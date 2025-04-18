# Installation Guide

This guide provides instructions for installing and setting up the WordPress Plugin Starter Template.

## Prerequisites

Before installing the plugin, ensure you have:

- WordPress 5.0 or higher
- PHP 7.0 or higher
- A WordPress site with administrator access

## Installation Methods

### Method 1: From WordPress.org (For Released Plugins)

1. Log in to your WordPress admin dashboard.
2. Navigate to **Plugins > Add New**.
3. Search for "WordPress Plugin Starter Template".
4. Click **Install Now** next to the plugin.
5. After installation, click **Activate**.

### Method 2: Manual Installation

1. Download the latest release from the [GitHub repository](https://github.com/wpallstars/wp-plugin-starter-template-for-ai-coding/releases).
2. Log in to your WordPress admin dashboard.
3. Navigate to **Plugins > Add New**.
4. Click the **Upload Plugin** button at the top of the page.
5. Click **Choose File** and select the downloaded ZIP file.
6. Click **Install Now**.
7. After installation, click **Activate**.

### Method 3: Using as a Template for Your Plugin

1. Clone or download the repository:
   ```bash
   git clone https://github.com/wpallstars/wp-plugin-starter-template-for-ai-coding.git your-plugin-name
   ```

2. Navigate to your plugin directory:
   ```bash
   cd your-plugin-name
   ```

3. Rename files and update namespaces:
   - Rename `wp-plugin-starter-template.php` to your plugin name (e.g., `your-plugin-name.php`)
   - Update the namespace from `WPALLSTARS\PluginStarterTemplate` to your own
   - Update text domain from `wp-plugin-starter-template` to your own

4. Update plugin headers in the main PHP file.

5. Install dependencies:
   ```bash
   composer install
   ```

6. Upload the plugin to your WordPress site or use the local development script:
   ```bash
   ./scripts/deploy-local.sh
   ```

## Post-Installation

After installing and activating the plugin, you should:

1. Review the plugin settings (if applicable).
2. Customize the plugin for your specific needs.
3. Update documentation to reflect your plugin's features.

## Troubleshooting Installation Issues

If you encounter any issues during installation, please check the following:

1. **Plugin Conflicts**: Deactivate other plugins to check for conflicts.
2. **Server Requirements**: Ensure your server meets the minimum requirements.
3. **File Permissions**: Check that your WordPress installation has the correct file permissions.
4. **Memory Limit**: Increase PHP memory limit if you encounter memory-related errors.

## Next Steps

After installation, refer to the [Usage Instructions](Usage-Instructions) to learn how to use and customize the plugin.
