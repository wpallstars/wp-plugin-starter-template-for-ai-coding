<?php
/**
 * Class CoreTest
 *
 * @package WPALLSTARS\PluginStarterTemplate
 */

use WPALLSTARS\PluginStarterTemplate\Core;
use WP_Mock\Tools\TestCase;
use WP_Mock;

/**
 * Core test case.
 */
class CoreTest extends TestCase {

    /**
     * Test instance
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

        // Create instance of Core class
        $this->core = new Core();
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
        $this->assertInstanceOf(Core::class, $this->core);
    }

    /**
     * Test example method
     */
    public function test_filter_content() {
        $content = 'Test content';

        // Test that filter_content returns the content
        $this->assertEquals($content, $this->core->filter_content($content));
    }
}
