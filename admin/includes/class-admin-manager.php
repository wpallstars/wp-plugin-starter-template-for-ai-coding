<?php
/**
 * WP Plugin Starter admin screen.
 *
 * Owns the settings screen: tab registry, page chrome and the admin
 * script and stylesheets. Its markup (header, navigation, panels) is in
 * WPStarter_Admin_Page; tab content is delegated to the manager classes.
 * Settings tabs and header links come from WPStarter_Setup; add other tabs
 * with the `wpstarter_admin_tabs` filter.
 *
 * The screen draws the active tab with the other tabs of its group
 * (page_tabs()), so the script switches between them without a reload.
 *
 * The screen is Settings → WP Plugin Starter, or Settings in the plugin's own
 * top-level menu when WPStarter_Setup::MENU_PARENT names that menu. Build
 * its links with page_url() or tab_url(), which follow where it is. The
 * plugin's own screens show the same header with enqueue_header() and
 * render_header().
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 * SPDX-FileCopyrightText: 2026 Marcus Quinn
 * Additional terms (GPL-3.0 section 7(b)): ATTRIBUTION.txt
 *
 * @package WPStarter
 * @since 0.2.0
 */

if (!defined('ABSPATH')) {
    exit;
}

class WPStarter_Admin_Manager {

    /** Menu/page slug. */
    const PAGE = 'wp-plugin-starter-template';

    /**
     * Hook suffix of the screen under Settings. In the plugin's own menu it
     * differs; hook() gives the one in use.
     */
    const HOOK = 'settings_page_' . self::PAGE;

    /**
     * Admin stylesheets and script, relative to the plugin folder. The
     * header stylesheet (colour tokens, the full-width screen and its
     * header) is also for the plugin's own screens; the settings one
     * depends on it.
     */
    const HEADER_CSS_FILE = 'admin/css/wpstarter-header.css';
    const CSS_FILE        = 'admin/css/wpstarter-admin.css';
    const JS_FILE         = 'admin/js/wpstarter-admin.js';

    /** Hook suffix WordPress gave the screen when it was registered. */
    private static $hook = '';

    /**
     * Register hooks (once).
     */
    public static function init() {
        // After the plugin's own top-level menu (priority 10), so Settings
        // is the last item in it.
        add_action('admin_menu', array(__CLASS__, 'register_admin_menu'), 20);
        add_action('admin_page_access_denied', array(__CLASS__, 'redirect_old_address'));
        add_action('admin_enqueue_scripts', array(__CLASS__, 'enqueue_assets'));
        add_filter('plugin_action_links_' . plugin_basename(WPSTARTER_FILE), array(__CLASS__, 'plugin_action_links'));
    }

    /**
     * Menu the screen is in: the plugin's own top-level menu
     * (WPStarter_Setup::MENU_PARENT), or Settings.
     *
     * @return string Menu slug.
     */
    public static function parent() {
        $constant = 'WPStarter_Setup::MENU_PARENT';
        $parent   = defined($constant) ? (string) constant($constant) : '';
        return '' === $parent ? 'options-general.php' : $parent;
    }

    /**
     * Admin file the screen's address uses.
     *
     * @return string
     */
    private static function screen_file() {
        return 'options-general.php' === self::parent() ? 'options-general.php' : 'admin.php';
    }

    /**
     * Address of the screen.
     *
     * @param array $args Extra query args.
     * @return string
     */
    public static function page_url(array $args = array()) {
        return add_query_arg(array_merge(array('page' => self::PAGE), $args), admin_url(self::screen_file()));
    }

    /**
     * Hook suffix of the screen, once registered.
     *
     * @return string
     */
    public static function hook() {
        return '' !== self::$hook ? self::$hook : self::HOOK;
    }

    /** Slug of the search results screen (not shown in the navigation). */
    const SEARCH = 'search';

    /**
     * Settings tabs, in navigation order (WPStarter_Setup::settings_tabs()).
     *
     * @return array<string,array{label:string,description:string}>
     */
    public static function settings_tabs() {
        return WPStarter_Setup::settings_tabs();
    }

    /**
     * Registered tabs. Settings tabs and Read Me preload: they are drawn
     * with the other tabs of their group (page_tabs()).
     *
     * @return array<string,array{label:string,group:string,render:callable,preload?:bool,capability?:string}>
     */
    public static function get_tabs() {
        $tabs = array();

        // Settings tabs without settings are hidden (they can be filled via
        // the schema filter). With no settings at all, the first tab shows
        // and says so, so a new plugin still has a settings screen.
        $settings_tabs = self::settings_tabs();
        $has_settings  = false;
        foreach (array_keys($settings_tabs) as $slug) {
            if (WPStarter_Settings::fields_for_tab($slug)) {
                $has_settings = true;
                break;
            }
        }
        foreach ($settings_tabs as $slug => $tab) {
            if ($has_settings && !WPStarter_Settings::fields_for_tab($slug)) {
                continue;
            }
            if (!$has_settings && $tabs) {
                break;
            }
            $tabs[$slug] = array(
                'label'   => $tab['label'],
                'group'   => 'settings',
                'preload' => true,
                'render'  => function () use ($slug, $tab) {
                    WPStarter_Settings_Manager::render_tab($slug, $tab['label'], $tab['description']);
                },
            );
        }

        $tabs += array(
            'readme' => array(
                'label'   => __('Read Me', 'wp-plugin-starter-template'),
                'group'   => 'about',
                'preload' => true,
                'render'  => array('WPStarter_Readme_Manager', 'display_tab_content'),
            ),
        );

        /**
         * Filter the admin tabs.
         *
         * @param array $tabs Tabs keyed by slug: label, group (settings|discover|about),
         *                    render callback, optional capability, optional
         *                    preload (true: drawn with the other tabs of its
         *                    group, so switching to it is instant; its script
         *                    must then work while its panel is hidden).
         */
        $tabs = (array) apply_filters('wpstarter_admin_tabs', $tabs);

        // Hide tabs the current user cannot use.
        return array_filter($tabs, function ($tab) {
            return empty($tab['capability']) || current_user_can($tab['capability']);
        });
    }

    /**
     * Active tab slug, falling back to the first registered tab.
     *
     * @return string
     */
    public static function get_active_tab() {
        // phpcs:ignore WordPress.Security.NonceVerification.Recommended -- read-only navigation.
        $tab = isset($_GET['tab']) ? sanitize_key(wp_unslash($_GET['tab'])) : '';
        if (self::SEARCH === $tab && '' !== self::search_query()) {
            return $tab;
        }

        $tabs = self::get_tabs();
        $tab  = WPStarter_Settings::resolve_tab($tab);
        if (!isset($tabs[$tab])) {
            $tab = (string) key($tabs);
        }
        return $tab;
    }

    /**
     * Tabs drawn on this page, the active one first: the active tab and the
     * other tabs of its group that preload. The script switches between
     * them without a reload; a link to any other tab loads its page. Search
     * results are drawn alone.
     *
     * @return string[]
     */
    public static function page_tabs() {
        $active = self::get_active_tab();
        $tabs   = self::get_tabs();
        $group  = isset($tabs[$active]['group']) ? (string) $tabs[$active]['group'] : '';
        if (self::SEARCH === $active || '' === $group) {
            return array($active);
        }
        $preload = array_filter($tabs, function ($tab, $slug) use ($active, $group) {
            return (string) $slug !== $active && !empty($tab['preload']) && isset($tab['group']) && $tab['group'] === $group;
        }, ARRAY_FILTER_USE_BOTH);
        return array_merge(array($active), array_map('strval', array_keys($preload)));
    }

    /**
     * Current settings search text.
     *
     * @return string
     */
    public static function search_query() {
        // phpcs:ignore WordPress.Security.NonceVerification.Recommended -- read-only search.
        $query = isset($_GET['s']) ? sanitize_text_field(wp_unslash($_GET['s'])) : '';
        return trim(function_exists('mb_substr') ? mb_substr($query, 0, 100) : substr($query, 0, 100));
    }

    /**
     * URL of a tab.
     *
     * @param string $tab  Tab slug.
     * @param array  $args Extra query args.
     * @return string
     */
    public static function tab_url($tab, array $args = array()) {
        return self::page_url(array_merge(array('tab' => $tab), $args));
    }

    /**
     * Add the Settings link on the Plugins screen.
     *
     * @param array $links Action links.
     * @return array
     */
    public static function plugin_action_links($links) {
        array_unshift($links, sprintf('<a href="%s">%s</a>', esc_url(self::page_url()), esc_html__('Settings', 'wp-plugin-starter-template')));
        return $links;
    }

    /**
     * Register Settings → WP Plugin Starter, or Settings in the plugin's own
     * menu.
     */
    public static function register_admin_menu() {
        $parent = self::parent();
        if ('options-general.php' === $parent) {
            $hook = add_options_page(
                __('WP Plugin Starter', 'wp-plugin-starter-template'),
                __('WP Plugin Starter', 'wp-plugin-starter-template'),
                'manage_options',
                self::PAGE,
                array(__CLASS__, 'render_settings_page')
            );
        } else {
            $hook = add_submenu_page(
                $parent,
                /* translators: %s: the plugin's name. */
                sprintf(__('%s settings', 'wp-plugin-starter-template'), __('WP Plugin Starter', 'wp-plugin-starter-template')),
                __('Settings', 'wp-plugin-starter-template'),
                'manage_options',
                self::PAGE,
                array(__CLASS__, 'render_settings_page')
            );
        }
        self::$hook = is_string($hook) ? $hook : '';
    }

    /**
     * An address from before the screen moved into the plugin's own menu
     * (options-general.php?page=…) opens it where it is now. WordPress
     * would refuse it; this runs just before it does.
     */
    public static function redirect_old_address() {
        global $pagenow;
        // phpcs:ignore WordPress.Security.NonceVerification.Recommended -- read-only redirect to the same screen.
        $page = isset($_GET['page']) ? sanitize_key(wp_unslash($_GET['page'])) : '';
        if ('options-general.php' !== $pagenow || self::PAGE !== $page || 'admin.php' !== self::screen_file()) {
            return;
        }
        // phpcs:ignore WordPress.Security.NonceVerification.Recommended -- read-only redirect to the same screen.
        $args = array_map('sanitize_text_field', wp_unslash($_GET));
        unset($args['page']);
        wp_safe_redirect(self::page_url(array_map('rawurlencode', $args)));
        exit;
    }

    /**
     * Version of an admin file: its file time, so edits bust caches, or the
     * plugin version when that can't be read.
     *
     * @param string $file Path relative to the plugin folder.
     * @return string
     */
    private static function asset_version($file) {
        $time = file_exists(WPSTARTER_DIR . $file) ? filemtime(WPSTARTER_DIR . $file) : false;
        return false === $time ? WPSTARTER_VERSION : (string) $time;
    }

    /**
     * Enqueue the header's stylesheet (render_header()), for the plugin's
     * own screens; the settings screen loads it with its own.
     */
    public static function enqueue_header() {
        wp_enqueue_style('wpstarter-header', WPSTARTER_URL . self::HEADER_CSS_FILE, array('dashicons'), self::asset_version(self::HEADER_CSS_FILE));
    }

    /**
     * Enqueue the admin stylesheets and script on our screen only.
     *
     * @param string $hook Current admin page hook.
     */
    public static function enqueue_assets($hook) {
        if (self::hook() !== $hook) {
            return;
        }

        $tab       = self::get_active_tab();
        $page_tabs = self::page_tabs();

        self::enqueue_header();
        wp_enqueue_style('wpstarter-admin', WPSTARTER_URL . self::CSS_FILE, array('wpstarter-header'), self::asset_version(self::CSS_FILE));

        $deps = array('jquery', 'wp-a11y', 'wp-i18n');
        foreach ($page_tabs as $page_tab) {
            /**
             * Filter the admin script's dependencies; enqueue what a tab
             * needs. Runs for each tab drawn on the page (page_tabs()), the
             * active tab first.
             *
             * @param string[] $deps Script handles.
             * @param string   $tab  Tab slug.
             */
            $deps = (array) apply_filters('wpstarter_admin_script_deps', $deps, $page_tab);
        }
        $deps = array_values(array_unique(array_filter(array_map('strval', $deps))));

        foreach ($page_tabs as $page_tab) {
            if (self::shows_media_field($page_tab)) {
                wp_enqueue_media();
                break;
            }
        }

        wp_enqueue_script('wpstarter-admin', WPSTARTER_URL . self::JS_FILE, $deps, self::asset_version(self::JS_FILE), true);
        wp_set_script_translations('wpstarter-admin', 'wp-plugin-starter-template');

        /**
         * Filter the data the admin script reads (wpstarterAdmin). Its tab
         * follows the tab shown; tabs lists the tabs drawn on the page.
         *
         * @param array  $data Script data.
         * @param string $tab  Active tab.
         */
        wp_localize_script('wpstarter-admin', 'wpstarterAdmin', (array) apply_filters('wpstarter_admin_script_data', array(
            'ajaxUrl' => admin_url('admin-ajax.php'),
            'nonce'   => wp_create_nonce(WPStarter_Settings::NONCE),
            'tab'     => $tab,
            'tabs'    => $page_tabs,
            'i18n'    => array(
                'saving'      => __('Saving…', 'wp-plugin-starter-template'),
                'saved'       => __('Saved', 'wp-plugin-starter-template'),
                'saveFailed'  => __('Could not save. Please try again.', 'wp-plugin-starter-template'),
                'chooseImage' => __('Choose a picture', 'wp-plugin-starter-template'),
                'useImage'    => __('Use this picture', 'wp-plugin-starter-template'),
            ),
        ), $tab));

        foreach ($page_tabs as $page_tab) {
            /**
             * Fires after the admin stylesheets and script are enqueued:
             * enqueue the plugin's own, depending on 'wpstarter-admin'. Fires
             * for each tab drawn on the page (page_tabs()), the active tab
             * first; WordPress loads each handle once, but guard inline code
             * with the tab.
             *
             * @param string $tab Tab slug.
             */
            do_action('wpstarter_admin_enqueue', $page_tab);
        }
    }

    /**
     * Whether a tab (or the search results) may show a media field, which
     * needs the media dialog.
     *
     * @param string $tab Tab slug.
     * @return bool
     */
    private static function shows_media_field($tab) {
        $schema = WPStarter_Settings::schema();
        foreach ($schema as $field) {
            if (!isset($field['type']) || 'media' !== $field['type']) {
                continue;
            }
            if (self::SEARCH === $tab) {
                return true;
            }
            $field_tab = isset($field['tab']) ? $field['tab'] : '';
            if (!$field_tab && isset($field['parent'], $schema[$field['parent']]['tab'])) {
                $field_tab = $schema[$field['parent']]['tab'];
            }
            if ($field_tab === $tab) {
                return true;
            }
        }
        return false;
    }

    /**
     * Render the page chrome and the tabs drawn on the page (page_tabs()),
     * each in its own panel; only the active tab's shows.
     */
    public static function render_settings_page() {
        if (!current_user_can('manage_options')) {
            return;
        }

        $tabs      = self::get_tabs();
        $active    = self::get_active_tab();
        $page_tabs = self::page_tabs();
        ?>
        <div class="wrap wps-wrap">
            <?php WPStarter_Admin_Page::header(); ?>

            <?php WPStarter_Admin_Page::nav($tabs, $active, $page_tabs); ?>

            <?php // Core moves admin notices after this marker instead of into the header. ?>
            <hr class="wp-header-end" />

            <?php settings_errors(); ?>

            <?php
            if (self::SEARCH === $active) {
                WPStarter_Admin_Page::panel($active, function () use ($tabs) {
                    WPStarter_Settings_Manager::render_search(self::search_query(), $tabs);
                }, true);
            } else {
                foreach ($page_tabs as $slug) {
                    if (isset($tabs[$slug]['render']) && is_callable($tabs[$slug]['render'])) {
                        WPStarter_Admin_Page::panel($slug, $tabs[$slug]['render'], $slug === $active);
                    }
                }
            }
            ?>
        </div>
        <?php
    }

    /**
     * Render the screen's header: the plugin's name and version, the feature
     * search (for people who can open the settings screen) and the links
     * WPStarter_Setup::header_links() gives. The plugin's own screens can show
     * it too: enqueue_header() on their admin_enqueue_scripts, then print
     * it first in `<div class="wrap wps-wrap">`, followed by
     * `<hr class="wp-header-end">` so admin notices go below it, and their
     * content in `<div class="wps-main">`. A screen with sections puts them
     * between the two as the settings screen's tabs: `<nav class="wps-nav">`
     * holding `<a class="wps-nav__tab">` links, the one shown `is-active`
     * with `aria-current="page"`.
     */
    public static function render_header() {
        WPStarter_Admin_Page::header();
    }
}
