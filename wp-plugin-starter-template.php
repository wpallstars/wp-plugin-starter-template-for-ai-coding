<?php
/**
 * Plugin Name:       WP Plugin Starter
 * Plugin URI:        https://github.com/wpallstars/wp-plugin-starter-template-for-ai-coding
 * Description:       A clean start for a WordPress plugin: a settings screen, a Read Me tab, updates from GitHub and release scripts, ready for your features.
 * Version:           1.0.14
 * Requires at least: 6.2
 * Requires PHP:      7.4
 * Author:            Marcus Quinn
 * Author URI:        https://www.wpallstars.com/
 * License:           GPL-2.0-or-later
 * License URI:       https://www.gnu.org/licenses/gpl-2.0.html
 * Text Domain:       wp-plugin-starter-template
 * GitHub Plugin URI: wpallstars/wp-plugin-starter-template-for-ai-coding
 * Primary Branch:    main
 * Release Asset:     true
 *
 * Copyright (C) 2026 Marcus Quinn
 *
 * WP Plugin Starter is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 2 of the License, or
 * any later version.
 *
 * WP Plugin Starter is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 * GNU General Public License for more details.
 *
 * @package WPStarter
 */

if (!defined('ABSPATH')) {
    exit;
}

define('WPSTARTER_VERSION', '1.0.14');
define('WPSTARTER_FILE', __FILE__);
define('WPSTARTER_DIR', plugin_dir_path(__FILE__));
define('WPSTARTER_URL', plugin_dir_url(__FILE__));

require_once WPSTARTER_DIR . 'includes/class-wpstarter.php';
WPStarter::load();
register_deactivation_hook(__FILE__, array('WPStarter', 'deactivate'));

// Translations load just-in-time from WordPress.org language packs (WP 4.6+).
