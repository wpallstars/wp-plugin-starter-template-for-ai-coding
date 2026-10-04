<?php
/**
 * Read Me content for the WP Plugin Starter admin tab (from README.md).
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

/**
 * README.md contents, with a short fallback if the file is missing.
 *
 * @return array{title:string,content:string}
 */
function wpstarter_get_readme_content() {
    $readme_path = WPSTARTER_DIR . 'README.md';

    if (is_readable($readme_path)) {
        $content = (string) file_get_contents($readme_path); // phpcs:ignore WordPress.WP.AlternativeFunctions.file_get_contents_file_get_contents -- local file.
    } else {
        $content = "# WP Plugin Starter\n\nVersion: " . WPSTARTER_VERSION;
    }

    return array(
        'title'   => __('Read Me', 'wp-plugin-starter-template'),
        'content' => $content,
    );
}
