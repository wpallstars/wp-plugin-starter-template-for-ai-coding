# Working in Multi-Repository Workspaces

This document provides guidelines for AI assistants working in VSCode/VSCodium workspaces that contain multiple repository folders.

## Understanding Multi-Repository Workspaces

In VSCode/VSCodium, developers often create workspaces that include multiple repository folders. This allows them to work on related projects simultaneously or reference code from one project while working on another.

### Common Workspace Configurations

1. **Multiple WordPress Plugins**: A workspace containing several WordPress plugin repositories
2. **Plugin and Theme Combinations**: Repositories for both plugins and themes that work together
3. **Reference Repositories**: Including repositories purely for reference or inspiration
4. **Shared Libraries**: Repositories containing shared code used across multiple projects

## Potential Issues in Multi-Repository Workspaces

### 1. Feature Hallucination

The most common issue is "feature hallucination" - assuming that features present in one repository should be implemented in another, or documenting non-existent features based on code seen in other repositories.

### 2. Cross-Repository Code References

Referencing or suggesting code patterns from one repository when working on another can lead to inconsistent coding styles and approaches.

### 3. Documentation Confusion

Creating documentation that includes features or functionality from other repositories in the workspace.

### 4. Scope Creep

Suggesting changes or improvements based on other repositories, leading to scope creep and feature bloat.

## Best Practices for AI Assistants

### 1. Repository Verification

**ALWAYS** verify which repository you're currently working in before:
- Making code suggestions
- Creating or updating documentation
- Discussing features or functionality
- Implementing new features

### 2. Explicit Code Search Scoping

When searching for code or functionality:
- Explicitly limit searches to the current repository
- Use repository-specific paths in search queries
- Verify search results are from the current repository before using them

### 3. Feature Verification Process

Before documenting or implementing a feature:

1. **Check the codebase**: Use the codebase-retrieval tool to search for relevant code in the current repository
2. **Verify functionality**: Look for actual implementation, not just references or comments
3. **Check documentation**: Review existing documentation to understand intended functionality
4. **Ask for clarification**: If uncertain, ask the developer to confirm the feature's existence or scope

### 4. Documentation Guidelines

When creating or updating documentation:

1. **Repository-specific content**: Only document features and functionality that exist in the current repository
2. **Verify before documenting**: Check the codebase to confirm features actually exist
3. **Clear boundaries**: Make it clear which repository the documentation applies to
4. **Accurate feature descriptions**: Describe features as they are implemented, not as they might be in other repositories

### 5. Cross-Repository Inspiration

When implementing features inspired by other repositories:

1. **Explicit attribution**: Clearly state that the feature is inspired by another repository
2. **New implementation**: Treat it as a new feature being added, not an existing one
3. **Repository-appropriate adaptation**: Adapt the feature to fit the current repository's architecture and style
4. **Developer confirmation**: Confirm with the developer that adding the feature is appropriate

## Repository Context Verification Checklist

Before making significant changes or recommendations, run through this checklist:

- [ ] Verified current working directory/repository
- [ ] Confirmed repository name and purpose
- [ ] Checked that code searches are limited to current repository
- [ ] Verified features exist in current repository before documenting them
- [ ] Ensured documentation reflects only the current repository's functionality
- [ ] Confirmed that any cross-repository inspiration is clearly marked as new functionality

## Example Verification Workflow

1. **Check current repository**:
   ```
   pwd
   git remote -v
   ```

2. **Verify feature existence**:
   ```
   # Use codebase-retrieval to search for the feature
   # Look for actual implementation, not just references
   ```

3. **Document with clear repository context**:
   ```
   # Always include repository name in documentation
   # Be specific about which features are included
   ```

4. **When suggesting new features**:
   ```
   # Clearly state if inspired by another repository
   # Explain why it's appropriate for the current repository
   ```

## Handling Repository Switching

When the developer switches between repositories in the workspace:

1. **Acknowledge the switch**: Confirm the new repository context
2. **Reset context**: Don't carry over assumptions from the previous repository
3. **Verify new environment**: Check the structure and features of the new repository
4. **Update documentation references**: Ensure you're referencing documentation specific to the new repository
