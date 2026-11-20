<?php
/**
 * The shop side of scripts/shop-release.sh, run on the shop's WordPress
 * (FluentCart Pro, wpallstars.com) with WP-CLI:
 *
 *   wp eval-file shop-release-remote.php plan  ITEM TITLE SLUG ZIP SHA256 CHANGELOG BACKUP_DIR
 *   wp eval-file shop-release-remote.php apply ITEM TITLE SLUG ZIP SHA256 CHANGELOG BACKUP_DIR
 *   wp eval-file shop-release-remote.php check ITEM SLUG
 *
 * plan shows what a release would change and changes nothing. plan and
 * apply need product ITEM titled TITLE with licence settings on and exactly
 * one locally stored download row, and a zip named SLUG-X.Y.Z.zip whose
 * X.Y.Z is newer than the product's licence version. apply writes a JSON
 * backup (mode 600) of the download row and the two meta rows it changes (on a
 * first release it records which were absent and, after writing, the IDs of
 * the rows it inserted: roll back by deleting those and restoring the rest),
 * copies the zip into FluentCart's storage beside the old one (kept for a
 * rollback), points the download row at it, sets the licence version and
 * the update changelog (the version's section of CHANGELOG, a changelog.txt
 * or readme.txt, without its "Developers:" lines), touches the product, then
 * reads it all back and fails, naming the backup, when anything differs.
 *
 * check runs on a site with a valid licence for ITEM (the shared licence
 * library, includes/wpallstars-licence/): it asks the shop again, downloads
 * the offered package to a temporary file and prints its version, size,
 * SHA-256, entry count and main-file Version:, never its signed address.
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 * SPDX-FileCopyrightText: 2026 Marcus Quinn
 * Additional terms (GPL-3.0 section 7(b)): ATTRIBUTION.txt
 * Provenance: wpas-e4502af0f07e8a92. Copies, even of part, keep these lines.
 *
 * @package WPStarter
 */

// phpcs:disable WordPress.NamingConventions.PrefixAllGlobals -- A WP-CLI eval-file script run on the shop, never loaded by the plugin.

if (!defined('ABSPATH') || !defined('WP_CLI') || !WP_CLI) {
    exit(1);
}

/**
 * Stop with a message.
 *
 * @param string $message Why.
 * @return never
 */
function wpas_shop_fail($message) {
    WP_CLI::error($message);
    exit(1);
}

/**
 * One meta row of the product.
 *
 * @param int    $item Product ID.
 * @param string $key  Meta key.
 * @return array<string,mixed>|null
 */
function wpas_shop_meta_row($item, $key) {
    global $wpdb;
    $row = $wpdb->get_row($wpdb->prepare("SELECT * FROM {$wpdb->prefix}fct_product_meta WHERE object_id = %d AND meta_key = %s ORDER BY id LIMIT 1", $item, $key), ARRAY_A);
    return is_array($row) ? $row : null;
}

/**
 * The product's licence settings, decoded.
 *
 * @param int $item Product ID.
 * @return array<string,mixed>|null
 */
function wpas_shop_settings($item) {
    $row      = wpas_shop_meta_row($item, 'license_settings');
    $settings = $row ? json_decode((string) $row['meta_value'], true) : null;
    return is_array($settings) ? $settings : null;
}

/**
 * The version's section of a changelog, as HTML for the update details.
 *
 * @param string $file    changelog.txt or readme.txt.
 * @param string $version X.Y.Z.
 * @return string
 */
function wpas_shop_changelog_html($file, $version) {
    $text = (string) file_get_contents($file); // phpcs:ignore WordPress.WP.AlternativeFunctions.file_get_contents_file_get_contents -- a local file sent by the release script.
    if (!preg_match('/^= ' . preg_quote($version, '/') . '(?: [^=\n]*)? =\s*$(.*?)(?=^=|\z)/ms', $text, $m)) {
        wpas_shop_fail("The changelog has no = $version = section.");
    }
    $items = array();
    foreach (preg_split('/^\* /m', trim($m[1])) as $line) {
        $line = trim((string) preg_replace('/\s+/', ' ', $line));
        if ('' !== $line && 0 !== strpos($line, 'Developers:')) {
            $items[] = '<li>' . esc_html($line) . '</li>';
        }
    }
    if (!$items) {
        $items[] = '<li>Maintenance release.</li>';
    }
    return '<h4>' . esc_html($version) . '</h4><ul>' . implode('', $items) . '</ul>';
}

/**
 * The release's facts, checked: product, download row, versions, file names.
 *
 * @param array<int,string> $args The command's arguments after the mode.
 * @return array<string,mixed>
 */
function wpas_shop_plan(array $args) {
    if (7 !== count($args)) {
        wpas_shop_fail('Usage: plan|apply ITEM TITLE SLUG ZIP SHA256 CHANGELOG BACKUP_DIR');
    }
    list($item, $title, $slug, $zip, $sha, $changelog, $backup_dir) = $args;
    $item = (int) $item;
    if (!preg_match('/^' . preg_quote($slug, '/') . '-(\d+\.\d+\.\d+)\.zip$/', basename($zip), $m)) {
        wpas_shop_fail("The zip must be named $slug-X.Y.Z.zip, not " . basename($zip) . '.');
    }
    $version = $m[1];
    if (!is_file($zip) || !preg_match('/^[0-9a-f]{64}$/', $sha) || hash_file('sha256', $zip) !== $sha) {
        wpas_shop_fail('The zip on the host is missing or its SHA-256 is not the build\'s.');
    }
    if (!is_file($changelog)) {
        wpas_shop_fail('The changelog is missing on the host.');
    }
    $post = get_post($item);
    if (!$post || $post->post_title !== $title) {
        wpas_shop_fail("Product $item is not \"$title\".");
    }
    $settings = wpas_shop_settings($item);
    if (!$settings || !isset($settings['enabled']) || 'yes' !== $settings['enabled']) {
        wpas_shop_fail('The product\'s licence settings are missing or not enabled.');
    }
    $current = isset($settings['version']) ? (string) $settings['version'] : '';
    if ('' !== $current && !version_compare($version, $current, '>')) {
        wpas_shop_fail("$version is not newer than the product's licence version ($current).");
    }
    global $wpdb;
    $downloads = $wpdb->get_results($wpdb->prepare("SELECT * FROM {$wpdb->prefix}fct_product_downloads WHERE post_id = %d", $item), ARRAY_A);
    if (!is_array($downloads) || '' !== $wpdb->last_error) {
        // A failed lookup is not "no rows": never treat it as a first release.
        wpas_shop_fail('Cannot read the product\'s download rows: ' . $wpdb->last_error);
    }
    $count     = count($downloads);
    $uploads   = wp_upload_dir(null, false);
    $dir       = trailingslashit($uploads['basedir']) . 'fluent-cart';
    if (0 === $count && '' === $current) {
        // The product's first release: apply adds its one download row, for
        // every variation, in FluentCart's storage (which must exist).
        $variations = $wpdb->get_col($wpdb->prepare("SELECT id FROM {$wpdb->prefix}fct_product_variations WHERE post_id = %d ORDER BY id", $item));
        if (!$variations) {
            wpas_shop_fail('The product has no variations, so a download row would serve nobody.');
        }
        if (!is_dir($dir)) {
            wpas_shop_fail('FluentCart\'s storage folder (uploads/fluent-cart) is missing; stopping rather than guessing it.');
        }
        $download = array('id' => 0, 'file_path' => '', 'variations' => array_map('intval', $variations));
    } else {
        if (1 !== $count) {
            wpas_shop_fail("The product must have exactly one download row; it has $count.");
        }
        $download = $downloads[0];
        if ('local' !== $download['driver']) {
            wpas_shop_fail('The download row is not stored locally (driver ' . $download['driver'] . ').');
        }
        if (!is_file($dir . '/' . $download['file_path'])) {
            wpas_shop_fail('The current download file is not in FluentCart\'s storage; stopping rather than guessing the folder.');
        }
    }
    $file = basename($zip) . '__fluent-cart__.' . substr($sha, 0, 32) . '.zip';
    $reuse = false;
    if (is_file($dir . '/' . $file)) {
        // A failed apply can leave its copied ZIP behind. The same bytes that
        // no download row references are that leftover: reuse it. Anything
        // else (other bytes, or a file a row serves) is never touched.
        $refs = $wpdb->get_var($wpdb->prepare("SELECT COUNT(*) FROM {$wpdb->prefix}fct_product_downloads WHERE file_path = %s", $file));
        if ('' !== $wpdb->last_error || null === $refs) {
            wpas_shop_fail('Cannot check whether ' . $file . ' is in use: ' . $wpdb->last_error);
        }
        if (0 !== (int) $refs || hash_file('sha256', $dir . '/' . $file) !== $sha) {
            wpas_shop_fail("$file is already in FluentCart's storage and is not an unreferenced copy of this ZIP; stopping rather than overwriting it.");
        }
        $reuse = true;
    }
    return array(
        'item'         => $item,
        'title'        => $title,
        'version'      => $version,
        'current'      => $current,
        'zip'          => $zip,
        'sha'          => $sha,
        'size'         => (int) filesize($zip),
        'dir'          => $dir,
        'old_file'     => (string) $download['file_path'],
        'file'         => $file,
        'reuse'        => $reuse,
        'download'     => $download,
        'settings_row' => wpas_shop_meta_row($item, 'license_settings'),
        'settings'     => $settings,
        'log_row'      => wpas_shop_meta_row($item, '_fluent_sl_changelog'),
        'changelog'    => wpas_shop_changelog_html($changelog, $version),
        'backup_dir'   => $backup_dir,
    );
}

/**
 * Write the backup of everything apply changes (mode 600).
 *
 * @param array<string,mixed> $plan The release's facts.
 * @return string The backup's path.
 */
function wpas_shop_backup(array $plan) {
    if (!wp_mkdir_p($plan['backup_dir'])) {
        wpas_shop_fail('Cannot create the backup folder.');
    }
    $backup = trailingslashit($plan['backup_dir']) . 'shop-release-' . $plan['item'] . '-' . $plan['current'] . '-to-' . $plan['version'] . '-' . gmdate('Ymd\THis\Z') . '.json';
    $old    = umask(077);
    $saved  = file_put_contents($backup, wp_json_encode(array( // phpcs:ignore WordPress.WP.AlternativeFunctions.file_system_operations_file_put_contents -- a private backup on the shop's host.
        'product_id'       => $plan['item'],
        'download'         => $plan['download'],
        'license_settings' => $plan['settings_row'],
        'changelog'        => $plan['log_row'],
        // A first release has no row to restore: apply inserts them. Rollback:
        // delete the rows named in "inserted" (filled in after apply writes),
        // and restore by ID only the rows that were not absent.
        'absent'           => array(
            'download'  => 0 === (int) $plan['download']['id'],
            'changelog' => !$plan['log_row'],
        ),
        'inserted'         => array('download_id' => null, 'changelog_row_id' => null),
    ), JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES));
    umask($old);
    if (false === $saved) {
        wpas_shop_fail('Cannot write the backup; nothing changed.');
    }
    WP_CLI::log('Backup: ' . $backup);
    return $backup;
}

/**
 * Record in the backup the IDs of the rows apply inserted, so a rollback can
 * delete them.
 *
 * @param string             $backup   The backup's path.
 * @param array<string,?int> $inserted download_id and changelog_row_id.
 */
function wpas_shop_backup_inserted($backup, array $inserted) {
    $data = json_decode((string) file_get_contents($backup), true); // phpcs:ignore WordPress.WP.AlternativeFunctions.file_get_contents_file_get_contents -- the private backup just written.
    if (!is_array($data)) {
        wpas_shop_fail('Cannot read the backup back to record the inserted rows: ' . $backup);
    }
    $data['inserted'] = $inserted;
    if (false === file_put_contents($backup, wp_json_encode($data, JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES))) { // phpcs:ignore WordPress.WP.AlternativeFunctions.file_system_operations_file_put_contents -- as above.
        wpas_shop_fail('Cannot record the inserted rows in the backup: ' . $backup);
    }
}

/**
 * Point the download row at the new file and set the licence version,
 * changelog and product time.
 *
 * Every completed write is undone when a later one fails, so the licence
 * version and changelog never advance without the download.
 *
 * @param array<string,mixed> $plan     The release's facts.
 * @param string              $error    Set to the first failure's description.
 * @param array<string,?int>  $inserted Set to the IDs of the rows inserted.
 * @return int The download row's ID, or 0 when a write failed (all undone).
 */
function wpas_shop_write(array $plan, &$error = '', array &$inserted = array()) {
    global $wpdb;
    $now                 = current_time('mysql');
    $meta                = $wpdb->prefix . 'fct_product_meta';
    $settings            = $plan['settings'];
    $settings['version'] = $plan['version'];
    $log                 = $plan['log_row'] ? (string) $plan['log_row']['meta_value'] : '';
    $log                 = false === strpos($log, '<h4>' . $plan['version'] . '</h4>') ? $plan['changelog'] . $log : $log;
    $file                = array(
        'title'      => $plan['title'] . ' ' . $plan['version'],
        'file_name'  => $plan['file'],
        'file_path'  => $plan['file'],
        'file_url'   => $plan['file'],
        'file_size'  => (string) $plan['size'],
        'updated_at' => $now,
    );
    $id                  = (int) $plan['download']['id'];
    $downloads           = $wpdb->prefix . 'fct_product_downloads';
    $undo                = array();
    $fail                = static function ($what) use (&$error, &$undo, $wpdb, $plan) {
        // Keep the first database error: the undo queries replace last_error.
        $error = $what . ('' !== $wpdb->last_error ? ': ' . $wpdb->last_error : '');
        foreach (array_reverse($undo) as $restore) {
            $restore();
        }
        clean_post_cache($plan['item']);
        return 0;
    };
    if (0 === $id) {
        // First release: the row FluentCart's product editor would add.
        $added = $wpdb->insert($downloads, $file + array(
            'post_id'              => $plan['item'],
            'product_variation_id' => wp_json_encode($plan['download']['variations']),
            'download_identifier'  => wp_generate_uuid4(),
            'type'                 => 'zip',
            'driver'               => 'local',
            'settings'             => wp_json_encode(array('download_limit' => '', 'download_expiry' => '', 'bucket' => '')),
            'serial'               => 1,
            'created_at'           => $now,
        ));
        if (!$added) {
            return $fail('The download row could not be added');
        }
        $id                      = (int) $wpdb->insert_id;
        $inserted['download_id'] = $id;
        $undo[]                  = static function () use ($wpdb, $downloads, $id) {
            $wpdb->delete($downloads, array('id' => $id));
        };
    } else {
        $old = array_intersect_key($plan['download'], $file);
        if (false === $wpdb->update($downloads, $file, array('id' => $id))) {
            return $fail('The download row could not be updated');
        }
        $undo[] = static function () use ($wpdb, $downloads, $id, $old) {
            $wpdb->update($downloads, $old, array('id' => $id));
        };
    }
    // The licence version and changelog advance only after the download row did.
    $old_settings = $plan['settings_row'];
    if (false === $wpdb->update($meta, array('meta_value' => wp_json_encode($settings, JSON_UNESCAPED_SLASHES), 'updated_at' => $now), array('id' => (int) $old_settings['id']))) { // phpcs:ignore WordPress.DB.SlowDBQuery.slow_db_query_meta_value -- FluentCart's own table, by primary key.
        return $fail('The licence settings could not be updated');
    }
    $undo[] = static function () use ($wpdb, $meta, $old_settings) {
        $wpdb->update($meta, array('meta_value' => $old_settings['meta_value'], 'updated_at' => isset($old_settings['updated_at']) ? $old_settings['updated_at'] : current_time('mysql')), array('id' => (int) $old_settings['id'])); // phpcs:ignore WordPress.DB.SlowDBQuery.slow_db_query_meta_value -- as above.
    };
    if ($plan['log_row']) {
        $old_log = $plan['log_row'];
        if (false === $wpdb->update($meta, array('meta_value' => $log, 'updated_at' => $now), array('id' => (int) $old_log['id']))) { // phpcs:ignore WordPress.DB.SlowDBQuery.slow_db_query_meta_value -- as above.
            return $fail('The changelog could not be updated');
        }
        $undo[] = static function () use ($wpdb, $meta, $old_log) {
            $wpdb->update($meta, array('meta_value' => $old_log['meta_value'], 'updated_at' => isset($old_log['updated_at']) ? $old_log['updated_at'] : current_time('mysql')), array('id' => (int) $old_log['id'])); // phpcs:ignore WordPress.DB.SlowDBQuery.slow_db_query_meta_value -- as above.
        };
    } elseif (!$wpdb->insert($meta, array('object_id' => $plan['item'], 'object_type' => $plan['settings_row']['object_type'], 'meta_key' => '_fluent_sl_changelog', 'meta_value' => $log, 'created_at' => $now, 'updated_at' => $now))) { // phpcs:ignore WordPress.DB.SlowDBQuery -- as above.
        return $fail('The changelog could not be added');
    } else {
        $log_id                       = (int) $wpdb->insert_id;
        $inserted['changelog_row_id'] = $log_id;
        $undo[]                       = static function () use ($wpdb, $meta, $log_id) {
            $wpdb->delete($meta, array('id' => $log_id));
        };
    }
    if (false === $wpdb->update($wpdb->posts, array('post_modified' => $now, 'post_modified_gmt' => current_time('mysql', true)), array('ID' => $plan['item']))) {
        return $fail('The product time could not be updated');
    }
    clean_post_cache($plan['item']);
    return $id;
}

/**
 * Publish the release, then read it back.
 *
 * @param array<string,mixed> $plan The release's facts.
 */
function wpas_shop_apply(array $plan) {
    global $wpdb;
    $backup = wpas_shop_backup($plan);
    if (empty($plan['reuse']) && !copy($plan['zip'], $plan['dir'] . '/' . $plan['file'])) {
        wpas_shop_fail('Cannot copy the zip into FluentCart\'s storage; nothing else changed. Backup: ' . $backup);
    }
    $error    = '';
    $inserted = array('download_id' => null, 'changelog_row_id' => null);
    $id       = wpas_shop_write($plan, $error, $inserted);
    if (0 === $id) {
        wpas_shop_fail('A database update failed (completed writes were undone): ' . $error . '. Backup: ' . $backup);
    }
    // Writes succeeded: name the rows they inserted in the backup, for a rollback.
    if (null !== $inserted['download_id'] || null !== $inserted['changelog_row_id']) {
        wpas_shop_backup_inserted($backup, $inserted);
        WP_CLI::log('Rows inserted (delete on rollback): download ' . (int) $inserted['download_id'] . ', changelog ' . (int) $inserted['changelog_row_id'] . '.');
    }
    $row      = $wpdb->get_row($wpdb->prepare("SELECT * FROM {$wpdb->prefix}fct_product_downloads WHERE id = %d", $id), ARRAY_A);
    $settings = wpas_shop_settings($plan['item']);
    $log      = wpas_shop_meta_row($plan['item'], '_fluent_sl_changelog');
    $target   = $plan['dir'] . '/' . $plan['file'];
    $checks   = array(
        'the download row does not point at the new file'      => is_array($row) && $row['file_path'] === $plan['file'],
        'the licence version is not ' . $plan['version']       => $settings && isset($settings['version']) && $settings['version'] === $plan['version'],
        'the stored file\'s SHA-256 is not the build\'s'       => is_file($target) && hash_file('sha256', $target) === $plan['sha'],
        'the update changelog has no ' . $plan['version'] . ' section' => $log && false !== strpos((string) $log['meta_value'], '<h4>' . $plan['version'] . '</h4>'),
    );
    $problems = array_keys(array_filter($checks, static function ($ok) {
        return !$ok;
    }));
    if ($problems) {
        wpas_shop_fail('Read back failed: ' . implode('; ', $problems) . '. Restore from the backup: ' . $backup);
    }
    WP_CLI::success(sprintf('Published %s %s (product %d): file %s, SHA-256 %s. The old file %s stays for a rollback.', $plan['title'], $plan['version'], $plan['item'], $plan['file'], $plan['sha'], $plan['old_file']));
}

/**
 * On a licensed site: what the shop offers now, downloaded and checked.
 *
 * @param array<int,string> $args ITEM SLUG.
 */
function wpas_shop_check(array $args) {
    if (2 !== count($args)) {
        wpas_shop_fail('Usage: check ITEM SLUG');
    }
    $item = (int) $args[0];
    $slug = (string) $args[1];
    if (!class_exists('WPAllStars_Licence') || !WPAllStars_Licence::valid($item)) {
        wpas_shop_fail("This site has no valid licence for product $item.");
    }
    $products = WPAllStars_Licence::products();
    if (!isset($products[$item]) || $products[$item]['slug'] !== $slug) {
        wpas_shop_fail("Product $item is not $slug here.");
    }
    $product = $products[$item];
    if (!defined('DOING_CRON')) {
        define('DOING_CRON', true); // Some request managers hold back outbound requests outside cron.
    }
    require_once ABSPATH . 'wp-admin/includes/plugin.php';
    require_once ABSPATH . 'wp-admin/includes/file.php';
    require_once ABSPATH . 'wp-includes/update.php';
    delete_site_transient(WPAllStars_Licence::UPDATE_CACHE . $item);
    $theme     = 'theme' === $product['type'];
    $transient = $theme ? 'update_themes' : 'update_plugins';
    delete_site_transient($transient);
    if ($theme) {
        wp_update_themes();
    } else {
        wp_update_plugins();
    }
    $state = get_site_transient($transient);
    $offer = null;
    foreach (array('response' => true, 'no_update' => false) as $list => $pending) {
        $items = is_object($state) && isset($state->$list) ? (array) $state->$list : array();
        if (isset($items[$product['file']]) && !empty(((array) $items[$product['file']])['package'])) {
            $offer = array('entry' => (array) $items[$product['file']], 'pending' => $pending);
            break;
        }
    }
    if (null === $offer) {
        wpas_shop_fail('The shop offered no package (no answer, or no licence for updates).');
    }
    $offered = isset($offer['entry']['new_version']) ? (string) $offer['entry']['new_version'] : '';
    $file    = download_url((string) $offer['entry']['package'], 300);
    if (is_wp_error($file)) {
        wpas_shop_fail('The offered package did not download: ' . $file->get_error_message());
    }
    $entries = 0;
    $version = '';
    if (class_exists('ZipArchive')) {
        $archive = new ZipArchive();
        if (true === $archive->open($file)) {
            $entries = $archive->numFiles;
            $main    = $archive->getFromName($slug . '/' . ($theme ? 'style.css' : $slug . '.php'));
            if (is_string($main) && preg_match('/^[ \t\/*#@]*Version:\s*(\S+)/mi', $main, $m)) {
                $version = $m[1];
            }
            $archive->close();
        }
    }
    WP_CLI::log(sprintf('Installed: %s', $product['version']));
    WP_CLI::log(sprintf('Offered:   %s (%s)', '' !== $offered ? $offered : '?', $offer['pending'] ? 'update available' : 'up to date'));
    WP_CLI::log(sprintf('Package:   %d bytes, SHA-256 %s, %d entries, main file Version: %s', (int) filesize($file), hash_file('sha256', $file), $entries, '' !== $version ? $version : '?'));
    wp_delete_file($file);
    if ('' === $version || $version !== $offered) {
        wpas_shop_fail('The package\'s main-file Version: is not the offered version.');
    }
    WP_CLI::success('The offered package matches the offered version.');
}

$wpas_shop_args = isset($args) && is_array($args) ? array_values($args) : array();
$wpas_shop_mode = $wpas_shop_args ? (string) array_shift($wpas_shop_args) : '';
if ('check' === $wpas_shop_mode) {
    wpas_shop_check($wpas_shop_args);
} elseif ('plan' === $wpas_shop_mode || 'apply' === $wpas_shop_mode) {
    $wpas_shop_plan = wpas_shop_plan($wpas_shop_args);
    WP_CLI::log(sprintf('Product %d "%s": licence version %s -> %s', $wpas_shop_plan['item'], $wpas_shop_plan['title'], '' !== $wpas_shop_plan['current'] ? $wpas_shop_plan['current'] : '(none)', $wpas_shop_plan['version']));
    WP_CLI::log(sprintf('Download row %d: %s -> %s (%d bytes, SHA-256 %s)', $wpas_shop_plan['download']['id'], $wpas_shop_plan['old_file'], $wpas_shop_plan['file'], $wpas_shop_plan['size'], $wpas_shop_plan['sha']));
    WP_CLI::log('Update changelog adds: ' . wp_strip_all_tags(str_replace(array('</li>', '</h4>'), array(' | ', ': '), $wpas_shop_plan['changelog'])));
    if ('apply' === $wpas_shop_mode) {
        wpas_shop_apply($wpas_shop_plan);
    } else {
        WP_CLI::log('Dry run: nothing changed. Add --apply to publish.');
    }
} else {
    wpas_shop_fail('Usage: wp eval-file shop-release-remote.php plan|apply ITEM TITLE SLUG ZIP SHA256 CHANGELOG BACKUP_DIR, or check ITEM SLUG');
}
