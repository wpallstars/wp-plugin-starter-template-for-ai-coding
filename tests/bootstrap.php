<?php
/**
 * PHPUnit bootstrap file
 *
 * @package WPALLSTARS\PluginStarterTemplate
 */

// First, we need to load the composer autoloader so we can use WP Mock.
require_once dirname(__DIR__) . '/vendor/autoload.php';

// No need to import WP_Mock classes here

// Now call the bootstrap method of WP Mock.
WP_Mock::bootstrap();

/**
 * Now we define a few constants to help us with testing.
 */
define('WPST_PLUGIN_DIR', dirname(__DIR__) . '/');
define('WPST_PLUGIN_URL', 'http://example.org/wp-content/plugins/wp-plugin-starter-template/');
define('WPST_VERSION', '0.1.0');

/**
 * Now we include any plugin files that we need to be able to run the tests.
 * This should be files that define the functions and classes you're going to test.
 */
require_once WPST_PLUGIN_DIR . 'includes/core.php';
require_once WPST_PLUGIN_DIR . 'includes/plugin.php';
require_once WPST_PLUGIN_DIR . 'admin/lib/admin.php';
