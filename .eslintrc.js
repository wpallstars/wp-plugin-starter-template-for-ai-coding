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
    'no-console': 'warn',
    'no-unused-vars': 'warn'
  },
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
