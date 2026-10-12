<?php
/**
 * WP Plugin Starter network screen (multisite).
 *
 * Network Admin → Settings → WP Plugin Starter, for people who can manage
 * the network: the settings screen (WPStarter_Admin_Manager), drawn by the
 * same code in the network admin, where its cards save network values
 * (WPStarter_Network_Settings). Under each card's description:
 *
 * - Apply to every site: every site uses the card's network values and
 *   cannot change them; switching it off gives each site its own again.
 * - The sites whose own values differ, up to SITES_NAMED of them named
 *   with links to their settings screens, and Make every site the same,
 *   which copies the card's network values into every site's own settings
 *   once.
 *
 * The network admin has no admin-ajax.php of its own, so its saves go to
 * the main site's, where is_network_admin() is false: the AJAX actions here
 * check manage_network_options themselves.
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

class WPStarter_Network_Manager {

    /** Most sites named under a card; the others are counted. */
    const SITES_NAMED = 10;

    /** Hook suffix WordPress gave the screen when it was registered. */
    private static $hook = '';

    /**
     * Register hooks (multisite only).
     */
    public static function init() {
        if (!is_multisite()) {
            return;
        }
        add_action('network_admin_menu', array(__CLASS__, 'register_menu'));
        add_filter('network_admin_plugin_action_links_' . plugin_basename(WPSTARTER_FILE), array(__CLASS__, 'plugin_action_links'));
        add_action('wp_ajax_wpstarter_network_save', array(__CLASS__, 'ajax_save'));
        add_action('wp_ajax_wpstarter_network_apply', array(__CLASS__, 'ajax_apply'));
        add_action('wp_ajax_wpstarter_network_copy', array(__CLASS__, 'ajax_copy'));
    }

    /**
     * Register Network Admin → Settings → WP Plugin Starter.
     */
    public static function register_menu() {
        $hook = add_submenu_page(
            'settings.php',
            __('WP Plugin Starter', 'wp-plugin-starter-template'),
            __('WP Plugin Starter', 'wp-plugin-starter-template'),
            'manage_network_options',
            WPStarter_Admin_Manager::PAGE,
            array('WPStarter_Admin_Manager', 'render_settings_page')
        );
        // A string, or false for people who cannot see the screen.
        self::$hook = (string) $hook;
        if ('' !== self::$hook) {
            // The browser title names the tab shown, as on each site's screen.
            add_action('load-' . self::$hook, array('WPStarter_Admin_Page', 'title_tab'));
        }
    }

    /**
     * Hook suffix of the screen, once registered.
     *
     * @return string
     */
    public static function hook() {
        return self::$hook;
    }

    /**
     * Address of the network screen.
     *
     * @param array $args Extra query args.
     * @return string
     */
    public static function page_url(array $args = array()) {
        return add_query_arg(array_merge(array('page' => WPStarter_Admin_Manager::PAGE), $args), network_admin_url('settings.php'));
    }

    /**
     * Add the Settings link on the network's Plugins screen.
     *
     * @param array $links Action links.
     * @return array
     */
    public static function plugin_action_links($links) {
        array_unshift($links, sprintf('<a href="%s">%s</a>', esc_url(self::page_url()), esc_html__('Settings', 'wp-plugin-starter-template')));
        return $links;
    }

    /**
     * Render a card's network part (WPStarter_Settings_Manager::render_card()
     * on the network screen): Apply to every site and the sites that differ.
     *
     * @param string $key Card's setting key.
     */
    public static function render_card_network($key) {
        $id = 'wps-' . $key . '-network';
        ?>
        <div class="wps-network">
            <label class="wps-network__apply" for="<?php echo esc_attr($id); ?>">
                <input type="checkbox"
                       id="<?php echo esc_attr($id); ?>"
                       data-wps-network-apply="<?php echo esc_attr($key); ?>"
                       aria-describedby="<?php echo esc_attr($id); ?>-sites"
                       <?php checked(WPStarter_Network_Settings::is_applied($key)); ?> />
                <?php esc_html_e('Apply to every site', 'wp-plugin-starter-template'); ?>
            </label>
            <span class="wps-status" data-wps-status="<?php echo esc_attr($key); ?>:network" aria-hidden="true"></span>
            <div class="wps-network__sites" id="<?php echo esc_attr($id); ?>-sites">
                <?php self::render_sites($key); ?>
            </div>
        </div>
        <?php
    }

    /**
     * Render which sites have their own different values for a card, with
     * Make every site the same (sites()). The script draws the same from
     * an AJAX reply (Network.sites() in admin/js/wpstarter-admin.js).
     *
     * @param string $key Card's setting key.
     */
    private static function render_sites($key) {
        $sites = self::sites($key);
        foreach ($sites['lines'] as $line) {
            echo '<p>';
            foreach ($line as $part) {
                if (isset($part['url'])) {
                    printf('<a href="%1$s">%2$s</a>', esc_url($part['url']), esc_html($part['text']));
                } else {
                    echo esc_html($part['text']);
                }
            }
            echo '</p>';
        }
        if ('' !== $sites['copy']) {
            printf(
                '<p><button type="button" class="button" data-wps-network-copy="%1$s">%2$s</button></p>',
                esc_attr($key),
                esc_html($sites['copy'])
            );
        }
    }

    /**
     * What a card's sites part says: lines of text and links naming the
     * sites whose own values differ, and the label of Make every site the
     * same when it is offered. AJAX replies send it as it is, so the script
     * builds the part from text and never inserts markup.
     *
     * @param string $key Card's setting key.
     * @return array{lines:array<int,array<int,array{text:string,url?:string}>>,copy:string}
     */
    private static function sites($key) {
        $differences = WPStarter_Network_Differences::differences();
        $applied     = WPStarter_Network_Settings::is_applied($key);
        if (!$differences['checked']) {
            /* translators: %d: number of sites */
            return self::note(sprintf(__('This network has more than %d sites, so they are not compared here.', 'wp-plugin-starter-template'), WPStarter_Network_Differences::MAX_SITES));
        }
        if (!$differences['total']) {
            return self::note(__('No site has used WP Plugin Starter yet. Each starts with these settings.', 'wp-plugin-starter-template'));
        }
        $ids = $differences['cards'][$key] ?? array();
        if (!$ids) {
            return self::note($applied ? __('Every site uses these settings.', 'wp-plugin-starter-template') : __('Every site has these settings.', 'wp-plugin-starter-template'));
        }

        $count = count($ids);
        $text  = $applied
            /* translators: 1: number of sites that differ, 2: number of sites, 3: list of those sites */
            ? _n('Every site uses these settings. When they stop applying, %1$d of %2$d sites goes back to different settings of its own: %3$s.', 'Every site uses these settings. When they stop applying, %1$d of %2$d sites go back to different settings of their own: %3$s.', $count, 'wp-plugin-starter-template')
            /* translators: 1: number of sites that differ, 2: number of sites, 3: list of those sites */
            : _n('%1$d of %2$d sites has different settings of its own: %3$s.', '%1$d of %2$d sites have different settings of their own: %3$s.', $count, 'wp-plugin-starter-template');
        return array(
            'lines' => array(self::fill($text, array(1 => $count, 2 => $differences['total'], 3 => self::site_links($key, $ids, $differences['sites'])))),
            'copy'  => __('Make every site the same', 'wp-plugin-starter-template'),
        );
    }

    /**
     * One line about the sites, with nothing to offer.
     *
     * @param string $text Text.
     * @return array{lines:array<int,array<int,array{text:string,url?:string}>>,copy:string}
     */
    private static function note($text) {
        return array('lines' => array(array(self::part($text))), 'copy' => '');
    }

    /**
     * One part of a line about the sites: text, or a link when it has an
     * address.
     *
     * @param string      $text Text.
     * @param string|null $url  Address of the link.
     * @return array{text:string,url?:string}
     */
    private static function part($text, $url = null) {
        $part = array('text' => (string) $text);
        if (null !== $url) {
            $part['url'] = (string) $url;
        }
        return $part;
    }

    /**
     * Links to the sites that differ, as parts of a line: the first
     * SITES_NAMED by name, then how many more. Each opens the card's tab on
     * that site's settings screen.
     *
     * @param string                                   $key   Card's setting key.
     * @param int[]                                    $ids   The sites that differ.
     * @param array<int,array{name:string,url:string}> $sites Site ID => name and address (WPStarter_Network_Differences::differences()).
     * @return array<int,array{text:string,url?:string}>
     */
    private static function site_links($key, array $ids, array $sites) {
        $schema = WPStarter_Settings::schema();
        $args   = empty($schema[$key]['tab']) ? array() : array('tab' => (string) $schema[$key]['tab']);
        $links  = array();
        foreach (array_slice($ids, 0, self::SITES_NAMED) as $site_id) {
            if ($links) {
                $links[] = self::part(', ');
            }
            $site    = $sites[$site_id];
            $links[] = self::part('' !== trim($site['name']) ? $site['name'] : $site['url'], self::site_url($site['url'], $args));
        }
        $more = count($ids) - self::SITES_NAMED;
        if ($more > 0) {
            /* translators: 1: list of sites, 2: number of other sites */
            $links = self::fill(_n('%1$s and %2$d more', '%1$s and %2$d more', $more, 'wp-plugin-starter-template'), array(1 => $links, 2 => $more));
        }
        return $links;
    }

    /**
     * A translated text as parts of a line, its numbered placeholders
     * (%1$s, %2$d) filled with numbers, text or parts (a list of links).
     * A placeholder without a value is left out.
     *
     * @param string           $text Translated text.
     * @param array<int,mixed> $args Placeholder number => value.
     * @return array<int,array{text:string,url?:string}>
     */
    private static function fill($text, array $args) {
        $pieces = preg_split('/%(\d+)\$[sd]/', (string) $text, -1, PREG_SPLIT_DELIM_CAPTURE);
        $parts  = array();
        foreach (is_array($pieces) ? $pieces : array((string) $text) as $i => $piece) {
            // Odd pieces are the placeholders' numbers.
            $value = $i % 2 ? ($args[(int) $piece] ?? '') : $piece;
            if (is_array($value)) {
                $parts = array_merge($parts, $value);
            } elseif ('' !== (string) $value) {
                $parts[] = self::part((string) $value);
            }
        }
        return $parts;
    }

    /**
     * Address of the screen on another site of the network, from its
     * siteurl option (get_admin_url() would load that site's options).
     *
     * @param string $site_url The site's siteurl.
     * @param array  $args     Extra query args.
     * @return string
     */
    private static function site_url($site_url, array $args) {
        $url = set_url_scheme(trailingslashit((string) $site_url) . 'wp-admin/' . WPStarter_Admin_Manager::screen_file(), 'admin');
        return esc_url_raw(add_query_arg(array_merge(array('page' => WPStarter_Admin_Manager::PAGE), $args), $url));
    }

    /**
     * Check an AJAX request from the network screen, and read its setting key.
     *
     * @return string Setting key.
     */
    private static function ajax_key() {
        check_ajax_referer(WPStarter_Settings::NONCE, 'nonce');
        if (!is_multisite() || !current_user_can('manage_network_options')) {
            wp_send_json_error(array('message' => __('You are not allowed to change the network’s settings.', 'wp-plugin-starter-template')), 403);
        }
        return isset($_POST['key']) ? sanitize_key(wp_unslash($_POST['key'])) : '';
    }

    /**
     * AJAX: save a network value. While its card is applied, every site
     * uses it from its next request, and runs its saving work on its next
     * admin, cron or WP-CLI request.
     */
    public static function ajax_save() {
        $key = self::ajax_key();
        // phpcs:ignore WordPress.Security.ValidatedSanitizedInput.InputNotSanitized,WordPress.Security.NonceVerification.Missing -- sanitized per schema in set_value(); nonce checked in ajax_key().
        $raw = isset($_POST['value']) ? wp_unslash($_POST['value']) : '';

        $value = WPStarter_Network_Settings::set_value($key, $raw);
        if (is_wp_error($value)) {
            wp_send_json_error(array('message' => $value->get_error_message()), 400);
        }

        $card = WPStarter_Settings::card_of($key);
        wp_send_json_success(array(
            'key'     => $key,
            'value'   => $value,
            'message' => __('Saved', 'wp-plugin-starter-template'),
            'reload'  => false,
            'card'    => $card,
            'sites'   => self::sites($card),
        ));
    }

    /**
     * AJAX: apply a card to every site, or stop applying it.
     */
    public static function ajax_apply() {
        $key = self::ajax_key();
        // phpcs:ignore WordPress.Security.NonceVerification.Missing -- nonce checked in ajax_key().
        $apply = isset($_POST['apply']) && '1' === sanitize_key(wp_unslash($_POST['apply']));

        $result = WPStarter_Network_Settings::apply($key, $apply);
        if (is_wp_error($result)) {
            wp_send_json_error(array('message' => $result->get_error_message()), 400);
        }

        wp_send_json_success(array(
            'key'     => $key,
            'applied' => $apply,
            'message' => $apply
                ? __('Every site now uses these settings.', 'wp-plugin-starter-template')
                : __('Each site uses its own settings again.', 'wp-plugin-starter-template'),
            'sites'   => self::sites($key),
        ));
    }

    /**
     * AJAX: Make every site the same, for one card.
     */
    public static function ajax_copy() {
        $key     = self::ajax_key();
        $changed = WPStarter_Network_Differences::copy($key);
        if (is_wp_error($changed)) {
            wp_send_json_error(array('message' => $changed->get_error_message()), 400);
        }

        wp_send_json_success(array(
            'key'     => $key,
            'changed' => $changed,
            'message' => $changed
                /* translators: %d: number of sites */
                ? sprintf(_n('%d site now has these settings.', '%d sites now have these settings.', $changed, 'wp-plugin-starter-template'), $changed)
                : __('Every site already has these settings.', 'wp-plugin-starter-template'),
            'sites'   => self::sites($key),
        ));
    }
}
