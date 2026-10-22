//! The public API of fab-core: one compilation of one source text.
//!
//! Each stage runs on demand, and only once: asking for the IR runs lexing,
//! parsing and analysis, and asking for the CST afterwards reuses the parse.
//! The compilation owns everything it produces, including a copy of the
//! source, and frees it all in `deinit`.
//!
//! The analyser always produces an IR. Whether an IR with errors is handed
//! out is decided here, by the tolerance, which the caller must state in full:
//! there are no defaults, so leniency is never an accident.
//!
//!   var c = try Compilation.init(gpa, source, .{ .warnings = .warn, .ir = .withhold });
//!   defer c.deinit();
//!   if (try c.ir()) |ir| { ... } else { for (try c.diagnostics()) |d| ... }

const std = @import("std");
const Token = @import("../lex/Token.zig");
const Lexer = @import("../lex/Lexer.zig");
const Cst = @import("../parse/Cst.zig");
const Parser = @import("../parse/Parser.zig");
const Ir = @import("../analyse/Ir.zig");
const Analyser = @import("../analyse/Analyser.zig");
const Sheet = @import("../format/Sheet.zig");
const Formatter = @import("../format/Formatter.zig");
const Diagnostic = @import("Diagnostic.zig");

const Compilation = @This();

gpa: std.mem.Allocator,
/// A copy of the source, owned by the compilation.
source: [:0]const u8,
tolerance: Tolerance,

lexed: ?std.MultiArrayList(Token) = null,
parsed: ?Cst = null,
analysed: ?Analyser.Result = null,
formatted: ?Sheet = null,
/// Syntax diagnostics first, then analysis diagnostics, in source order
/// within each. Complete once analysis has run.
diags: std.ArrayList(Diagnostic) = .empty,

/// How much the caller accepts. Both fields must be given.
pub const Tolerance = struct {
    /// Whether warnings count as errors. Promoted warnings keep their own
    /// severity, `promoted`, so they can be shown apart from errors.
    warnings: enum { warn, promote },
    /// What `ir` returns for a program with errors: nothing, or the
    /// best-effort IR, with holes and issues marking what is wrong.
    ir: enum { withhold, keep },
};

/// The state of the whole program: the worst severity among its diagnostics.
pub const Status = enum {
    ok,
    warning,
    promoted,
    @"error",

    pub fn of(severity: Diagnostic.Severity) Status {
        return switch (severity) {
            .warning => .warning,
            .promoted => .promoted,
            .@"error" => .@"error",
        };
    }

    pub fn join(a: Status, b: Status) Status {
        return if (@backingInt(a) >= @backingInt(b)) a else b;
    }

    /// Whether this status means the program has errors. Promoted warnings
    /// count as errors.
    pub fn isError(s: Status) bool {
        return s == .promoted or s == .@"error";
    }
};

pub fn init(gpa: std.mem.Allocator, source: []const u8, tolerance: Tolerance) error{OutOfMemory}!Compilation {
    const copy = try gpa.allocSentinel(u8, source.len, 0);
    @memcpy(copy, source);
    return .{ .gpa = gpa, .source = copy, .tolerance = tolerance };
}

pub fn deinit(c: *Compilation) void {
    if (c.lexed) |*list| list.deinit(c.gpa);
    if (c.parsed) |*tree| tree.deinit(c.gpa);
    if (c.formatted) |*s| s.deinit();
    if (c.analysed) |*result| result.deinit(c.gpa);
    c.diags.deinit(c.gpa);
    c.gpa.free(c.source);
    c.* = undefined;
}

// ---------------------------------------------------------------------------
// Stages

/// Stage 1: the tokens, ending in `.eof`.
pub fn tokens(c: *Compilation) error{OutOfMemory}!*const std.MultiArrayList(Token) {
    if (c.lexed == null) c.lexed = try Lexer.tokenize(c.gpa, c.source);
    return &c.lexed.?;
}

/// Stage 2: the concrete syntax tree. Its syntax errors become diagnostics.
pub fn cst(c: *Compilation) error{OutOfMemory}!*const Cst {
    if (c.parsed == null) {
        var parsed = try Parser.parse(c.gpa, c.source);
        errdefer parsed.deinit(c.gpa);
        for (parsed.errors) |err| try c.addDiagnostic(.fromSyntax(&parsed, err));
        c.parsed = parsed;
    }
    return &c.parsed.?;
}

/// Stage 3: the IR, or null when the program has errors and the tolerance
/// withholds the IR.
pub fn ir(c: *Compilation) error{OutOfMemory}!?*const Ir {
    const result = try c.analysis();
    if (c.tolerance.ir == .withhold and (try c.status()).isError()) return null;
    return &result.ir;
}

/// Stage 4: the sheet, a resolved Style for every node, edge and zone, or
/// null when `ir` is.
pub fn sheet(c: *Compilation) error{OutOfMemory}!?*const Sheet {
    const graph = try c.ir() orelse return null;
    if (c.formatted == null) c.formatted = try Formatter.format(c.gpa, graph);
    return &c.formatted.?;
}

/// Every diagnostic of the program, from every stage.
pub fn diagnostics(c: *Compilation) error{OutOfMemory}![]const Diagnostic {
    _ = try c.analysis();
    return c.diags.items;
}

/// The worst severity among the program's diagnostics.
pub fn status(c: *Compilation) error{OutOfMemory}!Status {
    var s: Status = .ok;
    for (try c.diagnostics()) |d| s = s.join(.of(d.severity));
    return s;
}

/// The diagnostic an IR issue comes from.
pub fn diagnosticOf(c: *Compilation, issue: Ir.Issue) error{OutOfMemory}!Diagnostic {
    const all = try c.diagnostics();
    return all[try c.diagnosticIndex(issue)];
}

/// The position in `diagnostics()` of the diagnostic an IR issue comes from.
/// Issues count analysis errors only, so syntax diagnostics are skipped.
pub fn diagnosticIndex(c: *Compilation, issue: Ir.Issue) error{OutOfMemory}!usize {
    _ = try c.analysis();
    return c.parsed.?.errors.len + issue.err;
}

fn analysis(c: *Compilation) error{OutOfMemory}!*const Analyser.Result {
    if (c.analysed == null) {
        const tree = try c.cst();
        var result = try Analyser.analyse(c.gpa, tree);
        errdefer result.deinit(c.gpa);
        for (result.errors) |err| try c.addDiagnostic(.fromAnalysis(tree, err));
        c.analysed = result;
    }
    return &c.analysed.?;
}

/// Records a diagnostic, promoting a warning if the tolerance says so.
/// The program's header will be able to promote too, once it has syntax.
fn addDiagnostic(c: *Compilation, d: Diagnostic) error{OutOfMemory}!void {
    var promoted = d;
    if (d.severity == .warning and c.tolerance.warnings == .promote) promoted.severity = .promoted;
    try c.diags.append(c.gpa, promoted);
}

test {
    _ = @import("compilation.test.zig");
}
