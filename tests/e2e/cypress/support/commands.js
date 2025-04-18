/**
 * Custom Cypress commands.
 */

// Login command
Cypress.Commands.add('login', (username = 'admin', password = 'password') => {
  cy.visit('/wp-login.php');
  cy.get('#user_login').type(username);
  cy.get('#user_pass').type(password);
  cy.get('#wp-submit').click();
  cy.get('body.wp-admin').should('exist');
});
