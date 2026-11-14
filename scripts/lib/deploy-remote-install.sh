#!/usr/bin/env bash
# Part of scripts/lib/deploy-remote.sh (see it for what the remote part does):
# Swapping the plugin folder in, installing, reporting and the recheck of killed sites.
# Only functions: sourced by deploy-remote.sh, or bundled with it by
# deploy-sites.sh, never run alone. Its variables are set in deploy-remote.sh.
#
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Marcus Quinn
# Additional terms (GPL-3.0 section 7(b)): ATTRIBUTION.txt
# Provenance: wpas-e4502af0f07e8a92. Copies, even of part, keep these lines.
# shellcheck disable=SC2034,SC2153 # globals are shared across deploy-remote*.sh, which shellcheck reads one file at a time

# Put back the INT/TERM/HUP handlers saved with trap -p (empty: defaults).
swap_restore_traps() {
	local saved="$1"
	trap - INT TERM HUP
	[[ -z "$saved" ]] || eval "$saved"
	return 0
}

# Replace $plugins/$SLUG with the folder in the zip using two rename() calls
# inside the plugins folder (same filesystem, so each is atomic). Returns 1
# with the live folder untouched if anything fails before the first rename;
# if the second rename fails the old folder is put back.
#
# The release zip gives every file the same fixed time (reproducible builds)
# and unzip keeps it, but PHP's OPcache revalidates a file only when its time
# changes: the web server would go on running the old version's code, and
# assets versioned by file time would keep their old addresses. So the
# extracted files get the current time first, as WordPress's own updater
# gives them.
swap_plugin_folder() {
	local plugins="$1"
	local zip="$2"
	local stamp staging old prev_traps
	stamp="$(date +%s)-$$"
	staging="$plugins/.$SLUG-new-$stamp"
	old="$plugins/.$SLUG-old-$stamp"

	command -v unzip >/dev/null 2>&1 || return 1
	mkdir "$staging" || return 1
	# umask 022: the web server's account must be able to read what unzip makes.
	if ! (umask 022 && unzip -q "$zip" -d "$staging") || [[ ! -f "$staging/$SLUG/$SLUG.php" ]] \
		|| ! find "$staging/$SLUG" -exec touch -c {} +; then
		rm -rf "$staging"
		return 1
	fi
	# A signal between the two renames would leave the plugin only in $old:
	# put it back before exiting.
	# Single quotes: paths expand when the trap runs, so any character is safe.
	prev_traps="$(trap -p INT TERM HUP)"
	trap '[[ -d "$plugins/$SLUG" ]] || mv "$old" "$plugins/$SLUG"; rm -rf "$staging"; exit 143' INT TERM HUP
	if ! mv "$plugins/$SLUG" "$old"; then
		swap_restore_traps "$prev_traps"
		rm -rf "$staging"
		return 1
	fi
	# Refuse to move into a destination another writer recreated (mv would nest
	# the release inside it): roll back and keep the old copy.
	if [[ -e "$plugins/$SLUG" ]] || ! mv "$staging/$SLUG" "$plugins/$SLUG"; then
		if [[ -e "$plugins/$SLUG" ]] || ! mv "$old" "$plugins/$SLUG"; then
			swap_restore_traps "$prev_traps"
			printf '%s\tFAIL: folder swap and rollback failed; old copy kept at %s\n' "$SLUG" "$old" >&2
			return 2
		fi
		swap_restore_traps "$prev_traps"
		rm -rf "$staging"
		return 1
	fi
	swap_restore_traps "$prev_traps"
	rm -rf "$staging"
	if ! rm -rf "$old"; then
		printf '%s\tWARN: could not remove old folder %s\n' "$SLUG" "$old" >&2
	fi
	return 0
}

# Swap by two renames so running jobs never find the folder missing.
# Activation (and network activation) is kept: the folder and main file
# names do not change. If the swap cannot be made (no unzip, a different
# filesystem, an odd zip), nothing has changed and install --force runs.
install_build() {
	local root="$1"
	local name="$2"
	local zip="$3"
	local plugins="$4"
	local backup="$5"

	local swap_rc=0
	swap_plugin_folder "$plugins" "$zip" || swap_rc=$?
	[[ "$swap_rc" -eq 0 ]] && return 0
	if [[ "$swap_rc" -eq 2 ]]; then
		printf '%s\tFAIL: folder swap rollback failed; restore: tar -xzf %q -C %q\n' "$name" "$backup" "$plugins"
		return 1
	fi
	printf '%s\tWARN: folder swap failed; using wp plugin install --force\n' "$name" >&2
	if ! active_guard "$root" "" "" --skip-plugins --skip-themes plugin install "$zip" --force >/dev/null; then
		printf '%s\tFAIL: guarded install stopped; restore: tar -xzf %q -C %q\n' "$name" "$backup" "$plugins"
		return 1
	fi
	return 0
}

apply_one() {
	local root="$1"
	local name="$2"
	local want="$3"
	local zip="$4"
	local backups="$5"
	local plugins="$root/wp-content/plugins"
	local main="$plugins/$SLUG/$SLUG.php"
	local before backup
	local comparison=0

	before="$(plugin_version "$main")"
	if [[ "$ALLOW_DOWNGRADE" -eq 0 ]]; then
		newer_than "$before" "$want" || comparison=$?
		case "$comparison" in
		0)
			printf '%s\tFAIL: has %s, newer than %s; not installed (--allow-downgrade to install anyway)\n' "$name" "$before" "$want"
			FAILED=1
			return 0
			;;
		1) ;;
		*)
			printf '%s\tFAIL: cannot compare versions (has %s); not installed (--allow-downgrade to install anyway)\n' "$name" "${before:-no readable Version}"
			FAILED=1
			return 0
			;;
		esac
	fi
	backup="$backups/$SLUG-$name-${before:-unknown}.tar.gz"
	if ! tar -czf "$backup" -C "$plugins" "$SLUG"; then
		printf '%s\tFAIL: could not back up %s; not installed\n' "$name" "$plugins/$SLUG"
		FAILED=1
		return 0
	fi
	chmod 600 "$backup"
	# A wrong web PHP log path fails before the account-load wait. The log
	# baseline is taken after it, just before the install, so lines the site
	# logs during the wait are not counted as the install's.
	if ! web_log_usable "$root" || ! wait_for_account_load || ! log_files "$root"; then
		printf '%s\tFAIL: cannot check the web PHP log; not installed\n' "$name"
		FAILED=1
		return 0
	fi

	INSTALL_START="$(date +%s)"
	if ! install_build "$root" "$name" "$zip" "$plugins" "$backup"; then
		FAILED=1
		return 0
	fi
	# Each site's guarded full load runs its own settings upgrade.
	if ! check_sites "$root"; then
		printf '%s\tFAIL: cannot list the sites; restore: tar -xzf %q -C %q\n' "$name" "$backup" "$plugins"
		FAILED=1
		return 0
	fi

	R_ROOT="$root" R_NAME="$name" R_BEFORE="$before" R_WANT="$want" R_BACKUP="$backup" R_PLUGINS="$plugins"
	R_AFTER="$(plugin_version "$main")"
	classify_new_log
	R_NEW_LINES="$LOG_NEW_LINES" R_LOG_WARN="$LOG_WARN" R_LOG_FAIL="$LOG_FAIL" R_LOG_TEXT=""
	# Read now: the next install's log_files replaces the log list. Ignored
	# lines are shown too, so nothing is hidden.
	[[ "$R_NEW_LINES" -eq 0 && "$LOG_IGNORED" -eq 0 ]] || R_LOG_TEXT="$(new_log_text)"
	# Nothing failed, but the host killed a check twice: report it after
	# the recheck at the end of the run (GH#750). Its Cloudflare purge (the
	# @cdn lines) waits too, so it follows the recheck's page-cache purge.
	if [[ "$SITES_UNVERIFIED" -gt 0 ]] && ! install_failed; then
		DEFERRED+=("$(install_state)")
		printf '    %s: %s on %s site(s); rechecked at the end of the run\n' "$name" "$KILLED_TEXT" "$SITES_UNVERIFIED"
		return 0
	fi
	install_report
	return 0
}

# Whether the install in the R_* and check_sites results failed: a version
# not reached, new log lines that count or a failed site.
install_failed() {
	if [[ "$R_AFTER" != "$R_WANT" || ("$R_NEW_LINES" -gt 0 && "$R_LOG_FAIL" -eq 1) || "$SITES_FAILED" -gt 0 ]]; then
		return 0
	fi
	return 1
}

# The install line from the R_* and check_sites results, then its site rows,
# recheck hints, new log lines and restore command. FAIL (exit 1) beats
# UNVERIFIED (exit 4, no restore), which beats WARN and ok.
install_report() {
	local result="ok" warn="" record
	# Single sites have no site row on which to show these warnings.
	[[ -z "$MAIN_RECHECKED" || -n "$SITE_LINES" ]] || warn+="$MAIN_RECHECKED, "
	warn+="$R_LOG_WARN"
	[[ "$PURGE_FAILED" -eq 0 ]] || warn+="purge failed, "
	[[ -z "$CRON_WARNED" || -n "$SITE_LINES" ]] || warn+="$CRON_WARNED"
	[[ "$MAIN_CACHE" != *hit* || "$MAIN_CACHE" == redirected:* ]] || warn+="cached, "
	[[ -z "$MAIN_LOAD_RETRIED" || -n "$SITE_LINES" ]] || warn+="load retried ($MAIN_LOAD_RETRIED), "
	[[ -z "$MAIN_RETRIED" ]] || warn+="home retried ($MAIN_RETRIED), "
	# A network's site rows carry this warning; a single site has no row.
	[[ -z "$MAIN_CF" || -n "$SITE_LINES" ]] || warn+="$(cf_warning "$MAIN_CF"), "
	if install_failed; then
		result="FAIL"
		if [[ -z "$SITE_LINES" && -n "$MAIN_REASON" ]]; then
			result+=": $MAIN_REASON"
		elif [[ -z "$SITE_LINES" && -n "$MAIN_UNVERIFIED" ]]; then
			result+=": $MAIN_UNVERIFIED"
		fi
		FAILED=1
	elif [[ "$SITES_UNVERIFIED" -gt 0 ]]; then
		result="UNVERIFIED"
		[[ -n "$SITE_LINES" || -z "$MAIN_UNVERIFIED" ]] || result+=": $MAIN_UNVERIFIED"
		INSTALLS_UNVERIFIED=$((INSTALLS_UNVERIFIED + 1))
	else
		[[ -z "$warn" ]] || result="$(warn_result "$warn")"
		INSTALLS_OK=$((INSTALLS_OK + 1))
	fi
	UNVERIFIED_SITES=$((UNVERIFIED_SITES + SITES_UNVERIFIED))
	cdn_announce
	printf '%s\t%s -> %s\tstatus=%s\tpurged=%s/%s\tcron=%s/%s\thome=%s\tcache=%s\tcdn=%s\tnew_log_lines=%s' \
		"$R_NAME" "${R_BEFORE:-?}" "${R_AFTER:-?}" "$MAIN_STATUS" "$SITES_PURGED" "$SITES_TOTAL" "$CRON_SUM_RUN" "$CRON_SUM_TOTAL" "$MAIN_CODE" "$MAIN_CACHE" "$CDN_FIELD" "$R_NEW_LINES"
	if [[ -n "$SITE_LINES" ]]; then
		printf '\tsites=%s/%s' "$((SITES_TOTAL - SITES_FAILED - SITES_UNVERIFIED))" "$SITES_TOTAL"
	fi
	printf '\t%s\n' "$result"
	printf '%s' "$SITE_LINES"
	while IFS= read -r record; do
		[[ -z "$record" ]] || recheck_hint "$record"
	done <<<"$UNV_RECORDS"
	if [[ -n "$R_LOG_TEXT" ]]; then
		printf '%s\n' "$R_LOG_TEXT" | sed 's/^/    /'
	fi
	if [[ "$result" == FAIL* ]]; then
		printf '    restore: rm -rf %q && tar -xzf %q -C %q\n' "$R_PLUGINS/$SLUG" "$R_BACKUP" "$R_PLUGINS"
	fi
	return 0
}

# One unverified site's recheck command (an unverified_record in $1), to run
# by hand when the host is quieter: for a killed load, a plain full load
# (which runs the settings upgrade; not the activation guard); for a killed
# cron list, the list. Its scheduled events run on the site's own WP-Cron.
recheck_hint() {
	local record="$1"
	local kind url
	local cmd=("$WP_CLI" --path="$R_ROOT")
	IFS=$'\x1f' read -r kind url _ <<<"$record"
	[[ "$NETWORK" -eq 0 ]] || cmd+=(--url="$url")
	if [[ "$kind" == cron* ]]; then
		cmd+=(cron event list)
	else
		cmd+=(eval "$(load_code)")
	fi
	printf '    recheck:'
	printf ' %q' "${cmd[@]}"
	printf '\n'
	return 0
}

# The R_* and check_sites results of one install, as assignments for eval.
install_state() {
	local var
	for var in R_ROOT R_NAME R_BEFORE R_AFTER R_WANT R_BACKUP R_PLUGINS R_NEW_LINES R_LOG_TEXT R_LOG_WARN R_LOG_FAIL \
		NETWORK SITES_TOTAL SITES_FAILED SITES_PURGED PURGE_FAILED SITES_UNVERIFIED SITE_LINES UNV_RECORDS \
		CRON_SUM_RUN CRON_SUM_TOTAL CRON_WARNED CRON_HOOKS_RUN MAIN_STATUS MAIN_CODE MAIN_CACHE MAIN_REASON \
		MAIN_RETRIED MAIN_LOAD_RETRIED MAIN_CF MAIN_UNVERIFIED MAIN_RECHECKED CDN_URLS; do
		printf '%s=%q\n' "$var" "${!var}"
	done
	return 0
}

# Rechecks one held-back install (its install_state in $1), then reports it.
# Each site the host killed twice gets its killed step once more, with its
# own retry: the load (site_load, then its cron step) or the cron step alone
# (site_cron). A pass is WARN rechecked after host kill (137); killed again
# stays UNVERIFIED; any other failure is a FAIL, with the restore command.
recheck_install() {
	local state="$1"
	local record kind url status home cache purged cron_note warn hooks result old_row old_result records="" errors
	local url_args=()
	eval "$state"
	wait_for_account_load
	# The recheck's load and cron run can log too: a new baseline, as the
	# install's own (a shared --web-error-log has other installs' lines since).
	# Without one nothing is rechecked, so the sites stay UNVERIFIED.
	if ! log_files "$R_ROOT"; then
		printf '    %s: cannot read the PHP logs for the recheck; not rechecked\n' "$R_NAME"
		install_report
		return 0
	fi
	errors="$(mktemp)" || errors=/dev/null
	while IFS= read -r record; do
		[[ -n "$record" ]] || continue
		IFS=$'\x1f' read -r kind url status home cache purged cron_note warn hooks <<<"$record"
		url_args=()
		[[ "$NETWORK" -eq 0 ]] || url_args=(--url="$url")
		old_result="$(killed_result "$kind" "$hooks")"
		site_row "$url" "$status" "$purged" "$cron_note" "$home" "$cache" "$old_result"
		old_row="$ROW"
		SITES_UNVERIFIED=$((SITES_UNVERIFIED - 1))
		STEP_REASON="" STEP_WARN="" STEP_KILLED="" STEP_HOOKS="" STEP_LOAD_RETRIED="" STEP_CRON="$cron_note"
		if [[ "$kind" == load ]]; then
			site_load "$R_ROOT" "$errors" ${url_args[@]+"${url_args[@]}"}
			purged="$STEP_PURGED"
			cat "$errors" >&2
		elif [[ "$kind" == cronevent ]]; then
			recheck_cron_events "$R_ROOT" "$errors" "$hooks" ${url_args[@]+"${url_args[@]}"}
			cat "$errors" >&2
		else
			site_cron "$R_ROOT" ${url_args[@]+"${url_args[@]}"}
		fi
		cron_note="$STEP_CRON"
		warn+="$STEP_WARN"
		if [[ -n "$STEP_REASON" ]]; then
			result="FAIL: ${STEP_REASON%; }"
			SITES_FAILED=$((SITES_FAILED + 1))
			[[ "$NETWORK" -eq 1 ]] || MAIN_REASON="${STEP_REASON%; }"
		elif [[ -n "$STEP_KILLED" ]]; then
			result="$(killed_result "$STEP_KILLED" "$STEP_HOOKS")"
			SITES_UNVERIFIED=$((SITES_UNVERIFIED + 1))
			records+="$(unverified_record "$STEP_KILLED" "$url" "$status" "$home" "$cache" "$purged" "$cron_note" "$warn" "$STEP_HOOKS")"$'\n'
			[[ "$NETWORK" -eq 1 ]] || MAIN_UNVERIFIED="${result#UNVERIFIED: }"
		else
			warn="$RECHECKED_TEXT, $warn"
			result="$(warn_result "$warn")"
			[[ "$NETWORK" -eq 1 ]] || MAIN_RECHECKED="$RECHECKED_TEXT" MAIN_UNVERIFIED=""
		fi
		[[ "$NETWORK" -eq 1 || -z "$STEP_LOAD_RETRIED" ]] || MAIN_LOAD_RETRIED="$STEP_LOAD_RETRIED"
		if [[ "$NETWORK" -eq 1 ]]; then
			site_row "$url" "$status" "$purged" "$cron_note" "$home" "$cache" "$result"
			# The x keeps the rows' last newline through $(...).
			SITE_LINES="$(
				replace_text "$SITE_LINES" "$old_row" "$ROW"
				printf x
			)"
			SITE_LINES="${SITE_LINES%x}"
		fi
	done <<<"$UNV_RECORDS"
	UNV_RECORDS="$records"
	[[ "$errors" == /dev/null ]] || rm -f "$errors"
	recheck_log
	install_report
	return 0
}

# Adds the lines the logs gained during the recheck to the install's R_LOG_*.
# A held-back install had no new lines that fail it, so lines that fail it
# now (any but cron-save contention) decide R_LOG_FAIL. Ignored lines are
# shown but leave R_LOG_FAIL alone.
recheck_log() {
	local text
	classify_new_log
	R_LOG_WARN+="$LOG_WARN"
	[[ "$LOG_NEW_LINES" -gt 0 || "$LOG_IGNORED" -gt 0 ]] || return 0
	R_NEW_LINES=$((R_NEW_LINES + LOG_NEW_LINES))
	[[ "$LOG_NEW_LINES" -eq 0 ]] || R_LOG_FAIL="$LOG_FAIL"
	text="$(new_log_text)"
	if [[ -n "$R_LOG_TEXT" ]]; then
		R_LOG_TEXT+=$'\n'"$text"
	else
		R_LOG_TEXT="$text"
	fi
	return 0
}

# The end-of-run recheck of every held-back install (GH#750): after
# LOAD_RETRY_DELAY seconds, and before each install the account-load wait
# (DEPLOY_MAX_ACCOUNT_PROCS), so the host's limit has had time to clear.
recheck_deferred() {
	local state
	[[ "${#DEFERRED[@]}" -gt 0 ]] || return 0
	printf '\nRechecking %s install(s) where the %s, after %ss:\n' "${#DEFERRED[@]}" "$KILLED_TEXT" "$LOAD_RETRY_DELAY"
	sleep "$LOAD_RETRY_DELAY"
	for state in "${DEFERRED[@]}"; do
		recheck_install "$state"
	done
	return 0
}
