const std = @import("std");
const testing = std.testing;
const fab = @import("fab_core");
const navigation = @import("navigation.zig");
const Message = @import("Message.zig");

const prelude_uri = "file:///cache/fab/prelude.fab";

fn doc(source: []const u8) navigation.Document {
    return .{ .uri = "file:///x.fab", .source = source, .prelude_uri = prelude_uri };
}

fn at(line: u32, character: u32) Message.Position {
    return .{ .line = line, .character = character };
}

fn range(l0: u32, c0: u32, l1: u32, c1: u32) Message.Range {
    return .{ .start = at(l0, c0), .end = at(l1, c1) };
}

/// The text a range of `source` covers, on one line.
fn textOf(source: []const u8, r: Message.Range) ![]const u8 {
    var lines = try fab.Lines.init(testing.allocator, source);
    defer lines.deinit(testing.allocator);
    return source[lines.byteOffset(.{ .line = r.start.line, .character = r.start.character })..lines.byteOffset(.{ .line = r.end.line, .character = r.end.character })];
}

test "a name's definition, from the name or just after it" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const source = "G :: f g\nH :: G.f+/h";
    for ([_]u32{ 7, 8 }) |c| {
        const l = (try navigation.definition(arena.allocator(), doc(source), at(1, c))).?;
        try testing.expectEqualStrings("file:///x.fab", l.uri);
        try testing.expectEqual(range(0, 5, 0, 6), l.range);
    }
    // The diagram's name, too.
    const g = (try navigation.definition(arena.allocator(), doc(source), at(1, 5))).?;
    try testing.expectEqual(range(0, 0, 0, 1), g.range);
}

test "nothing to navigate: no name, a built-in" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    try testing.expectEqual(null, try navigation.definition(a, doc("G :: f"), at(0, 3)));
    try testing.expectEqual(null, try navigation.definition(a, doc(":Shade :: :Color"), at(0, 11)));
    try testing.expectEqual(0, (try navigation.references(a, doc("G :: f"), at(0, 3), true)).len);
}

test "a prelude name's definition is in the prelude's file, if there is one" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const source = "G :: f\nG.f :label \"x\"";
    const l = (try navigation.definition(arena.allocator(), doc(source), at(1, 5))).?;
    try testing.expectEqualStrings(prelude_uri, l.uri);
    try testing.expectEqualStrings(":label", try textOf(fab.Compilation.prelude_source, l.range));

    var without = doc(source);
    without.prelude_uri = null;
    try testing.expectEqual(null, try navigation.definition(arena.allocator(), without, at(1, 5)));
}

test "references: the uses, with or without the definition" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const source = "G :: f/g, +f/h\nG.f :label \"x\"";
    const all = try navigation.references(a, doc(source), at(0, 11), true);
    try testing.expectEqual(3, all.len);
    try testing.expectEqual(range(0, 5, 0, 6), all[0].range);
    try testing.expectEqual(range(0, 11, 0, 12), all[1].range);
    try testing.expectEqual(range(1, 2, 1, 3), all[2].range);
    try testing.expectEqual(2, (try navigation.references(a, doc(source), at(0, 5), false)).len);
}

test "references to a prelude name end at its definition there" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const source = "G :: f, g\nG.f :label \"x\"\nG.g :label \"y\"";
    const with = try navigation.references(a, doc(source), at(1, 6), true);
    try testing.expectEqual(3, with.len);
    try testing.expectEqualStrings(prelude_uri, with[2].uri);
    try testing.expectEqual(2, (try navigation.references(a, doc(source), at(1, 6), false)).len);
}

test "highlights: the definition written, the uses read" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const h = try navigation.highlights(arena.allocator(), doc("G :: f/g, +f/h"), at(0, 11));
    try testing.expectEqual(2, h.len);
    try testing.expectEqual(Message.DocumentHighlight.write, h[0].kind);
    try testing.expectEqual(Message.DocumentHighlight.read, h[1].kind);
}

test "a label's definition is the bracket declaring it" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const source = ":Mood :: [calm], [wild]\n:Mood [quiet] := [calm]";
    const l = (try navigation.definition(a, doc(source), at(1, 18))).?;
    try testing.expectEqualStrings("[calm]", try textOf(source, l.range));
    // The use inside the declaring bracket is its definition, written.
    const h = try navigation.highlights(a, doc(source), at(0, 10));
    try testing.expectEqual(2, h.len);
    try testing.expectEqual(Message.DocumentHighlight.write, h[0].kind);
}
