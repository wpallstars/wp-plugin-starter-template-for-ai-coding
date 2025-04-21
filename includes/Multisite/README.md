# Multisite Support

This directory contains placeholder files for multisite-specific functionality. When developing a plugin based on this template, you can extend these files or create additional classes in this directory to implement multisite features.

## Usage

To implement multisite-specific functionality:

1. Create your multisite-specific classes in this directory
2. Load and initialize these classes in your main plugin file when in a multisite environment:

```php
// Load multisite support classes if in multisite environment
if ( is_multisite() ) {
    require_once WP_PLUGIN_STARTER_TEMPLATE_PATH . 'includes/Multisite/class-multisite.php';

    // Initialize multisite support
    $multisite = new WPALLSTARS\PluginStarterTemplate\Multisite\Multisite();
}
```

## Testing

For information on testing your plugin in a multisite environment, see the [Testing Framework](../../.wiki/Testing-Framework.md) documentation.
