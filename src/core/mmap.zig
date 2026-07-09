// src/core/mmap.zig — Zero-copy file-backed storage.
//
// All large data structures (axioms, edges, isomorphisms, living memory)
// live in mmap'd files. We treat their content as typed slices into
// the mmap'd region — no copies, no allocations, just pointer chasing.

const std = @import("std");
const posix = std.posix;

/// Map a file read-only as a typed slice. Zero-copy.
/// The returned slice points directly into the mmap'd region; reading
/// `slice[42].id` is a single pointer chase into the kernel page cache.
pub fn mmapFileRO(comptime T: type, path: []const u8) ![]const T {
    const file = try std.fs.cwd().openFile(path, .{});
    defer file.close();

    const stat = try file.stat();
    if (stat.size == 0) return &[_]T{};

    const n = stat.size / @sizeOf(T);
    if (n * @sizeOf(T) != stat.size) {
        return error.MisalignedFile;
    }

    const ptr = try posix.mmap(
        null,
        stat.size,
        posix.PROT.READ,
        .{ .TYPE = .PRIVATE, .POPULATE = true },
        file.handle,
        0,
    );

    const typed_ptr: [*]const T = @ptrCast(@alignCast(ptr.ptr));
    return typed_ptr[0..n];
}

/// Map a file read-write. Used by Living Memory to persist deltas.
pub fn mmapFileRW(comptime T: type, path: []const u8, capacity: usize) ![]T {
    const file = try std.fs.cwd().createFile(path, .{
        .read = true,
        .truncate = false,
    });
    defer file.close();

    const target_size = capacity * @sizeOf(T);
    try file.setEndPos(target_size);

    const ptr = try posix.mmap(
        null,
        target_size,
        posix.PROT.READ | posix.PROT.WRITE,
        .{ .TYPE = .SHARED },
        file.handle,
        0,
    );

    const typed_ptr: [*]T = @ptrCast(@alignCast(ptr.ptr));
    return typed_ptr[0..capacity];
}

/// Map a raw byte file (for text blobs).
pub fn mmapBytesRO(path: []const u8) ![]const u8 {
    const file = try std.fs.cwd().openFile(path, .{});
    defer file.close();
    const stat = try file.stat();
    if (stat.size == 0) return &[_]u8{};

    const ptr = try posix.mmap(
        null,
        stat.size,
        posix.PROT.READ,
        .{ .TYPE = .PRIVATE, .POPULATE = true },
        file.handle,
        0,
    );
    return ptr[0..stat.size];
}

/// Unmap a previously mapped slice.
pub fn unmap(memory: anytype) void {
    const Slice = @TypeOf(memory);
    const elem_size = @sizeOf(std.meta.Child(Slice));
    const byte_len = memory.len * elem_size;
    posix.munmap(@alignCast(memory.ptr[0..byte_len]));
}

/// Compute a 64-bit Bloom signature from arbitrary bytes.
/// Used everywhere for fast O(1) concept matching.
pub fn bloomSig(text: []const u8) u64 {
    // FNV-1a 64-bit, then spread bits across 64-bit signature
    var h: u64 = 0xcbf29ce484222325;
    for (text) |b| {
        h ^= b;
        h *%= 0x100000001b3;
    }
    // Spread: rotate and XOR to fill all 64 bits
    var sig: u64 = 0;
    var s = h;
    var i: u8 = 0;
    while (i < 8) : (i += 1) {
        sig ^= s;
        s = std.math.rotl(u64, s, 7);
        sig = std.math.rotl(u64, sig, 9);
    }
    return sig;
}

test "bloomSig is deterministic" {
    try std.testing.expectEqual(bloomSig("hello"), bloomSig("hello"));
    try std.testing.expect(bloomSig("hello") != bloomSig("world"));
}

test "bloomSig distributes bits" {
    const s = bloomSig("quantum mechanics");
    // Should have at least 8 set bits (good spread)
    try std.testing.expect(@popCount(s) >= 8);
}
