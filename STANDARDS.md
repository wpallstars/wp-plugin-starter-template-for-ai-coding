# Plugin standards

Rules every plugin made from the wpallstars starter plugin follows. This file
is the same in each of them: the starter holds the master copy, so a lesson
learned in one plugin goes into the starter's copy and then to every plugin
(`scripts/sync-core.sh` shows the differences). Never put rules for one
  plugin here; they go in its `AGENTS.md` or its `docs/` (Agent docs below).

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
  scripts, the CI workflow and tool configuration, and the shared docs (this
  file, `DEVELOPMENT.md`, `RELEASING.md`, `CONTRIBUTING.md`,
  `CODE_OF_CONDUCT.md`, `SECURITY.md`).
  A plugin's copy differs from the starter's only in the names above. They
  hold no code for one plugin: they read `{Prefix}_Setup`
  (`includes/class-{prefix}-setup.php`: features, settings tabs, header
  links, settings version and history, the plugin's own helpers and admin
  parts) or use hooks (`{prefix}_admin_tabs` for tabs,
  `{prefix}_admin_enqueue` for the plugin's own admin CSS and JS,
  `scripts/preflight-plugin.sh` for its own release checks). Anything only
  one plugin needs goes there, in a feature, or in its own file loaded from
  there. To change a core file, change the starter first, then run
  `scripts/sync-core.sh` in each plugin; `scripts/sync-core.sh --check` lists
  core files that differ. A new plugin starts as a copy of the starter
  renamed with `scripts/rename-plugin.sh`.
- Every plugin keeps up with the starter. The weekly Starter sync workflow
  (`.github/workflows/starter-sync.yml`) compares the plugin's core files
  with the starter's and keeps one issue labelled `starter-sync` open while
  any differ, with the files and the steps; it closes the issue once they
  match. Work that issue like any other: sync, check the starter's
  changelog for changes the plugin's own files need, lint, smoke test,
  pull request. A change the plugin made to a core file goes into the
  starter first.
- One class per feature in `includes/features/`, extending `{Prefix}_Feature`,
  registered in `{Prefix}_Setup::FEATURES`. Features some builds leave out
  go in `{Prefix}_Setup::OPTIONAL_FEATURES` and load only when present.
- `settings()` declares the schema; the admin screen renders, searches and
  saves it with no extra code. Field types and keys: `README.md` → Developers.
- `boot()` returns early unless `self::enabled()`. Features are **off by
  default**; the plugin's `AGENTS.md` lists any the owner asked to be on.
  Turning another feature on by default needs the owner's say.
- A feature that replaces another plugin sets `'replaces' => array(slug => name)`
  and imports that plugin's settings in `migrate()` with
  `self::import_setting()` (fills only unset keys). It never writes or
  deletes the other plugin's options. While that plugin is active the
  feature waits, and the Plugins screen suggests deactivating and deleting
  it (`admin/includes/class-replaced-plugins.php`) with no extra code.
- Migrations run once per `{Prefix}_Setup::DB_VERSION`. After a release, a
  new or changed import needs a version bump and a line in its docblock.
- New options, post meta, user meta, transients, cron hooks and files must be
  removed in `uninstall.php`.
- `README.md` is also the plugin's Read Me tab
  (`admin/includes/class-readme-manager.php`), which renders headings, lists,
  tables, bold, italic, inline code, links (http(s) and `#heading` links,
  with GitHub-style heading IDs) and images from the plugin folder on a line
  of their own (`![alt](admin/images/banner.svg)`). Use only that Markdown,
  or extend the renderer in the same change. It leaves out HTML comments and
  the badges block under the title (`<!-- aidevops:badges:start -->` to
  `<!-- aidevops:badges:end -->`), which is for GitHub only: CI, SonarCloud,
  Codacy, CodeFactor, license, latest release, and the repository facts in
  `docs/metrics/` that `.github/workflows/repo-metrics.yml` keeps up to date.
  `scripts/rename-plugin.sh` rebuilds the block for the new repository; add
  the new Codacy badge once Codacy has the repository. It also leaves out
  anything between `<!-- github-only:start -->` and `<!-- github-only:end -->`,
  for GitHub-only parts such as the screenshots section: screenshots are
  `.wordpress-org/screenshot-N.png` (WordPress.org's `assets/` names, captions
  in `readme.txt` → Screenshots), which the release zip leaves out.
- Update `README.md` (feature section, hooks, changelog), `changelog.txt`
  (the user-facing changelog entry) and `readme.txt` in the same change.
  `readme.txt` must stay under 10 KB for WordPress.org: one short line per
  feature, every service the plugin contacts under External services, and
  only the newest version's changelog, in short. Details go in `README.md`.
- Every plugin keeps its credits in `README.md` and `readme.txt` (the
  **Built with AI** section): the credit to aidevops (<https://aidevops.sh>),
  a line sending questions to aidevops, which reads the plugin's docs and
  code to answer them, and the line starting "Made from " that credits the
  starter with a link to it. `scripts/rename-plugin.sh` writes the starter's
  line for a new plugin; keep all three when replacing the starter's
  README and readme.txt. `scripts/preflight-release.sh` warns when a credit
  is missing.
- Every plugin except SEO Pro Stack keeps the line starting "Works well
  with " that recommends SEO Pro Stack
  (<https://github.com/wpallstars/seoprostack>), the base plugin for every
  site, at the end of `README.md` → **Built with AI**. Keep it out of
  `readme.txt`, admin notices and the plugin's own screens other than the
  Read Me tab: WordPress.org's guidelines are strict about plugins promoting
  other plugins, and those are the places its reviewers check.
  `scripts/preflight-release.sh` warns when the line is missing from
  `README.md` or appears in `readme.txt`.
- `.distignore` lists files kept out of the release zip. Add new
  development-only files there (the preflight fails when a known one gets in),
  then check the build with Plugin Check.

## Agent docs

AI agents read `AGENTS.md` in every session, whatever the task, so every
line there costs every session. Keep it a short map; put the detail where
only the task that needs it reads it. This works the same for a small
plugin and a large one: a small plugin has only `AGENTS.md`, a large one
adds docs as it grows.

- `AGENTS.md` holds the plugin's names (the placeholder table), the rules
  for this plugin that apply to any change (a line or two each, such as
  features the owner asked to be on), and one line for each doc saying when
  to read it. Near the top it tells agents to read this file before any
  change.
- Agents keep the plugin at the starter's standard; the starter is where
  the standard is set, not the plugin's copy of it:
  - Before work, look for an open `starter-sync` issue. If one is open,
    the plugin's core files, this file included, are behind: read the
    starter's copy of any core file or rule the task touches, and do that
    issue first when the task changes the same files.
  - Never change a core file only in the plugin. A fix or rule every
    plugin needs goes to the starter first, as a pull request or an issue
    there with the plugin's case, then comes back with
    `scripts/sync-core.sh`. Only the plugin's own files (`{Prefix}_Setup`,
    features, `phpstan-plugin.neon`, `scripts/preflight-plugin.sh`,
    `AGENTS.md`, `docs/`) take changes for this plugin alone.
  - Steps that need the owner's accounts or make secrets (SonarCloud,
    Codacy, `SYNC_PAT`: `DEVELOPMENT.md` → Services setup) are listed for
    the owner, not done by an agent.
- Guidance for one kind of task (a procedure, a checklist, a data format,
  a list of choices) goes in `docs/{topic}.md`, named for the task
  (`docs/presets.md`). `AGENTS.md` names it with when to read it: "Adding
  or changing a preset: read `docs/presets.md` first." Move a section there
  when only some tasks need it or it grows past about 15 lines.
- Rules every plugin shares go in this file, in the starter; workflows every
  plugin shares go in `DEVELOPMENT.md` and `RELEASING.md`. Never copy them
  into a plugin's `AGENTS.md` or `docs/`.
- `docs/` is for people working on the plugin and never ships (`.distignore`).
  Users' docs stay in `README.md` and `readme.txt`.
- No agent definitions (subagents) in the plugin by default: each AI tool
  has its own format, and a doc serves every tool. Add one only when agents
  keep getting a task wrong even with its doc, and have it read that doc.
- `scripts/preflight-release.sh` warns when `AGENTS.md` is over 150 lines,
  does not name `STANDARDS.md`, names a doc that does not exist, or leaves
  out one in `docs/`.

## Code rules

- PHP 7.4 syntax and WordPress 6.2 APIs. Guard newer core APIs with
  `function_exists()` or `method_exists()`.
- Capability and nonce checks on every admin action and AJAX handler; escape on
  output; sanitise through the schema.
- Prefix everything global with `{prefix}_`, `{Prefix}_` or `{PREFIX}_`. The
  shared GitHub updater is the one exception: its `wpallstars_` names are the
  same in every plugin, so that one copy can stand in for the others.
- Admin copy: short, plain words, sentence case, no jargon.
- Decide for the user. Within a feature, the plugin makes the choices
  (which plugins, screens or items it applies to) from what it can detect.
  Settings are there to bypass something that causes a problem, not choices
  people need to understand first. A new setting must earn its place;
  prefer detecting the right behaviour plus a short bypass list.
- Site owner in control, performance first: the owner decides what their site
  sends, contacts and shows. Calls to outside services are opt-in where they
  are not the point of the feature, made only as often and for as long as
  needed (cache answers, never on every page load), and never block a
  visitor's page when they can run later. Features that rein in other
  plugins hand the choice to the owner instead of deciding for them.
  WordPress update checks and downloads are the exception: leave them alone
  (next rule).
- Do not change WordPress update behaviour (update transients, `auto_update_*`
  filters, update checks) outside the shared GitHub updater. Plugin Check
  reports `plugin_updater_detected` as an error, and WordPress.org asks plugins
  not to interfere with the updater.
- Leave no PHP errors, warnings, notices or deprecations behind. Fix any that
  the plugin causes as you find them, in the same change when it is small,
  or as a tracked issue. That includes ones in other plugins that only happen
  because of this one. Messages that other plugins cause on their own are
  theirs: mention them, do not hide them.
- WordPress first: use core's APIs (options, transients, the object cache,
  `WP_Query`, cron, the HTTP API, the Settings and REST APIs) before writing
  your own, and follow the WordPress Coding Standards (`phpcs.xml.dist`).
  Fix a PHPCS finding in the code; an inline `phpcs:ignore` needs the
  sniff and the reason, on that line only.

## Performance

Every plugin runs on every request of every site it is on, next to many
others, so it must cost nearly nothing when idle and stay fast on large
sites. The lessons come from WordPress and WooCommerce sites with hundreds
of thousands of posts, products and meta rows, where problems invisible on
a test site take the site down.

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
    lookup, join and sort. Never add indexes to WordPress's own tables:
    that is a job for plugins that specialise in it.
  - Admin lists of large tables page, sort only on indexed columns, and
    cache their counts.
- **Options:** one autoloaded settings array (`{prefix}_options`). Store
  large or rarely used data with autoload off (`update_option( $name,
  $value, false )`) or in the plugin's own table. Never write an option or
  transient on every page load.
- **Cache repeated work:** `wp_cache_*` for lookups repeated within a
  request (a persistent object cache keeps them between requests), and
  transients that expire for results that are slow to build. Cache times
  are at least five minutes.
- **Work off the page.** Heavy or bulk work runs in cron, in batches with a
  limit, and never on a visitor's page or with no limit. Bulk changes to
  posts or terms use `wp_defer_term_counting()` and
  `wp_suspend_cache_invalidation()`, then turn them back on.
- **No request per page view.** No admin-ajax, REST or remote request on
  every visitor page unless the feature needs it; remote requests a page
  waits on have a short timeout (at most 3 seconds).
- **Measure on large data.** `scripts/smoke-test.sh` loads every page on a
  site seeded with thousands of posts and meta rows, reports query counts
  and times, and fails on a full table or index scan, or a large sort, in
  the plugin's own queries (`DEVELOPMENT.md` → Smoke test). PHPCS flags the
  patterns above as you write them (`WordPress.DB.SlowDBQuery` and
  WordPress VIP's performance sniffs, `phpcs.xml.dist`). An exception, such
  as an unlimited query over a list that cannot grow, needs an inline
  `phpcs:ignore` with the reason.

## Updates from GitHub

The one exception to the update rule, at the owner's request (for speed,
reliability and site owners' control, and because the plugins are released
on GitHub first): the shared GitHub updater in `includes/github-updater/`.
It replaces Git Updater.

- Every plugin made from the starter carries a copy. Each copy registers its
  version from `load.php` when its plugin loads; on `plugins_loaded` only the
  newest copy loads, once, and serves every installed plugin with a
  `GitHub Plugin URI` header. One update check covers them all.
- It adds GitHub releases of those plugins to core's own update check and
  `plugins_api`, and leaves the download, install, auto-updates and rollback
  to core. It only adds entries for those plugins; it never removes or blocks
  other updates.
- It is the same in every plugin apart from its text domain and `@package`.
  Change it in the starter, raise the version in its `load.php`, and copy it
  to each plugin. Plugins change what it does only through its filters
  (`wpallstars_github_updater_enabled`, `wpallstars_github_updater_early`,
  `wpallstars_github_plugins`, `wpallstars_github_token`), never by calling
  its class: another plugin's copy may be the one that runs.
- Keep anything that installs or updates code from outside WordPress.org in
  that folder (and in a feature listed in `.distignore-wporg`, when a plugin
  has a setting for it), because the WordPress.org build leaves them out.
- Never put an `Update URI` header in the main file in Git: WordPress.org
  rejects it. `scripts/build-release.sh` adds
  `Update URI: https://github.com/{owner}/{repo}` to the GitHub zip only, so
  WordPress.org never offers a plugin of the same slug in its place, and the
  updater never takes WordPress.org's answer for that build. A site moves to
  WordPress.org updates only by installing the WordPress.org build.
- Tokens for private repositories come only from `wp-config.php`
  (`WPALLSTARS_GITHUB_TOKEN`) or the filter, go only to api.github.com and
  are never stored.

## Releases

GitHub releases are the early channel; WordPress.org gets settled versions.
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
- The WordPress.org build is the release build without the files in
  `.distignore-wporg` (the GitHub updater) and the `GitHub Plugin URI`,
  `Primary Branch` and `Release Asset` header lines, and has no
  `Update URI`. Its zip is named `wordpress-org-{slug}-X.Y.Z.zip` so no
  updater picks it; never attach it to a GitHub release.
- Any plugin released on GitHub (made from the starter or not) follows the
  same pattern: a `GitHub Plugin URI: owner/repo` header (and
  `Release Asset: true`), plain version tags, and a `{folder}-X.Y.Z.zip`
  asset with a `{folder}/` inside.
- Build both zips with `scripts/build-release.sh`, check them with
  `scripts/preflight-release.sh` and `scripts/plugin-check.sh`. None of them
  tags, publishes or uploads anything; only the Release workflow publishes,
  and only from a tag someone pushed.
- Releasing and submitting to WordPress.org need the owner's say. A private
  repository cannot be read by sites without a token
  (`WPALLSTARS_GITHUB_TOKEN`).

Details: `RELEASING.md`; the plugin's own submission state: `LAUNCH.md`.

## Front-end styling and dark mode

Block, shortcode and other front-end styles must work with the Kadence Pro
dark mode switcher (and themes that switch palettes the same way).

- How it switches: Kadence adds `color-switch-dark` or `color-switch-light` to
  `<body>`. The dark class sets `color-scheme: dark` and redefines
  `--global-palette1`…`15` and `--wp--preset--color--theme-palette-N` **on
  `<body>`**. `<html>` stays `color-scheme: light`. Palette 3 is the strongest
  text and palette 9 the page background in light mode; dark mode swaps them.
- Use `currentColor`, `inherit`, translucent neutrals (for example
  `rgba(127, 127, 127, 0.12)`) or palette variables, never fixed light or dark
  colours for text, backgrounds or borders.
- Do not use `@media (prefers-color-scheme)` to follow the site: it tracks the
  visitor's system, not the switcher.
- Do not define custom properties on `:root` from palette variables; they
  resolve above `<body>` and keep the light values. Read palette variables
  where they are used, or define derived ones on the block.
- Preset references (`var:preset|color|theme-palette3`) become CSS variables
  with kebab-cased slugs, as core does: `--wp--preset--color--theme-palette-3`.
  Use `_wp_to_kebab_case()` in PHP and the same rule in editor JS (a hyphen
  between letters and digits, lower case).
- Embedded pages (iframes) do not follow the switcher: they see the visitor's
  system setting, and the browser paints their own background behind them, so
  they stay readable in both modes. Do not make iframes transparent or tint them.
- Test light and dark with the Kadence theme by toggling the body class (see
  Testing, step 5).

## Testing

CI (`.github/workflows/ci.yml`) runs the code checks, the release preflight,
Plugin Check and a smoke test on every pull request; details and local
commands: `DEVELOPMENT.md`.

While a repository is private, CI and review apps only advise: nothing is
required to merge, for speed. Fix failures your change causes before merging;
open an issue for any other failure and merge anyway. Do not turn on branch
protection, required checks or paid reviewers. At public launch (owner's say),
run the full sweep in `DEVELOPMENT.md` → At public launch, which makes the
checks required.

The checks catch errors, not wrong behaviour, so also verify on real
WordPress:

1. `scripts/lint.sh` (syntax, ShellCheck, PHPCS, PHPStan; run
   `composer install` once). Fix findings in the code; never grow
   `phpstan-baseline.neon` or add a `phpcs:ignore` without a reason.
2. The user reviews on one local test site per plugin, shared by every
   session and worktree. It shows a **combined preview**: `origin/main` plus
   every open pull request from the repository, merged together. Update it
   only with the script, from any worktree:

   ```bash
   scripts/preview-site.sh             # the first run on a clone takes the site: scripts/preview-site.sh "<site>"
   scripts/preview-site.sh --dry-run   # report what would be included, copy nothing
   ```

   It fetches `origin`, merges each open PR's branch onto `origin/main` in PR
   order without touching any checkout, leaves out branches that conflict
   (and lists them), copies the result with `.distignore` applied (exactly
   what a release build contains), and writes
   `<site>/wp-content/{slug}-synced-from.txt` listing what is included.
   A lock stops two runs at once. Because every run includes everyone's
   pushed work, no session hides another's.

   - **Never** `rsync` your worktree into the shared site: it hides every
     other session's work until the next run. Do not use Git hooks either:
     they are shared by every worktree and would deploy the wrong checkout.
   - Only pushed work with an open PR is included. Before asking the user to
     look at unmerged work, push the branch and open a draft PR, then run the
     script. It says so if the branch you run it from is missing or has
     commits that are not pushed.
   - After merging a PR, run the script again, then check that the stamp
     lists your merge in `main` before telling the user to look.
   - Conflicts only in `changelog.txt`, `readme.txt` or `README.md` do not
     leave a branch out: every PR adds lines at the top of the same
     changelogs, so each merge to `main` would otherwise drop every other
     open PR. The preview keeps both sides' lines there and says so in the
     stamp; still merge `origin/main` into your branch before it merges.
   - If your branch is left out because it conflicts in other files, merge
     `origin/main` into it (or wait for the other PR), push and run the
     script again. Tell the user which PRs are left out.
   - To check your branch on its own, or for checks the user will not look
     at, use a throwaway site of your own (step 4's Docker image on a free
     port), which no one else overwrites:
     `rsync -a --delete --delete-excluded --exclude-from=.distignore ./ "<site>/wp-content/plugins/{slug}/"`.
   - Size every test site, shared or throwaway, as `DEVELOPMENT.md` → Test
     site resources says. PHP's defaults fill up and the slowdowns look like
     bugs.

3. Exercise the changed feature through the admin UI or HTTP, and check
   the debug log for new messages mentioning `{slug}` or a plugin it affects
   (`wp-content/debug.log`, or the file Debug Log Manager writes in
   `wp-content/uploads/debug-log-manager/` when it is active). For settings
   imports, seed the replaced plugin's options and delete `{prefix}_options`
   and `{prefix}_db_version` while the plugin is inactive, then activate it.
4. For changes that touch core APIs, also smoke-test on WordPress 6.2 with
   PHP 7.4 (`scripts/smoke-test.sh --wp 6.2 --php 7.4`, or the
   `wordpress:php7.4-apache` Docker image with
   `wp core download --version=6.2 --force`).
5. For front-end styling, view the page with the Kadence theme in light and
   dark mode. Without Kadence Pro, simulate the switcher: print a
   `body.color-switch-dark { color-scheme: dark; --global-palette1: …; }`
   rule with a dark palette (palette 3 light, palette 9 dark, and the matching
   `--wp--preset--color--theme-palette-N: var(--global-paletteN)` lines), then
   swap the body class between `color-switch-light` and `color-switch-dark`.
   Check text, backgrounds, borders and palette colours chosen in block
   settings in both.

Note: since WordPress 5.6, posts restored from the Bin become drafts. Republish
test posts after bulk-trash tests.
