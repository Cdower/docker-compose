#!/usr/bin/env bash
# Store a GitHub Actions runner registration token in the Ubuntu Secret Service
# (libsecret / gnome-keyring) — the system "device keychain".
#
# Get the token from:
#   GitHub > (repo or org) Settings > Actions > Runners > New self-hosted runner
# It is short-lived (expires ~1h), but config.sh only needs it once: after the
# runner registers, the persisted .credentials keep it connected. Re-run this and
# `runner-up-linux.sh` whenever you need to (re)register.
#
# Requirements on Ubuntu Server 26.04 (headless):
#   sudo apt-get install -y libsecret-tools gnome-keyring
# A Secret Service provider must be running and unlocked for this user — see the
# project README ("Linux x86 — token in the keychain") for the headless setup.
set -euo pipefail

SERVICE="${RUNNER_TOKEN_KEYCHAIN_SERVICE:-github-actions-runner-token}"

command -v secret-tool >/dev/null 2>&1 || {
  echo "secret-tool not found. Install it with: sudo apt-get install -y libsecret-tools" >&2
  exit 1
}

echo "Storing the runner token in the Secret Service (service='${SERVICE}', account='${USER}')."
# secret-tool prompts for the secret value itself (read from the tty, not argv).
secret-tool store --label="GitHub Actions runner token" \
  service "${SERVICE}" account "${USER}"

echo "Stored. Verify with: secret-tool lookup service \"${SERVICE}\" account \"${USER}\""
