# fAB

fAB is a language for diagrams: a program declares a graph by its edges, and nodes are where edge ends meet. Its semantics is category theory. Pre-alpha: the language, the CLI and the JSON format change without notice.

## Working here

- **The user writes the code; Claude teaches and reviews.** Claude writes no implementation code unless asked. Claude does write and edit documents: the spec, the decision notes, the grammar and this file. Each plan step is reviewed before the next one starts.
- **The spec leads.** When code and spec disagree, the code changes. When the spec is wrong or unclear, fix the spec first, record the reason in a decision note, then change the code.
- **Equations are open.** The proof layer writes them `==` and `~=`, and these operators are settled. What equations mean is not, so don't redesign them unless asked.
- **No commits** unless the user asks.

## Layout

| Path          | What                                                                          |
| ------------- | ----------------------------------------------------------------------------- |
| `fab-core/`   | Lexer, parser, analyser, IR, styling, diagnostics, JSON. Source in, IR out, no I/O |
| `fab-render/` | Pure backends from the styled IR to bytes (DOT for now)                       |
| `fab-cli/`    | The `fab` command, the only package that does I/O                             |
| `fab-lsp/`, `docs/` | Empty, for later                                                        |
| `examples/`   | `.fab` programs: the spec's Examples section, in the new syntax               |
| `spec/`       | The language: spec, grammar and decision notes                                |

Each package is a plain Zig project that depends only on the ones above it.

**Tests** are separate from the code, beside it: `Lexer.zig` is tested by `lexer.test.zig` (the source's name, snake_case), which the source pulls in with a trailing `test { _ = @import("lexer.test.zig"); }`. Tests go file by file. Files with a logical dependency share one test file, named after their stage (its folder): a file built only by another is tested with it, so `lex.test.zig` covers Lexer and Token, `parse.test.zig` Parser and Cst, `analyse.test.zig` the analyser, `format.test.zig` the style pass. A behaviour can have its own file, as `recovery.test.zig` does. A test file sees only `pub` declarations.

### spec/

| File             | Role                                                                    |
| ---------------- | ----------------------------------------------------------------------- |
| `spec.md`        | The language. **The truth**: where anything else differs, it wins      |
| `grammar.ebnf`   | Go-style EBNF, a permissive superset; the analyser rejects the rest. `~` touching, `_` apart |
| `joining.md`     | Decision note, 1 November: chains, pinches, cycles, undirected edges     |
| `statements.md`  | Decision note, 23 October, superseded in part; §12 lines and the comma, §13 schemas (1 November), §14 operators between chains (2 November) |
| `style.md`       | Style note, 23 October: the full `:style` vocabulary                     |

## Commands

Zig 0.17. Graphviz only for `-e graphviz` to svg, png or pdf.

```
make                # debug build of every package, in dependency order
make test           # all tests; or test-core, test-render, test-cli
make fmt            # zig fmt; fmt-check to verify
fab check x.fab     # diagnostics only
fab show cst x.fab  # a stage of compilation: tokens, cst or ir
fab render x.fab -e graphviz
```

## Pipeline

Lexer → tokens; parser → CST, a permissive superset with error nodes; analyser → IR. Language errors (attachment, references, kinds, arities) belong to the analyser; the parser only builds trees.

## Plan: closing the gap to the spec

The code (written against the 22 October revision) has drifted from the spec (1 November). The plan brings it in line one step at a time. Each step is small enough to review on its own, keeps every package building and the tests green, and is done when its corpus rows pass. It goes vertically: level 1 relations reach a drawing first, then levels, definitions and style. Between milestones, styling may be reduced to kind defaults.

| Step | What                                      | State   |
| ---- | ----------------------------------------- | ------- |
| 0    | Spec cleanup                              | done    |
| 1    | Grammar                                   | done    |
| 2    | Conformance corpus                        | done    |
| 3    | Lexer                                     | done    |
| 4    | Parser and CST                            | next    |
| 5    | Analyser: level 1                         |         |
| 6    | IR, JSON, renderer for level 1; examples  |         |
| 7    | Levels                                    |         |
| 8    | Definitions and values                    |         |
| 9    | Style layer                               |         |
| 10   | Renderer: style, arrows, themes           |         |
| 11   | Proof and place shells                    |         |
| 12   | CLI, README, examples, docs               |         |

Steps 0 and 1 are recorded in `joining.md` and `statements.md` §12–13, and stated in the spec.

### A. The spec as a contract

**2. Conformance corpus.** One test file, `fab-core/src/compile/conformance.test.zig`, shaped like `recovery.test.zig`: a helper, and the cases defined beside it. Each case is a spec snippet and its expected outcome: the diagnostics it reports, by tag (checked at compile time), and the graph it denotes, as `recovery.test.zig`'s IR dump. One case per example line, one per error-table row, named after the spec section. Each case names the plan step that makes it pass; the file's `done` is the last step finished, and later cases are skipped (`error.SkipZigTest`). Step 2 brings the machinery, the accepted programs and the rows whose tags exist; each later step brings its new tags, their messages and their rows. Finishing a step bumps `done`.

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
| Sorts | what a name is: zone, node, edge, attribute, class, value | `Analyser.zig` (rules 0–1) |
| Interfaces | a term's type: its sides, (m, n) ends, or a node; the arity errors | `Interface.zig` (rules 1–2), before elaboration |
| Nodes as types | which node each end lands on | elaboration, with `UnionFind.zig` (rules 3–4) and the label join, `Label.zig` (rule 5) |
| Variables | what a name refers to: binding by first occurrence, scopes | the environment; `Scope.zig` if it grows (rules 0, 6) |

`Analyser.zig` is the driver: statements, recovery, holes, building the IR. `UnionFind.zig`, `Ir.Builder` and `Result` are kept. Recovery behaviours to bring back (the old `recovery.test.zig`, in git before step 4): a failed element becomes a hole and the path stays connected; cascades are silent and their hole points back to the cause; undefined zones become holes; an edge declared twice keeps the first shape; a zone defined twice is drawn, with references to the first; local fixes keep the first kind and the first name; statements with syntax errors are skipped and the rest is analysed.

Also back in step 5: the tests skipped in 4a ("Needs an analysed program"), and `compilation.test.zig`'s out-of-memory test, which fails with `NondeterministicMemoryUsage` without the old analyser: `Lexer.tokenize` grows a `MultiArrayList`, and whether the testing allocator grows it in place depends on what else is allocated.

One rule at a time, in order, each with its corpus rows and its messages in `compile/messages.zig`:

0. **Statements and items.** Declarations hold terms; definitions hold entries and equations. An operation mixing different operators without a group is an error. `|` only in a declaration, a lone literal only in a definition. A declaration's head is a zone (nodes and edges are open). The warning for a chain broken across lines. The Statements error table.
1. **Node terms take a slash.** `#A`, `@`, diagram names, `+f`, `f+`, `*`. A node beside a space is an error. `*` is fresh and private to one end: `*/(f, g)`, `f/* g`, `*/f/*` are errors.
2. **Interfaces.** Every term computes a left and a right side. A space joins one to one; closed branches (a stop, a cycle's right side) are skipped when counting; nothing on a side is an error.
3. **Slash chains.** One edge attaches to the nodes beside it; two or more close a cycle, which exposes its start on the left. `/` distributes over a group. A trailing `/` makes a one-edge chain undirected.
4. **Pinches.** Several branches are declared; a pinched single edge is a reference; `?` and `!` only on groups; one side only for a single edge; the first branch names the pinched nodes.
5. **Where nodes meet.** The label join: at most one name, kinds that agree, reported by the union-find.
6. **Cross-diagram references.** `A.+f`, `A.#X` (must exist), diagram names as nodes (need an `@`).
7. **Canonical references** for every node, as the IR's `canonical`.

Done when every level-1 relations case passes.

**6. IR, JSON and renderer for level 1; examples.**
- The IR carries undirected edges, null nodes split into `&start` and `&end`, and holes; `emit/json.zig` follows it.
- fab-render draws undirected edges without heads, and starts, ends, choices and bars by kind default.
- Every file in `examples/` compiles, and its relations draw; styling may still be reported as not applied.

Done when `fab render` draws every example and the JSON tests pass.

### C. Levels

**7. Levels.**
- The IR's `Cell` generalises from 2-cells to level k, with source and target in level k−1.
- The analyser elaborates `|` levels with the level-1 rules one dimension up. Sides are single named cells; there are no anonymous or undirected cells; cells sit only between parallel cells.
- The renderer keeps its note that Graphviz doesn't draw cells. The two tests skipped since step 3 come back, written with `|`: fab-render's "cells are left out, with one note each" and fab-cli's "notes follow the diagnostics, and never change the exit code".

Done when every level case passes.

### D. Definitions and style

**8. Definitions and values.**
- An environment of names: `[name] :=` values and aliases, `:attr :=` bundles, themes. Each is defined once, before use; built-ins are fixed.
- A bracket is read by its shape (arrow, name, colour, number or range); its type comes from the attribute.
- `!` inside brackets: struck lines, inner hooks and harpoons, inward angles.
- The prelude is ordinary fAB source embedded in fab-core: the base theme, built-in values, named arrows and themes.

**9. Style layer.** `fab-core/src/format/` becomes the style pass, with `style.md` as the reference.
- `:style` replaces `:format`. Blocks are factored subjects. Groups of subjects take attributes distributed over them. Each (subject, attribute) is bound once per layer.
- Classes with `&`, and specificity: class, narrower class, class in a diagram, single element.
- The spec's attribute vocabulary, with type checks and "does not apply" errors.
- Kind defaults, then themes left to right, then the program.
- The arrow parser: `[tail/line/head]`, its glyphs and line words.

**10. Renderer.** fab-render realises the new Style: arrows, ends, `:bend`, `:side`, theme tokens.

Done (8–10) when the styled examples in the spec draw as described.

### E. Shells and docs

**11. Proof and place shells.** `:prove` and `:place` are parsed and checked for placement only: the zone exists, and each layer appears once. Their contents are kept in the tree, unchecked.

**12. CLI, README, examples.**
- `fab show` stages follow the new CST, along with help text and messages.
- The README covers the new syntax, the `:style` layer and the status.
- `examples/` grow to one example per section of the spec.

### Open decisions

| Decision                                                        | Needed by          |
| --------------------------------------------------------------- | ------------------ |
| The prelude's contents                                          | step 8             |
| The header's attributes (`:kind`, strictness, boundary)         | step 7             |
| Column names for emitters: from `:label`, or a schema attribute | when fAB emits SQL |
| Equations: what `==` and `~=` mean                              | later              |
| The place vocabulary                                            | later              |
