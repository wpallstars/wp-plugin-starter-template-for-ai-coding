<?php
/**
 * Class AdminTest
 *
 * @package WPALLSTARS\PluginStarterTemplate
 * @group wpmock
 */

// Skip this test file if WP_Mock is not available or WordPress test framework is loaded.
if ( ! class_exists( 'WP_Mock' ) || class_exists( 'WP_UnitTestCase' ) ) {
	return;
}

use WPALLSTARS\PluginStarterTemplate\Admin\Admin;
use WPALLSTARS\PluginStarterTemplate\Core;

/**
 * Admin test case.
 */
class AdminTest extends \WP_Mock\Tools\TestCase {

    /**
     * Test instance
     *
     * @var Admin
     */
    private $admin;

    /**
     * Core mock
     *
     * @var Core
     */
    private $core;

    /**
     * Set up the test environment.
     */
    public function setUp(): void
    {
        parent::setUp();

        // Set up mocks
        WP_Mock::setUp();

        // Mock the Core class dependency using Mockery.
        $this->core = \Mockery::mock( '\WPALLSTARS\PluginStarterTemplate\Core' );
        // Add expectation for get_plugin_version BEFORE Admin is instantiated.
        $this->core->shouldReceive( 'get_plugin_version' )->andReturn( '1.0.0' );

        // Expect the action hook to be added BEFORE Admin is instantiated.
        \WP_Mock::expectActionAdded( 'admin_enqueue_scripts', array( \Mockery::any(), 'enqueue_admin_assets' ) );

        // Instantiate the Admin class (this triggers the constructor and add_hooks).
        $this->admin = new Admin( $this->core );
    }

    /**
     * Tear down test environment
     */
    public function tearDown(): void {
        WP_Mock::tearDown();
        parent::tearDown();
    }

    /**
     * Test constructor
     */
    public function test_constructor() {
        // Verify that the constructor initializes hooks
        $this->assertInstanceOf(Admin::class, $this->admin);
    }

    /**
     * Test the enqueue_admin_assets method.
     */
    public function test_enqueue_admin_assets(): void
    {
        // Define the PHPUNIT_RUNNING constant
        if ( ! defined( 'PHPUNIT_RUNNING' ) ) {
            define( 'PHPUNIT_RUNNING', true );
        }

        // Set up the superglobal for the test
        $_GET['page'] = 'wp_plugin_starter_template_settings';

        // Mock wp_unslash function
        WP_Mock::userFunction('wp_unslash', [
            'args' => ['wp_plugin_starter_template_settings'],
            'return' => 'wp_plugin_starter_template_settings',
        ]);

        // Mock WordPress functions used in the method
        WP_Mock::userFunction('plugin_dir_url', [
            'return' => 'http://example.com/wp-content/plugins/wp-plugin-starter-template/includes/Admin/',
        ]);

        // Mock wp_enqueue_style
        WP_Mock::userFunction('wp_enqueue_style', [
            'times' => 1,
            'args' => [
                'wpst-admin-styles',
                'http://example.com/wp-content/plugins/wp-plugin-starter-template/includes/Admin/../../admin/css/admin-styles.css',
                [],
                '1.0.0',
            ],
        ]);

        // Mock wp_enqueue_script
        WP_Mock::userFunction('wp_enqueue_script', [
            'times' => 1,
            'args' => [
                'wpst-admin-script',
                'http://example.com/wp-content/plugins/wp-plugin-starter-template/includes/Admin/../../admin/js/admin-scripts.js',
                ['jquery'],
                '1.0.0',
                true,
            ],
        ]);

        // Mock admin_url
        WP_Mock::userFunction('admin_url', [
            'args' => ['admin-ajax.php'],
            'return' => 'http://example.com/wp-admin/admin-ajax.php',
        ]);

        // Mock wp_create_nonce
        WP_Mock::userFunction('wp_create_nonce', [
            'args' => ['wpst_admin_nonce'],
            'return' => 'test_nonce_123',
        ]);

        // Mock wp_localize_script
        WP_Mock::userFunction('wp_localize_script', [
            'times' => 1,
            'args' => [
                'wpst-admin-script',
                'wpst_admin_data',
                [
                    'ajax_url' => 'http://example.com/wp-admin/admin-ajax.php',
                    'nonce' => 'test_nonce_123',
                ],
            ],
        ]);

        // Call the method
        $this->admin->enqueue_admin_assets();

        // If we get here without exceptions, the test passes
        $this->assertTrue(true);
    }
}
