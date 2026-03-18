/* eslint-env node, mocha */

const { defineConfig } = require('cypress');

module.exports = defineConfig({
  e2e: {
    baseUrl: 'http://localhost:8888',
    setupNodeEvents(on, config) {
      // This function can be used to register custom Cypress plugins or event listeners.
      // Currently not in use, but left for future extensibility.
      return config;
    },
    // Add configuration for WordPress Playground
    experimentalWebKitSupport: true,
    chromeWebSecurity: false
  }
});
