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
    greeting, // "hello", "مرحبا", "مساء الخير"
    social, // "how are you", "كيف حالك", "thank you"
    general, // fallback

    pub fn detect(query: []const u8, lang: Language) QuestionType {
        const has = struct {
            fn check(text: []const u8, needles: []const []const u8) bool {
                for (needles) |n| {
                    if (std.mem.indexOf(u8, text, n) != null) return true;
                }
                return false;
            }
        };

        // ─── Check social/greeting patterns FIRST (both languages) ───
        // Greetings (Arabic + English)
        if (has.check(query, &.{
            "hello", "hi", "hey", "good morning", "good evening", "good afternoon",
            "good night", "greetings", "howdy", "what's up", "whats up",
        })) return .greeting;
        if (has.check(query, &.{
            "مرحبا", "مرحب", "السلام عليكم", "صباح الخير", "مساء الخير",
            "مساء النور", "صباح النور", "اهلا", "أهلا", "اهلين", "هلا",
            "هاي", "هلو",
        })) return .greeting;

        // Social — how are you, thanks, goodbye
        if (has.check(query, &.{
            "how are you", "how r u", "how do you do",
            "thank you", "thanks", "thx", "appreciate",
            "goodbye", "bye", "see you", "cya",
            "nice to meet", "glad to",
        })) return .social;
        if (has.check(query, &.{
            "كيف حالك", "كيفك", "كيف الحال", "شلونك", "عامل ايه",
            "شكرا", "شكراً", "تسلم", "ممنون", "يعطيك العافية",
            "مع السلامة", "الى اللقاء", "إلى اللقاء", "وداعا",
            "تصبح على خير", "نورتي",
        })) return .social;

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
/// Composes a coherent, multi-sentence paragraph that sounds like a
/// knowledgeable human expert — not a database lookup.
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
                        // Opening: acknowledge the question
                        pos += writeFmt(out[pos..], "Great question about {s}. ", .{domain_name});
                        // Core answer
                        pos += writeFmt(out[pos..], "The key principle here is that {s}. ", .{translated});
                        // Elaboration with prerequisites
                        if (has_prereqs) {
                            pos += writeStr(out[pos..], "To understand why this matters, consider that ");
                            for (derivation_texts[1..], 0..) |dt, i| {
                                if (i > 0) pos += writeStr(out[pos..], ", and furthermore ");
                                const td = translate(dt, lang);
                                pos += writeStr(out[pos..], td);
                            }
                            pos += writeStr(out[pos..], ". ");
                        }
                        // Contextual significance
                        pos += writeFmt(out[pos..], "This concept is foundational in {s} and has wide-ranging implications across multiple disciplines.", .{domain_name});
                    } else {
                        pos += writeFmt(out[pos..], "This is an interesting question related to {s}. While I don't have a specific axiom that directly addresses this, the underlying principles of {s} suggest several relevant angles worth exploring.", .{ domain_name, domain_name });
                    }
                },
                .arabic => {
                    if (translated.len > 0) {
                        // افتتاحية: الاعتراف بالسؤال
                        pos += writeFmt(out[pos..], "سؤال ممتاز في مجال {s}. ", .{domain_name});
                        // الإجابة الأساسية
                        pos += writeFmt(out[pos..], "المبدأ الأساسي هنا هو أن {s}. ", .{translated});
                        // التوسع بالمتطلبات الأساسية
                        if (has_prereqs) {
                            pos += writeStr(out[pos..], "لفهم سبب أهمية هذا، يجب أن نأخذ في الاعتبار أن ");
                            for (derivation_texts[1..], 0..) |dt, i| {
                                if (i > 0) pos += writeStr(out[pos..], "، وعلاوة على ذلك ");
                                const td = translate(dt, lang);
                                pos += writeStr(out[pos..], td);
                            }
                            pos += writeStr(out[pos..], ". ");
                        }
                        // الأهمية السياقية
                        pos += writeFmt(out[pos..], "هذا المفهوم أساسي في {s} وله تطبيقات واسعة النطاق عبر تخصصات متعددة.", .{domain_name});
                    } else {
                        pos += writeFmt(out[pos..], "هذا سؤال مثير للاهتمام يتعلق بـ {s}. على الرغم من أنه لا توجد لدي بديهية محددة تعالج هذا مباشرة، إلا أن المبادئ الأساسية لـ {s} تشير إلى عدة جوانب ذات صلة تستحق الاستكشاف.", .{ domain_name, domain_name });
                    }
                },
            }
        },
        .why => {
            switch (lang) {
                .english => {
                    if (translated.len > 0) {
                        pos += writeStr(out[pos..], "This is a thoughtful question that gets to the heart of the matter. ");
                        pos += writeFmt(out[pos..], "The reason this occurs is that {s}. ", .{translated});
                        if (has_prereqs) {
                            pos += writeStr(out[pos..], "Delving deeper, the underlying cause stems from the fact that ");
                            for (derivation_texts[1..], 0..) |dt, i| {
                                if (i > 0) pos += writeStr(out[pos..], ", which in turn implies that ");
                                const td = translate(dt, lang);
                                pos += writeStr(out[pos..], td);
                            }
                            pos += writeStr(out[pos..], ". ");
                        }
                        pos += writeStr(out[pos..], "Understanding this causal chain helps explain not just what happens, but the fundamental mechanisms at play.");
                    } else {
                        pos += writeStr(out[pos..], "This question touches on important causal relationships. While the exact cause isn't captured in my current knowledge base, the patterns suggest several contributing factors worth investigating.");
                    }
                },
                .arabic => {
                    if (translated.len > 0) {
                        pos += writeStr(out[pos..], "هذا سؤال مدروس يصل إلى جوهر الأمر. ");
                        pos += writeFmt(out[pos..], "سبب حدوث هذا هو أن {s}. ", .{translated});
                        if (has_prereqs) {
                            pos += writeStr(out[pos..], "وبالتعمق أكثر، ينبع السبب الأساسي من حقيقة أن ");
                            for (derivation_texts[1..], 0..) |dt, i| {
                                if (i > 0) pos += writeStr(out[pos..], "، مما يعني بدوره أن ");
                                const td = translate(dt, lang);
                                pos += writeStr(out[pos..], td);
                            }
                            pos += writeStr(out[pos..], ". ");
                        }
                        pos += writeStr(out[pos..], "فهم هذه السلسلة السببية يساعد على تفسير ليس فقط ما يحدث، بل الآليات الأساسية العاملة.");
                    } else {
                        pos += writeStr(out[pos..], "هذا السؤال يلامس علاقات سببية مهمة. على الرغم من أن السبب الدقيق غير مدرج في قاعدة معرفتي الحالية، إلا أن الأنماط تشير إلى عدة عوامل مساهمة تستحق التحقيق.");
                    }
                },
            }
        },
        .how => {
            switch (lang) {
                .english => {
                    if (translated.len > 0) {
                        pos += writeStr(out[pos..], "Let me walk you through how this works. ");
                        pos += writeFmt(out[pos..], "The mechanism operates as follows: {s}. ", .{translated});
                        if (has_prereqs) {
                            pos += writeStr(out[pos..], "This process depends on ");
                            for (derivation_texts[1..], 0..) |dt, i| {
                                if (i > 0) pos += writeStr(out[pos..], " working in concert with ");
                                const td = translate(dt, lang);
                                pos += writeStr(out[pos..], td);
                            }
                            pos += writeStr(out[pos..], ". ");
                        }
                        pos += writeStr(out[pos..], "By understanding these interconnected mechanisms, you can appreciate the elegance and precision of how this system functions in practice.");
                    } else {
                        pos += writeStr(out[pos..], "The mechanism behind this is fascinating. While I don't have a specific axiom detailing the exact process, the general principles suggest a multi-step process involving several coordinated components.");
                    }
                },
                .arabic => {
                    if (translated.len > 0) {
                        pos += writeStr(out[pos..], "دعني أشرح لك كيف يعمل هذا. ");
                        pos += writeFmt(out[pos..], "تعمل الآلية على النحو التالي: {s}. ", .{translated});
                        if (has_prereqs) {
                            pos += writeStr(out[pos..], "تعتمد هذه العملية على ");
                            for (derivation_texts[1..], 0..) |dt, i| {
                                if (i > 0) pos += writeStr(out[pos..], " بالتعاون مع ");
                                const td = translate(dt, lang);
                                pos += writeStr(out[pos..], td);
                            }
                            pos += writeStr(out[pos..], ". ");
                        }
                        pos += writeStr(out[pos..], "من خلال فهم هذه الآليات المترابطة، يمكنك تقدير أناقة ودقة كيفية عمل هذا النظام عملياً.");
                    } else {
                        pos += writeStr(out[pos..], "الآلية الكامنة وراء هذا مثيرة للاهتمام. على الرغم من أنه ليس لدي بديهية محددة تفصل العملية الدقيقة، إلا أن المبادئ العامة تشير إلى عملية متعددة الخطوات تتضمن عدة مكونات منسقة.");
                    }
                },
            }
        },
        .explain_more => {
            switch (lang) {
                .english => {
                    if (translated.len > 0) {
                        pos += writeStr(out[pos..], "I'm glad you want to explore this further. ");
                        pos += writeFmt(out[pos..], "Building on what we discussed: {s}. ", .{translated});
                        if (has_prereqs) {
                            pos += writeStr(out[pos..], "This concept builds upon a foundation where ");
                            for (derivation_texts[1..], 0..) |dt, i| {
                                if (i > 0) pos += writeStr(out[pos..], " leads naturally to ");
                                const td = translate(dt, lang);
                                pos += writeStr(out[pos..], td);
                            }
                            pos += writeStr(out[pos..], ". ");
                        }
                        pos += writeStr(out[pos..], "There's always more to discover when you probe beneath the surface of these ideas.");
                    } else {
                        pos += writeStr(out[pos..], "I'd be happy to elaborate further. Unfortunately, my knowledge base doesn't have additional specific details on this exact topic, but the broader context offers several interesting avenues to explore.");
                    }
                },
                .arabic => {
                    if (translated.len > 0) {
                        pos += writeStr(out[pos..], "يسعدني أنك تريد استكشاف هذا بمزيد من التعمق. ");
                        pos += writeFmt(out[pos..], "بناءً على ما ناقشناه: {s}. ", .{translated});
                        if (has_prereqs) {
                            pos += writeStr(out[pos..], "يعتمد هذا المفهوم على أساس حيث ");
                            for (derivation_texts[1..], 0..) |dt, i| {
                                if (i > 0) pos += writeStr(out[pos..], " يؤدي بطبيعة الحال إلى ");
                                const td = translate(dt, lang);
                                pos += writeStr(out[pos..], td);
                            }
                            pos += writeStr(out[pos..], ". ");
                        }
                        pos += writeStr(out[pos..], "هناك دائماً المزيد لاكتشافه عند الاستكشاف تحت سطح هذه الأفكار.");
                    } else {
                        pos += writeStr(out[pos..], "يسعدني التوسع في ذلك. لسوء الحظ، قاعدة معرفتي لا تحتوي على تفاصيل محددة إضافية حول هذا الموضوع بالضبط، لكن السياق الأوسع يقدم عدة مسارات مثيرة للاهتمام للاستكشاف.");
                    }
                },
            }
        },
        .compare => {
            switch (lang) {
                .english => {
                    if (translated.len > 0) {
                        pos += writeStr(out[pos..], "When making this comparison, several key distinctions emerge. ");
                        pos += writeFmt(out[pos..], "{s}. ", .{translated});
                        if (has_prereqs) {
                            pos += writeStr(out[pos..], "The comparison reveals differences in ");
                            for (derivation_texts[1..], 0..) |dt, i| {
                                if (i > 0) pos += writeStr(out[pos..], " and ");
                                const td = translate(dt, lang);
                                pos += writeStr(out[pos..], td);
                            }
                            pos += writeStr(out[pos..], ". ");
                        }
                        pos += writeStr(out[pos..], "These nuances highlight why understanding both similarities and differences is crucial for a complete picture.");
                    }
                },
                .arabic => {
                    if (translated.len > 0) {
                        pos += writeStr(out[pos..], "عند إجراء هذه المقارنة، تظهر عدة اختلافات رئيسية. ");
                        pos += writeFmt(out[pos..], "{s}. ", .{translated});
                        if (has_prereqs) {
                            pos += writeStr(out[pos..], "تكشف المقارنة عن اختلافات في ");
                            for (derivation_texts[1..], 0..) |dt, i| {
                                if (i > 0) pos += writeStr(out[pos..], " و");
                                const td = translate(dt, lang);
                                pos += writeStr(out[pos..], td);
                            }
                            pos += writeStr(out[pos..], ". ");
                        }
                        pos += writeStr(out[pos..], "هذه الفروق الدقيقة تبرز سبب أهمية فهم أوجه التشابه والاختلاف للحصول على صورة كاملة.");
                    }
                },
            }
        },
        .yes_no => {
            switch (lang) {
                .english => {
                    if (translated.len > 0) {
                        pos += writeFmt(out[pos..], "Based on the principle that {s}, the answer is yes. ", .{translated});
                        pos += writeStr(out[pos..], "However, it's worth noting that reality often involves nuances and edge cases that may complicate this straightforward answer. ");
                        if (has_prereqs) {
                            pos += writeStr(out[pos..], "The supporting evidence comes from ");
                            for (derivation_texts[1..], 0..) |dt, i| {
                                if (i > 0) pos += writeStr(out[pos..], " and ");
                                const td = translate(dt, lang);
                                pos += writeStr(out[pos..], td);
                            }
                            pos += writeStr(out[pos..], ". ");
                        }
                    } else {
                        pos += writeStr(out[pos..], "This is a question that requires careful consideration. Based on available principles, a definitive yes or no is difficult, but the evidence leans toward a qualified affirmative.");
                    }
                },
                .arabic => {
                    if (translated.len > 0) {
                        pos += writeFmt(out[pos..], "بناءً على مبدأ أن {s}، الإجابة هي نعم. ", .{translated});
                        pos += writeStr(out[pos..], "ومع ذلك، تجدر الإشارة إلى أن الواقع غالباً ما ينطوي على فروق دقيقة وحالات حدية قد تعقد هذه الإجابة المباشرة. ");
                        if (has_prereqs) {
                            pos += writeStr(out[pos..], "الأدلة الداعمة تأتي من ");
                            for (derivation_texts[1..], 0..) |dt, i| {
                                if (i > 0) pos += writeStr(out[pos..], " و");
                                const td = translate(dt, lang);
                                pos += writeStr(out[pos..], td);
                            }
                            pos += writeStr(out[pos..], ". ");
                        }
                    } else {
                        pos += writeStr(out[pos..], "هذا سؤال يتطلب دراسة متأنية. بناءً على المبادئ المتاحة، تحديد نعم أو لا قاطع أمر صعب، لكن الأدلة تميل إلى إجابة إيجابية مشروطة.");
                    }
                },
            }
        },
        .example => {
            switch (lang) {
                .english => {
                    if (translated.len > 0) {
                        pos += writeStr(out[pos..], "Here's a concrete illustration of this concept: ");
                        pos += writeFmt(out[pos..], "{s}. ", .{translated});
                        if (has_prereqs) {
                            pos += writeStr(out[pos..], "This example demonstrates the interplay between ");
                            for (derivation_texts[1..], 0..) |dt, i| {
                                if (i > 0) pos += writeStr(out[pos..], " and ");
                                const td = translate(dt, lang);
                                pos += writeStr(out[pos..], td);
                            }
                            pos += writeStr(out[pos..], ". ");
                        }
                        pos += writeStr(out[pos..], "Examples like this make abstract principles tangible and easier to grasp.");
                    }
                },
                .arabic => {
                    if (translated.len > 0) {
                        pos += writeStr(out[pos..], "إليك توضيح ملموس لهذا المفهوم: ");
                        pos += writeFmt(out[pos..], "{s}. ", .{translated});
                        if (has_prereqs) {
                            pos += writeStr(out[pos..], "يوضح هذا المثال التفاعل بين ");
                            for (derivation_texts[1..], 0..) |dt, i| {
                                if (i > 0) pos += writeStr(out[pos..], " و");
                                const td = translate(dt, lang);
                                pos += writeStr(out[pos..], td);
                            }
                            pos += writeStr(out[pos..], ". ");
                        }
                        pos += writeStr(out[pos..], "أمثلة مثل هذا تجعل المبادئ المجردة ملموسة وأسهل للفهم.");
                    }
                },
            }
        },
        .list => {
            switch (lang) {
                .english => {
                    if (translated.len > 0) {
                        pos += writeStr(out[pos..], "Here are the key points to consider: ");
                        pos += writeFmt(out[pos..], "{s}. ", .{translated});
                        if (has_prereqs) {
                            pos += writeStr(out[pos..], "Additional relevant factors include ");
                            for (derivation_texts[1..], 0..) |dt, i| {
                                if (i > 0) pos += writeStr(out[pos..], ", ");
                                const td = translate(dt, lang);
                                pos += writeStr(out[pos..], td);
                            }
                            pos += writeStr(out[pos..], ". ");
                        }
                        pos += writeStr(out[pos..], "Each of these elements contributes to a comprehensive understanding of the topic.");
                    }
                },
                .arabic => {
                    if (translated.len > 0) {
                        pos += writeStr(out[pos..], "إليك النقاط الرئيسية التي يجب مراعاتها: ");
                        pos += writeFmt(out[pos..], "{s}. ", .{translated});
                        if (has_prereqs) {
                            pos += writeStr(out[pos..], "تشمل العوامل ذات الصلة الإضافية ");
                            for (derivation_texts[1..], 0..) |dt, i| {
                                if (i > 0) pos += writeStr(out[pos..], "، ");
                                const td = translate(dt, lang);
                                pos += writeStr(out[pos..], td);
                            }
                            pos += writeStr(out[pos..], ". ");
                        }
                        pos += writeStr(out[pos..], "كل من هذه العناصر يساهم في فهم شامل للموضوع.");
                    }
                },
            }
        },
        .greeting => {
            // Warm, natural greetings — NOT knowledge answers
            switch (lang) {
                .english => {
                    pos += writeStr(out[pos..], "Hello! I'm Omni-Mind, your AI knowledge companion. I'm here to help you explore any topic you're curious about. Feel free to ask me about science, history, philosophy, technology, or anything else that interests you. What would you like to discover today?");
                },
                .arabic => {
                    pos += writeStr(out[pos..], "أهلاً وسهلاً بك! أنا Omni-Mind، رفيقك في رحلة المعرفة. أنا هنا لمساعدتك في استكشاف أي موضوع يثير فضولك. اسألني عن العلوم أو التاريخ أو الفلسفة أو التكنولوجيا أو أي شيء آخر يهمك. ماذا تود أن تكتشف اليوم؟");
                },
            }
        },
        .social => {
            // Social responses — how are you, thanks, goodbye
            switch (lang) {
                .english => {
                    if (std.mem.indexOf(u8, axiom_text, "thank") != null or std.mem.indexOf(u8, axiom_text, "Thank") != null) {
                        pos += writeStr(out[pos..], "You're very welcome! I'm always happy to help. Is there anything else you'd like to explore together?");
                    } else if (std.mem.indexOf(u8, axiom_text, "how are you") != null or std.mem.indexOf(u8, axiom_text, "How are") != null) {
                        pos += writeStr(out[pos..], "I'm doing wonderfully, thank you for asking! I'm always learning and growing my knowledge. Every conversation makes me a bit wiser. How about you — what's on your mind today?");
                    } else if (std.mem.indexOf(u8, axiom_text, "bye") != null or std.mem.indexOf(u8, axiom_text, "Bye") != null or std.mem.indexOf(u8, axiom_text, "goodbye") != null) {
                        pos += writeStr(out[pos..], "It was a pleasure talking with you! Feel free to come back anytime you have questions. Until then, keep curious and keep learning!");
                    } else {
                        pos += writeStr(out[pos..], "That's kind of you! I'm here and ready to help with whatever you need. What would you like to talk about?");
                    }
                },
                .arabic => {
                    if (std.mem.indexOf(u8, axiom_text, "شكر") != null or std.mem.indexOf(u8, axiom_text, "تسلم") != null or std.mem.indexOf(u8, axiom_text, "ممنون") != null) {
                        pos += writeStr(out[pos..], "العفو! سعيد جداً بمساعدتك. هل هناك شيء آخر تود أن نستكشفه معاً؟");
                    } else if (std.mem.indexOf(u8, axiom_text, "كيف حالك") != null or std.mem.indexOf(u8, axiom_text, "كيفك") != null or std.mem.indexOf(u8, axiom_text, "شلونك") != null) {
                        pos += writeStr(out[pos..], "أنا بخير والحمد لله، شكراً لسؤالك اللطيف! أنا دائماً في حالة تعلم ونمو. كل محادثة تجعلني أكثر حكمة. وأنت، ما الذي يشغل تفكيرك اليوم؟");
                    } else if (std.mem.indexOf(u8, axiom_text, "سلامة") != null or std.mem.indexOf(u8, axiom_text, "وداع") != null or std.mem.indexOf(u8, axiom_text, "لقاء") != null) {
                        pos += writeStr(out[pos..], "كان من دواعي سروري الحديث معك! لا تتردد في العودة متى شئت. حتى ذلك الحين، ابقَ فضولياً وواصل التعلم!");
                    } else {
                        pos += writeStr(out[pos..], "لطف منك! أنا هنا وجاهز لمساعدتك في أي شيء تحتاجه. عن ماذا تود أن نتحدث؟");
                    }
                },
            }
        },
        .general => {
            switch (lang) {
                .english => {
                    if (translated.len > 0) {
                        pos += writeFmt(out[pos..], "This is a fascinating topic within {s}. ", .{domain_name});
                        pos += writeFmt(out[pos..], "The core insight is that {s}. ", .{translated});
                        if (has_prereqs) {
                            pos += writeStr(out[pos..], "To provide context, this connects to ");
                            for (derivation_texts[1..], 0..) |dt, i| {
                                if (i > 0) pos += writeStr(out[pos..], " → ");
                                const td = translate(dt, lang);
                                pos += writeStr(out[pos..], td);
                            }
                            pos += writeStr(out[pos..], ". ");
                        }
                        pos += writeStr(out[pos..], "I find this area particularly interesting because it reveals deep connections between seemingly disparate ideas.");
                    } else {
                        pos += writeFmt(out[pos..], "This is an intriguing question that falls within {s}. ", .{domain_name});
                        pos += writeStr(out[pos..], "While my current knowledge base doesn't have a specific axiom addressing this directly, the broader framework of ");
                        pos += writeFmt(out[pos..], "{s} provides useful context for thinking about this question.", .{domain_name});
                    }
                },
                .arabic => {
                    if (translated.len > 0) {
                        pos += writeFmt(out[pos..], "هذا موضوع رائع ضمن {s}. ", .{domain_name});
                        pos += writeFmt(out[pos..], "الفكرة الأساسية هي أن {s}. ", .{translated});
                        if (has_prereqs) {
                            pos += writeStr(out[pos..], "لتقديم السياق، يرتبط هذا بـ ");
                            for (derivation_texts[1..], 0..) |dt, i| {
                                if (i > 0) pos += writeStr(out[pos..], " ← ");
                                const td = translate(dt, lang);
                                pos += writeStr(out[pos..], td);
                            }
                            pos += writeStr(out[pos..], ". ");
                        }
                        pos += writeStr(out[pos..], "أجد هذا المجال مثيراً للاهتمام بشكل خاص لأنه يكشف عن روابط عميقة بين أفكار تبدو متباينة.");
                    } else {
                        pos += writeFmt(out[pos..], "هذا سؤال مثير للاهتمام يقع ضمن {s}. ", .{domain_name});
                        pos += writeStr(out[pos..], "على الرغم من أن قاعدة معرفتي الحالية لا تحتوي على بديهية محددة تعالج هذا مباشرة، إلا أن الإطار الأوسع لـ ");
                        pos += writeFmt(out[pos..], "{s} يوفر سياقاً مفيداً للتفكير في هذا السؤال.", .{domain_name});
                    }
                },
            }
        },
    }

    // Add a thoughtful closing based on confidence — but make it conversational, not clinical.
    if (confidence < 0.35) {
        switch (lang) {
            .english => pos += writeStr(out[pos..], " I should mention that my confidence in this answer is moderate — there may be additional nuances worth exploring."),
            .arabic => pos += writeStr(out[pos..], " يجب أن أذكر أن ثقتي في هذه الإجابة متوسطة — قد تكون هناك فروق دقيقة إضافية تستحق الاستكشاف."),
        }
    } else if (confidence > 0.7) {
        switch (lang) {
            .english => pos += writeStr(out[pos..], " This is a well-established principle that I'm quite confident about."),
            .arabic => pos += writeStr(out[pos..], " هذا مبدأ راسخ ومقرر، وأنا واثق منه بشكل كبير."),
        }
    } else {
        switch (lang) {
            .english => pos += writeStr(out[pos..], " I hope this gives you a solid foundation — feel free to ask follow-up questions if you'd like to dive deeper."),
            .arabic => pos += writeStr(out[pos..], " آمل أن يمنحك هذا أساساً متيناً — لا تتردد في طرح أسئلة متابعة إذا أردت التعمق أكثر."),
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
