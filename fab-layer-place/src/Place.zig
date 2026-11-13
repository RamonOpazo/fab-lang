//! A program's place, resolved (layout.md, statements.md §29; plan step α4):
//! per diagram its seed, its metric and its flow; per edge its span and its
//! collapse; the bundles of collapsed edges. Indexed as the IR's tables.
//!
//! What it holds is what fab-layer-place's solver reads (step β): the
//! values as the lattice understands them, every default filled in.

const std = @import("std");
const fab = @import("fab_core");
const Ir = fab.Ir;
const Decimal = fab.Decimal;
const grid = @import("grid.zig");

const Place = @This();

arena: std.heap.ArenaAllocator,
ir: *const Ir,
/// One per IR zone.
zones: []const Zone,
/// One per IR edge.
edges: []const Edge,
/// Edges with the same two ends, each flagged `:collapse`, in source order:
/// two or more, drawn as one route.
bundles: []const []const Ir.EdgeIndex,
/// The layer's own (statements.md §29), in fab-core's shape.
diagnostics: []const fab.Diagnostic,

pub const Seed = grid.Seed;
pub const Dir = grid.Dir;

pub const Zone = struct {
    seed: Seed = .default,
    /// `[1/2/3!]`: steps repeating, each turning the sequence back where
    /// marked.
    metric: []const Step = &.{.{}},
    flow: Flow,
};

/// One step of a metric: how long it is drawn, relative to the base step.
pub const Step = struct {
    length: Decimal = .{ .mantissa = 1, .scale = 0 },
    /// `!`: the sequence reads back from here, this step not repeated.
    turn: bool = false,
};

pub const Flow = union(enum) {
    /// Along a direction: ranks grow along it, a commuting square drawn as a
    /// diamond.
    along: Dir,
    /// Across an area: both its sides one rank, a square drawn upright.
    area: Area,
};

/// The area of edge k (layout.md §4), between e_k and e_k+1.
pub const Area = struct {
    edge: u8,
    /// Of the mirrored seed (`[0!/1!]`).
    mirrored: bool,
    /// e_k and e_k+1, each one rank.
    sides: [2]Dir,
    /// Where a node with one child sends it, alternately, down a chain:
    /// `[0/0]` east twice, `[0//0/]` the normal twice, `[0/1]` a stair.
    legs: [2]Dir,
};

pub const Edge = struct {
    /// Null when no layer states it: one rank, stretched where branches must
    /// agree (layout.md §5).
    span: ?Span = null,
    collapse: bool = false,
    /// Its bundle in `bundles`, when it is in one.
    bundle: ?u32 = null,
};

/// `:span [k]`: the ranks an edge crosses; `[k!]` against the flow.
pub const Span = struct { ranks: u32, against: bool = false };

pub fn deinit(p: *Place) void {
    p.arena.deinit();
    p.* = undefined;
}

// ---------------------------------------------------------------------------
// Dump: zone by zone, in Ir.dump's shape, then its edges with something
// stated, then its bundles. The format of `fab show place` and of the
// corpus's `.place` rows.
//
//   zone G grid [4] metric [1] flow 90° (0,1)       along a direction
//   zone Sq grid [4] metric [1] flow area 0 sides 0° 90° legs 0° 0°
//   zone T grid [3!] metric [1/2!] flow 90° (1,2)
//   zone A in G grid [4] metric [1] flow 90° (0,1)  A's first container is G
//     edge n span 2
//     edge m span 1!                                  against the flow
//     edge f collapse
//     bundle f g

pub fn dump(p: *const Place, w: *std.Io.Writer) std.Io.Writer.Error!void {
    const ir = p.ir;
    for (p.zones, 0..) |zone, z| {
        try w.print("zone {s}", .{ir.string(ir.zones.items(.name)[z])});
        if (ir.zones.items(.container)[z]) |c| try w.print(" in {s}", .{ir.string(ir.zones.items(.name)[@backingInt(c)])});
        try w.print(" grid [{d}{s}] metric [", .{ zone.seed.n(), if (zone.seed.mirrored) "!" else "" });
        for (zone.metric, 0..) |step, i| {
            if (i > 0) try w.writeByte('/');
            try step.length.format(w);
            if (step.turn) try w.writeByte('!');
        }
        try w.writeAll("] flow ");
        switch (zone.flow) {
            .along => |d| try writeDir(d, zone.seed, true, w),
            .area => |a| {
                try w.print("area {d}{s} sides ", .{ a.edge, if (a.mirrored) "!" else "" });
                try writeDir(a.sides[0], zone.seed, false, w);
                try w.writeByte(' ');
                try writeDir(a.sides[1], zone.seed, false, w);
                try w.writeAll(" legs ");
                try writeDir(a.legs[0], zone.seed, false, w);
                try w.writeByte(' ');
                try writeDir(a.legs[1], zone.seed, false, w);
            },
        }
        try w.writeByte('\n');

        for (p.edges, ir.edges.items(.zone), ir.edges.items(.name)) |edge, owner, name| {
            if (@backingInt(owner) != z or (edge.span == null and !edge.collapse)) continue;
            try w.print("  edge {s}", .{ir.string(name)});
            if (edge.span) |s| try w.print(" span {d}{s}", .{ s.ranks, if (s.against) "!" else "" });
            if (edge.collapse) try w.writeAll(" collapse");
            try w.writeByte('\n');
        }
        for (p.bundles) |bundle| {
            if (@backingInt(ir.edges.items(.zone)[@backingInt(bundle[0])]) != z) continue;
            try w.writeAll("  bundle");
            for (bundle) |e| try w.print(" {s}", .{ir.string(ir.edges.items(.name)[@backingInt(e)])});
            try w.writeByte('\n');
        }
    }
}

/// `90°`, and with `vector` its lattice vector, `90° (0,1)`.
fn writeDir(d: Dir, seed: Seed, vector: bool, w: *std.Io.Writer) std.Io.Writer.Error!void {
    try w.print("{d}°", .{d.degrees(seed)});
    if (vector) {
        const v = d.vector(seed);
        try w.print(" ({d},{d})", .{ v.a, v.b });
    }
}
