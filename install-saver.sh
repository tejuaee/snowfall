#!/usr/bin/env bash
# Build Snowfall.saver and install it for the current user.
set -euo pipefail
cd "$(dirname "$0")"

BUNDLE="build/Snowfall.saver"
rm -rf "$BUNDLE"
mkdir -p "$BUNDLE/Contents/MacOS" "$BUNDLE/Contents/Resources"

cat > "$BUNDLE/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key>                 <string>Snowfall</string>
  <key>CFBundleDisplayName</key>          <string>Snowfall</string>
  <key>CFBundleIdentifier</key>           <string>com.github.tejuaee.snowfall.saver</string>
  <key>CFBundleExecutable</key>           <string>Snowfall</string>
  <key>CFBundlePackageType</key>          <string>BNDL</string>
  <key>CFBundleShortVersionString</key>   <string>1.0</string>
  <key>CFBundleVersion</key>              <string>1</string>
  <key>NSPrincipalClass</key>             <string>SnowfallView</string>
  <key>NSHighResolutionCapable</key>      <true/>
</dict>
</plist>
PLIST

echo "· building Snowfall.saver"
swiftc -O -emit-library -module-name SnowfallSaver Saver.swift \
  -o "$BUNDLE/Contents/MacOS/Snowfall" \
  -framework ScreenSaver -framework AppKit

DEST="$HOME/Library/Screen Savers"
mkdir -p "$DEST"
rm -rf "$DEST/Snowfall.saver"
cp -R "$BUNDLE" "$DEST/"

echo "installed: $DEST/Snowfall.saver"
echo
echo "Now pick it: System Settings → Screen Saver → Other → Snowfall."
echo "For snow on the lock screen, set Lock Screen → \"Start Screen Saver when inactive\""
echo "and \"Require password after screen saver begins\"."
