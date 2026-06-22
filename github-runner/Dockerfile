# syntax=docker/dockerfile:1

# GitHub Actions self-hosted runner.
#
# One Dockerfile, two architectures. Docker Desktop on Apple Silicon and an x86
# Ubuntu server both run *Linux* containers, so the only difference is the build
# platform. The compose files set `platform:` (linux/arm64 vs linux/amd64);
# BuildKit then fills in TARGETARCH, which we map to the runner's own arch
# naming (amd64 -> x64, arm64 -> arm64).
FROM ubuntu:26.04

# TARGETARCH is provided automatically by BuildKit when a platform is selected.
ARG TARGETARCH
# Pin a runner version, or leave "latest" to resolve the newest release at build.
ARG RUNNER_VERSION=latest
# Tiny "step-down-from-root" helper so the runner never runs as root.
ARG GOSU_VERSION=1.17

ENV DEBIAN_FRONTEND=noninteractive

# Base tooling the runner bootstrap + most jobs expect. installdependencies.sh
# (run below) pulls in the runtime libs (libicu, liblttng-ust, libkrb5, …).
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      ca-certificates \
      curl \
      tar \
      gzip \
      jq \
      git \
      sudo \
      procps \
      lsb-release \
 && rm -rf /var/lib/apt/lists/*

# Docker CLI (+ buildx & compose plugins) so workflow steps can run Docker
# ("docker-in-job"). The daemon is NOT installed: at runtime the compose files
# mount the host's Docker socket (docker-out-of-docker). Set INSTALL_DOCKER_CLI=
# false to slim the image if your jobs never touch Docker.
ARG INSTALL_DOCKER_CLI=true
# Override if Docker's apt repo does not yet publish your Ubuntu codename.
ARG DOCKER_APT_CODENAME=
RUN if [ "${INSTALL_DOCKER_CLI}" = "true" ]; then \
      set -eux; \
      install -m 0755 -d /etc/apt/keyrings; \
      curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc; \
      chmod a+r /etc/apt/keyrings/docker.asc; \
      . /etc/os-release; \
      CODENAME="${DOCKER_APT_CODENAME:-${VERSION_CODENAME}}"; \
      # Docker publishes one repo per Ubuntu release. If this brand-new release \
      # is not published yet, fall back to the latest LTS (its CLI runs fine on \
      # newer Ubuntu) so the build still succeeds. \
      if ! curl -fsSL -o /dev/null "https://download.docker.com/linux/ubuntu/dists/${CODENAME}/Release"; then \
        echo "Docker apt repo has no '${CODENAME}' dist yet; falling back to 'noble'"; \
        CODENAME=noble; \
      fi; \
      echo "deb [arch=${TARGETARCH} signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu ${CODENAME} stable" \
        > /etc/apt/sources.list.d/docker.list; \
      apt-get update; \
      apt-get install -y --no-install-recommends \
        docker-ce-cli docker-buildx-plugin docker-compose-plugin; \
      rm -rf /var/lib/apt/lists/*; \
    fi

# gosu: download the prebuilt binary for this arch (no dead keyservers).
RUN curl -fsSL -o /usr/local/bin/gosu \
      "https://github.com/tianon/gosu/releases/download/${GOSU_VERSION}/gosu-${TARGETARCH}" \
 && chmod +x /usr/local/bin/gosu \
 && gosu --version

# Unprivileged account the runner actually executes under.
RUN useradd --create-home --shell /bin/bash runner

# Stage the runner binaries in the image. At runtime entrypoint.sh copies these
# into the *persistent* /runner volume on first boot (see entrypoint.sh), so the
# image stays the source of truth for binaries while config + work persist.
WORKDIR /opt/actions-runner
RUN set -eux; \
    case "${TARGETARCH}" in \
      amd64) RUNNER_ARCH=x64 ;; \
      arm64) RUNNER_ARCH=arm64 ;; \
      *) echo "Unsupported TARGETARCH='${TARGETARCH}' (need amd64 or arm64; build with BuildKit + a platform)" >&2; exit 1 ;; \
    esac; \
    VERSION="${RUNNER_VERSION}"; \
    if [ "${VERSION}" = "latest" ]; then \
      VERSION="$(curl -fsSL https://api.github.com/repos/actions/runner/releases/latest | jq -r '.tag_name' | sed 's/^v//')"; \
    fi; \
    echo "Installing actions-runner ${VERSION} for linux-${RUNNER_ARCH}"; \
    curl -fsSL -o runner.tar.gz \
      "https://github.com/actions/runner/releases/download/v${VERSION}/actions-runner-linux-${RUNNER_ARCH}-${VERSION}.tar.gz"; \
    tar xzf runner.tar.gz && rm runner.tar.gz; \
    ./bin/installdependencies.sh; \
    chown -R runner:runner /opt/actions-runner

COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

# Persisted runner directory: config.sh output (.runner/.credentials/_diag) + _work.
ENV RUNNER_DIR=/runner
VOLUME ["/runner"]
WORKDIR /runner

# Runs as root so it can fix volume ownership, then drops to `runner` via gosu.
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
