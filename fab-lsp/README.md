# fab-lsp

fAB's language server, as a library: messages in, messages out, no I/O.
`fab lsp` (fab-cli) runs it over standard input and output. Depends on
fab-core and on Zig's standard library only.

Today (plan steps L1–L2): diagnostics on open and change (whole-document
sync), semantic tokens by sort, go to definition, references, document
highlights, hover, rename, and completion of names (`G.`, `#`, `&`, types) of the descriptors applying where they are written, and of the values fitting a bracket; and formatting, as `fab fmt` does. Positions are UTF-16. A definition in the prelude opens a copy of
it that `fab lsp` writes to `$XDG_CACHE_HOME/fab` (or `~/.cache/fab`).

```
zig build test
```

## Editors

`fab lsp` serves any editor; each one's setup is in [`../editors`](../editors).

Part of [fAB](../README.md). Pre-alpha. Licensed under AGPL-3.0-or-later.
