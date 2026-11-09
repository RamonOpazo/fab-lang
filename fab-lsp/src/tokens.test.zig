const std = @import("std");
const tokens = @import("tokens.zig");

const gpa = std.testing.allocator;

fn expectTokens(source: []const u8, expected: []const u32) !void {
    const data = try tokens.encode(gpa, source);
    defer gpa.free(data);
    try std.testing.expectEqualSlices(u32, expected, data);
}

const ns = @backingInt(tokens.Type.namespace);
const func = @backingInt(tokens.Type.function);
const op = @backingInt(tokens.Type.operator);
const decl = tokens.declaration;

test "a declaration: the diagram declared, then its edges" {
    // G :: f/g
    try expectTokens("G :: f/g", &.{
        0, 0, 1, ns,   decl,
        0, 2, 2, op,   0,
        0, 3, 1, func, 0,
        0, 1, 1, op,   0,
        0, 1, 1, func, 0,
    });
}

test "lines restart the start delta" {
    try expectTokens("G :: f\nH :: g", &.{
        0, 0, 1, ns,   decl,
        0, 2, 2, op,   0,
        0, 3, 1, func, 0,
        1, 0, 1, ns,   decl,
        0, 2, 2, op,   0,
        0, 3, 1, func, 0,
    });
}

test "positions count UTF-16 units" {
    // "é" is two bytes, one unit; "𝔸" four bytes, two units.
    try expectTokens("G :: f \"é𝔸\" g", &.{
        0, 0, 1, ns,                              decl,
        0, 2, 2, op,                              0,
        0, 3, 1, func,                            0,
        0, 2, 5, @backingInt(tokens.Type.string), 0,
        0, 6, 1, func,                            0,
    });
}

test "punctuation is not coloured" {
    try expectTokens("(,)", &.{});
}
