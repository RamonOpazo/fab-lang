# editors

Each editor's glue for fAB: its grammar (`../tree-sitter-fab`) and its
language server (`fab lsp`). Outside fAB, so any toolchain an editor needs is
allowed here; nothing in fAB builds or tests through it.

| Editor | Colours (Tree-sitter) | Diagnostics (`fab lsp`) |
| ------ | --------------------- | ----------------------- |
| [Helix](helix/) | yes | yes |
| [Zed](zed/) | yes | waits: needs Rust code, built with rustup |
| VS Code, Neovim | later | later |
