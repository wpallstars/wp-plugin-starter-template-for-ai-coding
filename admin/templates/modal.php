<?php
/**
 * Modal Template
 *
 * @package WPALLSTARS\PluginStarterTemplate\Admin\Templates
 */

// Ensure this file is loaded within WordPress.
if ( ! defined( 'ABSPATH' ) ) {
	die;
}
?>

<!-- Update Source Modal -->
<div id="wpst-update-source-modal" class="wpst-modal">
	<div class="wpst-modal-content">
		<div class="wpst-modal-header">
			<h2 class="wpst-modal-title"><?php esc_html_e( 'Select Update Source', 'wp-plugin-starter-template' ); ?></h2>
			<span class="wpst-modal-close">&times;</span>
		</div>
		
		<div class="wpst-modal-body">
			<p><?php esc_html_e( 'Choose your preferred source for plugin updates:', 'wp-plugin-starter-template' ); ?></p>
			
			<div class="wpst-modal-message"></div>
			
			<div class="wpst-source-options">
				<?php
				// Get current update source.
				$current_source = get_option( 'wpst_update_source', 'wordpress.org' );
				?>
				
				<label class="wpst-source-option <?php echo 'wordpress.org' === $current_source ? 'selected' : ''; ?>">
					<input type="radio" name="update_source" value="wordpress.org" <?php checked( $current_source, 'wordpress.org' ); ?>>
					<span class="wpst-source-option-label"><?php esc_html_e( 'WordPress.org', 'wp-plugin-starter-template' ); ?></span>
					<div class="wpst-source-option-description"><?php esc_html_e( 'Receive updates from the official WordPress.org repository. Recommended for most users.', 'wp-plugin-starter-template' ); ?></div>
				</label>
				
				<label class="wpst-source-option <?php echo 'github' === $current_source ? 'selected' : ''; ?>">
					<input type="radio" name="update_source" value="github" <?php checked( $current_source, 'github' ); ?>>
					<span class="wpst-source-option-label"><?php esc_html_e( 'GitHub', 'wp-plugin-starter-template' ); ?></span>
					<div class="wpst-source-option-description"><?php esc_html_e( 'Receive updates from the GitHub repository. May include pre-release versions.', 'wp-plugin-starter-template' ); ?></div>
				</label>
				
				<label class="wpst-source-option <?php echo 'gitea' === $current_source ? 'selected' : ''; ?>">
					<input type="radio" name="update_source" value="gitea" <?php checked( $current_source, 'gitea' ); ?>>
					<span class="wpst-source-option-label"><?php esc_html_e( 'Gitea', 'wp-plugin-starter-template' ); ?></span>
					<div class="wpst-source-option-description"><?php esc_html_e( 'Receive updates from the Gitea repository. May include pre-release versions.', 'wp-plugin-starter-template' ); ?></div>
				</label>
			</div>
		</div>
		
		<div class="wpst-modal-footer">
			<button type="button" id="wpst-save-source" class="button button-primary"><?php esc_html_e( 'Save', 'wp-plugin-starter-template' ); ?></button>
		</div>
	</div>
</div>
