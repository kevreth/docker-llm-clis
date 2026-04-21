# Docker

> **Docs Convention**: Read `docs/PROTOCOL.md` if you haven't already in this session.

## Purpose

Docker development environment configuration for the Kev Labs meta-repo.

## Files

| File | Purpose |
|------|---------|
| `Dockerfile` | Multi-stage build using `node:24.4.1-bookworm-slim`; installs apt packages, npm globals, and offline Mistral builder |
| `docker-compose.yml` | Compose service `kev-labs` with volume mounts for workspace, artifacts, SSH agent, and aliases |
| `entrypoint.sh` | Container entrypoint script |
| `aliases.sh` | Shell aliases mounted into container at `/etc/profile.d/aliases.sh` |
| `Makefile` | Build targets: `verify-artifacts`, `build`, `destroy`, `exec` |

## Commands

```bash
make build      # Load artifact image, build and start container
make destroy    # Stop container and remove volumes
make exec       # Enter running container via bash
```

**Prerequisite:** Run `make artifacts` from the repo root first to populate `artiary/artifacts/`.

## Build Process

1. `make verify-artifacts` checks that `artiary/artifacts/images/node.tar` and `artiary/artifacts/manifest/versions.yml` exist
2. `docker load -i` loads the frozen Node image
3. Compose builds with `--pull never`, using `NODE_IMAGE` and `YARN_VERSION` from `versions.yml`

## Key Details

- Container runs as user `node` (UID 1000) with sudo access
- Working directory inside container: `/workspace`
- The host repo is mounted at `/workspace/kev-labs` via `KEV_LABS` env var
- SSH agent socket is forwarded for git operations inside the container
