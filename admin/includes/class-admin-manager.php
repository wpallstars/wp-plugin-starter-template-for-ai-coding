<?php
/**
 * WP Plugin Starter admin screen.
 *
 * Owns the settings screen: tab registry, page chrome and the single admin
 * script/stylesheet. Tab content is delegated to the manager classes.
 * Settings tabs and header links come from WPStarter_Setup; add other tabs
 * with the `wpstarter_admin_tabs` filter.
 *
 * The screen is Settings → WP Plugin Starter, or Settings in the plugin's own
 * top-level menu when WPStarter_Setup::MENU_PARENT names that menu. Build
 * its links with page_url() or tab_url(), which follow where it is.
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

    /** Admin stylesheet and script, relative to the plugin folder. */
    const CSS_FILE = 'admin/css/wpstarter-admin.css';
    const JS_FILE  = 'admin/js/wpstarter-admin.js';

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
     * Registered tabs.
     *
     * @return array<string,array{label:string,group:string,render:callable}>
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
                'label'  => $tab['label'],
                'group'  => 'settings',
                'render' => function () use ($slug, $tab) {
                    WPStarter_Settings_Manager::render_tab($slug, $tab['label'], $tab['description']);
                },
            );
        }

        $tabs += array(
            'readme' => array(
                'label'  => __('Read Me', 'wp-plugin-starter-template'),
                'group'  => 'about',
                'render' => array('WPStarter_Readme_Manager', 'display_tab_content'),
            ),
        );

        /**
         * Filter the admin tabs.
         *
         * @param array $tabs Tabs keyed by slug: label, group (settings|discover|about),
         *                    render callback, optional capability.
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
     * Enqueue the admin stylesheet and script on our screen only.
     *
     * @param string $hook Current admin page hook.
     */
    public static function enqueue_assets($hook) {
        if (self::hook() !== $hook) {
            return;
        }

        $tab = self::get_active_tab();
        // File times bust caches after edits; the version is the fallback.
        $css = file_exists(WPSTARTER_DIR . self::CSS_FILE) ? filemtime(WPSTARTER_DIR . self::CSS_FILE) : false;
        $css = false === $css ? WPSTARTER_VERSION : (string) $css;
        $js  = file_exists(WPSTARTER_DIR . self::JS_FILE) ? filemtime(WPSTARTER_DIR . self::JS_FILE) : false;
        $js  = false === $js ? WPSTARTER_VERSION : (string) $js;

        wp_enqueue_style('wpstarter-admin', WPSTARTER_URL . self::CSS_FILE, array('dashicons'), $css);

        /**
         * Filter the admin script's dependencies; enqueue what a tab needs.
         *
         * @param string[] $deps Script handles.
         * @param string   $tab  Active tab.
         */
        $deps = array_values(array_filter(array_map('strval', (array) apply_filters('wpstarter_admin_script_deps', array('jquery', 'wp-a11y', 'wp-i18n'), $tab))));

        if (self::shows_media_field($tab)) {
            wp_enqueue_media();
        }

        wp_enqueue_script('wpstarter-admin', WPSTARTER_URL . self::JS_FILE, $deps, $js, true);
        wp_set_script_translations('wpstarter-admin', 'wp-plugin-starter-template');

        /**
         * Filter the data the admin script reads (wpstarterAdmin).
         *
         * @param array  $data Script data.
         * @param string $tab  Active tab.
         */
        wp_localize_script('wpstarter-admin', 'wpstarterAdmin', (array) apply_filters('wpstarter_admin_script_data', array(
            'ajaxUrl' => admin_url('admin-ajax.php'),
            'nonce'   => wp_create_nonce(WPStarter_Settings::NONCE),
            'tab'     => $tab,
            'i18n'    => array(
                'saving'      => __('Saving…', 'wp-plugin-starter-template'),
                'saved'       => __('Saved', 'wp-plugin-starter-template'),
                'saveFailed'  => __('Could not save. Please try again.', 'wp-plugin-starter-template'),
                'chooseImage' => __('Choose a picture', 'wp-plugin-starter-template'),
                'useImage'    => __('Use this picture', 'wp-plugin-starter-template'),
            ),
        ), $tab));

        /**
         * Fires after the admin stylesheet and script are enqueued: enqueue
         * the plugin's own, depending on 'wpstarter-admin'.
         *
         * @param string $tab Active tab.
         */
        do_action('wpstarter_admin_enqueue', $tab);
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
     * Render the page chrome and the active tab.
     */
    public static function render_settings_page() {
        if (!current_user_can('manage_options')) {
            return;
        }

        $tabs   = self::get_tabs();
        $active = self::get_active_tab();
        $links  = WPStarter_Setup::header_links();
        ?>
        <div class="wrap wps-wrap">
            <header class="wps-header">
                <div class="wps-header__brand">
                    <span class="wps-header__logo dashicons dashicons-star-filled" aria-hidden="true"></span>
                    <h1 class="wps-header__title"><?php esc_html_e('WP Plugin Starter', 'wp-plugin-starter-template'); ?></h1>
                    <span class="wps-badge"><?php echo esc_html('v' . WPSTARTER_VERSION); ?></span>
                </div>
                <form class="wps-search" role="search" method="get" action="<?php echo esc_url(admin_url(self::screen_file())); ?>">
                    <input type="hidden" name="page" value="<?php echo esc_attr(self::PAGE); ?>" />
                    <input type="hidden" name="tab" value="<?php echo esc_attr(self::SEARCH); ?>" />
                    <label class="screen-reader-text" for="wps-search-input"><?php esc_html_e('Search features', 'wp-plugin-starter-template'); ?></label>
                    <span class="wps-search__field">
                        <span class="wps-search__icon dashicons dashicons-search" aria-hidden="true"></span>
                        <input type="search"
                               id="wps-search-input"
                               class="wps-search__input"
                               name="s"
                               maxlength="100"
                               value="<?php echo esc_attr(self::search_query()); ?>"
                               placeholder="<?php esc_attr_e('Search features', 'wp-plugin-starter-template'); ?>" />
                    </span>
                    <button type="submit" class="button wps-search__button"><?php esc_html_e('Search', 'wp-plugin-starter-template'); ?></button>
                </form>
                <div class="wps-header__actions">
                    <?php if (!empty($links['source'])) : ?>
                        <a class="button wps-header__support" href="<?php echo esc_url($links['source']); ?>" target="_blank" rel="noopener noreferrer">
                            <span class="dashicons dashicons-editor-code" aria-hidden="true"></span>
                            <?php esc_html_e('Source code', 'wp-plugin-starter-template'); ?>
                            <span class="screen-reader-text"><?php esc_html_e('(opens in a new tab)', 'wp-plugin-starter-template'); ?></span>
                        </a>
                    <?php elseif (!empty($links['website'])) : ?>
                        <?php // Older {Prefix}_Setup classes link the maker's website instead. ?>
                        <a class="button" href="<?php echo esc_url($links['website']); ?>" target="_blank" rel="noopener noreferrer">
                            <?php esc_html_e('Visit website', 'wp-plugin-starter-template'); ?>
                            <span class="screen-reader-text"><?php esc_html_e('(opens in a new tab)', 'wp-plugin-starter-template'); ?></span>
                        </a>
                    <?php endif; ?>
                    <?php if (!empty($links['support'])) : ?>
                        <a class="button wps-header__support" href="<?php echo esc_url($links['support']); ?>" target="_blank" rel="noopener noreferrer">
                            <span class="dashicons dashicons-sos" aria-hidden="true"></span>
                            <?php esc_html_e('Support', 'wp-plugin-starter-template'); ?>
                            <span class="screen-reader-text"><?php esc_html_e('(opens in a new tab)', 'wp-plugin-starter-template'); ?></span>
                        </a>
                    <?php endif; ?>
                    <?php if (!empty($links['donate'])) : ?>
                        <a class="button wps-header__support wps-header__donate" href="<?php echo esc_url($links['donate']); ?>" target="_blank" rel="noopener noreferrer">
                            <span class="dashicons dashicons-coffee" aria-hidden="true"></span>
                            <?php esc_html_e('Buy me a coffee', 'wp-plugin-starter-template'); ?>
                            <span class="screen-reader-text"><?php esc_html_e('(opens in a new tab)', 'wp-plugin-starter-template'); ?></span>
                        </a>
                    <?php endif; ?>
                </div>
            </header>

            <?php self::render_nav($tabs, $active); ?>

            <?php // Core moves admin notices after this marker instead of into the header. ?>
            <hr class="wp-header-end" />

            <?php settings_errors(); ?>

            <?php // Not <main>: core's #wpbody already carries role="main". ?>
            <div class="wps-main wps-tab-<?php echo esc_attr($active); ?>" id="wps-tab-<?php echo esc_attr($active); ?>">
                <?php
                if (self::SEARCH === $active) {
                    WPStarter_Settings_Manager::render_search(self::search_query(), $tabs);
                } elseif (isset($tabs[$active]['render']) && is_callable($tabs[$active]['render'])) {
                    call_user_func($tabs[$active]['render']);
                }
                ?>
            </div>
        </div>
        <?php
    }

    /**
     * Render the tab navigation: one labelled group of links per section
     * that has tabs.
     *
     * @param array  $tabs   Tabs (get_tabs()).
     * @param string $active Active tab slug.
     */
    private static function render_nav(array $tabs, $active) {
        $groups = array(
            'settings' => __('Settings', 'wp-plugin-starter-template'),
            'discover' => __('Discover', 'wp-plugin-starter-template'),
            'about'    => __('About', 'wp-plugin-starter-template'),
        );
        ?>
        <nav class="wps-nav" aria-label="<?php esc_attr_e('WP Plugin Starter sections', 'wp-plugin-starter-template'); ?>">
            <?php
            foreach ($groups as $group => $group_label) {
                $group_tabs = array_filter($tabs, function ($tab) use ($group) {
                    return isset($tab['group']) && $tab['group'] === $group;
                });
                if ($group_tabs) {
                    self::render_nav_group($group_label, $group_tabs, $active);
                }
            }
            ?>
        </nav>
        <?php
    }

    /**
     * Render one navigation group. A group of links, not form controls, so
     * role="group" with a label rather than <fieldset>.
     *
     * @param string $label  Group label.
     * @param array  $tabs   The group's tabs.
     * @param string $active Active tab slug.
     */
    private static function render_nav_group($label, array $tabs, $active) {
        ?>
        <div class="wps-nav__group" role="group" aria-label="<?php echo esc_attr($label); ?>">
            <?php foreach ($tabs as $slug => $tab) : ?>
                <a href="<?php echo esc_url(self::tab_url($slug)); ?>"
                   class="wps-nav__tab<?php echo $slug === $active ? ' is-active' : ''; ?>"
                   <?php echo $slug === $active ? 'aria-current="page"' : ''; ?>>
                    <?php echo esc_html($tab['label']); ?>
                </a>
            <?php endforeach; ?>
        </div>
        <?php
    }
}
