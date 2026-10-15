#!/bin/bash
# Bundles the release binary into a proper macOS .app so TCC permissions
# (Accessibility / Screen Recording) attach to a stable, ad-hoc-signed bundle.
set -euo pipefail

cd "$(dirname "$0")/.."

APP="build/AltTab Dev.app"
CONTENTS="$APP/Contents"

swift build -c release

rm -rf "$APP"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources"
cp .build/release/AltTab "$CONTENTS/MacOS/AltTab"

cat > "$CONTENTS/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>AltTab</string>
    <key>CFBundleIdentifier</key>
    <string>personal.alttab.clone</string>
    <key>CFBundleName</key>
    <string>AltTab Dev</string>
    <key>CFBundleDisplayName</key>
    <string>AltTab Dev</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>0.1.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
PLIST

# Ad-hoc signature: stable identity for the TCC grants across rebuilds.
codesign --force --sign - "$APP"

echo "Bundled: $APP"
