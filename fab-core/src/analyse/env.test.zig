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

test "each declared type has its own identity" {
    var env: Env = try .init(gpa);
    defer env.deinit(gpa);
    const shape = try env.newDeclared(gpa);
    const line = try env.newDeclared(gpa);
    try testing.expect(shape != line);
    try testing.expect(!env.fits(shape, line));
}

test "fits: the same type, and unions" {
    var env: Env = try .init(gpa);
    defer env.deinit(gpa);
    const facing = try env.newDeclared(gpa);
    const on = try env.newDeclared(gpa);
    const side = try env.intern(gpa, .{ .@"union" = &.{ facing, on } });
    try testing.expect(env.fits(.color, .color));
    try testing.expect(env.fits(facing, side));
    try testing.expect(env.fits(on, side));
    try testing.expect(!env.fits(.color, side));
    try testing.expect(!env.fits(side, facing));
}

test "fits: lists take tuples of their elements, one value, and nil" {
    var env: Env = try .init(gpa);
    defer env.deinit(gpa);
    const sizes = try env.intern(gpa, .{ .list = .number });
    try testing.expect(env.fits(try env.intern(gpa, .{ .tuple = &.{ .number, .number, .number } }), sizes));
    try testing.expect(env.fits(.number, sizes));
    try testing.expect(env.fits(.nil, sizes));
    // A list's nil is no elements; nil among its elements is no number.
    try testing.expect(!env.fits(try env.intern(gpa, .{ .tuple = &.{ .nil, .number } }), sizes));
    try testing.expect(!env.fits(try env.intern(gpa, .{ .tuple = &.{ .number, .color } }), sizes));
    try testing.expect(!env.fits(.color, sizes));
}

test "fits: tuples match element by element, nil only where a slot admits it" {
    var env: Env = try .init(gpa);
    defer env.deinit(gpa);
    const head = try env.newDeclared(gpa);
    const line = try env.newDeclared(gpa);
    const arrow = try env.intern(gpa, .{ .tuple = &.{ head, line, head } });
    try testing.expect(env.fits(try env.intern(gpa, .{ .tuple = &.{ head, line, head } }), arrow));
    try testing.expect(!env.fits(try env.intern(gpa, .{ .tuple = &.{ .nil, line, head } }), arrow));
    const tip = try env.intern(gpa, .{ .@"union" = &.{ head, .nil } });
    const arrow_with_tips = try env.intern(gpa, .{ .tuple = &.{ tip, line, tip } });
    try testing.expect(env.fits(try env.intern(gpa, .{ .tuple = &.{ .nil, line, head } }), arrow_with_tips));
    try testing.expect(!env.fits(try env.intern(gpa, .{ .tuple = &.{ head, .nil, head } }), arrow_with_tips));
    try testing.expect(!env.fits(try env.intern(gpa, .{ .tuple = &.{ head, head, head } }), arrow));
    try testing.expect(!env.fits(try env.intern(gpa, .{ .tuple = &.{ line, head } }), arrow));
    try testing.expect(!env.fits(line, arrow));
}

test "fits: nil only where a type admits it" {
    var env: Env = try .init(gpa);
    defer env.deinit(gpa);
    try testing.expect(env.fits(.nil, .nil));
    try testing.expect(!env.fits(.nil, .color));
    try testing.expect(env.fits(.nil, try env.intern(gpa, .{ .@"union" = &.{ .color, .nil } })));
    try testing.expectEqual(@as(?Env.TypeIndex, null), try env.twin(gpa, .nil));
}

test "fits: what failed to type fits anywhere, so it says nothing more" {
    var env: Env = try .init(gpa);
    defer env.deinit(gpa);
    try testing.expect(env.fits(.unknown, .color));
    try testing.expect(env.fits(.color, .unknown));
}

test "a declared type holds its members' values, and is held by none but its own" {
    var env: Env = try .init(gpa);
    defer env.deinit(gpa);
    const length = try env.newDeclared(gpa);
    const width = try env.newDeclared(gpa);
    try env.declared.items[0].members.append(gpa, .number);
    try env.declared.items[1].members.append(gpa, length);
    // A literal fits through the members.
    try testing.expect(env.fits(.number, length));
    try testing.expect(env.fits(.number, width));
    // A length is a width, since a width includes lengths; not the reverse,
    // and a length is no number: declared types are never unwrapped.
    try testing.expect(env.fits(length, width));
    try testing.expect(!env.fits(width, length));
    try testing.expect(!env.fits(length, .number));
    try testing.expect(env.includes(width, length));
    try testing.expect(!env.includes(length, width));
}

test "twins: T fits T!, never the reverse; ! distributes and is idempotent" {
    var env: Env = try .init(gpa);
    defer env.deinit(gpa);
    const angle = (try env.twin(gpa, .number)).?;
    const inward = angle; // [30!] is typed :Number!
    try testing.expect(env.fits(.number, angle));
    try testing.expect(env.fits(inward, angle));
    try testing.expect(!env.fits(inward, .number));
    try testing.expectEqual(angle, (try env.twin(gpa, angle)).?);
    try testing.expectEqual(Env.TypeIndex.flag, (try env.twin(gpa, .flag)).?);
    try testing.expectEqual(@as(?Env.TypeIndex, null), try env.twin(gpa, .record));

    const hook = try env.newDeclared(gpa);
    const head = try env.newDeclared(gpa);
    const both = try env.intern(gpa, .{ .@"union" = &.{ head, hook } });
    const twins = (try env.twin(gpa, both)).?;
    try testing.expect(env.fits((try env.twin(gpa, hook)).?, twins));
    try testing.expect(env.fits(head, twins));

    // Untwinned: what a value would be without its `!`s.
    const pair = try env.intern(gpa, .{ .tuple = &.{ angle, .color } });
    try testing.expectEqual(try env.intern(gpa, .{ .tuple = &.{ .number, .color } }), try env.untwinned(gpa, pair));
}

test "labels go on single values only" {
    var env: Env = try .init(gpa);
    defer env.deinit(gpa);
    try testing.expect(env.takesLabels(.color));
    try testing.expect(env.takesLabels(try env.newDeclared(gpa)));
    try testing.expect(!env.takesLabels(.record));
    try testing.expect(!env.takesLabels(.flag));
    try testing.expect(!env.takesLabels(try env.intern(gpa, .{ .list = .color })));
}

test "classes by name" {
    try testing.expectEqual(Env.Class.node, Env.class("&node").?);
    try testing.expectEqual(@as(?Env.Class, null), Env.class("&nodes"));
}

test "types are written as fAB spells them" {
    const Parser = @import("../parse/Parser.zig");
    const Analyser = @import("Analyser.zig");
    var cst = try Parser.parse(testing.allocator,
        \\:Tip :: [a], [b]
        \\:Angle :: :Number!
        \\:Pair :: [:Tip/:Color]
        \\:Many :: [:Tip]
        \\:Either :: :Tip, :Color
        \\&node :angle :: :Angle
        \\&node :twin :: :Number!
        \\&node :pair :: [:Tip/:Color]
        \\&node :either :: :Tip, :Color
    );
    defer cst.deinit(testing.allocator);
    var result = try Analyser.analyse(testing.allocator, &cst, null);
    defer result.deinit(testing.allocator);
    const env = &result.env;
    for ([_][2][]const u8{
        .{ ":angle", ":Angle" },
        .{ ":twin", ":Number!" },
        .{ ":pair", "[:Tip/:Color]" },
        .{ ":either", ":Tip, :Color" },
    }) |case| {
        var out: std.Io.Writer.Allocating = .init(testing.allocator);
        defer out.deinit();
        try env.writeType(env.functions.get(case[0]).?.type, &out.writer);
        try testing.expectEqualStrings(case[1], out.written());
    }
}
