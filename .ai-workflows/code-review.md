# Code Review Guide for AI Assistants

This document provides guidance for AI assistants to help with code review for the Fix Plugin Does Not Exist Notices plugin.

## Code Review Checklist

When reviewing code, check for the following:

### Functionality

- [ ] Does the code work as expected?
- [ ] Does it handle edge cases appropriately?
- [ ] Are there any logical errors?
- [ ] Is error handling implemented properly?

### Code Quality

- [ ] Does the code follow WordPress coding standards?
- [ ] Is the code well-organized and easy to understand?
- [ ] Are there any code smells (duplicate code, overly complex functions, etc.)?
- [ ] Are functions and variables named appropriately?
- [ ] Are there appropriate comments and documentation?

### Security

- [ ] Is user input properly validated and sanitized?
- [ ] Is output properly escaped?
- [ ] Are capability checks used for user actions?
- [ ] Are nonces used for form submissions?
- [ ] Are there any potential SQL injection vulnerabilities?
- [ ] Are there any potential XSS vulnerabilities?

### Performance

- [ ] Are there any performance bottlenecks?
- [ ] Are database queries optimized?
- [ ] Is caching used appropriately?
- [ ] Are assets (CSS, JS) properly enqueued?

### Compatibility

- [ ] Is the code compatible with the minimum supported WordPress version (5.0)?
- [ ] Is the code compatible with the minimum supported PHP version (7.0)?
- [ ] Are there any browser compatibility issues?
- [ ] Are there any conflicts with other plugins?

### Internationalization

- [ ] Are all user-facing strings translatable?
- [ ] Is the correct text domain used?
- [ ] Are translation functions used correctly?

### Accessibility

- [ ] Does the code follow accessibility best practices?
- [ ] Are ARIA attributes used appropriately?
- [ ] Is keyboard navigation supported?
- [ ] Is screen reader support implemented?

## Code Review Process

### 1. Understand the Context

Before reviewing code, understand:

- What problem is the code trying to solve?
- What are the requirements?
- What are the constraints?

### 2. Review the Code

Review the code with the checklist above in mind.

### 3. Provide Feedback

When providing feedback:

- Be specific and clear
- Explain why a change is needed
- Provide examples or suggestions when possible
- Prioritize feedback (critical issues vs. minor improvements)
- Be constructive and respectful

### 4. Follow Up

After the code has been updated:

- Review the changes
- Verify that issues have been addressed
- Provide additional feedback if necessary

## Common Issues to Look For

### PHP Issues

- Undefined variables or functions
- Incorrect function parameters
- Missing return statements
- Improper error handling
- Inefficient loops or conditionals
- Hardcoded values that should be configurable

### WordPress-Specific Issues

- Incorrect hook usage
- Missing or incorrect nonces
- Missing capability checks
- Direct database queries instead of using WordPress functions
- Improper enqueuing of scripts and styles
- Not using WordPress functions for common tasks

### JavaScript Issues

- Undefined variables or functions
- Event listener memory leaks
- jQuery conflicts
- Browser compatibility issues
- Missing error handling

### CSS Issues

- Browser compatibility issues
- Specificity issues
- Unused styles
- Overriding WordPress admin styles inappropriately

## Example Feedback

### Good Feedback Example

```
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

```
This code has security issues and doesn't follow best practices. Fix it.
```
