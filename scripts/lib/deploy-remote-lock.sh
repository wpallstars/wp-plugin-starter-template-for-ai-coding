#!/usr/bin/env bash
# Part of scripts/lib/deploy-remote.sh (see it for what the remote part does):
# The zip checksum, the per-plugin deploy lock and the checks before the first install.
# Only functions: sourced by deploy-remote.sh, or bundled with it by
# deploy-sites.sh, never run alone. Its variables are set in deploy-remote.sh.
#
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Marcus Quinn
# Additional terms (GPL-3.0 section 7(b)): ATTRIBUTION.txt
# Provenance: wpas-e4502af0f07e8a92. Copies, even of part, keep these lines.
# shellcheck disable=SC2034,SC2153 # globals are shared across deploy-remote*.sh, which shellcheck reads one file at a time

sha256_of() {
	local file="$1"
	if command -v sha256sum >/dev/null 2>&1; then
		sha256sum "$file" | awk '{print $1}'
	elif command -v shasum >/dev/null 2>&1; then
		shasum -a 256 "$file" | awk '{print $1}'
	else
		return 1
	fi
	return 0
}

# The host's per-plugin deploy lock: ~/.SLUG-deploy/.lock, made with mkdir
# (atomic everywhere, unlike flock, which shared hosts may lack), with an
# owner file inside: pid, tag, started and parent, one key=value per line.
lock_path() {
	printf '%s/.%s-deploy/.lock' "$HOME" "$SLUG"
	return 0
}

lock_field() {
	local dir="$1"
	local key="$2"
	[[ -f "$dir/owner" ]] || return 0
	awk -v k="$key" 'index($0, k "=") == 1 { print substr($0, length(k) + 2); exit }' "$dir/owner" 2>/dev/null
	return 0
}

lock_holder() {
	local dir="$1"
	local tag started parent pid
	tag="$(lock_field "$dir" tag)"
	started="$(lock_field "$dir" started)"
	parent="$(lock_field "$dir" parent)"
	pid="$(lock_field "$dir" pid)"
	printf 'tag %s, started %s, parent %s, PID %s' "${tag:-?}" "${started:-?}" "${parent:-?}" "${pid:-?}"
	return 0
}

# Whether the lock's run is still going: its PID runs a command line that
# contains deploy-remote (so a PID reused by another command does not keep
# the lock; one reused by another deploy-remote run would), or, where ps -p
# fails (no ps, BusyBox ps, no readable process table), kill -0 finds it. A
# lock with no owner file yet is being taken: live for its first two minutes.
lock_live() {
	local dir="$1"
	local pid args
	pid="$(lock_field "$dir" pid)"
	if [[ -z "$pid" ]]; then
		[[ -n "$(find "$dir" -maxdepth 0 -mmin -2 2>/dev/null)" ]] || return 1
		return 0
	fi
	[[ "$pid" =~ ^[0-9]+$ ]] || return 1
	if command -v ps >/dev/null 2>&1 && args="$(ps -p "$pid" -o args= 2>/dev/null)"; then
		[[ "$args" == *deploy-remote* ]] || return 1
		return 0
	fi
	kill -0 "$pid" 2>/dev/null || return 1
	return 0
}

# Remove a stale lock only if it is still the one judged stale. Takeovers
# take turns under a second lock (DIR.takeover, made with mkdir), so a run
# cannot move a lock another takeover has just made. Under it the lock's
# PID and liveness are read again, the lock is moved aside (atomic) and its
# PID is compared once more; a lock that is not the stale one is put back.
# A takeover lock more than a minute old (find -mmin +1; GNU find counts
# whole minutes, so up to two) is from a run that died during its
# takeover, which takes a moment, and is removed.
lock_break() {
	local dir="$1"
	local stale_pid="$2"
	local guard="$dir.takeover"
	local moved="$dir.stale.$$"
	local tries=0
	until mkdir "$guard" 2>/dev/null; do
		tries=$((tries + 1))
		[[ "$tries" -le 10 ]] || return 0
		if [[ -n "$(find "$guard" -maxdepth 0 -mmin +1 2>/dev/null)" ]]; then
			rmdir "$guard" 2>/dev/null || true
		else
			sleep 1
		fi
	done
	if [[ -d "$dir" && "$(lock_field "$dir" pid)" == "$stale_pid" ]] && ! lock_live "$dir" &&
		mv "$dir" "$moved" 2>/dev/null; then
		if [[ "$(lock_field "$moved" pid)" == "$stale_pid" ]]; then
			rm -rf "$moved"
		elif [[ -e "$dir" ]] || ! mv "$moved" "$dir" 2>/dev/null; then
			say "deploy-remote: WARN a lock taken during the takeover was moved to $moved; remove it once no deploy of $SLUG runs"
		fi
	fi
	rmdir "$guard" 2>/dev/null || true
	return 0
}

# Takes the lock for this apply run, or says who holds it. Returns 3 when
# another run holds it, 2 when the lock cannot be made.
lock_take() {
	local tag="$1"
	local parent="$2"
	local dir pid tries=0
	dir="$(lock_path)"
	if ! mkdir -p "$(dirname "$dir")"; then
		say "deploy-remote: cannot make $(dirname "$dir"); nothing installed"
		return 2
	fi
	while [[ "$tries" -lt 3 ]]; do
		tries=$((tries + 1))
		if mkdir "$dir" 2>/dev/null; then
			if ! printf 'pid=%s\ntag=%s\nstarted=%s\nparent=%s\n' "$$" "$tag" \
				"$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$(printf '%s' "$parent" | tr '\n' ' ')" >"$dir/owner" 2>/dev/null; then
				# The redirect may have made a partial owner file (a full disk).
				# Remove the lock only while its owner file names this run: an
				# empty or missing one may already be a replacement run's lock
				# (this run's was taken over as stale while it was paused), so it
				# is left to be taken over once two minutes old.
				if [[ "$(lock_field "$dir" pid)" == "$$" ]]; then
					rm -f "$dir/owner"
					rmdir "$dir" 2>/dev/null || true
					say "deploy-remote: cannot write the deploy lock's owner file $dir/owner; nothing installed"
				else
					say "deploy-remote: cannot write the deploy lock's owner file $dir/owner; nothing installed. The lock is left in place; a run in two minutes takes it over if it is not another run's."
				fi
				return 2
			fi
			if [[ "$(lock_field "$dir" pid)" != "$$" ]]; then
				say "deploy-remote: lost the deploy lock $dir while taking it; nothing installed"
				return 3
			fi
			LOCK_DIR="$dir"
			trap lock_release EXIT
			trap 'exit 129' HUP
			trap 'exit 130' INT
			trap 'exit 143' TERM
			return 0
		fi
		# Gone since mkdir failed: another run's takeover; try again.
		[[ -d "$dir" ]] || continue
		if lock_live "$dir"; then
			if [[ -z "$(lock_field "$dir" pid)" ]]; then
				say "deploy-remote: the deploy lock $dir has no owner yet: another run is taking it, or one could not write its owner file; nothing installed. Run again in two minutes, when a lock with no owner is taken over."
			else
				say "deploy-remote: another deploy of $SLUG is running on this host ($(lock_holder "$dir")); nothing installed. Wait for it to finish, then run again."
			fi
			return 3
		fi
		pid="$(lock_field "$dir" pid)"
		say "deploy-remote: WARN taking over a stale deploy lock ($(lock_holder "$dir")): that run is no longer running"
		lock_break "$dir" "$pid"
	done
	if [[ ! -d "$dir" ]]; then
		say "deploy-remote: cannot make the deploy lock $dir; nothing installed"
		return 2
	fi
	say "deploy-remote: could not take the deploy lock $dir after 3 tries; nothing installed"
	return 3
}

# Another plugin's deploy on this host (GH#761). Every plugin made from the
# starter keeps its lock at ~/.SLUG-deploy/.lock, so without this two
# plugins' roll-outs could run at once on one shared account and push it past
# its process limit (the host then kills WP-CLI with 137). Returns 3, naming
# the first other lock that lock_live finds live. Other plugins' locks are
# only read: a stale one is ignored, never removed or taken over. Checked
# before this run takes its own lock, so two runs starting in the same
# second may both pass; it stops the common case of one roll-out starting
# while another is mid-way.
other_plugin_deploy() {
	local own dir other
	own="$(lock_path)"
	for dir in "$HOME"/.*-deploy/.lock; do
		[[ -d "$dir" && "$dir" != "$own" ]] || continue
		lock_live "$dir" || continue
		other="${dir%/.lock}"
		other="${other##*/.}"
		other="${other%-deploy}"
		if [[ -z "$(lock_field "$dir" pid)" ]]; then
			say "deploy-remote: another plugin's deploy is starting on this host ($other: its lock $dir has no owner yet); nothing installed. Wait for it to finish, then run again."
		else
			say "deploy-remote: another plugin's deploy is running on this host ($other, $(lock_holder "$dir")); nothing installed. Wait for it to finish, then run again."
		fi
		return 3
	done
	return 0
}

# On exit: remove the lock, but only while it is still this run's.
lock_release() {
	if [[ -n "$LOCK_DIR" && "$(lock_field "$LOCK_DIR" pid)" == "$$" ]]; then
		rm -rf "$LOCK_DIR"
	fi
	LOCK_DIR=""
	return 0
}

# Dry run: say when an apply run is active; it takes no lock.
lock_report() {
	local dir
	dir="$(lock_path)"
	[[ -d "$dir" ]] || return 0
	if lock_live "$dir" && [[ -z "$(lock_field "$dir" pid)" ]]; then
		say "A deploy lock of $SLUG with no owner yet is on this host ($dir): another run is taking it, or one could not write its owner file. --apply stops until it is two minutes old, then takes it over."
	elif lock_live "$dir"; then
		say "A deploy of $SLUG is running on this host ($(lock_holder "$dir")); --apply stops until it ends."
	else
		say "A stale deploy lock of $SLUG is on this host ($(lock_holder "$dir")); --apply will take it over."
	fi
	return 0
}

# apply's checks before the first install: the web PHP log setting, the
# zip's SHA-256 on this host, the backup folder, other plugins' deploys
# (unless --allow-concurrent-plugins), then this plugin's lock. Returns 2 or
# 3 as main does, with nothing installed.
apply_start() {
	local want="$1"
	local zip="$2"
	local sha="$3"
	local backups="$4"
	local parent="$5"
	if [[ -z "$WEB_ERROR_LOG" || "$WEB_ERROR_LOG" == "syslog" ]]; then
		say "deploy-remote: apply requires DEPLOY_WEB_ERROR_LOG, the verified web PHP log file; nothing installed"
		return 2
	fi
	if [[ "$(sha256_of "$zip" || true)" != "$sha" ]]; then
		say "deploy-remote: the zip's SHA-256 on this host is not $sha; nothing installed"
		return 2
	fi
	say "zip SHA-256 on the host: ok"
	if ! mkdir -p "$backups" || ! chmod 700 "$backups"; then
		say "deploy-remote: cannot make the backup folder $backups"
		return 2
	fi
	if [[ "$ALLOW_CONCURRENT" -eq 0 ]]; then
		other_plugin_deploy || return $?
	fi
	lock_take "v$want" "$parent" || return $?
	return 0
}
