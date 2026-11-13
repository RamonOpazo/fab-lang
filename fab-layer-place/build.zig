const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const fab_core = b.dependency("fab_core", .{ .target = target, .optimize = optimize }).module("fab_core");

    // The place layer's runtime: the analysis in, the Place out. No I/O.
    const fab_layer_place = b.addModule("fab_layer_place", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{.{ .name = "fab_core", .module = fab_core }},
    });

    const tests = b.addTest(.{ .root_module = fab_layer_place });
    b.step("test", "Run all tests").dependOn(&b.addRunArtifact(tests).step);
}
