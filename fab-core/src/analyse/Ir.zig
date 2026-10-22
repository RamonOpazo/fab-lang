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
};

pub const Node = struct {
    kind: Kind,
    /// `#A`, if the node is named.
    name: ?String,
    zone: ZoneIndex,
    /// The edge end that created the node, in reading order: how the format
    /// layer refers to an unnamed node. Null when a name created the node
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
    /// The error it comes from: an index into the analyser's error list.
    err: u32,
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
//   zone G own n0
//     node n0 canon +f
//     node n1 choice #Valid canon f+
//     edge f n0 -> n1          directed
//     edge g n1 -- n2          undirected
//     cell α f => g
//   issue e0 node n1           error 0 marks node n1

pub fn dump(ir: Ir, w: *std.Io.Writer) std.Io.Writer.Error!void {
    for (0..ir.zones.len) |z| {
        const zone = ir.zones.get(z);
        try w.print("zone {s}", .{ir.string(zone.name)});
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
        try w.print("issue e{d} ", .{issue.err});
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

// ---------------------------------------------------------------------------
// Tests. Until the analyser exists, IRs are built by hand.

const testing = std.testing;

fn expectDump(ir: Ir, expected: []const u8) !void {
    var out: std.Io.Writer.Allocating = .init(testing.allocator);
    defer out.deinit();
    try ir.dump(&out.writer);
    try testing.expectEqualStrings(expected, out.written());
}

test "a decision with an undirected edge: G :: #Valid? (f, g/)" {
    var b: Builder = .init(testing.allocator);
    errdefer b.deinit();

    const g = try b.addZone(.{ .name = try b.addString("G"), .own = null });
    const f_name = try b.addString("f");
    const g_name = try b.addString("g");
    const n0 = try b.addNode(.{ .kind = .choice, .name = try b.addString("#Valid"), .zone = g, .canonical = null });
    const n1 = try b.addNode(.{ .kind = .plain, .name = null, .zone = g, .canonical = .{ .edge = @fromBackingInt(@intCast(0)), .side = .cod } });
    const n2 = try b.addNode(.{ .kind = .plain, .name = null, .zone = g, .canonical = .{ .edge = @fromBackingInt(@intCast(1)), .side = .cod } });
    _ = try b.addEdge(.{ .name = f_name, .source = n0, .target = n1, .directed = true, .zone = g });
    _ = try b.addEdge(.{ .name = g_name, .source = n0, .target = n2, .directed = false, .zone = g });

    var ir = try b.finish();
    defer ir.deinit(testing.allocator);

    try expectDump(ir,
        \\zone G
        \\  node n0 choice #Valid
        \\  node n1 canon f+
        \\  node n2 canon g+
        \\  edge f n0 -> n1
        \\  edge g n0 -- n2
        \\
    );
}

test "two zones sharing a node, and a 2-cell" {
    // A :: f, +f/g/f+, [f α g]   and   B :: h/A.f+
    var b: Builder = .init(testing.allocator);
    errdefer b.deinit();

    const a = try b.addZone(.{ .name = try b.addString("A"), .own = null });
    const n0 = try b.addNode(.{ .kind = .plain, .name = null, .zone = a, .canonical = .{ .edge = @fromBackingInt(@intCast(0)), .side = .dom } });
    const n1 = try b.addNode(.{ .kind = .plain, .name = null, .zone = a, .canonical = .{ .edge = @fromBackingInt(@intCast(0)), .side = .cod } });
    const f = try b.addEdge(.{ .name = try b.addString("f"), .source = n0, .target = n1, .directed = true, .zone = a });
    const g = try b.addEdge(.{ .name = try b.addString("g"), .source = n0, .target = n1, .directed = true, .zone = a });
    _ = try b.addCell(.{ .name = try b.addString("α"), .source = f, .target = g, .zone = a });

    const zb = try b.addZone(.{ .name = try b.addString("B"), .own = null });
    const n2 = try b.addNode(.{ .kind = .plain, .name = null, .zone = zb, .canonical = .{ .edge = @fromBackingInt(@intCast(2)), .side = .dom } });
    _ = try b.addEdge(.{ .name = try b.addString("h"), .source = n2, .target = n1, .directed = true, .zone = zb });

    var ir = try b.finish();
    defer ir.deinit(testing.allocator);

    // n1 belongs to A; B's edge h reaches into it.
    try expectDump(ir,
        \\zone A
        \\  node n0 canon +f
        \\  node n1 canon f+
        \\  edge f n0 -> n1
        \\  edge g n0 -> n1
        \\  cell α f => g
        \\zone B
        \\  node n2 canon +h
        \\  edge h n2 -> n1
        \\
    );
}

test "a zone with an own node: User :: @ (id T.#UUID7)" {
    var b: Builder = .init(testing.allocator);
    errdefer b.deinit();

    const t = try b.addZone(.{ .name = try b.addString("T"), .own = null });
    const uuid = try b.addNode(.{ .kind = .plain, .name = try b.addString("#UUID7"), .zone = t, .canonical = null });
    const user = try b.addZone(.{ .name = try b.addString("User"), .own = null });
    const at = try b.addNode(.{ .kind = .plain, .name = null, .zone = user, .canonical = null });
    b.zones.items(.own)[@backingInt(user)] = at;
    _ = try b.addEdge(.{ .name = try b.addString("id"), .source = at, .target = uuid, .directed = true, .zone = user });

    var ir = try b.finish();
    defer ir.deinit(testing.allocator);

    try expectDump(ir,
        \\zone T
        \\  node n0 #UUID7
        \\zone User own n1
        \\  node n1
        \\  edge id n1 -> n0
        \\
    );
}
