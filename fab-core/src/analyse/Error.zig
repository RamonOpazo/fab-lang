//! An error the analyser found: what, where, and what to mark in the graph.
//! Re-exported as `Analyser.Error`.

const std = @import("std");
const builtin = @import("builtin");
const Cst = @import("../parse/Cst.zig");
const Subject = @import("Analyser.zig").Subject;

const Error = @This();
const TokenIndex = Cst.TokenIndex;

tag: Tag,
/// Where the error is reported.
token: TokenIndex,
/// Where the conflicting thing was first declared, when that helps.
related: ?TokenIndex = null,
/// What to mark in the graph, if anything.
subject: ?Subject = null,

pub const Tag = enum(u8) {
    // -- statements (rule 0) -------------------------------------------------

    /// `G :: f (g :label "x")`, `G :: f == g`.
    entry_in_declaration,
    /// `G :: &node f`.
    class_in_declaration,
    /// `G :: +(g1, [f], g2)`.
    value_in_declaration,
    /// `yes, paid :label "yes"`: the bare `yes`.
    bare_term_in_definition,
    /// `:x := a | b`.
    levels_in_definition,
    /// `[red] :: f`, `G :style :: f`.
    bad_declaration_head,
    /// `f g := [red]`, `G := [red]`.
    bad_definition_head,
    /// `f == g ~= h`.
    mixed_operators,
    /// `G :: f` … `G :: g`.
    zone_declared_twice,
    /// Warning. `f g` then `h k` on the next line, in braces.
    chain_broken_across_lines,

    // -- sorts (rule 1) ------------------------------------------------------

    /// `#A f`, `* f`, `@ (f)`, `? f`.
    node_beside_space,
    /// `f? (g, h)`, `k +f`, `f+ g`.
    pinched_edge_beside_space,
    /// `#A/#B`, `+g/+f`, `#A/?`, `f/#A/#B/g`.
    slash_between_nodes,
    /// `*/f/*`.
    both_ends_null,
    /// `*`, `f/*/g`, `*/f/g`; with rule 2, `*/(f, g)`, `*/+(f, g)`.
    null_not_on_one_end,
    /// `?(g, h)`, `!f`, `?/f`, `f/?/g`.
    kind_on_the_left,
    /// `f/g/?`.
    kind_closes_cycle,
    /// `?`, `(!)`.
    lone_kind,
    /// `f?`, `A.f/?`.
    kind_on_reference,
    /// `(a, b)/?`.
    kind_after_group,
    /// Warning. `(f)/?`.
    kind_after_group_of_one,

    // -- interfaces (rule 2) -------------------------------------------------

    /// `f (g, h)`, `(f, g) h`, `(a, b) (c, d)`.
    ends_dont_match,
    /// `f/g h`, `f/* g`, `(f/*) g`; at a slash, `(f/*)/g`.
    nothing_to_join,
    /// Warning. `(f/*, g) h`, `(f, #A) g`.
    space_reaches_one_branch,
    /// `(f, g)/(h, k)`.
    slash_between_groups,
    /// `f/g/`, `(f, g)/`, `(f g)/`, `#B/`.
    undirected_not_one_edge,

    // -- slash chains and names (rule 3) -------------------------------------

    /// `f g f`.
    edge_declared_twice,
    /// `(f g)/f`.
    self_reference_outside_loop,
    /// `f/+f`.
    redundant_self_attachment,
    /// `f/f+`.
    vacuous_self_attachment,
    /// `#A/f/#B/g/#C`, `+f/m/n/g+`.
    cycle_does_not_close,
    /// `+k/g` with k undeclared.
    reference_not_declared,
    /// `+f/g f`.
    forward_reference,

    // -- pinches (rule 4) ----------------------------------------------------

    /// `f g, h k, +(f, h)`.
    pinch_of_declared_edges,
    /// `+f+`, `+(f)+`.
    single_edge_pinched_twice,
    /// `+#A`, `#A?`, `(@)+`.
    pinch_of_a_node,
    /// `(f/*, g/*)+`.
    pinch_of_nothing,
    /// Warning. `+(f, #A)`, `(a, b/b)! k`.
    pinch_of_one_end,

    // -- where nodes meet (rule 5) -------------------------------------------

    /// `(a/?, b/!)+`, `validate/? #Valid/yes`.
    kinds_disagree,
    /// `a/#A #B/b`.
    two_names_for_one_node,
    /// `k f/*, j/f+`; `A :: f/*` then `B :: h/A.f+`.
    reference_to_null_node,

    // -- other diagrams (rule 6) ---------------------------------------------

    /// `B :: h/A.+f` with A not declared before B; `G :: G/f`.
    diagram_not_declared,
    /// `T.#UUDI7`, `A.+k` with no k in A.
    undeclared_name_in_diagram,
    /// `Db :: T/owns/User` where T has no `@`.
    diagram_without_own_node,
    /// `A.f g`, `A.(f, g)`, `f.#X`.
    cross_reference_not_a_node,

    // -- reserved: the spec has not decided (statements.md §15) --------------

    /// `#User :: @/(id, name)`, `review :: a b`.
    reserved_node_or_edge_declaration,

    // -- unsupported: the compiler has not caught up (statements.md §15) -----

    /// Levels above the first, until plan step 7.
    unsupported_levels,
    /// The contents of a definition, until plan steps 8–11.
    unsupported_definition,

    pub fn severity(tag: Tag) Severity {
        return switch (tag) {
            .chain_broken_across_lines, .kind_after_group_of_one, .space_reaches_one_branch, .pinch_of_one_end => .warning,
            .unsupported_levels, .unsupported_definition => .unsupported,
            else => .@"error",
        };
    }
};

/// An error's own severity, before the compiler promotes anything. Reserved
/// tags are plain errors; only their message says they are reserved.
pub const Severity = enum { warning, @"error", unsupported };

// Unsupported never ships (statements.md §15): a release build refuses to
// compile while any unsupported tag remains.
comptime {
    if (builtin.mode != .debug) for (std.enums.values(Tag)) |tag| {
        if (tag.severity() == .unsupported)
            @compileError("unsupported construct in a release build: " ++ @tagName(tag));
    };
}
