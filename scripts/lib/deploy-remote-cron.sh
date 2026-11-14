#!/usr/bin/env bash
# Part of scripts/lib/deploy-remote.sh (see it for what the remote part does):
# Loading a site and running the plugin's own WP-Cron events there.
# Only functions: sourced by deploy-remote.sh, or bundled with it by
# deploy-sites.sh, never run alone. Its variables are set in deploy-remote.sh.
#
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Marcus Quinn
# Additional terms (GPL-3.0 section 7(b)): ATTRIBUTION.txt
# Provenance: wpas-e4502af0f07e8a92. Copies, even of part, keep these lines.
# shellcheck disable=SC2034,SC2153 # globals are shared across deploy-remote*.sh, which shellcheck reads one file at a time

# The scheduled events of one site that belong to the plugin: hooks in the
# site's cron array with a callback defined in the plugin's folder. Prints
# one "cronhook:NAME" line each. It needs no hook prefix. Running a hook runs
# all its callbacks, so a shared hook also runs core and other-plugin
# callbacks, and a failure in one of them counts as this plugin's. Callbacks
# registered only while WP-Cron runs (DOING_CRON) are not seen here. A name
# with a control character (it would break the line) or a leading "-" (WP-CLI
# would read it as an option) is left out.
cron_list_code() {
	cat <<'PHP'
$base = realpath(WP_PLUGIN_DIR . "/" . getenv("DEPLOY_SLUG"));
if (false === $base) {
    return;
}
$dir = rtrim(wp_normalize_path($base), "/") . "/";
$seen = array();
foreach ((array) _get_cron_array() as $events) {
    foreach ((array) $events as $hook => $unused) {
        $hook = (string) $hook;
        if (isset($seen[$hook]) || "" === $hook || "-" === $hook[0] || preg_match("/[\\x00-\\x1f\\x7f]/", $hook) || empty($GLOBALS["wp_filter"][$hook])) {
            continue;
        }
        foreach ($GLOBALS["wp_filter"][$hook]->callbacks as $callbacks) {
            foreach ($callbacks as $callback) {
                $fn = $callback["function"];
                try {
                    if (is_array($fn)) {
                        $ref = new ReflectionMethod($fn[0], $fn[1]);
                    } elseif (is_object($fn) && !($fn instanceof Closure)) {
                        $ref = new ReflectionMethod($fn, "__invoke");
                    } elseif (is_string($fn) && false !== strpos($fn, "::")) {
                        $parts = explode("::", $fn, 2);
                        $ref = new ReflectionMethod($parts[0], $parts[1]);
                    } else {
                        $ref = new ReflectionFunction($fn);
                    }
                } catch (Throwable $e) {
                    continue;
                }
                if (0 === strpos(wp_normalize_path((string) $ref->getFileName()), $dir)) {
                    $seen[$hook] = true;
                    echo "cronhook:" . $hook . "\n";
                    break 2;
                }
            }
        }
    }
}
PHP
	return 0
}

# Prints "HOOK<TAB>TIMESTAMP" for each of the site's hooks that has exactly
# one event, a one-off: the only events a killed run may retry. WP-CLI shows
# a one-off's recurrence as "Non-repeating", and its timestamp field is the
# Unix time it is due. A hook with two events is left out: a run takes the
# hook's next one, so the list cannot tell which one was killed. Returns 1,
# printing nothing, when the list cannot be read, so no killed hook is
# retried. Read, then filter: as a library, pipefail may be off.
cron_lone_oneoffs() {
	local root="$1"
	shift
	local events
	events="$("$WP_CLI" --path="$root" "$@" cron event list --fields=hook,recurrence,timestamp --format=csv 2>/dev/null)" || return 1
	printf '%s\n' "$events" | awk '
		NR > 1 && split($0, field, ",") >= 3 && field[1] != "" {
			n[field[1]]++
			stamp[field[1]] = field[3]
			if (field[2] != "Non-repeating" || field[3] !~ /^[0-9]+$/) skip[field[1]] = 1
		}
		END { for (h in n) if (n[h] == 1 && !(h in skip)) print h "\t" stamp[h] }'
	return 0
}

# Whether the site still lists HOOK's event due at TIMESTAMP ($2, $3 after
# the root): the same one-off, not one its callback scheduled before it was
# killed. 1 when the list cannot be read.
cron_event_listed() {
	local root="$1" hook="$2" stamp="$3"
	shift 3
	local events
	events="$("$WP_CLI" --path="$root" "$@" cron event list --fields=hook,timestamp --format=csv 2>/dev/null)" || return 1
	if printf '%s\n' "$events" | HOOK="$hook" STAMP="$stamp" awk '
		NR > 1 && split($0, field, ",") >= 2 && field[1] == ENVIRON["HOOK"] && field[2] == ENVIRON["STAMP"] { found = 1 }
		END { exit !found }'; then
		return 0
	fi
	return 1
}

# Runs the plugin's own scheduled events once on one site, each in its own
# WP-CLI process (a fatal error ends one process, not the count). A fatal
# error that only a cron callback reaches never shows in the full load, the
# home fetch or the web PHP log: the host's cron job runs WP-Cron from the
# command line. Running an event early reschedules it, as wp cron event run
# does by hand. An event gets DEPLOY_CRON_TIMEOUT seconds (default 120, 0 for
# no limit); one that times out is a warning, not a failure. A single event
# the site's own cron ran between the list and its run here (WP-CLI: Invalid
# cron event) is a note, not a failure, and not counted as run here (GH#1369).
# Sets CRON_RUN, CRON_TOTAL, CRON_FAILURE and CRON_WARN for the site, and
# CRON_LIST_KILLED to 1 when the list was killed (137, nothing on stderr) on
# its retry too: then CRON_FAILURE is just CRON_LIST_FAILED.
run_site_cron() {
	local root="$1"
	shift
	local hooks hook out status limit="${DEPLOY_CRON_TIMEOUT:-120}" detail
	local cmd=()
	CRON_RUN=0 CRON_TOTAL=0 CRON_FAILURE="" CRON_WARN="" CRON_LIST_KILLED=0
	[[ "$limit" =~ ^[0-9]+$ ]] || limit=120
	local list_code list_out list_err list_status=0 retried="" list_failed="$CRON_LIST_FAILED"
	list_code="$(cron_list_code)"
	list_out="$(mktemp)" || {
		CRON_FAILURE="$list_failed"
		return 0
	}
	list_err="$(mktemp)" || {
		rm -f "$list_out"
		CRON_FAILURE="$list_failed"
		return 0
	}
	# In this shell, not in $(...), so WP_STDERR_EMPTY reaches the retry
	# test: on failure wp_checked copies stdout to stderr, so a non-empty
	# list_err does not mean WP-CLI wrote to stderr.
	DEPLOY_SLUG="$SLUG" wp_checked "$root" "$@" eval "$list_code" >"$list_out" 2>"$list_err" || list_status=$?
	# A bare SIGKILL (137, nothing on stderr) is retried once, as the load check is.
	if [[ "$list_status" -eq 137 && "$WP_STDERR_EMPTY" -eq 1 ]]; then
		retried=137 list_status=0
		sleep "$LOAD_RETRY_DELAY"
		DEPLOY_SLUG="$SLUG" wp_checked "$root" "$@" eval "$list_code" >"$list_out" 2>"$list_err" || list_status=$?
	fi
	hooks="$(cat "$list_out")"
	rm -f "$list_out"
	if [[ "$list_status" -ne 0 ]]; then
		[[ ! -s "$list_err" ]] || cat "$list_err" >&2
		rm -f "$list_err"
		CRON_FAILURE="$list_failed"
		# Killed again, as bare as the first time: the host's limit, not the
		# plugin (GH#750).
		[[ -z "$retried" || "$list_status" -ne 137 || "$WP_STDERR_EMPTY" -ne 1 ]] || CRON_LIST_KILLED=1
		return 0
	fi
	rm -f "$list_err"
	[[ -z "$retried" ]] || CRON_WARN+="cron list retried ($retried), "
	hooks="$(printf '%s\n' "$hooks" | sed -n 's/^cronhook://p')"
	# The time limit needs timeout, but only when there is an event to run.
	[[ -n "$hooks" ]] || return 0
	if [[ "$limit" -gt 0 ]] && command -v timeout >/dev/null 2>&1; then
		cmd=(timeout "$limit")
	elif [[ "$limit" -gt 0 ]]; then
		CRON_TOTAL="$(printf '%s\n' "$hooks" | grep -c .)"
		CRON_FAILURE="cron events not run: timeout is not installed on this host (set DEPLOY_CRON_TIMEOUT=0 for no limit); "
		return 0
	fi
	# Read before the first run: a run changes the list.
	local retryable=""
	retryable="$(cron_lone_oneoffs "$root" "$@")" || retryable=""
	while IFS= read -r hook; do
		[[ -n "$hook" ]] || continue
		CRON_TOTAL=$((CRON_TOTAL + 1))
		status=0
		out="$("${cmd[@]+"${cmd[@]}"}" "$WP_CLI" --path="$root" "$@" cron event run "$hook" 2>&1)" || status=$?
		# A killed event (137) is run again, up to 3 tries in all, but only a
		# hook's lone one-off still listed with the same timestamp: WP-CLI
		# removes a one-off before its callback and reschedules a recurring
		# event before it, so a retry of either runs the next occurrence early
		# or a callback twice. The same hook at another time is a successor
		# the callback scheduled before it was killed (a
		# wp_schedule_single_event() chain): not retried either. Any other
		# final 137 stays a failure, even for a one-off no longer listed.
		local tries=1 stamp=""
		stamp="$(printf '%s\n' "$retryable" | HOOK="$hook" awk 'split($0, field, "\t") >= 2 && field[1] == ENVIRON["HOOK"] { print field[2]; exit }')"
		while [[ "$status" -eq 137 && "$tries" -lt 3 ]]; do
			[[ -n "$stamp" ]] || break
			cron_event_listed "$root" "$hook" "$stamp" "$@" || break
			tries=$((tries + 1))
			sleep "$LOAD_RETRY_DELAY"
			status=0
			out="$("${cmd[@]+"${cmd[@]}"}" "$WP_CLI" --path="$root" "$@" cron event run "$hook" 2>&1)" || status=$?
		done
		if [[ "$status" -eq 137 && -z "$out" ]]; then
			out="cron $hook killed (137)"
		fi
		[[ "$tries" -eq 1 ]] || CRON_WARN+="cron $hook retried (137), "
		if [[ "$status" -eq 124 && "${#cmd[@]}" -gt 0 ]]; then
			CRON_WARN+="cron $hook timed out (${limit}s), "
			CRON_RUN=$((CRON_RUN + 1))
		elif [[ "$status" -ne 0 && "$out" == *"Invalid cron event '$hook'"* && "$out" != *"Fatal error"* && "$out" != *"$DB_QUERY_ERROR"* && "$out" != *"$DB_CONNECT_ERROR"* ]]; then
			CRON_WARN+="cron $hook ran meanwhile, "
		elif [[ "$status" -ne 0 || "$out" == *"PHP Fatal error"* || "$out" == *"Fatal error:"* || "$out" == *"$DB_QUERY_ERROR"* || "$out" == *"$DB_CONNECT_ERROR"* ]]; then
			detail="$(printf '%s\n' "$out" | tail -n 3 | LC_ALL=C tr '\t\r\n' '   ' | LC_ALL=C tr -cd '[:print:]')"
			CRON_FAILURE+="cron $hook failed (exit $status: ${detail:0:300}); "
		else
			CRON_RUN=$((CRON_RUN + 1))
			# Only a hook that ran to completion can have raced with the site's cron.
			CRON_HOOKS_RUN+="$hook "
		fi
	done <<<"$hooks"
	return 0
}
