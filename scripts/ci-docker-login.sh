#!/usr/bin/env bash
# CI's optional Docker Hub login, in a Docker config of the job's own:
#   ci-docker-login.sh login    (DOCKERHUB_USERNAME, DOCKERHUB_TOKEN)
#   ci-docker-login.sh logout   (DOCKER_CONFIG: the login step's config output)
#
# The job's config is the runner's own (context, proxies and the like) less
# its credential settings, with an empty Docker Hub entry and links to the
# runner's contexts/ and cli-plugins/. Docker picks the host's credential
# helper (pass, secretservice) for a config that holds no auth at all; the
# entry keeps the login in the job's own file instead, so neither login nor
# logout can reach the runner's credentials or another job's. Only a login
# that worked is used and later removed.
#
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Marcus Quinn
# Additional terms (GPL-3.0 section 7(b)): ATTRIBUTION.txt
# Provenance: wpas-e4502af0f07e8a92. Copies, even of part, keep these lines.

set -euo pipefail

readonly HUB='https://index.docker.io/v1/'

# Writes the job's config into $2 from the runner's config folder $1. Fails
# unless the result holds the Docker Hub entry: an empty or broken copy would
# hold no auth, which brings back the host's credential helper.
make_config() {
	local source="$1"
	local dir="$2"
	local entry
	if [[ -d "$source" ]]; then
		# Absolute, so the links below resolve from the job's folder.
		source="$(cd "$source" && pwd -P)" || return 1
	fi
	if [[ -f "$source/config.json" ]]; then
		command -v jq >/dev/null 2>&1 || return 1
		jq -e --arg hub "$HUB" \
			'if type == "object" then del(.auths, .credsStore, .credHelpers) | .auths = {($hub): {}} else error("not an object") end' \
			"$source/config.json" >"$dir/config.json" || return 1
		jq -e --arg hub "$HUB" '.auths[$hub] == {} and .credsStore == null and .credHelpers == null' \
			"$dir/config.json" >/dev/null || return 1
	else
		printf '{"auths": {"%s": {}}}\n' "$HUB" >"$dir/config.json" || return 1
		grep -qF "\"$HUB\"" "$dir/config.json" || return 1
	fi
	for entry in contexts cli-plugins; do
		if [[ -e "$source/$entry" ]]; then
			ln -s "$source/$entry" "$dir/$entry" || return 1
		fi
	done
	return 0
}

login() {
	local source="${DOCKER_CONFIG:-$HOME/.docker}"
	local dir
	if [[ -z "${DOCKERHUB_USERNAME:-}" || -z "${DOCKERHUB_TOKEN:-}" ]]; then
		printf 'Docker Hub credentials absent; skipping the optional login.\n'
		return 0
	fi
	dir="$(mktemp -d "${RUNNER_TEMP:?}/docker-auth.XXXXXX")"
	if ! make_config "$source" "$dir"; then
		rm -rf "$dir"
		printf '::warning::Could not copy the runner'"'"'s Docker config (jq is needed when it has one); skipping the optional Docker Hub login; pulls use the runner'"'"'s own Docker config.\n'
		return 0
	fi
	if ! printf '%s' "$DOCKERHUB_TOKEN" |
		DOCKER_CONFIG="$dir" docker login --username "$DOCKERHUB_USERNAME" --password-stdin; then
		rm -rf "$dir"
		printf '::warning::Optional Docker Hub login failed; pulls use the runner'"'"'s own Docker config.\n'
		return 0
	fi
	printf 'config=%s\n' "$dir" >>"${GITHUB_OUTPUT:?}"
	printf 'DOCKER_CONFIG=%s\n' "$dir" >>"${GITHUB_ENV:?}"
	return 0
}

# The login lives only in the job's config, so removing it logs out. rm -rf
# removes the links to the runner's folders, not what they point to.
logout() {
	local dir="${DOCKER_CONFIG:-}"
	case "$dir" in
	"${RUNNER_TEMP:?}"/docker-auth.*) ;;
	*)
		printf '::warning::Not a Docker config made by this script, left alone: %s\n' "${dir:-(none)}"
		return 0
		;;
	esac
	rm -rf "$dir"
	printf 'Logged out of Docker Hub (removed the job'"'"'s Docker config).\n'
	return 0
}

case "${1:-}" in
login) login ;;
logout) logout ;;
*)
	printf 'Usage: %s login|logout\n' "$0" >&2
	exit 2
	;;
esac
