# Multisite Development

This guide explains how to extend the WordPress Plugin Starter Template for multisite environments.

## Overview

WordPress Multisite allows you to run multiple WordPress sites from a single WordPress installation. The plugin template includes a basic structure for multisite-specific functionality that you can extend to add features for multisite environments.

## Directory Structure

The plugin includes a dedicated directory for multisite-specific functionality:

```text
includes/
└── Multisite/
    ├── class-multisite.php    # Base class for multisite functionality
    └── README.md              # Documentation for multisite development
```

## Getting Started

### 1. Understand the Base Class

The `Multisite` class in `includes/Multisite/class-multisite.php` provides a foundation for multisite-specific functionality. It includes:

* A constructor for initialization
* Example methods for multisite functionality

### 2. Load Multisite Classes

To use multisite-specific functionality, you need to load and initialize the classes in your main plugin file:

```php
// Load multisite support classes if in multisite environment
if ( is_multisite() ) {
    require_once WP_PLUGIN_STARTER_TEMPLATE_PATH . 'includes/Multisite/class-multisite.php';

    // Initialize multisite support
    $multisite = new WPALLSTARS\PluginStarterTemplate\Multisite\Multisite();
}
```

### 3. Extend the Base Class

You can extend the base `Multisite` class or create additional classes in the `Multisite` directory to implement specific features:

```php
<?php
namespace WPALLSTARS\PluginStarterTemplate\Multisite;

class Domain_Mapping extends Multisite {

    public function __construct() {
        parent::__construct();

        // Add hooks for domain mapping functionality
        add_action( 'init', array( $this, 'register_domain_mapping' ) );
    }

    public function register_domain_mapping() {
        // Implement domain mapping functionality
    }
}
```

## Common Multisite Features

Here are some common features you might want to implement for multisite environments:

### Network Admin Pages

To add pages to the network admin menu:

```php
add_action( 'network_admin_menu', array( $this, 'add_network_menu' ) );

public function add_network_menu() {
    add_submenu_page(
        'settings.php',
        __( 'Plugin Settings', 'your-text-domain' ),
        __( 'Plugin Settings', 'your-text-domain' ),
        'manage_network_options',
        'your-plugin-slug',
        array( $this, 'render_network_settings' )
    );
}
```

### Site Creation Hooks

To perform actions when a new site is created:

```php
add_action( 'wp_initialize_site', array( $this, 'on_site_creation' ), 10, 2 );

public function on_site_creation( $new_site, $args ) {
    // Get the blog ID
    $blog_id = $new_site->blog_id;

    // Switch to the new blog
    switch_to_blog( $blog_id );

    // Perform site-specific setup
    update_option( 'your_plugin_option', 'default_value' );

    // Restore the current blog
    restore_current_blog();
}
```

### Network Settings

To save network-wide settings:

```php
// Process network settings form
add_action( 'network_admin_edit_your_plugin_action', array( $this, 'save_network_settings' ) );

public function save_network_settings() {
    // Check nonce
    check_admin_referer( 'your_plugin_nonce' );

    // Save settings
    update_site_option( 'your_plugin_network_option', sanitize_text_field( $_POST['your_option'] ) );

    // Redirect back to settings page
    wp_redirect( add_query_arg( array(
        'page' => 'your-plugin-slug',
        'updated' => 'true'
    ), network_admin_url( 'settings.php' ) ) );
    exit;
}
```

## Testing Multisite Functionality

To test your multisite functionality, use the testing framework included in the plugin template:

```bash
# Set up multisite environment
npm run setup:multisite

# Run tests
npm run test:multisite
```

For more details on testing, see the [Testing Framework](Testing-Framework.md) documentation.

## Best Practices

1. **Always Check for Multisite**: Use `is_multisite()` to check if the current installation is a multisite network before loading multisite-specific functionality.

2. **Use Network-Specific Functions**: WordPress provides specific functions for multisite, such as `update_site_option()` instead of `update_option()` for network-wide settings.

3. **Handle Blog Switching Properly**: When working with specific sites, use `switch_to_blog()` and `restore_current_blog()` to ensure you're in the correct context.

4. **Respect Network Admin Capabilities**: Use appropriate capabilities like `manage_network_options` for network admin pages.

5. **Test in Both Environments**: Always test your plugin in both single site and multisite environments to ensure compatibility.

## Conclusion

By following this guide, you can extend the WordPress Plugin Starter Template to add multisite-specific functionality. The included structure provides a solid foundation for developing features that work seamlessly in multisite environments.
