=== WP Plugin Starter ===
Contributors: wpallstars
Donate link: https://buymeacoffee.com/marcusquinn
Tags: starter, boilerplate, settings, developer, template
Requires at least: 6.2
Tested up to: 7.1
Requires PHP: 7.4
Stable tag: 1.0.9
License: GPLv2 or later
License URI: https://www.gnu.org/licenses/gpl-2.0.html

A clean start for a WordPress plugin: a settings screen, a Read Me tab, updates from GitHub and release scripts, ready for your features.

== Description ==

WP Plugin Starter is what wpallstars plugins are made from. It has no features of its own: it holds the parts every plugin needs, so a new plugin starts with them working.

* **A settings screen** (Settings → WP Plugin Starter) that features fill by declaring their settings, saved instantly, searchable, in tabs. With no features yet it shows one empty tab.
* **A Read Me tab** that shows the plugin's README.md, banner included.
* **Features as classes**, off by default, with settings, hooks, one-off imports from the plugins they replace and clean uninstall.
* **Release and check scripts**: lint, smoke test, release build, preflight and Plugin Check.

Start a plugin from it on GitHub (wpallstars/wp-plugin-starter-template-for-ai-coding): the Read Me tab explains how.

= Built with AI =

WP Plugin Starter is built and maintained with aidevops (https://aidevops.sh), the same developer's open-source AI harness for creating and managing anything online with AI.

Questions about using or changing WP Plugin Starter: ask aidevops. It reads the plugin's docs and code to answer, and can report a problem for you.

Made from WP Plugin Starter (https://github.com/wpallstars/wp-plugin-starter-template-for-ai-coding), the wpallstars starter plugin.

== Installation ==

1. Upload the `wp-plugin-starter-template` folder to `/wp-content/plugins/`, or install the zip from Plugins → Add New → Upload Plugin.
2. Activate it, then open Settings → WP Plugin Starter.

== Frequently Asked Questions ==

= Does it do anything on its own? =

No. It adds an empty settings screen and a Read Me tab, ready for a plugin's features.

= Where do I get help? =

Ask aidevops (https://aidevops.sh): open the plugin's repository, or your site, with it and ask. To report a problem, use the Report a problem link on the settings screen.

= Does it contact other services? =

No. The WordPress.org build contacts nothing outside WordPress.

== Changelog ==

= 1.0.9 =
* Developers: performance rules for every plugin made from the starter (STANDARDS.md → Performance), enforced by WordPress VIP's performance sniffs in PHPCS and by a smoke test on 10,000 posts that fails on a full table scan or large sort in the plugin's own queries. Nothing changes for users.

Every change: changelog.txt.

== Upgrade Notice ==

= 1.0.1 =
Fixes: a failing options list can no longer stop every page after an update, and GitHub updates are more reliable.
