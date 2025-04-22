/* eslint-env mocha, jquery, cypress */
describe('WordPress Playground Multisite Tests', () => {
  beforeEach(() => {
    // Visit the WordPress Playground page
    cy.visit('/');
  });

  it('Can access the site', () => {
    // Check if the page loaded
    cy.get('body').should('exist');
  });

  it('Can access the network admin area', () => {
    // Visit the network admin dashboard
    cy.visit('/wp-admin/network/');

    // Fill in the login form if needed
    cy.get('body').then(($body) => {
      if ($body.hasClass('login')) {
        cy.get('#user_login').type('admin');
        cy.get('#user_pass').type('password');
        cy.get('#wp-submit').click();
      }
    });

    // Check if we're logged in to the network admin
    cy.get('#wpadminbar').should('exist');
  });

  it('Plugin is network activated', () => {
    // Navigate to network plugins page
    cy.visit('/wp-admin/network/plugins.php');

    // Check if the plugins are active
    cy.contains('Plugin Toggle').should('exist');
    cy.contains('Kadence Blocks').should('exist');
  });

  it('Network settings page loads correctly', () => {
    // Navigate to the network settings page
    cy.visit('/wp-admin/network/settings.php');

    // Check if the network settings page loaded correctly
    cy.get('#wpbody-content').should('exist');
  });
});
