#!/usr/bin/env bash
# The part of scripts/deploy-sites.sh that runs on the SSH host. It is not
# run by hand: deploy-sites.sh streams it to bash on the host for a dry run,
# and for --apply copies it with the zip to a private folder there first.
#
# Usage: bash deploy-remote.sh list  SLUG PARENT [--version=X.Y.Z] [--allow-downgrade] [SKIP]...
#        bash deploy-remote.sh apply SLUG PARENT VERSION ZIP SHA256 BACKUPS [--allow-downgrade] [SKIP]...
#
# PARENT is a pattern for the WordPress folders (wp-config.php and the
# plugin's main file inside); a leading ~/ is the home folder. Only installs
# that already have wp-content/plugins/SLUG/SLUG.php are touched. Each install
# gets one line; networks also get one indented line per site, excluding
# archived, deleted and spam sites. Each site is loaded, its page cache purged
# (LiteSpeed Cache, when its WP-CLI command is there; purged=N/SITES) and
# fetched with a unique query string. cache= lists the final response's cache
# headers, or redirected:HOST when a redirect dropped that query; WARN cached
# means a cache ignored the query string, so PHP did not run for that fetch,
# and WARN purge failed that visitors may still get pages pointing at the old
# CSS and JS. After each load the plugin's own WP-Cron events run once on
# that site (cron=N/M); a PHP fatal error or non-zero exit in one fails the
# site, as the host's cron job would hit it from the command line. A home
# that gives 5xx or no answer is fetched once more after
# DEPLOY_HOME_RETRY_DELAY seconds (default 5); a pass then is WARN home
# retried (CODE), a second failure fails the site. With DEPLOY_CDN_PURGE=1
# each install prints @cdn lines (its site addresses) and cdn=@CDN@ for
# deploy-sites.sh to fill after purging Cloudflare; with 0 each site's plain
# home address is fetched once and WARN Cloudflare keeps pages from before
# the deploy means a cf-cache-status HIT older than the install. apply exits 1 on a failed
# site, a version not reached or new log lines.
#
# apply holds a per-plugin lock on the host, ~/.SLUG-deploy/.lock (mkdir,
# with an owner file: PID, tag, start time, parent), from before the first
# install until it exits. While another run's lock is live it installs
# nothing, names that run and exits 3; a lock whose run has gone is taken
# over with a warning. list takes no lock and says when a run is active.
#
# Bash only, and no process substitution: /dev/fd is missing in some SSH
# sessions. Never wp plugin update: on hosts with HTTP request limiters
# WP-CLI's update check can report the plugin already up to date.
#
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Marcus Quinn
# Additional terms (GPL-3.0 section 7(b)): ATTRIBUTION.txt
# Provenance: wpas-e4502af0f07e8a92. Copies, even of part, keep these lines.

# Sourced as a library (DEPLOY_LIBRARY_ONLY=1), the caller's options stand.
if [[ "${DEPLOY_LIBRARY_ONLY:-0}" != 1 ]]; then
	set -uo pipefail
fi

WP_CLI="${DEPLOY_WP_CLI:-wp}"
WEB_ERROR_LOG="${DEPLOY_WEB_ERROR_LOG:-}"
SLUG=""
FAILED=0
ALLOW_DOWNGRADE=0
RUN_STAMP=""
LOCK_DIR=""
FETCHES=0
# WordPress's database failures in WP-CLI output: a load or cron run that
# prints one failed, whatever its exit code.
readonly DB_QUERY_ERROR="WordPress database error"
readonly DB_CONNECT_ERROR="Error establishing a database connection"
# 1 when the person running the deploy gave deploy-sites.sh a Cloudflare
# token: it purges Cloudflare from their computer (the token never comes
# here), and this part only names each site (@cdn lines) and leaves cdn=@CDN@
# on the install line for it to fill. 0: check the plain home address instead.
CDN_PURGE="${DEPLOY_CDN_PURGE:-0}"
[[ "$CDN_PURGE" == 1 ]] || CDN_PURGE=0
CDN_URLS=""
CF_STALE=""
MAIN_CF=""
INSTALL_START=0
# Seconds before a home page that gave 5xx or no answer is fetched again.
HOME_RETRY_DELAY="${DEPLOY_HOME_RETRY_DELAY:-5}"
[[ "$HOME_RETRY_DELAY" =~ ^[0-9]+$ ]] || HOME_RETRY_DELAY=5
# The host can kill WP-CLI (exit 137, no output) at its process or memory
# limit; the limit clears in tens of seconds, so the load check waits longer.
LOAD_RETRY_DELAY="${DEPLOY_LOAD_RETRY_DELAY:-30}"
[[ "$LOAD_RETRY_DELAY" =~ ^[0-9]+$ ]] || LOAD_RETRY_DELAY=30
SKIPS=()
LOG_FILES=()
LOG_BEFORE=()
LOG_FIRST=()
LOG_INODE=()

say() {
	local message="$1"
	printf '%s\n' "$message"
	return 0
}

# A docroot's short name: its own folder name, or the one above it when the
# folder has a common docroot name (~/domains/example.com/public_html is
# example.com).
install_name() {
	local root="$1"
	local name
	name="$(basename "$root")"
	case "$name" in
	public_html | htdocs | html | public | www | web)
		name="$(basename "$(dirname "$root")")"
		;;
	*) ;;
	esac
	printf '%s' "$name"
	return 0
}

skipped() {
	local root="$1"
	local name="$2"
	local skip
	for skip in ${SKIPS[@]+"${SKIPS[@]}"}; do
		if [[ "$skip" == "$name" || "$skip" == "$root" ]]; then
			return 0
		fi
	done
	return 1
}

# The Version: header of the plugin's main file.
plugin_version() {
	local file="$1"
	awk '{
		line = $0
		sub(/^[ \t*]*/, "", line)
		if (tolower(substr(line, 1, 8)) == "version:") {
			v = substr(line, 9)
			gsub(/^[ \t]+|[ \t\r]+$/, "", v)
			print v
			exit
		}
	}' "$file" 2>/dev/null
	return 0
}

wp_bare() {
	local root="$1"
	shift
	local output
	output="$(wp_checked "$root" --skip-plugins --skip-themes "$@")" || return 1
	printf '%s\n' "$output" | tail -n 1
	return 0
}

# Preserve exit status and check stderr too: database errors can accompany
# exit zero. Stdout stays clean (snapshots and JSON reports are parsed from
# it); stderr goes to a private temporary file, as process substitution is
# not available everywhere, and is shown only on failure.
wp_checked() {
	local root="$1"
	shift
	local output errors err_file status=0
	err_file="$(mktemp)" || return 1
	output="$("$WP_CLI" --path="$root" "$@" 2>"$err_file")" || status=$?
	errors="$(cat "$err_file")"
	rm -f "$err_file"
	# Whether WP-CLI itself wrote nothing to stderr (callers may retry a
	# bare SIGKILL; the copy of stdout below must not hide that).
	WP_STDERR_EMPTY=0
	[[ -n "$errors" ]] || WP_STDERR_EMPTY=1
	if [[ "$status" -ne 0 || "$output$errors" == *"$DB_CONNECT_ERROR"* || "$output$errors" == *"$DB_QUERY_ERROR"* ]]; then
		[[ -z "$output" ]] || printf '%s\n' "$output" >&2
		[[ -z "$errors" ]] || printf '%s\n' "$errors" >&2
		[[ "$status" -ne 0 ]] || status=1
		return "$status"
	fi
	printf '%s\n' "$output"
	return 0
}

# Raw stored lists, never option filters or an object-cache read. JSON carries
# sorted plugin files and explicit counts, including a genuinely empty array.
# Networks: inspect every blog in this network plus active_sitewide_plugins;
# NEVER auto-restore a network. Report it for operator recovery instead.
active_reader() {
	cat <<'PHP'
function fleet_active_read() {
    global $wpdb;
    $decode = function ($raw) use ($wpdb) {
        if ($wpdb->last_error || !is_string($raw)) { WP_CLI::error("Cannot read stored activation list"); }
        $value = @unserialize($raw, array("allowed_classes" => false));
        if (!is_array($value)) { WP_CLI::error("Stored activation list is not an array"); }
        return $value;
    };
    $network = array();
    $blogs = array(get_current_blog_id());
    if (is_multisite()) {
        $blogs = $wpdb->get_col($wpdb->prepare("SELECT blog_id FROM {$wpdb->blogs} WHERE site_id = %d ORDER BY blog_id", get_current_network_id()));
        if ($wpdb->last_error || !$blogs) { WP_CLI::error("Cannot read network blogs"); }
        $network = $decode($wpdb->get_var($wpdb->prepare("SELECT meta_value FROM {$wpdb->sitemeta} WHERE site_id = %d AND meta_key = %s", get_current_network_id(), "active_sitewide_plugins")));
        foreach ($network as $file => $time) {
            if (!is_string($file) || !is_numeric($time)) { WP_CLI::error("Invalid network activation entry"); }
        }
        ksort($network, SORT_STRING);
    }
    $sites = array();
    foreach ($blogs as $id) {
        $table = $wpdb->get_blog_prefix($id) . 'options';
        $raw = $wpdb->get_var($wpdb->prepare("SELECT option_value FROM `{$table}` WHERE option_name = %s", 'active_plugins'));
        $files = $decode($raw);
        foreach ($files as $file) {
            if (!is_string($file) || !preg_match("~^[a-zA-Z0-9_./-]+\\.php$~D", $file)) { WP_CLI::error("Invalid activation entry"); }
        }
        sort($files, SORT_STRING);
        $sites[(string) $id] = array('count' => count($files), 'files' => $files, 'stored' => base64_encode($raw));
    }
    return array('multisite' => is_multisite(), 'blog' => get_current_blog_id(), 'sites' => $sites, 'network_count' => count($network), 'network' => $network);
}
PHP
	return 0
}

active_snapshot() {
	local root="$1"
	wp_checked "$root" --skip-plugins --skip-themes eval "$(active_reader) echo json_encode(fleet_active_read(), JSON_UNESCAPED_SLASHES);" || return 1
	return 0
}

# The ONLY explicit active_plugins writer. Restore only a strict subset of
# BEFORE, on a single site, after re-reading and matching OBSERVED. Extra
# entries (including a new intended activation) may be concurrent work: stop,
# do not overwrite them. The sole restore write uses an atomic binary SQL
# compare-and-swap, not update_option(): option filters cannot interfere and
# a concurrent activation between the read and write cannot be overwritten.
active_restore_code() {
	active_reader
	cat <<'PHP'
$before = json_decode(getenv('FLEET_BEFORE'), true);
$observed = json_decode(getenv('FLEET_OBSERVED'), true);
if (getenv('FLEET_OBSERVED') === '') { $observed = fleet_active_read(); }
if (!is_array($before) || !is_array($observed) || $before['multisite'] || $observed !== fleet_active_read()) { WP_CLI::error("Restore refused: network, invalid snapshot or concurrent change; use the database backup after review"); }
$id = $before['blog'];
$old = $before['sites'][$id]['files'];
$now = $observed['sites'][$id]['files'];
if (count($now) >= count($old) || array_diff($now, $old)) { WP_CLI::error("Restore refused: not a strict subset; review the diff and database backup"); }
global $wpdb;
$changed = $wpdb->query($wpdb->prepare("UPDATE {$wpdb->options} SET option_value = %s WHERE option_name = %s AND BINARY option_value = BINARY %s", base64_decode($before['sites'][$id]['stored']), 'active_plugins', base64_decode($observed['sites'][$id]['stored'])));
if ($changed !== 1 || $wpdb->last_error) { WP_CLI::error("Restore refused: concurrent write or database error"); }
wp_cache_delete('active_plugins', 'options');
wp_cache_delete('alloptions', 'options');
wp_cache_delete('notoptions', 'options');
if (fleet_active_read() !== $before) { WP_CLI::error("Activation restore failed verification"); }
WP_CLI::line("Activation list restored; this install remains FAIL");
PHP
	return 0
}

# Compare the AFTER snapshot (FLEET_OBSERVED) with BEFORE plus the intended
# additions and removals (FLEET_ADD, FLEET_REMOVE: one plugin file per line).
active_check_code() {
	cat <<'PHP'
$before = json_decode(getenv('FLEET_BEFORE'), true); $after = json_decode(getenv('FLEET_OBSERVED'), true);
if (!is_array($before) || !is_array($after)) { WP_CLI::error("Invalid activation snapshot output"); }
$expected = $before; $id = $before['blog']; $files = $before['sites'][$id]['files'];
$remove = array_filter(explode("\n", getenv('FLEET_REMOVE'))); $add = array_filter(explode("\n", getenv('FLEET_ADD')));
$files = array_values(array_unique(array_merge(array_diff($files, $remove), $add))); sort($files, SORT_STRING);
$expected['sites'][$id]['count'] = count($files); $expected['sites'][$id]['files'] = $files;
// Stored order is recovery evidence, not activation semantics.
foreach ($expected['sites'] as $blog => $list) { if (isset($after['sites'][$blog])) { $expected['sites'][$blog]['stored'] = $after['sites'][$blog]['stored']; } }
if ($expected !== $after) {
    foreach ($expected['sites'] as $blog => $list) {
        $now = $after['sites'][$blog]['files'] ?? array();
        WP_CLI::line("FAIL blog=" . $blog . " missing=" . json_encode(array_values(array_diff($list['files'], $now))) . " extra=" . json_encode(array_values(array_diff($now, $list['files']))));
    }
    if ($expected['network'] !== $after['network']) { WP_CLI::line("FAIL network missing=" . json_encode(array_diff_key($expected['network'], $after['network'])) . " extra/changed=" . json_encode(array_diff_assoc($after['network'], $expected['network']))); }
    WP_CLI::error("Stored activation lists changed unexpectedly");
}
PHP
	return 0
}

active_check() {
	local root="$1" before="$2" add="$3" remove="$4"
	local after code
	after="$(active_snapshot "$root")" || {
		printf 'FAIL: cannot read activation lists after change; restore from the database backup after database recovery\n' >&2
		printf '    restore: env FLEET_BEFORE=%q FLEET_OBSERVED= %q --path=%q --skip-plugins --skip-themes eval %q\n' \
			"$before" "$WP_CLI" "$root" "$(active_restore_code)" >&2
		return 1
	}
	code="$(active_check_code)"
	if ! FLEET_BEFORE="$before" FLEET_OBSERVED="$after" FLEET_ADD="$add" FLEET_REMOVE="$remove" \
		wp_checked "$root" --skip-plugins --skip-themes eval "$code"; then
		code="$(active_restore_code)"
		printf '    restore: env FLEET_BEFORE=%q FLEET_OBSERVED=%q %q --path=%q --skip-plugins --skip-themes eval %q\n' \
			"$before" "$after" "$WP_CLI" "$root" "$code" >&2
		# On stderr: callers discard stdout, and the operator needs the result.
		FLEET_BEFORE="$before" FLEET_OBSERVED="$after" wp_checked "$root" --skip-plugins --skip-themes eval "$code" >&2 || true
		return 1
	fi
	return 0
}

# Even when the command fails, check for damage before stopping the install.
# Sets GUARD_ACTIVE_OK (1 only when the activation lists were checked and are as
# they should be; a retry is safe only then).
active_guard() {
	local root="$1" add="$2" remove="$3"
	shift 3
	local before status=0
	GUARD_ACTIVE_OK=0
	before="$(active_snapshot "$root")" || return 1
	# Validate the machine-readable snapshot before ANY mutation.
	FLEET_BEFORE="$before" wp_checked "$root" --skip-plugins --skip-themes eval \
		'if (!is_array(json_decode(getenv("FLEET_BEFORE"), true))) { WP_CLI::error("Invalid activation snapshot output"); }' >/dev/null || return 1
	wp_checked "$root" "$@" || status=$?
	if active_check "$root" "$before" "$add" "$remove"; then
		GUARD_ACTIVE_OK=1
	else
		[[ "$status" -ne 0 ]] || status=1
	fi
	return "$status"
}

# TEXT with every FIND replaced by WITH, taken literally: ${var//find/with}
# reads & in WITH as the match in bash 5.2 and later, and quoting WITH to stop
# that keeps the quotes in bash 3.2.
replace_text() {
	local text="$1"
	local find="$2"
	local with="$3"
	local out=""
	while [[ "$text" == *"$find"* ]]; do
		out+="${text%%"$find"*}$with"
		text="${text#*"$find"}"
	done
	printf '%s' "$out$text"
	return 0
}

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

# Discover log files before installation, then print the lines each one gained.
log_files() {
	local root="$1"
	local wp_debug php_error path folder candidate existing duplicate
	local candidates=()
	local unique=()
	wp_debug="$(wp_bare "$root" eval 'echo defined("WP_DEBUG_LOG") && is_string(WP_DEBUG_LOG) && !in_array(strtolower(WP_DEBUG_LOG), array("1", "true"), true) ? WP_DEBUG_LOG : (defined("WP_DEBUG_LOG") && WP_DEBUG_LOG ? WP_CONTENT_DIR . "/debug.log" : "");')" || return 1
	# CLI ini settings do not describe PHP-FPM pools or .user.ini. The
	# caller supplies the verified web destination separately for apply.
	php_error="$(wp_bare "$root" eval 'echo ini_get("error_log");')" || return 1
	candidates+=("$root/error_log" "$root/wp-content/debug.log")
	if [[ -n "$WEB_ERROR_LOG" ]]; then
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
classify_log() {
	local hooks=" $1 "
	awk -v hooks="$hooks" '
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
# warnings, not new lines. Sets LOG_NEW_LINES (lines that count), LOG_WARN
# (warning text) and LOG_FAIL (1 when the new lines fail the install).
classify_new_log() {
	local snapshot classified entry contention=0
	LOG_NEW_LINES=0 LOG_WARN="" LOG_FAIL=1
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
			*) ;;
			esac
		done <<<"$classified"
	fi
	if [[ "$LOG_NEW_LINES" -gt 0 && "$contention" -eq "$LOG_NEW_LINES" ]]; then
		# Two cron runners saved the cron option at once: not a failure.
		LOG_WARN+="cron save contention ($contention lines), "
		LOG_FAIL=0
	fi
	return 0
}

file_lines() {
	local file="$1"
	if [[ -f "$file" ]]; then
		wc -l <"$file" | tr -d ' '
	else
		printf '0'
	fi
	return 0
}

# Every WordPress folder matching PARENT that has the plugin, one per line.
installs() {
	local parent="$1"
	local matches root
	if [[ "$parent" == \~/* ]]; then
		parent="$HOME/${parent#\~/}"
	fi
	matches="$(compgen -G "$parent" | LC_ALL=C sort || true)"
	while IFS= read -r root; do
		[[ -n "$root" ]] || continue
		root="${root%/}"
		if [[ -f "$root/wp-config.php" && -f "$root/wp-content/plugins/$SLUG/$SLUG.php" ]]; then
			printf '%s\n' "$root"
		fi
	done <<<"$matches"
	return 0
}

# The host provides coreutils sort -V; equal versions may be reinstalled.
# Return 2 on comparison failure, distinct from 1 (not newer): also for an
# installed version that cannot be read, which may be newer. A prerelease
# of the target (2.0.0-rc1 for 2.0.0) is older, though sort -V puts it after.
newer_than() {
	local installed="$1"
	local want="$2"
	local sorted
	[[ -n "$installed" ]] || return 2
	[[ "$installed" != "$want" && "$installed" != "$want"-* ]] || return 1
	sorted="$(printf '%s\n%s\n' "$want" "$installed" | sort -V)" || return 2
	[[ "${sorted##*$'\n'}" == "$installed" ]] || return 1
	return 0
}

list_one() {
	local root="$1"
	local name="$2"
	local want="${3:-}"
	local version kind note="" comparison=0
	version="$(plugin_version "$root/wp-content/plugins/$SLUG/$SLUG.php")"
	kind="$(wp_bare "$root" eval 'echo is_multisite() ? "multisite" : "single";')" || return 1
	if [[ -n "$want" ]]; then
		newer_than "$version" "$want" || comparison=$?
		case "$comparison" in
		0)
			note="newer than tag; --apply will refuse"
			[[ "$ALLOW_DOWNGRADE" -eq 0 ]] || note="newer than tag; downgrade allowed (--allow-downgrade)"
			;;
		1) ;;
		*)
			if [[ "$ALLOW_DOWNGRADE" -eq 0 ]]; then
				note="FAIL: cannot compare versions; --apply will refuse without --allow-downgrade"
				FAILED=1
			else
				note="cannot compare versions; install allowed (--allow-downgrade)"
			fi
			;;
		esac
	fi
	printf '%s\t%s\t%s\t%s' "$name" "${version:-?}" "${kind:-unknown}" "$root"
	[[ -z "$note" ]] || printf '\t%s' "$note"
	printf '\n'
	if [[ "$CDN_PURGE" -eq 1 ]]; then
		# deploy-sites.sh lists the zones these sites would purge.
		site_urls "$root" "$kind" 2>/dev/null | cdn_lines || true
	fi
	return 0
}

# Main site first, then every other serving site. Preserve all WP-CLI rows.
site_urls() {
	local root="$1"
	local kind="$2"
	local main urls url
	main="$(wp_bare "$root" option get home)" || return 1
	[[ -n "$main" ]] || return 1
	printf '%s\n' "$main"
	[[ "$kind" == "multisite" ]] || return 0
	urls="$(wp_checked "$root" --skip-plugins --skip-themes site list --field=url --archived=0 --deleted=0 --spam=0)" || return 1
	while IFS= read -r url; do
		[[ -n "$url" && "${url%/}" != "${main%/}" ]] || continue
		printf '%s\n' "$url"
	done <<<"$urls"
	return 0
}

# The guarded full load of one site: WordPress runs the site's settings
# upgrade, then the site's page cache is purged, so cached pages stop
# pointing at the old ?ver= of the plugin's CSS and JS. Only page caches
# with a WP-CLI purge command are known: LiteSpeed Cache. wp cache flush
# empties the object cache, never the pages. cli has-command, not a per-site
# plugin is-active check, which misses a network-activated plugin. On a
# network, litespeed-purge all empties every site's cache, so each site
# purges only its own (litespeed-purge blog <id>). Prints purged=yes, no (no
# known page cache) or failed. A failed purge does not stop the load: the
# install worked, but visitors may see the old assets. LiteSpeed Cache's
# command delivers the purge with a request to the site's admin-ajax.php,
# with WordPress's 5 second timeout; just after an update the site's first
# requests compile the new code and can take longer (4.6-7 s seen on shared
# hosting), so that request gets 30 seconds. The commands run in this
# process (launch false), so the filter applies to them.
load_code() {
	cat <<'PHP'
echo "loaded\n";
$purged = "no";
add_filter("http_request_args", function ($args, $url) {
    if (false !== strpos((string) $url, "/wp-admin/admin-ajax.php")) {
        $args["timeout"] = max((float) $args["timeout"], 30);
    }
    return $args;
}, 10, 2);
$run = array("launch" => false, "exit_error" => false, "return" => "all");
$purges = array("litespeed-purge" => is_multisite() ? "blog " . get_current_blog_id() : "all");
foreach ($purges as $command => $args) {
    if (0 === WP_CLI::runcommand("cli has-command " . $command, $run)->return_code) {
        $purged = 0 === WP_CLI::runcommand($command . " " . $args, $run)->return_code ? "yes" : "failed";
        break;
    }
}
echo "purged=" . $purged . "\n";
PHP
	return 0
}

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

# Runs the plugin's own scheduled events once on one site, each in its own
# WP-CLI process (a fatal error ends one process, not the count). A fatal
# error that only a cron callback reaches never shows in the full load, the
# home fetch or the web PHP log: the host's cron job runs WP-Cron from the
# command line. Running an event early reschedules it, as wp cron event run
# does by hand. An event gets DEPLOY_CRON_TIMEOUT seconds (default 120, 0 for
# no limit); one that times out is a warning, not a failure. A single event
# the site's own cron ran between the list and its run here (WP-CLI: Invalid
# cron event) is a note, not a failure, and not counted as run here (GH#1369).
# Sets CRON_RUN, CRON_TOTAL, CRON_FAILURE and CRON_WARN for the site.
run_site_cron() {
	local root="$1"
	shift
	local hooks hook out status limit="${DEPLOY_CRON_TIMEOUT:-120}" detail
	local cmd=()
	CRON_RUN=0 CRON_TOTAL=0 CRON_FAILURE="" CRON_WARN=""
	[[ "$limit" =~ ^[0-9]+$ ]] || limit=120
	local list_code list_out list_err list_status=0 retried="" list_failed="cron list failed; "
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
	# Hooks that repeat, read before the first run (a run changes the list).
	# If the read fails, none is known and a kill is retried only for a hook
	# still listed.
	local recurrences
	recurrences="$("$WP_CLI" --path="$root" "$@" cron event list --fields=hook,recurrence --format=csv 2>/dev/null | awk -F, 'NR>1 && $2!="" && $2!="Non-repeating" {print $1}')" || recurrences=""
	while IFS= read -r hook; do
		[[ -n "$hook" ]] || continue
		CRON_TOTAL=$((CRON_TOTAL + 1))
		status=0
		out="$("${cmd[@]+"${cmd[@]}"}" "$WP_CLI" --path="$root" "$@" cron event run "$hook" 2>&1)" || status=$?
		# A killed event (137) is run again, up to 3 tries in all, but only a
		# one-off still listed: WP-CLI removes a one-off before its callback
		# and reschedules a recurring event before it, so a retry of either
		# runs the next occurrence early or a callback twice. Any other final
		# 137 stays a failure, even for a one-off no longer listed.
		local tries=1 still=""
		while [[ "$status" -eq 137 && "$tries" -lt 3 ]]; do
			printf '%s\n' "$recurrences" | grep -qxF "$hook" && break
			still="$("$WP_CLI" --path="$root" "$@" cron event list --field=hook 2>/dev/null)" || break
			printf '%s\n' "$still" | grep -qxF "$hook" || break
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
		CRON_RUN=0 CRON_TOTAL=0 CRON_WARN=""
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

# Called directly: counters, the main row and network lines are results.
check_sites() {
	local root="$1"
	local kind urls url status result reason warn load purged line network=0
	local load_errors load_status load_retried summary first_code cron_note cron_before
	local check_error="home check failed; "
	local url_args=() origin
	CDN_URLS="" MAIN_CF=""
	SITES_TOTAL=0 SITES_FAILED=0 SITES_PURGED=0 PURGE_FAILED=0 SITE_LINES=""
	CRON_SUM_RUN=0 CRON_SUM_TOTAL=0 CRON_WARNED="" CRON_HOOKS_RUN=""
	MAIN_STATUS="?" MAIN_CODE="000" MAIN_CACHE="none" MAIN_REASON="" MAIN_RETRIED="" MAIN_LOAD_RETRIED=""
	kind="$(wp_bare "$root" eval 'echo is_multisite() ? "multisite" : "single";')" || return 1
	case "$kind" in
	multisite) network=1 ;;
	single) ;;
	*) return 1 ;;
	esac
	urls="$(site_urls "$root" "$kind")" || return 1
	load_errors="$(mktemp)" || return 1
	while IFS= read -r url; do
		[[ -n "$url" ]] || continue
		SITES_TOTAL=$((SITES_TOTAL + 1))
		[[ "$network" -eq 0 ]] || url_args=(--url="$url")
		reason="" warn="" result="ok" purged="no" cron_note="cron=0/0"
		load_check "$root" "$load_errors" ${url_args[@]+"${url_args[@]}"}
		load="$LOAD_OUT" load_status="$LOAD_STATUS" load_retried="$LOAD_RETRIED"
		if [[ "$load_status" -eq 0 ]]; then
			[[ -z "$load_retried" ]] || warn+="load retried ($load_retried), "
			case "$load" in
			*purged=yes*) purged="yes" SITES_PURGED=$((SITES_PURGED + 1)) ;;
			*purged=failed*)
				purged="failed" warn+="purge failed, "
				PURGE_FAILED=$((PURGE_FAILED + 1))
				;;
			*) ;;
			esac
			# The plugin's own scheduled events, once, after a good load.
			# A cron callback must not change the activation lists either.
			cron_step "$root" ${url_args[@]+"${url_args[@]}"}
			cron_note="cron=${CRON_RUN}/${CRON_TOTAL}"
			[[ -z "$CRON_FAILURE" ]] || reason+="$CRON_FAILURE"
			[[ -z "$CRON_WARN" ]] || {
				warn+="$CRON_WARN"
				CRON_WARNED+="$CRON_WARN"
			}
		else
			# Keep the full diagnostics on stderr, but one short, printable
			# line on the report (also when WP-CLI itself printed no error).
			summary="$(tail -n 3 "$load_errors" | LC_ALL=C tr '\t\r\n' '   ' | LC_ALL=C tr -cd '[:print:]')"
			reason="WordPress load failed (exit $load_status"
			[[ -z "$summary" ]] || reason+=": ${summary:0:300}"
			reason+="); "
		fi
		cat "$load_errors" >&2
		if ! status="$(wp_bare "$root" ${url_args[@]+"${url_args[@]}"} plugin list --name="$SLUG" --field=status)" || [[ -z "$status" ]]; then
			reason+="status read failed; "
		fi
		origin="$(origin_ip "$root" ${url_args[@]+"${url_args[@]}"})"
		home_check "$url" "$origin" || reason+="$check_error"
		# A busy host can answer one fetch with 5xx (or not at all) while the
		# site is fine: fetch once more after a pause, and fail only if that
		# fails too. A pass on the second fetch is a warning, not silence.
		first_code=""
		if [[ "$HOME_CODE" == 5* || "$HOME_CODE" == "000" ]]; then
			first_code="$HOME_CODE"
			sleep "$HOME_RETRY_DELAY"
			home_check "$url" "$origin" || [[ "$reason" == *"$check_error"* ]] || reason+="$check_error"
		fi
		# 4xx may be the host's firewall: report, but do not fail it (a pinned
		# fetch skips the CDN, so a 4xx there is the origin's own answer).
		if [[ "$HOME_CODE" == 5* || "$HOME_CODE" == "000" ]]; then
			reason+="home failed${first_code:+ ($first_code, then $HOME_CODE)}; "
		elif [[ -n "$first_code" ]]; then
			warn+="home retried ($first_code), "
		fi
		[[ "$HOME_CACHE" != *hit* || "$HOME_CACHE" == redirected:* ]] || warn+="cached, "
		cdn_step "$url"
		warn+="$CDN_WARN"
		if [[ -n "$reason" ]]; then
			result="FAIL: ${reason%; }"
			SITES_FAILED=$((SITES_FAILED + 1))
		elif [[ -n "$warn" ]]; then
			result="WARN ${warn%, }"
		fi
		if [[ "$SITES_TOTAL" -eq 1 ]]; then
			MAIN_STATUS="$status" MAIN_CODE="${HOME_CODE}${HOME_PINNED:+ pinned}" MAIN_CACHE="$HOME_CACHE"
			MAIN_REASON="${reason%; }" MAIN_RETRIED="$first_code" MAIN_LOAD_RETRIED="$load_retried"
		fi
		if [[ "$network" -eq 1 ]]; then
			printf -v line '    site %s\tstatus=%s\tpurged=%s\t%s\thome=%s\tcache=%s\t%s\n' "$url" "${status:-?}" "$purged" "$cron_note" "${HOME_CODE}${HOME_PINNED:+ pinned}" "$HOME_CACHE" "$result"
			SITE_LINES+="$line"
		fi
	done <<<"$urls"
	rm -f "$load_errors"
	[[ "$SITES_TOTAL" -gt 0 ]] || return 1
	return 0
}

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
	local before after backup new_lines result="ok" warn=""
	local log_fail=1
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
	if ! log_files "$root"; then
		printf '%s\tFAIL: cannot check the web PHP log; not installed\n' "$name"
		FAILED=1
		return 0
	fi

	wait_for_account_load
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

	after="$(plugin_version "$main")"
	classify_new_log
	new_lines="$LOG_NEW_LINES"
	warn+="$LOG_WARN"
	log_fail="$LOG_FAIL"

	# Single sites have no site row on which to show these warnings.
	[[ "$PURGE_FAILED" -eq 0 ]] || warn+="purge failed, "
	[[ -z "$CRON_WARNED" || -n "$SITE_LINES" ]] || warn+="$CRON_WARNED"
	[[ "$MAIN_CACHE" != *hit* || "$MAIN_CACHE" == redirected:* ]] || warn+="cached, "
	[[ -z "$MAIN_LOAD_RETRIED" || -n "$SITE_LINES" ]] || warn+="load retried ($MAIN_LOAD_RETRIED), "
	[[ -z "$MAIN_RETRIED" ]] || warn+="home retried ($MAIN_RETRIED), "
	# A network's site rows carry this warning; a single site has no row.
	[[ -z "$MAIN_CF" || -n "$SITE_LINES" ]] || warn+="$(cf_warning "$MAIN_CF"), "
	if [[ "$after" != "$want" || ("$new_lines" -gt 0 && "$log_fail" -eq 1) || "$SITES_FAILED" -gt 0 ]]; then
		result="FAIL"
		if [[ -z "$SITE_LINES" && -n "$MAIN_REASON" ]]; then
			result+=": $MAIN_REASON"
		fi
		FAILED=1
	elif [[ -n "$warn" ]]; then
		result="WARN ${warn%, }"
	fi
	cdn_announce
	printf '%s\t%s -> %s\tstatus=%s\tpurged=%s/%s\tcron=%s/%s\thome=%s\tcache=%s\tcdn=%s\tnew_log_lines=%s' \
		"$name" "${before:-?}" "${after:-?}" "$MAIN_STATUS" "$SITES_PURGED" "$SITES_TOTAL" "$CRON_SUM_RUN" "$CRON_SUM_TOTAL" "$MAIN_CODE" "$MAIN_CACHE" "$CDN_FIELD" "$new_lines"
	if [[ -n "$SITE_LINES" ]]; then
		printf '\tsites=%s/%s' "$((SITES_TOTAL - SITES_FAILED))" "$SITES_TOTAL"
	fi
	printf '\t%s\n' "$result"
	printf '%s' "$SITE_LINES"
	if [[ "$new_lines" -gt 0 ]]; then
		new_log_text | sed 's/^/    /'
	fi
	if [[ "$result" == FAIL* ]]; then
		printf '    restore: rm -rf %q && tar -xzf %q -C %q\n' "$plugins/$SLUG" "$backup" "$plugins"
	fi
	return 0
}

sha256_of() {
	local file="$1"
	if command -v sha256sum >/dev/null 2>&1; then
		sha256sum "$file" | awk '{print $1}'
	elif command -v shasum >/dev/null 2>&1; then
		shasum -a 256 "$file" | awk '{print $1}'
	else
		return 1
	fi
	return 0
}

# The host's per-plugin deploy lock: ~/.SLUG-deploy/.lock, made with mkdir
# (atomic everywhere, unlike flock, which shared hosts may lack), with an
# owner file inside: pid, tag, started and parent, one key=value per line.
lock_path() {
	printf '%s/.%s-deploy/.lock' "$HOME" "$SLUG"
	return 0
}

lock_field() {
	local dir="$1"
	local key="$2"
	[[ -f "$dir/owner" ]] || return 0
	awk -v k="$key" 'index($0, k "=") == 1 { print substr($0, length(k) + 2); exit }' "$dir/owner" 2>/dev/null
	return 0
}

lock_holder() {
	local dir="$1"
	local tag started parent pid
	tag="$(lock_field "$dir" tag)"
	started="$(lock_field "$dir" started)"
	parent="$(lock_field "$dir" parent)"
	pid="$(lock_field "$dir" pid)"
	printf 'tag %s, started %s, parent %s, PID %s' "${tag:-?}" "${started:-?}" "${parent:-?}" "${pid:-?}"
	return 0
}

# Whether the lock's run is still going: its PID runs a command line that
# contains deploy-remote (so a PID reused by another command does not keep
# the lock; one reused by another deploy-remote run would), or, where ps -p
# fails (no ps, BusyBox ps, no readable process table), kill -0 finds it. A
# lock with no owner file yet is being taken: live for its first two minutes.
lock_live() {
	local dir="$1"
	local pid args
	pid="$(lock_field "$dir" pid)"
	if [[ -z "$pid" ]]; then
		[[ -n "$(find "$dir" -maxdepth 0 -mmin -2 2>/dev/null)" ]] || return 1
		return 0
	fi
	[[ "$pid" =~ ^[0-9]+$ ]] || return 1
	if command -v ps >/dev/null 2>&1 && args="$(ps -p "$pid" -o args= 2>/dev/null)"; then
		[[ "$args" == *deploy-remote* ]] || return 1
		return 0
	fi
	kill -0 "$pid" 2>/dev/null || return 1
	return 0
}

# Remove a stale lock only if it is still the one judged stale. Takeovers
# take turns under a second lock (DIR.takeover, made with mkdir), so a run
# cannot move a lock another takeover has just made. Under it the lock's
# PID and liveness are read again, the lock is moved aside (atomic) and its
# PID is compared once more; a lock that is not the stale one is put back.
# A takeover lock more than a minute old (find -mmin +1; GNU find counts
# whole minutes, so up to two) is from a run that died during its
# takeover, which takes a moment, and is removed.
lock_break() {
	local dir="$1"
	local stale_pid="$2"
	local guard="$dir.takeover"
	local moved="$dir.stale.$$"
	local tries=0
	until mkdir "$guard" 2>/dev/null; do
		tries=$((tries + 1))
		[[ "$tries" -le 10 ]] || return 0
		if [[ -n "$(find "$guard" -maxdepth 0 -mmin +1 2>/dev/null)" ]]; then
			rmdir "$guard" 2>/dev/null || true
		else
			sleep 1
		fi
	done
	if [[ -d "$dir" && "$(lock_field "$dir" pid)" == "$stale_pid" ]] && ! lock_live "$dir" &&
		mv "$dir" "$moved" 2>/dev/null; then
		if [[ "$(lock_field "$moved" pid)" == "$stale_pid" ]]; then
			rm -rf "$moved"
		elif [[ -e "$dir" ]] || ! mv "$moved" "$dir" 2>/dev/null; then
			say "deploy-remote: WARN a lock taken during the takeover was moved to $moved; remove it once no deploy of $SLUG runs"
		fi
	fi
	rmdir "$guard" 2>/dev/null || true
	return 0
}

# Takes the lock for this apply run, or says who holds it. Returns 3 when
# another run holds it, 2 when the lock cannot be made.
lock_take() {
	local tag="$1"
	local parent="$2"
	local dir pid tries=0
	dir="$(lock_path)"
	if ! mkdir -p "$(dirname "$dir")"; then
		say "deploy-remote: cannot make $(dirname "$dir"); nothing installed"
		return 2
	fi
	while [[ "$tries" -lt 3 ]]; do
		tries=$((tries + 1))
		if mkdir "$dir" 2>/dev/null; then
			if ! printf 'pid=%s\ntag=%s\nstarted=%s\nparent=%s\n' "$$" "$tag" \
				"$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$(printf '%s' "$parent" | tr '\n' ' ')" >"$dir/owner" 2>/dev/null; then
				# The redirect may have made a partial owner file (a full disk).
				# Remove the lock only while its owner file names this run: an
				# empty or missing one may already be a replacement run's lock
				# (this run's was taken over as stale while it was paused), so it
				# is left to be taken over once two minutes old.
				if [[ "$(lock_field "$dir" pid)" == "$$" ]]; then
					rm -f "$dir/owner"
					rmdir "$dir" 2>/dev/null || true
					say "deploy-remote: cannot write the deploy lock's owner file $dir/owner; nothing installed"
				else
					say "deploy-remote: cannot write the deploy lock's owner file $dir/owner; nothing installed. The lock is left in place; a run in two minutes takes it over if it is not another run's."
				fi
				return 2
			fi
			if [[ "$(lock_field "$dir" pid)" != "$$" ]]; then
				say "deploy-remote: lost the deploy lock $dir while taking it; nothing installed"
				return 3
			fi
			LOCK_DIR="$dir"
			trap lock_release EXIT
			trap 'exit 129' HUP
			trap 'exit 130' INT
			trap 'exit 143' TERM
			return 0
		fi
		# Gone since mkdir failed: another run's takeover; try again.
		[[ -d "$dir" ]] || continue
		if lock_live "$dir"; then
			if [[ -z "$(lock_field "$dir" pid)" ]]; then
				say "deploy-remote: the deploy lock $dir has no owner yet: another run is taking it, or one could not write its owner file; nothing installed. Run again in two minutes, when a lock with no owner is taken over."
			else
				say "deploy-remote: another deploy of $SLUG is running on this host ($(lock_holder "$dir")); nothing installed. Wait for it to finish, then run again."
			fi
			return 3
		fi
		pid="$(lock_field "$dir" pid)"
		say "deploy-remote: WARN taking over a stale deploy lock ($(lock_holder "$dir")): that run is no longer running"
		lock_break "$dir" "$pid"
	done
	if [[ ! -d "$dir" ]]; then
		say "deploy-remote: cannot make the deploy lock $dir; nothing installed"
		return 2
	fi
	say "deploy-remote: could not take the deploy lock $dir after 3 tries; nothing installed"
	return 3
}

# On exit: remove the lock, but only while it is still this run's.
lock_release() {
	if [[ -n "$LOCK_DIR" && "$(lock_field "$LOCK_DIR" pid)" == "$$" ]]; then
		rm -rf "$LOCK_DIR"
	fi
	LOCK_DIR=""
	return 0
}

# Dry run: say when an apply run is active; it takes no lock.
lock_report() {
	local dir
	dir="$(lock_path)"
	[[ -d "$dir" ]] || return 0
	if lock_live "$dir" && [[ -z "$(lock_field "$dir" pid)" ]]; then
		say "A deploy lock of $SLUG with no owner yet is on this host ($dir): another run is taking it, or one could not write its owner file. --apply stops until it is two minutes old, then takes it over."
	elif lock_live "$dir"; then
		say "A deploy of $SLUG is running on this host ($(lock_holder "$dir")); --apply stops until it ends."
	else
		say "A stale deploy lock of $SLUG is on this host ($(lock_holder "$dir")); --apply will take it over."
	fi
	return 0
}

main() {
	local mode="${1:-}"
	SLUG="${2:-}"
	local parent="${3:-}"
	local want="" zip="" sha="" backups="" found root name count=0 apply=0
	case "$mode" in
	apply)
		apply=1
		want="${4:-}"
		zip="${5:-}"
		sha="${6:-}"
		backups="${7:-}"
		shift 7 || {
			say "deploy-remote: apply needs SLUG PARENT VERSION ZIP SHA256 BACKUPS"
			return 2
		}
		;;
	list)
		shift 3 || {
			say "deploy-remote: list needs SLUG PARENT"
			return 2
		}
		if [[ "${1:-}" == --version=* ]]; then
			want="${1#--version=}"
			shift
		fi
		;;
	*)
		say "deploy-remote: the first argument is list or apply"
		return 2
		;;
	esac
	if [[ "${1:-}" == --allow-downgrade ]]; then
		ALLOW_DOWNGRADE=1
		shift
	fi
	SKIPS=("$@")
	if [[ ! "$SLUG" =~ ^[a-z0-9-]+$ ]]; then
		say "deploy-remote: not a plugin slug: $SLUG"
		return 2
	fi
	if ! command -v "$WP_CLI" >/dev/null 2>&1; then
		say "deploy-remote: no WP-CLI ($WP_CLI) on this host's PATH; set DEPLOY_WP_CLI"
		return 2
	fi

	if [[ "$apply" -eq 1 ]]; then
		if [[ -z "$WEB_ERROR_LOG" || "$WEB_ERROR_LOG" == "syslog" ]]; then
			say "deploy-remote: apply requires DEPLOY_WEB_ERROR_LOG, the verified web PHP log file; nothing installed"
			return 2
		fi
		if [[ "$(sha256_of "$zip" || true)" != "$sha" ]]; then
			say "deploy-remote: the zip's SHA-256 on this host is not $sha; nothing installed"
			return 2
		fi
		say "zip SHA-256 on the host: ok"
		if ! mkdir -p "$backups" || ! chmod 700 "$backups"; then
			say "deploy-remote: cannot make the backup folder $backups"
			return 2
		fi
		lock_take "v$want" "$parent" || return $?
	else
		lock_report
	fi

	RUN_STAMP="$(date -u +%Y%m%d%H%M%S)-$$"
	found="$(installs "$parent")"
	while IFS= read -r root; do
		[[ -n "$root" ]] || continue
		name="$(install_name "$root")"
		if skipped "$root" "$name"; then
			printf '%s\tskipped (--skip)\n' "$name"
			continue
		fi
		count=$((count + 1))
		if [[ "$apply" -eq 1 ]]; then
			apply_one "$root" "$name" "$want" "$zip" "$backups"
		else
			if ! list_one "$root" "$name" "$want"; then
				printf '%s\tFAIL: cannot read WordPress; no change made, no restore needed\n' "$name"
				FAILED=1
			fi
		fi
	done <<<"$found"

	if [[ "$count" -eq 0 ]]; then
		say "No install of $SLUG under $parent."
		return "$apply"
	fi
	if [[ "$apply" -eq 1 ]]; then
		say "Backups: $backups"
	fi
	[[ "$FAILED" -eq 0 ]] || return 1
	return 0
}

if [[ "${DEPLOY_LIBRARY_ONLY:-0}" != 1 ]]; then
	main "$@"
fi
