<?php
/**
 * Base class for WP Plugin Starter features.
 *
 * A feature is a self-contained class that:
 * - declares its settings in settings() (the on/off switch first, keyed by KEY,
 *   then any options with 'parent' => KEY);
 * - registers its hooks in boot(), which runs on `init` (priority 0, before
 *   widgets_init) for every registered feature. Disabled features should
 *   return early so they cost nothing;
 * - optionally imports settings from the plugin it replaces in migrate().
 *
 * While a plugin that a setting replaces is active, the setting waits:
 * enabled() is false and that plugin keeps doing the job, so the two never
 * run side by side (two admin bar menus, analytics loaded twice). The
 * settings card says so, with a deactivate link.
 *
 * Register extra features with the `wpstarter_features` filter.
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 * SPDX-FileCopyrightText: 2026 Marcus Quinn
 * Additional terms (GPL-3.0 section 7(b)): ATTRIBUTION.txt
 *
 * @package WPStarter
 * @since 0.3.0
 */

if (!defined('ABSPATH')) {
    exit;
}

abstract class WPStarter_Feature {

    /** Setting key of the feature's on/off switch. */
    const KEY = '';

    /**
     * Settings schema entries for this feature.
     *
     * @return array<string,array>
     */
    public static function settings() {
        return array();
    }

    /**
     * Whether the feature is switched on and not waiting for a plugin it
     * replaces to be deactivated.
     *
     * @return bool
     */
    public static function enabled() {
        return static::switched_on() && !self::replaced_active(static::KEY);
    }

    /**
     * Whether the feature's switch is on, even if it is waiting.
     *
     * @return bool
     */
    public static function switched_on() {
        return '' !== static::KEY && (bool) WPStarter_Settings::get(static::KEY);
    }

    /**
     * Names of the active plugins that a setting replaces.
     *
     * @param string $key Setting key.
     * @return array<string,string> slug => name
     */
    public static function replaced_active($key) {
        $schema = WPStarter_Settings::schema();
        if (empty($schema[$key]['replaces']) || !is_array($schema[$key]['replaces'])) {
            return array();
        }
        return array_intersect_key($schema[$key]['replaces'], self::active_plugins());
    }

    /**
     * Whether a listed plugin file is one WordPress would load: a valid path
     * to a file that exists, as wp_get_active_and_valid_plugins() checks. A
     * plugin deleted while active stays listed until the Plugins screen is
     * opened.
     *
     * @param string $file Plugin file, such as "akismet/akismet.php".
     * @return bool
     */
    public static function plugin_installed($file) {
        $file = (string) $file;
        return '' !== $file && 0 === validate_file($file) && is_file(WP_PLUGIN_DIR . '/' . $file);
    }

    /**
     * Plugins active on this site or network-wide, keyed by folder name.
     * Listed plugins whose files are gone are left out.
     *
     * @return array<string,string> slug => plugin file
     */
    public static function active_plugins() {
        static $active = null;
        if (null === $active) {
            $files = self::stored_active_plugins();
            if (is_multisite()) {
                $files = array_merge($files, array_keys((array) get_site_option('active_sitewide_plugins', array())));
            }
            $active = array();
            foreach ($files as $file) {
                $slug = dirname((string) $file);
                if ('.' !== $slug && self::plugin_installed($file)) {
                    $active[$slug] = (string) $file;
                }
            }
        }
        return $active;
    }

    /**
     * Plugin files active on this site (not network-wide), as stored: a
     * plugin skipped on this request still counts.
     *
     * @return string[]
     */
    public static function stored_active_plugins() {
        $files = get_option('active_plugins', array());
        $files = is_array($files) ? array_values(array_filter($files, 'is_string')) : array();
        /**
         * Filter the active plugin files as stored, for code that skips
         * plugins on some requests (WP Plugin Starter's "Load plugins only
         * where needed" filters the option itself).
         *
         * @param string[] $files Plugin files, such as "akismet/akismet.php".
         */
        $files = apply_filters('wpstarter_stored_active_plugins', $files);
        return is_array($files) ? array_values(array_filter($files, 'is_string')) : array();
    }

    /**
     * Whether some active plugins are skipped on this request, so things
     * they register (post types, widgets) may be missing.
     *
     * @return bool
     */
    public static function plugins_skipped() {
        /**
         * Filter whether some active plugins are skipped on this request.
         *
         * @param bool $skipped Whether they are.
         */
        return (bool) apply_filters('wpstarter_plugins_skipped', false);
    }

    /**
     * Import settings once, when the stored settings version is older than
     * WPStarter_Settings::DB_VERSION. Only fill keys that are not stored yet.
     *
     * @param array $options      Stored settings (raw, without defaults).
     * @param int   $from_version Stored settings version before this upgrade.
     * @return array
     */
    public static function migrate(array $options, $from_version) {
        return $options;
    }

    /**
     * Set a setting during migrate() unless it is already stored.
     * (Named import_setting() so features may keep their own import() methods.)
     *
     * @param array  $options Stored settings.
     * @param string $key     Setting key.
     * @param mixed  $value   Raw value; null skips.
     * @return array
     */
    protected static function import_setting(array $options, $key, $value) {
        $schema = WPStarter_Settings::schema();
        if (null !== $value && !array_key_exists($key, $options) && isset($schema[$key])) {
            $options[$key] = WPStarter_Settings::sanitize_value($value, $schema[$key]);
        }
        return $options;
    }

    /**
     * Role options for multi settings.
     *
     * @return array<string,string>
     */
    public static function role_options() {
        $roles = array();
        foreach (wp_roles()->get_names() as $role => $name) {
            $roles[$role] = translate_user_role($name);
        }
        return $roles;
    }

    /**
     * Role options for settings that restrict people, without roles that can
     * manage options (such as Administrator): current_user_in_roles() never
     * matches them, so offering them would only mislead.
     *
     * @return array<string,string>
     */
    public static function restrictable_role_options() {
        $roles = array();
        foreach (wp_roles()->roles as $role => $data) {
            if (empty($data['capabilities']['manage_options'])) {
                $roles[$role] = translate_user_role($data['name']);
            }
        }
        return $roles;
    }

    /**
     * Whether the current user has one of the roles. Users who can manage
     * options are never matched, so admins cannot lock themselves out.
     *
     * @param mixed $roles Role slugs.
     * @return bool
     */
    public static function current_user_in_roles($roles) {
        $user = wp_get_current_user();
        if (!$user->exists() || user_can($user, 'manage_options')) {
            return false;
        }
        return (bool) array_intersect((array) $user->roles, (array) $roles);
    }

    /**
     * Whether a batch that began at $start has time for one more item.
     *
     * The batch keeps to its own budget, and also to PHP's time limit for
     * the whole request: WP-Cron runs every due batch in one request, so two
     * 20-second batches would pass a 30-second limit. Where the host allows
     * it, the limit is restarted for the next item instead.
     *
     * @param float $start  microtime(true) when the batch began.
     * @param int   $budget Seconds the batch may run.
     * @return bool
     *
     * Hosts may disable set_time_limit(); its warning is not an error here.
     * @SuppressWarnings("PHPMD.ErrorControlOperator")
     */
    public static function more_time($start, $budget) {
        $now = microtime(true);
        if ($now - $start >= $budget) {
            return false;
        }
        $limit = (int) ini_get('max_execution_time');
        if ($limit <= 0) {
            return true;
        }
        // set_time_limit() restarts the count; hosts may disable it.
        if (function_exists('set_time_limit') && @set_time_limit(max($limit, 60))) { // phpcs:ignore WordPress.PHP.NoSilencedErrors, Squiz.PHP.DiscouragedFunctions -- may be disabled by the host.
            return true;
        }
        $begun = isset($_SERVER['REQUEST_TIME_FLOAT']) ? (float) $_SERVER['REQUEST_TIME_FLOAT'] : $start;
        $used  = $now - $begun;
        // On Linux the limit counts CPU time of every thread, and image
        // libraries use several, so CPU time can run ahead of the clock.
        // getrusage() counts the whole process, which under PHP-FPM serves
        // many requests (thousands of seconds on a test site), so only CPU
        // time since the first call in this request counts, plus the clock
        // time before it.
        $cpu = self::cpu_seconds();
        if (null !== $cpu) {
            if (null === self::$cpu_base) {
                self::$cpu_base = array($cpu, $now - $begun);
            }
            $used = max($used, $cpu - self::$cpu_base[0] + self::$cpu_base[1]);
        }
        return $used < $limit - min(10, $limit / 3);
    }

    /** CPU seconds and request seconds at the first more_time() check. @var array|null */
    private static $cpu_base = null;

    /**
     * CPU seconds this process has used, or null when unknown.
     *
     * @return float|null
     */
    private static function cpu_seconds() {
        if (!function_exists('getrusage')) {
            return null;
        }
        $usage = getrusage();
        if (!is_array($usage) || !isset($usage['ru_utime.tv_sec'], $usage['ru_stime.tv_sec'], $usage['ru_utime.tv_usec'], $usage['ru_stime.tv_usec'])) {
            return null;
        }
        return $usage['ru_utime.tv_sec'] + $usage['ru_stime.tv_sec'] + ($usage['ru_utime.tv_usec'] + $usage['ru_stime.tv_usec']) / 1e6;
    }

    /**
     * Register hooks.
     */
    abstract public static function boot();
}
