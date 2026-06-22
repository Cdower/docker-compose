#!/usr/bin/env bash
# Read the runner token from the Ubuntu Secret Service, then bring the runner up.
#
#   ./scripts/runner-up-linux.sh                # build + up -d
#   ./scripts/runner-up-linux.sh logs -f        # any docker compose subcommand
#   ./scripts/runner-up-linux.sh down           # stop (keeps the persisted volume)
#
# Docker-in-job is opt-in. Set RUNNER_DOCKER_IN_JOB=1 (here or in .env) to layer
# docker-compose.linux-x86.override.yml on top — it mounts the host Docker
# socket and adds the `docker` label:
#
#   RUNNER_DOCKER_IN_JOB=1 ./scripts/runner-up-linux.sh
#
# The token is exported only into this process's environment for the compose call
# (never written to disk). Non-secret settings come from ../.env.
set -euo pipefail

cd "$(dirname "$0")/.."

# Load non-secret config so RUNNER_TOKEN_KEYCHAIN_SERVICE (if customized) applies.
if [ -f .env ]; then set -a; . ./.env; set +a; fi
SERVICE="${RUNNER_TOKEN_KEYCHAIN_SERVICE:-github-actions-runner-token}"

command -v secret-tool >/dev/null 2>&1 || {
  echo "secret-tool not found. Install it with: sudo apt-get install -y libsecret-tools" >&2
  exit 1
}

RUNNER_TOKEN="$(secret-tool lookup service "${SERVICE}" account "${USER}")" || true
[ -n "${RUNNER_TOKEN:-}" ] || {
  echo "No token found in the Secret Service for service='${SERVICE}'." >&2
  echo "Store one first: ./scripts/store-token-linux.sh" >&2
  exit 1
}
export RUNNER_TOKEN

# Compose files: the base, plus the docker-in-job override when opted in. The -f
# flags must precede the subcommand, so build them into an array here.
compose_files=(-f docker-compose.linux-x86.yml)
case "${RUNNER_DOCKER_IN_JOB:-}" in
  1 | true | yes | on)
    compose_files+=(-f docker-compose.linux-x86.override.yml) ;;
esac

# Default to a build + detached up; pass through anything the caller provides.
if [ "$#" -eq 0 ]; then set -- up -d --build; fi
exec docker compose "${compose_files[@]}" "$@"
