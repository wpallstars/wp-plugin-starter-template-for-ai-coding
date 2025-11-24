#!/bin/bash

# LocalWP Integration Script for WordPress Plugin Development
# For use by AI coding assistants and developers
#
# This script manages LocalWP sites for testing the plugin.
# Creates standardized test sites with consistent URLs.
#
# URL Patterns:
#   Single site: {plugin-slug}-single.local
#   Multisite:   {plugin-slug}-multisite.local
#
# Usage:
#   ./bin/localwp-setup.sh create [--multisite]
#   ./bin/localwp-setup.sh sync
#   ./bin/localwp-setup.sh reset
#   ./bin/localwp-setup.sh info
#
# Examples:
#   npm run localwp:create              # Create single site
#   npm run localwp:create:multisite    # Create multisite
#   npm run localwp:sync                # Sync plugin files
#   npm run localwp:reset               # Reset to clean state

set -e

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
PLUGIN_SLUG="wp-plugin-starter-template"
PLUGIN_TEXT_DOMAIN="wp-plugin-starter-template"

# LocalWP paths (macOS)
LOCAL_SITES_DIR="$HOME/Local Sites"
LOCAL_APP="/Applications/Local.app"
LOCAL_WP_CLI="$LOCAL_APP/Contents/Resources/extraResources/bin/wp-cli/posix/wp"

# Site configurations
SINGLE_SITE_NAME="${PLUGIN_SLUG}-single"
MULTISITE_NAME="${PLUGIN_SLUG}-multisite"
SINGLE_SITE_DOMAIN="${SINGLE_SITE_NAME}.local"
MULTISITE_DOMAIN="${MULTISITE_NAME}.local"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Helper functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_step() {
    echo -e "${CYAN}[STEP]${NC} $1"
}

# Check if LocalWP is installed
check_localwp() {
    if [ ! -d "$LOCAL_APP" ]; then
        log_error "LocalWP is not installed at $LOCAL_APP"
        log_info "Download from: https://localwp.com/"
        exit 1
    fi
    
    if [ ! -f "$LOCAL_WP_CLI" ]; then
        log_error "WP-CLI not found in LocalWP installation"
        exit 1
    fi
    
    local version=$("$LOCAL_WP_CLI" --version 2>/dev/null || echo "unknown")
    log_info "LocalWP WP-CLI version: $version"
}

# Get site path
get_site_path() {
    local site_name="$1"
    echo "$LOCAL_SITES_DIR/$site_name"
}

# Get WordPress path within site
get_wp_path() {
    local site_name="$1"
    local site_path=$(get_site_path "$site_name")
    
    # LocalWP uses app/public for WordPress files
    echo "$site_path/app/public"
}

# Check if site exists
site_exists() {
    local site_name="$1"
    local site_path=$(get_site_path "$site_name")
    [ -d "$site_path" ]
}

# Get plugin destination path
get_plugin_path() {
    local site_name="$1"
    local wp_path=$(get_wp_path "$site_name")
    echo "$wp_path/wp-content/plugins/$PLUGIN_SLUG"
}

# Sync plugin files to LocalWP site
sync_plugin() {
    local site_name="$1"
    local plugin_dest=$(get_plugin_path "$site_name")
    
    if ! site_exists "$site_name"; then
        log_error "Site '$site_name' does not exist"
        return 1
    fi
    
    log_info "Syncing plugin to $site_name..."
    
    # Create plugin directory if it doesn't exist
    mkdir -p "$plugin_dest"
    
    # Sync files using rsync (excludes dev files)
    rsync -av --delete \
        --exclude 'node_modules' \
        --exclude 'vendor' \
        --exclude '.git' \
        --exclude 'dist' \
        --exclude 'tests' \
        --exclude 'cypress' \
        --exclude '.github' \
        --exclude '.agents' \
        --exclude '.wiki' \
        --exclude 'reference-plugins' \
        --exclude '*.zip' \
        --exclude '.playground.*' \
        --exclude 'composer.lock' \
        --exclude 'package-lock.json' \
        "$PROJECT_DIR/" "$plugin_dest/"
    
    log_success "Plugin synced to: $plugin_dest"
}

# Create a new LocalWP site
create_site() {
    local multisite=false
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --multisite)
                multisite=true
                shift
                ;;
            *)
                shift
                ;;
        esac
    done
    
    local site_name="$SINGLE_SITE_NAME"
    local domain="$SINGLE_SITE_DOMAIN"
    local mode="single site"
    
    if [ "$multisite" = true ]; then
        site_name="$MULTISITE_NAME"
        domain="$MULTISITE_DOMAIN"
        mode="multisite"
    fi
    
    check_localwp
    
    local site_path=$(get_site_path "$site_name")
    
    if site_exists "$site_name"; then
        log_warning "Site '$site_name' already exists at: $site_path"
        log_info "Use 'npm run localwp:reset' to reset it, or 'npm run localwp:sync' to update files"
        return 0
    fi
    
    echo ""
    echo "============================================"
    echo "  LocalWP Site Setup ($mode)"
    echo "============================================"
    echo ""
    echo "This script will guide you through creating a"
    echo "LocalWP site for testing the plugin."
    echo ""
    echo "Site Details:"
    echo "  Name:   $site_name"
    echo "  Domain: $domain"
    echo "  Path:   $site_path"
    echo ""
    
    log_step "Creating LocalWP Site"
    echo ""
    log_info "LocalWP doesn't have a CLI for site creation."
    log_info "Please create the site manually in LocalWP:"
    echo ""
    echo "1. Open LocalWP application"
    echo "2. Click the '+' button to create a new site"
    echo "3. Use these settings:"
    echo "   - Site name: ${CYAN}$site_name${NC}"
    echo "   - Local site domain: ${CYAN}$domain${NC}"
    echo "   - PHP version: 8.0 or higher"
    echo "   - Web server: nginx (preferred)"
    echo "   - MySQL version: 8.0+"
    
    if [ "$multisite" = true ]; then
        echo ""
        echo "4. After site creation, convert to multisite:"
        echo "   - Open Site Shell in LocalWP"
        echo "   - Run: wp core multisite-convert --subdomains=0"
        echo "   - Update wp-config.php if needed"
    fi
    
    echo ""
    log_info "After creating the site, run: npm run localwp:sync"
    echo ""
    
    # Wait for user to create site
    read -p "Press Enter after you've created the site in LocalWP..."
    
    if site_exists "$site_name"; then
        log_success "Site detected at: $site_path"
        sync_plugin "$site_name"
        
        # Install recommended plugins
        install_recommended_plugins "$site_name"
        
        show_site_info "$site_name" "$domain" "$multisite"
    else
        log_warning "Site not found at expected location"
        log_info "Expected path: $site_path"
        log_info "You can run 'npm run localwp:sync' later to sync files"
    fi
}

# Install recommended plugins (matching Playground blueprint)
install_recommended_plugins() {
    local site_name="$1"
    local wp_path=$(get_wp_path "$site_name")
    
    log_info "Note: Install these plugins to match Playground environment:"
    echo "  - Plugin Toggle (plugin-toggle)"
    echo "  - Kadence Blocks (kadence-blocks)"
    echo ""
    log_info "You can install them via LocalWP's WP Admin or Site Shell"
}

# Show site information
show_site_info() {
    local site_name="$1"
    local domain="$2"
    local multisite="$3"
    
    local site_path=$(get_site_path "$site_name")
    local plugin_path=$(get_plugin_path "$site_name")
    
    echo ""
    echo "============================================"
    echo "  LocalWP Site Ready"
    echo "============================================"
    echo "  Site:        $site_name"
    echo "  URL:         http://$domain"
    echo "  Admin:       http://$domain/wp-admin/"
    echo "  Plugin Path: $plugin_path"
    echo "============================================"
    
    if [ "$multisite" = true ]; then
        echo "  Network Admin: http://$domain/wp-admin/network/"
        echo "============================================"
    fi
    
    echo ""
    log_info "Remember to:"
    echo "  1. Start the site in LocalWP"
    echo "  2. Activate the plugin in WordPress admin"
    echo "  3. Run 'npm run localwp:sync' after making changes"
    echo ""
}

# Reset site to clean state
reset_site() {
    local site_name="${1:-$SINGLE_SITE_NAME}"
    
    if ! site_exists "$site_name"; then
        log_error "Site '$site_name' does not exist"
        exit 1
    fi
    
    log_warning "This will delete the plugin files and resync them."
    read -p "Continue? (y/n) " -n 1 -r
    echo
    
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        local plugin_path=$(get_plugin_path "$site_name")
        
        log_info "Removing plugin files..."
        rm -rf "$plugin_path"
        
        log_info "Resyncing plugin..."
        sync_plugin "$site_name"
        
        log_success "Site reset complete"
    else
        log_info "Reset cancelled"
    fi
}

# Sync all existing sites
sync_all() {
    local synced=0
    
    for site_name in "$SINGLE_SITE_NAME" "$MULTISITE_NAME"; do
        if site_exists "$site_name"; then
            sync_plugin "$site_name"
            synced=$((synced + 1))
        fi
    done
    
    if [ $synced -eq 0 ]; then
        log_warning "No LocalWP sites found for this plugin"
        log_info "Run 'npm run localwp:create' to create one"
    else
        log_success "Synced $synced site(s)"
    fi
}

# Show info about all sites
show_info() {
    echo ""
    echo "LocalWP Sites for $PLUGIN_SLUG"
    echo "==============================="
    
    for site_name in "$SINGLE_SITE_NAME" "$MULTISITE_NAME"; do
        local site_path=$(get_site_path "$site_name")
        
        if site_exists "$site_name"; then
            echo ""
            echo "  ${GREEN}✓${NC} $site_name"
            echo "    Path: $site_path"
            
            local plugin_path=$(get_plugin_path "$site_name")
            if [ -d "$plugin_path" ]; then
                echo "    Plugin: ${GREEN}Installed${NC}"
            else
                echo "    Plugin: ${YELLOW}Not synced${NC}"
            fi
        else
            echo ""
            echo "  ${YELLOW}○${NC} $site_name (not created)"
        fi
    done
    
    echo ""
    echo "Commands:"
    echo "  npm run localwp:create           Create single site"
    echo "  npm run localwp:create:multisite Create multisite"
    echo "  npm run localwp:sync             Sync plugin files"
    echo "  npm run localwp:reset            Reset plugin files"
    echo ""
}

# Main command handler
case "${1:-}" in
    create)
        shift
        create_site "$@"
        ;;
    sync)
        sync_all
        ;;
    reset)
        shift
        reset_site "$@"
        ;;
    info)
        show_info
        ;;
    *)
        echo "LocalWP Integration Script"
        echo ""
        echo "Usage:"
        echo "  $0 create [--multisite]   Create a new LocalWP site"
        echo "  $0 sync                   Sync plugin files to all sites"
        echo "  $0 reset [site-name]      Reset site plugin to clean state"
        echo "  $0 info                   Show info about LocalWP sites"
        echo ""
        echo "npm scripts:"
        echo "  npm run localwp:create              Create single site"
        echo "  npm run localwp:create:multisite    Create multisite"
        echo "  npm run localwp:sync                Sync plugin files"
        echo "  npm run localwp:reset               Reset plugin files"
        echo ""
        echo "URL Patterns:"
        echo "  Single site: http://${PLUGIN_SLUG}-single.local"
        echo "  Multisite:   http://${PLUGIN_SLUG}-multisite.local"
        echo ""
        exit 1
        ;;
esac
