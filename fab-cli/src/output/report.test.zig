//! Tests for report.zig. Diagnostic texts come from fab-core and may change,
//! so only the layout around them is compared in full.

const std = @import("std");
const testing = std.testing;
const fab = @import("fab_core");
const report = @import("report.zig");

fn render(source: []const u8, verbosity: anytype, color: bool) ![]u8 {
    var c = try fab.Compilation.init(testing.allocator, source, .{ .warnings = .warn, .ir = .keep });
    defer c.deinit();
    var out: std.Io.Writer.Allocating = .init(testing.allocator);
    errdefer out.deinit();
    try report.write(&out.writer, c.source, try c.diagnostics(), .{ .verbosity = verbosity, .color = color, .path = "x.fab" });
    return out.toOwnedSlice();
}

test "brief: message, location, excerpt and mark" {
    const text = try render("G :: f g/+k h", .brief, false);
    defer testing.allocator.free(text);
    try testing.expectEqualStrings(
        \\error: Edge `k` is not declared before this point
        \\ --> x.fab:1:11
        \\  |
        \\1 | G :: f g/+k h
        \\  |           ^
        \\
        \\1 error
        \\
    , text);
}

test "full: the related location, the explanation and the hint" {
    const text = try render("G :: f g f", .full, false);
    defer testing.allocator.free(text);
    try testing.expect(std.mem.indexOf(u8, text,
        \\  = note: first declared here
        \\ --> x.fab:1:6
        \\  |
        \\1 | G :: f g f
        \\  |      -
        \\  = why:
    ) != null);
    try testing.expect(std.mem.indexOf(u8, text, "  = hint: ") != null);
}

test "marks line up after tabs and multi-byte characters" {
    const text = try render("G :: α\tβ/+k", .brief, false);
    defer testing.allocator.free(text);
    try testing.expect(std.mem.indexOf(u8, text, " --> x.fab:1:11\n") != null);
    // Six characters before the tab: `G :: α`.
    try testing.expect(std.mem.indexOf(u8, text, "  |       \t   ^\n") != null);
}

test "wide line numbers widen the gutter" {
    const text = try render("A :: a\nB :: b\nC :: c\nD :: d\nE :: e\nF :: f\nG :: g\nH :: h\nI :: i\nJ :: j/+k", .brief, false);
    defer testing.allocator.free(text);
    try testing.expect(std.mem.indexOf(u8, text, "  --> x.fab:10:9\n   |\n10 | J :: j/+k\n   |         ^\n") != null);
}

test "a mark at the end of a line" {
    const text = try render("G :format {\n  f\n}", .brief, false);
    defer testing.allocator.free(text);
    try testing.expect(std.mem.indexOf(u8, text, " --> x.fab:2:4\n  |\n2 |   f\n  |    ^\n") != null);
}

test "quiet and clean programs write nothing" {
    const quiet = try render("G :: f g f", .quiet, false);
    defer testing.allocator.free(quiet);
    try testing.expectEqualStrings("", quiet);
    const clean = try render("G :: f g", .full, false);
    defer testing.allocator.free(clean);
    try testing.expectEqualStrings("", clean);
}

test "colour is on unless turned off" {
    const colored = try render("G :: f g f", .brief, true);
    defer testing.allocator.free(colored);
    try testing.expect(std.mem.startsWith(u8, colored, "\x1b[31m\x1b[1merror"));
    const plain = try render("G :: f g f", .brief, false);
    defer testing.allocator.free(plain);
    try testing.expect(std.mem.indexOfScalar(u8, plain, 0x1b) == null);
}

test "locations count characters from 1" {
    const source = "a\nαβ c\n";
    try testing.expectEqual(@as(usize, 1), report.locate(source, 0).line);
    const c = report.locate(source, 7);
    try testing.expectEqual(@as(usize, 2), c.line);
    try testing.expectEqual(@as(usize, 4), c.column);
    const end = report.locate(source, source.len);
    try testing.expectEqual(@as(usize, 3), end.line);
    try testing.expectEqual(@as(usize, 1), end.column);
}
