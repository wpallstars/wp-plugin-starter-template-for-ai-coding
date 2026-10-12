<?php
/**
 * WP Plugin Starter sites that differ from the network (multisite).
 *
 * The network screen names the sites whose own values differ from the
 * network values (WPStarter_Network_Settings) for each card
 * (differences()), and Make every site the same copies a card's network
 * values into every site's own settings once (copy()); each site then runs
 * its saving work (WPStarter_Network_Sites::sync()). Both read and write
 * each site's options table directly: switching to each site would load
 * all of its autoloaded options.
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

class WPStarter_Network_Differences {

    /** Most sites the network screen compares or changes in one request. */
    const MAX_SITES = 500;

    /**
     * Sites that differ, per card, for this request (differences()).
     *
     * @var array{checked:bool,total:int,cards:array<string,int[]>,sites:array<int,array{name:string,url:string}>}|null
     */
    private static $differences = null;

    /**
     * Forget the sites that differ, read for this request, after the
     * network values or the sites' own values changed.
     */
    public static function forget() {
        self::$differences = null;
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

        $cards    = self::cards();
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
     * The cards the network screen shows, each with the settings the
     * network can set on it (WPStarter_Network_Settings::card_keys()).
     *
     * @return array<string,string[]>
     */
    private static function cards() {
        $cards = array();
        foreach (WPStarter_Settings::schema() as $key => $field) {
            if (empty($field['parent']) && WPStarter_Network_Settings::eligible((string) $key)) {
                $cards[(string) $key] = WPStarter_Network_Settings::card_keys((string) $key);
            }
        }
        return $cards;
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
     * saving work on its next admin, cron or WP-CLI request
     * (WPStarter_Network_Sites::sync()); sites can change the values again
     * afterwards unless the card is applied.
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
            // Also keeps the site's values from before, under the same lock
            // (WPStarter_Network_Sites::remember()).
            if (WPStarter_Settings::replace_site_values($id, $values)) {
                $changed++;
            }
        }
        self::forget();
        return $changed;
    }
}
