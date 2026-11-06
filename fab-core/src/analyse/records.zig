//! Records, `{ … }`, checked against the environment (statements.md §21.6,
//! §22). Two of them are read here; the layers (`G :style { … }`) wait for
//! plan steps 9 and 11.
//!
//!   :Record [dark] := { [ink] := [#ddd], &zone :fill [#111] }   a theme
//!   :terminal := { :shape [circle], :fill [red] }                a bundle
//!
//! A theme holds tokens, named with `:=`, class contexts, and descriptors
//! with no context, which bind the diagram it is applied to. A bundle holds
//! descriptors only, and applies where all of them apply.
//!
//! The shapes `definitions.entries` reports (bare terms, levels,
//! declarations) are passed over here.

const std = @import("std");
const Cst = @import("../parse/Cst.zig");
const Analyser = @import("Analyser.zig");
const Env = @import("Env.zig");
const definitions = @import("definitions.zig");
const vocabulary = @import("vocabulary.zig");

const Node = Cst.Node;
const TokenIndex = Cst.TokenIndex;

/// `:Record [dark] := { … }`. Functions with no subject bind the owner, a
/// diagram.
pub fn theme(a: *Analyser, body: Node.Index) error{OutOfMemory}!void {
    try themeItems(a, body, .initOne(.zone));
}

/// The items of a theme, or of a subject's block in it, whose functions
/// bind `owner`.
fn themeItems(a: *Analyser, node: Node.Index, owner: Env.Classes) error{OutOfMemory}!void {
    const cst = a.cst;
    var one: [1]Node.Index = undefined;
    for (vocabulary.itemsOf(cst, node, &one)) |item| switch (cst.tag(item)) {
        .statement => if (cst.tokenTag(cst.mainToken(item)) == .defn) try token(a, item),
        .entry => {
            const parts = cst.children(item);
            const subject = cst.subject(item) orelse {
                for (parts) |part| try themeKey(a, part, owner);
                continue;
            };
            if (!definitions.areClasses(cst, subject)) {
                try a.fail(.element_in_theme, cst.firstToken(subject));
                continue;
            }
            var classes: Env.Classes = .empty;
            if (!try vocabulary.readClasses(a, subject, &classes)) continue;
            for (parts[1..]) |part| try themeKey(a, part, classes);
        },
        else => {},
    };
}

fn themeKey(a: *Analyser, part: Node.Index, owner: Env.Classes) error{OutOfMemory}!void {
    switch (a.cst.tag(part)) {
        .attr => try function(a, part, .{ .subject = owner }),
        .block => try themeItems(a, part, owner),
        else => {},
    }
}

/// `:terminal := { … }`: a new function, a flag applying where all its
/// contents apply.
pub fn bundle(a: *Analyser, name: Node.Index, body: Node.Index) error{OutOfMemory}!void {
    const cst = a.cst;
    const name_token = cst.mainToken(name);
    if (cst.inverted(name)) {
        try a.fail(.bad_naming_head, name_token);
        return;
    }
    var classes: Env.Classes = .full;
    if (isLiteral(cst, body)) {
        try a.fail(.wrong_type, cst.firstToken(body));
    } else try bundleItems(a, body, &classes);

    const gop = try a.env.functions.getOrPut(a.gpa, cst.tokenText(name_token));
    if (gop.found_existing) {
        try a.errors.append(a.gpa, .{ .tag = .name_defined_twice, .token = name_token, .related = if (gop.value_ptr.prelude) null else gop.value_ptr.token });
        return;
    }
    gop.value_ptr.* = .{ .classes = classes, .type = .flag, .token = name_token, .bundle = true };
}

fn bundleItems(a: *Analyser, node: Node.Index, classes: *Env.Classes) error{OutOfMemory}!void {
    const cst = a.cst;
    var one: [1]Node.Index = undefined;
    for (vocabulary.itemsOf(cst, node, &one)) |item| switch (cst.tag(item)) {
        // A token is no descriptor either.
        .statement => try a.fail(.subject_in_bundle, cst.firstToken(item)),
        .entry => {
            if (cst.subject(item)) |subject| {
                try a.fail(.subject_in_bundle, cst.firstToken(subject));
                continue;
            }
            for (cst.children(item)) |part| switch (cst.tag(part)) {
                .attr => try function(a, part, .{ .bundle = classes }),
                .block => try bundleItems(a, part, classes),
                else => {},
            };
        },
        else => {},
    };
}

/// Where a function is written: at a subject of these classes, or in a
/// bundle, whose classes it narrows.
const Use = union(enum) { subject: Env.Classes, bundle: *Env.Classes };

/// `:fill [red]`, `:hide`, `:hide!`: known, applying where it is written,
/// and given what its signature asks for.
fn function(a: *Analyser, attr: Node.Index, use: Use) error{OutOfMemory}!void {
    const cst = a.cst;
    const name_token = cst.mainToken(attr);
    const f = a.env.functions.get(cst.tokenText(name_token)) orelse {
        try a.fail(.unknown_attribute, name_token);
        return;
    };
    const signature: ?TokenIndex = if (f.prelude) null else f.token;

    const applies = switch (use) {
        .subject => |classes| Env.within(classes).subsetOf(f.classes),
        .bundle => |classes| blk: {
            const meet = classes.intersectWith(f.classes);
            // Once empty, the bundle applies nowhere, and that was said.
            const ok = !meet.eql(.empty) or classes.eql(.empty);
            classes.* = meet;
            break :blk ok;
        },
    };
    if (!applies) try a.errors.append(a.gpa, .{ .tag = .does_not_apply, .token = name_token, .related = signature });

    const value = cst.data(attr).node;
    const inverted = cst.inverted(attr);
    if (f.type == .flag) {
        if (value != .root) {
            try a.fail(.value_given_to_flag, cst.firstToken(value));
        } else if (inverted and f.bundle) {
            try a.fail(.only_a_flag_inverts, name_token);
        }
        return;
    }
    if (inverted) try a.fail(.only_a_flag_inverts, name_token);
    if (value == .root) {
        if (!inverted) try a.fail(.value_missing, name_token);
        return;
    }
    const t = try vocabulary.typeOf(a, value);
    if (!a.env.fits(t, f.type))
        try a.errors.append(a.gpa, .{ .tag = .wrong_type, .token = cst.firstToken(value), .related = signature });
}

/// `[ink] := [#dddddd]`: a label bound to a value of its type.
fn token(a: *Analyser, naming: Node.Index) error{OutOfMemory}!void {
    const cst = a.cst;
    const key, const value = cst.data(naming).nodes;
    const key_token = switch (vocabulary.labelToken(cst, key)) {
        .label => |t| t,
        .malformed => return,
        .not_a_label => {
            try a.fail(.not_a_label, cst.firstToken(key));
            return;
        },
    };
    const text = cst.tokenText(key_token);
    const label = a.env.values.get(text[1 .. text.len - 1]) orelse {
        try a.fail(.undefined_name, key_token);
        return;
    };
    // A named value is no label: it has a value already.
    if (label.body != null) {
        try a.fail(.not_a_label, key_token);
        return;
    }
    const t = try vocabulary.typeOf(a, value);
    if (!a.env.fits(t, label.type))
        try a.errors.append(a.gpa, .{ .tag = .key_of_wrong_type, .token = cst.firstToken(value), .related = if (label.prelude) null else label.token });
}

fn isLiteral(cst: *const Cst, node: Node.Index) bool {
    return cst.tag(node) == .leaf and switch (cst.tokenTag(cst.mainToken(node))) {
        .str, .math, .val => true,
        else => false,
    };
}
