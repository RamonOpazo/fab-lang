//! Tests for grid.zig: seeds, directions and their lattice vectors.

const std = @import("std");
const testing = std.testing;
const grid = @import("grid.zig");

const square: grid.Seed = .{ .sides = .square };
const triangle: grid.Seed = .{ .sides = .triangle };

fn expectDir(seed: grid.Seed, d: grid.Dir, degrees: u16, a: i32, b: i32) !void {
    try testing.expectEqual(degrees, d.degrees(seed));
    try testing.expectEqual(grid.Vector{ .a = a, .b = b }, d.vector(seed));
}

test "only [3] and [4] are seeds" {
    try testing.expect(grid.Seed.of(4, false) != null);
    try testing.expect(grid.Seed.of(3, true).?.mirrored);
    for ([_]u64{ 0, 1, 2, 5, 6, 8 }) |n| try testing.expectEqual(@as(?grid.Seed, null), grid.Seed.of(n, false));
}

test "edges run clockwise from east, modulo n; [0] is east on every seed" {
    try expectDir(square, square.edge(0, false), 0, 1, 0);
    try expectDir(square, square.edge(1, false), 90, 0, 1);
    try expectDir(square, square.edge(2, false), 180, -1, 0);
    try expectDir(square, square.edge(3, false), 270, 0, -1);
    try expectDir(square, square.edge(5, false), 90, 0, 1);
    // [3]: east, south-west, north-west.
    try expectDir(triangle, triangle.edge(0, false), 0, 1, 0);
    try expectDir(triangle, triangle.edge(1, false), 120, 0, 1);
    try expectDir(triangle, triangle.edge(2, false), 240, -1, -1);
}

test "every lattice vector has the length its angle says" {
    // Q on [4] is a² + b²; on [3], a² − ab + b²: 1 at every 60°, 3 between.
    for (0..8) |i| {
        const v = (grid.Dir{ .index = @intCast(i) }).vector(square);
        try testing.expectEqual(@as(i32, if (i % 2 == 0) 1 else 2), v.a * v.a + v.b * v.b);
    }
    for (0..12) |i| {
        const v = (grid.Dir{ .index = @intCast(i) }).vector(triangle);
        try testing.expectEqual(@as(i32, if (i % 2 == 0) 1 else 3), v.a * v.a - v.a * v.b + v.b * v.b);
    }
}

test "k! is the mirrored seed's direction k; a mirrored seed mirrors every number" {
    try expectDir(square, square.edge(0, true), 180, -1, 0);
    try expectDir(square, square.edge(1, true), 90, 0, 1); // on the axis
    try expectDir(triangle, triangle.edge(1, true), 60, 1, 1);
    try expectDir(triangle, triangle.edge(2, true), 300, 0, -1);
    const mirrored: grid.Seed = .{ .sides = .square, .mirrored = true };
    try expectDir(mirrored, mirrored.edge(0, false), 180, -1, 0);
    try expectDir(mirrored, mirrored.edge(0, true), 0, 1, 0);
}

test "a normal turns clockwise as the numbering does: [0/] is south" {
    try expectDir(square, square.normal(0, false), 90, 0, 1);
    try expectDir(square, square.normal(1, false), 180, -1, 0);
    try expectDir(triangle, triangle.normal(0, false), 90, 1, 2);
    try expectDir(triangle, triangle.normal(1, false), 210, -2, -1);
    const mirrored: grid.Seed = .{ .sides = .square, .mirrored = true };
    try expectDir(mirrored, mirrored.normal(0, false), 90, 0, 1);
    try expectDir(mirrored, mirrored.normal(1, false), 0, 1, 0);
}

test "letters are the page's, snapped to what the lattice serves" {
    const L = grid.Letter;
    try expectDir(square, square.letters(.S, null).?, 90, 0, 1);
    try expectDir(square, square.letters(.S, .E).?, 45, 1, 1);
    try expectDir(square, square.letters(.E, .S).?, 45, 1, 1);
    try expectDir(square, square.letters(.N, .E).?, 315, 1, -1);
    try expectDir(triangle, triangle.letters(.S, null).?, 90, 1, 2);
    try expectDir(triangle, triangle.letters(.N, null).?, 270, -1, -2);
    // 45° on [3] ties 30° and 60°: the first clockwise from east.
    try expectDir(triangle, triangle.letters(.S, .E).?, 30, 2, 1);
    try expectDir(triangle, triangle.letters(.N, .E).?, 300, 0, -1);
    try expectDir(triangle, triangle.letters(.S, .W).?, 120, 0, 1);
    // On [3!], counterclockwise from [0], as the seed is drawn.
    const mirrored: grid.Seed = .{ .sides = .triangle, .mirrored = true };
    try expectDir(mirrored, mirrored.letters(.N, .E).?, 330, 1, -1);
    try expectDir(mirrored, mirrored.letters(.S, .E).?, 60, 1, 1);
    try expectDir(mirrored, mirrored.letters(.S, .W).?, 150, -1, 1);
    try expectDir(mirrored, mirrored.letters(.S, null).?, 90, 1, 2);
    try testing.expectEqual(@as(?grid.Dir, null), square.letters(.N, .S));
    try testing.expectEqual(@as(?grid.Dir, null), square.letters(.S, .S));
    try testing.expectEqual(L.W, L.of("E", true).?);
    try testing.expectEqual(L.N, L.of("N", true).?);
    try testing.expectEqual(@as(?L, null), L.of("X", false));
}
