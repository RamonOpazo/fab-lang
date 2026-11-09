const std = @import("std");
const testing = std.testing;
const formatting = @import("formatting.zig");

test "one edit replaces the whole document with its printed form" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const edits = (try formatting.of(arena.allocator(), "G   ::  f\nLong :: g")).edits;
    try testing.expectEqual(@as(usize, 1), edits.len);
    try testing.expectEqualStrings("G    :: f\nLong :: g\n", edits[0].newText);
    try testing.expectEqual(@as(u32, 0), edits[0].range.start.line);
    try testing.expectEqual(@as(u32, 1), edits[0].range.end.line);
    try testing.expectEqual(@as(u32, 9), edits[0].range.end.character);
}

test "the end of the range counts UTF-16 units" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const edits = (try formatting.of(arena.allocator(), "N  :: f/α/g")).edits;
    try testing.expectEqual(@as(u32, 11), edits[0].range.end.character);
}

test "a formatted document needs no edit" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    try testing.expectEqual(@as(usize, 0), (try formatting.of(arena.allocator(), "G :: f\n")).edits.len);
}

test "a document with syntax errors is refused" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const outcome = try formatting.of(arena.allocator(), "G :: f ,, g");
    try testing.expect(outcome == .refused);
}
