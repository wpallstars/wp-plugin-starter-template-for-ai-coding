# WordPress.org Plugin Submission Guide

This document provides a step-by-step guide for submitting your plugin to the WordPress.org plugin repository.

## Before Submission

### 1. Prepare Your Plugin

- Ensure your plugin follows the [WordPress Plugin Guidelines](https://developer.wordpress.org/plugins/wordpress-org/detailed-plugin-guidelines/)
- Check that your plugin meets the [Plugin Directory Requirements](https://developer.wordpress.org/plugins/wordpress-org/plugin-developer-faq/)
- Verify that your plugin follows WordPress coding standards
- Test your plugin thoroughly on different WordPress versions

### 2. Prepare Required Files

- **readme.txt**: Create a readme.txt file following the [WordPress readme.txt standard](https://developer.wordpress.org/plugins/wordpress-org/how-your-readme-txt-works/)
- **Plugin Header**: Ensure your main plugin file includes the required plugin header
- **License**: Include the GPL v2 or later license
- **Assets**: Prepare banner, icon, and screenshots (see [WORDPRESS_ORG_ASSETS.md](WORDPRESS_ORG_ASSETS.md))

### 3. Create a Clean Build

- Remove any development files (e.g., .git, node_modules, etc.)
- Remove any unnecessary files (e.g., .DS_Store, Thumbs.db, etc.)
- Create a ZIP file of your plugin

## Submission Process

### 1. Create a WordPress.org Account

If you don't already have one, create an account on [WordPress.org](https://wordpress.org/).

### 2. Submit Your Plugin

1. Go to the [Add Your Plugin](https://wordpress.org/plugins/developers/add/) page
2. Fill out the submission form:
   - Plugin Name
   - Plugin URL (optional)
   - Description
   - Upload your plugin ZIP file
3. Agree to the terms and submit your plugin

### 3. Wait for Review

- The WordPress.org team will review your plugin
- This process can take several weeks
- You'll receive an email when your plugin is approved or if there are issues to address

### 4. Address Review Feedback

If the WordPress.org team provides feedback:

1. Make the requested changes
2. Create a new ZIP file
3. Reply to the review email with the changes you've made
4. Attach the updated ZIP file or provide a link to download it

### 5. Upload Assets

Once your plugin is approved:

1. Log in to your WordPress.org account
2. Navigate to your plugin's page
3. Click on the "Assets" tab
4. Upload your banner, icon, and screenshots

## After Approval

### 1. Set Up SVN Access

WordPress.org uses Subversion (SVN) for plugin management:

1. You'll receive SVN access details via email
2. Set up SVN on your local machine
3. Check out your plugin repository

### 2. Manage Your Plugin with SVN

Basic SVN commands for managing your plugin:

```bash
# Check out your plugin repository
svn checkout https://plugins.svn.wordpress.org/your-plugin-name/

# Add new files
svn add new-file.php

# Commit changes
svn commit -m "Description of changes"

# Update your local copy
svn update
```

### 3. Release Updates

To release a new version:

1. Update the version number in your plugin file and readme.txt
2. Update the changelog in readme.txt
3. Test the new version thoroughly
4. Commit the changes to the `trunk` directory
5. Tag the new version:
   ```bash
   svn copy https://plugins.svn.wordpress.org/your-plugin-name/trunk https://plugins.svn.wordpress.org/your-plugin-name/tags/1.0.1 -m "Tagging version 1.0.1"
   ```

## Best Practices

- **Respond Promptly**: Respond to review feedback promptly
- **Be Patient**: The review process can take time
- **Be Thorough**: Test your plugin thoroughly before submission
- **Follow Guidelines**: Adhere to all WordPress.org guidelines
- **Maintain Your Plugin**: Regularly update your plugin to fix bugs and add features

## Additional Resources

- [WordPress Plugin Developer Handbook](https://developer.wordpress.org/plugins/)
- [WordPress Plugin Directory Guidelines](https://developer.wordpress.org/plugins/wordpress-org/detailed-plugin-guidelines/)
- [WordPress Plugin Developer FAQ](https://developer.wordpress.org/plugins/wordpress-org/plugin-developer-faq/)
