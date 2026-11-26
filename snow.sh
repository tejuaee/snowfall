#!/usr/bin/env bash
# Build (only when needed) and start the snow.
set -euo pipefail
cd "$(dirname "$0")"

usage() {
  cat <<'TEXT'
Snowfall — falling snow for your desktop (macOS, Linux; Windows: snow.cmd).

  ./snow.sh            build if needed, then start the snow
  ./snow.sh stop       stop it
  ./snow.sh status     say whether it is snowing
  ./snow.sh help       this

Once it is running, everything else is in the ❄ menu in the menu bar (macOS) or
the ❄ tray icon (Linux):
intensity, the plough, Snowball Mode, and the settings window.
TEXT
}

# Linux (and anything that is not a Mac) runs the Electron shell in desktop/.
if [[ "$(uname -s)" != "Darwin" ]]; then
  command -v npm >/dev/null || { echo "Snowfall needs Node.js (with npm): https://nodejs.org" >&2; exit 1; }
  cd desktop
  case "${1:-start}" in
    help|-h|--help) usage ;;
    status)
      if pgrep -f 'electron/dist/electron\S* \. --ozone-platform=x11$' >/dev/null; then
        echo "Snowing."
      else
        echo "Not running. Start it with ./snow.sh"
      fi ;;
    stop) npm run --silent stop ;;
    start)
      [[ -d node_modules/electron ]] || { echo "Installing Electron (first run only)…"; npm install --no-fund --no-audit; }
      echo "Let it snow. ❄  Use the ❄ tray icon for intensity, settings or quit."
      exec npm start --silent ;;
    *) usage >&2; exit 2 ;;
  esac
  exit 0
fi

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
