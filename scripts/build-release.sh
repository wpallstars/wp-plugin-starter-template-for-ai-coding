#!/usr/bin/env bash
# Build the release zips of the plugin from a Git ref.
#
# Two builds of the same version, both with one {slug}/ folder inside (the
# slug is the main file's name, scripts/lib/plugin.sh):
#   {slug}-X.Y.Z.zip
#       GitHub release asset: the files in Git, less .distignore, with an
#       "Update URI: https://github.com/{owner}/{repo}" header added under
#       "GitHub Plugin URI", so WordPress.org never offers another plugin
#       with the same slug in its place.
#   wordpress-org-{slug}-X.Y.Z.zip
#       WordPress.org build: the same, less the files in .distignore-wporg and
#       the GitHub updater header lines, and without Update URI. Each text
#       listed in .wporg-links (affiliate links) is replaced by its plain
#       one. Its name is not {slug}-X.Y.Z.zip, so no updater installs it even
#       if it is attached to a GitHub release by mistake. Never attach it to
#       one.
#   SHA256SUMS
#
# Files come from the Git ref (git archive), never from the working tree, so
# uncommitted changes and untracked files are never included.
#
# Usage: scripts/build-release.sh [--ref REF] [--out DIR] [--quiet]
#   --ref REF   Commit, branch or tag to build (default: HEAD).
#   --out DIR   Output folder (default: dist/ in the repository, gitignored).
#   --quiet     Print only the paths of the zips.
#
# Needs git, rsync, zip, unzip and shasum or sha256sum (and perl with a
# .wporg-links file).
#
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Marcus Quinn
# Additional terms (GPL-3.0 section 7(b)): ATTRIBUTION.txt

set -euo pipefail
umask 022
export TZ=UTC

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
# shellcheck source=scripts/lib/plugin.sh disable=SC1091 # followed only with -x
. "$SCRIPT_DIR/lib/plugin.sh"
readonly WPORG_IGNORE=".distignore-wporg"
# Affiliate links and their plain replacements for the WordPress.org build.
readonly WPORG_LINKS=".wporg-links"
# Header lines read only by GitHub updaters (ours and Git Updater); left out of the WordPress.org build.
readonly WPORG_STRIP_HEADERS='GitHub Plugin URI|Primary Branch|Release Asset'

TMP_DIR=""
SLUG=""
MAIN_FILE=""

die() {
	local message="$1"
	printf 'build-release: %s\n' "$message" >&2
	exit 1
}

usage() {
	sed -n '2,29p' "$0" | sed 's/^# \{0,1\}//'
	return 0
}

cleanup() {
	if [[ -n "$TMP_DIR" ]] && [[ -d "$TMP_DIR" ]]; then
		rm -rf "$TMP_DIR"
	fi
	return 0
}

need() {
	local tool="$1"
	command -v "$tool" >/dev/null 2>&1 || die "needs $tool"
	return 0
}

# Version: header of the main file at a commit.
version_at() {
	local sha="$1"
	git show "$sha:$MAIN_FILE" | sed -n 's/^[[:space:]*]*Version:[[:space:]]*\([^[:space:]]*\).*/\1/p' | head -n 1
	return 0
}

sha256_of() {
	local file="$1"
	if command -v shasum >/dev/null 2>&1; then
		shasum -a 256 "$file" | cut -d' ' -f1
	else
		sha256sum "$file" | cut -d' ' -f1
	fi
	return 0
}

# Zip <folder>/<SLUG> as <zip>, with the slug folder at the top. Fixed times,
# modes (umask) and entry order make the same ref give the same zip with the
# same zip tool (another zip or zlib version may compress differently).
make_zip() {
	local folder="$1"
	local zip_path="$2"
	local partial="$zip_path.partial"
	rm -f "$zip_path" "$partial"
	(cd "$folder" && find "$SLUG" -exec touch -h -t 202001010000 {} + && find "$SLUG" | LC_ALL=C sort | zip -qX "$partial" -@)
	mv "$partial" "$zip_path"
	return 0
}

# Add "Update URI: https://github.com/{owner}/{repo}" under the GitHub Plugin
# URI header of the GitHub build's main file (WordPress 5.8+ then never asks
# WordPress.org about it). Fails when there is no such header or it is not a
# repository.
add_update_uri() {
	local main="$1"
	local added="$main.tmp"
	awk '
		!done && /^[[:space:]*]*GitHub Plugin URI:/ {
			print
			repo = $0
			sub(/^[^:]*:[[:space:]]*/, "", repo)
			sub(/[[:space:]]+$/, "", repo)
			sub(/^(https?:\/\/)?(www\.)?github\.com\//, "", repo)
			sub(/(\.git)?\/*$/, "", repo)
			if (repo !~ /^[A-Za-z0-9][A-Za-z0-9-]*\/[A-Za-z0-9._-]+$/) { exit 2 }
			prefix = $0
			sub(/GitHub Plugin URI:.*/, "", prefix)
			printf "%sUpdate URI:        https://github.com/%s\n", prefix, repo
			done = 1
			next
		}
		{ print }
		END { if (!done) { exit 3 } }' "$main" >"$added" || {
		rm -f "$added"
		die "no usable GitHub Plugin URI header in $MAIN_FILE for the Update URI"
	}
	mv "$added" "$main"
	return 0
}

# Remove the GitHub updater header lines from the main file of a build: only
# in the plugin header (up to the first */), not lines further down.
strip_updater_headers() {
	local main="$1"
	local stripped="$main.tmp"
	awk -v re="^[[:space:]*]*($WPORG_STRIP_HEADERS):" '
		!done && $0 ~ re { next }
		!done && /\*\// { done = 1 }
		{ print }' "$main" >"$stripped"
	mv "$stripped" "$main"
	return 0
}

# Replace each text in a .wporg-links file with its replacement in the text
# files of a build. One pair per line, separated by a tab: the text (such as
# an affiliate link, or only its referral query) and its replacement (the
# plain address, or nothing). Lines starting with # are comments. Each text
# is also replaced in its HTML-escaped forms (& as &amp; or &#038;). A text
# that ends in a letter, digit or one of _ % / + ~ . - is not replaced where
# the link goes on with one of those (?ref=alice is left alone in ?ref=alice2
# and ?ref=alice+vip, different links); a . then a space or the end of the
# text ends a sentence, not the link.
replace_wporg_links() {
	local dir="$1"
	local links="$2"
	[[ -s "$links" ]] || return 0
	need perl
	local file
	while IFS= read -r -d '' file; do
		WPORG_LINKS_FILE="$links" perl -i -pe '
			BEGIN {
				open(my $fh, "<", $ENV{WPORG_LINKS_FILE}) or die "build-release: cannot read .wporg-links: $!\n";
				while (my $line = <$fh>) {
					$line =~ s/\r?\n$//;
					next if $line =~ /^\s*(#|$)/;
					my ($from, $to) = split /\t+/, $line, 2;
					$to = "" unless defined $to;
					die "build-release: no tab in .wporg-links line: $line\n" unless $line =~ /\t/ && length $from;
					my $end = $from =~ m{[A-Za-z0-9_%/+~.-]\z} ? q{(?![A-Za-z0-9_%/+~-]|\.[A-Za-z0-9_%/+~-])} : q{};
					for my $amp ("&", "&amp;", "&#038;") {
						(my $f = $from) =~ s/&/$amp/g;
						(my $t = $to) =~ s/&/$amp/g;
						push @pairs, [qr/\Q$f\E$end/, $t];
					}
				}
			}
			for my $pair (@pairs) { s/$pair->[0]/$pair->[1]/g }
		' "$file"
	done < <(find "$dir" -type f \( -name '*.php' -o -name '*.js' -o -name '*.css' -o -name '*.json' -o -name '*.html' -o -name '*.md' -o -name '*.txt' -o -name '*.svg' -o -name '*.xml' -o -name '*.pot' -o -name '*.po' \) -print0)
	return 0
}

main() {
	local ref="HEAD"
	local out=""
	local quiet=0
	local arg
	while [[ $# -gt 0 ]]; do
		arg="$1"
		case "$arg" in
		--ref)
			[[ $# -ge 2 ]] || die "--ref needs a value"
			ref="$2"
			shift
			;;
		--out)
			[[ $# -ge 2 ]] || die "--out needs a value"
			out="$2"
			shift
			;;
		--quiet) quiet=1 ;;
		-h | --help)
			usage
			return 0
			;;
		*) die "unknown argument: $arg" ;;
		esac
		shift
	done

	local tool
	for tool in git rsync zip unzip; do
		need "$tool"
	done

	local root sha version
	root="$(git rev-parse --show-toplevel)" || die "run this inside a checkout of the plugin"
	cd "$root"
	sha="$(git rev-parse --verify --quiet "$ref^{commit}")" || die "not a commit: $ref"
	plugin_identity "$sha" || die "cannot tell which plugin this is at $ref"
	SLUG="$PLUGIN_SLUG"
	MAIN_FILE="$PLUGIN_MAIN_FILE"
	version="$(version_at "$sha")"
	[[ -n "$version" ]] || die "no Version: header in $MAIN_FILE at $ref"

	if [[ "$ref" = "HEAD" ]] && [[ -n "$(git status --porcelain --untracked-files=no)" ]] && [[ "$quiet" -eq 0 ]]; then
		printf 'Note: uncommitted changes are not in the build (it is made from HEAD).\n'
	fi

	[[ -n "$out" ]] || out="$root/dist"
	mkdir -p "$out"
	out="$(cd "$out" && pwd)"

	trap cleanup EXIT
	TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/$SLUG-build.XXXXXX")"
	mkdir -p "$TMP_DIR/src" "$TMP_DIR/github/$SLUG" "$TMP_DIR/wporg/$SLUG"

	git archive --format=tar "$sha" | tar -x -C "$TMP_DIR/src"
	# .distignore lists itself and is export-ignored, so read it from Git.
	git show "$sha:.distignore" >"$TMP_DIR/distignore" || die ".distignore missing at $ref"
	rsync -a --exclude-from="$TMP_DIR/distignore" "$TMP_DIR/src/" "$TMP_DIR/github/$SLUG/"
	[[ -f "$TMP_DIR/github/$SLUG/$MAIN_FILE" ]] || die "$MAIN_FILE is not in the build; check .distignore"

	if git cat-file -e "$sha:$WPORG_IGNORE" 2>/dev/null; then
		git show "$sha:$WPORG_IGNORE" >"$TMP_DIR/wporg-ignore"
	else
		: >"$TMP_DIR/wporg-ignore"
	fi
	rsync -a --exclude-from="$TMP_DIR/wporg-ignore" "$TMP_DIR/github/$SLUG/" "$TMP_DIR/wporg/$SLUG/"
	strip_updater_headers "$TMP_DIR/wporg/$SLUG/$MAIN_FILE"
	if git cat-file -e "$sha:$WPORG_LINKS" 2>/dev/null; then
		git show "$sha:$WPORG_LINKS" >"$TMP_DIR/wporg-links"
		replace_wporg_links "$TMP_DIR/wporg/$SLUG" "$TMP_DIR/wporg-links"
	fi
	add_update_uri "$TMP_DIR/github/$SLUG/$MAIN_FILE"

	local github_zip="$out/$SLUG-$version.zip"
	local wporg_zip="$out/wordpress-org-$SLUG-$version.zip"
	make_zip "$TMP_DIR/github" "$github_zip"
	make_zip "$TMP_DIR/wporg" "$wporg_zip"

	{
		printf '%s  %s\n' "$(sha256_of "$github_zip")" "$(basename "$github_zip")"
		printf '%s  %s\n' "$(sha256_of "$wporg_zip")" "$(basename "$wporg_zip")"
	} >"$out/SHA256SUMS"

	if [[ "$quiet" -eq 1 ]]; then
		printf '%s\n%s\n' "$github_zip" "$wporg_zip"
		return 0
	fi
	printf '%s %s from %s (%s)\n' "$PLUGIN_NAME" "$version" "$ref" "${sha:0:12}"
	printf '  GitHub release:  %s (%s files)\n' "$github_zip" "$(unzip -Z1 "$github_zip" | grep -cv '/$')"
	printf '  WordPress.org:   %s (%s files)\n' "$wporg_zip" "$(unzip -Z1 "$wporg_zip" | grep -cv '/$')"
	printf '  Checksums:       %s\n' "$out/SHA256SUMS"
	printf 'Check them with: scripts/preflight-release.sh --ref %s\n' "$ref"
	return 0
}

main "$@"
