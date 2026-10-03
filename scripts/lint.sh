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
# With no CHECK, runs them all. phpcs and phpstan need `composer install`.
#
# Exit status: 0 when every check passes, 1 when any fails, 2 on bad usage.

set -euo pipefail

readonly ALL_CHECKS="php js shell workflows phpcs phpstan"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly ROOT
FAILED=""

usage() {
	sed -n '2,17p' "$0" | sed 's/^# \{0,1\}//'
	return 0
}

say() {
	local message="$1"
	printf '\n== %s\n' "$message"
	return 0
}

need_vendor() {
	local tool="$1"
	if [ ! -x "$ROOT/vendor/bin/$tool" ]; then
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
	[ "${#files[@]}" -eq 0 ] && return 0
	# -x follows the scripts' `# shellcheck source=` lines (scripts/lib/).
	shellcheck -x --severity=style "${files[@]}"
	return $?
}

check_workflows() {
	if [ ! -d "$ROOT/.github/workflows" ]; then
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

main() {
	local checks="$*"
	local check
	if [ -z "$checks" ]; then
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

	if [ -n "$FAILED" ]; then
		printf '\nlint: failed:%s\n' "$FAILED" >&2
		return 1
	fi
	printf '\nlint: all passed (%s)\n' "$checks"
	return 0
}

main "$@"
