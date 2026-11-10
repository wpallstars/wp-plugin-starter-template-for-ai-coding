#!/usr/bin/env bash
# Roll out a published release (RELEASING.md step 5): install its zip on every
# WordPress install on one SSH host that already has the plugin.
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Marcus Quinn
# Additional terms (GPL-3.0 section 7(b)): ATTRIBUTION.txt
# Provenance: wpas-e4502af0f07e8a92. Copies, even of part, keep these lines.
#
# Usage: scripts/deploy-sites.sh --host SSH_HOST --tag vX.Y.Z
#                                [--parent PATTERN] [--skip NAME]...
#                                [--wp-cli COMMAND] [--apply | --dry-run]
#   --host SSH_HOST    The host as ssh knows it (an alias in ~/.ssh/config).
#   --tag vX.Y.Z       The GitHub release to install.
#   --parent PATTERN   The WordPress folders on the host, quoted so the local
#                      shell leaves it alone (default: '~/domains/*/public_html').
#   --skip NAME        Leave out an install, by its name (the folder above a
#                      public_html, htdocs, html, public, www or web folder,
#                      else the folder's own name) or its full path. Repeatable.
#   --wp-cli COMMAND   WP-CLI on the host (default: wp).
#   --web-error-log PATH  Verified web PHP log file, required for --apply;
#                      absolute, ~/ for the host's home folder, or relative
#                      to each WordPress folder. {name} is each install's name
#                      (as for --skip) and {name_} the same with . as _, for
#                      hosts with one log per site: '~/.logs/error_log_{name_}'.
#   --dry-run          List the installs found, with their version and whether
#                      each is a multisite network, and change nothing (the
#                      default).
#   --apply            Install the release on each of them.
#   --allow-downgrade  Allow installing a release older than the installed version.
#   --keep-releases N  After a successful --apply, remove this plugin's older run
#                      folders on the host (v<version>-<time> in ~/.{slug}-deploy),
#                      keeping the current run and every run of the newest N tags
#                      (default 3; 0 keeps everything). Skipped while another
#                      deploy holds the lock. Other files there stay.
#   --cloudflare-token-env NAME  The environment variable that holds a
#                      Cloudflare API token limited to Zone > Zone Read and
#                      Zone > Cache Purge (Read finds the zone). With
#                      it, the host names of each updated install's sites are
#                      purged at Cloudflare from this computer (the token never
#                      reaches the host); the dry run names the hosts per zone
#                      and purges nothing.
#   --cloudflare-purge hosts|zone  hosts (default): purge only those host
#                      names. zone: purge each whole zone (once per install),
#                      for pages on hosts this script does not see.
#
# The zip ({slug}-X.Y.Z.zip) is downloaded with gh (a failed download is tried
# again up to 4 times over about 5 minutes: GitHub sometimes answers "release
# not found" for a while) and must match the asset's SHA-256 on GitHub and its
# provenance bundle, if any (gh attestation verify).
# With --apply it is copied to a private folder on the host
# (~/.{slug}-deploy/<tag>-<time>, mode 700, files 600) and checked again.
# Then, for each install that already has wp-content/plugins/{slug}/{slug}.php
# (the plugin is never added anywhere): a tar backup of the plugin folder, wp
# a folder swap by two renames (activation and network activation are kept;
# files get the current time; wp plugin install --force if it cannot, except
# when the rollback of a failed second rename also fails: that install stops
# and its old folder, kept beside the plugin, needs a manual restore; with
# OPcache timestamp validation off, reset OPcache or restart PHP), then
# per site a full load for its settings upgrade, a LiteSpeed Cache purge (when
# its WP-CLI command is there) so pages stop pointing at the old CSS and JS,
# and a home fetch. After each load the plugin's own WP-Cron events run once
# on the site (this reschedules them, as wp cron event run does); a PHP fatal
# error or non-zero exit in one fails the install. Each event gets
# DEPLOY_CRON_TIMEOUT seconds (default 120; 0, no limit, for a host without
# timeout); a timeout only warns. Networks skip archived, deleted and spam
# sites. Each fetch uses a unique query string: WARN cached means a cache
# ignored it, so PHP did not run; WARN purge failed means visitors may still
# get the old CSS and JS. With --cloudflare-token-env the host names of each
# install's sites are purged at their zone (looked up by host name, then its
# parent domains; one request per zone and 30 hosts; --cloudflare-purge zone
# purges the whole zone once per install) (cdn=purged(N hosts), cdn=failed
# MESSAGE; cdn=- without a token). Without the token,
# the plain home address is fetched once: WARN Cloudflare keeps pages from
# before the deploy means Cloudflare answered HIT with a page older than the
# install. Each install line gives old -> new version, status,
# purged=N/SITES, cron=N/M, home HTTP code, cache= headers, cdn= and new log lines;
# networks add sites=PASSED/TOTAL and a line per site. Exits 1 on a failed
# site, a version not reached or new log lines, with the restore command.
# Host names, folders and backups stay out of the repository: only arguments.
#
# --apply holds a per-plugin lock on the host (~/.{slug}-deploy/.lock, made
# with mkdir) from the first install to the end, so two runs, even with
# different --parent, never install over each other. While another run holds
# it, --apply installs nothing, names that run (tag, start, parent, PID) and
# exits 3; a lock left by a run that has ended (kill -9, a restart) is taken
# over with a warning. The dry run takes no lock and says when one is active.
#
# Needs gh (signed in for a private repository), ssh, and bash, WP-CLI, tar
# and curl on the host; aidevops users can use wp-fleet-helper.sh instead.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
# shellcheck source=scripts/lib/plugin.sh disable=SC1091 # followed only with -x
. "$SCRIPT_DIR/lib/plugin.sh"
readonly REMOTE_PART="$SCRIPT_DIR/lib/deploy-remote.sh"

# Set in main() from the plugin's main file and the options.
SLUG=""
REPO=""
HOST=""
TAG=""
VERSION=""
# shellcheck disable=SC2088 # The host expands the ~, not this shell.
PARENT='~/domains/*/public_html'
WP_CLI="wp"
WEB_ERROR_LOG=""
APPLY=0
# Name of the environment variable that holds the Cloudflare token (never the
# token itself in an argument), and the token, read from it in main().
CF_TOKEN_ENV=""
CF_TOKEN=""
KEEP_RELEASES=3
# Zones already handled, one "ZONE_ID<TAB>RESULT" per line: for the whole dry
# run, and for one install in an apply (an install's update comes after the
# purges of earlier installs, so a shared zone is purged again).
CF_DONE=""
CF_PURGED=0
CF_FAILED=0
# Site addresses whose zone could not be found (no zone to count as failed).
CF_LOOKUP_FAILED=0
# What a purge covers: the updated sites' host names (hosts) or the whole zone.
CF_MODE_HOSTS="hosts"
CF_PURGE="$CF_MODE_HOSTS"
# Host names to purge, "ZONE_ID<TAB>ZONE<TAB>HOST" per line: for one install in
# an apply, for the whole dry run.
CF_PLAN=""
CF_HOSTS_PURGED=0
CF_HOSTS_FAILED=""
DOWNGRADE_ARGS=()
SKIPS=()
TMP_DIR=""
ZIP=""
SHA=""

die() {
	local message="$1"
	printf 'deploy-sites: %s\n' "$message" >&2
	exit 2
}

usage() {
	# The comment block under the first line, up to the first blank line.
	awk 'NR == 1 { next } /^$/ { exit } { sub(/^# ?/, ""); print }' "$0"
	return 0
}

cleanup() {
	if [[ -n "$TMP_DIR" ]] && [[ -d "$TMP_DIR" ]]; then
		rm -rf "$TMP_DIR"
	fi
	return 0
}

sha256_of() {
	local file="$1"
	if command -v sha256sum >/dev/null 2>&1; then
		sha256sum "$file" | awk '{print $1}'
	else
		shasum -a 256 "$file" | awk '{print $1}'
	fi
	return 0
}

# The words, each quoted for the remote shell, joined by spaces: ssh passes
# its command to the host's shell as one string.
remote_words() {
	local out="" word
	for word in "$@"; do
		out+="$(printf '%q' "$word") "
	done
	printf '%s' "${out% }"
	return 0
}

remote() {
	local command="$1"
	ssh -o BatchMode=yes "$HOST" "$command" || return $?
	return 0
}

parse_args() {
	while [[ $# -gt 0 ]]; do
		local arg="$1"
		local value="${2:-}"
		case "$arg" in
		--host | --tag | --parent | --skip | --wp-cli | --web-error-log | --cloudflare-token-env | --cloudflare-purge | --keep-releases)
			[[ $# -ge 2 ]] || die "$arg needs a value"
			[[ "$value" != -* ]] || die "$arg needs a value, not an option: $value"
			case "$arg" in
			--host) HOST="$value" ;;
			--tag) TAG="$value" ;;
			--parent) PARENT="$value" ;;
			--skip) SKIPS+=("$value") ;;
			--wp-cli) WP_CLI="$value" ;;
			--web-error-log) WEB_ERROR_LOG="$value" ;;
			--cloudflare-token-env) CF_TOKEN_ENV="$value" ;;
			--cloudflare-purge) CF_PURGE="$value" ;;
			--keep-releases) KEEP_RELEASES="$value" ;;
			*) ;; # The outer pattern lists every option that takes a value.
			esac
			shift
			;;
		--apply) APPLY=1 ;;
		--dry-run) APPLY=0 ;;
		--allow-downgrade) DOWNGRADE_ARGS=(--allow-downgrade) ;;
		-h | --help)
			usage
			exit 0
			;;
		*) die "unknown argument: $arg" ;;
		esac
		shift
	done
	[[ -n "$HOST" ]] || die "--host is required"
	[[ "$HOST" != -* ]] || die "--host cannot start with -"
	[[ "$TAG" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "--tag must be vX.Y.Z, not '$TAG'"
	VERSION="${TAG#v}"
	[[ -n "$PARENT" ]] || die "--parent cannot be empty"
	[[ "$KEEP_RELEASES" =~ ^[0-9]+$ ]] || die "--keep-releases takes a whole number, not '$KEEP_RELEASES'"
	[[ "$CF_PURGE" == "$CF_MODE_HOSTS" || "$CF_PURGE" == "zone" ]] || die "--cloudflare-purge takes hosts or zone, not '$CF_PURGE'"
	if [[ -n "$CF_TOKEN_ENV" ]]; then
		[[ "$CF_TOKEN_ENV" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || die "--cloudflare-token-env takes the NAME of an environment variable, not a token"
		CF_TOKEN="${!CF_TOKEN_ENV:-}"
		[[ -n "$CF_TOKEN" ]] || die "the environment variable $CF_TOKEN_ENV is empty or not set"
		# Goes into a curl config line: plain token characters only.
		[[ "$CF_TOKEN" =~ ^[A-Za-z0-9._-]+$ ]] || die "the value of $CF_TOKEN_ENV is not a Cloudflare API token"
	fi
	if [[ "$APPLY" -eq 1 ]]; then
		[[ -n "$WEB_ERROR_LOG" && "$WEB_ERROR_LOG" != "syslog" ]] ||
			die "--apply requires --web-error-log PATH (the verified web PHP log file, not syslog)"
	fi
	return 0
}

# Downloads one asset of the release into TMP_DIR. GitHub sometimes answers
# "release not found" for a published release for a few minutes, so a failed
# download is tried again after 30, 60, 120 and 120 seconds (5 tries).
download_asset() {
	local pattern="$1"
	local wait
	for wait in 30 60 120 120 0; do
		rm -f "$TMP_DIR/$pattern"
		if gh release download "$TAG" --repo "$REPO" --pattern "$pattern" --dir "$TMP_DIR"; then
			return 0
		fi
		[[ "$wait" -gt 0 ]] || break
		printf '  release download failed, retrying in %s s\n' "$wait" >&2
		sleep "$wait"
	done
	return 1
}

# Runs a gh read and prints its output. When GitHub defers or rate limits the
# read (quota pacing), it is tried again, up to 3 tries 60 s apart
# (GH_READ_RETRY_SECONDS). Any other failure, such as a missing release or bad
# auth, stops at once with gh's own message.
gh_read() {
	local out try err
	err="$(mktemp "${TMPDIR:-/tmp}/gh-read.XXXXXX")" || return 1
	for try in 1 2 3; do
		if out="$("$@" 2>"$err")"; then
			rm -f "$err"
			printf '%s\n' "$out"
			return 0
		fi
		if ! grep -Eiq 'github-api-read-deferred|rate limit|HTTP (403|429)' "$err" || [[ "$try" -eq 3 ]]; then
			break
		fi
		printf '  GitHub deferred the read (try %s of 3), retrying in %s s\n' "$try" "${GH_READ_RETRY_SECONDS:-60}" >&2
		sleep "${GH_READ_RETRY_SECONDS:-60}"
	done
	cat "$err" >&2
	rm -f "$err"
	return 1
}

# The release's zip, checked against GitHub's SHA-256 of the asset and, when
# the release has one, its provenance bundle. At least one check must apply.
download_zip() {
	local name="$SLUG-$VERSION.zip"
	local bundle="provenance-$SLUG-$VERSION.sigstore.json"
	local assets digest checked=0
	printf 'Release %s of %s\n' "$TAG" "$REPO"
	download_asset "$name" || die "cannot download $name from $TAG (is gh signed in?)"
	ZIP="$TMP_DIR/$name"
	SHA="$(sha256_of "$ZIP")"
	# Name and digest of each asset, one per line, compared outside jq.
	assets="$(gh_read gh api "repos/$REPO/releases/tags/$TAG" --jq '.assets[] | [.name, (.digest // "")] | @tsv')" ||
		die "cannot read the assets of $TAG"
	digest="$(awk -F '\t' -v n="$name" '$1 == n { print $2 }' <<<"$assets")"
	if [[ -n "$digest" ]]; then
		[[ "$digest" == "sha256:$SHA" ]] || die "$name does not match GitHub's digest ($digest, downloaded sha256:$SHA)"
		printf '  ok   SHA-256 matches the asset on GitHub: %s\n' "$SHA"
		checked=1
	fi
	if awk -F '\t' -v n="$bundle" '$1 == n { found = 1 } END { exit !found }' <<<"$assets"; then
		download_asset "$bundle" || die "cannot download $bundle"
		gh attestation verify "$ZIP" --bundle "$TMP_DIR/$bundle" --repo "$REPO" \
			--signer-workflow "$REPO/.github/workflows/release.yml" --source-ref "refs/tags/$TAG" >/dev/null ||
			die "the provenance of $name does not verify (gh attestation verify)"
		printf '  ok   provenance verifies: built by .github/workflows/release.yml from %s\n' "$TAG"
		checked=1
	fi
	[[ "$checked" -eq 1 ]] || die "$name has neither a GitHub digest nor a provenance bundle to check it against"
	return 0
}

# Cloudflare, called from this computer so the token never reaches the host.
# The token goes to curl in a config read from a pipe, not in an argument
# list, and is never printed. Needs Zone > Zone Read (to find the zone) and
# Zone > Cache Purge.
cf_api() {
	local method="$1"
	local path="$2"
	local data="${3:-}"
	local args=(-s --max-time 30 -X "$method" -H 'Content-Type: application/json')
	[[ -z "$data" ]] || args+=(--data "$data")
	curl "${args[@]}" --config <(printf 'header = "Authorization: Bearer %s"\n' "$CF_TOKEN") \
		"https://api.cloudflare.com/client/v4$path" </dev/null || return 1
	return 0
}

# Cloudflare's own message from a response body, one short printable line.
cf_message() {
	local body="$1"
	local message
	message="$(printf '%s' "$body" | grep -o '"message":"[^"]*"' | head -n 1 | cut -d '"' -f 4 || true)"
	[[ -n "$message" ]] || message="unexpected answer from Cloudflare"
	printf '%s' "$message" | LC_ALL=C tr -cd '[:print:]' | cut -c 1-100
	return 0
}

# The host name of a site address, lower case, without scheme, user, port or path.
cdn_host() {
	local rest="${1#*://}"
	rest="${rest%%/*}"
	rest="${rest##*@}"
	rest="${rest%%:*}"
	printf '%s' "$rest" | LC_ALL=C tr '[:upper:]' '[:lower:]'
	return 0
}

# Finds the zone of a host, trying the host and then each parent domain
# (a.b.example.co.uk, b.example.co.uk, example.co.uk). Sets CF_ZONE_ID and
# CF_ZONE_NAME; on failure returns 1 with CF_ERR.
cdn_zone() {
	local candidate="$1"
	local host="$1"
	local body id
	CF_ZONE_ID="" CF_ZONE_NAME="" CF_ERR=""
	while [[ "$candidate" == *.* ]]; do
		body="$(cf_api GET "/zones?name=$candidate")" || {
			CF_ERR="cannot reach the Cloudflare API"
			return 1
		}
		if [[ "$body" != *'"success":true'* ]]; then
			CF_ERR="$(cf_message "$body")"
			return 1
		fi
		id="$(printf '%s' "$body" | sed -n 's/.*"result":\[{"id":"\([0-9a-f]\{32\}\)".*/\1/p')"
		if [[ -n "$id" ]]; then
			CF_ZONE_ID="$id"
			CF_ZONE_NAME="$candidate"
			return 0
		fi
		candidate="${candidate#*.}"
	done
	CF_ERR="no Cloudflare zone for $host"
	return 1
}

# Looks up the zone of one site address. By default (--cloudflare-purge
# hosts) it adds the host to CF_PLAN ("ZONE_ID<TAB>ZONE<TAB>HOST" lines, no
# duplicates) for cdn_purge_hosts or cdn_list_hosts. With --cloudflare-purge
# zone it purges (or, in a dry run, only names) the whole zone, once per zone
# in a run. Sets CDN_STATUS to planned, purged, would-purge or "failed MESSAGE".
cdn_site() {
	local url="$1"
	local host body known
	CDN_STATUS=""
	host="$(cdn_host "$url")"
	if [[ ! "$host" =~ ^[a-z0-9.-]+$ ]]; then
		CDN_STATUS="failed no host name in $url"
	elif ! cdn_zone "$host"; then
		CDN_STATUS="failed $CF_ERR"
	fi
	if [[ -n "$CDN_STATUS" ]]; then
		CF_LOOKUP_FAILED=$((CF_LOOKUP_FAILED + 1))
		[[ "$APPLY" -eq 1 ]] || printf '  Cloudflare: %s: %s\n' "$url" "$CDN_STATUS" >&2
		return 0
	fi
	if [[ "$CF_PURGE" == "$CF_MODE_HOSTS" ]]; then
		if ! printf '%s' "$CF_PLAN" | awk -F '\t' -v z="$CF_ZONE_ID" -v h="$host" '$1 == z && $3 == h { found = 1 } END { exit !found }'; then
			CF_PLAN+="$CF_ZONE_ID"$'\t'"$CF_ZONE_NAME"$'\t'"$host"$'\n'
		fi
		CDN_STATUS="planned"
		return 0
	fi
	known="$(awk -F '\t' -v z="$CF_ZONE_ID" '$1 == z { print $2; exit }' <<<"$CF_DONE")"
	if [[ -z "$known" ]]; then
		if [[ "$APPLY" -eq 1 ]]; then
			if body="$(cf_api POST "/zones/$CF_ZONE_ID/purge_cache" '{"purge_everything":true}')" && [[ "$body" == *'"success":true'* ]]; then
				known="purged"
				CF_PURGED=$((CF_PURGED + 1))
			else
				known="failed $([[ -n "${body:-}" ]] && cf_message "$body" || printf 'cannot reach the Cloudflare API')"
				CF_FAILED=$((CF_FAILED + 1))
			fi
		else
			known="would-purge"
			printf '  Cloudflare: %s is in zone %s; --apply would purge it\n' "$host" "$CF_ZONE_NAME"
		fi
		CF_DONE+="$CF_ZONE_ID"$'\t'"$known"$'\n'
	fi
	CDN_STATUS="$known"
	return 0
}

# One purge request for up to 30 host names (Cloudflare's limit) of a zone.
# Adds to CF_HOSTS_PURGED, or sets CF_HOSTS_FAILED to the first failure.
cdn_post_hosts() {
	local zone_id="$1"
	local json="$2"
	local count="$3"
	local body=""
	if body="$(cf_api POST "/zones/$zone_id/purge_cache" "{\"hosts\":[$json]}")" && [[ "$body" == *'"success":true'* ]]; then
		CF_PURGED=$((CF_PURGED + 1))
		CF_HOSTS_PURGED=$((CF_HOSTS_PURGED + count))
	else
		CF_FAILED=$((CF_FAILED + 1))
		[[ -n "$CF_HOSTS_FAILED" ]] || CF_HOSTS_FAILED="failed $([[ -n "$body" ]] && cf_message "$body" || printf 'cannot reach the Cloudflare API')"
	fi
	return 0
}

# Purges the hosts in CF_PLAN, one request per zone and 30 hosts, then empties
# it. Sets CDN_STATUS to purged(N hosts) or the first failure.
cdn_purge_hosts() {
	local zone_id zone_name host json count
	CF_HOSTS_PURGED=0
	CF_HOSTS_FAILED=""
	while IFS=$'\t' read -r zone_id zone_name; do
		[[ -n "$zone_id" ]] || continue
		json="" count=0
		while IFS= read -r host; do
			json+="${json:+,}\"$host\""
			count=$((count + 1))
			if [[ "$count" -eq 30 ]]; then
				cdn_post_hosts "$zone_id" "$json" "$count"
				json="" count=0
			fi
		done < <(awk -F '\t' -v z="$zone_id" '$1 == z { print $3 }' <<<"$CF_PLAN")
		[[ "$count" -eq 0 ]] || cdn_post_hosts "$zone_id" "$json" "$count"
	done < <(awk -F '\t' '!seen[$1]++ { print $1 "\t" $2 }' <<<"$CF_PLAN")
	CF_PLAN=""
	if [[ -n "$CF_HOSTS_FAILED" ]]; then
		CDN_STATUS="$CF_HOSTS_FAILED"
	else
		CDN_STATUS="purged($CF_HOSTS_PURGED host$([[ "$CF_HOSTS_PURGED" -eq 1 ]] || printf s))"
	fi
	return 0
}

# Dry run: names the hosts it would purge, per zone.
cdn_list_hosts() {
	local zone_id zone_name hosts
	while IFS=$'\t' read -r zone_id zone_name; do
		[[ -n "$zone_id" ]] || continue
		hosts="$(awk -F '\t' -v z="$zone_id" '$1 == z { printf "%s%s", sep, $3; sep = " " }' <<<"$CF_PLAN")"
		printf '  Cloudflare: zone %s: --apply would purge %s host(s) only: %s\n' "$zone_name" "$(wc -w <<<"$hosts" | tr -d ' ')" "$hosts"
	done < <(awk -F '\t' '!seen[$1]++ { print $1 "\t" $2 }' <<<"$CF_PLAN")
	return 0
}

# The cdn= value for the addresses of one install (one per line): purged, or
# the first failure. Every address is tried, even after a failure. By default
# the install's hosts are purged together, one request per zone and 30 hosts;
# with --cloudflare-purge zone each zone is purged once per install.
cdn_result() {
	local urls="$1"
	local url
	CDN_RESULT="-"
	if [[ "$APPLY" -eq 1 ]]; then
		CF_DONE=""
		CF_PLAN=""
	fi
	while IFS= read -r url; do
		[[ -n "$url" ]] || continue
		cdn_site "$url"
		if [[ "$CDN_STATUS" == failed* ]]; then
			[[ "$CDN_RESULT" == failed* ]] || CDN_RESULT="$CDN_STATUS"
		elif [[ "$CDN_RESULT" != failed* ]]; then
			CDN_RESULT="purged"
		fi
	done <<<"$urls"
	if [[ "$CF_PURGE" == "$CF_MODE_HOSTS" && "$APPLY" -eq 1 && -n "$CF_PLAN" ]]; then
		cdn_purge_hosts
		if [[ "$CDN_STATUS" == failed* ]]; then
			[[ "$CDN_RESULT" == failed* ]] || CDN_RESULT="$CDN_STATUS"
		elif [[ "$CDN_RESULT" != failed* ]]; then
			CDN_RESULT="$CDN_STATUS"
		fi
	fi
	return 0
}

# Passes the host's output through. With a token, @cdn lines (the sites of an
# install) are read and not shown; cdn=@CDN@ on an install line becomes the
# result of purging those sites' zones. A dry run lists the zones instead.
stream_filter() {
	local line pending="" url
	if [[ -z "$CF_TOKEN" ]]; then
		cat
		return 0
	fi
	while IFS= read -r line || [[ -n "$line" ]]; do
		case "$line" in
		$'@cdn\t'*)
			url="${line#@cdn$'\t'}"
			if [[ "$APPLY" -eq 1 ]]; then
				pending+="$url"$'\n'
			else
				cdn_site "$url"
			fi
			;;
		*'cdn=@CDN@'*)
			cdn_result "$pending"
			pending=""
			printf '%s\n' "${line%%cdn=@CDN@*}cdn=$CDN_RESULT${line#*cdn=@CDN@}"
			;;
		*) printf '%s\n' "$line" ;;
		esac
	done
	if [[ "$APPLY" -eq 1 ]]; then
		printf '\nCloudflare: %s purge request(s) (%s), %s failed; %s site(s) with no zone found.\n' "$CF_PURGED" "$CF_PURGE" "$CF_FAILED" "$CF_LOOKUP_FAILED"
	else
		[[ "$CF_PURGE" != "$CF_MODE_HOSTS" ]] || cdn_list_hosts
	fi
	if [[ "$APPLY" -ne 1 && "$CF_LOOKUP_FAILED" -gt 0 ]]; then
		printf '\nCloudflare: %s site(s) with no zone found (named above); --apply would not purge them.\n' "$CF_LOOKUP_FAILED" >&2
	fi
	return 0
}

dry_run() {
	local command status=0
	command="$(remote_words env "DEPLOY_WP_CLI=$WP_CLI" "DEPLOY_CDN_PURGE=$([[ -n "$CF_TOKEN" ]] && printf 1 || printf 0)" bash -s -- list "$SLUG" "$PARENT" "--version=$VERSION" ${DOWNGRADE_ARGS[@]+"${DOWNGRADE_ARGS[@]}"} ${SKIPS[@]+"${SKIPS[@]}"})"
	printf '\nInstalls of %s on %s (name, version, kind, folder):\n' "$SLUG" "$HOST"
	set +e
	remote "$command" <"$REMOTE_PART" | stream_filter
	status="${PIPESTATUS[0]}"
	set -e
	[[ "$status" -eq 0 ]] || die "the dry run on $HOST failed"
	printf '\nDry run: nothing changed. Run again with --apply to install %s.\n' "$TAG"
	return 0
}

# Runs on the host (bash -s): removes old run folders of this plugin, keeping
# the current run and every run of the newest KEEP tags. Only directories named
# v<version>-<YYYYMMDDTHHMMSSZ> are touched, nothing is removed while a
# deploy holds the lock, and a folder with anything changed in the last two
# hours is kept: a run copies its zip before it takes the lock, and another
# deploy may start after the lock check.
# shellcheck disable=SC2016 # The host expands these, not this shell.
readonly PRUNE_REMOTE='
prune() {
	local base="$1"
	local keep="$2"
	local current="$3"
	local runs="" tags d size count=0 kb=0
	cd "$HOME/$base" 2>/dev/null || return 0
	if [ -d .lock ]; then echo "skipped: another deploy holds the lock"; return 0; fi
	for d in v*-*Z; do
		[ -d "$d" ] && [ ! -L "$d" ] || continue
		printf "%s\n" "$d" | grep -Eq "^v[0-9]+\.[0-9]+\.[0-9]+-[0-9]{8}T[0-9]{6}Z$" || continue
		runs="$runs$d
"
	done
	[ -n "$runs" ] || return 0
	tags="$(printf "%s" "$runs" | sed "s/-[0-9]*T[0-9]*Z$//" | sort -u | sort -t. -k1.2,1nr -k2,2nr -k3,3nr | head -n "$keep")"
	for d in $(printf "%s" "$runs"); do
		[ "$d" != "$current" ] || continue
		printf "%s\n" "$tags" | grep -qxF "${d%-*}" && continue
		[ -z "$(find "$d" -mmin -120 2>/dev/null | head -n 1)" ] || continue
		size="$(du -sk "$d" 2>/dev/null | cut -f1)"
		if rm -rf "$d"; then
			count=$((count + 1)); kb=$((kb + ${size:-0}))
			echo "removed $d"
		fi
	done
	echo "pruned $count run folder(s), freed $((kb / 1024)) MB"
	return 0
}
prune "$@"
'

# After a successful install: keep the current run and the newest KEEP_RELEASES
# tags on the host. A failure here only warns; the deploy has succeeded.
prune_host() {
	local current="$1"
	local out
	[[ "$KEEP_RELEASES" -gt 0 ]] || return 0
	if out="$(remote "bash -s -- $(remote_words ".$SLUG-deploy" "$KEEP_RELEASES" "$current")" <<<"$PRUNE_REMOTE")"; then
		printf '\nOld run folders on %s (keeping the newest %s tags):\n%s\n' "$HOST" "$KEEP_RELEASES" "  ${out//$'\n'/$'\n'  }"
	else
		printf '\nWARN could not remove old run folders on %s (the deploy itself succeeded).\n' "$HOST" >&2
	fi
	return 0
}

apply() {
	local stamp base run dir command status=0
	stamp="$(date -u +%Y%m%dT%H%M%SZ)"
	# In the host's home folder, mode 700. The slug and tag are plain
	# [a-z0-9.-] names, so they need no quoting there.
	base=".$SLUG-deploy"
	run="$base/$TAG-$stamp"
	dir="$(remote "umask 077 && cd && mkdir -p $run && chmod 700 $base $run && cd $run && pwd")" ||
		die "cannot make a private folder on $HOST"
	[[ "$dir" == /* ]] || die "unexpected folder from $HOST: $dir"
	remote "umask 077; cat >$(remote_words "$dir/$SLUG-$VERSION.zip")" <"$ZIP" || die "cannot copy the zip to $HOST"
	remote "umask 077; cat >$(remote_words "$dir/deploy-remote.sh")" <"$REMOTE_PART" || die "cannot copy the remote part to $HOST"
	remote "chmod 600 $(remote_words "$dir/$SLUG-$VERSION.zip" "$dir/deploy-remote.sh")" || die "cannot set the files' mode on $HOST"
	printf '\nInstalling %s on %s (folder %s):\n' "$TAG" "$HOST" "$dir"
	command="$(remote_words env "DEPLOY_WP_CLI=$WP_CLI" "DEPLOY_WEB_ERROR_LOG=$WEB_ERROR_LOG" "DEPLOY_CRON_TIMEOUT=${DEPLOY_CRON_TIMEOUT:-120}" "DEPLOY_CDN_PURGE=$([[ -n "$CF_TOKEN" ]] && printf 1 || printf 0)" bash "$dir/deploy-remote.sh" apply "$SLUG" "$PARENT" \
		"$VERSION" "$dir/$SLUG-$VERSION.zip" "$SHA" "$dir/backups" ${DOWNGRADE_ARGS[@]+"${DOWNGRADE_ARGS[@]}"} ${SKIPS[@]+"${SKIPS[@]}"})"
	set +e
	remote "$command" | stream_filter
	status="${PIPESTATUS[0]}"
	set -e
	if [[ "$status" -eq 3 ]]; then
		printf '\nAnother deploy of %s is running on %s (named above), so nothing was installed. Wait for it to finish, then run again.\n' "$SLUG" "$HOST" >&2
		exit 3
	fi
	if [[ "$status" -ne 0 ]]; then
		printf '\nDeploy of %s on %s failed (exit %s): see the FAIL lines and their restore commands above.\n' "$TAG" "$HOST" "$status"
		return 1
	fi
	printf '\nDeployed %s on %s. To undo one install: rm -rf its wp-content/plugins/%s, then tar -xzf its backup into wp-content/plugins.\n' "$TAG" "$HOST" "$SLUG"
	prune_host "$TAG-$stamp"
	return 0
}

main() {
	parse_args "$@"
	command -v gh >/dev/null 2>&1 || die "needs gh (GitHub CLI)"
	command -v ssh >/dev/null 2>&1 || die "needs ssh"
	command -v sha256sum >/dev/null 2>&1 || command -v shasum >/dev/null 2>&1 || die "needs sha256sum or shasum"
	local root
	root="$(git rev-parse --show-toplevel)" || die "run this inside a checkout of the plugin"
	cd "$root"
	plugin_identity HEAD || die "cannot tell which plugin this is"
	SLUG="$PLUGIN_SLUG"
	REPO="$PLUGIN_REPO"
	[[ "$REPO" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || die "the main file has no GitHub Plugin URI header (owner/repo)"

	trap cleanup EXIT
	TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/$SLUG-deploy.XXXXXX")"
	download_zip
	if [[ "$APPLY" -eq 1 ]]; then
		apply || return 1
	else
		dry_run
	fi
	return 0
}

main "$@"
