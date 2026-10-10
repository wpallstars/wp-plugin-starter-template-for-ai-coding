#!/usr/bin/env bash
# Rewrite README.md's badges block in the starter's three rows (STANDARDS.md
# → Structure): status, then requirements and size, then the languages
# chart. The repository comes from the main file's GitHub Plugin URI header,
# the requirements from readme.txt's header. The block keeps the services it
# already shows (SonarCloud, Codacy, CodeFactor, OpenSSF Scorecard); add one
# only once that service has the repository (DEVELOPMENT.md → Services
# setup). Running it again changes nothing.
#
# Usage: scripts/readme-badges.sh [--add SERVICE]... [--codacy ID] [--check]
#   --add SERVICE  Also show sonarcloud, codefactor or scorecard.
#   --codacy ID    Show Codacy's grade: ID is the project badge ID, the end of
#                  the badge address Codacy gives (.../project/badge/Grade/ID).
#   --check        Change nothing; print the block it would write and exit 1
#                  when README.md's differs.
#
# Reads README.md and readme.txt from the working tree. Review with git diff.

# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Marcus Quinn
# Additional terms (GPL-3.0 section 7(b)): ATTRIBUTION.txt

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
# shellcheck source=scripts/lib/plugin.sh disable=SC1091 # followed only with -x
. "$SCRIPT_DIR/lib/plugin.sh"

TMP_FILE=""

die() {
	local message="$1"
	printf 'readme-badges: %s\n' "$message" >&2
	exit 2
}

cleanup() {
	[[ -z "$TMP_FILE" ]] || rm -f "$TMP_FILE"
	return 0
}

usage() {
	sed -n '2,17p' "$0" | sed 's/^# \{0,1\}//'
	return 0
}

main() {
	local check=0 codacy="" extra=""
	while [[ $# -gt 0 ]]; do
		local arg="$1"
		local value="${2:-}"
		case "$arg" in
		--add | --codacy)
			[[ $# -ge 2 ]] || die "$arg needs a value"
			if [[ "$arg" = --add ]]; then
				case "$value" in
				sonarcloud | codefactor | scorecard) extra="$extra $value" ;;
				*) die "--add takes sonarcloud, codefactor or scorecard, not '$value'" ;;
				esac
			else
				[[ "$value" =~ ^[0-9A-Za-z]+$ ]] || die "--codacy '$value' is not a badge ID (letters and digits)"
				codacy="$value"
			fi
			shift
			;;
		--check) check=1 ;;
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
	[[ -n "$PLUGIN_REPO" ]] || die "$PLUGIN_MAIN_FILE has no GitHub Plugin URI header (owner/repo)"
	[[ -f README.md ]] || die "no README.md"
	[[ -f readme.txt ]] || die "no readme.txt (the requirements come from its header)"
	if ! grep -qxF "$PLUGIN_BADGES_START" README.md || ! grep -qxF "$PLUGIN_BADGES_END" README.md; then
		die "README.md needs the lines $PLUGIN_BADGES_START and $PLUGIN_BADGES_END under its title"
	fi

	local current block
	current="$(plugin_badges_current <README.md)"
	[[ -n "$codacy" ]] || codacy="$(plugin_badge_codacy "$current")"
	block="$(plugin_badges "$PLUGIN_REPO" "$(<readme.txt)" "$(plugin_badge_services "$current")$extra" "$codacy")"
	if [[ "$block" = "$current" ]]; then
		printf 'readme-badges: README.md badges block is up to date\n'
		return 0
	fi
	if [[ "$check" -eq 1 ]]; then
		printf 'readme-badges: README.md badges block differs; it would be:\n%s\n' "$block"
		return 1
	fi
	trap cleanup EXIT
	TMP_FILE="$(mktemp "${TMPDIR:-/tmp}/readme-badges.XXXXXX")"
	plugin_badges_replace "$block" <README.md >"$TMP_FILE"
	# Write in place (cat, not mv), so README.md keeps its mode.
	cat "$TMP_FILE" >README.md
	printf 'readme-badges: rewrote README.md badges block\n'
	return 0
}

main "$@"
