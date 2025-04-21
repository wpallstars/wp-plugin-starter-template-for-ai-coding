const { defineConfig } = require('cypress');

module.exports = defineConfig({
  e2e: {
    baseUrl: 'http://localhost:8888',
    setupNodeEvents() {
      // implement node event listeners here
    },
  },
});
