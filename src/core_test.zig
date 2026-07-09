// src/core_test.zig — Aggregated unit tests.
// Run with: zig build test

test "core: node sizes" {
    _ = @import("core/node.zig");
    _ = @import("core/graph.zig");
    _ = @import("core/mmap.zig");
    _ = @import("core/allocator.zig");
    _ = @import("core/lang.zig");
    _ = @import("core/axiom_translations.zig");
    _ = @import("core/conversation.zig");
    _ = @import("core/self.zig");
    _ = @import("core/learning.zig");
}

test "l1: axiom and collapse" {
    _ = @import("l1/axiom.zig");
    _ = @import("l1/collapse.zig");
    _ = @import("l1/procedural_weights.zig");
}

test "l2-l7: layers" {
    _ = @import("l2/reasoning.zig");
    _ = @import("l3/analogy.zig");
    _ = @import("l4/intent.zig");
    _ = @import("l5/doubt.zig");
    _ = @import("l6/synthesis.zig");
    _ = @import("l7/living.zig");
}
