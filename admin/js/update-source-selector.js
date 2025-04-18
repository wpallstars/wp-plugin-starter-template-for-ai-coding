/**
 * Update Source Selector Scripts
 *
 * @package WPALLSTARS\PluginStarterTemplate
 */

(function ($) {
	'use strict';

	/**
	 * Update Source Selector functionality
	 */
	const WPSTUpdateSourceSelector = {
		/**
		 * Modal element
		 */
		$modal: null,

		/**
		 * Selected source
		 */
		selectedSource: '',

		/**
		 * Initialize
		 */
		init: function () {
			// Cache DOM elements.
			this.$modal = $( '#wpst-update-source-modal' );

			// Bind events.
			this.bindEvents();
		},

		/**
		 * Bind events
		 */
		bindEvents: function () {
			// Open modal when clicking on the update source link.
			$( document ).on( 'click', '.wpst-update-source-selector', this.openModal.bind( this ) );

			// Close modal when clicking on the close button or outside the modal.
			this.$modal.on( 'click', '.wpst-modal-close', this.closeModal.bind( this ) );
			$( document ).on(
				'click',
				'.wpst-modal',
				function (e) {
					if ($( e.target ).hasClass( 'wpst-modal' )) {
						WPSTUpdateSourceSelector.closeModal();
					}
				}
			);

			// Select source option.
			this.$modal.on( 'click', '.wpst-source-option', this.selectSource.bind( this ) );

			// Save source selection.
			this.$modal.on( 'click', '#wpst-save-source', this.saveSource.bind( this ) );
		},

		/**
		 * Open the modal
		 *
		 * @param {Event} e Click event
		 */
		openModal: function (e) {
			e.preventDefault();
			this.$modal.show();
		},

		/**
		 * Close the modal
		 */
		closeModal: function () {
			this.$modal.hide();
		},

		/**
		 * Select a source option
		 *
		 * @param {Event} e Click event
		 */
		selectSource: function (e) {
			const $option = $( e.currentTarget );

			// Update selected state.
			this.$modal.find( '.wpst-source-option' ).removeClass( 'selected' );
			$option.addClass( 'selected' );

			// Update radio button.
			$option.find( 'input[type="radio"]' ).prop( 'checked', true );

			// Store selected source.
			this.selectedSource = $option.find( 'input[type="radio"]' ).val();
		},

		/**
		 * Save the selected source
		 */
		saveSource: function () {
			// Validate selection.
			if ( ! this.selectedSource) {
				this.showMessage( 'error', 'Please select an update source.' );
				return;
			}

			// Show loading state.
			const $saveButton = $( '#wpst-save-source' );
			$saveButton.prop( 'disabled', true ).html( '<span class="wpst-loading"></span> Saving...' );

			// Send AJAX request.
			$.ajax(
				{
					url: wpstModalData.ajaxUrl, // WordPress AJAX URL.
					type: 'POST',
					data: {
						action: 'wpst_set_update_source', // AJAX action hook.
						nonce: wpstModalData.nonce, // Security nonce.
						source: this.selectedSource
					},
					success: function (response) {
						if (response.success) {
							WPSTUpdateSourceSelector.showMessage( 'success', response.data.message );

							// Close modal after a short delay.
							setTimeout(
								function () {
									WPSTUpdateSourceSelector.closeModal();
								},
								1500
							);
						} else {
							WPSTUpdateSourceSelector.showMessage( 'error', response.data.message );
						}
					},
					error: function () {
						WPSTUpdateSourceSelector.showMessage( 'error', 'An error occurred. Please try again.' );
					},
					complete: function () {
						// Reset button state.
						$saveButton.prop( 'disabled', false ).text( wpstModalData.i18n.confirm );
					}
				}
			);
		},

		/**
		 * Show a message in the modal
		 *
		 * @param {string} type Message type (success, error)
		 * @param {string} message Message text
		 */
		showMessage: function (type, message) {
			const $message = this.$modal.find( '.wpst-modal-message' );

			// Set message content and type.
			$message.html( message ).removeClass( 'success error' ).addClass( type ).show();

			// Hide message after a delay for success messages.
			if (type === 'success') {
				setTimeout(
					function () {
						$message.fadeOut( 300 );
					},
					3000
				);
			}
		}
	};

	// Initialize when document is ready.
	$( document ).ready(
		function () {
			WPSTUpdateSourceSelector.init();
		}
	);

})( jQuery );
