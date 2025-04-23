# Error Checking and Feedback Loops

This document explains how to check for code quality issues and get feedback from automated tools in our development workflow.

## Table of Contents

* [Overview](#overview)
* [Local Error Checking](#local-error-checking)
* [CI/CD Feedback Loops](#cicd-feedback-loops)
* [Common Issues and Solutions](#common-issues-and-solutions)
* [Improving Code Quality](#improving-code-quality)

## Overview

Our development process includes multiple layers of error checking and feedback loops to ensure high code quality:

1. **Local Development**: Run linters and tests locally before committing
2. **Pull Request**: Automated checks run when you create or update a PR
3. **Code Review**: Human reviewers provide feedback on your code
4. **Continuous Integration**: Tests run in various environments to ensure compatibility

## Local Error Checking

### PHP Code Quality Checks

Run these commands locally to check for PHP code quality issues:

```bash
# Run all PHP code quality checks
npm run lint:php

# Run specific checks
npm run lint:phpcs    # PHP CodeSniffer
npm run lint:phpstan  # PHPStan static analysis
npm run lint:phpmd    # PHP Mess Detector
```

### JavaScript/CSS Checks

```bash
# Run ESLint for JavaScript files
npm run lint:js

# Run stylelint for CSS files
npm run lint:css
```

### Running Tests Locally

```bash
# Run Cypress tests for single site
npm run test:playground:single

# Run Cypress tests for multisite
npm run test:playground:multisite
```

## CI/CD Feedback Loops

When you push code or create a pull request, several automated checks run:

### GitHub Actions Workflows

* **Code Quality**: Runs PHP CodeSniffer, PHPStan, and PHP Mess Detector
* **WordPress Tests**: Runs tests in WordPress environments
* **WordPress Playground Tests**: Runs tests in WordPress Playground environments
* **Tests - Run PHP compatibility and unit tests**: Checks compatibility with different PHP versions

### Third-Party Code Quality Services

* **CodeFactor**: Provides automated code reviews and quality grades
* **Codacy**: Analyzes code quality and security issues
* **SonarCloud**: Detects bugs, vulnerabilities, and code smells

## Common Issues and Solutions

### PHP CodeSniffer Issues

* **Indentation**: Use tabs for indentation in PHP files
* **Spacing**: Add spaces after commas, around operators, and after control structures
* **Naming Conventions**: Use snake_case for functions and variables in PHP
* **DocBlocks**: Add proper documentation for functions and classes

### PHPStan Issues

* **Undefined Variables**: Ensure all variables are defined before use
* **Type Errors**: Use proper type hints and return types
* **Null Checks**: Add null checks for variables that might be null

### JavaScript/CSS Issues

* **ESLint Errors**: Follow JavaScript best practices
* **Stylelint Errors**: Follow CSS best practices
* **Accessibility Issues**: Ensure UI elements are accessible

## Improving Code Quality

### Best Practices

* **Write Tests First**: Use test-driven development (TDD) when possible
* **Small PRs**: Keep pull requests small and focused on a single issue
* **Regular Commits**: Commit frequently with clear messages
* **Code Reviews**: Request code reviews from team members
* **Documentation**: Keep documentation up-to-date

### Using AI Assistants

AI assistants can help you understand and fix code quality issues:

1. Copy the error message or feedback
2. Paste it into your AI assistant chat
3. Ask for help understanding and fixing the issue
4. Apply the suggested fixes
5. Run the checks again to verify the issue is resolved

### Continuous Learning

* Review the code quality reports regularly
* Learn from feedback and improve your coding practices
* Stay updated on best practices for WordPress development

## Related Documentation

* [Testing Framework](Testing.md)
* [Code Review Guide](../.ai-workflows/code-review.md)
* [Architecture Overview](Architecture-Overview.md)
