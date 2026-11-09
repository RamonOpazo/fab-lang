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
pub const RenameParams = struct { textDocument: DocumentId, position: Position, newName: []const u8 };
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
        renameProvider: struct { prepareProvider: bool = true } = .{},
        completionProvider: struct { triggerCharacters: []const []const u8 = &.{ ".", "#", "&", ":" } } = .{},
    },
    serverInfo: struct { name: []const u8 = "fab", version: []const u8 },
};

pub const SemanticTokens = struct { data: []const u32 };

pub const TextEdit = struct { range: Range, newText: []const u8 };

/// A completion: what is offered, and the text it replaces (the name being
/// typed, its sigil included, so `#`, `&` and `:` are replaced too).
pub const CompletionItem = struct {
    label: []const u8,
    kind: u8,
    detail: ?[]const u8 = null,
    textEdit: TextEdit,

    /// The protocol's kinds used here.
    pub const Kind = struct {
        pub const function: u8 = 3;
        pub const variable: u8 = 6;
        pub const class: u8 = 7;
        pub const module: u8 = 9;
        pub const property: u8 = 10;
        pub const value: u8 = 12;
        pub const @"enum": u8 = 13;
        pub const enum_member: u8 = 20;
    };
};
/// Edits by document URI.
pub const WorkspaceEdit = struct { changes: std.json.ArrayHashMap([]const TextEdit) };
pub const PrepareRename = struct { range: Range, placeholder: []const u8 };

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
    /// A request understood, and refused: a rename that can't be made.
    pub const request_failed: i32 = -32803;
};
