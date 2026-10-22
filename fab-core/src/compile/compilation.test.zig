//! Tests for Compilation.zig: stages on demand, tolerance, status, and the
//! link from IR issues to diagnostics.

const std = @import("std");
const testing = std.testing;
const Compilation = @import("Compilation.zig");
const Diagnostic = @import("Diagnostic.zig");

const strict: Compilation.Tolerance = .{ .warnings = .promote, .ir = .withhold };
const preview: Compilation.Tolerance = .{ .warnings = .warn, .ir = .keep };

fn message(c: *Compilation, d: Diagnostic) ![]u8 {
    var out: std.Io.Writer.Allocating = .init(testing.allocator);
    errdefer out.deinit();
    try d.write(.message, c.source, &out.writer);
    return out.toOwnedSlice();
}

test "a valid program: an IR under any tolerance, and status ok" {
    for ([_]Compilation.Tolerance{ strict, preview }) |tolerance| {
        var c = try Compilation.init(testing.allocator, "G :: f g", tolerance);
        defer c.deinit();
        try testing.expectEqual(Compilation.Status.ok, try c.status());
        try testing.expectEqual(@as(usize, 0), (try c.diagnostics()).len);
        const ir = (try c.ir()).?;
        try testing.expectEqual(@as(usize, 2), ir.edges.len);
        try testing.expectEqual(@as(usize, 0), ir.issues.len);
    }
}

test "a broken program: withheld, or kept with its issues" {
    const source = "G :: f g/+k h";

    var withheld = try Compilation.init(testing.allocator, source, strict);
    defer withheld.deinit();
    try testing.expectEqual(@as(?*const @import("../analyse/Ir.zig"), null), try withheld.ir());
    try testing.expectEqual(Compilation.Status.@"error", try withheld.status());

    var kept = try Compilation.init(testing.allocator, source, preview);
    defer kept.deinit();
    const ir = (try kept.ir()).?;
    try testing.expectEqual(@as(usize, 1), ir.issues.len);
    const d = try kept.diagnosticOf(ir.issues.get(0));
    const text = try message(&kept, d);
    defer testing.allocator.free(text);
    try testing.expectEqualStrings("Edge `k` is not declared before this point", text);
}

test "syntax diagnostics come first, and issues still find their own" {
    // A syntax error in H, then an analysis error in J.
    var c = try Compilation.init(testing.allocator, "G :: f\nH :: g /k\nJ :: m/+x", preview);
    defer c.deinit();

    const all = try c.diagnostics();
    try testing.expectEqual(@as(usize, 2), all.len);
    try testing.expectEqualStrings("slash_has_no_prefix_form", all[0].code.name());
    try testing.expectEqualStrings("undeclared_edge", all[1].code.name());

    const ir = (try c.ir()).?;
    try testing.expectEqual(@as(usize, 1), ir.issues.len);
    const d = try c.diagnosticOf(ir.issues.get(0));
    try testing.expectEqualStrings("undeclared_edge", d.code.name());
    try testing.expectEqualStrings("x", d.span.text(c.source));
}

test "stages run on demand, and only once" {
    var c = try Compilation.init(testing.allocator, "G :: f g", preview);
    defer c.deinit();

    // Lexing alone parses nothing.
    const toks = try c.tokens();
    try testing.expectEqual(@as(usize, 5), toks.len);
    try testing.expect(c.parsed == null);

    // Later stages reuse earlier ones.
    const first = try c.cst();
    _ = try c.ir();
    try testing.expectEqual(first, try c.cst());
    try testing.expectEqual(toks, try c.tokens());
}

test "the compilation keeps its own copy of the source" {
    var buffer = "G :: f g/+k h".*;
    var c = try Compilation.init(testing.allocator, &buffer, preview);
    defer c.deinit();
    @memset(&buffer, 'x');

    const d = (try c.diagnostics())[0];
    try testing.expectEqualStrings("k", d.span.text(c.source));
}

test "status is the join of severities" {
    const S = Compilation.Status;
    try testing.expectEqual(S.ok, S.ok.join(.ok));
    try testing.expectEqual(S.warning, S.ok.join(.warning));
    try testing.expectEqual(S.promoted, S.warning.join(.promoted));
    try testing.expectEqual(S.@"error", S.@"error".join(.promoted));
    try testing.expect(!S.warning.isError());
    try testing.expect(S.promoted.isError());
}

fn compileEverything(gpa: std.mem.Allocator, source: []const u8) !void {
    var c = try Compilation.init(gpa, source, preview);
    defer c.deinit();
    _ = try c.tokens();
    _ = try c.ir();
    _ = try c.status();
}

test "running out of memory at any allocation leaks nothing" {
    // A program with syntax errors, analysis errors, holes and repairs, so
    // that every stage and every recovery path allocates.
    const source =
        \\T :: #UUID7
        \\User :: @ (id T.#UUID7, name T.#String)
        \\G :: f? (g/+k, h) f, [f α g]
        \\H :: x /y
        \\G :format { f :label "x" }
    ;
    try testing.checkAllAllocationFailures(testing.allocator, compileEverything, .{source});
}
