//! The style layer's conformance corpus (statements.md §26): the style the
//! spec's programs resolve to, run through fab-core and the cascade.
//!
//! Each case is a spec snippet, the diagnostics it reports (by code, in
//! order) and the style it resolves to (as `Sheet.dump`: what the author
//! asked for). fab-core's corpus holds the diagnostics and the IR; this one
//! what they style. Tests are named after the spec section the case comes
//! from.
//!
//! Each case names the plan step (CLAUDE.md) that makes it pass, and its
//! part, as fab-core's corpus does: in step 9 its letter and sub-increment
//! (52 for 9e2), in step 11 its increment (4 for 11c2). `done` is the last
//! one finished; later cases are skipped. Unsupported diagnostics are left
//! out: the spec never mentions them (statements.md §15).

const std = @import("std");
const testing = std.testing;
const fab = @import("fab_core");
const style = @import("root.zig");
const Compilation = fab.Compilation;
const Diagnostic = fab.Diagnostic;

/// The last plan step, and its increment, finished.
const done: Progress = .{ .step = 11, .rule = 4 };

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
    /// The Sheet's dump.
    sheet: []const u8,
    /// The plan step that makes the case pass, and its part.
    step: u8,
    rule: u8 = 0,
};

/// Keeps the IR of a program with errors, so a rejected case is styled too.
const tolerance: Compilation.Tolerance = .{ .warnings = .warn, .ir = .keep };

fn check(case: Case) !void {
    if ((Progress{ .step = case.step, .rule = case.rule }).after(done)) return error.SkipZigTest;

    var c = try Compilation.init(testing.allocator, case.source, tolerance);
    defer c.deinit();

    var reported: std.ArrayList(Diagnostic) = .empty;
    defer reported.deinit(testing.allocator);
    for (try c.diagnostics()) |d| {
        if (d.severity != .unsupported) try reported.append(testing.allocator, d);
    }
    const diags = reported.items;
    const same = diags.len == case.codes.len and for (diags, case.codes) |d, want| {
        if (!std.meta.eql(d.code, want)) break false;
    } else true;
    if (!same) {
        std.debug.print("source: {s}\nexpected:", .{case.source});
        for (case.codes) |want| std.debug.print(" {s}", .{want.name()});
        std.debug.print("\nreported:", .{});
        for (diags) |d| std.debug.print(" {s}", .{d.code.name()});
        std.debug.print("\n", .{});
        return error.TestUnexpectedResult;
    }

    var sheet = (try style.of(testing.allocator, &c)).?;
    defer sheet.deinit();
    var out: std.Io.Writer.Allocating = .init(testing.allocator);
    defer out.deinit();
    try sheet.dump(&out.writer, .{});
    try testing.expectEqualStrings(case.sheet, out.written());
}

test "Program structure: a block is factored contexts" {
    try check(.{ .step = 9, .rule = 52, .source =
        \\G :: f/#Done
        \\:terminal := { :shape [circle], :fill [red] }
        \\G :style { #Done :terminal, f :label "x" }
    , .sheet =
        \\zone G
        \\  node n1: fill [#cf222e] program, shape [circle] program
        \\  edge f: label "x" program
        \\
    });
}

test "Program structure: a block, expanded" {
    try check(.{ .step = 9, .rule = 52, .source =
        \\G :: f/#Done
        \\:terminal := { :shape [circle], :fill [red] }
        \\G.#Done :terminal
        \\G.f :label "x"
    , .sheet =
        \\zone G
        \\  node n1: fill [#cf222e] program, shape [circle] program
        \\  edge f: label "x" program
        \\
    });
}

test "Style layer: the example" {
    try check(.{ .step = 9, .rule = 52, .source =
        \\G :: f g
        \\
        \\G :style {
        \\    f  { :arrow [epi], :stroke [#c0392b] },
        \\    +f {
        \\        :label $\mathbb{R}$,
        \\        :shape [circle]
        \\    },
        \\    f+ :label $\mathbb{N}$,
        \\    g+ :label $\sigma$
        \\}
    , .sheet =
        \\zone G
        \\  node n0: label $\mathbb{R}$ program, shape [circle] program
        \\  node n1: label $\mathbb{N}$ program
        \\  node n2: label $\sigma$ program
        \\  edge f: stroke [#c0392b] program, arrow [/solid/>>] program
        \\
    });
}

test "Specificity: a class, a narrower class, a class in a diagram, an element" {
    try check(.{ .step = 9, .rule = 52, .source =
        \\G :: */f/? +(g, h)
        \\&node   :fill [#111111]
        \\&choice :fill [#222222]
        \\&choice :line [dotted]
        \\G :style { &node { :stroke [#333333], :line [dashed] }, &choice :stroke [#444444], g+ :stroke [#555555] }
    , .sheet =
        \\zone G
        \\  node n0: fill [#111111] program, stroke [#333333] program, line [dashed] program
        \\  node n1: fill [#222222] program, stroke [#444444] program, line [dashed] program
        \\  node n2: fill [#111111] program, stroke [#555555] program, line [dashed] program
        \\  node n3: fill [#111111] program, stroke [#333333] program, line [dashed] program
        \\
    });
}

test "Themes: [base], then themes left to right, then the program" {
    try check(.{ .step = 9, .rule = 52, .source =
        \\:Style [one] := { &node :fill [#111111], &edge :stroke [#111111], &zone :fill [#111111] }
        \\:Style [two] := { &node :fill [#222222] }
        \\G :: f
        \\G :style { :theme [one/two], f :stroke [#333333] }
    , .sheet =
        \\zone G: fill [#111111] theme
        \\  node n0: fill [#222222] theme
        \\  node n1: fill [#222222] theme
        \\  edge f: stroke [#333333] program
        \\
    });
}

test "Themes: a theme includes others, applied before its own bindings" {
    try check(.{ .step = 9, .rule = 52, .source =
        \\:Style [night] := { :theme [dark], [accent] := [#58a6ff] }
        \\G :: f
        \\G :style { :theme [night] }
    , .sheet =
        \\zone G: fill [#1e1e1e] theme
        \\  token ink [#dddddd]
        \\  token soft [#aaaaaa]
        \\  token accent [#58a6ff]
        \\
    });
}

test "Themes: a later layer turns a flag off, and takes a value away with nil" {
    try check(.{ .step = 9, .rule = 52, .source =
        \\:Style [hidden] := { &edge :hide, &zone :fill [#111111] }
        \\G :: f
        \\G :style { :theme [hidden], :fill [], f :hide! }
    , .sheet =
        \\zone G: fill [] program
        \\  edge f: hide! program
        \\
    });
}

test "Themes: a diagram's own tokens, after its themes; any label rebound" {
    try check(.{ .step = 9, .rule = 52, .source =
        \\G :: f
        \\G :style { :theme [dark], [ink] := [#000000], [circle] := [box] }
    , .sheet =
        \\zone G: fill [#1e1e1e] theme
        \\  token ink [#000000]
        \\  token soft [#aaaaaa]
        \\  token circle [box]
        \\
    });
}

test "Text: a label resolves in three ways" {
    try check(.{ .step = 9, .rule = 52, .source =
        \\G :: f g h
        \\G :style { f :label [], g :label "Lorem", h :label "" }
    , .sheet =
        \\zone G
        \\  edge g: label "Lorem" program
        \\  edge h: label "" program
        \\
    });
}

test "Each diagram styles itself, and its members' classes" {
    try check(.{ .step = 9, .rule = 52, .source =
        \\Master  :: */a b
        \\Feature :: Master.(a+)/c
        \\Repo    :: Master, Feature
        \\&node :line [dashed]
        \\Feature :style { &node :shape [box] }
        \\Repo :style { :fill [#123456], &node { :shape [point], :line [dotted], :fill [#00ff00] }, [ink] := [#ff0000] }
    , .sheet =
        \\zone Master
        \\  token ink [#ff0000]
        \\  node n0: fill [#00ff00] program, line [dashed] program, shape [point] program
        \\  node n1: fill [#00ff00] program, line [dashed] program, shape [point] program
        \\  node n2: fill [#00ff00] program, line [dashed] program, shape [point] program
        \\zone Feature
        \\  token ink [#ff0000]
        \\  node n3: fill [#00ff00] program, line [dashed] program, shape [box] program
        \\zone Repo: fill [#123456] program
        \\  token ink [#ff0000]
        \\  node n4: fill [#00ff00] program, line [dotted] program, shape [point] program
        \\  node n5: fill [#00ff00] program, line [dotted] program, shape [point] program
        \\
    });
}

test "Examples: a flowchart, order fulfilment" {
    try check(.{ .step = 9, .rule = 52, .source =
        \\Order :: {
        \\    */receive/#Received validate/? +(
        \\        yes/#Accepted fork/! +(
        \\            charge/? +(paid, declined/#Waiting/retry)
        \\            , reserve/? +(reserved, short/#Backorder/restock)
        \\        )! ready/#Ready ship/#Shipped close/*
        \\        , no/#Rejected notify/*
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
    , .sheet =
        \\zone Order
        \\  node n1: label "Order received" program
        \\  node n2: label "Valid?" program
        \\  node n5: label "Payment accepted?" program
        \\  node n7: label "Wait 10 min" program
        \\  node n8: label "In stock?" program
        \\  node n11: label "Shipped" program
        \\  node n13: label "Rejected" program
        \\  edge yes: label "yes" program
        \\  edge paid: label "yes" program
        \\  edge declined: label "no" program
        \\  edge retry: arrow [/dashed/>] program, bend [inner] program
        \\  edge reserved: label "yes" program
        \\  edge short: label "no" program
        \\  edge restock: arrow [/dashed/>] program, bend [inner] program
        \\  edge no: label "no" program
        \\
    });
}

test "Examples: a database schema, documents and comments" {
    try check(.{ .step = 9, .rule = 52, .source =
        \\T :: #UUID7, #DTZ, #String, #Text, #JSONB, #Bool
        \\
        \\User         :: */(id/T.#UUID7, email/T.#String, nick/T.#String, name/T.#String, created_at/T.#DTZ)
        \\Organization :: */(id/T.#UUID7, name/T.#String)
        \\Membership   :: */(id/T.#UUID7, admin/T.#Bool)
        \\Project      :: */(id/T.#UUID7, name/T.#String)
        \\Document     :: */(id/T.#UUID7, title/T.#String, body/T.#JSONB)
        \\Comment      :: */(id/T.#UUID7, text/T.#Text)
        \\Tag          :: */(id/T.#UUID7, label/T.#String)
        \\Tagging      :: */id/T.#UUID7
        \\
        \\Db :: {
        \\    Membership/(user/User, org/Organization),
        \\    Project/owner/Organization,
        \\    Document/(project/Project, author/User),
        \\    Comment/(document/Document, writer/User, parent/Comment),
        \\    Tagging/(doc/Document, tag/Tag)
        \\}
        \\
        \\Db :kind [schema]
        \\
        \\Db :prove {
        \\    :axiom (&node.id :pk, &edge :card [0..*/1]),
        \\    :axiom (User.(email, nick)! :uk, Tag.label :uk, (user, org)! :uk, (doc, tag)! :uk),
        \\    :axiom (parent { :nullable, :card [0..*/0..1] }),
        \\    :axiom (parent document == document)  // a reply is on the same document as its parent
        \\}
        \\
        \\Db   :style { writer :label "author_id" }
        \\User :style { :label "users", :fill [muted] }
    , .sheet =
        \\zone T
        \\zone User: label "users" program, fill [#888888] program
        \\zone Organization
        \\zone Membership
        \\zone Project
        \\zone Document
        \\zone Comment
        \\zone Tag
        \\zone Tagging
        \\zone Db: stroke [#8250df] mark, caption "unsupported" mark
        \\  edge writer: label "author_id" program
        \\
    });
}

test "Examples: a git history, commits as arrows" {
    try check(.{ .step = 11, .rule = 4, .source =
        \\Repo :: {
        \\    */init readme/#Fork +(fix/#Main, login session/#Feature),
        \\    (#Main/merge, #Feature/merge')/#Merged bump/#V1 +(hotfix/#Head, spike/#Spike)
        \\}
        \\
        \\Repo :kind [git]
        \\
        \\:ref := :shape [round], :fill [muted]
        \\
        \\Repo :style {
        \\    #Head    { :ref, :label "main" },
        \\    #Feature { :ref, :label "feature/auth" },
        \\    #V1      { :ref, :label "v1.0" },
        \\    #Spike   { :ref, :label "spike/cache" },
        \\    init     :label "a1f3 init",
        \\    readme   :label "b27c add readme",
        \\    fix      :label "c90e fix typo",
        \\    login    :label "d4a1 login form",
        \\    session  :label "e5b2 sessions",
        \\    merge    :label "f6c3 merge feature/auth",
        \\    merge'   :arrow [/dashed/>],
        \\    bump     :label "0a7d bump to 1.0",
        \\    hotfix   :label "1b8e hotfix",
        \\    spike    :label "2c9f try cache"
        \\}
        \\
        \\Repo :prove {
        \\    :axiom (fix merge == login session merge'),  // both paths from the fork reach the same state
        \\    :lemma.[clean] (#Merged :pushout)            // fAB checks the merge is clean: the least common state
        \\}
    , .sheet =
        \\zone Repo: stroke [#8250df] mark, caption "unsupported" mark
        \\  node n0: shape [point] kind
        \\  node n1: shape [point] kind
        \\  node n2: shape [point] kind
        \\  node n3: shape [point] kind
        \\  node n4: shape [point] kind
        \\  node n5: label "feature/auth" program, fill [#888888] program, shape [round] program
        \\  node n6: shape [point] kind
        \\  node n7: label "v1.0" program, fill [#888888] program, shape [round] program
        \\  node n8: label "main" program, fill [#888888] program, shape [round] program
        \\  node n9: label "spike/cache" program, fill [#888888] program, shape [round] program
        \\  edge init: label "a1f3 init" program
        \\  edge readme: label "b27c add readme" program
        \\  edge fix: label "c90e fix typo" program
        \\  edge login: label "d4a1 login form" program
        \\  edge session: label "e5b2 sessions" program
        \\  edge merge: label "f6c3 merge feature/auth" program
        \\  edge merge': arrow [/dashed/>] program
        \\  edge bump: label "0a7d bump to 1.0" program
        \\  edge hotfix: label "1b8e hotfix" program
        \\  edge spike: label "2c9f try cache" program
        \\
    });
}

test "Examples: a git history, branch by branch" {
    try check(.{ .step = 11, .rule = 4, .source =
        \\Master     :: */init commit1 commit2 commit3 commit4 commit5
        \\FeatureOne :: Master.(commit2+)/commit1 commit2 commit3 commit4
        \\FeatureTwo :: Master.(commit2+)/commit1 commit2 merge/Master.(commit3+)
        \\
        \\Repo :: Master, FeatureOne, FeatureTwo
        \\
        \\Repo :kind [git]
    , .sheet =
        \\zone Master
        \\  node n0: shape [point] kind
        \\  node n1: shape [point] kind
        \\  node n2: shape [point] kind
        \\  node n3: shape [point] kind
        \\  node n4: shape [point] kind
        \\  node n5: shape [point] kind
        \\  node n6: shape [point] kind
        \\zone FeatureOne
        \\  node n7: shape [point] kind
        \\  node n8: shape [point] kind
        \\  node n9: shape [point] kind
        \\  node n10: shape [point] kind
        \\zone FeatureTwo
        \\  node n11: shape [point] kind
        \\  node n12: shape [point] kind
        \\zone Repo
        \\  node n13: shape [point] kind
        \\  node n14: shape [point] kind
        \\  node n15: shape [point] kind
        \\
    });
}

test "Kinds: the kind's theme, above [base], below themes and the program (statements.md §24.3)" {
    try check(.{ .step = 11, .rule = 4, .source = "G :: f\nG :kind [state-machine]", .sheet =
        \\zone G
        \\  node n0: shape [round] kind
        \\  node n1: shape [round] kind
        \\
    });
    try check(.{ .step = 11, .rule = 4, .source = ":Style [boxy] := { &node :shape [box] }\nG :: f\nG :kind [state-machine]\nG :style { :theme [boxy] }", .sheet =
        \\zone G
        \\  node n0: shape [box] theme
        \\  node n1: shape [box] theme
        \\
    });
    try check(.{ .step = 11, .rule = 4, .source = "G :: f\nG :kind [state-machine]\nG :style { &node :shape [box] }", .sheet =
        \\zone G
        \\  node n0: shape [box] program
        \\  node n1: shape [box] program
        \\
    });
    // A kind's theme binds tokens, before the themes'.
    try check(.{ .step = 11, .rule = 4, .source = "&zone :kind [schema] :> { :Style := { [ink] := [#000000], &edge :pen [thick] } }\nG :: f\nG :kind [schema]", .sheet =
        \\zone G
        \\  token ink [#000000]
        \\  edge f: pen [thick] kind
        \\
    });
}

test "Kinds: passed down, unless a member states its own (statements.md §24.2)" {
    try check(.{ .step = 11, .rule = 4, .source = "A :: f\nB :: g\nR :: A, B\nR :kind [git]\nB :kind [state-machine]", .sheet =
        \\zone A
        \\  node n0: shape [point] kind
        \\  node n1: shape [point] kind
        \\zone B
        \\  node n2: shape [round] kind
        \\  node n3: shape [round] kind
        \\zone R
        \\  node n4: shape [point] kind
        \\  node n5: shape [point] kind
        \\
    });
}
