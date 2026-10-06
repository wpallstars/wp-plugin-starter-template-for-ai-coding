<?php
/**
 * What makes this plugin WP Plugin Starter: its features, settings tabs,
 * links, settings history and the helpers only it needs.
 *
 * The other files in includes/ and admin/ that the starter plugin also has
 * (the feature registry, settings store, base feature and admin screen)
 * read this class and differ from the starter's only in names. Keep
 * anything that only this plugin needs here, in features or in its own
 * files loaded from here.
 *
 * The starter has no features yet, so its settings screen shows the first
 * settings tab with "No settings yet" and the Read Me tab. Add a feature:
 * STANDARDS.md → Structure and README.md → Developers.
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 * SPDX-FileCopyrightText: 2026 Marcus Quinn
 * Additional terms (GPL-3.0 section 7(b)): ATTRIBUTION.txt
 *
 * @package WPStarter
 * @since 1.0.0
 */

if (!defined('ABSPATH')) {
    exit;
}

final class WPStarter_Setup {

    /**
     * Built-in features, in the order their cards appear within each tab.
     * Each lives in includes/features/class-{lowercase-hyphenated-name}.php,
     * for example WPStarter_Example in class-wpstarter-example.php.
     */
    const FEATURES = array();

    /**
     * Features that some builds leave out, loaded only when their file is
     * present (for example one listed in .distignore-wporg).
     */
    const OPTIONAL_FEATURES = array();

    /**
     * Settings version. WPStarter_Settings::maybe_migrate() runs
     * migrate() below and every feature's migrate() once per version.
     * After a release, bump it for a new or changed import and add a line.
     *
     * v1: first version.
     */
    const DB_VERSION = 1;

    /**
     * Renamed tab slugs, old => new. Settings that still use an old slug
     * land on the new tab, and old admin links open the new tab.
     */
    const RENAMED_TABS = array();

    /**
     * Slug of the plugin's own top-level menu (add_menu_page()), when it
     * has one: the settings screen is then Settings, the last item in that
     * menu, and not in WordPress's Settings menu. Empty: Settings → WP Plugin Starter.
     */
    const MENU_PARENT = '';

    /**
     * Links in the settings screen header; leave one out for no button.
     *
     * - source:  the plugin's code (its GitHub repository)
     * - support: where people report problems (the plugin's GitHub issues)
     * - donate:  where people can support the maker
     *
     * @return array<string,string>
     */
    public static function header_links() {
        return array(
            'source'  => 'https://github.com/wpallstars/wp-plugin-starter-template-for-ai-coding',
            'support' => 'https://github.com/wpallstars/wp-plugin-starter-template-for-ai-coding/issues',
            'donate'  => 'https://buymeacoffee.com/marcusquinn',
        );
    }

    /**
     * Load the plugin's own helpers, before the features.
     */
    public static function load() {
    }

    /**
     * Register the helpers' hooks, after the settings store's.
     */
    public static function init() {
    }

    /**
     * Imports that belong to no feature, run once per DB_VERSION before
     * the features' own (for example settings from the plugin's earlier
     * names). Never write or delete other plugins' options.
     *
     * @param array $options      Stored settings (raw, without defaults).
     * @param int   $from_version Stored settings version before this upgrade.
     * @return array
     */
    public static function migrate(array $options, $from_version) {
        unset($from_version);
        return $options;
    }

    /**
     * Settings tabs, in navigation order. A tab shows only when a setting
     * uses it; with no settings at all, the first one shows, empty.
     *
     * @return array<string,array{label:string,description:string}>
     */
    public static function settings_tabs() {
        return array(
            'general' => array(
                'label'       => __('General', 'wp-plugin-starter-template'),
                'description' => __('WP Plugin Starter\'s settings appear here as features are added.', 'wp-plugin-starter-template'),
            ),
        );
    }

    /**
     * Admin requests: load and start the plugin's own admin parts (other
     * tabs with the wpstarter_admin_tabs filter, scripts with the
     * wpstarter_admin_enqueue action).
     */
    public static function admin() {
    }
}
