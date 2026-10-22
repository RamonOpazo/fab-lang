//! Tests for json.zig.
//!
//! Diagnostic texts are not compared in full, so the wording in messages.zig
//! can change without touching these tests.

const std = @import("std");
const testing = std.testing;
const Compilation = @import("../compile/Compilation.zig");
const json = @import("json.zig");

const strict: Compilation.Tolerance = .{ .warnings = .promote, .ir = .withhold };
const preview: Compilation.Tolerance = .{ .warnings = .warn, .ir = .keep };

fn document(source: []const u8, tolerance: Compilation.Tolerance) ![]u8 {
    var c = try Compilation.init(testing.allocator, source, tolerance);
    defer c.deinit();
    var out: std.Io.Writer.Allocating = .init(testing.allocator);
    errdefer out.deinit();
    try json.writeCompilation(&c, &out.writer);
    return out.toOwnedSlice();
}

fn expectContains(haystack: []const u8, needle: []const u8) !void {
    if (std.mem.indexOf(u8, haystack, needle) == null) {
        std.debug.print("\nmissing: {s}\nin: {s}\n", .{ needle, haystack });
        return error.TestExpectedEqual;
    }
}

test "a valid program, in full" {
    const doc = try document("G :: f g", strict);
    defer testing.allocator.free(doc);
    try testing.expectEqualStrings(
        \\{"version":1,"status":"ok","diagnostics":[],"ir":{"zones":[{"name":"G","own":null}],"nodes":[{"kind":"plain","name":null,"zone":0,"canonical":{"edge":0,"side":"dom"}},{"kind":"plain","name":null,"zone":0,"canonical":{"edge":0,"side":"cod"}},{"kind":"plain","name":null,"zone":0,"canonical":{"edge":1,"side":"cod"}}],"edges":[{"name":"f","source":0,"target":1,"directed":true,"zone":0},{"name":"g","source":1,"target":2,"directed":true,"zone":0}],"cells":[],"issues":[]}}
    , doc);
}

test "a broken program: diagnostics, holes and issues" {
    const doc = try document("G :: f g/+k h", preview);
    defer testing.allocator.free(doc);
    try expectContains(doc,
        \\"status":"error","diagnostics":[{"code":"undeclared_edge","stage":"analysis","severity":"error","span":{"bytes":[10,11],"utf16":[10,11],"range":{"start":{"line":0,"character":10},"end":{"line":0,"character":11}}},"related":null,"message":"Edge `k` is not declared
    );
    try expectContains(doc,
        \\{"kind":"hole","name":null,"zone":0,"canonical":{"edge":0,"side":"cod"}}
    );
    try expectContains(doc,
        \\"issues":[{"subject":{"node":1},"diagnostic":0}]}}
    );
}

test "a withheld IR is null" {
    const doc = try document("G :: f g/+k h", strict);
    defer testing.allocator.free(doc);
    try expectContains(doc, "\"status\":\"error\"");
    try testing.expect(std.mem.endsWith(u8, doc, ",\"ir\":null}"));
}

test "issues point into the document's diagnostics, after the syntax ones" {
    const doc = try document("G :: f\nH :: g /k\nJ :: m/+x", preview);
    defer testing.allocator.free(doc);
    try expectContains(doc, "\"code\":\"slash_has_no_prefix_form\",\"stage\":\"syntax\"");
    try expectContains(doc, "\"issues\":[{\"subject\":{\"node\":");
    try expectContains(doc, "\"diagnostic\":1}]");
    // The second diagnostic is on line 2, at `x`.
    try expectContains(doc, "\"range\":{\"start\":{\"line\":2,\"character\":8}");
}

test "related spans are written" {
    const doc = try document("G :: f g f", preview);
    defer testing.allocator.free(doc);
    try expectContains(doc, "\"related\":{\"bytes\":[5,6],");
}

test "tokens" {
    var c = try Compilation.init(testing.allocator, "f/g", preview);
    defer c.deinit();
    var out: std.Io.Writer.Allocating = .init(testing.allocator);
    defer out.deinit();
    try json.writeTokens(&c, &out.writer);
    try testing.expectEqualStrings(
        \\{"version":1,"tokens":[{"tag":"edge_id","bytes":[0,1],"utf16":[0,1]},{"tag":"slash","bytes":[1,2],"utf16":[1,2]},{"tag":"edge_id","bytes":[2,3],"utf16":[2,3]},{"tag":"eof","bytes":[3,3],"utf16":[3,3]}]}
    , out.written());
}

test "positions: lines, and UTF-16 characters" {
    // bytes: a0 \n1 α2-3 b4 😀5-8 c9 \n10 e11
    const source = "a\nαb😀c\nend";
    var lines = try json.Lines.init(testing.allocator, source);
    defer lines.deinit(testing.allocator);

    const P = json.Lines.Position;
    try testing.expectEqual(P{ .line = 0, .character = 0 }, lines.position(0));
    try testing.expectEqual(P{ .line = 1, .character = 0 }, lines.position(2));
    try testing.expectEqual(P{ .line = 1, .character = 1 }, lines.position(4)); // after α: one unit
    try testing.expectEqual(P{ .line = 1, .character = 2 }, lines.position(5));
    try testing.expectEqual(P{ .line = 1, .character = 4 }, lines.position(9)); // after 😀: two units
    try testing.expectEqual(P{ .line = 2, .character = 0 }, lines.position(11));
    try testing.expectEqual(@as(u32, 6), lines.utf16(9));
    try testing.expectEqual(@as(u32, 8), lines.utf16(11));
    try testing.expectEqual(@as(u32, 11), lines.utf16(@intCast(source.len)));
}

test "strings are escaped, and invalid UTF-8 becomes U+FFFD" {
    var out: std.Io.Writer.Allocating = .init(testing.allocator);
    defer out.deinit();
    try json.string(&out.writer, "a\"b\\c\n\x01\tαé😀\xff\xce");
    try testing.expectEqualStrings("\"a\\\"b\\\\c\\n\\u0001\\tαé😀\\ufffd\\ufffd\"", out.written());
}

test "every document is valid JSON" {
    const sources = [_][]const u8{
        "G :: f g",
        "G :: f g/+k h",
        "Db :: Doc owner User",
        "G :: f\nH :: g /k\nJ :: m/+x",
        "Nat :: f, +f/g/f+, [f α g]",
        "T :: #UUID7\nUser :: @ (id T.#UUID7)\nDb :: User owner User",
        "G :: f\nG :format { f :label \"a \\\"quoted\\\" \xff label\" }",
        "G :: \"unterminated",
        "G :: α β/+γ 😀",
        "",
    };
    for (sources) |source| {
        for ([_]Compilation.Tolerance{ strict, preview }) |tolerance| {
            const doc = try document(source, tolerance);
            defer testing.allocator.free(doc);
            if (!try std.json.validate(testing.allocator, doc)) {
                std.debug.print("\ninvalid JSON for {s}:\n{s}\n", .{ source, doc });
                return error.TestUnexpectedResult;
            }
        }
    }
}
