#!/usr/bin/env bash
# Copy the core files (scripts/core-files.txt) from the starter plugin into
# this plugin, with this plugin's names. Core files hold no code for one
# plugin, so after a sync they match the starter apart from the names.
#
# Usage: scripts/sync-core.sh [--check] [--from DIR] [--ref REF]
#   --check     Change nothing; list core files that differ from the starter's
#               and exit 1 if any do (scripts/preflight-release.sh warns).
#   --from DIR  A checkout of the starter (default: <PREFIX>_STARTER_DIR, then
#               <STARTER_REPO_DIR> next to this repository).
#   --ref REF   Starter commit, branch or tag to copy from (default: HEAD of
#               that checkout; use origin/main after a git fetch there).
#
# The list of core files and their contents come from the starter at REF;
# the plugin's names come from this repository's main file at HEAD.
# Review the changes with git diff, then commit them.

# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Marcus Quinn
# Additional terms (GPL-3.0 section 7(b)): ATTRIBUTION.txt

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
# shellcheck source=scripts/lib/plugin.sh disable=SC1091 # followed only with -x
. "$SCRIPT_DIR/lib/plugin.sh"

# Split the starter slug so plugin_map leaves its repository name unchanged.
readonly STARTER_REPO_DIR="wp-plugin-""starter-template-for-ai-coding"

die() {
	local message="$1"
	printf 'sync-core: %s\n' "$message" >&2
	exit 2
}

TMP_FILE=""
LIST_FILE=""
# The file being swapped in, removed if the run stops.
NEW_FILE=""

cleanup() {
	[[ -z "$TMP_FILE" ]] || rm -f "$TMP_FILE"
	[[ -z "$LIST_FILE" ]] || rm -f "$LIST_FILE"
	[[ -z "$NEW_FILE" ]] || rm -f "$NEW_FILE"
	return 0
}

# A core path must stay inside the plugin: not absolute, no .. segment.
check_path() {
	local path="$1"
	case "/$path/" in
	//* | */../*) die "scripts/core-files.txt lists $path, which is outside the plugin" ;;
	*) ;;
	esac
	return 0
}

# A target is written only through real folders of the plugin: neither it
# nor a folder above it may be a symbolic link, which could point outside.
check_target() {
	local target="$1"
	local dir
	[[ ! -L "$target" ]] || die "$target is a symbolic link; core files are written only inside the plugin"
	dir="$(dirname "$target")"
	while [[ "$dir" != "." && "$dir" != "/" ]]; do
		[[ ! -L "$dir" ]] || die "$dir is a symbolic link; core files are written only inside the plugin"
		dir="$(dirname "$dir")"
	done
	return 0
}

# Whether a file's executable bit matches a Git mode (100755 or 100644).
same_mode() {
	local file="$1"
	local mode="$2"
	if [[ "$mode" = "100755" ]]; then
		[[ -x "$file" ]] || return 1
	elif [[ -x "$file" ]]; then
		return 1
	fi
	return 0
}

usage() {
	sed -n '2,17p' "$0" | sed -e 's/^# \{0,1\}//' -e "s/<STARTER_REPO_DIR>/$STARTER_REPO_DIR/"
	return 0
}

# Core paths at the starter ref, one per line, with directories expanded,
# into FILE. Stops when the list cannot be read or comes out empty, so a
# failure never reads as "all 0 core files match".
core_paths() {
	local from="$1"
	local ref="$2"
	local out="$3"
	local list line files
	list="$(git -C "$from" show "$ref:scripts/core-files.txt" 2>/dev/null)" ||
		die "no scripts/core-files.txt in the starter at $ref"
	: >"$out"
	while IFS= read -r line; do
		case "$line" in
		*/)
			files="$(git --literal-pathspecs -C "$from" ls-tree -r --name-only "$ref" -- "$line")" ||
				die "cannot list $line in the starter at $ref"
			[[ -n "$files" ]] || die "scripts/core-files.txt lists $line, which has no files in the starter at $ref"
			printf '%s\n' "$files" >>"$out"
			;;
		*) printf '%s\n' "$line" >>"$out" ;;
		esac
	done < <(printf '%s\n' "$list" | sed -e 's/[[:space:]]*$//' -e '/^#/d' -e '/^$/d')
	[[ -s "$out" ]] || die "scripts/core-files.txt in the starter at $ref lists no files"
	return 0
}

main() {
	local check=0 from="" ref="HEAD"
	while [[ $# -gt 0 ]]; do
		local arg="$1"
		local value="${2:-}"
		case "$arg" in
		--check) check=1 ;;
		--from)
			[[ $# -ge 2 ]] || die "--from needs a value"
			from="$value"
			shift
			;;
		--ref)
			[[ $# -ge 2 ]] || die "--ref needs a value"
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

	if [[ -z "$from" ]]; then
		from="$(plugin_env STARTER_DIR "$(dirname "$root")/$STARTER_REPO_DIR")"
	fi
	[[ -d "$from" ]] || die "no starter checkout at $from; clone it there or pass --from DIR"
	from="$(cd "$from" && pwd)"
	[[ "$from" != "$root" ]] || die "this is the starter; run it in a plugin made from the starter"
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
	LIST_FILE="$(mktemp "${TMPDIR:-/tmp}/sync-core-list.XXXXXX")"
	core_paths "$from" "$ref" "$LIST_FILE"
	local tmp="$TMP_FILE"
	while IFS= read -r path; do
		check_path "$path"
		target="$(printf '%s' "$path" | plugin_map)"
		check_path "$target"
		check_target "$target"
		# A literal pathspec: a name such as file[1].php is that file only.
		mode="$(git --literal-pathspecs -C "$from" ls-tree "$ref" -- "$path" | awk '{ print $1 }')"
		case "$mode" in
		100644 | 100755) ;;
		*) die "$path in the starter at $ref is not one regular file (mode '$mode')" ;;
		esac
		git -C "$from" show "$ref:$path" | plugin_map "$target" >"$tmp"
		count=$((count + 1))
		if [[ -f "$target" ]] && cmp -s "$tmp" "$target" && same_mode "$target" "$mode"; then
			continue
		fi
		differ=$((differ + 1))
		if [[ "$check" -eq 1 ]]; then
			if [[ ! -f "$target" ]]; then
				printf '  missing  %s\n' "$target"
			elif cmp -s "$tmp" "$target"; then
				printf '  mode     %s (executable bit)\n' "$target"
			else
				printf '  differs  %s\n' "$target"
			fi
			continue
		fi
		mkdir -p "$(dirname "$target")"
		# Replace by rename, never in place: bash reads a running script as it
		# goes, so rewriting scripts/sync-core.sh itself would break this run.
		NEW_FILE="$target.sync-core-new"
		# Never write through a leftover file or link of that name.
		rm -f "$NEW_FILE"
		cp "$tmp" "$NEW_FILE"
		if [[ "$mode" = "100755" ]]; then chmod 755 "$NEW_FILE"; else chmod 644 "$NEW_FILE"; fi
		mv -f "$NEW_FILE" "$target"
		NEW_FILE=""
		printf '  updated  %s\n' "$target"
	done <"$LIST_FILE"

	if [[ "$check" -eq 1 ]]; then
		if [[ "$differ" -eq 0 ]]; then
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
