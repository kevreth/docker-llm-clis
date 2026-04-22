# Docker

> **Docs Convention**: Read `docs/PROTOCOL.md` if you haven't already in this session.

## Purpose

`docker-llm-cli` — a distributable container that bundles LLM CLIs with full permissions in an isolated environment.

## Files

| File | Purpose |
|------|---------|
| `Dockerfile` | Builds the image using `node:bookworm-slim` base; Linux user renamed to `llm` via `CONTAINER_USER` ARG |
| `docker-compose.yml` | Compose service for local developer builds; reads `WORKSPACE_DIR` from environment |
| `run.sh` | End-user wrapper script; sources `docker-llm-cli.env` and calls `docker run` |
| `docker-llm-cli.env.example` | Template env file — copy to `docker-llm-cli.env`, fill in values, `chmod 600` |
| `aliases.sh` | Shell aliases baked into the image at `/etc/profile.d/aliases.sh` |
| `Makefile` | Build targets: `verify-artifacts`, `build`, `destroy`, `exec`, `run` |

## End-User Setup (distributed tarball)

```bash
# 1. Load the image
docker load -i docker-llm-cli.tar

# 2. Configure your env file
cp docker-llm-cli.env.example docker-llm-cli.env
chmod 600 docker-llm-cli.env
# Edit docker-llm-cli.env: set WORKSPACE_DIR and any API keys

# 3. Run
./run.sh
```

`run.sh` enforces that `docker-llm-cli.env` has `600` permissions before sourcing it.

## Developer Commands

```bash
make build      # Load artifact image, build and start container
make destroy    # Stop container and remove volumes
make exec       # Attach to running container via bash
make run        # Run container via run.sh
```

**Prerequisite:** Run `make artifacts` from the repo root first to populate `artiary/artifacts/`.

## Build Process

1. `make verify-artifacts` checks for `node.tar`, `versions.yml`, and `docker-llm-cli.env`
2. `docker load -i` loads the frozen Node image
3. Compose builds with `--pull never`, passing `NODE_IMAGE` and `YARN_VERSION` from `versions.yml`

## Key Details

- Container runs as user `llm` (UID 1000) with sudo access; username is a build ARG (`CONTAINER_USER=llm`)
- `/workspace` is a bind mount to `WORKSPACE_DIR` on the host — edits are visible from both sides
- `/artifacts` is a named Docker volume (`docker-llm-cli-artifacts`)
- SSH agent socket is forwarded for git operations inside the container
