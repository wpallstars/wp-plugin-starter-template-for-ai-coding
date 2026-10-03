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
     * Register hooks.
     */
    public static function init() {
        // Priority 0, before WPStarter::boot_features() so features read
        // migrated values, and before widgets_init (init:1).
        add_action('init', array(__CLASS__, 'maybe_migrate'), 0);
        add_action('admin_init', array(__CLASS__, 'register_setting'));
        add_action('wp_ajax_wpstarter_save_setting', array(__CLASS__, 'ajax_save'));
        add_filter('option_page_capability_' . self::GROUP, array(__CLASS__, 'capability'));
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
        $options = is_callable($field['options']) ? call_user_func($field['options']) : $field['options'];
        return is_array($options) ? $options : array();
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
     * All settings merged over defaults.
     *
     * @return array
     */
    public static function all() {
        $stored = get_option(self::OPTION, array());
        if (!is_array($stored)) {
            $stored = array();
        }
        return array_merge(self::defaults(), array_intersect_key($stored, self::schema()));
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

        // Read what is stored now, not the copy loaded when this request
        // began, so a save made meanwhile is not overwritten.
        self::flush_cache();
        $options       = self::all();
        $options[$key] = self::sanitize_value($value, $schema[$key]);
        update_option(self::OPTION, $options);

        if (!self::stored($key, $options[$key])) {
            return new WP_Error('wpstarter_not_saved', __('The setting could not be saved. Please try again.', 'wp-plugin-starter-template'));
        }
        return $options[$key];
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
            if (!empty($field['parent']) || empty($field['tab'])) {
                continue;
            }

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

            $text = implode(' ', array_map('strval', $haystack));
            $found = function_exists('mb_stripos') ? mb_stripos($text, $query) : stripos($text, $query);
            if (false !== $found) {
                $matches[$key] = $field;
            }
        }

        return $matches;
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
        $type    = isset($field['type']) ? $field['type'] : 'text';
        $default = isset($field['default']) ? $field['default'] : null;

        switch ($type) {
            case 'bool':
                return rest_sanitize_boolean($value);

            case 'int':
                $value = is_numeric($value) ? (int) $value : (int) $default;
                if (isset($field['min'])) {
                    $value = max((int) $field['min'], $value);
                }
                if (isset($field['max'])) {
                    $value = min((int) $field['max'], $value);
                }
                return $value;

            case 'domains':
                return implode("\n", self::parse_domains($value));

            case 'media':
                // A Media Library picture's ID, or 0.
                $value = is_numeric($value) ? absint($value) : 0;
                return $value && wp_attachment_is_image($value) ? $value : 0;

            case 'select':
                $value = is_scalar($value) ? (string) $value : '';
                if (array_key_exists($value, self::options_for($field))) {
                    return $value;
                }
                // Open selects (another plugin's board or course) keep an
                // identifier whose plugin is not loaded on this request.
                return !empty($field['open']) && strlen($value) <= 200 && preg_match('/^[A-Za-z0-9_-]+$/', $value) ? $value : $default;

            case 'multi':
                $values = is_array($value) ? $value : preg_split('/\s*,\s*/', (string) $value, -1, PREG_SPLIT_NO_EMPTY);
                $values = array_map('strval', array_filter((array) $values, 'is_scalar'));
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

            case 'times':
                return implode(', ', self::parse_times($value));

            case 'url':
                $value = trim((string) $value);
                if ('' === $value) {
                    return '';
                }
                if ('/' === $value[0] && '/' !== substr($value, 1, 1)) {
                    // Site path: keep it relative so it survives domain changes.
                    return '/' . ltrim(preg_replace('/\s+/', '', sanitize_text_field($value)), '/');
                }
                return esc_url_raw($value, array('http', 'https'));

            case 'lines':
                $lines = preg_split('/[\r\n]+/', (string) $value);
                // Not sanitize_text_field(): it strips %xx, which URL paths need.
                $lines = array_filter(array_map(function ($line) {
                    return trim(preg_replace('/[\x00-\x1F\x7F]+/', '', wp_strip_all_tags($line)));
                }, $lines), function ($line) {
                    return '' !== $line;
                });
                return implode("\n", array_values(array_unique($lines)));

            case 'text':
            default:
                $value = (string) $value;
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
    }

    /**
     * Normalise a newline/comma separated domain list to bare lowercase hosts.
     *
     * @param mixed $value Raw list.
     * @return string[]
     */
    public static function parse_domains($value) {
        $lines   = preg_split('/[\r\n,]+/', (string) $value);
        $domains = array();

        foreach ($lines as $line) {
            $line = trim($line);
            if ('' === $line) {
                continue;
            }
            $host = wp_parse_url(false === strpos($line, '://') ? 'http://' . $line : $line, PHP_URL_HOST);
            $host = $host ? strtolower(preg_replace('/^www\./i', '', $host)) : '';
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
        $host = strtolower(preg_replace('/^www\./i', '', (string) $host));
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
        preg_match_all('/(\d{1,2})(?:[:.](\d{2}))?\s*(am|pm)?/i', (string) $value, $matches, PREG_SET_ORDER);
        $times = array();

        foreach ($matches as $match) {
            $hour   = (int) $match[1];
            $minute = isset($match[2]) && '' !== $match[2] ? (int) $match[2] : 0;
            $suffix = isset($match[3]) ? strtolower($match[3]) : '';
            if ('pm' === $suffix && $hour < 12) {
                $hour += 12;
            } elseif ('am' === $suffix && 12 === $hour) {
                $hour = 0;
            }
            if ($hour > 23 || $minute > 59) {
                continue;
            }
            $times[] = sprintf('%02d:%02d', $hour, $minute);
        }

        $times = array_values(array_unique($times));
        sort($times);
        return $times;
    }

    /**
     * Sanitize the whole array when saved through options.php or update_option().
     *
     * @param mixed $input Raw option value.
     * @return array
     */
    public static function sanitize_all($input) {
        $input  = is_array($input) ? $input : array();
        $schema = self::schema();
        $clean  = self::all();

        foreach ($input as $key => $value) {
            if (isset($schema[$key])) {
                $clean[$key] = self::sanitize_value($value, $schema[$key]);
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

        $clean = self::sanitize_all($options);
        update_option(self::OPTION, $clean);

        // Only record the version once the settings are stored, so a failed
        // write is retried on the next request instead of losing imports.
        self::flush_cache();
        if (get_option(self::OPTION) != $clean) { // phpcs:ignore Universal.Operators.StrictComparisons -- key order may differ.
            return;
        }
        update_option(self::DB_VERSION_OPTION, self::DB_VERSION);
    }
}
