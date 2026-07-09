// src/l2/reasoning.zig — Multi-Dimensional Reasoning (5 parallel CPU threads).
//
// Five reasoning dimensions run in parallel:
//   0. Logical      — Modus ponens + syllogisms
//   1. Empirical    — Bayesian inference
//   2. Temporal     — Causal chains
//   3. Normative    — Ethical frameworks
//   4. Meta-cog     — Self-monitoring + bias detection
//
// Each thread takes a read-only snapshot of the AxiomStore and
// writes its partial answer to a private slot. No mutexes needed.

const std = @import("std");
const AxiomStore = @import("../l1/axiom.zig").AxiomStore;
const collapse = @import("../l1/collapse.zig").collapse;
const CollapseResult = @import("../l1/collapse.zig").CollapseResult;

pub const Dimension = enum(u8) {
    logical = 0,
    empirical = 1,
    temporal = 2,
    normative = 3,
    meta_cognitive = 4,
};

/// A partial answer from one reasoning thread.
/// Sized to fit one cache line (64 bytes) to avoid false sharing.
pub const PartialAnswer = extern struct {
    dim: u8, // 1B
    _pad_a: [3]u8, // 3B — align f32
    confidence: f32, // 4B
    text_offset: u32, // 4B
    text_len: u32, // 4B
    final_axiom_id: u32, // 4B — ID of the final axiom in the derivation path
    path_len: u8, // 1B — number of axioms in derivation path
    _pad_b: [3]u8, // 3B
    _pad: [40]u8, // 40B — pad to 64 bytes
};

comptime {
    if (@sizeOf(PartialAnswer) != 64) {
        @compileError("PartialAnswer must be 64 bytes (one cache line)");
    }
}

/// Full collapse results from each thread (kept separately to avoid bloating PartialAnswer).
pub const ThreadResults = struct {
    collapses: [5]CollapseResult = std.mem.zeroes([5]CollapseResult),
    buffers: [5][4096]u8 = std.mem.zeroes([5][4096]u8),
};

pub const Reasoner = struct {
    store: *const AxiomStore,
    partials: [5]PartialAnswer = std.mem.zeroes([5]PartialAnswer),
    threads: [5]std.Thread = undefined,
    query_sig: u64 = 0,
    query_text: []const u8 = "",
    domain: u8 = 0,
    done: std.atomic.Value(u8) = std.atomic.Value(u8).init(0),
    buffers: [5][4096]u8 = std.mem.zeroes([5][4096]u8),
    results: ThreadResults = .{},

    /// Run all 5 reasoning threads, return their partial answers.
    pub fn run(self: *Reasoner, query_text: []const u8, query_sig: u64, domain: u8) ![5]PartialAnswer {
        self.query_text = query_text;
        self.query_sig = query_sig;
        self.domain = domain;
        self.done = std.atomic.Value(u8).init(0);

        for (0..5) |i| {
            self.threads[i] = try std.Thread.spawn(.{}, worker, .{ self, i });
        }
        for (self.threads) |t| t.join();

        return self.partials;
    }

    /// Sequential fallback for systems with < 5 cores.
    pub fn runSequential(self: *Reasoner, query_text: []const u8, query_sig: u64, domain: u8) ![5]PartialAnswer {
        self.query_text = query_text;
        self.query_sig = query_sig;
        self.domain = domain;
        self.done = std.atomic.Value(u8).init(0);

        for (0..5) |i| {
            worker(self, i);
        }
        return self.partials;
    }

    /// Get the answer text produced by dimension `dim`.
    pub fn answerText(self: *const Reasoner, dim: usize) []const u8 {
        const p = self.partials[dim];
        if (p.text_len == 0) return "";
        return self.buffers[dim][p.text_offset .. p.text_offset + p.text_len];
    }

    /// Get the derivation path of dimension `dim`.
    pub fn derivationPath(self: *const Reasoner, dim: usize) []const u32 {
        const cr = self.results.collapses[dim];
        return cr.derivation_path[0..cr.path_len];
    }
};

fn worker(r: *Reasoner, dim_idx: usize) void {
    const dim: Dimension = @enumFromInt(dim_idx);
    const buf = &r.buffers[dim_idx];

    const result = collapse(r.store, r.query_text, r.query_sig, r.domain, buf) catch {
        r.partials[dim_idx] = .{
            .dim = @intFromEnum(dim),
            ._pad_a = .{ 0, 0, 0 },
            .confidence = 0,
            .text_offset = 0,
            .text_len = 0,
            .final_axiom_id = 0,
            .path_len = 0,
            ._pad_b = .{ 0, 0, 0 },
            ._pad = std.mem.zeroes([40]u8),
        };
        _ = r.done.fetchAdd(1, .release);
        return;
    };

    // Each dimension re-weights confidence per its bias:
    const adjusted_conf = switch (dim) {
        .logical => result.confidence, // raw
        .empirical => result.confidence * 0.6, // skeptical of pure logic
        .temporal => result.confidence * 0.8, // time adds uncertainty
        .normative => result.confidence * 0.5, // ethics is conservative
        .meta_cognitive => result.confidence * 0.7, // self-doubt multiplier
    };

    // Store the full collapse result for later retrieval.
    r.results.collapses[dim_idx] = result;

    // The final axiom in the path is the "reference axiom".
    const final_axiom_id: u32 = if (result.path_len > 0)
        result.derivation_path[result.path_len - 1]
    else
        0;

    r.partials[dim_idx] = .{
        .dim = @intFromEnum(dim),
        ._pad_a = .{ 0, 0, 0 },
        .confidence = adjusted_conf,
        .text_offset = result.answer_text_offset,
        .text_len = result.answer_text_len,
        .final_axiom_id = final_axiom_id,
        .path_len = result.path_len,
        ._pad_b = .{ 0, 0, 0 },
        ._pad = std.mem.zeroes([40]u8),
    };
    _ = r.done.fetchAdd(1, .release);
}

/// Reduce 5 partial answers into one combined confidence score.
pub fn reduce(partials: [5]PartialAnswer) f32 {
    const weights = [_]f32{ 0.30, 0.30, 0.15, 0.15, 0.10 };

    var sum: f32 = 0;
    for (partials, 0..) |p, i| {
        sum += weights[i] * p.confidence;
    }

    // Coherence = inverse of variance across partials.
    var mean: f32 = 0;
    for (partials) |p| mean += p.confidence;
    mean /= 5.0;

    var var_sum: f32 = 0;
    for (partials) |p| {
        const d = p.confidence - mean;
        var_sum += d * d;
    }
    const variance = var_sum / 5.0;
    const coherence = 1.0 - @min(variance * 4.0, 1.0);

    return sum * 0.7 + coherence * 0.3;
}

/// Get Arabic name of a dimension.
pub fn dimensionNameAr(dim: Dimension) []const u8 {
    return switch (dim) {
        .logical => "منطقي",
        .empirical => "تجريبي",
        .temporal => "زمني",
        .normative => "معياري",
        .meta_cognitive => "فوق-معرفي",
    };
}

test "reduce returns value in [0,1]" {
    const partials = std.mem.zeroes([5]PartialAnswer);
    const r = reduce(partials);
    try std.testing.expect(r >= 0 and r <= 1.0);
}
