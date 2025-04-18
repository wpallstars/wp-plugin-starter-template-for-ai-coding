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
class AdminTest extends WP_Mock\Tools\TestCase {

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
     * Set up test environment
     */
    public function setUp(): void {
        parent::setUp();
        
        // Set up mocks
        WP_Mock::setUp();
        
        // Mock Core class
        $this->core = $this->createMock(Core::class);
        
        // Set up WordPress function mocks
        WP_Mock::userFunction('add_action', [
            'times' => 1,
            'args' => ['admin_enqueue_scripts', \WP_Mock\Functions::type('array')],
        ]);
        
        // Create instance of Admin class
        $this->admin = new Admin($this->core);
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
     * Test enqueue_admin_assets
     */
    public function test_enqueue_admin_assets() {
        // Set up WordPress function mocks
        WP_Mock::userFunction('wp_enqueue_style', [
            'times' => 1,
            'args' => ['wpst-admin-styles', \WP_Mock\Functions::type('string'), [], \WP_Mock\Functions::type('string')],
        ]);
        
        WP_Mock::userFunction('wp_enqueue_script', [
            'times' => 1,
            'args' => ['wpst-admin-scripts', \WP_Mock\Functions::type('string'), ['jquery'], \WP_Mock\Functions::type('string'), true],
        ]);
        
        WP_Mock::userFunction('wp_localize_script', [
            'times' => 1,
            'args' => ['wpst-admin-scripts', 'wpstData', \WP_Mock\Functions::type('array')],
        ]);
        
        WP_Mock::userFunction('esc_html__', [
            'times' => 2,
            'args' => [\WP_Mock\Functions::type('string'), 'wp-plugin-starter-template'],
            'return' => 'Translated string',
        ]);
        
        WP_Mock::userFunction('admin_url', [
            'times' => 1,
            'args' => ['admin-ajax.php'],
            'return' => 'http://example.org/wp-admin/admin-ajax.php',
        ]);
        
        WP_Mock::userFunction('wp_create_nonce', [
            'times' => 1,
            'args' => ['wpst-admin-nonce'],
            'return' => '1234567890',
        ]);
        
        // Call the method
        $this->admin->enqueue_admin_assets('plugins.php');
        
        // If we get here, the test passed
        $this->assertTrue(true);
    }
}
