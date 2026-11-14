#!/usr/bin/env bash
# Part of scripts/lib/deploy-remote.sh (see it for what the remote part does):
# Finding the installs and the sites of each.
# Only functions: sourced by deploy-remote.sh, or bundled with it by
# deploy-sites.sh, never run alone. Its variables are set in deploy-remote.sh.
#
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Marcus Quinn
# Additional terms (GPL-3.0 section 7(b)): ATTRIBUTION.txt
# Provenance: wpas-e4502af0f07e8a92. Copies, even of part, keep these lines.
# shellcheck disable=SC2034,SC2153 # globals are shared across deploy-remote*.sh, which shellcheck reads one file at a time

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
