#!/usr/bin/env bash
# Shared disposable WordPress setup. Callers supply NAME, TMP_DIR, versions,
# DB_IMAGE, MULTISITE, wp_cli, start_network and die. Optional DOCKER_LABEL
# labels every resource; the caller owns persistence and cleanup.
# STARTED and CURL_ARGS are consumed by the callers, not this library.
# shellcheck disable=SC2034
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Marcus Quinn
# Additional terms (GPL-3.0 section 7(b)): ATTRIBUTION.txt
# Provenance: wpas-e4502af0f07e8a92. Copies, even of part, keep these lines.

random_password() {
	# No early-closing pipeline (SIGPIPE under pipefail).
	od -An -N24 -tx1 /dev/urandom | tr -d ' \n' || return 1
	return 0
}

write_htaccess() {
	printf '%s\n' "$@" | docker exec -i -u www-data "$NAME-web" sh -c 'cat >/var/www/html/.htaccess' || return 1
	return 0
}

docker_prepare_core() {
	local labels=()
	[[ -z "${DOCKER_LABEL:-}" ]] || labels=(--label "$DOCKER_LABEL")
	docker run --rm ${labels[@]+"${labels[@]}"} -v "$NAME-wp:/var/www/html" --user 0:0 "wordpress:cli-php$PHP_VERSION" chown 33:33 /var/www/html
	local waited=0
	until docker exec "$NAME-db" mariadb-admin ping -h127.0.0.1 -uroot -p"$DB_PASSWORD" --silent >/dev/null 2>&1; do
		[[ "$waited" -lt 90 ]] || die "the database did not start"
		sleep 2
		waited=$((waited + 2))
	done
	wp_cli core download --version="$WP_VERSION" --quiet
	return 0
}

docker_debug_config() {
	wp_cli config set WP_DEBUG true --raw --quiet
	wp_cli config set WP_DEBUG_LOG true --raw --quiet
	wp_cli config set WP_DEBUG_DISPLAY false --raw --quiet
	wp_cli config set DISABLE_WP_CRON true --raw --quiet
	return 0
}

docker_network_rewrites() {
	local ref='$'
	write_htaccess '# BEGIN WordPress Multisite' 'RewriteEngine On' 'RewriteBase /' \
		'RewriteRule ^index\.php$ - [L]' "RewriteRule ^([_0-9a-zA-Z-]+/)?wp-admin$ ${ref}1wp-admin/ [R=301,L]" \
		'RewriteCond %{REQUEST_FILENAME} -f [OR]' 'RewriteCond %{REQUEST_FILENAME} -d' 'RewriteRule ^ - [L]' \
		"RewriteRule ^([_0-9a-zA-Z-]+/)?(wp-(content|admin|includes).*) ${ref}2 [L]" \
		"RewriteRule ^([_0-9a-zA-Z-]+/)?(.*\.php)$ ${ref}2 [L]" 'RewriteRule . index.php [L]' '# END WordPress Multisite'
	return 0
}

docker_start_site() {
	printf 'Starting a disposable WordPress %s on PHP %s (%s)...\n' "$WP_VERSION" "$PHP_VERSION" "$NAME"
	STARTED=1
	DB_PASSWORD="$(random_password)"
	ADMIN_PASSWORD="$(random_password)"
	local labels=()
	[[ -z "${DOCKER_LABEL:-}" ]] || labels=(--label "$DOCKER_LABEL")
	docker network create ${labels[@]+"${labels[@]}"} "$NAME" >/dev/null
	docker volume create ${labels[@]+"${labels[@]}"} "$NAME-wp" >/dev/null
	docker volume create ${labels[@]+"${labels[@]}"} "$NAME-db" >/dev/null
	docker run -d ${labels[@]+"${labels[@]}"} --name "$NAME-db" --network "$NAME" \
		-v "$NAME-db:/var/lib/mysql" \
		-e MARIADB_ROOT_PASSWORD="$DB_PASSWORD" -e MARIADB_DATABASE=wordpress "$DB_IMAGE" >/dev/null
	docker_prepare_core
	docker run -d ${labels[@]+"${labels[@]}"} --name "$NAME-web" --network "$NAME" -v "$NAME-wp:/var/www/html" \
		-p 127.0.0.1::80 "wordpress:php$PHP_VERSION-apache" >/dev/null
	local published
	published="$(docker port "$NAME-web" 80)"
	BASE_URL="http://$published"
	if [[ "$MULTISITE" -eq 1 ]]; then
		BASE_URL="http://127.0.0.1"
		CURL_ARGS=(--connect-to "127.0.0.1:80:$published")
	fi
	wp_cli config create --dbname=wordpress --dbuser=root --dbpass="$DB_PASSWORD" --dbhost="$NAME-db" --skip-check --quiet
	docker_debug_config
	if [[ "$MULTISITE" -eq 1 ]]; then
		start_network
	else
		wp_cli core install --title=TestSite --admin_user=admin --admin_password="$ADMIN_PASSWORD" --admin_email=admin@example.com --skip-email --quiet --url="$BASE_URL"
		wp_cli rewrite structure '/%postname%/' --quiet
		write_htaccess "# BEGIN WordPress" "RewriteEngine On" "RewriteBase /" \
			"RewriteRule ^index\.php$ - [L]" "RewriteCond %{REQUEST_FILENAME} !-f" "RewriteCond %{REQUEST_FILENAME} !-d" \
			"RewriteRule . /index.php [L]" "# END WordPress"
	fi
	printf 'WordPress %s at %s\n' "$(wp_cli core version)" "$BASE_URL"
	return 0
}
