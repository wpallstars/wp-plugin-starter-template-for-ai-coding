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
  cy.visit('/wp-admin', { timeout: 30000 });

  cy.get('body', { timeout: 15000 }).then(($body) => {
    if ($body.find('#wpadminbar').length > 0) {
      cy.log('Already logged in as admin');
      return;
    }

    if ($body.find('#user_login').length > 0) {
      cy.get('#user_login').should('be.visible').type('admin');
      cy.get('#user_pass').should('be.visible').type('password');
      cy.get('#wp-submit').should('be.visible').click();
      cy.get('#wpadminbar', { timeout: 15000 }).should('exist');
    } else {
      cy.log('Login form not found, assuming already logged in');
    }
  });
});

/**
 * Custom command to activate plugin
 */
Cypress.Commands.add('activatePlugin', (pluginSlug) => {
  cy.loginAsAdmin();
  cy.visit('/wp-admin/plugins.php');

  // Check if plugin is already active
  cy.contains('tr', pluginSlug).then(($tr) => {
    if ($tr.find('.deactivate').length > 0) {
      // Plugin is already active
      cy.log(`Plugin ${pluginSlug} is already active`);
      return;
    }

    // Activate the plugin
    cy.contains('tr', pluginSlug).find('.activate a').click();
    cy.contains('tr', pluginSlug).find('.deactivate').should('exist');
  });
});

/**
 * Custom command to network activate plugin
 */
Cypress.Commands.add('networkActivatePlugin', (pluginSlug) => {
  cy.loginAsAdmin();
  cy.visit('/wp-admin/network/plugins.php');

  // Check if plugin is already network active
  cy.contains('tr', pluginSlug).then(($tr) => {
    if ($tr.find('.network_active').length > 0) {
      // Plugin is already network active
      cy.log(`Plugin ${pluginSlug} is already network active`);
      return;
    }

    // Network activate the plugin
    cy.contains('tr', pluginSlug).find('.activate a').click();
    cy.contains('tr', pluginSlug).find('.network_active').should('exist');
  });
});
