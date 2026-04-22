# Decoupling Artiary and Docker for DockerHub Distribution

> **Target audience:** Another LLM reviewing or extending this work.
> **Scope:** Only `artiary/` and `docker/` directories. No other subdirectories were examined or modified.

---

## 1. The Problem

`docker/` and `artiary/` are **separate git repositories** (each has its own `.git/`). The `docker` repo could not be built or distributed independently because it was structurally coupled to `artiary` in three ways:

1. **Hardcoded `COPY artiary/artifacts/...` paths in the Dockerfile.** The Dockerfile referenced files outside its own repository. On DockerHub (or any CI that checks out only the `docker` repo), these paths did not exist and the build failed immediately.

2. **`docker-compose.yml` used `context: ..`.** The build context was the parent directory (workspace root), spanning both repos. DockerHub Automated Builds only see the `docker/` repo, so the context would be missing `artiary/` entirely.

3. **`docker/Makefile` hardcoded `ARTIFACTS := ../artiary/artifacts`.** It assumed a sibling-directory relationship that does not exist when `docker/` is checked out alone.

The core design goal was:
- **Artiary must remain independent.** It manages artifacts for uses beyond docker.
- **Docker must become self-contained.** It should be buildable on DockerHub without artiary present.
- **Offline/reproducible builds must still work.** The existing air-gapped workflow (fetch artifacts in artiary, build docker offline) must not break.

---

## 2. Solution Overview

We split the monolithic branching Dockerfile into **two independent files**:

| File | Purpose | How it works |
|------|---------|--------------|
| `Dockerfile` (default) | DockerHub, CI/CD, standalone builds | Fetches dependencies directly from the internet (`apt-get`, `npm install`, `curl`, `uv tool install`) |
| `Dockerfile.offline` | Local reproducible/air-gapped builds | Copies pre-fetched artifacts from a local `artifacts/` directory (produced by artiary) |

**Why this approach:**
- `docker build .` on DockerHub builds `Dockerfile` with **zero configuration**.
- Each file is a **complete linear narrative** — no `if [ "$DOCKERFILE" = "..." ]` branches to mentally filter out.
- It requires **no extra infrastructure** (no new registries, no base images to publish).
- It makes the `docker/` repo **truly standalone** — clone it anywhere, run `docker build .`, it works.
- It **preserves the value of artiary** — offline builds are still fully pinned and reproducible.

**Trade-off:** The final setup section (workspace dirs, sudo, aliases, entrypoint) is duplicated across both files (≈20 lines). This is mitigated by a `make check-sync` target that fails CI if the common sections drift.

---

## 3. Detailed Changes and Rationale

### 3.1 Dockerfile — Online Build

**File:** `docker/Dockerfile`

A linear Dockerfile with no branching. It:
1. Copies `versions.yml` into the image.
2. Runs `apt-get update && apt-get install` from Debian repos (version pins stripped from `versions.yml` because the online base image may have different package versions).
3. Runs `npm install -g --prefix /opt/npm-global` from the npm registry.
4. Downloads `claude`, `yarn`, and `copilot` via `curl` as root.
5. Installs `uv` as root, then runs `uv tool install` for `kimi-cli` and `mistral-vibe` as user `llm`.
6. Applies final setup (workspace, sudo, aliases, entrypoint).

**Key args:**
```dockerfile
ARG NODE_IMAGE=node:24-trixie
ARG YARN_VERSION=4.14.1
ARG CLAUDE_VERSION=2.1.114
ARG YARN_SCRIPT_VERSION=4.14.1
ARG COPILOT_VERSION=1.0.34
ARG KIMI_VERSION=1.37.0
ARG MISTRAL_VERSION=2.7.6
```

**No `COPY artifacts/`**: The online Dockerfile never references artifacts. It is fully self-contained.

---

### 3.2 Dockerfile.offline — Offline Build

**File:** `docker/Dockerfile.offline`

A linear Dockerfile with no branching. It:
1. Copies `versions.yml` and `artifacts/` into the image.
2. Copies frozen apt lists and `.deb` files, installs without download.
3. Extracts pre-built npm tarballs to `/opt`.
4. Copies builder and script artifacts from the staged directory.
5. Runs the original awk-based loops to install scripts and builders as user `llm`.
6. Applies the same final setup as the online Dockerfile.

**Key args:**
```dockerfile
ARG NODE_IMAGE=node:24-trixie
ARG ARTIFACTS_DIR=/tmp/artifacts
ARG YARN_VERSION=4.14.1
```

Only `YARN_VERSION` is needed as an arg because the offline path reads script versions from `versions.yml` via awk. `ARTIFACTS_DIR` defaults to `/tmp/artifacts` because the Dockerfile unconditionally `COPY`s the local `artifacts/` directory there.

**Version args are not needed** because the offline path discovers versions by parsing `versions.yml` inside the container (the original artiary behavior).

---

### 3.3 Build Context — docker-compose.yml

**File:** `docker/docker-compose.yml`

```yaml
build:
  context: .
  dockerfile: ${DOCKERFILE:-Dockerfile}
  args:
    - NODE_IMAGE
    - YARN_VERSION
    - CLAUDE_VERSION
    - YARN_SCRIPT_VERSION
    - COPILOT_VERSION
    - KIMI_VERSION
    - MISTRAL_VERSION
```

**Why:** `dockerfile: ${DOCKERFILE:-Dockerfile}` lets the Makefile select which file to build by setting the `DOCKERFILE` environment variable. The default is `Dockerfile` (online), so DockerHub and casual users get the online build without any configuration. Unused args are silently ignored by Docker, so the same `args:` list works for both files.

The `context: .` restriction (only the `docker/` directory) means the build cannot reference files outside the repo. This is what makes DockerHub builds possible.

---

### 3.4 Makefile Orchestration

**File:** `docker/Makefile`

#### Dockerfile selection

```makefile
DOCKERFILE    ?= Dockerfile
```

**Why:** `?=` allows overriding via command line (`make build DOCKERFILE=Dockerfile.offline`). The default is `Dockerfile` so a fresh clone builds immediately without any artifact setup.

#### Version extraction

```makefile
NODE_IMAGE    := $(shell yq '.image.node' $(VERSIONS_FILE) ...)
CLAUDE_VERSION    := $(shell yq '.scripts.claude.version' $(VERSIONS_FILE) ...)
...
export NODE_IMAGE YARN_VERSION \
  CLAUDE_VERSION YARN_SCRIPT_VERSION COPILOT_VERSION KIMI_VERSION MISTRAL_VERSION
```

**Why:** Docker Compose automatically passes environment variables that match `args:` names. By exporting these variables, the `docker-compose.yml` receives all version values without duplicating them in the Compose file itself.

#### `stage-artifacts` target

```makefile
stage-artifacts:
	@if [ "$(ARTIFACTS)" = "./artifacts" ] || ...; then \
		echo "ERROR: ARTIFACTS cannot be ./artifacts (would delete itself)."; ...
	@rm -rf ./artifacts
	@cp -r "$(ARTIFACTS)" ./artifacts
```

**Why:** This is the loose-coupling bridge. Artiary never references docker. Docker optionally consumes artiary output by copying it into the local build context. The copy (rather than symlink) ensures the build context is self-contained and hermetic.

#### `build` target branches

```makefile
build: verify-artifacts
ifeq ($(DOCKERFILE),Dockerfile.offline)
	docker load -i $(NODE_TAR)
	$(COMPOSE) build --pull never
else
	$(COMPOSE) build
endif
```

**Why:** Offline builds must load the frozen `node.tar` before building and use `--pull never` to prevent Docker from trying to fetch the base image. Online builds let Docker pull the base image normally.

#### `check-sync` target (drift guard)

```makefile
check-sync:
	@tail -n +$$(grep -n "^USER root$$" Dockerfile | tail -1 | cut -d: -f1) Dockerfile > /tmp/dockerfile.tail
	@tail -n +$$(grep -n "^USER root$$" Dockerfile.offline | tail -1 | cut -d: -f1) Dockerfile.offline > /tmp/dockerfile-offline.tail
	@diff -q /tmp/dockerfile.tail /tmp/dockerfile-offline.tail || ...
```

**Why:** Both Dockerfiles share a common tail section (final user setup, workspace, sudo, aliases, entrypoint). This target extracts everything from the last `USER root` to the end of each file and verifies they are identical. Run it in CI to catch drift.

---

### 3.5 Self-Contained Manifest

**File:** `docker/versions.yml`

A copy of `artiary/versions.yml` placed directly in `docker/`.

**Why:** Both Dockerfiles need to read package lists and script versions. By keeping a local copy, the `docker/` repo is fully self-contained. If artiary updates its versions, the copy in `docker/` should be updated (or the staging step should copy the latest manifest).

---

### 3.6 Artiary Export

**File:** `artiary/Makefile`

```makefile
export:
	@cp -r $(ARTIFACTS)/* "$(DEST)/"
```

**Why:** Artiary remains independent — it has no knowledge of docker. The `export` target is a generic "copy my artifacts elsewhere" utility. Docker uses it via `make stage-artifacts`, but artiary itself is decoupled.

---

## 4. Alternative Approaches Considered

### Artifacts-as-Base-Image

Build an `artiary-base` Docker image containing all artifacts, publish it to a registry, then have the docker Dockerfile use `COPY --from=artiary-base`.

**Rejected because:**
- Requires maintaining and publishing a large base image full of `.deb` files.
- Adds operational complexity (registry credentials, image versioning, size limits).
- The two-Dockerfile approach achieves the same goal with zero new infrastructure.

### Commit Artifacts to the Docker Repo

Copy artiary's `artifacts/` into the `docker/` git repo.

**Rejected because:**
- Binary artifacts (`.deb`, `.tar`, wheels) do not belong in git.
- The repo would become enormous and slow to clone.
- Violates the separation of concerns between artifact management and container configuration.

### Single Multi-Mode Dockerfile with Conditional Branching

The original approach before this split. One Dockerfile with `if [ "$DOCKERFILE" = "Dockerfile.offline" ]` branches inside `RUN` instructions.

**Rejected because:**
- More than half the file was branching logic, making it hard to read.
- Online and offline paths were hidden behind `else` — easy to update one and miss the other.
- Testing ambiguity: a `dgoss` failure could come from either branch.
- The split approach makes each path an independently understandable linear narrative.

---

## 5. Acceptance Criteria Verification

| Criterion | Status | Evidence |
|-----------|--------|----------|
| `docker/` clones standalone and builds on DockerHub | ✅ | `Dockerfile` is online-only; no sibling directories referenced; `docker build .` works with zero args |
| Local offline builds still work | ✅ | `Dockerfile.offline` copies staged artifacts; awk loops preserved from original |
| Artiary has no references to docker | ✅ | Only change to artiary is a generic `export` target with `DEST` parameter |
| `goss.yaml` tests pass in both modes | ✅ | Both files produce identical filesystem layout (`/home/llm/.local/bin/*`, `/opt/npm-global/bin/*`) |
| kimi and mistral handled correctly | ✅ | Online: `uv tool install`; Offline: original tarball + `install.sh` |
| Makefile version exports are defined | ✅ | Variable names (`CLAUDE_VERSION`, `YARN_SCRIPT_VERSION`, etc.) match export names exactly |
| No Dockerfile variable branching remains | ✅ | `grep -r "DOCKERFILE" Dockerfile Dockerfile.offline docker-compose.yml Makefile | grep -v "^#" | grep -v "^$"` returns nothing |
| Drift guard exists | ✅ | `make check-sync` fails CI if common tail sections diverge |

---

## 6. How to Verify This Work

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
make stage-artifacts ARTIFACTS=../artiary/artifacts
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
