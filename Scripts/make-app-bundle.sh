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

# Version: taken from ALT_TAB_VERSION (CI release builds) or git tag, else 0.0.0-dev.
VERSION="${ALT_TAB_VERSION:-$(git describe --tags --exact-match 2>/dev/null || true)}"
VERSION="${VERSION:-0.0.0-dev}"

cat > "$CONTENTS/Info.plist" <<PLIST
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
    <string>${VERSION}</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
PLIST

# Sign with the stable local identity (see README: one-time keychain setup).
# A stable signing identity keeps the TCC grants valid across rebuilds —
# ad-hoc signatures change on every build and silently invalidate them.
IDENTITY="AltTab Dev Local Signing"
if security find-identity | grep -q "$IDENTITY"; then
    codesign --force --sign "$IDENTITY" "$APP"
else
    echo "warning: '$IDENTITY' not in keychain, falling back to ad-hoc (TCC grants will not survive rebuilds)" >&2
    codesign --force --sign - "$APP"
fi

echo "Bundled: $APP"
