// src/l6/synthesis.zig — Creative Synthesis Engine.
//
// Merge functions from disparate domains to generate unprecedented
// solutions. This is true creativity: mathematical composition,
// not statistical recombination.

const std = @import("std");
const allocator = @import("../core/allocator.zig");

pub const FunctionHandle = extern struct {
    id: u32, // 4B — index into registry
    domain: u8, // 1B
    arity: u8, // 1B
    _pad: [2]u8, // 2B
    signature: u64, // 8B — input/output type signature (Bloom)

};
comptime {
        if (@sizeOf(FunctionHandle) != 16) {
            @compileError("FunctionHandle must be 16 bytes");
        }
}

pub const SynthesisResult = struct {
    composed_fn: FunctionHandle,
    novelty: f32,
    usefulness: f32,
    surprise: f32,
};

pub const Synthesizer = struct {
    registry: []FunctionHandle,
    composed_log: []u64, // signatures of past compositions
    log_len: usize = 0,

    pub fn init(reg_cap: usize, log_cap: usize) !Synthesizer {
        const r = try allocator.allocAligned(FunctionHandle, reg_cap);
        const l = try allocator.allocAligned(u64, log_cap);
        @memset(r, std.mem.zeroes(FunctionHandle));
        @memset(l, 0);
        return .{
            .registry = r,
            .composed_log = l,
        };
    }

    pub fn registerFunction(
        self: *Synthesizer,
        domain: u8,
        arity: u8,
        sig_text: []const u8,
    ) !u32 {
        var i: usize = 0;
        while (i < self.registry.len and self.registry[i].signature != 0) : (i += 1) {}
        if (i >= self.registry.len) return error.RegistryFull;
        self.registry[i] = .{
            .id = @intCast(i),
            .domain = domain,
            .arity = arity,
            ._pad = .{ 0, 0 },
            .signature = @import("../core/mmap.zig").bloomSig(sig_text),
        };
        return @intCast(i);
    }

    /// Try to synthesize a new function from domain_a × domain_b.
    pub fn synthesize(
        self: *Synthesizer,
        target_sig: u64,
        domain_a: u8,
        domain_b: u8,
    ) ?SynthesisResult {
        var cands_a: [16]FunctionHandle = undefined;
        var cands_b: [16]FunctionHandle = undefined;
        var n_a: usize = 0;
        var n_b: usize = 0;

        for (self.registry) |fh| {
            if (fh.signature == 0) continue;
            if (fh.domain == domain_a and n_a < 16 and
                @popCount(fh.signature & target_sig) >= 3)
            {
                cands_a[n_a] = fh;
                n_a += 1;
            }
            if (fh.domain == domain_b and n_b < 16 and
                @popCount(fh.signature & target_sig) >= 3)
            {
                cands_b[n_b] = fh;
                n_b += 1;
            }
        }

        var best: ?SynthesisResult = null;
        var best_score: f32 = 0;

        for (cands_a[0..n_a]) |fa| {
            for (cands_b[0..n_b]) |fb| {
                const composed_sig = fa.signature ^ fb.signature; // XOR composition

                // Skip duplicates
                if (isDuplicate(self.composed_log[0..self.log_len], composed_sig)) continue;

                const novelty = 1.0 - maxOverlap(self.registry, composed_sig);
                const usefulness: f32 = @as(f32, @floatFromInt(@popCount(composed_sig & target_sig))) / 16.0;
                const surprise: f32 = if (fa.domain != fb.domain) 0.8 else 0.2;

                const score = novelty * 0.4 + usefulness * 0.4 + surprise * 0.2;
                if (score > best_score) {
                    best_score = score;
                    best = .{
                        .composed_fn = .{
                            .id = 0xDEAD0000 | (fa.id << 8) | fb.id,
                            .domain = 0xFF, // composed marker
                            .arity = fa.arity + fb.arity,
                            ._pad = .{ 0, 0 },
                            .signature = composed_sig,
                        },
                        .novelty = novelty,
                        .usefulness = usefulness,
                        .surprise = surprise,
                    };
                }
            }
        }

        if (best) |b| {
            if (self.log_len < self.composed_log.len) {
                self.composed_log[self.log_len] = b.composed_fn.signature;
                self.log_len += 1;
            }
        }
        return best;
    }
};

fn isDuplicate(log: []const u64, sig: u64) bool {
    for (log) |s| if (s == sig) return true;
    return false;
}

fn maxOverlap(registry: []const FunctionHandle, sig: u64) f32 {
    var max: f32 = 0;
    for (registry) |fh| {
        if (fh.signature == 0) continue;
        const ov: f32 = @as(f32, @floatFromInt(@popCount(fh.signature & sig))) / 64.0;
        if (ov > max) max = ov;
    }
    return max;
}

test "synthesizer creates novel composition" {
    allocator.init();
    var s = try Synthesizer.init(64, 256);
    _ = try s.registerFunction(0, 1, "sine wave periodic");
    _ = try s.registerFunction(5, 1, "exponential growth");

    const target = @import("../core/mmap.zig").bloomSig("oscillating growth");
    const r = s.synthesize(target, 0, 5);
    try std.testing.expect(r != null);
    try std.testing.expect(r.?.novelty > 0);
}
