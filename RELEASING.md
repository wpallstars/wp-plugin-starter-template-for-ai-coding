# Releasing

How every plugin made from the wpallstars starter plugin is released. This
file is the same in each of them (names as placeholders: `STANDARDS.md`
lists them, and the plugin's `AGENTS.md` gives its values). The plugin's own
submission state and guideline review: `LAUNCH.md`.

Releases on GitHub and the WordPress.org submission need the owner's say.
None of the scripts below tags, publishes or commits anything, and only
`scripts/deploy-sites.sh --apply` changes a site outside Docker. The
Release workflow (`.github/workflows/release.yml`) publishes a GitHub release
only when someone pushes a version tag or manually runs it for an existing tag.

## Scripts

| Script | What it does |
|--------|--------------|
| `scripts/build-release.sh [--ref REF] [--out DIR] [--quiet]` | Builds both zips from a Git ref (default `HEAD`) into `dist/` (gitignored), with `SHA256SUMS`. Files come from Git, never the working tree. `--quiet` prints only the zips' paths. |
| `scripts/preflight-release.sh [--ref REF] [--strict] [--offline] [--no-docker]` | Checks versions, headers, readme, both zips (layout, development files, PHP 7.4 and JS syntax, updater code), remote assets, presets and starter data where the plugin has them, and the Git tag. Errors stop a release; `--strict` also fails on warnings, for a WordPress.org submission. `--no-docker` lints PHP with the local `php` instead of PHP 7.4 in Docker. |
| `scripts/plugin-check.sh [--ref REF] [--zip FILE]` | Runs Plugin Check on both zips in a disposable WordPress in Docker, then removes it. |
| `scripts/update-test.sh [--from X.Y.Z] [--to X.Y.Z] [--wp VERSION] [--php VERSION] [--keep-log FILE]` | After a release: installs the previous GitHub release (default: the one before the newest) on a disposable WordPress in Docker and checks that it is offered the new one from its asset (WP-CLI, **Check again** on the Updates screen, the Plugins screen), that the update installs and the plugin stays active, and that `debug.log` stays empty. Then removes the site. Reads releases with `gh`. |
| `scripts/deploy-sites.sh --host SSH_HOST --tag vX.Y.Z [--parent PATTERN] [--skip NAME]... [--wp-cli COMMAND] [--allow-downgrade] [--cloudflare-token-env NAME [--cloudflare-purge zone]] [--keep-releases N] [--web-error-log PATH --apply]` | After the update test: installs the release's zip (a failed download is tried again after 30, 60, 120 and 120 seconds, as GitHub sometimes answers "release not found" for a while), checked against GitHub's SHA-256 and its provenance bundle, on every install on one SSH host that already has the plugin (default `'~/domains/*/public_html'`). Without `--apply` it only lists them, with their version and whether each is a multisite network. With `--apply`: a backup of each plugin folder, the new folder swapped in with two renames so running requests and cron jobs never find it missing (activation kept; the files get the install's current time, so OPcache and `filemtime()`-versioned assets pick up the new code; falls back to `wp plugin install --force`, except when the rollback of a failed second rename also fails: that install stops with a FAIL and its old folder, kept beside the plugin, needs a manual restore; where OPcache timestamp validation is off, also reset the web-serving OPcache or restart its PHP processes), a full load for each site's settings upgrade, a purge of each site's page cache (LiteSpeed Cache, when its WP-CLI command is there), one run of the plugin's own WP-Cron events (`cron=N/M`; a PHP fatal error in one fails the install; running one early reschedules it) and a home fetch with a unique query string, pinned to the origin when LiteSpeed Cache's Server IP or an address the plugin learned (its `{prefix}_origin_ip` option) is known (`home=200 pinned`; a CDN in front of a LiteSpeed host can answer the host's own unpinned fetch with 403; with neither address it uses plain DNS) (fetched once more after a 5xx or no answer; a fetch that does not complete counts as no answer). Networks skip archived, deleted and spam sites and print one indented line per site, after the install line. `cache=` lists the response's cache headers; `WARN cached` means a cache ignored query strings, so PHP did not run for that fetch. Fails on a version not reached, new lines in the site's PHP logs (`WP_DEBUG_LOG`, including a custom path, PHP's `error_log` and the `--web-error-log` file, where `{name}` and `{name_}` give each install its own: `'~/.logs/error_log_{name_}'`) or any failed site, with the restore command. New lines that are all WordPress core's cron-save notices (error code `could_not_set`, in any language: two cron runners saving at once) give `WARN cron save contention (N lines)` instead, with the lines shown and no restore command; any other line still fails. Just before each install, `--apply` refuses one whose installed version is newer than the tag, or cannot be read, with a FAIL line; `--allow-downgrade` installs anyway, for a rollback or to repair a broken install. A prerelease of the tag (`2.0.0-rc1` for `2.0.0`) counts as older, and the dry run marks the installs `--apply` would refuse. `--apply` holds a per-plugin lock on the host (`~/.{slug}-deploy/.lock`) until it ends, so overlapping runs cannot install over each other: while another run holds it, it installs nothing, names that run (tag, start time, parent) and exits 3, so wait for that run to finish and run again; the dry run says when one is active, and a lock whose run is no longer running is taken over with a warning. The lock is in the SSH account's home folder, so it keeps apart only runs from one account: roll a plugin out to a host from one account. After a successful install it removes the plugin's older run folders in `~/.{slug}-deploy/` on the host, keeping the current run and the newest `N` tags (`--keep-releases N`, default 3; 0 keeps everything), and lists what it removed and the space freed; it skips this while another deploy holds the lock and leaves other files there alone. The remote part is `scripts/lib/deploy-remote.sh`. |

The deploy runner snapshots the **stored**, unfiltered activation lists and
their counts before the install and the settings-upgrade load, then requires
exactly the intended difference (none: `install --force` keeps activation).
On multisite it checks every blog and the network activation list too. A
WP-CLI error (including `Error establishing a database connection` even with
exit zero), an invalid snapshot or an unexpected difference prints FAIL and
stops that install; the host run continues with the others. On a healthy
readable single site, a strict-subset wipe is restored with an atomic
compare-and-swap and rechecked, but the install still fails. Extra entries,
concurrent changes and network state are **never** overwritten
automatically: review the diff and restore command instead. A plugin's own
fleet script can source `scripts/lib/deploy-remote.sh` with
`DEPLOY_LIBRARY_ONLY=1` and wrap each change in `active_guard` for the same
checks.

<!-- wps-own:start -->
<!-- wps-own:end -->

The two builds of each version:

| Zip | Contents | Goes to |
|-----|----------|---------|
| `{slug}-X.Y.Z.zip` | Files in Git, less `.distignore`, with `Update URI: https://github.com/{owner}/{repo}` added to the main file | GitHub release asset |
| `wordpress-org-{slug}-X.Y.Z.zip` | The same, less `.distignore-wporg` (the GitHub updater) and the `GitHub Plugin URI`, `Primary Branch` and `Release Asset` header lines, without `Update URI`, and with the affiliate links in `.wporg-links` replaced by plain ones | WordPress.org only, 30 days after the GitHub release (security releases at once) |

Sites install the release asset named exactly `{slug}-X.Y.Z.zip` (the
shared GitHub updater), so the WordPress.org zip is named differently and
must never be attached to a GitHub release. The `Update URI` stops
WordPress.org offering a plugin of the same slug to sites on the GitHub
build.

Plugin Check reports the GitHub updater as an updater
(`plugin_updater_detected` for the `Update URI` header and the updater files,
`update_modification_detected`, and `OffloadedContent` for its
raw.githubusercontent.com address) and its shared `wpallstars_` names as
unprefixed, in the GitHub zip; `scripts/plugin-check.sh` lists those as
expected there and fails on the updater findings in the WordPress.org zip.
A file a plugin lists in `.distignore-wporg` because WordPress.org must not
get it (such as an endpoint requested directly, without WordPress) may lack
the `ABSPATH` guard: `missing_direct_file_access_protection` in it is
expected in the GitHub zip too.

## GitHub release

1. In a pull request, set the version in `{slug}.php` (`Version:` and
   `{PREFIX}_VERSION`), `readme.txt` (`Stable tag:`) and `README.md` (the
   `Version:` line under the intro, which GitHub shows as written), run
   `scripts/readme-badges.sh` (the release badge shows `Stable tag:`), rename the
   changelog's Unreleased section to the version in `readme.txt`,
   `changelog.txt` and `README.md`, and add an upgrade notice if people need
   to act. `readme.txt` keeps only the newest version, in short, and must stay
   under 10 KB; `changelog.txt` keeps every version in full.
   Numbers only (`1.2.3`): sites still on Git Updater offer a `Version:` on
   `main` to every site, and the shared updater skips tags with letters.
2. On the pull request's branch: `scripts/preflight-release.sh` (no errors) and
   `scripts/plugin-check.sh` (no errors).
   <!-- wps-own:start -->
   <!-- wps-own:end -->
3. Merge, then straight away:

   ```bash
   git fetch origin
   release_commit="$(gh pr view N --json mergeCommit --jq .mergeCommit.oid)"   # N is the release PR
   scripts/preflight-release.sh --ref "$release_commit"   # no errors before tagging
   git tag -a vX.Y.Z "$release_commit" -m "{Name} X.Y.Z"
   git push origin vX.Y.Z
   gh run watch   # choose the Release run for vX.Y.Z
   ```

   Tag the release PR's merge commit, not the latest `origin/main`: metrics
   commits use `[skip ci]`, which stops tag-triggered workflows, and touch only
   `docs/metrics/`, which is not in the zips.

   The tag starts the Release workflow (`.github/workflows/release.yml`).
   It checks the tag is on `main`, runs the preflight on it, builds the zips
   from it and publishes the release `{Name} X.Y.Z` with
   `{slug}-X.Y.Z.zip`, its notes taken from the version's section of the
   `README.md` changelog (edit them on GitHub afterwards if needed). In a
   public repository it also signs the zip's build provenance with Sigstore
   and attaches the bundle as `provenance-{slug}-X.Y.Z.sigstore.json`;
   anyone can check a download with
   `gh attestation verify {slug}-X.Y.Z.zip --repo {owner}/{repo}`. OpenSSF
   Scorecard counts it (Signed-Releases). Attestations in a private
   repository need GitHub Enterprise Cloud, so a private plugin's release
   has the zip only.

   If the workflow cannot run, publish by hand from the same tag:
   `scripts/build-release.sh --ref vX.Y.Z`, then
   `gh release create vX.Y.Z dist/{slug}-X.Y.Z.zip --verify-tag --title "{Name} X.Y.Z" --notes-file <notes>`.
   Running the workflow again later (Actions → the failed run → **Re-run
   jobs**, or Actions → **Release** → **Run workflow**, with `tag` set to
   `vX.Y.Z` if no run started) replaces that zip with its signed build.

   Sites with the shared updater see the release when they next check.
   Sites still on Git Updater are offered the `Version:` on `main` before the
   release exists, so do this in the same sitting as the merge.
4. Run `scripts/update-test.sh`. It checks the release has exactly one
   plugin asset, `{slug}-X.Y.Z.zip` (and, if present, that its provenance
   bundle verifies), and that a site with the previous version
   sees the update with **Check again** on the Updates screen and installs
   it. For a private repository, export a read-only token as
   `WPALLSTARS_GITHUB_TOKEN` first (below); the test site reads it from the
   environment. GitHub can take a few minutes to list a new release
   everywhere, so straight after one the test first waits up to 2 minutes
   for the address the site reads to name it, and checks a missing offer 3
   more times, 20 seconds apart. Without Docker, check the same by hand on a
   test site.
5. Roll the release out to the owner's own sites, one SSH host at a time:

   ```bash
   scripts/deploy-sites.sh --host <ssh-host> --tag vX.Y.Z            # lists the installs; changes nothing
   scripts/deploy-sites.sh --host <ssh-host> --tag vX.Y.Z --web-error-log <path> --apply    # installs, then one line per install
   scripts/deploy-sites.sh --host <ssh-host> --tag vX.Y.Z --web-error-log '~/.logs/error_log_{name_}' --apply    # one PHP log per site (Hostinger)
   ```

   Only installs that already have the plugin are touched. Each install line gives
   the old and new version, the status (`active-network` on a network
   activation), `purged=N/SITES` (the sites whose page cache was purged),
   `cron=N/M` (below), the main home page's HTTP code, `cache=` (the final response's
    `x-litespeed-cache`, `x-cache` and `cf-cache-status` headers, `none`, or
    `redirected:HOST` when a redirect dropped the unique query string) and the
    log lines gained. Networks add `sites=PASSED/TOTAL` and one indented
   `site` line per site, with its status, `purged=yes`, `no` or `failed`, home
   code, cache headers and result.
    Cloudflare: a Cache Rule that caches HTML keeps the pre-deploy pages for up
    to the edge TTL (2 hours by default), while the home fetch's unique query
    string never sees them. Add `--cloudflare-token-env NAME`, naming an
    environment variable that holds an API token limited to Zone → Zone Read
    (to find the zone) and Zone → Cache Purge, and the script purges the host names of each updated install's sites from
    your computer (the token never reaches the host and is never printed): it
    finds the zone from each site's host name, trying its parent domains, and
    after the install sends one `{"hosts":[...]}` purge per zone (30 hosts per
    request), so other sites sharing the zone keep their cached pages. The
    install line shows `cdn=purged(N hosts)`, `cdn=failed MESSAGE` (a failed
    purge does not fail the install) or `cdn=-` without the option, and the
    summary counts the requests. `--cloudflare-purge zone` instead sends
    `purge_everything` for each zone once per install, for pages on hosts the
    script does not see. The dry run with the option names the hosts it would
    purge for each zone and purges nothing. Without the option the script fetches each site's plain home
    address once after the install and warns `WARN Cloudflare keeps pages from
    before the deploy (age=N s); purge the zone or pass --cloudflare-token-env`
    when Cloudflare answers `cf-cache-status: HIT` with an `age` older than the
    install.
    After each site's full load, the plugin's own WP-Cron events (hooks in the
   site's cron schedule with a callback in the plugin's folder) run once on
   that site, each in its own `wp cron event run` process, shown as `cron=N/M`
   on the install line. A fatal error that only a cron callback reaches does
   not show in the load, the home fetch or the web PHP log (the host's cron
   job runs WP-Cron from the command line), so a PHP fatal error, database
   error or non-zero exit in one fails the install, with its restore command,
   and so does a change to the activation lists during the run. Side effect:
   running an event early also reschedules it, as `wp cron event run` by hand
   does. A hook runs all its callbacks, so a shared hook also runs core and
   other-plugin callbacks, and a failure in one counts against the install.
   An event gets `DEPLOY_CRON_TIMEOUT` seconds (default 120, `0` for no
   limit, which a host without `timeout` needs when there is an event to
   run); one that times out is a warning, not a failure. On a network each
   site runs its own. `wp cron event run` takes no lock, so when the site's
   own cron runner (`wp-cron.php` from the host's cron job) has already read
   the same due event, whichever runs it second logs `Cron reschedule event
   error for hook: HOOK, Error code: could_not_set` (or `unschedule`),
   followed on WordPress 6.1 and later by `, Error message: …, Data: …`
   in the site's language: only the hook and the code stay in
   English (Dutch: `Cron ongepland event fout voor hook: HOOK, foutcode:
   could_not_set, …`), so the check matches that shape, not the words: after
   the `[…]` timestamp, text with no `PHP …:` prefix (core writes it with
   `error_log()`) and no colon, comma or digit, then `: HOOK, `, a label,
   `: could_not_set, `, a label and the message, and a last label with the
   event's JSON (`: {…}`) ending the line (or before Apache's
   `, referer: URL`). A plugin's own line that only starts the same way
   (`Payment task failed for hook: HOOK, status: could_not_set`) still
   fails. For a hook the check just ran to completion, this message shows
   as `WARN cron race HOOK` and is not counted in `new_log_lines`; the warning does not confirm a race, as
   a cron-storage failure can log the same message. The same line for any other
   hook is cron-save contention, which warns only when every new line is one;
   every other new line still fails.
   Every site that is not archived, deleted or spam gets a guarded full load
   for its settings upgrade, a page cache purge and a home fetch with a query
   string unique to that fetch, pinned to the origin (`home=200 pinned`) when LiteSpeed
   Cache's Server IP or the address the plugin learned (its `{prefix}_origin_ip`
   option) is known; otherwise plain DNS, where a 4xx stays a warning. The purge matters: WordPress versions the
   plugin's CSS and JS by `?ver=`, and a cached page keeps pointing at the old
   version, so without it visitors get the old files until the page cache
   expires. It runs `wp litespeed-purge all` on a single site and
   `wp --url=<site> litespeed-purge blog <id>` on each network site (`all`
   would empty every site's cache each time) when
   `wp cli has-command litespeed-purge` finds LiteSpeed Cache (also when it is
   network-activated); other page caches are not purged, so purge them by
   hand. `wp cache flush` is not enough: it empties the object cache, not the
   pages. `WARN purge failed` means the purge command failed, so visitors may
    still get the old files. `WARN cached` means a cache answered anyway (it
    ignores query strings), so PHP did not run for that fetch. A redirect that
    drops the unique query reports `cache=redirected:HOST` instead, because any
    final cache response belongs to another address. Both warn
   rather than fail.
   A failed load, status read or home (5xx or no answer) fails the install;
   4xx is reported only. A busy host can answer one fetch with 5xx while the
   site is fine, so a home with 5xx or no answer is fetched once more after
   5 seconds: a pass then reports `WARN home retried (CODE)`, a second
   failure fails the site (`home failed (FIRST, then SECOND)`). All sites are
   checked even after one fails. On a
   single site, the FAIL line gives the reason (`FAIL: WordPress load
   failed (exit N: <last lines of WP-CLI's errors>)`); the full errors go
   to stderr. A failed install prints its restore command and the backup folder
   (`~/.{slug}-deploy/` on the host). `--parent` names the WordPress
   folders on hosts with another layout, and `--skip` leaves an install
   out. It never uses `wp plugin update`: behind an HTTP request limiter,
   WP-CLI's update check can report the plugin already up to date. Host
   names, folders and backups stay out of the repository and its issues.
   `--apply` requires `--web-error-log PATH`: verify the active web PHP
   `error_log` destination in the host's PHP-FPM/CGI or Apache configuration
   (including `.user.ini` overrides), not WP-CLI's CLI configuration. The
   path is absolute on the host, starts with `~/` for the SSH account's home
   folder, or is relative to each WordPress folder. On hosts with one web PHP
   log per site, `{name}` in the path is each install's name (as `--skip`
   takes it: `~/domains/example.com/public_html` is `example.com`) and
   `{name_}` the same with each `.` as `_` (`example_com`): on Hostinger,
   `--web-error-log '~/.logs/error_log_{name_}'` (or
   `'../../../.logs/error_log_{name_}'`) checks each install's own log in one
   run, with one lock, upload and summary. Quote the path so the local shell
   leaves it alone. Otherwise deploy separately with `--parent`/`--skip` when
   sites use different paths.
   Only file destinations are supported, not syslog or stderr. This path,
   the CLI PHP destination, `WP_DEBUG_LOG` and the two default paths are
   checked, including files first created during installation. A missing
   folder fails the install; a missing file in an existing folder is reported
   and counted if installation creates it.
   With aidevops, `wp-fleet-helper.sh` (plan, backup, deploy, verify and
   report across hosts, with a reviewed plan) is the alternative.

Sites read the repository without signing in, so it must be public for sites
to get updates. While it is private, a test site can use a read-only token
in `WPALLSTARS_GITHUB_TOKEN` (`wp-config.php`; it serves every plugin with
the shared updater). Making it public needs the owner's say; do the quality
sweep in `DEVELOPMENT.md` → At public launch in the same step.

## First release

Before a plugin's first release (1.0.0), work through **Before 1.0** in its
`LAUNCH.md`, which `scripts/rename-plugin.sh` writes. `scripts/preflight-release.sh`
warns, under Starter leftovers, about what is still the starter's: the
banner's words, the plug on the banner and icon, the description and the
screenshots.

## WordPress.org

Guidelines: [Detailed Plugin Guidelines](https://developer.wordpress.org/plugins/wordpress-org/detailed-plugin-guidelines/),
[Planning, submitting and maintaining](https://developer.wordpress.org/plugins/wordpress-org/planning-submitting-and-maintaining-plugins/),
[Plugin readmes](https://developer.wordpress.org/plugins/wordpress-org/how-your-readme-txt-works/),
[Plugin assets](https://developer.wordpress.org/plugins/wordpress-org/plugin-assets/),
[Using Subversion](https://developer.wordpress.org/plugins/wordpress-org/how-to-use-subversion/).

GitHub releases are the stable beta channel; WordPress.org gets each version
30 days after its GitHub release (`STANDARDS.md` → Releases). When a version
has been on GitHub for 30 days, release it to WordPress.org from its tag,
even if newer versions are on GitHub by then. A security release (its
changelog entry starts "Security:") goes to WordPress.org as soon as its
GitHub release is out: the newest GitHub release with the fix, so the
WordPress.org version skips ahead. Note each WordPress.org release, with its
date, in the plugin's `LAUNCH.md`.

The WordPress.org build replaces the affiliate links listed in
`.wporg-links` (one per line: the link or its referral query, a tab, and
the plain replacement, or nothing to remove a query), also where `&` is
written `&amp;` or `&#038;`, and only as a whole link: a listed `?ref=alice`
is left alone in `?ref=alice2`. The preflight errors when one is left in
that build and warns about other addresses with referral parameters
(`ref=`, `aff=`, `irpid=`, `via=` and the like).

Before submitting, work through the plugin's `LAUNCH.md`: what
`scripts/preflight-release.sh --strict` still reports, and a review of the
code against each guideline (no code from elsewhere, external services,
scripts and styles shipped with the plugin, links, admin notices, defaults,
files outside the plugin folder, uninstall, GPL, name and trademarks, a
complete plugin).

### Submitting

1. `scripts/build-release.sh --ref vX.Y.Z` (a version already released on
   GitHub), then `scripts/preflight-release.sh --ref vX.Y.Z --strict` passes,
   or every warning is accepted.
2. `scripts/plugin-check.sh --ref vX.Y.Z` reports no errors; read every
   warning.
3. Test the WordPress.org zip on a clean site (latest WordPress and 6.2 with
   PHP 7.4), with `WP_DEBUG` on: activate, turn each feature on and off,
   deactivate, delete. `debug.log` stays empty.
4. Signed in as the owner's WordPress.org account, upload
   `dist/wordpress-org-{slug}-X.Y.Z.zip` at
   [Add your plugin](https://wordpress.org/plugins/developers/add/), and ask
   for the `{slug}` slug in the notes.
5. Review takes about 1 to 10 business days. Reply to the reviewer's email
   from the same account; fix issues in the repository, not in a copy.

### After approval (Subversion)

The SVN repository is `https://plugins.svn.wordpress.org/{slug}/` (or the
slug given). It is for releases only, not development. The SVN password is
separate from the account password and is set on the WordPress.org profile
(see Using Subversion). Install Subversion first (`brew install subversion`).

1. Check out the empty repository: `svn co https://plugins.svn.wordpress.org/{slug}/ svn-{slug}`.
2. Unzip the WordPress.org build's `{slug}/` folder into `trunk/` (no zip
   files in SVN), `svn add` new files, `svn rm` removed ones.
3. Copy trunk to the tag: `svn cp trunk tags/X.Y.Z`. `Stable tag:` in
   `trunk/readme.txt` and `tags/X.Y.Z/readme.txt` must be `X.Y.Z`; never
   `trunk`.
4. Copy the listing images from `.wordpress-org/` to `assets/`: the banner
   and icon PNGs, `icon.svg` and the `screenshot-N` files (not
   `banner.svg`, which is only a source). `scripts/preflight-release.sh`
   checks them under "WordPress.org assets".
5. `svn ci -m "Release X.Y.Z"`, then check the plugin page and download.
6. Consider release confirmation emails (Plugin Handbook → Release
   Confirmation Emails), so a release goes out only after it is confirmed.

Each later WordPress.org release: the GitHub tag that has been out for 30
days (or the security release), `--strict` preflight, Plugin Check, then
steps 2 to 5. Readme-only changes
(such as raising Tested up to) go to trunk and the current tag.

Once listed, sites with the GitHub build update from WordPress.org, unless
the plugin returns true from `wpallstars_github_updater_early` (a setting
such as Early updates from GitHub), which keeps them on GitHub releases.
