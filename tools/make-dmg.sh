#!/bin/bash
# Packages the built app as a compressed DMG for download.
#
# The DMG is ad-hoc signed, not notarized, so Gatekeeper will warn on a machine that
# did not build it. That trade-off is recorded on spec-26 dec-5; building from source
# stays the warning-free path.
set -euo pipefail

cd "$(dirname "$0")/.."

NAME="TokenCounter"
VOLUME="Token Counter"
APP="dist/${NAME}.app"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "${APP}/Contents/Info.plist" 2>/dev/null || echo 1.0)"
DMG="dist/${NAME}-${VERSION}.dmg"

if [ ! -d "$APP" ]; then
    echo "error: ${APP} not found. Run ./build.sh first." >&2
    exit 1
fi

STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT

echo "==> Staging"
cp -R "$APP" "$STAGE/"
# The Applications symlink is what lets someone drag the app across in the mounted window.
ln -s /Applications "$STAGE/Applications"

echo "==> Building ${DMG}"
rm -f "$DMG"
hdiutil create \
    -volname "$VOLUME" \
    -srcfolder "$STAGE" \
    -ov -format UDZO \
    -quiet \
    "$DMG"

echo "==> Verifying"
hdiutil verify -quiet "$DMG"
SIZE="$(du -h "$DMG" | cut -f1)"
echo "    ${DMG} (${SIZE}) verified"
echo
echo "Reminder: this is not notarized. A first-time user has to right-click, Open,"
echo "then allow it, or run: xattr -d com.apple.quarantine /Applications/${NAME}.app"
