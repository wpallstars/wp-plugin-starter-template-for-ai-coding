/* eslint-env mocha, jquery, cypress */
describe('WordPress Playground Single Site Tests', () => {
  beforeEach(() => {
    // Visit the WordPress Playground page
    cy.visit('/');
  });

  it('Can access the site', () => {
    // Check if the page loaded
    cy.get('body').should('exist');
  });

  it('Can access the admin area', () => {
    // Visit the admin dashboard
    cy.visit('/wp-admin/');

    // Fill in the login form if needed
    cy.get('body').then(($body) => {
      if ($body.hasClass('login')) {
        cy.get('#user_login').type('admin');
        cy.get('#user_pass').type('password');
        cy.get('#wp-submit').click();
      }
    });

    // Check if we're logged in
    cy.get('#wpadminbar').should('exist');
  });

  it('Plugin is activated', () => {
    // Navigate to plugins page
    cy.visit('/wp-admin/plugins.php');

    // Check if the plugin is active
    cy.contains('Plugin Toggle').should('exist');
    cy.contains('Kadence Blocks').should('exist');
  });

  it('Plugin settings page loads correctly', () => {
    // Navigate to the plugin settings page
    cy.visit('/wp-admin/options-general.php');

    // Check if the settings page exists
    cy.get('#wpbody-content').should('exist');
  });
});
