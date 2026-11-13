# fAB

> **Pre-alpha.** fAB is in active development. The language, the command
> line and the JSON format change without notice, and nothing is stable
> yet. Do not depend on it for anything that matters.

fAB is a language for diagrams. A program describes a graph by its edges;
nodes are where edge ends meet. One line draws a natural transformation:

```
Nat :: +(f, g)+ | f/α/g
```

`fab` compiles a program to a graph IR and draws it. Layers say how: `:style`
how things look, `:place` where they go.

```
Sq :: +(f h, g k)+
Sq :place { :flow [area] }  // drawn upright, as tikz-cd draws a square
```

## The name

fAB is pronounced /fæb/, like the start of "fabulous". The name is
`f : A → B`, a morphism f from A to B: the smallest statement in category
theory, and the first program the language was designed around. Every
diagram in fAB is built by gluing such arrows together.

## Packages

| Package                                        | Role                                                                     |
| ---------------------------------------------- | ------------------------------------------------------------------------ |
| [`fab-core`](fab-core/README.md)               | Lexer, parser, analyser, IR, diagnostics, JSON: the language             |
| [`fab-layer-style`](fab-layer-style/README.md) | The style layer: every element's look, resolved by the cascade           |
| [`fab-layer-place`](fab-layer-place/README.md) | The place layer: each diagram's grid, metric and flow, each edge's span  |
| [`fab-render`](fab-render/README.md)           | Pure backends from the analysis and its layers to bytes (DOT for now)    |
| [`fab-lsp`](fab-lsp/README.md)                 | The language server                                                      |
| [`fab-cli`](fab-cli/README.md)                 | The `fab` command: the only package that does I/O                        |

Each depends only on the ones above it. Each is a plain Zig project and
builds on its own.

## Requirements

- Zig 0.17
- Graphviz, for `-e graphviz` to svg, png or pdf (`-f dot` works without it)

## Build, test, install

```
make              # debug build of every package
make test         # all tests, in dependency order
make install      # tests, then a release build into ~/.local/bin
```

`make install PREFIX=/usr/local` installs system wide. `make help` lists
every target and variable.

## Usage

```
fab render example.fab -e graphviz           # example.svg
fab render example.fab -e graphviz -f png    # example.png
fab render example.fab -f dot -o -           # DOT on standard output
fab render example.fab -f json               # the compilation, as JSON
fab check example.fab                        # diagnostics only
fab show ir example.fab                      # a stage of compilation
fab show place example.fab                   # where things go: grid, flow, spans
fab check example.fab --watch                # again on every save
```

Exit codes: 0 no errors, 1 the program has errors, 2 the command could not
run. `--strict` turns warnings into errors and writes nothing on failure.
`fab --help` has the full reference. More programs are in `examples/`.

## Status

Working: the language core, diagnostics, JSON output, the style layer, the
place layer's vocabulary and checks, the language server, and drawing
through Graphviz. Graphviz reads only the flow's direction, one for the
whole graph, and draws no cells (edges between edges); `fab` says so with a
note.

Planned: fAB's own layout (the place layer's solver), TikZ through LaTeX,
the native SVG engine, the proof layer, `--preview`, `--zone`, and a
WebAssembly build.

## License

Copyright (C) 2026 Ramón Opazo

fAB is free software: you can redistribute it and/or modify it under the
terms of the GNU Affero General Public License as published by the Free
Software Foundation, either version 3 of the License, or (at your option)
any later version. See `LICENSE`.

SPDX-License-Identifier: AGPL-3.0-or-later
