# Contributing

Thank you for considering contributing to this project! This document provides guidelines and instructions for contributing.

## Code of Conduct

By participating in this project, you agree to abide by our code of conduct:

- Be respectful and inclusive
- Be patient and welcoming
- Be considerate
- Be collaborative
- Be open-minded

## How to Contribute

### Reporting Bugs

If you find a bug, please report it by creating an issue on GitHub:

1. Go to the [Issues](https://github.com/wpallstars/wp-plugin-starter-template-for-ai-coding/issues) page
2. Click "New Issue"
3. Select "Bug Report"
4. Fill out the template with as much detail as possible
5. Submit the issue

Please include:

- A clear, descriptive title
- Steps to reproduce the bug
- Expected behavior
- Actual behavior
- Screenshots (if applicable)
- Your environment (WordPress version, PHP version, browser, etc.)

### Suggesting Enhancements

If you have an idea for an enhancement:

1. Go to the [Issues](https://github.com/wpallstars/wp-plugin-starter-template-for-ai-coding/issues) page
2. Click "New Issue"
3. Select "Feature Request"
4. Fill out the template with as much detail as possible
5. Submit the issue

Please include:

- A clear, descriptive title
- A detailed description of the enhancement
- Why this enhancement would be useful
- Any relevant examples or mockups

### Pull Requests

If you want to contribute code:

1. Fork the repository
2. Create a new branch for your feature or bugfix
3. Make your changes
4. Run tests to ensure your changes don't break anything
5. Submit a pull request

#### Pull Request Process

1. Fork the repository on [GitHub](https://github.com/wpallstars/wp-plugin-starter-template-for-ai-coding/) or [Gitea](https://gitea.wpallstars.com/wpallstars/wp-plugin-starter-template-for-ai-coding/)
2. Clone your fork: `git clone https://github.com/YOUR-USERNAME/wp-plugin-starter-template-for-ai-coding.git`
3. Create your feature branch: `git checkout -b feature/amazing-feature`
4. Make your changes
5. Commit your changes: `git commit -m 'Add some amazing feature'`
6. Push to the branch: `git push origin feature/amazing-feature`
7. Submit a pull request

#### Pull Request Guidelines

- Follow the coding standards (see [Coding Standards](Coding-Standards))
- Write tests for your changes
- Update documentation as needed
- Keep pull requests focused on a single change
- Write a clear, descriptive title and description
- Reference any related issues
- Ensure your code passes the automated code quality checks (see below)

#### Code Quality Tools

This project uses several automated code quality tools to ensure high standards. These tools are free for public repositories and will automatically analyze your code when you create a pull request:

1. **CodeRabbit**: AI-powered code review tool
   - [Website](https://www.coderabbit.ai/)
   - Provides automated feedback on pull requests

2. **CodeFactor**: Continuous code quality monitoring
   - [Website](https://www.codefactor.io/)
   - Provides a grade for your codebase

3. **Codacy**: Code quality and static analysis
   - [Website](https://www.codacy.com/)
   - Identifies issues related to code style, security, and performance

4. **SonarCloud**: Code quality and security analysis
   - [Website](https://sonarcloud.io/)
   - Provides detailed analysis of code quality and security

#### Using AI Assistants with Code Quality Tools

When you receive feedback from these code quality tools, you can use AI assistants to help address the issues:

1. Copy the output from the code quality tool
2. Paste it into your AI assistant chat
3. Ask the AI to help you understand and resolve the issues
4. Apply the suggested fixes
5. Commit the changes and verify that the issues are resolved

Example prompt for AI assistants:

```text
I received the following feedback from [Tool Name]. Please help me understand and resolve these issues:

[Paste the tool output here]
```

## Development Environment

To set up your development environment:

1. Clone the repository: `git clone https://github.com/wpallstars/wp-plugin-starter-template-for-ai-coding.git`
2. Install dependencies: `composer install && npm install`
3. Start the development environment: `npm run start`

### Testing

Before submitting a pull request, make sure to run the tests:

* PHP Unit Tests: `npm run test:php`
* End-to-End Tests: `npm run test:e2e`
* Coding Standards: `npm run lint:php`

#### Code Quality Checks

To ensure your code meets the quality standards, run these commands before submitting a pull request:

* Check coding standards: `composer run phpcs`
* Fix coding standards automatically: `composer run phpcbf`
* Check JavaScript coding standards: `npm run lint:js`
* Check CSS coding standards: `npm run lint:css`

These checks will help identify and fix issues before they are caught by the automated code quality tools in the pull request process.

## Documentation

If you're adding a new feature or changing existing functionality, please update the documentation:

* Update the README.md file if necessary
* Update the readme.txt file if necessary
* Update or create wiki pages as needed
* Update code comments

## Community

Join our community to discuss the project:

* [GitHub Discussions](https://github.com/wpallstars/wp-plugin-starter-template-for-ai-coding/discussions)
* [Gitea Issues](https://gitea.wpallstars.com/wpallstars/wp-plugin-starter-template-for-ai-coding/issues)

## Recognition

Contributors will be recognized in the following ways:

* Added to the contributors list in readme.txt
* Mentioned in release notes for significant contributions
* Thanked in the Changelog for specific contributions

## License

By contributing to this project, you agree that your contributions will be licensed under the project's [GPL-2.0+ License](https://www.gnu.org/licenses/gpl-2.0.html).

## Questions?

If you have any questions about contributing, please open an issue or contact the maintainers.

Thank you for your contributions!
