<?php
/**
 * Remove WP Plugin Starter's settings and caches on uninstall (every site on
 * multisite). Add every option, post meta, user meta, transient, cron hook
 * and file a feature stores (STANDARDS.md → Structure).
 *
 * @package WPStarter
 */

if (!defined('WP_UNINSTALL_PLUGIN')) {
    exit;
}

/**
 * Delete the plugin's options and transients for the current site.
 */
function wpstarter_uninstall_site() {
    global $wpdb;

    delete_option('wpstarter_options');
    delete_option('wpstarter_db_version');

    $patterns = array('_transient_wpstarter_', '_transient_timeout_wpstarter_');
    foreach ($patterns as $pattern) {
        // phpcs:ignore WordPress.DB.DirectDatabaseQuery -- one-off cleanup of our transients.
        $wpdb->query($wpdb->prepare("DELETE FROM {$wpdb->options} WHERE option_name LIKE %s", $wpdb->esc_like($pattern) . '%'));
    }
}

if (is_multisite()) {
    foreach (get_sites(array('fields' => 'ids', 'number' => 0)) as $wpstarter_site_id) {
        switch_to_blog($wpstarter_site_id);
        wpstarter_uninstall_site();
        restore_current_blog();
    }
} else {
    wpstarter_uninstall_site();
}

// Hidden "WP Plugin Starter can do the job of these plugins" lines.
delete_metadata('user', 0, 'wpstarter_replaced_plugins_hidden', '', true);

// Latest GitHub releases (the shared GitHub updater). Only a cache: another
// plugin's copy asks again.
delete_site_transient('wpallstars_github_releases');
