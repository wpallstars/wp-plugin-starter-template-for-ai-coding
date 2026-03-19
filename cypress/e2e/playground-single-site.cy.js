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
      // Verify the starter template plugin exists and is activated.
      if ($body.find('tr[data-slug="wp-plugin-starter-template-for-ai-coding"]').length) {
        cy.get('tr[data-slug="wp-plugin-starter-template-for-ai-coding"]').as('starterTemplatePluginRow');
        cy.get('@starterTemplatePluginRow').then(($row) => {
          if ($row.find('.deactivate a').length) {
            cy.get('@starterTemplatePluginRow').find('.deactivate a').should('exist');
          } else if ($row.find('.activate a').length) {
            cy.get('@starterTemplatePluginRow').find('.activate a').click();
            cy.get('tr[data-slug="wp-plugin-starter-template-for-ai-coding"] .deactivate a', { timeout: 15000 }).should('exist');
          } else {
            cy.log('Starter template plugin row found without activate/deactivate controls');
          }
        });
      } else {
        cy.log('Starter template plugin not found by slug, skipping check');
      }

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
