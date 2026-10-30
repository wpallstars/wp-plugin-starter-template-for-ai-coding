<?php
/**
 * Shared problem reports (load.php says how copies load).
 *
 * A site's AI assistant, or an administrator, drafts a report about one of
 * the wpallstars plugins or themes on the site: a problem, or an
 * improvement. Drafts wait in Tools → Report a problem until an
 * administrator reviews, edits and sends them:
 *
 * - email (a product's support link is mailto:address): sent with the site's
 *   own mailer, wp_mail(), with the site's address and versions, and the
 *   administrator as Reply-To;
 * - GitHub (a product's support link is its GitHub issues): a prefilled new
 *   issue, which the administrator submits with their own GitHub account.
 *   Issues are public, so the site's address, email and IP addresses,
 *   server paths and anything that looks like a key are taken out first.
 *
 * Assistants only draft: the wpallstars/report-problem and wpallstars/reports
 * abilities (WordPress 6.9+) and `wp wpallstars report` have no way to send.
 *
 * Products list themselves through the wpallstars_report_products filter:
 * slug => array(
 *     'name'    => 'Product name',
 *     'type'    => 'plugin' or 'theme',
 *     'version' => '1.2.3',
 *     'support' => 'https://github.com/owner/repo/issues' or 'mailto:address',
 * ).
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

final class WPAllStars_Reports { // phpcs:ignore WordPress.NamingConventions.PrefixAllGlobals -- Shared across wpallstars products; see STANDARDS.md, Problem reports.

    /** Admin screen slug (Tools → Report a problem); wpallstars_report_url() uses it too. */
    const PAGE = 'wpallstars-report';

    /** The site's reports (not autoloaded). */
    const OPTION = 'wpallstars_reports';

    /** admin-post.php action and nonce. */
    const ACTION = 'wpallstars_report';

    /** Abilities' category. */
    const CATEGORY = 'wpallstars';

    /** Drafts kept at once: more are refused until some are sent or deleted. */
    const MAX_DRAFTS = 50;

    /** Reports kept in all; the oldest sent ones go first. */
    const MAX_KEPT = 100;

    /** Longest title, in characters. */
    const TITLE_MAX = 200;

    /** Longest details, in characters. */
    const DETAILS_MAX = 20000;

    /** Longest GitHub issue body, so the new-issue address stays short enough. */
    const GITHUB_BODY_MAX = 6000;

    /** Report types. */
    const TYPES = array('problem', 'improvement');

    /**
     * Products, once read.
     *
     * @var array<string,array{name:string,type:string,version:string,channel:string,to:string}>|null
     */
    private static $products = null;

    /**
     * Why the last report email failed, if it did.
     *
     * @var string
     */
    private static $mail_error = '';

    /**
     * Register hooks.
     */
    public static function load() {
        add_action('admin_menu', array(__CLASS__, 'menu'));
        add_action('admin_post_' . self::ACTION, array(__CLASS__, 'handle'));
        add_action('admin_notices', array(__CLASS__, 'notice'));
        add_action('wp_abilities_api_categories_init', array(__CLASS__, 'register_category'));
        add_action('wp_abilities_api_init', array(__CLASS__, 'register_abilities'));
        if (defined('WP_CLI') && WP_CLI && is_readable(__DIR__ . '/class-wpallstars-reports-cli.php')) {
            require_once __DIR__ . '/class-wpallstars-reports-cli.php';
            WPAllStars_Reports_CLI::register();
        }
    }

    /**
     * Products that take reports: slug => name, type, version, channel
     * (email or github) and to (the address, or the GitHub owner/repo).
     *
     * @return array<string,array{name:string,type:string,version:string,channel:string,to:string}>
     */
    public static function products() {
        if (null !== self::$products) {
            return self::$products;
        }
        /**
         * Filter the wpallstars plugins and themes that take problem reports.
         *
         * @param array<string,array> $products Slug (plugin folder or theme stylesheet) =>
         *                                      name, type (plugin or theme), version and
         *                                      support (GitHub issues address or mailto:address).
         */
        $listed   = apply_filters('wpallstars_report_products', array()); // phpcs:ignore WordPress.NamingConventions.PrefixAllGlobals -- Shared across wpallstars products; see STANDARDS.md, Problem reports.
        $products = array();
        foreach ((array) $listed as $slug => $product) {
            if (!is_string($slug) || !is_array($product)) {
                continue;
            }
            $slug    = sanitize_key($slug);
            $channel = self::channel(isset($product['support']) ? (string) $product['support'] : '');
            if ('' === $slug || null === $channel) {
                continue;
            }
            $name             = isset($product['name']) ? sanitize_text_field((string) $product['name']) : '';
            $products[$slug] = array(
                'name'    => '' !== $name ? $name : $slug,
                'type'    => (isset($product['type']) && 'theme' === $product['type']) ? 'theme' : 'plugin',
                'version' => isset($product['version']) ? sanitize_text_field((string) $product['version']) : '',
                'channel' => $channel[0],
                'to'      => $channel[1],
            );
        }
        uasort($products, function ($a, $b) {
            return strcasecmp($a['name'], $b['name']);
        });
        self::$products = $products;
        return $products;
    }

    /**
     * Where a support link sends reports: array(channel, to), or null for a
     * link that is neither an email address nor a GitHub repository.
     *
     * @param string $support Support link.
     * @return array{0:string,1:string}|null
     */
    private static function channel($support) {
        $support = trim($support);
        if (0 === stripos($support, 'mailto:')) {
            $email = strtok(substr($support, 7), '?');
            $email = false === $email ? '' : sanitize_email(rawurldecode($email));
            return is_email($email) ? array('email', $email) : null;
        }
        if (preg_match('#^https://github\.com/([A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+?)(?:\.git)?(?:/issues)?/?$#', $support, $match)) {
            return array('github', $match[1]);
        }
        return null;
    }

    /**
     * Whether the current user may review and send reports.
     *
     * @return bool
     */
    public static function can_review() {
        return current_user_can('manage_options');
    }

    // Storage.

    /**
     * Every report on this site, newest first.
     *
     * @return array<string,array>
     */
    private static function all() {
        $reports = get_option(self::OPTION, array());
        if (!is_array($reports)) {
            return array();
        }
        $reports = array_filter($reports, function ($report) {
            return is_array($report) && isset($report['id'], $report['product'], $report['title'], $report['status']);
        });
        uasort($reports, function ($a, $b) {
            return (int) ($b['created'] ?? 0) <=> (int) ($a['created'] ?? 0);
        });
        return $reports;
    }

    /**
     * Store the reports, dropping the oldest sent ones beyond MAX_KEPT.
     *
     * @param array<string,array> $reports Reports.
     */
    private static function store(array $reports) {
        if (count($reports) > self::MAX_KEPT) {
            uasort($reports, function ($a, $b) {
                return (int) ($a['created'] ?? 0) <=> (int) ($b['created'] ?? 0);
            });
            foreach ($reports as $id => $report) {
                if (count($reports) <= self::MAX_KEPT) {
                    break;
                }
                if ('sent' === $report['status']) {
                    unset($reports[$id]);
                }
            }
        }
        update_option(self::OPTION, $reports, false);
    }

    /**
     * One report, or null.
     *
     * @param string $id Report ID.
     * @return array|null
     */
    public static function get($id) {
        $reports = self::all();
        $id      = sanitize_key((string) $id);
        return isset($reports[$id]) ? $reports[$id] : null;
    }

    /**
     * Reports, newest first, optionally for one product or status.
     *
     * @param string $product Product slug, or empty for all.
     * @param string $status  draft, sent, or empty for all.
     * @return array<int,array>
     */
    public static function reports($product = '', $status = '') {
        $list = array();
        foreach (self::all() as $report) {
            if ('' !== $product && $report['product'] !== $product) {
                continue;
            }
            if ('' !== $status && $report['status'] !== $status) {
                continue;
            }
            $list[] = $report;
        }
        return $list;
    }

    /**
     * Check and clean a report's fields.
     *
     * @param array $input product, type, title, details.
     * @return array{product:string,type:string,title:string,details:string}|WP_Error
     */
    private static function clean(array $input) {
        $products = self::products();
        $product  = isset($input['product']) ? sanitize_key((string) $input['product']) : '';
        if ('' === $product && 1 === count($products)) {
            foreach (array_keys($products) as $only) {
                $product = (string) $only;
            }
        }
        if (!isset($products[$product])) {
            return new WP_Error(
                'wpallstars_report_product',
                sprintf(
                    /* translators: %s: product slugs, comma-separated. */
                    __('Name the plugin or theme the report is about, one of: %s.', 'wp-plugin-starter-template'),
                    implode(', ', array_keys($products))
                )
            );
        }
        $type    = isset($input['type']) && in_array($input['type'], self::TYPES, true) ? (string) $input['type'] : 'problem';
        $title   = isset($input['title']) ? trim(sanitize_text_field((string) $input['title'])) : '';
        $details = isset($input['details']) ? trim(sanitize_textarea_field((string) $input['details'])) : '';
        if ('' === $title || '' === $details) {
            return new WP_Error('wpallstars_report_empty', __('A report needs a title and details.', 'wp-plugin-starter-template'));
        }
        return array(
            'product' => $product,
            'type'    => $type,
            'title'   => mb_substr($title, 0, self::TITLE_MAX),
            'details' => mb_substr($details, 0, self::DETAILS_MAX),
        );
    }

    /**
     * Draft a report.
     *
     * @param array  $input  product, type, title, details.
     * @param string $source assistant (an ability or WP-CLI) or administrator (the screen).
     * @return array|WP_Error The report.
     */
    public static function create(array $input, $source = 'assistant') {
        $fields = self::clean($input);
        if (is_wp_error($fields)) {
            return $fields;
        }
        $reports = self::all();
        if (count(self::reports('', 'draft')) >= self::MAX_DRAFTS) {
            return new WP_Error(
                'wpallstars_report_full',
                sprintf(
                    /* translators: %d: number of drafts. */
                    __('There are already %d draft reports waiting for review. Send or delete some in Tools → Report a problem first.', 'wp-plugin-starter-template'),
                    self::MAX_DRAFTS
                )
            );
        }
        do {
            $id = strtolower(wp_generate_password(10, false, false));
        } while (isset($reports[$id]));
        $now          = time();
        $reports[$id] = array_merge($fields, array(
            'id'      => $id,
            'status'  => 'draft',
            'source'  => 'administrator' === $source ? 'administrator' : 'assistant',
            'created' => $now,
            'updated' => $now,
            'sent'    => 0,
            'sent_by' => 0,
            'channel' => '',
        ));
        self::store($reports);
        return $reports[$id];
    }

    /**
     * Change a draft's fields.
     *
     * @param string $id    Report ID.
     * @param array  $input product, type, title, details.
     * @return array|WP_Error The report.
     */
    public static function update($id, array $input) {
        $reports = self::all();
        $id      = sanitize_key((string) $id);
        if (!isset($reports[$id])) {
            return new WP_Error('wpallstars_report_missing', __('That report no longer exists.', 'wp-plugin-starter-template'));
        }
        if ('draft' !== $reports[$id]['status']) {
            return new WP_Error('wpallstars_report_sent', __('That report has been sent already.', 'wp-plugin-starter-template'));
        }
        $fields = self::clean($input);
        if (is_wp_error($fields)) {
            return $fields;
        }
        $reports[$id] = array_merge($reports[$id], $fields, array('updated' => time()));
        self::store($reports);
        return $reports[$id];
    }

    /**
     * Delete a report.
     *
     * @param string $id Report ID.
     * @return bool Whether it existed.
     */
    public static function delete($id) {
        $reports = self::all();
        $id      = sanitize_key((string) $id);
        if (!isset($reports[$id])) {
            return false;
        }
        unset($reports[$id]);
        self::store($reports);
        return true;
    }

    /**
     * Record that a report was sent.
     *
     * @param string $id      Report ID.
     * @param string $channel email or github.
     */
    private static function mark_sent($id, $channel) {
        $reports = self::all();
        if (!isset($reports[$id])) {
            return;
        }
        $reports[$id] = array_merge($reports[$id], array(
            'status'  => 'sent',
            'sent'    => time(),
            'sent_by' => get_current_user_id(),
            'channel' => $channel,
        ));
        self::store($reports);
    }

    /**
     * A report as abilities and WP-CLI show it: its fields, the product's
     * name and channel, where to review it and what would be sent.
     *
     * @param array $report  Report.
     * @param bool  $preview Include what would leave the site.
     * @return array<string,mixed>
     */
    public static function view(array $report, $preview = false) {
        $products = self::products();
        $product  = isset($products[$report['product']]) ? $products[$report['product']] : null;
        $view     = array(
            'id'           => $report['id'],
            'product'      => $report['product'],
            'product_name' => $product ? $product['name'] : $report['product'],
            'type'         => $report['type'],
            'title'        => $report['title'],
            'details'      => $report['details'],
            'status'       => $report['status'],
            'source'       => $report['source'],
            'created'      => gmdate('c', (int) $report['created']),
            'sent'         => $report['sent'] ? gmdate('c', (int) $report['sent']) : '',
            'channel'      => 'sent' === $report['status'] ? $report['channel'] : ($product ? $product['channel'] : ''),
            'review_url'   => self::url($report['id']),
        );
        if ($preview && $product) {
            $view['preview'] = 'github' === $product['channel'] ? self::github_text($report, $product) : self::email_text($report, $product, wp_get_current_user());
        }
        return $view;
    }

    // What leaves the site.

    /**
     * The type's name.
     *
     * @param string $type problem or improvement.
     * @return string
     */
    private static function type_label($type) {
        return 'improvement' === $type ? __('Improvement', 'wp-plugin-starter-template') : __('Problem', 'wp-plugin-starter-template');
    }

    /**
     * Versions both channels include.
     *
     * @param array $product Product.
     * @return string[]
     */
    private static function versions(array $product) {
        return array(
            trim($product['name'] . ' ' . $product['version']) . ' (' . $product['type'] . ')',
            'WordPress ' . get_bloginfo('version') . (is_multisite() ? ' (multisite)' : ''),
            'PHP ' . PHP_VERSION,
        );
    }

    /**
     * The email's subject.
     *
     * @param array $report  Report.
     * @param array $product Product.
     * @return string
     */
    private static function email_subject(array $report, array $product) {
        return sprintf('[%s] %s: %s', $product['name'], self::type_label($report['type']), $report['title']);
    }

    /**
     * The email's text: the report, the site and its versions, and who sent
     * it. It goes privately to the product's maker, so it keeps the site's
     * address; anything that looks like a key is still taken out.
     *
     * @param array   $report  Report.
     * @param array   $product Product.
     * @param WP_User $user    Who sends it.
     * @return string
     */
    private static function email_text(array $report, array $product, $user) {
        $theme = wp_get_theme();
        $lines = array(
            self::type_label($report['type']) . ': ' . self::redact($report['title'], false),
            '',
            self::redact($report['details'], false),
            '',
            '--',
            'Site: ' . home_url('/'),
        );
        foreach (self::versions($product) as $version) {
            $lines[] = $version;
        }
        $lines[] = 'Theme: ' . trim($theme->get('Name') . ' ' . $theme->get('Version'));
        $lines[] = 'Plugins: ' . implode(', ', self::active_plugins());
        $lines[] = 'Drafted by: ' . ('administrator' === $report['source'] ? 'a site administrator' : 'the site\'s AI assistant, reviewed by an administrator');
        if ($user instanceof WP_User && $user->exists()) {
            $lines[] = 'Sent by: ' . $user->display_name . ' <' . $user->user_email . '>';
        }
        return implode("\n", $lines) . "\n";
    }

    /**
     * Active plugins' names and versions.
     *
     * @return string[]
     */
    private static function active_plugins() {
        if (!function_exists('get_plugins')) {
            require_once ABSPATH . 'wp-admin/includes/plugin.php';
        }
        $files = (array) get_option('active_plugins', array());
        if (is_multisite()) {
            $files = array_merge($files, array_keys((array) get_site_option('active_sitewide_plugins', array())));
        }
        $plugins = get_plugins();
        $names   = array();
        foreach (array_unique($files) as $file) {
            if (isset($plugins[$file])) {
                $names[] = trim($plugins[$file]['Name'] . ' ' . $plugins[$file]['Version']);
            }
        }
        sort($names);
        return $names;
    }

    /**
     * The GitHub issue's text: the report and versions only, cleaned.
     *
     * @param array $report  Report.
     * @param array $product Product.
     * @return string
     */
    private static function github_text(array $report, array $product) {
        $footer = "\n\n---\n\n- " . implode("\n- ", self::versions($product))
            . "\n\nSent from a site's Tools → Report a problem screen after an administrator's review. The site's address, email and IP addresses, server paths and keys are left out.\n";
        $body   = self::redact($report['details'], true);
        $room   = self::GITHUB_BODY_MAX - mb_strlen($footer);
        if (mb_strlen($body) > $room) {
            $body = rtrim(mb_substr($body, 0, max(0, $room - 30))) . "\n\n[Shortened for GitHub.]";
        }
        return $body . $footer;
    }

    /**
     * The prefilled new-issue address.
     *
     * @param array $report  Report.
     * @param array $product Product.
     * @return string
     */
    private static function github_url(array $report, array $product) {
        $query = http_build_query(
            array(
                'title' => self::redact($report['title'], true),
                'body'  => self::github_text($report, $product),
            ),
            '',
            '&',
            PHP_QUERY_RFC3986
        );
        return 'https://github.com/' . $product['to'] . '/issues/new?' . $query;
    }

    /**
     * Take out anything that looks like a key or password; for a public
     * report, also the site's address, email and IP addresses and server
     * paths.
     *
     * @param string $text   Text.
     * @param bool   $public For a public GitHub issue.
     * @return string
     */
    public static function redact($text, $public) {
        $text = (string) $text;
        $rules = array(
            // wp-config.php keys, salts and passwords.
            '/(define\(\s*[\'"][A-Z0-9_]*(?:KEY|SALT|PASSWORD|PASS|TOKEN|SECRET)[A-Z0-9_]*[\'"]\s*,\s*)([\'"]).*?\2/' => '$1\'[removed]\'',
            // name=value and name: value pairs that hold secrets.
            '/\b(Authorization\s*["\']?\s*[=:]\s*)[^\r\n]+/i' => '$1[removed]',
            '/\b((?:password|passwd|pwd|secret|token|api[_-]?key|licen[cs]e[_-]?key|access[_-]?key)["\']?\s*[=:]\s*)(["\']?)[^\s"\'&,;]+\2/i' => '$1[removed]',
            '/\bBearer\s+[A-Za-z0-9._~+\/=-]{16,}/' => 'Bearer [removed]',
            // Known key formats, then long random-looking strings of letters and digits.
            '/\b(?:gh[pousr]_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}|sk_(?:live|test)_[A-Za-z0-9]{10,}|xox[abpr]-[A-Za-z0-9-]{10,}|AKIA[0-9A-Z]{16}|AIza[0-9A-Za-z_-]{30,})\b/' => '[key removed]',
            '/\b(?=[A-Za-z0-9]*[0-9])(?=[A-Za-z0-9]*[A-Za-z])[A-Za-z0-9]{32,}\b/' => '[key removed]',
        );
        if ($public) {
            foreach (self::site_hosts() as $host) {
                $quoted                                                            = preg_quote($host, '#');
                $rules['#\bhttps?://(?:www\.)?' . $quoted . '\b[^\s<>"\')\]]*#i'] = '[site address]';
                $rules['#\b(?:www\.)?' . $quoted . '\b#i']                         = '[site]';
            }
            $paths = array_unique(array_filter(array(untrailingslashit(ABSPATH), untrailingslashit(WP_CONTENT_DIR))));
            usort($paths, function ($a, $b) {
                return strlen($b) - strlen($a);
            });
            foreach ($paths as $path) {
                $rules['#' . preg_quote($path, '#') . '#'] = '[site folder]';
            }
            $rules += array(
                '/[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}/i'                   => '[email address]',
                '/\b(?:(?:25[0-5]|2[0-4]\d|1?\d?\d)\.){3}(?:25[0-5]|2[0-4]\d|1?\d?\d)\b/' => '[IP address]',
                '/\b(?:[0-9a-f]{1,4}:){3,7}[0-9a-f]{1,4}\b/i'                => '[IP address]',
                '#(/(?:home|Users|var/www|srv|data)/)[^/\s]+#'               => '$1[folder]',
                '#\b([A-Z]:\\\\Users\\\\)[^\\\\\s]+#i'                        => '$1[folder]',
            );
        }
        foreach ($rules as $pattern => $replacement) {
            $cleaned = preg_replace($pattern, $replacement, $text);
            if (is_string($cleaned)) {
                $text = $cleaned;
            }
        }
        return $text;
    }

    /**
     * The site's host names: this site's and, on multisite, the network's.
     *
     * @return string[]
     */
    private static function site_hosts() {
        $urls = array(home_url(), site_url());
        if (is_multisite()) {
            $urls[] = network_home_url();
        }
        $hosts = array();
        foreach ($urls as $url) {
            $host = wp_parse_url($url, PHP_URL_HOST);
            if (is_string($host) && '' !== $host) {
                $hosts[] = (string) preg_replace('/^www\./i', '', strtolower($host));
            }
        }
        $hosts = array_unique($hosts);
        usort($hosts, function ($a, $b) {
            return strlen($b) - strlen($a);
        });
        return $hosts;
    }

    /**
     * Send a report: email it, or give the GitHub new-issue address to
     * open. Only the admin screen calls this, for an administrator.
     *
     * @param array $report Report.
     * @return string|WP_Error The GitHub address to open, '' once emailed, or an error.
     */
    private static function send(array $report) {
        $products = self::products();
        if (!isset($products[$report['product']])) {
            return new WP_Error('wpallstars_report_product', __('That plugin or theme no longer takes reports here.', 'wp-plugin-starter-template'));
        }
        $product = $products[$report['product']];
        if ('github' === $product['channel']) {
            self::mark_sent($report['id'], 'github');
            return self::github_url($report, $product);
        }

        $user    = wp_get_current_user();
        $headers = array();
        if ($user->exists() && is_email($user->user_email)) {
            $name      = trim((string) preg_replace('/[\r\n<>",]+/', ' ', $user->display_name));
            $headers[] = 'Reply-To: ' . ('' !== $name ? $name . ' <' . $user->user_email . '>' : $user->user_email);
        }
        self::$mail_error = '';
        add_action('wp_mail_failed', array(__CLASS__, 'mail_failed'));
        $sent = wp_mail($product['to'], self::email_subject($report, $product), self::email_text($report, $product, $user), $headers);
        remove_action('wp_mail_failed', array(__CLASS__, 'mail_failed'));
        if (!$sent) {
            $message = self::mail_error();
            return new WP_Error('wpallstars_report_mail', '' !== $message ? $message : __('The site could not send email.', 'wp-plugin-starter-template'));
        }
        self::mark_sent($report['id'], 'email');
        return '';
    }

    /**
     * Keep why wp_mail() failed (wp_mail_failed, while a report is sent).
     *
     * @param mixed $error WP_Error.
     */
    public static function mail_failed($error) {
        if ($error instanceof WP_Error) {
            self::$mail_error = $error->get_error_message();
        }
    }

    /**
     * Why the last report email failed, or ''.
     *
     * @return string
     */
    private static function mail_error() {
        return self::$mail_error;
    }

    // Admin screen.

    /**
     * The screen's address, for one report or the list.
     *
     * @param string $report Report ID, 'new', or empty for the list.
     * @param array  $args   More query arguments.
     * @return string
     */
    public static function url($report = '', array $args = array()) {
        if ('' !== $report) {
            $args['report'] = $report;
        }
        return add_query_arg($args, admin_url('tools.php?page=' . self::PAGE));
    }

    /**
     * Tools → Report a problem, when some product takes reports.
     */
    public static function menu() {
        if (!self::products()) {
            return;
        }
        add_management_page(
            __('Report a problem', 'wp-plugin-starter-template'),
            __('Report a problem', 'wp-plugin-starter-template'),
            'manage_options',
            self::PAGE,
            array(__CLASS__, 'render')
        );
    }

    /**
     * Say so on the Dashboard, Plugins and Themes screens while an
     * assistant's drafts wait for review.
     */
    public static function notice() {
        if (!self::can_review() || !function_exists('get_current_screen')) {
            return;
        }
        $screen = get_current_screen();
        if (!$screen || !in_array($screen->id, array('dashboard', 'plugins', 'themes'), true)) {
            return;
        }
        $waiting = 0;
        foreach (self::reports('', 'draft') as $report) {
            if ('assistant' === $report['source']) {
                ++$waiting;
            }
        }
        if (!$waiting) {
            return;
        }
        printf(
            '<div class="notice notice-info"><p>%1$s <a href="%2$s">%3$s</a></p></div>',
            esc_html(sprintf(
                /* translators: %d: number of draft reports. */
                _n(
                    'Your AI assistant drafted %d report about a wpallstars plugin or theme. Nothing is sent until you review it.',
                    'Your AI assistant drafted %d reports about wpallstars plugins or themes. Nothing is sent until you review them.',
                    $waiting,
                    'wp-plugin-starter-template'
                ),
                $waiting
            )),
            esc_url(self::url()),
            esc_html__('Review reports', 'wp-plugin-starter-template')
        );
    }

    /**
     * Draw the screen: a report to review, a new one, or the list.
     */
    public static function render() {
        if (!self::can_review()) {
            wp_die(esc_html__('Sorry, you are not allowed to review reports.', 'wp-plugin-starter-template'));
        }
        // phpcs:disable WordPress.Security.NonceVerification.Recommended -- these only choose what to show.
        $id      = isset($_GET['report']) ? sanitize_key(wp_unslash($_GET['report'])) : '';
        $product = isset($_GET['product']) ? sanitize_key(wp_unslash($_GET['product'])) : '';
        $done    = isset($_GET['done']) ? sanitize_key(wp_unslash($_GET['done'])) : '';
        // phpcs:enable WordPress.Security.NonceVerification.Recommended
        echo '<div class="wrap">';
        echo '<h1 class="wp-heading-inline">' . esc_html__('Report a problem', 'wp-plugin-starter-template') . '</h1>';
        if ('new' !== $id) {
            $new_url = self::url('new', $product ? array('product' => $product) : array());
            printf(' <a class="page-title-action" href="%1$s">%2$s</a>', esc_url($new_url), esc_html__('New report', 'wp-plugin-starter-template'));
        }
        echo '<hr class="wp-header-end">';
        self::render_done($done);

        $report = '' !== $id && 'new' !== $id ? self::get($id) : null;
        if ('new' === $id || $report) {
            self::render_form($report, $product);
        } else {
            self::render_list($product);
        }
        echo '</div>';
    }

    /**
     * The message after an action.
     *
     * @param string $done saved, sent, deleted or failed.
     */
    private static function render_done($done) {
        $messages = array(
            'saved'   => array('success', __('Draft saved. Check what will be sent below, then send it.', 'wp-plugin-starter-template')),
            'sent'    => array('success', __('Report sent. Thank you: the maker will look into it.', 'wp-plugin-starter-template')),
            'deleted' => array('success', __('Report deleted.', 'wp-plugin-starter-template')),
        );
        $error = get_transient(self::error_key());
        if ('failed' === $done && is_string($error) && '' !== $error) {
            delete_transient(self::error_key());
            $messages['failed'] = array('error', $error);
        }
        if (!isset($messages[$done])) {
            return;
        }
        printf('<div class="notice notice-%1$s is-dismissible"><p>%2$s</p></div>', esc_attr($messages[$done][0]), esc_html($messages[$done][1]));
    }

    /**
     * Transient key for the current user's last error.
     *
     * @return string
     */
    private static function error_key() {
        return 'wpallstars_report_error_' . get_current_user_id();
    }

    /**
     * Where a product's reports go, in words.
     *
     * @param array $product Product.
     * @return string
     */
    private static function channel_label(array $product) {
        if ('github' === $product['channel']) {
            /* translators: %s: GitHub repository, owner/name. */
            return sprintf(__('a public GitHub issue on %s', 'wp-plugin-starter-template'), $product['to']);
        }
        /* translators: %s: email address. */
        return sprintf(__('a private email to %s', 'wp-plugin-starter-template'), $product['to']);
    }

    /**
     * The list of reports.
     *
     * @param string $product Product slug to show first in the intro, if any.
     */
    private static function render_list($product) {
        $products = self::products();
        echo '<p>' . esc_html__('Tell the makers of the wpallstars plugins and themes on this site about a problem or an improvement, so every site using them gets the fix. Your AI assistant can draft reports too (the wpallstars/report-problem ability, or wp wpallstars report create); nothing leaves the site until an administrator sends it here.', 'wp-plugin-starter-template') . '</p>';
        echo '<ul class="ul-disc">';
        foreach ($products as $slug => $item) {
            printf(
                '<li>%1$s: %2$s</li>',
                (string) $slug === $product ? '<strong>' . esc_html($item['name']) . '</strong>' : esc_html($item['name']),
                esc_html(self::channel_label($item))
            );
        }
        echo '</ul>';

        $reports = self::reports();
        if (!$reports) {
            echo '<p>' . esc_html__('No reports yet.', 'wp-plugin-starter-template') . '</p>';
            return;
        }
        echo '<table class="widefat striped"><thead><tr>';
        foreach (array(__('Title', 'wp-plugin-starter-template'), __('Plugin or theme', 'wp-plugin-starter-template'), __('Type', 'wp-plugin-starter-template'), __('Status', 'wp-plugin-starter-template'), __('Drafted by', 'wp-plugin-starter-template'), __('Date', 'wp-plugin-starter-template')) as $heading) {
            echo '<th scope="col">' . esc_html($heading) . '</th>';
        }
        echo '</tr></thead><tbody>';
        foreach ($reports as $report) {
            $name = isset($products[$report['product']]) ? $products[$report['product']]['name'] : $report['product'];
            echo '<tr>';
            echo '<td><a href="' . esc_url(self::url($report['id'])) . '"><strong>' . esc_html($report['title']) . '</strong></a></td>';
            echo '<td>' . esc_html($name) . '</td>';
            echo '<td>' . esc_html(self::type_label($report['type'])) . '</td>';
            echo '<td>' . esc_html(self::status_label($report)) . '</td>';
            echo '<td>' . esc_html('administrator' === $report['source'] ? __('Administrator', 'wp-plugin-starter-template') : __('AI assistant', 'wp-plugin-starter-template')) . '</td>';
            echo '<td>' . esc_html((string) wp_date(get_option('date_format') . ' ' . get_option('time_format'), (int) $report['created'])) . '</td>';
            echo '</tr>';
        }
        echo '</tbody></table>';
    }

    /**
     * A report's status, in words.
     *
     * @param array $report Report.
     * @return string
     */
    private static function status_label(array $report) {
        if ('sent' !== $report['status']) {
            return __('Draft, waiting for review', 'wp-plugin-starter-template');
        }
        $when = (string) wp_date((string) get_option('date_format'), (int) $report['sent']);
        if ('github' === $report['channel']) {
            /* translators: %s: date. */
            return sprintf(__('Opened on GitHub %s', 'wp-plugin-starter-template'), $when);
        }
        /* translators: %s: date. */
        return sprintf(__('Emailed %s', 'wp-plugin-starter-template'), $when);
    }

    /**
     * The form for a new report or one to review.
     *
     * @param array|null $report  Report, or null for a new one.
     * @param string     $product Product to select in a new report.
     */
    private static function render_form($report, $product) {
        $products = self::products();
        $sent     = $report && 'sent' === $report['status'];
        $current  = $report ? $report['product'] : $product;
        $type     = $report ? $report['type'] : 'problem';
        $disabled = $sent ? ' disabled' : '';
        $details  = $report ? (string) $report['details'] : '';
        ?>
        <p><a href="<?php echo esc_url(self::url()); ?>">&larr; <?php esc_html_e('All reports', 'wp-plugin-starter-template'); ?></a></p>
        <?php if ($report && 'assistant' === $report['source'] && !$sent) : ?>
            <p><?php esc_html_e('Your AI assistant drafted this report. Check it says what you want the maker to know, change anything that is wrong, then send it.', 'wp-plugin-starter-template'); ?></p>
        <?php endif; ?>
        <form method="post" action="<?php echo esc_url(admin_url('admin-post.php')); ?>">
            <input type="hidden" name="action" value="<?php echo esc_attr(self::ACTION); ?>" />
            <input type="hidden" name="report" value="<?php echo esc_attr($report ? $report['id'] : ''); ?>" />
            <?php wp_nonce_field(self::ACTION); ?>
            <table class="form-table">
                <tr>
                    <th scope="row"><label for="wpallstars-report-product"><?php esc_html_e('Plugin or theme', 'wp-plugin-starter-template'); ?></label></th>
                    <td>
                        <select id="wpallstars-report-product" name="product"<?php echo esc_attr($disabled); ?>>
                            <?php foreach ($products as $slug => $item) : ?>
                                <option value="<?php echo esc_attr($slug); ?>"<?php selected($slug, $current); ?>><?php echo esc_html($item['name'] . ' — ' . self::channel_label($item)); ?></option>
                            <?php endforeach; ?>
                        </select>
                    </td>
                </tr>
                <tr>
                    <th scope="row"><?php esc_html_e('Type', 'wp-plugin-starter-template'); ?></th>
                    <td>
                        <fieldset>
                            <?php foreach (self::TYPES as $option) : ?>
                                <label><input type="radio" name="type" value="<?php echo esc_attr($option); ?>"<?php checked($option, $type); ?><?php echo esc_attr($disabled); ?> /> <?php echo esc_html(self::type_label($option)); ?></label><br />
                            <?php endforeach; ?>
                        </fieldset>
                    </td>
                </tr>
                <tr>
                    <th scope="row"><label for="wpallstars-report-title"><?php esc_html_e('Title', 'wp-plugin-starter-template'); ?></label></th>
                    <td><input type="text" id="wpallstars-report-title" name="title" class="large-text" maxlength="<?php echo esc_attr((string) self::TITLE_MAX); ?>" required value="<?php echo esc_attr($report ? $report['title'] : ''); ?>"<?php echo esc_attr($disabled); ?> /></td>
                </tr>
                <tr>
                    <th scope="row"><label for="wpallstars-report-details"><?php esc_html_e('Details', 'wp-plugin-starter-template'); ?></label></th>
                    <td>
                        <textarea id="wpallstars-report-details" name="details" class="large-text code" rows="14" maxlength="<?php echo esc_attr((string) self::DETAILS_MAX); ?>" required<?php echo esc_attr($disabled); ?>><?php printf('%s', esc_textarea($details)); ?></textarea>
                        <p class="description"><?php esc_html_e('What you did, what you expected and what happened, with the steps to see it again, or the improvement and why it would help. Leave out passwords and licence keys.', 'wp-plugin-starter-template'); ?></p>
                    </td>
                </tr>
            </table>
            <?php
            if ($report && isset($products[$report['product']])) {
                self::render_preview($report, $products[$report['product']], $sent);
            }
            ?>
            <p class="submit">
                <?php if (!$sent) : ?>
                    <button type="submit" name="do" value="save" class="button"><?php esc_html_e('Save draft', 'wp-plugin-starter-template'); ?></button>
                    <?php if ($report && isset($products[$report['product']])) : ?>
                        <button type="submit" name="do" value="send" class="button button-primary">
                            <?php
                            if ('github' === $products[$report['product']]['channel']) {
                                esc_html_e('Open the issue on GitHub', 'wp-plugin-starter-template');
                            } else {
                                esc_html_e('Send by email', 'wp-plugin-starter-template');
                            }
                            ?>
                        </button>
                    <?php endif; ?>
                <?php endif; ?>
                <?php if ($report) : ?>
                    <button type="submit" name="do" value="delete" class="button button-link-delete"><?php esc_html_e('Delete', 'wp-plugin-starter-template'); ?></button>
                <?php endif; ?>
            </p>
        </form>
        <?php
    }

    /**
     * What leaves the site, word for word.
     *
     * @param array $report  Report.
     * @param array $product Product.
     * @param bool  $sent    Already sent.
     */
    private static function render_preview(array $report, array $product, $sent) {
        echo '<h2>' . esc_html__('What will be sent', 'wp-plugin-starter-template') . '</h2>';
        if ('github' === $product['channel']) {
            echo '<p>' . esc_html(sprintf(
                /* translators: %s: GitHub repository, owner/name. */
                __('Opens a new issue on GitHub (%s) with this text filled in, for you to submit with your own GitHub account. GitHub issues are public, so the site\'s address, email and IP addresses, server paths and anything that looks like a key are taken out. Check the text below before you submit it.', 'wp-plugin-starter-template'),
                $product['to']
            )) . '</p>';
            echo '<p><strong>' . esc_html(self::redact($report['title'], true)) . '</strong></p>';
            echo '<pre style="white-space:pre-wrap;max-height:30em;overflow:auto;">' . esc_html(self::github_text($report, $product)) . '</pre>';
        } else {
            echo '<p>' . esc_html(sprintf(
                /* translators: %s: email address. */
                __('Sent privately by this site\'s email to %s, with your name and email address to reply to. Anything that looks like a password or key is taken out.', 'wp-plugin-starter-template'),
                $product['to']
            )) . '</p>';
            echo '<p><strong>' . esc_html(self::email_subject($report, $product)) . '</strong></p>';
            echo '<pre style="white-space:pre-wrap;max-height:30em;overflow:auto;">' . esc_html(self::email_text($report, $product, wp_get_current_user())) . '</pre>';
        }
        if (!$sent) {
            echo '<p class="description">' . esc_html__('Changed the text or the plugin or theme? Save the draft to see the new version here.', 'wp-plugin-starter-template') . '</p>';
        }
    }

    /**
     * Save, send or delete from the form (admin-post.php).
     */
    public static function handle() {
        if (!self::can_review()) {
            wp_die(esc_html__('Sorry, you are not allowed to review reports.', 'wp-plugin-starter-template'), '', array('response' => 403));
        }
        check_admin_referer(self::ACTION);
        $id    = isset($_POST['report']) ? sanitize_key(wp_unslash($_POST['report'])) : '';
        $do    = isset($_POST['do']) ? sanitize_key(wp_unslash($_POST['do'])) : 'save';
        $input = array(
            'product' => isset($_POST['product']) ? sanitize_key(wp_unslash($_POST['product'])) : '',
            'type'    => isset($_POST['type']) ? sanitize_key(wp_unslash($_POST['type'])) : 'problem',
            'title'   => isset($_POST['title']) ? sanitize_text_field(wp_unslash($_POST['title'])) : '',
            'details' => isset($_POST['details']) ? sanitize_textarea_field(wp_unslash($_POST['details'])) : '',
        );

        if ('delete' === $do) {
            self::delete($id);
            self::redirect(self::url('', array('done' => 'deleted')));
        }

        if ('' === $id) {
            $report = self::create($input, 'administrator');
        } else {
            $report = self::get($id);
            if (!$report) {
                self::fail(__('That report no longer exists.', 'wp-plugin-starter-template'), '');
                return;
            }
            if ('draft' === $report['status']) {
                $report = self::update($id, $input);
            }
        }
        if (is_wp_error($report)) {
            self::fail($report->get_error_message(), '' === $id ? 'new' : $id);
            return;
        }
        if ('send' !== $do || 'draft' !== $report['status']) {
            self::redirect(self::url($report['id'], array('done' => 'saved')));
        }

        $result = self::send($report);
        if (is_wp_error($result)) {
            self::fail($result->get_error_message(), $report['id']);
            return;
        }
        if ('' !== $result) {
            add_filter('allowed_redirect_hosts', function ($hosts) {
                $hosts[] = 'github.com';
                return $hosts;
            });
            self::redirect($result);
        }
        self::redirect(self::url('', array('done' => 'sent')));
    }

    /**
     * Keep an error for the screen and go back to it.
     *
     * @param string $message Error.
     * @param string $report  Report ID, or 'new'.
     */
    private static function fail($message, $report) {
        set_transient(self::error_key(), $message, 5 * MINUTE_IN_SECONDS);
        self::redirect(self::url($report, array('done' => 'failed')));
    }

    /**
     * Redirect and stop.
     *
     * @param string $url Address.
     */
    private static function redirect($url) {
        wp_safe_redirect($url);
        exit;
    }

    // Abilities (WordPress 6.9+).

    /**
     * The abilities' category, unless another copy or plugin has it.
     */
    public static function register_category() {
        if (!function_exists('wp_register_ability_category')) {
            return;
        }
        if (function_exists('wp_has_ability_category') && wp_has_ability_category(self::CATEGORY)) {
            return;
        }
        wp_register_ability_category(self::CATEGORY, array(
            'label'       => __('wpallstars plugins and themes', 'wp-plugin-starter-template'),
            'description' => __('Problem reports and improvements for the makers of the wpallstars plugins and themes on this site.', 'wp-plugin-starter-template'),
        ));
    }

    /**
     * wpallstars/report-problem (draft) and wpallstars/reports (read).
     */
    public static function register_abilities() {
        if (!function_exists('wp_register_ability') || !self::products()) {
            return;
        }
        $slugs = array_keys(self::products());
        wp_register_ability('wpallstars/report-problem', array(
            'label'               => __('Report a problem', 'wp-plugin-starter-template'),
            'description'         => __('Draft a problem report or an improvement for the maker of one of this site\'s wpallstars plugins or themes (list them with wpallstars/reports), so every site using it gets the fix. Use it when a problem or improvement belongs to that product\'s own code, not to this site\'s content or settings. It only saves a draft: nothing leaves the site until a site administrator reviews and sends it in Tools → Report a problem, so tell them to. Say what was done, what was expected and what happened, with steps, versions and error messages; leave out passwords, keys and personal data.', 'wp-plugin-starter-template'),
            'category'            => self::CATEGORY,
            'input_schema'        => array(
                'type'                 => 'object',
                'additionalProperties' => false,
                'required'             => array('title', 'details'),
                'properties'           => array(
                    'product' => array(
                        'type'        => 'string',
                        'enum'        => $slugs,
                        'description' => __('The plugin folder or theme the report is about. May be left out when only one takes reports.', 'wp-plugin-starter-template'),
                    ),
                    'type'    => array(
                        'type'    => 'string',
                        'enum'    => self::TYPES,
                        'default' => 'problem',
                    ),
                    'title'   => array(
                        'type'      => 'string',
                        'minLength' => 1,
                        'maxLength' => self::TITLE_MAX,
                    ),
                    'details' => array(
                        'type'      => 'string',
                        'minLength' => 1,
                        'maxLength' => self::DETAILS_MAX,
                    ),
                ),
            ),
            'output_schema'       => array('type' => 'object'),
            'execute_callback'    => array(__CLASS__, 'ability_report'),
            'permission_callback' => array(__CLASS__, 'can_review'),
            'meta'                => array(
                'show_in_rest' => true,
                'annotations'  => array('readonly' => false, 'destructive' => false, 'idempotent' => false),
            ),
        ));
        wp_register_ability('wpallstars/reports', array(
            'label'               => __('Problem reports', 'wp-plugin-starter-template'),
            'description'         => __('List the wpallstars plugins and themes that take problem reports, where each sends them, and this site\'s reports with their status; with an id, one report and exactly what would be sent.', 'wp-plugin-starter-template'),
            'category'            => self::CATEGORY,
            'input_schema'        => array(
                'type'                 => 'object',
                'default'              => array(),
                'additionalProperties' => false,
                'properties'           => array(
                    'id'      => array('type' => 'string'),
                    'product' => array('type' => 'string'),
                    'status'  => array('type' => 'string', 'enum' => array('', 'draft', 'sent'), 'default' => ''),
                ),
            ),
            'output_schema'       => array('type' => 'object'),
            'execute_callback'    => array(__CLASS__, 'ability_reports'),
            'permission_callback' => array(__CLASS__, 'can_review'),
            'meta'                => array(
                'show_in_rest' => true,
                'annotations'  => array('readonly' => true, 'destructive' => false, 'idempotent' => true),
            ),
        ));
    }

    /**
     * wpallstars/report-problem.
     *
     * @param mixed $input Input.
     * @return array<string,mixed>|WP_Error
     */
    public static function ability_report($input = null) {
        $report = self::create(is_array($input) ? $input : array(), 'assistant');
        if (is_wp_error($report)) {
            return $report;
        }
        $view            = self::view($report);
        $view['message'] = sprintf(
            /* translators: %s: address of the Report a problem screen. */
            __('Saved as a draft; nothing has been sent. Ask a site administrator to review and send it in Tools → Report a problem: %s', 'wp-plugin-starter-template'),
            $view['review_url']
        );
        return $view;
    }

    /**
     * wpallstars/reports.
     *
     * @param mixed $input Input.
     * @return array<string,mixed>|WP_Error
     */
    public static function ability_reports($input = null) {
        $input = is_array($input) ? $input : array();
        if (!empty($input['id'])) {
            $report = self::get((string) $input['id']);
            if (!$report) {
                return new WP_Error('wpallstars_report_missing', __('That report no longer exists.', 'wp-plugin-starter-template'));
            }
            return array('report' => self::view($report, true));
        }
        $products = array();
        foreach (self::products() as $slug => $product) {
            $products[] = array(
                'product' => $slug,
                'name'    => $product['name'],
                'type'    => $product['type'],
                'version' => $product['version'],
                'channel' => $product['channel'],
            );
        }
        $reports = array();
        foreach (self::reports(sanitize_key((string) ($input['product'] ?? '')), sanitize_key((string) ($input['status'] ?? ''))) as $report) {
            $reports[] = self::view($report);
        }
        return array(
            'products'   => $products,
            'reports'    => $reports,
            'review_url' => self::url(),
        );
    }
}
