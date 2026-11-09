const std = @import("std");
const testing = std.testing;
const fab = @import("fab_core");
const completion = @import("completion.zig");

/// The labels offered at the end of `text`, from `base`'s names, joined by
/// spaces.
fn offered(arena: std.mem.Allocator, text: []const u8, base: []const u8) ![]const u8 {
    var lines = try fab.Lines.init(arena, text);
    const end = lines.position(@intCast(text.len));
    const items = try completion.of(arena, text, base, .{ .line = end.line, .character = end.character });
    var labels: std.ArrayList([]const u8) = .empty;
    for (items) |item| try labels.append(arena, item.label);
    return std.mem.join(arena, " ", labels.items);
}

fn expectOffered(text: []const u8, want: []const u8) !void {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    try testing.expectEqualStrings(want, try offered(arena.allocator(), text, text));
}

const classes = "&node &plain &choice &parallel &start &end &hole &canonical &edge &cell &zone";

test "after a diagram's name and a dot: its parts" {
    try expectOffered("G :: @/f/#A g | f/α/g\nG.", "f g α #A @ " ++ classes);
    try expectOffered("G :: f/g, h\nH :: k\nG.g", "g");
    // A diagram not declared offers nothing.
    try expectOffered("G :: f\nK.", "");
}

test "a node's or an edge's name: the statement's diagram's" {
    try expectOffered("G :: #A/f, #B/g\nH :: #C/h\nG :: #", "#A #B");
    try expectOffered("G :: #A/f, #B/g\nG :: #B", "#B");
    try expectOffered("G :: fa/g, fb/h\nH :: fc\nG :: f", "fa fb");
}

test "diagrams, classes, types" {
    try expectOffered("Order :: f\nOther :: g\nO", "Order Other");
    try expectOffered("&no", "&node");
    try expectOffered("&", classes);
    try expectOffered(":Mood :: [calm]\n:Shade :: :Mo", ":Mood");
    try testing.expect(std.mem.indexOf(u8, try offeredOnce(":Shade :: :"), ":Color") != null);
}

fn offeredOnce(text: []const u8) ![]const u8 {
    const S = struct {
        var buffer: [8192]u8 = undefined;
    };
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const got = try offered(arena.allocator(), text, text);
    @memcpy(S.buffer[0..got.len], got);
    return S.buffer[0..got.len];
}

test "nothing to offer: no name typed, or a space before the cursor" {
    try expectOffered("G :: f ", "");
    try expectOffered("", "");
}

test "the names come from the base: the last text with no syntax errors" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    // G's own statement is broken now: read alone, G has no parts.
    const broken = "G :: f g /\nG.";
    try testing.expectEqualStrings("", try offered(arena.allocator(), broken, broken));
    try testing.expectEqualStrings("f g " ++ classes, try offered(arena.allocator(), broken, "G :: f g"));
}

test "an item replaces the name typed, its sigil included" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const items = try completion.of(arena.allocator(), "G :: #A/f\nG :: #", "G :: #A/f\nG :: #", .{ .line = 1, .character = 6 });
    try testing.expectEqual(1, items.len);
    try testing.expectEqual(@as(u32, 5), items[0].textEdit.range.start.character);
    try testing.expectEqual(@as(u32, 6), items[0].textEdit.range.end.character);
}

// The prelude's descriptors, by the classes they apply to.
const edge_descriptors = ":arrow :bend :ink :label :label-at :label-end :label-start :link :note :pen :shorten :side :size :step :stroke";
const zone_descriptors = ":alt :as :caption :cross :face :fill :font :ink :label :line :link :marks :note :padding :pen :size :stroke :theme";

test "descriptors at a context: by the subject's classes" {
    try expectOffered("G :: f/g\nG.f :bend [inner] :la", ":label :label-at :label-end :label-start");
    try expectOffered("G :: #A/f\nG.#A :sh", ":shape");
    try expectOffered("G :: f/?\nG.f+ :sh", ":shape");
    try expectOffered("G :: f\nG :ca", ":caption");
    // At the top level a diagram can open its layer; inside, it can't.
    try expectOffered("G :: f\nG :st", ":stroke :style");
    try expectOffered("G :: f\nG :style { :st", ":stroke");
    try expectOffered("&edge :sh", ":shorten");
}

test "descriptors in a block: the entry's context, or the block's owner" {
    try expectOffered("G :: #A/f\nG :style { :label \"x\", f :ar", ":arrow");
    try expectOffered("G :: #A/f\nG :style {\n  #A { :sh", ":shape");
    try expectOffered("G :: #A/f\nG :style { #A :fill [red], :cap", ":caption");
    try expectOffered("G :: #A/f\nG :style { f :ar }\nG.#A :sh", ":shape");
}

test "a group's descriptors fit every subject" {
    try expectOffered("G :: #A/f\nG :style { (f, #A) :s", ":size :step :stroke");
}

test "no descriptors where there is no subject" {
    // A chain, parts of an element, a declaration, a type's block.
    try expectOffered("G :: f g\nG :style { f g :", "");
    try expectOffered("G :: #A/f\nG :style { #A { f :", "");
    try expectOffered("G :: f :", "");
    try expectOffered(":Mood :: { &node :", "");
}

test "a name not yet declared is judged by its sort" {
    try expectOffered("G :: f\nG.g :sh", ":shorten");
    try expectOffered("G :: f\nG.#B :sh", ":shape");
}
