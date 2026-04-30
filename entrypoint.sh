#!/usr/bin/env bash
set -euo pipefail
cp -a "${HOME}.seed/." "${HOME}/"
exec "$@"
