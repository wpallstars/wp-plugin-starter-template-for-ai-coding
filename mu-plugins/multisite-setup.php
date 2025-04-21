<?php
/**
 * Plugin Name: Multisite Setup Helper
 * Description: Helper plugin to set up multisite testing environment
 * Version: 1.0.0
 * Author: WPALLSTARS
 * License: GPL-2.0-or-later
 */

// Exit if accessed directly.
if ( ! defined( 'ABSPATH' ) ) {
    exit;
}

/**
 * Add a filter to allow subdirectory multisite on localhost
 */
add_filter( 'allow_subdirectory_install', '__return_true' );

/**
 * Add a filter to skip domain verification for multisite
 */
add_filter( 'multisite_domain_check', '__return_true' );

/**
 * Add a filter to allow wildcard subdomains
 */
add_filter( 'wp_is_large_network', '__return_false' );

/**
 * Add a filter to allow domain mapping
 */
add_filter( 'domain_mapping_warning', '__return_false' );
