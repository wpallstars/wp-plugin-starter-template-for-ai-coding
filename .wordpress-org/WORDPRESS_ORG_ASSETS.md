# WordPress.org Plugin Assets Guide

This document provides detailed information about the assets required for the WordPress.org plugin repository.

## Required Assets

### Banner

The banner is displayed at the top of your plugin's page on WordPress.org.

- **Regular Banner**: 772x250 pixels
- **Retina Banner**: 1544x500 pixels
- **Format**: PNG or JPG
- **File Names**: `banner-772x250.{png|jpg}` and `banner-1544x500.{png|jpg}`

### Icon

The icon is displayed next to your plugin's name in search results and on your plugin's page.

- **Regular Icon**: 128x128 pixels
- **Retina Icon**: 256x256 pixels
- **Format**: PNG with transparency
- **File Names**: `icon-128x128.png` and `icon-256x256.png`

### Screenshots

Screenshots are displayed in the "Screenshots" tab on your plugin's page.

- **Size**: At least 1200 pixels wide
- **Format**: PNG or JPG
- **File Names**: `screenshot-1.{png|jpg}`, `screenshot-2.{png|jpg}`, etc.
- **Description**: Screenshot descriptions are added in the `readme.txt` file under the "Screenshots" section

## Asset Design Best Practices

### Banner Design

- **Keep it Simple**: Don't overcrowd the banner with too much information
- **Consistent Branding**: Use colors and fonts that match your plugin's branding
- **Readable Text**: Ensure any text is large enough to read
- **Purpose**: Clearly communicate what your plugin does
- **Avoid Small Details**: Small details may not be visible at the displayed size

### Icon Design

- **Simple and Recognizable**: The icon should be simple and easily recognizable
- **Consistent with Banner**: Use similar colors and style as your banner
- **Works at Small Sizes**: Ensure the icon is recognizable even at small sizes
- **Transparent Background**: Use a transparent background for the PNG

### Screenshot Best Practices

- **Show Key Features**: Showcase the most important features of your plugin
- **Logical Order**: Arrange screenshots in a logical order that tells a story
- **Clear and Focused**: Each screenshot should focus on a specific feature
- **Annotations**: Consider adding annotations to highlight important elements
- **Real-World Examples**: Show the plugin in action with real-world examples

## Uploading Assets

Assets are uploaded separately from your plugin code:

1. Log in to your WordPress.org account
2. Navigate to your plugin's page
3. Click on the "Assets" tab
4. Upload your assets using the provided interface

## Asset Updates

When updating assets:

1. Prepare the new assets following the guidelines above
2. Log in to your WordPress.org account
3. Navigate to your plugin's page
4. Click on the "Assets" tab
5. Upload the new assets
6. It may take some time for the changes to appear on WordPress.org

## Additional Resources

- [WordPress Plugin Developer Handbook](https://developer.wordpress.org/plugins/)
- [WordPress Plugin Directory Guidelines](https://developer.wordpress.org/plugins/wordpress-org/detailed-plugin-guidelines/)
- [WordPress Plugin Assets](https://developer.wordpress.org/plugins/wordpress-org/plugin-assets/)
