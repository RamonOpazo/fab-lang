# Zed

A dev extension for highlighting, brackets and the outline (no Rust needed).

1. Commit `tree-sitter-fab`, then set `rev` in [`extension.toml`](extension.toml)
   to that commit. To try it before pushing, set `repository` to the local
   clone: `file:///path/to/fab-lang`.
2. In Zed, `zed: install dev extension`, and pick this directory.
3. Open a `.fab` file. Problems show in `zed: open log`.

The grammar is read from the repository's `tree-sitter-fab` subdirectory
(`path`). If Zed refuses that, the grammar moves to a repository of its own.

Diagnostics from `fab lsp` wait: a Zed extension starts a language server
only through Rust code compiled to WebAssembly, which Zed builds with
rustup.
