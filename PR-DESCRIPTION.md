# Add Comprehensive Testing Framework for Single Site and Multisite

This PR adds a comprehensive testing framework for our WordPress plugin template.

It allows testing in both single site and multisite WordPress environments.

The focus is purely on testing functionality, not on adding multisite-specific features.

## Changes

* Added wp-env configuration for both single site and multisite environments
* Created Cypress e2e tests for both environments
* Added GitHub Actions workflow to run tests automatically on PRs
* Created a unified setup script for test environments
* Added detailed documentation in the wiki
* Updated README.md to reference the new testing approach
* Added placeholder files for multisite functionality

## Testing

The testing framework can be used as follows:

### Single Site Testing

```bash
# Set up single site environment
npm run setup:single

# Run tests in interactive mode
npm run test:single

# Run tests in headless mode
npm run test:single:headless
```

### Multisite Testing

```bash
# Set up multisite environment
npm run setup:multisite

# Run tests in interactive mode
npm run test:multisite

# Run tests in headless mode
npm run test:multisite:headless
```

## Documentation

Detailed documentation is available in the [Testing Framework](.wiki/Testing-Framework.md) wiki page.

## Inspiration

This implementation was inspired by the e2e testing approach in
[wp-multisite-waas issue #55](https://github.com/superdav42/wp-multisite-waas/issues/55).

It focuses on testing our plugin in different WordPress environments.

It does not add domain mapping or other multisite-specific functionality from that plugin.
