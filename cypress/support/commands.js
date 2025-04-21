// ***********************************************
// This example commands.js shows you how to
// create various custom commands and overwrite
// existing commands.
//
// For more comprehensive examples of custom
// commands please read more here:
// https://on.cypress.io/custom-commands
// ***********************************************

/**
 * Custom command to login as admin
 */
Cypress.Commands.add('loginAsAdmin', () => {
  cy.visit('/wp-admin');

  // Check if we're already logged in
  cy.get('body').then(($body) => {
    if ($body.find('body.wp-admin').length > 0) {
      // Already logged in
      cy.log('Already logged in as admin');
      return;
    }

    // Need to log in
    cy.get('#user_login').type('admin');
    cy.get('#user_pass').type('password');
    cy.get('#wp-submit').click();
    cy.get('body.wp-admin').should('exist');
  });
});

/**
 * Custom command to activate plugin
 */
Cypress.Commands.add('activatePlugin', (pluginSlug) => {
  cy.loginAsAdmin();
  cy.visit('/wp-admin/plugins.php');

  // Check if plugin is already active
  cy.get(`tr[data-slug="${pluginSlug}"]`).then(($tr) => {
    if ($tr.find('.deactivate').length > 0) {
      // Plugin is already active
      cy.log(`Plugin ${pluginSlug} is already active`);
      return;
    }

    // Activate the plugin
    cy.get(`tr[data-slug="${pluginSlug}"] .activate a`).click();
    cy.get(`tr[data-slug="${pluginSlug}"] .deactivate`).should('exist');
  });
});

/**
 * Custom command to network activate plugin
 */
Cypress.Commands.add('networkActivatePlugin', (pluginSlug) => {
  cy.loginAsAdmin();
  cy.visit('/wp-admin/network/plugins.php');

  // Check if plugin is already network active
  cy.get(`tr[data-slug="${pluginSlug}"]`).then(($tr) => {
    if ($tr.find('.network_active').length > 0) {
      // Plugin is already network active
      cy.log(`Plugin ${pluginSlug} is already network active`);
      return;
    }

    // Network activate the plugin
    cy.get(`tr[data-slug="${pluginSlug}"] .activate a`).click();
    cy.get(`tr[data-slug="${pluginSlug}"] .network_active`).should('exist');
  });
});
