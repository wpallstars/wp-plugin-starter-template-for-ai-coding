<?php
/**
 * Shared GitHub updater: registers this copy.
 *
 * Every plugin made from the starter carries a copy of includes/github-updater/.
 * Each copy registers its version here when its plugin loads; on
 * plugins_loaded only the newest copy loads, once, and serves every installed
 * plugin with a `GitHub Plugin URI` header. So one update check covers all of
 * them, however many carry a copy.
 *
 * The WordPress.org build leaves this folder out (.distignore-wporg): plugins
 * hosted there may not install or update code from anywhere else.
 *
 * The starter holds the master copy. Change it there, raise the version
 * below with every change, then copy it to each plugin (scripts/sync-core.sh).
 * Plugins change what it does only through its filters, never by calling the
 * class: another plugin's newer or older copy may be the one that runs.
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 * SPDX-FileCopyrightText: 2026 Marcus Quinn
 * Additional terms (GPL-3.0 section 7(b)): ATTRIBUTION.txt
 *
 * @package WPStarter
 */

if (!defined('ABSPATH')) {
    exit;
}

if (!isset($GLOBALS['wpallstars_github_updater']) || !is_array($GLOBALS['wpallstars_github_updater'])) {
    $GLOBALS['wpallstars_github_updater'] = array();
}
// Version of this copy => its class file.
$GLOBALS['wpallstars_github_updater']['1.5.0'] = __DIR__ . '/class-wpallstars-github-updater.php';

if (!function_exists('wpallstars_github_updater_load')) {
    /**
     * Load the newest registered copy of the updater (plugins_loaded).
     */
    function wpallstars_github_updater_load() {
        if (class_exists('WPAllStars_GitHub_Updater', false) || empty($GLOBALS['wpallstars_github_updater'])) {
            return;
        }
        $copies = (array) $GLOBALS['wpallstars_github_updater'];
        uksort($copies, 'version_compare');
        $file = (string) end($copies);
        if (is_readable($file)) {
            require_once $file;
            WPAllStars_GitHub_Updater::load();
        }
    }
    // Every plugin's main file has run by then, so every copy is registered.
    add_action('plugins_loaded', 'wpallstars_github_updater_load', 1);
}
