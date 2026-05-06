#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$SCRIPT_DIR/docker-llm-cli.env"

if [[ ! -f "$ENV_FILE" ]]; then
  echo "Error: $ENV_FILE not found." >&2
  echo "Copy docker-llm-cli.env.example to docker-llm-cli.env and fill in your values." >&2
  exit 1
fi

PERMS=$(stat -c "%a" "$ENV_FILE")
if [[ "$PERMS" != "600" ]]; then
  echo "Error: $ENV_FILE must have permissions 600 (currently $PERMS)." >&2
  echo "Fix: chmod 600 $ENV_FILE" >&2
  exit 1
fi

# shellcheck source=/dev/null
source "$ENV_FILE"

if [[ -z "${WORKSPACE_DIR:-}" ]]; then
  echo "Error: WORKSPACE_DIR is not set in $ENV_FILE." >&2
  exit 1
fi

if [[ ! -d "$WORKSPACE_DIR" ]]; then
  echo "Error: WORKSPACE_DIR '$WORKSPACE_DIR' does not exist on the host." >&2
  exit 1
fi

# Build -e flags from the env file. Only forward variables that resolved to a
# non-empty value — variables left unset in the environment are not passed to
# the container, so they remain absent rather than set to an empty string.
ENV_ARGS=()
while IFS= read -r line; do
  [[ "$line" =~ ^[[:space:]]*(#|$) ]] && continue
  varname="${line%%=*}"
  varname="${varname//[[:space:]]/}"
  if [[ -n "$varname" ]]; then
    val="${!varname:-}"
    [[ -n "$val" ]] && ENV_ARGS+=("-e" "$varname=$val")
  fi
done < "$ENV_FILE"

if ! docker image inspect docker-llm-cli &>/dev/null; then
  docker load -i "$SCRIPT_DIR/docker-llm-cli.tar"
fi

if ! docker container inspect docker-llm-cli &>/dev/null; then
  echo "Starting container..."
  docker run -d \
    --name docker-llm-cli \
    --init \
    -u 1000:1000 \
    -w /workspace \
    -v "${WORKSPACE_DIR}:/workspace" \
    -v "docker-llm-cli-artifacts:/artifacts" \
    -v "docker-llm-cli-home:/home/llm" \
    -v "${SSH_AUTH_SOCK:-/dev/null}:/ssh-agent" \
    "${ENV_ARGS[@]}" \
    -e HOME=/home/llm \
    -e SHELL=/bin/bash \
    -e SSH_AUTH_SOCK=/ssh-agent \
    -e TMPDIR=/workspace/.tmp \
    -e "GIT_SSH_COMMAND=ssh -o UserKnownHostsFile=/home/llm/.ssh/known_hosts -o IdentityAgent=/ssh-agent" \
    -e "GH_TOKEN=${GH_TOKEN:-}" \
    --cap-drop ALL \
    --cap-add SETUID \
    --cap-add SETGID \
    --cap-add NET_RAW \
    --cap-add NET_ADMIN \
    --security-opt no-new-privileges:false \
    --tmpfs /tmp \
    --tmpfs /run \
    docker-llm-cli sleep infinity
elif [[ "$(docker container inspect -f '{{.State.Running}}' docker-llm-cli)" != "true" ]]; then
  echo "Resuming stopped container..."
  docker start docker-llm-cli
fi

exec docker exec -it docker-llm-cli /bin/bash --login
