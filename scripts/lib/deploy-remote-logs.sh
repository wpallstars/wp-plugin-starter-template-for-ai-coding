#!/usr/bin/env bash
# Part of scripts/lib/deploy-remote.sh (see it for what the remote part does):
# Web and PHP log files: which to watch, what each gained, and how new lines are classified.
# Only functions: sourced by deploy-remote.sh, or bundled with it by
# deploy-sites.sh, never run alone. Its variables are set in deploy-remote.sh.
#
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Marcus Quinn
# Additional terms (GPL-3.0 section 7(b)): ATTRIBUTION.txt
# Provenance: wpas-e4502af0f07e8a92. Copies, even of part, keep these lines.
# shellcheck disable=SC2034,SC2153 # globals are shared across deploy-remote*.sh, which shellcheck reads one file at a time

# The web PHP log of one install, from WEB_ERROR_LOG: {name} becomes the
# install's name (install_name) and {name_} the same with each . as _, so
# hosts with one log per site (~/.logs/error_log_example_com) need one run. A
# leading ~/ is the home folder; another relative path is from the install.
web_error_log_path() {
	local root="$1"
	local path="$WEB_ERROR_LOG"
	local name
	name="$(install_name "$root")"
	path="$(replace_text "$path" '{name_}' "${name//./_}")"
	path="$(replace_text "$path" '{name}' "$name")"
	if [[ "$path" == \~/* ]]; then
		path="$HOME/${path#\~/}"
	elif [[ "$path" != /* ]]; then
		path="$root/$path"
	fi
	printf '%s' "$path"
	return 0
}

# The web PHP log's own checks (its folder exists; the file, if there, is a
# readable regular file), without WP-CLI: cheap enough to run before the
# account-load wait, so a wrong path fails at once.
web_log_usable() {
	local root="$1"
	local path folder
	[[ -n "$WEB_ERROR_LOG" ]] || return 0
	path="$(web_error_log_path "$root")"
	folder="$(dirname "$path")"
	if [[ ! -d "$folder" ]]; then
		say "deploy-remote: the web PHP log's folder does not exist: $folder"
		return 1
	fi
	if [[ -e "$path" && ( ! -f "$path" || ! -r "$path" ) ]]; then
		say "deploy-remote: web PHP log is not a readable regular file: $path"
		return 1
	fi
	return 0
}

# Discover log files before installation, then print the lines each one gained.
log_files() {
	local root="$1"
	local wp_debug php_error path candidate existing duplicate
	local candidates=()
	local unique=()
	wp_debug="$(wp_bare "$root" eval 'echo defined("WP_DEBUG_LOG") && is_string(WP_DEBUG_LOG) && !in_array(strtolower(WP_DEBUG_LOG), array("1", "true"), true) ? WP_DEBUG_LOG : (defined("WP_DEBUG_LOG") && WP_DEBUG_LOG ? WP_CONTENT_DIR . "/debug.log" : "");')" || return 1
	# CLI ini settings do not describe PHP-FPM pools or .user.ini. The
	# caller supplies the verified web destination separately for apply.
	php_error="$(wp_bare "$root" eval 'echo ini_get("error_log");')" || return 1
	candidates+=("$root/error_log" "$root/wp-content/debug.log")
	if [[ -n "$WEB_ERROR_LOG" ]]; then
		web_log_usable "$root" || return 1
		path="$(web_error_log_path "$root")"
		if [[ ! -e "$path" ]]; then
			say "web PHP log $path: not there yet (counted if the install creates it)"
		fi
		candidates+=("$path")
	fi
	if [[ -n "$wp_debug" ]]; then
		if [[ "$wp_debug" == /* ]]; then
			candidates+=("$wp_debug")
		else
			candidates+=("$root/$wp_debug")
		fi
	fi
	if [[ -n "$php_error" && "$php_error" != "syslog" ]]; then
		if [[ "$php_error" == /* ]]; then
			candidates+=("$php_error")
		else
			candidates+=("$root/$php_error")
		fi
	fi
	for candidate in "${candidates[@]}"; do
		duplicate=0
		for existing in ${unique[@]+"${unique[@]}"}; do
			if [[ "$candidate" == "$existing" || "$candidate" -ef "$existing" ]]; then
				duplicate=1
				break
			fi
		done
		[[ "$duplicate" -eq 1 ]] || unique+=("$candidate")
	done
	LOG_FILES=(${unique[@]+"${unique[@]}"})
	LOG_BEFORE=()
	LOG_FIRST=()
	LOG_INODE=()
	for path in ${LOG_FILES[@]+"${LOG_FILES[@]}"}; do
		LOG_BEFORE+=("$(file_lines "$path")")
		LOG_FIRST+=("$(first_line "$path")")
		LOG_INODE+=("$(file_inode "$path")")
	done
	return 0
}

# First line of a file, to tell a rotated or replaced log from a grown one.
first_line() {
	local file="$1"
	if [[ -f "$file" ]]; then
		head -n 1 "$file" 2>/dev/null || true
	fi
	return 0
}

# File identity (inode), to tell a replaced log from a grown one even when the
# replacement has the same first line and at least as many lines.
file_inode() {
	local file="$1"
	if [[ -f "$file" ]]; then
		# find -ls prints the inode first on GNU and BSD, without stat flags.
		find "$file" -maxdepth 0 -ls 2>/dev/null | awk '{print $1}' || true
	fi
	return 0
}

# Line to read a log from: after the baseline, or from the top when the log
# shrank, was replaced (new inode) or its first line changed (rotated, however
# far it has regrown).
log_start() {
	local file="$1" before="$2" first="$3" inode="$4"
	if [[ "$(file_lines "$file")" -lt "$before" ]] || [[ "$(file_inode "$file")" != "$inode" ]] || { [[ "$before" -gt 0 ]] && [[ "$(first_line "$file")" != "$first" ]]; }; then
		printf '1'
	else
		printf '%s' "$((before + 1))"
	fi
	return 0
}

# Every line the web logs gained since log_files; a truncated or rotated log
# contributes all of its current lines. awk ends each log's last line with a
# newline, so a log without one cannot join its last line to the next log's
# first (an error read as part of a cron notice).
new_log_all() {
	local index=0
	local file start
	for file in ${LOG_FILES[@]+"${LOG_FILES[@]}"}; do
		if [[ -f "$file" ]]; then
			start="$(log_start "$file" "${LOG_BEFORE[index]}" "${LOG_FIRST[index]}" "${LOG_INODE[index]}")"
			tail -n +"$start" "$file" | awk '{ print }'
		fi
		index=$((index + 1))
	done
	return 0
}

# Reads log lines on stdin; HOOKS is the space-separated hooks this run
# executed. WordPress's cron reschedule/unschedule error with code
# could_not_set means two cron runners saved the cron option at once. For one
# of HOOKS (our forced run and the site's own cron runner handled the same
# event) it prints "race HOOK" once per hook; for any other hook,
# "contention". Every other line prints "line", which still counts as new.
# WordPress logs the error in the site's language ("Cron unschedule event
# error for hook: HOOK, Error code: could_not_set, Error message: ..., Data:
# {...}"; in Dutch "Cron ongepland event fout voor hook: HOOK, foutcode:
# could_not_set, foutmelding: ..., gegevens: {...}"), so only its shape is
# matched. wp-cron.php writes it with error_log() (no "PHP Notice:" prefix),
# always with all four fields (WordPress 6.1 and later; plugins need 6.2), the
# last being the event as JSON. So the line must be: optional [timestamp]
# blocks, message text with no colon, comma or digit, then ": HOOK, ", a
# label, ": could_not_set, ", a label, ": " and the message, ", ", a label,
# ": {...}" and the end of the line (or Apache's ", referer: URL"). A
# plugin's own line of a similar start ("Payment task failed for hook: HOOK,
# status: could_not_set") is not WordPress's and still fails the install.
# Any other line that contains one of IGNORE_LOG_LINES (a fixed string, not a
# pattern) after its leading [...] blocks (timestamp, Apache prefix) prints
# "ignored" (GH#756). Read through ENVIRON: awk -v would process backslashes.
classify_log() {
	local hooks=" $1 "
	IGNORE="$IGNORE_LOG_LINES" awk -v hooks="$hooks" '
		BEGIN { ignores = split(ENVIRON["IGNORE"], ignore, "\n") }
		{
			if (match($0, /:[[:space:]]*[^[:space:],:]+,[^:,]*:[[:space:]]*could_not_set[[:space:]]*,[^:,]*:.*,[^:,]*:[[:space:]]*[{].*[}][[:space:]]*(,[[:space:]]*referer:[[:space:]]*[^[:space:]]*[[:space:]]*)?$/) \
				&& substr($0, 1, RSTART - 1) ~ /^(\[[^]]*\][[:space:]]*)*[^]:[,0-9]*$/) {
				text = substr($0, RSTART, RLENGTH)
				sub(/^:[[:space:]]*/, "", text)
				sub(/,.*$/, "", text)
				if (index(hooks, " " text " ") == 0) {
					print "contention"
				} else if (!(text in seen)) {
					seen[text] = 1
					print "race " text
				}
				next
			}
			rest = $0
			sub(/^(\[[^]]*\][[:space:]]*)+/, "", rest)
			for (i = 1; i <= ignores; i++) {
				if (ignore[i] != "" && index(rest, ignore[i]) > 0) {
					print "ignored"
					next
				}
			}
			print "line"
		}
	'
	return 0
}

# The first lines of the new log text, for the report.
new_log_text() {
	new_log_all | head -n 10
	return 0
}

# Classifies the new log lines from one snapshot, so a line arriving mid-check
# cannot hide an error. Cron race lines for hooks this run executed are
# warnings, not new lines, as are lines the operator ignored. Sets
# LOG_NEW_LINES (lines that count), LOG_IGNORED (ignored lines), LOG_WARN
# (warning text) and LOG_FAIL (1 when the new lines fail the install).
classify_new_log() {
	local snapshot classified entry contention=0
	LOG_NEW_LINES=0 LOG_IGNORED=0 LOG_WARN="" LOG_FAIL=1
	snapshot="$(new_log_all)"
	if [[ -n "$snapshot" ]]; then
		classified="$(printf '%s\n' "$snapshot" | classify_log "$CRON_HOOKS_RUN")"
		while IFS= read -r entry; do
			case "$entry" in
			line) LOG_NEW_LINES=$((LOG_NEW_LINES + 1)) ;;
			contention)
				# The same cron error, for a hook this run did not execute.
				LOG_NEW_LINES=$((LOG_NEW_LINES + 1))
				contention=$((contention + 1))
				;;
			"race "*) LOG_WARN+="cron race ${entry#race }, " ;;
			ignored) LOG_IGNORED=$((LOG_IGNORED + 1)) ;;
			*) ;;
			esac
		done <<<"$classified"
	fi
	[[ "$LOG_IGNORED" -eq 0 ]] || LOG_WARN+="ignored log lines ($LOG_IGNORED), "
	if [[ "$LOG_NEW_LINES" -gt 0 && "$contention" -eq "$LOG_NEW_LINES" ]]; then
		# Two cron runners saved the cron option at once: not a failure.
		LOG_WARN+="cron save contention ($contention lines), "
		LOG_FAIL=0
	fi
	return 0
}
