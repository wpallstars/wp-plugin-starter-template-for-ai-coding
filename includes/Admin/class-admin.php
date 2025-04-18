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
		// Enqueue admin styles
		\wp_enqueue_style(
			'wpst-admin-style',
			'path/to/admin/css/admin-styles.css'
		);

		// Enqueue admin scripts
		\wp_enqueue_script(
			'wpst-admin-script',
			'path/to/admin/js/admin-scripts.js',
			array( 'jquery' ),
			null,
			true
		);

		// Localize script
		\wp_localize_script(
			'wpst-admin-script',
			'wpst_admin_params',
			array(
				'ajax_url' => \admin_url( 'admin-ajax.php' ),
				'nonce'    => \wp_create_nonce( 'wpst-admin-nonce' ),
			)
		);
	}
}
