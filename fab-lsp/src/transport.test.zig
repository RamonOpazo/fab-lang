const std = @import("std");
const Io = std.Io;
const Transport = @import("Transport.zig");

const gpa = std.testing.allocator;

test "a message is read after its header" {
    var r: Io.Reader = .fixed("Content-Length: 2\r\n\r\n{}");
    const body = (try Transport.read(gpa, &r)).?;
    defer gpa.free(body);
    try std.testing.expectEqualStrings("{}", body);
    try std.testing.expectEqual(null, try Transport.read(gpa, &r));
}

test "other header fields are skipped, the name's case ignored" {
    var r: Io.Reader = .fixed("Content-Type: application/vscode-jsonrpc\r\ncontent-length: 3\r\n\r\n[1]");
    const body = (try Transport.read(gpa, &r)).?;
    defer gpa.free(body);
    try std.testing.expectEqualStrings("[1]", body);
}

test "messages follow one another" {
    var r: Io.Reader = .fixed("Content-Length: 1\r\n\r\n1Content-Length: 1\r\n\r\n2");
    const a = (try Transport.read(gpa, &r)).?;
    defer gpa.free(a);
    const b = (try Transport.read(gpa, &r)).?;
    defer gpa.free(b);
    try std.testing.expectEqualStrings("1", a);
    try std.testing.expectEqualStrings("2", b);
}

test "a header without a length, or cut short, is bad" {
    var none: Io.Reader = .fixed("Content-Type: x\r\n\r\n{}");
    try std.testing.expectError(error.BadHeader, Transport.read(gpa, &none));
    var cut: Io.Reader = .fixed("Content-Length: 9\r\n\r\n{}");
    try std.testing.expectError(error.BadHeader, Transport.read(gpa, &cut));
    var unended: Io.Reader = .fixed("Content-Length: 2\r\n");
    try std.testing.expectError(error.BadHeader, Transport.read(gpa, &unended));
    var nan: Io.Reader = .fixed("Content-Length: two\r\n\r\n{}");
    try std.testing.expectError(error.BadHeader, Transport.read(gpa, &nan));
}

test "a message is written with its header" {
    var out: Io.Writer.Allocating = .init(gpa);
    defer out.deinit();
    try Transport.write(&out.writer, "{}");
    try std.testing.expectEqualStrings("Content-Length: 2\r\n\r\n{}", out.written());
}
