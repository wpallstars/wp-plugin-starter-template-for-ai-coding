<?php
/**
 * Plugin Name: WordPress Plugin Starter Template
 * Plugin URI: https://www.wpallstars.com
 * Description: A comprehensive starter template for WordPress plugins with best practices for AI-assisted development.
 * Version: 0.1.13
 * Author: Your Name & The WPALLSTARS Team
 * Author URI: https://www.wpallstars.com
 * License: GPL-2.0+
 * License URI: http://www.gnu.org/licenses/gpl-2.0.txt
 * Text Domain: wp-plugin-starter-template
 * Domain Path: /languages
 * GitHub Plugin URI: wpallstars/wp-plugin-starter-template-for-ai-coding
 * GitHub Branch: main
 * Primary Branch: main
 * Release Branch: main
 * Release Asset: true
 * Requires at least: 5.0
 * Requires PHP: 7.4
 * Update URI: https://github.com/wpallstars/wp-plugin-starter-template-for-ai-coding
 *
 * Gitea Plugin URI: https://gitea.wpallstars.com/wpallstars/wp-plugin-starter-template-for-ai-coding
 * Gitea Branch: main
 * Gitea Languages: languages
 *
 * @package WPALLSTARS\PluginStarterTemplate
 */

// If this file is called directly, abort.
if ( ! defined( 'WPINC' ) ) {
    die;
}

// Define plugin constants
define( 'WP_PLUGIN_STARTER_TEMPLATE_FILE', __FILE__ );
define( 'WP_PLUGIN_STARTER_TEMPLATE_PATH', plugin_dir_path( __FILE__ ) );
define( 'WP_PLUGIN_STARTER_TEMPLATE_URL', plugin_dir_url( __FILE__ ) );
define( 'WP_PLUGIN_STARTER_TEMPLATE_VERSION', '0.1.13' );

// Load the main plugin class.
require_once WP_PLUGIN_STARTER_TEMPLATE_PATH . 'includes/class-plugin.php';

// Plugin is multisite compatible - see .wiki/Testing-Framework.md for testing instructions

// Initialize the plugin and store the instance in a global variable.
$wpst_plugin = new WPALLSTARS\PluginStarterTemplate\Plugin( __FILE__, WP_PLUGIN_STARTER_TEMPLATE_VERSION );

// Initialize the plugin.
$wpst_plugin->init();
