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
#   build      Plugins with a JavaScript build (a "build" script in
#              package.json): its "check" script (types, lint) if any, then a
#              fresh build, which must match the built files in assets/build/.
# With no CHECK, runs them all. phpcs and phpstan need `composer install`.
#
# Exit status: 0 when every check passes, 1 when any fails, 2 on bad usage.

# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Marcus Quinn
# Additional terms (GPL-3.0 section 7(b)): ATTRIBUTION.txt

set -euo pipefail

readonly ALL_CHECKS="php js shell workflows phpcs phpstan build"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly ROOT
# Built JavaScript and CSS that ship (release zips are made from Git, with
# no build step, so they are committed): DEVELOPMENT.md → JavaScript builds.
readonly BUILD_DIR="assets/build"
FAILED=""

usage() {
	sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'
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
