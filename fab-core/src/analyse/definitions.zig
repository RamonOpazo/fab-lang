//! `head := body`. The head has one of five forms; the body holds entries,
//! operations and, alone, a literal or a type. What a definition means waits
//! for plan steps 8–11, so each one is reported as unsupported once checked.
//!
//! Also the heads of the declarations that make vocabulary, not structure:
//! a type's labels and a function's signature (statements.md §21).

const Token = @import("../lex/Token.zig");
const Cst = @import("../parse/Cst.zig");
const Analyser = @import("Analyser.zig");
const value = @import("value.zig");

const Node = Cst.Node;

pub fn definition(a: *Analyser, node: Node.Index, head: Node.Index, body: Node.Index) error{OutOfMemory}!void {
    const cst = a.cst;
    if (!isHead(cst, head)) try a.fail(.bad_definition_head, cst.firstToken(head));

    if (cst.tag(body) == .levels) {
        try a.fail(.levels_in_definition, cst.mainToken(body));
    } else if (!isLiteral(cst, body) and !isLeafOf(cst, head, .type_id)) {
        // An alias's body is a type expression, read with step 8c.
        try entries(a, body);
    }
    try brackets(a, head);
    try brackets(a, body);
    try a.fail(.unsupported_definition, cst.mainToken(node));
}

/// Reads every bracket under `node`, and reports each element whose shape is
/// wrong. What the elements mean waits for the environment (step 8c).
pub fn brackets(a: *Analyser, node: Node.Index) error{OutOfMemory}!void {
    const cst = a.cst;
    if (cst.tag(node) == .leaf) {
        const token = cst.mainToken(node);
        if (cst.tokenTag(token) != .val) return;
        var reader = value.read(cst.tokenText(token));
        while (true) {
            const element = reader.next() catch {
                try a.fail(reader.failure, token);
                continue;
            };
            if (element == null) break;
        }
        return;
    }
    for (cst.children(node)) |child| try brackets(a, child);
}

/// `[name]`, `:Type [name]`, `:Type` (an alias), `:attr` or `subject :attr`:
/// one attribute, with no value.
fn isHead(cst: *const Cst, head: Node.Index) bool {
    return switch (cst.tag(head)) {
        .leaf => switch (cst.tokenTag(cst.mainToken(head))) {
            .val, .type_id => true,
            else => false,
        },
        .o_chain => isPair(cst, head, .type_id),
        .attr => cst.data(head).node == .root,
        .entry => blk: {
            const attrs = cst.list(cst.data(head).range)[1..];
            break :blk attrs.len == 1 and cst.tag(attrs[0]) == .attr and cst.data(attrs[0]).node == .root;
        },
        else => false,
    };
}

/// `:Shape` in `:Shape :: …`, or `classes :attr` in `(&node) :fill :: …`.
pub fn isVocabulary(cst: *const Cst, head: Node.Index) bool {
    return switch (cst.tag(head)) {
        .leaf => cst.tokenTag(cst.mainToken(head)) == .type_id,
        .entry => blk: {
            const parts = cst.list(cst.data(head).range);
            break :blk parts.len == 2 and areClasses(cst, parts[0]) and cst.tag(parts[1]) == .attr and
                cst.data(parts[1]).node == .root and !cst.inverted(parts[1]);
        },
        else => false,
    };
}

/// `&node`, or a group of classes: `(&node, &zone)`.
fn areClasses(cst: *const Cst, node: Node.Index) bool {
    return switch (cst.tag(node)) {
        .leaf => cst.tokenTag(cst.mainToken(node)) == .class_id,
        .group => areClasses(cst, cst.children(node)[0]),
        .items => for (cst.children(node)) |item| {
            if (!areClasses(cst, item)) break false;
        } else true,
        else => false,
    };
}

/// Two leaves side by side: a typed name, `:Color [red]`, when `first` is a
/// type; a record's key and its value, `[ink] [#dddddd]`, when a bracket.
fn isPair(cst: *const Cst, node: Node.Index, first: Token.Tag) bool {
    const parts = cst.children(node);
    if (parts.len != 2 or !isLeafOf(cst, parts[0], first)) return false;
    return if (first == .type_id) isLeafOf(cst, parts[1], .val) else isLiteral(cst, parts[1]);
}

fn isLeafOf(cst: *const Cst, node: Node.Index, tag: Token.Tag) bool {
    return cst.tag(node) == .leaf and cst.tokenTag(cst.mainToken(node)) == tag;
}

fn isLiteral(cst: *const Cst, node: Node.Index) bool {
    return cst.tag(node) == .leaf and switch (cst.tokenTag(cst.mainToken(node))) {
        .str, .math, .val => true,
        else => false,
    };
}

/// The items of a definition: entries and operations, side by side.
fn entries(a: *Analyser, node: Node.Index) error{OutOfMemory}!void {
    const cst = a.cst;
    switch (cst.tag(node)) {
        .items => for (cst.children(node)) |item| try entries(a, item),
        .block => {
            const inner = cst.children(node)[0];
            if (cst.tag(inner) == .levels) {
                try a.fail(.levels_in_definition, cst.mainToken(inner));
            } else try entries(a, inner);
        },
        .entry => {
            // `subject { … }`: the block holds the subject's entries.
            const parts = cst.children(node);
            const last = parts[parts.len - 1];
            if (cst.tag(last) == .block) try entries(a, last);
        },
        .operation => try operation(a, node),
        // A token bound in a record: `[ink] [#dddddd]`.
        .o_chain => if (!isPair(cst, node, .val)) try a.fail(.bare_term_in_definition, cst.firstToken(node)),
        // A group of propositions: `(f h == g k, +f :pullback)`.
        .group => try entries(a, cst.children(node)[0]),
        .invalid => {},
        else => try a.fail(.bare_term_in_definition, cst.firstToken(node)),
    }
}

/// One operator per run; different ones need a group. Groups among the
/// operands hold runs of their own.
fn operation(a: *Analyser, node: Node.Index) error{OutOfMemory}!void {
    const cst = a.cst;
    const operands = cst.children(node);
    const first = cst.tokenTag(cst.operator(node, 0));
    for (1..operands.len - 1) |i| {
        const op = cst.operator(node, i);
        if (cst.tokenTag(op) != first) {
            try a.fail(.mixed_operators, op);
            break;
        }
    }
    for (operands) |operand| try nestedOperations(a, operand);
}

fn nestedOperations(a: *Analyser, node: Node.Index) error{OutOfMemory}!void {
    switch (a.cst.tag(node)) {
        .operation => try operation(a, node),
        .entry, .leaf, .invalid => {},
        else => for (a.cst.children(node)) |child| try nestedOperations(a, child),
    }
}
