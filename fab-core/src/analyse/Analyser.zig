//! Turns a concrete syntax tree into the IR, and reports what is wrong with it.
//!
//! The analyser always produces an IR, valid program or not, together with the
//! errors it found. Deciding whether an IR with errors is acceptable belongs to
//! the compiler, not to this file.
//!
//! Statements are processed in source order, which is what makes "references
//! point left" hold: a zone, edge or name can only be used once it exists.
//!
//! Nodes are derived. Every edge contributes two ends, and every named node
//! (`#A`) or own node (`@`) one atom. The syntax glues these elements together,
//! and a node is a class of glued elements: the quotient P/~ of the spec. The
//! classes live in a union-find (UnionFind.zig). When two classes can't be
//! merged, the union-find returns the conflict and this file reports it.
//!
//! Errors are handled in one of two ways (see Recovery):
//!   - `report` records an error and carries on with an obvious repair,
//!     such as keeping the first of two conflicting kinds;
//!   - `fail` records an error and unwinds to the nearest element of a path
//!     or a sum. Everything that element did is rolled back, and a hole, a
//!     placeholder node, takes its place, so the rest of the graph stays
//!     connected around it.
//!
//! Sections, in order: statements; recovery; terms (fragments, composition,
//! back edges and references, markers); names; edge-to-edge relations; gluing;
//! building the IR. The tests are in analyse_test.zig and recovery.test.zig.
//!
//! The format and proof layers are only checked for placement here (the zone
//! exists, the layer name is known, each layer appears once). Their contents
//! are analysed in a later step.

const std = @import("std");
const Token = @import("../lex/Token.zig");
const Cst = @import("../parse/Cst.zig");
const Ir = @import("Ir.zig");
const UnionFind = @import("UnionFind.zig");

const Node = Cst.Node;
const TokenIndex = Cst.TokenIndex;

const Analyser = @This();

gpa: std.mem.Allocator,
/// Everything that only lives during analysis.
arena: std.mem.Allocator,
cst: *const Cst,
errors: std.ArrayList(Error) = .empty,

/// Level 1: the whole program's nodes.
uf: UnionFind,
zones: std.ArrayList(Zone) = .empty,
zone_by_name: std.StringHashMapUnmanaged(u32) = .empty,
edges: std.ArrayList(Edge) = .empty,
cells: std.ArrayList(Cell) = .empty,
/// The zone being elaborated.
zone: u32 = 0,
/// Set while a `[ ]` block is being elaborated.
cell_ctx: ?*CellContext = null,
/// Issues beyond each error's own subject: holes that stand in for a
/// cascade point back to the error that started it.
extra_issues: std.ArrayList(ExtraIssue) = .empty,
/// The error behind the latest silent failure, if known.
silent_cause: ?u32 = null,

pub const Error = struct {
    tag: Tag,
    /// Where the error is reported.
    token: TokenIndex,
    /// Where the conflicting thing was first declared, when that helps.
    related: ?TokenIndex = null,
    /// What to mark in the graph, if anything.
    subject: ?Subject = null,

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

/// An element of the graph under construction, before it becomes part of the
/// IR: a union-find element (whose class is a node), an edge, a cell or a zone.
pub const Subject = union(enum) {
    elem: u32,
    edge: u32,
    cell: u32,
    zone: u32,
};

/// Always an IR, and the errors found while building it. Errors with a
/// subject appear in the IR's issues table.
pub const Result = struct {
    ir: Ir,
    errors: []const Error,

    pub fn deinit(result: *Result, gpa: std.mem.Allocator) void {
        result.ir.deinit(gpa);
        gpa.free(result.errors);
        result.* = undefined;
    }
};

const AnalysisError = error{ OutOfMemory, Reported };

/// Analyses a program. A program with syntax errors is analysed too: the
/// statements the parser could not shape are skipped.
pub fn analyse(gpa: std.mem.Allocator, cst: *const Cst) error{OutOfMemory}!Result {
    var arena_state: std.heap.ArenaAllocator = .init(gpa);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    var a: Analyser = .{ .gpa = gpa, .arena = arena, .cst = cst, .uf = .init(arena) };
    errdefer a.errors.deinit(gpa);

    for (cst.children(.root)) |stmt| {
        a.statement(stmt) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            error.Reported => {}, // already recorded; go on with the next statement
        };
    }
    try a.checkCells();

    var ir = try a.buildIr();
    errdefer ir.deinit(gpa);
    return .{ .ir = ir, .errors = try a.errors.toOwnedSlice(gpa) };
}

// ---------------------------------------------------------------------------
// Bookkeeping

const Zone = struct {
    name: []const u8,
    token: TokenIndex,
    edges: std.StringHashMapUnmanaged(u32) = .empty,
    cells: std.StringHashMapUnmanaged(u32) = .empty,
    names: std.StringHashMapUnmanaged(u32) = .empty,
    /// Names whose declaration was rolled back, with the error that caused it,
    /// if known. Failing to find one of these is silent: that error has been
    /// reported already.
    poisoned: std.StringHashMapUnmanaged(?u32) = .empty,
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

const ExtraIssue = struct { subject: Subject, err: u32 };

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
        .invalid => {}, // the parser has reported it
        else => unreachable, // the parser puts nothing else at the top
    }
}

fn relations(a: *Analyser, node: Node.Index) AnalysisError!void {
    const token = a.cst.mainToken(node);
    const name = a.text(token);
    const first = a.zone_by_name.get(name);

    // The zone is registered before its term is elaborated, but only zones
    // with a smaller index count as defined, so a zone can't refer to itself.
    a.zone = @intCast(a.zones.items.len);
    try a.zones.append(a.arena, .{ .name = name, .token = token });
    if (first) |existing| {
        // Drawn anyway, but unreachable by name: references go to the first.
        try a.report(.zone_defined_twice, token, a.zones.items[existing].token, .{ .zone = a.zone });
    } else {
        try a.zone_by_name.put(a.arena, name, a.zone);
    }
    _ = try a.element(a.cst.data(node).node);
}

fn layer(a: *Analyser, node: Node.Index) AnalysisError!void {
    const attr = a.cst.mainToken(node);
    const zone_token = attr - 1;
    const index = a.zone_by_name.get(a.text(zone_token)) orelse
        return a.report(.layer_for_unknown_zone, zone_token, null, null);
    const zone = &a.zones.items[index];

    const slot: *?TokenIndex = if (std.mem.eql(u8, a.text(attr), ":format"))
        &zone.format
    else if (std.mem.eql(u8, a.text(attr), ":proof"))
        &zone.proof
    else
        return a.report(.unknown_layer, attr, null, null);

    if (slot.*) |first| return a.report(.layer_defined_twice, attr, first, null);
    slot.* = attr;
}

// ---------------------------------------------------------------------------
// Recovery

/// Records an error and carries on.
fn report(a: *Analyser, tag: Error.Tag, token: TokenIndex, related: ?TokenIndex, subject: ?Subject) error{OutOfMemory}!void {
    try a.errors.append(a.gpa, .{ .tag = tag, .token = token, .related = related, .subject = subject });
}

/// Records an error and unwinds to the nearest guarded element, which becomes
/// a hole.
fn fail(a: *Analyser, tag: Error.Tag, token: TokenIndex, related: ?TokenIndex) AnalysisError {
    try a.report(tag, token, related, null);
    return error.Reported;
}

/// Unwinds like `fail`, but records nothing: for cascades of an error already
/// reported, which is `cause` when known.
fn silent(a: *Analyser, cause: ?u32) AnalysisError {
    a.silent_cause = cause;
    return error.Reported;
}

/// Everything needed to undo the work of one element.
const Snapshot = struct {
    uf: UnionFind.Mark,
    edges: u32,
    cells: u32,
    errors: u32,
    extra_issues: u32,
};

fn snapshot(a: *Analyser) Snapshot {
    return .{
        .uf = a.uf.snapshot(),
        .edges = @intCast(a.edges.items.len),
        .cells = @intCast(a.cells.items.len),
        .errors = @intCast(a.errors.items.len),
        .extra_issues = @intCast(a.extra_issues.items.len),
    };
}

/// Undoes everything since `saved` except the errors. Names declared since
/// then are removed from the current zone and poisoned, remembering `cause`.
fn rollback(a: *Analyser, saved: Snapshot, cause: ?u32) error{OutOfMemory}!void {
    const zone = &a.zones.items[a.zone];
    try a.unmap(zone, &zone.edges, saved.edges, cause);
    try a.unmap(zone, &zone.cells, saved.cells, cause);
    try a.unmap(zone, &zone.names, saved.uf.len, cause);
    if (zone.own) |own| {
        if (own >= saved.uf.len) zone.own = null;
    }
    a.edges.shrinkRetainingCapacity(saved.edges);
    a.cells.shrinkRetainingCapacity(saved.cells);
    a.uf.rollback(saved.uf);
}

/// Removes the names in `map` whose value is at least `limit`, poisoning them.
fn unmap(a: *Analyser, zone: *Zone, map: *std.StringHashMapUnmanaged(u32), limit: u32, cause: ?u32) error{OutOfMemory}!void {
    var removed: std.ArrayList([]const u8) = .empty;
    var it = map.iterator();
    while (it.next()) |entry| {
        if (entry.value_ptr.* >= limit) try removed.append(a.arena, entry.key_ptr.*);
    }
    for (removed.items) |name| {
        _ = map.remove(name);
        try zone.poisoned.put(a.arena, name, cause);
    }
}

/// Elaborates one element of a path or a sum, or a whole relations term. If
/// it fails, everything it did is undone and a hole takes its place. Errors
/// it recorded that mark nothing, or mark something undone, mark the hole. A
/// hole from a silent failure is marked with the error that caused it.
fn element(a: *Analyser, node: Node.Index) AnalysisError!Graph {
    const saved = a.snapshot();
    const result: ?Frag = a.elab(node) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.Reported => null,
    };
    if (result) |frag| switch (frag) {
        .graph => |g| return g,
        // References are only allowed fused with `/`.
        .ref => |r| try a.report(.bare_reference, a.cst.mainToken(r.node), null, null),
    };

    const reported = a.errors.items.len > saved.errors;
    const cause: ?u32 = if (reported) saved.errors else a.silent_cause;
    try a.rollback(saved, cause);
    const hole = try a.uf.add(a.zone, null, .{ .hole = true });
    for (a.errors.items[saved.errors..]) |*e| {
        if (e.subject == null or lost(e.subject.?, saved)) e.subject = .{ .elem = hole };
    }
    for (a.extra_issues.items[saved.extra_issues..]) |*x| {
        if (lost(x.subject, saved)) x.subject = .{ .elem = hole };
    }
    if (!reported) {
        if (cause) |c| try a.extra_issues.append(a.arena, .{ .subject = .{ .elem = hole }, .err = c });
    }
    return a.atom(hole);
}

/// Whether a rollback to `saved` removed `subject`.
fn lost(subject: Subject, saved: Snapshot) bool {
    return switch (subject) {
        .elem => |x| x >= saved.uf.len,
        .edge => |x| x >= saved.edges,
        .cell => |x| x >= saved.cells,
        .zone => false,
    };
}

// ---------------------------------------------------------------------------
// Terms, level 1
//
// Every term elaborates to a fragment: a piece of graph with its open ends,
// or a reference to an existing end. Juxtaposition glues the outputs of one
// fragment to the inputs of the next, comma puts fragments side by side, and
// the tight operators (`/`, `+`, `*`, `?`, `!`) attach, close or mark ends.

/// What a term elaborates to.
const Frag = union(enum) {
    /// A piece of graph with its open ends: elements of the union-find.
    graph: Graph,
    /// `+f`, `f+`, `A.+f`: an existing end. It closes the side it's on, and
    /// only `/` may use it.
    ref: struct { elem: u32, node: Node.Index },
};

const Graph = struct { ins: []const u32, outs: []const u32 };

const empty: Frag = .{ .graph = .{ .ins = &.{}, .outs = &.{} } };

/// Elaborates an element of a path or a sum, at either level.
const ChildFn = fn (*Analyser, Node.Index) AnalysisError!Graph;

fn elab(a: *Analyser, node: Node.Index) AnalysisError!Frag {
    const main = a.cst.mainToken(node);
    return switch (a.cst.tag(node)) {
        .leaf => switch (a.tokenTag(main)) {
            .edge_id => a.single(try a.declareEdge(main)),
            .node_id => .{ .graph = try a.atom(try a.namedNode(a.zone, main, true)) },
            .at => .{ .graph = try a.atom(try a.ownNode(main)) },
            .zone_id => .{ .graph = try a.atom(try a.zoneAsNode(main)) },
            else => unreachable, // the parser only puts names here
        },
        .group => a.elab(a.cst.data(node).node_token[0]),
        .path => a.path(&a.uf, node, element),
        .sum => a.sum(node, element),
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
            // A block that fails is dropped: a cell has no hole to stand for it.
            a.elabCells(node) catch |err| switch (err) {
                error.OutOfMemory => return error.OutOfMemory,
                error.Reported => {},
            };
            break :blk empty;
        },
        .class => a.fail(.class_in_relations, main, null),
        .invalid => a.silent(null), // the parser has reported it
        else => unreachable, // layer shapes never appear in a relations term
    };
}

// ---------------------------------------------------------------------------
// Fragments

/// A new edge: open at both ends.
fn single(a: *Analyser, edge: u32) AnalysisError!Frag {
    const e = a.edges.items[edge];
    return .{ .graph = .{ .ins = try a.one(e.dom), .outs = try a.one(e.cod) } };
}

/// A node term: the same node is its input and its output.
fn atom(a: *Analyser, elem: u32) error{OutOfMemory}!Graph {
    const both = try a.one(elem);
    return .{ .ins = both, .outs = both };
}

fn one(a: *Analyser, elem: u32) error{OutOfMemory}![]const u32 {
    const slice = try a.arena.alloc(u32, 1);
    slice[0] = elem;
    return slice;
}

fn concat(a: *Analyser, x: []const u32, y: []const u32) error{OutOfMemory}![]const u32 {
    return std.mem.concat(a.arena, u32, &.{ x, y });
}

/// References are only allowed fused with `/`.
fn expectGraph(a: *Analyser, frag: Frag) AnalysisError!Graph {
    return switch (frag) {
        .graph => |g| g,
        .ref => |r| a.fail(.bare_reference, a.cst.mainToken(r.node), null),
    };
}

// ---------------------------------------------------------------------------
// Composition, shared by both levels

/// `s t`: all open outputs of s and all open inputs of t become one node.
/// If one side has nothing to glue, the two are kept side by side, as `s, t`.
fn path(a: *Analyser, uf: *UnionFind, node: Node.Index, comptime child: ChildFn) AnalysisError!Frag {
    const kids = a.cst.children(node);
    var acc = try child(a, kids[0]);
    for (kids[1..]) |kid| {
        const next = try child(a, kid);
        const at = a.cst.firstToken(kid);
        if (acc.outs.len == 0 or next.ins.len == 0) {
            try a.report(.juxtaposition_glues_nothing, at, null, null);
            acc = .{ .ins = try a.concat(acc.ins, next.ins), .outs = try a.concat(acc.outs, next.outs) };
            continue;
        }
        try a.uniteAll(uf, acc.outs, next.ins, at);
        acc = .{ .ins = acc.ins, .outs = next.outs };
    }
    return .{ .graph = acc };
}

/// `s, t`: side by side, sharing nothing.
fn sum(a: *Analyser, node: Node.Index, comptime child: ChildFn) AnalysisError!Frag {
    var ins: std.ArrayList(u32) = .empty;
    var outs: std.ArrayList(u32) = .empty;
    for (a.cst.children(node)) |kid| {
        const g = try child(a, kid);
        try ins.appendSlice(a.arena, g.ins);
        try outs.appendSlice(a.arena, g.outs);
    }
    return .{ .graph = .{ .ins = ins.items, .outs = outs.items } };
}

// ---------------------------------------------------------------------------
// Back edges and references

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
                    const edge = a.zones.items[a.zone].edges.get(a.text(a.cst.mainToken(left))).?;
                    if (rr.elem == a.edges.items[edge].dom) {
                        // f/+f is f/f written another way: build it as written.
                        try a.report(.redundant_self_attachment, token, null, .{ .edge = edge });
                    }
                }
                for (lg.outs) |out| {
                    if (a.uf.find(out) == a.uf.find(rr.elem)) {
                        try a.report(.vacuous_self_attachment, token, null, .{ .elem = out });
                        continue;
                    }
                    // k?/+f: the reference's node keeps its own kind.
                    const class = a.uf.class(out);
                    if (class.kind != null and !class.sealed and !class.hole) {
                        try a.report(.kind_declared_twice, class.kind_token, null, .{ .elem = out });
                        try a.uf.force(rr.elem, out);
                        continue;
                    }
                    try a.unite(&a.uf, out, rr.elem, token);
                }
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
    const edge = try a.lookupEdge(a.zone, name_token);
    return a.endRef(node, edge, side);
}

/// An edge declared in `zone`. A poisoned name fails silently.
fn lookupEdge(a: *Analyser, zone: u32, name_token: TokenIndex) AnalysisError!u32 {
    const name = a.text(name_token);
    if (a.zones.items[zone].edges.get(name)) |edge| return edge;
    if (a.zones.items[zone].poisoned.get(name)) |cause| return a.silent(cause);
    return a.fail(.undeclared_edge, name_token, null);
}

fn endRef(a: *Analyser, node: Node.Index, edge: u32, side: Ir.End.Side) AnalysisError!Frag {
    const e = a.edges.items[edge];
    const elem = if (side == .dom) e.dom else e.cod;
    if (a.uf.class(elem).sealed) return a.fail(.reference_to_sealed_end, a.cst.mainToken(node), null);
    return .{ .ref = .{ .elem = elem, .node = node } };
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
            const edge = try a.lookupEdge(zone, a.cst.mainToken(operand));
            return a.endRef(unit, edge, if (a.cst.tag(unit) == .prefix) .dom else .cod);
        },
        .leaf => switch (a.tokenTag(unit_main)) {
            .node_id => return .{ .graph = try a.atom(try a.namedNode(zone, unit_main, false)) },
            .at => return .{ .graph = try a.atom(a.zones.items[zone].own orelse
                return a.fail(.zone_has_no_own_node, a.cst.mainToken(node), null)) },
            else => {},
        },
        else => {},
    }
    return a.fail(.unsupported_qualified_reference, unit_main, null);
}

// ---------------------------------------------------------------------------
// Markers

const Side = enum { ins, outs };

/// `*t`, `t*`: each end on that side becomes its own null node and leaves
/// the interface. An end that can't be sealed is reported and left open.
fn seal(a: *Analyser, node: Node.Index, side: Side) AnalysisError!Frag {
    const token = a.cst.mainToken(node);
    const frag = try a.elab(a.cst.data(node).node);
    const g = switch (frag) {
        .graph => |g| g,
        .ref => return a.fail(.sealing_shared_end, token, null),
    };
    const ends = if (side == .ins) g.ins else g.outs;
    if (ends.len == 0) {
        try a.report(.marker_on_closed_side, token, null, null);
        return frag;
    }

    var open: std.ArrayList(u32) = .empty;
    for (ends) |elem| {
        const class = a.uf.class(elem);
        if (class.hole) {
            try open.append(a.arena, elem); // a hole absorbs the marker
            continue;
        }
        if (class.kind) |kind| {
            const tag: Error.Tag = if (kind == .null_node) .kind_declared_twice else .conflicting_kinds;
            try a.report(tag, token, class.kind_token, .{ .elem = elem });
            try open.append(a.arena, elem);
            continue;
        }
        if (class.size > 1 or class.named()) {
            try a.report(.sealing_shared_end, token, null, .{ .elem = elem });
            try open.append(a.arena, elem);
            continue;
        }
        // *f*: an edge from nothing to nothing says nothing.
        if (a.uf.end_of.items[elem]) |end| {
            const e = a.edges.items[@backingInt(end.edge)];
            const other = if (end.side == .dom) e.cod else e.dom;
            if (a.uf.class(other).sealed) {
                try a.report(.both_ends_sealed, token, null, .{ .elem = elem });
                try open.append(a.arena, elem);
                continue;
            }
        }
        const c = try a.uf.edit(elem);
        c.kind = .null_node;
        c.kind_token = token;
        c.sealed = true;
    }
    return switch (side) {
        .ins => .{ .graph = .{ .ins = open.items, .outs = g.outs } },
        .outs => .{ .graph = .{ .ins = g.ins, .outs = open.items } },
    };
}

/// `t?`, `t!`: the outputs merge into one node of that kind. A node that
/// already has a kind keeps it.
fn mark(a: *Analyser, node: Node.Index, kind: Ir.Node.Kind) AnalysisError!Frag {
    const token = a.cst.mainToken(node);
    const frag = try a.elab(a.cst.data(node).node);
    const g = switch (frag) {
        .graph => |g| g,
        .ref => {
            // (+f)?: references inherit the kind of the node they land on.
            try a.report(.kind_declared_twice, token, null, null);
            return frag;
        },
    };
    if (g.outs.len == 0) {
        try a.report(.marker_on_closed_side, token, null, null);
        return frag;
    }

    const errors_before = a.errors.items.len;
    try a.uniteAll(&a.uf, g.outs, &.{}, token);
    const class = a.uf.class(g.outs[0]);
    if (class.hole) {
        // a hole absorbs the marker
    } else if (class.kind) |existing| {
        // Merging the outputs may already have reported this conflict.
        if (a.errors.items.len == errors_before) {
            const tag: Error.Tag = if (existing == kind) .kind_declared_twice else .conflicting_kinds;
            try a.report(tag, token, class.kind_token, .{ .elem = g.outs[0] });
        }
    } else {
        const c = try a.uf.edit(g.outs[0]);
        c.kind = kind;
        c.kind_token = token;
    }
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

// ---------------------------------------------------------------------------
// Names

/// A bare name: a new edge. A name declared twice still gets its own edge,
/// so the graph keeps the shape that was written, but references keep going
/// to the first.
fn declareEdge(a: *Analyser, token: TokenIndex) AnalysisError!u32 {
    const zone = &a.zones.items[a.zone];
    const name = a.text(token);
    const first: ?TokenIndex = if (zone.edges.get(name)) |e|
        a.edges.items[e].token
    else if (zone.cells.get(name)) |c|
        a.cells.items[c].token
    else
        null;

    const index: u32 = @intCast(a.edges.items.len);
    const dom = try a.uf.add(a.zone, .{ .edge = @fromBackingInt(@intCast(index)), .side = .dom }, .{});
    const cod = try a.uf.add(a.zone, .{ .edge = @fromBackingInt(@intCast(index)), .side = .cod }, .{});
    try a.edges.append(a.arena, .{ .name = name, .token = token, .zone = a.zone, .dom = dom, .cod = cod });

    if (first) |related| {
        try a.report(.edge_declared_twice, token, related, .{ .edge = index });
    } else {
        try zone.edges.put(a.arena, name, index);
        _ = zone.poisoned.remove(name);
    }
    return index;
}

/// `#A`. In the current zone a new name creates the node and a repeated name
/// glues to it. In another zone (`A.#X`) the name must already exist.
fn namedNode(a: *Analyser, zone_index: u32, token: TokenIndex, create: bool) AnalysisError!u32 {
    const zone = &a.zones.items[zone_index];
    const name = a.text(token);
    if (zone.names.get(name)) |elem| return elem;
    if (!create) {
        if (zone.poisoned.get(name)) |cause| return a.silent(cause);
        return a.fail(.undeclared_name, token, null);
    }
    const elem = try a.uf.add(zone_index, null, .{ .name = name, .name_token = token });
    try zone.names.put(a.arena, name, elem);
    _ = zone.poisoned.remove(name);
    return elem;
}

/// `@`: the node that stands for the zone itself. A second `@` is reported and
/// glued to the first.
fn ownNode(a: *Analyser, token: TokenIndex) AnalysisError!u32 {
    const zone = &a.zones.items[a.zone];
    if (zone.own) |own| {
        try a.report(.two_own_nodes, token, zone.own_token, .{ .elem = own });
        return own;
    }
    const elem = try a.uf.add(a.zone, null, .{ .own = true, .name_token = token });
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
// the nodes; new names are cells. Each `[ ]` block has its own union-find,
// whose classes must each be exactly one outer edge. Juxtaposition, comma and
// back edges keep their level-1 meaning, through the shared `path` and `sum`.
// A block that fails is dropped as a whole; a cell that can't be placed is
// dropped on its own.

/// The state of the `[ ]` block being elaborated.
const CellContext = struct {
    uf: *UnionFind,
    /// Outer edge name → its element in `uf`.
    atoms: *std.StringHashMapUnmanaged(u32),
    new_cells: *std.ArrayList(PendingCell),
};

const PendingCell = struct { token: TokenIndex, dom: u32, cod: u32 };

/// Elaborates one `[ ]` block and records its cells.
fn elabCells(a: *Analyser, node: Node.Index) AnalysisError!void {
    var uf: UnionFind = .init(a.arena);
    var atoms: std.StringHashMapUnmanaged(u32) = .empty;
    var new_cells: std.ArrayList(PendingCell) = .empty;
    var ctx: CellContext = .{ .uf = &uf, .atoms = &atoms, .new_cells = &new_cells };
    a.cell_ctx = &ctx;
    defer a.cell_ctx = null;

    _ = try a.elab2(a.cst.data(node).node_token[0]);

    for (new_cells.items) |pending| {
        const source = uf.class(pending.dom).outer;
        const target = uf.class(pending.cod).outer;
        if (source == null or target == null) {
            try a.report(.inner_node_not_an_edge, pending.token, null, null);
            continue;
        }
        const index: u32 = @intCast(a.cells.items.len);
        try a.cells.append(a.arena, .{
            .name = a.text(pending.token),
            .token = pending.token,
            .zone = a.zone,
            .source = source.?,
            .target = target.?,
        });
        try a.zones.items[a.zone].cells.put(a.arena, a.text(pending.token), index);
    }
}

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
                if (!gop.found_existing) gop.value_ptr.* = try ctx.uf.add(a.zone, null, .{ .outer = edge });
                return .{ .graph = try a.atom(gop.value_ptr.*) };
            }
            // A rolled-back edge would otherwise read as a new cell.
            if (zone.poisoned.get(name)) |cause| return a.silent(cause);
            if (zone.cells.get(name)) |existing| return a.fail(.edge_declared_twice, main, a.cells.items[existing].token);
            for (ctx.new_cells.items) |pending| {
                if (std.mem.eql(u8, a.text(pending.token), name)) return a.fail(.edge_declared_twice, main, pending.token);
            }
            // A new name is a cell.
            const dom = try ctx.uf.add(a.zone, null, .{});
            const cod = try ctx.uf.add(a.zone, null, .{});
            try ctx.new_cells.append(a.arena, .{ .token = main, .dom = dom, .cod = cod });
            return .{ .graph = .{ .ins = try a.one(dom), .outs = try a.one(cod) } };
        },
        .group => return a.elab2(a.cst.data(node).node_token[0]),
        .path => return a.path(ctx.uf, node, graph2),
        .sum => return a.sum(node, graph2),
        .slash => {
            const left, const right = a.cst.data(node).nodes;
            const lg = try a.graph2(left);
            const rg = try a.graph2(right);
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

fn graph2(a: *Analyser, node: Node.Index) AnalysisError!Graph {
    return a.expectGraph(try a.elab2(node));
}

/// A cell's source and target must be parallel edges. Checked at the end,
/// once every node of the program is final. A cell that isn't is kept, and
/// marked.
fn checkCells(a: *Analyser) error{OutOfMemory}!void {
    for (a.cells.items, 0..) |cell, i| {
        const s = a.edges.items[cell.source];
        const t = a.edges.items[cell.target];
        if (a.uf.find(s.dom) != a.uf.find(t.dom) or a.uf.find(s.cod) != a.uf.find(t.cod)) {
            try a.report(.cells_not_parallel, cell.token, null, .{ .cell = @intCast(i) });
        }
    }
}

// ---------------------------------------------------------------------------
// Gluing

/// Merges two classes. A conflict is reported at `token` and repaired: two
/// kinds or two names keep the older one; a sealed end stays unglued. At
/// level 2, two different edges in one node fail the block.
fn unite(a: *Analyser, uf: *UnionFind, x: u32, y: u32, token: TokenIndex) AnalysisError!void {
    const conflict = (try uf.unite(x, y)) orelse return;
    // Subjects are level-1 elements; level 2 only ever fails.
    const subject: ?Subject = if (uf == &a.uf) .{ .elem = x } else null;
    switch (conflict.tag) {
        .sealed_end => try a.report(.sealing_shared_end, token, null, subject),
        .same_kind => {
            try a.report(.kind_declared_twice, token, conflict.related, subject);
            try uf.force(x, y);
        },
        .different_kinds => {
            try a.report(.conflicting_kinds, token, conflict.related, subject);
            try uf.force(x, y);
        },
        .two_names => {
            try a.report(.node_named_twice, token, conflict.related, subject);
            try uf.force(x, y);
        },
        .two_outer_edges => return a.fail(.two_edges_in_one_node, token, null),
    }
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

    const node_of = try a.arena.alloc(?Ir.NodeIndex, a.uf.len());
    @memset(node_of, null);
    for (0..a.uf.len()) |i| {
        const root = a.uf.find(@intCast(i));
        if (node_of[root] != null) continue;
        const class = a.uf.classes.items[root];
        const zone: Ir.ZoneIndex = @fromBackingInt(@intCast(a.uf.zone_of.items[root]));
        const node = try b.addNode(.{
            .kind = if (class.hole) .hole else class.kind orelse .plain,
            .name = if (class.name) |name| try b.addString(name) else null,
            .zone = zone,
            .canonical = if (class.named()) null else a.uf.end_of.items[root],
        });
        node_of[root] = node;
        if (class.own) b.zones.items(.own)[@backingInt(zone)] = node;
    }

    for (a.edges.items) |edge| {
        _ = try b.addEdge(.{
            .name = try b.addString(edge.name),
            .source = node_of[a.uf.find(edge.dom)].?,
            .target = node_of[a.uf.find(edge.cod)].?,
            .directed = edge.directed,
            .zone = @fromBackingInt(@intCast(edge.zone)),
        });
    }
    for (a.cells.items) |cell| {
        _ = try b.addCell(.{
            .name = try b.addString(cell.name),
            .source = @fromBackingInt(@intCast(cell.source)),
            .target = @fromBackingInt(@intCast(cell.target)),
            .zone = @fromBackingInt(@intCast(cell.zone)),
        });
    }

    for (a.errors.items, 0..) |err, i| {
        const subject: Ir.Subject = switch (err.subject orelse continue) {
            .elem => |x| .{ .node = node_of[a.uf.find(x)].? },
            .edge => |x| .{ .edge = @fromBackingInt(@intCast(x)) },
            .cell => |x| .{ .cell = @fromBackingInt(@intCast(x)) },
            .zone => |x| .{ .zone = @fromBackingInt(@intCast(x)) },
        };
        try b.addIssue(.{ .subject = subject, .err = @intCast(i) });
    }
    for (a.extra_issues.items) |x| {
        try b.addIssue(.{ .subject = .{ .node = node_of[a.uf.find(x.subject.elem)].? }, .err = x.err });
    }
    return b.finish();
}

test {
    _ = @import("union_find.test.zig");
    _ = @import("analyser.test.zig");
    _ = @import("recovery.test.zig");
}
