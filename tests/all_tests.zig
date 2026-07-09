// tests/all_tests.zig — Aggregates all unit tests.
// NOTE: in Zig 0.13 we can only import files within the same module.
// The test runner uses src/ as the root, so we import from there.
// This file is referenced from build.zig.

test {
    _ = @import("core_test.zig");
}
