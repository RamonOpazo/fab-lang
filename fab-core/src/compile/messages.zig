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
            .message = "Expected a zone name, found {}",
            .explanation = "Every statement starts with a zone name: `G :: …` defines the zone, and `G :format { … }` adds a layer to it.",
            .hint = "Start the line with an uppercase zone name.",
        },
        .expected_atom => .{
            .message = "Expected an edge, a node or a group, found {}",
            .explanation = "Terms are built from edges (`f`), nodes (`#A`, `@`, zone names), groups `( … )` and edge-to-edge relations `[ … ]`.",
            .hint = "Check for a missing name, or for an operator with nothing to apply to.",
        },
        .expected_attrs_or_relation => .{
            .message = "Expected attributes or an equation, found {}",
            .explanation = "Each line of a layer either gives its subject attributes (`f :label \"x\"`) or states an equation (`f g == h`).",
            .hint = "Add an attribute such as `:label`, or an equation with `==` or `~=`.",
        },
        .slash_has_no_prefix_form => .{
            .message = "`/` touches only what follows it",
            .explanation = "`/` attaches to what it touches: `f/g` is a back edge, and `f/` with nothing after it makes `f` undirected. There is no form where `/` touches only the right side.",
            .hint = "Write `f/g` without spaces, or `f/ g` for an undirected `f` followed by `g`.",
        },
        .operator_touches_nothing => .{
            .message = "{} touches nothing",
            .explanation = "The operators `/`, `+`, `*`, `?` and `!` attach to the term they touch. With spaces on both sides, this one has nothing to attach to.",
            .hint = "Remove the space between the operator and its term, as in `+f` or `f?`.",
        },
        .detached_dot => .{
            .message = "A `.` must touch both sides",
            .explanation = "The dot joins a qualifier to what it qualifies, as in `A.+f` or `.node.id`, so nothing may separate them.",
            .hint = "Remove the spaces around the dot.",
        },
        .invalid_token => .{
            .message = "Unrecognised text {}",
            .explanation = "This is not a name, number, literal or operator of fAB. Unterminated strings and math end up here too.",
            .hint = "Check for a missing closing `\"` or `$`, or a character fAB does not use.",
        },
    };
}

pub fn analysis(tag: Analyser.Error.Tag) Text {
    return switch (tag) {
        // zones and layers
        .zone_defined_twice => .{
            .message = "Zone {} is defined twice",
            .explanation = "Each zone is defined by exactly one `::` statement.",
            .hint = "Rename one of the zones, or merge their terms into one definition.",
        },
        .zone_not_defined => .{
            .message = "Zone {} is not defined before this point",
            .explanation = "References point left: a zone can only be used after the statement that defines it, and never inside its own definition.",
            .hint = "Define {} above this line, or check its spelling.",
        },
        .zone_has_no_own_node => .{
            .message = "Zone {} has no own node `@`",
            .explanation = "A zone used as a node attaches at the node that stands for it, written `@` in its definition.",
            .hint = "Add `@` to the zone's definition, as in `User :: @ (…)`.",
        },
        .layer_for_unknown_zone => .{
            .message = "Layer for undefined zone {}",
            .explanation = "A layer adds format or proof to a zone that already exists.",
            .hint = "Define the zone with `::` before its layers, or check its spelling.",
        },
        .layer_defined_twice => .{
            .message = "Layer {} is defined twice for this zone",
            .explanation = "Each zone has at most one format layer and one proof layer.",
            .hint = "Merge the two blocks into one.",
        },
        .unknown_layer => .{
            .message = "Unknown layer {}",
            .explanation = "The layers are `:format`, for presentation, and `:proof`, for equations and properties.",
            .hint = "Use `:format` or `:proof`.",
        },

        // edges and references
        .edge_declared_twice => .{
            .message = "Edge {} is declared twice",
            .explanation = "A bare name declares a new edge, and each name is declared once per zone. The one exception is the endomorphism `f/f`.",
            .hint = "To use the edge again, refer to one of its ends, `+f` or `f+`, fused with `/`.",
        },
        .undeclared_edge => .{
            .message = "Edge {} is not declared before this point",
            .explanation = "References point left: `+f` and `f+` refer to an edge declared earlier in the same zone, or in the zone named before the dot.",
            .hint = "Declare {} earlier, or check its spelling.",
        },
        .undeclared_name => .{
            .message = "Node {} is not declared in that zone",
            .explanation = "A name reached through another zone, as in `T.#UUID7`, must already be declared there. Names never come into existence by being mentioned.",
            .hint = "Add {} to that zone's definition, or check its spelling.",
        },
        .bare_reference => .{
            .message = "A reference must be fused with `/`",
            .explanation = "`+f` and `f+` name an existing node. On their own they add nothing, so they only appear joined to an edge, as in `g/+f` or `+f/g`.",
            .hint = "Attach an edge to the reference with `/`, or remove it.",
        },
        .not_an_edge => .{
            .message = "Only a single edge has ends to refer to",
            .explanation = "`+f` is the domain of the edge `f`, `f+` its codomain, and `f/` makes `f` undirected. These forms apply to one edge name.",
            .hint = "Apply the operator to an edge name.",
        },
        .edge_from_references_only => .{
            .message = "This `/` creates no edge",
            .explanation = "With references on both sides, `/` would only identify two existing nodes. At least one side must be a bare edge name.",
            .hint = "Make the identification where one of the two edges is declared, as in `g/+f`.",
        },
        .self_reference_outside_endomorphism => .{
            .message = "Edge {} returns to its own term",
            .explanation = "`f/f` is the only form in which a name repeats: it makes `f` an endomorphism. A longer term on the left can't end in one of its own edges.",
            .hint = "Give the returning edge its own name, as in `(f g)/h`.",
        },
        .redundant_self_attachment => .{
            .message = "This is the endomorphism `f/f`, written another way",
            .explanation = "Attaching an edge's codomain to its own domain gives the same graph as `f/f`.",
            .hint = "Write it as `f/f`.",
        },
        .vacuous_self_attachment => .{
            .message = "This glues an end to itself",
            .explanation = "The edge already ends at this node, so the attachment adds nothing.",
            .hint = "Remove the reference.",
        },
        .unsupported_qualified_reference => .{
            .message = "{} can't be reached through another zone",
            .explanation = "Through a zone name you can reach an edge's end (`A.+f`, `A.f+`), a named node (`A.#X`) or the zone's own node (`A.@`).",
            .hint = "Use one of those forms.",
        },
        .class_in_relations => .{
            .message = "Classes belong in layers, not in relations",
            .explanation = "A class such as `.iso` names a set of attributes. It is used in `:format` and `:proof` blocks, never in a `::` term.",
            .hint = "Move it into a layer.",
        },

        // gluing
        .juxtaposition_glues_nothing => .{
            .message = "Nothing to connect {} to",
            .explanation = "Juxtaposition glues the open outputs on its left to the open inputs on its right. Here one side has none, because a `*` or a reference closed it.",
            .hint = "Separate the pieces with `,`, or remove what closes the side.",
        },
        .back_edge_glues_nothing => .{
            .message = "This back edge has nothing to connect",
            .explanation = "`s/e` runs `e` from the end of `s` back to its start, so every side involved needs open ends.",
            .hint = "Check for a `*` or a reference closing one of the sides.",
        },

        // node kinds and names
        .kind_declared_twice => .{
            .message = "This node's kind is already declared",
            .explanation = "A node's kind (`?`, `!` or `*`) is set once, where the node is created. References inherit the kind of the node they land on.",
            .hint = "Remove this marker.",
        },
        .conflicting_kinds => .{
            .message = "Conflicting node kinds",
            .explanation = "A node is plain, a choice `?`, parallel `!` or null `*`, never two of these at once.",
            .hint = "Keep one of the markers.",
        },
        .marker_on_closed_side => .{
            .message = "{} has no open end to mark",
            .explanation = "`?`, `!` and `*` act on the open ends of the term they touch, and that side has already been closed.",
            .hint = "Move the marker, or remove it.",
        },
        .reference_to_sealed_end => .{
            .message = "This end is sealed",
            .explanation = "A null node `*` belongs to exactly one edge end: nothing can be glued to it, and nothing can refer to it.",
            .hint = "Remove the `*`, or refer to another end.",
        },
        .sealing_shared_end => .{
            .message = "Only an unshared end can be sealed",
            .explanation = "`*` closes an end with its own null node, so the end can't also be glued to another edge, carry a name, or be used by a back edge.",
            .hint = "Remove the `*`, or seal an end nothing else uses.",
        },
        .both_ends_sealed => .{
            .message = "This edge is sealed at both ends",
            .explanation = "An edge from nothing to nothing says nothing: it connects no node of the diagram.",
            .hint = "Remove one of the `*` markers.",
        },
        .node_named_twice => .{
            .message = "This node already has a name",
            .explanation = "A node has at most one name: `#A`, `@`, or a zone name.",
            .hint = "Keep one name, and refer to the node by it.",
        },
        .two_own_nodes => .{
            .message = "A second own node `@` in this zone",
            .explanation = "`@` marks the one node that stands for the zone itself.",
            .hint = "Use a single `@`, and connect everything that needs it through that one.",
        },

        // edge-to-edge relations
        .inner_node_not_an_edge => .{
            .message = "Cell {} must run between declared edges",
            .explanation = "Inside `[ ]` the nodes are the edges declared in the zone, and every new name is a cell between two of them.",
            .hint = "Connect the cell to a declared edge on each side, as in `[f α g]`.",
        },
        .two_edges_in_one_node => .{
            .message = "Two different edges would become one node",
            .explanation = "Inside `[ ]` each node is exactly one declared edge. Gluing two of them would identify different arrows.",
            .hint = "Put a cell between them, as in `[f α g]`.",
        },
        .cells_not_parallel => .{
            .message = "Cell {} connects edges that aren't parallel",
            .explanation = "A cell between two edges requires them to share both their domain and their codomain.",
            .hint = "Check that both edges start and end at the same nodes.",
        },
        .unsupported_in_cells => .{
            .message = "{} is not supported inside `[ ]` yet",
            .explanation = "Inside `[ ]` you can use edge names, juxtaposition, `,`, groups and back edges. Markers and references have no meaning there yet.",
            .hint = "Remove it from the block.",
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
        .number => "a number",
        .string => "a string",
        .math => "math",
        .arrow => "an arrow",
        .slash => "`/`",
        .plus => "`+`",
        .star => "`*`",
        .quid => "`?`",
        .bang => "`!`",
        .at => "`@`",
        .dot => "`.`",
        .range => "`..`",
        .iden => "`==`",
        .cong => "`~=`",
        .decl => "`::`",
        .defn => "`:=`",
        .comma => "`,`",
        .l_paren => "`(`",
        .r_paren => "`)`",
        .l_brack => "`[`",
        .r_brack => "`]`",
        .l_brace => "`{`",
        .r_brace => "`}`",
    };
}
