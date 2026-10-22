//! The intermediate representation: the graph a program denotes.
//!
//! A program is one graph, E ⇉ V, with a kind on every node, plus 2-cells
//! C ⇉ E between parallel edges. Each zone is a subgraph of it. A node that
//! two zones share (through a cross reference such as `A.+f`) is a single
//! node, owned by the zone that created it.
//!
//! The IR is self-contained: it never points into the source. Names are
//! copied into `strings`. It is produced only for programs without errors.
//!
//! Format attributes and proof facts are added when those passes exist.

const std = @import("std");

const Ir = @This();

zones: std.MultiArrayList(Zone).Slice,
nodes: std.MultiArrayList(Node).Slice,
edges: std.MultiArrayList(Edge).Slice,
cells: std.MultiArrayList(Cell).Slice,
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

pub fn deinit(ir: *Ir, gpa: std.mem.Allocator) void {
    ir.zones.deinit(gpa);
    ir.nodes.deinit(gpa);
    ir.edges.deinit(gpa);
    ir.cells.deinit(gpa);
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
        b.strings.deinit(b.gpa);
    }

    pub fn addString(b: *Builder, text: []const u8) !String {
        const start: u32 = @intCast(b.strings.items.len);
        try b.strings.appendSlice(b.gpa, text);
        return .{ .start = start, .end = @intCast(b.strings.items.len) };
    }

    pub fn addZone(b: *Builder, zone: Zone) !ZoneIndex {
        try b.zones.append(b.gpa, zone);
        return @enumFromInt(b.zones.len - 1);
    }

    pub fn addNode(b: *Builder, node: Node) !NodeIndex {
        try b.nodes.append(b.gpa, node);
        return @enumFromInt(b.nodes.len - 1);
    }

    pub fn addEdge(b: *Builder, edge: Edge) !EdgeIndex {
        try b.edges.append(b.gpa, edge);
        return @enumFromInt(b.edges.len - 1);
    }

    pub fn addCell(b: *Builder, cell: Cell) !CellIndex {
        try b.cells.append(b.gpa, cell);
        return @enumFromInt(b.cells.len - 1);
    }

    /// Hands the tables over to an Ir. The builder is empty afterwards.
    pub fn finish(b: *Builder) !Ir {
        const strings = try b.strings.toOwnedSlice(b.gpa);
        return .{
            .zones = b.zones.toOwnedSlice(),
            .nodes = b.nodes.toOwnedSlice(),
            .edges = b.edges.toOwnedSlice(),
            .cells = b.cells.toOwnedSlice(),
            .strings = strings,
        };
    }
};

// ---------------------------------------------------------------------------
// Dump: zone by zone, its nodes, then its edges, then its cells. The format of
// `fab ir` and of the golden files in test/cases/ir/.
//
//   zone G own n0
//     node n0 canon +f
//     node n1 choice #Valid canon f+
//     edge f n0 -> n1          directed
//     edge g n1 -- n2          undirected
//     cell α f => g

pub fn dump(ir: Ir, w: *std.Io.Writer) std.Io.Writer.Error!void {
    for (0..ir.zones.len) |z| {
        const zone = ir.zones.get(z);
        try w.print("zone {s}", .{ir.string(zone.name)});
        if (zone.own) |own| try w.print(" own n{d}", .{@intFromEnum(own)});
        try w.writeAll("\n");

        for (0..ir.nodes.len) |n| {
            const node = ir.nodes.get(n);
            if (@intFromEnum(node.zone) != z) continue;
            try w.print("  node n{d}", .{n});
            if (node.kind != .plain) try w.print(" {s}", .{@tagName(node.kind)});
            if (node.name) |name| try w.print(" {s}", .{ir.string(name)});
            if (node.canonical) |end| try w.print(" canon {f}", .{ir.endText(end)});
            try w.writeAll("\n");
        }
        for (0..ir.edges.len) |e| {
            const edge = ir.edges.get(e);
            if (@intFromEnum(edge.zone) != z) continue;
            try w.print("  edge {s} n{d} {s} n{d}\n", .{
                ir.string(edge.name),
                @intFromEnum(edge.source),
                if (edge.directed) "->" else "--",
                @intFromEnum(edge.target),
            });
        }
        for (0..ir.cells.len) |c| {
            const cell = ir.cells.get(c);
            if (@intFromEnum(cell.zone) != z) continue;
            try w.print("  cell {s} {s} => {s}\n", .{
                ir.string(cell.name),
                ir.edgeName(cell.source),
                ir.edgeName(cell.target),
            });
        }
    }
}

fn edgeName(ir: Ir, e: EdgeIndex) []const u8 {
    return ir.string(ir.edges.items(.name)[@intFromEnum(e)]);
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
    const n1 = try b.addNode(.{ .kind = .plain, .name = null, .zone = g, .canonical = .{ .edge = @enumFromInt(0), .side = .cod } });
    const n2 = try b.addNode(.{ .kind = .plain, .name = null, .zone = g, .canonical = .{ .edge = @enumFromInt(1), .side = .cod } });
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
    const n0 = try b.addNode(.{ .kind = .plain, .name = null, .zone = a, .canonical = .{ .edge = @enumFromInt(0), .side = .dom } });
    const n1 = try b.addNode(.{ .kind = .plain, .name = null, .zone = a, .canonical = .{ .edge = @enumFromInt(0), .side = .cod } });
    const f = try b.addEdge(.{ .name = try b.addString("f"), .source = n0, .target = n1, .directed = true, .zone = a });
    const g = try b.addEdge(.{ .name = try b.addString("g"), .source = n0, .target = n1, .directed = true, .zone = a });
    _ = try b.addCell(.{ .name = try b.addString("α"), .source = f, .target = g, .zone = a });

    const zb = try b.addZone(.{ .name = try b.addString("B"), .own = null });
    const n2 = try b.addNode(.{ .kind = .plain, .name = null, .zone = zb, .canonical = .{ .edge = @enumFromInt(2), .side = .dom } });
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
    b.zones.items(.own)[@intFromEnum(user)] = at;
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
