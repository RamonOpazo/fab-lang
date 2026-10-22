//! Tests for Args.zig.

const std = @import("std");
const testing = std.testing;
const Args = @import("Args.zig");
const Command = Args.Command;

fn command(args: []const []const u8) !Command {
    return switch (Args.parse(args)) {
        .command => |c| c,
        else => |other| {
            std.debug.print("expected a command, got {s}\n", .{@tagName(other)});
            return error.TestUnexpectedResult;
        },
    };
}

fn expectUsage(args: []const []const u8, message_part: []const u8) !void {
    switch (Args.parse(args)) {
        .usage => |u| if (std.mem.indexOf(u8, u.message, message_part) == null) {
            std.debug.print("message \"{s}\" lacks \"{s}\"\n", .{ u.message, message_part });
            return error.TestUnexpectedResult;
        },
        else => |other| {
            std.debug.print("expected a usage error, got {s}\n", .{@tagName(other)});
            return error.TestUnexpectedResult;
        },
    }
}

fn expectHint(args: []const []const u8, hint_part: []const u8) !void {
    const u = Args.parse(args).usage;
    const hint = u.hint orelse return error.TestExpectedHint;
    if (std.mem.indexOf(u8, hint, hint_part) == null) {
        std.debug.print("hint \"{s}\" lacks \"{s}\"\n", .{ hint, hint_part });
        return error.TestUnexpectedResult;
    }
}

fn expectEngine(args: []const []const u8, engine: Command.Engine, format: Command.Format) !void {
    const c = try command(args);
    try testing.expectEqual(engine, c.engine);
    try testing.expectEqual(format, c.format);
}

test "render is a command, and a bare file gets a hint" {
    const c = try command(&.{ "render", "order.fab" });
    try testing.expectEqual(Command.Action.render, c.action);
    try testing.expectEqualStrings("order.fab", c.input);
    try testing.expectEqual(@as(?[]const u8, null), c.output);

    try expectUsage(&.{"order.fab"}, "expected a command");
    try expectHint(&.{"order.fab"}, "fab render <file>");
    try expectUsage(&.{"--strict"}, "expected a command first");
}

test "a file may have any name, since the command comes first" {
    try testing.expectEqualStrings("check", (try command(&.{ "render", "check" })).input);
    try testing.expectEqualStrings("render", (try command(&.{ "check", "render" })).input);
}

test "engines and formats: defaults" {
    try expectEngine(&.{ "render", "x.fab" }, .native, .svg);
    try expectEngine(&.{ "render", "x.fab", "-e", "graphviz" }, .graphviz, .svg);
    try expectEngine(&.{ "render", "x.fab", "-e", "latex" }, .latex, .pdf);
}

test "engines and formats: a source format implies its engine" {
    try expectEngine(&.{ "render", "x.fab", "-f", "dot" }, .graphviz, .dot);
    try expectEngine(&.{ "render", "x.fab", "-f", "tex" }, .latex, .tex);
    try expectEngine(&.{ "render", "x.fab", "-o", "out.dot" }, .graphviz, .dot);
    try expectEngine(&.{ "render", "x.fab", "-o", "paper.tex" }, .latex, .tex);
}

test "engines and formats: explicit choices" {
    try expectEngine(&.{ "render", "x.fab", "-e", "graphviz", "-f", "png" }, .graphviz, .png);
    try expectEngine(&.{ "render", "x.fab", "-e", "latex", "-o", "x.pdf" }, .latex, .pdf);
    try expectEngine(&.{ "render", "x.fab", "-e", "graphviz", "-o", "out.pdf" }, .graphviz, .pdf);
    // `-f` wins over the output's extension.
    try expectEngine(&.{ "render", "x.fab", "-o", "out.png", "-f", "svg" }, .native, .svg);
}

test "engines and formats: contradictions and unsupported pairs, with hints" {
    try expectUsage(&.{ "render", "x.fab", "-e", "native", "-f", "dot" }, "native engine can't produce");
    try expectHint(&.{ "render", "x.fab", "-e", "native", "-f", "dot" }, "-e graphviz");
    try expectUsage(&.{ "render", "x.fab", "-e", "latex", "-f", "dot" }, "latex engine can't produce");
    try expectUsage(&.{ "render", "x.fab", "-e", "graphviz", "-f", "tex" }, "graphviz engine can't produce");
    try expectHint(&.{ "render", "x.fab", "-e", "graphviz", "-f", "tex" }, "-e latex");
    try expectUsage(&.{ "render", "x.fab", "-o", "out.png" }, "native engine can't produce");
    try expectHint(&.{ "render", "x.fab", "-o", "out.png" }, "-e graphviz");
    try expectUsage(&.{ "render", "x.fab", "-e", "latex", "-f", "svg" }, "latex engine can't produce");
    try expectHint(&.{ "render", "x.fab", "-e", "latex", "-f", "svg" }, "-e native` or `-e graphviz");
}

test "json comes from fab-core, with no engine" {
    try testing.expectEqual(Command.Format.json, (try command(&.{ "render", "x.fab", "-f", "json" })).format);
    try testing.expectEqual(Command.Format.json, (try command(&.{ "render", "x.fab", "-o", "x.json" })).format);
    try expectUsage(&.{ "render", "x.fab", "-f", "json", "-e", "graphviz" }, "doesn't use an engine");
}

test "check, with options anywhere" {
    const c = try command(&.{ "check", "--strict", "x.fab", "--verbosity", "full", "--no-color", "--watch" });
    try testing.expectEqual(Command.Action.check, c.action);
    try testing.expect(c.strict and c.watch and !c.color);
    try testing.expectEqual(Command.Verbosity.full, c.verbosity);
}

test "show takes a stage" {
    const c = try command(&.{ "show", "tokens", "x.fab", "--json" });
    try testing.expectEqual(Command.Action.show, c.action);
    try testing.expectEqual(Command.Stage.tokens, c.stage);
    try testing.expect(c.json);
}

test "standard input and `--`" {
    try testing.expectEqualStrings("-", (try command(&.{ "show", "ir", "-" })).input);
    try testing.expectEqualStrings("--odd", (try command(&.{ "render", "--", "--odd" })).input);
}

test "help and version" {
    try testing.expect(Args.parse(&.{}) == .help);
    try testing.expect(Args.parse(&.{"--help"}) == .help);
    try testing.expect(Args.parse(&.{"-h"}) == .help);
    try testing.expect(Args.parse(&.{ "render", "x.fab", "--help" }) == .help);
    try testing.expect(Args.parse(&.{"--version"}) == .version);
}

test "every other mistake is reported" {
    try expectUsage(&.{"check"}, "no input file");
    try expectUsage(&.{ "render", "a.fab", "b.fab" }, "only one input");
    try expectUsage(&.{ "render", "x.fab", "--frobnicate" }, "unknown option");
    try expectUsage(&.{ "render", "x.fab", "-o" }, "missing path");
    try expectUsage(&.{ "render", "x.fab", "-f", "gif" }, "unknown format");
    try expectUsage(&.{ "render", "x.fab", "-e", "cairo" }, "unknown engine");
    try expectUsage(&.{ "render", "x.fab", "--verbosity", "loud" }, "unknown verbosity");
    try expectUsage(&.{"show"}, "needs a stage");
    try expectUsage(&.{ "show", "graph", "x.fab" }, "unknown stage");
    try expectUsage(&.{ "check", "x.fab", "-o", "y.svg" }, "`render` only");
    try expectUsage(&.{ "check", "x.fab", "-e", "graphviz" }, "`render` only");
    try expectUsage(&.{ "show", "ir", "x.fab", "--preview" }, "`render` only");
    try expectUsage(&.{ "render", "x.fab", "--json" }, "`show` only");
    try expectUsage(&.{ "check", "-", "--watch" }, "needs a file");
    try expectUsage(&.{ "render", "x.fab", "--preview", "-o", "-" }, "standard output");
    try expectUsage(&.{ "render", "x.fab", "-o", "out.gif" }, "extension");
}
