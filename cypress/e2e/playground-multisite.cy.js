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
    // Use the custom login command
    cy.loginAsAdmin();

    // Visit the network admin dashboard
    cy.visit('/wp-admin/network/');

    // Check if we're logged in to the network admin
    cy.get('#wpadminbar').should('exist');
  });

  it('Plugin is network activated', () => {
    // Use the custom login command
    cy.loginAsAdmin();

    // Navigate to network plugins page
    cy.visit('/wp-admin/network/plugins.php');

    // Check if the plugins are network active
    cy.contains('tr', 'Plugin Toggle').find('.network_active').should('exist');
    cy.contains('tr', 'Kadence Blocks').find('.network_active').should('exist');
  });

  it('Network settings page loads correctly', () => {
    // Use the custom login command
    cy.loginAsAdmin();

    // Navigate to the network settings page
    cy.visit('/wp-admin/network/settings.php');

    // Check if the network settings page loaded correctly
    cy.get('#wpbody-content').should('exist');
    cy.get('h1').should('contain', 'Network Settings');
  });
});
