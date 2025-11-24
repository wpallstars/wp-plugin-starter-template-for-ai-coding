# Code Quality Checks Workflow

## Scope

This document is intended for plugin developers and code reviewers working on this repository. It outlines the process for ensuring code quality before pushing changes to the repository. Following these steps will help catch issues early and save time in the review process.

## Pre-Push Checklist

Before pushing your changes to the repository, run through the following checks:

1. **Run Unit Tests**

   ```bash
   composer test
   ```

   Ensure all tests pass. If any tests fail, resolve the issues before proceeding.

2. **Run PHP CodeSniffer**

   ```bash
   composer phpcs
   ```

   This will check your code against WordPress coding standards. Fix any issues before proceeding.

3. **Run PHP Code Beautifier and Fixer**

   ```bash
   composer phpcbf
   ```

   This will automatically fix many coding standard issues.

4. **Run PHPStan**

   ```bash
   composer phpstan
   ```

   This will perform static analysis on your code to find potential bugs and issues.

5. **Run PHP Mess Detector**

   ```bash
   composer phpmd
   ```

   This will check for potential problems like unused variables, empty catch blocks, etc.

## Common Issues and How to Fix Them

### 1. Inline Comments

All inline comments must end with proper punctuation (period, exclamation mark, or question mark).

```php
// Incorrect comment
$var = true;

// Correct comment.
$var = true;
```

### 2. Superglobal Access

Never access superglobals like `$_GET`, `$_POST`, etc. directly. Always use WordPress functions to sanitize and validate input.

```php
// Incorrect
$page = $_GET['page'];

// Correct
$page = filter_input(INPUT_GET, 'page', FILTER_SANITIZE_FULL_SPECIAL_CHARS);

// For testing environments
if (defined('PHPUNIT_RUNNING') && PHPUNIT_RUNNING) {
    // phpcs:ignore WordPress.Security.ValidatedSanitizedInput.InputNotSanitized -- This rule is ignored in tests to allow direct access for testing purposes
    $page = isset($_GET['page']) ? wp_unslash($_GET['page']) : '';
}
```

### 3. Avoid Unnecessary Else Clauses

Simplify your code by avoiding unnecessary else clauses.

```php
// Less preferred
if (condition) {
    return true;
} else {
    return false;
}

// Preferred
if (condition) {
    return true;
}
return false;
```

### 4. Proper Function Spacing

Ensure proper spacing in function calls and declarations.

```php
// Incorrect
function_name($param1,$param2);

// Correct
function_name( $param1, $param2 );
```

### 5. Naming Conventions

Follow WordPress naming conventions:

* Functions and variables: snake_case with plugin-specific prefix (e.g., `myplugin_function_name`)
* Classes: CamelCase
* Constants: UPPERCASE_WITH_UNDERSCORES with plugin-specific prefix (e.g., `MYPLUGIN_CONSTANT_NAME`)

## Automated Checks in CI/CD

Our CI/CD pipeline includes the following automated checks:

1. **CodeFactor**: Analyzes code quality and style
2. **Codacy**: Performs static code analysis
3. **SonarCloud**: Checks for code smells, bugs, and security vulnerabilities
4. **CodeRabbit**: Provides AI-powered code review

Although CI runs these checks, catching issues locally helps save time and minimize follow-up commits.

## Using AI to Help with Code Quality

You can use AI assistants to help improve code quality:

1. Run the code quality checks locally
2. If issues are found, ask the AI assistant to help fix them
3. Apply the suggested fixes
4. Run the checks again to verify the issues are resolved

Example prompt:

```text
I ran PHPCS and got the following errors. Can you help me fix them?

[Paste error output here]
```

For more AI assistance guidelines, see the [AI Assistant Guide](./../AGENTS.md).

## Conclusion

This workflow helps maintain high code quality and accelerates the review process. Remember, it's always more efficient to resolve issues locally than to go through multiple rounds of CI/CD and code review.
