# WordPress Playground Testing

This document explains how to use WordPress Playground for testing our plugin.

## What is WordPress Playground?

[WordPress Playground](https://wordpress.org/playground/) is a project that runs WordPress entirely in the browser using WebAssembly. This means:

* No server required - WordPress runs in the browser
* Fast startup times
* Isolated testing environment
* Works well with CI/CD pipelines

## Using WordPress Playground Online

The easiest way to test our plugin with WordPress Playground is to use the online version:

1. Single site testing: [Open in WordPress Playground](https://playground.wordpress.net/?blueprint-url=https://raw.githubusercontent.com/wpallstars/wp-plugin-starter-template-for-ai-coding/main/playground/blueprint.json&_t=1)

2. Multisite testing: [Open in WordPress Playground](https://playground.wordpress.net/?blueprint-url=https://raw.githubusercontent.com/wpallstars/wp-plugin-starter-template-for-ai-coding/main/playground/multisite-blueprint.json&_t=1)

These links will automatically set up WordPress with multisite enabled, WP_DEBUG enabled, and both the Plugin Toggle and Kadence Blocks plugins activated.

## WP-CLI Commands for WordPress Playground

WordPress Playground supports WP-CLI commands, which can be used to interact with WordPress programmatically. Here are some useful commands for testing:

### General Commands

```bash
# Get WordPress version
wp core version

# List installed plugins
wp plugin list

# Install a plugin
wp plugin install plugin-slug

# Activate a plugin
wp plugin activate plugin-slug

# Deactivate a plugin
wp plugin deactivate plugin-slug

# Get plugin status
wp plugin status plugin-slug
```

### Multisite Commands

```bash
# List all sites in the network
wp site list

# Create a new site
wp site create --slug=testsite

# Delete a site
wp site delete 2

# Network activate a plugin
wp plugin activate plugin-slug --network

# Activate a plugin for a specific site
wp plugin activate plugin-slug --url=example.com/testsite

# Create a new user and add them to a site
wp user create testuser test@example.com --role=editor
wp user add-role testuser editor --url=example.com/testsite
```

### Testing Commands

```bash
# Run a specific test
wp scaffold plugin-tests my-plugin
wp test run --filter=test_function_name

# Check for PHP errors
wp site health check

# Export/import content for testing
wp export
wp import
```

## Plugin Activation in Multisite

In a WordPress multisite environment, there are two ways to activate plugins:

1. **Network Activation**: Activates a plugin for all sites in the network
   * In the WordPress admin, go to Network Admin > Plugins
   * Click "Network Activate" under the plugin
   * Or use WP-CLI: `wp plugin install plugin-name --activate-network`

2. **Per-Site Activation**: Activates a plugin for a specific site
   * In the WordPress admin, go to the specific site's admin area
   * Go to Plugins and activate the plugin for that site only
   * Or use WP-CLI: `wp plugin activate plugin-name --url=site-url`

Our multisite blueprint uses network activation for the Plugin Toggle plugin as an example.

## Running Tests with WordPress Playground

We have two blueprints for testing:

1. `playground/blueprint.json` - For single site testing
2. `playground/multisite-blueprint.json` - For multisite testing

To run tests with WordPress Playground:

1. Open the appropriate WordPress Playground link:
   * [Single site](https://playground.wordpress.net/?blueprint-url=https://raw.githubusercontent.com/wpallstars/wp-plugin-starter-template-for-ai-coding/main/playground/blueprint.json&_t=1)
   * [Multisite](https://playground.wordpress.net/?blueprint-url=https://raw.githubusercontent.com/wpallstars/wp-plugin-starter-template-for-ai-coding/main/playground/multisite-blueprint.json&_t=1)

2. Test the plugin manually in the browser

## Local Testing with HTML Files

We've also included HTML files that embed WordPress Playground:

1. Open `playground/index.html` in your browser for single site testing
2. Open `playground/multisite.html` in your browser for multisite testing
3. Open `playground/test.html` in your browser for a unified interface with buttons to switch between single site and multisite

You can serve these files locally with a simple HTTP server:

```bash
# Using Python
python -m http.server 8888 --directory playground

# Then open http://localhost:8888/index.html in your browser
# Or open http://localhost:8888/multisite.html for multisite testing
```

### Using wp-now

Alternatively, you can use [wp-now](https://github.com/WordPress/playground-tools/tree/trunk/packages/wp-now), a tool from the WordPress Playground team that makes it easy to run WordPress locally:

```bash
# Install wp-now globally
npm install -g @wp-playground/wp-now

# Start a WordPress instance with the current plugin
wp-now start

# Start with multisite enabled
wp-now start --multisite

# Start with specific PHP and WordPress versions
wp-now start --php 8.0 --wp 6.2

# Start with WP_DEBUG enabled
wp-now start --wp-debug
```

This will start a local WordPress instance with your plugin installed and activated.

## Customizing Blueprints

You can customize the blueprints to suit your testing needs. See the [WordPress Playground Blueprints documentation](https://wordpress.github.io/wordpress-playground/blueprints/) for more information.

## WordPress Playground JavaScript API

WordPress Playground provides a JavaScript API that allows you to programmatically interact with WordPress. This is useful for automated testing and CI/CD integration.

### Basic Usage

```javascript
// Import the WordPress Playground client
import { createWordPressPlayground } from '@wp-playground/client';

// Create a playground instance
const playground = await createWordPressPlayground({
  iframe: document.getElementById('wp-playground'),
  remoteUrl: 'https://playground.wordpress.net/remote.html',
});

// Run a blueprint
await playground.run({
  steps: [
    { step: 'enableMultisite' },
    { step: 'wp-cli', command: 'wp site create --slug=testsite' },
    { step: 'wp-cli', command: 'wp plugin install plugin-toggle kadence-blocks --activate-network' }
  ]
});

// Run WP-CLI commands
const result = await playground.run({
  step: 'wp-cli',
  command: 'wp plugin list --format=json'
});

// Parse the JSON output
const plugins = JSON.parse(result.output);
console.log(plugins);
```

### Automated Testing

You can use the JavaScript API with testing frameworks like Jest or Cypress:

```javascript
describe('Plugin Tests', () => {
  let playground;

  beforeAll(async () => {
    playground = await createWordPressPlayground({
      iframe: document.getElementById('wp-playground'),
      remoteUrl: 'https://playground.wordpress.net/remote.html',
    });

    // Set up WordPress with our blueprint
    await playground.run({
      steps: [
        { step: 'enableMultisite' },
        { step: 'wp-cli', command: 'wp site create --slug=testsite' },
        { step: 'wp-cli', command: 'wp plugin install plugin-toggle kadence-blocks --activate-network' }
      ]
    });
  });

  test('Plugin is activated', async () => {
    const result = await playground.run({
      step: 'wp-cli',
      command: 'wp plugin list --format=json'
    });

    const plugins = JSON.parse(result.output);
    const pluginToggle = plugins.find(plugin => plugin.name === 'plugin-toggle');
    expect(pluginToggle.status).toBe('active');
  });
});
```

## CI/CD Integration

We have a GitHub Actions workflow that uses WordPress Playground for testing. See `.github/workflows/playground-tests.yml` for more information.

### Example GitHub Actions Workflow

```yaml
jobs:
  playground-test:
    name: WordPress Playground Tests
    runs-on: ubuntu-latest

    steps:
    - uses: actions/checkout@v4

    - name: Setup Node.js
      uses: actions/setup-node@v4
      with:
        node-version: '20'
        cache: 'npm'

    - name: Install dependencies
      run: npm ci

    - name: Install WordPress Playground CLI
      run: npm install -g @wordpress/playground-tools

    - name: Create plugin zip
      run: |
        mkdir -p dist
        zip -r dist/plugin.zip . -x "node_modules/*" "dist/*" ".git/*"

    - name: Run tests with WordPress Playground
      run: |
        # Start WordPress Playground with our blueprint
        wp-playground start --blueprint playground/blueprint.json --port 8888 &

        # Wait for WordPress Playground to be ready
        echo "Waiting for WordPress Playground to be ready..."
        timeout 60 bash -c 'until curl -s http://localhost:8888; do sleep 2; done'

        # Run Cypress tests against WordPress Playground
        npm run test:single:headless
```

## Performance Testing

We also use the [WP Performance Tests GitHub Action](https://github.com/marketplace/actions/wp-performance-tests) for performance testing. This action tests our plugin against various WordPress versions and PHP versions to ensure it performs well in different environments.
