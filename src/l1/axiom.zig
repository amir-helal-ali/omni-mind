// src/l1/axiom.zig — Axiom and AxiomStore.
//
// An axiom is the smallest unit of knowledge. Omni-Mind stores ~100
// axioms per domain; everything else is derived procedurally on demand.
// Each axiom carries a Bloom signature for O(1) concept matching.

const std = @import("std");
const Node = @import("../core/node.zig").Node;
const Domain = @import("../core/node.zig").Domain;
const bloomSig = @import("../core/mmap.zig").bloomSig;
const allocator = @import("../core/allocator.zig");

/// An axiom — a first principle, never derived from anything else.
/// 48 bytes (one cache line + 16B spillover; could be split if needed).
pub const Axiom = extern struct {
    node_id: u64, // 8B  — links back to Node in graph
    domain: u8, // 1B  — physics, bio, logic...
    confidence: u8, // 1B  — 0-255 (0.0-1.0 mapped)
    _pad: [6]u8, // 6B  — pad for u64 alignment
    text_offset: u32, // 4B  — offset into text_blob
    text_len: u32, // 4B  — length of axiom text
    prerequisites: [4]u32, // 16B — up to 4 prerequisite axiom indices
    signature: u64, // 8B  — Bloom signature for fast matching
};

comptime {
    if (@sizeOf(Axiom) != 48) {
        @compileError("Axiom must be exactly 48 bytes");
    }
}

/// Scored axiom ID — used by keyword matching.
pub const ScoredAxiom = struct {
    id: u32,
    score: u32,
};

/// Get the axiom text as a slice into the text blob.
pub fn axiomText(ax: Axiom, blob: []const u8) []const u8 {
    return blob[ax.text_offset .. ax.text_offset + ax.text_len];
}

/// AxiomStore — flat array of axioms + concatenated text blob.
/// Indexed by axiom ID (which equals Node.id for axiom nodes).
pub const AxiomStore = struct {
    axioms: []Axiom,
    text_blob: []const u8,
    by_domain: [256]DomainIndex = [_]DomainIndex{.{ .start = 0, .end = 0 }} ** 256,
    count: usize = 0,

    pub const DomainIndex = struct {
        start: u32,
        end: u32,
    };

    /// Create an empty store with given capacity.
    pub fn init(axiom_cap: usize, text_cap: usize) !AxiomStore {
        const ax = try allocator.allocAligned(Axiom, axiom_cap);
        const txt = try allocator.allocAligned(u8, text_cap);
        @memset(txt, 0); // Zero text blob so the "find first 0" scan works.
        @memset(ax, std.mem.zeroes(Axiom));
        return .{
            .axioms = ax,
            .text_blob = txt,
            .count = 0,
        };
    }

    /// Add an axiom. Returns its index.
    pub fn add(
        self: *AxiomStore,
        domain: u8,
        text_str: []const u8,
        confidence: f32,
        prerequisites: []const u32,
    ) !u32 {
        if (self.count >= self.axioms.len) return error.StoreFull;

        const idx: u32 = @intCast(self.count);
        const text_off = blk: {
            var i: usize = 0;
            while (i < self.text_blob.len and self.text_blob[i] != 0) : (i += 1) {}
            if (i + text_str.len > self.text_blob.len) return error.TextFull;
            break :blk @as(u32, @intCast(i));
        };

        @memcpy(
            @constCast(self.text_blob[text_off .. text_off + text_str.len]),
            text_str,
        );

        var prereq: [4]u32 = .{ 0, 0, 0, 0 };
        const n = @min(prerequisites.len, 4);
        @memcpy(prereq[0..n], prerequisites[0..n]);

        self.axioms[idx] = .{
            .node_id = idx,
            .domain = domain,
            .confidence = @intFromFloat(@max(0, @min(1, confidence)) * 255),
            ._pad = .{ 0, 0, 0, 0, 0, 0 },
            .text_offset = text_off,
            .text_len = @intCast(text_str.len),
            .prerequisites = prereq,
            .signature = bloomSig(text_str),
        };

        self.count += 1;
        // Update domain index.
        // If this is the first axiom in this domain, set start.
        if (self.by_domain[domain].start == 0 and self.by_domain[domain].end == 0) {
            self.by_domain[domain].start = idx;
        }
        self.by_domain[domain].end = idx + 1;

        return idx;
    }

    /// Get an axiom by index. O(1).
    pub fn get(self: *const AxiomStore, idx: u32) ?Axiom {
        if (idx >= self.count) return null;
        return self.axioms[idx];
    }

    /// Iterate axioms in a specific domain.
    pub fn findByDomain(self: *const AxiomStore, domain: u8) []const Axiom {
        const idx = self.by_domain[domain];
        return self.axioms[idx.start..idx.end];
    }

    /// Find axioms whose signature overlaps a query signature
    /// by at least `threshold` bits. Writes matches into `out`.
    pub fn findBySignature(
        self: *const AxiomStore,
        query_sig: u64,
        domain_hint: u8,
        threshold: u8,
        out: []u32,
    ) usize {
        const domain_axioms = self.findByDomain(domain_hint);
        var n: usize = 0;
        for (domain_axioms) |ax| {
            const overlap = @popCount(ax.signature & query_sig);
            if (overlap >= threshold and n < out.len) {
                out[n] = @intCast(ax.node_id);
                n += 1;
            }
        }
        return n;
    }

    /// Find axioms by direct keyword matching.
    /// Searches ALL axioms with English stemming support.
    /// Also matches Arabic keywords against translated axiom texts.
    pub fn findByKeywords(
        self: *const AxiomStore,
        query: []const u8,
        domain_hint: u8,
        out: []ScoredAxiom,
    ) usize {
        // Tokenize the query into words.
        var query_words: [32][]const u8 = undefined;
        var n_words: usize = 0;
        tokenizeWords(query, &query_words, &n_words);

        if (n_words == 0) return 0;

        // Stem English words for better matching.
        var stemmed_words: [32][64]u8 = undefined;
        var stemmed_slices: [32][]const u8 = undefined;
        var n_stemmed: usize = 0;
        for (query_words[0..n_words]) |qw| {
            if (qw.len < 2) continue; // Skip 1-char noise (was < 3; allows AI, pH, DNA, RNA)
            // Check if it's ASCII (English) — stem it
            if (qw[0] < 0x80) {
                const stemmed = @import("../core/conversation.zig").stemEnglish(qw, &stemmed_words[n_stemmed]);
                stemmed_slices[n_stemmed] = stemmed;
            } else {
                // Arabic — use as-is
                stemmed_slices[n_stemmed] = qw;
            }
            n_stemmed += 1;
        }

        // Get translations for Arabic matching.
        const translations = @import("../core/axiom_translations.zig");
        const lang_mod = @import("../core/lang.zig");

        var n: usize = 0;

        for (0..self.count) |i| {
            const ax = self.axioms[i];
            const text_en = axiomText(ax, self.text_blob);
            const text_ar = translations.translate(text_en, .arabic);

            var score: u32 = 0;

            // Match against English text + Arabic translation
            for (query_words[0..n_words]) |qw| {
                if (qw.len < 2) continue; // Skip 1-char noise (was < 3)
                // Skip English stopwords (the, and, for, etc.)
                if (qw[0] < 0x80 and isStopword(qw)) continue;
                var matched = false;

                if (qw[0] < 0x80) {
                    // English word — match against English text (original + stemmed)
                    if (std.mem.indexOf(u8, text_en, qw) != null) {
                        score += 1;
                        matched = true;
                    }
                    if (!matched) {
                        // Try stemmed version
                        var stem_buf: [64]u8 = undefined;
                        const stemmed = @import("../core/conversation.zig").stemEnglish(qw, &stem_buf);
                        if (stemmed.len != qw.len) { // Only if stemming actually changed it
                            if (std.mem.indexOf(u8, text_en, stemmed) != null) {
                                score += 1;
                                matched = true;
                            }
                        }
                    }
                } else {
                    // Arabic word — match against Arabic translation (original + stemmed)
                    if (std.mem.indexOf(u8, text_ar, qw) != null) {
                        score += 1;
                        matched = true;
                    }
                    if (!matched) {
                        // Try Arabic stemmed version
                        var stem_buf: [128]u8 = undefined;
                        const stemmed = @import("../core/conversation.zig").stemArabic(qw, &stem_buf);
                        if (stemmed.len != qw.len) {
                            if (std.mem.indexOf(u8, text_ar, stemmed) != null) {
                                score += 1;
                                matched = true;
                            }
                            // Also try matching stemmed word as substring (partial match)
                            if (!matched and stemmed.len > 4) {
                                // Check if any part of the Arabic text contains the stem
                                if (std.mem.indexOf(u8, text_ar, stemmed) != null) {
                                    score += 1;
                                    matched = true;
                                }
                            }
                        }
                    }
                    // Also try: match the RAW query word against English text
                    // (in case the user typed an English word in Arabic script)
                }
            }

            // Bonus: same domain as hint.
            if (score > 0 and ax.domain == domain_hint) {
                score += 2;
            }

            if (score > 0 and n < out.len) {
                // Insert sorted by score (descending).
                var j: usize = n;
                while (j > 0 and out[j - 1].score < score) : (j -= 1) {
                    out[j] = out[j - 1];
                }
                out[j] = .{ .id = @intCast(i), .score = score };
                n += 1;
            }
        }
        _ = lang_mod;
        return n;
    }
};

/// Check if a byte is likely the SECOND byte of a 2-byte Arabic punctuation.
/// Arabic punctuation: ؟ (D8 9F), ، (D8 8C), ؛ (D8 9B)
/// We need to remove BOTH bytes when trimming.
fn isArabicPunctSecondByte(b: u8) bool {
    return b == 0x9F or b == 0x8C or b == 0x9B;
}

/// Trim trailing punctuation from a word, handling multi-byte UTF-8.
fn trimTrailingPunct(text: []const u8, start: usize, end: usize) usize {
    var e = end;
    while (e > start) {
        const last = text[e - 1];
        // ASCII punctuation
        if (last == '?' or last == '!' or last == '.' or last == ',' or
            last == ';' or last == ':' or last == ')' or last == '(' or
            last == ']' or last == '[' or last == '"' or last == '\'')
        {
            e -= 1;
            continue;
        }
        // Arabic 2-byte punctuation: check if last byte is second byte
        // and the byte before it is 0xD8 (first byte of ؟ ، ؛)
        if (isArabicPunctSecondByte(last) and e >= start + 2 and text[e - 2] == 0xD8) {
            e -= 2; // Remove both bytes
            continue;
        }
        break;
    }
    return e;
}

/// Split text into lowercase words (for keyword matching).
/// Strips trailing punctuation from each word (handles multi-byte Arabic).
fn tokenizeWords(text: []const u8, out: *[32][]const u8, n: *usize) void {
    n.* = 0;
    var word_start: ?usize = null;
    var word_end: usize = 0;
    for (text, 0..) |b, i| {
        if (isWordChar(b)) {
            if (word_start == null) word_start = i;
            word_end = i + 1;
        } else {
            if (word_start) |ws| {
                if (n.* < out.len) {
                    const trimmed_end = trimTrailingPunct(text, ws, word_end);
                    if (trimmed_end > ws and trimmed_end - ws >= 2) {
                        out[n.*] = text[ws..trimmed_end];
                        n.* += 1;
                    }
                }
                word_start = null;
            }
        }
    }
    // Last word
    if (word_start) |ws| {
        if (n.* < out.len) {
            const trimmed_end = trimTrailingPunct(text, ws, word_end);
            if (trimmed_end > ws and trimmed_end - ws >= 2) {
                out[n.*] = text[ws..trimmed_end];
                n.* += 1;
            }
        }
    }
}

fn isWordChar(b: u8) bool {
    // ASCII letters
    if ((b >= 'a' and b <= 'z') or (b >= 'A' and b <= 'Z')) return true;
    // Arabic characters (UTF-8: 0xD8-0xDB first byte, or continuation 0x80-0xBF)
    if (b >= 0x80) return true;
    // Digits
    if (b >= '0' and b <= '9') return true;
    // Hyphen within words
    if (b == '-') return true;
    return false;
}

/// Check if a word is a common English stopword that should be skipped.
fn isStopword(word: []const u8) bool {
    const stopwords = [_][]const u8{
        "the", "and", "for", "are", "but", "not", "all", "any", "can", "has",
        "had", "was", "who", "how", "why", "its", "our", "you", "what", "this",
        "that", "with", "from", "they", "have", "were", "been", "will", "would",
        "could", "should", "does", "into", "than", "them", "then", "these",
        "those", "about", "which", "their", "there", "where", "when",
        // 2-char common English words (so 2-char concept words like AI, pH, DNA, RNA pass through)
        "is", "in", "of", "to", "be", "an", "as", "at", "by", "do", "go",
        "he", "if", "it", "me", "my", "no", "or", "so", "up", "us", "we",
        "am", "on", "or",
    };
    for (stopwords) |sw| {
        if (word.len == sw.len) {
            var match = true;
            for (word, sw) |wc, sc| {
                if (toLowerAscii(wc) != sc) {
                    match = false;
                    break;
                }
            }
            if (match) return true;
        }
    }
    return false;
}

fn toLowerAscii(b: u8) u8 {
    if (b >= 'A' and b <= 'Z') return b + 32;
    return b;
}

test "axiom store add and find" {
    allocator.init();
    var store = try AxiomStore.init(64, 4096);

    const id = try store.add(
        @intFromEnum(Domain.physics),
        "energy is conserved",
        1.0,
        &[_]u32{},
    );
    try std.testing.expectEqual(@as(u32, 0), id);
    try std.testing.expectEqual(@as(usize, 1), store.count);

    const ax = store.get(0).?;
    try std.testing.expectEqualStrings("energy is conserved", axiomText(ax, store.text_blob));

    const sig = bloomSig("energy is conserved");
    var out: [16]u32 = undefined;
    const n = store.findBySignature(sig, @intFromEnum(Domain.physics), 8, &out);
    try std.testing.expect(n >= 1);
}

test "short 2-char keywords match (AI, pH, DNA, RNA, sql)" {
    allocator.init();
    var store = try AxiomStore.init(64, 8192);
    _ = try store.add(
        @intFromEnum(Domain.computer_science),
        "AI is artificial intelligence",
        1.0,
        &[_]u32{},
    );
    _ = try store.add(
        @intFromEnum(Domain.chemistry),
        "pH measures acidity",
        1.0,
        &[_]u32{},
    );

    var out: [16]ScoredAxiom = undefined;
    // Query "AI" (2 bytes) should now match (was filtered by len<3 before)
    const n1 = store.findByKeywords("what is AI?", 5, &out);
    try std.testing.expect(n1 >= 1);

    // Query "pH" (2 bytes) should match
    const n2 = store.findByKeywords("what is pH?", 1, &out);
    try std.testing.expect(n2 >= 1);
}
