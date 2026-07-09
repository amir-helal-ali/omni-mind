// build.zig — Project Omni-Mind build system
// Builds the Zig core as executable, static library, and benchmark.

const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{
        .preferred_optimize_mode = .ReleaseFast,
    });

    // ─── Main executable: omni-mind ──────────────────────────
    const exe = b.addExecutable(.{
        .name = "omni-mind",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .strip = optimize != .Debug,
    });
    exe.linkLibC();
    b.installArtifact(exe);

    // ─── Run step ────────────────────────────────────────────
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| run_cmd.addArgs(args);
    const run_step = b.step("run", "Run the omni-mind server");
    run_step.dependOn(&run_cmd.step);

    // ─── Static library: libomni_core.a ──────────────────────
    // Linked into the Rust swarm crate via FFI.
    const lib = b.addStaticLibrary(.{
        .name = "omni_core",
        .root_source_file = b.path("src/ffi.zig"),
        .target = target,
        .optimize = optimize,
        .single_threaded = true,
    });
    lib.linkLibC();
    lib.root_module.stack_check = false;
    b.installArtifact(lib);

    // ─── Tests ───────────────────────────────────────────────
    const tests = b.addTest(.{
        .root_source_file = b.path("src/core_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    tests.linkLibC();
    const run_tests = b.addRunArtifact(tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_tests.step);

    // ─── Bench step ──────────────────────────────────────────
    const bench = b.addExecutable(.{
        .name = "omni-bench",
        .root_source_file = b.path("src/bench.zig"),
        .target = target,
        .optimize = optimize,
    });
    bench.linkLibC();
    b.installArtifact(bench);

    const run_bench = b.addRunArtifact(bench);
    run_bench.step.dependOn(b.getInstallStep());
    const bench_step = b.step("bench", "Run performance benchmarks");
    bench_step.dependOn(&run_bench.step);

    // ─── Native verify step (pure Zig, no Python) ───────────
    // Runs the 1000-question benchmark using actual Zig code paths.
    const verify = b.addExecutable(.{
        .name = "omni-verify",
        .root_source_file = b.path("src/verify.zig"),
        .target = target,
        .optimize = optimize,
    });
    verify.linkLibC();
    b.installArtifact(verify);

    const run_verify = b.addRunArtifact(verify);
    run_verify.step.dependOn(b.getInstallStep());
    const verify_step = b.step("verify", "Native Zig verification of 1000 questions (no Python)");
    verify_step.dependOn(&run_verify.step);
}

