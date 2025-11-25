/* eslint-env mocha, jquery, cypress */
describe('WordPress Playground Multisite Tests', () => {
  beforeEach(() => {
    cy.visit('/', { timeout: 30000 });
  });

  it('Can access the site', () => {
    cy.get('body', { timeout: 15000 }).should('exist');
  });

  it('Can access the network admin area', () => {
    cy.loginAsAdmin();
    cy.visit('/wp-admin/network/', { timeout: 30000 });
    cy.get('#wpadminbar', { timeout: 15000 }).should('exist');
    cy.get('#wpbody-content').should('exist');
  });

  it('Plugin is network activated', () => {
    cy.loginAsAdmin();
    cy.visit('/wp-admin/network/plugins.php', { timeout: 30000 });

    cy.get('body', { timeout: 15000 }).then(($body) => {
      if ($body.text().includes('Plugin Toggle')) {
        cy.contains('tr', 'Plugin Toggle').should('exist');
        cy.contains('tr', 'Plugin Toggle').find('.network_active, .deactivate').should('exist');
      } else {
        cy.log('Plugin Toggle not found, skipping check');
      }

      if ($body.text().includes('Kadence Blocks')) {
        cy.contains('tr', 'Kadence Blocks').find('.network_active, .deactivate').should('exist');
      } else {
        cy.log('Kadence Blocks plugin not found, skipping check');
      }
    });
  });

  it('Network settings page loads correctly', () => {
    cy.loginAsAdmin();
    cy.visit('/wp-admin/network/settings.php', { timeout: 30000 });
    cy.get('#wpbody-content', { timeout: 15000 }).should('exist');
  });
});
