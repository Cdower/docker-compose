#!/usr/bin/env bash
# Entrypoint for the GitHub Actions self-hosted runner container.
#
# Responsibilities:
#   1. Seed the runner binaries into the persistent /runner volume on first boot.
#   2. Register the runner with `config.sh` exactly once — its output (.runner,
#      .credentials, .credentials_rsaparams, _diag/, _work/) lives in the volume,
#      so later starts reuse it instead of re-registering.
#   3. Drop privileges and exec `run.sh` as the unprivileged `runner` user.
set -euo pipefail

STAGING=/opt/actions-runner
RUNNER_DIR="${RUNNER_DIR:-/runner}"

# Token delivery: prefer the Docker/Compose secret mounted at /run/secrets
# (kept out of the container environment and `docker inspect`); fall back to the
# RUNNER_TOKEN env var for the inline one-liner workflow.
if [ -z "${RUNNER_TOKEN:-}" ] && [ -f /run/secrets/runner_token ]; then
  RUNNER_TOKEN="$(cat /run/secrets/runner_token)"
  export RUNNER_TOKEN
fi

# 1. First boot on a fresh volume: copy the image's runner binaries in.
if [ ! -x "${RUNNER_DIR}/config.sh" ]; then
  echo "==> Seeding runner binaries into ${RUNNER_DIR} (first boot on this volume)"
  mkdir -p "${RUNNER_DIR}"
  cp -a "${STAGING}/." "${RUNNER_DIR}/"
fi

# The runner refuses to run as root; make sure it owns everything it persists.
chown -R runner:runner "${RUNNER_DIR}"

# Docker-in-job: if the host Docker socket is mounted, let `runner` use it by
# matching the socket's owning group (GID varies by host; commonly 0 on Docker
# Desktop, often 999/erratic on Linux — so we detect it instead of hardcoding).
DOCKER_SOCK="${DOCKER_SOCK:-/var/run/docker.sock}"
if [ -S "${DOCKER_SOCK}" ]; then
  DOCKER_GID="$(stat -c '%g' "${DOCKER_SOCK}")"
  if [ "${DOCKER_GID}" = "0" ]; then
    # Socket owned by the root group (e.g. Docker Desktop) — add runner to root.
    usermod -aG root runner
  else
    GROUP_NAME="$(getent group "${DOCKER_GID}" | cut -d: -f1 || true)"
    if [ -z "${GROUP_NAME}" ]; then
      GROUP_NAME=docker
      groupadd -g "${DOCKER_GID}" "${GROUP_NAME}"
    fi
    usermod -aG "${GROUP_NAME}" runner
  fi
  echo "==> Docker socket ${DOCKER_SOCK} detected (gid ${DOCKER_GID}); jobs can run Docker"
fi

cd "${RUNNER_DIR}"

# 2. Configure once. The .runner file is created by config.sh and persisted in
#    the volume, so its presence means "already registered — just reuse it".
if [ ! -f "${RUNNER_DIR}/.runner" ]; then
  : "${RUNNER_URL:?RUNNER_URL is not set — set it in github-runner/.env (e.g. https://github.com/<org>/<repo>)}"
  : "${RUNNER_TOKEN:?RUNNER_TOKEN is empty — the keychain lookup returned nothing. Run scripts/store-token-*.sh once, then start via scripts/runner-up-*.sh}"

  echo "==> Registering runner '${RUNNER_NAME:-$(hostname)}' with ${RUNNER_URL}"
  gosu runner ./config.sh \
    --unattended \
    --url         "${RUNNER_URL}" \
    --token       "${RUNNER_TOKEN}" \
    --name        "${RUNNER_NAME:-$(hostname)}" \
    --labels      "${RUNNER_LABELS:-self-hosted}" \
    --runnergroup "${RUNNER_GROUP:-Default}" \
    --work        "${RUNNER_WORKDIR:-_work}" \
    --replace \
    ${RUNNER_EXTRA_ARGS:-}
else
  echo "==> Found existing ${RUNNER_DIR}/.runner — reusing persisted configuration"
fi

# 3. Hand off to the runner. `exec` keeps it as PID 1's replacement so that
#    `docker stop` delivers SIGTERM straight to it for a graceful, finish-the-
#    current-job shutdown (allow time via stop_grace_period in the compose file).
echo "==> Starting runner"
exec gosu runner ./run.sh
