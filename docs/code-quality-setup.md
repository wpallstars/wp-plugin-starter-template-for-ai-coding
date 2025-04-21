# Code Quality Tools Setup

This document explains how to set up and use the code quality tools for this project.

## Prerequisites

* PHP 7.4 or higher
* Composer

## Installation

1. Clone the repository:
   ```bash
   git clone https://github.com/wpallstars/wp-plugin-starter-template-for-ai-coding.git
   cd wp-plugin-starter-template-for-ai-coding
   ```

2. Install dependencies:
   ```bash
   composer install
   ```

## Available Tools

### PHP CodeSniffer (PHPCS)

PHPCS checks your code against the WordPress Coding Standards.

```bash
# Run PHPCS
composer phpcs

# Run PHPCS with a simplified ruleset
composer phpcs:simple
```

### PHP Code Beautifier and Fixer (PHPCBF)

PHPCBF automatically fixes coding standard violations.

```bash
# Run PHPCBF to fix coding standard violations
composer phpcbf

# Run PHPCBF with a simplified ruleset
composer phpcbf:simple
```

### PHPStan

PHPStan performs static analysis to find bugs in your code.

```bash
# Run PHPStan
composer phpstan
```

### PHP Mess Detector (PHPMD)

PHPMD detects potential problems in your code.

```bash
# Run PHPMD
composer phpmd
```

### Running All Linters

```bash
# Run all linters (PHPCS, PHPStan, PHPMD)
composer lint
```

### Running All Fixers

```bash
# Run all fixers (PHPCBF)
composer fix
```

## Environment Variables

For SonarCloud and Codacy integration, you need to set up the following environment variables:

### SonarCloud

```bash
export SONAR_TOKEN=your_sonar_token
```

### Codacy

```bash
export CODACY_PROJECT_TOKEN=your_codacy_token
```

## CI/CD Integration

The project includes GitHub Actions workflows for running these tools automatically on each push and pull request. See the `.github/workflows/code-quality.yml` file for details.

## Customization

* PHPCS rules can be customized in `phpcs.xml`
* PHPStan configuration is in `phpstan.neon`
* SonarCloud configuration is in `sonar-project.properties`
