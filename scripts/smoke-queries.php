<?php
/**
 * Query checks for scripts/smoke-test.sh (STANDARDS.md → Performance).
 *
 * A must-use plugin on the smoke test's throwaway site only; it never ships
 * (.distignore leaves out scripts/). With the WPALLSTARS_SMOKE_PLUGIN
 * constant set to the tested plugin's folder name and SAVEQUERIES on, it
 * records each request's query count and time, and which queries the tested
 * plugin made (a file of the plugin is in the call stack). WP-CLI then calls:
 *
 *   wpallstars_smoke_seed( $posts )      adds $posts posts, 3 meta rows each,
 *                                        all in one category.
 *   wpallstars_smoke_reset()             forgets the recorded requests.
 *   wpallstars_smoke_report( $rows )     lists the requests, then runs EXPLAIN
 *                                        on each of the plugin's own queries.
 *                                        A full table or index scan, or a
 *                                        sort, over $rows rows or more fails.
 *
 * /?smoke-query-canary runs a known full table scan as if the plugin had
 * made it; the report must find it, which proves the check works (a report
 * with no findings proves nothing otherwise).
 *
 * The names start with wpallstars_ so they stay the same in every plugin
 * made from the starter.
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 * SPDX-FileCopyrightText: 2026 Marcus Quinn
 * Additional terms (GPL-3.0 section 7(b)): ATTRIBUTION.txt
 *
 * @package WPStarter
 */

if (!defined('ABSPATH') || !defined('WPALLSTARS_SMOKE_PLUGIN')) {
    return;
}

/** Queries of this request made by the tested plugin, by their index in $wpdb->queries. */
$GLOBALS['wpallstars_smoke_own']    = array();
$GLOBALS['wpallstars_smoke_canary'] = false;
$GLOBALS['wpallstars_smoke_off']    = false;

/**
 * Where the requests are recorded.
 *
 * @return string
 */
function wpallstars_smoke_log_file() {
    return WP_CONTENT_DIR . '/smoke-queries.log';
}

/**
 * Whether a file of the tested plugin is in the call stack.
 *
 * @return bool
 */
function wpallstars_smoke_called_by_plugin() {
    $folder = WP_PLUGIN_DIR . '/' . WPALLSTARS_SMOKE_PLUGIN . '/';
    foreach (debug_backtrace(DEBUG_BACKTRACE_IGNORE_ARGS) as $frame) {
        if (isset($frame['file']) && 0 === strpos($frame['file'], $folder)) {
            return true;
        }
    }
    return false;
}

/**
 * Note a query the tested plugin is about to make ('query' filter).
 *
 * @param string $query SQL.
 * @return string The same SQL.
 */
function wpallstars_smoke_record($query) {
    global $wpdb;
    if ($GLOBALS['wpallstars_smoke_off']) {
        return $query;
    }
    if ($GLOBALS['wpallstars_smoke_canary'] || wpallstars_smoke_called_by_plugin()) {
        $index = is_array($wpdb->queries) ? count($wpdb->queries) : 0;

        $GLOBALS['wpallstars_smoke_own'][$index] = array(
            'sql'    => $query,
            'canary' => $GLOBALS['wpallstars_smoke_canary'],
        );
    }
    return $query;
}
add_filter('query', 'wpallstars_smoke_record', PHP_INT_MAX);

/**
 * The canary: a full table scan of the posts table, counted as the plugin's.
 *
 * @return void
 */
function wpallstars_smoke_canary() {
    global $wpdb;
    if (!isset($_GET['smoke-query-canary'])) {
        return;
    }
    $GLOBALS['wpallstars_smoke_canary'] = true;
    $wpdb->get_col("SELECT ID FROM {$wpdb->posts} WHERE post_content LIKE '%smoke-query-canary%'");
    $GLOBALS['wpallstars_smoke_canary'] = false;
}
add_action('init', 'wpallstars_smoke_canary');

/**
 * The WP-CLI command, when it is cron; otherwise an empty string.
 *
 * @return string
 */
function wpallstars_smoke_cli_command() {
    $command = class_exists('WP_CLI') ? WP_CLI::get_runner()->arguments : array();
    $is_cron = isset($command[0]) && 'cron' === $command[0];
    return $is_cron ? 'wp ' . implode(' ', array_slice($command, 0, 3)) : '';
}

/**
 * What this request was: the method and address, or the WP-CLI command.
 * Of WP-CLI's commands only cron runs the plugin's own work; the test's
 * other commands are its set-up, so they get an empty string.
 *
 * @return string
 */
function wpallstars_smoke_request() {
    if (defined('WP_CLI') && WP_CLI) {
        return wpallstars_smoke_cli_command();
    }
    $method = isset($_SERVER['REQUEST_METHOD']) ? (string) $_SERVER['REQUEST_METHOD'] : 'GET';
    $uri    = isset($_SERVER['REQUEST_URI']) ? (string) $_SERVER['REQUEST_URI'] : '/';
    return $method . ' ' . $uri . (is_user_logged_in() ? ' (admin)' : '');
}

/**
 * Record this request: what it was, its query count and time, and the
 * plugin's own queries with their times.
 *
 * @return void
 */
function wpallstars_smoke_write() {
    global $wpdb;
    $where = $GLOBALS['wpallstars_smoke_off'] ? '' : wpallstars_smoke_request();
    if ('' === $where) {
        return;
    }
    $queries = is_array($wpdb->queries) ? $wpdb->queries : array();
    $times   = array_map('floatval', array_column($queries, 1));
    $own     = array();
    foreach ($GLOBALS['wpallstars_smoke_own'] as $index => $query) {
        $query['time'] = isset($times[$index]) ? $times[$index] : 0.0;

        $own[] = $query;
    }
    // Invalid UTF-8 in a query would make json_encode() return false and
    // drop the request; a failed write goes to debug.log, which fails the test.
    $line = json_encode(
        array(
            'where' => $where,
            'count' => count($queries),
            'time'  => array_sum($times),
            'own'   => $own,
        ),
        JSON_INVALID_UTF8_SUBSTITUTE
    );
    if (false === $line || false === file_put_contents(wpallstars_smoke_log_file(), $line . "\n", FILE_APPEND | LOCK_EX)) {
        error_log('smoke-queries: could not record the queries of ' . $where); // phpcs:ignore WordPress.PHP.DevelopmentFunctions.error_log_error_log -- test tool: the debug.log check reports it.
    }
}
add_action('shutdown', 'wpallstars_smoke_write', PHP_INT_MAX);

/**
 * Forget the recorded requests.
 *
 * @return void
 */
function wpallstars_smoke_reset() {
    $GLOBALS['wpallstars_smoke_off'] = true;
    wp_delete_file(wpallstars_smoke_log_file());
}

/**
 * Add $posts published posts with three meta rows each, in one category, in
 * a few queries (WP-CLI's post generate takes minutes for this many).
 *
 * @param int $posts How many posts.
 * @return void
 */
function wpallstars_smoke_seed($posts) {
    global $wpdb;
    $GLOBALS['wpallstars_smoke_off'] = true;

    $posts   = max(1, (int) $posts);
    $digits  = '(SELECT 0 AS d UNION ALL SELECT 1 UNION ALL SELECT 2 UNION ALL SELECT 3 UNION ALL SELECT 4'
        . ' UNION ALL SELECT 5 UNION ALL SELECT 6 UNION ALL SELECT 7 UNION ALL SELECT 8 UNION ALL SELECT 9)';
    $numbers = "SELECT a.d + b.d * 10 + c.d * 100 + d.d * 1000 + e.d * 10000 + f.d * 100000 + 1 AS n
        FROM $digits a, $digits b, $digits c, $digits d, $digits e, $digits f";

    $wpdb->query(
        "INSERT INTO {$wpdb->posts} (post_author, post_date, post_date_gmt, post_content, post_title,
            post_excerpt, post_status, comment_status, ping_status, post_name, to_ping, pinged,
            post_modified, post_modified_gmt, post_content_filtered, post_type, guid)
        SELECT 1, NOW() - INTERVAL n MINUTE, UTC_TIMESTAMP() - INTERVAL n MINUTE,
            CONCAT('Smoke test post ', n, '. Lorem ipsum dolor sit amet, consectetur adipiscing elit.'),
            CONCAT('Smoke test post ', n), '', 'publish', 'open', 'open', CONCAT('smoke-post-', n), '', '',
            NOW() - INTERVAL n MINUTE, UTC_TIMESTAMP() - INTERVAL n MINUTE, '', 'post', ''
        FROM ($numbers) numbers WHERE n <= " . $posts
    );
    $wpdb->query(
        "INSERT INTO {$wpdb->postmeta} (post_id, meta_key, meta_value)
        SELECT p.ID, k.meta_key, CONCAT(k.meta_key, '-', p.ID % 1000)
        FROM {$wpdb->posts} p,
            (SELECT '_smoke_a' AS meta_key UNION ALL SELECT '_smoke_b' UNION ALL SELECT 'smoke_value') k
        WHERE p.post_name LIKE 'smoke-post-%'"
    );
    $category = get_term((int) get_option('default_category'), 'category');
    if ($category instanceof WP_Term) {
        $wpdb->query(
            $wpdb->prepare(
                "INSERT IGNORE INTO {$wpdb->term_relationships} (object_id, term_taxonomy_id)
                SELECT ID, %d FROM {$wpdb->posts} WHERE post_name LIKE 'smoke-post-%%'",
                $category->term_taxonomy_id
            )
        );
        wp_update_term_count_now(array($category->term_taxonomy_id), 'category');
    }
    wp_cache_flush();
    printf(
        "Seeded %d posts and %d meta rows.\n",
        (int) $wpdb->get_var("SELECT COUNT(*) FROM {$wpdb->posts} WHERE post_type = 'post'"),
        (int) $wpdb->get_var("SELECT COUNT(*) FROM {$wpdb->postmeta}")
    );
}

/**
 * What is wrong with one step of an EXPLAIN plan, if anything.
 *
 * @param array<string,mixed> $step One row of EXPLAIN.
 * @param int                 $rows Rows from which a scan or sort counts.
 * @return string[]
 */
function wpallstars_smoke_step_problems(array $step, $rows) {
    $step     = array_merge(array('rows' => 0, 'table' => '', 'type' => '', 'Extra' => ''), $step);
    $count    = (int) $step['rows'];
    $table    = (string) $step['table'];
    $type     = (string) $step['type']; // NULL for steps that read no table.
    $scans    = array(
        'ALL'   => 'full table scan',
        'index' => 'full index scan',
    );
    $problems = array();
    if ($count >= $rows && isset($scans[$type])) {
        $problems[] = sprintf('%s of %s (%d rows)', $scans[$type], $table, $count);
    }
    if ($count >= $rows && false !== strpos((string) $step['Extra'], 'Using filesort')) {
        $problems[] = sprintf('sort of %d rows of %s without an index', $count, $table);
    }
    return $problems;
}

/**
 * What EXPLAIN says is wrong with one query, if anything.
 *
 * @param string $sql  The query.
 * @param int    $rows Rows from which a scan or sort counts.
 * @return string[]|null Problems, or null when the query cannot be explained.
 */
function wpallstars_smoke_explain($sql, $rows) {
    global $wpdb;
    $suppress = $wpdb->suppress_errors(true);
    $plan     = $wpdb->get_results('EXPLAIN ' . $sql, ARRAY_A); // The query as the plugin made it.
    $wpdb->suppress_errors($suppress);
    if (!is_array($plan) || '' !== $wpdb->last_error) {
        return null;
    }
    $problems = array();
    foreach ($plan as $step) {
        $problems = array_merge($problems, wpallstars_smoke_step_problems($step, $rows));
    }
    return $problems;
}

/**
 * Add one request's own queries to $own, each SQL once with its calls and
 * total time.
 *
 * @param array<string,array{sql:string,canary:bool,calls:int,time:float}> $own     The queries so far.
 * @param array<int,array{sql:string,canary:bool,time:float}>               $queries One request's.
 * @return array<string,array{sql:string,canary:bool,calls:int,time:float}>
 */
function wpallstars_smoke_add_queries(array $own, array $queries) {
    foreach ($queries as $query) {
        $sql = $query['sql'];
        if (!isset($own[$sql])) {
            $own[$sql] = array('sql' => $sql, 'canary' => $query['canary'], 'calls' => 0, 'time' => 0.0);
        }
        ++$own[$sql]['calls'];
        $own[$sql]['time'] += $query['time'];
    }
    return $own;
}

/**
 * Read the recorded requests, print one line for each, and return the
 * plugin's own queries, each once with its calls and total time, slowest
 * first.
 *
 * @return array<string,array{sql:string,canary:bool,calls:int,time:float}>
 */
function wpallstars_smoke_requests() {
    $file  = wpallstars_smoke_log_file();
    $lines = file_exists($file) ? (array) file($file, FILE_IGNORE_NEW_LINES | FILE_SKIP_EMPTY_LINES) : array();
    $own   = array();
    echo "  queries     ms  own   own ms  request\n";
    foreach ($lines as $line) {
        $request = array_merge(
            array('where' => '', 'count' => 0, 'time' => 0.0, 'own' => array()),
            (array) json_decode($line, true)
        );
        $own     = wpallstars_smoke_add_queries($own, (array) $request['own']);
        printf(
            "  %7d %6.1f %4d %8.1f  %s\n",
            $request['count'],
            $request['time'] * 1000,
            count($request['own']),
            array_sum(array_column($request['own'], 'time')) * 1000,
            $request['where']
        );
    }
    uasort(
        $own,
        static function ($a, $b) {
            return $b['time'] <=> $a['time'];
        }
    );
    return $own;
}

/**
 * Print one of the plugin's own queries with what EXPLAIN found.
 *
 * @param array{sql:string,calls:int,time:float} $query    The query.
 * @param string[]|null                          $problems From wpallstars_smoke_explain().
 * @return void
 */
function wpallstars_smoke_print_query(array $query, $problems) {
    $verdict = 'ok';
    if (null === $problems) {
        $verdict = 'not checked (EXPLAIN cannot read it)';
    } elseif ($problems) {
        $verdict = 'FAIL ' . implode('; ', $problems);
    }
    $sql = preg_replace('/\s+/', ' ', trim($query['sql']));
    $sql = strlen($sql) > 160 ? substr($sql, 0, 157) . '...' : $sql;
    printf("  %s: %dx, %.1f ms: %s\n", $verdict, $query['calls'], $query['time'] * 1000, $sql);
}

/**
 * List the recorded requests, then check the plugin's own queries with
 * EXPLAIN. Prints "queries: ok" or "queries: failed" last.
 *
 * @param int $rows Rows from which a scan or sort fails.
 * @return void
 */
function wpallstars_smoke_report($rows) {
    $GLOBALS['wpallstars_smoke_off'] = true;

    $failed = false;
    $canary = false;
    $mine   = 0;
    foreach (wpallstars_smoke_requests() as $query) {
        $problems = wpallstars_smoke_explain($query['sql'], $rows);
        if ($query['canary']) {
            $canary = !empty($problems);
            continue;
        }
        ++$mine;
        $failed = $failed || !empty($problems);
        wpallstars_smoke_print_query($query, $problems);
    }
    printf("  The plugin's own queries: %d different, slowest first (EXPLAIN, %d rows or more fail).\n", $mine, $rows);
    if (0 === $mine) {
        // The canary proves EXPLAIN works, not that queries are traced to the
        // plugin: a plugin that makes queries should show some here.
        printf("  Note: no query was traced to wp-content/plugins/%s (WPALLSTARS_SMOKE_PLUGIN); fine if the plugin makes none.\n", WPALLSTARS_SMOKE_PLUGIN);
    }
    if (!$canary) {
        echo "  FAIL the canary query's full table scan was not found: the check does not work\n";
        $failed = true;
    }
    echo $failed ? "queries: failed\n" : "queries: ok\n";
}
