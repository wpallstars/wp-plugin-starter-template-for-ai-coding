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
  cy.get('#user_login').type('admin');
  cy.get('#user_pass').type('password');
  cy.get('#wp-submit').click();
  cy.get('body.wp-admin').should('exist');
});
