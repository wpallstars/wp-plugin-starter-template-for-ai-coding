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
		$this->core = $core;
		$this->initialize_hooks();
	}

	/**
	 * Initializes WordPress hooks.
	 */
	private function initialize_hooks() {
		\add_action( 'admin_enqueue_scripts', array( $this, 'enqueue_admin_assets' ) );
	}

	/**
	 * Enqueues admin scripts and styles.
	 *
	 * @param string $hook_suffix The current admin page.
	 * @phpcs:ignore WordPress.CodeAnalysis.UnusedFunctionParameter.Found
	 *
	 */
	public function enqueue_admin_assets( $hook_suffix ) {
		// Enqueue admin styles.
		\wp_enqueue_style(
			'wpst-admin-style',
			'path/to/admin/css/admin-styles.css',
			array(), // Dependencies.
			$this->core->get_plugin_version() // Version.
		);

		// Enqueue admin scripts.
		\wp_enqueue_script(
			'wpst-admin-script',
			'path/to/admin/js/admin-scripts.js',
			array( 'jquery' ),
			$this->core->get_plugin_version(), // Version.
			true
		);

		// Localize script.
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
