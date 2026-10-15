# Development

How changes are made and checked in every plugin made from the wpallstars
starter plugin. This file is the same in each of them (names as
placeholders: `STANDARDS.md` lists them, and the plugin's `AGENTS.md` gives
its values). Rules for features, code and testing: `STANDARDS.md`; styling:
`STYLING.md`; the plugin's own rules: `AGENTS.md`. Releases: `RELEASING.md`.

## Workflow

1. Open or pick an issue that says what should change and how to check it.
2. Work on a branch in its own worktree, never on `main`. Branch names:
   `feature/…`, `bugfix/…`, `chore/…`.
3. Commit small, working steps. Run `scripts/lint.sh` before pushing.
4. Push and open a pull request (`Resolves #N`). Open it as a draft while
   the work is in progress: CI lints every push, and the longer release and
   smoke-test jobs start when the pull request is marked ready for review.
5. Check the change on the shared preview site (Preview site below,
   `STANDARDS.md` → Testing), in light and dark mode for front-end styles.
6. Merge once CI passes. Releases are separate: `RELEASING.md`.

## Preview site

Each plugin has one local test site for the user to review, shared by every
session and worktree (rules: `STANDARDS.md` → Testing). Update it only with
the script, from any worktree:

```bash
scripts/preview-site.sh             # the first run on a clone takes the site: scripts/preview-site.sh "<site>"
scripts/preview-site.sh --dry-run   # report what would be included, copy nothing
```

It fetches `origin`, merges each open PR's branch onto `origin/main` in PR
order without touching any checkout, leaves out branches that conflict (and
lists them), copies the result with `.distignore` applied (exactly what a
release build contains), and writes `<site>/wp-content/{slug}-synced-from.txt`
listing what is included. A lock stops two runs at once. Because every run
includes everyone's pushed work, no session hides another's. It says so if
the branch you run it from is missing or has commits that are not pushed.

- Conflicts only in `changelog.txt`, `readme.txt` or `README.md` do not
  leave a branch out: every PR adds lines at the top of the same
  changelogs, so each merge to `main` would otherwise drop every other open
  PR. The preview keeps both sides' lines there and says so in the stamp;
  still merge `origin/main` into your branch before it merges.
- If your branch is left out because it conflicts in other files, merge
  `origin/main` into it (or wait for the other PR), push and run the script
  again.
- To check your branch on its own, use `scripts/test-site.sh` below. Never
  replace the combined preview with one branch's files.

### One branch's Docker test site

`scripts/test-site.sh` keeps a disposable WordPress running until `down`,
for manual or agent checks through WP-CLI, REST and wp-admin. It builds the
GitHub zip from one Git ref (default `HEAD`), not uncommitted files, and
installs and activates it. It needs Docker and internet access:

```bash
scripts/test-site.sh up                         # latest WordPress, PHP 8.3
scripts/test-site.sh wp plugin list
scripts/test-site.sh url
scripts/test-site.sh wp --files "<import folder>" eval 'var_dump(is_readable("/files/example.csv"));'
scripts/test-site.sh reinstall --ref HEAD        # commit fixes first
scripts/test-site.sh log                        # wp-content/debug.log
scripts/test-site.sh down                       # delete this site's data
scripts/test-site.sh up --wp 6.2 --php 7.4       # minimum versions
scripts/test-site.sh down
scripts/test-site.sh up --multisite              # network activation; /two/ too
scripts/test-site.sh down
```

`up --ref REF` tests another commit without changing the checkout. `up`
prints the address and random local admin and database passwords; keep its
output private. Credentials (mode 600) and site metadata live outside Git,
under `${XDG_STATE_HOME:-$HOME/.local/state}/wpallstars-test-sites/`.
`wp --files DIR` mounts only that folder, read-only at `/files`; other
arguments pass unchanged to WP-CLI, as uid 33. Debug logging and
`SAVEQUERIES` are enabled; PHP errors are not displayed in pages. The HTTP
port listens only on `127.0.0.1`. Multisite URLs include the published port
and work directly in a browser, without changing hosts or the shared site.

The plugin slug, branch and checkout path determine the name and exact
Docker label (`wpallstars.test-site`), so worktrees have independent sites.
Run commands from the same checkout and branch; `up` twice reports that
the site exists. Commands are locked against concurrent changes. After a
forced termination, remove the stale `lock` directory in that site's state
folder only after checking no command is running, then run `down`.
`down` deletes only containers, volumes and networks with that exact label,
including interrupted WP-CLI containers. It never touches the preview site
or other Docker resources. A failed `up` attempts the same scoped cleanup;
run `down` again if Docker interrupted it.

### Checking screens in a browser

`scripts/preview-browser.sh` signs a browser in to the preview site's admin
and reads the debug log lines a check added. It needs no WP-CLI and no file
reads outside the repository, so headless workers can use it too
(`--help` for the options, such as `--site` and `--user`):

```bash
mark="$(scripts/preview-browser.sh log-mark)"  # the debug log's length now
scripts/preview-browser.sh login               # one-hour session; prints the state file and admin URL
# … check the screens with that state file (below) …
scripts/preview-browser.sh logout "<state file>"
scripts/preview-browser.sh log-since "$mark"   # entries added since, naming {slug} (--all: every entry)
```

The state file (mode 600, in `$TMPDIR`) is a Playwright `storageState`; the
script never prints cookie values. Always log out when done: that ends the
session and deletes the file.

```js
const context = await browser.newContext( { storageState: stateFile, ignoreHTTPSErrors: true } );
const page = await context.newPage();
await page.goto( adminUrl + 'options-general.php?page={slug}' );
```

It runs the site's WordPress with the local `php` and `memory_limit` 1024M,
finds a LocalWP site's database socket itself (other hosts:
`{PREFIX}_PREVIEW_PHP_ARGS`), and keeps its own PHP messages out of the
debug log, so `log-since` shows only what the pages wrote. Other requests
to the site in the meantime (other sessions, cron) also write to the log.
Its WordPress load bypasses page caches with a dummy logged-in cookie name,
not a real sign-in cookie; cached home pages cannot end the load early.
An incomplete load or sign-in fails with `preview-browser:` and removes
the unfinished state file instead of reporting an empty sign-in.

## Set up

Needs PHP 7.4 or later, Composer 2, Node.js (syntax checks, and the build
in plugins that have one: JavaScript builds below), ShellCheck and Docker (release checks, smoke test and update test), and
the GitHub CLI `gh` for releases. actionlint is optional locally; CI runs
it.

```bash
composer install
```

Recommended: [aidevops](https://aidevops.sh), the open-source AI harness
these plugins are built and maintained with, for development, the sites
they run on, and questions. It reads `AGENTS.md`, `STANDARDS.md` and these
docs, so it follows the same workflow, runs the checks and releases, and
answers questions about the plugin from its docs and code. The docs work
with any AI tool or by hand; nothing here needs aidevops.

`composer.json` lists development tools only. The plugin has no Composer
dependencies, and `vendor/`, `composer.*`, the tool configuration and
`.github/` are left out of release zips (`.distignore`; the preflight fails
if one gets in).

## Checks

Every pull request and every push to `main` runs these in GitHub Actions
(`.github/workflows/ci.yml`). Each one runs the same way locally.

| Check | Command | What it finds |
| --- | --- | --- |
| PHP syntax | `scripts/lint.sh php` | Syntax errors; CI uses PHP 7.4, the minimum. |
| JavaScript syntax | `scripts/lint.sh js` | Syntax errors (`node --check`). |
| Shell scripts | `scripts/lint.sh shell` | ShellCheck findings in `scripts/`. |
| Workflows | `scripts/lint.sh workflows` | actionlint findings in `.github/workflows/`. |
| Coding standards | `scripts/lint.sh phpcs` | WordPress Coding Standards: escaping, sanitising, nonces, prepared SQL, i18n, PHP 7.4 and WordPress 6.2 compatibility; slow and unlimited queries, `ORDER BY RAND()`, short cache times and long remote timeouts (`phpcs.xml.dist`). |
| Static analysis | `scripts/lint.sh phpstan` | Unknown functions, classes and methods, wrong argument counts and types, dead code, `false` and `null` results used as values (PHPStan level 8 without the `missingType.*` checks, `phpstan.neon.dist`). |
| JavaScript build | `scripts/lint.sh build` | Plugins with a build only: the `check` script's findings (types, lint), and built files in `assets/build/` that differ from a fresh build. |
| Release build | `scripts/preflight-release.sh --offline` | Versions, headers, `readme.txt`, presets (where the plugin has them) and the contents of both zips. |
| Plugin Check | `scripts/plugin-check.sh` | The WordPress.org review tool, on both zips. |
| Smoke test | `scripts/smoke-test.sh --wp 6.2 --php 7.4`, `scripts/smoke-test.sh` and `scripts/smoke-test.sh --multisite` | Installs the GitHub zip on a site with 10,000 posts, loads the site and admin screens with default settings and with every feature on, runs cron, uninstalls. Lists each page's queries. Fails on any PHP message, a failed page, a full table scan or large sort in the plugin's own queries, or leftover options, cron events or tables (`{prefix}_*`). On a network, also applies a setting to every site and checks the other site picks it up. |

`scripts/lint.sh` with no arguments runs the first seven.

<!-- wps-own:start -->
<!-- wps-own:end -->

The scripts work out which plugin they are in from its main file
(`scripts/lib/plugin.sh`): the PHP file at the top of the repository with a
`Plugin Name:` header gives the slug (its file name), the name, the class
prefix (`@package`) and the constant prefix (`define('<PREFIX>_VERSION', …)`).
Environment overrides use that prefix, for example
`{PREFIX}_PREVIEW_SITE` or `{PREFIX}_DB_IMAGE`. Checks for parts only some
plugins have (presets and starter data, the replaced plugins count) run
when their files exist, so the same scripts serve every plugin made from the
starter.

### Coding standards

`phpcs.xml.dist` uses the WordPress ruleset. The plugin's own style
differs from it in a few places (spacing, `array()`, file names, Yoda
conditions), and those sniffs are off; the comments in the file say why.
Security, database and compatibility sniffs stay on, with the performance
sniffs of WordPress VIP's standard (`automattic/vipwpcs`; only its
`WordPressVIPMinimum.Performance` group, as the rest is for VIP's own
hosting): unlimited queries, `ORDER BY RAND()`, `REGEXP`, `post__not_in`,
cache times under five minutes and remote requests with timeouts over 3
seconds. The shared updater's GitHub requests may take longer: they run
only during update checks and updates. Fix findings in the
code. Where a finding is intended, add an inline
`// phpcs:ignore Sniff.Name -- reason` on that line only.

`vendor/bin/phpcbf` fixes what it can automatically.

### Static analysis

PHPStan reads the code with WordPress's stubs and PHP 7.4's functions.
`scripts/phpstan-bootstrap.php` defines the constants WordPress and the
plugin set while loading. Classes and functions of other plugins the code
uses (WP-CLI, WooCommerce and the like) are ignored in `phpstan-plugin.neon`,
because the code uses them only after checking they are loaded.

`phpstan-baseline.neon` is empty: every finding fails the check. Fix the
code. Where PHPStan or the stubs are wrong (a custom `wp_hash()` scheme, a
check for a method newer WordPress versions have, variables a closure
changes by reference), add an entry under `ignoreErrors` with the
identifier, the file and the reason: in `phpstan.neon.dist` for the files
every plugin made from the starter shares, in `phpstan-plugin.neon` for the
plugin's own files and extra paths. Never put findings in the baseline to
get a change through.

### JavaScript builds

Most plugins need none: plain JavaScript and CSS in `assets/` ship as
written. A plugin whose admin screens or front-end script need a build
(TypeScript, React with WordPress's packages, bundling) follows these rules,
so release zips stay buildless and the shared scripts work unchanged:

- Sources live in `packages/` (one folder per package; npm workspaces when
  there are several), with `package.json`, `package-lock.json` and the tool
  configuration at the top of the repository. None of them ship
  (`.distignore`; the preflight fails if one gets in).
- `npm run build` writes everything that ships to `assets/build/`, and the
  built files are committed with the source change that made them: release
  zips and the preview site are made from Git without a build step.
  `.gitattributes` marks them as generated, so GitHub folds them in diffs.
- Scripts made with `@wordpress/scripts` come with a `*.asset.php` file
  listing their WordPress dependencies and version; register them with it
  rather than by hand. Use WordPress's own React and components (externals),
  never a second copy.
- An optional `npm run check` runs the type check and linters.
- `scripts/lint.sh build` runs `check`, then the build, and fails if
  `assets/build/` changed, so a stale or hand-edited build never merges.
  CI runs it when `package-lock.json` exists. Locally it installs only when
  `node_modules/` is missing; run `npm ci --ignore-scripts` after a
  dependency change. Packages' install scripts never run (a supply-chain
  risk); a package that needs one is set up by the plugin's `build` script
  (`npm rebuild <name>`).
- Dependabot does not update npm packages (`.github/` is a core file, and
  the starter has no `package.json`); Socket still checks them. Run
  `npm outdated` and update in a pull request of its own, at least before
  each release.

### Secrets in history

Scan the whole Git history before the repository goes public, and after
importing code from elsewhere:

```bash
docker run --rm -v "$PWD:/repo:ro" ghcr.io/gitleaks/gitleaks:latest git /repo --redact --no-banner
```

In a linked worktree, also mount the main repository's `.git` folder at
the same path. `.gitleaks.toml` lists the false positives with reasons. A
real secret is rotated first, then removed from history.

### Smoke test

`scripts/smoke-test.sh` starts a throwaway WordPress in Docker (MariaDB,
Apache and WP-CLI images for the chosen PHP version), so nothing touches
the shared preview site. CI runs it on WordPress 6.2 with PHP 7.4 and on
the latest WordPress with PHP 8.3, and on a network (below). Every feature with an on/off setting is
switched on at once, except one with the key `maintenance` (a maintenance
mode would answer every visitor page with its notice). `--keep-log FILE` saves `debug.log`; CI keeps it as an artifact
when the test fails.

`--multisite` (CI runs it too, on the latest WordPress with PHP 8.3)
installs a network with subdirectories and a second site, `/two/`, and
network-activates the plugin. Besides the main site's pages, it loads site
two's, the network screens and the plugin's network settings screen, and
runs cron on every site. It then applies one on/off setting to every site
from the network, through `{Package}_Network_Settings::set_value()` and
`apply()` (the plugin's first eligible one other than `maintenance`, else
`smoke_network`, which a must-use plugin adds so a plugin without settings
has one), and fails unless site two does its saving work on its next admin
request (its `{prefix}_network_seen` records the network's version) and
reads the network's value. Uninstall must leave no options, cron events or
tables on any site, and no network option (`{prefix}` in the meta key).
WordPress runs a network only on port 80, so the network's address has no
port and curl reaches the published port with `--connect-to`.

Queries are checked on large data (`STANDARDS.md` → Performance). Before
installing the plugin, the test seeds 10,000 posts (`--posts N`) with three
meta rows each, and adds `scripts/smoke-queries.php` as a must-use plugin
with `SAVEQUERIES` on. It records every request: the query count and time,
and the queries the plugin made itself (a file of the plugin is in the call
stack, so this includes core queries the plugin causes, such as an option
that is not autoloaded). After each round of pages it lists the requests,
then runs `EXPLAIN` on each of the plugin's own queries, slowest first. A
full table or index scan, or a sort without an index, over 1,000 rows or
more fails. A canary page runs a known full table scan, and the test fails
if the check misses it. Query counts and times are listed, not limited:
compare them with `main` when a change adds work to every page.

### SonarCloud

`.github/workflows/sonarcloud.yml` runs the SonarCloud scan on pull
requests and pushes to `main`, with `sonar-project.properties`. That file
ignores four rules WordPress coding standards contradict (snake_case method
and field names, `Prefix_Name` classes, early returns), since the free plan
cannot give a project its own Quality Profile; ignores a few findings that
are by design, each scoped to its files with the reason; and leaves
coverage out, as the smoke test, not unit tests, checks the plugin. Fix
other findings in the code. Without the `SONAR_TOKEN` secret the job is
skipped; setting it up: Services setup below.

### Scorecard

`.github/workflows/scorecard.yml` runs OpenSSF Scorecard on pushes to
`main`, every Monday, when branch protection changes, and from the Actions
tab (**Run workflow**). It checks the repository's security practices
(pinned actions, token permissions, branch protection, code review and
more), puts the results in Security → Code scanning and publishes them for
the Scorecard badge. It needs no setup. In a private repository the job is
skipped: publishing needs a public one, and minutes cost money there.
Fix what it finds in the repository, or dismiss the alert with the reason.

### Release

`.github/workflows/release.yml` runs when a `vX.Y.Z` tag is pushed: it
checks the tag is on `main`, runs the preflight, builds the zips and
publishes the GitHub release, with signed build provenance in a public
repository. It needs no setup. Steps: `RELEASING.md` → GitHub release.

### Starter sync

`.github/workflows/starter-sync.yml` runs every Monday (and from the
Actions tab, **Run workflow**). It checks out the starter's default branch,
with its history, next to the plugin and runs the starter's
`scripts/sync-core.sh --check`, so the newest check is used. When core
files differ it opens one issue labelled `starter-sync`, or updates the
open one, with the files, each file's class (below) and the steps; when
they match it closes that issue. It needs no setup: the
workflow's own token reads the public starter and writes the issue. To
follow another starter (a fork), set the repository variable
`STARTER_REPO` to its `owner/repo`. In the starter itself it does nothing.

To sync by hand, with the starter cloned next to the plugin (the issue
gives its folder name):

```bash
git -C ../<starter> pull
scripts/sync-core.sh --check   # list what differs, with each file's class
scripts/sync-core.sh           # copy the starter's core files, renamed
```

Core files flow both ways: starter changes out to every plugin, and what a
plugin learns back into the starter. So a sync never replaces a core file
it would lose work in. It compares each file that differs with every
version in the starter's history (with the plugin's names and its own
blocks), and `--check` puts its class under it:

| Class | The plugin's file is | A sync |
|---|---|---|
| behind | a starter version `--ref` contains (default: the starter checkout's `HEAD`) | updates it |
| missing | not there | adds it |
| newer | a starter version `--ref` does not contain: later on `main`, or on another branch | stops: sync from a starter ref that contains it, the starter's `main` (what the weekly check uses) or a later tag. There is no option to go backwards. |
| changed here | no starter version: the plugin changed it outside its `{css}-own` blocks | stops: take the change to the starter first (a pull request, or an issue there with the plugin's case), or move the plugin-only lines into `{css}-own` blocks; then run again with `--discard-local`, which replaces changed-here files only |

While any file is newer or changed here, a sync writes nothing (exit 2)
and lists them with what to do; every core file still syncs in one run,
never a few, so a plugin never mixes core files from different starter
versions. The classes need the starter's history: from a shallow clone
`--check` marks such files "unknown (shallow starter clone)", and a sync
stops until `git -C ../<starter> fetch --unshallow`.

When a sync adds a core doc at the top of the repository (such as
`STYLING.md`) and the aidevops commit hook rejects it as a new root file,
add its name to `root_files.allow` in the plugin's `.aidevops.json`, as for
`STANDARDS.md`.

## Services setup

Once per repository, for a new plugin or one that has just synced these
workflows from the starter. Each step needs the owner's accounts or makes a
secret, so an agent lists the missing ones for the owner (with this
section) instead of doing them. `{owner}/{repo}` is the plugin's GitHub
repository.

While the repository is private: SonarCloud's free plan analyses private
projects up to 50,000 lines of code for the whole organization, so a
private plugin can take step 1 if the organization has room. Codacy
analyses private repositories only on a paid plan, so step 2 waits for
public launch (below). Branch rulesets need a paid GitHub plan on private
repositories, so step 4 waits too. Until then the SonarCloud job skips
without its secret, and nothing fails.

1. **SonarCloud** (SonarQube Cloud), for `.github/workflows/sonarcloud.yml`:
   1. Import the repository into the `{owner}` organization: in its GitHub
      import screen, select the repository and choose **Analyze 1
      project**. The project key must stay `{owner}_{repo}`, the key the
      workflow passes.
   2. In the project, **Administration → Analysis Method**: turn
      **Automatic Analysis** off. It ignores `sonar-project.properties`, and
      the CI scan fails while it is on.
   3. Make a token for the scan: a personal access token on the free plan;
      on the Team plan, a scoped organization token with only **Execute
      analysis**. Store it in the repository:
      `gh secret set SONAR_TOKEN --repo {owner}/{repo}` (it asks for the
      value; never paste it into a chat, issue or file).
   4. Check: the next pull request's **SonarCloud analysis** job runs the
      scan instead of logging "skipping SonarCloud".
2. **Codacy**, which reads `.codacy.yml`: in the `{owner}` organization,
   **Manage repositories** (top right), then **Add** beside the repository.
   Check: the next pull request gets a **Codacy Static Code Analysis**
   check. Then add the repository's Codacy badge to `README.md`:
   `scripts/readme-badges.sh --codacy ID`, with the ID at the end of the
   badge address Codacy gives (`.../project/badge/Grade/ID`).
   Then, in the repository's **Code patterns**, turn on **Configuration
   file** for **ESLint** (it reads `.eslintrc.json`) and **PHP Mess
   Detector** (`phpmd.xml.dist`). Codacy's defaults for them are written
   for other code: ES5 compatibility, imports without the TypeScript
   resolver, camelCase names and static calls, a few thousand findings
   that say nothing about a WordPress plugin. The files keep the rules
   that do (`eslint:recommended`, TypeScript's recommended rules, code
   size and unused code); each left-out PHPMD rule says why. An
   organization coding standard still decides which tools run.
3. **CodeFactor**: its GitHub app is installed for the whole organization,
   but CodeFactor analyses a repository, and serves its badge, only once
   the repository is added on codefactor.io (signed in with GitHub).
   Check: `https://www.codefactor.io/repository/github/{owner}/{repo}/badge`
   returns an image instead of a 404 page. Then add its badge:
   `scripts/readme-badges.sh --add codefactor`. Until then the block
   leaves it out, so GitHub shows no broken image.
4. **`SYNC_PAT`**, only once `main` is protected by a branch ruleset.
   `.github/workflows/repo-metrics.yml` commits `docs/metrics/` to `main`;
   with protection and no `SYNC_PAT` it warns "SYNC_PAT not present" and
   leaves the metrics out of date. Make a fine-grained personal access token
   (GitHub → Settings → Developer settings → Personal access tokens →
   Fine-grained tokens) for an account the ruleset lets push to `main`,
   limited to this repository, with **Contents: Read and write**. Store it:
   `gh secret set SYNC_PAT --repo {owner}/{repo}`. Check: the next
   **Repository metrics** run logs "SYNC_PAT present".
5. **Starter sync**: Actions → **Starter sync** → **Run workflow**, once,
   to see that it runs. It needs no secret. Set the repository variable
   `STARTER_REPO` only to follow a fork of the starter.
6. **Self-hosted runners**, private repositories only. The workflows run on
   GitHub-hosted runners unless the repository variable `CI_RUNNER` holds
   a self-hosted runner label (such as `4cpu-8gb`); private repositories
   pay for GitHub-hosted minutes. Set it per repository:
   `gh variable set CI_RUNNER --repo {owner}/{repo} --body 4cpu-8gb`, and
   add the repository to the runner group. An organization variable does
   not reach private repositories on GitHub's Free plan. Never set it in a
   public repository, or in a private one that runs workflows from fork
   pull requests (Settings → Actions → General): a pull request from a
   fork could run code on the runner. Check:
   `gh api repos/{owner}/{repo}/actions/permissions/fork-pr-workflows-private-repos`
   shows `"run_workflows_from_fork_pull_requests":false`, and the next
   **CI** run's jobs show the self-hosted runner's name.

`gh secret list --repo {owner}/{repo}` shows which secrets are set (names
only). CodeRabbit, Socket and qlty are GitHub apps installed for the whole
organization; they need nothing per repository. CodeFactor needs step 3.

Qlty limits an organization's repositories, public or private, to a number
of free minutes each month. When they run out, its
**qlty check** fails with "Qlty did not run because you are out of
minutes". That is billing, not a finding: don't rerun it, change code or
open an issue; merge when the other checks pass (aidevops skips it:
`reference/ci-gate-policy.md`, rule 14). A qlty check with real findings
still counts. Never make qlty a required check: it would block every
merge once the minutes run out.

## Test site resources

Test sites run the plugin alongside many others (a plugin that recommends
plugins is tested with all of them active). Every test site also runs
[SEO Pro Stack](https://github.com/wpallstars/seoprostack), the base plugin
for speed and an organised admin, so each plugin is tested alongside the
base the sites it runs on will have. PHP's defaults are too small for that: OPcache fills
and restarts, admin requests queue behind two workers, and the slowdowns
look like bugs. Size every test site, shared or throwaway, with room to
spare:

| Setting | Where (LocalWP, nginx) | Value | PHP or Local default |
|---|---|---|---|
| `opcache.memory_consumption` | `conf/php/php.ini.hbs` | `1024` | 128 |
| `opcache.interned_strings_buffer` | `conf/php/php.ini.hbs` | `64` | 8 |
| `opcache.max_accelerated_files` | `conf/php/php.ini.hbs` | `50000` | 10000 |
| `memory_limit` | `conf/php/php.ini.hbs` | `768M` | 256M |
| `pm.max_children` | `conf/php/php-fpm.d/www.conf.hbs` | `5` | 2 |

Measured on a shared test site with 72 plugins installed: OPcache used
509 MB of 512 MB and restarted, then 315 MB of 1 GB with 31,723 PHP files
cached; pages peaked at 352 MB of memory; the busiest hour needed 5 workers.

- LocalWP keeps these per site in `<site>/conf/`. Edit the `.hbs`
  templates, not the generated files under Local's `run/` folder, then
  stop and start the site in Local: it rebuilds the configuration only on
  start. Add a comment with the date and reason next to each change.
- The OPcache lines sit inside `{{#unless apache}}`: on an Apache site,
  move them out or set them in Apache's own configuration.
- Check after the restart: Site Health → Info → Server shows the new values.
- Raise them again when a site needs more, and update this table in the
  starter.
- To test low-resource warnings, lower a value on a throwaway site, never
  the shared one.
- Docker sites (`scripts/smoke-test.sh`, step 4 in `STANDARDS.md` →
  Testing) take the same values in a `.ini` file mounted into
  `/usr/local/etc/php/conf.d/`.

## Dependencies

Dependabot (`.github/dependabot.yml`) opens one pull request a week for
the GitHub Actions and one for the Composer tools. Actions are pinned to
commit SHAs with the version in a comment; keep it that way when editing
workflows. Do not add third-party actions that only save a few lines of
shell.

## While private: checks are advisory

The repository is private until it is released, so Actions minutes cost
money and most code-review services are paid. Until then, work moves fast:

- No branch protection or required checks on `main`. A failing check does
  not block a merge, so a merge never waits on an unrelated failure.
- Fix any failure your change causes before merging. For a failure your
  change did not cause, open an issue with the run link and the first error,
  and merge anyway.
- Draft pull requests run only the lint job. A new push cancels the run for
  the previous one.
- The build zips and Plugin Check reports are kept for seven days on each
  run (artifact `<repository>-build-…`) for testing a branch on a site.
- Review apps that are already installed (CodeRabbit, qlty, Socket) give
  advice only. A rate-limited or missing review never holds up a merge.

## At public launch: full sweep

Making the repository public needs the owner's say. Do this sweep in the
same step, while the code-review services are free for
public repositories. It goes through the whole codebase once, then keeps
it at that standard:

1. Turn on the free reviewers for the whole codebase, not just new
   changes: CodeRabbit full review, Codacy, SonarCloud (SonarQube Cloud)
   and qlty (still limited to its monthly minutes; see Services setup),
   plus GitHub's CodeQL (JavaScript and GitHub Actions; it has
   no PHP support, so PHPStan, SonarCloud and Codacy cover the PHP),
   Dependabot security alerts, secret scanning with push protection, and
   OpenSSF Scorecard (Actions → **Scorecard** → **Run workflow** once; it
   then runs by itself). Socket keeps checking dependencies. Connect any
   service still missing with Services setup above.
2. Fix what they find in the code, in small pull requests by area
   (security first). Each finding is either fixed, explained in an inline
   comment, or marked as a false positive in that service with the reason.
3. Raise the PHPStan level one step at a time (9 next, if the findings
   are real bugs and not noise). The level is in `phpstan.neon.dist`, a
   core file, so it changes in the starter. The baseline is already empty.
4. Require the CI checks on `main` (Lint, Release build, both Smoke
   tests) with a branch ruleset, without "branch must be up to date": the
   checks are fast, and changelog lines conflict on every merge.
5. Turn on private vulnerability reporting (Settings → Security), which
   `SECURITY.md` asks reporters to use, and add the Scorecard badge to
   `README.md` (`scripts/readme-badges.sh --add scorecard`) once its first
   run has published. `SECURITY.md`, `CONTRIBUTING.md`, `CODE_OF_CONDUCT.md`
   and the issue and pull request templates are already in place.
6. Run `workflows/public-launch-checklist.md` from the AI DevOps framework
   for anything public: no private paths, site names or secrets in the code,
   history, issues or docs. Run the history scan above again for commits
   made since the last one.

What a plugin has already done ahead of launch is in its `LAUNCH.md`.
