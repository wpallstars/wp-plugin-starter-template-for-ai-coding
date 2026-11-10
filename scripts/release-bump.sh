#!/usr/bin/env bash
# Set the release version in one go (RELEASING.md → GitHub release, step 1):
# the main file's Version: and {PREFIX}_VERSION, readme.txt's Stable tag:,
# README.md's Version: line; rename the Unreleased block in changelog.txt,
# readme.txt and README.md to the version; run scripts/readme-badges.sh; print
# readme.txt's byte budget. Safe to run again: after a rebase conflict, take
# main's three changelog files and run it again. The short readme.txt lines
# and any upgrade notice stay hand-written.
#
# Usage: scripts/release-bump.sh X.Y.Z
#
# Edits the working tree only; review with git diff. Nothing is committed.

# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Marcus Quinn
# Additional terms (GPL-3.0 section 7(b)): ATTRIBUTION.txt
# Provenance: wpas-e4502af0f07e8a92. Copies, even of part, keep these lines.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
# shellcheck source=scripts/lib/plugin.sh disable=SC1091 # followed only with -x
. "$SCRIPT_DIR/lib/plugin.sh"

readonly README_MAX_BYTES=10240
TMP_FILE=""

die() {
	local message="$1"
	printf 'release-bump: %s\n' "$message" >&2
	exit 2
}

cleanup() {
	[[ -z "$TMP_FILE" ]] || rm -f "$TMP_FILE"
	return 0
}

usage() {
	sed -n '2,11p' "$0" | sed 's/^# \{0,1\}//'
	return 0
}

# Replace the first line matching the ERE with the new text; fail when none.
replace_line() {
	local file="$1"
	local pattern="$2"
	local replacement="$3"
	grep -Eq "$pattern" "$file" || die "$file has no line matching $pattern"
	TMP_FILE="$(mktemp)"
	awk -v pat="$pattern" -v rep="$replacement" '
		!done && $0 ~ pat { print rep; done = 1; next }
		{ print }' "$file" >"$TMP_FILE"
	cat "$TMP_FILE" >"$file"
	rm -f "$TMP_FILE"
	TMP_FILE=""
	return 0
}

# Rename the Unreleased heading (style eq: "= X =", hash: "### X") to the version.
rename_unreleased() {
	local file="$1"
	local style="$2"
	local version="$3"
	local escaped="${version//./\\.}"
	local unreleased="^= *[Uu]nreleased *=[[:space:]]*$"
	local named="^= *v?${escaped} *=[[:space:]]*$"
	local heading="= $version ="
	if [[ "$style" = "hash" ]]; then
		unreleased="^### *[Uu]nreleased[[:space:]]*$"
		named="^### *v?${escaped}[[:space:]]*$"
		heading="### $version"
	fi
	if ! grep -Eq "$unreleased" "$file"; then
		printf '  %s: no Unreleased block\n' "$file"
		return 0
	fi
	if grep -Eq "$named" "$file"; then
		die "$file has both an Unreleased block and a $version heading; move the Unreleased entries under $version by hand"
	fi
	replace_line "$file" "$unreleased" "$heading"
	printf '  %s: Unreleased -> %s\n' "$file" "$version"
	return 0
}

main() {
	local version="${1:-}"
	case "$version" in
	-h | --help)
		usage
		return 0
		;;
	esac
	[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "usage: scripts/release-bump.sh X.Y.Z (numbers only)"
	trap cleanup EXIT

	local root
	root="$(git rev-parse --show-toplevel)" || die "not in a Git repository"
	cd "$root"
	plugin_identity HEAD || die "cannot tell which plugin this is"
	[[ -n "$PLUGIN_MAIN_FILE" ]] || die "no main plugin file found"
	[[ -n "$PLUGIN_CONST" ]] || die "no VERSION constant found"
	local f
	for f in readme.txt README.md changelog.txt; do
		[[ -f "$f" ]] || die "$f is missing"
	done

	printf 'Setting version %s\n' "$version"
	replace_line "$PLUGIN_MAIN_FILE" '^[[:space:]*]*Version:[[:space:]]' " * Version:           $version"
	replace_line "$PLUGIN_MAIN_FILE" "^define.'${PLUGIN_CONST}_VERSION'" "define('${PLUGIN_CONST}_VERSION', '$version');"
	replace_line readme.txt '^Stable tag:' "Stable tag: $version"
	replace_line README.md '^Version:' "Version: $version"
	rename_unreleased changelog.txt eq "$version"
	rename_unreleased readme.txt eq "$version"
	rename_unreleased README.md hash "$version"

	"$SCRIPT_DIR/readme-badges.sh"

	local bytes left
	bytes="$(wc -c <readme.txt | tr -d ' ')"
	left=$((README_MAX_BYTES - bytes))
	printf 'readme.txt: %s bytes, %s left of %s\n' "$bytes" "$left" "$README_MAX_BYTES"
	if [[ "$left" -le 100 ]]; then
		printf 'readme.txt is within 100 bytes of the limit: combine the version lines into one line per type (Added, Faster, Fixed).\n'
	fi
	printf 'Next: write the short readme.txt lines, then scripts/preflight-release.sh.\n'
	return 0
}

main "$@"
