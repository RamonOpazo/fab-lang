//! Turns a concrete syntax tree into the IR, or into a list of errors.
//!
//! Statements are processed in source order, which is what makes "references
//! point left" hold: a zone, edge or name can only be used once it exists.
//!
//! Nodes are derived. Every edge contributes two ends, and every named node
//! (`#A`) or own node (`@`) one atom. The syntax glues these elements together,
//! and a node is a class of glued elements: the quotient P/~ of the spec. The
//! classes live in a union-find whose root is always the oldest element, so a
//! class's root is also the end that created it (its canonical reference) and
//! tells which zone owns it.
//!
//! A class carries annotations that are joined when classes merge: kind, name,
//! whether it is sealed. Two values that can't be joined are an error, so most
//! of the spec's rules about kinds and names are enforced inside `unite`.
//!
//! The format and proof layers are only checked for placement here (the zone
//! exists, the layer name is known, each layer appears once). Their contents
//! are analysed in a later step.

const std = @import("std");
const Token = @import("../lex/Token.zig");
const Cst = @import("../parse/Cst.zig");
const Ir = @import("Ir.zig");

const Node = Cst.Node;
const TokenIndex = Cst.TokenIndex;

const Analyser = @This();

gpa: std.mem.Allocator,
/// Everything that only lives during analysis.
arena: std.mem.Allocator,
cst: *const Cst,
errors: std.ArrayList(Error) = .empty,

/// Level 1: the whole program's nodes.
uf: UnionFind = .{},
zones: std.ArrayList(Zone) = .empty,
zone_by_name: std.StringHashMapUnmanaged(u32) = .empty,
edges: std.ArrayList(Edge) = .empty,
cells: std.ArrayList(Cell) = .empty,
/// The zone being elaborated.
zone: u32 = 0,
/// Set while a `[ ]` block is being elaborated.
cell_ctx: ?*CellContext = null,

pub const Error = struct {
    tag: Tag,
    /// Where the error is reported.
    token: TokenIndex,
    /// Where the conflicting thing was first declared, when that helps.
    related: ?TokenIndex = null,

    pub const Tag = enum {
        // zones and layers
        zone_defined_twice,
        zone_not_defined,
        zone_has_no_own_node,
        layer_for_unknown_zone,
        layer_defined_twice,
        unknown_layer,

        // edges and references
        edge_declared_twice,
        undeclared_edge,
        undeclared_name,
        bare_reference,
        not_an_edge,
        edge_from_references_only,
        self_reference_outside_endomorphism,
        redundant_self_attachment,
        vacuous_self_attachment,
        unsupported_qualified_reference,
        class_in_relations,

        // gluing
        juxtaposition_glues_nothing,
        back_edge_glues_nothing,

        // node kinds and names
        kind_declared_twice,
        conflicting_kinds,
        marker_on_closed_side,
        reference_to_sealed_end,
        sealing_shared_end,
        both_ends_sealed,
        node_named_twice,
        two_own_nodes,

        // edge-to-edge relations
        inner_node_not_an_edge,
        two_edges_in_one_node,
        cells_not_parallel,
        unsupported_in_cells,
    };
};

/// The result is either an IR or the errors that prevented it.
pub const Result = union(enum) {
    ir: Ir,
    errors: []const Error,

    pub fn deinit(result: *Result, gpa: std.mem.Allocator) void {
        switch (result.*) {
            .ir => |*ir| ir.deinit(gpa),
            .errors => |errors| gpa.free(errors),
        }
        result.* = undefined;
    }
};

/// Analyses a syntactically valid program.
pub fn analyse(gpa: std.mem.Allocator, cst: *const Cst) error{OutOfMemory}!Result {
    std.debug.assert(cst.errors.len == 0);

    var arena_state: std.heap.ArenaAllocator = .init(gpa);
    defer arena_state.deinit();

    var a: Analyser = .{ .gpa = gpa, .arena = arena_state.allocator(), .cst = cst };
    defer a.errors.deinit(gpa);

    for (cst.children(.root)) |stmt| {
        a.statement(stmt) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            error.Reported => {}, // already recorded; go on with the next statement
        };
    }
    try a.checkCells();

    if (a.errors.items.len > 0) return .{ .errors = try a.errors.toOwnedSlice(gpa) };
    return .{ .ir = try a.buildIr() };
}

const AnalysisError = error{ OutOfMemory, Reported };

// ---------------------------------------------------------------------------
// Bookkeeping

const Zone = struct {
    name: []const u8,
    token: TokenIndex,
    edges: std.StringHashMapUnmanaged(u32) = .empty,
    cells: std.StringHashMapUnmanaged(u32) = .empty,
    names: std.StringHashMapUnmanaged(u32) = .empty,
    /// The element of `@`.
    own: ?u32 = null,
    own_token: TokenIndex = 0,
    format: ?TokenIndex = null,
    proof: ?TokenIndex = null,
};

const Edge = struct {
    name: []const u8,
    token: TokenIndex,
    zone: u32,
    dom: u32,
    cod: u32,
    directed: bool = true,
};

const Cell = struct {
    name: []const u8,
    token: TokenIndex,
    zone: u32,
    source: u32,
    target: u32,
};

/// What a term elaborates to.
const Frag = union(enum) {
    /// A piece of graph with its open ends: elements of the union-find.
    graph: struct { ins: []const u32, outs: []const u32 },
    /// `+f`, `f+`, `A.+f`: an existing end. It closes the side it's on, and
    /// only `/` may use it.
    ref: struct { elem: u32, node: Node.Index },
};

fn fail(a: *Analyser, tag: Error.Tag, token: TokenIndex, related: ?TokenIndex) AnalysisError {
    try a.errors.append(a.gpa, .{ .tag = tag, .token = token, .related = related });
    return error.Reported;
}

fn text(a: *Analyser, token: TokenIndex) []const u8 {
    return a.cst.tokenText(token);
}

fn tokenTag(a: *Analyser, token: TokenIndex) Token.Tag {
    return a.cst.tokenTag(token);
}

// ---------------------------------------------------------------------------
// Statements

fn statement(a: *Analyser, node: Node.Index) AnalysisError!void {
    switch (a.cst.tag(node)) {
        .relations => try a.relations(node),
        .layer => try a.layer(node),
        else => unreachable, // a valid Cst has only these at the top
    }
}

fn relations(a: *Analyser, node: Node.Index) AnalysisError!void {
    const token = a.cst.mainToken(node);
    const name = a.text(token);
    if (a.zone_by_name.get(name)) |existing| {
        return a.fail(.zone_defined_twice, token, a.zones.items[existing].token);
    }
    // The zone is registered before its term is elaborated, but only zones
    // with a smaller index count as defined, so a zone can't refer to itself.
    a.zone = @intCast(a.zones.items.len);
    try a.zones.append(a.arena, .{ .name = name, .token = token });
    try a.zone_by_name.put(a.arena, name, a.zone);

    const frag = try a.elab(a.cst.data(node).node);
    if (frag == .ref) return a.fail(.bare_reference, a.cst.mainToken(frag.ref.node), null);
}

fn layer(a: *Analyser, node: Node.Index) AnalysisError!void {
    const attr = a.cst.mainToken(node);
    const zone_token = attr - 1;
    const index = a.zone_by_name.get(a.text(zone_token)) orelse
        return a.fail(.layer_for_unknown_zone, zone_token, null);
    const zone = &a.zones.items[index];

    const slot: *?TokenIndex = if (std.mem.eql(u8, a.text(attr), ":format"))
        &zone.format
    else if (std.mem.eql(u8, a.text(attr), ":proof"))
        &zone.proof
    else
        return a.fail(.unknown_layer, attr, null);

    if (slot.*) |first| return a.fail(.layer_defined_twice, attr, first);
    slot.* = attr;
}

// ---------------------------------------------------------------------------
// Terms, level 1

fn elab(a: *Analyser, node: Node.Index) AnalysisError!Frag {
    const main = a.cst.mainToken(node);
    return switch (a.cst.tag(node)) {
        .leaf => switch (a.tokenTag(main)) {
            .edge_id => a.single(try a.declareEdge(main)),
            .node_id => a.atomFrag(try a.namedNode(a.zone, main, true)),
            .at => a.atomFrag(try a.ownNode(main)),
            .zone_id => a.atomFrag(try a.zoneAsNode(main)),
            else => unreachable, // the parser only puts names here
        },
        .group => a.elab(a.cst.data(node).node_token[0]),
        .path => a.path(&a.uf, node, elab),
        .sum => a.sum(&a.uf, node, elab),
        .slash => a.slash(node),
        .prefix => switch (a.tokenTag(main)) {
            .plus => a.reference(node, a.cst.data(node).node, .dom),
            .star => a.seal(node, .ins),
            else => unreachable,
        },
        .postfix => switch (a.tokenTag(main)) {
            .plus => a.reference(node, a.cst.data(node).node, .cod),
            .star => a.seal(node, .outs),
            .quid => a.mark(node, .choice),
            .bang => a.mark(node, .parallel),
            .slash => a.undirected(node),
            else => unreachable,
        },
        .qualified => a.qualified(node),
        .cells => blk: {
            try a.elabCells(node);
            break :blk empty;
        },
        .class => a.fail(.class_in_relations, main, null),
        else => unreachable, // layer shapes never appear in a relations term
    };
}

const empty: Frag = .{ .graph = .{ .ins = &.{}, .outs = &.{} } };

/// A new edge: open at both ends.
fn single(a: *Analyser, edge: u32) AnalysisError!Frag {
    const e = a.edges.items[edge];
    return .{ .graph = .{ .ins = try a.one(e.dom), .outs = try a.one(e.cod) } };
}

/// A node term: the same node is its input and its output.
fn atomFrag(a: *Analyser, elem: u32) AnalysisError!Frag {
    const both = try a.one(elem);
    return .{ .graph = .{ .ins = both, .outs = both } };
}

fn one(a: *Analyser, elem: u32) error{OutOfMemory}![]const u32 {
    const slice = try a.arena.alloc(u32, 1);
    slice[0] = elem;
    return slice;
}

/// `s t`: all open outputs of s and all open inputs of t become one node.
/// Shared by both levels, so it takes the union-find and the elaborator.
fn path(
    a: *Analyser,
    uf: *UnionFind,
    node: Node.Index,
    comptime elabFn: fn (*Analyser, Node.Index) AnalysisError!Frag,
) AnalysisError!Frag {
    const kids = a.cst.children(node);
    var acc = try elabFn(a, kids[0]);
    for (kids[1..]) |kid| {
        const next = try elabFn(a, kid);
        const left = try a.expectGraph(acc);
        const right = try a.expectGraph(next);
        const at = a.cst.firstToken(kid);
        if (left.outs.len == 0 or right.ins.len == 0) return a.fail(.juxtaposition_glues_nothing, at, null);
        try a.uniteAll(uf, left.outs, right.ins, at);
        acc = .{ .graph = .{ .ins = left.ins, .outs = right.outs } };
    }
    return acc;
}

/// `s, t`: side by side, sharing nothing.
fn sum(
    a: *Analyser,
    uf: *UnionFind,
    node: Node.Index,
    comptime elabFn: fn (*Analyser, Node.Index) AnalysisError!Frag,
) AnalysisError!Frag {
    _ = uf;
    var ins: std.ArrayList(u32) = .empty;
    var outs: std.ArrayList(u32) = .empty;
    for (a.cst.children(node)) |kid| {
        const g = try a.expectGraph(try elabFn(a, kid));
        try ins.appendSlice(a.arena, g.ins);
        try outs.appendSlice(a.arena, g.outs);
    }
    return .{ .graph = .{ .ins = ins.items, .outs = outs.items } };
}

const Graph = @FieldType(Frag, "graph");

/// References are only allowed fused with `/`.
fn expectGraph(a: *Analyser, frag: Frag) AnalysisError!Graph {
    return switch (frag) {
        .graph => |g| g,
        .ref => |r| a.fail(.bare_reference, a.cst.mainToken(r.node), null),
    };
}

/// The `/` family.
fn slash(a: *Analyser, node: Node.Index) AnalysisError!Frag {
    const token = a.cst.mainToken(node);
    const left, const right = a.cst.data(node).nodes;

    // f/f: the endomorphism, the only place a bare name may repeat.
    if (a.isEdgeLeaf(left) and a.isEdgeLeaf(right) and
        std.mem.eql(u8, a.text(a.cst.mainToken(left)), a.text(a.cst.mainToken(right))))
    {
        const edge = try a.declareEdge(a.cst.mainToken(left));
        const e = a.edges.items[edge];
        try a.unite(&a.uf, e.dom, e.cod, token);
        return a.single(edge);
    }

    const edges_before = a.edges.items.len;
    const l = try a.elab(left);

    // (f g)/f: a bare name on the right that the left side just declared.
    if (a.isEdgeLeaf(right)) {
        const name_token = a.cst.mainToken(right);
        if (a.zones.items[a.zone].edges.get(a.text(name_token))) |existing| {
            if (existing >= edges_before) {
                return a.fail(.self_reference_outside_endomorphism, name_token, a.edges.items[existing].token);
            }
        }
    }
    const r = try a.elab(right);

    switch (l) {
        .graph => |lg| switch (r) {
            // s/e: e runs from the end of s back to its start. The interface
            // is unchanged.
            .graph => |rg| {
                try a.checkBackEdgeSides(left, right, lg, rg, token);
                try a.uniteAll(&a.uf, lg.outs, rg.ins, token);
                try a.uniteAll(&a.uf, rg.outs, lg.ins, token);
                return l;
            },
            // g/+f: g ends at an existing node; the right side closes.
            .ref => |rr| {
                if (lg.outs.len == 0) return a.fail(.back_edge_glues_nothing, token, null);
                if (a.isEdgeLeaf(left)) {
                    const e = a.edges.items[a.zones.items[a.zone].edges.get(a.text(a.cst.mainToken(left))).?];
                    if (rr.elem == e.dom) return a.fail(.redundant_self_attachment, token, null);
                }
                for (lg.outs) |out| {
                    if (a.uf.find(out) == a.uf.find(rr.elem)) return a.fail(.vacuous_self_attachment, token, null);
                    const class = a.uf.class(out);
                    if (class.kind != null and !class.sealed) {
                        return a.fail(.kind_declared_twice, class.kind_token, null);
                    }
                }
                try a.uniteAll(&a.uf, lg.outs, &.{rr.elem}, token);
                return .{ .graph = .{ .ins = lg.ins, .outs = &.{} } };
            },
        },
        .ref => |lr| switch (r) {
            // +f/g: g starts at an existing node; the left side closes.
            .graph => |rg| {
                if (rg.ins.len == 0) return a.fail(.back_edge_glues_nothing, token, null);
                try a.uniteAll(&a.uf, &.{lr.elem}, rg.ins, token);
                return .{ .graph = .{ .ins = &.{}, .outs = rg.outs } };
            },
            // +g/+f would only identify two nodes, creating no edge.
            .ref => return a.fail(.edge_from_references_only, token, null),
        },
    }
}

/// In `s/e`, all four sides must be open. A side closed by `*` is reported at
/// the `*`, as sealing an end that the back edge needs to share (`f/e*`).
fn checkBackEdgeSides(a: *Analyser, left: Node.Index, right: Node.Index, lg: Graph, rg: Graph, token: TokenIndex) AnalysisError!void {
    const sides = [_]struct { []const u32, Node.Index, Node.Tag }{
        .{ lg.ins, left, .prefix },
        .{ lg.outs, left, .postfix },
        .{ rg.ins, right, .prefix },
        .{ rg.outs, right, .postfix },
    };
    for (sides) |side| {
        const ends, const node, const marker = side;
        if (ends.len > 0) continue;
        const main = a.cst.mainToken(node);
        if (a.cst.tag(node) == marker and a.tokenTag(main) == .star) return a.fail(.sealing_shared_end, main, null);
        return a.fail(.back_edge_glues_nothing, token, null);
    }
}

fn isEdgeLeaf(a: *Analyser, node: Node.Index) bool {
    return a.cst.tag(node) == .leaf and a.tokenTag(a.cst.mainToken(node)) == .edge_id;
}

/// `+f`, `f+`: an end of an edge declared earlier in this zone.
fn reference(a: *Analyser, node: Node.Index, operand: Node.Index, side: Ir.End.Side) AnalysisError!Frag {
    // +f? parses as +(f?): a reference can't declare a kind, since it inherits
    // the kind of the node it lands on.
    if (a.cst.tag(operand) == .postfix) switch (a.tokenTag(a.cst.mainToken(operand))) {
        .quid, .bang => return a.fail(.kind_declared_twice, a.cst.mainToken(operand), null),
        else => {},
    };
    if (!a.isEdgeLeaf(operand)) return a.fail(.not_an_edge, a.cst.firstToken(operand), null);
    const name_token = a.cst.mainToken(operand);
    const edge = a.zones.items[a.zone].edges.get(a.text(name_token)) orelse
        return a.fail(.undeclared_edge, name_token, null);
    return a.endRef(node, edge, side);
}

fn endRef(a: *Analyser, node: Node.Index, edge: u32, side: Ir.End.Side) AnalysisError!Frag {
    const e = a.edges.items[edge];
    const elem = if (side == .dom) e.dom else e.cod;
    if (a.uf.class(elem).sealed) return a.fail(.reference_to_sealed_end, a.cst.mainToken(node), null);
    return .{ .ref = .{ .elem = elem, .node = node } };
}

const Side = enum { ins, outs };

/// `*t`, `t*`: each end on that side becomes its own null node and leaves
/// the interface.
fn seal(a: *Analyser, node: Node.Index, side: Side) AnalysisError!Frag {
    const token = a.cst.mainToken(node);
    const frag = try a.elab(a.cst.data(node).node);
    const g = switch (frag) {
        .graph => |g| g,
        .ref => return a.fail(.sealing_shared_end, token, null),
    };
    const ends = if (side == .ins) g.ins else g.outs;
    if (ends.len == 0) return a.fail(.marker_on_closed_side, token, null);

    for (ends) |elem| {
        const class = a.uf.class(elem);
        if (class.kind) |kind| {
            const tag: Error.Tag = if (kind == .null_node) .kind_declared_twice else .conflicting_kinds;
            return a.fail(tag, token, class.kind_token);
        }
        if (class.size > 1 or class.name != null or class.own) return a.fail(.sealing_shared_end, token, null);
        class.kind = .null_node;
        class.kind_token = token;
        class.sealed = true;

        // *f*: an edge from nothing to nothing says nothing.
        if (a.uf.end_of.items[elem]) |end| {
            const e = a.edges.items[@intFromEnum(end.edge)];
            const other = if (end.side == .dom) e.cod else e.dom;
            if (a.uf.class(other).sealed) return a.fail(.both_ends_sealed, token, null);
        }
    }
    return switch (side) {
        .ins => .{ .graph = .{ .ins = &.{}, .outs = g.outs } },
        .outs => .{ .graph = .{ .ins = g.ins, .outs = &.{} } },
    };
}

/// `t?`, `t!`: the outputs merge into one node of that kind.
fn mark(a: *Analyser, node: Node.Index, kind: Ir.Node.Kind) AnalysisError!Frag {
    const token = a.cst.mainToken(node);
    const frag = try a.elab(a.cst.data(node).node);
    const g = switch (frag) {
        .graph => |g| g,
        // +f?: references inherit the kind of the node they land on.
        .ref => return a.fail(.kind_declared_twice, token, null),
    };
    if (g.outs.len == 0) return a.fail(.marker_on_closed_side, token, null);

    try a.uniteAll(&a.uf, g.outs, &.{}, token);
    const class = a.uf.class(g.outs[0]);
    if (class.kind) |existing| {
        const tag: Error.Tag = if (existing == kind) .kind_declared_twice else .conflicting_kinds;
        return a.fail(tag, token, class.kind_token);
    }
    class.kind = kind;
    class.kind_token = token;
    return .{ .graph = .{ .ins = g.ins, .outs = g.outs[0..1] } };
}

/// `f/`: an undirected edge.
fn undirected(a: *Analyser, node: Node.Index) AnalysisError!Frag {
    const operand = a.cst.data(node).node;
    if (!a.isEdgeLeaf(operand)) return a.fail(.not_an_edge, a.cst.firstToken(operand), null);
    const edge = try a.declareEdge(a.cst.mainToken(operand));
    a.edges.items[edge].directed = false;
    return a.single(edge);
}

/// `A.+f`, `A.f+`, `A.#X`, `A.@`: something that zone A already declared.
fn qualified(a: *Analyser, node: Node.Index) AnalysisError!Frag {
    const zone = try a.definedZone(a.cst.mainToken(node));
    const unit = a.cst.data(node).node;
    const unit_main = a.cst.mainToken(unit);
    switch (a.cst.tag(unit)) {
        .prefix, .postfix => if (a.tokenTag(unit_main) == .plus) {
            const operand = a.cst.data(unit).node;
            if (!a.isEdgeLeaf(operand)) return a.fail(.not_an_edge, a.cst.firstToken(operand), null);
            const name_token = a.cst.mainToken(operand);
            const edge = a.zones.items[zone].edges.get(a.text(name_token)) orelse
                return a.fail(.undeclared_edge, name_token, null);
            return a.endRef(unit, edge, if (a.cst.tag(unit) == .prefix) .dom else .cod);
        },
        .leaf => switch (a.tokenTag(unit_main)) {
            .node_id => return a.atomFrag(try a.namedNode(zone, unit_main, false)),
            .at => return a.atomFrag(a.zones.items[zone].own orelse
                return a.fail(.zone_has_no_own_node, a.cst.mainToken(node), null)),
            else => {},
        },
        else => {},
    }
    return a.fail(.unsupported_qualified_reference, unit_main, null);
}

// ---------------------------------------------------------------------------
// Names

fn declareEdge(a: *Analyser, token: TokenIndex) AnalysisError!u32 {
    const zone = &a.zones.items[a.zone];
    const name = a.text(token);
    if (zone.edges.get(name)) |existing| return a.fail(.edge_declared_twice, token, a.edges.items[existing].token);
    if (zone.cells.get(name)) |existing| return a.fail(.edge_declared_twice, token, a.cells.items[existing].token);

    const index: u32 = @intCast(a.edges.items.len);
    const dom = try a.uf.add(a.arena, a.zone, .{ .edge = @enumFromInt(index), .side = .dom }, .{});
    const cod = try a.uf.add(a.arena, a.zone, .{ .edge = @enumFromInt(index), .side = .cod }, .{});
    try a.edges.append(a.arena, .{ .name = name, .token = token, .zone = a.zone, .dom = dom, .cod = cod });
    try zone.edges.put(a.arena, name, index);
    return index;
}

/// `#A`. In the current zone a new name creates the node and a repeated name
/// glues to it. In another zone (`A.#X`) the name must already exist.
fn namedNode(a: *Analyser, zone_index: u32, token: TokenIndex, create: bool) AnalysisError!u32 {
    const zone = &a.zones.items[zone_index];
    const name = a.text(token);
    if (zone.names.get(name)) |elem| return elem;
    if (!create) return a.fail(.undeclared_name, token, null);
    const elem = try a.uf.add(a.arena, zone_index, null, .{ .name = name, .name_token = token });
    try zone.names.put(a.arena, name, elem);
    return elem;
}

/// `@`: the node that stands for the zone itself. At most one per zone.
fn ownNode(a: *Analyser, token: TokenIndex) AnalysisError!u32 {
    const zone = &a.zones.items[a.zone];
    if (zone.own != null) return a.fail(.two_own_nodes, token, zone.own_token);
    const elem = try a.uf.add(a.arena, a.zone, null, .{ .own = true, .name_token = token });
    zone.own = elem;
    zone.own_token = token;
    return elem;
}

/// `User` in a term: that zone's own node.
fn zoneAsNode(a: *Analyser, token: TokenIndex) AnalysisError!u32 {
    const zone = try a.definedZone(token);
    return a.zones.items[zone].own orelse return a.fail(.zone_has_no_own_node, token, null);
}

/// A zone defined before the current one.
fn definedZone(a: *Analyser, token: TokenIndex) AnalysisError!u32 {
    const index = a.zone_by_name.get(a.text(token)) orelse return a.fail(.zone_not_defined, token, null);
    if (index >= a.zone) return a.fail(.zone_not_defined, token, null);
    return index;
}

// ---------------------------------------------------------------------------
// Edge-to-edge relations, level 2: `[f α g]`
//
// The same language one dimension up. Edges already declared in the zone are
// the nodes; new names are cells. Each block has its own union-find, whose
// classes must each be exactly one outer edge.

fn elabCells(a: *Analyser, node: Node.Index) AnalysisError!void {
    var uf: UnionFind = .{};
    var atoms: std.StringHashMapUnmanaged(u32) = .empty;
    var new_cells: std.ArrayList(PendingCell) = .empty;
    var ctx: CellContext = .{ .uf = &uf, .atoms = &atoms, .new_cells = &new_cells };
    a.cell_ctx = &ctx;
    defer a.cell_ctx = null;

    _ = try a.elab2(a.cst.data(node).node_token[0]);

    for (new_cells.items) |pending| {
        const source = uf.class(pending.dom).outer orelse return a.fail(.inner_node_not_an_edge, pending.token, null);
        const target = uf.class(pending.cod).outer orelse return a.fail(.inner_node_not_an_edge, pending.token, null);
        const index: u32 = @intCast(a.cells.items.len);
        try a.cells.append(a.arena, .{
            .name = a.text(pending.token),
            .token = pending.token,
            .zone = a.zone,
            .source = source,
            .target = target,
        });
        try a.zones.items[a.zone].cells.put(a.arena, a.text(pending.token), index);
    }
}

const PendingCell = struct { token: TokenIndex, dom: u32, cod: u32 };

const CellContext = struct {
    uf: *UnionFind,
    atoms: *std.StringHashMapUnmanaged(u32),
    new_cells: *std.ArrayList(PendingCell),
};

fn elab2(a: *Analyser, node: Node.Index) AnalysisError!Frag {
    const ctx = a.cell_ctx.?;
    const main = a.cst.mainToken(node);
    switch (a.cst.tag(node)) {
        .leaf => if (a.tokenTag(main) == .edge_id) {
            const name = a.text(main);
            const zone = &a.zones.items[a.zone];
            // A declared edge is a node here.
            if (zone.edges.get(name)) |edge| {
                const gop = try ctx.atoms.getOrPut(a.arena, name);
                if (!gop.found_existing) gop.value_ptr.* = try ctx.uf.add(a.arena, a.zone, null, .{ .outer = edge });
                return a.atomFrag(gop.value_ptr.*);
            }
            if (zone.cells.get(name)) |existing| return a.fail(.edge_declared_twice, main, a.cells.items[existing].token);
            for (ctx.new_cells.items) |pending| {
                if (std.mem.eql(u8, a.text(pending.token), name)) return a.fail(.edge_declared_twice, main, pending.token);
            }
            // A new name is a cell.
            const dom = try ctx.uf.add(a.arena, a.zone, null, .{});
            const cod = try ctx.uf.add(a.arena, a.zone, null, .{});
            try ctx.new_cells.append(a.arena, .{ .token = main, .dom = dom, .cod = cod });
            return .{ .graph = .{ .ins = try a.one(dom), .outs = try a.one(cod) } };
        },
        .group => return a.elab2(a.cst.data(node).node_token[0]),
        .path => return a.path(ctx.uf, node, elab2),
        .sum => return a.sum(ctx.uf, node, elab2),
        .slash => {
            const left, const right = a.cst.data(node).nodes;
            const lg = try a.expectGraph(try a.elab2(left));
            const rg = try a.expectGraph(try a.elab2(right));
            if (lg.outs.len == 0 or lg.ins.len == 0 or rg.ins.len == 0 or rg.outs.len == 0) {
                return a.fail(.back_edge_glues_nothing, main, null);
            }
            try a.uniteAll(ctx.uf, lg.outs, rg.ins, main);
            try a.uniteAll(ctx.uf, rg.outs, lg.ins, main);
            return .{ .graph = lg };
        },
        else => {},
    }
    return a.fail(.unsupported_in_cells, a.cst.firstToken(node), null);
}

/// A cell's source and target must be parallel edges. Checked at the end,
/// once every node of the program is final.
fn checkCells(a: *Analyser) error{OutOfMemory}!void {
    for (a.cells.items) |cell| {
        const s = a.edges.items[cell.source];
        const t = a.edges.items[cell.target];
        if (a.uf.find(s.dom) != a.uf.find(t.dom) or a.uf.find(s.cod) != a.uf.find(t.cod)) {
            try a.errors.append(a.gpa, .{ .tag = .cells_not_parallel, .token = cell.token });
        }
    }
}

// ---------------------------------------------------------------------------
// Union-find

const UnionFind = struct {
    parent: std.ArrayList(u32) = .empty,
    classes: std.ArrayList(Class) = .empty,
    /// Which edge end each element is; null for atoms.
    end_of: std.ArrayList(?Ir.End) = .empty,
    zone_of: std.ArrayList(u32) = .empty,

    /// Valid at roots only.
    const Class = struct {
        kind: ?Ir.Node.Kind = null,
        kind_token: TokenIndex = 0,
        name: ?[]const u8 = null,
        name_token: TokenIndex = 0,
        own: bool = false,
        sealed: bool = false,
        size: u32 = 1,
        /// Level 2: the outer edge this class stands for.
        outer: ?u32 = null,

        fn named(c: Class) bool {
            return c.name != null or c.own;
        }
    };

    fn add(uf: *UnionFind, arena: std.mem.Allocator, zone: u32, end: ?Ir.End, init: Class) !u32 {
        const elem: u32 = @intCast(uf.parent.items.len);
        try uf.parent.append(arena, elem);
        try uf.classes.append(arena, init);
        try uf.end_of.append(arena, end);
        try uf.zone_of.append(arena, zone);
        return elem;
    }

    fn find(uf: *UnionFind, x: u32) u32 {
        var i = x;
        while (uf.parent.items[i] != i) {
            uf.parent.items[i] = uf.parent.items[uf.parent.items[i]]; // path halving
            i = uf.parent.items[i];
        }
        return i;
    }

    fn class(uf: *UnionFind, x: u32) *Class {
        return &uf.classes.items[uf.find(x)];
    }
};

/// Merges two classes, joining their annotations. The older root stays root,
/// so a class's root is always its first element.
fn unite(a: *Analyser, uf: *UnionFind, x: u32, y: u32, token: TokenIndex) AnalysisError!void {
    var rx = uf.find(x);
    var ry = uf.find(y);
    if (rx == ry) return;
    if (ry < rx) std.mem.swap(u32, &rx, &ry);
    const cx = &uf.classes.items[rx];
    const cy = uf.classes.items[ry];

    if (cx.sealed or cy.sealed) return a.fail(.sealing_shared_end, token, null);
    if (cx.kind != null and cy.kind != null) {
        const tag: Error.Tag = if (cx.kind.? == cy.kind.?) .kind_declared_twice else .conflicting_kinds;
        return a.fail(tag, token, cy.kind_token);
    }
    if (cx.named() and cy.named()) return a.fail(.node_named_twice, token, cx.name_token);
    if (cx.outer != null and cy.outer != null and cx.outer.? != cy.outer.?) {
        return a.fail(.two_edges_in_one_node, token, null);
    }

    if (cx.kind == null) {
        cx.kind = cy.kind;
        cx.kind_token = cy.kind_token;
    }
    if (!cx.named()) {
        cx.name = cy.name;
        cx.own = cy.own;
        cx.name_token = cy.name_token;
    }
    cx.outer = cx.outer orelse cy.outer;
    cx.size += cy.size;
    uf.parent.items[ry] = rx;
}

/// Merges every element of `xs` and `ys` into one class.
fn uniteAll(a: *Analyser, uf: *UnionFind, xs: []const u32, ys: []const u32, token: TokenIndex) AnalysisError!void {
    const first = if (xs.len > 0) xs[0] else ys[0];
    for (xs) |x| try a.unite(uf, first, x, token);
    for (ys) |y| try a.unite(uf, first, y, token);
}

// ---------------------------------------------------------------------------
// Building the IR. Nodes are numbered in order of their first element, which
// is reading order, so equal programs give identical IRs.

fn buildIr(a: *Analyser) error{OutOfMemory}!Ir {
    var b: Ir.Builder = .init(a.gpa);
    errdefer b.deinit();

    for (a.zones.items) |zone| {
        _ = try b.addZone(.{ .name = try b.addString(zone.name), .own = null });
    }

    const node_of = try a.arena.alloc(?Ir.NodeIndex, a.uf.parent.items.len);
    @memset(node_of, null);
    for (0..a.uf.parent.items.len) |i| {
        const root = a.uf.find(@intCast(i));
        if (node_of[root] != null) continue;
        const class = a.uf.classes.items[root];
        const zone: Ir.ZoneIndex = @enumFromInt(a.uf.zone_of.items[root]);
        const node = try b.addNode(.{
            .kind = class.kind orelse .plain,
            .name = if (class.name) |name| try b.addString(name) else null,
            .zone = zone,
            .canonical = if (class.named()) null else a.uf.end_of.items[root],
        });
        node_of[root] = node;
        if (class.own) b.zones.items(.own)[@intFromEnum(zone)] = node;
    }

    for (a.edges.items) |edge| {
        _ = try b.addEdge(.{
            .name = try b.addString(edge.name),
            .source = node_of[a.uf.find(edge.dom)].?,
            .target = node_of[a.uf.find(edge.cod)].?,
            .directed = edge.directed,
            .zone = @enumFromInt(edge.zone),
        });
    }
    for (a.cells.items) |cell| {
        _ = try b.addCell(.{
            .name = try b.addString(cell.name),
            .source = @enumFromInt(cell.source),
            .target = @enumFromInt(cell.target),
            .zone = @enumFromInt(cell.zone),
        });
    }
    return b.finish();
}

// ---------------------------------------------------------------------------
// Tests

const testing = std.testing;
const Parser = @import("../parse/Parser.zig");

fn expectIr(source: [:0]const u8, expected: []const u8) !void {
    var cst = try Parser.parse(testing.allocator, source);
    defer cst.deinit(testing.allocator);
    try testing.expectEqual(@as(usize, 0), cst.errors.len);

    var result = try analyse(testing.allocator, &cst);
    defer result.deinit(testing.allocator);
    switch (result) {
        .errors => |errors| {
            for (errors) |e| std.debug.print("unexpected {s} at '{s}'\n", .{ @tagName(e.tag), cst.tokenText(e.token) });
            return error.TestUnexpectedResult;
        },
        .ir => |ir| {
            var out: std.Io.Writer.Allocating = .init(testing.allocator);
            defer out.deinit();
            try ir.dump(&out.writer);
            try testing.expectEqualStrings(expected, out.written());
        },
    }
}

/// Checks the first error's tag and the text of the token it points at.
fn expectError(source: [:0]const u8, tag: Error.Tag, at: []const u8) !void {
    var cst = try Parser.parse(testing.allocator, source);
    defer cst.deinit(testing.allocator);
    try testing.expectEqual(@as(usize, 0), cst.errors.len);

    var result = try analyse(testing.allocator, &cst);
    defer result.deinit(testing.allocator);
    switch (result) {
        .ir => return error.TestExpectedError,
        .errors => |errors| {
            testing.expectEqual(tag, errors[0].tag) catch |err| {
                std.debug.print("source: {s}\n", .{source});
                return err;
            };
            try testing.expectEqualStrings(at, cst.tokenText(errors[0].token));
        },
    }
}

test "a chain" {
    try expectIr("G :: f g h",
        \\zone G
        \\  node n0 canon +f
        \\  node n1 canon f+
        \\  node n2 canon g+
        \\  node n3 canon h+
        \\  edge f n0 -> n1
        \\  edge g n1 -> n2
        \\  edge h n2 -> n3
        \\
    );
}

test "fork and join" {
    try expectIr("Fork :: f (g, h)\nJoin :: (f, g) h",
        \\zone Fork
        \\  node n0 canon +f
        \\  node n1 canon f+
        \\  node n2 canon g+
        \\  node n3 canon h+
        \\  edge f n0 -> n1
        \\  edge g n1 -> n2
        \\  edge h n1 -> n3
        \\zone Join
        \\  node n4 canon +f
        \\  node n5 canon f+
        \\  node n6 canon +g
        \\  node n7 canon h+
        \\  edge f n4 -> n5
        \\  edge g n6 -> n5
        \\  edge h n5 -> n7
        \\
    );
}

test "back edges and endomorphisms" {
    try expectIr("A :: f/e\nB :: (f g)/h\nC :: f/f g h/h",
        \\zone A
        \\  node n0 canon +f
        \\  node n1 canon f+
        \\  edge f n0 -> n1
        \\  edge e n1 -> n0
        \\zone B
        \\  node n2 canon +f
        \\  node n3 canon f+
        \\  node n4 canon g+
        \\  edge f n2 -> n3
        \\  edge g n3 -> n4
        \\  edge h n4 -> n2
        \\zone C
        \\  node n5 canon +f
        \\  node n6 canon g+
        \\  edge f n5 -> n5
        \\  edge g n5 -> n6
        \\  edge h n6 -> n6
        \\
    );
}

test "the commutative square: canonical nodes as in the spec" {
    try expectIr("Sq :: f h, +f/g k/h+",
        \\zone Sq
        \\  node n0 canon +f
        \\  node n1 canon f+
        \\  node n2 canon h+
        \\  node n3 canon g+
        \\  edge f n0 -> n1
        \\  edge h n1 -> n2
        \\  edge g n0 -> n3
        \\  edge k n3 -> n2
        \\
    );
}

test "node kinds" {
    try expectIr("If :: f? (fg g, fh h)? k\nWhile :: f? (b/f+, e)\nP :: *f g h*",
        \\zone If
        \\  node n0 canon +f
        \\  node n1 choice canon f+
        \\  node n2 canon fg+
        \\  node n3 choice canon g+
        \\  node n4 canon fh+
        \\  node n5 canon k+
        \\  edge f n0 -> n1
        \\  edge fg n1 -> n2
        \\  edge g n2 -> n3
        \\  edge fh n1 -> n4
        \\  edge h n4 -> n3
        \\  edge k n3 -> n5
        \\zone While
        \\  node n6 canon +f
        \\  node n7 choice canon f+
        \\  node n8 canon e+
        \\  edge f n6 -> n7
        \\  edge b n7 -> n7
        \\  edge e n7 -> n8
        \\zone P
        \\  node n9 null_node canon +f
        \\  node n10 canon f+
        \\  node n11 canon g+
        \\  node n12 null_node canon h+
        \\  edge f n9 -> n10
        \\  edge g n10 -> n11
        \\  edge h n11 -> n12
        \\
    );
}

test "undirected edges" {
    try expectIr("G :: #A f/ #B, #B g/ #C",
        \\zone G
        \\  node n0 #A
        \\  node n1 #B
        \\  node n2 #C
        \\  edge f n0 -- n1
        \\  edge g n1 -- n2
        \\
    );
}

test "zones as nodes, own nodes and shared types" {
    try expectIr(
        \\T :: #UUID7, #String
        \\User :: @ (id T.#UUID7, name T.#String)
        \\Doc :: @ (id T.#UUID7)
        \\Db :: Doc owner User
    ,
        \\zone T
        \\  node n0 #UUID7
        \\  node n1 #String
        \\zone User own n2
        \\  node n2
        \\  edge id n2 -> n0
        \\  edge name n2 -> n1
        \\zone Doc own n3
        \\  node n3
        \\  edge id n3 -> n0
        \\zone Db
        \\  edge owner n3 -> n2
        \\
    );
}

test "a cross-zone reference reaches into another zone's node" {
    try expectIr("A :: f g\nB :: h/A.+f",
        \\zone A
        \\  node n0 canon +f
        \\  node n1 canon f+
        \\  node n2 canon g+
        \\  edge f n0 -> n1
        \\  edge g n1 -> n2
        \\zone B
        \\  node n3 canon +h
        \\  edge h n3 -> n0
        \\
    );
}

test "edge-to-edge relations" {
    try expectIr("Nat :: f, +f/g/f+, [f α g]\nIso :: f, +f/g/f+, [f α/β g]",
        \\zone Nat
        \\  node n0 canon +f
        \\  node n1 canon f+
        \\  edge f n0 -> n1
        \\  edge g n0 -> n1
        \\  cell α f => g
        \\zone Iso
        \\  node n2 canon +f
        \\  node n3 canon f+
        \\  edge f n2 -> n3
        \\  edge g n2 -> n3
        \\  cell α f => g
        \\  cell β g => f
        \\
    );
}

test "the spec's flowchart" {
    try expectIr(
        \\Order :: *receive #Received validate #Valid? (
        \\    yes #Accepted! (
        \\        charge #Charged? (paid, declined #Waiting retry/charge+)
        \\      , reserve #InStock? (reserved, short #Backorder restock/reserve+)
        \\    )! #Ready ship #Shipped close*
        \\  , no #Rejected notify*
        \\)
    ,
        \\zone Order
        \\  node n0 null_node canon +receive
        \\  node n1 #Received
        \\  node n2 choice #Valid
        \\  node n3 parallel #Accepted
        \\  node n4 choice #Charged
        \\  node n5 parallel #Ready
        \\  node n6 #Waiting
        \\  node n7 choice #InStock
        \\  node n8 #Backorder
        \\  node n9 #Shipped
        \\  node n10 null_node canon close+
        \\  node n11 #Rejected
        \\  node n12 null_node canon notify+
        \\  edge receive n0 -> n1
        \\  edge validate n1 -> n2
        \\  edge yes n2 -> n3
        \\  edge charge n3 -> n4
        \\  edge paid n4 -> n5
        \\  edge declined n4 -> n6
        \\  edge retry n6 -> n4
        \\  edge reserve n3 -> n7
        \\  edge reserved n7 -> n5
        \\  edge short n7 -> n8
        \\  edge restock n8 -> n7
        \\  edge ship n5 -> n9
        \\  edge close n9 -> n10
        \\  edge no n2 -> n11
        \\  edge notify n11 -> n12
        \\
    );
}

test "layers are placed but not yet analysed" {
    try expectIr("G :: f\nG :format { f :label \"x\" }\nG :proof { f == f }",
        \\zone G
        \\  node n0 canon +f
        \\  node n1 canon f+
        \\  edge f n0 -> n1
        \\
    );
}

test "errors: zones and layers" {
    try expectError("G :: f\nG :: g", .zone_defined_twice, "G");
    try expectError("Db :: Doc owner User", .zone_not_defined, "Doc");
    try expectError("G :: f G", .zone_not_defined, "G");
    try expectError("T :: #A\nDb :: T owns T", .zone_has_no_own_node, "T");
    try expectError("H :format { f :label \"x\" }", .layer_for_unknown_zone, "H");
    try expectError("G :: f\nG :style { f :label \"x\" }", .unknown_layer, ":style");
    try expectError("G :: f\nG :format { f :label \"x\" }\nG :format { f :label \"y\" }", .layer_defined_twice, ":format");
}

test "errors: edges and references (the spec's table)" {
    try expectError("G :: f g f", .edge_declared_twice, "f");
    try expectError("G :: (f g)/f", .self_reference_outside_endomorphism, "f");
    try expectError("G :: f/+f", .redundant_self_attachment, "/");
    try expectError("G :: f/f+", .vacuous_self_attachment, "/");
    try expectError("G :: f g, +g/+f", .edge_from_references_only, "/");
    try expectError("G :: +f/g f", .undeclared_edge, "f");
    try expectError("G :: f, k +f", .bare_reference, "+");
    try expectError("G :: f, +(f g)/h", .not_an_edge, "(");
    try expectError("A :: f\nB :: h/A.+k", .undeclared_edge, "k");
    try expectError("T :: #A\nU :: f T.#B", .undeclared_name, "#B");
}

test "errors: node kinds and sealing (the spec's table)" {
    try expectError("G :: f, k?/+f", .kind_declared_twice, "?");
    try expectError("G :: f, +f?", .kind_declared_twice, "?");
    try expectError("G :: f?*", .conflicting_kinds, "*");
    try expectError("G :: f?!", .conflicting_kinds, "!");
    try expectError("G :: f* g", .juxtaposition_glues_nothing, "g");
    try expectError("G :: f, g/+f h", .juxtaposition_glues_nothing, "h");
    try expectError("G :: f*, k/f+", .reference_to_sealed_end, "+");
    try expectError("G :: f/e*", .sealing_shared_end, "*");
    try expectError("G :: *f*", .both_ends_sealed, "*");
}

test "errors: names and own nodes" {
    try expectError("G :: #A #B", .node_named_twice, "#B");
    try expectError("G :: @ f @", .two_own_nodes, "@");
    try expectError("G :: .iso f", .class_in_relations, ".");
}

test "errors: edge-to-edge relations" {
    try expectError("Sq :: f h, +f/g k/h+, [f α h]", .cells_not_parallel, "α");
    try expectError("G :: f, +f/g/f+, [α β]", .inner_node_not_an_edge, "α");
    try expectError("G :: f, +f/g/f+, [f g]", .two_edges_in_one_node, "g");
}
