/**
 * Admin Scripts
 *
 * @package WPALLSTARS\PluginStarterTemplate
 */

(function ($) {
  'use strict';

  /**
	 * Admin functionality
	 */
  const WPSTAdmin = {
    /**
		 * Initialize
		 */
    init: function () {
      // Initialize components.
      this.initComponents();

      // Bind events.
      this.bindEvents();
    },

    /**
		 * Initialize components
		 */
    initComponents: function () {
      // Initialize any components here.
    },

    /**
		 * Bind events
		 */
    bindEvents: function () {
      // Example: Toggle sections.
      $( '.wpst-toggle-section' ).on( 'click', this.toggleSection );

      // Example: Form submission.
      $( '#wpst-settings-form' ).on( 'submit', this.handleFormSubmit );
    },

    /**
		 * Toggle section visibility
		 *
		 * @param {Event} e Click event
		 */
    toggleSection: function (e) {
      e.preventDefault();

      const $this  = $( this );
      const target = $this.data( 'target' );

      $( target ).slideToggle( 200 );
      $this.toggleClass( 'open' );
    },

    /**
		 * Handle form submission
		 *
		 * @param {Event} e Submit event
		 */
    handleFormSubmit: function (e) {
      e.preventDefault();

      const $form         = $( this );
      const $submitButton = $form.find( 'input[type="submit"]' );
      const formData      = $form.serialize();

      // Disable submit button and show loading state.
      $submitButton.prop( 'disabled', true ).addClass( 'loading' );

      // Send AJAX request.
      $.ajax(
        {
          url: wpstData.ajaxUrl,
          type: 'POST',
          data: {
            action: 'wpst_save_settings',
            nonce: wpstData.nonce,
            formData: formData
          },
          success: function (response) {
            if (response.success) {
              WPSTAdmin.showNotice( 'success', response.data.message );
            } else {
              WPSTAdmin.showNotice( 'error', response.data.message );
            }
          },
          error: function () {
            WPSTAdmin.showNotice( 'error', 'An error occurred. Please try again.' );
          },
          complete: function () {
            // Re-enable submit button and remove loading state.
            $submitButton.prop( 'disabled', false ).removeClass( 'loading' );
          }
        }
      );
    },

    /**
		 * Show admin notice
		 *
		 * @param {string} type Notice type (success, error, warning)
		 * @param {string} message Notice message
		 */
    showNotice: function (type, message) {
      const $notice = $( '<div class="wpst-notice ' + type + '"><p>' + message + '</p></div>' );

      // Add notice to the page.
      $( '.wpst-notices' ).html( $notice );

      // Automatically remove notice after 5 seconds.
      setTimeout(
        function () {
          $notice.fadeOut(
            300,
            function () {
              $( this ).remove();
            }
          );
        },
        5000
      );
    }
  };

  // Initialize when document is ready.
  $( document ).ready(
    function () {
      WPSTAdmin.init();
    }
  );

})( jQuery );
