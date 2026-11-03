# fAB — edge notation spec

Oct 20, 2026 · @Ramon

**Revision of 1 November 2026.** This spec was rewritten from the design decisions of 22 and 23 October, recorded in [`statements.md`](statements.md) and [`style.md`](style.md), and revised by the grammar of joining settled on 1 November, [`joining.md`](joining.md). Those notes keep the reasons and every rejected alternative; this spec states the language. The implementation (fab-core, fab-render, fab-cli) still follows an earlier revision, and will be brought in line with this one.

## Principles

fAB describes a diagram by its edges only. Nodes are never written: they are derived from how the edges are glued together.

- **Edges are primary.** Every edge is declared by name, and a name denotes exactly one edge.
- **Nodes are derived.** Each edge has two ends, its domain and its codomain. A node is a class of ends that the syntax glues together. Nodes can also be named (`#A`), but never need to be.
- **Honesty rule.** Every edge has a name, and every node is a quotient. No construct creates an anonymous edge.
- **Collapses are written.** Anonymous ends become one node only where a pinch says so. A space joins one end to one end, a slash attaches to a written node or closes a cycle, and nothing merges silently.
- **Declare once, refer backwards.** A bare name declares an edge. A name that already exists is a reference, and a reference always points left, to something declared before it. The same holds for every name in a program: nothing is used before it is created.
- **Describe once, draw what fits.** A program states the whole system of relations once, at every level. What a diagram draws is the part of that system its kind can show: a flow has cells like any diagram, and draws none of them.
- **Structure, then data about it.** Declarations (`::`) build the structure. Definitions (`:=`) give it data: how it looks, what holds in it, where it goes. Data never changes structure.
- **Topology, not geometry.** fAB says what connects to what. Nothing in the language names a direction on the page; layout decides that.
- **One symbol, one meaning.** Every operator means the same thing wherever it appears, at every level of a diagram.

## Program structure

A program is a sequence of statements, one per line; braces let a statement span lines (see Items and lines). There are exactly two kinds, told apart by their operator.

| Kind        | Operator | Introduces                   | Example                                      |
| ----------- | -------- | ---------------------------- | -------------------------------------------- |
| Declaration | `::`     | new **structure**            | `Order :: */receive/#Received validate/? +(…)` |
| Definition  | `:=`     | a new **binding** of a value | `[red] := [#ff0000]`, `G :style := { … }`    |

**Declarations** build structure. Today only diagrams (zones) are declared: `G :: term`. Zones, nodes and edges are the only things that can ever be declared; what declaring a node or an edge on its own means is open, so it is reserved: an error until decided.

**Definitions** bind values. Every definition has one form, read left to right as context, then attribute, then value:

```
subject :attr := value
```

Its parts are optional, which gives exactly three kinds of definition:

| Left side       | Defines                                | Examples                                                               |
| --------------- | -------------------------------------- | ---------------------------------------------------------------------- |
| `[name]`        | a value                                | `[red] := [#ff0000]`, `[warn] := [red]`                                |
| `:attr`         | a new attribute (a bundle), everywhere | `:terminal := { :shape [circle], :fill [red] }`                         |
| `subject :attr` | an attribute's value at a subject      | `&node :shape := [circle]`, `G :style := { … }`, `G.f :arrow := [epi]` |

**Layers.** Three attributes of a diagram take a list of entries as their value, usually written in braces. Each is a five-letter verb, and each accepts its own vocabulary:

| Layer               | Says                                           | Relational?                                               |
| ------------------- | ---------------------------------------------- | --------------------------------------------------------- |
| `G :style := { … }` | how things look                                | no: a style describes one element and never names another |
| `G :prove := { … }` | what holds: equations and universal properties | yes                                                       |
| `G :place := { … }` | where things go                                | yes                                                       |

**Blocks are factored subjects.** A block is shorthand for a set of definitions with a common subject:

```
G :style := { #Done :terminal, f :label "x" }
// means
G.#Done :terminal := …
G.f :label := "x"
```

- An entry with a subject, `s :attr v`, inside the block of owner `X`, binds `X.s :attr`.
- An entry with no subject, `:attr v`, binds the owner itself.
- Inside blocks, entries use the light form, without `:=`. `:=` appears once per statement, at the left margin, so every binding statement is visible there.
- Several subjects are a group, and the attributes distribute over it, as `/` distributes over a group: `(yes, paid) :label "yes"`.
- **An entry has one attribute.** Several attributes of one subject go in braces: `retry { :arrow [/dashed/>], :bend [inner] }`. Side by side (`retry :arrow [/dashed/>] :bend [inner]`) is an error: a comma there would end the entry, and `:bend` would bind the owner instead. Right after `:=` the owner is the subject, so the comma suffices: `User :style := :label "users", :fill [muted]`.

**Items and lines.** Both statements take the same right side: items separated by commas, written on one line or in braces.

- **An item** is a bare term (`f g`, `+(f, g)+`), an entry (`#Done :terminal`, `+f { :label $P$ }`) or an equation (`f h == g k`). Which items each statement allows is checked after parsing: a declaration's items are terms, a definition's are entries and equations.
- **`,` separates items everywhere, with one meaning:** side by side, and independent. In a declaration the items are graphs side by side (a coproduct), in a style bindings side by side, in a proof propositions side by side (a conjunction).
- **The comma is required between items, and only between them.** `#Done :terminal f :label "x"` is an error, and so is a trailing comma: `(f, g,)`, `{ a :x, }`. Without the group, `yes, paid :label "yes"` is two items, and the bare `yes` binds nothing.
- **A statement is one line. Braces let it span lines:** inside `{ }`, at any depth, a newline is a space. Outside them a newline ends the statement, even inside parentheses. Braces are optional for both kinds: `G :style := #Done :terminal, f :label "x"` needs none.
- **There are no empty statements:** `G :: {}` and `G :style := {}` are errors.
- **A group isolates what it holds,** in a term, a subject or a list of propositions alike: `+(f, g)`, `(yes, paid) :label`, `(f h == g k, +f :pullback)`. Groups and braces without a subject may nest freely to organise a block.

**Bindings.**

- **Each (subject, attribute) pair is bound once** within a layer. Binding `G.#Done :shape` twice is an error.
- **Different subjects may overlap**, such as `&node` and `#Done`. The more specific subject wins (see Subjects and classes). Nothing is ever silently overridden.
- **Before use.** Definitions are top-level statements, and come before their first use. A definition at a subject comes after the subject's declaration.

**The header.** A diagram's kind (flow, category, schema, plain graph), its strictness and its boundary are naturally definitions at the zone, such as `Sq :kind := [category]`. Which header attributes exist, and what each changes, is open.

- **Kind** decides what the relations mean. In category mode `f g` also implies that the composite exists; in flow mode it is two steps. The kind also decides what is drawn: a flow draws no cells.
- **Strictness** decides which warnings are errors, for example an unmatched `!` fork.
- **Boundary** decides which open ends the diagram exposes when it is used inside another diagram.

## Diagrams and names

A diagram is declared once, with an uppercase name followed by `::` and a term.

```
G :: f g h
```

- **Diagram names** start with an uppercase letter. Each diagram is declared exactly once.
- **Edge names** are lowercase. The apostrophe is allowed, so `h` and `h'` are distinct names. Greek letters are allowed: `α`.
- **Declaration.** A bare edge name declares a new edge. Writing the same bare name twice is an error, with one exception: the endomorphism `f/f`.
- **Derived nodes.** Comments in this spec write nodes as N1, N2, … and junctions as ◇. These are labels for derived nodes, not syntax.

**Every name has a mark that says what it is:**

| Written     | Names                           |
| ----------- | ------------------------------- |
| `G`         | a diagram                       |
| `f`         | an edge or a cell               |
| `#A`        | a node                          |
| `[red]`     | a value, in value position only |
| `:terminal` | an attribute                    |
| `&node`     | a class of elements             |

**Scope.** Edge names are local to their diagram, so two diagrams can each have their own `f`. Something inside another diagram is reached with `.`, which means "inside" and nothing else. The parentheses are optional but read better:

```
A :: f g
B :: h/A.+f        // h ends at dom(f) of A
B :: h/(A.+f)      // the same, easier to read
```

- The referenced diagram must be declared earlier, just as references inside a diagram point left. A diagram is not earlier than itself: it names its own node with `@`, never by its name.
- In relations, `.` reaches a node: an end (`A.+f`, `A.f+`), a named node (`A.#X`) or the own node (`A.@`, the same as `A`). Another diagram's edge is its own, so `A.f g` is an error; style and proofs name it freely (`User.email :uk`).
- Only ends A exposes can be referenced: never a null node's end, and only ends on A's boundary once the header defines one.
- A cross reference makes B share a node with A. When B is drawn, A appears inside it as a cluster with its own style; B styles only its own subjects, including edges that reach into A.

## Composition

Three constructs build terms: juxtaposition (a space) writes paths, the comma separates, and parentheses group. A fourth, `/`, attaches edges to nodes and closes cycles (next section).

| Syntax  | Name           | Meaning                                                                        |
| ------- | -------------- | ------------------------------------------------------------------------------ |
| `s t`   | Juxtaposition  | The one end on the right of s and the one end on the left of t become one node |
| `s, t`  | Disjoint union | s and t side by side, sharing nothing                                          |
| `( … )` | Grouping       | Groups a term; `f (g h)` is the same as `f g h`                                |

```
G :: f              // f : N1 → N2
G :: f g h          // f : N1 → N2, g : N2 → N3, h : N3 → N4
G :: f, g           // f : N1 → N2, g : N3 → N4
G :: f +(g, h)      // fork: g and h both start at N2
G :: (f, g)+ h      // join: f and g both end at +h
G :: f (g, h)       // error: one end on the left, two on the right
```

**Juxtaposition is typed.** Every term has a left side and a right side, each holding the ends a neighbour can attach to (see Interfaces). A space joins exactly one end to exactly one end, so `f (g, h)` is an error: one against two. Several ends become one only through a pinch (`+`, `?`, `!`), which is how a collapse is declared. A space never closes a cycle; that is the job of `/`.

**What meets at a space is edges.** Each side of a space is an edge end, possibly already sitting on a node: a pinch, or a named node attached by `/`. The node where they meet carries what each side brings: at most one name, and kinds that agree (see Where nodes meet). A node on its own (`#A`, `*`, `@`, a diagram name) never stands beside a space: `#A f` is an error, written `#A/f`.

**Precedence,** tightest first: postfix markers, then the juxtafix `.`, then prefix markers, then the infixes `/` and juxtaposition, then the operators between chains (`==`, `~=`), then the separator `,`, then `|`. A group isolates what it holds and stands as one element. So `A.f+` is `A.(f+)`, `+A.f` is `+(A.f)`, `f g/h` is `f (g/h)`, and `+f/α β/g+` is `(+f/α) (β/g+)`: a path through a fresh node. Within a chain of `/`, reading is left to right.

**Line breaks.** A declaration spans lines only in braces (see Items and lines). Inside them a newline is a space, so a chain may continue on the next line. The analyser warns when a newline falls between two closed chains of an open chain, unless a group stands on either side of it: `(f g)` then `(h k)` on the next line is quiet.

```
Db :: {
  Document/owner/User,
  Config/settings_of/User
}
```

**Whitespace decides attachment.** A tight operator attaches to what it touches. Touching both sides, it is binary; touching one side, it is postfix or prefix; touching neither, it is an error.

| Written      | Meaning                                          |
| ------------ | ------------------------------------------------ |
| `f/g`        | a cycle: g goes back from cod(f) to dom(f)       |
| `f/ g`       | undirected f, then g                             |
| `f /g`       | error: `/` has no prefix form                    |
| `f/? +(g, h)` | a choice node at cod(f), where g and h start    |
| `f+(g, h)`   | error: `+` touches both sides; write `f +(g, h)` |
| `?(g, h)`    | error: a kind is written on the right            |
| `+(f, g)`    | the starts of f and g pinched into one node      |
| `+f`         | the start of f; `+ f` is an error                |
| `*/f`, `f/*` | a null node holding the start of f, or its end   |
| `* f`, `f *` | error: `*` is a node, and a node takes a slash   |

## The slash: attachment and cycles

`/` joins an edge to what touches it on either side: a node, or another edge. A space leaves things open; a slash closes them.

> One edge in a chain is attached to the nodes beside it. Two or more edges in a chain form a cycle: the chain ends where it began.

### One edge: attachment

| Written        | Meaning                                |
| -------------- | -------------------------------------- |
| `#A/f`         | f : A → N1                             |
| `f/#B`         | f : N1 → B                             |
| `#A/f/#B`      | f : A → B                              |
| `+f/g`, `g/f+` | g starts at dom(f); g ends at cod(f)   |
| `+f/g/f+`      | g : dom(f) → cod(f), parallel to f     |
| `*/f`, `f/*`   | f starts at a null node; f ends at one |

- **The sides are nodes:** named nodes (`#A`), the diagram's own node `@`, diagram names, references to ends (`+f`, `f+`) and `*`. Named nodes, `@`, diagram names and `*` need nothing before them; a reference needs its edge declared earlier.
- **A node continues with a space.** `receive/#Received validate` is a path through Received, and `g/+f h` continues from dom(f). With a slash instead, `receive/#Received/validate` would be a cycle.
- **Two notations, one graph.** `f, +f/g/f+` is `+(f, g)+`, and `a/#N b` is `a #N/b`. Both are legal, and each puts a different thing first.

### Two or more edges: cycles

A chain with two or more edges must end where it began. When it ends on an edge, that edge closes on the chain's start; when it ends on a node, that node must be the start.

| Written        | Meaning                                            |
| -------------- | -------------------------------------------------- |
| `f/g`          | f : N1 → N2, g : N2 → N1                           |
| `f/f`          | f : N → N, a loop                                  |
| `f/g/h`        | a directed triangle; h closes on dom(f)            |
| `f/#Z/g`       | f : N1 → Z, g : Z → N1                             |
| `#A/f/#B/g`    | f : A → B, g : B → A; the same as `#A/f/#B/g/#A`   |
| `+f/m/g+/n`    | the pair: m : dom(f) → cod(g), n : cod(g) → dom(f) |
| `(f g)/h`      | f, then g, then h back to dom(f)                   |
| `#A/f/#B/g/#C` | error: the chain ends away from its start          |

- **`f/f` is not a special case.** `f/g` says dom(g) = cod(f) and cod(g) = dom(f). With g = f, both say dom(f) = cod(f).
- **A cycle closes on its start.** It exposes that node on its left and nothing on its right. So `h f/g` ends h at dom(f), and in `f/? +(b/b, e)` the pinch puts the loop b on the decision; but `f/g h` is an error. To continue from another node of the cycle, use a comma and a reference: `f/g, f+/h`.
- **A space is never a cycle.** `+f/α β/g+` is a path through a fresh node, not the pair; the pair is `+f/α/g+/β`.
- **The old pair form is an error.** `+f/m/n/g+` has two edges and ends on `g+`, not on its start. The pair is `+f/m/g+/n`.

### Distribution

`/` distributes over a group: every branch is joined to the same side. `#X/(g1, f, g2)` means `#X/g1, #X/f, #X/g2`, and `f+/(p1/g1+, p2/g2+)` means `f+/p1/g1+, f+/p2/g2+`. Every branch lands on a written node, so no anonymous ends merge and no pinch is needed. Gluing to a node distributes over the comma for the same reason pushouts commute with coproducts.

### Undirected edges

A postfix `/`, touching only the edge before it, makes that edge undirected: f is its own way back, reversed. Compare `f/g` (the way back is g) and `f/f` (the way back is f in the same direction, so a loop).

```
G :: f/                // f connects N1 and N2, in no direction
G :: f/ g/             // two undirected edges in a path
```

- The ends are still distinguished by position: `+f` is the end written first and `f+` the end written second. References and glueing work as before.
- The default arrow of an undirected edge has no heads, `[/solid/]`. Giving it a head is an error: it would draw a direction the relations don't have.
- **A trailing `/` ends a chain of one edge,** so the edge may be attached first: `#A/f/` is undirected f with one end at A, and `#A/f/#B/` is undirected f between A and B. Continue with a space: `#A/f/ g/`.
- In a diagram whose header kind is undirected, every edge is undirected, and writing `f/` there is an error.
- Cells may be undirected too, spelled the same way: `f/α/g/` is undirected α between f and g (see Levels).

## Node kinds and pinching

Every node has exactly one kind: plain, choice ◇, parallel ‖ or null ⊙. Choice and parallel are written where flow arrives, on the right: after a single edge (`f/?`) or after a group (`(a, b)?`). Null comes only from `*`, and a named node is always plain. A node whose kind nothing sets is plain.

| Marker | Kind                                  | On the left              | On the right                                  |
| ------ | ------------------------------------- | ------------------------ | --------------------------------------------- |
| `+`    | none of its own                       | `+t`: pinches the starts | `t+`: pinches the ends                        |
| `?`    | choice ◇: exactly one branch is taken | never                    | `f/?` after an edge, `t?` pinching a group    |
| `!`    | parallel ‖: all branches are taken    | never                    | `f/!` after an edge, `t!` pinching a group    |

`+` is structural, so it has both sides. `?` and `!` are flow, and flow has a direction: a kind is written where flow arrives, so a decision is reached by its edge and a merge by its branches.

### Pinches: `+`, `?`, `!`

> A pinch merges one side of a group into a single node. It is the only way anonymous ends merge, so every collapse is written.

- **On a group,** the start of every branch (or the end of every branch) becomes one node. Only the _first_ node of each branch is pinched at the start, and only the _last_ at the end; inner nodes of a path stay separate.
- **`(a, b)?` and `(a, b)!` are `t+` with a kind:** `(g, h)? k` merges the branches, `(a, b)! k` joins them.
- **A decision or a fork is a kind after an edge, then a pinch.** `f/?` ends f at a fresh choice node, and `f/? +(g, h)` starts g and h there. Likewise `f/! +(g, h)` forks, and `(a, b)! +(c, d)` is one bar that joins and forks. Since the kind is on the node, the branches may also be written apart: `f/?, f+/g, f+/h`.
- **On one edge, a pinch is a reference.** A pinched single edge resolves to the node at that end: `+f` is dom(f), `f+` is cod(f), and `+(f) = +f`. A reference is a node, so it takes a slash: `f+ g` is an error, and `f? (g, h)` is too; write `f/? +(g, h)`.
- **A single edge has one side.** A pinched edge is one node, and a term cannot be two: `+f+` and `+(f)+` are errors. A group may be pinched on both sides: `+(f, g)+`.
- **A kind is set where its node is created.** `f?` and `A.f/?` would change the kind of a node that already exists; write `f/?` where f is declared. `?` and `!` are never on the left: `?(g, h)`, `!f` and `?/f` are errors.

**A pinch with several branches declares them.**

- `+(f, g)+` declares new edges f and g and pinches them on each side. The names inside must be new: pinching declared edges is an error ("`f` is already declared; a pinch declares its branches"). A pinch never merges two existing nodes by surprise; joining existing things is the job of `/`.
- **The first branch names the pinched nodes,** by the canonical rule: in `+(f, g)+`, the pinched start is `+f` and the pinched end is `f+`.
- **A pinched node continues with a space,** like any end: `f +(g, h)`, `(f, g)+ h`.

```
Pair :: +(f, g)+               // a parallel pair f, g : A ⇉ B
Sq   :: +(f h, g k)+           // a square: two paths from one start to one end
G    :: f/? +(g, h)? k         // decision, two branches, merge, continue
G    :: f/! +(g, h)! k         // fork, two parallel branches, join, continue
G    :: (a, b)+ +(c, d)        // a bowtie: a and b end where c and d start
```

**Mathematical reading.** A group `(f, g)` is a coproduct, its ends side by side. In cospans of finite sets every point carries a special commutative Frobenius structure: merging n ends into one is its multiplication, and splitting one into n its comultiplication. A pinch is that structure, written; juxtaposition never applies it silently. `+( … )` is the topologists' wedge sum, pieces glued at one point; `+( … )+` glues both ends, which is parallel composition.

### Where nodes meet

When a space joins two sides, the node they meet at carries what each side brings:

| Side                                                          | Brings                        |
| ------------------------------------------------------------- | ----------------------------- |
| a free end, or a `+` pinch                                    | nothing                       |
| on the right only: `f/?`, `f/!`, or a `?` or `!` pinch        | its kind                      |
| an end attached by `/` to a named node, `@` or a diagram name | that name, and the kind plain |

A null node never meets anything: `*` exposes nothing (see Interfaces).

> The node may have at most one name, and its kinds must agree.

| Written                      | Meets              | Result                                                     |
| ---------------------------- | ------------------ | ---------------------------------------------------------- |
| `f g`                        | nothing, nothing   | a fresh node                                               |
| `f/? +(a, b)`                | choice, nothing    | a choice node                                              |
| `receive/#Received validate` | name, nothing      | Received                                                   |
| `validate/#Valid +(yes, no)` | name, nothing      | a fan out of Valid                                         |
| `(a, b)+ +(c, d)`            | nothing, nothing   | the bowtie                                                 |
| `(a, b)! +(c, d)`            | parallel, nothing  | one bar that joins and forks                               |
| `(a/?, b/!)+`                | choice, parallel   | error: kinds disagree                                      |
| `f/? #Valid/yes`             | choice, plain      | error: a state is not a decision; put an edge between them |
| `a/#A #B/b`                  | two names          | error: one node, one name                                  |

Mathematically, the labels form a partial commutative monoid with "nothing" as its unit. A space is a pushout along one node, and it is defined exactly when the join of the two labels is.

### Null nodes: `*`

`*` is a node with no name. It behaves like `#A` with one difference: it is **private to one edge end**. Each `*` is a fresh null node, attached with `/`, and holds exactly one end.

```
G :: */f g h/*              // a path from a start to a stop
G :: (*/f, */g)+ h          // two starts, joined at +h
G :: (*/f f1, */g g1)+      // two starts, two paths, one end
```

- **A node, so a slash.** `* f`, `*f` and `f *` are errors.
- **Exactly one end.** `*/(f, g)`, `(f, g)/*`, `*/+(f, g)` and `f/*/g` are errors: each would make one null node hold several ends. Write `(*/f, */g)`. A lone `*` holds none, and is an error too.
- **Private.** Nothing glues to a null node and nothing refers to it: `k f/*, j/f+` is an error. Definitions still name it through its edge, as `+f` or `f+`.
- **It leaves the interface:** `f/*` exposes nothing on its right, so `f/* g` is "nothing to join".

## Interfaces

Every term has a left side and a right side. Each side holds what a neighbour can attach to: open edge ends, or one node that ends already sit on (a pinch, or a node an edge is attached to with `/`). A space needs exactly one on each side it joins.

| Term                               | Left side                                                         | Right side              |
| ---------------------------------- | ----------------------------------------------------------------- | ----------------------- |
| `f`                                | dom(f)                                                            | cod(f)                  |
| `s t`                              | the left of s                                                     | the right of t          |
| `s, t`                             | the left of s and of t                                            | the right of s and of t |
| `+(s, t)`                          | one pinched node                                                  | the right of s and of t |
| `(s, t)+`, `(s, t)?`, `(s, t)!`    | the left of s and of t                                            | one pinched node        |
| `#A/f`, `+f/g`                     | A; dom(f)                                                         | cod(f); cod(g)          |
| `f/#B`, `g/f+`                     | dom(f); dom(g)                                                    | B; cod(f)               |
| `#A/f/#B`                          | A                                                                 | B                       |
| `*/f`                              | nothing                                                           | cod(f)                  |
| `f/*`                              | dom(f)                                                            | nothing                 |
| `f/?`, `f/!`                       | dom(f)                                                            | cod(f), with its kind   |
| `f/`                               | dom(f)                                                            | cod(f)                  |
| a cycle: `f/g`, `f/f`, `#A/f/#B/g` | its start: dom(f); A                                              | nothing                 |
| `#A`, `@`, `User` alone            | a lone node: it may stand as a whole branch, never beside a space |                         |

- **One to one.** `f (g, h)` and `(f, g) h` are errors: pinch the group, `f +(g, h)`, `(f, g)+ h`.
- **Ending a branch.** A branch ends with `*` (a stop) or with a cycle, and then exposes nothing on that side. Those branches are skipped when ends are counted, so `(f/*, g) h` attaches h to g only; it warns, because the space reads as joining the group. Write `f/*, g h`. A cycle still exposes its start on the left, so a pinch gathers it: in `f/? +(b/b, e)`, b loops on the decision. A branch that ends on a node (`k/+f`, `x/#Done`) still exposes that node.
- **Nothing to join.** A space with nothing on one side is an error: `f/g h`, `f/* g`, `(f/*) g`. Use a comma for separate pieces.
- **Lone nodes.** `T :: #UUID7, #DTZ` is a discrete diagram: nodes and no edges. In a group, a lone node exposes nothing on either side, so a space beside the group warns as for a stop: `(f, #A) g` is `f g, #A`.

## Named nodes and diagrams as nodes

Edges remain primary, but a node can be named when the diagram needs to talk about it directly. In category theory a node's name is usually only a label, given in the style layer; a named node is for when the structure itself needs to say "this same node" twice.

**Named nodes.** `#A` is a node term: it adds no edge, and names the node an edge is attached to with `/`. Categorically it is the identity on A.

```
G :: #A/f/#B                         // f : A → B
G :: #A/f g/#C                       // f : A → N1, g : N1 → C
G :: #A                              // a lone object: one node, no edges
T :: #UUID7, #DTZ, #String, #JSONB   // a discrete diagram: objects only
```

- **Free.** A named node needs nothing declared before it: writing it creates it. A repeated name glues: `#U/f/#V, #U/g/#W` forks at U.
- **Always with a slash.** A named node is attached to an edge with `/`, never placed beside a space: `#A f` is an error.
- **A state, never a junction.** A named node is plain, so it is never a decision or a bar: `validate/? #Valid/yes` is an error. Put an edge between the state and the decision, and label the decision through its canonical end.
- **The name is canonical.** A named node is referenced and styled as `#A`, never as `+f`.
- **One node, one name.** `a/#A #B/b` is an error.
- **Scope is local.** Another diagram's named node is `A.#X`, as with `A.+f`. It must already be declared there: names never come into existence by being mentioned from outside.
- **Naming is optional,** and decouples names from order. Both of these draw the product diagram with f in the middle:

```
G :: #X/(g1, f/#P, g2), #P/(p1/g1+, p2/g2+)
G :: #X/(g1, f, g2), f+/(p1/g1+, p2/g2+)
```

**The diagram's own node.** `@` is a node term marking the node that stands for the diagram itself. Like `*` it takes a slash; unlike `*` it is shared, and can hold any number of ends. A diagram has one `@`, and writing it again glues to it.

```
User :: @/(id/T.#UUID7, created_at/T.#DTZ, name/T.#String)
```

`@/( … )` distributes: every attribute is an edge from User's own node to a type.

**Diagrams as nodes.** In relations, an uppercase name is a node term: the diagram it names, attached at its `@`. Like `#A`, it takes a slash, and repeated names glue.

```
Db :: Document/owner/User    // owner : Document.@ → User.@
```

When drawn, User and Document appear inside Db as clusters, each with its own style. Using a diagram without an `@` as a node is an error. This is the move cells make, one level up: there edges become nodes, here diagrams do.

### Schemas

A database schema is a category presented by a graph and path equations, as in categorical databases. fAB writes one directly; the schema statements are part of the proof layer.

| Schema      | fAB                                                                                       |
| ----------- | ----------------------------------------------------------------------------------------- |
| Table       | A diagram with an `@` node                                                                |
| Column      | An edge from `@` to a type                                                                |
| Type        | A named node in a shared types diagram                                                    |
| Foreign key | An edge from the table holding it to the table it references, in the diagram joining them |
| Primary key | `:pk` on a column: the key, mono (injective), one per table                               |
| Unique key  | `:uk` on a column: another key, mono                                                      |
| Referenced key | `:refs` on a foreign key and a key of its target: the key it references, if not the `:pk` |
| Constraint  | A path equation                                                                           |

- **A schema is a kind:** `Db :prove := { :kind [schema], … }`. In a schema, an edge between two tables is a foreign key; nothing else marks it, so there is no `:fk`.
- **A foreign key is one edge.** It is both the relationship, used in paths and equations, and the column that stores it. The column's type is the type of the target's `:pk`, so it is never written and cannot mismatch. Name foreign keys as relationships (`parent`, `author`); the column takes its name from the edge (see the foreign-key row under Style layer, Diagrams).
- **No forward references between tables.** Tables never refer to each other, and hold only their own columns; every foreign key lives in the diagram that joins them, declared after them. Circular foreign keys are two edges there, and a self-reference is a loop on one cluster.
- **One scope for foreign keys.** Edge names are local to their diagram, so the foreign keys of one schema share its scope: two tables cannot both have an edge `author`. Choose another name and give the column its name with `:label`.
- **Shared types.** `T.#UUID7` is the same node in every table, so a foreign key's column has the same type as the key it references. T is listed explicitly, so a misspelled type is an error.

## Levels: cells

A declaration is written in **levels**, separated by `|`. Level 1 holds the edges between nodes; level 2 holds the cells between edges (2-cells); level 3 the cells between 2-cells; and so on.

```
G :: level 1 | level 2 | level 3
```

A diagram with cells is a presentation graded by dimension, which mathematicians call a **polygraph** or **computad**: generators at each dimension, each with a source and a target in the dimension below. `|` writes exactly that grading. Level k can only follow level k−1, because its cells refer to cells declared before them.

**Rules.**

- **Each level uses the same grammar as level 1, one dimension up.** At level k ≥ 2, a declared name refers to a cell of level k−1, and a new name creates a cell of level k. No sigil is needed.
- **Cells are placed with `/`.** The slash rules hold unchanged: one cell between two sides is attached to them, and two or more cells in a chain form a cycle. `f/α/g` is α : f ⇒ g, and the pair there and back is `f/α/g/β`.
- **Each diagram keeps one table of names, each with its level.** At level k, a name not in the table is a new k-cell; a name of a lower level is a side, standing where a named node stands at level 1; a name of level k is a cell of this level, so using it again is declared twice. Named nodes are level 0, which is why level 1 reads them as nodes.
- **A lower side is an identity.** A side of level j < k−1 stands for its identity at level k−1, as every cell x has an identity 1_x one level up: `#A/f/#A | f/α/#A` is α : f ⇒ 1_A, and `α/m/f` at level 3 is m : α ⇛ 1_f. 1_x has source and target x, so parallelism still holds: α : f ⇒ 1_A needs f : A → A.
- **No unnamed sides.** At level 1 a node may be unnamed, since nodes are derived. Above it, a node is a (k−1)-cell, and fAB has no nameless edges, so every side is a name: `f/α β/g` would need a 1-cell between α and β, and is an error at level 2. For the same reason there is nothing to pinch above level 1, and `*`, `?`, `!` and other diagrams' nodes belong to level 1 only.
- **Vertical composition** is two attachments, `f/α/g, g/β/h`, or a space landing on the shared side, `f/α g/β/h`: α's target meets g, which is named.
- **Sides are always single, named cells.** There are never paths as sides, and never parentheses around a side.
- **Undirected sides and cells.** A cell may lie on undirected edges: their endpoints must agree as an unordered pair, so undirected f between A and B is parallel to g : B → A. A cell may itself be undirected, with the trailing `/` of a one-cell chain: `f/α/g/`. Neither is category theory; the declaration describes them, and a proof environment that proves against a category flags them (Open questions, Coming).
- **`|` appears only at the top of a declaration's right side,** inline or in its braces. A group never holds `|`: `G :: f (g | α)` is an error, because a level cannot live inside a branch.

| Level | Form      | Meaning                                              |
| ----- | --------- | ---------------------------------------------------- |
| 1     | `+f/g/f+` | g : +f → f+, a new edge between two existing nodes   |
| 2     | `f/α/g`   | α : f ⇒ g, a new 2-cell between two existing edges   |
| 3     | `α/m/β`   | m : α ⇛ β, a new 3-cell between two existing 2-cells |

```
Nat :: +(f, g)+ | f/α/g                    // a natural transformation
Eq  :: +(f, g)+ | f/α/g/β                  // α : f ⇒ g and β : g ⇒ f
Vc  :: +(f, g, h)+ | f/α/g, g/β/h          // α then β: vertical composition
Vs  :: +(f, g, h)+ | f/α g/β/h             // the same, with a space
Mod :: +(f, g)+ | f/(α, β)/g | α/m/β       // two 2-cells and a modification
Id  :: #A/f/#A | f/α/#A                    // α : f ⇒ 1_A, a side from a lower level
Ud  :: #A/f/#B/, #B/g/#A | f/α/g           // a cell on an undirected edge
```

**Composites as sources.** A 2-cell whose source is a composite, such as α : f h ⇒ g, cannot be written directly, since sides are named. The composite is named first at level 1, and the proof layer states that it is the composite:

```
W :: +(f h, k, g)+ | k/α/g
W :prove := { k == f h }
```

Structure stays a plain graph at every level, and composites are facts stated by proofs, not shapes the syntax must express.

**Multi-line declarations** use braces, which may contain the `|`:

```
Iso :: {
  +(f, g)+
  | f/α/g/β
}
```

**Kind.** Cells are declared the same way in every diagram. A category draws them as 2-cells and above; a flow draws none of them, since a flow shows steps, not relations between steps. They stay part of the program: other layers can still refer to them.

## Values and definitions

### Three forms, never bare

A value is always written in exactly one of three forms:

| Form  | For                                 | Example                                                                              |
| ----- | ----------------------------------- | ------------------------------------------------------------------------------------ |
| `"…"` | text                                | `:label "Order received"`; inline math allowed: `"x = $\alpha$"`; `\n` breaks a line |
| `$…$` | math                                | `:label $\mathbb{R}$`                                                                |
| `[…]` | everything else: names and literals | `[red]`, `[circle]`, `[#ff0000]`, `[/solid/>]`, `[12]`, `[0..*/1..1]`                |

Numbers go in brackets too: `:width [2]`. The only exception is a **flag**, an attribute written with no value at all, such as `:hide`.

### The bracket token

- `[ … ]` is **one opaque token**. Its contents are any characters except whitespace, `[` and `]`.
- No whitespace inside: `[0..*/1..1]`, not `[0..* / 1..1]`. Text with spaces belongs in `"…"`.
- No nesting. Lists, if needed, live inside one token with commas: `[dark,compact]`.
- Because the main grammar never looks inside, symbols there cannot clash with their meaning outside: `[#ff0000]` is a colour, and `#A` outside is a node.
- Brackets appear only in value position, and as the left side of a value definition. Never in a declaration, and never as a subject.

**How a bracket is read.** One rule, by shape, gives every bracket exactly one kind:

| Bracket                        | Is                           | Examples                                         |
| ------------------------------ | ---------------------------- | ------------------------------------------------ |
| contains exactly two `/`       | an arrow                     | `[/solid/>]`, `[?/solid/>]`, `[>/wavy/X]`        |
| starts with a lowercase letter | a name                       | `[red]`, `[circle]`, `[warn-bg]`, `[epi]`        |
| starts with `#`                | a colour                     | `[#c0392b]`, `[#f00]`                            |
| starts with a digit            | a number; with `..`, a range | `[2]`, `[0.5]`, `[30!]`, `[0..*]`, `[0..*/1..1]` |

The value's type then comes from what the attribute expects: `:ink` reads a colour, `:arrow` an arrow. `:shape [red]` is a type error ("a colour where a shape is expected").

### `!` inverts what it follows

Inside brackets `!` has one meaning, as `/` does: it inverts what it follows.

| After             | Inverts                             | Example         |
| ----------------- | ----------------------------------- | --------------- |
| a line word       | its meaning: struck, "does not"     | `[/solid!/>]` ↛ |
| a hook or harpoon | its side: inner instead of outer    | `[/solid/^!]`   |
| an angle          | its side: inward instead of outward | `:bend [30!]`   |

So there are **no negative numbers**: every number starts with a digit.

### Units

Lengths are numbers in **em**, relative to the theme's text size. Angles are in **degrees**. A fraction is a number from 0 to 1, a position along an edge.

### Definitions

- **Values:** `[red] := [#ff0000]`. Aliases are allowed: `[warn] := [red]`. The type is inferred from the right side.
- **Bundles:** `:terminal := { :shape [circle], :fill [red] }`. A bundle is a named set of attributes. Writing it applies its contents, exactly as if they were written there; later settings refine it: `#Done :terminal :fill [green]`.
- **Themes:** `[dark] := { &zone :fill [#1e1e1e], &node :stroke [#dddddd] }`. A theme is a named style: subjects with attributes. A bundle holds attributes only; a theme holds subjects.
- **Names** start with a lowercase letter, are defined once, and come before their first use. Built-in names cannot be redefined.

### The prelude

The prelude is ordinary fAB source, compiled into `fab`. It defines the base theme (every default of the style layer), the built-in values (colour names, theme tokens, keywords), the named arrows, and the built-in themes. The defaults are documented by being written in the language itself.

## Subjects and classes

The subjects of definitions are the things a style, a proof or a placement talks about.

| Subject                      | Written                            | Example                                              |
| ---------------------------- | ---------------------------------- | ---------------------------------------------------- |
| a diagram                    | its name                           | `G :style := { … }`                                  |
| an edge or a cell            | its name, qualified by its diagram | `G.f :stroke := [red]`                               |
| a node, by its canonical end | `+f`, `f+`                         | `G.+f :label := $P$`                                 |
| a named node                 | `#Name`                            | `G.#Done :shape := [box]`                            |
| a class                      | `&name`                            | `&node :shape := [circle]`, `G.&edge :pen := [thin]` |
| several subjects             | a group                            | `(yes, paid) :label "yes"`                           |

**Canonical references.** A node is addressed only through its canonical reference: its name if it has one (`#A`, `@`), and otherwise the first end that created it, in reading order. In `f g`, the middle node is `f+`, never `+g`. In `+(f h, g k)+`, the canonical references are `+f` (the pinched start), `f+`, `g+` and `f h`'s end `h+` (the pinched end); `+g`, `+h`, `+k` and `k+` are rejected.

**Classes carry the sigil `&`,** and are qualified with `.` like anything else: `G.&edge` is every edge inside G. A class is a marked name, so no words are reserved; an edge may be called `edge`, and `G.edge` means exactly that edge.

| Class                                                       | Covers                                                                                                                         |
| ----------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------ |
| `&node`                                                     | every node                                                                                                                     |
| `&plain`, `&choice`, `&parallel`, `&start`, `&end`, `&hole` | nodes by kind; a start is a null node no edge arrives at, an end one some edge arrives at; a hole is left by an analysis error |
| `&canonical`                                                | nodes labelled by their canonical end (cuts across the kinds)                                                                  |
| `&edge`                                                     | 1-cells                                                                                                                        |
| `&cell`                                                     | 2-cells and above                                                                                                              |
| `&zone`                                                     | diagrams, standalone or drawn inside another                                                                                   |

**Specificity,** from general to narrow; where subjects overlap, the narrower wins:

1. a class (`&node`);
2. a narrower class (`&choice`, `&canonical`);
3. a class inside a diagram (`G.&node`);
4. a single element (`G.+f`, `G.#Done`, `G.f`).

Specificity orders bindings within a layer of style; layers compose on top (see Style layer, Themes).

**Each diagram styles itself.** When C references A, A is drawn inside C as a cluster, and keeps its own style. C styles only C's own subjects, including C's edges that reach into A.

## Style layer

`G :style := { … }` gives everything drawn in G its appearance. It never changes the graph, never refers to one element from another, and never names a direction on the page: everything is relative to the element, its text, or the diagram's own shape. A diagram can flow towards any cardinal point and every style still means the same.

```
G :: f g

G :style := {
  f  { :arrow [epi], :stroke [#c0392b] },
  +f {
    :label $\mathbb{R}$,
    :shape [circle]
  },
  f+ :label $\mathbb{N}$,
  g+ :label $\sigma$
}
```

There is one word per concept, and text and line words are never shared: `:font`, `:face`, `:size` and `:ink` are about lettering; `:pen`, `:stroke`, `:arrow` and `:line` are about lines. Three paints, one each: `:ink` for text and math, `:stroke` for lines and borders, `:fill` for areas.

Applies to: **N** nodes, **E** edges, **C** cells, **Z** diagrams.

### Text

| Attribute | Applies to | Values                                           | Default                                                                                                                                                  |
| --------- | ---------- | ------------------------------------------------ | -------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `:label`  | N E C Z    | text, math                                       | node: its name without `#`, else its canonical end; edge, cell, diagram: its name. Choices, parallels, starts and ends have no label unless one is given |
| `:font`   | N E C Z    | text (a font name)                               | theme                                                                                                                                                    |
| `:face`   | N E C Z    | `[regular]` `[italic]` `[bold]` `[bold-italic]`  | `[regular]`; `[italic]` for `&canonical`                                                                                                                 |
| `:size`   | N E C Z    | length: the size of the lettering, and only that | theme; edge and cell labels smaller                                                                                                                      |
| `:ink`    | N E C Z    | colour                                           | `[ink]`; `[soft]` for edge and cell labels; `[muted]` for `&canonical`                                                                                   |

### Nodes

| Attribute           | Values                                                                                                                                                                                          | Default                           |
| ------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | --------------------------------- |
| `:shape`            | `[none]` `[box]` `[round]` `[circle]` `[double-circle]` `[ellipse]` `[stadium]` `[diamond]` `[hexagon]` `[parallelogram]` `[cylinder]` `[document]` `[bar]` `[point]` `[terminal]` `[bullseye]` | by kind                           |
| `:fill`             | colour                                                                                                                                                                                          | none                              |
| `:stroke`           | colour                                                                                                                                                                                          | `[ink]`                           |
| `:pen`              | `[thin]` `[normal]` `[thick]`                                                                                                                                                                   | `[normal]`                        |
| `:line`             | `[solid]` `[dashed]` `[dotted]` `[double]` `[wavy]` `[none]`                                                                                                                                    | `[solid]`; `[dashed]` for `&hole` |
| `:width`, `:height` | length, as minimums                                                                                                                                                                             | fitted to the label               |
| `:padding`          | length                                                                                                                                                                                          | theme                             |
| `:align`            | `[start]` `[center]` `[end]`: the start of a line of text, whatever the script                                                                                                                  | `[center]`                        |
| `:wrap`             | length                                                                                                                                                                                          | none                              |

### Edges and cells

| Attribute                    | Values                                                           | Default                                                                      |
| ---------------------------- | ---------------------------------------------------------------- | ---------------------------------------------------------------------------- |
| `:arrow`                     | an arrow                                                         | `[/solid/>]` for edges, `[/double/>]` for 2-cells, `[/triple/>]` for 3-cells |
| `:stroke`                    | colour                                                           | `[ink]`                                                                      |
| `:pen`                       | `[thin]` `[normal]` `[thick]`                                    | `[normal]`                                                                   |
| `:bend`                      | `[outer]` `[inner]`, or an angle: `[30]` outward, `[30!]` inward | none: straight                                                               |
| `:label-start`, `:label-end` | text, math                                                       | none                                                                         |
| `:label-at`                  | `[start]` `[mid]` `[end]`, or a fraction                         | `[mid]`                                                                      |
| `:side`                      | `[outer]` `[inner]` `[on]`                                       | `[outer]`                                                                    |
| `:shorten`                   | length                                                           | none                                                                         |

An edge has no `:line`: its line is part of `:arrow`.

### Diagrams

| Attribute                   | Values                                               | Default                                             |
| --------------------------- | ---------------------------------------------------- | --------------------------------------------------- |
| `:as`                       | `[flat]` `[cluster]` `[node]` `[table]`              | `[cluster]`                                         |
| `:fill`                     | colour                                               | none                                                |
| `:stroke`                   | colour                                               | none: an unframed cluster                           |
| `:pen`, `:line`, `:padding` | as for nodes                                         |                                                     |
| `:caption`                  | text, math                                           | none                                                |
| `:theme`                    | theme names, applied left to right: `[dark,compact]` | none: the base theme alone                          |
| `:marks`                    | `[all]` `[none]`                                     | `[all]`: draw marks from the proof layer, such as ⌟ |
| `:cross`                    | `[gap]` `[plain]`                                    | `[gap]`                                             |

A diagram is drawn framed only if it has a `:stroke` or a `:fill`: borders are always explicit. `table` draws the edges leaving `@` as rows inside the frame, each showing the edge's label and its target.

**Foreign-key rows.** In a schema, each foreign key leaving a table drawn `[table]` is a row of that table too. Its default label is the edge's name, `_`, and the name of the key it references: `parent` referencing `Comment.id` is drawn `parent_id`. Its type is the type of the target's key. Its arrow leaves the row and ends at the target's key row. The label is the column's name; `:label` overrides it: `writer :label "author_id"`.

### Behaviour

| Attribute | Applies to | Values       | Effect                                      |
| --------- | ---------- | ------------ | ------------------------------------------- |
| `:hide`   | N E C      | flag         | kept in the graph and the layout, not drawn |
| `:note`   | N E C Z    | text         | shown on hover, never drawn                 |
| `:link`   | N E C Z    | text (a URL) | the subject links to it                     |
| `:step`   | N E C      | number       | reveal order when presenting                |
| `:alt`    | Z          | text         | a description for screen readers            |

### Arrows

An arrow is three fields: `[tail/line/head]`. The ends are symbolic glyphs, the line is a word. `tail` and `head` may be empty; `line` is required. The arrow only draws: the edge's direction always comes from the relations.

**Lines** use the words of `:line`, plus `triple`: `solid`, `dashed`, `dotted`, `wavy`, `double` (2-cells, ⇒), `triple` (3-cells, ⇛), `none`. A `!` suffix strikes the line: `[/solid!/>]` is ↛, "does not".

**Ends are read as a picture, left to right.** Each end is written as it looks when reading from tail to head, and any glyph may go at either end: `[/solid/<]` puts a backward-pointing head at the target end, `[</solid/>]` points both ways, `[>/solid/>]` is a mono ↣.

| Glyph                                                      | End                                                      |
| ---------------------------------------------------------- | -------------------------------------------------------- |
| `>` `<`                                                    | arrowhead, pointing as drawn                             |
| `>>` `<<`                                                  | two heads                                                |
| `\|>` `<\|`                                                | hollow triangle                                          |
| `\|`                                                       | bar                                                      |
| `O`                                                        | hollow circle                                            |
| `@`                                                        | filled circle                                            |
| `X`                                                        | cross                                                    |
| `<>`                                                       | hollow diamond                                           |
| `<@>`                                                      | filled diamond                                           |
| `?`                                                        | hook                                                     |
| `^`                                                        | harpoon                                                  |
| `\|\|` `O\|` `\|{` `O{` (as tails `\|\|` `\|O` `}\|` `}O`) | crow's feet: one, zero or one, one or more, zero or more |

**Hooks and harpoons have a side:** the outer side by default, the inner side with `!` (`?!`, `^!`). A pair of harpoons ⇌ between two parallel arrows has each barb facing out, automatically.

| Arrow                                    | Reads as                        |
| ---------------------------------------- | ------------------------------- |
| `[/solid/>]`                             | → plain                         |
| `[>/solid/>]`                            | ↣ mono                          |
| `[/solid/>>]`                            | ↠ epi                           |
| `[?/solid/>]`                            | ↪ inclusion                     |
| `[\|/solid/>]`                           | ↦ maps to                       |
| `[</solid/>]`                            | ↔ both ways                     |
| `[/dashed/>]`                            | ⇢ unique existence              |
| `[/double/>]`, `[/triple/>]`             | ⇒, ⇛ cells                      |
| `[/wavy/>]`                              | ⇝                               |
| `[/solid!/>]`                            | ↛ does not                      |
| `[/solid/^]`, `[/solid/^!]`              | ⇀ harpoon, outer or inner       |
| `[/solid/O]`, `[/solid/@]`, `[/solid/X]` | lollipop, solid lollipop, cross |
| `[/solid/\|]`, `[/solid/\|>]`            | ⊣ inhibition, generalization    |
| `[<>/solid/]`, `[<@>/solid/]`            | aggregation, composition        |
| `[\|\|/solid/O{]`                        | one to zero-or-more             |

The prelude names the common arrows: `[mono]`, `[epi]`, `[incl]`, `[mapsto]`, `[unique]`, `[iso]`. The literal covers anything unusual.

### Geometry without directions

**Inner and outer.** Sides are measured against the diagram's own shape. `[outer]` is the side away from the region an edge borders, `[inner]` the side facing it. The region is the face of a cycle the edge lies on, else the side facing the diagram's centre. Inner and outer are invariant under every rotation and reflection, unlike left and right of travel, which flip when a layout is mirrored.

- **`:side`** places labels outside by default, as mathematicians draw squares and triangles. `[on]` places the label on the line.
- **`:bend`** bows an edge outward or inward. `+(f, g)+` with `&edge :bend [outer]` bows the two arrows apart into a lens.

**Crossings.** How crossings are drawn is one decision per diagram. With `:cross [gap]`, the default, the upper line is drawn with a gap cut around it, so the lower line visibly passes underneath; labels crossing or sitting on a line get the same gap. The upper line is the one drawn later; the gap takes the diagram's background colour. `:cross [plain]` lets lines simply cross.

**Inside one subject,** the drawing order is fixed: gap, fill, line, label on top.

### Kind defaults

| Class        | Default                                                                                                |
| ------------ | ------------------------------------------------------------------------------------------------------ |
| `&plain`     | `[circle]`, label inside; every circle in a diagram drawn at one diameter, fitted to the longest label |
| `&choice`    | `[diamond]`, no label                                                                                  |
| `&parallel`  | `[bar]`, no label; as wide as its busier side needs                                                    |
| `&start`     | `[point]` (a filled dot), no label                                                                     |
| `&end`       | `[bullseye]`, no label                                                                                 |
| `&hole`      | `[circle]`, `:line [dashed]`, labelled by its canonical end if it has one                              |
| `&canonical` | `:face [italic]`, `:ink [muted]`                                                                       |
| `&edge`      | `:arrow [/solid/>]`, `:ink [soft]`, smaller `:size`                                                    |
| `&cell`      | `:arrow [/double/>]` or `[/triple/>]`, `:ink [soft]`, smaller `:size`                                  |
| `&zone`      | `:as [cluster]`, unframed, `:cross [gap]`                                                              |

### Themes

A theme is a named style (see Values and definitions). Styles compose in layers, the later winning wherever both set a value:

```
base  <  themes, left to right  <  the program's own bindings
```

- **The base theme always applies.** It binds every attribute for every kind, so every element always has every attribute: the style is a total function, and themes and programs only override parts of it.
- **"Each binding once" holds within a layer;** across layers, the later one wins, deliberately and in order.
- **`:theme`** chooses themes for a diagram, and cascades to nested diagrams: `Order :theme := [dark,compact]`.
- **Theme tokens** are colour names whose value the theme decides: `[ink]` (lines and text), `[soft]` (edge labels), `[muted]` (canonical labels), `[accent]`.

## Place layer

`G :place := { … }` says where things go. Unlike style, it is relational by nature: placement relates one element to another. Its vocabulary is open, and will be designed with fAB's own layout engine. What is settled:

- **Direction-agnostic.** The overall flow is given by a cardinal point. Placement within it uses relative ranks, along the flow and across it, without the words vertical and horizontal.
- **Drawing order is source order.** Without anything in `:place`, branches are drawn in the order they are written, and what is written later is drawn on top. So in `#X/(g1, f, g2)`, f is drawn between g1 and g2.
- **What belongs here:** relative placement (what the first revision called `:right-of`), ranks and grid cells, the overall direction, layout and routing styles, spacing, which side of a node a loop sits on, and stacking between elements.
- **A strict grid** (every node on an integer coordinate) is a layout of this layer, for the native engine.

## Proof layer

`G :prove := { … }` states what holds in the diagram. Its items are propositions of two forms, equations and properties, side by side: the block is their conjunction.

```
Sq :: +(f h, g k)+

Sq :prove := {
  f h == g k,        // path == path: the square commutes
  +f :pullback       // subject :property
}
```

- **Chains of equations** state each step: `f h == g k == d` is `f h == g k` and `g k == d`.
- **One level, no precedence.** The operators between chains, `==` and `~=` today and any the layer adds later, share one level and read left to right. A run may repeat one operator; different operators need a group: `(f == g) ~= h`, never `f == g ~= h`.
- **Groups organise.** A proposition, or several, may be grouped: `(f h == g k, +f :pullback)`. The group changes nothing.

- **Equations** relate two paths, written with juxtaposition in diagrammatic order. Both sides must be existing paths with the same start and end. Equations are not settled: they are written `==`, and `~=` is reserved for a weaker relation whose meaning is open (see Open questions).
- **Identities are equations.** `+f` denotes the identity on dom(f), so `f == +f` says that the endomorphism `f/f` is an identity. No keyword is needed.
- **Universal properties** attach to a node. `+f :pullback` takes the commuting square that starts at `+f` as its cone. If no such square, or more than one, starts there, the statement is rejected and the square must be given explicitly.
- **Pushouts mirror pullbacks.** `#M :pushout` takes the commuting square that ends at `#M` as its cocone, with the same rule.
- **States, not proofs.** The checker verifies that every statement is well formed. Whether an arbitrary equation is true cannot be decided in general (commutation is a word problem), so the layer states facts; consequences and what is drawn for them are open.
- **Composites.** Naming a composite at level 1 and stating it here (`k == f h`) is how cells get composite sources (see Levels).

### Schema statements

In schemas, the proof layer states keys and constraints. Properties without a value are flags.

| Statement        | Says                                                             |
| ---------------- | ---------------------------------------------------------------- |
| `:pk`            | the key: mono, one per table, referenced by every foreign key |
| `:uk`            | another key: mono, any number per table                       |
| `:nullable`      | the column, or the foreign key, may be empty                  |
| `:required`      | on a choice group: exactly one member is set                  |
| `:card [0..*/1]` | the cardinality at the edge's source, then at its target      |
| `:refs`          | on a foreign key and a key of its target: the key it references |

**Groups of columns** take the table once, with the same dot notation as cross-diagram references, and the group's marker says how the columns combine. Foreign keys live in the joining diagram, so a group of them is written unqualified, and must share their source table.

- **Each:** `User.(email, nick) :uk` makes each column a key on its own.
- **Together:** `User.(email, nick)! :uk` makes the pair a key, read as ⟨email, nick⟩ : User → String × String being mono; `(user, org)! :uk` does the same for two foreign keys of Membership. A composite primary key is `Table.(a, b)! :pk`; `Table.(a, b) :pk` is an error, because it gives the table two keys.
- **One of:** `(post, photo)? :required` says exactly one of two foreign keys is set; each must also be `:nullable`. Categorically, the two edges are one arrow into the sum Post + Photo.
- **Not a key:** juxtaposition inside a group is a path, so `User.(email nick)` is an error.

The three group forms are the three ways columns combine: each on its own, together as a product, or one of them as a sum.

**Foreign keys** always go from the table holding them to the table they reference, so they compose like functions. The checker verifies that the target has a `:pk`, that a target end of `0..1` is `:nullable`, and that a source end of at most one is `:uk`.

**Referenced keys.** A foreign key references its target's `:pk`. To reference another key, as SQL allows, state it on the pair: `(author, User.email) :refs`. The group holds one foreign key and one key of its target, in either order. The choice changes how the relationship is stored, not the relationship: the pair denotes the composite `author User.email`, the column the table stores. The row is drawn `author_email`, typed as `User.email`, with its arrow to the `User.email` row.

**Local defaults.** A proof block can state a default for a class of subjects. Nothing is defaulted unless the author writes it.

- `&node` ranges over the diagram's nodes, which in a schema are its tables; `&node.id` is each table's `id` column. `&edge` ranges over its edges.
- **Explicit wins.** A statement about a specific subject overrides the default, by specificity.
- **No guessing.** If a default matches no column, or several, for some subject, that is an error at that subject until an explicit statement covers it.

**Derived marks attach to existing subjects.** Crow's feet come from `:card` but are drawn on the relationship edge, which the style layer styles as usual.

## Errors

A program that hits any of these is rejected, each with its precise cause. Warnings are marked as such. Rows marked *reserved* are errors because their meaning is still open (see Open questions); lifting one later breaks no program.

**Every program draws something.** A diagnostic that belongs to an element of the graph marks that element: a hole, an edge, the node where two names met. Each diagram is drawn with a border in the colour of its most severe diagnostic: error, then warning. A diagnostic with no element of its own, such as one in a statement or in a definition about the diagram, shows only as that border. A statement that names no diagram (`review :: a b`, `[red] :: f`, `:x := a | b`) draws a placeholder in its place: a small square with that border, crossed corner to corner. A statement with a syntax error, anywhere from its first token to the next statement, is not read at all: it draws the same placeholder, under its diagram's name when its head names one (`G :: f ]] g` draws G's placeholder, not a G holding only `f`). That diagram counts as declared but broken, so what refers into it (`G.+f`) is a hole with no error of its own. So even a program with nothing valid in it renders, and an image embedded in a document always shows what went wrong, and never a drawing that is wrong.

### Statements

| Error                              | Example                                      | Why                                                              |
| ---------------------------------- | -------------------------------------------- | ---------------------------------------------------------------- |
| Statement spanning lines           | `Db :: (` with `)` on a later line           | A statement is one line; braces let it span lines                |
| Missing comma                      | `#Done :terminal f :label "x"`               | Items are separated by commas                                    |
| Trailing comma                     | `(f, g,)`, `{ a :x, }`                       | A comma stands between items only                                |
| Empty braces                       | `G :: {}`, `G :style := {}`                  | There are no empty declarations or definitions                   |
| Bare term in a definition          | `yes, paid :label "yes"`                     | Several subjects are a group: `(yes, paid) :label`               |
| Entry or equation in a declaration | `G :: f (g :label "x")`                      | A declaration's items are terms                                  |
| Class in a declaration             | `G :: &node f`                               | Classes are subjects of definitions only                         |
| Levels in a definition             | `:x := a \| b`                               | `\|` separates the levels of a declaration                       |
| Declaration head not a diagram     | `[red] :: f`, `G :style :: f`                | Only diagrams, nodes and edges are declared                      |
| Reserved: node or edge declared    | `#User :: @/(id, name)`, `review :: a b`     | What declaring a node or an edge means is open                   |
| Definition head of no form         | `f g := [red]`, `G := [red]`                 | A definition's left side is `[name]`, `:attr` or `subject :attr` |
| Warning: chain broken across lines | `f g` then `h k` on the next line, in braces | Write `,` for two items, or group the chains                     |

### Relations

| Error                             | Example                                         | Why                                                                        |
| --------------------------------- | ----------------------------------------------- | -------------------------------------------------------------------------- |
| Diagram declared twice            | `G :: f` … `G :: g`                             | One declaration per diagram                                                |
| Edge or cell declared twice       | `f g f`, `f/α/g, f/α/g` at level 2              | A bare name declares; only `f/f` repeats it                                |
| Self-reference outside `f/f`      | `(f g)/f`                                       | A loop needs a single edge on the left                                     |
| Redundant self-attachment         | `f/+f`                                          | Same graph as `f/f`                                                        |
| Vacuous self-attachment           | `f/f+`                                          | Glues an end to itself                                                     |
| `/` between nodes only            | `+g/+f`, `#A/#B`, `#A/?`, `f/#A/#B/g`, `#A/#B/` | `/` needs an edge between its sides                                        |
| Slash between two groups          | `(f, g)/(h, k)`                                 | Gluing many ends to many is a collapse nobody wrote; pinch one side: `(f, g)+/(h, k)` |
| Trailing `/` not on one edge      | `f/g/`, `(f, g)/`, `(f g)/`, `#B/`              | A trailing `/` makes one edge undirected: `f/ g/`                          |
| Cycle that does not close         | `#A/f/#B/g/#C`, `+f/m/n/g+`                     | A chain of two or more edges ends where it began                           |
| Reference not declared            | `+k/g`, `gg/α/g` with k, gg undeclared          | A reference needs its edge declared before it                              |
| Forward reference                 | `+f/g f`                                        | References point left only                                                 |
| Node beside a space               | `#A f`, `* f`, `@ (…)`, `f User`                | A node is attached to an edge with `/`                                     |
| Ends don't match                  | `f (g, h)`, `(f, g) h`, `(a, b) (c, d)`         | A space joins one end to one end; pinch the group: `f +(g, h)`             |
| Nothing to join                   | `f/g h`, `f/* g`, `(f/*)/g`                     | One side exposes nothing; write `,` for separate pieces                    |
| Warning: a space reaches one branch of several | `(f/*, g) h`, `(f, #A) g`, `+(g/*, h) k` | The other branches expose nothing there; move the step into the branch: `f/*, g h` |
| Pinch of declared edges           | `f g, h k, +(f, h)`                             | A pinch with several branches declares them                                |
| Pinched edge beside a space       | `f? (g, h)`, `k +f`, `f+ g`                     | A pinched single edge is a node; to pinch the group, move the marker: `f/? +(g, h)` |
| Single edge pinched on both sides | `+f+`, `+(f)+`                                  | A pinched edge is one node; it has one side                                |
| Pinch of a node                   | `+#A`, `#A?`, `(@)+`                            | A pinch merges the ends of a group; a node has none: attach it with `/`    |
| Pinch of nothing                  | `(f/*, g/*)+`                                   | Every branch exposes nothing on that side                                  |
| Warning: pinch of one end         | `+(f, #A)`, `(a, b/b)! k`                       | The pinch merges one end with nothing; write the pieces apart: `a/! k, b/b` |
| Kind on the left                  | `?(g, h)`, `!f`, `?/f`, `f/?/g`                 | A kind is written where flow arrives: `f/?`, `(a, b)?`                     |
| Kind closing a cycle              | `f/g/?`                                         | A cycle ends on its start, so the kind would sit on the left of f          |
| Lone kind                         | `?`, `(!)`                                      | A kind marks where flow arrives, and nothing arrives here                  |
| Kind on a reference               | `f?`, `A.f/?`                                   | A kind is set where its node is created: `f/?` where f is declared         |
| Kind after a group                | `(a, b)/?`                                      | After a group, the kind is a pinch: `(a, b)?`                              |
| Warning: kind after a group of one | `(f)/?`                                        | A group of one is its item: write `f/?`                                    |
| Marker touching both sides        | `f+(g, h)`, `(a, b)!(c, d)`                     | Write `f +(g, h)` or `(a, b)! +(c, d)`                                     |
| Kinds disagree                    | `(a/?, b/!)+`, `validate/? #Valid/yes`          | A node has one kind, and a named node is plain                             |
| Two names for one node            | `a/#A #B/b`                                     | One node, one name                                                         |
| Reference to a null node          | `k f/*, j/f+`                                   | A null node is private to its edge end                                     |
| `*` not on exactly one end        | `*`, `*/(f, g)`, `(f, g)/*`, `*/+(f, g)`, `f/*/g` | A null node holds exactly one edge end; write `(*/f, */g)`                 |
| Both ends null                    | `*/f/*`                                         | An edge from nothing to nothing says nothing                               |
| Tight operator touching nothing   | `f / g`, `+ f`                                  | A tight operator attaches to what it touches                               |
| Atoms touching                    | `f(g)`, `*f`, `#A(f)`                           | Only `/` joins what touches; write a space for a path, or `/` to attach    |
| Prefix `/`                        | `f /g`                                          | `/` is binary or postfix only                                              |

### Levels

| Error                            | Example                        | Why                                                             |
| -------------------------------- | ------------------------------ | --------------------------------------------------------------- |
| Empty level                      | `G :: f \| \| m`               | Every level declares something                                  |
| Level inside a branch            | `G :: f (g \| α)`              | `\|` appears only at the top of a declaration                   |
| Side not declared                | `+(f, g)+ \| f/α/#B`          | Only level 1 makes nodes; above it a named node is a side       |
| Cells between non-parallel cells | `f/α/h` in a square, `f/α/#B` with f : A → B | α : f ⇒ h needs f and h to share start and end; 1_B starts at B |
| Path as a side                   | `(f h)/α/g`                    | Sides are single named cells; name the composite first          |
| Unnamed side                     | `f/α β/g`, `α`, `(α, β)/g` at level 2 | Every end of a cell lands on a named cell; `f/α β/g` needs a 1-cell between α and β |
| Two names for one side           | `f/α/g h/β/k` at level 2       | The space puts g and h in one place; each cell keeps its own sides |
| Not a cell                       | `+(f, g)+ \| f/α/*`, `f/α/?`, `f/α/A.#X` | `*`, kinds and other diagrams' nodes are level 1 only |
| Pinch above level 1              | `+(α, β)`, `+α/β/g` at level 2 | Sides are named, so there is nothing to pinch                    |

### Definitions and values

| Error                               | Example                       | Why                                                          |
| ----------------------------------- | ----------------------------- | ------------------------------------------------------------ |
| Undefined name                      | `:ink [wran]`                 | Every name is defined before its use                         |
| Name defined twice                  | `[red] := …` twice            | Each name is defined once                                    |
| Built-in redefined                  | `[epi] := …`                  | The prelude's names are fixed                                |
| Uppercase name                      | `[Warn]`                      | Names start with a lowercase letter                          |
| Bare value                          | `:width 2`                    | Values are written `"…"`, `$…$` or `[…]`                     |
| Space inside brackets               | `[0..* / 1]`                  | A bracket is one token                                       |
| Negative number                     | `[-30]`                       | Numbers are never negative; for the inner side write `[30!]` |
| Value in a declaration              | `+(g1, [f], g2)`              | Brackets are values only                                     |
| Wrong type                          | `:shape [red]`                | A colour where a shape is expected                           |
| Flag given a value, value missing   | `:hide [on]`, `:shape`        | Flags take no value; other attributes need one               |
| Binding made twice in a layer       | `#Done :shape` twice          | Each (subject, attribute) pair is bound once                 |
| Definition at an undeclared subject | `G :style := …` before `G ::` | A definition comes after what it talks about                 |
| Unknown class                       | `&nodes`                      | Classes are built in, or defined                             |
| Theme and bundle mixed up           | a bundle in `:theme`          | A theme holds subjects; a bundle holds attributes            |
| Attributes side by side             | `f :label "x" :bend [inner]` | An entry has one attribute; several go in braces: `f { :label "x", :bend [inner] }` |

### Style

| Error                                  | Example                                                    | Why                                                          |
| -------------------------------------- | ---------------------------------------------------------- | ------------------------------------------------------------ |
| Unknown attribute                      | `:colour`                                                  | Did you mean `:ink`, `:stroke` or `:fill`?                   |
| Attribute that does not apply          | `:fill` on an edge, `:arrow` on a node, `:line` on an edge | An edge's line is part of `:arrow`                           |
| Value not among the attribute's values | `:side [sideways]`                                         | Expected `[outer]`, `[inner]` or `[on]`                      |
| Direction word                         | `:side [left]`                                             | Styles never name a direction on the page                    |
| Relational value                       | a style value that names `g`                               | Placement belongs in `:place`                                |
| Non-canonical reference                | `+g :label …` in `f g`                                     | Label the node through `f+`, the end that created it         |
| Another diagram's subject              | `A.+f` styled from C                                       | Each diagram styles itself                                   |
| Arrow without a line                   | `[//>]`                                                    | An arrow needs a line, such as `solid`                       |
| Unknown line word or end               | `[/zigzag/>]`, `[/solid/%]`                                | Lines are words from a fixed list; ends from the glyph table |
| `!` on an end without a side           | `[/solid/>!]`                                              | Only hooks `?` and harpoons `^` have a side                  |
| `!` on a number without a side         | `:size [2!]`                                               | Only `:bend` angles have a side                              |
| Head on an undirected edge             | `f/` with `:arrow [/solid/>]`                              | The drawing would show a direction the relations don't have  |

### Named nodes and schemas

| Error                                        | Example                                                      | Why                                                                               |
| -------------------------------------------- | ------------------------------------------------------------ | --------------------------------------------------------------------------------- |
| Node named twice                             | `a/#A #B/b`                                                  | One node, one name                                                                |
| Named node referenced by an end              | `+f :label …` where dom(f) is `#A`                           | A named node is referenced by its name                                            |
| Diagram without `@` used as a node           | `Db :: T/owns/User`                                          | Only a diagram with an own node can attach                                        |
| Undeclared name in another diagram           | `T.#UUDI7`, `A.+k`                                           | Names never come into existence by being mentioned                                |
| Diagram not declared before                  | `B :: h/A.+f` before `A ::`, `G :: G/f`                      | References point left; a diagram names its own node with `@`                      |
| Another diagram's edge in relations          | `A.f g`, `A.(f, g)`                                          | `.` reaches a node: `A.f+`, `A.#X`, `A.@`                                         |
| Foreign key to a table without a key         | an edge to `Tag` with no `Tag.… :pk`                         | A foreign key references the target's key                                         |
| Reference to a column that is not a key      | `(author, User.name) :refs`, `User.name` not `:uk`           | A foreign key references a key                                                    |
| `:refs` without a foreign key and its target | `(author, Tag.label) :refs` where `author` goes to User      | The group pairs one foreign key with a key of its target                          |
| One-to-one without a unique key              | `:card [0..1/1]`, edge not `:uk`                             | One-to-one needs a unique key                                                     |
| Optional reference not nullable              | `:card [0..*/0..1]`, edge not `:nullable`                    | A target end of `0..1` means the column may be empty                              |
| Composite key across tables                  | `(User.id, Tag.id)! :uk`                                     | A composite key groups columns of one table                                       |
| Two primary keys                             | `User.(id, email) :pk`                                       | The plain group gives each column the key; a composite key is `Table.(a, b)! :pk` |
| Path used as a key                           | `User.(email nick) :uk`                                      | Juxtaposition is a path; a composite key is a product                             |
| Exclusive member not nullable                | `(post, photo)? :required` without `:nullable`               | Only one member is set, so the others must be able to be empty                    |
| Default without exactly one match            | a `&edge` default with no matching column                    | Defaults never guess; state it explicitly                                         |

### Proofs

| Error                               | Example                                 | Why                                                     |
| ----------------------------------- | --------------------------------------- | ------------------------------------------------------- |
| Equation between non-parallel paths | `f == g` in `f g`                       | Both paths must have the same start and end             |
| Different operators without a group | `f == g ~= h`                           | Operators share one level; group the parts: `(f == g) ~= h` |
| Ambiguous universal property        | `+f :pullback` with two squares at `+f` | The cone must be determined; give the square explicitly |

## Examples

In this spec, each line of a code block is an independent diagram. A real program declares each diagram once.

**Mathematical diagrams**

```
Sq   :: +(f h, g k)+              // a square: f;h and g;k from A to D
Tri  :: +(f g, h)+                // a triangle: f;g and h from A to C
Iso  :: f/g                       // f : A → B, g : B → A
Endo :: f/f                       // f : A → A
Und  :: f/                        // f connects A and B, in no direction
Cyc  :: f/g/h                     // a directed triangle: f, g, then h back to A
Pair :: +(f, g)+                  // a parallel pair f, g : A ⇉ B
Nat  :: +(f, g)+ | f/α/g          // a natural transformation α : f ⇒ g
Eq   :: +(f, g)+ | f/α/g/β        // α : f ⇒ g and β : g ⇒ f
Pr   :: #X/(g1, f, g2), f+/(p1/g1+, p2/g2+)   // the universal property of a product
```

**Flow diagrams**

```
If    :: f/? +(fg g, fh h)? k            // decision, two branches, merge
While :: f/? +(b/b, e k)                 // body b loops on the test; e exits to k
Exit  :: f/? +(fg g/*, fh h k)           // g's branch stops; only h continues to k
Loop  :: f/? +(fg g, fh h k/+f)          // k : cod(h) → dom(f), back before the test
Par   :: */s/! +(a, b)! t/*              // start, fork, two parallel branches, join, stop
```

### A flowchart: order fulfilment

An order is validated, then payment and stock reservation run in parallel, each with its own retry loop, before the order ships. States are named nodes. Decisions and bars are anonymous, and are labelled through their canonical ends.

```
Order :: {
  */receive/#Received validate/? +(
      yes/#Accepted fork/! +(
          charge/? +(paid, declined/#Waiting/retry)
        , reserve/? +(reserved, short/#Backorder/restock)
      )! ready/#Ready ship/#Shipped close/*
    , no/#Rejected notify/*
  )
}

Order :style := {
  #Received  :label "Order received",
  validate+  :label "Valid?",
  charge+    :label "Payment accepted?",
  #Waiting   :label "Wait 10 min",
  reserve+   :label "In stock?",
  #Shipped   :label "Shipped",
  #Rejected  :label "Rejected",
  (yes, paid, reserved)  :label "yes",
  (no, declined, short)  :label "no",
  (retry, restock)       { :arrow [/dashed/>], :bend [inner] }
}
```

- `*/receive` opens the flow at a start; `close/*` and `notify/*` end it at two stops.
- `validate/? +(…)` puts a decision at the end of the edge validate, and starts both branches there. A named node is never a decision, so the state Received and the decision are joined by that edge, and the decision is labelled through its canonical end, `validate+`.
- `fork/! +(…)!` forks and joins on anonymous bars; `ready` leads from the join to the state Ready.
- `declined/#Waiting/retry` is a cycle: it exposes its start on the left, which the pinch makes the payment decision, so retry closes on it; it exposes nothing on the right, so only `paid` reaches the join. The same holds for `short/#Backorder/restock`.
- The fork is matched by a join, and both loops are choice loops, so the diagram is well-structured.

### A database schema: documents and comments

Users belong to organizations through memberships, projects belong to organizations, and documents live in projects, with comments that can reply to each other and tags attached through a join table.

```
T :: #UUID7, #DTZ, #String, #Text, #JSONB, #Bool

User         :: @/(id/T.#UUID7, email/T.#String, nick/T.#String, name/T.#String, created_at/T.#DTZ)
Organization :: @/(id/T.#UUID7, name/T.#String)
Membership   :: @/(id/T.#UUID7, admin/T.#Bool)
Project      :: @/(id/T.#UUID7, name/T.#String)
Document     :: @/(id/T.#UUID7, title/T.#String, body/T.#JSONB)
Comment      :: @/(id/T.#UUID7, text/T.#Text)
Tag          :: @/(id/T.#UUID7, label/T.#String)
Tagging      :: @/(id/T.#UUID7)

Db :: {
  Membership/(user/User, org/Organization),
  Project/owner/Organization,
  Document/(project/Project, author/User),
  Comment/(document/Document, writer/User, parent/Comment),
  Tagging/(doc/Document, tag/Tag)
}

Db :prove := {
  :kind [schema],

  &node.id :pk,
  &edge :card [0..*/1],

  User.(email, nick)! :uk,
  Tag.label :uk,
  (user, org)! :uk,
  (doc, tag)! :uk,

  parent { :nullable, :card [0..*/0..1] },
  parent document == document         // a reply is on the same document as its parent
}

Db :style := writer :label "author_id"
User :style := :label "users", :fill [muted]
```

- Every foreign key goes from the table holding it to the table it references, so foreign keys compose like functions, and `parent document == document` is a real path equation: both sides go from Comment to Document.
- Tables hold only their own columns. Each foreign key is one edge in Db, drawn as a row of its table: `document` is the row `document_id`, with its arrow to `Document.id`.
- Each table is a fan out of its `@`, and each table's foreign keys fan out of its diagram name; `/` distributes over the group, so every column and every foreign key lands on a written node.
- `Comment/(…, parent/Comment)` is a self-reference: the repeated name glues, so `parent` is a loop on one cluster.
- Foreign keys share Db's scope, so Comment's author is `writer`, labelled `author_id` for its column.
- Membership and Tagging are join tables; many-to-many relationships are two many-to-one foreign keys. No arrow styles are written: the crow's feet come from `:card`.

### A git history: commits as arrows

A commit is a change, so it is an edge from one state of the code to the next, and branches and tags are names for states. A branch is a fork, and a merge is the one place where history stops being a tree: both branches reach the merged state, and the square they form is a pushout, as in categorical theories of patches.

```
Repo :: {
  */init readme/#Fork +(fix/#Main, login session/#Feature),
  (#Main/merge, #Feature/merge')/#Merged bump/#V1 +(hotfix/#Head, spike/#Spike)
}

:ref := :shape [round], :fill [muted]

Repo :style := {
  &node :shape [point],
  #Head    { :ref, :label "main" },
  #Feature { :ref, :label "feature/auth" },
  #V1      { :ref, :label "v1.0" },
  #Spike   { :ref, :label "spike/cache" },
  init    :label "a1f3 init",
  readme  :label "b27c add readme",
  fix     :label "c90e fix typo",
  login   :label "d4a1 login form",
  session :label "e5b2 sessions",
  merge   :label "f6c3 merge feature/auth",
  merge'  :arrow [/dashed/>],
  bump    :label "0a7d bump to 1.0",
  hotfix  :label "1b8e hotfix",
  spike   :label "2c9f try cache"
}

Repo :prove := {
  fix merge == login session merge',   // both paths from the fork reach the same state
  #Merged :pushout                      // the merge is clean: the least common state
}
```

- `*/init` starts the history from nothing: before the first commit there is no state.
- `readme/#Fork +(fix/#Main, login session/#Feature)` is a branch: the pinch fans out of Fork, main gets fix, and feature/auth gets two commits.
- `(#Main/merge, #Feature/merge')/#Merged` is the merge. A merge commit has two parents, so it has two legs: `merge` from main and `merge'` from the feature, drawn dashed as the second parent link. The repeated names glue the legs onto the branch heads, and `/` distributes `#Merged` over both.
- `:ref` is a bundle: states that branches and tags name are drawn round and filled, the rest as points.
- The proof states that the merge square commutes and that `#Merged` is its pushout. A merge conflict is exactly the case where no such pushout exists, so a checker could refuse the second statement.

## Mathematical reading

A diagram denotes a graph presented by its edges, graded by dimension: the shape from which a free category, a commutative diagram or a higher category is built.

**Nodes as a quotient.** Let E be the declared edges. The ends are P = E × {dom, cod}, and the syntax generates an equivalence \~ on P. The nodes are the classes, V = P/\~, and source and target s, t : E → V send an edge to the class of its end. In Set this quotient is a coequalizer, so a diagram is a graph obtained by gluing free edges.

**The layers.**

- **Declarations** give the free structure: the graph E ⇉ V, the cells above it, and the category of paths they generate. With levels, a declaration is a **polygraph** (computad): generators at each dimension, each with source and target in the dimension below.
- **Style** is a function on the elements of that structure into the attribute monoid (layers composed with `over`, identity the empty style). The base theme makes it total.
- **Proofs** give a quotient: equations generate a congruence on paths, so a diagram with proofs denotes F(G)/\~. Universal properties are claims about cones in that quotient. Together, relations and proofs form an Ehresmann sketch: a graph, plus the diagrams that must commute and the cones that must be limits.
- **Definitions** form an environment of typed names, single assignment.

| fAB                        | Mathematics                                                                                |
| -------------------------- | ------------------------------------------------------------------------------------------ |
| Edges first, nodes derived | Arrows-only (single-sorted) definition of a category                                       |
| `+f`, `f+`                 | s(f), t(f): the identities on dom(f) and cod(f)                                            |
| `s t`                      | Composition of open graphs along one point: a pushout over a point                         |
| `s, t`                     | Coproduct in the category of graphs; in definitions, bindings or propositions side by side |
| `+(s, t)`, `(s, t)+`       | The Frobenius (co)multiplication on a point: n ends merged into one; the wedge sum         |
| `+(s, t)+`                 | Parallel composition                                                                       |
| `#A/f`, `+f/g/f+`          | Attaching an end to a written node: a pushout along that node                              |
| `/` over a group           | Gluing distributes over coproducts                                                         |
| `f/g`, `f/g/h`             | A cycle: the boundary of a face, which a 2-cell or an equation can fill                    |
| `f/f`                      | Endomorphism: the cycle equations with g = f                                               |
| `f/`                       | An undirected edge: an edge that is its own reverse                                        |
| Where nodes meet           | A partial commutative monoid of labels (name, kind); a meeting is defined when the join is |
| `?`                        | Choice: exactly one branch, coproduct-like                                                 |
| `!`                        | Parallel: all branches, product- or tensor-like                                            |
| `*`                        | A fresh node of degree one: the end it holds leaves the interface                          |
| `\|`                       | The grading of a polygraph by dimension                                                    |
| `f/α/g`                    | A 2-cell α : f ⇒ g between parallel arrows                                                 |
| `:style`                   | A total function from elements to attributes                                               |
| `:prove`                   | A congruence on paths, and limit cones                                                     |

## Open questions

**Structure**

- **Declaring nodes and edges.** Zones, nodes and edges are the only declarable structures. A proposed reading: a declaration says "this has a graph inside it". A declared node (`#User :: @/(id, name)`) is a graph inside a point: a composite state, or a table, which could replace `:as [node]` and `:as [table]`. A declared edge (`review :: check approve`) is a graph along an arrow: a subprocess, whose inner ends must match the edge's ends.
- **The header.** Which attributes (`:kind`, boundary) and what each changes. `:kind` is one attribute, the same in the header and in the proof, where it wins (Coming, Restrictions and passes).
- **Diagram composition.** How one diagram is used inside another, through its boundary.
- **What a flow could draw of its cells,** if anything, and how many levels stay readable.
- **How a category draws `?` and `!`.** They are declared the same way in every diagram; what a category shows of them is the renderer's to decide.
- **Well-structuredness.** Whether to warn on a `!` fork with no matching `!` join, especially inside a loop, where tokens multiply without bound.
- **Open name sets.** Whether a diagram may admit names on mention. Deferred: types are listed explicitly for now.
- **Patterns of edges.** A way to build several edges from one pattern, such as `f +(3/g)` for g1, g2 and g3. Not decided; every edge still has its own name, and nameless edges are not part of fAB.

**Style**

- **Equal-specificity overlaps.** When two classes of equal specificity (`&choice` and `&canonical`) set the same attribute: an error, or a fixed precedence.
- **The fallback for `[outer]`** on a lone edge that borders no region.
- **The prelude's contents:** colour names, keyword lists, named arrows, built-in themes.
- **Styling nested diagrams from outside,** which the current rule forbids.

**Place**

- **The whole vocabulary,** with the native layout engine: cardinal flow, relative ranks, grids, routing, loops, stacking.

**Proof**

- **What the checker checks,** whether statements imply others (two commuting squares imply the outer rectangle), and what is drawn for them (corner marks ⌟ ⌜, dashed unique arrows).
- **Explicit cones.** How a universal property names its square when it can't be inferred from the node.
- **Proof vocabulary per kind.** Whether the proof layer says `:mono` or `:pk`: the kind chooses, and which attributes each kind accepts is open.
- **Equations.** They are written `==` and `~=`; what `~=` means (isomorphic objects, or commuting up to an invertible 2-cell) and the rest of their design is open.
- **Proof equations** over partial edges: `parent document == document` holds only where `parent` is defined.
- **Undirected edges in equations,** which have no composition order.
- **Column names for emitters.** A foreign-key row's label is its column's name; whether an emitter reads it from `:label` or from a schema attribute of its own is open until fAB emits SQL.

**Coming.** Decided, and due in a later revision:

- **Recovery item by item inside braces.** Inside `{ }` the parser recovers at each `,`, so a statement with a syntax error there could still draw its good items, with the broken one as a hole (`G :: { f /g, h }` draws `f` and `h`). Until then the whole statement draws its placeholder. What a hole attached to nothing means is to be settled with it.
- **Restrictions and passes** (`statements.md` §17). Declarations describe every structure with a reading; a proof narrows it. `G :prove := { :kind [cd], … }` states what kind of graph it is (an entry with no subject binds the owner, G): what is drawn, which proofs may be posited, and which structures become findings, classed by reason: `&refutable` (contradicts the kind, an error) and `&undecidable` (has no check there, a warning), each with narrower classes per structure (`&undirected_cell`). `:pass` acknowledges a finding, by element or by class, with an optional reason: `α :pass "a relation, not a morphism"`. A pass reaches only findings, never a language error; it leaves a note and never changes the exit code, and a pass that matches nothing warns. The header may state `:kind` too, under the same name; the proof's wins. A diagram with no kind is a plain graph: it draws everything and raises no findings.

**Reserved.** Constructs whose meaning is open are errors until decided, each marked *reserved* in Errors. Deciding one lifts its error:

- Declaring a node or an edge on its own (Declaring nodes and edges, above).

**Settled since the first revision:** name scope (local to a diagram); precedence of `/` chains (left to right); the clash between colours and named nodes on `#` (colours are values in brackets); the format vocabulary and arrow grammar (now the style layer); styling proof-derived marks (`:marks`, as a definition after the proof).

**Settled on 1 November:** the grammar of joining. Juxtaposition is typed and never merges silently; pinches are the only collapse; `/` attaches one edge or closes a cycle, which exposes its start on the left only; a trailing `/` makes a one-edge chain undirected; every node term takes a slash; nodes meet only when their names and kinds agree. Statements are one line, and braces let them span lines; `,` separates items everywhere, as graphs, bindings or propositions side by side.
