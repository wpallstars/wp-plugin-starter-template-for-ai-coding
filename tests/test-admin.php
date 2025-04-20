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
     *
     * This test is currently disabled due to issues with mocking.
     * TODO: Fix this test in a future update.
     */
    // public function test_enqueue_admin_assets(): void
    // {
    //     // Test implementation will be added in a future update
    // }
}
