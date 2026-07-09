// src/ffi.zig — C ABI exports for the Rust swarm layer.
//
// The Zig core exposes a small C ABI that the Rust swarm calls
// via extern "C". All data crossing the boundary is via raw
// pointers with explicit lifetimes — no shared ownership.

const std = @import("std");
const core = @import("core.zig");
const allocator = @import("core/allocator.zig");

// Pull in runtime stubs so they get linked into the static library.
comptime {
    _ = @import("zig_runtime_stubs.zig");
}

/// CoreStats — returned by omni_stats.
pub const CoreStats = extern struct {
    bytes_used: usize,
    bytes_budget: usize,
    node_count: usize,
    edge_count: usize,
    axiom_count: usize,
};

/// omni_query — process a query string, return answer in `out_buf`.
/// Returns: answer length (>0) on success, negative on error.
///
/// Safety: query_ptr must be NUL-terminated UTF-8. out_buf must
/// be at least out_len bytes. Caller retains ownership of both.
export fn omni_query(
    query_ptr: [*:0]const u8,
    out_buf: [*]u8,
    out_len: u32,
) callconv(.C) i32 {
    const q = std.mem.span(query_ptr);
    var buf = out_buf[0..out_len];

    const result = core.runQuery(q, &buf) catch |err| {
        std.log.err("omni_query failed: {}", .{err});
        return -1;
    };

    if (result.len > out_len) return -2;
    return @intCast(result.len);
}

/// omni_inject_axiom — called by the swarm when a new axiom is gossiped in.
/// Returns: 0 on success, negative on error.
export fn omni_inject_axiom(
    domain: u8,
    axiom_ptr: [*:0]const u8,
    confidence: f32,
) callconv(.C) i32 {
    const text = std.mem.span(axiom_ptr);
    core.ingestAxiom(domain, text, confidence) catch return -1;
    return 0;
}

/// omni_stats — return current memory + node stats.
export fn omni_stats() callconv(.C) CoreStats {
    return .{
        .bytes_used = allocator.bytes_used,
        .bytes_budget = allocator.CORE_BUDGET,
        .node_count = if (core.graph) |*g| g.nodes.count else 0,
        .edge_count = if (core.graph) |*g| g.edges.count else 0,
        .axiom_count = if (core.store) |*s| s.count else 0,
    };
}

/// omni_bootstrap — initialize the core. Returns 0 on success.
export fn omni_bootstrap() callconv(.C) i32 {
    core.bootstrap() catch return -1;
    return 0;
}

/// omni_shutdown — flush living memory to disk.
export fn omni_shutdown() callconv(.C) void {
    core.shutdown();
}
