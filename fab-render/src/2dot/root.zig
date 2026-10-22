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
//! What DOT needs and the Sheet doesn't say, such as fonts, sizes and
//! spacing, is decided here once, in the header:
//!   - One sans-serif font; edge labels smaller, in the theme's soft grey.
//!   - Every circle in a diagram has the same size, big enough for its
//!     longest label, so the label fits inside.
//!   - A bar is as wide as its busier side needs: one unit per branch.

const std = @import("std");
const fab = @import("fab_core");
const Note = @import("../shared/Note.zig");
const Theme = @import("../shared/Theme.zig");

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
    try writeHeader(w);
    const circle = circleSize(sheet);

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
            const index: fab.Ir.NodeIndex = @fromBackingInt(@as(u32, @intCast(n)));
            const sizes: Sizes = .{ .circle = circle, .branches = branches(ir, index) };
            try writeNodeAttrs(sheet.nodes[n], index, sizes, w, notes);
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
// Defaults and sizes

const font = "Helvetica";
const font_italic = "Helvetica-Oblique";

/// Graph-wide defaults, so that each node and edge lists only what differs.
fn writeHeader(w: *Writer) Writer.Error!void {
    const t = Theme.default;
    try w.print("  graph [fontname=\"{s}\", fontsize=11, nodesep=0.45, ranksep=0.45, pad=0.2]\n", .{font});
    try w.print("  node [fontname=\"{s}\", fontsize=11, fontcolor=\"#{x:0>6}\", color=\"#{x:0>6}\"]\n", .{ font, t.ink, t.ink });
    try w.print("  edge [fontname=\"{s}\", fontsize=9, fontcolor=\"#{x:0>6}\", color=\"#{x:0>6}\", arrowsize=0.6]\n", .{ font, t.soft, t.ink });
}

/// What a node's size depends on, beyond its own style.
const Sizes = struct {
    /// The diameter of every circle in the diagram, in inches.
    circle: f32,
    /// For bars: the branches on the busier side.
    branches: usize,
};

/// One diameter for every circle, wide enough for the longest label inside
/// one. An estimate: about 0.085 in per character at 11 pt, plus a margin.
fn circleSize(sheet: *const Sheet) f32 {
    var longest: usize = 0;
    for (sheet.nodes) |style| {
        if (style.shape != .circle and style.shape != .double_circle) continue;
        const chars = std.unicode.utf8CountCodepoints(style.label) catch style.label.len;
        longest = @max(longest, chars);
    }
    return @max(0.35, 0.085 * @as(f32, @floatFromInt(longest)) + 0.2);
}

/// The larger of a node's in- and out-degree.
fn branches(ir: *const fab.Ir, n: fab.Ir.NodeIndex) usize {
    var in: usize = 0;
    var out: usize = 0;
    for (ir.edges.items(.source), ir.edges.items(.target)) |s, t| {
        out += @intFromBool(s == n);
        in += @intFromBool(t == n);
    }
    return @max(in, out);
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

    /// `key=1.25`: inches, to two decimals.
    fn inches(a: *Attrs, key: []const u8, value: f32) Writer.Error!void {
        try a.sep();
        try a.w.print("{s}={d:.2}", .{ key, value });
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
    size: Size = .free,
    /// Filled with the stroke colour: a solid mark, such as a bar or a dot.
    solid: bool = false,
    approximated: bool = false,

    const Size = union(enum) {
        /// DOT sizes it around its label.
        free,
        /// The diagram's one circle size; the label inside.
        circle,
        /// A small mark of fixed width and height; any label goes beside it.
        mark: struct { f32, f32 },
        /// A bar: one unit of width per branch.
        bar,
    };
};

fn realizeShape(shape: Style.Shape) ShapeRealization {
    return switch (shape) {
        .none => .{ .shape = "plaintext" },
        .box => .{ .shape = "box" },
        .round => .{ .shape = "box", .rounded = true },
        .circle => .{ .shape = "circle", .size = .circle },
        .double_circle => .{ .shape = "doublecircle", .size = .circle },
        .ellipse => .{ .shape = "ellipse" },
        .stadium => .{ .shape = "box", .rounded = true, .approximated = true },
        .diamond => .{ .shape = "diamond", .size = .{ .mark = .{ 0.32, 0.32 } } },
        .hexagon => .{ .shape = "hexagon" },
        .parallelogram => .{ .shape = "parallelogram" },
        .cylinder => .{ .shape = "cylinder" },
        .document => .{ .shape = "note", .approximated = true },
        .bar => .{ .shape = "box", .size = .bar, .solid = true },
        .point => .{ .shape = "circle", .size = .{ .mark = .{ 0.14, 0.14 } }, .solid = true },
        .terminal => .{ .shape = "circle", .size = .{ .mark = .{ 0.15, 0.15 } } },
        .bullseye => .{ .shape = "doublecircle", .size = .{ .mark = .{ 0.1, 0.1 } }, .solid = true },
    };
}

fn writeNodeAttrs(style: Style, n: fab.Ir.NodeIndex, sizes: Sizes, w: *Writer, notes: *Note.List) Error!void {
    const r = realizeShape(style.shape);
    if (r.approximated) try notes.add(.{ .tag = .shape_approximated, .subject = .{ .node = n } });
    const beside = r.size == .mark or r.size == .bar;

    var a: Attrs = .begin(w);
    if (beside) {
        try a.text("label", "");
        if (style.label.len > 0) try a.text("xlabel", style.label);
    } else {
        try a.text("label", style.label);
    }
    try a.raw("shape", r.shape);
    switch (r.size) {
        .free => {},
        .circle => {
            try a.inches("width", sizes.circle);
            try a.inches("height", sizes.circle);
            try a.raw("fixedsize", "true");
        },
        .mark => |size| {
            const width, const height = size;
            try a.inches("width", width);
            try a.inches("height", height);
            try a.raw("fixedsize", "true");
        },
        .bar => {
            try a.inches("width", @max(0.6, 0.38 * @as(f32, @floatFromInt(sizes.branches))));
            try a.inches("height", 0.05);
            try a.raw("fixedsize", "true");
        },
    }
    if (style.italic) try a.text("fontname", font_italic);
    if (style.ink) |c| try a.color("fontcolor", c);
    if (style.stroke) |c| try a.color("color", c);
    if (r.solid) {
        a.flag("filled");
        try a.color("fillcolor", style.stroke orelse style.fill orelse .{ .rgb = Theme.default.ink });
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
    if (style.italic) try a.text("fontname", font_italic);
    if (style.ink) |c| try a.color("fontcolor", c);
    if (style.line == .double) {
        // Two parallel lines: the colour, a gap, the colour.
        const c = style.stroke orelse Style.Color{ .rgb = Theme.default.ink };
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

/// A colour as DOT writes it: `#rrggbb`, tokens resolved by the theme.
fn writeColor(w: *Writer, c: Style.Color) Writer.Error!void {
    try w.print("#{x:0>6}", .{Theme.default.rgb(c)});
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
