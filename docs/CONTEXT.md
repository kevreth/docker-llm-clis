# Docker — Current Context

> **Scope**: `docker/` repository only. This directory is self-contained and no longer references sibling directories.  
> **Last updated**: 2026-05-03

---

## 1. Purpose

`docker-llm-cli` — a distributable container that bundles LLM CLIs with full permissions in an isolated environment.

---

## 2. File Structure

```
docker/
├── Dockerfile                  # Online build — self-contained, fetches from internet (default)
├── Dockerfile.offline           # Offline build — uses staged artifacts (air-gapped/reproducible)
├── docker-compose.yml           # Compose service; self-contained build context
├── Makefile                     # Build orchestration, version extraction, drift detection
├── run.sh                       # Bundle exporter — saves image + export/ into tarball
├── docker-llm-cli.env           # Runtime env file (gitignored; copy from export/docker-llm-cli.env)
├── aliases.sh                   # Shell aliases baked into image at /etc/profile.d/aliases.sh
├── entrypoint.sh                # Seeds $HOME from .seed/ then execs $@
├── motd                         # Message-of-the-day displayed at login
├── versions.yml                 # Self-contained manifest of dependency versions
├── goss.yaml                    # dgoss runtime contract tests
├── tests/
│   └── test_harness.py          # stdlib PTY script for interactive CLI startup validation
├── export/
│   ├── run.sh                   # End-user runtime launcher
│   ├── docker-llm-cli.env       # Env template for distribution
│   └── README.md                # End-user documentation
└── docs/
    ├── PROTOCOL.md              # Development protocol
    ├── REQUIREMENTS.md          # Complete PRD (replaces DECOUPLING.md + handoff_llm_harness_testing.md)
    ├── CONTEXT.md               # This file
    └── BACKLOG.md               # Active/icebox/completed backlog
```

---

## 3. Build Modes

### 3.1 Online Mode (default)

Builds directly from the internet. No sibling repositories required. Ideal for DockerHub and CI/CD.

```bash
make build        # Online build (default)
```

The Dockerfile fetches:
- APT packages via `apt-get` (version pins stripped from `versions.yml`)
- NPM packages via `npm install -g`
- Scripts (`claude`, `yarn`, `gh`, `copilot`) via `curl`
- Python tools (`kimi`, `mistral`) via `uv tool install`

### 3.2 Offline Mode

Uses pre-fetched artifacts for reproducible, air-gapped builds.

```bash
make all          # Destroys, rebuilds offline, runs tests — canonical CI path
```

Or manually:
```bash
make build DOCKERFILE=Dockerfile.offline
make test
```

The Makefile reads versions from `$(ARTIARY_DATA_DIR)/versions.yml` (default `~/.local/share/artiary/versions.yml`), verifies the frozen base image tar and all `.deb` artifacts exist, loads the base image, and builds with `--pull never`.

**`make all` is the only valid way to build and test for offline validation.** `docker build` and `make build` alone must not be used for final validation because they bypass the offline package repository.

---

## 4. End-User Setup (distributed tarball)

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

`export/run.sh` enforces that `docker-llm-cli.env` has `600` permissions before sourcing it.

---

## 5. Developer Commands

```bash
make all                          # Full offline build + test cycle
make build                        # Build (online or via DOCKERFILE=...)
make build DOCKERFILE=Dockerfile.offline   # Offline build
make test                         # Run dgoss validation tests
make check-sync                   # Verify Dockerfile tail sections match
make destroy                      # Stop container and remove volumes
make exec                         # Attach to running container via bash
make clean                        # Destroy container, image, prune system
make export                       # Run bundle exporter (repo root run.sh)
```

---

## 6. Key Details

- Container runs as user `llm` (UID 1000) with sudo access; username is a build ARG (`CONTAINER_USER=llm`)
- `/workspace` is a bind mount to `WORKSPACE_DIR` on the host — edits are visible from both sides
- `/artifacts` is a named Docker volume (`docker-llm-cli-artifacts`)
- `/home/llm` is a named Docker volume (`docker-llm-cli-home`); seeded from `/home/llm.seed/` on every start via `entrypoint.sh`
- SSH agent socket is forwarded for git operations inside the container
- The `docker/` directory is self-contained; it no longer references sibling directories
- Both Dockerfiles share a common tail section drift-guarded by `make check-sync`
- `test_harness.py` uses **only Python stdlib** (pty, select, fcntl, termios, struct, os, signal, sys, time)
- `goss.yaml` tests include both static contract checks and interactive PTY-based harness tests for `opencode` and `kilo`

---

## 7. Bundled Tools (as of current `goss.yaml`)

| Tool | Binary | Location |
|------|--------|----------|
| Claude Code | `claude` | `/home/llm/.local/bin/` |
| GitHub Copilot | `copilot` | `/home/llm/.local/bin/` |
| GitHub CLI | `gh` | `/home/llm/.local/bin/` |
| OpenAI Codex | `codex` | `/opt/npm-global/bin/` |
| Google Gemini | `gemini` | `/opt/npm-global/bin/` |
| Charm Crush | `crush` | `/opt/npm-global/bin/` |
| Alibaba Qwen | `qwen` | `/opt/npm-global/lib/node_modules/@qwen-code/qwen-code/` |
| OpenCode | `opencode` / `oc` | `/opt/npm-global/bin/` |
| Kilo | `kilo` | `/opt/npm-global/bin/` |
| Goose | `goose` | `/home/llm/.local/bin/` |
| Factory Droid | `factory-droid` / `droid` | `/home/llm/.local/bin/` |
| Kimi | `kimi` | `/home/llm/.local/bin/` (symlink) |
| Mistral Vibe | `vibe` | `/home/llm/.local/bin/` (symlink) |
| Yarn | `yarn` | `/home/llm/.local/bin/` |
| jq | `jq` | system |
| yq | `yq` | system |
| fd | `fd` | `/usr/local/bin/fd` → `/usr/bin/fdfind` |

---

## 8. Decoupling Status

The `docker/` repo is fully decoupled from `artiary/`:

- No `COPY artiary/...` references in any Dockerfile
- `docker-compose.yml` uses `context: .` (not `context: ..`)
- No `../` paths in Dockerfile, Dockerfile.offline, or docker-compose.yml
- Offline builds use Docker `additional_contexts` (`artiary_artifacts`, `artiary_data`) rather than filesystem traversal
- A self-contained `versions.yml` copy lives in `docker/`

Verification:
```bash
grep -r "artiary/" Dockerfile Dockerfile.offline docker-compose.yml  # should be empty
grep -r "\.\./" Dockerfile Dockerfile.offline docker-compose.yml     # should be empty
make check-sync                                                     # should pass
```
