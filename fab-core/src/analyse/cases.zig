//! Cases (statements.md §24.3, plan step 11c): what holds in the diagrams of
//! one kind.
//!
//!   &zone :kind [flow] :> {
//!       :Proposition :: { &zone :may-end :: :Flag },   declared for flows only
//!       :Style := { &node :shape [round] }             the kind's look (11c2)
//!   }
//!
//! The head is a condition on `&zone :kind`, and nothing else, so a case
//! never feeds itself. Inside the block, `::` declares descriptors in a
//! record type for the kind alone (`Analyser.case_kind`, which `signature`
//! reads), and `:=` binds a record of a type for its diagrams. A name may be
//! declared in several kinds' cases; for every kind and in a case, it is
//! defined twice.

const std = @import("std");
const Cst = @import("../parse/Cst.zig");
const Analyser = @import("Analyser.zig");
const definitions = @import("definitions.zig");
const vocabulary = @import("vocabulary.zig");
const records = @import("records.zig");
const decode = @import("decode.zig");

const Node = Cst.Node;

/// `head :> body`.
pub fn case(a: *Analyser, head: Node.Index, body: Node.Index) error{OutOfMemory}!void {
    const kind = try condition(a, head) orelse return;
    if (a.cst.tag(body) != .block) return a.fail(.case_item_of_no_form, a.cst.firstToken(body));
    a.case_kind = kind;
    defer a.case_kind = null;
    var one: [1]Node.Index = undefined;
    for (vocabulary.itemsOf(a.cst, body, &one)) |item| try caseItem(a, item);
}

/// `&zone :kind [flow]`: the kind, by name, or null when the head is no
/// such condition (said here) or its kind is wrong (said by the check).
fn condition(a: *Analyser, head: Node.Index) error{OutOfMemory}!?[]const u8 {
    const cst = a.cst;
    const first = cst.firstToken(head);
    if (cst.tag(head) != .entry) {
        try a.fail(.case_on_another_descriptor, first);
        return null;
    }
    const parts = cst.children(head);
    const context = cst.subject(head);
    const zone_class = if (context) |c| cst.tag(c) == .leaf and std.mem.eql(u8, cst.tokenText(cst.mainToken(c)), "&zone") else false;
    if (!zone_class or parts.len != 2 or cst.tag(parts[1]) != .attr or !std.mem.eql(u8, cst.tokenText(cst.mainToken(parts[1])), ":kind")) {
        try a.fail(.case_on_another_descriptor, first);
        return null;
    }
    const attr = parts[1];
    try definitions.brackets(a, attr);
    const errors = a.errors.items.len;
    try records.function(a, attr, .{ .record = null, .at = .{ .subject = .initOne(.zone) } });
    if (a.errors.items.len > errors) return null;
    const f = a.env.descriptor(":kind", null) orelse return null;
    return switch (try decode.attr(a, attr, f)) {
        .label => |l| l.name,
        else => null,
    };
}

/// `:T :: { … }`, the kind's descriptors in a record type; `:T := { … }`,
/// its record, applied with its look in plan step 11c2.
fn caseItem(a: *Analyser, item: Node.Index) error{OutOfMemory}!void {
    const cst = a.cst;
    if (cst.tag(item) != .statement) return a.fail(.case_item_of_no_form, cst.firstToken(item));
    const head, const body = cst.data(item).nodes;
    const op = cst.mainToken(item);
    const typed = cst.tag(head) == .leaf and cst.tokenTag(cst.mainToken(head)) == .type_id;
    if (!typed or cst.tag(body) != .block) return a.fail(.case_item_of_no_form, cst.firstToken(item));
    switch (cst.tokenTag(op)) {
        .decl => {
            // Descriptors only: labels and members would be every kind's.
            var one: [1]Node.Index = undefined;
            for (vocabulary.itemsOf(cst, body, &one)) |d| {
                if (cst.tag(d) != .statement or cst.tokenTag(cst.mainToken(d)) != .decl)
                    return a.fail(.case_item_of_no_form, cst.firstToken(d));
            }
            try definitions.brackets(a, body);
            try vocabulary.declareType(a, head, body);
        },
        .defn => try a.fail(.unsupported_case, op),
        else => try a.fail(.case_item_of_no_form, cst.firstToken(item)),
    }
}
