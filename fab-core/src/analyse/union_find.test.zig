//! Tests for UnionFind.zig: merging, the join of annotations, conflicts,
//! holes, and rollback.
//!
//! Run on their own with `zig test src/analyse/union_find.test.zig`.

const std = @import("std");
const testing = std.testing;
const Ir = @import("Ir.zig");
const UnionFind = @import("UnionFind.zig");

const no_conflict: ?UnionFind.Conflict = null;

test "the oldest element stays root, whichever side it is on" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    var uf: UnionFind = .init(arena.allocator());
    const a = try uf.add(0, null, .{});
    const b = try uf.add(0, null, .{});
    const c = try uf.add(0, null, .{});

    try testing.expectEqual(no_conflict, try uf.unite(c, b));
    try testing.expectEqual(b, uf.find(c));
    try testing.expectEqual(no_conflict, try uf.unite(c, a));
    try testing.expectEqual(a, uf.find(b));
    try testing.expectEqual(a, uf.find(c));
    try testing.expectEqual(@as(u32, 3), uf.class(c).size);
}

test "annotations join: a kind and a name end up on one class" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    var uf: UnionFind = .init(arena.allocator());
    const a = try uf.add(0, null, .{ .kind = .choice, .kind_token = 4 });
    const b = try uf.add(0, null, .{ .name = "#Valid", .name_token = 7 });

    try testing.expectEqual(no_conflict, try uf.unite(a, b));
    const joined = uf.class(b);
    try testing.expectEqual(Ir.Node.Kind.choice, joined.kind.?);
    try testing.expectEqualStrings("#Valid", joined.name.?);
}

test "conflicts are returned and change nothing" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    var uf: UnionFind = .init(arena.allocator());
    const choice = try uf.add(0, null, .{ .kind = .choice, .kind_token = 1 });
    const parallel = try uf.add(0, null, .{ .kind = .parallel, .kind_token = 2 });
    const choice2 = try uf.add(0, null, .{ .kind = .choice, .kind_token = 3 });
    const a = try uf.add(0, null, .{ .name = "#A", .name_token = 4 });
    const b = try uf.add(0, null, .{ .name = "#B", .name_token = 5 });
    const sealed = try uf.add(0, null, .{ .sealed = true });
    const outer_f = try uf.add(0, null, .{ .outer = 0 });
    const outer_g = try uf.add(0, null, .{ .outer = 1 });

    try testing.expectEqual(UnionFind.Conflict{ .tag = .different_kinds, .related = 2 }, (try uf.unite(choice, parallel)).?);
    try testing.expectEqual(UnionFind.Conflict{ .tag = .same_kind, .related = 3 }, (try uf.unite(choice, choice2)).?);
    try testing.expectEqual(UnionFind.Conflict{ .tag = .two_names, .related = 4 }, (try uf.unite(a, b)).?);
    try testing.expectEqual(UnionFind.Conflict{ .tag = .sealed_end }, (try uf.unite(a, sealed)).?);
    try testing.expectEqual(UnionFind.Conflict{ .tag = .two_outer_edges }, (try uf.unite(outer_f, outer_g)).?);

    // Every class is still on its own.
    for (0..uf.len()) |i| try testing.expectEqual(@as(u32, @intCast(i)), uf.find(@intCast(i)));
}

test "a hole joins with anything, and stays a hole" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    var uf: UnionFind = .init(arena.allocator());
    const choice = try uf.add(0, null, .{ .kind = .choice });
    const parallel = try uf.add(0, null, .{ .kind = .parallel });
    const named = try uf.add(0, null, .{ .name = "#A" });
    const sealed = try uf.add(0, null, .{ .sealed = true });
    const hole = try uf.add(0, null, .{ .hole = true });

    // Through a hole, even conflicting classes join without complaint.
    try testing.expectEqual(no_conflict, try uf.unite(hole, choice));
    try testing.expectEqual(no_conflict, try uf.unite(hole, parallel));
    try testing.expectEqual(no_conflict, try uf.unite(named, hole));
    try testing.expectEqual(no_conflict, try uf.unite(sealed, hole));
    const c = uf.class(hole);
    try testing.expect(c.hole);
    try testing.expectEqual(Ir.Node.Kind.choice, c.kind.?); // the oldest value is kept
    try testing.expectEqualStrings("#A", c.name.?);
}

test "force merges a conflict, keeping the older value" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    var uf: UnionFind = .init(arena.allocator());
    const first = try uf.add(0, null, .{ .kind = .choice, .name = "#A" });
    const second = try uf.add(0, null, .{ .kind = .parallel, .name = "#B" });

    try uf.force(second, first);
    try testing.expectEqual(first, uf.find(second));
    try testing.expectEqual(Ir.Node.Kind.choice, uf.class(second).kind.?);
    try testing.expectEqualStrings("#A", uf.class(second).name.?);
}

test "rollback undoes merges, edits and additions, even between old classes" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    var uf: UnionFind = .init(arena.allocator());
    const a = try uf.add(0, null, .{});
    const b = try uf.add(0, null, .{});

    const mark = uf.snapshot();
    // A new element glued to two old classes merges them through itself.
    const n = try uf.add(0, null, .{});
    try testing.expectEqual(no_conflict, try uf.unite(n, a));
    try testing.expectEqual(no_conflict, try uf.unite(n, b));
    (try uf.edit(a)).kind = .choice;
    try testing.expectEqual(a, uf.find(b));

    uf.rollback(mark);
    try testing.expectEqual(@as(usize, 2), uf.len());
    try testing.expectEqual(a, uf.find(a));
    try testing.expectEqual(b, uf.find(b));
    try testing.expectEqual(@as(?Ir.Node.Kind, null), uf.class(a).kind);
    try testing.expectEqual(@as(u32, 1), uf.class(a).size);

    // The structure works normally after a rollback.
    try testing.expectEqual(no_conflict, try uf.unite(b, a));
    try testing.expectEqual(a, uf.find(b));
}

test "nested snapshots roll back independently" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    var uf: UnionFind = .init(arena.allocator());
    const a = try uf.add(0, null, .{});

    const outer = uf.snapshot();
    const b = try uf.add(0, null, .{});
    _ = try uf.unite(a, b);
    const inner = uf.snapshot();
    const c = try uf.add(0, null, .{});
    _ = try uf.unite(b, c);

    uf.rollback(inner);
    try testing.expectEqual(@as(usize, 2), uf.len());
    try testing.expectEqual(a, uf.find(b)); // the outer merge survives
    uf.rollback(outer);
    try testing.expectEqual(@as(usize, 1), uf.len());
    try testing.expectEqual(@as(u32, 1), uf.class(a).size);
}
