#!/bin/bash

# WordPress Playground CLI Testing Script
# For use by AI coding assistants and developers
#
# This script provides a simple interface to start/stop WordPress Playground
# for local testing with the plugin. Uses @wp-playground/cli 3.0.22+
#
# Usage:
#   ./bin/playground-test.sh start [--multisite] [--port PORT]
#   ./bin/playground-test.sh stop
#   ./bin/playground-test.sh status
#
# Examples:
#   npm run playground:start              # Start single site on port 8888
#   npm run playground:start:multisite    # Start multisite on port 8889
#   npm run playground:stop               # Stop all playground instances
#   npm run playground:status             # Check if playground is running

set -e

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
PID_FILE="$PROJECT_DIR/.playground.pid"
DEFAULT_PORT=8888
MULTISITE_PORT=8889
PLUGIN_SLUG="wp-plugin-starter-template"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
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

# Check if @wp-playground/cli is installed
check_cli() {
    if ! npx @wp-playground/cli --version > /dev/null 2>&1; then
        log_error "@wp-playground/cli is not installed"
        log_info "Run: npm install"
        exit 1
    fi
    local version=$(npx @wp-playground/cli --version 2>/dev/null)
    log_info "Using @wp-playground/cli version: $version"
}

# Create plugin zip for installation
create_plugin_zip() {
    log_info "Creating plugin zip..."
    mkdir -p "$PROJECT_DIR/dist"
    
    cd "$PROJECT_DIR"
    zip -r "dist/$PLUGIN_SLUG.zip" . \
        -x "node_modules/*" \
        -x "dist/*" \
        -x ".git/*" \
        -x "vendor/*" \
        -x "tests/*" \
        -x "cypress/*" \
        -x "*.zip" \
        -x ".github/*" \
        -x ".agents/*" \
        -x ".wiki/*" \
        -x "reference-plugins/*" \
        > /dev/null 2>&1
    
    log_success "Plugin zip created: dist/$PLUGIN_SLUG.zip"
}

# Start WordPress Playground
start_playground() {
    local multisite=false
    local port=$DEFAULT_PORT
    local blueprint="$PROJECT_DIR/playground/blueprint.json"
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --multisite)
                multisite=true
                port=$MULTISITE_PORT
                blueprint="$PROJECT_DIR/playground/multisite-blueprint.json"
                shift
                ;;
            --port)
                port="$2"
                shift 2
                ;;
            *)
                shift
                ;;
        esac
    done
    
    # Check if already running
    if [ -f "$PID_FILE" ]; then
        local old_pid=$(cat "$PID_FILE")
        if kill -0 "$old_pid" 2>/dev/null; then
            log_warning "Playground is already running (PID: $old_pid)"
            log_info "Run 'npm run playground:stop' first to restart"
            exit 1
        else
            rm -f "$PID_FILE"
        fi
    fi
    
    # Check port availability
    if lsof -i ":$port" > /dev/null 2>&1; then
        log_error "Port $port is already in use"
        exit 1
    fi
    
    check_cli
    create_plugin_zip
    
    local mode="single site"
    if [ "$multisite" = true ]; then
        mode="multisite"
    fi
    
    log_info "Starting WordPress Playground ($mode) on port $port..."
    log_info "Blueprint: $blueprint"
    
    # Start the server in background
    cd "$PROJECT_DIR"
    npx @wp-playground/cli server \
        --blueprint "$blueprint" \
        --port "$port" \
        --login \
        > "$PROJECT_DIR/.playground.log" 2>&1 &
    
    local server_pid=$!
    echo "$server_pid" > "$PID_FILE"
    
    # Wait for server to be ready
    log_info "Waiting for server to be ready..."
    local timeout=120
    local elapsed=0
    
    while ! curl -s "http://localhost:$port" > /dev/null 2>&1; do
        if [ $elapsed -ge $timeout ]; then
            log_error "Timeout waiting for WordPress Playground to start"
            log_info "Check logs: cat $PROJECT_DIR/.playground.log"
            kill "$server_pid" 2>/dev/null || true
            rm -f "$PID_FILE"
            exit 1
        fi
        
        # Check if process is still running
        if ! kill -0 "$server_pid" 2>/dev/null; then
            log_error "Server process died unexpectedly"
            log_info "Check logs: cat $PROJECT_DIR/.playground.log"
            rm -f "$PID_FILE"
            exit 1
        fi
        
        sleep 2
        elapsed=$((elapsed + 2))
        echo -ne "\r${BLUE}[INFO]${NC} Waiting... $elapsed/$timeout seconds"
    done
    
    echo ""
    log_success "WordPress Playground is ready!"
    echo ""
    echo "============================================"
    echo "  WordPress Playground ($mode)"
    echo "============================================"
    echo "  URL:      http://localhost:$port"
    echo "  Admin:    http://localhost:$port/wp-admin/"
    echo "  Login:    admin / password"
    echo "  PID:      $server_pid"
    echo "============================================"
    echo ""
    log_info "Run 'npm run playground:stop' to stop the server"
    log_info "Logs: $PROJECT_DIR/.playground.log"
}

# Stop WordPress Playground
stop_playground() {
    if [ -f "$PID_FILE" ]; then
        local pid=$(cat "$PID_FILE")
        if kill -0 "$pid" 2>/dev/null; then
            log_info "Stopping WordPress Playground (PID: $pid)..."
            kill "$pid" 2>/dev/null || true
            
            # Wait for process to stop
            local timeout=10
            local elapsed=0
            while kill -0 "$pid" 2>/dev/null && [ $elapsed -lt $timeout ]; do
                sleep 1
                elapsed=$((elapsed + 1))
            done
            
            # Force kill if still running
            if kill -0 "$pid" 2>/dev/null; then
                log_warning "Force killing process..."
                kill -9 "$pid" 2>/dev/null || true
            fi
            
            log_success "WordPress Playground stopped"
        else
            log_warning "Process not running"
        fi
        rm -f "$PID_FILE"
    else
        log_warning "No PID file found. Playground may not be running."
    fi
    
    # Clean up any orphaned processes on common ports
    for port in $DEFAULT_PORT $MULTISITE_PORT; do
        local orphan_pid=$(lsof -t -i ":$port" 2>/dev/null || true)
        if [ -n "$orphan_pid" ]; then
            log_info "Found process on port $port (PID: $orphan_pid), stopping..."
            kill "$orphan_pid" 2>/dev/null || true
        fi
    done
}

# Check status
check_status() {
    echo ""
    echo "WordPress Playground Status"
    echo "============================"
    
    if [ -f "$PID_FILE" ]; then
        local pid=$(cat "$PID_FILE")
        if kill -0 "$pid" 2>/dev/null; then
            log_success "Running (PID: $pid)"
        else
            log_warning "PID file exists but process not running"
            rm -f "$PID_FILE"
        fi
    else
        log_info "Not running (no PID file)"
    fi
    
    echo ""
    echo "Port Status:"
    for port in $DEFAULT_PORT $MULTISITE_PORT; do
        if lsof -i ":$port" > /dev/null 2>&1; then
            local port_pid=$(lsof -t -i ":$port" 2>/dev/null || echo "unknown")
            echo "  Port $port: ${GREEN}IN USE${NC} (PID: $port_pid)"
            
            # Test if it's responding
            if curl -s "http://localhost:$port" > /dev/null 2>&1; then
                echo "    └─ HTTP: ${GREEN}OK${NC}"
            else
                echo "    └─ HTTP: ${RED}NOT RESPONDING${NC}"
            fi
        else
            echo "  Port $port: ${YELLOW}AVAILABLE${NC}"
        fi
    done
    echo ""
}

# Main command handler
case "${1:-}" in
    start)
        shift
        start_playground "$@"
        ;;
    stop)
        stop_playground
        ;;
    status)
        check_status
        ;;
    *)
        echo "WordPress Playground CLI Testing Script"
        echo ""
        echo "Usage:"
        echo "  $0 start [--multisite] [--port PORT]  Start WordPress Playground"
        echo "  $0 stop                               Stop WordPress Playground"
        echo "  $0 status                             Check playground status"
        echo ""
        echo "npm scripts:"
        echo "  npm run playground:start              Start single site"
        echo "  npm run playground:start:multisite    Start multisite"
        echo "  npm run playground:stop               Stop playground"
        echo "  npm run playground:status             Check status"
        echo ""
        exit 1
        ;;
esac
