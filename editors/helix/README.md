# Helix

1. Install `fab` (`make install` at the root) so `fab lsp` is on the PATH.
2. Append [`languages.toml`](languages.toml) to `~/.config/helix/languages.toml`,
   setting the grammar's `path` to this repository's `tree-sitter-fab`.
3. Build the grammar, and give Helix the queries:

   ```
   hx --grammar build
   mkdir -p ~/.config/helix/runtime/queries
   ln -s /path/to/fab-lang/tree-sitter-fab/queries ~/.config/helix/runtime/queries/fab
   ```

4. `hx --health fab` should show the server, the grammar and highlights.

Diagnostics show inline and under `space d`. Helix ignores semantic tokens:
it colours only through Tree-sitter. After changing `grammar.js`, run
`make tree-sitter` and `hx --grammar build` again.
