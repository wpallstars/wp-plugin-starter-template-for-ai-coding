describe('WordPress Multisite Tests', () => {
  it('Can access the main site', () => {
    cy.visit('/');
    cy.get('body').should('exist');
  });

  it('Can access the test subsite', () => {
    cy.visit('/testsite');
    cy.get('body').should('exist');
  });

  it('Can login to the admin area', () => {
    cy.visit('/wp-admin');
    cy.get('#user_login').type('admin');
    cy.get('#user_pass').type('password');
    cy.get('#wp-submit').click();
    cy.get('body.wp-admin').should('exist');
  });

  it('Can access network admin', () => {
    // Login first
    cy.visit('/wp-admin');
    cy.get('#user_login').type('admin');
    cy.get('#user_pass').type('password');
    cy.get('#wp-submit').click();
    
    // Go to network admin
    cy.visit('/wp-admin/network/');
    cy.get('body.network-admin').should('exist');
  });

  it('Plugin is network activated', () => {
    // Login first
    cy.visit('/wp-admin');
    cy.get('#user_login').type('admin');
    cy.get('#user_pass').type('password');
    cy.get('#wp-submit').click();
    
    // Check plugins page
    cy.visit('/wp-admin/network/plugins.php');
    cy.contains('tr', 'WP Plugin Starter Template').should('contain', 'Network Active');
  });
});
