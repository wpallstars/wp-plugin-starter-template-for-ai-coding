# Customization Guide

This guide provides detailed instructions on how to customize the plugin starter template for your specific needs.

## Basic Customization

### Renaming the Plugin

1. **Main Plugin File**: Rename `wp-plugin-starter-template.php` to match your plugin name (e.g., `my-awesome-plugin.php`)

2. **Update Plugin Header**: Edit the plugin header in your main plugin file:
   ```php
   /**
    * Plugin Name: My Awesome Plugin
    * Plugin URI: https://www.example.com
    * Description: A brief description of your plugin
    * Version: 0.1.0
    * Author: Your Name
    * Author URI: https://www.example.com
    * License: GPL-2.0+
    * License URI: http://www.gnu.org/licenses/gpl-2.0.txt
    * Text Domain: my-awesome-plugin
    * Domain Path: /languages
    */
   ```

3. **Update Text Domain**: Change the text domain throughout the codebase from `wp-plugin-starter-template` to your plugin's text domain

### Updating Namespaces

1. **Change Namespace**: Update all namespace references from `WPALLSTARS\PluginStarterTemplate` to your own namespace (e.g., `MyCompany\MyAwesomePlugin`)

2. **Update Autoloading**: Modify the `composer.json` file to reflect your new namespace:
   ```json
   "autoload": {
       "psr-4": {
           "MyCompany\\MyAwesomePlugin\\": "includes/"
       }
   }
   ```

3. **Run Composer**: After updating the namespace, run `composer dump-autoload` to update the autoloader

### Customizing Documentation

1. **README.md**: Update the README.md file with your plugin's information
2. **readme.txt**: Update the readme.txt file for WordPress.org compatibility
3. **CHANGELOG.md**: Start a fresh changelog for your plugin
4. **Wiki Documentation**: Customize the wiki documentation to match your plugin

## Advanced Customization

### Adding Custom Functionality

1. **Core Functionality**: Modify the `includes/core.php` file to implement your core functionality

2. **Admin Interface**: Customize the `admin/lib/admin.php` file to create your admin interface

3. **Frontend Features**: Add frontend functionality as needed

### Customizing Assets

1. **CSS**: Modify or add stylesheets in the `assets/css/` directory
2. **JavaScript**: Customize JavaScript files in the `assets/js/` directory
3. **Images**: Add your own images to the `assets/images/` directory

### Adding Custom Post Types

If your plugin needs custom post types, add them to the Core class:

```php
public function register_post_types() {
    register_post_type('my_custom_post', [
        'labels' => [
            'name' => __('Custom Posts', 'my-awesome-plugin'),
            'singular_name' => __('Custom Post', 'my-awesome-plugin'),
        ],
        'public' => true,
        'has_archive' => true,
        'supports' => ['title', 'editor', 'thumbnail'],
        'menu_icon' => 'dashicons-admin-post',
    ]);
}
```

### Adding Custom Taxonomies

For custom taxonomies, add them to the Core class:

```php
public function register_taxonomies() {
    register_taxonomy('custom_category', 'my_custom_post', [
        'labels' => [
            'name' => __('Custom Categories', 'my-awesome-plugin'),
            'singular_name' => __('Custom Category', 'my-awesome-plugin'),
        ],
        'hierarchical' => true,
        'show_admin_column' => true,
    ]);
}
```

### Adding Settings Pages

To add a settings page, customize the Admin class:

```php
public function add_menu_pages() {
    add_menu_page(
        __('My Plugin Settings', 'my-awesome-plugin'),
        __('My Plugin', 'my-awesome-plugin'),
        'manage_options',
        'my-awesome-plugin',
        [$this, 'render_settings_page'],
        'dashicons-admin-generic',
        100
    );
}

public function render_settings_page() {
    include plugin_dir_path(__FILE__) . '../templates/settings-page.php';
}
```

### Customizing Update Mechanism

The template includes functionality for updates from different sources. Customize the update source options in the main plugin file:

```php
/**
 * GitHub Plugin URI: username/repository
 * GitHub Branch: main
 * Primary Branch: main
 * Release Branch: main
 * Release Asset: true
 * Requires at least: 5.0
 * Requires PHP: 7.0
 * Update URI: https://example.com/plugin-updates
 */
```

## Testing Your Customizations

After making your customizations, it's important to test your plugin:

1. **Unit Tests**: Update and run the unit tests to ensure your core functionality works correctly
2. **End-to-End Tests**: Update and run the end-to-end tests to test the plugin as a whole
3. **Manual Testing**: Test your plugin in different WordPress environments

## Building Your Plugin

Once you've customized the plugin to your needs, build it for distribution:

```bash
./build.sh {VERSION}
```

This will create a ZIP file that you can install in WordPress or distribute to users.

## Conclusion

By following this customization guide, you can transform the plugin starter template into a fully functional plugin that meets your specific needs. Remember to maintain the same level of code quality and documentation as you customize the template.
