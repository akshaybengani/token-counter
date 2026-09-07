#!/bin/bash
# Builds TokenCounter.app and installs it to ~/Applications.
set -euo pipefail

cd "$(dirname "$0")"

NAME="TokenCounter"
DISPLAY_NAME="Token Counter"
BUNDLE_ID="com.akshaybengani.tokencounter"
APP="dist/${NAME}.app"
INSTALL_DIR="${HOME}/Applications"

echo "==> Generating icon"
./tools/make-icon.sh

echo "==> Compiling"
swift build -c release

echo "==> Assembling ${APP}"
rm -rf "$APP"
mkdir -p "${APP}/Contents/MacOS" "${APP}/Contents/Resources"
cp ".build/release/${NAME}" "${APP}/Contents/MacOS/${NAME}"
cp "Resources/AppIcon.icns" "${APP}/Contents/Resources/AppIcon.icns"

cat > "${APP}/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>${NAME}</string>
    <key>CFBundleIdentifier</key><string>${BUNDLE_ID}</string>
    <key>CFBundleName</key><string>${DISPLAY_NAME}</string>
    <key>CFBundleDisplayName</key><string>${DISPLAY_NAME}</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>NSHighResolutionCapable</key><true/>
    <!-- Menu-bar accessory: no Dock icon, no app switcher entry. -->
    <key>LSUIElement</key><true/>
</dict>
</plist>
PLIST

echo "==> Signing (ad-hoc)"
codesign --force --sign - --timestamp=none "$APP"
codesign --verify --verbose=1 "$APP" 2>&1 | sed 's/^/    /'

echo "==> Installing to ${INSTALL_DIR}"
mkdir -p "$INSTALL_DIR"
pkill -x "$NAME" 2>/dev/null || true
sleep 0.5
rm -rf "${INSTALL_DIR}/${NAME}.app"
cp -R "$APP" "${INSTALL_DIR}/${NAME}.app"

echo "==> Done: ${INSTALL_DIR}/${NAME}.app"
