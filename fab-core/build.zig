const std = @import("std");
const manifest = @import("build.zig.zon");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // The library: source in, IR out. No I/O.
    const fab_core_mod = b.addModule("fab_core", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    // The build's version (release.md §1), for the code:
    // `@import("build_options")`.
    const v = version(b);
    const options = b.addOptions();
    options.addOption([]const u8, "version", v.text);
    options.addOption(bool, "stable", v.stable);
    fab_core_mod.addOptions("build_options", options);

    const unit_tests = b.addTest(.{ .root_module = fab_core_mod });
    unit_tests.root_module.addAnonymousImport("examples", .{ .root_source_file = examples(b) });
    b.step("test", "Run all tests").dependOn(&b.addRunArtifact(unit_tests).step);
}

const Version = struct {
    /// `0.1.0`, `0.1.0-dev.97+e3ee815`, `0.1.0-dev.97+e3ee815.dirty`, or
    /// `0.1.0-dev+unknown` without the repository. `.incomplete` is the
    /// code's to add: only it knows its unsupported tags.
    text: []const u8,
    /// A tagged commit, built clean: the only build that refuses
    /// unsupported constructs (statements.md §22.16).
    stable: bool,
};

/// The version worked towards (the manifest's), and what git says of the
/// tree: the last tag `vX.Y.Z`, the commits since it (since the first, while
/// there is none), the commit, and whether tracked files changed.
fn version(b: *std.Build) Version {
    const written = manifest.version;
    // Git's state is no file the configure cache can watch: a commit, or an
    // edit not yet staged, must still change the version. So the
    // configuration runs again at every build, which costs a few
    // milliseconds of git.
    b.graph.poisonCache();

    // The repository is fab-core's parent, named outright, so a fab-core
    // built elsewhere never reads another project's history.
    const repo = b.root.joinString(b.allocator, "..") catch @panic("OOM");
    const unknown: Version = .{ .text = b.fmt("{s}-dev+unknown", .{written}), .stable = false };

    if (git(b, repo, &.{ "describe", "--tags", "--match", "v*", "--long", "--dirty", "--abbrev=7" })) |described| {
        // `v0.1.0-12-gabc1234`, `v0.1.0-0-gabc1234-dirty`: the tag may hold
        // dashes itself, so it is read from the right.
        var rest = described;
        const dirty = std.mem.endsWith(u8, rest, "-dirty");
        if (dirty) rest = rest[0 .. rest.len - "-dirty".len];
        const g = std.mem.lastIndexOf(u8, rest, "-g") orelse return unknown;
        const hash = rest[g + 2 ..];
        rest = rest[0..g];
        const dash = std.mem.lastIndexOfScalar(u8, rest, '-') orelse return unknown;
        const count = rest[dash + 1 ..];
        const tag = rest[1..dash]; // without the `v`

        if (std.mem.eql(u8, count, "0") and !dirty) {
            if (!std.mem.eql(u8, tag, written)) {
                std.debug.print("error: commit tagged v{s}, but build.zig.zon's version is {s}\n", .{ tag, written });
                std.process.exit(1);
            }
            return .{ .text = written, .stable = true };
        }
        return dev(b, written, count, hash, dirty);
    }

    // No tag yet: the commits since the first, and the commit.
    const count = git(b, repo, &.{ "rev-list", "--count", "HEAD" }) orelse return unknown;
    var hash = git(b, repo, &.{ "describe", "--always", "--dirty", "--abbrev=7" }) orelse return unknown;
    const dirty = std.mem.endsWith(u8, hash, "-dirty");
    if (dirty) hash = hash[0 .. hash.len - "-dirty".len];
    return dev(b, written, count, hash, dirty);
}

fn dev(b: *std.Build, written: []const u8, count: []const u8, hash: []const u8, dirty: bool) Version {
    return .{
        .text = b.fmt("{s}-dev.{s}+{s}{s}", .{ written, count, hash, if (dirty) ".dirty" else "" }),
        .stable = false,
    };
}

/// `git args…` in `repo`'s own `.git`, its output trimmed; null when git is
/// missing, the repository is, or the command fails.
fn git(b: *std.Build, repo: []const u8, args: []const []const u8) ?[]const u8 {
    var argv: std.ArrayList([]const u8) = .empty;
    argv.appendSlice(b.allocator, &.{ "git", "-C", repo, "--git-dir=.git" }) catch @panic("OOM");
    argv.appendSlice(b.allocator, args) catch @panic("OOM");
    return switch (b.runFallible(argv.items, .{ .stderr_behavior = .ignore })) {
        .success => |out| std.mem.trim(u8, out, " \r\n"),
        .spawn_failed, .bad_exit_code, .crashed => null,
    };
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
