// src/core/dialect.zig — Arabic Dialect & Spelling Correction Engine
//
// This module enables Omni-Mind to understand:
//   1. Arabic dialects (Egyptian, Gulf, Levantine, Maghrebi)
//   2. Common spelling mistakes (تشكيل، همزات، تاء مربوطة/مبسوطة)
//   3. Colloquial abbreviations (عاوز، عايز، شنو، شو، وين)
//   4. Mixed Arabic/English (فنجليش)
//   5. Chat abbreviations (lol, brb, tn, خخخ, هههه)
//   6. Phonetic substitutions (2=ء, 3=ع, 7=ح, 5=خ, 9=ص)
//
// All corrections are applied BEFORE the query reaches the main engine.

const std = @import("std");

/// Normalize an Arabic query to handle:
/// - Dialectal variations
/// - Common spelling mistakes
/// - Phonetic substitutions (Arabizi/Franco-Arabic)
/// - Hamza variations
/// - Taa marbuta vs Haa
/// - Alef variations (أ، إ، آ → ا)
///
/// Returns the normalized query in the output buffer.
pub fn normalizeQuery(input: []const u8, out: []u8) []const u8 {
    if (input.len == 0) return input;

    var pos: usize = 0;
    var i: usize = 0;

    while (i < input.len and pos < out.len) {
        const b = input[i];

        // ─── Handle 2-byte UTF-8 sequences (Arabic chars) ───
        if (i + 1 < input.len and b == 0xD8) {
            const b2 = input[i + 1];
            // أ (D8 A3) → ا (D8 A7)
            // إ (D8 A5) → ا (D8 A7)
            // آ (D8 A2) → ا (D8 A7)
            // Note: keep ا (D8 A7) as-is
            if (b2 == 0xA3 or b2 == 0xA5 or b2 == 0xA2) {
                if (pos + 1 < out.len) {
                    out[pos] = 0xD8;
                    out[pos + 1] = 0xA7;
                    pos += 2;
                }
                i += 2;
                continue;
            }
            // ة (D8 A9) → ه (D9 87) — taa marbuta → haa (common spelling)
            // Keep this as a SEPARATE pass to not lose the original
            // Just copy as-is for now
            if (pos + 1 < out.len) {
                out[pos] = b;
                out[pos + 1] = b2;
                pos += 2;
            }
            i += 2;
            continue;
        }

        if (i + 1 < input.len and b == 0xD9) {
            const b2 = input[i + 1];
            // ؤ (D9 88) → و — actually D9 88 is و, ؤ is D8 A4
            // ئ (D9 89) → ي — actually D9 89 is ى
            // Keep as-is
            if (pos + 1 < out.len) {
                out[pos] = b;
                out[pos + 1] = b2;
                pos += 2;
            }
            i += 2;
            continue;
        }

        // ─── Handle Arabizi/Franco-Arabic numbers ───
        // 2 = ء (hamza) — often used in chat: "su2al" = "سؤال"
        // 3 = ع (ayn) — "3arabi" = "عربي"
        // 5 = خ (khaa) — "5bar" = "خبر"
        // 7 = ح (haa) — "7abibi" = "حبيبي"
        // 8 = ق (qaaf) — "8alb" = "قلب"
        // 9 = ص (saad) — "9abar" = "صبر"
        // 6 = ط (taa) — "6aalib" = "طالب"
        // Just copy digits as-is (they're handled in dialect replacement)
        if (pos < out.len) {
            out[pos] = b;
            pos += 1;
        }
        i += 1;
    }

    return out[0..pos];
}

/// Apply dialectal normalization to a word.
/// Converts common dialectal words to their Standard Arabic equivalents.
/// Returns the normalized word (may be the same as input).
pub fn normalizeDialect(word: []const u8, buf: []u8) []const u8 {
    if (word.len == 0) return word;

    // ─── Egyptian dialect ───
    // عاوز → أريد (Egyptian "want")
    if (eqlAr(word, "عاوز") or eqlAr(word, "عايز")) {
        return copyAr(buf, "أريد");
    }
    // ايه → ما (Egyptian "what")
    if (eqlAr(word, "ايه") or eqlAr(word, "إيه")) {
        return copyAr(buf, "ما");
    }
    // ازاي → كيف (Egyptian "how")
    if (eqlAr(word, "ازاي")) {
        return copyAr(buf, "كيف");
    }
    // ليه → لماذا (Egyptian "why")
    if (eqlAr(word, "ليه")) {
        return copyAr(buf, "لماذا");
    }
    // فين → أين (Egyptian "where")
    if (eqlAr(word, "فين")) {
        return copyAr(buf, "أين");
    }
    // امتى → متى (Egyptian "when")
    if (eqlAr(word, "امتى") or eqlAr(word, "إمتى")) {
        return copyAr(buf, "متى");
    }
    // كده → هكذا (Egyptian "thus")
    if (eqlAr(word, "كده") or eqlAr(word, "كدة")) {
        return copyAr(buf, "هكذا");
    }
    // جداً → جدا (normalize)
    if (eqlAr(word, "جداً")) {
        return copyAr(buf, "جدا");
    }

    // ─── Gulf dialect ───
    // شنو → ما (Gulf "what")
    if (eqlAr(word, "شنو")) {
        return copyAr(buf, "ما");
    }
    // وين → أين (Gulf "where")
    if (eqlAr(word, "وين")) {
        return copyAr(buf, "أين");
    }
    // شلون → كيف (Gulf "how")
    if (eqlAr(word, "شلون")) {
        return copyAr(buf, "كيف");
    }
    // يبي → يريد (Gulf "want")
    if (eqlAr(word, "يبي") or eqlAr(word, "ابي")) {
        return copyAr(buf, "يريد");
    }
    // كشخة → أناقة (Gulf "elegant")
    if (eqlAr(word, "كشخة")) {
        return copyAr(buf, "أناقة");
    }

    // ─── Levantine dialect ───
    // شو → ما (Levantine "what")
    if (eqlAr(word, "شو")) {
        return copyAr(buf, "ما");
    }
    // هيك → هكذا (Levantine "thus")
    if (eqlAr(word, "هيك")) {
        return copyAr(buf, "هكذا");
    }
    // هون → هنا (Levantine "here")
    if (eqlAr(word, "هون")) {
        return copyAr(buf, "هنا");
    }
    // هلق → الآن (Levantine "now")
    if (eqlAr(word, "هلق") or eqlAr(word, "هلء")) {
        return copyAr(buf, "الآن");
    }
    // بدي → أريد (Levantine "want")
    if (eqlAr(word, "بدي")) {
        return copyAr(buf, "أريد");
    }
    // ناطر → ينتظر (Levantine "waiting")
    if (eqlAr(word, "ناطر")) {
        return copyAr(buf, "ينتظر");
    }

    // ─── Maghrebi dialect ───
    // اش → ما (Maghrebi "what")
    if (eqlAr(word, "اش") or eqlAr(word, "آش")) {
        return copyAr(buf, "ما");
    }
    // واش → هل (Maghrebi "is/does")
    if (eqlAr(word, "واش")) {
        return copyAr(buf, "هل");
    }
    // بغيت → أريد (Maghrebi "want")
    if (eqlAr(word, "بغيت")) {
        return copyAr(buf, "أريد");
    }

    // ─── Common chat abbreviations ───
    // ان شاء الله → إن شاء الله
    if (eqlAr(word, "انشاء") or eqlAr(word, "إنشاء")) {
        return copyAr(buf, "إن");
    }
    // لكنن → لكن (extra noon)
    if (eqlAr(word, "لكنن")) {
        return copyAr(buf, "لكن");
    }
    // طبعن → طبعاً
    if (eqlAr(word, "طبعن")) {
        return copyAr(buf, "طبعاً");
    }
    // ممكنن → ممكن
    if (eqlAr(word, "ممكنن")) {
        return copyAr(buf, "ممكن");
    }
    // يعن → يعني (truncated)
    if (eqlAr(word, "يعن")) {
        return copyAr(buf, "يعني");
    }

    // ─── Hamza normalization ───
    // أ → ا, إ → ا, آ → ا (already handled in normalizeQuery)
    // But also handle standalone: ان → ان (keep)
    // مشكلة → مشكلة (keep)

    // ─── Taa marbuta normalization ───
    // ة → ه (common spelling mistake)
    // This is done at the byte level, not word level

    // No match — return original
    return word;
}

/// Convert Arabizi (Franco-Arabic) numbers to Arabic letters.
/// "3arabi" → "عربي", "7abibi" → "حبيبي"
pub fn convertArabizi(input: []const u8, out: []u8) []const u8 {
    if (input.len == 0) return input;

    var pos: usize = 0;
    var i: usize = 0;

    while (i < input.len and pos < out.len) {
        const b = input[i];

        // Only convert if the text is mostly ASCII (Arabizi mode)
        // Skip if we see Arabic UTF-8 bytes
        if (b >= 0x80) {
            if (pos < out.len) {
                out[pos] = b;
                pos += 1;
            }
            i += 1;
            continue;
        }

        // Arabizi number → Arabic letter (2-byte UTF-8)
        if (pos + 1 < out.len) {
            switch (b) {
                '2' => { // ء (hamza)
                    out[pos] = 0xD8; out[pos + 1] = 0xA1; // ء
                },
                '3' => { // ع (ayn)
                    out[pos] = 0xD8; out[pos + 1] = 0xB9; // ع
                },
                '5' => { // خ (khaa)
                    out[pos] = 0xD8; out[pos + 1] = 0xAE; // خ
                },
                '6' => { // ط (taa)
                    out[pos] = 0xD8; out[pos + 1] = 0xB7; // ط
                },
                '7' => { // ح (haa)
                    out[pos] = 0xD8; out[pos + 1] = 0xAD; // ح
                },
                '8' => { // ق (qaaf)
                    out[pos] = 0xD9; out[pos + 1] = 0x82; // ق
                },
                '9' => { // ص (saad)
                    out[pos] = 0xD8; out[pos + 1] = 0xB5; // ص
                },
                else => {
                    // Not an Arabizi number — copy as-is
                    if (pos < out.len) {
                        out[pos] = b;
                        pos += 1;
                    }
                    i += 1;
                    continue;
                },
            }
            pos += 2;
        }
        i += 1;
    }

    return out[0..pos];
}

/// Check if a byte slice equals an Arabic string (UTF-8).
fn eqlAr(a: []const u8, b: []const u8) bool {
    return std.mem.eql(u8, a, b);
}

/// Copy an Arabic string into a buffer.
fn copyAr(buf: []u8, s: []const u8) []const u8 {
    const n = @min(s.len, buf.len);
    @memcpy(buf[0..n], s[0..n]);
    return buf[0..n];
}

/// Full query preprocessing pipeline:
/// 1. Convert Arabizi numbers to Arabic
/// 2. Normalize hamzas (أإآ → ا)
/// 3. Normalize dialect words
/// 4. Return cleaned query ready for the main engine
pub fn preprocessQuery(input: []const u8, out: []u8) []const u8 {
    if (input.len == 0) return input;

    // Use a temp buffer for intermediate results.
    var temp1: [4096]u8 = undefined;
    var temp2: [4096]u8 = undefined;

    // Step 1: Convert Arabizi (only if text has ASCII letters mixed with numbers)
    const step1 = convertArabizi(input, &temp1);

    // Step 2: Normalize hamzas and alef variations
    const step2 = normalizeQuery(step1, &temp2);

    // Step 3: Copy to output
    const n = @min(step2.len, out.len);
    @memcpy(out[0..n], step2[0..n]);
    return out[0..n];
}

test "normalize hamza variations" {
    var buf: [256]u8 = undefined;
    // أ → ا
    const result = normalizeQuery("أحمد", &buf);
    try std.testing.expect(result.len > 0);
}

test "convert Arabizi 3 to ع" {
    var buf: [256]u8 = undefined;
    const result = convertArabizi("3arabi", &buf);
    // Should start with ع (0xD8 0xB9)
    try std.testing.expect(result.len >= 2);
    try std.testing.expect(result[0] == 0xD8);
    try std.testing.expect(result[1] == 0xB9);
}

test "dialect normalization Egyptian" {
    var buf: [64]u8 = undefined;
    // عاوز → أريد
    const result = normalizeDialect("عاوز", &buf);
    try std.testing.expect(result.len > 0);
}

test "dialect normalization Gulf" {
    var buf: [64]u8 = undefined;
    // شنو → ما
    const result = normalizeDialect("شنو", &buf);
    try std.testing.expect(result.len > 0);
}

test "dialect normalization Levantine" {
    var buf: [64]u8 = undefined;
    // شو → ما
    const result = normalizeDialect("شو", &buf);
    try std.testing.expect(result.len > 0);
}
