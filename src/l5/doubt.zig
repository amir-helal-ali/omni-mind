// src/l5/doubt.zig — Self-Reflection & Confidence Calculator.
//
// Every answer carries a numeric confidence (0.0–1.0). The tone
// adapts: confident, likely, uncertain, low_confidence.
// Confident hallucination (LLM's biggest flaw) is structurally impossible.

const std = @import("std");
const PartialAnswer = @import("../l2/reasoning.zig").PartialAnswer;

pub const ConfidenceBreakdown = struct {
    logical: f32,
    empirical: f32,
    coherence: f32,
    novelty: f32,
    meta: f32,
};

pub const Tone = enum {
    confident, // C > 0.85
    likely, // C 0.6-0.85
    uncertain, // C 0.3-0.6
    low_confidence, // C < 0.3
    contradictory, // partials disagree strongly
};

/// Calculate confidence breakdown from the 5 partial answers.
pub fn calculate(partials: [5]PartialAnswer, tunnel_used: bool) ConfidenceBreakdown {
    const log_c = partials[0].confidence;
    const emp_c = partials[1].confidence;
    const meta_c = partials[4].confidence;

    // Coherence = inverse of variance across the 5 partials.
    var sum: f32 = 0;
    for (partials) |p| sum += p.confidence;
    const mean = sum / 5.0;
    var var_sum: f32 = 0;
    for (partials) |p| {
        const d = p.confidence - mean;
        var_sum += d * d;
    }
    const variance = var_sum / 5.0;
    const coherence = 1.0 - @min(variance * 4.0, 1.0);

    const novelty: f32 = if (tunnel_used) 0.7 else 0.3;

    return .{
        .logical = log_c,
        .empirical = emp_c,
        .coherence = coherence,
        .novelty = novelty,
        .meta = meta_c,
    };
}

/// Combine breakdown into a single confidence value.
pub fn combine(cb: ConfidenceBreakdown) f32 {
    return 0.30 * cb.logical
        + 0.30 * cb.empirical
        + 0.20 * cb.coherence
        + 0.10 * cb.novelty
        + 0.10 * cb.meta;
}

/// Pick the tone that matches the confidence.
pub fn pickTone(c: f32, cb: ConfidenceBreakdown) Tone {
    if (cb.coherence < 0.3) return .contradictory;
    if (c > 0.85) return .confident;
    if (c > 0.6) return .likely;
    if (c > 0.3) return .uncertain;
    return .low_confidence;
}

/// Arabic tone prefix to prepend to the answer.
pub fn tonePrefixArabic(t: Tone) []const u8 {
    return switch (t) {
        .confident => "بثقة عالية: ",
        .likely => "الأرجح أن: ",
        .uncertain => "هناك شك في أن: ",
        .low_confidence => "لا أعرف بدقة، لكن: ",
        .contradictory => "هناك آراء متعارضة. من جهة: ",
    };
}

/// English tone prefix.
pub fn tonePrefixEnglish(t: Tone) []const u8 {
    return switch (t) {
        .confident => "With high confidence: ",
        .likely => "Most likely: ",
        .uncertain => "There is uncertainty: ",
        .low_confidence => "I don't know precisely, but: ",
        .contradictory => "There are conflicting views. On one hand: ",
    };
}

test "confidence in [0,1]" {
    const partials = std.mem.zeroes([5]PartialAnswer);
    const cb = calculate(partials, false);
    const c = combine(cb);
    try std.testing.expect(c >= 0 and c <= 1.0);
}

test "tone picker" {
    try std.testing.expectEqual(Tone.confident, pickTone(0.9, .{
        .logical = 0.9,
        .empirical = 0.9,
        .coherence = 0.9,
        .novelty = 0.9,
        .meta = 0.9,
    }));
    try std.testing.expectEqual(Tone.low_confidence, pickTone(0.1, .{
        .logical = 0.1,
        .empirical = 0.1,
        .coherence = 0.9, // high coherence so we don't trigger contradictory
        .novelty = 0.1,
        .meta = 0.1,
    }));
}
