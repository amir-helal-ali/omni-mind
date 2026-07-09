// src/core/axiom_translations.zig — Bilingual axiom text translations.
//
// Maps axiom English text to Arabic equivalent. Used when the
// answer language is Arabic — the axiom is displayed in Arabic
// instead of the stored English text.

const std = @import("std");
const Language = @import("lang.zig").Language;

/// Translation entry: English text → Arabic text.
const Translation = struct {
    en: []const u8,
    ar: []const u8,
};

/// All axiom translations. Must match the axioms in seedAxioms().
const TRANSLATIONS = [_]Translation{
    // Physics
    .{ .en = "energy is conserved", .ar = "الطاقة محفوظة" },
    .{ .en = "motion is kinetic energy", .ar = "الحركة طاقة حركية" },
    .{ .en = "friction converts kinetic energy to heat", .ar = "الاحتكاك يحول الطاقة الحركية إلى حرارة" },
    .{ .en = "braking is friction", .ar = "الكبح احتكاك" },
    .{ .en = "quantum superposition allows multiple states", .ar = "التراكب الكمي يسمح بحالات متعددة" },
    .{ .en = "quantum collapse selects one state on measurement", .ar = "الانهيار الكمي يختار حالة واحدة عند القياس" },
    .{ .en = "entanglement links quantum states nonlocally", .ar = "التشابك يربط الحالات الكمية عن بعد" },
    // Computer Science
    .{ .en = "AI processes information", .ar = "الذكاء الاصطناعي يعالج المعلومات" },
    .{ .en = "neural networks are weighted graphs", .ar = "الشبكات العصبية رسوم موزونة" },
    .{ .en = "symbolic AI uses logical axioms", .ar = "الذكاء الاصطناعي الرمزي يستخدم بديهيات منطقية" },
    .{ .en = "quantum inspired algorithms use superposition analogies", .ar = "الخوارزميات المستوحاة من الكم تستخدم تشبيهات التراكب" },
    // Math
    .{ .en = "isomorphism preserves structure", .ar = "التماثل يحافظ على البنية" },
    .{ .en = "diffusion equations describe heat flow", .ar = "معادلات الانتشار تصف تدفق الحرارة" },
    .{ .en = "schrodinger equation is a diffusion-like equation", .ar = "معادلة شرودنغر تشبه معادلة الانتشار" },
    .{ .en = "linear algebra studies vector spaces and transformations", .ar = "الجبر الخطي يدرس الفضاءات المتجهة والتحويلات" },
    // Biology
    .{ .en = "cells are the basic unit of life", .ar = "الخلية هي الوحدة الأساسية للحياة" },
    .{ .en = "DNA stores genetic information", .ar = "الحمض النووي يخزن المعلومات الوراثية" },
    .{ .en = "neurons transmit electrical signals", .ar = "الخلايا العصبية تنقل الإشارات الكهربائية" },
    .{ .en = "natural selection favors adaptive traits", .ar = "الانتخاب الطبيعي يفضل الصفات التكيفية" },
    .{ .en = "evolution causes species to change over generations", .ar = "التطور يسبب تغير الأنواع عبر الأجيال" },
    // Chemistry
    .{ .en = "atoms are the basic unit of matter", .ar = "الذرة هي الوحدة الأساسية للمادة" },
    .{ .en = "molecules are combinations of atoms", .ar = "الجزيئات تراكيب من الذرات" },
    .{ .en = "chemical bonds store potential energy", .ar = "الروابط الكيميائية تخزن الطاقة الكامنة" },
    .{ .en = "catalysts accelerate reactions without being consumed", .ar = "العوامل الحفازة تسرع التفاعلات دون أن تُستهلك" },
    // Economics
    .{ .en = "resources are scarce", .ar = "الموارد نادرة" },
    .{ .en = "supply and demand determine prices", .ar = "العرض والطلب يحددان الأسعار" },
    .{ .en = "inflation reduces purchasing power", .ar = "التضخم يقلل القوة الشرائية" },
    .{ .en = "comparative advantage drives trade", .ar = "الميزة النسبية تدفع التجارة" },
    // Logic
    .{ .en = "modus ponens: if A implies B and A is true, then B is true", .ar = "الاستنتاج المباشر: إذا كان أ يستلزم ب وأ صحيح، فإن ب صحيح" },
    .{ .en = "modus tollens: if A implies B and B is false, then A is false", .ar = "الاستنتاج العكسي: إذا كان أ يستلزم ب وب خاطئ، فإن أ خاطئ" },
    .{ .en = "law of non-contradiction: A and not-A cannot both be true", .ar = "قانون عدم التناقض: أ ولا-أ لا يمكن كلاهما صحيح" },
    .{ .en = "isomorphic structures have identical logical properties", .ar = "البنى المتماثلة لها خصائص منطقية متطابقة" },
    // Physics (new)
    .{ .en = "gravity attracts masses", .ar = "الجاذبية تجذب الكتل" },
    .{ .en = "light travels at constant speed in vacuum", .ar = "الضوء ينتقل بسرعة ثابتة في الفراغ" },
    .{ .en = "thermodynamics governs heat and entropy", .ar = "الديناميكا الحرارية تحكم الحرارة والإنتروبيا" },
    .{ .en = "entropy always increases in closed systems", .ar = "الإنتروبيا تزداد دائماً في الأنظمة المغلقة" },
    .{ .en = "waves carry energy through oscillation", .ar = "الموجات تحمل الطاقة عبر التذبذب" },
    // CS (new)
    .{ .en = "algorithms are step-by-step procedures", .ar = "الخوارزميات إجراءات خطوة بخطوة" },
    .{ .en = "data structures organize information efficiently", .ar = "هياكل البيانات تنظم المعلومات بكفاءة" },
    .{ .en = "information can be measured in bits", .ar = "المعلومات يمكن قياسها بالبتات" },
    .{ .en = "compression reduces redundancy in data", .ar = "الضغط يقلل التكرار في البيانات" },
    // Math (new)
    .{ .en = "calculus studies rates of change and accumulation", .ar = "التفاضل والتكامل يدرس معدلات التغير والتراكم" },
    .{ .en = "probability quantifies uncertainty", .ar = "الاحتمالات تقدر عدم اليقين" },
    .{ .en = "set theory provides foundations of mathematics", .ar = "نظرية المجموعات تؤسس الرياضيات" },
    .{ .en = "graph theory studies networks of nodes and edges", .ar = "نظرية المخططات تدرس شبكات العقد والحواف" },
    // Biology (new)
    .{ .en = "proteins perform cellular functions", .ar = "البروتينات تؤدي الوظائف الخلوية" },
    .{ .en = "enzymes catalyze biochemical reactions", .ar = "الإنزيمات تحفز التفاعلات الكيميائية الحيوية" },
    .{ .en = "photosynthesis converts light to chemical energy", .ar = "التمثيل الضوئي يحول الضوء إلى طاقة كيميائية" },
    .{ .en = "homeostasis maintains internal balance", .ar = "الاتزان الداخلي يحافظ على التوازن" },
    // Chemistry (new)
    .{ .en = "acids donate protons and bases accept them", .ar = "الأحماض تمنح البروتونات والقواعد تستقبلها" },
    .{ .en = "oxidation involves electron loss", .ar = "الأكسدة تنطوي على فقدان الإلكترونات" },
    .{ .en = "periodic table organizes elements by properties", .ar = "الجدول الدوري ينظم العناصر حسب الخصائص" },
    .{ .en = "chemical equilibrium balances forward and reverse reactions", .ar = "التوازن الكيميائي يوازن التفاعلات الأمامية والعكسية" },
    // Economics (new)
    .{ .en = "opportunity cost measures foregone alternatives", .ar = "التكلفة الضيعة تقيس البدائل المتخلى عنها" },
    .{ .en = "economies of scale reduce per-unit cost", .ar = "وفورات الحجم تقلل التكلفة لكل وحدة" },
    .{ .en = "game theory studies strategic decision making", .ar = "نظرية الألعاب تدرس اتخاذ القرارات الاستراتيجية" },
    // Logic (new)
    .{ .en = "inductive reasoning generalizes from specific instances", .ar = "الاستقراء يعمم من الحالات الخاصة" },
    .{ .en = "abductive reasoning finds the best explanation", .ar = "الاستدلال الابداعي يجد أفضل تفسير" },
    .{ .en = "a tautology is always true by definition", .ar = "التحصيل الحاصل صحيح دائماً بالتعريف" },
};

/// Get the translated text for an axiom, in the requested language.
/// Uses the seed_knowledge.zig translations table.
/// If no translation found, returns the original text.
pub fn translate(axiom_text: []const u8, target_lang: Language) []const u8 {
    if (target_lang == .english) return axiom_text;

    // Search the seed knowledge table.
    const seed = @import("seed_knowledge.zig");
    for (seed.SEED_AXIOMS) |sa| {
        if (std.mem.eql(u8, sa.text_en, axiom_text)) {
            return sa.text_ar;
        }
    }

    // Fallback: also check the old static translation table.
    for (TRANSLATIONS) |t| {
        if (std.mem.eql(u8, t.en, axiom_text)) {
            return t.ar;
        }
    }

    // If it's already Arabic, return as-is.
    return axiom_text;
}

test "translate physics axiom to Arabic" {
    const ar = translate("energy is conserved", .arabic);
    try std.testing.expectEqualStrings("الطاقة محفوظة", ar);
}

test "translate keeps English for English" {
    const en = translate("energy is conserved", .english);
    try std.testing.expectEqualStrings("energy is conserved", en);
}

test "translate unknown axiom returns original" {
    const orig = translate("unknown axiom text", .arabic);
    try std.testing.expectEqualStrings("unknown axiom text", orig);
}
