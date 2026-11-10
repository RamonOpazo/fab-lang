const std = @import("std");
const testing = std.testing;
const hover = @import("hover.zig");
const navigation = @import("navigation.zig");

fn hoverAt(arena: std.mem.Allocator, source: []const u8, line: u32, character: u32) !?[]const u8 {
    const doc: navigation.Document = .{ .uri = "file:///x.fab", .source = source, .prelude_uri = null };
    const h = try hover.of(arena, doc, .{ .line = line, .character = character }) orelse return null;
    return h.contents.value;
}

const program =
    \\G :: #A/f g/? +(h, k)
    \\H :: f/g | f/α/g
    \\G.f :label "x"
    \\G.+g :fill [red]
    \\:Mood :: [calm]
    \\:Mood [quiet] := [calm]
;

fn expectHover(line: u32, character: u32, want: ?[]const u8) !void {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const got = try hoverAt(arena.allocator(), program, line, character);
    if (want) |w| try testing.expectEqualStrings(w, got.?) else try testing.expectEqual(null, got);
}

test "a diagram: its size" {
    try expectHover(0, 0, "**diagram** `G` · 5 nodes, 4 edges\n\n```fab\nG :: #A/f g/? +(h, k)\n```");
}

test "a diagram: its kind, its own or its container's (statements.md §24.2)" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const source = "A :: */f\nR :: A\nR :kind [git]";
    try testing.expectEqualStrings(
        "**diagram** `A` · 2 nodes, 1 edge; kind `[git]`, from `R`; in `R`\n\n```fab\nA :: */f\n```",
        (try hoverAt(arena.allocator(), source, 0, 0)).?,
    );
    try testing.expectEqualStrings(
        "**diagram** `R` · 1 node, 0 edges; kind `[git]`; holds `A`\n\n```fab\nR :: A\n```",
        (try hoverAt(arena.allocator(), source, 1, 0)).?,
    );
}

test "a diagram: what it holds, and what holds it (statements.md §23.2)" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const source = "A :: */f\nB :: */g\nDb :: A/h/B\nRepo :: Db, A";
    try testing.expectEqualStrings(
        "**diagram** `A` · 2 nodes, 1 edge; in `Db`\n\n```fab\nA :: */f\n```",
        (try hoverAt(arena.allocator(), source, 0, 0)).?,
    );
    try testing.expectEqualStrings(
        "**diagram** `Db` · 2 nodes, 1 edge; holds `A`, `B`; in `Repo`\n\n```fab\nDb :: A/h/B\n```",
        (try hoverAt(arena.allocator(), source, 2, 0)).?,
    );
    // A node standing for a diagram is named by it.
    try testing.expectEqualStrings(
        "**edge** `h` in `Db`: `A` → `B`\n\n```fab\nDb :: A/h/B\n```",
        (try hoverAt(arena.allocator(), source, 2, 8)).?,
    );
    try testing.expectEqualStrings(
        "**diagram** `Repo` · 2 nodes, 0 edges; holds `Db`, `A`\n\n```fab\nRepo :: Db, A\n```",
        (try hoverAt(arena.allocator(), source, 3, 0)).?,
    );
}

test "an edge: its ends, by name or by canonical end, and their kind" {
    try expectHover(0, 8, "**edge** `f` in `G`: `#A` → `f+`\n\n```fab\nG :: #A/f g/? +(h, k)\n```");
    try expectHover(0, 10, "**edge** `g` in `G`: `f+` → `g+` (choice)\n\n```fab\nG :: #A/f g/? +(h, k)\n```");
}

test "a node and a cell" {
    try expectHover(0, 5, "**node** `#A` in `G`\n\n```fab\nG :: #A/f g/? +(h, k)\n```");
    try expectHover(1, 13, "**cell** `α` in `H`, a 2-cell: `f` ⇒ `g`\n\n```fab\nH :: f/g | f/α/g\n```");
}

test "a descriptor: its type, its classes, its record type" {
    try expectHover(3, 6, "**descriptor** `:fill`: `(:Color, :Nil)`, on `&node`, `&zone`, in `:Style`, from the prelude\n\n```fab\n(&node, &zone)               :fill   :: (:Color, :Nil),\n```");
}

test "types, labels and values" {
    try expectHover(3, 12, "**value** `[red]`: `:Color`, from the prelude\n\n```fab\n:Color [red]    := [#cf222e]\n```");
    try expectHover(4, 1, "**type** `:Mood`\n\n```fab\n:Mood :: [calm]\n```");
    try expectHover(4, 10, "**label** `[calm]`, of `:Mood`\n\n```fab\n:Mood :: [calm]\n```");
    try expectHover(5, 8, "**value** `[quiet]`: `:Mood`\n\n```fab\n:Mood [quiet] := [calm]\n```");
}

test "no name, no hover" {
    try expectHover(0, 3, null);
}

test "a built-in type says so" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    try testing.expectEqualStrings("**type** `:Color`, built-in", (try hoverAt(arena.allocator(), ":Shade :: :Color", 0, 11)).?);
}
