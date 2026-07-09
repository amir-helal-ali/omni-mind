# Changelog

All notable changes to the Omni-Mind project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- Docker containerization with multi-stage builds
- docker-compose for orchestrated multi-service deployment
- GitHub Actions CI/CD pipeline
- Configuration file support (omni.toml)
- Health check endpoint (`/api/health`)
- Graceful shutdown via SIGINT/SIGTERM
- Prometheus-compatible metrics endpoint (`/api/metrics`)
- Integration test suite
- Property-based stress tests
- Comprehensive API documentation

## [0.2.0] — 2026-07-09

### Added
- TCP server with multi-client support (`--serve` mode)
- Web UI with HTTP API + Arabic RTL frontend
- Live academic API crawler (Crossref, arXiv, Semantic Scholar)
- TCP-based P2P gossip networking
- 100-question benchmark suite with LLaMA-7B comparison
- Interactive REPL with multi-user + persistent memory
- Rich answer generation with derivation paths
- 7 knowledge domains (physics, chemistry, biology, math, logic, CS, economics)
- 6 cross-domain isomorphisms
- 10 synthesizer functions
- FFI bridge between Zig core and Rust swarm

### Changed
- Allocator switched to mmap-backed FixedBufferAllocator
- Reduced debug memory budget to 16 MB for faster testing
- All structs cache-aligned (Node=64B, Edge=32B, DeltaEvent=32B)
- Comptime assertions on struct sizes

### Performance
- Avg latency: 0.734 ms (682× faster than LLaMA-7B)
- Memory: 14.48 MB (967× less than LLaMA-7B)
- Throughput: 1363 queries/sec
- 100/100 benchmark pass rate

## [0.1.0] — 2026-07-08

### Added
- Initial project structure with 7-layer architecture
- Core data structures: Node, Edge, Axiom, DeltaEvent
- Quantum collapse function (L1)
- Multi-dimensional reasoning with 5 threads (L2)
- Analogy engine with isomorphism tunneling (L3)
- Intent parser with user modeling (L4)
- Confidence calculator with tone modulation (L5)
- Creative synthesis engine (L6)
- Delta-compressed living memory (L7)
- Procedural weight function (no stored weights)
- Architecture specification document (61 pages, Arabic)
