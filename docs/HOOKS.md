# WP Plugin Starter hooks

Every `wpstarter_*` filter and action in the code, and whether site code may
rely on it (`STANDARDS.md` → Code rules: hooks are a contract with site
code). `scripts/check-hooks.js` (`scripts/lint.sh hooks`, run by CI) fails
when this list and the code disagree, including a Type that is not how the
code calls the hook (`apply_filters*()` is a filter, `do_action*()` an
action); a call inside a PHP comment does not count. `README.md` →
Developers describes the most used ones in words.

## Status

- **supported**: for site code (a site's own plugin or theme, a must-use
  file). Kept, or kept working through `apply_filters_deprecated()` /
  `do_action_deprecated()`, for at least two minor releases before it is
  removed (Deprecation rule below).
- **internal**: no promise. For WP Plugin Starter's own code (its features,
  other plugins by the same maker, tests); may change or go without notice.

A new hook is internal unless site code is meant to use it.

## Deprecation rule

A supported hook is never removed or renamed in one step:

1. Keep it, or keep the old name working by calling it through
   `apply_filters_deprecated()` / `do_action_deprecated()` (with the version
   and the replacement), for at least two minor releases: deprecated in a
   1.3 release, it stays in every 1.4 release and in 1.5.0, and may go in a
   release after that.
2. Name the hook, its replacement and the release it will go in the
   changelog (`changelog.txt`, `README.md`) when it is deprecated, and again
   when it is removed.
3. Keep its row here, still supported, until the release that removes it,
   then delete the row in that change. A supported hook stays supported
   until then: never mark it internal to remove it sooner.

An internal hook may be removed at once, with its row.

The check keeps this honest. It fails when:

- the code calls a `wpstarter_*` hook that has no row;
- a row's Type is not how the code calls it;
- a row's hook is no longer called, directly or through a `_deprecated`
  function;
- a hook supported at the latest release tag is gone or marked internal,
  unless a release at least two minor versions back already called it
  through a `_deprecated` function. Each major.minor released counts once,
  across a major version too: before 1.0.0, 0.9 is one back and 0.8 two.

A call inside a PHP comment does not count. A name built at run time
(`"wpstarter_{$id}_items"`) counts when at least one row fits it: list each
name it makes.

## Adding a hook

Add the row in the same change as the code, in alphabetical order:

- **Hook**: the name, in backticks.
- **Type**: `filter` (returns its first argument, changed or not) or
  `action` (returns nothing).
- **Status**: `supported` or `internal`.
- **Since**: the first release that has it.
- **Called in**: the class that calls it.
- **Arguments**: for a filter, the value filtered, then the other
  arguments; for an action, all of them, as at the call.

Hooks the core files call (`scripts/core-files.txt`) are the same in every
plugin made from the starter, and so are their rows, apart from Since: the
plugin's first release that has them. After `scripts/sync-core.sh` brings a
new one, add its row from the starter's list (the check names it).

## Hooks

| Hook | Type | Status | Since | Called in | Arguments |
|---|---|---|---|---|---|
| `wpstarter_admin_enqueue` | action | supported | 1.0.0 | `WPStarter_Admin_Manager` | `$page_tab`: once for each tab drawn, the active tab first |
| `wpstarter_admin_script_data` | filter | supported | 1.0.0 | `WPStarter_Admin_Manager` | the settings screen script's `wpstarterAdmin` data (`ajaxUrl`, `nonce`, `tab`, `tabs`, `titles`, `network`, `i18n` and more); `$tab` |
| `wpstarter_admin_script_deps` | filter | supported | 1.0.0 | `WPStarter_Admin_Manager` | `$deps`; `$page_tab` |
| `wpstarter_admin_tabs` | filter | supported | 1.0.0 | `WPStarter_Admin_Manager` | `$tabs` |
| `wpstarter_admin_theme_screens` | filter | internal | 1.0.35 | `WPStarter_Admin_Theme` | screen IDs: the settings screen and the network settings screen |
| `wpstarter_can_change_settings` | filter | supported | 1.0.0 | `WPStarter_Settings` | `true` |
| `wpstarter_features` | filter | supported | 1.0.0 | `WPStarter` | feature class names |
| `wpstarter_network_setting_panel` | action | supported | 1.0.35 | `WPStarter_Settings_Manager` | `$key`, `$field` |
| `wpstarter_network_settings_tab_after` | action | supported | 1.0.35 | `WPStarter_Settings_Manager` | `$tab` |
| `wpstarter_plugins_skipped` | filter | supported | 1.0.0 | `WPStarter_Feature` | `false` |
| `wpstarter_redundant_plugins` | filter | supported | 1.0.50 | `WPStarter_Replaced_Plugins` | `array()`: plugin files |
| `wpstarter_replaced_plugin_extras` | filter | supported | 1.0.0 | `WPStarter_Replaced_Plugins` | `array()`: plain names; `$slug` |
| `wpstarter_replaces_link` | filter | internal | 1.0.40 | `WPStarter_Settings_Manager` | `$link` (`url`, `label`); `$slug`, the plugin file, `$name` |
| `wpstarter_setting_panel` | action | supported | 1.0.0 | `WPStarter_Settings_Manager` | `$key`, `$field` |
| `wpstarter_setting_saved` | action | supported | 1.0.0 | `WPStarter_Settings`, `WPStarter_Network_Sites` | `$key`, `$value` |
| `wpstarter_settings_changed` | action | supported | 1.0.35 | `WPStarter_Settings`, `WPStarter_Network_Sites` | `$old`, `$new` |
| `wpstarter_settings_schema` | filter | supported | 1.0.0 | `WPStarter_Settings` | `$schema` |
| `wpstarter_settings_tab_after` | action | supported | 1.0.0 | `WPStarter_Settings_Manager` | `$tab` |
| `wpstarter_stored_active_plugins` | filter | supported | 1.0.0 | `WPStarter_Feature` | `$files` |
| `wpstarter_troubleshooting_open` | filter | supported | 1.0.24 | `WPStarter_Settings_Manager` | `false`; `$key` |
