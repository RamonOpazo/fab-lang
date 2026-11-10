# fAB design decisions, 2026-10-23

Decisions taken in the design sessions of 22-23 October 2026, after `fab render` first worked end to end. They change the grammar in six places: statements and bindings, values, cells (levels), the `/` operator, pinching (with the split between flow and fusion), and subjects (classes). This note is the record of what was decided and why; the code does not implement it yet.

> **Superseded in part.** Sections 4 and 5, and the matching parts of 7, are replaced by the grammar of joining of 1 November ([`joining.md`](joining.md)); sections 9 and 11 by the plan in [`CLAUDE.md`](../CLAUDE.md). Section 12 (1 November) replaces how statements span lines (3) and how entries are delimited (1.3). Section 13 (1 November) settles the schema statements left open in 8.3; section 14 (2 November), how operators between chains are read; section 15 (2 November), how programs with no meaning yet are reported; section 21 (3 November), the types and the prelude, which revise 1.7 and 2; section 22 (5 November), the three forms, typed records and the style pass, which revise 1.1–1.3, 12, 17, 19 and 21. They are kept for the record. Where this note and [`spec.md`](spec.md) differ, the spec wins.

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
| `:attr`         | a new attribute, everywhere       | `:terminal := { :shape [circle], :fill [red] }`                                                    |
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
- An entry with no subject, `:attr v`, binds the owner itself: `&node :style := { :shape [circle], :ink [black] }` binds `&node :shape` and `&node :ink`.
- **Inside blocks, entries use the light form, without `:=`.** `:=` appears once per statement, at the top level, so every binding statement is visible at the left margin.
- **Entries are delimited by their values.** Values are never bare, so a bare name after an attribute always starts a new entry: `#Done :terminal  f :label "x"` is two entries. (Added in the spec.) (Revised in 19: an entry has one attribute, and several go in braces.)
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
- **Attributes (bundles):** `:terminal := { :shape [circle], :fill [red] }`. A bundle is a named element of the Attrs monoid. Using it lays its contents over the cascade, exactly like writing them, so `#Done :terminal :fill [green]` works, and the later setting wins. This is the `:=` user-defined attribute that was postponed during the format-layer discussion ("expand in place").
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
- **Unsupported never ships.** It is scaffolding for the plan: each unsupported diagnostic names the step that removes it, and the spec never mentions one. A stable build refuses to compile while any remains, so no released compiler skips part of a valid program; a dev build admits them, marked `incomplete` (§22.16).

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

- **Level k is level 1 one dimension up.** Each diagram keeps one table of names with their levels; named nodes are level 0. At level k a new name is a k-cell, a name of level k−1 is a side, standing as a named node does at level 1, and any other level is an error ("side from the wrong level", "declared twice"). (Revised in 16.3: a lower level is an identity side.)
- **No unnamed sides.** Level 1 nodes may be unnamed because nodes are derived; above it a node is a (k−1)-cell, an edge one level down, and fAB has no nameless edges. An unnamed node at level k would be an undeclared generator of the polygraph, with no boundary. The row is *unnamed side*, not *anonymous cell*: in `f/α β/g` the cells are named, and the missing thing is the side between them.
- **No pinches above level 1.** A pinch merges unnamed ends; above level 1 there are none, so a pinch there is an error, never a synonym (`+α` for f).
- **Not a cell.** Named nodes, `@`, `*`, `?`, `!` and other diagrams' nodes belong to level 1.
- **The space is legal above level 1.** `f/α g/β/h` is α : f ⇒ g and β : g ⇒ h: the space lands on g, which is named. Both spellings of vertical composition are fAB.
- **Describe once, draw what fits.** A flow has cells like any diagram and draws none of them; nothing forbids them. Drawing follows the kind; declarations describe the whole system.
- **No union-find above level 1.** Every side is named, and nothing glues ends later (no pinches, no references), so each end of a cell is settled in its own term: it lands on a side, meets another open end (an unnamed side, reported where they meet), meets a different side (two names for one side), or is left open (an unnamed side, at the cell's name). `α/β` reports two unnamed sides: it lacks two 1-cells. Edges and cells are one kind of name, a generator with a level and two sides.
- **Two names for one side** keeps both cells as written: above level 1 there is nothing to merge, since each cell already has its sides.
- **Declared twice** is one rule for edges and cells: the same rule, one dimension up.
- **Parallel is judged on the final graph** (plan step 7c), once every diagram is elaborated: a later diagram can merge nodes, and merges only make more cells parallel, never fewer. The error is at the cell's name, and the cell stays drawn, marked.
- **A cell on an undirected edge is reserved.** An undirected edge has no source and target to be parallel by. Undirected edges stay legal everywhere: they describe a relation, and whether a commutative diagram refuses to draw one is a contextual error, decided with the header. (Revised in 16.3: allowed, and a restriction may flag it, section 17.)

### 16.2 Rejected

- Forbidding cells in flows: the relations exist whatever the diagram shows, and the program states them once.
- Forbidding the space above level 1: it breaks "the same grammar one dimension up" for no gain in meaning.
- The header in this step: the header's scope and syntax are tied to the CLI, so it waits until fab-core is complete.

### 16.3 Identity and undirected sides, 2026-11-03

Revises 16.1 (plan step 7d). The principle: the analyser describes the largest structure that still has a reading, and restrictions narrow it (section 17). Full freedom has no structure to draw; full strictness is a small set of shapes. fAB sits between them.

- **A side may come from any lower level.** At level k, a name of level j < k−1 stands for its identity at level k−1: every cell x has an identity 1_x one level up, so this is plain category theory, not a relaxation. `#A/f/#A | f/α/#A` is α : f ⇒ 1_A; `+(f, g)+ | f/(α, β)/g | α/m/f` is m : α ⇛ 1_f. Named nodes and `@` are level 0, so they are sides at every level above 1. `*`, `?`, `!` and other diagrams' nodes are still not cells.
- **Side from the wrong level goes.** Levels are read in order, so a name of level k or above is a cell of this level, and using it again is *declared twice*, as at level 1. A named node or `@` not made at level 1 is *side not declared*: only level 1 makes nodes.
- **Parallel uses the identities' boundaries.** 1_x has source x and target x, so α : f ⇒ 1_A needs f : A → A, and m : α ⇛ 1_f needs α : f ⇒ f. A non-parallel cell stays an error: parallelism is what makes a cell a cell, while a direction is only a property of a side.
- **Undirected sides are allowed.** An undirected edge relates two nodes in no order, so a cell on it is parallel when the endpoints agree as an unordered pair: undirected f between A and B is parallel to g : B → A. Lifts the reserved row *cell on an undirected edge*.
- **Undirected cells are allowed,** spelled as at level 1: a trailing `/` ends a chain of one cell, `f/α/g/`. A cell is its own way back. `f/α/` alone still lacks a side (unnamed side).
- **Neither is category theory,** and neither is an error in the analyser. A restriction that proves against a category flags them (section 17); the IR keeps each cell's direction, so it can.

### 16.4 Rejected

- Undirected cells and cells on undirected edges as errors: they describe relations a diagram may hold, and forbidding them in the analyser decides for every kind what only some kinds refuse.
- Non-parallel cells as a restriction finding: a cell is a relation between parallel cells, and without that it is no structure at all.

## 17. Restrictions and passes, 2026-11-03 (planned)

Planned with the proof shells (plan step 11); nothing here is implemented. Revises the open question on the header's errors by kind.

- **The analyser describes, restrictions narrow.** Declarations accept every structure with a reading (16.3). A restriction turns some of them into findings: the kind states what the graph is proved against, and the proof layer narrows further.
- **The kind is stated in the proof:** `G :prove := { :kind [cd], … }`. An entry with no subject binds the block's owner (1.3), so this is `G :kind`; `@` would be G's own node, and a class for the diagram itself (`&self`) would say again what the empty subject says. A proof is like a paper about the relations declared: it says what kind of thing they are, and that one statement decides three things, so no second attribute is needed: the kind of graph (what is drawn), the proofs that may be posited (which attributes the proof layer accepts), and which structures are promoted to findings. The same attribute may be given at the header, `G :kind := [cd]`, with the same name; the local one, in the proof, wins. The header comes late (it needs a stable CLI), so the proof's `:kind` is the one implemented first.
- **No kind, no restrictions.** A diagram without a `:kind` is a plain graph: everything declared is drawn, and nothing becomes a finding.
- **Findings are classed by reason, and the reason sets the severity.** A restriction never chooses a severity; it chooses the reason, so a pass written against a reason never breaks when severities move.

| Class | Meaning | Severity |
|---|---|---|
| `&refutable` | the structure contradicts the kind's rules, so the proof must take it as false (an undirected cell in a category) | error |
| `&undecidable` | the structure has no check in the kind, because it does not belong to it: neither provable nor refutable there | warning |

- **Narrower classes name the structure,** one per finding, beneath its reason: `&undirected_cell`, `&undirected_side`, and so on. The general and the specific live together, by the style layer's specificity: reason, structure, then one element.
- **`:pass` acknowledges a finding,** with an optional literal for the reason:

  ```
  G :prove := {
    :kind [cd],
    &undirected_side :pass,
    α :pass "a relation, not a morphism",
    &undecidable :pass
  }
  ```

- **A pass reaches only findings.** Language errors (an undeclared reference, an unnamed side, a non-parallel cell) belong to no finding class, and nothing can name them, so no pass quiets them, by construction.
- **A pass leaves a trace.** It never changes the exit code; `fab check` keeps it as a note, with its reason, and the drawing loses its mark.
- **A pass that matches nothing warns,** so acknowledgements cannot go stale silently.

**Rejected.** `&unprovable` for the error class: in logic it includes the undecidable too, while *refutable* says exactly "provably false". `:env` beside `:kind`: two names for what the graph is. `&errors` and `&warnings` as classes: they name how loud a finding is, which depends on the restriction, and `&errors :pass` would reach language errors too.

## 18. Drawing issues, and the renderers, 2026-11-03

How 15.3 is drawn (plan step 6).

### 18.1 Decided

- **Starts and ends are told apart in the style pass, not the IR.** The IR has one kind, the null node; `&start` and `&end` are classes, derived from the edges: a null node an edge arrives at is an end, any other a start. The IR already says which way each edge goes, so a kind would state it twice, and `*/f/` (an undirected edge) has neither: the style pass draws it as it likes. A JSON reader derives it with the same rule.
- **Severities reach the style pass as a list, one per issue.** The IR does not know the tolerance: under `--strict` a warning is promoted, and its border turns red. `Compilation.sheet()` computes the severities and hands them to the style pass beside the IR, so the style pass stays a function of both, testable without compiling, and `format/` does not depend on `compile/`.
- **Marks always win.** They are applied last, over kind defaults, themes and the program's style. An issue has no name in fAB, so no program can address, restyle or hide one: `g :stroke [green]` on an edge marked by an error is drawn in the error's colour, and `:stroke [none]` on a broken diagram keeps its border. What can change is the theme token for each severity.
- **Severity colours are theme tokens** shared by every backend: error, warning, unsupported.
- **A placeholder in DOT is a square with the glyph ✕** (U+2715), in its border's colour. Graphviz has no square crossed corner to corner, and ╳ (U+2573) is too narrow to reach the corners; the native renderer draws the exact shape. (Tried on 3 November.)
- **The caption is part of the Style,** text and colour: "unsupported" in the unsupported colour, even under a red frame. Backends realize it and never decide it; DOT writes an HTML label only for a captioned cluster.
- **Graphviz is a convenience.** The renderers that matter are fAB's own, native and TikZ, which come later and draw what the spec describes. The Graphviz backend should look reasonable and be correct about structure, but its layout (askew graphs, odd curves) is not worth tuning: effort goes into the IR, the style pass and the native renderer.

### 18.2 Rejected

- `&start` and `&end` as IR kinds: a derived fact stored twice, and undefined on undirected edges.
- The style pass reading the `Compilation`: a dependency upward, and tests that need a whole compilation.
- Letting the program style marks: an error could be painted over.
- Graphviz's `Msquare` or `style=diagonals` for the placeholder (its corners are cut, not crossed), the glyph ╳ (too narrow), and an HTML label drawing the cross (fragile across Graphviz versions).

## 19. One attribute per entry, 2026-11-03

Revises 1.3 and 12.

### 19.1 Decided

- **An entry has one attribute, or a block.** Several attributes of one subject go in braces, the block that already factors a subject: `retry { :arrow [/dashed/>], :bend [inner] }`. The grammar's `entry` loses `{ attr }`.
- **The comma always means "next entry".** It ends an entry and its subject, and an entry with no subject binds the owner (1.3). Side by side, `retry :arrow [/dashed/>] :bend [inner]`, was the only place where a space separated two things of one kind, and a reader had to know that values delimit entries.
- **Side by side is an error, never a missing comma.** Recovering by assuming a comma would change the meaning in silence: in `Order :style := { retry :arrow [/dashed/>] :bend [inner] }`, an assumed comma makes `:bend` bind Order. The error's hint gives the braces.
- **Right after `:=` the comma suffices,** since the owner is the subject: `User :style := :label "users", :fill [muted]` binds both to User, and `:ref := :shape [round], :fill [muted]` both to the bundle. Braces work there too.
- **Inside a block, braces nest:** `Repo :style := { #Head { :ref, :label "main" }, … }`. A block holds items, so its entries are separated by commas on one line or several.

### 19.2 Rejected

- **Keeping attributes side by side:** shorter for two attributes, but it gives the space a second meaning, and the comma two (next attribute of this subject, or next subject).
- **Parentheses for a group of attributes,** `retry (:arrow [/dashed/>], :bend [inner])`: parentheses already group subjects (`(yes, paid) :label "yes"`) and terms; braces already factor a subject.
- **The rule only at the top level:** there the comma already means the same as side by side, so the problem is only inside blocks.

## 20. The examples, drawn, 2026-11-03

How step 6 ends (plan step 6c).

- **The own node is labelled with its diagram's name,** unless `:label` gives one: `@` stands for the diagram itself (`User :: @/(id/T.#UUID7, …)` draws a node `User`). It is named, so it has no canonical end to fall back on.
- **A diagram with no nodes of its own still shows its mark.** Db, whose edges all join other diagrams' nodes, owns no node, and a Graphviz cluster is a set of nodes, so the frame of an issue on Db had nothing to surround. The IR and the style pass were right; DOT now draws the frame, name and caption around one invisible point, and Db's edges stay where they are. The native renderer frames the edges themselves.
- **A definition that names no diagram** (a bundle, a value, a theme) draws its placeholder while it is unsupported (15.3), labelled by its head (`:ref`). It is for development only, and goes with step 8.
- **The examples are checked and drawn by one target,** `make examples`: every example must check with no error and no warning (unsupported is allowed until steps 8–11), and is then drawn to SVG beside it, with Graphviz. `make test examples` runs both.


## 21. Types and the prelude, 2026-11-03

Revises 1.7 and 2, `style.md` §3 (value types, the bracket reading), §4.6 (arrows) and §7 (themes and the prelude), and the spec's Values and definitions. The prelude it describes is drafted in [`prelude.fab`](prelude.fab). Plan step 8 implements it.

### 21.1 Decided

**Four sorts of name,** told apart by their spelling, so no word is reserved:

| Sort | Spelled | Examples |
| --- | --- | --- |
| Types | `:UpperCamel` | `:Color`, `:Shape`, `:Arrow`, `:Cardinality` |
| Functions (attributes) | `:lowercase-kebab` | `:fill`, `:label-at`, `:terminal` |
| Named values and labels | `[lowercase-kebab]` | `[red]`, `[circle]`, `[epi]`, `[base]` |
| Symbols | glyphs, with at most one capital letter | `[>]`, `[|>]`, `[X]`, `[O{]`, `[⊸]` |

**The constructors are closed; the names are open.** The language fixes the kinds of type. Every name of a type, a label or a function lives in source, the prelude's or a program's:

| Constructor | Written | Its type, read from the value |
| --- | --- | --- |
| `:Text`, `:Math` | `"…"`, `$…$` | the delimiters |
| `:Color` | `[#c0392b]`, `[#f00]` | `#` |
| `:Number` | `[2]`, `[0.5]`, `[30!]` | a digit |
| `:Range` | `[0..*]`, `[1..3]` | `..` |
| `:Flag` | written or not: `:hide`, `:hide!` | |
| `:Tuple.(T, U, …)` | `[a/b/c]` | its elements' types |
| `:List.(T)` | `[a/b/c]`, `[]` | a contract, never read |
| `:Union.(T, U, …)` | any value of one of its types | a contract, never read |
| `:Record` | `{ … }` | the braces |
| labels | `:Shape :: [circle], [box]` | the label's own type |

- **Every value has a type, and every name.** A type is read from the value's shape, as the table says, or from the name's definition. Nothing is inferred from use.
- **A type written in a definition is a contract:** `:Color [red] := [#d1242f]`. It is optional, and checked when given: `:Color [warn] := [circle]` is an error. It is also what the LSP completes from.
- **Aliases name types:** `:Arrow := :Tuple.(:Head, :Union.(:Line, :None), :Head)`, `:Length := :Number`. An alias is the same type under a second name, never a new one.
- **Type parameters use `.` and a group,** as qualification does: `:List.(:Record)`.

**Labels: `:Type :: [a], [b]`.** A declaration with a type as its head creates labels of that type: values with no definition, whose meaning a renderer gives (`[circle]`) or a record binds (`[ink]`, below). `::` because the labels are new: nothing is bound to them. Several lines go in braces, as any long statement: `:Shape :: { [box], … }`.

- **One label, one type.** Declaring a label already declared in another type is an error. Words two types share get a type of their own, which both include: `:Facing :: [outer], [inner]`, `:Side := :Union.(:Facing, :On)`, and `:bend` takes `:Union.(:Facing, :Angle)`. Where the words mean the same, the types merge instead: `:align` and `:label-at` share `:Span :: [start], [center], [end]` (`[mid]` became `[center]`).
- **Nothing on its own is a label of its type:** `:shape [none]`, `:line [none]`, both through `:None :: [none]`. No label is the empty text, `:label ""`.

**Symbols draw from an allowlist:** Its glyphs are ASCII punctuation (less `/`, `!`, `#`, `[` and `]`, which a bracket uses itself) and the Unicode blocks of arrows, mathematical operators and geometric symbols: U+2190–23FF, U+25A0–27FF, U+2900–2BFF. Never a space, a control, a combining mark or a letter of any script; an allowlist, so nothing new in Unicode slips in. **Colours** take 3, 4, 6 or 8 hex digits; without alpha, opaque.

**Sequences: `[a/b/c]`.** `/` separates the elements of a bracket, everywhere.

- **What is written is a tuple:** `[1/1.5/2]` is `:Tuple.(:Number, :Number, :Number)`. A tuple whose elements share a type fits where `:List.(T)` is expected, and a single value fits a list of one: `:theme [dark]`, `:theme [dark/compact]`.
- **An empty slot is nothing there,** in tuples and lists alike: `[/solid/>]` has no tail, `[////1/2]` is six elements, four of them empty. It is the only "none", and it exists only inside a sequence.
- **`[]` is the empty list,** not a none: `:theme []`.
- **One level:** a bracket is one token, so sequences do not nest. Nothing needs nesting.
- **Arrows and cardinalities are tuples with names:** `:Arrow`, `:Cardinality := :Tuple.(:Range, :Range)`. The rule "two slashes make an arrow" goes; the type the function expects decides.
- **`!` inverts the element it follows,** as before (2): a struck line `[/solid!/>]`, an inner hook `[?!/solid/>]`, an inward angle `[30!]`.

**Numbers: one `:Number`, an exact decimal.** fAB does no arithmetic, so a number goes from the source to a renderer unchanged: a whole mantissa and a count of decimal places (`1.5` is 15 and 1). It is exact, compares exactly against the ranges functions check (a fraction is 0 to 1), and prints as written in JSON and DOT. A renderer converts to a float when it lays out geometry, and only then. Digits on both sides of a point (`[.5]` and `[1.]` are errors), no exponent, at most 18 digits from the first nonzero one, so mantissa and scale fit 64 bits. Normalised, and printed so: `1.50` is `1.5`. `:Length`, `:Angle` and `:Fraction` are aliases: the unit is the function's.

**Functions: `subject :function :: type`.** A declaration with a function as its head and a type as its body states where the function applies and what it takes: `(&node, &zone) :fill :: :Color`. Anywhere else it is "does not apply". Zig gives each function its meaning; a function or a label a renderer does not know is a renderer issue ("no drawing for `[hexagon]`"), drawn with the type's fallback and marked like any other.

**Flags are true when written, false otherwise:** `:hide`. `!` after a flag inverts it, so a later layer can turn it off: `f :hide!`. Only a flag inverts; a value given to a flag is an error.

**Records: `{ … }`, keyed by subjects, functions and labels.** A record entry is a key and its value:

- a function: `:fill [red]` (a bundle's contents, an element's style);
- a subject: `&node :stroke [ink]`, short for `&node { :stroke [ink] }` (a style, a theme);
- a label, bound to a value of its own type: `[ink] [#dddddd]`. This is how themes set tokens, and why records have structure where sequences have none. `[circle] [box]` is legal too: in this theme, circles are drawn as boxes.

So **a theme is a record**, `:Record [dark] := { … }`, and `:theme` takes `:List.(:Record)`. `G :style := { … }` is a record bound to a diagram. A bundle still names a function, not a value: `:terminal := { :shape [circle] }` is used as `#Done :terminal`, and its record's keys must be functions.

**The prelude is ordinary fAB,** with no powers a program lacks. It is read first, so its names come first, and defining one again is "defined twice"; "built-in redefined" goes. A program may declare labels, functions and types as the prelude does; what no renderer knows, a renderer reports. The prelude is what users trust, and tinkerers may change it.

**`[base]` is the base theme,** the one name the style pass looks up. It always applies, first. Defaults that depend on the element (a node's label, a cell's arrow by level, one circle diameter per diagram) are computed by the style pass and sit below it:

```
computed  <  [base]  <  themes, left to right  <  the program
```

`[base]` binds nothing computed, or it would hide it; the prelude names the computed defaults in comments, where their bindings would be. `[base]` binds the tokens, so a renderer never falls back on a colour of its own.

### 21.2 Consequences for the code

- **Lexer:** `:Color` is a type token (today `:` is invalid before a capital); `[]` is the empty list (today invalid); `!` touching an attribute on its right is a flag's inversion. Symbols are any characters but whitespace, `[`, `]` and `/`, as values already are.
- **Parser:** a declaration's head may be a type (labels) or a subject and a function (a signature); a definition's head may be a type and a name (`:Color [red]`); a record entry's key may be a label; `:Type.( … )` is a type expression.
- **Analyser:** an environment of types, labels, functions and named values, each defined once and before its use, the prelude's first; types read from shape, contracts checked, unions and lists matched against tuples; "does not apply" from signatures.
- **Formatter:** the base theme stops being hard-coded (`kindDefault`): it is `[base]`, read from the prelude. What stays in Zig is the meaning of each function and label, and the computed defaults.

### 21.3 Errors

New: **contract broken** (`:Color [warn] := [circle]`), **label in two types** (`[outer]` declared again), **not a type** (`:Colour [x] := …`), **type in a diagram's declaration** (`G :: f :Color`; with the renamed **entry**, **class** and **value in a diagram's declaration**: a declaration is a diagram's, a type's or a function's, each with its own body), **value given to a flag** (`:hide [on]`), **only a flag inverts** (`:fill!`), **key of the wrong type** (`[ink] [circle]` in a record), **wrong type parameters** (`:List`, `:Color.(:Text)`), **not a label** (`:Shape :: [#f00]`), **labels on structure** (`:Arrow :: [x]`), **subject in a bundle** (`:t := { &node :fill [red] }`: a bundle's keys are functions), **number malformed** (`[.5]`, `[1.]`, too many digits). Gone: **built-in redefined**, and **theme and bundle mixed up**, which becomes an ordinary type error ("a function where a record is expected").

### 21.4 Rejected

- **Keywords in Zig** (`[circle]` and `[dashed]` built in, outside the prelude): the language has no keywords, and the prelude should show every name a program can use.
- **Types through functions** (`:ink [red] := …`, a value typed by the function it fits): functions share types (`:ink`, `:fill`, `:stroke`), so the function named would be arbitrary, and it gives types no names to contract on.
- **A label in several types, chosen by context** (`[outer]` both a `:Bow` and a `:Side`): too much overloading, and a name defined with no type written becomes ambiguous.
- **One label in one type, others including it** (`:Side := :Union.(:Bow, :On)`): awkward once the including type is no longer a superset in meaning. A shared type of its own, named for what the words share, says why both take them.
- **`[]` as none:** it is the empty list. None is only an empty slot; alone, each type has its own nothing.
- **`[on]` and `[off]` for flags:** `!` already inverts what it follows.
- **Floats:** fAB never computes with numbers, so exact decimals cost nothing and keep output deterministic.
- **A prelude with privileges** (labels declared only there): the prelude is what users trust, not what binds them.

### 21.5 Open

- **The prelude's contents** beyond the draft: more colour names, more themes, whether `[base]`'s sizes are right.
- **Records under `:prove`** hold propositions (`f h == g k`), which are not key–value entries; whether a proof block is a `:Record` waits for the equations.
- **A renderer's fallback per type** (which shape stands in for an unknown one): with step 10.

### 21.6 Records, 2026-11-03

What each record checks, before the style pass reads it (step 9).

- **A theme's subjects are classes:** `&node`, `(&edge, &cell)`. A theme applies to any diagram, so it names no element: `G.f` or `G.&edge` in a theme is **element in a theme**. A subject's block holds its functions; a class subject inside it is a narrower subject, its own classes.
- **A function with no subject in a theme binds its owner,** the diagram the theme is applied to: `:Record [paper] := { :fill [white] }` fills the diagram. So it must apply to `&zone`.
- **A bundle's signature is computed:** a flag that applies where all its contents apply, the intersection of their classes. `:terminal := { :shape [circle], :fill [red] }` applies to `&node`; `{ :fill [red], :arrow [mono] }` applies nowhere, and its second key **does not apply**. A bundle's keys are functions, so a subject or a token in a bundle is **subject in a bundle**. A bundle is used as a flag, never inverted: `:terminal!` is **only a flag inverts**.
- **"Does not apply" reads the class hierarchy:** `&plain`, `&choice`, `&parallel`, `&start`, `&end`, `&hole` and `&canonical` lie inside `&node`. A function applies to the classes its signature names and to the classes inside them: `:line`, declared for `&node`, applies to `&hole`; one declared for `&choice` only does not apply to `&node`.
- **A function entry** is checked against its signature: known (**unknown attribute**), applying to its subject's classes (**does not apply**), a flag with no value (**value given to a flag**) and any other with one (**value missing**), `!` only on a flag (**only a flag inverts**), and its value fitting the type (**wrong type**).
- **A token** binds a label to a value of the label's type: the key is a declared label (**not a label**, **undefined name**), the value fits its type (**key of the wrong type**).

## 22. Three forms, typed records, and the style pass, 2026-11-05

Revises 1.1–1.3, 12 (the comma after `:=`), 17 (the proof's shape), 19, and 21 (`[]`, `:None`, `:Record`, tables, records). Settles the design of plan step 9, and plans the proof's shape for step 11.

### 22.1 Three forms

**`:` is the one sign of assignment, and a statement has one of three forms,** named by what it does:

| Form | Operator | Does | Examples |
| --- | --- | --- | --- |
| Declaration | `::` | introduces something new, binding nothing | `G :: f g`, `:Shape :: [circle], [box]`, `(&node, &zone) :fill :: :Color` |
| Naming | `:=` | binds a name to a value | `[red] := [#d1242f]`, `:Length := :Number`, `:terminal := { … }`, `:Style [dark] := { … }` |
| Description | none | `context :descriptor value`: says something of a context | `G :style { … }`, `G.f :arrow [mono]`, `Order :theme [dark]` |

- **A descriptor is an attribute applied:** `:fill`, `:style`, `:lemma`. A description names nothing, so it needs no operator; the descriptor stands where `:=` stood. `G :style := { … }` and `G.f :arrow := [epi]` are errors (**description written with `:=`**).
- **A reference is a description without its value:** `G.#Done :shape`, `Repo :lemma.[a]`.
- **The three forms nest.** Inside braces, a description is the usual entry; a naming binds a name in that record only (`[ink] := [#dddddd]` in a theme, 22.3); a declaration declares inside the type being declared (`:Style :: { &node :fill :: :Color, … }`, 22.3).
- **A context may be left out only inside a block,** where it is the block's owner, written on the line above: `Order :style { :caption "Orders", &node :fill [muted] }` binds `Order :caption`. At the top level the context is always written.
- **The owner's descriptors come first in a block,** before any entry that names a context. Otherwise it is a style warning (**owner described after a part**): the block reads as its owner, then its parts.
- **Descriptions lose the comma form** of 19.1: with no `:=`, `User :style :label "users", :fill [muted]` is two entries side by side. Braces group them: `User :style { :label "users", :fill [muted] }`, or `User { … }`. A naming keeps it: `:ref := :shape [round], :fill [muted]`.
- **A descriptor may be written outside its layer:** `G :fill [white]` is `G :style { :fill [white] }`. Each descriptor belongs to one record type (22.3), so it is never ambiguous which layer it is in.

**Rejected.**
- **Typed layer statements,** `G :Style :: { … }`. A type would stand where a descriptor goes, meaning "G's style", which is a descriptor's job; and `::` binds nothing, while a style binds values. The typing goes on the value instead (22.3).
- **Contexts left out at the top level:** the owner would be invisible.
- **"Owner first" as an error:** it is good practice, not meaning.

**Implemented (plan step 9a, 6 November).**
- **A descriptor's value may be a record:** `attr = ATTR_ID [key] [!] [literal | ( items ) | block]`. The grammar named `G :style { … }` an entry but gave `attr` no block, so the rule now reads as the examples do. A description is then one entry, `context attr`, and the parser takes an entry with no operator as a statement.
- **Two errors the forms imply:** a top-level description with no context is **description with no context** (`:fill [red]`), and `::` inside a record that is not a type being declared is **declaration in a record** (`:Style [x] := { [ink] :: :Color }`). A token written the old way, `[ink] [#dddddd]`, is two terms side by side, so it is a **bare term in a record**.
- **A description written with `:=`** has its body checked as a description's would be, since what it meant is plain.
- **`{}` as a value** (`G :style {}`) waits for 9b, with the record types it fits; until then empty braces stay a syntax error everywhere.

### 22.2 Nil, and the elements of a bracket

**A bracket has one element more than it has slashes, and an element with nothing in it is nil.**

- `[red]`, `[2.5]`, `[#f00]` are one element: the value itself. **There are no one-element lists.**
- `[]` is one empty element: **nil**. There are no zero-element brackets, so the reader never yields none.
- `[/]` is two nils; `[/solid/>]` is nil, `solid` and `>`; `[////1/2]` six elements, four of them nil.
- **`:Nil` is the type of nil,** a built-in. Nil fits only where a type admits it: `:Union.(:Color, :Nil)`. **`:List.(T)` admits nil** as its "no elements": `:theme []` chooses no themes. An empty slot fits a slot of the tuple only where that slot admits nil, so arrows say where they may be empty: `:Tip := :Union.(:Head, :Nil)`, `:Arrow := :Tuple.(:Tip, :Union.(:Line, :Nil), :Tip)`.
- **Nothing is marked by its spelling,** not by a name: `:None :: [none]` goes, and no label is reserved for it. Text keeps its own nothing, `""`.
- **The style is total through nil** (style.md 7.2). Every descriptor that can be nothing admits `:Nil`, and `[base]` binds every descriptor for every class it applies to: `&node :fill []`, `:width [0]` (a minimum: fitted to the content), `:bend [0]`, `:note ""`, `:step []`. So a later layer can take a value away: `[dark]` fills zones, and a program writes `G :fill []`.

**Rejected.** `:Nil :: [nil]`: simple, but nil becomes an ordinary label, a name that means nothing. `[]` as the empty list beside a separate none: two nothings, and `[]` would have two types.

### 22.3 Typed records, and tables

**A record type is declared by its descriptors,** as a label type is by its labels:

```
:Shape :: [circle], [box], …          // a label type: its labels

:Style :: {                           // a record type: its descriptors
  (&node, &zone) :fill :: :Union.(:Color, :Nil),
  (&edge, &cell) :arrow :: :Arrow,
  …
}
```

- **One descriptor, one record type,** as one label has one type. A descriptor declared at the top level, outside any record type (`&zone :style :: :Style`), describes at the top level only.
- **A record has no type of its own; it is checked by its structure where a record type is expected** (22.9). A descriptor of another record type in it **does not apply**. `{}` fits any record type.
- **`:Record` goes.** Themes are styles, `:Style [dark] := { … }`, and `:theme` takes `:List.(:Style)`, so `:theme [some-proof]` is a wrong type. A bundle has no record type of its own: it is checked where it is used (22.9).
- **The layers are descriptors of their record type:** `&zone :style :: :Style`, `&zone :prove :: :Proof`, `&zone :place :: :Place`. Zig gives `:style` its meaning: apply the record, with the diagram as its owner.
- **Tokens are namings:** `[ink] := [#dddddd]` inside a record binds the label in that record, to a value of its type (**key of the wrong type** otherwise).

**Tables are descriptors with keys.** `:Table.(T)` is a type for descriptors only, never written as a value: its descriptor takes a key and a value.

```
&zone :axiom :: :Table.(:Proposition)
Repo :prove { :axiom.[merge] (fix merge == login session merge') }
```

- **A binding is (context, descriptor, key), once per layer.** Nothing accumulates, so "each binding once" holds with no exception.
- **Keys are written with `.`,** the sign of "the part of": `:axiom.[a]`. `/` keeps its two meanings, attaching in chains and separating elements in brackets. **A key is optional:** an entry without one has a fresh key no one can refer to (22.5).
- **Keys are local to their descriptor:** `[a]` as a key never collides with a value `[a]`. A key is declared by its binding, as an edge is by its first occurrence.
- **Arity follows the type:** a flag takes nothing, a plain descriptor a value, a table descriptor a key and a value.
- **Lists are choices, tables are facts.** `:theme` is a list, bound once: a composition whose order matters (`[dark/compact]` is dark, then compact over it), replaced by a later layer. A table holds facts that hold together, each under its own key.

**Rejected.** Tables that accumulate by position: a positional reference (`:lemma.[0]`) shifts when a lemma is inserted, and accumulation is a second binding rule. A missing key is a fresh one instead, which nothing can refer to. `/` for keys (`G/[style]`): a chain's operator. Layers as keys (`[style]`): three fixed parts named like the user's own.

### 22.4 The style pass (plan step 9)

- **Contexts in a diagram's style** resolve in its own names: edges, cells, `#X`, `@`, canonical ends (`+f`, `f+`), and classes (`&node` there is the diagram's nodes). Groups distribute, blocks factor. Each diagram styles itself: a part of another diagram is an error (**context in another diagram**); so is a description before the diagram's declaration (**description at an undeclared context**). Canonical references (rule 7): `+g` where the node is `f+` (**non-canonical reference**), `+f` on `#Done` (**named node referenced by an end**). A top-level class, `&node :shape [box]`, describes every diagram.
- **Specificity, within a layer,** narrowest winning: a single element; a class inside a diagram; a narrower class; a class. Classes of one rank apply in the order they are defined, the later winning, and errors come last, so nothing paints over them: `&node` < `&plain`, `&choice`, `&parallel`, `&start`, `&end` < `&canonical` < `&hole`. Marks stay the last layer of all. This settles style.md 12.1.
- **Binding made twice** is checked per element, after groups distribute, at one rank: `(yes, paid) :label "yes", yes :label "x"`.
- **Values are decoded once, by the analyser.** Records keep decoded bindings, so the style pass reads no CST. *(Superseded by §22.12: no typed fields; the Sheet holds values.)* `Style` has one typed field per descriptor of `:Style` that Zig gives meaning to; a label Zig does not know (`:Shape :: [blob]`) is carried by name, and a descriptor it does not know (`&node :glow :: :Color`) is kept beside the style, for a renderer to report. A test ties the prelude's `:Style` to `Style`'s fields and their types.
- **Tokens are resolved in core,** per diagram, through its layers: `[base]`, its themes, its own style. Colours reach a renderer as RGBA. A label bound to a label resolves one step: `[circle] := [box]` with `[box] := [round]` draws circles as boxes.
- **`:theme` inside a theme includes,** before the theme's own bindings. Names are defined before use, so inclusion never cycles. `:theme` cascading into nested diagrams waits for the header.
- **Computed defaults** stay below `[base]`: a node's label, a cell's arrow by its level. Sizes that need text metrics (one circle diameter per diagram, a bar's width) belong to the renderer.
- **An arrow draws something:** `[//>]`, `[>//]` and `[>//>]` are arrows, `[//]` is an error (**empty arrow**). An edge that should not be drawn is hidden, `:hide`, not emptied.
- **`!` with nothing to invert** is one error, **not invertible**: `[>!/solid/>]`, `:size [2!]`. Only hooks and harpoons have a side, and among numbers only angles.
- **The stage is named after its layer:** `format/` becomes `style/`, `Formatter` the `Styler`.

### 22.5 The proof's shape (plan step 11, planned)

**A diagram presents a theory.** A diagram G of kind K presents

```
T(G) = the generators (the cells G declares) + the laws of K + the axioms
```

and a proof says what T(G) holds: **axioms** state, **lemmas** are checked. An axiom is what the user tells fAB about the system (this square commutes, this column is a key); a lemma is what the user asks fAB to confirm (is this a pushout?), a proved step that later lemmas may build on. Most programs, a git history or a schema, use only axioms: they are the standard way to give a structure its features. Lemmas are for questions about the structure built.

**An axiom's truth is never checked: it fits the structure, or it is an error.** What can be wrong with it is what it is stated about:

1. **Ill-formed:** an unknown name, an equation between paths whose ends differ, a property on the wrong class. Always decidable.
2. **Not admitted by the kind:** `:pullback` in a flow, `:pk` outside a schema, an equation through an undirected edge in a category. Always decidable.
3. **Inconsistent with the other axioms,** where a contradiction can be shown. Where it cannot, the axiom is **trusted**: facts are stated, not evidenced.

| | Ill-formed | Not admitted by the kind | Inconsistent, or refuted | Cannot tell |
| --- | --- | --- | --- | --- |
| `:axiom` | error | error | error, when decidable | trusted, silent |
| `:lemma` | error | error | error, `&refutable` (17) | warning, `&undecidable`; a pass acknowledges it |

- **No pass reaches an axiom.** From an inconsistent theory everything follows, so every lemma would be confirmed and none would mean anything: a broken fact is fixed, never acknowledged.
- **An axiom states what it presupposes.** `#M :pushout` needs its square to commute: as an axiom it states the commuting square too, so no precondition is left to decide; as a lemma, both are checked.
- **Independence is opt-in** (amended in 22.7: the flag is `:strict`, `-H strict` on the command line). An axiom that follows from the others is redundant, and could be a lemma. Checking every axiom costs a proof each, so fAB looks only when asked, in the header (`Repo :independent`, a flag) or from the command line (`fab check --independent`); each axiom that follows is then a warning ("follows from the other axioms; it could be a lemma"), and one fAB cannot decide is left alone.
- **Axioms have no order;** nothing derives them. **A lemma may use every axiom and the lemmas before it,** so lemmas never prove each other.
- **Both are tables:** `&zone :axiom :: :Table.(:Proposition)`, `&zone :lemma :: :Table.(:Proposition)`. **A key is optional:** an entry without one has a fresh key no one can refer to, so each entry is still one binding. Name only what is referred to, as with nodes: `Repo :lemma.[clean]`, for a pass or a drawing.
- **`( … )` is the fifth shape of a value, `:Proposition`,** a record type declared by its descriptors, the properties:

  ```
  :Proposition :: {
    &node :pushout :: :Flag,
    (&node, &edge) :pullback :: :Flag,
    &edge :card :: :Cardinality,
    …
  }
  ```

  Properties are ordinary descriptors with ordinary types, so `(&edge :card [0..*/1])` takes a value and `(parent { :nullable, … })` factors a context. One descriptor, one record type: `#X :pk` in a style does not apply. A proposition differs from a record in two ways: operations (`==`, `~=`) stand among its descriptions, and its comma means *and*; it holds no namings or declarations. What `==` and `~=` mean stays open.
- **`:Proof` holds `:kind`, `:axiom`, `:lemma` and `:pass`.** `:kind` comes first, as the owner's descriptors do (22.1).

```
Db :prove {
  :kind [schema],
  :axiom (&node.id :pk, &edge :card [0..*/1]),
  :axiom (User.(email, nick)! :uk, Tag.label :uk, (user, org)! :uk, (doc, tag)! :uk),
  :axiom (parent { :nullable, :card [0..*/0..1] }),
  :axiom.[same-document] (parent document == document)
}
Repo :prove {
  :kind [category],
  :axiom (fix merge == login session merge'),     // we say it commutes
  :lemma.[clean] (#Merged :pushout)               // fAB confirms it
}
```

- **What a confirmed lemma constructs** (a pushout's unique arrows, drawn dashed; corner marks ⌟) may be drawn, under `:marks`: open, with step 11.

**Rejected.**
- **Lemmas only, everything checked.** Without axioms T(G) is the free category on G's edges, where two different paths are never equal: every commuting square would be refuted. A lemma that is assumed instead of checked is an axiom under another name, and then nothing is ever verified.
- **Constraints as bare descriptions beside the lemmas** (`&node.id :pk` in the proof record): `:pk` and `:pushout` are the same sort of claim, and the syntax would not say which is stated and which is asked.
- **Required keys:** names for every key and cardinality, which nothing refers to.
- **Properties as bare descriptors of type `:Proposition`:** `:card` takes a value.
- **Postfix operators for properties** (`#Merged |<`): a closed family in the lexer, and precedence again. The context after the property (`:pushout #Merged`): every description reads context first.

### 22.6 The scope of proof (plan step 11, planned)

fAB checks claims about one finite presentation; it is not a proof assistant. Three rules keep it so:

1. **State, never prove.** A program writes axioms and lemmas, never proofs: no tactics, no proof terms, no steps. fAB confirms a lemma, refutes it, or says it cannot decide. A confirmed lemma is a fact the lemmas after it may use; how they use it is fAB's business, not the program's.
2. **A small logic.** A proposition is a conjunction (`,`) of atoms; an atom is a path equation (`==`, `~=`) or a property of a named element (`#M :pushout`, `id :pk`). No variables, no quantifiers, no disjunction or implication, and no predicates defined by the program with a meaning: a program may declare a property (`&node :mine :: :Flag`), but with no meaning in Zig it serves only as an axiom, and as a lemma it is undecidable.
3. **Closed procedures, bounded.** Every property with a meaning has a decision procedure in Zig, per kind, and every check runs within a budget; past it, the lemma is undecidable (a warning). fAB never loops and never asks for help. A new property is a deliberate addition: its signature in the prelude, its procedure in Zig.

| Kind | Lemmas it can decide (examples) | How |
| --- | --- | --- |
| plain graph | connected, acyclic, a path exists | graph search |
| flow | every fork joins, the end is reachable, no deadlock | search of the finite flow |
| category | an equation follows from the axioms; mono, epi, iso; pullback, pushout | congruence closure on paths: decided outright when the presentation has finitely many paths (acyclic graphs: histories, most schemas), bounded rewriting otherwise |
| schema | keys and cardinalities agree along paths; path constraints follow | the same, with cardinalities composed |

So §17's classes have content: *refutable* is a counterexample found, *undecidable* is no procedure, or the budget spent.

**Rejected.** A general logic with written proofs (Lean, Coq): what anything can state, nothing can check unaided, and fAB is a description language. Unbounded checks: a drawing must always finish.

### 22.7 The header, the command line, and strict proofs, 2026-11-06

Amends 22.5 (independence) and the header's open question. The header's syntax, and the command line's, wait for the CLI's revision (plan step 12); what is settled here is what they say and who wins.

**The header holds the file's general rules,** applying to every diagram in it: what kind of graphs its structures are, how strict their proofs are, how errors are treated. It is defined in fab-core, with its descriptors and their types, like any record type.

**One description, three levels:**

| Level | Where | Example |
| --- | --- | --- |
| Command line | `fab check` | `fab check db.fab -H kind=schema -H strict` |
| Header | the file, once | the file's `:kind [schema]`, `:strict` |
| Local | a diagram's layer | `Db :prove { :kind [schema], :strict }` |

- **The most specific wins: command line < header < local.** A local description overrides the header for its diagram, and the header overrides the command line. The command line is a default for what the file leaves unsaid.
- **Why the file wins.** The header changes what diagrams mean (`:kind [category]` makes `f g` a composite); if a flag could override it, one file would mean different things depending on how it is run, and a file that states its rules would stop being the truth. rustc does the same: `#[allow]` in the source overrides `-D` on the command line.
- **Forcing is its own flag,** as rustc's `--cap-lints` is: CI that must impose a rule on files that opted out says so explicitly. Its name and shape wait for the CLI.
- **Descriptors that are a diagram's** (`:kind`, `:strict`) may be written at all three levels. **Descriptors of the compilation** (`:warnings`, `:broken`) only in the header and on the command line.

**The command line follows shell conventions,** not fAB syntax: arguments are what a shell loop expects, even when wordier. fab-cli derives its options from the header's definition in fab-core, by fixed translation rules, so the two never drift:

- `-H name` sets a flag; `-H no-name` turns it off. Never `name!`: interactive bash and zsh read `!` as history expansion.
- `-H name=value` sets a value; the value is the bracket's contents: `-H kind=category`, `-H warnings=error`. Always the descriptor's name: never `-H category`, even though a label names its type.

**`:strict` replaces `:independent`:** a strict proof uses no axiom it does not need. `G :prove { :strict, :axiom (…), :lemma (…) }`, or `:strict` in the header for every diagram, or `-H strict`. Each axiom that follows from the others is a warning: "follows from the other axioms; it could be a lemma". One fAB cannot decide is left alone, as before. The word is plain on purpose: a programmer learns what independence is from the message, without the word.

**The compilation's tolerance becomes two descriptors,** each named after what it does, freeing "strict" for proofs:

| Today (`Compilation.Tolerance`) | Header | Command line |
| --- | --- | --- |
| warnings promoted to errors | `:warnings [error]`, default `[warn]` | `-H warnings=error` |
| a broken IR withheld | `:broken [withhold]`, default `[draw]` | `-H broken=withhold` |

The code's `strict` and `preview` tolerances are renamed to match when the header lands.

**Rejected.**
- **fAB syntax in arguments** (`--with 'Db :strict'`): not how a shell is used, and quoting gets in the way.
- **The command line on top:** it would let the way a file is run change what it means.
- **`:independent`, `:minimal`:** exact, but they need the formalism to explain; `:strict` needs one sentence.
- **`-H category`:** short, but scripts read better with the descriptor named.

### 22.8 Types are declared; twins, 2026-11-06

Amends 21.2, 22.2–22.5 (plan step 9b); the tables of 22.3 and 22.5 are declared as below. Settles how a type says where `!` is allowed, and with it how types are written.

**`::` introduces a type; `:=` binds values only.** A declaration's body says what the new thing holds: `G :: f g` its edges, `:Shape :: [circle], [box]` its labels, `:Style :: { … }` its descriptors, and `:Angle :: :Number!` its values, those of `:Number!`. `[red] := [#f00]` says red *is* `#f00`; no type is a value, so type aliases go, and `:Length := :Number` is an error (**type named with `:=`**).

- **Declared types are distinct.** `:Length`, `:Angle` and `:Fraction` all hold numbers, but a length is no angle: `:Length [gap] := [2]` then `:bend [gap]` is a wrong type. The unit, carried only by the type's name until now, is checked.
- **Literals fit by shape:** a declared type accepts its body's values as written, literals and untyped names, so `:size [2]` fits `:Length`. A value already typed by a declaration fits that type, and every type whose body includes it.
- **Repeating a declaration adds to the type,** uniformly: labels (`:Shape :: [blob]`), descriptors (`:Style :: { &node :glow :: :Color }`) and types (`:Tip :: :Arc`). A pro user extends the vocabulary where it lives, with no new types and no new names.

**A type is spelled like its values.**

| Body of `:T :: …` | Declares | Example |
| --- | --- | --- |
| labels | a label type | `:Shape :: [circle], [box]` |
| descriptors | a record type | `:Style :: { (&node, &zone) :fill :: (:Color, :Nil) }` |
| types, by commas | a union | `:Tip :: :Head, :Hook!, :Nil` |
| a bracket of two or more type names | a tuple | `:Arrow :: [:Tip/:Stroke/:Tip]` |
| a bracket of one type name | a list | `:Themes :: [:Style]` |

- **A comma is a choice, as in a diagram's declaration** (side by side, the coproduct). Parentheses group, as in a graph: `:Tip :: (:Head, :Hook!, :Nil)` is `:Tip :: :Head, :Hook!, :Nil`, as `G :: (f, g)` is `G :: f, g`. Inside an expression the group is needed: `&node :fill :: (:Color, :Nil)`. **The grouped form is canonical:** wherever fAB prints a type (messages, hover, completion), a union is grouped, `(:Color, :Nil)`, so one spelling reads the same everywhere (9 November).
- **A bracket is a tuple of its slots,** as `[>/solid/>]` is a tuple of values.
- **`[:T]` is a list of `:T`:** a deliberate shorthand. A one-slot tuple would only repeat `:T`, so the spelling is free to mean the list. Its values are as before: `[dark]` is a list of one, `[dark/compact]` of two, `[]` none.
- **A bracket holds type names only,** each with an optional `!`: no expression, so what it needs is named first, as a composite is before it is a side (`W :: +(f h, k, g)+`): `:Stroke :: :Line!, :Nil`, then `[:Tip/:Stroke/:Tip]`. A list of tuples is `:Pair :: [:A/:B]`, then `[:Pair]`.
- **No `(`, `)` or `,` inside any bracket,** of values or of types: they are fAB's own grouping, so `[:A/(:B,:C)/:D]` cannot be smuggled in without spaces. Symbols lose these three glyphs; none of the prelude's uses them.
- **Types and values never mix in a bracket:** `[:Tip/solid/>]` is an error (**types and values mixed**). Verbose in an edge case, easy to decide always.
- **No constructors remain.** `:Union.(…)`, `:Tuple.(…)`, `:List.(…)` and `:Table.(…)` go, and with them `.( … )` on a type (**type with parameters**). A type is names, `!`, commas, groups and brackets.

**A table is a descriptor that takes a key, declared by its key slot.** No value is a table: `(f == g)` is a `:Proposition`, and what makes `:axiom` a table is that the descriptor takes a key. So being a table is the descriptor's arity (a flag; a value; a key and a value), written where the key is written:

```
:Proof :: {
  &zone :kind      :: :Kind,              // a value
  &zone :strict    :: :Flag,              // a flag
  &zone :axiom.[]  :: :Proposition,       // a table: a key, then a value
  &zone :lemma.[]  :: :Proposition
}

Repo :prove {
  :kind [category],
  :strict,
  :axiom (fix merge == login session merge'),    // no key: a fresh one
  :axiom.[root] (*/init :initial),
  :lemma.[clean] (#Merged :pushout)
}
Repo :lemma.[clean]                              // a reference
```

- **`.[]` is the key slot, empty because a declaration names no key:** nil is nothing written, so `.[]` reads "a key goes here, and may be empty", which is the rule that keys are optional and a missing one is fresh. A filled slot in a declaration, `:axiom.[a] :: …`, is an error (**key in a declaration**).
- **The declaration looks like its use,** as every other type in this section does, and the value keeps its own type: `&zone :note.[] :: :Text, :Math` is a table of text or maths.
- **Any record type may hold tables:** `:Style :: { &zone :legend.[] :: :Label }`, then `Board :style { :legend.[done] "green: shipped", :legend.[late] "red: overdue", :legend "grey: not started" }`. A legend is facts under their keys, where `:theme [dark/compact]` is one choice.
- **Errors read from the slot:** **key not taken** is a key on a descriptor declared without `.[]` (`:kind.[x] [category]`); two entries under one key are a **binding made twice**.
- **A key in a use is one name** (`.[merge]`), read as a name in a bracket is. A slot left empty, `:legend.[] "x"`, is **key malformed**, as are `.[a/b]` and `.[#fff]`: an entry with no key leaves the slot off, so a fresh key has one spelling (9 November, plan step 9b3).
- A typed key, `.[:Name]`, would fit this spelling later; nothing asks for it.

**`!` names a value's twin.** The three uses of 3.2 in style.md are one idea: a two-sided value has exactly one partner, its unmarked spelling is the first. The flag's twin is off, a hook's or an angle's is the inner side, a line's is struck. A type with twins is `T × 2`, and `!` swaps the halves; the twin of a twin is the value itself, so `[30!!]` stays an error.

- **Twins are declared on types, never on labels:** `T!` is `T` with its twins. `:Angle :: :Number!`, `:Hook :: [?], [^]` with `:Hook!` in `:Tip`, `:Line!` in `:Stroke`. A type at each use decides: an arrow's line may be struck, a node's border (`:line :: (:Line, :Nil)`) may not.
- **`T` fits `T!`,** an unmarked value being the first of its pair; **`T!` does not fit `T`**. On a union `!` distributes: `(:Head, :Hook)!` is `(:Head!, :Hook!)`. `:Flag` has twins by nature; `:Nil` and records have none.
- **`:Angle :: :Number!` leaves `:Number` as it is:** `:size [2!]` is still an error. It declares a new type, holding the numbers and their twins.
- **One error, not invertible:** `!` where the type has no twins. It replaces *only a flag inverts* (`:fill!`): a bundle is no `:Flag!`, so `:terminal!` is the same error.
- **Zig gives each twin its meaning,** per type, as it does labels: `:Hook!` the side, `:Angle` inward, `:Line!` struck, `:Flag!` off. The `!` of a node kind (`f/!`, a parallel) is another position and unrelated.

**Rejected.**
- **Twins on labels** (`:Head :: [?!], [^!]`): it reads as a value, the inner hook, while it would mean "both sides"; it cannot vary with use, so struck lines would reach node borders; and it is a second way to say what `T!` says.
- **Type aliases with `:=`:** a type is not a value, and aliases make units unchecked.
- **`:Union.(…)` beside the comma:** two spellings of one choice. **`[:Style..]` for a list:** `..` would mean two things inside brackets.
- **`:Table.(T)` and `:{ :A, :B }` for tables:** both spell as a type what no value has; a table is the descriptor's arity, so it is declared on the descriptor.
- **Expressions inside brackets:** the token holds no spaces, so they would depend on whitespace; naming first keeps a type readable.

### 22.9 Record types and bundles, 2026-11-09

Amends 22.3 (plan step 9b2). Settles what a record type's declaration may hold, and how records and bundles are typed: by their structure, where they are used.

**A type holds values or descriptors, never both.** A body of labels and types declares a value type; a body of signatures, a record type. Repeating a declaration keeps its side:

```
:Style :: { &node :glow :: :Color }       // a record type, extended
:Style :: [x]                             // error: labels on structure
:Shape :: { &node :x :: :Color }          // error: descriptors on a value type
```

**`::` and `:=` never nest inside each other.** A declaration declares, a naming names, all the way down:

```
:Style :: { &node :fill :: :Color }       // a declaration in a declaration
:Style :: { [ink] := [#fff] }             // error: naming in a type
:Style [x] := { [ink] :: :Color }         // error: declaration in a record (22.1)
```

**A bundle has no record type; it is checked where it is used.** A bundle is a flag whose record is applied where it is written, as if its contents were written there (21). So it is checked there: against the classes of its context, as before, and now against the record type expected there. A descriptor of its contents outside that type **does not apply**.

```
:key := { :pk, :fill [gold] }             // fine on its own

Db :style { User.id :key }                // error: :pk does not apply in a :Style
Db :prove { :axiom (User.id :key) }       // error: :fill does not apply in a :Proposition
```

- **The error is at the use,** where it fails, with `related` at the first foreign descriptor in the bundle; one error per use. Bundles in bundles are checked through: `:a := { :key }` used in a style reports `:pk`, reached through `:key`.
- **A record with a type in its head** says what it is: `:Style [x] := { :pk }` reports `:pk` where it is written. A record after a descriptor has that descriptor's type: `G :style { :pk }` likewise.
- **`{}` holds nothing,** so it fits any record type.
- **A bundle that fits nowhere is no error** until it is used, as nothing in fAB is an error for being unused.

So one rule covers classes and record types: a bundle applies where all its contents apply.

**A record has no type either: it is checked by its structure where a record type is expected.** A record is a set of descriptors with values; whether it is a style is whether its descriptors are `:Style`'s, asked where a `:Style` is expected:

```
[x] := { &node :fill [red] }              // a record: no type assigned
:Style [y] := { :theme [x] }              // fine: :fill is a :Style descriptor

[n] := { &node :memo "x" }                // :memo of :Notes
:Style [y] := { :theme [n] }              // error: wrong type, at [n], related at :memo
```

- **Where a record type is expected,** the record's descriptors are checked against it: after a descriptor (`G :style { … }`), under a contract (`:Style [x] := { … }`, reported at each foreign descriptor, as written there), and where a named record is used (`:theme [x]`, a **wrong type** at the use, related at the first foreign descriptor).
- **A named record keeps its structure, not a type:** what its descriptors belong to, read once at its definition. A name for named records (`[both] := [x/y]`) keeps theirs.
- **A contract checks, and names no type:** `:Style [x] := { … }` checks the record against `:Style` where it is written, rather than at each use.
- **Inside a record with no expected type,** each descriptor is still checked where it is written for its classes and its value; only belonging waits for the use.

**Rejected.** A record's type read from its first descriptor: a record is its structure, and two records with the same descriptors are the same whatever came first. A bundle joining the record type of its first descriptor: arbitrary, and it reports the second descriptor of `:key` though neither is more wrong than the other. A bundle checked at its definition: a mixed bundle is wrong only where it is used, and the use is what the user must change.

### 22.10 Layers read, 2026-11-09

Settles how descriptions are read into layers (plan step 9c).

**A layer is open.** Every description of a diagram's layer joins one layer, wherever it is written: a block, another block, the top-level shorthand. **Binding made twice** counts the leaf bindings, (element, descriptor, key), never the layer's own descriptor:

```
G :style { #Done :terminal }
G.f :label "x"                        // joins G's style: it is G :style { f :label "x" }
G :style { f :label "y" }             // error: (G.f, :label) bound twice
```

Two contexts naming one element are one binding: `(f, f) :label "x"` binds twice. Classes and elements overlap freely; specificity orders them.

**A context is a subject:** a diagram's name, an edge's or a cell's, an end (`f+`, `+f`), a named node (`#Done`, `@`), a class (`&edge`), each qualified with `.` (`G.f`), or a group of them, over which the descriptor distributes. A chain, a path or a pinch addresses a structure, not one element: `f g :label`, `f/g :label`, `+(f, g)+ :label` are **not a subject**.

**Only a diagram has parts.** Inside a block whose owner is an element or a class, only the owner is described: `G :style { #Done { f :label "x" } }` is **element has no parts**, as is `&node { #A :fill [red] }`. Nesting means one thing, the part of a diagram.

**A class at the top level describes every diagram:** `&node :fill [red]` is the program's own, at a class's rank, as a theme's class would be. `G.&node` narrows it to G.

**Each diagram styles itself.** In C's layer, `A.+f` is **another diagram's subject**; at the top level, `A.+f :fill [red]` is A's layer, and fine.

**Rejected.** A layer bound once, `(G, :style)`: the top-level shorthand would then conflict with any block. Contexts inside an element read relative to its diagram: nesting would mean nothing. Classes only inside a diagram: a program could not restyle every diagram without a theme.

### 22.11 The cascade, 2026-11-09

Settles three questions before the style pass is written (plan step 9d).

**Ties are settled.** Two classes of one rank setting one descriptor are no error: they apply in their fixed order, `&node` < the kinds < `&canonical` < `&hole` (§22.4). The open question in the spec's list goes.

**Numbers stay exact to the renderer.** A `Style` holds a number as a `Decimal`, mantissa and scale, its normal form; core compares and checks it without reading text again, and only a renderer, laying out geometry, turns it into a float. JSON writes it as its normal form, a string: `"0.85"`, `"1.5"`. The string is the format at the boundary, the decimal the value inside.

**A diagram's own layer rebinds tokens.** `G :style { [ink] := [#000000] }` is a `:Style` record like any theme, so it binds tokens for G, after its themes: `[base]`, then G's themes left to right, then G's own. What a theme can say, a diagram can say of itself.

**Rejected.** Floats in the Sheet: simpler for a renderer, but `0.1` would stop being `0.1` on its way. Numbers as strings inside core: every check would parse again. Tokens only in themes: a diagram would need a theme of its own to change one colour.

### 22.12 The prelude is the schema; the Sheet holds values, shared, 2026-11-09

Settles what the style pass hands renderers (plan steps 9d3–9d5, 10), before its types are written. It replaces §22.4's fourth point: `Style` gets no typed field per descriptor.

**The prelude is the only schema.** `:Style`'s descriptors, their types, their classes and the label types are stated once, in `prelude.fab`, and checked by the analyser. Nothing restates them: no Zig struct written or generated from them, no JSON or TOML file beside them. A schema in JSON may later be *emitted* from the prelude for renderers outside Zig (`fab show schema`), never written.

**The Sheet holds resolved values, not typed fields.** Each style is a list of entries, a descriptor and its `decoded.Value`, resolved: tokens are RGBA, computed defaults filled in. Core gives meaning only to what it computes or consumes: `:label` and a cell's `:arrow` (computed defaults), `:theme`, `:marks` and the marks; a test checks each of those names is in `:Style`. A descriptor or a label Zig does not know is an entry like any other.

**Resolved, and shared.** The Sheet follows the lines the author wrote. A *rule* per diagram and set of classes present (`G` with `&node`, `&choice`) holds the style those make: `[base]`, the diagram's themes, its class bindings and its tokens. An *element* names its rule and holds only its own: its computed label, its own bindings (`G.#A :fill`), its marks. `sheet.style(element)` merges the two for a renderer that wants one style; SVG writes a CSS class per rule (`.G-choice`) and an element's own values beside it. The cascade stays in core, once.

**Renderers declare what they draw:** the descriptors, and per label type the labels they give a meaning. Typed access is the renderer's (`style.color(.stroke)`, `style.label(Shape, .shape)`, a label mapped to the renderer's own enum by name); whatever it does not declare it reports, and draws with a fallback. Graphviz declares a part. fAB's own renderer declares all of it: a test checks its declarations against the prelude, every descriptor of `:Style` and every label of each label type, so a change to the prelude fails the test until the renderer follows. The test also catches a misspelled name, since every name a renderer declares must be in `:Style`.

**Rejected.**
- A typed `Style` written by hand, tied to the prelude by a test: two lists of one thing.
- The same generated from the prelude, committed or at build time: compile-time exhaustiveness, but a generator, a bootstrapped build or a file to keep fresh, for what a test checks as well.
- The schema in JSON or TOML: a second source of truth, or an export mistaken for one; TOML needs a parser outside Zig's standard library.
- Unresolved layers handed to renderers, for SVG's cascade to resolve: CSS's cascade is not fAB's (specificity ranks, themes in order, tokens per diagram, marks last, computed defaults), and each renderer would emulate it, differently.
- A fully resolved style per element: what the author shared by classes would be repeated on every element, in memory, in JSON, in SVG.

### 22.13 The Sheet in JSON; names without sigils, 2026-11-09

Settles JSON version 2 (plan step 9d5b): the Sheet beside the IR.

**Names are written without sigils.** A sigil tells sorts apart in the source, where every name shares one stream of text: `#A` is a node, `&node` a class, `:label` a descriptor, `[circle]` a label. In JSON a name's place already says its sort, a node's name in `"nodes"`, a class in `"classes"`, a descriptor as a key of `"style"`, so the sigil says nothing more: the node `#A` is `"name": "A"`, as the edge `f` is `"f"` and the diagram `G` is `"G"`. Diagnostics keep them, since their prose quotes the source.

**The Sheet beside the IR.** `"sheet"` follows `"ir"`, null when the IR is. It holds the rules, `{zone, classes, style}`, and each table's elements, indexed as the IR's, `{rule, style, mark}`, with an element's `"style"` only its own entries, merged over its rule's as `Sheet.style` does; and the tokens, `[base]`'s and each diagram's, resolved. A style maps a descriptor to `{layer, value}`, in `:Style`'s order: the layer (`computed`, `base`, `theme`, `program`, `mark`) is what a renderer reads to report what it does not draw.

**Values tagged by shape,** JSON's own types where they cannot be confused: nil `null`, a flag `true` or `false`, elements an array; then `{"text"}`, `{"math"}`, `{"label", "inverted"}`, `{"color": "#rrggbbaa"}` (always eight digits), `{"number": "0.85"}` (its normal form, §22.11), `{"range": [lo, hi]}` (`hi` null when open). No record reaches the Sheet while `:theme` is the only descriptor taking one; `:prove` and `:place` (step 11) decide how theirs are written.

**Rejected.** Keys with their sigils (`":label"`, `"#A"`): `style[":label"]` instead of `style.label`, for nothing a reader needs. A value's layer inside its object: nil and flags are JSON scalars and cannot carry it. Colours with the alpha only when not opaque, as the dumps write them: two forms for every reader to parse.

### 22.14 Base rules, shared by every diagram, 2026-11-09

Amends §22.12 and §22.13 (plan step 9d5d). A rule per diagram and set of classes repeated `[base]` in every diagram: every descriptor of `:Style`, for every class, the same in each unstyled diagram. That is the repetition §22.12 rejected for elements, one level up.

**Base rules.** A *base rule* is what `[base]` makes for a set of classes, its tokens resolved with `[base]`'s own: one per set of classes present anywhere in the program, belonging to no diagram. A *diagram rule* names its base rule as its parent and holds only the entries that differ from it, by value or by layer: what the diagram's themes and class bindings make, and what its tokens change (`[ink] := [#000000]` changes every `[base]` entry written `[ink]`). A binding equal to `[base]`'s value is kept, since its layer is the author's and a renderer reports what it does not draw (§22.12). A diagram rule with nothing of its own is not made: its elements name the base rule. An unstyled program is its base rules, and each element's own entries.

**One level.** A rule's parent is a base rule, and a base rule has none. Sharing along the classes (`&node`'s entries inherited by `&plain` and `&hole`) would make the Sheet a second cascade, ranked as fAB ranks it, which §22.12 rejected; between diagrams one level removes the repetition.

**Read the same.** `sheet.style(element)` merges an element's own entries over its rule's, and those over its parent's. In JSON a rule is `{zone, classes, parent, style}`: a base rule has `"zone": null, "parent": null`, and a parent comes before the rules that name it. SVG writes a class per base rule and one per diagram rule, stacked (`class="node-plain G-node-plain"`), each with its own entries.

**Rejected.** Sharing in JSON only, a diff written by the emitter: the Sheet, and so SVG, would still repeat it. A parent per class (`&node` under `&plain`): above. Dropping a diagram rule's entries equal to its parent's whatever their layer: what a theme binds and a renderer cannot draw would go unreported.

### 22.15 A label's three values, stated, 2026-11-10

States in the spec what the prelude already said (`prelude.fab`, `:Label` and `[base]`'s comment) and the style pass does (plan step 9d4).

**Three values.** `:label []` is the computed name, `:label "…"` (or math) the text as written, `:label ""` no text. Nil is not "no label": for a computed descriptor nil is the computation, as a cell's `:arrow []` is its level's arrow. `[base]` binds `:label []` everywhere but on choices, parallels, starts and ends, which it binds `""`.

**A label holding text is drawn.** A diagram's name is its label, so it is drawn framed or not; the frame is explicit (`:stroke`, `:fill`), the name is not. Graphviz drew a diagram's name only when it framed the diagram, so an unstyled diagram lost its name once marks stopped framing styled ones (step 9d5c); the spec said nothing either way. It is now a renderer's bug.

Nil means one thing everywhere: no layer binds a value, so what lies below shows through, the computation where there is one (`:label`, a cell's `:arrow`), else nothing (`:fill []`).

**Rejected.** `[]` as no text: `[]` and `""` would say the same, and a later layer would have no way back to the computed name; `""` says no text in text's own terms. An unframed diagram nameless: a label left to its default would be dropped by the renderer, against the Sheet, which holds it.

### 22.16 Unsupported in dev builds, 2026-11-10

Amends §15's *unsupported never ships* (`release.md` §2). The rule was that a release build refuses to compile while any unsupported tag remains; "release" meant an optimised build, so no optimised compiler could exist before step 11, and the editor ran a debug one, 15–20 times slower (`profile.md`, F8).

**Decided.** The refusal belongs to a *stable* build, the one a tag names (`release.md` §1), in any optimisation mode. A dev build admits unsupported constructs in any mode, and is marked `incomplete` in its version's build metadata, wherever it names itself. What ships is stable, so unsupported still never ships.

**Rejected.** A build option to admit them (`-Ddev`): a choice anyone could make, giving an optimised build that names itself like a stable one.

## 23. Diagrams as nodes, `@` removed, and `*` on one side, 2026-11-10

Found while writing a template for git diagrams (`examples/git-simple.fab`). A repository is its branches seen together, so one diagram must hold others, and each branch's history starts at `*`. Three rules stood in the way: a diagram name in relations meant the diagram's `@`, so holding a diagram required giving it one; `@` and `*` cannot share a node, so `Master :: @/(*/init commit1 …)` had no meaning; and `*` holds exactly one end, so a table's columns, which fan out of one row, had to fan out of `@` or of an open pinch. The analyser also turned that `@` into a hole without an error (§23.4).

### 23.1 `@` is removed

**What `@` did.** Two jobs. In styles it named the diagram (`G.@ :shape [box]`), and in relations it was a node inside the diagram standing for the diagram, where the diagram's own edges and other diagrams' edges met: a table's columns and the foreign keys that reach it.

**The first job needs no `@`.** A diagram already describes itself: a description at the diagram, or an entry with no context in its block, and in a theme an entry with no subject binds the diagram the theme is applied to.

```
G :: f
G :label "Lorem"                // G itself
G :style { :label "Lorem" }     // the same, in its block
```

**The second job mixed two things.** A node standing for the diagram belongs to the diagrams that use it, not to the diagram's own graph. Inside, it forced a shape on the graph: a table had to be a fan out of `@`, and a git branch had nowhere to put it (its start is `*`, its tip moves with every commit). Outside, it made being used depend on having one: *diagram without `@` used as a node*.

**Decided.** `@` leaves the language. The lexer reads `@` as an invalid token, so the sign stays free for later. The job moves to the diagram's name (§23.2). Gone with it: `A.@`, `G.@` as a context, *diagram without `@` used as a node*, the computed label `@`, `&canonical`'s "not `@`", the filled circle for `@`.

### 23.2 A diagram name is the diagram

**In relations, an uppercase name is the diagram itself, as one node of the diagram that writes it.** That node never enters the named diagram's own graph. As with named nodes, repeated names glue: one node per diagram and container.

- **Alone, it includes the diagram:** `Repo :: Master, FeatureOne, FeatureTwo` holds the three branches and adds no edge.
- **Attached by a slash, it includes it too,** and the edge reaches the diagram as a whole: `Membership/user/User`.
- **A reference to a part shares, and includes nothing:** `FeatureOne :: Master.(commit2+)/commit1 …` starts at Master's node, and FeatureOne does not hold Master. (The spec said a cross reference drew A inside B; read literally, every branch would have drawn Master inside itself.)
- **References point left,** as before: a diagram not yet declared, or the diagram itself, is *not declared before*.

**Membership.** A diagram is a member of each diagram that names it, in order. Clusters form a tree, so a diagram belongs to the *first* diagram that names it: it is drawn there, and styled from there (below). Nodes still belong to the diagram that made them.

**Drawn by its motif.** By default a member is a cluster, a delimited zone with a graph of its own, and an edge to the diagram reaches the cluster's border. Other motifs are the style's `:as` (`[node]`, `[table]`), chosen later by the proof's kind (step 11): a member drawn as one node, a table drawn as a table. The relations say *the diagram*; how it looks is not theirs to say.

**The style reaches members.** Amends the spec's *each diagram styles itself*. A member's rules are its containers' layers beneath its own: `[base]`, then the containers, outermost first, then the diagram's own layer. What reaches is a layer's themes, tokens, class bindings and `:theme`. Element bindings do not: a container naming a member's parts (`Repo :style { Master.init :label "…" }`) is still *another diagram's subject*. Relaxing that later breaks nothing.

**The proof sees members** (step 11): a proof at Repo reads Master's contents, as `(Master.init :init)` needs.

**Categorically.** A container is a diagram whose objects may be diagrams; an edge between two of them is a morphism between diagrams, whose kind (a foreign key, a functor, a call) the proof says. Including a diagram alone adds an object and no arrow; the graph seen inside is the union of the members, glued where they share nodes.

### 23.3 `*` holds the ends of one term, on one side

**Why the guard was.** §5.3 replaced the seal with `*`, and three rules of the seal with one: "a null node holds one end". One end was the cheapest way to make a node *private*: nothing can glue to it or refer to it. It also kept a null node *one-sided*, so it is always a start (nothing arrives) or an end (§10, as in UML).

**Privacy and one side are the point; the count is not.** `*/(a, b, c)` is private (nothing outside the term reaches it) and one-sided (three ends, all starts).

**Decided.** `*` beside a term holds every free end on that side of it, at least one. `*/` distributes over a group, as `#A/` does, and every end it reaches lands on the one null node; closed branches are skipped, as when ends are counted.

| Program | Before | Now |
| --- | --- | --- |
| `*/(a, b, c)` | *not on exactly one end* | one start holding dom a, b, c |
| `(f, g)/*`, `+(yes, no)/*` | *not on exactly one end* | one stop holding cod f, g |
| `*/(a, b c)` | *not on exactly one end* | a and b start there; c follows b |
| `*/+(f, g)` | *not on exactly one end* | a slash between two nodes; write `*/(f, g)` |
| a lone `*`, `f/*/g`, `*/f/g` | *not on exactly one end* | unchanged: no end, or both sides |
| `k f/*, j/f+` | *reference to a null node* | unchanged: private |
| `*/(a, b) h` | *nothing to join* | unchanged: `*` exposes nothing |

**Categorically,** `+(a, b, c)` and `*/(a, b, c)` are the same graph, a wedge: three edges from one node. They differ in the interface. A pinch's apex stays open: `h +(a, b)` attaches to it, and relations reach it as `+a`. A null apex is sealed: anonymous, out of reach in relations, drawn as a dot. Definitions still name it through an edge (`+a :label "row"`).

### 23.4 A node beside a group that exposes nothing

`g/(*/f)` and `(f/*)/g` report *nothing to join*; `#X/(*/f)` and `@/(*/f)` made the node a hole and reported nothing. Rule 2 missed the mirror case: a node, a slash, then a group whose side facing it is empty. It is *nothing to join* at the slash, with its corpus row. With `@` gone, `#X/(*/f)` remains.

### 23.5 The examples

**Git.** Each branch is its history from `*`; the repository holds them. Nothing is written for the diagrams' sake.

```
Master     :: */init commit1 commit2 commit3 commit4 commit5
FeatureOne :: Master.(commit2+)/commit1 commit2 commit3 commit4
FeatureTwo :: Master.(commit2+)/commit1 commit2 merge/Master.(commit3+)

Repo :: Master, FeatureOne, FeatureTwo

Repo :style { &node :shape [point] }    // reaches every branch's commits
```

FeatureTwo forks after commit2 and merges into the state after commit3, so master's `commit3` and FeatureTwo's `merge` both arrive there: a square, the merge commit. Under `@`, Master needed `@/init …` (then init did not start at `*`), or `commit5/@` (then `@` moved with every commit).

**Entity–relationship.** A table is one sealed row with its columns; the schema joins tables as wholes.

```
T :: #UUID7, #DTZ, #String, #Text, #JSONB, #Bool

User         :: */(id/T.#UUID7, email/T.#String, nick/T.#String, name/T.#String, created_at/T.#DTZ)
Organization :: */(id/T.#UUID7, name/T.#String)
Membership   :: */(id/T.#UUID7, admin/T.#Bool)
Tagging      :: */id/T.#UUID7

Db :: {
    Membership/(user/User, org/Organization),
    …
}
```

Db is written as before, and means more: it holds its tables, so its frame surrounds them and its proof reads them (`&node.id :pk`, `User.(email, nick)! :uk` already assumed so). T, reached only by `T.#UUID7`, is beside Db, not in it. Under `@` each table was `@/( … )`; written as an open pinch, `+( … )`, the row would draw as a node labelled `+id`, could be extended by mistake, and a one-column table (`+(id/…)`) would warn as a pinch of one end. As `*/( … )` every table has one form. A table's row and the table itself are now one sealed start and the diagram: a schema kind (step 11) identifies them, and `[table]` draws them as one.

**Flowchart.** A subprocess is a diagram, and a flow passes through it as through a node, BPMN's call activity:

```
Payment :: */charge/? +(paid, declined)/*
Order   :: */receive validate/Payment ship/*
```

`+(paid, declined)/*` ends both outcomes at one final node, where before each needed its own (`+(paid/*, declined/*)`). Order holds Payment, drawn inside it, and `validate` and `ship` reach its border. A start holding several flows (`*/(a, b)`) is an implicit fork, which `Par :: */s/! +(a, b)! t/*` writes with a bar; whether flows may write it is a restriction of the flowchart kind (§17), not of the syntax, as with `?`.

### 23.6 Rejected

- **`@` at a branch's tip** (`commit5/@`, a branch as a ref to its last commit). True of git, but fragile: the `@` moves at every commit, and every diagram that is to be held needs one.
- **A name alone includes, a name with a slash is its `@`.** Keeps `@` only to be attached to, and gives one name two meanings by position.
- **Its own syntax for inclusion** (`Master.*`, braces). A bare name already says it, and braces are a declaration's lines and a record's contents.
- **Inclusion by reference.** Every diagram reaching a part of Master would hold Master: nesting with no tree.
- **`&self`.** The diagram already describes itself (§23.1), and `&zone` is the class of every diagram.
- **Tables as open pinches, made to look like dots by style.** The source would say "an open node, reachable" where the author means "a sealed start", and the one-column table would stay the exception.
- ***Included twice*** (a warning). Repeated names glue, as Db names User three times; a diagram written alone twice is one member.
