//! Tests for value.zig and Decimal.zig: what a bracket holds.

const std = @import("std");
const testing = std.testing;
const value = @import("value.zig");
const Decimal = @import("Decimal.zig");
const Error = @import("Error.zig");

const Kind = std.meta.Tag(value.Kind);

/// Reads `token` and checks each element's kind, in order.
fn expectKinds(token: []const u8, expected: []const Kind) !void {
    var reader = value.read(token);
    for (expected) |kind| {
        const element = (try reader.next()).?;
        try testing.expectEqual(kind, std.meta.activeTag(element.kind));
    }
    try testing.expectEqual(@as(?value.Element, null), try reader.next());
}

fn only(token: []const u8) !value.Element {
    var reader = value.read(token);
    const element = (try reader.next()).?;
    try testing.expectEqual(@as(?value.Element, null), try reader.next());
    return element;
}

/// The first element fails with `tag`.
fn expectFailure(token: []const u8, tag: Error.Tag) !void {
    var reader = value.read(token);
    if (reader.next()) |_| {
        std.debug.print("{s} read, expected {s}\n", .{ token, @tagName(tag) });
        return error.TestExpectedError;
    } else |_| try testing.expectEqual(tag, reader.failure);
}

fn decimal(text: []const u8) !Decimal {
    return Decimal.parse(text);
}

fn expectFormat(text: []const u8, expected: []const u8) !void {
    var buf: [64]u8 = undefined;
    var w: std.Io.Writer = .fixed(&buf);
    try (try decimal(text)).format(&w);
    try testing.expectEqualStrings(expected, w.buffered());
}

// ---------------------------------------------------------------------------
// Shapes

test "one element per slash" {
    try expectKinds("[red]", &.{.name});
    try expectKinds("[>/solid/>>]", &.{ .symbol, .name, .symbol });
    try expectKinds("[0..*/1..1]", &.{ .range, .range });
    try expectKinds("[1/1.5/2]", &.{ .number, .number, .number });
}

test "one element more than slashes: [] is one nil, empty slots are nil" {
    try expectKinds("[]", &.{.empty});
    try expectKinds("[/solid/>]", &.{ .empty, .name, .symbol });
    try expectKinds("[/]", &.{ .empty, .empty });
    try expectKinds("[////1/2]", &.{ .empty, .empty, .empty, .empty, .number, .number });
}

test "names: lowercase-kebab" {
    for ([_][]const u8{ "[red]", "[warn-bg]", "[h2]", "[bold-italic]", "[double-circle]" }) |token|
        try testing.expectEqual(Kind.name, std.meta.activeTag((try only(token)).kind));
}

test "symbols: glyphs, at most one capital" {
    for ([_][]const u8{ "[>]", "[|>]", "[<@>]", "[X]", "[O{]", "[}O]", "[||]", "[?]", "[^]", "[*]", "[⊸]", "[→]", "[⌟]", "[●]" }) |token|
        try testing.expectEqual(Kind.symbol, std.meta.activeTag((try only(token)).kind));
}

test "colours, with or without alpha" {
    try testing.expectEqual(value.Rgba{ .r = 0xff, .g = 0, .b = 0 }, (try only("[#f00]")).kind.color);
    try testing.expectEqual(value.Rgba{ .r = 0xff, .g = 0, .b = 0, .a = 0xaa }, (try only("[#F00a]")).kind.color);
    try testing.expectEqual(value.Rgba{ .r = 0xd1, .g = 0x24, .b = 0x2f }, (try only("[#d1242f]")).kind.color);
    try testing.expectEqual(value.Rgba{ .r = 0xd1, .g = 0x24, .b = 0x2f, .a = 0x22 }, (try only("[#d1242f22]")).kind.color);
}

test "ranges: a number up to a number or *" {
    const open = (try only("[0..*]")).kind.range;
    try testing.expect(open.lo.eql(Decimal.zero) and open.hi == null);
    const closed = (try only("[0.5..1]")).kind.range;
    try testing.expect(closed.lo.eql(try decimal("0.5")) and closed.hi.?.eql(try decimal("1")));
    _ = try only("[1..1]");
}

test "! inverts the element it follows" {
    var reader = value.read("[?!/solid!/>]");
    const hook = (try reader.next()).?;
    try testing.expect(hook.inverted and std.mem.eql(u8, hook.text, "?"));
    const line = (try reader.next()).?;
    try testing.expect(line.inverted and std.mem.eql(u8, line.text, "solid"));
    try testing.expect(!(try reader.next()).?.inverted);

    const angle = try only("[30!]");
    try testing.expect(angle.inverted and angle.kind.number.eql(try decimal("30")));
}

test "a failed element doesn't stop the rest" {
    var reader = value.read("[Warn/red]");
    try testing.expectError(error.Malformed, reader.next());
    try testing.expectEqual(Error.Tag.uppercase_name, reader.failure);
    try testing.expectEqual(Kind.name, std.meta.activeTag((try reader.next()).?.kind));
}

// ---------------------------------------------------------------------------
// Errors

test "uppercase names" {
    try expectFailure("[Warn]", .uppercase_name);
    try expectFailure("[myColor]", .uppercase_name);
    try expectFailure("[Ok]", .uppercase_name);
}

test "malformed names" {
    try expectFailure("[warn_bg]", .malformed_name);
    try expectFailure("[warn-]", .malformed_name);
    try expectFailure("[warn--bg]", .malformed_name);
    try expectFailure("[café]", .malformed_name);
}

test "malformed colours" {
    try expectFailure("[#ggg]", .malformed_color);
    try expectFailure("[#12345]", .malformed_color);
    try expectFailure("[#]", .malformed_color);
}

test "negative and malformed numbers" {
    try expectFailure("[-30]", .negative_number);
    try expectFailure("[.5]", .malformed_number);
    try expectFailure("[1.]", .malformed_number);
    try expectFailure("[1.2.3]", .malformed_number);
    try expectFailure("[1x]", .malformed_number);
    try expectFailure("[1234567890123456789]", .malformed_number);
}

test "empty ranges" {
    try expectFailure("[5..2]", .empty_range);
    try expectFailure("[1..]", .empty_range);
    try expectFailure("[*..3]", .empty_range);
}

test "malformed symbols" {
    try expectFailure("[>a]", .malformed_symbol);
    try expectFailure("[OX]", .malformed_symbol);
    try expectFailure("[>2]", .malformed_symbol);
    try expectFailure("[>#]", .malformed_symbol);
    try expectFailure("[\u{00a0}]", .malformed_symbol); // a no-break space
    try expectFailure("[\u{200b}]", .malformed_symbol); // a zero-width space
    try expectFailure("[α]", .malformed_symbol); // a letter of another script
    try expectFailure("[\xff]", .malformed_symbol); // not UTF-8
}

test "misplaced !" {
    try expectFailure("[!]", .misplaced_bang);
    try expectFailure("[solid!!]", .misplaced_bang);
    try expectFailure("[so!lid]", .misplaced_bang);
    var reader = value.read("[/!/>]");
    _ = try reader.next();
    try testing.expectError(error.Malformed, reader.next());
    try testing.expectEqual(Error.Tag.misplaced_bang, reader.failure);
}

// ---------------------------------------------------------------------------
// Decimal

test "decimals are normal: equal numbers are equal structs" {
    try testing.expect((try decimal("1.50")).eql(try decimal("1.5")));
    try testing.expect((try decimal("007")).eql(try decimal("7")));
    try testing.expect((try decimal("0.0")).eql(Decimal.zero));
    try testing.expectEqual(Decimal{ .mantissa = 5, .scale = 2 }, try decimal("0.05"));
}

test "decimals print their normal form" {
    try expectFormat("1.50", "1.5");
    try expectFormat("007", "7");
    try expectFormat("0.05", "0.05");
    try expectFormat("12.034", "12.034");
    try expectFormat("0", "0");
}

test "decimals compare exactly" {
    try testing.expectEqual(std.math.Order.lt, (try decimal("0.1")).order(try decimal("0.25")));
    try testing.expectEqual(std.math.Order.eq, (try decimal("1.0")).order(try decimal("1")));
    try testing.expectEqual(std.math.Order.gt, (try decimal("10")).order(try decimal("9.999")));
    const big = try decimal("999999999999999999");
    const small = try decimal("0.000000000000000001");
    try testing.expectEqual(std.math.Order.gt, big.order(small));
}

test "decimals: at most 18 digits" {
    _ = try decimal("123456789012345678");
    try testing.expectError(error.TooManyDigits, decimal("1234567890123456789"));
    try testing.expectError(error.TooManyDigits, decimal("0.0000000000000000001"));
    try testing.expectError(error.Malformed, decimal("1."));
}

test "a decimal as a float, for renderers" {
    try testing.expectEqual(@as(f64, 0.25), (try decimal("0.25")).toFloat());
}
