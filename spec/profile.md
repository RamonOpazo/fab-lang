# Profile

Performance note, 10 November. How fast fAB compiles, where the time and the memory go, and the goals it should meet: fast enough to draw while the author types. The measurements are of commit `4b0aaa8` (steps up to 9d5); the goals are to be settled, then each becomes a plan step or a constraint on one.

## 1. Method

**A release build.** A release build refuses to compile while an unsupported tag exists (`statements.md` §15), so the measurements use a copy of the sources outside the repository, with that guard lifted (`if (builtin.mode != .debug)` in `analyse/Error.zig` becomes `if (false)`), built with `zig build -Doptimize=ReleaseFast`. A second copy links libc (`.link_libc = true` on fab-cli's executable), so `fab` allocates with `malloc` and heaptrack can follow it; the first allocates with Zig's `smp_allocator`, straight from `mmap`, which heaptrack cannot see.

**Programs.** Generated, each family at three sizes, ten times apart:

| Family | Program | What it stresses |
| --- | --- | --- |
| chain | `G :: e0 e1 … eN` | edges and nodes, one diagram |
| fan | `G :: +(e0, …, eN)+` | one node pair, many edges |
| squares | `G :: +(a0 b0, c0 d0)+ +(a1 b1, …)+ …` | pinches, joins |
| diagrams | `G0 :: f g h` … one per line | many diagrams |
| cells | `G :: +(f0, g0)+ … \| f0/a0/g0, …` | level 2 |
| styled | a chain, then `G :style { e0 :label "…", e0+ :label "…", … }` | layers, references |
| flowchart | `examples/order-fulfilment.fab` repeated, `Order` renamed `Order0`… | a realistic program |

**Tools.**
- `hyperfine -N` (2.0), end to end, process start included (about 1 ms): mean ± σ, peak RSS, and instructions retired, which are steadier than time and show growth best.
- `perf record -e cpu-clock`, flat. With `kernel.perf_event_paranoid = 2` only software events without call stacks are allowed; `--sort srcline` still names the hot lines, which matters since ReleaseFast inlines most of the analyser into `Analyser.analyse`. Call stacks need `sudo sysctl kernel.perf_event_paranoid=1`.
- `heaptrack --record-only` on the libc copy; `heaptrack_print --merge-backtraces 0`, grouped by the first frame in fAB's own code, since every Zig allocation passes through `Allocator.rawAlloc` and merged backtraces fold into one.

**Machine.** AMD Ryzen 7 5825U, 16 threads; CachyOS, Linux 7.3; Zig 0.17.1.

## 2. Results

Wall time, mean ± σ, ReleaseFast. `parse` is `fab show cst`, `check` the analysis, `+ Sheet` `fab render -f json` (analysis, style pass, JSON), `DOT` `fab render -e graphviz -f dot` (no Graphviz layout).

| Program | KiB | parse | check | + Sheet | DOT | peak RSS | Minstr (+ Sheet) |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| flowchart ×10 | 7 | 0.9 ± 0.1 ms | 1.8 ± 0.4 ms | 2.3 ± 0.3 ms | 2.5 ± 0.7 ms | 13 MiB | 6.4 |
| flowchart ×100 | 76 | 2.6 ± 0.8 ms | 7.7 ± 1.9 ms | 11.5 ± 1.5 ms | 12.1 ± 1.3 ms | 7 MiB | 53 |
| flowchart ×1000 | 766 | 19.9 ± 0.9 ms | 63.6 ± 0.6 ms | 123 ± 9 ms | 273 ± 6 ms | 51 MiB | 514 |
| chain 1k | 4 | 1.1 ms | 2.3 ms | 3.5 ms | 4.2 ms | 10 MiB | 12 |
| chain 10k | 57 | 1.7 ms | 9.1 ms | 20 ms | 66 ms | 15 MiB | 106 |
| chain 100k | 672 | 9.0 ms | 69 ms | 163 ms | **4,921 ms** | 128 MiB | 1,065 |
| fan 100k | 770 | 14 ms | 100 ms | 159 ms | 141 ms | 149 MiB | 668 |
| squares 25k | 762 | 33 ms | 107 ms | 199 ms | **3,767 ms** | 157 MiB | 1,069 |
| diagrams 333 | 4 | 0.9 ms | 2.3 ms | 6.4 ms | 7.5 ms | 9 MiB | 32 |
| diagrams 3,333 | 47 | 2.8 ms | 12 ms | 49 ms | 140 ms | 26 MiB | 309 |
| diagrams 33,333 | 509 | 16 ms | 82 ms | 401 ms | **10,328 ms** | 232 MiB | 3,072 |
| styled 100k | 6,977 | 79 ms | 382 ms | 592 ms | **5,226 ms** | 258 MiB | 3,254 |
| cells 500 | 14 | 1.4 ms | 4.6 ms | 5.6 ms | 5.0 ms | 9 MiB | 21 |
| cells 5k | 170 | 7.5 ms | 27 ms | 44 ms | 68 ms | 22 MiB | 257 |
| cells 50k | 1,947 | 46 ms | **500 ms** | 621 ms | 3,537 ms | 214 MiB | **8,230** |

**Debug builds**, the only ones that compile today, are 15–20 times slower: every example takes 16–20 ms to draw, of which about 15 ms is the prelude, against 1.2 ms in release.

**Graphviz's own layout** (`dot -Tsvg` on fAB's DOT) takes 21 ms for each example, 266 ms for flowchart ×100 and 876 ms for a chain of 1,000 edges: where fAB takes 1–11 ms, Graphviz takes ten to a hundred times more.

## 3. Findings

Parsing, analysis and the style pass are linear, except where noted; the instructions grow tenfold with the input (a chain: 12, 106, 1,065 million). Ordered by impact.

**F1. Cell references are quadratic.** `sortedReferences` (`analyse/Analyser.zig:297`) finds each cell's IR index by scanning `cell_tokens` from the start: 67% of the cells check is that line. Instructions grow 21, 257, 8,230 million: thirty-two times for ten. Cells are made in source order, so the list is sorted by token: a binary search, or a map from token to cell, makes it linear.

**F2. Graphviz is quadratic twice.** `branches()` (`fab-render/src/2dot/root.zig:347`) counts a node's edges by scanning every edge, once per node: O(nodes × edges). The zone loop scans every node, once per diagram, to find its nodes: O(diagrams × nodes). A fan, with two nodes, stays linear (141 ms); a chain, squares and many diagrams take seconds. Both counts can be made once, before writing.

**F3. The cascade makes every diagram's full rules before sharing them.** For 33,333 unstyled diagrams, 60% of the peak heap (153 of 255 MB) is `cascade.emit` writing a full rule per (diagram, classes), which `share` then folds into the same four base rules; `prepareZone` copies `[base]`'s tokens into each diagram (21 MB), and the Sheet keeps them. In time, `foldRecord`, `ruleFor`, `emit` and their appends are a third of the run, and the Sheet is five times the check (401 against 82 ms). A diagram with no themes, bindings or tokens of its own can take its base rules directly, and keep no tokens of its own.

**F4. The union-find holds most of the analyser's memory.** For a chain of 100k edges, 85% of the peak heap (176 of 207 MB, about 1.8 KB per edge) is the union-find: `add` (113 MB), `merge` (50 MB), `edit` (13 MB). Its five lists (`parent`, `classes`, `end_of`, `zone_of`, `log`) grow in the analyser's arena, which can grow only the block it handed out last; growing in turn, each list is copied at every growth and its old buffer abandoned. And `log` records every merge, a whole `Class`, for a rollback that only an open snapshot needs. In a realistic program it is the same: half the peak of flowchart ×1000.

**F5. References are sorted by a block sort.** `sortedReferences` sorts with `std.mem.sort`, stable, by swaps (`mem.swap`, `mem.zig:3944`): about 15% of the styled run. The references are appended nearly in source order already; an unstable sort, or a sort of indices, or none where they arrive in order, would cost little.

**F6. `fab show tokens` is quadratic.** `writeTokens` (`fab-cli/src/command/run.zig:154`) calls `report.locate`, which scans the source from its start, once per token: 6.5 s for 170 KiB. fab-core's `Lines` gives every position in one pass.

**F7. Smaller costs.**
- `Lines.init` decodes the whole source for UTF-16 positions, for JSON: 5–9% of a JSON run.
- The CLI holds the whole output in memory before writing it (23 MB of JSON for 33,333 diagrams).
- `elaborate.closedChain` allocates its ports in the arena per chain: 14 MB of flowchart ×1000's 79 MB.

**F8. Debug is what runs.** Release builds wait for step 11, so `fab lsp` in an editor is a debug build: 16–20 ms per change on an example, where release would take about 1 ms.

## 4. Goals

Each is a target, the measure that checks it, and what it asks of the code. A *hard* target is the limit, a *soft* one where the code should be. **For now no goal blocks:** the bench reports every target it misses, hard ones first, and succeeds. Once fAB's real capabilities are better known (its own renderer above all), the tolerances will be estimated again, and missed hard targets made to fail the bench.

**G1. Linear in the program.** Every stage, from the source to the Sheet and every renderer's output, costs O(n log n) at worst in the program's size. Measured by the bench (§5): ten times the input costs at most about twelve times the time, and twelve times the memory, for every family in §1. Asks: F1, F2, F6 fixed.

**G2. Within a keystroke.** For a document an author edits (up to 2,000 lines, about 100 KiB), the compiler with its Sheet, in release: **hard 5 ms, soft 2 ms**, so a renderer has the rest of a 16 ms frame. Today flowchart ×100 (2,300 lines) takes 11.5 ms. Asks: F3 and F5 at least.

**G3. Memory in proportion.** At peak, beyond the empty program's baseline, per element (node, edge or cell): **hard 400 bytes, soft 150 bytes**. Today about 1.8 KB per edge. Asks: F4 (the union-find's lists out of the arena, the undo log only while a snapshot is open) and F3.

**G4. A fast build to use** (decided: `release.md` §2, `statements.md` §22.16). A dev build admits unsupported constructs in any optimisation mode, marked `incomplete` in its version, so the editor runs an optimised build before step 11 removes the last unsupported tag; a stable build refuses them. No build option asks for it: the source tree decides.

**G5. Layout within the budget.** The native renderer (step 10) lays out within what G2 leaves: under about 10 ms for a diagram of a few hundred nodes, stable across edits (a small change moves little), incremental where the compiler can say what changed. A constraint on step 10's design, not yet a measure.

## 5. The bench

**What it is.** `bench/`, a plain Zig package over fab-core and fab-render, as fab-lsp is over fab-core: a program that measures the compiler as a library, inside its own process, the way the language server runs it on every change. It needs nothing but Zig: no hyperfine, no scripts, no other toolchain.

**What it does.**
1. **Generates** the programs: §1's families at their three sizes, and for G2 a *document* of about 2,000 lines made from the examples, each copy's diagrams renamed apart, so it is realistic and varied.
2. **Times** each stage on each (the Sheet through `Compilation`, and DOT through fab-render), many runs, keeping the median. No process start is measured.
3. **Measures memory exactly:** fab-core is given an allocator that wraps the real one and counts every byte allocated and freed, keeping the peak. The figure is the heap's, the same at every run: no heaptrack, and no RSS.
4. **Checks the goals** and prints a table: each family's growth for G1, the document's time for G2, bytes per element for G3, each against its hard and soft target.

**When it runs.** Only for a stable release, and only when the release asks for it explicitly: never for a dev build, never by default. How a release asks is settled with the release procedure (`release.md` §4). Performance is not a goal of the work towards 0.1.0: the bench, and the findings' fixes, wait until then. Not in `make test`: time depends on the machine and its load.

**Profiling** stays by hand, for finding *where* once the bench says *what*: perf by source line, heaptrack on a build linked with libc, as §1 describes. Helpers for it are optional, and wait.
