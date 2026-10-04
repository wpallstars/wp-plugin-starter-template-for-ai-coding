# Releasing

How every plugin made from the wpallstars starter plugin is released. This
file is the same in each of them (names as placeholders: `STANDARDS.md`
lists them, and the plugin's `AGENTS.md` gives its values). The plugin's own
submission state and guideline review: `LAUNCH.md`.

Releases on GitHub and the WordPress.org submission need the owner's say.
None of the scripts below tags, publishes, uploads or commits anything. The
Release workflow (`.github/workflows/release.yml`) publishes a GitHub release
only when someone pushes a version tag.

## Scripts

| Script | What it does |
|--------|--------------|
| `scripts/build-release.sh [--ref REF] [--out DIR]` | Builds both zips from a Git ref (default `HEAD`) into `dist/` (gitignored), with `SHA256SUMS`. Files come from Git, never the working tree. |
| `scripts/preflight-release.sh [--ref REF] [--strict] [--offline]` | Checks versions, headers, readme, both zips (layout, development files, PHP 7.4 and JS syntax, updater code), remote assets, presets and starter data where the plugin has them, and the Git tag. Errors stop a release; `--strict` also fails on warnings, for a WordPress.org submission. |
| `scripts/plugin-check.sh [--ref REF] [--zip FILE]` | Runs Plugin Check on both zips in a disposable WordPress in Docker, then removes it. |
| `scripts/update-test.sh [--from X.Y.Z] [--to X.Y.Z] [--wp VERSION] [--php VERSION] [--keep-log FILE]` | After a release: installs the previous GitHub release (default: the one before the newest) on a disposable WordPress in Docker and checks that it is offered the new one from its asset (WP-CLI, **Check again** on the Updates screen, the Plugins screen), that the update installs and the plugin stays active, and that `debug.log` stays empty. Then removes the site. Reads releases with `gh`. |

The two builds of each version:

| Zip | Contents | Goes to |
|-----|----------|---------|
| `{slug}-X.Y.Z.zip` | Files in Git, less `.distignore`, with `Update URI: https://github.com/{owner}/{repo}` added to the main file | GitHub release asset |
| `wordpress-org-{slug}-X.Y.Z.zip` | The same, less `.distignore-wporg` (the GitHub updater) and the `GitHub Plugin URI`, `Primary Branch` and `Release Asset` header lines, without `Update URI` | WordPress.org only |

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

## GitHub release

1. In a pull request, set the version in `{slug}.php` (`Version:` and
   `{PREFIX}_VERSION`), `readme.txt` (`Stable tag:`) and `README.md` (the
   `Version:` line under the intro, which GitHub shows as written), rename the
   changelog's Unreleased section to the version in `readme.txt`,
   `changelog.txt` and `README.md`, and add an upgrade notice if people need
   to act. `readme.txt` keeps only the newest version, in short, and must stay
   under 10 KB; `changelog.txt` keeps every version in full.
   Numbers only (`1.2.3`): sites still on Git Updater offer a `Version:` on
   `main` to every site, and the shared updater skips tags with letters.
2. On the pull request's branch: `scripts/preflight-release.sh` (no errors) and
   `scripts/plugin-check.sh` (no errors).
3. Merge, then straight away:

   ```bash
   git fetch origin
   scripts/preflight-release.sh --ref origin/main   # no errors before tagging
   git tag -a vX.Y.Z origin/main -m "{Name} X.Y.Z"
   git push origin vX.Y.Z
   gh run watch   # choose the Release run for vX.Y.Z
   ```

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
   jobs**) replaces that zip with its signed build.

   Sites with the shared updater see the release when they next check.
   Sites still on Git Updater are offered the `Version:` on `main` before the
   release exists, so do this in the same sitting as the merge.
4. Run `scripts/update-test.sh`. It checks the release has exactly one
   plugin asset, `{slug}-X.Y.Z.zip` (and, if present, that its provenance
   bundle verifies), and that a site with the previous version
   sees the update with **Check again** on the Updates screen and installs
   it. For a private repository, export a read-only token as
   `WPALLSTARS_GITHUB_TOKEN` first (below); the test site reads it from the
   environment. Without Docker, check the same by hand on a test site.

Sites read the repository without signing in, so it must be public for sites
to get updates. While it is private, a test site can use a read-only token
in `WPALLSTARS_GITHUB_TOKEN` (`wp-config.php`; it serves every plugin with
the shared updater). Making it public needs the owner's say; do the quality
sweep in `DEVELOPMENT.md` → At public launch in the same step.

## WordPress.org

Guidelines: [Detailed Plugin Guidelines](https://developer.wordpress.org/plugins/wordpress-org/detailed-plugin-guidelines/),
[Planning, submitting and maintaining](https://developer.wordpress.org/plugins/wordpress-org/planning-submitting-and-maintaining-plugins/),
[Plugin readmes](https://developer.wordpress.org/plugins/wordpress-org/how-your-readme-txt-works/),
[Plugin assets](https://developer.wordpress.org/plugins/wordpress-org/plugin-assets/),
[Using Subversion](https://developer.wordpress.org/plugins/wordpress-org/how-to-use-subversion/).

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

Each later WordPress.org release: build from the tag that is already on GitHub,
`--strict` preflight, Plugin Check, then steps 2 to 5. Readme-only changes
(such as raising Tested up to) go to trunk and the current tag.

Once listed, sites with the GitHub build update from WordPress.org, unless
the plugin returns true from `wpallstars_github_updater_early` (a setting
such as Early updates from GitHub), which keeps them on GitHub releases.
