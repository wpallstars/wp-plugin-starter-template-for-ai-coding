#!/usr/bin/env bash
# Give this plugin new names: run it once in a fresh copy of the starter to
# start a new plugin. Renames every tracked file's contents and paths, then
# leaves the changes for you to review and commit.
#
# Usage: scripts/rename-plugin.sh --slug SLUG --name NAME --prefix Prefix
#                                 [--const PREFIX] [--css CSS] [--repo OWNER/REPO]
#                                 [--description TEXT] [--author NAME]
#                                 [--author-uri URL] [--plugin-uri URL]
#                                 [--contributors USERS] [--donate URL|none]
#                                 [--version X.Y.Z]
#   --slug    Plugin folder, main file and text domain (my-plugin).
#   --name    Plugin Name (My Plugin).
#   --prefix  Class prefix (MyPlugin: MyPlugin_Settings).
#   --const   Constant prefix (default: --prefix in capitals, MYPLUGIN). In
#             lower case it is the option, hook and function prefix (myplugin).
#   --css     CSS class and data attribute prefix (default: the lower-case
#             prefix; a short one such as mp keeps the markup readable).
#   --repo    GitHub repository, owner/repo (default: wpallstars/SLUG).
#   --version The new plugin's first version (default: 0.1.0). The changelogs
#             in README.md, readme.txt and changelog.txt start again with it.
# The rest are the maker's details; each one left out keeps the starter's:
#   --description   One line, up to 150 characters: the Description header,
#                   the readme.txt short description and the line under
#                   README.md's title.
#   --author        Author header.
#   --author-uri    Author URI header.
#   --plugin-uri    Plugin URI header (default: the GitHub repository page).
#   --contributors  readme.txt Contributors, WordPress.org usernames (a, b).
#   --donate        readme.txt Donate link and the settings screen's donate
#                   button; none takes both out.
#
# Needs a clean working tree. Then update README.md, readme.txt,
# changelog.txt, AGENTS.md, LAUNCH.md and the banner (STANDARDS.md and DEVELOPMENT.md say how).
#
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Marcus Quinn
# Additional terms (GPL-3.0 section 7(b)): ATTRIBUTION.txt

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
# shellcheck source=scripts/lib/plugin.sh disable=SC1091 # followed only with -x
. "$SCRIPT_DIR/lib/plugin.sh"

# The starter's name and repository page, kept in every plugin's credits and
# AGENTS.md. Split, so that renaming this script leaves them alone.
readonly STARTER_NAME="WP Plugin ""Starter"
readonly STARTER_URL="https://github.com/wpallstars/wp-plugin-""starter-template-for-ai-coding"

die() {
	local message="$1"
	printf 'rename-plugin: %s\n' "$message" >&2
	exit 2
}

TMP_FILE=""
# The file being swapped in (replace_with_tmp), removed if the run stops.
NEW_FILE=""

cleanup() {
	[[ -z "$TMP_FILE" ]] || rm -f "$TMP_FILE"
	[[ -z "$NEW_FILE" ]] || rm -f "$NEW_FILE"
	return 0
}

usage() {
	sed -n '2,34p' "$0" | sed 's/^# \{0,1\}//'
	return 0
}

need() {
	local flag="$1"
	local value="$2"
	local pattern="$3"
	[[ -n "$value" ]] || die "$flag is needed (see --help)"
	# The whole value, not line by line as grep would: a value with a new
	# line must not pass an anchored pattern.
	[[ "$value" =~ $pattern ]] || die "$flag '$value' must match $pattern"
	return 0
}

# Like need, for a flag that may be left out.
allow() {
	local flag="$1"
	local value="$2"
	local pattern="$3"
	[[ -z "$value" ]] || need "$flag" "$value" "$pattern"
	return 0
}

# Swap in $TMP_FILE by rename, never in place: bash reads a running script as
# it goes, and this file is one of those changed. Returns 1 when the file is
# unchanged. Callers add || true for that, which also turns off set -e in
# here, so each step stops the run itself when it fails.
replace_with_tmp() {
	local file="$1"
	local mode=644
	cmp -s "$TMP_FILE" "$file" && return 1
	[[ -x "$file" ]] && mode=755
	NEW_FILE="$file.rename-new"
	cp "$TMP_FILE" "$NEW_FILE" || die "cannot write $NEW_FILE"
	chmod "$mode" "$NEW_FILE" || die "cannot set the mode of $NEW_FILE"
	mv -f "$NEW_FILE" "$file" || die "cannot replace $file"
	NEW_FILE=""
	return 0
}

# Set the value of the first "Field: value" line (a plugin or readme.txt
# header), keeping what comes before the value; with no value, drop the line.
set_field() {
	local file="$1"
	local field="$2"
	local value="$3"
	[[ -f "$file" ]] || return 0
	FIELD="$field" VALUE="$value" awk '
		!done && match($0, "^[ \t*#/]*" ENVIRON["FIELD"] ":[ \t]*") {
			done = 1
			if (ENVIRON["VALUE"] != "") print substr($0, 1, RLENGTH) ENVIRON["VALUE"]
			next
		}
		{ print }' "$file" >"$TMP_FILE"
	replace_with_tmp "$file" || true
	return 0
}

# Replace the first line that is exactly OLD with NEW.
set_line() {
	local file="$1"
	local old="$2"
	local new="$3"
	[[ -f "$file" ]] || return 0
	OLD="$old" NEW="$new" awk '
		!done && $0 == ENVIRON["OLD"] { print ENVIRON["NEW"]; done = 1; next }
		{ print }' "$file" >"$TMP_FILE"
	replace_with_tmp "$file" || true
	return 0
}

# Set one 'key' => 'URL' header link in the Setup class; with no URL, drop it.
set_link() {
	local file="$1"
	local key="$2"
	local url="$3"
	[[ -f "$file" ]] || return 0
	Q="'" KEY="$key" URL="$url" awk '
		BEGIN { q = ENVIRON["Q"] }
		!done && match($0, "^[ \t]*" q ENVIRON["KEY"] q "[ \t]*=>[ \t]*" q) {
			done = 1
			if (ENVIRON["URL"] != "") print substr($0, 1, RLENGTH) ENVIRON["URL"] q ","
			next
		}
		{ print }' "$file" >"$TMP_FILE"
	replace_with_tmp "$file" || true
	return 0
}

# Replace what follows the line that is exactly HEADING, up to the next line
# matching NEXT (with no NEXT, the end), with BODY; with no BODY, drop the
# heading too.
set_section() {
	local file="$1"
	local heading="$2"
	local next="$3"
	local body="$4"
	[[ -f "$file" ]] || return 0
	HEADING="$heading" NEXT="$next" BODY="$body" awk '
		skip && ENVIRON["NEXT"] != "" && $0 ~ ENVIRON["NEXT"] {
			skip = 0
			if (ENVIRON["BODY"] != "") print ""
		}
		skip { next }
		!done && $0 == ENVIRON["HEADING"] {
			done = 1
			skip = 1
			if (ENVIRON["BODY"] != "") print $0 "\n\n" ENVIRON["BODY"]
			next
		}
		{ print }' "$file" >"$TMP_FILE"
	replace_with_tmp "$file" || true
	return 0
}

# Start the new plugin at its own version, with a changelog of its own.
set_version() {
	local main_file="$1"
	local starter="$2"
	local first="First version, made from $FROM_NAME $starter."
	local file
	for file in "$main_file" README.md; do
		set_field "$file" "Version" "$VERSION"
	done
	set_field readme.txt "Stable tag" "$VERSION"
	# The define() forms scripts/lib/plugin.sh reads: either quote, spaces
	# allowed. What follows the old value (its quote, ");", a comment) stays.
	if CONST="${TO_CONST}_VERSION" VALUE="$VERSION" awk '
		!done && match($0, "^[ \t]*define\\([ \t]*[\047\"]" ENVIRON["CONST"] "[\047\"][ \t]*,[ \t]*[\047\"]") {
			done = 1
			quote = substr($0, RLENGTH, 1)
			rest = substr($0, RLENGTH + 1)
			print substr($0, 1, RLENGTH) ENVIRON["VALUE"] substr(rest, index(rest, quote))
			next
		}
		{ print }
		END { if (!done) exit 3 }' "$main_file" >"$TMP_FILE"; then
		replace_with_tmp "$main_file" || true
	else
		printf 'rename-plugin: no define of %s_VERSION in %s; set it to %s by hand\n' "$TO_CONST" "$main_file" "$VERSION" >&2
	fi
	set_section readme.txt "== Upgrade Notice ==" '^== ' ""
	set_section readme.txt "== Changelog ==" '^== ' "= $VERSION =
* $first

Every change: changelog.txt."
	set_section changelog.txt "== Changelog ==" "" "Every change to $TO_NAME. readme.txt lists the latest version in short.

= $VERSION =
* $first"
	set_section README.md "## Changelog" '^## ' "### $VERSION

- $first"
	# Launch state belongs to this plugin, not the repository it was copied from.
	cat >"$TMP_FILE" <<EOF
# $TO_NAME launch state

Version: $VERSION

In development; no release yet. The repository is private. Making it public
needs the owner's say.

## While private

Follow \`DEVELOPMENT.md\` → While private. No branch protection or repository
rules, CodeQL, secret scanning or Scorecard are on: they need a public
repository or a paid GitHub plan. Connect Codacy, CodeFactor and SonarCloud
at public launch. \`SYNC_PAT\` is needed only once \`main\` is protected
(\`DEVELOPMENT.md\` → Services setup, step 4).

## Before 1.0

Tick these off; \`scripts/preflight-release.sh\` checks most of them (Starter
leftovers lists what is still the starter's).

- [ ] Description: the \`Description:\` header and \`readme.txt\`'s short
  description (150 characters at most) say what this plugin does, not the
  starter's.
- [ ] \`README.md\` and \`readme.txt\` open with this plugin's own offering (what
  it does, for whom, why it differs), then getting started and a guide. Keep
  both credits (Built with AI, Made from).
- [ ] \`readme.txt\`: under 10 KB, up to 5 tags, Tested up to the latest
  WordPress, FAQ, an External services section for every service the plugin
  contacts, one Screenshots caption per screenshot.
- [ ] Banner and icon: in \`.wordpress-org/banner.svg\` replace the headline and
  tagline, and replace the starter's plug on the stack with this plugin's own
  mark (the same in \`.wordpress-org/icon.svg\`); run \`scripts/build-banner.sh\`
  and check the icon reads at 128 px.
- [ ] Screenshots of this plugin in \`.wordpress-org/screenshot-N.png\`
  (\`scripts/build-banner.sh\` makes the View details copies).
- [ ] \`AGENTS.md\` describes this plugin; \`DESIGN.md\` and search keywords, if
  the plugin has them, are current.
- [ ] Version 1.0.0 everywhere: \`Version:\`, the version constant, \`Stable tag:\`,
  \`README.md\`'s Version line and the three changelogs.
- [ ] \`scripts/sync-core.sh --check\` lists no differences from the starter.
- [ ] Checks pass: \`scripts/lint.sh\`, \`scripts/preflight-release.sh\` (no
  errors; each warning understood), \`scripts/smoke-test.sh\`,
  \`scripts/plugin-check.sh\` (no errors on either zip).
- [ ] The owner has seen it on a test site (\`scripts/preview-site.sh\`) and
  approved the banner, icon and screenshots.
- [ ] WordPress.org: if the Plugin Name gives another slug, ask for this
  plugin's slug in the submission notes.
- [ ] After the release: \`scripts/update-test.sh\`.

## At public launch

First follow \`DEVELOPMENT.md\` → Secrets in history, then
\`DEVELOPMENT.md\` → At public launch. Update this file with what is on.

## WordPress.org

Not submitted. Follow \`RELEASING.md\` → WordPress.org when the owner says,
and record the submission here.
EOF
	replace_with_tmp LAUNCH.md || true
	return 0
}

# The agent guide belongs to this plugin too: the starter's describes the
# starter (what every plugin is made from), which is wrong for a plugin.
set_agents() {
	cat >"$TMP_FILE" <<EOF
# $TO_NAME — agent guide

$TO_NAME: a wpallstars plugin made from $STARTER_NAME. Say here, in a line or
two, what it does and who it is for.

**Read \`STANDARDS.md\` before any change.** It holds the rules every plugin
made from the starter shares: structure and core files, code rules,
performance, Updates from GitHub, releases and testing; styling (admin
forms, front-end dark mode) is in \`STYLING.md\`. The starter holds the
master copy of both and of every core file (\`scripts/core-files.txt\`).
This file holds only what is $TO_NAME's own.

| Placeholder in \`STANDARDS.md\` | $TO_NAME |
|---|---|
| \`{slug}\` | \`$TO_SLUG\` (main file \`$TO_SLUG.php\`) |
| \`{prefix}\` | \`$TO_PREFIX\` |
| \`{Prefix}\` | \`$TO_PACKAGE\` |
| \`{PREFIX}\` | \`$TO_CONST\` |
| \`{Name}\` | $TO_NAME |
| \`{css}\` | \`$TO_CSS\` |

User docs: \`README.md\` (developers, and the Read Me tab) and \`readme.txt\`.
Development: \`DEVELOPMENT.md\`. Releases: \`RELEASING.md\`; launch state:
\`LAUNCH.md\`. Keep this file a short map: guidance for one kind of task goes
in \`docs/\` (\`STANDARDS.md\` → Agent docs); there is none yet.

## What belongs here

- $TO_NAME's own features: settings, features and wiring in
  \`${TO_PACKAGE}_Setup\` (\`includes/class-$TO_PREFIX-setup.php\`), each
  feature in its own files. Add a line here for each rule only this plugin
  has.
- Core files (\`scripts/core-files.txt\`) come from the starter: do not change
  them here. \`scripts/sync-core.sh\` updates them (\`--check\` lists what
  differs). A fix every plugin needs goes to the starter first.
- Keep the credits in \`README.md\` and \`readme.txt\`: **Built with AI** to
  aidevops (<https://aidevops.sh>) and the "Made from" line crediting the
  starter (\`STANDARDS.md\` → Structure).

## Test sites

Install the GitHub build on a local test site with
\`scripts/preview-site.sh\` (see \`DEVELOPMENT.md\`), or install the GitHub
zip from \`scripts/build-release.sh\` on any test site.
EOF
	replace_with_tmp AGENTS.md || true
	return 0
}

# Rebuild README.md's GitHub badges block for the new repository. The
# SonarCloud key is owner_repo. The Codacy badge has a per-project ID, and
# CodeFactor's badge is a broken image until the repository is added on
# codefactor.io, so both are left out until that service has the new
# repository (DEVELOPMENT.md → Services setup).
set_badges() {
	local repo="$1"
	local url="https://github.com/$repo"
	local key="${repo/\//_}"
	[[ -f README.md ]] || return 0
	BADGES="<!-- On GitHub only: the Read Me tab skips this block. scripts/rename-plugin.sh rewrites it. -->
[![CI]($url/actions/workflows/ci.yml/badge.svg?branch=main)]($url/actions/workflows/ci.yml)
[![Quality Gate Status](https://sonarcloud.io/api/project_badges/measure?project=$key&metric=alert_status)](https://sonarcloud.io/summary/new_code?id=$key)
[![License: GPL v3 or later](https://img.shields.io/badge/License-GPL%20v3%20or%20later-blue.svg)](LICENSE)
[![Latest release](https://img.shields.io/github/v/release/$repo)]($url/releases)

[![Lines of code](docs/metrics/badges/loc.svg)](docs/metrics/repo-metrics.md)
[![Dependencies](docs/metrics/badges/dependencies.svg)](docs/metrics/repo-metrics.md)

[![Languages by lines of code](docs/metrics/badges/languages.svg)](docs/metrics/repo-metrics.md)" awk '
		$0 == "<!-- aidevops:badges:end -->" { skip = 0 }
		skip { next }
		{ print }
		$0 == "<!-- aidevops:badges:start -->" { print ENVIRON["BADGES"]; skip = 1 }' README.md >"$TMP_FILE"
	replace_with_tmp README.md || true
	return 0
}

# The starter's credit, kept in every plugin made from it (STANDARDS.md →
# Structure): the renaming above turned the starter's name and repository in
# it into the new plugin's, so write the line again.
set_credit() {
	local name="$STARTER_NAME"
	local url="$STARTER_URL"
	local file line
	for file in README.md readme.txt; do
		[[ -f "$file" ]] || continue
		if [[ "$file" = README.md ]]; then
			line="Made from [$name]($url), the wpallstars starter plugin. Its shared standards and the weekly Starter sync keep this plugin up to date."
		else
			line="Made from $name ($url), the wpallstars starter plugin."
		fi
		LINE="$line" awk '
			!done && index($0, "Made from ") == 1 { print ENVIRON["LINE"]; done = 1; next }
			{ print }' "$file" >"$TMP_FILE"
		replace_with_tmp "$file" || true
	done
	return 0
}

# Copyright (STANDARDS.md → Structure): the new plugin's own line (this year,
# its Author), then the starter's, kept as "Parts copyright". Split strings,
# as STARTER_NAME, so renaming this script leaves them alone.
set_copyright() {
	local main_file="$1"
	local name="$STARTER_NAME"
	local url="$STARTER_URL"
	local starter="Copyright (C) 2026 Marcus ""Quinn"
	local parts="Parts copyright (C) 2026 Marcus ""Quinn"
	local owner year
	owner="$(plugin_header_field "$(head -c 8192 "$main_file")" "Author")"
	year="$(date +%Y)"
	set_line "$main_file" " * $starter" " * Copyright (C) $year $owner
 * $parts, from $name ($url)"
	set_line README.md "$starter" "Copyright (C) $year $owner

$parts, from [$name]($url)."
	return 0
}

# Put the maker's details in, after the renaming. Empty ones stay as they are.
set_identity() {
	local main_file="$1"
	local setup_file="$2"
	local old_description="$3"
	if [[ -n "$DESCRIPTION" ]]; then
		set_field "$main_file" "Description" "$DESCRIPTION"
		set_line readme.txt "$old_description" "$DESCRIPTION"
		set_line README.md "$old_description" "$DESCRIPTION"
	fi
	[[ -z "$AUTHOR" ]] || set_field "$main_file" "Author" "$AUTHOR"
	if [[ -n "$AUTHOR_URI" ]]; then
		set_field "$main_file" "Author URI" "$AUTHOR_URI"
	fi
	[[ -z "$PLUGIN_URI" ]] || set_field "$main_file" "Plugin URI" "$PLUGIN_URI"
	[[ -z "$CONTRIBUTORS" ]] || set_field readme.txt "Contributors" "$CONTRIBUTORS"
	if [[ "$DONATE" = none ]]; then
		set_field readme.txt "Donate link" ""
		set_link "$setup_file" donate ""
	elif [[ -n "$DONATE" ]]; then
		set_field readme.txt "Donate link" "$DONATE"
		set_link "$setup_file" donate "$DONATE"
	fi
	return 0
}

DESCRIPTION=""
AUTHOR=""
AUTHOR_URI=""
PLUGIN_URI=""
CONTRIBUTORS=""
DONATE=""
VERSION="0.1.0"

check_identity() {
	local url='^https?://[^[:space:]<>"'\''\\]+$'
	case "$DESCRIPTION$AUTHOR" in
	*[[:cntrl:]]* | *'*/'*) die "--description and --author are one line, without */ or control characters" ;;
	*) ;;
	esac
	[[ "${#DESCRIPTION}" -le 150 ]] || die "--description is ${#DESCRIPTION} characters; WordPress.org allows 150"
	allow --author "$AUTHOR" '^[^<>]+$'
	allow --author-uri "$AUTHOR_URI" "$url"
	allow --plugin-uri "$PLUGIN_URI" "$url"
	allow --contributors "$CONTRIBUTORS" '^[A-Za-z0-9_.@-]+(, ?[A-Za-z0-9_.@-]+)*$'
	[[ "$DONATE" = none ]] || allow --donate "$DONATE" "$url"
	need --version "$VERSION" '^[0-9]+\.[0-9]+\.[0-9]+$'
	return 0
}

# Stop if a renamed PHP file no longer parses (the changes stay for git diff).
check_php() {
	command -v php >/dev/null 2>&1 || {
		printf 'rename-plugin: php not found; run php -l on the changed files yourself\n' >&2
		return 0
	}
	local file bad=0
	while IFS= read -r file; do
		[[ -f "$file" ]] || continue
		php -l "$file" >/dev/null 2>&1 || {
			php -l "$file" >&2 || true
			bad=1
		}
	done < <(git ls-files '*.php')
	[[ "$bad" -eq 0 ]] || die "the renamed PHP above does not parse; see git diff"
	return 0
}

main() {
	local slug="" name="" prefix="" const="" css="" repo=""
	while [[ $# -gt 0 ]]; do
		local arg="$1"
		local value="${2:-}"
		case "$arg" in
		--slug | --name | --prefix | --const | --css | --repo | --description | --author | --author-uri | --plugin-uri | --contributors | --donate | --version)
			[[ $# -ge 2 ]] || die "$arg needs a value"
			case "$arg" in
			--slug) slug="$value" ;;
			--name) name="$value" ;;
			--prefix) prefix="$value" ;;
			--const) const="$value" ;;
			--css) css="$value" ;;
			--repo) repo="$value" ;;
			--description) DESCRIPTION="$value" ;;
			--author) AUTHOR="$value" ;;
			--author-uri) AUTHOR_URI="$value" ;;
			--plugin-uri) PLUGIN_URI="$value" ;;
			--contributors) CONTRIBUTORS="$value" ;;
			--donate) DONATE="$value" ;;
			--version) VERSION="$value" ;;
			*) ;; # The outer pattern lists every option that takes a value.
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

	[[ -n "$const" ]] || const="$(printf '%s' "$prefix" | tr '[:lower:]' '[:upper:]')"
	[[ -n "$css" ]] || css="$(printf '%s' "$const" | tr '[:upper:]' '[:lower:]')"
	[[ -n "$repo" ]] || repo="wpallstars/$slug"
	need --slug "$slug" '^[a-z][a-z0-9-]*[a-z0-9]$'
	# Quotes and $ are escaped where the name lands in code (plugin_map); /, \,
	# <, > and % are not allowed: paths, comments, HTML and sprintf formats.
	need --name "$name" '^[^/\\<>%[:cntrl:]]+$'
	need --prefix "$prefix" '^[A-Z][A-Za-z0-9]*$'
	need --const "$const" '^[A-Z][A-Z0-9]*$'
	need --css "$css" '^[a-z][a-z0-9]*$'
	need --repo "$repo" '^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$'
	check_identity

	local root
	root="$(git rev-parse --show-toplevel)" || die "run this inside a checkout of the plugin"
	cd "$root"
	[[ -z "$(git status --porcelain)" ]] || die "commit or put away your changes first"
	plugin_identity HEAD || die "cannot tell which plugin this is"
	plugin_names_as FROM

	export TO_SLUG="$slug" TO_NAME="$name" TO_PACKAGE="$prefix" TO_CONST="$const"
	export TO_PREFIX
	TO_PREFIX="$(printf '%s' "$const" | tr '[:upper:]' '[:lower:]')"
	export TO_CSS="$css" TO_REPO="$repo"
	[[ "$TO_SLUG" != "$FROM_SLUG" ]] || die "the slug is already $slug"

	printf 'Renaming %s to %s: %s / %s / %s / %s / %s / %s\n' "$FROM_NAME" "$name" "$slug" "$TO_PREFIX" "$prefix" "$const" "$css" "$repo"

	local file kind target changed=0 moved=0
	trap cleanup EXIT
	TMP_FILE="$(mktemp "${TMPDIR:-/tmp}/rename-plugin.XXXXXX")"
	local tmp="$TMP_FILE"
	while IFS= read -r file; do
		[[ -f "$file" ]] || continue
		# Text files only (pictures and other binaries keep their bytes).
		if grep -Iq . "$file"; then
			# The path only tells plugin_map how to escape the name.
			kind="$file"
			plugin_map "$kind" <"$file" >"$tmp"
			if replace_with_tmp "$file"; then
				changed=$((changed + 1))
			fi
		fi
		target="$(printf '%s' "$file" | plugin_map)"
		if [[ "$target" != "$file" ]]; then
			mkdir -p "$(dirname "$target")"
			git mv "$file" "$target"
			moved=$((moved + 1))
		fi
	done < <(git ls-files)

	local old_description starter_version
	old_description="$(plugin_header_field "$(head -c 8192 "$slug.php")" "Description")"
	starter_version="$(plugin_header_field "$(head -c 8192 "$slug.php")" "Version")"
	set_identity "$slug.php" "includes/class-$TO_PREFIX-setup.php" "$old_description"
	set_version "$slug.php" "$starter_version"
	set_agents
	set_badges "$repo"
	set_credit
	set_copyright "$slug.php"
	check_php

	printf '%d files changed, %d renamed. Run composer update --lock (the package name changed), review with git diff and git status, then commit.\n' "$changed" "$moved"
	return 0
}

main "$@"
