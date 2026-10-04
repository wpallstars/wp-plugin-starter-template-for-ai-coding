#!/usr/bin/env bash
# Build the plugin's banner from its source, .wordpress-org/banner.svg.
#
#   admin/images/banner.svg
#       Shipped with the plugin, shown at the top of the Read Me tab (and of
#       README.md on GitHub). Text is turned into shapes, so it looks the same
#       without the Zilla Slab font.
#   .wordpress-org/banner-772x250.png
#   .wordpress-org/banner-1544x500.png
#       For the WordPress.org SVN assets/ folder (not in the plugin zip).
#
# And the icons from .wordpress-org/icon.svg (the banner's picture on its
# own, with no words), when the plugin has one:
#
#   .wordpress-org/icon-256x256.png
#   .wordpress-org/icon-128x128.png
#       For assets/ too, with icon.svg itself.
#
# Usage: scripts/build-banner.sh
#
# Needs Inkscape 1.x (INKSCAPE=/path/to/inkscape to choose one) and the Zilla Slab
# font installed (wpallstars.com's heading font).
#
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Marcus Quinn
# Additional terms (GPL-3.0 section 7(b)): ATTRIBUTION.txt

set -euo pipefail

SOURCE=".wordpress-org/banner.svg"
ICON_SOURCE=".wordpress-org/icon.svg"

die() {
	local message="$1"
	printf 'build-banner: %s\n' "$message" >&2
	exit 1
}

find_inkscape() {
	if [[ -n "${INKSCAPE:-}" ]]; then
		printf '%s\n' "$INKSCAPE"
		return 0
	fi
	if command -v inkscape >/dev/null 2>&1; then
		command -v inkscape
		return 0
	fi
	if [[ -x /Applications/Inkscape.app/Contents/MacOS/inkscape ]]; then
		printf '%s\n' /Applications/Inkscape.app/Contents/MacOS/inkscape
		return 0
	fi
	return 1
}

# Export SOURCE as .wordpress-org/NAME-WIDTHxHEIGHT.png.
export_png() {
	local inkscape="$1"
	local source="$2"
	local name="$3"
	local width="$4"
	local height="$5"
	"$inkscape" "$source" --export-type=png --export-background-opacity=1 \
		--export-width="$width" --export-height="$height" \
		--export-filename=".wordpress-org/${name}-${width}x${height}.png"
	return 0
}

main() {
	cd "$(git rev-parse --show-toplevel)"
	[[ -f "$SOURCE" ]] || die "missing $SOURCE"

	local inkscape
	inkscape="$(find_inkscape)" || die "Inkscape not found; set INKSCAPE=/path/to/inkscape"

	if command -v fc-list >/dev/null 2>&1; then
		local families
		families="$(fc-list : family)"
		grep -qi '^Zilla Slab' <<<"$families" || die "the Zilla Slab font is not installed"
	fi

	"$inkscape" "$SOURCE" --export-text-to-path --export-plain-svg \
		--export-filename=admin/images/banner.svg
	export_png "$inkscape" "$SOURCE" banner 1544 500
	export_png "$inkscape" "$SOURCE" banner 772 250
	ls -l admin/images/banner.svg .wordpress-org/banner-1544x500.png .wordpress-org/banner-772x250.png

	if [[ -f "$ICON_SOURCE" ]]; then
		export_png "$inkscape" "$ICON_SOURCE" icon 256 256
		export_png "$inkscape" "$ICON_SOURCE" icon 128 128
		ls -l .wordpress-org/icon-256x256.png .wordpress-org/icon-128x128.png
	else
		printf 'build-banner: no %s, so no icons (WordPress.org needs them)\n' "$ICON_SOURCE" >&2
	fi
	return 0
}

main "$@"
