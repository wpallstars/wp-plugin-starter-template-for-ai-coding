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
    private string $version;

    /**
     * Constructor
     *
     * @param string $version Plugin version.
     */
    public function __construct( string $version = '' ) {
        // Initialize hooks.
        $this->version = $version;
    }

    /**
     * Example method to filter content
     *
     * @param string $content The content to filter.
     * @return string The filtered content.
     */
    public function filter_content( string $content ): string {
        return $content;
    }

    /**
     * Get the plugin version
     *
     * @return string The plugin version.
     */
    public function get_plugin_version(): string {
        return $this->version;
    }
}
