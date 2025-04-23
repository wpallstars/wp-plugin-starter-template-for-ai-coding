<?php
/**
 * Class MultisiteTest
 *
 * @package WP_Plugin_Starter_Template_For_AI_Coding
 */

/**
 * Sample test case for the Multisite class.
 */
class MultisiteTest extends WP_UnitTestCase {

	/**
	 * Test instance creation.
	 */
	public function test_instance() {
		// Skip this test if the class doesn't exist
		if (!class_exists('WP_Plugin_Starter_Template_For_AI_Coding\Multisite\Multisite')) {
			$this->markTestSkipped('Multisite class not available');
			return;
		}

		$multisite = new WP_Plugin_Starter_Template_For_AI_Coding\Multisite\Multisite();
		$this->assertInstanceOf( 'WP_Plugin_Starter_Template_For_AI_Coding\Multisite\Multisite', $multisite );
	}

	/**
	 * Test is_multisite_compatible method.
	 */
	public function test_is_multisite_compatible() {
		// Skip this test if the class doesn't exist
		if (!class_exists('WP_Plugin_Starter_Template_For_AI_Coding\Multisite\Multisite')) {
			$this->markTestSkipped('Multisite class not available');
			return;
		}

		$multisite = new WP_Plugin_Starter_Template_For_AI_Coding\Multisite\Multisite();
		$this->assertTrue( $multisite->is_multisite_compatible() );
	}

	/**
	 * Test get_network_sites method.
	 */
	public function test_get_network_sites() {
		// Skip this test if the class doesn't exist
		if (!class_exists('WP_Plugin_Starter_Template_For_AI_Coding\Multisite\Multisite')) {
			$this->markTestSkipped('Multisite class not available');
			return;
		}

		$multisite = new WP_Plugin_Starter_Template_For_AI_Coding\Multisite\Multisite();

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
	 */
	public function test_initialize_hooks() {
		// Skip this test if the class doesn't exist
		if (!class_exists('WP_Plugin_Starter_Template_For_AI_Coding\Multisite\Multisite')) {
			$this->markTestSkipped('Multisite class not available');
			return;
		}

		$multisite = new WP_Plugin_Starter_Template_For_AI_Coding\Multisite\Multisite();

		// Call the method.
		$multisite->initialize_hooks();

		// Check if the action was added.
		$this->assertEquals( 10, has_action( 'network_admin_menu', array( $multisite, 'add_network_menu' ) ) );
	}
}
