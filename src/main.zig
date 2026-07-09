// src/main.zig — Omni-Mind entry point.
//
// Supports three modes:
//   --query "..."   — single query, exit
//   --repl          — interactive REPL with multi-user + persistent memory
//   --demo          — run 4 demo queries
//   --serve PORT    — TCP server mode (multiple clients)
//
// REPL commands:
//   /user NAME      — switch user
//   /history        — show recent memory for current user
//   /stats          — show system stats
//   /ingest DOMAIN TEXT — add a new axiom
//   /save           — save memory to disk
//   /load           — reload memory from disk
//   /help           — show commands
//   /exit           — quit

const std = @import("std");
const core = @import("core.zig");
const allocator = @import("core/allocator.zig");
const Domain = @import("core/node.zig").Domain;

const MEMORY_FILE = "omni_memory.bin";
const MAX_USERS = 64;

const ReplState = struct {
    current_user: u32 = 0,
    user_names: [MAX_USERS][32]u8 = std.mem.zeroes([MAX_USERS][32]u8),
    user_count: u32 = 0,
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const heap = gpa.allocator();

    const args = try std.process.argsAlloc(heap);
    defer std.process.argsFree(heap, args);

    try core.bootstrap();
    defer core.shutdown();

    if (args.len >= 3 and std.mem.eql(u8, args[1], "--query")) {
        try runOneQuery(args[2]);
        return;
    }

    if (args.len >= 3 and std.mem.eql(u8, args[1], "--serve")) {
        const port = std.fmt.parseInt(u16, args[2], 10) catch 19090;
        const server = @import("server.zig");
        try server.run(port);
        return;
    }

    if (args.len >= 2 and std.mem.eql(u8, args[1], "--repl")) {
        try replMode();
        return;
    }

    if (args.len >= 2 and std.mem.eql(u8, args[1], "--demo")) {
        try demoMode();
        return;
    }

    printUsage();
}

fn printUsage() void {
    const stderr = std.io.getStdErr().writer();
    stderr.print(
        \\Omni-Mind — Quantum-Inspired Symbolic AI on CPU
        \\
        \\Usage:
        \\  omni-mind --query "your question here"
        \\  omni-mind --repl
        \\  omni-mind --serve PORT
        \\  omni-mind --demo
        \\
        \\TCP server protocol:
        \\  QUERY:user_id:text  — run a query
        \\  STATS               — get system stats
        \\  INGEST:domain:text  — add an axiom
        \\  BYE                 — disconnect
        \\
        \\REPL commands:
        \\  /user NAME      — switch to user (creates if new)
        \\  /history        — show recent memory for current user
        \\  /stats          — show system stats
        \\  /ingest D TEXT  — add axiom (D = domain 0-9)
        \\  /list           — list all axioms (English)
        \\  /list ar        — list all axioms (Arabic)
        \\  /save           — save memory to disk
        \\  /load           — reload memory from disk
        \\  /help           — show commands
        \\  /exit           — quit
        \\
    , .{}) catch {};
}

fn runOneQuery(query: []const u8) !void {
    var buf: [8192]u8 = undefined;
    var buf_slice: []u8 = buf[0..];
    const answer = try core.runQuery(query, &buf_slice);

    const stdout = std.io.getStdOut().writer();
    try stdout.print("Q: {s}\n", .{query});
    try stdout.print("A: {s}\n\n", .{answer});
    try printStats(stdout);
}

fn printStats(writer: anytype) !void {
    try writer.print("[Memory: {d:.2} MB / {d:.0} MB ({d:.1}%)]\n", .{
        @as(f32, @floatFromInt(allocator.bytes_used)) / (1024 * 1024),
        @as(f32, @floatFromInt(allocator.CORE_BUDGET)) / (1024 * 1024),
        allocator.usageFraction() * 100.0,
    });
}

fn replMode() !void {
    const stdin = std.io.getStdIn().reader();
    const stdout = std.io.getStdOut().writer();

    var state = ReplState{};
    // Default user "default"
    setUserName(&state, 0, "default");

    try stdout.print("╔════════════════════════════════════════════════════════════╗\n", .{});
    try stdout.print("║  Omni-Mind Interactive REPL                                ║\n", .{});
    try stdout.print("║  Multi-user · Persistent Memory · 7-Layer Reasoning        ║\n", .{});
    try stdout.print("╚════════════════════════════════════════════════════════════╝\n", .{});
    try stdout.print("\nCurrent user: default (id=0)\n", .{});
    try stdout.print("Type /help for commands, or ask any question.\n\n", .{});

    var buf: [8192]u8 = undefined;
    while (true) {
        try stdout.print("[user:{d}] > ", .{state.current_user});
        const line = stdin.readUntilDelimiterOrEof(&buf, '\n') catch |err| {
            try stdout.print("Error: {}\n", .{err});
            continue;
        } orelse break;

        const input = std.mem.trim(u8, line, " \t\r");
        if (input.len == 0) continue;

        // Handle commands
        if (std.mem.startsWith(u8, input, "/")) {
            try handleCommand(&state, input, stdout);
            continue;
        }

        if (std.mem.eql(u8, input, "exit") or std.mem.eql(u8, input, "quit")) break;

        // Run the query
        var out_buf: [8192]u8 = undefined;
        var out_slice: []u8 = out_buf[0..];
        const answer = core.runQuery(input, &out_slice) catch |err| {
            try stdout.print("Error: {}\n", .{err});
            continue;
        };
        try stdout.print("\n{s}\n\n", .{answer});
    }

    try stdout.print("\nGoodbye!\n", .{});
}

fn handleCommand(state: *ReplState, input: []const u8, stdout: anytype) !void {
    if (std.mem.eql(u8, input, "/help")) {
        try stdout.print(
            \\Commands:
            \\  /user NAME      — switch to user (creates if new)
            \\  /history        — show recent memory for current user
            \\  /stats          — show system stats
            \\  /ingest D TEXT  — add axiom (D = domain 0-9)
            \\  /list           — list all axioms (English)
            \\  /list ar        — list all axioms (Arabic)
            \\  /save           — save memory to disk
            \\  /load           — reload memory from disk
            \\  /help           — show this help
            \\  /exit           — quit
            \\
        , .{});
        return;
    }

    if (std.mem.eql(u8, input, "/exit") or std.mem.eql(u8, input, "/quit")) {
        return error.ExitRequested;
    }

    if (std.mem.eql(u8, input, "/stats")) {
        try stdout.print("\n=== System Stats ===\n", .{});
        try stdout.print("  Memory: {d:.2} MB / {d:.0} MB ({d:.1}%)\n", .{
            @as(f32, @floatFromInt(allocator.bytes_used)) / (1024 * 1024),
            @as(f32, @floatFromInt(allocator.CORE_BUDGET)) / (1024 * 1024),
            allocator.usageFraction() * 100.0,
        });
        const stats = core.graph.?.stats();
        try stdout.print("  Nodes: {d}\n", .{stats.node_count});
        try stdout.print("  Edges: {d}\n", .{stats.edge_count});
        try stdout.print("  Axioms: {d}\n", .{core.store.?.count});
        try stdout.print("  Total events: {d}\n\n", .{core.memory.?.totalEvents()});
        return;
    }

    if (std.mem.startsWith(u8, input, "/user ")) {
        const name = input[6..];
        if (name.len == 0) {
            try stdout.print("Usage: /user NAME\n", .{});
            return;
        }
        // Find or create user
        for (0..state.user_count) |i| {
            const existing = std.mem.sliceTo(&state.user_names[i], 0);
            if (std.mem.eql(u8, existing, name)) {
                state.current_user = @intCast(i);
                try stdout.print("Switched to user '{s}' (id={d})\n", .{ name, state.current_user });
                return;
            }
        }
        if (state.user_count >= MAX_USERS) {
            try stdout.print("Max users reached\n", .{});
            return;
        }
        setUserName(state, state.user_count, name);
        state.current_user = state.user_count;
        state.user_count += 1;
        try stdout.print("Created user '{s}' (id={d})\n", .{ name, state.current_user });
        return;
    }

    if (std.mem.eql(u8, input, "/history")) {
        try stdout.print("\n=== Recent memory for user {d} ===\n", .{state.current_user});
        const DeltaEvent = @import("l7/living.zig").DeltaEvent;
        var events: [16]DeltaEvent = undefined;
        const n = core.memory.?.recall(state.current_user, 0xFF, &events);
        if (n == 0) {
            try stdout.print("  (no events)\n", .{});
        } else {
            for (events[0..n], 0..) |ev, i| {
                try stdout.print("  [{d}] domain={d} confidence={d:.2} target={d}\n", .{
                    i + 1, ev.domain, ev.confidence, ev.target_id,
                });
            }
        }
        try stdout.print("\n", .{});
        return;
    }

    if (std.mem.startsWith(u8, input, "/ingest ")) {
        // /ingest DOMAIN TEXT
        const rest = input[8..];
        const space = std.mem.indexOf(u8, rest, " ") orelse {
            try stdout.print("Usage: /ingest DOMAIN TEXT\n", .{});
            return;
        };
        const domain_str = rest[0..space];
        const text = rest[space + 1 ..];
        const domain = std.fmt.parseInt(u8, domain_str, 10) catch {
            try stdout.print("Invalid domain. Use 0-9.\n", .{});
            return;
        };
        core.ingestAxiom(domain, text, 0.8) catch |err| {
            try stdout.print("Ingest failed: {}\n", .{err});
            return;
        };
        try stdout.print("Ingested axiom into domain {d}: {s}\n", .{ domain, text });
        return;
    }

    if (std.mem.eql(u8, input, "/list")) {
        try stdout.print("\n=== Knowledge Base ({d} axioms) ===\n", .{core.store.?.count});
        const lang_mod = @import("core/lang.zig");
        for (0..core.store.?.count) |i| {
            const ax = core.store.?.axioms[i];
            const text = @import("l1/axiom.zig").axiomText(ax, core.store.?.text_blob);
            const domain_name = lang_mod.domainName(ax.domain, .english);
            try stdout.print("  [{d:>3}] {s}: {s}\n", .{ i, domain_name, text });
        }
        try stdout.print("\n", .{});
        return;
    }

    if (std.mem.eql(u8, input, "/self")) {
        var report_buf: [2048]u8 = undefined;
        const self_mod = @import("core/self.zig");
        const lang_mod = @import("core/lang.zig");
        const detected = lang_mod.Language.detect(input);
        const n = self_mod.selfReport(&core.self_state, detected, &report_buf);
        try stdout.print("\n{s}\n", .{report_buf[0..n]});
        return;
    }

    if (std.mem.eql(u8, input, "/self reflect")) {
        try stdout.print("\n=== Self-Reflection: Generating self-tests ===\n", .{});
        const self_mod = @import("core/self.zig");
        var tests: [16]self_mod.SelfTest = undefined;
        const n = self_mod.selfReflect(&core.self_state, &tests);
        if (n == 0) {
            try stdout.print("  (no weak domains or self-learned axioms to test)\n", .{});
        } else {
            for (tests[0..n], 0..) |t, i| {
                try stdout.print("  [{d}] domain={d} reason={s}\n    Q: {s}\n", .{
                    i + 1,
                    t.domain,
                    t.reason[0..t.reason_len],
                    t.question[0..t.question_len],
                });
            }
        }
        try stdout.print("\n", .{});
        return;
    }

    if (std.mem.eql(u8, input, "/self learn")) {
        try stdout.print("\n=== Self-Learning: Checking for patterns ===\n", .{});
        const self_mod = @import("core/self.zig");
        var auto_axioms: [8]self_mod.AutoAxiom = undefined;
        const n = self_mod.selfLearn(&core.self_state, &auto_axioms);
        if (n == 0) {
            try stdout.print("  (no patterns found yet — need more failed queries)\n", .{});
        } else {
            for (auto_axioms[0..n], 0..) |aa, i| {
                try stdout.print("  [{d}] domain={d} conf={d:.2}\n    {s}\n", .{
                    i + 1,
                    aa.domain,
                    aa.confidence,
                    aa.text[0..aa.text_len],
                });
            }
        }
        try stdout.print("\n", .{});
        return;
    }

    if (std.mem.eql(u8, input, "/self evolve")) {
        var evolve_buf: [4096]u8 = undefined;
        const self_mod = @import("core/self.zig");
        const lang_mod = @import("core/lang.zig");
        const detected = lang_mod.Language.detect(input);
        const n = self_mod.selfEvolve(&core.self_state, detected, &evolve_buf);
        try stdout.print("\n{s}\n", .{evolve_buf[0..n]});
        return;
    }

    if (std.mem.eql(u8, input, "/self iq")) {
        const self_mod = @import("core/self.zig");
        const lang_mod = @import("core/lang.zig");
        const detected = lang_mod.Language.detect(input);
        // Count active domains
        var domain_count: usize = 0;
        for (core.self_state.domain_weakness) |ds| {
            if (ds.query_count > 0) domain_count += 1;
        }
        if (domain_count == 0) domain_count = 7; // default domains
        const report = self_mod.generateIQReport(&core.self_state, core.store.?.count, domain_count);
        var iq_buf: [2048]u8 = undefined;
        const n = self_mod.formatIQReport(report, detected, &iq_buf);
        try stdout.print("\n{s}\n", .{iq_buf[0..n]});
        return;
    }

    if (std.mem.eql(u8, input, "/list ar")) {
        try stdout.print("\n=== قاعدة المعرفة ({d} بديهية) ===\n", .{core.store.?.count});
        const lang_mod = @import("core/lang.zig");
        const translate = @import("core/axiom_translations.zig").translate;
        for (0..core.store.?.count) |i| {
            const ax = core.store.?.axioms[i];
            const text = @import("l1/axiom.zig").axiomText(ax, core.store.?.text_blob);
            const ar_text = translate(text, .arabic);
            const domain_name = lang_mod.domainName(ax.domain, .arabic);
            try stdout.print("  [{d:>3}] {s}: {s}\n", .{ i, domain_name, ar_text });
        }
        try stdout.print("\n", .{});
        return;
    }

    if (std.mem.eql(u8, input, "/save")) {
        try saveMemory(stdout);
        return;
    }

    if (std.mem.eql(u8, input, "/load")) {
        try loadMemory(stdout);
        return;
    }

    try stdout.print("Unknown command: {s} (try /help)\n", .{input});
}

fn setUserName(state: *ReplState, idx: u32, name: []const u8) void {
    @memset(&state.user_names[idx], 0);
    const n = @min(name.len, 31);
    @memcpy(state.user_names[idx][0..n], name[0..n]);
}

fn saveMemory(stdout: anytype) !void {
    const DeltaEvent = @import("l7/living.zig").DeltaEvent;
    const file = std.fs.cwd().createFile(MEMORY_FILE, .{}) catch |err| {
        try stdout.print("Save failed: {}\n", .{err});
        return;
    };
    defer file.close();

    const total = core.memory.?.totalEvents();
    const capacity = core.memory.?.capacity;
    const to_write = @min(total, capacity);

    var writer = file.writer();
    // Write header: total (8 bytes) + capacity (8 bytes)
    var total_bytes: [8]u8 = undefined;
    std.mem.writeInt(u64, &total_bytes, total, .little);
    try writer.writeAll(&total_bytes);
    var cap_bytes: [8]u8 = undefined;
    std.mem.writeInt(u64, &cap_bytes, capacity, .little);
    try writer.writeAll(&cap_bytes);

    // Write events
    const events: []const DeltaEvent = core.memory.?.events[0..capacity];
    for (events[0..to_write]) |ev| {
        try writer.writeAll(std.mem.asBytes(&ev));
    }

    try stdout.print("Saved {d} events to {s}\n", .{ to_write, MEMORY_FILE });
}

fn loadMemory(stdout: anytype) !void {
    const DeltaEvent = @import("l7/living.zig").DeltaEvent;
    const file = std.fs.cwd().openFile(MEMORY_FILE, .{}) catch |err| {
        try stdout.print("Load failed: {} (no saved memory?)\n", .{err});
        return;
    };
    defer file.close();

    var reader = file.reader();
    var hdr_buf: [16]u8 = undefined;
    _ = reader.readAll(&hdr_buf) catch |err| {
        try stdout.print("Read failed: {}\n", .{err});
        return;
    };
    const total = std.mem.readInt(u64, hdr_buf[0..8], .little);
    const cap = std.mem.readInt(u64, hdr_buf[8..16], .little);

    const to_read = @min(total, cap, core.memory.?.capacity);
    for (0..to_read) |_| {
        var ev: DeltaEvent = undefined;
        const bytes = std.mem.asBytes(&ev);
        _ = reader.readAll(bytes) catch |err| {
            try stdout.print("Read failed at event: {}\n", .{err});
            return;
        };
        core.memory.?.record(ev);
    }

    try stdout.print("Loaded {d} events from {s}\n", .{ to_read, MEMORY_FILE });
}

fn demoMode() !void {
    const stdout = std.io.getStdOut().writer();
    try stdout.print(
        \\╔════════════════════════════════════════════════════════════╗
        \\║          Project Omni-Mind — Demo Mode                    ║
        \\║   Quantum-Inspired Symbolic AI · CPU Only · 2GB RAM       ║
        \\╚════════════════════════════════════════════════════════════╝
        \\
        \\
    , .{});

    const queries = [_][]const u8{
        "why do brakes get hot?",
        "Can quantum mechanics improve AI?",
        "what is isomorphism in math?",
        "how does friction work?",
    };

    for (queries) |q| {
        try runOneQuery(q);
        try stdout.print("─────────────────────────────────────────\n", .{});
    }
}
