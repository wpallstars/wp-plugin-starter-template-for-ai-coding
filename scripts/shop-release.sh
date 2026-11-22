#!/usr/bin/env bash
# Publish a licensed plugin's release zip to its product in the wpallstars.com
# shop (FluentCart Pro), or check what a licensed site is offered. Shop only:
# never tags, creates GitHub releases or touches WordPress.org.
#
# Usage: scripts/shop-release.sh --host SSH_HOST --path WP_ROOT --ref REF
#                                [--url URL] [--wp-cli COMMAND] [--apply]
#        scripts/shop-release.sh --host SSH_HOST --check-site WP_ROOT
#                                [--url URL] [--wp-cli COMMAND]
#   --host SSH_HOST    The host as ssh knows it (an alias in ~/.ssh/config).
#   --path WP_ROOT     The shop's WordPress folder on the host.
#   --url URL          The site's address, for a multisite network (the shop,
#                      or the site checked).
#   --ref REF          Commit, branch or tag to build (scripts/build-release.sh
#                      --ref: files from Git, never the working tree).
#   --apply            Publish. Without it, only print what would change.
#   --check-site WP_ROOT  Read-only: on that WordPress folder (the product
#                      installed, its licence valid), ask the shop for the
#                      product's version, download the offered package and
#                      print its version, size, SHA-256, entry count and
#                      main-file Version:, never the signed package address.
#                      The product must be updated from the shop (its Update
#                      URI). The offer is asked of the licence library
#                      directly: the site's update_plugins / update_themes
#                      are not rewritten; only the library's own cached
#                      answer for the product is dropped, and put back when
#                      it ends, even after a failure.
#   --wp-cli COMMAND   WP-CLI on the host (default: wp).
#
# Only for a licensed plugin: the main file has `Update URI:
# https://www.wpallstars.com/`, `Licence Item: <product ID>` and no GitHub
# Plugin URI (STANDARDS.md, Licensed updates). The product in the shop must
# be titled as the Plugin Name header, with licence settings on and exactly
# one download row, and the version must be newer than the product's licence
# version. --apply writes a JSON backup (mode 600) of the download row,
# licence settings and update changelog to ~/.wpallstars-shop/backups on the
# host, copies the zip into FluentCart's storage beside the old one (kept
# for a rollback), points the download row at it, sets the licence version
# and the update changelog (the version's changelog.txt section, else
# readme.txt's, without the Developers: lines), touches the product and
# reads it all back (scripts/lib/shop-release-remote.php, run with wp
# eval-file). The copies sent to the host (a mode 700 folder) are removed
# afterwards.
#
# Rollback: put the backup's download row and meta rows back (by ID) with
# wp eval-file; the old zip is still in uploads/fluent-cart/. A first release
# has no row to restore: delete the rows the backup's "inserted" names
# (download_id in fct_product_downloads, changelog_row_id in
# fct_product_meta) and restore only the rows "absent" does not mark absent.
#
# Host names, folders and backups stay out of the repository: only arguments.
# Needs git, ssh and scp here, and WP-CLI on the host.
#
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Marcus Quinn
# Additional terms (GPL-3.0 section 7(b)): ATTRIBUTION.txt
# Provenance: wpas-e4502af0f07e8a92. Copies, even of part, keep these lines.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
readonly REMOTE_PHP="$SCRIPT_DIR/lib/shop-release-remote.php"
# shellcheck disable=SC2088 # The host expands the ~, not this shell.
readonly REMOTE_BASE="~/.wpallstars-shop"
# shellcheck source=scripts/lib/plugin.sh disable=SC1091 # followed only with -x
. "$SCRIPT_DIR/lib/plugin.sh"

HOST=""
WP_ROOT=""
SITE_URL=""
REF=""
CHECK_ROOT=""
WP_CLI="wp"
APPLY=0
TMP_DIR=""
REMOTE_DIR=""
ITEM=""

die() {
	local message="$1"
	printf 'shop-release: %s\n' "$message" >&2
	exit 2
}

usage() {
	# The comment block under the first line, up to the first blank line.
	awk 'NR == 1 { next } /^$/ { exit } { sub(/^# ?/, ""); print }' "$0"
	return 0
}

# The words, each quoted for the remote shell, joined by spaces.
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

cleanup() {
	if [[ -n "$REMOTE_DIR" ]]; then
		remote "rm -rf $REMOTE_DIR" || printf 'shop-release: could not remove %s on the host\n' "$REMOTE_DIR" >&2
	fi
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

parse_args() {
	while [[ $# -gt 0 ]]; do
		local arg="$1"
		local value="${2:-}"
		case "$arg" in
		--host | --path | --url | --ref | --check-site | --wp-cli)
			[[ $# -ge 2 ]] || die "$arg needs a value"
			[[ "$value" != -* ]] || die "$arg needs a value, not an option: $value"
			case "$arg" in
			--host) HOST="$value" ;;
			--path) WP_ROOT="$value" ;;
			--url) SITE_URL="$value" ;;
			--ref) REF="$value" ;;
			--check-site) CHECK_ROOT="$value" ;;
			--wp-cli) WP_CLI="$value" ;;
			*) ;; # The outer pattern lists every option that takes a value.
			esac
			shift
			;;
		--apply) APPLY=1 ;;
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
	if [[ -n "$CHECK_ROOT" ]]; then
		[[ -z "$REF" && -z "$WP_ROOT" && "$APPLY" -eq 0 ]] || die "--check-site takes only --host, --url and --wp-cli"
	else
		[[ -n "$WP_ROOT" ]] || die "--path (the shop's WordPress folder) is required"
		[[ -n "$REF" ]] || die "--ref is required"
	fi
	return 0
}

# Read the plugin at a ref and check it is a licensed plugin; sets ITEM.
identify() {
	local ref="$1"
	plugin_identity "$ref" || die "cannot tell which plugin this is at $ref"
	[[ "$PLUGIN_SELF_UPDATING" -eq 1 ]] || die "$PLUGIN_MAIN_FILE is not a licensed plugin (an Update URI and no GitHub Plugin URI)"
	[[ "$PLUGIN_UPDATE_URI" =~ ^https://www\.wpallstars\.com/?$ ]] || die "$PLUGIN_MAIN_FILE's Update URI is not https://www.wpallstars.com/"
	local text
	text="$(git show "$ref:$PLUGIN_MAIN_FILE")"
	ITEM="$(plugin_header_field "${text:0:8192}" "Licence Item")"
	[[ "$ITEM" =~ ^[0-9]+$ ]] || die "$PLUGIN_MAIN_FILE has no Licence Item header (the shop's product ID)"
	return 0
}

# Make a private folder on the host for this run, and remember it for cleanup.
# The host allocates it exclusively (mktemp -d), so two runs, even by the same
# user, never share a folder; cleanup removes only the one returned here.
remote_dir() {
	local dir
	dir="$(remote "umask 077 && mkdir -p $REMOTE_BASE/backups && chmod 700 $REMOTE_BASE $REMOTE_BASE/backups && mktemp -d $REMOTE_BASE/run-XXXXXXXXXX")" || dir=""
	if [[ ! "$dir" =~ ^/[A-Za-z0-9._/-]+$ ]]; then
		die "cannot make a private folder on the host"
	fi
	REMOTE_DIR="$dir"
	return 0
}

# Run the remote PHP with WP-CLI in a WordPress folder. The arguments are
# quoted for the remote shell, except paths under ~ (expanded there).
run_php() {
	local root="$1"
	local args="$2"
	local url_arg=""
	[[ -z "$SITE_URL" ]] || url_arg="$(remote_words "--url=$SITE_URL") "
	remote "cd $(remote_words "$root") && $WP_CLI ${url_arg}--skip-themes eval-file $REMOTE_DIR/shop-release-remote.php $args" || return $?
	return 0
}

check_site() {
	identify HEAD
	remote_dir
	scp -q -o BatchMode=yes "$REMOTE_PHP" "$HOST:$REMOTE_DIR/" || die "cannot copy the check to the host"
	run_php "$CHECK_ROOT" "check $(remote_words "$ITEM" "$PLUGIN_SLUG")" || return 1
	return 0
}

release() {
	local root sha zip version changelog=""
	root="$(git rev-parse --show-toplevel)" || die "run this inside a checkout of the plugin"
	cd "$root"
	sha="$(git rev-parse --verify --quiet "$REF^{commit}")" || die "not a commit: $REF"
	identify "$sha"
	TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/$PLUGIN_SLUG-shop.XXXXXX")" || TMP_DIR=""
	[[ -n "$TMP_DIR" && -d "$TMP_DIR" ]] || die "cannot make a temporary folder"
	zip="$("$SCRIPT_DIR/build-release.sh" --ref "$sha" --out "$TMP_DIR" --quiet)" || die "the build failed"
	[[ "$zip" != *$'\n'* ]] || die "the build made more than one zip; a licensed plugin gets one"
	version="$(basename "$zip" .zip)"
	version="${version#"$PLUGIN_SLUG"-}"
	[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "the build is not named $PLUGIN_SLUG-X.Y.Z.zip: $zip"
	local section="^= $version( [^=]*)? ="
	changelog=""
	local candidate text
	for candidate in changelog.txt readme.txt; do
		text="$(git show "$sha:$candidate" 2>/dev/null)" || continue
		if grep -Eq "$section" <<<"$text"; then
			changelog="$candidate"
			break
		fi
	done
	[[ -n "$changelog" ]] || die "neither changelog.txt nor readme.txt at $REF has a = $version = section"
	git show "$sha:$changelog" >"$TMP_DIR/changelog.txt" || die "no $changelog at $REF"
	local digest
	digest="$(sha256_of "$zip")"
	printf '%s %s from %s (%s), product %s, SHA-256 %s\n' "$PLUGIN_NAME" "$version" "$REF" "${sha:0:12}" "$ITEM" "$digest"

	remote_dir
	scp -q -o BatchMode=yes "$zip" "$TMP_DIR/changelog.txt" "$REMOTE_PHP" "$HOST:$REMOTE_DIR/" || die "cannot copy the build to the host"
	local mode="plan"
	[[ "$APPLY" -eq 0 ]] || mode="apply"
	run_php "$WP_ROOT" "$mode $(remote_words "$ITEM" "$PLUGIN_NAME" "$PLUGIN_SLUG") $REMOTE_DIR/$(basename "$zip") $digest $REMOTE_DIR/changelog.txt $REMOTE_BASE/backups" || return 1
	return 0
}

main() {
	parse_args "$@"
	command -v ssh >/dev/null 2>&1 || die "needs ssh"
	command -v scp >/dev/null 2>&1 || die "needs scp"
	trap cleanup EXIT
	if [[ -n "$CHECK_ROOT" ]]; then
		check_site || return 1
	else
		release || return 1
	fi
	return 0
}

main "$@"
