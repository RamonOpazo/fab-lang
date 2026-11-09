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

`fab lsp` serves any editor; each one's setup is in [`../editors`](../editors).

Part of [fAB](../README.md). Pre-alpha. Licensed under AGPL-3.0-or-later.
