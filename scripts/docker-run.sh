#!/usr/bin/env bash
# scripts/docker-run.sh — Easy wrapper for running Omni-Mind in Docker.
#
# This script handles building the image and running any command inside it.
# No need to install Zig or Rust on your host — Docker does it all.
#
# Usage:
#   bash scripts/docker-run.sh build         # build the Docker image
#   bash scripts/docker-run.sh verify        # native Zig verification
#   bash scripts/docker-run.sh bench         # 1000-question benchmark
#   bash scripts/docker-run.sh repl          # interactive REPL
#   bash scripts/docker-run.sh web           # HTTP API on port 8080
#   bash scripts/docker-run.sh tcp           # TCP server on port 19090
#   bash scripts/docker-run.sh stats         # system statistics
#   bash scripts/docker-run.sh help          # show all commands

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
IMAGE_NAME="omni-mind:latest"

cd "${PROJECT_DIR}"

# ─── Helper: ensure image is built ─────────────────────────────────
ensure_image() {
    if ! docker image inspect "${IMAGE_NAME}" >/dev/null 2>&1; then
        echo "Image '${IMAGE_NAME}' not found. Building..."
        build_image
    fi
}

# ─── Helper: build the Docker image ────────────────────────────────
build_image() {
    echo "═══════════════════════════════════════════════════════════════════"
    echo "  Building Omni-Mind Docker Image"
    echo "  (This includes downloading Zig 0.13.0 + Rust — may take 5-15 min)"
    echo "═══════════════════════════════════════════════════════════════════"
    docker build -t "${IMAGE_NAME}" .
    echo ""
    echo "✓ Image built: ${IMAGE_NAME}"
    docker images "${IMAGE_NAME}"
}

# ─── Main ──────────────────────────────────────────────────────────
CMD="${1:-help}"
shift || true

case "${CMD}" in
    build)
        build_image
        ;;

    verify|bench|repl|stats|help|version)
        ensure_image
        echo "Running: docker run --rm -it ${IMAGE_NAME} ${CMD}"
        docker run --rm -it "${IMAGE_NAME}" "${CMD}"
        ;;

    web)
        ensure_image
        PORT="${1:-8080}"
        echo "Starting web server on port ${PORT}..."
        echo "  Web UI:  http://localhost:${PORT}"
        echo "  API:     http://localhost:${PORT}/api/query"
        docker run --rm -it -p "${PORT}:8080" "${IMAGE_NAME}" web
        ;;

    tcp)
        ensure_image
        PORT="${1:-19090}"
        echo "Starting TCP server on port ${PORT}..."
        docker run --rm -it -p "${PORT}:19090" "${IMAGE_NAME}" tcp
        ;;

    swarm)
        ensure_image
        PORT="${1:-18101}"
        PEERS="${2:-}"
        if [[ -n "${PEERS}" ]]; then
            docker run --rm -it -p "${PORT}:18101" "${IMAGE_NAME}" swarm 18101 "${PEERS}"
        else
            docker run --rm -it -p "${PORT}:18101" "${IMAGE_NAME}" swarm
        fi
        ;;

    bash|shell)
        ensure_image
        docker run --rm -it "${IMAGE_NAME}" bash
        ;;

    compose-up)
        echo "Starting all services via docker-compose..."
        docker-compose up -d
        docker-compose ps
        ;;

    compose-down)
        echo "Stopping all services..."
        docker-compose down
        ;;

    compose-logs)
        docker-compose logs -f "${1:-}"
        ;;

    *)
        cat <<'USAGE'
Omni-Mind Docker Runner

Usage: bash scripts/docker-run.sh <command> [args]

Commands:
  build          Build the Docker image (downloads Zig + Rust, ~5-15 min)
  verify         ★ Native Zig verification of 1000 questions
  bench          Run the 1000-question benchmark
  repl           Interactive REPL (ask questions in EN/AR)
  web [port]     HTTP API + Web UI (default port 8080)
  tcp [port]     TCP server (default port 19090)
  swarm [port] [peers]  P2P swarm node
  stats          Show system statistics
  bash           Open a bash shell in the container
  compose-up     Start all services via docker-compose
  compose-down   Stop all services
  compose-logs [service]  Follow logs
  help           Show this help
  version        Show version info

Examples:
  bash scripts/docker-run.sh build
  bash scripts/docker-run.sh verify
  bash scripts/docker-run.sh repl
  bash scripts/docker-run.sh web 8080
  echo "what is energy?" | docker run --rm -i omni-mind:latest repl
USAGE
        exit 1
        ;;
esac
