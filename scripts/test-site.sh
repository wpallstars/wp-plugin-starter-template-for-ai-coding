#!/usr/bin/env bash
# Keep a disposable Docker WordPress running for one branch's release build.
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Marcus Quinn
# Additional terms (GPL-3.0 section 7(b)): ATTRIBUTION.txt
# Provenance: wpas-e4502af0f07e8a92. Copies, even of part, keep these lines.

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib/plugin.sh disable=SC1091
. "$SCRIPT_DIR/lib/plugin.sh"
# shellcheck source=scripts/lib/docker-wordpress.sh disable=SC1091
. "$SCRIPT_DIR/lib/docker-wordpress.sh"
REF=HEAD
WP_VERSION=latest
PHP_VERSION=8.3
MULTISITE=0
STARTED=0
FILES=""
BASE_URL=""
DB_PASSWORD=""
ADMIN_PASSWORD=""

die() {
	local message="$1"
	printf 'test-site: %s\n' "$message" >&2
	exit 1
}

usage() {
	printf '%s\n' 'Usage: scripts/test-site.sh COMMAND' \
		'  up [--ref REF] [--wp VERSION] [--php VERSION] [--multisite]' \
		'  reinstall [--ref REF]' '  wp [--files DIR] ARGS...' '  url | log | down' \
		'One site per plugin, branch and checkout; Docker listens on 127.0.0.1 only.'
	return 0
}

wp_cli() {
	local mounts=()
	[[ -z "$FILES" ]] || mounts=(-v "$FILES:/files:ro")
	docker run --rm --label "$DOCKER_LABEL" --network "$NAME" \
		-v "$NAME-wp:/var/www/html" -v "$TMP_DIR/zips:/zips:ro" \
		${mounts[@]+"${mounts[@]}"} --user 33:33 "wordpress:cli-php$PHP_VERSION" \
		php -d memory_limit=1G /usr/local/bin/wp "$@" || return 1
	return 0
}

start_network() {
	wp_cli core multisite-install --title=TestSite --admin_user=admin --admin_password="$ADMIN_PASSWORD" \
		--admin_email=admin@example.com --skip-email --quiet --url="$BASE_URL"
	wp_cli site create --slug=two --title='TestSite Two' --email=admin@example.com --quiet
	wp_cli rewrite structure '/%postname%/' --quiet
	wp_cli rewrite structure '/%postname%/' --url="$BASE_URL/two/" --quiet
	docker_network_rewrites
	return 0
}

resources() {
	local kind="$1"
	case "$kind" in
	container) docker ps -aq --filter "label=$DOCKER_LABEL" || return 1 ;;
	volume) docker volume ls -q --filter "label=$DOCKER_LABEL" || return 1 ;;
	network) docker network ls -q --filter "label=$DOCKER_LABEL" || return 1 ;;
	*) return 1 ;;
	esac
	return 0
}

down() {
	local kind id ids
	# Every deletion is from a successful exact-label listing. Never by name,
	# volume attachment, prune, or a broad plugin/preview label.
	for kind in container volume network; do
		ids="$(resources "$kind")" || return 1
		while IFS= read -r id; do
			[[ -n "$id" ]] || continue
			case "$kind" in
			container) docker rm -f "$id" >/dev/null || return 1 ;;
			volume) docker volume rm "$id" >/dev/null || return 1 ;;
			network) docker network rm "$id" >/dev/null || return 1 ;;
			*) return 1 ;;
			esac
		done <<<"$ids"
	done
	# Only remove our known state files, never a recursively chosen directory.
	rm -f "$TMP_DIR/site" "$TMP_DIR/credentials" "$TMP_DIR/zips/$SLUG.zip" || return 1
	printf 'Removed test site %s (label %s).\n' "$NAME" "$DOCKER_LABEL"
	return 0
}

finish() {
	local status="$?"
	if [[ "$status" -ne 0 && "$STARTED" -eq 1 ]]; then
		printf 'test-site: setup failed; removing its labelled resources\n' >&2
		down || printf 'test-site: cleanup incomplete; run down again\n' >&2
	fi
	rmdir "$TMP_DIR/lock"
	return 0
}

load_site() {
	[[ -f "$TMP_DIR/site" ]] || die 'no completed site; run up (or down to clear incomplete setup)'
	# Read data, never execute state files as shell code.
	{ IFS= read -r PHP_VERSION; IFS= read -r MULTISITE; IFS= read -r BASE_URL; } <"$TMP_DIR/site"
	[[ "$PHP_VERSION" =~ ^[0-9]+\.[0-9]+$ && "$MULTISITE" =~ ^[01]$ ]] || die 'invalid site state'
	return 0
}

reinstall() {
	local build built=()
	plugin_identity "$REF" || die "cannot read plugin at $REF"
	[[ "$PLUGIN_SLUG" = "$SLUG" ]] || die 'ref belongs to a different plugin slug'
	build="$(mktemp -d "$TMP_DIR/build.XXXXXX")"
	"$SCRIPT_DIR/build-release.sh" --ref "$REF" --out "$build" --quiet >/dev/null
	built=("$build/$SLUG"-*.zip)
	[[ -f "${built[0]}" ]] || die 'build made no zip'
	cp "${built[0]}" "$TMP_DIR/zips/$SLUG.zip"
	chmod 644 "$TMP_DIR/zips/$SLUG.zip"
	local activation=--activate
	[[ "$MULTISITE" -eq 0 ]] || activation=--activate-network
	wp_cli plugin install "/zips/$SLUG.zip" --force "$activation"
	# build is a directory created by mktemp immediately above, not state input.
	rm -rf "$build"
	return 0
}

main() {
	local command="${1:---help}"
	[[ $# -eq 0 ]] || shift
	case "$command" in -h | --help | help) usage; return 0 ;; *) ;; esac
	case "$command" in up | reinstall | wp | url | log | down) ;; *) die "unknown command: $command" ;; esac
	local arg value
	if [[ "$command" = wp ]]; then
		if [[ "${1:-}" = --files ]]; then
			value="${2:-}"
			[[ -n "$value" && -d "$value" ]] || die '--files needs an existing directory'
			FILES="$(cd "$value" && pwd)"
			shift 2
		fi
		[[ $# -gt 0 ]] || die 'wp needs WP-CLI arguments'
	else
		while [[ $# -gt 0 ]]; do
			arg="$1"; value="${2:-}"
			# WP_VERSION is consumed by docker_start_site in the sourced helper.
			# shellcheck disable=SC2034
			case "$command:$arg" in
			up:--ref | reinstall:--ref) [[ -n "$value" ]] || die "$arg needs a value"; REF="$value"; shift ;;
			up:--php) [[ "$value" =~ ^[0-9]+\.[0-9]+$ ]] || die 'invalid PHP version'; PHP_VERSION="$value"; shift ;;
			up:--wp) [[ "$value" =~ ^(latest|[0-9]+\.[0-9]+(\.[0-9]+)?)$ ]] || die 'invalid WordPress version'; WP_VERSION="$value"; shift ;;
			up:--multisite) MULTISITE=1 ;;
			*) die "unknown option for $command: $arg" ;;
			esac
			shift
		done
	fi
	local root branch identity digest state_home
	root="$(git -C "$SCRIPT_DIR/.." rev-parse --show-toplevel)"
	cd "$root"
	plugin_identity HEAD || die 'cannot identify this plugin'
	SLUG="$PLUGIN_SLUG"
	branch="$(git symbolic-ref --quiet --short HEAD)" || die 'use a named branch, not detached HEAD'
	identity="$SLUG:$branch:$root"
	digest="$(printf '%s' "$identity" | shasum -a 256)"; digest="${digest%% *}"
	NAME="${SLUG:0:32}-test-${digest:0:16}"
	DOCKER_LABEL="wpallstars.test-site=$digest"
	state_home="${XDG_STATE_HOME:-$HOME/.local/state}/wpallstars-test-sites"
	umask 077
	mkdir -p "$state_home/$NAME/zips"
	TMP_DIR="$state_home/$NAME"
	# The CLI image runs as uid 33; only non-secret zips are traversable/readable.
	chmod 755 "$TMP_DIR" "$TMP_DIR/zips"
	mkdir "$TMP_DIR/lock" 2>/dev/null || die 'another command is running (or a stale lock needs removal)'
	trap finish EXIT
	trap 'exit 130' INT
	trap 'exit 143' TERM
	command -v docker >/dev/null || die 'needs Docker'
	docker info >/dev/null 2>&1 || die 'Docker is not running'
	case "$command" in
	up)
		[[ ! -f "$TMP_DIR/site" && ! -f "$TMP_DIR/credentials" ]] || die 'site already exists; use url, reinstall or down'
		local existing="" kind listed
		for kind in network volume container; do
			listed="$(resources "$kind")" || die "could not list Docker $kind resources"
			existing+="$listed"
		done
		[[ -z "$existing" ]] || die 'site resources already exist; use down first'
		# Used by docker_start_site in the sourced helper.
		# shellcheck disable=SC2034
		DB_IMAGE="$(plugin_env DB_IMAGE mariadb:10.6)"
		docker_start_site
		if [[ "$MULTISITE" -eq 1 ]]; then
			# WP-CLI refuses a port during installation, but core can serve it
			# afterwards. Migrate domains and URLs so browsers need no proxy.
			local published
			published="$(docker port "$NAME-web" 80)"
			wp_cli search-replace '127.0.0.1' "$published" --all-tables --quiet
			wp_cli config set DOMAIN_CURRENT_SITE "$published" --quiet
			BASE_URL="http://$published" # NOSONAR: disposable HTTP bound only to 127.0.0.1.
		fi
		wp_cli config set SAVEQUERIES true --raw --quiet
		wp_cli config set DISABLE_WP_CRON false --raw --quiet
		reinstall
		printf 'admin_user=admin\nadmin_password=%s\ndatabase_user=root\ndatabase_password=%s\n' "$ADMIN_PASSWORD" "$DB_PASSWORD" >"$TMP_DIR/credentials"
		printf '%s\n' "$PHP_VERSION" "$MULTISITE" "$BASE_URL" >"$TMP_DIR/site" # NOSONAR: disposable HTTP bound only to 127.0.0.1.
		STARTED=0
		printf 'Site: %s\nAdmin: %s/wp-admin/\nLogin: admin / %s\nDatabase password: %s\nCredentials: %s/credentials\n' "$BASE_URL" "$BASE_URL" "$ADMIN_PASSWORD" "$DB_PASSWORD" "$TMP_DIR" # NOSONAR: disposable HTTP bound only to 127.0.0.1.
		;;
	reinstall) load_site; reinstall ;;
	wp) load_site; wp_cli "$@" ;;
	url) load_site; printf '%s\n' "$BASE_URL" ;; # NOSONAR: disposable HTTP bound only to 127.0.0.1.
	log) load_site; docker exec "$NAME-web" sh -c 'if [ -f wp-content/debug.log ]; then cat wp-content/debug.log; fi' ;;
	down) down ;;
	*) die "unknown command: $command" ;;
	esac
	return 0
}

main "$@"
