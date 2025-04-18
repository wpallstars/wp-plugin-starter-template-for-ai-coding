<?php
/**
 * Class AdminTest
 *
 * @package WPALLSTARS\PluginStarterTemplate
 */

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
        // Define expected parameters for the functions
        $style_handle  = 'wpst-admin-style';
        $style_src     = 'path/to/admin/css/admin-styles.css';
        $script_handle = 'wpst-admin-script';
        $script_src    = 'path/to/admin/js/admin-scripts.js';
        $version       = '1.0.0'; // Match the version returned by the mocked core->get_plugin_version()

        // Expect wp_enqueue_style to be called
        \WP_Mock::userFunction(
            'wp_enqueue_style',
            [
                'times' => 1,
                'args'  => [ $style_handle, $style_src, [], $version ],
            ]
        );

        // Expect wp_enqueue_script to be called
        \WP_Mock::userFunction(
            'wp_enqueue_script',
            [
                'times' => 1,
                'args'  => [ $script_handle, $script_src, [ 'jquery' ], $version, true ],
            ]
        );

        // Expect wp_localize_script to be called
        \WP_Mock::userFunction(
            'wp_localize_script',
            [
                'times' => 1,
                'args'  => [
                    $script_handle,
                    'wpst_admin_params',
                    \Mockery::type( 'array' ), // We don't need to assert the exact array content here
                ],
            ]
        );

        // Call the method under test.
        $this->admin->enqueue_admin_assets( 'test-hook' );

        // Assertions are implicitly handled by WP_Mock's expectation checks on tearDown.
    }
}
