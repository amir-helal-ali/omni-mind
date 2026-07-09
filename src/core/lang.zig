// src/core/lang.zig — Language detection and bilingual support.
//
// Auto-detects whether a query is Arabic or English based on
// character ranges. All answers are generated in the detected
// language, with the ability to override via explicit flags.

const std = @import("std");

/// Supported languages.
pub const Language = enum(u8) {
    arabic = 0,
    english = 1,

    /// Detect language from text.
    pub fn detect(text: []const u8) Language {
        var arabic_count: usize = 0;
        var latin_count: usize = 0;

        for (text) |b| {
            // Arabic Unicode range: U+0600–U+06FF (UTF-8: 0xD8–0xDB first byte)
            if (b >= 0xD8 and b <= 0xDB) {
                arabic_count += 1;
            }
            // Latin letters (basic ASCII)
            if ((b >= 'a' and b <= 'z') or (b >= 'A' and b <= 'Z')) {
                latin_count += 1;
            }
        }

        if (arabic_count > latin_count) return .arabic;
        return .english;
    }

    /// Get the language name in the language itself.
    pub fn name(self: Language) []const u8 {
        return switch (self) {
            .arabic => "العربية",
            .english => "English",
        };
    }

    /// Get the language code for HTTP headers.
    pub fn code(self: Language) []const u8 {
        return switch (self) {
            .arabic => "ar",
            .english => "en",
        };
    }

    /// Get the text direction (rtl or ltr).
    pub fn direction(self: Language) []const u8 {
        return switch (self) {
            .arabic => "rtl",
            .english => "ltr",
        };
    }
};

/// Bilingual string — holds both Arabic and English versions.
pub const Bilingual = struct {
    ar: []const u8,
    en: []const u8,

    /// Get the string in the requested language.
    pub fn get(self: Bilingual, lang: Language) []const u8 {
        return switch (lang) {
            .arabic => self.ar,
            .english => self.en,
        };
    }
};

/// Tone prefixes in both languages.
pub const TonePrefixes = struct {
    pub fn confident(lang: Language) []const u8 {
        return switch (lang) {
            .arabic => "بثقة عالية: ",
            .english => "With high confidence: ",
        };
    }

    pub fn likely(lang: Language) []const u8 {
        return switch (lang) {
            .arabic => "الأرجح أن: ",
            .english => "Most likely: ",
        };
    }

    pub fn uncertain(lang: Language) []const u8 {
        return switch (lang) {
            .arabic => "هناك شك في أن: ",
            .english => "There is uncertainty: ",
        };
    }

    pub fn low_confidence(lang: Language) []const u8 {
        return switch (lang) {
            .arabic => "لا أعرف بدقة، لكن: ",
            .english => "I don't know precisely, but: ",
        };
    }

    pub fn contradictory(lang: Language) []const u8 {
        return switch (lang) {
            .arabic => "هناك آراء متعارضة. من جهة: ",
            .english => "There are conflicting views. On one hand: ",
        };
    }
};

/// Domain names in both languages.
pub fn domainName(domain: u8, lang: Language) []const u8 {
    return switch (domain) {
        0 => switch (lang) {
            .arabic => "الفيزياء",
            .english => "Physics",
        },
        1 => switch (lang) {
            .arabic => "الكيمياء",
            .english => "Chemistry",
        },
        2 => switch (lang) {
            .arabic => "الأحياء",
            .english => "Biology",
        },
        3 => switch (lang) {
            .arabic => "الرياضيات",
            .english => "Mathematics",
        },
        4 => switch (lang) {
            .arabic => "المنطق",
            .english => "Logic",
        },
        5 => switch (lang) {
            .arabic => "علوم الحاسوب",
            .english => "Computer Science",
        },
        6 => switch (lang) {
            .arabic => "الاقتصاد",
            .english => "Economics",
        },
        7 => switch (lang) {
            .arabic => "علم النفس",
            .english => "Psychology",
        },
        8 => switch (lang) {
            .arabic => "التاريخ",
            .english => "History",
        },
        9 => switch (lang) {
            .arabic => "الفلسفة",
            .english => "Philosophy",
        },
        10 => switch (lang) {
            .arabic => "اللسانيات",
            .english => "Linguistics",
        },
        11 => switch (lang) {
            .arabic => "الفلك",
            .english => "Astronomy",
        },
        12 => switch (lang) {
            .arabic => "الجيولوجيا",
            .english => "Geology",
        },
        13 => switch (lang) {
            .arabic => "الطب",
            .english => "Medicine",
        },
        14 => switch (lang) {
            .arabic => "الهندسة",
            .english => "Engineering",
        },
        15 => switch (lang) {
            .arabic => "العلوم السياسية",
            .english => "Political Science",
        },
        else => switch (lang) {
            .arabic => "غير محدد",
            .english => "Unknown",
        },
    };
}

/// Reasoning dimension names in both languages.
pub fn dimensionName(dim: u8, lang: Language) []const u8 {
    return switch (dim) {
        0 => switch (lang) {
            .arabic => "منطقي",
            .english => "Logical",
        },
        1 => switch (lang) {
            .arabic => "تجريبي",
            .english => "Empirical",
        },
        2 => switch (lang) {
            .arabic => "زمني",
            .english => "Temporal",
        },
        3 => switch (lang) {
            .arabic => "معياري",
            .english => "Normative",
        },
        4 => switch (lang) {
            .arabic => "فوق-معرفي",
            .english => "Meta-Cognitive",
        },
        else => switch (lang) {
            .arabic => "غير معروف",
            .english => "Unknown",
        },
    };
}

/// Subtext hints in both languages.
pub fn subtextHint(hint: u8, lang: Language) []const u8 {
    return switch (hint) {
        0 => switch (lang) {
            .arabic => "نية: توصية قابلة للتنفيذ. ",
            .english => "Intent: actionable recommendation. ",
        },
        1 => switch (lang) {
            .arabic => "نية: تحدٍّ، تقديم أقوى حجة. ",
            .english => "Intent: challenge, presenting strongest argument. ",
        },
        2 => switch (lang) {
            .arabic => "نية: تحقق، الأدلة أولاً. ",
            .english => "Intent: verification, evidence first. ",
        },
        3 => switch (lang) {
            .arabic => "نية: عمق تقني. ",
            .english => "Intent: technical depth. ",
        },
        4 => switch (lang) {
            .arabic => "نية: نظرة عامة متوازنة. ",
            .english => "Intent: balanced overview. ",
        },
        else => switch (lang) {
            .arabic => "",
            .english => "",
        },
    };
}

/// Bilingual labels for answer formatting.
pub const Labels = struct {
    pub fn query_label(lang: Language) []const u8 {
        return switch (lang) {
            .arabic => "سؤال",
            .english => "Question",
        };
    }

    pub fn domain_label(lang: Language) []const u8 {
        return switch (lang) {
            .arabic => "المجال",
            .english => "Domain",
        };
    }

    pub fn axiom_label(lang: Language) []const u8 {
        return switch (lang) {
            .arabic => "البديهية المرجعية",
            .english => "Reference axiom",
        };
    }

    pub fn path_label(lang: Language) []const u8 {
        return switch (lang) {
            .arabic => "مسار الاشتقاق",
            .english => "Derivation path",
        };
    }

    pub fn dimension_label(lang: Language) []const u8 {
        return switch (lang) {
            .arabic => "البُعد الأقوى",
            .english => "Strongest dimension",
        };
    }

    pub fn tunnel_label(lang: Language) []const u8 {
        return switch (lang) {
            .arabic => "تم استخدام التناظر الكمي عبر المجالات",
            .english => "Quantum analogy tunneling used across domains",
        };
    }

    pub fn confidence_label(lang: Language) []const u8 {
        return switch (lang) {
            .arabic => "الثقة",
            .english => "Confidence",
        };
    }

    pub fn latency_label(lang: Language) []const u8 {
        return switch (lang) {
            .arabic => "الزمن",
            .english => "Latency",
        };
    }

    pub fn ms_unit(lang: Language) []const u8 {
        return switch (lang) {
            .arabic => "مللي ثانية",
            .english => "ms",
        };
    }

    pub fn no_axiom(lang: Language) []const u8 {
        return switch (lang) {
            .arabic => "لا توجد بديهية مباشرة",
            .english => "No direct axiom found",
        };
    }

    pub fn derivation_default(lang: Language) []const u8 {
        return switch (lang) {
            .arabic => "اشتقاق من المبادئ الأولى",
            .english => "Derived from first principles",
        };
    }
};

/// Tunnel label (bilingual).
pub fn tunnelLabel(lang: Language) []const u8 {
    return switch (lang) {
        .arabic => "تم استخدام التناظر الكمي عبر المجالات",
        .english => "Quantum analogy tunneling used across domains",
    };
}

test "language detection arabic" {
    try std.testing.expectEqual(Language.arabic, Language.detect("ما هو الطاقة؟"));
}

test "language detection english" {
    try std.testing.expectEqual(Language.english, Language.detect("what is energy?"));
}

test "language detection mixed favors majority" {
    // More Arabic chars than Latin
    try std.testing.expectEqual(Language.arabic, Language.detect("what is الطاقة"));
}

test "language name" {
    try std.testing.expectEqualStrings("العربية", Language.arabic.name());
    try std.testing.expectEqualStrings("English", Language.english.name());
}

test "domain names bilingual" {
    try std.testing.expectEqualStrings("الفيزياء", domainName(0, .arabic));
    try std.testing.expectEqualStrings("Physics", domainName(0, .english));
}
