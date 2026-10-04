# Contributing to WP Plugin Starter

Thank you for helping. Bug reports, fixes and ideas are all welcome.
Everyone taking part follows the `CODE_OF_CONDUCT.md`.

## Reporting a problem

Open an issue with the **Bug report** form. Include the versions, the steps
and any messages from `wp-content/debug.log`. Security problems go through
`SECURITY.md`, never a public issue.

## Suggesting a feature

Open an issue with the **Feature request** form before writing code. Each
setting makes a choice for the plugin's users, so a new one has to earn its
place: say what the feature does on its own and what problem it solves.

## Pull requests

1. Read `STANDARDS.md` (how features, settings, migrations and front-end
   styles work, the code rules and testing), `AGENTS.md` (what is this
   plugin's own) and `DEVELOPMENT.md` (set-up and checks).
2. Keep each pull request to one change. Features are off by default.
3. Run `scripts/lint.sh` and fix what it finds in the code.
4. Test on a real WordPress site, including WordPress 6.2 with PHP 7.4 if
   you use a core function, and Kadence light and dark mode if you change
   front-end styles.
5. Add a line to the changelogs: `README.md` (details), `changelog.txt`
   (for users) and `readme.txt` (one short line).

CI runs the checks on every pull request. Write the pull request description
so a reviewer knows what changed, why, and how you tested it.

## Licence

WP Plugin Starter is GPL-3.0-or-later, with the additional terms in
`ATTRIBUTION.txt` (GPL-3.0 section 7(b)). By contributing, you agree your work
is released under the same licence and terms.
