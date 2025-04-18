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
	 * Enqueues admin-specific scripts and styles.
	 *
	 * This method is hooked into 'admin_enqueue_scripts'. It checks if the current
	 * screen is relevant to the plugin before enqueueing assets.
	 *
	 * @phpcs:ignore Generic.CodeAnalysis.UnusedFunctionParameter.Found
	 * @param string $hook_suffix The hook suffix of the current admin page.
	 */
	public function enqueue_admin_assets( string $hook_suffix ): void {

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
