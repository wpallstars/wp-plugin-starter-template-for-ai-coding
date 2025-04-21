#!/bin/bash

# Make this script executable
chmod +x "$0"

# Check if wp-env is installed
if ! command -v wp-env &> /dev/null; then
    echo "wp-env is not installed. Installing..."
    npm install -g @wordpress/env
fi

# Check if environment type is provided
if [ -z "$1" ]; then
    echo "Usage: $0 [single|multisite]"
    exit 1
fi

ENV_TYPE=$1

if [ "$ENV_TYPE" == "single" ]; then
    echo "Setting up single site environment..."

    # Start the environment
    wp-env start

    # Wait for WordPress to be ready with a timeout
    MAX_ATTEMPTS=30
    ATTEMPT=0
    echo "Waiting for WordPress to be ready..."
    until wp-env run cli wp core is-installed || [ $ATTEMPT -ge $MAX_ATTEMPTS ]; do
        ATTEMPT=$((ATTEMPT+1))
        echo "Attempt $ATTEMPT/$MAX_ATTEMPTS..."
        sleep 2
    done

    if [ $ATTEMPT -ge $MAX_ATTEMPTS ]; then
        echo "Timed out waiting for WordPress to be ready."
        exit 1
    fi

    # Activate our plugin
    if ! wp-env run cli wp plugin activate wp-plugin-starter-template-for-ai-coding; then
        echo "Failed to activate plugin. Exiting."
        exit 1
    fi

    echo "WordPress Single Site environment is ready!"
    echo "Site: http://localhost:8888"
    echo "Admin login: admin / password"

elif [ "$ENV_TYPE" == "multisite" ]; then
    echo "Setting up multisite environment..."

    # Start the environment with multisite configuration
    wp-env start --config=.wp-env.multisite.json

    # Wait for WordPress to be ready with a timeout
    MAX_ATTEMPTS=30
    ATTEMPT=0
    echo "Waiting for WordPress to be ready..."
    until wp-env run cli wp core is-installed || [ $ATTEMPT -ge $MAX_ATTEMPTS ]; do
        ATTEMPT=$((ATTEMPT+1))
        echo "Attempt $ATTEMPT/$MAX_ATTEMPTS..."
        sleep 2
    done

    if [ $ATTEMPT -ge $MAX_ATTEMPTS ]; then
        echo "Timed out waiting for WordPress to be ready."
        exit 1
    fi

    # Create a test site
    if ! wp-env run cli wp site create --slug=testsite --title="Test Site" --email=admin@example.com; then
        echo "Failed to create test site. Exiting."
        exit 1
    fi

    # Network activate our plugin
    if ! wp-env run cli wp plugin activate wp-plugin-starter-template-for-ai-coding --network; then
        echo "Failed to activate plugin. Exiting."
        exit 1
    fi

    echo "WordPress Multisite environment is ready!"
    echo "Main site: http://localhost:8888"
    echo "Test site: http://localhost:8888/testsite"
    echo "Admin login: admin / password"

else
    echo "Invalid environment type. Use 'single' or 'multisite'."
    exit 1
fi
