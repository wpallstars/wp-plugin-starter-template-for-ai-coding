# Coding Standards

This document outlines the coding standards used in this plugin. Following these standards ensures consistency, readability, and maintainability of the codebase.

## PHP Coding Standards

This plugin follows the [WordPress Coding Standards](https://developer.wordpress.org/coding-standards/wordpress-coding-standards/php/) with some additional guidelines.

### File Structure

- Each PHP file should begin with the PHP opening tag `<?php` (no closing tag)
- Files should use the Unix line endings (LF)
- Files should be encoded in UTF-8 without BOM

### Naming Conventions

- **Classes**: Use `PascalCase` for class names
  ```php
  class MyClassName {}
  ```

- **Methods and Functions**: Use `snake_case` for method and function names
  ```php
  function my_function_name() {}
  public function my_method_name() {}
  ```

- **Variables**: Use `snake_case` for variable names
  ```php
  $my_variable_name = 'value';
  ```

- **Constants**: Use `UPPERCASE_WITH_UNDERSCORES` for constants
  ```php
  define('MY_CONSTANT', 'value');
  const MY_CLASS_CONSTANT = 'value';
  ```

- **Namespaces**: Use `PascalCase` for namespace segments
  ```php
  namespace WPALLSTARS\PluginStarterTemplate;
  ```

- **Hooks**: Prefix hooks with the plugin's prefix
  ```php
  do_action('wpst_hook_name');
  apply_filters('wpst_filter_name', $value);
  ```

### Indentation and Formatting

- Use 4 spaces for indentation (not tabs)
- Opening braces for classes and functions should be on the same line
- Control structures should have one space between the statement and the opening parenthesis
- Each line should be no longer than 100 characters

```php
if ($condition) {
    // Code here
} elseif ($another_condition) {
    // More code
} else {
    // Default code
}
```

### Documentation

- All classes, methods, and functions should be documented using PHPDoc
- Include a description, parameters, return values, and exceptions

```php
/**
 * Short description of the function.
 *
 * Longer description if needed.
 *
 * @param string $param1 Description of the parameter.
 * @param int    $param2 Description of the parameter.
 * @return bool Description of the return value.
 * @throws Exception When something goes wrong.
 */
function my_function($param1, $param2) {
    // Function code
}
```

### Object-Oriented Programming

- Each class should have a single responsibility
- Use visibility declarations for all properties and methods (public, protected, private)
- Use type hints for parameters and return types when possible

```php
class MyClass {
    /**
     * Property description.
     *
     * @var string
     */
    private $property;

    /**
     * Method description.
     *
     * @param string $param Description of the parameter.
     * @return bool Description of the return value.
     */
    public function my_method(string $param): bool {
        // Method code
    }
}
```

## JavaScript Coding Standards

This plugin follows the [WordPress JavaScript Coding Standards](https://developer.wordpress.org/coding-standards/wordpress-coding-standards/javascript/).

### Naming Conventions

- **Variables and Functions**: Use `camelCase` for variable and function names
  ```javascript
  var myVariableName = 'value';
  function myFunctionName() {}
  ```

- **Constants**: Use `UPPERCASE_WITH_UNDERSCORES` for constants
  ```javascript
  var MY_CONSTANT = 'value';
  ```

### Indentation and Formatting

- Use 4 spaces for indentation (not tabs)
- Opening braces should be on the same line as the statement
- Each line should be no longer than 100 characters

```javascript
if (condition) {
    // Code here
} else if (anotherCondition) {
    // More code
} else {
    // Default code
}
```

### Documentation

- Use JSDoc for documenting functions and objects

```javascript
/**
 * Short description of the function.
 *
 * @param {string} param1 - Description of the parameter.
 * @param {number} param2 - Description of the parameter.
 * @returns {boolean} Description of the return value.
 */
function myFunction(param1, param2) {
    // Function code
}
```

## CSS Coding Standards

This plugin follows the [WordPress CSS Coding Standards](https://developer.wordpress.org/coding-standards/wordpress-coding-standards/css/).

### Naming Conventions

- Use lowercase for selectors
- Use hyphens to separate words in class and ID names
- Prefix classes and IDs with the plugin's prefix

```css
.wpst-container {
    margin: 0;
}

#wpst-header {
    padding: 10px;
}
```

### Indentation and Formatting

- Use 4 spaces for indentation (not tabs)
- Each property should be on its own line
- Include a space after the colon in property declarations
- End each declaration with a semicolon
- Use single quotes for attribute selectors and property values

```css
.wpst-container {
    margin: 0;
    padding: 10px;
    font-family: 'Helvetica', sans-serif;
}
```

## Automated Code Checking

This plugin uses automated tools to enforce coding standards:

1. **PHP_CodeSniffer (PHPCS)**: Checks PHP code against the WordPress Coding Standards
   ```bash
   composer run phpcs
   ```

2. **PHP Code Beautifier and Fixer (PHPCBF)**: Automatically fixes some coding standard violations
   ```bash
   composer run phpcbf
   ```

3. **ESLint**: Checks JavaScript code against the WordPress Coding Standards
   ```bash
   npm run lint:js
   ```

4. **Stylelint**: Checks CSS code against the WordPress Coding Standards
   ```bash
   npm run lint:css
   ```

## Conclusion

Following these coding standards ensures that the plugin's code is consistent, readable, and maintainable. All contributors should adhere to these standards when submitting code to the project.
