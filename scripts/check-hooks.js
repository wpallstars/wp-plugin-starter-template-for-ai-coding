#!/usr/bin/env node
/**
 * Checks docs/HOOKS.md, the list of the plugin's hooks, against the code
 * (STANDARDS.md → Code rules: hooks are a contract with site code):
 *
 *  - every {prefix}_* filter and action the PHP calls is listed, as supported
 *    or internal, with the type the code calls it as (apply_filters*() is a
 *    filter, do_action*() an action);
 *  - every listed hook is still called, or called through
 *    apply_filters_deprecated() / do_action_deprecated();
 *  - every hook listed as supported at the latest release tag (vX.Y.Z, not
 *    above the main file's version) is still in the code and still
 *    supported, unless a release at least two minor versions back (counting
 *    each major.minor released, so v0.8 is two before v1.0) already called
 *    it through a _deprecated function.
 *
 * A call inside a PHP comment does not count.
 *
 * {prefix} is the main file's define('<PREFIX>_VERSION', ...) in lower case,
 * as scripts/lib/plugin.sh reads it; here the define may also span lines. A
 * hook name built at run time ("{prefix}_{$id}_items", or
 * '{prefix}_' . $id . '_items') counts when at least one listed hook fits it.
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
	if (fs.existsSync('/usr/bin/git')) {
		return '/usr/bin/git';
	}
	if (fs.existsSync('/usr/local/bin/git')) {
		return '/usr/local/bin/git';
	}
	if (fs.existsSync('/opt/homebrew/bin/git')) {
		return '/opt/homebrew/bin/git';
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
// define('<PREFIX>_VERSION', 'x.y.z'), the prefix in lower case. The whole
// file is read (through git grep, as the hooks are), comments blanked out,
// so a define split over lines is found too.
function mainFile() {
	const main = (git('grep', '-l', '-I', '-i', '-E', '^[[:space:]/*#@]*Plugin Name:', '--', ':(glob)*.php') || '').split('\n').filter(Boolean);
	if (main.length !== 1) {
		fail(main.length ? `more than one main file: ${main.join(', ')}.` : 'no PHP file with a Plugin Name: header at the top of the repository.');
	}
	const source = stripComments(git('grep', '-h', '-I', '-E', '^', '--', main[0]) || '');
	const constant = /define\(\s*['"]([A-Z0-9_]+)_VERSION['"]\s*,\s*['"]([^'"]*)['"]/.exec(source);
	if (!constant) {
		fail(`${main[0]} does not define a {PREFIX}_VERSION constant.`);
	}
	return { prefix: constant[1].toLowerCase(), version: constant[2] };
}

if (!fs.existsSync(DOC)) {
	console.log(`check-hooks: no ${DOC}; skipped. Add one to list the plugin's hooks (STANDARDS.md → Code rules).`);
	process.exit(0);
}

const { prefix, version } = mainFile();
const SLUG = /^[a-z0-9_]+$/;
const isHookName = (name) => name.length > prefix.length + 1 && name.startsWith(`${prefix}_`) && SLUG.test(name);
// The first argument of a hook call: a quoted name, then a "." when the code
// joins more to it.
const callRe = /\b(apply_filters|do_action)(_ref_array|_deprecated)?\(\s*(?:'([^'\n]*)'|"([^"\n]*)")(\s*\.)?/g;

// A matcher for a name built at run time: "{prefix}_{$id}_items" or
// '{prefix}_' . $id. The literal parts must appear in order, at the start and
// the end, and each gap between them is one or more of [a-z0-9_]. No
// RegExp is built from the code being checked.
function namePattern(text, joined) {
	const parts = text.split(/\{\$[^}]*\}|\$[A-Za-z_]\w*(?:->\w+|\[[^\]]*\])*/);
	if (joined) {
		parts.push('');
	}
	const first = parts[0];
	const last = parts[parts.length - 1];
	return (candidate) => {
		if (parts.length === 1) {
			return candidate === first;
		}
		if (!candidate.startsWith(first)) {
			return false;
		}
		let pos = first.length;
		for (const part of parts.slice(1, -1)) {
			const at = candidate.indexOf(part, pos + 1);
			if (at === -1 || !SLUG.test(candidate.slice(pos, at))) {
				return false;
			}
			pos = at + part.length;
		}
		const end = candidate.length - last.length;
		return end > pos && candidate.endsWith(last) && SLUG.test(candidate.slice(pos, end));
	};
}

// One part of a name joined with "." after its first literal: a quoted
// literal or a plain variable, then the next "." or the end of the argument
// ("," or ")").
const joinRe = /\s*(?:'([a-z0-9_]*)'|"([^"\\\n]*)"|(\$[A-Za-z_]\w*(?:->\w+|\[[^\]}\n]*\])*))\s*([.,)])/y;

// The rest of a joined name ('{prefix}_' . $id . '_items') from `from`, the
// place after its first ".", written as a built name is ("{$id}_items"); or
// null when a part is anything else (a function call, a constant), which the
// check cannot read.
function joinedRest(text, from) {
	let rest = '';
	joinRe.lastIndex = from;
	for (;;) {
		const part = joinRe.exec(text);
		if (!part) {
			return null;
		}
		rest += part[1] ?? part[2] ?? `{${part[3]}}`;
		if (part[4] !== '.') {
			return rest;
		}
	}
}

// The hooks called in PHP (working tree, as committed or not): live names,
// names only called through a _deprecated function, and run-time patterns
// ({ match, kinds, loose, label }); deprecatedPatterns holds the precise
// run-time patterns called through a _deprecated function: a loose one fits
// every name with its first literal, so it proves no hook's deprecation in
// the release check (GH#758). kinds: name => Set of
// "filter"/"action", as the code calls it. A joined name is read to the end
// of its argument, so 'p_' . $s . '_label' and 'p_' . $s . '_saved' are two
// patterns; one whose rest cannot be read is loose: it fits every name that
// starts with its first literal and keeps a key of its own, so calls with
// different endings never share their types.
function hooksIn(text) {
	const found = { live: new Set(), deprecated: new Set(), patterns: new Map(), deprecatedPatterns: [], kinds: new Map() };
	for (const m of text.matchAll(callRe)) {
		const name = m[3] ?? m[4];
		if (!name.startsWith(`${prefix}_`)) {
			continue;
		}
		const kind = m[1] === 'apply_filters' ? 'filter' : 'action';
		const built = m[5] !== undefined || (m[4] !== undefined && name.includes('$'));
		if (built) {
			const rest = m[5] === undefined ? '' : joinedRest(text, m.index + m[0].length);
			const loose = rest === null;
			const key = loose ? `${name}…@${m.index}` : name + rest;
			if (!found.patterns.has(key)) {
				found.patterns.set(key, { match: namePattern(loose ? name : key, loose), kinds: new Set(), loose, label: loose ? `${name}…` : key });
			}
			found.patterns.get(key).kinds.add(kind);
			if (m[2] === '_deprecated' && !loose) {
				found.deprecatedPatterns.push(found.patterns.get(key).match);
			}
			continue;
		}
		(m[2] === '_deprecated' ? found.deprecated : found.live).add(name);
		if (!found.kinds.has(name)) {
			found.kinds.set(name, new Set());
		}
		found.kinds.get(name).add(kind);
	}
	return found;
}

// The end of a heredoc or nowdoc that starts at i (<<<ID, <<<'ID' or
// <<<"ID"): the index after its closing ID, or -1 when none starts there.
function heredocEnd(source, i) {
	const open = /^<<<[ \t]*(['"]?)([A-Za-z_]\w*)\1[ \t]*\r?\n/.exec(source.slice(i, i + 200));
	if (!open) {
		return -1;
	}
	const id = open[2];
	let pos = i + open[0].length;
	while (pos < source.length) {
		const eol = source.indexOf('\n', pos);
		const line = source.slice(pos, eol === -1 ? source.length : eol);
		const body = line.trimStart();
		if (body.startsWith(id) && !/\w/.test(body.charAt(id.length))) {
			return pos + (line.length - body.length) + id.length;
		}
		if (eol === -1) {
			break;
		}
		pos = eol + 1;
	}
	return source.length;
}

// PHP source with its comments (/* … */, // and # to the end of the line)
// blanked out, outside quoted strings, heredocs and inline HTML, so a
// commented-out call is not a call. Newlines stay, so a call split over
// lines still matches.
function stripComments(source) {
	let out = '';
	let i = 0;
	while (i < source.length) {
		// Inline HTML, copied as it is, up to the next <?php or <?=.
		const open = source.indexOf('<?', i);
		const start = open === -1 ? source.length : open + 2;
		out += source.slice(i, start);
		i = start;
		// PHP, token by token, up to ?> or the end of the file.
		while (i < source.length) {
			const [end, kind] = phpToken(source, i);
			const text = source.slice(i, end);
			out += kind === 'blank' ? text.replace(/[^\n]/g, ' ') : text;
			i = end;
			if (kind === 'close') {
				break;
			}
		}
	}
	return out;
}

// The PHP token that starts at i, as [end, kind]: kind is "close" (?>, back
// to inline HTML), "blank" (a comment) or "keep" (a string, a heredoc or one
// character of code).
function phpToken(source, i) {
	const two = source.slice(i, i + 2);
	if (two === '?>') {
		return [i + 2, 'close'];
	}
	if (two === '/*') {
		const end = source.indexOf('*/', i + 2);
		return [end === -1 ? source.length : end + 2, 'blank'];
	}
	if (two === '//' || (source[i] === '#' && two !== '#[')) {
		return [lineCommentEnd(source, i), 'blank'];
	}
	if (source[i] === "'" || source[i] === '"') {
		return [stringEnd(source, i), 'keep'];
	}
	const heredoc = source[i] === '<' ? heredocEnd(source, i) : -1;
	return [heredoc === -1 ? i + 1 : heredoc, 'keep'];
}

// The index after the quoted string that starts at i (backslash escapes
// skipped), or the end of the file when it does not close.
function stringEnd(source, i) {
	let j = i + 1;
	while (j < source.length && source[j] !== source[i]) {
		j += source[j] === '\\' ? 2 : 1;
	}
	return Math.min(j + 1, source.length);
}

// Where a // or # comment that starts at i ends: at the end of its line,
// or before a ?> that closes PHP on that line.
function lineCommentEnd(source, i) {
	const ends = [source.indexOf('\n', i), source.indexOf('?>', i)].filter((at) => at !== -1);
	return ends.length ? Math.min(...ends) : source.length;
}

// The text of each PHP file that calls a hook, comments blanked out: in the
// working tree (new files not yet added included), or at REF. Whole files,
// read through git grep (no file is opened by a built path), so a block
// comment that starts lines before a call is seen. Empty when there are
// none; null when git grep fails.
function phpCalls(ref) {
	const args = ['grep', ...(ref ? [] : ['--untracked']), '-I', '--null', '-E', '^'];
	if (ref) {
		args.push(ref);
	}
	args.push('--', '*.php', ':(exclude)scripts/');
	let output;
	try {
		output = execFileSync(gitBin, args, { encoding: 'utf8', maxBuffer: 256 * 1024 * 1024, stdio: ['ignore', 'pipe', 'ignore'] });
	} catch (error) {
		return error.status === 1 ? '' : null;
	}
	// Each line is "path\0text" ("REF:path\0text" at a ref).
	const files = new Map();
	for (const line of output.split('\n')) {
		const cut = line.indexOf('\0');
		if (cut === -1) {
			continue;
		}
		const file = line.slice(0, cut);
		if (!files.has(file)) {
			files.set(file, []);
		}
		files.get(file).push(line.slice(cut + 1));
	}
	let text = '';
	for (const lines of files.values()) {
		const source = lines.join('\n');
		if (source.includes('apply_filters') || source.includes('do_action')) {
			text += `${stripComments(source)}\n`;
		}
	}
	return text;
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
		if (!isHookName(name)) {
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
const fits = (name) => [...found.patterns.values()].some((pattern) => pattern.match(name));
const inCode = (name) => found.live.has(name) || found.deprecated.has(name) || fits(name);

for (const name of [...new Set([...found.live, ...found.deprecated])].sort((a, b) => a.localeCompare(b))) {
	if (!listed.has(name)) {
		problems.push(`${name} is called in the code but not listed: add its row.`);
	}
}
const reported = new Set();
for (const pattern of found.patterns.values()) {
	if (!reported.has(pattern.label) && ![...listed.keys()].some((name) => pattern.match(name))) {
		reported.add(pattern.label);
		problems.push(`"${pattern.label}" builds a hook name at run time, and no listed hook fits it: list each name it makes.`);
	}
}
// The listed type against the calls: apply_filters*() is a filter,
// do_action*() an action. A name called both ways is reported for the other.
// Loose patterns (a joined name the check cannot read) count only for a name
// no other call fits, and then pass when any of them has the listed type.
for (const [name, row] of listed) {
	if (!TYPES.includes(row.type)) {
		continue;
	}
	const kinds = new Set(found.kinds.get(name) || []);
	const loose = new Set();
	for (const pattern of found.patterns.values()) {
		if (pattern.match(name)) {
			pattern.kinds.forEach((kind) => (pattern.loose ? loose : kinds).add(kind));
		}
	}
	if (kinds.size === 0 && !loose.has(row.type)) {
		loose.forEach((kind) => kinds.add(kind));
	}
	for (const kind of [...kinds].sort((a, b) => a.localeCompare(b))) {
		if (kind !== row.type) {
			problems.push(`${name}: listed as ${row.type} but the code calls it as ${kind}.`);
		}
	}
}
for (const [name, row] of listed) {
	if (!isHookName(name) || !STATUSES.includes(row.status) || inCode(name)) {
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
// "major.minor" of a release tag, or null for any other tag.
function minorKey(tag) {
	const v = versionParts(tag);
	return v ? `${v[0]}.${v[1]}` : null;
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
	// Distinct major.minor pairs, newest first (tags are sorted by version):
	// the old release is the newest one two pairs below the latest, so
	// v0.9.x is one minor release before v1.0.0 and v0.8.x two.
	const minors = [...new Set(tags.map(minorKey))];
	const old = tags.find((tag) => minors.indexOf(minorKey(tag)) >= 2);
	const oldFound = old ? hooksIn(phpCalls(old) || '') : null;
	const oldDeprecated = (name) => oldFound !== null && (oldFound.deprecated.has(name) || oldFound.deprecatedPatterns.some((match) => match(name)));
	const doc = git('show', `${latest}:${DOC}`);
	const before = readList(doc || '', null);
	let released = 0;
	// Rows with another prefix (a copy of the starter's tags) are not this
	// plugin's hooks.
	for (const [name, row] of before) {
		if (row.status !== 'supported' || !isHookName(name)) {
			continue;
		}
		released++;
		if (!inCode(name) && !oldDeprecated(name)) {
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
