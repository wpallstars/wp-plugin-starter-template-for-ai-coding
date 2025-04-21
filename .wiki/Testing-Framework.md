# WordPress Plugin Testing Framework

This document outlines how to set up and run tests for our plugin in both single site and multisite WordPress environments.

## Overview

Our plugin is designed to work with both standard WordPress installations and WordPress Multisite. This testing framework allows you to verify functionality in both environments.

## Setting Up the Test Environment

We use `@wordpress/env` and Cypress for testing our plugin.

### Prerequisites

* Node.js (v14 or higher)
* npm or yarn
* Docker and Docker Compose

### Installation

1. Clone the repository:

   ```bash
   git clone https://github.com/wpallstars/wp-plugin-starter-template-for-ai-coding.git
   cd wp-plugin-starter-template-for-ai-coding
   ```

2. Install dependencies:
   ```bash
   npm install
   ```

## Testing in Single Site WordPress

1. Set up the single site environment:
   ```bash
   npm run setup:single
   ```

   This will:
   * Start a WordPress environment using wp-env
   * Activate our plugin

2. Run Cypress tests for single site:
   ```bash
   npm run test:single
   ```

   For headless testing:
   ```bash
   npm run test:single:headless
   ```

3. Access the site manually:
   * Site: <http://localhost:8888>
   * Admin login: admin / password

## Testing in WordPress Multisite

1. Set up the multisite environment:
   ```bash
   npm run setup:multisite
   ```

   This will:
   * Start a WordPress environment using wp-env
   * Configure it as a multisite installation
   * Create a test subsite
   * Network activate our plugin

2. Run Cypress tests for multisite:
   ```bash
   npm run test:multisite
   ```

   For headless testing:
   ```bash
   npm run test:multisite:headless
   ```

3. Access the sites manually:
   * Main site: <http://localhost:8888>
   * Test subsite: <http://localhost:8888/testsite>
   * Admin login: admin / password

## Continuous Integration

We use GitHub Actions to automatically run tests on pull requests. The workflow is defined in `.github/workflows/wordpress-tests.yml` and runs tests in both single site and multisite environments.

## Writing Tests

### Single Site Tests

Add new single site tests to `cypress/e2e/single-site.cy.js`.

### Multisite Tests

Add new multisite tests to `cypress/e2e/multisite.cy.js`.

## Troubleshooting

### Common Issues

1. **Database connection errors**: Make sure Docker is running and ports 8888 and 8889 are available.

2. **Multisite conversion fails**: Check the wp-env logs for details:
   ```bash
   wp-env logs
   ```

3. **Plugin not activated**: Run the following command:
   ```bash
   # For single site
   wp-env run cli wp plugin activate wp-plugin-starter-template-for-ai-coding

   # For multisite
   wp-env run cli wp plugin activate wp-plugin-starter-template-for-ai-coding --network
   ```

### Getting Help

If you encounter any issues, please open an issue on our GitHub repository with:

* A description of the problem
* Steps to reproduce
* Any error messages
* Your environment details (OS, Node.js version, etc.)
