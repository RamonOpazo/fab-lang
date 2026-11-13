# fAB layout: a grid substrate and an integer superstrate, 2026-11-13

Designed in the sessions of 10 to 13 November 2026. This note is the design of `:place` and its solver: the vocabulary is step α, the solver step β, both in fab-layer-place; renderers embed and draw from γ on (`statements.md` §27). It replaces the draft of 10 November, whose three layers (substrate, heuristic, epistrate) became two parts, and whose ranks became spans; on 13 November the grid became only where nodes sit, edges joining any two of its points. Nothing is implemented yet.

Status words as elsewhere: **Decided**, **Open**, **Rejected**. **Open (proposed)** marks a proposal not yet agreed.

---

## 1. Principles

**Decided.** The design is held to these, and a proposal that breaks one is rejected:

- **General, never per case.** Square and triangular grids, any flow, any growth, any number of children are values of one machinery, never branches of the solver. A kind chooses defaults; it adds no algorithm.
- **Two parts.** A **grid substrate**, where nodes may sit, with its **heuristic**, a first placement; then a **force superstrate**, integer physics that relaxes it.
- **Integers.** Every quantity the solver compares is in ℕ or ℤ. Termination is a theorem about ℕ (§7.6), and two runs give the same layout.
- **Descriptive first.** `:place` states constraints; fab-layer-place resolves them. No descriptor names an algorithm.
- **Two ways to point, one for each job.** Numbers point relative to the seed, and describe areas; letters point absolutely, on the page (§3.3). No descriptor names a layout convention (TD, LR).
- **Extremely fast.** Near-linear per sweep, a few sweeps, a library call (no process), so that the editor can lay out on every keystroke.

## 2. Shape

**Decided.**

| Part | Job | Postcondition |
| --- | --- | --- |
| **Grid substrate** | where nodes may sit | a set of anchors with integer coordinates; mandatory |
| **Ranks** | how far along the flow each node is, from edges' spans | ranks final, before any placement (§5) |
| **Heuristic** | a first placement across the flow: children centred under their parent | every node on an anchor or a half shift (§6.2); colocation allowed |
| **Force superstrate** | relax the placement across the flow | no wall crossed; an equilibrium of the energy |

Pipeline: grid → ranks → dummies and blocks → heuristic → superstrate (repair, then relaxation) → routes. All of it in fab-layer-place, from fab-core's analysis alone; the renderer embeds the result and draws (§10).

**No node is ever placed off an anchor**, in any part, but by a half shift across the flow (§6.2). **No part after the ranks changes a rank.**

## 3. The grid

### 3.1 Lattice and dimension

**Decided.** **A grid is only where nodes sit:** the vertices of a tiling, the anchors, each a node's barycentre when it is placed. **An edge joins any two anchors,** never only the tiling's own edges: a cocone's legs fan out to points no polygon edge reaches. d is 2. **d = 3 is designed for, not built:** ℤ³ projected orthographically onto the page, as an isometric drawing is. A projection P : ℤ³ → ℤ² can send a whole line to one point ((0,0,0) and (1,1,1) under the isometric view), so the walls (§7.2) are checked on P(p), and the coordinate P forgets is depth, the order of drawing. The solver stays two-dimensional either way.

### 3.2 The seed: `:grid`

**Decided.** The grid is constructed as GomJau-Hogg constructs a tiling (Gómez-Jáuregui et al., *J. Struct. Eng.* 2012; *Symmetry* 2021): a **seed polygon**, which fixes the directions, then what repeats it. For now the seed alone, a regular tiling, and **two seeds:**

```
G :place { :grid [4] }      // square; [3] triangular
```

- **Anchors are the tiling's vertices**, as GJH counts them: ℤ² for `[4]`, the triangular lattice for `[3]`.
- **`[6]` is not a seed:** a honeycomb's vertices are the triangular lattice less a third of its points, a restricted `[3]`, which the GJH tail can express if ever needed.
- **The seed rests on an edge, the horizontal top one.** Its vertex 0 is the top edge's first vertex in the order of drawing: `[n]` draws clockwise, so vertex 0 is the top left one and vertex 1 the top right; `[n!]` draws counterclockwise, from the top right.
- The default is `[4]`. Any other seed is an error.

**Open (proposed): the GJH tail,** `:symmetry`, for k-uniform grids: the transforms (translation, mirror, rotation, glide) that repeat a patch of polygons around the seed. Written in lowercase labels.

### 3.3 Directions

**Decided.** Directions are hard to convey, so there are two systems, each for one job: **numbers** point relative to the seed, and describe areas; **letters** point on the page, absolutely.

**Numbers: the seed's edges.**

- **`[k]` runs along edge k,** from vertex k to vertex k + 1, in the seed's order of drawing, **modulo n**: on `[4]`, `[5]` is `[1]`. **`[0]` is west to east on every seed,** since the top edge is horizontal and drawn from its left vertex. `[4]`: 0 east, 1 south, 2 west, 3 north. `[3]`: 0 east, 1 south-west, 2 north-west.
- **`[k!]` is direction k of the mirrored seed** (`!` is a reflection, `statements.md` §28; a direction's mirror is the seed's vertical axis). On `[4]`, `[0!]` is west and `[1!]` south, on the axis; on `[3]`, `0!`, `1!`, `2!` are the other three of its six neighbours.
- **`[k/]` is the normal to edge k:** perpendicular, turned clockwise as the numbering is. `[0/]` is south on every seed; `[1/]` on `[4]` is west. A quarter turn takes a direction of either lattice to another of it, so a normal always falls on the grid.
- **Two directions of one edge k are an area** (§4): each `[k]`, `[k/]` or `[k+1]`, the first a number or normal of k. A number followed by an empty slot is a normal, so `[0//0/]` is two normals of 0, `[0//1]` a normal then a number. No other pair of numbers is a direction.

**Letters: the page.**

- `[N]`, `[E]`, `[S]`, `[W]` are the page's directions, **the same whatever the seed**; only their tie to the numbers is fixed, `[E]` and `[0]` being one direction. They are symbols, as the heads `[X]` and `[O]` are: a glyph with one capital.
- **Two adjacent letters are the direction between them:** `[N/E]`, `[S/W]`. A pair that cancels (`[N/S]`) and a word of more than two letters (`[N/N/E]`) are rejected.
- `[E!]` is `[W]`; `[N!]` is `[N]`, on the axis.
- Letters and numbers never mix in one word.

**Directions the lattice serves.** A flow needs ranks that are lattice lines with integer ranks, and each rank's anchors offset from the last by 0 or half a step: then a node's children fall evenly (§6.2). On `[4]` eight directions do so (the four letters and the diagonals), on `[3]` twelve (every 30°). Every number and normal is among them. A letter that is not (`[N/E]` on `[3]`, at 45°) **snaps** to the nearest that is, a tie going to the first in the seed's order of drawing from `[0]`: clockwise on `[n]`, counterclockwise on `[n!]` (`[N/E]` is 300° on `[3]`, 330° on `[3!]`).

### 3.4 The metric: `:metric`

**Decided.** Steps are computed: adjacent anchors are one step apart, whatever their distance on the page. The metric says only how long steps are drawn, and is read by the embedding, never by the solver. **It is also the angle:** the canonical structure is 90° between a node's two branches and 45° from the flow to each, on `[4]` (60° and 30° on `[3]`); a metric that lengthens the steps across the flow against those along it opens the branches wider on the page, while the solver still counts every step as one.

```
G :place { :metric [1/2/3!] }   // 1 2 3 2 1 2 3 …
```

- A metric is a sequence of steps that repeats: `[1/2/3]` is 1 2 3 1 2 3 ….
- **`!` on a step turns the sequence around there:** it reads back, the step not repeated. `[1/2/3!]` is 1 2 3 2 1 2 3 …; `[1/1!]` and `[1]` are the regular grid.
- **Steps are relative,** multiples of a base step that content can widen, as a TikZ matrix sizes its columns: a label never overflows its step.
- **Open:** whether each axis may take its own metric (a table, `:metric.[k]` keyed by direction), or one metric serves every axis.

### 3.5 The quadratic form

**Decided.** The substrate gives the solver an integer quadratic form Q, the squared length of a vector in steps:

| Grid | Q |
| --- | --- |
| `[4]` | a² + b² |
| `[3]` | a² − ab + b² |
| a GJH grid of mixed polygons (the tail) | the translation lattice's form, plus a fixed integer cost per step inside the motif |

On the regular lattices Q is exact. A mixed grid's lengths involve √3, which no integer form holds; there Q is the computed length, by definition. Irrational lengths appear only in the embedding, which uses floats and belongs to the renderer.

## 4. Flow and growth

**Decided.** The flow is an integer linear form f on the lattice: the rank of an anchor p is f(p), and its position across the flow a second form g. The solver sees only f, g and Q, so every grid and every flow is the same computation. A flow is one of:

| Written | Is | Growth |
| --- | --- | --- |
| a number, `[1]`, or a normal, `[0/]` | that direction of the seed (§3.3) | **along it**: f = B(·, e), B the bilinear form of Q, e the direction's lattice vector, so f is integer |
| a letter or two, `[S]`, `[N/E]` | that page direction, snapped if need be (§3.3) | along it, likewise |
| two directions of edge k: `[0/0]`, `[0/1]`, `[0//0/]`, `[0//0]` | the area between edges k and k + 1 | **across the area**: f(e_k) = f(e_k+1) = 1, both edges one rank |

and three named values, the same on every seed: **`[edge] := [0]`**, **`[normal] := [0/]`**, **`[area] := [0/0]`**. The default is `[S]`.

- **Along a direction, a commuting square is a diamond:** on `[4]` with `:flow [1]`, A→B, A→C, B→D, C→D have ranks 0, 1, 1, 2, B and C beside each other across the flow.
- **Across an area, it is a square:** with `:flow [area]` on `[4]`, f = x + y, and the same square is drawn upright, its composite A→D along the bisector, as tikz-cd draws it. The same on every seed.
- **An area's two directions say where a lone child goes.** A bisector spans two ranks, so a node with one child cannot continue straight along it; the child goes along the first direction, then the second, and so on down a chain. The area is always the one of edge k, between e_k and e_k+1; the normal of k lies in it (on `[4]` it is e_k+1, on `[3]` inside). So, in the area of edge 0 on `[4]`: `[0/0]` keeps a chain on edge 0, straight east, as tikz-cd draws a chain; `[0//0/]` keeps it on the normal, straight south; `[0/1]` and `[0/0/]` alternate east and south, a stair; `[0//0]` alternates south and east. A node's first child, in source order, is its left branch, along e_k; with two, the second goes along e_k+1.
- **`[category]` grows across an area** by default (`:flow [area]` in its case); the other kinds take `[S]`.

## 5. Ranks from spans

**Decided.** **Ranks belong to edges, not to nodes.** An edge has a **span**, the number of ranks it crosses; a node's rank follows from the spans that reach it. A node is never moved along the flow; an edge is stretched or shrunk.

- Every edge spans at least 1 unless stated: `:span [k]`. **`[k!]` spans k against the flow**, the explicit back edge (`:Ranks :: :Number!`).
- **Where a node can stand at two ranks, a span decides.** In `G :: +(f g h, m n)+` the branches must agree, span(f) + span(g) + span(h) = span(m) + span(n), so one of m and n spans 2. By default the shorter branch's last edge stretches (n), so nodes stand as early as they can; `m :span [2]` moves the middle node one rank down instead.

**The solve is constraints, not a search:**

1. **Stated spans and offsets are equalities**, rank(target) − rank(source) = span, contracted by a union-find with an offset per element. Two that disagree are an error, found before any placement: `m :span [1]` with `n :span [1]` against f g h (2 ≠ 3).
2. **Every other edge spans at least 1:** the longest path over the quotient, in source order.
3. **Cycles:** an edge spanning `[k!]` is a back edge. Where none is stated and a cycle remains (one glued across statements, `#A/f/#B, #B/g/#A`, has no slash cycle to read it from), a depth-first search in source order picks the back edges. That is the heuristic's choice, and deterministic.

O(V + E·α(V)).

**Open:** span 0, both ends on one rank (an upright square in diamond growth, a same-rank edge).

## 6. The heuristic

### 6.1 Dummies

**Decided.** An edge spanning k ranks is split by k − 1 dummy nodes, one per rank it crosses. Every crossing is then between adjacent ranks, an edge passing through a node is a dummy on the node's anchor (a wall, §7.2), and **the route of an edge is its chain of dummies**: a polyline, straight between anchors, at any angle. The directions of a grid place nodes, never edges: an edge may run diagonally across a square grid.

### 6.2 The first placement: children centred

**Decided.** **A node's children on the next rank are centred under it, one step apart:** the tidy tree of Reingold and Tilford (1981), refined by Walker (1990) and made linear by Buchheim, Jünger and Leipert (2002). Subtrees are laid out from the leaves, each kept clear of its left neighbour, and shifted as a whole.

- **A half shift where the centre falls between anchors.** Whether it does depends on the flow, never on a count rule: along `[S]` on `[4]` the next rank's anchors are aligned with the parent, so three children fall on −1, 0, +1 and two on ±½; across an area, or along `[S]` on `[3]`, they are offset by half a step, so two children fall on the grid and one or three need the shift. Across positions are therefore counted in half steps, integers once doubled; nodes on one rank stay at least one whole step apart, so a shift moves a group and never squeezes it.
- **A lone child** is centred, straight along the flow, except across an area, where the area's numbers place it (§4).
- **What a tree cannot say is the superstrate's:** a node with several parents (the D of a commuting square, a cocone's apex) is placed under its first, in source order, and the superstrate relaxes the rest, half shifts included.
- Ranks in source order; blocks (§8) placed as units; colocation allowed, and repaired by the superstrate (§7.6). O(V′) on trees.

### 6.3 Parallel edges

**Decided.** k edges with the same two ends are drawn apart through **k − 1 virtual anchors subdivided in their gap**, local to that pair and indexed 1 … k − 1, so they stay integers; only those edges' dummies use them. A global (1/k)ℤ is rejected: making it integer multiplies every rank by the least common multiple of every k.

### 6.4 Loops

**Decided.** A loop routes through a virtual anchor beside its node; which side is the superstrate's choice, among the free ones. Tweaked as needed.

### 6.5 Collapse

**Decided.** Edges with the same two ends, whatever their direction or directedness, may be **collapsed**: one route, drawn as one line per edge (`:line [double]`, `[triple]`), each line keeping its own head, so f : A → B and g : B → A collapse to ⇄. What is collapsed is stated, as a flag on each edge: `(f, g) :collapse` (a group distributes, so f and g each carry it), and the flagged edges with the same two ends form one bundle; an unflagged parallel edge stays apart. **`&edge :collapse` collapses every eligible bundle of the diagram**, a class binding as any other. Errors: collapsing edges whose ends differ; collapsing an edge a cell lies on (a 2-cell is drawn between its sides, and a collapsed pair has no between).

## 7. The force superstrate

### 7.1 State

**Decided.** Ranks are final and the dummy graph is frozen, so each node, dummy or block has one free coordinate, its position across the flow, in half steps, in ℤ. The superstrate moves nodes only across, to free anchors or half shifts, never off the grid.

### 7.2 Walls

**Decided.** Some states are infeasible, not expensive: two nodes on one anchor (colocation), a dummy on a node's anchor (occlusion), two dummies on one anchor (edges overlapping). In ℤ³, checked on the projection.

### 7.3 Energy

**Decided** in its shape; the constants are open.

| Term | Form | Why |
| --- | --- | --- |
| **Tension** | Σ over edges of Q(Δ) | convex: swaps undo simple crossings (§7.5), and a node's best position has a closed form |
| **Straightness** | Σ over nodes with one edge in and one out (dummies included) of Q(Δ_in − Δ_out) | zero when straight: keeps long edges straight; across an area, measured against the line or stair its numbers ask for (§4) |
| **Crossings** | Σ over cells of X_c² | per cell of an anchor (its Voronoi area): a few scattered crossings cost little, many in one place much |

Every term is in ℕ. A crossing point is rational, and its cell is found by integer comparison.

### 7.4 Friction: mass

**Decided.** A node's mass is the number of nodes it holds: M(e) = ⌈M(w) / k_w⌉ for an edge e : v → w, k_w the edges into w (back edges excluded), and M(v) = 1 + Σ M(e) over the edges out of v. One pass in reverse rank order, in ℕ. Sharing over-counts (k·⌈m/k⌉ ≥ m), so shared structure is damped more than a tree of its size. **A move is accepted only if ΔE + M < 0**: friction is the price of a move, not a term of the energy, and heavy structure stays.

Stiffness is the energy's convexity; permanence is friction. Rest lengths ("the shorter, the stiffer") are rejected: they need a length per edge that only the heuristic could invent, and lose the closed form.

### 7.5 Why swaps fix simple crossings

**Decided.** For two edges between the same two ranks, a strictly convex cost of the difference has the Monge property, so by the rearrangement inequality the order-preserving matching costs strictly less: a simple crossing is never an equilibrium of tension. The crossings that survive are structural (undoing them stretches more) or damped (at heavy nodes); the crossing term weighs them.

### 7.6 Phases, moves, termination

**Decided.**

1. **Repair**, a rule, not a search: at each wall crossed, the lighter node moves to the nearest free anchor in its rank, on the side that stretches its edges less. Ranks are unbounded, so one exists. At most V′ repairs.
2. **Relaxation**, from the first feasible state, by moves into free anchors only:

| Move | What it does | Friction |
| --- | --- | --- |
| **jump** | a node to its best position with the others fixed: the weighted mean of its neighbours, rounded by integer division, or the nearest free anchor | m(v) |
| **swap** | two neighbours in a rank exchange places; the only move that changes order | m(u) + m(v) |
| **slide** | an edge with the mass it holds, as a rigid body; tension changes only on edges crossing its border | M(e) |

**Termination:** E ∈ ℕ and every accepted move lowers it by at least 1, so there are at most E₀ − E_final moves. A sweep cap, if ever needed, is a budget, not a correctness condition.

## 8. Offsets

**Deferred:** offsets are left out of α. What follows is what is known.

**A node may be placed relative to another node, never to the diagram:** an offset fixes B's position against A's as a vector of the lattice. Offset nodes are one **block**, a quotient: it holds several anchors, which the walls check together; its mass is its members' sum; it moves as a unit, and nothing interleaves it. Offsets are applied first, then the heuristic places blocks. An offset's rank part is an equality of §5, so spans and offsets are one structure, and their conflicts one error.

Errors before any placement: an offset against a span (`#A/f/#B` with B offset across A); two blocks on one anchor; a direction the grid lacks.

**Fixation is a flag, not a mass:** an infinite mass would propagate through §7.4 and freeze everything upstream.

**Open: the spelling,** probably on edges, as almost everything here is. A bracket can't hold `#A`, and a group of subjects distributes (`(#A, #B) :x` is `#A :x, #B :x`), so an offset can't be an ordered group; an edge already orders its two ends, so a direction word on an edge (its target placed that way from its source) needs neither, at the cost of offsets between nodes no edge joins.

## 9. Kinds

**Decided.** A kind chooses defaults by its case, as it chooses its theme (`statements.md` §24): `[category]` grows square. A kind adds no algorithm.

## 10. The layer and the renderer

**Decided.** **The solve needs no sizes.** Ranks, positions across, crossings and walls are facts of the lattice. The embedding ι maps each axis monotonically (the metric, then content sizes), which keeps the order within every rank, and so every crossing between adjacent ranks. So fab-layer-place solves the whole layout from fab-core's analysis alone, without the Sheet or any text measuring, and gives renderers an anchor per node and a route per edge. The renderer embeds: the metric, sizes measured through its interface, the routes' geometry, nested diagrams.

## 11. Efficiency

**Decided** as a goal; the numbers are estimates.

| Phase | Cost |
| --- | --- |
| spans and offsets (union-find, longest path) | O(V + E·α(V)) |
| dummies, mass | O(V′ + E′) |
| heuristic | O(V′ + E′) |
| repair | O(V′ log V′ + E′) |
| one relaxation sweep | O(V′ + E′), up to Δ² per swap for crossings |

V′ and E′ count dummies; Δ is the maximum degree. Memory is O(V′ + E′) integers and one sorted occupancy per rank. A few to a few tens of sweeps are expected: tens of microseconds for a small diagram, about a millisecond for a schema of 200 nodes, tens of milliseconds for 2,000.

dot is slower by its phases, not its code: network-simplex ranking (here, spans), crossing reduction by global sweeps (local swaps), coordinates by a second network simplex (none: anchors are coordinates), spline routing (dummy chains), floats and arbitrary sizes (ℕ and steps), a host process (a library call). Measured in step κ against dot on the same corpus.

## 12. Open

1. **Offsets** (§8), deferred.
2. **Span 0** (§5).
3. **A metric per axis** (§3.4).
4. **The constants:** the weights of straightness and crossings against tension.
5. **The GJH tail,** `:symmetry` (§3.2).
6. **Nested diagrams:** a member's grid, its own or its container's; one anchor or a block of anchors in the container.

## 13. Rejected

- **Absolute positions:** a position is relative to another node or nothing; the diagram has no origin a program could name.
- **Layout conventions as values** (TD, LR): a flow is a direction word.
- **`k!` as a half turn:** on `[4!]` direction 1 is south while `[1!]` would be north, so the seed's `!` and a direction's would disagree; `!` is the mirror in the seed's vertical axis (§3.3).
- **Direction n as a full turn,** a loop: numbers are modulo n.
- **Growth only along the tiling's edges:** an edge joins any two anchors (§3.1).
- **`[6]` as a seed:** a restricted `[3]` (§3.2).
- **A rule by parity** (an odd count keeping a centre, an even one shifting): whether the centre falls between anchors depends on the flow (§6.2).
- **Letter words of three or more,** and the compass's NNE: at 22.5°, it falls on no lattice.
- **An angle descriptor:** the angle is the metric (§3.4).
- **`[area] := [0/1]`:** a chain across it is a stair; `[0/0]` keeps it straight (§4).
- **`[edge]` and `[area]` as labels whose meaning differs by seed:** an area is defined by its two edges, the same on every seed, so they are named values.
- **An alias for the vertical edge** (`[v-edge]`): `[3]` has none, and `[S]`, or `[normal]`, is as short (§4).
- **Moving nodes along the flow,** and attraction toward an edge's end: ranks come from spans.
- **Rest lengths:** permanence is friction (§7.4).
- **A global (1/k)ℤ** for parallel edges (§6.3).
- **Floats in the solver.**
