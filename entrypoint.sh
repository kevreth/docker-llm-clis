#!/usr/bin/env bash
set -euo pipefail
cp -an "${HOME}.seed/." "${HOME}/"
exec "$@"
