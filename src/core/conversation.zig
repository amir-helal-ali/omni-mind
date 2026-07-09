// src/core/conversation.zig — Conversation context, question type detection,
// anaphora resolution, and natural language generation.
//
// This module transforms Omni-Mind from a query-answer machine into
// a conversational AI that remembers context, understands follow-up
// questions, and generates natural sentences.

const std = @import("std");
const Language = @import("lang.zig").Language;
const translate = @import("axiom_translations.zig").translate;

/// Question type — determines how we compose the answer.
pub const QuestionType = enum(u8) {
    what_is, // "what is X", "ما هو X"
    why, // "why does X", "لماذا"
    how, // "how does X", "كيف"
    explain_more, // "tell me more", "أخبرني المزيد"
    compare, // "compare X and Y", "قارن"
    yes_no, // "is X true", "هل"
    example, // "give an example", "مثال"
    definition, // "define X", "عرّف"
    list, // "list all", "عدد"
    general, // fallback

    pub fn detect(query: []const u8, lang: Language) QuestionType {
        // English patterns
        const has = struct {
            fn check(text: []const u8, needles: []const []const u8) bool {
                for (needles) |n| {
                    if (std.mem.indexOf(u8, text, n) != null) return true;
                }
                return false;
            }
        };

        switch (lang) {
            .english => {
                if (has.check(query, &.{ "tell me more", "explain more", "elaborate", "go on", "continue", "more about" })) return .explain_more;
                if (has.check(query, &.{ "what is", "what are", "what's", "who is", "who are" })) return .what_is;
                if (has.check(query, &.{ "define", "definition of" })) return .definition;
                if (has.check(query, &.{ "why" })) return .why;
                if (has.check(query, &.{ "how" })) return .how;
                if (has.check(query, &.{ "compare", "difference between", "versus", " vs " })) return .compare;
                if (has.check(query, &.{ "is ", "are ", "does ", "do ", "can ", "could ", "should ", "would ", "will ", "have ", "has ", "had " })) return .yes_no;
                if (has.check(query, &.{ "example", "instance", "illustration" })) return .example;
                if (has.check(query, &.{ "list", "enumerate", "name all" })) return .list;
            },
            .arabic => {
                if (has.check(query, &.{ "أخبرني المزيد", "اكثر", "تفصيل", "استمر", "المزيد" })) return .explain_more;
                if (has.check(query, &.{ "ما هو", "ما هي", "ما هو", "من هو", "من هي" })) return .what_is;
                if (has.check(query, &.{ "عرّف", "تعريف" })) return .definition;
                if (has.check(query, &.{ "لماذا", "لِماذا" })) return .why;
                if (has.check(query, &.{ "كيف" })) return .how;
                if (has.check(query, &.{ "قارن", "الفرق بين" })) return .compare;
                if (has.check(query, &.{ "هل" })) return .yes_no;
                if (has.check(query, &.{ "مثال" })) return .example;
                if (has.check(query, &.{ "عدد", "اذكر" })) return .list;
            },
        }
        return .general;
    }
};

/// Conversation context — tracks the last N exchanges.
pub const ConversationContext = struct {
    history: [8]Exchange = std.mem.zeroes([8]Exchange),
    count: usize = 0,
    head: usize = 0,

    pub const Exchange = struct {
        query: [512]u8 = std.mem.zeroes([512]u8),
        query_len: u16 = 0,
        axiom_id: u32 = 0,
        domain: u8 = 0,
        confidence: f32 = 0,
        valid: bool = false,
    };

    /// Record a new exchange.
    pub fn record(self: *ConversationContext, query: []const u8, axiom_id: u32, domain: u8, confidence: f32) void {
        const slot = &self.history[self.head];
        const n = @min(query.len, 511);
        @memcpy(slot.query[0..n], query[0..n]);
        slot.query_len = @intCast(n);
        slot.axiom_id = axiom_id;
        slot.domain = domain;
        slot.confidence = confidence;
        slot.valid = true;

        self.head = (self.head + 1) % 8;
        if (self.count < 8) self.count += 1;
    }

    /// Get the last exchange (most recent).
    pub fn last(self: *const ConversationContext) ?*const Exchange {
        if (self.count == 0) return null;
        const idx = if (self.head == 0) 7 else self.head - 1;
        if (!self.history[idx].valid) return null;
        return &self.history[idx];
    }

    /// Get the last query text.
    pub fn lastQuery(self: *const ConversationContext) []const u8 {
        if (self.last()) |ex| {
            return ex.query[0..ex.query_len];
        }
        return "";
    }

    /// Resolve anaphora: if the query is a follow-up, return the
    /// topic from the previous query.
    pub fn resolveTopic(self: *const ConversationContext, query: []const u8, qtype: QuestionType) []const u8 {
        if (qtype == .explain_more) {
            // "tell me more" → use the previous query's topic.
            return self.lastQuery();
        }
        return query;
    }

    /// Clear context (new conversation).
    pub fn clear(self: *ConversationContext) void {
        self.count = 0;
        self.head = 0;
        for (&self.history) |*ex| ex.valid = false;
    }
};

/// Simple English stemmer — strips common suffixes.
/// Only stems words longer than 5 chars to avoid breaking short words
/// like "energy" → "ener" (too aggressive).
pub fn stemEnglish(word: []const u8, buf: []u8) []const u8 {
    if (word.len < 4 or buf.len < word.len) return word;
    @memcpy(buf[0..word.len], word);
    var len = word.len;

    // Strip common suffixes (order matters: longest first).
    const suffixes = [_][]const u8{ "tion", "sion", "ness", "ment", "able", "ible", "ence", "ance", "ing", "ies", "ied", "ed", "es", "ly", "s" };

    for (suffixes) |sfx| {
        if (len > sfx.len + 2) { // Keep at least 3 chars stem.
            if (std.mem.eql(u8, buf[len - sfx.len .. len], sfx)) {
                len -= sfx.len;
                if (std.mem.eql(u8, sfx, "ies") and buf.len > len + 1) {
                    buf[len] = 'y';
                    len += 1;
                }
                break;
            }
        }
    }

    return buf[0..len];
}

/// Simple Arabic stemmer — removes common Arabic prefixes/suffixes.
/// "التضخم" → "ضخم", "الطاقة" → "طاقة", "الكيمياء" → "كيمياء"
/// Handles common Arabic morphological affixes for better keyword matching.
pub fn stemArabic(word: []const u8, buf: []u8) []const u8 {
    if (word.len < 4 or buf.len < word.len) return word;
    @memcpy(buf[0..word.len], word);
    var len = word.len;

    // ── Suffix removal (do suffixes first to expose root, then prefixes) ──

    // Remove "؟" suffix (UTF-8: 0xD8 0x9F = question mark)
    if (len > 4) {
        if (buf[len - 2] == 0xD8 and buf[len - 1] == 0x9F) {
            len -= 2;
        }
    }

    // Remove "ها" suffix (UTF-8: 0xD9 0x87 0xD8 0xA7 = her/its feminine)
    if (len > 6) {
        if (buf[len - 4] == 0xD9 and buf[len - 3] == 0x87 and buf[len - 2] == 0xD8 and buf[len - 1] == 0xA7) {
            len -= 4;
        }
    }

    // Remove "هم" suffix (UTF-8: 0xD9 0x87 0xD9 0x85 = their/masculine)
    if (len > 6) {
        if (buf[len - 4] == 0xD9 and buf[len - 3] == 0x87 and buf[len - 2] == 0xD9 and buf[len - 1] == 0x85) {
            len -= 4;
        }
    }

    // Remove "نا" suffix (UTF-8: 0xD9 0x86 0xD8 0xA7 = our)
    if (len > 6) {
        if (buf[len - 4] == 0xD9 and buf[len - 3] == 0x86 and buf[len - 2] == 0xD8 and buf[len - 1] == 0xA7) {
            len -= 4;
        }
    }

    // Remove "ون" suffix (UTF-8: 0xD9 0x88 0xD9 0x86 = masculine plural)
    if (len > 6) {
        if (buf[len - 4] == 0xD9 and buf[len - 3] == 0x88 and buf[len - 2] == 0xD9 and buf[len - 1] == 0x86) {
            len -= 4;
        }
    }

    // Remove "ين" suffix (UTF-8: 0xD9 0x8A 0xD9 0x86 = genitive/accusative plural)
    if (len > 6) {
        if (buf[len - 4] == 0xD9 and buf[len - 3] == 0x8A and buf[len - 2] == 0xD9 and buf[len - 1] == 0x86) {
            len -= 4;
        }
    }

    // Remove "ان" suffix (UTF-8: 0xD8 0xA7 0xD9 0x86 = dual nominative)
    if (len > 6) {
        if (buf[len - 4] == 0xD8 and buf[len - 3] == 0xA7 and buf[len - 2] == 0xD9 and buf[len - 1] == 0x86) {
            len -= 4;
        }
    }

    // Remove "ات" suffix (UTF-8: 0xD8 0xA7 0xD8 0xAA = feminine plural)
    if (len > 6) {
        if (buf[len - 4] == 0xD8 and buf[len - 3] == 0xA7 and buf[len - 2] == 0xD8 and buf[len - 1] == 0xAA) {
            len -= 4;
        }
    }

    // Remove "ة" suffix (UTF-8: 0xD8 0xA9 = taa marbuta)
    if (len > 4) {
        if (buf[len - 2] == 0xD8 and buf[len - 1] == 0xA9) {
            len -= 2;
        }
    }

    // Remove "ه" suffix (UTF-8: 0xD9 0x87 = his/its)
    if (len > 4) {
        if (buf[len - 2] == 0xD9 and buf[len - 1] == 0x87) {
            len -= 2;
        }
    }

    // Remove "ي" suffix (UTF-8: 0xD9 0x8A = my)
    if (len > 4) {
        if (buf[len - 2] == 0xD9 and buf[len - 1] == 0x8A) {
            len -= 2;
        }
    }

    // ── Prefix removal ──

    // Remove "ال" prefix (UTF-8: 0xD8 0xA7 0xD9 0x84 = 4 bytes for "ال")
    if (len > 6) {
        if (buf[0] == 0xD8 and buf[1] == 0xA7 and buf[2] == 0xD9 and buf[3] == 0x84) {
            std.mem.copyForwards(u8, buf[0..len - 4], buf[4..len]);
            len -= 4;
        }
    }

    // Remove "و" prefix (UTF-8: 0xD9 0x88 = 2 bytes for "and") — only if word is long enough
    if (len > 4) {
        if (buf[0] == 0xD9 and buf[1] == 0x88) {
            std.mem.copyForwards(u8, buf[0..len - 2], buf[2..len]);
            len -= 2;
        }
    }

    // Remove "ف" prefix (UTF-8: 0xD9 0x81 = 2 bytes for "so/then")
    if (len > 4) {
        if (buf[0] == 0xD9 and buf[1] == 0x81) {
            std.mem.copyForwards(u8, buf[0..len - 2], buf[2..len]);
            len -= 2;
        }
    }

    // Remove "ب" prefix (UTF-8: 0xD8 0xA8 = 2 bytes for "in/by/with")
    if (len > 4) {
        if (buf[0] == 0xD8 and buf[1] == 0xA8) {
            std.mem.copyForwards(u8, buf[0..len - 2], buf[2..len]);
            len -= 2;
        }
    }

    // Remove "ل" prefix (UTF-8: 0xD9 0x84 = 2 bytes for "for/to")
    if (len > 4) {
        if (buf[0] == 0xD9 and buf[1] == 0x84) {
            std.mem.copyForwards(u8, buf[0..len - 2], buf[2..len]);
            len -= 2;
        }
    }

    // Remove "ك" prefix (UTF-8: 0xD9 0x83 = 2 bytes for "like/as")
    if (len > 4) {
        if (buf[0] == 0xD9 and buf[1] == 0x83) {
            std.mem.copyForwards(u8, buf[0..len - 2], buf[2..len]);
            len -= 2;
        }
    }

    return buf[0..len];
}

/// Generate a natural language answer from an axiom and question type.
/// Composes a coherent paragraph using the primary axiom + derivation context.
pub fn generateAnswer(
    axiom_text: []const u8,
    qtype: QuestionType,
    domain_name: []const u8,
    confidence: f32,
    lang: Language,
    derivation_texts: []const []const u8,
    out: []u8,
) usize {
    var pos: usize = 0;
    const translated = translate(axiom_text, lang);

    // Determine the primary axiom (first in path) vs prerequisites.
    const has_prereqs = derivation_texts.len > 1;

    switch (qtype) {
        .what_is, .definition => {
            switch (lang) {
                .english => {
                    if (translated.len > 0) {
                        pos += writeFmt(out[pos..], "In {s}, the key principle is: {s}.", .{ domain_name, translated });
                    } else {
                        pos += writeFmt(out[pos..], "This question relates to {s}, but no specific axiom was found.", .{domain_name});
                    }
                    // Add prerequisite context
                    if (has_prereqs) {
                        pos += writeStr(out[pos..], " This principle is grounded in the fact that ");
                        for (derivation_texts[1..], 0..) |dt, i| {
                            if (i > 0) pos += writeStr(out[pos..], ", and ");
                            const td = translate(dt, lang);
                            pos += writeStr(out[pos..], td);
                        }
                        pos += writeStr(out[pos..], ".");
                    }
                },
                .arabic => {
                    if (translated.len > 0) {
                        pos += writeFmt(out[pos..], "في {s}، المبدأ الأساسي هو: {s}.", .{ domain_name, translated });
                    } else {
                        pos += writeFmt(out[pos..], "هذا السؤال يتعلق بـ {s}، لكن لم يتم العثور على بديهية محددة.", .{domain_name});
                    }
                    if (has_prereqs) {
                        pos += writeStr(out[pos..], " يعتمد هذا المبدأ على أن ");
                        for (derivation_texts[1..], 0..) |dt, i| {
                            if (i > 0) pos += writeStr(out[pos..], "، و");
                            const td = translate(dt, lang);
                            pos += writeStr(out[pos..], td);
                        }
                        pos += writeStr(out[pos..], ".");
                    }
                },
            }
        },
        .why => {
            switch (lang) {
                .english => {
                    if (translated.len > 0) {
                        pos += writeFmt(out[pos..], "This occurs because {s}.", .{translated});
                    } else {
                        pos += writeStr(out[pos..], "The exact cause could not be determined from available principles.");
                    }
                    if (has_prereqs) {
                        pos += writeStr(out[pos..], " The underlying reason is that ");
                        for (derivation_texts[1..], 0..) |dt, i| {
                            if (i > 0) pos += writeStr(out[pos..], ", which in turn means ");
                            const td = translate(dt, lang);
                            pos += writeStr(out[pos..], td);
                        }
                        pos += writeStr(out[pos..], ".");
                    }
                },
                .arabic => {
                    if (translated.len > 0) {
                        pos += writeFmt(out[pos..], "يحدث هذا لأن {s}.", .{translated});
                    } else {
                        pos += writeStr(out[pos..], "لا يمكن تحديد السبب الدقيق من المبادئ المتاحة.");
                    }
                    if (has_prereqs) {
                        pos += writeStr(out[pos..], " والسبب الأساسي هو أن ");
                        for (derivation_texts[1..], 0..) |dt, i| {
                            if (i > 0) pos += writeStr(out[pos..], "، مما يعني بدوره أن ");
                            const td = translate(dt, lang);
                            pos += writeStr(out[pos..], td);
                        }
                        pos += writeStr(out[pos..], ".");
                    }
                },
            }
        },
        .how => {
            switch (lang) {
                .english => {
                    if (translated.len > 0) {
                        pos += writeFmt(out[pos..], "The mechanism works as follows: {s}.", .{translated});
                    } else {
                        pos += writeStr(out[pos..], "The mechanism could not be determined from available principles.");
                    }
                    if (has_prereqs) {
                        pos += writeStr(out[pos..], " This process relies on ");
                        for (derivation_texts[1..], 0..) |dt, i| {
                            if (i > 0) pos += writeStr(out[pos..], " and ");
                            const td = translate(dt, lang);
                            pos += writeStr(out[pos..], td);
                        }
                        pos += writeStr(out[pos..], ".");
                    }
                },
                .arabic => {
                    if (translated.len > 0) {
                        pos += writeFmt(out[pos..], "تعمل الآلية على النحو التالي: {s}.", .{translated});
                    } else {
                        pos += writeStr(out[pos..], "لا يمكن تحديد الآلية من المبادئ المتاحة.");
                    }
                    if (has_prereqs) {
                        pos += writeStr(out[pos..], " تعتمد هذه العملية على ");
                        for (derivation_texts[1..], 0..) |dt, i| {
                            if (i > 0) pos += writeStr(out[pos..], " و");
                            const td = translate(dt, lang);
                            pos += writeStr(out[pos..], td);
                        }
                        pos += writeStr(out[pos..], ".");
                    }
                },
            }
        },
        .explain_more => {
            switch (lang) {
                .english => {
                    if (translated.len > 0) {
                        pos += writeFmt(out[pos..], "To elaborate further: {s}.", .{translated});
                    } else {
                        pos += writeStr(out[pos..], "No additional information is available on this topic.");
                    }
                    if (has_prereqs) {
                        pos += writeStr(out[pos..], " This builds upon: ");
                        for (derivation_texts[1..], 0..) |dt, i| {
                            if (i > 0) pos += writeStr(out[pos..], ", then ");
                            const td = translate(dt, lang);
                            pos += writeStr(out[pos..], td);
                        }
                        pos += writeStr(out[pos..], ".");
                    }
                },
                .arabic => {
                    if (translated.len > 0) {
                        pos += writeFmt(out[pos..], "لتوضيح المزيد: {s}.", .{translated});
                    } else {
                        pos += writeStr(out[pos..], "لا تتوفر معلومات إضافية حول هذا الموضوع.");
                    }
                    if (has_prereqs) {
                        pos += writeStr(out[pos..], " ويعتمد هذا على: ");
                        for (derivation_texts[1..], 0..) |dt, i| {
                            if (i > 0) pos += writeStr(out[pos..], "، ثم ");
                            const td = translate(dt, lang);
                            pos += writeStr(out[pos..], td);
                        }
                        pos += writeStr(out[pos..], ".");
                    }
                },
            }
        },
        .compare => {
            if (translated.len > 0) {
                pos += writeFmt(out[pos..], "{s}.", .{translated});
            }
        },
        .yes_no => {
            switch (lang) {
                .english => {
                    if (translated.len > 0) {
                        pos += writeFmt(out[pos..], "Based on the principle that {s}, the answer is likely yes, though with some uncertainty.", .{translated});
                    } else {
                        pos += writeStr(out[pos..], "Unable to determine a definitive answer from available principles.");
                    }
                },
                .arabic => {
                    if (translated.len > 0) {
                        pos += writeFmt(out[pos..], "بناءً على مبدأ أن {s}، فالإجابة على الأرجح نعم، مع بعض عدم اليقين.", .{translated});
                    } else {
                        pos += writeStr(out[pos..], "لا يمكن تحديد إجابة قاطعة من المبادئ المتاحة.");
                    }
                },
            }
        },
        .example => {
            if (translated.len > 0) {
                pos += writeFmt(out[pos..], "{s}.", .{translated});
            }
        },
        .list => {
            if (translated.len > 0) {
                pos += writeFmt(out[pos..], "{s}.", .{translated});
            }
        },
        .general => {
            if (translated.len > 0) {
                switch (lang) {
                    .english => pos += writeFmt(out[pos..], "Relevant principle: {s}.", .{translated}),
                    .arabic => pos += writeFmt(out[pos..], "المبدأ ذو الصلة: {s}.", .{translated}),
                }
            } else {
                switch (lang) {
                    .english => pos += writeFmt(out[pos..], "This relates to {s}, but no specific axiom matches.", .{domain_name}),
                    .arabic => pos += writeFmt(out[pos..], "هذا يتعلق بـ {s}، لكن لا توجد بديهية مطابقة.", .{domain_name}),
                }
            }
            if (has_prereqs) {
                switch (lang) {
                    .english => {
                        pos += writeStr(out[pos..], " Context: ");
                        for (derivation_texts[1..], 0..) |dt, i| {
                            if (i > 0) pos += writeStr(out[pos..], " → ");
                            const td = translate(dt, lang);
                            pos += writeStr(out[pos..], td);
                        }
                        pos += writeStr(out[pos..], ".");
                    },
                    .arabic => {
                        pos += writeStr(out[pos..], " السياق: ");
                        for (derivation_texts[1..], 0..) |dt, i| {
                            if (i > 0) pos += writeStr(out[pos..], " ← ");
                            const td = translate(dt, lang);
                            pos += writeStr(out[pos..], td);
                        }
                        pos += writeStr(out[pos..], ".");
                    },
                }
            }
        },
    }

    // Add confidence qualifier.
    if (confidence < 0.35) {
        switch (lang) {
            .english => pos += writeStr(out[pos..], " (Note: this answer has significant uncertainty.)"),
            .arabic => pos += writeStr(out[pos..], " (ملاحظة: هذه الإجابة بها قدر كبير من عدم اليقين.)"),
        }
    } else if (confidence > 0.7) {
        switch (lang) {
            .english => pos += writeStr(out[pos..], " (This is a well-established principle.)"),
            .arabic => pos += writeStr(out[pos..], " (هذا مبدأ راسخ ومقرر.)"),
        }
    }

    return pos;
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

test "question type detection" {
    try std.testing.expectEqual(QuestionType.what_is, QuestionType.detect("what is energy?", .english));
    try std.testing.expectEqual(QuestionType.why, QuestionType.detect("why do brakes get hot?", .english));
    try std.testing.expectEqual(QuestionType.how, QuestionType.detect("how does DNA work?", .english));
    try std.testing.expectEqual(QuestionType.explain_more, QuestionType.detect("tell me more about that", .english));
}

test "arabic question type detection" {
    try std.testing.expectEqual(QuestionType.what_is, QuestionType.detect("ما هو الطاقة؟", .arabic));
    try std.testing.expectEqual(QuestionType.why, QuestionType.detect("لماذا تسخن المكابح؟", .arabic));
    try std.testing.expectEqual(QuestionType.how, QuestionType.detect("كيف يعمل الحمض النووي؟", .arabic));
}

test "stemming basic" {
    var buf: [64]u8 = undefined;
    try std.testing.expectEqualStrings("brak", stemEnglish("brakes", &buf));
    try std.testing.expectEqualStrings("brak", stemEnglish("braking", &buf));
}

test "conversation context" {
    var ctx = ConversationContext{};
    ctx.record("what is energy?", 0, 0, 0.5);
    try std.testing.expectEqualStrings("what is energy?", ctx.lastQuery());
    ctx.record("tell me more", 0, 0, 0.5);
    try std.testing.expectEqualStrings("tell me more", ctx.lastQuery());
}
