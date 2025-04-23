<?php
/**
 * Plugin Name: Multisite Setup Helper
 * Description: Helper plugin to set up multisite testing environment
 * Version: 1.0.0
 * Author: WPALLSTARS
 * License: GPL-2.0-or-later
 *
 * @package WP_Plugin_Starter_Template_For_AI_Coding
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

/**
 * Helper function to check if we're in a multisite environment.
 *
 * @return bool True if multisite is enabled, false otherwise.
 */
function wpst_is_multisite() {
    return defined( 'MULTISITE' ) && MULTISITE;
}

/**
 * Helper function to get all sites in the network.
 *
 * @return array Array of site objects.
 */
function wpst_get_network_sites() {
    if ( ! wpst_is_multisite() ) {
        return array();
    }

    return get_sites( array( 'public' => 1 ) );
}

// Add a filter to enable multisite testing in PHPUnit.
add_filter( 'wpst_is_multisite_compatible', '__return_true' );
