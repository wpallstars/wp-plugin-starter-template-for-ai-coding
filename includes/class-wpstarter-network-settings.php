<?php
/**
 * WP Plugin Starter network settings (multisite).
 *
 * The network screen (Network Admin → Settings → WP Plugin Starter) saves
 * network values, kept in one network option. A card applied to every
 * site overrides each site's own values with the network's, and sites
 * cannot change them; when it stops applying, each site has its own values
 * again, as they were never overwritten. Make every site the same copies a
 * card's network values into every site's own settings once. New sites,
 * and sites where the plugin runs for the first time, start with the
 * network values.
 *
 * Settings that only make sense on each site are never set for the
 * network: Media Library pictures, hidden wiring, and fields with
 * 'network' => false in the schema (eligible()).
 *
 * A change the network makes for a site runs that site's saving work
 * (wpstarter_settings_changed and wpstarter_setting_saved) on its next
 * admin, cron or WP-CLI request, in its own context and as nobody
 * (sync()): never on a visitor's page, never with another site's features
 * loaded, and never as the person who happens to open the site's admin.
 *
 * Single sites never read the network option.
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 * SPDX-FileCopyrightText: 2026 Marcus Quinn
 * Additional terms (GPL-3.0 section 7(b)): ATTRIBUTION.txt
 *
 * @package WPStarter
 * @since 1.0.34
 */

if (!defined('ABSPATH')) {
    exit;
}

class WPStarter_Network_Settings {

    /**
     * Network option: `values` (key => value saved on the network screen),
     * `applied` (keys of the cards applied to every site), `enforced`
     * (applied card key => its keys and the values every site uses) and
     * `version` (raised whenever `enforced` changes). Code that runs before
     * the plugin loads (a must-use file) reads `enforced` over the site's
     * own settings, as WPStarter_Settings::all() does.
     */
    const OPTION = 'wpstarter_network';

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
     * The network option, read once per request (stored()).
     *
     * @var array{values:array,applied:string[],enforced:array<array>,version:int}|null
     */
    private static $stored = null;

    /**
     * The enforced values of every applied card, flattened (enforced()).
     *
     * @var array|null
     */
    private static $enforced = null;

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
     * The network option, with every part present.
     *
     * @return array{values:array,applied:string[],enforced:array<array>,version:int}
     */
    public static function stored() {
        if (null === self::$stored) {
            $raw          = is_multisite() ? get_site_option(self::OPTION, array()) : array();
            $raw          = is_array($raw) ? $raw : array();
            self::$stored = array(
                'values'   => isset($raw['values']) && is_array($raw['values']) ? $raw['values'] : array(),
                'applied'  => isset($raw['applied']) && is_array($raw['applied']) ? array_values(array_filter($raw['applied'], 'is_string')) : array(),
                'enforced' => isset($raw['enforced']) && is_array($raw['enforced']) ? array_filter($raw['enforced'], 'is_array') : array(),
                'version'  => isset($raw['version']) ? (int) $raw['version'] : 0,
            );
        }
        return self::$stored;
    }

    /**
     * Forget what this request read, after a change.
     */
    private static function forget() {
        self::$stored      = null;
        self::$enforced    = null;
        self::$differences = null;
    }

    /**
     * Values every site uses because their card is applied, by key. Empty on
     * single sites.
     *
     * @return array
     */
    public static function enforced() {
        if (null === self::$enforced) {
            self::$enforced = is_multisite() ? self::flatten(self::stored()['enforced']) : array();
        }
        return self::$enforced;
    }

    /**
     * One array of key => value from the enforced values of each card.
     *
     * @param array $cards Card key => (key => value).
     * @return array
     */
    private static function flatten(array $cards) {
        $flat = array();
        foreach ($cards as $values) {
            if (is_array($values)) {
                $flat = array_merge($flat, $values);
            }
        }
        return $flat;
    }

    /**
     * Whether the network sets a setting for every site.
     *
     * @param string $key Setting key.
     * @return bool
     */
    public static function is_enforced($key) {
        return is_multisite() && array_key_exists((string) $key, self::enforced());
    }

    /**
     * Whether a card is applied to every site.
     *
     * @param string $key Card's setting key.
     * @return bool
     */
    public static function is_applied($key) {
        return in_array((string) $key, self::stored()['applied'], true);
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
     * Whether a setting can be set for the network: not a Media Library
     * picture (each site has its own), hidden wiring or a field marked
     * 'network' => false, and for a child setting, its parent can be too.
     *
     * @param string $key Setting key.
     * @return bool
     */
    public static function eligible($key) {
        $schema = WPStarter_Settings::schema();
        if (!isset($schema[$key])) {
            return false;
        }
        $field = $schema[$key];
        if ((isset($field['network']) && false === $field['network']) || !empty($field['hidden']) || (isset($field['type']) && 'media' === $field['type'])) {
            return false;
        }
        if (!empty($field['parent'])) {
            return (string) $field['parent'] !== (string) $key && self::eligible((string) $field['parent']);
        }
        return !empty($field['tab']);
    }

    /**
     * A card's settings the network can set: its own key and its eligible
     * child settings.
     *
     * @param string $key Card's setting key.
     * @return string[]
     */
    public static function card_keys($key) {
        if (!self::eligible($key)) {
            return array();
        }
        $keys = array((string) $key);
        foreach (array_keys(WPStarter_Settings::children_of($key)) as $child) {
            if (self::eligible((string) $child)) {
                $keys[] = (string) $child;
            }
        }
        return $keys;
    }

    /**
     * Top-level settings of a tab that the network screen shows.
     *
     * @param string $tab Tab slug.
     * @return array
     */
    public static function fields_for_tab($tab) {
        return array_filter(WPStarter_Settings::fields_for_tab($tab), function ($key) {
            return self::eligible((string) $key);
        }, ARRAY_FILTER_USE_KEY);
    }

    /**
     * A setting's network value: as saved on the network screen, else its
     * default.
     *
     * @param string $key Setting key.
     * @return mixed
     */
    public static function value($key) {
        $values = self::stored()['values'];
        if (array_key_exists($key, $values)) {
            return $values[$key];
        }
        $defaults = WPStarter_Settings::defaults();
        return array_key_exists($key, $defaults) ? $defaults[$key] : null;
    }

    /**
     * Save a setting's network value. While its card is applied, every site
     * uses it.
     *
     * @param string $key   Setting key.
     * @param mixed  $value Raw value.
     * @return mixed|WP_Error Sanitized value.
     */
    public static function set_value($key, $value) {
        if (!self::eligible($key)) {
            return new WP_Error('wpstarter_unknown_setting', __('This setting is set on each site.', 'wp-plugin-starter-template'));
        }
        $schema  = WPStarter_Settings::schema();
        $clean   = WPStarter_Settings::sanitize_value($value, $schema[$key]);
        $network = self::stored();

        $network['values'][$key] = $clean;
        return self::save($network) ? $clean : new WP_Error('wpstarter_not_saved', __('The setting could not be saved. Please try again.', 'wp-plugin-starter-template'));
    }

    /**
     * Apply a card to every site, or stop applying it.
     *
     * @param string $key   Card's setting key.
     * @param bool   $apply Whether to apply it.
     * @return bool|WP_Error
     */
    public static function apply($key, $apply) {
        // A card can always stop applying, even once its feature is gone.
        if ($apply && !self::card_keys($key)) {
            return new WP_Error('wpstarter_unknown_setting', __('This setting is set on each site.', 'wp-plugin-starter-template'));
        }
        $network            = self::stored();
        $network['applied'] = array_values(array_diff($network['applied'], array((string) $key)));
        if ($apply) {
            $network['applied'][] = (string) $key;
        }
        return self::save($network) ? true : new WP_Error('wpstarter_not_saved', __('The setting could not be saved. Please try again.', 'wp-plugin-starter-template'));
    }

    /**
     * Store the network option, with the enforced values worked out again
     * and the version raised when they changed.
     *
     * @param array $network The network option (stored()).
     * @return bool Whether it is stored.
     */
    private static function save(array $network) {
        $before              = self::stored()['enforced'];
        $network['enforced'] = self::enforced_for($network['applied'], $network['values'], $before);
        if ($network['enforced'] != $before) { // phpcs:ignore Universal.Operators.StrictComparisons -- key order may differ.
            $network['version'] = (int) $network['version'] + 1;
        }
        update_site_option(self::OPTION, $network);
        self::forget();
        return self::stored() == $network; // phpcs:ignore Universal.Operators.StrictComparisons -- key order may differ.
    }

    /**
     * The values every site uses for each applied card. A card whose
     * feature is not registered on this request keeps the values it had.
     *
     * @param string[] $applied Applied cards.
     * @param array    $values  Network values.
     * @param array    $before  Enforced values until now.
     * @return array<string,array>
     */
    private static function enforced_for(array $applied, array $values, array $before) {
        $defaults = WPStarter_Settings::defaults();
        $enforced = array();
        foreach ($applied as $card) {
            if (!array_key_exists($card, $defaults)) {
                if (isset($before[$card])) {
                    $enforced[$card] = $before[$card];
                }
                continue;
            }
            foreach (self::card_keys($card) as $key) {
                $enforced[$card][$key] = array_key_exists($key, $values) ? $values[$key] : $defaults[$key];
            }
        }
        return $enforced;
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
        foreach (self::stored()['values'] as $key => $value) {
            $key = (string) $key;
            if (array_key_exists($key, $options) || !self::eligible($key)) {
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
        $seen = is_array($seen) ? $seen : array();
        return array(
            'version'  => isset($seen['version']) ? (int) $seen['version'] : 0,
            'enforced' => isset($seen['enforced']) && is_array($seen['enforced']) ? $seen['enforced'] : array(),
            'before'   => isset($seen['before']) && is_array($seen['before']) ? $seen['before'] : array(),
        );
    }

    /**
     * Run this site's saving work for changes the network made since the
     * last time: a card applied, changed or no longer applied, Make every
     * site the same, or the values a new site started with. Only on admin
     * screens, cron and WP-CLI, so a visitor's page or AJAX request never
     * waits on it; the values themselves apply at once.
     */
    public static function sync() {
        if (wp_installing() || !((is_admin() && !wp_doing_ajax()) || wp_doing_cron() || (defined('WP_CLI') && WP_CLI))) {
            return;
        }
        $network = self::stored();
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
        $old    = array_merge(
            WPStarter_Settings::own(),
            array_intersect_key($seen['before'], $schema),
            array_intersect_key(self::flatten($seen['enforced']), $schema)
        );
        $new = WPStarter_Settings::all();

        $changed = array();
        foreach ($new as $key => $value) {
            if (!WPStarter_Settings::same(array_key_exists($key, $old) ? $old[$key] : null, $value)) {
                $changed[$key] = $value;
            }
        }
        if ($changed) {
            self::as_nobody(function () use ($old, $new, $changed) {
                /** This action is documented in includes/class-wpstarter-settings.php */
                do_action('wpstarter_settings_changed', $old, $new);
                foreach ($changed as $key => $value) {
                    /** This action is documented in includes/class-wpstarter-settings.php */
                    do_action('wpstarter_setting_saved', $key, $value);
                }
            });
        }
    }

    /**
     * Run saving work as nobody, as WP-CLI and cron do: the network made
     * the change, not the person whose request runs it.
     *
     * @param callable $work Work to run.
     */
    private static function as_nobody(callable $work) {
        $user          = get_current_user_id();
        self::$syncing = true;
        if ($user) {
            wp_set_current_user(0);
        }
        try {
            $work();
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
            if (empty($field['parent']) && self::eligible((string) $key)) {
                $cards[(string) $key] = self::card_keys((string) $key);
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
     * @param string[] $keys     The card's keys (card_keys()).
     * @param array    $options  The site's stored settings.
     * @param array    $defaults Defaults.
     * @return bool
     */
    private static function card_differs(array $keys, array $options, array $defaults) {
        foreach ($keys as $key) {
            $own = array_key_exists($key, $options) ? $options[$key] : $defaults[$key];
            if (!WPStarter_Settings::same($own, self::value($key))) {
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
        $keys = self::card_keys($key);
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
            $values[$card_key] = self::value($card_key);
        }

        $changed = 0;
        foreach ($ids as $id) {
            $previous = WPStarter_Settings::replace_site_values($id, $values);
            if ($previous) {
                self::remember($id, $previous);
                $changed++;
            }
        }
        self::$differences = null;
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
