# Folder Structure

This document outlines the folder structure of the plugin and explains the purpose of each directory.

## Root Directories

- **admin/** - Contains admin-specific functionality and assets
- **includes/** - Contains core plugin functionality and classes
- **languages/** - Contains translation files
- **scripts/** - Contains build and deployment scripts
- **.agents/** - Contains documentation for AI assistants
- **.github/** - Contains GitHub-specific files like workflows
- **.wordpress-org/** - Contains WordPress.org assets like banners and screenshots

## Admin Directory Structure

- **admin/css/** - Admin-specific CSS files
- **admin/js/** - Admin-specific JavaScript files
- **admin/images/** - Admin-specific images
- **admin/partials/** - Admin-specific template partials
- **admin/settings/** - Admin settings functionality
- **admin/tools/** - Admin tools functionality
- **admin/lib/** - Admin-specific library files and helper functions
  - **admin/lib/admin.php** - Admin class for handling admin-specific functionality
  - **admin/lib/modal.php** - Modal class for handling the update source selector modal

## Includes Directory

The `includes/` directory contains the core plugin functionality:

- **includes/core.php** - Core class for handling the main plugin functionality
- **includes/plugin.php** - Main plugin class that initializes all components
- **includes/updater.php** - Updater class for handling plugin updates

## File Naming Conventions

- All PHP files in the `includes/` directory use lowercase filenames
- All directories use lowercase names
- JavaScript and CSS files use kebab-case (e.g., `update-source-selector.js`)

## Best Practices

1. **Unique Directory Names**: Each directory should have a unique name to avoid confusion
2. **Logical Organization**: Files should be organized logically by function
3. **Consistent Naming**: File and directory names should follow consistent naming conventions
4. **Clear Separation**: Admin functionality should be separate from core functionality
5. **Minimal Dependencies**: Files should have minimal dependencies on other files

## @mentions for AI Assistants

When referring to files or directories in AI conversations, use the following format:

- **@includes/plugin.php** - Main plugin class
- **@includes/core.php** - Core functionality
- **@admin/lib/admin.php** - Admin functionality
- **@admin/lib/modal.php** - Modal functionality
- **@includes/updater.php** - Updater functionality
- **@admin/js/update-source-selector.js** - Update source selector JavaScript
- **@admin/css/update-source-selector.css** - Update source selector CSS
