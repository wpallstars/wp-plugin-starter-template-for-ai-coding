<?php
/**
 * Shared licensed updates: registers this copy.
 *
 * Every wpallstars plugin and theme made from the starters carries a copy of
 * includes/wpallstars-licence/. Each copy registers its version here when its
 * plugin or theme loads; on after_setup_theme (so themes' copies count too)
 * only the newest copy loads, once, and serves every installed plugin or
 * theme sold through the wpallstars.com shop: those whose header says
 * `Update URI: https://www.wpallstars.com/` and names the shop's product with
 * `Licence Item: <id>`.
 *
 * What it does: an administrator (or `wp wpallstars licence activate`)
 * enters each product's licence key once for the site, or for the whole
 * network on multisite. WordPress is then offered each new release as a
 * normal update, with the zip downloaded from the shop for a licensed site
 * only. The licence gates updates only: a product without one keeps working.
 *
 * The starter holds the master copy. Change it there, raise the version
 * below with every change, then copy it to each plugin and theme
 * (scripts/sync-core.sh). Products never call the class: another product's
 * newer or older copy may be the one that runs.
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 * SPDX-FileCopyrightText: 2026 Marcus Quinn
 * Additional terms (GPL-3.0 section 7(b)): ATTRIBUTION.txt
 * Provenance: wpas-e4502af0f07e8a92. Copies, even of part, keep these lines.
 *
 * @package WPStarter
 */

if (!defined('ABSPATH')) {
    exit;
}

if (!isset($GLOBALS['wpallstars_licence']) || !is_array($GLOBALS['wpallstars_licence'])) {
    $GLOBALS['wpallstars_licence'] = array(); // phpcs:ignore WordPress.NamingConventions.PrefixAllGlobals -- Shared across wpallstars products; see STANDARDS.md, Licensed updates.
}
// Version of this copy => its class file.
$GLOBALS['wpallstars_licence']['1.0.0'] = __DIR__ . '/class-wpallstars-licence.php'; // phpcs:ignore WordPress.NamingConventions.PrefixAllGlobals -- Shared across wpallstars products; see STANDARDS.md, Licensed updates.

if (!function_exists('wpallstars_licence_load')) {
    /**
     * Load the newest registered copy (after_setup_theme).
     */
    function wpallstars_licence_load() { // phpcs:ignore WordPress.NamingConventions.PrefixAllGlobals -- Shared across wpallstars products; see STANDARDS.md, Licensed updates.
        if (class_exists('WPAllStars_Licence', false) || empty($GLOBALS['wpallstars_licence'])) {
            return;
        }
        $copies = (array) $GLOBALS['wpallstars_licence'];
        uksort($copies, 'version_compare');
        $file = (string) end($copies);
        if (is_readable($file)) {
            require_once $file;
            WPAllStars_Licence::load();
        }
    }
    // Every plugin's main file and the theme's functions.php have run by
    // then, so every copy is registered.
    add_action('after_setup_theme', 'wpallstars_licence_load', 1);
}
