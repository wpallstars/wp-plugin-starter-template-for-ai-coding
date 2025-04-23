#!/bin/bash

# Make this script executable
chmod +x "$0"

# Check if environment type is provided
if [ -z "$1" ]; then
    echo "Usage: $0 [single|multisite|playground-single|playground-multisite]"
    exit 1
fi

ENV_TYPE=$1

# Function to check if a command exists
command_exists() {
    command -v "$1" &> /dev/null
}

# Function to install wp-env if needed
install_wp_env() {
    if ! command_exists wp-env; then
        echo "wp-env is not installed. Installing..."
        npm install -g @wordpress/env
    fi
}

# Function to install wp-playground if needed
install_wp_playground() {
    # Check if we have a local installation
    if [ ! -d "node_modules/@wp-playground" ]; then
        echo "WordPress Playground is not installed locally. Installing..."
        npm install --save-dev @wp-playground/client @wp-playground/blueprints
    fi
}

if [ "$ENV_TYPE" == "single" ]; then
    echo "Setting up single site environment..."

    # Install wp-env if needed
    install_wp_env

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

    # Install wp-env if needed
    install_wp_env

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

elif [ "$ENV_TYPE" == "playground-single" ]; then
    echo "Setting up WordPress Playground single site environment..."

    # Install wp-playground if needed
    install_wp_playground

    # Create plugin zip
    echo "Creating plugin zip..."
    mkdir -p dist
    zip -r dist/plugin.zip . -x "node_modules/*" "dist/*" ".git/*"

    # Update blueprint to use local plugin
    cat > playground/blueprint.json << EOF
{
  "landingPage": "/wp-admin/",
  "preferredVersions": {
    "php": "8.0",
    "wp": "latest"
  },
  "steps": [
    {
      "step": "login",
      "username": "admin",
      "password": "password"
    },
    {
      "step": "installPlugin",
      "pluginZipFile": {
        "resource": "local",
        "path": "dist/plugin.zip"
      }
    },
    {
      "step": "activatePlugin",
      "pluginSlug": "wp-plugin-starter-template-for-ai-coding"
    }
  ]
}
EOF

    # Start WordPress Playground
    echo "Starting WordPress Playground..."
    if command_exists python3; then
        python3 -m http.server 8888 --directory playground &
        echo "Opening WordPress Playground in your browser..."
        if command_exists open; then
            open http://localhost:8888/index.html
        elif command_exists xdg-open; then
            xdg-open http://localhost:8888/index.html
        elif command_exists start; then
            start http://localhost:8888/index.html
        else
            echo "Please open http://localhost:8888/index.html in your browser"
        fi
    else
        echo "Python3 is not installed. Please open playground/index.html in your browser."
    fi

    # Wait for WordPress Playground to be ready
    echo "Waiting for WordPress Playground to be ready..."
    sleep 5

    echo "WordPress Playground Single Site environment is ready!"
    echo "Site: http://localhost:8888"
    echo "Admin login: admin / password"
    echo "Press Ctrl+C to stop the server when done."

elif [ "$ENV_TYPE" == "playground-multisite" ]; then
    echo "Setting up WordPress Playground multisite environment..."

    # Install wp-playground if needed
    install_wp_playground

    # Create plugin zip
    echo "Creating plugin zip..."
    mkdir -p dist
    zip -r dist/plugin.zip . -x "node_modules/*" "dist/*" ".git/*"

    # Update blueprint to use local plugin
    cat > playground/multisite-blueprint.json << EOF
{
  "landingPage": "/wp-admin/network/",
  "preferredVersions": {
    "php": "8.0",
    "wp": "latest"
  },
  "steps": [
    {
      "step": "defineWpConfig",
      "name": "WP_ALLOW_MULTISITE",
      "value": true
    },
    {
      "step": "defineWpConfig",
      "name": "MULTISITE",
      "value": true
    },
    {
      "step": "defineWpConfig",
      "name": "SUBDOMAIN_INSTALL",
      "value": false
    },
    {
      "step": "defineWpConfig",
      "name": "DOMAIN_CURRENT_SITE",
      "value": "localhost"
    },
    {
      "step": "defineWpConfig",
      "name": "PATH_CURRENT_SITE",
      "value": "/"
    },
    {
      "step": "defineWpConfig",
      "name": "SITE_ID_CURRENT_SITE",
      "value": 1
    },
    {
      "step": "defineWpConfig",
      "name": "BLOG_ID_CURRENT_SITE",
      "value": 1
    },
    {
      "step": "login",
      "username": "admin",
      "password": "password"
    },
    {
      "step": "installPlugin",
      "pluginZipFile": {
        "resource": "local",
        "path": "dist/plugin.zip"
      }
    },
    {
      "step": "activatePlugin",
      "pluginSlug": "wp-plugin-starter-template-for-ai-coding",
      "networkWide": true
    },
    {
      "step": "runPHP",
      "code": "<?php\n// Create a test subsite\n$domain = 'localhost';\n$path = '/testsite/';\n$title = 'Test Subsite';\n$user_id = 1;\n\nif (!get_site_by_path($domain, $path)) {\n    $blog_id = wpmu_create_blog($domain, $path, $title, $user_id);\n    if (is_wp_error($blog_id)) {\n        echo 'Error creating subsite: ' . $blog_id->get_error_message();\n    } else {\n        echo 'Created subsite with ID: ' . $blog_id;\n    }\n} else {\n    echo 'Subsite already exists';\n}\n"
    }
  ]
}
EOF

    # Start WordPress Playground
    echo "Starting WordPress Playground..."
    if command_exists python3; then
        python3 -m http.server 8888 --directory playground &
        echo "Opening WordPress Playground in your browser..."
        if command_exists open; then
            open http://localhost:8888/multisite.html
        elif command_exists xdg-open; then
            xdg-open http://localhost:8888/multisite.html
        elif command_exists start; then
            start http://localhost:8888/multisite.html
        else
            echo "Please open http://localhost:8888/multisite.html in your browser"
        fi
    else
        echo "Python3 is not installed. Please open playground/multisite.html in your browser."
    fi

    # Wait for WordPress Playground to be ready
    echo "Waiting for WordPress Playground to be ready..."
    sleep 5

    echo "WordPress Playground Multisite environment is ready!"
    echo "Main site: http://localhost:8888"
    echo "Test site: http://localhost:8888/testsite"
    echo "Admin login: admin / password"
    echo "Press Ctrl+C to stop the server when done."

else
    echo "Invalid environment type. Use 'single', 'multisite', 'playground-single', or 'playground-multisite'."
    exit 1
fi
