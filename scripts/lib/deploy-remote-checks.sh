#!/usr/bin/env bash
# Part of scripts/lib/deploy-remote.sh (see it for what the remote part does):
# Home and CDN checks, the load check and the per-site steps.
# Only functions: sourced by deploy-remote.sh, or bundled with it by
# deploy-sites.sh, never run alone. Its variables are set in deploy-remote.sh.
#
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Marcus Quinn
# Additional terms (GPL-3.0 section 7(b)): ATTRIBUTION.txt
# Provenance: wpas-e4502af0f07e8a92. Copies, even of part, keep these lines.
# shellcheck disable=SC2034,SC2153 # globals are shared across deploy-remote*.sh, which shellcheck reads one file at a time

# Prints the origin server's IPv4 address for the site: LiteSpeed Cache's
# Server IP, or else an address the plugin learned from a web request and
# stored as array('ip' => ...) in its wpstarter_origin_ip option (a plugin
# without such a feature has none). Prints nothing when neither is set or
# valid. A host behind a CDN can refuse its own uncached fetch
# that loops back through the CDN, so the home fetch goes to the origin.
origin_ip() {
	local root="$1"
	shift
	local ip
	# shellcheck disable=SC2016 # PHP code, not shell.
	ip="$(wp_bare "$root" "$@" eval '$ip = trim((string) get_option("litespeed.conf.server_ip", "")); if ("" === $ip) { $learned = get_option("wpstarter_origin_ip", array()); $ip = is_array($learned) && isset($learned["ip"]) ? trim((string) $learned["ip"]) : ""; } echo "originip:" . $ip;' 2>/dev/null)" || return 0
	ip="${ip##*originip:}"
	if [[ "$ip" =~ ^[0-9]{1,3}(\.[0-9]{1,3}){3}$ ]]; then
		printf '%s\n' "$ip"
	fi
	return 0
}

# Sets HOME_CODE/HOME_CACHE/HOME_PINNED and advances FETCHES in the caller's
# shell. With an origin IP as the second argument the fetch is pinned to it
# (curl --resolve); a pinned fetch that does not connect falls back to DNS.
home_check() {
	local url="$1"
	local ip="${2:-}"
	local headers fetch result final_url final_host rc=0 scheme host port
	local pin=()
	FETCHES=$((FETCHES + 1))
	HOME_CODE="000"
	HOME_CACHE="none"
	HOME_PINNED=""
	fetch="deploy-check=${RUN_STAMP}-${FETCHES}"
	headers="$(mktemp)" || return 1
	if [[ -n "$ip" ]]; then
		scheme="${url%%://*}"
		host="${url#*://}"
		host="${host%%/*}"
		port=443
		[[ "$scheme" != "http" ]] || port=80
		if [[ "$host" == *:* ]]; then
			port="${host##*:}"
			host="${host%:*}"
		fi
		# Both web ports too, so a redirect to the other scheme on the same
		# host (http to https) still reaches the origin.
		pin=(--resolve "${host}:${port}:${ip}" --resolve "${host}:80:${ip}" --resolve "${host}:443:${ip}")
		HOME_PINNED=1
	fi
	result="$(curl -s -o /dev/null -L -D "$headers" -w '%{http_code} %{url_effective}' --max-time 30 \
		${pin[@]+"${pin[@]}"} "${url%/}/?${fetch}")" || rc=$?
	if [[ "$rc" -ne 0 && -n "$HOME_PINNED" ]]; then
		# The pinned address did not answer: use DNS, with the 4xx rule.
		HOME_PINNED=""
		rc=0
		result="$(curl -s -o /dev/null -L -D "$headers" -w '%{http_code} %{url_effective}' --max-time 30 \
			"${url%/}/?${fetch}")" || rc=$?
	fi
	HOME_CODE="${result%% *}"
	# A fetch curl did not finish (timeout, reset) is no answer, even when
	# the headers said 200.
	[[ "$rc" -eq 0 ]] || HOME_CODE="000"
	final_url="${result#* }"
	HOME_CACHE="$(awk '
		/^HTTP\// { cache = "" }
		{
			line = tolower($0)
			sub(/\r$/, "", line)
			if (line ~ /^(x-litespeed-cache|x-cache|cf-cache-status):/) {
				sub(/:[ \t]*/, ":", line)
				sub(/[ \t]+$/, "", line)
				cache = cache (cache == "" ? "" : ",") line
			}
		}
		END { print (cache == "" ? "none" : cache) }
	' "$headers")"
	if [[ "$final_url" != *"?$fetch" && "$final_url" != *"?$fetch&"* && "$final_url" != *"&$fetch" && "$final_url" != *"&$fetch&"* ]]; then
		final_host="${final_url#*://}"
		final_host="${final_host%%/*}"
		final_host="${final_host##*@}"
		HOME_CACHE="redirected:${final_host:-unknown}"
	fi
	# A redirect to another host was fetched through DNS, not the origin.
	if [[ -n "$HOME_PINNED" && -n "$host" ]]; then
		final_host="${final_url#*://}"
		final_host="${final_host%%/*}"
		final_host="${final_host##*@}"
		final_host="${final_host%%:*}"
		[[ "$final_host" == "$host" ]] || HOME_PINNED=""
	fi
	rm -f "$headers"
	return 0
}

# The plain home address (no query string, through DNS and so through any
# CDN) once, after the install. Sets CF_STALE to the page's age in seconds
# when Cloudflare answers HIT with a page older than the install began: it
# still serves the pages from before the deploy. Sets it to "" otherwise.
cf_stale_check() {
	local url="$1"
	local headers rc=0 found cache age now
	CF_STALE=""
	headers="$(mktemp)" || return 0
	curl -s -o /dev/null -D "$headers" --max-time 30 "${url%/}/" || rc=$?
	if [[ "$rc" -eq 0 ]]; then
		found="$(awk '
			/^HTTP\// { cache = "-"; age = "-" }
			{
				line = tolower($0)
				sub(/\r$/, "", line)
				if (line ~ /^cf-cache-status:/) { sub(/^[^:]*:[ \t]*/, "", line); cache = line }
				if (line ~ /^age:/) { sub(/^[^:]*:[ \t]*/, "", line); age = line }
			}
			END { print cache, age }
		' "$headers")"
		cache="${found%% *}"
		age="${found#* }"
		now="$(date +%s)"
		if [[ "$cache" == hit && "$age" =~ ^[0-9]+$ && "$INSTALL_START" -gt 0 && "$age" -gt $((now - INSTALL_START)) ]]; then
			CF_STALE="$age"
		fi
	fi
	rm -f "$headers"
	return 0
}

cf_warning() {
	local age="$1"
	printf 'Cloudflare keeps pages from before the deploy (age=%s s); purge the zone or pass --cloudflare-token-env' "$age"
	return 0
}

# One "@cdn<TAB>URL" line per address on stdin: names the sites for
# deploy-sites.sh, which works out their Cloudflare zones from the host names.
cdn_lines() {
	local url
	while IFS= read -r url; do
		[[ -z "$url" ]] || printf '@cdn\t%s\n' "$url"
	done
	return 0
}

# The plugin's own scheduled events, once, on one site after a good load. A
# cron callback must not change the activation lists either. Sets the CRON_*
# results and adds to the CRON_SUM_* totals.
cron_step() {
	local root="$1"
	shift
	local cron_before
	if cron_before="$(active_snapshot "$root")"; then
		run_site_cron "$root" "$@"
		active_check "$root" "$cron_before" "" "" || CRON_FAILURE+="activation lists changed during cron; "
	else
		CRON_RUN=0 CRON_TOTAL=0 CRON_WARN="" CRON_LIST_KILLED=0 CRON_KILLED=""
		CRON_FAILURE="cron skipped: activation snapshot failed; "
	fi
	CRON_SUM_RUN=$((CRON_SUM_RUN + CRON_RUN))
	CRON_SUM_TOTAL=$((CRON_SUM_TOTAL + CRON_TOTAL))
	return 0
}

# Notes one site's address for the Cloudflare purge; without a token, checks
# the plain home address. Sets CDN_WARN to the warning (with its separator)
# or "", and MAIN_CF for the first site.
cdn_step() {
	local url="$1"
	CDN_URLS+="$url"$'\n'
	CDN_WARN=""
	[[ "$CDN_PURGE" -eq 0 ]] || return 0
	cf_stale_check "$url"
	[[ -n "$CF_STALE" ]] || return 0
	CDN_WARN="$(cf_warning "$CF_STALE"), "
	[[ "$SITES_TOTAL" -ne 1 ]] || MAIN_CF="$CF_STALE"
	return 0
}

# Prints the @cdn lines of the install and sets CDN_FIELD, the cdn= value.
cdn_announce() {
	CDN_FIELD="-"
	[[ "$CDN_PURGE" -eq 1 ]] || return 0
	CDN_FIELD="@CDN@"
	printf '%s' "$CDN_URLS" | cdn_lines
	return 0
}

# Waits, at most 10 minutes, while the account runs more than
# DEPLOY_MAX_ACCOUNT_PROCS processes (unset or not a number: no wait), so a
# host at its process limit does not kill the install's checks.
wait_for_account_load() {
	local max="${DEPLOY_MAX_ACCOUNT_PROCS:-}" count waited=0
	[[ "$max" =~ ^[0-9]+$ ]] || return 0
	command -v pgrep >/dev/null 2>&1 || return 0
	while [[ "$waited" -lt 600 ]]; do
		count="$(pgrep -u "$(id -u)" | wc -l | tr -d ' ')"
		[[ "$count" =~ ^[0-9]+$ && "$count" -gt "$max" ]] || return 0
		sleep 10
		waited=$((waited + 10))
	done
	return 0
}

# The load check: $1 root, $2 stderr file, rest WP-CLI args. Sets LOAD_OUT,
# LOAD_STATUS and LOAD_RETRIED. Only a SIGKILL (137), whatever stderr holds,
# after which the activation lists were found intact, is retried, once,
# after LOAD_RETRY_DELAY: an activation failure stays FAIL.
load_check() {
	local root="$1" errors="$2"
	shift 2
	LOAD_STATUS=0 LOAD_RETRIED="" LOAD_OUT="" GUARD_ACTIVE_OK=0
	local out_file
	out_file="$(mktemp)" || {
		LOAD_STATUS=1
		return 0
	}
	# active_guard runs in this shell, not in $(...), so its GUARD_* flags
	# reach the retry test below; stdout goes through a private file.
	active_guard "$root" "" "" "$@" eval "$(load_code)" >"$out_file" 2>"$errors" || LOAD_STATUS=$?
	if [[ "$LOAD_STATUS" -eq 137 && "$GUARD_ACTIVE_OK" -eq 1 ]]; then
		LOAD_RETRIED=137 LOAD_STATUS=0
		sleep "$LOAD_RETRY_DELAY"
		active_guard "$root" "" "" "$@" eval "$(load_code)" >"$out_file" 2>"$errors" || LOAD_STATUS=$?
	fi
	LOAD_OUT="$(cat "$out_file")"
	rm -f "$out_file"
	return 0
}

# The plugin's own scheduled events on one site, after a good load (cron_step).
# Adds to STEP_REASON and STEP_WARN; sets STEP_CRON (cron=N/M) and STEP_KILLED
# to cron when only the cron list was killed twice (GH#750), or to cronevent,
# with STEP_HOOKS the killed hooks, when events were killed (137) and nothing
# else is wrong (GH#771).
site_cron() {
	local root="$1"
	shift
	cron_step "$root" "$@"
	STEP_CRON="cron=${CRON_RUN}/${CRON_TOTAL}"
	if [[ "$CRON_LIST_KILLED" -eq 1 && "$CRON_FAILURE" == "$CRON_LIST_FAILED" ]]; then
		STEP_KILLED="cron"
	else
		STEP_REASON+="$CRON_FAILURE"
		if [[ -n "$CRON_KILLED" ]]; then
			STEP_KILLED="$KILLED_EVENT" STEP_HOOKS="$CRON_KILLED"
		fi
	fi
	if [[ -n "$CRON_WARN" ]]; then
		STEP_WARN+="$CRON_WARN"
		CRON_WARNED+="$CRON_WARN"
	fi
	return 0
}

# The end-of-run recheck of a site whose cron events the host killed (137):
# $1 root, $2 stderr file, $3 the killed hooks ("HOOK HOOK "), rest WP-CLI
# args. Runs the load check and the cron list only, never the hooks again
# (a run reschedules a recurring event early). A hook still scheduled is a
# warning; one no longer listed (a one-off WP-CLI removed before its callback)
# cannot be confirmed, so it stays killed. Sets STEP_REASON, STEP_WARN,
# STEP_KILLED and STEP_HOOKS like site_load (GH#771).
recheck_cron_events() {
	local root="$1" errors="$2" hooks="$3"
	shift 3
	local events="" status=0 hook missing="" summary
	local hook_list=()
	STEP_HOOKS=""
	load_check "$root" "$errors" "$@"
	if [[ "$LOAD_STATUS" -eq 0 ]]; then
		[[ -z "$LOAD_RETRIED" ]] || STEP_WARN+="load retried ($LOAD_RETRIED), "
	elif [[ "$LOAD_STATUS" -eq 137 && "$LOAD_RETRIED" == 137 && "$GUARD_ACTIVE_OK" -eq 1 ]]; then
		STEP_KILLED="load"
		return 0
	else
		summary="$(tail -n 3 "$errors" | LC_ALL=C tr '\t\r\n' '   ' | LC_ALL=C tr -cd '[:print:]')"
		STEP_REASON="WordPress load failed (exit $LOAD_STATUS"
		[[ -z "$summary" ]] || STEP_REASON+=": ${summary:0:300}"
		STEP_REASON+="); "
		return 0
	fi
	events="$("$WP_CLI" --path="$root" "$@" cron event list --fields=hook --format=csv 2>"$errors")" || status=$?
	if [[ "$status" -eq 137 ]] && ! grep -qiE 'fatal error|error establishing a database|database error' "$errors"; then
		status=0
		sleep "$LOAD_RETRY_DELAY"
		events="$("$WP_CLI" --path="$root" "$@" cron event list --fields=hook --format=csv 2>"$errors")" || status=$?
	fi
	if [[ "$status" -eq 137 ]] && grep -qiE 'fatal error|error establishing a database|database error' "$errors"; then
		summary="$(tail -n 3 "$errors" | LC_ALL=C tr '\t\r\n' '   ' | LC_ALL=C tr -cd '[:print:]')"
		STEP_REASON+="cron list failed (exit 137: ${summary:0:300}); "
		return 0
	elif [[ "$status" -eq 137 ]]; then
		STEP_KILLED="$KILLED_EVENT" STEP_HOOKS="$hooks"
		return 0
	elif [[ "$status" -ne 0 ]]; then
		STEP_REASON+="$CRON_LIST_FAILED"
		return 0
	fi
	read -ra hook_list <<<"$hooks"
	for hook in ${hook_list[@]+"${hook_list[@]}"}; do
		if printf '%s\n' "$events" | HOOK="$hook" awk 'NR > 1 && $0 == ENVIRON["HOOK"] { found = 1 } END { exit !found }'; then
			STEP_WARN+="cron $hook killed by host (137), still scheduled, "
			CRON_WARNED+="cron $hook killed by host (137), still scheduled, "
		else
			missing+="$hook "
		fi
	done
	if [[ -n "$missing" ]]; then
		STEP_KILLED="$KILLED_EVENT" STEP_HOOKS="$missing"
	fi
	return 0
}

# The guarded full load of one site (load_check), then, after a good load, the
# plugin's own scheduled events (site_cron): $1 root, $2 stderr file, rest
# WP-CLI args. Sets STEP_REASON (failures, with "; "), STEP_WARN (with ", "),
# STEP_PURGED, STEP_CRON, STEP_LOAD_RETRIED and STEP_KILLED (load when the
# load was killed twice with the activation lists intact, cron as above, else
# empty), and adds to SITES_PURGED and PURGE_FAILED.
site_load() {
	local root="$1" errors="$2"
	shift 2
	local summary
	STEP_REASON="" STEP_WARN="" STEP_PURGED="no" STEP_CRON="cron=0/0" STEP_LOAD_RETRIED="" STEP_KILLED="" STEP_HOOKS=""
	CRON_RUN=0 CRON_TOTAL=0
	load_check "$root" "$errors" "$@"
	if [[ "$LOAD_STATUS" -eq 0 ]]; then
		STEP_LOAD_RETRIED="$LOAD_RETRIED"
		[[ -z "$LOAD_RETRIED" ]] || STEP_WARN+="load retried ($LOAD_RETRIED), "
		case "$LOAD_OUT" in
		*purged=yes*)
			STEP_PURGED="yes"
			SITES_PURGED=$((SITES_PURGED + 1))
			;;
		*purged=failed*)
			STEP_PURGED="failed" STEP_WARN+="purge failed, "
			PURGE_FAILED=$((PURGE_FAILED + 1))
			;;
		*) ;;
		esac
		# A cron callback must not change the activation lists either.
		site_cron "$root" "$@"
	elif [[ "$LOAD_STATUS" -eq 137 && "$LOAD_RETRIED" == 137 && "$GUARD_ACTIVE_OK" -eq 1 ]]; then
		# Killed on the retry too, activation lists intact both times: the
		# host's process or memory limit, not the release (GH#750).
		STEP_KILLED="load"
	else
		# Keep the full diagnostics on stderr, but one short, printable
		# line on the report (also when WP-CLI itself printed no error).
		summary="$(tail -n 3 "$errors" | LC_ALL=C tr '\t\r\n' '   ' | LC_ALL=C tr -cd '[:print:]')"
		STEP_REASON="WordPress load failed (exit $LOAD_STATUS"
		[[ -z "$summary" ]] || STEP_REASON+=": ${summary:0:300}"
		STEP_REASON+="); "
	fi
	return 0
}
