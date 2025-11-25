describe('WordPress Single Site Tests', () => {
  it('Can access the site', () => {
    cy.visit('/');
    cy.get('body').should('exist');
  });

  it('Can login to the admin area', () => {
    cy.loginAsAdmin();
    cy.get('#wpadminbar').should('exist');
    cy.get('#dashboard-widgets').should('exist');
  });

  it('Plugin is activated', () => {
    // Use our custom command to check and activate the plugin if needed
    cy.activatePlugin('wp-plugin-starter-template-for-ai-coding');

    // Verify it's active
    cy.get('tr[data-slug="wp-plugin-starter-template-for-ai-coding"] .deactivate').should('exist');
  });

  it('Plugin settings page loads correctly', () => {
    cy.loginAsAdmin();

    // Navigate to the plugin settings page (if it exists)
    cy.visit('/wp-admin/options-general.php?page=wp-plugin-starter-template');

    // This is a basic check - adjust based on your actual plugin's settings page
    cy.get('h1').should('contain', 'WP Plugin Starter Template');
  });
});
