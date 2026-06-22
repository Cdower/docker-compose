# GitHub Actions self-hosted runner

A [GitHub Actions self-hosted runner](https://docs.github.com/en/actions/hosting-your-own-runners)
packaged as a Docker Compose stack, with one compose file per host platform:

| Compose file                       | Host                              | Container       | Token source (device keychain)            |
|------------------------------------|-----------------------------------|-----------------|-------------------------------------------|
| `docker-compose.macos-arm64.yml`   | macOS, Apple Silicon (arm64)      | `linux/arm64`   | macOS login Keychain (`security`)         |
| `docker-compose.linux-x86.yml`     | Ubuntu Server 26.04, x86 (amd64)  | `linux/amd64`   | Secret Service / libsecret (`secret-tool`)|

Two design points the task calls for:

- **The token comes from the device keychain, never from a file.** The short-lived
  registration token is read from the OS keychain at start time and injected as
  `RUNNER_TOKEN`. It is never written to `.env`, the image, or the repo. The
  `runner-up-*.sh` wrappers do the lookup for you.
- **`config.sh` output is persisted.** Everything `config.sh` writes —
  `.runner`, `.credentials`, `.credentials_rsaparams`, `.env`, `_diag/`, and the
  `_work/` checkout dir — lives in a Docker volume (or a local-disk bind mount),
  so the runner registers **once** and survives restarts and image rebuilds.

> Docker Desktop on a Mac runs *Linux* containers, so the "macOS" runner is a
> `linux/arm64` container. The only macOS-specific part is where the token is
> read from. The same single `Dockerfile` builds both architectures (BuildKit
> `TARGETARCH` → runner arch: `amd64`→`x64`, `arm64`→`arm64`).

## Prerequisites

- Docker Engine / Docker Desktop with BuildKit (the default) and the Compose v2 plugin.
- A repo/org where you can add a runner: **Settings > Actions > Runners > New
  self-hosted runner** — copy the **registration token** shown there.
- **Linux host only:** a Secret Service provider and the `secret-tool` CLI:
  ```bash
  sudo apt-get update && sudo apt-get install -y libsecret-tools gnome-keyring
  ```

## Quick start

```bash
cd github-runner
cp .env.example .env          # set RUNNER_URL (and labels/name if you like)
```

### macOS (Apple Silicon / arm64)

```bash
./scripts/store-token-macos.sh    # paste the registration token -> macOS Keychain
./scripts/runner-up-macos.sh      # reads Keychain -> RUNNER_TOKEN -> build + up -d
```

### Linux x86 (Ubuntu Server 26.04)

```bash
./scripts/store-token-linux.sh    # paste the registration token -> Secret Service
./scripts/runner-up-linux.sh      # reads keychain -> RUNNER_TOKEN -> build + up -d
```

The runner should appear under **Settings > Actions > Runners** within a few
seconds. Target it from a workflow with the labels you configured:

```yaml
jobs:
  build:
    runs-on: [self-hosted, linux, x64]   # or: [self-hosted, macos, arm64]
```

## How the token reaches the runner

Docker Compose can't shell out to a keychain on its own, so the host reads the
secret from the OS keychain and exports it as `RUNNER_TOKEN`. The compose file
then delivers it to the container as a **Docker secret** — mounted as a file at
`/run/secrets/runner_token`, *not* placed in the container environment — so it
never shows up in `docker inspect` or the process environment:

```yaml
secrets:
  runner_token:
    environment: RUNNER_TOKEN     # value comes from the exported env var
```

The wrappers do the keychain read for you:

**macOS** — `scripts/runner-up-macos.sh`:

```bash
RUNNER_TOKEN="$(security find-generic-password -a "$USER" \
    -s github-actions-runner-token -w)" \
  docker compose -f docker-compose.macos-arm64.yml up -d --build
```

**Linux** — `scripts/runner-up-linux.sh`:

```bash
RUNNER_TOKEN="$(secret-tool lookup service github-actions-runner-token \
    account "$USER")" \
  docker compose -f docker-compose.linux-x86.yml up -d --build
```

You can run those one-liners directly; the wrappers just add error messages and
pass through extra `docker compose` arguments. Because the token only needs to be
valid for the initial `config.sh` registration, it can expire afterwards without
affecting an already-registered runner.

### Is there a more Docker-native way to pass the secret?

Two questions hide in there — *how it's delivered* and *where it lives at rest* —
and they have different "most native" answers:

- **Delivery to the container** — the Docker-native mechanism is **Compose
  secrets** (`secrets:` + `/run/secrets/<name>`), which this stack uses. It's
  strictly better than putting the token in `environment:` because the value is
  mounted as a tmpfs file instead of being visible in `docker inspect` and the
  process environment. The secret here is sourced from the `RUNNER_TOKEN` env var
  (`secrets.runner_token.environment`); you could instead point it at a file with
  `file: ./token.txt`, but a plaintext file on disk is exactly what the keychain
  avoids.
- **At rest** — Docker's own managed secret store is **Swarm secrets**
  (`docker secret create`), encrypted in the Raft log and mounted at
  `/run/secrets`. It's the most "Docker-native" place to keep a secret, but it
  requires Swarm mode (`docker swarm init`) and a `secret` declared
  `external: true`. For a single-host runner that's heavier than it's worth, and
  the OS keychain is a better at-rest store than a file either way.
- **Build-time only** — for secrets needed during `docker build` (not our runtime
  token), the native tool is **BuildKit secrets** (`--secret` +
  `RUN --mount=type=secret`), which keep them out of image layers.

So the design here is deliberately a hybrid: **keychain at rest** (your original
ask, and better than a file) + **Compose secret for delivery** (the Docker-native
hand-off). If you run a Swarm, swap the `secrets:` block to an
`external: true` Swarm secret and drop the keychain wrapper.

### Linux x86 — token in the keychain (headless setup)

On a desktop, `secret-tool` "just works" against the logged-in user's keyring.
On a **headless Ubuntu Server**, start an unlocked keyring for the session, e.g.:

```bash
# Unlock (or create) the "login" keyring for this shell, then store the token:
dbus-run-session -- bash -c '
  echo -n "<your-keyring-password>" | gnome-keyring-daemon --unlock --components=secrets
  ./scripts/store-token-linux.sh
  ./scripts/runner-up-linux.sh
'
```

If you manage the runner as a long-running service, run the keyring under the
same user/systemd session that launches Compose so the lookup succeeds. Prefer a
different secret store (e.g. `pass`, HashiCorp Vault)? Point the wrappers at it —
they only need to print the token on stdout.

## Persistence (config.sh output)

The runner directory inside the container is `/runner`, backed by the
`runner-data` named volume:

```yaml
volumes:
  - runner-data:/runner
```

On first boot the entrypoint seeds the runner binaries into the empty volume,
then `config.sh` registers the runner and writes its state there. On every later
start the entrypoint finds `/runner/.runner` and **reuses** it — no
re-registration, no token needed.

**Persist to local disk instead of a Docker volume?** In the compose file,
comment the `runner-data:/runner` line and use a bind mount:

```yaml
volumes:
  - ./_data/runner:/runner       # config.sh output lands in github-runner/_data/runner
```

(`_data/` is git-ignored.)

Inspect the persisted files:

```bash
docker compose -f docker-compose.linux-x86.yml exec runner ls -a /runner
docker volume inspect github-runner_runner-data
```

## Docker-in-job

Workflow steps can run Docker out of the box. The image ships the Docker CLI plus
the `buildx` and `compose` plugins, and the compose files mount the host Docker
daemon socket (**docker-out-of-docker** — the host's daemon does the work, no
nested daemon):

```yaml
volumes:
  - /var/run/docker.sock:/var/run/docker.sock
```

The socket's owning group differs by host (often `0`/root on Docker Desktop,
something like `999` on Linux), so the entrypoint detects its GID at start and
adds the `runner` user to the matching group — no hardcoded `docker` GID. A job
can then just use Docker:

```yaml
steps:
  - run: docker version
  - run: docker build -t myimage .
  - run: docker compose up -d
```

**Disable it** by commenting the `docker.sock` line in the compose file (and, to
also drop the CLI from the image, rebuild with `INSTALL_DOCKER_CLI=false`).

> **Security:** mounting the Docker socket gives jobs root-equivalent control of
> the host's Docker (and therefore the host). Only enable it for trusted repos /
> workflows. If you need isolation for untrusted jobs, run a privileged
> Docker-in-Docker (`docker:dind`) sidecar instead and point the runner at it via
> `DOCKER_HOST=tcp://docker:2376` with TLS — heavier, but the daemon is contained.

## Operations

All commands accept either compose file — swap in the one for your platform.

```bash
# Tail logs
./scripts/runner-up-linux.sh logs -f

# Update the image (the runner also auto-updates itself when GitHub requires it)
./scripts/runner-up-linux.sh build --pull
./scripts/runner-up-linux.sh up -d

# Stop but KEEP the registration + work (the volume survives)
docker compose -f docker-compose.linux-x86.yml down

# Stop and DELETE the persisted runner state (forces a fresh registration)
docker compose -f docker-compose.linux-x86.yml down -v
```

To **unregister cleanly** (remove it from GitHub), exec a removal with a fresh
*remove* token from the Runners page:

```bash
docker compose -f docker-compose.linux-x86.yml exec runner \
  bash -lc 'cd /runner && ./config.sh remove --token <REMOVE_TOKEN>'
```

## Configuration reference (`.env`)

| Variable                        | Default                              | Purpose |
|---------------------------------|--------------------------------------|---------|
| `RUNNER_URL`                    | — (required)                         | Repo/org/enterprise URL to register against. |
| `RUNNER_NAME`                   | container hostname                   | Name shown in the Runners list. |
| `RUNNER_LABELS`                 | platform default (see compose)       | Labels for `runs-on` targeting. |
| `RUNNER_GROUP`                  | `Default`                            | Runner group (org/enterprise). |
| `RUNNER_WORKDIR`                | `_work`                              | Checkout dir under `/runner`. |
| `RUNNER_EXTRA_ARGS`             | —                                    | Extra `config.sh` flags (e.g. `--ephemeral`). |
| `RUNNER_VERSION`                | `latest`                             | Pin a runner version or resolve newest at build. |
| `RUNNER_TOKEN_KEYCHAIN_SERVICE` | `github-actions-runner-token`        | Keychain entry the wrappers read. |
| `RUNNER_TOKEN`                  | — (from keychain, never in `.env`)   | Injected by the wrappers at start. |

## Notes & troubleshooting

- **`RUNNER_TOKEN is empty`** — the keychain lookup returned nothing. Re-run the
  `store-token-*.sh` script and start via the matching `runner-up-*.sh` wrapper.
- **Runner won't re-register after editing labels/name** — `config.sh` runs only
  when `/runner/.runner` is absent. Either `down -v` to reset, or `exec … config.sh
  remove` then bring it up again.
- **`docker: command not found` in a job** — the image was built with
  `INSTALL_DOCKER_CLI=false`, or the `docker.sock` mount is commented out. See
  [Docker-in-job](#docker-in-job).
- **`permission denied` on `/var/run/docker.sock`** — the entrypoint adjusts the
  `runner` group to match the socket at start; if you bind-mount a socket with an
  unusual owner, check the `==> Docker socket … detected` log line.
- **Don't run privileged CI on a runner exposed to untrusted PRs.** Self-hosted
  runners should generally be limited to private repos or trusted workflows, and
  the mounted Docker socket makes this especially important.
