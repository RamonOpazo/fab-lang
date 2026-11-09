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

const std = @import("std");
const Ir = @import("../analyse/Ir.zig");
const Sheet = @import("Sheet.zig");
const cascade = @import("cascade.zig");
const Mark = Sheet.Mark;

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

    var sheet: Sheet = .{ .ir = ir, .arena = .init(gpa), .gpa = gpa };
    errdefer sheet.deinit();
    try cascade.build(gpa, ir, in, reached, .{ .nodes = node_marks, .edges = edge_marks, .cells = cell_marks, .zones = zone_marks }, &sheet);
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

test {
    _ = @import("style.test.zig");
}
