# AI Assistant Guide for WordPress Plugin Development

This guide helps AI assistants understand the project structure, workflows, and best practices for this repository.

## IMPORTANT: Repository Context

This workspace may contain multiple repository folders. Always focus ONLY on the current repository you're working in and avoid hallucinating functionality from other repositories in the workspace.

* **Current Repository**: wp-plugin-starter-template-for-ai-coding
* **Repository Purpose**: A comprehensive starter template for WordPress plugins with best practices for AI-assisted development
* **Repository Scope**: All code changes, documentation, and functionality discussions should be limited to THIS repository only

## Project Overview

* **Plugin Name**: WordPress Plugin Starter Template
* **Plugin Slug**: wp-plugin-starter-template
* **Text Domain**: wp-plugin-starter-template
* **Namespace**: WPALLSTARS\PluginStarterTemplate
* **Version**: 0.1.13
* **Requires WordPress**: 5.0+
* **Requires PHP**: 7.0+
* **License**: GPL-2.0+

## Repository Structure

* **wp-plugin-starter-template.php**: Main plugin file with plugin headers
* **includes/**: Core plugin functionality
  * **plugin.php**: Main plugin class that initializes everything
  * **core.php**: Core functionality class
  * **updater.php**: Update mechanism for multiple sources
* **admin/**: Admin-specific functionality
  * **lib/**: Admin classes
  * **css/**: Admin stylesheets
  * **js/**: Admin JavaScript files
* **languages/**: Translation files
* **.github/workflows/**: GitHub Actions workflows
* **.agents/**: Documentation for AI assistants
* **.wiki/**: Wiki documentation templates

## Coding Standards

This project follows the [WordPress Coding Standards](https://developer.wordpress.org/coding-standards/wordpress-coding-standards/):

* Use 4 spaces for indentation, not tabs (this is a project-specific override of WordPress standards)
* Follow WordPress naming conventions:
  * Class names: `Class_Name`
  * Function names: `function_name`
  * Variable names: `$variable_name`
* Use proper DocBlocks for all classes, methods, and functions
* Ensure all user-facing strings are translatable
* Validate and sanitize all inputs
* Escape all outputs
* Use asterisks (*) for bullet points in all Markdown files, not hyphens (-)
* Add periods to the end of all inline comments

### Code Quality Tools

This project uses several automated code quality tools to ensure high standards:

1. **PHP_CodeSniffer (PHPCS)**: Checks PHP code against the WordPress Coding Standards
   ```bash
   composer run phpcs
   ```

2. **PHP Code Beautifier and Fixer (PHPCBF)**: Automatically fixes some coding standard violations
   ```bash
   composer run phpcbf
   ```

3. **ESLint**: Checks JavaScript code against the WordPress Coding Standards
   ```bash
   npm run lint:js
   ```

4. **Stylelint**: Checks CSS code against the WordPress Coding Standards
   ```bash
   npm run lint:css
   ```

5. **Continuous Integration Tools**: The project integrates with several code quality tools:
   * **CodeRabbit**: AI-powered code review tool
   * **CodeFactor**: Continuous code quality monitoring
   * **Codacy**: Code quality and static analysis
   * **SonarCloud**: Code quality and security analysis

Always run PHPCS and PHPCBF locally before committing code to ensure it meets the project's coding standards.

## Common Tasks

For detailed instructions on common tasks like creating releases, adding features, fixing bugs, and testing previous versions, see **@.agents/release-process.md**.

## Avoiding Cross-Repository Confusion

When working in a multi-repository workspace, follow these guidelines to avoid confusion:

1. **Verify Repository Context**: Always check which repository you're currently working in before making any changes or recommendations.

2. **Limit Code Search Scope**: When searching for code or functionality, explicitly limit your search to the current repository.

3. **Don't Assume Features**: Never assume that features present in one repository should be implemented in another. Each repository has its own specific purpose and feature set.

4. **Repository-Specific Documentation**: Documentation should only reflect the actual features and functionality of the current repository.

5. **Cross-Repository Inspiration**: If you want to implement a feature inspired by another repository, explicitly mention that it's a new feature being added, not an existing one.

6. **Verify Before Implementation**: Before implementing or documenting a feature, verify that it actually exists in the current repository by checking the codebase.

7. **Consistent Markdown Formatting**: Always use asterisks (*) for bullet points in Markdown files, not hyphens (-).

## Internationalization (i18n)

All user-facing strings should be translatable:

* Use `__()` for simple strings
* Use `_e()` for echoed strings
* Use `esc_html__()` for escaped strings
* Use `esc_html_e()` for escaped and echoed strings
* Always use the plugin's text domain: `wp-plugin-starter-template`

Example:
```php
echo esc_html__('This is a translatable string', 'wp-plugin-starter-template');
```

## Security Best Practices

* Validate and sanitize all inputs
* Escape all outputs
* Use nonces for form submissions
* Use capability checks for user actions
* Follow the principle of least privilege

## Documentation

* Keep code comments up-to-date
* Update README.md and readme.txt when adding new features
* Update wiki documentation in the `.wiki/` directory
* Update changelog in both CHANGELOG.md and readme.txt
* Use asterisks (*) for bullet points in all Markdown files

## Git Workflow

* Create feature branches from `main`
* Use descriptive branch names (e.g., `feature/add-settings-page`)
* Make atomic commits with clear messages
* Create pull requests for review
* Tag releases with version numbers (e.g., `v1.0.0`)

## Developer Preferences

When working with this repository, remember these preferences:

1. Follow WordPress coding standards
2. Use OOP approach with namespaced classes
3. Keep code modular and maintainable
3. Reference these preferences in future interactions

This ensures consistency across coding sessions and reduces the need for developers to repeatedly explain their preferences.
