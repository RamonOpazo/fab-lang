//! A problem found in a program, by any stage, in a form that needs only the
//! source to be understood: byte spans instead of token indices.
//!
//! Each stage keeps its own error type (Cst.Error, Analyser.Error) and knows
//! nothing of this folder. A diagnostic's code is the coproduct of those
//! types, so a tag added to any stage needs a text in messages.zig before the
//! program compiles. A layer's package writes its own codes and texts
//! (`Foreign`), so no layer's meaning is written here (statements.md §29).

const std = @import("std");
const Token = @import("../lex/Token.zig");
const Cst = @import("../parse/Cst.zig");
const Analyser = @import("../analyse/Analyser.zig");
const messages = @import("messages.zig");

const Diagnostic = @This();

code: Code,
severity: Severity,
/// Where the problem is.
span: Span,
/// Where the conflicting thing was first declared, when that helps.
related: ?Span = null,
/// For `expected_token`: the token that was expected.
expected: Token.Tag = .invalid,

pub const Code = union(enum) {
    syntax: Cst.Error.Tag,
    analysis: Analyser.Error.Tag,
    /// A layer's own, defined by its package.
    layer: *const Foreign,

    /// The code's stable name, as `edge_declared_twice`. Names are unique
    /// across stages.
    pub fn name(code: Code) []const u8 {
        return switch (code) {
            .layer => |f| f.name,
            inline else => |tag| @tagName(tag),
        };
    }

    pub fn text(code: Code) messages.Text {
        return switch (code) {
            .syntax => |tag| messages.syntax(tag),
            .analysis => |tag| messages.analysis(tag),
            .layer => |f| f.text,
        };
    }

    /// The severity before any promotion. Syntax errors are all errors.
    pub fn defaultSeverity(code: Code) Severity {
        return switch (code) {
            .syntax => .@"error",
            .analysis => |tag| switch (tag.severity()) {
                .warning => .warning,
                .@"error" => .@"error",
                .unsupported => .unsupported,
            },
            .layer => |f| f.severity,
        };
    }
};

/// A code a layer's package defines: its stable name, unique across stages
/// and layers (`seed_not_a_tiling`), its texts, with the placeholders
/// `write` fills, and its severity before any promotion.
pub const Foreign = struct {
    name: []const u8,
    text: messages.Text,
    severity: Severity,
};

pub const Text = messages.Text;

/// Ordered from least to most severe, so the worst of several is their max.
pub const Severity = enum(u2) {
    /// Not a problem with the program: a construct the compiler does not
    /// implement yet, and skips (spec/statements.md §15). Never promoted,
    /// never part of the program's status, and never in a release build.
    unsupported,
    warning,
    /// A warning that the program's header or the caller made an error.
    promoted,
    @"error",

    pub fn max(a: Severity, b: Severity) Severity {
        return if (@backingInt(a) >= @backingInt(b)) a else b;
    }

    /// Promoted warnings count as errors.
    pub fn isError(s: Severity) bool {
        return s == .promoted or s == .@"error";
    }
};

/// Byte offsets into the source, `start` inclusive, `end` exclusive.
pub const Span = struct {
    start: u32,
    end: u32,

    pub fn text(span: Span, source: []const u8) []const u8 {
        return source[span.start..span.end];
    }
};

pub fn fromSyntax(cst: *const Cst, err: Cst.Error) Diagnostic {
    const code: Code = .{ .syntax = err.tag };
    return .{
        .code = code,
        .severity = code.defaultSeverity(),
        .span = tokenSpan(cst, err.token),
        .expected = err.expected,
    };
}

pub fn fromAnalysis(cst: *const Cst, err: Analyser.Error) Diagnostic {
    const code: Code = .{ .analysis = err.tag };
    return .{
        .code = code,
        .severity = code.defaultSeverity(),
        .span = tokenSpan(cst, err.token),
        .related = if (err.related) |token| tokenSpan(cst, token) else null,
    };
}

/// A layer's diagnostic, at a node of the program (a descriptor, a value),
/// related to another if one helps. Warnings are not promoted here: the
/// caller applies its tolerance.
pub fn fromLayer(cst: *const Cst, code: *const Foreign, at: Cst.Node.Index, related: ?Cst.Node.Index) Diagnostic {
    return .{
        .code = .{ .layer = code },
        .severity = code.severity,
        .span = nodeSpan(cst, at),
        .related = if (related) |r| nodeSpan(cst, r) else null,
    };
}

/// From a node's first token to its last.
pub fn nodeSpan(cst: *const Cst, node: Cst.Node.Index) Span {
    return .{
        .start = cst.tokens.items(.start)[cst.firstToken(node)],
        .end = cst.tokens.items(.end)[cst.lastToken(node)],
    };
}

fn tokenSpan(cst: *const Cst, token: Cst.TokenIndex) Span {
    return .{ .start = cst.tokens.items(.start)[token], .end = cst.tokens.items(.end)[token] };
}

pub fn text(d: Diagnostic) messages.Text {
    return d.code.text();
}

/// Writes one layer of the diagnostic's text (message, explanation or hint),
/// with its placeholders filled in:
///   {}          the text at the span, quoted as code: `f`
///   {expected}  the token that was expected: `)` or "an edge name"
pub fn write(d: Diagnostic, layer: messages.Layer, source: []const u8, w: *std.Io.Writer) std.Io.Writer.Error!void {
    var rest = d.text().get(layer);
    while (std.mem.indexOfScalar(u8, rest, '{')) |open| {
        const close = std.mem.indexOfScalarPos(u8, rest, open, '}') orelse break;
        try w.writeAll(rest[0..open]);
        const key = rest[open + 1 .. close];
        if (key.len == 0) {
            try d.writeSubject(source, w);
        } else if (std.mem.eql(u8, key, "expected")) {
            try w.writeAll(messages.describe(d.expected));
        } else {
            try w.writeAll(rest[open .. close + 1]); // not a placeholder
        }
        rest = rest[close + 1 ..];
    }
    try w.writeAll(rest);
}

/// The text at the span as code, or a plain description where nothing is
/// visible: the end of a line or of the input.
fn writeSubject(d: Diagnostic, source: []const u8, w: *std.Io.Writer) std.Io.Writer.Error!void {
    const t = d.span.text(source);
    if (t.len == 0) return w.writeAll("end of input");
    if (t[0] == '\n' or t[0] == '\r') return w.writeAll("end of line");
    try w.print("`{s}`", .{t});
}

test {
    _ = @import("diagnostic.test.zig");
}
