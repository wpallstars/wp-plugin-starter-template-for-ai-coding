#!/usr/bin/env bash
# Deploy log classifier check: runs classify_new_log() from
# scripts/lib/deploy-remote.sh on sample web PHP log lines and compares the
# result with what scripts/deploy-sites.sh must do with them. WordPress's own
# cron could_not_set notice (any language, PHP or Apache log format) is a
# warning; every other line, including look-alikes, fails an install.
#
# Usage: scripts/check-deploy-log.sh [--awk PATH]
#   --awk PATH  Run with this awk (mawk, gawk, ...) first on PATH, as the
#               host's awk differs from macOS's.
#
# One line per case: ok or FAIL, the label and the warning text. Exits 1 on
# any mismatch. Needs bash and awk only; it touches nothing outside a
# temporary folder.

# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Marcus Quinn
# Additional terms (GPL-3.0 section 7(b)): ATTRIBUTION.txt
# Provenance: wpas-e4502af0f07e8a92. Copies, even of part, keep these lines.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR

AWK_PATH=""
parse_args() {
	while [[ $# -gt 0 ]]; do
		local arg="$1" value="${2:-}"
		case "$arg" in
		--awk)
			[[ -n "$value" ]] || {
				echo "--awk needs a path" >&2
				exit 2
			}
			AWK_PATH="$value"
			shift 2
			;;
		-h | --help)
			sed -n '2,12p' "${BASH_SOURCE[0]}"
			exit 0
			;;
		*)
			echo "Unknown option: $arg" >&2
			exit 2
			;;
		esac
	done
	return 0
}
parse_args "$@"

WORK_DIR="$(mktemp -d)"
readonly WORK_DIR
trap 'rm -rf "$WORK_DIR"' EXIT

if [[ -n "$AWK_PATH" ]]; then
	[[ -x "$AWK_PATH" ]] || {
		echo "Not executable: $AWK_PATH" >&2
		exit 2
	}
	mkdir -p "$WORK_DIR/bin"
	ln -s "$(cd "$(dirname "$AWK_PATH")" && pwd)/$(basename "$AWK_PATH")" "$WORK_DIR/bin/awk"
	PATH="$WORK_DIR/bin:$PATH"
fi

export DEPLOY_LIBRARY_ONLY=1
# shellcheck source=scripts/lib/deploy-remote.sh disable=SC1091 # followed only with -x
. "$SCRIPT_DIR/lib/deploy-remote.sh"

readonly TS="[09-Nov-2026 02:53:00 UTC] "
readonly JSON='{"schedule":"daily","args":[],"interval":86400}'
readonly OWN="wpstarter_daily_task"
readonly OWN2="wpstarter_cleanup"
readonly OTHER="otherplugin_sync"
readonly MSG="Could not save cron option."
readonly ENGLISH_RESCHEDULE="Cron reschedule event error for hook: $OWN, Error code: could_not_set, Error message: $MSG, Data: $JSON"
readonly CASE_LOG="$WORK_DIR/php-error.log"

readonly FAIL="fail"
CASES=0
MISMATCHES=0

# check_case LABEL EXPECTED LINE: EXPECTED is "fail" (the install fails) or
# the exact warning text (the install only warns).
# shellcheck disable=SC2034 # the globals set here are read by the sourced library
check_case() {
	local label="$1" expected="$2" line="$3"
	local fails=0 got
	printf '%s\n' "$line" >"$CASE_LOG"
	LOG_FILES=("$CASE_LOG")
	LOG_BEFORE=(0)
	LOG_FIRST=("")
	LOG_INODE=("$(file_inode "$CASE_LOG")")
	CRON_HOOKS_RUN="$OWN $OWN2 "
	classify_new_log
	# deploy-sites.sh fails an install on new lines that are not all contention.
	if [[ "$LOG_NEW_LINES" -gt 0 && "$LOG_FAIL" -eq 1 ]]; then
		fails=1
	fi
	if [[ "$fails" -eq 1 ]]; then
		got="$FAIL"
	else
		got="$LOG_WARN"
	fi
	CASES=$((CASES + 1))
	if [[ "$got" == "$expected" ]]; then
		printf 'ok   %s: %s\n' "$label" "${LOG_WARN:-fail}"
	else
		printf 'FAIL %s: expected "%s", got "%s"\n' "$label" "$expected" "$got"
		MISMATCHES=$((MISMATCHES + 1))
	fi
	return 0
}

RACE="cron race $OWN, "
CONTENTION="cron save contention (1 lines), "

# Warnings: WordPress's own notice.
check_case "warn: English reschedule" "$RACE" "$TS$ENGLISH_RESCHEDULE"
check_case "warn: English unschedule" "$RACE" "${TS}Cron unschedule event error for hook: $OWN, Error code: could_not_set, Error message: $MSG, Data: $JSON"
check_case "warn: Dutch" "$RACE" "${TS}Cron ongepland event fout voor hook: $OWN, foutcode: could_not_set, foutmelding: $MSG, gegevens: $JSON"
check_case "warn: French" "$RACE" "${TS}Erreur de Cron pour le crochet : $OWN, Code d’erreur : could_not_set, Message d’erreur : $MSG, Données : $JSON"
check_case "warn: German" "$RACE" "${TS}Cron-Ereignis-Fehler beim Neuplanen für Hook: $OWN, Fehlercode: could_not_set, Fehlermeldung: $MSG, Daten: $JSON"
check_case "warn: second hook run" "cron race $OWN2, " "${TS}Cron reschedule event error for hook: $OWN2, Error code: could_not_set, Error message: $MSG, Data: $JSON"
check_case "warn: no timestamp" "$RACE" "$ENGLISH_RESCHEDULE"
check_case "warn: Apache format with referer" "$RACE" "[Mon Nov 09 02:53:00.123456 2026] [php:notice] [pid 1234] [client 203.0.113.9:51234] Cron reschedule event error for hook: $OWN, Error code: could_not_set, Error message: $MSG, Data: $JSON, referer: https://example.com/wp-cron.php?doing_wp_cron=1"
check_case "warn: another plugin's hook (contention)" "$CONTENTION" "${TS}Cron reschedule event error for hook: $OTHER, Error code: could_not_set, Error message: $MSG, Data: $JSON"

# Failures: look-alikes and everything else.
check_case "fail: payment task line, own hook" "$FAIL" "${TS}Payment task failed for hook: $OWN, status: could_not_set"
check_case "fail: payment task line, other hook" "$FAIL" "${TS}Payment task failed for hook: $OTHER, status: could_not_set"
check_case "fail: payment task line, trailing text" "$FAIL" "${TS}Payment task failed for hook: $OWN, status: could_not_set, retry later"
check_case "fail: plugin line, digits before hook" "$FAIL" "${TS}Payment task 42 failed for hook: $OWN, Error code: could_not_set, Error message: $MSG, Data: $JSON"
check_case "fail: PHP Notice quoting the notice" "$FAIL" "${TS}PHP Notice:  $ENGLISH_RESCHEDULE"
check_case "fail: PHP Fatal error quoting the notice" "$FAIL" "${TS}PHP Fatal error:  Uncaught Exception: $ENGLISH_RESCHEDULE in /var/www/html/wp-cron.php:12"
check_case "fail: could_not_set_x" "$FAIL" "${TS}Cron reschedule event error for hook: $OWN, Error code: could_not_set_x, Error message: $MSG, Data: $JSON"
check_case "fail: no message or JSON" "$FAIL" "${TS}Cron reschedule event error for hook: $OWN, Error code: could_not_set"
check_case "fail: text after the JSON" "$FAIL" "$TS$ENGLISH_RESCHEDULE and more text"
check_case "fail: plain PHP warning" "$FAIL" "${TS}PHP Warning:  Undefined variable \$value in /var/www/html/wp-content/plugins/example/example.php on line 12"

if [[ "$MISMATCHES" -gt 0 ]]; then
	printf '%d of %d cases failed.\n' "$MISMATCHES" "$CASES" >&2
	exit 1
fi
printf 'All %d cases passed (awk: %s).\n' "$CASES" "$(command -v awk)"
exit 0
