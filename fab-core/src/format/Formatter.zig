//! The format pass: Ir → Sheet, the IR with every entity's look resolved.
//!
//! For each node, edge and zone, the cascade is folded once, in order:
//!
//!   kind defaults ⊕ built-in classes ⊕ named classes ⊕ direct attributes
//!
//! The format layer (`:format`) isn't analysed yet, so today only the first
//! two layers have content: kind defaults, and the built-in classes `.node`,
//! `.edge`, `.zone` and `.canonical`. Named classes and direct attributes
//! will be folded in later without changing the fold.
//!
//! Labels follow one rule: `:label` if given, else the node's name without
//! its `#`, else the node's canonical end (`f+`, `+f`). A canonical label
//! puts the node in the built-in class `.canonical`: italic and muted, and
//! like any class, overridable. Edges and zones are labelled with their name.
//!
//! As with Parser and Analyser, the fields are the pass's working state, and
//! `format` is the entry point.

const std = @import("std");
const Ir = @import("../analyse/Ir.zig");
const Style = @import("Style.zig");
const Sheet = @import("Sheet.zig");
const Attrs = Style.Attrs;

const Formatter = @This();

gpa: std.mem.Allocator,
ir: *const Ir,
/// Canonical labels, written here first and pointed to only once the buffer
/// has stopped growing.
labels: std.ArrayList(u8) = .empty,
/// Which node each canonical label belongs to, and where it is in `labels`.
spans: std.ArrayList(Span) = .empty,

const Span = struct { node: usize, start: usize, end: usize };

/// Resolves every node, edge and zone of `ir`. The Sheet borrows `ir`.
pub fn format(gpa: std.mem.Allocator, ir: *const Ir) error{OutOfMemory}!Sheet {
    var f: Formatter = .{ .gpa = gpa, .ir = ir };
    defer f.labels.deinit(gpa);
    defer f.spans.deinit(gpa);

    const nodes = try gpa.alloc(Style, ir.nodes.len);
    errdefer gpa.free(nodes);
    for (nodes, 0..) |*style, i| style.* = try f.node(i);

    const edges = try gpa.alloc(Style, ir.edges.len);
    errdefer gpa.free(edges);
    for (edges, ir.edges.items(.name)) |*style, name| {
        style.* = builtin.edge.over(.{ .label = ir.string(name) }).resolve();
    }

    const zones = try gpa.alloc(Style, ir.zones.len);
    errdefer gpa.free(zones);
    for (zones, ir.zones.items(.name)) |*style, name| {
        style.* = builtin.zone.over(.{ .label = ir.string(name) }).resolve();
    }

    const owned = try f.labels.toOwnedSlice(gpa);
    for (f.spans.items) |span| nodes[span.node].label = owned[span.start..span.end];
    return .{ .ir = ir, .nodes = nodes, .edges = edges, .zones = zones, .labels = owned, .gpa = gpa };
}

/// The cascade for node `i`. A canonical label is recorded in `labels` and
/// filled in by `format` at the end.
fn node(f: *Formatter, i: usize) error{OutOfMemory}!Style {
    const n = f.ir.nodes.get(i);
    var attrs = kindDefault(n.kind).over(builtin.node);
    if (n.name) |name| {
        attrs = attrs.over(.{ .label = withoutSigil(f.ir.string(name)) });
    } else if (n.canonical) |end| {
        attrs = attrs.over(builtin.canonical);
        const start = f.labels.items.len;
        try f.writeCanonical(end);
        try f.spans.append(f.gpa, .{ .node = i, .start = start, .end = f.labels.items.len });
    }
    return attrs.resolve();
}

/// `+f` for a domain, `f+` for a codomain.
fn writeCanonical(f: *Formatter, end: Ir.End) error{OutOfMemory}!void {
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
fn kindDefault(kind: Ir.Node.Kind) Attrs {
    return switch (kind) {
        .plain => .{ .shape = .none },
        .choice => .{ .shape = .diamond },
        .parallel => .{ .shape = .bar },
        .null_node => .{ .shape = .terminal },
        .hole => .{ .shape = .circle, .line = .dashed },
    };
}

/// The built-in classes. The format layer will let a program override them.
pub const builtin = struct {
    pub const node: Attrs = .empty;
    pub const edge: Attrs = .empty;
    /// Zones are clusters, with no border unless the program gives one.
    pub const zone: Attrs = .{ .as = .cluster };
    /// Nodes labelled by their canonical end.
    pub const canonical: Attrs = .{ .italic = true, .ink = .{ .token = .muted } };
};

test {
    _ = @import("format.test.zig");
}
