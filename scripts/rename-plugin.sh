#!/usr/bin/env bash
# Give this plugin new names: run it once in a fresh copy of the starter to
# start a new plugin. Renames every tracked file's contents and paths, then
# leaves the changes for you to review and commit.
#
# Usage: scripts/rename-plugin.sh --slug SLUG --name NAME --prefix Prefix
#                                 [--const PREFIX] [--css CSS] [--repo OWNER/REPO]
#   --slug    Plugin folder, main file and text domain (my-plugin).
#   --name    Plugin Name (My Plugin).
#   --prefix  Class prefix (MyPlugin: MyPlugin_Settings).
#   --const   Constant prefix (default: --prefix in capitals, MYPLUGIN). In
#             lower case it is the option, hook and function prefix (myplugin).
#   --css     CSS class and data attribute prefix (default: the lower-case
#             prefix; a short one such as mp keeps the markup readable).
#   --repo    GitHub repository, owner/repo (default: wpallstars/SLUG).
#
# Needs a clean working tree. Then update README.md, readme.txt,
# changelog.txt, AGENTS.md and the banner (STANDARDS.md and DEVELOPMENT.md say how).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
# shellcheck source=scripts/lib/plugin.sh disable=SC1091 # followed only with -x
. "$SCRIPT_DIR/lib/plugin.sh"

die() {
	local message="$1"
	printf 'rename-plugin: %s\n' "$message" >&2
	exit 2
}

TMP_FILE=""

cleanup() {
	[ -z "$TMP_FILE" ] || rm -f "$TMP_FILE"
	return 0
}

usage() {
	sed -n '2,19p' "$0" | sed 's/^# \{0,1\}//'
	return 0
}

need() {
	local flag="$1"
	local value="$2"
	local pattern="$3"
	[ -n "$value" ] || die "$flag is needed (see --help)"
	printf '%s' "$value" | grep -Eq "$pattern" || die "$flag '$value' must match $pattern"
	return 0
}

main() {
	local slug="" name="" prefix="" const="" css="" repo=""
	while [ $# -gt 0 ]; do
		local arg="$1"
		local value="${2:-}"
		case "$arg" in
		--slug | --name | --prefix | --const | --css | --repo)
			[ $# -ge 2 ] || die "$arg needs a value"
			case "$arg" in
			--slug) slug="$value" ;;
			--name) name="$value" ;;
			--prefix) prefix="$value" ;;
			--const) const="$value" ;;
			--css) css="$value" ;;
			--repo) repo="$value" ;;
			esac
			shift
			;;
		-h | --help)
			usage
			return 0
			;;
		*) die "unknown argument: $arg" ;;
		esac
		shift
	done

	[ -n "$const" ] || const="$(printf '%s' "$prefix" | tr '[:lower:]' '[:upper:]')"
	[ -n "$css" ] || css="$(printf '%s' "$const" | tr '[:upper:]' '[:lower:]')"
	[ -n "$repo" ] || repo="wpallstars/$slug"
	need --slug "$slug" '^[a-z][a-z0-9-]*[a-z0-9]$'
	need --name "$name" '^[^/\\]+$'
	need --prefix "$prefix" '^[A-Z][A-Za-z0-9]*$'
	need --const "$const" '^[A-Z][A-Z0-9]*$'
	need --css "$css" '^[a-z][a-z0-9]*$'
	need --repo "$repo" '^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$'

	local root
	root="$(git rev-parse --show-toplevel)" || die "run this inside a checkout of the plugin"
	cd "$root"
	[ -z "$(git status --porcelain)" ] || die "commit or put away your changes first"
	plugin_identity HEAD || die "cannot tell which plugin this is"
	plugin_names_as FROM

	export TO_SLUG="$slug" TO_NAME="$name" TO_PACKAGE="$prefix" TO_CONST="$const"
	export TO_PREFIX
	TO_PREFIX="$(printf '%s' "$const" | tr '[:upper:]' '[:lower:]')"
	export TO_CSS="$css" TO_REPO="$repo"
	[ "$TO_SLUG" != "$FROM_SLUG" ] || die "the slug is already $slug"

	printf 'Renaming %s to %s: %s / %s / %s / %s / %s / %s\n' "$FROM_NAME" "$name" "$slug" "$TO_PREFIX" "$prefix" "$const" "$css" "$repo"

	local file target changed=0 moved=0
	trap cleanup EXIT
	TMP_FILE="$(mktemp "${TMPDIR:-/tmp}/rename-plugin.XXXXXX")"
	local tmp="$TMP_FILE"
	while IFS= read -r file; do
		[ -f "$file" ] || continue
		# Text files only (pictures and other binaries keep their bytes).
		if grep -Iq . "$file"; then
			plugin_map <"$file" >"$tmp"
			if ! cmp -s "$tmp" "$file"; then
				# Replace by rename, never in place: bash reads a running script
				# as it goes, and this file is one of those renamed.
				cp "$tmp" "$file.rename-new"
				if [ -x "$file" ]; then chmod 755 "$file.rename-new"; else chmod 644 "$file.rename-new"; fi
				mv -f "$file.rename-new" "$file"
				changed=$((changed + 1))
			fi
		fi
		target="$(printf '%s' "$file" | plugin_map)"
		if [ "$target" != "$file" ]; then
			mkdir -p "$(dirname "$target")"
			git mv "$file" "$target"
			moved=$((moved + 1))
		fi
	done < <(git ls-files)

	printf '%d files changed, %d renamed. Run composer update --lock (the package name changed), review with git diff and git status, then commit.\n' "$changed" "$moved"
	return 0
}

main "$@"
