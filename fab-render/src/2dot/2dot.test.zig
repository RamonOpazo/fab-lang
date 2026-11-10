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

/// Every file names what made it (release.md §2), then opens the graph.
const prologue = "// fab " ++ fab.version ++ "\ndigraph {\n";

/// Every file starts with these defaults, so goldens show only the body.
const header =
    \\  graph [compound=true, fontname="Helvetica", fontsize=11, fontcolor="#333333", nodesep=0.45, ranksep=0.45, pad=0.2]
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
    const start = prologue ++ header;
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
    try expectDot("J :: f\nJ :style { f :label \"x\" }\nJ :prove { :strict }",
        \\  subgraph cluster_0 {
        \\    label=<<font point-size="9" color="#8250df">unsupported</font><br/>J>
        \\    pencolor="#8250df"
        \\    n0 [label="+f", shape=circle, width=0.37, height=0.37, fixedsize=true, fontname="Helvetica-Oblique", fontcolor="#888888"]
        \\    n1 [label="f+", shape=circle, width=0.37, height=0.37, fixedsize=true, fontname="Helvetica-Oblique", fontcolor="#888888"]
        \\  }
        \\  n0 -> n1 [label="x"]
        \\}
        \\
    );
}

test "under a red frame, the caption stays violet" {
    var c = try fab.Compilation.init(testing.allocator, "G :: f g/+k h\nG :style { f :label \"x\" }\nG :prove { :strict }", preview);
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
    // No analysis error marks an edge yet: the IR and its issues are made
    // by hand, and styled with the prelude.
    var b: fab.Ir.Builder = .init(testing.allocator);
    errdefer b.deinit();
    const z = try b.addZone(.{ .name = try b.addString("G") });
    const start = try b.addNode(.{ .kind = .null_node, .name = null, .zone = z, .canonical = null });
    const end = try b.addNode(.{ .kind = .plain, .name = null, .zone = z, .canonical = .{ .edge = @fromBackingInt(@as(u32, 0)), .side = .cod } });
    const f = try b.addEdge(.{ .name = try b.addString("f"), .source = start, .target = end, .directed = true, .zone = z });
    try b.addIssue(.{ .subject = .{ .node = start }, .err = .{ .analysis = 0 } });
    try b.addIssue(.{ .subject = .{ .edge = f }, .err = .{ .analysis = 1 } });
    var ir = try b.finish();
    defer ir.deinit(testing.allocator);
    var c = try fab.Compilation.init(testing.allocator, "", preview);
    defer c.deinit();
    var sheet = try fab.Styler.style(testing.allocator, &ir, .{ .env = &(try c.analysis()).env }, &.{ .@"error", .warning });
    defer sheet.deinit();
    var o = try render(&sheet);
    defer o.deinit();
    try testing.expect(std.mem.indexOf(u8, o.dot, "n0 [label=\"\", shape=circle, width=0.14, height=0.14, fixedsize=true, color=\"#d1242f\", fillcolor=\"#d1242f\", style=\"filled\"]") != null);
    try testing.expect(std.mem.indexOf(u8, o.dot, "n0 -> n1 [label=\"f\", color=\"#bf8700\"]") != null);
}

test "a diagram held by another is a cluster inside it, and edges stop at its border" {
    // A and B are Db's members (statements.md §23.2): their clusters nest in
    // Db's, and their nodes in Db are points inside them, which h and k
    // reach through the border.
    try expectDot("A :: */f\nB :: */g\nDb :: A/h/B, k/A",
        \\  subgraph cluster_2 {
        \\    peripheries=0
        \\    n6 [label="+k", shape=circle, width=0.37, height=0.37, fixedsize=true, fontname="Helvetica-Oblique", fontcolor="#888888"]
        \\    subgraph cluster_0 {
        \\      peripheries=0
        \\      label=""
        \\      style=""
        \\      n0 [label="", shape=circle, width=0.14, height=0.14, fixedsize=true, fillcolor="#333333", style="filled"]
        \\      n1 [label="f+", shape=circle, width=0.37, height=0.37, fixedsize=true, fontname="Helvetica-Oblique", fontcolor="#888888"]
        \\      n4 [label="", shape=point, width=0.01, height=0.01, style="invis"]
        \\    }
        \\    subgraph cluster_1 {
        \\      peripheries=0
        \\      label=""
        \\      style=""
        \\      n2 [label="", shape=circle, width=0.14, height=0.14, fixedsize=true, fillcolor="#333333", style="filled"]
        \\      n3 [label="g+", shape=circle, width=0.37, height=0.37, fixedsize=true, fontname="Helvetica-Oblique", fontcolor="#888888"]
        \\      n5 [label="", shape=point, width=0.01, height=0.01, style="invis"]
        \\    }
        \\  }
        \\  n0 -> n1 [label="f"]
        \\  n2 -> n3 [label="g"]
        \\  n4 -> n5 [label="h", ltail=cluster_0, lhead=cluster_1]
        \\  n6 -> n4 [label="k", lhead=cluster_0]
        \\}
        \\
    );
}

test "a member's cluster writes every attribute, or it would wear its container's" {
    var c = try fab.Compilation.init(testing.allocator, "A :: f\nB :: A\nA :style { :marks [], :stroke [#ff0000] }\nB :style { :marks [], :fill [#00ff00], :line [dashed] }", preview);
    defer c.deinit();
    var o = try render((try c.sheet()).?);
    defer o.deinit();
    try expectBody(
        \\  subgraph cluster_1 {
        \\    label="B"
        \\    peripheries=0
        \\    fillcolor="#00ff00"
        \\    style="filled,dashed"
        \\    subgraph cluster_0 {
        \\      label="A"
        \\      pencolor="#ff0000"
        \\      peripheries=1
        \\      fontcolor="#333333"
        \\      style=""
        \\      n0 [label="+f", shape=circle, width=0.37, height=0.37, fixedsize=true, fontname="Helvetica-Oblique", fontcolor="#888888"]
        \\      n1 [label="f+", shape=circle, width=0.37, height=0.37, fixedsize=true, fontname="Helvetica-Oblique", fontcolor="#888888"]
        \\      n2 [label="", shape=point, width=0.01, height=0.01, style="invis"]
        \\    }
        \\  }
        \\  n0 -> n1 [label="f"]
        \\}
        \\
    , o.dot);
}

test "an edge from inside a diagram to its node is not clipped; a flat diagram's node is drawn" {
    // f+ is inside A's cluster, where Graphviz can't clip; B is flat, so its
    // node in C is an ordinary node, labelled with its name.
    var c = try fab.Compilation.init(testing.allocator, "A :: f\nB :: g\nC :: A.f+/h/A, k/B\nB :style { :marks [], :as [flat] }", preview);
    defer c.deinit();
    var o = try render((try c.sheet()).?);
    defer o.deinit();
    try testing.expect(std.mem.indexOf(u8, o.dot, "[label=\"h\"]") != null);
    try testing.expect(std.mem.indexOf(u8, o.dot, "[label=\"k\"]") != null);
    try testing.expect(std.mem.indexOf(u8, o.dot, "[label=\"B\", shape=") != null);
    try testing.expect(std.mem.indexOf(u8, o.dot, "cluster_1") == null);
}

test "a marked diagram that owns no node still shows its frame" {
    // Db's edge joins two of A's nodes; its unsupported proof marks Db.
    try expectDot("A :: f g\nDb :: A.g+/h/A.+f\nDb :prove { :strict }",
        \\  subgraph cluster_0 {
        \\    peripheries=0
        \\    n0 [label="+f", shape=circle, width=0.37, height=0.37, fixedsize=true, fontname="Helvetica-Oblique", fontcolor="#888888"]
        \\    n1 [label="f+", shape=circle, width=0.37, height=0.37, fixedsize=true, fontname="Helvetica-Oblique", fontcolor="#888888"]
        \\    n2 [label="g+", shape=circle, width=0.37, height=0.37, fixedsize=true, fontname="Helvetica-Oblique", fontcolor="#888888"]
        \\  }
        \\  subgraph cluster_1 {
        \\    label=<<font point-size="9" color="#8250df">unsupported</font><br/>Db>
        \\    pencolor="#8250df"
        \\    a1 [label="", shape=point, width=0.01, height=0.01, style="invis"]
        \\  }
        \\  n0 -> n1 [label="f"]
        \\  n1 -> n2 [label="g"]
        \\  n2 -> n0 [label="h"]
        \\}
        \\
    );
}

test "HTML text escapes what an HTML label would read" {
    var out: std.Io.Writer.Allocating = .init(testing.allocator);
    defer out.deinit();
    try to_dot.html(&out.writer, "a<b & \"c\">");
    try testing.expectEqualStrings("a&lt;b &amp; &quot;c&quot;&gt;", out.written());
}

// ---------------------------------------------------------------------------
// Looks a program asks for. `:marks []` keeps the layer's own issue, still
// unsupported, from framing the diagram.

test "a framed cluster draws its border, label and fill" {
    var c = try fab.Compilation.init(testing.allocator, "G :: f\nG :style { :marks [], :stroke [#336699], :fill [accent], :line [dashed] }", preview);
    defer c.deinit();
    var o = try render((try c.sheet()).?);
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
    var c = try fab.Compilation.init(testing.allocator,
        \\A :: f
        \\B :: g
        \\C :: h
        \\A :style { :marks [], :as [flat] }
        \\B :style { :marks [], :as [node] }
        \\C :style { :marks [], :as [table] }
    , preview);
    defer c.deinit();
    var o = try render((try c.sheet()).?);
    defer o.deinit();
    try testing.expect(std.mem.indexOf(u8, o.dot, "cluster_0") == null);
    try testing.expect(std.mem.indexOf(u8, o.dot, "cluster_1") != null);
    try testing.expect(std.mem.indexOf(u8, o.dot, "cluster_2") != null);
    try testing.expectEqual(2, o.notes.items.items.len);
    for (o.notes.items.items) |n| try testing.expectEqual(Note.Tag.zone_drawn_as_cluster, n.tag);
}

test "lines and shapes: double, invisible, wavy, approximations" {
    var c = try fab.Compilation.init(testing.allocator,
        \\G :: f g
        \\G :style {
        \\    :marks [],
        \\    +f { :label "a", :shape [stadium] },
        \\    f+ { :label "b", :shape [round], :line [double], :stroke [#ff0000] },
        \\    g+ { :label "c", :shape [document], :line [wavy] },
        \\    f  :arrow [/double/>],
        \\    g  :arrow [//>]
        \\}
    , preview);
    defer c.deinit();
    var o = try render((try c.sheet()).?);
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

test "lines: triple, as three parallel lines" {
    var c = try fab.Compilation.init(testing.allocator, "G :: f\nG :style { :marks [], +f { :label \"a\", :line [triple] }, f+ :label \"b\", f :arrow [/triple/>] }", preview);
    defer c.deinit();
    var o = try render((try c.sheet()).?);
    defer o.deinit();
    try expectBody(
        \\  subgraph cluster_0 {
        \\    peripheries=0
        \\    n0 [label="a", shape=circle, width=0.35, height=0.35, fixedsize=true, peripheries=3]
        \\    n1 [label="b", shape=circle, width=0.35, height=0.35, fixedsize=true]
        \\  }
        \\  n0 -> n1 [label="f", color="#333333:invis:#333333:invis:#333333"]
        \\}
        \\
    , o.dot);
}

// ---------------------------------------------------------------------------
// The correctness law

/// What a DOT file written by write() says about the graph.
const Read = struct {
    /// Per node, by index: the cluster it was declared in, if any.
    nodes: std.AutoHashMapUnmanaged(u32, ?u32) = .empty,
    /// Per cluster: the cluster it was declared in, if any.
    clusters: std.AutoHashMapUnmanaged(u32, ?u32) = .empty,
    /// Per placeholder `z{z}`: its zone, and the cluster it was declared in.
    placeholders: std.ArrayList(struct { u32, u32 }) = .empty,
    /// Per anchor `a{z}` of a framed zone with nothing in it: the same.
    anchors: std.ArrayList(struct { u32, u32 }) = .empty,
    edges: std.ArrayList(Edge) = .empty,

    const Edge = struct { source: u32, target: u32, directed: bool, label: []const u8, tail: ?u32, head: ?u32 };

    fn deinit(r: *Read) void {
        r.nodes.deinit(testing.allocator);
        r.clusters.deinit(testing.allocator);
        r.edges.deinit(testing.allocator);
        r.placeholders.deinit(testing.allocator);
        r.anchors.deinit(testing.allocator);
    }
};

/// Reads back exactly the subset write() produces, line by line; anything
/// else is an error. Edge labels point into `dot`, still escaped.
fn readDot(dot: []const u8) !Read {
    const gpa = testing.allocator;
    var r: Read = .{};
    errdefer r.deinit();
    var open: std.ArrayList(u32) = .empty;
    defer open.deinit(gpa);
    var edges_started = false;

    if (!std.mem.startsWith(u8, dot, prologue ++ header)) return error.BadHeader;
    var lines = std.mem.splitScalar(u8, dot[(prologue ++ header).len..], '\n');
    while (lines.next()) |raw| {
        const line = std.mem.trim(u8, raw, " ");
        // Each line is indented by what is open around it.
        const depth = open.items.len + @intFromBool(!std.mem.eql(u8, line, "}"));
        if (line.len > 0 and raw.len - line.len != 2 * depth) return error.BadIndentation;
        const cluster: ?u32 = if (open.items.len > 0) open.items[open.items.len - 1] else null;
        if (std.mem.eql(u8, line, "}")) {
            if (open.pop() == null) break;
        } else if (std.mem.startsWith(u8, line, "subgraph cluster_")) {
            if (edges_started) return error.MisplacedCluster;
            const rest = line["subgraph cluster_".len..];
            const z = try std.fmt.parseInt(u32, rest[0 .. std.mem.indexOfScalar(u8, rest, ' ') orelse return error.BadCluster], 10);
            if ((try r.clusters.fetchPut(gpa, z, cluster)) != null) return error.ClusterTwice;
            try open.append(gpa, z);
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
                    .tail = try clusterAttr(rest, "ltail"),
                    .head = try clusterAttr(rest, "lhead"),
                });
            } else {
                if (edges_started) return error.NodeAfterEdges;
                if ((try r.nodes.fetchPut(gpa, first, cluster)) != null) return error.NodeTwice;
            }
        } else if (std.mem.startsWith(u8, line, "z") or std.mem.startsWith(u8, line, "a")) {
            const c = cluster orelse return error.MarkOutsideCluster;
            const ident_end = std.mem.indexOfScalar(u8, line, ' ') orelse return error.BadMark;
            const list = if (line[0] == 'z') &r.placeholders else &r.anchors;
            try list.append(gpa, .{ try std.fmt.parseInt(u32, line[1..ident_end], 10), c });
        } else if (cluster == null or line.len == 0) {
            return error.UnexpectedLine;
        }
        // Otherwise a cluster attribute line.
    }
    if (open.items.len > 0) return error.ClusterNotClosed;
    if (lines.next()) |trailing| if (trailing.len != 0) return error.TrailingText;
    return r;
}

/// `key=cluster_{z}` in an edge's attribute list: z.
fn clusterAttr(list: []const u8, key: []const u8) !?u32 {
    const at = std.mem.indexOf(u8, list, key) orelse return null;
    const rest = list[at + key.len ..];
    if (!std.mem.startsWith(u8, rest, "=cluster_")) return error.BadClip;
    const digits = rest["=cluster_".len..];
    const end = std.mem.indexOfAny(u8, digits, ",]") orelse return error.BadClip;
    return try std.fmt.parseInt(u32, digits[0..end], 10);
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

/// Where the law expects each thing, from the IR and the Sheet alone.
const Expected = struct {
    ir: *const fab.Ir,
    grouped: []bool,
    written: []bool,
    anchor: []bool,

    fn init(sheet: *const fab.Sheet) !Expected {
        const gpa = testing.allocator;
        const ir = sheet.ir;
        const n = ir.zones.len;
        const e: Expected = .{ .ir = ir, .grouped = try gpa.alloc(bool, n), .written = try gpa.alloc(bool, n), .anchor = try gpa.alloc(bool, n) };
        for (0..n) |z| {
            const v = sheet.style(.{ .zone = @fromBackingInt(@as(u32, @intCast(z))) });
            const as = v.label(enum { flat, cluster, node, table }, sheet.descriptor(":as").?);
            const placeholder = ir.zones.items(.placeholder)[z];
            e.grouped[z] = placeholder or !(as == .value and as.value == .flat);
            const framed = e.grouped[z] and (v.color(sheet.descriptor(":stroke").?) != null or v.color(sheet.descriptor(":fill").?) != null);
            // Members come first: a diagram names only earlier ones.
            var content = placeholder;
            for (ir.nodes.items(.zone), ir.nodes.items(.diagram)) |owner, diagram| {
                const home = if (diagram) |d| (if (e.grouped[@backingInt(d)]) d else owner) else owner;
                content = content or @backingInt(home) == z;
            }
            for (ir.zones.items(.container), 0..) |c, m| {
                if (c != null and @backingInt(c.?) == z and e.written[m]) content = true;
            }
            e.written[z] = content or framed;
            e.anchor[z] = framed and !content;
        }
        return e;
    }

    fn deinit(e: Expected) void {
        testing.allocator.free(e.grouped);
        testing.allocator.free(e.written);
        testing.allocator.free(e.anchor);
    }

    /// The innermost cluster around `zone`'s contents: its own, or its
    /// containers'.
    fn around(e: Expected, zone: ?fab.Ir.ZoneIndex) ?u32 {
        var z = zone;
        while (z) |inside| : (z = e.ir.zones.items(.container)[@backingInt(inside)]) {
            if (e.grouped[@backingInt(inside)]) return @backingInt(inside);
        }
        return null;
    }

    fn standsFor(e: Expected, diagram: ?fab.Ir.ZoneIndex) ?fab.Ir.ZoneIndex {
        const d = diagram orelse return null;
        return if (e.grouped[@backingInt(d)]) d else null;
    }

    fn clip(e: Expected, n: fab.Ir.NodeIndex, other: fab.Ir.NodeIndex) ?u32 {
        const d = e.standsFor(e.ir.nodes.items(.diagram)[@backingInt(n)]) orelse return null;
        const o = @backingInt(other);
        const start = e.standsFor(e.ir.nodes.items(.diagram)[o]) orelse e.ir.nodes.items(.zone)[o];
        var z: ?fab.Ir.ZoneIndex = start;
        while (z) |inside| : (z = e.ir.zones.items(.container)[@backingInt(inside)]) if (inside == d) return null;
        return @backingInt(d);
    }
};

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

    const zones = try Expected.init(sheet);
    defer zones.deinit();

    // Clusters: each inside its first container's, or around it.
    for (0..ir.zones.len) |z| {
        const read = r.clusters.get(@intCast(z));
        if (!zones.written[z] or !zones.grouped[z]) {
            try testing.expectEqual(null, read);
            continue;
        }
        try testing.expectEqual(@as(??u32, zones.around(ir.zones.items(.container)[z])), read);
    }
    // Nodes: the same set, each in its owning zone's cluster, or in its
    // diagram's when it stands for one drawn as a cluster.
    try testing.expectEqual(ir.nodes.len, r.nodes.count());
    for (ir.nodes.items(.zone), ir.nodes.items(.diagram), 0..) |zone, diagram, n| {
        const expected = if (zones.standsFor(diagram)) |d| @backingInt(d) else zones.around(zone);
        try testing.expectEqual(@as(??u32, expected), r.nodes.get(@intCast(n)));
    }
    // Edges: the same multiset, in order, with ends, direction and label;
    // an end at a diagram's node stops at its cluster, unless the other end
    // is inside it.
    try testing.expectEqual(ir.edges.len, r.edges.items.len);
    for (ir.edges.items(.source), ir.edges.items(.target), ir.edges.items(.directed), r.edges.items, 0..) |s, t, d, e, i| {
        const label = sheet.style(.{ .edge = @fromBackingInt(@as(u32, @intCast(i))) }).text(sheet.descriptor(":label").?).?;
        try testing.expectEqual(@backingInt(s), e.source);
        try testing.expectEqual(@backingInt(t), e.target);
        try testing.expectEqual(d, e.directed);
        try testing.expectEqual(zones.clip(s, t), e.tail);
        try testing.expectEqual(zones.clip(t, s), e.head);
        var escaped: std.Io.Writer.Allocating = .init(testing.allocator);
        defer escaped.deinit();
        try to_dot.quoted(&escaped.writer, label);
        const q = escaped.written();
        try testing.expectEqualStrings(q[1 .. q.len - 1], e.label);
    }
    // One placeholder per placeholder zone, in its own cluster.
    var expected_placeholders: usize = 0;
    for (0..ir.zones.len) |z| {
        if (!ir.zones.items(.placeholder)[z]) continue;
        expected_placeholders += 1;
        var found: usize = 0;
        for (r.placeholders.items) |p| found += @intFromBool(p[0] == z and p[1] == z);
        try testing.expectEqual(1, found);
    }
    try testing.expectEqual(expected_placeholders, r.placeholders.items.len);
    // One anchor per framed cluster with nothing else in it, so its frame
    // shows.
    var expected_anchors: usize = 0;
    for (0..ir.zones.len) |z| {
        if (!zones.anchor[z]) continue;
        expected_anchors += 1;
        var found: usize = 0;
        for (r.anchors.items) |p| found += @intFromBool(p[0] == z and p[1] == z);
        try testing.expectEqual(1, found);
    }
    try testing.expectEqual(expected_anchors, r.anchors.items.len);
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
    "A :: */f\nB :: */g\nDb :: A/h/B\nDb :prove { :strict }",
    "A :: */f\nB :: */g\nDb :: A/h/B\nRepo :: Db, A/k/#X\nOuter :: Repo, Db/m",
    "A :: f\nB :: A/g/A, A.f+/h/A",
    "T :: #UUID7, #String\nUser :: */(id/T.#UUID7, name/T.#String)",
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

// ---------------------------------------------------------------------------
// What Graphviz reads of the Sheet, and what it notes (statements.md §22.12)

fn countNotes(notes: []const Note, tag: Note.Tag, name: []const u8) usize {
    var n: usize = 0;
    for (notes) |note| n += @intFromBool(note.tag == tag and std.mem.eql(u8, note.name, name));
    return n;
}

test "what the author binds and graphviz doesn't draw is noted, once per diagram" {
    var c = try fab.Compilation.init(testing.allocator,
        \\:Shape :: [star]
        \\G :: f g
        \\G :style { :marks [], (f, g) :bend [inner], f+ :shape [star], g :arrow [epi] }
        \\H :: h
        \\H :style { :marks [], h :bend [outer] }
    , preview);
    defer c.deinit();
    var o = try render((try c.sheet()).?);
    defer o.deinit();
    const notes = o.notes.items.items;
    // :bend, bound on two edges of G and one of H: one note per diagram.
    try testing.expectEqual(2, countNotes(notes, .descriptor_not_drawn, ":bend"));
    // [base]'s bindings are never noted: :font, :size, :pen…
    var undrawn: usize = 0;
    for (notes) |n| undrawn += @intFromBool(n.tag == .descriptor_not_drawn);
    try testing.expectEqual(2, undrawn);
    try testing.expectEqual(1, countNotes(notes, .label_not_drawn, "star"));
    try testing.expectEqual(1, countNotes(notes, .arrow_ends_not_drawn, ""));
    // A label with no meaning here draws as none: the label alone.
    try testing.expect(std.mem.indexOf(u8, o.dot, "n1 [label=\"f+\", shape=plaintext") != null);
}

test ":hide, a bold face, and a themed diagram's own colours" {
    var c = try fab.Compilation.init(testing.allocator,
        \\G :: #A/f/#B
        \\G :style { :marks [], :theme [dark], #A :hide, #B :face [bold] }
    , preview);
    defer c.deinit();
    var o = try render((try c.sheet()).?);
    defer o.deinit();
    try testing.expectEqual(0, o.notes.items.items.len);
    // [dark]'s ink, not the header's [base] one.
    try testing.expect(std.mem.indexOf(u8, o.dot, "n0 [label=\"A\", shape=circle, width=0.35, height=0.35, fixedsize=true, fontcolor=\"#dddddd\", color=\"#dddddd\", style=\"invis\"]") != null);
    try testing.expect(std.mem.indexOf(u8, o.dot, "fontname=\"Helvetica-Bold\"") != null);
    try testing.expect(std.mem.indexOf(u8, o.dot, "fillcolor=\"#1e1e1e\"") != null);
}
