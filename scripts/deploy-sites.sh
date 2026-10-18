#!/usr/bin/env bash
# Roll out a published release (RELEASING.md step 5): install its zip on every
# WordPress install on one SSH host that already has the plugin.
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
#                      absolute, or relative to each WordPress folder.
#   --dry-run          List the installs found, with their version and whether
#                      each is a multisite network, and change nothing (the
#                      default).
#   --apply            Install the release on each of them.
#
# The zip ({slug}-X.Y.Z.zip) is downloaded with gh and must match the
# asset's SHA-256 on GitHub and, when the release has one, its provenance
# bundle (gh attestation verify). With --apply it is copied to a private
# folder on the host (~/.{slug}-deploy/<tag>-<time>, mode 700, files 600)
# and checked again there. Then, for each install that already has
# wp-content/plugins/{slug}/{slug}.php (the plugin is never added anywhere):
# a tar backup of the plugin folder, wp plugin install --force (activation
# and network activation are kept), then per site a full load for its
# settings upgrade, a page cache purge (LiteSpeed Cache, when its WP-CLI
# command is there) so pages stop pointing at the old CSS and JS, and a home
# fetch. Networks skip archived, deleted and spam sites and print one
# indented line per site. Each fetch uses a unique query string; cache= lists
# the response's cache headers. WARN cached means a cache ignored query
# strings, so PHP did not run for that fetch; WARN purge failed means
# visitors may still get the old CSS and JS. Each install line gives old ->
# new version, status, purged=N/SITES, home HTTP code, cache headers and new
# log lines; networks add sites=PASSED/TOTAL. Exits 1 on a failed site, a
# version not reached or new log lines, with the restore command. Host names,
# folders and backups stay out of the repository: they are only arguments.
#
# Needs gh (signed in to read a private repository), ssh, and bash, WP-CLI,
# tar and curl on the host. aidevops users can use wp-fleet-helper.sh instead
# (RELEASING.md step 5).

# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Marcus Quinn
# Additional terms (GPL-3.0 section 7(b)): ATTRIBUTION.txt
# Provenance: wpas-e4502af0f07e8a92. Copies, even of part, keep these lines.

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
		--host | --tag | --parent | --skip | --wp-cli | --web-error-log)
			[[ $# -ge 2 ]] || die "$arg needs a value"
			case "$arg" in
			--host) HOST="$value" ;;
			--tag) TAG="$value" ;;
			--parent) PARENT="$value" ;;
			--skip) SKIPS+=("$value") ;;
			--wp-cli) WP_CLI="$value" ;;
			--web-error-log) WEB_ERROR_LOG="$value" ;;
			*) ;; # The outer pattern lists every option that takes a value.
			esac
			shift
			;;
		--apply) APPLY=1 ;;
		--dry-run) APPLY=0 ;;
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
	if [[ "$APPLY" -eq 1 ]]; then
		[[ -n "$WEB_ERROR_LOG" && "$WEB_ERROR_LOG" != "syslog" ]] ||
			die "--apply requires --web-error-log PATH (the verified web PHP log file, not syslog)"
	fi
	return 0
}

# The release's zip, checked against GitHub's SHA-256 of the asset and, when
# the release has one, its provenance bundle. At least one check must apply.
download_zip() {
	local name="$SLUG-$VERSION.zip"
	local bundle="provenance-$SLUG-$VERSION.sigstore.json"
	local assets digest checked=0
	printf 'Release %s of %s\n' "$TAG" "$REPO"
	gh release download "$TAG" --repo "$REPO" --pattern "$name" --dir "$TMP_DIR" ||
		die "cannot download $name from $TAG (is gh signed in?)"
	ZIP="$TMP_DIR/$name"
	SHA="$(sha256_of "$ZIP")"
	# Name and digest of each asset, one per line, compared outside jq.
	assets="$(gh api "repos/$REPO/releases/tags/$TAG" --jq '.assets[] | [.name, (.digest // "")] | @tsv')" ||
		die "cannot read the assets of $TAG"
	digest="$(awk -F '\t' -v n="$name" '$1 == n { print $2 }' <<<"$assets")"
	if [[ -n "$digest" ]]; then
		[[ "$digest" == "sha256:$SHA" ]] || die "$name does not match GitHub's digest ($digest, downloaded sha256:$SHA)"
		printf '  ok   SHA-256 matches the asset on GitHub: %s\n' "$SHA"
		checked=1
	fi
	if awk -F '\t' -v n="$bundle" '$1 == n { found = 1 } END { exit !found }' <<<"$assets"; then
		gh release download "$TAG" --repo "$REPO" --pattern "$bundle" --dir "$TMP_DIR" ||
			die "cannot download $bundle"
		gh attestation verify "$ZIP" --bundle "$TMP_DIR/$bundle" --repo "$REPO" \
			--signer-workflow "$REPO/.github/workflows/release.yml" --source-ref "refs/tags/$TAG" >/dev/null ||
			die "the provenance of $name does not verify (gh attestation verify)"
		printf '  ok   provenance verifies: built by .github/workflows/release.yml from %s\n' "$TAG"
		checked=1
	fi
	[[ "$checked" -eq 1 ]] || die "$name has neither a GitHub digest nor a provenance bundle to check it against"
	return 0
}

dry_run() {
	local command
	command="$(remote_words env "DEPLOY_WP_CLI=$WP_CLI" bash -s -- list "$SLUG" "$PARENT" ${SKIPS[@]+"${SKIPS[@]}"})"
	printf '\nInstalls of %s on %s (name, version, kind, folder):\n' "$SLUG" "$HOST"
	remote "$command" <"$REMOTE_PART" || die "the dry run on $HOST failed"
	printf '\nDry run: nothing changed. Run again with --apply to install %s.\n' "$TAG"
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
	command="$(remote_words env "DEPLOY_WP_CLI=$WP_CLI" "DEPLOY_WEB_ERROR_LOG=$WEB_ERROR_LOG" bash "$dir/deploy-remote.sh" apply "$SLUG" "$PARENT" \
		"$VERSION" "$dir/$SLUG-$VERSION.zip" "$SHA" "$dir/backups" ${SKIPS[@]+"${SKIPS[@]}"})"
	remote "$command" || status=$?
	if [[ "$status" -ne 0 ]]; then
		printf '\nDeploy of %s on %s failed (exit %s): see the FAIL lines and their restore commands above.\n' "$TAG" "$HOST" "$status"
		return 1
	fi
	printf '\nDeployed %s on %s. To undo one install: rm -rf its wp-content/plugins/%s, then tar -xzf its backup into wp-content/plugins.\n' "$TAG" "$HOST" "$SLUG"
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
