const js = require('@eslint/js');
const cypress = require('eslint-plugin-cypress');
const globals = require('globals');

const browserGlobals = {
  jQuery: 'readonly',
  wp: 'readonly',
  wpstData: 'readonly',
  wpstModalData: 'readonly',
};

const cypressGlobals = {
  Cypress: 'readonly',
  assert: 'readonly',
  chai: 'readonly',
  cy: 'readonly',
  expect: 'readonly',
};

const cypressRecommendedRules = cypress.configs.recommended.rules;

module.exports = [
  {
    ignores: ['vendor/**', 'node_modules/**', 'build/**', 'dist/**', 'bin/**'],
  },
  js.configs.recommended,
  {
    files: ['**/*.js'],
    ignores: ['cypress/eslint.config.js'],
    languageOptions: {
      ecmaVersion: 'latest',
      sourceType: 'module',
      globals: {
        ...globals.browser,
        ...browserGlobals,
      },
    },
    rules: {
      'comma-dangle': ['error', 'always-multiline'],
      'no-console': 'warn',
      'no-unused-vars': 'warn',
    },
  },
  {
    files: ['cypress/**/*.js'],
    ignores: ['cypress/eslint.config.js'],
    languageOptions: {
      globals: {
        ...globals.browser,
        ...globals.mocha,
        ...browserGlobals,
        ...cypressGlobals,
      },
    },
    plugins: {
      cypress,
    },
    rules: {
      ...cypressRecommendedRules,
      'comma-dangle': ['error', 'always-multiline'],
      'no-console': 'warn',
      'no-unused-vars': 'warn',
    },
  },
  {
    files: ['cypress.config.js', 'cypress.config.cjs', 'cypress/eslint.config.js'],
    languageOptions: {
      sourceType: 'commonjs',
      globals: {
        ...globals.node,
        exports: 'readonly',
      },
    },
  },
];
