# Release Process

This document outlines the process for creating and publishing new releases of the plugin.

## Version Numbering

This plugin follows [Semantic Versioning](https://semver.org/) (SemVer):

- **MAJOR version** (x.0.0): Incompatible API changes
- **MINOR version** (0.x.0): Add functionality in a backward-compatible manner
- **PATCH version** (0.0.x): Backward-compatible bug fixes

## Pre-Release Checklist

Before creating a new release, complete the following checklist:

1. **Code Review**: Ensure all code has been reviewed and approved
2. **Testing**: Verify that all tests pass
   - Unit tests
   - End-to-end tests
   - Manual testing in different environments
3. **Documentation**: Update all relevant documentation
   - README.md
   - readme.txt
   - Wiki pages
   - Code comments
4. **Changelog**: Update CHANGELOG.md with all changes since the last release
5. **Version Numbers**: Update version numbers in:
   - Main plugin file header
   - Plugin initialization
   - readme.txt
   - package.json (if applicable)
   - composer.json (if applicable)

## Creating a Release

### Manual Release Process

1. **Create a Release Branch**:
   ```bash
   git checkout -b release/x.y.z
   ```

2. **Update Version Numbers**:
   - Update the version number in the main plugin file header
   - Update the version number in the plugin initialization
   - Update the "Stable tag" in readme.txt
   - Update the version in package.json and composer.json (if applicable)

3. **Update Changelog**:
   - Add a new section to CHANGELOG.md for the new version
   - Add a new section to the Changelog in readme.txt
   - Add a new section to the Upgrade Notice in readme.txt

4. **Commit Changes**:
   ```bash
   git add .
   git commit -m "Bump version to x.y.z"
   ```

5. **Create a Pull Request**:
   - Push the release branch to GitHub
   - Create a pull request against the main branch
   - Have the pull request reviewed and approved

6. **Merge the Pull Request**:
   - Merge the pull request into the main branch

7. **Create a Release Tag**:
   ```bash
   git checkout main
   git pull
   git tag -a vx.y.z -m "Version x.y.z"
   git push origin vx.y.z
   ```

8. **Create a GitHub Release**:
   - Go to the GitHub repository
   - Click on "Releases"
   - Click "Draft a new release"
   - Select the tag you just created
   - Add a title and description
   - Upload the built plugin ZIP file
   - Publish the release

### Automated Release Process

This plugin uses GitHub Actions to automate the release process:

1. **Create a Release Branch**:
   ```bash
   git checkout -b release/x.y.z
   ```

2. **Update Version Numbers and Changelog** (as described above)

3. **Commit Changes**:
   ```bash
   git add .
   git commit -m "Bump version to x.y.z"
   ```

4. **Create a Pull Request** (as described above)

5. **Merge the Pull Request** (as described above)

6. **Create a Release Tag**:
   ```bash
   git checkout main
   git pull
   git tag -a vx.y.z -m "Version x.y.z"
   git push origin vx.y.z
   ```

7. **Automated GitHub Release**:
   - The GitHub Actions workflow will automatically:
     - Build the plugin
     - Create a GitHub release
     - Upload the built plugin ZIP file
     - Update the wiki (if configured)

## Post-Release Tasks

After creating a release, complete the following tasks:

1. **Verify the Release**:
   - Check that the GitHub release was created successfully
   - Download the ZIP file and verify its contents
   - Test the plugin by installing it from the ZIP file

2. **Update Documentation**:
   - Update any external documentation that references the plugin version
   - Update the plugin's website (if applicable)

3. **Announce the Release**:
   - Announce the release on relevant channels (blog, social media, etc.)
   - Notify users who have reported issues that are fixed in this release

4. **Start Planning the Next Release**:
   - Create issues for the next release
   - Update the project roadmap

## Hotfix Process

For critical bugs that need to be fixed immediately:

1. **Create a Hotfix Branch**:
   ```bash
   git checkout -b hotfix/x.y.z
   ```

2. **Fix the Bug**:
   - Make the necessary changes to fix the bug
   - Add tests to prevent regression

3. **Update Version Numbers and Changelog** (as described above)

4. **Commit Changes**:
   ```bash
   git add .
   git commit -m "Hotfix: description of the fix"
   ```

5. **Create a Pull Request** (as described above)

6. **Merge the Pull Request** (as described above)

7. **Create a Release Tag and GitHub Release** (as described above)

## Release Branches

This plugin uses the following branch strategy:

- **main**: The main development branch
- **release/x.y.z**: Temporary branches for preparing releases
- **hotfix/x.y.z**: Temporary branches for hotfixes

## Conclusion

Following this release process ensures that releases are consistent, well-documented, and properly tested. It also helps users understand what has changed between versions and how to upgrade safely.
