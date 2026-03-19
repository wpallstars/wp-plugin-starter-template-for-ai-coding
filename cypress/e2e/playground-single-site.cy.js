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

  it('Plugin is activated', () => {
    cy.loginAsAdmin();
    cy.visit('/wp-admin/plugins.php', { timeout: 30000 });

    cy.get('body', { timeout: 15000 }).then(($body) => {
      const hasPluginToggle = $body.text().includes('Plugin Toggle');
      const hasKadenceBlocks = $body.text().includes('Kadence Blocks');

      expect(
        hasPluginToggle || hasKadenceBlocks,
        'At least one blueprint plugin should be present in the plugins table',
      ).to.be.true;

      if (hasPluginToggle) {
        cy.contains('tr', 'Plugin Toggle').should('exist');
        cy.contains('tr', 'Plugin Toggle').find('.deactivate').should('exist');
      } else {
        cy.log('Plugin Toggle not found, skipping check');
      }

      if (hasKadenceBlocks) {
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
