#!/usr/bin/env bash
# Run Plugin Check (the WordPress.org review tool) on the release zips, in a
# disposable WordPress in Docker. Nothing is kept: the containers, volume and
# network are removed when it ends, and no other site is touched.
#
# Usage: scripts/plugin-check.sh [--ref REF] [--zip FILE]... [--keep-output DIR]
#   --ref REF          Build both zips from REF (default: HEAD) and check them.
#   --zip FILE         Check this zip instead (repeatable); it must hold one
#                      {slug}/ folder.
#   --keep-output DIR  Save each full report as JSON in DIR.
#
# Exit status: 0 when no zip has Plugin Check errors. Warnings are listed;
# review them before a WordPress.org submission. Updater findings in the
# GitHub zip's updater files (.distignore-wporg) and its main file's Update
# URI header are expected and not counted.
# Needs Docker and internet access (WordPress and Plugin Check are downloaded).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
# shellcheck source=scripts/lib/plugin.sh disable=SC1091 # followed only with -x
. "$SCRIPT_DIR/lib/plugin.sh"
# Set in main() from the plugin's main file.
SLUG=""
MAIN_FILE=""
UPDATER_FILES=""
CLI_IMAGE=""
DB_IMAGE=""
readonly DB_PASSWORD="plugincheck"

NAME=""
TMP_DIR=""
STARTED=0

die() {
	local message="$1"
	printf 'plugin-check: %s\n' "$message" >&2
	exit 2
}

usage() {
	sed -n '2,16p' "$0" | sed 's/^# \{0,1\}//'
	return 0
}

cleanup() {
	if [[ "$STARTED" -eq 1 ]]; then
		local attempt id
		# wp-cli containers still stopping (after Ctrl-C) keep the volume and
		# network in use, so remove them first and retry.
		for attempt in 1 2 3; do
			docker ps -aq --filter "volume=$NAME-wp" | while IFS= read -r id; do
				docker rm -f "$id" >/dev/null 2>&1 || true
			done
			docker rm -f "$NAME-db" >/dev/null 2>&1 || true
			docker volume rm "$NAME-wp" >/dev/null 2>&1 || true
			docker network rm "$NAME" >/dev/null 2>&1 || true
			if ! docker volume inspect "$NAME-wp" >/dev/null 2>&1 && ! docker network inspect "$NAME" >/dev/null 2>&1; then
				break
			fi
			[[ "$attempt" -eq 3 ]] && printf 'plugin-check: could not remove %s-wp or network %s\n' "$NAME" "$NAME" >&2
			sleep 2
		done
	fi
	if [[ -n "$TMP_DIR" ]] && [[ -d "$TMP_DIR" ]]; then
		rm -rf "$TMP_DIR"
	fi
	return 0
}

# wp-cli in the disposable site; zips are mounted at /zips. The image's
# 128 MB PHP memory limit is too small to unpack WordPress.
wp_cli() {
	docker run --rm --network "$NAME" -v "$NAME-wp:/var/www/html" -v "$TMP_DIR/zips:/zips:ro" \
		--user 33:33 "$CLI_IMAGE" php -d memory_limit=1G /usr/local/bin/wp "$@"
	return $?
}

start_site() {
	printf 'Starting a disposable WordPress (%s)...\n' "$NAME"
	STARTED=1
	docker network create "$NAME" >/dev/null
	docker volume create "$NAME-wp" >/dev/null
	docker run -d --name "$NAME-db" --network "$NAME" \
		-e MARIADB_ROOT_PASSWORD="$DB_PASSWORD" -e MARIADB_DATABASE=wordpress "$DB_IMAGE" >/dev/null
	# The volume starts owned by root; let www-data (33) write to it.
	docker run --rm -v "$NAME-wp:/var/www/html" --user 0:0 "$CLI_IMAGE" chown 33:33 /var/www/html

	# Ping over TCP: the image's first, socket-only server answers on the
	# socket before the real server is listening.
	local waited=0
	until docker exec "$NAME-db" mariadb-admin ping -h127.0.0.1 -uroot -p"$DB_PASSWORD" --silent >/dev/null 2>&1; do
		[[ "$waited" -lt 90 ]] || die "the database did not start"
		sleep 2
		waited=$((waited + 2))
	done

	wp_cli core download --quiet
	wp_cli config create --dbname=wordpress --dbuser=root --dbpass="$DB_PASSWORD" --dbhost="$NAME-db" --skip-check --quiet
	wp_cli core install --url=http://localhost --title=PluginCheck --admin_user=admin --admin_password="$DB_PASSWORD" \
		--admin_email=admin@example.com --skip-email --quiet
	wp_cli plugin install plugin-check --activate --quiet
	printf 'WordPress %s, Plugin Check %s\n' "$(wp_cli core version)" "$(wp_cli plugin get plugin-check --field=version)"
	return 0
}

# Check one zip; returns 1 when Plugin Check reports errors.
check_zip() {
	local zip_name="$1"
	local keep="$2"
	local report errors warnings code=0
	printf '\n== %s ==\n' "$zip_name"
	if ! wp_cli plugin install "/zips/$zip_name" --force --quiet; then
		printf 'Could not install %s.\n' "$zip_name"
		return 1
	fi
	# Plugin Check exits non-zero when it reports errors, so the exit code is
	# read with the findings below, not on its own.
	report="$(wp_cli plugin check "$SLUG" --format=json 2>&1)" || code=$?
	if [[ -n "$keep" ]]; then
		printf '%s\n' "$report" >"$keep/${zip_name%.zip}-plugin-check.json"
	fi
	if ! grep -Eq '^(FILE: |Success: )' <<<"$report"; then
		# Neither findings nor the success line: Plugin Check did not run.
		printf 'Plugin Check did not run:\n%s\n' "$report"
		wp_cli plugin delete "$SLUG" --quiet || true
		return 1
	fi
	errors="$( (printf '%s\n' "$report" | grep -o '"type":"ERROR"' || true) | wc -l | tr -d ' ')"
	warnings="$( (printf '%s\n' "$report" | grep -o '"type":"WARNING"' || true) | wc -l | tr -d ' ')"
	if [[ "$code" -ne 0 ]] && [[ "$errors" -eq 0 ]]; then
		# A failure with no errors found: it stopped part way.
		printf 'Plugin Check failed (exit %s) without reporting errors:\n%s\n' "$code" "$report"
		wp_cli plugin delete "$SLUG" --quiet || true
		return 1
	fi
	# The GitHub zip carries Updates from GitHub on purpose; Plugin Check
	# reports it as an updater. Those findings are expected there (and only
	# in those files); in the WordPress.org zip they stay errors. So are
	# prefix warnings there: the shared updater's names (wpallstars_) are the
	# same in every plugin, so that one copy can stand in for the others.
	local expected=0
	local expected_warnings=0
	local counts
	case "$zip_name" in
	"$SLUG"-*)
		# The file list goes through the environment: awk -v cannot hold newlines.
		# The main file's Update URI header (added to this zip only) is an
		# expected plugin_updater_detected too.
		counts="$(printf '%s\n' "$report" | FILES="$UPDATER_FILES" MAIN="$MAIN_FILE" awk '
			BEGIN { nfiles = split(ENVIRON["FILES"], list, "\n") }
			# A listed file, or a file inside a listed folder.
			function updater(path,   i) {
				for (i = 1; i <= nfiles; i++) {
					if (list[i] != "" && (path == list[i] || index(path, list[i] "/") == 1)) { return 1 }
				}
				return 0
			}
			/^FILE: / { current = substr($0, 7); next }
			/^\[/ && (current == ENVIRON["MAIN"] || updater(current)) {
				main = (current == ENVIRON["MAIN"])
				n = split($0, items, "},{")
				for (i = 1; i <= n; i++) {
					if (items[i] ~ /"type":"ERROR"/ && items[i] ~ /"code":"(plugin_updater_detected|update_modification_detected|PluginCheck\.CodeAnalysis\.Offloading\.OffloadedContent)"/ && (!main || items[i] ~ /plugin_updater_detected/)) { count++ }
					if (!main && items[i] ~ /"type":"WARNING"/ && items[i] ~ /"code":"WordPress\.NamingConventions\.PrefixAllGlobals\./) { prefix++ }
				}
			}
			END { print count + 0, prefix + 0 }')"
		expected="${counts% *}"
		expected_warnings="${counts#* }"
		;;
	*) ;; # The WordPress.org zip: every finding counts.
	esac
	if [[ "$expected" -gt 0 ]] || [[ "$expected_warnings" -gt 0 ]]; then
		printf '%s updater error(s) and %s prefix warning(s) in %s are expected in the GitHub zip.\n' "$expected" "$expected_warnings" "$MAIN_FILE (Update URI) $(printf '%s' "$UPDATER_FILES" | tr '\n' ' ')"
		errors=$((errors - expected))
		warnings=$((warnings - expected_warnings))
	fi
	# Readable summary: one line per finding (type, code, file:line).
	printf '%s\n' "$report" | awk '
		/^FILE: / { file = substr($0, 7); next }
		/^\[/ {
			n = split($0, items, "},{")
			for (i = 1; i <= n; i++) {
				t = items[i]; c = items[i]; l = items[i]
				sub(/.*"type":"/, "", t); sub(/".*/, "", t)
				sub(/.*"code":"/, "", c); sub(/".*/, "", c)
				sub(/.*"line":/, "", l); sub(/[^0-9].*/, "", l)
				printf "  %-7s %s  %s:%s\n", t, c, file, l
			}
		}'
	printf '%s error(s), %s warning(s)\n' "$errors" "$warnings"
	wp_cli plugin delete "$SLUG" --quiet || true
	[[ "$errors" -eq 0 ]] || return 1
	return 0
}

main() {
	local ref="HEAD"
	local keep=""
	local zips=""
	local arg value
	while [[ $# -gt 0 ]]; do
		arg="$1"
		value="${2:-}"
		case "$arg" in
		--ref)
			[[ $# -ge 2 ]] || die "--ref needs a value"
			ref="$value"
			shift
			;;
		--zip)
			[[ $# -ge 2 ]] || die "--zip needs a file"
			[[ -f "$value" ]] || die "no such zip: $value"
			zips="$zips
$(cd "$(dirname "$value")" && pwd)/$(basename "$value")"
			shift
			;;
		--keep-output)
			[[ $# -ge 2 ]] || die "--keep-output needs a folder"
			mkdir -p "$value"
			keep="$(cd "$value" && pwd)"
			shift
			;;
		-h | --help)
			usage
			return 0
			;;
		*) die "unknown argument: $arg" ;;
		esac
		shift
	done

	command -v docker >/dev/null 2>&1 || die "needs Docker"
	docker info >/dev/null 2>&1 || die "Docker is not running"
	local root
	root="$(git rev-parse --show-toplevel)" || die "run this inside a checkout of the plugin"
	cd "$root"
	plugin_identity "$ref" || die "cannot tell which plugin this is at $ref"
	SLUG="$PLUGIN_SLUG"
	MAIN_FILE="$PLUGIN_MAIN_FILE"
	UPDATER_FILES="$(plugin_wporg_only "$ref")"
	CLI_IMAGE="$(plugin_env CLI_IMAGE wordpress:cli-php8.3)"
	DB_IMAGE="$(plugin_env DB_IMAGE mariadb:10.6)"
	NAME="$SLUG-plugincheck-$$"

	trap cleanup EXIT
	TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/$SLUG-plugincheck.XXXXXX")"
	mkdir -p "$TMP_DIR/zips"
	chmod 755 "$TMP_DIR" "$TMP_DIR/zips"

	local zip_path
	if [[ -z "$zips" ]]; then
		"$root/scripts/build-release.sh" --ref "$ref" --out "$TMP_DIR/zips" --quiet >/dev/null || die "build failed"
	else
		while IFS= read -r zip_path; do
			[[ -n "$zip_path" ]] && cp "$zip_path" "$TMP_DIR/zips/"
		done <<EOF
$zips
EOF
	fi
	chmod 644 "$TMP_DIR"/zips/*.zip

	start_site
	local failed=0 zip_name
	for zip_path in "$TMP_DIR"/zips/*.zip; do
		zip_name="$(basename "$zip_path")"
		check_zip "$zip_name" "$keep" || failed=1
	done

	printf '\n'
	if [[ "$failed" -eq 1 ]]; then
		printf 'Plugin Check found errors.\n'
		return 1
	fi
	printf 'Plugin Check: no errors.\n'
	return 0
}

main "$@"
