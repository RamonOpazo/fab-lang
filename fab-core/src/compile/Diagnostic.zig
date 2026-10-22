//! A problem found in a program, by any stage, in a form that needs only the
//! source to be understood: byte spans instead of token indices.
//!
//! Each stage keeps its own error type (Cst.Error, Analyser.Error) and knows
//! nothing of this folder. A diagnostic's code is the coproduct of those
//! types, so a tag added to any stage needs a text in messages.zig before the
//! program compiles.

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

    /// The code's stable name, as `edge_declared_twice`. Names are unique
    /// across stages.
    pub fn name(code: Code) []const u8 {
        return switch (code) {
            inline else => |tag| @tagName(tag),
        };
    }

    pub fn text(code: Code) messages.Text {
        return switch (code) {
            .syntax => |tag| messages.syntax(tag),
            .analysis => |tag| messages.analysis(tag),
        };
    }

    /// The severity before any promotion. Every code is an error for now.
    pub fn defaultSeverity(code: Code) Severity {
        _ = code;
        return .@"error";
    }
};

/// Ordered from least to most severe, so the worst of several is their max.
pub const Severity = enum(u2) {
    warning,
    /// A warning that the program's header or the caller made an error.
    promoted,
    @"error",

    pub fn max(a: Severity, b: Severity) Severity {
        return if (@backingInt(a) >= @backingInt(b)) a else b;
    }

    /// Promoted warnings count as errors.
    pub fn isError(s: Severity) bool {
        return s != .warning;
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
