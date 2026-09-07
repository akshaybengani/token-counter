#!/bin/bash
# Cross-checks the Codex and Cursor providers against an independent Python
# implementation of the same rules. Both sides scan from the cutoff you pass,
# rather than from local midnight, so there is real data to compare.
#
#   ./tools/verify/run.sh 2025-01-01
#
# The two outputs must agree field by field.
set -euo pipefail
cd "$(dirname "$0")/../.."

CUTOFF="${1:-2025-01-01}"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# Run against a throwaway state directory. Without this the harness would advance the
# app's byte cursors while writing a cutoff day key, and the app would then skip
# today's records because cursors are meant to outlive a midnight rollover.
export TOKEN_COUNTER_STATE_DIR="$WORK/state"

echo "==> Reference (Python)"
python3 tools/verify/reference.py "$CUTOFF"

echo
echo "==> Providers (Swift)"
cp Sources/TokenCounter/Providers/*.swift "$WORK/"
# Provider.swift names Palette for its tints, so the palette has to come too.
# Anything else the providers grow a reference to needs adding here.
cp Sources/TokenCounter/Palette.swift "$WORK/"
cp tools/verify/main.swift "$WORK/"
swiftc -O "$WORK"/*.swift -o "$WORK/verify"
"$WORK/verify" "$CUTOFF"

echo
echo "The running app's state was not touched."
