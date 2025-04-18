#!/bin/bash

# WordPress Plugin Local Deployment Script
# This script deploys the plugin to a local WordPress installation for testing

# Configuration
PLUGIN_SLUG="wp-plugin-starter-template"
SOURCE_DIR="$(pwd)"
TARGET_DIR="${WP_LOCAL_PLUGIN_DIR:-/path/to/your/local/wordpress/wp-content/plugins}/$PLUGIN_SLUG"

# Check if WP_LOCAL_PLUGIN_DIR is set
if [ -z "$WP_LOCAL_PLUGIN_DIR" ]; then
    echo "⚠️ Warning: WP_LOCAL_PLUGIN_DIR environment variable is not set."
    echo "Please set it to your local WordPress plugins directory or edit this script."
    echo "Example: export WP_LOCAL_PLUGIN_DIR=/path/to/your/local/wordpress/wp-content/plugins"
    exit 1
fi

# Check if target directory exists
if [ ! -d "$(dirname "$TARGET_DIR")" ]; then
    echo "❌ Error: Target directory does not exist: $(dirname "$TARGET_DIR")"
    exit 1
fi

# Create or clean target directory
if [ -d "$TARGET_DIR" ]; then
    echo "Cleaning existing plugin directory..."
    rm -rf "$TARGET_DIR"
fi

echo "Creating plugin directory..."
mkdir -p "$TARGET_DIR"

# Copy plugin files
echo "Copying plugin files..."
rsync -av --exclude=".git" --exclude=".github" --exclude=".DS_Store" \
    --exclude="node_modules" --exclude="build" --exclude=".wordpress-org" \
    "$SOURCE_DIR/" "$TARGET_DIR/"

# Clear WordPress transients if WP-CLI is available
if command -v wp &> /dev/null; then
    echo "Clearing WordPress transients..."
    wp transient delete --all --path="$(dirname "$(dirname "$TARGET_DIR")")"
else
    echo "⚠️ WP-CLI not found, skipping transient clearing"
fi

echo "✅ Deployment successful!"
echo "Plugin deployed to: $TARGET_DIR"
