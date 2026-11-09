//! Tests for decode.zig: values decoded once, as their types expect.

const std = @import("std");
const testing = std.testing;
const Compilation = @import("../compile/Compilation.zig");
const Env = @import("Env.zig");
const decoded = @import("decoded.zig");

const tolerance: Compilation.Tolerance = .{ .warnings = .warn, .ir = .keep };

/// A record as text: one binding per line, `classes descriptor = value`,
/// then its tokens, `[label] := value`.
fn writeRecord(env: *const Env, index: decoded.RecordIndex, w: *std.Io.Writer) !void {
    const r = env.records.items[@backingInt(index)];
    for (r.bindings) |b| {
        if (b.classes) |classes| {
            var it = classes.iterator();
            var first = true;
            while (it.next()) |c| {
                try w.print("{s}&{t}", .{ if (first) "" else ",", c });
                first = false;
            }
        } else try w.writeAll("(where used)");
        try w.print(" {s}", .{b.descriptor});
        if (b.key) |k| try w.print(".[{s}]", .{k});
        try w.writeAll(" = ");
        try decoded.write(b.value, w);
        try w.writeByte('\n');
    }
    for (r.tokens) |t| {
        try w.print("[{s}] := ", .{t.label});
        try decoded.write(t.value, w);
        try w.writeByte('\n');
    }
}

/// The record a named value is, as text.
fn named(c: *Compilation, name: []const u8, w: *std.Io.Writer) !void {
    const env = &(try c.analysis()).env;
    const v = env.values.get(name) orelse return error.TestUnexpectedResult;
    try writeRecord(env, (v.decoded orelse return error.TestUnexpectedResult).record, w);
}

fn expectRecord(source: []const u8, name: []const u8, want: []const u8) !void {
    var c = try Compilation.init(testing.allocator, source, tolerance);
    defer c.deinit();
    var out: std.Io.Writer.Allocating = .init(testing.allocator);
    defer out.deinit();
    try named(&c, name, &out.writer);
    try testing.expectEqualStrings(want, out.written());
}

test "the prelude's themes decode, every binding and token" {
    try expectRecord("", "dark",
        \\&zone :fill = #1e1e1e
        \\[ink] := #dddddd
        \\[soft] := #aaaaaa
        \\[muted] := #888888
        \\
    );
    try expectRecord("", "compact",
        \\&node :padding = 0.2
        \\&zone :padding = 0.5
        \\
    );
    try expectRecord("", "print",
        \\[ink] := #000000
        \\[soft] := #000000
        \\[muted] := #555555
        \\[accent] := #000000
        \\
    );
}

test "[base] decodes with nothing left unread" {
    var c = try Compilation.init(testing.allocator, "", tolerance);
    defer c.deinit();
    var out: std.Io.Writer.Allocating = .init(testing.allocator);
    defer out.deinit();
    try named(&c, "base", &out.writer);
    // One binding per descriptor written in it: 19 for nodes, 11 for the
    // kinds, 18 each for edges and cells, 18 for zones; seven tokens.
    try testing.expectEqual(@as(usize, 19 + 11 + 18 + 18 + 18 + 7), std.mem.count(u8, out.written(), "\n"));
    // Nil only where `[]` is written: a computed default, or nothing.
    for ([_][]const u8{
        "&node :size = 1\n",      "&node :shape = circle\n",        "&node :ink = ink\n",
        "&node :hide = off\n",    "&node :note = \"\"\n",           "&choice :label = \"\"\n",
        "&edge :size = 0.85\n",   "&edge :arrow = [nil/solid/>]\n", "&cell :arrow = nil\n",
        "&zone :theme = []\n",    "&zone :as = cluster\n",          "[ink] := #333333\n",
        "&node :padding = 0.4\n", "&hole :line = dashed\n",         "&canonical :face = italic\n",
    }) |line| if (std.mem.indexOf(u8, out.written(), line) == null) {
        std.debug.print("missing: {s}", .{line});
        return error.TestUnexpectedResult;
    };
}

test "named values are resolved where used; labels stay by name" {
    // [epi] is its tuple, [pink] its colour, [warn] a colour named after
    // another name; [muted] is a token, a label, resolved per diagram.
    try expectRecord(
        \\:Color [warn] := [pink]
        \\:Style [mine] := { &edge :arrow [epi], &node { :fill [warn], :stroke [muted], :shape [box] } }
    , "mine",
        \\&edge :arrow = [nil/solid/>>]
        \\&node :fill = #bf3989
        \\&node :stroke = muted
        \\&node :shape = box
        \\
    );
}

test "a theme's bindings: classes, the diagram applied to, includes, tokens" {
    try expectRecord(
        \\:Style [night] := { :theme [dark], (&choice, &parallel) :ink [accent], [accent] := [#58a6ff], :caption $\mathbb{N}$ }
    , "night",
        \\&zone :theme = [record 1]
        \\&choice,&parallel :ink = accent
        \\&zone :caption = $\mathbb{N}$
        \\[accent] := #58a6ff
        \\
    );
}

test "a bundle's body binds where it is used" {
    var c = try Compilation.init(testing.allocator, ":ref := :shape [round], :fill [muted], :hide!", tolerance);
    defer c.deinit();
    const env = &(try c.analysis()).env;
    var out: std.Io.Writer.Allocating = .init(testing.allocator);
    defer out.deinit();
    try writeRecord(env, env.functions.get(":ref").?.body.?, &out.writer);
    try testing.expectEqualStrings(
        \\(where used) :shape = round
        \\(where used) :fill = muted
        \\(where used) :hide = off
        \\
    , out.written());
}

test "a diagram's layer: each binding's value, and its own tokens" {
    var c = try Compilation.init(testing.allocator,
        \\G :: #A/f/#B
        \\:ref := :shape [round]
        \\G :style { #A :label "a \"b\"", f { :arrow [/dashed/>], :hide }, #B :ref, :theme [dark], [ink] := [#000000] }
        \\G.f :label-at [0.25]
    , tolerance);
    defer c.deinit();
    const result = try c.analysis();
    var out: std.Io.Writer.Allocating = .init(testing.allocator);
    defer out.deinit();
    for (result.bindings) |b| {
        try out.writer.print("{s} = ", .{c.parsed.?.tokenText(c.parsed.?.mainToken(b.attr))});
        try decoded.write(b.value, &out.writer);
        try out.writer.writeByte('\n');
    }
    for (result.tokens) |t| {
        try out.writer.print("zone {d} [{s}] := ", .{ @backingInt(t.zone), t.token.label });
        try decoded.write(t.token.value, &out.writer);
        try out.writer.writeByte('\n');
    }
    // `:theme [dark]` is a list of one, though one element is written.
    try testing.expectEqualStrings(
        \\:label = "a "b""
        \\:arrow = [nil/dashed/>]
        \\:hide = on
        \\:ref = on
        \\:theme = [record 1]
        \\:label-at = 0.25
        \\zone 0 [ink] := #000000
        \\
    , out.written());
}

test "every example's layers decode: nil only where nil is written" {
    const value = @import("value.zig");
    var checked: usize = 0;
    for (@import("examples").all) |example| {
        const name, const source = example;
        var c = try Compilation.init(testing.allocator, source, tolerance);
        defer c.deinit();
        const result = try c.analysis();
        const cst = &c.parsed.?;
        for (result.bindings) |b| {
            checked += 1;
            const body = cst.data(b.attr).node;
            // A flag, or a value with no brackets: text, maths, a record.
            if (body == .root or cst.tag(body) != .leaf or cst.tokenTag(cst.mainToken(body)) != .val) {
                if (b.value != .nil) continue;
            } else {
                var written: std.ArrayList(value.Element) = .empty;
                defer written.deinit(testing.allocator);
                var reader = value.read(cst.tokenText(cst.mainToken(body)));
                while (try reader.next()) |e| try written.append(testing.allocator, e);
                const empty = struct {
                    fn at(es: []const value.Element, i: usize) bool {
                        return es[i].kind == .empty;
                    }
                }.at;
                switch (b.value) {
                    .nil => if (written.items.len == 1 and empty(written.items, 0)) continue,
                    .elements => |es| if (es.len == written.items.len) {
                        for (es, 0..) |e, i| {
                            if (e == .nil and !empty(written.items, i)) break;
                        } else continue;
                    } else if (written.items.len == 1 and written.items[0].kind == .name) {
                        continue; // a named value, decoded against its own definition
                    },
                    else => continue,
                }
            }
            var got: std.Io.Writer.Allocating = .init(testing.allocator);
            defer got.deinit();
            try decoded.write(b.value, &got.writer);
            std.debug.print("{s}: `{s}` decoded as {s}\n", .{ name, cst.tokenText(cst.mainToken(b.attr)), got.written() });
            return error.TestUnexpectedResult;
        }
    }
    try testing.expect(checked > 0);
}
