#!/usr/bin/env bash
# Part of scripts/lib/deploy-remote.sh (see it for what the remote part does):
# Per-site results and the check_sites loop.
# Only functions: sourced by deploy-remote.sh, or bundled with it by
# deploy-sites.sh, never run alone. Its variables are set in deploy-remote.sh.
#
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Marcus Quinn
# Additional terms (GPL-3.0 section 7(b)): ATTRIBUTION.txt
# Provenance: wpas-e4502af0f07e8a92. Copies, even of part, keep these lines.
# shellcheck disable=SC2034,SC2153 # globals are shared across deploy-remote*.sh, which shellcheck reads one file at a time

# The FAIL reason for a killed step ($1: load or cron) on a site that also
# failed another check: then it is a FAIL like before, not UNVERIFIED.
killed_reason() {
	local killed="$1" hooks="${2:-}"
	if [[ "$killed" == load ]]; then
		printf 'WordPress load failed (exit 137); '
	elif [[ "$killed" == cronevent ]]; then
		printf 'cron %s killed (137); ' "${hooks% }"
	else
		printf '%s' "$CRON_LIST_FAILED"
	fi
	return 0
}

# A site's result for a step killed twice ($1: load, cron or cronevent; $2 the
# killed hooks of cronevent, "HOOK HOOK ").
killed_result() {
	local killed="$1" hooks="${2:-}"
	if [[ "$killed" == cronevent ]]; then
		printf 'UNVERIFIED: host killed cron event (137), not confirmed: %s' "${hooks% }"
		return 0
	fi
	printf 'UNVERIFIED: %s' "$KILLED_TEXT"
	[[ "$killed" != cron ]] || printf ' (cron list)'
	return 0
}

# A result with warnings ($1, each ending in ", ").
warn_result() {
	local warn="$1"
	printf 'WARN %s' "${warn%, }"
	return 0
}

# One network site row into ROW: $1 url, $2 status, $3 purged, $4 cron note,
# $5 home, $6 cache, $7 result.
site_row() {
	local url="$1" status="$2" purged="$3" cron_note="$4" home="$5" cache="$6" result="$7"
	printf -v ROW '    site %s\tstatus=%s\tpurged=%s\t%s\thome=%s\tcache=%s\t%s\n' "$url" "${status:-?}" "$purged" "$cron_note" "$home" "$cache" "$result"
	return 0
}

# The fields of one unverified site, for the recheck and its recheck hint,
# separated by the unit separator (none of them holds one): killed step, url,
# status, home, cache, purged, cron note, the site's warnings so far, the
# killed cron hooks.
unverified_record() {
	local killed="$1" url="$2" status="$3" home="$4" cache="$5" purged="$6" cron_note="$7" warn="$8" hooks="${9:-}"
	local sep=$'\x1f'
	printf '%s' "$killed$sep$url$sep$status$sep$home$sep$cache$sep$purged$sep$cron_note$sep$warn$sep$hooks"
	return 0
}

# Called directly: counters, the main row and network lines are results.
# A site that only had a step killed twice (STEP_KILLED) is UNVERIFIED, not
# FAIL: it adds to SITES_UNVERIFIED and UNV_RECORDS (one unverified_record a
# line), for recheck_install.
check_sites() {
	local root="$1"
	local kind urls url status result reason warn web_warn purged network=0
	local load_errors first_code cron_note killed home hooks
	local check_error="home check failed; "
	local url_args=() origin
	CDN_URLS="" MAIN_CF=""
	SITES_TOTAL=0 SITES_FAILED=0 SITES_PURGED=0 PURGE_FAILED=0 SITE_LINES=""
	SITES_UNVERIFIED=0 UNV_RECORDS="" NETWORK=0
	CRON_SUM_RUN=0 CRON_SUM_TOTAL=0 CRON_WARNED="" CRON_HOOKS_RUN=""
	MAIN_STATUS="?" MAIN_CODE="000" MAIN_CACHE="none" MAIN_REASON="" MAIN_RETRIED="" MAIN_LOAD_RETRIED=""
	MAIN_UNVERIFIED="" MAIN_RECHECKED=""
	kind="$(wp_bare "$root" eval 'echo is_multisite() ? "multisite" : "single";')" || return 1
	case "$kind" in
	multisite) network=1 ;;
	single) ;;
	*) return 1 ;;
	esac
	NETWORK="$network"
	urls="$(site_urls "$root" "$kind")" || return 1
	load_errors="$(mktemp)" || return 1
	while IFS= read -r url; do
		[[ -n "$url" ]] || continue
		SITES_TOTAL=$((SITES_TOTAL + 1))
		[[ "$network" -eq 0 ]] || url_args=(--url="$url")
		result="ok" web_warn=""
		site_load "$root" "$load_errors" ${url_args[@]+"${url_args[@]}"}
		reason="$STEP_REASON" warn="$STEP_WARN" purged="$STEP_PURGED" cron_note="$STEP_CRON" killed="$STEP_KILLED" hooks="$STEP_HOOKS"
		cat "$load_errors" >&2
		if ! status="$(wp_bare "$root" ${url_args[@]+"${url_args[@]}"} plugin list --name="$SLUG" --field=status)" || [[ -z "$status" ]]; then
			reason+="status read failed; "
		fi
		origin="$(origin_ip "$root" ${url_args[@]+"${url_args[@]}"})"
		home_check "$url" "$origin" || reason+="$check_error"
		# A busy host can answer one fetch with 5xx (or not at all) while the
		# site is fine: fetch once more after a pause, and fail only if that
		# fails too. A pass on the second fetch is a warning, not silence.
		first_code=""
		if [[ "$HOME_CODE" == 5* || "$HOME_CODE" == "000" ]]; then
			first_code="$HOME_CODE"
			sleep "$HOME_RETRY_DELAY"
			home_check "$url" "$origin" || [[ "$reason" == *"$check_error"* ]] || reason+="$check_error"
		fi
		# 4xx may be the host's firewall: report, but do not fail it (a pinned
		# fetch skips the CDN, so a 4xx there is the origin's own answer).
		if [[ "$HOME_CODE" == 5* || "$HOME_CODE" == "000" ]]; then
			reason+="home failed${first_code:+ ($first_code, then $HOME_CODE)}; "
		elif [[ -n "$first_code" ]]; then
			web_warn+="home retried ($first_code), "
		fi
		[[ "$HOME_CACHE" != *hit* || "$HOME_CACHE" == redirected:* ]] || web_warn+="cached, "
		cdn_step "$url"
		web_warn+="$CDN_WARN"
		warn+="$web_warn"
		home="${HOME_CODE}${HOME_PINNED:+ pinned}"
		if [[ -n "$reason" ]]; then
			[[ -z "$killed" ]] || reason="$(killed_reason "$killed" "$hooks")$reason"
			result="FAIL: ${reason%; }"
			SITES_FAILED=$((SITES_FAILED + 1))
		elif [[ -n "$killed" ]]; then
			result="$(killed_result "$killed" "$hooks")"
			SITES_UNVERIFIED=$((SITES_UNVERIFIED + 1))
			UNV_RECORDS+="$(unverified_record "$killed" "$url" "$status" "$home" "$HOME_CACHE" "$purged" "$cron_note" "$warn" "$hooks")"$'\n'
		elif [[ -n "$warn" ]]; then
			result="$(warn_result "$warn")"
		fi
		if [[ "$SITES_TOTAL" -eq 1 ]]; then
			MAIN_STATUS="$status" MAIN_CODE="$home" MAIN_CACHE="$HOME_CACHE"
			MAIN_REASON="${reason%; }" MAIN_RETRIED="$first_code" MAIN_LOAD_RETRIED="$STEP_LOAD_RETRIED"
			[[ "$result" != UNVERIFIED* ]] || MAIN_UNVERIFIED="${result#UNVERIFIED: }"
		fi
		if [[ "$network" -eq 1 ]]; then
			site_row "$url" "$status" "$purged" "$cron_note" "$home" "$HOME_CACHE" "$result"
			SITE_LINES+="$ROW"
		fi
	done <<<"$urls"
	rm -f "$load_errors"
	[[ "$SITES_TOTAL" -gt 0 ]] || return 1
	return 0
}
