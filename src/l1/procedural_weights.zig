// src/l1/procedural_weights.zig — Procedural Weight Generation.
//
// Replaces a stored weight matrix with a deterministic function.
// Instead of O(N²) storage, we use O(1) storage + O(K) compute,
// where K is the number of basis functions (8-16).
//
// Mathematical form:
//   W(q, k) = Σ αᵢ · φᵢ(sig(q), sig(k))
//
// The α coefficients are derived from axioms, not learned.

const std = @import("std");
const AxiomStore = @import("axiom.zig").AxiomStore;

pub const NUM_BASIS: usize = 4;

pub const AlphaWeights = struct {
    pub const logical: f32 = 0.30;
    pub const empirical: f32 = 0.30;
    pub const coherence: f32 = 0.20;
    pub const novelty: f32 = 0.10;
    pub const meta: f32 = 0.10;
};

/// Compute the procedural weight between two concepts from their
/// Bloom signatures. O(K) where K = NUM_BASIS = 4.
///
/// This is the heart of "no stored weights" — every weight is
/// computed on-the-fly from the axiom-derived alphas.
pub fn weight(sig_q: u64, sig_k: u64, alpha: [NUM_BASIS]f32) f32 {
    // Basis 1: Bloom intersection — captures shared concepts
    const intersection = @popCount(sig_q & sig_k);
    const phi1: f32 = @as(f32, @floatFromInt(intersection)) / 64.0;

    // Basis 2: Trigonometric — captures periodic co-occurrence patterns
    const q_norm: f32 = @as(f32, @floatFromInt(sig_q % 1000000)) / 1000000.0;
    const k_norm: f32 = @as(f32, @floatFromInt(sig_k % 1000000)) / 1000000.0;
    const phi2 = @cos(q_norm * 6.2832) * @cos(k_norm * 6.2832);

    // Basis 3: Sigmoidal XOR — captures "complementary" concepts
    const xor_val: f32 = @as(f32, @floatFromInt(@popCount(sig_q ^ sig_k)));
    const phi3 = 1.0 / (1.0 + @exp(-0.1 * (xor_val - 32.0)));

    // Basis 4: Gaussian RBF on Hamming distance — captures similarity
    const hamming: f32 = xor_val;
    const phi4 = @exp(-(hamming * hamming) / (2.0 * 16.0 * 16.0));

    return alpha[0] * phi1 + alpha[1] * phi2 + alpha[2] * phi3 + alpha[3] * phi4;
}

/// Derive alpha coefficients from the axioms of a domain.
/// Each axiom type contributes to specific alphas:
///   - causal axioms → intersection (α₁)
///   - similarity axioms → RBF (α₄)
///   - complement axioms → XOR (α₃)
///   - periodic axioms → trig (α₂)
pub fn deriveAlphaFromAxioms(domain: u8, store: *const AxiomStore) [NUM_BASIS]f32 {
    var alpha: [NUM_BASIS]f32 = .{ 0.25, 0.15, 0.15, 0.25 };

    const domain_axioms = store.findByDomain(domain);
    for (domain_axioms) |ax| {
        // Heuristic: classify axiom by text keywords (zero-alloc substring scan).
        const txt = @import("axiom.zig").axiomText(ax, store.text_blob);
        if (std.mem.indexOf(u8, txt, "causes") != null or
            std.mem.indexOf(u8, txt, "caused") != null or
            std.mem.indexOf(u8, txt, "ي cause") != null)
        {
            alpha[0] += 0.01; // causal → intersection
        }
        if (std.mem.indexOf(u8, txt, "similar") != null or
            std.mem.indexOf(u8, txt, "analogous") != null)
        {
            alpha[3] += 0.01; // similarity → RBF
        }
        if (std.mem.indexOf(u8, txt, "complement") != null or
            std.mem.indexOf(u8, txt, "opposite") != null)
        {
            alpha[2] += 0.01; // complementarity → XOR
        }
        if (std.mem.indexOf(u8, txt, "periodic") != null or
            std.mem.indexOf(u8, txt, "cyclic") != null or
            std.mem.indexOf(u8, txt, "oscillat") != null)
        {
            alpha[1] += 0.01; // periodicity → trig
        }
    }

    // Normalize alphas to sum to 1.0
    var sum: f32 = 0;
    for (alpha) |a| sum += a;
    if (sum > 0) {
        for (&alpha) |*a| a.* /= sum;
    }
    return alpha;
}

test "weight is bounded" {
    const alpha = [_]f32{ 0.25, 0.25, 0.25, 0.25 };
    const w = weight(0xAAAAAAAAAAAAAAAA, 0x5555555555555555, alpha);
    // Weight is a linear combination of basis functions each in [-1, 1],
    // so the result is bounded but may slightly exceed [0, 1] due to basis 2.
    try std.testing.expect(w >= -1.0 and w <= 1.5);
}

test "identical signatures give max weight" {
    const alpha = [_]f32{ 1.0, 0.0, 0.0, 0.0 };
    const w_same = weight(0xFFFFFFFFFFFFFFFF, 0xFFFFFFFFFFFFFFFF, alpha);
    try std.testing.expect(w_same > 0.5);
}

test "alpha derivation normalizes to 1.0" {
    @import("../core/allocator.zig").init();
    var store = try AxiomStore.init(64, 4096);
    _ = try store.add(0, "X causes Y", 1.0, &[_]u32{});
    const alpha = deriveAlphaFromAxioms(0, &store);
    var sum: f32 = 0;
    for (alpha) |a| sum += a;
    try std.testing.expectApproxEqAbs(@as(f32, 1.0), sum, 0.01);
}
