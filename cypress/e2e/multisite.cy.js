describe('WordPress Multisite Tests', () => {
  it('Can access the main site', () => {
    cy.visit('/');
    cy.get('body').should('exist');
    cy.get('h1').should('exist');
    cy.title().should('include', 'WordPress');
  });

  it('Can access the test subsite', () => {
    cy.visit('/testsite');
    cy.get('body').should('exist');
    cy.get('h1').should('exist');
    cy.title().should('include', 'Test Site');
  });

  it('Can login to the admin area', () => {
    cy.loginAsAdmin();
    cy.get('#wpadminbar').should('exist');
    cy.get('#dashboard-widgets').should('exist');
  });

  it('Can access network admin', () => {
    cy.loginAsAdmin();

    // Go to network admin
    cy.visit('/wp-admin/network/');
    cy.get('body.network-admin').should('exist');
  });

  it('Plugin is network activated', () => {
    // Use our custom command to check and network activate the plugin if needed
    cy.networkActivatePlugin('wp-plugin-starter-template-for-ai-coding');

    // Verify it's network active
    cy.get('tr[data-slug="wp-plugin-starter-template-for-ai-coding"] .network_active').should('exist');
  });

  it('Network settings page loads correctly', () => {
    cy.loginAsAdmin();

    // Navigate to the network settings page (if it exists)
    cy.visit('/wp-admin/network/settings.php');

    // This is a basic check for the network settings page
    cy.get('h1').should('contain', 'Network Settings');
  });
});
