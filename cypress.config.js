/* eslint-env node */

const { defineConfig } = require('cypress');

module.exports = defineConfig({
  e2e: {
    baseUrl: 'http://localhost:8888',
    setupNodeEvents() {
      // This function can be used to register custom Cypress plugins or event listeners.
      // Currently not in use, but left for future extensibility.
    }
  }
});
