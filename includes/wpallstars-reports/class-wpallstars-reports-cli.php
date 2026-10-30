<?php
/**
 * `wp wpallstars report`: draft, list, show and delete problem reports about
 * the wpallstars plugins and themes on this site (class-wpallstars-reports.php).
 * There is no send: an administrator reviews and sends each report in
 * Tools → Report a problem.
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
 * Draft problem reports and improvements for the makers of this site's
 * wpallstars plugins and themes. Drafts wait for an administrator to review
 * and send them in Tools → Report a problem; nothing here sends anything.
 */
final class WPAllStars_Reports_CLI {

    /**
     * Register the command.
     */
    public static function register() {
        WP_CLI::add_command('wpallstars report', __CLASS__);
    }

    /**
     * List the plugins and themes that take reports, and where each sends them.
     *
     * ## OPTIONS
     *
     * [--format=<format>]
     * : table, json, csv or yaml.
     * ---
     * default: table
     * ---
     *
     * ## EXAMPLES
     *
     *     wp wpallstars report products
     *
     * @param array $args       Positional arguments.
     * @param array $assoc_args Options.
     */
    public function products($args, $assoc_args) {
        unset($args);
        $rows = array();
        foreach (WPAllStars_Reports::products() as $slug => $product) {
            $rows[] = array(
                'product' => $slug,
                'name'    => $product['name'],
                'type'    => $product['type'],
                'version' => $product['version'],
                'channel' => $product['channel'],
                'to'      => $product['to'],
            );
        }
        WP_CLI\Utils\format_items(self::format($assoc_args), $rows, array('product', 'name', 'type', 'version', 'channel', 'to'));
    }

    /**
     * Draft a report. It waits for an administrator to review and send it.
     *
     * ## OPTIONS
     *
     * [--product=<slug>]
     * : The plugin folder or theme it is about (`wp wpallstars report products`). May be left out when only one takes reports.
     *
     * --title=<title>
     * : A short summary.
     *
     * [--details=<details>]
     * : What was done, what was expected and what happened, with steps, versions and error messages. Without it, read from STDIN.
     *
     * [--type=<type>]
     * : problem or improvement.
     * ---
     * default: problem
     * options:
     *   - problem
     *   - improvement
     * ---
     *
     * [--porcelain]
     * : Print only the report's ID.
     *
     * ## EXAMPLES
     *
     *     wp wpallstars report create --product=my-plugin --title="Settings do not save on multisite" --details="Steps: ..."
     *     wp wpallstars report create --product=my-plugin --title="Add a CSV export" --type=improvement < details.txt
     *
     * @param array $args       Positional arguments.
     * @param array $assoc_args Options.
     */
    public function create($args, $assoc_args) {
        unset($args);
        $details = isset($assoc_args['details']) ? (string) $assoc_args['details'] : (string) file_get_contents('php://stdin'); // phpcs:ignore WordPress.WP.AlternativeFunctions.file_get_contents_file_get_contents -- WP-CLI input.
        $report  = WPAllStars_Reports::create(array(
            'product' => isset($assoc_args['product']) ? (string) $assoc_args['product'] : '',
            'type'    => isset($assoc_args['type']) ? (string) $assoc_args['type'] : 'problem',
            'title'   => isset($assoc_args['title']) ? (string) $assoc_args['title'] : '',
            'details' => $details,
        ), 'assistant');
        if (is_wp_error($report)) {
            WP_CLI::error($report->get_error_message());
            return;
        }
        if (!empty($assoc_args['porcelain'])) {
            WP_CLI::line($report['id']);
            return;
        }
        WP_CLI::success(sprintf(
            'Draft %1$s saved; nothing has been sent. Ask a site administrator to review and send it in Tools → Report a problem: %2$s',
            $report['id'],
            WPAllStars_Reports::url($report['id'])
        ));
    }

    /**
     * List reports, newest first.
     *
     * ## OPTIONS
     *
     * [--product=<slug>]
     * : Only this plugin or theme's.
     *
     * [--status=<status>]
     * : draft or sent.
     *
     * [--format=<format>]
     * : table, json, csv or yaml.
     * ---
     * default: table
     * ---
     *
     * @subcommand list
     *
     * @param array $args       Positional arguments.
     * @param array $assoc_args Options.
     */
    public function list_($args, $assoc_args) {
        unset($args);
        $rows = array();
        foreach (WPAllStars_Reports::reports(isset($assoc_args['product']) ? (string) $assoc_args['product'] : '', isset($assoc_args['status']) ? (string) $assoc_args['status'] : '') as $report) {
            $rows[] = WPAllStars_Reports::view($report);
        }
        WP_CLI\Utils\format_items(self::format($assoc_args), $rows, array('id', 'product', 'type', 'status', 'channel', 'source', 'created', 'title'));
    }

    /**
     * Show one report and exactly what would be sent.
     *
     * ## OPTIONS
     *
     * <id>
     * : Report ID.
     *
     * [--format=<format>]
     * : yaml or json.
     * ---
     * default: yaml
     * ---
     *
     * @param array $args       Positional arguments.
     * @param array $assoc_args Options.
     */
    public function show($args, $assoc_args) {
        $report = WPAllStars_Reports::get((string) $args[0]);
        if (!$report) {
            WP_CLI::error('No report with that ID.');
            return;
        }
        $view = WPAllStars_Reports::view($report, true);
        if ('json' === self::format($assoc_args, 'yaml')) {
            WP_CLI::line((string) wp_json_encode($view, JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE));
            return;
        }
        WP_CLI\Utils\format_items('yaml', array($view), array_keys($view));
    }

    /**
     * Delete a report.
     *
     * ## OPTIONS
     *
     * <id>
     * : Report ID.
     *
     * @param array $args       Positional arguments.
     * @param array $assoc_args Options.
     */
    public function delete($args, $assoc_args) {
        unset($assoc_args);
        if (!WPAllStars_Reports::delete((string) $args[0])) {
            WP_CLI::error('No report with that ID.');
            return;
        }
        WP_CLI::success('Report deleted.');
    }

    /**
     * The --format option.
     *
     * @param array  $assoc_args Options.
     * @param string $default    Default format.
     * @return string
     */
    private static function format($assoc_args, $default = 'table') {
        $format = isset($assoc_args['format']) ? (string) $assoc_args['format'] : $default;
        return in_array($format, array('table', 'json', 'csv', 'yaml'), true) ? $format : $default;
    }
}
