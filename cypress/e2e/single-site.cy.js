describe('WordPress Single Site Tests', () => {
  it('Can access the site', () => {
    cy.visit('/');
    cy.get('body').should('exist');
  });

  it('Can login to the admin area', () => {
    cy.visit('/wp-admin');
    cy.get('#user_login').type('admin');
    cy.get('#user_pass').type('password');
    cy.get('#wp-submit').click();
    cy.get('body.wp-admin').should('exist');
  });

  it('Plugin is activated', () => {
    // Login first
    cy.visit('/wp-admin');
    cy.get('#user_login').type('admin');
    cy.get('#user_pass').type('password');
    cy.get('#wp-submit').click();
    
    // Check plugins page
    cy.visit('/wp-admin/plugins.php');
    cy.contains('tr', 'WP Plugin Starter Template').should('contain', 'Deactivate');
  });
});
