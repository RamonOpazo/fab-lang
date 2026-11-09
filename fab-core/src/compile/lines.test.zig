const std = @import("std");
const testing = std.testing;
const Lines = @import("Lines.zig");

test "positions count lines from 0 and characters in UTF-16 units" {
    // "é" is two bytes and one unit; "𝔸" four bytes and two units.
    const source = "ab\né𝔸c\n";
    var lines = try Lines.init(testing.allocator, source);
    defer lines.deinit(testing.allocator);
    try testing.expectEqual(Lines.Position{ .line = 0, .character = 1 }, lines.position(1));
    try testing.expectEqual(Lines.Position{ .line = 1, .character = 0 }, lines.position(3));
    try testing.expectEqual(Lines.Position{ .line = 1, .character = 3 }, lines.position(9));
    try testing.expectEqual(@as(u32, 6), lines.utf16(9));
}

test "an offset is a position read back" {
    const source = "ab\né𝔸c\n";
    var lines = try Lines.init(testing.allocator, source);
    defer lines.deinit(testing.allocator);
    for ([_]u32{ 0, 1, 2, 3, 5, 9, 10, 11 }) |o| try testing.expectEqual(o, lines.byteOffset(lines.position(o)));
}

test "a position past a line's end is the line's end, past the last line the source's" {
    const source = "ab\ncd";
    var lines = try Lines.init(testing.allocator, source);
    defer lines.deinit(testing.allocator);
    try testing.expectEqual(@as(u32, 2), lines.byteOffset(.{ .line = 0, .character = 40 }));
    try testing.expectEqual(@as(u32, 5), lines.byteOffset(.{ .line = 1, .character = 40 }));
    try testing.expectEqual(@as(u32, 5), lines.byteOffset(.{ .line = 9, .character = 0 }));
}
