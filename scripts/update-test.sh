#!/usr/bin/env bash
# Update test (RELEASING.md step 4): install the previous GitHub release on a
# disposable WordPress in Docker, then check that WordPress offers the new
# release from its zip (WP-CLI, the Updates screen's Check again, the Plugins
# screen) and that the update installs. Nothing is kept and no other site is
# touched.
#
# Usage: scripts/update-test.sh [--from VERSION] [--to VERSION] [--wp VERSION]
#                               [--php VERSION] [--keep-log FILE]
#   --from VERSION   Release installed first (default: the one before --to).
#   --to VERSION     Release the site must be offered (default: the newest).
#   --wp VERSION     WordPress version (default: latest). The minimum is 6.2.
#   --php VERSION    PHP version of the Docker images (default: 8.3).
#   --keep-log FILE  Save the site's debug.log to FILE.
#
# Releases are read with gh from the repository in the GitHub Plugin URI
# header, so gh must be signed in to read a private one. Sites read releases
# without signing in: for a private repository, export WPALLSTARS_GITHUB_TOKEN
# (a read-only token) and the test site gets it from the environment. Fails
# on a missing release or asset, no update offered, a failed update or any PHP
# message in debug.log. Needs Docker, curl, gh and internet access.

# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Marcus Quinn
# Additional terms (GPL-3.0 section 7(b)): ATTRIBUTION.txt

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
# shellcheck source=scripts/lib/plugin.sh disable=SC1091 # followed only with -x
. "$SCRIPT_DIR/lib/plugin.sh"

readonly TOKEN_NAME="WPALLSTARS_GITHUB_TOKEN"

# Set in main() from the plugin's main file and the options.
SLUG=""
BASENAME=""
REPO=""
DB_IMAGE=""
NAME=""
TMP_DIR=""
STARTED=0
WP_VERSION="latest"
PHP_VERSION="8.3"
FROM=""
TO=""
BASE_URL=""
DB_PASSWORD=""
ADMIN_PASSWORD=""
FAILED=0
TOKEN_ARGS=()
# The new release asset's API address: with a token, the shared updater
# offers this one, as private repositories need it.
ASSET_API=""

die() {
	local message="$1"
	printf 'update-test: %s\n' "$message" >&2
	exit 2
}

usage() {
	sed -n '2,22p' "$0" | sed 's/^# \{0,1\}//'
	return 0
}

ok() {
	local message="$1"
	printf '  ok   %s\n' "$message"
	return 0
}

fail() {
	local message="$1"
	printf '  FAIL %s\n' "$message"
	FAILED=1
	return 0
}

# ok when the actual value is the wanted one, else fail with both.
expect() {
	local actual="$1"
	local wanted="$2"
	local what="$3"
	if [[ "$actual" == "$wanted" ]]; then
		ok "$what: $actual"
	else
		fail "$what: $actual, not $wanted"
	fi
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
			[[ "$attempt" -eq 3 ]] && printf 'update-test: could not remove %s-wp or network %s\n' "$NAME" "$NAME" >&2
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

# wp-cli in the disposable site; the old release's zip is mounted at /zips.
# The token, when set, is passed by name only, so its value is in no
# command line.
wp_cli() {
	docker run --rm --network "$NAME" -v "$NAME-wp:/var/www/html" -v "$TMP_DIR/zips:/zips:ro" \
		-e WP_CLI_CACHE_DIR=/tmp/wp-cli-cache ${TOKEN_ARGS[@]+"${TOKEN_ARGS[@]}"} \
		--user 33:33 "wordpress:cli-php$PHP_VERSION" php -d memory_limit=1G /usr/local/bin/wp "$@" || return 1
	return 0
}

# Release tags with numbers only (vX.Y.Z), newest first; drafts and
# pre-releases left out, as the shared updater leaves them out.
release_versions() {
	local tags
	tags="$(gh release list --repo "$REPO" --exclude-drafts --exclude-pre-releases --limit 50 \
		--json tagName --jq '.[].tagName')" || return 1
	printf '%s\n' "$tags" | sed -nE 's/^v([0-9]+\.[0-9]+\.[0-9]+)$/\1/p'
	return 0
}

pick_versions() {
	local versions
	versions="$(release_versions)" || die "cannot list the releases of $REPO (is gh signed in?)"
	[[ -n "$versions" ]] || die "$REPO has no vX.Y.Z releases"
	if [[ -z "$TO" ]]; then
		TO="$(head -n 1 <<<"$versions")"
	fi
	grep -qxF "$TO" <<<"$versions" || die "no release v$TO in $REPO"
	if [[ -z "$FROM" ]]; then
		FROM="$(printf '%s\n' "$versions" | grep -A1 -xF "$TO" | sed -n 2p)"
		[[ -n "$FROM" ]] || die "no release before v$TO in $REPO; give --from"
	fi
	grep -qxF "$FROM" <<<"$versions" || die "no release v$FROM in $REPO"
	[[ "$FROM" != "$TO" ]] || die "--from and --to are the same version ($TO)"
	return 0
}

# The new release must carry exactly the asset the shared updater takes,
# plus, from the release workflow in a public repository, its provenance
# bundle (a name that does not start with the slug, so Git Updater never
# takes it for the plugin), which must verify against the zip.
check_assets() {
	local assets bundle="provenance-$SLUG-$TO.sigstore.json"
	assets="$(gh release view "v$TO" --repo "$REPO" --json assets --jq '.assets[].name')" ||
		die "cannot read the assets of v$TO in $REPO"
	assets="$(LC_ALL=C sort <<<"$assets")"
	if [[ "$assets" == "$SLUG-$TO.zip" ]]; then
		ok "v$TO has one asset, $SLUG-$TO.zip (no provenance bundle)"
	elif [[ "$assets" == "$(printf '%s\n' "$SLUG-$TO.zip" "$bundle" | LC_ALL=C sort)" ]]; then
		ok "v$TO has the asset $SLUG-$TO.zip and its provenance bundle"
		check_provenance "$bundle"
	else
		fail "v$TO assets are not exactly $SLUG-$TO.zip (and $bundle): $(printf '%s' "$assets" | tr '\n' ' ')"
	fi
	# The name goes to jq as data (env), not joined into the filter.
	ASSET_API="$(ASSET_NAME="$SLUG-$TO.zip" gh release view "v$TO" --repo "$REPO" --json assets \
		--jq '.assets[] | select(.name == env.ASSET_NAME) | .apiUrl')" ||
		die "cannot read the assets of v$TO in $REPO"
	gh release download "v$FROM" --repo "$REPO" --pattern "$SLUG-$FROM.zip" --dir "$TMP_DIR/zips" ||
		die "v$FROM has no asset $SLUG-$FROM.zip"
	chmod 644 "$TMP_DIR/zips/$SLUG-$FROM.zip"
	return 0
}

# The bundle is Sigstore build provenance for the zip, made by this
# repository's release workflow from the release's tag.
check_provenance() {
	local bundle="$1"
	local dir="$TMP_DIR/provenance"
	mkdir -p "$dir"
	if ! gh release download "v$TO" --repo "$REPO" --pattern "$SLUG-$TO.zip" --pattern "$bundle" --dir "$dir"; then
		fail "cannot download $SLUG-$TO.zip and $bundle"
		return 0
	fi
	if gh attestation verify "$dir/$SLUG-$TO.zip" --bundle "$dir/$bundle" --repo "$REPO" \
		--signer-workflow "$REPO/.github/workflows/release.yml" --source-ref "refs/tags/v$TO" >/dev/null; then
		ok "provenance verifies: built by .github/workflows/release.yml from v$TO"
	else
		fail "provenance for $SLUG-$TO.zip does not verify (gh attestation verify; --source-ref needs a recent gh, this is $(gh --version | head -n 1))"
	fi
	return 0
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
		${TOKEN_ARGS[@]+"${TOKEN_ARGS[@]}"} -p 127.0.0.1::80 "wordpress:php$PHP_VERSION-apache" >/dev/null
	# Plain HTTP on purpose: a throwaway site that only listens on 127.0.0.1.
	BASE_URL="http://$(docker port "$NAME-web" 80 | head -n 1)"

	wp_cli config create --dbname=wordpress --dbuser=root --dbpass="$DB_PASSWORD" --dbhost="$NAME-db" --skip-check --quiet
	wp_cli config set WP_DEBUG true --raw --quiet
	wp_cli config set WP_DEBUG_LOG true --raw --quiet
	wp_cli config set WP_DEBUG_DISPLAY false --raw --quiet
	wp_cli config set DISABLE_WP_CRON true --raw --quiet
	if [[ "${#TOKEN_ARGS[@]}" -gt 0 ]]; then
		# wp-config.php reads the token from the environment; its value is
		# never written to a file.
		wp_cli config set "$TOKEN_NAME" "getenv('$TOKEN_NAME')" --raw --quiet
	fi
	wp_cli core install --title=UpdateTest --admin_user=admin --admin_password="$ADMIN_PASSWORD" --admin_email=admin@example.com --skip-email --quiet --url="$BASE_URL" # NOSONAR: local-only HTTP, see BASE_URL
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

# Load an admin page into $TMP_DIR/page; prints the HTTP status.
admin_page() {
	local path="$1"
	local code
	# curl prints 000 itself when it cannot connect, and exits non-zero.
	code="$(curl -sS -o "$TMP_DIR/page" -w '%{http_code}' --max-time 120 -b "$TMP_DIR/cookies" "$BASE_URL$path" || true)"
	printf '%s' "${code:-000}"
	return 0
}

# The update WordPress has on record for the plugin, after a fresh check:
# "new_version package", or "none".
update_offer() {
	# shellcheck disable=SC2016 # PHP code: its $variables are PHP's, not the shell's.
	wp_cli eval '
		delete_site_transient("update_plugins");
		wp_update_plugins();
		$t = get_site_transient("update_plugins");
		$r = isset($t->response["'"$BASENAME"'"]) ? $t->response["'"$BASENAME"'"] : null;
		echo $r ? $r->new_version . " " . $r->package : "none";' || return 1
	return 0
}

install_from() {
	printf '\nInstalling %s from the v%s release\n' "$SLUG-$FROM.zip" "$FROM"
	wp_cli plugin install "/zips/$SLUG-$FROM.zip" --activate --quiet || die "could not install and activate v$FROM"
	expect "$(wp_cli plugin get "$SLUG" --field=version)" "$FROM" "installed version"
	return 0
}

check_offer() {
	printf '\nUpdate check (WP-CLI):\n'
	local offer repo
	offer="$(update_offer)" || offer="error"
	printf '  offer: %s\n' "$offer"
	# Exactly the release asset. GitHub's own address may differ from the
	# header's owner/repo in case only, so only that part ignores case.
	local start="$TO https://github.com/"
	local end="/releases/download/v$TO/$SLUG-$TO.zip"
	repo=""
	if [[ "$offer" == "$start"*"$end" ]]; then
		repo="${offer#"$start"}"
		repo="${repo%"$end"}"
	fi
	if [[ -n "$repo" && "$(tr '[:upper:]' '[:lower:]' <<<"$repo")" == "$(tr '[:upper:]' '[:lower:]' <<<"$REPO")" ]]; then
		ok "offers $TO from the release asset"
	elif [[ "${#TOKEN_ARGS[@]}" -gt 0 && -n "$ASSET_API" && "$offer" == "$TO $ASSET_API" ]]; then
		ok "offers $TO from the release asset (its API address, with the token)"
	elif [[ "${#TOKEN_ARGS[@]}" -gt 0 ]]; then
		fail "no offer of $TO from $SLUG-$TO.zip (check that $TOKEN_NAME can read $REPO)"
	else
		fail "no offer of $TO from $SLUG-$TO.zip (a private repository needs $TOKEN_NAME)"
	fi
	return 0
}

check_screens() {
	printf '\nUpdates screen (Check again) and Plugins screen:\n'
	local name status
	# The admin screens print the name HTML-escaped.
	name="$(printf '%s' "$PLUGIN_NAME" | sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g')"
	wp_cli transient delete update_plugins --network --quiet || true
	status="$(admin_page '/wp-admin/update-core.php?force-check=1')"
	if [[ "$status" == "200" ]] && grep -qF "$name" "$TMP_DIR/page" && grep -qF "Update to $TO" "$TMP_DIR/page"; then
		ok "Updates screen lists $PLUGIN_NAME: Update to $TO"
	else
		fail "Updates screen ($status) does not list $PLUGIN_NAME with Update to $TO"
	fi
	status="$(admin_page '/wp-admin/plugins.php')"
	if [[ "$status" == "200" ]] && grep -qF "There is a new version of $name available" "$TMP_DIR/page"; then
		ok "Plugins screen shows the update notice"
	else
		fail "Plugins screen ($status) shows no update notice for $PLUGIN_NAME"
	fi
	return 0
}

check_update() {
	printf '\nInstalling the update:\n'
	wp_cli plugin update "$SLUG" --quiet || fail "wp plugin update $SLUG"
	local status offer
	expect "$(wp_cli plugin get "$SLUG" --field=version)" "$TO" "version after the update"
	expect "$(wp_cli plugin get "$SLUG" --field=status)" "active" "status after the update"
	offer="$(update_offer)" || offer="error"
	expect "$offer" "none" "update offered after updating"
	status="$(admin_page "/wp-admin/options-general.php?page=$SLUG")"
	if [[ "$status" == "200" ]] && ! grep -q 'There has been a critical error' "$TMP_DIR/page"; then
		ok "settings screen loads"
	else
		fail "settings screen answered $status"
	fi
	return 0
}

# A must-use plugin that logs a notice for /?update-canary, so an empty
# debug.log proves the site logged nothing else (not that logging is off).
add_canary() {
	docker exec -u www-data "$NAME-web" sh -c 'mkdir -p /var/www/html/wp-content/mu-plugins && printf "%s\n" "<?php" \
		"if (isset(\$_GET[\"update-canary\"])) { trigger_error(\"update-test canary\", E_USER_NOTICE); }" \
		>/var/www/html/wp-content/mu-plugins/update-canary.php' || return 1
	return 0
}

check_debug_log() {
	local keep="$1"
	local log
	printf '\ndebug.log:\n'
	curl -sS -o /dev/null --max-time 60 "$BASE_URL/?update-canary" || true
	log="$(docker exec "$NAME-web" sh -c 'cat /var/www/html/wp-content/debug.log 2>/dev/null' || true)"
	if [[ -n "$keep" ]]; then
		printf '%s\n' "$log" >"$keep"
	fi
	if ! grep -q 'update-test canary' <<<"$log"; then
		fail "debug.log does not work: the canary notice is missing"
		return 0
	fi
	log="$(printf '%s\n' "$log" | grep -v 'update-test canary' || true)"
	if [[ -n "$log" ]]; then
		printf '%s\n' "$log"
		fail "PHP messages in debug.log"
	else
		ok "no PHP messages (the canary notice arrived)"
	fi
	return 0
}

main() {
	local keep=""
	while [[ $# -gt 0 ]]; do
		local arg="$1"
		local value="${2:-}"
		case "$arg" in
		--from | --to | --wp | --php | --keep-log)
			[[ $# -ge 2 ]] || die "$arg needs a value"
			case "$arg" in
			--from) FROM="${value#v}" ;;
			--to) TO="${value#v}" ;;
			--wp) WP_VERSION="$value" ;;
			--php) PHP_VERSION="$value" ;;
			--keep-log)
				case "$value" in
				/*) keep="$value" ;;
				*) keep="$PWD/$value" ;;
				esac
				;;
			*) ;; # The outer pattern lists every option that takes a value.
			esac
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
	local version_re='^[0-9]+\.[0-9]+\.[0-9]+$'
	[[ -z "$FROM" || "$FROM" =~ $version_re ]] || die "--from must be X.Y.Z, not $FROM"
	[[ -z "$TO" || "$TO" =~ $version_re ]] || die "--to must be X.Y.Z, not $TO"

	command -v docker >/dev/null 2>&1 || die "needs Docker"
	command -v curl >/dev/null 2>&1 || die "needs curl"
	command -v gh >/dev/null 2>&1 || die "needs gh (GitHub CLI)"
	docker info >/dev/null 2>&1 || die "Docker is not running"
	local root
	root="$(git rev-parse --show-toplevel)" || die "run this inside a checkout of the plugin"
	cd "$root"
	plugin_identity HEAD || die "cannot tell which plugin this is"
	SLUG="$PLUGIN_SLUG"
	BASENAME="$SLUG/$PLUGIN_MAIN_FILE"
	REPO="$PLUGIN_REPO"
	[[ "$REPO" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || die "the main file has no GitHub Plugin URI header (owner/repo)"
	DB_IMAGE="$(plugin_env DB_IMAGE mariadb:10.6)"
	NAME="$SLUG-update-$$"
	if [[ -n "${!TOKEN_NAME:-}" ]]; then
		TOKEN_ARGS=(-e "$TOKEN_NAME")
	fi

	pick_versions
	printf 'Update test for %s (%s): v%s to v%s\n\n' "$PLUGIN_NAME" "$REPO" "$FROM" "$TO"

	trap cleanup EXIT
	TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/$SLUG-update.XXXXXX")"
	mkdir -p "$TMP_DIR/zips"
	chmod 755 "$TMP_DIR" "$TMP_DIR/zips"
	check_assets

	start_site
	add_canary || die "could not add the debug.log canary"
	install_from
	log_in
	check_offer
	check_screens
	check_update
	check_debug_log "$keep"

	printf '\n'
	if [[ "$FAILED" -eq 1 ]]; then
		printf 'Update test failed: v%s to v%s (WordPress %s, PHP %s).\n' "$FROM" "$TO" "$WP_VERSION" "$PHP_VERSION"
		return 1
	fi
	printf 'Update test passed: v%s to v%s (WordPress %s, PHP %s).\n' "$FROM" "$TO" "$WP_VERSION" "$PHP_VERSION"
	return 0
}

main "$@"
