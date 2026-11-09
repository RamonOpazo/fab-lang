# tree-sitter-fab

fAB's grammar for [Tree-sitter](https://tree-sitter.github.io), so editors can
colour, fold and select fAB programs. Shallow on purpose: the tokens by sort,
statements and their heads, groups and blocks. `spec/grammar.ebnf` is the
grammar and fab-core's parser owns the structure; chains stay flat here, so
this follows the language cheaply.

- `grammar.js`: the grammar. `src/` is generated from it and committed, as
  editors build the parser from `src/parser.c` with a C compiler.
- `queries/highlights.scm`: the colours, in Helix's and Neovim's capture
  names. Zed's extension (`../editors/zed`) has its own copy, in Zed's names.
- `test/corpus/`: trees; `test/highlight/`: colours.

Unlike fAB, this needs Node and the Tree-sitter CLI. From the repository's
root:

```
make tree-sitter          # install the CLI (once), regenerate src/
make test-tree-sitter     # the tests, then every example and the prelude
```

Part of [fAB](../README.md). Pre-alpha. Licensed under AGPL-3.0-or-later.
