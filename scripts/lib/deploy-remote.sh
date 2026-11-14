#!/usr/bin/env bash
# The part of scripts/deploy-sites.sh that runs on the SSH host. It is not
# run by hand: deploy-sites.sh streams it to bash on the host for a dry run,
# and for --apply copies it with the zip to a private folder there first.
#
# Usage: bash deploy-remote.sh list  SLUG PARENT [--version=X.Y.Z] [--allow-downgrade] [SKIP]...
#        bash deploy-remote.sh apply SLUG PARENT VERSION ZIP SHA256 BACKUPS [--allow-downgrade] [--allow-concurrent-plugins] [SKIP]...
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
# site, a version not reached or new log lines, and 4 when nothing failed but
# a site stays UNVERIFIED (the host killed WP-CLI, 137, at the recheck too).
#
# apply holds a per-plugin lock on the host, ~/.SLUG-deploy/.lock (mkdir,
# with an owner file: PID, tag, start time, parent), from before the first
# install until it exits. While another run's lock is live it installs
# nothing, names that run and exits 3; a lock whose run has gone is taken
# over with a warning. list takes no lock and says when a run is active.
# Before taking it, apply also stops (exit 3, nothing installed) while
# another plugin's live lock (~/.OTHER-deploy/.lock) is on the host, so two
# plugins made from the starter never install at once on one shared account;
# that lock is never removed or taken over, and a stale one is ignored.
# --allow-concurrent-plugins skips this check.
#
# Bash only, and no process substitution: /dev/fd is missing in some SSH
# sessions. Never wp plugin update: on hosts with HTTP request limiters
# WP-CLI's update check can report the plugin already up to date.
#
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Marcus Quinn
# Additional terms (GPL-3.0 section 7(b)): ATTRIBUTION.txt
# Provenance: wpas-e4502af0f07e8a92. Copies, even of part, keep these lines.

# shellcheck disable=SC2034,SC2153 # globals are shared across deploy-remote*.sh, which shellcheck reads one file at a time

# Sourced as a library (DEPLOY_LIBRARY_ONLY=1), the caller's options stand.
if [[ "${DEPLOY_LIBRARY_ONLY:-0}" != 1 ]]; then
	set -uo pipefail
fi

WP_CLI="${DEPLOY_WP_CLI:-wp}"
WEB_ERROR_LOG="${DEPLOY_WEB_ERROR_LOG:-}"
# Fixed strings, one per line, from deploy-sites.sh --ignore-log-line (a file
# it copies here, so no remote quoting): a new log line that contains one is
# a warning, not a failure (GH#756). An unreadable file ignores nothing.
IGNORE_LOG_LINES=""
if [[ -n "${DEPLOY_IGNORE_LOG_FILE:-}" ]]; then
	IGNORE_LOG_LINES="$(cat "$DEPLOY_IGNORE_LOG_FILE" 2>/dev/null)" || IGNORE_LOG_LINES=""
fi
LOG_IGNORED=0
SLUG=""
FAILED=0
ALLOW_DOWNGRADE=0
# 1 with --allow-concurrent-plugins: install while another plugin deploys.
ALLOW_CONCURRENT=0
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
readonly CRON_LIST_FAILED="cron list failed; "
# A site whose load check or cron list the host killed (137) on its retry
# too, with nothing else wrong, is not a FAIL: it is checked again at the
# end of the run, and stays UNVERIFIED (exit 4, no restore) if killed again.
readonly KILLED_TEXT="host killed WP-CLI (137) twice"
readonly RECHECKED_TEXT="rechecked after host kill (137)"
# Installs held back for that recheck: install_state of each.
DEFERRED=()
INSTALLS_OK=0
INSTALLS_UNVERIFIED=0
UNVERIFIED_SITES=0
SKIPS=()
LOG_FILES=()
LOG_BEFORE=()
LOG_FIRST=()
LOG_INODE=()

# The functions live in deploy-remote-*.sh beside this file. deploy-sites.sh
# sends this part to the host as one stream (the modules, then this file, with
# DEPLOY_REMOTE_BUNDLED=1 first), so only a run from the repository sources them.
if [[ "${DEPLOY_REMOTE_BUNDLED:-0}" != 1 ]]; then
	DEPLOY_REMOTE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" || exit 1
	for DEPLOY_REMOTE_MODULE in "$DEPLOY_REMOTE_DIR"/deploy-remote-*.sh; do
		# shellcheck source=/dev/null # followed only with -x
		. "$DEPLOY_REMOTE_MODULE" || exit 1
	done
fi

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
	while :; do
		case "${1:-}" in
		--allow-downgrade) ALLOW_DOWNGRADE=1 ;;
		--allow-concurrent-plugins) ALLOW_CONCURRENT=1 ;;
		*) break ;;
		esac
		shift
	done
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
		apply_start "$want" "$zip" "$sha" "$backups" "$parent" || return $?
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
		recheck_deferred
		printf '\n%s install(s): %s ok or WARN, %s FAIL, %s UNVERIFIED; %s site(s) UNVERIFIED (%s).\n' \
			"$count" "$INSTALLS_OK" "$((count - INSTALLS_OK - INSTALLS_UNVERIFIED))" "$INSTALLS_UNVERIFIED" "$UNVERIFIED_SITES" "$KILLED_TEXT"
		say "Backups: $backups"
	fi
	[[ "$FAILED" -eq 0 ]] || return 1
	# Nothing failed, but a site could not be checked: no restore (GH#750).
	[[ "$UNVERIFIED_SITES" -eq 0 ]] || return 4
	return 0
}

if [[ "${DEPLOY_LIBRARY_ONLY:-0}" != 1 ]]; then
	main "$@"
fi
