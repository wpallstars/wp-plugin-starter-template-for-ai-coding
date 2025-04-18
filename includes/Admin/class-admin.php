<?php
/**
 * Admin area functionality for the plugin.
 *
 * @package WPALLSTARS\PluginStarterTemplate\Admin
 */

namespace WPALLSTARS\PluginStarterTemplate\Admin;

use WPALLSTARS\PluginStarterTemplate\Core;

/**
 * Admin class responsible for admin-specific hooks and functionality.
 */
class Admin {

	/**
	 * Core plugin class instance.
	 *
	 * @var Core
	 */
	private $core;

	/**
	 * Constructor.
	 *
	 * @param Core $core Core instance.
	 */
	public function __construct( Core $core ) {
		error_log('Admin::__construct called');
		$this->core = $core;
		$this->initialize_hooks();
	}

	/**
	 * Initializes WordPress hooks.
	 */
	private function initialize_hooks() {
		error_log('Admin::initialize_hooks called');
		\add_action( 'admin_enqueue_scripts', array( $this, 'enqueue_admin_assets' ) );
	}

	/**
	 * Enqueues admin-specific assets.
	 *
	 * @param string $hook_suffix The current admin page.
	 */
	public function enqueue_admin_assets( $hook_suffix ) {
		// Admin assets enqueue logic will go here.
		// The test mocks wp_enqueue_style, wp_enqueue_script, etc.
	}
}
