//! Sheet → Graphviz DOT. No layout here: Graphviz lays out.
//!
//! The output encodes the 1-truncation of the IR: nodes, edges, node kinds,
//! zone ownership and edge direction, but not cells, which DOT can't express.
//! The correctness law, checked by the tests:
//!
//!   parse(write(G)) = τ≤1(G)
//!
//! Encoding:
//!   - Node i is `n{i}` and zone z is `cluster_{z}`. Names live only in
//!     labels, so identifiers never need escaping.
//!   - Every node is written first, inside the cluster of the zone that owns
//!     it; every edge is written after, at the top level. In DOT, a node
//!     belongs to the subgraph where it is first mentioned, so this order is
//!     what keeps an edge from pulling a node into another zone's cluster.
//!   - `:as cluster` groups a zone's nodes. A cluster is drawn (border, label,
//!     background) only if its style has a stroke or a fill; otherwise it
//!     still groups the nodes for layout, but draws nothing.
//!   - An undirected edge is `dir=none`, since a digraph has only `->`.
//!   - Cells are not drawn. Each one gets a note.
//!
//! The Sheet decides every look; this file only realizes it in DOT's terms.

const std = @import("std");
const fab = @import("fab_core");
const Note = @import("../shared/Note.zig");

const Sheet = fab.Sheet;
const Style = fab.Style;
const Writer = std.Io.Writer;

pub const Error = Writer.Error || error{OutOfMemory};

/// Writes `sheet` as a DOT digraph. Whatever DOT can't express is added to
/// `notes`.
pub fn write(sheet: *const Sheet, w: *Writer, notes: *Note.List) Error!void {
    const ir = sheet.ir;
    const node_zone = ir.nodes.items(.zone);
    try w.writeAll("digraph {\n");

    // 1. Nodes, zone by zone, each inside its owner's cluster.
    for (0..ir.zones.len) |z| {
        const zone: fab.Ir.ZoneIndex = @fromBackingInt(@as(u32, @intCast(z)));
        var owns_nodes = false;
        for (node_zone) |owner| owns_nodes = owns_nodes or owner == zone;
        if (!owns_nodes) continue;

        const as = sheet.drawnAs(zone);
        const grouped = as != .flat;
        if (as == .node or as == .table) try notes.add(.{ .tag = .zone_drawn_as_cluster, .subject = .{ .zone = zone } });

        const indent = if (grouped) "    " else "  ";
        if (grouped) {
            try w.print("  subgraph cluster_{d} {{\n", .{z});
            try writeClusterAttrs(sheet, zone, w, notes);
        }
        for (node_zone, 0..) |owner, n| {
            if (owner != zone) continue;
            try w.print("{s}n{d}", .{ indent, n });
            try writeNodeAttrs(sheet.nodes[n], @fromBackingInt(@as(u32, @intCast(n))), w, notes);
            try w.writeAll("\n");
        }
        if (grouped) try w.writeAll("  }\n");
    }

    // 2. Edges, at the top level, so they place no node.
    for (ir.edges.items(.source), ir.edges.items(.target), ir.edges.items(.directed), sheet.edges, 0..) |s, t, directed, style, e| {
        try w.print("  n{d} -> n{d}", .{ @backingInt(s), @backingInt(t) });
        try writeEdgeAttrs(style, directed, @fromBackingInt(@as(u32, @intCast(e))), w, notes);
        try w.writeAll("\n");
    }

    try w.writeAll("}\n");

    // 3. What DOT leaves out.
    for (0..ir.cells.len) |c| {
        try notes.add(.{ .tag = .cell_not_drawn, .subject = .{ .cell = @fromBackingInt(@as(u32, @intCast(c))) } });
    }
}

// ---------------------------------------------------------------------------
// Attributes. Each entity's attributes are written as one bracketed list, in a
// fixed order, so the output is byte-for-byte deterministic.

const Attrs = struct {
    w: *Writer,
    count: usize = 0,
    /// Flags for DOT's comma-separated `style` attribute.
    style: [4][]const u8 = undefined,
    style_count: usize = 0,

    fn begin(w: *Writer) Attrs {
        return .{ .w = w };
    }

    fn sep(a: *Attrs) Writer.Error!void {
        try a.w.writeAll(if (a.count == 0) " [" else ", ");
        a.count += 1;
    }

    /// `key="value"`, escaped.
    fn text(a: *Attrs, key: []const u8, value: []const u8) Writer.Error!void {
        try a.sep();
        try a.w.print("{s}=", .{key});
        try quoted(a.w, value);
    }

    /// `key=value`, for values that never need quoting.
    fn raw(a: *Attrs, key: []const u8, value: []const u8) Writer.Error!void {
        try a.sep();
        try a.w.print("{s}={s}", .{ key, value });
    }

    fn color(a: *Attrs, key: []const u8, c: Style.Color) Writer.Error!void {
        try a.sep();
        try a.w.print("{s}=\"", .{key});
        try writeColor(a.w, c);
        try a.w.writeByte('"');
    }

    fn flag(a: *Attrs, name: []const u8) void {
        a.style[a.style_count] = name;
        a.style_count += 1;
    }

    fn end(a: *Attrs) Writer.Error!void {
        if (a.style_count > 0) {
            try a.sep();
            try a.w.writeAll("style=\"");
            for (a.style[0..a.style_count], 0..) |name, i| {
                if (i > 0) try a.w.writeByte(',');
                try a.w.writeAll(name);
            }
            try a.w.writeByte('"');
        }
        if (a.count > 0) try a.w.writeByte(']');
    }
};

/// How a Shape is realized: a DOT shape, plus what it needs to look right.
const ShapeRealization = struct {
    shape: []const u8,
    rounded: bool = false,
    /// A small fixed size, in inches; the label goes beside it as `xlabel`.
    small: ?struct { []const u8, []const u8 } = null,
    /// Filled with the stroke colour: a solid mark, such as a bar.
    solid: bool = false,
    approximated: bool = false,
};

fn realizeShape(shape: Style.Shape) ShapeRealization {
    return switch (shape) {
        .none => .{ .shape = "plaintext" },
        .box => .{ .shape = "box" },
        .round => .{ .shape = "box", .rounded = true },
        .circle => .{ .shape = "circle" },
        .double_circle => .{ .shape = "doublecircle" },
        .ellipse => .{ .shape = "ellipse" },
        .stadium => .{ .shape = "box", .rounded = true, .approximated = true },
        .diamond => .{ .shape = "diamond" },
        .hexagon => .{ .shape = "hexagon" },
        .parallelogram => .{ .shape = "parallelogram" },
        .cylinder => .{ .shape = "cylinder" },
        .document => .{ .shape = "note", .approximated = true },
        .bar => .{ .shape = "box", .small = .{ "0.5", "0.06" }, .solid = true },
        .point => .{ .shape = "point" },
        .terminal => .{ .shape = "circle", .small = .{ "0.15", "0.15" } },
        .bullseye => .{ .shape = "doublecircle", .small = .{ "0.2", "0.2" } },
    };
}

fn writeNodeAttrs(style: Style, n: fab.Ir.NodeIndex, w: *Writer, notes: *Note.List) Error!void {
    const r = realizeShape(style.shape);
    if (r.approximated) try notes.add(.{ .tag = .shape_approximated, .subject = .{ .node = n } });
    const beside = r.small != null or style.shape == .point;

    var a: Attrs = .begin(w);
    if (beside) {
        try a.text("label", "");
        if (style.label.len > 0) try a.text("xlabel", style.label);
    } else {
        try a.text("label", style.label);
    }
    try a.raw("shape", r.shape);
    if (r.small) |size| {
        const width, const height = size;
        try a.raw("width", width);
        try a.raw("height", height);
        try a.raw("fixedsize", "true");
    }
    if (style.italic) try a.text("fontname", "Times-Italic");
    if (style.ink) |c| try a.color("fontcolor", c);
    if (style.stroke) |c| try a.color("color", c);
    if (r.solid) {
        a.flag("filled");
        try a.color("fillcolor", style.stroke orelse style.fill orelse .{ .rgb = 0x000000 });
    } else if (style.fill) |c| {
        a.flag("filled");
        try a.color("fillcolor", c);
    }
    if (r.rounded) a.flag("rounded");
    try lineFlags(&a, style.line, .{ .node = n }, notes);
    if (style.line == .double) try a.raw("peripheries", "2");
    try a.end();
}

fn writeEdgeAttrs(style: Style, directed: bool, e: fab.Ir.EdgeIndex, w: *Writer, notes: *Note.List) Error!void {
    var a: Attrs = .begin(w);
    try a.text("label", style.label);
    if (!directed) try a.raw("dir", "none");
    if (style.italic) try a.text("fontname", "Times-Italic");
    if (style.ink) |c| try a.color("fontcolor", c);
    if (style.line == .double) {
        // Two parallel lines: the colour, a gap, the colour.
        const c = style.stroke orelse Style.Color{ .rgb = 0x000000 };
        try a.sep();
        try w.writeAll("color=\"");
        try writeColor(w, c);
        try w.writeAll(":invis:");
        try writeColor(w, c);
        try w.writeByte('"');
    } else if (style.stroke) |c| {
        try a.color("color", c);
    }
    try lineFlags(&a, style.line, .{ .edge = e }, notes);
    try a.end();
}

fn writeClusterAttrs(sheet: *const Sheet, zone: fab.Ir.ZoneIndex, w: *Writer, notes: *Note.List) Error!void {
    const style = sheet.zone(zone);
    if (!sheet.isFramed(zone)) {
        // Groups the nodes for layout, draws nothing.
        try w.writeAll("    peripheries=0\n");
        return;
    }
    try w.writeAll("    label=");
    try quoted(w, style.label);
    try w.writeByte('\n');
    if (style.stroke) |c| {
        try w.writeAll("    pencolor=\"");
        try writeColor(w, c);
        try w.writeAll("\"\n");
    } else {
        try w.writeAll("    peripheries=0\n");
    }
    if (style.ink) |c| {
        try w.writeAll("    fontcolor=\"");
        try writeColor(w, c);
        try w.writeAll("\"\n");
    }
    var flags: [2][]const u8 = undefined;
    var count: usize = 0;
    if (style.fill) |c| {
        flags[count] = "filled";
        count += 1;
        try w.writeAll("    fillcolor=\"");
        try writeColor(w, c);
        try w.writeAll("\"\n");
    }
    switch (style.line) {
        .dashed, .dotted => {
            flags[count] = @tagName(style.line);
            count += 1;
        },
        .wavy => try notes.add(.{ .tag = .wavy_line_drawn_solid, .subject = .{ .zone = zone } }),
        .solid, .double, .none => {},
    }
    if (count > 0) {
        try w.writeAll("    style=\"");
        for (flags[0..count], 0..) |name, i| {
            if (i > 0) try w.writeByte(',');
            try w.writeAll(name);
        }
        try w.writeAll("\"\n");
    }
}

/// The `style` flags a line needs. `double` is handled by the caller, since
/// nodes and edges draw it differently.
fn lineFlags(a: *Attrs, line: Style.Line, subject: fab.Ir.Subject, notes: *Note.List) error{OutOfMemory}!void {
    switch (line) {
        .solid, .double => {},
        .dashed => a.flag("dashed"),
        .dotted => a.flag("dotted"),
        .none => a.flag("invis"),
        .wavy => try notes.add(.{ .tag = .wavy_line_drawn_solid, .subject = subject }),
    }
}

// ---------------------------------------------------------------------------
// Values

/// The theme, as DOT realizes it.
fn writeColor(w: *Writer, c: Style.Color) Writer.Error!void {
    switch (c) {
        .rgb => |rgb| try w.print("#{x:0>6}", .{rgb}),
        .token => |t| try w.writeAll(switch (t) {
            .muted => "#888888",
            .accent => "#1f6feb",
        }),
    }
}

/// A DOT string. Backslashes are escaped too, so that DOT's own escapes
/// (`\n`, `\l`, `\N`) never fire by accident: `$\mathbb{R}$` stays as written.
pub fn quoted(w: *Writer, s: []const u8) Writer.Error!void {
    try w.writeByte('"');
    for (s) |c| switch (c) {
        '"' => try w.writeAll("\\\""),
        '\\' => try w.writeAll("\\\\"),
        '\n' => try w.writeAll("\\n"),
        '\r' => {},
        else => try w.writeByte(c),
    };
    try w.writeByte('"');
}

test {
    _ = @import("2dot.test.zig");
}
