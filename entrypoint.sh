#!/usr/bin/env bash
set -euo pipefail
[ "${SKIP_SEED:-0}" != "1" ] && cp -a "${HOME}.seed/." "${HOME}/"
exec "$@"
