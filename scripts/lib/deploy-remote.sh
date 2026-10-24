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
# that already have wp-content/plugins/SLUG/SLUG.php are touched. Each install
# gets one line; networks also get one indented line per site, excluding
# archived, deleted and spam sites. Each site is loaded, its page cache purged
# (LiteSpeed Cache, when its WP-CLI command is there; purged=N/SITES) and
# fetched with a unique query string. cache= lists the response's cache
# headers; WARN cached means a cache ignored the query string, so PHP did not
# run for that fetch, and WARN purge failed that visitors may still get pages
# pointing at the old CSS and JS. apply exits 1 on a failed site, a version
# not reached or new log lines.
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
RUN_STAMP=""
FETCHES=0
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
	local file start
	for file in ${LOG_FILES[@]+"${LOG_FILES[@]}"}; do
		if [[ -f "$file" ]]; then
			start=$((LOG_BEFORE[index] + 1))
			if [[ "$(file_lines "$file")" -lt "${LOG_BEFORE[index]}" ]]; then
				start=1
			fi
			tail -n +"$start" "$file" | head -n 10
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

# Sets HOME_CODE/HOME_CACHE and advances FETCHES in the caller's shell.
home_check() {
	local url="$1"
	local headers
	FETCHES=$((FETCHES + 1))
	HOME_CODE="000"
	HOME_CACHE="none"
	headers="$(mktemp)" || return 1
	HOME_CODE="$(curl -s -o /dev/null -L -D "$headers" -w '%{http_code}' --max-time 30 \
		"${url%/}/?deploy-check=${RUN_STAMP}-${FETCHES}" || true)"
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
		END { print cache == "" ? "none" : cache }
	' "$headers")"
	rm -f "$headers"
	return 0
}

# Called directly: counters, the main row and network lines are results.
check_sites() {
	local root="$1"
	local kind urls url status result reason warn load purged line network=0
	local url_args=()
	SITES_TOTAL=0 SITES_FAILED=0 SITES_PURGED=0 PURGE_FAILED=0 SITE_LINES=""
	MAIN_STATUS="?" MAIN_CODE="000" MAIN_CACHE="none"
	kind="$(wp_bare "$root" eval 'echo is_multisite() ? "multisite" : "single";')" || return 1
	case "$kind" in
	multisite) network=1 ;;
	single) ;;
	*) return 1 ;;
	esac
	urls="$(site_urls "$root" "$kind")" || return 1
	while IFS= read -r url; do
		[[ -n "$url" ]] || continue
		SITES_TOTAL=$((SITES_TOTAL + 1))
		[[ "$network" -eq 0 ]] || url_args=(--url="$url")
		reason="" warn="" result="ok" purged="no"
		if load="$(active_guard "$root" "" "" ${url_args[@]+"${url_args[@]}"} eval "$(load_code)")"; then
			case "$load" in
			*purged=yes*) purged="yes" SITES_PURGED=$((SITES_PURGED + 1)) ;;
			*purged=failed*)
				purged="failed" warn="purge failed, "
				PURGE_FAILED=$((PURGE_FAILED + 1))
				;;
			*) ;;
			esac
		else
			reason="WordPress load failed; "
		fi
		if ! status="$(wp_bare "$root" ${url_args[@]+"${url_args[@]}"} plugin list --name="$SLUG" --field=status)" || [[ -z "$status" ]]; then
			reason+="status read failed; "
		fi
		home_check "$url" || reason+="home check failed; "
		# 4xx may be the host's firewall: report, but do not fail it.
		if [[ "$HOME_CODE" == 5* || "$HOME_CODE" == "000" ]]; then
			reason+="home failed; "
		fi
		[[ "$HOME_CACHE" != *hit* ]] || warn+="cached, "
		if [[ -n "$reason" ]]; then
			result="FAIL: ${reason%; }"
			SITES_FAILED=$((SITES_FAILED + 1))
		elif [[ -n "$warn" ]]; then
			result="WARN ${warn%, }"
		fi
		if [[ "$SITES_TOTAL" -eq 1 ]]; then
			MAIN_STATUS="$status" MAIN_CODE="$HOME_CODE" MAIN_CACHE="$HOME_CACHE"
		fi
		if [[ "$network" -eq 1 ]]; then
			printf -v line '    site %s\tstatus=%s\tpurged=%s\thome=%s\tcache=%s\t%s\n' "$url" "${status:-?}" "$purged" "$HOME_CODE" "$HOME_CACHE" "$result"
			SITE_LINES+="$line"
		fi
	done <<<"$urls"
	[[ "$SITES_TOTAL" -gt 0 ]] || return 1
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
	local before after backup new_lines result="ok" warn="" index file current added

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
	# Each site's guarded full load runs its own settings upgrade.
	if ! check_sites "$root"; then
		printf '%s\tFAIL: cannot list the sites; restore: tar -xzf %q -C %q\n' "$name" "$backup" "$plugins"
		FAILED=1
		return 0
	fi

	after="$(plugin_version "$main")"
	new_lines=0
	index=0
	for file in ${LOG_FILES[@]+"${LOG_FILES[@]}"}; do
		current="$(file_lines "$file")"
		if [[ "$current" -lt "${LOG_BEFORE[index]}" ]]; then
			# A truncated or rotated log contributes all of its current lines.
			added="$current"
		else
			added=$((current - LOG_BEFORE[index]))
		fi
		new_lines=$((new_lines + added))
		index=$((index + 1))
	done

	# Single sites have no site row on which to show these warnings.
	[[ "$PURGE_FAILED" -eq 0 ]] || warn+="purge failed, "
	[[ "$MAIN_CACHE" != *hit* ]] || warn+="cached, "
	if [[ "$after" != "$want" || "$new_lines" -gt 0 || "$SITES_FAILED" -gt 0 ]]; then
		result="FAIL"
		FAILED=1
	elif [[ -n "$warn" ]]; then
		result="WARN ${warn%, }"
	fi
	printf '%s\t%s -> %s\tstatus=%s\tpurged=%s/%s\thome=%s\tcache=%s\tnew_log_lines=%s' \
		"$name" "${before:-?}" "${after:-?}" "$MAIN_STATUS" "$SITES_PURGED" "$SITES_TOTAL" "$MAIN_CODE" "$MAIN_CACHE" "$new_lines"
	if [[ -n "$SITE_LINES" ]]; then
		printf '\tsites=%s/%s' "$((SITES_TOTAL - SITES_FAILED))" "$SITES_TOTAL"
	fi
	printf '\t%s\n' "$result"
	printf '%s' "$SITE_LINES"
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
