#!/usr/bin/env bash
# scripts/docker-entrypoint.sh — Entrypoint for the omni-mind Docker image.
#
# Usage:
#   docker run --rm -it omni-mind                  # show this help
#   docker run --rm -it omni-mind help             # show help
#   docker run --rm -it omni-mind build            # build everything (already done in image)
#   docker run --rm -it omni-mind test             # run unit tests
#   docker run --rm -it omni-mind verify           # native Zig verification (1000 questions)
#   docker run --rm -it omni-mind bench            # 1000-question benchmark
#   docker run --rm -it omni-mind repl             # interactive REPL
#   docker run --rm -it omni-mind web              # HTTP API + UI (port 8080)
#   docker run --rm -it omni-mind tcp              # TCP server (port 19090)
#   docker run --rm -it omni-mind swarm            # P2P swarm node (port 18101)
#   docker run --rm -it omni-mind bash             # bash shell

set -e

# Use OMNI_HOME env var if set (for testing outside container), otherwise /home/omni
OMNI_HOME="${OMNI_HOME:-/home/omni}"
[ -d "${OMNI_HOME}" ] || OMNI_HOME="$(pwd)"
cd "${OMNI_HOME}"

CMD="${1:-help}"
shift || true

case "${CMD}" in
    help|--help|-h)
        cat <<'HELP'
═══════════════════════════════════════════════════════════════════════
  Omni-Mind — Quantum-Inspired Symbolic AI (Zig + Rust, no Python)
═══════════════════════════════════════════════════════════════════════

Available commands:
  help       Show this help message
  build      (Re)build all binaries (already built in image)
  test       Run Zig unit tests
  verify     ★ Native Zig verification of 1000 questions (no Python)
  bench      Run the 1000-question benchmark
  repl       Start interactive REPL (ask questions in EN/AR)
  web        Start HTTP API + Web UI (port 8080)
  tcp        Start TCP server (port 19090)
  swarm      Start P2P swarm node (port 18101)
  bash       Open a bash shell
  stats      Show system statistics
  version    Show version info

Examples:
  docker run --rm -it omni-mind verify
  docker run --rm -it -p 8080:8080 omni-mind web
  docker run --rm -it omni-mind repl
  echo "what is energy?" | docker run --rm -i omni-mind repl

═══════════════════════════════════════════════════════════════════════
HELP
        ;;

    build)
        echo "Binaries are already built in this image. To rebuild from source:"
        echo "  docker run --rm -it omni-mind bash"
        echo "  # inside the container:"
        echo "  # zig build -Doptimize=ReleaseFast"
        echo "  # cd swarm && cargo build --release"
        ;;

    test)
        echo "Running Zig unit tests..."
        # We need zig to run tests; if not available, fall back to running verify
        if command -v zig >/dev/null 2>&1; then
            cd /home/omni/src && zig test core_test.zig
        else
            echo "Zig compiler not available in runtime image. Use the builder stage:"
            echo "  docker run --rm -it --target builder omni-mind zig build test"
        fi
        ;;

    verify)
        echo "═══════════════════════════════════════════════════════════════════"
        echo "  Omni-Mind Native Zig Verification (1000 questions)"
        echo "═══════════════════════════════════════════════════════════════════"
        echo ""
        ./omni-verify
        ;;

    bench)
        echo "═══════════════════════════════════════════════════════════════════"
        echo "  Omni-Mind Benchmark (1000 questions)"
        echo "═══════════════════════════════════════════════════════════════════"
        echo ""
        ./omni-bench
        ;;

    repl)
        echo "Starting Omni-Mind REPL (type /help for commands, Ctrl-D to exit)..."
        echo ""
        ./omni-mind
        ;;

    web)
        PORT="${1:-8080}"
        echo "Starting Omni-Mind Web Server on port ${PORT}..."
        echo "  Web UI:  http://localhost:${PORT}"
        echo "  API:     http://localhost:${PORT}/api/query"
        echo "  Health:  http://localhost:${PORT}/api/health"
        echo ""
        ./omni-web --port "${PORT}"
        ;;

    tcp)
        PORT="${1:-19090}"
        echo "Starting Omni-Mind TCP Server on port ${PORT}..."
        echo "  Connect with: nc localhost ${PORT}"
        echo "  Send query:   echo 'QUERY:0:what is energy?' | nc localhost ${PORT}"
        echo ""
        ./omni-mind --serve "${PORT}"
        ;;

    swarm)
        PORT="${1:-18101}"
        PEERS="${2:-}"
        echo "Starting Omni-Mind P2P Swarm Node on port ${PORT}..."
        if [[ -n "${PEERS}" ]]; then
            echo "  Peers: ${PEERS}"
            ./omni-swarm-node --port "${PORT}" --peers "${PEERS}"
        else
            ./omni-swarm-node --port "${PORT}"
        fi
        ;;

    stats)
        echo "=== Omni-Mind System Statistics ==="
        echo ""
        echo "Image contents:"
        ls -lh /home/omni/omni-* 2>/dev/null
        echo ""
        echo "Source code (in builder stage):"
        echo "  Use: docker run --rm -it --target builder omni-mind bash"
        ;;

    version)
        echo "Omni-Mind v0.2.0"
        echo "  Built with: Zig 0.13.0 + Rust stable"
        echo "  Architecture: 7-layer symbolic AI"
        echo "  Knowledge base: 622 axioms × 16 domains"
        echo "  Benchmark: 1000 questions (500 EN + 500 AR)"
        ;;

    bash|sh)
        exec /bin/bash
        ;;

    *)
        echo "Unknown command: ${CMD}"
        echo "Run 'docker run --rm -it omni-mind help' for usage."
        exit 1
        ;;
esac
