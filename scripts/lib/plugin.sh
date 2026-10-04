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
	printf '%s\n' "$text" | awk -v k="$key" '
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
		}'
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
		if [ -n "$(plugin_header_field "${text:0:8192}" "Plugin Name")" ]; then
			[ -z "$found" ] || {
				printf 'plugin: more than one main file at %s: %s and %s\n' "$ref" "$found" "$file" >&2
				return 1
			}
			found="$file"
		fi
	done < <(git ls-tree --name-only "$ref" 2>/dev/null)
	if [ -z "$found" ]; then
		printf 'plugin: no PHP file with a Plugin Name: header at the top of %s\n' "$ref" >&2
		return 1
	fi

	text="$(git show "$ref:$found")"
	PLUGIN_MAIN_FILE="$found"
	PLUGIN_SLUG="${found%.php}"
	PLUGIN_NAME="$(plugin_header_field "${text:0:8192}" "Plugin Name")"
	PLUGIN_PACKAGE="$(printf '%s\n' "$text" | sed -nE '/^[[:space:]*]*@package[[:space:]]+[A-Za-z0-9_]+/{s/^[[:space:]*]*@package[[:space:]]+([A-Za-z0-9_]+).*/\1/p;q;}')"
	PLUGIN_CONST="$(printf '%s\n' "$text" | sed -nE "/define\([[:space:]]*['\"][A-Z0-9_]+_VERSION['\"]/{s/.*define\([[:space:]]*['\"]([A-Z0-9_]+)_VERSION['\"].*/\1/p;q;}")"
	if [ -z "$PLUGIN_PACKAGE" ]; then
		printf 'plugin: %s has no @package tag (the class prefix)\n' "$found" >&2
		return 1
	fi
	if [ -z "$PLUGIN_CONST" ]; then
		printf "plugin: %s does not define a <PREFIX>_VERSION constant\n" "$found" >&2
		return 1
	fi
	PLUGIN_PREFIX="$(printf '%s' "$PLUGIN_CONST" | tr '[:upper:]' '[:lower:]')"
	PLUGIN_REPO="$(plugin_header_field "${text:0:8192}" "GitHub Plugin URI")"
	PLUGIN_CSS="$(git show "$ref:admin/includes/class-admin-manager.php" 2>/dev/null | sed -nE 's/.*class="wrap ([a-z0-9]+)-wrap.*/\1/p' | head -n 1)"
	if [ -z "$PLUGIN_CSS" ]; then
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
plugin_map() {
	local file="${1:-}"
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

# Paths the WordPress.org build leaves out (.distignore-wporg at the ref),
# one per line, without the leading slash: the GitHub updater.
plugin_wporg_only() {
	local ref="${1:-HEAD}"
	git show "$ref:.distignore-wporg" 2>/dev/null | sed -e 's/[[:space:]]*$//' -e '/^#/d' -e '/^$/d' -e 's|^/||' -e 's|/$||'
	return 0
}
