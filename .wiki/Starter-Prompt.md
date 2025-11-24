# WordPress Plugin Starter Template - AI Assistant Prompt

This document provides a comprehensive prompt to help you get started with creating your own WordPress plugin using this starter template with the assistance of AI tools like GitHub Copilot, Claude, or ChatGPT.

## Important: Optimize AI Context

**Before starting, add the AGENTS.md file and .agents/ directory to your AI IDE chat context.** In most AI IDEs, you can pin these files to ensure they're considered in each message. This will help the AI understand the project structure and follow the established best practices.

## Initial Setup Prompt

Use the following prompt to guide the AI assistant in helping you set up your new plugin based on this template:

```
I'm creating a new WordPress plugin based on the wp-plugin-starter-template-for-ai-coding template. Please help me customize this template for my specific plugin needs.

Here are the details for my new plugin:

- Plugin Name: [YOUR PLUGIN NAME]
- Plugin Slug: [YOUR-PLUGIN-SLUG]
- Text Domain: [your-plugin-text-domain]
- Namespace: [VENDOR]\[PluginName]
- Description: [BRIEF DESCRIPTION OF YOUR PLUGIN]
- Version: 0.1.0 (starting version)
- Author: [YOUR NAME/ORGANIZATION]
- Author URI: [YOUR WEBSITE]
- License: GPL-2.0+ (or specify another compatible license)
- Requires WordPress: [MINIMUM WP VERSION, e.g., 5.0]
- Requires PHP: [MINIMUM PHP VERSION, e.g., 7.0]
- GitHub Repository: [YOUR GITHUB REPO URL]
- Gitea Repository (if applicable): [YOUR GITEA REPO URL]

I need help with the following tasks:

1. Updating all template placeholders with my plugin information
2. Customizing the plugin structure for my specific needs
3. Setting up the initial functionality for my plugin

I've added the AGENTS.md and .agents/ directory to the chat context to ensure you have all the necessary information about the project structure and best practices.

Please guide me through this process step by step, starting with identifying all files that need to be updated with my plugin information.
```

## Files That Need Updating

The AI will help you identify and update the following files with your plugin information:

1. **Main Plugin File**: Rename `wp-plugin-starter-template.php` to `your-plugin-slug.php` and update all plugin header information
2. **README.md**: Update with your plugin details, features, and installation instructions
3. **readme.txt**: Update WordPress.org plugin repository information
4. **CHANGELOG.md**: Initialize with your starting version
5. **composer.json**: Update package name and description
6. **languages/pot file**: Rename and update the POT file
7. **.github/workflows/**: Update GitHub Actions workflows with your repository information
8. **.wiki/**: Update wiki documentation with your plugin information
9. **AGENTS.md**: Update AI assistant guidance for your specific plugin
10. **includes/plugin.php**: Update namespace and class references
11. **includes/core.php**: Update namespace and customize core functionality
12. **admin/lib/admin.php**: Update namespace and customize admin functionality

## Customization Process

After providing the initial information, follow this process with your AI assistant:

### 1. File Renaming

Ask the AI to help you identify all files that need to be renamed:

```
Please list all files that need to be renamed to match my plugin slug, and provide the commands to rename them.
```

### 2. Namespace Updates

Ask the AI to help you update all namespace references:

```
Please help me update all namespace references from WPALLSTARS\PluginStarterTemplate to [VENDOR]\[PluginName] throughout the codebase.
```

### 3. Text Domain Updates

Ask the AI to help you update all text domain references:

```
Please help me update all text domain references from 'wp-plugin-starter-template' to '[your-plugin-text-domain]' throughout the codebase.
```

### 4. Function Prefix Updates

Ask the AI to help you update any function prefixes:

```
Please help me update any function prefixes from 'wpst_' to '[your_prefix]_' throughout the codebase.
```

### 5. Customizing Core Functionality

Ask the AI to help you customize the core functionality for your specific plugin needs:

```
Now I'd like to customize the core functionality for my plugin. Here's what my plugin should do:

[DESCRIBE YOUR PLUGIN'S CORE FUNCTIONALITY]

Please help me modify the includes/core.php file to implement this functionality.
```

### 6. Customizing Admin Interface

Ask the AI to help you customize the admin interface for your specific plugin needs:

```
I'd like to customize the admin interface for my plugin. Here's what I need in the admin area:

[DESCRIBE YOUR PLUGIN'S ADMIN INTERFACE NEEDS]

Please help me modify the admin/lib/admin.php file and any other necessary files to implement this.
```

### 7. Testing Setup

Ask the AI to help you set up testing for your plugin:

```
Please help me update the testing setup to match my plugin's namespace and functionality. I want to ensure I have proper test coverage for the core features.
```

## Additional Customization Areas

Depending on your plugin's needs, you might want to ask the AI for help with:

1. **Custom Post Types**: Setting up custom post types and taxonomies
2. **Settings API**: Implementing WordPress Settings API for your plugin options
3. **Shortcodes**: Creating shortcodes for front-end functionality
4. **Widgets**: Developing WordPress widgets
5. **REST API**: Adding custom REST API endpoints
6. **Blocks**: Creating Gutenberg blocks
7. **Internationalization**: Ensuring proper i18n setup
8. **Database Tables**: Creating custom database tables if needed
9. **Cron Jobs**: Setting up WordPress cron jobs
10. **User Roles and Capabilities**: Managing custom user roles and capabilities

## Final Review

Once you've completed the customization, ask the AI to help you review everything:

```
Please help me review all the changes we've made to ensure:

1. All template placeholders have been replaced with my plugin information
2. All namespaces, text domains, and function prefixes have been updated consistently
3. The plugin structure matches my specific needs
4. The initial functionality is properly implemented
5. All documentation (README.md, readme.txt, wiki) is updated and consistent

Are there any issues or inconsistencies that need to be addressed?
```

## Building and Testing

Finally, ask the AI to guide you through building and testing your plugin:

```
Please guide me through the process of building and testing my plugin:

1. How do I use the build script to create a deployable version?
2. What tests should I run to ensure everything is working correctly?
3. How do I set up a local testing environment?
4. What should I check before releasing the first version?
```

## Optimizing AI Assistance

To ensure the AI assistant has all the necessary context about your plugin's structure and best practices:

```
Please add the AGENTS.md and .agents/ directory to your AI IDE chat context. In most AI IDEs, you can pin these files to ensure they're considered in each message. This will help the AI understand the project structure and follow the established best practices.
```

## Remember

- This template is designed to be a starting point. Feel free to add, remove, or modify components as needed for your specific plugin.
- The AI assistant can help you understand the existing code and make appropriate modifications, but you should review all changes to ensure they meet your requirements.
- Always test your plugin thoroughly before releasing it.
- Keep documentation updated as you develop your plugin.
- Pin the AGENTS.md and .agents/ files in your AI IDE chat to ensure the AI has the necessary context for each interaction.

## Credits

This plugin is based on the [WordPress Plugin Starter Template for AI Coding](https://github.com/wpallstars/wp-plugin-starter-template-for-ai-coding) by WPALLSTARS.
