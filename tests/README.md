# Plugin Tests

This directory contains test files for the plugin.

## Test Structure

- `bootstrap.php`: Sets up the test environment
- `test-core.php`: Tests for the Core class
- `test-admin.php`: Tests for the Admin class
- Add more test files as needed for additional classes

## Running Tests

To run the tests, you need to have PHPUnit and WP Mock installed. You can install them using Composer:

```bash
composer install
```

Then, run the tests:

```bash
./vendor/bin/phpunit
```

## Writing Tests

When writing tests:

1. Create a new file named `test-{class-name}.php` for each class you want to test
2. Extend the `WP_Mock\Tools\TestCase` class
3. Use WP Mock to mock WordPress functions
4. Write test methods for each method in your class

Example:

```php
<?php
use WPALLSTARS\PluginStarterTemplate\YourClass;

class YourClassTest extends WP_Mock\Tools\TestCase {
    public function setUp(): void {
        parent::setUp();
        WP_Mock::setUp();
    }

    public function tearDown(): void {
        WP_Mock::tearDown();
        parent::tearDown();
    }

    public function test_your_method() {
        // Set up mocks
        WP_Mock::userFunction('wp_function', [
            'times' => 1,
            'args' => ['argument'],
            'return' => 'result',
        ]);

        // Create instance of your class
        $instance = new YourClass();

        // Call the method
        $result = $instance->your_method('argument');

        // Assert the result
        $this->assertEquals('expected result', $result);
    }
}
```

## Test Coverage

To generate a test coverage report:

```bash
./vendor/bin/phpunit --coverage-html coverage
```

This will generate an HTML report in the `coverage` directory.

## Continuous Integration

The tests are automatically run on GitHub Actions when you push to the repository. See the `.github/workflows/tests.yml` file for details.
