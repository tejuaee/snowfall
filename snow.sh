#!/usr/bin/env bash
# Build (only when needed) and start the snow.
set -euo pipefail
cd "$(dirname "$0")"

if [[ ! -x ./snowfall || Snow.swift -nt ./snowfall ]]; then
  echo "Building snowfall…"
  swiftc -O Snow.swift -o snowfall
fi

echo "Let it snow. ❄  Use the ❄ in the menu bar to change intensity or quit."
exec ./snowfall
