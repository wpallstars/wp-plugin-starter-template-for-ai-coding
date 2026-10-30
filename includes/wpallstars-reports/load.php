<?php
/**
 * Shared problem reports: registers this copy.
 *
 * Every wpallstars plugin and theme made from the starters carries a copy of
 * includes/wpallstars-reports/. Each copy registers its version here when its
 * plugin or theme loads; on after_setup_theme (so themes' copies count too)
 * only the newest copy loads, once, and serves every product that lists
 * itself through the wpallstars_report_products filter.
 *
 * What it does: a site's AI assistant drafts a problem report or an
 * improvement for one of those products (the wpallstars/report-problem
 * ability or `wp wpallstars report create`), and a site administrator
 * reviews, edits and sends it in Tools → Report a problem: by email with the
 * site's own mailer to a private product's support address, or as a
 * prefilled GitHub issue for a public one. Nothing leaves the site before
 * an administrator sends it.
 *
 * The starter holds the master copy. Change it there, raise the version
 * below with every change, then copy it to each plugin and theme
 * (scripts/sync-core.sh). Products change what it does only through its
 * filters and wpallstars_report_url(), never by calling the class: another
 * product's newer or older copy may be the one that runs.
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

if (!isset($GLOBALS['wpallstars_reports']) || !is_array($GLOBALS['wpallstars_reports'])) {
    $GLOBALS['wpallstars_reports'] = array();
}
// Version of this copy => its class file.
$GLOBALS['wpallstars_reports']['1.0.0'] = __DIR__ . '/class-wpallstars-reports.php';

if (!function_exists('wpallstars_reports_load')) {
    /**
     * Load the newest registered copy (after_setup_theme).
     */
    function wpallstars_reports_load() {
        if (class_exists('WPAllStars_Reports', false) || empty($GLOBALS['wpallstars_reports'])) {
            return;
        }
        $copies = (array) $GLOBALS['wpallstars_reports'];
        uksort($copies, 'version_compare');
        $file = (string) end($copies);
        if (is_readable($file)) {
            require_once $file;
            WPAllStars_Reports::load();
        }
    }
    // Every plugin's main file and the theme's functions.php have run by
    // then, so every copy is registered.
    add_action('after_setup_theme', 'wpallstars_reports_load', 1);
}

if (!function_exists('wpallstars_report_url')) {
    /**
     * The Report a problem screen (Tools), for one product or all of them.
     * The same in every copy, so products may call it.
     *
     * @param string $product Product slug (plugin folder or theme stylesheet); empty for all.
     * @return string
     */
    function wpallstars_report_url($product = '') {
        $args = array('page' => 'wpallstars-report');
        if ('' !== (string) $product) {
            $args['product'] = (string) $product;
        }
        return add_query_arg($args, admin_url('tools.php'));
    }
}
