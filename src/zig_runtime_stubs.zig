// src/zig_runtime_stubs.zig — Minimal Zig runtime stubs needed when
// the Zig static library is linked into a non-Zig binary (e.g. Rust).
//
// Zig inserts stack-probe calls (__zig_probe_stack) on functions with
// large stack frames. When linking into a Rust binary, the Zig
// runtime isn't automatically pulled in, so we provide a no-op here.
//
// Real stack probing is handled by the OS page fault handler on most
// platforms; this stub just satisfies the linker.

// No-op stack probe. The OS will page-fault on stack overflow anyway.
export fn __zig_probe_stack(start: [*]u8, target: [*]u8) callconv(.C) void {
    _ = start;
    _ = target;
    // Intentionally empty: rely on OS page-fault protection.
}
