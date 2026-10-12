<?php
/**
 * WP Plugin Starter settings store.
 *
 * Every setting lives in a single `wpstarter_options` array and is described
 * by a schema entry (type, default, UI metadata) declared by its feature.
 * Features read values with WPStarter_Settings::get(); the admin UI renders
 * cards from the same schema; the AJAX endpoint and the Settings API sanitize
 * through it. Add settings with the `wpstarter_settings_schema` filter or by
 * registering a feature (see WPStarter_Feature).
 *
 * On multisite, values the network applies to every site
 * (WPStarter_Network_Settings) take the place of the site's own when read;
 * the option keeps only the site's own values.
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

class WPStarter_Settings {

    /** Option that stores every setting. */
    const OPTION = 'wpstarter_options';

    /** Settings API group. */
    const GROUP = 'wpstarter_settings';

    /** Nonce action shared by admin AJAX requests. */
    const NONCE = 'wpstarter_admin';

    /** Stored schema version, used for one-off migrations. */
    const DB_VERSION_OPTION = 'wpstarter_db_version';

    /** Current schema version; its history is in WPStarter_Setup. */
    const DB_VERSION = WPStarter_Setup::DB_VERSION;

    /** Seconds after which a save lock is taken as left behind (see lock()). */
    const LOCK_TIMEOUT = 10;

    /** Sanitizer for each field type (sanitize_value()); any other type is text. */
    private const SANITIZERS = array(
        'bool'    => 'sanitize_bool',
        'int'     => 'sanitize_int',
        'domains' => 'sanitize_domains',
        'media'   => 'sanitize_media',
        'select'  => 'sanitize_select',
        'multi'   => 'sanitize_multi',
        'times'   => 'sanitize_times',
        'url'     => 'sanitize_url',
        'lines'   => 'sanitize_lines',
    );

    /**
     * Request-level cache of the resolved schema.
     *
     * @var array|null
     */
    private static $schema = null;

    /**
     * Request-level cache of defaults.
     *
     * @var array|null
     */
    private static $defaults = null;

    /**
     * The value of the save lock this request holds, or '' (see lock()).
     *
     * @var string
     */
    private static $lock_value = '';

    /**
     * The options table holding that lock (see lock()).
     *
     * @var string
     */
    private static $lock_table = '';

    /**
     * That lock's name (see lock()).
     *
     * @var string
     */
    private static $lock_name = '';

    /**
     * Whether maybe_migrate() is storing migrated settings (see sanitize_all()).
     *
     * @var bool
     */
    private static $migrating = false;

    /**
     * Register hooks.
     */
    public static function init() {
        // Priority 0, before WPStarter::boot_features() so features read
        // migrated values, and before widgets_init (init:1).
        add_action('init', array(__CLASS__, 'maybe_migrate'), 0);
        add_action('admin_init', array(__CLASS__, 'register_setting'));
        add_action('wp_ajax_wpstarter_save_setting', array(__CLASS__, 'ajax_save'));
        add_action('update_option_' . self::OPTION, array(__CLASS__, 'option_updated'), 10, 2);
        add_filter('option_page_capability_' . self::GROUP, array(__CLASS__, 'capability'));
        WPStarter_Network_Sites::init();
    }

    /**
     * Whether the current user may change WP Plugin Starter's settings.
     *
     * @return bool
     */
    public static function can_change() {
        /**
         * Filter whether the current user may change WP Plugin Starter's settings
         * (on top of the manage_options check).
         *
         * @param bool $can Whether they may.
         */
        return current_user_can('manage_options') && (bool) apply_filters('wpstarter_can_change_settings', true);
    }

    /**
     * Capability options.php checks before saving the settings.
     *
     * @param string $capability Capability.
     * @return string
     */
    public static function capability($capability) {
        return self::can_change() ? $capability : 'do_not_allow';
    }

    /**
     * Setting definitions, collected from the registered features.
     *
     * Keys:
     * - type:        bool | int | text | domains | select | multi | times
     * - default:     default value
     * - tab:         admin tab slug (top-level settings only)
     * - parent:      parent setting key (renders inside the parent's panel)
     * - options:     value => label array, or a callable returning one (select, multi)
     * - open:        multi only; also keep key-like values that are not (yet)
     *                in options, e.g. post types or widgets registered later
     * - replaces:    top-level only; plugin slug => name this setting replaces
     * - panel:       top-level only; true to show the Options panel even with
     *                no visible child settings, for a feature that renders its
     *                own controls there (wpstarter_setting_panel)
     * - hidden:      child only; true for wiring set by starter data or code,
     *                which the panel does not show
     * - locked:      multi only; values (or a callable returning them) that
     *                are always chosen: shown ticked, cannot be unticked and
     *                are never stored, so the feature itself must treat
     *                them as chosen (locked_values())
     * - network:     false for a setting that only makes sense on each site
     *                (such as one listing the site's own posts or people):
     *                the network screen leaves it out (multisite)
     * - reload:      true when the change shows only after a page load; the
     *                saved message then asks to reload the page
     * - label, description, placeholder, min, max, unit, tokens, rows: UI metadata
     *
     * Types also include `url` (one URL or site path), `lines` (one entry
     * per line, sanitized as plain text) and `media` (a Media Library
     * picture's ID, chosen with the media dialog).
     *
     * @return array<string,array>
     */
    public static function schema() {
        if (null !== self::$schema) {
            return self::$schema;
        }

        $schema = array();
        foreach (WPStarter::features() as $class) {
            $schema += (array) $class::settings();
        }

        /**
         * Filter the settings schema to add or adjust settings.
         *
         * @param array $schema Setting definitions keyed by setting key.
         */
        $schema = (array) apply_filters('wpstarter_settings_schema', $schema);

        foreach ($schema as $key => $field) {
            if (isset($field['tab']) && is_string($field['tab'])) {
                $schema[$key]['tab'] = self::resolve_tab($field['tab']);
            }
        }

        self::$schema = $schema;

        return self::$schema;
    }

    /**
     * Resolve a select/multi field's options.
     *
     * Options may be a callable so they can depend on data registered at
     * `init` (post types, roles) without building it for every request.
     *
     * @param array $field Schema entry.
     * @return array<string,string> value => label
     */
    public static function options_for(array $field) {
        if (empty($field['options'])) {
            return array();
        }
        try {
            $options = is_callable($field['options']) ? call_user_func($field['options']) : $field['options'];
        } catch (\Throwable $e) {
            // A broken option source must not stop settings migrations or page loads.
            return array();
        }
        return is_array($options) ? $options : array();
    }

    /**
     * A multi field's locked values: always chosen, never stored.
     *
     * @param array $field Schema entry.
     * @return string[]
     */
    public static function locked_values(array $field) {
        if (empty($field['locked'])) {
            return array();
        }
        try {
            $locked = is_callable($field['locked']) ? call_user_func($field['locked']) : $field['locked'];
        } catch (\Throwable $e) {
            return array();
        }
        return array_values(array_unique(array_map('strval', array_filter((array) $locked, 'is_scalar'))));
    }

    /**
     * Default values for every setting.
     *
     * @return array
     */
    public static function defaults() {
        if (null === self::$defaults) {
            self::$defaults = array();
            foreach (self::schema() as $key => $field) {
                self::$defaults[$key] = isset($field['default']) ? $field['default'] : null;
            }
        }
        return self::$defaults;
    }

    /**
     * All settings merged over defaults, with the values the network
     * applies to every site in place of the site's own (multisite).
     *
     * @return array
     */
    public static function all() {
        return self::effective(self::stored_all());
    }

    /**
     * The site's own settings merged over defaults, without the values the
     * network applies: what the site gets back when the network stops
     * applying them.
     *
     * @return array
     */
    public static function own() {
        return array_merge(self::defaults(), array_intersect_key(self::stored_all(), self::schema()));
    }

    /**
     * Stored settings as features read them: over defaults, with the values
     * the network applies to every site.
     *
     * @param array $stored Stored settings.
     * @return array
     */
    private static function effective(array $stored) {
        $all = array_merge(self::defaults(), array_intersect_key($stored, self::schema()));
        return is_multisite() ? array_merge($all, array_intersect_key(WPStarter_Network_Settings::enforced(), $all)) : $all;
    }

    /**
     * After the option is updated, tell features what changed, as they read
     * it (with the network's values), so a change only to a value the
     * network overrides is no change.
     *
     * @param mixed $old Old value.
     * @param mixed $new New value.
     */
    public static function option_updated($old, $new) {
        $old = self::effective(is_array($old) ? $old : array());
        $new = self::effective(is_array($new) ? $new : array());
        if ($old != $new) { // phpcs:ignore Universal.Operators.StrictComparisons -- key order may differ.
            /**
             * Fires after settings change: saved in any way (the admin
             * screen, presets, WP-CLI, update_option()), or changed for this
             * site by the network (multisite, on the site's next admin, cron
             * or WP-CLI request). Use it instead of update_option_{option},
             * which misses the network's changes.
             *
             * @param array $old Settings before, as features read them.
             * @param array $new Settings after.
             */
            do_action('wpstarter_settings_changed', $old, $new);
        }
    }

    /**
     * Whether two setting values are the same: lists in any order, switches
     * as true or false, anything else as text.
     *
     * @param mixed $a Value.
     * @param mixed $b Value.
     * @return bool
     */
    public static function same($a, $b) {
        if (is_array($a) || is_array($b)) {
            $a = array_map('strval', array_filter((array) $a, 'is_scalar'));
            $b = array_map('strval', array_filter((array) $b, 'is_scalar'));
            sort($a);
            sort($b);
            return $a === $b;
        }
        if (is_bool($a) || is_bool($b)) {
            return (bool) $a === (bool) $b;
        }
        return (is_scalar($a) ? (string) $a : '') === (is_scalar($b) ? (string) $b : '');
    }

    /**
     * Everything stored in the option, including settings not registered on
     * this request (a feature added by another plugin that is switched off).
     *
     * @return array
     */
    private static function stored_all() {
        $stored = get_option(self::OPTION, array());
        return is_array($stored) ? $stored : array();
    }

    /**
     * Read one setting.
     *
     * @param string $key Setting key.
     * @return mixed Value, or null for unknown keys.
     */
    public static function get($key) {
        $all = self::all();
        return array_key_exists($key, $all) ? $all[$key] : null;
    }

    /**
     * Update one setting after sanitizing it.
     *
     * @param string $key   Setting key.
     * @param mixed  $value Raw value.
     * @return mixed|WP_Error Sanitized value, or error for unknown keys.
     */
    public static function set($key, $value) {
        $schema = self::schema();
        if (!isset($schema[$key])) {
            return new WP_Error('wpstarter_unknown_setting', __('Unknown setting.', 'wp-plugin-starter-template'));
        }
        if (WPStarter_Network_Settings::is_enforced($key)) {
            return new WP_Error('wpstarter_network_setting', __('The network administrator sets this for every site, so it cannot be changed here.', 'wp-plugin-starter-template'));
        }

        $clean = self::sanitize_value($value, $schema[$key]);

        // Every setting is in one option, so a save reads it, changes one key
        // and writes it all back. The lock stops two saves at once (two tabs,
        // two admins) each writing back a copy without the other's change.
        if (!self::lock()) {
            return new WP_Error('wpstarter_not_saved', __('The setting could not be saved. Please try again.', 'wp-plugin-starter-template'));
        }
        try {
            // Read what is stored now, not the copy loaded when this request
            // began, so a save made meanwhile is not overwritten. Keep the
            // settings not registered on this request (sanitize_all()).
            self::flush_cache();
            $options       = array_merge(self::defaults(), self::stored_all());
            $options[$key] = $clean;
            update_option(self::OPTION, $options);
            $saved = self::stored($key, $clean);
        } finally {
            self::unlock();
        }

        if (!$saved) {
            return new WP_Error('wpstarter_not_saved', __('The setting could not be saved. Please try again.', 'wp-plugin-starter-template'));
        }
        return $clean;
    }

    /**
     * Store sanitized values as a site's own settings, for the network
     * (WPStarter_Network_Differences::copy()), under that site's save lock.
     * Read and written straight in its options table: switching to each
     * site would load all of its autoloaded options, and run this
     * request's hooks, which belong to another site; the site runs its own
     * saving work on its next request, for the values from before that are
     * kept under the same lock (WPStarter_Network_Sites::remember()), so
     * that work never misses them (WPStarter_Network_Sites::sync()). Sites
     * where the plugin has not run yet are left alone.
     *
     * @param int   $site_id Site ID.
     * @param array $values  Key => sanitized value.
     * @return array|null The site's values before, of the keys that
     *                    changed; null when it has no stored settings or
     *                    they could not be saved.
     */
    public static function replace_site_values($site_id, array $values) {
        global $wpdb;
        $table = $wpdb->get_blog_prefix((int) $site_id) . 'options';
        if (!self::lock($table)) {
            return null;
        }
        try {
            // phpcs:ignore WordPress.DB.DirectDatabaseQuery -- another site's options, read past this request's caches (see above).
            $raw    = $wpdb->get_var($wpdb->prepare('SELECT option_value FROM %i WHERE option_name = %s', $table, self::OPTION));
            $stored = null === $raw ? null : maybe_unserialize($raw);
            if (!is_array($stored)) {
                return null;
            }
            $defaults = self::defaults();
            $previous = array();
            foreach ($values as $key => $value) {
                $was = array_key_exists($key, $stored) ? $stored[$key] : ($defaults[$key] ?? null);
                if (!self::same($was, $value)) {
                    $previous[$key] = $was;
                    $stored[$key]   = $value;
                }
            }
            if ($previous) {
                // phpcs:ignore WordPress.DB.DirectDatabaseQuery -- as above; the site's caches are cleared next.
                if (false === $wpdb->update($table, array('option_value' => maybe_serialize($stored)), array('option_name' => self::OPTION))) {
                    return null;
                }
                WPStarter_Network_Sites::flush_site_cache((int) $site_id, array(self::OPTION));
                WPStarter_Network_Sites::remember((int) $site_id, $previous);
            }
            return $previous;
        } finally {
            self::unlock();
        }
    }

    /**
     * Take the save lock: a row in the options table that only one request
     * can insert (INSERT IGNORE, as WP_Upgrader::create_lock() does;
     * add_option() checks then writes, so two requests can both "add" it).
     * Waits up to about five seconds; a lock older than LOCK_TIMEOUT seconds
     * was left by a request that stopped, and is taken over.
     *
     * The value is the time and a value unique to this request, so a request
     * deletes only the lock it read or holds: of two requests that find the
     * same stale lock, only one deletes it, and a request whose lock was
     * taken over does not delete the new one.
     *
     * @param string $table Options table: this site's, or another site's
     *                      (replace_site_values(), under_lock()).
     * @param string $name  Lock name: the settings' own, or another
     *                      (under_lock()).
     * @return bool Whether this request holds the lock.
     */
    private static function lock($table = '', $name = '') {
        global $wpdb;
        $table = '' === $table ? $wpdb->options : $table;
        $name  = '' === $name ? self::OPTION . '_lock' : $name;
        $value = time() . ' ' . wp_generate_uuid4();
        for ($try = 0; $try < 50; $try++) {
            // phpcs:ignore WordPress.DB.DirectDatabaseQuery -- an atomic insert is the lock; the options API cannot do it.
            if ($wpdb->query($wpdb->prepare("INSERT IGNORE INTO %i (option_name, option_value, autoload) VALUES (%s, %s, 'no')", $table, $name, $value))) {
                self::$lock_value = $value;
                self::$lock_table = $table;
                self::$lock_name  = $name;
                return true;
            }
            // phpcs:ignore WordPress.DB.DirectDatabaseQuery -- read past the options cache: the lock changes under it.
            $held  = (string) $wpdb->get_var($wpdb->prepare('SELECT option_value FROM %i WHERE option_name = %s', $table, $name));
            $since = (int) strtok($held, ' ');
            if ($since && $since < time() - self::LOCK_TIMEOUT) {
                self::delete_lock($held, $table, $name);
                continue;
            }
            usleep(100000);
        }
        return false;
    }

    /**
     * Release the save lock this request holds.
     */
    private static function unlock() {
        if ('' !== self::$lock_value) {
            self::delete_lock(self::$lock_value, self::$lock_table, self::$lock_name);
            self::$lock_value = '';
            self::$lock_table = '';
            self::$lock_name  = '';
        }
    }

    /**
     * Delete a save lock if it still has the given value.
     *
     * @param string $value Lock value.
     * @param string $table Options table holding it.
     * @param string $name  Lock name.
     */
    private static function delete_lock($value, $table, $name) {
        global $wpdb;
        // phpcs:ignore WordPress.DB.DirectDatabaseQuery -- the lock row is never cached (see lock()).
        $wpdb->query($wpdb->prepare('DELETE FROM %i WHERE option_name = %s AND option_value = %s', $table, $name, $value));
    }

    /**
     * Run a change under a save lock (lock()), released however the change
     * ends: one of its own, for an option kept outside this site's
     * settings, such as the network option
     * (WPStarter_Network_Settings::change()); or, with no table and name,
     * this site's save lock, for an option the network also writes under it
     * (WPStarter_Network_Sites::sync()). The change must not save settings
     * itself (set()): it would wait on the lock it is under.
     *
     * @param callable $change The change; its result is returned.
     * @param string   $table  Options table to hold the lock in; '' for this site's.
     * @param string   $name   Lock name; '' for the settings' save lock.
     * @return mixed|null The change's result, or null when the lock could
     *                    not be taken.
     */
    public static function under_lock(callable $change, $table = '', $name = '') {
        if (!self::lock($table, $name)) {
            return null;
        }
        try {
            return $change();
        } finally {
            self::unlock();
        }
    }

    /**
     * Drop cached copies of the settings so the next read hits the database.
     */
    private static function flush_cache() {
        wp_cache_delete(self::OPTION, 'options');
        wp_cache_delete('alloptions', 'options');
    }

    /**
     * Whether the database holds a value for a setting (update_option()
     * returns false both for "unchanged" and for a failed write).
     *
     * @param string $key   Setting key.
     * @param mixed  $value Expected value.
     * @return bool
     */
    private static function stored($key, $value) {
        self::flush_cache();
        $stored = get_option(self::OPTION);
        return is_array($stored) && array_key_exists($key, $stored) && $stored[$key] === $value;
    }

    /**
     * Top-level settings for a tab.
     *
     * @param string $tab Tab slug.
     * @return array
     */
    public static function fields_for_tab($tab) {
        return array_filter(self::schema(), function ($field) use ($tab) {
            return empty($field['parent']) && isset($field['tab']) && $field['tab'] === $tab;
        });
    }

    /**
     * Map a renamed tab slug to its current slug
     * (WPStarter_Setup::RENAMED_TABS).
     *
     * @param string $tab Tab slug.
     * @return string
     */
    public static function resolve_tab($tab) {
        $renamed = WPStarter_Setup::RENAMED_TABS;
        return array_key_exists($tab, $renamed) ? $renamed[$tab] : $tab;
    }

    /**
     * Top-level settings that match a search, in schema order.
     *
     * Matches the label, description, replaced plugin names and the labels
     * of child options, ignoring case.
     *
     * @param string $query Search text.
     * @return array
     */
    public static function search($query) {
        $query = trim((string) $query);
        if ('' === $query) {
            return array();
        }

        $matches = array();
        foreach (self::schema() as $key => $field) {
            if (empty($field['parent']) && !empty($field['tab']) && self::contains(self::search_text($key, $field), $query)) {
                $matches[$key] = $field;
            }
        }

        return $matches;
    }

    /**
     * What search() looks in for a top-level setting: its key, label,
     * description, replaced plugins and its visible child settings' labels.
     *
     * @param string $key   Setting key.
     * @param array  $field Schema entry.
     * @return string
     */
    private static function search_text($key, array $field) {
        $haystack = array(
            $key,
            isset($field['label']) ? $field['label'] : '',
            isset($field['description']) ? $field['description'] : '',
        );
        if (!empty($field['replaces']) && is_array($field['replaces'])) {
            $haystack = array_merge($haystack, array_keys($field['replaces']), array_values($field['replaces']));
        }
        foreach (self::children_of($key) as $child) {
            $haystack[] = isset($child['label']) && empty($child['hidden']) ? (string) $child['label'] : '';
        }
        return implode(' ', array_map('strval', $haystack));
    }

    /**
     * Whether text contains a query, ignoring case (multibyte when it can).
     *
     * @param string $text  Text.
     * @param string $query Query.
     * @return bool
     */
    private static function contains($text, $query) {
        return false !== (function_exists('mb_stripos') ? mb_stripos($text, $query) : stripos($text, $query));
    }

    /**
     * Child settings rendered in a parent's panel.
     *
     * @param string $parent Parent setting key.
     * @return array
     */
    public static function children_of($parent) {
        return array_filter(self::schema(), function ($field) use ($parent) {
            return isset($field['parent']) && $field['parent'] === $parent;
        });
    }

    /**
     * The card a setting is on: its own key, or its parent's.
     *
     * @param string $key Setting key.
     * @return string
     */
    public static function card_of($key) {
        $schema = self::schema();
        return !empty($schema[$key]['parent']) ? (string) $schema[$key]['parent'] : (string) $key;
    }

    /**
     * Sanitize a value according to its schema entry.
     *
     * Must be idempotent: update_option() re-runs sanitize_all() on the
     * already-sanitized array.
     *
     * @param mixed $value Raw value.
     * @param array $field Schema entry.
     * @return mixed
     */
    public static function sanitize_value($value, array $field) {
        $type   = isset($field['type']) ? $field['type'] : 'text';
        $method = isset(self::SANITIZERS[$type]) ? self::SANITIZERS[$type] : 'sanitize_text';
        return self::$method($value, $field);
    }

    /**
     * A field's default value.
     *
     * @param array $field Schema entry.
     * @return mixed
     */
    private static function default_of(array $field) {
        return isset($field['default']) ? $field['default'] : null;
    }

    /**
     * A raw value as text: '' for an array or object, which no text-like
     * type accepts (a cast would give "Array" and a PHP notice).
     *
     * @param mixed $value Raw value.
     * @return string
     */
    private static function to_text($value) {
        return is_scalar($value) ? (string) $value : '';
    }

    /**
     * Sanitize a bool field.
     *
     * @param mixed $value Raw value.
     * @param array $field Schema entry (not needed for this type).
     * @return bool
     */
    private static function sanitize_bool($value, array $field) {
        // Core reads strings ('false', '0'); everything else is a plain cast.
        return is_string($value) ? rest_sanitize_boolean($value) : (bool) $value;
    }

    /**
     * Sanitize an int field: a number (else the default) within min and max.
     *
     * @param mixed $value Raw value.
     * @param array $field Schema entry.
     * @return int
     */
    private static function sanitize_int($value, array $field) {
        $value = is_numeric($value) ? (int) $value : (int) self::default_of($field);
        if (isset($field['min'])) {
            $value = max((int) $field['min'], $value);
        }
        if (isset($field['max'])) {
            $value = min((int) $field['max'], $value);
        }
        return $value;
    }

    /**
     * Sanitize a domains field: one bare host per line.
     *
     * @param mixed $value Raw value.
     * @param array $field Schema entry (not needed for this type).
     * @return string
     */
    private static function sanitize_domains($value, array $field) {
        return implode("\n", self::parse_domains($value));
    }

    /**
     * Sanitize a media field: a Media Library picture's ID, or 0.
     *
     * @param mixed $value Raw value.
     * @param array $field Schema entry (not needed for this type).
     * @return int
     */
    private static function sanitize_media($value, array $field) {
        $value = is_numeric($value) ? absint($value) : 0;
        return $value && wp_attachment_is_image($value) ? $value : 0;
    }

    /**
     * Sanitize a select field: one of its options, else the default.
     *
     * @param mixed $value Raw value.
     * @param array $field Schema entry.
     * @return mixed
     */
    private static function sanitize_select($value, array $field) {
        $value = is_scalar($value) ? (string) $value : '';
        if (array_key_exists($value, self::options_for($field))) {
            return $value;
        }
        // Open selects (another plugin's board or course) keep an
        // identifier whose plugin is not loaded on this request.
        return !empty($field['open']) && strlen($value) <= 200 && preg_match('/^[A-Za-z0-9_-]+$/', $value) ? $value : self::default_of($field);
    }

    /**
     * Sanitize a multi field: its options that are chosen, in the options'
     * order; open lists also keep other identifiers. Locked values are
     * always chosen, so they are not stored (locked_values()).
     *
     * @param mixed $value Raw value: an array or a comma separated list.
     * @param array $field Schema entry.
     * @return string[]
     */
    private static function sanitize_multi($value, array $field) {
        $values = is_array($value) ? $value : preg_split('/\s*,\s*/', (string) $value, -1, PREG_SPLIT_NO_EMPTY);
        $values = array_map('strval', array_filter((array) $values, 'is_scalar'));
        if (!empty($field['locked'])) {
            $values = array_diff($values, self::locked_values($field));
        }
        // Keep the options' order so stored values are stable.
        $known = array_values(array_intersect(array_map('strval', array_keys(self::options_for($field))), $values));
        if (empty($field['open'])) {
            return $known;
        }
        // Open lists also keep identifiers that are not registered right now
        // (class names may contain namespace separators).
        $extra = array_filter(array_diff($values, $known), function ($item) {
            return strlen($item) <= 200 && (bool) preg_match('/^[A-Za-z0-9_\\\\-]+$/', $item);
        });
        return array_values(array_unique(array_merge($known, $extra)));
    }

    /**
     * Sanitize a times field: sorted 24-hour times, comma separated.
     *
     * @param mixed $value Raw value.
     * @param array $field Schema entry (not needed for this type).
     * @return string
     */
    private static function sanitize_times($value, array $field) {
        return implode(', ', self::parse_times($value));
    }

    /**
     * Sanitize a url field: an http(s) URL, or a site path kept relative so
     * it survives domain changes.
     *
     * @param mixed $value Raw value.
     * @param array $field Schema entry (not needed for this type).
     * @return string
     */
    private static function sanitize_url($value, array $field) {
        $value = trim(self::to_text($value));
        // Browsers read "/\" as "//", another site; no URL needs a backslash.
        if ('' === $value || false !== strpos($value, '\\')) {
            return '';
        }
        if ('/' === $value[0] && '/' !== substr($value, 1, 1)) {
            return '/' . ltrim((string) preg_replace('/\s+/', '', sanitize_text_field($value)), '/');
        }
        return esc_url_raw($value, array('http', 'https'));
    }

    /**
     * Sanitize a lines field: unique plain-text lines.
     *
     * @param mixed $value Raw value.
     * @param array $field Schema entry (not needed for this type).
     * @return string
     */
    private static function sanitize_lines($value, array $field) {
        $lines = preg_split('/[\r\n]+/', self::to_text($value)) ?: array();
        // Not sanitize_text_field(): it strips %xx, which URL paths need.
        $lines = array_filter(array_map(function ($line) {
            return trim((string) preg_replace('/[\x00-\x1F\x7F]+/', '', wp_strip_all_tags($line)));
        }, $lines), function ($line) {
            return '' !== $line;
        });
        return implode("\n", array_values(array_unique($lines)));
    }

    /**
     * Sanitize a text field, keeping its tokens (such as %date%).
     *
     * @param mixed $value Raw value.
     * @param array $field Schema entry.
     * @return string
     */
    private static function sanitize_text($value, array $field) {
        $value = self::to_text($value);
        if (empty($field['tokens'])) {
            return sanitize_text_field($value);
        }
        // sanitize_text_field() drops "%" plus two hex digits, which
        // breaks tokens such as %date% and %day%; set them aside.
        $tokens = array();
        foreach (array_values((array) $field['tokens']) as $i => $token) {
            $tokens["\u{E000}{$i}\u{E001}"] = (string) $token;
        }
        $value = str_replace(array_values($tokens), array_keys($tokens), $value);
        return str_replace(array_keys($tokens), array_values($tokens), sanitize_text_field($value));
    }

    /**
     * Normalise a newline/comma separated domain list to bare lowercase hosts.
     *
     * @param mixed $value Raw list.
     * @return string[]
     */
    public static function parse_domains($value) {
        $lines   = preg_split('/[\r\n,]+/', self::to_text($value)) ?: array();
        $domains = array();

        foreach ($lines as $line) {
            $line = trim($line);
            if ('' === $line) {
                continue;
            }
            // A bare domain gets a scheme-relative "//" so the host is found.
            $host = wp_parse_url(false === strpos($line, '://') ? '//' . $line : $line, PHP_URL_HOST);
            $host = $host ? strtolower((string) preg_replace('/^www\./i', '', $host)) : '';
            if ('' !== $host && preg_match('/^[a-z0-9.-]+$/', $host)) {
                $domains[] = $host;
            }
        }

        return array_values(array_unique($domains));
    }

    /**
     * Whether a host is one of the domains or a subdomain of one.
     *
     * @param string   $host    Host name.
     * @param string[] $domains Normalised domains from parse_domains().
     * @return bool
     */
    public static function host_matches($host, array $domains) {
        $host = strtolower((string) preg_replace('/^www\./i', '', (string) $host));
        foreach ($domains as $domain) {
            if ($host === $domain || substr($host, -strlen('.' . $domain)) === '.' . $domain) {
                return true;
            }
        }
        return false;
    }

    /**
     * Normalise a list of times of day to sorted, unique 24-hour "HH:MM".
     *
     * Accepts "9", "9:30", "09:30", "9.30", "9pm", "9:30 am" separated by
     * commas, spaces or new lines.
     *
     * @param mixed $value Raw list.
     * @return string[]
     */
    public static function parse_times($value) {
        preg_match_all('/(\d{1,2})(?:[:.](\d{2}))?\s*(am|pm)?/i', self::to_text($value), $matches, PREG_SET_ORDER);
        $times = array_values(array_unique(array_filter(array_map(array(__CLASS__, 'time_of'), $matches))));
        sort($times);
        return $times;
    }

    /**
     * One parse_times() match as "HH:MM", or '' when it is not a time of day.
     *
     * @param array $match Hour, minutes and am/pm from parse_times().
     * @return string
     */
    private static function time_of(array $match) {
        $hour   = (int) $match[1];
        $minute = isset($match[2]) && '' !== $match[2] ? (int) $match[2] : 0;
        $hour   = self::hour_24($hour, isset($match[3]) ? strtolower($match[3]) : '');
        return $hour > 23 || $minute > 59 ? '' : sprintf('%02d:%02d', $hour, $minute);
    }

    /**
     * An hour on the 24-hour clock: 9 pm is 21, 12 am is 0.
     *
     * @param int    $hour   Hour as written.
     * @param string $suffix 'am', 'pm' or ''.
     * @return int
     */
    private static function hour_24($hour, $suffix) {
        if ('pm' === $suffix && $hour < 12) {
            return $hour + 12;
        }
        if ('am' === $suffix && 12 === $hour) {
            return 0;
        }
        return $hour;
    }

    /**
     * Sanitize the whole array when saved through options.php or
     * update_option(). Only the site's own values are stored: values the
     * network applies to every site are not (own()), and a save cannot
     * change the site's own value of a setting the network applies, as
     * set() cannot. Migrations store them, as a new site starts with the
     * network's values (WPStarter_Network_Sites::seed()).
     *
     * @param mixed $input Raw option value.
     * @return array
     */
    public static function sanitize_all($input) {
        $input    = is_array($input) ? $input : array();
        $schema   = self::schema();
        $stored   = self::stored_all();
        $clean    = self::own();
        $enforced = self::$migrating ? array() : WPStarter_Network_Settings::enforced();
        if (!self::$migrating) {
            // Settings not registered on this request (their feature is
            // switched off) keep their stored values, even when the input
            // leaves them out. Not while migrating: there a key left out
            // was removed by a migration.
            $clean = array_merge($clean, array_diff_key($stored, $schema));
        }

        foreach ($input as $key => $value) {
            if (array_key_exists($key, $enforced)) {
                continue;
            }
            if (isset($schema[$key])) {
                $clean[$key] = self::sanitize_value($value, $schema[$key]);
            } elseif (array_key_exists($key, $stored) && $stored[$key] === $value) {
                // An unregistered setting given with its stored value (as
                // set() and migrations pass it) is kept; new unknown keys
                // and changed values of unregistered ones are not stored.
                $clean[$key] = $value;
            }
        }

        return $clean;
    }

    /**
     * Register the option with the Settings API.
     */
    public static function register_setting() {
        register_setting(self::GROUP, self::OPTION, array(
            'type'              => 'object',
            'sanitize_callback' => array(__CLASS__, 'sanitize_all'),
            'default'           => self::defaults(),
            'show_in_rest'      => false,
        ));
    }

    /**
     * AJAX: save a single setting (used by instant-save controls).
     */
    public static function ajax_save() {
        check_ajax_referer(self::NONCE, 'nonce');

        if (!self::can_change()) {
            wp_send_json_error(array('message' => __('You are not allowed to change these settings.', 'wp-plugin-starter-template')), 403);
        }

        $key = isset($_POST['key']) ? sanitize_key(wp_unslash($_POST['key'])) : '';
        // phpcs:ignore WordPress.Security.ValidatedSanitizedInput.InputNotSanitized -- sanitized per schema in set().
        $raw = isset($_POST['value']) ? wp_unslash($_POST['value']) : '';

        $value = self::set($key, $raw);
        if (is_wp_error($value)) {
            wp_send_json_error(array('message' => $value->get_error_message()), 400);
        }

        /**
         * Fires after a setting is saved from the admin UI.
         *
         * @param string $key   Setting key.
         * @param mixed  $value Sanitized value.
         */
        do_action('wpstarter_setting_saved', $key, $value);

        $schema = self::schema();
        $reload = !empty($schema[$key]['reload']);
        wp_send_json_success(array(
            'key'     => $key,
            'value'   => $value,
            'message' => $reload ? __('Saved. Reload the page to see the change.', 'wp-plugin-starter-template') : __('Saved', 'wp-plugin-starter-template'),
            'reload'  => $reload,
        ));
    }

    /**
     * One-off migrations, once per DB_VERSION: WPStarter_Setup::migrate()
     * (imports that belong to no feature), then each feature's migrate().
     * The history of versions is in WPStarter_Setup::DB_VERSION.
     *
     * Old options are left in place so a downgrade keeps working;
     * uninstall.php removes ours. Other plugins' options are never touched.
     *
     * On multisite, a site where the plugin runs for the first time starts
     * with the values saved on the network screen, for anything not
     * imported (WPStarter_Network_Sites::seed()).
     */
    public static function maybe_migrate() {
        $from = (int) get_option(self::DB_VERSION_OPTION, 0);
        if ($from >= self::DB_VERSION) {
            return;
        }

        $options = get_option(self::OPTION, array());
        $options = is_array($options) ? $options : array();
        $options = (array) WPStarter_Setup::migrate($options, $from);

        foreach (WPStarter::features() as $class) {
            $options = (array) $class::migrate($options, $from);
        }
        if (0 === $from) {
            $options = WPStarter_Network_Sites::seed($options);
        }

        // Keys the migrations removed stay removed (see sanitize_all()),
        // also when update_option() runs it again.
        self::$migrating = true;
        try {
            $clean = self::sanitize_all($options);
            update_option(self::OPTION, $clean);
        } finally {
            self::$migrating = false;
        }

        // Only record the version once the settings are stored, so a failed
        // write is retried on the next request instead of losing imports.
        self::flush_cache();
        if (get_option(self::OPTION) != $clean) { // phpcs:ignore Universal.Operators.StrictComparisons -- key order may differ.
            return;
        }
        update_option(self::DB_VERSION_OPTION, self::DB_VERSION);
    }
}
