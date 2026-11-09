//! The style pass: Ir → Sheet, the IR with every element's look resolved.
//!
//! The cascade (`cascade.zig`, statements.md §22.4, §22.11, §22.12) makes
//! the Sheet of values: rules per diagram and set of classes, from `[base]`,
//! the diagram's themes and the program's class bindings; each element's
//! own bindings, what is computed (labels by name, a cell's arrow by level)
//! and its marks.
//!
//! Marks (statements.md §15.3, §18) are the last layer, so they always win.
//! Each issue has a severity, given beside the IR, since only the caller
//! knows its tolerance. A marked node or edge has its lines in the colour of
//! its worst issue, and a solid shape (a dot, a bar, an end) its fill too,
//! since the fill is the shape. A diagram with any issue, on it or on what
//! it holds, is framed in the colour of its worst, with "unsupported" above
//! its name while any is unsupported. `:marks []` draws none.
//!
//! Until fab-render reads the Sheet of values (plan step 9d5), the typed
//! tables are translated from it: `bridge`.

const std = @import("std");
const Ir = @import("../analyse/Ir.zig");
const Style = @import("Style.zig");
const Sheet = @import("Sheet.zig");
const cascade = @import("cascade.zig");
const value = @import("../analyse/value.zig");
const Mark = Style.Mark;

pub const Inputs = cascade.Inputs;
pub const ZoneMark = cascade.ZoneMark;

/// Resolves every element of `ir`, with `marks[i]` the severity of issue i.
/// The Sheet borrows `ir` and `in.env`.
pub fn style(gpa: std.mem.Allocator, ir: *const Ir, in: Inputs, marks: []const Mark) error{OutOfMemory}!Sheet {
    std.debug.assert(marks.len == ir.issues.len);

    // Which nodes some edge arrives at: that tells a start from an end.
    const reached = try gpa.alloc(bool, ir.nodes.len);
    defer gpa.free(reached);
    @memset(reached, false);
    for (ir.edges.items(.target)) |t| reached[@backingInt(t)] = true;

    // Each element's worst issue, and each diagram's.
    const node_marks = try gpa.alloc(?Mark, ir.nodes.len);
    defer gpa.free(node_marks);
    @memset(node_marks, null);
    const edge_marks = try gpa.alloc(?Mark, ir.edges.len);
    defer gpa.free(edge_marks);
    @memset(edge_marks, null);
    const cell_marks = try gpa.alloc(?Mark, ir.cells.len);
    defer gpa.free(cell_marks);
    @memset(cell_marks, null);
    for (ir.issues.items(.subject), marks) |subject, m| switch (subject) {
        .node => |n| join(&node_marks[@backingInt(n)], m),
        .edge => |e| join(&edge_marks[@backingInt(e)], m),
        .cell => |x| join(&cell_marks[@backingInt(x)], m),
        .zone => {},
    };
    const zone_marks = try gpa.alloc(ZoneMark, ir.zones.len);
    defer gpa.free(zone_marks);
    for (zone_marks, 0..) |*m, z| m.* = zoneMark(ir, marks, @fromBackingInt(@as(u32, @intCast(z))));

    var sheet: Sheet = .{ .ir = ir, .nodes = &.{}, .edges = &.{}, .zones = &.{}, .arena = .init(gpa), .gpa = gpa };
    errdefer sheet.deinit();
    try cascade.build(gpa, ir, in, reached, .{ .nodes = node_marks, .edges = edge_marks, .cells = cell_marks, .zones = zone_marks }, &sheet);
    try bridge(&sheet, zone_marks);
    return sheet;
}

/// The mark of `zone`: the issues on it, and on the nodes, edges and cells
/// in it.
pub fn zoneMark(ir: *const Ir, marks: []const Mark, zone: Ir.ZoneIndex) ZoneMark {
    var mark: ZoneMark = .{};
    for (ir.issues.items(.subject), marks) |subject, m| {
        const in = switch (subject) {
            .zone => |z| z,
            .node => |n| ir.nodes.items(.zone)[@backingInt(n)],
            .edge => |e| ir.edges.items(.zone)[@backingInt(e)],
            .cell => |x| ir.cells.items(.zone)[@backingInt(x)],
        };
        if (in != zone) continue;
        join(&mark.border, m);
        mark.unsupported = mark.unsupported or m == .unsupported;
    }
    return mark;
}

fn join(worst: *?Mark, m: Mark) void {
    worst.* = if (worst.*) |w| w.max(m) else m;
}

// ---------------------------------------------------------------------------
// The bridge (plan steps 9d4–9d5): the typed tables renderers read, from the
// Sheet of values. It goes once fab-render reads the Sheet.

const Names = struct {
    label: ?Sheet.Descriptor,
    caption: ?Sheet.Descriptor,
    face: ?Sheet.Descriptor,
    ink: ?Sheet.Descriptor,
    stroke: ?Sheet.Descriptor,
    fill: ?Sheet.Descriptor,
    line: ?Sheet.Descriptor,
    shape: ?Sheet.Descriptor,
    as: ?Sheet.Descriptor,
    arrow: ?Sheet.Descriptor,
};

fn bridge(s: *Sheet, zone_marks: []const ZoneMark) error{OutOfMemory}!void {
    const n: Names = .{
        .label = s.descriptor(":label"),
        .caption = s.descriptor(":caption"),
        .face = s.descriptor(":face"),
        .ink = s.descriptor(":ink"),
        .stroke = s.descriptor(":stroke"),
        .fill = s.descriptor(":fill"),
        .line = s.descriptor(":line"),
        .shape = s.descriptor(":shape"),
        .as = s.descriptor(":as"),
        .arrow = s.descriptor(":arrow"),
    };
    const ir = s.ir;
    const nodes = try s.gpa.alloc(Style, ir.nodes.len);
    s.nodes = nodes;
    for (nodes, 0..) |*out, i| out.* = typed(s.style(.{ .node = @fromBackingInt(@as(u32, @intCast(i))) }), n, .node);
    const edges = try s.gpa.alloc(Style, ir.edges.len);
    s.edges = edges;
    for (edges, 0..) |*out, i| out.* = typed(s.style(.{ .edge = @fromBackingInt(@as(u32, @intCast(i))) }), n, .edge);
    const zones = try s.gpa.alloc(Style, ir.zones.len);
    s.zones = zones;
    for (zones, ir.zones.items(.placeholder), zone_marks, 0..) |*out, placeholder, mark, i| {
        const zone: Ir.ZoneIndex = @fromBackingInt(@as(u32, @intCast(i)));
        const view = s.style(.{ .zone = zone });
        out.* = typed(view, n, .zone);
        if (placeholder) out.as = .placeholder;
        // In its own colour, even under a red frame (statements.md §15.3).
        if (mark.unsupported) if (n.caption) |d| if (view.text(d)) |text| {
            const ink = if (s.token(zone, "unsupported")) |v| switch (v) {
                .color => |c| rgb(c),
                else => Mark.unsupported.color(),
            } else Mark.unsupported.color();
            out.caption = .{ .text = text, .ink = ink };
        };
    }
}

fn typed(v: Sheet.View, n: Names, comptime of: enum { node, edge, zone }) Style {
    const face = if (n.face) |d| v.label(enum { regular, italic, bold, bold_italic }, d) else .nil;
    return .{
        .label = if (n.label) |d| v.text(d) orelse math(v, d) orelse "" else "",
        .caption = null,
        .italic = face == .value and (face.value == .italic or face.value == .bold_italic),
        .ink = colour(v, n.ink),
        .stroke = colour(v, n.stroke),
        .fill = if (of == .edge) null else colour(v, n.fill),
        .line = switch (of) {
            .node, .zone => if (n.line) |d| switch (v.label(Style.Line, d)) {
                .value => |l| l,
                .nil, .unknown => .none,
            } else .solid,
            // An edge's line is its arrow's middle.
            .edge => if (n.arrow) |d| arrowLine(v.get(d)) else .solid,
        },
        .shape = if (of == .node) if (n.shape) |d| switch (v.label(Style.Shape, d)) {
            .value => |shape| shape,
            .nil, .unknown => .none,
        } else .none else .none,
        .as = if (of == .zone) if (n.as) |d| switch (v.label(Style.As, d)) {
            .value => |as| as,
            .nil, .unknown => .cluster,
        } else .cluster else .cluster,
    };
}

fn math(v: Sheet.View, d: Sheet.Descriptor) ?[]const u8 {
    return if (v.get(d)) |x| switch (x) {
        .math => |m| m,
        else => null,
    } else null;
}

fn colour(v: Sheet.View, d: ?Sheet.Descriptor) ?Style.Color {
    return rgb(v.color(d orelse return null) orelse return null);
}

fn rgb(c: value.Rgba) Style.Color {
    return .{ .rgb = (@as(u24, c.r) << 16) | (@as(u24, c.g) << 8) | c.b };
}

fn arrowLine(arrow: ?@import("../analyse/decoded.zig").Value) Style.Line {
    const a = arrow orelse return .solid;
    if (a != .elements or a.elements.len != 3) return .solid;
    return switch (a.elements[1]) {
        .label => |l| std.meta.stringToEnum(Style.Line, l.name) orelse .solid,
        .nil => .none,
        else => .solid,
    };
}

test {
    _ = @import("style.test.zig");
}
