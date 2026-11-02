//! `head := body`. The head has one of three forms; the body holds entries,
//! operations and, alone, a literal. What a definition means waits for plan
//! steps 8–11, so each one is reported as unsupported once checked.

const Cst = @import("../parse/Cst.zig");
const Analyser = @import("Analyser.zig");

const Node = Cst.Node;

pub fn definition(a: *Analyser, node: Node.Index, head: Node.Index, body: Node.Index) error{OutOfMemory}!void {
    const cst = a.cst;
    if (!isHead(cst, head)) try a.fail(.bad_definition_head, cst.firstToken(head));

    if (cst.tag(body) == .levels) {
        try a.fail(.levels_in_definition, cst.mainToken(body));
    } else if (!isLiteral(cst, body)) {
        try entries(a, body);
    }
    try a.fail(.unsupported_definition, cst.mainToken(node));
}

/// `[name]`, `:attr` or `subject :attr`: one attribute, with no value.
fn isHead(cst: *const Cst, head: Node.Index) bool {
    return switch (cst.tag(head)) {
        .leaf => cst.tokenTag(cst.mainToken(head)) == .val,
        .attr => cst.data(head).node == .root,
        .entry => blk: {
            const attrs = cst.list(cst.data(head).range)[1..];
            break :blk attrs.len == 1 and cst.tag(attrs[0]) == .attr and cst.data(attrs[0]).node == .root;
        },
        else => false,
    };
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
