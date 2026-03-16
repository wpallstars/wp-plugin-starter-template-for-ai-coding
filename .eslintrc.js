module.exports = {
  env: {
    browser: true,
    es2021: true,
    node: true,
    'cypress/globals': true
  },
  extends: [
    'eslint:recommended'
  ],
  plugins: [
    'cypress'
  ],
  parserOptions: {
    ecmaVersion: 'latest',
    sourceType: 'module'
  },
  rules: {
    'comma-dangle': ['error', 'never'],
    'no-console': 'warn',
    'no-unused-vars': 'warn'
  },
  overrides: [
    {
      // cypress.config.js uses CommonJS (require/module.exports).
      // Override sourceType to 'script' so ESLint does not flag require as undefined.
      files: ['cypress.config.js', 'cypress.config.cjs'],
      parserOptions: {
        sourceType: 'script'
      },
      env: {
        node: true
      }
    }
  ],
  globals: {
    cy: 'readonly',
    Cypress: 'readonly',
    describe: 'readonly',
    it: 'readonly',
    expect: 'readonly',
    beforeEach: 'readonly',
    afterEach: 'readonly',
    before: 'readonly',
    after: 'readonly',
    jQuery: 'readonly',
    wpstData: 'readonly',
    wpstModalData: 'readonly',
    wp: 'readonly'
  }
};
