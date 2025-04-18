# WordPress Plugin Starter Template for AI Coding

A comprehensive starter template for WordPress plugins with best practices for AI-assisted development.

[![WordPress Plugin Version](https://img.shields.io/wordpress/plugin/v/wp-plugin-starter-template-for-ai-coding)](https://wordpress.org/plugins/wp-plugin-starter-template-for-ai-coding/)
[![WordPress Plugin Rating](https://img.shields.io/wordpress/plugin/rating/wp-plugin-starter-template-for-ai-coding)](https://wordpress.org/plugins/wp-plugin-starter-template-for-ai-coding/)
[![WordPress Plugin Downloads](https://img.shields.io/wordpress/plugin/dt/wp-plugin-starter-template-for-ai-coding)](https://wordpress.org/plugins/wp-plugin-starter-template-for-ai-coding/)
[![License](https://img.shields.io/github/license/wpallstars/wp-plugin-starter-template-for-ai-coding)](https://github.com/wpallstars/wp-plugin-starter-template-for-ai-coding/blob/main/LICENSE)

## Description

The WordPress Plugin Starter Template provides a solid foundation for developing WordPress plugins with AI assistance. It includes a well-structured codebase, documentation templates, and best practices to help you create high-quality WordPress plugins efficiently.

### Key Features

- **Well-structured codebase** following WordPress coding standards
- **Modular architecture** for easy maintenance and extension
- **Comprehensive documentation** templates for both users and developers
- **AI-friendly workflows** with detailed guidance for AI assistants
- **Git integration** with GitHub and Gitea support
- **Update mechanism** with multiple source options (WordPress.org, GitHub, Gitea)
- **Internationalization** ready with proper text domain setup
- **Admin interface** components for building settings pages

### For Developers

This template is designed to be a starting point for your WordPress plugin development. It provides:

- A clean, well-organized file structure
- OOP approach with namespaced classes
- Separation of concerns (admin, core functionality)
- Documentation templates for wiki and readme files
- GitHub Actions workflows for automated tasks
- AI workflow documentation for AI-assisted development

## Installation

### From GitHub

1. Download the latest release from the [GitHub repository](https://github.com/wpallstars/wp-plugin-starter-template-for-ai-coding/releases)
2. Upload the plugin files to the `/wp-content/plugins/wp-plugin-starter-template` directory, or install the plugin through the WordPress plugins screen directly
3. Activate the plugin through the 'Plugins' screen in WordPress

### Using as a Template for Your Plugin

1. Clone or download this repository
2. Rename the plugin directory and files to match your plugin name
3. Update namespaces, function prefixes, and text domains
4. Update plugin headers in the main PHP file
5. Customize the functionality to meet your specific needs
6. Update documentation to reflect your plugin's features

## Usage

### Basic Structure

The template follows a modular structure:

- `wp-plugin-starter-template.php`: Main plugin file with plugin headers
- `includes/`: Core plugin functionality
  - `plugin.php`: Main plugin class that initializes everything
  - `core.php`: Core functionality class
  - `updater.php`: Update mechanism for multiple sources
- `admin/`: Admin-specific functionality
  - `lib/`: Admin classes
  - `css/`: Admin stylesheets
  - `js/`: Admin JavaScript files
- `languages/`: Translation files
- `.github/workflows/`: GitHub Actions workflows
- `.ai-workflows/`: Documentation for AI assistants
- `.wiki/`: Wiki documentation templates

### Customizing for Your Plugin

1. **Rename Files and Update Namespaces**:
   - Rename `wp-plugin-starter-template.php` to your plugin name
   - Update the namespace from `WPALLSTARS\PluginStarterTemplate` to your own
   - Update text domain from `wp-plugin-starter-template` to your own

2. **Update Plugin Headers**:
   - Edit the plugin headers in the main PHP file
   - Update GitHub/Gitea repository URLs

3. **Customize Functionality**:
   - Modify the core functionality in `includes/core.php`
   - Add your own classes as needed
   - Customize admin interfaces in the `admin/` directory

4. **Update Documentation**:
   - Update README.md and readme.txt with your plugin information
   - Customize wiki documentation in the `.wiki/` directory

## Documentation

Comprehensive documentation is available in the [Wiki](https://github.com/wpallstars/wp-plugin-starter-template-for-ai-coding/wiki).

### For Users

- [Installation Guide](https://github.com/wpallstars/wp-plugin-starter-template-for-ai-coding/wiki/Installation-Guide)
- [Usage Instructions](https://github.com/wpallstars/wp-plugin-starter-template-for-ai-coding/wiki/Usage-Instructions)
- [Frequently Asked Questions](https://github.com/wpallstars/wp-plugin-starter-template-for-ai-coding/wiki/Frequently-Asked-Questions)
- [Troubleshooting](https://github.com/wpallstars/wp-plugin-starter-template-for-ai-coding/wiki/Troubleshooting)

### For Developers

- [Architecture Overview](https://github.com/wpallstars/wp-plugin-starter-template-for-ai-coding/wiki/Architecture-Overview)
- [Extending the Plugin](https://github.com/wpallstars/wp-plugin-starter-template-for-ai-coding/wiki/Extending-the-Plugin)
- [Coding Standards](https://github.com/wpallstars/wp-plugin-starter-template-for-ai-coding/wiki/Coding-Standards)
- [Release Process](https://github.com/wpallstars/wp-plugin-starter-template-for-ai-coding/wiki/Release-Process)

### For AI Assistants

The `.ai-assistant.md` file and `.ai-workflows/` directory contain detailed guidance for AI assistants working with this template. These resources help ensure consistent, high-quality code and documentation when using AI tools for development.

## Contributing

Contributions are welcome! Please feel free to submit a pull request or open an issue on the [GitHub repository](https://github.com/wpallstars/wp-plugin-starter-template-for-ai-coding).

### Development Process

1. Fork the repository
2. Create a feature branch: `git checkout -b feature/your-feature-name`
3. Make your changes and commit them: `git commit -m 'Add some feature'`
4. Push to the branch: `git push origin feature/your-feature-name`
5. Submit a pull request

## Credits

This template is maintained by [WPALLSTARS](https://www.wpallstars.com) and is based on the experience and best practices developed while creating the [Fix 'Plugin file does not exist' Notices](https://github.com/wpallstars/wp-fix-plugin-does-not-exist-notices) plugin.

## License

This project is licensed under the GPL-2.0+ License - see the [LICENSE](LICENSE) file for details.

## Changelog

### 0.1.0
- Initial release with basic template structure
- Added core plugin architecture
- Added admin interface components
- Added documentation templates
- Added AI workflow documentation
