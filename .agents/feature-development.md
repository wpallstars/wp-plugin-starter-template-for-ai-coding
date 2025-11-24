# Feature Development Guide for AI Assistants

This document provides guidance for AI assistants to help with feature development for the Fix Plugin Does Not Exist Notices plugin.

## Feature Development Workflow

### 1. Create a Feature Branch

Always start by creating a feature branch from the latest main branch pulled from origin (this step is mandatory):

```bash
git checkout main
git pull origin main  # Critical step - never skip this
git checkout -b feature/descriptive-name
```

Use a descriptive name that clearly indicates what the feature is about. If there's an issue number, include it in the branch name (e.g., `feature/123-update-source-selector`).

For more detailed git workflow guidelines, see **@.agents/git-workflow.md**.

### 2. Implement the Feature

When implementing a new feature:

- Follow WordPress coding standards
- Ensure all strings are translatable
- Add appropriate comments
- Consider performance implications
- Maintain backward compatibility
- Review reference plugins in the `reference-plugins/` directory for inspiration and best practices

### 3. Update Documentation

Update relevant documentation to reflect the new feature:

- Add a description to CHANGELOG.md under an "Unreleased" section
- Update readme.txt if the feature affects user-facing functionality
- Update README.md with the new feature description
- Update inline documentation/comments
- Update wiki documentation in the `.wiki` directory:
  - Create or update feature-specific pages
  - Update the Home.md page if necessary
  - Add the feature to any relevant existing pages
  - Add screenshots or examples if applicable
- Remember that any feature addition will require a version increment in all relevant files

For detailed guidelines on maintaining wiki documentation, see **@.agents/wiki-documentation.md**.

### 4. Testing

Test the feature thoroughly:

- Test with the latest WordPress version
- Test with the minimum supported WordPress version (5.0)
- Test with PHP 7.0+ (minimum supported version)
- Test in different environments (if possible)

### 5. Commit Changes

Make atomic commits with clear messages:

```bash
git add .
git commit -m "Add feature: descriptive name"
```

### 6. Prepare for Release

When the feature is ready to be released:

1. Create a version branch with the appropriate version number (typically increment the minor version for features):

```bash
# Example: from 2.2.0 to 2.3.0
git checkout -b v{MAJOR}.{MINOR+1}.0
```

2. Now update version numbers in all required files:

- Main plugin file (wp-fix-plugin-does-not-exist-notices.php)
- CHANGELOG.md (add a new version section)
- readme.txt
- README.md
- languages/wp-fix-plugin-does-not-exist-notices.pot (Project-Id-Version)

3. Commit the version updates:

```bash
git add .
git commit -m "Version {MAJOR}.{MINOR+1}.0 - [brief description]"
```

4. Tag the version as stable:

```bash
git tag -a v{MAJOR}.{MINOR+1}.0-stable -m "Stable version {MAJOR}.{MINOR+1}.0"
```

5. Follow the standard release process from this point

**IMPORTANT**: Don't update version numbers during initial development and testing. Only create a version branch and update version numbers when the feature is confirmed working.

For detailed guidelines on time-efficient development and testing, see **@.agents/incremental-development.md**.

### 7. Push to Remote (Optional for Collaboration)

If you need to collaborate with others on the feature before it's ready for release:

```bash
git push github HEAD:feature/descriptive-name
git push gitea HEAD:feature/descriptive-name
```

### 8. Create Pull Request (Optional)

If the repository uses pull requests for code review, create a pull request from the feature branch to the version branch.

## Code Standards and Best Practices

### PHP Coding Standards

- Follow [WordPress PHP Coding Standards](https://developer.wordpress.org/coding-standards/wordpress-coding-standards/php/)
- Use tabs for indentation, not spaces
- Use proper naming conventions:
  - Class names: `Class_Name`
  - Function names: `function_name`
  - Variable names: `$variable_name`

### JavaScript Coding Standards

- Follow [WordPress JavaScript Coding Standards](https://developer.wordpress.org/coding-standards/wordpress-coding-standards/javascript/)
- Use tabs for indentation, not spaces
- Use proper naming conventions:
  - Function names: `functionName`
  - Variable names: `variableName`

### Internationalization (i18n)

- Wrap all user-facing strings in appropriate translation functions:
  - `__()` for simple strings
  - `_e()` for echoed strings
  - `esc_html__()` for escaped strings
  - `esc_html_e()` for escaped and echoed strings
- Always use the plugin's text domain: `fix-plugin-does-not-exist-notices`

### Security Best Practices

- Validate and sanitize all input
- Escape all output
- Use nonces for form submissions
- Use capability checks for user actions

## Working in Multi-Repository Workspaces

When developing features in a workspace with multiple repositories:

1. **Verify Repository Context**:
   - Confirm you're working in the correct repository before suggesting or implementing features
   - Use `pwd` and `git remote -v` to verify the current repository

2. **Feature Verification**:
   - Before implementing a feature, verify it doesn't already exist in the current repository
   - Don't assume features from other repositories should be implemented in this one
   - Use `codebase-retrieval` to search for existing functionality

3. **Repository-Specific Implementation**:
   - Implement features appropriate for this specific plugin's purpose
   - Maintain consistency with the current repository's architecture and coding style
   - Don't copy code directly from other repositories without adaptation

4. **Cross-Repository Inspiration**:
   - If implementing a feature inspired by another repository, explicitly note that it's a new feature
   - Adapt the feature to fit the current repository's needs and architecture
   - Document the inspiration source in code comments

For detailed guidelines on working in multi-repository workspaces, see **@.agents/multi-repo-workspace.md**.

## Feature Types and Implementation Guidelines

### Admin Interface Features

When adding features to the admin interface:

- Use WordPress admin UI components for consistency
- Follow WordPress admin UI patterns
- Ensure accessibility compliance
- Add appropriate help text

### Plugin Functionality Features

When adding core functionality:

- Ensure compatibility with WordPress hooks system
- Consider performance impact
- Maintain backward compatibility
- Add appropriate error handling

### Integration Features

When adding integration with other plugins or services:

- Make integrations optional when possible
- Check if the integrated plugin/service is available before using it
- Provide fallback functionality when the integration is not available
- Document the integration requirements
