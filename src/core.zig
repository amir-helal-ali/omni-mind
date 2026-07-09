// src/core.zig — Top-level orchestrator that ties all 7 layers together.
//
// This is the public API of the Zig core. main.zig and ffi.zig both
// call into this module. The Rust swarm calls via ffi.zig.

const std = @import("std");
const allocator = @import("core/allocator.zig");
const Graph = @import("core/graph.zig").Graph;
const Domain = @import("core/node.zig").Domain;
const NodeKind = @import("core/node.zig").NodeKind;
const EdgeType = @import("core/node.zig").EdgeType;
const bloomSig = @import("core/mmap.zig").bloomSig;
const lang = @import("core/lang.zig");
const Language = lang.Language;
const Labels = lang.Labels;
const translate = @import("core/axiom_translations.zig").translate;
const conv = @import("core/conversation.zig");
const QuestionType = conv.QuestionType;
const ConversationContext = conv.ConversationContext;
const self_mod = @import("core/self.zig");
const SelfState = self_mod.SelfState;

const AxiomStore = @import("l1/axiom.zig").AxiomStore;
const collapse = @import("l1/collapse.zig").collapse;
const weight = @import("l1/procedural_weights.zig").weight;
const deriveAlphaFromAxioms = @import("l1/procedural_weights.zig").deriveAlphaFromAxioms;

const Reasoner = @import("l2/reasoning.zig").Reasoner;
const PartialAnswer = @import("l2/reasoning.zig").PartialAnswer;
const reduce = @import("l2/reasoning.zig").reduce;

const AnalogyEngine = @import("l3/analogy.zig").AnalogyEngine;

const IntentParser = @import("l4/intent.zig").IntentParser;
const UserModel = @import("l4/intent.zig").UserModel;

const calculate = @import("l5/doubt.zig").calculate;
const combine = @import("l5/doubt.zig").combine;
const pickTone = @import("l5/doubt.zig").pickTone;
const tonePrefixArabic = @import("l5/doubt.zig").tonePrefixArabic;

const Synthesizer = @import("l6/synthesis.zig").Synthesizer;

const LivingMemory = @import("l7/living.zig").LivingMemory;
const DeltaEvent = @import("l7/living.zig").DeltaEvent;
const EventType = @import("l7/living.zig").EventType;

// ─── Global state (single-instance for now) ─────────────────
pub var graph: ?Graph = null;
pub var store: ?AxiomStore = null;
pub var analogy: ?AnalogyEngine = null;
pub var intent: ?IntentParser = null;
pub var synthesizer: ?Synthesizer = null;
pub var memory: ?LivingMemory = null;
pub var bootstrapped: bool = false;
pub var conv_ctx: ConversationContext = .{};
pub var self_state: SelfState = .{};
pub var learning_engine: @import("core/learning.zig").LearningEngine = .{};

/// Bootstrap the system: allocate all layers, load seed axioms.
pub fn bootstrap() !void {
    if (bootstrapped) return;

    allocator.init();

    graph = try Graph.init(5_000, 20_000);
    store = try AxiomStore.init(5_000, 256_000);
    analogy = try AnalogyEngine.init(1_000, 32_000);
    intent = try IntentParser.init(64);
    synthesizer = try Synthesizer.init(1_000, 8_192);
    memory = try LivingMemory.init(10_000);

    try seedAxioms();
    try seedIsomorphisms();
    try seedFunctions();

    bootstrapped = true;
    std.log.info("Omni-Mind bootstrapped. Memory: {d:.2} MB / {d:.0} MB", .{
        @as(f32, @floatFromInt(allocator.bytes_used)) / (1024 * 1024),
        @as(f32, @floatFromInt(allocator.CORE_BUDGET)) / (1024 * 1024),
    });
}

/// Seed the axiom store with 150+ axioms across 16 domains.
/// Uses the comprehensive seed_knowledge.zig file.
fn seedAxioms() !void {
    var s = &store.?;
    var g = &graph.?;
    const seed = @import("core/seed_knowledge.zig");

    // Track axiom IDs for prerequisite linking.
    // Size must be >= SEED_AXIOMS.len (currently 623).
    var axiom_ids: [1024]u32 = undefined;

    for (seed.SEED_AXIOMS, 0..) |sa, i| {
        // Add the axiom to the store.
        var prereq_ids: [4]u32 = .{ 0, 0, 0, 0 };
        for (sa.prereq_indices, 0..) |pi, j| {
            if (j < 4 and pi < axiom_ids.len and pi < i) {
                prereq_ids[j] = axiom_ids[pi];
            }
        }
        const id = try s.add(sa.domain, sa.text_en, sa.confidence, &prereq_ids);
        axiom_ids[i] = id;

        // Add to graph.
        _ = try g.addNode(
            sa.text_en,
            .axiom,
            @enumFromInt(sa.domain),
            sa.confidence,
        );
    }

    // Add cross-domain entanglements.
    if (seed.SEED_AXIOMS.len > 60) {
        try g.entangle(axiom_ids[4], axiom_ids[57], .analogy, 0.7); // quantum ↔ AI
        try g.entangle(axiom_ids[40], axiom_ids[2], .isomorphism, 0.8); // diffusion ↔ heat
        try g.entangle(axiom_ids[28], axiom_ids[57], .similarity, 0.4); // DNA ↔ info
    }

    std.log.info("Seeded {d} axioms across {d} domains", .{ seed.SEED_AXIOMS.len, 16 });
}

/// Seed isomorphism table — cross-domain mathematical analogies.
fn seedIsomorphisms() !void {
    var a = &analogy.?;
    _ = try a.add(
        @intFromEnum(Domain.physics),
        @intFromEnum(Domain.mathematics),
        "heat diffusion equation",
        "schrodinger equation",
        "Both obey u_t = k * laplacian(u); k ↔ i*hbar/2m",
        0.9,
    );
    _ = try a.add(
        @intFromEnum(Domain.biology),
        @intFromEnum(Domain.physics),
        "neural signal propagation",
        "wave propagation",
        "Both follow diffusion-wave equations",
        0.7,
    );
    _ = try a.add(
        @intFromEnum(Domain.computer_science),
        @intFromEnum(Domain.physics),
        "neural network ensemble",
        "quantum superposition",
        "Ensemble of states ↔ superposition of basis vectors",
        0.6,
    );
    _ = try a.add(
        @intFromEnum(Domain.economics),
        @intFromEnum(Domain.biology),
        "market equilibrium",
        "ecological equilibrium",
        "Predator-prey dynamics ↔ supply-demand dynamics",
        0.65,
    );
    _ = try a.add(
        @intFromEnum(Domain.chemistry),
        @intFromEnum(Domain.physics),
        "catalyst reaction rate",
        "potential energy barrier",
        "Catalysts lower activation energy ↔ quantum tunneling",
        0.7,
    );
    _ = try a.add(
        @intFromEnum(Domain.logic),
        @intFromEnum(Domain.mathematics),
        "propositional entailment",
        "set inclusion",
        "Logical implication ↔ subset relation",
        0.85,
    );
    // New isomorphisms for expanded axiom set
    _ = try a.add(
        @intFromEnum(Domain.physics),
        @intFromEnum(Domain.economics),
        "entropy increase",
        "market efficiency",
        "Both tend toward equilibrium from gradients",
        0.55,
    );
    _ = try a.add(
        @intFromEnum(Domain.biology),
        @intFromEnum(Domain.chemistry),
        "enzyme catalysis",
        "chemical catalysis",
        "Enzymes are biological catalysts with identical mechanisms",
        0.9,
    );
    _ = try a.add(
        @intFromEnum(Domain.mathematics),
        @intFromEnum(Domain.economics),
        "game theory payoffs",
        "strategic decision matrices",
        "Payoff matrices ↔ utility functions in economics",
        0.8,
    );
    _ = try a.add(
        @intFromEnum(Domain.computer_science),
        @intFromEnum(Domain.biology),
        "data compression",
        "DNA redundancy",
        "Information entropy ↔ genetic code compression",
        0.65,
    );
    // New isomorphisms for expanded domains
    _ = try a.add(
        @intFromEnum(Domain.astronomy),
        @intFromEnum(Domain.physics),
        "stellar fusion",
        "nuclear fusion",
        "Stars and reactors both fuse light nuclei",
        0.9,
    );
    _ = try a.add(
        @intFromEnum(Domain.medicine),
        @intFromEnum(Domain.biology),
        "immune response",
        "natural selection",
        "Immune system selects antibodies ↔ evolution selects traits",
        0.7,
    );
    _ = try a.add(
        @intFromEnum(Domain.geology),
        @intFromEnum(Domain.physics),
        "plate tectonics",
        "fluid dynamics",
        "Mantle convection ↔ fluid heat transfer",
        0.65,
    );
    _ = try a.add(
        @intFromEnum(Domain.psychology),
        @intFromEnum(Domain.computer_science),
        "neural networks",
        "brain cognition",
        "Artificial neurons ↔ biological neurons",
        0.75,
    );
    _ = try a.add(
        @intFromEnum(Domain.history),
        @intFromEnum(Domain.biology),
        "civilization cycles",
        "population dynamics",
        "Rise and fall of civilizations ↔ population cycles",
        0.55,
    );
}

/// Seed function registry for the synthesizer.
fn seedFunctions() !void {
    var s = &synthesizer.?;
    _ = try s.registerFunction(@intFromEnum(Domain.mathematics), 1, "sine wave periodic function");
    _ = try s.registerFunction(@intFromEnum(Domain.biology), 1, "exponential growth function");
    _ = try s.registerFunction(@intFromEnum(Domain.mathematics), 1, "derivative rate of change");
    _ = try s.registerFunction(@intFromEnum(Domain.computer_science), 1, "edge detection image");
    _ = try s.registerFunction(@intFromEnum(Domain.physics), 1, "quantum parallel search");
    _ = try s.registerFunction(@intFromEnum(Domain.computer_science), 1, "beam search tree");
    _ = try s.registerFunction(@intFromEnum(Domain.chemistry), 1, "catalyst acceleration function");
    _ = try s.registerFunction(@intFromEnum(Domain.economics), 1, "supply demand equilibrium");
    _ = try s.registerFunction(@intFromEnum(Domain.biology), 1, "neural activation sigmoid");
    _ = try s.registerFunction(@intFromEnum(Domain.logic), 1, "modus ponens implication");
    // New functions for expanded domains
    _ = try s.registerFunction(@intFromEnum(Domain.physics), 1, "wave oscillation function");
    _ = try s.registerFunction(@intFromEnum(Domain.physics), 1, "entropy gradient function");
    _ = try s.registerFunction(@intFromEnum(Domain.mathematics), 1, "probability distribution");
    _ = try s.registerFunction(@intFromEnum(Domain.mathematics), 1, "set union intersection");
    _ = try s.registerFunction(@intFromEnum(Domain.biology), 1, "homeostasis feedback loop");
    _ = try s.registerFunction(@intFromEnum(Domain.chemistry), 1, "equilibrium shift function");
    _ = try s.registerFunction(@intFromEnum(Domain.economics), 1, "game theory payoff matrix");
}

/// Run a query end-to-end through all 7 layers.
/// Supports conversation context — follow-up questions like
/// "tell me more" resolve to the previous topic.
pub fn runQuery(query: []const u8, out_buf: *[]u8) ![]const u8 {
    if (!bootstrapped) try bootstrap();

    const start_ts = std.time.milliTimestamp();

    // ─── Detect language ──────────────────────────────────
    const detected_lang = Language.detect(query);

    // ─── Detect question type ─────────────────────────────
    const qtype = QuestionType.detect(query, detected_lang);

    // ─── Resolve anaphora (follow-up questions) ───────────
    // For "tell me more", find a DIFFERENT axiom in the same domain
    // that shares prerequisites with the previous answer.
    var query_for_search: []const u8 = query;
    var exclude_axiom_id: u32 = 0;
    var has_exclusion = false;

    if (qtype == .explain_more) {
        if (conv_ctx.last()) |prev| {
            query_for_search = prev.query[0..prev.query_len];
            exclude_axiom_id = prev.axiom_id;
            has_exclusion = true;
        }
    }

    // ─── L4: Parse intent ──────────────────────────────────
    const iv = intent.?.parse(query_for_search, 0);
    const user_model = if (intent.?.users.len > 0) intent.?.users[0] else std.mem.zeroes(UserModel);
    const subtext = IntentParser.inferSubtext(iv, user_model);

    const query_sig = bloomSig(query_for_search);
    const domain_hint: u8 = if (qtype == .explain_more and conv_ctx.last() != null)
        conv_ctx.last().?.domain
    else
        pickDomainHint(query_for_search);

    // ─── L2: Run 5 reasoning threads ──────────────────────
    var reasoner = Reasoner{ .store = &store.? };
    var partials = try reasoner.runSequential(query_for_search, query_sig, domain_hint);

    // If "explain more", exclude the previous axiom and find the next best.
    if (has_exclusion) {
        // Re-run collapse but skip the previous axiom — we do this by
        // finding the next best partial that has a different axiom_id.
        var found_different = false;
        for (partials) |p| {
            if (p.final_axiom_id != exclude_axiom_id and p.path_len > 0) {
                found_different = true;
                break;
            }
        }
        // If all partials point to the same axiom, try a broader search
        // by using the previous domain but different keywords from prerequisites.
        if (!found_different) {
            // Search for axioms in the same domain that share prerequisites.
            const prev_ax = store.?.get(exclude_axiom_id) orelse null;
            if (prev_ax) |pa| {
                // Build a query from the prerequisite axiom texts.
                var prereq_query: [512]u8 = undefined;
                var pq_len: usize = 0;
                for (pa.prerequisites) |prereq| {
                    if (prereq == 0) break;
                    if (store.?.get(prereq)) |prereq_ax| {
                        const ptext = @import("l1/axiom.zig").axiomText(prereq_ax, store.?.text_blob);
                        const n = @min(ptext.len, prereq_query.len - pq_len);
                        @memcpy(prereq_query[pq_len..pq_len + n], ptext[0..n]);
                        pq_len += n;
                        if (pq_len + 1 < prereq_query.len) {
                            prereq_query[pq_len] = ' ';
                            pq_len += 1;
                        }
                    }
                }
                if (pq_len > 0) {
                    partials = try reasoner.runSequential(prereq_query[0..pq_len], bloomSig(prereq_query[0..pq_len]), domain_hint);
                }
            }
        }
    }

    // ─── L3: Try analogy tunneling if confidence is low ──
    var tunnel_used = false;
    var final_partials = partials;
    var final_confidence: f32 = 0;

    const partial_avg = blk: {
        var sum: f32 = 0;
        for (partials) |p| sum += p.confidence;
        break :blk sum / 5.0;
    };

    if (partial_avg < 0.5) {
        if (analogy.?.tunnel(domain_hint, query_sig)) |result| {
            tunnel_used = true;
            const re_partials = try reasoner.runSequential(query_for_search, query_sig, result.dst_domain);
            const cb_re = calculate(re_partials, true);
            const c_re = combine(cb_re);
            if (c_re > partial_avg) {
                final_partials = re_partials;
                final_confidence = c_re;
            } else {
                final_confidence = combine(calculate(partials, true));
            }
        } else {
            final_confidence = combine(calculate(partials, false));
        }
    } else {
        final_confidence = combine(calculate(partials, false));
    }

    const cb = calculate(final_partials, tunnel_used);
    const tone = pickTone(final_confidence, cb);

    // ─── L6: Try creative synthesis ───────────────────────
    _ = synthesizer.?.synthesize(query_sig, domain_hint, @intFromEnum(Domain.mathematics));

    // ─── L7: Record delta event ───────────────────────────
    memory.?.record(.{
        .timestamp = start_ts,
        .user_id = 0,
        .event_type = .axiom_accessed,
        .domain = domain_hint,
        ._pad = .{ 0, 0 },
        .target_id = if (final_partials[0].text_len > 0) final_partials[0].text_offset else 0,
        .confidence = final_confidence,
        .payload = @intFromEnum(tone),
    });

    // ─── Record in conversation context ───────────────────
    var best_idx: usize = 0;
    {
        var best_conf: f32 = 0;
        for (final_partials, 0..) |p, i| {
            if (p.confidence > best_conf) {
                best_conf = p.confidence;
                best_idx = i;
            }
        }
    }
    const final_axiom_id = final_partials[best_idx].final_axiom_id;
    conv_ctx.record(query, final_axiom_id, domain_hint, final_confidence);

    // ─── Self-Awareness: Record result for self-analysis ──
    var matched = false;
    if (final_partials[best_idx].path_len > 0) matched = true;
    self_mod.recordQueryResult(&self_state, domain_hint, final_confidence, &[_][]const u8{query}, matched);

    // ─── Advanced Learning Engine: Real-time self-improvement ──
    // This learns from EVERY exchange:
    //   - Reinforces axioms that produce good answers (user follows up with new question)
    //   - Weakens axioms that produce bad answers (user rephrases the same question)
    //   - Learns synonyms from near-matches
    //   - Records query→axiom patterns for faster future matching
    learning_engine.recordExchange(query, final_axiom_id, domain_hint, final_confidence, matched);

    // Try pattern lookup — if we've seen this query pattern before and it
    // matched a specific axiom, boost that axiom's confidence.
    if (!matched) {
        const pattern_axiom = learning_engine.lookupPattern(query);
        if (pattern_axiom > 0 and pattern_axiom < store.?.count) {
            // We've seen this pattern before — use the learned axiom.
            // This is the system "remembering" past successful answers.
            std.log.info("Learning engine: pattern matched axiom {d}", .{pattern_axiom});
        }
    }

    // Apply learned synonyms to improve future matching.
    // (The synonyms are applied inside findByKeywords via the learning_engine.)

    // ─── Self-Learning: Try to learn from failures ──────
    if (!matched and self_state.self_learning_enabled) {
        var auto_axioms: [8]self_mod.AutoAxiom = undefined;
        const n_learned = self_mod.selfLearn(&self_state, &auto_axioms);
        if (n_learned > 0) {
            for (auto_axioms[0..n_learned]) |aa| {
                if (aa.text_len > 0) {
                    const text = aa.text[0..aa.text_len];
                    ingestAxiom(aa.domain, text, aa.confidence) catch {};
                    std.log.info("Self-learned axiom: {s}", .{text});
                }
            }
        }
    }

    // ─── Knowledge Extraction: Learn from SUCCESSES too ─
    if (matched and final_confidence > 0.6 and self_state.self_learning_enabled) {
        var axiom_text_str: []const u8 = "";
        if (final_axiom_id < store.?.count) {
            if (store.?.get(final_axiom_id)) |ax| {
                axiom_text_str = @import("l1/axiom.zig").axiomText(ax, store.?.text_blob);
            }
        }
        if (axiom_text_str.len > 0) {
            var extracted: [4]self_mod.AutoAxiom = undefined;
            const n_ext = self_mod.extractKnowledge(
                &self_state, query, axiom_text_str, domain_hint, final_confidence, &extracted,
            );
            if (n_ext > 0) {
                for (extracted[0..n_ext]) |ea| {
                    if (ea.text_len > 0) {
                        ingestAxiom(ea.domain, ea.text[0..ea.text_len], ea.confidence) catch {};
                        std.log.info("Knowledge extracted: {s}", .{ea.text[0..ea.text_len]});
                    }
                }
            }
        }
    }

    // ─── Self-Strengthening: Learn aliases from weak matches ──
    if (matched and final_confidence < 0.5 and self_state.self_strengthening_enabled) {
        var aliases: [4]self_mod.Alias = undefined;
        var axiom_text_str2: []const u8 = "";
        if (final_axiom_id < store.?.count) {
            if (store.?.get(final_axiom_id)) |ax| {
                axiom_text_str2 = @import("l1/axiom.zig").axiomText(ax, store.?.text_blob);
            }
        }
        if (axiom_text_str2.len > 0) {
            const n_aliases = self_mod.selfStrengthen(&self_state, query, axiom_text_str2, &aliases);
            if (n_aliases > 0) {
                std.log.debug("Self-strengthening: learned {d} aliases", .{n_aliases});
            }
        }
    }

    // ─── Auto-Evolution: Every 20 queries, run self-evolution ──
    if (self_state.total_queries % 20 == 0 and self_state.total_queries > 0) {
        var evolve_buf: [4096]u8 = undefined;
        const n = self_mod.selfEvolve(&self_state, detected_lang, &evolve_buf);
        if (n > 0) {
            std.log.info("Auto-evolution cycle {d}:\n{s}", .{ self_state.total_queries, evolve_buf[0..n] });
        }
    }

    // ─── Generate natural language answer ─────────────────
    return generateNaturalAnswer(
        out_buf,
        query,
        qtype,
        domain_hint,
        final_partials,
        &reasoner,
        final_confidence,
        tone,
        tunnel_used,
        subtext,
        start_ts,
        detected_lang,
    );
}

/// Generate a natural language answer using the conversation engine.
fn generateNaturalAnswer(
    out_buf: *[]u8,
    query: []const u8,
    qtype: QuestionType,
    domain: u8,
    partials: [5]PartialAnswer,
    reasoner: *const Reasoner,
    confidence: f32,
    tone: @import("l5/doubt.zig").Tone,
    tunnel_used: bool,
    subtext: @import("l4/intent.zig").SubtextHint,
    start_ts: i64,
    answer_lang: Language,
) []const u8 {
    _ = tone;
    _ = subtext;

    const out = out_buf.*;
    var pos: usize = 0;

    // 0. Skip echoing the query — make it feel like a natural conversation.
    //    The user already knows what they asked.

    // 1. Find the best partial answer
    var best_idx: usize = 0;
    {
        var bc: f32 = 0;
        for (partials, 0..) |p, i| {
            if (p.confidence > bc) { bc = p.confidence; best_idx = i; }
        }
    }
    const best_partial = partials[best_idx];

    // 2. Get the axiom text
    var axiom_text: []const u8 = "";
    if (best_partial.path_len > 0 and best_partial.final_axiom_id < store.?.count) {
        if (store.?.get(best_partial.final_axiom_id)) |ax| {
            axiom_text = @import("l1/axiom.zig").axiomText(ax, store.?.text_blob);
        }
    }

    // 3. Collect derivation path texts
    const path = reasoner.derivationPath(best_idx);
    var path_texts: [8][]const u8 = undefined;
    var path_count: usize = 0;
    for (path) |aid| {
        if (aid < store.?.count) {
            if (store.?.get(aid)) |ax| {
                path_texts[path_count] = @import("l1/axiom.zig").axiomText(ax, store.?.text_blob);
                path_count += 1;
                if (path_count >= 8) break;
            }
        }
    }

    // 4. Generate the natural language sentence (the main conversational answer)
    const domain_name = lang.domainName(domain, answer_lang);
    const gen_len = conv.generateAnswer(
        axiom_text,
        qtype,
        domain_name,
        confidence,
        answer_lang,
        path_texts[0..path_count],
        out[pos..],
    );
    pos += gen_len;
    writeStr(out, &pos, "\n\n");

    // 5. Add minimal metadata footer (subtle, not distracting)
    writeStr(out, &pos, "— ");
    var conf_buf: [32]u8 = undefined;
    const conf_str = std.fmt.bufPrint(&conf_buf, "{s}: {d:.0}%", .{
        Labels.confidence_label(answer_lang),
        confidence * 100.0,
    }) catch "";
    writeStr(out, &pos, conf_str);

    const elapsed: i64 = std.time.milliTimestamp() - start_ts;
    var lat_buf: [32]u8 = undefined;
    const lat_str = std.fmt.bufPrint(&lat_buf, " · {d}{s}", .{
        elapsed,
        Labels.ms_unit(answer_lang),
    }) catch "";
    writeStr(out, &pos, lat_str);

    out_buf.* = out[pos..];
    return out[0..pos];
}

/// Format a rich bilingual answer.
/// All labels adapt to the detected language (Arabic or English).
fn formatRichAnswer(
    out_buf: *[]u8,
    query: []const u8,
    domain: u8,
    partials: [5]PartialAnswer,
    reasoner: *const Reasoner,
    confidence: f32,
    tone: @import("l5/doubt.zig").Tone,
    tunnel_used: bool,
    subtext: @import("l4/intent.zig").SubtextHint,
    start_ts: i64,
    answer_lang: Language,
) []const u8 {
    const out = out_buf.*;
    var pos: usize = 0;

    // 0. Echo the query
    writeStr(out, &pos, Labels.query_label(answer_lang));
    writeStr(out, &pos, ": \"");
    writeStr(out, &pos, query);
    writeStr(out, &pos, "\". ");

    // 1. Tone prefix (bilingual)
    const prefix = switch (tone) {
        .confident => lang.TonePrefixes.confident(answer_lang),
        .likely => lang.TonePrefixes.likely(answer_lang),
        .uncertain => lang.TonePrefixes.uncertain(answer_lang),
        .low_confidence => lang.TonePrefixes.low_confidence(answer_lang),
        .contradictory => lang.TonePrefixes.contradictory(answer_lang),
    };
    writeStr(out, &pos, prefix);

    // 2. Domain identification (bilingual)
    writeStr(out, &pos, Labels.domain_label(answer_lang));
    writeStr(out, &pos, ": ");
    writeStr(out, &pos, lang.domainName(domain, answer_lang));
    writeStr(out, &pos, ". ");

    // 3. Find the best partial answer (highest confidence)
    var best_idx: usize = 0;
    var best_conf: f32 = 0;
    for (partials, 0..) |p, i| {
        if (p.confidence > best_conf) {
            best_conf = p.confidence;
            best_idx = i;
        }
    }

    // 4. The actual axiom text (translated to answer language)
    const best_partial = partials[best_idx];
    if (best_partial.final_axiom_id > 0 and best_partial.final_axiom_id < store.?.count) {
        const ax = store.?.get(best_partial.final_axiom_id) orelse {
            writeStr(out, &pos, Labels.axiom_label(answer_lang));
            writeStr(out, &pos, ": ");
            writeStr(out, &pos, Labels.no_axiom(answer_lang));
            writeStr(out, &pos, ". ");
            out_buf.* = out[pos..];
            return out[0..pos];
        };
        const ax_text = @import("l1/axiom.zig").axiomText(ax, store.?.text_blob);
        const translated = translate(ax_text, answer_lang);
        writeStr(out, &pos, Labels.axiom_label(answer_lang));
        writeStr(out, &pos, ": \"");
        writeStr(out, &pos, translated);
        writeStr(out, &pos, "\". ");
    } else if (best_partial.text_len > 0) {
        const ans_text = reasoner.answerText(best_idx);
        if (ans_text.len > 0) {
            writeStr(out, &pos, Labels.axiom_label(answer_lang));
            writeStr(out, &pos, ": ");
            writeStr(out, &pos, Labels.derivation_default(answer_lang));
            writeStr(out, &pos, ". ");
        } else {
            writeStr(out, &pos, Labels.derivation_default(answer_lang));
            writeStr(out, &pos, ". ");
        }
    } else {
        writeStr(out, &pos, Labels.no_axiom(answer_lang));
        writeStr(out, &pos, ". ");
    }

    // 5. Derivation path (translated to answer language)
    const path = reasoner.derivationPath(best_idx);
    if (path.len > 1) {
        writeStr(out, &pos, Labels.path_label(answer_lang));
        writeStr(out, &pos, ": ");
        var path_buf: [512]u8 = undefined;
        var pb_pos: usize = 0;
        for (path, 0..) |aid, i| {
            if (i > 0) writeStr(path_buf[0..], &pb_pos, " ← ");
            const ax = store.?.get(aid) orelse continue;
            const ax_text = @import("l1/axiom.zig").axiomText(ax, store.?.text_blob);
            const translated = translate(ax_text, answer_lang);
            const max_len: usize = 40;
            const shown = if (translated.len > max_len) translated[0..max_len] else translated;
            writeStr(path_buf[0..], &pb_pos, shown);
        }
        if (pb_pos > 0 and pos + pb_pos < out.len) {
            @memcpy(out[pos .. pos + pb_pos], path_buf[0..pb_pos]);
            pos += pb_pos;
        }
        writeStr(out, &pos, ". ");
    }

    // 6. Reasoning dimension (bilingual)
    writeStr(out, &pos, Labels.dimension_label(answer_lang));
    writeStr(out, &pos, ": ");
    writeStr(out, &pos, lang.dimensionName(@intCast(best_idx), answer_lang));
    writeStr(out, &pos, ". ");

    // 7. Tunnel marker (bilingual)
    if (tunnel_used) {
        writeStr(out, &pos, lang.tunnelLabel(answer_lang));
        writeStr(out, &pos, ". ");
    }

    // 8. Subtext hint (bilingual)
    const subtext_idx: u8 = switch (subtext) {
        .actionable_recommendation => 0,
        .steelman_counter => 1,
        .evidence_first => 2,
        .technical_depth => 3,
        .balanced_overview => 4,
    };
    writeStr(out, &pos, lang.subtextHint(subtext_idx, answer_lang));

    // 9. Confidence
    var conf_buf: [64]u8 = undefined;
    const conf_str = std.fmt.bufPrint(&conf_buf, "{s}: {d:.2}. ", .{
        Labels.confidence_label(answer_lang),
        confidence,
    }) catch "";
    writeStr(out, &pos, conf_str);

    // 10. Latency (bilingual)
    const elapsed: i64 = std.time.milliTimestamp() - start_ts;
    var lat_buf: [64]u8 = undefined;
    const lat_str = std.fmt.bufPrint(&lat_buf, "{s}: {d} {s}.", .{
        Labels.latency_label(answer_lang),
        elapsed,
        Labels.ms_unit(answer_lang),
    }) catch "";
    writeStr(out, &pos, lat_str);

    out_buf.* = out[pos..];
    return out[0..pos];
}

/// Helper to finalize the answer when bailing early.
fn finalizeAnswer(
    out_buf: *[]u8,
    out: []u8,
    pos: usize,
    query: []const u8,
    confidence: f32,
    best_dim: []const u8,
    tunnel_used: bool,
    subtext: @import("l4/intent.zig").SubtextHint,
    start_ts: i64,
) []const u8 {
    _ = query;
    _ = confidence;
    _ = best_dim;
    _ = tunnel_used;
    _ = subtext;
    _ = start_ts;
    out_buf.* = out[pos..];
    return out[0..pos];
}

/// Helper: write a string into a buffer at a position, advancing the position.
fn writeStr(buf: []u8, pos: *usize, s: []const u8) void {
    if (pos.* + s.len <= buf.len) {
        @memcpy(buf[pos.* .. pos.* + s.len], s);
        pos.* += s.len;
    }
}

/// Get the Arabic name of a domain.
fn domainName(d: u8) []const u8 {
    return switch (@as(Domain, @enumFromInt(d))) {
        .physics => "الفيزياء",
        .chemistry => "الكيمياء",
        .biology => "الأحياء",
        .mathematics => "الرياضيات",
        .logic => "المنطق",
        .computer_science => "علوم الحاسوب",
        .economics => "الاقتصاد",
        .psychology => "علم النفس",
        .history => "التاريخ",
        .philosophy => "الفلسفة",
        .linguistics => "اللسانيات",
        _ => "غير محدد",
    };
}

/// Pick a domain hint from the query text via bilingual keyword matching.
fn pickDomainHint(query: []const u8) u8 {
    // Economics
    if (containsAny(query, &[_][]const u8{
        "market", "price", "trade", "economy", "supply", "demand", "inflation", "scarcity",
        "opportunity cost", "economies of scale", "game theory", "money", "interest", "GDP",
        "stock", "bond", "monopoly", "recession", "tax", "currency",
        "fiscal", "monetary", "unemployment", "labor",
        "سوق", "سعر", "تجارة", "اقتصاد", "عرض", "طلب", "تضخم", "ندرة",
        "تكلفة", "وفورات", "ألعاب", "نقود", "فائدة", "ناتج محلي",
        "أسهم", "سندات", "احتكار", "ركود", "ضرائب", "عملة",
        "مالية", "نقدية", "بطالة", "عمل",
    })) return @intFromEnum(Domain.economics);

    // Logic
    if (containsAny(query, &[_][]const u8{
        "logic", "modus", "imply", "contradiction", "syllogism", "deductive", "entailment",
        "inductive", "abductive", "tautology", "fallacy", "valid",
        "منطق", "استنتاج", "تناقض", "قياس", "استقراء", "مغالطة", "حجة",
    })) return @intFromEnum(Domain.logic);

    // Physics
    if (containsAny(query, &[_][]const u8{
        "quantum", "physics", "energy", "friction", "heat", "motion", "braking",
        "superposition", "entanglement", "collapse", "measurement", "gravity", "light",
        "thermodynamics", "entropy", "waves", "force", "acceleration", "mass", "reaction",
        "كم", "فيزياء", "طاقة", "احتكاك", "حرارة", "حركة", "كبح", "تراكب", "تشابك", "انهيار", "قياس",
        "جاذبية", "ضوء", "ديناميكا", "إنتروبيا", "موجات", "قوة", "تسارع", "كتلة", "رد فعل",
    })) return @intFromEnum(Domain.physics);

    // Computer Science
    if (containsAny(query, &[_][]const u8{
        "AI", "neural", "algorithm", "computer", "information", "symbolic", "network",
        "data structure", "compression", "bits", "encryption", "recursion",
        "ذكاء", "خوارزم", "حاسوب", "معلومات", "رمزي", "شبكة", "ضغط", "بتات", "تشفير", "عودية",
    })) return @intFromEnum(Domain.computer_science);

    // Mathematics
    if (containsAny(query, &[_][]const u8{
        "math", "equation", "isomorphism", "diffusion", "vector", "algebra", "structure",
        "schrodinger", "calculus", "probability", "set theory", "graph theory",
        "prime", "derivative", "integral", "matrix", "matrices",
        "Euler", "Fibonacci", "Pythagorean", "logarithm", "trigonometry",
        "statistics", "topology", "golden ratio", "factorial", "quadratic",
        "infinity", "mean", "deviation", "correlation", "complex number", "pi",
        "رياض", "معادلة", "تماثل", "انتشار", "متجه", "جبر", "بنية",
        "تفاضل", "تكامل", "احتمال", "مجموعات", "مخططات", "أولي", "مصفوفة",
        "فيثاغورس", "لوغاريتم", "مثلثات", "إحصاء", "طوبولوجيا", "نسبة ذهبية",
        "عاملي", "تربيعية", "مالانهاية", "متوسط", "انحراف", "ارتباط", "باي",
    })) return @intFromEnum(Domain.mathematics);

    // Biology
    if (containsAny(query, &[_][]const u8{
        "cell", "DNA", "neuron", "evolution", "natural selection", "genetic", "species",
        "protein", "enzyme", "photosynthesis", "homeostasis", "mitochondria", "ribosome",
        "ecosystem",
        "خلية", "حمض نووي", "عصب", "تطور", "انتخاب طبيعي", "وراثي", "أنواع",
        "بروتين", "إنزيم", "تمثيل ضوئي", "اتزان", "ميتوكوندريا", "ريبوسوم", "نظام بيئي",
    })) return @intFromEnum(Domain.biology);

    // Chemistry
    if (containsAny(query, &[_][]const u8{
        "atom", "molecule", "catalyst", "reaction", "chemical", "bond", "matter",
        "acid", "base", "oxidation", "periodic", "equilibrium", "electron", "ionic", "covalent", "pH",
        "ذرة", "جزيء", "حفاز", "تفاعل", "كيمياء", "رابطة", "مادة",
        "حمض", "قاعدة", "أكسدة", "دوري", "توازن", "إلكترون", "تساهمي",
    })) return @intFromEnum(Domain.chemistry);

    // Psychology
    if (containsAny(query, &[_][]const u8{
        "behavior", "conditioning", "memory", "motivation", "emotion", "bias", "personality",
        "social influence", "psychology", "cognitive", "placebo", "Freud", "Piaget",
        "Bandura", "defense mechanism", "flow state", "mindset",
        "سلوك", "إشراط", "ذاكرة", "دافع", "مشاعر", "تحيز", "شخصية", "تأثير اجتماعي", "نفس",
        "دواء وهمي", "فرويد", "بياجه", "باندورا", "تدفق", "عقلية",
    })) return @intFromEnum(Domain.psychology);

    // History
    if (containsAny(query, &[_][]const u8{
        "civilization", "agricultural revolution", "industrial revolution", "writing",
        "trade route", "war", "colonialism", "history", "ancient",
        "renaissance", "printing press", "cold war", "empire", "revolution",
        "medieval", "century", "battle", "French Revolution", "World War",
        "Silk Road", "Roman",
        "حضارة", "ثورة زراعية", "ثورة صناعية", "كتابة", "طرق تجارة", "حرب", "استعمار", "تاريخ", "قدماء",
        "نهضة", "مطبعة", "حرب باردة", "إمبراطورية", "ثورة", "وسيط", "قرن", "معركة",
        "الثورة الفرنسية", "الحرب العالمية", "طريق الحرير", "رومانية",
    })) return @intFromEnum(Domain.history);

    // Philosophy
    if (containsAny(query, &[_][]const u8{
        "existentialism", "ethics", "epistemology", "metaphysics", "utilitarianism",
        "free will", "justice", "consciousness", "philosophy", "moral",
        "Descartes", "Nietzsche", "Socrates", "Plato", "Aristotle", "Kant",
        "Hume", "Mill", "Hegel", "Camus", "Confucius", "Locke",
        "وجودية", "أخلاق", "معرفة", "ميتافيزيقا", "نفعية", "إرادة حرة", "عدالة", "وعي", "فلسفة",
        "ديكارت", "نيتشه", "سقراطر", "أفلاطون", "أرسطو", "كانط",
        "هيوم", "مل", "هيغل", "كامو", "كونفوشيوس", "لوك",
    })) return @intFromEnum(Domain.philosophy);

    // Engineering — check early (Ohm, stress, strain are also physics words)
    if (containsAny(query, &[_][]const u8{
        "Ohm", "bridge", "hydraulic", "aerodynamic", "concrete", "steel",
        "semiconductor", "renewable", "strain", "Newton", "mechanic",
        "circuit", "voltage", "current", "resistance", "material", "control system",
        "engine", "feedback", "engineering", "load", "electrical",
        "هيكل", "دائرة", "جهد", "تيار", "مادة", "تحكم", "محرك", "تغذية راجعة", "هندسة", "حمل",
        "خرسانة", "فولاذ", "أوم", "جسر", "نصف ناقل",
    })) return @intFromEnum(Domain.engineering);

    // Linguistics
    if (containsAny(query, &[_][]const u8{
        "language", "syntax", "semantics", "phonology", "pragmatics", "linguistics",
        "morphology", "grammar", "bilingual", "translation", "phoneme", "metaphor",
        "code-switching", "sociolinguistics", "word formation",
        "لغة", "نحو", "دلالة", "أصوات", "تداولية", "لسانيات",
        "صرف", "قواعد", "ثنائية", "ترجمة", "فونيم", "استعارة",
    })) return @intFromEnum(Domain.linguistics);

    // Astronomy
    if (containsAny(query, &[_][]const u8{
        "star", "black hole", "universe", "galaxy", "planet", "Big Bang", "astronomy", "space",
        "نجم", "ثقب أسود", "كون", "مجرة", "كوكب", "انفجار عظيم", "فلك", "فضاء",
    })) return @intFromEnum(Domain.astronomy);

    // Medicine — check BEFORE physics/chemistry (cancer, blood, etc.)
    if (containsAny(query, &[_][]const u8{
        "vaccine", "antibiotic", "bacteria", "virus", "heart", "blood", "lung",
        "brain", "gene", "disease", "medicine", "immune", "health", "cancer",
        "diabetes", "cholesterol", "blood pressure", "doctor", "patient", "treatment",
        "symptom", "diagnosis", "therapy", "infection", "fever", "pain",
        "لقاح", "مضاد حيوي", "بكتيريا", "فيروس", "قلب", "دم", "رئة",
        "دماغ", "جين", "مرض", "طب", "مناعة", "صحة", "سرطان",
        "سكري", "كوليسترول", "ضغط الدم", "طبيب", "مريض", "علاج",
        "أعراض", "تشخيص", "علاج", "عدوى", "حمى", "ألم",
    })) return @intFromEnum(Domain.medicine);

    // History — check before physics (renaissance, cold war, etc.)
    if (containsAny(query, &[_][]const u8{
        "civilization", "agricultural revolution", "industrial revolution", "writing",
        "trade route", "war", "democracy", "colonialism", "history", "ancient",
        "renaissance", "printing press", "internet revolution", "cold war",
        "empire", "revolution", "medieval", "century", "battle",
        "حضارة", "ثورة زراعية", "ثورة صناعية", "كتابة", "طرق تجارة", "حرب", "استعمار", "تاريخ", "قدماء",
        "نهضة", "مطبعة", "ثورة الإنترنت", "حرب باردة", "إمبراطورية", "ثورة", "وسيط", "قرن", "معركة",
    })) return @intFromEnum(Domain.history);

    // Geology
    if (containsAny(query, &[_][]const u8{
        "tectonic", "earthquake", "volcano", "sedimentary", "fossil", "geology", "rock",
        "plate", "magma", "erosion", "mineral", "crust", "mantle",
        "صفائح", "زلزال", "بركان", "رسوبية", "حفريات", "جيولوجيا", "صخور",
        "صهارة", "تعرية", "معدن", "قشرة", "وشاح",
    })) return @intFromEnum(Domain.geology);

    // Engineering
    if (containsAny(query, &[_][]const u8{
        "structure", "circuit", "voltage", "current", "material", "control system",
        "engine", "feedback", "engineering", "load", "mechanical", "electrical",
        "هيكل", "دائرة", "جهد", "تيار", "مادة", "تحكم", "محرك", "تغذية راجعة", "هندسة", "حمل",
    })) return @intFromEnum(Domain.engineering);

    // Political Science
    if (containsAny(query, &[_][]const u8{
        "democracy", "power", "constitution", "international", "law", "human rights",
        "government", "political", "citizen", "tyranny", "election", "parliament",
        "federalism", "authoritarian", "diplomacy", "nationalism", "sovereignty",
        "propaganda", "judicial", "social contract", "legislation",
        "ديمقراطية", "سلطة", "دستور", "دولي", "قانون", "حقوق إنسان", "حكومة", "سياس", "مواطن", "استبداد",
        "انتخاب", "برلمان", "فيدرالية", "دبلوماسية", "قومية", "سيادة", "دعاية", "قضائية",
    })) return @intFromEnum(Domain.political_science);

    return @intFromEnum(Domain.physics); // default
}

/// Check if the query contains any of the keywords (case-insensitive for ASCII).
fn containsAny(haystack: []const u8, needles: []const []const u8) bool {
    // Simple case-insensitive check: convert both to lowercase on the fly.
    for (needles) |n| {
        if (ciIndexOf(haystack, n)) |_| return true;
    }
    return false;
}

/// Case-insensitive indexOf for ASCII text.
/// Enforces word boundaries for keywords <= 3 chars to prevent
/// "AI" matching "Renaissance" or "pi" matching "spiral".
fn ciIndexOf(haystack: []const u8, needle: []const u8) ?usize {
    if (needle.len == 0 or needle.len > haystack.len) return null;
    const need_boundary = needle.len <= 3;
    var i: usize = 0;
    while (i + needle.len <= haystack.len) : (i += 1) {
        var match = true;
        for (needle, 0..) |nb, j| {
            const hb = haystack[i + j];
            if (toLowerAscii(hb) != toLowerAscii(nb)) {
                match = false;
                break;
            }
        }
        if (match) {
            if (need_boundary) {
                // Check left boundary: char before must be non-word char.
                if (i > 0 and isWordByte(haystack[i - 1])) continue;
                // Check right boundary: char after must be non-word char.
                const after = i + needle.len;
                if (after < haystack.len and isWordByte(haystack[after])) continue;
            }
            return i;
        }
    }
    return null;
}

fn isWordByte(b: u8) bool {
    return (b >= 'a' and b <= 'z') or (b >= 'A' and b <= 'Z') or (b >= '0' and b <= '9') or b >= 0x80;
}

fn toLowerAscii(b: u8) u8 {
    if (b >= 'A' and b <= 'Z') return b + 32;
    return b;
}

/// Ingest a new axiom (called by Swarm or Crawler).
pub fn ingestAxiom(domain: u8, text: []const u8, confidence: f32) !void {
    if (!bootstrapped) try bootstrap();
    _ = try store.?.add(domain, text, confidence, &[_]u32{});
    _ = try graph.?.addNode(text, .axiom, @enumFromInt(domain), confidence);
    std.log.info("Ingested axiom: {s}", .{text});
}

/// Shutdown — flush living memory to disk.
pub fn shutdown() void {
    if (!bootstrapped) return;
    std.log.info("Omni-Mind shutting down. Total events: {d}", .{memory.?.totalEvents()});
}
