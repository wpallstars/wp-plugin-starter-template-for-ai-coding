#!/usr/bin/env bash
# The part of scripts/deploy-sites.sh that runs on the SSH host. It is not
# run by hand: deploy-sites.sh streams it to bash on the host for a dry run,
# and for --apply copies it with the zip to a private folder there first.
#
# Usage: bash deploy-remote.sh list  SLUG PARENT [SKIP]...
#        bash deploy-remote.sh apply SLUG PARENT VERSION ZIP SHA256 BACKUPS [SKIP]...
#
# PARENT is a pattern for the WordPress folders (wp-config.php and the
# plugin's main file inside); a leading ~/ is the home folder. Only installs
# that already have wp-content/plugins/SLUG/SLUG.php are touched. Each line
# printed is one install; apply exits 1 when any install did not reach
# VERSION or logged new lines.
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
SKIPS=()
LOG_FILES=()
LOG_BEFORE=()

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
	if [[ "$status" -ne 0 || "$output$errors" == *"Error establishing a database connection"* || "$output$errors" == *"WordPress database error"* ]]; then
		[[ -z "$output" ]] || printf '%s\n' "$output" >&2
		[[ -z "$errors" ]] || printf '%s\n' "$errors" >&2
		return 1
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
active_guard() {
	local root="$1" add="$2" remove="$3"
	shift 3
	local before status=0
	before="$(active_snapshot "$root")" || return 1
	# Validate the machine-readable snapshot before ANY mutation.
	FLEET_BEFORE="$before" wp_checked "$root" --skip-plugins --skip-themes eval \
		'if (!is_array(json_decode(getenv("FLEET_BEFORE"), true))) { WP_CLI::error("Invalid activation snapshot output"); }' >/dev/null || return 1
	wp_checked "$root" "$@" || status=1
	active_check "$root" "$before" "$add" "$remove" || status=1
	[[ "$status" -eq 0 ]] || return 1
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
		if [[ "$WEB_ERROR_LOG" == /* ]]; then
			path="$WEB_ERROR_LOG"
		else
			path="$root/$WEB_ERROR_LOG"
		fi
		if [[ -e "$path" && ( ! -f "$path" || ! -r "$path" ) ]]; then
			say "deploy-remote: web PHP log is not a readable regular file: $path"
			return 1
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
	for path in ${LOG_FILES[@]+"${LOG_FILES[@]}"}; do
		LOG_BEFORE+=("$(file_lines "$path")")
	done
	return 0
}

new_log_text() {
	local index=0
	local file
	for file in ${LOG_FILES[@]+"${LOG_FILES[@]}"}; do
		if [[ -f "$file" ]]; then
			tail -n +"$((LOG_BEFORE[index] + 1))" "$file" | head -n 10
		fi
		index=$((index + 1))
	done
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

list_one() {
	local root="$1"
	local name="$2"
	local version kind
	version="$(plugin_version "$root/wp-content/plugins/$SLUG/$SLUG.php")"
	kind="$(wp_bare "$root" eval 'echo is_multisite() ? "multisite" : "single";')" || return 1
	printf '%s\t%s\t%s\t%s\n' "$name" "${version:-?}" "${kind:-unknown}" "$root"
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
	local before after status home code backup new_lines result="ok" index file

	before="$(plugin_version "$main")"
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

	# Activation (and network activation) is kept by install --force.
	if ! active_guard "$root" "" "" --skip-plugins --skip-themes plugin install "$zip" --force >/dev/null; then
		printf '%s\tFAIL: guarded install stopped; restore: tar -xzf %q -C %q\n' "$name" "$backup" "$plugins"
		FAILED=1
		return 0
	fi
	# One full load, so the plugin's settings upgrade runs (main site).
	if ! active_guard "$root" "" "" eval 'echo "loaded";' >/dev/null; then
		printf '%s\tFAIL: WordPress load failed; restore: tar -xzf %q -C %q\n' "$name" "$backup" "$plugins"
		FAILED=1
		return 0
	fi

	after="$(plugin_version "$main")"
	if ! status="$(wp_bare "$root" plugin list --name="$SLUG" --field=status)" ||
		! home="$(wp_bare "$root" option get home)"; then
		printf '%s\tFAIL: verification WP-CLI failed; restore: tar -xzf %q -C %q\n' "$name" "$backup" "$plugins"
		FAILED=1
		return 0
	fi
	code="000"
	if [[ -n "$home" ]]; then
		code="$(curl -s -o /dev/null -L -w '%{http_code}' --max-time 30 "$home/" || true)"
	fi
	new_lines=0
	index=0
	for file in ${LOG_FILES[@]+"${LOG_FILES[@]}"}; do
		new_lines=$((new_lines + $(file_lines "$file") - LOG_BEFORE[index]))
		index=$((index + 1))
	done

	# A home page that fails (5xx, such as WordPress's critical error page)
	# or does not answer fails the install; 4xx can be a firewall's answer
	# to the host itself, so it is only reported.
	if [[ "$after" != "$want" || "$new_lines" -gt 0 || "$code" == 5* || "$code" == "000" ]]; then
		result="FAIL"
		FAILED=1
	fi
	printf '%s\t%s -> %s\tstatus=%s\thome=%s\tnew_log_lines=%s\t%s\n' \
		"$name" "${before:-?}" "${after:-?}" "${status:-?}" "${code:-000}" "$new_lines" "$result"
	if [[ "$new_lines" -gt 0 ]]; then
		new_log_text | sed 's/^/    /'
	fi
	if [[ "$result" == "FAIL" ]]; then
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
		;;
	*)
		say "deploy-remote: the first argument is list or apply"
		return 2
		;;
	esac
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
	fi

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
			if ! list_one "$root" "$name"; then
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
