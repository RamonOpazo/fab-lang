//! The place layer's own diagnostics (statements.md §29): what its values
//! mean against the seed and the graph (spec, Errors, Places). Each is a
//! code in fab-core's shape, `Diagnostic.Foreign`; `{}` is the text at the
//! span, quoted as code.

const fab = @import("fab_core");
const Foreign = fab.Diagnostic.Foreign;

pub const seed_not_a_tiling: Foreign = .{
    .name = "seed_not_a_tiling",
    .severity = .@"error",
    .text = .{
        .message = "{} is not a seed",
        .explanation = "A grid grows from a regular polygon that tiles the plane: `[4]`, square, or `[3]`, triangular. `!` draws either counterclockwise.",
        .hint = "Write `[4]` or `[3]`",
    },
};

pub const number_not_whole: Foreign = .{
    .name = "number_not_whole",
    .severity = .@"error",
    .text = .{
        .message = "{} is not a whole number",
        .explanation = "Seeds, spans and directions count sides, ranks and edges: whole numbers. Only a metric's steps may be fractions.",
        .hint = "",
    },
};

pub const flow_of_no_direction: Foreign = .{
    .name = "flow_of_no_direction",
    .severity = .@"error",
    .text = .{
        .message = "{} names no direction",
        .explanation = "A flow is a number, a normal (a number and an empty slot, `[0/]`), one or two letters, or two directions of one edge. An empty slot stands for a normal only after a number.",
        .hint = "",
    },
};

pub const not_an_area: Foreign = .{
    .name = "not_an_area",
    .severity = .@"error",
    .text = .{
        .message = "{} is not an area",
        .explanation = "An area is two directions of one edge k: the first `[k]` or `[k/]`, the second `[k]`, `[k/]` or `[k+1]`, modulo the seed's sides, both mirrored or neither.",
        .hint = "For edge 0: `[0/0]`, `[0/1]`, `[0//0/]`, or `[area]`",
    },
};

pub const directions_cancel: Foreign = .{
    .name = "directions_cancel",
    .severity = .@"error",
    .text = .{
        .message = "{} has no direction between its letters",
        .explanation = "Two letters are the direction between them, so they must be adjacent: `[N/E]`, `[S/W]`. Opposite letters cancel, and a letter twice is the letter.",
        .hint = "",
    },
};

pub const step_of_nothing: Foreign = .{
    .name = "step_of_nothing",
    .severity = .@"error",
    .text = .{
        .message = "{} has a step of 0",
        .explanation = "Every step of a metric is drawn, so each is longer than nothing.",
        .hint = "",
    },
};

pub const span_of_nothing: Foreign = .{
    .name = "span_of_nothing",
    .severity = .@"error",
    .text = .{
        .message = "{} spans no rank",
        .explanation = "An edge crosses at least one rank. Edges within one rank are not designed yet (layout.md §12).",
        .hint = "",
    },
};

pub const spans_disagree: Foreign = .{
    .name = "spans_disagree",
    .severity = .@"error",
    .text = .{
        .message = "The span {} disagrees with the diagram's other spans",
        .explanation = "Where paths meet, their spans must add up alike, and an edge no span states crosses at least one rank: no ranks satisfy these together.",
        .hint = "Leave one of the spans out, so its edge stretches",
    },
};

pub const collapse_different_ends: Foreign = .{
    .name = "collapse_different_ends",
    .severity = .@"error",
    .text = .{
        .message = "{} collapses edges whose ends differ",
        .explanation = "Collapsed edges share one route, so they must join the same two nodes, in either direction. An edge collapses only with another flagged edge between its ends.",
        .hint = "",
    },
};

pub const collapse_cell_side: Foreign = .{
    .name = "collapse_cell_side",
    .severity = .@"error",
    .text = .{
        .message = "{} collapses a side of a cell",
        .explanation = "A cell is drawn between its sides, and edges collapsed into one route have no between.",
        .hint = "",
    },
};
