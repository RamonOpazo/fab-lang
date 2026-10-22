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

    const unit_tests = b.addTest(.{ .root_module = fab_core_mod });
    b.step("test", "Run all tests").dependOn(&b.addRunArtifact(unit_tests).step);
}
