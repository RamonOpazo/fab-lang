//! Tests for the style pass: Style.zig, Styler.zig and Sheet.zig.

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
    try expectNodes("G :: #A/f #B/g", &.{
        .{ "A", false, null, .circle },
        .{ "B", false, null, .circle },
        .{ "g+", true, muted, .circle },
    });
    try expectNodes("G :: f", &.{
        .{ "+f", true, muted, .circle },
        .{ "f+", true, muted, .circle },
    });
}

test "kind defaults: plain circles, and marks with no label" {
    // A start, a fork after f, the join of g and h, and a choice after k.
    try expectNodes("G :: */f/! +(g, h)+ k/?", &.{
        .{ "", false, null, .point },
        .{ "", false, null, .bar },
        .{ "g+", true, muted, .circle },
        .{ "", false, null, .diamond },
    });
}

test "a null node is a start if nothing arrives at it, else an end" {
    try expectNodes("G :: */f g/*", &.{
        .{ "", false, null, .point },
        .{ "f+", true, muted, .circle },
        .{ "", false, null, .bullseye },
    });
}

test "the own node is labelled with its diagram's name" {
    try expectNodes("T :: #UUID7\nUser :: @/id/T.#UUID7", &.{
        .{ "UUID7", false, null, .circle },
        .{ "User", false, null, .circle },
    });
}

test "holes are dashed circles, labelled by their canonical end" {
    var c = try Compilation.init(testing.allocator, "G :: f g/+k h\nDb :: Doc/owner/User", preview);
    defer c.deinit();
    const s = (try c.sheet()).?;
    // n2 is the hole that replaced `+k`, glued to g's codomain.
    try testing.expectEqualStrings("g+", s.nodes[2].label);
    try testing.expectEqual(Style.Shape.circle, s.nodes[2].shape);
    try testing.expectEqual(Style.Line.dashed, s.nodes[2].line);
    // In Db, the holes for Doc and User take owner's ends, which created them.
    const doc = s.nodes[s.nodes.len - 2];
    try testing.expectEqualStrings("+owner", doc.label);
    try testing.expectEqual(Style.Line.dashed, doc.line);
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
    // The second f is a hole, not an edge.
    try testing.expectEqual(@as(usize, 2), first.edges.len);
}

// ---------------------------------------------------------------------------
// Marks: the last layer (statements.md §15.3, §18)

const red: ?Style.Color = .{ .token = .@"error" };
const amber: ?Style.Color = .{ .token = .warning };
const violet: ?Style.Color = .{ .token = .unsupported };

test "marks win: a hole keeps its dashes, in its error's colour, and frames its diagram" {
    var c = try Compilation.init(testing.allocator, "G :: f g/+k h\nH :: f", preview);
    defer c.deinit();
    const s = (try c.sheet()).?;
    try testing.expectEqual(red, s.nodes[2].stroke);
    try testing.expectEqual(Style.Line.dashed, s.nodes[2].line);
    try testing.expectEqual(@as(?Style.Color, null), s.nodes[1].stroke);
    try testing.expectEqual(@as(?Style.Color, null), s.edges[1].stroke);
    // G is framed in red; H, clean, stays unframed.
    try testing.expectEqual(red, s.zones[0].stroke);
    try testing.expect(s.isFramed(@fromBackingInt(@as(u32, 0))));
    try testing.expect(!s.isFramed(@fromBackingInt(@as(u32, 1))));
    try testing.expectEqual(@as(?Style.Caption, null), s.zones[0].caption);
}

test "a diagram's frame is its worst issue; unsupported adds the caption, even under red" {
    var c = try Compilation.init(testing.allocator,
        \\K :: (f/*, g) h
        \\J :: f
        \\J :style { f :label "x" }
        \\G :: f g/+k h
        \\G :style { f :label "x" }
    , preview);
    defer c.deinit();
    const s = (try c.sheet()).?;
    try testing.expectEqual(amber, s.zones[0].stroke);
    try testing.expectEqual(@as(?Style.Caption, null), s.zones[0].caption);
    try testing.expectEqual(violet, s.zones[1].stroke);
    try testing.expectEqualStrings("unsupported", s.zones[1].caption.?.text);
    try testing.expectEqual(violet.?, s.zones[1].caption.?.ink);
    try testing.expectEqual(red, s.zones[2].stroke);
    try testing.expectEqualStrings("unsupported", s.zones[2].caption.?.text);
}

test "a promoted warning is drawn as an error" {
    var c = try Compilation.init(testing.allocator, "K :: (f/*, g) h", .{ .warnings = .promote, .ir = .keep });
    defer c.deinit();
    try testing.expectEqual(red, (try c.sheet()).?.zones[0].stroke);
}

test "a placeholder is drawn as one, framed by its error" {
    var c = try Compilation.init(testing.allocator, "G :: f\nH :: g /k", preview);
    defer c.deinit();
    const s = (try c.sheet()).?;
    try testing.expectEqual(Style.As.cluster, s.drawnAs(@fromBackingInt(@as(u32, 0))));
    try testing.expectEqual(Style.As.placeholder, s.drawnAs(@fromBackingInt(@as(u32, 1))));
    try testing.expectEqual(red, s.zones[1].stroke);
}

test "a marked edge takes the colour; a solid shape's fill follows its line" {
    // No analysis error marks an edge yet, so the IR is made by hand.
    const Ir = @import("../analyse/Ir.zig");
    const Styler = @import("Styler.zig");
    var b: Ir.Builder = .init(testing.allocator);
    errdefer b.deinit();
    const z = try b.addZone(.{ .name = try b.addString("G"), .own = null });
    const start = try b.addNode(.{ .kind = .null_node, .name = null, .zone = z, .canonical = null });
    const end = try b.addNode(.{ .kind = .plain, .name = null, .zone = z, .canonical = .{ .edge = @fromBackingInt(@as(u32, 0)), .side = .cod } });
    const f = try b.addEdge(.{ .name = try b.addString("f"), .source = start, .target = end, .directed = true, .zone = z });
    try b.addIssue(.{ .subject = .{ .edge = f }, .err = .{ .analysis = 0 } });
    try b.addIssue(.{ .subject = .{ .node = start }, .err = .{ .analysis = 1 } });
    try b.addIssue(.{ .subject = .{ .node = end }, .err = .{ .analysis = 2 } });
    var ir = try b.finish();
    defer ir.deinit(testing.allocator);

    var s = try Styler.style(testing.allocator, &ir, &.{ .warning, .unsupported, .@"error" });
    defer s.deinit();
    try testing.expectEqual(amber, s.edges[0].stroke);
    // The start is a dot: its fill is its line.
    try testing.expectEqual(violet, s.nodes[0].stroke);
    try testing.expectEqual(violet, s.nodes[0].fill);
    // A circle keeps its fill.
    try testing.expectEqual(red, s.nodes[1].stroke);
    try testing.expectEqual(@as(?Style.Color, null), s.nodes[1].fill);
    try testing.expectEqual(red, s.zones[0].stroke);
    try testing.expectEqualStrings("unsupported", s.zones[0].caption.?.text);
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
    // In-place growth makes the count of allocations drift from run to run.
    var fixed: @import("../compile/compilation.test.zig").FixedInPlace = .{ .backing = testing.allocator };
    try testing.checkAllAllocationFailures(fixed.allocator(), styleEverything, .{});
}
