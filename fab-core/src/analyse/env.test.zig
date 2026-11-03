//! Tests for Env.zig: interned types, and what fits where.

const std = @import("std");
const testing = std.testing;
const Env = @import("Env.zig");

const gpa = testing.allocator;

test "structural types are interned: one index per type" {
    var env: Env = try .init(gpa);
    defer env.deinit(gpa);
    const a = try env.intern(gpa, .{ .list = .color });
    const b = try env.intern(gpa, .{ .list = .color });
    try testing.expectEqual(a, b);
    try testing.expect(a != try env.intern(gpa, .{ .list = .number }));

    var parts = [_]Env.TypeIndex{ .color, .number };
    const t1 = try env.intern(gpa, .{ .tuple = &parts });
    parts[0] = .text; // the table keeps its own copy
    try testing.expectEqual(t1, try env.intern(gpa, .{ .tuple = &.{ .color, .number } }));
}

test "the scalars have fixed indices" {
    var env: Env = try .init(gpa);
    defer env.deinit(gpa);
    try testing.expectEqual(Env.TypeIndex.color, try env.intern(gpa, .color));
    try testing.expectEqualStrings(":Color", env.type_names.items[@backingInt(Env.TypeIndex.color)].?);
}

test "each label type has its own identity" {
    var env: Env = try .init(gpa);
    defer env.deinit(gpa);
    const shape = try env.newLabels(gpa);
    const line = try env.newLabels(gpa);
    try testing.expect(shape != line);
    try testing.expect(!env.fits(shape, line));
}

test "fits: the same type, and unions" {
    var env: Env = try .init(gpa);
    defer env.deinit(gpa);
    const facing = try env.newLabels(gpa);
    const on = try env.newLabels(gpa);
    const side = try env.intern(gpa, .{ .@"union" = &.{ facing, on } });
    try testing.expect(env.fits(.color, .color));
    try testing.expect(env.fits(facing, side));
    try testing.expect(env.fits(on, side));
    try testing.expect(!env.fits(.color, side));
    try testing.expect(!env.fits(side, facing));
}

test "fits: lists take tuples of their elements, one value, and []" {
    var env: Env = try .init(gpa);
    defer env.deinit(gpa);
    const sizes = try env.intern(gpa, .{ .list = .number });
    try testing.expect(env.fits(try env.intern(gpa, .{ .tuple = &.{ .number, .number, .number } }), sizes));
    try testing.expect(env.fits(.number, sizes));
    try testing.expect(env.fits(try env.intern(gpa, .{ .list = .nothing }), sizes));
    try testing.expect(env.fits(try env.intern(gpa, .{ .tuple = &.{ .nothing, .number } }), sizes));
    try testing.expect(!env.fits(try env.intern(gpa, .{ .tuple = &.{ .number, .color } }), sizes));
    try testing.expect(!env.fits(.color, sizes));
}

test "fits: tuples match element by element, empty slots anywhere" {
    var env: Env = try .init(gpa);
    defer env.deinit(gpa);
    const head = try env.newLabels(gpa);
    const line = try env.newLabels(gpa);
    const arrow = try env.intern(gpa, .{ .tuple = &.{ head, line, head } });
    try testing.expect(env.fits(try env.intern(gpa, .{ .tuple = &.{ head, line, head } }), arrow));
    try testing.expect(env.fits(try env.intern(gpa, .{ .tuple = &.{ .nothing, line, head } }), arrow));
    try testing.expect(!env.fits(try env.intern(gpa, .{ .tuple = &.{ head, head, head } }), arrow));
    try testing.expect(!env.fits(try env.intern(gpa, .{ .tuple = &.{ line, head } }), arrow));
    try testing.expect(!env.fits(line, arrow));
}

test "fits: what failed to type fits anywhere, so it says nothing more" {
    var env: Env = try .init(gpa);
    defer env.deinit(gpa);
    try testing.expect(env.fits(.unknown, .color));
    try testing.expect(env.fits(.color, .unknown));
}

test "labels go on single values only" {
    var env: Env = try .init(gpa);
    defer env.deinit(gpa);
    try testing.expect(env.takesLabels(.color));
    try testing.expect(env.takesLabels(try env.newLabels(gpa)));
    try testing.expect(!env.takesLabels(.record));
    try testing.expect(!env.takesLabels(.flag));
    try testing.expect(!env.takesLabels(try env.intern(gpa, .{ .list = .color })));
}

test "classes by name" {
    try testing.expectEqual(Env.Class.node, Env.class("&node").?);
    try testing.expectEqual(@as(?Env.Class, null), Env.class("&nodes"));
}
