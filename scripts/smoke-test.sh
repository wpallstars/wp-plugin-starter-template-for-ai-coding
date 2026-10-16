#!/usr/bin/env bash
# Smoke test: install the release zip on a disposable WordPress in Docker,
# seeded with many posts and meta rows, and load the site and admin screens,
# first with the default settings and then with every feature switched on.
# Then uninstall it and check it left nothing behind. Nothing is kept and no
# other site is touched.
#
# Usage: scripts/smoke-test.sh [--wp VERSION] [--php VERSION] [--ref REF]
#                              [--zip FILE] [--wporg] [--keep-log FILE]
#                              [--posts N] [--multisite]
#   --wp VERSION     WordPress version (default: latest). The minimum is 6.2.
#   --php VERSION    PHP version of the Docker images (default: 8.3). The
#                    minimum is 7.4.
#   --ref REF        Build the zip from REF (default: HEAD).
#   --zip FILE       Test this zip instead of building one.
#   --wporg          Test the WordPress.org build instead of the GitHub one.
#   --keep-log FILE  Save the site's debug.log to FILE.
#   --posts N        Seed N posts, with 3 meta rows each (default: 10000).
#   --multisite      A network (subdirectories) with a second site, /two/,
#                    and the plugin network-activated: also loads the network
#                    screens and site two's, applies a setting to every site
#                    from the network, checks site two does its saving work
#                    on its next admin request, and checks uninstall cleans
#                    every site and the network.
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
# Provenance: wpas-e4502af0f07e8a92. Copies, even of part, keep these lines.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
# shellcheck source=scripts/lib/plugin.sh disable=SC1091 # followed only with -x
. "$SCRIPT_DIR/lib/plugin.sh"
# shellcheck source=scripts/lib/docker-wordpress.sh disable=SC1091
. "$SCRIPT_DIR/lib/docker-wordpress.sh"

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
MULTISITE=0
# Multisite: WordPress does not run a network on a port other than 80, so
# the network's address is http://localhost and curl reaches the published
# port with these arguments (start_site).
CURL_ARGS=()
# Multisite: site two's path and every site's address, for WP-CLI's --url.
readonly SITE_TWO="/two"
SITE_URLS=()
# Where the main site's posts and archives start: /blog on a network with
# subdirectories, where WordPress keeps them apart from the sites' paths.
POST_BASE=""
# A scan or sort over this many rows or more in the plugin's own queries fails.
readonly SCAN_ROWS=1000

die() {
	local message="$1"
	printf 'smoke-test: %s\n' "$message" >&2
	exit 2
}

usage() {
	sed -n '2,33p' "$0" | sed 's/^# \{0,1\}//'
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

# wp-cli in the disposable site; the zip is mounted at /zips.
wp_cli() {
	docker run --rm --network "$NAME" -v "$NAME-wp:/var/www/html" -v "$TMP_DIR/zips:/zips:ro" \
		--user 33:33 "wordpress:cli-php$PHP_VERSION" php -d memory_limit=1G /usr/local/bin/wp "$@"
	return $?
}

# Match docker run's default: keep cached images, retry only missing pulls.
pull_image() {
	local image="$1"
	local attempt
	if docker image inspect "$image" >/dev/null 2>&1; then
		return 0
	fi
	for attempt in 1 2 3; do
		if docker pull "$image"; then
			return 0
		fi
		if [[ "$attempt" -lt 3 ]]; then
			printf 'Pull failed for %s (attempt %s/3); retrying in 20 seconds.\n' "$image" "$attempt" >&2
			sleep 20
		fi
	done
	return 1
}

start_site() {
	printf 'Starting a disposable WordPress %s on PHP %s (%s)...\n' "$WP_VERSION" "$PHP_VERSION" "$NAME"
	pull_image "$DB_IMAGE" || die "could not pull $DB_IMAGE after 3 attempts"
	pull_image "wordpress:cli-php$PHP_VERSION" || die "could not pull the WP-CLI image after 3 attempts"
	pull_image "wordpress:php$PHP_VERSION-apache" || die "could not pull the Apache image after 3 attempts"
	STARTED=1
	DB_PASSWORD="$(random_password)"
	ADMIN_PASSWORD="$(random_password)"
	docker network create "$NAME" >/dev/null
	docker volume create "$NAME-wp" >/dev/null
	docker run -d --name "$NAME-db" --network "$NAME" \
		-e MARIADB_ROOT_PASSWORD="$DB_PASSWORD" -e MARIADB_DATABASE=wordpress "$DB_IMAGE" >/dev/null
	docker_prepare_core
	docker run -d --name "$NAME-web" --network "$NAME" -v "$NAME-wp:/var/www/html" \
		-p 127.0.0.1::80 "wordpress:php$PHP_VERSION-apache" >/dev/null
	# Plain HTTP on purpose: a throwaway site that only listens on 127.0.0.1.
	local published
	published="$(docker port "$NAME-web" 80 | head -n 1)"
	BASE_URL="http://$published"
	if [[ "$MULTISITE" -eq 1 ]]; then
		BASE_URL="http://localhost"
		CURL_ARGS=(--connect-to "localhost:80:$published")
	fi

	wp_cli config create --dbname=wordpress --dbuser=root --dbpass="$DB_PASSWORD" --dbhost="$NAME-db" --skip-check --quiet
	docker_debug_config
	if [[ "$MULTISITE" -eq 1 ]]; then
		start_network
	else
		wp_cli core install --title=SmokeTest --admin_user=admin --admin_password="$ADMIN_PASSWORD" --admin_email=admin@example.com --skip-email --quiet --url="$BASE_URL" # NOSONAR: local-only HTTP, see BASE_URL
		# WP-CLI cannot see Apache's mod_rewrite, so write core's rules itself.
		wp_cli rewrite structure '/%postname%/' --quiet
		write_htaccess "# BEGIN WordPress" "RewriteEngine On" "RewriteBase /" \
			"RewriteRule ^index\.php$ - [L]" "RewriteCond %{REQUEST_FILENAME} !-f" "RewriteCond %{REQUEST_FILENAME} !-d" \
			"RewriteRule . /index.php [L]" "# END WordPress"
	fi
	printf 'WordPress %s at %s\n' "$(wp_cli core version)" "$BASE_URL" # NOSONAR: local-only HTTP, see BASE_URL
	return 0
}

# A network with subdirectories, its main site and site two, with core's
# rewrite rules for it, and a setting the network check can always use
# (add_network_setting).
start_network() {
	local url
	wp_cli core multisite-install --title=SmokeTest --admin_user=admin --admin_password="$ADMIN_PASSWORD" --admin_email=admin@example.com --skip-email --quiet --url="$BASE_URL" # NOSONAR: local-only HTTP, see BASE_URL
	wp_cli site create --slug="${SITE_TWO#/}" --title="SmokeTest Two" --email=admin@example.com --quiet
	SITE_URLS=("$BASE_URL/" "$BASE_URL$SITE_TWO/")
	for url in "${SITE_URLS[@]}"; do
		wp_cli rewrite structure '/%postname%/' --url="$url" --quiet
	done
	# The main site's structure, as WordPress saved it: /blog/%postname%/.
	POST_BASE="$(wp_cli option get permalink_structure --url="$BASE_URL/")" || die "could not read the main site's permalinks"
	POST_BASE="${POST_BASE%/%postname%/}"
	docker_network_rewrites
	add_network_setting || die "could not add the network check's setting"
	return 0
}

# A must-use plugin adding a bool setting, smoke_network, so the network
# check has one to apply even in a plugin without settings (the starter).
# Its tab does not exist, so no screen shows it.
add_network_setting() {
	local php="<?php add_filter('${PLUGIN_PREFIX}_settings_schema', function (\$schema) { \$schema['smoke_network'] = array('type' => 'bool', 'default' => false, 'label' => 'Smoke test network setting', 'description' => '', 'tab' => 'smoke-test'); return \$schema; });"
	printf '%s\n' "$php" | docker exec -i -u www-data "$NAME-web" sh -c 'mkdir -p /var/www/html/wp-content/mu-plugins && cat >/var/www/html/wp-content/mu-plugins/smoke-network.php'
	return $?
}

log_in() {
	curl -sS -o /dev/null ${CURL_ARGS[@]+"${CURL_ARGS[@]}"} -c "$TMP_DIR/cookies" -b 'wordpress_test_cookie=WP%20Cookie%20check' \
		--data-urlencode 'log=admin' --data-urlencode "pwd=$ADMIN_PASSWORD" \
		--data-urlencode 'testcookie=1' --data-urlencode "redirect_to=$BASE_URL/wp-admin/" \
		"$BASE_URL/wp-login.php"
	local status
	status="$(curl -sS -o /dev/null ${CURL_ARGS[@]+"${CURL_ARGS[@]}"} -w '%{http_code}' -b "$TMP_DIR/cookies" "$BASE_URL/wp-admin/")"
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
	local args=(-sS -o "$TMP_DIR/page" -w '%{http_code}' --max-time 60 ${CURL_ARGS[@]+"${CURL_ARGS[@]}"})
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
		'/' "$POST_BASE/hello-world/" '/sample-page/' '/?s=hello' "$POST_BASE/category/uncategorized/" '/feed/'
		'/wp-json/' '/wp-json/wp/v2/posts' '/wp-sitemap.xml' '/no-such-page/' '/wp-login.php'
	)
	local admin_pages=(
		'/' "$POST_BASE/hello-world/" '/wp-admin/' '/wp-admin/plugins.php' "${PLUGIN_PAGES[@]}"
		'/wp-admin/edit.php' '/wp-admin/edit.php?post_type=page' '/wp-admin/post-new.php'
		'/wp-admin/post.php?post=1&action=edit' '/wp-admin/upload.php' '/wp-admin/edit-comments.php'
		'/wp-admin/themes.php' '/wp-admin/users.php' '/wp-admin/profile.php' '/wp-admin/tools.php'
		'/wp-admin/site-health.php' '/wp-admin/options-general.php' '/wp-admin/options-permalink.php'
	)
	if [[ "$MULTISITE" -eq 1 ]]; then
		# Site two's pages, and the network screens with the plugin's own.
		visitor_pages+=("$SITE_TWO/" "$SITE_TWO/hello-world/" "$SITE_TWO/?s=hello" "$SITE_TWO/wp-json/wp/v2/posts")
		admin_pages+=("$SITE_TWO/" "$SITE_TWO/wp-admin/" "$SITE_TWO/wp-admin/plugins.php")
		for path in "${PLUGIN_PAGES[@]}"; do
			admin_pages+=("$SITE_TWO$path")
		done
		admin_pages+=('/wp-admin/network/' '/wp-admin/network/sites.php' '/wp-admin/network/plugins.php'
			'/wp-admin/network/settings.php' "/wp-admin/network/settings.php?page=$SLUG")
	fi
	for path in "${visitor_pages[@]}"; do
		fetch "$path" visitor
	done
	for path in "${admin_pages[@]}"; do
		fetch "$path" admin
	done
	if [[ "$MULTISITE" -eq 1 ]]; then
		for path in "${SITE_URLS[@]}"; do
			wp_cli cron event run --due-now --url="$path" --quiet || fail "wp cron event run --url=$path"
		done
	else
		wp_cli cron event run --due-now --quiet || fail "wp cron event run"
	fi
	return 0
}

# Multisite: the network screen's path through its classes, once. Applies
# one bool setting to every site from the network with the plugin's
# {Package}_Network_Settings::set_value() and apply(): the plugin's first
# eligible one other than maintenance mode, else smoke_network
# (add_network_setting). Then an admin request on site two must run its
# saving work ({Package}_Network_Sites::sync(): the site records the
# network's version in {prefix}_network_seen) and site two must read the
# network's value. The card stays applied, so uninstall must clean it.
check_network() {
	local result key want version seen got two="$BASE_URL$SITE_TWO/"
	printf '\nNetwork settings:\n'
	# shellcheck disable=SC2016 # PHP code: its $variables are PHP's, not the shell's.
	result="$(wp_cli eval '
		$plugin   = "'"$PLUGIN_PACKAGE"'";
		$settings = $plugin . "_Settings";
		$network  = $plugin . "_Network_Settings";
		$key      = "";
		$defaults = $settings::defaults();
		foreach ($settings::schema() as $k => $field) {
			$on_off = isset($defaults[$k]) && is_bool($defaults[$k]);
			if ("maintenance" !== $k && empty($field["parent"]) && $on_off && $network::eligible((string) $k)) {
				$key = (string) $k;
				break;
			}
		}
		if ("" === $key) {
			echo "none";
			exit(1);
		}
		$want = !$network::value($key);
		foreach (array($network::set_value($key, $want), $network::apply($key, true)) as $r) {
			if (is_wp_error($r)) {
				echo $r->get_error_message();
				exit(1);
			}
		}
		$stored = $network::stored();
		echo $key, " ", $want ? 1 : 0, " ", (int) $stored["version"];')" || {
		fail "applying a setting to every site from the network: $result"
		return 0
	}
	read -r key want version <<<"$result"
	printf '  applied %s = %s to every site (network version %s)\n' "$key" "$want" "$version"

	fetch "$SITE_TWO/wp-admin/" admin
	# Without the plugin loaded, so this WP-CLI request does not sync itself.
	# shellcheck disable=SC2016 # PHP code: its $variables are PHP's, not the shell's.
	seen="$(wp_cli eval --url="$two" --skip-plugins '$s = get_option("'"$PLUGIN_PREFIX"'_network_seen"); echo is_array($s) && isset($s["version"]) ? (int) $s["version"] : -1;')" || seen="error"
	if [[ "$seen" == "$version" ]]; then
		printf '  ok   site two did its saving work on its next admin request (seen version %s)\n' "$seen"
	else
		fail "site two did not run its saving work: ${PLUGIN_PREFIX}_network_seen version $seen, network version $version"
	fi
	got="$(wp_cli eval --url="$two" 'echo '"$PLUGIN_PACKAGE"'_Settings::get("'"$key"'") ? 1 : 0;')" || got="error"
	if [[ "$got" == "$want" ]]; then
		printf '  ok   site two reads the network value of %s (%s)\n' "$key" "$got"
	else
		fail "site two reads $key = $got, not the network's $want"
	fi
	for path in "${PLUGIN_PAGES[@]}"; do
		fetch "$SITE_TWO$path" admin
	done
	fetch "/wp-admin/network/settings.php?page=$SLUG" admin
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
	local url_args=("$@")
	local php
	# shellcheck disable=SC2016 # PHP variables, expanded by PHP.
	php='global $wpdb; foreach ($wpdb->get_col($wpdb->prepare("SHOW TABLES LIKE %s", $wpdb->esc_like($wpdb->prefix . "'"$PLUGIN_PREFIX"'_") . "%")) as $t) { echo $t, "\n"; }'
	wp_cli eval "$php" ${url_args[@]+"${url_args[@]}"}
	return $?
}

# Multisite: the network's own options ({prefix} in the meta key), one per line.
network_options() {
	local php
	# shellcheck disable=SC2016 # PHP variables, expanded by PHP.
	php='global $wpdb; foreach ($wpdb->get_col($wpdb->prepare("SELECT meta_key FROM {$wpdb->sitemeta} WHERE meta_key LIKE %s", "%" . $wpdb->esc_like("'"$PLUGIN_PREFIX"'") . "%")) as $k) { echo $k, "\n"; }'
	wp_cli eval "$php"
	return $?
}

# One site's options, cron events and tables left after uninstalling. URL
# (multisite) names the site, WHERE how failures name it.
check_site_clean() {
	local where="$1"
	shift
	local url_args=("$@")
	local left hooks
	if left="$(plugin_tables ${url_args[@]+"${url_args[@]}"})"; then
		[[ -z "$left" ]] || fail "tables left after uninstalling$where: $(printf '%s' "$left" | tr '\n' ' ')"
	else
		fail "could not list the plugin's tables after uninstalling$where"
	fi
	# A failed listing must fail the check, not read as "nothing left".
	if left="$(wp_cli option list --search="*$PLUGIN_PREFIX*" --field=option_name ${url_args[@]+"${url_args[@]}"} 2>/dev/null)"; then
		[[ -z "$left" ]] || fail "options left after uninstalling$where: $(printf '%s' "$left" | tr '\n' ' ')"
	else
		fail "could not list the options after uninstalling$where"
	fi
	if hooks="$(wp_cli cron event list --field=hook ${url_args[@]+"${url_args[@]}"} 2>/dev/null)"; then
		left="$(grep -i "$PLUGIN_PREFIX" <<<"$hooks" || true)"
		[[ -z "$left" ]] || fail "cron events left after uninstalling$where: $(printf '%s' "$left" | tr '\n' ' ')"
	else
		fail "could not list the cron events after uninstalling$where"
	fi
	return 0
}

check_uninstall() {
	local left tables url
	if tables="$(plugin_tables)"; then
		if [[ -n "$tables" ]]; then
			printf '  tables before uninstalling: %s\n' "$(printf '%s' "$tables" | tr '\n' ' ')"
		fi
	else
		fail "could not list the plugin's tables"
	fi
	if [[ "$MULTISITE" -eq 1 ]]; then
		if left="$(network_options)"; then
			printf '  network options before uninstalling: %s\n' "$(printf '%s' "${left:-none}" | tr '\n' ' ')"
		fi
		wp_cli plugin deactivate "$SLUG" --network --quiet || fail "deactivate --network"
	else
		wp_cli plugin deactivate "$SLUG" --quiet || fail "deactivate"
	fi
	wp_cli plugin uninstall "$SLUG" --quiet || fail "uninstall"
	if [[ "$MULTISITE" -eq 1 ]]; then
		for url in "${SITE_URLS[@]}"; do
			check_site_clean " on $url" --url="$url"
		done
		if left="$(network_options)"; then
			[[ -z "$left" ]] || fail "network options left after uninstalling: $(printf '%s' "$left" | tr '\n' ' ')"
		else
			fail "could not list the network options after uninstalling"
		fi
	else
		check_site_clean ""
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
	reset_queries
	return 0
}

# Forget the requests recorded so far (scripts/smoke-queries.php).
reset_queries() {
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

# Read the options into REF, ZIP, WPORG, KEEP_LOG, MULTISITE and the
# settings above.
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
		--multisite) MULTISITE=1 ;;
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
	if [[ "$MULTISITE" -eq 1 ]]; then
		wp_cli plugin install "/zips/$SLUG.zip" --activate-network --quiet || die "could not install and network-activate the plugin"
	else
		wp_cli plugin install "/zips/$SLUG.zip" --activate --quiet || die "could not install and activate the plugin"
	fi
	log_in
	find_plugin_pages || die "could not tell where the plugin's admin screens are"
	wp_cli eval 'wpallstars_smoke_reset();' || die "could not reset the query log"

	printf '\nDefault settings:\n'
	load_pages
	check_queries

	printf '\nEvery feature on:\n'
	switch_all_on || fail "switching features on"
	reset_queries
	load_pages
	check_queries

	# check_queries has reset the query log.
	if [[ "$MULTISITE" -eq 1 ]]; then
		check_network
		check_queries
	fi

	printf '\nUninstall:\n'
	check_uninstall
	check_debug_log "$keep"

	printf '\n'
	local kind=""
	[[ "$MULTISITE" -eq 1 ]] && kind=", multisite"
	if [[ "$FAILED" -eq 1 ]]; then
		printf 'Smoke test failed (WordPress %s, PHP %s%s).\n' "$WP_VERSION" "$PHP_VERSION" "$kind"
		return 1
	fi
	printf 'Smoke test passed (WordPress %s, PHP %s%s).\n' "$WP_VERSION" "$PHP_VERSION" "$kind"
	return 0
}

main "$@"
