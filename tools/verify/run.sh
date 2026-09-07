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

echo "==> Reference (Python)"
python3 tools/verify/reference.py "$CUTOFF"

echo
echo "==> Providers (Swift)"
cp Sources/TokenCounter/Providers/*.swift "$WORK/"
cp tools/verify/main.swift "$WORK/"
swiftc -O "$WORK"/*.swift -o "$WORK/verify"
# The harness resets provider state, so the app re-tallies on its next scan.
"$WORK/verify" "$CUTOFF"

echo
echo "Note: provider state was reset. The app re-scans within its refresh interval."
