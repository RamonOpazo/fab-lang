//! The place layer's conformance corpus (statements.md §26, §29): the place
//! the spec's programs resolve to, run through fab-core and the layer.
//!
//! Each case is a spec snippet, the diagnostics it reports (fab-core's and
//! the layer's, by code, in order) and the place it resolves to (as
//! `Place.dump`). fab-core's corpus holds what the language rejects; this
//! one what the values mean against the seed and the graph. Tests are named
//! after the spec section the case comes from, or `layout.md`'s.
//!
//! Each case names the plan step that makes it pass, numbered as fab-core's
//! corpus numbers the route (α is 20), and its increment. `done` is the last
//! one finished; later cases are skipped. Unsupported diagnostics are left
//! out: the spec never mentions them (statements.md §15).

const std = @import("std");
const testing = std.testing;
const fab = @import("fab_core");
const place = @import("root.zig");
const Compilation = fab.Compilation;
const Diagnostic = fab.Diagnostic;

/// The last plan step, and its increment, finished.
const done: Progress = .{ .step = alpha, .rule = 5 };
const alpha = 20;

const Progress = struct {
    step: u8,
    rule: u8 = 0,

    fn after(a: Progress, b: Progress) bool {
        return a.step > b.step or (a.step == b.step and a.rule > b.rule);
    }
};

const Case = struct {
    source: [:0]const u8,
    /// The diagnostics the case reports, in order. None: the case is accepted.
    codes: []const Diagnostic.Code = &.{},
    /// The Place's dump.
    place: []const u8,
    step: u8 = alpha,
    rule: u8,
};

/// Keeps the IR of a program with errors, so a rejected case is placed too.
const tolerance: Compilation.Tolerance = .{ .warnings = .warn, .ir = .keep };

fn check(case: Case) !void {
    if ((Progress{ .step = case.step, .rule = case.rule }).after(done)) return error.SkipZigTest;

    var c = try Compilation.init(testing.allocator, case.source, tolerance);
    defer c.deinit();
    var p = (try place.of(testing.allocator, &c)).?;
    defer p.deinit();

    var reported: std.ArrayList(Diagnostic) = .empty;
    defer reported.deinit(testing.allocator);
    for (try c.diagnostics()) |d| {
        if (d.severity != .unsupported) try reported.append(testing.allocator, d);
    }
    try reported.appendSlice(testing.allocator, p.diagnostics);
    const diags = reported.items;
    const same = diags.len == case.codes.len and for (diags, case.codes) |d, want| {
        if (!std.mem.eql(u8, d.code.name(), want.name())) break false;
    } else true;
    if (!same) {
        std.debug.print("source: {s}\nexpected:", .{case.source});
        for (case.codes) |want| std.debug.print(" {s}", .{want.name()});
        std.debug.print("\nreported:", .{});
        for (diags) |d| std.debug.print(" {s}", .{d.code.name()});
        std.debug.print("\n", .{});
        return error.TestUnexpectedResult;
    }

    var out: std.Io.Writer.Allocating = .init(testing.allocator);
    defer out.deinit();
    try p.dump(&out.writer);
    try testing.expectEqualStrings(case.place, out.written());
}

fn checkAll(cases: []const Case) !void {
    var skipped = false;
    for (cases) |case| check(case) catch |err| switch (err) {
        error.SkipZigTest => skipped = true,
        else => return err,
    };
    if (skipped) return error.SkipZigTest;
}

test "Place layer: the defaults, [4], [1] and [S]" {
    try checkAll(&.{
        .{ .rule = 4, .source = "G :: f g", .place =
        \\zone G grid [4] metric [1] flow 90° (0,1)
        \\
        },
    });
}

test "Place layer: the spec's examples" {
    try checkAll(&.{
        .{ .rule = 4, .source =
        \\Sq :: +(f h, g k)+
        \\Sq :place { :flow [area] }
        \\Ch :: f g h
        \\Ch :place { :flow [edge], :metric [2] }
        \\G  :: +(f g h, m n)+
        \\G.n :span [2]
        \\G  :place { &edge :collapse }
        , .place =
        \\zone Sq grid [4] metric [1] flow area 0 sides 0° 90° legs 0° 0°
        \\zone Ch grid [4] metric [2] flow 0° (1,0)
        \\zone G grid [4] metric [1] flow 90° (0,1)
        \\  edge f collapse
        \\  edge g collapse
        \\  edge h collapse
        \\  edge m collapse
        \\  edge n span 2 collapse
        \\
        },
    });
}

test "Place layer: numbers along the seed's edges, normals, and ! as a mirror" {
    try checkAll(&.{
        .{ .rule = 4, .source =
        \\A :: f
        \\A :place { :flow [1] }
        \\B :: f
        \\B :place { :flow [1/] }
        \\C :: f
        \\C :place { :flow [0!] }
        \\D :: f
        \\D :place { :flow [6] }
        \\H :: f
        \\H :place { :grid [4!], :flow [0] }
        \\J :: f
        \\J :place { :grid [4!], :flow [normal] }
        , .place =
        \\zone A grid [4] metric [1] flow 90° (0,1)
        \\zone B grid [4] metric [1] flow 180° (-1,0)
        \\zone C grid [4] metric [1] flow 180° (-1,0)
        \\zone D grid [4] metric [1] flow 180° (-1,0)
        \\zone H grid [4!] metric [1] flow 180° (-1,0)
        \\zone J grid [4!] metric [1] flow 90° (0,1)
        \\
        },
        // [3]: 0 east, 1 south-west, 2 north-west; the normal of 0 is south.
        .{ .rule = 4, .source =
        \\A :: f
        \\A :place { :grid [3], :flow [1] }
        \\B :: f
        \\B :place { :grid [3], :flow [normal] }
        \\C :: f
        \\C :place { :grid [3], :flow [1!] }
        \\D :: f
        \\D :place { :grid [3], :flow [2] }
        , .place =
        \\zone A grid [3] metric [1] flow 120° (0,1)
        \\zone B grid [3] metric [1] flow 90° (1,2)
        \\zone C grid [3] metric [1] flow 60° (1,1)
        \\zone D grid [3] metric [1] flow 240° (-1,-1)
        \\
        },
    });
}

test "Place layer: letters are the page's, the same on every seed, snapped" {
    try checkAll(&.{
        .{ .rule = 4, .source =
        \\A :: f
        \\A :place { :flow [E] }
        \\B :: f
        \\B :place { :flow [S/E] }
        \\C :: f
        \\C :place { :flow [E!] }
        \\D :: f
        \\D :place { :grid [3], :flow [S] }
        \\H :: f
        \\H :place { :grid [3], :flow [S/E] }
        \\J :: f
        \\J :place { :grid [3], :flow [N/E] }
        \\K :: f
        \\K :place { :grid [4!], :flow [E] }
        \\M :: f
        \\M :place { :grid [3!], :flow [N/E] }
        , .place =
        \\zone A grid [4] metric [1] flow 0° (1,0)
        \\zone B grid [4] metric [1] flow 45° (1,1)
        \\zone C grid [4] metric [1] flow 180° (-1,0)
        \\zone D grid [3] metric [1] flow 90° (1,2)
        \\zone H grid [3] metric [1] flow 30° (2,1)
        \\zone J grid [3] metric [1] flow 300° (0,-1)
        \\zone K grid [4!] metric [1] flow 0° (1,0)
        \\zone M grid [3!] metric [1] flow 330° (1,-1)
        \\
        },
    });
}

test "layout.md §4: an area, its sides, and where a lone child goes" {
    try checkAll(&.{
        .{ .rule = 4, .source =
        \\A :: f
        \\A :place { :flow [0//0/] }
        \\B :: f
        \\B :place { :flow [0/1] }
        \\C :: f
        \\C :place { :flow [0//0] }
        \\D :: f
        \\D :place { :flow [0/0/] }
        \\H :: f
        \\H :place { :flow [1/2] }
        \\J :: f
        \\J :place { :grid [3], :flow [area] }
        \\K :: f
        \\K :place { :grid [3], :flow [0/0/] }
        , .place =
        \\zone A grid [4] metric [1] flow area 0 sides 0° 90° legs 90° 90°
        \\zone B grid [4] metric [1] flow area 0 sides 0° 90° legs 0° 90°
        \\zone C grid [4] metric [1] flow area 0 sides 0° 90° legs 90° 0°
        \\zone D grid [4] metric [1] flow area 0 sides 0° 90° legs 0° 90°
        \\zone H grid [4] metric [1] flow area 1 sides 90° 180° legs 90° 180°
        \\zone J grid [3] metric [1] flow area 0 sides 0° 120° legs 0° 0°
        \\zone K grid [3] metric [1] flow area 0 sides 0° 120° legs 0° 90°
        \\
        },
    });
}

test "layout.md §3.4: the metric repeats, and turns back at !" {
    try checkAll(&.{
        .{ .rule = 4, .source =
        \\A :: f
        \\A :place { :metric [1/2/3!] }
        \\B :: f
        \\B :place { :metric [1.5] }
        , .place =
        \\zone A grid [4] metric [1/2/3!] flow 90° (0,1)
        \\zone B grid [4] metric [1.5] flow 90° (0,1)
        \\
        },
    });
}

test "Place layer: spans, and [k!] against the flow" {
    try checkAll(&.{
        .{ .rule = 4, .source =
        \\G :: f g h
        \\G.f :span [2]
        \\G.g :span [1!]
        \\G :place { h :span [3] }
        , .place =
        \\zone G grid [4] metric [1] flow 90° (0,1)
        \\  edge f span 2
        \\  edge g span 1!
        \\  edge h span 3
        \\
        },
    });
}

test "layout.md §6.5: collapse, flagged edges with the same two ends" {
    try checkAll(&.{
        // A pinch: f and g share both ends; h too, but unflagged.
        .{ .rule = 4, .source =
        \\G :: +(f, g, h)+
        \\G.(f, g) :collapse
        , .place =
        \\zone G grid [4] metric [1] flow 90° (0,1)
        \\  edge f collapse
        \\  edge g collapse
        \\  bundle f g
        \\
        },
        // Whatever their direction: f : A → B and g : B → A, as ⇄.
        .{ .rule = 4, .source =
        \\G :: #A/f/#B, #B/g/#A, #A/h/#C
        \\G :place { &edge :collapse }
        , .place =
        \\zone G grid [4] metric [1] flow 90° (0,1)
        \\  edge f collapse
        \\  edge g collapse
        \\  edge h collapse
        \\  bundle f g
        \\
        },
        // An edge's own flag over its diagram's class.
        .{ .rule = 4, .source =
        \\G :: +(f, g, h)+
        \\G :place { &edge :collapse, h :collapse! }
        , .place =
        \\zone G grid [4] metric [1] flow 90° (0,1)
        \\  edge f collapse
        \\  edge g collapse
        \\  bundle f g
        \\
        },
    });
}

test "Place layer: passed down, the kind's case, then the containers', then its own" {
    try checkAll(&.{
        // [category]'s case: :flow [area], to its members too.
        .{ .rule = 4, .source =
        \\A :: f
        \\G :: A/g
        \\G :kind [category]
        , .place =
        \\zone A in G grid [4] metric [1] flow area 0 sides 0° 90° legs 0° 0°
        \\zone G grid [4] metric [1] flow area 0 sides 0° 90° legs 0° 0°
        \\
        },
        // A container's classes over the kind; a member's own over both.
        .{ .rule = 4, .source =
        \\A :: f
        \\B :: f
        \\G :: A/g/B
        \\G :kind [category]
        \\G :place { &zone :flow [E], &edge :span [2] }
        \\B :place { :flow [N] }
        , .place =
        \\zone A in G grid [4] metric [1] flow 0° (1,0)
        \\  edge f span 2
        \\zone B in G grid [4] metric [1] flow 270° (0,-1)
        \\  edge f span 2
        \\zone G grid [4] metric [1] flow 0° (1,0)
        \\  edge g span 2
        \\
        },
        // A diagram's own binding stays its own.
        .{ .rule = 4, .source =
        \\A :: f
        \\G :: A/g
        \\G :place { :flow [E], :grid [3] }
        , .place =
        \\zone A in G grid [4] metric [1] flow 90° (0,1)
        \\zone G grid [3] metric [1] flow 0° (1,0)
        \\
        },
        // The flow is read against the seed the layers settle.
        .{ .rule = 4, .source =
        \\A :: f
        \\G :: A/g
        \\G :place { &zone :flow [1] }
        \\A :place { :grid [3] }
        , .place =
        \\zone A in G grid [3] metric [1] flow 120° (0,1)
        \\zone G grid [4] metric [1] flow 90° (0,1)
        \\
        },
    });
}

fn layer(comptime name: []const u8) Diagnostic.Code {
    return .{ .layer = &@field(place.messages, name) };
}

test "Places: what the layer rejects, and the layer below stands" {
    try checkAll(&.{
        .{ .rule = 5, .source =
        \\A :: f
        \\A :place { :grid [5], :flow [0/2], :metric [1/0] }
        , .codes = &.{ layer("seed_not_a_tiling"), layer("not_an_area"), layer("step_of_nothing") }, .place =
        \\zone A grid [4] metric [1] flow 90° (0,1)
        \\
        },
        .{ .rule = 5, .source =
        \\A :: f
        \\A :place { :flow [N/S] }
        \\B :: f
        \\B :place { :flow [S/S] }
        , .codes = &.{ layer("directions_cancel"), layer("directions_cancel") }, .place =
        \\zone A grid [4] metric [1] flow 90° (0,1)
        \\zone B grid [4] metric [1] flow 90° (0,1)
        \\
        },
        // A flow the seed can't read leaves the one below: here the
        // container's.
        .{ .rule = 5, .source =
        \\A :: f
        \\G :: A/g
        \\G :place { &zone :flow [E] }
        \\A :place { :flow [0/2/] }
        , .codes = &.{layer("not_an_area")}, .place =
        \\zone A in G grid [4] metric [1] flow 0° (1,0)
        \\zone G grid [4] metric [1] flow 0° (1,0)
        \\
        },
        // Not an area: three directions, a mirror on one only, a normal of
        // the next edge.
        .{ .rule = 5, .source =
        \\A :: f
        \\A :place { :flow [0/0/0] }
        \\B :: f
        \\B :place { :flow [0/1!] }
        \\C :: f
        \\C :place { :flow [0/1/] }
        , .codes = &.{ layer("not_an_area"), layer("not_an_area"), layer("not_an_area") }, .place =
        \\zone A grid [4] metric [1] flow 90° (0,1)
        \\zone B grid [4] metric [1] flow 90° (0,1)
        \\zone C grid [4] metric [1] flow 90° (0,1)
        \\
        },
        // Modulo the seed: [2/0] is edge 2's area on [3], not on [4]. A
        // class reaching both is reported once.
        .{ .rule = 5, .source =
        \\A :: f
        \\B :: f
        \\G :: A/g/B
        \\G :place { &zone :flow [2/0] }
        \\A :place { :grid [3] }
        , .codes = &.{layer("not_an_area")}, .place =
        \\zone A in G grid [3] metric [1] flow area 2 sides 240° 0° legs 240° 0°
        \\zone B in G grid [4] metric [1] flow 90° (0,1)
        \\zone G grid [4] metric [1] flow 90° (0,1)
        \\
        },
    });
}

test "Places: numbers that count are whole, and a flow names a direction" {
    try checkAll(&.{
        .{ .rule = 5, .source =
        \\A :: f
        \\A :place { :grid [3.5], :flow [0.5], :metric [0.5/1.5] }
        \\A.f :span [1.5]
        , .codes = &.{ layer("number_not_whole"), layer("number_not_whole"), layer("number_not_whole") }, .place =
        \\zone A grid [4] metric [0.5/1.5] flow 90° (0,1)
        \\
        },
        .{ .rule = 5, .source =
        \\A :: f
        \\A :place { :flow [] }
        \\B :: f
        \\B :place { :flow [//] }
        \\C :: f
        \\C :place { :flow [/0] }
        , .codes = &.{ layer("flow_of_no_direction"), layer("flow_of_no_direction"), layer("flow_of_no_direction") }, .place =
        \\zone A grid [4] metric [1] flow 90° (0,1)
        \\zone B grid [4] metric [1] flow 90° (0,1)
        \\zone C grid [4] metric [1] flow 90° (0,1)
        \\
        },
    });
}

test "Places: a span of nothing, and spans that disagree" {
    try checkAll(&.{
        .{ .rule = 5, .source =
        \\C :: f
        \\C.f :span [0]
        , .codes = &.{layer("span_of_nothing")}, .place =
        \\zone C grid [4] metric [1] flow 90° (0,1)
        \\
        },
        // The spec's: f g h climb three ranks, m n two.
        .{ .rule = 5, .source =
        \\G :: +(f g h, m n)+
        \\G.m :span [1]
        \\G.n :span [1]
        , .codes = &.{layer("spans_disagree")}, .place =
        \\zone G grid [4] metric [1] flow 90° (0,1)
        \\  edge m span 1
        \\  edge n span 1
        \\
        },
        // One span stretches its edge, so the branches agree.
        .{ .rule = 5, .source =
        \\G :: +(f g h, m n)+
        \\G.m :span [2]
        , .place =
        \\zone G grid [4] metric [1] flow 90° (0,1)
        \\  edge m span 2
        \\
        },
        // A class's span, every edge's: two paths of different lengths.
        .{ .rule = 5, .source =
        \\G :: +(f g, h)+
        \\G :place { &edge :span [1] }
        , .codes = &.{layer("spans_disagree")}, .place =
        \\zone G grid [4] metric [1] flow 90° (0,1)
        \\  edge f span 1
        \\  edge g span 1
        \\  edge h span 1
        \\
        },
        // A cycle no span states is broken at a back edge; against the
        // flow, a span states one.
        .{ .rule = 5, .source =
        \\G :: #A/f/#B, #B/g/#A
        \\H :: #A/f/#B, #B/g/#A
        \\H.f :span [2]
        \\H.g :span [2!]
        , .place =
        \\zone G grid [4] metric [1] flow 90° (0,1)
        \\zone H grid [4] metric [1] flow 90° (0,1)
        \\  edge f span 2
        \\  edge g span 2!
        \\
        },
        .{ .rule = 5, .source =
        \\H :: #A/f/#B, #B/g/#A
        \\H.f :span [2]
        \\H.g :span [1!]
        , .codes = &.{layer("spans_disagree")}, .place =
        \\zone H grid [4] metric [1] flow 90° (0,1)
        \\  edge f span 2
        \\  edge g span 1!
        \\
        },
    });
}

test "Places: collapse between different ends, and of a cell's side" {
    try checkAll(&.{
        .{ .rule = 5, .source =
        \\G :: #A/f/#B, #A/g/#C
        \\G.(f, g) :collapse
        , .codes = &.{layer("collapse_different_ends")}, .place =
        \\zone G grid [4] metric [1] flow 90° (0,1)
        \\  edge f collapse
        \\  edge g collapse
        \\
        },
        // A class collapses what it can, and says nothing of the rest.
        .{ .rule = 5, .source =
        \\G :: #A/f/#B, #A/g/#C
        \\G :place { &edge :collapse }
        , .place =
        \\zone G grid [4] metric [1] flow 90° (0,1)
        \\  edge f collapse
        \\  edge g collapse
        \\
        },
        .{ .rule = 5, .source =
        \\G :: +(f, g)+ | f/α/g
        \\G.(f, g) :collapse
        , .codes = &.{layer("collapse_cell_side")}, .place =
        \\zone G grid [4] metric [1] flow 90° (0,1)
        \\  edge f collapse
        \\  edge g collapse
        \\
        },
        .{ .rule = 5, .source =
        \\G :: +(f, g, h)+ | f/α/g
        \\G :place { &edge :collapse }
        , .place =
        \\zone G grid [4] metric [1] flow 90° (0,1)
        \\  edge f collapse
        \\  edge g collapse
        \\  edge h collapse
        \\
        },
    });
}

test "Places: the layer's diagnostics point at the value, with their texts" {
    var c = try Compilation.init(testing.allocator, "G :: +(f g h, m n)+\nG.m :span [1]\nG.n :span [1]\nG :place { :grid [5] }", tolerance);
    defer c.deinit();
    var p = (try place.of(testing.allocator, &c)).?;
    defer p.deinit();
    try testing.expectEqual(@as(usize, 2), p.diagnostics.len);
    const expected = [_][2][]const u8{
        .{ "The span `[1]` disagrees with the diagram's other spans", "[1]" },
        .{ "`[5]` is not a seed", "[5]" },
    };
    for (p.diagnostics, expected) |d, want| {
        var out: std.Io.Writer.Allocating = .init(testing.allocator);
        defer out.deinit();
        try d.write(.message, c.source, &out.writer);
        try testing.expectEqualStrings(want[0], out.written());
        try testing.expectEqualStrings(want[1], d.span.text(c.source));
    }
    // n, related to m.
    const span = p.diagnostics[0];
    try testing.expectEqual(std.mem.indexOf(u8, c.source, "G.n").? + 10, span.span.start);
    try testing.expectEqual(std.mem.indexOf(u8, c.source, "G.m").? + 10, span.related.?.start);
}

fn placeEverything(gpa: std.mem.Allocator, source: []const u8) !void {
    var c = try Compilation.init(gpa, source, tolerance);
    defer c.deinit();
    var p = (try place.of(gpa, &c)).?;
    p.deinit();
}

test "running out of memory at any allocation leaks nothing" {
    // Every reader and every check: errors, passing down, bundles, spans.
    const source =
        \\A :: f
        \\G :: A/g, +(m n, h k)+, +(p, q)+ | p/α/q
        \\G :kind [category]
        \\G :place { &zone :flow [2/0], &edge :collapse, :grid [5], :metric [1/0] }
        \\A :place { :grid [3], :flow [N/S] }
        \\G.(m, n) :span [1]
        \\G.(p, q) :collapse
        \\
    ;
    var fixed: fab.testing.FixedInPlace = .{ .backing = testing.allocator };
    try testing.checkAllAllocationFailures(fixed.allocator(), placeEverything, .{source});
}
