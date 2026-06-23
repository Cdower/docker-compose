#!/usr/bin/env bash
# Pre-job hook (ACTIONS_RUNNER_HOOK_JOB_STARTED): runs as the unprivileged
# `runner` user before the FIRST step of every job — i.e. before
# actions/checkout — and reclaims ownership of the persisted work tree.
#
# WHY THIS EXISTS — root-owned files in _work break the next checkout.
# Jobs that touch Docker run their containers through the daemon as root:
#   - `container:` jobs and their service containers — e.g.
#     .github/workflows/migrations.yml runs in python:3.14-slim with a
#     pgvector service, and
#   - the Claude Code action (.github/workflows/claude.yml), which writes
#     .claude/.launch.json into the checked-out repo.
# With the dind overlay (docker-compose.<platform>.dind.override.yml) that
# daemon shares THIS runner's /runner volume, so every file those root
# processes write under /runner/_work ends up owned by uid 0. The runner is
# the unprivileged `runner` user, so on the next job actions/checkout cannot
# clean the workspace and dies with, e.g.:
#   fatal: Unable to create '.../.git/index.lock': Permission denied
#   File was unable to be removed Error: EACCES ... unlink '.../.claude/.launch.json'
# which then SKIPS setup-uv (it has no `if:`) and surfaces downstream as the
# misleading `uv: command not found` on every later step.
#
# Reclaiming ownership here, before checkout, keeps the work tree cleanable.
# Passwordless sudo for this single chown is granted in the Dockerfile.
set -uo pipefail

RUNNER_DIR="${RUNNER_DIR:-/runner}"
WORK_DIR="${RUNNER_DIR}/${RUNNER_WORKDIR:-_work}"

if [ -d "${WORK_DIR}" ]; then
  echo "==> [job-started] reclaiming ownership of ${WORK_DIR} for the runner user"
  # -n: never prompt. If sudo/chown is unavailable or partially fails, warn but
  # do NOT fail the hook — a non-zero hook exit fails the whole job, and if the
  # tree is still unclean checkout will report the exact offending file itself.
  if ! sudo -n /usr/bin/chown -R runner:runner "${WORK_DIR}"; then
    echo "WARNING: [job-started] could not fully reset ownership of ${WORK_DIR}" >&2
  fi
fi

exit 0
