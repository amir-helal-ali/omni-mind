# Omni-Mind Makefile — Professional build automation
#
# Usage:
#   make build      — Build everything (Zig + Rust)
#   make test       — Run all tests
#   make bench      — Run 100-question benchmark
#   make docker     — Build Docker images
#   make run-web    — Start web server
#   make run-tcp    — Start TCP server
#   make clean      — Remove all build artifacts
#   make release    — Create release tarball
#   make help       — Show all targets

.ZPHONY: all build build-zig build-rust test test-zig test-rust bench \
         docker docker-up docker-down run-web run-tcp run-repl run-swarm \
         clean release install help

# ─── Variables ────────────────────────────────────────
ZIG ?= zig
CARGO ?= cargo
VERSION := 0.2.0
DIST_DIR := dist

# ─── Default target ───────────────────────────────────
all: build

# ─── Build ────────────────────────────────────────────
build: build-zig build-rust

build-zig:
	@echo "── Building Zig core ──"
	$(ZIG) build

build-rust:
	@echo "── Building Rust swarm ──"
	cd swarm && $(CARGO) build --release

# ─── Tests ────────────────────────────────────────────
test: test-zig test-rust

test-zig:
	@echo "── Running Zig tests ──"
	$(ZIG) build test

test-rust:
	@echo "── Running Rust tests ──"
	cd swarm && $(CARGO) test

# ─── Benchmark ────────────────────────────────────────
bench:
	@echo "── Running 100-question benchmark ──"
	$(ZIG) build bench
	./zig-out/bin/omni-bench

# ─── Docker ───────────────────────────────────────────
docker:
	@echo "── Building Docker images ──"
	docker build -t omni-mind:$(VERSION) .
	docker build -t omni-mind-web:$(VERSION) --target web .

docker-up:
	docker-compose up -d

docker-down:
	docker-compose down

# ─── Run ──────────────────────────────────────────────
run-web: build-rust
	cd swarm && ./target/release/omni-web --port 8080

run-tcp: build-zig
	./zig-out/bin/omni-mind --serve 19090

run-repl: build-zig
	./zig-out/bin/omni-mind --repl

run-swarm: build-rust
	cd swarm && ./target/release/omni-swarm-node --port 18101

# ─── Clean ────────────────────────────────────────────
clean:
	rm -rf zig-out .zig-cache
	rm -rf swarm/target
	rm -rf $(DIST_DIR)
	rm -f omni_memory.bin *.log

# ─── Release ──────────────────────────────────────────
release: build
	@echo "── Creating release $(VERSION) ──"
	mkdir -p $(DIST_DIR)
	cp zig-out/bin/omni-mind $(DIST_DIR)/
	cp zig-out/bin/omni-bench $(DIST_DIR)/
	cp swarm/target/release/omni-swarm-node $(DIST_DIR)/
	cp swarm/target/release/omni-web $(DIST_DIR)/
	cp swarm/target/release/omni-crawler $(DIST_DIR)/
	tar -czf omni-mind-$(VERSION)-linux-x86_64.tar.gz -C $(DIST_DIR) .
	@echo "Release: omni-mind-$(VERSION)-linux-x86_64.tar.gz"

# ─── Install ──────────────────────────────────────────
install: build
	@echo "── Installing to /usr/local/bin ──"
	sudo cp zig-out/bin/omni-mind /usr/local/bin/
	sudo cp zig-out/bin/omni-bench /usr/local/bin/
	sudo cp swarm/target/release/omni-swarm-node /usr/local/bin/
	sudo cp swarm/target/release/omni-web /usr/local/bin/
	@echo "Installed. Try: omni-mind --demo"

# ─── Help ─────────────────────────────────────────────
help:
	@echo "Omni-Mind v$(VERSION) — Build targets:"
	@echo ""
	@echo "  make build       Build everything (Zig + Rust)"
	@echo "  make test        Run all tests"
	@echo "  make bench       Run 100-question benchmark"
	@echo "  make docker      Build Docker images"
	@echo "  make docker-up   Start services via docker-compose"
	@echo "  make run-web     Start web server (port 8080)"
	@echo "  make run-tcp     Start TCP server (port 19090)"
	@echo "  make run-repl    Start interactive REPL"
	@echo "  make run-swarm   Start P2P swarm node"
	@echo "  make clean       Remove build artifacts"
	@echo "  make release     Create release tarball"
	@echo "  make install     Install binaries to /usr/local/bin"
	@echo ""
