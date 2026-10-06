#!/usr/bin/env bash
# Smoke test: install the release zip on a disposable WordPress in Docker,
# seeded with many posts and meta rows, and load the site and admin screens,
# first with the default settings and then with every feature switched on.
# Then uninstall it and check it left nothing behind. Nothing is kept and no
# other site is touched.
#
# Usage: scripts/smoke-test.sh [--wp VERSION] [--php VERSION] [--ref REF]
#                              [--zip FILE] [--wporg] [--keep-log FILE]
#                              [--posts N]
#   --wp VERSION     WordPress version (default: latest). The minimum is 6.2.
#   --php VERSION    PHP version of the Docker images (default: 8.3). The
#                    minimum is 7.4.
#   --ref REF        Build the zip from REF (default: HEAD).
#   --zip FILE       Test this zip instead of building one.
#   --wporg          Test the WordPress.org build instead of the GitHub one.
#   --keep-log FILE  Save the site's debug.log to FILE.
#   --posts N        Seed N posts, with 3 meta rows each (default: 10000).
#
# Fails on any PHP error, warning, notice or deprecation in debug.log (from
# the pages loaded, WP-CLI and cron), a page that fails to load (HTTP 500 or
# WordPress's critical error page; for admin pages, any 4xx too, so the
# plugin's own screens must open), a full table or index scan, or a sort,
# over 1000 rows or more in the plugin's own queries (EXPLAIN, see
# scripts/smoke-queries.php), or settings, cron events or database tables
# ({prefix}_*) left after uninstalling. Lists each request's query count and
# time, the plugin's own queries, and its tables before uninstalling.
# Needs Docker, curl and internet access (WordPress is downloaded).
#
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Marcus Quinn
# Additional terms (GPL-3.0 section 7(b)): ATTRIBUTION.txt

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
# shellcheck source=scripts/lib/plugin.sh disable=SC1091 # followed only with -x
. "$SCRIPT_DIR/lib/plugin.sh"

# Set in main() from the plugin's main file.
SLUG=""
DB_IMAGE=""
NAME=""
TMP_DIR=""
STARTED=0
WP_VERSION="latest"
PHP_VERSION="8.3"
BASE_URL=""
DB_PASSWORD=""
ADMIN_PASSWORD=""
FAILED=0
POSTS=10000
# The plugin's own admin screens (find_plugin_pages).
PLUGIN_PAGES=()
# Options (parse_args).
REF="HEAD"
ZIP=""
WPORG=0
KEEP_LOG=""
# A scan or sort over this many rows or more in the plugin's own queries fails.
readonly SCAN_ROWS=1000

die() {
	local message="$1"
	printf 'smoke-test: %s\n' "$message" >&2
	exit 2
}

usage() {
	sed -n '2,26p' "$0" | sed 's/^# \{0,1\}//'
	return 0
}

fail() {
	local message="$1"
	printf '  FAIL %s\n' "$message"
	FAILED=1
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
			docker rm -f "$NAME-web" "$NAME-db" >/dev/null 2>&1 || true
			docker volume rm "$NAME-wp" >/dev/null 2>&1 || true
			docker network rm "$NAME" >/dev/null 2>&1 || true
			if ! docker volume inspect "$NAME-wp" >/dev/null 2>&1 && ! docker network inspect "$NAME" >/dev/null 2>&1; then
				break
			fi
			[[ "$attempt" -eq 3 ]] && printf 'smoke-test: could not remove %s-wp or network %s\n' "$NAME" "$NAME" >&2
			sleep 2
		done
	fi
	if [[ -n "$TMP_DIR" ]] && [[ -d "$TMP_DIR" ]]; then
		rm -rf "$TMP_DIR"
	fi
	return 0
}

random_password() {
	LC_ALL=C tr -dc 'A-Za-z0-9' </dev/urandom | head -c 24
	return 0
}

# wp-cli in the disposable site; the zip is mounted at /zips.
wp_cli() {
	docker run --rm --network "$NAME" -v "$NAME-wp:/var/www/html" -v "$TMP_DIR/zips:/zips:ro" \
		--user 33:33 "wordpress:cli-php$PHP_VERSION" php -d memory_limit=1G /usr/local/bin/wp "$@"
	return $?
}

start_site() {
	printf 'Starting a disposable WordPress %s on PHP %s (%s)...\n' "$WP_VERSION" "$PHP_VERSION" "$NAME"
	STARTED=1
	DB_PASSWORD="$(random_password)"
	ADMIN_PASSWORD="$(random_password)"
	docker network create "$NAME" >/dev/null
	docker volume create "$NAME-wp" >/dev/null
	docker run -d --name "$NAME-db" --network "$NAME" \
		-e MARIADB_ROOT_PASSWORD="$DB_PASSWORD" -e MARIADB_DATABASE=wordpress "$DB_IMAGE" >/dev/null
	docker run --rm -v "$NAME-wp:/var/www/html" --user 0:0 "wordpress:cli-php$PHP_VERSION" chown 33:33 /var/www/html

	local waited=0
	until docker exec "$NAME-db" mariadb-admin ping -h127.0.0.1 -uroot -p"$DB_PASSWORD" --silent >/dev/null 2>&1; do
		[[ "$waited" -lt 90 ]] || die "the database did not start"
		sleep 2
		waited=$((waited + 2))
	done

	# Core first, so the web image finds WordPress and does not copy its own.
	wp_cli core download --version="$WP_VERSION" --quiet
	docker run -d --name "$NAME-web" --network "$NAME" -v "$NAME-wp:/var/www/html" \
		-p 127.0.0.1::80 "wordpress:php$PHP_VERSION-apache" >/dev/null
	# Plain HTTP on purpose: a throwaway site that only listens on 127.0.0.1.
	BASE_URL="http://$(docker port "$NAME-web" 80 | head -n 1)"

	wp_cli config create --dbname=wordpress --dbuser=root --dbpass="$DB_PASSWORD" --dbhost="$NAME-db" --skip-check --quiet
	wp_cli config set WP_DEBUG true --raw --quiet
	wp_cli config set WP_DEBUG_LOG true --raw --quiet
	wp_cli config set WP_DEBUG_DISPLAY false --raw --quiet
	wp_cli config set DISABLE_WP_CRON true --raw --quiet
	wp_cli core install --title=SmokeTest --admin_user=admin --admin_password="$ADMIN_PASSWORD" --admin_email=admin@example.com --skip-email --quiet --url="$BASE_URL" # NOSONAR: local-only HTTP, see BASE_URL
	# WP-CLI cannot see Apache's mod_rewrite, so write core's rules itself.
	wp_cli rewrite structure '/%postname%/' --quiet
	docker exec -u www-data "$NAME-web" sh -c 'printf "%s\n" "# BEGIN WordPress" "RewriteEngine On" "RewriteBase /" \
		"RewriteRule ^index\.php$ - [L]" "RewriteCond %{REQUEST_FILENAME} !-f" "RewriteCond %{REQUEST_FILENAME} !-d" \
		"RewriteRule . /index.php [L]" "# END WordPress" >/var/www/html/.htaccess'
	printf 'WordPress %s at %s\n' "$(wp_cli core version)" "$BASE_URL" # NOSONAR: local-only HTTP, see BASE_URL
	return 0
}

log_in() {
	curl -sS -o /dev/null -c "$TMP_DIR/cookies" -b 'wordpress_test_cookie=WP%20Cookie%20check' \
		--data-urlencode 'log=admin' --data-urlencode "pwd=$ADMIN_PASSWORD" \
		--data-urlencode 'testcookie=1' --data-urlencode "redirect_to=$BASE_URL/wp-admin/" \
		"$BASE_URL/wp-login.php"
	local status
	status="$(curl -sS -o /dev/null -w '%{http_code}' -b "$TMP_DIR/cookies" "$BASE_URL/wp-admin/")"
	[[ "$status" = "200" ]] || die "could not log in (wp-admin answered $status)"
	return 0
}

# Load one page; $2 is "admin" to send the login cookie. Fails when the site
# does not answer, on 5xx or WordPress's critical error page; other statuses
# are listed.
fetch() {
	local path="$1"
	local who="$2"
	local status code=0
	local args=(-sS -o "$TMP_DIR/page" -w '%{http_code}' --max-time 60)
	[[ "$who" = "admin" ]] && args+=(-b "$TMP_DIR/cookies")
	rm -f "$TMP_DIR/page"
	status="$(curl "${args[@]}" "$BASE_URL$path")" || code=$?
	if [[ "$code" -ne 0 ]] || ! [[ "$status" =~ ^[1-9][0-9][0-9]$ ]]; then
		fail "${status:-000} $who $path: no answer (curl exit $code)"
	elif [[ -f "$TMP_DIR/page" ]] && grep -q 'There has been a critical error' "$TMP_DIR/page"; then
		fail "$status $who $path: critical error page"
	elif [[ "$status" -ge 500 ]]; then
		fail "$status $who $path"
	elif [[ "$who" = "admin" && "$status" -ge 400 ]]; then
		# Every admin page listed opens for an administrator.
		fail "$status $who $path"
	else
		printf '  %s %s %s\n' "$status" "$who" "$path"
	fi
	return 0
}

# Sets PLUGIN_PAGES, the plugin's own admin screens: the settings screen, and
# the plugin's top-level menu page when {Prefix}_Setup::MENU_PARENT names one
# (the settings screen is then in that menu).
find_plugin_pages() {
	local parent
	# shellcheck disable=SC2016 # PHP code: its $variables are PHP's, not the shell's.
	parent="$(wp_cli eval '$c = "'"$PLUGIN_PACKAGE"'_Setup::MENU_PARENT"; echo defined($c) ? (string) constant($c) : "";')" || return 1
	if [[ -n "$parent" ]]; then
		PLUGIN_PAGES=("/wp-admin/admin.php?page=$parent" "/wp-admin/admin.php?page=$SLUG")
	else
		PLUGIN_PAGES=("/wp-admin/options-general.php?page=$SLUG")
	fi
	return 0
}

load_pages() {
	local path
	local visitor_pages=(
		'/' '/hello-world/' '/sample-page/' '/?s=hello' '/category/uncategorized/' '/feed/'
		'/wp-json/' '/wp-json/wp/v2/posts' '/wp-sitemap.xml' '/no-such-page/' '/wp-login.php'
	)
	local admin_pages=(
		'/' '/hello-world/' '/wp-admin/' '/wp-admin/plugins.php' "${PLUGIN_PAGES[@]}"
		'/wp-admin/edit.php' '/wp-admin/edit.php?post_type=page' '/wp-admin/post-new.php'
		'/wp-admin/post.php?post=1&action=edit' '/wp-admin/upload.php' '/wp-admin/edit-comments.php'
		'/wp-admin/themes.php' '/wp-admin/users.php' '/wp-admin/profile.php' '/wp-admin/tools.php'
		'/wp-admin/site-health.php' '/wp-admin/options-general.php' '/wp-admin/options-permalink.php'
	)
	for path in "${visitor_pages[@]}"; do
		fetch "$path" visitor
	done
	for path in "${admin_pages[@]}"; do
		fetch "$path" admin
	done
	wp_cli cron event run --due-now --quiet || fail "wp cron event run"
	return 0
}

# Switch on every feature that has an on/off setting, except maintenance
# mode, which would answer every visitor page with its 503 notice.
switch_all_on() {
	# The class prefix is the plugin's @package (scripts/lib/plugin.sh).
	# shellcheck disable=SC2016 # PHP code: its $variables are PHP's, not the shell's.
	wp_cli eval '
		$plugin = "'"$PLUGIN_PACKAGE"'";
		$settings = $plugin . "_Settings";
		$schema = $settings::schema();
		$on = 0;
		foreach ($plugin::features() as $class) {
			$key = defined($class . "::KEY") ? $class::KEY : "";
			if ("" !== $key && "maintenance" !== $key && isset($schema[$key]["type"]) && in_array($schema[$key]["type"], array("bool", "boolean"), true)) {
				$settings::set($key, true);
				$on++;
			}
		}
		echo "$on features switched on\n";'
	return $?
}

# The plugin's own database tables ({$wpdb->prefix}{prefix}_*), one per line.
# PLUGIN_PREFIX is lower-case letters, digits and underscores (plugin.sh).
plugin_tables() {
	local php
	# shellcheck disable=SC2016 # PHP variables, expanded by PHP.
	php='global $wpdb; foreach ($wpdb->get_col($wpdb->prepare("SHOW TABLES LIKE %s", $wpdb->esc_like($wpdb->prefix . "'"$PLUGIN_PREFIX"'_") . "%")) as $t) { echo $t, "\n"; }'
	wp_cli eval "$php"
	return $?
}

check_uninstall() {
	local left hooks tables
	if tables="$(plugin_tables)"; then
		if [[ -n "$tables" ]]; then
			printf '  tables before uninstalling: %s\n' "$(printf '%s' "$tables" | tr '\n' ' ')"
		fi
	else
		fail "could not list the plugin's tables"
	fi
	wp_cli plugin deactivate "$SLUG" --quiet || fail "deactivate"
	wp_cli plugin uninstall "$SLUG" --quiet || fail "uninstall"
	if left="$(plugin_tables)"; then
		[[ -z "$left" ]] || fail "tables left after uninstalling: $(printf '%s' "$left" | tr '\n' ' ')"
	else
		fail "could not list the plugin's tables after uninstalling"
	fi
	# A failed listing must fail the check, not read as "nothing left".
	if left="$(wp_cli option list --search="*$PLUGIN_PREFIX*" --field=option_name 2>/dev/null)"; then
		[[ -z "$left" ]] || fail "options left after uninstalling: $(printf '%s' "$left" | tr '\n' ' ')"
	else
		fail "could not list the options after uninstalling"
	fi
	if hooks="$(wp_cli cron event list --field=hook 2>/dev/null)"; then
		left="$(grep -i "$PLUGIN_PREFIX" <<<"$hooks" || true)"
		[[ -z "$left" ]] || fail "cron events left after uninstalling: $(printf '%s' "$left" | tr '\n' ' ')"
	else
		fail "could not list the cron events after uninstalling"
	fi
	return 0
}

# A must-use plugin that logs a notice for /?smoke-canary, so the test can
# prove that page loads reach debug.log (an empty log proves nothing otherwise).
add_canary() {
	docker exec -u www-data "$NAME-web" sh -c 'mkdir -p /var/www/html/wp-content/mu-plugins && printf "%s\n" "<?php" \
		"if (isset(\$_GET[\"smoke-canary\"])) { trigger_error(\"smoke-test canary\", E_USER_NOTICE); }" \
		>/var/www/html/wp-content/mu-plugins/smoke-canary.php'
	return $?
}

# The query recorder (scripts/smoke-queries.php) as a must-use plugin, with
# SAVEQUERIES on so it gets each query's time, then the seeded posts.
add_query_checks() {
	wp_cli config set WPALLSTARS_SMOKE_PLUGIN "$SLUG" --quiet || return 1
	wp_cli config set SAVEQUERIES true --raw --quiet || return 1
	wp_cli eval 'copy( "/zips/smoke-queries.php", WPMU_PLUGIN_DIR . "/smoke-queries.php" ) || exit( 1 );' || return 1
	wp_cli eval "wpallstars_smoke_seed( $POSTS );" || return 1
	return 0
}

# List the requests since the last reset and check the plugin's own queries;
# the canary page proves the check finds a full table scan.
check_queries() {
	local report code=0
	fetch '/?smoke-query-canary' visitor
	report="$(wp_cli eval "wpallstars_smoke_report( $SCAN_ROWS );" 2>&1)" || code=$?
	printf '\n%s\n' "$report"
	if [[ "$code" -ne 0 ]]; then
		fail "the query report stopped (exit $code)"
	elif ! grep -q '^queries: ok$' <<<"$report"; then
		fail "the plugin's own queries (see above)"
	fi
	wp_cli eval 'wpallstars_smoke_reset();' || fail "resetting the query log"
	return 0
}

check_debug_log() {
	local keep="$1"
	local log
	fetch '/?smoke-canary' visitor
	log="$(docker exec "$NAME-web" sh -c 'cat /var/www/html/wp-content/debug.log 2>/dev/null' || true)"
	if [[ -n "$keep" ]]; then
		printf '%s\n' "$log" >"$keep"
	fi
	if ! grep -q 'smoke-test canary' <<<"$log"; then
		fail "debug.log does not work: the canary notice is missing"
		return 0
	fi
	log="$(printf '%s\n' "$log" | grep -v 'smoke-test canary' || true)"
	if [[ -n "$log" ]]; then
		printf '\ndebug.log:\n%s\n' "$log"
		fail "PHP messages in debug.log"
	else
		printf '\ndebug.log: no PHP messages (the canary notice arrived)\n'
	fi
	return 0
}

# Read the options into REF, ZIP, WPORG, KEEP_LOG and the settings above.
parse_args() {
	local arg value
	while [[ $# -gt 0 ]]; do
		arg="$1"
		value="${2:-}"
		case "$arg" in
		--wp | --php | --ref | --zip | --keep-log | --posts)
			[[ $# -ge 2 ]] || die "$arg needs a value"
			case "$arg" in
			--wp) WP_VERSION="$value" ;;
			--php) PHP_VERSION="$value" ;;
			--ref) REF="$value" ;;
			--posts)
				[[ "$value" =~ ^[1-9][0-9]{0,5}$ ]] || die "--posts needs a number from 1 to 999999"
				POSTS="$value"
				;;
			--zip)
				[[ -f "$value" ]] || die "no such zip: $value"
				ZIP="$(cd "$(dirname "$value")" && pwd)/$(basename "$value")"
				;;
			--keep-log)
				case "$value" in
				/*) KEEP_LOG="$value" ;;
				*) KEEP_LOG="$PWD/$value" ;;
				esac
				;;
			*) ;; # The outer pattern lists every option that takes a value.
			esac
			shift
			;;
		--wporg) WPORG=1 ;;
		-h | --help)
			usage
			exit 0
			;;
		*) die "unknown argument: $arg" ;;
		esac
		shift
	done
	return 0
}

main() {
	parse_args "$@"
	local ref="$REF"
	local zip="$ZIP"
	local wporg="$WPORG"
	local keep="$KEEP_LOG"

	command -v docker >/dev/null 2>&1 || die "needs Docker"
	command -v curl >/dev/null 2>&1 || die "needs curl"
	docker info >/dev/null 2>&1 || die "Docker is not running"
	local root
	root="$(git rev-parse --show-toplevel)" || die "run this inside a checkout of the plugin"
	cd "$root"
	plugin_identity "$ref" || die "cannot tell which plugin this is at $ref"
	SLUG="$PLUGIN_SLUG"
	DB_IMAGE="$(plugin_env DB_IMAGE mariadb:10.6)"
	NAME="$SLUG-smoke-$$"

	trap cleanup EXIT
	TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/$SLUG-smoke.XXXXXX")"
	mkdir -p "$TMP_DIR/zips"
	chmod 755 "$TMP_DIR" "$TMP_DIR/zips"
	if [[ -z "$zip" ]]; then
		"$root/scripts/build-release.sh" --ref "$ref" --out "$TMP_DIR/build" --quiet >/dev/null || die "build failed"
		local built=()
		if [[ "$wporg" -eq 1 ]]; then
			built=("$TMP_DIR"/build/wordpress-org-"$SLUG"-*.zip)
		else
			built=("$TMP_DIR"/build/"$SLUG"-*.zip)
		fi
		[[ -f "${built[0]}" ]] || die "the build made no zip"
		zip="${built[0]}"
	fi
	cp "$zip" "$TMP_DIR/zips/$SLUG.zip"
	cp "$root/scripts/smoke-queries.php" "$TMP_DIR/zips/smoke-queries.php"
	chmod 644 "$TMP_DIR/zips/$SLUG.zip" "$TMP_DIR/zips/smoke-queries.php"

	start_site
	add_canary || die "could not add the debug.log canary"
	add_query_checks || die "could not add the query checks and seed the posts"
	printf '\nInstalling %s\n' "$(basename "$zip")"
	wp_cli plugin install "/zips/$SLUG.zip" --activate --quiet || die "could not install and activate the plugin"
	log_in
	find_plugin_pages || die "could not tell where the plugin's admin screens are"
	wp_cli eval 'wpallstars_smoke_reset();' || die "could not reset the query log"

	printf '\nDefault settings:\n'
	load_pages
	check_queries

	printf '\nEvery feature on:\n'
	switch_all_on || fail "switching features on"
	wp_cli eval 'wpallstars_smoke_reset();' || fail "resetting the query log"
	load_pages
	check_queries

	printf '\nUninstall:\n'
	check_uninstall
	check_debug_log "$keep"

	printf '\n'
	if [[ "$FAILED" -eq 1 ]]; then
		printf 'Smoke test failed (WordPress %s, PHP %s).\n' "$WP_VERSION" "$PHP_VERSION"
		return 1
	fi
	printf 'Smoke test passed (WordPress %s, PHP %s).\n' "$WP_VERSION" "$PHP_VERSION"
	return 0
}

main "$@"
