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

  it('Network plugin management page loads correctly', () => {
    cy.loginAsAdmin();
    cy.visit('/wp-admin/network/plugins.php', { timeout: 30000 });

    cy.get('#wpbody-content', { timeout: 15000 }).should('exist');
    cy.get('.wp-list-table.plugins', { timeout: 15000 }).should('exist');
  });

  it('Network settings page loads correctly', () => {
    cy.loginAsAdmin();
    cy.visit('/wp-admin/network/settings.php', { timeout: 30000 });
    cy.get('#wpbody-content', { timeout: 15000 }).should('exist');
  });
});
