#!/bin/bash
# Captures the settings window, including the AppKit-backed controls that
# ImageRenderer renders as a placeholder. Writes PNGs to the directory you pass
# (default docs/ui).
set -euo pipefail
cd "$(dirname "$0")/../.."

OUT="${1:-docs/ui}"
mkdir -p "$OUT"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# Never touch the app's own scan state.
export TOKEN_COUNTER_STATE_DIR="$WORK/state"
mkdir -p "$TOKEN_COUNTER_STATE_DIR"
# Reuse the real history if there is one, so the chart has something in it.
if [ -f "$HOME/Library/Application Support/TokenCounter/history.json" ]; then
    cp "$HOME/Library/Application Support/TokenCounter/history.json" "$TOKEN_COUNTER_STATE_DIR/"
fi

cp Sources/TokenCounter/*.swift "$WORK/"
cp Sources/TokenCounter/Providers/*.swift "$WORK/"
rm "$WORK/main.swift"
cp tools/uishot/main.swift "$WORK/"

swiftc -O "$WORK"/*.swift -o "$WORK/uishot"
"$WORK/uishot" "$(cd "$OUT" && pwd)"
