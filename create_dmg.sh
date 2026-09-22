#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$DIR"

VERSION="${1:-1.0.0}"
APP_NAME="VoltDB"
DMG_NAME="VoltDB-v${VERSION}-arm64.dmg"

# 1. Build app if not present
if [ ! -d "${APP_NAME}.app" ]; then
    echo "⚡ Building ${APP_NAME}..."
    ./run.sh
fi

echo "📦 Creating Drag-and-Drop DMG for ${APP_NAME} v${VERSION}..."
STAGING_DIR="dmg_staging"
rm -rf "${STAGING_DIR}"
mkdir -p "${STAGING_DIR}"

# Copy app bundle
cp -R "${APP_NAME}.app" "${STAGING_DIR}/"

# Create Applications alias (TablePro approach: try Finder AppleScript, fall back to native alias template, then symlink)
echo "📁 Creating Applications alias with official icon..."
osascript <<EOF 2>/dev/null || true
tell application "Finder"
    set applicationsFolder to POSIX file "/Applications" as alias
    set stagingFolder to POSIX file "${DIR}/${STAGING_DIR}" as alias
    try
        make new alias file at stagingFolder to applicationsFolder with properties {name:"Applications"}
    on error
    end try
end tell
EOF

# Ensure custom icon attribute is set (matching TablePro)
APPS_ICON="/System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/ApplicationsFolderIcon.icns"
if [ -f "$APPS_ICON" ] && [ -e "${STAGING_DIR}/Applications" ]; then
    if command -v SetFile &> /dev/null; then
        cp "$APPS_ICON" "${STAGING_DIR}/Applications/Icon"$'\r' 2>/dev/null || true
        SetFile -a C "${STAGING_DIR}/Applications" 2>/dev/null || true
    fi
fi

# Build DMG (prefer create-dmg for styled layout, fallback to hdiutil like TablePro)
if command -v create-dmg &> /dev/null; then
    echo "Using create-dmg for styled layout..."
    CREATE_DMG_ARGS=(
        --volname "${APP_NAME}"
        --window-pos 200 120
        --window-size 600 400
        --icon-size 120
        --text-size 14
        --icon "${APP_NAME}.app" 150 160
        --icon "Applications" 450 160
        --hide-extension "${APP_NAME}.app"
        --no-internet-enable
    )
    
    if [ -f "${DIR}/packaging/dmg-background.png" ]; then
        CREATE_DMG_ARGS+=(--background "${DIR}/packaging/dmg-background.png")
    fi

    
    if ! create-dmg "${CREATE_DMG_ARGS[@]}" "${DMG_NAME}" "${STAGING_DIR}"; then
        echo "⚠️ create-dmg exited with non-zero, falling back to hdiutil..."
        if [ ! -f "${DMG_NAME}" ]; then
            hdiutil create -volname "${APP_NAME}" -srcfolder "${STAGING_DIR}" -ov -format UDZO "${DMG_NAME}"
        fi
    fi
else
    echo "create-dmg not installed, creating DMG using hdiutil..."
    hdiutil create -volname "${APP_NAME}" -srcfolder "${STAGING_DIR}" -ov -format UDZO "${DMG_NAME}"
fi

rm -rf "${STAGING_DIR}"

echo "🎉 DMG successfully created: ${DMG_NAME}"
