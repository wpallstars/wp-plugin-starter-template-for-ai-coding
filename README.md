# WordPress Plugin Starter Template for AI Coding

[![License](https://img.shields.io/badge/license-GPL--2.0%2B-blue.svg)](https://www.gnu.org/licenses/gpl-2.0.html) [![Build Status](https://github.com/wpallstars/wp-plugin-starter-template-for-ai-coding/actions/workflows/tests.yml/badge.svg)](https://github.com/wpallstars/wp-plugin-starter-template-for-ai-coding/actions/workflows/tests.yml) [![Requires PHP](https://img.shields.io/badge/php-%3E%3D%207.4-blue.svg)](https://wordpress.org/about/requirements/) [![Requires WordPress](https://img.shields.io/badge/WordPress-%3E%3D%205.0-blue.svg)](https://wordpress.org/about/requirements/) [![Tested up to](https://img.shields.io/wordpress/plugin/tested/your-plugin-slug.svg)](https://wordpress.org/plugins/your-plugin-slug/) [![WordPress rating](https://img.shields.io/wordpress/plugin/r/your-plugin-slug.svg)](https://wordpress.org/plugins/your-plugin-slug/reviews/) [![WordPress downloads](https://img.shields.io/wordpress/plugin/dt/your-plugin-slug.svg)](https://wordpress.org/plugins/your-plugin-slug/) [![Latest Release](https://img.shields.io/github/v/release/wpallstars/wp-plugin-starter-template-for-ai-coding)](https://github.com/wpallstars/wp-plugin-starter-template-for-ai-coding/releases) [![GitHub issues](https://img.shields.io/github/issues/wpallstars/wp-plugin-starter-template-for-ai-coding)](https://github.com/wpallstars/wp-plugin-starter-template-for-ai-coding/issues) [![GitHub contributors](https://img.shields.io/github/contributors/wpallstars/wp-plugin-starter-template-for-ai-coding)](https://github.com/wpallstars/wp-plugin-starter-template-for-ai-coding/graphs/contributors) [![Wiki](https://img.shields.io/badge/documentation-wiki-blue.svg)](https://github.com/wpallstars/wp-plugin-starter-template-for-ai-coding/wiki) ![CodeRabbit Pull Request Reviews](https://img.shields.io/coderabbit/prs/github/wpallstars/wp-plugin-starter-template-for-ai-coding?utm_source=oss&utm_medium=github&utm_campaign=wpallstars%2Fwp-plugin-starter-template-for-ai-coding&labelColor=171717&color=FF570A&link=https%3A%2F%2Fcoderabbit.ai&label=CodeRabbit+Reviews) [![CodeFactor](https://www.codefactor.io/repository/github/wpallstars/wp-plugin-starter-template-for-ai-coding/badge)](https://www.codefactor.io/repository/github/wpallstars/wp-plugin-starter-template-for-ai-coding) [![Quality Gate Status](https://sonarcloud.io/api/project_badges/measure?project=wpallstars_wp-plugin-starter-template-for-ai-coding&metric=alert_status)](https://sonarcloud.io/summary/new_code?id=wpallstars_wp-plugin-starter-template-for-ai-coding) [![Bugs](https://sonarcloud.io/api/project_badges/measure?project=wpallstars_wp-plugin-starter-template-for-ai-coding&metric=bugs)](https://sonarcloud.io/summary/new_code?id=wpallstars_wp-plugin-starter-template-for-ai-coding) [![Code Smells](https://sonarcloud.io/api/project_badges/measure?project=wpallstars_wp-plugin-starter-template-for-ai-coding&metric=code_smells)](https://sonarcloud.io/summary/new_code?id=wpallstars_wp-plugin-starter-template-for-ai-coding) [![Coverage](https://sonarcloud.io/api/project_badges/measure?project=wpallstars_wp-plugin-starter-template-for-ai-coding&metric=coverage)](https://sonarcloud.io/summary/new_code?id=wpallstars_wp-plugin-starter-template-for-ai-coding) [![Duplicated Lines (%)](https://sonarcloud.io/api/project_badges/measure?project=wpallstars_wp-plugin-starter-template-for-ai-coding&metric=duplicated_lines_density)](https://sonarcloud.io/summary/new_code?id=wpallstars_wp-plugin-starter-template-for-ai-coding) [![Codacy Badge](https://app.codacy.com/project/badge/Grade/905754fd010b481490b496fb800e6144)](https://app.codacy.com/gh/wpallstars/wp-plugin-starter-template-for-ai-coding/dashboard?utm_source=gh&utm_medium=referral&utm_content=&utm_campaign=Badge_grade)

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

3. For testing in different WordPress environments:
   ```bash
   # For single site testing
   npm run setup:single

   # For multisite testing
   npm run setup:multisite
   ```

   See [Testing Framework](.wiki/Testing-Framework.md) for more details on our testing approach.

4. Access your local WordPress site at <http://localhost:8888> (admin credentials: admin/password)

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
   * **WordPress.org**: Updates from the official WordPress.org repository
   * **GitHub**: Updates directly from the GitHub repo
   * **Gitea**: Updates directly from the Gitea repo
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

Yes, this template is fully compatible with WordPress multisite installations. We have a comprehensive testing framework that allows you to verify functionality in both single site and multisite environments.

You can test multisite compatibility by running:

```bash
npm run setup:multisite
```

For more details on our testing approach, see the [Testing Framework](.wiki/Testing-Framework.md) file.

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

For more detailed information, see the [Contributing Guide](.wiki/Contributing.md).

### Code Quality Tools

This project uses several automated code quality tools to ensure high standards. These tools are free for public repositories and should be integrated into any new repositories based on this template:

1. **CodeRabbit**: AI-powered code review tool
   * [Website](https://www.coderabbit.ai/)
   * Provides automated feedback on pull requests

2. **CodeFactor**: Continuous code quality monitoring
   * [Website](https://www.codefactor.io/)
   * Provides a grade for your codebase

3. **Codacy**: Code quality and static analysis
   * [Website](https://www.codacy.com/)
   * Identifies issues related to code style, security, and performance
   * Requires a `CODACY_PROJECT_TOKEN` secret in your GitHub repository settings
   * To set up Codacy:
     1. Go to [Codacy](https://www.codacy.com/) and sign in with your GitHub account
     2. Add your repository to Codacy
     3. Go to your project settings > Integrations > Project API
     4. Generate a project API token
     5. Add the token as a secret named `CODACY_PROJECT_TOKEN` in your GitHub repository settings
     6. Note: Codacy tokens are project-specific, so they need to be added at the repository level. However, you can use GitHub Actions to securely pass these tokens between repositories if needed.

4. **SonarCloud**: Code quality and security analysis
   * [Website](https://sonarcloud.io/)
   * Provides detailed analysis of code quality and security
   * Requires a `SONAR_TOKEN` secret in your GitHub repository settings
   * To set up SonarCloud:
     1. Go to [SonarCloud](https://sonarcloud.io/) and sign in with your GitHub account
     2. Create a new organization or use an existing one
     3. Add your repository to SonarCloud
     4. Generate a token in SonarCloud (Account > Security > Tokens)
     5. Add the token as a secret named `SONAR_TOKEN` in your GitHub repository or organization settings (see "GitHub Secrets Management" section below)

5. **PHP_CodeSniffer (PHPCS)**: PHP code style checker
   * Enforces WordPress Coding Standards
   * Automatically runs in GitHub Actions workflow
   * Run locally with `composer phpcs`

6. **PHP Code Beautifier and Fixer (PHPCBF)**: Automatically fixes coding standard violations
   * Run locally with `composer phpcbf`

7. **PHPStan**: PHP static analysis tool
   * Detects bugs and errors without running the code
   * Run locally with `composer phpstan`

8. **PHP Mess Detector (PHPMD)**: Analyzes code for potential problems
   * Identifies complex code, unused parameters, etc.
   * Run locally with `composer phpmd`

For detailed setup instructions, see the [Code Quality Setup Guide](docs/code-quality-setup.md).

### Using AI Assistants with Code Quality Tools

When you receive feedback from these code quality tools, you can use AI assistants to help address the issues:

1. Copy the output from the code quality tool
2. Paste it into your AI assistant chat
3. Ask the AI to help you understand and resolve the issues
4. Apply the suggested fixes
5. Commit the changes and verify that the issues are resolved

For more information on coding standards and how to pass code quality checks, see the [Coding Standards Guide](.wiki/Coding-Standards.md).

### GitHub Secrets Management

GitHub offers three levels of secrets management, each with different scopes and use cases:

1. **Organization Secrets** (recommended for teams and organizations):
   * Available at: GitHub Organization > Settings > Secrets and variables > Actions
   * Scope: Can be shared across multiple repositories within the organization
   * Benefits: Centralized management, reduced duplication, easier rotation
   * Recommended for: `SONAR_TOKEN` and other tokens that apply to multiple repositories
   * Note: You can restrict which repositories can access organization secrets
   * Note: Codacy tokens (`CODACY_PROJECT_TOKEN`) are project-specific and should be set at the repository level

2. **Repository Secrets**:
   * Available at: Repository > Settings > Secrets and variables > Actions
   * Scope: Limited to a single repository
   * Benefits: Repository-specific, higher isolation
   * Recommended for: `CODACY_PROJECT_TOKEN` and other repository-specific credentials or tokens that shouldn't be shared

3. **Environment Secrets**:
   * Available at: Repository > Settings > Environments > (select environment) > Environment secrets
   * Scope: Limited to specific deployment environments (e.g., production, staging)
   * Benefits: Environment-specific, can have approval requirements
   * Recommended for: Deployment credentials that vary between environments

For code quality tools like SonarCloud, organization secrets are recommended if you have multiple repositories that use these tools. This approach reduces management overhead and ensures consistent configuration across projects. For Codacy, since tokens are project-specific, they should be set at the repository level.

### Local Environment Setup for Code Quality Tools

To run code quality tools locally before committing to GitHub:

1. **Install dependencies**:

   ```bash
   composer install
   ```

2. **Run PHP CodeSniffer**:

   ```bash
   composer phpcs
   ```

3. **Fix coding standards automatically**:

   ```bash
   composer phpcbf
   ```

4. **Run PHPStan static analysis**:

   ```bash
   composer phpstan
   ```

5. **Run PHP Mess Detector**:

   ```bash
   composer phpmd
   ```

6. **Run all linters at once**:

   ```bash
   composer lint
   ```

7. **Set up environment variables for SonarCloud and Codacy**:

   * **For macOS/Linux**:
     ```bash
     export SONAR_TOKEN=your_sonar_token
     export CODACY_PROJECT_TOKEN=your_codacy_token
     ```

   * **For Windows (Command Prompt)**:

     ```cmd
     set SONAR_TOKEN=your_sonar_token
     set CODACY_PROJECT_TOKEN=your_codacy_token
     ```

   * **For Windows (PowerShell)**:

     ```powershell
     $env:SONAR_TOKEN="your_sonar_token"
     $env:CODACY_PROJECT_TOKEN="your_codacy_token"
     ```

8. **Create a .env file** (alternative approach):

   ```env
   # .env (already included in .gitignore to prevent committing secrets)
   SONAR_TOKEN=your_sonar_token
   CODACY_PROJECT_TOKEN=your_codacy_token
   ```

   Then load these variables:

   ```bash
   # Using a tool like dotenv
   source .env
   ```

9. **Run SonarCloud locally**:

   ```bash
   # Install SonarScanner
   npm install -g sonarqube-scanner

   # Run analysis
   sonar-scanner \
     -Dsonar.projectKey=your_project_key \
     -Dsonar.organization=your_organization \
     -Dsonar.sources=. \
     -Dsonar.host.url=https://sonarcloud.io \
     -Dsonar.login=$SONAR_TOKEN
   ```

10. **Run Codacy locally**:

    ```bash
    # Install Codacy CLI
    npm install -g codacy-coverage

    # Run analysis
    codacy-analysis-cli analyze --directory . --project-token $CODACY_PROJECT_TOKEN
    ```

For more detailed instructions, see the [Code Quality Setup Guide](docs/code-quality-setup.md).

By running these tools locally, you can identify and fix issues before pushing your code to GitHub, ensuring smoother CI/CD workflows.

## Developers

### AI-Powered Development

This repository is configured to work with various AI-powered development tools. You can use any of the following AI IDEs to contribute to this project:

* [Augment Code](https://www.augmentcode.com/) - AI-powered coding assistant
* [Bolt](https://www.bolt.new/) - AI-powered code editor
* [Cline](https://cline.bot/) - AI terminal assistant
* [Cody](https://sourcegraph.com/cody) - Sourcegraph's AI coding assistant
* [Continue](https://continue.dev/) - Open-source AI coding assistant
* [Cursor](https://cursor.com/) - AI-first code editor
* [Loveable](https://lovable.dev/) - AI development environment
* [Roo Code](https://roocode.com/) - AI pair programmer
* [v0](https://v0.dev/) - AI-powered design and development tool
* [Windsurf](https://www.windsurf.com/) - AI coding assistant

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

### 0.1.13

* Improved: Code quality with proper type declarations
* Fixed: Inconsistent variable naming (camelCase to snake_case)
* Improved: Path handling in admin class
* Added: Textdomain loading functionality
* Removed: Unused phpcs:ignore comment
* Implemented: Proper return type declarations

### 0.1.12

* Fixed: WordPress mocking in unit tests
* Added: Proper mocking for WordPress functions in tests
* Improved: Code quality tool configurations
* Added: Detailed code quality checks workflow documentation
* Updated: Documentation for better workflow efficiency

### 0.1.11

* Improved: Code quality with comprehensive fixes
* Fixed: Indentation issues in PHP files
* Updated: CSS formatting with modern notation
* Fixed: JavaScript issues with proper global variables
* Improved: Security by using filter_input() instead of direct superglobal access
* Standardized: Naming conventions across the codebase
* Fixed: Documentation and comments for better clarity

### 0.1.10

* Fixed: Formatting issues in markdown files for better code quality
* Fixed: Improved URL formatting with angle brackets
* Fixed: Standardized list formatting across documentation files

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
