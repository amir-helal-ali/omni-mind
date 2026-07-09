// src/core/self.zig — Self-Awareness, Self-Understanding, Self-Learning,
// and Self-Strengthening engine.
//
// This module gives Omni-Mind the ability to:
//   1. Self-Understanding: Analyze its own confidence and identify weak spots.
//   2. Self-Learning: Generate new axioms from patterns it discovers.
//   3. Self-Strengthening: Improve its matching from past failures.
//   4. Self-Reflection: Generate questions for itself to test its knowledge.
//   5. Feedback Loop: Connect all four into an autonomous improvement cycle.

const std = @import("std");
const Language = @import("lang.zig").Language;
const translate = @import("axiom_translations.zig").translate;

/// Self-awareness state — tracks the system's understanding of its own
/// capabilities and weaknesses.
pub const SelfState = struct {
    // Statistics from all past queries.
    total_queries: u64 = 0,
    total_low_confidence: u64 = 0,
    total_failed: u64 = 0,
    total_auto_learned: u64 = 0,
    total_self_tests: u64 = 0,

    // Weak domains — domains where confidence is consistently low.
    domain_weakness: [10]DomainStat = std.mem.zeroes([10]DomainStat),

    // Patterns discovered from failed queries — words that appear in queries
    // but don't match any existing axiom. These become candidates for
    // self-generated axioms.
    unmatched_words: [128]UnmatchedWord = std.mem.zeroes([128]UnmatchedWord),
    unmatched_count: usize = 0,

    // Self-generated axioms — axioms the system created for itself.
    auto_axioms: [64]AutoAxiom = std.mem.zeroes([64]AutoAxiom),
    auto_axiom_count: usize = 0,

    // Confidence history — rolling average of recent confidences.
    confidence_history: [32]f32 = std.mem.zeroes([32]f32),
    confidence_head: usize = 0,
    confidence_count: usize = 0,

    // Whether self-learning is enabled.
    self_learning_enabled: bool = true,
    // Whether self-strengthening is enabled.
    self_strengthening_enabled: bool = true,
};

pub const DomainStat = struct {
    domain: u8 = 0,
    query_count: u32 = 0,
    low_confidence_count: u32 = 0,
    avg_confidence: f32 = 0,
    weak: bool = false,
};

pub const UnmatchedWord = struct {
    word: [64]u8 = std.mem.zeroes([64]u8),
    word_len: u8 = 0,
    count: u8 = 0, // how many times this word appeared in failed queries
    domain_hint: u8 = 0,
};

pub const AutoAxiom = struct {
    text: [256]u8 = std.mem.zeroes([256]u8),
    text_len: u16 = 0,
    domain: u8 = 0,
    confidence: f32 = 0,
    source: [32]u8 = std.mem.zeroes([32]u8), // "self-learned" or "self-strengthened"
    source_len: u8 = 0,
    timestamp: i64 = 0,
};

/// Record a query result for self-analysis.
pub fn recordQueryResult(
    state: *SelfState,
    domain: u8,
    confidence: f32,
    query_words: []const []const u8,
    matched_axiom_found: bool,
) void {
    state.total_queries += 1;

    // Update confidence history (rolling average).
    state.confidence_history[state.confidence_head] = confidence;
    state.confidence_head = (state.confidence_head + 1) % 32;
    if (state.confidence_count < 32) state.confidence_count += 1;

    // Update domain stats.
    if (domain < 10) {
        const ds = &state.domain_weakness[domain];
        ds.domain = domain;
        ds.query_count += 1;
        if (confidence < 0.4) {
            ds.low_confidence_count += 1;
            state.total_low_confidence += 1;
        }
        // Update rolling average.
        const alpha: f32 = 0.3;
        ds.avg_confidence = (alpha * confidence) + ((1.0 - alpha) * ds.avg_confidence);
        // Mark as weak if >40% of queries have low confidence.
        if (ds.query_count > 5 and
            @as(f32, @floatFromInt(ds.low_confidence_count)) / @as(f32, @floatFromInt(ds.query_count)) > 0.4)
        {
            ds.weak = true;
        }
    }

    // If no axiom was found, record the unmatched words for self-learning.
    if (!matched_axiom_found and state.self_learning_enabled) {
        state.total_failed += 1;
        for (query_words) |qw| {
            if (qw.len < 3) continue;
            recordUnmatchedWord(state, qw, domain);
        }
    }
}

/// Record an unmatched word — a word that appeared in a query but didn't
/// match any existing axiom. If the same word appears multiple times,
/// it becomes a candidate for self-learning.
fn recordUnmatchedWord(state: *SelfState, word: []const u8, domain: u8) void {
    // Check if this word is already tracked.
    for (0..state.unmatched_count) |i| {
        const uw = &state.unmatched_words[i];
        if (uw.word_len > 0) {
            const existing = uw.word[0..uw.word_len];
            if (std.mem.eql(u8, existing, word)) {
                uw.count +%= 1;
                uw.domain_hint = domain;
                return;
            }
        }
    }

    // Add new unmatched word.
    if (state.unmatched_count < state.unmatched_words.len) {
        const uw = &state.unmatched_words[state.unmatched_count];
        const n = @min(word.len, 63);
        @memcpy(uw.word[0..n], word[0..n]);
        uw.word_len = @intCast(n);
        uw.count = 1;
        uw.domain_hint = domain;
        state.unmatched_count += 1;
    }
}

/// Self-Learning: Generate new axioms from patterns discovered in
/// unmatched words. If a word appears >= 3 times in failed queries
/// for the same domain, the system generates a provisional axiom.
pub fn selfLearn(state: *SelfState, out: []AutoAxiom) usize {
    if (!state.self_learning_enabled) return 0;

    var n: usize = 0;
    for (0..state.unmatched_count) |i| {
        const uw = state.unmatched_words[i];
        if (uw.count >= 3 and n < out.len) {
            // Generate a provisional axiom from the unmatched word.
            const word = uw.word[0..uw.word_len];
            const domain = uw.domain_hint;

            // Create the axiom text.
            var text_buf: [256]u8 = undefined;
            const text = std.fmt.bufPrint(&text_buf, "{s} is a concept in {s} that requires further study", .{
                word,
                domainNameEn(domain),
            }) catch continue;

            const ax = AutoAxiom{
                .text = std.mem.zeroes([256]u8),
                .text_len = @intCast(text.len),
                .domain = domain,
                .confidence = 0.3, // Low confidence — it's self-learned
                .source = std.mem.zeroes([32]u8),
                .source_len = 0,
                .timestamp = std.time.timestamp(),
            };

            // Copy text and source.
            var new_ax = ax;
            @memcpy(new_ax.text[0..text.len], text);
            const source = "self-learned";
            @memcpy(new_ax.source[0..source.len], source);
            new_ax.source_len = @intCast(source.len);

            out[n] = new_ax;
            n += 1;
            state.total_auto_learned += 1;

            // Remove this word from unmatched list (it's been learned).
            state.unmatched_words[i].count = 0;
        }
    }
    return n;
}

/// Self-Strengthening: Analyze past failures and create synonym/alias
/// mappings to improve future matching. For example, if "brakes" failed
/// to match "braking", the system creates an alias.
pub fn selfStrengthen(
    state: *SelfState,
    failed_query: []const u8,
    best_axiom_text: []const u8,
    out_aliases: []Alias,
) usize {
    if (!state.self_strengthening_enabled) return 0;

    var n: usize = 0;

    // Tokenize both the query and the axiom text.
    var query_words: [32][]const u8 = undefined;
    var nqw: usize = 0;
    tokenize(failed_query, &query_words, &nqw);

    var axiom_words: [32][]const u8 = undefined;
    var naw: usize = 0;
    tokenize(best_axiom_text, &axiom_words, &naw);

    // Find words in the query that are similar to (but not identical to)
    // words in the axiom. These are potential aliases.
    for (query_words[0..nqw]) |qw| {
        if (qw.len < 4) continue;
        for (axiom_words[0..naw]) |aw| {
            if (aw.len < 4) continue;
            if (std.mem.eql(u8, qw, aw)) continue;

            // Check if they share a common prefix (at least 4 chars).
            const min_len = @min(qw.len, aw.len);
            const prefix_len = commonPrefix(qw, aw, @min(min_len, 6));
            if (prefix_len >= 4 and n < out_aliases.len) {
                // Create an alias: qw → aw
                const alias = Alias{
                    .from = std.mem.zeroes([64]u8),
                    .from_len = @intCast(@min(qw.len, 63)),
                    .to = std.mem.zeroes([64]u8),
                    .to_len = @intCast(@min(aw.len, 63)),
                };
                var a = alias;
                @memcpy(a.from[0..a.from_len], qw[0..a.from_len]);
                @memcpy(a.to[0..a.to_len], aw[0..a.to_len]);
                out_aliases[n] = a;
                n += 1;
                break; // One alias per query word
            }
        }
    }

    return n;
}

/// Self-Reflection: Generate questions the system should test itself on.
/// These are based on weak domains and recently learned axioms.
pub fn selfReflect(state: *SelfState, out: []SelfTest) usize {
    var n: usize = 0;

    // Generate questions for weak domains.
    for (state.domain_weakness[0..10]) |ds| {
        if (ds.weak and n < out.len) {
            const domain_name = domainNameEn(ds.domain);
            var q_buf: [128]u8 = undefined;
            const q = std.fmt.bufPrint(&q_buf, "what is the fundamental principle of {s}?", .{domain_name}) catch continue;

            out[n] = .{
                .question = std.mem.zeroes([128]u8),
                .question_len = @intCast(q.len),
                .domain = ds.domain,
                .reason = std.mem.zeroes([64]u8),
                .reason_len = 0,
            };
            @memcpy(out[n].question[0..q.len], q);
            const reason = "weak domain";
            @memcpy(out[n].reason[0..reason.len], reason);
            out[n].reason_len = @intCast(reason.len);
            n += 1;
            state.total_self_tests += 1;
        }
    }

    // Generate questions for self-learned axioms (to verify them).
    for (0..state.auto_axiom_count) |i| {
        const aa = state.auto_axioms[i];
        if (aa.text_len > 0 and n < out.len) {
            var q_buf: [256]u8 = undefined;
            const q = std.fmt.bufPrint(&q_buf, "what is {s}?", .{aa.text[0..@min(aa.text_len, 60)]}) catch continue;

            out[n] = .{
                .question = std.mem.zeroes([128]u8),
                .question_len = @intCast(@min(q.len, 127)),
                .domain = aa.domain,
                .reason = std.mem.zeroes([64]u8),
                .reason_len = 0,
            };
            @memcpy(out[n].question[0..@min(q.len, 127)], q[0..@min(q.len, 127)]);
            const reason = "verify self-learned";
            @memcpy(out[n].reason[0..reason.len], reason);
            out[n].reason_len = @intCast(reason.len);
            n += 1;
        }
    }

    return n;
}

/// Get the system's overall self-confidence — how well it thinks it's doing.
pub fn selfConfidence(state: *const SelfState) f32 {
    if (state.confidence_count == 0) return 0.0;
    var sum: f32 = 0;
    for (state.confidence_history[0..state.confidence_count]) |c| {
        sum += c;
    }
    return sum / @as(f32, @floatFromInt(state.confidence_count));
}

/// Get a self-awareness report in the specified language.
pub fn selfReport(state: *const SelfState, lang: Language, out: []u8) usize {
    var pos: usize = 0;
    const avg_conf = selfConfidence(state);
    const weak_count = blk: {
        var c: usize = 0;
        for (state.domain_weakness) |ds| {
            if (ds.weak) c += 1;
        }
        break :blk c;
    };

    switch (lang) {
        .english => {
            pos += writeFmt(out[pos..], "Self-Awareness Report:\n", .{});
            pos += writeFmt(out[pos..], "  Total queries: {d}\n", .{state.total_queries});
            pos += writeFmt(out[pos..], "  Avg confidence: {d:.2}\n", .{avg_conf});
            pos += writeFmt(out[pos..], "  Low confidence queries: {d}\n", .{state.total_low_confidence});
            pos += writeFmt(out[pos..], "  Failed queries: {d}\n", .{state.total_failed});
            pos += writeFmt(out[pos..], "  Auto-learned axioms: {d}\n", .{state.total_auto_learned});
            pos += writeFmt(out[pos..], "  Self-tests run: {d}\n", .{state.total_self_tests});
            pos += writeFmt(out[pos..], "  Weak domains: {d}\n", .{weak_count});
            pos += writeFmt(out[pos..], "  Unmatched words tracked: {d}\n", .{state.unmatched_count});

            if (weak_count > 0) {
                pos += writeStr(out[pos..], "  Weak domains: ");
                for (state.domain_weakness) |ds| {
                    if (ds.weak) {
                        pos += writeFmt(out[pos..], "{s} ", .{domainNameEn(ds.domain)});
                    }
                }
                pos += writeStr(out[pos..], "\n");
            }

            if (avg_conf < 0.4) {
                pos += writeStr(out[pos..], "  Status: NEEDS IMPROVEMENT\n");
            } else if (avg_conf < 0.6) {
                pos += writeStr(out[pos..], "  Status: MODERATE\n");
            } else {
                pos += writeStr(out[pos..], "  Status: HEALTHY\n");
            }
        },
        .arabic => {
            pos += writeFmt(out[pos..], "تقرير الوعي الذاتي:\n", .{});
            pos += writeFmt(out[pos..], "  إجمالي الاستعلامات: {d}\n", .{state.total_queries});
            pos += writeFmt(out[pos..], "  متوسط الثقة: {d:.2}\n", .{avg_conf});
            pos += writeFmt(out[pos..], "  استعلامات منخفضة الثقة: {d}\n", .{state.total_low_confidence});
            pos += writeFmt(out[pos..], "  استعلامات فاشلة: {d}\n", .{state.total_failed});
            pos += writeFmt(out[pos..], "  بديهيات مُتعلَّمة ذاتياً: {d}\n", .{state.total_auto_learned});
            pos += writeFmt(out[pos..], "  اختبارات ذاتية: {d}\n", .{state.total_self_tests});
            pos += writeFmt(out[pos..], "  مجالات ضعيفة: {d}\n", .{weak_count});
            pos += writeFmt(out[pos..], "  كلمات غير مطابقة: {d}\n", .{state.unmatched_count});

            if (avg_conf < 0.4) {
                pos += writeStr(out[pos..], "  الحالة: يحتاج تحسين\n");
            } else if (avg_conf < 0.6) {
                pos += writeStr(out[pos..], "  الحالة: متوسط\n");
            } else {
                pos += writeStr(out[pos..], "  الحالة: صحي\n");
            }
        },
    }

    return pos;
}

// ─── Types ────────────────────────────────────────────

pub const Alias = struct {
    from: [64]u8 = std.mem.zeroes([64]u8),
    from_len: u8 = 0,
    to: [64]u8 = std.mem.zeroes([64]u8),
    to_len: u8 = 0,
};

pub const SelfTest = struct {
    question: [128]u8 = std.mem.zeroes([128]u8),
    question_len: u8 = 0,
    domain: u8 = 0,
    reason: [64]u8 = std.mem.zeroes([64]u8),
    reason_len: u8 = 0,
};

// ─── Helpers ──────────────────────────────────────────

fn domainNameEn(d: u8) []const u8 {
    return switch (d) {
        0 => "physics",
        1 => "chemistry",
        2 => "biology",
        3 => "mathematics",
        4 => "logic",
        5 => "computer science",
        6 => "economics",
        else => "unknown",
    };
}

fn tokenize(text: []const u8, out: *[32][]const u8, n: *usize) void {
    n.* = 0;
    var start: ?usize = null;
    for (text, 0..) |b, i| {
        if ((b >= 'a' and b <= 'z') or (b >= 'A' and b <= 'Z') or b >= 0x80) {
            if (start == null) start = i;
        } else {
            if (start) |s| {
                if (n.* < out.len and i - s >= 3) {
                    out[n.*] = text[s..i];
                    n.* += 1;
                }
                start = null;
            }
        }
    }
    if (start) |s| {
        if (n.* < out.len and text.len - s >= 3) {
            out[n.*] = text[s..];
            n.* += 1;
        }
    }
}

fn commonPrefix(a: []const u8, b: []const u8, max: usize) usize {
    const n = @min(@min(a.len, b.len), max);
    var i: usize = 0;
    while (i < n) : (i += 1) {
        if (a[i] != b[i]) break;
    }
    return i;
}

fn writeStr(buf: []u8, s: []const u8) usize {
    const n = @min(s.len, buf.len);
    @memcpy(buf[0..n], s[0..n]);
    return n;
}

fn writeFmt(buf: []u8, comptime fmt: []const u8, args: anytype) usize {
    const result = std.fmt.bufPrint(buf, fmt, args) catch return 0;
    return result.len;
}

// ═══════════════════════════════════════════════════════════════
// Part 2: Advanced Self-Evolution
//   6. Knowledge Extraction: Extract new axioms from successful queries.
//   7. Contradiction Detection: Find conflicting axioms.
//   8. Self-Evolution: Strategically improve based on performance history.
//   9. IQ Report: Comprehensive intelligence self-assessment.
// ═══════════════════════════════════════════════════════════════

/// Knowledge Extraction: When a query succeeds with high confidence,
/// extract a new derived axiom that connects the query topic to the
/// matched axiom. This is how the system "understands" new concepts.
pub fn extractKnowledge(
    state: *SelfState,
    query: []const u8,
    matched_axiom_text: []const u8,
    domain: u8,
    confidence: f32,
    out: []AutoAxiom,
) usize {
    if (confidence < 0.5) return 0; // Only learn from confident answers

    // Extract the key topic from the query (remove question words).
    var topic_buf: [128]u8 = undefined;
    const topic = extractTopic(query, &topic_buf);
    if (topic.len < 3) return 0;

    var n: usize = 0;
    if (n < out.len) {
        var text_buf: [256]u8 = undefined;
        const text = std.fmt.bufPrint(&text_buf, "{s} relates to: {s}", .{
            topic,
            matched_axiom_text,
        }) catch return 0;

        var ax = AutoAxiom{
            .text = std.mem.zeroes([256]u8),
            .text_len = @intCast(@min(text.len, 255)),
            .domain = domain,
            .confidence = confidence * 0.6, // Lower than original
            .source = std.mem.zeroes([32]u8),
            .source_len = 0,
            .timestamp = std.time.timestamp(),
        };
        @memcpy(ax.text[0..ax.text_len], text[0..ax.text_len]);
        const src = "knowledge-extracted";
        @memcpy(ax.source[0..src.len], src);
        ax.source_len = @intCast(src.len);

        out[n] = ax;
        n += 1;
        state.total_auto_learned += 1;
    }
    return n;
}

/// Contradiction Detection: Scan all axioms for potential contradictions.
/// Two axioms contradict if they share many keywords but assert opposite things.
pub const Contradiction = struct {
    axiom_a: u32,
    axiom_b: u32,
    reason: [128]u8 = std.mem.zeroes([128]u8),
    reason_len: u8 = 0,
};

pub fn detectContradictions(
    axiom_texts: []const []const u8,
    out: []Contradiction,
) usize {
    var n: usize = 0;
    var i: usize = 0;
    while (i < axiom_texts.len) : (i += 1) {
        var j: usize = i + 1;
        while (j < axiom_texts.len) : (j += 1) {
            const a = axiom_texts[i];
            const b = axiom_texts[j];

            // Check for negation patterns: one says X, the other says NOT X
            if (containsNegation(a) and containsNegation(b)) continue;

            // Check if they share enough keywords but have negation
            const shared = sharedKeywordCount(a, b);
            if (shared >= 2 and (containsNegation(a) or containsNegation(b)) and n < out.len) {
                var reason_buf: [128]u8 = undefined;
                const reason = std.fmt.bufPrint(&reason_buf, "shared={d} keywords with negation", .{shared}) catch "";
                var c = Contradiction{
                    .axiom_a = @intCast(i),
                    .axiom_b = @intCast(j),
                };
                @memcpy(c.reason[0..reason.len], reason);
                c.reason_len = @intCast(reason.len);
                out[n] = c;
                n += 1;
            }
        }
    }
    return n;
}

/// Self-Evolution: Analyze overall performance and decide what to improve.
/// Returns an evolution plan as text.
pub fn selfEvolve(state: *const SelfState, lang: Language, out: []u8) usize {
    var pos: usize = 0;
    const avg_conf = selfConfidence(state);
    const fail_rate: f32 = if (state.total_queries > 0)
        @as(f32, @floatFromInt(state.total_failed)) / @as(f32, @floatFromInt(state.total_queries))
    else
        0.0;

    switch (lang) {
        .english => {
            pos += writeStr(out[pos..], "=== Self-Evolution Plan ===\n\n");

            // Analyze performance
            pos += writeFmt(out[pos..], "Performance: {d:.1}% success, {d:.2} avg confidence\n\n", .{
                (1.0 - fail_rate) * 100.0,
                avg_conf,
            });

            // Determine what to improve
            if (fail_rate > 0.3) {
                pos += writeStr(out[pos..], "PRIORITY: High failure rate detected.\n");
                pos += writeStr(out[pos..], "  → Activate aggressive self-learning.\n");
                pos += writeStr(out[pos..], "  → Increase crawler foraging for new axioms.\n");
                pos += writeStr(out[pos..], "  → Generate self-test questions for weak domains.\n\n");
            }

            // Check domain weaknesses
            var weak_domains: usize = 0;
            for (state.domain_weakness) |ds| {
                if (ds.weak) weak_domains += 1;
            }
            if (weak_domains > 0) {
                pos += writeFmt(out[pos..], "WEAK DOMAINS: {d} domains need attention.\n", .{weak_domains});
                for (state.domain_weakness) |ds| {
                    if (ds.weak) {
                        pos += writeFmt(out[pos..], "  → {s}: {d:.2} avg confidence ({d}/{d} low)\n", .{
                            domainNameEn(ds.domain),
                            ds.avg_confidence,
                            ds.low_confidence_count,
                            ds.query_count,
                        });
                    }
                }
                pos += writeStr(out[pos..], "\n");
            }

            // Check unmatched words
            if (state.unmatched_count > 5) {
                pos += writeFmt(out[pos..], "KNOWLEDGE GAPS: {d} unmatched concepts detected.\n", .{state.unmatched_count});
                pos += writeStr(out[pos..], "  → Run /self learn to generate provisional axioms.\n\n");
            }

            // Overall recommendation
            if (avg_conf > 0.7) {
                pos += writeStr(out[pos..], "STATUS: System is performing well.\n");
                pos += writeStr(out[pos..], "  → Continue normal operation.\n");
                pos += writeStr(out[pos..], "  → Focus on creative synthesis and cross-domain analogy.\n");
            } else if (avg_conf > 0.4) {
                pos += writeStr(out[pos..], "STATUS: Moderate performance — room for improvement.\n");
                pos += writeStr(out[pos..], "  → Strengthen weak domains with targeted learning.\n");
                pos += writeStr(out[pos..], "  → Expand axiom base in underperforming areas.\n");
            } else {
                pos += writeStr(out[pos..], "STATUS: Critical — significant improvement needed.\n");
                pos += writeStr(out[pos..], "  → Activate all self-learning mechanisms.\n");
                pos += writeStr(out[pos..], "  → Prioritize axiom acquisition for weak domains.\n");
                pos += writeStr(out[pos..], "  → Run self-reflection tests immediately.\n");
            }

            // Auto-learned axioms status
            if (state.total_auto_learned > 0) {
                pos += writeFmt(out[pos..], "\nSELF-LEARNED: {d} axioms generated autonomously.\n", .{state.total_auto_learned});
                pos += writeStr(out[pos..], "  → These need verification through self-testing.\n");
            }
        },
        .arabic => {
            pos += writeStr(out[pos..], "=== خطة التطور الذاتي ===\n\n");
            pos += writeFmt(out[pos..], "الأداء: {d:.1}% نجاح، {d:.2} متوسط الثقة\n\n", .{
                (1.0 - fail_rate) * 100.0,
                avg_conf,
            });

            if (fail_rate > 0.3) {
                pos += writeStr(out[pos..], "أولوية: معدل فشل مرتفع.\n");
                pos += writeStr(out[pos..], "  ← تفعيل التعلم الذاتي المكثف.\n");
                pos += writeStr(out[pos..], "  ← زيادة البحث عن بديهيات جديدة.\n\n");
            }

            if (avg_conf > 0.7) {
                pos += writeStr(out[pos..], "الحالة: النظام يعمل بشكل جيد.\n");
                pos += writeStr(out[pos..], "  ← الاستمرار في التشغيل العادي.\n");
            } else if (avg_conf > 0.4) {
                pos += writeStr(out[pos..], "الحالة: أداء متوسط — مجال للتحسين.\n");
                pos += writeStr(out[pos..], "  ← تعزيز المجالات الضعيفة.\n");
            } else {
                pos += writeStr(out[pos..], "الحالة: حرج — يحتاج تحسيناً كبيراً.\n");
                pos += writeStr(out[pos..], "  ← تفعيل جميع آليات التعلم الذاتي.\n");
            }

            if (state.total_auto_learned > 0) {
                pos += writeFmt(out[pos..], "\nبديهيات مُتعلَّمة: {d} بديهية مولّدة ذاتياً.\n", .{state.total_auto_learned});
            }
        },
    }

    return pos;
}

/// IQ Report: Comprehensive intelligence self-assessment.
/// Scores the system across multiple dimensions (0-100 each).
pub const IQReport = struct {
    knowledge_breadth: u8 = 0, // How many domains are covered
    knowledge_depth: u8 = 0, // How many axioms per domain
    reasoning_accuracy: u8 = 0, // Average confidence
    self_awareness: u8 = 0, // How well it knows its weaknesses
    learning_rate: u8 = 0, // How fast it acquires new knowledge
    adaptability: u8 = 0, // How well it handles novel queries
    overall_iq: u16 = 0, // Weighted average
};

pub fn generateIQReport(state: *const SelfState, axiom_count: usize, domain_count: usize) IQReport {
    var report = IQReport{};

    // Knowledge breadth: how many domains have axioms
    report.knowledge_breadth = @intCast(@min(domain_count * 10, 100));

    // Knowledge depth: axioms per domain (ideal: 10+)
    const avg_per_domain = if (domain_count > 0) axiom_count / domain_count else 0;
    report.knowledge_depth = @intCast(@min(avg_per_domain * 10, 100));

    // Reasoning accuracy: based on avg confidence
    const conf = selfConfidence(state);
    report.reasoning_accuracy = @intFromFloat(conf * 100.0);

    // Self-awareness: based on how many queries were tracked
    if (state.total_queries > 10) {
        report.self_awareness = @intCast(@min(state.total_queries, 100));
    }

    // Learning rate: based on auto-learned axioms
    report.learning_rate = @intCast(@min(state.total_auto_learned * 20, 100));

    // Adaptability: based on handling novel queries (1 - fail rate)
    const fail_rate: f32 = if (state.total_queries > 0)
        @as(f32, @floatFromInt(state.total_failed)) / @as(f32, @floatFromInt(state.total_queries))
    else
        0.5;
    report.adaptability = @intFromFloat((1.0 - fail_rate) * 100.0);

    // Overall IQ: weighted average
    const iq: f32 =
        @as(f32, @floatFromInt(report.knowledge_breadth)) * 0.15 +
        @as(f32, @floatFromInt(report.knowledge_depth)) * 0.15 +
        @as(f32, @floatFromInt(report.reasoning_accuracy)) * 0.25 +
        @as(f32, @floatFromInt(report.self_awareness)) * 0.15 +
        @as(f32, @floatFromInt(report.learning_rate)) * 0.10 +
        @as(f32, @floatFromInt(report.adaptability)) * 0.20;
    report.overall_iq = @intFromFloat(iq);

    return report;
}

/// Format IQ report as text.
pub fn formatIQReport(report: IQReport, lang: Language, out: []u8) usize {
    var pos: usize = 0;
    switch (lang) {
        .english => {
            pos += writeStr(out[pos..], "═══ Intelligence Quotient Report ═══\n\n");
            pos += writeFmt(out[pos..], "  Knowledge Breadth:    {d:>3}/100\n", .{report.knowledge_breadth});
            pos += writeFmt(out[pos..], "  Knowledge Depth:      {d:>3}/100\n", .{report.knowledge_depth});
            pos += writeFmt(out[pos..], "  Reasoning Accuracy:   {d:>3}/100\n", .{report.reasoning_accuracy});
            pos += writeFmt(out[pos..], "  Self-Awareness:       {d:>3}/100\n", .{report.self_awareness});
            pos += writeFmt(out[pos..], "  Learning Rate:        {d:>3}/100\n", .{report.learning_rate});
            pos += writeFmt(out[pos..], "  Adaptability:         {d:>3}/100\n", .{report.adaptability});
            pos += writeStr(out[pos..], "  ─────────────────────────────\n");
            pos += writeFmt(out[pos..], "  OVERALL IQ:           {d:>3}/100\n\n", .{report.overall_iq});

            if (report.overall_iq >= 80) {
                pos += writeStr(out[pos..], "  Rating: EXCEPTIONAL\n");
            } else if (report.overall_iq >= 60) {
                pos += writeStr(out[pos..], "  Rating: ABOVE AVERAGE\n");
            } else if (report.overall_iq >= 40) {
                pos += writeStr(out[pos..], "  Rating: AVERAGE\n");
            } else {
                pos += writeStr(out[pos..], "  Rating: DEVELOPING\n");
            }
        },
        .arabic => {
            pos += writeStr(out[pos..], "═══ تقرير نسبة الذكاء ═══\n\n");
            pos += writeFmt(out[pos..], "  اتساع المعرفة:        {d:>3}/100\n", .{report.knowledge_breadth});
            pos += writeFmt(out[pos..], "  عمق المعرفة:          {d:>3}/100\n", .{report.knowledge_depth});
            pos += writeFmt(out[pos..], "  دقة الاستدلال:        {d:>3}/100\n", .{report.reasoning_accuracy});
            pos += writeFmt(out[pos..], "  الوعي الذاتي:         {d:>3}/100\n", .{report.self_awareness});
            pos += writeFmt(out[pos..], "  معدل التعلم:          {d:>3}/100\n", .{report.learning_rate});
            pos += writeFmt(out[pos..], "  القدرة على التكيف:    {d:>3}/100\n", .{report.adaptability});
            pos += writeStr(out[pos..], "  ─────────────────────────────\n");
            pos += writeFmt(out[pos..], "  نسبة الذكاء الإجمالية: {d:>3}/100\n\n", .{report.overall_iq});

            if (report.overall_iq >= 80) {
                pos += writeStr(out[pos..], "  التصنيف: استثنائي\n");
            } else if (report.overall_iq >= 60) {
                pos += writeStr(out[pos..], "  التصنيف: فوق المتوسط\n");
            } else if (report.overall_iq >= 40) {
                pos += writeStr(out[pos..], "  التصنيف: متوسط\n");
            } else {
                pos += writeStr(out[pos..], "  التصنيف: في التطور\n");
            }
        },
    }
    return pos;
}

// ─── Helper functions for advanced features ──────────

fn extractTopic(query: []const u8, buf: []u8) []const u8 {
    // Remove common question prefixes to get the topic.
    const prefixes = [_][]const u8{
        "what is ", "what are ", "what's ", "who is ", "who are ",
        "why does ", "why do ", "why is ", "why are ",
        "how does ", "how do ", "how is ", "how are ",
        "define ", "explain ", "describe ",
    };
    var text = query;
    for (prefixes) |prefix| {
        if (std.mem.startsWith(u8, text, prefix)) {
            text = text[prefix.len..];
            break;
        }
    }
    // Strip trailing punctuation
    var end = text.len;
    while (end > 0 and (text[end - 1] == '?' or text[end - 1] == '.' or text[end - 1] == '!')) {
        end -= 1;
    }
    const n = @min(end, buf.len);
    @memcpy(buf[0..n], text[0..n]);
    return buf[0..n];
}

fn containsNegation(text: []const u8) bool {
    const negations = [_][]const u8{ "not ", "never", "cannot", "can't", "no ", "impossible", "false" };
    for (negations) |neg| {
        if (std.mem.indexOf(u8, text, neg) != null) return true;
    }
    return false;
}

fn sharedKeywordCount(a: []const u8, b: []const u8) usize {
    var words_a: [16][]const u8 = undefined;
    var na: usize = 0;
    tokenize(a, &words_a, &na);

    var count: usize = 0;
    for (words_a[0..na]) |wa| {
        if (wa.len < 4) continue;
        if (std.mem.indexOf(u8, b, wa) != null) count += 1;
    }
    return count;
}

// ─── Tests ────────────────────────────────────────────

test "self state initialization" {
    const state = SelfState{};
    try std.testing.expectEqual(@as(u64, 0), state.total_queries);
    try std.testing.expect(state.self_learning_enabled);
}

test "record query result" {
    var state = SelfState{};
    recordQueryResult(&state, 0, 0.7, &[_][]const u8{}, true);
    try std.testing.expectEqual(@as(u64, 1), state.total_queries);
}

test "record unmatched word" {
    var state = SelfState{};
    const words = [_][]const u8{"photosynthesis"};
    recordQueryResult(&state, 2, 0.2, &words, false);
    try std.testing.expect(state.unmatched_count > 0);
}

test "self confidence" {
    var state = SelfState{};
    recordQueryResult(&state, 0, 0.8, &[_][]const u8{}, true);
    recordQueryResult(&state, 0, 0.6, &[_][]const u8{}, true);
    const conf = selfConfidence(&state);
    try std.testing.expect(conf > 0.6 and conf < 0.8);
}
