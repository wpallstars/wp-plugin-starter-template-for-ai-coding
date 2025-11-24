# Local Testing Guide for AI Assistants

This guide provides instructions for AI coding assistants to set up and run local
WordPress testing environments for this plugin.

## Overview

Three testing approaches are available:

1. **WordPress Playground CLI** - Quick browser-based testing (recommended for AI)
2. **LocalWP** - Full local WordPress environment
3. **wp-env** - Docker-based WordPress environment

Each approach has trade-offs. Choose based on the testing needs.

## Quick Reference

```bash
# Playground CLI (fastest for AI testing)
npm run playground:start              # Start single site
npm run playground:start:multisite    # Start multisite
npm run playground:stop               # Stop server
npm run playground:status             # Check status

# LocalWP (full environment)
npm run localwp:create                # Create single site
npm run localwp:create:multisite      # Create multisite
npm run localwp:sync                  # Sync plugin changes
npm run localwp:reset                 # Reset to clean state

# wp-env (Docker-based)
npm run start                         # Start wp-env
npm run stop                          # Stop wp-env
```

## WordPress Playground CLI

Uses `@wp-playground/cli` version 3.0.22+ for instant WordPress testing.

### When to Use

* Quick plugin functionality testing
* Verifying admin UI changes
* Testing single site vs multisite behavior
* CI/CD pipeline testing (note: may be flaky in GitHub Actions)

### Starting Playground

```bash
# Single site on port 8888
npm run playground:start

# Multisite on port 8889
npm run playground:start:multisite
```

### Accessing the Site

After starting, the script provides access details:

* **Single Site**: http://localhost:8888
* **Multisite**: http://localhost:8889
* **Admin Login**: admin / password

### Blueprint Configuration

Blueprints define the WordPress setup. Located in `playground/`:

* `blueprint.json` - Single site configuration
* `multisite-blueprint.json` - Multisite configuration

Blueprints install:
* Plugin Toggle (debugging helper)
* Kadence Blocks (testing with block plugins)

### Stopping Playground

```bash
npm run playground:stop
```

### Status Check

```bash
npm run playground:status
```

Shows running processes and port usage.

### Troubleshooting

If Playground fails to start:

1. Check if ports 8888/8889 are in use: `lsof -i :8888`
2. Check logs: `cat .playground.log`
3. Stop any orphaned processes: `npm run playground:stop`
4. Ensure npm dependencies are installed: `npm install`

## LocalWP Integration

LocalWP provides a full WordPress environment with database persistence.

### Prerequisites

* LocalWP installed at `/Applications/Local.app` (macOS)
* Local Sites directory at `~/Local Sites/`

### When to Use

* Testing database migrations
* Long-term development environment
* Testing with specific PHP/MySQL versions
* Network/multisite configuration testing
* Testing WP-CLI commands

### Creating Sites

LocalWP requires manual site creation through the GUI.

```bash
npm run localwp:create
```

This guides you through:

1. Opening LocalWP
2. Creating a site with standardized name
3. Syncing plugin files

### URL Patterns

Sites use consistent naming:

* **Single Site**: `wp-plugin-starter-template-single.local`
* **Multisite**: `wp-plugin-starter-template-multisite.local`

### Syncing Plugin Files

After making code changes:

```bash
npm run localwp:sync
```

This uses rsync to copy plugin files, excluding:
* node_modules
* vendor
* tests
* .git
* dist

### Resetting

To reset the plugin to a clean state:

```bash
npm run localwp:reset
```

### Site Information

View all LocalWP sites:

```bash
./bin/localwp-setup.sh info
```

## wp-env (Docker)

Docker-based environment using `@wordpress/env`.

### When to Use

* Consistent environment across machines
* PHPUnit testing
* WP-CLI operations
* CI/CD testing

### Starting

```bash
npm run start     # or: wp-env start
```

### Running Tests

```bash
npm run test:phpunit              # Single site tests
npm run test:phpunit:multisite    # Multisite tests
```

### Running WP-CLI Commands

```bash
wp-env run cli wp plugin list
wp-env run cli wp option get siteurl
```

## Testing Workflows for AI Assistants

### Verifying a Code Change

1. Make the code change
2. Start Playground: `npm run playground:start`
3. Navigate to relevant admin page
4. Verify expected behavior
5. Stop Playground: `npm run playground:stop`

### Testing Multisite Functionality

1. Start multisite: `npm run playground:start:multisite`
2. Navigate to Network Admin
3. Test network-wide functionality
4. Test per-site functionality
5. Stop: `npm run playground:stop`

### Running PHPUnit Tests

```bash
# Single site
composer test

# Multisite
WP_MULTISITE=1 composer test

# Specific test file
vendor/bin/phpunit tests/phpunit/test-core.php
```

### Running Cypress E2E Tests

```bash
# With Playground (headless)
npm run test:playground:single
npm run test:playground:multisite

# With wp-env (headless)
npm run test:e2e:single
npm run test:e2e:multisite
```

## Environment Comparison

| Feature | Playground CLI | LocalWP | wp-env |
|---------|---------------|---------|--------|
| Setup Time | Instant | 5-10 min | 2-5 min |
| Persistence | None | Full | Partial |
| PHP Versions | Limited | Many | Limited |
| Database | In-memory | MySQL | MySQL |
| WP-CLI | Yes | Yes | Yes |
| Multisite | Yes | Yes | Yes |
| GitHub Actions | Flaky | N/A | Works |
| Best For | Quick testing | Full dev | CI/Testing |

## Common Issues

### Port Already in Use

```bash
# Check what's using the port
lsof -i :8888

# Kill the process if needed
kill $(lsof -t -i :8888)
```

### Playground Won't Start

1. Ensure dependencies installed: `npm install`
2. Check Node.js version: `node --version` (requires 18+)
3. Check logs: `cat .playground.log`

### LocalWP Site Not Found

The script expects sites at:
* `~/Local Sites/wp-plugin-starter-template-single/`
* `~/Local Sites/wp-plugin-starter-template-multisite/`

Verify the site name matches exactly.

### wp-env Docker Issues

```bash
# Restart Docker
wp-env stop
docker system prune -f
wp-env start
```

## Blueprint Reference

Blueprints use JSON format. Key steps:

```json
{
  "$schema": "https://playground.wordpress.net/blueprint-schema.json",
  "landingPage": "/wp-admin/",
  "login": true,
  "features": {
    "networking": true,
    "phpVersion": "7.4"
  },
  "steps": [
    {
      "step": "defineWpConfigConsts",
      "consts": {
        "WP_DEBUG": true
      }
    },
    {
      "step": "wp-cli",
      "command": "wp plugin install plugin-toggle --activate"
    }
  ]
}
```

For multisite, add:

```json
{
  "step": "enableMultisite"
}
```

## Resources

* [WordPress Playground CLI](https://wordpress.github.io/wordpress-playground/)
* [WordPress Playground Blueprints](https://wordpress.github.io/wordpress-playground/blueprints)
* [LocalWP Documentation](https://localwp.com/help-docs/)
* [@wordpress/env Documentation](https://developer.wordpress.org/block-editor/reference-guides/packages/packages-env/)
