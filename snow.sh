#!/usr/bin/env bash
# Build (only when needed) and start the snow.
set -euo pipefail
cd "$(dirname "$0")"

usage() {
  cat <<'TEXT'
Snowfall — falling snow for your macOS desktop.

  ./snow.sh            build if needed, then start the snow
  ./snow.sh stop       stop it
  ./snow.sh status     say whether it is snowing
  ./snow.sh help       this

Once it is running, everything else is in the ❄ menu in the menu bar:
intensity, the plough, Snowball Mode, and the settings window.
TEXT
}

case "${1:-start}" in
  help|-h|--help)
    usage
    exit 0
    ;;
  status)
    if pid=$(pgrep -x snowfall); then
      echo "Snowing. (pid $pid)"
    else
      echo "Not running. Start it with ./snow.sh"
    fi
    exit 0
    ;;
  stop)
    pkill -x snowfall && echo "Snow stopped." || echo "No snow was falling."
    exit 0
    ;;
  start)
    if [[ ! -x ./snowfall || Snow.swift -nt ./snowfall ]]; then
      echo "Building snowfall…"
      swiftc -O Snow.swift -o snowfall
    fi
    pkill -x snowfall 2>/dev/null || true   # never stack two overlays per screen
    echo "Let it snow. ❄  Use the ❄ in the menu bar for intensity, battery mode or quit."
    exec ./snowfall
    ;;
  *)
    usage >&2
    exit 2
    ;;
esac
