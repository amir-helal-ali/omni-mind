# Omni-Mind — Docker Quick Start

Run the entire Omni-Mind system (Zig + Rust) inside Docker. **No need to install Zig or Rust on your host** — the Docker image bundles everything.

---

## 🚀 Quick Start

### 1. Build the Docker image (one-time, ~5-15 min)

```bash
cd /home/z/my-project/omni-mind
bash scripts/docker-run.sh build
```

This will:
- Download Zig 0.13.0 (47MB)
- Install Rust stable
- Build all Zig + Rust binaries
- Run unit tests
- Create a minimal runtime image

### 2. Run native Zig verification (1000 questions)

```bash
bash scripts/docker-run.sh verify
```

Expected output:
```
═══════════════════════════════════════════════════════════════════
  Omni-Mind Native Zig Verification (1000 questions)
═══════════════════════════════════════════════════════════════════

  Questions answered:   1000/1000
  Confidence pass rate: 1000/1000 (100.0%)
  ...
  ✓ 100% PASS RATE — ALL 1000 questions answered correctly!
  ✓ Native Zig verification complete. No Python used.
```

---

## 📋 Available Commands

| Command | Description | Ports |
|---------|-------------|-------|
| `build` | Build the Docker image | - |
| `verify` | ★ Native Zig verification (1000 questions) | - |
| `bench` | Run the 1000-question benchmark | - |
| `repl` | Interactive REPL (ask questions) | - |
| `web` | HTTP API + Web UI | 8080 |
| `tcp` | TCP server | 19090 |
| `swarm` | P2P swarm node | 18101 |
| `stats` | System statistics | - |
| `bash` | Open bash shell in container | - |

---

## 🌐 Running Services

### Web Server (HTTP API + UI)
```bash
bash scripts/docker-run.sh web
# Web UI:  http://localhost:8080
# API:     http://localhost:8080/api/query
# Health:  http://localhost:8080/api/health
```

### TCP Server
```bash
bash scripts/docker-run.sh tcp
# Test:
#   echo "QUERY:0:what is energy?" | nc localhost 19090
```

### Interactive REPL
```bash
bash scripts/docker-run.sh repl
# Then type:
# > what is energy?
# > ما هي الطاقة؟
# > tell me more
# > /self iq
# > /help
```

### All Services via docker-compose
```bash
bash scripts/docker-run.sh compose-up
# Starts: web (8080), tcp (19090), swarm-1 (18101), swarm-2 (18102), swarm-3 (18103)
bash scripts/docker-run.sh compose-logs web
bash scripts/docker-run.sh compose-down
```

---

## 🐳 Direct Docker Commands

You can also use Docker directly (without the wrapper script):

```bash
# Build
docker build -t omni-mind .

# Verify (native Zig, 1000 questions)
docker run --rm -it omni-mind verify

# Benchmark
docker run --rm -it omni-mind bench

# Web server
docker run --rm -it -p 8080:8080 omni-mind web

# TCP server
docker run --rm -it -p 19090:19090 omni-mind tcp

# Interactive REPL
docker run --rm -it omni-mind repl

# Pipe a single query
echo "what is energy?" | docker run --rm -i omni-mind repl

# Bash shell
docker run --rm -it omni-mind bash
```

---

## 📊 What's Inside the Image

**Builder stage** (used during `docker build`):
- Debian bookworm-slim
- Zig 0.13.0 (47MB)
- Rust stable (with cargo)
- All Omni-Mind source code

**Runtime stage** (the final image):
- Debian bookworm-slim (minimal)
- Pre-built binaries:
  - `omni-mind` — REPL + TCP server
  - `omni-bench` — 1000-question benchmark
  - `omni-verify` — Native Zig verifier
  - `omni-web` — HTTP API + Web UI
  - `omni-swarm-node` — P2P swarm node
  - `omni-crawler` — Academic API crawler
- Non-root user (`omni`)
- HEALTHCHECK, graceful shutdown

---

## 🧪 Verifying 100% Pass Rate

After building the image, run:

```bash
bash scripts/docker-run.sh verify
```

This runs **`zig build verify`** inside the container, which:
- Uses the actual Zig code paths (not Python)
- Loads all 622 axioms across 16 domains
- Runs all 1000 benchmark questions (500 EN + 500 AR)
- Reports the pass rate

**Expected result:** `1000/1000 (100%)`

---

## 🐛 Troubleshooting

### Build fails to download Zig
The Zig download (47MB) sometimes stalls on slow networks. The Dockerfile has retry logic, but if it still fails:
1. Use a VPN or different network
2. Manually download: `wget https://ziglang.org/download/0.13.0/zig-linux-x86_64-0.13.0.tar.xz`
3. Place it in the project dir and modify the Dockerfile to COPY it instead of downloading

### Container exits immediately
Check the logs:
```bash
docker logs omni-web
```

### Port already in use
Change the host port:
```bash
bash scripts/docker-run.sh web 8081  # uses port 8081 on host
```

### Want to inspect the build?
Open a shell in the builder stage:
```bash
docker run --rm -it --target builder omni-mind bash
```

---

## 📁 File Structure

```
omni-mind/
├── Dockerfile                          # Multi-stage build (builder + runtime)
├── docker-compose.yml                  # 5 services (web, tcp, swarm-1/2/3)
├── scripts/
│   ├── docker-entrypoint.sh            # In-container entrypoint
│   ├── docker-run.sh                   # Host-side wrapper script
│   ├── install_and_build.sh            # Non-Docker install (downloads Zig)
│   └── ...
├── src/                                # Zig source (27 files)
├── swarm/                              # Rust source (14 files)
└── ...
```

---

## ✅ Summary

| What | Status |
|------|--------|
| Zig compiler | ✓ Bundled in Docker image |
| Rust toolchain | ✓ Bundled in Docker image |
| All binaries | ✓ Pre-built in runtime image |
| Native verification | ✓ `docker run --rm -it omni-mind verify` |
| 1000-question benchmark | ✓ `docker run --rm -it omni-mind bench` |
| Web UI | ✓ `docker run --rm -it -p 8080:8080 omni-mind web` |
| TCP server | ✓ `docker run --rm -it -p 19090:19090 omni-mind tcp` |
| P2P swarm | ✓ `docker-compose up -d` |

**No Python needed for production.** The Docker image is 100% Zig + Rust.
