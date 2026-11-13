# fab-cli

The `fab` command. The only package that does I/O: it reads files, writes
results and starts Graphviz. Depends on fab-core, fab-layer-place (whose
diagnostics `check` reports, and `show place`), fab-render and fab-lsp.

```
zig build test
zig build run -- render example.fab -e graphviz
```

Part of [fAB](../README.md). Pre-alpha. Licensed under AGPL-3.0-or-later.
