# fab-lsp

fAB's language server, as a library: messages in, messages out, no I/O.
`fab lsp` (fab-cli) runs it over standard input and output. Depends on
fab-core and on Zig's standard library only.

Today (plan step L1): diagnostics on open and change (whole-document sync),
and semantic tokens by sort. Positions are UTF-16.

```
zig build test
```

## Editors

Install `fab` (`make install` at the root), then point the editor at
`fab lsp`.

**Helix**, in `~/.config/helix/languages.toml`:

```toml
[language-server.fab]
command = "fab"
args = ["lsp"]

[[language]]
name = "fab"
scope = "source.fab"
file-types = ["fab"]
comment-token = "//"
indent = { tab-width = 2, unit = "  " }
language-servers = ["fab"]
```

`hx --health fab` checks it. Helix shows the diagnostics (`space d`), but
not semantic tokens: it colours only through Tree-sitter, which fAB has not
got yet.

Part of [fAB](../README.md). Pre-alpha. Licensed under AGPL-3.0-or-later.
