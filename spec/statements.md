# fAB design decisions, 2026-10-23

Decisions taken in the design sessions of 22-23 October 2026, after `fab render` first worked end to end. They change the grammar in six places: statements and bindings, values, cells (levels), the `/` operator, pinching (with the split between flow and fusion), and subjects (classes). This note is the record of what was decided and why; the code does not implement it yet.

> **Superseded in part.** Sections 4 and 5, and the matching parts of 7, are replaced by the grammar of joining of 1 November ([`joining.md`](joining.md)); sections 9 and 11 by the plan in [`CLAUDE.md`](../CLAUDE.md). Section 12 (1 November) replaces how statements span lines (3) and how entries are delimited (1.3). Section 13 (1 November) settles the schema statements left open in 8.3; section 14 (2 November), how operators between chains are read; section 15 (2 November), how programs with no meaning yet are reported. They are kept for the record. Where this note and [`spec.md`](spec.md) differ, the spec wins.

**The spec doc ([`spec.md`](spec.md)) was rewritten from this note and [`style.md`](style.md) on the evening of 23 October. Where this note and the spec differ, the spec wins.** Three corrections were made while writing it, and are applied below: repeated node names glue in flows (5.1); `*` is not a pinch (5.3); `?` and `!` stay postfix only (5.3). Two decisions followed the same evening, both in 5.3: **`*` is a nameless node term, written alone, private to one edge end**, which replaced the seal; and **a pinched single edge resolves as a reference node, so it is pinched on one side only**, with redundant pinches allowed. The bracket reading and arrow literals of section 2 were refined in the style document (lowercase names, `[tail/line/head]` arrows).

Status words used below: **Decided** (agreed, ready for the spec), **Open** (still to settle), **Rejected** (considered and dropped, with the reason, so it is not proposed again). Where a later decision replaced an earlier one in the same sessions, the earlier one is listed under Rejected with the reason.

---

## 1. Two kinds of statement: declarations and definitions

**Decided.** Every top-level statement is one of two kinds, told apart by its operator.

| Kind        | Operator | Introduces                   | Example                                   |
| ----------- | -------- | ---------------------------- | ----------------------------------------- |
| Declaration | `::`     | new **structure**            | `Order :: * receive #Received …`          |
| Definition  | `:=`     | a new **binding** of a value | `[red] := [#ff0000]`, `G :style := { … }` |

- **Declarations assign structure.** Today only zones are declared. Nodes and edges may become declarable too (section 8, open). Zones, nodes and edges are the only things that can ever be declared.
- **Definitions assign values.** Every definition binds something new: a value name, an attribute, or an attribute's value at a subject. Nothing is ever bound twice.

### 1.1 The one form of a definition: subject first

**Decided.** A definition's left side names _where_ the value goes, read left to right as context then attribute; the right side is the value:

```
subject :attr := value
```

Its parts are optional, which gives exactly three kinds of definition:

| Left side       | Defines                           | Examples                                                                                          |
| --------------- | --------------------------------- | ------------------------------------------------------------------------------------------------- |
| `[name]`        | a value                           | `[red] := [#ff0000]`, `[warn] := [red]`                                                           |
| `:attr`         | a new attribute, everywhere       | `:terminal := { :shape [circle] :fill [red] }`                                                    |
| `subject :attr` | an attribute's value at a subject | `&node :shape := [circle]`, `G :style := { … }`, `G.f :style := { … }`, `G.&edge :style := { … }` |

Why subject first: inside blocks entries were already written _subject, attribute, value_ (`f :label "x"`). The top level now uses the same order, with `:=` marking that a binding is made. The language reads as one cohesive syntax rather than glued, disparate forms. "The context of `:func` is to the left, and the value is to the right."

### 1.2 Layers are attributes whose values are blocks

**Decided.** The three layers are attributes, each named by a five-letter verb, each accepting its own vocabulary in its block:

```
G :style := { … }    // how things look
G :prove := { … }    // what holds
G :place := { … }    // where things go
```

- `:style` replaces the old `:format`; `:prove` replaces `:proof`; `:place` is new (layout).
- **`:style` is non-relational:** a style value describes one element's look and never mentions another element.
- **`:place` is relational by nature:** direction, alignment, which node sits beside which, grid cells. This is where statements such as `:right-of` belong, which were rejected from format because format must not refer to structure. With nothing in `:place`, the defaults apply (drawing order is source order, section 5.4). Its vocabulary is open (section 8).
- **`:prove` holds equations and universal properties** (`f h = g k`, `+f :pullback`).

### 1.3 Blocks are factored subjects

**Decided.** A block is shorthand for a set of atomic definitions with a common subject prefix:

```
G :style := { #Done :terminal  f :label "x" }
// means
G.#Done :terminal := …
G.f :label := "x"
```

- An entry with a subject, `s :attr v`, inside the block of owner `X`, binds `X.s :attr`.
- An entry with no subject, `:attr v`, binds the owner itself: `&node :style := { :shape [circle] :ink [black] }` binds `&node :shape` and `&node :ink`.
- **Inside blocks, entries use the light form, without `:=`.** `:=` appears once per statement, at the top level, so every binding statement is visible at the left margin.
- **Entries are delimited by their values.** Values are never bare, so a bare name after an attribute always starts a new entry: `#Done :terminal  f :label "x"` is two entries. (Added in the spec.)
  **Mathematical reading.** A style is a partial function from (subject, attribute) pairs to values. `G :style := { … }` gives the part of it whose subjects start with G, as a function of the rest: it is **currying**. A block is a curried group of bindings.

### 1.4 Each binding once; overlap resolved by specificity

**Decided.**

- **Each (subject, attribute) pair is bound once.** Binding `#Done :shape` twice is an error, like any redefinition.
- **Different subjects may overlap.** `&node :shape := [circle]` and `#Done :shape := [box]` bind different subjects, and they overlap on `#Done`. The cascade resolves it: **the more specific subject wins.**
- So there is no silent overriding anywhere. A value changes only because a narrower subject says so, which is visible in the source.

### 1.5 Consequences

- Every name in a program comes from exactly one statement, `::` or `:=`.
- **Definitions are top level only, and come before their first use.** This is the same left-to-right rule as references to edges ("a marked name always points left"). One reading order for the whole program, and no forward references to resolve. A definition at a subject comes after the subject's declaration: `G :style := …` is an error if `G` is not declared.
- Definitions are immutable.

### 1.6 Mathematical reading of the split

- Declarations build the free structure: the graph E ⇉ V (nodes derived from edge ends), the cells above it, and the category of paths they generate.
- `:style` is a function on the elements of that structure, σ : Elements(G) → Attrs, folded through the cascade monoid (`Attrs.over`, identity `empty`) that already exists in fab-core.
- `:prove` gives a quotient. Its equations generate a congruence on paths, so a diagram with proofs denotes F(G)/~. Its universal properties (`:pullback`, `:pushout`) are claims about cones in that quotient.
- Value and attribute definitions form an environment Γ : Names → Values, typed, single assignment.
  So the split is **structure** (declarations) against **data indexed by structure** (definitions at subjects), plus a **name environment** (value and attribute definitions).

### 1.7 What can be defined

- **Values:** `[red] := [#ff0000]`, `[warn] := [red]` (aliases allowed). The type is inferred from the right side (section 2).
- **Attributes (bundles):** `:terminal := { :shape [circle] :fill [red] }`. A bundle is a named element of the Attrs monoid. Using it lays its contents over the cascade, exactly like writing them, so `#Done :terminal :fill [green]` works, and the later setting wins. This is the `:=` user-defined attribute that was postponed during the format-layer discussion ("expand in place").
- **Attributes at subjects:** `&node :shape := [circle]`, `G :style := { … }`.
- **Themes:** named styles, defined in the style document.
- **Not yet:** new shapes or arrow heads. Renderers would have to know how to draw them, so that is a bigger feature for later.
  **Rejected** (in the order they were considered).
- `Obj := :format { … }`: it would define `Obj` twice, once for format and once for proof, breaking "each name is defined once".
- `Obj := { :format { … } :proof { … } }`: too verbose; deep nesting.
- **Attribution as a third kind of statement** (`G :format { … }` with no `:=`, "format and proof are not definitions"). Decided first, then replaced: once a definition can bind an attribute's value at a subject, format and proof are definitions too, and a third kind is unnecessary.
- `:style G := { … }` (attribute first, the function applied to G). Replaced by subject first: the context belongs to the left, the value to the right, matching the order of entries inside blocks.

---

## 2. Values: three forms, and the bracket token

**Decided.** A value is always written in exactly one of three forms, and is **never bare**:

| Form  | For                                 | Example                                                                |
| ----- | ----------------------------------- | ---------------------------------------------------------------------- |
| `"…"` | text                                | `:label "Order received"`                                              |
| `$…$` | math                                | `:label $\mathbb{R}$`                                                  |
| `[…]` | everything else: names and literals | `[red]`, `[circle]`, `[#ff0000]`, `[/solid/>>]`, `[12]`, `[0..*/1..1]` |

Numbers go in brackets too: `:width [2]`, never `:width 2`. The rule has no exceptions apart from flags (an attribute with no value at all). The cost is a slightly heavier syntax, but it is opt-in: brackets only appear where something is styled. A program that only declares structure looks exactly as before.

**Brackets are values only.** They appear only in value position (after an `:attr`, or on the right of `:=`) and as the left side of a value definition, never inside a declaration or as a subject (see the rejected `[f]` in section 5 and `G [edge]` in section 6).

**The bracket token.**

- `[ … ]` is lexed as **one opaque token**. Its contents are any non-whitespace characters except `[` and `]`.
- No whitespace inside, ever: `[0..*/1..1]`, not `[0..* / 1..1]`. Text with spaces belongs in `"…"`.
- No nesting. A value never contains another value. Lists, if ever needed, live inside one token with commas (`[4,2]` for a dash pattern) and are read by that type's grammar.
- Because the main lexer never looks inside, symbols there cannot clash with their meaning outside. That is how `[#ff0000]` gets hex colours back without colliding with named nodes `#A`.
  **Typed reading.** The analyser reads a bracket's contents by the type its attribute expects. `:ink` expects a colour, so `[…]` is read as a colour; `:arrow` expects an arrow, so arrow syntax applies.

**How a bracket is read** (refined in the style document, section 3.1, which supersedes the first-character rule first decided here):

| Bracket                        | Is                           |
| ------------------------------ | ---------------------------- |
| contains exactly two `/`       | an arrow, `[tail/line/head]` |
| starts with a lowercase letter | a name                       |
| starts with `#`                | a colour                     |
| starts with a digit            | a number; with `..`, a range |

Every bracket has exactly one kind, so `[x] := […]` works out its own type without annotation. Mathematically, values form a coproduct of sorts, and each literal lies in exactly one summand. `!` inside brackets inverts what it follows, and there are no negative numbers (style document, 3.2).

**Definitions use brackets on both sides:** `[red] := [#ff0000]`. The left side is a name, the right side a value like any other.

**Type errors** become precise: `:shape [red]` is "a colour where a shape is expected".

**Lexer consequence.** The separate `arrow` token, and the `[`/`]` tokens used for cells, disappear. One value token replaces them; cells move to `|` (section 3).

**Rejected.**

- `[:if]` as a value for boolean control (it was meant for proofs). Dropped by its author: it pushes values from data towards a programming language.
- Bare names in value position (`:ink red`, `red := …`): lighter, but a bare `red` at the top level looks like an edge name.
- Bare numbers: an exception to "one of three forms".
- Names versus literals by "starts with a letter": replaced by the lowercase rule and two-slash arrows (style document).

---

## 3. Cells: levels separated by `|`

**Decided.** The old `[ … ]` syntax for edge-to-edge relations (2-cells) is replaced. A declaration is written in **levels**, separated by `|`:

```
G :: level 1 | level 2 | level 3
```

**Why.** A diagram with cells is a presentation graded by dimension: 1-cells between nodes, 2-cells between 1-cells, 3-cells between 2-cells. Mathematicians call this a **polygraph** or **computad**: generators at each dimension, each with a source and a target in the dimension below. `|` writes exactly that grading. It also turns into syntax a rule that `[ ]` only implied: level k can only follow level k-1, because its cells refer to cells declared before them.

**Rules for levels.**

- Each level uses the same grammar as level 1, one dimension up.
- **At level k ≥ 2, a declared name refers to a cell of level k-1, and a new name creates a cell of level k.** No sigil is needed. The declare-once rule tells the two apart, and the `/` rule (section 4) makes it visible by position.
- **Sides are always single, already-named cells.** There are never paths as sides, and never parentheses around a side. "All paths must be previously named."
- **No undirected cells above level 1.** A trailing `/` at level 2 or above is an error.
- `|` may appear only at the top of a declaration's right side, or inside one group that wraps the _whole_ right side. `G :: f (g | α)` is an error: a level cannot live inside a branch.
  **Composites as sources.** A 2-cell whose source is a composite, such as α : f h ⇒ g, cannot be written directly, since sides are named. The composite is named first at level 1, and the proof layer states that it is the composite:

```
W :: f h, +f/k/h+, +f/g/h+ | k/α/g
W :prove := { k = f h }
```

This keeps structure a plain graph at every level, and makes composites facts stated by proofs, not shapes the syntax must express. It matches the split of section 1: declarations give structure, proofs give equations.

**Multi-line declarations.** Only with one outer group `( … )`, as today (the parser already skips newlines inside parentheses). The group may contain the `|`:

```
Iso :: (
  +(f, g)+
  | f/α/β/g
)
```

**Rejected.**

- Keeping `[ ]` for cells. Position would have separated cells from values, but each symbol now has one meaning: brackets are values only.
- `#f` to mark references at level 2 (generalising `#` as "a cell one level down"), and `#f#g` or `f#g` for paths. Unnecessary: every edge has a name and is declared once, so references are known. `#` keeps one meaning: a named node at level 1.
- Plain juxtaposition at level 2 (`f α g`, `f h α g`). It overloaded juxtaposition twice (gluing a cell to its ends, and composing references) and made new names visible only through declaration lookup. Replaced by `/` (section 4).
- `(f h)/α/g`, a path as a side. Sides are always named.
- Continuation lines starting with `|`. Explicit parentheses are the only way to span lines; no new rule about newlines.

---

## 4. The `/` rule, the same at every level

**Decided.** Between two existing sides, `/` places new cells. The middle is new; the sides already exist.

| Level | Form      | Meaning                                              |
| ----- | --------- | ---------------------------------------------------- |
| 1     | `+f/g/f+` | g : +f → f+, a new edge between two existing nodes   |
| 2     | `f/α/g`   | α : f ⇒ g, a new 2-cell between two existing edges   |
| 3     | `α/m/β`   | m : α ⇛ β, a new 3-cell between two existing 2-cells |

At level 1 the sides are node references with end markers (`+f`, `f+`) or existing node names (`#P`); at level 2 and above they are the names of cells, which need no markers.

**One or two new cells.**

- **One new name** between two sides is one cell, from the left side to the right: `f/α/g`.
- **Two new names** between two sides are a pair, there and back: `f/a/b/g` gives a : f ⇒ g and b : g ⇒ f. The prime is a natural naming convention for the inverse: `f/a/a'/g`.
- **Three or more new names in a row** is an error.
- **With no sides,** `f/g` keeps its current meaning: a loop, f goes and g comes back.
  This is the level-1 rule for `f/g` (there and back) placed between two existing sides.

**This applies to level 1 too, and changes the analyser.** `+f/m/n/g+` means m : +f → g+ and n : g+ → +f. Checked on 2026-10-23 with the current `fab`: `G :: f g, +f/m/n/g+` is **rejected today**, with "This back edge has nothing to connect" at the second `/`. Under the new rule it becomes a legal pair. The `/` chain must see that both outer operands are references before deciding what the middle names mean. It is a small, local change, and it turns an error into a useful form.

**Named nodes as sides change the analyser too.** Checked on 2026-10-23: today `#V/g` makes g a loop on V (the back edge of a node term returns to that node), and `#U/g/#V` with both names existing is rejected. Under the `/` rule, `#V/g` starts g at V and `#U/g/#V` puts g between U and V.

**Chains** continue through existing names, read left to right as `/` already is (`+f/h/g+` is `(+f/h)/g+`):

- `f/α/g/β/h` gives α : f ⇒ g, then β : g ⇒ h (vertical composition);
- a cell is declared in its middle position and can be referenced to the right, in the same level or the next: `f/α/g, f/β/g | α/m/β`.
  **Going straight back gets a hint.** `f/a/g/b/f` follows from the chain rule, but it is cumbersome. Forbidding it would need an exception in the grammar, and longer cycles such as `f/α/g/β/h/γ/f` are legitimate and have no shorter form. So the analyser **warns** on the two-step return:

> warning: this chain goes from `f` to `g` and straight back
> hint: write `f/a/b/g`

The check is the same if it is later made a hard error; only the severity changes.

**Why this is better than everything before it.** The new name is visible by position, and it is checked twice: the middle must not be declared yet, and the sides must be. When position and declarations disagree, the error has a precise cause.

---

## 5. Flow, fusion and pinching

### 5.1 Juxtaposition flows, `/` fuses

**Decided** (corrected on the evening of 23 October; see below).

| Operator      | Meaning        | Its operands                                                                               |
| ------------- | -------------- | ------------------------------------------------------------------------------------------ |
| juxtaposition | **flows into** | new edges; node names and diagram names, new or repeated; `*`                              |
| `/`           | **fuses with** | a new edge in the middle; things that exist as sides: `+f`, `f+`, `#Name`, a declared cell |

- **A node name in a flow names the node there:** in `#A f g #C`, A is where f starts and C is where g ends.
- **Repeated names glue.** Named nodes and diagram names are identified by their name, so writing one again glues to it: `#U f #V, #U g #W` forks at U. A name stays open, so it can be continued. Today's analyser does exactly this, and the schemas depend on it: `Comment (on Document, writer User, reply_to Comment)` repeats diagram names.
- **References to ends are fused, never juxtaposed.** `+f` and `f+` are only ever sides of `/`, because they close the side they are on. Today's analyser rejects a juxtaposed reference with "A reference must be fused with `/`".
- **Anything that exists can be a side of `/`:** an end (`+f/h/g+`), a named node (`#A/h/#C`, `#P/(p1/g1+, p2/g2+)`), a cell. The middle of `/` is always new. A null node is the exception: it is private (5.3), so it is never a side.
  **Correction.** The first version of this section said that a name in a flow must be new, and that today's analyser enforces it. Both claims were wrong: the analyser lets repeated names glue (and the first spec required it), and the error quoted for `#A/f g/#C` came from `/` on a node term, which today makes back-edge loops. Decided with the spec rewrite: repeated names glue, and names can also be sides of `/`.

### 5.2 Both operators distribute over a group

**Decided.** A group takes what is on its left once per branch, whichever operator joins them. This is not a new rule for `/`: it is the rule juxtaposition already follows.

- `#X (g1, f, g2)`: the flow from X continues into every branch, so all three start at X.
- `f+/(p1/g1+, p2/g2+)` means `f+/p1/g1+, f+/p2/g2+`: the fusion with f+ applies to every branch.

### 5.3 Pinching markers, and the null node `*`

**Decided** (corrected and refined on the evening of 23 October; see below).

> A pinching marker merges one side of what it touches into a single node of its kind: `+` plain, `?` choice, `!` parallel.

| Marker | Prefix                   | Postfix                | On a group        |
| ------ | ------------------------ | ---------------------- | ----------------- |
| `+`    | `+t`: pinches the starts | `t+`: pinches the ends | one plain node    |
| `?`    | no                       | `t?`: pinches the ends | one choice node   |
| `!`    | no                       | `t!`: pinches the ends | one parallel node |

- On a **group**, the start of every branch (or the end of every branch) becomes one node. Only the _first_ node of each branch is pinched at the start, and only the _last_ at the end; inner nodes of a path stay separate.
- On **one branch**, the pinch just _is_ that branch's node: **a pinched edge resolves as a reference node.** So `+(f) = +f` by definition; `+f` is the node at dom(f), and `f?` is the node at cod(f), made a choice. When f is new, the flow declares it there and continues from that node, as in `f? (g, h)`. When f is already declared, `+f` is a reference. References are not a separate concept: they are the one-branch pinch.
- **A single edge is pinched on one side only.** A pinched edge is one node, and a term cannot be two nodes: `+f+`, `+f?`, `+f!` and `+(f)+` are errors. A group may be pinched on both sides: `+(f, g)+`.
- **Redundant pinches are fine.** Juxtaposition already merges the side it glues, so `f (g, h)` and `f +(g, h)` are the same graph, and so are `#X (a, b)` and `#X +(a, b)`. A redundant pinch gets no warning. "It does not matter if the pinching is redundant. I prefer that, than to live with messy notation."
- **`?` and `!` are `+` plus a kind.** They always pinch, and make the pinched node a choice or a parallel. They are postfix only, as in the first spec. A flow that starts with a decision writes `* start? ( … )`.
- `+` was the missing plain member of the pinching family: `(g, h)?` and `(g, h)!` already merged branch ends.
  **`*` is a nameless node term, not a marker.** "`*` is a reference to a node per se, so it should behave exactly like `#Node`, except for one difference: `*` is private to one edge."
- Each `*` is a **fresh null node** that holds **exactly one edge end**: the start of the edge after it, or the end of the edge before it.
- **Written alone.** `*` is spaced from names and operators and touches only punctuation: `* f g h *`, `(* f f1, * g g1)+`, `(…, k *)`. The touching forms `*f` and `f*` are errors, so `(*f, f1 *g g1)+` is rejected.
- **One end only.** `* (f, g)`, `(f, g) *`, `(f, g)+ *` and `f * g` are errors: each would make one null node hold several ends. Two starts are written `(* f, * g)`.
- **Private.** Nothing in a flow can glue to a null node or refer to it, and it is never a side of `/`. Definitions still name it through its edge's end, `+f` or `f+`.
- **It leaves the interface:** `f` has an open codomain, `f *` has none. A branch ending with `*` is closed, so `(f *, g) h` attaches h to g only.
- Privacy replaces three separate rules of the seal: a seal that glues nothing, sealing a shared end, and a reference to a sealed end. All three are now one: a null node holds one end.
  **Corrections.**
- The first version of this section listed `*` among the pinches and said `*(f, g)` "starts both branches at one null node", and let every marker pinch as a prefix. The spec rewrite corrected it to a seal that closes each end with its own null node and distributes over groups (`(g, h)*` = `g*, h*`), with `?` and `!` postfix only.
- Later the same evening the seal was replaced in turn: as a marker, `*` sat in the marker family while behaving like no other member, which made `*(f, g)` look like a pinch. As a node term it reads like `#A`, the only difference is privacy, and the touching forms disappear.
- Then the one-side rule and redundant pinches were added. A proposal to make the pinch mandatory (juxtaposition joining exactly one end to one end, so `f (g, h)` would have to be `f +(g, h)`) was **rejected**: it puts a `+` on every fan, including every schema line, and messy notation is worse than a redundant pinch.
  **Mathematical reading.** A group `(f, g)` is a disjoint union of graphs (a coproduct). A pinch is a quotient that identifies the chosen endpoints. `+( … )` is the topologists' _wedge sum_ (pieces glued at one point); `+( … )+` glues both ends, which is _parallel composition_. On one edge the quotient is trivial, and what is left is the endpoint itself: a node, so it has one side. A null node is a vertex of degree one that the quotient may never identify with anything: a point outside the interface.

**A pinch with several branches declares them.**

- `+(f, g)+` declares new edges f and g and pinches them on each side. The names inside must be new.
- The first branch names the pinched nodes, by the usual canonical rule (the first end described): in `+(f, g)+`, the pinched start is `+f` and the pinched end is `f+`.
- `G :: f g, h k, +(f, h)` is an **error**: "`f` is already declared; a pinch declares its branches". A pinch never merges two existing nodes by surprise.
- Glueing existing things stays the job of `/` (5.1), which already says "the sides exist".
- The one-branch case on a declared name (`+f`, `+(f)`) is the reference.
- A pinched node stays open, and can be continued like any node term.
  **Examples.**

```
Nat :: +(f, g)+ | f/α/g             // a natural transformation; was f, +f/g/f+ | f/α/g
Sq  :: +(f h, g k)+                 // a commutative square; was f h, +f/g k/h+
Eq  :: +(f, g)+ | f/α/β/g           // an invertible 2-cell
Pr  :: +(f, g1, g2), f+/(p1/g1+, p2/g2+)   // the universal property of a product
Par :: * s! (a, b)! t *             // start, fork, two parallel branches, join, stop
```

The square is now readable at a glance: two paths with the same start and the same end.

### 5.4 Drawing order is source order

**Decided.** Branches are drawn left to right **in the order they are written**. This is the default layout rule; there is no `:order` attribute in `:style`.

- In `#X (g1, f, g2)`, f is drawn in the middle because it is written in the middle.
- An `:order` style value was avoided on purpose: it would refer to _structure_ (`:order [g1,f,g2]` names edges), which `:style` must never do. Relational placement belongs to `:place` (section 1.2), whose vocabulary is open.
- For Graphviz, `ordering=out` would keep each node's outgoing edges in written order. **Deferred** (decided on 23 October): no layout work until fAB has its own layout engine.

### 5.5 Naming nodes is optional, and decouples names from order

**Decided.** Both of these are accepted, and draw the same product diagram with f in the middle:

```
G :: #X (g1, f #P, g2), #P/(p1/g1+, p2/g2+)
G :: #X (g1, f, g2), f+/(p1/g1+, p2/g2+)
```

- `#X (…)` fans all three edges out of one start: the pinch you get from a named node followed by a group.
- `#P` names the product independently of order; without it, the product node is referenced as `f+`.
- Since names come from `#`, the first branch no longer has to be f for naming purposes. Order serves the drawing; names serve the reader.
  **Rejected.** `[f]` to mark a distinguished branch (in `+(g1, [f], g2)`). Brackets are values only (section 2). Its two possible purposes are covered otherwise: naming the pinched node is done by `#X` or by reading order, and "the unique mediating arrow" is a fact about a universal property, so it belongs to `:prove`, which would also produce the dashed rendering.

---

## 6. Subjects and classes

**Decided.** The subjects of definitions (section 1) are:

| Subject              | Means                        | Example                                           |
| -------------------- | ---------------------------- | ------------------------------------------------- |
| a zone               | the diagram                  | `G :style := …`                                   |
| an edge or cell name | that edge or cell            | `G.f :style := …`                                 |
| an end               | a node, by its canonical end | `G.+f :label := "X"`                              |
| a node name          | that named node              | `G.#Done :terminal := …`                          |
| a class              | every element of a kind      | `&node :shape := [circle]`, `G.&edge :style := …` |

**`.` means "inside", and nothing else.** `G.f` is the edge f inside G; `G.&edge` is the class of edges inside G; `A.+f` is the start of f inside A. The dot is always infix, between two things.

**Classes carry the sigil `&`.** The built-in classes are `&node`, the node kinds (`&plain`, `&choice`, `&parallel`, `&start`, `&end`, `&hole`), `&canonical`, `&edge`, `&cell` and `&zone` (style document, 2.2).

- A class is a marked name, never a bare word, so **no words are reserved**. An edge may be called `edge`, and `G.edge` means exactly that edge.
- `&` reads naturally as "all" (`&edge`, all edges), and stands apart from the node mark `#`.
- The grammar's special class production (a leading `.`, as in `.edge`) disappears, since `.` is now only infix.
- **Later:** user-defined classes (`&iso`) could name sets of elements chosen by the user. Bundles (`:terminal`) remain sets of attributes. The two sides stay distinct, each with its own mark: `&` for sets of elements, `:` for attributes.
  **Specificity** (section 1.4) orders subjects from general to narrow: a class, then a narrower class, then a class inside a zone, then a single element. A narrower subject wins where they overlap.

**Rejected.**

- `.edge`, a leading dot for classes. It gave `.` two meanings ("inside" between names, "class" at the start), and `G.edge` was ambiguous between "the edge named `edge` in G" and "the class `.edge` in G".
- Reserving bare words (`node`, `edge`, `zone`, `canonical`) so `G.edge` means the class: no reserved unmarked names; they take words away from users.
- `G .edge`, with a meaningful space: brittle.
- `G [edge]`: brackets are values only, and a class is a subject.
- `G..edge` (G, then the class `.edge`): exact but reads like a range.
- Other sigils considered: `%` and `^` would also work; `~` is risky next to `~=`.

---

## 7. Errors these decisions introduce

All local, each with a precise cause. The spec's Errors section is the complete list.

**Definitions, bindings and values**

- `[x]` is not defined; `[x]` is defined twice; `[x]` is used before its definition.
- A built-in (`[circle]`) cannot be redefined.
- A binding made twice: "`#Done :shape` is already defined".
- A definition at an undeclared subject: "`G` is not declared".
- An attribute not allowed in this layer: "`:pullback` belongs in `:prove`, not `:style`".
- A relational value in `:style` (a value that names structure).
- Wrong type: "a colour where a shape is expected".
- Whitespace or brackets inside `[…]`.
- A bare value (`:width 2`): "values are written `"…"`, `$…$` or `[…]`".
- A value (`[…]`) inside a declaration or as a subject.
- Unknown attribute, or an attribute bundle used before its definition.
- Unknown class (`&nodes`).
  **Levels and `/`**
- An empty level: `G :: f | | m`.
- `|` inside a branch: `G :: f (g | α)`.
- A side that is not declared: "`gg` is not declared; the sides of `/…/` must already exist".
- A middle name that is already declared: "`α` is already declared; the middle of `/…/` must be new".
- Three or more new names in a row.
- A trailing `/` at level 2 or above: no undirected cells there.
- A side from the wrong level: "`f` is a 1-cell; level 3 relates 2-cells".
- Sides that are not parallel: α : f ⇒ g needs f and g to share their start and end.
- Warning: a chain that goes straight back (`f/a/g/b/f`), with the hint `f/a/b/g`.
  **Flow, fusion and pinching**
- A reference juxtaposed instead of fused (exists today): "A reference must be fused with `/`".
- A pinch with several branches containing a declared name: "`f` is already declared; a pinch declares its branches".
- A prefix `?` or `!`: they are postfix only.
- A single edge pinched on both sides: `+f+`, `+f?`, `+(f)+`. "A pinched edge is one reference node; it has one side".
- Pinching nodes of conflicting kinds, such as a choice with a parallel (the union-find conflict, reported today), and changing a node's kind after it was created (`k?/+f`).
- No warning for a redundant pinch: `f +(g, h)` and `+(f)` are fine. (The earlier "empty pinch" warning is dropped.)
  **The null node `*`**
- `*` touching a name: `*f`, `f*`. "`*` is a node term, written alone: `* f`".
- `*` holding several ends: `* (f, g)`, `(f, g) *`, `(f, g)+ *`, `f * g`. "A null node holds exactly one edge end; write `(* f, * g)`".
- Reference to a null node: `k f *, j/f+`. "A null node is private to its edge end".
- Both ends null: `* f *`. An edge from nothing to nothing says nothing.

---

## 8. Open questions

1. **Declaring nodes and edges.** Agreed that zones, nodes and edges are the only declarable structures; not yet agreed what declaring a node or an edge means. The proposed reading: a declaration says "this thing has a graph inside it", and a graph can live in three places:
   ```
   Order :: …                 // a zone: a graph on its own
   #User :: @ (id, name)      // a node: a graph inside a point
   review :: check approve    // an edge: a graph along an arrow
   ```
   - A declared node is a compound node: a composite state, or a table in a schema. It would cover what `:as node` and `:as table` say with an attribute, so contraction would follow from structure, not style, and `:as node` might disappear.
   - A declared edge stands for a whole path: a subprocess, or an abstraction one could expand. Its inside has a boundary (it must run from `+review` to `review+`), which gives a new error: the inner diagram's open ends do not match the edge's ends.
   - Related to proofs: `review :: check approve` (built from: structure) is not the same statement as `review = check approve` (equal to: a fact), but the first implies the second.
2. **The `:prove` layer.** To settle before implementing it:
   - what the checker checks: well-formedness (both sides of an equation are real paths with the same ends; a universal property has exactly one square to apply to). It cannot decide whether an arbitrary equation is true (commutation is a word problem, undecidable in general), so the layer states facts rather than proving them, even though its verb is "prove";
   - consequences: whether statements imply others (two commuting squares side by side imply the outer rectangle commutes);
   - what is drawn: corner marks for pullbacks (⌟) and pushouts (⌜) certainly; whether a commuting square gets a mark or only a layout hint; dashing for arrows a universal property makes unique (the mediating f of a product).
3. **Schema statements under the new rules** (found while rewriting the spec). Mechanical conversions are done in the spec (`:card [0..*/1]`, `&node.id`, `&edge`, flags `:pk`, `:unique`, `:nullable`, `:required`). Open: `:by` names a column, which is a reference to structure, not a value, so how it is written in value position; and interpolation of names in defaults (`{.edge+ :snakecase}_id`), since braces now open blocks. *Settled in section 13: `:by` and interpolation are gone.*
4. **The `:place` vocabulary.** Direction, alignment, relative placement, grid cells, and the strict mesh (section 10), likely after the native layout engine exists.
5. **The header** (diagram kind, strictness, boundary). Under section 1 it is naturally a definition at the zone, such as `Sq :kind := [category]`. Which attributes, and what each changes, is not discussed yet.
   The arrow-literal grammar, listed here before, is settled in the style document.

---

## 9. Plan

Agreed order of work:

1. **Update the spec.** Done on the evening of 23 October, including the null node `*` and the one-side rule for pinched edges.
2. **Change the grammar in fab-core:**
   - lexer: one value token for `[…]` (replacing `arrow`, `l_brack`, `r_brack`), a `pipe` token for `|`, `:=` in use, `&` for classes, and `*` as a token that must stand alone (an error when it touches a name);
   - parser: levels; definitions in their three forms with subject first; blocks as factored subjects; values; classes as `&name`, `.` only infix; `*` as a node term, no longer a marker;
   - analyser: the level rules; the `/` rule at every level (including `+f/m/n/g+`, and named nodes as sides, at level 1); `/` distributing over groups; pinches on groups (`+` prefix and postfix; `?`, `!` postfix), with several-branch pinches declaring their branches; a pinched single edge as a reference node, pinched on one side only; `*` as a fresh, private null node holding one end; the name environment for definitions; one binding per (subject, attribute);
   - tests, examples and the JSON output updated.
3. **The `:style` layer,** built on the name environment, in four usable steps: direct attributes at subjects; selectors (lists, canonical ends, classes); named bundles (`:name := { … }`) and themes; `:as` set by a zone or its parent (parent may override only `:as`), then zone contraction.
4. **Settle the `:prove` layer** (open question 2), then implement it in fab-core.
5. **The native renderer:** `layout/` (shared by native and TikZ, with a text-measuring function), then `native/` (SVG), then `2tikz/`. The `:place` vocabulary (open question 4) grows with it.
   Why this order: the style layer settles the grammar of subjects (`+f`, `#Name`, `&class`, qualification with `.`, blocks), the name environment and the diagnostics machinery, and the proof layer reuses all of it. The proof layer comes before the native renderer because proofs add to the IR (equations, universal properties), produce marks the renderer must draw, and give layout hints (a square stated to commute should be drawn as a square). The renderer's input should be stable before the biggest piece of work is built on it.

---

## 10. Rendering decisions from the same session

Implemented in code on 2026-10-22 (fab-core `Formatter.zig`, fab-render `Theme.zig` and `2dot/root.zig`), recorded here for completeness.

**Kind defaults (fab-core, the Sheet):**

- Plain nodes are circles, with the label inside.
- Marks have no label by default, even when named: choices (diamond), parallels (bar), starts and ends. Only `:label` will label a mark.
- A null node is a **start** (filled dot) if no edge arrives at it, else an **end** (bullseye), as in UML activity diagrams.
- Holes stay dashed circles with their canonical label.
  **DOT realization (fab-render):**
- A header with graph, node and edge defaults: Helvetica (oblique for canonical labels), edge labels at 9pt in the theme's soft grey, `nodesep`/`ranksep` 0.45, dark grey lines, arrowsize 0.6.
- Every circle in a diagram has the same diameter, big enough for its longest label (estimated at 0.085 in per character plus 0.2 in; minimum 0.35 in). Graphviz cannot measure text, so this is an estimate; the native engine will measure.
- A bar is as wide as its busier side needs: 0.38 in per branch, minimum 0.6 in.
- Theme colours: `ink` #333333 (lines, node text), `soft` #555555 (edge labels), `muted` #888888 (canonical labels), `accent` #1f6feb.
  **Layout:** Graphviz's own layout is kept unchanged. Tried and rejected, with mockups:
- labels beside small circles (Graphviz places outside labels without making room, so they collide with edges);
- forcing edges to leave at the bottom and enter at the top (ugly hooks on back edges);
- side ports for back edges (crossings);
- right-angle edges (labels float away from their edges);
- snapping nodes to a strict grid via `dot` then `neato -n2` (aligned, but edges degrade: paired edges overlap, labels drift).
  **A strict mesh layout is deferred to the native layout engine**, where it can be first-class: ranks as rows, order within a rank as columns, every coordinate an integer, with edge routing that knows the grid. It will be requested through `:place`.

---

## 11. Implementation status, 2026-10-23

Working, in Zig 0.17, monorepo `fab-lang/` (`fab-core`, `fab-render`, `fab-cli`, root `Makefile`, `README.md`, AGPL-3.0-or-later):

- **fab-core** (113 tests): lexer, parser (with per-statement error recovery), analyser (union-find nodes, best-effort analysis with holes), IR, format pass to a `Sheet`, diagnostics with three-layer messages, JSON output (format v1), `Compilation` as the public API.
- **fab-render** (19 tests): `2dot/` (Sheet to DOT, with notes for what DOT cannot draw, such as cells), `shared/Note.zig`, `shared/Theme.zig`. Correctness law tested: reading the DOT back gives the IR's 1-truncation, on every spec program and 2,000 random ones.
- **fab-cli** (35 tests): `fab render | check | show`, engines and formats, `--strict`, `--watch`, `--verbosity`, `--no-color`; the graphviz engine runs `dot` from the host.
  Not yet: the style layer (`:format` blocks parse but are not applied; the code still uses the old names `:format` and `:proof` and the old class syntax `.edge`), the proof layer, the native and TikZ engines, `--preview`, `--zone`, the WebAssembly build, `*` as a standalone node term (the code still reads `*f` and `f*` as seals), the one-side rule for pinched edges, and every decision in sections 1 to 8 of this note.

---

## 12. Lines, items and the comma, 2026-11-01

Decided in the grammar session of 1 November 2026, while rewriting [`grammar.ebnf`](grammar.ebnf). It replaces the multi-line rule of section 3 ("explicit parentheses are the only way to span lines") and the delimiting of entries by their values in 1.3.

### 12.1 Decided

- **A statement is one line; braces let it span lines.** Inside `{ }`, at any depth, a newline is a space. Outside them a newline ends the statement, even inside parentheses. Braces are optional for both kinds of statement: `Iso :: { +(f, g)+ | f/α/g/β }`, `G :style := #Done :terminal, f :label "x"`.
- **Both statements take the same right side:** items, inline or in braces. A declaration is `primitive :: …`, where a primitive is a zone, node or edge name; a definition is `subject := …`. Which items each allows is the analyser's call.
- **An item is a bare term, an entry or an equation.** Declarations hold terms; definitions hold entries and equations.
- **`,` separates items everywhere, with one meaning:** side by side, and independent. Graphs side by side in a declaration (the coproduct it already was), bindings side by side in a style, propositions side by side in a proof (their conjunction). The comma is required between items and only between them: a missing comma and a trailing comma (`(f, g,)`) are errors. "Small noise for lots of semantic separation."
- **Several subjects are a group:** `(yes, paid) :label "yes"`. The attributes distribute over the group, as `/` does. It separates the group being styled or tested from what is said about it.
- **One group, `( … )`, everywhere.** It isolates what it holds: a term, a subject, or propositions. The parser builds the same node for each; what a group means is the analyser's call. Groups and subjectless braces may nest to organise.
- **Equations end at a comma,** since a side is a chain and a chain stops there. Chains state each step: `f h == g k == d`. Grouping a proposition, `(f h == g k)`, is optional.
- **`|` appears only at the top of a declaration's right side.** It is not a separator: a declaration is one line, and braces only let it break, naturally at `|`. A group never holds `|`, so `f (h | g)` is a parse error.
- **No empty braces:** `G :: {}` and `G :style := {}` are errors.
- **A newline inside a chain is a feature,** for composing long structures. The analyser warns when a newline falls between two closed chains of an open chain, unless a group stands on either side: `(f g)` then `(h k)` on the next line is quiet.
- **Precedence,** tightest first: postfix, juxtafix, prefix, then the infixes `/` and space, then `,`, then `|`.

### 12.2 Rejected

- **Parentheses spanning lines** (section 3): `( )` then had two jobs, grouping and wrapping a multi-line declaration, with the exception "a group holds `|` only when it holds whole levels".
- **`;` as a terminator of statements and equations,** with newlines always spaces: workable, but it adds a token to every line.
- **`;` as the universal separator, replacing `|`:** too many problems and ambiguities; `|` is not a separator.
- **Every equation in its own braces:** braces would have taken a third job; the comma ends an equation with no new rule.
- **Entries delimited by their values** (1.3), with the comma optional: two ways to write the same thing.
- **A trailing comma:** `(f, g,)` is a real problem in terms.

---

## 13. Schemas: foreign keys and keys, 2026-11-01

Decided in the same session, while closing the open schema question of 8.3. It replaces `:by`, `:unique` and the interpolated default names.

### 13.1 Decided

- **A schema is a header kind:** `Db :kind := [schema]`. In a schema, an edge between two tables is a foreign key; nothing else marks it, so there is no `:fk`.
- **A foreign key is one edge,** from the table holding it to the table it references, declared in the diagram that joins them. It is both the relationship, used in paths and equations, and the column that stores it. Name it as a relationship (`parent`, `author`), not as a column (`parent_id`).
- **Its column's type is the type of the target's key,** so it is never written and cannot mismatch.
- **Tables hold only their own columns.** No forward references between tables: every foreign key lives in the joining diagram, after the tables. Its foreign keys share that diagram's scope, so two tables cannot both have an `author`; another name and `:label` cover it.
- **Foreign-key rows.** A table drawn `[table]` shows each foreign key leaving it as a row: label the edge's name, `_`, and the referenced key's name (`parent_id`), type the key's type, and an arrow from the row to the target's key row. `:label` overrides the name: `writer :label "author_id"`. This gives the field-to-field arrow without a second edge.
- **`:pk` is the key** (mono, one per table); **`:uk` is another key** (mono, any number), replacing `:unique`. A source end of at most one must be `:uk`.
- **Groups of foreign keys are unqualified,** since they live in the joining diagram, and share their source table: `(user, org)! :uk`.
- **`(fk, Table.key) :refs`** references a key other than the `:pk`. The group holds one foreign key and one key of its target, in either order, and denotes the composite `author User.email`: the column the table stores. It changes the storage, not the relationship. Row `author_email`, typed as `User.email`, arrow to the `User.email` row.
- **New errors:** a foreign key to a table without a key; a reference to a column that is not a key; `:refs` without a foreign key and a key of its target.
- **Open:** column names for emitters (from `:label`, or a schema attribute), when fAB emits SQL.

### 13.2 Rejected

- **`:by Column`** naming the column a foreign key goes through: a reference to structure in value position.
- **`:by` as a level-2 cell,** from the relationship edge to the column edge: the two edges are not parallel, and levels stay globular (a cell sits between parallel cells).
- **Two edges per foreign key,** a column edge `@/parent_id/T.#UUID7` and a relationship edge, or both at field level (`parent_id` to `id`): two names for one fact, and the types could mismatch. The foreign-key row draws the same arrow from one edge.
- **`:fk`:** the header kind already says it.
- **Interpolated default names** (`{.edge+ :snakecase}_id`): braces open blocks; the foreign-key row's default label replaces it.
- **Foreign keys only to the `:pk`:** SQL allows a unique key, and `:refs` states it as a proof, without touching the declaration.

---

## 14. Operators between chains, 2026-11-02

Decided while planning the parser (plan step 4). The proof layer will add operators between chains beside `==` and `~=`, mostly infix (connectives, perhaps an order), with a prefix not; about 6 to 10 of them is a realistic ceiling. What they mean stays open, as equations do; this section only settles how they are read.

### 14.1 Decided

- **One level, strict left to right.** All operators between chains share one precedence level, looser than the chain infixes and tighter than `,`. There is no precedence among them.
- **Same is fine, different needs a group.** A run may repeat one operator: `f == g == h`. Different operators without a group are an error: `f == g ~= h` is rejected, `(f == g) ~= h` is not. Carbon and Pony do the same. The parser reads any run; the analyser rejects mixed ones.
- **A prefix takes the operand after it:** a future not on `a == b` is written with a group, `not (a == b)`.
- **Recursive descent, no Pratt parser.** With one level there is nothing for binding powers to resolve: an item is a loop, `chain { operator chain }`, like the chains themselves. Adding an operator adds a token and a message.
- **One flat CST node** for a run, its operands in a list and its operators the tokens between them, as with chains. It replaces the `equation` node.

### 14.2 Rejected

- **A Pratt parser with a precedence table:** worth it for many operators at many levels; here it would resolve nothing, and its binary trees would have to be flattened again.
- **Plain left to right, mixing allowed:** unambiguous, but `a == b implies c == d` would read `((a == b) implies c) == d`.
- **Precedence among the connectives** (not over and over or over implies): a rule every reader has to remember; a group says the same thing in the program.


---

## 15. Reserved and unsupported, 2026-11-02

Decided while designing the analyser (plan step 5). Some programs have no meaning yet: either the spec has not decided one, or the compiler does not implement it yet. Both are said plainly, and differently, because what is missing differs.

### 15.1 Decided

- **Every program has a meaning or a diagnostic.** There is nothing in between: no undefined behaviour, and no implementation-defined meaning.
- **Reserved: the spec has not decided.** A construct whose meaning is an open question, such as declaring a node (`#User :: …`) or an edge (`review :: …`), is an error, marked *reserved* in the spec's error tables and listed under Open questions. Rejecting it is forward compatible: lifting an error never breaks a program, while changing an accepted meaning would. The message says the meaning is open, so the user knows the program is not wrong, only early. Reserved errors may ship; they are the language's answer until the spec decides.
- **Unsupported: the compiler has not caught up.** A construct the spec defines and the compiler does not implement yet, such as levels above the first or the contents of a definition, is reported with its own severity, `unsupported`. It is not an error about the program, so it never changes the status or the exit code, is never promoted, and the IR is still handed out, with the skipped parts left out rather than marked as holes, since nothing in them failed. It is reported once per skipped construct (a level, a definition), never once per element inside it.
- **Unsupported never ships.** It is scaffolding for the plan: each unsupported diagnostic names the step that removes it, and the spec never mentions one. A release build refuses to compile while any remains, so no released compiler skips part of a valid program.

### 15.2 Rejected

- **Undefined behaviour:** it means the compiler may assume something never happens. fAB has no runtime, so there is nothing to assume, and every program is either a diagram or rejected.
- **Implementation-defined meaning:** programs would come to depend on what this compiler happens to do, and the spec would inherit it.
- **Unsupported as an error:** a valid program would be reported as wrong, and the examples could not draw until every step had landed.
- **Unsupported as a warning:** it would mix with warnings about the user's program, and promoting warnings would fail a valid program for a gap in the compiler.

### 15.3 Drawing them, 2026-11-03

**Decided.** Every program draws something (the spec, Errors): diagnostics mark their elements, each diagram has a border in the colour of its most severe one, and a statement that names no diagram draws a placeholder, a small square crossed corner to corner. Unsupported is drawn the same way, in its own colour, below error and warning, with the label "unsupported" above the diagram whenever one is present, even when the border is red. A diagram with skipped parts still draws what is supported (`G :: +(f, g)+ | f/α/g` draws level 1), and a definition about a diagram (`G :style := …`) marks that diagram rather than drawing a square of its own: you see as much as the compiler can draw, and the label says it is incomplete. Since unsupported never ships, this is for testing only.

**Rejected.** Replacing a diagram with skipped parts by the placeholder: one line of style would turn a whole diagram into a square.

### 15.4 Statements with syntax errors, 2026-11-03

The parser recovers by skipping to the next statement, and keeps what it read before the error. Analysing that remnant drew wrong diagrams with no mark: `H :: g /k` drew H without `k`, `G :: f/ /g` drew `f` undirected. A statement the parser dropped whole (`G :: f(g)`) declared nothing, so `H :: G.+f/x` reported a second error, a cascade.

**Decided.**

- **Ownership by range.** A syntax error belongs to the statement from whose first token up to the next statement's it lies, so the tail the parser skipped belongs to the statement it cut short.
- **A broken statement is not read.** It draws the placeholder, bordered by its errors. When its head names a diagram, the diagram is declared, as broken: it is drawn as that placeholder, and references into it are holes with no error of their own, as any cascade.
- **Issues reach syntax errors.** An issue names the list its error is in, syntax or analysis, so a placeholder can be marked by the syntax error that made it, and no diagnostic is copied.

**Coming.** Recovery item by item inside braces (the spec, Open questions): the parser already recovers at each `,` there, so the good items could be drawn, with the broken one as a hole. It needs a meaning for a hole attached to nothing, and is the next large change to recovery.

**Rejected.**

- Analysing what the parser kept, with a red border: it draws what was not written (`f` undirected, `g` missing) with confidence, and a truncated tree has errors of its own.
- Ownership by the statement's own tokens: the skipped tail lies outside them, which is how the wrong drawings went unmarked.
- Copying syntax errors into the analyser's list: two copies of one diagnostic, free to drift.

## 16. Levels, 2026-11-03

Revises section 3 for the implementation of levels (plan step 7).

### 16.1 Decided

- **Level k is level 1 one dimension up.** Each diagram keeps one table of names with their levels; named nodes are level 0. At level k a new name is a k-cell, a name of level k−1 is a side, standing as a named node does at level 1, and any other level is an error ("side from the wrong level", "declared twice").
- **No unnamed sides.** Level 1 nodes may be unnamed because nodes are derived; above it a node is a (k−1)-cell, an edge one level down, and fAB has no nameless edges. An unnamed node at level k would be an undeclared generator of the polygraph, with no boundary. The row is *unnamed side*, not *anonymous cell*: in `f/α β/g` the cells are named, and the missing thing is the side between them.
- **No pinches above level 1.** A pinch merges unnamed ends; above level 1 there are none, so a pinch there is an error, never a synonym (`+α` for f).
- **Not a cell.** Named nodes, `@`, `*`, `?`, `!` and other diagrams' nodes belong to level 1.
- **The space is legal above level 1.** `f/α g/β/h` is α : f ⇒ g and β : g ⇒ h: the space lands on g, which is named. Both spellings of vertical composition are fAB.
- **Describe once, draw what fits.** A flow has cells like any diagram and draws none of them; nothing forbids them. Drawing follows the kind; declarations describe the whole system.
- **No union-find above level 1.** Every side is named, and nothing glues ends later (no pinches, no references), so each end of a cell is settled in its own term: it lands on a side, meets another open end (an unnamed side, reported where they meet), meets a different side (two names for one side), or is left open (an unnamed side, at the cell's name). `α/β` reports two unnamed sides: it lacks two 1-cells. Edges and cells are one kind of name, a generator with a level and two sides.
- **Two names for one side** keeps both cells as written: above level 1 there is nothing to merge, since each cell already has its sides.
- **Declared twice** is one rule for edges and cells: the same rule, one dimension up.
- **Parallel is judged on the final graph** (plan step 7c), once every diagram is elaborated: a later diagram can merge nodes, and merges only make more cells parallel, never fewer. The error is at the cell's name, and the cell stays drawn, marked.
- **A cell on an undirected edge is reserved.** An undirected edge has no source and target to be parallel by. Undirected edges stay legal everywhere: they describe a relation, and whether a commutative diagram refuses to draw one is a contextual error, decided with the header.

### 16.2 Rejected

- Forbidding cells in flows: the relations exist whatever the diagram shows, and the program states them once.
- Forbidding the space above level 1: it breaks "the same grammar one dimension up" for no gain in meaning.
- The header in this step: the header's scope and syntax are tied to the CLI, so it waits until fab-core is complete.
