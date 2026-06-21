#!/usr/bin/env bash
# Read the runner token from the macOS Keychain, then bring the runner up.
#
#   ./scripts/runner-up-macos.sh                # build + up -d
#   ./scripts/runner-up-macos.sh logs -f        # any docker compose subcommand
#   ./scripts/runner-up-macos.sh down           # stop (keeps the persisted volume)
#
# The token is exported only into this process's environment for the compose call
# (never written to disk). Non-secret settings come from ../.env.
set -euo pipefail

cd "$(dirname "$0")/.."

# Load non-secret config so RUNNER_TOKEN_KEYCHAIN_SERVICE (if customized) applies.
if [ -f .env ]; then set -a; . ./.env; set +a; fi
SERVICE="${RUNNER_TOKEN_KEYCHAIN_SERVICE:-github-actions-runner-token}"

RUNNER_TOKEN="$(security find-generic-password -a "${USER}" -s "${SERVICE}" -w 2>/dev/null)" || {
  echo "No token found in the macOS Keychain for service='${SERVICE}'." >&2
  echo "Store one first: ./scripts/store-token-macos.sh" >&2
  exit 1
}
export RUNNER_TOKEN

# Default to a build + detached up; pass through anything the caller provides.
if [ "$#" -eq 0 ]; then set -- up -d --build; fi
exec docker compose -f docker-compose.macos-arm64.yml "$@"
