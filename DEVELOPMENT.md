# Development

How changes are made and checked in every plugin made from the wpallstars
starter plugin. This file is the same in each of them (names as
placeholders: `STANDARDS.md` lists them, and the plugin's `AGENTS.md` gives
its values). Rules for features, code, styling and testing: `STANDARDS.md`;
the plugin's own rules: `AGENTS.md`. Releases: `RELEASING.md`.

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
- To check your branch on its own, or for checks the user will not look at,
  use a throwaway site of your own (the Docker image in `STANDARDS.md` →
  Testing, step 4, on a free port), which no one else overwrites:
  `rsync -a --delete --delete-excluded --exclude-from=.distignore ./ "<site>/wp-content/plugins/{slug}/"`.

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
| Static analysis | `scripts/lint.sh phpstan` | Unknown functions, classes and methods, wrong argument counts and types, dead code, `false` and `null` results used as values (PHPStan level 7 without the `missingType.*` checks, `phpstan.neon.dist`). |
| JavaScript build | `scripts/lint.sh build` | Plugins with a build only: the `check` script's findings (types, lint), and built files in `assets/build/` that differ from a fresh build. |
| Release build | `scripts/preflight-release.sh --offline` | Versions, headers, `readme.txt`, presets (where the plugin has them) and the contents of both zips. |
| Plugin Check | `scripts/plugin-check.sh` | The WordPress.org review tool, on both zips. |
| Smoke test | `scripts/smoke-test.sh --wp 6.2 --php 7.4` and `scripts/smoke-test.sh` | Installs the GitHub zip on a site with 10,000 posts, loads the site and admin screens with default settings and with every feature on, runs cron, uninstalls. Lists each page's queries. Fails on any PHP message, a failed page, a full table scan or large sort in the plugin's own queries, or leftover options, cron events or tables (`{prefix}_*`). |

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
the latest WordPress with PHP 8.3. Every feature with an on/off setting is
switched on at once, except one with the key `maintenance` (a maintenance
mode would answer every visitor page with its notice). `--keep-log FILE` saves `debug.log`; CI keeps it as an artifact
when the test fails.

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
Actions tab, **Run workflow**). It checks out the starter's default branch
next to the plugin and runs the starter's `scripts/sync-core.sh --check`,
so the newest check is used. When core files differ it opens one issue
labelled `starter-sync`, or updates the open one, with the files and the
steps; when they match it closes that issue. It needs no setup: the
workflow's own token reads the public starter and writes the issue. To
follow another starter (a fork), set the repository variable
`STARTER_REPO` to its `owner/repo`. In the starter itself it does nothing.

To sync by hand, with the starter cloned next to the plugin (the issue
gives its folder name):

```bash
git -C ../<starter> pull
scripts/sync-core.sh --check   # list what differs
scripts/sync-core.sh           # copy the starter's core files, renamed
```

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
   check. Then add the repository's Codacy badge to the badges block in
   `README.md` (`STANDARDS.md` → Structure).
3. **CodeFactor**: its GitHub app is installed for the whole organization,
   but CodeFactor analyses a repository, and serves its badge, only once
   the repository is added on codefactor.io (signed in with GitHub).
   Check: `https://www.codefactor.io/repository/github/{owner}/{repo}/badge`
   returns an image instead of a 404 page. Then add
   `[![CodeFactor](https://www.codefactor.io/repository/github/{owner}/{repo}/badge)](https://www.codefactor.io/repository/github/{owner}/{repo})`
   to the badges block after the SonarCloud badge. Until then the block
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

`gh secret list --repo {owner}/{repo}` shows which secrets are set (names
only). CodeRabbit, Socket and qlty are GitHub apps installed for the whole
organization; they need nothing per repository. CodeFactor needs step 3.

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
   and qlty, plus GitHub's CodeQL (JavaScript and GitHub Actions; it has
   no PHP support, so PHPStan, SonarCloud and Codacy cover the PHP),
   Dependabot security alerts, secret scanning with push protection, and
   OpenSSF Scorecard (Actions → **Scorecard** → **Run workflow** once; it
   then runs by itself). Socket keeps checking dependencies. Connect any
   service still missing with Services setup above.
2. Fix what they find in the code, in small pull requests by area
   (security first). Each finding is either fixed, explained in an inline
   comment, or marked as a false positive in that service with the reason.
3. Raise the PHPStan level one step at a time (8 next, if the findings
   are real bugs and not noise). The baseline is already empty.
4. Require the CI checks on `main` (Lint, Release build, both Smoke
   tests) with a branch ruleset, without "branch must be up to date": the
   checks are fast, and changelog lines conflict on every merge.
5. Turn on private vulnerability reporting (Settings → Security), which
   `SECURITY.md` asks reporters to use, and add the CI and Scorecard badges
   to `README.md`. `SECURITY.md`, `CONTRIBUTING.md`, `CODE_OF_CONDUCT.md`
   and the issue and pull request templates are already in place.
6. Run `workflows/public-launch-checklist.md` from the AI DevOps framework
   for anything public: no private paths, site names or secrets in the code,
   history, issues or docs. Run the history scan above again for commits
   made since the last one.

What a plugin has already done ahead of launch is in its `LAUNCH.md`.
