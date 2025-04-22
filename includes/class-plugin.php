<?php
/**
 * Main plugin class
 *
 * @package WPALLSTARS\PluginStarterTemplate
 */

namespace WPALLSTARS\PluginStarterTemplate;

use WPALLSTARS\PluginStarterTemplate\Admin\Admin;

/**
 * Plugin class
 */
class Plugin {

    /**
     * Core instance
     *
     * @var Core
     */
    private Core $core;

    /**
     * Admin instance
     *
     * @var Admin
     */
    private Admin $admin;

    /**
     * Plugin file path
     *
     * @var string
     */
    private string $pluginFile;

    /**
     * Plugin version
     *
     * @var string
     */
    private string $version;

    /**
     * Constructor
     *
     * @param string $pluginFile Main plugin file path.
     * @param string $version Plugin version.
     */
    public function __construct( string $pluginFile, string $version ) {
        $this->pluginFile = $pluginFile;
        $this->version = $version;
        $this->core = new Core( $version );
        $this->admin = new Admin( $this->core );
    }

    /**
     * Initialize the plugin
     */
    public function init(): void {
        // Register hooks and filters.
        add_action( 'plugins_loaded', array( $this, 'load_textdomain' ) );

        // Initialize any other plugin functionality.
    }

    /**
     * Load plugin textdomain.
     *
     * @return void
     */
    public function load_textdomain(): void {
        load_plugin_textdomain(
            'wp-plugin-starter-template',
            false,
            dirname( plugin_basename( $this->pluginFile ) ) . '/languages/'
        );
    }

    /**
     * Get the plugin version.
     *
     * @return string The plugin version.
     */
    public function getVersion(): string {
        return $this->version;
    }

    /**
     * Get the admin instance.
     *
     * @return Admin The admin instance.
     */
    public function getAdmin(): Admin {
        return $this->admin;
    }
}
