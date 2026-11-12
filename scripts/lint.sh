#!/usr/bin/env bash
# Code checks for the plugin, the same ones CI runs on every pull request
# (.github/workflows/ci.yml). Changes nothing.
#
# Usage: scripts/lint.sh [CHECK]...
#   php        PHP syntax of every PHP file, with the local php.
#   js         JavaScript syntax of every JS file (node --check).
#   shell      ShellCheck on every shell script.
#   workflows  actionlint on .github/workflows (skipped if not installed).
#   phpcs      WordPress Coding Standards, security sniffs and PHP 7.4
#              compatibility (phpcs.xml.dist).
#   phpstan    Static analysis (phpstan.neon.dist): no new findings beyond
#              phpstan-baseline.neon.
#   hooks      docs/HOOKS.md lists every {prefix}_* hook the code calls, and
#              no supported hook has gone (scripts/check-hooks.js; skipped
#              when there is no docs/HOOKS.md).
#   build      Plugins with a JavaScript build (a "build" script in
#              package.json): its "check" script (types, lint) if any, then a
#              fresh build, which must match the built files in assets/build/.
#   changelog  A pull request adds changelog lines only under "= Unreleased ="
#              in changelog.txt and "### Unreleased" in README.md, never under
#              a released version (base: origin/$GITHUB_BASE_REF, default main;
#              a release PR that renames the heading passes).
# With no CHECK, runs them all. phpcs and phpstan need `composer install`.
#
# Exit status: 0 when every check passes, 1 when any fails, 2 on bad usage.

# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Marcus Quinn
# Additional terms (GPL-3.0 section 7(b)): ATTRIBUTION.txt
# Provenance: wpas-e4502af0f07e8a92. Copies, even of part, keep these lines.

set -euo pipefail

readonly ALL_CHECKS="php js shell workflows phpcs phpstan hooks build changelog"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly ROOT
# Built JavaScript and CSS that ship (release zips are made from Git, with
# no build step, so they are committed): DEVELOPMENT.md → JavaScript builds.
readonly BUILD_DIR="assets/build"
FAILED=""

usage() {
	sed -n '2,27p' "$0" | sed 's/^# \{0,1\}//'
	return 0
}

say() {
	local message="$1"
	printf '\n== %s\n' "$message"
	return 0
}

need_vendor() {
	local tool="$1"
	if [[ ! -x "$ROOT/vendor/bin/$tool" ]]; then
		printf 'lint: vendor/bin/%s is missing; run: composer install\n' "$tool" >&2
		return 1
	fi
	return 0
}

check_php() {
	local file output status=0
	while IFS= read -r -d '' file; do
		if ! output="$(php -l "$file" 2>&1)"; then
			printf '%s\n' "$output"
			status=1
		fi
	done < <(git -C "$ROOT" ls-files -z '*.php')
	return "$status"
}

check_js() {
	local file status=0
	while IFS= read -r -d '' file; do
		node --check "$file" || status=1
	done < <(git -C "$ROOT" ls-files -z '*.js')
	return "$status"
}

check_shell() {
	local files=()
	local file
	while IFS= read -r -d '' file; do
		files+=("$file")
	done < <(git -C "$ROOT" ls-files -z '*.sh')
	[[ "${#files[@]}" -eq 0 ]] && return 0
	# -x follows the scripts' `# shellcheck source=` lines (scripts/lib/).
	shellcheck -x --severity=style "${files[@]}"
	return $?
}

check_workflows() {
	if [[ ! -d "$ROOT/.github/workflows" ]]; then
		return 0
	fi
	if ! command -v actionlint >/dev/null 2>&1; then
		printf 'actionlint is not installed; skipped (CI runs it)\n'
		return 0
	fi
	actionlint
	return $?
}

check_phpcs() {
	need_vendor phpcs || return 1
	vendor/bin/phpcs -q --report=full
	return $?
}

check_phpstan() {
	need_vendor phpstan || return 1
	vendor/bin/phpstan analyse --memory-limit=4G --no-progress
	return $?
}

# STANDARDS.md → Code rules: hooks are a contract with site code.
check_hooks() {
	node "$ROOT/scripts/check-hooks.js"
	return $?
}

# Whether package.json has a script of this name: 0 yes, 1 no (or no
# package.json), 2 when package.json cannot be read (no Node, bad JSON), so
# a broken setup fails instead of reading as "no build".
has_npm_script() {
	local name="$1"
	[[ -f "$ROOT/package.json" ]] || return 1
	if ! command -v node >/dev/null 2>&1; then
		printf 'lint: package.json exists but node is not installed\n' >&2
		return 2
	fi
	node -e 'let s; try { s = require(process.argv[1]).scripts || {}; } catch (e) { console.error("lint: cannot read package.json: " + e.message); process.exit(2); } process.exit(s[process.argv[2]] ? 0 : 1);' "$ROOT/package.json" "$name"
	return $?
}

# Fingerprint of every file in BUILD_DIR (names and contents).
build_fingerprint() {
	[[ -d "$ROOT/$BUILD_DIR" ]] || return 0
	find "$BUILD_DIR" -type f -print0 | LC_ALL=C sort -z | xargs -0 -r shasum -a 256
	return 0
}

check_build() {
	local status=0
	has_npm_script build || status=$?
	if [[ "$status" -eq 1 ]]; then
		printf 'no "build" script in package.json; skipped\n'
		return 0
	fi
	[[ "$status" -eq 0 ]] || return 1
	if [[ ! -f "$ROOT/package-lock.json" ]]; then
		printf 'lint: package-lock.json is missing; run npm install and commit it\n' >&2
		return 1
	fi
	# A clean install in CI; locally only when nothing is installed yet.
	# Packages' install scripts never run (supply-chain risk); a package that
	# needs one is set up in the plugin's own build script (npm rebuild NAME).
	if [[ -n "${CI:-}" || ! -d "$ROOT/node_modules" ]]; then
		npm ci --ignore-scripts --no-audit --no-fund --loglevel=error || return 1
	fi
	status=0
	has_npm_script check || status=$?
	if [[ "$status" -eq 0 ]]; then
		npm run --silent check || return 1
	elif [[ "$status" -ne 1 ]]; then
		return 1
	fi
	local before after
	before="$(build_fingerprint)"
	npm run --silent build || return 1
	after="$(build_fingerprint)"
	if [[ -z "$after" ]]; then
		printf 'lint: the build wrote nothing to %s\n' "$BUILD_DIR" >&2
		return 1
	fi
	if [[ "$before" != "$after" ]]; then
		printf 'lint: %s differed from a fresh build; it is rebuilt now: commit it\n' "$BUILD_DIR" >&2
		return 1
	fi
	return 0
}

# Line numbers (in the new file) of lines a one-file --unified=0 diff on
# stdin adds that start with PREFIX.
added_lines() {
	local prefix="$1"
	awk -v prefix="$prefix" '
		/^@@ / {
			split($3, a, ",")
			n = substr(a[1], 2) + 0
			next
		}
		/^\+\+\+ / { next }
		/^\+/ {
			if (index(substr($0, 2), prefix) == 1) print n
			n++
		}
	'
	return 0
}

# The heading above line NUMBER of FILE (style "eq": "= X ="; "hash": the
# "### X" headings inside README.md's "## Changelog"; empty outside it).
heading_above() {
	local file="$1"
	local number="$2"
	local style="$3"
	awk -v number="$number" -v style="$style" '
		BEGIN { hash = (style == "hash") }
		NR > number { exit }
		hash && /^## / { inlog = ($0 == "## Changelog"); head = ""; next }
		hash && /^### / { head = $0; next }
		!hash && /^= .+ =[[:space:]]*$/ { head = $0 }
		END {
			if (hash && !inlog) head = "(outside the changelog)"
			print head
		}
	' < <(git -C "$ROOT" show "HEAD:$file")
	return 0
}

# The Version: of the plugin's main file (the PHP file in the root with one).
main_file_version() {
	local ref="${1:-}"
	local file version
	while IFS= read -r file; do
		[[ "$file" == */* ]] && continue
		if [[ -n "$ref" ]]; then
			version="$(git -C "$ROOT" show "$ref:$file" 2>/dev/null | sed -n 's/^[[:space:]*]*Version:[[:space:]]*//p' | head -n 1 | tr -d '[:space:]')"
		else
			version="$(sed -n 's/^[[:space:]*]*Version:[[:space:]]*//p' "$ROOT/$file" | head -n 1 | tr -d '[:space:]')"
		fi
		if [[ -n "$version" ]]; then
			printf '%s' "$version"
			return 0
		fi
	done < <(git -C "$ROOT" ls-files '*.php')
	return 0
}

# One file of check_changelog: prints each misplaced line, returns 1 if any.
changelog_file() {
	local base="$1"
	local file="$2"
	local prefix="$3"
	local style="$4"
	local unreleased="$5"
	local version="$6"
	local diff number heading escaped status=0 release=0
	diff="$(git diff --unified=0 "$base"...HEAD -- "$file")"
	[[ -n "$diff" ]] || return 0
	# A release PR renames the Unreleased heading to the new version.
	if [[ -n "$version" && "$version" != "$(main_file_version "$base")" ]]; then
		escaped="${version//./\\.}"
		if grep -Eq '^-(= *Unreleased *=|### *Unreleased)[[:space:]]*$' <<<"$diff" &&
			grep -Eq "^\\+(= *v?${escaped} *=|### *v?${escaped})[[:space:]]*\$" <<<"$diff"; then
			release=1
		fi
	fi
	while IFS= read -r number; do
		[[ -n "$number" ]] || continue
		heading="$(heading_above "$file" "$number" "$style")"
		[[ "$heading" == "(outside the changelog)" ]] && continue
		heading="${heading%"${heading##*[![:space:]]}"}"
		if [[ "$release" == 1 ]] && grep -Eq "^(= *v?${escaped} *=|### *v?${escaped})\$" <<<"$heading"; then
			continue
		fi
		if [[ "$heading" != "$unreleased" ]]; then
			printf '%s:%s: changelog line is under "%s"; move it under "%s"\n' \
				"$file" "$number" "${heading:-no heading}" "$unreleased"
			status=1
		fi
	done < <(printf '%s\n' "$diff" | added_lines "$prefix")
	return "$status"
}

# A pull request's changelog lines belong under Unreleased: a merge conflict
# with the release PR's heading rename can leave one under the released
# version (RELEASING.md → GitHub release).
check_changelog() {
	local base="origin/${GITHUB_BASE_REF:-main}"
	local version status=0
	if ! git rev-parse --verify --quiet "$base" >/dev/null; then
		printf 'no %s to compare with; skipped (CI fetches it)\n' "$base"
		return 0
	fi
	version="$(main_file_version)"
	if [[ -f "$ROOT/changelog.txt" ]]; then
		changelog_file "$base" changelog.txt '* ' eq '= Unreleased =' "$version" || status=1
	fi
	if [[ -f "$ROOT/README.md" ]]; then
		changelog_file "$base" README.md '- ' hash '### Unreleased' "$version" || status=1
	fi
	return "$status"
}

main() {
	local checks="$*"
	local check
	if [[ -z "$checks" ]]; then
		checks="$ALL_CHECKS"
	fi
	for check in $checks; do
		case " $ALL_CHECKS " in
		*" $check "*) ;;
		*)
			usage >&2
			return 2
			;;
		esac
	done

	cd "$ROOT"
	for check in $checks; do
		say "$check"
		if "check_$check"; then
			printf 'ok\n'
		else
			FAILED="$FAILED $check"
		fi
	done

	if [[ -n "$FAILED" ]]; then
		printf '\nlint: failed:%s\n' "$FAILED" >&2
		return 1
	fi
	printf '\nlint: all passed (%s)\n' "$checks"
	return 0
}

main "$@"
