#!/usr/bin/env bash
# Check a version of the plugin before it is released on GitHub or
# submitted to WordPress.org. Changes nothing: it builds both zips into a
# temporary folder (scripts/build-release.sh) and reads them and the Git ref.
#
# Errors stop a release. Warnings need a look and a decision; most matter only
# for WordPress.org. Notes are for information.
#
# Usage: scripts/preflight-release.sh [--ref REF] [--offline] [--strict] [--no-docker]
#   --ref REF    Commit, branch or tag to check (default: HEAD).
#   --offline    Skip checks that ask WordPress.org (latest WordPress version,
#                slug, contributor profiles).
#   --strict     Fail on warnings too (use before a WordPress.org submission).
#   --no-docker  Lint PHP with the local php instead of PHP 7.4 in Docker.
#
# Exit status: 0 when there are no errors (and, with --strict, no warnings).
# Plugin Check runs separately: scripts/plugin-check.sh.

set -euo pipefail

readonly UPDATER_HEADERS='GitHub Plugin URI|Primary Branch|Release Asset|Update URI'
# Development files that must never be in a release zip (paths inside the slug folder).
readonly DEV_FILES='^[^/]+/(\.git|\.agents|\.wordpress-org|\.distignore|\.distignore-wporg|\.gitattributes|\.gitignore|\.woodpecker\.yml|\.github|\.editorconfig|\.gitleaks\.toml|\.codacy\.yml|sonar-project\.properties|\.aidevops\.json|\.task-counter|composer\.(json|lock)|phpcs\.xml(\.dist)?|phpstan(-baseline|-plugin)?\.neon(\.dist)?|vendor|AGENTS\.md|CODE_OF_CONDUCT\.md|CONTRIBUTING\.md|DEVELOPMENT\.md|LAUNCH\.md|SECURITY\.md|STANDARDS\.md|RELEASING\.md|ROADMAP\.md|STABILITY\.md|TESTING\.md|docs|scripts|dist|node_modules|reference-plugins|project-documents)(/|$)|(^|/)(\.DS_Store|__MACOSX|Thumbs\.db)(/|$)|\.(bak|log|orig|swp)$'
readonly README_MAX_BYTES=10240
readonly SHORT_DESC_MAX=150
readonly MAX_TAGS=5
# AGENTS.md is read in every agent session; longer guidance goes in docs/.
readonly AGENTS_MD_MAX_LINES=150
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
# shellcheck source=scripts/lib/plugin.sh disable=SC1091 # followed only with -x
. "$SCRIPT_DIR/lib/plugin.sh"

# Set from the main file at the ref (plugin_identity).
SLUG=""
MAIN_FILE=""
VERSION_CONSTANT=""
# Paths only in the GitHub build (.distignore-wporg): the GitHub updater.
UPDATER_FILES=""

ERRORS=0
WARNINGS=0
TMP_DIR=""
OFFLINE=0
USE_DOCKER=1
CHANGELOG_TXT=""

die() {
	local message="$1"
	printf 'preflight: %s\n' "$message" >&2
	exit 2
}

usage() {
	sed -n '2,18p' "$0" | sed 's/^# \{0,1\}//'
	return 0
}

cleanup() {
	if [[ -n "$TMP_DIR" ]] && [[ -d "$TMP_DIR" ]]; then
		rm -rf "$TMP_DIR"
	fi
	return 0
}

ok() {
	local message="$1"
	printf '  ok     %s\n' "$message"
	return 0
}

err() {
	local message="$1"
	printf '  ERROR  %s\n' "$message"
	ERRORS=$((ERRORS + 1))
	return 0
}

warn() {
	local message="$1"
	printf '  warn   %s\n' "$message"
	WARNINGS=$((WARNINGS + 1))
	return 0
}

note() {
	local message="$1"
	printf '  note   %s\n' "$message"
	return 0
}

section() {
	local title="$1"
	printf '\n%s\n' "$title"
	return 0
}

# Value of "Key: value" in a header (plugin file comment or readme), case-insensitive.
field() {
	local text="$1"
	local key="$2"
	awk -v k="$key" '
		BEGIN { k = tolower(k) }
		{
			line = $0
			sub(/^[ \t*]*/, "", line)
			i = index(line, ":")
			if (i > 0 && tolower(substr(line, 1, i - 1)) == k) {
				v = substr(line, i + 1)
				gsub(/^[ \t]+|[ \t\r]+$/, "", v)
				print v
				exit
			}
		}' <<<"$text"
	return 0
}

# A licence name in one spelling, so "GPLv2 or later", "GPL-2.0-or-later"
# and "GPL-2.0+" compare equal.
license_key() {
	local key="$1"
	key="$(tr '[:upper:]' '[:lower:]' <<<"$key")"
	key="${key//+/orlater}"
	key="${key//[^a-z0-9]/}"
	key="${key/gplv/gpl}"
	key="${key/gpl20/gpl2}"
	key="${key/gpl30/gpl3}"
	printf '%s\n' "$key"
	return 0
}

# 1 if version a < b (numeric parts), else 0.
version_lt() {
	local a="$1"
	local b="$2"
	awk -v a="$a" -v b="$b" 'BEGIN {
		na = split(a, x, "."); nb = split(b, y, "."); n = (na > nb) ? na : nb
		for (i = 1; i <= n; i++) { if ((x[i] + 0) < (y[i] + 0)) { print 1; exit } if ((x[i] + 0) > (y[i] + 0)) { print 0; exit } }
		print 0 }'
	return 0
}

# HTTP status of a URL (000 when offline or unreachable).
http_status() {
	local url="$1"
	local code
	# curl prints 000 itself when it cannot connect, and exits non-zero.
	code="$(curl -sL -o /dev/null -m 20 -w '%{http_code}' "$url" || true)"
	printf '%s' "${code:-000}"
	return 0
}

# README.md's "Version: X.Y.Z" line under the intro, shown on GitHub and in
# the Read Me tab, must match the plugin's Version. A {PREFIX}_VERSION
# placeholder still works in the Read Me tab, but GitHub shows it as written.
check_readme_version() {
	local sha="$1"
	local version="$2"
	git cat-file -e "$sha:README.md" 2>/dev/null || return 0
	local line
	# Read to the end and keep the first match: sed quitting early would end
	# git show with SIGPIPE on a README over the pipe buffer (pipefail, set -e).
	line="$(git show "$sha:README.md" | sed -nE 's/^Version:[[:space:]]*//p')"
	line="${line%%$'\n'*}"
	if [[ -z "$line" ]]; then
		return 0
	elif [[ "$line" = "$version" ]]; then
		ok "README.md Version: matches"
	elif [[ "$line" = "{${VERSION_CONSTANT}}" ]]; then
		warn "README.md shows 'Version: $line' on GitHub; write the version ($version) instead"
	else
		err "README.md Version: is '$line', Version: is '$version'"
	fi
	return 0
}

check_versions() {
	local plugin_header="$1"
	local readme="$2"
	local main_php="$3"
	section "Versions and headers"

	local version constant stable
	version="$(field "$plugin_header" "Version")"
	constant="$(printf '%s\n' "$main_php" | sed -nE "/define\([[:space:]]*['\"]${VERSION_CONSTANT}['\"]/{s/.*,[[:space:]]*['\"]([^'\"]+)['\"].*/\1/p;q;}")"
	stable="$(field "$readme" "Stable tag")"

	if grep -Eq '^[0-9]+\.[0-9]+(\.[0-9]+)?$' <<<"$version"; then
		ok "Version: $version (numbers only, so GitHub updates and WordPress.org treat it as stable)"
	else
		err "Version: '$version' is not X.Y.Z; pre-release versions on main are offered to sites still using Git Updater"
	fi
	if [[ "$constant" = "$version" ]]; then ok "version constant matches ($constant)"; else err "version constant is '$constant', Version: is '$version'"; fi
	if [[ "$stable" = "$version" ]]; then ok "readme.txt Stable tag matches"; else err "readme.txt Stable tag is '$stable', Version: is '$version'"; fi
	if [[ "$(printf '%s' "$stable" | tr '[:upper:]' '[:lower:]')" = "trunk" ]]; then err "Stable tag: trunk is not allowed for new plugins"; fi

	local key header_value readme_value
	for key in "Requires at least" "Requires PHP"; do
		header_value="$(field "$plugin_header" "$key")"
		readme_value="$(field "$readme" "$key")"
		if [[ -z "$header_value" ]]; then
			err "$MAIN_FILE has no '$key' header (WordPress reads it from the plugin file)"
		elif [[ -n "$readme_value" ]] && [[ "$header_value" != "$readme_value" ]]; then
			err "$key: $header_value in $MAIN_FILE, $readme_value in readme.txt"
		else
			ok "$key: $header_value"
		fi
	done

	if grep -Eiq '^[[:space:]*]*Update URI:' <<<"$main_php"; then
		err "Update URI header in $MAIN_FILE: scripts/build-release.sh adds it to the GitHub zip only (WordPress.org rejects it)"
	else
		ok "no Update URI header in Git (the GitHub zip gets one at build time)"
	fi

	local domain license plugin_uri author_uri
	domain="$(field "$plugin_header" "Text Domain")"
	if [[ "$domain" = "$SLUG" ]]; then ok "Text Domain: $domain"; else err "Text Domain is '$domain'; it must be the slug ($SLUG) for language packs"; fi
	license="$(field "$plugin_header" "License")"
	if grep -Eiq 'GPL' <<<"$license"; then ok "License: $license"; else err "License '$license' is not GPL-compatible as written"; fi
	if [[ "$(license_key "$license")" != "gpl2orlater" ]]; then
		warn "License '$license': plugins made from the starter stay GPL-2.0-or-later (STANDARDS.md → Structure)"
	fi
	plugin_uri="$(field "$plugin_header" "Plugin URI")"
	author_uri="$(field "$plugin_header" "Author URI")"
	if [[ -n "$plugin_uri" ]] && [[ "$plugin_uri" = "$author_uri" ]]; then
		warn "Plugin URI and Author URI are the same ($plugin_uri); WordPress.org asks for a Plugin URI unique to the plugin, or none"
	fi
	VERSION="$version"
	return 0
}

# Changelog text (a readme section or changelog.txt): an entry for the version,
# and no Unreleased section left. Text goes to grep -q as a here-string, never
# through a pipe: grep -q stops at the first match, and with pipefail the
# writer's SIGPIPE on text over 64 KB would fail a check that matched.
check_changelog() {
	local label="$1"
	local text="$2"
	local version="$3"
	if grep -Eq "^= *v?$version *=" <<<"$text"; then
		ok "$label changelog has $version"
	else
		warn "$label changelog has no '= $version =' entry"
	fi
	if grep -Eiq '^= *unreleased *=' <<<"$text"; then
		warn "$label changelog still has an Unreleased section; name it $version when releasing"
	fi
	return 0
}

check_readme() {
	local readme="$1"
	local plugin_header="$2"
	local version="$3"
	section "readme.txt"

	local bytes
	bytes="$(printf '%s' "$readme" | wc -c | tr -d ' ')"
	if [[ "$bytes" -le "$README_MAX_BYTES" ]]; then
		ok "size ${bytes} bytes ($((README_MAX_BYTES - bytes)) left)"
	else
		warn "size ${bytes} bytes; WordPress.org says over 10 KB may cause errors (keep the current changelog, move older entries to changelog.txt, trim the description)"
	fi

	local name readme_name
	name="$(field "$plugin_header" "Plugin Name")"
	readme_name="$(printf '%s\n' "$readme" | sed -n '1s/^===[[:space:]]*\(.*[^[:space:]]\)[[:space:]]*===.*/\1/p')"
	if [[ "$readme_name" = "$name" ]]; then ok "name matches the plugin header ($name)"; else warn "readme name '$readme_name' differs from Plugin Name '$name'"; fi

	local license readme_license
	license="$(field "$plugin_header" "License")"
	readme_license="$(field "$readme" "License")"
	if [[ -z "$readme_license" ]]; then
		err "no License: header"
	elif [[ "$(license_key "$readme_license")" = "$(license_key "$license")" ]]; then
		ok "License: $readme_license (the same as the plugin header)"
	else
		err "License '$readme_license' differs from the plugin header's '$license'"
	fi

	local short
	short="$(awk 'NR == 1 { next } !h && /^[ \t]*$/ { h = 1; next } h && /^==/ { exit } h && !/^[ \t]*$/ { print; exit }' <<<"$readme")"
	if [[ -z "$short" ]]; then
		err "no short description (the line after the header)"
	elif [[ "${#short}" -le "$SHORT_DESC_MAX" ]]; then
		ok "short description ${#short} characters"
	else
		warn "short description ${#short} characters; WordPress.org cuts it at $SHORT_DESC_MAX"
	fi

	local tags tag_count
	tags="$(field "$readme" "Tags")"
	tag_count="$(printf '%s\n' "$tags" | awk -F',' '{ print ($0 == "") ? 0 : NF }')"
	if [[ "$tag_count" -ge 1 ]] && [[ "$tag_count" -le "$MAX_TAGS" ]]; then ok "$tag_count tags"; else warn "$tag_count tags; WordPress.org shows at most $MAX_TAGS"; fi

	local tested
	tested="$(field "$readme" "Tested up to")"
	if grep -Eq '^[0-9]+\.[0-9]+$' <<<"$tested"; then
		ok "Tested up to: $tested"
	else
		err "Tested up to '$tested' should be a major version such as 6.8"
	fi
	if [[ "$OFFLINE" -eq 0 ]]; then
		local latest latest_major
		# The first offer is the latest release; later ones are older branches.
		latest="$(curl -s -m 20 'https://api.wordpress.org/core/version-check/1.7/' | grep -o '"current":"[0-9.]*"' | head -n 1 | cut -d'"' -f4 || true)"
		latest_major="$(printf '%s' "$latest" | cut -d. -f1-2)"
		if [[ -z "$latest_major" ]]; then
			note "could not read the latest WordPress version"
		elif [[ "$(version_lt "$tested" "$latest_major")" = "1" ]]; then
			warn "Tested up to $tested, latest WordPress is $latest; test and raise it"
		else
			ok "Tested up to is the latest WordPress ($latest)"
		fi
	fi

	check_changelog "readme.txt" "$(awk '/^== *[Cc]hangelog *==/ { c = 1; next } c && /^== / { exit } c' <<<"$readme")" "$version"
	if [[ -n "$CHANGELOG_TXT" ]]; then
		check_changelog "changelog.txt" "$CHANGELOG_TXT" "$version"
	fi
	if grep -Eiq '^== *upgrade notice *==' <<<"$readme"; then
		local notice
		notice="$(awk '/^== *[Uu]pgrade [Nn]otice *==/ { u = 1; next } u && /^== / { exit } u' <<<"$readme")"
		if grep -Eq "^= *v?$version *=" <<<"$notice"; then
			ok "upgrade notice has $version"
		else
			note "no upgrade notice for $version (optional)"
		fi
	fi
	return 0
}

check_wporg() {
	local readme="$1"
	local plugin_header="$2"
	section "WordPress.org listing"

	local name derived
	name="$(field "$plugin_header" "Plugin Name")"
	derived="$(printf '%s' "$name" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/-/g; s/^-+|-+$//g')"
	if [[ "$derived" = "$SLUG" ]]; then
		ok "the slug WordPress.org makes from '$name' is $SLUG"
	else
		warn "WordPress.org makes the slug from Plugin Name: '$name' becomes '$derived', not '$SLUG'. Ask for '$SLUG' in the submission notes (it can change only before approval), or the text domain will not match"
	fi
	if grep -Eiq '^(wordpress|wp|woocommerce|woo|gutenberg)([^a-z]|$)' <<<"$name"; then
		warn "Plugin Name starts with a trademark ('$name'); WordPress.org does not allow that"
	fi

	if [[ "$OFFLINE" -eq 1 ]]; then
		note "offline: slug and contributor profiles not checked"
		return 0
	fi
	local info
	info="$(curl -s -m 20 "https://api.wordpress.org/plugins/info/1.2/?action=plugin_information&request%5Bslug%5D=$SLUG&request%5Bfields%5D%5Bsections%5D=0" || true)"
	if grep -q '"error"' <<<"$info"; then
		note "slug $SLUG is not listed on WordPress.org yet"
	elif [[ -n "$info" ]]; then
		note "slug $SLUG is already listed on WordPress.org; check it is this plugin"
	fi

	local contributors user status
	contributors="$(field "$readme" "Contributors")"
	if [[ -z "$contributors" ]]; then
		err "readme.txt has no Contributors"
	fi
	for user in $(printf '%s' "$contributors" | tr ',' ' '); do
		status="$(http_status "https://profiles.wordpress.org/$user/")"
		case "$status" in
		200) ok "contributor $user has a WordPress.org profile" ;;
		000) note "could not check contributor $user" ;;
		*) warn "contributor '$user' has no WordPress.org profile (HTTP $status); Contributors must be WordPress.org usernames, case-sensitive" ;;
		esac
	done
	return 0
}

# WIDTHxHEIGHT of a PNG at the ref, from its header (empty if not a PNG).
png_size() {
	local sha="$1"
	local path="$2"
	local bytes
	# od stops reading after the header, so git may get SIGPIPE: ignore that.
	bytes="$(git cat-file blob "$sha:$path" 2>/dev/null | od -An -tu1 -N24 || true)"
	awk '{ for (i = 1; i <= NF; i++) b[++n] = $i }
		END {
			if (n < 24 || b[2] != 80 || b[3] != 78 || b[4] != 71) exit
			printf "%dx%d", ((b[17] * 256 + b[18]) * 256 + b[19]) * 256 + b[20], ((b[21] * 256 + b[22]) * 256 + b[23]) * 256 + b[24]
		}' <<<"$bytes"
	return 0
}

# The listing images in .wordpress-org/ (copied to WordPress.org's SVN
# assets/ folder): banners and icons at their sizes, and screenshot-N files
# numbered from 1 with one readme.txt caption each.
check_wporg_assets() {
	local sha="$1"
	local readme="$2"
	section "WordPress.org assets (.wordpress-org/)"

	local files
	files="$(git ls-tree --name-only "$sha" .wordpress-org/ | sed 's|^\.wordpress-org/||')"

	local spec name size found file
	for spec in banner:772x250 banner:1544x500 icon:128x128 icon:256x256; do
		name="${spec%%:*}-${spec#*:}"
		found=""
		for file in "$name.png" "$name.jpg"; do
			grep -qxF "$file" <<<"$files" && found="$file" && break
		done
		if [[ -z "$found" ]]; then
			if [[ "${spec%%:*}" = icon ]]; then
				warn "no $name.png; WordPress.org shows a generated pattern instead (scripts/build-banner.sh builds it from icon.svg)"
			else
				warn "no $name.png; the WordPress.org page has no banner (scripts/build-banner.sh builds it from banner.svg)"
			fi
			continue
		fi
		size="$(png_size "$sha" ".wordpress-org/$found")"
		if [[ -z "$size" ]]; then
			note "$found: size not checked (not a PNG)"
		elif [[ "$size" = "${spec#*:}" ]]; then
			ok "$found ($size)"
		else
			warn "$found is $size, not ${spec#*:}"
		fi
	done
	if grep -qxF "icon.svg" <<<"$files"; then ok "icon.svg"; fi

	local shots captions
	shots="$(grep -E '^screenshot-[0-9]+\.(png|jpe?g|gif)$' <<<"$files" | sed -E 's/^screenshot-([0-9]+)\..*/\1/' | sort -n || true)"
	captions="$(awk '/^== *[Ss]creenshots *==/ { s = 1; next } s && /^== / { exit } s && /^[0-9]+\. / { sub(/\..*/, ""); print }' <<<"$readme" | sort -n)"
	if [[ -z "$shots" ]] && [[ -z "$captions" ]]; then
		note "no screenshots"
		return 0
	fi
	local numbers dupes count
	numbers="$(sort -un <<<"$shots")"
	dupes="$(uniq -d <<<"$shots")"
	[[ -z "$dupes" ]] || err "more than one screenshot file for number $(number_list "$dupes") (keep one of .png, .jpg, .gif)"
	count="$(grep -c . <<<"$numbers" || true)"
	if [[ "$count" -gt 0 ]] && [[ "$numbers" != "$(seq 1 "$count")" ]]; then
		err "screenshot files are numbered $(number_list "$numbers"); WordPress.org needs 1, 2, 3 and so on with no gaps"
	fi
	if [[ "$numbers" = "$(sort -un <<<"$captions")" ]]; then
		ok "$count screenshots, each with a readme.txt caption"
	else
		err "screenshot files ($(number_list "$numbers")) and readme.txt Screenshots captions ($(number_list "$captions")) do not match: one caption per .wordpress-org/screenshot-N file; GitHub-only pictures go in docs/images/"
	fi
	return 0
}

# Numbers, one per line, as "1, 2, 3" ("none" when there are none).
number_list() {
	local numbers="$1"
	local list
	list="$(grep . <<<"$numbers" | paste -sd ',' - | sed 's/,/, /g' || true)"
	printf '%s' "${list:-none}"
	return 0
}

# Lint PHP (PHP 7.4 in Docker when possible) and JS in an unpacked build.
check_syntax() {
	local dir="$1"
	local label="$2"
	local out php_label
	local expected
	expected="$(find "$dir" -name '*.php' | wc -l | tr -d ' ')"
	if [[ "$USE_DOCKER" -eq 1 ]] && command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
		local image="php:7.4-cli"
		if docker image inspect wordpress:php7.4-apache >/dev/null 2>&1; then image="wordpress:php7.4-apache"; fi
		out="$(docker run --rm -v "$dir:/src:ro" "$image" sh -c 'find /src -name "*.php" -exec php -l {} \;' 2>&1 || true)"
		php_label="PHP 7.4 syntax ($image)"
	elif command -v php >/dev/null 2>&1; then
		out="$(find "$dir" -name '*.php' -exec php -l {} \; 2>&1 || true)"
		php_label="PHP syntax ($(php -r 'echo PHP_VERSION;'); not 7.4)"
	else
		out=""
		php_label=""
		warn "$label: no PHP to lint with"
	fi
	if [[ -n "$php_label" ]]; then
		# Count the files php -l passed, so a lint that never ran cannot pass.
		local passed problems
		passed="$(printf '%s\n' "$out" | grep -c '^No syntax errors' || true)"
		problems="$(printf '%s\n' "$out" | grep -v '^No syntax errors' | grep -v '^[[:space:]]*$' || true)"
		if [[ -z "$problems" ]] && [[ "$passed" -eq "$expected" ]] && [[ "$expected" -gt 0 ]]; then
			ok "$label: $php_label, $passed files"
		elif [[ -z "$problems" ]]; then
			err "$label: PHP lint checked $passed of $expected files"
		else
			err "$label: $php_label errors:"
			printf '%s\n' "$problems" | sed 's/^/           /'
		fi
	fi
	if command -v node >/dev/null 2>&1; then
		out="$(find "$dir" -name '*.js' -exec node --check {} \; 2>&1 || true)"
		if [[ -z "$out" ]]; then ok "$label: JS syntax"; else err "$label: JS syntax errors:"; printf '%s\n' "$out" | sed 's/^/           /'; fi
	else
		warn "$label: node not found, JS not checked"
	fi
	return 0
}

# Shared checks for a release zip; prints its unpacked folder in UNPACKED.
check_zip() {
	local zip_path="$1"
	local label="$2"
	local dir="$TMP_DIR/unpacked-$label"
	local list tops dev size
	list="$(unzip -Z1 "$zip_path")"
	tops="$(printf '%s\n' "$list" | cut -d/ -f1 | sort -u | tr '\n' ' ')"
	if [[ "$tops" = "$SLUG " ]]; then ok "$label: one $SLUG/ folder"; else err "$label: top level is '$tops', must be only $SLUG/"; fi
	if grep -qx "$SLUG/$MAIN_FILE" <<<"$list"; then ok "$label: $SLUG/$MAIN_FILE present"; else err "$label: $SLUG/$MAIN_FILE missing"; fi
	if grep -qx "$SLUG/LICENSE" <<<"$list"; then ok "$label: LICENSE present"; else err "$label: LICENSE missing (the GPL needs its text shipped with the code)"; fi
	dev="$(printf '%s\n' "$list" | grep -E "$DEV_FILES" || true)"
	if [[ -z "$dev" ]]; then ok "$label: no development files"; else err "$label: development files: $(printf '%s' "$dev" | tr '\n' ' ')"; fi
	size="$(wc -c <"$zip_path" | tr -d ' ')"
	note "$label: $(basename "$zip_path"), $((size / 1024)) KB, $(printf '%s\n' "$list" | grep -cv '/$') files"
	mkdir -p "$dir"
	unzip -q "$zip_path" -d "$dir"
	check_syntax "$dir" "$label"
	UNPACKED="$dir/$SLUG"
	return 0
}

check_builds() {
	local github_zip="$1"
	local wporg_zip="$2"
	local version="$3"
	section "Release zips"

	if [[ "$(basename "$github_zip")" = "$SLUG-$version.zip" ]]; then
		ok "GitHub asset name $SLUG-$version.zip (sites install only that name)"
	else
		err "GitHub asset is $(basename "$github_zip"), expected $SLUG-$version.zip"
	fi
	case "$(basename "$wporg_zip")" in
	"$SLUG"*) err "WordPress.org zip name starts with $SLUG; sites could install it from GitHub" ;;
	*) ok "WordPress.org zip name does not start with $SLUG" ;;
	esac

	UNPACKED=""
	check_zip "$github_zip" "github"
	local github_dir="$UNPACKED" path
	if [[ -z "$UPDATER_FILES" ]]; then
		note "no .distignore-wporg: both builds hold the same files"
	fi
	for path in $UPDATER_FILES; do
		if [[ -e "$github_dir/$path" ]]; then ok "github: has $path"; else err "github: $path missing (listed in .distignore-wporg)"; fi
	done
	if grep -Eq "^[[:space:]*]*GitHub Plugin URI:" "$github_dir/$MAIN_FILE"; then ok "github: has the GitHub Plugin URI header"; else err "github: no GitHub Plugin URI header, sites cannot update it from GitHub"; fi
	if grep -Eq "^[[:space:]*]*Update URI:[[:space:]]*https://github\.com/" "$github_dir/$MAIN_FILE"; then
		ok "github: has an Update URI on github.com (WordPress.org never offers a same-slug plugin for it)"
	else
		err "github: no Update URI on github.com; WordPress.org could offer another plugin with the same slug"
	fi

	check_zip "$wporg_zip" "wporg"
	local wporg_dir="$UNPACKED"
	for path in $UPDATER_FILES; do
		if [[ -e "$wporg_dir/$path" ]]; then err "wporg: $path must not be in the WordPress.org build"; else ok "wporg: no $path"; fi
	done
	if grep -Eq "^[[:space:]*]*($UPDATER_HEADERS):" "$wporg_dir/$MAIN_FILE"; then err "wporg: GitHub updater header lines still in $MAIN_FILE"; else ok "wporg: no GitHub updater header lines"; fi
	local hits
	hits="$(grep -rEl --include='*.php' --include='*.js' 'gu_override_dot_org|api\.github\.com/repos|Plugin_Upgrader|Theme_Upgrader|site_transient_update_plugins|auto_update_(plugin|theme)' "$wporg_dir" 2>/dev/null | sed "s|^$wporg_dir/||" || true)"
	if [[ -z "$hits" ]]; then
		ok "wporg: no code that installs or updates plugins from elsewhere"
	else
		warn "wporg: check these install or update code (guideline 8 allows only WordPress.org sources): $(printf '%s' "$hits" | tr '\n' ' ')"
	fi

	section "Remote assets and services (WordPress.org build)"
	hits="$(grep -rEn "(wp_(enqueue|register)_(script|style)|<script|<link)[^;]*['\"](https?:)?//" "$wporg_dir" --include='*.php' 2>/dev/null | sed "s|^$wporg_dir/||" | cut -c1-160 || true)"
	if [[ -z "$hits" ]]; then ok "no scripts or styles loaded from other sites"; else warn "scripts or styles from other sites (guideline 8: ship them in the plugin unless they are part of a service):"; printf '%s\n' "$hits" | sed 's/^/           /'; fi
	local readme_text hosts host missing=""
	readme_text="$(cat "$wporg_dir/readme.txt")"
	hosts="$(grep -rEoh 'https?://[A-Za-z0-9.-]+\.[a-z]{2,}' "$wporg_dir/includes" "$wporg_dir/blocks" 2>/dev/null | sed -E 's|https?://||; s|^www\.||' | sort -u || true)"
	for host in $hosts; do
		case "$host" in
		w3.org | gnu.org | wordpress.org | *.wordpress.org | w.org | *.w.org | wp.org | *.wp.org | example.com | *.example.com) continue ;;
		*) ;;
		esac
		if ! grep -Fqi "$host" <<<"$readme_text"; then missing="$missing $host"; fi
	done
	if [[ -z "$missing" ]]; then
		ok "every host in includes/ and blocks/ is named in readme.txt"
	else
		note "hosts in code not named in readme.txt (fine if they are only links; services the plugin contacts need an External services entry):$missing"
	fi

	# Checks for parts only some plugins have; each runs when its files exist.
	# A plugin's own checks: scripts/preflight-plugin.sh defines plugin_preflight,
	# which gets the unpacked GitHub build and can use section, ok, warn and err.
	if [[ -f "$SCRIPT_DIR/preflight-plugin.sh" ]]; then
		# shellcheck source=/dev/null
		. "$SCRIPT_DIR/preflight-plugin.sh"
		plugin_preflight "$github_dir"
	fi
	if [[ -f "$SCRIPT_DIR/replaced-plugins.php" ]]; then
		check_replaced_count "$github_dir"
	fi
	return 0
}

# README.md's "<Plugin Name> replaces **N plugins**" line matches the
# 'replaces' entries in the code (scripts/replaced-plugins.php).
check_replaced_count() {
	local dir="$1"
	section "Replaced plugins"
	if ! command -v php >/dev/null 2>&1; then
		warn "php not found, the replaced plugins count in README.md was not checked"
		return 0
	fi
	local out
	if out="$(php "$SCRIPT_DIR/replaced-plugins.php" --check "$dir" 2>&1)"; then
		ok "$out"
	else
		err "$out"
	fi
	return 0
}

# Core files match the starter's (scripts/sync-core.sh --check), when a
# checkout of the starter is at hand. A warning, not an error: the starter's
# checkout may be behind, and only a person can tell which side is right.
check_core_files() {
	section "Core files"
	local out status=0
	out="$(bash "$SCRIPT_DIR/sync-core.sh" --check 2>&1)" || status=$?
	case "$status" in
	0) ok "$(printf '%s\n' "$out" | tail -n 1)" ;;
	1) warn "$(printf '%s\n' "$out" | sed -n '2,$p' | tr '\n' ' ')" ;;
	*) note "not compared: ${out#sync-core: }" ;;
	esac
	return 0
}

# AGENTS.md stays a short map (STANDARDS.md → Agent docs): under
# AGENTS_MD_MAX_LINES lines, it sends agents to STANDARDS.md, and it names
# every docs/*.md (top level) and only ones that exist, so agents find each
# task doc. Warnings: only a person can judge
# what moves.
check_agent_docs() {
	local sha="$1"
	section "Agent docs"
	local agents
	if ! agents="$(git show "$sha:AGENTS.md" 2>/dev/null)"; then
		warn "AGENTS.md missing: agents need the plugin's names and its own rules"
		return 0
	fi
	local lines problems=0
	lines="$(printf '%s\n' "$agents" | wc -l | tr -d ' ')"
	if [[ "$lines" -gt "$AGENTS_MD_MAX_LINES" ]]; then
		warn "AGENTS.md is $lines lines (most $AGENTS_MD_MAX_LINES): move sections only one kind of task needs to docs/, with one line saying when to read each"
		problems=1
	fi
	if ! grep -qF 'STANDARDS.md' <<<"$agents"; then
		warn "AGENTS.md does not send agents to STANDARDS.md, so they miss the rules every plugin shares"
		problems=1
	fi
	local doc
	while IFS= read -r doc; do
		[[ -n "$doc" ]] || continue
		if ! grep -qF "$doc" <<<"$agents"; then
			warn "$doc is not named in AGENTS.md, so agents will not find it"
			problems=1
		fi
	# Agent docs are docs/{topic}.md; subfolders such as docs/metrics/ hold
	# generated data, not guidance.
	done < <(git ls-tree --name-only "$sha" -- docs/ | grep -E '^docs/[^/]+\.md$' || true)
	while IFS= read -r doc; do
		[[ -n "$doc" ]] || continue
		if ! git cat-file -e "$sha:$doc" 2>/dev/null; then
			warn "AGENTS.md names $doc, which does not exist"
			problems=1
		fi
	done < <(printf '%s\n' "$agents" | grep -oE 'docs/[A-Za-z0-9._/-]+\.md' | sort -u || true)
	[[ "$problems" -eq 1 ]] || ok "AGENTS.md is $lines lines and names every doc in docs/"
	return 0
}

# Every plugin keeps two credits in README.md and readme.txt (STANDARDS.md →
# Structure): Built with AI, linking aidevops, and the line starting
# "Made from " that links the starter. Warnings: a person writes them.
check_credits() {
	local sha="$1"
	section "Credits"
	local file text problems=0
	for file in README.md readme.txt; do
		if ! text="$(git show "$sha:$file" 2>/dev/null)"; then
			warn "$file missing"
			problems=1
			continue
		fi
		if ! grep -qF 'aidevops.sh' <<<"$text"; then
			warn "$file has no Built with AI credit linking aidevops (https://aidevops.sh)"
			problems=1
		fi
		if ! grep -qE '^Made from .*https://github\.com/' <<<"$text"; then
			warn "$file has no line starting 'Made from ' with a link to the starter on GitHub"
			problems=1
		fi
	done
	[[ "$problems" -eq 1 ]] || ok "README.md and readme.txt credit aidevops and the starter"
	return 0
}

# Licence (STANDARDS.md → Structure): LICENSE in Git, the GPL notice in the
# main file, and the starter's copyright line in the main file and README.md
# (a plugin's own line goes above it). Warnings: a person writes them.
check_licence() {
	local sha="$1"
	section "Licence"
	local starter="copyright (C) 2026 Marcus Quinn"
	local file text problems=0
	if ! git cat-file -e "$sha:LICENSE" 2>/dev/null; then
		warn "no LICENSE file (the GPL's text; copy the starter's)"
		problems=1
	fi
	text="$(git show "$sha:$MAIN_FILE")"
	if ! grep -qF 'GNU General Public License' <<<"$text"; then
		warn "$MAIN_FILE has no GPL notice in its header comment"
		problems=1
	fi
	# A line starting "Copyright (C) " is the plugin's own (in the starter,
	# the starter's line is its own); "Parts copyright" is not.
	for file in "$MAIN_FILE" README.md; do
		text="$(git show "$sha:$file" 2>/dev/null || true)"
		if ! grep -Eq '^[[:space:]*]*Copyright \(C\) ' <<<"$text"; then
			warn "$file has no copyright line of its own ('Copyright (C) year owner'), above the starter's"
			problems=1
		fi
		if ! grep -qiF "$starter" <<<"$text"; then
			warn "$file has no line with the starter's 'Copyright (C) 2026 Marcus Quinn'; keep it below your own"
			problems=1
		fi
	done
	[[ "$problems" -eq 1 ]] || ok "LICENSE, the GPL notice, and both copyright lines (the plugin's and the starter's) are present"
	return 0
}

# Every plugin except SEO Pro Stack recommends it in README.md only, with a
# line starting "Works well with " (STANDARDS.md → Structure). readme.txt
# never mentions it: WordPress.org reviewers check it for promotion.
check_recommendation() {
	local sha="$1"
	section "Recommendation"
	if [[ "$SLUG" = "seoprostack" ]]; then
		ok "SEO Pro Stack does not recommend itself"
		return 0
	fi
	local file text problems=0
	for file in README.md readme.txt; do
		# Missing files already warn under Credits; read them as empty here.
		text="$(git show "$sha:$file" 2>/dev/null || true)"
		case "$file" in
		README.md)
			if ! grep -qE '^Works well with .*github\.com/wpallstars/seoprostack' <<<"$text"; then
				warn "README.md has no line starting 'Works well with ' linking SEO Pro Stack (https://github.com/wpallstars/seoprostack)"
				problems=1
			fi
			;;
		*)
			if grep -qiE 'seo ?pro ?stack' <<<"$text"; then
				warn "$file mentions SEO Pro Stack; keep the recommendation in README.md only"
				problems=1
			fi
			;;
		esac
	done
	[[ "$problems" -eq 1 ]] || ok "README.md recommends SEO Pro Stack; readme.txt does not"
	return 0
}

check_git() {
	local ref="$1"
	local sha="$2"
	local version="$3"
	section "Git"
	local tag_sha
	if tag_sha="$(git rev-parse --verify --quiet "refs/tags/v$version^{commit}")"; then
		if [[ "$tag_sha" = "$sha" ]]; then ok "tag v$version is this commit"; else warn "tag v$version exists on another commit (${tag_sha:0:12}); bump the version"; fi
	else
		note "no tag v$version yet"
	fi
	local main_sha
	if main_sha="$(git rev-parse --verify --quiet "refs/remotes/origin/main^{commit}")"; then
		if git merge-base --is-ancestor "$sha" "$main_sha"; then ok "$ref is on origin/main"; else note "$ref is not on origin/main yet; release only from main"; fi
	fi
	if [[ "$ref" = "HEAD" ]] && [[ -n "$(git status --porcelain --untracked-files=no)" ]]; then
		note "uncommitted changes are not checked (the build comes from HEAD)"
	fi
	return 0
}

main() {
	local ref="HEAD"
	local strict=0
	local arg
	while [[ $# -gt 0 ]]; do
		arg="$1"
		case "$arg" in
		--ref)
			[[ $# -ge 2 ]] || die "--ref needs a value"
			ref="$2"
			shift
			;;
		--offline) OFFLINE=1 ;;
		--strict) strict=1 ;;
		--no-docker) USE_DOCKER=0 ;;
		-h | --help)
			usage
			return 0
			;;
		*) die "unknown argument: $arg" ;;
		esac
		shift
	done

	local root sha
	root="$(git rev-parse --show-toplevel)" || die "run this inside a checkout of the plugin"
	cd "$root"
	sha="$(git rev-parse --verify --quiet "$ref^{commit}")" || die "not a commit: $ref"
	plugin_identity "$sha" || die "cannot tell which plugin this is at $ref"
	SLUG="$PLUGIN_SLUG"
	MAIN_FILE="$PLUGIN_MAIN_FILE"
	VERSION_CONSTANT="${PLUGIN_CONST}_VERSION"
	UPDATER_FILES="$(plugin_wporg_only "$sha")"

	trap cleanup EXIT
	TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/$SLUG-preflight.XXXXXX")"

	local main_php readme plugin_header
	main_php="$(git show "$sha:$MAIN_FILE")"
	readme="$(git show "$sha:readme.txt")" || die "readme.txt missing at $ref"
	if git cat-file -e "$sha:changelog.txt" 2>/dev/null; then
		CHANGELOG_TXT="$(git show "$sha:changelog.txt")"
	fi
	plugin_header="$(printf '%s\n' "$main_php" | sed -n '1,/\*\//p')"

	printf '%s preflight: %s (%s)\n' "$PLUGIN_NAME" "$ref" "${sha:0:12}"
	VERSION=""
	check_versions "$plugin_header" "$readme" "$main_php"
	check_readme_version "$sha" "$VERSION"
	check_readme "$readme" "$plugin_header" "$VERSION"
	check_wporg "$readme" "$plugin_header"
	check_wporg_assets "$sha" "$readme"

	local zips github_zip wporg_zip
	zips="$("$root/scripts/build-release.sh" --ref "$sha" --out "$TMP_DIR/dist" --quiet)" || die "build failed"
	github_zip="$(printf '%s\n' "$zips" | sed -n 1p)"
	wporg_zip="$(printf '%s\n' "$zips" | sed -n 2p)"
	check_builds "$github_zip" "$wporg_zip" "$VERSION"
	if [[ -f "$SCRIPT_DIR/sync-core.sh" ]]; then
		check_core_files
	fi
	check_agent_docs "$sha"
	check_credits "$sha"
	check_licence "$sha"
	check_recommendation "$sha"
	check_git "$ref" "$sha" "$VERSION"

	printf '\n%s error(s), %s warning(s).\n' "$ERRORS" "$WARNINGS"
	if [[ "$ERRORS" -gt 0 ]]; then
		printf 'Not ready: fix the errors.\n'
		return 1
	fi
	if [[ "$strict" -eq 1 ]] && [[ "$WARNINGS" -gt 0 ]]; then
		printf 'Not ready (--strict): resolve or accept the warnings.\n'
		return 1
	fi
	printf 'Next: scripts/plugin-check.sh (Plugin Check on both zips).\n'
	return 0
}

main "$@"
