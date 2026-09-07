#!/bin/bash
# Runs every gate and fails loudly on the first one that breaks.
#
# This exists because the differential harness once stopped compiling after a
# refactor moved a type it depends on, and the breakage was easy to miss while
# reading a filtered pipeline instead of an exit code.
set -uo pipefail

cd "$(dirname "$0")/.."

FAILED=()

step() {
    local label="$1"; shift
    printf '\n==> %s\n' "$label"
    if "$@"; then
        printf '    ok\n'
    else
        printf '    FAILED\n'
        FAILED+=("$label")
    fi
}

step "Release build"        swift build -c release
step "Unit tests"           swift test
step "Mutation check"       python3 tools/mutation-check.py
step "Differential harness" ./tools/verify/run.sh "${1:-2025-01-01}"

printf '\n'
if [ ${#FAILED[@]} -gt 0 ]; then
    printf 'FAILED: %s\n' "${FAILED[*]}"
    exit 1
fi
printf 'All gates passed.\n'
