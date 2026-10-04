#!/usr/bin/env bash
# Copy a combined preview of the plugin to the shared local test site:
# origin/main plus every open pull request from this repository, merged in
# PR order. Branches that conflict are left out and reported, except when
# the only conflicts are in the changelogs (DOC_FILES): every PR adds lines
# at the top of the same lists, so after each merge to main the open PRs
# conflict there. For the preview those files keep both sides' lines (git's
# union merge) and the PR is included, with a note; real merges are not
# affected.
#
# Nothing is checked out, committed to a branch or pushed: merges are worked
# out with `git merge-tree` and exported with `git archive`, so any worktree
# can run it, and every run includes everyone's pushed work. The copy holds
# what a release build contains (.distignore applied). A checkout whose copy
# of this script differs from origin/main's runs origin/main's, so an old
# worktree cannot leave PRs out (<PREFIX>_PREVIEW_OWN=1 runs its own; the
# prefix is the plugin's constant prefix, such as WPSTARTER).
#
# Usage: scripts/preview-site.sh [--dry-run] [<site>]
#   <site>     WordPress folder of the test site (the one with wp-load.php).
#              Remembered for every worktree of this clone after first use;
#              <PREFIX>_PREVIEW_SITE overrides it.
#   --dry-run  Report what would be included; copy nothing.
#
# Needs git 2.38+ (merge-tree --write-tree), gh (signed in) and rsync.

set -euo pipefail

readonly LOCK_WAIT_SECONDS=180
# Files whose conflicts do not keep a PR out of the preview.
readonly DOC_FILES="changelog.txt readme.txt README.md"

LOCK_DIR=""
TMP_DIR=""
UNION_ATTRIBUTES=""
# Set in main() from the plugin's main file (scripts/lib/plugin.sh).
STAMP_NAME=""

# Results, set by the functions below (Bash 3.2 has no namerefs).
SITE=""
MAIN_SHA=""
PREVIEW_COMMIT=""
INCLUDED=""
SKIPPED=""

die() {
	local message="$1"
	printf 'preview-site: %s\n' "$message" >&2
	exit 1
}

usage() {
	sed -n '2,26p' "$0" | sed 's/^# \{0,1\}//'
	return 0
}

# Source scripts/lib/plugin.sh: the copy beside this script, or origin/main's
# when this runs as origin/main's copy from a temporary file and an older
# checkout started it (run_latest) without the library beside it.
load_plugin_lib() {
	local dir lib
	dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
	if [[ -r "$dir/lib/plugin.sh" ]]; then
		# shellcheck source=scripts/lib/plugin.sh disable=SC1091 # followed only with -x
		. "$dir/lib/plugin.sh"
		return 0
	fi
	lib="$(git show origin/main:scripts/lib/plugin.sh)" || die "scripts/lib/plugin.sh not found beside the script or on origin/main"
	eval "$lib"
	return 0
}

cleanup() {
	if [[ -n "$LOCK_DIR" ]] && [[ -f "$LOCK_DIR/pid" ]] && [[ "$(cat "$LOCK_DIR/pid" 2>/dev/null)" = "$$" ]]; then
		rm -rf "$LOCK_DIR"
	fi
	if [[ -n "$TMP_DIR" ]] && [[ -d "$TMP_DIR" ]]; then
		rm -rf "$TMP_DIR"
	fi
	return 0
}

# One run at a time across all worktrees. A lock is taken over only when its
# pid is no longer running, so a live run keeps it however long it takes. A
# lock without a pid (its run is starting, or stopped in the instant before
# writing one) is never taken over: after LOCK_WAIT_SECONDS the message says
# how to remove it.
acquire_lock() {
	local lock="$1"
	local waited=0
	local owner=""
	while ! mkdir "$lock" 2>/dev/null; do
		owner="$(cat "$lock/pid" 2>/dev/null || true)"
		if [[ -n "$owner" ]] && ! kill -0 "$owner" 2>/dev/null; then
			rm -rf "$lock"
			continue
		fi
		if [[ "$waited" -ge "$LOCK_WAIT_SECONDS" ]]; then
			[[ -n "$owner" ]] || die "a lock without a run id is in the way; if no preview run is going, remove $lock"
			die "another preview run (pid $owner) is still going (lock: $lock)"
		fi
		[[ "$waited" -eq 0 ]] && printf 'Waiting for another preview run to finish...\n'
		sleep 3
		waited=$((waited + 3))
	done
	LOCK_DIR="$lock"
	printf '%s\n' "$$" >"$lock/pid"
	return 0
}

# owner/repo of the GitHub remote "origin".
origin_slug() {
	local url
	url="$(git remote get-url origin)"
	url="${url%.git}"
	case "$url" in
	*github.com[:/]*) printf '%s\n' "${url#*github.com[:/]}" ;;
	*) die "origin is not a GitHub remote: $url" ;;
	esac
	return 0
}

# Sets SITE: the argument, then the environment, then the one remembered for
# this clone. A new argument is remembered unless this is a dry run.
resolve_site() {
	local site_arg="$1"
	local saved="$2"
	local remember="$3"
	SITE="$(plugin_env PREVIEW_SITE)"
	[[ -n "$site_arg" ]] && SITE="$site_arg"
	if [[ -z "$SITE" ]] && [[ -f "$saved" ]]; then
		SITE="$(cat "$saved")"
	fi
	[[ -n "$SITE" ]] || die "which site? Run: scripts/preview-site.sh \"<WordPress folder>\" (remembered after that)"
	SITE="${SITE%/}"
	if [[ ! -f "$SITE/wp-load.php" ]] || [[ ! -d "$SITE/wp-content/plugins" ]]; then
		die "not a WordPress folder: $SITE"
	fi
	if [[ -n "$site_arg" ]] && [[ "$remember" -eq 1 ]]; then
		printf '%s\n' "$SITE" >"$saved"
	fi
	return 0
}

# Open same-repository PRs as "number<TAB>branch<TAB>draft|ready<TAB>title", oldest first.
open_prs() {
	local slug
	slug="$(origin_slug)"
	gh pr list --repo "$slug" --state open --limit 100 \
		--json number,headRefName,isDraft,isCrossRepository,title \
		--jq 'sort_by(.number) | .[] | select(.isCrossRepository | not) | [.number, .headRefName, (if .isDraft then "draft" else "ready" end), .title] | @tsv' ||
		return 1
	return 0
}

# Merge one PR branch onto PREVIEW_COMMIT, or record why it is left out.
merge_pr() {
	local num="$1"
	local ref="$2"
	local state="$3"
	local title="$4"
	local sha out tree files
	local note=""
	local rc=0
	if ! sha="$(git rev-parse --verify --quiet "refs/remotes/origin/$ref^{commit}")"; then
		SKIPPED="${SKIPPED}  #$num $ref: branch not found on origin
"
		return 0
	fi
	if git merge-base --is-ancestor "$sha" "$PREVIEW_COMMIT"; then
		INCLUDED="${INCLUDED}  #$num $ref ${sha:0:7} ($state, nothing new) $title
"
		return 0
	fi
	out="$(git merge-tree --write-tree --name-only --no-messages "$PREVIEW_COMMIT" "$sha")" || rc=$?
	if [[ "$rc" -eq 1 ]]; then
		files="$(printf '%s\n' "$out" | sed 1d | sort -u | tr '\n' ' ')"
		files="${files% }"
		if only_doc_files "$files"; then
			rc=0
			out="$(git -c core.attributesFile="$UNION_ATTRIBUTES" merge-tree --write-tree --name-only --no-messages "$PREVIEW_COMMIT" "$sha")" || rc=$?
			[[ "$rc" -eq 0 ]] && note="; both sides' lines kept in $files"
		fi
	fi
	if [[ "$rc" -eq 0 ]]; then
		tree="${out%%$'\n'*}"
		PREVIEW_COMMIT="$(git -c user.name=preview -c user.email=preview@localhost commit-tree "$tree" -p "$PREVIEW_COMMIT" -p "$sha" -m "preview: merge #$num $ref")"
		INCLUDED="${INCLUDED}  #$num $ref ${sha:0:7} ($state$note) $title
"
	elif [[ "$rc" -eq 1 ]]; then
		SKIPPED="${SKIPPED}  #$num $ref ${sha:0:7}: conflicts with main or an earlier PR in $files
"
	else
		die "git merge-tree failed for #$num $ref"
	fi
	return 0
}

# Whether every file in the space-separated list is one of DOC_FILES.
only_doc_files() {
	local files="$1"
	local file
	[[ -n "$files" ]] || return 1
	for file in $files; do
		case " $DOC_FILES " in
		*" $file "*) ;;
		*) return 1 ;;
		esac
	done
	return 0
}

# Write the attributes file that makes DOC_FILES merge as a union.
write_union_attributes() {
	local file
	: >"$UNION_ATTRIBUTES"
	for file in $DOC_FILES; do
		printf '/%s merge=union\n' "$file" >>"$UNION_ATTRIBUTES"
	done
	return 0
}

# Sets MAIN_SHA, PREVIEW_COMMIT, INCLUDED and SKIPPED.
build_preview() {
	local prs num ref state title
	prs="$(open_prs)" ||
		die "could not list open pull requests with gh; nothing copied (a copy without them would hide work in progress)"
	MAIN_SHA="$(git rev-parse --verify 'refs/remotes/origin/main^{commit}')"
	PREVIEW_COMMIT="$MAIN_SHA"
	while IFS=$'\t' read -r num ref state title; do
		[[ -n "$num" ]] || continue
		merge_pr "$num" "$ref" "$state" "$title"
	done <<EOF
$prs
EOF
	return 0
}

# A note when the branch this runs from is not in the preview as it is here.
branch_note() {
	local current="$1"
	local merged changed
	if [[ -z "$current" ]] || [[ "$current" = "main" ]]; then
		return 0
	fi
	# Nothing to add: its work is already in the preview, through main (after
	# a squash merge its commits are not ancestors of main) or its open PR.
	# Changelog lines can sit in another order there (other PRs' lines are
	# kept beside them), so differences only in DOC_FILES do not count.
	if merged="$(git -c core.attributesFile="$UNION_ATTRIBUTES" merge-tree --write-tree --no-messages "$PREVIEW_COMMIT" HEAD 2>/dev/null)"; then
		changed="$(git diff --name-only "$PREVIEW_COMMIT" "$merged" | tr '\n' ' ')"
		changed="${changed% }"
		if [[ -z "$changed" ]] || only_doc_files "$changed"; then
			return 0
		fi
	fi
	if ! grep -q " $current " <<<"$INCLUDED"; then
		printf 'Your branch %s is not in the preview: push it and open a draft PR, or see skipped above.\n' "$current"
	elif [[ "$(git rev-parse HEAD)" != "$(git rev-parse --verify --quiet "refs/remotes/origin/$current" || true)" ]]; then
		printf 'Your branch %s is in the preview as pushed; local commits not pushed are not.\n' "$current"
	fi
	return 0
}

# The stamp text; it ends with a newline.
report() {
	local root="$1"
	local current="$2"
	printf 'Combined preview: origin/main plus open pull requests, made by scripts/preview-site.sh.\n'
	printf 'time: %s\n' "$(date '+%Y-%m-%d %H:%M %Z')"
	printf 'run from: %s (%s)\n' "$root" "${current:-detached}"
	printf 'main: %s\n' "$(git log -1 --format='%h %s' "$MAIN_SHA")"
	printf 'preview commit: %s (local only)\n' "${PREVIEW_COMMIT:0:12}"
	printf 'included:\n%s' "${INCLUDED:-  none
}"
	printf 'skipped:\n%s' "${SKIPPED:-  none
}"
	return 0
}

# Copy PREVIEW_COMMIT to the site as a release build would contain it.
copy_to_site() {
	local destination="$SITE/wp-content/plugins/$PLUGIN_SLUG"
	[[ -n "$PLUGIN_SLUG" ]] || die "no plugin slug"
	mkdir "$TMP_DIR/plugin"
	git archive --format=tar "$PREVIEW_COMMIT" | tar -x -C "$TMP_DIR/plugin"
	git show "$PREVIEW_COMMIT:.distignore" >"$TMP_DIR/distignore"
	mkdir -p "$destination"
	rsync -a --delete --delete-excluded --exclude-from="$TMP_DIR/distignore" "$TMP_DIR/plugin/" "$destination/"
	return 0
}

# Run origin/main's copy of this script when this checkout's differs, so a
# worktree made before a fix to the script cannot leave open PRs out of the
# shared preview. <PREFIX>_PREVIEW_OWN=1 runs this copy instead (to try a
# change to the script itself). The copy goes in a temporary folder with
# origin/main's scripts/lib/plugin.sh beside it.
run_latest() {
	local dry_run="$1"
	local site_arg="$2"
	local root="$3"
	local latest_var="${PLUGIN_CONST}_PREVIEW_LATEST"
	local latest
	latest="$(plugin_env PREVIEW_LATEST)"
	if [[ -n "$latest" ]]; then
		# Already main's copy: bash has the file open and the library is
		# loaded, so the folder can go now.
		rm -rf "$latest"
		return 0
	fi
	if [[ "$(plugin_env PREVIEW_OWN)" = "1" ]]; then
		return 0
	fi
	git fetch --quiet --prune origin || return 0
	latest="$(mktemp -d "${TMPDIR:-/tmp}/$PLUGIN_SLUG-preview-latest.XXXXXX")"
	mkdir -p "$latest/lib"
	if ! git show origin/main:scripts/preview-site.sh >"$latest/preview-site.sh" 2>/dev/null ||
		! git show origin/main:scripts/lib/plugin.sh >"$latest/lib/plugin.sh" 2>/dev/null ||
		{ cmp -s "$latest/preview-site.sh" "$root/scripts/preview-site.sh" && cmp -s "$latest/lib/plugin.sh" "$root/scripts/lib/plugin.sh"; }; then
		rm -rf "$latest"
		return 0
	fi
	printf 'preview-site: this checkout'\''s copy of the script differs from origin/main; running origin/main'\''s.\n' >&2
	if [[ "$dry_run" -eq 1 ]]; then
		exec env "$latest_var=$latest" bash "$latest/preview-site.sh" --dry-run ${site_arg:+"$site_arg"}
	fi
	exec env "$latest_var=$latest" bash "$latest/preview-site.sh" ${site_arg:+"$site_arg"}
}

main() {
	local dry_run=0
	local site_arg=""
	local arg
	while [[ $# -gt 0 ]]; do
		arg="$1"
		case "$arg" in
		--dry-run) dry_run=1 ;;
		-h | --help)
			usage
			return 0
			;;
		-*) die "unknown option: $arg" ;;
		*) site_arg="$arg" ;;
		esac
		shift
	done

	local root common current text note
	root="$(git rev-parse --show-toplevel)" || die "run this inside a checkout of the plugin"
	common="$(git rev-parse --path-format=absolute --git-common-dir)"
	cd "$root"
	load_plugin_lib
	plugin_identity HEAD || die "cannot tell which plugin this is"
	STAMP_NAME="$PLUGIN_SLUG-synced-from.txt"
	run_latest "$dry_run" "$site_arg" "$root"
	resolve_site "$site_arg" "$common/$PLUGIN_SLUG-preview-site" "$((1 - dry_run))"

	trap cleanup EXIT
	TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/$PLUGIN_SLUG-preview.XXXXXX")"
	UNION_ATTRIBUTES="$TMP_DIR/union-attributes"
	write_union_attributes
	if [[ "$dry_run" -eq 0 ]]; then
		acquire_lock "$common/$PLUGIN_SLUG-preview.lock"
	fi
	git fetch --quiet --prune origin
	build_preview

	current="$(git symbolic-ref --short -q HEAD || true)"
	text="$(report "$root" "$current")"
	note="$(branch_note "$current")"
	if [[ "$dry_run" -eq 0 ]]; then
		copy_to_site
		printf '%s\n' "$text" >"$SITE/wp-content/$STAMP_NAME"
	fi

	printf '%s\n' "$text"
	[[ -n "$note" ]] && printf '\n%s\n' "$note"
	if [[ "$dry_run" -eq 1 ]]; then
		printf '\nDry run: nothing copied to %s\n' "$SITE"
	else
		printf '\nCopied to %s/wp-content/plugins/%s\n' "$SITE" "$PLUGIN_SLUG"
	fi
	return 0
}

main "$@"
