<?php
/**
 * Shared GitHub updater: updates from GitHub releases for every installed
 * plugin that names its GitHub repository.
 *
 * Loaded by load.php, which picks the newest copy on the site; see there.
 * Only in builds made from GitHub releases: the WordPress.org build leaves
 * this folder out.
 *
 * - A plugin takes part by naming its repository in its main file's header:
 *   `GitHub Plugin URI: owner/repo` (the header Git Updater reads, so the
 *   two stay compatible). `Release Asset: true` means "install only the zip
 *   attached to the release, never the source code".
 * - WordPress does the rest itself: this only tells it that a newer release
 *   exists and where its zip is. The Updates screen, auto-updates, "View
 *   details", the download, the install and the rollback on failure are
 *   WordPress's own. Nothing is removed from or blocked in its update check.
 * - The latest release of each repository is asked for at most every 12
 *   hours (an hour after a failure), when WordPress checks for updates, and
 *   again when someone presses "Check again" on the Updates screen.
 * - Public repositories are read from github.com's own pages (the
 *   releases/latest redirect, the asset's download address and the main
 *   file on raw.githubusercontent.com), not the API: without a token the API
 *   allows 60 requests an hour per server address, shared by every site on
 *   a host. The asset must be named {folder}-{version}.zip.
 * - Private repositories need a GitHub token in wp-config.php
 *   (WPALLSTARS_GITHUB_TOKEN) or from the `wpallstars_github_token` filter,
 *   and are read through the API. The token is sent only to api.github.com,
 *   never stored and never shown.
 * - Plugins also on WordPress.org keep updating from there unless the
 *   `wpallstars_github_updater_early` filter returns true.
 * - While Git Updater is active, this waits and Git Updater does the job.
 *   The `wpallstars_github_updater_enabled` filter can turn it off too.
 *
 * @package WPStarter
 */

if (!defined('ABSPATH')) {
    exit;
}

final class WPAllStars_GitHub_Updater {

    /** Site transient: latest release of each repository, keyed by owner/repo. */
    const CACHE = 'wpallstars_github_releases';

    /** How long a release answer and a failed request are kept. */
    const FRESH  = 12 * HOUR_IN_SECONDS;
    const RETRY  = HOUR_IN_SECONDS;
    const RECENT = MINUTE_IN_SECONDS;

    /** Update IDs this file adds, so its own entries can be told apart. */
    const ID_PREFIX = 'github.com/';

    /**
     * Release answers read this request.
     *
     * @var array|null
     */
    private static $cache = null;

    /**
     * Register hooks (plugins_loaded). Whether to run is decided on init,
     * once plugins have added their filters.
     */
    public static function load() {
        add_action('init', array(__CLASS__, 'boot'), 20);
    }

    /**
     * Register the update hooks, unless switched off or Git Updater is active.
     */
    public static function boot() {
        /**
         * Whether to add GitHub releases to WordPress's update check.
         *
         * @param bool $enabled False while Git Updater is active.
         */
        if (!apply_filters('wpallstars_github_updater_enabled', !self::git_updater_active())) {
            return;
        }
        // Update checks run in the admin, in cron and in WP-CLI.
        add_filter('pre_set_site_transient_update_plugins', array(__CLASS__, 'add_updates'));
        add_filter('plugins_api', array(__CLASS__, 'plugin_information'), 20, 3);
        add_filter('upgrader_package_options', array(__CLASS__, 'private_package'));
        add_filter('upgrader_pre_download', array(__CLASS__, 'private_download'), 10, 3);
        add_filter('upgrader_source_selection', array(__CLASS__, 'fix_folder'), 10, 4);
    }

    /**
     * Whether Git Updater is active on this site or network-wide.
     *
     * @return bool
     */
    private static function git_updater_active() {
        $files = (array) get_option('active_plugins', array());
        if (is_multisite()) {
            $files = array_merge($files, array_keys((array) get_site_option('active_sitewide_plugins', array())));
        }
        foreach ($files as $file) {
            if ('git-updater' === dirname((string) $file)) {
                return true;
            }
        }
        return false;
    }

    /**
     * Installed plugins that name a GitHub repository.
     *
     * @return array<string,array{repo:string,asset_only:bool,version:string,name:string}> Plugin file => details.
     */
    public static function plugins() {
        static $found = null;
        if (null !== $found) {
            return $found;
        }
        if (!function_exists('get_plugins')) {
            require_once ABSPATH . 'wp-admin/includes/plugin.php';
        }

        $found = array();
        foreach (get_plugins() as $file => $data) {
            // Plugins in a folder only: an update replaces the whole folder.
            if ('.' === dirname($file)) {
                continue;
            }
            $headers = get_file_data(WP_PLUGIN_DIR . '/' . $file, array(
                'repo'  => 'GitHub Plugin URI',
                'asset' => 'Release Asset',
            ));
            $repo = self::repo_name($headers['repo']);
            if ('' === $repo) {
                continue;
            }
            $found[$file] = array(
                'repo'       => $repo,
                'asset_only' => in_array(strtolower(trim($headers['asset'])), array('true', 'yes', '1'), true),
                'version'    => isset($data['Version']) ? (string) $data['Version'] : '',
                'name'       => isset($data['Name']) ? (string) $data['Name'] : $file,
            );
        }

        /**
         * Filter the plugins updated from GitHub releases.
         *
         * @param array $found Plugin file => array(repo, asset_only, version, name).
         */
        $filtered = (array) apply_filters('wpallstars_github_plugins', $found);
        $found    = array();
        foreach ($filtered as $file => $plugin) {
            $repo = is_array($plugin) && isset($plugin['repo']) ? self::repo_name($plugin['repo']) : '';
            if ('' === $repo || '.' === dirname((string) $file)) {
                continue;
            }
            $found[(string) $file] = array(
                'repo'       => $repo,
                'asset_only' => !empty($plugin['asset_only']),
                'version'    => isset($plugin['version']) ? (string) $plugin['version'] : '',
                'name'       => isset($plugin['name']) ? (string) $plugin['name'] : (string) $file,
            );
        }
        return $found;
    }

    /**
     * owner/repo from a header value ("owner/repo" or a github.com address).
     *
     * @param mixed $value Header value.
     * @return string owner/repo, or '' when it is not one.
     */
    public static function repo_name($value) {
        $value = trim((string) $value);
        $value = preg_replace('#^(?:https?://)?(?:www\.)?github\.com/#i', '', $value);
        $value = preg_replace('#(?:\.git)?/*$#', '', (string) $value);
        return preg_match('#^[A-Za-z0-9](?:[A-Za-z0-9-]{0,38})/[A-Za-z0-9._-]{1,100}$#', (string) $value) ? (string) $value : '';
    }

    /**
     * Token for a repository, if the site has one.
     *
     * @param string $repo owner/repo.
     * @return string
     */
    private static function token($repo) {
        $token = defined('WPALLSTARS_GITHUB_TOKEN') ? (string) WPALLSTARS_GITHUB_TOKEN : '';
        /**
         * Filter the GitHub token used for a repository (private repositories
         * need one with read access to its contents). Return '' for none.
         *
         * @param string $token Token.
         * @param string $repo  owner/repo.
         */
        return trim((string) apply_filters('wpallstars_github_token', $token, $repo));
    }

    /**
     * GET from the GitHub API.
     *
     * @param string $repo   owner/repo (for the token).
     * @param string $path   Path after /repos/{repo}.
     * @param string $accept Accept header.
     * @return array|WP_Error
     */
    private static function api_get($repo, $path, $accept = 'application/vnd.github+json') {
        $headers = array(
            'Accept'               => $accept,
            'X-GitHub-Api-Version' => '2022-11-28',
        );
        $token = self::token($repo);
        if ('' !== $token) {
            $headers['Authorization'] = 'Bearer ' . $token;
        }
        // No redirects: the token must never travel to another address.
        return wp_safe_remote_get('https://api.github.com/repos/' . $repo . $path, array(
            'timeout'     => 10,
            'redirection' => 0,
            'headers'     => $headers,
        ));
    }

    /**
     * Stored release answers.
     *
     * @return array
     */
    private static function cache() {
        if (null === self::$cache) {
            $stored      = get_site_transient(self::CACHE);
            self::$cache = is_array($stored) ? $stored : array();
        }
        return self::$cache;
    }

    /**
     * Whether someone pressed "Check again" on the Updates screen.
     *
     * @return bool
     */
    private static function forced() {
        global $pagenow;
        // phpcs:ignore WordPress.Security.NonceVerification.Recommended -- core's own link; it only refreshes data.
        return is_admin() && 'update-core.php' === $pagenow && !empty($_GET['force-check']) && current_user_can('update_plugins');
    }

    /**
     * Latest release of a repository, from the cache or GitHub.
     *
     * @param string $repo    owner/repo.
     * @param string $folder  Plugin folder (picks the release asset).
     * @param string $main    Main file name in the folder (reads its requirements).
     * @return array|null Release, or null when there is none or GitHub did not answer.
     */
    public static function release($repo, $folder, $main) {
        $cache = self::cache();
        // The asset and requirements depend on the plugin, not only the repository.
        $key   = $repo . '|' . $folder . '/' . $main;
        $entry = isset($cache[$key]) && is_array($cache[$key]) ? $cache[$key] : null;
        $age   = $entry && isset($entry['checked']) ? time() - (int) $entry['checked'] : PHP_INT_MAX;
        $keep  = $entry && !empty($entry['failed']) ? self::RETRY : self::FRESH;

        if ($entry && $age < $keep && !(self::forced() && $age > self::RECENT)) {
            return isset($entry['release']) ? $entry['release'] : null;
        }

        $release = self::fetch($repo, $folder, $main);
        if (is_wp_error($release)) {
            // Keep the last good answer, and try again in an hour.
            $entry = array(
                'checked' => time(),
                'failed'  => $release->get_error_message(),
                'release' => $entry && isset($entry['release']) ? $entry['release'] : null,
            );
        } else {
            $entry = array('checked' => time(), 'release' => $release);
        }

        self::$cache[$key] = $entry;
        set_site_transient(self::CACHE, self::$cache, 2 * DAY_IN_SECONDS);
        return $entry['release'];
    }

    /**
     * Ask GitHub for a repository's latest release.
     *
     * @param string $repo   owner/repo.
     * @param string $folder Plugin folder.
     * @param string $main   Main file name.
     * @return array|null|WP_Error Release, null when there is no usable one, or the error.
     */
    private static function fetch($repo, $folder, $main) {
        return '' !== self::token($repo) ? self::fetch_api($repo, $folder, $main) : self::fetch_web($repo, $folder, $main);
    }

    /**
     * An error for a GitHub answer that was not the expected one.
     *
     * @param int $code HTTP status code.
     * @return WP_Error
     */
    private static function status_error($code) {
        /* translators: %d: HTTP status code */
        return new WP_Error('wpallstars_github', sprintf(__('GitHub answered with status %d.', 'wp-plugin-starter-template'), $code));
    }

    /**
     * Latest release from github.com's own pages, for public repositories.
     * The GitHub API allows 60 requests an hour per server address without
     * a token, which hosts share between many sites; these pages do not
     * count towards it.
     *
     * @param string $repo   owner/repo.
     * @param string $folder Plugin folder.
     * @param string $main   Main file name.
     * @return array|null|WP_Error
     */
    private static function fetch_web($repo, $folder, $main) {
        // Redirects to the newest release that is not a draft or pre-release.
        $response = wp_safe_remote_head('https://github.com/' . $repo . '/releases/latest', array(
            'timeout'     => 10,
            'redirection' => 0,
        ));
        if (is_wp_error($response)) {
            return $response;
        }
        $code     = (int) wp_remote_retrieve_response_code($response);
        $location = (string) wp_remote_retrieve_header($response, 'location');
        if (404 === $code) {
            // No such public repository (private ones need a token).
            return null;
        }
        if ($code < 300 || $code > 399) {
            return self::status_error($code);
        }
        if (!preg_match('#^https://github\.com/' . preg_quote($repo, '#') . '/releases/tag/([^/?\#]+)$#i', $location, $match)) {
            // No releases yet: GitHub sends the releases list instead.
            return null;
        }

        $tag     = rawurldecode($match[1]);
        $version = preg_replace('/^v/i', '', $tag);
        if (!preg_match('/^[0-9]+(\.[0-9]+)*$/', $version)) {
            return null;
        }

        // The release zip, by its usual name: {folder}-{version}.zip.
        $asset    = null;
        $download = 'https://github.com/' . $repo . '/releases/download/' . rawurlencode($tag) . '/' . rawurlencode($folder . '-' . $version . '.zip');
        $head     = wp_safe_remote_head($download, array('timeout' => 10, 'redirection' => 0));
        if (is_wp_error($head)) {
            return $head;
        }
        $code = (int) wp_remote_retrieve_response_code($head);
        if ($code >= 300 && $code < 400) {
            $asset = array('public' => $download, 'api' => '');
        } elseif (404 !== $code) {
            return self::status_error($code);
        }

        $release = array(
            'tag'       => $tag,
            'version'   => $version,
            'url'       => $location,
            'published' => '',
            'notes'     => '',
            'asset'     => $asset,
            'zipball'   => 'https://github.com/' . $repo . '/archive/refs/tags/' . rawurlencode($tag) . '.zip',
        );
        $file = wp_safe_remote_get('https://raw.githubusercontent.com/' . $repo . '/' . rawurlencode($tag) . '/' . rawurlencode($main), array(
            'timeout' => 10,
            'headers' => array('Range' => 'bytes=0-8191'),
        ));
        $body = !is_wp_error($file) && in_array((int) wp_remote_retrieve_response_code($file), array(200, 206), true) ? (string) wp_remote_retrieve_body($file) : '';
        return $release + self::requirements($body);
    }

    /**
     * Latest release from the GitHub API, with a token (private repositories).
     *
     * @param string $repo   owner/repo.
     * @param string $folder Plugin folder.
     * @param string $main   Main file name.
     * @return array|null|WP_Error
     */
    private static function fetch_api($repo, $folder, $main) {
        // The newest release that is not a draft or pre-release.
        $response = self::api_get($repo, '/releases/latest');
        if (is_wp_error($response)) {
            return $response;
        }
        $code = (int) wp_remote_retrieve_response_code($response);
        if (404 === $code) {
            // No releases yet, or a private repository without a token.
            return null;
        }
        if (200 !== $code) {
            return self::status_error($code);
        }

        $data    = json_decode(wp_remote_retrieve_body($response), true);
        $tag     = is_array($data) && isset($data['tag_name']) ? (string) $data['tag_name'] : '';
        $version = preg_replace('/^v/i', '', $tag);
        // Numbers only: anything else is not a finished version.
        if (!preg_match('/^[0-9]+(\.[0-9]+)*$/', $version)) {
            return null;
        }

        $release = array(
            'tag'       => $tag,
            'version'   => $version,
            'url'       => isset($data['html_url']) ? (string) $data['html_url'] : 'https://github.com/' . $repo . '/releases',
            'published' => isset($data['published_at']) ? (string) $data['published_at'] : '',
            'notes'     => isset($data['body']) ? substr((string) $data['body'], 0, 20000) : '',
            'asset'     => self::pick_asset($repo, $folder, isset($data['assets']) && is_array($data['assets']) ? $data['assets'] : array()),
            'zipball'   => 'https://api.github.com/repos/' . $repo . '/zipball/' . rawurlencode($tag),
        );
        $file = self::api_get($repo, '/contents/' . rawurlencode($main) . '?ref=' . rawurlencode($tag), 'application/vnd.github.raw+json');
        $body = !is_wp_error($file) && 200 === (int) wp_remote_retrieve_response_code($file) ? (string) wp_remote_retrieve_body($file) : '';
        return $release + self::requirements($body);
    }

    /**
     * The release zip for a plugin folder: a .zip asset whose name starts
     * with the folder name (never the "wordpress-org-…" build).
     *
     * @param string $repo   owner/repo.
     * @param string $folder Plugin folder.
     * @param array  $assets Release assets.
     * @return array{public:string,api:string}|null Download addresses.
     */
    private static function pick_asset($repo, $folder, array $assets) {
        foreach ($assets as $asset) {
            $name = isset($asset['name']) ? (string) $asset['name'] : '';
            if (0 !== stripos($name, $folder) || '.zip' !== strtolower(substr($name, -4))) {
                continue;
            }
            $public = isset($asset['browser_download_url']) ? (string) $asset['browser_download_url'] : '';
            $api    = isset($asset['id']) ? 'https://api.github.com/repos/' . $repo . '/releases/assets/' . (int) $asset['id'] : '';
            if (0 === strpos($public, 'https://github.com/' . $repo . '/releases/download/')) {
                return array('public' => $public, 'api' => $api);
            }
        }
        return null;
    }

    /**
     * "Requires at least" and "Requires PHP" of the released main file, so
     * WordPress does not offer an update the site cannot run.
     *
     * @param string $file Start of the released main file ('' when unknown).
     * @return array{requires:string,requires_php:string}
     */
    private static function requirements($file) {
        $found = array('requires' => '', 'requires_php' => '');
        $head  = substr((string) $file, 0, 8192);
        foreach (array('requires' => 'Requires at least', 'requires_php' => 'Requires PHP') as $key => $header) {
            if (preg_match('/^(?:[ \t]*<\?php)?[ \t\/*#@]*' . preg_quote($header, '/') . ':(.*)$/mi', $head, $match)) {
                $value = trim(preg_replace('/\s*(?:\*\/|\?>).*/', '', $match[1]));
                if (preg_match('/^[0-9]+(\.[0-9]+)*$/', $value)) {
                    $found[$key] = $value;
                }
            }
        }
        return $found;
    }

    /**
     * Download address WordPress installs from.
     *
     * @param string $repo       owner/repo.
     * @param array  $release    Release.
     * @param bool   $asset_only Install the release asset only.
     * @return string '' when the release has nothing to install.
     */
    private static function package($repo, array $release, $asset_only) {
        $private = '' !== self::token($repo);
        if (!empty($release['asset'])) {
            // Assets of private repositories download through the API (see private_package()).
            return $private && $release['asset']['api'] ? $release['asset']['api'] : $release['asset']['public'];
        }
        return $asset_only ? '' : (string) $release['zipball'];
    }

    /**
     * Whether WordPress.org offers updates for a plugin.
     *
     * @param object $transient update_plugins.
     * @param string $file      Plugin file.
     * @return bool
     */
    private static function on_wordpress_org($transient, $file) {
        foreach (array('response', 'no_update') as $list) {
            if (isset($transient->{$list}[$file])) {
                $item = (object) $transient->{$list}[$file];
                $id   = isset($item->id) ? (string) $item->id : '';
                if (0 !== strpos($id, self::ID_PREFIX)) {
                    return true;
                }
            }
        }
        return false;
    }

    /**
     * Tell WordPress about GitHub releases when it saves its update check.
     *
     * @param mixed $transient update_plugins.
     * @return mixed
     */
    public static function add_updates($transient) {
        if (!is_object($transient)) {
            return $transient;
        }
        /**
         * Whether plugins also on WordPress.org take each version from GitHub
         * as soon as it is released, instead of waiting for WordPress.org.
         *
         * @param bool $early Default false.
         */
        $early = (bool) apply_filters('wpallstars_github_updater_early', false);

        foreach (self::plugins() as $file => $plugin) {
            if (!$early && self::on_wordpress_org($transient, $file)) {
                continue;
            }
            $folder  = dirname($file);
            $release = self::release($plugin['repo'], $folder, basename($file));
            $current = isset($transient->checked[$file]) ? (string) $transient->checked[$file] : $plugin['version'];
            if (!$release) {
                // Keep WordPress.org's answer, or say nothing.
                continue;
            }
            $dot_org = isset($transient->response[$file]->new_version) ? (string) $transient->response[$file]->new_version : '';
            if ('' !== $dot_org && 0 !== strpos((string) ($transient->response[$file]->id ?? ''), self::ID_PREFIX) && version_compare($dot_org, $release['version'], '>=')) {
                // WordPress.org already offers this version or a newer one.
                continue;
            }

            $item = (object) array(
                'id'            => self::ID_PREFIX . $plugin['repo'],
                'slug'          => $folder,
                'plugin'        => $file,
                'new_version'   => $release['version'],
                'url'           => 'https://github.com/' . $plugin['repo'],
                'package'       => self::package($plugin['repo'], $release, $plugin['asset_only']),
                'requires'      => $release['requires'],
                'requires_php'  => $release['requires_php'],
                'tested'        => '',
                'icons'         => array(),
                'banners'       => array(),
                'banners_rtl'   => array(),
                'compatibility' => new stdClass(),
            );

            if (!is_array($transient->response ?? null)) {
                $transient->response = array();
            }
            if (!is_array($transient->no_update ?? null)) {
                $transient->no_update = array();
            }
            if ('' === $item->package && self::on_wordpress_org($transient, $file)) {
                // Nothing to install from GitHub: keep WordPress.org's answer.
                continue;
            }
            unset($transient->response[$file], $transient->no_update[$file]);
            if ('' !== $item->package && version_compare($release['version'], $current, '>')) {
                $transient->response[$file] = $item;
            } else {
                // Listed as up to date, so the Plugins screen offers auto-updates.
                $transient->no_update[$file] = $item;
            }
        }
        return $transient;
    }

    /**
     * The plugin a "View details" request is about, if it is ours to answer.
     *
     * @param string $slug Plugin folder.
     * @return string Plugin file, or ''.
     */
    private static function file_for_slug($slug) {
        $updates = get_site_transient('update_plugins');
        foreach (self::plugins() as $file => $plugin) {
            if (dirname($file) !== $slug) {
                continue;
            }
            foreach (array('response', 'no_update') as $list) {
                if (is_object($updates) && isset($updates->{$list}[$file]->id) && 0 === strpos((string) $updates->{$list}[$file]->id, self::ID_PREFIX)) {
                    return $file;
                }
            }
        }
        return '';
    }

    /**
     * "View details" for plugins updated from GitHub.
     *
     * @param false|object|array $result Result so far.
     * @param string             $action plugins_api action.
     * @param object             $args   Request arguments.
     * @return false|object|array
     */
    public static function plugin_information($result, $action, $args) {
        if ('plugin_information' !== $action || !is_object($args) || empty($args->slug)) {
            return $result;
        }
        $file = self::file_for_slug((string) $args->slug);
        if ('' === $file) {
            return $result;
        }
        $plugins = self::plugins();
        $plugin  = $plugins[$file];
        $release = self::release($plugin['repo'], dirname($file), basename($file));
        $data    = get_plugin_data(WP_PLUGIN_DIR . '/' . $file, false, true);

        $sections = array(
            'description' => wpautop(esc_html(isset($data['Description']) ? wp_strip_all_tags($data['Description']) : '')),
        );
        if ($release) {
            $sections['changelog'] = '<h4>' . esc_html($release['version']) . '</h4>'
                . ('' !== trim($release['notes']) ? self::notes_html($release['notes']) : '')
                . sprintf('<p><a href="%1$s" target="_blank" rel="noopener noreferrer">%2$s</a></p>', esc_url($release['url']), esc_html__('Release notes on GitHub', 'wp-plugin-starter-template'));
        }

        return (object) array(
            'name'          => $plugin['name'],
            'slug'          => dirname($file),
            'version'       => $release ? $release['version'] : $plugin['version'],
            'author'        => isset($data['Author']) ? $data['Author'] : '',
            'homepage'      => 'https://github.com/' . $plugin['repo'],
            'requires'      => $release ? $release['requires'] : '',
            'requires_php'  => $release ? $release['requires_php'] : '',
            'last_updated'  => $release ? $release['published'] : '',
            'download_link' => $release ? self::package($plugin['repo'], $release, $plugin['asset_only']) : '',
            'sections'      => $sections,
            'banners'       => array(),
            'external'      => true,
        );
    }

    /**
     * Release notes (Markdown) as simple HTML: headings, lists, paragraphs,
     * bold and code. Everything is escaped first.
     *
     * @param string $markdown Release notes.
     * @return string
     */
    private static function notes_html($markdown) {
        $html = '';
        $list = false;
        foreach (preg_split('/\r\n|\r|\n/', (string) $markdown) as $line) {
            $line = rtrim($line);
            $text = esc_html(ltrim(preg_replace('/^(#{1,6}|[-*+])\s+/', '', trim($line))));
            $text = preg_replace('/\*\*(.+?)\*\*/', '<strong>$1</strong>', $text);
            $text = preg_replace('/`([^`]+)`/', '<code>$1</code>', $text);
            $item = (bool) preg_match('/^\s*[-*+]\s+/', $line);
            if ($list && !$item) {
                $html .= '</ul>';
                $list  = false;
            }
            if ('' === trim($line)) {
                continue;
            }
            if ($item) {
                if (!$list) {
                    $html .= '<ul>';
                    $list  = true;
                }
                $html .= '<li>' . $text . '</li>';
            } elseif (preg_match('/^#{1,6}\s/', $line)) {
                $html .= '<h4>' . $text . '</h4>';
            } else {
                $html .= '<p>' . $text . '</p>';
            }
        }
        return $html . ($list ? '</ul>' : '');
    }

    /**
     * Downloads from private repositories: before WordPress downloads, swap
     * the API address for the signed, short-lived address GitHub sends the
     * token holder to, so WordPress downloads it itself without the token.
     *
     * This runs before upgrader_pre_download on purpose: some plugins' own
     * updaters return false there for every package (GPLVault Updater does,
     * at priority 999999999), which throws away a file already downloaded
     * and leaves WordPress fetching the API address without the token
     * (GitHub answers 404).
     *
     * @param array $options Upgrader options; 'package' is the address.
     * @return array
     */
    public static function private_package($options) {
        if (!is_array($options) || !isset($options['package'])) {
            return $options;
        }
        $address = self::signed_address($options['package']);
        if (is_string($address)) {
            $options['package'] = $address;
        }
        return $options;
    }

    /**
     * Fallback for downloads that skip upgrader_package_options: ask the API
     * with the token, then fetch the file from where GitHub sends us without
     * it.
     *
     * @param mixed       $reply    False to let WordPress download.
     * @param string      $package  Download address.
     * @param WP_Upgrader $upgrader Upgrader.
     * @return mixed File path, WP_Error or $reply.
     */
    public static function private_download($reply, $package, $upgrader) {
        if (false !== $reply) {
            return $reply;
        }
        $address = self::signed_address($package);
        if (null === $address) {
            return $reply;
        }
        return is_wp_error($address) ? $address : download_url($address, 300);
    }

    /**
     * The signed, short-lived download address of a private repository's
     * release asset or source zip, asked for with the token. No token is
     * needed (or wanted) there.
     *
     * @param mixed $package Download address.
     * @return string|WP_Error|null Address; error; null when the address is
     *                              not one of ours or there is no token.
     */
    private static function signed_address($package) {
        if (!is_string($package) || !preg_match('#^https://api\.github\.com/repos/([^/]+/[^/]+)/(?:releases/assets/[0-9]+|zipball/[^/?]+)$#', $package, $match)) {
            return null;
        }
        $repo  = $match[1];
        $known = false;
        foreach (self::plugins() as $plugin) {
            $known = $known || $plugin['repo'] === $repo;
        }
        $token = self::token($repo);
        if (!$known || '' === $token) {
            return null;
        }

        $response = wp_safe_remote_get($package, array(
            'timeout'     => 30,
            'redirection' => 0,
            'headers'     => array(
                'Accept'        => false !== strpos($package, '/releases/assets/') ? 'application/octet-stream' : 'application/vnd.github+json',
                'Authorization' => 'Bearer ' . $token,
            ),
        ));
        if (is_wp_error($response)) {
            return $response;
        }
        $location = (string) wp_remote_retrieve_header($response, 'location');
        if ('' === $location || !in_array((int) wp_remote_retrieve_response_code($response), array(301, 302, 303, 307, 308), true)) {
            return new WP_Error('wpallstars_github_download', __('GitHub did not give a download address. Check the token’s access to the repository.', 'wp-plugin-starter-template'));
        }
        return $location;
    }

    /**
     * Keep a plugin in its folder when the zip's top folder has another name
     * (GitHub's source zips are named owner-repo-commit).
     *
     * @param string|WP_Error $source        Unpacked folder.
     * @param string          $remote_source Folder it was unpacked in.
     * @param WP_Upgrader     $upgrader      Upgrader.
     * @param array           $hook_extra    Context.
     * @return string|WP_Error
     */
    public static function fix_folder($source, $remote_source, $upgrader, $hook_extra = array()) {
        global $wp_filesystem;
        if (is_wp_error($source) || empty($hook_extra['plugin']) || !$wp_filesystem) {
            return $source;
        }
        $file = (string) $hook_extra['plugin'];
        if (!isset(self::plugins()[$file])) {
            return $source;
        }
        $folder = dirname($file);
        if (basename(untrailingslashit($source)) === $folder) {
            return $source;
        }
        $target = trailingslashit($remote_source) . $folder . '/';
        $from   = untrailingslashit($source);
        if ($from === untrailingslashit($remote_source)) {
            // A zip without a top folder: move its files aside, then into the folder.
            $from = untrailingslashit($remote_source) . '-github-updater';
            if (!$wp_filesystem->move(untrailingslashit($remote_source), $from, true) || !$wp_filesystem->mkdir(untrailingslashit($remote_source), FS_CHMOD_DIR)) {
                return new WP_Error('wpallstars_github_folder', __('The update could not be unpacked into the plugin’s folder.', 'wp-plugin-starter-template'));
            }
        }
        if (!$wp_filesystem->move($from, untrailingslashit($target), true)) {
            return new WP_Error('wpallstars_github_folder', __('The update could not be unpacked into the plugin’s folder.', 'wp-plugin-starter-template'));
        }
        return $target;
    }
}
