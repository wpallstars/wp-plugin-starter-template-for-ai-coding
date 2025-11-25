# Error Checking and Feedback Loops

This document outlines the processes for error checking, debugging, and establishing feedback loops.

The goal is to create a seamless, autonomous CI/CD pipeline.

The AI can identify, diagnose, and fix issues with minimal human intervention.

## Table of Contents

* [GitHub Actions Workflow Monitoring](#github-actions-workflow-monitoring)
* [Local Build and Test Feedback](#local-build-and-test-feedback)
* [Code Quality Tool Integration](#code-quality-tool-integration)
* [Automated Error Resolution](#automated-error-resolution)
* [Feedback Loop Architecture](#feedback-loop-architecture)
* [When to Consult Humans](#when-to-consult-humans)

## GitHub Actions Workflow Monitoring

### Checking Workflow Status via GitHub API

AI assistants can directly monitor GitHub Actions workflows using the GitHub API.

This helps identify failures and diagnose issues:

```
github-api /repos/{owner}/{repo}/actions/runs
```

#### Step-by-Step Process

1. **Get Recent Workflow Runs**:
   ```
   github-api /repos/wpallstars/wp-plugin-starter-template-for-ai-coding/actions/runs
   ```

2. **Filter for Failed Runs**:
   ```
   github-api /repos/wpallstars/wp-plugin-starter-template-for-ai-coding/actions/runs?status=failure
   ```

3. **Get Details for a Specific Run**:
   ```
   github-api /repos/wpallstars/wp-plugin-starter-template-for-ai-coding/actions/runs/{run_id}
   ```

4. **Get Jobs for a Workflow Run**:
   ```
   github-api /repos/wpallstars/wp-plugin-starter-template-for-ai-coding/actions/runs/{run_id}/jobs
   ```

5. **Analyze Job Logs** (if accessible via API):
   ```
   github-api /repos/wpallstars/wp-plugin-starter-template-for-ai-coding/actions/jobs/{job_id}/logs
   ```

### Common GitHub Actions Errors and Solutions

#### Missing or Outdated Action Versions

**Error**: `Missing download info for actions/upload-artifact@v3`

**Solution**: Update to the latest version of the action:
```yaml
uses: actions/upload-artifact@v4
```

#### Port Configuration Issues for WordPress Multisite

**Error**: `The current host is 127.0.0.1:8888, but WordPress multisites do not support custom ports.`

**Solution**: Use port 80 for multisite environments:
```yaml
npx @wp-playground/cli server --blueprint playground/multisite-blueprint.json --port 80 --login &
```

#### Artifact Path Syntax Issues

**Error**: Invalid path syntax for artifacts

**Solution**: Use multi-line format for better readability:
```yaml
path: |
  cypress/videos
  cypress/screenshots
```

#### Concurrency Control

**Problem**: Redundant workflow runs when multiple commits land quickly

**Solution**: Add concurrency control to cancel in-progress runs:
```yaml
concurrency:
  group: playground-tests-${{ github.ref }}
  cancel-in-progress: true
```

## Local Build and Test Feedback

### Monitoring Local Test Runs

AI assistants can monitor local test runs by analyzing the output of test commands.

#### PHP Unit Tests

```bash
composer run phpunit
```

#### Cypress Tests

```bash
npm run test:single
npm run test:multisite
```

#### WordPress Playground Tests

```bash
npm run test:playground:single
npm run test:playground:multisite
```

### Capturing and Analyzing Test Output

1. **Run Tests with Output Capture**:
   ```bash
   npm run test:single > test-output.log 2>&1
   ```

2. **Analyze Output for Errors**:
   ```bash
   cat test-output.log | grep -i 'error\|fail\|exception'
   ```

3. **Parse Structured Test Results** (if available):
   ```bash
   cat cypress/results/results.json
   ```

### Common Local Test Errors and Solutions

#### WordPress Playground Port Issues

**Error**: `The current host is 127.0.0.1:8888, but WordPress multisites do not support custom ports.`

**Solution**: Modify the port in the blueprint or test configuration:
```json
{
  "features": {
    "networking": true
  }
}
```

#### Cypress Selector Errors

**Error**: `Timed out retrying after 4000ms: expected '<body...>' to have class 'wp-admin'`

**Solution**: Update selectors to be more robust and handle login states:
```javascript
cy.get('body').then(($body) => {
  if ($body.hasClass('login')) {
    cy.get('#user_login').type('admin');
    cy.get('#user_pass').type('password');
    cy.get('#wp-submit').click();
  }
});

// Check for admin bar instead of body class
cy.get('#wpadminbar').should('exist');
```

## Code Quality Tool Integration

### Automated Code Quality Checks

AI assistants can integrate with various code quality tools to identify and fix issues.

#### PHPCS (PHP CodeSniffer)

```bash
composer run phpcs
```

#### ESLint (JavaScript)

```bash
npm run lint:js
```

#### Stylelint (CSS)

```bash
npm run lint:css
```

### Parsing Code Quality Tool Output

1. **Run Code Quality Check**:
   ```bash
   composer run phpcs > phpcs-output.log 2>&1
   ```

2. **Analyze Output for Errors**:
   ```bash
   cat phpcs-output.log | grep -i 'ERROR\|WARNING'
   ```

3. **Automatically Fix Issues** (when possible):
   ```bash
   composer run phpcbf
   ```

### Monitoring Code Quality Feedback in Pull Requests

Automated code quality tools often provide feedback directly in pull requests.

AI assistants can check these comments to identify and address issues.

#### Accessing PR Comments via GitHub API

```
github-api /repos/wpallstars/wp-plugin-starter-template-for-ai-coding/pulls/{pull_number}/comments
```

#### Accessing PR Review Comments

```
github-api /repos/wpallstars/wp-plugin-starter-template-for-ai-coding/pulls/{pull_number}/reviews
```

#### Checking CodeRabbit Feedback

CodeRabbit provides AI-powered code review comments via the GitHub API.

1. **Get PR Comments**:
   ```
   github-api /repos/wpallstars/wp-plugin-starter-template-for-ai-coding/pulls/{pull_number}/comments
   ```

2. **Filter for CodeRabbit Comments**:
   Look for comments from the `coderabbitai` user.

3. **Parse Actionable Feedback**:
   * Code quality issues
   * Suggested improvements
   * Best practice recommendations
   * Specific code snippets to fix

#### Checking Codacy and CodeFactor Feedback

These tools provide automated code quality checks and post results as PR comments.

1. **Check PR Status Checks**:
   ```
   github-api /repos/wpallstars/wp-plugin-starter-template-for-ai-coding/commits/{sha}/check-runs
   ```

2. **Get Detailed Reports** (if available via API):
   ```
   github-api /repos/wpallstars/wp-plugin-starter-template-for-ai-coding/commits/{sha}/check-runs/{id}
   ```

3. **Parse Common Issues**:
   * Code style violations
   * Potential bugs
   * Security vulnerabilities
   * Performance issues
   * Duplication

#### Checking SonarCloud Analysis

SonarCloud provides detailed code quality and security analysis.

1. **Check SonarCloud Status**:
   ```
   github-api /repos/wpallstars/wp-plugin-starter-template-for-ai-coding/commits/{sha}/check-runs?check_name=SonarCloud
   ```

2. **Parse SonarCloud Issues**:
   * Code smells
   * Bugs
   * Vulnerabilities
   * Security hotspots
   * Coverage gaps

### Common Code Quality Issues and Solutions

#### WordPress Coding Standards

**Error**: `ERROR: Expected snake_case for function name, but found camelCase`

**Solution**: Rename functions to follow snake_case convention:
```php
// Before
function getPluginVersion() { ... }

// After
function get_plugin_version() { ... }
```

#### Missing Docblocks

**Error**: `ERROR: Missing doc comment for function`

**Solution**: Add proper docblocks:
```php
/**
 * Get the plugin version.
 *
 * @since 1.0.0
 * @return string The plugin version.
 */
function get_plugin_version() { ... }
```

## Automated Error Resolution

### Error Resolution Workflow

1. **Identify Error**: Use GitHub API or local test output to identify errors
2. **Categorize Error**: Determine error type and severity
3. **Search for Solution**: Look for patterns in known solutions
4. **Apply Fix**: Make necessary code changes
5. **Verify Fix**: Run tests again to confirm the issue is resolved
6. **Document Solution**: Update documentation with the solution

### Processing Code Quality Feedback

#### Extracting Actionable Items from PR Comments

1. **Collect All Feedback**:
   ```
   github-api /repos/wpallstars/wp-plugin-starter-template-for-ai-coding/pulls/{number}/comments
   github-api /repos/wpallstars/wp-plugin-starter-template-for-ai-coding/pulls/{number}/reviews
   ```

2. **Categorize Issues**:
   * Critical: Security vulnerabilities, breaking bugs
   * High: Code quality violations, potential bugs
   * Medium: Style issues, best practices
   * Low: Documentation, minor improvements

3. **Prioritize Fixes**:
   * Address critical issues first
   * Group related issues for efficient fixing
   * Consider dependencies between issues

4. **Create Fix Plan**:
   * Document files that need changes
   * Outline specific changes needed
   * Note any potential side effects

#### Responding to Code Quality Tool Comments

1. **Acknowledge Feedback**: React to or reply to comments
2. **Implement Fixes**: Make the necessary code changes
3. **Explain Changes** (if needed): Add comments explaining decisions
4. **Request Review** (if needed): Ask for re-review after fixes

## Feedback Loop Architecture

### Complete Feedback Loop System

```
┌─────────────────┐     ┌─────────────────┐     ┌─────────────────┐
│                 │     │                 │     │                 │
│  Code Changes   │────▶│  Local Testing  │────▶│  GitHub Actions │
│                 │     │                 │     │                 │
└────────┬────────┘     └────────┬────────┘     └────────┬────────┘
         │                       │                       │
         │                       │                       │
         │                       │                       │
┌────────▼────────┐     ┌────────▼────────┐     ┌────────▼────────┐
│                 │     │                 │     │                 │
│  AI Assistant   │◀────│  Error Analysis │◀────│  Status Check   │
│                 │     │                 │     │                 │
└────────┬────────┘     └─────────────────┘     └─────────────────┘
         │
         │
         │
┌────────▼────────┐     ┌─────────────────┐
│                 │     │                 │
│  Fix Generation │────▶│  Human Review   │ (only when necessary)
│                 │     │                 │
└─────────────────┘     └─────────────────┘
```

### Key Components

1. **Code Changes**: Initial code modifications
2. **Local Testing**: Immediate feedback on local environment
3. **GitHub Actions**: Remote CI/CD pipeline validation
4. **Status Check**: Monitoring workflow status via GitHub API
5. **Error Analysis**: Parsing and categorizing errors
6. **AI Assistant**: Central intelligence for error resolution
7. **Fix Generation**: Creating and implementing solutions
8. **Human Review**: Optional step for complex decisions

## Handling Direct Feedback from Code Review Tools

### Accessing and Processing CodeRabbit Feedback

CodeRabbit provides detailed AI-powered code reviews.

These can be directly accessed and processed.

#### Example CodeRabbit Feedback

```
coderabbitai bot left a comment
Actionable comments posted: 1

🧹 Nitpick comments (3)
.github/workflows/playground-tests-fix.yml (3)
9-13: Add concurrency control to avoid redundant runs.
```

#### Processing Steps

1. **Extract Specific Recommendations**:
   * Identify file paths and line numbers
   * Parse suggested code changes
   * Understand the rationale for changes

2. **Implement Recommendations**: Apply the suggested changes

3. **Verify Implementation**:
   * Run local tests if applicable
   * Commit changes with descriptive message
   * Monitor CI/CD pipeline for success

### Handling SonarCloud and Codacy Feedback

These tools provide structured feedback that can be systematically addressed.

#### Example SonarCloud Feedback

```
SonarCloud Quality Gate failed
- 3 Bugs
- 5 Code Smells
- 1 Security Hotspot
```

#### Processing Steps

1. **Access Detailed Reports**:
   * Use the SonarCloud API or web interface
   * Categorize issues by severity and type

2. **Address Issues Systematically**:
   * Fix bugs first
   * Address security hotspots
   * Resolve code smells

3. **Document Resolutions**:
   * Note patterns of issues for future prevention
   * Update coding guidelines if necessary

## When to Consult Humans

While the goal is to create an autonomous system, there are scenarios where human input is necessary.

### Scenarios Requiring Human Consultation

1. **Product Design Decisions**: Features, UX, and strategic direction
2. **Security-Critical Changes**: Changes that could impact security posture
3. **Architectural Decisions**: Major structural changes to the codebase
4. **Deployment Approvals**: Final approval for production releases
5. **Access Requirements**: When additional permissions are needed
6. **Ambiguous Errors**: When errors have multiple possible interpretations
7. **Novel Problems**: Issues without precedent or documented solutions
8. **External Service Issues**: Problems with third-party services

### Effective Human Consultation

When consulting humans, provide:

1. **Clear Context**: Explain what you were trying to accomplish
2. **Error Details**: Provide specific error messages and logs
3. **Attempted Solutions**: Document what you've already tried
4. **Specific Questions**: Ask targeted questions rather than open-ended ones
5. **Recommendations**: Suggest possible solutions for approval

## Contributing to External Repositories

When issues are caused by bugs or missing features in external dependencies or GitHub Actions,
AI assistants can contribute fixes upstream.

### Workflow for External Contributions

1. **Clone the Repository Locally**:
   ```bash
   cd ~/Git
   git clone https://github.com/owner/repo.git
   cd repo
   git checkout -b feature/descriptive-branch-name
   ```

2. **Make Changes and Commit**:
   ```bash
   # Make your changes
   git add -A
   git commit -m "Descriptive commit message

   Detailed explanation of what the change does and why.

   Fixes #issue-number"
   ```

3. **Fork and Push**:
   ```bash
   # Create a fork (if not already forked)
   gh repo fork owner/repo --clone=false --remote=true

   # Add fork as remote
   git remote add fork https://github.com/your-username/repo.git

   # Push to fork
   git push fork feature/descriptive-branch-name
   ```

4. **Create Pull Request**:
   ```bash
   gh pr create \
     --repo owner/repo \
     --head your-username:feature/descriptive-branch-name \
     --title "Clear, descriptive title" \
     --body "## Summary

   Description of changes...

   Fixes #issue-number"
   ```

### Best Practices for External Contributions

* Always clone to `~/Git/` for consistency
* Check existing issues and PRs before starting work
* Follow the project's contribution guidelines
* Keep changes focused and minimal
* Include tests if the project has a test suite
* Reference the issue number in commits and PR description

### Local Repository Management

Keep cloned repositories in `~/Git/` organized:

* `~/Git/wp-plugin-starter-template-for-ai-coding/` - Main project
* `~/Git/wp-performance-action/` - Forked for contributions
* Other cloned repos as needed

## Conclusion

This error checking and feedback loop system creates a comprehensive framework for AI-driven development.

By systematically monitoring, analyzing, and resolving errors, the AI assistant can maintain high code quality.

For related workflows, refer to the other documents in the `.agents/` directory.
