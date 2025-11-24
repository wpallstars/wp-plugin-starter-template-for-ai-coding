# Wiki Documentation Guide for AI Assistants

This document provides guidelines for maintaining and updating the wiki documentation for the WordPress Plugin Starter Template.

## Wiki Structure

The wiki documentation is organized into the following sections:

1. **User Documentation**:
   - Home
   - Starter Prompt (must be listed before Installation Guide)
   - Installation Guide
   - Usage Instructions
   - Frequently Asked Questions
   - Troubleshooting

2. **Developer Documentation**:
   - Architecture Overview
   - Customization Guide
   - Extending the Plugin
   - Coding Standards
   - Release Process

3. **AI Documentation**:
   - AI Workflow Documentation

4. **Additional Resources**:
   - Changelog
   - Contributing

## Wiki Files Location

The wiki documentation is stored in the `.wiki/` directory in the repository. This allows:

1. Version control of wiki content alongside the code
2. Automated synchronization with the GitHub wiki using GitHub Actions
3. Easy contribution to documentation through pull requests

## Synchronization Process

When changes are pushed to the `.wiki/` directory in the `main` branch, the GitHub Actions workflow `.github/workflows/sync-wiki.yml` automatically synchronizes these changes with the GitHub wiki.

## Documentation Standards

### General Guidelines

- Use clear, concise language
- Follow Markdown formatting conventions
- Include code examples where appropriate
- Use screenshots or diagrams for complex concepts
- Keep documentation up-to-date with code changes

### Markdown Formatting

- Use `#` for main headings
- Use `##` for section headings
- Use `###` for subsection headings
- Use backticks for inline code: `code`
- Use triple backticks for code blocks:
  ```php
  // Code example
  function example() {
      return true;
  }
  ```
- Use bullet points for lists
- Use numbered lists for sequential steps
- Use blockquotes for important notes: > Note

### Code Examples

- Include complete, working code examples
- Use proper syntax highlighting
- Include comments to explain complex parts
- Follow WordPress coding standards in examples

## Updating Documentation

### When to Update

Documentation should be updated:

1. When adding new features
2. When changing existing functionality
3. When fixing bugs that affect user experience
4. When improving or clarifying existing documentation

### How to Update

1. Identify the relevant wiki file(s) in the `.wiki/` directory
2. Make the necessary changes
3. **Always ensure the Changelog.md in the wiki is updated to match the main CHANGELOG.md file**
4. **Always ensure the _Sidebar.md file has the correct navigation structure with Starter Prompt listed before Installation Guide**
5. Commit and push the changes to the `main` branch
6. The GitHub Actions workflow will automatically sync the changes with the GitHub wiki

### Creating New Pages

To create a new wiki page:

1. Create a new Markdown file in the `.wiki/` directory
2. Name the file according to the page title (e.g., `New-Feature.md`)
3. Add a link to the new page in the appropriate section of `Home.md`
4. Add a link to the new page in `_Sidebar.md`

## Repository-Specific Documentation

When working in a multi-repository workspace, it's critical to ensure that wiki documentation accurately reflects the features and functionality of the **current repository only**.

### Avoiding Cross-Repository Confusion

1. **Verify Features Before Documenting**:
   - Always verify that a feature exists in the current repository before documenting it
   - Use `codebase-retrieval` to search for feature implementations
   - Check the actual code, not just comments or references

2. **Repository-Specific Content**:
   - Document only features that exist in the current repository
   - Don't assume features from other repositories are present in this one
   - Be explicit about which repository the documentation applies to

3. **Feature Inspiration vs. Existing Features**:
   - If documenting a feature inspired by another repository but not yet implemented, clearly mark it as a proposed feature
   - Don't document features as if they exist when they're only planned or inspired by other repositories

4. **Cross-Repository References**:
   - If referencing functionality from another repository, clearly indicate that it's external
   - Use phrases like "unlike Repository X, this plugin does not include..."

For detailed guidelines on working in multi-repository workspaces, see **@.agents/multi-repo-workspace.md**.

## Best Practices

### Content Guidelines

- Use clear, concise language
- Include step-by-step instructions for complex tasks
- Use screenshots or diagrams to illustrate concepts
- Provide code examples for developers
- Keep the documentation organized and easy to navigate

### Formatting Guidelines

- Use consistent Markdown formatting
- Use headings to create a clear hierarchy
- Use lists for steps or related items
- Use tables for structured data
- Use code blocks for code examples

### Maintenance Guidelines

- Review documentation regularly for accuracy
- Update documentation when code changes
- Remove outdated information
- Add new documentation for new features
- Respond to user feedback about documentation

## User-Focused Documentation

When writing documentation for users:

1. Assume minimal technical knowledge
2. Provide clear, step-by-step instructions
3. Include screenshots for visual guidance
4. Explain technical terms when necessary
5. Focus on what users want to accomplish

## Developer-Focused Documentation

When writing documentation for developers:

1. Assume familiarity with WordPress development
2. Provide technical details and explanations
3. Include code examples and API references
4. Explain architectural decisions
5. Focus on how to extend or customize the plugin

## Responding to User Feedback

Improve documentation based on user feedback:

1. Monitor GitHub issues and WordPress.org support forums for common questions
2. Update the FAQ and troubleshooting sections based on user feedback
3. Add new examples or clarifications based on user questions
