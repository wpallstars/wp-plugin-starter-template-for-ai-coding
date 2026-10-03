<?php
/**
 * Constants for PHPStan (phpstan.neon.dist). WordPress's functions and
 * classes come from szepeviktor/phpstan-wordpress; this adds the constants
 * WordPress defines while it loads (wp-settings.php, wp-config.php) and
 * those wp-plugin-starter-template.php defines.
 *
 * @package WPStarter
 */

define('WPINC', 'wp-includes');
define('COOKIEPATH', '/');
define('SITECOOKIEPATH', '/');
define('DB_NAME', 'wordpress');
define('WPSTARTER_VERSION', '0.0.0');
define('WPSTARTER_FILE', dirname(__DIR__) . '/wp-plugin-starter-template.php');
define('WPSTARTER_DIR', dirname(__DIR__) . '/');
define('WPSTARTER_URL', 'https://example.com/wp-content/plugins/wp-plugin-starter-template/');
