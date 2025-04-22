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
    // Use the custom login command
    cy.loginAsAdmin();

    // Check if we're logged in
    cy.get('#wpadminbar').should('exist');
  });

  it('Plugin is activated', () => {
    // Use the custom login command
    cy.loginAsAdmin();

    // Navigate to plugins page
    cy.visit('/wp-admin/plugins.php');

    // Check if the plugin is active
    cy.contains('tr', 'Plugin Toggle').find('.deactivate').should('exist');
    cy.contains('tr', 'Kadence Blocks').find('.deactivate').should('exist');
  });

  it('Plugin settings page loads correctly', () => {
    // Use the custom login command
    cy.loginAsAdmin();

    // Navigate to the plugin settings page
    cy.visit('/wp-admin/options-general.php');

    // Check if the settings page exists
    cy.get('#wpbody-content').should('exist');
    cy.get('h1').should('be.visible');
    cy.title().should('include', 'Settings');
  });
});
