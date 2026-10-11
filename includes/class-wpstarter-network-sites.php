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
 * - The network screen names the sites whose own values differ
 *   (differences()), and Make every site the same copies a card's network
 *   values into every site's own settings once (copy()). Both read and
 *   write each site's options table directly: switching to each site
 *   would load all of its autoloaded options.
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 * SPDX-FileCopyrightText: 2026 Marcus Quinn
 * Additional terms (GPL-3.0 section 7(b)): ATTRIBUTION.txt
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

    /** Most sites the network screen compares or changes in one request. */
    const MAX_SITES = 500;

    /**
     * Sites that differ, per card, for this request (differences()).
     *
     * @var array{checked:bool,total:int,cards:array<string,int[]>,sites:array<int,array{name:string,url:string}>}|null
     */
    private static $differences = null;

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
     * Forget the sites that differ, read for this request, after the
     * network values or the sites' own values changed.
     */
    public static function forget() {
        self::$differences = null;
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
        $seen = self::seen();
        if ($seen['version'] === $network['version'] && !$seen['before']) {
            return;
        }

        // Recorded first, so a request that starts meanwhile does not run
        // the same work again.
        update_option(self::SEEN, array('version' => $network['version'], 'enforced' => $network['enforced']), true);

        // What the site's features last ran their saving work for: its own
        // values, as they were before the network changed them, under the
        // values the network applied then.
        $schema = WPStarter_Settings::schema();
        self::run_saving_work(array_merge(
            WPStarter_Settings::own(),
            array_intersect_key($seen['before'], $schema),
            array_intersect_key(WPStarter_Network_Settings::flatten($seen['enforced']), $schema)
        ), WPStarter_Settings::all());
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
     * Sites of this network, or null when there are more than MAX_SITES.
     *
     * @return int[]|null
     */
    private static function site_ids() {
        $ids = get_sites(array(
            'fields'     => 'ids',
            'number'     => self::MAX_SITES + 1,
            'network_id' => get_current_network_id(),
            'orderby'    => 'id',
        ));
        return count($ids) > self::MAX_SITES ? null : array_map('intval', $ids);
    }

    /**
     * A site's own settings, name and address, read straight from its
     * options table: switching to each site would load all of its autoloaded
     * options, for every site on the network.
     *
     * @param int $site_id Site ID.
     * @return array{options:array|null,name:string,url:string}
     */
    private static function read_site($site_id) {
        global $wpdb;
        $suppress = $wpdb->suppress_errors(true);
        // phpcs:ignore WordPress.DB.DirectDatabaseQuery -- reads another site's options without loading all of them (read_site()).
        $rows = $wpdb->get_results($wpdb->prepare(
            'SELECT option_name, option_value FROM %i WHERE option_name IN (%s, %s, %s)',
            $wpdb->get_blog_prefix($site_id) . 'options',
            WPStarter_Settings::OPTION,
            'blogname',
            'siteurl'
        ));
        $wpdb->suppress_errors($suppress);

        $site = array('options' => null, 'name' => '', 'url' => '');
        foreach ((array) $rows as $row) {
            if (WPStarter_Settings::OPTION === $row->option_name) {
                $options         = maybe_unserialize($row->option_value);
                $site['options'] = is_array($options) ? $options : null;
            } elseif ('blogname' === $row->option_name) {
                $site['name'] = (string) $row->option_value;
            } else {
                $site['url'] = (string) $row->option_value;
            }
        }
        return $site;
    }

    /**
     * Sites whose own values differ from the network's, for each card the
     * network screen shows. Sites where the plugin has not run yet are left
     * out: they start with the network values. Not checked (checked false)
     * on networks with more than MAX_SITES sites.
     *
     * @return array{checked:bool,total:int,cards:array<string,int[]>,sites:array<int,array{name:string,url:string}>}
     */
    public static function differences() {
        if (null !== self::$differences) {
            return self::$differences;
        }
        $result = array('checked' => false, 'total' => 0, 'cards' => array(), 'sites' => array());
        $ids    = self::site_ids();
        if (null === $ids) {
            self::$differences = $result;
            return $result;
        }

        $cards = array();
        foreach (WPStarter_Settings::schema() as $key => $field) {
            if (empty($field['parent']) && WPStarter_Network_Settings::eligible((string) $key)) {
                $cards[(string) $key] = WPStarter_Network_Settings::card_keys((string) $key);
            }
        }
        $defaults = WPStarter_Settings::defaults();

        foreach ($ids as $id) {
            $site = self::read_site($id);
            if (null === $site['options']) {
                continue;
            }
            $result['total']++;
            $result['sites'][$id] = array('name' => $site['name'], 'url' => $site['url']);
            foreach ($cards as $card => $keys) {
                if (self::card_differs($keys, $site['options'], $defaults)) {
                    $result['cards'][$card][] = $id;
                }
            }
        }
        $result['checked'] = true;
        self::$differences = $result;
        return $result;
    }

    /**
     * Whether a site's own values for a card differ from the network's.
     *
     * @param string[] $keys     The card's keys (WPStarter_Network_Settings::card_keys()).
     * @param array    $options  The site's stored settings.
     * @param array    $defaults Defaults.
     * @return bool
     */
    private static function card_differs(array $keys, array $options, array $defaults) {
        foreach ($keys as $key) {
            $own = array_key_exists($key, $options) ? $options[$key] : $defaults[$key];
            if (!WPStarter_Settings::same($own, WPStarter_Network_Settings::value($key))) {
                return true;
            }
        }
        return false;
    }

    /**
     * Make every site the same: copy a card's network values into the own
     * settings of every site where the plugin has run. Each site runs its
     * saving work on its next admin, cron or WP-CLI request (sync()); sites
     * can change the values again afterwards unless the card is applied.
     *
     * @param string $key Card's setting key.
     * @return int|WP_Error Number of sites changed.
     */
    public static function copy($key) {
        $keys = WPStarter_Network_Settings::card_keys($key);
        if (!$keys) {
            return new WP_Error('wpstarter_unknown_setting', __('This setting is set on each site.', 'wp-plugin-starter-template'));
        }
        $ids = self::site_ids();
        if (null === $ids) {
            /* translators: %d: number of sites */
            return new WP_Error('wpstarter_too_many_sites', sprintf(__('This network has more than %d sites, too many to change at once.', 'wp-plugin-starter-template'), self::MAX_SITES));
        }

        $values = array();
        foreach ($keys as $card_key) {
            $values[$card_key] = WPStarter_Network_Settings::value($card_key);
        }

        $changed = 0;
        foreach ($ids as $id) {
            $previous = WPStarter_Settings::replace_site_values($id, $values);
            if ($previous) {
                self::remember($id, $previous);
                $changed++;
            }
        }
        self::forget();
        return $changed;
    }

    /**
     * Keep a site's own values from before Make every site the same, for
     * its saving work (sync()). The earliest value of a key is kept.
     * Written straight to its options table, as
     * WPStarter_Settings::replace_site_values() does.
     *
     * @param int   $site_id  Site ID.
     * @param array $previous Key => own value before the change.
     */
    private static function remember($site_id, array $previous) {
        global $wpdb;
        $table = $wpdb->get_blog_prefix($site_id) . 'options';
        // phpcs:ignore WordPress.DB.DirectDatabaseQuery -- another site's options, not loaded here (read_site()).
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
