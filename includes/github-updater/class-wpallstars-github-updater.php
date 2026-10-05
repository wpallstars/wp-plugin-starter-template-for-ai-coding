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
 *   a host. The asset must be named {folder}-{version}.zip, with or without
 *   a token.
 * - Private repositories need a GitHub token in wp-config.php
 *   (WPALLSTARS_GITHUB_TOKEN) or from the `wpallstars_github_token` filter,
 *   and are read through the API. With a token, every repository it is
 *   given for is read through the API, public ones too (the filter can
 *   return it for some repositories only). The token is sent only to
 *   api.github.com, never stored and never shown.
 * - The GitHub build's main file has an `Update URI` header on github.com
 *   (scripts/build-release.sh adds it; the WordPress.org build has none).
 *   WordPress.org then never offers its own plugin of the same slug for it,
 *   and this file never takes WordPress.org's answer for it.
 * - Other plugins also on WordPress.org (builds without that header) keep
 *   updating from there unless the `wpallstars_github_updater_early` filter
 *   returns true.
 * - While Git Updater is active, this waits and Git Updater does the job.
 *   The `wpallstars_github_updater_enabled` filter can turn it off too.
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 * SPDX-FileCopyrightText: 2026 Marcus Quinn
 * Additional terms (GPL-3.0 section 7(b)): ATTRIBUTION.txt
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

    /** GitHub addresses. */
    const GITHUB    = 'https://github.com/';
    const API_REPOS = 'https://api.github.com/repos/';

    /** A finished version: numbers and dots only. */
    const VERSION_PATTERN = '/^\d+(\.\d+)*$/';

    /** Hosts GitHub sends signed downloads from. */
    const DOWNLOAD_HOSTS = '/^(?:github\.com|codeload\.github\.com|[a-z0-9-]+\.githubusercontent\.com)$/';

    /**
     * Release answers read this request.
     *
     * @var array|null
     */
    private static $cache = null;

    /**
     * Signed download addresses (or errors) found this request, by package.
     *
     * @var array<string,string|WP_Error>
     */
    private static $signed = array();

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
     * 'github_only' is true for a build whose `Update URI` header points
     * anywhere but WordPress.org: WordPress.org's answers are never its own.
     *
     * @return array<string,array{repo:string,asset_only:bool,github_only:bool,version:string,name:string}> Plugin file => details.
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
            $plugin = self::from_headers($file, $data);
            if ($plugin) {
                $found[$file] = $plugin;
            }
        }

        /**
         * Filter the plugins updated from GitHub releases.
         *
         * @param array $found Plugin file => array(repo, asset_only, github_only, version, name).
         */
        $filtered = (array) apply_filters('wpallstars_github_plugins', $found);
        $found    = array();
        foreach ($filtered as $file => $plugin) {
            $plugin = self::clean_plugin((string) $file, $plugin);
            if ($plugin) {
                $found[(string) $file] = $plugin;
            }
        }
        return $found;
    }

    /**
     * A plugin's details from its headers, if it names a GitHub repository.
     *
     * @param string $file Plugin file.
     * @param array  $data get_plugins() data.
     * @return array|null
     */
    private static function from_headers($file, array $data) {
        // Plugins in a folder only: an update replaces the whole folder.
        if ('.' === dirname($file)) {
            return null;
        }
        $headers = get_file_data(WP_PLUGIN_DIR . '/' . $file, array(
            'repo'  => 'GitHub Plugin URI',
            'asset' => 'Release Asset',
        ));
        $update_host = isset($data['UpdateURI']) ? (string) wp_parse_url((string) $data['UpdateURI'], PHP_URL_HOST) : '';
        return self::clean_plugin($file, array(
            'repo'        => $headers['repo'],
            'asset_only'  => in_array(strtolower(trim($headers['asset'])), array('true', 'yes', '1'), true),
            'github_only' => '' !== $update_host && !in_array(strtolower($update_host), array('w.org', 'wordpress.org'), true),
            'version'     => isset($data['Version']) ? $data['Version'] : '',
            'name'        => isset($data['Name']) ? $data['Name'] : $file,
        ));
    }

    /**
     * One plugin's details in the expected shape, or null when it has no
     * usable repository or is not in a folder.
     *
     * @param string $file   Plugin file.
     * @param mixed  $plugin Details.
     * @return array{repo:string,asset_only:bool,github_only:bool,version:string,name:string}|null
     */
    private static function clean_plugin($file, $plugin) {
        $repo = is_array($plugin) && isset($plugin['repo']) ? self::repo_name($plugin['repo']) : '';
        if ('' === $repo || '.' === dirname($file)) {
            return null;
        }
        return array(
            'repo'        => $repo,
            'asset_only'  => !empty($plugin['asset_only']),
            'github_only' => !empty($plugin['github_only']),
            'version'     => isset($plugin['version']) ? (string) $plugin['version'] : '',
            'name'        => isset($plugin['name']) ? (string) $plugin['name'] : $file,
        );
    }

    /**
     * A response header as one string. With more than one header of that
     * name WordPress returns an array; the last one is the one that counts.
     *
     * @param array|WP_Error $response HTTP response.
     * @param string         $name     Header name.
     * @return string
     */
    private static function header_value($response, $name) {
        $value = wp_remote_retrieve_header($response, $name);
        if (is_array($value)) {
            $value = $value ? end($value) : '';
        }
        return (string) $value;
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
        return preg_match('#^[A-Za-z0-9][A-Za-z0-9-]{0,38}/[A-Za-z0-9._-]{1,100}$#', (string) $value) ? (string) $value : '';
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
        return self::remote_no_redirect('GET', self::API_REPOS . $repo . $path, array(
            'timeout' => 10,
            'headers' => $headers,
        ));
    }

    /**
     * A request that never follows a redirect, so the answer's Location can
     * be read and a token never travels to another address.
     *
     * Some plugins raise every request's redirection count (HTTP Requests
     * Manager sets it to 1), which would follow GitHub's redirect: the token
     * would go along and the Location would be lost. Only this request is
     * held at 0, after every other filter.
     *
     * @param string $method GET or HEAD.
     * @param string $url    Address.
     * @param array  $args   Request arguments.
     * @return array|WP_Error
     */
    private static function remote_no_redirect($method, $url, array $args) {
        $args['redirection'] = 0;
        $hold                = function ($parsed_args, $request_url) use ($url) {
            if ($request_url === $url && is_array($parsed_args)) {
                $parsed_args['redirection'] = 0;
            }
            return $parsed_args;
        };
        add_filter('http_request_args', $hold, PHP_INT_MAX, 2);
        $response = 'HEAD' === $method ? wp_safe_remote_head($url, $args) : wp_safe_remote_get($url, $args);
        remove_filter('http_request_args', $hold, PHP_INT_MAX);
        return $response;
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
        $entry = isset($cache[$key]) && is_array($cache[$key]) ? $cache[$key] : array();

        if (self::still_fresh($entry)) {
            return isset($entry['release']) ? $entry['release'] : null;
        }

        $release = self::fetch($repo, $folder, $main);
        if (is_wp_error($release)) {
            // Keep the last good answer, and try again in an hour.
            $entry = array(
                'checked' => time(),
                'failed'  => $release->get_error_message(),
                'release' => isset($entry['release']) ? $entry['release'] : null,
            );
        } else {
            $entry = array('checked' => time(), 'release' => $release);
        }

        self::$cache[$key] = $entry;
        set_site_transient(self::CACHE, self::$cache, 2 * DAY_IN_SECONDS);
        return $entry['release'];
    }

    /**
     * Whether a stored answer can still be used: younger than 12 hours (an
     * hour after a failure), and not older than a minute when someone
     * pressed "Check again".
     *
     * @param array $entry Stored answer.
     * @return bool
     */
    private static function still_fresh(array $entry) {
        if (!isset($entry['checked'])) {
            return false;
        }
        $age  = time() - (int) $entry['checked'];
        $keep = empty($entry['failed']) ? self::FRESH : self::RETRY;
        return $age < $keep && !(self::forced() && $age > self::RECENT);
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
        $response = self::remote_no_redirect('HEAD', self::GITHUB . $repo . '/releases/latest', array('timeout' => 10));
        if (is_wp_error($response)) {
            return $response;
        }
        $code     = (int) wp_remote_retrieve_response_code($response);
        $location = self::header_value($response, 'location');
        if (404 === $code) {
            // No such public repository (private ones need a token).
            return null;
        }
        if ($code < 300 || $code > 399) {
            return self::status_error($code);
        }
        if (preg_match('#^https://github\.com/([A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+)/#i', $location, $moved) && 0 !== strcasecmp($moved[1], $repo)) {
            // A renamed or moved repository: say where, so the plugin's
            // header can be changed (requests never follow redirects).
            /* translators: 1: owner/repo in the plugin's header, 2: owner/repo GitHub points to */
            return new WP_Error('wpallstars_github_moved', sprintf(__('GitHub repository %1$s has moved to %2$s; change the plugin\'s GitHub Plugin URI header.', 'wp-plugin-starter-template'), $repo, $moved[1]));
        }
        if (!preg_match('#^https://github\.com/' . preg_quote($repo, '#') . '/releases/tag/([^/?\#]+)$#i', $location, $match)) {
            // No releases yet: GitHub sends the releases list instead.
            return null;
        }

        $tag     = rawurldecode($match[1]);
        $version = preg_replace('/^v/i', '', $tag);
        if (!preg_match(self::VERSION_PATTERN, $version)) {
            return null;
        }

        // The release zip, by its name: {folder}-{version}.zip.
        $asset    = null;
        $download = self::GITHUB . $repo . '/releases/download/' . rawurlencode($tag) . '/' . rawurlencode(self::asset_name($folder, $version));
        $head     = self::remote_no_redirect('HEAD', $download, array('timeout' => 10));
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
            'zipball'   => self::GITHUB . $repo . '/archive/refs/tags/' . rawurlencode($tag) . '.zip',
        );
        $file = wp_safe_remote_get('https://raw.githubusercontent.com/' . $repo . '/' . rawurlencode($tag) . '/' . rawurlencode($main), array(
            'timeout' => 10,
            'headers' => array('Range' => 'bytes=0-8191'),
        ));
        return self::with_requirements($release, $file, array(200, 206));
    }

    /**
     * A release with the requirements of its main file. When GitHub did not
     * answer, the whole check fails (and is tried again in an hour), so no
     * release is offered without its requirements; only a release without
     * that file (404) goes on without them.
     *
     * @param array          $release  Release.
     * @param array|WP_Error $response Answer for the released main file.
     * @param int[]          $ok       Status codes that carry the file.
     * @return array|WP_Error
     */
    private static function with_requirements(array $release, $response, array $ok) {
        if (is_wp_error($response)) {
            return $response;
        }
        $code = (int) wp_remote_retrieve_response_code($response);
        if (404 === $code) {
            return $release + self::requirements('');
        }
        if (!in_array($code, $ok, true)) {
            return self::status_error($code);
        }
        return $release + self::requirements((string) wp_remote_retrieve_body($response));
    }

    /**
     * The release zip's name for a plugin folder.
     *
     * @param string $folder  Plugin folder.
     * @param string $version Version.
     * @return string
     */
    private static function asset_name($folder, $version) {
        return $folder . '-' . $version . '.zip';
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
        if (!preg_match(self::VERSION_PATTERN, $version)) {
            return null;
        }

        $release = array(
            'tag'       => $tag,
            'version'   => $version,
            'url'       => isset($data['html_url']) ? (string) $data['html_url'] : self::GITHUB . $repo . '/releases',
            'published' => isset($data['published_at']) ? (string) $data['published_at'] : '',
            'notes'     => isset($data['body']) ? substr((string) $data['body'], 0, 20000) : '',
            'asset'     => self::pick_asset($repo, self::asset_name($folder, $version), isset($data['assets']) && is_array($data['assets']) ? $data['assets'] : array()),
            'zipball'   => self::API_REPOS . $repo . '/zipball/' . rawurlencode($tag),
        );
        $file = self::api_get($repo, '/contents/' . rawurlencode($main) . '?ref=' . rawurlencode($tag), 'application/vnd.github.raw+json');
        return self::with_requirements($release, $file, array(200));
    }

    /**
     * The release zip: the asset named exactly {folder}-{version}.zip, as
     * without a token (never another zip, such as the "wordpress-org-…" build).
     *
     * @param string $repo   owner/repo.
     * @param string $name   Asset name.
     * @param array  $assets Release assets.
     * @return array{public:string,api:string}|null Download addresses.
     */
    private static function pick_asset($repo, $name, array $assets) {
        foreach ($assets as $asset) {
            if (!isset($asset['name']) || (string) $asset['name'] !== $name) {
                continue;
            }
            $public = isset($asset['browser_download_url']) ? (string) $asset['browser_download_url'] : '';
            $api    = isset($asset['id']) ? self::API_REPOS . $repo . '/releases/assets/' . (int) $asset['id'] : '';
            // GitHub writes owner/repo in its own case, which the header may not.
            if (0 === stripos($public, self::GITHUB . $repo . '/releases/download/')) {
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
                if (preg_match(self::VERSION_PATTERN, $value)) {
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
     * Whether WordPress.org offers updates for a plugin. Never for a GitHub
     * build (its `Update URI` is on github.com): an entry there would be
     * another plugin with the same slug.
     *
     * @param object $transient update_plugins.
     * @param string $file      Plugin file.
     * @param array  $plugin    Plugin details (plugins()).
     * @return bool
     */
    private static function on_wordpress_org($transient, $file, array $plugin) {
        if (!empty($plugin['github_only'])) {
            return false;
        }
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
        /** @var \stdClass $transient Core saves update_plugins as a stdClass. */
        /**
         * Whether plugins also on WordPress.org take each version from GitHub
         * as soon as it is released, instead of waiting for WordPress.org.
         *
         * @param bool $early Default false.
         */
        $early = (bool) apply_filters('wpallstars_github_updater_early', false);

        foreach (self::plugins() as $file => $plugin) {
            if (!$early && self::on_wordpress_org($transient, $file, $plugin)) {
                continue;
            }
            $release = self::release($plugin['repo'], dirname($file), basename($file));
            if (!$release || self::dot_org_is_newer($transient, $file, $plugin, $release)) {
                // Keep WordPress.org's answer, or say nothing.
                continue;
            }
            self::list_update($transient, $file, $plugin, $release);
        }
        return $transient;
    }

    /**
     * Whether WordPress.org already offers this version or a newer one.
     *
     * @param object $transient update_plugins.
     * @param string $file      Plugin file.
     * @param array  $plugin    Plugin details.
     * @param array  $release   GitHub release.
     * @return bool
     */
    private static function dot_org_is_newer($transient, $file, array $plugin, array $release) {
        if (!empty($plugin['github_only']) || !isset($transient->response[$file]->new_version)) {
            return false;
        }
        $offer = $transient->response[$file];
        return 0 !== strpos((string) ($offer->id ?? ''), self::ID_PREFIX)
            && version_compare((string) $offer->new_version, $release['version'], '>=');
    }

    /**
     * Put a GitHub release in WordPress's update check: as an update when it
     * is newer and has something to install, otherwise as up to date.
     *
     * @param \stdClass $transient update_plugins (changed).
     * @param string    $file      Plugin file.
     * @param array     $plugin    Plugin details.
     * @param array     $release   GitHub release.
     */
    private static function list_update($transient, $file, array $plugin, array $release) {
        $item = (object) array(
            'id'            => self::ID_PREFIX . $plugin['repo'],
            'slug'          => dirname($file),
            'plugin'        => $file,
            'new_version'   => $release['version'],
            'url'           => self::GITHUB . $plugin['repo'],
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
        if ('' === $item->package && self::on_wordpress_org($transient, $file, $plugin)) {
            // Nothing to install from GitHub: keep WordPress.org's answer.
            return;
        }
        $current = isset($transient->checked[$file]) ? (string) $transient->checked[$file] : $plugin['version'];
        unset($transient->response[$file], $transient->no_update[$file]);
        if ('' !== $item->package && version_compare($release['version'], $current, '>')) {
            $transient->response[$file] = $item;
        } else {
            // Listed as up to date, so the Plugins screen offers auto-updates.
            $transient->no_update[$file] = $item;
        }
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
            'homepage'      => self::GITHUB . $plugin['repo'],
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
        foreach (preg_split('/\r\n|\r|\n/', (string) $markdown) ?: array() as $line) {
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
     * When GitHub gives no address, the API address stays and the error is
     * kept for private_download(), which returns it instead of asking again.
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
     * it. A failure already met this request is returned as it was.
     *
     * @param mixed       $reply    False to let WordPress download.
     * @param string      $package  Download address.
     * @param WP_Upgrader $upgrader Upgrader (unused; the filter passes it).
     * @return mixed File path, WP_Error or $reply.
     */
    public static function private_download($reply, $package, $upgrader) { // NOSONAR: WordPress passes $upgrader to this filter.
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
        if (!is_string($package) || !preg_match('#^https://api\.github\.com/repos/([^/]+/[^/]+)/(?:releases/assets/\d+|zipball/[^/?]+)$#', $package, $match)) {
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
        // Once per request: the fallback reuses the first answer, error included.
        if (!isset(self::$signed[$package])) {
            self::$signed[$package] = self::ask_signed_address($package, $token);
        }
        return self::$signed[$package];
    }

    /**
     * Ask the API, with the token, where GitHub serves a download. Only an
     * https address on a GitHub download host is accepted.
     *
     * @param string $package API download address.
     * @param string $token   Token.
     * @return string|WP_Error
     */
    private static function ask_signed_address($package, $token) {
        $response = self::remote_no_redirect('GET', $package, array(
            'timeout' => 30,
            'headers' => array(
                'Accept'        => false !== strpos($package, '/releases/assets/') ? 'application/octet-stream' : 'application/vnd.github+json',
                'Authorization' => 'Bearer ' . $token,
            ),
        ));
        if (is_wp_error($response)) {
            return $response;
        }
        $location = self::header_value($response, 'location');
        if ('' === $location || !in_array((int) wp_remote_retrieve_response_code($response), array(301, 302, 303, 307, 308), true)) {
            return new WP_Error('wpallstars_github_download', __('GitHub did not give a download address. Check the token’s access to the repository.', 'wp-plugin-starter-template'));
        }
        $host = strtolower((string) wp_parse_url($location, PHP_URL_HOST));
        if ('https' !== strtolower((string) wp_parse_url($location, PHP_URL_SCHEME)) || !preg_match(self::DOWNLOAD_HOSTS, $host)) {
            return new WP_Error('wpallstars_github_download', __('GitHub sent the download to an unexpected address.', 'wp-plugin-starter-template'));
        }
        return $location;
    }

    /**
     * Keep a plugin in its folder when the zip's top folder has another name
     * (GitHub's source zips are named owner-repo-commit).
     *
     * @param string|WP_Error $source        Unpacked folder.
     * @param string          $remote_source Folder it was unpacked in.
     * @param WP_Upgrader     $upgrader      Upgrader (unused; the filter passes it).
     * @param array           $hook_extra    Context.
     * @return string|WP_Error
     */
    public static function fix_folder($source, $remote_source, $upgrader, $hook_extra = array()) { // NOSONAR: WordPress passes $upgrader to this filter.
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
