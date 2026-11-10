//! Tests for the style pass: Styler.zig, cascade.zig and Sheet.zig.

const std = @import("std");
const testing = std.testing;
const Compilation = @import("../compile/Compilation.zig");
const Sheet = @import("Sheet.zig");

const preview: Compilation.Tolerance = .{ .warnings = .warn, .ir = .keep };
const strict: Compilation.Tolerance = .{ .warnings = .promote, .ir = .withhold };

/// What these tests check of a style, read by descriptor as a renderer
/// reads it.
const Look = struct {
    label: []const u8,
    italic: bool,
    ink: ?u24,
    stroke: ?u24,
    fill: ?u24,
    /// Labels by name; "" for nil.
    shape: []const u8,
    line: []const u8,
    as: []const u8,
    caption: ?[]const u8,
};

fn look(s: *const Sheet, subject: Sheet.Subject) Look {
    const v = s.style(subject);
    const Read = struct {
        fn colour(view: Sheet.View, sheet: *const Sheet, name: []const u8) ?u24 {
            const c = view.color(sheet.descriptor(name) orelse return null) orelse return null;
            return (@as(u24, c.r) << 16) | (@as(u24, c.g) << 8) | c.b;
        }
        fn label(view: Sheet.View, sheet: *const Sheet, name: []const u8) []const u8 {
            const x = view.get(sheet.descriptor(name) orelse return "") orelse return "";
            return if (x == .label) x.label.name else "";
        }
    };
    const face = Read.label(v, s, ":face");
    return .{
        .label = v.text(s.descriptor(":label").?) orelse "",
        .italic = std.mem.eql(u8, face, "italic") or std.mem.eql(u8, face, "bold-italic"),
        .ink = Read.colour(v, s, ":ink"),
        .stroke = Read.colour(v, s, ":stroke"),
        .fill = Read.colour(v, s, ":fill"),
        .shape = Read.label(v, s, ":shape"),
        .line = Read.label(v, s, ":line"),
        .as = Read.label(v, s, ":as"),
        .caption = v.text(s.descriptor(":caption").?),
    };
}

fn nodeAt(i: u32) Sheet.Subject {
    return .{ .node = @fromBackingInt(i) };
}
fn edgeAt(i: u32) Sheet.Subject {
    return .{ .edge = @fromBackingInt(i) };
}
fn zoneAt(i: u32) Sheet.Subject {
    return .{ .zone = @fromBackingInt(i) };
}

/// Compiles `source` and checks each node's label, italics, ink and shape.
const Expected = struct { []const u8, bool, ?u24, []const u8 };

fn expectNodes(source: []const u8, expected: []const Expected) !void {
    var c = try Compilation.init(testing.allocator, source, preview);
    defer c.deinit();
    const s = (try c.sheet()).?;
    try testing.expectEqual(expected.len, s.ir.nodes.len);
    for (expected, 0..) |want, i| {
        const got = look(s, nodeAt(@intCast(i)));
        const label, const italic, const want_ink, const shape = want;
        testing.expectEqualStrings(label, got.label) catch |err| {
            std.debug.print("node n{d}\n", .{i});
            return err;
        };
        try testing.expectEqual(italic, got.italic);
        try testing.expectEqual(want_ink, got.ink);
        try testing.expectEqualStrings(shape, got.shape);
    }
}

// [base]'s tokens: `[ink]` and `[muted]`.
const ink: ?u24 = 0x333333;
const muted: ?u24 = 0x888888;

test "labels: a name without its #, else the canonical end, in the canonical class" {
    try expectNodes("G :: #A/f #B/g", &.{
        .{ "A", false, ink, "circle" },
        .{ "B", false, ink, "circle" },
        .{ "g+", true, muted, "circle" },
    });
    try expectNodes("G :: f", &.{
        .{ "+f", true, muted, "circle" },
        .{ "f+", true, muted, "circle" },
    });
}

test "kind defaults: plain circles, and marks with no label" {
    // A start, a fork after f, the join of g and h, and a choice after k.
    // Marks are labelled "", so not by their canonical end.
    try expectNodes("G :: */f/! +(g, h)+ k/?", &.{
        .{ "", false, ink, "point" },
        .{ "", false, ink, "bar" },
        .{ "g+", true, muted, "circle" },
        .{ "", false, ink, "diamond" },
    });
    // `&choice :label []` gives a choice its name back, and so its class.
    try expectNodes("G :: k/?\nG :style { &choice :label [] }", &.{
        .{ "+k", true, muted, "circle" },
        .{ "k+", true, muted, "diamond" },
    });
}

test "a null node is a start if nothing arrives at it, else an end" {
    try expectNodes("G :: */f g/*", &.{
        .{ "", false, ink, "point" },
        .{ "f+", true, muted, "circle" },
        .{ "", false, ink, "bullseye" },
    });
}

test "a diagram's node is labelled with its diagram's name" {
    try expectNodes("A :: f\nDb :: A/g", &.{
        .{ "+f", true, muted, "circle" },
        .{ "f+", true, muted, "circle" },
        .{ "A", false, ink, "circle" },
        .{ "g+", true, muted, "circle" },
    });
}

test "holes are dashed circles, labelled by their canonical end" {
    var c = try Compilation.init(testing.allocator, "G :: f g/+k h\nDb :: Doc/owner/User", preview);
    defer c.deinit();
    const s = (try c.sheet()).?;
    // n2 is the hole that replaced `+k`, glued to g's codomain.
    const hole = look(s, nodeAt(2));
    try testing.expectEqualStrings("g+", hole.label);
    try testing.expectEqualStrings("circle", hole.shape);
    try testing.expectEqualStrings("dashed", hole.line);
    // In Db, the holes for Doc and User take owner's ends, which created them.
    const doc = look(s, nodeAt(@intCast(s.ir.nodes.len - 2)));
    try testing.expectEqualStrings("+owner", doc.label);
    try testing.expectEqualStrings("dashed", doc.line);
}

test "edges and zones are labelled by name, and zones are unframed clusters by default" {
    var c = try Compilation.init(testing.allocator, "A :: f g\nB :: h/A.+f", preview);
    defer c.deinit();
    const s = (try c.sheet()).?;
    try testing.expectEqualStrings("f", look(s, edgeAt(0)).label);
    try testing.expectEqualStrings("h", look(s, edgeAt(2)).label);
    try testing.expect(!look(s, edgeAt(0)).italic);
    for ([_]u32{ 0, 1 }, [_][]const u8{ "A", "B" }) |z, name| {
        const l = look(s, zoneAt(z));
        try testing.expectEqualStrings(name, l.label);
        try testing.expectEqualStrings("cluster", l.as);
        // Unframed: no stroke, no fill.
        try testing.expectEqual(@as(?u24, null), l.stroke);
        try testing.expectEqual(@as(?u24, null), l.fill);
    }
    // The node B's edge reaches into keeps the label from the zone that owns it.
    try testing.expectEqualStrings("+f", look(s, nodeAt(0)).label);
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
    try testing.expectEqual(@as(usize, 2), first.elements.edges.len);
}

// ---------------------------------------------------------------------------
// Marks: the last layer (statements.md §15.3, §18)

// [base]'s `[error]`, `[warning]` and `[unsupported]`.
const red: ?u24 = 0xd1242f;
const amber: ?u24 = 0xbf8700;
const violet: ?u24 = 0x8250df;

test "marks win: a hole keeps its dashes, in its error's colour, and frames its diagram" {
    var c = try Compilation.init(testing.allocator, "G :: f g/+k h\nH :: f", preview);
    defer c.deinit();
    const s = (try c.sheet()).?;
    try testing.expectEqual(red, look(s, nodeAt(2)).stroke);
    try testing.expectEqualStrings("dashed", look(s, nodeAt(2)).line);
    try testing.expectEqual(ink, look(s, nodeAt(1)).stroke);
    try testing.expectEqual(ink, look(s, edgeAt(1)).stroke);
    // G is framed in red; H, clean, stays unframed.
    try testing.expectEqual(red, look(s, zoneAt(0)).stroke);
    try testing.expectEqual(@as(?u24, null), look(s, zoneAt(1)).stroke);
    try testing.expectEqual(@as(?[]const u8, null), look(s, zoneAt(0)).caption);
    // The layer says it was a mark.
    try testing.expectEqual(Sheet.Layer.mark, s.style(zoneAt(0)).entry(s.descriptor(":stroke").?).?.layer);
}

test "a diagram's frame is its worst issue; unsupported adds the caption, even under red" {
    var c = try Compilation.init(testing.allocator,
        \\K :: (f/*, g) h
        \\J :: f
        \\J :prove { :kind [category] }
        \\G :: f g/+k h
        \\G :prove { :kind [category] }
    , preview);
    defer c.deinit();
    const s = (try c.sheet()).?;
    try testing.expectEqual(amber, look(s, zoneAt(0)).stroke);
    try testing.expectEqual(@as(?[]const u8, null), look(s, zoneAt(0)).caption);
    try testing.expectEqual(violet, look(s, zoneAt(1)).stroke);
    try testing.expectEqualStrings("unsupported", look(s, zoneAt(1)).caption.?);
    try testing.expectEqual(red, look(s, zoneAt(2)).stroke);
    try testing.expectEqualStrings("unsupported", look(s, zoneAt(2)).caption.?);
    // The caption's colour, a renderer's to read from the diagram's tokens.
    try testing.expectEqual(@as(u8, 0x82), s.token(@fromBackingInt(@as(u32, 2)), "unsupported").?.color.r);
}

test "a promoted warning is drawn as an error" {
    var c = try Compilation.init(testing.allocator, "K :: (f/*, g) h", .{ .warnings = .promote, .ir = .keep });
    defer c.deinit();
    try testing.expectEqual(red, look((try c.sheet()).?, zoneAt(0)).stroke);
}

test "a placeholder is framed by its error" {
    var c = try Compilation.init(testing.allocator, "G :: f\nH :: g /k", preview);
    defer c.deinit();
    const s = (try c.sheet()).?;
    try testing.expect(s.ir.zones.items(.placeholder)[1]);
    try testing.expectEqual(red, look(s, zoneAt(1)).stroke);
}

test "a marked edge takes the colour; a solid shape's fill follows its line" {
    // No analysis error marks an edge yet, so the IR is made by hand.
    const Ir = @import("../analyse/Ir.zig");
    const Styler = @import("Styler.zig");
    var b: Ir.Builder = .init(testing.allocator);
    errdefer b.deinit();
    const z = try b.addZone(.{ .name = try b.addString("G") });
    const start = try b.addNode(.{ .kind = .null_node, .name = null, .zone = z, .canonical = null });
    const end = try b.addNode(.{ .kind = .plain, .name = null, .zone = z, .canonical = .{ .edge = @fromBackingInt(@as(u32, 0)), .side = .cod } });
    const f = try b.addEdge(.{ .name = try b.addString("f"), .source = start, .target = end, .directed = true, .zone = z });
    try b.addIssue(.{ .subject = .{ .edge = f }, .err = .{ .analysis = 0 } });
    try b.addIssue(.{ .subject = .{ .node = start }, .err = .{ .analysis = 1 } });
    try b.addIssue(.{ .subject = .{ .node = end }, .err = .{ .analysis = 2 } });
    var ir = try b.finish();
    defer ir.deinit(testing.allocator);

    // The prelude's environment, from an empty program.
    var c = try Compilation.init(testing.allocator, "", preview);
    defer c.deinit();
    var s = try Styler.style(testing.allocator, &ir, .{ .env = &(try c.analysis()).env }, &.{ .warning, .unsupported, .@"error" });
    defer s.deinit();
    try testing.expectEqual(amber, look(&s, edgeAt(0)).stroke);
    // The start is a dot: its fill is its line.
    try testing.expectEqual(violet, look(&s, nodeAt(0)).stroke);
    try testing.expectEqual(violet, look(&s, nodeAt(0)).fill);
    // A circle keeps its fill.
    try testing.expectEqual(red, look(&s, nodeAt(1)).stroke);
    try testing.expectEqual(@as(?u24, null), look(&s, nodeAt(1)).fill);
    try testing.expectEqual(red, look(&s, zoneAt(0)).stroke);
    try testing.expectEqualStrings("unsupported", look(&s, zoneAt(0)).caption.?);
}

test "every rule is an element's or a parent; :theme is no element's style" {
    var c = try Compilation.init(testing.allocator, "G :: f/? +(a, b)\nG :style { :theme [dark] }", preview);
    defer c.deinit();
    const s = (try c.sheet()).?;
    for (s.rules, 0..) |_, r| {
        var named = false;
        for (s.elements.nodes) |e| named = named or @backingInt(e.rule) == r;
        for (s.elements.edges) |e| named = named or @backingInt(e.rule) == r;
        for (s.elements.zones) |e| named = named or @backingInt(e.rule) == r;
        for (s.rules) |other| named = named or (other.parent != null and @backingInt(other.parent.?) == r);
        try testing.expect(named);
    }
    try testing.expectEqual(@as(?@import("../analyse/decoded.zig").Value, null), s.style(zoneAt(0)).get(s.descriptor(":theme").?));
}

/// The rule `subject` names.
fn ruleOf(s: *const Sheet, subject: Sheet.Subject) Sheet.Rule {
    return s.rule(s.element(subject).rule);
}

test "an unstyled program is its base rules, shared by every diagram" {
    var c = try Compilation.init(testing.allocator, "G :: #A/f\nH :: #B/g", preview);
    defer c.deinit();
    const s = (try c.sheet()).?;
    // One per set of classes: the zones, the named nodes, the canonical
    // ones (`f+`), the edges.
    try testing.expectEqual(4, s.rules.len);
    for (s.rules) |r| {
        try testing.expectEqual(null, r.zone);
        try testing.expectEqual(null, r.parent);
    }
    try testing.expectEqual(s.element(nodeAt(0)).rule, s.element(nodeAt(2)).rule);
    try testing.expectEqual(s.element(zoneAt(0)).rule, s.element(zoneAt(1)).rule);
}

test "a diagram rule holds what differs from its base rule, by value or by layer" {
    var c = try Compilation.init(testing.allocator,
        \\G :: #A/f
        \\H :: #B/g
        \\J :: #C/h
        \\G :style { [ink] := [#000000] }
        \\H :style { &edge :size [0.85] }
    , preview);
    defer c.deinit();
    const s = (try c.sheet()).?;
    const ink_of = s.descriptor(":ink").?;
    const size = s.descriptor(":size").?;

    // G rebinds a token: every entry written [ink] changes, the rest is the
    // base rule's.
    const g = ruleOf(s, nodeAt(0));
    try testing.expectEqual(0, @backingInt(g.zone.?));
    const base = s.rule(g.parent.?);
    try testing.expectEqual(null, base.zone);
    for (s.slice(g.entries)) |e| try testing.expect(e.value == .color);
    try testing.expectEqual(0x000000, rgb(s.style(nodeAt(0)).color(ink_of).?));
    try testing.expectEqual(ink, rgb(s.style(nodeAt(4)).color(ink_of).?));

    // H binds [base]'s own value: kept, since the author bound it.
    const h = ruleOf(s, edgeAt(1));
    try testing.expectEqual(1, @backingInt(h.zone.?));
    const entries = s.slice(h.entries);
    try testing.expectEqual(1, entries.len);
    try testing.expectEqual(size, entries[0].descriptor);
    try testing.expectEqual(.program, entries[0].layer);
    // Its nodes change nothing: they name the base rule.
    try testing.expectEqual(null, ruleOf(s, nodeAt(2)).zone);

    // J is unstyled.
    try testing.expectEqual(null, ruleOf(s, nodeAt(4)).zone);
    try testing.expectEqual(null, ruleOf(s, edgeAt(2)).zone);
}

test "a theme makes a diagram rule; parents come first" {
    var c = try Compilation.init(testing.allocator, "G :: #A/f\nG :style { :theme [dark] }", preview);
    defer c.deinit();
    const s = (try c.sheet()).?;
    const r = ruleOf(s, nodeAt(0));
    try testing.expect(r.zone != null);
    for (s.slice(r.entries)) |e| try testing.expect(e.layer == .theme or e.value == .color);
    for (s.rules, 0..) |x, i| if (x.parent) |p| try testing.expect(@backingInt(p) < i);
}

fn rgb(c: @import("../analyse/value.zig").Rgba) u24 {
    return @as(u24, c.r) << 16 | @as(u24, c.g) << 8 | c.b;
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

/// A label's name, or "nil" when there is none.
fn labelName(v: Sheet.View, d: Sheet.Descriptor) []const u8 {
    return if (v.get(d)) |x| switch (x) {
        .label => |l| l.name,
        else => "not a label",
    } else "nil";
}

test "the Sheet of values: [base] folded by specificity into rules" {
    var c = try Compilation.init(testing.allocator, "G :: #A/f/? +(a, b), g/? +(c, d)", preview);
    defer c.deinit();
    const s = (try c.sheet()).?;
    const d = struct {
        fn of(sheet: *const Sheet, name: []const u8) !Sheet.Descriptor {
            return sheet.descriptor(name) orelse error.TestUnexpectedResult;
        }
    }.of;
    const shape = try d(s, ":shape");
    const face = try d(s, ":face");
    const label = try d(s, ":label");

    // #A, then f's and g's choices, unnamed: canonical.
    const named = s.style(.{ .node = @fromBackingInt(@as(u32, 0)) });
    try testing.expectEqualStrings("circle", labelName(named, shape));
    try testing.expectEqualStrings("regular", labelName(named, face));
    // Computed below [base]'s nil: the name without its #.
    try testing.expectEqualStrings("A", named.text(label).?);

    const choice = s.style(.{ .node = @fromBackingInt(@as(u32, 1)) });
    // &choice over &node; labelled "", so not &canonical.
    try testing.expectEqualStrings("diamond", labelName(choice, shape));
    try testing.expectEqualStrings("", choice.text(label).?);
    try testing.expectEqualStrings("regular", labelName(choice, face));
    // `[ink]`, a token, resolved to [base]'s colour.
    try testing.expectEqual(@import("../analyse/value.zig").Rgba{ .r = 0x33, .g = 0x33, .b = 0x33 }, choice.color(try d(s, ":ink")).?);

    // The two choices share one rule; #A has its own.
    var choices: usize = 0;
    var rule: ?Sheet.RuleIndex = null;
    for (s.ir.nodes.items(.kind), s.elements.nodes) |kind, e| if (kind == .choice) {
        choices += 1;
        if (rule) |r| try testing.expectEqual(r, e.rule) else rule = e.rule;
    };
    try testing.expectEqual(@as(usize, 2), choices);
    try testing.expect(s.elements.nodes[0].rule != rule.?);

    // An edge's arrow, a zone's `:as`.
    const edge = s.style(.{ .edge = @fromBackingInt(@as(u32, 0)) });
    const arrow = edge.get(try d(s, ":arrow")).?.elements;
    try testing.expectEqual(@as(usize, 3), arrow.len);
    try testing.expectEqual(@as(@import("../analyse/decoded.zig").Value, .nil), arrow[0]);
    const zone = s.style(.{ .zone = @fromBackingInt(@as(u32, 0)) });
    try testing.expectEqualStrings("cluster", labelName(zone, try d(s, ":as")));
}

test "a renderer reads labels as its own enum, and is told what it can't draw" {
    var c = try Compilation.init(testing.allocator, "G :: #A/f/? +(a, b)", preview);
    defer c.deinit();
    const s = (try c.sheet()).?;
    const Shape = enum { circle, diamond, double_circle };
    const shape = s.descriptor(":shape").?;
    const choice = s.style(.{ .node = @fromBackingInt(@as(u32, 1)) });
    try testing.expectEqual(Sheet.Label(Shape){ .value = .diamond }, choice.label(Shape, shape));
    // Nil is nothing there: `:fill []`.
    try testing.expectEqual(Sheet.Label(Shape).nil, choice.label(Shape, s.descriptor(":fill").?));
    const Point = enum { point };
    try testing.expectEqualStrings("diamond", choice.label(Point, shape).unknown);
}

test "the names core gives meaning to are :Style's descriptors" {
    var c = try Compilation.init(testing.allocator, "", preview);
    defer c.deinit();
    const s = (try c.sheet()).?;
    for ([_][]const u8{ ":label", ":arrow", ":theme", ":marks" }) |name| {
        if (s.descriptor(name) == null) {
            std.debug.print("not in :Style: {s}\n", .{name});
            return error.TestUnexpectedResult;
        }
    }
    // In declaration order, the prelude's first.
    try testing.expectEqualStrings(":label", s.descriptors[0]);
}

// ---------------------------------------------------------------------------
// The cascade (plan step 9d4): computed < [base] < themes < the program < marks

const Rgba = @import("../analyse/value.zig").Rgba;

fn rgba(hex: u24) Rgba {
    return .{ .r = @truncate(hex >> 16), .g = @truncate(hex >> 8), .b = @truncate(hex) };
}

/// The style of the node named `name`, `#` included.
fn nodeNamed(s: *const Sheet, name: []const u8) !Sheet.View {
    for (s.ir.nodes.items(.name), 0..) |n, i| if (n) |text| if (std.mem.eql(u8, s.ir.string(text), name))
        return s.style(.{ .node = @fromBackingInt(@as(u32, @intCast(i))) });
    return error.TestUnexpectedResult;
}

/// The style of the first node of `kind`.
fn firstOf(s: *const Sheet, kind: @import("../analyse/Ir.zig").Node.Kind) !Sheet.View {
    for (s.ir.nodes.items(.kind), 0..) |k, i| if (k == kind)
        return s.style(.{ .node = @fromBackingInt(@as(u32, @intCast(i))) });
    return error.TestUnexpectedResult;
}

fn zoneStyle(s: *const Sheet, z: u32) Sheet.View {
    return s.style(.{ .zone = @fromBackingInt(z) });
}

test "themes: left to right, a theme's own :theme included first, tokens through them" {
    var c = try Compilation.init(testing.allocator,
        \\:Style [warm] := { :theme [dark], &node :fill [#ffeeee], [soft] := [#ff0000] }
        \\G :: #A/f
        \\G :style { :theme [warm/compact] }
        \\H :: #B/g
    , preview);
    defer c.deinit();
    const s = (try c.sheet()).?;
    const a = try nodeNamed(s, "#A");
    try testing.expectEqual(rgba(0xffeeee), a.color(s.descriptor(":fill").?).?);
    // [dark]'s, included by [warm]: its tokens and its zone fill.
    try testing.expectEqual(rgba(0xdddddd), a.color(s.descriptor(":ink").?).?);
    try testing.expectEqual(rgba(0x1e1e1e), zoneStyle(s, 0).color(s.descriptor(":fill").?).?);
    // [warm] rebinds [soft] after [dark]: edge labels.
    try testing.expectEqual(rgba(0xff0000), s.style(.{ .edge = @fromBackingInt(@as(u32, 0)) }).color(s.descriptor(":ink").?).?);
    // [compact], after [warm].
    try testing.expectEqualStrings("0.2", try decimal(a.number(s.descriptor(":padding").?).?));
    // H has no theme: [base]'s.
    const b = try nodeNamed(s, "#B");
    try testing.expectEqual(rgba(0x333333), b.color(s.descriptor(":ink").?).?);
    try testing.expectEqual(@as(?Rgba, null), b.color(s.descriptor(":fill").?));
}

/// A number in its normal form, `0.2`.
fn decimal(d: @import("../analyse/Decimal.zig")) ![]const u8 {
    const State = struct {
        var buf: [32]u8 = undefined;
    };
    var w: std.Io.Writer = .fixed(&State.buf);
    try d.format(&w);
    return w.buffered();
}

test "the program's ranks: a top-level class, then a class in the diagram, then the element" {
    var c = try Compilation.init(testing.allocator,
        \\G :: #A/f/? +(a, b)
        \\H :: #B/g/? +(c, d)
        \\&choice :shape [box]
        \\G :style { &node :shape [hexagon], #A :shape [round] }
    , preview);
    defer c.deinit();
    const s = (try c.sheet()).?;
    const shape = s.descriptor(":shape").?;
    const Shape = enum { box, hexagon, round, circle, diamond };
    // In H, the top-level &choice over [base]'s.
    var choice_h: ?Sheet.View = null;
    for (s.ir.nodes.items(.kind), s.ir.nodes.items(.zone), 0..) |k, z, i| if (k == .choice and @backingInt(z) == 1) {
        choice_h = s.style(.{ .node = @fromBackingInt(@as(u32, @intCast(i))) });
    };
    try testing.expectEqual(Sheet.Label(Shape){ .value = .box }, choice_h.?.label(Shape, shape));
    // In G, G's &node over the top-level &choice; #A's own over both.
    try testing.expectEqual(Sheet.Label(Shape){ .value = .hexagon }, (try firstOf(s, .choice)).label(Shape, shape));
    try testing.expectEqual(Sheet.Label(Shape){ .value = .round }, (try nodeNamed(s, "#A")).label(Shape, shape));
    try testing.expectEqual(Sheet.Label(Shape){ .value = .circle }, (try nodeNamed(s, "#B")).label(Shape, shape));
}

test "a bundle binds its body where it is used; a token bound to a label resolves once" {
    var c = try Compilation.init(testing.allocator,
        \\:ref := :shape [round], :fill [muted]
        \\:Style [boxes] := { [circle] := [box], [box] := [round] }
        \\G :: #A/f/#B
        \\G :style { #A :ref, :theme [boxes] }
    , preview);
    defer c.deinit();
    const s = (try c.sheet()).?;
    const Shape = enum { box, round, circle };
    const shape = s.descriptor(":shape").?;
    const a = try nodeNamed(s, "#A");
    // The bundle's [round], which no token rebinds.
    try testing.expectEqual(Sheet.Label(Shape){ .value = .round }, a.label(Shape, shape));
    try testing.expectEqual(rgba(0x888888), a.color(s.descriptor(":fill").?).?);
    // [base]'s [circle] becomes [box], one step: not [round].
    try testing.expectEqual(Sheet.Label(Shape){ .value = .box }, (try nodeNamed(s, "#B")).label(Shape, shape));
}

test "a diagram's own tokens come after its themes" {
    var c = try Compilation.init(testing.allocator, "G :: #A/f\nG :style { :theme [dark], [ink] := [#000000] }", preview);
    defer c.deinit();
    const s = (try c.sheet()).?;
    try testing.expectEqual(rgba(0x000000), (try nodeNamed(s, "#A")).color(s.descriptor(":ink").?).?);
    try testing.expectEqual(rgba(0x000000), s.token(@fromBackingInt(@as(u32, 0)), "ink").?.color);
}

test "a container's layer reaches its members, beneath their own (statements.md §23.2)" {
    var c = try Compilation.init(testing.allocator,
        \\Master  :: #A/f
        \\Feature :: #B/g
        \\H       :: #C/h
        \\Repo    :: Master, Feature
        \\Outer   :: Repo
        \\&node :line [dashed]
        \\Repo :style { :theme [compact], :fill [#123456], &node { :shape [point], :line [dotted] }, [ink] := [#000000] }
        \\Feature :style { &node :shape [box], [ink] := [#ff0000] }
        \\Outer :style { &node :fill [#00ff00] }
    , preview);
    defer c.deinit();
    const s = (try c.sheet()).?;
    const Shape = enum { point, box, circle };
    const Line = enum { solid, dashed, dotted };
    const shape = s.descriptor(":shape").?;
    const line = s.descriptor(":line").?;
    const fill = s.descriptor(":fill").?;
    const ink_of = s.descriptor(":ink").?;

    // Master, in Repo, in Outer: Repo's classes, theme and tokens, Outer's
    // classes; the top-level class is Master's own, over Repo's.
    const a = try nodeNamed(s, "#A");
    try testing.expectEqual(Sheet.Label(Shape){ .value = .point }, a.label(Shape, shape));
    try testing.expectEqual(Sheet.Label(Line){ .value = .dashed }, a.label(Line, line));
    try testing.expectEqual(rgba(0x00ff00), a.color(fill).?);
    try testing.expectEqual(rgba(0x000000), a.color(ink_of).?);
    try testing.expectEqualStrings("0.2", try decimal(a.number(s.descriptor(":padding").?).?));
    // Feature's own class and token, over Repo's.
    const b = try nodeNamed(s, "#B");
    try testing.expectEqual(Sheet.Label(Shape){ .value = .box }, b.label(Shape, shape));
    try testing.expectEqual(rgba(0xff0000), b.color(ink_of).?);
    // H is held by nobody.
    const h = try nodeNamed(s, "#C");
    try testing.expectEqual(Sheet.Label(Shape){ .value = .circle }, h.label(Shape, shape));
    try testing.expectEqual(@as(?Rgba, null), h.color(fill));
    // In Repo itself, Repo's class over the top-level one.
    for (s.ir.nodes.items(.diagram), 0..) |d, i| if (d != null and @backingInt(d.?) == 0) {
        const of_master = s.style(.{ .node = @fromBackingInt(@as(u32, @intCast(i))) });
        try testing.expectEqual(Sheet.Label(Line){ .value = .dotted }, of_master.label(Line, line));
    };
    // Repo's own binding stays Repo's.
    try testing.expectEqual(rgba(0x123456), zoneStyle(s, 3).color(fill).?);
    try testing.expectEqual(@as(?Rgba, null), zoneStyle(s, 0).color(fill));
}

test "computed below [base]: labels by name, `:label []` gives the name back, a cell's arrow by level" {
    var c = try Compilation.init(testing.allocator,
        \\G :: #A/f/#B, #A/g/#B | f/α/g
        \\G :style { &node :label "n", #B :label [] }
    , preview);
    defer c.deinit();
    const s = (try c.sheet()).?;
    const label = s.descriptor(":label").?;
    try testing.expectEqualStrings("n", (try nodeNamed(s, "#A")).text(label).?);
    try testing.expectEqualStrings("B", (try nodeNamed(s, "#B")).text(label).?);
    try testing.expectEqualStrings("G", zoneStyle(s, 0).text(label).?);
    const cell = s.style(.{ .cell = @fromBackingInt(@as(u32, 0)) });
    try testing.expectEqualStrings("α", cell.text(label).?);
    const arrow = cell.get(s.descriptor(":arrow").?).?.elements;
    try testing.expectEqualStrings("double", arrow[1].label.name);
}

test "marks over everything, unless the diagram draws none" {
    var c = try Compilation.init(testing.allocator,
        \\G :: f g/+k h
        \\G :style { &node :stroke [#00ff00] }
        \\Q :: f g/+k h
        \\Q :style { :marks [], &node :stroke [#00ff00] }
    , preview);
    defer c.deinit();
    const s = (try c.sheet()).?;
    const stroke = s.descriptor(":stroke").?;
    var seen: [2]bool = .{ false, false };
    for (s.ir.nodes.items(.kind), s.ir.nodes.items(.zone), s.elements.nodes, 0..) |k, z, e, i| {
        const v = s.style(.{ .node = @fromBackingInt(@as(u32, @intCast(i))) });
        const zone = @backingInt(z);
        if (k == .hole) {
            seen[zone] = true;
            try testing.expect(e.mark != null);
            // G's hole in [error]'s colour; Q draws no marks.
            try testing.expectEqual(rgba(if (zone == 0) 0xd1242f else 0x00ff00), v.color(stroke).?);
        } else try testing.expectEqual(rgba(0x00ff00), v.color(stroke).?);
    }
    try testing.expect(seen[0] and seen[1]);
    try testing.expectEqual(rgba(0xd1242f), zoneStyle(s, 0).color(stroke).?);
    try testing.expectEqual(@as(?Rgba, null), zoneStyle(s, 1).color(stroke));
}

fn expectDump(source: []const u8, want: []const u8) !void {
    var c = try Compilation.init(testing.allocator, source, preview);
    defer c.deinit();
    var out: std.Io.Writer.Allocating = .init(testing.allocator);
    defer out.deinit();
    try (try c.sheet()).?.dump(&out.writer, .{});
    try testing.expectEqualStrings(want, out.written());
}

test "the dump: what the author asked for, by layer; [base] and the computed left out" {
    try expectDump(
        \\:Style [boxy] := { &node :shape [box], [ink] := [#ff0000] }
        \\G :: f g
        \\H :: h
        \\G :style {
        \\    :theme [boxy],
        \\    :fill  [#123456],
        \\    +f     { :label "x", :hide },
        \\    g      { :arrow [/dashed/>], :hide! }
        \\}
    ,
        \\zone G: fill [#123456] program
        \\  token ink [#ff0000]
        \\  node n0: label "x" program, shape [box] theme, hide program
        \\  node n1: shape [box] theme
        \\  node n2: shape [box] theme
        \\  edge g: arrow [/dashed/>] program, hide! program
        \\zone H
        \\
    );
}

test "the dump with [base]: its entries and every token, never the computed" {
    var c = try Compilation.init(testing.allocator, "G :: f", preview);
    defer c.deinit();
    const sheet = (try c.sheet()).?;
    var out: std.Io.Writer.Allocating = .init(testing.allocator);
    defer out.deinit();
    try sheet.dump(&out.writer, .{ .base = true });
    const text = out.written();
    for ([_][]const u8{ "as [cluster] base", "  token ink [#333333]\n", "  node n0: ", "shape [circle] base", "  edge f: ", "arrow [/solid/>] base" }) |want| {
        if (std.mem.indexOf(u8, text, want) == null) {
            std.debug.print("missing {s} in:\n{s}\n", .{ want, text });
            return error.TestUnexpectedResult;
        }
    }
    // The canonical label, `+f`, is computed.
    try testing.expect(std.mem.indexOf(u8, text, "\"+f\"") == null);

    out.clearRetainingCapacity();
    try sheet.dump(&out.writer, .{});
    try testing.expectEqualStrings("zone G\n", out.written());
}
