# Usage Instructions

This guide provides instructions for using and customizing the WordPress Plugin Starter Template for your own plugin development.

## Basic Usage

The WordPress Plugin Starter Template is designed to be a starting point for your WordPress plugin development. It provides a well-structured codebase that you can customize to create your own plugin.

### Template Structure

The template follows a modular structure:

- `wp-plugin-starter-template.php`: Main plugin file with plugin headers
- `includes/`: Core plugin functionality
  - `plugin.php`: Main plugin class that initializes everything
  - `core.php`: Core functionality class
  - `updater.php`: Update mechanism for multiple sources
- `admin/`: Admin-specific functionality
  - `lib/`: Admin classes
  - `css/`: Admin stylesheets
  - `js/`: Admin JavaScript files
- `languages/`: Translation files
- `.github/workflows/`: GitHub Actions workflows
- `.agents/`: Documentation for AI assistants
- `.wiki/`: Wiki documentation templates

### Customizing for Your Plugin

1. **Rename Files and Update Namespaces**:
   - Rename `wp-plugin-starter-template.php` to your plugin name
   - Update the namespace from `WPALLSTARS\PluginStarterTemplate` to your own
   - Update text domain from `wp-plugin-starter-template` to your own

2. **Update Plugin Headers**:
   - Edit the plugin headers in the main PHP file
   - Update GitHub/Gitea repository URLs

3. **Customize Functionality**:
   - Modify the core functionality in `includes/core.php`
   - Add your own classes as needed
   - Customize admin interfaces in the `admin/` directory

4. **Update Documentation**:
   - Update README.md and readme.txt with your plugin information
   - Customize wiki documentation in the `.wiki/` directory

## Advanced Usage

### Adding Admin Pages

The template includes a structure for adding admin pages to the WordPress dashboard. To add an admin page:

1. Uncomment the `add_admin_menu` method in `admin/lib/admin.php`
2. Customize the menu parameters to match your plugin
3. Create the corresponding render method for your admin page
4. Create template files in an `admin/templates/` directory

### Adding Settings

To add settings to your plugin:

1. Create a settings class in `includes/settings.php`
2. Register settings using the WordPress Settings API
3. Create form fields for your settings
4. Handle settings validation and sanitization

### Adding Custom Post Types or Taxonomies

To add custom post types or taxonomies:

1. Create a new class in `includes/` for your post type or taxonomy
2. Register the post type or taxonomy in the class constructor
3. Initialize the class in `includes/plugin.php`

### Internationalization

The template is ready for internationalization. To make your plugin translatable:

1. Use translation functions for all user-facing strings:
   - `__()` for simple strings
   - `_e()` for echoed strings
   - `esc_html__()` for escaped strings
2. Update the text domain in all translation functions
3. Generate a POT file for translations

### Update Mechanism

The template includes an update mechanism that supports multiple sources:

- WordPress.org
- GitHub
- Gitea

To configure the update mechanism:

1. Update the plugin headers in the main PHP file
2. Customize the `updater.php` file if needed
3. Ensure your repository follows the required structure for updates

## Building and Releasing

The template includes scripts for building and releasing your plugin:

1. **Building the Plugin**:
   ```bash
   ./build.sh <version>
   ```

2. **Deploying to a Local WordPress Installation**:
   ```bash
   ./scripts/deploy-local.sh
   ```

3. **Creating a Release**:
   - Tag a new version in Git
   - Push the tag to GitHub
   - The GitHub Actions workflow will create a release

## Next Steps

After customizing the template for your needs, refer to the [Architecture Overview](Architecture-Overview) to understand the plugin's structure in more detail.
