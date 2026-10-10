#!/usr/bin/env bash
# The PLUGIN_* variables are read by the scripts that source this file.
# shellcheck disable=SC2034
# Who the plugin is, read from its main file, so the scripts in scripts/ work
# unchanged in every plugin made from the starter. Source it, then call
# plugin_identity [REF] (default HEAD). It sets:
#
#   PLUGIN_MAIN_FILE  the PHP file at the top of the repository with a
#                     "Plugin Name:" header, for example wp-plugin-starter-template.php
#   PLUGIN_SLUG       its name without .php: the plugin folder and text domain
#   PLUGIN_NAME       the Plugin Name header, for example WP Plugin Starter
#   PLUGIN_PACKAGE    the @package tag, which is also the class prefix
#                     (WPStarter: WPStarter_Settings, WPStarter::features())
#   PLUGIN_CONST      the constant prefix, from define('<PREFIX>_VERSION', ...)
#                     (WPSTARTER)
#   PLUGIN_PREFIX     the option, hook and transient prefix: PLUGIN_CONST in
#                     lower case (wpstarter)
#   PLUGIN_CSS        the CSS class and data attribute prefix, from the admin
#                     screen's "wrap <css>-wrap" class (wps: .wps-card)
#   PLUGIN_REPO       the GitHub Plugin URI header, owner/repo (may be empty)
#
# Files come from the Git ref, never the working tree, like the release build.
#
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Marcus Quinn
# Additional terms (GPL-3.0 section 7(b)): ATTRIBUTION.txt

PLUGIN_MAIN_FILE=""
PLUGIN_SLUG=""
PLUGIN_NAME=""
PLUGIN_PACKAGE=""
PLUGIN_CONST=""
PLUGIN_PREFIX=""
PLUGIN_CSS=""
PLUGIN_REPO=""

# Value of a "Key: value" header line in the text, case-insensitive.
plugin_header_field() {
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

plugin_identity() {
	local ref="${1:-HEAD}"
	local file text found=""
	while IFS= read -r file; do
		case "$file" in
		*.php) ;;
		*) continue ;;
		esac
		# WordPress reads the header from the first 8 KB of the file.
		text="$(git show "$ref:$file" 2>/dev/null || true)"
		if [[ -n "$(plugin_header_field "${text:0:8192}" "Plugin Name")" ]]; then
			[[ -z "$found" ]] || {
				printf 'plugin: more than one main file at %s: %s and %s\n' "$ref" "$found" "$file" >&2
				return 1
			}
			found="$file"
		fi
	done < <(git ls-tree --name-only "$ref" 2>/dev/null)
	if [[ -z "$found" ]]; then
		printf 'plugin: no PHP file with a Plugin Name: header at the top of %s\n' "$ref" >&2
		return 1
	fi

	text="$(git show "$ref:$found")"
	PLUGIN_MAIN_FILE="$found"
	PLUGIN_SLUG="${found%.php}"
	PLUGIN_NAME="$(plugin_header_field "${text:0:8192}" "Plugin Name")"
	# Here-strings, not pipes: sed quitting at the first match would end
	# printf with SIGPIPE on a large file (pipefail).
	PLUGIN_PACKAGE="$(sed -nE '/^[[:space:]*]*@package[[:space:]]+[A-Za-z0-9_]+/{s/^[[:space:]*]*@package[[:space:]]+([A-Za-z0-9_]+).*/\1/p;q;}' <<<"$text")"
	PLUGIN_CONST="$(sed -nE "/define\([[:space:]]*['\"][A-Z0-9_]+_VERSION['\"]/{s/.*define\([[:space:]]*['\"]([A-Z0-9_]+)_VERSION['\"].*/\1/p;q;}" <<<"$text")"
	if [[ -z "$PLUGIN_PACKAGE" ]]; then
		printf 'plugin: %s has no @package tag (the class prefix)\n' "$found" >&2
		return 1
	fi
	if [[ -z "$PLUGIN_CONST" ]]; then
		printf "plugin: %s does not define a <PREFIX>_VERSION constant\n" "$found" >&2
		return 1
	fi
	PLUGIN_PREFIX="$(printf '%s' "$PLUGIN_CONST" | tr '[:upper:]' '[:lower:]')"
	PLUGIN_REPO="$(plugin_header_field "${text:0:8192}" "GitHub Plugin URI")"
	PLUGIN_CSS="$(git show "$ref:admin/includes/class-admin-manager.php" 2>/dev/null | sed -nE 's/.*class="wrap ([a-z0-9]+)-wrap.*/\1/p' | head -n 1)"
	if [[ -z "$PLUGIN_CSS" ]]; then
		printf 'plugin: no "wrap <css>-wrap" class in admin/includes/class-admin-manager.php at %s\n' "$ref" >&2
		return 1
	fi
	return 0
}

# Copy the PLUGIN_* names into FROM_* (from) or TO_* (to), for plugin_map.
plugin_names_as() {
	local side="$1"
	local name
	for name in SLUG NAME PACKAGE CONST PREFIX CSS REPO; do
		eval "export ${side}_${name}=\"\$PLUGIN_${name}\""
	done
	return 0
}

# Rewrite text on stdin from one plugin's names (FROM_*) to another's (TO_*):
# GitHub repository, name, class prefix, constant prefix, slug, prefix and
# CSS prefix, in that order. When the source plugin's slug is also its prefix
# (myplugin), the slug is only the quoted word ('myplugin': text domain,
# admin page) and the main file name; everywhere else it is the prefix.
#
# With FILE (the path the text belongs to), the new name is escaped for where
# it lands: inside PHP string literals ('…' or "…") in .php files, in JSON
# strings in .json files, and as XML text in .xml, .dist and .svg files.
# Comments, Markdown and plain text get it as it is.
#
# ATTRIBUTION.txt is the starter's own licence terms (GPL-3.0 section 7(b)),
# kept word for word in every plugin, so it passes through unchanged.
plugin_map() {
	local file="${1:-}"
	if [[ "$file" = "ATTRIBUTION.txt" ]]; then
		cat
		return 0
	fi
	MAP_FILE="$file" perl -pe '
		BEGIN {
			%e = map { $_ => $ENV{$_} // "" } grep { /^(FROM|TO)_/ } keys %ENV;
			$f = $ENV{MAP_FILE} // "";
			$kind = $f =~ /\.php$/ ? "php" : $f =~ /\.json$/ ? "json" : $f =~ /\.(xml|dist|svg)$/ ? "xml" : "";
			($sq = $e{TO_NAME}) =~ s/([\\\x27])/\\$1/g;
			($dq = $e{TO_NAME}) =~ s/([\\"\$])/\\$1/g;
			($xml = $e{TO_NAME}) =~ s/&/&amp;/g;
			$xml =~ s/</&lt;/g; $xml =~ s/>/&gt;/g; $xml =~ s/"/&quot;/g;
			$from = quotemeta $e{FROM_NAME};
		}
		# PHP: only string literals need escaping; lines that are comments
		# (docblocks, // and #) and the rest of a line after a comment do not.
		# One pass, so a new name that contains the old one is not renamed twice.
		sub php_name {
			my ($text) = @_;
			return $text =~ s/$from/$e{TO_NAME}/gr if $text =~ m{^\s*(\*|/\*|//|#)};
			return $text =~ s{(?<t>\x27(?:[^\x27\\]|\\.)*\x27|"(?:[^"\\]|\\.)*"|(?://|#).*|/\*.*?(?:\*/|$)|$from)}{
				my $t = $+{t};
				$t =~ /^\x27/ ? $t =~ s/$from/$sq/gr : $t =~ /^"/ ? $t =~ s/$from/$dq/gr : $t =~ s/$from/$e{TO_NAME}/gr
			}gre;
		}
		# Only code between <?php (or <?=) and ?> is PHP; the rest is HTML.
		sub php_line {
			my ($line) = @_;
			my $out = "";
			for my $piece (split m{(<\?(?:php\b|=)|\?>)}, $line) {
				if ($piece =~ m{^<\?(?:php|=)$}) { $in_php = 1; $out .= $piece; }
				elsif ($piece eq "?>") { $in_php = 0; $out .= $piece; }
				elsif ($in_php) { $out .= php_name($piece); }
				else { $out .= $piece =~ s/$from/$e{TO_NAME}/gr; }
			}
			return $out;
		}
		s{\Q$e{FROM_REPO}\E}{$e{TO_REPO}}g if $e{FROM_REPO} ne "" && $e{TO_REPO} ne "";
		if ($e{FROM_NAME} eq "") { }
		elsif ($kind eq "php") { $_ = php_line($_); }
		elsif (!/$from/) { }
		elsif ($kind eq "json") { ($j = $e{TO_NAME}) =~ s/([\\"])/\\$1/g; s/$from/$j/g; }
		elsif ($kind eq "xml") { s/$from/$xml/g; }
		else { s/$from/$e{TO_NAME}/g; }
		s{\Q$e{FROM_PACKAGE}\E}{$e{TO_PACKAGE}}g;
		s{\Q$e{FROM_CONST}\E}{$e{TO_CONST}}g;
		if ($e{FROM_SLUG} eq $e{FROM_PREFIX}) {
			s{(["\x27])\Q$e{FROM_SLUG}\E\1}{${1}$e{TO_SLUG}${1}}g;
			s{\b\Q$e{FROM_SLUG}\E\.php\b}{$e{TO_SLUG}.php}g;
		} else {
			s{\Q$e{FROM_SLUG}\E}{$e{TO_SLUG}}g;
		}
		s{\Q$e{FROM_PREFIX}\E}{$e{TO_PREFIX}}g;
		s{\b\Q$e{FROM_CSS}\E(?=[-_A-Z])}{$e{TO_CSS}}g;
	'
	return 0
}

# Value of the environment variable <PLUGIN_CONST>_<NAME>, or the default.
# For example plugin_env PREVIEW_SITE reads WPSTARTER_PREVIEW_SITE.
plugin_env() {
	local name="${PLUGIN_CONST}_$1"
	local default="${2:-}"
	printf '%s' "${!name:-$default}"
	return 0
}

# README.md's badges block (STANDARDS.md → Structure): the lines between
# these markers, the first of which says who writes them.
PLUGIN_BADGES_START="<!-- aidevops:badges:start -->"
PLUGIN_BADGES_END="<!-- aidevops:badges:end -->"
PLUGIN_BADGES_FIRST_LINE="<!-- On GitHub only: the Read Me tab skips this block. scripts/rename-plugin.sh rewrites it. -->"

# The badges block's lines: the first line, then three rows with one blank
# line between them, each a paragraph on GitHub:
#   1. status: CI, the services given, licence and latest release;
#   2. requirements from readme.txt's header (Requires at least, Tested up
#      to, Requires PHP), lines of code and dependencies;
#   3. the languages chart alone: it is 96 px high, so beside 20 px badges
#      it would misalign a row.
# Usage: plugin_badges OWNER/REPO README_TXT "SERVICES" CODACY_ID
#   SERVICES: any of sonarcloud codefactor scorecard; Codacy shows when its
#   project badge ID is given.
plugin_badges() {
	local repo="$1"
	local readme="$2"
	local services=" $3 "
	local codacy="$4"
	local url="https://github.com/$repo"
	local key="${repo/\//_}"
	local shield="https://img.shields.io/badge"
	local wp tested php
	wp="$(plugin_header_field "$readme" "Requires at least")"
	tested="$(plugin_header_field "$readme" "Tested up to")"
	php="$(plugin_header_field "$readme" "Requires PHP")"
	printf '%s\n' "$PLUGIN_BADGES_FIRST_LINE"
	printf '[![CI](%s/actions/workflows/ci.yml/badge.svg?branch=main)](%s/actions/workflows/ci.yml)\n' "$url" "$url"
	if [[ "$services" = *" sonarcloud "* ]]; then
		printf '[![Quality Gate Status](https://sonarcloud.io/api/project_badges/measure?project=%s&metric=alert_status)](https://sonarcloud.io/summary/new_code?id=%s)\n' "$key" "$key"
	fi
	if [[ -n "$codacy" ]]; then
		printf '[![Codacy Badge](https://app.codacy.com/project/badge/Grade/%s)](https://app.codacy.com/gh/%s/dashboard)\n' "$codacy" "$repo"
	fi
	if [[ "$services" = *" codefactor "* ]]; then
		printf '[![CodeFactor](https://www.codefactor.io/repository/github/%s/badge)](https://www.codefactor.io/repository/github/%s)\n' "$repo" "$repo"
	fi
	if [[ "$services" = *" scorecard "* ]]; then
		printf '[![OpenSSF Scorecard](https://api.scorecard.dev/projects/github.com/%s/badge)](https://scorecard.dev/viewer/?uri=github.com/%s)\n' "$repo" "$repo"
	fi
	printf '[![License: GPL v3 or later](%s/License-GPL%%20v3%%20or%%20later-blue.svg)](LICENSE)\n' "$shield"
	printf '[![Latest release](https://img.shields.io/github/v/release/%s)](%s/releases)\n\n' "$repo" "$url"
	if [[ -n "$wp" ]]; then
		printf '[![Requires WordPress](%s/WordPress-%s%%2B-21759B.svg?logo=wordpress)](readme.txt)\n' "$shield" "$wp"
	fi
	if [[ -n "$tested" ]]; then
		printf '[![Tested up to](%s/tested%%20up%%20to-%s-21759B.svg?logo=wordpress)](readme.txt)\n' "$shield" "$tested"
	fi
	if [[ -n "$php" ]]; then
		printf '[![Requires PHP](%s/PHP-%s%%2B-777BB4.svg?logo=php)](readme.txt)\n' "$shield" "$php"
	fi
	printf '[![Lines of code](docs/metrics/badges/loc.svg)](docs/metrics/repo-metrics.md)\n'
	printf '[![Dependencies](docs/metrics/badges/dependencies.svg)](docs/metrics/repo-metrics.md)\n\n'
	printf '[![Languages by lines of code](docs/metrics/badges/languages.svg)](docs/metrics/repo-metrics.md)\n'
	return 0
}

# The services a badges block shows, for plugin_badges: sonarcloud,
# codefactor, scorecard.
plugin_badge_services() {
	local block="$1"
	local found=""
	if grep -qF 'sonarcloud.io/' <<<"$block"; then found="$found sonarcloud"; fi
	if grep -qF 'codefactor.io/' <<<"$block"; then found="$found codefactor"; fi
	if grep -qF 'scorecard.dev/' <<<"$block"; then found="$found scorecard"; fi
	printf '%s' "${found# }"
	return 0
}

# The Codacy project badge ID in a badges block (empty when it has none).
plugin_badge_codacy() {
	local block="$1"
	sed -nE '/app\.codacy\.com\/project\/badge\/Grade\//{s|.*app\.codacy\.com/project/badge/Grade/([0-9A-Za-z]+).*|\1|p;q;}' <<<"$block"
	return 0
}

# The badges block's lines in README.md text on standard input.
plugin_badges_current() {
	START="$PLUGIN_BADGES_START" END="$PLUGIN_BADGES_END" awk '
		$0 == ENVIRON["END"] { exit }
		on { print }
		$0 == ENVIRON["START"] { on = 1 }'
	return 0
}

# README.md text on standard input, with the badges block's lines replaced
# by BLOCK. Call it only when both markers are there.
plugin_badges_replace() {
	local block="$1"
	START="$PLUGIN_BADGES_START" END="$PLUGIN_BADGES_END" BADGES="$block" awk '
		$0 == ENVIRON["END"] { skip = 0 }
		skip { next }
		{ print }
		$0 == ENVIRON["START"] { print ENVIRON["BADGES"]; skip = 1 }'
	return 0
}

# Paths the WordPress.org build leaves out (.distignore-wporg at the ref),
# one per line, without the leading slash: the GitHub updater.
plugin_wporg_only() {
	local ref="${1:-HEAD}"
	git show "$ref:.distignore-wporg" 2>/dev/null | sed -e 's/[[:space:]]*$//' -e '/^#/d' -e '/^$/d' -e 's|^/||' -e 's|/$||'
	return 0
}
