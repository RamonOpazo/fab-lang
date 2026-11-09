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
    unit_tests.root_module.addAnonymousImport("examples", .{ .root_source_file = examples(b) });
    b.step("test", "Run all tests").dependOn(&b.addRunArtifact(unit_tests).step);
}

/// The repository's examples, for the tests that read every one:
/// `@import("examples").all`, each a name and its source, in name order.
/// None when fab-core is built outside the repository.
fn examples(b: *std.Build) std.Build.LazyPath {
    const io = b.graph.io;
    const files = b.addWriteFiles();
    var names: std.ArrayList([]const u8) = .empty;
    b.dependOnDirectoryContents(b.path("../examples"));
    if (b.root.openDir(io, "../examples", .{ .iterate = true })) |opened| {
        var dir = opened;
        defer dir.close(io);
        var it = dir.iterate();
        while (it.next(io) catch null) |entry| {
            if (entry.kind == .file and std.mem.endsWith(u8, entry.name, ".fab"))
                names.append(b.allocator, b.dupe(entry.name)) catch @panic("OOM");
        }
    } else |_| {}
    std.mem.sort([]const u8, names.items, {}, struct {
        fn lessThan(_: void, l: []const u8, r: []const u8) bool {
            return std.mem.lessThan(u8, l, r);
        }
    }.lessThan);

    var list: std.Io.Writer.Allocating = .init(b.allocator);
    const w = &list.writer;
    w.writeAll("pub const all = [_]struct { []const u8, [:0]const u8 }{\n") catch @panic("OOM");
    for (names.items) |name| {
        _ = files.addCopyFile(b.path(b.fmt("../examples/{s}", .{name})), name);
        w.print("    .{{ \"{s}\", @embedFile(\"{s}\") }},\n", .{ name, name }) catch @panic("OOM");
    }
    w.writeAll("};\n") catch @panic("OOM");
    return files.add("examples.zig", list.written());
}
