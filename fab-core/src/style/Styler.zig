//! The style pass: Ir → Sheet, the IR with every entity's look resolved.
//!
//! For each node, edge and zone, the cascade is folded once, in order:
//!
//!   kind defaults ⊕ built-in classes ⊕ named classes ⊕ direct attributes ⊕ marks
//!
//! The style layer (`:style`) isn't read here yet, so today only the first
//! two layers have content: kind defaults, and the built-in classes `.node`,
//! `.edge`, `.zone` and `.canonical`. Named classes and direct attributes
//! will be folded in later without changing the fold.
//!
//! Labels follow one rule: `:label` if given, else the node's name without
//! its `#`, the own node `@` its diagram's name, else the node's canonical
//! end (`f+`, `+f`). A canonical label
//! puts the node in the built-in class `.canonical`: italic and muted, and
//! like any class, overridable. Edges and zones are labelled with their name.
//!
//! Marks are the exception: choices, parallels, starts and ends draw a shape
//! that already says what they are, so by default they have no label, named
//! or canonical. Only `:label` will label a mark.
//!
//! Kind defaults: a plain node is a circle, a hole a dashed circle, a choice
//! a diamond, a parallel a bar. A null node is a start (a dot) if no edge
//! arrives at it, else an end (a bullseye), as in UML activity diagrams.
//!
//! Marks (statements.md §15.3, §18) are the last layer, so they always win.
//! Each issue has a severity, given beside the IR, since only the caller
//! knows its tolerance. A marked node or edge has its lines in the colour of
//! its worst issue, and a solid shape (a dot, a bar, an end) its fill too,
//! since the fill is the shape. A diagram with any issue, on it or on what
//! it holds, is framed in the colour of its worst, with "unsupported" above
//! its name while any is unsupported. A placeholder is drawn as one.
//!
//! As with Parser and Analyser, the fields are the pass's working state, and
//! `style` is the entry point.

const std = @import("std");
const Ir = @import("../analyse/Ir.zig");
const Style = @import("Style.zig");
const Sheet = @import("Sheet.zig");
const Attrs = Style.Attrs;
const Mark = Style.Mark;

const Styler = @This();

gpa: std.mem.Allocator,
ir: *const Ir,
/// Canonical labels, written here first and pointed to only once the buffer
/// has stopped growing.
labels: std.ArrayList(u8) = .empty,
/// Which node each canonical label belongs to, and where it is in `labels`.
spans: std.ArrayList(Span) = .empty,

const Span = struct { node: usize, start: usize, end: usize };

/// Resolves every node, edge and zone of `ir`, with `marks[i]` the severity
/// of issue i. The Sheet borrows `ir`.
pub fn style(gpa: std.mem.Allocator, ir: *const Ir, marks: []const Mark) error{OutOfMemory}!Sheet {
    std.debug.assert(marks.len == ir.issues.len);
    var f: Styler = .{ .gpa = gpa, .ir = ir };
    defer f.labels.deinit(gpa);
    defer f.spans.deinit(gpa);

    // Which nodes some edge arrives at: that tells a start from an end.
    const reached = try gpa.alloc(bool, ir.nodes.len);
    defer gpa.free(reached);
    @memset(reached, false);
    for (ir.edges.items(.target)) |t| reached[@backingInt(t)] = true;

    // Each node's and edge's worst issue.
    const node_marks = try gpa.alloc(?Mark, ir.nodes.len);
    defer gpa.free(node_marks);
    @memset(node_marks, null);
    const edge_marks = try gpa.alloc(?Mark, ir.edges.len);
    defer gpa.free(edge_marks);
    @memset(edge_marks, null);
    for (ir.issues.items(.subject), marks) |subject, m| switch (subject) {
        .node => |n| join(&node_marks[@backingInt(n)], m),
        .edge => |e| join(&edge_marks[@backingInt(e)], m),
        .cell, .zone => {},
    };

    const nodes = try gpa.alloc(Style, ir.nodes.len);
    errdefer gpa.free(nodes);
    for (nodes, reached, node_marks, 0..) |*resolved, arrived, m, i| {
        const attrs = try f.node(i, arrived);
        resolved.* = attrs.over(markLayer(m, attrs.shape)).resolve();
    }

    const edges = try gpa.alloc(Style, ir.edges.len);
    errdefer gpa.free(edges);
    for (edges, ir.edges.items(.name), edge_marks) |*resolved, name, m| {
        resolved.* = builtin.edge.over(.{ .label = ir.string(name) }).over(markLayer(m, null)).resolve();
    }

    const zones = try gpa.alloc(Style, ir.zones.len);
    errdefer gpa.free(zones);
    for (zones, ir.zones.items(.name), ir.zones.items(.placeholder), 0..) |*resolved, name, placeholder, z| {
        var attrs = builtin.zone.over(.{ .label = ir.string(name) });
        if (placeholder) attrs = attrs.over(.{ .as = .placeholder });
        const mark = zoneMark(ir, marks, @fromBackingInt(@as(u32, @intCast(z))));
        if (mark.border) |b| attrs = attrs.over(.{ .stroke = b.color() });
        // In its own colour, even under a red frame (statements.md §15.3).
        if (mark.unsupported) attrs = attrs.over(.{ .caption = .{ .text = "unsupported", .ink = Mark.unsupported.color() } });
        resolved.* = attrs.resolve();
    }

    const owned = try f.labels.toOwnedSlice(gpa);
    for (f.spans.items) |span| nodes[span.node].label = owned[span.start..span.end];
    return .{ .ir = ir, .nodes = nodes, .edges = edges, .zones = zones, .labels = owned, .gpa = gpa };
}

/// How a diagram is drawn for its issues: a border in the colour of the most
/// severe, and the label "unsupported" while any is unsupported.
pub const ZoneMark = struct {
    border: ?Mark = null,
    unsupported: bool = false,
};

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

/// The last layer: a marked element's lines in its colour, and the fill of a
/// solid shape too.
fn markLayer(mark: ?Mark, shape: ?Style.Shape) Attrs {
    const m = mark orelse return .empty;
    const solid = if (shape) |s| s == .point or s == .bar or s == .bullseye else false;
    return .{ .stroke = m.color(), .fill = if (solid) m.color() else null };
}

/// The cascade for node `i`, before marks; `arrived` says whether some edge
/// ends at it. A canonical label is recorded in `labels` and filled in by
/// `style` at the end.
fn node(f: *Styler, i: usize, arrived: bool) error{OutOfMemory}!Attrs {
    const n = f.ir.nodes.get(i);
    var attrs = kindDefault(n.kind, arrived).over(builtin.node);
    if (isMark(n.kind)) {
        // Unlabelled: the shape says what it is.
    } else if (n.name) |name| {
        attrs = attrs.over(.{ .label = withoutSigil(f.ir.string(name)) });
    } else if (f.ir.zones.items(.own)[@backingInt(n.zone)] == @as(Ir.NodeIndex, @fromBackingInt(@as(u32, @intCast(i))))) {
        // `@` stands for the diagram itself (statements.md §20).
        attrs = attrs.over(.{ .label = f.ir.string(f.ir.zones.items(.name)[@backingInt(n.zone)]) });
    } else if (n.canonical) |end| {
        attrs = attrs.over(builtin.canonical);
        const start = f.labels.items.len;
        try f.writeCanonical(end);
        try f.spans.append(f.gpa, .{ .node = i, .start = start, .end = f.labels.items.len });
    }
    return attrs;
}

/// `+f` for a domain, `f+` for a codomain.
fn writeCanonical(f: *Styler, end: Ir.End) error{OutOfMemory}!void {
    const name = f.ir.string(f.ir.edges.items(.name)[@backingInt(end.edge)]);
    if (end.side == .dom) try f.labels.append(f.gpa, '+');
    try f.labels.appendSlice(f.gpa, name);
    if (end.side == .cod) try f.labels.append(f.gpa, '+');
}

/// `#Valid` is labelled `Valid`.
fn withoutSigil(name: []const u8) []const u8 {
    return if (name.len > 0 and name[0] == '#') name[1..] else name;
}

/// The first layer of the cascade: how each kind of node looks by default.
/// A null node is a start unless some edge arrives at it.
fn kindDefault(kind: Ir.Node.Kind, arrived: bool) Attrs {
    return switch (kind) {
        .plain => .{ .shape = .circle },
        .choice => .{ .shape = .diamond },
        .parallel => .{ .shape = .bar },
        .null_node => .{ .shape = if (arrived) .bullseye else .point },
        .hole => .{ .shape = .circle, .line = .dashed },
    };
}

/// Kinds whose shape is their meaning: unlabelled by default.
fn isMark(kind: Ir.Node.Kind) bool {
    return switch (kind) {
        .choice, .parallel, .null_node => true,
        .plain, .hole => false,
    };
}

/// The built-in classes. The style layer will let a program override them.
pub const builtin = struct {
    pub const node: Attrs = .empty;
    pub const edge: Attrs = .empty;
    /// Zones are clusters, with no border unless the program gives one.
    pub const zone: Attrs = .{ .as = .cluster };
    /// Nodes labelled by their canonical end.
    pub const canonical: Attrs = .{ .italic = true, .ink = .{ .token = .muted } };
};

test {
    _ = @import("style.test.zig");
}
