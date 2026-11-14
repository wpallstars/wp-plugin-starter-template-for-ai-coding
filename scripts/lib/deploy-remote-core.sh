#!/usr/bin/env bash
# Part of scripts/lib/deploy-remote.sh (see it for what the remote part does):
# Output, install names and versions, WP-CLI calls, and the active-plugin snapshot, check and restore.
# Only functions: sourced by deploy-remote.sh, or bundled with it by
# deploy-sites.sh, never run alone. Its variables are set in deploy-remote.sh.
#
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Marcus Quinn
# Additional terms (GPL-3.0 section 7(b)): ATTRIBUTION.txt
# Provenance: wpas-e4502af0f07e8a92. Copies, even of part, keep these lines.
# shellcheck disable=SC2034,SC2153 # globals are shared across deploy-remote*.sh, which shellcheck reads one file at a time

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
