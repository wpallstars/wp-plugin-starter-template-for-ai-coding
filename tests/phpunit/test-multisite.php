<?php
/**
 * Class MultisiteTest
 *
 * @package WP_Plugin_Starter_Template_For_AI_Coding
 * @group wordpress
 */

use WP_Plugin_Starter_Template_For_AI_Coding\Multisite\Multisite;

// Skip this test file if WordPress test framework is not available.
if ( ! class_exists( 'WP_UnitTestCase' ) ) {
    return; // phpcs:ignore -- Early return is intentional.
}

/**
 * Multisite class name constant for testing.
 */
const MULTISITE_CLASS = 'WP_Plugin_Starter_Template_For_AI_Coding\Multisite\Multisite';

/**
 * Skip message constant.
 */
const MULTISITE_SKIP_MSG = 'Multisite class not available';

/**
 * Sample test case for the Multisite class.
 */
class MultisiteTest extends WP_UnitTestCase {

    /**
     * Test instance creation.
     *
     * @return void
     */
    public function test_instance() {
        if ( ! class_exists( MULTISITE_CLASS ) ) {
            $this->markTestSkipped( MULTISITE_SKIP_MSG );
        }

        $multisite = new Multisite();
        $this->assertInstanceOf( MULTISITE_CLASS, $multisite );
    }

    /**
     * Test is_multisite_compatible method.
     *
     * @return void
     */
    public function test_is_multisite_compatible() {
        if ( ! class_exists( MULTISITE_CLASS ) ) {
            $this->markTestSkipped( MULTISITE_SKIP_MSG );
        }

        $multisite = new Multisite();
        $this->assertTrue( $multisite->is_multisite_compatible() );
    }

    /**
     * Test get_network_sites method.
     *
     * @return void
     */
    public function test_get_network_sites() {
        if ( ! class_exists( MULTISITE_CLASS ) ) {
            $this->markTestSkipped( MULTISITE_SKIP_MSG );
        }

        $multisite = new Multisite();

        // Mock the get_sites function if we're not in a multisite environment.
        if ( ! function_exists( 'get_sites' ) ) {
            $this->assertEquals( array(), $multisite->get_network_sites() );
        } else {
            $sites = $multisite->get_network_sites();
            $this->assertIsArray( $sites );
        }
    }

    /**
     * Test initialize_hooks method.
     *
     * @return void
     */
    public function test_initialize_hooks() {
        if ( ! class_exists( MULTISITE_CLASS ) ) {
            $this->markTestSkipped( MULTISITE_SKIP_MSG );
        }

        $multisite = new Multisite();

        // Call the method.
        $multisite->initialize_hooks();

        // Check if the action was added.
        $this->assertEquals( 10, has_action( 'network_admin_menu', array( $multisite, 'add_network_menu' ) ) );
    }
}
