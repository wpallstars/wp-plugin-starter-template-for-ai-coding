<?php
/**
 * WP-CLI for the shared licensed updates (class-wpallstars-licence.php):
 * `wp wpallstars licence status|activate|check|deactivate`.
 *
 * Keys are read from the WPALLSTARS_LICENCE_KEY environment variable or
 * standard input, never from an argument (arguments show in process lists
 * and shell history), and are never printed: only their last four
 * characters.
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

/**
 * Manage the licences that bring updates from wpallstars.com.
 */
final class WPAllStars_Licence_CLI {

    /** Register the command. */
    public static function register() {
        if (class_exists('WP_CLI')) {
            WP_CLI::add_command('wpallstars licence', __CLASS__);
        }
    }

    /**
     * List the installed products and their licences.
     *
     * ## OPTIONS
     *
     * [--format=<format>]
     * : table, csv, json or yaml.
     * ---
     * default: table
     * ---
     *
     * ## EXAMPLES
     *
     *     wp wpallstars licence status --format=json
     *
     * @param array<int,string>    $args       Positional arguments.
     * @param array<string,string> $assoc_args Options.
     */
    public function status($args, $assoc_args) {
        unset($args);
        $rows = array();
        foreach (WPAllStars_Licence::products() as $item => $product) {
            $stored = WPAllStars_Licence::stored($item);
            $rows[] = array(
                'item'    => $item,
                'type'    => $product['type'],
                'slug'    => $product['slug'],
                'version' => $product['version'],
                'status'  => '' === $stored['secret'] ? 'none' : $stored['status'],
                'valid'   => WPAllStars_Licence::valid($item) ? 'yes' : 'no',
                'key'     => '' === $stored['hint'] ? '' : '…' . $stored['hint'],
                'expires' => $stored['expires'],
                'checked' => $stored['checked'] ? gmdate('Y-m-d H:i:s', $stored['checked']) : '',
                'error'   => $stored['error'],
            );
        }
        WP_CLI\Utils\format_items(isset($assoc_args['format']) ? $assoc_args['format'] : 'table', $rows, array('item', 'type', 'slug', 'version', 'status', 'valid', 'key', 'expires', 'checked', 'error'));
    }

    /**
     * Activate a licence key for one product. The key comes from the
     * WPALLSTARS_LICENCE_KEY environment variable, else standard input.
     *
     * ## OPTIONS
     *
     * --item=<id>
     * : The product's item ID in the shop (its Licence Item header).
     *
     * ## EXAMPLES
     *
     *     printf '%s' "$KEY" | wp wpallstars licence activate --item=856
     *
     * @param array<int,string>    $args       Positional arguments.
     * @param array<string,string> $assoc_args Options.
     */
    public function activate($args, $assoc_args) {
        unset($args);
        $item = self::item($assoc_args);
        $key  = (string) getenv('WPALLSTARS_LICENCE_KEY');
        if ('' === trim($key)) {
            $key = (string) stream_get_contents(STDIN, 400); // phpcs:ignore WordPress.WP.AlternativeFunctions -- reads the key from standard input, never an argument.
        }
        self::finish(WPAllStars_Licence::activate($item, $key), $item);
    }

    /**
     * Check one product's licence with the shop now, or every stored one.
     *
     * ## OPTIONS
     *
     * [--item=<id>]
     * : The product's item ID; all stored licences when left out.
     *
     * @param array<int,string>    $args       Positional arguments.
     * @param array<string,string> $assoc_args Options.
     */
    public function check($args, $assoc_args) {
        unset($args);
        if (!isset($assoc_args['item'])) {
            $failed = 0;
            foreach (array_keys(WPAllStars_Licence::products()) as $item) {
                if ('' === WPAllStars_Licence::stored($item)['secret']) {
                    continue;
                }
                $result = WPAllStars_Licence::check($item);
                if (is_wp_error($result) || !WPAllStars_Licence::valid($item)) {
                    ++$failed;
                    WP_CLI::warning(sprintf('%d: %s', $item, is_wp_error($result) ? $result->get_error_message() : WPAllStars_Licence::describe($item)));
                } else {
                    WP_CLI::log(sprintf('%d: %s', $item, WPAllStars_Licence::describe($item)));
                }
            }
            if ($failed) {
                WP_CLI::error(sprintf('%d licence(s) not valid.', $failed));
            }
            WP_CLI::success('Checked.');
            return;
        }
        $item = self::item($assoc_args);
        self::finish(WPAllStars_Licence::check($item), $item);
    }

    /**
     * Free this site's activation of one product in the shop, and forget
     * its key here.
     *
     * ## OPTIONS
     *
     * --item=<id>
     * : The product's item ID.
     *
     * @param array<int,string>    $args       Positional arguments.
     * @param array<string,string> $assoc_args Options.
     */
    public function deactivate($args, $assoc_args) {
        unset($args);
        $item   = self::item($assoc_args);
        $result = WPAllStars_Licence::deactivate($item);
        if (is_wp_error($result)) {
            WP_CLI::error($result->get_error_message());
        }
        WP_CLI::success(sprintf('%d: licence deactivated and forgotten here.', $item));
    }

    /**
     * The --item option, checked against the installed products.
     *
     * @param array<string,string> $assoc_args Options.
     * @return int
     */
    private static function item(array $assoc_args) {
        $item = isset($assoc_args['item']) ? absint($assoc_args['item']) : 0;
        if (!isset(WPAllStars_Licence::products()[$item])) {
            WP_CLI::error(sprintf('No installed plugin or theme has "Licence Item: %d" and an Update URI on wpallstars.com.', $item));
        }
        return $item;
    }

    /**
     * Report a result: success with the licence's state, or an error.
     *
     * @param true|WP_Error $result Result.
     * @param int           $item   Item ID.
     */
    private static function finish($result, $item) {
        if (is_wp_error($result)) {
            WP_CLI::error($result->get_error_message());
        }
        if (!WPAllStars_Licence::valid($item)) {
            WP_CLI::error(sprintf('%d: %s', $item, WPAllStars_Licence::describe($item)));
        }
        WP_CLI::success(sprintf('%d: %s', $item, WPAllStars_Licence::describe($item)));
    }
}
