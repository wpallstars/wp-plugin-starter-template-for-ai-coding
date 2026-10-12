#!/usr/bin/env bash
# The part of scripts/deploy-sites.sh that runs on the SSH host. It is not
# run by hand: deploy-sites.sh streams it to bash on the host for a dry run,
# and for --apply copies it with the zip to a private folder there first.
#
# Usage: bash deploy-remote.sh list  SLUG PARENT [SKIP]...
#        bash deploy-remote.sh apply SLUG PARENT VERSION ZIP SHA256 BACKUPS [SKIP]...
#
# PARENT is a pattern for the WordPress folders (wp-config.php and the
# plugin's main file inside); a leading ~/ is the home folder. Only installs
# that already have wp-content/plugins/SLUG/SLUG.php are touched. Each line
# printed is one install; apply exits 1 when any install did not reach
# VERSION or logged new lines.
#
# Bash only, and no process substitution: /dev/fd is missing in some SSH
# sessions. Never wp plugin update: on hosts with HTTP request limiters
# WP-CLI's update check can report the plugin already up to date.
#
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Marcus Quinn
# Additional terms (GPL-3.0 section 7(b)): ATTRIBUTION.txt

set -uo pipefail

WP_CLI="${DEPLOY_WP_CLI:-wp}"
SLUG=""
FAILED=0
SKIPS=()

say() {
	local message="$1"
	printf '%s\n' "$message"
	return 0
}

# A docroot's short name: its own folder name, or the one above it when the
# folder has a common docroot name (~/domains/example.com/public_html is
# example.com).
install_name() {
	local root="$1"
	local name
	name="$(basename "$root")"
	case "$name" in
	public_html | htdocs | html | public | www | web)
		name="$(basename "$(dirname "$root")")"
		;;
	*) ;;
	esac
	printf '%s' "$name"
	return 0
}

skipped() {
	local root="$1"
	local name="$2"
	local skip
	for skip in ${SKIPS[@]+"${SKIPS[@]}"}; do
		if [[ "$skip" == "$name" || "$skip" == "$root" ]]; then
			return 0
		fi
	done
	return 1
}

# The Version: header of the plugin's main file.
plugin_version() {
	local file="$1"
	awk '{
		line = $0
		sub(/^[ \t*]*/, "", line)
		if (tolower(substr(line, 1, 8)) == "version:") {
			v = substr(line, 9)
			gsub(/^[ \t]+|[ \t\r]+$/, "", v)
			print v
			exit
		}
	}' "$file" 2>/dev/null
	return 0
}

wp_bare() {
	local root="$1"
	shift
	"$WP_CLI" --path="$root" --skip-plugins --skip-themes "$@" 2>/dev/null | tail -n 1
	return 0
}

# The first lines the docroot's error_log and wp-content/debug.log gained
# since they had BEFORE_ERROR and BEFORE_DEBUG lines.
new_log_text() {
	local root="$1"
	local before_error="$2"
	local before_debug="$3"
	if [[ -f "$root/error_log" ]]; then
		tail -n +"$((before_error + 1))" "$root/error_log" | head -n 10
	fi
	if [[ -f "$root/wp-content/debug.log" ]]; then
		tail -n +"$((before_debug + 1))" "$root/wp-content/debug.log" | head -n 10
	fi
	return 0
}

file_lines() {
	local file="$1"
	if [[ -f "$file" ]]; then
		wc -l <"$file" | tr -d ' '
	else
		printf '0'
	fi
	return 0
}

# Every WordPress folder matching PARENT that has the plugin, one per line.
installs() {
	local parent="$1"
	local matches root
	if [[ "$parent" == \~/* ]]; then
		parent="$HOME/${parent#\~/}"
	fi
	matches="$(compgen -G "$parent" | LC_ALL=C sort || true)"
	while IFS= read -r root; do
		[[ -n "$root" ]] || continue
		root="${root%/}"
		if [[ -f "$root/wp-config.php" && -f "$root/wp-content/plugins/$SLUG/$SLUG.php" ]]; then
			printf '%s\n' "$root"
		fi
	done <<<"$matches"
	return 0
}

list_one() {
	local root="$1"
	local name="$2"
	local version kind
	version="$(plugin_version "$root/wp-content/plugins/$SLUG/$SLUG.php")"
	kind="$(wp_bare "$root" eval 'echo is_multisite() ? "multisite" : "single";')"
	printf '%s\t%s\t%s\t%s\n' "$name" "${version:-?}" "${kind:-unknown}" "$root"
	return 0
}

apply_one() {
	local root="$1"
	local name="$2"
	local want="$3"
	local zip="$4"
	local backups="$5"
	local plugins="$root/wp-content/plugins"
	local main="$plugins/$SLUG/$SLUG.php"
	local before after status home code backup err_before debug_before new_lines result="ok"

	before="$(plugin_version "$main")"
	backup="$backups/$SLUG-$name-${before:-unknown}.tar.gz"
	if ! tar -czf "$backup" -C "$plugins" "$SLUG"; then
		printf '%s\tFAIL: could not back up %s; not installed\n' "$name" "$plugins/$SLUG"
		FAILED=1
		return 0
	fi
	chmod 600 "$backup"
	err_before="$(file_lines "$root/error_log")"
	debug_before="$(file_lines "$root/wp-content/debug.log")"

	# Activation (and network activation) is kept by install --force.
	"$WP_CLI" --path="$root" --skip-plugins --skip-themes plugin install "$zip" --force >/dev/null 2>&1
	# One full load, so the plugin's settings upgrade runs (main site).
	"$WP_CLI" --path="$root" eval 'echo "loaded";' >/dev/null 2>&1

	after="$(plugin_version "$main")"
	status="$(wp_bare "$root" plugin list --name="$SLUG" --field=status)"
	home="$(wp_bare "$root" option get home)"
	code="000"
	if [[ -n "$home" ]]; then
		code="$(curl -s -o /dev/null -L -w '%{http_code}' --max-time 30 "$home/" || true)"
	fi
	new_lines=$(($(file_lines "$root/error_log") - err_before + $(file_lines "$root/wp-content/debug.log") - debug_before))

	# A home page that fails (5xx, such as WordPress's critical error page)
	# or does not answer fails the install; 4xx can be a firewall's answer
	# to the host itself, so it is only reported.
	if [[ "$after" != "$want" || "$new_lines" -gt 0 || "$code" == 5* || "$code" == "000" ]]; then
		result="FAIL"
		FAILED=1
	fi
	printf '%s\t%s -> %s\tstatus=%s\thome=%s\tnew_log_lines=%s\t%s\n' \
		"$name" "${before:-?}" "${after:-?}" "${status:-?}" "${code:-000}" "$new_lines" "$result"
	if [[ "$new_lines" -gt 0 ]]; then
		new_log_text "$root" "$err_before" "$debug_before" | sed 's/^/    /'
	fi
	if [[ "$result" == "FAIL" ]]; then
		printf '    restore: rm -rf %q && tar -xzf %q -C %q\n' "$plugins/$SLUG" "$backup" "$plugins"
	fi
	return 0
}

sha256_of() {
	local file="$1"
	if command -v sha256sum >/dev/null 2>&1; then
		sha256sum "$file" | awk '{print $1}'
	elif command -v shasum >/dev/null 2>&1; then
		shasum -a 256 "$file" | awk '{print $1}'
	else
		return 1
	fi
	return 0
}

main() {
	local mode="${1:-}"
	SLUG="${2:-}"
	local parent="${3:-}"
	local want="" zip="" sha="" backups="" found root name count=0 apply=0
	case "$mode" in
	apply)
		apply=1
		want="${4:-}"
		zip="${5:-}"
		sha="${6:-}"
		backups="${7:-}"
		shift 7 || {
			say "deploy-remote: apply needs SLUG PARENT VERSION ZIP SHA256 BACKUPS"
			return 2
		}
		;;
	list)
		shift 3 || {
			say "deploy-remote: list needs SLUG PARENT"
			return 2
		}
		;;
	*)
		say "deploy-remote: the first argument is list or apply"
		return 2
		;;
	esac
	SKIPS=("$@")
	if [[ ! "$SLUG" =~ ^[a-z0-9-]+$ ]]; then
		say "deploy-remote: not a plugin slug: $SLUG"
		return 2
	fi
	if ! command -v "$WP_CLI" >/dev/null 2>&1; then
		say "deploy-remote: no WP-CLI ($WP_CLI) on this host's PATH; set DEPLOY_WP_CLI"
		return 2
	fi

	if [[ "$apply" -eq 1 ]]; then
		if [[ "$(sha256_of "$zip" || true)" != "$sha" ]]; then
			say "deploy-remote: the zip's SHA-256 on this host is not $sha; nothing installed"
			return 2
		fi
		say "zip SHA-256 on the host: ok"
		if ! mkdir -p "$backups" || ! chmod 700 "$backups"; then
			say "deploy-remote: cannot make the backup folder $backups"
			return 2
		fi
	fi

	found="$(installs "$parent")"
	while IFS= read -r root; do
		[[ -n "$root" ]] || continue
		name="$(install_name "$root")"
		if skipped "$root" "$name"; then
			printf '%s\tskipped (--skip)\n' "$name"
			continue
		fi
		count=$((count + 1))
		if [[ "$apply" -eq 1 ]]; then
			apply_one "$root" "$name" "$want" "$zip" "$backups"
		else
			list_one "$root" "$name"
		fi
	done <<<"$found"

	if [[ "$count" -eq 0 ]]; then
		say "No install of $SLUG under $parent."
		return "$apply"
	fi
	if [[ "$apply" -eq 1 ]]; then
		say "Backups: $backups"
		[[ "$FAILED" -eq 0 ]] || return 1
	fi
	return 0
}

main "$@"
