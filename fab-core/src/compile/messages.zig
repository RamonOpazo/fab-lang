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
