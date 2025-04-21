#!/bin/bash

# Make the bin directory executable
chmod +x bin

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
    
    # Wait for WordPress to be ready
    sleep 5
    
    # Activate our plugin
    wp-env run cli wp plugin activate wp-plugin-starter-template-for-ai-coding
    
    echo "WordPress Single Site environment is ready!"
    echo "Site: http://localhost:8888"
    echo "Admin login: admin / password"
    
elif [ "$ENV_TYPE" == "multisite" ]; then
    echo "Setting up multisite environment..."
    
    # Start the environment with multisite configuration
    wp-env start --config=.wp-env.multisite.json
    
    # Wait for WordPress to be ready
    sleep 5
    
    # Create a test site
    wp-env run cli wp site create --slug=testsite --title="Test Site" --email=admin@example.com
    
    # Network activate our plugin
    wp-env run cli wp plugin activate wp-plugin-starter-template-for-ai-coding --network
    
    echo "WordPress Multisite environment is ready!"
    echo "Main site: http://localhost:8888"
    echo "Test site: http://localhost:8888/testsite"
    echo "Admin login: admin / password"
    
else
    echo "Invalid environment type. Use 'single' or 'multisite'."
    exit 1
fi
