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

    const g = try b.addZone(.{ .name = try b.addString("G"), .own = null });
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

    const a = try b.addZone(.{ .name = try b.addString("A"), .own = null });
    const n0 = try b.addNode(.{ .kind = .plain, .name = null, .zone = a, .canonical = .{ .edge = @fromBackingInt(@intCast(0)), .side = .dom } });
    const n1 = try b.addNode(.{ .kind = .plain, .name = null, .zone = a, .canonical = .{ .edge = @fromBackingInt(@intCast(0)), .side = .cod } });
    const f = try b.addEdge(.{ .name = try b.addString("f"), .source = n0, .target = n1, .directed = true, .zone = a });
    const g = try b.addEdge(.{ .name = try b.addString("g"), .source = n0, .target = n1, .directed = true, .zone = a });
    const alpha = try b.addCell(.{ .name = try b.addString("α"), .level = 2, .source = @backingInt(f), .target = @backingInt(g), .zone = a });
    const beta = try b.addCell(.{ .name = try b.addString("β"), .level = 2, .source = @backingInt(f), .target = @backingInt(g), .zone = a });
    _ = try b.addCell(.{ .name = try b.addString("m"), .level = 3, .source = @backingInt(alpha), .target = @backingInt(beta), .zone = a });

    const zb = try b.addZone(.{ .name = try b.addString("B"), .own = null });
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
        \\  cell β f => g
        \\  cell m α => β level 3
        \\zone B
        \\  node n2 canon +h
        \\  edge h n2 -> n1
        \\
    );
}

test "a zone with an own node: User :: @ (id T.#UUID7)" {
    var b: Builder = .init(testing.allocator);
    errdefer b.deinit();

    const t = try b.addZone(.{ .name = try b.addString("T"), .own = null });
    const uuid = try b.addNode(.{ .kind = .plain, .name = try b.addString("#UUID7"), .zone = t, .canonical = null });
    const user = try b.addZone(.{ .name = try b.addString("User"), .own = null });
    const at = try b.addNode(.{ .kind = .plain, .name = null, .zone = user, .canonical = null });
    b.zones.items(.own)[@backingInt(user)] = at;
    _ = try b.addEdge(.{ .name = try b.addString("id"), .source = at, .target = uuid, .directed = true, .zone = user });

    var ir = try b.finish();
    defer ir.deinit(testing.allocator);

    try expectDump(ir,
        \\zone T
        \\  node n0 #UUID7
        \\zone User own n1
        \\  node n1
        \\  edge id n1 -> n0
        \\
    );
}
