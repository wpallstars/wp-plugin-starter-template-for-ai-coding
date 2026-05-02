/* eslint-env mocha, jquery, cypress */
describe('WordPress Playground Single Site Tests', {
  retries: {
    runMode: 2,
    openMode: 0,
  },
}, () => {
  beforeEach(() => {
    cy.visit('/', { timeout: 30000 });
  });

  it('Can access the site', () => {
    cy.get('body', { timeout: 15000 }).should('exist');
  });

  it('Can access the admin area', () => {
    cy.loginAsAdmin();
    cy.get('#wpadminbar', { timeout: 15000 }).should('exist');
  });

  it('Plugin management page loads correctly', () => {
    cy.loginAsAdmin();
    cy.visit('/wp-admin/plugins.php', { timeout: 30000 });

    cy.get('#wpbody-content', { timeout: 15000 }).should('exist');
    cy.get('.wp-list-table.plugins', { timeout: 15000 }).should('exist');
  });

  it('Plugin settings page loads correctly', () => {
    cy.loginAsAdmin();
    cy.visit('/wp-admin/options-general.php', { timeout: 30000 });
    cy.get('#wpbody-content', { timeout: 15000 }).should('exist');
    cy.get('h1').should('be.visible');
    cy.title().should('include', 'Settings');
  });
});
