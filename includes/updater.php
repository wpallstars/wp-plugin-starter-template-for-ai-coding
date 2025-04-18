<?php
/**
 * Updater functionality for the plugin
 *
 * @package WPALLSTARS\PluginStarterTemplate
 */

namespace WPALLSTARS\PluginStarterTemplate;

/**
 * Updater class
 */
class Updater {

	/**
	 * Plugin file
	 *
	 * @var string
	 */
	private $plugin_file;

	/**
	 * Constructor
	 *
	 * @param string $plugin_file Main plugin file path.
	 */
	public function __construct($plugin_file) {
		$this->plugin_file = $plugin_file;
		$this->init();
	}

	/**
	 * Initialize the updater
	 */
	public function init() {
		add_filter('plugin_action_links_' . plugin_basename($this->plugin_file), array($this, 'add_update_source_link'));
		add_action('admin_post_wpst_update_source', array($this, 'handle_update_source'));
	}

	/**
	 * Add update source link to plugin actions
	 *
	 * @param array $links Plugin action links.
	 * @return array Modified plugin action links.
	 */
	public function add_update_source_link($links) {
		$update_source_link = '<a href="' . admin_url('admin-post.php?action=wpst_update_source&plugin=' . plugin_basename($this->plugin_file)) . '">' . esc_html__('Update Source', 'wp-plugin-starter-template') . '</a>';
		array_unshift($links, $update_source_link);
		return $links;
	}

	/**
	 * Handle update source selection
	 */
	public function handle_update_source() {
		// Handle update source selection.
	}
}
