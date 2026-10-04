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
5. Check the change on the shared preview site (`scripts/preview-site.sh`,
   `STANDARDS.md` → Testing), in light and dark mode for front-end styles.
6. Merge once CI passes. Releases are separate: `RELEASING.md`.

## Set up

Needs PHP 7.4 or later, Composer 2, Node.js (syntax checks only),
ShellCheck and Docker (release checks and smoke test). actionlint is
optional locally; CI runs it.

```bash
composer install
```

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
| Coding standards | `scripts/lint.sh phpcs` | WordPress Coding Standards: escaping, sanitising, nonces, prepared SQL, i18n, PHP 7.4 and WordPress 6.2 compatibility (`phpcs.xml.dist`). |
| Static analysis | `scripts/lint.sh phpstan` | Unknown functions, classes and methods, wrong argument counts and types, dead code (PHPStan level 5, `phpstan.neon.dist`). |
| Release build | `scripts/preflight-release.sh --offline` | Versions, headers, `readme.txt`, presets (where the plugin has them) and the contents of both zips. |
| Plugin Check | `scripts/plugin-check.sh` | The WordPress.org review tool, on both zips. |
| Smoke test | `scripts/smoke-test.sh --wp 6.2 --php 7.4` and `scripts/smoke-test.sh` | Installs the GitHub zip, loads the site and admin screens with default settings and with every feature on, runs cron, uninstalls. Fails on any PHP message, a failed page or leftover options. |

`scripts/lint.sh` with no arguments runs the first six.

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
Security, database and compatibility sniffs stay on. Fix findings in the
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

### SonarCloud

`.github/workflows/sonarcloud.yml` runs the SonarCloud scan on pull
requests and pushes to `main`, with `sonar-project.properties`. That file
ignores four rules WordPress coding standards contradict (snake_case method
and field names, `Prefix_Name` classes, early returns); the free plan cannot
give a project its own Quality Profile. For a new plugin: import the
repository in SonarCloud, turn off **Automatic Analysis** (Administration →
Analysis Method; it ignores the file), and add a SonarCloud token as the
`SONAR_TOKEN` Actions secret. Without the secret the job is skipped.

## Test site resources

Test sites run the plugin alongside many others (a plugin that recommends
plugins is tested with all of them active). PHP's defaults are too small for that: OPcache fills
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
   OpenSSF Scorecard. Socket keeps checking dependencies.
2. Fix what they find in the code, in small pull requests by area
   (security first). Each finding is either fixed, explained in an inline
   comment, or marked as a false positive in that service with the reason.
3. Raise the PHPStan level one step at a time (6, then higher if the
   findings are real bugs and not noise). The baseline is already empty.
4. Require the CI checks on `main` (Lint, Release build, both Smoke
   tests) with a branch ruleset, without "branch must be up to date": the
   checks are fast, and changelog lines conflict on every merge.
5. Turn on private vulnerability reporting (Settings → Security), which
   `SECURITY.md` asks reporters to use, and add the CI badge to
   `README.md`. `SECURITY.md`, `CONTRIBUTING.md` and the issue and pull
   request templates are already in place.
6. Run `workflows/public-launch-checklist.md` from the AI DevOps framework
   for anything public: no private paths, site names or secrets in the code,
   history, issues or docs. Run the history scan above again for commits
   made since the last one.

What a plugin has already done ahead of launch is in its `LAUNCH.md`.
