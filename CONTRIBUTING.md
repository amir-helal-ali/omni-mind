# Contributing to Omni-Mind

Thank you for your interest in contributing to Omni-Mind! This document outlines the process for contributing to the project.

## Code of Conduct

Be respectful, constructive, and professional. We're building a revolutionary AI system together.

## Getting Started

### Prerequisites

- **Zig 0.13+** — [ziglang.org](https://ziglang.org/download/)
- **Rust 1.75+** — [rustup.rs](https://rustup.rs)
- **curl** — for the crawler's HTTPS fallback

### Development Setup

```bash
# Clone the repository
git clone https://github.com/your-org/omni-mind.git
cd omni-mind

# Build the Zig core
zig build

# Build the Rust swarm
cd swarm && cargo build --release

# Run tests
zig build test
cargo test

# Run the benchmark
zig build bench && ./zig-out/bin/omni-bench
```

## Architecture Overview

Omni-Mind has 7 layers, each in its own directory:

| Layer | Path | Responsibility |
|-------|------|----------------|
| Core | `src/core/` | Allocator, mmap, Node/Edge, Graph |
| L1 | `src/l1/` | Axioms, collapse, procedural weights |
| L2 | `src/l2/` | 5 parallel reasoning threads |
| L3 | `src/l3/` | Analogy engine (isomorphism tunneling) |
| L4 | `src/l4/` | Intent parsing, user modeling |
| L5 | `src/l5/` | Confidence calculation, tone |
| L6 | `src/l6/` | Creative synthesis |
| L7 | `src/l7/` | Delta-compressed living memory |

The Rust swarm (`swarm/`) handles networking, P2P gossip, and web UI.

## Coding Standards

### Zig

- **Cache alignment**: All hot-path structs must be cache-line sized (64 bytes). Use `comptime` assertions:
  ```zig
  comptime {
      if (@sizeOf(MyStruct) != 64) {
          @compileError("MyStruct must be exactly 64 bytes");
      }
  }
  ```

- **Zero-copy**: No heap allocations in hot paths. Use `allocAligned` from `core/allocator.zig`.

- **Error handling**: Use Zig's error unions. Never `catch unreachable` in production code.

- **Naming**: `camelCase` for functions and variables, `PascalCase` for types.

- **Comments**: Document every `pub` function with `///` doc comments.

### Rust

- **Safety**: Minimize `unsafe`. Document every `unsafe` block with a safety comment.

- **Error handling**: Use `Result<T, E>`. Define custom error types with `thiserror`.

- **Naming**: `snake_case` for functions and variables, `PascalCase` for types.

- **Documentation**: Every `pub` item must have `///` doc comments.

## Pull Request Process

1. **Fork** the repository and create a feature branch:
   ```bash
   git checkout -b feature/my-feature
   ```

2. **Write tests** for your changes. All new features must have tests.

3. **Ensure CI passes**:
   ```bash
   zig build test
   cd swarm && cargo test
   zig build bench
   ```

4. **Update documentation** if you change APIs or architecture.

5. **Update CHANGELOG.md** under the `[Unreleased]` section.

6. **Submit a PR** with a clear description of what changed and why.

## Commit Message Format

```
<type>(<scope>): <subject>

<body>

<footer>
```

Types: `feat`, `fix`, `docs`, `refactor`, `test`, `chore`, `perf`

Example:
```
feat(l3): add catalyst-to-quantum-tunneling isomorphism

Add a new cross-domain analogy entry linking chemistry catalysts
to quantum tunneling, enabling the engine to explain reaction
rate acceleration via potential energy barrier lowering.
```

## Testing

### Unit Tests

```bash
# Zig unit tests
zig build test

# Rust unit tests
cd swarm && cargo test
```

### Integration Tests

```bash
# Multi-client TCP server test
python3 scripts/test_client.py

# 3-node swarm test
python3 scripts/test_swarm.py
```

### Benchmarks

```bash
# 100-question benchmark
zig build bench && ./zig-out/bin/omni-bench
```

## Release Process

1. Update `CHANGELOG.md` with the new version
2. Update `build.zig.zon` version
3. Tag the release: `git tag v0.X.0`
4. Push tags: `git push --tags`
5. CI will build release binaries automatically

## Questions?

Open an issue with the `question` label, or reach out to the maintainers.
