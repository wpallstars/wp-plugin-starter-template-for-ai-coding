/* eslint-env mocha, jquery, cypress */
describe( 'WordPress Single Site Tests', () => {
    it( 'Can access the site', () => {
        cy.visit( '/' );
        cy.get( 'body' ).should( 'exist' );
    } );

    it( 'Can login to the admin area', () => {
        cy.loginAsAdmin();
        cy.get( '#wpadminbar' ).should( 'exist' );
        cy.get( '#dashboard-widgets' ).should( 'exist' );
    } );

    it( 'Plugin is activated', () => {
        // Use our custom command to check and activate the plugin if needed.
        cy.activatePlugin( 'wp-plugin-starter-template-for-ai-coding' );

        // Verify it's active.
        cy.get( 'tr[data-slug="wp-plugin-starter-template-for-ai-coding"] .deactivate' ).should( 'exist' );
    } );

    it( 'Plugin row is visible on the plugins page', () => {
        cy.loginAsAdmin();
        cy.visit( '/wp-admin/plugins.php' );

        // Verify the plugin row exists with the correct slug.
        cy.get( 'tr[data-slug="wp-plugin-starter-template-for-ai-coding"]' ).should( 'exist' );

        // Verify the plugin name is displayed.
        cy.get( 'tr[data-slug="wp-plugin-starter-template-for-ai-coding"] .plugin-title strong' )
            .should( 'contain', 'WordPress Plugin Starter Template' );
    } );

    it( 'Update source selector link is present in the plugin row', () => {
        cy.loginAsAdmin();
        cy.visit( '/wp-admin/plugins.php' );

        // The update source selector link should be rendered in the plugin row.
        cy.get( 'tr[data-slug="wp-plugin-starter-template-for-ai-coding"]' )
            .find( '.wpst-update-source-selector' )
            .should( 'exist' );
    } );

    it( 'Update source modal opens and displays source options', () => {
        cy.loginAsAdmin();
        cy.visit( '/wp-admin/plugins.php' );

        // Click the update source selector link to open the modal.
        cy.get( '.wpst-update-source-selector' ).first().click();

        // Modal should be visible.
        cy.get( '#wpst-update-source-modal' ).should( 'be.visible' );

        // Modal should contain the three update source options.
        cy.get( '#wpst-update-source-modal input[name="update_source"][value="wordpress.org"]' ).should( 'exist' );
        cy.get( '#wpst-update-source-modal input[name="update_source"][value="github"]' ).should( 'exist' );
        cy.get( '#wpst-update-source-modal input[name="update_source"][value="gitea"]' ).should( 'exist' );

        // Save button should be present.
        cy.get( '#wpst-save-source' ).should( 'exist' );
    } );

    it( 'Update source modal can be closed', () => {
        cy.loginAsAdmin();
        cy.visit( '/wp-admin/plugins.php' );

        // Open the modal.
        cy.get( '.wpst-update-source-selector' ).first().click();
        cy.get( '#wpst-update-source-modal' ).should( 'be.visible' );

        // Close the modal via the close button.
        cy.get( '#wpst-update-source-modal .wpst-modal-close' ).click();
        cy.get( '#wpst-update-source-modal' ).should( 'not.be.visible' );
    } );
} );
