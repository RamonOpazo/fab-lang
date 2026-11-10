//! Namings, `head := body`, and descriptions, `context :descriptor value`
//! (statements.md §22.1). A naming's head has one of three forms; its body
//! holds descriptions, namings, equations and, alone, a literal. A type is
//! declared, never named (§22.8). Named values are read into the environment
//! (`vocabulary.zig`), themes and bundles checked as records
//! (`records.zig`). Descriptions are the layers, which wait for plan steps 9
//! and 11, so they are reported as unsupported once checked.
//!
//! Also the heads of the declarations that make vocabulary, not structure:
//! a type's labels and a function's signature (statements.md §21).

const Token = @import("../lex/Token.zig");
const Cst = @import("../parse/Cst.zig");
const Analyser = @import("Analyser.zig");
const value = @import("value.zig");
const vocabulary = @import("vocabulary.zig");
const records = @import("records.zig");

const Node = Cst.Node;

pub fn naming(a: *Analyser, node: Node.Index, head: Node.Index, body: Node.Index) error{OutOfMemory}!void {
    const cst = a.cst;
    // A head of no known form says nothing of what its body holds, so the
    // body's items are not checked: their errors would be guesses. Its
    // brackets are, since a bracket's shape doesn't depend on the head.
    if (!isHead(cst, head)) {
        try a.fail(.bad_naming_head, cst.firstToken(head));
        try brackets(a, body);
        return;
    }

    // `:Length := :Number`: a type is no value. Read as the declaration it
    // meant, so its uses don't fail too.
    if (isLeafOf(cst, head, .type_id)) {
        try a.fail(.type_named_with_defn, cst.mainToken(node));
        try brackets(a, body);
        return vocabulary.declareType(a, head, body);
    }

    // `G :style := { … }`: a description, which takes no operator. What it
    // would have meant is plain, so its body is checked as one.
    if (cst.tag(head) == .entry and cst.subject(head) != null) {
        try a.fail(.description_with_operator, cst.mainToken(node));
        try brackets(a, body);
        if (!isLiteral(cst, body)) try entries(a, body);
        return;
    }

    if (cst.tag(body) == .levels) {
        try a.fail(.levels_in_naming, cst.mainToken(body));
    } else if (!isLiteral(cst, body)) {
        try entries(a, body);
    }
    try brackets(a, head);
    try brackets(a, body);

    // `[warn] := [red]`, `:Color [warn] := [red]`: a named value; with a
    // record, `:Style [dark] := { … }`, a theme.
    if (isLeafOf(cst, head, .val) or (cst.tag(head) == .o_chain and isPair(cst, head, .type_id))) {
        const named = try vocabulary.namedValue(a, head, body);
        if (cst.tag(body) == .block) {
            const record = if (named.contract) |t| (if (a.env.isRecord(t)) t else null) else null;
            const contents = try records.theme(a, body, record);
            // Its structure, for where it is used. Defined once: a name
            // defined twice keeps the first.
            if (named.name) |n| if (a.env.values.getPtr(n)) |v| {
                if (v.body == body) v.contents = contents;
            };
        }
        return;
    }
    // `:terminal := { … }`: a bundle, the only head left.
    try records.bundle(a, if (cst.tag(head) == .attr) head else cst.children(head)[0], body);
}

/// `G :style { … }`, `G.f :arrow [epi]`: a layer's description. Checked for
/// shape; what it binds is applied from step 9 on. Returns whether it has a
/// context, without which it describes nothing.
pub fn description(a: *Analyser, entry: Node.Index) error{OutOfMemory}!bool {
    const cst = a.cst;
    const subject = cst.subject(entry);
    if (subject == null) try a.fail(.context_missing, cst.firstToken(entry));
    try brackets(a, entry);
    try entries(a, entry);
    return subject != null;
}

/// Reads every bracket under `node`, and reports each element whose shape is
/// wrong. What the elements mean waits for the environment (step 8c).
pub fn brackets(a: *Analyser, node: Node.Index) error{OutOfMemory}!void {
    const cst = a.cst;
    if (cst.tag(node) == .leaf) {
        const token = cst.mainToken(node);
        if (cst.tokenTag(token) != .val) return;
        var reader = value.read(cst.tokenText(token));
        var types = false;
        var values = false;
        while (true) {
            const element = (reader.next() catch {
                try a.fail(reader.failure, token);
                continue;
            }) orelse break;
            if (element.kind == .type) types = true else values = true;
        }
        // `[:Tip/solid/>]`: a bracket holds values, or type names.
        if (types and values) try a.fail(.types_and_values_mixed, token);
        return;
    }
    for (cst.children(node)) |child| try brackets(a, child);
}

/// `[name]`, `:Type [name]`, `:Type` (an error, read as a declaration),
/// `:attr` or `subject :attr`:
/// one attribute, with no value.
fn isHead(cst: *const Cst, head: Node.Index) bool {
    return switch (cst.tag(head)) {
        .leaf => switch (cst.tokenTag(cst.mainToken(head))) {
            .val, .type_id => true,
            else => false,
        },
        .o_chain => isPair(cst, head, .type_id),
        .attr => bare(cst, head),
        .entry => blk: {
            const attrs = cst.list(cst.data(head).range)[1..];
            break :blk attrs.len == 1 and cst.tag(attrs[0]) == .attr and bare(cst, attrs[0]);
        },
        else => false,
    };
}

/// A descriptor with no value and no key.
fn bare(cst: *const Cst, attr: Node.Index) bool {
    return cst.data(attr).node == .root and cst.key(attr) == null;
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
pub fn areClasses(cst: *const Cst, node: Node.Index) bool {
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
/// type; a bracket and a literal, when a bracket.
pub fn isPair(cst: *const Cst, node: Node.Index, first: Token.Tag) bool {
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

/// The items of a record: descriptions, namings and operations, side by
/// side. A descriptor's record or proposition is one too.
pub fn entries(a: *Analyser, node: Node.Index) error{OutOfMemory}!void {
    const cst = a.cst;
    switch (cst.tag(node)) {
        .items => {
            // The owner's descriptors come first (statements.md §22.1).
            var part = false;
            for (cst.children(node)) |item| {
                if (cst.tag(item) == .entry) {
                    if (cst.subject(item) != null) {
                        part = true;
                    } else if (part) try a.fail(.owner_after_part, cst.firstToken(item));
                }
                try entries(a, item);
            }
        },
        .block => {
            const inner = cst.children(node)[0];
            if (cst.tag(inner) == .levels) {
                try a.fail(.levels_in_naming, cst.mainToken(inner));
            } else try entries(a, inner);
        },
        .entry => {
            const parts = cst.children(node);
            for (parts[@intFromBool(cst.subject(node) != null)..]) |part| switch (cst.tag(part)) {
                // `subject { … }`: the block holds the subject's items.
                .block => try entries(a, part),
                // `:style { … }`, `:axiom (f == g)`: a record, a proposition.
                .attr => {
                    const v = cst.data(part).node;
                    switch (cst.tag(v)) {
                        .block, .group => try entries(a, v),
                        else => {},
                    }
                },
                else => {},
            };
        },
        .operation => try operation(a, node),
        // `[ink] := [#dddddd]` names in the record; `::` declares only in a
        // type being declared, `:Style :: { … }` (step 9b).
        .statement => switch (cst.tokenTag(cst.mainToken(node))) {
            .decl => try a.fail(.declaration_in_record, cst.mainToken(node)),
            else => {},
        },
        // A group of propositions: `(f h == g k, +f :pullback)`.
        .group => try entries(a, cst.children(node)[0]),
        .invalid => {},
        else => try a.fail(.bare_term_in_record, cst.firstToken(node)),
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
