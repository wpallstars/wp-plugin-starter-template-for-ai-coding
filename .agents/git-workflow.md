# Git Workflow Guide for AI Assistants

This document provides guidance for AI assistants to help with git workflow management for the Fix Plugin Does Not Exist Notices plugin.

## Core Git Workflow Principles

### 1. Always Start from Latest Main Branch

Before creating any new branch, always ensure you're working with the latest code from the main branch by pulling from the origin:

```bash
git checkout main
git pull origin main
```

This critical step ensures that your new branch includes all the latest changes from the remote repository and reduces the chance of merge conflicts later. Never skip this step, as working from an outdated main branch can lead to integration problems.

### 2. One Issue Per Branch

Create a separate branch for each issue or feature you're working on:

- For bug fixes: `fix/issue-description` or `fix/issue-number-description`
- For features: `feature/descriptive-name`
- For small improvements: `patch/descriptive-name`
- For code restructuring: `refactor/descriptive-name`

**Important**: Use descriptive names without version numbers for development branches. This allows focusing on the changes without worrying about version updates until the changes are confirmed working.

Only create version branches (e.g., `v2.2.3`) when changes are ready for release, and only then update version numbers in files.

This approach keeps changes focused, makes code review easier, and provides clear rollback points if needed.

### 3. Pull Request for Each Issue

Create a separate pull request for each issue or feature. This ensures:

- Each change can be reviewed independently
- Issues can be merged as soon as they're ready
- Changes can be reverted individually if needed
- CI/CD checks can run on focused changes

## Detailed Workflow

### Starting a New Task

1. **Update Main Branch from Origin**
   ```bash
   git checkout main
   git pull origin main
   ```

   This step is mandatory before creating any new branch to ensure you're working with the latest code.

2. **Create a New Branch**
   ```bash
   git checkout -b [branch-type]/[description]
   ```

   Examples:
   ```bash
   git checkout -b fix/123-plugin-activation-error
   git checkout -b feature/update-source-selector
   git checkout -b patch/2.2.1
   ```

3. **Make Your Changes**
   - Make focused changes related only to the specific issue
   - Commit regularly with clear, descriptive messages
   - Reference issue numbers in commit messages when applicable

4. **Testing Approach**

   For efficient development:
   - **Local Testing (Default)**: Test without updating version numbers
     ```bash
     # Get current version from plugin file
     CURRENT_VERSION=$(grep -o "Version: [0-9.]*" wp-fix-plugin-does-not-exist-notices.php | cut -d' ' -f2)

     # Build and deploy with current version
     ./build.sh $CURRENT_VERSION
     ```
   - **Remote Testing (When Requested)**: Push development branch to remote
     ```bash
     git add .
     git commit -m "[Brief description] for remote testing"
     git push origin [branch-name]
     ```
   - **Version Creation**: Only when changes are confirmed working
     ```bash
     # Create version branch
     git checkout -b v{MAJOR}.{MINOR}.{PATCH}

     # Update version numbers in all required files
     # Commit version updates
     git add .
     git commit -m "Version {MAJOR}.{MINOR}.{PATCH} - Brief description"

     # Tag as stable
     git tag -a v{MAJOR}.{MINOR}.{PATCH}-stable -m "Stable version {MAJOR}.{MINOR}.{PATCH}"
     ```

5. **Push Branch to Remote (When Needed)**
   ```bash
   git push origin [branch-name]
   ```

### Creating a Pull Request

1. **Ensure Tests Pass Locally**
   - Run any available tests to ensure your changes work as expected
   - Fix any issues before creating a pull request

2. **Create Pull Request**
   - Create a pull request from your branch to the main branch
   - Include a clear description of the changes
   - Reference any related issues
   - Assign reviewers if appropriate

3. **Address Review Feedback**
   - Make requested changes
   - Push additional commits to the same branch
   - Respond to comments

### CI/CD Integration

Each pull request should pass through CI/CD checks before being merged. This ensures that all changes are compatible with the existing codebase and meet quality standards.

1. **Automated Tests**
   - Unit tests
   - Integration tests
   - Code style checks
   - Compatibility checks

2. **Manual Review**
   - Code review by team members
   - Functional testing in test environment
   - Verification of feature requirements

3. **Approval Process**
   - Required approvals before merging
   - Final checks for conflicts with other pending PRs
   - Verification that all CI/CD checks have passed

4. **Compatibility with Unmerged PRs**
   - When multiple PRs are in progress simultaneously, ensure each PR is compatible with the main branch
   - For related changes, consider using feature flags to allow independent merging
   - Document dependencies between PRs in the PR description

### Handling Concurrent Development

When working on multiple issues simultaneously:

1. **Keep Branches Independent**
   - Always create new branches from the latest main branch pulled from origin, not from other feature branches
   - This ensures each PR can be merged independently and contains all the latest changes

2. **Handle Conflicts Proactively**
   - If main has been updated with other changes while you're working:
     ```bash
     git checkout main
     git pull origin main
     git checkout your-branch
     git merge main
     ```
   - Resolve any conflicts locally before pushing

3. **Coordinate on Dependent Changes**
   - If changes depend on each other, note this in the PR description
   - Consider using the "Depends on #PR-number" notation in PR descriptions

## Release Process

When preparing for a release:

1. **Ensure All Required PRs are Merged**
   - All features and fixes planned for the release should be merged to main

2. **Create a Release Branch**
   ```bash
   git checkout main
   git pull origin main
   git checkout -b v{MAJOR}.{MINOR}.{PATCH}
   ```

3. **Follow Standard Release Process**
   - Update version numbers
   - Update changelogs
   - Create tag
   - See **@.ai-workflows/release-process.md** for complete details

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

## Best Practices

### Commit Messages

- Use present tense ("Add feature" not "Added feature")
- Start with a verb
- Keep the first line under 50 characters
- Reference issues when relevant: "Fix #123: Resolve plugin detection issue"
- For more complex changes, add a detailed description after the first line

### Branch Management

- Delete branches after they've been merged
- Keep branch names descriptive but concise
- Use consistent naming conventions

### Code Review

- Review code thoroughly before approving
- Test changes locally when possible
- Provide constructive feedback
- See **@.ai-workflows/code-review.md** for detailed code review guidelines

### Suggested Improvements

If you identify potential improvements outside the scope of the current issue:

1. **Document the Suggestion**
   - Note the suggestion in the PR comments
   - Create a new issue for the suggestion
   - Be specific about the benefits and implementation details

2. **Create a Separate Branch**
   - Don't include unrelated improvements in the current PR
   - Create a new branch from the latest main branch for the suggested improvement
   - Submit a separate PR for the suggestion

3. **Ensure Compatibility**
   - Make sure the suggested improvement is compatible with any unmerged PRs
   - If the improvement depends on changes in another PR, note this dependency
   - Consider how the improvement will interact with other pending changes
