const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const fab_core = b.dependency("fab_core", .{ .target = target, .optimize = optimize }).module("fab_core");

    // The library: a language server as messages in, messages out, over the
    // reader and writer it is given. No I/O: `fab lsp` (fab-cli) owns the
    // standard streams.
    const fab_lsp = b.addModule("fab_lsp", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{.{ .name = "fab_core", .module = fab_core }},
    });

    const tests = b.addTest(.{ .root_module = fab_lsp });
    b.step("test", "Run all tests").dependOn(&b.addRunArtifact(tests).step);
}
