//! From fab-core's analysis to the Place (plan steps α4–α5): each
//! descriptor's value, by precedence, read against the seed, and the checks
//! no search needs (spec, Errors, Places).
//!
//! A diagram's place is folded from its layers, lowest first, as its style
//! is (statements.md §23.2, §29):
//!
//!   defaults  <  for each diagram of its chain, containers outermost first:
//!                the kind's case where that diagram states its kind, then
//!                (for the diagram itself) the top level's classes, then the
//!                diagram's classes  <  its own bindings
//!
//! so `&zone` and `&edge` pass down to members, and a diagram's own
//! `G :place { :flow [E] }` stays its own. The defaults are `:grid [4]`,
//! `:metric [1]`, `:flow [S]`; an edge's span is unstated, its collapse off.
//!
//! A value the lattice can't read (`:grid [5]`, `:flow [0/2]`) is reported
//! at the value, once, and passed over, so the layer below stands. A flow is
//! read against each seed it reaches: `[2/0]` is an area on `[3]`, not on
//! `[4]`.

const std = @import("std");
const fab = @import("fab_core");
const Ir = fab.Ir;
const Env = fab.Env;
const Cst = fab.Cst;
const Diagnostic = fab.Diagnostic;
const decoded = fab.decoded;
const layers = fab.layers;
const grid = @import("grid.zig");
const ranks = @import("ranks.zig");
const messages = @import("messages.zig");
const Place = @import("Place.zig");

const Node = Cst.Node;
const Value = decoded.Value;
const Seed = grid.Seed;
const Dir = grid.Dir;

/// What the layer reads besides the IR.
pub const Inputs = struct {
    env: *const Env,
    bindings: []const layers.Binding = &.{},
    /// Each diagram's kind in effect, and the diagram stating it.
    kinds: []const layers.Kind = &.{},
    /// The program, for the diagnostics' spans; without it, none is made.
    cst: ?*const Cst = null,
};

pub fn resolve(gpa: std.mem.Allocator, ir: *const Ir, in: Inputs) error{OutOfMemory}!Place {
    var place: Place = .{
        .arena = .init(gpa),
        .ir = ir,
        .zones = &.{},
        .edges = &.{},
        .bundles = &.{},
        .diagnostics = &.{},
    };
    errdefer place.arena.deinit();
    var r: Resolver = .{ .gpa = gpa, .arena = place.arena.allocator(), .ir = ir, .in = in };
    defer r.deinit();

    const zones = try r.arena.alloc(Place.Zone, ir.zones.len);
    const edges = try r.arena.alloc(Place.Edge, ir.edges.len);
    @memset(edges, .{});
    r.stated = try gpa.alloc(Stated, ir.edges.len);
    @memset(r.stated, .{});
    const edge_zones = ir.edges.items(.zone);
    for (zones, 0..) |*zone, z| {
        const index: Ir.ZoneIndex = @fromBackingInt(@as(u32, @intCast(z)));
        zone.* = try r.zone(index);
        // The edges' layers above the defaults, the same for every edge of
        // the diagram.
        try r.collect(index, .edge);
        var common: Place.Edge = .{};
        var stated: Stated = .{};
        for (r.sources.items) |s| try r.bindEdge(&common, &stated, s, false);
        for (edges, r.stated, edge_zones) |*e, *st, owner| if (owner == index) {
            e.* = common;
            st.* = stated;
        };
    }
    for (in.bindings) |b| if (placed(b)) switch (b.subject) {
        .edge => |e| try r.bindEdge(&edges[@backingInt(e)], &r.stated[@backingInt(e)], .{
            .descriptor = b.descriptor,
            .value = b.value,
            .attr = b.attr,
        }, true),
        else => {},
    };

    place.zones = zones;
    place.edges = edges;
    place.bundles = try r.bundle(edges);
    for (0..ir.zones.len) |z| try r.checkSpans(@fromBackingInt(@as(u32, @intCast(z))), edges);

    std.mem.sort(Diagnostic, r.diagnostics.items, {}, before);
    place.diagnostics = try r.arena.dupe(Diagnostic, r.diagnostics.items);
    return place;
}

fn before(_: void, a: Diagnostic, b: Diagnostic) bool {
    return a.span.start < b.span.start;
}

/// A binding of place's, as the layer reads it: `attr` its descriptor in the
/// program, null for the prelude's (a kind's case).
const Source = struct { descriptor: []const u8, value: Value, attr: ?Node.Index = null };

/// Where an edge's span and its own collapse were stated, for the checks.
const Stated = struct {
    span: ?Node.Index = null,
    /// `f :collapse`, the edge's own flag: a class's collapses only what it
    /// can, silently.
    collapse: ?Node.Index = null,
};

fn placed(b: layers.Binding) bool {
    return b.layer == .place and b.key == null;
}

fn is(s: Source, name: []const u8) bool {
    return std.mem.eql(u8, s.descriptor, name);
}

/// Why a value can't be read: each a code of the layer's.
const Unread = error{ NotATiling, NotWhole, NoDirection, NotAnArea, Cancel, StepOfNothing, SpanOfNothing };

fn code(err: Unread) *const Diagnostic.Foreign {
    return switch (err) {
        error.NotATiling => &messages.seed_not_a_tiling,
        error.NotWhole => &messages.number_not_whole,
        error.NoDirection => &messages.flow_of_no_direction,
        error.NotAnArea => &messages.not_an_area,
        error.Cancel => &messages.directions_cancel,
        error.StepOfNothing => &messages.step_of_nothing,
        error.SpanOfNothing => &messages.span_of_nothing,
    };
}

const Resolver = struct {
    gpa: std.mem.Allocator,
    /// The Place's.
    arena: std.mem.Allocator,
    ir: *const Ir,
    in: Inputs,
    /// What `collect` gathers, lowest first.
    sources: std.ArrayList(Source) = .empty,
    chain_buffer: std.ArrayList(Ir.ZoneIndex) = .empty,
    stated: []Stated = &.{},
    diagnostics: std.ArrayList(Diagnostic) = .empty,
    /// Each (descriptor, code) reported once, however many diagrams or
    /// edges it reaches.
    reported: std.AutoHashMapUnmanaged(struct { Node.Index, *const Diagnostic.Foreign }, void) = .empty,

    fn deinit(r: *Resolver) void {
        r.sources.deinit(r.gpa);
        r.chain_buffer.deinit(r.gpa);
        r.gpa.free(r.stated);
        r.diagnostics.deinit(r.gpa);
        r.reported.deinit(r.gpa);
    }

    /// Reports `foreign` at `attr`'s value (at `attr` when it has none),
    /// once.
    fn report(r: *Resolver, foreign: *const Diagnostic.Foreign, attr: ?Node.Index, related: ?Node.Index) error{OutOfMemory}!void {
        const cst = r.in.cst orelse return;
        const at = attr orelse return;
        const gop = try r.reported.getOrPut(r.gpa, .{ at, foreign });
        if (gop.found_existing) return;
        try r.diagnostics.append(r.gpa, .fromLayer(cst, foreign, valueOf(cst, at), if (related) |x| valueOf(cst, x) else null));
    }

    /// A diagram's place: its layers folded, the flow read against the seed
    /// they settle.
    fn zone(r: *Resolver, z: Ir.ZoneIndex) error{OutOfMemory}!Place.Zone {
        try r.collect(z, .zone);
        for (r.in.bindings) |b| if (placed(b) and b.subject == .zone and b.subject.zone == z) {
            try r.sources.append(r.gpa, .{ .descriptor = b.descriptor, .value = b.value, .attr = b.attr });
        };
        var seed: Seed = .default;
        var metric: ?Value = null;
        for (r.sources.items) |s| {
            if (is(s, ":grid")) {
                seed = seedOf(s.value) catch |err| {
                    try r.report(code(err), s.attr, null);
                    continue;
                };
            } else if (is(s, ":metric")) {
                _ = steps(&s.value) catch |err| {
                    try r.report(code(err), s.attr, null);
                    continue;
                };
                metric = s.value;
            }
        }
        // The highest flow the seed can read, else `[S]`.
        var flow: Place.Flow = .{ .along = seed.letters(.S, null).? };
        for (r.sources.items) |s| if (is(s, ":flow")) {
            flow = flowOf(seed, s.value) catch |err| {
                try r.report(code(err), s.attr, null);
                continue;
            };
        };
        var zone_place: Place.Zone = .{ .seed = seed, .flow = flow };
        if (metric) |*m| {
            const items = steps(m) catch unreachable;
            const out = try r.arena.alloc(Place.Step, items.len);
            for (items, out) |item, *step| step.* = .{ .length = item.number.value, .turn = item.number.inverted };
            zone_place.metric = out;
        }
        return zone_place;
    }

    fn bindEdge(r: *Resolver, e: *Place.Edge, stated: *Stated, s: Source, own: bool) error{OutOfMemory}!void {
        if (is(s, ":span")) {
            e.span = span(s.value) catch |err| return r.report(code(err), s.attr, null);
            stated.span = s.attr;
        } else if (is(s, ":collapse")) {
            if (s.value != .flag) return;
            e.collapse = s.value.flag;
            if (own) stated.collapse = if (s.value.flag) s.attr else null;
        }
    }

    /// The layers of `class` above the defaults and below a subject's own,
    /// lowest first, into `sources`.
    fn collect(r: *Resolver, z: Ir.ZoneIndex, class: Env.Class) error{OutOfMemory}!void {
        r.sources.clearRetainingCapacity();
        const target: Env.Classes = .initOne(class);
        for (try r.chain(z)) |d| {
            if (r.statedKind(d)) |label| if (r.in.env.kind_places.get(label)) |case| {
                for (r.in.env.records.items[@backingInt(case.record)].bindings) |b| {
                    if (b.key != null) continue;
                    const classes = b.classes orelse continue;
                    if (classes.intersectWith(target).count() == 0) continue;
                    try r.sources.append(r.gpa, .{ .descriptor = b.descriptor, .value = b.value });
                }
            };
            if (d == z) try r.classBindings(null, target);
            try r.classBindings(d, target);
        }
    }

    /// The program's class bindings of `target` in diagram `in` (null: the
    /// top level's), in source order.
    fn classBindings(r: *Resolver, in: ?Ir.ZoneIndex, target: Env.Classes) error{OutOfMemory}!void {
        for (r.in.bindings) |b| if (placed(b) and b.subject == .class) {
            const c = b.subject.class;
            if (c.zone != in or c.classes.intersectWith(target).count() == 0) continue;
            try r.sources.append(r.gpa, .{ .descriptor = b.descriptor, .value = b.value, .attr = b.attr });
        };
    }

    /// The kind `d` states itself, if it does.
    fn statedKind(r: *const Resolver, d: Ir.ZoneIndex) ?[]const u8 {
        for (r.in.kinds) |k| if (k.zone == d and k.from == d) return k.label;
        return null;
    }

    /// `z`'s containers, outermost first, then `z`. The Resolver's, valid
    /// until the next call.
    fn chain(r: *Resolver, z: Ir.ZoneIndex) error{OutOfMemory}![]const Ir.ZoneIndex {
        r.chain_buffer.clearRetainingCapacity();
        var at: ?Ir.ZoneIndex = z;
        while (at) |d| : (at = r.ir.zones.items(.container)[@backingInt(d)]) try r.chain_buffer.append(r.gpa, d);
        std.mem.reverse(Ir.ZoneIndex, r.chain_buffer.items);
        return r.chain_buffer.items;
    }

    /// Collapsed edges by their two ends, whatever their direction, in a
    /// diagram: each group of two or more is a bundle. A cell's side is in
    /// none. An edge's own flag that bundles nothing is an error; a class's,
    /// collapsing what it can, is not.
    fn bundle(r: *Resolver, edges: []Place.Edge) error{OutOfMemory}![]const []const Ir.EdgeIndex {
        const ir = r.ir;
        const side = try r.gpa.alloc(bool, edges.len);
        defer r.gpa.free(side);
        @memset(side, false);
        for (ir.cells.items(.source), ir.cells.items(.target)) |s, t| for ([_]Ir.Cell.Side{ s, t }) |x| switch (x) {
            .edge => |e| side[@backingInt(e)] = true,
            else => {},
        };

        const Ends = struct { zone: Ir.ZoneIndex, lo: Ir.NodeIndex, hi: Ir.NodeIndex };
        var groups: std.AutoArrayHashMapUnmanaged(Ends, std.ArrayList(Ir.EdgeIndex)) = .empty;
        defer {
            for (groups.values()) |*l| l.deinit(r.gpa);
            groups.deinit(r.gpa);
        }
        for (edges, side, r.stated, ir.edges.items(.zone), ir.edges.items(.source), ir.edges.items(.target), 0..) |e, is_side, st, z, s, t, i| {
            if (!e.collapse) continue;
            if (is_side) {
                try r.report(&messages.collapse_cell_side, st.collapse, null);
                continue;
            }
            const ends: Ends = if (@backingInt(s) <= @backingInt(t))
                .{ .zone = z, .lo = s, .hi = t }
            else
                .{ .zone = z, .lo = t, .hi = s };
            const gop = try groups.getOrPut(r.gpa, ends);
            if (!gop.found_existing) gop.value_ptr.* = .empty;
            try gop.value_ptr.append(r.gpa, @fromBackingInt(@as(u32, @intCast(i))));
        }
        var out: std.ArrayList([]const Ir.EdgeIndex) = .empty;
        for (groups.values()) |l| {
            if (l.items.len < 2) {
                try r.report(&messages.collapse_different_ends, r.stated[@backingInt(l.items[0])].collapse, null);
                continue;
            }
            for (l.items) |e| edges[@backingInt(e)].bundle = @intCast(out.items.len);
            try out.append(r.arena, try r.arena.dupe(Ir.EdgeIndex, l.items));
        }
        return out.items;
    }

    /// Whether a diagram's stated spans admit ranks (`ranks.zig`).
    fn checkSpans(r: *Resolver, z: Ir.ZoneIndex, edges: []const Place.Edge) error{OutOfMemory}!void {
        var list: std.ArrayList(ranks.Edge) = .empty;
        defer list.deinit(r.gpa);
        var index: std.ArrayList(u32) = .empty;
        defer index.deinit(r.gpa);
        var any = false;
        const ir = r.ir;
        for (edges, ir.edges.items(.zone), ir.edges.items(.source), ir.edges.items(.target), 0..) |e, owner, s, t, i| {
            if (owner != z) continue;
            const stated: ?i64 = if (e.span) |x| (if (x.against) -@as(i64, x.ranks) else x.ranks) else null;
            any = any or stated != null;
            try list.append(r.gpa, .{ .source = @backingInt(s), .target = @backingInt(t), .span = stated });
            try index.append(r.gpa, @intCast(i));
        }
        if (!any) return;
        const conflict = try ranks.check(r.gpa, list.items) orelse return;
        const at = r.stated[index.items[conflict.at]].span;
        const related = if (conflict.related) |x| r.stated[index.items[x]].span else null;
        try r.report(&messages.spans_disagree, at, if (!std.meta.eql(related, at)) related else null);
    }
};

/// A descriptor's value in the program: what a diagnostic points at.
fn valueOf(cst: *const Cst, attr: Node.Index) Node.Index {
    const body = cst.data(attr).node;
    return if (body == .root) attr else body;
}

// ---------------------------------------------------------------------------
// Values, as the lattice reads them.

/// A whole number, with its `!`.
const Whole = struct { n: u64, inverted: bool };

fn whole(v: Value) Unread!Whole {
    return switch (v) {
        .number => |x| if (x.value.scale == 0) .{ .n = x.value.mantissa, .inverted = x.inverted } else error.NotWhole,
        else => error.NoDirection,
    };
}

/// `[x]` read where a list may go is a list of one.
fn single(v: Value) Value {
    return switch (v) {
        .elements => |es| if (es.len == 1) es[0] else v,
        else => v,
    };
}

fn seedOf(v: Value) Unread!Seed {
    const w = whole(single(v)) catch |err| return if (err == error.NotWhole) err else error.NotATiling;
    return Seed.of(w.n, w.inverted) orelse error.NotATiling;
}

/// A metric's steps, every one a number above zero: `v`'s own, or `v`.
fn steps(v: *const Value) Unread![]const Value {
    const items: []const Value = switch (v.*) {
        .elements => |es| es,
        else => @as(*const [1]Value, v),
    };
    for (items) |item| switch (item) {
        .number => |x| if (x.value.mantissa == 0) return error.StepOfNothing,
        else => return error.StepOfNothing,
    };
    if (items.len == 0) return error.StepOfNothing;
    return items;
}

fn span(v: Value) Unread!Place.Span {
    const w = whole(single(v)) catch |err| return if (err == error.NotWhole) err else error.SpanOfNothing;
    if (w.n == 0) return error.SpanOfNothing;
    return .{ .ranks = @intCast(@min(w.n, std.math.maxInt(u32))), .against = w.inverted };
}

/// A number or a normal of the seed: `[k]`, `[k!]`, `[k/]`.
const Bearing = struct {
    k: u64,
    inverted: bool,
    normal: bool,

    fn dir(b: Bearing, seed: Seed) Dir {
        return if (b.normal) seed.normal(b.k, b.inverted) else seed.edge(b.k, b.inverted);
    }
};

/// `:flow`: a direction (one bearing, or one or two letters) or an area
/// (two bearings of one edge). `[]` and `[//]` name none.
fn flowOf(seed: Seed, v: Value) Unread!Place.Flow {
    // `[area]` where a list may go: a list of one, its value.
    const one = single(v);
    const items: []const Value = switch (one) {
        .elements => |es| es,
        else => @as(*const [1]Value, &one),
    };
    if (items.len == 0) return error.NoDirection;

    if (items[0] == .label) {
        if (items.len > 2) return error.Cancel;
        const first = try letter(items[0]);
        const second = if (items.len == 2) try letter(items[1]) else null;
        return .{ .along = seed.letters(first, second) orelse return error.Cancel };
    }

    var bearings: [2]Bearing = undefined;
    var count: usize = 0;
    var i: usize = 0;
    while (i < items.len) {
        const w = try whole(items[i]);
        // A number followed by an empty slot is its normal.
        const normal = i + 1 < items.len and items[i + 1] == .nil;
        if (count == 2) return error.NotAnArea;
        bearings[count] = .{ .k = w.n % seed.n(), .inverted = w.inverted, .normal = normal };
        count += 1;
        i += if (normal) 2 else 1;
    }
    if (count == 1) return .{ .along = bearings[0].dir(seed) };
    return area(seed, bearings[0], bearings[1]);
}

fn letter(v: Value) Unread!grid.Letter {
    return switch (v) {
        .label => |l| grid.Letter.of(l.name, l.inverted) orelse error.NoDirection,
        else => error.NoDirection,
    };
}

/// Two bearings of edge k: the first `[k]` or `[k/]`, the second `[k]`,
/// `[k/]` or `[k+1]`, both of one seed, mirrored or not.
fn area(seed: Seed, first: Bearing, second: Bearing) Unread!Place.Flow {
    if (first.inverted != second.inverted) return error.NotAnArea;
    const k = first.k;
    const next = (k + 1) % seed.n();
    if (!(second.k == k or (second.k == next and !second.normal))) return error.NotAnArea;
    return .{ .area = .{
        .edge = @intCast(k),
        .mirrored = first.inverted,
        .sides = .{ seed.edge(k, first.inverted), seed.edge(next, first.inverted) },
        .legs = .{ first.dir(seed), second.dir(seed) },
    } };
}
