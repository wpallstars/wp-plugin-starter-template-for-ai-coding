<?php
/**
 * Core functionality for the plugin
 *
 * @package WPALLSTARS\PluginStarterTemplate
 */

namespace WPALLSTARS\PluginStarterTemplate;

/**
 * Core class
 */
class Core {

    /**
     * Plugin version
     *
     * @var string
     */
    private $version;

    /**
     * Constructor
     *
     * @param string $version Plugin version.
     */
    public function __construct( $version = '' ) {
        // Initialize hooks.
        $this->version = $version;
    }

    /**
     * Example method to filter content
     *
     * @param string $content The content to filter.
     * @return string The filtered content.
     */
    public function filter_content( $content ) {
        return $content;
    }

    /**
     * Get the plugin version
     *
     * @return string The plugin version.
     */
    public function get_plugin_version() {
        return $this->version;
    }
}
