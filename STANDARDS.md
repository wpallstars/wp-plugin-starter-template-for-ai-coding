# Plugin standards

Rules every plugin made from the wpallstars starter plugin follows. This file
is the same in each of them: the starter holds the master copy, so a lesson
learned in one plugin goes into the starter's copy, then to every plugin
(`scripts/sync-core.sh` shows the differences). Rules for one plugin go in
its `AGENTS.md` or its `docs/` (Agent docs below), never here.

Names below are placeholders. Each plugin's `AGENTS.md` gives its values:

| Placeholder | Meaning | Example |
|---|---|---|
| `{slug}` | Folder, main file and text domain | `my-plugin` |
| `{prefix}` | Option, hook, function and file prefix: `{PREFIX}` in lower case | `myplugin` |
| `{Prefix}` | Class prefix (`@package`) | `MyPlugin` |
| `{PREFIX}` | Constant prefix | `MYPLUGIN` |
| `{Name}` | Plugin name | My Plugin |
| `{css}` | CSS class and data attribute prefix (`{css}-card`, `data-{css}-setting`) | `mp` |

Minimums: **WordPress 6.2, PHP 7.4** (`readme.txt`, plugin header).
How changes are made and checked: `DEVELOPMENT.md`. Releases: `RELEASING.md`.

## Structure

- Core files are listed in `scripts/core-files.txt`: the feature registry
  (`includes/class-{prefix}.php`), the base feature
  (`includes/class-{prefix}-feature.php`), the settings store
  (`includes/class-{prefix}-settings.php`), the admin screen and Read Me tab
  (`admin/`), the shared GitHub updater (`includes/github-updater/`), the
  scripts, the CI workflow, tool configuration and the shared docs (this
  file, `STYLING.md`, `DEVELOPMENT.md`, `RELEASING.md`, `CONTRIBUTING.md`,
  `CODE_OF_CONDUCT.md`, `SECURITY.md`). They hold no code for one plugin (a
  plugin's own lines in a core file go only between its `{css}-own`
  markers): they read `{Prefix}_Setup` (`includes/class-{prefix}-setup.php`:
  features, settings tabs, header links, settings version and history, the
  plugin's own helpers and admin parts) or use hooks (`{prefix}_admin_tabs`
  for tabs, `{prefix}_admin_enqueue` for its own admin CSS and JS,
  `scripts/preflight-plugin.sh` for its own release checks). Anything only
  one plugin needs goes there, in a feature, or in its own file loaded from
  there. Change a core file in the starter first, then run
  `scripts/sync-core.sh` in each plugin; `scripts/sync-core.sh --check`
  lists core files that differ. A new plugin is a copy of the starter
  renamed with `scripts/rename-plugin.sh`.
- Every plugin keeps up with the starter: the weekly Starter sync workflow
  keeps one `starter-sync` issue open while core files differ
  (`DEVELOPMENT.md` → Starter sync). Work it like any issue: sync, check the
  starter's changelog for changes the plugin's own files need, lint, smoke
  test, pull request.
- One class per feature in `includes/features/`, extending `{Prefix}_Feature`,
  registered in `{Prefix}_Setup::FEATURES`. Features some builds leave out
  go in `{Prefix}_Setup::OPTIONAL_FEATURES` and load only when present.
- `settings()` declares the schema; the admin screen renders, searches and
  saves it with no extra code. Field types and keys: `README.md` → Developers.
- `boot()` returns early unless `self::enabled()`. Features are **off by
  default**; the plugin's `AGENTS.md` lists any the owner asked to be on.
  Turning another feature on by default needs the owner's say.
- A changed default is only sure to reach new installs: each migration and
  any save on the settings screen store every setting, defaults included
  (`set()` writes them all back), and a stored setting keeps its value. A
  setting with no stored value yet (one added since) follows the current
  default, so a new setting's default reaches every site. Change a stored
  value on existing sites only in `migrate()` with a `DB_VERSION` bump, and
  only where the owner agrees.
- A feature that replaces another plugin lists it in a class constant on
  the feature class, `const REPLACES = array(slug => name);`, and sets
  `'replaces' => self::REPLACES`. Other code (migrations, audits, checks for
  active plugins) reads `self::REPLACES`, never a copy of the list, and
  `scripts/replaced-plugins.php` counts it. `migrate()` imports that
  plugin's settings with `self::import_setting()` (fills only unset keys),
  never writing or deleting its options. While that plugin is active the
  feature waits, and the Plugins screen suggests deactivating and deleting
  it (`admin/includes/class-replaced-plugins.php`) with no extra code.
- Migrations run once per `{Prefix}_Setup::DB_VERSION`. After a release, a
  new or changed import needs a version bump and a line in its docblock.
  `uninstall.php` removes every new option, post meta, user meta, transient,
  cron hook and file.
- `README.md` is also the Read Me tab (`admin/includes/class-readme-manager.php`):
  it renders headings, lists, tables, bold, italic, inline code, links
  (http(s) and `#heading` links, with GitHub-style heading IDs) and images
  from the plugin folder on a line of their own
  (`![alt](admin/images/banner.svg)`). Use only that Markdown, or extend the
  renderer in the same change. The tab leaves out HTML comments, anything
  between `<!-- github-only:start -->` and `<!-- github-only:end -->`
  (GitHub-only parts such as the screenshots section) and the badges block
  under the title (`<!-- aidevops:badges:start -->` to
  `<!-- aidevops:badges:end -->`). The `Version: X.Y.Z` line under the
  intro holds the version itself (GitHub shows it as written) and changes
  with every release (`RELEASING.md`).
- The badges block is the starter's, the same in every plugin, and other
  tools leave it alone: `scripts/readme-badges.sh` writes it
  (`scripts/rename-plugin.sh` for a new repository). Three rows, one blank
  line between them: status (CI, SonarCloud, Codacy, CodeFactor, OpenSSF
  Scorecard, licence, latest release); requirements from `readme.txt`
  (Requires WordPress, Tested up to, Requires PHP) and size (the facts in
  `docs/metrics/` that `.github/workflows/repo-metrics.yml` keeps up to
  date); then the languages chart alone. Add a service's badge
  (`--add`, `--codacy`) once it has the repository (`DEVELOPMENT.md` →
  Services setup), never before: it would be a broken image.
  `scripts/preflight-release.sh` warns when the block differs.
- Listing images are in `.wordpress-org/`. Screenshots are
  `.wordpress-org/screenshot-N.png` (WordPress.org's `assets/` names,
  captions in `readme.txt` → Screenshots), which the release zip leaves
  out; they show only what the WordPress.org build shows. GitHub-only pictures, such as
  Updates from GitHub, go in `docs/images/` with no caption in `readme.txt`.
  `scripts/build-banner.sh` turns the banner (`banner.svg`) and the icon
  (`icon.svg`, the banner's picture alone, with no words) into
  `banner-772x250.png`, `banner-1544x500.png`, `icon-128x128.png`,
  `icon-256x256.png` and the shipped `admin/images/banner.svg`,
  `admin/images/banner-details.svg` and `admin/images/icon.svg`, and the
  screenshots into `admin/images/screenshot-N.webp`; the GitHub updater
  shows them on the Updates screen and in View details, and
  `banner-details.svg` and the screenshot copies are in the GitHub build
  only. `scripts/preflight-release.sh` checks their sizes, that the icon,
  View details banner and screenshot copies ship, and that each
  `screenshot-N` has a caption.
- A wpallstars-branded banner keeps the starter's two words layouts, so
  every plugin's banners match. `banner.svg` holds the same four lines on
  the left twice, at sizes 27 (WPALLSTARS), 104 (the name), 72 (the gold
  line) and 33 (the tagline):
  - `<g id="words">`, centred top to bottom against the picture
    (baselines y 128, 240, 326 and 396; `gold-text` gradient y 280 to
    340), becomes `admin/images/banner.svg`: the README on GitHub and the
    Read Me tab.
  - `<g id="words-details" display="none">`, all above y 340 (baselines
    y 86, 190, 270 and 324; `gold-text-details` gradient y 224 to 284),
    becomes `admin/images/banner-details.svg` (GitHub build only) and the
    WordPress.org PNGs. View details (Plugins and Updates screens)
    writes the plugin name in a dark box over the banner's lower left, y
    348 to 448 of 500; the GitHub updater shows `banner-details.svg`
    there, and WordPress.org's View details shows its PNGs.

  Change the words in both groups, and only the words; when a name or
  line is too long, shorten it rather than move or resize the lines.
  Each group is one `<g id=...>` line, its `<text>` lines and `</g>`,
  which is how `scripts/build-banner.sh` finds them.
- Settings → {Name} is the settings screen. A plugin with its own top-level
  menu names it in `{Prefix}_Setup::MENU_PARENT`, and the screen is
  **Settings**, last in that menu (not also under Settings). Link to it with
  `{Prefix}_Admin_Manager::page_url()` or `tab_url()`, never a fixed
  `options-general.php` address. Its header links come from
  `{Prefix}_Setup::header_links()`: `source` (the GitHub repository,
  **Source code**), `support` (its issues, **Support**) and `donate` (**Buy
  me a coffee**); leave one out for no button, and keep labels short so they
  fit one row. The plugin's own screens show the same header
  (`{Prefix}_Admin_Manager::enqueue_header()`, `render_header()`) and their
  sections as the same tabs (`.{css}-nav`, `.{css}-nav__tab`, `is-active`).
  Settings tabs in one group (between dividers) switch without a reload; a
  `{prefix}_admin_tabs` tab joins with `'preload' => true` once it is cheap
  to draw and its script works with its panel hidden.
- Update `README.md` (feature section, hooks, changelog), `changelog.txt`
  (the user-facing changelog entry) and `readme.txt` in the same change.
  `readme.txt` must stay under 10 KB for WordPress.org: one short line per
  feature, every service the plugin contacts under External services, and
  only the newest version's changelog, in short. Details go in `README.md`.
- Credits: every plugin keeps, in `README.md` and `readme.txt` (the **Built
  with AI** section), the credit to aidevops (<https://aidevops.sh>), a line
  sending questions to aidevops, which reads the plugin's docs and code to
  answer them, and the line starting "Made from " that credits the starter
  with a link to it. `scripts/rename-plugin.sh` writes the starter's line
  for a new plugin; keep all three when replacing the starter's README and
  readme.txt. `scripts/preflight-release.sh` warns when a credit is missing.
- Licence: the starter, and every plugin made from it, is GPL-3.0-or-later
  with additional terms under GPL-3.0 section 7(b) in `ATTRIBUTION.txt`
  (WordPress.org accepts GPLv3). The terms make the credit part of the
  licence. Keep:
  - `LICENSE` and `ATTRIBUTION.txt` (core files; both ship in both zips, and
    `ATTRIBUTION.txt` keeps the starter's names word for word);
  - the `License:` and `License URI:` headers in the main file and
    `readme.txt` (the same licence in both), and the GPL notice in the main
    file's comment;
  - the SPDX lines at the top of each source file (licence, copyright, and
    the pointer to `ATTRIBUTION.txt`; a plugin's own new files carry its own
    copyright);
  - the line starting "Made from " in `README.md` and `readme.txt`, and the
    starter's copyright line, "Copyright (C) 2026 Marcus Quinn", in the main
    file and `README.md` → License. Add your own copyright line above it;
    never replace or remove the starter's. `scripts/rename-plugin.sh` writes
    both for a new plugin: its own (this year and `--author`), then the
    starter's as "Parts copyright (C) 2026 Marcus Quinn, from" the starter's
    name and link.

  `scripts/preflight-release.sh` errors when `LICENSE` or `ATTRIBUTION.txt`
  is missing from a zip or the two licences differ, and warns when the
  licence is not GPL-3.0-or-later, `ATTRIBUTION.txt` is missing, or a
  copyright line or a source file's SPDX copyright line is missing.
- Every plugin except SEO Pro Stack ends `README.md` → **Built with AI** with
  the line starting "Works well with " that recommends SEO Pro Stack
  (<https://github.com/wpallstars/seoprostack>), the base plugin for every
  site. Keep it out of `readme.txt`, admin notices and the plugin's screens
  other than the Read Me tab, where WordPress.org's reviewers look for
  plugins promoting others. `scripts/preflight-release.sh` warns when the
  line is missing from `README.md` or appears in `readme.txt`.
- `.distignore` lists files kept out of the release zip. Add new
  development-only files there (the preflight fails when a known one gets
  in), then check the build with Plugin Check.

## Agent docs

AI agents read `AGENTS.md` in every session, so every line there costs every
session: keep it a short map, with the detail where only the task that needs
it reads it. A small plugin has only `AGENTS.md`; a large one adds docs.

- `AGENTS.md` holds the plugin's names (the placeholder table), its rules
  that apply to any change (a line or two each, such as features the owner
  asked to be on), and one line per doc saying when to read it. Near the
  top it tells agents to read this file before any change.
- Agents keep the plugin at the starter's standard, which is set in the
  starter, not in the plugin's copy:
  - Before work, look for an open `starter-sync` issue. If one is open, the
    plugin's core files, this file included, are behind: read the starter's
    copy of any core file or rule the task touches, and do that issue first
    when the task changes the same files.
  - Never change a core file only in the plugin. A fix or rule every plugin
    needs goes to the starter first (a pull request, or an issue there with
    the plugin's case), then comes back with `scripts/sync-core.sh`. Only
    the plugin's own files (`{Prefix}_Setup`, features,
    `phpstan-plugin.neon`, `scripts/preflight-plugin.sh`, `AGENTS.md`,
    `LAUNCH.md`, `docs/`) take changes for this plugin alone.
  - Steps that need the owner's accounts or make secrets (SonarCloud,
    Codacy, `SYNC_PAT`: `DEVELOPMENT.md` → Services setup) are listed for
    the owner, not done by an agent.
- Guidance for one kind of task (a procedure, a checklist, a data format, a
  list of choices) goes in `docs/{topic}.md`, named for the task
  (`docs/presets.md`), and `AGENTS.md` says when to read it: "Adding or
  changing a preset: read `docs/presets.md` first." Move a section there
  when only some tasks need it or it grows past about 15 lines.
- Rules every plugin shares go in this file and `STYLING.md`, in the
  starter; workflows every plugin shares go in `DEVELOPMENT.md` and
  `RELEASING.md`. Never copy them into a plugin's `AGENTS.md` or `docs/`.
- `docs/` is for people working on the plugin and never ships
  (`.distignore`); users' docs stay in `README.md` and `readme.txt`.
- No agent definitions (subagents) in the plugin by default: each AI tool
  has its own format, and a doc serves every tool. Add one only when agents
  keep getting a task wrong even with its doc, and have it read that doc.
- `scripts/preflight-release.sh` warns when `AGENTS.md` is over 150 lines,
  does not name `STANDARDS.md`, still describes the starter (in a plugin),
  names a doc that does not exist, or leaves out one in `docs/`.

## Code rules

- PHP 7.4 syntax and WordPress 6.2 APIs. Guard newer core APIs with
  `function_exists()` or `method_exists()`.
- Capability and nonce checks on every admin action and AJAX handler; escape
  on output; sanitise through the schema.
- SQL goes through `$wpdb->prepare()`: values as `%s`, `%d` or `%f`, and the
  plugin's own table and column names as `%i` (WordPress 6.2), never put
  into the query string; core tables as `$wpdb->posts`, `$wpdb->options` and
  the like. Otherwise Plugin Check warns
  `PluginCheck.Security.DirectDB.UnescapedDBParameter`.
- A notice shown once after an action, read from a query argument
  (`?{prefix}_done=…`), adds that argument to `removable_query_args`, so
  WordPress takes it out of the address and a reload does not repeat it.
- Prefix everything global with `{prefix}_`, `{Prefix}_` or `{PREFIX}_`,
  except the shared GitHub updater: its `wpallstars_` names are the same in
  every plugin, so that one copy can stand in for the others.
- Admin copy: short, plain words, sentence case, no jargon.
- Decide for the user. Within a feature, the plugin makes the choices
  (which plugins, screens or items it applies to) from what it can detect.
  Settings are there to bypass something that causes a problem, not choices
  people need to understand first. A new setting must earn its place;
  prefer detecting the right behaviour plus a short bypass list. Put
  bypasses under Troubleshooting (`'group' => 'troubleshooting'`).
- Site owner in control, performance first: the owner decides what their
  site sends, contacts and shows. Calls to outside services are opt-in where
  they are not the point of the feature, made only as often and for as long
  as needed (cache answers, never on every page load), and never block a
  visitor's page when they can run later. Features that rein in other
  plugins hand the choice to the owner instead of deciding for them.
  WordPress update checks and downloads are the exception (next rule).
- Do not change WordPress update behaviour (update transients,
  `auto_update_*` filters, update checks, including when and where they run)
  outside the shared GitHub updater: Plugin Check reports
  `plugin_updater_detected` as an error, and WordPress.org asks plugins not
  to interfere with the updater. Such a change goes in the shared updater,
  so it reaches GitHub builds only.
- Leave no PHP errors, warnings, notices or deprecations behind. Fix any the
  plugin causes, including ones in other plugins that happen only because of
  this one, in the same change when small or as a tracked issue. Messages
  other plugins cause on their own are theirs: mention them, do not hide them.
- WordPress first: use core's APIs (options, transients, the object cache,
  `WP_Query`, cron, the HTTP API, the Settings and REST APIs) before writing
  your own, and follow the WordPress Coding Standards (`phpcs.xml.dist`).
  Fix a PHPCS finding in the code; an inline `phpcs:ignore` needs the sniff
  and the reason, and an inline `NOSONAR` (SonarCloud) the reason, on that
  line only, such as `// NOSONAR: a cache key, not security.` for `md5()`
  used as a fingerprint or cache key.

## Performance

Every plugin runs on every request of every site it is on, next to many
others, so it must cost nearly nothing when idle and stay fast on large sites.
The lessons come from WordPress and WooCommerce sites with hundreds of
thousands of posts, products and meta rows, where problems invisible on a
test site take the site down.

- **Load only what is used.** Hook each feature on the narrowest hook and
  screen it needs. Admin code runs only in the admin; CSS and JS load only
  on the screens or pages that use them, and nothing loads on the front end
  unless the feature shows something there.
- **No full table scans.** Every query reads only the rows it needs,
  through an index:
  - No unlimited queries (`posts_per_page => -1`, `nopaging`): page or
    batch them.
  - No `'no_found_rows' => false` unless the page shows a total or page
    numbers; set `true` otherwise (counting every match is often the
    slowest part).
  - Ask only for what is used: `'fields' => 'ids'`, and
    `update_post_meta_cache`/`update_post_term_cache` off when meta or
    terms are not read.
  - No lookups or sorting by `meta_value`, `LIKE '%term%'`, `REGEXP`,
    `ORDER BY RAND()` or large `post__not_in` lists on large tables.
    Searching or filtering by the plugin's own data uses its own table with
    indexes on the columns it searches, or taxonomies; full-text search
    uses a full-text index.
  - Index the plugin's own tables (created with `dbDelta()`) for every
    lookup, join and sort. Never duplicate an index a table already has
    (other plugins or the host may have added it, and a copy slows every
    write for no gain): check its keys (`SHOW INDEX`) first and skip any
    whose leading columns an existing key covers. An index on a table the
    plugin does not own (WordPress's or another plugin's) is opt-in, and
    uninstall removes only the ones it added.
  - Admin lists of large tables page, sort only on indexed columns and cache counts.
- **Options:** one autoloaded settings array (`{prefix}_options`). Store
  large or rarely used data with autoload off (`update_option( $name,
  $value, false )`) or in the plugin's own table. Never write an option or
  transient on every page load.
- **Small choice lists:** a `select` or `multi` setting's `options` callable
  runs on every settings save, not only on its screen, because a save checks
  every setting. Never list what grows with the site (pages, posts, users)
  there: one such list ran out of memory on every save with 60,000 pages.
  Mark the field `open` to keep any ID, and offer the list only where it is
  shown, paged or searched.
- **Cache repeated work:** `wp_cache_*` for lookups repeated within a
  request (a persistent object cache keeps them between requests), and
  expiring transients for results that are slow to build. Cache times are at
  least five minutes.
- **Work off the page.** Heavy or bulk work runs in cron, in batches with a
  limit, never on a visitor's page or with no limit. Bulk changes to posts
  or terms use `wp_defer_term_counting()` and
  `wp_suspend_cache_invalidation()`, then turn them back on.
- **No request per page view.** No admin-ajax, REST or remote request on
  every visitor page unless the feature needs it; remote requests a page
  waits on time out within 3 seconds. Admin screens do not wait on remote
  requests either when the answer can be fetched in cron and cached:
  licence and update servers are the usual cause of slow admin screens.
- **Clear only your own cache.** Delete the plugin's own object-cache keys
  or groups, never the whole object cache (`wp_cache_flush()`): on many
  hosts every site on the account shares one memcached server, so a flush
  empties every site's cache and slows each of their next uncached page
  loads (measured on a host with 14 sites: about 0.2 seconds a page, up to
  0.5).
- **Measure on large data.** `scripts/smoke-test.sh` loads every page on a
  site seeded with thousands of posts and meta rows, reports query counts
  and times, and fails on a full table or index scan, or a large sort, in
  the plugin's own queries (`DEVELOPMENT.md` → Smoke test). PHPCS flags the
  patterns above as you write them (`WordPress.DB.SlowDBQuery` and VIP's
  performance sniffs, `phpcs.xml.dist`); an exception, such as an unlimited
  query over a list that cannot grow, needs an inline `phpcs:ignore` with why.

## Updates from GitHub

The one exception to the update rule, at the owner's request (for speed,
reliability and site owners' control, and because the plugins are released
on GitHub first): the shared GitHub updater in `includes/github-updater/`,
which replaces Git Updater.

- Every plugin made from the starter carries a copy. Each copy registers its
  version from `load.php` when its plugin loads; on `plugins_loaded` only the
  newest copy loads, once, and serves every installed plugin with a
  `GitHub Plugin URI` header, in one update check.
- It adds GitHub releases of those plugins to core's own update check and
  `plugins_api`, and leaves the download, install, auto-updates and rollback
  to core. It only adds entries for those plugins, never removing or
  blocking other updates. Its icon, banner and View details (`readme.txt`
  and the screenshots) are the installed plugin's own files.
- Update checks that fall due while someone opens an admin screen run in
  WP-Cron instead: core runs them on `admin_init` when its stored check is
  12 hours old, so that screen waits while WordPress and every plugin's own
  updater ask their servers (seconds on hosts with many premium plugins).
  The updater moves only those three checks (`_maybe_update_core`,
  `_maybe_update_plugins`, `_maybe_update_themes`) to core's own cron
  events, and leaves them in place while WP-Cron is not running. The checks
  on the Plugins, Themes and Updates screens, the twice-daily checks, the
  checks after updating and automatic updates stay as in core.
- It is the same in every plugin apart from its text domain and `@package`.
  Change it in the starter, raise the version in its `load.php`, and copy it
  to each plugin. Plugins change what it does only through its filters
  (`wpallstars_github_updater_enabled`, `wpallstars_github_updater_early`,
  `wpallstars_github_plugins`, `wpallstars_github_token`), never by calling
  its class: another plugin's copy may be the one that runs.
- Keep anything that installs or updates code from outside WordPress.org in
  that folder (and in a feature listed in `.distignore-wporg`, when a plugin
  has a setting for it): the WordPress.org build leaves them out.
- Never put an `Update URI` header in the main file in Git: WordPress.org
  rejects it. `scripts/build-release.sh` adds
  `Update URI: https://github.com/{owner}/{repo}` to the GitHub zip only, so
  WordPress.org never offers a plugin of the same slug in its place, and the
  updater never takes WordPress.org's answer for that build. A site moves to
  WordPress.org updates only by installing the WordPress.org build.
- Tokens for private repositories come only from `wp-config.php`
  (`WPALLSTARS_GITHUB_TOKEN`) or the filter, go only to api.github.com and
  are never stored.
- Release answers are cached for 12 hours (an hour after a failure). "Check
  again" on the Updates screen, or a core check that starts without the
  `update_plugins` site transient (cleared, say, with `wp transient delete
  update_plugins --network`), asks GitHub again, at most once a minute.

## Releases

Two release channels, at the owner's decision:

- **GitHub releases are the stable beta channel.** Every version is released
  there first, as soon as it is ready; sites with the GitHub build (and
  sites that turn on early updates from GitHub) get it at once.
- **WordPress.org gets a version 30 days after its GitHub release**, once it
  has been used on real sites, except a security release (one that fixes a
  vulnerability), which goes to WordPress.org as soon as it is on GitHub.
  It is built from the GitHub tag of the version it ships, never from
  changes that are not on GitHub.
- Say which channel a site is on in `README.md` → Updates and releases and
  in `readme.txt` (FAQ), and mark security releases in the changelog
  ("Security:") so the exception is clear.

Sites install the latest GitHub release whose tag is a plain version and the
asset named exactly `{folder}-X.Y.Z.zip` (the shared updater; Git Updater,
where still active, reads `Version:` on `main` instead), so:

- Publish the GitHub release (tag `vX.Y.Z`, asset `{slug}-X.Y.Z.zip` with a
  `{slug}/` folder, built with `.distignore`) straight after the version
  change reaches `main`: push the tag, and the Release workflow
  (`.github/workflows/release.yml`) builds, checks and publishes it, with
  signed build provenance in a public repository
  (`provenance-{slug}-X.Y.Z.sigstore.json`). No other asset name may start
  with `{slug}`: Git Updater installs the first one that does.
- Never put a pre-release version (`-beta1`, `-rc1`) in `Version:` on `main`;
  mark test releases as pre-releases on GitHub.
- The WordPress.org build, `wordpress-org-{slug}-X.Y.Z.zip` (named so no
  updater picks it; never attach it to a GitHub release), is the release
  build without the files in `.distignore-wporg` (the GitHub updater), the
  `GitHub Plugin URI`, `Primary Branch` and `Release Asset` header lines,
  and `Update URI`.
- It has no affiliate links: guideline 11 does not permit tracking referrals
  in the dashboard, and guideline 12 wants affiliate links to point straight
  at the service. List each one in `.wporg-links` for
  `scripts/build-release.sh` to replace in that build only (format and
  preflight checks: `RELEASING.md` → WordPress.org). GitHub builds keep
  them, disclosed in `README.md` and `readme.txt`.
- Any plugin released on GitHub (made from the starter or not) follows the
  same pattern: a `GitHub Plugin URI: owner/repo` header (and
  `Release Asset: true`), plain version tags, and a `{folder}-X.Y.Z.zip`
  asset with a `{folder}/` inside.
- Build both zips with `scripts/build-release.sh` and check them with
  `scripts/preflight-release.sh` and `scripts/plugin-check.sh`. None of them
  tags, publishes or uploads anything; only the Release workflow publishes,
  and only from a tag someone pushed.
- Releasing and submitting to WordPress.org need the owner's say. Sites
  cannot read a private repository without a token
  (`WPALLSTARS_GITHUB_TOKEN`).

Details: `RELEASING.md`; the plugin's own submission state: `LAUNCH.md`.

## Styling

Styling rules are in `STYLING.md`; read it before changing styles:

- Admin screens: spacing and forms (React forms and modals in wp-admin).
- Front-end styling and dark mode (the Kadence Pro dark mode switcher).

## Testing

CI (`.github/workflows/ci.yml`) runs the code checks, the release preflight,
Plugin Check and a smoke test on every pull request; details and local
commands: `DEVELOPMENT.md`. While a repository is private, CI and review
apps only advise, for speed (`DEVELOPMENT.md` → While private): fix failures
your change causes before merging; open an issue for any other failure and
merge anyway. Do not turn on branch protection, required checks or paid
reviewers. At public launch (owner's say), run the sweep in
`DEVELOPMENT.md` → At public launch, which makes them required.

The checks catch errors, not wrong behaviour, so also verify on real
WordPress:

1. `scripts/lint.sh` (syntax, ShellCheck, PHPCS, PHPStan; run
   `composer install` once). Fix findings in the code; never grow
   `phpstan-baseline.neon` or add a `phpcs:ignore` without a reason.
2. The user reviews on one local test site per plugin, shared by every
   session and worktree, showing a **combined preview**: `origin/main` plus
   every open pull request, merged together. Update it only with
   `scripts/preview-site.sh`, from any worktree (`--dry-run` reports what it
   would include); how it works, conflicts and throwaway sites for your own
   checks: `DEVELOPMENT.md` → Preview site.
   - **Never** `rsync` your worktree into the shared site or deploy it with
     Git hooks (shared by every worktree): either hides every other
     session's work or deploys the wrong checkout.
   - Only pushed work with an open PR is included. Before asking the user to
     look at unmerged work, push the branch, open a draft PR and run the
     script. After merging a PR, run it again and check that the stamp lists
     your merge in `main` before telling the user to look. Tell the user
     which PRs it leaves out.
   - Size every test site, shared or throwaway, as `DEVELOPMENT.md` → Test
     site resources says: PHP's defaults fill up and the slowdowns look like
     bugs.
3. Exercise the changed feature through the admin UI or HTTP, and check the
   debug log for new messages mentioning `{slug}` or a plugin it affects
   (`wp-content/debug.log`, or the file Debug Log Manager writes in
   `wp-content/uploads/debug-log-manager/` when it is active). For settings
   imports, seed the replaced plugin's options and delete `{prefix}_options`
   and `{prefix}_db_version` while the plugin is inactive, then activate it.
4. For changes that touch core APIs, also smoke-test on WordPress 6.2 with
   PHP 7.4 (`scripts/smoke-test.sh --wp 6.2 --php 7.4`, or the
   `wordpress:php7.4-apache` Docker image with
   `wp core download --version=6.2 --force`).
5. For front-end styling, view the page with the Kadence theme in light and
   dark mode; without Kadence Pro, simulate the switcher as `STYLING.md` →
   Front-end styling and dark mode says.

Since WordPress 5.6, posts restored from the Bin become drafts; republish
test posts after.
