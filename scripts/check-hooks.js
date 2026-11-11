#!/usr/bin/env node
/**
 * Checks docs/HOOKS.md, the list of the plugin's hooks, against the code
 * (STANDARDS.md → Code rules: hooks are a contract with site code):
 *
 *  - every {prefix}_* filter and action the PHP calls is listed, as supported
 *    or internal;
 *  - every listed hook is still called, or called through
 *    apply_filters_deprecated() / do_action_deprecated();
 *  - every hook listed as supported at the latest release tag (vX.Y.Z, not
 *    above the main file's version) is still in the code and still
 *    supported, unless a release at least two minor versions back already
 *    called it through a _deprecated function.
 *
 * {prefix} is the main file's define('<PREFIX>_VERSION', ...) in lower case,
 * as scripts/lib/plugin.sh reads it. A hook name built at run time
 * ("{prefix}_{$id}_items") counts when at least one listed hook fits it.
 * PHP in scripts/ (test helpers, not shipped) is not searched. The release
 * check needs the tags and their history; without them (a shallow clone, or
 * a new plugin before its first release) it is skipped with a note. A plugin without docs/HOOKS.md is skipped.
 *
 * Usage: node scripts/check-hooks.js   (or scripts/lint.sh hooks)
 * Exit status: 0 when the list matches or there is none, 1 when it does not.
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 * SPDX-FileCopyrightText: 2026 Marcus Quinn
 * Additional terms (GPL-3.0 section 7(b)): ATTRIBUTION.txt
 * Provenance: wpas-e4502af0f07e8a92. Copies, even of part, keep these lines.
 */
'use strict';

const { execFileSync } = require('node:child_process');
const fs = require('node:fs');
const path = require('node:path');

const DOC = 'docs/HOOKS.md';
const TYPES = ['filter', 'action'];
const STATUSES = ['supported', 'internal'];
const RULE = `${DOC} → Deprecation rule`;

process.chdir(path.resolve(__dirname, '..'));

function fail(message) {
	console.error(`check-hooks: ${message}`);
	process.exit(1);
}

// Git from a fixed system folder rather than whatever PATH holds.
function findGit() {
	for (const bin of ['/usr/bin/git', '/usr/local/bin/git', '/opt/homebrew/bin/git']) {
		if (fs.existsSync(bin)) {
			return bin;
		}
	}
	return fail('git was not found in /usr/bin, /usr/local/bin or /opt/homebrew/bin.');
}
const gitBin = findGit();

// Git's output, or null when it fails (a missing tag or file).
function git(...args) {
	try {
		return execFileSync(gitBin, args, { encoding: 'utf8', maxBuffer: 64 * 1024 * 1024, stdio: ['ignore', 'pipe', 'ignore'] });
	} catch {
		return null;
	}
}

// The hook prefix and the version, from the main file (the PHP file at the
// top of the repository with a Plugin Name: header): its
// define('<PREFIX>_VERSION', 'x.y.z'), the prefix in lower case.
function mainFile() {
	const files = (git('ls-files', '--', ':(glob)*.php') || '').split('\n').filter(Boolean);
	const main = files.filter((file) => /^[ \t/*#@]*Plugin Name:/im.test(fs.readFileSync(file, 'utf8').slice(0, 8192)));
	if (main.length !== 1) {
		fail(main.length ? `more than one main file: ${main.join(', ')}.` : 'no PHP file with a Plugin Name: header at the top of the repository.');
	}
	const constant = /define\(\s*['"]([A-Z0-9_]+)_VERSION['"]\s*,\s*['"]([^'"]*)['"]/.exec(fs.readFileSync(main[0], 'utf8'));
	if (!constant) {
		fail(`${main[0]} does not define a <PREFIX>_VERSION constant.`);
	}
	return { prefix: constant[1].toLowerCase(), version: constant[2] };
}

if (!fs.existsSync(DOC)) {
	console.log(`check-hooks: no ${DOC}; skipped. Add one to list the plugin's hooks (STANDARDS.md → Code rules).`);
	process.exit(0);
}

const { prefix, version } = mainFile();
const hookName = new RegExp(`^${prefix}_[a-z0-9_]+$`);
// The first argument of a hook call: a quoted name, then a "." when the code
// joins more to it.
const callRe = /\b(apply_filters|do_action)(_ref_array|_deprecated)?\(\s*(?:'([^'\n]*)'|"([^"\n]*)")(\s*\.)?/g;

// A regular expression for a name built at run time: "{prefix}_{$id}_items"
// or '{prefix}_' . $id.
function namePattern(text, joined) {
	const parts = text.split(/\{\$[^}]*\}|\$[A-Za-z_]\w*(?:->\w+|\[[^\]]*\])*/);
	const body = parts.map((part) => part.replace(/[.*+?^${}()|[\]\\]/g, String.raw`\$&`)).join('[a-z0-9_]+');
	return new RegExp(`^${body}${joined ? '[a-z0-9_]+' : ''}$`);
}

// The hooks called in PHP (working tree, as committed or not): live names,
// names only called through a _deprecated function, and run-time patterns.
function hooksIn(text) {
	const found = { live: new Set(), deprecated: new Set(), patterns: new Map() };
	for (const m of text.matchAll(callRe)) {
		const name = m[3] ?? m[4];
		if (!name.startsWith(`${prefix}_`)) {
			continue;
		}
		const built = m[5] !== undefined || (m[4] !== undefined && name.includes('$'));
		if (built) {
			found.patterns.set(m[5] === undefined ? name : `${name}…`, namePattern(name, m[5] !== undefined));
		} else if (m[2] === '_deprecated') {
			found.deprecated.add(name);
		} else {
			found.live.add(name);
		}
	}
	return found;
}

// The PHP lines with hook calls, each with the two lines after it, so a call
// split over lines is seen: in the working tree (new files not yet added
// included), or at REF. Empty when there are none; null when git grep fails.
function phpCalls(ref) {
	const args = ['grep', ...(ref ? [] : ['--untracked']), '-h', '-A2', '-E', '(apply_filters|do_action)'];
	if (ref) {
		args.push(ref);
	}
	args.push('--', '*.php', ':(exclude)scripts/');
	try {
		return execFileSync(gitBin, args, { encoding: 'utf8', maxBuffer: 64 * 1024 * 1024, stdio: ['ignore', 'pipe', 'ignore'] });
	} catch (error) {
		return error.status === 1 ? '' : null;
	}
}

// The rows of a hooks list: name => { type, status }.
function readList(text, problems) {
	const listed = new Map();
	for (const line of text.split('\n')) {
		const cells = line.split(/(?<!\\)\|/).map((cell) => cell.trim());
		const m = /^`([^`]+)`$/.exec(cells[1] || '');
		if (!line.trimStart().startsWith('|') || !m) {
			continue;
		}
		const [name, type, status] = [m[1], cells[2], cells[3]];
		if (!problems) {
			listed.set(name, { type, status });
			continue;
		}
		if (!hookName.test(name)) {
			problems.push(`${name}: not a ${prefix}_* hook; list only this plugin's own hooks.`);
			continue;
		}
		if (listed.has(name)) {
			problems.push(`${name} is listed twice.`);
		}
		if (!TYPES.includes(type)) {
			problems.push(`${name}: the type must be filter or action, not "${type}".`);
		}
		if (!STATUSES.includes(status)) {
			problems.push(`${name}: the status must be supported or internal, not "${status}".`);
		}
		listed.set(name, { type, status });
	}
	return listed;
}

const problems = [];
const code = phpCalls(null);
if (code === null) {
	fail('could not search the code with git grep.');
}
const found = hooksIn(code);
const listed = readList(fs.readFileSync(DOC, 'utf8'), problems);
const fits = (name) => [...found.patterns.values()].some((re) => re.test(name));
const inCode = (name) => found.live.has(name) || found.deprecated.has(name) || fits(name);

for (const name of [...found.live, ...found.deprecated].sort((a, b) => a.localeCompare(b))) {
	if (!listed.has(name)) {
		problems.push(`${name} is called in the code but not listed: add its row.`);
	}
}
for (const [built, re] of found.patterns) {
	if (![...listed.keys()].some((name) => re.test(name))) {
		problems.push(`"${built}" builds a hook name at run time, and no listed hook fits it: list each name it makes.`);
	}
}
for (const [name, row] of listed) {
	if (!hookName.test(name) || !STATUSES.includes(row.status) || inCode(name)) {
		continue;
	}
	if (row.status === 'supported') {
		problems.push(`${name} is supported but no longer in the code: keep it, or call it through apply_filters_deprecated() / do_action_deprecated() for at least two minor releases (${RULE}).`);
	} else {
		problems.push(`${name} is internal and no longer in the code: remove its row.`);
	}
}

// Release check: the latest release tag in this branch's history, and the
// newest release at least two minor versions before it. Tags above the main
// file's version are not this plugin's own (a copy that kept the starter's
// history starts again at 0.1.0).
function versionParts(text) {
	const v = /^v?(\d+)\.(\d+)\.(\d+)$/.exec(text);
	return v ? v.slice(1).map(Number) : null;
}
function minorKey(tag) {
	const v = versionParts(tag);
	return v ? v[0] * 1000 + v[1] : null;
}
function notAbove(tag, ceiling) {
	const [a, b] = [versionParts(tag), versionParts(ceiling)];
	if (!a || !b) {
		return a !== null;
	}
	const i = a.findIndex((part, n) => part !== b[n]);
	return i === -1 || a[i] < b[i];
}
const tags = (git('tag', '--list', '--merged', 'HEAD', '--sort=-v:refname') || '').split('\n').filter((tag) => minorKey(tag) !== null && notAbove(tag, version));
let release = '';
if (tags.length === 0) {
	console.log(`check-hooks: no release tags up to ${version} in this history (none yet, or a shallow clone); the release check is skipped.`);
} else {
	const latest = tags[0];
	const old = tags.find((tag) => minorKey(tag) <= minorKey(latest) - 2);
	const oldDeprecated = old ? hooksIn(phpCalls(old) || '').deprecated : new Set();
	const doc = git('show', `${latest}:${DOC}`);
	const before = readList(doc || '', null);
	let released = 0;
	// Rows with another prefix (a copy of the starter's tags) are not this
	// plugin's hooks.
	for (const [name, row] of before) {
		if (row.status !== 'supported' || !hookName.test(name)) {
			continue;
		}
		released++;
		if (!inCode(name) && !oldDeprecated.has(name)) {
			const since = old ? `in ${old} or earlier` : 'two minor releases before';
			problems.push(`${name} was supported in ${latest} and is gone without being deprecated ${since}: restore it, or deprecate it for two minor releases first (${RULE}).`);
		} else if (listed.has(name) && listed.get(name).status !== 'supported') {
			problems.push(`${name} was supported in ${latest}: it stays supported until it is removed (${RULE}).`);
		}
	}
	release = doc === null ? `; ${latest} has no hooks list yet` : `; ${released} supported in ${latest}`;
}

if (problems.length) {
	console.error(`check-hooks: ${DOC} and the code disagree:`);
	for (const problem of problems) {
		console.error(`  - ${problem}`);
	}
	process.exit(1);
}
const supported = [...listed.values()].filter((row) => row.status === 'supported').length;
const built = found.patterns.size ? `, ${found.patterns.size} built at run time` : '';
console.log(`check-hooks: ${listed.size} hooks listed (${supported} supported, ${listed.size - supported} internal); ${found.live.size} called in the code, ${found.deprecated.size} deprecated${built}${release}. All match.`);
