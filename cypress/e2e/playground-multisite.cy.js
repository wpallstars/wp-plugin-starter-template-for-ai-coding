/* eslint-env mocha, jquery, cypress */
describe('WordPress Playground Multisite Tests', () => {
  beforeEach(() => {
    // Visit the WordPress Playground page
    cy.visit('/multisite.html');

    // Wait for the iframe to load
    cy.get('iframe').should('be.visible');
  });

  it('Can access the site', () => {
    // Switch to the iframe context
    cy.get('iframe').then($iframe => {
      const $body = $iframe.contents().find('body');
      cy.wrap($body).should('exist');
    });
  });

  it('Can access the network admin area', () => {
    // WordPress Playground should auto-login as admin
    cy.get('iframe').then($iframe => {
      const $body = $iframe.contents().find('body');
      cy.wrap($body).find('#wpadminbar').should('exist');
    });
  });

  it('Plugin is network activated', () => {
    // WordPress Playground should auto-activate the plugin
    cy.get('iframe').then($iframe => {
      // Navigate to network plugins page
      const $document = $iframe.contents();
      const $body = $document.find('body');

      // Click on Network Admin in the admin bar
      cy.wrap($body).find('#wpadminbar #wp-admin-bar-network-admin a').click();

      // Click on Plugins in the network admin menu
      cy.wrap($body).find('#menu-plugins a[href*="plugins.php"]').first().click();

      // Check if the plugin is network active
      cy.wrap($body).find('tr[data-slug="wp-plugin-starter-template-for-ai-coding"]').should('exist');
      cy.wrap($body).find('tr[data-slug="wp-plugin-starter-template-for-ai-coding"] .network_active').should('exist');
    });
  });

  it('Network settings page loads correctly', () => {
    cy.get('iframe').then($iframe => {
      const $document = $iframe.contents();
      const $body = $document.find('body');

      // Navigate to the network settings page
      cy.wrap($body).find('#wpadminbar #wp-admin-bar-network-admin a').click();
      cy.wrap($body).find('#menu-settings a[href*="settings.php"]').first().click();

      // Check if the network settings page loaded correctly
      cy.wrap($body).find('h1').should('contain', 'Network Settings');
    });
  });
});
