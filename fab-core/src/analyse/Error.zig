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
    entry_in_zone_declaration,
    /// `G :: &node f`.
    class_in_zone_declaration,
    /// `G :: +(g1, [f], g2)`.
    value_in_zone_declaration,
    /// `G :: f :Color`.
    type_in_zone_declaration,
    /// `yes, paid :label "yes"`: the bare `yes`; `[ink] [#ddd]`, a token
    /// named without `:=`.
    bare_term_in_record,
    /// `:x := a | b`, `G :style { a | b }`.
    levels_in_naming,
    /// `[red] :: f`, `G :style :: f`.
    bad_declaration_head,
    /// `f g := [red]`, `G := [red]`.
    bad_naming_head,
    /// `G :style := { … }`, `G.f :arrow := [epi]`.
    description_with_operator,
    /// `:fill [red]` at the top level, with nothing to describe.
    context_missing,
    /// `:Style [x] := { [ink] :: :Color }`: `::` in a record.
    declaration_in_record,
    /// Warning. `G :style { &node :fill [red], :caption "x" }`.
    owner_after_part,
    /// `f == g ~= h`.
    mixed_operators,
    /// `G :: f` … `G :: g`.
    zone_declared_twice,
    /// Warning. `f g` then `h k` on the next line, in braces.
    chain_broken_across_lines,

    // -- values: what a bracket holds (step 8b) ------------------------------

    /// `[Warn]`, `[myColor]`.
    uppercase_name,
    /// `[warn_bg]`, `[warn-]`, `[warn--bg]`.
    malformed_name,
    /// `[#ggg]`, `[#12345]`.
    malformed_color,
    /// `[-30]`.
    negative_number,
    /// `[1.]`, `[.5]`, `[1.2.3]`, nineteen digits.
    malformed_number,
    /// `[5..2]`, `[1..]`, `[*..3]`.
    empty_range,
    /// `[>a]`, `[OX]`, `[>2]`, a space-like character.
    malformed_symbol,
    /// `[!]`, `[solid!!]`, `[so!lid]`.
    misplaced_bang,

    // -- the environment (step 8c) -------------------------------------------

    /// `[w] := [wran]`, or a name defined further down.
    undefined_name,
    /// `[red] := …` twice; a type, a label or a signature again.
    name_defined_twice,
    /// `:Bow :: [outer]` when `[outer]` is a `:Facing`.
    label_in_two_types,
    /// `:Colour [x] := …`, `(&node) :fill :: [red]`.
    not_a_type,
    /// `:List`, `:Color.(:Text)`, `:List.(:A, :B)`.
    wrong_type_parameters,
    /// `:Color [w] := [circle]`.
    contract_broken,
    /// `:Shape :: [#f00]`, `[a/b]`, `[x!]`, `f`.
    not_a_label,
    /// `:Arrow :: [x]`.
    labels_on_structure,
    /// `(&nodes) :fill :: :Color`.
    unknown_class,

    // -- records (step 8e) ---------------------------------------------------

    /// `:colour [red]`, a bundle used before its definition.
    unknown_attribute,
    /// `&edge :fill [red]`, `{ :fill [red], :arrow [mono] }` in a bundle.
    does_not_apply,
    /// `&node :shape [red]`, `:theme [circle]`, `:t := [red]`.
    wrong_type,
    /// `&node :hide [on]`.
    value_given_to_flag,
    /// `&node :shape`.
    value_missing,
    /// `&node :fill!`, `:terminal!`.
    only_a_flag_inverts,
    /// `[ink] [circle]`.
    key_of_wrong_type,
    /// `:t := { &node :fill [red] }`, `:t := { [ink] := [#fff] }`.
    subject_in_bundle,
    /// `:Record [x] := { G.f :pen [thin] }`.
    element_in_theme,

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

    // -- levels (rule 1, one dimension up) ------------------------------------

    /// `f/α/*`, `f/α/?`, `f/α/A.#X`: above level 1, a side is a name of a
    /// lower level, and these are level 1 only.
    not_a_cell,
    /// `+(f, g)+ | f/α/#B`: a named node is a side above level 1, and only
    /// level 1 makes nodes.
    side_not_declared,
    /// `+(α, β)`, `+α/β/g` at level 2: sides are named, nothing to pinch.
    pinch_above_level_one,
    /// `(f h)/α/g` at level 2: two sides side by side.
    path_as_side,
    /// `G :: f, { g | α }`: braces inside a body hold no levels.
    level_inside_branch,

    // -- levels (elaboration, one dimension up) -------------------------------

    /// `f/α β/g`, `α`, `(α, β)/g` at level 2: an end on no named cell.
    unnamed_side,
    /// `f/α/g h/β/k` at level 2: g and h in one place.
    two_names_for_one_side,
    /// `+(f h, g k)+ | f/α/h`: f and h don't share their start and end.
    cells_not_parallel,

    // -- reserved: the spec has not decided (statements.md §15) --------------

    /// `#User :: @/(id, name)`, `review :: a b`.
    reserved_node_or_edge_declaration,

    // -- unsupported: the compiler has not caught up (statements.md §15) -----

    /// A layer, `G :style { … }`, until plan steps 9 and 11.
    unsupported_layer,

    pub fn severity(tag: Tag) Severity {
        return switch (tag) {
            .chain_broken_across_lines, .owner_after_part, .kind_after_group_of_one, .space_reaches_one_branch, .pinch_of_one_end => .warning,
            .unsupported_layer => .unsupported,
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
