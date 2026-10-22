const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // fab_render depends on fab_core too. Both ask for it with the same
    // options, so the build system gives them the same instance: one module.
    const fab_core = b.dependency("fab_core", .{ .target = target, .optimize = optimize }).module("fab_core");
    const fab_render = b.dependency("fab_render", .{ .target = target, .optimize = optimize }).module("fab_render");

    // The pure part: command line, running, reporting. No I/O.
    const fab_cli = b.createModule(.{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "fab_core", .module = fab_core },
            .{ .name = "fab_render", .module = fab_render },
        },
    });

    // The executable: the I/O shell around fab_cli.
    const exe = b.addExecutable(.{
        .name = "fab",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "fab_core", .module = fab_core },
                .{ .name = "fab_cli", .module = fab_cli },
            },
        }),
    });
    b.installArtifact(exe);

    // `zig build run -- check x.fab` passes everything after `--` to fab.
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    run_cmd.addPassthruArgs();
    b.step("run", "Run fab").dependOn(&run_cmd.step);

    // Tests are rooted at root.zig, as in fab-core. The step also compiles the
    // executable, so a break in main.zig fails `zig build test` too.
    const test_step = b.step("test", "Run all tests");
    const tests = b.addTest(.{ .root_module = fab_cli });
    test_step.dependOn(&b.addRunArtifact(tests).step);
    test_step.dependOn(&exe.step);
}
