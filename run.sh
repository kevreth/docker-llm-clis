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

