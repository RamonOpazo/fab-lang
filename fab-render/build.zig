const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const fab_core = b.dependency("fab_core", .{ .target = target, .optimize = optimize }).module("fab_core");

    // The library: pure functions from a Sheet to bytes. No I/O.
    const fab_render = b.addModule("fab_render", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{.{ .name = "fab_core", .module = fab_core }},
    });

    const tests = b.addTest(.{ .root_module = fab_render });
    b.step("test", "Run all tests").dependOn(&b.addRunArtifact(tests).step);
}
