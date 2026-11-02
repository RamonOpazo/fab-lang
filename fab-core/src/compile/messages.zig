//! The text of every diagnostic, in three layers from short to long:
//!
//!   message      one line, saying what is wrong
//!   explanation  why it is wrong: the rule of the language behind it
//!   hint         how to fix it
//!
//! Front ends choose how many layers to show. Each `switch` is exhaustive, so
//! a code without text is a compile error.
//!
//! Placeholders, filled in by Diagnostic.write:
//!   {}          the text at the diagnostic's span, quoted as code
//!   {expected}  for expected_token, the token that was expected

const std = @import("std");
const Token = @import("../lex/Token.zig");
const Cst = @import("../parse/Cst.zig");
const Analyser = @import("../analyse/Analyser.zig");

pub const Layer = enum { message, explanation, hint };

pub const Text = struct {
    message: []const u8,
    explanation: []const u8,
    hint: []const u8,

    pub fn get(t: Text, layer: Layer) []const u8 {
        return switch (layer) {
            .message => t.message,
            .explanation => t.explanation,
            .hint => t.hint,
        };
    }
};

pub fn syntax(tag: Cst.Error.Tag) Text {
    return switch (tag) {
        .expected_token => .{
            .message = "Expected {expected}, found {}",
            .explanation = "The construct being read needs this token to be complete.",
            .hint = "Add {expected} here, or check the construct that starts before this point.",
        },
        .expected_statement => .{
            .message = "Expected a statement, found {}",
            .explanation = "Every statement is a head, then `::` or `:=`, then its body: `G :: f g` declares a diagram, `G :style := { … }` defines a value.",
            .hint = "Start the line with a name, or remove what is left over from the line before.",
        },
        .expected_atom => .{
            .message = "Expected an edge, a node or a group, found {}",
            .explanation = "Chains are built from edges (`f`), nodes (`#A`, `@`, `*`, diagram names), classes (`&node`), literals and groups `( … )`.",
            .hint = "Check for a missing name, or for an operator with nothing to apply to.",
        },
        .statement_spans_lines => .{
            .message = "The line ends inside parentheses",
            .explanation = "A statement is one line. Outside braces a newline ends it, even inside `( )`.",
            .hint = "Close the parentheses on this line, or wrap the statement in braces: `G :: { … }`.",
        },
        .missing_comma => .{
            .message = "Expected a comma before {}",
            .explanation = "Items are separated by commas: terms in a declaration, entries and equations in a definition.",
            .hint = "Add `,` before this item.",
        },
        .trailing_comma => .{
            .message = "A comma with no item after it",
            .explanation = "A comma stands between items only, never after the last one.",
            .hint = "Remove the comma.",
        },
        .empty_braces => .{
            .message = "Empty braces",
            .explanation = "There are no empty declarations or definitions, and braces always hold something.",
            .hint = "Write what the braces hold, or remove them.",
        },
        .empty_level => .{
            .message = "An empty level",
            .explanation = "Every level declares something: `|` stands between two levels.",
            .hint = "Remove the extra `|`, or write what the level declares.",
        },
        .bar_in_group => .{
            .message = "{} inside a group",
            .explanation = "`|` separates the levels of a body, at its top. A group holds items of one level.",
            .hint = "Move the levels out of the group: `G :: f g | f/α/g`.",
        },
        .atoms_touch => .{
            .message = "{} touches what comes before it",
            .explanation = "Only `/` joins things that touch. A space separates the steps of a chain.",
            .hint = "Write a space for a path, or `/` to attach: `f g`, `#A/f`, `*/f`.",
        },
        .marker_touches_both_sides => .{
            .message = "{} touches both sides",
            .explanation = "A marker attaches to the one side it touches: `f+` pinches the end of f, `+f` its start.",
            .hint = "Separate it from one side: `f ?(g, h)`, or `(a, b)! !(c, d)`.",
        },
        .slash_has_no_prefix_form => .{
            .message = "`/` touches only what follows it",
            .explanation = "`/` attaches to what it touches: `f/g` joins two things, and `f/` with nothing after it makes `f` undirected. There is no form where `/` touches only the right side.",
            .hint = "Write `f/g` without spaces, or `f/ g` for an undirected `f` followed by `g`.",
        },
        .operator_touches_nothing => .{
            .message = "{} touches nothing",
            .explanation = "The operators `/`, `+`, `?` and `!` attach to what they touch. With spaces on both sides, this one has nothing to attach to.",
            .hint = "Remove the space between the operator and its term, as in `+f` or `f?`.",
        },
        .detached_dot => .{
            .message = "A `.` must touch both sides",
            .explanation = "The dot joins a qualifier to what it qualifies, as in `A.+f` or `&node.id`, so nothing may separate them.",
            .hint = "Remove the spaces around the dot.",
        },
        .invalid_token => .{
            .message = "Unrecognised text {}",
            .explanation = "This is not a name, literal or operator of fAB. Unterminated strings and math, and numbers outside a value, end up here too.",
            .hint = "Check for a missing closing `\"`, `$` or `]`; write numbers in brackets: `[30]`.",
        },
    };
}

pub fn analysis(tag: Analyser.Error.Tag) Text {
    return switch (tag) {
        .entry_in_declaration => .{
            .message = "An entry or equation in a declaration",
            .explanation = "A declaration's items are terms: edges, nodes and groups of them. Attributes and equations are bound in definitions.",
            .hint = "Move it to a definition: `G :style := { … }` or `G :prove := { … }`.",
        },
        .class_in_declaration => .{
            .message = "The class {} in a declaration",
            .explanation = "Classes name sets of subjects for definitions. A declaration builds structure from edges and nodes only.",
            .hint = "Bind it in a definition: `&node :shape := [circle]`.",
        },
        .value_in_declaration => .{
            .message = "The value {} in a declaration",
            .explanation = "Strings, math and brackets are values, and values are bound in definitions. A declaration builds structure from edges and nodes only.",
            .hint = "Remove it, or bind it in a definition: `G :style := { f :label \"x\" }`.",
        },
        .bare_term_in_definition => .{
            .message = "{} binds nothing",
            .explanation = "A definition's items are entries (`subject :attr value`) and equations. A term on its own has no attribute to bind.",
            .hint = "Give it an attribute, or group several subjects: `(yes, paid) :label \"yes\"`.",
        },
        .levels_in_definition => .{
            .message = "Levels in a definition",
            .explanation = "`|` separates the levels of a declaration. A definition binds values, which have no levels.",
            .hint = "Write `,` between items, or move the levels to the diagram's declaration.",
        },
        .bad_declaration_head => .{
            .message = "{} cannot be declared",
            .explanation = "A declaration builds structure, and only diagrams, nodes and edges are structure: `G :: f g`.",
            .hint = "Use a diagram name for the head, or `:=` to define a value.",
        },
        .bad_definition_head => .{
            .message = "{} is not the head of a definition",
            .explanation = "A definition's left side is `[name]` (a value), `:attr` (a bundle) or `subject :attr` (an attribute at a subject).",
            .hint = "Add the attribute being defined, as in `G :style := { … }`, or use `::` to declare a diagram.",
        },
        .mixed_operators => .{
            .message = "{} follows a different operator",
            .explanation = "Operators between chains share one level, with no precedence: a run may repeat one operator, and different ones need a group.",
            .hint = "Group the parts: `(f == g) ~= h`.",
        },
        .zone_declared_twice => .{
            .message = "The diagram {} is declared twice",
            .explanation = "One declaration per diagram. References go to the first one.",
            .hint = "Rename one of them, or merge their bodies into one declaration.",
        },
        .chain_broken_across_lines => .{
            .message = "This chain continues from the line before",
            .explanation = "Inside braces a newline is a space, so a chain on two lines is one chain: `f g` then `h k` reads `f g h k`.",
            .hint = "Write `,` at the end of the line for two items, or group the chain to say it is one.",
        },
        .node_beside_space => .{
            .message = "The node {} stands beside a space",
            .explanation = "A space joins the end of one edge to the start of the next. A node is attached to an edge with `/`.",
            .hint = "Attach it with a slash: `#A/f`, `*/f`, `@/(…)`.",
        },
        .pinched_edge_beside_space => .{
            .message = "The reference {} stands beside a space",
            .explanation = "A pinched single edge is a reference to the node at that end, and a node is attached with `/`. To pinch a group, the marker goes on the group.",
            .hint = "Move the marker to the group: `f/? +(g, h)`, or attach the reference: `g/+f`.",
        },
        .slash_between_nodes => .{
            .message = "A `/` between two nodes",
            .explanation = "`/` attaches a node to an edge, so it needs an edge on one side at least. Two nodes side by side have nothing between them.",
            .hint = "Put the edge between them: `#A/f/#B`.",
        },
        .both_ends_null => .{
            .message = "An edge from a null node to a null node",
            .explanation = "A null node is a start or a stop. An edge from nothing to nothing says nothing.",
            .hint = "Keep one end: `*/f` or `f/*`.",
        },
        .null_not_on_one_end => .{
            .message = "{} does not hold exactly one end",
            .explanation = "A null node is private to one edge end: it starts one edge or stops one. Alone it holds none; inside a chain or a cycle it would hold two.",
            .hint = "Put `*` at the outer end of a single edge: `*/f`, `f/*`; for several, `(*/f, */g)`.",
        },
        .kind_on_the_left => .{
            .message = "The kind {} is on the left",
            .explanation = "A kind is written where flow arrives: after an edge, `f/?`, or after a group, `(a, b)?`. Nothing arrives on the left.",
            .hint = "Write the decision after its edge: `f/? +(g, h)`.",
        },
        .kind_closes_cycle => .{
            .message = "The kind {} closes a cycle",
            .explanation = "A cycle ends where it starts, so a kind at its end sits on the left of its first edge, where nothing arrives.",
            .hint = "Put the kind after an edge that leads into the cycle, or name the node: `f/#Loop/g`.",
        },
        .lone_kind => .{
            .message = "The kind {} stands alone",
            .explanation = "A kind marks the node where flow arrives, and nothing arrives at a lone node.",
            .hint = "Write it after the edge that reaches it: `f/?`.",
        },
        .kind_on_reference => .{
            .message = "The kind {} is on a node that already exists",
            .explanation = "A kind is set where its node is created. A reference, `f+` or `A.f`, points to a node created before.",
            .hint = "Write the kind where the edge is declared: `f/?`.",
        },
        .kind_after_group => .{
            .message = "The kind {} follows a group",
            .explanation = "A kind node follows a single edge. After a group, the ends are pinched with the kind as the marker.",
            .hint = "Pinch the group: `(a, b)?`.",
        },
        .kind_after_group_of_one => .{
            .message = "The kind {} follows a group of one",
            .explanation = "A group of one is its item, so this is the kind after that edge.",
            .hint = "Drop the parentheses: `f/?`.",
        },
        .ends_dont_match => .{
            .message = "The space before {} joins several ends",
            .explanation = "A space joins exactly one end to exactly one end. Several ends become one only through a pinch.",
            .hint = "Pinch the group: `f +(g, h)`, `(f, g)+ h`.",
        },
        .nothing_to_join => .{
            .message = "Nothing to join here: one side exposes nothing",
            .explanation = "A stop (`*`) and a cycle expose nothing on their right, so there is no end for the space or the `/` to join.",
            .hint = "Write `,` for separate pieces: `f/*, g`.",
        },
        .slash_between_groups => .{
            .message = "This `/` glues several ends to several",
            .explanation = "A `/` glues one node or end to every end on its other side. Several to several would merge them all into one node, a collapse nobody wrote.",
            .hint = "Pinch one side first: `(f, g)+/(h, k)`.",
        },
        .undirected_not_one_edge => .{
            .message = "A trailing `/` needs a single edge",
            .explanation = "A trailing `/` makes one edge undirected, so the chain it ends must hold exactly one edge, written by its name.",
            .hint = "Write it on each edge: `f/ g/`.",
        },
        .edge_declared_twice => .{
            .message = "The edge {} is already declared",
            .explanation = "A bare name declares an edge, once per diagram. Only `f/f` writes the same edge twice, as a loop.",
            .hint = "Refer to one of its ends instead: `+f`, `f+`.",
        },
        .self_reference_outside_loop => .{
            .message = "The edge {} refers to itself in its own chain",
            .explanation = "A loop is written `f/f`: a single edge on the left. Anywhere else in the chain, the second name would declare the edge again.",
            .hint = "Close the cycle on a reference: `+f/g/f+`, or write the loop `f/f`.",
        },
        .redundant_self_attachment => .{
            .message = "This reference attaches {} to its own start",
            .explanation = "Gluing the end of f to its start is a loop, which is written `f/f`.",
            .hint = "Write `f/f`.",
        },
        .vacuous_self_attachment => .{
            .message = "This reference attaches {} to its own end",
            .explanation = "Gluing the end of f to itself says nothing.",
            .hint = "Drop the reference: `f`.",
        },
        .cycle_does_not_close => .{
            .message = "This cycle ends at {}, not where it began",
            .explanation = "A chain of two or more edges is a cycle: it ends where it began. Ending on a node, that node must be its start.",
            .hint = "End on the start (`#A/f/#B/g/#A`, or just `#A/f/#B/g`), or write a path with a space.",
        },
        .reference_not_declared => .{
            .message = "The edge {} is not declared",
            .explanation = "A reference to an end needs its edge declared before it, in the same diagram.",
            .hint = "Declare the edge first: `k, +k/g`.",
        },
        .forward_reference => .{
            .message = "The edge {} is declared later",
            .explanation = "References point left only: the edge must be declared before it is referred to.",
            .hint = "Move the declaration first: `f, +f/g`.",
        },
        .pinch_of_declared_edges => .{
            .message = "The edge {} is already declared; a pinch declares its branches",
            .explanation = "A pinch with several branches declares new edges. It never merges existing nodes by surprise: joining existing things is the job of `/`.",
            .hint = "Attach with a slash to the ends you mean: `+f/h`, or give the branch a new name.",
        },
        .single_edge_pinched_twice => .{
            .message = "{} pinches a single edge that is already pinched",
            .explanation = "A pinched single edge is a reference to one node, and a node has no sides to pinch. A term can't be both ends of an edge.",
            .hint = "Keep one side: `+f` or `f+`. A group may be pinched on both sides: `+(f, g)+`.",
        },
        .pinch_of_a_node => .{
            .message = "{} pinches a node",
            .explanation = "A pinch merges the ends of the branches of a group into one node. A node is already one, with no ends of its own to merge.",
            .hint = "Attach the node with a slash: `#A/f`.",
        },
        .pinch_of_nothing => .{
            .message = "{} pinches nothing",
            .explanation = "Every branch exposes nothing on this side (a stop, a cycle's right side, a lone node), so there are no ends to merge.",
            .hint = "Drop the pinch, or end the branches where they can meet.",
        },
        .pinch_of_one_end => .{
            .message = "{} pinches a single end",
            .explanation = "The other branches expose nothing on this side, so the pinch merges one end with nothing: it is that end.",
            .hint = "Drop the pinch and write the pieces apart: `+(f, #A)` is `f, #A`; with a kind, `(a, b/b)! k` is `a/! k, b/b`.",
        },
        .kinds_disagree => .{
            .message = "Two different kinds meet at {}",
            .explanation = "A node has one kind: plain, choice, parallel or null. A named node is plain, so it is never a decision or a bar.",
            .hint = "Put an edge between them: `validate/? yes/#Valid`.",
        },
        .two_names_for_one_node => .{
            .message = "Two names meet at {}",
            .explanation = "Where ends meet they become one node, and a node has at most one name.",
            .hint = "Put an edge between them, or keep one name.",
        },
        .reference_to_null_node => .{
            .message = "This end of {} is a null node",
            .explanation = "A null node (`*`) is private to the one edge end it holds: nothing glues to it and nothing refers to it.",
            .hint = "Name the node instead of `*`: `f/#Done, j/#Done`.",
        },
        .space_reaches_one_branch => .{
            .message = "The space before {} joins one branch of several",
            .explanation = "The other branches of the group expose nothing on this side (a stop, a cycle, a lone node), so the space joins only one of them, though it reads as joining the group.",
            .hint = "Move the step into the branch it joins: `f/*, g h`.",
        },
        .reserved_node_or_edge_declaration => .{
            .message = "Declaring {} is reserved",
            .explanation = "Only diagrams are declared today. What declaring a node or an edge on its own means is still open in the spec, so it is an error until it is decided.",
            .hint = "Declare a diagram instead: `T :: …`.",
        },
        .unsupported_levels => .{
            .message = "Levels above the first are not supported yet",
            .explanation = "The program is valid, but this compiler does not analyse levels above the first yet. They are skipped; the first level is drawn.",
            .hint = "Nothing to fix in the program.",
        },
        .unsupported_definition => .{
            .message = "Definitions are not supported yet",
            .explanation = "The program is valid, but this compiler only checks a definition's shape so far. Its value is not applied.",
            .hint = "Nothing to fix in the program.",
        },
    };
}

/// How a token kind reads in a message, for `{expected}`.
pub fn describe(tag: Token.Tag) []const u8 {
    return switch (tag) {
        .eof => "end of input",
        .eol => "end of line",
        .invalid => "valid text",
        .zone_id => "a zone name",
        .node_id => "a node name",
        .edge_id => "an edge name",
        .attr_id => "an attribute",
        .class_id => "a class",
        .str => "a string",
        .math => "math",
        .val => "a value",
        .slash => "`/`",
        .plus => "`+`",
        .star => "`*`",
        .quid => "`?`",
        .bang => "`!`",
        .at => "`@`",
        .dot => "`.`",
        .iden => "`==`",
        .cong => "`~=`",
        .decl => "`::`",
        .defn => "`:=`",
        .comma => "`,`",
        .bar => "`|`",
        .l_par => "`(`",
        .r_par => "`)`",
        .l_cur => "`{`",
        .r_cur => "`}`",
    };
}
