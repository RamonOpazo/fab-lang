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
    try print.program(gpa, &cst, &out.writer);
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
        \\    f  :label "x"
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

test "columns: a run's operators, descriptors and blocks, one space after the widest" {
    try expectPrinted(
        \\Sq :: +(f h, g k)+
        \\Endo :: f/f
        \\Und :: f/
    ,
        \\Sq   :: +(f h, g k)+
        \\Endo :: f/f
        \\Und  :: f/
        \\
    );
    // A descriptor and a block share their column, and the `::` after a
    // descriptor has its own.
    try expectPrinted(
        \\Repo :style {
        \\    &node :shape [point],
        \\    #Feature { :ref },
        \\    init :label "a1f3 init"
        \\}
        \\:Style :: {
        \\    (&node, &zone) :fill :: (:Color, :Nil),
        \\    &node :padding :: :Length
        \\}
    ,
        \\Repo :style {
        \\    &node    :shape [point],
        \\    #Feature { :ref },
        \\    init     :label "a1f3 init"
        \\}
        \\:Style :: {
        \\    (&node, &zone) :fill    :: (:Color, :Nil),
        \\    &node          :padding :: :Length
        \\}
        \\
    );
    // Only at the line's own depth, after its first token, and before its
    // `::` or `:=`: what follows is the rest.
    try expectPrinted(
        \\:ref := :shape [round], :fill [muted]
        \\:quiet := :hide
        \\W :prove { :axiom (k == f h) }
        \\Wide :prove { :lemma.[a] (f :pullback) }
    ,
        \\:ref   := :shape [round], :fill [muted]
        \\:quiet := :hide
        \\W    :prove { :axiom (k == f h) }
        \\Wide :prove { :lemma.[a] (f :pullback) }
        \\
    );
    // A line of descriptors has no context: its next ones are no column,
    // nor anything after a comma, which begins another entry.
    try expectPrinted(
        \\&node {
        \\    :label [], :font [],
        \\    :shape [circle], :fill []
        \\}
        \\G :style { #A :fill [red], f :label "x" }
        \\Long :style { :label "y" }
    ,
        \\&node {
        \\    :label [], :font [],
        \\    :shape [circle], :fill []
        \\}
        \\G    :style { #A :fill [red], f :label "x" }
        \\Long :style { :label "y" }
        \\
    );
    // Widths count code points: α is one.
    try expectPrinted("Nat :: f/α/g // a\nIso :: f/g // b", "Nat :: f/α/g  // a\nIso :: f/g    // b\n");
}

test "a run ends at a blank line, a comment's line, or another indentation" {
    try expectPrinted("A :: f\nLong :: g\n\nB :: h", "A    :: f\nLong :: g\n\nB :: h\n");
    try expectPrinted("A :: f\n// note\nLong :: g", "A :: f\n// note\nLong :: g\n");
    try expectPrinted(
        \\G :style {
        \\    #A :fill [red]
        \\}
        \\Long :style { f :arrow [epi] }
    ,
        \\G :style {
        \\    #A :fill [red]
        \\}
        \\Long :style { f :arrow [epi] }
        \\
    );
}

test "comments: two spaces after the run's widest code, or a line of their own" {
    try expectPrinted("G :: f    // one\n   // two\nH :: g//three", "G :: f  // one\n// two\nH :: g  //three\n");
    try expectPrinted(
        \\Sq :: +(f h, g k)+ // a square
        \\Iso :: f/g // an isomorphism
        \\Pr :: #X/(g1, f, g2), f+/(p1/g1+, p2/g2+) // a product
    ,
        \\Sq  :: +(f h, g k)+                         // a square
        \\Iso :: f/g                                  // an isomorphism
        \\Pr  :: #X/(g1, f, g2), f+/(p1/g1+, p2/g2+)  // a product
        \\
    );
    // A line with no comment doesn't push the comments.
    try expectPrinted(
        \\Repo :prove {
        \\    :kind [category],
        \\    :axiom (fix merge == login session merge'), // both paths
        \\    :lemma.[clean] (#Merged :pushout) // the merge is clean
        \\}
    ,
        \\Repo :prove {
        \\    :kind [category],
        \\    :axiom (fix merge == login session merge'),  // both paths
        \\    :lemma.[clean] (#Merged :pushout)            // the merge is clean
        \\}
        \\
    );
    try expectPrinted(
        \\G :style {
        \\      // the start
        \\  #A :fill [red] // red
        \\// the end
        \\}
    ,
        \\G :style {
        \\    // the start
        \\    #A :fill [red]  // red
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
    try testing.expectError(error.SyntaxError, print.program(testing.allocator, &cst, &out.writer));
}

test "the prelude prints as it is written" {
    try expectPrinted(Compilation.prelude_source, Compilation.prelude_source);
}

test "the examples print as they are written" {
    // examples/order-fulfilment.fab.
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
        \\Order :style {
        \\    #Received             :label "Order received",
        \\    validate+             :label "Valid?",
        \\    charge+               :label "Payment accepted?",
        \\    #Waiting              :label "Wait 10 min",
        \\    reserve+              :label "In stock?",
        \\    #Shipped              :label "Shipped",
        \\    #Rejected             :label "Rejected",
        \\    (yes, paid, reserved) :label "yes",
        \\    (no, declined, short) :label "no",
        \\    (retry, restock)      { :arrow [/dashed/>], :bend [inner] }
        \\}
        \\
    ;
    try expectPrinted(order, order);
}
