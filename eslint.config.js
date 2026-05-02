const js = require('@eslint/js');
const cypress = require('eslint-plugin-cypress');

const browserGlobals = {
  document: 'readonly',
  jQuery: 'readonly',
  navigator: 'readonly',
  window: 'readonly',
  wp: 'readonly',
  wpstData: 'readonly',
  wpstModalData: 'readonly',
};

const cypressGlobals = {
  after: 'readonly',
  afterEach: 'readonly',
  before: 'readonly',
  beforeEach: 'readonly',
  context: 'readonly',
  cy: 'readonly',
  Cypress: 'readonly',
  describe: 'readonly',
  expect: 'readonly',
  it: 'readonly',
};

const nodeGlobals = {
  __dirname: 'readonly',
  module: 'readonly',
  process: 'readonly',
  require: 'readonly',
};

module.exports = [
  {
    ignores: ['vendor/**', 'node_modules/**', 'build/**', 'dist/**', 'bin/**'],
  },
  js.configs.recommended,
  {
    files: ['**/*.js'],
    languageOptions: {
      ecmaVersion: 'latest',
      sourceType: 'module',
      globals: {
        ...browserGlobals,
        ...cypressGlobals,
      },
    },
    plugins: {
      cypress,
    },
    rules: {
      'comma-dangle': ['error', 'always-multiline'],
      'no-console': 'warn',
      'no-unused-vars': 'warn',
    },
  },
  {
    files: ['cypress.config.js', 'cypress.config.cjs'],
    languageOptions: {
      sourceType: 'commonjs',
      globals: nodeGlobals,
    },
  },
];
