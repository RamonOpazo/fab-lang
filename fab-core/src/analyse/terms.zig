//! The terms of a declaration: they hold only structure, edges and nodes
//! (rule 0), and each node term stands where its sort allows (rule 1). A term
//! with an error is not looked into further.

const Cst = @import("../parse/Cst.zig");
const Analyser = @import("Analyser.zig");
const sort = @import("sort.zig");

const Node = Cst.Node;

/// Where a list of terms sits: as items of a body or a block, or inside a
/// group.
pub const Place = enum { item, group };

/// The items of a declaration: terms, side by side.
pub fn items(a: *Analyser, node: Node.Index, place: Place) error{OutOfMemory}!void {
    const cst = a.cst;
    switch (cst.tag(node)) {
        .items => for (cst.children(node)) |item| try items(a, item, place),
        // Braces without a subject only organise. A body's braces may hold
        // its levels; nested ones may not, since a level is the whole body.
        .block => {
            const inner = cst.children(node)[0];
            if (cst.tag(inner) == .levels) {
                try a.fail(.level_inside_branch, cst.mainToken(inner));
                try items(a, cst.children(inner)[0], place);
            } else try items(a, inner, place);
        },
        else => {
            if (a.scope.level > 1 and !try cellsOnly(a, node)) return;
            if (place == .item) try brokenChain(a, node);
            try term(a, node);
        },
    }
}

/// Above level 1 every name is a cell or a side of a lower level (spec,
/// Levels). `*`, kinds, diagram names and other diagrams are level 1 only,
/// and sides are named, so there is nothing to pinch. Each one found fails
/// its own term. Whether there were none.
fn cellsOnly(a: *Analyser, node: Node.Index) error{OutOfMemory}!bool {
    const cst = a.cst;
    const main = cst.mainToken(node);
    switch (cst.tag(node)) {
        .leaf => switch (cst.tokenTag(main)) {
            .zone_id, .star, .quid, .bang => {
                try a.failTerm(.not_a_cell, node, main);
                return false;
            },
            // Only level 1 makes nodes: above it a named node is a side.
            .node_id, .at => {
                const key = if (cst.tokenTag(main) == .at) "@" else cst.tokenText(main);
                if (a.scope.table.contains(key)) return true;
                try a.failTerm(.side_not_declared, node, main);
                return false;
            },
            // Values and classes are rule 0's.
            else => return true,
        },
        .juxtafix => {
            try a.failTerm(.not_a_cell, node, cst.firstToken(node));
            return false;
        },
        .prefix, .postfix => switch (cst.tokenTag(main)) {
            .plus => {
                try a.failTerm(.pinch_above_level_one, node, main);
                return false;
            },
            .quid, .bang => {
                try a.failTerm(.not_a_cell, node, main);
                return false;
            },
            else => return cellsOnly(a, cst.data(node).node),
        },
        .invalid => return true,
        else => {
            var clean = true;
            for (cst.children(node)) |child| clean = try cellsOnly(a, child) and clean;
            return clean;
        },
    }
}

fn term(a: *Analyser, node: Node.Index) error{OutOfMemory}!void {
    const cst = a.cst;
    const main = cst.mainToken(node);
    switch (cst.tag(node)) {
        .entry, .operation => try a.failTerm(.entry_in_declaration, node, cst.firstToken(node)),
        // Chains judge the leaves in them; a leaf reaching here stands alone.
        .leaf => switch (cst.tokenTag(main)) {
            .class_id => try a.failTerm(.class_in_declaration, node, main),
            .str, .math, .val => try a.failTerm(.value_in_declaration, node, main),
            .star => try a.failTerm(.null_not_on_one_end, node, main),
            .quid, .bang => try a.failTerm(.lone_kind, node, main),
            else => {},
        },
        .group => try items(a, cst.children(node)[0], .group),
        .o_chain => for (cst.children(node), 0..) |step, i| {
            if (sort.of(a, step) == .edges) {
                try term(a, step);
            } else if (sort.isPinchedEdge(a, step)) {
                try a.failTerm(.pinched_edge_beside_space, step, cst.firstToken(step));
            } else if (a.scope.level > 1 and isPath(a, cst.children(node), i)) {
                // Two sides side by side: a composite, which is no side.
                try a.failTerm(.path_as_side, node, cst.firstToken(node));
                return;
            } else {
                try a.failTerm(.node_beside_space, step, cst.firstToken(step));
            }
        },
        .c_chain => try closedChain(a, node),
        .prefix => switch (cst.tokenTag(main)) {
            .quid, .bang => try a.failTerm(.kind_on_the_left, node, main),
            else => try markerOperand(a, node),
        },
        .postfix => switch (cst.tokenTag(main)) {
            .quid, .bang => if (sort.isSingleEdge(a, cst.data(node).node)) {
                try a.failTerm(.kind_on_reference, node, main);
            } else try markerOperand(a, node),
            // A trailing `/` is judged with its chain (rule 2).
            .slash => if (sort.of(a, cst.data(node).node) == .edges) try term(a, cst.data(node).node),
            else => try markerOperand(a, node),
        },
        .juxtafix => try crossReference(a, node),
        .invalid => {},
        else => for (cst.children(node)) |child| try term(a, child),
    }
}

/// Above level 1, whether a step and the one after it are both sides.
fn isPath(a: *Analyser, steps: []const Node.Index, i: usize) bool {
    return i + 1 < steps.len and sort.of(a, steps[i + 1]) == .node;
}

/// `A.+f`, `A.f+`, `A.#X`, `A.@` (rule 6): in relations, `.` reaches a node
/// of another diagram, never one of its edges. A kind there would change a
/// node that exists.
fn crossReference(a: *Analyser, node: Node.Index) error{OutOfMemory}!void {
    const cst = a.cst;
    const left, const right_ = cst.data(node).nodes;
    const right = sort.ofOne(cst, right_);
    const marker = if (cst.tag(right) == .postfix) cst.tokenTag(cst.mainToken(right)) else null;
    if (marker == .quid or marker == .bang)
        return a.failTerm(.kind_on_reference, node, cst.mainToken(right));
    const reaches = sort.isPinchedEdge(a, right) or sort.isLeaf(cst, right, .node_id) or sort.isLeaf(cst, right, .at);
    if (!sort.isLeaf(cst, left, .zone_id) or !reaches)
        try a.failTerm(.cross_reference_not_a_node, node, cst.firstToken(node));
}

/// The operand of a marker (rule 4). A pinched single edge is one node, so
/// it can't be pinched again; a marker on any other node has nothing to
/// pinch.
fn markerOperand(a: *Analyser, marker: Node.Index) error{OutOfMemory}!void {
    const cst = a.cst;
    const main = cst.mainToken(marker);
    const operand = sort.ofOne(cst, cst.data(marker).node);
    if (sort.isPinchedEdge(a, operand)) return a.failTerm(.single_edge_pinched_twice, marker, main);
    if (sort.of(a, operand) == .node) return a.failTerm(.pinch_of_a_node, marker, main);
    try term(a, operand);
}

/// `a/b/…`. A `/` needs an edge on one side at least. A `*` is private to one
/// end, so it stands at either end of a one-edge chain. A kind marks where
/// flow arrives, so it stands last, right after the chain's one edge.
fn closedChain(a: *Analyser, node: Node.Index) error{OutOfMemory}!void {
    const cst = a.cst;
    const links = cst.children(node);
    const last = links.len - 1;

    // Checked first: with two nodes side by side, nothing else in the chain
    // can be judged.
    for (links[0..last], links[1..]) |left, right| {
        if (sort.of(a, left) == .node and sort.of(a, right) == .node)
            return a.failTerm(.slash_between_nodes, node, cst.lastToken(left) + 1);
    }

    var edges: usize = 0;
    for (links) |link| edges += @intFromBool(sort.of(a, link) == .edges);

    if (links.len == 3 and edges == 1 and sort.isLeaf(cst, links[0], .star) and sort.isLeaf(cst, links[last], .star))
        return a.failTerm(.both_ends_null, node, cst.mainToken(links[last]));

    for (links, 0..) |link, i| {
        const token = cst.mainToken(link);
        if (sort.isLeaf(cst, link, .star)) {
            if ((i != 0 and i != last) or edges > 1) try a.failTerm(.null_not_on_one_end, link, token);
        } else if (sort.isLeaf(cst, link, .quid) or sort.isLeaf(cst, link, .bang)) {
            if (i != last) {
                try a.failTerm(.kind_on_the_left, link, token);
            } else if (edges > 1) {
                try a.failTerm(.kind_closes_cycle, link, token);
            } else {
                try kindAfter(a, links[i - 1], link);
            }
        } else if (!(i + 1 == last and cst.tag(link) == .juxtafix and isKind(cst, links[last]))) {
            // A cross reference before a kind is the kind's to report.
            try term(a, link);
        }
    }
}

fn isKind(cst: *const Cst, link: Node.Index) bool {
    return sort.isLeaf(cst, link, .quid) or sort.isLeaf(cst, link, .bang);
}

/// What a kind node may follow: an edge being declared. A node before it was
/// already reported, as a slash between nodes.
fn kindAfter(a: *Analyser, before: Node.Index, kind: Node.Index) error{OutOfMemory}!void {
    const cst = a.cst;
    const token = cst.mainToken(kind);
    switch (cst.tag(before)) {
        .leaf => {},
        .group => if (sort.isSingleEdge(a, before)) {
            try a.failAt(.kind_after_group_of_one, token, kind);
        } else try a.failTerm(.kind_after_group, kind, token),
        .prefix, .postfix => if (sort.isPinchedEdge(a, before)) {
            try a.failTerm(.kind_on_reference, kind, token);
        } else if (cst.tokenTag(cst.mainToken(before)) != .slash) {
            try a.failTerm(.kind_after_group, kind, token);
        },
        .juxtafix => if (sort.of(a, before) == .edges) try a.failTerm(.kind_on_reference, kind, token),
        else => {},
    }
}

/// Warns about an open chain whose steps continue on the next line: in
/// braces a newline is a space, so `f g` then `h k` is one chain, `f g h k`.
/// The chain must be an item of its own; inside a group it is clearly meant.
fn brokenChain(a: *Analyser, node: Node.Index) error{OutOfMemory}!void {
    const cst = a.cst;
    if (cst.tag(node) != .o_chain) return;
    const steps = cst.children(node);
    for (steps[0 .. steps.len - 1], steps[1..]) |left, right| {
        const after = cst.firstToken(right);
        for (cst.lastToken(left) + 1..after) |t| {
            if (cst.tokenTag(@intCast(t)) == .eol) return a.fail(.chain_broken_across_lines, after);
        }
    }
}
