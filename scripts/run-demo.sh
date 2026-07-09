#!/usr/bin/env bash
# scripts/run-demo.sh — Run the Omni-Mind demo mode.

set -euo pipefail
cd "$(dirname "$0")/.."

if [ ! -f "zig-out/bin/omni-mind" ]; then
    echo "Binary not found. Running build first..."
    bash scripts/build.sh
fi

echo ""
exec ./zig-out/bin/omni-mind --demo
