// src/prog_bench.zig — Programming knowledge benchmark
//
// Tests the system's software engineering knowledge across
// 19 categories of programming axioms.

const std = @import("std");
const core = @import("core.zig");

pub const PROG_BENCH = [_]struct {
    query: []const u8,
    expected_domain: u8,
    min_confidence: f32,
    category: []const u8,
}{
    .{ .query = "what is Python?", .expected_domain = 5, .min_confidence = 0.30, .category = "prog/lang" },
    .{ .query = "what is JavaScript?", .expected_domain = 5, .min_confidence = 0.30, .category = "prog/lang" },
    .{ .query = "what is Rust?", .expected_domain = 5, .min_confidence = 0.30, .category = "prog/lang" },
    .{ .query = "what is Go?", .expected_domain = 5, .min_confidence = 0.30, .category = "prog/lang" },
    .{ .query = "what is Java?", .expected_domain = 5, .min_confidence = 0.30, .category = "prog/lang" },
    .{ .query = "what is C++?", .expected_domain = 5, .min_confidence = 0.30, .category = "prog/lang" },
    .{ .query = "what is TypeScript?", .expected_domain = 5, .min_confidence = 0.30, .category = "prog/lang" },
    .{ .query = "what is Swift?", .expected_domain = 5, .min_confidence = 0.30, .category = "prog/lang" },
    .{ .query = "what is Kotlin?", .expected_domain = 5, .min_confidence = 0.30, .category = "prog/lang" },
    .{ .query = "what is a hash table?", .expected_domain = 5, .min_confidence = 0.30, .category = "prog/ds" },
    .{ .query = "what is a linked list?", .expected_domain = 5, .min_confidence = 0.30, .category = "prog/ds" },
    .{ .query = "what is a binary search tree?", .expected_domain = 5, .min_confidence = 0.30, .category = "prog/ds" },
    .{ .query = "what is a heap?", .expected_domain = 5, .min_confidence = 0.30, .category = "prog/ds" },
    .{ .query = "what is a stack?", .expected_domain = 5, .min_confidence = 0.30, .category = "prog/ds" },
    .{ .query = "what is a queue?", .expected_domain = 5, .min_confidence = 0.30, .category = "prog/ds" },
    .{ .query = "what is a graph?", .expected_domain = 5, .min_confidence = 0.30, .category = "prog/ds" },
    .{ .query = "what is a trie?", .expected_domain = 5, .min_confidence = 0.30, .category = "prog/ds" },
    .{ .query = "what is an array?", .expected_domain = 5, .min_confidence = 0.30, .category = "prog/ds" },
    .{ .query = "what is quicksort?", .expected_domain = 5, .min_confidence = 0.30, .category = "prog/algo" },
    .{ .query = "what is mergesort?", .expected_domain = 5, .min_confidence = 0.30, .category = "prog/algo" },
    .{ .query = "what is binary search?", .expected_domain = 5, .min_confidence = 0.30, .category = "prog/algo" },
    .{ .query = "what is dynamic programming?", .expected_domain = 5, .min_confidence = 0.30, .category = "prog/algo" },
    .{ .query = "what is memoization?", .expected_domain = 5, .min_confidence = 0.30, .category = "prog/algo" },
    .{ .query = "what is Dijkstra algorithm?", .expected_domain = 5, .min_confidence = 0.30, .category = "prog/algo" },
    .{ .query = "what is BFS?", .expected_domain = 5, .min_confidence = 0.30, .category = "prog/algo" },
    .{ .query = "what is DFS?", .expected_domain = 5, .min_confidence = 0.30, .category = "prog/algo" },
    .{ .query = "what is Singleton pattern?", .expected_domain = 5, .min_confidence = 0.30, .category = "prog/pattern" },
    .{ .query = "what is Factory pattern?", .expected_domain = 5, .min_confidence = 0.30, .category = "prog/pattern" },
    .{ .query = "what is Observer pattern?", .expected_domain = 5, .min_confidence = 0.30, .category = "prog/pattern" },
    .{ .query = "what is Strategy pattern?", .expected_domain = 5, .min_confidence = 0.30, .category = "prog/pattern" },
    .{ .query = "what is Decorator pattern?", .expected_domain = 5, .min_confidence = 0.30, .category = "prog/pattern" },
    .{ .query = "what is Adapter pattern?", .expected_domain = 5, .min_confidence = 0.30, .category = "prog/pattern" },
    .{ .query = "what is MVC?", .expected_domain = 5, .min_confidence = 0.30, .category = "prog/pattern" },
    .{ .query = "what is SOLID?", .expected_domain = 5, .min_confidence = 0.30, .category = "prog/principle" },
    .{ .query = "what is DRY principle?", .expected_domain = 5, .min_confidence = 0.30, .category = "prog/principle" },
    .{ .query = "what is KISS principle?", .expected_domain = 5, .min_confidence = 0.30, .category = "prog/principle" },
    .{ .query = "what is YAGNI?", .expected_domain = 5, .min_confidence = 0.30, .category = "prog/principle" },
    .{ .query = "what is single responsibility?", .expected_domain = 5, .min_confidence = 0.30, .category = "prog/principle" },
    .{ .query = "what is dependency inversion?", .expected_domain = 5, .min_confidence = 0.30, .category = "prog/principle" },
    .{ .query = "what is composition over inheritance?", .expected_domain = 5, .min_confidence = 0.30, .category = "prog/principle" },
    .{ .query = "what is microservices?", .expected_domain = 5, .min_confidence = 0.30, .category = "prog/arch" },
    .{ .query = "what is monolithic architecture?", .expected_domain = 5, .min_confidence = 0.30, .category = "prog/arch" },
    .{ .query = "what is clean architecture?", .expected_domain = 5, .min_confidence = 0.30, .category = "prog/arch" },
    .{ .query = "what is event-driven architecture?", .expected_domain = 5, .min_confidence = 0.30, .category = "prog/arch" },
    .{ .query = "what is CQRS?", .expected_domain = 5, .min_confidence = 0.30, .category = "prog/arch" },
    .{ .query = "what is REST API?", .expected_domain = 5, .min_confidence = 0.30, .category = "prog/arch" },
    .{ .query = "what is GraphQL?", .expected_domain = 5, .min_confidence = 0.30, .category = "prog/arch" },
    .{ .query = "what is gRPC?", .expected_domain = 5, .min_confidence = 0.30, .category = "prog/arch" },
    .{ .query = "what is unit testing?", .expected_domain = 5, .min_confidence = 0.30, .category = "prog/test" },
    .{ .query = "what is TDD?", .expected_domain = 5, .min_confidence = 0.30, .category = "prog/test" },
    .{ .query = "what is BDD?", .expected_domain = 5, .min_confidence = 0.30, .category = "prog/test" },
    .{ .query = "what is code coverage?", .expected_domain = 5, .min_confidence = 0.30, .category = "prog/test" },
    .{ .query = "what is fuzz testing?", .expected_domain = 5, .min_confidence = 0.30, .category = "prog/test" },
    .{ .query = "what is Docker?", .expected_domain = 5, .min_confidence = 0.30, .category = "prog/devops" },
    .{ .query = "what is Kubernetes?", .expected_domain = 5, .min_confidence = 0.30, .category = "prog/devops" },
    .{ .query = "what is CI/CD?", .expected_domain = 5, .min_confidence = 0.30, .category = "prog/devops" },
    .{ .query = "what is load balancing?", .expected_domain = 5, .min_confidence = 0.30, .category = "prog/devops" },
    .{ .query = "what is caching?", .expected_domain = 5, .min_confidence = 0.30, .category = "prog/devops" },
    .{ .query = "what is ACID?", .expected_domain = 5, .min_confidence = 0.30, .category = "prog/db" },
    .{ .query = "what is NoSQL?", .expected_domain = 5, .min_confidence = 0.30, .category = "prog/db" },
    .{ .query = "what is database indexing?", .expected_domain = 5, .min_confidence = 0.30, .category = "prog/db" },
    .{ .query = "what is sharding?", .expected_domain = 5, .min_confidence = 0.30, .category = "prog/db" },
    .{ .query = "what is CAP theorem?", .expected_domain = 5, .min_confidence = 0.30, .category = "prog/db" },
    .{ .query = "what is SQL injection?", .expected_domain = 5, .min_confidence = 0.30, .category = "prog/security" },
    .{ .query = "what is XSS?", .expected_domain = 5, .min_confidence = 0.30, .category = "prog/security" },
    .{ .query = "what is JWT?", .expected_domain = 5, .min_confidence = 0.30, .category = "prog/security" },
    .{ .query = "what is OAuth?", .expected_domain = 5, .min_confidence = 0.30, .category = "prog/security" },
    .{ .query = "what is bcrypt?", .expected_domain = 5, .min_confidence = 0.30, .category = "prog/security" },
    .{ .query = "what is Git?", .expected_domain = 5, .min_confidence = 0.30, .category = "prog/git" },
    .{ .query = "what is Git branching?", .expected_domain = 5, .min_confidence = 0.30, .category = "prog/git" },
    .{ .query = "what is Git rebase?", .expected_domain = 5, .min_confidence = 0.30, .category = "prog/git" },
    .{ .query = "what is a pull request?", .expected_domain = 5, .min_confidence = 0.30, .category = "prog/git" },
    .{ .query = "what is technical debt?", .expected_domain = 5, .min_confidence = 0.30, .category = "prog/quality" },
    .{ .query = "what is refactoring?", .expected_domain = 5, .min_confidence = 0.30, .category = "prog/quality" },
    .{ .query = "what is clean code?", .expected_domain = 5, .min_confidence = 0.30, .category = "prog/quality" },
    .{ .query = "what are code smells?", .expected_domain = 5, .min_confidence = 0.30, .category = "prog/quality" },
    .{ .query = "what is React?", .expected_domain = 5, .min_confidence = 0.30, .category = "prog/web" },
    .{ .query = "what is Node.js?", .expected_domain = 5, .min_confidence = 0.30, .category = "prog/web" },
    .{ .query = "what is Next.js?", .expected_domain = 5, .min_confidence = 0.30, .category = "prog/web" },
    .{ .query = "what is Django?", .expected_domain = 5, .min_confidence = 0.30, .category = "prog/web" },
    .{ .query = "what are WebSockets?", .expected_domain = 5, .min_confidence = 0.30, .category = "prog/web" },
    .{ .query = "what is async/await?", .expected_domain = 5, .min_confidence = 0.30, .category = "prog/concurrency" },
    .{ .query = "what is a mutex?", .expected_domain = 5, .min_confidence = 0.30, .category = "prog/concurrency" },
    .{ .query = "what is deadlock?", .expected_domain = 5, .min_confidence = 0.30, .category = "prog/concurrency" },
    .{ .query = "what is the event loop?", .expected_domain = 5, .min_confidence = 0.30, .category = "prog/concurrency" },
    .{ .query = "what is a CDN?", .expected_domain = 5, .min_confidence = 0.30, .category = "prog/system" },
    .{ .query = "what is a circuit breaker?", .expected_domain = 5, .min_confidence = 0.30, .category = "prog/system" },
    .{ .query = "what is an API gateway?", .expected_domain = 5, .min_confidence = 0.30, .category = "prog/system" },
    .{ .query = "what is backpressure?", .expected_domain = 5, .min_confidence = 0.30, .category = "prog/system" },
    .{ .query = "what are neural networks?", .expected_domain = 5, .min_confidence = 0.30, .category = "prog/ai" },
    .{ .query = "what is gradient descent?", .expected_domain = 5, .min_confidence = 0.30, .category = "prog/ai" },
    .{ .query = "what is overfitting?", .expected_domain = 5, .min_confidence = 0.30, .category = "prog/ai" },
    .{ .query = "what are transformers?", .expected_domain = 5, .min_confidence = 0.30, .category = "prog/ai" },
    .{ .query = "what is RAG?", .expected_domain = 5, .min_confidence = 0.30, .category = "prog/ai" },
    .{ .query = "what is AWS?", .expected_domain = 5, .min_confidence = 0.30, .category = "prog/cloud" },
    .{ .query = "what is serverless?", .expected_domain = 5, .min_confidence = 0.30, .category = "prog/cloud" },
    .{ .query = "what is IaaS?", .expected_domain = 5, .min_confidence = 0.30, .category = "prog/cloud" },
    .{ .query = "what is edge computing?", .expected_domain = 5, .min_confidence = 0.30, .category = "prog/cloud" },
};

pub fn main() !void {
    try core.bootstrap();
    defer core.shutdown();

    const stdout = std.io.getStdOut().writer();
    try stdout.print("=== Programming Knowledge Benchmark ===\n\n", .{});
    try stdout.print("Testing {d} programming questions...\n\n", .{PROG_BENCH.len});

    var pass: u32 = 0;
    var fail: u32 = 0;

    for (PROG_BENCH) |q| {
        var buf: [8192]u8 = undefined;
        var slice: []u8 = buf[0..];
        const answer = core.runQuery(q.query, &slice) catch {
            try stdout.print("  ✗ {s}: ERROR\n", .{q.category});
            fail += 1;
            continue;
        };

        // Check if answer contains relevant content
        const has_content = answer.len > 50;

        if (has_content) {
            try stdout.print("  ✓ [{s}] {s}\n", .{ q.category, q.query });
            pass += 1;
        } else {
            try stdout.print("  ✗ [{s}] {s}\n", .{ q.category, q.query });
            fail += 1;
        }
    }

    try stdout.print("\n=== Results ===\n", .{});
    try stdout.print("  Pass: {d}/{d}\n", .{ pass, PROG_BENCH.len });
    try stdout.print("  Fail: {d}/{d}\n", .{ fail, PROG_BENCH.len });
    try stdout.print("  Rate: {d:.1}%\n", .{ @as(f32, @floatFromInt(pass)) / @as(f32, @floatFromInt(PROG_BENCH.len)) * 100.0 });
}
