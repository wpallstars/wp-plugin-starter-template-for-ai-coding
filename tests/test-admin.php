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
     * Set up test environment
     */
    public function setUp() {
        parent::setUp();

        // Set up mocks
        WP_Mock::setUp();

        // Mock Core class
        $this->core = $this->createMock(Core::class);

        // Instantiate the class under test
        $this->admin = new Admin($this->core);
    }

    /**
     * Tear down test environment
     */
    public function tearDown() {
        WP_Mock::tearDown();
        parent::tearDown();
    }

    /**
     * Test constructor
     */
    public function test_constructor() {
        // Verify that the constructor initializes hooks
        $this->assertInstanceOf(Admin::class, $this->admin);
        $this->assertTrue(WP_Mock::onActionAdded('admin_enqueue_scripts'));

    }

    /**
     * Test enqueue_admin_assets method
     */
    public function test_enqueue_admin_assets() {
        // Set up mocks for this specific test
        WP_Mock::userFunction('wp_enqueue_style', [
            'times' => 1,
            'args' => ['wpst-admin-style', 'path/to/admin/css/admin-styles.css'],
        ]);
        WP_Mock::userFunction('wp_enqueue_script', [
            'times' => 1,
            'args' => ['wpst-admin-script', 'path/to/admin/js/admin-scripts.js', array('jquery'), null, true],
        ]);
        WP_Mock::userFunction('wp_localize_script', [
            'times' => 1,
            'args' => [
                'wpst-admin-script',
                'wpst_admin_params',
                array(
                    'ajax_url' => 'http://example.org/wp-admin/admin-ajax.php',
                    'nonce' => '1234567890',
                ),
            ],
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

        // Call the method under test
        $this->admin->enqueue_admin_assets('plugins.php');

        // WP_Mock::tearDown() in the main tearDown method will verify the expectations
        // We can add an assertion here to make the test explicit
        $this->assertTrue(true);
    }
}
