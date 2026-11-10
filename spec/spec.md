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
- **Structure, then data about it.** Declarations (`::`) build the structure. Descriptions give it data: how it looks, what holds in it, where it goes. Data never changes structure.
- **Topology, not geometry.** fAB says what connects to what. Nothing in the language names a direction on the page; layout decides that.
- **One symbol, one meaning.** Every operator means the same thing wherever it appears, at every level of a diagram.

## Program structure

A program is a sequence of statements, one per line; braces let a statement span lines (see Items and lines). `:` is the one sign of assignment, and a statement has one of three forms, named by what it does:

| Form        | Operator | Does                                         | Example                                                    |
| ----------- | -------- | -------------------------------------------- | ---------------------------------------------------------- |
| Declaration | `::`     | introduces new **structure**, binding nothing | `Order :: */receive/#Received validate/? +(…)`             |
| Naming      | `:=`     | binds a **name** to a value                  | `[red] := [#ff0000]`, `:terminal := { :shape [circle] }`   |
| Description | none     | says something of a **context**              | `G :style { … }`, `G.f :arrow [epi]`, `Order :theme [dark]` |

**Declarations** build structure: they make something new, bound to nothing. Diagrams (zones) are declared with a term: `G :: term`. The vocabulary is declared too, in the prelude or in a program (see Values and definitions): labels of a type, `:Shape :: [circle], [box]`; types from other types, `:Angle :: :Number!`, `:Tip :: :Head, :Hook!, :Nil`; descriptors with their signature, `(&node, &zone) :fill :: :Color`; and record types by their descriptors, `:Style :: { … }`. Nodes and edges may become declarable on their own; what that means is open, so it is reserved: an error until decided.

**Namings** bind a name to a value, read left to right as name, then value. A type is no value: types are declared, with `::`.

| Left side      | Names                                     | Examples                                                         |
| -------------- | ----------------------------------------- | ---------------------------------------------------------------- |
| `[name]`       | a value, with an optional type before it  | `[red] := [#ff0000]`, `:Color [warn] := [red]`, `:Style [dark] := { … }` |
| `:descriptor`  | a new descriptor (a bundle), everywhere   | `:terminal := { :shape [circle], :fill [red] }`                  |

**Descriptions** apply a descriptor, an attribute, to a context. A description has one form, read left to right as context, then descriptor, then value, with no operator:

```
context :descriptor value
```

The value is left out for a flag or a bundle (`G.#Done :terminal`), and a table descriptor takes a key first (`Repo :lemma.[merge] ( … )`). A description written with `:=` is an error. **A reference is a description without its value:** `G.#Done :shape`, `Repo :lemma.[merge]`.

**Layers.** Three descriptors of a diagram take a record of descriptions as their value. Each is a five-letter verb, and each record has its own type, whose descriptors it accepts:

| Layer             | Type     | Says                                           | Relational?                                               |
| ----------------- | -------- | ---------------------------------------------- | --------------------------------------------------------- |
| `G :style { … }`  | `:Style` | how things look                                | no: a style describes one element and never names another |
| `G :prove { … }`  | `:Proof` | what holds: equations and universal properties | yes                                                       |
| `G :place { … }`  | `:Place` | where things go                                | yes                                                       |

Every descriptor belongs to one record type, so a descriptor may also be written outside its layer: `G :fill [white]` is `G :style { :fill [white] }`.

**Blocks are factored contexts.** A block is shorthand for descriptions with a common context:

```
G :style { #Done :terminal, f :label "x" }
// means
G.#Done :terminal
G.f :label "x"
```

- An entry with a context, `s :attr v`, inside the block of owner `X`, describes `X.s`.
- An entry with no context, `:attr v`, describes the owner itself. A context is left out only inside a block, where the owner is written on the line above; at the top level it is always written.
- **The owner's descriptors come first,** before any entry that names a context: `Order :style { :caption "Orders", &node :fill [muted] }`. Otherwise it is a style warning.
- Several contexts are a group, and the descriptors distribute over it, as `/` distributes over a group: `(yes, paid) :label "yes"`.
- **An entry has one descriptor.** Several descriptors of one context go in braces: `retry { :arrow [/dashed/>], :bend [inner] }`. Side by side (`retry :arrow [/dashed/>] :bend [inner]`) is an error: a comma there would end the entry, and `:bend` would describe the owner instead.
- **The three forms nest.** Inside braces, a naming binds a name in that record only, as a theme binds its tokens (`[ink] := [#dddddd]`), and a declaration declares inside the type being declared (`:Style :: { &node :fill :: :Color }`).

**Items and lines.** Every statement takes the same right side: items separated by commas, written on one line or in braces.

- **An item** is a bare term (`f g`, `+(f, g)+`), an entry (`#Done :terminal`, `+f { :label $P$ }`), a naming or declaration inside braces, or an equation (`f h == g k`). Which items each statement allows is checked after parsing: a declaration's items are terms, a record's are entries, namings and declarations.
- **`,` separates items everywhere, with one meaning:** side by side, and independent. In a declaration the items are graphs side by side (a coproduct), in a style descriptions side by side, in a proof propositions side by side (a conjunction).
- **The comma is required between items, and only between them.** `#Done :terminal f :label "x"` is an error, and so is a trailing comma: `(f, g,)`, `{ a :x, }`. Without the group, `yes, paid :label "yes"` is two items, and the bare `yes` describes nothing.
- **A statement is one line. Braces let it span lines:** inside `{ }`, at any depth, a newline is a space. Outside them a newline ends the statement, even inside parentheses.
- **There are no empty statements:** `G :: {}` is an error. `{}` as a value is an empty record.
- **A group isolates what it holds,** in a term, a context or a proposition alike: `+(f, g)`, `(yes, paid) :label`, `(f h == g k)`. Groups and braces without a context may nest freely to organise a block.

**Bindings.**

- **Each (element, descriptor) pair is bound once** within a layer, and each (element, descriptor, key) for a table. Binding `G.#Done :shape` twice is an error. **A layer is open:** every description of it joins one layer, so `G :style { … }` and `G.f :label "x"` add to the same style.
- **Different contexts may overlap**, such as `&node` and `#Done`. The more specific context wins (see Subjects and classes). Nothing is ever silently overridden.
- **Before use.** Names are defined before their first use, and a description at a context comes after the context's declaration.

**The header.** A file's general rules, applying to every diagram in it: the kind of its graphs (flow, category, schema, plain graph), whether its proofs are strict, how errors are treated. The same description may be written at three levels, and **the most specific wins: command line < header < local** (`Db :kind [schema]` overrides the header for Db). Descriptors of the compilation, `:warnings [error]` (warnings become errors) and `:broken [withhold]` (no drawing while errors remain), are header and command line only. The command line follows shell conventions, derived from the header's definition: `fab check db.fab -H kind=schema -H strict -H no-strict -H warnings=error`. The header's syntax, its boundary, and a flag to force a rule from the command line are open.

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
| `:terminal` | an attribute (a function)       |
| `:Color`    | a type                          |
| `&node`     | a class of elements             |

**Scope.** Edge names are local to their diagram, so two diagrams can each have their own `f`. Something inside another diagram is reached with `.`, which means "inside" and nothing else. The parentheses are optional but read better:

```
A :: f g
B :: h/A.+f        // h ends at dom(f) of A
B :: h/(A.+f)      // the same, easier to read
```

- The referenced diagram must be declared earlier, just as references inside a diagram point left. A diagram is not earlier than itself, so its relations never name it.
- In relations, `.` reaches a node: an end (`A.+f`, `A.f+`) or a named node (`A.#X`). The diagram itself is `A` (see Diagrams as nodes). Another diagram's edge is its own, so `A.f g` is an error; style and proofs name it freely (`User.email :uk`).
- Only ends A exposes can be referenced: never a null node's end, and only ends on A's boundary once the header defines one.
- A cross reference makes B share a node with A, and nothing more: B does not hold A, and A is drawn where it is held, or on its own. B styles only its own subjects, including edges that reach into A.

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

- **The sides are nodes:** named nodes (`#A`), diagram names, references to ends (`+f`, `f+`) and `*`. Named nodes and `*` need nothing before them, a diagram name its diagram declared earlier, and a reference its edge declared earlier.
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
G :: f/g/h/            // an undirected triangle
```

- The ends are still distinguished by position: `+f` is the end written first and `f+` the end written second. References and glueing work as before.
- The default arrow of an undirected edge has no heads, `[/solid/]`. Giving it a head is an error: it would draw a direction the relations don't have.
- **A trailing `/` makes every edge of its chain undirected.** A chain of one edge may be attached first: `#A/f/` is undirected f with one end at A, and `#A/f/#B/` is undirected f between A and B; continue with a space: `#A/f/ g/`. A chain of two or more is an undirected cycle: `f/g/`, `#A/f/#B/g/`. A cycle with some edges directed names its nodes: `#A/f/#B/, #B/g/#A`. After a group or a path there is no chain to end: `(f, g)/` and `(f g)/` are errors.
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
| an end attached by `/` to a named node or a diagram name      | that name, and the kind plain |

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

`*` is a node with no name. It behaves like `#A` with one difference: it is **private to one term**. Each `*` is a fresh null node, attached with `/`, and holds the ends on the side of the term it touches: a start if they leave it, a stop if they arrive.

```
G :: */f g h/*              // a path from a start to a stop
G :: (*/f, */g)+ h          // two starts, joined at +h
G :: */(f, g)               // one start, two edges leaving it
G :: f/? +(yes, no)/*       // a decision, both outcomes ending at one stop
```

- **A node, so a slash.** `* f`, `*f` and `f *` are errors.
- **One side.** `*/` distributes over a group as `#A/` does, and every free end it reaches lands on the one null node; closed branches are skipped, as when ends are counted. A null node holding ends on both sides would be neither a start nor a stop: `f/*/g` and `*/f/g` (in a cycle) are errors, and so is a lone `*`, which holds none. `*/+(f, g)` puts `/` between two nodes; write `*/(f, g)`.
- **Private.** Nothing glues to a null node and nothing refers to it: `k f/*, j/f+` is an error. Definitions still name it through an edge, as `+f` or `f+`.
- **It leaves the interface:** `f/*` exposes nothing on its right, so `f/* g` is "nothing to join", and so is `h */(f, g)` on its left.

`+(f, g)` and `*/(f, g)` are the same graph, two edges from one node. They differ in the interface: a pinch's node stays open, and `h +(f, g)` attaches to it; a null node is sealed, and drawn as a dot.

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
| `*/f`, `*/(f, g)`                  | nothing                                                           | cod(f); cod(f), cod(g)  |
| `f/*`, `(f, g)/*`                  | dom(f); dom(f), dom(g)                                            | nothing                 |
| `f/?`, `f/!`                       | dom(f)                                                            | cod(f), with its kind   |
| `f/`                               | dom(f)                                                            | cod(f)                  |
| a cycle: `f/g`, `f/f`, `#A/f/#B/g` | its start: dom(f); A                                              | nothing                 |
| `#A`, `User` alone                 | a lone node: it may stand as a whole branch, never beside a space |                         |

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

**Diagrams as nodes.** In relations, an uppercase name is a node term: the diagram it names, as one node of the diagram that writes it. That node stands for the whole, and never enters the named diagram's own graph. Like `#A`, it takes a slash, and repeated names glue.

```
Db   :: Document/owner/User           // owner : Document → User, between the two diagrams
Repo :: Master, FeatureOne, FeatureTwo // three diagrams held, and no edge
```

- **Naming a diagram includes it.** Alone, the name holds the diagram and adds nothing; attached by a slash, it holds it too, and the edge reaches the diagram as a whole.
- **A reference to a part includes nothing:** `B :: h/A.+f` shares a node with A, and B does not hold A.
- **Members.** A diagram is a member of each diagram that names it. Clusters form a tree, so a diagram is drawn inside the *first* diagram that names it, and styled from there (see Each diagram styles itself); its nodes still belong to it.
- **Drawn by its motif.** By default a member is a cluster, a zone with a graph of its own, and an edge to it reaches the cluster's border. `:as` draws it otherwise: as one node, or as a table.

A diagram whose objects are diagrams is the move cells make, one level up: there edges become nodes, here diagrams do. An edge between two members is a morphism between diagrams, whose kind (a foreign key, a call, a functor) the proof says.

### Schemas

A database schema is a category presented by a graph and path equations, as in categorical databases. fAB writes one directly; the schema statements are part of the proof layer.

| Schema      | fAB                                                                                       |
| ----------- | ----------------------------------------------------------------------------------------- |
| Table       | A diagram of one start, its row: `*/( … )`                                                |
| Column      | An edge from the row to a type                                                            |
| Type        | A named node in a shared types diagram                                                    |
| Foreign key | An edge from the table holding it to the table it references, in the diagram joining them |
| Primary key | `:pk` on a column: the key, mono (injective), one per table                               |
| Unique key  | `:uk` on a column: another key, mono                                                      |
| Referenced key | `:refs` on a foreign key and a key of its target: the key it references, if not the `:pk` |
| Constraint  | A path equation                                                                           |

- **A schema is a kind:** `Db :kind [schema]`. In a schema, an edge between two tables is a foreign key; nothing else marks it, so there is no `:fk`.
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
W :prove { :axiom (k == f h) }
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

Numbers go in brackets too: `:width [2]`. A record is written in braces, `{ … }`. The only exception is a **flag**, an attribute written with no value at all, such as `:hide`.

### The bracket token

- `[ … ]` is **one opaque token**. Its contents are any characters except whitespace, `[` and `]`.
- No whitespace inside: `[0..*/1..1]`, not `[0..* / 1..1]`. Text with spaces belongs in `"…"`.
- Because the main grammar never looks inside, symbols there cannot clash with their meaning outside: `[#ff0000]` is a colour, and `#A` outside is a node.
- Brackets appear in value position, as the name in a value definition, as the labels a type declares, and as a key in a record. Never in a term, and never as a subject.

**What a bracket holds.** `/` separates the elements of a bracket, everywhere. Each element is read by its shape:

| Element                        | Is                | Examples                                    |
| ------------------------------ | ----------------- | ------------------------------------------- |
| starts with a lowercase letter | a name or a label | `[red]`, `[circle]`, `[warn-bg]`, `[epi]`   |
| starts with `#`                | a colour          | `[#c0392b]`, `[#f00]`                       |
| starts with a digit            | a number          | `[2]`, `[0.5]`, `[30!]`                     |
| a digit, with `..`             | a range           | `[0..*]`, `[1..3]`                          |
| anything else                  | a symbol          | `[>]`, `[|>]`, `[X]`, `[O{]`                |
| nothing                        | an empty slot     | the tail in `[/solid/>]`                    |

A **symbol** is a run of glyphs with at most one capital letter, so `X` and `O{` are symbols, and no name is ever mistaken for one. Its glyphs are ASCII punctuation (less `/`, `!`, `#`, `[` and `]`, which a bracket uses itself, and `(`, `)` and `,`, which group: no bracket holds them) and the Unicode blocks of arrows, mathematical operators and geometric symbols: U+2190–23FF, U+25A0–27FF, U+2900–2BFF. Never a space, a control, a combining mark or a letter of any script; an allowlist, so nothing new in Unicode slips in. A **colour** is `#` and 3, 4, 6 or 8 hex digits, with alpha or without: without, it is opaque.

**A bracket has one element more than it has slashes, and an element with nothing in it is nil.** One element is the value itself: `[red]`, `[2.5]`, `[#f00]`; there are no one-element lists. Two or more are a tuple of their types: `[>/solid/>>]` is a tuple of a symbol, a label and a symbol, `[1/1.5/2]` a tuple of three numbers. A tuple whose elements share a type is also a list of that type, and a single value is a list of one: `:theme [dark]`, `:theme [dark/compact]`.

- **Nil is nothing written:** `[]` is one empty element, nil; `[/]` is two nils; `[/solid/>]` has a nil tail; `[////1/2]` is six elements, four of them nil. Nothing is marked by its spelling, never by a name. Text has its own nothing, `""`.
- **Nil fits only where a type admits it** (`(:Color, :Nil)`), and every list admits it, as its "no elements": `:theme []` chooses no themes.
- **Sequences do not nest:** a bracket is one token.

The value's type must be the one the attribute expects: `:ink` takes a colour, `:arrow` an arrow. `:shape [red]` is a type error ("a `:Color` where a `:Shape` is expected").

### `!` inverts what it follows

`!` has one meaning, as `/` does: it inverts what it follows.

| After             | Inverts                             | Example         |
| ----------------- | ----------------------------------- | --------------- |
| a line word       | its meaning: struck, "does not"     | `[/solid!/>]` ↛ |
| a hook or harpoon | its side: inner instead of outer    | `[/solid/^!]`   |
| an angle          | its side: inward instead of outward | `:bend [30!]`   |
| a flag            | it: off instead of on               | `f :hide!`      |

These are one idea: **`!` names a value's twin**, its other side, and the unmarked spelling is the first. Only a type with twins takes it, and the type says so: `T!` is `T` with its twins (`:Angle :: :Number!`, `:Hook!`, `:Line!`); `:Flag` has them by nature. `T` fits `T!`, never the reverse: `:size [2!]` is not invertible. So there are **no negative numbers**: every number starts with a digit. Outside brackets `!` follows only a flag; in a term it is a node kind, and attributes never appear in terms.

### Types

Every value has a type, and so does every name. The kinds of type are fixed by the language; their names are written in fAB.

| Type               | Values                                                       |
| ------------------ | ------------------------------------------------------------ |
| `:Text`, `:Math`   | `"…"`, `$…$`                                                 |
| `:Color`           | `[#c0392b]`, `[#f00]`, and the colours the prelude names     |
| `:Number`          | `[2]`, `[0.5]`, `[30!]`: an exact decimal                    |
| `:Range`           | `[0..*]`, `[1..3]`                                           |
| `:Flag`            | none: written (`:hide`) or not, inverted with `!` (`:hide!`) |
| `[:T/:U/…]`        | `[a/b/c]`, a tuple: one element of each type                 |
| `[:T]`             | `[a/b/c]`, a list: any number of elements, all of type T     |
| `:T, :U, …`        | a union: a value of any of its types; `(:T, :U)` inside an expression, and when printed |
| `:T!`              | the values of T and their twins: `[30]`, `[30!]`             |
| `:Nil`             | `[]`, and an empty slot: nil                                 |
| a record type      | `{ … }`, holding its descriptors: `:Style`, `:Proof`, `:Place` |
| a label type       | the labels it declares: `:Shape :: [circle], [box]`          |

- **Types are `:UpperCamel`,** descriptors (attributes) `:lowercase-kebab`, classes `&lowercase-kebab`, named values and labels `[lowercase-kebab]`.
- **A type is read from the value's shape** (the bracket rules above, `"…"`, `$…$`, while `{ … }` has no type: it is checked by its structure where a record type is expected) or from a name's definition. A type written in a definition is a contract, checked: `:Color [warn] := [circle]` is an error. It is optional, and the LSP completes from it.
- **Types are declared and spelled like their values:** `:Length :: :Number`, `:Tip :: :Head, :Hook!, :Nil`, `:Arrow :: [:Tip/:Stroke/:Tip]`, `:Themes :: [:Style]`. A comma is a choice, a bracket a tuple, a bracket of one type a list. A bracket holds type names only, never types and values together; what it needs is named first. **Declared types are distinct:** `:Length` and `:Angle` hold numbers, but a length is no angle. A literal fits by its shape; a value typed by a declaration fits that type, and the types that include it. **Repeating a declaration adds to the type:** labels, descriptors or types. There are no type constructors: a type is names, `!`, commas, groups and brackets (`statements.md` §22.8).
- **Labels** are values with no definition, declared by their type: `:Shape :: [circle], [box]`. A renderer gives each its meaning (`[circle]`), or a record binds it (`[ink]`, see Themes). **A label belongs to one type:** declaring it in another is an error. Words two types share get a type of their own, which both include: `:Facing :: [outer], [inner]`, `:Side :: :Facing, :On`.
- **Numbers are exact decimals:** fAB never computes with them, so `0.1` stays `0.1` from the source to the renderer. Digits on both sides of a point (`[.5]` and `[1.]` are errors), no exponent, at most 18 digits from the first nonzero one. Numbers are normalised, and printed so: `[1.50]` is `1.5`, `[007]` is `7`.

### Units

Lengths are numbers in **em**, relative to the theme's text size. Angles are in **degrees**. A fraction is a number from 0 to 1, a position along an edge. `:Length :: :Number`, `:Angle :: :Number!` and `:Fraction :: :Number` are distinct types, so units are checked: a length is no angle. An angle has a twin, the inner side: `:bend [30!]`.

### Definitions

- **Values:** `[red] := [#ff0000]`, or with its type, `:Color [red] := [#ff0000]`. A value may name another: `[warn] := [red]` has red's type.
- **Record types** are declared by their descriptors, as a label type is by its labels: `:Style :: { (&node, &zone) :fill :: (:Color, :Nil), … }`. **A descriptor belongs to one record type,** and a record is checked by its structure where a record type is expected: `[x] := { :fill [red] }` has no type, and fits wherever a `:Style` is expected, `:theme [x]`; a descriptor of another type in it does not apply. `{}` fits any record type. A descriptor declared outside any record type (`&zone :style :: :Style`) describes at the top level only. A type holds values or descriptors, never both.
- **Records:** `{ … }`, holding descriptions, namings and, in a type's declaration, signatures. `&node :stroke [ink]` is short for `&node { :stroke [ink] }`. A naming inside a record binds a name in that record only: `[ink] := [#dddddd]` binds a label to a value of its own type.
- **Bundles:** `:terminal := { :shape [circle], :fill [red] }`. A bundle is a new attribute, a flag whose record is applied where it is written, exactly as if its contents were written there; later settings refine it: `#Done { :terminal, :fill [green] }`. A bundle holds descriptors only, and has no record type of its own: it applies where all its contents apply, to the classes there (`:terminal` applies to nodes) and in the record type expected there. `:key := { :pk, :fill [gold] }` is fine, but used in a style, `:pk` does not apply, and in a proposition, `:fill`.
- **Themes:** `:Style [dark] := { [ink] := [#dddddd], &zone :fill [#1e1e1e] }`. A theme is a named style, of contexts and tokens, chosen with `:theme`. Its contexts are classes, since it applies to any diagram; a descriptor with no context describes the diagram it is applied to.
- **Tables:** a descriptor declared with a key slot, `&zone :lemma.[] :: :Proposition`, takes a key, then a value: `Repo :prove { :lemma.[merge] (fix merge == login session merge') }`. A binding is (context, descriptor, key), once; keys are optional (an entry without one has a fresh key nothing can refer to), written with `.`, and local to their descriptor.
- **Signatures:** `(&node, &zone) :fill :: :Color` declares a descriptor: the classes it applies to, and the type it takes. Anywhere else it does not apply. A class includes the classes inside it: what applies to `&node` applies to `&choice`.
- **Names** are defined once, and before their first use.

### The prelude

The prelude ([`prelude.fab`](../fab-core/src/prelude.fab)) is ordinary fAB source, compiled into `fab` and read before every program. It declares the types, labels and attributes, names the colours and the common arrows, and defines the base theme `[base]` and the built-in themes. So the vocabulary is documented by being written in the language itself.

It has no powers a program lacks. Its names come first, so defining one again is "defined twice"; a program may declare labels, attributes and types as the prelude does. What no renderer knows how to draw (`:Shape :: [blob]`), a renderer reports, and draws with a fallback.

## Subjects and classes

The contexts of descriptions are the things a style, a proof or a placement talks about.

| Subject                      | Written                            | Example                                              |
| ---------------------------- | ---------------------------------- | ---------------------------------------------------- |
| a diagram                    | its name                           | `G :style { … }`                                     |
| an edge or a cell            | its name, qualified by its diagram | `G.f :stroke [red]`                                  |
| a node, by its canonical end | `+f`, `f+`                         | `G.+f :label $P$`                                    |
| a named node                 | `#Name`                            | `G.#Done :shape [box]`                               |
| a class                      | `&name`                            | `&node :shape [circle]`, `G.&edge :pen [thin]`      |
| several subjects             | a group                            | `(yes, paid) :label "yes"`                           |

**Canonical references.** A node is addressed only through its canonical reference: its name if it has one (`#A`), and otherwise the first end that created it, in reading order. In `f g`, the middle node is `f+`, never `+g`. In `+(f h, g k)+`, the canonical references are `+f` (the pinched start), `f+`, `g+` and `f h`'s end `h+` (the pinched end); `+g`, `+h`, `+k` and `k+` are rejected.

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

Classes of one rank apply in the order they are defined, the later winning, and errors come last, so nothing paints over them: `&node`, then the kinds (`&plain`, `&choice`, `&parallel`, `&start`, `&end`), then `&canonical`, then `&hole`. Marks on issues are applied after everything.

Specificity orders bindings within a layer of style; layers compose on top (see Style layer, Themes).

**Each diagram styles itself, and its members' classes.** C's bindings of elements name only C's own subjects, including C's edges that reach into A. C's classes, tokens and themes reach its members too, beneath their own layers: a member is styled by `[base]`, then the diagrams holding it, outermost first, then itself. So `Repo :style { &node :shape [point] }` draws every branch's commits as points, and a branch can still bind its own. A diagram held by several is styled from the first, where it is drawn. A class bound at the top level (`&node :line [dashed]`) is every diagram's own, so it ranks above the diagrams holding it. A container's element bindings never reach its members.

## Style layer

`G :style { … }` gives everything drawn in G its appearance. It never changes the graph, never refers to one element from another, and never names a direction on the page: everything is relative to the element, its text, or the diagram's own shape. A diagram can flow towards any cardinal point and every style still means the same.

```
G :: f g

G :style {
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
| `:label`  | N E C Z    | text, math, `[]`                                 | `[]`, computed: a node's name without `#`, a diagram's node its diagram's name, else its canonical end; an edge's, a cell's or a diagram's name. `""` for choices, parallels, starts and ends |
| `:font`   | N E C Z    | text (a font name)                               | theme                                                                                                                                                    |
| `:face`   | N E C Z    | `[regular]` `[italic]` `[bold]` `[bold-italic]`  | `[regular]`; `[italic]` for `&canonical`                                                                                                                 |
| `:size`   | N E C Z    | length: the size of the lettering, and only that | theme; edge and cell labels smaller                                                                                                                      |
| `:ink`    | N E C Z    | colour                                           | `[ink]`; `[soft]` for edge and cell labels; `[muted]` for `&canonical`                                                                                   |

**A label resolves in three ways.**

```
f :label []        // its computed name: f
f :label "Lorem"   // the text Lorem; math the same, $\sigma$
f :label ""        // no text
```

- **`[]`, nil, is the computed name.** The name is computed below `[base]` (see Themes), wherever the cascade leaves `:label` nil: a named node is its name without `#` (`#Valid` is Valid), any other node is its canonical end (`f+`, `+f`), and an edge, a cell or a diagram is its name.
- **`""` is no text,** written on purpose. `[base]` gives choices, parallels, starts and ends `:label ""`, since each is a shape that says what it is; `&choice :label []` gives their computed names back.
- **Text or math is drawn as written.**
- **A label is drawn whenever it holds text,** whatever else is drawn: a diagram shows its name framed or not (`:label ""` hides it), and a node, its label, whatever its shape.
- **`&canonical`** is a node whose label is its canonical end: unnamed, and with its label nil once every layer but `&canonical`'s own is applied. So `validate+ :label "Valid?"` is not canonical, and drawn upright.

### Nodes

| Attribute           | Values                                                                                                                                                                                          | Default                           |
| ------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | --------------------------------- |
| `:shape`            | `[]` `[box]` `[round]` `[circle]` `[double-circle]` `[ellipse]` `[stadium]` `[diamond]` `[hexagon]` `[parallelogram]` `[cylinder]` `[document]` `[bar]` `[point]` `[terminal]` `[bullseye]` | by kind                           |
| `:fill`             | colour                                                                                                                                                                                          | none                              |
| `:stroke`           | colour                                                                                                                                                                                          | `[ink]`                           |
| `:pen`              | `[thin]` `[normal]` `[thick]`                                                                                                                                                                   | `[normal]`                        |
| `:line`             | `[solid]` `[dashed]` `[dotted]` `[double]` `[wavy]` `[]`                                                                                                                                    | `[solid]`; `[dashed]` for `&hole` |
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
| `:label-at`                  | `[start]` `[center]` `[end]`, or a fraction                      | `[center]`                                                                   |
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
| `:theme`                    | theme names, applied left to right: `[dark/compact]` | none: the base theme alone                          |
| `:marks`                    | `[all]` `[]`                                     | `[all]`: draw marks from the proof layer, such as ⌟ |
| `:cross`                    | `[gap]` `[plain]`                                    | `[gap]`                                             |

A diagram is drawn framed only if it has a `:stroke` or a `:fill`: borders are always explicit. Its name is drawn either way, as its `:label`; `:label ""` hides it. `table` draws the edges leaving the diagram's start, its row, as rows inside the frame, each showing the edge's label and its target.

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

An arrow is a tuple of three fields, `[tail/line/head]`: `:Arrow :: [:Tip/:Stroke/:Tip]`, with `:Tip :: :Head, :Hook!, :Nil` and `:Stroke :: :Line!, :Nil`. The ends are symbols, the line is a word. Any field may be empty, nil, meaning nothing there, but not all three: `[//]` is an error, since an edge that draws nothing is hidden with `:hide`, never emptied. `[/solid/>]` has no tail, `[>//>]` no line. The arrow only draws: the edge's direction always comes from the relations.

**Lines** use the words of `:line`, plus `triple`: `solid`, `dashed`, `dotted`, `wavy`, `double` (2-cells, ⇒), `triple` (3-cells, ⇛); no line is an empty field. A `!` suffix strikes the line: `[/solid!/>]` is ↛, "does not".

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
| `&choice`    | `[diamond]`, `:label ""`                                                                               |
| `&parallel`  | `[bar]`, `:label ""`; as wide as its busier side needs                                                 |
| `&start`     | `[point]` (a filled dot), `:label ""`                                                                  |
| `&end`       | `[bullseye]`, `:label ""`                                                                              |
| `&hole`      | `[circle]`, `:line [dashed]`, labelled by its canonical end if it has one                              |
| `&canonical` | `:face [italic]`, `:ink [muted]`                                                                       |
| `&edge`      | `:arrow [/solid/>]`, `:ink [soft]`, smaller `:size`                                                    |
| `&cell`      | `:arrow [/double/>]` or `[/triple/>]`, `:ink [soft]`, smaller `:size`                                  |
| `&zone`      | `:as [cluster]`, unframed, `:cross [gap]`                                                              |

### Themes

A theme is a named style, of contexts and tokens (see Values and definitions): `:Style [dark] := { [ink] := [#dddddd], &zone :fill [#1e1e1e] }`. Styles compose in layers, the later winning wherever both set a value:

```
computed  <  [base]  <  themes, left to right  <  the program's own bindings
```

- **`[base]` always applies, first.** It is the prelude's base theme: the kind defaults above, and every other default written as a value. Defaults that depend on the element are **computed** below it: a node's label from its name or canonical end, a cell's arrow from its level, one circle diameter per diagram. `[base]` binds nothing computed. Together they bind every attribute for every kind, so every element always has every attribute: the style is a total function, and themes and programs only override parts of it. What can be nothing admits nil, so a later layer can take a value away: `G :fill []`. For a computed attribute, nil is the computation: `:label []` gives back the name, and `""` is a label's nothing.
- **"Each binding once" holds within a layer;** across layers, the later one wins, deliberately and in order. A flag set by one layer is turned off by a later one with `!`: `f :hide!`.
- **`:theme`** chooses themes for a diagram, and cascades to nested diagrams: `Order :theme [dark/compact]`. A theme may include others, applied before its own bindings: `:Style [night] := { :theme [dark], [accent] := [#58a6ff] }`.
- **Theme tokens** are colour labels whose value a record binds: `[ink]` (lines and text), `[soft]` (edge labels), `[muted]` (canonical labels), `[accent]`, and the severities `[error]`, `[warning]`, `[unsupported]`. `[base]` binds them all; a theme rebinds some, `[ink] := [#dddddd]`, and so does a diagram's own style, after its themes: `G :style { [ink] := [#000000] }`. Any label may be rebound so, one step: `[circle] := [box]` draws circles as boxes.

## Place layer

`G :place { … }` says where things go. Unlike style, it is relational by nature: placement relates one element to another. Its vocabulary is open, and will be designed with fAB's own layout engine. What is settled:

- **Direction-agnostic.** The overall flow is given by a cardinal point. Placement within it uses relative ranks, along the flow and across it, without the words vertical and horizontal.
- **Drawing order is source order.** Without anything in `:place`, branches are drawn in the order they are written, and what is written later is drawn on top. So in `#X/(g1, f, g2)`, f is drawn between g1 and g2.
- **What belongs here:** relative placement (what the first revision called `:right-of`), ranks and grid cells, the overall direction, layout and routing styles, spacing, which side of a node a loop sits on, and stacking between elements.
- **A strict grid** (every node on an integer coordinate) is a layout of this layer, for the native engine.

## Proof layer

`G :prove { … }` states what holds in the diagram. A diagram presents a theory: the cells it declares, the laws of its kind, and its **axioms**. The proof gives that theory its axioms, which fAB takes as stated, and its **lemmas**, which fAB checks against it. Axioms are the standard way to give a structure its features (this square commutes, this column is a key); lemmas are questions about the structure built (is this a pushout?), and most programs need none.

```
Sq :: +(f h, g k)+

Sq :kind [category]

Sq :prove {
    :axiom (f h == g k),                // path == path: we say the square commutes
    :lemma.[corner] (+f :pullback)      // fAB confirms it: context :property
}
```

- **A proof is a record of type `:Proof`:** `:strict` first, then `:axiom`, `:lemma` and `:pass`. The kind is not the proof's but the diagram's, stated before its layers (`Sq :kind [category]`), and it decides which propositions the proof admits (`statements.md` §24). Axioms and lemmas are tables of propositions, `:axiom.[] :: :Proposition`, the proof's own: declared with no class, bound by an entry with no subject. A key is optional; name only what is referred to: `Sq :lemma.[corner]`.
- **A proposition is the fifth shape of a value,** `( … )`, a record type whose descriptors are properties: `:pullback`, `:pushout`, `:card`, `:pk` and the rest are declared in `:Proposition :: { … }`, with ordinary types. Equations stand among them, and a comma means *and*: `:axiom (&node.id :pk, &edge :card [0..*/1])`.
- **How each is checked:**

| | Ill-formed | Not admitted by the kind | Inconsistent, or refuted | Cannot tell |
| --- | --- | --- | --- | --- |
| `:axiom` | error | error | error, when decidable | trusted, silent |
| `:lemma` | error | error | error | warning; a pass acknowledges it |

- **An axiom fits the structure, or it is an error:** its truth is never checked, and no pass reaches it, since from an inconsistent theory everything follows. An axiom states what it presupposes: `#M :pushout` as an axiom states its commuting square too.
- **A strict proof uses no axiom it does not need.** With `:strict` (in the proof, in the header, or `-H strict`), each axiom that follows from the others warns that it could be a lemma. It is opt-in, since checking costs a proof per axiom.

- **Axioms have no order; a lemma may use every axiom and the lemmas before it.**
- **Chains of equations** state each step: `(f h == g k == d)` is `f h == g k` and `g k == d`.
- **One level, no precedence.** The operators between chains, `==` and `~=` today and any the layer adds later, share one level and read left to right. A run may repeat one operator; different operators need a group: `(f == g) ~= h`, never `f == g ~= h`.

- **Equations** relate two paths, written with juxtaposition in diagrammatic order. Both sides must be existing paths with the same start and end. Equations are not settled: they are written `==`, and `~=` is reserved for a weaker relation whose meaning is open (see Open questions).
- **Identities are equations.** `+f` denotes the identity on dom(f), so `f == +f` says that the endomorphism `f/f` is an identity. No keyword is needed.
- **Universal properties** attach to a node. `(+f :pullback)` takes the commuting square that starts at `+f` as its cone. If no such square, or more than one, starts there, the statement is rejected and the square must be given explicitly.
- **Pushouts mirror pullbacks.** `(#M :pushout)` takes the commuting square that ends at `#M` as its cocone, with the same rule.
- **Checking is partial.** Whether an arbitrary equation follows cannot be decided in general (commutation is a word problem), so an undecidable lemma is a warning, never silence; what a confirmed lemma constructs, and how it is drawn, is open.
- **Composites.** Naming a composite at level 1 and stating it as an axiom (`:axiom (k == f h)`) is how cells get composite sources (see Levels).

### Schema statements

In schemas, the proof layer states keys and constraints, as axioms: they are properties, written inside a proposition, `:axiom (&node.id :pk)`. Properties without a value are flags.

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
| Empty braces                       | `G :: {}`                                    | There are no empty declarations; `{}` is only a value            |
| Bare term in a record              | `yes, paid :label "yes"`                     | Several subjects are a group: `(yes, paid) :label`               |
| Entry or equation in a diagram's declaration | `G :: f (g :label "x")`            | A diagram's declaration holds terms                              |
| Class in a diagram's declaration   | `G :: &node f`                               | Classes are contexts of descriptions and signatures only         |
| Levels in a naming or a record     | `:x := a \| b`, `G :style { a \| b }`        | `\|` separates the levels of a declaration                       |
| Declaration head not a diagram     | `[red] :: f`, `G :style :: f`                | Only diagrams, nodes and edges are declared                      |
| Reserved: node or edge declared    | `#User :: */(id, name)`, `review :: a b`     | What declaring a node or an edge means is open                   |
| Naming head of no form             | `f g := [red]`, `G := [red]`                 | A naming's left side is `[name]`, `:Type [name]` or `:descriptor` |
| Description written with `:=`      | `G :style := { … }`, `G.f :arrow := [epi]`   | A description has no operator: `G :style { … }`                  |
| Description with no context        | `:fill [red]` at the top level               | A context is left out only inside a block, where it is the owner |
| Declaration in a record            | `:Style [x] := { [ink] :: :Color }`          | Inside braces, `::` declares only in a record type: `:Style :: { … }` |
| Naming in a type                   | `:Style :: { [ink] := [#fff] }`              | A declaration holds signatures; `:=` names only in a record       |
| Warning: owner described after a part | `G :style { &node :fill [red], :caption "x" }` | The owner's descriptors come first in a block                 |
| Warning: chain broken across lines | `f g` then `h k` on the next line, in braces | Write `,` for two items, or group the chains                     |

### Relations

| Error                             | Example                                         | Why                                                                        |
| --------------------------------- | ----------------------------------------------- | -------------------------------------------------------------------------- |
| Diagram declared twice            | `G :: f` … `G :: g`                             | One declaration per diagram                                                |
| Edge or cell declared twice       | `f g f`, `f/α/g, f/α/g` at level 2              | A bare name declares; only `f/f` repeats it                                |
| Self-reference outside `f/f`      | `(f g)/f`                                       | A loop needs a single edge on the left                                     |
| Redundant self-attachment         | `f/+f`                                          | Same graph as `f/f`                                                        |
| Vacuous self-attachment           | `f/f+`                                          | Glues an end to itself                                                     |
| `/` between nodes only            | `+g/+f`, `#A/#B`, `#A/?`, `f/#A/#B/g`, `#A/#B/`, `*/+(f, g)` | `/` needs an edge between its sides                                        |
| Slash between two groups          | `(f, g)/(h, k)`                                 | Gluing many ends to many is a collapse nobody wrote; pinch one side: `(f, g)+/(h, k)` |
| Trailing `/` not on a chain       | `(f, g)/`, `(f g)/`, `#B/`                      | A trailing `/` makes a chain's edges undirected: `f/ g/`, `f/g/`          |
| Cycle that does not close         | `#A/f/#B/g/#C`, `+f/m/n/g+`                     | A chain of two or more edges ends where it began                           |
| Reference not declared            | `+k/g`, `gg/α/g` with k, gg undeclared          | A reference needs its edge declared before it                              |
| Forward reference                 | `+f/g f`                                        | References point left only                                                 |
| Node beside a space               | `#A f`, `* f`, `#A (…)`, `f User`               | A node is attached to an edge with `/`                                     |
| Ends don't match                  | `f (g, h)`, `(f, g) h`, `(a, b) (c, d)`         | A space joins one end to one end; pinch the group: `f +(g, h)`             |
| Nothing to join                   | `f/g h`, `f/* g`, `(f/*)/g`, `#A/(*/f)`         | One side exposes nothing; write `,` for separate pieces                    |
| Warning: a space reaches one branch of several | `(f/*, g) h`, `(f, #A) g`, `+(g/*, h) k` | The other branches expose nothing there; move the step into the branch: `f/*, g h` |
| Pinch of declared edges           | `f g, h k, +(f, h)`                             | A pinch with several branches declares them                                |
| Pinched edge beside a space       | `f? (g, h)`, `k +f`, `f+ g`                     | A pinched single edge is a node; to pinch the group, move the marker: `f/? +(g, h)` |
| Single edge pinched on both sides | `+f+`, `+(f)+`                                  | A pinched edge is one node; it has one side                                |
| Pinch of a node                   | `+#A`, `#A?`, `(User)+`                         | A pinch merges the ends of a group; a node has none: attach it with `/`    |
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
| Reference to a null node          | `k f/*, j/f+`                                   | A null node is private to its term                                         |
| `*` not on one side               | `*`, `f/*/g`, `*/f/g`                           | A null node is a start or a stop: it holds the ends of one side of one term |
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

| Error                               | Example                                  | Why                                                                                  |
| ----------------------------------- | ---------------------------------------- | ------------------------------------------------------------------------------------ |
| Undefined name                      | `:ink [wran]`                            | Every name is defined before its use                                                 |
| Name defined twice                  | `[red] := …` twice, `[epi] := …`         | Each name is defined once; the prelude's come first                                  |
| Label in two types                  | `:Bow :: [outer]` after `:Facing`        | A label belongs to one type; shared words get a type of their own                    |
| Not a type                          | `:Colour [x] := …`                       | Types are declared before their use                                                  |
| Type named with `:=`                | `:Length := :Number`                     | A type is no value: it is declared, `:Length :: :Number`                             |
| Types and values mixed              | `[:Tip/solid/>]`                         | A bracket holds values, or type names                                                |
| Type as a value                     | `:theme [:Style]`                        | A bracket of type names is a type; values are written without `:`                    |
| Type including itself               | `:A :: :B` then `:B :: :A`, `:A :: [:A]` | A type holds other types' values, never its own                                      |
| Expression in a bracket             | `[:Tip/(:Line,:Nil)/:Tip]`, `[a,b]`      | Name the type first: `:Stroke :: :Line!, :Nil`; brackets never hold `(`, `)` or `,`  |
| Contract broken                     | `:Color [warn] := [circle]`              | A type written in a naming is checked                                                |
| Type with parameters                | `:Color.(:Text)`, `:List.(:Style)`       | Types take none: a tuple is `[:A/:B]`, a list `[:A]`, a table a key slot `:d.[] :: :A` |
| Key in a declaration                | `&zone :axiom.[a] :: :Proposition`       | A declaration names no key: its slot is empty, `:axiom.[]`                           |
| Not a label                         | `:Shape :: [#f00]`, `[a/b]`, `[x!]`      | A label is one name or one symbol, alone in its bracket                              |
| Labels on structure                 | `:Flag :: [x]`, `:Style :: [x]`          | Labels go on declared types and single values; flags and record types take none      |
| Descriptors on a value type         | `:Shape :: { &node :x :: :Color }`       | A type holds values or descriptors, never both                                       |
| Uppercase name                      | `[Warn]`                                 | Names start with a lowercase letter; a symbol has at most one capital, and no letter after it |
| Bare value                          | `:width 2`                               | Values are written `"…"`, `$…$`, `[…]` or `{ … }`                                     |
| Space inside brackets               | `[0..* / 1]`                             | A bracket is one token                                                               |
| Negative number                     | `[-30]`                                  | Numbers are never negative; for the inner side write `[30!]`                         |
| Number malformed                    | `[.5]`, `[1.]`, 19 digits                | A number is digits, with digits on both sides of a point                             |
| Name malformed                      | `[warn_bg]`, `[warn-]`                   | Names are lowercase-kebab: letters and digits, words joined by single hyphens        |
| Colour malformed                    | `[#ggg]`, `[#12345]`                     | A colour is `#` and 3, 4, 6 or 8 hex digits                                           |
| Empty range                         | `[5..2]`, `[1..]`, `[*..3]`              | A range runs from a number up to a larger or equal one, or `*`                       |
| Symbol malformed                    | `[>a]`, `[OX]`, `[>2]`, a space          | Glyphs from the allowed blocks, with at most one capital letter                     |
| `!` misplaced                       | `[!]`, `[solid!!]`, `[so!lid]`           | `!` comes last in an element, once, after something                                  |
| Value in a diagram's declaration    | `G :: +(g1, [f], g2)`                    | Brackets are values, never structure                                                 |
| Type in a diagram's declaration     | `G :: f :Color`                          | Types are declared on their own and used in namings and signatures                   |
| Wrong type                          | `:shape [red]`, `:theme [terminal]`      | A `:Color` where a `:Shape` is expected                                              |
| Does not apply                      | `f :shape [box]`, `G :style { :pk }`     | An attribute applies to the classes its signature names, in its own record type     |
| Value given to a flag, value missing | `:hide [on]`, `:shape`                  | Flags take no value; other attributes need one                                       |
| Key of the wrong type               | `[ink] [circle]` in a record             | A label binds a value of its own type                                                |
| Subject in a bundle                 | `:t := { &node :fill [red] }`            | A bundle is applied where it is written; it holds descriptors only                   |
| Element in a theme                  | `:Style [x] := { G.f :pen [thin] }`      | A theme applies to any diagram; its contexts are classes                             |
| Binding made twice in a layer       | `#Done :shape` twice                     | Each (context, descriptor) pair is bound once, and each key of a table               |
| Key not taken                       | `:fill.[a] [red]`                        | Only a table's descriptor takes a key; an entry without one has a fresh key          |
| Key malformed                       | `:legend.[] "x"`, `:legend.[a/b] "x"`   | A key is one name; an entry with no key leaves the slot off                          |
| Description at an undeclared context | `G :style { … }` before `G ::`         | A description comes after what it talks about                                        |
| Not a subject                       | `f g :label "x"`, `+(f, g)+ :label "x"` | A context names elements: names, ends, `#X`, classes, groups of them            |
| Element has no parts                | `G :style { #Done { f :label "x" } }`   | Inside an element's or a class's block, only the owner is described                  |
| Unknown class                       | `&nodes`                                 | Classes are built in, or defined                                                     |
| Attributes side by side             | `f :label "x" :bend [inner]`             | An entry has one attribute; several go in braces: `f { :label "x", :bend [inner] }`  |

### Style

| Error                                  | Example                                                    | Why                                                          |
| -------------------------------------- | ---------------------------------------------------------- | ------------------------------------------------------------ |
| Unknown attribute                      | `:colour`                                                  | Did you mean `:ink`, `:stroke` or `:fill`?                   |
| Attribute that does not apply          | `:fill` on an edge, `:arrow` on a node, `:line` on an edge | An edge's line is part of `:arrow`                           |
| Value not among the attribute's values | `:side [sideways]`                                         | Expected `[outer]`, `[inner]` or `[on]`                      |
| Direction word                         | `:side [left]`                                             | Styles never name a direction on the page                    |
| Relational value                       | a style value that names `g`                               | Placement belongs in `:place`                                |
| Non-canonical reference                | `+g :label …` in `f g`                                     | Label the node through `f+`, the end that created it         |
| Another diagram's subject              | `A.+f` styled from C                                       | Each diagram binds its own elements; its classes reach its members |
| Empty arrow                            | `[//]`                                                     | An arrow draws something; to draw no edge, `:hide` it        |
| Unknown line word or end               | `[/zigzag/>]`, `[/solid/%]`                                | Lines are words from a fixed list; ends from the glyph table |
| Not invertible                         | `[/solid/>!]`, `:size [2!]`, `:fill!`, `:terminal!`        | `!` names a twin, and only a type with twins (`T!`) has one  |
| Head on an undirected edge             | `f/` with `:arrow [/solid/>]`                              | The drawing would show a direction the relations don't have  |

### Named nodes and schemas

| Error                                        | Example                                                      | Why                                                                               |
| -------------------------------------------- | ------------------------------------------------------------ | --------------------------------------------------------------------------------- |
| Node named twice                             | `a/#A #B/b`                                                  | One node, one name                                                                |
| Named node referenced by an end              | `+f :label …` where dom(f) is `#A`                           | A named node is referenced by its name                                            |
| Undeclared name in another diagram           | `T.#UUDI7`, `A.+k`                                           | Names never come into existence by being mentioned                                |
| Diagram not declared before                  | `B :: h/A.+f` before `A ::`, `G :: G/f`                      | References point left; a diagram never names itself                               |
| Another diagram's edge in relations          | `A.f g`, `A.(f, g)`                                          | `.` reaches a node: `A.f+`, `A.#X`; the diagram itself is `A`                     |
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

Order :style {
    #Received             :label "Order received",
    validate+             :label "Valid?",
    charge+               :label "Payment accepted?",
    #Waiting              :label "Wait 10 min",
    reserve+              :label "In stock?",
    #Shipped              :label "Shipped",
    #Rejected             :label "Rejected",
    (yes, paid, reserved) :label "yes",
    (no, declined, short) :label "no",
    (retry, restock)      { :arrow [/dashed/>], :bend [inner] }
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

User         :: */(id/T.#UUID7, email/T.#String, nick/T.#String, name/T.#String, created_at/T.#DTZ)
Organization :: */(id/T.#UUID7, name/T.#String)
Membership   :: */(id/T.#UUID7, admin/T.#Bool)
Project      :: */(id/T.#UUID7, name/T.#String)
Document     :: */(id/T.#UUID7, title/T.#String, body/T.#JSONB)
Comment      :: */(id/T.#UUID7, text/T.#Text)
Tag          :: */(id/T.#UUID7, label/T.#String)
Tagging      :: */id/T.#UUID7

Db :: {
    Membership/(user/User, org/Organization),
    Project/owner/Organization,
    Document/(project/Project, author/User),
    Comment/(document/Document, writer/User, parent/Comment),
    Tagging/(doc/Document, tag/Tag)
}

Db :kind [schema]

Db :prove {
    :axiom (&node.id :pk, &edge :card [0..*/1]),
    :axiom (User.(email, nick)! :uk, Tag.label :uk, (user, org)! :uk, (doc, tag)! :uk),
    :axiom (parent { :nullable, :card [0..*/0..1] }),
    :axiom (parent document == document)  // a reply is on the same document as its parent
}

Db   :style { writer :label "author_id" }
User :style { :label "users", :fill [muted] }
```

- Every foreign key goes from the table holding it to the table it references, so foreign keys compose like functions, and `parent document == document` is a real path equation: both sides go from Comment to Document.
- Tables hold only their own columns. Each foreign key is one edge in Db, drawn as a row of its table: `document` is the row `document_id`, with its arrow to `Document.id`.
- Each table is a fan out of one sealed start, its row, and each table's foreign keys fan out of its diagram name; `/` distributes over the group, so every column lands on the row and every foreign key on a diagram.
- Db holds the tables it names, so its frame surrounds them and its proof reads them. T, reached only through `T.#UUID7`, is drawn beside Db, not in it.
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

Repo :kind [git]

:ref := :shape [round], :fill [muted]

Repo :style {
    &node    :shape [point],
    #Head    { :ref, :label "main" },
    #Feature { :ref, :label "feature/auth" },
    #V1      { :ref, :label "v1.0" },
    #Spike   { :ref, :label "spike/cache" },
    init     :label "a1f3 init",
    readme   :label "b27c add readme",
    fix      :label "c90e fix typo",
    login    :label "d4a1 login form",
    session  :label "e5b2 sessions",
    merge    :label "f6c3 merge feature/auth",
    merge'   :arrow [/dashed/>],
    bump     :label "0a7d bump to 1.0",
    hotfix   :label "1b8e hotfix",
    spike    :label "2c9f try cache"
}

Repo :prove {
    :axiom (fix merge == login session merge'),  // both paths from the fork reach the same state
    :lemma.[clean] (#Merged :pushout)            // fAB checks the merge is clean: the least common state
}
```

- `*/init` starts the history from nothing: before the first commit there is no state.
- `readme/#Fork +(fix/#Main, login session/#Feature)` is a branch: the pinch fans out of Fork, main gets fix, and feature/auth gets two commits.
- `(#Main/merge, #Feature/merge')/#Merged` is the merge. A merge commit has two parents, so it has two legs: `merge` from main and `merge'` from the feature, drawn dashed as the second parent link. The repeated names glue the legs onto the branch heads, and `/` distributes `#Merged` over both.
- `:ref` is a bundle: states that branches and tags name are drawn round and filled, the rest as points.
- The proof states, as an axiom, that the merge square commutes, and asks, as a lemma, whether `#Merged` is its pushout. A merge conflict is exactly the case where no such pushout exists, so the checker would refute the lemma.

The same history can be written branch by branch, each branch its own diagram, and the repository as the diagram holding them (`examples/git-simple.fab`):

```
Master     :: */init commit1 commit2 commit3 commit4 commit5
FeatureOne :: Master.(commit2+)/commit1 commit2 commit3 commit4
FeatureTwo :: Master.(commit2+)/commit1 commit2 merge/Master.(commit3+)

Repo :: Master, FeatureOne, FeatureTwo

Repo :style {
    &node :shape [point]
}
```

- Each branch starts where it leaves another: `Master.(commit2+)` is the state after Master's second commit, shared with Master, so both branches fork from it. The merge lands on `Master.(commit3+)`.
- `Repo :: Master, FeatureOne, FeatureTwo` names the three diagrams, so Repo holds them (see Diagrams as nodes): they are drawn inside it, and Repo's style reaches them, beneath their own. Every commit is a point.
- Repo's three nodes stand for the branches and join nothing; the history itself lives in the branches.

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

- **Declaring nodes and edges.** Zones, nodes and edges are the only declarable structures; labels and signatures declare vocabulary, not structure. A proposed reading: a declaration says "this has a graph inside it". A declared node (`#User :: */(id, name)`) is a graph inside a point: a composite state, or a table, which could replace `:as [node]` and `:as [table]`. A declared edge (`review :: check approve`) is a graph along an arrow: a subprocess, whose inner ends must match the edge's ends.
- **The header.** Its syntax, its boundary, which further descriptors it holds, and the command line's flag to force a rule on files that opted out (`statements.md` §22.7).
- **Diagram composition.** A diagram is held by naming it (see Diagrams as nodes); how an edge reaches into a held diagram through its boundary, rather than to the whole, is open.
- **What a flow could draw of its cells,** if anything, and how many levels stay readable.
- **How a category draws `?` and `!`.** They are declared the same way in every diagram; what a category shows of them is the renderer's to decide.
- **Well-structuredness.** Whether to warn on a `!` fork with no matching `!` join, especially inside a loop, where tokens multiply without bound.
- **Open name sets.** Whether a diagram may admit names on mention. Deferred: types are listed explicitly for now.
- **Patterns of edges.** A way to build several edges from one pattern, such as `f +(3/g)` for g1, g2 and g3. Not decided; every edge still has its own name, and nameless edges are not part of fAB.

**Style**

- **The fallback for `[outer]`** on a lone edge that borders no region.
- **The prelude's contents** beyond the draft in `prelude.fab`: more colour names and themes, and whether `[base]`'s sizes are right.
- **A renderer's fallback per type,** for a label or an attribute it cannot draw.
- **Styling nested diagrams from outside,** which the current rule forbids.

**Place**

- **The whole vocabulary,** with the native layout engine: cardinal flow, relative ranks, grids, routing, loops, stacking.

**Proof**

- **What the checker checks,** whether statements imply others (two commuting squares imply the outer rectangle), and what is drawn for them (corner marks ⌟ ⌜, dashed unique arrows).
- **Explicit cones.** How a universal property names its square when it can't be inferred from the node.
- **Proof vocabulary per kind.** Whether the proof layer says `:mono` or `:pk`: the kind chooses, each in its case of the prelude (`statements.md` §24.3); which properties each kind beyond `[flow]` admits is open.
- **Equations.** They are written `==` and `~=`; what `~=` means (isomorphic objects, or commuting up to an invertible 2-cell) and the rest of their design is open.
- **Proof equations** over partial edges: `parent document == document` holds only where `parent` is defined.
- **Undirected edges in equations,** which have no composition order.
- **Column names for emitters.** A foreign-key row's label is its column's name; whether an emitter reads it from `:label` or from a schema attribute of its own is open until fAB emits SQL.

**Coming.** Decided, and due in a later revision:

- **Recovery item by item inside braces.** Inside `{ }` the parser recovers at each `,`, so a statement with a syntax error there could still draw its good items, with the broken one as a hole (`G :: { f /g, h }` draws `f` and `h`). Until then the whole statement draws its placeholder. What a hole attached to nothing means is to be settled with it.
- **Restrictions and passes** (`statements.md` §17). Declarations describe every structure with a reading; a proof narrows it. `G :kind [category]` states what kind of graph it is, beside G's layers (`statements.md` §24: each kind's look and vocabulary are a case in the prelude, `&zone :kind [category] :> { … }`): what is drawn, which proofs may be posited, and which structures become findings, classed by reason: `&refutable` (contradicts the kind, an error) and `&undecidable` (has no check there, a warning), each with narrower classes per structure (`&undirected-cell`). `:pass` acknowledges a finding, by element or by class, with an optional reason: `α :pass "a relation, not a morphism"`. A pass reaches only findings, never a language error; it leaves a note and never changes the exit code, and a pass that matches nothing warns. The header may state `:kind` too, under the same name; the diagram's wins. A diagram with no kind is a plain graph: it draws everything and raises no findings.

**Reserved.** Constructs whose meaning is open are errors until decided, each marked *reserved* in Errors. Deciding one lifts its error:

- Declaring a node or an edge on its own (Declaring nodes and edges, above).

**Settled since the first revision:** name scope (local to a diagram); precedence of `/` chains (left to right); the clash between colours and named nodes on `#` (colours are values in brackets); the format vocabulary and arrow grammar (now the style layer); styling proof-derived marks (`:marks`, as a definition after the proof).

**Settled on 1 November:** the grammar of joining. Juxtaposition is typed and never merges silently; pinches are the only collapse; `/` attaches one edge or closes a cycle, which exposes its start on the left only; a trailing `/` makes a one-edge chain undirected; every node term takes a slash; nodes meet only when their names and kinds agree. Statements are one line, and braces let them span lines; `,` separates items everywhere, as graphs, bindings or propositions side by side.
