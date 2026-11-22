<?php
/**
 * Licensed updates from the wpallstars.com shop (FluentCart Pro's licensing
 * API) for every installed plugin and theme that names a shop product.
 *
 * - Products: an installed plugin or theme whose header has
 *   `Update URI: https://www.wpallstars.com/` and `Licence Item: <id>`
 *   (the shop's product ID). Active or not, each is listed.
 * - Licences: one key per product for the site, or for the whole network on
 *   multisite (a network option; the activation's address is the network's
 *   main site). Entered in Settings → Licences (Network Admin on multisite)
 *   or with `wp wpallstars licence activate`, which reads the key from the
 *   WPALLSTARS_LICENCE_KEY environment variable or standard input, never an
 *   argument. Activating sends the key, the site's address and the
 *   WordPress, PHP and product versions; the answer is checked again once a
 *   day by WP-Cron. Visitor pages never read the licences or ask the shop.
 * - Updates: WordPress's update_plugins_{hostname} and
 *   update_themes_{hostname} filters for the Update URI's host, and
 *   plugins_api for View details, from the shop's version answer (cached
 *   for 12 hours). The package address is given to a licensed site only;
 *   nothing is asked before a key is entered. The licence gates updates
 *   only: without one a product keeps working and is offered nothing.
 *   On the shop's own WordPress install, the package is downloaded with
 *   maintenance mode lifted, since that install answers 503 to every
 *   request, the shop's too, while it is on.
 *
 * Keys and activation hashes are stored encrypted (sodium, with a key from
 * WPALLSTARS_LICENCE_ENCRYPTION_KEY when defined, else the site's AUTH_KEY
 * and AUTH_SALT) and are never printed: only their last four characters.
 * A copy of the site with new security keys cannot read them; its licences
 * show as unreadable until each key is activated again.
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

final class WPAllStars_Licence {

    /** The shop; its licensing API answers at ?fluent-cart=<action>. */
    const STORE = 'https://www.wpallstars.com/';

    /** The header naming a product's item in the shop. */
    const HEADER = 'Licence Item';

    /** The stored licences (network option on multisite): item ID => state. */
    const OPTION = 'wpallstars_licences';

    /** The daily check's WP-Cron hook. */
    const CRON_HOOK = 'wpallstars_licence_check';

    /** Prefix of each product's last version answer (network transient). */
    const UPDATE_CACHE = 'wpallstars_licence_update_';

    /** How long a version answer is kept, and a failed one. */
    const UPDATE_TTL   = 12 * HOUR_IN_SECONDS;
    const UPDATE_RETRY = HOUR_IN_SECONDS;

    /** Days a licence stays on after its expiry date, while a renewal reaches the shop. */
    const GRACE = 7 * DAY_IN_SECONDS;

    /** The admin screen's page slug and its admin-post action. */
    const PAGE   = 'wpallstars-licences';
    const ACTION = 'wpallstars_licence';

    /** Prefix of an encrypted value, so a later scheme can be told apart. */
    const CIPHER = 'v1:';

    /** The stored status when this site cannot decrypt a stored key. */
    const UNREADABLE = 'unreadable';

    /** Plugin images for the Updates screen, by WordPress's keys, best file first. */
    const IMAGES = array(
        'icons'   => array('svg' => array('icon.svg')),
        'banners' => array(
            'low'  => array('banner-details.svg', 'banner.svg'),
            'high' => array('banner-details.svg', 'banner.svg'),
        ),
    );

    /**
     * Products, once read.
     *
     * @var array<int,array{type:string,shop:bool,file:string,slug:string,name:string,version:string,dir:string,requires:string,requires_php:string}>|null
     */
    private static $products = null;

    /**
     * Register the hooks. Nothing here reads the database or asks the shop.
     */
    public static function load() {
        static $done = false;
        if ($done) {
            return;
        }
        $done = true;
        $host = (string) wp_parse_url(self::STORE, PHP_URL_HOST);
        add_action(self::CRON_HOOK, array(__CLASS__, 'scheduled_check'));
        add_filter('update_plugins_' . $host, array(__CLASS__, 'update_plugin'), 10, 3);
        add_filter('update_themes_' . $host, array(__CLASS__, 'update_theme'), 10, 3);
        add_filter('plugins_api', array(__CLASS__, 'details'), 10, 3);
        // Last: some updaters reset every earlier answer to false.
        add_filter('upgrader_pre_download', array(__CLASS__, 'download'), PHP_INT_MAX, 4);
        if (is_admin()) {
            add_action(is_multisite() ? 'network_admin_menu' : 'admin_menu', array(__CLASS__, 'menu'));
            add_action('admin_post_' . self::ACTION, array(__CLASS__, 'submit'));
            add_action('admin_init', array(__CLASS__, 'schedule'));
        }
        if (defined('WP_CLI') && WP_CLI && is_readable(__DIR__ . '/class-wpallstars-licence-cli.php')) {
            require_once __DIR__ . '/class-wpallstars-licence-cli.php';
            WPAllStars_Licence_CLI::register();
        }
    }

    // ------------------------------------------------------------------
    // Products.

    /**
     * Installed products sold through the shop: item ID => details. Every
     * plugin or theme with a Licence Item header is listed, so its licence
     * can be activated before it moves to the shop; 'shop' is whether its
     * Update URI is the shop's, which it needs for updates and View details.
     *
     * @return array<int,array{type:string,shop:bool,file:string,slug:string,name:string,version:string,dir:string,requires:string,requires_php:string}>
     */
    public static function products() {
        if (null !== self::$products) {
            return self::$products;
        }
        self::$products = array();
        if (!function_exists('get_plugins')) {
            require_once ABSPATH . 'wp-admin/includes/plugin.php';
        }
        foreach (get_plugins() as $file => $data) {
            $item = self::item_of(WP_PLUGIN_DIR . '/' . $file);
            if ($item > 0 && !isset(self::$products[$item])) {
                self::$products[$item] = array(
                    'type'         => 'plugin',
                    'shop'         => self::is_store_uri(isset($data['UpdateURI']) ? (string) $data['UpdateURI'] : ''),
                    'file'         => (string) $file,
                    'slug'         => dirname((string) $file),
                    'name'         => isset($data['Name']) ? (string) $data['Name'] : (string) $file,
                    'version'      => isset($data['Version']) ? (string) $data['Version'] : '',
                    'dir'          => trailingslashit(dirname(WP_PLUGIN_DIR . '/' . $file)),
                    'requires'     => isset($data['RequiresWP']) ? (string) $data['RequiresWP'] : '',
                    'requires_php' => isset($data['RequiresPHP']) ? (string) $data['RequiresPHP'] : '',
                );
            }
        }
        foreach (wp_get_themes() as $stylesheet => $theme) {
            $item = self::item_of($theme->get_stylesheet_directory() . '/style.css');
            if ($item > 0 && !isset(self::$products[$item])) {
                self::$products[$item] = array(
                    'type'         => 'theme',
                    'shop'         => self::is_store_uri((string) $theme->get('UpdateURI')),
                    'file'         => (string) $stylesheet,
                    'slug'         => (string) $stylesheet,
                    'name'         => (string) $theme->get('Name'),
                    'version'      => (string) $theme->get('Version'),
                    'dir'          => trailingslashit($theme->get_stylesheet_directory()),
                    'requires'     => (string) $theme->get('RequiresWP'),
                    'requires_php' => (string) $theme->get('RequiresPHP'),
                );
            }
        }
        ksort(self::$products);
        return self::$products;
    }

    /**
     * Whether an Update URI is the shop's.
     *
     * @param string $uri Update URI header.
     * @return bool
     */
    private static function is_store_uri($uri) {
        return '' !== $uri && wp_parse_url($uri, PHP_URL_HOST) === wp_parse_url(self::STORE, PHP_URL_HOST);
    }

    /**
     * A file's Licence Item header: the shop's product ID, or 0.
     *
     * @param string $file Plugin main file or theme style.css.
     * @return int
     */
    private static function item_of($file) {
        if (!is_readable($file)) {
            return 0;
        }
        $headers = get_file_data($file, array('item' => self::HEADER));
        return ctype_digit((string) $headers['item']) ? (int) $headers['item'] : 0;
    }

    /**
     * The item ID of an installed plugin or theme updated from the shop
     * (its Update URI is the shop's), or 0.
     *
     * @param string $type plugin or theme.
     * @param string $file Plugin basename or theme stylesheet.
     * @return int
     */
    private static function item_for($type, $file) {
        foreach (self::products() as $item => $product) {
            if ($product['shop'] && $product['type'] === $type && $product['file'] === $file) {
                return $item;
            }
        }
        return 0;
    }

    // ------------------------------------------------------------------
    // Licences.

    /**
     * Every stored licence: item ID => state.
     *
     * @return array<int,array{secret:string,hint:string,status:string,expires:string,plan:string,limit:int,count:int,checked:int,error:string}>
     */
    private static function all() {
        $stored = get_site_option(self::OPTION, array());
        $out    = array();
        foreach (is_array($stored) ? $stored : array() as $item => $state) {
            if ((int) $item > 0 && is_array($state)) {
                $out[(int) $item] = self::normalise($state);
            }
        }
        return $out;
    }

    /**
     * One product's stored licence (empty when none).
     *
     * @param int $item Item ID.
     * @return array{secret:string,hint:string,status:string,expires:string,plan:string,limit:int,count:int,checked:int,error:string}
     */
    public static function stored($item) {
        $all = self::all();
        return isset($all[(int) $item]) ? $all[(int) $item] : self::normalise(array());
    }

    /**
     * A stored state with every field.
     *
     * @param array<string,mixed> $state Stored state.
     * @return array{secret:string,hint:string,status:string,expires:string,plan:string,limit:int,count:int,checked:int,error:string}
     */
    private static function normalise(array $state) {
        return array(
            'secret'  => isset($state['secret']) ? (string) $state['secret'] : '',
            'hint'    => isset($state['hint']) ? (string) $state['hint'] : '',
            'status'  => isset($state['status']) ? (string) $state['status'] : '',
            'expires' => isset($state['expires']) ? (string) $state['expires'] : '',
            'plan'    => isset($state['plan']) ? (string) $state['plan'] : '',
            'limit'   => isset($state['limit']) ? (int) $state['limit'] : 0,
            'count'   => isset($state['count']) ? (int) $state['count'] : 0,
            'checked' => isset($state['checked']) ? (int) $state['checked'] : 0,
            'error'   => isset($state['error']) ? (string) $state['error'] : '',
        );
    }

    /**
     * Store one product's licence, or forget it (null).
     *
     * @param int                      $item  Item ID.
     * @param array<string,mixed>|null $state  State.
     * @param string|null              $expect The stored secret this save was
     *                                         worked out from. When the stored
     *                                         secret differs inside the lock (a
     *                                         key was activated, changed or
     *                                         removed meanwhile) nothing is saved.
     * @return bool|WP_Error True when saved, false when discarded on purpose
     *                       (secret mismatch), WP_Error when the lock was not held.
     */
    private static function save($item, $state, $expect = null) {
        $token = self::lock();
        if ('' === $token) {
            // Never read-modify-write the map without the lock: fail explicitly.
            return new WP_Error('wpallstars_licence_locked', __('The licence could not be saved because another request holds the save lock. Try again.', 'wp-plugin-starter-template'));
        }
        // Re-read inside the lock, past any cached copy, so a save from a
        // concurrent request for another product is kept, not overwritten.
        self::forget_cache();
        $all = self::all();
        if (null !== $expect) {
            $now = isset($all[(int) $item]['secret']) ? (string) $all[(int) $item]['secret'] : '';
            if ($now !== $expect) {
                self::unlock($token);
                return false;
            }
        }
        if (null === $state) {
            unset($all[(int) $item]);
        } else {
            $all[(int) $item] = self::normalise($state);
        }
        if (!update_site_option(self::OPTION, $all)) {
            // False also means "unchanged": read the stored value back to tell that from a failed write.
            self::forget_cache();
            if (self::all() != $all) { // phpcs:ignore WordPress.PHP.StrictComparisons.LooseComparison -- same keys and scalar values; only key order may differ.
                self::unlock($token);
                return new WP_Error('wpallstars_licence_not_stored', __('The licence could not be written to the database. Try again.', 'wp-plugin-starter-template'));
            }
        }
        self::unlock($token);
        delete_site_transient(self::UPDATE_CACHE . (int) $item);
        if (!self::valid($item)) {
            self::drop_offer((int) $item);
        }
        return true;
    }

    /**
     * Remove one product's shop offer from WordPress's stored update lists,
     * so a licence that is gone cannot still install it. Other products'
     * offers are left as they are.
     *
     * @param int $item Item ID.
     */
    private static function drop_offer($item) {
        $products = self::products();
        if (!isset($products[$item]) || !$products[$item]['shop']) {
            return;
        }
        $name = 'plugin' === $products[$item]['type'] ? 'update_plugins' : 'update_themes';
        $list = get_site_transient($name);
        if (is_object($list) && isset($list->response) && is_array($list->response) && isset($list->response[$products[$item]['file']])) {
            unset($list->response[$products[$item]['file']]);
            set_site_transient($name, $list);
        }
    }

    /**
     * Run a lock query against the main site's options table, whose
     * option_name is unique (multisite sitemeta has no such constraint, so
     * add_site_option() is not atomic there). One lock row serves the whole
     * network.
     *
     * @param callable $fn Receives $wpdb and the options table name.
     * @return mixed
     */
    private static function lock_query($fn) {
        global $wpdb;
        $switched = is_multisite() && function_exists('get_main_site_id') && get_current_blog_id() !== (int) get_main_site_id();
        if ($switched) {
            switch_to_blog((int) get_main_site_id());
        }
        $result = call_user_func($fn, $wpdb, $wpdb->options);
        if ($switched) {
            restore_current_blog();
        }
        return $result;
    }

    /**
     * Take the save lock (an atomic insert on a unique key; a stale lock is
     * taken over after 15 seconds by compare-and-delete on the observed
     * value). Waits up to about 5 seconds.
     *
     * @return string The owner token, or '' when the lock is not held.
     */
    private static function lock() {
        $name  = self::OPTION . '_lock';
        for ($try = 0; $try < 50; $try++) {
            // A fresh timestamp per attempt, so the 15 second stale window
            // counts from when the lock was taken, not from when we started.
            $token = time() . ':' . wp_generate_password(12, false);
            $got = self::lock_query(function ($db, $table) use ($name, $token) {
                return 1 === (int) $db->query($db->prepare("INSERT IGNORE INTO %i (option_name, option_value, autoload) VALUES (%s, %s, 'no')", $table, $name, $token));
            });
            if ($got) {
                return $token;
            }
            $seen = self::lock_query(function ($db, $table) use ($name) {
                return $db->get_var($db->prepare("SELECT option_value FROM %i WHERE option_name = %s", $table, $name));
            });
            if (is_string($seen) && (int) $seen < time() - 15) {
                // Delete only the stale row observed, never a waiter's fresh one.
                self::lock_query(function ($db, $table) use ($name, $seen) {
                    return $db->query($db->prepare("DELETE FROM %i WHERE option_name = %s AND option_value = %s", $table, $name, $seen));
                });
                continue;
            }
            usleep(100000);
        }
        return '';
    }

    /**
     * Release the save lock, only when this request still owns it.
     *
     * @param string $token Token lock() returned.
     */
    private static function unlock($token) {
        $name = self::OPTION . '_lock';
        self::lock_query(function ($db, $table) use ($name, $token) {
            return $db->query($db->prepare("DELETE FROM %i WHERE option_name = %s AND option_value = %s", $table, $name, $token));
        });
    }

    /**
     * Drop the cached copies of the licence option and its lock, so the next
     * read comes from the database.
     */
    private static function forget_cache() {
        $network = get_current_network_id();
        foreach (array(self::OPTION, self::OPTION . '_lock') as $name) {
            wp_cache_delete($name, 'options');
            wp_cache_delete($network . ':' . $name, 'site-options');
        }
        wp_cache_delete($network . ':notoptions', 'site-options');
        wp_cache_delete('alloptions', 'options');
        wp_cache_delete('notoptions', 'options');
    }

    /**
     * Whether a product's licence is valid, from the stored answer only (no
     * request): the shop said valid, and it has not expired more than GRACE
     * ago.
     *
     * @param int $item Item ID.
     * @return bool
     */
    public static function valid($item) {
        $stored = self::stored($item);
        if ('' === $stored['secret'] || 'valid' !== $stored['status']) {
            return false;
        }
        return 'lifetime' === $stored['expires'] || '' === $stored['expires'] || self::expiry_time($stored['expires']) + self::GRACE > time();
    }

    /**
     * An expiry date the shop gave (GMT), as a timestamp; 0 when unknown.
     *
     * @param string $expires Y-m-d H:i:s, or lifetime.
     * @return int
     */
    private static function expiry_time($expires) {
        $time = '' !== $expires && 'lifetime' !== $expires ? strtotime($expires . ' UTC') : false;
        return false === $time ? 0 : (int) $time;
    }

    /**
     * Activate a key for one product on this site (network).
     *
     * @param int    $item Item ID.
     * @param string $key  Licence key.
     * @return true|WP_Error
     */
    public static function activate($item, $key) {
        $item = (int) $item;
        $key  = trim((string) $key);
        if ($item <= 0) {
            return new WP_Error('wpallstars_licence_item', __('Name the product by its item ID in the shop.', 'wp-plugin-starter-template'));
        }
        if ('' === $key || strlen($key) > 200) {
            return new WP_Error('wpallstars_licence_key', __('Enter the licence key from the purchase receipt or the account on wpallstars.com.', 'wp-plugin-starter-template'));
        }
        $answer = self::ask($item, 'activate_license', array('license_key' => $key));
        if (is_wp_error($answer)) {
            return $answer;
        }
        if (!isset($answer['status']) || 'valid' !== $answer['status'] || empty($answer['activation_hash'])) {
            return self::refused($answer);
        }
        $secret = self::encrypt((string) wp_json_encode(array('key' => $key, 'hash' => (string) $answer['activation_hash'])));
        if (is_wp_error($secret)) {
            return $secret;
        }
        $saved = self::save($item, array('secret' => $secret, 'hint' => substr($key, -4)) + self::from_answer($answer));
        if (is_wp_error($saved)) {
            return $saved;
        }
        self::schedule(true);
        return true;
    }

    /**
     * Ask the shop for one licence's state now, and store the answer. A
     * failed request keeps the stored state, with the error. A stored key
     * this site cannot read is marked unreadable without asking.
     *
     * @param int $item Item ID.
     * @return true|WP_Error
     */
    public static function check($item) {
        $stored = self::stored($item);
        if ('' === $stored['secret']) {
            return new WP_Error('wpallstars_licence_none', __('No licence key is stored for this product.', 'wp-plugin-starter-template'));
        }
        $secret = self::secret($item);
        if (null === $secret) {
            $error = new WP_Error('wpallstars_licence_unreadable', __('This site cannot read the stored licence key: its security keys changed, or it was copied from another site. Activate the key again.', 'wp-plugin-starter-template'));
            $saved = self::save($item, array('status' => self::UNREADABLE, 'checked' => time(), 'error' => $error->get_error_message()) + $stored, $stored['secret']);
            return is_wp_error($saved) ? $saved : $error;
        }
        $answer = self::ask($item, 'check_license', array('license_key' => $secret['key'], 'activation_hash' => $secret['hash']));
        if (is_wp_error($answer)) {
            // Discarded when the licence changed while the shop was asked.
            $saved = self::save($item, array('error' => $answer->get_error_message()) + $stored, $stored['secret']);
            return is_wp_error($saved) ? $saved : $answer;
        }
        $state   = self::from_answer($answer);
        $refusal = 'valid' !== $state['status'] ? self::refused($answer) : null;
        if ($refusal) {
            $state['error'] = $refusal->get_error_message();
        }
        // Discarded when the licence changed while the shop was asked.
        $saved = self::save($item, $state + $stored, $stored['secret']);
        if (is_wp_error($saved)) {
            return $saved;
        }
        // The refusal is stored, and also returned: it is not a success.
        return $refusal ? $refusal : true;
    }

    /**
     * Free this site's activation in the shop, and forget the key. When the
     * shop cannot be reached the key stays, so the activation is never left
     * in use with no key here to free it. A key this site cannot read is
     * forgotten (its activation is freed in the shop's account screens).
     *
     * @param int $item Item ID.
     * @return true|WP_Error
     */
    public static function deactivate($item) {
        $before = self::stored($item)['secret'];
        $secret = self::secret($item);
        if (null !== $secret) {
            $answer = self::ask($item, 'deactivate_license', array('license_key' => $secret['key']));
            if (is_wp_error($answer)) {
                return $answer;
            }
            // Already freed in the shop (or the licence is gone): forget it here too.
            $gone = isset($answer['error_type']) && in_array($answer['error_type'], array('license_not_found', 'site_not_found'), true);
            if (!$gone && (!isset($answer['status']) || 'deactivated' !== $answer['status'])) {
                return self::refused($answer);
            }
        }
        // Forget only the licence this deactivation freed: a key activated
        // meanwhile (while the shop was asked) is not deleted.
        $saved = self::save($item, null, $before);
        if (false === $saved) {
            return new WP_Error('wpallstars_licence_changed', __('The key was freed in the shop, but another key was activated meanwhile and was kept.', 'wp-plugin-starter-template'));
        }
        return is_wp_error($saved) ? $saved : true;
    }

    /**
     * The item IDs of every stored licence, also of a product no longer
     * installed.
     *
     * @return array<int,int>
     */
    public static function stored_items() {
        return array_keys(self::all());
    }

    /** The daily WP-Cron check of every stored licence. */
    public static function scheduled_check() {
        foreach (self::stored_items() as $item) {
            self::check($item);
        }
    }

    /**
     * Put the daily check in WP-Cron while a licence is stored. The event
     * belongs to the main site: from another site's context (WP-CLI with a
     * subsite --url) $switch schedules it there and restores the context.
     *
     * @param bool $switch Switch to the main site when on another one.
     */
    public static function schedule($switch = false) {
        if (is_multisite() && !is_main_site()) {
            if ($switch === true && function_exists('get_main_site_id')) {
                switch_to_blog((int) get_main_site_id());
                self::schedule();
                restore_current_blog();
            }
            return;
        }
        $any = (bool) self::all();
        if ($any && !wp_next_scheduled(self::CRON_HOOK)) {
            wp_schedule_event(time() + DAY_IN_SECONDS, 'daily', self::CRON_HOOK);
        } elseif (!$any && wp_next_scheduled(self::CRON_HOOK)) {
            wp_clear_scheduled_hook(self::CRON_HOOK);
        }
    }

    /**
     * One product's stored key and activation hash.
     *
     * @param int $item Item ID.
     * @return array{key:string,hash:string}|null
     */
    private static function secret($item) {
        $stored = self::stored($item);
        $plain  = '' === $stored['secret'] ? false : self::decrypt($stored['secret']);
        $secret = is_string($plain) ? json_decode($plain, true) : null;
        if (!is_array($secret) || empty($secret['key']) || !is_string($secret['key'])) {
            return null;
        }
        return array('key' => $secret['key'], 'hash' => isset($secret['hash']) ? (string) $secret['hash'] : '');
    }

    /**
     * The stored state from one of the shop's answers.
     *
     * @param array<string,mixed> $answer The shop's answer.
     * @return array{status:string,expires:string,plan:string,limit:int,count:int,checked:int,error:string}
     */
    private static function from_answer(array $answer) {
        return array(
            'status'  => isset($answer['status']) ? sanitize_key((string) $answer['status']) : 'invalid',
            'expires' => isset($answer['expiration_date']) ? sanitize_text_field((string) $answer['expiration_date']) : '',
            'plan'    => isset($answer['variation_title']) ? sanitize_text_field((string) $answer['variation_title']) : '',
            'limit'   => isset($answer['activation_limit']) ? (int) $answer['activation_limit'] : 0,
            'count'   => isset($answer['activations_count']) ? (int) $answer['activations_count'] : 0,
            'checked' => time(),
            'error'   => '',
        );
    }

    /**
     * The shop's refusal, for people.
     *
     * @param array<string,mixed> $answer The shop's answer.
     * @return WP_Error
     */
    private static function refused(array $answer) {
        $type     = isset($answer['error_type']) ? (string) $answer['error_type'] : (isset($answer['status']) ? (string) $answer['status'] : '');
        $unknown  = __('The shop does not know this licence key. Check it against the purchase receipt.', 'wp-plugin-starter-template');
        $expired  = __('This licence has expired. Renew it in the account on wpallstars.com, then check it again.', 'wp-plugin-starter-template');
        $messages = array(
            'license_not_found'         => $unknown,
            'invalid_license'           => $unknown,
            'invalid_activation'        => __('This site is no longer activated for the licence (it was freed in the account on wpallstars.com, or the site\'s address changed). Activate the key again.', 'wp-plugin-starter-template'),
            'key_mismatch'              => __('This licence key is for another product.', 'wp-plugin-starter-template'),
            'license_expired'           => $expired,
            'expired'                   => $expired,
            'license_not_active'        => __('This licence is not active. Contact support on wpallstars.com.', 'wp-plugin-starter-template'),
            'activation_limit_exceeded' => __('This licence is in use on as many sites as it allows. Deactivate it on another site, or upgrade it in the account on wpallstars.com.', 'wp-plugin-starter-template'),
            'site_not_found'            => __('This site is not activated for the licence.', 'wp-plugin-starter-template'),
            'invalid'                   => __('The shop says this licence is no longer active (refunded, cancelled or disabled). Check the account on wpallstars.com.', 'wp-plugin-starter-template'),
        );
        if (isset($messages[$type])) {
            return new WP_Error('wpallstars_licence_' . $type, $messages[$type]);
        }
        $said = isset($answer['message']) ? sanitize_text_field((string) $answer['message']) : '';
        return new WP_Error(
            'wpallstars_licence_refused',
            '' !== $said
                /* translators: %s: the shop's message */
                ? sprintf(__('The shop refused the licence: %s', 'wp-plugin-starter-template'), $said)
                : __('The shop refused the licence.', 'wp-plugin-starter-template')
        );
    }

    /**
     * The address the licences are activated for: the network's main site
     * on multisite, else this site.
     *
     * @return string
     */
    public static function site_url() {
        return is_multisite() ? get_home_url(get_main_site_id()) : home_url();
    }

    /**
     * Ask the shop's licensing API about one product.
     *
     * @param int                  $item   Item ID.
     * @param string               $action check_license, activate_license, deactivate_license or get_license_version.
     * @param array<string,string> $fields The request's own fields.
     * @return array<string,mixed>|WP_Error The JSON answer (refusals too), or the failure.
     */
    private static function ask($item, $action, array $fields) {
        global $wp_version;
        $products = self::products();
        $version  = isset($products[(int) $item]) ? $products[(int) $item]['version'] : '';
        $response = wp_safe_remote_post(add_query_arg('fluent-cart', $action, self::STORE), array(
            'timeout'    => 15, // phpcs:ignore WordPressVIPMinimum.Performance.RemoteRequestTimeout.timeout_timeout -- owner action, WP-CLI, WP-Cron or WordPress's update check, never a visitor request.
            'user-agent' => 'WPAllStarsLicence/' . $version . '; ' . self::site_url(),
            'body'       => $fields + array(
                'item_id'          => (string) (int) $item,
                'site_url'         => self::site_url(),
                'current_version'  => $version,
                'platform_version' => (string) $wp_version,
                'server_version'   => PHP_VERSION,
            ),
        ));
        if (is_wp_error($response)) {
            /* translators: %s: the error */
            return new WP_Error('wpallstars_licence_http', sprintf(__('wpallstars.com could not be reached: %s', 'wp-plugin-starter-template'), $response->get_error_message()));
        }
        $answer = json_decode((string) wp_remote_retrieve_body($response), true);
        $code   = (int) wp_remote_retrieve_response_code($response);
        // A service failure (outage, rate limit) or an answer with neither a licence status nor a refusal type is not a licence answer: keep the stored state.
        if (!is_array($answer) || $code >= 500 || 429 === $code || (!isset($answer['status']) && !isset($answer['error_type']) && !isset($answer['new_version']))) {
            /* translators: %d: HTTP status */
            return new WP_Error('wpallstars_licence_http', sprintf(__('wpallstars.com gave an answer that is not the licensing API\'s (HTTP %d). Try again later.', 'wp-plugin-starter-template'), (int) wp_remote_retrieve_response_code($response)));
        }
        return $answer;
    }

    // ------------------------------------------------------------------
    // Updates.

    /**
     * The update_plugins_{hostname} filter: the shop's latest version of a
     * licensed plugin. WordPress compares the versions.
     *
     * @param array<string,mixed>|false $update      Another filter's answer, or false.
     * @param array<string,string>      $plugin_data The plugin's headers.
     * @param string                    $plugin_file The plugin's file.
     * @return array<string,mixed>|false
     */
    public static function update_plugin($update, $plugin_data, $plugin_file) {
        unset($plugin_data);
        $item = $update ? 0 : self::item_for('plugin', (string) $plugin_file);
        $info = $item > 0 ? self::version_info($item) : null;
        if (null === $info) {
            return $update;
        }
        $product = self::products()[$item];
        $out     = array(
            'slug'         => $product['slug'],
            'version'      => $info['version'],
            'url'          => $info['homepage'],
            'package'      => $info['package'],
            'requires'     => $product['requires'],
            'requires_php' => $product['requires_php'],
        );
        foreach (array('icons', 'banners') as $images) {
            $urls = self::images($product, $images, $info[$images]);
            if ($urls) {
                $out[$images] = $urls;
            }
        }
        return $out;
    }

    /**
     * The update_themes_{hostname} filter: the shop's latest version of a
     * licensed theme.
     *
     * @param array<string,mixed>|false $update     Another filter's answer, or false.
     * @param array<string,string>      $theme_data The theme's headers.
     * @param string                    $stylesheet The theme's stylesheet (folder).
     * @return array<string,mixed>|false
     */
    public static function update_theme($update, $theme_data, $stylesheet) {
        unset($theme_data);
        $item = $update ? 0 : self::item_for('theme', (string) $stylesheet);
        $info = $item > 0 ? self::version_info($item) : null;
        if (null === $info) {
            return $update;
        }
        $product = self::products()[$item];
        return array(
            'theme'        => $product['slug'],
            'version'      => $info['version'],
            'url'          => $info['homepage'],
            'package'      => $info['package'],
            'requires'     => $product['requires'],
            'requires_php' => $product['requires_php'],
        );
    }

    /**
     * The plugins_api filter: View details for a licensed plugin.
     *
     * @param false|object|array<string,mixed> $result Another filter's answer.
     * @param string                           $action plugins_api action.
     * @param object                           $args   Its arguments.
     * @return false|object|array<string,mixed>
     */
    public static function details($result, $action, $args) {
        if ('plugin_information' !== $action || !is_object($args) || !isset($args->slug)) {
            return $result;
        }
        foreach (self::products() as $item => $product) {
            if (!$product['shop'] || 'plugin' !== $product['type'] || $product['slug'] !== $args->slug) {
                continue;
            }
            $info = self::version_info($item);
            if (null === $info) {
                return $result;
            }
            return (object) array(
                'name'          => $product['name'],
                'slug'          => $product['slug'],
                'version'       => $info['version'],
                'author'        => '<a href="' . esc_url(self::STORE) . '">WP ALLSTARS</a>',
                'homepage'      => $info['homepage'],
                'last_updated'  => $info['updated'],
                'download_link' => $info['package'],
                'sections'      => $info['sections'],
                'requires'      => $product['requires'],
                'requires_php'  => $product['requires_php'],
                'banners'       => self::images($product, 'banners', $info['banners']),
                'icons'         => self::images($product, 'icons', $info['icons']),
            );
        }
        return $result;
    }

    /**
     * A plugin's own icon or banners for the Updates screen and View
     * details, from its installed admin/images/, else the shop's. The site's
     * browser loads these and the shop's CDN refuses images linked from
     * other sites. Scheme-less, so a check run by WP-CLI or cron (where
     * is_ssl() is false) does not store http addresses for an https admin.
     *
     * @param array{dir:string,file:string} $product Product.
     * @param string               $key     icons or banners.
     * @param array<string,string> $shop    The shop's addresses, by size.
     * @return array<string,string>
     */
    private static function images(array $product, $key, array $shop) {
        $out = array();
        foreach (isset(self::IMAGES[$key]) ? self::IMAGES[$key] : array() as $size => $names) {
            foreach ($names as $name) {
                if (is_file($product['dir'] . 'admin/images/' . $name)) {
                    $out[$size] = (string) preg_replace('#^https?:#i', '', plugins_url('admin/images/' . $name, WP_PLUGIN_DIR . '/' . $product['file']));
                    break;
                }
            }
        }
        return $out ? $out : $shop;
    }

    /**
     * The upgrader_pre_download filter: download a product's package with
     * maintenance mode lifted, when this WordPress install is also the shop
     * (it answers 503 to the shop's package address while maintenance mode
     * is on). Nothing is replaced while downloading; maintenance mode is
     * turned on again before WordPress unpacks the package.
     *
     * @param bool|string|WP_Error $reply      Another filter's answer, or false.
     * @param string               $package    The package's address.
     * @param WP_Upgrader|mixed    $upgrader   The upgrader.
     * @param array<string,mixed>  $hook_extra The update's details.
     * @return bool|string|WP_Error
     */
    public static function download($reply, $package, $upgrader, $hook_extra = array()) {
        if (false !== $reply
            || !$upgrader instanceof WP_Upgrader
            || !is_string($package)
            || wp_parse_url($package, PHP_URL_HOST) !== wp_parse_url(self::STORE, PHP_URL_HOST)
            || !file_exists(ABSPATH . '.maintenance')
            || !self::is_product_update($hook_extra)
            || !self::shop_is_here()
        ) {
            return $reply;
        }
        $upgrader->maintenance_mode(false);
        $file = download_url($package, 300);
        $upgrader->maintenance_mode(true);
        if (is_wp_error($file)) {
            return new WP_Error('download_failed', isset($upgrader->strings['download_failed']) ? $upgrader->strings['download_failed'] : __('Download failed.', 'wp-plugin-starter-template'), $file->get_error_message());
        }
        return $file;
    }

    /**
     * Whether an upgrade is of one of the products.
     *
     * @param mixed $hook_extra The update's details.
     * @return bool
     */
    private static function is_product_update($hook_extra) {
        if (!is_array($hook_extra)) {
            return false;
        }
        if (isset($hook_extra['plugin'])) {
            return self::item_for('plugin', (string) $hook_extra['plugin']) > 0;
        }
        return isset($hook_extra['theme']) && self::item_for('theme', (string) $hook_extra['theme']) > 0;
    }

    /**
     * Whether the shop is a site of this WordPress install.
     *
     * @return bool
     */
    private static function shop_is_here() {
        $host = (string) wp_parse_url(self::STORE, PHP_URL_HOST);
        if (is_multisite()) {
            return get_site_by_path($host, '/') instanceof WP_Site;
        }
        return wp_parse_url(home_url(), PHP_URL_HOST) === $host;
    }

    /**
     * The shop's latest version of a product, cached: null without a stored
     * key (nothing is asked), while the licence is not valid, or while the
     * shop cannot be reached.
     *
     * @param int $item Item ID.
     * @return array{version:string,homepage:string,package:string,updated:string,sections:array<string,string>,icons:array<string,string>,banners:array<string,string>}|null
     */
    private static function version_info($item) {
        // No offer, cached or fetched, once the licence is no longer valid
        // (expired past GRACE, or not valid): matches describe().
        if (!self::valid($item)) {
            return null;
        }
        $secret = self::secret($item);
        if (null === $secret) {
            return null;
        }
        // The cache is keyed to this activation: an answer fetched for a key
        // that was replaced while the shop was asked is never read back.
        $for    = substr(hash('sha256', self::stored($item)['secret']), 0, 16);
        $cached = get_site_transient(self::UPDATE_CACHE . (int) $item);
        if (is_array($cached) && isset($cached['for']) && $cached['for'] === $for) {
            return isset($cached['answer']) && is_array($cached['answer']) ? self::version_from_answer($cached['answer']) : null;
        }
        $answer = self::ask($item, 'get_license_version', array('activation_hash' => $secret['hash'], 'license_key' => '' === $secret['hash'] ? $secret['key'] : ''));
        $info   = is_array($answer) ? self::version_from_answer($answer) : null;
        set_site_transient(
            self::UPDATE_CACHE . (int) $item,
            null === $info || !is_array($answer) ? array('failed' => time(), 'for' => $for) : array('answer' => $answer, 'for' => $for),
            null === $info ? self::UPDATE_RETRY : self::UPDATE_TTL
        );
        return $info;
    }

    /**
     * A version answer, checked and trimmed to what WordPress shows. The
     * package is kept only when it is the shop's own address.
     *
     * @param array<string,mixed> $answer The shop's answer.
     * @return array{version:string,homepage:string,package:string,updated:string,sections:array<string,string>,icons:array<string,string>,banners:array<string,string>}|null
     */
    private static function version_from_answer(array $answer) {
        $version = isset($answer['new_version']) ? (string) $answer['new_version'] : '';
        if (!preg_match('/^\d+\.\d+\.\d+$/', $version)) {
            return null;
        }
        $package = isset($answer['package']) ? esc_url_raw((string) $answer['package']) : '';
        if ('' !== $package && wp_parse_url($package, PHP_URL_HOST) !== wp_parse_url(self::STORE, PHP_URL_HOST)) {
            $package = '';
        }
        $sections = array();
        foreach (isset($answer['sections']) && is_array($answer['sections']) ? $answer['sections'] : array() as $name => $html) {
            if (in_array($name, array('description', 'changelog'), true) && is_string($html) && '' !== $html) {
                $sections[$name] = wp_kses_post($html);
            }
        }
        return array(
            'version'  => $version,
            'homepage' => isset($answer['homepage']) ? esc_url_raw((string) $answer['homepage']) : self::STORE,
            'package'  => $package,
            'updated'  => isset($answer['last_updated']) ? sanitize_text_field((string) $answer['last_updated']) : '',
            'sections' => $sections,
            'icons'    => self::image_urls($answer, 'icons'),
            'banners'  => self::image_urls($answer, 'banners'),
        );
    }

    /**
     * An answer's icon or banner addresses, leaving out empty ones.
     *
     * @param array<string,mixed> $answer The shop's answer.
     * @param string              $key    icons or banners.
     * @return array<string,string>
     */
    private static function image_urls(array $answer, $key) {
        $out = array();
        foreach (isset($answer[$key]) && is_array($answer[$key]) ? $answer[$key] : array() as $size => $url) {
            $url = is_string($url) ? esc_url_raw($url) : '';
            if ('' !== $url) {
                $out[(string) $size] = $url;
            }
        }
        return $out;
    }

    // ------------------------------------------------------------------
    // Encryption.

    /**
     * Encrypt a text: version, then base64 of nonce and ciphertext.
     *
     * @param string $plain Text.
     * @return string|WP_Error
     */
    private static function encrypt($plain) {
        if (!function_exists('sodium_crypto_secretbox')) {
            return new WP_Error('wpallstars_licence_no_sodium', __('PHP\'s sodium functions, which WordPress normally provides, are missing, so the licence key cannot be stored safely.', 'wp-plugin-starter-template'));
        }
        $nonce = random_bytes(SODIUM_CRYPTO_SECRETBOX_NONCEBYTES);
        return self::CIPHER . base64_encode($nonce . sodium_crypto_secretbox($plain, $nonce, self::key())); // phpcs:ignore WordPress.PHP.DiscouragedPHPFunctions.obfuscation_base64_encode -- stores binary ciphertext as text.
    }

    /**
     * Decrypt a text made by encrypt().
     *
     * @param string $stored Stored value.
     * @return string|false False when it cannot be read.
     */
    private static function decrypt($stored) {
        if (!function_exists('sodium_crypto_secretbox_open') || 0 !== strpos($stored, self::CIPHER)) {
            return false;
        }
        $raw = base64_decode(substr($stored, strlen(self::CIPHER)), true); // phpcs:ignore WordPress.PHP.DiscouragedPHPFunctions.obfuscation_base64_decode -- reads what encrypt() stored.
        if (false === $raw || strlen($raw) <= SODIUM_CRYPTO_SECRETBOX_NONCEBYTES) {
            return false;
        }
        try {
            return sodium_crypto_secretbox_open(substr($raw, SODIUM_CRYPTO_SECRETBOX_NONCEBYTES), substr($raw, 0, SODIUM_CRYPTO_SECRETBOX_NONCEBYTES), self::key());
        } catch (\Throwable $e) {
            return false;
        }
    }

    /**
     * The 32-byte key, for this use only.
     *
     * @return string
     */
    private static function key() {
        $secret = defined('WPALLSTARS_LICENCE_ENCRYPTION_KEY') && is_string(WPALLSTARS_LICENCE_ENCRYPTION_KEY) && '' !== WPALLSTARS_LICENCE_ENCRYPTION_KEY ? WPALLSTARS_LICENCE_ENCRYPTION_KEY : wp_salt('auth');
        return hash_hmac('sha256', 'wpallstars-licence', $secret, true);
    }

    // ------------------------------------------------------------------
    // Settings → Licences.

    /** The capability that manages licences. */
    private static function capability() {
        return is_multisite() ? 'manage_network_options' : 'manage_options';
    }

    /** Add Settings → Licences (Network Admin on multisite), when a product is installed. */
    public static function menu() {
        if (!self::products()) {
            return;
        }
        add_submenu_page(
            is_multisite() ? 'settings.php' : 'options-general.php',
            __('Licences', 'wp-plugin-starter-template'),
            __('Licences', 'wp-plugin-starter-template'),
            self::capability(),
            self::PAGE,
            array(__CLASS__, 'render')
        );
    }

    /**
     * The screen's address.
     *
     * @return string
     */
    public static function page_url() {
        return is_multisite() ? network_admin_url('settings.php?page=' . self::PAGE) : admin_url('options-general.php?page=' . self::PAGE);
    }

    /** Draw Settings → Licences. */
    public static function render() {
        if (!current_user_can(self::capability())) {
            return;
        }
        $notice = get_transient(self::notice_key());
        if (is_array($notice)) {
            delete_transient(self::notice_key());
        }
        ?>
        <div class="wrap">
            <h1><?php esc_html_e('Licences', 'wp-plugin-starter-template'); ?></h1>
            <?php if (is_array($notice) && isset($notice['message'], $notice['type'])) : ?>
                <div class="notice notice-<?php echo esc_attr('success' === $notice['type'] ? 'success' : 'error'); ?>"><p><?php echo esc_html((string) $notice['message']); ?></p></div>
            <?php endif; ?>
            <p><?php esc_html_e('A licence brings each new release of its product from wpallstars.com as a normal WordPress update. Without one the product keeps working, but is not updated. Licences are checked once a day from WP-Cron, never while a visitor loads a page, sending the key, this site\'s address and the WordPress, PHP and product versions.', 'wp-plugin-starter-template'); ?></p>
            <?php if (is_multisite()) : ?>
                <p><?php esc_html_e('One licence per product covers the whole network.', 'wp-plugin-starter-template'); ?></p>
            <?php endif; ?>
            <table class="widefat striped">
                <thead><tr>
                    <th scope="col"><?php esc_html_e('Product', 'wp-plugin-starter-template'); ?></th>
                    <th scope="col"><?php esc_html_e('Licence', 'wp-plugin-starter-template'); ?></th>
                    <th scope="col"><?php esc_html_e('Actions', 'wp-plugin-starter-template'); ?></th>
                </tr></thead>
                <tbody>
                <?php foreach (self::products() as $item => $product) : ?>
                    <?php $stored = self::stored($item); ?>
                    <tr>
                        <td>
                            <strong><?php echo esc_html($product['name']); ?></strong><br><?php echo esc_html($product['version']); ?>
                            <?php if (!$product['shop']) : ?>
                                <br><?php esc_html_e('This version still updates from elsewhere; a later release moves it to wpallstars.com.', 'wp-plugin-starter-template'); ?>
                            <?php endif; ?>
                        </td>
                        <td>
                            <?php echo esc_html(self::describe($item)); ?>
                            <?php if ('' !== $stored['error'] && !self::valid($item)) : ?>
                                <br><span role="alert"><?php echo esc_html($stored['error']); ?></span>
                            <?php endif; ?>
                        </td>
                        <td>
                            <form method="post" action="<?php echo esc_url(admin_url('admin-post.php')); ?>">
                                <input type="hidden" name="action" value="<?php echo esc_attr(self::ACTION); ?>">
                                <input type="hidden" name="item" value="<?php echo esc_attr((string) $item); ?>">
                                <?php wp_nonce_field(self::ACTION); ?>
                                <?php if ('' === $stored['secret'] || self::UNREADABLE === $stored['status']) : ?>
                                    <label class="screen-reader-text" for="wpallstars-licence-<?php echo esc_attr((string) $item); ?>"><?php esc_html_e('Licence key', 'wp-plugin-starter-template'); ?></label>
                                    <input type="password" class="regular-text" id="wpallstars-licence-<?php echo esc_attr((string) $item); ?>" name="key" autocomplete="off" spellcheck="false" required>
                                    <button type="submit" class="button button-primary" name="licence_action" value="activate"><?php esc_html_e('Activate', 'wp-plugin-starter-template'); ?></button>
                                <?php else : ?>
                                    <button type="submit" class="button" name="licence_action" value="check"><?php esc_html_e('Check now', 'wp-plugin-starter-template'); ?></button>
                                    <button type="submit" class="button button-link-delete" name="licence_action" value="deactivate"><?php esc_html_e('Deactivate', 'wp-plugin-starter-template'); ?></button>
                                <?php endif; ?>
                            </form>
                        </td>
                    </tr>
                <?php endforeach; ?>
                </tbody>
            </table>
        </div>
        <?php
    }

    /**
     * A licence's state, in a sentence. Never shows the key: only its last
     * four characters.
     *
     * @param int $item Item ID.
     * @return string
     */
    public static function describe($item) {
        $stored = self::stored($item);
        if ('' === $stored['secret']) {
            return __('No licence: not updated from wpallstars.com.', 'wp-plugin-starter-template');
        }
        if (self::UNREADABLE === $stored['status']) {
            return __('The stored key cannot be read on this site; activate it again.', 'wp-plugin-starter-template');
        }
        $expiry  = self::expiry_time($stored['expires']);
        $checked = $stored['checked']
            /* translators: %s: time span such as "3 hours" */
            ? sprintf(__('checked %s ago', 'wp-plugin-starter-template'), human_time_diff($stored['checked']))
            : __('not checked yet', 'wp-plugin-starter-template');
        if (self::valid($item)) {
            $until = $expiry
                /* translators: %s: date */
                ? sprintf(__('renews or expires on %s', 'wp-plugin-starter-template'), wp_date((string) get_option('date_format'), $expiry))
                : __('never expires', 'wp-plugin-starter-template');
            /* translators: 1: plan, 2: key's last four characters, 3: sites in use, 4: sites allowed, 5: when it expires, 6: when it was checked */
            return sprintf(__('%1$s (key ending %2$s): %3$d of %4$d sites, %5$s; %6$s.', 'wp-plugin-starter-template'), '' !== $stored['plan'] ? $stored['plan'] : __('Active', 'wp-plugin-starter-template'), $stored['hint'], $stored['count'], $stored['limit'], $until, $checked);
        }
        if ($expiry && $expiry + self::GRACE <= time()) {
            /* translators: 1: date, 2: when it was checked */
            return sprintf(__('Expired on %1$s (%2$s): not updated until it is renewed.', 'wp-plugin-starter-template'), wp_date((string) get_option('date_format'), $expiry), $checked);
        }
        /* translators: 1: key's last four characters, 2: when it was checked */
        return sprintf(__('Not valid (key ending %1$s, %2$s): not updated.', 'wp-plugin-starter-template'), $stored['hint'], $checked);
    }

    /** @return string The current user's notice transient. */
    private static function notice_key() {
        return 'wpallstars_licence_notice_' . get_current_user_id();
    }

    /** The screen's buttons (admin-post). */
    public static function submit() {
        if (!current_user_can(self::capability())) {
            wp_die(esc_html__('Sorry, you are not allowed to manage licences.', 'wp-plugin-starter-template'), 403);
        }
        check_admin_referer(self::ACTION);
        $item     = isset($_POST['item']) ? absint(wp_unslash($_POST['item'])) : 0;
        $action   = isset($_POST['licence_action']) ? sanitize_key(wp_unslash((string) $_POST['licence_action'])) : '';
        $products = self::products();
        if (!isset($products[$item])) {
            $result = new WP_Error('wpallstars_licence_item', __('That product is not installed.', 'wp-plugin-starter-template'));
        } elseif ('activate' === $action) {
            // phpcs:ignore WordPress.Security.ValidatedSanitizedInput.InputNotSanitized -- a key is sent as typed; activate() trims it and it is stored only encrypted.
            $result = self::activate($item, isset($_POST['key']) && is_string($_POST['key']) ? wp_unslash($_POST['key']) : '');
        } elseif ('deactivate' === $action) {
            $result = self::deactivate($item);
        } else {
            $result = self::check($item);
        }
        $name = isset($products[$item]) ? $products[$item]['name'] : '';
        set_transient(self::notice_key(), is_wp_error($result)
            ? array('type' => 'error', 'message' => $result->get_error_message())
            /* translators: 1: product name, 2: the licence's state */
            : array('type' => 'success', 'message' => sprintf(__('%1$s: %2$s', 'wp-plugin-starter-template'), $name, self::describe($item))), MINUTE_IN_SECONDS);
        wp_safe_redirect(self::page_url());
        exit;
    }
}
