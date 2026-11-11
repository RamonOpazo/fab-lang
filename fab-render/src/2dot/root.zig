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
//!   - A placeholder zone (a statement that drew nothing) is a cluster with
//!     one node, `z{z}`, a square holding ✕: Graphviz has no square crossed
//!     corner to corner (statements.md §18). Its identifier is not `n…`, so
//!     no edge reaches it, and the law counts it apart.
//!   - A diagram's cluster is inside its first container's (statements.md
//!     §23.2), so clusters nest along the containment tree; a flat diagram's
//!     nodes are in the cluster around it, if any.
//!   - A node standing for a diagram drawn as a cluster is an invisible
//!     point inside that cluster, and an edge to it stops at the border
//!     (`compound=true`, `ltail`, `lhead`), unless its other end is inside
//!     the cluster, where Graphviz can't clip. A flat diagram's node is an
//!     ordinary node, labelled with the diagram's name.
//!   - A framed cluster with nothing in it (Db, whose edges all join other
//!     diagrams' nodes) holds one invisible point, `a{z}`, so its frame,
//!     name and caption still show; its edges stay at the top level
//!     (statements.md §20). Unframed, it writes nothing.
//!   - A caption ("unsupported") makes the cluster's label an HTML label: the
//!     one place DOT needs two kinds of text in one label.
//!
//! The Sheet decides every look; this file only realizes it in DOT's terms.
//! It reads the descriptors it draws (`drawn`), each element's once, into a
//! `Look`, the labels as its own enums; what else the author binds, a label
//! it has no meaning for, an arrow's ends, it notes (statements.md §22.12).
//! What DOT needs and the Sheet doesn't say, such as fonts, sizes and
//! spacing, is decided here once, in the header:
//!   - One sans-serif font; edge labels smaller. The header's colours are
//!     `[base]`'s ink and soft, and no element repeats them.
//!   - Every circle in a diagram has the same size, big enough for its
//!     longest label, so the label fits inside.
//!   - A bar is as wide as its busier side needs: one unit per branch.

const std = @import("std");
const fab = @import("fab_core");
const style = @import("fab_layer_style");
const Note = @import("../shared/Note.zig");
const Theme = @import("../shared/Theme.zig");

const Sheet = style.Sheet;
const Rgba = fab.value.Rgba;
const Writer = std.Io.Writer;

pub const Error = Writer.Error || error{OutOfMemory};

/// Draws `c`'s program as a DOT digraph: the style layer first, then the
/// graph (statements.md §26). False, and nothing written, when its IR is
/// withheld. Whatever DOT can't express is added to `notes`.
pub fn draw(c: *fab.Compilation, w: *Writer, notes: *Note.List) Error!bool {
    var sheet = try style.of(notes.gpa, c) orelse return false;
    defer sheet.deinit();
    try write(&sheet, w, notes);
    return true;
}

/// Writes `sheet` as a DOT digraph. Whatever DOT can't express is added to
/// `notes`.
pub fn write(sheet: *const Sheet, w: *Writer, notes: *Note.List) Error!void {
    const ir = sheet.ir;
    const gpa = notes.gpa;
    const node_zone = ir.nodes.items(.zone);

    var reader: Reader = try .init(sheet, notes);
    defer reader.deinit();
    const nodes = try gpa.alloc(Look, ir.nodes.len);
    defer gpa.free(nodes);
    for (nodes, node_zone, 0..) |*l, z, n| l.* = try reader.read(.{ .node = @fromBackingInt(@as(u32, @intCast(n))) }, z);
    const edges = try gpa.alloc(Look, ir.edges.len);
    defer gpa.free(edges);
    for (edges, ir.edges.items(.zone), 0..) |*l, z, e| l.* = try reader.read(.{ .edge = @fromBackingInt(@as(u32, @intCast(e))) }, z);
    const zones = try gpa.alloc(Look, ir.zones.len);
    defer gpa.free(zones);
    for (zones, 0..) |*l, z| {
        const zone: fab.Ir.ZoneIndex = @fromBackingInt(@as(u32, @intCast(z)));
        l.* = try reader.read(.{ .zone = zone }, zone);
    }

    // What made it (release.md §2).
    try w.print("// fab {s}\ndigraph {{\n", .{fab.version});
    try writeHeader(reader.defaults, w);

    var layout: Layout = try .init(gpa, ir, zones);
    defer layout.deinit(gpa);
    const out: Out = .{
        .ir = ir,
        .layout = &layout,
        .nodes = nodes,
        .zones = zones,
        .defaults = reader.defaults,
        .circle = circleSize(nodes),
        .w = w,
        .notes = notes,
    };

    // 1. Nodes, zone by zone, each inside its owner's cluster, and each
    // member's cluster inside its container's.
    for (ir.zones.items(.container), 0..) |container, z| {
        if (container == null) try out.zone(@fromBackingInt(@as(u32, @intCast(z))), 1);
    }

    // 2. Edges, at the top level, so they place no node. One reaching a
    // diagram's node stops at its border.
    for (ir.edges.items(.source), ir.edges.items(.target), ir.edges.items(.directed), edges, 0..) |s, t, directed, look, e| {
        try w.print("  n{d} -> n{d}", .{ @backingInt(s), @backingInt(t) });
        const clip: Clip = .{ .tail = layout.clip(s, t), .head = layout.clip(t, s) };
        try writeEdgeAttrs(look, directed, clip, @fromBackingInt(@as(u32, @intCast(e))), reader.defaults, w, notes);
        try w.writeAll("\n");
    }

    try w.writeAll("}\n");

    // 3. What DOT leaves out.
    for (0..ir.cells.len) |c| {
        try notes.add(.{ .tag = .cell_not_drawn, .subject = .{ .cell = @fromBackingInt(@as(u32, @intCast(c))) } });
    }
}

// ---------------------------------------------------------------------------
// Where each thing is drawn

/// Which cluster holds what. A diagram's cluster is inside its first
/// container's (statements.md §23.2), and a flat diagram's nodes are in the
/// cluster around it, if any.
const Layout = struct {
    ir: *const fab.Ir,
    /// Per zone: whether it is a cluster (not `:as flat`, or a placeholder).
    grouped: []bool,
    /// Per zone: whether anything is written for it.
    written: []bool,
    /// Per zone: a framed cluster with nothing in it holds an invisible
    /// point, `a{z}`, so its frame, name and caption still show.
    anchor: []bool,

    fn init(gpa: std.mem.Allocator, ir: *const fab.Ir, zones: []const Look) error{OutOfMemory}!Layout {
        const grouped = try gpa.alloc(bool, zones.len);
        errdefer gpa.free(grouped);
        const written = try gpa.alloc(bool, zones.len);
        errdefer gpa.free(written);
        const anchor = try gpa.alloc(bool, zones.len);
        errdefer gpa.free(anchor);
        const placeholder = ir.zones.items(.placeholder);
        for (grouped, zones, placeholder) |*g, look, p| g.* = p or look.as != .flat;

        var l: Layout = .{ .ir = ir, .grouped = grouped, .written = written, .anchor = anchor };
        // A diagram names only diagrams declared before it, so its members
        // are settled before it is.
        for (zones, 0..) |look, z| {
            const zone: fab.Ir.ZoneIndex = @fromBackingInt(@as(u32, @intCast(z)));
            var content = placeholder[z];
            for (0..ir.nodes.len) |n| content = content or l.home(@fromBackingInt(@as(u32, @intCast(n)))) == zone;
            for (ir.members.items(.member)) |m| content = content or (l.heldBy(m) == zone and written[@backingInt(m)]);
            const framed = grouped[z] and look.framed();
            written[z] = content or framed;
            anchor[z] = framed and !content;
        }
        return l;
    }

    fn deinit(l: *Layout, gpa: std.mem.Allocator) void {
        gpa.free(l.grouped);
        gpa.free(l.written);
        gpa.free(l.anchor);
    }

    /// The container that draws `m` inside it.
    fn heldBy(l: *const Layout, m: fab.Ir.ZoneIndex) ?fab.Ir.ZoneIndex {
        return l.ir.zones.items(.container)[@backingInt(m)];
    }

    /// The node of a diagram drawn as a cluster: the cluster stands for it.
    fn standsFor(l: *const Layout, n: fab.Ir.NodeIndex) ?fab.Ir.ZoneIndex {
        const d = l.ir.nodes.items(.diagram)[@backingInt(n)] orelse return null;
        return if (l.grouped[@backingInt(d)]) d else null;
    }

    /// The zone whose part of the output writes `n`: its diagram's, for a
    /// node standing for one, so edges reach that cluster; else its owner's.
    fn home(l: *const Layout, n: fab.Ir.NodeIndex) fab.Ir.ZoneIndex {
        return l.standsFor(n) orelse l.ir.nodes.items(.zone)[@backingInt(n)];
    }

    /// The cluster an edge end at `n` stops at, unless the other end, `other`,
    /// is inside it, where Graphviz can't clip.
    fn clip(l: *const Layout, n: fab.Ir.NodeIndex, other: fab.Ir.NodeIndex) ?u32 {
        const d = l.standsFor(n) orelse return null;
        var z: ?fab.Ir.ZoneIndex = l.home(other);
        while (z) |inside| : (z = l.heldBy(inside)) if (inside == d) return null;
        return @backingInt(d);
    }
};

/// The clusters an edge stops at, `ltail` and `lhead`.
const Clip = struct { tail: ?u32, head: ?u32 };

/// What step 1 writes with.
const Out = struct {
    ir: *const fab.Ir,
    layout: *const Layout,
    nodes: []const Look,
    zones: []const Look,
    defaults: Defaults,
    circle: f32,
    w: *Writer,
    notes: *Note.List,

    /// A zone at `depth` (two spaces each): its cluster, its nodes, then its
    /// members, each the same way.
    fn zone(o: *const Out, zone_index: fab.Ir.ZoneIndex, depth: usize) Error!void {
        const z = @backingInt(zone_index);
        if (!o.layout.written[z]) return;
        const look = o.zones[z];
        const w = o.w;
        const grouped = o.layout.grouped[z];
        const inner = depth + @intFromBool(grouped);
        if (grouped) {
            try w.splatByteAll(' ', 2 * depth);
            try w.print("subgraph cluster_{d} {{\n", .{z});
            try writeClusterAttrs(look, zone_index, inner, o.defaults, w, o.notes);
        }
        if (o.ir.zones.items(.placeholder)[z]) {
            try writePlaceholder(look, z, inner, o.defaults, w);
        } else {
            if (grouped and (look.as == .node or look.as == .table)) try o.notes.add(.{ .tag = .zone_drawn_as_cluster, .subject = .{ .zone = zone_index } });
            if (o.layout.anchor[z]) {
                try w.splatByteAll(' ', 2 * inner);
                try w.print("a{d} [label=\"\", shape=point, width=0.01, height=0.01, style=\"invis\"]\n", .{z});
            }
            for (0..o.ir.nodes.len) |n| {
                const index: fab.Ir.NodeIndex = @fromBackingInt(@as(u32, @intCast(n)));
                if (o.layout.home(index) != zone_index) continue;
                try w.splatByteAll(' ', 2 * inner);
                try w.print("n{d}", .{n});
                if (o.layout.standsFor(index) != null) {
                    // The cluster is the node; edges clip at its border.
                    try w.writeAll(" [label=\"\", shape=point, width=0.01, height=0.01, style=\"invis\"]");
                } else {
                    const sizes: Sizes = .{ .circle = o.circle, .branches = branches(o.ir, index) };
                    try writeNodeAttrs(o.nodes[n], index, sizes, o.defaults, w, o.notes);
                }
                try w.writeAll("\n");
            }
            for (o.ir.members.items(.container), o.ir.members.items(.member)) |c, m| {
                if (c == zone_index and o.layout.heldBy(m) == zone_index) try o.zone(m, inner);
            }
        }
        if (grouped) {
            try w.splatByteAll(' ', 2 * depth);
            try w.writeAll("}\n");
        }
    }
};

// ---------------------------------------------------------------------------
// What Graphviz draws, read from the Sheet

/// The descriptors this engine draws. Any other the author binds (a theme
/// or the program, not `[base]`) gets a note, once per diagram. `:marks`
/// is drawn by core, which applies the marks or not.
const drawn = [_][]const u8{ ":label", ":face", ":ink", ":stroke", ":fill", ":line", ":shape", ":as", ":caption", ":arrow", ":hide", ":marks" };

/// The labels it gives a meaning to, as enums; nil is the absence of one.
const Shape = enum { box, round, circle, double_circle, ellipse, stadium, diamond, hexagon, parallelogram, cylinder, document, bar, point, terminal, bullseye };
const Line = enum { solid, dashed, dotted, double, triple, wavy };
const Face = enum { regular, italic, bold, bold_italic };
const As = enum { flat, cluster, node, table };

/// One element's style, as Graphviz draws it.
const Look = struct {
    label: []const u8 = "",
    face: Face = .regular,
    ink: ?Rgba = null,
    stroke: ?Rgba = null,
    fill: ?Rgba = null,
    /// Null: no line.
    line: ?Line = .solid,
    /// Null: no shape, the label alone.
    shape: ?Shape = null,
    as: As = .cluster,
    caption: ?Caption = null,
    hide: bool = false,

    const Caption = struct { text: []const u8, ink: ?Rgba };

    /// A cluster draws a border or a background only when it has one.
    fn framed(l: Look) bool {
        return l.stroke != null or l.fill != null;
    }

    fn font(l: Look) ?[]const u8 {
        return switch (l.face) {
            .regular => null,
            .italic => Theme.font_italic,
            .bold => Theme.font_bold,
            .bold_italic => Theme.font_bold_italic,
        };
    }
};

/// The colours the header sets, so no element repeats them.
const Defaults = struct { ink: Rgba, soft: Rgba };

const Reader = struct {
    sheet: *const Sheet,
    notes: *Note.List,
    defaults: Defaults,
    /// `drawn`'s descriptors, looked up once.
    d: [drawn.len]?Sheet.Descriptor,
    /// The (zone, descriptor) pairs already noted.
    noted: std.AutoHashMapUnmanaged(struct { u32, u16 }, void) = .empty,

    fn init(sheet: *const Sheet, notes: *Note.List) error{OutOfMemory}!Reader {
        var r: Reader = .{ .sheet = sheet, .notes = notes, .defaults = .{
            .ink = baseColor(sheet, "ink") orelse .{ .r = 0, .g = 0, .b = 0 },
            .soft = baseColor(sheet, "soft") orelse .{ .r = 0, .g = 0, .b = 0 },
        }, .d = undefined };
        inline for (drawn, 0..) |name, i| r.d[i] = sheet.descriptor(name);
        return r;
    }

    fn deinit(r: *Reader) void {
        r.noted.deinit(r.notes.gpa);
    }

    fn at(r: *const Reader, comptime name: []const u8) ?Sheet.Descriptor {
        inline for (drawn, 0..) |n, i| if (comptime std.mem.eql(u8, n, name)) return r.d[i];
        @compileError("not drawn: " ++ name);
    }

    fn read(r: *Reader, subject: fab.Ir.Subject, zone: fab.Ir.ZoneIndex) error{OutOfMemory}!Look {
        const v = r.sheet.style(subject);
        try r.noteUndrawn(v, subject, zone);
        var l: Look = .{};
        if (r.at(":label")) |d| l.label = v.text(d) orelse math(v, d) orelse "";
        if (r.at(":face")) |d| l.face = try r.label(Face, v, d, subject) orelse .regular;
        if (r.at(":ink")) |d| l.ink = v.color(d);
        if (r.at(":stroke")) |d| l.stroke = v.color(d);
        if (r.at(":fill")) |d| l.fill = v.color(d);
        if (r.at(":line")) |d| l.line = try r.label(Line, v, d, subject);
        if (r.at(":shape")) |d| l.shape = try r.label(Shape, v, d, subject);
        if (r.at(":as")) |d| l.as = try r.label(As, v, d, subject) orelse .cluster;
        if (r.at(":hide")) |d| l.hide = v.flag(d);
        if (subject == .edge) {
            l.fill = null;
            l.line = .solid;
            if (r.at(":arrow")) |d| if (v.entry(d)) |e| {
                l.line = try r.arrowLine(e, subject);
            };
        }
        if (subject == .zone) if (r.at(":caption")) |d| if (v.entry(d)) |e| switch (e.value) {
            .text, .math => |text| l.caption = .{
                .text = text,
                // A mark's caption, "unsupported", in its own colour.
                .ink = if (e.layer == .mark) tokenColor(r.sheet, subject.zone, "unsupported") else l.ink,
            },
            else => {},
        };
        return l;
    }

    /// A label as `E`, null for nil; one `E` lacks is noted, and drawn as
    /// nil.
    fn label(r: *Reader, comptime E: type, v: Sheet.View, d: Sheet.Descriptor, subject: fab.Ir.Subject) error{OutOfMemory}!?E {
        return switch (v.label(E, d)) {
            .value => |x| x,
            .nil => null,
            .unknown => |name| {
                try r.notes.add(.{ .tag = .label_not_drawn, .subject = subject, .name = name });
                return null;
            },
        };
    }

    /// An edge's line, its arrow's middle; ends other than `[/…/>]` noted.
    fn arrowLine(r: *Reader, e: Sheet.Entry, subject: fab.Ir.Subject) error{OutOfMemory}!?Line {
        const slots = switch (e.value) {
            .elements => |es| es,
            else => return .solid,
        };
        if (slots.len != 3) return .solid;
        const plain_ends = slots[0] == .nil and slots[2] == .label and std.mem.eql(u8, slots[2].label.name, ">");
        if (!plain_ends and e.layer != .base and e.layer != .computed) try r.notes.add(.{ .tag = .arrow_ends_not_drawn, .subject = subject });
        return switch (slots[1]) {
            .label => |l| std.meta.stringToEnum(Line, l.name) orelse blk: {
                try r.notes.add(.{ .tag = .label_not_drawn, .subject = subject, .name = l.name });
                break :blk .solid;
            },
            .nil => null,
            else => .solid,
        };
    }

    /// What the author bound that this engine doesn't draw, once per
    /// diagram and descriptor.
    fn noteUndrawn(r: *Reader, v: Sheet.View, subject: fab.Ir.Subject, zone: fab.Ir.ZoneIndex) error{OutOfMemory}!void {
        try r.noteEntries(v.own, subject, zone);
        var it = v.rules();
        while (it.next()) |entries| try r.noteEntries(entries, subject, zone);
    }

    fn noteEntries(r: *Reader, entries: []const Sheet.Entry, subject: fab.Ir.Subject, zone: fab.Ir.ZoneIndex) error{OutOfMemory}!void {
        for (entries) |e| {
            if (e.layer != .kind and e.layer != .theme and e.layer != .program) continue;
            if (r.drawsDescriptor(e.descriptor)) continue;
            const gop = try r.noted.getOrPut(r.notes.gpa, .{ @backingInt(zone), @backingInt(e.descriptor) });
            if (gop.found_existing) continue;
            try r.notes.add(.{ .tag = .descriptor_not_drawn, .subject = subject, .name = r.sheet.descriptors[@backingInt(e.descriptor)] });
        }
    }

    fn drawsDescriptor(r: *const Reader, d: Sheet.Descriptor) bool {
        for (r.d) |x| if (x == d) return true;
        return false;
    }
};

fn math(v: Sheet.View, d: Sheet.Descriptor) ?[]const u8 {
    return if (v.get(d)) |x| switch (x) {
        .math => |m| m,
        else => null,
    } else null;
}

fn baseColor(sheet: *const Sheet, name: []const u8) ?Rgba {
    return switch (sheet.baseToken(name) orelse return null) {
        .color => |c| c,
        else => null,
    };
}

fn tokenColor(sheet: *const Sheet, zone: fab.Ir.ZoneIndex, name: []const u8) ?Rgba {
    return switch (sheet.token(zone, name) orelse return null) {
        .color => |c| c,
        else => null,
    };
}

// ---------------------------------------------------------------------------
// Defaults and sizes

/// Graph-wide defaults, so that each node and edge lists only what differs.
fn writeHeader(d: Defaults, w: *Writer) Writer.Error!void {
    try w.print("  graph [compound=true, fontname=\"{s}\", fontsize=11, fontcolor=\"{f}\", nodesep=0.45, ranksep=0.45, pad=0.2]\n", .{ Theme.font, hex(d.ink) });
    try w.print("  node [fontname=\"{s}\", fontsize=11, fontcolor=\"{f}\", color=\"{f}\"]\n", .{ Theme.font, hex(d.ink), hex(d.ink) });
    try w.print("  edge [fontname=\"{s}\", fontsize=9, fontcolor=\"{f}\", color=\"{f}\", arrowsize=0.6]\n", .{ Theme.font, hex(d.soft), hex(d.ink) });
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
fn circleSize(nodes: []const Look) f32 {
    var longest: usize = 0;
    for (nodes) |look| {
        const shape = look.shape orelse continue;
        if (shape != .circle and shape != .double_circle) continue;
        const chars = std.unicode.utf8CountCodepoints(look.label) catch look.label.len;
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

    /// `key`, unless `c` is what the graph's header already sets.
    fn colorUnless(a: *Attrs, key: []const u8, c: Rgba, default: Rgba) Writer.Error!void {
        if (!std.meta.eql(c, default)) try a.color(key, c);
    }

    fn color(a: *Attrs, key: []const u8, c: Rgba) Writer.Error!void {
        try a.sep();
        try a.w.print("{s}=\"{f}\"", .{ key, hex(c) });
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

fn realizeShape(shape: ?Shape) ShapeRealization {
    return switch (shape orelse return .{ .shape = "plaintext" }) {
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

fn writeNodeAttrs(look: Look, n: fab.Ir.NodeIndex, sizes: Sizes, d: Defaults, w: *Writer, notes: *Note.List) Error!void {
    const r = realizeShape(look.shape);
    if (r.approximated) try notes.add(.{ .tag = .shape_approximated, .subject = .{ .node = n } });
    const beside = r.size == .mark or r.size == .bar;

    var a: Attrs = .begin(w);
    if (beside) {
        try a.text("label", "");
        if (look.label.len > 0) try a.text("xlabel", look.label);
    } else {
        try a.text("label", look.label);
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
    // A font for text only.
    if (look.label.len > 0) {
        if (look.font()) |f| try a.text("fontname", f);
        if (look.ink) |c| try a.colorUnless("fontcolor", c, d.ink);
    }
    if (look.stroke) |c| try a.colorUnless("color", c, d.ink);
    if (r.solid) {
        a.flag("filled");
        try a.color("fillcolor", look.stroke orelse look.fill orelse d.ink);
    } else if (look.fill) |c| {
        a.flag("filled");
        try a.color("fillcolor", c);
    }
    if (r.rounded) a.flag("rounded");
    try lineFlags(&a, look.line, .{ .node = n }, notes);
    if (look.hide) a.flag("invis");
    if (look.line) |line| switch (line) {
        .double => try a.raw("peripheries", "2"),
        .triple => try a.raw("peripheries", "3"),
        else => {},
    };
    try a.end();
}

fn writeEdgeAttrs(look: Look, directed: bool, clip: Clip, e: fab.Ir.EdgeIndex, d: Defaults, w: *Writer, notes: *Note.List) Error!void {
    var a: Attrs = .begin(w);
    try a.text("label", look.label);
    if (!directed) try a.raw("dir", "none");
    if (clip.tail) |z| {
        try a.sep();
        try w.print("ltail=cluster_{d}", .{z});
    }
    if (clip.head) |z| {
        try a.sep();
        try w.print("lhead=cluster_{d}", .{z});
    }
    if (look.font()) |f| try a.text("fontname", f);
    if (look.ink) |c| try a.colorUnless("fontcolor", c, d.soft);
    if (look.line == .double or look.line == .triple) {
        // Parallel lines: the colour, a gap, the colour (and again).
        const c = look.stroke orelse d.ink;
        try a.sep();
        try w.print("color=\"{f}:invis:{f}", .{ hex(c), hex(c) });
        if (look.line == .triple) try w.print(":invis:{f}", .{hex(c)});
        try w.writeByte('"');
    } else if (look.stroke) |c| {
        try a.colorUnless("color", c, d.ink);
    }
    try lineFlags(&a, look.line, .{ .edge = e }, notes);
    if (look.hide) a.flag("invis");
    try a.end();
}

/// A cluster's attributes, at `depth`. Inside another cluster (`depth` past
/// the first), each is written out even when it is the default: a DOT
/// subgraph inherits its parent's, so a member would wear its container's
/// name, border and fill.
fn writeClusterAttrs(look: Look, zone: fab.Ir.ZoneIndex, depth: usize, d: Defaults, w: *Writer, notes: *Note.List) Error!void {
    const nested = depth > 2;
    if (!look.framed()) {
        // Groups the nodes for layout, draws nothing.
        try w.splatByteAll(' ', 2 * depth);
        try w.writeAll("peripheries=0\n");
        if (nested) {
            try w.splatByteAll(' ', 2 * depth);
            try w.writeAll("label=\"\"\n");
            try w.splatByteAll(' ', 2 * depth);
            try w.writeAll("style=\"\"\n");
        }
        return;
    }
    try w.splatByteAll(' ', 2 * depth);
    try w.writeAll("label=");
    if (look.caption) |caption| {
        // `<<font …>unsupported</font><br/>G>`: the caption above the name.
        try w.writeAll("<<font point-size=\"9\"");
        if (caption.ink) |c| try w.print(" color=\"{f}\"", .{hex(c)});
        try w.writeAll(">");
        try html(w, caption.text);
        try w.writeAll("</font><br/>");
        try html(w, look.label);
        try w.writeByte('>');
    } else {
        try quoted(w, look.label);
    }
    try w.writeByte('\n');
    try w.splatByteAll(' ', 2 * depth);
    if (look.stroke) |c| {
        try w.print("pencolor=\"{f}\"\n", .{hex(c)});
        if (nested) {
            try w.splatByteAll(' ', 2 * depth);
            try w.writeAll("peripheries=1\n");
        }
    } else {
        try w.writeAll("peripheries=0\n");
    }
    const ink = look.ink orelse d.ink;
    if (nested or !std.meta.eql(ink, d.ink)) {
        try w.splatByteAll(' ', 2 * depth);
        try w.print("fontcolor=\"{f}\"\n", .{hex(ink)});
    }
    var flags: [2][]const u8 = undefined;
    var count: usize = 0;
    if (look.fill) |c| {
        flags[count] = "filled";
        count += 1;
        try w.splatByteAll(' ', 2 * depth);
        try w.print("fillcolor=\"{f}\"\n", .{hex(c)});
    }
    if (look.line) |line| switch (line) {
        .dashed, .dotted => {
            flags[count] = @tagName(line);
            count += 1;
        },
        .wavy => try notes.add(.{ .tag = .wavy_line_drawn_solid, .subject = .{ .zone = zone } }),
        .solid, .double, .triple => {},
    };
    if (count > 0 or nested) {
        try w.splatByteAll(' ', 2 * depth);
        try w.writeAll("style=\"");
        for (flags[0..count], 0..) |name, i| {
            if (i > 0) try w.writeByte(',');
            try w.writeAll(name);
        }
        try w.writeAll("\"\n");
    }
}

/// The one node of a placeholder: a square holding ✕, in the frame's colour.
fn writePlaceholder(look: Look, z: usize, depth: usize, d: Defaults, w: *Writer) Writer.Error!void {
    const c = look.stroke orelse d.ink;
    try w.splatByteAll(' ', 2 * depth);
    try w.print("z{d} [label=\"✕\", shape=square, width=0.30, height=0.30, fixedsize=true, fontsize=16", .{z});
    try w.print(", color=\"{f}\", fontcolor=\"{f}\"]\n", .{ hex(c), hex(c) });
}

/// The `style` flags a line needs. `double` and `triple` are handled by the
/// caller, since nodes and edges draw them differently; no line is
/// invisible.
fn lineFlags(a: *Attrs, line: ?Line, subject: fab.Ir.Subject, notes: *Note.List) error{OutOfMemory}!void {
    switch (line orelse {
        a.flag("invis");
        return;
    }) {
        .solid, .double, .triple => {},
        .dashed => a.flag("dashed"),
        .dotted => a.flag("dotted"),
        .wavy => try notes.add(.{ .tag = .wavy_line_drawn_solid, .subject = subject }),
    }
}

// ---------------------------------------------------------------------------
// Values

/// A colour as DOT writes it: `#rrggbb`, and `aa` when it isn't opaque.
fn hex(c: Rgba) std.fmt.Alt(Rgba, writeHex) {
    return .{ .data = c };
}

fn writeHex(c: Rgba, w: *Writer) Writer.Error!void {
    try w.print("#{x:0>2}{x:0>2}{x:0>2}", .{ c.r, c.g, c.b });
    if (c.a != 0xff) try w.print("{x:0>2}", .{c.a});
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

/// Text inside an HTML label: `&`, `<`, `>` and `"` escaped.
pub fn html(w: *Writer, s: []const u8) Writer.Error!void {
    for (s) |c| switch (c) {
        '&' => try w.writeAll("&amp;"),
        '<' => try w.writeAll("&lt;"),
        '>' => try w.writeAll("&gt;"),
        '"' => try w.writeAll("&quot;"),
        else => try w.writeByte(c),
    };
}

test {
    _ = @import("2dot.test.zig");
}
