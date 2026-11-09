//! fAB's language server, as a library: messages in, messages out. The
//! standard streams belong to `fab lsp` (fab-cli), which reads each message
//! with `Transport.read`, hands it to `Server.handle`, and flushes.

pub const Server = @import("Server.zig");
pub const Transport = @import("Transport.zig");
pub const Message = @import("Message.zig");
pub const diagnostics = @import("diagnostics.zig");
pub const tokens = @import("tokens.zig");
pub const navigation = @import("navigation.zig");
pub const hover = @import("hover.zig");
pub const rename = @import("rename.zig");

test {
    _ = Server;
    _ = Transport;
    _ = Message;
    _ = diagnostics;
    _ = tokens;
    _ = navigation;
    _ = hover;
    _ = rename;
}
