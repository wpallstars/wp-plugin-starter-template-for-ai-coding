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
    private Core $core;

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
     */
    public function enqueue_admin_assets(): void {

		// @phpcs:disable WordPress.Security.NonceVerification.Recommended
		// @phpcs:disable WordPress.Security.NonceVerification.Missing
        // For production, use filter_input.
        $page = '';
        if ( defined( 'PHPUNIT_RUNNING' ) && PHPUNIT_RUNNING ) {
            // For testing, use $_GET directly.
            // phpcs:ignore WordPress.Security.ValidatedSanitizedInput.InputNotSanitized -- We're sanitizing with wp_unslash and validating later
            $page = isset( $_GET['page'] ) ? \wp_unslash( $_GET['page'] ) : '';
        }

        // Use filter_input for production environment.
        if ( empty( $page ) ) {
            $page = filter_input( INPUT_GET, 'page', FILTER_SANITIZE_FULL_SPECIAL_CHARS );
        }

        if ( ! $page || 'wp_plugin_starter_template_settings' !== $page ) {
            return;
        }
		// @phpcs:enable

        // Get the plugin version.
        $plugin_version = $this->core->get_plugin_version();

        // Enqueue styles.
        \wp_enqueue_style(
            'wpst-admin-styles',
            plugin_dir_url( dirname( __DIR__ ) ) . 'admin/css/admin-styles.css',
            array(), // Dependencies.
            $plugin_version // Version.
        );

        // Enqueue admin scripts.
        \wp_enqueue_script(
            'wpst-admin-script',
            plugin_dir_url( dirname( __DIR__ ) ) . 'admin/js/admin-scripts.js',
            array( 'jquery' ),
            $plugin_version, // Version.
            true
        );

        // Prepare data for localization.
        $data = array(
            'ajax_url' => \admin_url( 'admin-ajax.php' ),
            'nonce'    => \wp_create_nonce( 'wpst_admin_nonce' ),
        );

        // Localize the script with the data.
        \wp_localize_script(
            'wpst-admin-script',
            'wpst_admin_data',
            $data
        );
    }
}
