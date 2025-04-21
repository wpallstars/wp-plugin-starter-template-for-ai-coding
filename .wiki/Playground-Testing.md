# WordPress Playground Testing

This document explains how to use WordPress Playground for testing our plugin.

## What is WordPress Playground?

[WordPress Playground](https://wordpress.org/playground/) is a project that runs WordPress entirely in the browser using WebAssembly. This means:

* No server required - WordPress runs in the browser
* Fast startup times
* Isolated testing environment
* Works well with CI/CD pipelines

## Setting Up WordPress Playground Locally

1. Install the WordPress Playground CLI:

```bash
npm install -g @wordpress/playground-tools
```

2. Start WordPress Playground with our blueprint:

```bash
wp-playground start --blueprint playground/blueprint.json --port 8888
```

3. Open your browser and navigate to http://localhost:8888

## Running Tests with WordPress Playground

We have two blueprints for testing:

1. `playground/blueprint.json` - For single site testing
2. `playground/multisite-blueprint.json` - For multisite testing

To run tests with WordPress Playground:

1. Start WordPress Playground with the appropriate blueprint:

```bash
# For single site testing
wp-playground start --blueprint playground/blueprint.json --port 8888

# For multisite testing
wp-playground start --blueprint playground/multisite-blueprint.json --port 8888
```

2. Run Cypress tests against WordPress Playground:

```bash
# For single site testing
npm run test:single:headless

# For multisite testing
npm run test:multisite:headless
```

## Customizing Blueprints

You can customize the blueprints to suit your testing needs. See the [WordPress Playground Blueprints documentation](https://wordpress.github.io/wordpress-playground/blueprints/) for more information.

## CI/CD Integration

We have a GitHub Actions workflow that uses WordPress Playground for testing. See `.github/workflows/playground-tests.yml` for more information.

## Performance Testing

We also use the [WP Performance Tests GitHub Action](https://github.com/marketplace/actions/wp-performance-tests) for performance testing. This action tests our plugin against various WordPress versions and PHP versions to ensure it performs well in different environments.
