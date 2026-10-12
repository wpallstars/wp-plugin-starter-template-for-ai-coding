#!/usr/bin/env bash
# Copy the core files (scripts/core-files.txt) from the starter plugin into
# this plugin, with this plugin's names. Core files hold no code for one
# plugin, so they match the starter apart from names and marked own blocks.
#
# Usage: scripts/sync-core.sh [--check] [--from DIR] [--ref REF] [--discard-local]
#   --check          Change nothing; list core files that differ from the
#                    starter's, each with its class, and exit 1 if any do
#                    (scripts/preflight-release.sh warns).
#   --from DIR       A checkout of the starter (default: <PREFIX>_STARTER_DIR,
#                    then <STARTER_REPO_DIR> next to this repository).
#   --ref REF        Starter commit, branch or tag to copy from (default: HEAD
#                    of that checkout; use origin/main after a git fetch there).
#   --discard-local  Also replace files changed here (below), once their
#                    change is in the starter or no longer needed.
#
# A core file that differs is behind (an older starter version: a sync
# updates it), newer (a starter version REF does not contain, such as a
# later one on main), changed here (no starter version has it: the plugin
# changed it outside its own blocks) or missing (a sync adds it). A sync
# writes nothing while any file is newer or changed here, so it never undoes
# a starter change or loses the plugin's own: sync from a ref that contains
# the newer files, and take a change made here to the starter first. The
# classes come from the starter checkout's history, so it must not be a
# shallow clone. DEVELOPMENT.md → Starter sync.
#
# The list of core files and their contents come from the starter at REF;
# the plugin's names come from this repository's main file at HEAD.
# Review the changes with git diff, then commit them.

# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Marcus Quinn
# Additional terms (GPL-3.0 section 7(b)): ATTRIBUTION.txt
# Provenance: wpas-e4502af0f07e8a92. Copies, even of part, keep these lines.

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
OWN_FILE=""
# A starter version being compared, the versions of one path, and each
# differing file's class (classify).
CAND_FILE=""
BLOBS_FILE=""
CLASS_FILE=""
# The file being swapped in, removed if the run stops.
NEW_FILE=""

cleanup() {
	local file
	for file in "$TMP_FILE" "$LIST_FILE" "$OWN_FILE" "$CAND_FILE" "$BLOBS_FILE" "$CLASS_FILE" "$NEW_FILE"; do
		[[ -z "$file" ]] || rm -f "$file"
	done
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
	sed -n '2,29p' "$0" | sed -e 's/^# \{0,1\}//' -e "s/<STARTER_REPO_DIR>/$STARTER_REPO_DIR/"
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
	local check=0 discard=0 from="" ref="HEAD"
	while [[ $# -gt 0 ]]; do
		local arg="$1"
		local value="${2:-}"
		case "$arg" in
		--check) check=1 ;;
		--discard-local) discard=1 ;;
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
	if [[ "$(git -C "$from" rev-parse --is-shallow-repository)" = "true" ]]; then
		SHALLOW=1
	fi

	cd "$from"
	plugin_identity "$ref" || die "cannot read the starter's names at $ref"
	plugin_names_as FROM
	cd "$root"

	printf 'Core files from %s (%s) into %s, as %s / %s / %s / %s / %s\n' \
		"$FROM_NAME" "$(git -C "$from" rev-parse --short "$ref")" "$TO_NAME" \
		"$TO_SLUG" "$TO_PREFIX" "$TO_PACKAGE" "$TO_CONST" "$TO_CSS"

	local path count=0
	DIFFER=0
	trap cleanup EXIT
	TMP_FILE="$(mktemp "${TMPDIR:-/tmp}/sync-core.XXXXXX")"
	LIST_FILE="$(mktemp "${TMPDIR:-/tmp}/sync-core-list.XXXXXX")"
	OWN_FILE="$(mktemp "${TMPDIR:-/tmp}/sync-core-own.XXXXXX")"
	CAND_FILE="$(mktemp "${TMPDIR:-/tmp}/sync-core-cand.XXXXXX")"
	BLOBS_FILE="$(mktemp "${TMPDIR:-/tmp}/sync-core-blobs.XXXXXX")"
	CLASS_FILE="$(mktemp "${TMPDIR:-/tmp}/sync-core-class.XXXXXX")"
	core_paths "$from" "$ref" "$LIST_FILE"
	# Validate and classify every file before writing any: a late malformed
	# block, or a file a sync would lose work in, must not leave the plugin
	# partly synced.
	while IFS= read -r path; do
		sync_file "$from" "$ref" "$path" 2
	done <"$LIST_FILE"
	if [[ "$check" -eq 0 ]]; then
		stop_if_unsafe "$from" "$ref" "$discard"
	fi
	while IFS= read -r path; do
		sync_file "$from" "$ref" "$path" "$check"
		count=$((count + 1))
	done <"$LIST_FILE"

	if [[ "$check" -eq 1 ]]; then
		if [[ "$DIFFER" -eq 0 ]]; then
			printf 'All %d core files match the starter.\n' "$count"
			return 0
		fi
		printf '%d of %d core files differ from the starter. Run scripts/sync-core.sh, or change the starter first.\n' "$DIFFER" "$count"
		return 1
	fi
	printf '%d of %d core files updated. Review with git diff, then commit.\n' "$DIFFER" "$count"
	return 0
}

# Core files that differ from the starter (sync_file counts them).
DIFFER=0
# 1 when the starter checkout is a shallow clone: no history to classify.
SHALLOW=0
# Set by classify: behind, newer, changed or unknown, and for behind and
# newer the starter commit whose version the plugin's file is.
CLASS=""
CLASS_AT=""

# Put each own block of TARGET into the corresponding block of FILE, in
# order. Recognise whole comment lines only, including indented release
# steps. Returns 1, with the reason on stderr, when the blocks do not fit.
own_merge() {
	local target="$1"
	local file="$2"
	awk -v marker="$TO_CSS-own" '
		function fail(message) {
			print "sync-core: " FILENAME ": " message > "/dev/stderr"
			failed = 1
			exit 1
		}
		function boundary(line, suffix) {
			sub(/^[[:space:]]*/, "", line)
			sub(/[[:space:]]*$/, "", line)
			return line == "# " marker suffix || line == "<!-- " marker suffix " -->"
		}
		FILENAME != previous {
			if (inside) fail("own start marker has no end marker")
			inside = 0
			count = 0
			previous = FILENAME
		}
		{
			target = (FILENAME == ARGV[1])
			if (boundary($0, ":start")) {
				if (inside) fail("nested own start marker")
				inside = 1
				count++
				if (target) target_count = count
				else { starter_count = count; print; printf "%s", content[count] }
			} else if (boundary($0, ":end")) {
				if (!inside) fail("own end marker has no start marker")
				inside = 0
				if (!target) print
			} else if (inside) {
				if (target) content[count] = content[count] $0 ORS
			} else if (!target) print
		}
		END {
			if (!failed) {
				if (inside) fail("own start marker has no end marker")
				if (target_count > starter_count) fail("target has more own blocks than the starter")
			}
		}
	' "$target" "$file" >"$OWN_FILE" || return 1
	cp "$OWN_FILE" "$file"
	return 0
}

# Keep the target's own blocks in the starter's file (TMP_FILE).
preserve_own() {
	local target="$1"
	grep -Fq "$TO_CSS-own:" "$target" || return 0
	own_merge "$target" "$TMP_FILE" || die "cannot preserve own blocks in $target; no core files written"
	return 0
}

# The versions of PATH in the starter's history, newest first, each once:
# "blob commit" per line, into BLOBS_FILE. REVS are git log's revisions.
starter_versions() {
	local from="$1"
	local path="$2"
	shift 2
	git -c core.quotePath=false --literal-pathspecs -C "$from" log --format='%H' --raw --no-abbrev \
		--no-renames --full-history "$@" -- "$path" |
		awk -v p="$path" '
			!/^:/ { if (NF) commit = $0; next }
			{
				# ":old-mode new-mode old-blob new-blob status<TAB>path"
				split($0, part, "\t")
				split(part[1], f, " ")
				if (part[2] == p && f[4] !~ /^0+$/ && !seen[f[4]]++) print f[4], commit
			}' >"$BLOBS_FILE" || die "cannot read the history of $path in the starter"
	return 0
}

# Whether the starter's version BLOB, with this plugin's names and the
# target's own blocks, is the target's content.
same_version() {
	local from="$1"
	local blob="$2"
	local target="$3"
	git -C "$from" cat-file blob "$blob" | plugin_map "$target" >"$CAND_FILE" || return 1
	if grep -Fq "$TO_CSS-own:" "$target"; then
		own_merge "$target" "$CAND_FILE" 2>/dev/null || return 1
	fi
	cmp -s "$CAND_FILE" "$target" || return 1
	return 0
}

# Set CLASS and CLASS_AT for a core file whose content differs from the
# starter's at REF: behind when it is a version REF contains, newer when it
# is one only other starter commits have (later on main, another branch),
# changed when no starter version is the same, unknown without history.
# Versions REF contains are tried first, newest first; each stops at the
# first match.
classify() {
	local from="$1"
	local ref="$2"
	local path="$3"
	local target="$4"
	local blob commit seen=" "
	CLASS="unknown"
	CLASS_AT=""
	[[ "$SHALLOW" -eq 0 ]] || return 0
	starter_versions "$from" "$path" "$ref"
	while read -r blob commit; do
		seen="$seen$blob "
		if same_version "$from" "$blob" "$target"; then
			CLASS="behind"
			CLASS_AT="$commit"
			return 0
		fi
	done <"$BLOBS_FILE"
	starter_versions "$from" "$path" --all --not "$ref"
	while read -r blob commit; do
		case "$seen" in
		*" $blob "*) continue ;;
		*) ;;
		esac
		if same_version "$from" "$blob" "$target"; then
			CLASS="newer"
			CLASS_AT="$commit"
			return 0
		fi
	done <"$BLOBS_FILE"
	CLASS="changed"
	return 0
}

# The class recorded for TARGET (CLASS and CLASS_AT), from CLASS_FILE.
class_of() {
	local target="$1"
	local line
	line="$(awk -F'\t' -v t="$target" '$1 == t { print $2 "\t" $3; exit }' "$CLASS_FILE")"
	CLASS="${line%%$'\t'*}"
	CLASS_AT="${line#*$'\t'}"
	return 0
}

# The indented line under a file in --check: its class and what to do. The
# starter-sync workflow reads the words before the colon.
class_line() {
	local from="$1"
	local ref="$2"
	case "$CLASS" in
	behind) printf '    behind: an older starter version (%s); a sync updates it\n' "${CLASS_AT:0:7}" ;;
	newer) printf '    newer: the starter'\''s version at %s, which %s does not contain; sync from the starter'\''s main or a later tag\n' "${CLASS_AT:0:7}" "$ref" ;;
	changed) printf '    changed here: no starter version has it; take the change to the starter first, or move plugin-only lines into %s-own blocks, then sync with --discard-local\n' "$TO_CSS" ;;
	*) printf '    unknown (shallow starter clone): run git -C %s fetch --unshallow\n' "$from" ;;
	esac
	return 0
}

# Stop before writing anything when a sync would lose work: a file newer
# than REF, changed here (unless --discard-local), or not classified.
stop_if_unsafe() {
	local from="$1"
	local ref="$2"
	local discard="$3"
	local target class at list="" newer=0 changed=0 unknown=0
	while IFS=$'\t' read -r target class at; do
		case "$class" in
		newer)
			list="$list  newer         $target (the starter's version at ${at:0:7})"$'\n'
			newer=1
			;;
		changed)
			[[ "$discard" -eq 0 ]] || continue
			list="$list  changed here  $target"$'\n'
			changed=1
			;;
		unknown)
			list="$list  unknown       $target"$'\n'
			unknown=1
			;;
		*) ;;
		esac
	done <"$CLASS_FILE"
	[[ -n "$list" ]] || return 0
	{
		printf 'sync-core: nothing written. A sync from the starter at %s could lose work in these core files:\n%s' "$ref" "$list"
		if [[ "$newer" -eq 1 ]]; then
			printf 'Newer: this plugin has a later starter version than %s. Sync from a starter ref that contains it: the starter'\''s main (what the weekly Starter sync checks against), or a later tag. There is no option to go backwards.\n' "$ref"
		fi
		if [[ "$changed" -eq 1 ]]; then
			printf 'Changed here: this plugin changed it outside its %s-own blocks. Take the change to the starter first (a pull request, or an issue there with this plugin'\''s case), or move plugin-only lines into %s-own blocks. Then run again with --discard-local.\n' "$TO_CSS" "$TO_CSS"
		fi
		if [[ "$unknown" -eq 1 ]]; then
			printf 'Unknown: the starter checkout is a shallow clone, so its history cannot tell. Run: git -C %s fetch --unshallow\n' "$from"
		fi
	} >&2
	exit 2
}

# Compare one core file with the starter's, with this plugin's names; list
# it (CHECK 1), validate and classify only (CHECK 2), or replace it when it
# differs.
sync_file() {
	local from="$1"
	local ref="$2"
	local path="$3"
	local check="$4"
	local target mode
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
	git -C "$from" show "$ref:$path" | plugin_map "$target" >"$TMP_FILE"
	if [[ -f "$target" ]]; then preserve_own "$target"; fi
	if [[ "$check" -eq 2 ]]; then
		# Only files whose content differs need their history read.
		if [[ -f "$target" ]] && ! cmp -s "$TMP_FILE" "$target"; then
			classify "$from" "$ref" "$path" "$target"
			printf '%s\t%s\t%s\n' "$target" "$CLASS" "$CLASS_AT" >>"$CLASS_FILE"
		fi
		return 0
	fi
	if [[ -f "$target" ]] && cmp -s "$TMP_FILE" "$target" && same_mode "$target" "$mode"; then
		return 0
	fi
	DIFFER=$((DIFFER + 1))
	if [[ "$check" -eq 1 ]]; then
		if [[ ! -f "$target" ]]; then
			printf '  missing  %s\n' "$target"
			printf '    missing: a sync adds it\n'
		elif cmp -s "$TMP_FILE" "$target"; then
			printf '  mode     %s (executable bit)\n' "$target"
			printf '    behind: only the executable bit differs; a sync sets it\n'
		else
			printf '  differs  %s\n' "$target"
			class_of "$target"
			class_line "$from" "$ref"
		fi
		return 0
	fi
	local note=""
	if [[ -f "$target" ]] && ! cmp -s "$TMP_FILE" "$target"; then
		class_of "$target"
		[[ "$CLASS" != "changed" ]] || note=" (changed here; its change discarded)"
	fi
	mkdir -p "$(dirname "$target")"
	# Replace by rename, never in place: bash reads a running script as it
	# goes, so rewriting scripts/sync-core.sh itself would break this run.
	NEW_FILE="$target.sync-core-new"
	# Never write through a leftover file or link of that name.
	rm -f "$NEW_FILE"
	cp "$TMP_FILE" "$NEW_FILE"
	if [[ "$mode" = "100755" ]]; then chmod 755 "$NEW_FILE"; else chmod 644 "$NEW_FILE"; fi
	mv -f "$NEW_FILE" "$target"
	NEW_FILE=""
	printf '  updated  %s%s\n' "$target" "$note"
	return 0
}

main "$@"
