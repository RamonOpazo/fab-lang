//! Tests for the IR's dump. IRs are built by hand, apart from the analyser.

const std = @import("std");
const testing = std.testing;
const Ir = @import("Ir.zig");

const Builder = Ir.Builder;

fn expectDump(ir: Ir, expected: []const u8) !void {
    var out: std.Io.Writer.Allocating = .init(testing.allocator);
    defer out.deinit();
    try ir.dump(&out.writer);
    try testing.expectEqualStrings(expected, out.written());
}

test "a decision with an undirected edge: G :: #Valid? (f, g/)" {
    var b: Builder = .init(testing.allocator);
    errdefer b.deinit();

    const g = try b.addZone(.{ .name = try b.addString("G") });
    const f_name = try b.addString("f");
    const g_name = try b.addString("g");
    const n0 = try b.addNode(.{ .kind = .choice, .name = try b.addString("#Valid"), .zone = g, .canonical = null });
    const n1 = try b.addNode(.{ .kind = .plain, .name = null, .zone = g, .canonical = .{ .edge = @fromBackingInt(@intCast(0)), .side = .cod } });
    const n2 = try b.addNode(.{ .kind = .plain, .name = null, .zone = g, .canonical = .{ .edge = @fromBackingInt(@intCast(1)), .side = .cod } });
    _ = try b.addEdge(.{ .name = f_name, .source = n0, .target = n1, .directed = true, .zone = g });
    _ = try b.addEdge(.{ .name = g_name, .source = n0, .target = n2, .directed = false, .zone = g });

    var ir = try b.finish();
    defer ir.deinit(testing.allocator);

    try expectDump(ir,
        \\zone G
        \\  node n0 choice #Valid
        \\  node n1 canon f+
        \\  node n2 canon g+
        \\  edge f n0 -> n1
        \\  edge g n0 -- n2
        \\
    );
}

test "two zones sharing a node, a 2-cell and a 3-cell" {
    // A :: +(f, g)+ | f/(α, β)/g | α/m/β   and   B :: h/A.f+
    var b: Builder = .init(testing.allocator);
    errdefer b.deinit();

    const a = try b.addZone(.{ .name = try b.addString("A") });
    const n0 = try b.addNode(.{ .kind = .plain, .name = null, .zone = a, .canonical = .{ .edge = @fromBackingInt(@intCast(0)), .side = .dom } });
    const n1 = try b.addNode(.{ .kind = .plain, .name = null, .zone = a, .canonical = .{ .edge = @fromBackingInt(@intCast(0)), .side = .cod } });
    const f = try b.addEdge(.{ .name = try b.addString("f"), .source = n0, .target = n1, .directed = true, .zone = a });
    const g = try b.addEdge(.{ .name = try b.addString("g"), .source = n0, .target = n1, .directed = true, .zone = a });
    const alpha = try b.addCell(.{ .name = try b.addString("α"), .level = 2, .source = .{ .edge = f }, .target = .{ .edge = g }, .directed = true, .zone = a });
    const beta = try b.addCell(.{ .name = try b.addString("β"), .level = 2, .source = .{ .edge = f }, .target = .{ .edge = g }, .directed = false, .zone = a });
    _ = try b.addCell(.{ .name = try b.addString("m"), .level = 3, .source = .{ .cell = alpha }, .target = .{ .cell = beta }, .directed = true, .zone = a });
    _ = try b.addCell(.{ .name = try b.addString("ι"), .level = 2, .source = .{ .edge = f }, .target = .{ .node = n0 }, .directed = true, .zone = a });

    const zb = try b.addZone(.{ .name = try b.addString("B") });
    const n2 = try b.addNode(.{ .kind = .plain, .name = null, .zone = zb, .canonical = .{ .edge = @fromBackingInt(@intCast(2)), .side = .dom } });
    _ = try b.addEdge(.{ .name = try b.addString("h"), .source = n2, .target = n1, .directed = true, .zone = zb });

    var ir = try b.finish();
    defer ir.deinit(testing.allocator);

    // n1 belongs to A; B's edge h reaches into it.
    try expectDump(ir,
        \\zone A
        \\  node n0 canon +f
        \\  node n1 canon f+
        \\  edge f n0 -> n1
        \\  edge g n0 -> n1
        \\  cell α f => g
        \\  cell β f == g
        \\  cell m α => β level 3
        \\  cell ι f => n0
        \\zone B
        \\  node n2 canon +h
        \\  edge h n2 -> n1
        \\
    );
}

test "a diagram as a node of another: Db :: T/owns/User" {
    var b: Builder = .init(testing.allocator);
    errdefer b.deinit();

    const t = try b.addZone(.{ .name = try b.addString("T") });
    const user = try b.addZone(.{ .name = try b.addString("User") });
    const db = try b.addZone(.{ .name = try b.addString("Db") });
    const of_t = try b.addNode(.{ .kind = .plain, .name = null, .zone = db, .diagram = t, .canonical = null });
    const of_user = try b.addNode(.{ .kind = .plain, .name = null, .zone = db, .diagram = user, .canonical = null });
    _ = try b.addEdge(.{ .name = try b.addString("owns"), .source = of_t, .target = of_user, .directed = true, .zone = db });

    var ir = try b.finish();
    defer ir.deinit(testing.allocator);

    try expectDump(ir,
        \\zone T
        \\zone User
        \\zone Db
        \\  node n0 diagram T
        \\  node n1 diagram User
        \\  edge owns n0 -> n1
        \\
    );
}
