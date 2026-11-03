//! Tests for 2dot: golden outputs, and the correctness law
//!
//!   parse(write(G)) = τ≤1(G)
//!
//! checked by reading the DOT back with a reader for exactly the subset
//! write() produces.

const std = @import("std");
const testing = std.testing;
const fab = @import("fab_core");
const to_dot = @import("root.zig");
const Note = @import("../shared/Note.zig");

const Style = fab.Style;

/// A resolved style from just the attributes a test cares about.
fn style(a: Style.Attrs) Style {
    return a.resolve();
}

const preview: fab.Compilation.Tolerance = .{ .warnings = .warn, .ir = .keep };

/// The DOT for `sheet`, and its notes. Caller frees both.
const Output = struct {
    dot: []u8,
    notes: Note.List,

    fn deinit(o: *Output) void {
        testing.allocator.free(o.dot);
        o.notes.deinit();
    }
};

fn render(sheet: *const fab.Sheet) !Output {
    var out: std.Io.Writer.Allocating = .init(testing.allocator);
    defer out.deinit();
    var notes: Note.List = .init(testing.allocator);
    errdefer notes.deinit();
    try to_dot.write(sheet, &out.writer, &notes);
    return .{ .dot = try out.toOwnedSlice(), .notes = notes };
}

/// Every file starts with these defaults, so goldens show only the body.
const header =
    \\  graph [fontname="Helvetica", fontsize=11, nodesep=0.45, ranksep=0.45, pad=0.2]
    \\  node [fontname="Helvetica", fontsize=11, fontcolor="#333333", color="#333333"]
    \\  edge [fontname="Helvetica", fontsize=9, fontcolor="#555555", color="#333333", arrowsize=0.6]
    \\
;

fn expectDot(source: []const u8, body: []const u8) !void {
    var c = try fab.Compilation.init(testing.allocator, source, preview);
    defer c.deinit();
    var o = try render((try c.sheet()).?);
    defer o.deinit();
    try expectBody(body, o.dot);
}

fn expectBody(body: []const u8, dot: []const u8) !void {
    const start = "digraph {\n" ++ header;
    try testing.expect(std.mem.startsWith(u8, dot, start));
    try testing.expectEqualStrings(body, dot[start.len..]);
}

// ---------------------------------------------------------------------------
// Golden outputs

test "a chain: canonical labels, in the canonical class" {
    try expectDot("G :: f g",
        \\  subgraph cluster_0 {
        \\    peripheries=0
        \\    n0 [label="+f", shape=circle, width=0.37, height=0.37, fixedsize=true, fontname="Helvetica-Oblique", fontcolor="#888888"]
        \\    n1 [label="f+", shape=circle, width=0.37, height=0.37, fixedsize=true, fontname="Helvetica-Oblique", fontcolor="#888888"]
        \\    n2 [label="g+", shape=circle, width=0.37, height=0.37, fixedsize=true, fontname="Helvetica-Oblique", fontcolor="#888888"]
        \\  }
        \\  n0 -> n1 [label="f"]
        \\  n1 -> n2 [label="g"]
        \\}
        \\
    );
}

test "names label circles without their #; a choice is unlabelled" {
    try expectDot("G :: #A/f/? g",
        \\  subgraph cluster_0 {
        \\    peripheries=0
        \\    n0 [label="A", shape=circle, width=0.37, height=0.37, fixedsize=true]
        \\    n1 [label="", shape=diamond, width=0.32, height=0.32, fixedsize=true]
        \\    n2 [label="g+", shape=circle, width=0.37, height=0.37, fixedsize=true, fontname="Helvetica-Oblique", fontcolor="#888888"]
        \\  }
        \\  n0 -> n1 [label="f"]
        \\  n1 -> n2 [label="g"]
        \\}
        \\
    );
}

test "marks: a start is a dot, a bar is as wide as its branches, a choice a diamond" {
    try expectDot("G :: */f/! +(g, h)? k",
        \\  subgraph cluster_0 {
        \\    peripheries=0
        \\    n0 [label="", shape=circle, width=0.14, height=0.14, fixedsize=true, fillcolor="#333333", style="filled"]
        \\    n1 [label="", shape=box, width=0.76, height=0.05, fixedsize=true, fillcolor="#333333", style="filled"]
        \\    n2 [label="", shape=diamond, width=0.32, height=0.32, fixedsize=true]
        \\    n3 [label="k+", shape=circle, width=0.37, height=0.37, fixedsize=true, fontname="Helvetica-Oblique", fontcolor="#888888"]
        \\  }
        \\  n0 -> n1 [label="f"]
        \\  n1 -> n2 [label="g"]
        \\  n1 -> n2 [label="h"]
        \\  n2 -> n3 [label="k"]
        \\}
        \\
    );
}

test "two zones sharing a node: it stays in its owner's cluster" {
    // `h` points into A. Were the edge written inside B's cluster, Graphviz
    // would place n0 there; nodes first, edges after, prevents it.
    try expectDot("A :: f g\nB :: h/A.+f",
        \\  subgraph cluster_0 {
        \\    peripheries=0
        \\    n0 [label="+f", shape=circle, width=0.37, height=0.37, fixedsize=true, fontname="Helvetica-Oblique", fontcolor="#888888"]
        \\    n1 [label="f+", shape=circle, width=0.37, height=0.37, fixedsize=true, fontname="Helvetica-Oblique", fontcolor="#888888"]
        \\    n2 [label="g+", shape=circle, width=0.37, height=0.37, fixedsize=true, fontname="Helvetica-Oblique", fontcolor="#888888"]
        \\  }
        \\  subgraph cluster_1 {
        \\    peripheries=0
        \\    n3 [label="+h", shape=circle, width=0.37, height=0.37, fixedsize=true, fontname="Helvetica-Oblique", fontcolor="#888888"]
        \\  }
        \\  n0 -> n1 [label="f"]
        \\  n1 -> n2 [label="g"]
        \\  n3 -> n0 [label="h"]
        \\}
        \\
    );
}

test "undirected edges have no arrowhead" {
    try expectDot("G :: f/",
        \\  subgraph cluster_0 {
        \\    peripheries=0
        \\    n0 [label="+f", shape=circle, width=0.37, height=0.37, fixedsize=true, fontname="Helvetica-Oblique", fontcolor="#888888"]
        \\    n1 [label="f+", shape=circle, width=0.37, height=0.37, fixedsize=true, fontname="Helvetica-Oblique", fontcolor="#888888"]
        \\  }
        \\  n0 -> n1 [label="f", dir=none]
        \\}
        \\
    );
}

test "holes are dashed circles, marked by their error, which frames the diagram" {
    // `+k` is not declared: g's end is a hole, and the path goes on to h.
    try expectDot("G :: f g/+k h",
        \\  subgraph cluster_0 {
        \\    label="G"
        \\    pencolor="#d1242f"
        \\    n0 [label="+f", shape=circle, width=0.37, height=0.37, fixedsize=true, fontname="Helvetica-Oblique", fontcolor="#888888"]
        \\    n1 [label="f+", shape=circle, width=0.37, height=0.37, fixedsize=true, fontname="Helvetica-Oblique", fontcolor="#888888"]
        \\    n2 [label="g+", shape=circle, width=0.37, height=0.37, fixedsize=true, fontname="Helvetica-Oblique", fontcolor="#888888", color="#d1242f", style="dashed"]
        \\    n3 [label="h+", shape=circle, width=0.37, height=0.37, fixedsize=true, fontname="Helvetica-Oblique", fontcolor="#888888"]
        \\  }
        \\  n0 -> n1 [label="f"]
        \\  n1 -> n2 [label="g"]
        \\  n2 -> n3 [label="h"]
        \\}
        \\
    );
}

test "an end is a bullseye" {
    try expectDot("G :: f/*",
        \\  subgraph cluster_0 {
        \\    peripheries=0
        \\    n0 [label="+f", shape=circle, width=0.37, height=0.37, fixedsize=true, fontname="Helvetica-Oblique", fontcolor="#888888"]
        \\    n1 [label="", shape=doublecircle, width=0.10, height=0.10, fixedsize=true, fillcolor="#333333", style="filled"]
        \\  }
        \\  n0 -> n1 [label="f"]
        \\}
        \\
    );
}

test "every circle has the size of the longest label" {
    var c = try fab.Compilation.init(testing.allocator, "G :: #A/f/#Approved g", preview);
    defer c.deinit();
    var o = try render((try c.sheet()).?);
    defer o.deinit();
    // "Approved" has 8 characters: 0.085 × 8 + 0.2 = 0.88, for all three.
    try testing.expectEqual(3, std.mem.count(u8, o.dot, "width=0.88, height=0.88"));
}

test "cells are left out, with one note each" {
    var c = try fab.Compilation.init(testing.allocator, "Iso :: +(f, g)+ | f/α/g/β", preview);
    defer c.deinit();
    const sheet = (try c.sheet()).?;
    var o = try render(sheet);
    defer o.deinit();
    try testing.expectEqual(sheet.ir.cells.len, o.notes.items.items.len);
    try testing.expect(sheet.ir.cells.len == 2);
    for (o.notes.items.items, 0..) |n, i| {
        try testing.expectEqual(Note.Tag.cell_not_drawn, n.tag);
        try testing.expectEqual(i, @backingInt(n.subject.?.cell));
    }
    try testing.expect(std.mem.indexOf(u8, o.dot, "α") == null);
}

test "strings: quotes, backslashes and newlines are escaped" {
    var out: std.Io.Writer.Allocating = .init(testing.allocator);
    defer out.deinit();
    try to_dot.quoted(&out.writer, "say \"hi\"\n$\\mathbb{R}$\\n");
    try testing.expectEqualStrings(
        \\"say \"hi\"\n$\\mathbb{R}$\\n"
    , out.written());
}

// ---------------------------------------------------------------------------
// Issues (statements.md §15.3, §18)

test "a placeholder is a square holding ✕, framed by its error" {
    try expectDot("G :: f\nH :: g /k",
        \\  subgraph cluster_0 {
        \\    peripheries=0
        \\    n0 [label="+f", shape=circle, width=0.37, height=0.37, fixedsize=true, fontname="Helvetica-Oblique", fontcolor="#888888"]
        \\    n1 [label="f+", shape=circle, width=0.37, height=0.37, fixedsize=true, fontname="Helvetica-Oblique", fontcolor="#888888"]
        \\  }
        \\  subgraph cluster_1 {
        \\    label="H"
        \\    pencolor="#d1242f"
        \\    z1 [label="✕", shape=square, width=0.30, height=0.30, fixedsize=true, fontsize=16, color="#d1242f", fontcolor="#d1242f"]
        \\  }
        \\  n0 -> n1 [label="f"]
        \\}
        \\
    );
}

test "a reserved head draws a placeholder too" {
    try expectDot("review :: a b",
        \\  subgraph cluster_0 {
        \\    label="review"
        \\    pencolor="#d1242f"
        \\    z0 [label="✕", shape=square, width=0.30, height=0.30, fixedsize=true, fontsize=16, color="#d1242f", fontcolor="#d1242f"]
        \\  }
        \\}
        \\
    );
}

test "unsupported: a violet frame, and the caption above the name" {
    try expectDot("J :: f\nJ :style := f :label \"x\"",
        \\  subgraph cluster_0 {
        \\    label=<<font point-size="9" color="#8250df">unsupported</font><br/>J>
        \\    pencolor="#8250df"
        \\    n0 [label="+f", shape=circle, width=0.37, height=0.37, fixedsize=true, fontname="Helvetica-Oblique", fontcolor="#888888"]
        \\    n1 [label="f+", shape=circle, width=0.37, height=0.37, fixedsize=true, fontname="Helvetica-Oblique", fontcolor="#888888"]
        \\  }
        \\  n0 -> n1 [label="f"]
        \\}
        \\
    );
}

test "under a red frame, the caption stays violet" {
    var c = try fab.Compilation.init(testing.allocator, "G :: f g/+k h\nG :style := f :label \"x\"", preview);
    defer c.deinit();
    var o = try render((try c.sheet()).?);
    defer o.deinit();
    try testing.expect(std.mem.indexOf(u8, o.dot,
        \\    label=<<font point-size="9" color="#8250df">unsupported</font><br/>G>
        \\    pencolor="#d1242f"
    ) != null);
}

test "a warning frames its diagram in amber, and marks its node" {
    try expectDot("K :: (f/*, g) h",
        \\  subgraph cluster_0 {
        \\    label="K"
        \\    pencolor="#bf8700"
        \\    n0 [label="+f", shape=circle, width=0.37, height=0.37, fixedsize=true, fontname="Helvetica-Oblique", fontcolor="#888888"]
        \\    n1 [label="", shape=doublecircle, width=0.10, height=0.10, fixedsize=true, fillcolor="#333333", style="filled"]
        \\    n2 [label="+g", shape=circle, width=0.37, height=0.37, fixedsize=true, fontname="Helvetica-Oblique", fontcolor="#888888"]
        \\    n3 [label="g+", shape=circle, width=0.37, height=0.37, fixedsize=true, fontname="Helvetica-Oblique", fontcolor="#888888", color="#bf8700"]
        \\    n4 [label="h+", shape=circle, width=0.37, height=0.37, fixedsize=true, fontname="Helvetica-Oblique", fontcolor="#888888"]
        \\  }
        \\  n0 -> n1 [label="f"]
        \\  n2 -> n3 [label="g"]
        \\  n3 -> n4 [label="h"]
        \\}
        \\
    );
}

test "a marked edge takes the colour, and a marked dot is filled with it" {
    // No analysis error marks an edge yet: the marks are set by hand.
    var c = try fab.Compilation.init(testing.allocator, "G :: */f", preview);
    defer c.deinit();
    var sheet = (try c.sheet()).?.*;
    var nodes = [_]Style{ sheet.nodes[0], sheet.nodes[1] };
    nodes[0].stroke = .{ .token = .@"error" };
    var edges = [_]Style{sheet.edges[0]};
    edges[0].stroke = .{ .token = .warning };
    sheet.nodes = &nodes;
    sheet.edges = &edges;
    var o = try render(&sheet);
    defer o.deinit();
    try testing.expect(std.mem.indexOf(u8, o.dot, "n0 [label=\"\", shape=circle, width=0.14, height=0.14, fixedsize=true, color=\"#d1242f\", fillcolor=\"#d1242f\", style=\"filled\"]") != null);
    try testing.expect(std.mem.indexOf(u8, o.dot, "n0 -> n1 [label=\"f\", color=\"#bf8700\"]") != null);
}

test "HTML text escapes what an HTML label would read" {
    var out: std.Io.Writer.Allocating = .init(testing.allocator);
    defer out.deinit();
    try to_dot.html(&out.writer, "a<b & \"c\">");
    try testing.expectEqualStrings("a&lt;b &amp; &quot;c&quot;&gt;", out.written());
}

// ---------------------------------------------------------------------------
// Realization of looks the source can't ask for yet. The Sheet is the
// contract, so a hand-made Sheet stands in for the format layer to come.

test "a framed cluster draws its border, label and fill" {
    var c = try fab.Compilation.init(testing.allocator, "G :: f", preview);
    defer c.deinit();
    var sheet = (try c.sheet()).?.*;
    const zones = [_]Style{style(.{ .label = "G", .stroke = .{ .rgb = 0x336699 }, .fill = .{ .token = .accent }, .line = .dashed })};
    sheet.zones = &zones;
    var o = try render(&sheet);
    defer o.deinit();
    try expectBody(
        \\  subgraph cluster_0 {
        \\    label="G"
        \\    pencolor="#336699"
        \\    fillcolor="#1f6feb"
        \\    style="filled,dashed"
        \\    n0 [label="+f", shape=circle, width=0.37, height=0.37, fixedsize=true, fontname="Helvetica-Oblique", fontcolor="#888888"]
        \\    n1 [label="f+", shape=circle, width=0.37, height=0.37, fixedsize=true, fontname="Helvetica-Oblique", fontcolor="#888888"]
        \\  }
        \\  n0 -> n1 [label="f"]
        \\}
        \\
    , o.dot);
}

test "flat zones have no cluster; :as node and table are clusters, with a note" {
    var c = try fab.Compilation.init(testing.allocator, "A :: f\nB :: g\nC :: h", preview);
    defer c.deinit();
    var sheet = (try c.sheet()).?.*;
    const zones = [_]Style{ style(.{ .as = .flat }), style(.{ .as = .node }), style(.{ .as = .table }) };
    sheet.zones = &zones;
    var o = try render(&sheet);
    defer o.deinit();
    try testing.expect(std.mem.indexOf(u8, o.dot, "cluster_0") == null);
    try testing.expect(std.mem.indexOf(u8, o.dot, "cluster_1") != null);
    try testing.expect(std.mem.indexOf(u8, o.dot, "cluster_2") != null);
    try testing.expectEqual(2, o.notes.items.items.len);
    for (o.notes.items.items) |n| try testing.expectEqual(Note.Tag.zone_drawn_as_cluster, n.tag);
}

test "lines and shapes: double, invisible, wavy, approximations" {
    var c = try fab.Compilation.init(testing.allocator, "G :: f g", preview);
    defer c.deinit();
    var sheet = (try c.sheet()).?.*;
    const nodes = [_]Style{
        style(.{ .label = "a", .shape = .stadium }),
        style(.{ .label = "b", .shape = .round, .line = .double, .stroke = .{ .rgb = 0xff0000 } }),
        style(.{ .label = "c", .shape = .document, .line = .wavy }),
    };
    const edges = [_]Style{
        style(.{ .label = "f", .line = .double }),
        style(.{ .label = "g", .line = .none }),
    };
    sheet.nodes = &nodes;
    sheet.edges = &edges;
    var o = try render(&sheet);
    defer o.deinit();
    try expectBody(
        \\  subgraph cluster_0 {
        \\    peripheries=0
        \\    n0 [label="a", shape=box, style="rounded"]
        \\    n1 [label="b", shape=box, color="#ff0000", peripheries=2, style="rounded"]
        \\    n2 [label="c", shape=note]
        \\  }
        \\  n0 -> n1 [label="f", color="#333333:invis:#333333"]
        \\  n1 -> n2 [label="g", style="invis"]
        \\}
        \\
    , o.dot);
    const tags = [_]Note.Tag{ .shape_approximated, .shape_approximated, .wavy_line_drawn_solid };
    try testing.expectEqual(tags.len, o.notes.items.items.len);
    for (o.notes.items.items, tags) |n, t| try testing.expectEqual(t, n.tag);
}

// ---------------------------------------------------------------------------
// The correctness law

/// What a DOT file written by write() says about the graph.
const Read = struct {
    /// Per node, in order: the cluster it was declared in, if any.
    nodes: std.ArrayList(?u32) = .empty,
    /// Per placeholder `z{z}`: its zone, and the cluster it was declared in.
    placeholders: std.ArrayList(struct { u32, u32 }) = .empty,
    edges: std.ArrayList(Edge) = .empty,

    const Edge = struct { source: u32, target: u32, directed: bool, label: []const u8 };

    fn deinit(r: *Read) void {
        r.nodes.deinit(testing.allocator);
        r.edges.deinit(testing.allocator);
        r.placeholders.deinit(testing.allocator);
    }
};

/// Reads back exactly the subset write() produces, line by line; anything
/// else is an error. Edge labels point into `dot`, still escaped.
fn readDot(dot: []const u8) !Read {
    const gpa = testing.allocator;
    var r: Read = .{};
    errdefer r.deinit();
    var cluster: ?u32 = null;
    var edges_started = false;

    if (!std.mem.startsWith(u8, dot, "digraph {\n" ++ header)) return error.BadHeader;
    var lines = std.mem.splitScalar(u8, dot[("digraph {\n" ++ header).len..], '\n');
    while (lines.next()) |raw| {
        const line = std.mem.trim(u8, raw, " ");
        if (std.mem.eql(u8, line, "}")) {
            if (cluster == null) break;
            cluster = null;
        } else if (std.mem.startsWith(u8, line, "subgraph cluster_")) {
            if (cluster != null or edges_started) return error.MisplacedCluster;
            const rest = line["subgraph cluster_".len..];
            cluster = try std.fmt.parseInt(u32, rest[0 .. std.mem.indexOfScalar(u8, rest, ' ') orelse return error.BadCluster], 10);
        } else if (std.mem.startsWith(u8, line, "n")) {
            const ident_end = std.mem.indexOfAny(u8, line, " [") orelse line.len;
            const first = try std.fmt.parseInt(u32, line[1..ident_end], 10);
            const rest = line[ident_end..];
            if (std.mem.startsWith(u8, rest, " -> n")) {
                if (cluster != null) return error.EdgeInsideCluster;
                edges_started = true;
                const t_text = rest[" -> n".len..];
                const t_end = std.mem.indexOfAny(u8, t_text, " [") orelse t_text.len;
                try r.edges.append(gpa, .{
                    .source = first,
                    .target = try std.fmt.parseInt(u32, t_text[0..t_end], 10),
                    .directed = std.mem.indexOf(u8, rest, "dir=none") == null,
                    .label = attr(rest, "label") orelse return error.EdgeWithoutLabel,
                });
            } else {
                if (edges_started) return error.NodeAfterEdges;
                if (first != r.nodes.items.len) return error.NodesOutOfOrder;
                try r.nodes.append(gpa, cluster);
            }
        } else if (std.mem.startsWith(u8, line, "z")) {
            const c = cluster orelse return error.PlaceholderOutsideCluster;
            const ident_end = std.mem.indexOfScalar(u8, line, ' ') orelse return error.BadPlaceholder;
            try r.placeholders.append(gpa, .{ try std.fmt.parseInt(u32, line[1..ident_end], 10), c });
        } else if (cluster == null or line.len == 0) {
            return error.UnexpectedLine;
        }
        // Otherwise a cluster attribute line.
    }
    if (lines.next()) |trailing| if (trailing.len != 0) return error.TrailingText;
    return r;
}

/// The raw (escaped) value of `key="..."` in an attribute list.
fn attr(list: []const u8, key: []const u8) ?[]const u8 {
    var i: usize = 0;
    while (std.mem.indexOfPos(u8, list, i, key)) |at| : (i = at + 1) {
        const before = if (at == 0) ' ' else list[at - 1];
        if (before != '[' and before != ' ') continue;
        const after = at + key.len;
        if (!std.mem.startsWith(u8, list[after..], "=\"")) continue;
        var j = after + 2;
        while (j < list.len and list[j] != '"') : (j += 1) {
            if (list[j] == '\\') j += 1;
        }
        return list[after + 2 .. j];
    }
    return null;
}

fn expectLaw(source: []const u8) !void {
    var c = try fab.Compilation.init(testing.allocator, source, preview);
    defer c.deinit();
    const sheet = (try c.sheet()) orelse return;
    const ir = sheet.ir;
    var o = try render(sheet);
    defer o.deinit();
    var r = readDot(o.dot) catch |err| {
        std.debug.print("unreadable DOT for {s}:\n{s}\n", .{ source, o.dot });
        return err;
    };
    defer r.deinit();

    // Nodes: the same set, each in its owning zone's cluster.
    try testing.expectEqual(ir.nodes.len, r.nodes.items.len);
    for (ir.nodes.items(.zone), r.nodes.items) |zone, cluster| {
        const expected: ?u32 = if (sheet.drawnAs(zone) == .flat) null else @backingInt(zone);
        try testing.expectEqual(expected, cluster);
    }
    // Edges: the same multiset, in order, with ends, direction and label.
    try testing.expectEqual(ir.edges.len, r.edges.items.len);
    for (ir.edges.items(.source), ir.edges.items(.target), ir.edges.items(.directed), sheet.edges, r.edges.items) |s, t, d, look, e| {
        try testing.expectEqual(@backingInt(s), e.source);
        try testing.expectEqual(@backingInt(t), e.target);
        try testing.expectEqual(d, e.directed);
        var escaped: std.Io.Writer.Allocating = .init(testing.allocator);
        defer escaped.deinit();
        try to_dot.quoted(&escaped.writer, look.label);
        const q = escaped.written();
        try testing.expectEqualStrings(q[1 .. q.len - 1], e.label);
    }
    // One placeholder per placeholder zone, in its own cluster.
    var expected_placeholders: usize = 0;
    for (0..ir.zones.len) |z| {
        if (sheet.drawnAs(@fromBackingInt(@as(u32, @intCast(z)))) != .placeholder) continue;
        expected_placeholders += 1;
        var found: usize = 0;
        for (r.placeholders.items) |p| found += @intFromBool(p[0] == z and p[1] == z);
        try testing.expectEqual(1, found);
    }
    try testing.expectEqual(expected_placeholders, r.placeholders.items.len);
    // What is left out is accounted for.
    var cell_notes: usize = 0;
    for (o.notes.items.items) |n| cell_notes += @intFromBool(n.tag == .cell_not_drawn);
    try testing.expectEqual(ir.cells.len, cell_notes);
}

/// Every program of the spec, one per entry, valid in the current syntax.
pub const spec_programs = [_][]const u8{
    "G :: f",
    "G :: f g h",
    "G :: f, g",
    "G :: f +(g, h)",
    "G :: (f, g)+ h",
    "G :: f (g h)",
    "G :: f/e",
    "G :: f/",
    "G :: f/ g",
    "G :: #A/f/#B/, #B/g/#C/",
    "G :: f/? +(fg g, fh h)",
    "G :: f/? +(g, h)? k",
    "G :: f/! +(g, h)! k",
    "G :: */f g h/*",
    "G :: #A/f/#B",
    "G :: #A",
    "Sq :: +(f h, g k)+",
    "Tri :: +(f g, h)+",
    "Iso :: f/g",
    "Endo :: f/f",
    "Cyc :: f/g/h",
    "Pair :: +(f, g)+",
    "Nat :: +(f, g)+ | f/α/g",
    "Eq :: +(f, g)+ | f/α/g/β",
    "Mod :: +(f, g)+ | f/(α, β)/g | α/m/β",
    "Id :: #A/f/#A | f/α/#A",
    "Ud :: #A/f/#B/, #B/g/#A | f/α/g",
    "Pr :: #X/(g1, f, g2), f+/(p1/g1+, p2/g2+)",
    "If :: f/? +(fg g, fh h)? k",
    "While :: f/? +(b/b, e k)",
    "Exit :: f/? +(fg g/*, fh h k)",
    "Loop :: f/? +(fg g, fh h k/+f)",
    "Par :: */s/! +(a, b)! t/*",
    "A :: f g\nB :: h/A.+f",
    "G :: f\nH :: g /k\nreview :: a b",
    "T :: #UUID7, #String\nUser :: @/(id/T.#UUID7, name/T.#String)",
    \\Order :: {
    \\  */receive/#Received validate/? +(
    \\      yes/#Accepted fork/! +(
    \\          charge/? +(paid, declined/#Waiting/retry)
    \\        , reserve/? +(reserved, short/#Backorder/restock)
    \\      )! ready/#Ready ship/#Shipped close/*
    \\    , no/#Rejected notify/*
    \\  )
    \\}
    ,
};

test "the law holds on every spec program" {
    for (spec_programs) |source| expectLaw(source) catch |err| {
        std.debug.print("law fails for:\n{s}\n", .{source});
        return err;
    };
}

test "the law holds on random programs, broken ones included" {
    // Fragments glued at random: most programs are invalid, and the preview
    // IR, holes and all, must still read back exactly.
    const pieces = [_][]const u8{ "f", "g", "h", "f/", "+f", "g+", " ", ", ", "(", ")", "?", "!", "*", "#A", "#B", "/", " | ", "α", "A.", "\n", "B :: ", "{", "}" };
    var prng: std.Random.DefaultPrng = .init(0xfab);
    const random = prng.random();
    var buf: [256]u8 = undefined;
    for (0..2000) |_| {
        var len: usize = 0;
        const head = "A :: ";
        @memcpy(buf[0..head.len], head);
        len = head.len;
        for (0..random.intRangeAtMost(usize, 1, 12)) |_| {
            const p = pieces[random.uintLessThan(usize, pieces.len)];
            if (len + p.len > buf.len) break;
            @memcpy(buf[len..][0..p.len], p);
            len += p.len;
        }
        expectLaw(buf[0..len]) catch |err| {
            std.debug.print("law fails for:\n{s}\n", .{buf[0..len]});
            return err;
        };
    }
}

test "out of memory is reported, never a crash or a leak" {
    const Case = struct {
        fn run(gpa: std.mem.Allocator, sheet: *const fab.Sheet) !void {
            var out: std.Io.Writer.Allocating = .init(gpa);
            defer out.deinit();
            var notes: Note.List = .init(gpa);
            defer notes.deinit();
            // An allocating writer reports its own failure as WriteFailed.
            to_dot.write(sheet, &out.writer, &notes) catch |err| return switch (err) {
                error.WriteFailed => error.OutOfMemory,
                else => err,
            };
        }
    };
    var c = try fab.Compilation.init(testing.allocator, "Iso :: +(f, g)+ | f/α/g/β", preview);
    defer c.deinit();
    const sheet = (try c.sheet()).?;
    try testing.checkAllAllocationFailures(testing.allocator, Case.run, .{sheet});
}
