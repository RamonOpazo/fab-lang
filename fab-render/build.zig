const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // The layers depend on fab_core too; asked with the same options, the
    // build system gives all of them the same instance.
    const fab_core = b.dependency("fab_core", .{ .target = target, .optimize = optimize }).module("fab_core");
    const fab_layer_style = b.dependency("fab_layer_style", .{ .target = target, .optimize = optimize }).module("fab_layer_style");
    const fab_layer_place = b.dependency("fab_layer_place", .{ .target = target, .optimize = optimize }).module("fab_layer_place");

    // The library: pure functions from the analysis, styled, to bytes. No I/O.
    const fab_render = b.addModule("fab_render", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "fab_core", .module = fab_core },
            .{ .name = "fab_layer_style", .module = fab_layer_style },
            .{ .name = "fab_layer_place", .module = fab_layer_place },
        },
    });

    const tests = b.addTest(.{ .root_module = fab_render });
    b.step("test", "Run all tests").dependOn(&b.addRunArtifact(tests).step);
}
