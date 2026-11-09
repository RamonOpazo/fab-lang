# Helix

1. Install `fab` so `fab lsp` is on the PATH: `make install` at the root.
   Until plan step 9d, a release build refuses to compile (an unsupported
   construct remains), so install a debug one: `make install OPTIMIZE=Debug`.
2. Append [`languages.toml`](languages.toml) to `~/.config/helix/languages.toml`,
   setting the grammar's `path` to this repository's `tree-sitter-fab`. Its
   `use-grammars` builds only fAB's grammar; Helix ships the others.
3. Build the grammar, and give Helix the queries:

   ```
   mkdir -p ~/.config/helix/runtime/grammars ~/.config/helix/runtime/queries
   hx --grammar build
   ln -s /path/to/fab-lang/tree-sitter-fab/queries ~/.config/helix/runtime/queries/fab
   ```

4. `hx --health fab` should tick the server, the parser and the highlights.

Arch installs Helix as `helix`, not `hx`.

Diagnostics show inline and under `space d`. Helix ignores semantic tokens:
it colours only through Tree-sitter. After changing `grammar.js`, run
`make tree-sitter` and `hx --grammar build` again.
