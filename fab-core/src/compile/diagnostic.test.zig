//! Tests for Diagnostic.zig and messages.zig.

const std = @import("std");
const testing = std.testing;
const Cst = @import("../parse/Cst.zig");
const Parser = @import("../parse/Parser.zig");
const Analyser = @import("../analyse/Analyser.zig");
const Diagnostic = @import("Diagnostic.zig");
const messages = @import("messages.zig");

/// Diagnostics for `source`: the parser's if there are any, else the analyser's.
fn diagnose(source: [:0]const u8) ![]Diagnostic {
    const gpa = testing.allocator;
    var cst = try Parser.parse(gpa, source);
    defer cst.deinit(gpa);

    var list: std.ArrayList(Diagnostic) = .empty;
    errdefer list.deinit(gpa);
    if (cst.errors.len > 0) {
        for (cst.errors) |e| try list.append(gpa, .fromSyntax(&cst, e));
        return list.toOwnedSlice(gpa);
    }
    var result = try Analyser.analyse(gpa, &cst);
    defer result.deinit(gpa);
    for (result.errors) |e| try list.append(gpa, .fromAnalysis(&cst, e));
    return list.toOwnedSlice(gpa);
}

fn expectLayer(d: Diagnostic, layer: messages.Layer, source: []const u8, expected: []const u8) !void {
    var out: std.Io.Writer.Allocating = .init(testing.allocator);
    defer out.deinit();
    try d.write(layer, source, &out.writer);
    try testing.expectEqualStrings(expected, out.written());
}

test "an analysis error: spans, related span, message and hint" {
    const source = "G :: f g f";
    const ds = try diagnose(source);
    defer testing.allocator.free(ds);

    try testing.expectEqual(@as(usize, 1), ds.len);
    const d = ds[0];
    try testing.expectEqualStrings("edge_declared_twice", d.code.name());
    try testing.expectEqual(Diagnostic.Severity.@"error", d.severity);
    try testing.expectEqual(Diagnostic.Span{ .start = 9, .end = 10 }, d.span);
    try testing.expectEqual(Diagnostic.Span{ .start = 5, .end = 6 }, d.related.?);
    try expectLayer(d, .message, source, "Edge `f` is declared twice");
}

test "a syntax error: the operator is the subject" {
    const source = "G :: f /g";
    const ds = try diagnose(source);
    defer testing.allocator.free(ds);

    try testing.expectEqualStrings("slash_has_no_prefix_form", ds[0].code.name());
    try testing.expectEqualStrings("/", ds[0].span.text(source));
    try expectLayer(ds[0], .message, source, "`/` touches only what follows it");
}

test "expected tokens, and the ends of lines and input" {
    var source: [:0]const u8 = "G :: (f g";
    var ds = try diagnose(source);
    try expectLayer(ds[0], .message, source, "Expected `)`, found end of input");
    try expectLayer(ds[0], .hint, source, "Add `)` here, or check the construct that starts before this point.");
    testing.allocator.free(ds);

    source = "G f\nH :: g";
    ds = try diagnose(source);
    try expectLayer(ds[0], .message, source, "Expected `::`, found `f`");
    testing.allocator.free(ds);

    source = "G :format {\n  f\n}";
    ds = try diagnose(source);
    try expectLayer(ds[0], .message, source, "Expected attributes or an equation, found end of line");
    testing.allocator.free(ds);
}

test "braces that are not placeholders are written as they are" {
    const source = "f :: g";
    const ds = try diagnose(source);
    defer testing.allocator.free(ds);
    try expectLayer(ds[0], .explanation, source, "Every statement starts with a zone name: `G :: …` defines the zone, and `G :format { … }` adds a layer to it.");
}

test "every code has all three layers, and names are unique across stages" {
    var names: std.StringHashMapUnmanaged(void) = .empty;
    defer names.deinit(testing.allocator);

    inline for (.{ Cst.Error.Tag, Analyser.Error.Tag }, .{ "syntax", "analysis" }) |Tag, stage| {
        inline for (comptime std.enums.values(Tag)) |tag| {
            const code = @unionInit(Diagnostic.Code, stage, tag);
            const t = code.text();
            try testing.expect(t.message.len > 0);
            try testing.expect(t.explanation.len > 0);
            try testing.expect(t.hint.len > 0);
            // a message is one line
            try testing.expect(std.mem.indexOfScalar(u8, t.message, '\n') == null);
            const gop = try names.getOrPut(testing.allocator, code.name());
            try testing.expect(!gop.found_existing);
        }
    }
}

test "severities are ordered, and promoted warnings count as errors" {
    const S = Diagnostic.Severity;
    try testing.expectEqual(S.promoted, S.warning.max(.promoted));
    try testing.expectEqual(S.@"error", S.@"error".max(.warning));
    try testing.expect(!S.warning.isError());
    try testing.expect(S.promoted.isError());
    try testing.expect(S.@"error".isError());
}
