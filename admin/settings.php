<?php
/**
 * WP Plugin Starter admin loader.
 *
 * Loads the settings screen, the Read Me tab and the Plugins screen notes
 * for replaced plugins, then the plugin's own admin parts
 * (WPStarter_Setup::admin()). Included from the main plugin file for
 * admin requests only.
 *
 * @package WPStarter
 */

if (!defined('ABSPATH')) {
    exit;
}

$wpstarter_admin_files = array(
    'admin/data/readme.php',
    'admin/includes/class-settings-manager.php',
    'admin/includes/class-readme-manager.php',
    'admin/includes/class-admin-manager.php',
    'admin/includes/class-replaced-plugins.php',
);

foreach ($wpstarter_admin_files as $wpstarter_file) {
    require_once WPSTARTER_DIR . $wpstarter_file;
}
unset($wpstarter_admin_files, $wpstarter_file);

WPStarter_Admin_Manager::init();
WPStarter_Replaced_Plugins::init();
WPStarter_Setup::admin();
