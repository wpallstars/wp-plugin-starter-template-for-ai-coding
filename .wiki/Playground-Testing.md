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

1. Single site testing: [Open in WordPress Playground](https://playground.wordpress.net/?blueprint-url=https://raw.githubusercontent.com/wpallstars/wp-plugin-starter-template-for-ai-coding/feature/testing-framework/playground/blueprint.json&_t=4)

2. Multisite testing: [Open in WordPress Playground](https://playground.wordpress.net/?blueprint-url=https://raw.githubusercontent.com/wpallstars/wp-plugin-starter-template-for-ai-coding/feature/testing-framework/playground/multisite-blueprint.json&_t=13)

These links will automatically set up WordPress with our plugin installed and activated.

## Running Tests with WordPress Playground

We have two blueprints for testing:

1. `playground/blueprint.json` - For single site testing
2. `playground/multisite-blueprint.json` - For multisite testing

To run tests with WordPress Playground:

1. Open the appropriate WordPress Playground link:
   - [Single site](https://playground.wordpress.net/?blueprint-url=https://raw.githubusercontent.com/wpallstars/wp-plugin-starter-template-for-ai-coding/feature/testing-framework/playground/blueprint.json&_t=4)
   - [Multisite](https://playground.wordpress.net/?blueprint-url=https://raw.githubusercontent.com/wpallstars/wp-plugin-starter-template-for-ai-coding/feature/testing-framework/playground/multisite-blueprint.json&_t=13)

2. Test the plugin manually in the browser

## Local Testing with HTML Files

We've also included HTML files that embed WordPress Playground:

1. Open `playground/index.html` in your browser for single site testing
2. Open `playground/multisite.html` in your browser for multisite testing

You can serve these files locally with a simple HTTP server:

```bash
# Using Python
python -m http.server 8888 --directory playground

# Then open http://localhost:8888/index.html in your browser
```

## Customizing Blueprints

You can customize the blueprints to suit your testing needs. See the [WordPress Playground Blueprints documentation](https://wordpress.github.io/wordpress-playground/blueprints/) for more information.

## CI/CD Integration

We have a GitHub Actions workflow that uses WordPress Playground for testing. See `.github/workflows/playground-tests.yml` for more information.

## Performance Testing

We also use the [WP Performance Tests GitHub Action](https://github.com/marketplace/actions/wp-performance-tests) for performance testing. This action tests our plugin against various WordPress versions and PHP versions to ensure it performs well in different environments.
