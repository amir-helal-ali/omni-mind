// src/l3/analogy.zig — Deep Analogy Engine (Quantum Tunneling).
//
// When direct reasoning hits a wall (no candidate axioms), the
// engine "tunnels" through another domain by finding a
// mathematical isomorphism. This is cross-domain creativity.

const std = @import("std");
const bloomSig = @import("../core/mmap.zig").bloomSig;
const allocator = @import("../core/allocator.zig");

/// An isomorphism entry: source structure ↔ target structure + transforms.
pub const Isomorphism = extern struct {
    src_domain: u8, // 1B
    dst_domain: u8, // 1B
    _pad: [2]u8, // 2B
    src_signature: u64, // 8B — Bloom signature of source math structure
    dst_signature: u64, // 8B — target structure signature
    description_offset: u32, // 4B — into descriptions blob
    description_len: u32, // 4B
    confidence: f32, // 4B — how strong the isomorphism is
    _pad2: [4]u8, // 4B

};
comptime {
        if (@sizeOf(Isomorphism) != 40) {
            @compileError("Isomorphism must be 40 bytes");
        }
}

pub const AnalogyEngine = struct {
    table: []Isomorphism,
    descriptions: []const u8,
    count: usize = 0,

    pub fn init(cap: usize, desc_cap: usize) !AnalogyEngine {
        const t = try allocator.allocAligned(Isomorphism, cap);
        const d = try allocator.allocAligned(u8, desc_cap);
        @memset(d, 0);
        @memset(t, std.mem.zeroes(Isomorphism));
        return .{
            .table = t,
            .descriptions = d,
            .count = 0,
        };
    }

    /// Add an isomorphism entry.
    pub fn add(
        self: *AnalogyEngine,
        src_domain: u8,
        dst_domain: u8,
        src_text: []const u8,
        dst_text: []const u8,
        description: []const u8,
        confidence: f32,
    ) !u32 {
        if (self.count >= self.table.len) return error.TableFull;
        const idx: u32 = @intCast(self.count);

        // Find description offset (append to descriptions blob).
        var desc_off: u32 = 0;
        var i: usize = 0;
        while (i < self.descriptions.len and self.descriptions[i] != 0) : (i += 1) {}
        if (i + description.len > self.descriptions.len) return error.DescFull;
        desc_off = @intCast(i);
        @memcpy(@constCast(self.descriptions[desc_off .. desc_off + description.len]), description);

        self.table[idx] = .{
            .src_domain = src_domain,
            .dst_domain = dst_domain,
            ._pad = .{ 0, 0 },
            .src_signature = bloomSig(src_text),
            .dst_signature = bloomSig(dst_text),
            .description_offset = desc_off,
            .description_len = @intCast(description.len),
            .confidence = confidence,
            ._pad2 = .{ 0, 0, 0, 0 },
        };
        self.count += 1;
        return idx;
    }

    /// Tunnel: find an isomorphism from src_domain matching query_sig.
    /// Returns the destination domain + the isomorphism entry, or null.
    pub fn tunnel(
        self: *const AnalogyEngine,
        src_domain: u8,
        query_sig: u64,
    ) ?struct { iso: Isomorphism, dst_domain: u8 } {
        for (self.table[0..self.count]) |iso| {
            if (iso.src_domain != src_domain) continue;
            const overlap = @popCount(iso.src_signature & query_sig);
            if (overlap >= 6) { // strong match threshold
                return .{ .iso = iso, .dst_domain = iso.dst_domain };
            }
        }
        return null;
    }
};

test "analogy engine tunnel" {
    allocator.init();
    var eng = try AnalogyEngine.init(16, 4096);
    _ = try eng.add(0, 5, "heat diffusion equation", "schrodinger equation", "Both obey u_t = k * laplacian(u)", 0.9);

    const sig = bloomSig("heat diffusion");
    const r = eng.tunnel(0, sig);
    try std.testing.expect(r != null);
    try std.testing.expectEqual(@as(u8, 5), r.?.dst_domain);
}
