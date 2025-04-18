/**
 * Basic e2e test for the plugin.
 */
describe('Plugin Basic Tests', () => {
  before(() => {
    cy.login();
  });

  it('Should activate the plugin', () => {
    cy.visit('/wp-admin/plugins.php');
    cy.contains('WP Plugin Starter Template').should('exist');
    
    // Check if plugin is not active, then activate it
    cy.get('tr[data-slug="wp-plugin-starter-template-for-ai-coding"]')
      .then(($tr) => {
        if ($tr.hasClass('inactive')) {
          cy.wrap($tr).find('.activate a').click();
          cy.contains('Plugin activated.').should('exist');
        }
      });
  });

  it('Should have the plugin settings page', () => {
    cy.visit('/wp-admin/options-general.php?page=wp-plugin-starter-template');
    cy.contains('WP Plugin Starter Template Settings').should('exist');
  });
});
