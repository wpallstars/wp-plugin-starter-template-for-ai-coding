# WARP.md

This file provides guidance to WARP (warp.dev) when working with code in this repository.

## Project Overview

**WordPress Plugin Starter Template** - A comprehensive starter template for WordPress plugins with best practices for AI-assisted development.

* **Plugin Slug**: wp-plugin-starter-template
* **Namespace**: `WPALLSTARS\PluginStarterTemplate`
* **Text Domain**: wp-plugin-starter-template
* **Requirements**: WordPress 5.0+, PHP 7.4+
* **License**: GPL-2.0+

## Common Development Commands

### Environment Setup

```bash
# Install dependencies
npm install
composer install

# Start local WordPress environment (requires Docker)
npm run start

# Stop WordPress environment
npm run stop

# Setup single-site test environment
npm run setup:single

# Setup multisite test environment
npm run setup:multisite
```

Local WordPress site runs at: <http://localhost:8888> (admin: admin/password)

### Testing

```bash
# PHP unit tests
npm run test:php
composer test

# E2E tests (Cypress)
npm run test:e2e:single
npm run test:e2e:multisite

# Run specific test configurations
npm run test:single              # Interactive single-site
npm run test:multisite           # Interactive multisite
npm run test:single:headless     # Headless single-site
npm run test:multisite:headless  # Headless multisite

# Playground tests (no Docker required)
npm run test:playground:single
npm run test:playground:multisite
```

### Code Quality & Linting

```bash
# PHP linting and fixing
npm run lint:php              # Run PHPCS
npm run fix:php               # Run PHPCBF
composer run phpcs            # Run PHPCS directly
composer run phpcbf           # Run PHPCBF directly

# Static analysis
npm run lint:phpstan          # PHPStan
composer run phpstan

npm run lint:phpmd            # PHP Mess Detector
composer run phpmd

# JavaScript linting
npm run lint:js

# Run all linters
npm run lint                  # Runs phpcs, phpstan, phpmd
composer run lint

# Run quality checks and tests
npm run quality
```

### Building & Release

```bash
# Build plugin ZIP for distribution
npm run build
# or
./build.sh {VERSION}

# Example:
./build.sh 1.0.0
```

The build script creates a deployable ZIP file in the repository root.

## Architecture Overview

### Plugin Initialization Flow

1. **Main Plugin File** (`wp-plugin-starter-template.php`):
   * Defines constants (`WP_PLUGIN_STARTER_TEMPLATE_FILE`, `_PATH`, `_URL`, `_VERSION`)
   * Registers custom autoloader for namespaced classes
   * Instantiates `Plugin` class
   * Calls `init()` method

2. **Autoloader**:
   * Converts namespace `WPALLSTARS\PluginStarterTemplate` to file paths
   * Looks for class files in `includes/` directory
   * Uses PSR-4 naming with class file prefix conversion

3. **Plugin Class** (`includes/class-plugin.php`):
   * Main orchestration class
   * Instantiates `Core` and `Admin` classes
   * Registers hooks and loads text domain
   * Provides getters for version and admin instance

4. **Core Class** (`includes/class-core.php`):
   * Contains core plugin functionality
   * Provides version management
   * Houses filter/action methods

5. **Admin Class** (`includes/Admin/class-admin.php`):
   * Manages admin-specific functionality
   * Handles admin menu, pages, and UI

### Directory Structure

```
wp-plugin-starter-template-for-ai-coding/
├── wp-plugin-starter-template.php  # Main plugin file with headers
├── includes/                        # Core plugin classes
│   ├── class-plugin.php            # Main plugin orchestration
│   ├── class-core.php              # Core functionality
│   ├── updater.php                 # Update mechanism
│   ├── Admin/                      # Admin-specific classes
│   └── Multisite/                  # Multisite-specific functionality
├── admin/                           # Admin UI resources
│   ├── lib/                        # Admin classes
│   ├── css/                        # Admin stylesheets
│   ├── js/                         # Admin JavaScript
│   └── templates/                  # Admin template files
├── tests/                           # PHPUnit and test files
├── cypress/                         # E2E tests
├── .github/workflows/               # CI/CD workflows
├── .agents/                   # AI assistant documentation
├── .wiki/                           # Wiki documentation
└── languages/                       # Translation files
```

### Key Architectural Patterns

* **Object-Oriented**: All functionality in namespaced classes
* **PSR-4 Autoloading**: Automatic class loading without require statements
* **Dependency Injection**: `Admin` receives `Core` instance via constructor
* **Separation of Concerns**: Core functionality, admin UI, and multisite features are isolated
* **Hook-Based**: WordPress hooks for extensibility

## Coding Standards

### PHP Standards (WordPress Coding Standards)

* **Indentation**: 4 spaces (project-specific override of WordPress tabs)
* **Naming Conventions**:
  * Classes: `Class_Name`
  * Functions: `function_name`
  * Variables: `$variable_name`
* **Documentation**: DocBlocks required for all classes, methods, and functions
* **Internationalization**: All user-facing strings must be translatable with text domain `wp-plugin-starter-template`

### Markdown Standards

* Use asterisks (`*`) for bullet points, never hyphens (`-`)
* Add periods to the end of all inline comments

### Code Quality Tools

The project uses several automated tools integrated via CI/CD:

* **PHP_CodeSniffer**: Enforces WordPress Coding Standards
* **PHPCBF**: Auto-fixes coding standard violations
* **PHPStan**: Static analysis (level 5)
* **PHPMD**: Detects code complexity issues
* **ESLint**: JavaScript linting
* **Stylelint**: CSS linting
* **CodeRabbit, CodeFactor, Codacy, SonarCloud**: Continuous quality monitoring

Always run `npm run lint` or `composer run lint` before committing.

## Security Requirements

* Validate and sanitize all inputs (use `sanitize_*()` functions)
* Escape all outputs (use `esc_*()` functions)
* Use nonces for form submissions
* Check user capabilities before allowing actions
* Never expose secrets in plain text

## Release Process

### Version Numbering

Follow semantic versioning (MAJOR.MINOR.PATCH):

* **PATCH**: Bug fixes (1.0.0 → 1.0.1)
* **MINOR**: New features, backward-compatible (1.0.0 → 1.1.0)
* **MAJOR**: Breaking changes (1.0.0 → 2.0.0)

### Release Steps

1. Create version branch from main: `git checkout -b v{MAJOR}.{MINOR}.{PATCH}`
2. Update version in:
   * `wp-plugin-starter-template.php` (header and constant)
   * `readme.txt` (Stable tag and changelog)
   * `README.md` (changelog)
   * `CHANGELOG.md`
   * `languages/wp-plugin-starter-template.pot`
3. Run code quality checks: `npm run quality`
4. Build plugin: `./build.sh {VERSION}`
5. Test thoroughly (single-site and multisite)
6. Commit: `git commit -m "Version {VERSION} - [description]"`
7. Tag: `git tag -a v{VERSION} -m "Version {VERSION}"`
8. Tag stable: `git tag -a v{VERSION}-stable -m "Stable version {VERSION}"`
9. Push to remotes: `git push github main --tags && git push gitea main --tags`

**Important**: Tags with 'v' prefix trigger GitHub Actions to build and create releases automatically.

## Git Updater Integration

This template works with the Git Updater plugin for updates from GitHub and Gitea.

Required headers in main plugin file:

```php
* GitHub Plugin URI: wpallstars/wp-plugin-starter-template-for-ai-coding
* GitHub Branch: main
* Gitea Plugin URI: https://gitea.wpallstars.com/wpallstars/wp-plugin-starter-template-for-ai-coding
* Gitea Branch: main
```

Users can choose their update source (WordPress.org, GitHub, or Gitea) via plugin settings.

## Testing Framework

### WordPress Playground Testing

Test without Docker using WordPress Playground blueprints:

* Single-site: <https://playground.wordpress.net/?blueprint-url=https://raw.githubusercontent.com/wpallstars/wp-plugin-starter-template-for-ai-coding/feature/testing-framework/playground/blueprint.json>
* Multisite: <https://playground.wordpress.net/?blueprint-url=https://raw.githubusercontent.com/wpallstars/wp-plugin-starter-template-for-ai-coding/feature/testing-framework/playground/multisite-blueprint.json>

### Local Testing with wp-env

`.wp-env.json` and `.wp-env.multisite.json` configure WordPress environments.

## AI-Assisted Development

This repository includes comprehensive AI workflow documentation in `.agents/`:

* `feature-development.md`: Adding new features
* `bug-fixing.md`: Diagnosing and fixing issues
* `release-process.md`: Creating releases
* `code-quality-checks.md`: Running quality tools
* `error-checking-feedback-loops.md`: Monitoring CI/CD
* `git-workflow.md`: Git best practices
* `wiki-documentation.md`: Maintaining documentation

Reference these workflows with `@.agents/{filename}` syntax.

## Multi-Repository Workspace Context

When working in a workspace with multiple repositories:

1. Always verify you're in the correct repository: `pwd` and `git remote -v`
2. Never assume features from other repositories exist here
3. Don't hallucinate functionality from other repositories in the workspace
4. Each repository has its own specific purpose and feature set
5. Repository-specific documentation reflects only actual features in this repository

## GitHub Actions Workflows

* `tests.yml`: PHPUnit tests
* `phpunit.yml`: Additional PHPUnit configurations
* `code-quality.yml`: Runs PHPCS, PHPStan, PHPMD
* `sonarcloud.yml`: SonarCloud analysis
* `playground-tests.yml`: Tests in WordPress Playground
* `release.yml`: Creates releases when tags are pushed
* `sync-wiki.yml`: Syncs `.wiki/` to GitHub wiki

Workflows run automatically on push and pull requests.

## Internationalization (i18n)

All user-facing strings must use translation functions:

```php
// Simple strings
__('Text', 'wp-plugin-starter-template')

// Echoed strings
_e('Text', 'wp-plugin-starter-template')

// Escaped strings
esc_html__('Text', 'wp-plugin-starter-template')

// Escaped and echoed
esc_html_e('Text', 'wp-plugin-starter-template')
```

Translation files are in `languages/` directory.

## Multisite Compatibility

Fully compatible with WordPress multisite. Multisite-specific functionality is in `includes/Multisite/`.

Test multisite with:

* `npm run setup:multisite`
* `npm run test:e2e:multisite`
* WordPress Playground multisite blueprint

## Documentation Maintenance

When adding features or making changes:

1. Update `CHANGELOG.md` and `readme.txt` changelog
2. Update `README.md` if user-facing functionality changes
3. Update `.wiki/` documentation (syncs to GitHub wiki)
4. Update inline code comments and DocBlocks
5. Follow markdown standards (asterisks for bullets, periods in comments)

## Reference

* WordPress Coding Standards: <https://developer.wordpress.org/coding-standards/>
* Git Updater Headers: <https://git-updater.com/knowledge-base/required-headers/>
* Testing Framework: `.wiki/Testing-Framework.md`
* Playground Testing: `.wiki/Playground-Testing.md`
* Code Quality Setup: `docs/code-quality-setup.md`
