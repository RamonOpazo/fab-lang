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

fn expectDot(source: []const u8, expected: []const u8) !void {
    var c = try fab.Compilation.init(testing.allocator, source, preview);
    defer c.deinit();
    var o = try render((try c.sheet()).?);
    defer o.deinit();
    try testing.expectEqualStrings(expected, o.dot);
}

// ---------------------------------------------------------------------------
// Golden outputs

test "a chain: canonical labels, in the canonical class" {
    try expectDot("G :: f g",
        \\digraph {
        \\  subgraph cluster_0 {
        \\    peripheries=0
        \\    n0 [label="+f", shape=plaintext, fontname="Times-Italic", fontcolor="#888888"]
        \\    n1 [label="f+", shape=plaintext, fontname="Times-Italic", fontcolor="#888888"]
        \\    n2 [label="g+", shape=plaintext, fontname="Times-Italic", fontcolor="#888888"]
        \\  }
        \\  n0 -> n1 [label="f"]
        \\  n1 -> n2 [label="g"]
        \\}
        \\
    );
}

test "names are labels without their #; identifiers stay n{i}" {
    try expectDot("G :: #A f #B? g",
        \\digraph {
        \\  subgraph cluster_0 {
        \\    peripheries=0
        \\    n0 [label="A", shape=plaintext]
        \\    n1 [label="B", shape=diamond]
        \\    n2 [label="g+", shape=plaintext, fontname="Times-Italic", fontcolor="#888888"]
        \\  }
        \\  n0 -> n1 [label="f"]
        \\  n1 -> n2 [label="g"]
        \\}
        \\
    );
}

test "kinds: null is a small circle, parallel a bar, choice a diamond" {
    try expectDot("G :: *f! (g, h)? k",
        \\digraph {
        \\  subgraph cluster_0 {
        \\    peripheries=0
        \\    n0 [label="", xlabel="+f", shape=circle, width=0.15, height=0.15, fixedsize=true, fontname="Times-Italic", fontcolor="#888888"]
        \\    n1 [label="", xlabel="f+", shape=box, width=0.5, height=0.06, fixedsize=true, fontname="Times-Italic", fontcolor="#888888", fillcolor="#000000", style="filled"]
        \\    n2 [label="g+", shape=diamond, fontname="Times-Italic", fontcolor="#888888"]
        \\    n3 [label="k+", shape=plaintext, fontname="Times-Italic", fontcolor="#888888"]
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
        \\digraph {
        \\  subgraph cluster_0 {
        \\    peripheries=0
        \\    n0 [label="+f", shape=plaintext, fontname="Times-Italic", fontcolor="#888888"]
        \\    n1 [label="f+", shape=plaintext, fontname="Times-Italic", fontcolor="#888888"]
        \\    n2 [label="g+", shape=plaintext, fontname="Times-Italic", fontcolor="#888888"]
        \\  }
        \\  subgraph cluster_1 {
        \\    peripheries=0
        \\    n3 [label="+h", shape=plaintext, fontname="Times-Italic", fontcolor="#888888"]
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
        \\digraph {
        \\  subgraph cluster_0 {
        \\    peripheries=0
        \\    n0 [label="+f", shape=plaintext, fontname="Times-Italic", fontcolor="#888888"]
        \\    n1 [label="f+", shape=plaintext, fontname="Times-Italic", fontcolor="#888888"]
        \\  }
        \\  n0 -> n1 [label="f", dir=none]
        \\}
        \\
    );
}

test "holes are dashed circles" {
    try expectDot("G :: f g/+k h",
        \\digraph {
        \\  subgraph cluster_0 {
        \\    peripheries=0
        \\    n0 [label="+f", shape=plaintext, fontname="Times-Italic", fontcolor="#888888"]
        \\    n1 [label="f+", shape=circle, fontname="Times-Italic", fontcolor="#888888", style="dashed"]
        \\    n2 [label="h+", shape=plaintext, fontname="Times-Italic", fontcolor="#888888"]
        \\  }
        \\  n0 -> n1 [label="f"]
        \\  n1 -> n2 [label="h"]
        \\}
        \\
    );
}

test "cells are left out, with one note each" {
    var c = try fab.Compilation.init(testing.allocator, "Iso :: f, +f/g/f+, [f α/β g]", preview);
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
    try testing.expectEqualStrings(
        \\digraph {
        \\  subgraph cluster_0 {
        \\    label="G"
        \\    pencolor="#336699"
        \\    fillcolor="#1f6feb"
        \\    style="filled,dashed"
        \\    n0 [label="+f", shape=plaintext, fontname="Times-Italic", fontcolor="#888888"]
        \\    n1 [label="f+", shape=plaintext, fontname="Times-Italic", fontcolor="#888888"]
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
    try testing.expectEqualStrings(
        \\digraph {
        \\  subgraph cluster_0 {
        \\    peripheries=0
        \\    n0 [label="a", shape=box, style="rounded"]
        \\    n1 [label="b", shape=box, color="#ff0000", peripheries=2, style="rounded"]
        \\    n2 [label="c", shape=note]
        \\  }
        \\  n0 -> n1 [label="f", color="#000000:invis:#000000"]
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
    edges: std.ArrayList(Edge) = .empty,

    const Edge = struct { source: u32, target: u32, directed: bool, label: []const u8 };

    fn deinit(r: *Read) void {
        r.nodes.deinit(testing.allocator);
        r.edges.deinit(testing.allocator);
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

    var lines = std.mem.splitScalar(u8, dot, '\n');
    if (!std.mem.eql(u8, lines.next().?, "digraph {")) return error.BadHeader;
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
    // What is left out is accounted for.
    var cell_notes: usize = 0;
    for (o.notes.items.items) |n| cell_notes += @intFromBool(n.tag == .cell_not_drawn);
    try testing.expectEqual(ir.cells.len, cell_notes);
}

/// Every program of the spec, one per entry.
pub const spec_programs = [_][]const u8{
    "G :: f",
    "G :: f g h",
    "G :: f, g",
    "G :: f (g, h)",
    "G :: (f, g) h",
    "G :: f (g h)",
    "G :: f/e",
    "G :: f/f g h/h",
    "G :: (f g)/h",
    "G :: f/",
    "G :: f/ g",
    "G :: #A f/ #B, #B g/ #C",
    "G :: f? (fg g, fh h)",
    "G :: f?(g, h)",
    "G :: f? (g, h)? k",
    "G :: f! (g, h)! k",
    "G :: *f g h*",
    "G :: *(f, g) h",
    "G :: (f*, g) h",
    "Sq :: f h, +f/g k/h+",
    "Tri :: f g, +f/h/g+",
    "Iso :: f/g",
    "Endo :: f/f",
    "Pair :: f, +f/g/f+",
    "Nat :: f, +f/g/f+, [f α g]",
    "Iso2 :: f, +f/g/f+, [f α/β g]",
    "If :: f? (fg g, fh h)? k",
    "While :: f? (b/f+, e)",
    "Exit :: f? (fg g*, fh h) k",
    "Loop :: f? (fg g/g, fh h/h' k/+f)",
    "Par :: *s! (a, b)! t*",
    "A :: f g\nB :: h/A.+f",
    "A :: f g\nB :: h/(A.+f)",
    "G :: #A f #B",
    "G :: #A",
    "T :: #UUID7, #DTZ, #String, #JSONB",
    "T :: #UUID7, #DTZ, #String\nUser :: @ (id T.#UUID7, created_at T.#DTZ, name T.#String)",
    "Db :: Document owner User",
    \\Order :: *receive #Received validate #Valid? (
    \\    yes #Accepted! (
    \\        charge #Charged? (paid, declined #Waiting retry/charge+)
    \\      , reserve #InStock? (reserved, short #Backorder restock/reserve+)
    \\    )! #Ready ship #Shipped close*
    \\  , no #Rejected notify*
    \\)
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
    const pieces = [_][]const u8{ "f", "g", "h", "f/", "+f", "g+", " ", ", ", "(", ")", "?", "!", "*", "#A ", "#B ", "/", "[f α g]", "A.", "\n", "B :: " };
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
    var c = try fab.Compilation.init(testing.allocator, "Iso :: f, +f/g/f+, [f α/β g]", preview);
    defer c.deinit();
    const sheet = (try c.sheet()).?;
    try testing.checkAllAllocationFailures(testing.allocator, Case.run, .{sheet});
}
