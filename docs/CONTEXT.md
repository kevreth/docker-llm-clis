# Docker

> **Docs Convention**: Read `docs/PROTOCOL.md` if you haven't already in this session.

## Purpose

`docker-llm-cli` — a distributable container that bundles LLM CLIs with full permissions in an isolated environment.

## Files

| File | Purpose |
|------|---------|
| `Dockerfile` | Online build — self-contained, fetches all dependencies from the internet (default for DockerHub/CI) |
| `Dockerfile.offline` | Offline build — uses pre-fetched artifacts staged into `docker/artifacts/` (air-gapped/reproducible) |
| `docker-compose.yml` | Compose service for local builds; self-contained build context |
| `run.sh` | End-user wrapper script; sources `docker-llm-cli.env` and calls `docker run` |
| `docker-llm-cli.env.example` | Template env file — copy to `docker-llm-cli.env`, fill in values, `chmod 600` |
| `aliases.sh` | Shell aliases baked into the image at `/etc/profile.d/aliases.sh` |
| `Makefile` | Build targets: `verify-artifacts`, `build`, `destroy`, `exec`, `run` |
| `versions.yml` | Self-contained manifest of dependency versions (copied from artiary) |

## Build Modes

### Online Mode (default)

Builds directly from the internet. No sibling repositories required. Ideal for DockerHub and CI/CD.

```bash
make build        # Online build (default)
```

The Dockerfile fetches:
- APT packages via `apt-get`
- NPM packages via `npm install -g`
- Scripts (`claude`, `yarn`, `copilot`) via `curl`
- Python tools (`kimi`, `mistral`) via `uv tool install`

### Offline Mode

Uses pre-fetched artifacts from artiary for reproducible, air-gapped builds.

```bash
# Stage artiary artifacts into the docker build context
make stage-artifacts ARTIFACTS=../artiary/artifacts
# Or copy/link them manually to docker/artifacts/

# Build offline
make build DOCKERFILE=Dockerfile.offline
```

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
make build DOCKERFILE=Dockerfile          # Online build (default)
make build DOCKERFILE=Dockerfile.offline # Offline build using staged artifacts
make destroy                     # Stop container and remove volumes
make exec                        # Attach to running container via bash
make run                         # Run container via run.sh
make test                        # Run dgoss validation tests
```

## Build Process

1. `make verify-artifacts` checks prerequisites (skips artifact checks in online mode)
2. `docker compose build` builds the image with `--pull never` in offline mode
3. Compose starts the container with the appropriate environment

## Key Details

- Container runs as user `llm` (UID 1000) with sudo access; username is a build ARG (`CONTAINER_USER=llm`)
- `/workspace` is a bind mount to `WORKSPACE_DIR` on the host — edits are visible from both sides
- `/artifacts` is a named Docker volume (`docker-llm-cli-artifacts`)
- SSH agent socket is forwarded for git operations inside the container
- The `docker/` directory is self-contained; it no longer references sibling directories
