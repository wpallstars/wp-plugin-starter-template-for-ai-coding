describe('WordPress Playground Single Site Tests', () => {
  beforeEach(() => {
    // Visit the WordPress Playground page
    cy.visit('/index.html');
    
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

  it('Can access the admin area', () => {
    // WordPress Playground should auto-login as admin
    cy.get('iframe').then($iframe => {
      const $body = $iframe.contents().find('body');
      cy.wrap($body).find('#wpadminbar').should('exist');
    });
  });

  it('Plugin is activated', () => {
    // WordPress Playground should auto-activate the plugin
    cy.get('iframe').then($iframe => {
      // Navigate to plugins page
      const $document = $iframe.contents();
      const $body = $document.find('body');
      
      // Click on Plugins in the admin menu
      cy.wrap($body).find('#menu-plugins a[href*="plugins.php"]').first().click();
      
      // Check if the plugin is active
      cy.wrap($body).find('tr[data-slug="wp-plugin-starter-template-for-ai-coding"]').should('exist');
    });
  });

  it('Plugin settings page loads correctly', () => {
    cy.get('iframe').then($iframe => {
      const $document = $iframe.contents();
      const $body = $document.find('body');
      
      // Navigate to the plugin settings page
      cy.wrap($body).find('#menu-settings a[href*="options-general.php"]').first().click();
      cy.wrap($body).find('a[href*="options-general.php?page=wp-plugin-starter-template"]').click();
      
      // Check if the settings page loaded correctly
      cy.wrap($body).find('h1').should('contain', 'WP Plugin Starter Template');
    });
  });
});
