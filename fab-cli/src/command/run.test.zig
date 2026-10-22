//! Tests for run.zig.

const std = @import("std");
const testing = std.testing;
const Args = @import("Args.zig");
const run = @import("run.zig");

const Result = struct {
    code: u8,
    produced: bool,
    graphviz: ?Args.Command.Format,
    out: []u8,
    err: []u8,

    fn deinit(r: Result) void {
        testing.allocator.free(r.out);
        testing.allocator.free(r.err);
    }
};

fn runArgs(args: []const []const u8, source: []const u8) !Result {
    const command = Args.parse(args).command;
    var out: std.Io.Writer.Allocating = .init(testing.allocator);
    errdefer out.deinit();
    var err: std.Io.Writer.Allocating = .init(testing.allocator);
    errdefer err.deinit();
    const outcome = try run.run(testing.allocator, command, source, "x.fab", &out.writer, &err.writer);
    return .{
        .code = outcome.code,
        .produced = outcome.produced,
        .graphviz = outcome.graphviz,
        .out = try out.toOwnedSlice(),
        .err = try err.toOwnedSlice(),
    };
}

test "check: exit code 0 without errors, 1 with" {
    const ok = try runArgs(&.{ "check", "x.fab", "--no-color" }, "G :: f g");
    defer ok.deinit();
    try testing.expectEqual(@as(u8, 0), ok.code);
    try testing.expectEqualStrings("", ok.err);

    const bad = try runArgs(&.{ "check", "x.fab", "--no-color" }, "G :: f g f");
    defer bad.deinit();
    try testing.expectEqual(@as(u8, 1), bad.code);
    try testing.expect(std.mem.startsWith(u8, bad.err, "error: Edge `f` is declared twice\n --> x.fab:1:10\n"));
    try testing.expect(std.mem.endsWith(u8, bad.err, "1 error\n"));
}

test "render to JSON: produced even with errors, unless strict" {
    const kept = try runArgs(&.{ "render", "x.fab", "-o", "x.json", "--no-color" }, "G :: f g/+k h");
    defer kept.deinit();
    try testing.expectEqual(@as(u8, 1), kept.code);
    try testing.expect(kept.produced);
    try testing.expect(std.mem.indexOf(u8, kept.out, "\"kind\":\"hole\"") != null);

    const refused = try runArgs(&.{ "render", "x.fab", "-o", "x.json", "--strict", "--no-color" }, "G :: f g/+k h");
    defer refused.deinit();
    try testing.expectEqual(@as(u8, 1), refused.code);
    try testing.expect(!refused.produced);
    try testing.expectEqualStrings("", refused.out);

    const clean = try runArgs(&.{ "render", "x.fab", "-o", "x.json", "--strict" }, "G :: f g");
    defer clean.deinit();
    try testing.expectEqual(@as(u8, 0), clean.code);
    try testing.expect(clean.produced);
}

test "native, latex, preview and zones say they are not available yet" {
    for ([_][]const []const u8{
        &.{ "render", "x.fab" },
        &.{ "render", "x.fab", "-f", "tex" },
        &.{ "render", "x.fab", "--preview" },
        &.{ "render", "x.fab", "--zone", "G" },
    }) |args| {
        const r = try runArgs(args, "G :: f");
        defer r.deinit();
        try testing.expectEqual(@as(u8, 2), r.code);
        try testing.expect(!r.produced);
        try testing.expect(std.mem.indexOf(u8, r.err, "not available yet") != null);
    }
}

test "the native engine points to graphviz" {
    const r = try runArgs(&.{ "render", "x.fab" }, "G :: f");
    defer r.deinit();
    try testing.expect(std.mem.indexOf(u8, r.err, "the native engine is not available yet: try `-e graphviz`") != null);
}

test "render to DOT: written here, nothing left for Graphviz to do" {
    const r = try runArgs(&.{ "render", "x.fab", "-f", "dot" }, "G :: #A f");
    defer r.deinit();
    try testing.expectEqual(@as(u8, 0), r.code);
    try testing.expect(r.produced);
    try testing.expectEqual(@as(?Args.Command.Format, null), r.graphviz);
    try testing.expect(std.mem.startsWith(u8, r.out, "digraph {\n"));
    try testing.expect(std.mem.indexOf(u8, r.out, "n0 [label=\"A\"") != null);
    try testing.expectEqualStrings("", r.err);
}

test "render with graphviz to an image: DOT here, the image from the host" {
    const r = try runArgs(&.{ "render", "x.fab", "-e", "graphviz", "-o", "x.png" }, "G :: f");
    defer r.deinit();
    try testing.expectEqual(@as(?Args.Command.Format, .png), r.graphviz);
    try testing.expect(std.mem.startsWith(u8, r.out, "digraph {\n"));
}

test "render with graphviz: errors keep the drawing, unless strict" {
    const kept = try runArgs(&.{ "render", "x.fab", "-f", "dot", "--no-color" }, "G :: f g/+k h");
    defer kept.deinit();
    try testing.expectEqual(@as(u8, 1), kept.code);
    try testing.expect(kept.produced);
    try testing.expect(std.mem.indexOf(u8, kept.out, "style=\"dashed\"") != null);

    const refused = try runArgs(&.{ "render", "x.fab", "-f", "dot", "--strict", "--no-color" }, "G :: f g/+k h");
    defer refused.deinit();
    try testing.expect(!refused.produced);
    try testing.expectEqualStrings("", refused.out);
}

test "notes follow the diagnostics, and never change the exit code" {
    const brief = try runArgs(&.{ "render", "x.fab", "-f", "dot", "--no-color" }, "Iso :: f, +f/g/f+, [f α/β g]");
    defer brief.deinit();
    try testing.expectEqual(@as(u8, 0), brief.code);
    try testing.expectEqualStrings("note: cells are not drawn by the graphviz engine (×2)\n", brief.err);

    const full = try runArgs(&.{ "render", "x.fab", "-f", "dot", "--no-color", "--verbosity", "full" }, "Iso :: f, +f/g/f+, [f α/β g]");
    defer full.deinit();
    try testing.expectEqualStrings(
        \\note: cells are not drawn by the graphviz engine (cell 0)
        \\note: cells are not drawn by the graphviz engine (cell 1)
        \\
    , full.err);

    const quiet = try runArgs(&.{ "render", "x.fab", "-f", "dot", "--verbosity", "quiet" }, "Iso :: f, +f/g/f+, [f α/β g]");
    defer quiet.deinit();
    try testing.expectEqualStrings("", quiet.err);
}

test "show cst reports syntax errors only" {
    const r = try runArgs(&.{ "show", "cst", "x.fab", "--no-color" }, "G :: f /g\nH :: x/+k");
    defer r.deinit();
    try testing.expectEqual(@as(u8, 1), r.code);
    try testing.expect(std.mem.indexOf(u8, r.err, "touches only what follows it") != null);
    try testing.expect(std.mem.indexOf(u8, r.err, "not declared") == null);
    try testing.expect(std.mem.startsWith(u8, r.out, "root\n"));
}

test "show tokens and ir" {
    const tokens = try runArgs(&.{ "show", "tokens", "x.fab" }, "f/g");
    defer tokens.deinit();
    try testing.expectEqualStrings(
        \\1:1      edge_id      f
        \\1:2      slash        /
        \\1:3      edge_id      g
        \\1:4      eof
        \\
    , tokens.out);

    const ir = try runArgs(&.{ "show", "ir", "x.fab" }, "G :: f");
    defer ir.deinit();
    try testing.expectEqualStrings("zone G\n  node n0 canon +f\n  node n1 canon f+\n  edge f n0 -> n1\n", ir.out);
}

test "output paths" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const path = struct {
        fn of(al: std.mem.Allocator, args: []const []const u8) !?[]const u8 {
            return run.outputPath(al, Args.parse(args).command);
        }
    }.of;
    try testing.expectEqualStrings("dir/order.svg", (try path(a, &.{ "render", "dir/order.fab" })).?);
    try testing.expectEqualStrings("order.json", (try path(a, &.{ "render", "order.fab", "-f", "json" })).?);
    try testing.expectEqualStrings("order.dot", (try path(a, &.{ "render", "order.fab", "-f", "dot" })).?);
    try testing.expectEqualStrings("order.pdf", (try path(a, &.{ "render", "order.fab", "-e", "latex" })).?);
    try testing.expectEqualStrings("out.png", (try path(a, &.{ "render", "order.fab", "-e", "graphviz", "-o", "out.png" })).?);
    try testing.expectEqual(@as(?[]const u8, null), try path(a, &.{ "render", "order.fab", "-o", "-" }));
    try testing.expectEqual(@as(?[]const u8, null), try path(a, &.{ "render", "-" }));
    try testing.expectEqualStrings("README.svg", (try path(a, &.{ "render", "README" })).?);
}
