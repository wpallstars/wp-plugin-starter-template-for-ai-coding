<?php
/**
 * Plugins screen: plugins WP Plugin Starter can replace.
 *
 * Lists installed plugins that a setting's `replaces` names:
 * - active, with every setting that replaces it on: the plugin can go, with a
 *   Deactivate link (the settings wait until it is deactivated);
 * - active, with a replacing setting off: WP Plugin Starter can do this job, with
 *   a link to the settings (only for people who can change them);
 * - installed but inactive, with every replacing setting on: no longer
 *   needed, with a Delete link (single sites; on multisite a plugin may be
 *   active on another site).
 * While an active plugin does things here that WP Plugin Starter does not (the
 * `wpstarter_replaced_plugin_extras` filter), the notice names them
 * instead of saying the plugin can go.
 *
 * Each of those plugins, and inactive ones whose replacing setting is off,
 * also gets a note under its own row with the same step.
 *
 * Shown on the Plugins screen to people who can activate plugins. "Hide"
 * hides the plugins listed at the time for that person; a plugin that needs
 * a different step later shows again.
 *
 * @package WPStarter
 * @since 0.7.0
 */

if (!defined('ABSPATH')) {
    exit;
}

class WPStarter_Replaced_Plugins {

    /** admin-post action, also the nonce action. */
    const HIDE = 'wpstarter_hide_replaced_plugins';

    /** User meta: list of "slug:step" items the person hid. */
    const HIDDEN = 'wpstarter_replaced_plugins_hidden';

    /** admin-post action that deactivates a replaced plugin and comes back. */
    const DEACTIVATE = 'wpstarter_deactivate_replaced';

    /** Query argument on the page it comes back to. */
    const DONE = 'wpstarter-deactivated';

    /**
     * Register hooks.
     */
    public static function init() {
        add_action('load-plugins.php', array(__CLASS__, 'load_screen'));
        add_action('admin_post_' . self::HIDE, array(__CLASS__, 'hide'));
        add_action('admin_post_' . self::DEACTIVATE, array(__CLASS__, 'deactivate'));
        // phpcs:ignore WordPress.Security.NonceVerification.Recommended -- only shows a message.
        if (isset($_GET[self::DONE])) {
            add_action('admin_notices', array(__CLASS__, 'deactivated_notice'));
        }
    }

    /**
     * Plugins screen: add the notice and the notes on each plugin's row.
     */
    public static function load_screen() {
        if (!current_user_can('activate_plugins')) {
            return;
        }
        add_action(is_network_admin() ? 'network_admin_notices' : 'admin_notices', array(__CLASS__, 'notice'));
        add_action('after_plugin_row', array(__CLASS__, 'row_note'), 10, 1);
        add_action('admin_head', array(__CLASS__, 'row_note_style'));
    }

    /**
     * Join a row note to its plugin's row, as core does for update notes.
     */
    public static function row_note_style() {
        echo '<style>.plugins tr:has(+ tr.wps-replaced-row) th, .plugins tr:has(+ tr.wps-replaced-row) td { box-shadow: none; }</style>' . "\n";
    }

    /**
     * Link that deactivates a replaced plugin on this site and comes back to
     * the page it was clicked on.
     *
     * @param string $file Plugin file.
     * @return string Unescaped URL.
     */
    public static function deactivate_url($file) {
        return wp_nonce_url(add_query_arg(array(
            'action'           => self::DEACTIVATE,
            'plugin'           => rawurlencode($file),
            '_wp_http_referer' => rawurlencode(remove_query_arg(array(self::DONE, 'deactivate', 'activate'))),
        ), admin_url('admin-post.php')), self::DEACTIVATE . '_' . $file);
    }

    /**
     * Core's deactivate link on the Plugins screen, keeping the list's
     * status, page and search, so it comes back to the same list.
     *
     * @param string $file Plugin file.
     * @return string Unescaped URL.
     */
    private static function plugins_deactivate_url($file) {
        // phpcs:disable WordPress.Security.NonceVerification.Recommended -- the list being shown.
        $args = array(
            'action'        => 'deactivate',
            'plugin'        => rawurlencode($file),
            'plugin_status' => isset($_GET['plugin_status']) ? sanitize_key(wp_unslash($_GET['plugin_status'])) : 'all',
            'paged'         => isset($_GET['paged']) ? absint($_GET['paged']) : 1,
            's'             => isset($_GET['s']) ? rawurlencode(sanitize_text_field(wp_unslash($_GET['s']))) : '',
        );
        // phpcs:enable
        return wp_nonce_url(add_query_arg($args, self_admin_url('plugins.php')), 'deactivate-plugin_' . $file);
    }

    /**
     * admin-post: deactivate a replaced plugin on this site, then go back.
     */
    public static function deactivate() {
        $file = isset($_GET['plugin']) ? sanitize_text_field(wp_unslash($_GET['plugin'])) : '';
        check_admin_referer(self::DEACTIVATE . '_' . $file);
        if ('' === $file || validate_file($file) || !current_user_can('deactivate_plugin', $file)) {
            wp_die(esc_html__('You are not allowed to deactivate this plugin.', 'wp-plugin-starter-template'), '', array('response' => 403));
        }
        if (!isset(self::replaced()[dirname($file)])) {
            wp_die(esc_html__('WP Plugin Starter only deactivates plugins it replaces.', 'wp-plugin-starter-template'), '', array('response' => 400));
        }
        if (!function_exists('is_plugin_active')) {
            require_once ABSPATH . 'wp-admin/includes/plugin.php';
        }
        $back = wp_get_referer();
        $back = $back ? $back : admin_url('plugins.php');
        // Network-wide plugins are deactivated in the network admin.
        if (in_array($file, self::stored_plugins(), true) && !is_plugin_active_for_network($file)) {
            deactivate_plugins($file);
            if (self::save_plugin_state($file, false)) {
                update_option('recently_activated', array($file => time()) + (array) get_option('recently_activated'), false);
                $back = add_query_arg(self::DONE, 1, $back);
            }
        }
        wp_safe_redirect($back);
        exit;
    }

    /**
     * Make sure a plugin's new state is saved, after core's activate_plugin()
     * or deactivate_plugins() has run its hooks.
     *
     * Plugins that load fewer plugins on some requests guard saves of
     * `active_plugins`. Freesoul Deactivate Plugins, for one, saves the full
     * list it read when the page loaded instead of the new one, unless the
     * request is the Plugins screen's own action, so a change made anywhere
     * else is lost without a word. When the stored list does not have the
     * change, save that one change to it, with those filters paused.
     *
     * @param string $file   Plugin file.
     * @param bool   $active Whether it should be active on this site.
     * @return bool Whether the stored list now has it that way.
     */
    public static function save_plugin_state($file, $active) {
        $stored = self::stored_plugins();
        if (in_array($file, $stored, true) === $active) {
            return true;
        }
        if ($active) {
            $stored[] = $file;
            sort($stored);
        } else {
            $stored = array_values(array_diff($stored, array($file)));
        }
        self::without_list_filters(function () use ($stored) {
            update_option('active_plugins', $stored);
        });
        return in_array($file, self::stored_plugins(), true) === $active;
    }

    /**
     * Plugins stored as active on this site, as saved: not as other plugins
     * filter the list for the current request.
     *
     * @return string[] Plugin files.
     */
    public static function stored_plugins() {
        $stored = self::without_list_filters(function () {
            return get_option('active_plugins', array());
        });
        return is_array($stored) ? array_values(array_filter($stored, 'is_string')) : array();
    }

    /**
     * Run a callback with the filters on reading and saving `active_plugins`
     * paused, then put them back.
     *
     * @param callable $callback Callback.
     * @return mixed What the callback returns.
     */
    private static function without_list_filters(callable $callback) {
        global $wp_filter;
        $paused = array();
        foreach (array('pre_option_active_plugins', 'option_active_plugins', 'pre_update_option_active_plugins') as $hook) {
            if (isset($wp_filter[$hook])) {
                $paused[$hook] = $wp_filter[$hook];
                unset($wp_filter[$hook]);
            }
        }
        try {
            return $callback();
        } finally {
            foreach ($paused as $hook => $filters) {
                $wp_filter[$hook] = $filters; // phpcs:ignore WordPress.WP.GlobalVariablesOverride.Prohibited -- puts back what was paused above.
            }
        }
    }

    /**
     * "Plugin deactivated." on the page the link came back to.
     */
    public static function deactivated_notice() {
        echo '<div class="notice notice-success is-dismissible"><p>' . esc_html__('Plugin deactivated.', 'wp-plugin-starter-template') . '</p></div>';
    }

    /**
     * A note under a replaced plugin's row on the Plugins screen: which
     * setting does its job and what to do next.
     *
     * @param string $file Plugin file.
     */
    public static function row_note($file) {
        global $wp_list_table;
        $states = self::states();
        if (!isset($states[$file])) {
            return;
        }
        $item   = $states[$file];
        $labels = esc_html(implode(', ', array_map(function ($label) {
            return '‘' . $label . '’';
        }, $item['settings'])));
        $setting = '';
        if (WPStarter_Settings::can_change()) {
            $setting = sprintf(' <a href="%1$s">%2$s</a>', esc_url(WPStarter_Admin_Manager::tab_url(WPStarter_Admin_Manager::SEARCH, array('s' => $item['name']))), esc_html__('Show the setting', 'wp-plugin-starter-template'));
        }
        $extras = esc_html(implode(', ', $item['extras']));

        switch ($item['step']) {
            case 'deactivate':
                /* translators: %s: WP Plugin Starter setting names */
                $text = sprintf(esc_html__('WP Plugin Starter makes this plugin redundant: %s is on and takes over once you deactivate this plugin. Then you can delete it.', 'wp-plugin-starter-template'), $labels);
                break;
            case 'partial':
                /* translators: 1: WP Plugin Starter setting names, 2: the plugin's settings WP Plugin Starter does not have */
                $text = sprintf(esc_html__('WP Plugin Starter can do this plugin\'s job: %1$s is on and takes over once you deactivate it, except for these, which WP Plugin Starter does not do: %2$s.', 'wp-plugin-starter-template'), $labels, $extras);
                break;
            case 'switch_on':
                /* translators: %s: WP Plugin Starter setting names */
                $text = sprintf(esc_html__('WP Plugin Starter makes this plugin redundant: turn on %s in WP Plugin Starter, then deactivate and delete this plugin.', 'wp-plugin-starter-template'), $labels) . $setting;
                break;
            case 'switch_on_partial':
                /* translators: 1: WP Plugin Starter setting names, 2: the plugin's settings WP Plugin Starter does not have */
                $text = sprintf(esc_html__('WP Plugin Starter can do part of this plugin\'s job with %1$s. It does not do these, which this plugin has on: %2$s.', 'wp-plugin-starter-template'), $labels, $extras) . $setting;
                break;
            case 'switch_on_inactive':
                /* translators: %s: WP Plugin Starter setting names */
                $text = sprintf(esc_html__('WP Plugin Starter makes this plugin redundant: turn on %s in WP Plugin Starter, then you can delete this plugin.', 'wp-plugin-starter-template'), $labels) . $setting;
                break;
            default:
                /* translators: %s: WP Plugin Starter setting names */
                $text = sprintf(esc_html__('No longer needed: %s in WP Plugin Starter does this plugin\'s job. You can delete it.', 'wp-plugin-starter-template'), $labels);
        }
        $columns = ($wp_list_table instanceof WP_List_Table) ? $wp_list_table->get_column_count() : 4;
        $active  = in_array($item['step'], array('deactivate', 'partial', 'switch_on', 'switch_on_partial'), true) ? ' active' : ' inactive';
        printf(
            '<tr class="plugin-update-tr wps-replaced-row%1$s"><td colspan="%2$d" class="plugin-update colspanchange"><div class="notice inline notice-info notice-alt"><p>%3$s</p></div></td></tr>',
            esc_attr($active),
            (int) $columns,
            $text // phpcs:ignore WordPress.Security.EscapeOutput -- built from escaped parts above.
        );
    }

    /**
     * Replaced plugins, keyed by folder name, with the settings that replace
     * them.
     *
     * @return array<string,array{name:string,settings:array<string,string>}> slug => name and setting key => label.
     */
    private static function replaced() {
        $replaced = array();
        foreach (WPStarter_Settings::schema() as $key => $field) {
            if (empty($field['replaces']) || !is_array($field['replaces']) || !empty($field['parent'])) {
                continue;
            }
            foreach ($field['replaces'] as $slug => $name) {
                if (!isset($replaced[$slug])) {
                    $replaced[$slug] = array('name' => (string) $name, 'settings' => array());
                }
                $replaced[$slug]['settings'][$key] = isset($field['label']) ? (string) $field['label'] : (string) $key;
            }
        }
        return $replaced;
    }

    /**
     * What to show in the notice: one item per installed replaced plugin that
     * needs a step, leaving out what the person hid.
     *
     * @return array<int,array{slug:string,file:string,name:string,step:string,settings:array<string,string>}>
     */
    private static function items() {
        $items = array_filter(self::states(), function ($item) {
            // Inactive with the setting off: only a note on its row.
            return 'switch_on_inactive' !== $item['step']
                && ('switch_on' !== $item['step'] || WPStarter_Settings::can_change());
        });
        $hidden = (array) get_user_meta(get_current_user_id(), self::HIDDEN, true);
        return array_values(array_filter($items, function ($item) use ($hidden) {
            return !in_array($item['slug'] . ':' . $item['step'], $hidden, true);
        }));
    }

    /**
     * Every installed replaced plugin that needs a step, keyed by plugin file.
     *
     * Steps: deactivate, partial (active, setting on, it does more),
     * switch_on, switch_on_partial, delete (inactive, setting on) and
     * switch_on_inactive (inactive, setting off; single sites only).
     *
     * @return array<string,array{slug:string,file:string,name:string,step:string,settings:array<string,string>,extras:string[]}>
     */
    private static function states() {
        static $states = null;
        if (null !== $states) {
            return $states;
        }
        if (!function_exists('get_plugins')) {
            require_once ABSPATH . 'wp-admin/includes/plugin.php';
        }
        $installed = array();
        foreach (array_keys(get_plugins()) as $file) {
            $slug = dirname($file);
            if ('.' !== $slug) {
                $installed[$slug] = $file;
            }
        }

        $network = is_multisite() && is_network_admin();
        // Active where this screen can deactivate it: network-wide in the
        // network admin, on this site otherwise. Stored lists, so plugins
        // skipped on this screen still count.
        $here = $network
            ? array_keys((array) get_site_option('active_sitewide_plugins', array()))
            : WPStarter_Feature::stored_active_plugins();
        $all  = WPStarter_Feature::active_plugins();

        $items = array();
        foreach (self::replaced() as $slug => $plugin) {
            if (!isset($installed[$slug])) {
                continue;
            }
            $file   = $installed[$slug];
            $all_on = true;
            foreach (array_keys($plugin['settings']) as $key) {
                $all_on = $all_on && (bool) WPStarter_Settings::get($key);
            }

            if (in_array($file, $here, true)) {
                $step = $all_on ? 'deactivate' : 'switch_on';
            } elseif (!isset($all[$slug]) && !is_multisite()) {
                $step = $all_on ? 'delete' : 'switch_on_inactive';
            } else {
                continue;
            }
            $extras = array();
            if ('deactivate' === $step || 'switch_on' === $step) {
                /**
                 * What a replaced plugin does on this site that WP Plugin Starter,
                 * as set up, does not. When there is any, the notice lists it
                 * instead of saying the plugin can go.
                 *
                 * @param string[] $extras Plain names.
                 * @param string   $slug   Plugin folder.
                 */
                $extras = array_values(array_filter(array_map('strval', (array) apply_filters('wpstarter_replaced_plugin_extras', array(), (string) $slug))));
            }
            if ($extras) {
                $step = 'deactivate' === $step ? 'partial' : 'switch_on_partial';
            }
            $items[$file] = array(
                'slug'     => (string) $slug,
                'file'     => $file,
                'name'     => $plugin['name'],
                'step'     => $step,
                'settings' => $plugin['settings'],
                'extras'   => $extras,
            );
        }
        $states = $items;
        return $states;
    }

    /**
     * The notice.
     */
    public static function notice() {
        $items = self::items();
        if (!$items) {
            return;
        }
        $rows = array();
        foreach ($items as $item) {
            $rows[] = self::row($item);
        }
        $keys = array_map(function ($item) {
            return $item['slug'] . ':' . $item['step'];
        }, $items);
        $hide = wp_nonce_url(add_query_arg(array('action' => self::HIDE, 'items' => implode(',', $keys)), admin_url('admin-post.php')), self::HIDE);
        ?>
        <div class="notice notice-info wps-replaced-plugins">
            <p><strong><?php esc_html_e('WP Plugin Starter can do the job of these plugins:', 'wp-plugin-starter-template'); ?></strong></p>
            <ul class="ul-disc">
                <?php foreach ($rows as $row) : ?>
                    <li><?php echo $row; // phpcs:ignore WordPress.Security.EscapeOutput -- built from escaped parts in row(). ?></li>
                <?php endforeach; ?>
            </ul>
            <p><a href="<?php echo esc_url($hide); ?>"><?php esc_html_e('Hide', 'wp-plugin-starter-template'); ?></a></p>
        </div>
        <?php
    }

    /**
     * One line of the notice.
     *
     * @param array $item Item from items().
     * @return string HTML.
     */
    private static function row(array $item) {
        $labels = implode(', ', array_map(function ($label) {
            return '‘' . $label . '’';
        }, $item['settings']));
        $name   = '<strong>' . esc_html($item['name']) . '</strong>';
        $base   = self_admin_url('plugins.php');

        if ('deactivate' === $item['step']) {
            /* translators: 1: plugin name, 2: WP Plugin Starter setting names */
            $text = sprintf(esc_html__('%1$s: %2$s is on and takes over once you deactivate it. Then you can delete it.', 'wp-plugin-starter-template'), $name, esc_html($labels));
            if (current_user_can('deactivate_plugin', $item['file'])) {
                $url   = self::plugins_deactivate_url($item['file']);
                /* translators: %s: plugin name */
                $text .= sprintf(' <a href="%1$s">%2$s</a>', esc_url($url), esc_html(sprintf(__('Deactivate %s', 'wp-plugin-starter-template'), $item['name'])));
            }
            return $text;
        }

        if ('partial' === $item['step'] || 'switch_on_partial' === $item['step']) {
            $extras = esc_html(implode(', ', $item['extras']));
            if ('partial' === $item['step']) {
                /* translators: 1: plugin name, 2: WP Plugin Starter setting names, 3: the plugin's settings WP Plugin Starter does not have */
                $text = sprintf(esc_html__('%1$s: %2$s is on and takes over once you deactivate it, except for these, which WP Plugin Starter does not do: %3$s. Deactivate it only if you no longer need them.', 'wp-plugin-starter-template'), $name, esc_html($labels), $extras);
                if (current_user_can('deactivate_plugin', $item['file'])) {
                    $url   = self::plugins_deactivate_url($item['file']);
                    /* translators: %s: plugin name */
                    $text .= sprintf(' <a href="%1$s">%2$s</a>', esc_url($url), esc_html(sprintf(__('Deactivate %s', 'wp-plugin-starter-template'), $item['name'])));
                }
                return $text;
            }
            /* translators: 1: plugin name, 2: WP Plugin Starter setting names, 3: the plugin's settings WP Plugin Starter does not have */
            $text = sprintf(esc_html__('%1$s: %2$s can do part of its job. WP Plugin Starter does not do these, which it has on: %3$s.', 'wp-plugin-starter-template'), $name, esc_html($labels), $extras);
            $url  = WPStarter_Admin_Manager::tab_url(WPStarter_Admin_Manager::SEARCH, array('s' => $item['name']));
            return $text . sprintf(' <a href="%1$s">%2$s</a>', esc_url($url), esc_html__('Show the setting', 'wp-plugin-starter-template'));
        }

        if ('delete' === $item['step']) {
            /* translators: 1: plugin name, 2: WP Plugin Starter setting names */
            $text = sprintf(esc_html__('%1$s is inactive and no longer needed: %2$s does its job.', 'wp-plugin-starter-template'), $name, esc_html($labels));
            if (current_user_can('delete_plugins')) {
                $url   = wp_nonce_url(add_query_arg(array('action' => 'delete-selected', 'checked[]' => $item['file'], 'plugin_status' => 'all'), $base), 'bulk-plugins');
                /* translators: %s: plugin name */
                $text .= sprintf(' <a href="%1$s">%2$s</a>', esc_url($url), esc_html(sprintf(__('Delete %s', 'wp-plugin-starter-template'), $item['name'])));
            }
            return $text;
        }

        /* translators: 1: plugin name, 2: WP Plugin Starter setting names */
        $text = sprintf(esc_html__('%1$s: switch on %2$s, then deactivate and delete it.', 'wp-plugin-starter-template'), $name, esc_html($labels));
        $url  = WPStarter_Admin_Manager::tab_url(WPStarter_Admin_Manager::SEARCH, array('s' => $item['name']));
        return $text . sprintf(' <a href="%1$s">%2$s</a>', esc_url($url), esc_html__('Show the setting', 'wp-plugin-starter-template'));
    }

    /**
     * admin-post: hide the listed items for this person.
     */
    public static function hide() {
        check_admin_referer(self::HIDE);
        if (!current_user_can('activate_plugins')) {
            wp_die(esc_html__('You are not allowed to manage plugins on this site.', 'wp-plugin-starter-template'), '', array('response' => 403));
        }
        $items  = isset($_GET['items']) ? explode(',', sanitize_text_field(wp_unslash($_GET['items']))) : array();
        $items  = array_filter($items, function ($item) {
            return (bool) preg_match('/^[A-Za-z0-9._-]+:(deactivate|switch_on|delete|partial|switch_on_partial)$/', $item);
        });
        $hidden = (array) get_user_meta(get_current_user_id(), self::HIDDEN, true);
        update_user_meta(get_current_user_id(), self::HIDDEN, array_values(array_unique(array_filter(array_merge($hidden, $items)))));

        $back = wp_get_referer();
        wp_safe_redirect($back ? $back : self_admin_url('plugins.php'));
        exit;
    }
}
