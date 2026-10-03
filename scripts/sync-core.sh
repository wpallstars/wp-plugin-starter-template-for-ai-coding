#!/usr/bin/env bash
# Copy the core files (scripts/core-files.txt) from the starter plugin into
# this plugin, with this plugin's names. Core files hold no code for one
# plugin, so after a sync they match the starter apart from the names.
#
# Usage: scripts/sync-core.sh [--check] [--from DIR] [--ref REF]
#   --check     Change nothing; list core files that differ from the starter's
#               and exit 1 if any do (scripts/preflight-release.sh warns).
#   --from DIR  A checkout of the starter (default: <PREFIX>_STARTER_DIR, then
#               wp-plugin-starter-template-for-ai-coding next to this repository).
#   --ref REF   Starter commit, branch or tag to copy from (default: HEAD of
#               that checkout; use origin/main after a git fetch there).
#
# The list of core files and their contents come from the starter at REF;
# the plugin's names come from this repository's main file at HEAD.
# Review the changes with git diff, then commit them.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
# shellcheck source=scripts/lib/plugin.sh disable=SC1091 # followed only with -x
. "$SCRIPT_DIR/lib/plugin.sh"

readonly STARTER_REPO_DIR="wp-plugin-starter-template-for-ai-coding"

die() {
	local message="$1"
	printf 'sync-core: %s\n' "$message" >&2
	exit 2
}

TMP_FILE=""

cleanup() {
	[ -z "$TMP_FILE" ] || rm -f "$TMP_FILE"
	return 0
}

usage() {
	sed -n '2,17p' "$0" | sed 's/^# \{0,1\}//'
	return 0
}

# Core paths at the starter ref, one per line, with directories expanded.
core_paths() {
	local from="$1"
	local ref="$2"
	local line
	git -C "$from" show "$ref:scripts/core-files.txt" | sed -e 's/[[:space:]]*$//' -e '/^#/d' -e '/^$/d' | while IFS= read -r line; do
		case "$line" in
		*/) git -C "$from" ls-tree -r --name-only "$ref" -- "$line" ;;
		*) printf '%s\n' "$line" ;;
		esac
	done
	return 0
}

main() {
	local check=0 from="" ref="HEAD"
	while [ $# -gt 0 ]; do
		local arg="$1"
		local value="${2:-}"
		case "$arg" in
		--check) check=1 ;;
		--from)
			[ $# -ge 2 ] || die "--from needs a value"
			from="$value"
			shift
			;;
		--ref)
			[ $# -ge 2 ] || die "--ref needs a value"
			ref="$value"
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

	local root
	root="$(git rev-parse --show-toplevel)" || die "run this inside a checkout of the plugin"
	cd "$root"
	plugin_identity HEAD || die "cannot tell which plugin this is"
	plugin_names_as TO

	if [ -z "$from" ]; then
		from="$(plugin_env STARTER_DIR "$(dirname "$root")/$STARTER_REPO_DIR")"
	fi
	[ -d "$from" ] || die "no starter checkout at $from; clone it there or pass --from DIR"
	from="$(cd "$from" && pwd)"
	[ "$from" != "$root" ] || die "this is the starter; run it in a plugin made from the starter"
	git -C "$from" rev-parse --verify --quiet "$ref^{commit}" >/dev/null || die "not a commit in the starter: $ref"

	cd "$from"
	plugin_identity "$ref" || die "cannot read the starter's names at $ref"
	plugin_names_as FROM
	cd "$root"

	printf 'Core files from %s (%s) into %s, as %s / %s / %s / %s / %s\n' \
		"$FROM_NAME" "$(git -C "$from" rev-parse --short "$ref")" "$TO_NAME" \
		"$TO_SLUG" "$TO_PREFIX" "$TO_PACKAGE" "$TO_CONST" "$TO_CSS"

	local path target mode differ=0 count=0
	trap cleanup EXIT
	TMP_FILE="$(mktemp "${TMPDIR:-/tmp}/sync-core.XXXXXX")"
	local tmp="$TMP_FILE"
	while IFS= read -r path; do
		target="$(printf '%s' "$path" | plugin_map)"
		git -C "$from" show "$ref:$path" | plugin_map >"$tmp"
		count=$((count + 1))
		if [ -f "$target" ] && cmp -s "$tmp" "$target"; then
			continue
		fi
		differ=$((differ + 1))
		if [ "$check" -eq 1 ]; then
			if [ -f "$target" ]; then
				printf '  differs  %s\n' "$target"
			else
				printf '  missing  %s\n' "$target"
			fi
			continue
		fi
		mkdir -p "$(dirname "$target")"
		cp "$tmp" "$target"
		mode="$(git -C "$from" ls-tree "$ref" -- "$path" | awk '{ print $1 }')"
		if [ "$mode" = "100755" ]; then chmod +x "$target"; else chmod -x "$target"; fi
		printf '  updated  %s\n' "$target"
	done < <(core_paths "$from" "$ref")

	if [ "$check" -eq 1 ]; then
		if [ "$differ" -eq 0 ]; then
			printf 'All %d core files match the starter.\n' "$count"
			return 0
		fi
		printf '%d of %d core files differ from the starter. Run scripts/sync-core.sh, or change the starter first.\n' "$differ" "$count"
		return 1
	fi
	printf '%d of %d core files updated. Review with git diff, then commit.\n' "$differ" "$count"
	return 0
}

main "$@"
