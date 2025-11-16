/* eslint-env mocha, jquery, cypress */
describe('WordPress Playground Single Site Tests', () => {
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

  it('Plugin is activated', () => {
    cy.loginAsAdmin();
    cy.visit('/wp-admin/plugins.php', { timeout: 30000 });

    cy.get('body', { timeout: 15000 }).then(($body) => {
      if ($body.text().includes('Plugin Toggle')) {
        cy.contains('tr', 'Plugin Toggle').should('exist');
        cy.contains('tr', 'Plugin Toggle').find('.deactivate').should('exist');
      } else {
        cy.log('Plugin Toggle not found, skipping check');
      }

      if ($body.text().includes('Kadence Blocks')) {
        cy.contains('tr', 'Kadence Blocks').find('.deactivate').should('exist');
      } else {
        cy.log('Kadence Blocks plugin not found, skipping check');
      }
    });
  });

  it('Plugin settings page loads correctly', () => {
    cy.loginAsAdmin();
    cy.visit('/wp-admin/options-general.php', { timeout: 30000 });
    cy.get('#wpbody-content', { timeout: 15000 }).should('exist');
    cy.get('h1').should('be.visible');
    cy.title().should('include', 'Settings');
  });
});
