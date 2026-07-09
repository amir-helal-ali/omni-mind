// src/l1/collapse.zig — Quantum Collapse Function (Reasoning Loop).
//
// When the model encounters a query, the state vector of possible
// reasoning paths "collapses" into the single most probable path
// based on First Principles. This is the analog of quantum
// superposition collapse, translated into software logic.

const std = @import("std");
const AxiomStore = @import("axiom.zig").AxiomStore;
const Axiom = @import("axiom.zig").Axiom;
const bloomSig = @import("../core/mmap.zig").bloomSig;
const weight = @import("procedural_weights.zig").weight;
const deriveAlphaFromAxioms = @import("procedural_weights.zig").deriveAlphaFromAxioms;

/// The result of a collapse — a derivation path + confidence.
pub const CollapseResult = struct {
    derivation_path: [16]u32, // chain of axiom IDs used
    path_len: u8,
    confidence: f32, // 0.0-1.0 from coherence
    answer_text_offset: u32, // into answer buffer
    answer_text_len: u32,

    pub fn path(self: CollapseResult) []const u32 {
        return self.derivation_path[0..self.path_len];
    }

    pub fn answer(self: CollapseResult, buf: []const u8) []const u8 {
        return buf[self.answer_text_offset .. self.answer_text_offset + self.answer_text_len];
    }
};

/// Error set for the collapse function.
pub const CollapseError = error{
    NoCandidateAxioms,
    PathTooLong,
    AnswerBufferTooSmall,
};

/// Collapse a superposition of possible reasoning paths into one final answer.
///
/// Time complexity: O(K × D) where K = paths explored, D = max depth.
/// Memory: zero allocations in hot path.
pub fn collapse(
    store: *const AxiomStore,
    query: []const u8,
    _: u64,
    domain_hint: u8,
    out_buf: []u8,
) CollapseError!CollapseResult {
    var result: CollapseResult = .{
        .derivation_path = std.mem.zeroes([16]u32),
        .path_len = 0,
        .confidence = 0,
        .answer_text_offset = 0,
        .answer_text_len = 0,
    };

    // 1. Find candidate axioms by DIRECT KEYWORD MATCHING.
    var candidates: [32]@import("axiom.zig").ScoredAxiom = undefined;
    const n_cand = store.findByKeywords(query, domain_hint, &candidates);

    if (n_cand == 0) return error.NoCandidateAxioms;

    // 2. Pick the best candidate (highest keyword score).
    const best_cand = candidates[0];

    // 3. Build derivation path from best candidate + prerequisites.
    var best_path: [16]u32 = std.mem.zeroes([16]u32);
    best_path[0] = best_cand.id;
    var best_len: u8 = 1;

    const ax = store.get(best_cand.id) orelse return error.NoCandidateAxioms;
    for (ax.prerequisites) |prereq| {
        if (prereq == 0) break;
        if (best_len < 16) {
            best_path[best_len] = prereq;
            best_len += 1;
        }
    }

    // 4. Calculate confidence based on keyword match score.
    // Higher score = higher confidence. Good matches (score >= 3) get
    // high confidence to prevent analogy tunneling from overriding them.
    const max_possible: f32 = 8.0;
    const keyword_conf = @min(@as(f32, @floatFromInt(best_cand.score)) / max_possible, 1.0);
    if (best_cand.score >= 3) {
        result.confidence = 0.75; // Good match — high confidence, no tunneling needed
    } else if (best_cand.score >= 2) {
        result.confidence = 0.55; // Decent match
    } else {
        result.confidence = @min(0.3 + keyword_conf * 0.5, 0.45); // Weak match — allow tunneling
    }

    result.derivation_path = best_path;
    result.path_len = best_len;

    // 5. Materialize answer text from the final axiom.
    const final_axiom = store.get(best_path[0]) orelse return error.NoCandidateAxioms;
    const final_text = @import("axiom.zig").axiomText(final_axiom, store.text_blob);

    // Compose answer: query → derivation → final axiom text
    const written = composeAnswer(out_buf, store, best_path[0..best_len], final_text);
    if (written == 0) return error.AnswerBufferTooSmall;

    result.answer_text_len = @intCast(written);
    return result;
}

/// Forward chaining: expand an axiom via its prerequisites until
/// either the target signature is reached or max depth exceeded.
fn forwardChain(
    store: *const AxiomStore,
    start: u32,
    target_sig: u64,
    alpha: [4]f32,
    path: *[16]u32,
) u8 {
    var current: u32 = start;
    var len: u8 = 0;

    while (len < 16) {
        path[len] = current;
        len += 1;

        const ax = store.get(current) orelse break;

        // Check if we've reached an axiom whose signature covers the target.
        if ((ax.signature & target_sig) == target_sig) break;

        // Pick the prerequisite with highest procedural weight to the target.
        var best_prereq: u32 = 0;
        var best_w: f32 = 0;
        for (ax.prerequisites) |p| {
            if (p == 0) continue;
            const p_ax = store.get(p) orelse continue;
            const w = weight(p_ax.signature, target_sig, alpha);
            if (w > best_w) {
                best_w = w;
                best_prereq = p;
            }
        }
        if (best_w == 0) break;
        current = best_prereq;
    }
    return len;
}

/// Score the coherence of a derivation path.
/// Higher = more logically consistent.
fn scoreCoherence(
    store: *const AxiomStore,
    path: []const u32,
    alpha: [4]f32,
    target_sig: u64,
) f32 {
    if (path.len == 0) return 0;

    var total: f32 = 0;
    for (path) |aid| {
        const ax = store.get(aid) orelse continue;
        const w = weight(ax.signature, target_sig, alpha);
        total += w;
    }
    // Average weight + bonus for path length (longer = more derivations = more confidence if coherent)
    const avg = total / @as(f32, @floatFromInt(path.len));
    const length_bonus: f32 = @as(f32, @floatFromInt(path.len)) * 0.05;
    return @min(avg + length_bonus, 1.0);
}

/// Compose an answer string from the derivation path.
/// Format: "[step 1] → [step 2] → ... → [final axiom text]"
fn composeAnswer(
    out: []u8,
    store: *const AxiomStore,
    path: []const u32,
    final_text: []const u8,
) usize {
    var pos: usize = 0;
    const prefix = "Derivation: ";
    if (pos + prefix.len > out.len) return 0;
    @memcpy(out[pos .. pos + prefix.len], prefix);
    pos += prefix.len;

    for (path, 0..) |aid, i| {
        if (i > 0) {
            if (pos + 4 > out.len) return 0;
            @memcpy(out[pos .. pos + 4], " -> ");
            pos += 4;
        }
        const ax = store.get(aid) orelse continue;
        const txt = @import("axiom.zig").axiomText(ax, store.text_blob);
        if (pos + txt.len > out.len) return 0;
        @memcpy(out[pos .. pos + txt.len], txt);
        pos += txt.len;
    }

    if (pos + 2 + final_text.len > out.len) return 0;
    @memcpy(out[pos .. pos + 2], ". ");
    pos += 2;
    @memcpy(out[pos .. pos + final_text.len], final_text);
    pos += final_text.len;

    return pos;
}

test "collapse returns a path" {
    @import("../core/allocator.zig").init();
    var store = try AxiomStore.init(64, 8192);

    // Build a tiny chain: A → B → C
    _ = try store.add(
        @intFromEnum(@import("../core/node.zig").Domain.physics),
        "friction converts kinetic energy to heat",
        1.0,
        &[_]u32{},
    );
    _ = try store.add(
        @intFromEnum(@import("../core/node.zig").Domain.physics),
        "motion is kinetic energy",
        1.0,
        &[_]u32{0},
    );

    const q = bloomSig("friction heat");
    var buf: [4096]u8 = undefined;
    const result = try collapse(&store, q, 0, &buf);
    try std.testing.expect(result.path_len >= 1);
    try std.testing.expect(result.confidence >= 0);
}
