# Zed

A dev extension: highlighting, brackets and the outline from
`tree-sitter-fab`, and diagnostics from `fab lsp`.

Needs Rust through rustup (Zed builds `src/lib.rs` to WebAssembly,
`wasm32-wasip2`), and `fab` on the PATH: `make install OPTIMIZE=Debug` at the
root until plan step 9d, after which `make install` works.

1. In Zed, `zed: install dev extension`, and pick this directory.
2. Open a `.fab` file. Problems show in `zed: open log`.

The grammar is read from GitHub, at the commit in `extension.toml` (`rev`),
from the repository's `tree-sitter-fab` subdirectory (`path`). After
changing the grammar, push, set `rev` to the new commit, and reinstall. To
try a grammar before pushing, set `repository` to the local clone
(`file:///path/to/fab-lang`) and `rev` to a local commit. If Zed refuses
`path`, the grammar moves to a repository of its own.

Zed's capture names differ from Helix's: `languages/fab/highlights.scm` is
kept in step with `tree-sitter-fab/queries/highlights.scm` by hand.
