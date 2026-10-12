#!/usr/bin/env bash
# Check the shared preview site's admin screens in a browser, signed in, and
# read the debug log lines a check added (DEVELOPMENT.md → Preview site).
# Needs no WP-CLI and no reads outside the repository by file tools, so it
# works for people, agents and headless workers alike.
#
# Usage: scripts/preview-browser.sh [--site DIR] COMMAND
#   login [--user ID|LOGIN]  Sign in for one hour (default: the first
#                            administrator; on a network, the first super
#                            admin) and write a Playwright storageState file,
#                            mode 600, in ${TMPDIR:-/tmp}. Prints its path, the
#                            admin URL and the expiry, never cookie values.
#   logout FILE              End that session and delete the file. Always log
#                            out when done.
#   log-mark                 Print a mark: the debug log's line count now.
#   log-since MARK [--all]   Print the debug log entries added since MARK,
#                            only those naming this plugin's slug (--all: all).
#   --site DIR               The site's WordPress folder (wp-load.php). Default
#                            as for scripts/preview-site.sh: <PREFIX>_PREVIEW_SITE,
#                            then the site remembered for this clone.
#
# It runs the site's WordPress with the local php, with memory_limit 1024M:
# PHP's 128M default cannot load a site with many plugins. For a LocalWP site
# it uses the site's database socket from Local's sites.json (never its
# password). For other local hosts, <PREFIX>_PREVIEW_PHP_ARGS holds the php
# options instead, such as "-d mysqli.default_socket=/path/to/mysqld.sock".
# <PREFIX>_PREVIEW_HOST is the host name WordPress sees while it loads
# (default: Local's domain for the site, else localhost). The prefix is the
# plugin's constant prefix, such as WPSTARTER.

# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Marcus Quinn
# Additional terms (GPL-3.0 section 7(b)): ATTRIBUTION.txt
# Provenance: wpas-e4502af0f07e8a92. Copies, even of part, keep these lines.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
# shellcheck source=scripts/lib/plugin.sh disable=SC1091 # followed only with -x
. "$SCRIPT_DIR/lib/plugin.sh"

# Where the script was started: a relative state file is relative to it.
START_DIR="$PWD"
readonly START_DIR
# Results, set by the functions below (Bash 3.2 has no namerefs).
SITE=""
PHP_ARGS=()
SITE_HOST=""

die() {
	local message="$1"
	printf 'preview-browser: %s\n' "$message" >&2
	exit 1
}

usage() {
	sed -n '2,29p' "$0" | sed 's/^# \{0,1\}//'
	return 0
}

# Local's id and domain for the site whose app/public folder is SITE, as
# "id<TAB>domain", from sites.json in Local's folder (macOS, then Linux).
# Reads only each site's path, id and domain. Returns 1 for other sites.
local_site() {
	local base sites
	for base in "$HOME/Library/Application Support/Local" "${XDG_CONFIG_HOME:-$HOME/.config}/Local"; do
		sites="$base/sites.json"
		[[ -f "$sites" ]] || continue
		# shellcheck disable=SC2016 # PHP code, not shell expansions
		if php -r '
			$sites = json_decode( (string) file_get_contents( $argv[1] ), true );
			$want = realpath( $argv[2] );
			foreach ( is_array( $sites ) ? $sites : array() as $id => $site ) {
				$path = is_array( $site ) && isset( $site["path"] ) ? (string) $site["path"] : "";
				if ( 0 === strpos( $path, "~/" ) ) {
					$path = getenv( "HOME" ) . substr( $path, 1 );
				}
				if ( "" !== $path && false !== $want && realpath( $path . "/app/public" ) === $want ) {
					echo $id, "\t", isset( $site["domain"] ) ? (string) $site["domain"] : "", "\t", $argv[3], "\n";
					exit( 0 );
				}
			}
			exit( 1 );' -- "$sites" "$SITE" "$base"; then
			return 0
		fi
	done
	return 1
}

# Sets PHP_ARGS and SITE_HOST: memory_limit, then <PREFIX>_PREVIEW_PHP_ARGS,
# or for a Local site its database socket.
php_setup() {
	local own info id domain base socket
	command -v php >/dev/null || die "php not found; install PHP 7.4 or later"
	# Fatal errors only (E_ERROR, E_PARSE, E_CORE_ERROR, E_COMPILE_ERROR,
	# E_USER_ERROR, E_RECOVERABLE_ERROR), on stderr, never in the site's log:
	# other plugins' notices under this php are not what a check looks for.
	PHP_ARGS=(-d memory_limit=1024M -d display_errors=stderr -d log_errors=0 -d error_reporting=4437)
	SITE_HOST="$(plugin_env PREVIEW_HOST)"
	own="$(plugin_env PREVIEW_PHP_ARGS)"
	if [[ -n "$own" ]]; then
		local -a extra
		read -r -a extra <<<"$own"
		PHP_ARGS+=("${extra[@]}")
	elif info="$(local_site)"; then
		IFS=$'\t' read -r id domain base <<<"$info"
		socket="$base/run/$id/mysql/mysqld.sock"
		[[ -S "$socket" ]] || die "the Local site's database is not running (no $socket); start the site in Local"
		PHP_ARGS+=(-d "mysqli.default_socket=$socket" -d "pdo_mysql.default_socket=$socket")
		[[ -n "$SITE_HOST" ]] || SITE_HOST="$domain"
	fi
	[[ -n "$SITE_HOST" ]] || SITE_HOST="localhost"
	return 0
}

# Run COMMAND in the site's WordPress (the PHP below), with ARGS.
wp_run() {
	local command="$1"
	shift
	local status=0
	PREVIEW_HOST="$SITE_HOST" php "${PHP_ARGS[@]}" -- "$command" "$SITE" "$@" <<'PHP' || status=$?
<?php
// scripts/preview-browser.sh runs this in the preview site's WordPress.
// Nothing here prints a cookie value or a session token.
$args    = array_slice( $argv, 1 );
$command = (string) array_shift( $args );
$site    = (string) array_shift( $args );

function preview_fail( $message ) {
	fwrite( STDERR, 'preview-browser: ' . $message . "\n" );
	exit( 3 );
}

$host = (string) getenv( 'PREVIEW_HOST' );
$_SERVER['HTTP_HOST']       = $host;
$_SERVER['SERVER_NAME']     = $host;
$_SERVER['SERVER_PORT']     = '80';
$_SERVER['SERVER_PROTOCOL'] = 'HTTP/1.1';
$_SERVER['REQUEST_METHOD']  = 'GET';
$_SERVER['REQUEST_URI']     = '/';
$_SERVER['SCRIPT_NAME']     = '/index.php';
$_SERVER['PHP_SELF']        = '/index.php';
$_SERVER['REMOTE_ADDR']     = '127.0.0.1';
$_SERVER['HTTP_USER_AGENT'] = 'scripts/preview-browser.sh';

// Page caches skip logged-in cookie names. This is not WordPress's hashed
// LOGGED_IN_COOKIE, so it bypasses the page cache without signing anyone in.
$_COOKIE['wordpress_logged_in_preview_browser'] = '1';

// Keep this run's own PHP messages out of the site's debug log, so a check
// finds only what its pages wrote: WordPress leaves error logging and
// reporting as php was started (fatal errors to stderr), and its fatal
// error handler (recovery mode emails) stays off. Hooks set before
// WordPress loads are kept (WP_Hook::build_preinitialized_hooks()).
$preview_off = function () {
	return false;
};
$GLOBALS['wp_filter'] = array(
	'enable_wp_debug_mode_checks'   => array( 10 => array( array( 'function' => $preview_off, 'accepted_args' => 1 ) ) ),
	'wp_fatal_error_handler_enabled' => array( 10 => array( array( 'function' => $preview_off, 'accepted_args' => 1 ) ) ),
);
// The log path needs only WordPress's configuration, not its plugins.
if ( 'log-path' === $command ) {
	define( 'SHORTINIT', true );
}
// Whatever plugins print while loading is not this script's output.
$preview_loaded = false;
// A page cache can exit inside wp-load.php, never reaching the check below.
register_shutdown_function( function () use ( &$preview_loaded ) {
	if ( ! $preview_loaded ) {
		preview_fail( 'WordPress exited before loading; check the page cache' );
	}
} );
ob_start();
require $site . '/wp-load.php';
$preview_loaded = true;
while ( ob_get_level() > 0 ) {
	ob_end_clean();
}
// log-path deliberately uses SHORTINIT and does not load plugins or wp_loaded.
if ( 'log-path' !== $command && ! did_action( 'wp_loaded' ) ) {
	preview_fail( 'WordPress did not finish loading (wp_loaded did not run)' );
}

// The user to sign in: an ID or login, or the first administrator (on a
// network, the first super admin).
function preview_user( $which ) {
	if ( '' !== $which ) {
		$user = ctype_digit( $which ) ? get_user_by( 'id', (int) $which ) : get_user_by( 'login', $which );
		if ( ! $user ) {
			preview_fail( 'no user ' . $which );
		}
		return $user;
	}
	if ( is_multisite() ) {
		foreach ( get_super_admins() as $login ) {
			$user = get_user_by( 'login', $login );
			if ( $user ) {
				return $user;
			}
		}
	}
	$ids = get_users(
		array(
			'role'    => 'administrator',
			'orderby' => 'ID',
			'order'   => 'ASC',
			'number'  => 1,
			'fields'  => 'ID',
		)
	);
	if ( empty( $ids ) ) {
		preview_fail( 'no administrator on this site; pass --user' );
	}
	return get_user_by( 'id', (int) $ids[0] );
}

// One Playwright cookie.
function preview_cookie( $name, $value, $domain, $path, $expires, $secure ) {
	return array(
		'name'     => $name,
		'value'    => $value,
		'domain'   => $domain,
		'path'     => '' === $path ? '/' : $path,
		'expires'  => $expires,
		'httpOnly' => true,
		'secure'   => $secure,
		'sameSite' => 'Lax',
	);
}

switch ( $command ) {
	case 'log-path':
		$log = defined( 'WP_DEBUG_LOG' ) ? WP_DEBUG_LOG : false;
		if ( ! defined( 'WP_DEBUG' ) || ! WP_DEBUG || ! $log ) {
			preview_fail( 'the debug log is off: set WP_DEBUG and WP_DEBUG_LOG in wp-config.php' );
		}
		echo in_array( strtolower( (string) $log ), array( 'true', '1' ), true ) ? WP_CONTENT_DIR . '/debug.log' : (string) $log, "\n";
		break;

	case 'login':
		$user       = preview_user( (string) array_shift( $args ) );
		if ( ! $user ) {
			preview_fail( 'no user to sign in; pass --user' );
		}
		$expiration = time() + HOUR_IN_SECONDS;
		$admin      = admin_url();
		// As wp_set_auth_cookie(): the secure auth cookie when the admin is
		// on https, and the logged-in cookie secure only when home is too.
		$secure    = 'https' === wp_parse_url( $admin, PHP_URL_SCHEME );
		$secure_li = $secure && 'https' === wp_parse_url( get_option( 'home' ), PHP_URL_SCHEME );
		$scheme    = $secure ? 'secure_auth' : 'auth';
		$auth_name = $secure ? SECURE_AUTH_COOKIE : AUTH_COOKIE;
		$domain    = COOKIE_DOMAIN ? COOKIE_DOMAIN : (string) wp_parse_url( $admin, PHP_URL_HOST );
		$token     = WP_Session_Tokens::get_instance( $user->ID )->create( $expiration );
		$auth      = wp_generate_auth_cookie( $user->ID, $expiration, $scheme, $token );
		$logged_in = wp_generate_auth_cookie( $user->ID, $expiration, 'logged_in', $token );
		$cookies   = array(
			preview_cookie( $auth_name, $auth, $domain, ADMIN_COOKIE_PATH, $expiration, $secure ),
			preview_cookie( $auth_name, $auth, $domain, PLUGINS_COOKIE_PATH, $expiration, $secure ),
			preview_cookie( LOGGED_IN_COOKIE, $logged_in, $domain, COOKIEPATH, $expiration, $secure_li ),
		);
		if ( COOKIEPATH !== SITECOOKIEPATH ) {
			$cookies[] = preview_cookie( LOGGED_IN_COOKIE, $logged_in, $domain, SITECOOKIEPATH, $expiration, $secure_li );
		}
		$state = array(
			'cookies' => $cookies,
			'origins' => array(),
		);
		// The file exists already, mode 600; writing keeps the mode.
		if ( false === file_put_contents( (string) array_shift( $args ), wp_json_encode( $state, JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES ) . "\n" ) ) {
			WP_Session_Tokens::get_instance( $user->ID )->destroy( $token );
			preview_fail( 'cannot write the state file' );
		}
		printf( "user\t%s (ID %d)\nadmin\t%s\nexpires\t%s\n", $user->user_login, $user->ID, $admin, gmdate( 'Y-m-d H:i', $expiration ) . ' UTC' );
		break;

	case 'logout':
		$file  = (string) array_shift( $args );
		$state = json_decode( (string) file_get_contents( $file ), true );
		$value = '';
		foreach ( isset( $state['cookies'] ) && is_array( $state['cookies'] ) ? $state['cookies'] : array() as $cookie ) {
			if ( isset( $cookie['name'], $cookie['value'] ) && LOGGED_IN_COOKIE === $cookie['name'] ) {
				$value = (string) $cookie['value'];
			}
		}
		$parts = '' === $value ? false : wp_parse_auth_cookie( $value, 'logged_in' );
		$user  = $parts ? get_user_by( 'login', $parts['username'] ) : false;
		if ( ! $user ) {
			preview_fail( 'not a sign-in file of this site from scripts/preview-browser.sh login: ' . $file );
		}
		WP_Session_Tokens::get_instance( $user->ID )->destroy( $parts['token'] );
		printf( "user\t%s (ID %d)\n", $user->user_login, $user->ID );
		break;

	default:
		preview_fail( 'unknown command ' . $command );
}
PHP
	case "$status" in
	0) return 0 ;;
	3) exit 1 ;;
	*) die "WordPress did not load (php exit $status); its errors are in the site's debug log" ;;
	esac
}

# The debug log's path, from WordPress (WP_DEBUG_LOG).
log_path() {
	local path
	path="$(wp_run log-path)"
	[[ -n "$path" ]] || die "no debug log path"
	printf '%s\n' "$path"
	return 0
}

# Lines in FILE (0 when it does not exist yet).
line_count() {
	local file="$1"
	if [[ ! -f "$file" ]]; then
		printf '0\n'
		return 0
	fi
	wc -l <"$file" | tr -d ' '
	return 0
}

# The value after KEY and a tab in TEXT's lines (the PHP's output).
out_field() {
	local text="$1"
	local key="$2"
	local line
	while IFS= read -r line; do
		if [[ "$line" == "$key"$'\t'* ]]; then
			printf '%s\n' "${line#*$'\t'}"
			return 0
		fi
	done <<<"$text"
	return 0
}

cmd_login() {
	local user=""
	while [[ $# -gt 0 ]]; do
		local arg="$1"
		local value="${2:-}"
		case "$arg" in
		--user)
			[[ $# -ge 2 ]] || die "--user needs an ID or login"
			user="$value"
			shift
			;;
		*) die "unknown argument for login: $arg" ;;
		esac
		shift
	done
	local file out who admin expires
	# mktemp makes the file mode 600; the session is written into it.
	local tmp="${TMPDIR:-/tmp}"
	file="$(mktemp "${tmp%/}/$PLUGIN_SLUG-browser.XXXXXX")"
	chmod 600 "$file"
	if ! out="$(wp_run login "$user" "$file")"; then
		rm -f "$file"
		exit 1
	fi
	who="$(out_field "$out" user)"
	admin="$(out_field "$out" admin)"
	expires="$(out_field "$out" expires)"
	if [[ -z "$who" || -z "$admin" || -z "$expires" || ! -s "$file" ]]; then
		rm -f "$file"
		die "WordPress returned no complete sign-in; check the page cache"
	fi
	printf 'Signed in as %s until %s.\n' "$who" "$expires"
	printf 'State file: %s\n' "$file"
	printf 'Admin: %s\n' "$admin"
	printf 'Log out when done: scripts/preview-browser.sh logout %s\n' "$file"
	return 0
}

cmd_logout() {
	local file="${1:-}"
	[[ -n "$file" ]] || die "logout needs the state file login printed"
	# Relative to where the script was started, not the repository root.
	[[ "$file" = /* ]] || file="$START_DIR/$file"
	[[ -f "$file" ]] || die "no state file $file"
	local out
	out="$(wp_run logout "$file")" || exit 1
	rm -f "$file"
	printf 'Signed out %s: session ended, %s deleted.\n' "$(out_field "$out" user)" "$file"
	return 0
}

cmd_log_since() {
	local mark="" all=0
	while [[ $# -gt 0 ]]; do
		local arg="$1"
		case "$arg" in
		--all) all=1 ;;
		*)
			[[ -z "$mark" ]] || die "unknown argument for log-since: $arg"
			mark="$arg"
			;;
		esac
		shift
	done
	[[ "$mark" =~ ^[0-9]+$ ]] || die "log-since needs the number log-mark printed"
	local path now
	path="$(log_path)"
	now="$(line_count "$path")"
	if [[ "$now" -lt "$mark" ]]; then
		printf 'preview-browser: the debug log is shorter than the mark (cleared or rotated); all of it follows\n' >&2
		mark=0
	fi
	[[ -f "$path" ]] || return 0
	# An entry starts with "[date]"; the lines under it (stack traces, also
	# Xdebug's "[date] PHP Stack trace:" and "[date] PHP   1. ..." lines) go
	# with it, so an entry is kept or left out whole.
	awk -v mark="$mark" -v all="$all" -v slug="$PLUGIN_SLUG" '
		function flush() {
			if (entry != "" && (all || index(entry, slug))) print entry
			entry = ""
		}
		NR <= mark { next }
		/^\[[^]]*\] PHP (Stack trace:|  +[0-9]+\. )/ { entry = (entry == "" ? $0 : entry "\n" $0); next }
		/^\[/ { flush(); entry = $0; next }
		{ entry = (entry == "" ? $0 : entry "\n" $0) }
		END { flush() }' "$path"
	return 0
}

main() {
	local site_arg=""
	while [[ $# -gt 0 ]]; do
		local arg="$1"
		local value="${2:-}"
		case "$arg" in
		--site)
			[[ $# -ge 2 ]] || die "--site needs the WordPress folder"
			site_arg="$value"
			shift 2
			;;
		-h | --help)
			usage
			return 0
			;;
		*) break ;;
		esac
	done
	local command="${1:-}"
	[[ -n "$command" ]] || {
		usage >&2
		exit 1
	}
	shift

	local root
	root="$(git rev-parse --show-toplevel)" || die "run this inside a checkout of the plugin"
	cd "$root"
	plugin_identity HEAD || die "cannot tell which plugin this is"
	if [[ -n "$site_arg" ]] && [[ "$site_arg" != /* ]]; then
		site_arg="$START_DIR/$site_arg"
	fi
	plugin_preview_site "$site_arg" 0 || die "$PLUGIN_SITE_ERROR"
	SITE="$PLUGIN_SITE"
	php_setup

	case "$command" in
	login) cmd_login "$@" ;;
	logout) cmd_logout "$@" ;;
	log-mark)
		local path
		path="$(log_path)"
		line_count "$path"
		;;
	log-since) cmd_log_since "$@" ;;
	*) die "unknown command: $command (login, logout, log-mark, log-since)" ;;
	esac
	return 0
}

main "$@"
