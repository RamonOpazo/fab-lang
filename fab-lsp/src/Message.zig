//! The protocol's messages that fab-lsp reads and writes, written by hand:
//! only the fields used. Parsed with `std.json`, unknown fields ignored, and
//! written with it, null optional fields left out.

const std = @import("std");

/// Any message, before its method says what its params are. A request has
/// an `id` and a `method`; a notification only a `method`.
pub const Envelope = struct {
    id: ?std.json.Value = null,
    method: ?[]const u8 = null,
    params: ?std.json.Value = null,
};

// ---------------------------------------------------------------------------
// Read

pub const TextDocumentItem = struct { uri: []const u8, text: []const u8, version: i64 = 0 };
pub const DocumentId = struct { uri: []const u8 };
pub const VersionedDocumentId = struct { uri: []const u8, version: i64 = 0 };
/// With full sync, a change is the whole new text.
pub const Change = struct { text: []const u8 };

pub const DidOpen = struct { textDocument: TextDocumentItem };
pub const DidChange = struct { textDocument: VersionedDocumentId, contentChanges: []const Change };
pub const DidClose = struct { textDocument: DocumentId };
pub const SemanticTokensParams = struct { textDocument: DocumentId };
/// A place in a document: definition, references, highlights.
pub const PositionParams = struct { textDocument: DocumentId, position: Position };
pub const ReferenceParams = struct {
    textDocument: DocumentId,
    position: Position,
    context: struct { includeDeclaration: bool = true } = .{},
};

// ---------------------------------------------------------------------------
// Written

pub const Position = struct { line: u32, character: u32 };
pub const Range = struct { start: Position, end: Position };
pub const Location = struct { uri: []const u8, range: Range };
pub const Related = struct { location: Location, message: []const u8 };

pub const Diagnostic = struct {
    range: Range,
    severity: u8,
    code: []const u8,
    source: []const u8 = "fab",
    message: []const u8,
    relatedInformation: ?[]const Related = null,
};

/// Where a name is used, in the document: written (its definition) or
/// read.
pub const DocumentHighlight = struct {
    range: Range,
    kind: u8,

    pub const read: u8 = 2;
    pub const write: u8 = 3;
};

pub const PublishDiagnostics = struct {
    uri: []const u8,
    version: ?i64 = null,
    diagnostics: []const Diagnostic,
};

pub const InitializeResult = struct {
    capabilities: struct {
        positionEncoding: []const u8 = "utf-16",
        /// Full: each change sends the whole document.
        textDocumentSync: u8 = 1,
        semanticTokensProvider: struct {
            legend: struct { tokenTypes: []const []const u8, tokenModifiers: []const []const u8 },
            full: bool = true,
        },
        definitionProvider: bool = true,
        referencesProvider: bool = true,
        documentHighlightProvider: bool = true,
        hoverProvider: bool = true,
    },
    serverInfo: struct { name: []const u8 = "fab", version: []const u8 },
};

pub const SemanticTokens = struct { data: []const u32 };

pub const Hover = struct {
    contents: struct { kind: []const u8 = "markdown", value: []const u8 },
    range: ?Range = null,
};

pub const ResponseError = struct { code: i32, message: []const u8 };

/// The protocol's error codes used here.
pub const Code = struct {
    pub const parse_error: i32 = -32700;
    pub const invalid_request: i32 = -32600;
    pub const method_not_found: i32 = -32601;
    pub const invalid_params: i32 = -32602;
    pub const server_not_initialized: i32 = -32002;
};
