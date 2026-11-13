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
const done: Progress = .{ .step = alpha, .rule = 4 };
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

test "Places: what the lattice can't read is passed over, until its checks" {
    // Step α5 reports each (spec, Errors, Places); until then the layer
    // below stands.
    try checkAll(&.{
        .{ .rule = 4, .source =
        \\A :: f
        \\A :place { :grid [5], :flow [0/2], :metric [1/0] }
        \\B :: f
        \\B :place { :flow [N/S] }
        \\C :: f
        \\C.f :span [0]
        , .place =
        \\zone A grid [4] metric [1] flow 90° (0,1)
        \\zone B grid [4] metric [1] flow 90° (0,1)
        \\zone C grid [4] metric [1] flow 90° (0,1)
        \\
        },
    });
}
