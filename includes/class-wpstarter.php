<?php
/**
 * WP Plugin Starter bootstrap and feature registry. The features and anything
 * else only this plugin needs come from WPStarter_Setup.
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 * SPDX-FileCopyrightText: 2026 Marcus Quinn
 * Additional terms (GPL-3.0 section 7(b)): ATTRIBUTION.txt
 * Provenance: wpas-e4502af0f07e8a92. Copies, even of part, keep these lines.
 *
 * @package WPStarter
 * @since 0.3.0
 */

if (!defined('ABSPATH')) {
    exit;
}

final class WPStarter {

    /**
     * Feature classes whose files are loaded: WPStarter_Setup::FEATURES,
     * plus each of WPStarter_Setup::OPTIONAL_FEATURES this build has.
     *
     * @var string[]
     */
    private static $core_features = array();

    /**
     * Resolved feature classes.
     *
     * @var string[]|null
     */
    private static $features = null;

    /**
     * Load files and register hooks.
     */
    public static function load() {
        require_once WPSTARTER_DIR . 'includes/class-wpstarter-settings.php';
        require_once WPSTARTER_DIR . 'includes/class-wpstarter-network-settings.php';
        require_once WPSTARTER_DIR . 'includes/class-wpstarter-network-sites.php';
        require_once WPSTARTER_DIR . 'includes/class-wpstarter-network-differences.php';
        require_once WPSTARTER_DIR . 'includes/class-wpstarter-feature.php';
        require_once WPSTARTER_DIR . 'includes/class-wpstarter-setup.php';
        WPStarter_Setup::load();

        foreach (WPStarter_Setup::FEATURES as $class) {
            require_once self::feature_file($class);
            self::$core_features[] = $class;
        }
        // Features that some builds leave out (the WordPress.org build has
        // no GitHub updates) load only when their file is present.
        foreach (WPStarter_Setup::OPTIONAL_FEATURES as $class) {
            if (is_readable(self::feature_file($class))) {
                require_once self::feature_file($class);
                self::$core_features[] = $class;
            }
        }

        // The shared GitHub updater (GitHub builds only): registers this
        // copy; the newest copy on the site loads on plugins_loaded.
        if (is_readable(WPSTARTER_DIR . 'includes/github-updater/load.php')) {
            require_once WPSTARTER_DIR . 'includes/github-updater/load.php';
        }

        // Shared problem reports: registers this copy; the newest copy on
        // the site loads on after_setup_theme and lists this plugin, so a
        // site's AI assistant can draft reports for an administrator to send.
        if (is_readable(WPSTARTER_DIR . 'includes/wpallstars-reports/load.php')) {
            require_once WPSTARTER_DIR . 'includes/wpallstars-reports/load.php';
            add_filter('wpallstars_report_products', array(__CLASS__, 'report_product'));
        }

        WPStarter_Settings::init();
        WPStarter_Setup::init();
        // Priority 0, added after WPStarter_Settings::maybe_migrate() so features
        // read migrated values, and early enough to hook widgets_init (init:1).
        add_action('init', array(__CLASS__, 'boot_features'), 0);

        if (is_admin()) {
            require_once WPSTARTER_DIR . 'admin/settings.php';
        }
    }

    /**
     * File of a feature class.
     *
     * @param string $class Class name.
     * @return string
     */
    private static function feature_file($class) {
        return WPSTARTER_DIR . 'includes/features/class-' . str_replace('_', '-', strtolower($class)) . '.php';
    }

    /**
     * The plugin's folder name, which names it in problem reports.
     *
     * @return string
     */
    public static function slug() {
        return dirname(plugin_basename(WPSTARTER_FILE));
    }

    /**
     * List the plugin for problem reports (wpallstars_report_products):
     * reports go where WPStarter_Setup::header_links()['support'] points, a
     * GitHub issues address (public) or mailto:address (private, by email).
     *
     * @param mixed $products Products.
     * @return array
     */
    public static function report_product($products) {
        $products = (array) $products;
        $links    = WPStarter_Setup::header_links();
        if (!empty($links['support'])) {
            $products[self::slug()] = array(
                'name'    => 'WP Plugin Starter',
                'type'    => 'plugin',
                'version' => WPSTARTER_VERSION,
                'support' => $links['support'],
            );
        }
        return $products;
    }

    /**
     * Registered feature classes.
     *
     * @return string[]
     */
    public static function features() {
        if (null === self::$features) {
            /**
             * Filter the feature classes. Each must extend WPStarter_Feature.
             *
             * @param string[] $features Class names.
             */
            $features       = (array) apply_filters('wpstarter_features', self::$core_features);
            self::$features = array_values(array_filter($features, function ($class) {
                return is_string($class) && class_exists($class) && is_subclass_of($class, 'WPStarter_Feature');
            }));
        }
        return self::$features;
    }

    /**
     * Boot every feature.
     */
    public static function boot_features() {
        foreach (self::features() as $class) {
            $class::boot();
        }
    }

    /**
     * Plugin deactivated: let features that changed files or scheduled
     * work outside WordPress's options undo it (a static deactivate() method).
     *
     * @param bool $network_wide Deactivated for the whole network.
     */
    public static function deactivate($network_wide = false) {
        foreach (self::features() as $class) {
            if (method_exists($class, 'deactivate')) {
                $class::deactivate((bool) $network_wide);
            }
        }
    }
}
