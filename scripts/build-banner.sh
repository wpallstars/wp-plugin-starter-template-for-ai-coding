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
# Usage: scripts/build-banner.sh
#
# Needs Inkscape 1.x (INKSCAPE=/path/to/inkscape to choose one) and the Zilla Slab
# font installed (wpallstars.com's heading font).

set -euo pipefail

SOURCE=".wordpress-org/banner.svg"

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

export_png() {
	local inkscape="$1"
	local width="$2"
	local height="$3"
	"$inkscape" "$SOURCE" --export-type=png --export-background-opacity=1 \
		--export-width="$width" --export-height="$height" \
		--export-filename=".wordpress-org/banner-${width}x${height}.png"
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
	export_png "$inkscape" 1544 500
	export_png "$inkscape" 772 250

	ls -l admin/images/banner.svg .wordpress-org/banner-1544x500.png .wordpress-org/banner-772x250.png
	return 0
}

main "$@"
