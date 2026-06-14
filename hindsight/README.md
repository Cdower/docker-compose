# Hindsight

[Hindsight](https://hindsight.vectorize.io) agent-memory stack, packaged to run
with an **external PostgreSQL** container, a **hosted free LLM provider**
(OpenRouter by default), and **local embedding + reranker models** (the full
image's baked-in defaults).

Adapted from the upstream
[`docker/docker-compose`](https://github.com/vectorize-io/hindsight/tree/main/docker/docker-compose)
examples (`external-pg`, `custom-models`, `local-llm`).

## What's in the stack

| Service     | Image                                          | Purpose |
|-------------|------------------------------------------------|---------|
| `db`        | `pgvector/pgvector:pg18`                        | Dedicated PostgreSQL + pgvector (not the embedded pg0). |
| `hindsight` | `ghcr.io/vectorize-io/hindsight:latest` (full) | API (`:8888`) + Control Plane UI (`:9999`). Local embeddings + reranker baked in. |
| `llama`     | `ghcr.io/ggml-org/llama.cpp:server`            | Optional local-LLM sidecar — off unless `--profile local-llm`. |

- **LLM**: hosted, OpenAI-compatible provider. Defaults to OpenRouter; NVIDIA
  NIM, Google Gemini, Groq, and local options are ready to uncomment in
  `.env.example`.
- **Embeddings & reranking**: run locally with the full image's default models
  (`BAAI/bge-small-en-v1.5`, `cross-encoder/ms-marco-MiniLM-L-6-v2`). No config
  needed — the defaults are fine.

## Quick start

```bash
cd hindsight
cp .env.example .env          # set HINDSIGHT_DB_PASSWORD + your LLM API key
docker compose up -d
```

- API: <http://localhost:8888>
- Control Plane UI: <http://localhost:9999>

Smoke test:

```bash
curl -s http://localhost:8888/health
```

## Choosing an LLM provider

Edit `.env` and uncomment the block you want. Defaults to **OpenRouter** — get a
key at <https://openrouter.ai/keys> and pick a current free model (the `:free`
suffix) from <https://openrouter.ai/models>, since the free list changes.
Pre-filled blocks for **NVIDIA NIM**, **Google Gemini**, and **Groq** are in
`.env.example`.

## Local LLM (fully offline)

Keep the local-model path available via the bundled llama.cpp sidecar:

```bash
docker compose --profile local-llm up -d
```

Then uncomment the "Local model via the llama.cpp sidecar" block in `.env`. The
first boot downloads the GGUF (~3.5 GB) into the `llama_models` volume. For
GPU acceleration, switch the `llama` image to `:server-cuda` and uncomment the
`LLAMA_ARG_N_GPU_LAYERS` line and the `deploy` block in `docker-compose.yml`
(needs the NVIDIA Container Toolkit). On CPU, small models are smoke-test only.

You can also point Hindsight at **Ollama on the host** — see that block in
`.env.example`.

## Using a fully managed / remote PostgreSQL

The bundled `db` container already gives you a PostgreSQL separate from the
Hindsight process. To instead use a managed/remote Postgres (RDS, Cloud SQL,
CloudNativePG, ...):

1. Set `HINDSIGHT_API_DATABASE_URL` in `.env` to the full connection string
   (the target must have the `pgvector` extension available; managed databases
   usually need `?sslmode=require`).
2. Stop running the bundled `db`: comment out the `db` service **and** the
   `depends_on:` block under `hindsight` in `docker-compose.yml`, then
   `docker compose up -d`.

`HINDSIGHT_API_DATABASE_URL`, when set, overrides the bundled-DB connection.

## Other PostgreSQL backends (vchord, pgvectorscale, AlloyDB, ...)

This stack uses the default `pgvector` + native full-text search, which is fine
for most use. For VectorChord, Timescale/pgvectorscale, ParadeDB pg_search,
AlloyDB ScaNN, etc., see the upstream
[examples](https://github.com/vectorize-io/hindsight/tree/main/docker/docker-compose)
and set `HINDSIGHT_API_VECTOR_EXTENSION` / `HINDSIGHT_API_TEXT_SEARCH_EXTENSION`.

## Operations

```bash
docker compose logs -f hindsight      # tail logs
docker compose pull && docker compose up -d   # update to the latest image
docker compose down                   # stop (keeps data volumes)
docker compose down -v                # stop and DELETE the database volume
```

Data lives in the `pg_data` (Postgres) and `llama_models` (GGUF cache) named
volumes. Pin a Hindsight version with `HINDSIGHT_VERSION` in `.env` instead of
tracking `latest`.
