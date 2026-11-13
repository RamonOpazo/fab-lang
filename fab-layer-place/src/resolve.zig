//! From fab-core's analysis to the Place (plan step α4): each descriptor's
//! value, by precedence, read against the seed.
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
//! A value the lattice can't read (`:grid [5]`, `:flow [0/2]`) is passed
//! over, so the layer below stands; step α5 reports it.

const std = @import("std");
const fab = @import("fab_core");
const Ir = fab.Ir;
const Env = fab.Env;
const decoded = fab.decoded;
const layers = fab.layers;
const grid = @import("grid.zig");
const Place = @import("Place.zig");

const Value = decoded.Value;
const Seed = grid.Seed;
const Dir = grid.Dir;

/// What the layer reads besides the IR.
pub const Inputs = struct {
    env: *const Env,
    bindings: []const layers.Binding = &.{},
    /// Each diagram's kind in effect, and the diagram stating it.
    kinds: []const layers.Kind = &.{},
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
    const edge_zones = ir.edges.items(.zone);
    for (zones, 0..) |*zone, z| {
        const index: Ir.ZoneIndex = @fromBackingInt(@as(u32, @intCast(z)));
        zone.* = try r.zone(index);
        // The edges' layers above the defaults, the same for every edge of
        // the diagram.
        try r.collect(index, .edge);
        var common: Place.Edge = .{};
        for (r.sources.items) |s| bindEdge(&common, s);
        for (edges, edge_zones) |*e, owner| if (owner == index) {
            e.* = common;
        };
    }
    for (in.bindings) |b| if (placed(b)) switch (b.subject) {
        .edge => |e| bindEdge(&edges[@backingInt(e)], .{ .descriptor = b.descriptor, .value = b.value }),
        else => {},
    };

    place.zones = zones;
    place.edges = edges;
    place.bundles = try r.bundle(edges);
    return place;
}

/// A binding of place's, as the layer reads it.
const Source = struct { descriptor: []const u8, value: Value };

fn placed(b: layers.Binding) bool {
    return b.layer == .place and b.key == null;
}

fn bindEdge(e: *Place.Edge, s: Source) void {
    if (is(s, ":span")) {
        if (span(s.value)) |x| e.span = x;
    } else if (is(s, ":collapse")) {
        if (s.value == .flag) e.collapse = s.value.flag;
    }
}

fn is(s: Source, name: []const u8) bool {
    return std.mem.eql(u8, s.descriptor, name);
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

    fn deinit(r: *Resolver) void {
        r.sources.deinit(r.gpa);
        r.chain_buffer.deinit(r.gpa);
    }

    /// A diagram's place: its layers folded, the flow read against the seed
    /// they settle.
    fn zone(r: *Resolver, z: Ir.ZoneIndex) error{OutOfMemory}!Place.Zone {
        try r.collect(z, .zone);
        for (r.in.bindings) |b| if (placed(b) and b.subject == .zone and b.subject.zone == z) {
            try r.sources.append(r.gpa, .{ .descriptor = b.descriptor, .value = b.value });
        };
        var seed: Seed = .default;
        var metric: ?Value = null;
        for (r.sources.items) |s| {
            if (is(s, ":grid")) {
                if (seedOf(s.value)) |x| seed = x;
            } else if (is(s, ":metric")) {
                if (steps(&s.value) != null) metric = s.value;
            }
        }
        // The highest flow the seed can read, else `[S]`.
        var flow: Place.Flow = .{ .along = seed.letters(.S, null).? };
        for (r.sources.items) |s| if (is(s, ":flow")) {
            if (flowOf(seed, s.value)) |f| flow = f;
        };
        var zone_place: Place.Zone = .{ .seed = seed, .flow = flow };
        if (metric) |*m| {
            const items = steps(m).?;
            const out = try r.arena.alloc(Place.Step, items.len);
            for (items, out) |item, *step| step.* = .{ .length = item.number.value, .turn = item.number.inverted };
            zone_place.metric = out;
        }
        return zone_place;
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
            try r.sources.append(r.gpa, .{ .descriptor = b.descriptor, .value = b.value });
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
    /// diagram: each group of two or more is a bundle.
    fn bundle(r: *Resolver, edges: []Place.Edge) error{OutOfMemory}![]const []const Ir.EdgeIndex {
        const Ends = struct { zone: Ir.ZoneIndex, lo: Ir.NodeIndex, hi: Ir.NodeIndex };
        var groups: std.AutoArrayHashMapUnmanaged(Ends, std.ArrayList(Ir.EdgeIndex)) = .empty;
        defer {
            for (groups.values()) |*l| l.deinit(r.gpa);
            groups.deinit(r.gpa);
        }
        const ir = r.ir;
        for (edges, ir.edges.items(.zone), ir.edges.items(.source), ir.edges.items(.target), 0..) |e, z, s, t, i| {
            if (!e.collapse) continue;
            const ends: Ends = if (@backingInt(s) <= @backingInt(t))
                .{ .zone = z, .lo = s, .hi = t }
            else
                .{ .zone = z, .lo = t, .hi = s };
            const gop = try groups.getOrPut(r.gpa, ends);
            if (!gop.found_existing) gop.value_ptr.* = .empty;
            try gop.value_ptr.append(r.gpa, @fromBackingInt(@as(u32, @intCast(i))));
        }
        var out: std.ArrayList([]const Ir.EdgeIndex) = .empty;
        for (groups.values()) |l| if (l.items.len >= 2) {
            for (l.items) |e| edges[@backingInt(e)].bundle = @intCast(out.items.len);
            try out.append(r.arena, try r.arena.dupe(Ir.EdgeIndex, l.items));
        };
        return out.items;
    }
};

// ---------------------------------------------------------------------------
// Values, as the lattice reads them. Each returns null for what it can't.

/// A whole number, with its `!`.
const Whole = struct { n: u64, inverted: bool };

fn whole(v: Value) ?Whole {
    return switch (v) {
        .number => |x| if (x.value.scale == 0) .{ .n = x.value.mantissa, .inverted = x.inverted } else null,
        else => null,
    };
}

/// `[x]` read where a list may go is a list of one.
fn single(v: Value) Value {
    return switch (v) {
        .elements => |es| if (es.len == 1) es[0] else v,
        else => v,
    };
}

fn seedOf(v: Value) ?Seed {
    const w = whole(single(v)) orelse return null;
    return Seed.of(w.n, w.inverted);
}

/// A metric's steps, every one a number above zero: `v`'s own, or `v`.
fn steps(v: *const Value) ?[]const Value {
    const items: []const Value = switch (v.*) {
        .elements => |es| es,
        .number => @as(*const [1]Value, v),
        else => return null,
    };
    if (items.len == 0) return null;
    for (items) |item| switch (item) {
        .number => |x| if (x.value.mantissa == 0) return null,
        else => return null,
    };
    return items;
}

fn span(v: Value) ?Place.Span {
    const w = whole(single(v)) orelse return null;
    if (w.n == 0 or w.n > std.math.maxInt(u32)) return null;
    return .{ .ranks = @intCast(w.n), .against = w.inverted };
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
/// (two bearings of one edge).
fn flowOf(seed: Seed, v: Value) ?Place.Flow {
    // `[area]` where a list may go: a list of one, its value.
    const one = single(v);
    const items: []const Value = switch (one) {
        .elements => |es| es,
        else => @as(*const [1]Value, &one),
    };
    if (items.len == 0) return null;

    if (items[0] == .label) {
        if (items.len > 2) return null;
        const first = letter(items[0]) orelse return null;
        const second = if (items.len == 2) letter(items[1]) orelse return null else null;
        return .{ .along = seed.letters(first, second) orelse return null };
    }

    var bearings: [2]Bearing = undefined;
    var count: usize = 0;
    var i: usize = 0;
    while (i < items.len) {
        const w = whole(items[i]) orelse return null;
        // A number followed by an empty slot is its normal.
        const normal = i + 1 < items.len and items[i + 1] == .nil;
        if (count == 2) return null;
        bearings[count] = .{ .k = w.n % seed.n(), .inverted = w.inverted, .normal = normal };
        count += 1;
        i += if (normal) 2 else 1;
    }
    if (count == 1) return .{ .along = bearings[0].dir(seed) };
    return area(seed, bearings[0], bearings[1]);
}

fn letter(v: Value) ?grid.Letter {
    return switch (v) {
        .label => |l| grid.Letter.of(l.name, l.inverted),
        else => null,
    };
}

/// Two bearings of edge k: the first `[k]` or `[k/]`, the second `[k]`,
/// `[k/]` or `[k+1]`, both of one seed, mirrored or not.
fn area(seed: Seed, first: Bearing, second: Bearing) ?Place.Flow {
    if (first.inverted != second.inverted) return null;
    const k = first.k;
    const next = (k + 1) % seed.n();
    if (!(second.k == k or (second.k == next and !second.normal))) return null;
    return .{ .area = .{
        .edge = @intCast(k),
        .mirrored = first.inverted,
        .sides = .{ seed.edge(k, first.inverted), seed.edge(next, first.inverted) },
        .legs = .{ first.dir(seed), second.dir(seed) },
    } };
}
