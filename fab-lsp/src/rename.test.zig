const std = @import("std");
const testing = std.testing;
const fab = @import("fab_core");
const rename = @import("rename.zig");
const navigation = @import("navigation.zig");

const uri = "file:///x.fab";

fn doc(source: []const u8) navigation.Document {
    return .{ .uri = uri, .source = source, .prelude_uri = null };
}

/// The source with the rename at `line:character` applied, or the reason
/// it was refused, prefixed `refused: `.
fn renamed(arena: std.mem.Allocator, source: []const u8, line: u32, character: u32, new_name: []const u8) ![]const u8 {
    const outcome = try rename.rename(arena, doc(source), .{ .line = line, .character = character }, new_name);
    const edit = switch (outcome) {
        .ok => |e| e,
        .refused => |why| return std.fmt.allocPrint(arena, "refused: {s}", .{why}),
    };
    var lines = try fab.Lines.init(arena, source);
    const edits = edit.changes.map.get(uri).?;
    // Applied back to front, so earlier offsets hold.
    var out: []const u8 = source;
    var i = edits.len;
    while (i > 0) {
        i -= 1;
        const r = edits[i].range;
        const start = lines.byteOffset(.{ .line = r.start.line, .character = r.start.character });
        const end = lines.byteOffset(.{ .line = r.end.line, .character = r.end.character });
        out = try std.mem.concat(arena, u8, &.{ out[0..start], edits[i].newText, out[end..] });
    }
    return out;
}

fn expectRenamed(source: []const u8, line: u32, character: u32, new_name: []const u8, want: []const u8) !void {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    try testing.expectEqualStrings(want, try renamed(arena.allocator(), source, line, character, new_name));
}

test "an edge, everywhere it is used, other diagrams included" {
    try expectRenamed("G :: f/g, +f/h\nH :: G.f+/k\nG.f :label \"x\"", 1, 7, "step", "G :: step/g, +step/h\nH :: G.step+/k\nG.step :label \"x\"");
}

test "an edge of another diagram keeps its name" {
    try expectRenamed("G :: f g\nH :: f h", 0, 5, "m", "G :: m g\nH :: f h");
}

test "a diagram, a node, a cell" {
    try expectRenamed("G :: f g\nH :: G/k\nG.f :label \"x\"", 0, 0, "Order", "Order :: f g\nH :: Order/k\nOrder.f :label \"x\"");
    try expectRenamed("G :: #A/f, #A/g", 0, 12, "#Start", "G :: #Start/f, #Start/g");
    try expectRenamed("G :: f/g | f/α/g", 0, 13, "β", "G :: f/g | f/β/g");
}

test "a type, a label, a value, a descriptor" {
    try expectRenamed(":Mood :: [calm]\n:Mood [quiet] := [calm]", 0, 2, ":Temper", ":Temper :: [calm]\n:Temper [quiet] := [calm]");
    try expectRenamed(":Mood :: [calm]\n:Mood [quiet] := [calm]", 1, 18, "still", ":Mood :: [still]\n:Mood [quiet] := [still]");
    try expectRenamed(":Mood :: [calm]\n:Mood [quiet] := [calm]", 1, 8, "hush", ":Mood :: [calm]\n:Mood [hush] := [calm]");
    try expectRenamed(":Mood :: [calm]\n&edge :mood :: :Mood\nG :: f\nG.f :mood [calm]", 1, 7, ":feel", ":Mood :: [calm]\n&edge :feel :: :Mood\nG :: f\nG.f :feel [calm]");
}

test "refused: built-ins, the prelude's" {
    try expectRenamed(":Shade :: :Color", 0, 11, ":Hue", "refused: `:Color` is built in: it can't be renamed.");
    try expectRenamed("G :: f\nG.f :label \"x\"", 1, 5, ":name", "refused: `:label` is the prelude's: it can't be renamed here.");
}

test "refused: a new name spelled for another sort, or taken" {
    try expectRenamed("G :: f g", 0, 5, "F", "refused: An edge's or a cell's name starts with a lowercase letter: `f`, `α`.");
    try expectRenamed("G :: f g", 0, 0, "g", "refused: A diagram's name starts with a capital: `G`, `Order`.");
    try expectRenamed("G :: f g", 0, 5, "f g", "refused: An edge's or a cell's name starts with a lowercase letter: `f`, `α`.");
    try expectRenamed(":Mood :: [calm]", 0, 10, "Calm", "refused: A label's or a value's name is lowercase letters and digits, with single hyphens: `dark-red`.");
    try expectRenamed("G :: f g", 0, 5, "g", "refused: `g` already names an edge or a cell in this diagram.");
    try expectRenamed("G :: f\nH :: g", 0, 0, "H", "refused: `H` already names a diagram.");
    // The prelude's names count: `[red]` is its colour.
    try expectRenamed(":Mood :: [calm]", 0, 10, "red", "refused: `red` already names a label or a value.");
}

test "refused: a name also written where the program couldn't be read" {
    try expectRenamed("G :: f g\nH :: f /k", 0, 5, "m", "refused: `f` is also written where the program couldn't be read: fix its errors first.");
}

test "prepare: the name's range, and its text" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const p = (try rename.prepare(arena.allocator(), doc(":Mood :: [calm]"), .{ .line = 0, .character = 11 })).ok;
    try testing.expectEqualStrings("calm", p.placeholder);
    try testing.expectEqual(@as(u32, 10), p.range.start.character);
    try testing.expect((try rename.prepare(arena.allocator(), doc("G :: f"), .{ .line = 0, .character = 3 })) == .refused);
}
