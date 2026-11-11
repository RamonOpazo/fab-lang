//! Tests for json.zig.
//!
//! Diagnostic texts are not compared in full, so the wording in messages.zig
//! can change without touching these tests.

const std = @import("std");
const testing = std.testing;
const Compilation = @import("../compile/Compilation.zig");
const json = @import("json.zig");
const Lines = @import("../compile/Lines.zig");
const build = @import("../version.zig");

/// Every output starts so: the format, then the build.
const head = "{\"format\":1,\"version\":\"" ++ build.string ++ "\",";

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

/// The document up to its sheet: status, diagnostics and IR.
fn beforeSheet(doc: []const u8) []const u8 {
    return doc[0 .. std.mem.indexOf(u8, doc, ",\"sheet\":") orelse doc.len];
}

test "a valid program, its IR in full" {
    const doc = try document("G :: f g", strict);
    defer testing.allocator.free(doc);
    try testing.expectEqualStrings(head ++
        \\"status":"ok","diagnostics":[],"ir":{"zones":[{"name":"G","container":null,"members":[],"placeholder":false}],"nodes":[{"kind":"plain","name":null,"zone":0,"diagram":null,"canonical":{"edge":0,"side":"dom"}},{"kind":"plain","name":null,"zone":0,"diagram":null,"canonical":{"edge":0,"side":"cod"}},{"kind":"plain","name":null,"zone":0,"diagram":null,"canonical":{"edge":1,"side":"cod"}}],"edges":[{"name":"f","source":0,"target":1,"directed":true,"zone":0},{"name":"g","source":1,"target":2,"directed":true,"zone":0}],"cells":[],"issues":[]}
    , beforeSheet(doc));
}

test "cells name their sides by kind, with their direction" {
    const doc = try document("G :: #A/f/#A | f/α/#A, f/β/f/ | β/m/β", strict);
    defer testing.allocator.free(doc);
    try expectContains(doc,
        \\"cells":[{"name":"α","level":2,"source":{"edge":0},"target":{"node":0},"directed":true,"zone":0},{"name":"β","level":2,"source":{"edge":0},"target":{"edge":0},"directed":false,"zone":0},{"name":"m","level":3,"source":{"cell":1},"target":{"cell":1},"directed":true,"zone":0}]
    );
}

test "diagrams held: members in naming order, the first container, the diagram's node" {
    const doc = try document("A :: f\nB :: g\nR :: B, A/h", preview);
    defer testing.allocator.free(doc);
    try expectContains(doc,
        \\"zones":[{"name":"A","container":2,"members":[],"placeholder":false},{"name":"B","container":2,"members":[],"placeholder":false},{"name":"R","container":null,"members":[1,0],"placeholder":false}]
    );
    try expectContains(doc,
        \\{"kind":"plain","name":null,"zone":2,"diagram":1,"canonical":null}
    );
}

test "a broken program: diagnostics, holes and issues" {
    const doc = try document("G :: f g/+k h", preview);
    defer testing.allocator.free(doc);
    try expectContains(doc,
        \\"status":"error","diagnostics":[{"code":"reference_not_declared","stage":"analysis","severity":"error","span":{"bytes":[10,11],"utf16":[10,11],"range":{"start":{"line":0,"character":10},"end":{"line":0,"character":11}}},"related":null,"message":"The edge `k` is not declared
    );
    try expectContains(doc,
        \\{"kind":"hole","name":null,"zone":0,"diagram":null,"canonical":{"edge":1,"side":"cod"}}
    );
    try expectContains(doc,
        \\"issues":[{"subject":{"node":2},"diagnostic":0}]},"sheet":
    );
}

test "a withheld IR is null" {
    const doc = try document("G :: f g/+k h", strict);
    defer testing.allocator.free(doc);
    try expectContains(doc, "\"status\":\"error\"");
    try testing.expect(std.mem.endsWith(u8, doc, ",\"ir\":null,\"sheet\":null}"));
}

test "issues point into the document's diagnostics, after the syntax ones" {
    const doc = try document("G :: f\nH :: g /k\nJ :: m/+x", preview);
    defer testing.allocator.free(doc);
    try expectContains(doc, "\"code\":\"slash_has_no_prefix_form\",\"stage\":\"syntax\"");
    // H's placeholder is zone 1, marked by the syntax error; J's hole by the
    // analysis error after it.
    try expectContains(doc, "\"issues\":[{\"subject\":{\"zone\":1},\"diagnostic\":0},{\"subject\":{\"node\":");
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
    try testing.expectEqualStrings(head ++
        \\"tokens":[{"tag":"edge_id","bytes":[0,1],"utf16":[0,1]},{"tag":"slash","bytes":[1,2],"utf16":[1,2]},{"tag":"edge_id","bytes":[2,3],"utf16":[2,3]},{"tag":"eof","bytes":[3,3],"utf16":[3,3]}]}
    , out.written());
}

test "names are written without sigils" {
    const doc = try document("G :: #A/f\nG :style { #A :fill [#ff0000] }", strict);
    defer testing.allocator.free(doc);
    try expectContains(doc, "{\"kind\":\"plain\",\"name\":\"A\",");
    try expectContains(doc, "\"adds\":{\"class\":\"plain\"}");
    try expectContains(doc, "\"program\":{\"fill\":{\"color\":\"#ff0000ff\"}}");
}

test "the sheet: rules as a tree, an element's own entries, by layer, values by shape" {
    const doc = try document(
        \\G :: #A/f g
        \\G :style { :theme [dark], &edge :size [1.5], #A :fill [#ff000080], #A :hide, f :arrow [?!/dashed/>], f :label $x_1$ }
    , strict);
    defer testing.allocator.free(doc);
    // The edges' tree: [base]'s `&edge` (a root: no parent), `[dark]` over
    // it, then G's class binding (statements.md §25). A rule writes no
    // classes: its class steps are its classes.
    try expectContains(doc, "{\"adds\":{\"class\":\"edge\"},\"style\":{\"base\":{\"label\":null,");
    try expectContains(doc, "\"adds\":{\"theme\":\"dark\"},\"style\":{\"base\":{\"ink\":{\"color\":\"#aaaaaaff\"}");
    try expectContains(doc, "\"adds\":{\"zone\":0},\"style\":{\"program\":{\"size\":{\"number\":\"1.5\"}}}}");
    try expectContains(doc, "\"theme\":{\"fill\":{\"color\":\"#1e1e1eff\"}}");
    try testing.expect(std.mem.indexOf(u8, doc, "\"classes\"") == null);
    // Each element: its rule, and only its own entries, by layer; no mark
    // when it has none.
    try expectContains(doc, "{\"rule\":4,\"style\":{\"computed\":{\"label\":{\"text\":\"A\"}},\"program\":{\"fill\":{\"color\":\"#ff000080\"},\"hide\":true}}}");
    try expectContains(doc, "\"program\":{\"label\":{\"math\":\"x_1\"},\"arrow\":[{\"label\":\"?\",\"inverted\":true},{\"label\":\"dashed\"},{\"label\":\">\"}]}");
    try testing.expect(std.mem.indexOf(u8, doc, "\"mark\":null") == null);
    try testing.expect(std.mem.indexOf(u8, doc, "\"inverted\":false") == null);
    // Nil is null; :theme is no element's style.
    try expectContains(doc, "\"caption\":null");
    try testing.expect(std.mem.indexOf(u8, doc, "\"theme\":[") == null);
    // The tokens: [base]'s, and what G's theme changes, only.
    try expectContains(doc, "\"tokens\":{\"base\":{\"ink\":{\"color\":\"#333333ff\"}");
    try expectContains(doc, "\"zones\":[{\"ink\":{\"color\":\"#ddddddff\"},\"soft\":{\"color\":\"#aaaaaaff\"}}]");
}

test "an unstyled diagram's tokens are [base]'s, written once" {
    const doc = try document("G :: f", strict);
    defer testing.allocator.free(doc);
    try expectContains(doc, "\"zones\":[{}]");
}

test "marks are the last layer, and a marked element's mark is written" {
    const doc = try document("G :: f g/+k h", preview);
    defer testing.allocator.free(doc);
    try expectContains(doc, "\"mark\":{\"stroke\":{\"color\":\"#d1242fff\"}}},\"mark\":\"error\"}");
}

test "a sheet is indexed as its IR" {
    // Cells, members, a placeholder, a marked zone, themes.
    const programs = [_][]const u8{
        "G :: f g",
        "Nat :: +(f, g)+ | f/α/g\nNat :style { α :label \"a\" }",
        "A :: */f\nB :: */g\nDb :: A/h/B\nDb :prove { :strict }",
        "review :: a b\nG :: f/? +(g, h)\nG :style { :theme [dark], &choice :fill [accent] }",
    };
    for (programs, 0..) |source, name| {
        const doc = try document(source, preview);
        defer testing.allocator.free(doc);
        const parsed = try std.json.parseFromSlice(std.json.Value, testing.allocator, doc, .{});
        defer parsed.deinit();
        const root = parsed.value.object;
        const ir = root.get("ir").?.object;
        const sheet = root.get("sheet").?.object;
        const rules = sheet.get("rules").?.array.items.len;
        errdefer std.debug.print("\nin program {d}\n", .{name});
        inline for (.{ "nodes", "edges", "cells", "zones" }) |table| {
            const elements = sheet.get(table).?.array.items;
            try testing.expectEqual(ir.get(table).?.array.items.len, elements.len);
            for (elements) |e| try testing.expect(e.object.get("rule").?.integer < rules);
        }
        try testing.expectEqual(ir.get("zones").?.array.items.len, sheet.get("tokens").?.object.get("zones").?.array.items.len);
    }
}

test "positions: lines, and UTF-16 characters" {
    // bytes: a0 \n1 α2-3 b4 😀5-8 c9 \n10 e11
    const source = "a\nαb😀c\nend";
    var lines = try Lines.init(testing.allocator, source);
    defer lines.deinit(testing.allocator);

    const P = Lines.Position;
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
