=== WordPress Plugin Starter Template for AI Coding ===
Contributors: wpallstars
Donate link: https://www.wpallstars.com/
Tags: starter, template, boilerplate, plugin development, ai coding
Requires at least: 5.0
Tested up to: 6.4
Requires PHP: 7.0
Stable tag: 0.1.7
License: GPL-2.0+
License URI: https://www.gnu.org/licenses/gpl-2.0.html

A comprehensive starter template for WordPress plugins with best practices for AI-assisted development.

== Description ==

The WordPress Plugin Starter Template provides a solid foundation for developing WordPress plugins. It incorporates best practices, modern coding standards, and a comprehensive structure that makes it easy to get started with plugin development.

This template is based on the experience gained from developing the "Fix 'Plugin file does not exist' Notices" plugin and other successful WordPress plugins.

= Key Features =

* **Object-Oriented Architecture**: Well-structured, maintainable code using OOP principles
* **Namespace Support**: Modern PHP namespacing for better organization and avoiding conflicts
* **Comprehensive Documentation**: Detailed documentation for both users and developers
* **Testing Framework**: PHPUnit setup for unit testing and Cypress for e2e testing
* **Internationalization Ready**: Full support for translation and localization
* **Update Source Selection**: Choose between WordPress.org, GitHub, or Gitea for plugin updates
* **AI Workflow Documentation**: Detailed guides for AI-assisted development
* **Wiki Documentation**: Ready-to-use wiki structure for comprehensive documentation
* **Multisite Compatible**: Fully tested and compatible with WordPress multisite installations

= How to Use This Template =

1. Clone or download this repository
2. **Important**: Begin by reading the Starter Prompt file in the wiki for detailed instructions
3. Add the .ai-assistant.md file and .ai-workflows/ directory to your AI IDE chat context (pin them if possible)
4. Use the prompt in the Starter Prompt file to guide the AI in customizing the template for your plugin
5. Rename files and update namespaces to match your plugin
6. Customize the functionality for your specific needs
7. Update documentation to reflect your plugin's features
8. Build and test your plugin

For detailed instructions, see the [Starter Prompt](https://github.com/wpallstars/wp-plugin-starter-template-for-ai-coding/wiki/Starter-Prompt) file in the wiki.

= AI-Assisted Development =

This template includes comprehensive documentation for AI-assisted development:

* **.ai-assistant.md**: Guide for AI assistants to understand the project structure
* **.ai-workflows/**: Detailed workflow documentation for common development tasks
* **Starter Prompt**: Comprehensive prompt for AI tools to help customize the template (available in the wiki)

**Important**: For the best AI assistance, add the .ai-assistant.md file and .ai-workflows/ directory to your AI IDE chat context. In most AI IDEs, you can pin these files to ensure they're considered in each message.

= Development Environment =

This template includes configuration for WordPress Environment (wp-env) to make local development easier:

1. Install Node.js dependencies:
   ```bash
   npm install
   ```

2. Start the WordPress environment:
   ```bash
   npm run start
   ```

3. For multisite testing:
   ```bash
   npm run multisite
   ```

4. Access your local WordPress site at http://localhost:8888 (admin credentials: admin/password)

= Testing =

The template includes both PHP unit tests and end-to-end tests:

**PHP Unit Tests**

1. Install Composer dependencies:
   ```bash
   composer install
   ```

2. Run PHP unit tests:
   ```bash
   npm run test:php
   ```

3. Check PHP coding standards:
   ```bash
   npm run lint:php
   ```

4. Fix PHP coding standards issues:
   ```bash
   npm run fix:php
   ```

**End-to-End Tests**

1. Start the WordPress environment:
   ```bash
   npm run start
   ```

2. Run Cypress tests in interactive mode:
   ```bash
   npm run test:e2e
   ```

3. Run Cypress tests in headless mode:
   ```bash
   npm run test:e2e:headless
   ```

= Support & Feedback =

If you need help with this template, there are several ways to get support:

* [GitHub Issues](https://github.com/wpallstars/wp-plugin-starter-template-for-ai-coding/issues)
* [Gitea Issues](https://gitea.wpallstars.com/wpallstars/wp-plugin-starter-template-for-ai-coding/issues)

= Contributing =

Contributions are welcome! Please feel free to submit a Pull Request.

1. Fork the repository on [GitHub](https://github.com/wpallstars/wp-plugin-starter-template-for-ai-coding/) or [Gitea](https://gitea.wpallstars.com/wpallstars/wp-plugin-starter-template-for-ai-coding/)
2. Create your feature branch: `git checkout -b feature/amazing-feature`
3. Commit your changes: `git commit -m 'Add some amazing feature'`
4. Push to the branch: `git push origin feature/amazing-feature`
5. Submit a pull request

== Installation ==

1. Clone or download this repository
2. Read the Starter Prompt file in the wiki for detailed instructions
3. Add the .ai-assistant.md file and .ai-workflows/ directory to your AI IDE chat context
4. Use the prompt in the Starter Prompt file to guide the AI in customizing the template
5. Rename files and update namespaces to match your plugin
6. Customize the functionality for your specific needs
7. Update documentation to reflect your plugin's features
8. Build and test your plugin

For detailed instructions, see the [Starter Prompt](https://github.com/wpallstars/wp-plugin-starter-template-for-ai-coding/wiki/Starter-Prompt) file in the wiki.

== Frequently Asked Questions ==

= How do I customize this template for my plugin? =

See the [Starter Prompt](https://github.com/wpallstars/wp-plugin-starter-template-for-ai-coding/wiki/Starter-Prompt) file in the wiki for detailed instructions on customizing this template for your specific plugin needs. Make sure to add the .ai-assistant.md file and .ai-workflows/ directory to your AI IDE chat context for the best results.

= What files do I need to update with my plugin information? =

The main files you need to update include:
1. Main plugin file (rename and update header)
2. README.md
3. readme.txt
4. CHANGELOG.md
5. composer.json
6. package.json
7. languages/pot file
8. .github/workflows/
9. .wiki/
10. .ai-assistant.md
11. includes/plugin.php
12. includes/core.php
13. admin/lib/admin.php

= How do I build and test my plugin? =

Use the included build.sh script to create a deployable version of your plugin:

```bash
./build.sh {VERSION}
```

This will create a ZIP file that you can install in WordPress.

= How do I add custom functionality to my plugin? =

Customize the includes/core.php file to implement your core functionality and the admin/lib/admin.php file for admin-specific functionality.

= How do I update the namespace for my plugin? =

You'll need to update all namespace references from WPALLSTARS\PluginStarterTemplate to your own namespace throughout the codebase.

= How do I update the text domain for my plugin? =

You'll need to update all text domain references from 'wp-plugin-starter-template' to your own text domain throughout the codebase.

= Is this template compatible with WordPress multisite? =

Yes, this template is fully compatible with WordPress multisite installations. You can test multisite compatibility by running:

```bash
npm run multisite
```

== Screenshots ==

1. This is a placeholder for your plugin's screenshots. Replace with actual screenshots of your plugin in action.

== Changelog ==

= 0.1.7 =
* Fixed: GitHub Actions tests workflow with proper file paths and dependencies
* Improved: Workflow names for better clarity in GitHub Actions UI

= 0.1.6 =
* Fixed: GitHub Actions workflows permissions for releases and wiki sync

= 0.1.5 =
* Fixed: Release workflow to use correct plugin directory name
* Added: Testing setup with wp-env and Cypress
* Added: Multisite compatibility
* Added: npm scripts for development and testing

= 0.1.3 =
* Added: Improved AI IDE context recommendations in documentation
* Enhanced: Starter Prompt with guidance on pinning .ai-assistant.md and .ai-workflows/
* Moved: Starter Prompt to the wiki for better organization
* Updated: README.md and readme.txt with AI IDE context recommendations
* Improved: Documentation for AI-assisted development

= 0.1.2 =
* Added: STARTER-PROMPT.md with comprehensive guide for customizing the template
* Updated: Documentation files with improved instructions
* Added: Additional AI workflow files for better development guidance

= 0.1.1 =
* Updated: LICENSE file with correct GPL-2.0 text

= 0.1.0 =
* Initial release with basic template structure
* Added: Core plugin architecture with OOP approach
* Added: Admin interface components and styling
* Added: Update mechanism with multiple source options
* Added: Documentation templates for users and developers
* Added: AI workflow documentation for AI-assisted development
* Added: GitHub Actions workflows for automated tasks
* Added: Wiki documentation templates

== Upgrade Notice ==

= 0.1.7 =
Fixed GitHub Actions tests workflow and improved workflow names for better clarity.

= 0.1.6 =
Fixed GitHub Actions workflows permissions for releases and wiki sync.

= 0.1.5 =
Fixed release workflow and added testing setup with wp-env and Cypress, multisite compatibility, and npm scripts for development and testing.

= 0.1.3 =
Added improved AI IDE context recommendations and moved Starter Prompt to the wiki with guidance on pinning .ai-assistant.md and .ai-workflows/ files.

= 0.1.1 =
Updated LICENSE file with correct GPL-2.0 text.

= 0.1.0 =
Initial release with basic template structure and core functionality.
