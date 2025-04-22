# Testing Framework

This document explains how to use the testing framework for our plugin.

## Overview

Our testing framework uses:

See also:

* [.wiki/Architecture-Overview.md](Architecture-Overview.md) – high-level design
* [.wiki/Multisite-Development.md](Multisite-Development.md) – deeper multisite guidance

Components:

* **wp-env**: For setting up WordPress environments (both single site and multisite)
* **WordPress Playground**: For browser-based testing without Docker
* **Cypress**: For end-to-end testing
* **PHPUnit**: For unit testing (coming soon)

## Prerequisites

1. **Node.js**: Version 16 or higher
2. **npm**: For package management
3. **Docker**: For running WordPress environments with wp-env (not needed for WordPress Playground)
4. **PHP**: Version 7.4 or higher (for future PHPUnit tests)
5. **Composer**: For managing PHP dependencies

## Testing Approaches

We provide two main approaches for testing:

1. **wp-env**: Traditional approach using Docker
2. **WordPress Playground**: Browser-based approach without Docker

### 1. wp-env Approach

#### Setting Up Test Environments

We provide scripts to easily set up test environments:

##### Single Site Environment

```bash
# Set up a single site environment
npm run setup:single

# You can also use the unified setup script:
bash bin/setup-test-env.sh single
```

This will:

1. Start a WordPress single site environment using wp-env
2. Install and activate our plugin
3. Configure WordPress for testing

##### Multisite Environment

```bash
# Set up a multisite environment
npm run setup:multisite

# Or via the setup script:
bash bin/setup-test-env.sh multisite
```

This will:

1. Start a WordPress multisite environment using wp-env
2. Install and activate our plugin network-wide
3. Create a test subsite
4. Configure WordPress for testing

#### Running Tests

We have Cypress tests for both single site and multisite environments:

##### Single Site Tests

```bash
# Run tests in browser (interactive mode)
npm run test:single

# Run tests headless (CI mode)
npm run test:single:headless
```

##### Multisite Tests

```bash
# Run tests in browser (interactive mode)
npm run test:multisite

# Run tests headless (CI mode)
npm run test:multisite:headless
```

##### All-in-One Commands

We also provide all-in-one commands that set up the environment and run the tests:

```bash
# Set up single site environment and run tests
npm run test:e2e:single

# Set up multisite environment and run tests
npm run test:e2e:multisite
```

### 2. WordPress Playground Approach

WordPress Playground runs WordPress entirely in the browser using WebAssembly. This means:

* No server required - WordPress runs in the browser
* Fast startup times
* Isolated testing environment
* Works well with CI/CD pipelines

#### Using WordPress Playground Online

The easiest way to test our plugin with WordPress Playground is to use the online version:

1. Single site testing: [Open in WordPress Playground](https://playground.wordpress.net/?blueprint-url=https://raw.githubusercontent.com/wpallstars/wp-plugin-starter-template-for-ai-coding/main/playground/blueprint.json&_t=2)

2. Multisite testing: [Open in WordPress Playground](https://playground.wordpress.net/?blueprint-url=https://raw.githubusercontent.com/wpallstars/wp-plugin-starter-template-for-ai-coding/main/playground/multisite-blueprint.json&_t=2)

These links will automatically set up WordPress with multisite enabled, WP_DEBUG enabled, and both the Plugin Toggle and Kadence Blocks plugins activated.

#### Local Testing with HTML Files

We've also included HTML files that embed WordPress Playground:

1. Open `playground/index.html` in your browser for single site testing
2. Open `playground/multisite.html` in your browser for multisite testing
3. Open `playground/test.html` in your browser for a unified interface with buttons to switch between single site and multisite

You can serve these files locally with a simple HTTP server:

```bash
# Using Python
python -m http.server 8888 --directory playground

# Then open http://localhost:8888/index.html in your browser
# Or open http://localhost:8888/test.html for a unified single/multisite switcher
```

## Writing Tests

### Cypress Tests

We have custom Cypress commands to make testing WordPress easier:

* `cy.loginAsAdmin()`: Logs in as the admin user
* `cy.activatePlugin(pluginSlug)`: Activates a plugin
* `cy.networkActivatePlugin(pluginSlug)`: Network activates a plugin in multisite

Example test:

```javascript
describe('WordPress Single Site Tests', () => {
  it('Can login to the admin area', () => {
    cy.loginAsAdmin();
    cy.get('body.wp-admin').should('exist');
  });

  it('Plugin is activated', () => {
    cy.loginAsAdmin();
    cy.visit('/wp-admin/plugins.php');
    cy.get('tr[data-slug="wp-plugin-starter-template-for-ai-coding"]')
      .should('have.class', 'active');
  });
});
```

## CI/CD Integration

We have GitHub Actions workflows for running tests in CI/CD:

* `.github/workflows/wordpress-tests.yml`: Runs wp-env e2e tests
* `.github/workflows/playground-tests.yml`: Runs Playground e2e tests
* `.github/workflows/phpunit.yml`: Runs PHPUnit tests (coming soon)

## Troubleshooting

### Common Issues

1. **Docker not running**: Make sure Docker is running before starting wp-env
2. **Port conflicts**: If ports 8888 or 8889 are in use, wp-env will fail to start
3. **wp-env not installed**: Run `npm install -g @wordpress/env` to install wp-env globally

### Debugging

1. **Cypress debugging**: Use `cy.debug()` to pause test execution
2. **wp-env debugging**: Run `wp-env logs` to see WordPress logs

## Future Improvements

1. **PHPUnit tests**: Add unit tests for PHP code
2. **Performance tests**: Add performance testing
3. **Accessibility tests**: Add accessibility testing
