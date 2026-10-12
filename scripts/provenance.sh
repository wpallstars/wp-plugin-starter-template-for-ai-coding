#!/usr/bin/env bash
# Provenance IDs (ATTRIBUTION.txt → Provenance): each plugin's own ID, in its
# main file and in the licence lines of the files written for it, so public
# copies can be found by searching code. Plugins send nothing anywhere.
#
# Usage: scripts/provenance.sh id
#        scripts/provenance.sh stamp
#        scripts/provenance.sh search [--all] [--id ID]...
#   id      Print this plugin's ID (the Provenance line in its main file).
#   stamp   Give a plugin made from the starter its own ID when its main file
#           has none or the starter's, then put the Provenance line in each of
#           its own source files (not core files) with the licence lines:
#           added under the pointer to ATTRIBUTION.txt (in the main file,
#           under SPDX-License-Identifier) when missing, and the starter's ID
#           replaced with the plugin's. Other plugins' IDs, in files copied
#           from them, stay. scripts/rename-plugin.sh runs it. Running it
#           again changes nothing.
#   search  Search public code on GitHub (gh, signed in) for the starter's
#           ID, this plugin's and each --id ID, and list the repositories
#           outside the owners' (the starter's and this plugin's), with how
#           many files carry an ID and whether the repository has
#           ATTRIBUTION.txt. --all lists the owners' repositories too. Exits 1
#           when it finds any outside. GitHub indexes default branches only.
#
# Reads and writes the working tree. Review stamp's changes with git diff.

# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Marcus Quinn
# Additional terms (GPL-3.0 section 7(b)): ATTRIBUTION.txt
# Provenance: wpas-e4502af0f07e8a92. Copies, even of part, keep these lines.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
# shellcheck source=scripts/lib/plugin.sh disable=SC1091 # followed only with -x
. "$SCRIPT_DIR/lib/plugin.sh"

# The starter's ID and repository (split, so plugin_map leaves it unchanged).
readonly STARTER_ID="wpas-e4502af0f07e8a92"
readonly STARTER_REPO="wpallstars/wp-plugin-""starter-template-for-ai-coding"
# The starter's slug and prefix as in core file paths (split, as above).
readonly STARTER_SLUG="wp-plugin-""starter-template"
readonly STARTER_PREFIX="wp""starter"
readonly ID_PATTERN='wpas-[0-9a-f]{16}'
readonly LINE_TAIL='. Copies, even of part, keep these lines.'

MAIN_FILE=""
REPO=""
SLUG=""
PREFIX=""

die() {
	local message="$1"
	printf 'provenance: %s\n' "$message" >&2
	exit 2
}

usage() {
	sed -n '2,24p' "$0" | sed 's/^# \{0,1\}//'
	return 0
}

# The main file in the working tree (the top-level PHP file with a Plugin
# Name header) into MAIN_FILE, its GitHub Plugin URI into REPO, the slug into
# SLUG and the prefix (of its <PREFIX>_VERSION constant) into PREFIX.
find_main() {
	local file text found="" const
	for file in *.php; do
		[[ -f "$file" ]] || continue
		text="$(head -c 8192 "$file")"
		[[ -n "$(plugin_header_field "$text" "Plugin Name")" ]] || continue
		[[ -z "$found" ]] || die "more than one main file: $found and $file"
		found="$file"
	done
	[[ -n "$found" ]] || die "no PHP file with a Plugin Name: header at the top of the plugin"
	MAIN_FILE="$found"
	SLUG="${found%.php}"
	text="$(cat "$found")"
	REPO="$(plugin_header_field "${text:0:8192}" "GitHub Plugin URI")"
	const="$(sed -nE "/define\([[:space:]]*['\"][A-Z0-9_]+_VERSION['\"]/{s/.*define\([[:space:]]*['\"]([A-Z0-9_]+)_VERSION['\"].*/\1/p;q;}" <<<"$text")"
	[[ -n "$const" ]] || die "$found does not define a <PREFIX>_VERSION constant"
	PREFIX="$(printf '%s' "$const" | tr '[:upper:]' '[:lower:]')"
	return 0
}

# The ID on the main file's Provenance line, or nothing.
main_id() {
	local text
	text="$(head -c 8192 "$MAIN_FILE")"
	sed -nE "/Provenance:[[:space:]]*$ID_PATTERN/{s/.*Provenance:[[:space:]]*($ID_PATTERN).*/\\1/p;q;}" <<<"$text"
	return 0
}

# Core files (scripts/core-files.txt, with the plugin's slug and prefix in
# place of the starter's, folders expanded), one per line.
core_list() {
	local line
	[[ -f scripts/core-files.txt ]] || return 0
	while IFS= read -r line; do
		line="${line//$STARTER_SLUG/$SLUG}"
		line="${line//$STARTER_PREFIX/$PREFIX}"
		case "$line" in
		*/) git ls-files -- "$line" ;;
		*) printf '%s\n' "$line" ;;
		esac
	done < <(sed -e 's/[[:space:]]*$//' -e '/^#/d' -e '/^$/d' scripts/core-files.txt)
	return 0
}

# The plugin's own source files: tracked PHP, JS, CSS and shell files that
# are not core files, vendor code or minified.
own_files() {
	local core files
	core="$(core_list)"
	files="$(git ls-files -- '*.php' '*.js' '*.css' '*.sh' | grep -Ev '^(vendor|node_modules|dist)/|\.min\.(js|css)$' || true)"
	[[ -n "$files" ]] || return 0
	grep -vxF -f <(printf '%s\n' "$core") <<<"$files" || true
	return 0
}

# Put the Provenance line with ID in FILE (stamp above). REPLACE 1 swaps the
# starter's ID for ID. Returns 1 when the file is unchanged.
stamp_file() {
	local file="$1"
	local id="$2"
	local replace="$3"
	local before
	before="$(git hash-object -- "$file")"
	if grep -qE "Provenance:[[:space:]]*$ID_PATTERN" "$file"; then
		if [[ "$replace" -eq 1 ]]; then
			FROM="$STARTER_ID" TO="$id" perl -i -pe 's/(?<p>Provenance:\s*)\Q$ENV{FROM}\E\b/$+{p}$ENV{TO}/g' "$file"
		fi
	elif [[ "$file" = "$MAIN_FILE" ]]; then
		LINE="Provenance: $id$LINE_TAIL" perl -i -pe '
			if (!$done && /^(?<p>\s*\*\s*)SPDX-License-Identifier:/) { $_ .= "$+{p}$ENV{LINE}\n"; $done = 1 }' "$file"
		if ! grep -qE "Provenance:[[:space:]]*$ID_PATTERN" "$file"; then
			printf 'provenance: %s has no SPDX-License-Identifier line in its header; add " * Provenance: %s%s" there by hand\n' "$file" "$id" "$LINE_TAIL" >&2
		fi
	else
		LINE="Provenance: $id$LINE_TAIL" perl -i -pe '
			if (!$done && /^(?<p>\s*(?:\*|#|\/\/)\s*)Additional terms \(GPL-3\.0 section 7\(b\)\): ATTRIBUTION\.txt\s*$/) { $_ .= "$+{p}$ENV{LINE}\n"; $done = 1 }' "$file"
	fi
	[[ "$(git hash-object -- "$file")" != "$before" ]] || return 1
	printf '  stamped  %s\n' "$file"
	return 0
}

stamp() {
	# stamp_file runs in a condition, where a missing perl would go unnoticed.
	command -v perl >/dev/null 2>&1 || die "stamp needs perl"
	find_main
	local id replace=1 file changed=0
	[[ "$REPO" != "$STARTER_REPO" ]] || replace=0
	id="$(main_id)"
	if [[ -z "$id" ]] || { [[ "$id" = "$STARTER_ID" ]] && [[ "$replace" -eq 1 ]]; }; then
		id="wpas-$(od -An -N8 -tx1 /dev/urandom | tr -d ' \n')"
		[[ "$id" =~ ^$ID_PATTERN$ ]] || die "cannot make a new ID"
		printf 'This plugin'\''s provenance ID: %s (new)\n' "$id"
	else
		printf 'This plugin'\''s provenance ID: %s\n' "$id"
	fi
	while IFS= read -r file; do
		[[ -n "$file" ]] && [[ -f "$file" ]] || continue
		if stamp_file "$file" "$id" "$replace"; then
			changed=$((changed + 1))
		fi
	done < <(own_files)
	printf '%d file(s) stamped. Review with git diff, then commit.\n' "$changed"
	return 0
}

search() {
	local all="$1"
	shift
	command -v gh >/dev/null 2>&1 || die "search needs gh, the GitHub CLI, signed in"
	find_main
	local own id ids=("$STARTER_ID") hits="" out
	own="$(main_id)"
	[[ -z "$own" ]] || [[ "$own" = "$STARTER_ID" ]] || ids+=("$own")
	ids+=("$@")
	for id in "${ids[@]}"; do
		[[ "$id" =~ ^$ID_PATTERN$ ]] || die "not a provenance ID: $id"
		printf 'Searching GitHub code for %s\n' "$id"
		out="$(gh search code "\"$id\"" --limit 100 --json repository,path \
			--jq '.[] | "\(.repository.nameWithOwner)\t\(.path)"')" || die "GitHub code search failed for $id"
		[[ -z "$out" ]] || hits="$hits$out"$'\n'
	done
	local owners=" ${STARTER_REPO%%/*} " named
	case "$owners" in
	*" ${REPO%%/*} "*) ;;
	*) [[ -z "$REPO" ]] || owners="$owners${REPO%%/*} " ;;
	esac
	named="${owners# }"
	named="${named% }"
	named="${named// / and }"
	local repo count outside=0 attribution
	while IFS=$'\t' read -r count repo; do
		[[ -n "$repo" ]] || continue
		case "$owners" in
		*" ${repo%%/*} "*)
			[[ "$all" -eq 1 ]] || continue
			attribution="owner's"
			;;
		*)
			outside=$((outside + 1))
			if gh api "repos/$repo/contents/ATTRIBUTION.txt" --silent >/dev/null 2>&1; then
				attribution="has ATTRIBUTION.txt"
			else
				attribution="NO ATTRIBUTION.txt: check its credit and copyright notices"
			fi
			;;
		esac
		printf '  %-50s %3d file(s)  %s\n' "$repo" "$count" "$attribution"
	done < <(printf '%s' "$hits" | awk -F'\t' 'NF >= 2 && !seen[$1 FS $2]++ { n[$1]++ } END { for (r in n) printf "%d\t%s\n", n[r], r }' | sort -k2)
	if [[ "$outside" -eq 0 ]]; then
		printf 'No repositories outside %s carry these IDs.\n' "$named"
		return 0
	fi
	printf 'Repositories outside %s with these IDs: %d.\n' "$named" "$outside"
	return 1
}

main() {
	local command="${1:-}"
	[[ $# -eq 0 ]] || shift
	local root id
	case "$command" in
	-h | --help | "")
		usage
		return 0
		;;
	*) ;;
	esac
	root="$(git rev-parse --show-toplevel)" || die "run this inside a checkout of the plugin"
	cd "$root"
	case "$command" in
	id)
		[[ $# -eq 0 ]] || die "id takes no arguments"
		find_main
		id="$(main_id)"
		[[ -n "$id" ]] || die "$MAIN_FILE has no Provenance line; run scripts/provenance.sh stamp"
		printf '%s\n' "$id"
		;;
	stamp)
		[[ $# -eq 0 ]] || die "stamp takes no arguments"
		stamp
		;;
	search)
		local all=0 extra=()
		while [[ $# -gt 0 ]]; do
			local arg="$1"
			local value="${2:-}"
			case "$arg" in
			--all) all=1 ;;
			--id)
				[[ $# -ge 2 ]] || die "--id needs a value"
				extra+=("$value")
				shift
				;;
			*) die "unknown argument: $arg" ;;
			esac
			shift
		done
		search "$all" ${extra[@]+"${extra[@]}"}
		;;
	*) die "unknown command: $command (id, stamp or search; --help)" ;;
	esac
	return 0
}

main "$@"
