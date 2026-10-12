<?php
/**
 * Per-person Light, Dark or System mode on the plugin's own admin screens.
 * Shared user meta and document events keep other wpallstars controls in step.
 * The head script sets the classes before the first paint; other screens
 * keep WordPress's own colours (or their own dark mode).
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

final class WPStarter_Admin_Theme {

    const META        = 'wpstarter_admin_theme';
    const SHARED_META = 'wpallstars_admin_theme';
    const ACTION      = 'wpstarter_admin_theme';
    const MODES       = array('light', 'dark', 'system');
    const CSS_FILE    = 'admin/css/wpstarter-theme.css';
    const JS_FILE     = 'admin/js/wpstarter-theme.js';

    /** Register on admin requests, after the screen's own styles. */
    public static function init() {
        add_action('admin_enqueue_scripts', array(__CLASS__, 'enqueue'), 20);
        add_action('admin_head', array(__CLASS__, 'head'), 1);
        add_action('wp_ajax_' . self::ACTION, array(__CLASS__, 'save'));
        add_filter('wpallstars_admin_theme_participants', array(__CLASS__, 'participants'));
        add_filter('seoprostack_admin_dark_screen', array(__CLASS__, 'seoprostack_dark_screen'), 10, 2);
    }

    /**
     * Join the shared mode for people who can open these screens.
     *
     * @param mixed $participants Participating slugs => true.
     * @return array<string,bool>
     */
    public static function participants($participants) {
        $participants = is_array($participants) ? $participants : array();
        if (current_user_can(is_network_admin() ? 'manage_network_options' : 'manage_options')) {
            $participants['wp-plugin-starter-template'] = true;
        }
        return $participants;
    }

    /**
     * Keep Stack's whole-admin rules off screens with our own palette.
     *
     * @param mixed $applies Whether Stack darkens the screen.
     * @param mixed $screen WP_Screen or null.
     * @return bool
     */
    public static function seoprostack_dark_screen($applies, $screen = null) {
        return self::is_screen($screen) ? false : (bool) $applies;
    }

    /**
     * Read the shared choice first, then the plugin's own, then Light.
     *
     * @param int $user_id User ID, or zero for the current person.
     * @return string
     */
    public static function mode($user_id = 0) {
        $user_id = $user_id ? (int) $user_id : get_current_user_id();
        if ($user_id) {
            foreach (array(self::SHARED_META, self::META) as $key) {
                $mode = get_user_meta($user_id, $key, true);
                if (in_array($mode, self::MODES, true)) {
                    return $mode;
                }
            }
        }
        return self::MODES[0];
    }

    /**
     * Screen hooks known before the head is printed. Own screens normally
     * call enqueue_header() on admin_enqueue_scripts; plugins can also add
     * hooks here, for example when they enqueue their header later.
     *
     * @return string[]
     */
    public static function screens() {
        return (array) apply_filters('wpstarter_admin_theme_screens', array(
            WPStarter_Admin_Manager::hook(),
            WPStarter_Network_Manager::hook(),
        ));
    }

    /**
     * Whether this is an own screen, without claiming other admin screens.
     *
     * @param mixed $screen WP_Screen or null for the current one.
     * @return bool
     */
    private static function is_screen($screen = null) {
        $current = get_current_screen();
        $screen  = $screen instanceof WP_Screen ? $screen : $current;
        if (!$screen instanceof WP_Screen) {
            return false;
        }
        return in_array($screen->id, self::screens(), true)
            || ($current instanceof WP_Screen && $current->id === $screen->id && wp_style_is('wpstarter-header', 'enqueued'));
    }

    /**
     * Load only on own screens; the header's enqueue also identifies them.
     *
     * @param string $hook Current screen hook.
     */
    public static function enqueue($hook) {
        if (!in_array($hook, self::screens(), true) && !self::is_screen()) {
            return;
        }
        wp_enqueue_style('wpstarter-theme', WPSTARTER_URL . self::CSS_FILE, array('wpstarter-header'), self::asset_version(self::CSS_FILE));
        wp_enqueue_script('wpstarter-theme', WPSTARTER_URL . self::JS_FILE, array('wp-i18n', 'wp-a11y'), self::asset_version(self::JS_FILE), true);
        wp_set_script_translations('wpstarter-theme', 'wp-plugin-starter-template');
        wp_add_inline_script('wpstarter-theme', 'window.wpstarterTheme = ' . wp_json_encode(array(
            'mode'    => self::mode(),
            'ajaxUrl' => admin_url('admin-ajax.php'),
            'action'  => self::ACTION,
            'nonce'   => wp_create_nonce(self::nonce_action(is_network_admin())),
            'network' => is_network_admin(),
        )) . ';', 'before');
    }

    /**
     * File-based asset version, or the plugin version if absent.
     *
     * @param string $file Relative file path.
     * @return string
     */
    private static function asset_version($file) {
        $time = file_exists(WPSTARTER_DIR . $file) ? filemtime(WPSTARTER_DIR . $file) : false;
        return false === $time ? WPSTARTER_VERSION : (string) $time;
    }

    /** Set the mode classes before the body is parsed. */
    public static function head() {
        if (!self::is_screen()) {
            return;
        }
        $script = '(function(r,m){var q=window.matchMedia&&window.matchMedia("(prefers-color-scheme: dark)");'
            . 'r.classList.add("wps-theme-"+m);'
            . 'if(m==="dark"||(m==="system"&&q&&q.matches)){r.classList.add("wps-dark");}'
            . '})(document.documentElement,' . wp_json_encode(self::mode()) . ');';
        wp_print_inline_script_tag($script, array('id' => 'wpstarter-theme-mode'));
    }

    /**
     * Bind the nonce to its originating admin context: admin-ajax itself
     * is not a network admin screen.
     *
     * @param bool $network Whether saving from network admin.
     * @return string
     */
    private static function nonce_action($network) {
        return self::ACTION . ($network ? '_network' : '');
    }

    /** Save only the current person's allow-listed choice. */
    public static function save() {
        $network = isset($_POST['network']) && '1' === $_POST['network'];
        check_ajax_referer(self::nonce_action($network), 'nonce');
        if (!current_user_can($network ? 'manage_network_options' : 'manage_options')) {
            wp_send_json_error(array('message' => __('You cannot change this.', 'wp-plugin-starter-template')), 403);
        }
        $mode = isset($_POST['mode']) && is_string($_POST['mode']) ? sanitize_key(wp_unslash($_POST['mode'])) : '';
        if (!in_array($mode, self::MODES, true)) {
            wp_send_json_error(array('message' => __('Unknown colour mode.', 'wp-plugin-starter-template')), 400);
        }
        if (!self::store($mode)) {
            wp_send_json_error(array('message' => __('The colour mode could not be saved.', 'wp-plugin-starter-template')), 500);
        }
        wp_send_json_success(array('mode' => $mode));
    }

    /**
     * Save both copies, restoring a partial write before reporting failure.
     *
     * @param string $mode Allow-listed mode.
     * @return bool
     */
    private static function store($mode) {
        $user_id  = get_current_user_id();
        $previous = array();
        foreach (array(self::SHARED_META, self::META) as $key) {
            $previous[$key] = get_user_meta($user_id, $key, false);
        }
        foreach (array_keys($previous) as $key) {
            update_user_meta($user_id, $key, $mode);
            if (get_user_meta($user_id, $key, true) !== $mode) {
                self::restore($user_id, $previous, $mode);
                return false;
            }
        }
        return true;
    }

    /**
     * Undo only this mode's writes, not a newer choice in another tab.
     *
     * @param int $user_id Current user.
     * @param array<string,array> $previous Previous rows, empty for absent keys.
     * @param string $mode Mode this save attempted.
     */
    private static function restore($user_id, array $previous, $mode) {
        foreach ($previous as $key => $values) {
            if (!$values) {
                delete_user_meta($user_id, $key, $mode);
            } else {
                update_user_meta($user_id, $key, $values[0], $mode);
            }
        }
    }

    /**
     * Remove our preference on uninstall. Keep the shared choice while
     * another wpallstars plugin is installed, even if it is inactive.
     */
    public static function uninstall() {
        delete_metadata('user', 0, self::META, '', true);
        if (!function_exists('get_plugins')) {
            require_once ABSPATH . 'wp-admin/includes/plugin.php';
        }
        foreach (get_plugins() as $file => $plugin) {
            if (defined('WP_UNINSTALL_PLUGIN') && $file === constant('WP_UNINSTALL_PLUGIN')) {
                continue;
            }
            if (file_exists(WP_PLUGIN_DIR . '/' . dirname($file) . '/admin/includes/class-admin-theme.php')
                || 0 === strpos($plugin['PluginURI'], 'https://github.com/wpallstars/')) {
                return;
            }
        }
        delete_metadata('user', 0, self::SHARED_META, '', true);
    }
}
