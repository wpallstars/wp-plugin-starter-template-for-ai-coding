# AI Tool Best Practices

This document addresses recurring AI tool failure patterns detected from real development sessions in this repository.

These patterns were observed across multiple AI models (Claude, GPT-4, Gemini) and are tracked as contributor insights.

Implementing these practices reduces wasted tokens, failed edits, and broken pipelines.

## Table of Contents

* [Read Before Edit](#read-before-edit)
* [Re-Read After Edit](#re-read-after-edit)
* [Verify File Paths Before Reading](#verify-file-paths-before-reading)
* [Bash Command Hygiene](#bash-command-hygiene)
* [Known File Paths in This Repository](#known-file-paths-in-this-repository)

## Read Before Edit

**Failure pattern**: `edit:not_read_first` — 71 occurrences across 3 models.

**Root cause**: AI assistants attempt to use the Edit or Write tool on a file without first reading it with the Read tool. The Edit tool requires knowing the exact current content to construct a valid `oldString`/`newString` replacement.

### Rules

* ALWAYS use the Read tool on a file before using Edit or Write on it.
* This applies even when you wrote the file yourself earlier in the session — something else may have modified it.
* This applies even for single-line changes — you need the surrounding context lines.
* If another tool (Bash, a script, a build step) has modified a file since you last read it, re-read before editing.

### Correct pattern

```
Read: includes/core.php
Edit: includes/core.php (oldString matches what Read returned)
```

### Incorrect pattern (causes edit:not_read_first)

```
Edit: includes/core.php (no prior Read in this session)
```

## Re-Read After Edit

**Failure pattern**: `edit:edit_stale_read` — 32 occurrences across 3 models.

**Root cause**: After an Edit or Write tool call, the in-memory content of the file is immediately stale. A second Edit based on the pre-edit content will fail because `oldString` no longer matches the file on disk.

### Rules

* After any Edit or Write to a file, re-read it before making a second edit.
* The required sequence for multiple edits to the same file is: Read → Edit → Re-read → Edit → Re-read → Edit.
* Never chain two Edit calls to the same file without a Read in between.

### Correct pattern

```
Read: admin/lib/admin.php       (get current content)
Edit: admin/lib/admin.php       (first change)
Read: admin/lib/admin.php       (get updated content)
Edit: admin/lib/admin.php       (second change)
```

### Incorrect pattern (causes edit:edit_stale_read)

```
Read: admin/lib/admin.php       (get current content)
Edit: admin/lib/admin.php       (first change)
Edit: admin/lib/admin.php       (second change — oldString is stale, will fail)
```

## Verify File Paths Before Reading

**Failure pattern**: `read:file_not_found` — 23 occurrences across 4 models.

**Root cause**: AI assistants attempt to read files at paths that do not exist — usually due to assumed paths, renamed files, or path confusion in a multi-worktree workspace.

### Rules

* Before reading a file, verify it exists using `git ls-files '<pattern>'`.
* Use `git ls-files | grep <keyword>` when the exact path is uncertain.
* Never assume a file exists based on what you expect the project structure to contain.
* Paths in git worktrees differ from the canonical repo — the worktree root is a different directory.

### Verification commands

```bash
# Check a specific file exists
git ls-files 'includes/core.php'

# Find files matching a keyword
git ls-files | grep 'admin'

# List all tracked PHP files
git ls-files '*.php'

# List all tracked files in a directory
git ls-files 'includes/'
```

### Known tracked paths in this repository

See [Known File Paths in This Repository](#known-file-paths-in-this-repository) below.

## Bash Command Hygiene

**Failure pattern**: `bash:other` — 66 occurrences across 3 models.

**Root cause**: Bash tool calls fail for multiple reasons — wrong working directory, missing prerequisite tools, incorrect paths, unquoted strings with spaces, and commands that exit non-zero unexpectedly.

### Rules

1. **Verify working directory** — use `pwd` if uncertain before running path-dependent commands.
2. **Check prerequisites** — verify `composer`, `npm`, `php`, `wp-cli`, etc. are available before using them.
3. **Use `|| true` for acceptable failures** — if a command failing is expected or acceptable in a pipeline, append `|| true`.
4. **Quote paths with spaces** — always double-quote paths that may contain spaces.
5. **Check exit codes explicitly** — for critical commands, test `$?` or use `set -e` in scripts.

### Common failure causes and fixes

#### Wrong working directory

```bash
# Before a path-sensitive command, verify location
pwd

# Or use absolute paths
composer run phpcs --working-dir="/path/to/repo"
```

#### Missing prerequisite

```bash
# Check tool exists before using it
command -v composer || echo "composer not found"
command -v npm || echo "npm not found"
```

#### Command that may fail in pipeline

```bash
# Acceptable failure — don't abort the pipeline
npm run lint:js || true

# Check exit code explicitly when the result matters
composer run phpcs
if [ $? -ne 0 ]; then
    echo "PHPCS found violations"
fi
```

#### Unquoted paths

```bash
# Correct — quoted
git ls-files '*.php'

# Incorrect — may be interpreted by shell
git ls-files *.php
```

### Preferred commands for this repository

```bash
# PHP code quality
composer run phpcs     # Check coding standards
composer run phpcbf    # Auto-fix coding standards

# JavaScript
npm run lint:js        # ESLint check
npm run lint:css       # Stylelint check

# Tests
composer run phpunit   # PHP unit tests
npm run test:single    # Cypress single-site tests
npm run test:multisite # Cypress multisite tests

# Build
bash build.sh          # Build plugin release zip
```

## Known File Paths in This Repository

Use these paths directly. Verify with `git ls-files` if uncertain.

### Core plugin files

* `wp-plugin-starter-template.php` — Main plugin file with plugin headers
* `includes/plugin.php` — Main plugin class that initializes all components
* `includes/core.php` — Core functionality class
* `includes/updater.php` — Update mechanism for multiple sources

### Admin files

* `admin/lib/admin.php` — Admin class for admin-specific functionality
* `admin/lib/modal.php` — Modal class for update source selector
* `admin/css/` — Admin stylesheets directory
* `admin/js/` — Admin JavaScript files directory

### Configuration and tooling

* `composer.json` — PHP dependencies and scripts
* `package.json` — Node.js dependencies and scripts
* `phpcs.xml` — PHP CodeSniffer configuration
* `phpcs-simple.xml` — Simplified PHPCS configuration
* `phpstan.neon` — PHPStan static analysis configuration
* `phpunit.xml` — PHPUnit test configuration
* `.eslintrc.js` — ESLint JavaScript configuration
* `.stylelintrc.json` — Stylelint CSS configuration

### Documentation and AI guides

* `AGENTS.md` — Primary AI assistant guide for this repository
* `README.md` — Public-facing readme for GitHub
* `readme.txt` — WordPress.org readme
* `CHANGELOG.md` — Change log
* `.agents/` — Detailed AI assistant documentation directory
* `.wiki/` — Wiki documentation templates

### Testing

* `tests/` — PHP unit test files
* `cypress/` — Cypress end-to-end test files
* `playground/` — WordPress Playground blueprint files
* `bin/` — Helper scripts for local development and testing

### GitHub Actions

* `.github/workflows/` — CI/CD workflow definitions

## Summary: The Golden Rule

**Read → Edit → Re-read → Edit. Always verify paths. Always check prerequisites.**

Every edit failure in this repository has been traced to one of these four patterns.

Following these rules eliminates the most common class of AI tool failures in this codebase.
