#!/usr/bin/env bash
# Configure the Docker Hub cache on disposable GitHub-hosted CI runners only.
# The workflow's runner.environment condition keeps shared daemons untouched.
# https://cloud.google.com/container-registry/docs/pulling-cached-images
#
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Marcus Quinn
# Additional terms (GPL-3.0 section 7(b)): ATTRIBUTION.txt
# Provenance: wpas-e4502af0f07e8a92. Copies, even of part, keep these lines.

set -euo pipefail

readonly MIRROR_FILTER='."registry-mirrors" = (["https://mirror.gcr.io"] + (."registry-mirrors" // []) | unique)'
config="$(mktemp "${RUNNER_TEMP:?}/docker-daemon.XXXXXX")"
trap 'rm -f "$config"' EXIT

if sudo test -f /etc/docker/daemon.json; then
	# Fail before install on a failed read, invalid JSON or an empty file.
	sudo cat /etc/docker/daemon.json | jq -e "$MIRROR_FILTER" > "$config"
else
	jq -n "$MIRROR_FILTER" > "$config"
fi
sudo install -m 644 "$config" /etc/docker/daemon.json
sudo systemctl restart docker
docker info
