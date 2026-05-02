# Product Requirements Document: docker-llm-cli

> **Status**: Active  
> **Scope**: `docker/` repository only — self-contained container distribution of LLM CLI tools  
> **Audience**: Engineers extending the image, adding harnesses, or modifying the build/test pipeline

---

## 1. Overview

`docker-llm-cli` is a distributable Docker image that bundles multiple LLM command-line interfaces into a single, isolated runtime environment. The container runs as an unprivileged user (`llm`, UID 1000) with passwordless sudo, includes a curated shell environment, and is validated by an automated test suite before distribution.

### 1.1 Core Goals

| # | Goal | Rationale |
|---|------|-----------|
| 1 | **Standalone build** | `docker build .` must succeed on DockerHub/CI without sibling repositories or pre-staged artifacts |
| 2 | **Reproducible offline builds** | Air-gapped builds using frozen artifacts must remain possible for deterministic, auditable images |
| 3 | **Interactive harness validation** | Tests must prove that TUI-based CLIs actually start and reach a ready state — not just that binaries exist |
| 4 | **Zero-config distribution** | End users load a tar archive, set an env file, and run `./run.sh` |

---

## 2. Architecture

### 2.1 High-Level Components

```
┌─────────────────────────────────────────────────────────────┐
│                        Host System                          │
│  ┌─────────────┐  ┌──────────────┐  ┌─────────────────────┐ │
│  │  Makefile   │  │ docker-compose│  │  dgoss (test runner)│ │
│  │  run.sh     │  │   .yml       │  │                     │ │
│  └──────┬──────┘  └──────┬───────┘  └──────────┬──────────┘ │
│         │                │                     │            │
│         └────────────────┴─────────────────────┘            │
│                          │                                  │
│                   ┌──────┴──────┐                          │
│                   │ Docker Build │                          │
│                   │   Context   │                          │
│                   └──────┬──────┘                          │
│                          │                                  │
│              ┌───────────┴────────────┐                     │
│              ▼                        ▼                     │
│      ┌──────────────┐       ┌─────────────────┐            │
│      │  Dockerfile  │       │ Dockerfile.offline            │
│      │  (online)    │       │  (offline)      │            │
│      └──────┬───────┘       └────────┬────────┘            │
│             │                        │                      │
│             └───────────┬────────────┘                      │
│                         ▼                                   │
│              ┌─────────────────────┐                        │
│              │  docker-llm-cli     │                        │
│              │  (runtime image)    │                        │
│              └─────────────────────┘                        │
└─────────────────────────────────────────────────────────────┘
```

### 2.2 File Inventory

| File | Purpose |
|------|---------|
| `Dockerfile` | Online build — fetches all dependencies from the internet; default for DockerHub/CI |
| `Dockerfile.offline` | Offline build — uses pre-fetched artifacts staged into `docker/artifacts/` (air-gapped/reproducible) |
| `docker-compose.yml` | Compose service definition; self-contained build context with `additional_contexts` for offline mode |
| `Makefile` | Orchestration: version extraction, artifact verification, build, test, drift detection, bundle export |
| `run.sh` (repo root) | Bundle exporter — saves image, copies `export/` files, creates distributable tarball |
| `run.sh` (`export/`) | End-user runtime launcher — validates env, loads image, starts container |
| `docker-llm-cli.env` / `export/docker-llm-cli.env` | Runtime env file — API keys, workspace dir, SSH forwarding |
| `aliases.sh` | Shell aliases and prompt customization baked into the image at `/etc/profile.d/aliases.sh` |
| `entrypoint.sh` | Container entrypoint — seeds `$HOME` from `.seed/` then `exec`s the requested command |
| `motd` | Message-of-the-day displayed at container login |
| `versions.yml` | Self-contained manifest of dependency versions (copied from artiary) |
| `goss.yaml` | dgoss runtime contract tests — file existence, permissions, version commands, harness startup |
| `tests/test_harness.py` | Python stdlib PTY script for interactive CLI startup validation |
| `export/` | Distribution bundle template — `run.sh`, `docker-llm-cli.env`, `README.md` |

---

## 3. Build System

### 3.1 Dual Dockerfile Strategy

The project uses **two independent, linear Dockerfiles** rather than a single branched file. This avoids conditional `RUN` logic and makes each path independently readable and testable.

**Why this approach:**
- `docker build .` on DockerHub builds `Dockerfile` with **zero configuration**
- Each file is a **complete linear narrative** — no `if [ "$DOCKERFILE" = "..." ]` branches to mentally filter out
- It requires **no extra infrastructure** (no new registries, no base images to publish)
- It makes the `docker/` repo **truly standalone** — clone it anywhere, run `docker build .`, it works
- It **preserves the value of artiary** — offline builds are still fully pinned and reproducible

**Trade-off:** The final setup section (workspace dirs, sudo, aliases, entrypoint) is duplicated across both files (≈20 lines). This is mitigated by `make check-sync` that fails CI if the common sections drift.

#### 3.1.1 `Dockerfile` (Online — Default)

- **Base image**: `node:24-trixie` (configurable via `NODE_IMAGE` build arg)
- **Dependency sources**:
  - APT packages from Debian repos (version pins stripped from `versions.yml`)
  - NPM packages from the npm registry (`npm install -g --prefix /opt/npm-global`)
  - Scripts (`claude`, `yarn`, `gh`, `copilot`) downloaded via `curl`
  - Python tools (`kimi-cli`, `mistral-vibe`) installed via `uv tool install`
- **No artifact references**: The file never copies from `artifacts/` or references sibling directories

**Build args:**
```dockerfile
ARG NODE_IMAGE=node:24-trixie
ARG CONTAINER_USER=llm
ARG YARN_VERSION=4.14.1
ARG CLAUDE_VERSION=2.1.114
ARG YARN_SCRIPT_VERSION=4.14.1
ARG COPILOT_VERSION=1.0.34
ARG GH_VERSION=2.91.0
ARG KIMI_VERSION=1.37.0
ARG MISTRAL_VERSION=2.7.6
```

#### 3.1.2 `Dockerfile.offline` (Offline — Reproducible)

- **Base image**: Same as online, but loaded from a frozen `.tar` file (`docker load -i`)
- **Dependency sources**:
  - APT packages from frozen `.deb` files and apt lists copied from staged artifacts
  - NPM packages from pre-built `.tgz` tarballs extracted to `/opt`
  - Scripts from staged `artifacts/scripts/` directory; versions discovered by parsing `versions.yml` inside the container via awk loops
  - Builders from staged `artifacts/builders/` directory installed via `install.sh`; versions also discovered via awk loops
- **Uses Docker additional build contexts**: `artiary_artifacts` and `artiary_data` passed via `docker-compose.yml`
- **Copies tests into image**: `COPY tests/ /tests/` so that `dgoss` can invoke `test_harness.py`
- **Browser binary aliases**: Moves `links`, `links2`, `lynx` to prevent CLIs from opening text browsers for auth

**Key args:**
```dockerfile
ARG NODE_IMAGE=node:24-trixie
ARG ARTIFACTS_DIR=/tmp/artifacts
ARG YARN_VERSION=4.14.1
```

Only `YARN_VERSION` is needed as an arg because the offline path reads script versions from `versions.yml` via awk. `ARTIFACTS_DIR` defaults to `/tmp/artifacts` because the Dockerfile unconditionally `COPY`s the local `artifacts/` directory there.

### 3.2 Build Orchestration (`Makefile`)

| Target | Purpose |
|--------|---------|
| `all` | **Canonical build+test path**: destroys existing image/container, runs offline build, runs `dgoss` tests. **`make all` is the only valid way to build and test.** It creates the image, creates the container, and runs the tests using an offline package repository — in the correct order with correct configuration. |
| `build` | Verifies artifacts (offline only), loads frozen base image (offline only), runs `docker compose build`, starts container |
| `verify-artifacts` | Offline: checks that `versions.yml`, base image tar, manifest, and all `.deb` files exist. Online: only checks that `export/docker-llm-cli.env` exists |
| `test` | Runs `dgoss run` against the built image |
| `check-sync` | Drift guard — verifies that the common tail section (from last `USER root` to end) is identical in both Dockerfiles |
| `clean` | Destroys container, image, and prunes Docker system |
| `destroy` | Runs `docker compose down --volumes` |
| `exec` | Attaches to running container via `bash` |
| `backup-home` | Tarballs `/home/llm` into `/workspace/.backups/` |
| `export` | Runs `./run.sh` (distribution runtime) |

**Version extraction:**
- The Makefile reads `versions.yml` (local copy for online, artiary copy for offline) using `yq`
- Variables (`NODE_IMAGE`, `YARN_VERSION`, etc.) are `export`ed so `docker-compose.yml` receives them automatically via environment passthrough

**Dockerfile selection:**
```makefile
DOCKERFILE    ?= Dockerfile
```
`?=` allows overriding via command line (`make build DOCKERFILE=Dockerfile.offline`). The default is `Dockerfile` so a fresh clone builds immediately without any artifact setup.

**Build target branches:**
```makefile
build: verify-artifacts
ifeq ($(DOCKERFILE),Dockerfile.offline)
	docker load -i $(NODE_TAR)
	$(COMPOSE) build --pull never
else
	$(COMPOSE) build
endif
```
Offline builds must load the frozen `node.tar` before building. Online builds let Docker pull the base image normally.

### 3.3 Docker Compose Configuration

```yaml
build:
  context: .
  dockerfile: ${DOCKERFILE:-Dockerfile}
  additional_contexts:
    artiary_artifacts: ${ARTIARY_ARTIFACTS:-.}
    artiary_data: ${ARTIARY_DATA_DIR:-.}
  args:
    - NODE_IMAGE
    - YARN_VERSION
    - CLAUDE_VERSION
    - YARN_SCRIPT_VERSION
    - COPILOT_VERSION
    - KIMI_VERSION
    - MISTRAL_VERSION
```

- `context: .` restricts the build to the `docker/` directory — required for DockerHub
- `additional_contexts` provides the named contexts `artiary_artifacts` and `artiary_data` consumed by `Dockerfile.offline` via `COPY --from=...`
- Unused args are silently ignored by Docker, so the same `args:` list works for both Dockerfiles

### 3.4 Drift Guard

Both Dockerfiles share an identical tail section (workspace setup, sudo, aliases, entrypoint). `make check-sync` extracts everything from the last occurrence of `USER root` to EOF in each file and fails if they differ. This is intended to run in CI.

```makefile
check-sync:
	@tail -n +$$(grep -n "^USER root$$" Dockerfile | tail -1 | cut -d: -f1) Dockerfile > /tmp/dockerfile.tail
	@tail -n +$$(grep -n "^USER root$$" Dockerfile.offline | tail -1 | cut -d: -f1) Dockerfile.offline > /tmp/dockerfile-offline.tail
	@diff -q /tmp/dockerfile.tail /tmp/dockerfile-offline.tail || \
	    (echo "ERROR: Common tail sections of Dockerfile and Dockerfile.offline have drifted." && exit 1)
```

---

## 4. Runtime Environment

### 4.1 Container Identity

| Attribute | Value |
|-----------|-------|
| User | `llm` (UID 1000, GID 1000) |
| Home | `/home/llm` |
| Shell | `/bin/bash -l` |
| Sudo | Passwordless `NOPASSWD:ALL` |
| Groups | `sudo` |

The base image (`node:24-trixie`) originally contains a `node` user (UID 1000). The Dockerfiles rename this user to `llm` and adjust the home directory.

### 4.2 Volumes and Mounts

| Path | Type | Purpose |
|------|------|---------|
| `/workspace` | Bind mount (`WORKSPACE_DIR`) | User project directory — editable from both host and container |
| `/artifacts` | Named volume (`docker-llm-cli-artifacts`) | Persistent storage for artifacts between container restarts |
| `/home/llm` | Named volume (`docker-llm-cli-home`) | Persistent home directory (seeded from `.seed/` on first start) |
| `/ssh-agent` | Bind mount (`SSH_AUTH_SOCK`) | SSH agent forwarding for git operations |

### 4.3 Security Profile

- `cap_drop: ALL` — all capabilities removed by default
- `cap_add`: `SETUID`, `SETGID`, `NET_RAW`, `NET_ADMIN`
- `security_opt: no-new-privileges:false`
- `tmpfs` mounts for `/tmp` and `/run`
- `init: true` for proper PID 1 reaping

### 4.4 Environment Variables

The `docker-llm-cli.env` file supports 30+ optional API keys and configuration variables. Only non-empty variables are forwarded into the container. Categories include:

- **LLM Providers**: OpenAI, Anthropic, Google Gemini, Groq, Mistral, Cerebras, MiniMax, Kimi, Z.ai, OpenRouter, io.net, Vercel, Synthetic
- **Cloud Platforms**: AWS Bedrock, Azure OpenAI, Vertex AI
- **Auth/Tokens**: GitHub (`GH_TOKEN`, `CLAUDE_CODE_OAUTH_TOKEN`), Hugging Face (`HF_TOKEN`)
- **Infra**: `WORKSPACE_DIR`, `SSH_AUTH_SOCK`

### 4.5 Shell Environment (`aliases.sh`)

- **PATH**: `/opt/npm-global/bin` prepended; `$HOME/.local/bin` exported
- **Aliases**: All major CLIs are aliased with permissive flags (`--yolo`, `--allow-dangerously-skip-permissions`, `--dangerously-bypass-approvals-and-sandbox`) so they run non-interactively by default
- **Browser aliases**: `links`, `links2`, `lynx` aliased to moved binaries (`lnks`, `lnks2`, `lyx`) to prevent accidental TUI browser launches
- **Prompt**: Custom multi-line `PS1` with git branch, user, host, history number, working directory, and timestamp
- **Colors**: `LS_COLORS` and ANSI color definitions for prompt

### 4.6 Entrypoint Behavior (`entrypoint.sh`)

```bash
cp -a "${HOME}.seed/." "${HOME}/"
exec "$@"
```

On every container start, the entrypoint restores the home directory from a seeded snapshot (`/home/llm.seed/`). This ensures that dotfiles, installed tools, and shell configuration are always present even if the `/home/llm` named volume is empty on first run.

---

## 5. Bundled CLI Tools

The image contains the following LLM and developer CLI tools:

| Tool | Binary | Install Method | Location |
|------|--------|----------------|----------|
| Claude Code | `claude` | curl (script) | `/home/llm/.local/bin/claude` |
| GitHub Copilot | `copilot` | curl (tar.gz) | `/home/llm/.local/bin/copilot` |
| GitHub CLI | `gh` | curl (tar.gz) | `/home/llm/.local/bin/gh` |
| OpenAI Codex | `codex` | npm global | `/opt/npm-global/bin/codex` (symlink) |
| Google Gemini | `gemini` | npm global | `/opt/npm-global/bin/gemini` (symlink) |
| Charm Crush | `crush` | npm global | `/opt/npm-global/bin/crush` (symlink) |
| Alibaba Qwen | `qwen` | npm global | `/opt/npm-global/lib/node_modules/@qwen-code/qwen-code/` |
| OpenCode | `opencode` / `oc` | npm global | `/opt/npm-global/bin/opencode` (symlink) |
| Kilo | `kilo` | npm global | `/opt/npm-global/bin/kilo` (symlink) |
| Goose | `goose` | curl (script) | `/home/llm/.local/bin/goose` |
| Factory Droid | `factory-droid` / `droid` | curl (script) | `/home/llm/.local/bin/factory-droid` |
| Kimi | `kimi` | uv tool | `/home/llm/.local/bin/kimi` (symlink) |
| Mistral Vibe | `vibe` | uv tool | `/home/llm/.local/bin/vibe` (symlink) |
| Yarn | `yarn` | curl (script) | `/home/llm/.local/bin/yarn` |
| jq | `jq` | apt | system |
| yq | `yq` | apt | system |
| fd | `fd` | apt (symlinked) | `/usr/local/bin/fd` → `/usr/bin/fdfind` |

> **Note**: `kilo` is an npm-global alias for an OpenCode-related package and appears in `goss.yaml` tests.

---

## 6. Testing Framework

### 6.1 Philosophy

Testing has two layers:

1. **Runtime Contract Tests** (`goss.yaml`) — static assertions about the filesystem, user configuration, and non-interactive command exit codes
2. **Interactive Harness Tests** (`tests/test_harness.py`) — PTY-based validation that TUI applications start, reach a ready state, and exit cleanly

**Key constraints:**
- **Harnesses are never prompted.** No natural language input is submitted. No LLM inference occurs and no API connection is required.
- **TTY requirements**: Interactive TUI programs need pseudo-terminal allocation to start correctly
- **CI/CD integration**: Must run headlessly

```
┌─────────────────────────────────────────┐
│           dgoss (Test Runner)           │
│  ┌─────────────────────────────────┐    │
│  │      goss.yaml (Contracts)      │    │
│  │  • File existence/permissions   │    │
│  │  • Version command exit codes   │    │
│  └─────────────────────────────────┘    │
│  ┌─────────────────────────────────┐    │
│  │  test_harness.py (Functional)   │    │
│  │  • Spawn harness PTY            │    │
│  │  • Wait for "Tip"               │    │
│  │  • Send /exit, assert exit 0    │    │
│  └─────────────────────────────────┘    │
└─────────────────────────────────────────┘
         ↓
    Docker Container Under Test
```

### 6.2 Runtime Contract Tests (`goss.yaml`)

**User assertions:**
- `llm` user exists with UID 1000, GID 1000, home `/home/llm`, and group `sudo`

**File assertions (existence, type, mode):**
- All binaries listed in section 5
- `/workspace`, `/artifacts`, `/etc/motd`, `/etc/profile.d/aliases.sh`, `/usr/local/bin/entrypoint.sh`
- `/opt/npm-global/lib/node_modules/@qwen-code/qwen-code/package.json`

**Command assertions (exit-status: 0):**
- `node --version`, `npm --version`, `yarn --version`, `python3 --version`, `git --version`, `sudo --version`
- `--version` checks for all major LLM CLIs (with 5s timeouts for slow-starting tools)
- `python3 tests/test_harness.py opencode` (10s timeout)
- `python3 tests/test_harness.py kilo` (30s timeout)

### 6.3 Interactive Harness Test (`tests/test_harness.py`)

A Python 3 stdlib-only script that spawns a binary in a pseudo-terminal and validates its lifecycle.

**Algorithm:**
1. **SPAWN** → Open PTY master/slave pair; set terminal size to 24×80 via `TIOCSWINSZ`
2. **FORK** → Child becomes session leader, redirects stdio to PTY slave, and `execvp`s the binary
3. **WAIT** → Parent reads PTY output, searching for the ready indicator (`READY = b"Tip"`) within `STARTUP_TIMEOUT` (45s)
4. **FAIL** → If "Tip" not seen: SIGKILL, report "timed out waiting for ready state"
5. **SEND** → If ready indicator found, send quit command (`QUIT_CMD = b"/exit\r"`) one byte at a time with `CHAR_DELAY` (5ms) to simulate typing and avoid paste-mode triggers
6. **WAIT** → Drain PTY output continuously while polling for process exit within `QUIT_TIMEOUT` (30s)
7. **FAIL** → If no exit: SIGKILL, report "did not exit after quit"
8. **PASS** → Verify clean exit (`WIFEXITED` with status 0); reject signaled exits or non-zero codes

**Failure modes:**

| Error Type | Behavior |
|------------|----------|
| "Tip" not seen within 45s | SIGKILL, FAIL with "timed out waiting for ready state" |
| Process does not exit within 30s after `/exit` | SIGKILL, FAIL with "did not exit after quit" |
| Process killed by signal | FAIL with signal number |
| Process exits with non-zero code | FAIL with exit code |
| Missing binary | FAIL via existing `goss.yaml` file checks before test runs |

**Interface:**
```bash
python3 tests/test_harness.py [--debug] <binary>
```

**Why PTY instead of `--version`:** Command line parameters are not a substitute for interactive testing. `--version` does not validate that the interactive session starts and operates correctly. Each harness must be launched as a PTY session to prove real functionality.

### 6.4 Test Execution

`make test` runs:
```bash
dgoss run --user 1000:1000 -e HOME=/home/llm docker-llm-cli tail -f /dev/null
```

- `dgoss` copies `goss.yaml` and `tests/` into the container
- Runs all checks as user `llm`
- Exit code 0 = all pass; exit code 1 = any failure

**`dgoss` runs on the host**, not inside the container. The interactive test script (`test_harness.py`) must be present inside the image so the goss `command:` entry can invoke it.

### 6.5 Test Targets in Current `goss.yaml`

| Command | Timeout |
|---------|---------|
| `claude --version` | 5000ms |
| `codex --version` | 5000ms |
| `copilot --version` | 5000ms |
| `gemini --version` | 5000ms |
| `kimi --version` | default |
| `vibe --version` | 5000ms |
| `crush --version` | 5000ms |
| `opencode --version` | 5000ms |
| `qwen --version` | 5000ms |
| `goose --version` | 5000ms |
| `factory-droid --version` | 5000ms |
| `python3 tests/test_harness.py opencode` | 10000ms |
| `python3 tests/test_harness.py kilo` | 30000ms |

### 6.6 Adding a New Harness

To add a new interactive harness test:

1. Add the harness binary to the image (via `Dockerfile` and `Dockerfile.offline` if applicable)
2. Add file existence and `--version` checks to `goss.yaml`
3. Add a `command:` entry to `goss.yaml`:
   ```yaml
   "python3 tests/test_harness.py <binary>":
     exit-status: 0
     timeout: 30000
   ```
4. Update `motd` if the harness is user-facing
5. Add an alias to `aliases.sh` if the harness requires permissive flags

---

## 7. Distribution and Export

### 7.1 Bundle Creation (`run.sh` in repo root)

The repo root `run.sh` is the **bundle exporter**, not the runtime launcher:

```bash
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IMAGE_NAME="docker-llm-cli"
BUNDLE_NAME="docker-llm-cli-bundle"
BUNDLE_DIR="$SCRIPT_DIR/$BUNDLE_NAME"
BUNDLE_TAR="$SCRIPT_DIR/${BUNDLE_NAME}.tar.gz"

echo "Saving image ${IMAGE_NAME}..."
rm -rf "$BUNDLE_DIR"
mkdir -p "$BUNDLE_DIR"

docker save "$IMAGE_NAME" -o "$BUNDLE_DIR/${IMAGE_NAME}.tar"
cp "$SCRIPT_DIR"/export/* "$BUNDLE_DIR/"

tar czf "$BUNDLE_TAR" -C "$SCRIPT_DIR" "$BUNDLE_NAME"
rm -rf "$BUNDLE_DIR"

echo "Bundle ready: $BUNDLE_TAR"
```

### 7.2 Distribution Bundle Structure

```
docker-llm-cli-bundle/
├── docker-llm-cli.tar      # Saved Docker image
├── run.sh                  # Runtime launcher (copied from export/)
├── docker-llm-cli.env      # Env template (copied from export/)
└── README.md               # End-user documentation
```

### 7.3 End-User Runtime (`export/run.sh`)

1. Verify `docker-llm-cli.env` exists and has `600` permissions
2. Source the env file
3. Verify `WORKSPACE_DIR` is set and exists
4. Build `-e` flags only for non-empty variables
5. Load image from tar if not already present (`docker image inspect`)
6. Run container with full security profile, volume mounts, and environment

---

## 8. Decoupling from Artiary

The `docker/` repository was historically coupled to a sibling `artiary/` repository. The following decoupling measures are in place:

| Coupling | Resolution |
|----------|------------|
| `COPY artiary/artifacts/...` in Dockerfile | Removed. Online Dockerfile fetches from internet. Offline Dockerfile uses `COPY --from=artiary_artifacts` via Docker additional build contexts |
| `context: ..` in `docker-compose.yml` | Changed to `context: .` — build context is strictly inside `docker/` |
| `ARTIFACTS := ../artiary/artifacts` in Makefile | Changed to `ARTIFACTS ?= $(HOME)/.cache/artiary/artifacts` with override support |
| Shared `versions.yml` | A self-contained copy lives in `docker/versions.yml` |
| Artiary-specific export target | Artiary has a generic `export` target; docker uses `additional_contexts` |

### 8.1 Why Decouple

`docker/` and `artiary/` are **separate git repositories** (each has its own `.git/`). The `docker` repo could not be built or distributed independently because it was structurally coupled to `artiary` in three ways:

1. **Hardcoded `COPY artiary/artifacts/...` paths in the Dockerfile.** The Dockerfile referenced files outside its own repository. On DockerHub (or any CI that checks out only the `docker` repo), these paths did not exist and the build failed immediately.
2. **`docker-compose.yml` used `context: ..`.** The build context was the parent directory (workspace root), spanning both repos. DockerHub Automated Builds only see the `docker/` repo, so the context would be missing `artiary/` entirely.
3. **`Makefile` hardcoded `ARTIFACTS := ../artiary/artifacts`.** It assumed a sibling-directory relationship that does not exist when `docker/` is checked out alone.

The core design goals were:
- **Artiary must remain independent.** It manages artifacts for uses beyond docker.
- **Docker must become self-contained.** It should be buildable on DockerHub without artiary present.
- **Offline/reproducible builds must still work.** The existing air-gapped workflow (fetch artifacts in artiary, build docker offline) must not break.

### 8.2 Alternative Approaches Considered

#### Artifacts-as-Base-Image

Build an `artiary-base` Docker image containing all artifacts, publish it to a registry, then have the docker Dockerfile use `COPY --from=artiary-base`.

**Rejected because:**
- Requires maintaining and publishing a large base image full of `.deb` files
- Adds operational complexity (registry credentials, image versioning, size limits)
- The two-Dockerfile approach achieves the same goal with zero new infrastructure

#### Commit Artifacts to the Docker Repo

Copy artiary's `artifacts/` into the `docker/` git repo.

**Rejected because:**
- Binary artifacts (`.deb`, `.tar`, wheels) do not belong in git
- The repo would become enormous and slow to clone
- Violates the separation of concerns between artifact management and container configuration

#### Single Multi-Mode Dockerfile with Conditional Branching

One Dockerfile with `if [ "$DOCKERFILE" = "Dockerfile.offline" ]` branches inside `RUN` instructions.

**Rejected because:**
- More than half the file was branching logic, making it hard to read
- Online and offline paths were hidden behind `else` — easy to update one and miss the other
- Testing ambiguity: a `dgoss` failure could come from either branch
- The split approach makes each path an independently understandable linear narrative

### 8.3 Offline Build Workflow

```bash
# In artiary (independent)
make fetch && make freeze

# In docker
make build DOCKERFILE=Dockerfile.offline
make test
```

The Makefile reads versions from `$(ARTIARY_DATA_DIR)/versions.yml` when `DOCKERFILE=Dockerfile.offline`, and verifies that all referenced `.deb` files, the base image tar, and the manifest exist before building.

### 8.4 Verification Commands

**Online build (no artiary needed):**
```bash
cd docker
make build
make test   # dgoss validation
```

**Offline build (with artiary):**
```bash
cd artiary
make fetch && make freeze
cd ../docker
make build DOCKERFILE=Dockerfile.offline
make test
```

**Check for coupling leaks:**
```bash
grep -r "artiary/" docker/Dockerfile docker/Dockerfile.offline docker/docker-compose.yml
# Should return nothing

grep -r "\.\./" docker/Dockerfile docker/Dockerfile.offline docker/docker-compose.yml
# Should return nothing

grep -r "DOCKERFILE" Dockerfile Dockerfile.offline docker-compose.yml Makefile | grep -v "^#"
# Should return nothing (only comments, which are fine)
```

**Check for drift:**
```bash
cd docker
make check-sync
```

---

## 9. Non-Functional Requirements

### 9.1 Performance

| Metric | Requirement |
|--------|-------------|
| Image build (online) | < 10 minutes on broadband |
| Image build (offline) | < 5 minutes after artifacts are staged |
| Test suite execution | < 5 minutes total |
| Harness startup timeout | 45s per harness |
| Harness quit timeout | 30s per harness |

### 9.2 Reliability

- Tests must be idempotent (running twice produces identical results)
- No zombie processes on failure paths (SIGKILL + waitpid in all error branches)
- ANSI escape codes in PTY output must not break ready-state detection (raw byte search)
- Home directory seeding ensures container survives volume deletion

### 9.3 Maintainability

- Each Dockerfile is a linear narrative with no branching logic
- `test_harness.py` uses only Python stdlib — zero external dependencies
- Named constants for timeouts and ready indicators (`READY`, `QUIT_CMD`, `STARTUP_TIMEOUT`, `QUIT_TIMEOUT`)
- `make check-sync` guards against Dockerfile drift in CI

### 9.4 Security

- Container drops all capabilities except explicitly added ones
- Env file must have `600` permissions before `run.sh` will source it
- No secrets baked into the image — all API keys come from runtime env file
- Sudo access is passwordless but confined to the container
- Browser binaries moved to prevent CLI auth flows from opening unusable text browsers

---

## 10. Risks & Mitigations

| Risk | Impact | Mitigation |
|------|--------|------------|
| Harness CLI changes ready indicator | High | `READY = b"Tip"` is a named constant — one-line fix if it changes |
| ANSI codes obscure "Tip" in raw output | Low | Searching raw bytes; "Tip" is plain text unlikely to be split by escape codes |
| `/exit` not recognized by a harness | Low | Fall back to SIGKILL after `QUIT_TIMEOUT`; test still passes if process exits cleanly after SIGKILL |
| Dockerfile common sections drift | Medium | `make check-sync` fails CI if tail sections diverge |
| Online dependency disappears | Medium | Offline builds remain available; versions.yml documents expected versions |

---

## 11. Acceptance Criteria

| # | Criteria | Verification |
|---|----------|--------------|
| 1 | `docker build .` succeeds without artiary or artifacts | Clone repo fresh, run `docker build .` |
| 2 | Offline build succeeds with staged artifacts | Run `make all` after fetching artiary artifacts |
| 3 | All `goss.yaml` checks pass in both modes | Run `make test` after each build |
| 4 | Interactive harness tests pass (`opencode`, `kilo`) | `python3 tests/test_harness.py opencode` and `kilo` exit 0 |
| 5 | No coupling leaks to artiary | `grep -r "artiary/" Dockerfile Dockerfile.offline docker-compose.yml` returns nothing |
| 6 | No parent-directory references | `grep -r "\.\./" Dockerfile Dockerfile.offline docker-compose.yml` returns nothing |
| 7 | Drift guard passes | `make check-sync` exits 0 |
| 8 | Distribution bundle runs end-to-end | Load tar, configure env, `./run.sh` starts container |
| 9 | Home directory seeding works | Delete `docker-llm-cli-home` volume, restart container, shell config present |
| 10 | No Dockerfile branching remains | `grep -r "DOCKERFILE" Dockerfile Dockerfile.offline docker-compose.yml` (excluding comments) returns nothing |
| 11 | Both harness goss entries pass independently | Run `make all`, check output |
| 12 | Test fails when "Tip" is not seen within timeout | Mock binary that never prints "Tip", verify exit 1 |
| 13 | Test fails gracefully when binary is missing | Temporarily rename binary, verify exit 1 |

---

## 12. Definition of Done

- [ ] `Dockerfile` is online-only with no artifact references
- [ ] `Dockerfile.offline` uses `COPY --from=artiary_artifacts` and `COPY --from=artiary_data`
- [ ] `docker-compose.yml` uses `context: .` with `additional_contexts` for offline mode
- [ ] `tests/test_harness.py` present in image at build time (offline Dockerfile)
- [ ] Two `command:` entries added to `goss.yaml` (one per harness: `opencode`, `kilo`)
- [ ] `make all` completes with all tests green
- [ ] Each harness goss entry passes independently
- [ ] `make check-sync` passes (common tail sections synchronized)
- [ ] No coupling leaks (`grep` verification passes)
- [ ] README documents how to add a new harness
- [ ] Code review completed (if human review available)

---

## 13. References

| Resource | Link | Purpose |
|----------|------|---------|
| `docs/PROTOCOL.md` | — | Development protocol for this repo |
| `dgoss` documentation | https://github.com/aelsabbahy/goss/blob/master/docs/manual.md#dgoss | Runtime testing framework |
| Goss command validation | https://github.com/aelsabbahy/goss/blob/master/docs/manual.md#command | Non-interactive command checks |
| Python `pty` module | https://docs.python.org/3/library/pty.html | Stdlib PTY support |
