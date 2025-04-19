# Frequently Asked Questions

This page answers common questions about the WordPress Plugin Starter Template.

## General Questions

### What is the WordPress Plugin Starter Template?

The WordPress Plugin Starter Template is a comprehensive starting point for developing WordPress plugins. It provides a well-structured codebase, documentation templates, and best practices to help you create high-quality WordPress plugins efficiently.

### Who is this template for?

This template is designed for:

- WordPress plugin developers looking for a solid foundation
- Developers who want to leverage AI assistance in their development workflow
- Anyone who wants to create a WordPress plugin following best practices

### Is this template suitable for all types of plugins?

Yes, this template provides a solid foundation for most WordPress plugins. It's designed to be flexible and can be adapted for various types of plugins, from simple utilities to complex applications.

## Usage Questions

### How do I use this template?

This template is meant to be a starting point for your own plugin development. You should:

1. Copy the template files to your new plugin directory
2. Rename files and update namespaces to match your plugin name
3. Update plugin headers in the main PHP file
4. Customize the functionality to meet your specific needs
5. Update documentation to reflect your plugin's features

For detailed instructions, see the [Usage Instructions](Usage-Instructions) page.

### Do I need to keep the original credits?

While not strictly required, we appreciate if you keep a reference to the original template in your plugin's documentation. This helps others discover the template and contributes to the open-source community.

### Can I use this template for commercial plugins?

Yes, you can use this template for both free and commercial plugins. The template is licensed under GPL-2.0+, which allows for commercial use.

## Technical Questions

### What PHP version is required?

The template requires PHP 7.0 or higher, which is the minimum recommended version for WordPress plugins today.

### Does this template support Gutenberg blocks?

The template doesn't include Gutenberg blocks by default, but it provides a structure that makes it easy to add them. You can extend the template to include block registration and block-specific assets.

### How do I add custom post types or taxonomies?

To add custom post types or taxonomies:

1. Create a new class in `includes/` for your post type or taxonomy
2. Register the post type or taxonomy in the class constructor
3. Initialize the class in `includes/plugin.php`

### How do I handle plugin updates?

The template includes an update mechanism that supports multiple sources:

- WordPress.org
- GitHub
- Gitea

To configure the update mechanism:

1. Update the plugin headers in the main PHP file
2. Customize the `updater.php` file if needed
3. Ensure your repository follows the required structure for updates

## AI-Assisted Development Questions

### How does this template support AI-assisted development?

The template includes:

1. Detailed documentation in the `.ai-assistant.md` file
2. Workflow guidelines in the `.ai-workflows/` directory
3. Clear code structure and comments that help AI understand the codebase
4. Best practices for AI-friendly code organization

### What AI tools work best with this template?

This template is designed to work well with various AI coding assistants, including:

- GitHub Copilot
- Claude
- ChatGPT
- Other AI coding assistants

### How do I use the AI workflow documentation?

The AI workflow documentation in the `.ai-workflows/` directory provides guidelines for AI assistants working with this template. These files help ensure consistent, high-quality code and documentation when using AI tools for development.

## Contributing Questions

### How can I contribute to this template?

Contributions are welcome! Please feel free to:

1. Report bugs or issues
2. Suggest new features or improvements
3. Submit pull requests with bug fixes or enhancements

For more information, see the [Contributing](Contributing) page.

### Where can I report issues?

You can report issues on the [GitHub repository](https://github.com/wpallstars/wp-plugin-starter-template-for-ai-coding/issues).

### Is there a roadmap for future development?

Yes, we maintain a roadmap of planned features and improvements. You can find it in the [GitHub repository](https://github.com/wpallstars/wp-plugin-starter-template-for-ai-coding/projects).
