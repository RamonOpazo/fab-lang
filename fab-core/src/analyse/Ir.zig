//! The intermediate representation: the graph a program denotes.
//!
//! A program is one graph, E ⇉ V, with a kind on every node, plus 2-cells
//! C ⇉ E between parallel edges. Each zone is a subgraph of it. A node that
//! two zones share (through a cross reference such as `A.+f`) is a single
//! node, owned by the zone that created it.
//!
//! The IR is self-contained: it never points into the source. Names are
//! copied into `strings`.
//!
//! The IR is produced for every program, valid or not. Where part of a program
//! failed, the graph has a hole: a node standing for the part that could not
//! be elaborated. Problems are recorded in `issues`, a table beside the graph
//! rather than in it: an issue has no name, so no fAB syntax can create,
//! address, format or hide one. Only the analyser writes issues, and only
//! renderers read them.
//!
//! Format attributes and proof facts are added when those passes exist.

const std = @import("std");

const Ir = @This();

zones: std.MultiArrayList(Zone).Slice,
nodes: std.MultiArrayList(Node).Slice,
edges: std.MultiArrayList(Edge).Slice,
cells: std.MultiArrayList(Cell).Slice,
issues: std.MultiArrayList(Issue).Slice,
strings: []const u8,

pub const ZoneIndex = enum(u32) { _ };
pub const NodeIndex = enum(u32) { _ };
pub const EdgeIndex = enum(u32) { _ };
pub const CellIndex = enum(u32) { _ };

/// A span of `strings`.
pub const String = struct {
    start: u32,
    end: u32,
};

pub const Zone = struct {
    name: String,
    /// The node `@`, if the zone has one.
    own: ?NodeIndex,
    /// Stands for a statement that names no diagram (`review :: a b`,
    /// `:x := …`): it has no elements, only the issues that say what went
    /// wrong, and draws as a crossed square. Its name is the head's first
    /// token.
    placeholder: bool = false,
};

pub const Node = struct {
    kind: Kind,
    /// `#A`, if the node is named.
    name: ?String,
    zone: ZoneIndex,
    /// The first edge end that created the node, in reading order: how the
    /// format layer refers to an unnamed node. Null when the node is named
    /// (`#A` or `@`), since a named node is referred to by its name.
    canonical: ?End,

    pub const Kind = enum(u8) {
        plain,
        choice, // ◇, from ?
        parallel, // ‖, from !
        null_node, // ⊙, from *
        hole, // ◌, a part of the program that failed
    };
};

/// One end of an edge.
pub const End = struct {
    edge: EdgeIndex,
    side: Side,

    pub const Side = enum(u1) { dom, cod };
};

pub const Edge = struct {
    name: String,
    source: NodeIndex,
    target: NodeIndex,
    directed: bool,
    zone: ZoneIndex,
};

/// An edge between edges: `[f α g]`. Source and target are parallel.
pub const Cell = struct {
    name: String,
    source: EdgeIndex,
    target: EdgeIndex,
    zone: ZoneIndex,
};

/// Any element of the graph.
pub const Subject = union(enum) {
    node: NodeIndex,
    edge: EdgeIndex,
    cell: CellIndex,
    zone: ZoneIndex,
};

/// A problem attached to an element of the graph: what a renderer marks.
pub const Issue = struct {
    subject: Subject,
    /// The error it comes from, in the list it is in: the parser's (a
    /// statement too broken to read), or the analyser's.
    err: Err,

    pub const Err = union(enum) { syntax: u32, analysis: u32 };
};

pub fn deinit(ir: *Ir, gpa: std.mem.Allocator) void {
    ir.zones.deinit(gpa);
    ir.nodes.deinit(gpa);
    ir.edges.deinit(gpa);
    ir.cells.deinit(gpa);
    ir.issues.deinit(gpa);
    gpa.free(ir.strings);
    ir.* = undefined;
}

pub fn string(ir: Ir, s: String) []const u8 {
    return ir.strings[s.start..s.end];
}

// ---------------------------------------------------------------------------
// Building. The analyser appends to a Builder and finishes it into an Ir.

pub const Builder = struct {
    gpa: std.mem.Allocator,
    zones: std.MultiArrayList(Zone) = .empty,
    nodes: std.MultiArrayList(Node) = .empty,
    edges: std.MultiArrayList(Edge) = .empty,
    cells: std.MultiArrayList(Cell) = .empty,
    issues: std.MultiArrayList(Issue) = .empty,
    strings: std.ArrayList(u8) = .empty,

    pub fn init(gpa: std.mem.Allocator) Builder {
        return .{ .gpa = gpa };
    }

    /// Frees everything; only needed if `finish` is never called.
    pub fn deinit(b: *Builder) void {
        b.zones.deinit(b.gpa);
        b.nodes.deinit(b.gpa);
        b.edges.deinit(b.gpa);
        b.cells.deinit(b.gpa);
        b.issues.deinit(b.gpa);
        b.strings.deinit(b.gpa);
    }

    pub fn addString(b: *Builder, text: []const u8) !String {
        const start: u32 = @intCast(b.strings.items.len);
        try b.strings.appendSlice(b.gpa, text);
        return .{ .start = start, .end = @intCast(b.strings.items.len) };
    }

    pub fn addZone(b: *Builder, zone: Zone) !ZoneIndex {
        try b.zones.append(b.gpa, zone);
        return @fromBackingInt(@intCast(b.zones.len - 1));
    }

    pub fn addNode(b: *Builder, node: Node) !NodeIndex {
        try b.nodes.append(b.gpa, node);
        return @fromBackingInt(@intCast(b.nodes.len - 1));
    }

    pub fn addEdge(b: *Builder, edge: Edge) !EdgeIndex {
        try b.edges.append(b.gpa, edge);
        return @fromBackingInt(@intCast(b.edges.len - 1));
    }

    pub fn addCell(b: *Builder, cell: Cell) !CellIndex {
        try b.cells.append(b.gpa, cell);
        return @fromBackingInt(@intCast(b.cells.len - 1));
    }

    pub fn addIssue(b: *Builder, issue: Issue) !void {
        try b.issues.append(b.gpa, issue);
    }

    /// Hands the tables over to an Ir. The builder is empty afterwards.
    pub fn finish(b: *Builder) !Ir {
        const strings = try b.strings.toOwnedSlice(b.gpa);
        return .{
            .zones = b.zones.toOwnedSlice(),
            .nodes = b.nodes.toOwnedSlice(),
            .edges = b.edges.toOwnedSlice(),
            .cells = b.cells.toOwnedSlice(),
            .issues = b.issues.toOwnedSlice(),
            .strings = strings,
        };
    }
};

// ---------------------------------------------------------------------------
// Dump: zone by zone, its nodes, then its edges, then its cells; issues last.
// The format of `fab ir` and of the golden files in test/cases/ir/.
//
//   zone G own n0                    a placeholder: `placeholder review`
//     node n0 canon +f
//     node n1 choice #Valid canon f+
//     edge f n0 -> n1          directed
//     edge g n1 -- n2          undirected
//     cell α f => g
//   issue e0 node n1           analysis error 0 marks node n1
//   issue s0 zone G            syntax error 0 marks zone G

pub fn dump(ir: Ir, w: *std.Io.Writer) std.Io.Writer.Error!void {
    for (0..ir.zones.len) |z| {
        const zone = ir.zones.get(z);
        try w.print("{s} {s}", .{ if (zone.placeholder) "placeholder" else "zone", ir.string(zone.name) });
        if (zone.own) |own| try w.print(" own n{d}", .{@backingInt(own)});
        try w.writeAll("\n");

        for (0..ir.nodes.len) |n| {
            const node = ir.nodes.get(n);
            if (@backingInt(node.zone) != z) continue;
            try w.print("  node n{d}", .{n});
            if (node.kind != .plain) try w.print(" {s}", .{@tagName(node.kind)});
            if (node.name) |name| try w.print(" {s}", .{ir.string(name)});
            if (node.canonical) |end| try w.print(" canon {f}", .{ir.endText(end)});
            try w.writeAll("\n");
        }
        for (0..ir.edges.len) |e| {
            const edge = ir.edges.get(e);
            if (@backingInt(edge.zone) != z) continue;
            try w.print("  edge {s} n{d} {s} n{d}\n", .{
                ir.string(edge.name),
                @backingInt(edge.source),
                if (edge.directed) "->" else "--",
                @backingInt(edge.target),
            });
        }
        for (0..ir.cells.len) |c| {
            const cell = ir.cells.get(c);
            if (@backingInt(cell.zone) != z) continue;
            try w.print("  cell {s} {s} => {s}\n", .{
                ir.string(cell.name),
                ir.edgeName(cell.source),
                ir.edgeName(cell.target),
            });
        }
    }
    for (0..ir.issues.len) |i| {
        const issue = ir.issues.get(i);
        switch (issue.err) {
            .syntax => |e| try w.print("issue s{d} ", .{e}),
            .analysis => |e| try w.print("issue e{d} ", .{e}),
        }
        switch (issue.subject) {
            .node => |n| try w.print("node n{d}\n", .{@backingInt(n)}),
            .edge => |e| try w.print("edge {s}\n", .{ir.edgeName(e)}),
            .cell => |c| try w.print("cell {s}\n", .{ir.string(ir.cells.items(.name)[@backingInt(c)])}),
            .zone => |z| try w.print("zone {s}\n", .{ir.string(ir.zones.items(.name)[@backingInt(z)])}),
        }
    }
}

fn edgeName(ir: Ir, e: EdgeIndex) []const u8 {
    return ir.string(ir.edges.items(.name)[@backingInt(e)]);
}

/// `+f` for a domain, `f+` for a codomain, as the format layer writes them.
fn endText(ir: Ir, end: End) EndText {
    return .{ .name = ir.edgeName(end.edge), .side = end.side };
}

const EndText = struct {
    name: []const u8,
    side: End.Side,

    pub fn format(self: EndText, w: *std.Io.Writer) std.Io.Writer.Error!void {
        switch (self.side) {
            .dom => try w.print("+{s}", .{self.name}),
            .cod => try w.print("{s}+", .{self.name}),
        }
    }
};

test {
    _ = @import("ir.test.zig");
}
