//! The grid (layout.md §3): the seed, and the directions its lattice serves,
//! each with its lattice vector. Pure and integer.
//!
//! Coordinates are the lattice's own, on the page with y pointing down. On
//! `[4]`, (x, y): east is (1, 0), south (0, 1). On `[3]`, (a, b) in the basis
//! e0 = east and e1 = south-west, 120° apart, so a point is drawn at
//! (a − b/2, b·√3/2) and Q(a, b) = a² − ab + b² (layout.md §3.5).
//!
//! A direction is an angle, clockwise from east, in steps of the lattice's
//! served directions (layout.md §3.3): 45° on `[4]`, eight of them; 30° on
//! `[3]`, twelve. Every number and normal is among them; a letter that is
//! not snaps to the nearest.

const std = @import("std");

/// `:grid`: `[4]` square, `[3]` triangular; `[4!]` drawn counterclockwise.
pub const Seed = struct {
    sides: Sides,
    /// Drawn counterclockwise, from the top right: every number's direction
    /// is mirrored in the seed's vertical axis.
    mirrored: bool = false,

    pub const Sides = enum(u8) { triangle = 3, square = 4 };

    pub const default: Seed = .{ .sides = .square };

    /// `[3]` or `[4]`, with its `!`; null for any other number, which is no
    /// seed (`layout.md` §3.2).
    pub fn of(sides: u64, mirrored: bool) ?Seed {
        return switch (sides) {
            3 => .{ .sides = .triangle, .mirrored = mirrored },
            4 => .{ .sides = .square, .mirrored = mirrored },
            else => null,
        };
    }

    pub fn n(seed: Seed) u8 {
        return @backingInt(seed.sides);
    }

    /// How many directions the lattice serves: 8 on `[4]`, 12 on `[3]`.
    pub fn served(seed: Seed) u8 {
        return switch (seed.sides) {
            .square => 8,
            .triangle => 12,
        };
    }

    /// `[k]`: along edge k, modulo n, in the seed's order of drawing;
    /// `[k!]`, `inverted`, in the mirrored seed's.
    pub fn edge(seed: Seed, k: u64, inverted: bool) Dir {
        const step = seed.served() / seed.n(); // 90° on [4], 120° on [3]
        const d: Dir = .{ .index = @intCast((k % seed.n()) * step) };
        return if (seed.mirrored != inverted) d.mirror(seed) else d;
    }

    /// `[k/]`: the normal to edge k, turned as the numbering turns:
    /// clockwise, or counterclockwise where mirrored. `[0/]` is south.
    pub fn normal(seed: Seed, k: u64, inverted: bool) Dir {
        const unmirrored: Seed = .{ .sides = seed.sides };
        const d = unmirrored.edge(k, false).turn(seed);
        return if (seed.mirrored != inverted) d.mirror(seed) else d;
    }

    /// A page direction, in degrees clockwise from east, snapped to the
    /// nearest the lattice serves; a tie goes to the first in the seed's
    /// order of drawing from `[0]`: clockwise on `[n]`, counterclockwise on
    /// `[n!]` (`[N/E]`, at 315°, is 300° on `[3]` and 330° on `[3!]`).
    pub fn snap(seed: Seed, degrees: u16) Dir {
        // A mirrored seed is the unmirrored one seen in a mirror.
        if (seed.mirrored) {
            const unmirrored: Seed = .{ .sides = seed.sides };
            return unmirrored.snap((540 - degrees) % 360).mirror(seed);
        }
        const step: u16 = 360 / @as(u16, seed.served());
        const q = degrees / step;
        const r = degrees % step;
        const index = (q + @intFromBool(2 * r > step)) % seed.served();
        return .{ .index = @intCast(index) };
    }

    /// Letters as the page names them (layout.md §3.3): `[E]` 0°, `[S]`
    /// 90°, `[W]` 180°, `[N]` 270°; two adjacent ones, the angle between
    /// them. Null for two that are not adjacent (`[N/S]`, `[S/S]`).
    pub fn letters(seed: Seed, first: Letter, second: ?Letter) ?Dir {
        const a = first.degrees();
        const b = (second orelse return seed.snap(a)).degrees();
        const apart = (b + 360 - a) % 360;
        if (apart == 90) return seed.snap((a + 45) % 360);
        if (apart == 270) return seed.snap((b + 45) % 360);
        return null;
    }
};

pub const Letter = enum(u8) {
    E,
    S,
    W,
    N,

    pub fn of(name: []const u8, inverted: bool) ?Letter {
        const l = std.meta.stringToEnum(Letter, name) orelse return null;
        // `!` mirrors in the vertical axis: `[E!]` is `[W]`, `[N!]` `[N]`.
        return if (!inverted) l else switch (l) {
            .E => .W,
            .W => .E,
            .N, .S => l,
        };
    }

    pub fn degrees(l: Letter) u16 {
        return @as(u16, @backingInt(l)) * 90;
    }
};

/// A direction the lattice serves: `index` steps clockwise from east.
pub const Dir = struct {
    index: u8,

    pub fn degrees(d: Dir, seed: Seed) u16 {
        return @as(u16, d.index) * (360 / @as(u16, seed.served()));
    }

    /// Mirrored in the vertical axis: θ becomes 180° − θ.
    pub fn mirror(d: Dir, seed: Seed) Dir {
        const full = seed.served();
        return .{ .index = @intCast((full + full / 2 - d.index) % full) };
    }

    /// A quarter turn clockwise.
    pub fn turn(d: Dir, seed: Seed) Dir {
        const full = seed.served();
        return .{ .index = (d.index + full / 4) % full };
    }

    /// Its primitive lattice vector, in the lattice's coordinates.
    pub fn vector(d: Dir, seed: Seed) Vector {
        return switch (seed.sides) {
            .square => square_vectors[d.index],
            .triangle => triangle_vectors[d.index],
        };
    }
};

pub const Vector = struct { a: i32, b: i32 };

/// Every 45°, clockwise from east.
const square_vectors = [8]Vector{
    .{ .a = 1, .b = 0 },  .{ .a = 1, .b = 1 },   .{ .a = 0, .b = 1 },  .{ .a = -1, .b = 1 },
    .{ .a = -1, .b = 0 }, .{ .a = -1, .b = -1 }, .{ .a = 0, .b = -1 }, .{ .a = 1, .b = -1 },
};

/// Every 30°, clockwise from east: the six unit vectors at 0°, 60°, … and
/// between them the six of length √3.
const triangle_vectors = [12]Vector{
    .{ .a = 1, .b = 0 },   .{ .a = 2, .b = 1 },   .{ .a = 1, .b = 1 },  .{ .a = 1, .b = 2 },
    .{ .a = 0, .b = 1 },   .{ .a = -1, .b = 1 },  .{ .a = -1, .b = 0 }, .{ .a = -2, .b = -1 },
    .{ .a = -1, .b = -1 }, .{ .a = -1, .b = -2 }, .{ .a = 0, .b = -1 }, .{ .a = 1, .b = -1 },
};
