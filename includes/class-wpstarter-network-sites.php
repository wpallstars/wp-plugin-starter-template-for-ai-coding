<?php
/**
 * WP Plugin Starter network settings on each site (multisite).
 *
 * How the network values (WPStarter_Network_Settings) reach the sites of
 * the network:
 *
 * - A site where the plugin runs for the first time starts with them
 *   (seed()).
 * - A change the network makes for a site runs that site's saving work
 *   (wpstarter_settings_changed and wpstarter_setting_saved) on its next
 *   admin, cron or WP-CLI request, in its own context and as nobody
 *   (sync()): never on a visitor's page, never with another site's
 *   features loaded, and never as the person who happens to open the
 *   site's admin.
 * - Make every site the same (WPStarter_Network_Differences, which also
 *   names the sites whose own values differ) changes each site's own
 *   values; the site keeps its values from before (remember()) for its
 *   saving work.
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 * SPDX-FileCopyrightText: 2026 Marcus Quinn
 * Additional terms (GPL-3.0 section 7(b)): ATTRIBUTION.txt
 * Provenance: wpas-e4502af0f07e8a92. Copies, even of part, keep these lines.
 *
 * @package WPStarter
 * @since 1.0.35
 */

if (!defined('ABSPATH')) {
    exit;
}

class WPStarter_Network_Sites {

    /**
     * Site option: the network `version` and `enforced` values the site
     * last ran its saving work for, and in `before` its own values from
     * before the network changed them (Make every site the same, or the
     * values a new site started with).
     */
    const SEEN = 'wpstarter_network_seen';

    /**
     * Whether the network's changes are being applied to this site (sync()).
     *
     * @var bool
     */
    private static $syncing = false;

    /**
     * Register hooks (multisite only).
     */
    public static function init() {
        if (!is_multisite()) {
            return;
        }
        add_action('wp_loaded', array(__CLASS__, 'sync'));
    }

    /**
     * Whether the network's changes are being applied to this site, so
     * saving work runs as nobody: work that depends on who saves (such as
     * keeping the person saving on a list) can check this.
     *
     * @return bool
     */
    public static function syncing() {
        return self::$syncing;
    }

    /**
     * A site's first settings: what migrations imported, then the values
     * saved on the network screen for anything not imported. Those that
     * differ from their defaults run the site's saving work on its next
     * admin, cron or WP-CLI request (sync()), as if they had been saved.
     *
     * @param array $options Stored settings (raw, without defaults).
     * @return array
     */
    public static function seed(array $options) {
        if (!is_multisite()) {
            return $options;
        }
        $defaults = WPStarter_Settings::defaults();
        $before   = array();
        foreach (WPStarter_Network_Settings::stored()['values'] as $key => $value) {
            $key = (string) $key;
            if (array_key_exists($key, $options) || !WPStarter_Network_Settings::eligible($key)) {
                continue;
            }
            $options[$key] = $value;
            if (!WPStarter_Settings::same($value, $defaults[$key])) {
                $before[$key] = $defaults[$key];
            }
        }
        if ($before) {
            $seen           = self::seen();
            $seen['before'] = array_merge($before, $seen['before']);
            update_option(self::SEEN, $seen, true);
        }
        return $options;
    }

    /**
     * This site's SEEN option, with every part present.
     *
     * @return array{version:int,enforced:array,before:array}
     */
    private static function seen() {
        $seen = get_option(self::SEEN, array());
        $seen = (is_array($seen) ? $seen : array()) + array('version' => 0, 'enforced' => array(), 'before' => array());
        return array(
            'version'  => (int) $seen['version'],
            'enforced' => is_array($seen['enforced']) ? $seen['enforced'] : array(),
            'before'   => is_array($seen['before']) ? $seen['before'] : array(),
        );
    }

    /**
     * Run this site's saving work for changes the network made since the
     * last time: a card applied, changed or no longer applied, Make every
     * site the same, or the values a new site started with. Only on
     * requests that may wait on it (saving_request()); the values
     * themselves apply at once.
     */
    public static function sync() {
        if (!self::saving_request()) {
            return;
        }
        $network = WPStarter_Network_Settings::stored();
        // A site that has nothing recorded (SEEN is autoloaded once
        // written) has nothing to do until the network changes something:
        // skip asking the database for it on every admin request.
        if (0 === $network['version'] && !array_key_exists(self::SEEN, wp_load_alloptions())) {
            return;
        }
        if (!self::pending(self::seen(), $network)) {
            return;
        }

        // Read and recorded under the site's save lock, which Make every
        // site the same holds while it changes the site's values and keeps
        // those from before (WPStarter_Settings::replace_site_values()): so
        // values it keeps are never written over here, and the settings read
        // here already hold the values they were kept for. Read past this
        // request's caches, which may predate that. Recorded first, so a
        // request that starts meanwhile does not run the same work again.
        // The saving work runs after the lock is released: it may save.
        $work = WPStarter_Settings::under_lock(function () use ($network) {
            self::flush_site_cache(get_current_blog_id(), array(self::SEEN, WPStarter_Settings::OPTION));
            $seen = self::seen();
            if (!self::pending($seen, $network)) {
                return null;
            }
            update_option(self::SEEN, array('version' => $network['version'], 'enforced' => $network['enforced']), true);

            // What the site's features last ran their saving work for: its
            // own values, as they were before the network changed them,
            // under the values the network applied then.
            $schema = WPStarter_Settings::schema();
            return array(
                array_merge(
                    WPStarter_Settings::own(),
                    array_intersect_key($seen['before'], $schema),
                    array_intersect_key(WPStarter_Network_Settings::flatten($seen['enforced']), $schema)
                ),
                WPStarter_Settings::all(),
            );
        });
        // Nothing to do, or the lock was busy: the next request tries again.
        if (is_array($work)) {
            self::run_saving_work($work[0], $work[1]);
        }
    }

    /**
     * Whether the site has saving work to run for the network's changes.
     *
     * @param array $seen    This site's SEEN option (seen()).
     * @param array $network The network option (WPStarter_Network_Settings::stored()).
     * @return bool
     */
    private static function pending(array $seen, array $network) {
        return $seen['version'] !== $network['version'] || (bool) $seen['before'];
    }

    /**
     * Whether this request runs the site's saving work: admin screens, cron
     * and WP-CLI, so a visitor's page or AJAX request never waits on it.
     * Not while WordPress installs.
     *
     * @return bool
     */
    private static function saving_request() {
        if (wp_installing()) {
            return false;
        }
        return (is_admin() && !wp_doing_ajax()) || wp_doing_cron() || (defined('WP_CLI') && WP_CLI);
    }

    /**
     * Run the saving work for the settings that changed, as nobody, as
     * WP-CLI and cron do: the network made the change, not the person whose
     * request runs it.
     *
     * @param array $old What the site's features last ran their saving work for.
     * @param array $new The site's settings now.
     */
    private static function run_saving_work(array $old, array $new) {
        $changed = array();
        foreach ($new as $key => $value) {
            if (!WPStarter_Settings::same($old[$key] ?? null, $value)) {
                $changed[$key] = $value;
            }
        }
        if (!$changed) {
            return;
        }

        $user          = get_current_user_id();
        self::$syncing = true;
        if ($user) {
            wp_set_current_user(0);
        }
        try {
            /** This action is documented in includes/class-wpstarter-settings.php */
            do_action('wpstarter_settings_changed', $old, $new);
            foreach ($changed as $key => $value) {
                /** This action is documented in includes/class-wpstarter-settings.php */
                do_action('wpstarter_setting_saved', $key, $value);
            }
        } finally {
            if ($user) {
                wp_set_current_user($user);
            }
            self::$syncing = false;
        }
    }

    /**
     * Keep a site's own values from before Make every site the same
     * (WPStarter_Network_Differences::copy()), for its saving work (sync()).
     * The earliest value of a key is kept. Read and written straight in its
     * options table by WPStarter_Settings::replace_site_values(), under the
     * site's save lock, which sync() also holds while it reads and records
     * this option: call it only there.
     *
     * @param int   $site_id  Site ID.
     * @param array $previous Key => own value before the change.
     */
    public static function remember($site_id, array $previous) {
        global $wpdb;
        $table = $wpdb->get_blog_prefix($site_id) . 'options';
        // phpcs:ignore WordPress.DB.DirectDatabaseQuery -- another site's options, not loaded here (WPStarter_Network_Differences::read_site()).
        $raw  = $wpdb->get_var($wpdb->prepare('SELECT option_value FROM %i WHERE option_name = %s', $table, self::SEEN));
        $seen = null === $raw ? array() : maybe_unserialize($raw);
        $seen = is_array($seen) ? $seen : array();

        $seen['before'] = array_merge($previous, isset($seen['before']) && is_array($seen['before']) ? $seen['before'] : array());
        // phpcs:ignore WordPress.DB.DirectDatabaseQuery -- as above; the site's caches are cleared next.
        $wpdb->query($wpdb->prepare(
            "INSERT INTO %i (option_name, option_value, autoload) VALUES (%s, %s, 'yes') ON DUPLICATE KEY UPDATE option_value = VALUES(option_value)",
            $table,
            self::SEEN,
            maybe_serialize($seen)
        ));
        self::flush_site_cache($site_id, array(self::SEEN));
    }

    /**
     * Drop a site's cached copies of options written straight to its
     * table, so its next request reads them. Switches only the object
     * cache to that site, not the whole site.
     *
     * @param int      $site_id Site ID.
     * @param string[] $names   Option names.
     */
    public static function flush_site_cache($site_id, array $names) {
        $current = get_current_blog_id();
        $switch  = (int) $site_id !== $current;
        // Object caches without wp_cache_switch_to_blog() switch only with the site.
        $cache_only = function_exists('wp_cache_switch_to_blog');
        if ($switch) {
            if ($cache_only) {
                wp_cache_switch_to_blog((int) $site_id);
            } else {
                switch_to_blog((int) $site_id);
            }
        }
        foreach (array_merge($names, array('alloptions', 'notoptions')) as $name) {
            wp_cache_delete($name, 'options');
        }
        if ($switch) {
            if ($cache_only) {
                wp_cache_switch_to_blog($current);
            } else {
                restore_current_blog();
            }
        }
    }
}
