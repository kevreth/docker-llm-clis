#!/usr/bin/env bash
set -euo pipefail
if [[ ! -f "${HOME}/.initialized" ]]; then
    cp -an "${HOME}.seed/." "${HOME}/"
    touch "${HOME}/.initialized"
fi
exec "$@"
