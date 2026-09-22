#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$DIR"

APP_VERSION="0.1.0"

echo "⚡ Building VoltDB v${APP_VERSION}..."
swift build

mkdir -p VoltDB.app/Contents/MacOS VoltDB.app/Contents/Resources

# Generate Info.plist
cat <<EOF > VoltDB.app/Contents/Info.plist
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>VoltDB</string>
    <key>CFBundleIdentifier</key>
    <string>com.voltdb.app</string>
    <key>CFBundleName</key>
    <string>VoltDB</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>${APP_VERSION}</string>
    <key>CFBundleVersion</key>
    <string>${APP_VERSION}</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
EOF

cp .build/debug/VoltDB VoltDB.app/Contents/MacOS/
cp Sources/VoltDB/Resources/AppIcon.icns VoltDB.app/Contents/Resources/ 2>/dev/null || true
cp Sources/VoltDB/Resources/AppIcon.png VoltDB.app/Contents/Resources/ 2>/dev/null || true

# Sign with network entitlements
codesign --force --deep --sign - --entitlements VoltDB.entitlements VoltDB.app 2>/dev/null || true

touch VoltDB.app
killall VoltDB 2>/dev/null || true

echo "🚀 Launching VoltDB.app v${APP_VERSION}..."
open VoltDB.app
