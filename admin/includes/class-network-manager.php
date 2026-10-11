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
 *
 * @package WPStarter
 * @since 1.0.34
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
        self::$hook = is_string($hook) ? $hook : '';
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
     * @param string $key   Card's setting key.
     * @param array  $field Schema entry.
     */
    public static function render_card_network($key, array $field) {
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
            <div class="wps-network__sites" id="<?php echo esc_attr($id); ?>-sites" data-wps-network-sites="<?php echo esc_attr($key); ?>">
                <?php self::render_sites($key, isset($field['tab']) ? (string) $field['tab'] : ''); ?>
            </div>
        </div>
        <?php
    }

    /**
     * Render which sites have their own different values for a card, with
     * Make every site the same.
     *
     * @param string $key Card's setting key.
     * @param string $tab The card's tab, for the links to each site.
     */
    private static function render_sites($key, $tab) {
        $differences = WPStarter_Network_Settings::differences();
        $applied     = WPStarter_Network_Settings::is_applied($key);
        if (!$differences['checked']) {
            /* translators: %d: number of sites */
            self::note(sprintf(__('This network has more than %d sites, so they are not compared here.', 'wp-plugin-starter-template'), WPStarter_Network_Settings::MAX_SITES));
            return;
        }
        if (!$differences['total']) {
            self::note(__('No site has used WP Plugin Starter yet. Each starts with these settings.', 'wp-plugin-starter-template'));
            return;
        }

        $ids = isset($differences['cards'][$key]) ? $differences['cards'][$key] : array();
        if (!$ids) {
            self::note($applied ? __('Every site uses these settings.', 'wp-plugin-starter-template') : __('Every site has these settings.', 'wp-plugin-starter-template'));
            return;
        }

        $count = count($ids);
        $links = array();
        foreach (array_slice($ids, 0, self::SITES_NAMED) as $site_id) {
            $site    = $differences['sites'][$site_id];
            $links[] = sprintf(
                '<a href="%1$s">%2$s</a>',
                esc_url(WPStarter_Admin_Manager::site_page_url($site['url'], '' !== $tab ? array('tab' => $tab) : array())),
                esc_html('' !== trim($site['name']) ? $site['name'] : $site['url'])
            );
        }
        $list = implode(', ', $links);
        $more = $count - count($links);
        if ($more) {
            /* translators: 1: list of sites, 2: number of other sites */
            $list = sprintf(esc_html(_n('%1$s and %2$d more', '%1$s and %2$d more', $more, 'wp-plugin-starter-template')), $list, $more);
        }
        $text = $applied
            /* translators: 1: number of sites that differ, 2: number of sites, 3: list of those sites */
            ? _n('Every site uses these settings. When they stop applying, %1$d of %2$d sites goes back to different settings of its own: %3$s.', 'Every site uses these settings. When they stop applying, %1$d of %2$d sites go back to different settings of their own: %3$s.', $count, 'wp-plugin-starter-template')
            /* translators: 1: number of sites that differ, 2: number of sites, 3: list of those sites */
            : _n('%1$d of %2$d sites has different settings of its own: %3$s.', '%1$d of %2$d sites have different settings of their own: %3$s.', $count, 'wp-plugin-starter-template');
        ?>
        <p><?php printf(esc_html($text), (int) $count, (int) $differences['total'], $list); // phpcs:ignore WordPress.Security.EscapeOutput -- the text is escaped; the list holds links escaped above. ?></p>
        <p>
            <button type="button" class="button" data-wps-network-copy="<?php echo esc_attr($key); ?>"><?php esc_html_e('Make every site the same', 'wp-plugin-starter-template'); ?></button>
        </p>
        <?php
    }

    /**
     * Render one line about the sites.
     *
     * @param string $text Text.
     */
    private static function note($text) {
        echo '<p>' . esc_html($text) . '</p>';
    }

    /**
     * A card's sites, as render_sites() draws them, for an AJAX reply.
     *
     * @param string $key Card's setting key.
     * @return string HTML.
     */
    private static function sites_html($key) {
        $schema = WPStarter_Settings::schema();
        ob_start();
        self::render_sites($key, isset($schema[$key]['tab']) ? (string) $schema[$key]['tab'] : '');
        return (string) ob_get_clean();
    }

    /**
     * The card a setting is on: its own key, or its parent's.
     *
     * @param string $key Setting key.
     * @return string
     */
    private static function card_of($key) {
        $schema = WPStarter_Settings::schema();
        return !empty($schema[$key]['parent']) ? (string) $schema[$key]['parent'] : (string) $key;
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

        $card = self::card_of($key);
        wp_send_json_success(array(
            'key'     => $key,
            'value'   => $value,
            'message' => __('Saved', 'wp-plugin-starter-template'),
            'reload'  => false,
            'card'    => $card,
            'sites'   => self::sites_html($card),
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
            'sites'   => self::sites_html($key),
        ));
    }

    /**
     * AJAX: Make every site the same, for one card.
     */
    public static function ajax_copy() {
        $key     = self::ajax_key();
        $changed = WPStarter_Network_Settings::copy($key);
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
            'sites'   => self::sites_html($key),
        ));
    }
}
