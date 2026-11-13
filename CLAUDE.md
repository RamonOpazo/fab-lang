# fAB

fAB is a language for diagrams: a program declares a graph by its edges, and nodes are where edge ends meet. Its semantics is category theory. Pre-alpha: the language, the CLI and the JSON format change without notice.

## Working here

- **The user writes the code; Claude teaches and reviews.** Claude writes no implementation code unless asked. Claude does write and edit documents: the spec, the decision notes, the grammar and this file. Each plan step is reviewed before the next one starts.
- **The spec leads.** When code and spec disagree, the code changes. When the spec is wrong or unclear, fix the spec first, record the reason in a decision note, then change the code.
- **Equations are open.** The proof layer writes them `==` and `~=`, and these operators are settled. What equations mean is not, so don't redesign them unless asked.
- **No commits** unless the user asks. Commits follow Conventional Commits, `type(scope): subject (step N).` (`release.md` §5).

## Layout

| Path          | What                                                                          |
| ------------- | ----------------------------------------------------------------------------- |
| `fab-core/`   | Lexer, parser, analyser, IR, diagnostics, JSON (the analysis alone). Source in, IR out, no I/O. `src/prelude.fab`: the prelude, read before every program (`statements.md` §21) |
| `fab-layer-style/` | The style layer's runtime: the cascade and the Sheet, from fab-core's analysis (`statements.md` §26) |
| `fab-layer-place/` | The place layer's runtime: each diagram's seed, metric and flow, each edge's span and collapse, from fab-core's analysis (`statements.md` §29, `layout.md`); the solver from step β |
| `fab-render/` | Pure backends from the analysis to bytes, calling the layers they need (DOT for now) |
| `fab-cli/`    | The `fab` command, the only package that does I/O                             |
| `fab-lsp/`    | The language server, over fab-core and the layers (step L; the layers since α6) |
| `docs/`       | Empty, for later                                                              |
| `tree-sitter-fab/` | The Tree-sitter grammar, for editors' highlighting: shallow, checked against `examples/` (step T) |
| `editors/`    | Each editor's glue: `helix/`, `zed/`, later `vscode/`, `neovim/`              |
| `examples/`   | `.fab` programs to read and to draw, for users; no test reads them            |
| `spec/`       | The language: spec, grammar and decision notes                                |

Each package is a plain Zig project that depends only on the ones above it. A layer's package (`fab-layer-<name>`) depends on fab-core only; its consumers call it. fAB itself (fab-core, the layers, fab-render, fab-lsp, fab-cli) uses nothing but Zig and its standard library. Only `tree-sitter-fab/` and `editors/` may depend on other toolchains (Node, Rust, the Tree-sitter CLI), since editors need them; nothing in fAB builds or tests through them.

**The conformance corpora are the truth**, one per package, each of what it owns (`statements.md` §26): `fab-core/src/compile/conformance.test.zig`, a program's diagnostics and its graph; `fab-layer-style/src/conformance.test.zig`, its style; `fab-layer-place/src/conformance.test.zig`, its place. What the spec says a program means, checked against the code. `examples/` are illustrations for users, checked to compile and drawn by `make examples`; no test reads them.

**Tests** are separate from the code, beside it: `Lexer.zig` is tested by `lexer.test.zig` (the source's name, snake_case), which the source pulls in with a trailing `test { _ = @import("lexer.test.zig"); }`. Tests go file by file. Files with a logical dependency share one test file, named after their stage (its folder): a file built only by another is tested with it, so `lex.test.zig` covers Lexer and Token, `parse.test.zig` Parser and Cst, `analyse.test.zig` the analyser, `style.test.zig` the style layer (in fab-layer-style). A behaviour can have its own file, as `recovery.test.zig` does. A test file sees only `pub` declarations.

### spec/

| File             | Role                                                                    |
| ---------------- | ----------------------------------------------------------------------- |
| `spec.md`        | The language. **The truth**: where anything else differs, it wins      |
| `grammar.ebnf`   | Go-style EBNF, a permissive superset; the analyser rejects the rest. `~` touching, `_` apart |
| `joining.md`     | Decision note, 1 November: chains, pinches, cycles, undirected edges; §12 sorts, null nodes, kinds on the right, a space reaching one branch (2 November) |
| `statements.md`  | Decision note, 23 October, superseded in part; §12 lines and the comma, §13 schemas (1 November), §14 operators between chains (2 November), §15 reserved and unsupported (2 November), how they are drawn and statements with syntax errors, §16 levels (3 November), identity and undirected sides; §17 restrictions and passes, planned; §18 drawing issues, and Graphviz as a convenience; §19 one attribute per entry; §20 the examples, drawn; §21 types and the prelude; §22 three forms, typed records, the style pass, the proof's shape (5 November); §22.7 the header, the command line, `:strict`; §22.8 declared types, twins (6 November); §22.9 record types; records and bundles checked by structure where used (9 November); §22.10 layers read; §22.11 the cascade: ties, exact numbers, tokens in a diagram's own layer; §22.12 the prelude the only schema, the Sheet of values in rules and elements, renderers declaring what they draw; §22.13 the Sheet in JSON, names without sigils; §22.14 base rules, shared by every diagram; §22.15 a label's three values (10 November); §23 diagrams as nodes, `@` removed, `*` on one side (10 November); §24 kinds as the diagram's own (`G :kind [flow]`), passed down, cases on them (`:>`), flow's vocabulary (10 November); §25 the Sheet as a tree of differences; §26 layers as runtimes: fab-core resolves the language, a layer's package its meaning; the JSON the analysis alone (11 November); §27 the route after the style layer: `:proof`, math by RaTeX as an optional process, docs folded into each step, place in two steps and TikZ before SVG; §28 `!` as a reflection in its type's mirror, colours' complements (13 November); §29 the place layer's vocabulary, its checks split between fab-core and fab-layer-place, a layer's own diagnostics, the layers run by `fab check` and fab-lsp |
| `style.md`       | Style note, 23 October: the full `:style` vocabulary                     |
| `layout.md`      | Layout note, 13 November: `:place` and its solver. The grid (GJH's seed, anchors at vertices, direction 0 west to east, `k!` mirrored in the seed's axis, `:metric`), edges between any two anchors, `[3]` and `[4]`, flow as a direction (`[S]`, `[edge]`, `[normal]`, `[area] := [0/0]`) and growth, children centred (tidy trees), ranks from edges' spans, the heuristic, the integer force superstrate, offsets as blocks, collapse; the solve without sizes, in fab-layer-place |
| `profile.md`     | Performance note, 10 November: method, measurements, findings (F1–F8), goals (G1–G5; hard and soft targets, none blocking yet) and the bench |
| `release.md`     | Decision note, 10 November: stable and dev builds, versions in Zig's style (`0.1.0-dev.N+HASH[.dirty][.incomplete]`), one version written once, advancing below and from 1.0.0, Conventional Commits and the changelog |

## Commands

Zig 0.17. Graphviz only for `-e graphviz` to svg, png or pdf.

```
make                # debug build of every package, in dependency order
make test           # all tests; or test-core, test-layer-style, test-layer-place, test-render, test-lsp, test-cli
make examples       # check every example, then draw it to SVG (Graphviz); `make test examples` for both
make fmt            # zig fmt, and fab fmt on the examples and the prelude; fmt-check to verify
fab check x.fab     # diagnostics only
fab fmt x.fab       # the program in its canonical layout; -w writes it back, --check verifies
fab show cst x.fab  # a stage of compilation: tokens, cst or ir
fab render x.fab -e graphviz
fab lsp             # the language server, over stdio
```

## Pipeline

Lexer → tokens; parser → CST, a permissive superset with error nodes; analyser → IR. Language errors (attachment, references, kinds, arities) belong to the analyser; the parser only builds trees. That is fab-core's analysis, and the JSON's whole content. Then the layers, each in its package and called by its consumer: fab-layer-style, IR → Sheet, which renderers draw; fab-layer-place, IR → Place, which its solver will read (β).

## Plan: closing the gap to the spec

The code (written against the 22 October revision) has drifted from the spec (1 November). The plan brings it in line one step at a time. Each step is small enough to review on its own, keeps every package building and the tests green, and is done when its corpus rows pass. It goes vertically: level 1 relations reach a drawing first, then levels, definitions and style. Between milestones, styling may be reduced to kind defaults.

| Step | What                                      | State   |
| ---- | ----------------------------------------- | ------- |
| 0    | Spec cleanup                              | done    |
| 1    | Grammar                                   | done    |
| 2    | Conformance corpus                        | done    |
| 3    | Lexer                                     | done    |
| 4    | Parser and CST                            | done    |
| 5    | Analyser: level 1                         | done    |
| 6    | IR, JSON, renderer for level 1; examples  | done    |
| 7    | Levels (before 6)                         | done    |
| 8    | Definitions and values                    | done    |
| 9    | Style layer                               | done    |
| L    | Language server (after 9c, before 9d)     | done     |
| T    | Tree-sitter grammar (after L1, before L2) | done    |
| V    | Versions (`release.md`)                   | done    |
| R    | Diagrams as nodes, `@` removed, `*` on one side (`statements.md` §23; before 9e) | done |
| 11   | Kinds and cases (11a–11c3; 11d–11e become η) | done    |
| S    | Layers as packages (`statements.md` §26; after 11c3) | done    |
| α    | fab-layer-place: the vocabulary (`layout.md`) | next    |
| β    | fab-layer-place: the solver, grid and superstrate |         |
| γ    | fab-render: embedding and routing         |         |
| δ    | fab-render: TikZ                          |         |
| ε    | fab-render: SVG                           |         |
| ζ    | Math by RaTeX, an optional process        |         |
| η    | fab-layer-proof: the proof shell, flow's findings, `:pass` |         |
| θ    | fab-layer-style: the proof's result drawn |         |
| ι    | fab-lsp: refinement                       |         |
| κ    | Performance: the bench, F1–F6 (`profile.md`) |         |

0.1.0 is the user's call, some time after κ (`statements.md` §27).

Steps 0 and 1 are recorded in `joining.md` and `statements.md` §12–13, and stated in the spec.

### A. The spec as a contract

**2. Conformance corpus.** One test file, `fab-core/src/compile/conformance.test.zig`, shaped like `recovery.test.zig`: a helper, and the cases defined beside it. Each case is a spec snippet and its expected outcome: the diagnostics it reports, by tag (checked at compile time), and the graph it denotes, as `recovery.test.zig`'s IR dump. One case per example line, one per error-table row, named after the spec section. Each case names the plan step that makes it pass, and within step 5 the analyser's rule; the file's `done` is the last step and rule finished, and later cases are skipped (`error.SkipZigTest`). Unsupported diagnostics are left out of the comparison: the spec never mentions them. Step 2 brings the machinery, the accepted programs and the rows whose tags exist; each later step brings its new tags, their messages and their rows. Finishing a step bumps `done`.

First, the tests follow the convention: the inline tests move out (Lexer and Token → `lex.test.zig`, Parser and Cst → `parse.test.zig`, Ir → `ir.test.zig`), and `analyser.test.zig` becomes `analyse.test.zig`.

Done when the corpus runs, with every case failing or skipped for the right reason.

### B. Level 1, end to end

**3. Lexer** (`fab-core/src/lex/`).
- New tokens: CLASS_ID `&class`, BAR `|`, VAL `[…]` (one opaque token: no whitespace, `[` or `]`).
- Removed: `number`, `range`, `arrow`, `l_brack`, `r_brack`. A digit outside a bracket, or a bracket with a space in it, is `invalid`.
- Edge names lose the hyphen; attribute names keep it (`:label-start`).
- EOL stays a token; the parser decides whether it ends a statement.
- Tags renamed to the grammar's terminals.

Done when the tests cover every terminal and the corpus's lexical cases pass.

**4. Parser and CST** (`fab-core/src/parse/`). Only fab-core drives the plan from here; fab-render and fab-cli are redone later, and their tests may be skipped meanwhile. The analyser is rewritten, not adapted (step 5), so step 4 replaces the parser in place, in increments:

- **4a.** The old analyser goes. A skeleton keeps its interface (`analyse(gpa, cst) → Result`, an empty IR, no errors yet), so fab-core builds. The old analyser tests go with it; tests that need an analysed program are skipped until step 5.
- **4b.** The new CST and the whole parser, one function per grammar rule (recursive descent, no Pratt parser): statements, lines, levels, items, blocks, entries, attributes, operator runs, chains, atoms; the syntax errors, with their corpus rows; `parse.test.zig` in the new syntax.
- **4c.** Recovery.
- **4d.** Kinds on the right (`joining.md` §12): a `?` or `!` touching no atom on its right is a node leaf, as `*` is. The examples, `parse.test.zig` and the corpus move to `f/? +(a, b)`.

The CST:

| Node | Grammar |
| --- | --- |
| `root` | the statements |
| `statement` | `head (:: \| :=) body`; main token the operator |
| `levels`, `items` | two or more, separated by `\|` or `,` |
| `block` | `{ levels }` |
| `entry`, `attr` | `[chain] attr…` or `chain block`; `ATTR_ID [literal]` |
| `operation` | `chain operator chain …`, a flat run; the operators are the tokens between the operands |
| `o_chain`, `c_chain` | two or more, joined by space or by `/`; both flat |
| `prefix`, `postfix`, `juxtafix` | a marker or a trailing `/`; `a.b` |
| `leaf`, `group`, `invalid` | one-token primaries (names, `@`, `*`, `&class`, literals); `( items )`; recovery |

A single element is its own node, never a list of one. An absent child is index 0, `root`, which is never anyone's child.

- One statement node replaces `relations` and `layer`: the head is read once, and the operator decides.
- EOL ends a statement at the top level, even inside `( )`; inside `{ }`, at any depth, it is skipped.
- Items replace `entry`, `attrs`, `attr_block`, `equation`, `card`, `ref` and `interp`.
- `|` only at the top of a right side; inside a group it is a parse error.
- Chains are flat over `/` and space, one function per grammar rule. Operators between chains (`==`, `~=`, later more) share one level and read left to right, so an item is a loop, not a Pratt parser. `*` becomes a node primary, not a marker. `[ … ]` cells go. Classes become `&class`. Literals are primaries, so the analyser can say "value in a declaration".
- One group node, `( items )`, for terms, subjects and propositions alike.
- Touching errors (prefix `/`, an operator touching nothing, a detached dot, a marker touching both sides) stay in the parser: the grammar can't derive them, so they are syntax errors.
- Recovery: an `invalid` node, then skip to the next statement at the top level, or to the next `,` or `}` at the same depth inside braces.

Done when every case parses to the expected tree shape (`fab show cst`) and recovery tests pass.

**5. Analyser: level 1** (`fab-core/src/analyse/`). A fresh analyser on the new CST. Typing is its own pass, so elaboration only meets well-typed terms:

| Concern | Knows | File |
| --- | --- | --- |
| Sorts | what a name is: zone, node, edge, attribute, class, value | `sort.zig`, `terms.zig`, `definitions.zig` (rules 0–1) |
| Interfaces | a term's type: its sides, (m, n) ends, or a node; the arity errors | `interface.zig` (rule 2), before elaboration |
| Nodes as types | which node each end lands on | `elaborate.zig`, with `UnionFind.zig` (rules 3–4) and the label join, `Label.zig` (rule 5) |
| Cells | which side each end of a cell lands on, above level 1 | `cells.zig` (step 7b), no union-find |
| Variables | what a name refers to: binding by first occurrence, scopes | the environment; `Scope.zig` if it grows (rules 0, 6) |

`Analyser.zig` is the driver and the shared state: statements, recovery, holes, building the IR. Every concern is a namespace file (lowercase) of functions over `*Analyser`; only struct files are TitleCase (`Analyser.zig`, `Error.zig`, re-exported as `Analyser.Error`, `UnionFind.zig`). `UnionFind.zig`, `Ir.Builder` and `Result` are kept. Recovery behaviours to bring back (the old `recovery.test.zig`, in git before step 4): a failed element becomes a hole and the path stays connected; cascades are silent and their hole points back to the cause; undefined zones become holes; an edge declared twice keeps the first shape; a zone defined twice is drawn, with references to the first; local fixes keep the first kind and the first name; statements with syntax errors are skipped and the rest is analysed. Since issues (`statements.md` §15.4), a syntax error belongs to its statement by range, up to the next statement; a broken statement draws its placeholder, declares its diagram as broken, and references into it are silent holes. Recovery item by item inside braces is the next large change.

Also back in step 5: the tests skipped in 4a ("Needs an analysed program"), and `compilation.test.zig`'s out-of-memory test, which fails with `NondeterministicMemoryUsage` without the old analyser: `Lexer.tokenize` grows a `MultiArrayList`, and whether the testing allocator grows it in place depends on what else is allocated.

One rule at a time, in order, each with its corpus rows and its messages in `compile/messages.zig`:

0. **Statements and items.** The driver: statements in source order, the zone table, errors with subjects. Declarations hold terms; definitions hold entries and equations, in a head of one of the three forms. An operation mixing different operators without a group is an error. `|` only in a declaration; a value or class only in a definition. A declaration's head is a zone; a node or an edge is *reserved*. The warning for a chain broken across lines. Programs with no meaning yet (`statements.md` §15): `reserved` tags are errors, and `unsupported` is its own severity, which skips levels above the first (until step 7) and definition contents (until steps 8–11), never changes the status, and fails a stable build while any remains (`release.md` §2). The Statements error table.
1. **Sorts: node terms take a slash.** Every term is a node (`#A`, `@`, diagram names, `+f`, `f+`, `*`, `?`, `!`) or edges. A node beside a space is an error, and a pinched single edge beside one has its own (`f? (g, h)`); so is a `/` between two nodes (`#A/#B`, `+g/+f`, `#A/?`). `*` and the kinds by position: `*/f/*`, a lone `*`, `*` inside a chain or a cycle; `?` and `!` only right after a single edge, never on the left (`?(a, b)`, `?/f`, `f/?/g`), never after a group or a reference (`(a, b)/?`, `f?`, `A.f/?`). (`joining.md` §12.)
2. **Interfaces.** Every term computes a left and a right side, as free ends and nodes. A space joins one to one (`f (g, h)`); nothing on a side is an error (`f/* g`). Closed branches (a stop, a cycle's right side, a lone node) are skipped when counting, and a space that reaches one branch of several that way warns (`(f/*, g) h` is `f/*, g h`). The side beside `*` holds exactly one free end (`*/(f, g)`, `*/+(f, g)`). Failed terms are holes, so the spaces beside them report nothing. A slash between two groups (`(f, g)/(h, k)`) is an error, and a slash beside nothing is nothing to join (`(f/*)/g`).
3. **Slash chains.** Elaboration begins: each term elaborates to its ports, the union-find elements on each side, and each class becomes an IR node. One edge attaches to the nodes beside it; two or more close a cycle, which exposes its start on the left. `/` distributes over a group. A trailing `/` makes a one-edge chain undirected, and only a one-edge chain (`f/g/`, `(f, g)/` are errors). Its errors: an edge declared twice, a self-reference outside `f/f`, redundant and vacuous self-attachment, a cycle that does not close, references not declared or forward. Recovery is silent: a failed term is a hole (the edges in it are bound to it), and a join rule 2 rejected is a hole holding both sides, found again from the ports, so no side table is kept. Conflicts merge by force until rule 5 reports them.
4. **Pinches.** A pinch with several branches declares them (pinching declared edges is an error); a pinched single edge is a reference, with one side only (`+f+`); a marker on any other node is an error (`+#A`, `#A?`). A pinch of nothing is an error, and of one end a warning (`+(f, #A)` is `f, #A`). The first branch names the pinched nodes, since the union-find's root is its oldest element.
5. **Where nodes meet.** The label join: at most one name, kinds that agree (the same kind agrees), a named node plain. The union-find finds the conflict; elaboration reports it where the meeting is (the step after a space, the `/`, the marker), with `related` at the older name or kind, and merges anyway, the older winning. A pinch's kind is an element glued in like any other. Null never meets: a reference to a `*` end is an error at the edge's name.
6. **Cross-diagram references.** Each diagram keeps its names once elaborated. `A.+f`, `A.f+`, `A.#X`, `A.@` reach a node of a diagram declared earlier (never itself), shared through the union-find, so A keeps it; the name must exist there. Diagram names as nodes attach at their `@` (none is an error). In relations `.` never reaches an edge (`A.f g`). Boundaries wait for the header (step 7).
7. **Canonical references.** A name is opted into, so a named node (`#A`, `@`) is its name and has no canonical end; any other node, holes and `*` included, is the first end that created it, in reading order (the order elements are made in). A shared node is the creating diagram's, with its end. The errors that use them (non-canonical reference, named node referenced by an end) belong to the style layer, step 9.

Then **issues**: an error with a subject (a hole, an edge, a node) is written to the IR's issues table, so renderers can mark it; the tests that need them come back (`compilation.test.zig`, `json.test.zig`, `format.test.zig`).

Done when every level-1 relations case passes.

**6. IR, JSON and renderer for level 1; examples.**
- The IR carries undirected edges, null nodes and holes; `emit/json.zig` follows it. `&start` and `&end` are derived by the style pass, not stored (`statements.md` §18).
- fab-render draws undirected edges without heads, and starts, ends, choices and bars by kind default.
- Issues are drawn (§15.3, §18): marks on their elements, applied last; each diagram's border in its worst severity; placeholders as a square with ✕; the "unsupported" label. `Compilation.sheet()` hands the style pass one severity per issue; error, warning and unsupported are theme tokens.
- In increments: **6a** the fab-render and fab-cli tests in the new syntax, with the two cell tests back; **6b** drawing issues; **6c** the examples.
- Graphviz is a convenience: correct structure, reasonable looks, no layout tuning. The real renderers are native and TikZ.
- Every file in `examples/` compiles, and its relations draw; styling may still be reported as not applied.

Done when `fab render` draws every example and the JSON tests pass.

### C. Levels

**7. Levels.**
Level k is level 1 one dimension up (`statements.md` §16). Each zone keeps one table of names with their levels, named nodes at level 0; it replaces the zone's `edges` and `names` maps. At level k, sorts read the table: a new name is a k-cell (an edge), a name of level k−1 a side (a named node), any other level an error. Edges and cells are one kind of name, a generator with a level and two sides. Above level 1 every side is named and nothing glues later, so there is no union-find there: each end of a cell is a slot, settled in its own term (a side, an unnamed side, or two names for one side). Done after step 5, before step 6. In increments:

- **7a.** The IR's `Cell` generalises to level k: `level`, and source and target in level k−1 (edges at level 2, cells above); the dump and JSON follow. The table of names. `sort.of` takes the level and the table. The driver checks every level; until 7b their new names only enter the table, and `unsupported_levels` stays, as "checked, not drawn". Rows: not a cell, pinch above level 1, side from the wrong level.
- **7b.** Elaborating cells with rules 2–5: attachment, cycles, distribution, a space landing on a named side (`f/α g/β/h`). Rows: unnamed side, two names for one side, undirected cell, path as a side, a cell declared twice, a level inside a block. `unsupported_levels` goes.
- **7c.** Parallel cells, checked in `graph()` once level 1 is final (a later diagram can merge nodes). A non-parallel cell is kept and marked; a cell whose sides failed is dropped, its error on the zone. The corpus: the level rows and the spec's examples (Nat, Eq, Vc, Vs, Mod).
- **7d.** Identity and undirected sides (`statements.md` §16.3). A side may come from any lower level and stands for its identity, whose source and target are itself; side from the wrong level goes (a name of level k is declared twice), and a named node not made at level 1 is *side not declared*. Cells may lie on undirected edges, parallel when the endpoints agree as an unordered pair, and may be undirected (`f/α/g/`). The IR's `Side` gains `node`, and cells keep their direction. Rows: `#A/f/#A | f/α/#A`, `α/m/f`, a non-parallel identity side, an undirected square, an undirected cell; `undirected_cell`, `cell_on_undirected_edge` and `side_from_wrong_level` go. Nothing is flagged yet: restrictions come with the proof shells.

A flow draws no cells but declares them as any diagram does: there is no "cells in flow mode" error. The header waits until fab-core is complete. fab-render's "cells are left out, with one note each" and fab-cli's "notes follow the diagnostics, and never change the exit code" come back with step 6.

Done when every level case passes.

### D. Definitions and style

**8. Definitions and values** (`statements.md` §21). Types, labels, signatures and named values, checked and kept in an environment the style pass reads in step 9. `subject :attr :=` (the layers, `G.f :arrow`) stays unsupported until steps 9 and 11. In increments:

- **8a. Lexer and parser.** `TYPE_ID` (`:Color`); `[]`; `!` touching an attribute (`:hide!`); the new heads: `:Type :: labels`, `subjects :attr :: type`, `:Type [name] :=`, `:Type := type`; `:Tuple.( … )` as a juxtafix of a type; a record entry keyed by a label (`[ink] [#ddd]`). `parse.test.zig` and the corpus's syntax rows.
- **8b. Values.** `value.zig`, the bracket reader: elements split by `/`, each read by its shape (name or label, colour, number, range, symbol, empty slot), with its `!`. `:Number` is an exact decimal (mantissa and scale), never a float. Rows: uppercase name, negative number, number malformed, value in a term.
- **8c. The environment.** `Env.zig`: types (constructors, aliases, label types), labels (one type each), signatures and named values, defined once and before use; type expressions; types read from shape and from definitions; contracts; tuples matched against lists and unions. Rows: undefined name, defined twice, label in two types, not a type, contract broken.
- **8d. The prelude.** `src/prelude.fab`, embedded, analysed before every program with the same analyser; the program's environment starts as the prelude's, whose entries are marked so no error points into it. Tests: it checks with nothing but its records unsupported, and its label types match what Zig gives meaning to (`Style.Shape`, `Style.As`; `:Line` waits for step 9, since `[triple]` has no `Style.Line` yet). Its definitions stop drawing placeholders (§20).
- **8e. Records.** Bundles (keys are functions; the signature is a flag applying where all its contents apply) and themes (`:Record [x] := { … }`: class subjects, tokens, and function keys with no subject, which bind the diagram the theme is applied to); a token binds a value of its type. "Does not apply" reads the class hierarchy: `&plain`, `&choice`, `&parallel`, `&start`, `&end`, `&hole` and `&canonical` lie inside `&node`. Rows: subject in a bundle, element in a theme, key of the wrong type, value given to a flag, value missing, only a flag inverts, does not apply.

**9. Style layer** (`statements.md` §22). The three forms, typed records, then the style pass, with `style.md` as the vocabulary. In increments:

- **9a. Three forms** (done; `statements.md` §22.1, Implemented). A description is a statement with no operator (`G :style { … }`, `G.f :arrow [epi]`); `G :style := …` is *description written with `:=`*. Inside braces, `:=` names in the record (tokens: `[ink] := [#dddddd]`) and `::` declares in the type being declared. A table's key, `:lemma.[a]`; a context left out only inside a block; the warning *owner described after a part*. The 8e checks move to the new forms; the prelude, examples, corpus and `parse.test.zig` follow.
- **9b. Types** (`statements.md` §22.2–22.3, §22.8). In increments:
  - **9b0. Declared types** (done). `::` introduces a type; aliases go (*type named with `:=`*). Declared types are distinct, literals fit by shape, a typed value fits its type and those including it; repeating a declaration adds to the type. Types spelled like values: a comma is a union (a group inside expressions), `[:A/:B]` a tuple, `[:T]` a list, brackets of type names only (*types and values mixed*, *expression in a bracket*); `:Union`, `:Tuple`, `:List` and `:Table` go: no type takes parameters (*type with parameters*). The lexer: no `(`, `)` or `,` in a bracket. Twins: `T!`, `T` fits `T!`, `!` distributes over a union; *not invertible* replaces *only a flag inverts*. The prelude: `:Length`, `:Angle :: :Number!`, `:Fraction`, `:Head` and `:Hook`, `:Tip`, `:Stroke :: :Line!, :Nil`, `:Arrow :: [:Tip/:Stroke/:Tip]`.
  - **9b1. Nil** (done). A bracket has one element more than its slashes; `[]` is one nil, `[/]` two. `:Nil` built in; nil fits only where a type admits it, and every list. `:None` and `[none]` go; Zig's `none` values stop being labels.
  - **9b2. Record types** (done; `statements.md` §22.9). `:Style :: { … }` declares by descriptors, one descriptor one record type; a type holds values or descriptors, never both (*descriptors on a value type*), and `::` holds no `:=` (*naming in a type*). Records and bundles have no type: each keeps its structure (the record types of its descriptors) and is checked by it where a record type is expected: after a descriptor, under a contract (*does not apply* as written), or where a named record is used (*wrong type*); a bundle's use, *does not apply*. `{}` is a value, fitting any record type. `:Record` goes: themes are `:Style [x] :=`, `:theme :: [:Style]`, `&zone :style :: :Style`. `:Label` admits `:Nil` (the computed name). The prelude's descriptors move into `:Style`.
  - **9b3. Tables** (done). A descriptor declared with a key slot, `&zone :axiom.[] :: :Proposition`, is a table; arity follows the declaration; keys optional; *key not taken*, *key in a declaration*, *key malformed* (a key is one name; `.[]` in a use is an error). Keys in layers wait for 9c, two entries under one key (*binding made twice*) too.
  - **9b4. Value checks** (done). *Empty arrow* (`[//]` where an `:Arrow` goes); `Style.Line` gains `triple`, drawn as three lines (the prelude test covers `:Line`); `[base]` binds every descriptor for every class, nil where the default is nothing or computed, and the signatures admit `:Nil`.

  Moved out: values decoded once (9d, where the Styler reads them); `:prove` and `:place` declared in the prelude (step 11, with `:Proof`, `:Proposition`, `:Place`).
- **9c. Layers read** (`statements.md` §22.10). A new `analyse/layers.zig`; `Result` gains `bindings` (subject, descriptor, key, value node, layer), which 9d reads, and `references` (a use's token → what it names), which the LSP reads. `:prove` and `:place` contents stay unsupported. In increments:
  - **9c1. Contexts and layers** (done). Contexts resolve to subjects in their diagram: a diagram, `G.f`, `G.f+`/`G.+f`, `G.#X`, `G.@`, `&c`/`G.&c`, groups distributing; relative to the owner in a block; top-level descriptors routed to their record type's layer. A layer is open. Errors: *description at an undeclared context*, *undeclared name in diagram*, *another diagram's subject*, *not a subject*, *element has no parts*. Each descriptor is checked once per entry, against its subjects' classes. *unsupported layer* stays on every description until 9d applies it (read, not drawn, as `unsupported_levels` did in 7a).
  - **9c2. Canonical references** (done), inside `graph()` once canonical ends are computed, each error marking its node: *non-canonical reference*, *named node referenced by an end*.
  - **9c3. Per element** (done), with 9c2 in one pass (`layers.check`): *does not apply* for nodes by their kind (`&start`/`&end` by arrivals), the others judged when read; *binding made twice* per (layer, element or class, descriptor, key), a keyless table entry never colliding; a node another diagram made is *another diagram's subject*.
- **9d. The cascade** (`statements.md` §22.4, §22.11). The IR stays descriptive; the Sheet, what renderers read, resolves every element's style. In increments, each keeping every package green:
  - **9d1. The rename** (done). `format/` becomes `style/`, `Formatter` the `Styler`; fab-render and fab-cli follow. No change in behaviour.
  - **9d2. Values decoded once** (done). `decode.zig` reads each value, once it is checked, into a `decoded.Value` (`decoded.zig`): colour, `Decimal`, range, text (unescaped), math (as written but `\$`), label by name, elements (tuples and lists alike; one element is a list only where a list goes), nil, flag on or off, record. Named values are resolved when decoded, into the Env's arena, so the prelude's survive into the program; labels (tokens) stay by name, resolved per diagram in 9d4. Named records (`[base]`, themes) and bundle bodies are `Env.records`, each binding with its classes (null in a bundle: where used; no subject in a theme, `&zone`) and the record's tokens; a diagram's layer is `Result.bindings`, each with its value, and its tokens `Result.tokens`; `:theme` is an ordinary binding, a list of records. Tests: `decode.test.zig`, among them layers in every shape of value, nil only where nil is written.
  - **9d3. The Sheet's shape** (done; `statements.md` §22.12). No typed `Style`: the prelude is the only schema. A style is a list of entries, descriptor and `decoded.Value`, resolved. The Sheet holds *rules*, one per diagram and set of classes present, and *elements*, each naming its rule and holding its own entries (computed label, own bindings, marks); `style(element)` merges them. Descriptors indexed in `:Style`'s order, looked up by name once; reading helpers by type (colour, number, label as a renderer's enum by name). A test checks the names core gives meaning to (`:label`, `:arrow`, `:theme`, `:marks`) are in `:Style`. Built beside the typed tables, which renderers read until 9d5: `style/rules.zig` makes the descriptors, a rule per (zone, classes) holding `[base]` folded by specificity, and each element's rule (a node's classes: `&node`, its kind, `&canonical` when unnamed and not `@`); own entries stay empty until 9d4. `Sheet.View` reads them: `get`, `color`, `number`, `text`, `flag`, and `label(E, d)`, which tells nil from a label `E` lacks. The Sheet borrows the Env.
  - **9d4. The cascade** (done). Rules first, once per (diagram, classes): `[base]`, the diagram's themes left to right (a theme's `:theme` included first), the diagram's class bindings, by specificity (class, narrower class: `&node` < kinds < `&canonical` < `&hole`, ties settled so; class in a diagram). Then each element: computed defaults where its rule leaves nil, its own bindings, then marks. Tokens resolved per diagram to RGBA, one step, a diagram's own layer rebinding them after its themes. `kindDefault` and `builtin` go; the Sheet gains cells. Done when today's drawings come out the same from `[base]`. In `style/cascade.zig`: a diagram's `:theme` is read as any descriptor, below its themes; a bundle binds its body in its place; `:marks []` draws no marks (the element keeps `mark`); the Sheet keeps each diagram's tokens (`sheet.token`) and an arena for what it computes. A node is `&canonical` when unnamed, not `@`, and its label, resolved without `&canonical`, is nil: a mark's `:label ""` keeps it out, `&choice :label []` brings it in. `layers.Binding` carries its descriptor's name and key. The bridge (`Styler.bridge`) translates the Sheet of values into the typed tables, so the examples' layers draw; Graphviz writes no colour its header already sets, the graph's `fontcolor` now among them.
  - **9d5. Renderers and JSON.** In increments:
    - **9d5a. Graphviz reads the Sheet** (done). The old `Style`, the typed tables and the bridge go. fab-render's Graphviz backend declares what it draws (`:label`, `:face`, `:ink`, `:stroke`, `:fill`, `:line`, `:shape`, `:as`, `:caption`, `:arrow`'s line, `:hide`, `:marks`), with its own enums for labels, read by name; colours RGBA from the Sheet, so `Theme.zig` keeps only fonts (bold among them). What it doesn't draw is a note (`descriptor_not_drawn`, `label_not_drawn`, `arrow_ends_not_drawn`), once per diagram and descriptor, and only for what a theme or the program binds: each `Sheet.Entry` carries its layer (computed, base, theme, program, mark), so `[base]` is never reported. `:theme` is no element's style, and rules no element names are pruned. The DOT tests are programs (`:marks []` until 9d5c), one a hand-built IR.
    - **9d5b. JSON version 2** (done; `statements.md` §22.13). Names without sigils (`#A` is `"A"`, `:label` `"label"`, `&node` `"node"`). `"sheet"` beside `"ir"`, null when it is: rules `{zone, classes, style}`, each table's elements `{rule, style, mark}` indexed as the IR's (an element's style only its own entries), tokens `{base, zones}`. A style maps a descriptor to `{layer, value}`; values tagged by shape: nil `null`, a flag a bool, elements an array, `{"text"}`, `{"math"}`, `{"color":"#rrggbbaa"}`, `{"number":"0.85"}`, `{"range":[lo, hi]}`, `{"label","inverted"}`; no record reaches the Sheet. Tests: a sheet indexed as its IR.
    - **9d5c. *unsupported layer* narrowed** (done). `:style` is applied, and what a renderer can't draw it reports as a note, so a style description is no longer unsupported. `:prove` and `:place` still are, until step 11: the tag stays, at their descriptor (`layers.zig`), "Proofs and places are not supported yet", and so does the stable build's refusal. The examples lose the violet frames their styles gave them; an unframed diagram, as `[base]` draws one, shows no name.
    - **9d5d. Base rules** (done; `statements.md` §22.14). The cascade still makes a full rule per (diagram, classes), which the `&canonical` and `:marks` checks read; `share` (replacing `prune`) then splits each used one into its base rule and the differences. A base rule per set of classes, `[base]` with its own tokens, in no diagram; a diagram rule names it as `parent` and holds only what differs, by value or layer, and isn't made when nothing does. `View` reads own, rule, parent. JSON rules gain `"parent"`, `"zone": null` for a base rule, parents first. Tests: an unstyled program's rules are its base rules; a token rebinding and a theme each make a diagram rule; a binding equal to `[base]` kept for its layer.

    Done when every example draws as before and the JSON tests pass at version 2.
- **9e. Examples.** Every example's style resolves to a Sheet (it does: only unsupported proofs and Graphviz notes remain); corpus rows from the spec's styled examples. In increments:
  - **9e1. The Sheet's dump** (done). `Sheet.dump`, in `Ir.dump`'s shape: per zone its style, the tokens it rebinds unlike `[base]`, then its nodes (`n{i}`), edges and cells by name, each listing in `:Style`'s order the entries a theme, the program or a mark gave it, with that layer; `[base]` left out unless `.base` asks (`DumpOptions`, off by default), the computed always, and an element with nothing to show not written. Values as fAB writes them (`decoded.write`, which the decode tests share): `[]` for nil and an empty slot in a list (`[/dashed/>]`), `[box]`, `[#123456]`, `[0.85]`; a flag as its descriptor, `hide` or `hide!`. Conformance cases gain `.sheet`, compared as `.ir`.
  - **9e2. The rows** (done). The spec's six styled examples (the block example with its definitions); a block and its expanded form give the same Sheet; the cascade's rules as the spec states them: themes < classes < elements < marks, a diagram's own tokens, the containers' layers beneath a member's own (R5), a top-level class above a container's. `done` moves to 9e.

**L. Language server** (`fab-lsp/`), moved before the cascade so styles and renders are iterated with it. Depends on fab-core only, and on no library outside Zig's standard one (the project stays independent): JSON-RPC over stdio with `std.json`, message types written by hand; the whole document recompiled on each change. Positions in UTF-16. In increments:
- **L1** (done). The loop and documents; diagnostics (`related` as `relatedInformation`, *unsupported* as information); semantic tokens by sort. fab-lsp is a library without I/O (`Server.handle`: one message in, framed messages out; `Transport` the `Content-Length` framing); `fab lsp` in fab-cli owns the standard streams. Editors in `editors/`: Helix, and Zed through a small Rust extension that starts `fab lsp` from the PATH.
- **L2.** Navigation: go to definition, references, hover, rename. In increments:
  - **L2a** (done). fab-core: `Result.references`, one per name the program uses, its definition included: a span (a token, or a bracket's element: the `solid` in `[/solid/>]`), a sort (zone, node, edge, cell, type, label, value, descriptor), and the definition's site, a token in the program or in the prelude (null for a built-in). In source order, each span once. `Compilation.references()` and `definitionSpan(site)`. A named node keeps its first token as its definition. Classes have no site, and are left out. Layers keep their contexts apart, for the canonical checks.
  - **L2b** (done). Definition, references, document highlight (`navigation.zig`), from the name at the cursor or just before it; uses of one thing share its definition, built-ins their text. The prelude is not a virtual `fab://` document, which editors don't open: `fab lsp` (fab-cli) writes the embedded prelude to `$XDG_CACHE_HOME/fab/prelude-<version>.fab` (or `~/.cache/fab`), byte for byte (`navigation.prelude_file`, `prelude_name`; since S2), and the server points into it (`Server.Options.prelude_uri`), so it always matches the compiler; that file publishes no diagnostics. `Lines.byteOffset` reads positions back.
  - **L2c** (done). Hover (`hover.zig`): one Markdown line by sort, then the defining line. A diagram's size; an edge's ends and a cell's sides, nodes by name, `@`, `*` or canonical end (`+f`, `f+`), with their kind; a descriptor's type, classes and record type; a label's type, a value's; built-ins and the prelude's say so. A reference carries its IR subject (`Reference.subject`), nodes and cells resolved once the graph is built; `Env.writeType` spells types; `Compilation.analysis()` is public.
  - **L2d** (done). Rename and prepare rename (`rename.zig`), every use in the document, other diagrams' included. Refused, with a reason (error -32803): a built-in, the prelude's names, `@`, a name also written where the analyser couldn't read it, a new name spelled for another sort (lexed, or read as a bracket name; `fab.value` is exported), or one already naming its sort: in the same diagram for edges, cells and nodes, anywhere for the rest, the prelude's included.
- **L3.** Completion (`completion.zig`). The context is read from the tokens before the cursor, since a line being typed doesn't parse; the names come from the document's last text with no syntax errors (`Document.last_good`), so a broken line doesn't hide what is declared above it. Each item replaces the name typed, sigil included. In increments:
  - **L3a** (done). The machinery, and names: `G.` a diagram's parts (edges, cells, named nodes, `@`, classes); `#` and edge names, the statement's diagram's; capitals, the diagrams; `&`, the classes; `:T`, and `:` after `::` or `:=`, the types.
  - **L3b** (done). Descriptors applying at a context, by the subjects' classes as the analyser judges them (a node by its kind; a name the last good text lacks, by its sort): the entry's context, else its block's owner, read relative to the owner above (`G :style { #A { :`); a group's, those fitting every subject. Only in a description; a chain, an element's parts, a declaration or a type's block offer none. A layer (`:style`) only at the top level. The detail is the type, or *bundle*.
  - **L3c** (done). Values in an open bracket, read from the text (it lexes as no value): the labels and named values fitting the descriptor's type before it, the whole in the first slot or the slot's own type after a `/` (a tuple's slot, a list's element, through declarations and unions); after `:T [x] :=`, those fitting `:T`; a key (`:lemma.[`) none. In a record's block (`:Style [x] := {`), its type's descriptors, an entry with no subject describing the diagram applied to; in a bundle's, any descriptor, and no subject.
- **L4.** Formatting: a printer from the CST, which keeps the program's meaning, its line breaks and its comments. In increments:
  - **L4a** (done). Comments kept: `Lexer.Comment` (its span, without a `\r`, and the token after it, a line end or the end: a comment runs to its line's end, so at most one comes before any token); `next` leaves it in `comment`, `tokenize` collects them when given a list, and the parser keeps them in `Cst.comments`. The tokens are the same either way.
  - **L4b** (done). The printer, `print.program(gpa, cst, w)` (`fab-core/src/print/`, since `format/` is the style pass until 9d), over the tree's tokens and comments: it changes whitespace only. Touching is meaning, kept as written; apart is one space. Around structure the layout decides: no space before a comma or inside parentheses, one after a comma, around `::`, `:=`, `|`, `==`, `~=`, and inside braces holding something. Line breaks are the author's (gofmt's way), blank lines at most one, one line end at the end. A line is indented by what is open at its start, after its leading closers: four spaces per brace or parenthesis alike, whatever the line begins with (a leading comma included); the examples, the prelude and the spec's code are written so. Comments where they were, at a line's end (one space) or on their own line (indented as code). Syntax errors: not printed. Checked: printing twice changes nothing, and the printed text parses to the same tree (`Cst.dump`) and comments; the prelude and the spec's flowchart, which differ only in their aligned columns.
  - **L4c** (done). Columns aligned, always (one canonical form): the printer lays out lines, then pads each run, consecutive lines of one indentation that a blank line, a comment's own line or another indentation ends. A line's columns, in its first entry at its own depth: the descriptor or block after a context (one column for both; a line of descriptors has none), its `::` or `:=`, its comment. Each is one space after the widest text before it in the run, a comment two; widths in code points. No exception for a long line: a blank line before it starts its own run (`categories.fab`'s `Pr`). The prelude and the examples are written in the printed form, and the prelude's test prints it unchanged.
  - **L4d** (done). `fab fmt x.fab` prints the program formatted; `-w`/`--write` writes it back when it changed, `--check` prints nothing and exits 1 when it isn't formatted; syntax errors are reported, exit 1. `make fmt` and `make fmt-check` cover the examples and the prelude beside the Zig sources. `textDocument/formatting` (`formatting.zig`): one edit replacing the whole document, none when formatted, refused (-32803) while it has syntax errors; the editor's options are ignored.

**T. Tree-sitter** (`tree-sitter-fab/`, `editors/`), after L1 and before L2, so programs are read in colour while styles are iterated. The grammar is shallow, a second reading of `grammar.ebnf` kept cheap to follow: the tokens by sort, statements and their heads, groups, blocks; not the structure of chains, which the analyser owns. `queries/highlights.scm` colours as the semantic tokens do. Checked by `make test-tree-sitter` (its corpus and highlight tests, then every example and the prelude with no `ERROR` node); not in `make test`, and skipped without Node. `src/` is generated and committed, since editors compile `src/parser.c`. Editors: Helix from the local path, Zed by a dev extension reading this repository's subdirectory at a commit (`path`, accepted by Zed 1.27).

**R. Diagrams as nodes** (`statements.md` §23), before 9e, since the git example needs it. In increments, each with its corpus rows:
- **R1. Nothing to join beside a node.** `#X/(*/f)` reports *nothing to join* at the slash, as `g/(*/f)` does.
- **R2. `*` on one side.** The side beside `*` holds at least one free end, all landing on one null element; `*/(f, g)`, `(f, g)/*` accepted; `*/+(f, g)` is `/` between nodes; `*` not on exactly one end becomes *not on one side*.
- **R3. `@` removed.** The lexer reads `@` as invalid; `Zone.own`, `A.@`, `G.@` contexts, *diagram without `@` used as a node*, the label computed as `@` and `&canonical`'s "not `@`" go. A diagram name in relations is one node of the container standing for the diagram (kind `.zone`), made at its first use, glued after; the examples and the corpus follow (`*/( … )` tables).
- **R4. Members.** `Zone.members`, in order, from every diagram name in relations (alone or attached), none from `A.x`; a zone's container is the first that names it. JSON zones gain `"members"`; the format stays version 1 (`release.md` §3).
- **R5. The cascade.** A member's rules: `[base]`, its containers' layers outermost first (themes, tokens, class bindings, `:theme`), then its own; element bindings stay *another diagram's subject*.
- **R6. Graphviz.** Subgraphs nested along the containment tree; a nested cluster writes every attribute, since DOT subgraphs inherit their parent's. A diagram's node is an invisible point inside its cluster, and edges to it stop at the border (`compound=true`, `lhead`/`ltail`), unless the other end is inside; a flat diagram's node is an ordinary node.
- **R7. The rest.** fab-lsp (hover names members and container; completion offers no `@`), tree-sitter, and `examples/git-simple.fab` in its final form.

**V. Versions** (`release.md`). The version worked towards, `0.1.0`, written in fab-core's `build.zig.zon`; fab-core's `build.zig` reads it, asks git for the rest (`dev.N`, the commit, `.dirty`) and gives it to the code through build options, with `.incomplete` when a dev build admits unsupported tags, which a stable build refuses (`statements.md` §22.16); fab-core exports `fab.version`, which the other packages read. Shown by `fab --version`, the server's `serverInfo`, the JSON's `"version"` and generated files' comments. The other three `build.zig.zon` hold the same literal, checked in `make test`. The release procedure, the artifact and the changelog (after 0.1.0) wait for the first release.

### E. Shells and docs

**S. Layers as packages** (`statements.md` §26). fab-core stops at analysis; each layer with a meaning of its own gets a package over it, its runtime. In increments, each keeping every package green:
- **S1. fab-layer-style** (done). `fab-core/src/style/` (the cascade, the Sheet, the Styler, `style.test.zig`) and the corpus's `.sheet` rows (its own `conformance.test.zig`) move to `fab-layer-style/`. `Compilation` loses `sheet()`; `marks()` and `Mark` stay in fab-core, `ZoneMark` goes with the style pass; fab-core exports what the layer reads. The JSON loses `"sheet"`: it is the analysis alone. fab-render's backends call the layer (`style.of`); fab-render and fab-cli depend on it; `make test-layer-style`; the layout table and the dependency order follow. Otherwise no change in behaviour: every Sheet dump and drawing the same.
- **S2. The prelude by version** (done). `fab lsp` writes `prelude-<version>.fab`, the prelude byte for byte; L2b's comment and its shift go.

fab-layer-proof comes with step η: its findings are annotations (classes, issues) style takes as input, its diagnostics in fab-core's shape.

**11. Proof and place shells**, before 10, which waits for the native renderer's plan. Kinds (`statements.md` §24): six labels of `:Kind` (`[flow]`, `[state-machine]`, `[category]`, `[schema]`, `[git]`, `[sequence]`), stated as the diagram's own, `G :kind [flow]`, before its layers (`&zone :kind :: :Kind`, outside every record type). A case, `&zone :kind [flow] :> { … }` (a new token, `:>`), holds what a kind adds: `:Proposition :: { … }` its properties, admitted in its diagrams only (*not admitted by the kind*), and `:Style := { … }` its look, a new Sheet layer `kind` between `base` and `theme`. Cases test only `:kind`, add and never take away, and may share a name. Only `[flow]` gets rules, with its vocabulary (§24.5). Class ids take `-` (`&dead-end`). The tests and examples that write `:prove { :kind … }` move to `G :kind`. The prelude declares `:Proof`, `:Proposition` and `:Place`, and `&zone :prove`, `&zone :place`. `:prove` and `:place` are records of type `:Proof` and `:Place`, checked for placement: the zone exists, and each layer appears once. The proof's shape (`statements.md` §22.5): a diagram presents a theory; `:axiom` states, `:lemma` is checked against the axioms and the lemmas before it; both are tables of propositions with optional keys; `( … )` is `:Proposition`, a record type of properties (`:pushout`, `:card`, `:pk`), where equations stand and the comma means *and*. Contents are kept, their meaning unchecked, except the kind and `:pass` (`statements.md` §17): the kind decides what is drawn and which structures become findings, `&refutable` or `&undecidable`, and passes acknowledge them.

In increments, each with its corpus rows:
- **11a. Tokens** (done). `-` in class ids (`&dead-end`); `:>`, the token `then`, a statement's third operator, at the top level only (a case's head is an entry, its body a block). The analyser reads a case as *unsupported* (`unsupported_case`) until 11c. The grammar, tree-sitter, the printer (spaced and aligned as `::`) and the semantic tokens follow.
- **11b. The kind** (done). `:Kind` and `&zone :kind` in the prelude; `G :kind` read as a diagram's own descriptor (declared outside every record type, no record itself; `layers.zig`), alone or in G's block, before the diagram's layers (*kind stated after a layer*, gone in 11c2), once (*binding made twice*); `[dark]` *wrong type*; in a layer or at a part, *does not apply*; `&zone :kind` *reserved* (the header's). `Result.kinds`, one per diagram, by zone. The tests, the corpus and the examples move from `:prove { :kind … }` to `G :kind`.
- **11c. Cases.** In increments:
  - **11c1. Declarations** (done). `cases.zig` reads `&zone :kind [k] :> { … }` (*case on another descriptor*; items other than `:T :: { descriptors }` and `:T := { … }`, *case item of no form*). `:T :: { … }` is scoped to the kind (`Analyser.case_kind`; `Env.Function.kind`, the same name in other kinds' cases chained through `next` in `Env.cased`; `Env.descriptor(name, kind)` resolves): in a case and outside, or twice in one kind, *defined twice*. A use resolves by its subjects' diagrams' shared kind (`layers.kindOf`; a binding keeps its `function`); a bundle or a named record knows no kind; found only in other kinds, *not admitted by the kind*. The prelude's cases declare `:Proposition`. `:T := { … }` in a case stays `unsupported_case`. Completion skips kind-scoped descriptors.
  - **11c2. The kind's theme, passed down** (done). `:Style := { … }` in a case, an unnamed theme, one per kind (a second, *defined twice*), its descriptors the kind's own included: the first theme of the diagram stating the kind, so it passes down with its layers (R5); a Sheet layer `kind` between `base` and `theme` (the dump and JSON follow). A diagram's kind is its own or its container's, up the chain, known once the program is read: a kind's descriptor in a layer is checked then, with what depends on its function (type, classes, value, binding); *kind stated after a layer* goes; diagnostics sorted by position. `Result.kinds` holds each diagram's kind in effect and where it comes from; hover shows it. The prelude's themes (state machine: round; category: `:shape []`; git: points); `unsupported_case` narrows to `:Proof :=` and `:Place :=` in a case, until 11d. `kind_after_layer` goes; deferred errors take their diagram as subject. The spec's git example, its corpus row and the examples lose `&node :shape [point]`.
  - **11c3. The Sheet as a tree** (`statements.md` §25). In increments:
    - **11c3a. Rules as a tree** (done). `share` makes, per used rule, its chain of steps: class steps inside `[base]` (always made), then layer steps (each theme, the kind's first; the top level's classes; each diagram of the chain), a step that changes nothing not made, shared by sequence (a trie of steps). `Rule` gains `adds` (`class`, `kind`, `theme` by name, `zone`, null for the top level) and loses `zone`; `View` walks the parents; Graphviz's notes read every rule of the chain. Dumps and drawings unchanged. Tests: two flows share `[flow]`'s step, Repo's members share Repo's, `[dark]` shared, classes nest.
    - **11c3b. The JSON** (done). Rules `{parent, adds, style}`; styles grouped by layer; tokens only where they differ from `[base]`; no `"inverted": false`, `"mark": null` or empty style. The examples' JSON measured against 11c2's.
- **11d–11e** became step η.

### F. The route (`statements.md` §27)

Ten steps after the style layer, in order. **Each ends with its documentation and its command line**: what it changes in the README, the examples and `fab`'s flags and help is its last increment. Each starts, as before, with its decision note when it decides something. The layout's design is `layout.md`, being rewritten.

**α. fab-layer-place: the vocabulary** (`layout.md`, `statements.md` §29). fab-core checks what the language says (types from the prelude, contexts, classes, bindings made twice); fab-layer-place what the values mean against the seed and the graph. Offsets wait (`layout.md` §8). In increments, each with its corpus rows:
- **α1. The spec** (done). The spec's Place layer from `layout.md`: the descriptors, their values, what passes down, the error tables of both packages. `statements.md` §29 records the decisions below.
- **α2. The prelude** (done). `:Seed`, `:Step`, `:Ranks :: :Number!`; `:Compass :: [N], [E], [S], [W]`; `:Bearing :: :Number!, :Nil` (an empty slot after a number is its normal); `:Flow :: [:Bearing], :Compass!, [:Compass!/:Compass!]`, with `[edge] := [0]`, `[normal] := [0/]`, `[area] := [0/0]`; `:Place :: { &zone :grid :: :Seed, &zone :metric :: [:Step], &zone :flow :: :Flow, &edge :span :: :Ranks, &edge :collapse :: :Flag }; the pen's `[normal]` becomes `[medium]`, since a name in brackets has one meaning`; `&zone :place :: :Place`. Types reject what the language judges alone (`[N/N/E]`, `[0/N]` *wrong type*; `:span` on a node *does not apply*); what depends on the seed is the layer's.
- **α3. fab-core reads `:place`** (done). `Layer` gains `place`; `:place` stops being *unsupported* (`:prove` stays, until η), read as `:style` is (contexts, descriptions outside the block, class bindings, *binding made twice*); `unsupported_case` narrows to `:Proof :=`, and `[category]`'s case gains `:Place := { :flow [area] }` (the prelude test admits nothing to report, so not before). A diagram's place passes down to its members as its style does (R5), the kind's case first. fab-lsp: completion offers `:place` as a layer, and in a layer's block only its record type's descriptors. The corpus numbers the route's steps from 20 (α is 20; α3 is `{20, 3}`). A token named in a block (`G :place { [ink] := … }`, `G :style { [x] := [1] }`) is read silently when it names nothing a layer uses: left for later.
- **α4. fab-layer-place** (done). The package (`build.zig`, `root.zig`, `make test-layer-place`, after fab-layer-style in the dependency order); `place.of(gpa, c) → ?Place` (`resolve.zig`): per diagram the seed, the metric, the flow resolved (`grid.zig`: a direction is an angle in the lattice's served steps, 45° on `[4]`, 30° on `[3]`, with its primitive vector; numbers along the seed's edges, normals a quarter turn as the numbering turns, `!` and a mirrored seed the mirror in the vertical axis; letters by the page, snapped, a tie to the first in the seed's order of drawing from `[0]`, clockwise on `[n]`, counterclockwise on `[n!]` (`layout.md` §3.3); an area to its edge, its sides e_k and e_k+1, and its lone child's legs), per edge its span and collapse, and the bundles (flagged edges with the same two ends in one diagram, whatever their direction, two or more). Precedence as the cascade's (R5): the defaults `[4]`, `[1]`, `[S]`; along the chain, outermost first, the kind's case where a diagram states its kind, the top level's classes (for the diagram itself), the diagram's classes; then its own bindings, so `&zone` and `&edge` pass down and `G :place { :flow [E] }` stays G's. The flow is read against the seed the layers settle. A value the lattice can't read is passed over until α5 reports it. `Place.dump` and the corpus (`.place` rows, `done = {20, 4}`). **The layer's diagnostics are its own:** `Diagnostic.Code.layer`, a `Foreign` code (name, texts, severity) the layer's package defines, at a node's span (`Diagnostic.fromLayer`), so no layer's meaning is written in fab-core (the same for fab-layer-proof, η); `Place.diagnostics` stays empty until α5. Decoded numbers keep their `!` (`decoded.Number`), which `:span`, `:grid`, `:metric` and directions read.
- **α5. The checks before any search** (done). The layer's codes (`messages.zig`, `Diagnostic.Foreign`), reported once per descriptor, at its value, sorted by position, the rejected value passed over: *seed not a tiling* (`[5]`); *number not whole* (`[3.5]`, `[0.5]`, `:span [1.5]`); *flow of no direction* (`[]`, `[//]`, `[/0]`); *not an area* (`[0/2]`, `[0/1!]`, `[0/0/0]`; read against each seed a class reaches: `[2/0]` is one on `[3]`); *directions that cancel* (`[N/S]`, `[S/S]`); *step of nothing*; *span of nothing* (span 0 stays open, `layout.md` §12); *spans that disagree* (`ranks.zig`: stated spans a union-find with offsets, unstated edges at least 1 but the back edges a depth-first search picks in source order, then Bellman–Ford for a positive cycle over the classes; reported at the last stated span on it, related to the first); *collapse between different ends* and *collapse of a cell's side*, for an edge's own flag only (`&edge :collapse` collapses what it can). `Inputs.cst` gives the spans. `statements.md` §29 and the spec's Places table record the two new codes. The corpus: `done = {20, 5}`; an out-of-memory test.
- **α6. Docs and command line.** `fab show place`; `fab check` and fab-lsp report the layer's diagnostics (**fab-lsp depends on fab-core and the layers**); Graphviz reads the flow, as a convenience (`[S]` `rankdir=TB`, `[E]` `LR`, an area TB); the README; a category example with `:flow [area]`. Named place records (`:Place [x] := { … }`) are left out.

**β. fab-layer-place: the solver.** The integer layout from fab-core's analysis alone, with no sizes: the grid substrate and its heuristic, then the force superstrate. Its result, anchors per node and routes per edge, is what renderers read.

**γ. fab-render: embedding and routing.** From anchors to the page: `:metric` and content sizes, measured through an interface (plain text by embedded glyph widths, Zig std only; math by an estimate until ζ); the routes' geometry; nested diagrams (R6's clusters).

**δ. fab-render: TikZ.** The first native drawing: LaTeX sizes the matrix and typesets the math.

**ε. fab-render: SVG.** fAB's own drawing, from the embedding and the Sheet: arrows, ends, `:bend`, `:side`, theme tokens; a CSS class per rule of the chain (`statements.md` §25). fAB's own renderer declares every descriptor and label of `:Style`, checked against the prelude by a test (§22.12). Done when the styled examples in the spec draw as described.

**ζ. Math by RaTeX.** An optional process the host starts, as Graphviz is: with it, `$…$` labels typeset as LaTeX would, their boxes given to the embedding's measuring interface; without it, drawn as their source text.

**η. fab-layer-proof.** First `:prove` becomes `:proof` everywhere (§27). Then the proof shell (the old 11d): `:Proof` and `&zone :proof` in the prelude; a descriptor with no class is the record's own; propositions read and checked (ill-formed, not admitted by the kind); axioms trusted, lemmas and equations unsupported until checked. Then flow's findings and `:pass` (the old 11e): `&refutable`, `&undecidable` and flow's classes (§24.5) as annotations; `:pass` acknowledges them, a note; a pass matching nothing warns. `make test-layer-proof`; its own corpus.

**θ. fab-layer-style: the proof's result.** Findings reach the style layer as extra classes per element (§26), drawn as issues.

**ι. fab-lsp: refinement.**

**κ. Performance** (`profile.md`). `bench/`, a Zig package over fab-core and fab-render: generated families and a 2,000-line document, in-process medians, exact peak memory through a counting allocator, G1–G3 checked and reported, none blocking; `make bench`. Then the findings, each a measured change: F1 cell references, F2 Graphviz's two scans, F6 `show tokens`, then F3 the cascade's full rules, F4 the union-find's memory, F5 the reference sort. Profiling stays by hand.



### Open decisions

| Decision                                                        | Needed by          |
| --------------------------------------------------------------- | ------------------ |
| The prelude's contents beyond the draft (colours, themes; `[base]`'s sizes proposed in 9b4: `:padding` [0.4] nodes, [1] zones) | step 9 |
| The header's syntax, boundary and further descriptors; the CLI's force flag (settled: command line < header < local, `-H name[=value]`, `:strict`, `:warnings`, `:broken`; `statements.md` §22.7) | after fab-core |
| Restrictions and passes: the kind's findings, `&refutable`, `&undecidable`, `:pass` (`statements.md` §17) | step η |
| Column names for emitters: from `:label`, or a schema attribute | when fAB emits SQL |
| Equations: what `==` and `~=` mean                              | later              |
| The place vocabulary (`layout.md`)                              | step α             |
