#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IMAGE_NAME="docker-llm-cli"
IMAGE_DIR="$HOME/.cache/$IMAGE_NAME"
IMAGE_TAR="${IMAGE_DIR}/${IMAGE_NAME}.tar"
IMAGE_GZ="${IMAGE_DIR}.tar.gz"
RUNTIME="$SCRIPT_DIR/export"

echo "Saving image ${IMAGE_NAME}..."
rm -rf "$IMAGE_DIR"
mkdir -p "$IMAGE_DIR"

docker save "$IMAGE_NAME" -o "${IMAGE_TAR}"

cp "$RUNTIME"/* "$IMAGE_DIR/"

tar czf "$IMAGE_GZ" -C "$(dirname "$IMAGE_DIR")" "$(basename "$IMAGE_DIR")"

echo "Bundle ready: $IMAGE_GZ"

tar xzf "$IMAGE_GZ" -C "$(dirname "$IMAGE_GZ")"
cd "$IMAGE_DIR"
make init
