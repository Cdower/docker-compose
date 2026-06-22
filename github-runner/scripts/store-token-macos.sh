#!/usr/bin/env bash
# Store a GitHub Actions runner registration token in the macOS login Keychain.
#
# Get the token from:
#   GitHub > (repo or org) Settings > Actions > Runners > New self-hosted runner
# It is short-lived (expires ~1h), but config.sh only needs it once: after the
# runner registers, the persisted .credentials keep it connected. Re-run this and
# `runner-up-macos.sh` whenever you need to (re)register.
set -euo pipefail

SERVICE="${RUNNER_TOKEN_KEYCHAIN_SERVICE:-github-actions-runner-token}"

printf 'Paste the runner registration token: '
read -rs TOKEN
echo
[ -n "${TOKEN}" ] || { echo "No token entered — aborting." >&2; exit 1; }

# -U updates the entry if it already exists instead of erroring.
security add-generic-password -a "${USER}" -s "${SERVICE}" -w "${TOKEN}" -U

echo "Stored token in the macOS Keychain (service='${SERVICE}', account='${USER}')."
echo "Verify with: security find-generic-password -a \"${USER}\" -s \"${SERVICE}\" -w"
