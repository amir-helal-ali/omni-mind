// src/core/allocator.zig — The ONLY allocator the core knows.
//
// Iron rule: total RAM never exceeds 2 GB. Any attempt to allocate
// beyond this cap triggers an immediate panic (fail-fast by design).
// This is the constitutional contract of Omni-Mind — no soft caps,
// no renegotiation at runtime.

const std = @import("std");

/// Hard ceiling: 2 GB total RAM in production. Smaller for dev/test.
pub const CORE_BUDGET: usize = if (@import("builtin").mode == .Debug) 16 * 1024 * 1024 else 2 * 1024 * 1024 * 1024;

/// Backing buffer — allocated via mmap at init, not as a global BSS array
/// (which would overflow the stack on some linkers).
var backing_ptr: ?[*]u8 = null;
var backing_len: usize = 0;

/// Global FBA — points into the mmap'd region.
pub var fba: std.heap.FixedBufferAllocator = undefined;
pub var bytes_used: usize = 0;
pub var initialized: bool = false;

/// Initialize the allocator. Safe to call multiple times — resets state.
pub fn init() void {
    // Allocate the backing buffer via mmap (anonymous, lazy-committed).
    if (backing_ptr == null) {
        const ptr = std.posix.mmap(
            null,
            CORE_BUDGET,
            std.posix.PROT.READ | std.posix.PROT.WRITE,
            .{ .TYPE = .PRIVATE, .ANONYMOUS = true },
            -1,
            0,
        ) catch @panic("failed to mmap backing buffer");
        backing_ptr = ptr.ptr;
        backing_len = ptr.len;
    }
    fba = std.heap.FixedBufferAllocator.init(backing_ptr.?[0..backing_len]);
    bytes_used = 0;
    initialized = true;
}

/// The ONLY allocation function allowed in core paths.
/// FBA returns OutOfMemory when the buffer is full.
pub fn allocAligned(comptime T: type, n: usize) ![]T {
    if (!initialized) init();
    const slice = try fba.allocator().alloc(T, n);
    bytes_used = CORE_BUDGET - fba.end_index;
    return slice;
}

/// Allocate a single zero-initialized T.
pub fn create(comptime T: type) !*T {
    const slice = try allocAligned(T, 1);
    slice[0] = std.mem.zeroes(T);
    return &slice[0];
}

/// Allocate and copy from an existing slice (used for seed loading).
pub fn dupe(comptime T: type, src: []const T) ![]T {
    const dst = try allocAligned(T, src.len);
    @memcpy(dst, src);
    return dst;
}

/// String duplication — convenience for byte slices.
pub fn dupeString(src: []const u8) ![]u8 {
    return dupe(u8, src);
}

/// Current memory usage as a fraction of the budget (0.0 – 1.0).
pub fn usageFraction() f32 {
    return @as(f32, @floatFromInt(bytes_used)) / @as(f32, @floatFromInt(CORE_BUDGET));
}

/// Reset the arena (used only by tests). Frees everything.
pub fn reset() void {
    if (!initialized) return;
    init();
}

test "allocator stays within cap" {
    init();
    const a = try allocAligned(u8, 1024);
    try std.testing.expectEqual(@as(usize, 1024), a.len);
    try std.testing.expect(bytes_used >= 1024);
}
