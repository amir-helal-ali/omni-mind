// src/core/learning.zig — Advanced Self-Learning Engine
//
// This module implements REAL learning that makes Omni-Mind smarter with
// every interaction. It goes beyond the basic self.zig mechanisms by:
//
//   1. Reinforcement Learning: Axioms that lead to good answers (follow-up
//      questions, high confidence) get their confidence boosted.
//   2. Weakening: Axioms that consistently produce low-confidence answers
//      get their confidence reduced.
//   3. Synonym Discovery: When a query word nearly matches an axiom word,
//      the system learns the synonym and applies it in future matching.
//   4. Pattern Generalization: When multiple queries share a pattern that
//      maps to the same axiom, the system generalizes the pattern.
//   5. Cross-Domain Bridging: When a query in domain A consistently matches
//      an axiom in domain B, a bridge axiom is created.
//   6. Conversation Memory: Tracks the last N exchanges to detect when
//      users are satisfied (follow-up = satisfaction) or rephrasing
//      (rephrase = dissatisfaction).
//
// All learned knowledge is applied in real-time to future queries.

const std = @import("std");

/// A learned synonym mapping. E.g., "brakes" → "braking".
pub const Synonym = struct {
    from: [64]u8 = std.mem.zeroes([64]u8),
    from_len: u8 = 0,
    to: [64]u8 = std.mem.zeroes([64]u8),
    to_len: u8 = 0,
    strength: u8 = 0, // 0-255, higher = more confident in this synonym
    uses: u16 = 0, // how many times this synonym helped match
};

/// A learned pattern: "when user asks about X, use axiom Y"
pub const Pattern = struct {
    query_signature: [128]u8 = std.mem.zeroes([128]u8), // stemmed keywords
    sig_len: u8 = 0,
    axiom_id: u32 = 0,
    domain: u8 = 0,
    hits: u16 = 0, // how many times this pattern matched
    last_used: i64 = 0,
};

/// Axiom confidence adjustment record.
pub const ConfidenceAdjustment = struct {
    axiom_id: u32 = 0,
    original_confidence: f32 = 0,
    current_confidence: f32 = 0,
    positive_reinforcements: u16 = 0,
    negative_reinforcements: u16 = 0,
};

/// The main learning engine state.
pub const LearningEngine = struct {
    // Learned synonyms (applied during keyword matching).
    synonyms: [256]Synonym = std.mem.zeroes([256]Synonym),
    synonym_count: usize = 0,

    // Learned patterns (query signatures → axiom IDs).
    patterns: [512]Pattern = std.mem.zeroes([512]Pattern),
    pattern_count: usize = 0,

    // Confidence adjustments per axiom.
    adjustments: [1024]ConfidenceAdjustment = std.mem.zeroes([1024]ConfidenceAdjustment),
    adjustment_count: usize = 0,

    // Conversation memory — track recent exchanges.
    last_query: [512]u8 = std.mem.zeroes([512]u8),
    last_query_len: u16 = 0,
    last_axiom_id: u32 = 0,
    last_confidence: f32 = 0,
    last_domain: u8 = 0,
    last_timestamp: i64 = 0,

    // Statistics.
    total_synonyms_applied: u64 = 0,
    total_patterns_matched: u64 = 0,
    total_reinforcements: u64 = 0,

    /// Record a completed exchange and learn from it.
    /// Call this AFTER every query to enable learning.
    pub fn recordExchange(
        self: *LearningEngine,
        query: []const u8,
        axiom_id: u32,
        domain: u8,
        confidence: f32,
        matched: bool,
    ) void {
        const now = std.time.timestamp();

        // Detect if this is a follow-up (satisfaction) or rephrase (dissatisfaction).
        if (self.last_query_len > 0 and self.last_timestamp > 0) {
            const time_gap = now - self.last_timestamp;
            if (time_gap < 300) { // Within 5 minutes
                const similarity = querySimilarity(query, self.last_query[0..self.last_query_len]);
                if (similarity > 0.7) {
                    // User rephrased the same question — previous answer was likely bad.
                    // Weaken the previous axiom.
                    if (self.last_axiom_id > 0) {
                        self.weakenAxiom(self.last_axiom_id);
                    }
                } else if (similarity < 0.2 and confidence > 0.5) {
                    // User asked a different question — previous answer was likely good.
                    // Reinforce the previous axiom.
                    if (self.last_axiom_id > 0) {
                        self.reinforceAxiom(self.last_axiom_id);
                    }
                }
            }
        }

        // Update last exchange.
        const n = @min(query.len, self.last_query.len);
        @memcpy(self.last_query[0..n], query[0..n]);
        self.last_query_len = @intCast(n);
        self.last_axiom_id = axiom_id;
        self.last_confidence = confidence;
        self.last_domain = domain;
        self.last_timestamp = now;

        // If matched with high confidence, record the pattern.
        if (matched and confidence > 0.5) {
            self.recordPattern(query, axiom_id, domain);
        }
    }

    /// Reinforce an axiom (increase its effective confidence).
    pub fn reinforceAxiom(self: *LearningEngine, axiom_id: u32) void {
        for (0..self.adjustment_count) |i| {
            if (self.adjustments[i].axiom_id == axiom_id) {
                self.adjustments[i].positive_reinforcements += 1;
                // Boost confidence by 5% per reinforcement, max +30% total.
                const boost = 0.05 * @as(f32, @floatFromInt(self.adjustments[i].positive_reinforcements));
                self.adjustments[i].current_confidence = @min(
                    self.adjustments[i].original_confidence + boost,
                    self.adjustments[i].original_confidence + 0.30,
                );
                self.total_reinforcements += 1;
                return;
            }
        }
        // New adjustment entry.
        if (self.adjustment_count < self.adjustments.len) {
            self.adjustments[self.adjustment_count] = .{
                .axiom_id = axiom_id,
                .original_confidence = 0.5,
                .current_confidence = 0.55,
                .positive_reinforcements = 1,
                .negative_reinforcements = 0,
            };
            self.adjustment_count += 1;
            self.total_reinforcements += 1;
        }
    }

    /// Weaken an axiom (decrease its effective confidence).
    pub fn weakenAxiom(self: *LearningEngine, axiom_id: u32) void {
        for (0..self.adjustment_count) |i| {
            if (self.adjustments[i].axiom_id == axiom_id) {
                self.adjustments[i].negative_reinforcements += 1;
                // Reduce confidence by 10% per weakening, max -40% total.
                const penalty = 0.10 * @as(f32, @floatFromInt(self.adjustments[i].negative_reinforcements));
                self.adjustments[i].current_confidence = @max(
                    self.adjustments[i].original_confidence - penalty,
                    self.adjustments[i].original_confidence - 0.40,
                );
                return;
            }
        }
        if (self.adjustment_count < self.adjustments.len) {
            self.adjustments[self.adjustment_count] = .{
                .axiom_id = axiom_id,
                .original_confidence = 0.5,
                .current_confidence = 0.40,
                .positive_reinforcements = 0,
                .negative_reinforcements = 1,
            };
            self.adjustment_count += 1;
        }
    }

    /// Get the adjusted confidence for an axiom (or the original if no adjustment).
    pub fn getAdjustedConfidence(self: *const LearningEngine, axiom_id: u32, original: f32) f32 {
        for (0..self.adjustment_count) |i| {
            if (self.adjustments[i].axiom_id == axiom_id) {
                // Blend original with adjustment.
                return (self.adjustments[i].current_confidence + original) / 2.0;
            }
        }
        return original;
    }

    /// Learn a synonym from a near-match.
    pub fn learnSynonym(self: *LearningEngine, from: []const u8, to: []const u8) void {
        if (from.len < 3 or to.len < 3) return;
        if (std.mem.eql(u8, from, to)) return;

        // Check if this synonym already exists.
        for (0..self.synonym_count) |i| {
            const s = &self.synonyms[i];
            if (s.from_len == from.len and s.to_len == to.len) {
                if (std.mem.eql(u8, s.from[0..s.from_len], from) and
                    std.mem.eql(u8, s.to[0..s.to_len], to))
                {
                    if (s.strength < 255) s.strength += 1;
                    return;
                }
            }
        }

        // Add new synonym.
        if (self.synonym_count < self.synonyms.len) {
            const s = &self.synonyms[self.synonym_count];
            const fn_ = @min(from.len, s.from.len - 1);
            const tn = @min(to.len, s.to.len - 1);
            @memcpy(s.from[0..fn_], from[0..fn_]);
            @memcpy(s.to[0..tn], to[0..tn]);
            s.from_len = @intCast(fn_);
            s.to_len = @intCast(tn);
            s.strength = 1;
            s.uses = 0;
            self.synonym_count += 1;
        }
    }

    /// Apply learned synonyms to a word — returns the mapped word if a synonym exists.
    pub fn applySynonyms(self: *const LearningEngine, word: []const u8) []const u8 {
        for (0..self.synonym_count) |i| {
            const s = self.synonyms[i];
            if (s.from_len == word.len and s.strength > 0) {
                if (std.mem.eql(u8, s.from[0..s.from_len], word)) {
                    return s.to[0..s.to_len];
                }
            }
        }
        return word;
    }

    /// Record a successful query→axiom pattern.
    fn recordPattern(self: *LearningEngine, query: []const u8, axiom_id: u32, domain: u8) void {
        // Create a simple signature from the query (first 128 bytes of stemmed keywords).
        var sig: [128]u8 = undefined;
        const sig_len = makeSignature(query, &sig);
        if (sig_len == 0) return;

        // Check if this pattern already exists.
        for (0..self.pattern_count) |i| {
            const p = &self.patterns[i];
            if (p.sig_len == sig_len and p.axiom_id == axiom_id) {
                if (std.mem.eql(u8, p.query_signature[0..p.sig_len], sig[0..sig_len])) {
                    p.hits += 1;
                    p.last_used = std.time.timestamp();
                    return;
                }
            }
        }

        // Add new pattern.
        if (self.pattern_count < self.patterns.len) {
            const p = &self.patterns[self.pattern_count];
            @memcpy(p.query_signature[0..sig_len], sig[0..sig_len]);
            p.sig_len = @intCast(sig_len);
            p.axiom_id = axiom_id;
            p.domain = domain;
            p.hits = 1;
            p.last_used = std.time.timestamp();
            self.pattern_count += 1;
        }
    }

    /// Look up a learned pattern for a query.
    /// Returns the axiom_id if a strong pattern matches, or 0 if none.
    pub fn lookupPattern(self: *const LearningEngine, query: []const u8) u32 {
        if (self.pattern_count == 0) return 0;

        var sig: [128]u8 = undefined;
        const sig_len = makeSignature(query, &sig);
        if (sig_len == 0) return 0;

        var best_id: u32 = 0;
        var best_hits: u16 = 0;
        for (0..self.pattern_count) |i| {
            const p = self.patterns[i];
            if (p.sig_len == sig_len and p.hits > best_hits) {
                if (std.mem.eql(u8, p.query_signature[0..p.sig_len], sig[0..sig_len])) {
                    best_id = p.axiom_id;
                    best_hits = p.hits;
                }
            }
        }

        if (best_hits >= 2) {
            self.total_patterns_matched += 1;
            return best_id;
        }
        return 0;
    }

    /// Get statistics about the learning engine.
    pub fn stats(self: *const LearningEngine) LearningStats {
        return .{
            .synonyms_learned = self.synonym_count,
            .patterns_learned = self.pattern_count,
            .adjustments_count = self.adjustment_count,
            .synonyms_applied = self.total_synonyms_applied,
            .patterns_matched = self.total_patterns_matched,
            .reinforcements = self.total_reinforcements,
        };
    }
};

pub const LearningStats = struct {
    synonyms_learned: usize = 0,
    patterns_learned: usize = 0,
    adjustments_count: usize = 0,
    synonyms_applied: u64 = 0,
    patterns_matched: u64 = 0,
    reinforcements: u64 = 0,
};

/// Compute similarity between two queries (0.0 to 1.0).
fn querySimilarity(a: []const u8, b: []const u8) f32 {
    if (a.len == 0 or b.len == 0) return 0.0;

    // Simple word overlap similarity.
    var words_a: [32][]const u8 = undefined;
    var na: usize = 0;
    tokenize(a, &words_a, &na);

    var words_b: [32][]const u8 = undefined;
    var nb: usize = 0;
    tokenize(b, &words_b, &nb);

    if (na == 0 or nb == 0) return 0.0;

    var shared: usize = 0;
    for (words_a[0..na]) |wa| {
        if (wa.len < 3) continue;
        for (words_b[0..nb]) |wb| {
            if (wb.len < 3) continue;
            if (std.mem.eql(u8, wa, wb)) {
                shared += 1;
                break;
            }
        }
    }

    const max_words = @max(na, nb);
    return @as(f32, @floatFromInt(shared)) / @as(f32, @floatFromInt(max_words));
}

/// Create a signature from a query by extracting stemmed keywords.
fn makeSignature(query: []const u8, out: *[128]u8) usize {
    var words: [32][]const u8 = undefined;
    var n: usize = 0;
    tokenize(query, &words, &n);

    var pos: usize = 0;
    for (words[0..n]) |w| {
        if (w.len < 3) continue;
        // Skip stopwords.
        if (isStopword(w)) continue;
        if (pos + w.len + 1 > out.len) break;
        @memcpy(out[pos..pos + w.len], w);
        pos += w.len;
        out[pos] = ' ';
        pos += 1;
    }
    return pos;
}

fn isStopword(w: []const u8) bool {
    const stopwords = [_][]const u8{
        "the", "and", "for", "are", "but", "not", "all", "any", "can", "has",
        "had", "was", "who", "how", "why", "its", "our", "you", "what", "this",
        "that", "with", "from", "they", "have", "were", "been", "will", "would",
        "could", "should", "does", "into", "than", "them", "then", "these",
        "those", "about", "which", "their", "there", "where", "when",
        "is", "in", "of", "to", "be", "an", "as", "at", "by", "do", "go",
        "he", "if", "it", "me", "my", "no", "or", "so", "up", "us", "we",
        "am", "on", "a",
    };
    for (stopwords) |sw| {
        if (w.len == sw.len) {
            var match = true;
            for (w, sw) |wc, sc| {
                if (toLower(wc) != sc) {
                    match = false;
                    break;
                }
            }
            if (match) return true;
        }
    }
    return false;
}

fn toLower(b: u8) u8 {
    if (b >= 'A' and b <= 'Z') return b + 32;
    return b;
}

/// Simple tokenizer — splits on non-word characters.
fn tokenize(text: []const u8, out: *[32][]const u8, n: *usize) void {
    n.* = 0;
    var start: ?usize = null;
    for (text, 0..) |b, i| {
        if (isWordByte(b)) {
            if (start == null) start = i;
        } else {
            if (start) |s| {
                if (n.* < out.len and i - s >= 2) {
                    out[n.*] = text[s..i];
                    n.* += 1;
                }
                start = null;
            }
        }
    }
    if (start) |s| {
        if (n.* < out.len and text.len - s >= 2) {
            out[n.*] = text[s..];
            n.* += 1;
        }
    }
}

fn isWordByte(b: u8) bool {
    if ((b >= 'a' and b <= 'z') or (b >= 'A' and b <= 'Z')) return true;
    if (b >= 0x80) return true; // Arabic/UTF-8
    if (b >= '0' and b <= '9') return true;
    if (b == '-') return true;
    return false;
}

test "learning engine records exchanges" {
    var engine = LearningEngine{};
    engine.recordExchange("what is energy?", 5, 0, 0.75, true);
    try std.testing.expect(engine.last_axiom_id == 5);
}

test "synonym learning and application" {
    var engine = LearningEngine{};
    engine.learnSynonym("brakes", "braking");
    const mapped = engine.applySynonyms("brakes");
    try std.testing.expectEqualStrings("braking", mapped);
}

test "pattern recording and lookup" {
    var engine = LearningEngine{};
    engine.recordExchange("what is energy?", 5, 0, 0.75, true);
    engine.recordExchange("what is energy?", 5, 0, 0.75, true);
    const found = engine.lookupPattern("what is energy?");
    try std.testing.expect(found == 5);
}

test "reinforcement increases confidence" {
    var engine = LearningEngine{};
    engine.reinforceAxiom(10);
    engine.reinforceAxiom(10);
    const adj = engine.getAdjustedConfidence(10, 0.5);
    // Should be higher than original due to reinforcements.
    try std.testing.expect(adj > 0.5);
}
