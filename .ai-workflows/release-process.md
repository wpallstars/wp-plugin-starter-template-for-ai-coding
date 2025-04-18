# Release Process Guide for AI Assistants

This document outlines the process for preparing and publishing new releases of the WordPress Plugin Starter Template.

## Release Workflow Overview

1. Create a version branch
2. Update version numbers in all required files
3. Build and test the plugin
4. Commit version changes
5. Create version tags
6. Push to remote repositories
7. Merge into main branch

## Detailed Steps

### 1. Create a Version Branch

Always start by creating a version branch from the latest main branch:

```bash
git checkout main
git pull origin main  # Critical step - never skip this
git checkout -b v{MAJOR}.{MINOR}.{PATCH}
```

Example: `git checkout -b v1.0.0`

### 2. Update Version Numbers

Update version numbers in all required files:

1. **Main plugin file** (wp-plugin-starter-template.php):
   - Update the `Version:` header
   - Update the version parameter in the Plugin class instantiation

2. **readme.txt**:
   - Update the `Stable tag:` value
   - Add a new section to the changelog

3. **README.md**:
   - Update version references
   - Add new section to the changelog

4. **CHANGELOG.md**:
   - Add a new version section at the top

5. **languages/wp-plugin-starter-template.pot**:
   - Update the `Project-Id-Version` header

### 3. Build and Test the Plugin

Build the plugin with the new version:

```bash
./build.sh {MAJOR}.{MINOR}.{PATCH}
```

This will:
- Create a clean build in the `build/` directory
- Generate a ZIP file for distribution
- Deploy to a local WordPress installation if configured

Test the plugin thoroughly:
- Test with the latest WordPress version
- Test with the minimum supported WordPress version (5.0)
- Test with PHP 7.0+ (minimum supported version)
- Test all features and functionality

### 4. Commit Version Changes

Commit all version changes:

```bash
git add wp-plugin-starter-template.php readme.txt README.md CHANGELOG.md languages/wp-plugin-starter-template.pot
git commit -m "Version {MAJOR}.{MINOR}.{PATCH} - [brief description]"
```

### 5. Create Version Tags

Create version tags:

```bash
git tag -a v{MAJOR}.{MINOR}.{PATCH} -m "Version {MAJOR}.{MINOR}.{PATCH}"
git tag -a v{MAJOR}.{MINOR}.{PATCH}-stable -m "Stable version {MAJOR}.{MINOR}.{PATCH}"
```

The `-stable` tag is used by Git Updater to identify the stable version.

### 6. Push to Remote Repositories

Push the version branch and tags to remote repositories:

```bash
# Push to GitHub
git push github refs/heads/v{MAJOR}.{MINOR}.{PATCH}:refs/heads/v{MAJOR}.{MINOR}.{PATCH}
git push github refs/tags/v{MAJOR}.{MINOR}.{PATCH}:refs/tags/v{MAJOR}.{MINOR}.{PATCH}
git push github refs/tags/v{MAJOR}.{MINOR}.{PATCH}-stable:refs/tags/v{MAJOR}.{MINOR}.{PATCH}-stable

# Push to Gitea
git push gitea refs/heads/v{MAJOR}.{MINOR}.{PATCH}:refs/heads/v{MAJOR}.{MINOR}.{PATCH}
git push gitea refs/tags/v{MAJOR}.{MINOR}.{PATCH}:refs/tags/v{MAJOR}.{MINOR}.{PATCH}
git push gitea refs/tags/v{MAJOR}.{MINOR}.{PATCH}-stable:refs/tags/v{MAJOR}.{MINOR}.{PATCH}-stable
```

### 7. Merge into Main Branch

Merge the version branch into the main branch:

```bash
git checkout main
git merge v{MAJOR}.{MINOR}.{PATCH} --no-ff -m "Merge v{MAJOR}.{MINOR}.{PATCH} into main"
git push github main
git push gitea main
```

## Version Numbering Guidelines

Follow semantic versioning (MAJOR.MINOR.PATCH):

- **MAJOR**: Incompatible API changes
- **MINOR**: Add functionality in a backward-compatible manner
- **PATCH**: Backward-compatible bug fixes

Examples:
- Bug fix: 1.0.0 → 1.0.1
- New feature: 1.0.0 → 1.1.0
- Breaking change: 1.0.0 → 2.0.0

## GitHub Actions Workflow

When you push a tag, the GitHub Actions workflow will:

1. Build the plugin
2. Create a ZIP file
3. Create a GitHub release
4. Attach the ZIP file to the release

You can monitor the workflow in the "Actions" tab of the GitHub repository.

## WordPress.org Deployment (If Applicable)

If the plugin is hosted on WordPress.org:

1. Ensure the `readme.txt` file is properly formatted
2. Ensure the stable tag matches the new version
3. Use the WordPress.org SVN repository to deploy the new version

## Post-Release Tasks

After releasing a new version:

1. Update the wiki documentation if needed
2. Announce the release in relevant channels
3. Monitor for any issues or feedback
4. Start planning the next release
