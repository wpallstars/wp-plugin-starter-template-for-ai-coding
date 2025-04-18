# Extending the Plugin

This guide explains how to extend the plugin's functionality through various extension points.

## Extension Points

The plugin is designed with extensibility in mind, providing several ways to extend or modify its functionality:

1. **Action Hooks**: Add custom functionality at specific points
2. **Filter Hooks**: Modify data or behavior
3. **Class Extension**: Extend existing classes to add or modify functionality
4. **Template Overrides**: Customize the plugin's output

## Using Action Hooks

Action hooks allow you to add custom functionality at specific points in the plugin's execution. Here are some examples:

### Available Actions

- `wpst_plugin_init`: Fires when the plugin is initialized
- `wpst_before_process`: Fires before the plugin processes data
- `wpst_after_process`: Fires after the plugin processes data
- `wpst_admin_init`: Fires when the admin functionality is initialized

### Example: Adding Custom Functionality

```php
add_action('wpst_plugin_init', 'my_custom_init_function');

function my_custom_init_function() {
    // Your custom initialization code here
}
```

### Example: Adding Custom Admin Functionality

```php
add_action('wpst_admin_init', 'my_custom_admin_function');

function my_custom_admin_function() {
    // Your custom admin initialization code here
}
```

## Using Filter Hooks

Filter hooks allow you to modify data or behavior at specific points. Here are some examples:

### Available Filters

- `wpst_settings`: Filter the plugin settings
- `wpst_process_data`: Filter the data being processed
- `wpst_admin_tabs`: Filter the admin tabs
- `wpst_display_output`: Filter the output before display

### Example: Modifying Settings

```php
add_filter('wpst_settings', 'my_custom_settings_filter');

function my_custom_settings_filter($settings) {
    // Modify the settings array
    $settings['custom_option'] = 'custom_value';
    return $settings;
}
```

### Example: Modifying Output

```php
add_filter('wpst_display_output', 'my_custom_output_filter');

function my_custom_output_filter($output) {
    // Modify the output
    $output = str_replace('original', 'modified', $output);
    return $output;
}
```

## Extending Classes

You can extend the plugin's classes to add or modify functionality.

### Example: Extending the Core Class

```php
use WPALLSTARS\PluginStarterTemplate\Core;

class My_Extended_Core extends Core {
    public function __construct() {
        parent::__construct();
        // Add your custom initialization here
    }
    
    // Override an existing method
    public function filter_content($content) {
        // Modify the content
        $content = parent::filter_content($content);
        $content = str_replace('original', 'modified', $content);
        return $content;
    }
    
    // Add a new method
    public function custom_method() {
        // Your custom method implementation
    }
}
```

### Example: Extending the Admin Class

```php
use WPALLSTARS\PluginStarterTemplate\Admin\Admin;

class My_Extended_Admin extends Admin {
    public function __construct($core) {
        parent::__construct($core);
        // Add your custom initialization here
    }
    
    // Override an existing method
    public function enqueue_admin_assets($hook) {
        parent::enqueue_admin_assets($hook);
        // Add your custom assets
        wp_enqueue_script(
            'my-custom-script',
            plugin_dir_url(__FILE__) . 'js/custom-script.js',
            ['jquery'],
            '1.0.0',
            true
        );
    }
    
    // Add a new method
    public function custom_admin_method() {
        // Your custom method implementation
    }
}
```

## Creating Add-ons

You can create separate add-on plugins that extend the functionality of the main plugin.

### Example: Basic Add-on Structure

```php
<?php
/**
 * Plugin Name: My Awesome Add-on
 * Description: Extends the WordPress Plugin Starter Template with awesome features
 * Version: 1.0.0
 * Author: Your Name
 * License: GPL-2.0+
 * License URI: http://www.gnu.org/licenses/gpl-2.0.txt
 * Text Domain: my-awesome-addon
 * Requires: WordPress Plugin Starter Template
 */

// Check if the main plugin is active
if (!class_exists('WPALLSTARS\\PluginStarterTemplate\\Plugin')) {
    add_action('admin_notices', 'my_addon_missing_main_plugin_notice');
    return;
}

function my_addon_missing_main_plugin_notice() {
    echo '<div class="error"><p>';
    echo __('My Awesome Add-on requires the WordPress Plugin Starter Template to be installed and activated.', 'my-awesome-addon');
    echo '</p></div>';
}

// Initialize the add-on
add_action('wpst_plugin_init', 'initialize_my_addon');

function initialize_my_addon() {
    // Your add-on initialization code here
}
```

## Best Practices for Extensions

1. **Use Namespaces**: Use PHP namespaces to avoid conflicts with other plugins
2. **Follow Coding Standards**: Maintain the same coding standards as the main plugin
3. **Document Your Extensions**: Provide clear documentation for your extensions
4. **Test Thoroughly**: Test your extensions with different WordPress versions
5. **Version Compatibility**: Specify which versions of the main plugin your extension is compatible with

## Conclusion

By using these extension points, you can customize and extend the plugin's functionality to meet your specific needs without modifying the core plugin files. This approach ensures that your customizations will continue to work even when the main plugin is updated.
