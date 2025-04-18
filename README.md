# WordPress Plugin Starter Template for AI Coding

[![License](https://img.shields.io/badge/license-GPL--2.0%2B-blue.svg)](https://www.gnu.org/licenses/gpl-2.0.html) [![Build Status](https://github.com/wpallstars/wp-plugin-starter-template-for-ai-coding/actions/workflows/tests.yml/badge.svg)](https://github.com/wpallstars/wp-plugin-starter-template-for-ai-coding/actions/workflows/tests.yml) [![Requires PHP](https://img.shields.io/badge/php-%3E%3D%207.4-blue.svg)](https://wordpress.org/about/requirements/) [![Requires WordPress](https://img.shields.io/badge/WordPress-%3E%3D%205.0-blue.svg)](https://wordpress.org/about/requirements/) [![Tested up to](https://img.shields.io/wordpress/plugin/tested/your-plugin-slug.svg)](https://wordpress.org/plugins/your-plugin-slug/) [![WordPress rating](https://img.shields.io/wordpress/plugin/r/your-plugin-slug.svg)](https://wordpress.org/plugins/your-plugin-slug/reviews/) [![WordPress downloads](https://img.shields.io/wordpress/plugin/dt/your-plugin-slug.svg)](https://wordpress.org/plugins/your-plugin-slug/) [![Latest Release](https://img.shields.io/github/v/release/wpallstars/wp-plugin-starter-template-for-ai-coding)](https://github.com/wpallstars/wp-plugin-starter-template-for-ai-coding/releases) [![GitHub issues](https://img.shields.io/github/issues/wpallstars/wp-plugin-starter-template-for-ai-coding)](https://github.com/wpallstars/wp-plugin-starter-template-for-ai-coding/issues) [![GitHub contributors](https://img.shields.io/github/contributors/wpallstars/wp-plugin-starter-template-for-ai-coding)](https://github.com/wpallstars/wp-plugin-starter-template-for-ai-coding/graphs/contributors) [![Wiki](https://img.shields.io/badge/documentation-wiki-blue.svg)](https://github.com/wpallstars/wp-plugin-starter-template-for-ai-coding/wiki)

A comprehensive starter template for WordPress plugins with best practices for AI-assisted development.

## Description

The WordPress Plugin Starter Template provides a solid foundation for developing WordPress plugins. It incorporates best practices, modern coding standards, and a comprehensive structure that makes it easy to get started with plugin development.

This template is based on the experience gained from developing the "Fix 'Plugin file does not exist' Notices" plugin and other successful WordPress plugins.

### Key Features

* **Object-Oriented Architecture**: Well-structured, maintainable code using OOP principles
* **Namespace Support**: Modern PHP namespacing for better organization and avoiding conflicts
* **Comprehensive Documentation**: Detailed documentation for both users and developers
* **Testing Framework**: PHPUnit setup for unit testing and Cypress for e2e testing
* **Internationalization Ready**: Full support for translation and localization
* **Update Source Selection**: Choose between WordPress.org, GitHub, or Gitea for plugin updates
* **AI Workflow Documentation**: Detailed guides for AI-assisted development
* **Wiki Documentation**: Ready-to-use wiki structure for comprehensive documentation
* **Multisite Compatible**: Fully tested and compatible with WordPress multisite installations

### How to Use This Template

1. Clone or download this repository
2. **Important**: Begin by reading the [Starter Prompt](.wiki/Starter-Prompt.md) file for detailed instructions
3. Add the .ai-assistant.md file and .ai-workflows/ directory to your AI IDE chat context (pin them if possible)
4. Use the prompt in the Starter Prompt file to guide the AI in customizing the template for your plugin
5. Rename files and update namespaces to match your plugin
6. Customize the functionality for your specific needs
7. Update documentation to reflect your plugin's features
8. Build and test your plugin

### AI-Assisted Development

This template includes comprehensive documentation for AI-assisted development:

* **.ai-assistant.md**: Guide for AI assistants to understand the project structure
* **.ai-workflows/**: Detailed workflow documentation for common development tasks
* **Starter Prompt**: Comprehensive prompt for AI tools to help customize the template (available in the [wiki](.wiki/Starter-Prompt.md))

**Important**: For the best AI assistance, add the .ai-assistant.md file and .ai-workflows/ directory to your AI IDE chat context. In most AI IDEs, you can pin these files to ensure they're considered in each message.

## Installation

1. Clone or download this repository
2. Read the [Starter Prompt](.wiki/Starter-Prompt.md) file for detailed instructions
3. Add the .ai-assistant.md file and .ai-workflows/ directory to your AI IDE chat context
4. Use the prompt in the Starter Prompt file to guide the AI in customizing the template
5. Rename files and update namespaces to match your plugin
6. Customize the functionality for your specific needs
7. Update documentation to reflect your plugin's features
8. Build and test your plugin

## Usage

### Getting Started

To get started with this template, follow these steps:

1. In your terminal, navigate to the folder you keep you Git repositories (eg: `~/Git/`), then clone this repository to your local machine:
   ```bash
   git clone https://github.com/wpallstars/wp-plugin-starter-template-for-ai-coding.git
   ```

2. Open the [Starter Prompt](.wiki/Starter-Prompt.md) file and follow the instructions to customize the template for your plugin.

3. Add the .ai-assistant.md file and .ai-workflows/ directory to your AI IDE chat context.

4. Use an AI assistant like GitHub Copilot, Claude, or ChatGPT to help you customize the template by providing the prompt from the Starter Prompt file.

### Development Environment

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

### Testing

The template includes both PHP unit tests and end-to-end tests:

#### PHP Unit Tests

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

#### End-to-End Tests

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

### Building for Production

Use the included build script to create a deployable version of your plugin:

```bash
npm run build
```

Or directly:

```bash
./build.sh {VERSION}
```

This will create a ZIP file that you can install in WordPress.

### Using with Git Updater

If you've installed this plugin from GitHub or Gitea, you'll need Git Updater to receive updates:

1. Install the Git Updater plugin from [git-updater.com/git-updater/](https://git-updater.com/git-updater/)
2. Go to Settings > Git Updater > Remote Management
3. Click the "Refresh Cache" button to ensure Git Updater recognizes the latest version
4. Updates will now appear in your WordPress dashboard when available

### Choosing Your Update Source

This template includes functionality that allows users to choose where they want to receive updates from:

1. In the Plugins list, find your plugin
2. Click the "Update Source" link next to the plugin
3. Select your preferred update source:
   - **WordPress.org**: Updates from the official WordPress.org repository
   - **GitHub**: Updates directly from the GitHub repo
   - **Gitea**: Updates directly from the Gitea repo
4. Click "Save" to apply your preference

## Frequently Asked Questions

### How do I customize this template for my plugin?

See the [Starter Prompt](.wiki/Starter-Prompt.md) file for detailed instructions on customizing this template for your specific plugin needs. Make sure to add the .ai-assistant.md file and .ai-workflows/ directory to your AI IDE chat context for the best results.

### What files do I need to update with my plugin information?

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

### How do I build and test my plugin?

Use the included build.sh script to create a deployable version of your plugin:

```bash
./build.sh {VERSION}
```

This will create a ZIP file that you can install in WordPress.

### How do I add custom functionality to my plugin?

Customize the includes/core.php file to implement your core functionality and the admin/lib/admin.php file for admin-specific functionality.

### Is this template compatible with WordPress multisite?

Yes, this template is fully compatible with WordPress multisite installations. You can test multisite compatibility by running:

```bash
npm run multisite
```

## Support & Feedback

If you need help with this template, there are several ways to get support:

* [GitHub Issues](https://github.com/wpallstars/wp-plugin-starter-template-for-ai-coding/issues)
* [Gitea Issues](https://gitea.wpallstars.com/wpallstars/wp-plugin-starter-template-for-ai-coding/issues)

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

1. Fork the repository on [GitHub](https://github.com/wpallstars/wp-plugin-starter-template-for-ai-coding/) or [Gitea](https://gitea.wpallstars.com/wpallstars/wp-plugin-starter-template-for-ai-coding/)
2. Create your feature branch: `git checkout -b feature/amazing-feature`
3. Commit your changes: `git commit -m 'Add some amazing feature'`
4. Push to the branch: `git push origin feature/amazing-feature`
5. Submit a pull request

## Developers

### AI-Powered Development

This repository is configured to work with various AI-powered development tools. You can use any of the following AI IDEs to contribute to this project:

- [Augment Code](https://www.augmentcode.com/) - AI-powered coding assistant
- [Bolt](https://www.bolt.new/) - AI-powered code editor
- [Cline](https://cline.bot/) - AI terminal assistant
- [Cody](https://sourcegraph.com/cody) - Sourcegraph's AI coding assistant
- [Continue](https://continue.dev/) - Open-source AI coding assistant
- [Cursor](https://cursor.com/) - AI-first code editor
- [Loveable](https://lovable.dev/) - AI development environment
- [Roo Code](https://roocode.com/) - AI pair programmer
- [v0](https://v0.dev/) - AI-powered design and development tool
- [Windsurf](https://www.windsurf.com/) - AI coding assistant

The repository includes configuration files for all these tools to ensure a consistent development experience.

### Git Updater Integration

This template is designed to work seamlessly with the Git Updater plugin for updates from GitHub and Gitea. To ensure proper integration:

1. **Required Headers**: The plugin includes specific headers in the main plugin file that Git Updater uses to determine update sources and branches:
   ```php
   * GitHub Plugin URI: wpallstars/wp-plugin-starter-template-for-ai-coding
   * GitHub Branch: main
   * Primary Branch: main
   * Release Branch: main
   * Release Asset: true
   * Gitea Plugin URI: https://gitea.wpallstars.com/wpallstars/wp-plugin-starter-template-for-ai-coding
   * Gitea Branch: main
   ```

2. **Tagging Releases**: When creating a new release, always tag it with the 'v' prefix (e.g., `v0.1.2`) to ensure GitHub Actions can create the proper release assets.

3. **GitHub Actions**: The repository includes a GitHub Actions workflow that automatically builds the plugin and creates a release with the .zip file when a new tag is pushed.

4. **Update Source Selection**: The template includes a feature that allows users to choose their preferred update source (WordPress.org, GitHub, or Gitea).

For more information on Git Updater integration, see the [Git Updater Required Headers documentation](https://git-updater.com/knowledge-base/required-headers/).

## Changelog

### 0.1.9
* Changed: Alphabetized AI IDE list.

### 0.1.8
* Added: More informative badges (Build Status, Requirements, WP.org placeholders, Release, Issues, Contributors, Wiki).

### 0.1.7
* Fixed: GitHub Actions tests workflow with proper file paths and dependencies

### 0.1.6
* Fixed: GitHub Actions workflows permissions for releases and wiki sync

### 0.1.5
* Fixed: Release workflow to use correct plugin directory name
* Added: Testing setup with wp-env and Cypress
* Added: Multisite compatibility
* Added: npm scripts for development and testing

### 0.1.3
* Added: Improved AI IDE context recommendations in documentation
* Enhanced: Starter Prompt with guidance on pinning .ai-assistant.md and .ai-workflows/
* Moved: Starter Prompt to the wiki for better organization
* Updated: README.md and readme.txt with AI IDE context recommendations
* Improved: Documentation for AI-assisted development

### 0.1.2
* Added: STARTER-PROMPT.md with comprehensive guide for customizing the template
* Updated: Documentation files with improved instructions
* Added: Additional AI workflow files for better development guidance

### 0.1.1
* Updated: LICENSE file with correct GPL-2.0 text

### 0.1.0
* Initial release with basic template structure
* Added: Core plugin architecture with OOP approach
* Added: Admin interface components and styling
* Added: Update mechanism with multiple source options
* Added: Documentation templates for users and developers
* Added: AI workflow documentation for AI-assisted development
* Added: GitHub Actions workflows for automated tasks
* Added: Wiki documentation templates

[View full changelog](CHANGELOG.md)

## License

This project is licensed under the GPL-2.0+ License - see the [LICENSE](LICENSE) file for details.

## Credits

This template is based on the experience gained from developing the ["Fix 'Plugin file does not exist' Notices"](https://github.com/wpallstars/wp-fix-plugin-does-not-exist-notices) plugin by WPALLSTARS.
