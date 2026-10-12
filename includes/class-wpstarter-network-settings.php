<?php
/**
 * WP Plugin Starter network settings (multisite).
 *
 * The network screen (Network Admin → Settings → WP Plugin Starter) saves
 * network values, kept in one network option. A card applied to every
 * site overrides each site's own values with the network's, and sites
 * cannot change them; when it stops applying, each site has its own values
 * again, as they were never overwritten. How the network values reach
 * each site (new sites start with them, and each site runs its saving
 * work for the network's changes) is in WPStarter_Network_Sites; the
 * sites whose own values differ, and Make every site the same, which
 * copies them once, are in WPStarter_Network_Differences.
 *
 * Settings that only make sense on each site are never set for the
 * network: Media Library pictures, hidden wiring, and fields with
 * 'network' => false in the schema (eligible()).
 *
 * Single sites never read the network option.
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
     * The network option's save lock: a row in the main site's options
     * table (change()).
     */
    const LOCK = 'wpstarter_network_lock';

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
     * The network option, with every part present.
     *
     * @return array{values:array,applied:string[],enforced:array<array>,version:int}
     */
    public static function stored() {
        if (null === self::$stored) {
            $raw          = is_multisite() ? get_site_option(self::OPTION, array()) : array();
            $raw          = (is_array($raw) ? $raw : array()) + array('values' => array(), 'applied' => array(), 'enforced' => array(), 'version' => 0);
            self::$stored = array(
                'values'   => is_array($raw['values']) ? $raw['values'] : array(),
                'applied'  => is_array($raw['applied']) ? array_values(array_filter($raw['applied'], 'is_string')) : array(),
                'enforced' => is_array($raw['enforced']) ? array_filter($raw['enforced'], 'is_array') : array(),
                'version'  => (int) $raw['version'],
            );
        }
        return self::$stored;
    }

    /**
     * Forget what this request read, after a change.
     */
    private static function forget() {
        self::$stored   = null;
        self::$enforced = null;
        WPStarter_Network_Differences::forget();
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
    public static function flatten(array $cards) {
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
        if (false === ($field['network'] ?? true) || !empty($field['hidden']) || 'media' === ($field['type'] ?? '')) {
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
        return WPStarter_Settings::defaults()[$key] ?? null;
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
        $schema = WPStarter_Settings::schema();
        $clean  = WPStarter_Settings::sanitize_value($value, $schema[$key]);
        $saved  = self::change(function (array $network) use ($key, $clean) {
            $network['values'][$key] = $clean;
            return $network;
        });
        return $saved ? $clean : new WP_Error('wpstarter_not_saved', __('The setting could not be saved. Please try again.', 'wp-plugin-starter-template'));
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
        $saved = self::change(function (array $network) use ($key, $apply) {
            $network['applied'] = array_values(array_diff($network['applied'], array((string) $key)));
            if ($apply) {
                $network['applied'][] = (string) $key;
            }
            return $network;
        });
        return $saved ? true : new WP_Error('wpstarter_not_saved', __('The setting could not be saved. Please try again.', 'wp-plugin-starter-template'));
    }

    /**
     * Change the network option and store it, under its save lock and from
     * what is stored now, not the copy this request read when it began: two
     * saves at once (two tabs, two network administrators) would otherwise
     * each write back a copy without the other's change. The lock is a row
     * in the main site's options table (WPStarter_Settings::under_lock()),
     * as the network option's own table has no unique key to lock with.
     *
     * @param callable $change Gets the network option (stored()) and returns
     *                         it changed.
     * @return bool Whether it is stored.
     */
    private static function change(callable $change) {
        global $wpdb;
        $table = $wpdb->get_blog_prefix(get_main_site_id()) . 'options';
        return true === WPStarter_Settings::under_lock(function () use ($change) {
            $network_id = get_current_network_id();
            wp_cache_delete($network_id . ':' . self::OPTION, 'site-options');
            wp_cache_delete($network_id . ':notoptions', 'site-options');
            self::forget();
            return self::save($change(self::stored()));
        }, $table, self::LOCK);
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
}
