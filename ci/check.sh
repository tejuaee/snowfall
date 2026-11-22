#!/usr/bin/env bash
# Everything that has to hold before pushing: the overlay builds, the snow engine
# parses, and the page still exposes every hook the Swift side calls.
set -euo pipefail
cd "$(dirname "$0")/.."

echo "· building the overlay"
swiftc -O Snow.swift -o /tmp/snowfall-check

echo "· parsing the snow engine"
python3 - <<'PY'
import re
src = open("index.html").read()
script = re.search(r"<script>(.*)</script>", src, re.S).group(1)
open("/tmp/snow-check.js", "w").write(script)
PY
if command -v node >/dev/null; then
  node --check /tmp/snow-check.js
else
  echo "  (node not installed, skipping the syntax check)"
fi

echo "· checking the hooks the app calls"
for hook in setIntensity setPaused setPowerSaver applySettings sendPlow clearPile; do
  grep -q "window.$hook = " index.html || { echo "  missing window.$hook"; exit 1; }
done

echo "· starting the page in WebKit"
swiftc -O ci/check-page.swift -o /tmp/snowfall-page-check
/tmp/snowfall-page-check index.html

echo "· building and loading the screen saver"
./install-saver.sh --build-only >/dev/null
swiftc -O ci/check-saver.swift -o /tmp/snowfall-saver-check -framework ScreenSaver
/tmp/snowfall-saver-check build/Snowfall.saver

# The mistake this catches: commits authored with an address that is not linked to the
# GitHub account owning the repo are credited to nobody. The commits land, the
# contribution graph stays empty, and nothing anywhere says why.
if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
  echo "· checking who the commits will belong to"
  me=$(gh api user --jq .login 2>/dev/null || true)
  id=$(gh api user --jq .id 2>/dev/null || true)
  email=$(git config user.email 2>/dev/null || true)
  if [[ -n "$me" && -n "$email" && "$email" != *"+${me}@users.noreply.github.com" ]]; then
    echo "  warning: commits here are authored as $email"
    echo "  GitHub credits a commit only when that address is linked to the account that"
    echo "  owns this repository ($me). If the graph stays empty, this is why. Fix with:"
    echo "    git config user.email ${id}+${me}@users.noreply.github.com"
  fi
fi

echo "all good ❄"
