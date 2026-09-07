#!/bin/bash
# Renders Resources/AppIcon.icns from tools/icongen. Skips the work when the
# generated icon is already newer than its source.
set -euo pipefail

cd "$(dirname "$0")/.."

SRC="tools/icongen/main.swift"
ICNS="Resources/AppIcon.icns"
MASTER="Resources/icon-1024.png"

if [ -f "$ICNS" ] && [ "$ICNS" -nt "$SRC" ]; then
    echo "    icon up to date"
    exit 0
fi

mkdir -p Resources
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

swiftc -O "$SRC" -o "$WORK/icongen"
"$WORK/icongen" "$MASTER"

SET="$WORK/AppIcon.iconset"
mkdir -p "$SET"
# .icns expects each logical size at 1x and 2x.
for pair in "16 icon_16x16" "32 icon_16x16@2x" "32 icon_32x32" "64 icon_32x32@2x" \
            "128 icon_128x128" "256 icon_128x128@2x" "256 icon_256x256" \
            "512 icon_256x256@2x" "512 icon_512x512" "1024 icon_512x512@2x"; do
    set -- $pair
    sips -z "$1" "$1" "$MASTER" --out "$SET/$2.png" >/dev/null
done

iconutil -c icns "$SET" -o "$ICNS"
echo "    wrote $ICNS ($(du -h "$ICNS" | cut -f1))"
