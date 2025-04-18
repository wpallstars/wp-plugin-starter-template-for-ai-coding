# Incremental Development and Testing Guide

This document provides guidance for AI assistants to help with incremental development and testing for the Fix Plugin Does Not Exist Notices plugin.

## Time-Efficient Development Principles

### Branch Naming for Development

1. **Initial Development Branches**
   - Use descriptive names without version numbers:
     - `fix/issue-description` - For bug fixes
     - `feature/descriptive-name` - For new features
     - `patch/descriptive-name` - For small improvements
     - `refactor/descriptive-name` - For code restructuring
   - **Don't update version numbers** during this phase
   - Focus on implementing and testing the changes

2. **Version Branches**
   - Only create after changes are confirmed working:
     - `v{MAJOR}.{MINOR}.{PATCH}` (e.g., `v2.2.3`)
   - Only update version numbers at this point
   - This minimizes unnecessary version updates

### Version Numbering Guidelines

1. **Patch Versions (X.Y.Z → X.Y.Z+1)**
   - Use for bug fixes and small improvements
   - Example: `v2.2.3`

2. **Minor Versions (X.Y.Z → X.Y+1.0)**
   - Use for new features or significant improvements
   - Example: `v2.3.0`

3. **Major Versions (X.Y.Z → X+1.0.0)**
   - Only increment when numerous features and fixes are tested and confirmed stable
   - Reserved for breaking changes or significant overhauls
   - Example: `v3.0.0`

### Marking Stable Versions

When the user confirms that changes are working correctly:
1. Create a version branch and update version numbers
2. Tag the version branch as stable
   ```bash
   git tag -a v{MAJOR}.{MINOR}.{PATCH}-stable -m "Stable version {MAJOR}.{MINOR}.{PATCH}"
   ```
3. Document in the PR or issue that this version has been confirmed stable

## Local Testing Workflow

### 1. Create a Descriptive Branch for Development

```bash
# Ensure you have the latest main branch
git checkout main
git pull origin main

# Create a descriptive branch (without version numbers)
git checkout -b fix/plugin-activation-error
```

### 2. Make Changes Without Updating Version Numbers

During the development and testing phase:
- Implement the necessary changes
- **Don't update version numbers** in any files yet
- Focus on the functionality

### 3. Build and Deploy Locally

For local testing, use the current version number from the main plugin file:

```bash
# Get the current version from the plugin file
CURRENT_VERSION=$(grep -o "Version: [0-9.]*" wp-fix-plugin-does-not-exist-notices.php | cut -d' ' -f2)

# Build and deploy with current version
./build.sh $CURRENT_VERSION
```

This will:
1. Create a build directory
2. Copy required files to the build directory
3. Deploy the plugin to your local WordPress testing environment

**Note**: For local testing iterations, you do not need to commit changes, push to remote repositories, or create tags unless specifically requested.

### 4. Test and Evaluate

Test the changes thoroughly in the local environment:
- Verify that the specific issue is fixed or feature works as expected
- Check for any regressions or new issues
- Document the results

### 5. Based on Testing Results

- **If changes need further refinement**: Continue working in the same branch
- **If changes work as expected**: Proceed to version branch creation

### 6. Creating a Version Branch

When changes are confirmed working and ready for release:

1. Create a version branch with the appropriate version number:

```bash
# Determine the appropriate version increment (patch, minor, or major)
# based on the nature of the changes
git checkout -b v{MAJOR}.{MINOR}.{PATCH}
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
git commit -m "Version {MAJOR}.{MINOR}.{PATCH} - [brief description]"
```

4. Tag the version as stable:

```bash
git tag -a v{MAJOR}.{MINOR}.{PATCH}-stable -m "Stable version {MAJOR}.{MINOR}.{PATCH}"
```

## Remote Testing Workflow

When the user specifically requests remote testing:

### 1. Commit Changes to Remote Repository

If testing a development branch (without version updates):

```bash
git add .
git commit -m "[brief description] for remote testing"
git push origin [branch-name]
```

If testing a version branch (with version updates):

```bash
git add .
git commit -m "Version {MAJOR}.{MINOR}.{PATCH} - [brief description]"
git push origin v{MAJOR}.{MINOR}.{PATCH}
```

### 2. Create and Push Tag (For Version Branches Only)

```bash
git tag -a v{MAJOR}.{MINOR}.{PATCH} -m "Version {MAJOR}.{MINOR}.{PATCH} for remote testing"
git push origin v{MAJOR}.{MINOR}.{PATCH}
```

This will trigger GitHub Actions to build the installable ZIP file.

### 3. Verify Remote Build

Check that the GitHub Actions workflow completed successfully and the ZIP file is available for download.

### 4. Test and Evaluate

Test the remotely built version and document the results.

## Contributing to External Repositories

When working on issues for external repositories (pull/merge requests):

### 1. Clearly Indicate Testing Status

In the PR description and comments, clearly indicate the testing status:

- **Not tested**: "This PR addresses [issue] but has not been tested locally or remotely. It's ready for community/maintainer testing."
- **Locally tested**: "This PR has been tested in a local WordPress environment and [describe results]."
- **Remotely tested**: "This PR has been tested with a remote build and [describe results]."

### 2. Provide Testing Instructions

Include clear instructions for maintainers on how to test the changes:

- Steps to reproduce the original issue (if applicable)
- Steps to verify the fix or feature
- Any specific environments or configurations needed for testing

### 3. Be Responsive to Feedback

Monitor the PR for feedback from maintainers and be prepared to make additional changes if requested.

## Rollback Procedure

If a change causes issues after release:

### 1. Identify the Last Stable Version

Find the last version that was marked as stable:

```bash
git tag -l "*-stable"
```

### 2. Create a New Branch from the Stable Version

```bash
git checkout v{MAJOR}.{MINOR}.{PATCH}-stable
git checkout -b fix/rollback-based-fix
```

### 3. Make Necessary Changes

Implement the fix based on the stable version. Don't update version numbers yet.

### 4. Test the Changes

Test thoroughly to ensure the fix resolves the issues.

### 5. When Confirmed Working

Create a version branch with an incremented patch version and update all version numbers as described in the "Creating a Version Branch" section.
