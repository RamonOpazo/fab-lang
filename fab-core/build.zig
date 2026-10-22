const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // The library: source in, IR out. No I/O.
    const fab_core_mod = b.addModule("fab_core", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    const test_step = b.step("test", "Run all tests");

    // 1. Unit tests: the `test` blocks inside src/.
    //    `zig test` only runs tests in a binary's root module, so the library
    //    needs a test binary of its own; importing it elsewhere doesn't run them.
    const unit_tests = b.addTest(.{
        .root_module = fab_core_mod,
    });
    test_step.dependOn(&b.addRunArtifact(unit_tests).step);

    // 2. Integration tests: test/main.zig, which uses the library only
    //    through its public API, as `fab_core`.
    const integration_mod = b.createModule(.{
        .root_source_file = b.path("test/main.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{.{ .name = "fab_core", .module = fab_core_mod }},
    });
    const integration_tests = b.addTest(.{
        .root_module = integration_mod,
    });
    test_step.dependOn(&b.addRunArtifact(integration_tests).step);
}
