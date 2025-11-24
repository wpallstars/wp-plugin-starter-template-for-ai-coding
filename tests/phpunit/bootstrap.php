<?php
/**
 * PHPUnit bootstrap file.
 *
 * @package WP_Plugin_Starter_Template_For_AI_Coding
 */

// Composer autoloader must be loaded before WP_PHPUNIT__DIR will be available.
require_once dirname( dirname( __DIR__ ) ) . '/vendor/autoload.php';

// Check if we're running the WordPress tests
if ( getenv( 'WP_PHPUNIT__DIR' ) ) {
	// Define PHPUnit Polyfills path for WordPress test suite.
	if ( ! defined( 'WP_TESTS_PHPUNIT_POLYFILLS_PATH' ) ) {
		define( 'WP_TESTS_PHPUNIT_POLYFILLS_PATH', dirname( dirname( __DIR__ ) ) . '/vendor/yoast/phpunit-polyfills/' );
	}

	// Give access to tests_add_filter() function.
	require_once getenv( 'WP_PHPUNIT__DIR' ) . '/includes/functions.php';

	/**
	 * Manually load the plugin being tested.
	 */
	function _manually_load_plugin() {
		require dirname( dirname( __DIR__ ) ) . '/wp-plugin-starter-template.php';
		// Load the multisite class for testing
		$multisite_file = dirname( dirname( __DIR__ ) ) . '/includes/multisite/class-multisite.php';
		if (file_exists($multisite_file)) {
			require $multisite_file;
		}
	}

	// Start up the WP testing environment.
	require getenv( 'WP_PHPUNIT__DIR' ) . '/includes/bootstrap.php';
} else {
	// We're running the WP_Mock tests
	WP_Mock::bootstrap();

	/**
	 * Now we define a few constants to help us with testing.
	 */
	define('WPST_PLUGIN_DIR', dirname(dirname(__DIR__)) . '/');
	define('WPST_PLUGIN_URL', 'http://example.org/wp-content/plugins/wp-plugin-starter-template/');
	define('WPST_VERSION', '0.1.0');

	/**
	 * Now we include any plugin files that we need to be able to run the tests.
	 * This should be files that define the functions and classes you're going to test.
	 */
	require_once WPST_PLUGIN_DIR . 'includes/class-core.php';
	require_once WPST_PLUGIN_DIR . 'includes/class-plugin.php';
	if (file_exists(WPST_PLUGIN_DIR . 'admin/lib/admin.php')) {
		require_once WPST_PLUGIN_DIR . 'admin/lib/admin.php';
	}
}
