# Code Review Guide for AI Assistants

This document provides guidance for AI assistants to help with code review for this project.

## Code Review Checklist

When reviewing code, check for the following:

### Functionality

* [ ] Does the code work as expected?
* [ ] Does it handle edge cases appropriately?
* [ ] Are there any logical errors?
* [ ] Is error handling implemented properly?

### Code Quality

* [ ] Does the code follow WordPress coding standards?
* [ ] Is the code well-organized and easy to understand?
* [ ] Are there any code smells (duplicate code, overly complex functions, etc.)?
* [ ] Are functions and variables named appropriately?
* [ ] Are there appropriate comments and documentation?

### Security

* [ ] Is user input properly validated and sanitized?
* [ ] Is output properly escaped?
* [ ] Are capability checks used for user actions?
* [ ] Are nonces used for form submissions?
* [ ] Are there any potential SQL injection vulnerabilities?
* [ ] Are there any potential XSS vulnerabilities?

### Performance

* [ ] Are there any performance bottlenecks?
* [ ] Are database queries optimized?
* [ ] Is caching used appropriately?
* [ ] Are assets (CSS, JS) properly enqueued?

### Compatibility

* [ ] Is the code compatible with the minimum supported WordPress version (5.0)?
* [ ] Is the code compatible with the minimum supported PHP version (7.0)?
* [ ] Are there any browser compatibility issues?
* [ ] Are there any conflicts with other plugins?

### Internationalization

* [ ] Are all user-facing strings translatable?
* [ ] Is the correct text domain used?
* [ ] Are translation functions used correctly?

### Accessibility

* [ ] Does the code follow accessibility best practices?
* [ ] Are ARIA attributes used appropriately?
* [ ] Is keyboard navigation supported?
* [ ] Is screen reader support implemented?

## Automated Code Review Tools

This project uses several automated code review tools to maintain high code quality standards. These tools are free to use for public repositories and should be integrated into any new repositories based on this template.

### 1. CodeRabbit

[CodeRabbit](https://www.coderabbit.ai/) is an AI-powered code review tool that provides automated feedback on pull requests.

* **Integration**: Add the CodeRabbit GitHub App to your repository
* **Benefits**: Provides AI-powered code reviews, identifies potential issues, and suggests improvements
* **Usage**: CodeRabbit automatically reviews pull requests when they are created or updated

### 2. CodeFactor

[CodeFactor](https://www.codefactor.io/) continuously monitors code quality and provides feedback on code style, complexity, and potential issues.

* **Integration**: Add the CodeFactor GitHub App to your repository
* **Benefits**: Provides a grade for your codebase, identifies issues, and tracks code quality over time
* **Usage**: CodeFactor automatically analyzes your codebase and provides feedback on pull requests

### 3. Codacy

[Codacy](https://www.codacy.com/) is a code quality tool that provides static analysis, code coverage, and code duplication detection.

* **Integration**: Add the Codacy GitHub App to your repository
* **Benefits**: Provides a grade for your codebase, identifies issues, and tracks code quality over time
* **Usage**: Codacy automatically analyzes your codebase and provides feedback on pull requests

### 4. PHPStan

[PHPStan](https://phpstan.org/) is a static analysis tool that finds errors in your code without running it.

* **Integration**: Included in the project's composer.json and GitHub Actions workflow
* **Benefits**: Detects undefined variables, methods, and properties; type-related issues; and logical errors
* **Usage**: Run `composer phpstan` or `npm run lint:phpstan` locally, or let GitHub Actions run it automatically

### 5. PHP Mess Detector

[PHP Mess Detector](https://phpmd.org/) is a tool that looks for potential problems in your code such as possible bugs, suboptimal code, overcomplicated expressions, and unused parameters, variables, and methods.

* **Integration**: Included in the project's composer.json and GitHub Actions workflow
* **Benefits**: Identifies code smells, complexity issues, unused code, naming problems, and more
* **Usage**: Run `composer phpmd` or `npm run lint:phpmd` locally, or let GitHub Actions run it automatically

### Using AI Assistants with Code Review Tools

When you receive feedback from these code review tools, you can use AI assistants to help address the issues:

1. Copy the output from the code review tool
2. Paste it into your AI assistant chat
3. Ask the AI to help you understand and resolve the issues
4. Apply the suggested fixes
5. Commit the changes and verify that the issues are resolved

### Markdown Formatting Standards

When writing or updating Markdown files in this project, follow these standards:

* Always use asterisks (*) for bullet points, not hyphens (-)
* Use proper heading hierarchy (# for main title, ## for sections, etc.)
* Use code blocks with language specification for code examples
* Use relative links for internal documentation
* Include alt text for images

Example prompt for AI assistants:

```text
I received the following feedback from [Tool Name]. Please help me understand and resolve these issues:

[Paste the tool output here]
```

## Code Review Process

### 1. Understand the Context

Before reviewing code, understand:

* What problem is the code trying to solve?
* What are the requirements?
* What are the constraints?

### 2. Review the Code

Review the code with the checklist above in mind.

### 3. Provide Feedback

When providing feedback:

* Be specific and clear
* Explain why a change is needed
* Provide examples or suggestions when possible
* Prioritize feedback (critical issues vs. minor improvements)
* Be constructive and respectful

### 4. Follow Up

After the code has been updated:

* Review the changes
* Verify that issues have been addressed
* Provide additional feedback if necessary

## Common Issues to Look For

### PHP Issues

* Undefined variables or functions
* Incorrect function parameters
* Missing return statements
* Improper error handling
* Inefficient loops or conditionals
* Hardcoded values that should be configurable

### WordPress-Specific Issues

* Incorrect hook usage
* Missing or incorrect nonces
* Missing capability checks
* Direct database queries instead of using WordPress functions
* Improper enqueuing of scripts and styles
* Not using WordPress functions for common tasks

### JavaScript Issues

* Undefined variables or functions
* Event listener memory leaks
* jQuery conflicts
* Browser compatibility issues
* Missing error handling

### CSS Issues

* Browser compatibility issues
* Specificity issues
* Unused styles
* Overriding WordPress admin styles inappropriately

## Example Feedback

### Good Feedback Example

```markdown
In function `handle_remove_reference()`:

1. The nonce check is missing, which could lead to CSRF vulnerabilities.
   Consider adding:
   ```php
   if (!isset($_GET['_wpnonce']) || !wp_verify_nonce($_GET['_wpnonce'], 'fpden_remove_reference')) {
       wp_die(__('Security check failed.', 'fix-plugin-does-not-exist-notices'));
   }
   ```

2. The user capability check should be more specific. Instead of:
   ```php
   if (!current_user_can('manage_options')) {
   ```
   Consider using:
   ```php
   if (!current_user_can('activate_plugins')) {
   ```
   This is more appropriate for the action being performed.

3. The success message should be translatable:
   ```php
   // Change this:
   add_settings_error('fpden', 'fpden_removed', 'Plugin reference removed successfully.', 'updated');

   // To this:
   add_settings_error('fpden', 'fpden_removed', __('Plugin reference removed successfully.', 'fix-plugin-does-not-exist-notices'), 'updated');
   ```
```

### Poor Feedback Example

```text
This code has security issues and doesn't follow best practices. Fix it.
```
