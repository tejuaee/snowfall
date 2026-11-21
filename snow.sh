#!/usr/bin/env bash
# Build (only when needed) and start the snow.
set -euo pipefail
cd "$(dirname "$0")"

if [[ ! -x ./snowfall || Snow.swift -nt ./snowfall ]]; then
  echo "Building snowfall…"
  swiftc -O Snow.swift -o snowfall
fi

case "${1:-start}" in
  stop)
    pkill -x snowfall && echo "Snow stopped." || echo "No snow was falling."
    exit 0
    ;;
  start)
    pkill -x snowfall 2>/dev/null || true   # never stack two overlays per screen
    echo "Let it snow. ❄  Use the ❄ in the menu bar for intensity, battery mode or quit."
    exec ./snowfall
    ;;
  *)
    echo "usage: ./snow.sh [start|stop]" >&2
    exit 2
    ;;
esac
