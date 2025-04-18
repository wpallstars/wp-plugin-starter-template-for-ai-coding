<?php
/**
 * Main plugin class
 *
 * @package WPALLSTARS\PluginStarterTemplate
 */

namespace WPALLSTARS\PluginStarterTemplate;

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
	 * Plugin file
	 *
	 * @var string
	 */
	private $plugin_file;

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
	public function __construct( $plugin_file, $version ) {
		$this->plugin_file = $plugin_file;
		$this->version     = $version;
		$this->core        = new Core();
	}

	/**
	 * Initialize the plugin
	 */
	public function init() {
		// Initialize plugin
	}
}
