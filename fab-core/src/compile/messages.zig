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
        _ => unreachable, // no tags yet
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
