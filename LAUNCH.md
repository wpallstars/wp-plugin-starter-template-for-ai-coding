# WP Plugin Starter — launch state

The starter is released on GitHub only. It is not meant for WordPress.org:
it has no features, and plugins made from it are submitted under their own
names. `RELEASING.md` → WordPress.org applies to those plugins, each with its
own `LAUNCH.md`.

`scripts/preflight-release.sh` and `scripts/plugin-check.sh` still run on
every release, so the core files stay ready for a plugin's submission.

The repository is public. From `DEVELOPMENT.md` → At public launch, these
are on: CodeQL (default setup: GitHub Actions and JavaScript), Dependabot
security updates, secret scanning with push protection, private
vulnerability reporting, OpenSSF Scorecard, and a `main` ruleset (pull
requests with squash merges, the four CI checks required, no force pushes or
deletion; repository admins may bypass, so the maintainer can merge their
own pull requests). Releases are built, signed and published by the Release
workflow. Still open: `SYNC_PAT` (`DEVELOPMENT.md` → Services setup, step
3); until it is set, the repository metrics on protected `main` are not
updated.
