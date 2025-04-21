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
    private function initialize_hooks(): void {
        \add_action( 'admin_enqueue_scripts', array( $this, 'enqueue_admin_assets' ) );
    }

    /**
     * Enqueues admin-specific scripts and styles.
     *
     * This method is hooked into 'admin_enqueue_scripts'. It checks if the current
     * screen is relevant to the plugin before enqueueing assets.


     *
	 * @phpcs:ignore Generic.CodeAnalysis.UnusedFunctionParameter.Found
     */
    public function enqueue_admin_assets(): void {

		// @phpcs:disable WordPress.Security.NonceVerification.Recommended
		// @phpcs:disable WordPress.Security.NonceVerification.Missing
        $page = filter_input( INPUT_GET, 'page', FILTER_SANITIZE_FULL_SPECIAL_CHARS );
        if ( ! $page || 'wp_plugin_starter_template_settings' !== $page ) {
            return;
        }
		// @phpcs:enable

        // Get the plugin version.
        $pluginVersion = $this->core->get_plugin_version();

        // Enqueue styles.
        \wp_enqueue_style(
            'wpst-admin-styles',
            \plugin_dir_url( __FILE__ ) . '../../admin/css/admin-styles.css',
            array(), // Dependencies.
            $pluginVersion // Version.
        );

        // Enqueue admin scripts.
        \wp_enqueue_script(
            'wpst-admin-script',
            \plugin_dir_url( __FILE__ ) . '../../admin/js/admin-scripts.js',
            array( 'jquery' ),
            $pluginVersion, // Version.
            true
        );

        // TODO: Implement localization when mocking is fixed (Issue #1).
        // This will include ajax_url and nonce for security.
    }
}
