# Developer Preferences Memory

This document serves as a persistent memory for developer preferences established during coding sessions. AI assistants should refer to this document to understand the developer's preferences and update it as new preferences are established.

## Purpose

- Maintain a consistent record of developer preferences across coding sessions
- Ensure AI assistants can provide assistance that aligns with the developer's preferred coding style and practices
- Reduce the need for developers to repeatedly explain their preferences

## How to Use This Document

- **AI Assistants**: Review this document before providing assistance. Update it when new preferences are established through user feedback.
- **Developers**: Reference this document to see what preferences have been recorded. Feel free to edit it directly to add or modify preferences.

## Recorded Preferences

### File and Directory Structure

- Prefer lowercase filenames for consistency across the codebase
- Use unique folder names following best practices
- Folder references should be easily identifiable when using @mentions in AI-assisted coding
- Admin-specific functionality should be in the `admin/lib/` directory
- Core plugin functionality should be in the `includes/` directory

### Code Style

- Follow WordPress coding standards
- Use OOP best practices for WordPress plugins
- Create modular, maintainable, and efficient code structure

### Documentation

- Prefer token-efficient documentation in `.ai-assistant.md` that references `.ai-workflows/` files
- Document the release workflow in `.ai-assistant.md` and `.ai-workflows/release-process.md`
- Store environment variable documentation in `.ai-workflows/local-env-vars.md`
- Maintain consistent documentation across readme.txt, README.md, and CHANGELOG.md

### Asset Organization

- Store banner, icon, and screenshot images in `.wordpress-org/assets/`
- Store WORDPRESS_ORG files within `/wordpress-org`
- Organize files in `/assets` into relevant `/admin` folders

### Version Control

- Use standard Git practices for version control and code management
- When updating plugin versions, create a GitHub tag and trigger GitHub actions
- Follow a specific release process with proper tagging and GitHub releases
- Ensure commits are merged to the main branch as Git Updater pulls data from the readme.txt file in the primary branch

### Plugin Development

- Prefer simpler solutions over complex ones for plugins
- Use a specific formatting style for the CHANGELOG.md file, using #### for section headings
- When updating plugin versions, remember to update language files (POT/PO)
- Comment out redundant code during testing

### Potential AI Assised IDE Issues

- Check for non-standard local terminal commandline customisations that might not be understood by the AI IDE in its terminal useage and cause errors in execution or confusion in not seeing expected results, and advise on how to resolve
- Check for non-standard or multiple python and node.js versions, including homebrew versions, that might not be understood by the AI IDE in its terminal useage and cause errors in execution or confusion in not seeing expected results, and advise on how to resolve