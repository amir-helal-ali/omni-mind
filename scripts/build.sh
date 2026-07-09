#!/usr/bin/env bash
# scripts/build.sh — Build the entire Omni-Mind project (Zig core + Rust swarm).

set -euo pipefail
cd "$(dirname "$0")/.."

echo "═════════════════════════════════════════════════════════════"
echo "  Building Omni-Mind — Zig core"
echo "═════════════════════════════════════════════════════════════"

# Check Zig is available
if ! command -v zig &> /dev/null; then
    echo "ERROR: Zig is not installed."
    echo "Install from: https://ziglang.org/download/"
    echo "Example: curl -L https://ziglang.org/download/0.13.0/zig-linux-x86_64-0.13.0.tar.xz | tar -xJ -C /usr/local && ln -s /usr/local/zig-linux-x86_64-0.13.0/zig /usr/local/bin/zig"
    exit 1
fi

zig version
zig build
echo "✓ Zig core built: zig-out/bin/omni-mind"

echo ""
echo "═════════════════════════════════════════════════════════════"
echo "  Running unit tests"
echo "═════════════════════════════════════════════════════════════"
zig build test
echo "✓ All tests passed"

echo ""
echo "═════════════════════════════════════════════════════════════"
echo "  Building Rust swarm (optional)"
echo "═════════════════════════════════════════════════════════════"

if command -v cargo &> /dev/null; then
    cd swarm
    cargo build --release 2>&1 | tail -5
    echo "✓ Rust swarm built: swarm/target/release/omni-swarm-node"
else
    echo "⚠ Cargo not installed, skipping Rust swarm build."
    echo "  Install Rust from: https://rustup.rs"
fi

echo ""
echo "═════════════════════════════════════════════════════════════"
echo "  Build complete!"
echo "═════════════════════════════════════════════════════════════"
echo "Try: ./zig-out/bin/omni-mind --demo"
