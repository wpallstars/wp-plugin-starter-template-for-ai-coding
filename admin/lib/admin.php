<?php
/**
 * Admin functionality
 *
 * @package WPALLSTARS\PluginStarterTemplate
 */

namespace WPALLSTARS\PluginStarterTemplate\Admin;

use WPALLSTARS\PluginStarterTemplate\Core;

/**
 * Admin class
 */
class Admin {

	/**
	 * Core instance
	 *
	 * @var Core
	 */
	private $core;

	/**
	 * Constructor
	 *
	 * @param Core $core Core instance.
	 */
	public function __construct( $core ) {
		$this->core = $core;
		add_action( 'admin_enqueue_scripts', [ $this, 'enqueue_admin_assets' ] );
	}

	/**
	 * Initialize admin
	 */
	public function init() {
		// Initialize admin
	}

	/**
	 * Enqueue admin assets
	 *
	 * @param string $hook Current admin page.
	 */
	public function enqueue_admin_assets( $hook ) {
		wp_enqueue_style(
			'wpst-admin-styles',
			WPST_PLUGIN_URL . 'assets/css/admin.css',
			[],
			WPST_VERSION
		);

		wp_enqueue_script(
			'wpst-admin-scripts',
			WPST_PLUGIN_URL . 'assets/js/admin.js',
			[ 'jquery' ],
			WPST_VERSION,
			true
		);

		wp_localize_script(
			'wpst-admin-scripts',
			'wpstData',
			[
				'ajaxUrl' => admin_url( 'admin-ajax.php' ),
				'nonce'   => wp_create_nonce( 'wpst-admin-nonce' ),
				'strings' => [
					'success' => esc_html__( 'Success!', 'wp-plugin-starter-template' ),
					'error'   => esc_html__( 'Error!', 'wp-plugin-starter-template' ),
				],
			]
		);
	}
}
