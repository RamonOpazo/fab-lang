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
    try testing.expectEqualStrings("The edge `k` is not declared", text);
}

test "syntax diagnostics come first, and issues find their own in either list" {
    // A syntax error in H, then an analysis error in J.
    var c = try Compilation.init(testing.allocator, "G :: f\nH :: g /k\nJ :: m/+x", preview);
    defer c.deinit();

    const all = try c.diagnostics();
    try testing.expectEqual(@as(usize, 2), all.len);
    try testing.expectEqualStrings("slash_has_no_prefix_form", all[0].code.name());
    try testing.expectEqualStrings("reference_not_declared", all[1].code.name());

    // H is too broken to read: its syntax error marks its placeholder.
    const ir = (try c.ir()).?;
    try testing.expectEqual(@as(usize, 2), ir.issues.len);
    const h = try c.diagnosticOf(ir.issues.get(0));
    try testing.expectEqualStrings("slash_has_no_prefix_form", h.code.name());
    try testing.expect(ir.zones.items(.placeholder)[1]);
    const j = try c.diagnosticOf(ir.issues.get(1));
    try testing.expectEqualStrings("reference_not_declared", j.code.name());
    try testing.expectEqualStrings("x", j.span.text(c.source));
}

test "a diagram's mark: the border of its worst issue, and the unsupported label" {
    var c = try Compilation.init(testing.allocator,
        \\G :: f g/+k h
        \\H :: (f/*, g) h
        \\J :: f
        \\K :: f
        \\review :: a b
        \\J :style := f :label "x"
    , preview);
    defer c.deinit();
    const Mark = Compilation.ZoneMark;
    // An error on a hole in G, a warning on a node in H.
    try testing.expectEqual(Mark{ .border = .@"error" }, try c.zoneMark(@fromBackingInt(@intCast(0))));
    try testing.expectEqual(Mark{ .border = .warning }, try c.zoneMark(@fromBackingInt(@intCast(1))));
    // Its style is skipped: J is drawn with the unsupported label.
    try testing.expectEqual(Mark{ .border = .unsupported, .unsupported = true }, try c.zoneMark(@fromBackingInt(@intCast(2))));
    try testing.expectEqual(Mark{}, try c.zoneMark(@fromBackingInt(@intCast(3))));
    // The reserved head draws a placeholder, bordered by its error.
    const ir = (try c.ir()).?;
    try testing.expect(ir.zones.items(.placeholder)[4]);
    try testing.expectEqual(Mark{ .border = .@"error" }, try c.zoneMark(@fromBackingInt(@intCast(4))));
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
    var buffer = "G :: f /g".*;
    var c = try Compilation.init(testing.allocator, &buffer, preview);
    defer c.deinit();
    @memset(&buffer, 'x');

    const d = (try c.diagnostics())[0];
    try testing.expectEqualStrings("/", d.span.text(c.source));
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
    // A program with syntax errors, analysis errors, warnings, holes,
    // placeholders, other diagrams and unsupported parts, so that every stage
    // and every recovery path allocates.
    const source =
        \\T :: #UUID7/u, #String/s
        \\User :: id/T.#UUID7, name/T.#String, (f/*, g) h
        \\G :: f? (g/+k, h) f, (a, b)/?, a/#A #B/b
        \\H :: x /y
        \\review :: a b
        \\G :style := f :label "x" | g
        \\J :: +(f, g)+ | f/α/g, f/β/g | α/m/β, f/γ
        \\
    ;
    var fixed: FixedInPlace = .{ .backing = testing.allocator };
    try testing.checkAllAllocationFailures(fixed.allocator(), compileEverything, .{source});
}

/// An allocator that never resizes in place. The checker counts allocations
/// only, and whether the testing allocator can grow a list in place depends
/// on what earlier runs left free, so with in-place growth the count drifts
/// from run to run. Without it, every growth is a counted allocation.
const FixedInPlace = struct {
    backing: std.mem.Allocator,

    fn allocator(f: *FixedInPlace) std.mem.Allocator {
        return .{ .ptr = f, .vtable = &.{
            .alloc = alloc,
            .resize = std.mem.Allocator.noResize,
            .remap = std.mem.Allocator.noRemap,
            .free = free,
        } };
    }

    fn alloc(ctx: *anyopaque, len: usize, alignment: std.mem.Alignment, ra: usize) ?[*]u8 {
        const f: *FixedInPlace = @ptrCast(@alignCast(ctx));
        return f.backing.rawAlloc(len, alignment, ra);
    }

    fn free(ctx: *anyopaque, memory: []u8, alignment: std.mem.Alignment, ra: usize) void {
        const f: *FixedInPlace = @ptrCast(@alignCast(ctx));
        f.backing.rawFree(memory, alignment, ra);
    }
};
