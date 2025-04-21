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
    private $core;

    /**
     * Admin instance
     *
     * @var Admin
     */
    private $admin;

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
    private $version;

    /**
     * Constructor
     *
     * @param string $plugin_file Main plugin file path.
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
    public function init() {
        // Initialization logic goes here.
    }
}
