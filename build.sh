#!/bin/bash

# WordPress Plugin Build Script
# This script creates a clean build of the plugin for distribution

# Check if version is provided
if [ -z "$1" ]; then
    echo "❌ Error: Version number is required"
    echo "Usage: ./build.sh <version>"
    exit 1
fi

VERSION=$1
PLUGIN_SLUG="wp-plugin-starter-template"
BUILD_DIR="build/$PLUGIN_SLUG"
ZIP_FILE="$PLUGIN_SLUG-$VERSION.zip"

# Create build directory
echo "Creating build directory..."
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

# Install composer dependencies
echo "Installing composer dependencies..."
composer install --no-dev --optimize-autoloader

# Copy plugin files to build directory
echo "Copying plugin files..."
cp -R *.php "$BUILD_DIR/"
cp -R README.md LICENSE CHANGELOG.md readme.txt composer.json "$BUILD_DIR/"

# Copy directories
echo "Copying directories..."
mkdir -p "$BUILD_DIR/admin" "$BUILD_DIR/includes" "$BUILD_DIR/languages" "$BUILD_DIR/assets"
cp -R admin/* "$BUILD_DIR/admin/"
cp -R includes/* "$BUILD_DIR/includes/"
cp -R languages/* "$BUILD_DIR/languages/"

# Create assets directory structure
mkdir -p "$BUILD_DIR/assets/banner" "$BUILD_DIR/assets/icon" "$BUILD_DIR/assets/screenshots"

# Copy assets if they exist
if [ -d "assets/banner" ]; then
    cp -R assets/banner/* "$BUILD_DIR/assets/banner/"
fi

if [ -d "assets/icon" ]; then
    cp -R assets/icon/* "$BUILD_DIR/assets/icon/"
fi

if [ -d "assets/screenshots" ]; then
    cp -R assets/screenshots/* "$BUILD_DIR/assets/screenshots/"
fi

# Copy vendor directory if it exists
if [ -d "vendor" ]; then
    cp -R vendor "$BUILD_DIR/"
fi

# Create ZIP file
echo "Creating ZIP file..."
cd build
zip -r "../$ZIP_FILE" "$PLUGIN_SLUG" -x "*.DS_Store" -x "*.git*" -x "*.github*"
cd ..

# Check if ZIP file was created successfully
if [ -f "$ZIP_FILE" ]; then
    echo "✅ Build successful: $ZIP_FILE created"
    echo "File path: $(pwd)/$ZIP_FILE"
    
    # Deploy to local WordPress installation if environment variable is set
    if [ -n "$WP_LOCAL_PLUGIN_DIR" ]; then
        echo "\nDeploying to local WordPress installation..."
        echo "Deploying to local WordPress installation..."
        
        # Remove existing plugin directory
        rm -rf "$WP_LOCAL_PLUGIN_DIR/$PLUGIN_SLUG"
        
        # Copy files to local WordPress installation
        rsync -av --exclude=".git" --exclude=".github" --exclude=".DS_Store" \
            "$BUILD_DIR/" "$WP_LOCAL_PLUGIN_DIR/$PLUGIN_SLUG"
        
        # Clear WordPress transients if WP-CLI is available
        if command -v wp &> /dev/null; then
            echo "Clearing WordPress transients..."
            wp transient delete --all --path="$WP_LOCAL_PLUGIN_DIR/../.."
        else
            echo "⚠️ WP-CLI not found, skipping transient clearing"
        fi
        
        echo "✅ Local deployment successful!"
        echo "Plugin deployed to: $WP_LOCAL_PLUGIN_DIR/$PLUGIN_SLUG"
    fi
else
    echo "❌ Build failed: ZIP file was not created"
    exit 1
fi
