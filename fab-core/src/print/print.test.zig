const std = @import("std");
const testing = std.testing;
const Parser = @import("../parse/Parser.zig");
const Cst = @import("../parse/Cst.zig");
const Compilation = @import("../compile/Compilation.zig");
const print = @import("print.zig");

/// `source` printed. The caller frees it.
fn printed(gpa: std.mem.Allocator, source: [:0]const u8) ![:0]u8 {
    var cst = try Parser.parse(gpa, source);
    defer cst.deinit(gpa);
    var out: std.Io.Writer.Allocating = .init(gpa);
    defer out.deinit();
    try print.program(&cst, &out.writer);
    return gpa.dupeSentinel(u8, out.written(), 0);
}

fn expectPrinted(source: [:0]const u8, want: []const u8) !void {
    const got = try printed(testing.allocator, source);
    defer testing.allocator.free(got);
    try testing.expectEqualStrings(want, got);
    try expectFaithful(source);
}

/// The tree and the comments of `source`, as one text: what printing keeps.
fn meaning(gpa: std.mem.Allocator, source: [:0]const u8) ![]u8 {
    var cst = try Parser.parse(gpa, source);
    defer cst.deinit(gpa);
    try testing.expectEqual(@as(usize, 0), cst.errors.len);
    var out: std.Io.Writer.Allocating = .init(gpa);
    defer out.deinit();
    try cst.dump(&out.writer);
    for (cst.comments) |c| try out.writer.print("{s}\n", .{source[c.start..c.end]});
    return out.toOwnedSlice();
}

/// Printing keeps the tree and the comments, and printing again changes
/// nothing.
fn expectFaithful(source: [:0]const u8) !void {
    const gpa = testing.allocator;
    const once = try printed(gpa, source);
    defer gpa.free(once);
    const twice = try printed(gpa, once);
    defer gpa.free(twice);
    try testing.expectEqualStrings(once, twice);
    const before = try meaning(gpa, source);
    defer gpa.free(before);
    const after = try meaning(gpa, once);
    defer gpa.free(after);
    try testing.expectEqualStrings(before, after);
}

test "touching is kept; apart is one space" {
    try expectPrinted("G   ::   f/g    h", "G :: f/g h\n");
    try expectPrinted("W :: +(f h,k)+  |  k/α/g", "W :: +(f h, k)+ | k/α/g\n");
    try expectPrinted("C :: f/? +(a , b)? k/+f", "C :: f/? +(a, b)? k/+f\n");
    try expectPrinted("G :: f/  g/", "G :: f/ g/\n");
    try expectPrinted("G.f   :arrow   [epi]", "G.f :arrow [epi]\n");
    try expectPrinted("D :: f (g, h)", "D :: f (g, h)\n");
}

test "space around structure: commas, groups, braces, operators" {
    try expectPrinted("G :: ( f, g )", "G :: (f, g)\n");
    try expectPrinted("G :style {#A :fill [red],f :label \"x\"}", "G :style { #A :fill [red], f :label \"x\" }\n");
    try expectPrinted(":Style [x] := {}", ":Style [x] := {}\n");
    try expectPrinted("W :prove { :axiom (k==f h) }", "W :prove { :axiom (k == f h) }\n");
    try expectPrinted(":Color [warn]:=[red]", ":Color [warn] := [red]\n");
}

test "line breaks are kept, blank lines at most one" {
    try expectPrinted("\n\nG :: f\n\n\n\nH :: g\n\n", "G :: f\n\nH :: g\n");
    try expectPrinted("G :: f\r\nH :: g", "G :: f\nH :: g\n");
}

test "indentation: four per brace or parenthesis, two fewer for a comma" {
    try expectPrinted(
        \\G :style {
        \\#A :fill [red],
        \\        f :label "x"
        \\}
    ,
        \\G :style {
        \\    #A :fill [red],
        \\    f :label "x"
        \\}
        \\
    );
    try expectPrinted(
        \\Order :: {
        \\ */receive validate/? +(
        \\ yes fork/! +(
        \\ charge
        \\ , reserve
        \\ )! ready
        \\ , no
        \\ )
        \\}
    ,
        \\Order :: {
        \\    */receive validate/? +(
        \\        yes fork/! +(
        \\            charge
        \\          , reserve
        \\        )! ready
        \\      , no
        \\    )
        \\}
        \\
    );
    // Nested braces, and a closer beginning a line.
    try expectPrinted("G :style {\n#A {\n:fill [red]\n}\n}", "G :style {\n    #A {\n        :fill [red]\n    }\n}\n");
}

test "comments stay where they were" {
    try expectPrinted("G :: f    // one\n   // two\nH :: g//three", "G :: f // one\n// two\nH :: g //three\n");
    try expectPrinted(
        \\G :style {
        \\      // the start
        \\  #A :fill [red] // red
        \\// the end
        \\}
    ,
        \\G :style {
        \\    // the start
        \\    #A :fill [red] // red
        \\    // the end
        \\}
        \\
    );
    try expectPrinted("// only", "// only\n");
    try expectPrinted("", "");
}

test "a program with syntax errors is not printed" {
    var cst = try Parser.parse(testing.allocator, "G :: f ,, g");
    defer cst.deinit(testing.allocator);
    var out: std.Io.Writer.Allocating = .init(testing.allocator);
    defer out.deinit();
    try testing.expectError(error.SyntaxError, print.program(&cst, &out.writer));
}

test "the examples and the prelude print faithfully" {
    try expectFaithful(Compilation.prelude_source);
    // examples/order-fulfilment.fab, already in its layout.
    const order =
        \\Order :: {
        \\    */receive/#Received validate/? +(
        \\        yes/#Accepted fork/! +(
        \\            charge/? +(paid, declined/#Waiting/retry)
        \\          , reserve/? +(reserved, short/#Backorder/restock)
        \\        )! ready/#Ready ship/#Shipped close/*
        \\      , no/#Rejected notify/*
        \\    )
        \\}
        \\
    ;
    try expectPrinted(order, order);
    // examples/git-history.fab and examples/document-schema.fab, in part.
    try expectFaithful(
        \\Repo :: {
        \\  */init readme/#Fork +(fix/#Main, login session/#Feature),
        \\  (#Main/merge, #Feature/merge')/#Merged bump/#V1 +(hotfix/#Head, spike/#Spike)
        \\}
        \\
        \\:ref := :shape [round], :fill [muted]
        \\
        \\Repo :style {
        \\  &node :shape [point],
        \\  #Head    { :ref, :label "main" },
        \\  merge'  :arrow [/dashed/>]
        \\}
        \\
        \\Repo :prove {
        \\  :kind [category],
        \\  :axiom (fix merge == login session merge'),   // both paths
        \\  :lemma.[clean] (#Merged :pushout)              // the merge is clean
        \\}
        \\Db :prove {
        \\  :axiom (User.(email, nick)! :uk, Tag.label :uk, (user, org)! :uk),
        \\  :axiom (parent { :nullable, :card [0..*/0..1] })
        \\}
    );
}
