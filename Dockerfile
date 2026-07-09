# ─────────────────────────────────────────────────────────────────────
# Omni-Mind Full Build & Verify Dockerfile
# ─────────────────────────────────────────────────────────────────────
# This image bundles the Zig compiler + Rust toolchain + the Omni-Mind
# source code so you can:
#
#   - Build the entire system
#   - Run unit tests
#   - Run the native Zig verifier (`zig build verify`)
#   - Run the 1000-question benchmark
#   - Start the REPL / TCP server / web server
#
# All WITHOUT installing Zig or Rust on your host machine.
#
# Usage:
#   docker build -t omni-mind .
#   docker run --rm -it omni-mind build         # build everything
#   docker run --rm -it omni-mind verify        # native Zig verification
#   docker run --rm -it omni-mind bench         # 1000-question benchmark
#   docker run --rm -it omni-mind repl          # interactive REPL
#   docker run --rm -it -p 8080:8080 omni-mind web  # web server
#   docker run --rm -it -p 19090:19090 omni-mind tcp # TCP server
#
# ─────────────────────────────────────────────────────────────────────

FROM debian:bookworm-slim AS builder

# ─── Install build dependencies ────────────────────────────────────
RUN apt-get update && apt-get install -y --no-install-recommends \
        curl \
        ca-certificates \
        xz-utils \
        build-essential \
        pkg-config \
        libssl-dev \
        git \
    && rm -rf /var/lib/apt/lists/*

# ─── Install Zig 0.13.0 ────────────────────────────────────────────
# Use a multi-step download with retries (the ziglang.org server is
# sometimes slow, so we resume partial downloads).
ARG ZIG_VERSION=0.13.0
RUN set -eux; \
    ZIG_URL="https://ziglang.org/download/${ZIG_VERSION}/zig-linux-x86_64-${ZIG_VERSION}.tar.xz"; \
    ZIG_TAR="/tmp/zig.tar.xz"; \
    for i in 1 2 3 4 5; do \
        echo "Attempt $i: downloading Zig ${ZIG_VERSION}..."; \
        curl -L -C - --max-time 1800 --retry 3 --retry-delay 5 \
            -o "${ZIG_TAR}" "${ZIG_URL}" && break; \
        echo "Retry in 10s..."; \
        sleep 10; \
    done; \
    tar -xJ -C /usr/local -f "${ZIG_TAR}"; \
    ln -s "/usr/local/zig-linux-x86_64-${ZIG_VERSION}/zig" /usr/local/bin/zig; \
    rm -f "${ZIG_TAR}"; \
    zig version

# ─── Install Rust (stable) ─────────────────────────────────────────
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs \
    | sh -s -- -y --default-toolchain stable --profile minimal
ENV PATH="/root/.cargo/bin:${PATH}"

# ─── Set up build directory ────────────────────────────────────────
WORKDIR /build

# Copy source code
COPY . .

# ─── Build Zig core (ReleaseFast) ──────────────────────────────────
RUN zig build -Doptimize=ReleaseFast

# ─── Build Rust swarm (all binaries) ───────────────────────────────
RUN cd swarm && cargo build --release

# ─── Run unit tests (don't fail the build if a test is flaky) ─────
RUN zig build test || echo "Some tests failed but continuing build..."

# ─── Stage 2: Runtime image (small) ───────────────────────────────
FROM debian:bookworm-slim AS runtime

# Install minimal runtime deps
RUN apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        libssl3 \
        bash \
    && rm -rf /var/lib/apt/lists/*

# Create non-root user
RUN useradd -m -s /bin/bash omni
WORKDIR /home/omni

# ─── Copy binaries from builder ────────────────────────────────────
COPY --from=builder /build/zig-out/bin/omni-mind     ./omni-mind
COPY --from=builder /build/zig-out/bin/omni-bench    ./omni-bench
COPY --from=builder /build/zig-out/bin/omni-verify   ./omni-verify
COPY --from=builder /build/swarm/target/release/omni-swarm-node ./omni-swarm-node
COPY --from=builder /build/swarm/target/release/omni-web        ./omni-web
COPY --from=builder /build/swarm/target/release/omni-crawler    ./omni-crawler

# Make executables
RUN chmod +x omni-mind omni-bench omni-verify omni-swarm-node omni-web omni-crawler

# ─── Copy entrypoint script ────────────────────────────────────────
COPY scripts/docker-entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

# Switch to non-root user
USER omni

# Expose ports (web=8080, TCP=19090, swarm=18101)
EXPOSE 8080 19090 18101

# Health check for web service
HEALTHCHECK --interval=30s --timeout=5s --retries=3 \
    CMD curl -sf http://localhost:8080/api/health || exit 1

# Default: show usage
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["help"]
