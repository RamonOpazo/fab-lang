//! Tests for the format pass: Style.zig, Formatter.zig and Sheet.zig.

const std = @import("std");
const testing = std.testing;
const Compilation = @import("../compile/Compilation.zig");
const Style = @import("Style.zig");
const Sheet = @import("Sheet.zig");
const Attrs = Style.Attrs;

const preview: Compilation.Tolerance = .{ .warnings = .warn, .ir = .keep };
const strict: Compilation.Tolerance = .{ .warnings = .promote, .ir = .withhold };

/// Compiles `source` and checks each node's label, italics, ink and shape.
const Expected = struct { []const u8, bool, ?Style.Color, Style.Shape };

fn expectNodes(source: []const u8, expected: []const Expected) !void {
    var c = try Compilation.init(testing.allocator, source, preview);
    defer c.deinit();
    const s = (try c.sheet()).?;
    try testing.expectEqual(expected.len, s.nodes.len);
    for (s.nodes, expected, 0..) |style, want, i| {
        const label, const italic, const ink, const shape = want;
        testing.expectEqualStrings(label, style.label) catch |err| {
            std.debug.print("node n{d}\n", .{i});
            return err;
        };
        try testing.expectEqual(italic, style.italic);
        try testing.expectEqual(ink, style.ink);
        try testing.expectEqual(shape, style.shape);
    }
}

const muted: ?Style.Color = .{ .token = .muted };

test "labels: a name without its #, else the canonical end, in the canonical class" {
    try expectNodes("G :: #A f #B g", &.{
        .{ "A", false, null, .circle },
        .{ "B", false, null, .circle },
        .{ "g+", true, muted, .circle },
    });
    try expectNodes("G :: f", &.{
        .{ "+f", true, muted, .circle },
        .{ "f+", true, muted, .circle },
    });
}

test "kind defaults: plain circles, and marks with no label, even when named" {
    // `(g, h)?` merges both branches' ends into one choice node.
    try expectNodes("G :: *f #Fork! (g, h)? #Pick k", &.{
        .{ "", false, null, .point },
        .{ "", false, null, .bar },
        .{ "", false, null, .diamond },
        .{ "k+", true, muted, .circle },
    });
}

test "a null node is a start if nothing arrives at it, else an end" {
    try expectNodes("G :: *f g*", &.{
        .{ "", false, null, .point },
        .{ "f+", true, muted, .circle },
        .{ "", false, null, .bullseye },
    });
}

test "holes are dashed circles, labelled by their canonical end if they have one" {
    var c = try Compilation.init(testing.allocator, "G :: f g/+k h\nDb :: Doc owner User", preview);
    defer c.deinit();
    const s = (try c.sheet()).?;
    // n1 is the hole that replaced `g/+k`, glued to f's codomain.
    try testing.expectEqualStrings("f+", s.nodes[1].label);
    try testing.expectEqual(Style.Shape.circle, s.nodes[1].shape);
    try testing.expectEqual(Style.Line.dashed, s.nodes[1].line);
    // In Db, the holes for Doc and User have no end of their own on one side.
    const doc = s.nodes[s.nodes.len - 2];
    try testing.expectEqualStrings("", doc.label);
    try testing.expectEqual(Style.Shape.circle, doc.shape);
}

test "edges and zones are labelled by name, and zones are unframed clusters by default" {
    var c = try Compilation.init(testing.allocator, "A :: f g\nB :: h/A.+f", preview);
    defer c.deinit();
    const s = (try c.sheet()).?;
    try testing.expectEqualStrings("f", s.edges[0].label);
    try testing.expectEqualStrings("h", s.edges[2].label);
    try testing.expect(!s.edges[0].italic);
    try testing.expectEqualStrings("A", s.zones[0].label);
    try testing.expectEqualStrings("B", s.zones[1].label);
    for ([_]u32{ 0, 1 }) |z| {
        try testing.expectEqual(Style.As.cluster, s.drawnAs(@fromBackingInt(z)));
        try testing.expect(!s.isFramed(@fromBackingInt(z)));
    }
    // The node B's edge reaches into keeps the label from the zone that owns it.
    try testing.expectEqualStrings("+f", s.nodes[0].label);
}

test "the sheet stage follows the IR: withheld with it, and computed once" {
    var withheld = try Compilation.init(testing.allocator, "G :: f g f", strict);
    defer withheld.deinit();
    try testing.expectEqual(@as(?*const Sheet, null), try withheld.sheet());

    var kept = try Compilation.init(testing.allocator, "G :: f g f", preview);
    defer kept.deinit();
    const first = (try kept.sheet()).?;
    try testing.expectEqual(first, (try kept.sheet()).?);
    try testing.expectEqual(@as(usize, 3), first.edges.len);
}

// ---------------------------------------------------------------------------
// The cascade is a monoid: `over` is associative, with `empty` as identity.

fn randomAttrs(r: std.Random) Attrs {
    const labels = [_][]const u8{ "a", "b" };
    const colors = [_]Style.Color{ .{ .rgb = 0xc0392b }, .{ .token = .muted } };
    var a: Attrs = .{};
    if (r.boolean()) a.label = labels[r.uintLessThan(usize, 2)];
    if (r.boolean()) a.italic = r.boolean();
    if (r.boolean()) a.ink = colors[r.uintLessThan(usize, 2)];
    if (r.boolean()) a.stroke = colors[r.uintLessThan(usize, 2)];
    if (r.boolean()) a.fill = colors[r.uintLessThan(usize, 2)];
    if (r.boolean()) a.line = if (r.boolean()) .dashed else .dotted;
    if (r.boolean()) a.shape = if (r.boolean()) .box else .diamond;
    if (r.boolean()) a.as = if (r.boolean()) .cluster else .node;
    return a;
}

test "over is associative, and empty is its identity" {
    var prng = std.Random.DefaultPrng.init(0xfab);
    const r = prng.random();
    for (0..5000) |_| {
        const a = randomAttrs(r);
        const b = randomAttrs(r);
        const c = randomAttrs(r);
        try testing.expect(std.meta.eql(a.over(b).over(c), a.over(b.over(c))));
        try testing.expect(std.meta.eql(Attrs.empty.over(a), a));
        try testing.expect(std.meta.eql(a.over(.empty), a));
    }
}

test "over: the later layer wins where it sets a value, and only there" {
    const base: Attrs = .{ .italic = true, .shape = .box, .ink = .{ .token = .muted } };
    const top: Attrs = .{ .shape = .diamond, .italic = false };
    const result = base.over(top);
    try testing.expectEqual(Style.Shape.diamond, result.shape.?);
    try testing.expectEqual(false, result.italic.?);
    try testing.expectEqual(Style.Color{ .token = .muted }, result.ink.?);
    try testing.expectEqual(@as(?Style.Color, null), result.stroke);
}

fn styleEverything(gpa: std.mem.Allocator) !void {
    var c = try Compilation.init(gpa, "G :: #A f? (g/+k, h) f\nH :: *x! y", preview);
    defer c.deinit();
    _ = try c.sheet();
}

test "running out of memory while styling leaks nothing" {
    try testing.checkAllAllocationFailures(testing.allocator, styleEverything, .{});
}
