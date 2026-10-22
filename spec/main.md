# fAB — edge notation spec

Oct 20, 2026 · @Ramon

## Principles

fAB describes a diagram by its edges only. Nodes are never written: they are derived from how the edges are glued together.

- **Edges are primary.** Every edge is declared by name, and a name denotes exactly one edge.
- **Nodes are derived.** Each edge has two ends, its domain and its codomain. A node is a class of ends that the syntax glues together. Nodes can also be named (`#A`), but never need to be.
- **Honesty rule.** Every edge has a name, and every node is a quotient. No construct creates an anonymous edge.
- **Declare once, refer backwards.** A bare name declares an edge. A marked name refers to an edge declared to its left.
- **Topology, not geometry.** fAB says what connects to what. Edge properties (identity, iso, commutativity) belong to a later layer.

## Architecture

A program has a header and three layers. Each layer refers only to the layers before it, and always through edge names.

| Part                    | Contents                                                | Mathematical role                                       |
| ----------------------- | ------------------------------------------------------- | ------------------------------------------------------- |
| Header                  | Kind of diagram, strictness, boundary                   | Decides what the relations mean                         |
| Relations `G :: …`      | Edges, gluing, node kinds, edge-to-edge relations `[ ]` | The underlying graph                                    |
| Format `G.format { … }` | Labels and arrow styles                                 | Presentation: what the shape depicts                    |
| Proof `G.proof { … }`   | Equations and universal properties                      | The diagrams that commute and the cones that are limits |

Together, the relations and proof layers form an Ehresmann sketch: a graph, plus the diagrams that must commute and the cones that must be limits.

**Header.** The header fixes three things. Its syntax is still open.

- **Kind:** flow, category or plain graph. In category mode `f g` also implies that the composite exists; in flow mode it is two steps. The kind also decides whether `?`, `!` and `[ ]` are allowed.
- **Strictness:** which warnings are errors, for example an unmatched `!` fork.
- **Boundary:** which open ends the diagram exposes when it is used inside another diagram.

## Diagrams and names

A diagram is declared once, with an uppercase name followed by `::` and a term.

```fab
G :: f g h
```

- **Diagram names** start with an uppercase letter. Each diagram is defined exactly once.
- **Edge names** are all lowercase. The apostrophe is allowed, so `h` and `h'` are distinct names.
- **Declaration.** A bare edge name declares a new edge. Writing the same bare name twice is an error, with one exception: the endomorphism `f/f` (see Back edges and references).
- **Derived nodes.** Comments in this spec write nodes as `N1`, `N2`, … and junctions as ◇. These are labels for derived nodes, not syntax.

**Scope.** Edge names are local to their diagram, so two diagrams can each have their own f. An end of another diagram is reached with dot notation; the parentheses are optional but read better:

```fab
A :: f g
B :: h/A.+f        // h ends at dom(f) of A
B :: h/(A.+f)      // same, easier to read
```

- The referenced diagram must be defined earlier, just as references inside a diagram point left.
- Only ends A exposes can be referenced: never a sealed end, and only ends on A's boundary once the header defines one.
- A cross reference makes B share a node with A. When B is drawn, A appears inside it as a cluster with its own format; B formats only its own subjects, including edges that reach into A.

## Composition

Three constructs build terms: juxtaposition glues, the comma separates, and parentheses group.

| Syntax  | Name           | Meaning                                                                |
| ------- | -------------- | ---------------------------------------------------------------------- |
| `s t`   | Juxtaposition  | All open output ends of s and all open input ends of t become one node |
| `s, t`  | Disjoint union | s and t side by side, sharing nothing                                  |
| `( … )` | Grouping       | Groups a term; `f (g h)` is the same as `f g h`                        |

Precedence, tightest first: `/`, then juxtaposition, then `,`.

Tight operators (`/` and the markers `+`, `?`, `!`, `*`) bind before juxtaposition, so `f g/h` is `f (g/h)`. Within a train of tight operators, reading is left to right: `+f/h/g+` is `(+f/h)/g+`.

**Line breaks.** A newline ends a declaration, except inside parentheses. A declaration that spans several lines is therefore wrapped in `( … )`, opening on the first line and closing on its own line:

```fab
Db :: (
  Document owner User,
  Config settings_of User
)
```

A break inside an existing group needs no extra parentheses: in `Order :: *receive … #Valid? (`, every line break falls inside the decision's group.

**Whitespace decides attachment.** A tight operator attaches to what it touches. Touching both sides, it is binary; touching one side, it is postfix or prefix; touching neither, it is an error.

| Written                 | Meaning                                        |
| ----------------------- | ---------------------------------------------- |
| `f/g`                   | f with the reverse edge g                      |
| `f/ g`                  | undirected f, then g                           |
| `f /g`                  | error: `/` has no prefix form                  |
| `f?(g, h)`, `f? (g, h)` | the same: `?` touches f, and the group follows |
| `*(f, g)`               | seals both domains                             |
| `+f`                    | a reference; `+ f` is an error                 |

```fab
G :: f              // f : N1 → N2
G :: f g h          // f : N1 → N2, g : N2 → N3, h : N3 → N4
G :: f, g           // f : N1 → N2, g : N3 → N4
G :: f (g, h)       // fork: f : N1 → N2, g : N2 → N3, h : N2 → N4
G :: (f, g) h       // join: f : N1 → N2, g : N3 → N2, h : N2 → N4
```

**Juxtaposition always merges.** `(a, b) (c, d)` has a single middle node, not two parallel paths. Matching pairs of ends is done with references (see the square under Examples). This is a deliberate design choice: fAB has no arities.

## Back edges and references

`/` connects the end of a term back to something: a new edge, the term itself, or an existing node. References are written with `+`.

**References.** `+f` is the domain of f and `f+` is its codomain: the marker sits on the side of the end it names. A reference always points left, to an edge declared earlier. A reference only appears fused to an edge by `/`, never on its own.

**A reference closes the side it is on.** Like `*`, it ends the path at that side. `g/+f` is a goto: g jumps to dom(f) and nothing can be glued after it. `+f/g` starts g at dom(f), and nothing can be glued before it.

| Written | Meaning                                         | Interface                             |
| ------- | ----------------------------------------------- | ------------------------------------- |
| `s/e`   | New edge e back, from the end of s to its start | Unchanged                             |
| `f/f`   | Endomorphism f : N → N                          | Unchanged: N stays open on both sides |
| `g/+f`  | g ends at dom(f)                                | Right side closed                     |
| `g/f+`  | g ends at cod(f)                                | Right side closed                     |
| `+f/g`  | g starts at dom(f)                              | Left side closed                      |
| `f+/g`  | g starts at cod(f)                              | Left side closed                      |

**Rules.**

1. In `a/b`, at least one side must not be a reference. A `/` between two references would create no edge. An edge may still be attached at both ends, as in `+f/h/g+`.
2. `f/f` is the only self-reference and the only place a bare name may repeat. It is allowed only when the left side is a single edge, so `(f g)/f` is an error.
3. `f/+f` and `f/f+` are errors. The first duplicates `f/f`; the second glues an end to itself.
4. `s/e` with a multi-end term merges the ends on each side, exactly as juxtaposition would.

```fab
G :: f/e            // f : N1 → N2, e : N2 → N1
G :: f/f g h/h      // f : N1 → N1, g : N1 → N2, h : N2 → N2
G :: (f g)/h        // f : N1 → N2, g : N2 → N3, h : N3 → N1
```

**Undirected edges.** A postfix `/`, touching only the edge before it, makes that edge undirected: it reads as `f/e` with the second edge left out, one connection that goes both ways.

```fab
G :: f/                // f connects N1 and N2, in no direction
G :: f/ g              // undirected f, then g
G :: #A f/ #B, #B g/ #C
```

- The ends are still distinguished by position: `+f` is the end written first and `f+` the end written second. References and gluing work as before.
- The default arrow is `-`. Giving an undirected edge a head, as in `:arrow ->`, is an error: it would draw a direction the relations don't have.
- In a diagram whose header kind is undirected, every edge is undirected, and writing `f/` there is an error.

## Node kinds

Every node has exactly one kind: plain, choice ◇, parallel ‖ or null ⊙. `?` and `!` are postfix only and affect output ends; a flow that starts with a decision writes `*start? ( … )`. `*` sits on the side of the ends it seals: postfix for output ends, prefix for input ends.

| Marker     | Kind       | Effect                                                                  | On a group                        |
| ---------- | ---------- | ----------------------------------------------------------------------- | --------------------------------- |
| none       | plain      | An ordinary node                                                        | —                                 |
| `t?`       | choice ◇   | Merges the ends on that side into one node; exactly one branch is taken | One merged node                   |
| `t!`       | parallel ‖ | Merges the ends on that side into one node; all branches are taken      | One merged node                   |
| `t*`, `*t` | null ⊙     | Seals each end on that side with its own null node                      | Distributes: `(g, h)*` = `g*, h*` |

**Merge versus seal.** `?` and `!` collect several ends into one node. `*` closes each end separately, because a null node belongs to exactly one edge end.

**A kind is declared once, where its node is created.** References inherit the kind of the node they land on, so `f? (b/f+, e)` returns b to the decision node.

**Null ends are private.** Nothing can be glued to a sealed end, and nothing can refer to it. A sealed end leaves the term's interface: `f` has an open codomain, `f*` has none.

```fab
G :: f? (fg g, fh h)       // f : N1 → ◇, fg : ◇ → N2, fh : ◇ → N3, …
G :: f? (g, h)? k          // decision, two branches, merge, continue
G :: f! (g, h)! k          // fork, two parallel branches, join, continue
G :: *f g h*               // a path from a start to a stop
```

## Interfaces

Every term has open input ends and open output ends. Juxtaposition glues only open ends, so the interface decides what a following term attaches to.

| Term                    | Open inputs            | Open outputs           |
| ----------------------- | ---------------------- | ---------------------- |
| `f`                     | dom(f)                 | cod(f)                 |
| `s t`                   | inputs of s            | outputs of t           |
| `s, t`                  | inputs of s and t      | outputs of s and t     |
| `s/e`, `f/f`            | inputs of s            | outputs of s           |
| `g/+f`, `g/f+`          | dom(g)                 | none                   |
| `+f/g`, `f+/g`          | none                   | cod(g)                 |
| `t?`, `t!`              | inputs of t            | the merged node        |
| `t*`                    | inputs of t            | none                   |
| `*t`                    | none                   | outputs of t           |
| `#A`, `A.#X`            | the named node         | the named node         |
| `@`                     | the diagram's own node | the diagram's own node |
| `User` (a diagram name) | `User.@`               | `User.@`               |

Two consequences follow:

- **Back edges keep the interface; references close it.** `f/f g` continues from the loop node, while `f (g/+f, h) k` continues only from h.
- **Ending a branch.** A branch inside a group ends with `*` (a stop) or with a reference (a jump). Any branch that does neither is glued to what follows the group. Closed ends are skipped, so `(f*, g) h` attaches h to g only; a juxtaposition is an error only when one side has no open end at all, as in `f* g`.

**Node terms stay open.** `#A`, `@` and diagram names add no edge, so the same node is both their input and their output. This is what lets `#U f #V, #U g #W` fork at U and `id T.#UUID7` end on a shared type. It is also the difference from references fused with `/`: those close the side they are on, while a named node never closes anything.

## Named nodes and diagrams as nodes

Edges remain primary, but a node can be named when the diagram needs to talk about it directly.

**Named nodes.** `#A` is a node term: it adds no edge, and names the node it is glued to. Categorically it is the identity on A.

```fab
G :: #A f #B                         // f : A → B
G :: #A                              // a lone object: one node, no edges
T :: #UUID7, #DTZ, #String, #JSONB   // a discrete diagram: objects only
```

- **A repeated name glues.** `#U f #V, #U g #W` is a fork at U.
- **The name is canonical.** A named node is referenced and formatted as `#A`, never as `+f`.
- **One node, one name.** `#A #B` is an error.
- **Scope is local.** Another diagram's named node is `A.#X`, as with `A.+f`. It must already be declared there: names never come into existence by being mentioned.

**The diagram's own node.** `@` is a node term marking the node that stands for the diagram itself. A diagram has at most one `@`.

```fab
User :: @ (id T.#UUID7, created_at T.#DTZ, name T.#String)
```

`@ ( … )` is an ordinary fork: every attribute is an edge from User's own node to a type.

**Diagrams as nodes.** In relations, an uppercase name is a node: the diagram it names, attached at its `@`. Repeated names glue, as with `#A`.

```fab
Db :: Document owner User    // owner : Document.@ → User.@
```

When drawn, User and Document appear inside Db as clusters, each with its own format. Using a diagram without an `@` as a node is an error. This is the move `[ ]` makes, one level up: there edges become nodes, here diagrams do.

### Schemas

A database schema is a category presented by a graph and path equations, as in categorical databases. fAB writes one directly.

| Schema       | fAB                                                                       |
| ------------ | ------------------------------------------------------------------------- |
| Table        | A diagram with an `@` node                                                |
| Column       | An edge from `@` to a type                                                |
| Type         | A named node in a shared types diagram                                    |
| Relationship | An edge from the table holding the foreign key to the table it references |
| Primary key  | `:pk` on a column: the column is mono (injective)                         |
| Foreign key  | `:by` on a relationship: the column that realizes it                      |
| Constraint   | A path equation                                                           |

```fab
T :: #UUID7, #DTZ, #String, #JSONB

User     :: @ (id T.#UUID7, created_at T.#DTZ, name T.#String)
Document :: @ (id T.#UUID7, user_id T.#UUID7, data T.#JSONB)
Config   :: @ (id T.#UUID7, user_id T.#UUID7, data T.#JSONB)

Db :: Document owner User, Config settings_of User

Db.proof {
  .node.id :pk
  Config.user_id :unique
  owner       :by user_id  :card 0..* 1
  settings_of :by user_id  :card 0..1 1
}
```

- **No forward references between tables.** Tables never refer to each other; every relationship lives in Db, which is defined after them. Circular foreign keys are two edges in Db, and a self-reference is a loop on one cluster.
- **Shared types.** `T.#UUID7` is the same node in every table, which is what lets `:by` check that a foreign key's type matches the key it references. T is listed explicitly, so a misspelled type is an error.

## Edge-to-edge relations

`[ ]` is the same language one dimension up: inside the brackets, the outer edges are the nodes, and new names are edges between edges (2-cells). Brackets are appended at the end with `,`, so every edge they mention is already declared.

```fab
Nat :: f, +f/g/f+, [f α g]       // f, g : A ⇉ B,  α : f ⇒ g
Iso :: f, +f/g/f+, [f α/β g]     // α : f ⇒ g,  β : g ⇒ f
Vc  :: …, [f α g β h]            // α followed by β
```

- **Names decide their role.** A name declared outside cannot be declared again, so inside `[ ]` it is a node. A new name is a 2-cell.
- **Same operators.** Juxtaposition, `/` and `,` keep their meaning: `f α g` glues α's domain to f and its codomain to g.
- **Node-first by necessity.** At this level the nodes already exist, as the outer edges. Each level is edges-first relative to the level below it.
- **Higher levels.** `[[ ]]` would hold edges between 2-cells, with the same rules. Deep nesting is hard to read, so its use should stay rare.
- **Kind.** In category mode `[ ]` holds 2-cells. In flow mode it has no meaning yet, and the header forbids it.

## Format layer

`G.format { … }` gives everything drawn in G its appearance. It never changes the graph: every relation, including placement relative to other nodes, is already fixed by the relations layer.

**Statements.** A statement is a subject followed by methods. Each method `:name value` is a single descriptor. A subject with several methods can open a block; the inline and block forms mean the same thing.

```fab
G :: f g

G.format {
  f  :arrow ->>  :stroke 0xc0392b
  +f {
    :label $\mathbb{R}$
    :shape circle
  }
  f+ :label $\mathbb{N}$
  g+ :label $\sigma$
}
```

- **Subjects are references.** Only the relations layer declares. A bare name refers to an edge, and a marked name (`+f`, `f+`, `f*`, `f?`, `f!`) refers to a node.
- **Canonical references.** A node is formatted only through its canonical reference: its name if it has one (`#A`, `@`), and otherwise the first end that created it, in reading order. In `f g`, the middle node is `f+`, never `+g`. `f*`, `f?` and `f!` are canonical by construction.
- **Once.** A subject appears once per format block, inline or as a block, and a method appears once per subject.
- **Blocks hold methods only.** A subject's block contains methods, never other subjects.

**Named nodes as subjects.** `#A` and `@` are subjects, and a named node is formatted only through its name. Another diagram's name is never a subject: each diagram formats itself.

```fab
Sq :: f h, +f/g k/h+
// canonical: +f (A), f+ (B), g+ (C), h+ (D)
// rejected:  +g, +h, +k, k+
```

### Subjects

| Subject | Written                      | Denotes                                                                   |
| ------- | ---------------------------- | ------------------------------------------------------------------------- |
| Edge    | `f`                          | An edge                                                                   |
| Node    | `+f`, `f+`, `f*`, `f?`, `f!` | A node, through its canonical reference                                   |
| Cell    | `α`                          | An edge declared inside `[ ]`                                             |
| Canvas  | `G`, in `G.format`           | The diagram itself, and its frame when it is drawn inside another diagram |
| Group   | `f, g, h`                    | Every subject in the list, with the same methods                          |
| Class   | `.iso`                       | A named set of methods, applied with `:class`                             |

**Each diagram formats itself.** When C references A, A is drawn inside C as a cluster, and A keeps its own format: A's frame is set in `A.format`, through its canvas subject. C formats only C's own subjects, including C's edges that reach into A. A's nodes and edges cannot be formatted from C.

```fab
A :: f
B :: g
C :: k (u/A.+f, v/B.f+)

A.format { A :line dashed  :label "A" }
C.format {
  u :arrow (->
  v :stroke 0x888888
}
```

### Colour

Three methods, one per kind of paint. Each applies only where that paint exists.

| Method    | Paints        | Applies to                                         |
| --------- | ------------- | -------------------------------------------------- |
| `:ink`    | Text and math | Labels of every subject                            |
| `:stroke` | Lines         | Edge lines and heads, node borders, diagram frames |
| `:fill`   | Areas         | Node interiors, diagram backgrounds                |

### Values and units

| Type     | Forms                                                                 |
| -------- | --------------------------------------------------------------------- |
| Math     | `$…$`, LaTeX                                                          |
| Text     | `"…"`, with inline math allowed: `"x = $\alpha$"`; `\n` breaks a line |
| Colour   | `0xrrggbb`, CSS names, theme tokens such as `accent` and `muted`      |
| Length   | number, in em only                                                    |
| Angle    | number, in degrees                                                    |
| Fraction | `0` to `1`, a position along an edge                                  |
| Keyword  | `left`, `dashed`, …                                                   |

### Methods

Applies to: N node, E edge, L cell, V canvas.

**Text**

| Method                       | Values                          | Applies to | Default                                                  |
| ---------------------------- | ------------------------------- | ---------- | -------------------------------------------------------- |
| `:label`                     | math, text                      | N E L V    | none; on the canvas it is the title, drawn on the frame  |
| `:label-start`, `:label-end` | math, text                      | E L        | none: labels at the tail and head                        |
| `:ink`                       | colour                          | N E L V    | theme                                                    |
| `:font`                      | name                            | N E L V    | theme                                                    |
| `:size`                      | length                          | N E L V    | theme                                                    |
| `:align`                     | `left`, `center`, `right`       | N V        | `center`                                                 |
| `:wrap`                      | length                          | N          | none                                                     |
| `:side`                      | `left`, `right`, `on`           | E L        | `left`, relative to the direction; `on` sits on the line |
| `:label-at`                  | `start`, `mid`, `end`, fraction | E L        | `mid`                                                    |

**Line**

| Method    | Values                                                | Applies to | Default                                                                                 |
| --------- | ----------------------------------------------------- | ---------- | --------------------------------------------------------------------------------------- |
| `:stroke` | colour                                                | N E L V    | theme                                                                                   |
| `:weight` | `thin`, `normal`, `thick`                             | N E L V    | `normal`                                                                                |
| `:line`   | `solid`, `dashed`, `dotted`, `double`, `wavy`, `none` | N V        | nodes: `solid` when they have a border; canvas: `none` standalone, `solid` as a cluster |
| `:arrow`  | arrow grammar                                         | E L        | `->` for edges, `=>` for cells                                                          |

**Area**

| Method              | Values                                                                                                                                                                         | Applies to | Default                                                           |
| ------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ | ---------- | ----------------------------------------------------------------- |
| `:fill`             | colour                                                                                                                                                                         | N V        | none                                                              |
| `:shape`            | `none`, `box`, `round`, `circle`, `double-circle`, `ellipse`, `stadium`, `diamond`, `hexagon`, `parallelogram`, `cylinder`, `document`, `bar`, `point`, `terminal`, `bullseye` | N          | category: `none`; flow: `box`, ◇ `diamond`, ‖ `bar`, ⊙ `terminal` |
| `:width`, `:height` | length                                                                                                                                                                         | N          | fitted to the label: minimums only                                |
| `:padding`          | length                                                                                                                                                                         | N V        | theme                                                             |

**Placement.** Only absolute hints; nothing here relates one subject to another.

| Method     | Values                                            | Applies to | Default                     |
| ---------- | ------------------------------------------------- | ---------- | --------------------------- |
| `:at`      | row col                                           | N          | free; grid layout only      |
| `:rank`    | number                                            | N          | free; layered layout only   |
| `:bend`    | `left`, `right`, with optional degrees: `left 30` | E L        | straight                    |
| `:loop`    | `above`, `below`, `left`, `right`                 | E          | `above`; endomorphisms only |
| `:shorten` | length                                            | E L        | none                        |
| `:z`       | number                                            | N E L      | drawing order               |

**Canvas only**

| Method       | Values                                                  | Default                                            |
| ------------ | ------------------------------------------------------- | -------------------------------------------------- |
| `:layout`    | `grid`, `layered`, `force`, `circular`, `table`, `auto` | category: `grid`; flow: `layered`                  |
| `:direction` | `right`, `left`, `down`, `up`                           | category: `right`; flow: `down`                    |
| `:routing`   | `straight`, `curved`, `orthogonal`                      | category: `straight`; flow: `orthogonal`           |
| `:spacing`   | length                                                  | theme                                              |
| `:caption`   | math, text                                              | none                                               |
| `:theme`     | `light`, `dark`, `print`, `auto`                        | `auto`                                             |
| `:marks`     | `all`, `none`                                           | `all`: draws marks from the proof layer, such as ⌟ |
| `:alt`       | text                                                    | none: description for screen readers               |

`table` draws the edges leaving the own node `@` as rows inside the frame, each showing the edge's name and its target. It is the default for diagrams with an `@` in the schema kind.

**Behaviour**

| Method   | Values      | Applies to                                     |
| -------- | ----------- | ---------------------------------------------- |
| `:class` | class names | N E L                                          |
| `:note`  | text        | N E L V: shown on hover, never drawn           |
| `:link`  | URL         | N E L V                                        |
| `:hide`  | —           | N E L: kept in the graph and layout, not drawn |
| `:step`  | number      | N E L: reveal order when presenting            |

**Not format.** Else-branches, probabilities and guards are meaning, not appearance. They belong in the proof layer, not here.

### Arrow grammar

An `:arrow` value is tail, line, mark, head. Only the line is required. Every end has a head form and a mirrored tail form, so `<->` and `<|-|>` need no extra rules. The arrow only draws: the edge's direction always comes from the relations.

**Lines**

| Line | Draws  |
| ---- | ------ |
| `-`  | Solid  |
| `--` | Dashed |
| `..` | Dotted |
| `~`  | Wavy   |
| `=`  | Double |

**Ends**

| Head                       | Tail                       | End             | Typical use                                              |
| -------------------------- | -------------------------- | --------------- | -------------------------------------------------------- |
| `>`                        | `<`                        | Arrow           | Default                                                  |
| `>>`                       | `<<`                       | Two heads       | Epi ↠                                                    |
| `\|>`                      | `<\|`                      | Hollow triangle | Generalization (UML)                                     |
| `\|`                       | `\|`                       | Bar             | Tail: maps-to ↦; head: inhibition ⊣                      |
| `0`                        | `0`                        | Hollow circle   | Lollipop, interfaces                                     |
| `@`                        | `@`                        | Filled dot      | Dot ends, Petri nets                                     |
| `*`                        | `*`                        | Cross           | Lost, destroyed, stopped                                 |
| `<>`                       | `<>`                       | Hollow diamond  | Aggregation                                              |
| `<@>`                      | `<@>`                      | Filled diamond  | Composition                                              |
| `)`                        | `(`                        | Hook            | Inclusion ↪                                              |
| `\`                        | `/`                        | Upper harpoon   | ⇀                                                        |
| `/`                        | `\`                        | Lower harpoon   | ⇁                                                        |
| `\|\|`, `0\|`, `\|{`, `0{` | `\|\|`, `\|0`, `}\|`, `}0` | Crow's foot     | Cardinality: one, zero or one, one or more, zero or more |

**Marks** sit between two copies of the line: `-/->` draws a struck arrow ↛, `-|->` a tick.

| Arrow     | Reads as                                       |
| --------- | ---------------------------------------------- |
| `->`      | Plain                                          |
| `>->`     | Mono ↣                                         |
| `->>`     | Epi ↠                                          |
| `(->`     | Inclusion ↪                                    |
| `\|->`    | Maps-to ↦                                      |
| `-->`     | Dashed: unique existence                       |
| `=>`      | Double: implication, and the default for cells |
| `-\|`     | Inhibition ⊣                                   |
| `-0`      | Lollipop                                       |
| `--*`     | Dashed, ending in a cross                      |
| `-\|>`    | Generalization                                 |
| `<>-`     | Aggregation                                    |
| `-/->`    | Struck: "does not" ↛                           |
| `\|\|-0{` | One to zero-or-more                            |
| `-`, `=`  | Line or double line, no heads                  |

Inside an `:arrow` value, characters are arrow glyphs only: `/` and `?` have no fAB meaning there. `*` keeps an echo of its relations meaning, an end where the flow stops.

### Classes

A class is a named set of methods, defined in the format block in either form. Built-in classes set defaults for every subject of one kind.

```fab
Sq.format {
  .iso { :arrow ->  :label $\cong$ }
  .edge :stroke 0x444444
  f    :class iso
  g, k :stroke 0x888888
  +f   :label $P$
}
```

- **Built-in classes:** `.node`, `.edge`, `.cell`, `.junction`, `.null`.
- **Cascade:** header kind, then built-in class, then named classes, then direct methods. Each level overrides the one before.
- **Conflict:** two named classes on one subject that set the same method is an error. Write the method directly instead.

**Format errors.** Unknown method; value of the wrong type; method that does not apply to the subject (`:loop` on a node, `:fill` on an edge, `:line` on an edge, whose line is part of `:arrow`); a subject formatted twice; a method set twice on one subject; a non-canonical reference; a subject inside another subject's block; another diagram's subject formatted here (`A.+f` in `C.format`); two named classes setting the same method; a class used before it is defined.

The earlier survey of every candidate method, with its friction, is in Vocabulary survey.

## Proof layer

`G.proof { … }` states what holds in the diagram. It has exactly two statement forms, both subject-first.

```fab
Sq :: f h, +f/g k/h+

Sq.proof {
  f h = g k          // path = path: the square commutes
  +f :pullback       // subject :property
}
```

- **Equations** relate two paths, written with juxtaposition in diagrammatic order. Both sides must be existing paths with the same start and end.
- **Identities are equations.** `+f` denotes the identity on dom(f), so `f = +f` says that the endomorphism `f/f` is an identity. No keyword is needed.
- **Universal properties** attach to a node. `+f :pullback` takes the commuting square that starts at `+f` as its cone. If no such square, or more than one, starts there, the statement is rejected and the square must be given explicitly.
- **Once per diagram.** `G.format` and `G.proof` each appear at most once, like `G` itself.

**Pushouts mirror pullbacks.** `#M :pushout` takes the commuting square that ends at `#M` as its cocone, with the same rule: if no such square ends there, or more than one does, the statement is rejected.

**Schema statements.** `:pk` marks a key, which makes it mono. `:unique` marks values that never repeat, and `:nullable` marks a column that may be empty. `:pk` and `:unique` also take a group of columns from one table, with the table written once: `User.( … )`, the same dot notation as cross-diagram references.

- **Each:** a plain group applies the statement to every member. `User.(email, nick) :unique` makes each column unique on its own.
- **Together:** a group closed with `!` is taken as one product. `User.(email, nick)! :unique` makes the pair unique, read as ⟨email, nick⟩ : User → String × String being mono. In a key group, `!` gathers the group into one key and says nothing about the columns' ends.
- **Not a key:** juxtaposition inside a group is a path, so `User.(email nick)` is an error, and `?` means "one of", so `User.(email, nick)? :unique` is an error too.
- **One primary key:** a composite primary key is `Table.(a, b)! :pk`, and `Table.(a, b) :pk` is an error, because it gives the table two keys.

**One of: `(a, b)?`.** A group closed with `?` is a choice, the coproduct. `:required` on it says that exactly one member is set. This is how exclusive columns are written, as in a comment that belongs either to a post or to a photo. Each member must also be `:nullable`, since the others are empty.

```fab
Post    :: @ (id T.#UUID7, author_id T.#UUID7, title T.#String)
Photo   :: @ (id T.#UUID7, url T.#String)
Comment :: @ (id T.#UUID7, post_id T.#UUID7, photo_id T.#UUID7, text T.#Text)

Feed :: Comment (on_post Post, on_photo Photo)

Feed.proof {
  .node.id :pk
  .edge :by {.edge+ :snakecase}_id  :card 0..* 0..1
  Post.(author_id, title)! :unique               // together: no author repeats a title
  Comment.(post_id, photo_id) :nullable          // each: either may be empty
  Comment.(post_id, photo_id)? :required         // one of: exactly one is set
}
```

Categorically, the two edges together are one arrow Comment → Post + Photo, into the sum. The three group forms are then the three ways columns combine: each on its own, together as a product, or one of them as a sum.

`:by` names the column that realizes a relationship, and `:card` gives the cardinality at the edge's source, then at its target: `:card 0..* 1`. Relationship edges always go from the table holding the foreign key to the table it references. The checker verifies that a `:by` column lives in the edge's source table, that its type is the target's key type, that a target end of `0..1` uses a `:nullable` column, and that a source end of at most one uses a `:unique` column.

**Bare `:by` columns.** A `:by` column always lives in the edge's source table, so it is written without the table: `within :by org_id` means `Membership.org_id`. The checker still reports an error if the column doesn't exist there.

**Local defaults.** A proof block can state a default for a class of subjects, using the same built-in classes as the format layer. Nothing is defaulted unless the author writes it.

```fab
Db.proof {
  .node.id :pk
  .edge :by {.edge+ :snakecase}_id  :card 0..* 1
}
```

- **Classes.** `.node` ranges over the diagram's nodes, which in a schema are its tables; `.node.id` is each table's `id` column. `.edge` ranges over its edges.
- **Ends of the matched subject.** Inside a `.edge` rule, `+.edge` and `.edge+` are the source and target of the edge being matched.
- **Interpolation.** `{ … }` inside a value inserts a name. A method inside it transforms the name: `:snakecase` turns `OrgUnit` into `org_unit`. So for `member`, `{.edge+ :snakecase}_id` is `user_id`.
- **Explicit wins.** A statement about a specific subject overrides the default, as direct methods override classes in the format layer.
- **No guessing.** If a default matches no column, or several, for some subject, that is an error at that subject until an explicit statement covers it.

**Derived marks attach to existing subjects.** Crow's feet come from `:card` but are drawn on the relationship edge, which the format layer styles as usual.

## Errors

A program that hits any of these is rejected.

| Error                            | Example             | Why                                                                                                                                             |
| -------------------------------- | ------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------- |
| Diagram defined twice            | `G :: f` … `G :: g` | One definition per diagram                                                                                                                      |
| Edge declared twice              | `f g f`             | A bare name declares; only `f/f` may repeat                                                                                                     |
| Self-reference outside `f/f`     | `(f g)/f`           | Endomorphism needs a single edge on the left                                                                                                    |
| Redundant self-attachment        | `f/+f`              | Same graph as `f/f`                                                                                                                             |
| Vacuous self-attachment          | `f/f+`              | Glues an end to itself                                                                                                                          |
| Edge built from references only  | `+g/+f`, `g+/f+`    | `/` needs at least one bare name                                                                                                                |
| Forward reference                | `+f/g f`            | References point left only                                                                                                                      |
| Bare reference                   | `k +f`              | A reference must be fused with `/`                                                                                                              |
| Kind declared twice              | `k?/+f`, `+f?`      | A node's kind is set once, where it is created                                                                                                  |
| Conflicting kinds                | `f?*`, `f?!`        | Kinds are exclusive                                                                                                                             |
| Juxtaposition that glues nothing | `f* g`, `g/+f h`    | One side has no open end, so nothing connects; write `f*, g` for separate pieces. Closed ends among open ones are skipped: `(f*, g) h` is legal |
| Reference to a sealed end        | `f*, k/f+`          | Null nodes are private                                                                                                                          |
| Sealing a shared end             | `f/e*`              | Only an otherwise unglued end can be sealed                                                                                                     |
| Both ends sealed                 | `*f*`, `*(f, g)*`   | An edge from nothing to nothing says nothing                                                                                                    |
| Tight operator touching nothing  | `f / g`, `+ f`      | A tight operator attaches to what it touches                                                                                                    |
| Prefix `/`                       | `f /g`              | `/` is binary or postfix only                                                                                                                   |

**Errors in edge-to-edge relations, format and proof**

| Error                               | Example                                 | Why                                                     |
| ----------------------------------- | --------------------------------------- | ------------------------------------------------------- |
| Inner node is not an outer edge     | `[α β]`, `[f α gg]` with gg undeclared  | Inside `[ ]`, every node must be a declared edge        |
| 2-cell between non-parallel edges   | `[f α h]` in the square                 | f and h must share domain and codomain                  |
| Declaration outside relations       | a new name in `G.format`                | Only the relations layer declares                       |
| Non-canonical reference             | `+g :label …` in `f g`                  | Label the node through `f+`, the end that created it    |
| Node labelled twice                 | `f+ :label A` and `f+ :label B`         | A node has one label                                    |
| Equation between non-parallel paths | `f = g` in `f g`                        | Both paths must have the same start and end             |
| Ambiguous universal property        | `+f :pullback` with two squares at `+f` | The cone must be determined; give the square explicitly |
| Layer block defined twice           | two `G.proof` blocks                    | Each block appears once per diagram                     |
| `[ ]` in flow mode                  | `[f α g]` under a flow header           | Edge-to-edge relations have no flow meaning yet         |

**Errors in named nodes and schemas**

| Error                                        | Example                                                                   | Why                                                                               |
| -------------------------------------------- | ------------------------------------------------------------------------- | --------------------------------------------------------------------------------- |
| Node named twice                             | `#A #B`                                                                   | One node, one name                                                                |
| Named node referenced by an end              | `+f :label …` where dom(f) is `#A`                                        | A named node is referenced by its name                                            |
| Two own nodes                                | `@ f @`                                                                   | A diagram has at most one `@`                                                     |
| Diagram without `@` used as a node           | `Db :: T owns User`                                                       | Only a diagram with an own node can attach                                        |
| Undeclared name in another diagram           | `T.#UUDI7`                                                                | Names never come into existence by being mentioned                                |
| `:by` column on the wrong side               | `owner :by User.id`                                                       | The column lives in the edge's source table                                       |
| Foreign key type mismatch                    | `user_id` typed `T.#String`                                               | The column's type must be the referenced key's type                               |
| One-to-one without a unique column           | `:card 0..1 1` with a column not marked `:unique`                         | One-to-one needs a unique column                                                  |
| Optional reference without a nullable column | `:card 0..* 0..1` with a column not marked `:nullable`                    | A target end of 0..1 means the column may be empty                                |
| Composite key across tables                  | `(User.id, Tag.id)! :unique`                                              | A composite key groups columns of one table                                       |
| Undirected edge with a head                  | `f/` with `f :arrow ->`                                                   | The drawing would show a direction the relations don't have                       |
| Redundant undirected marker                  | `f/` under an undirected header                                           | Every edge is already undirected                                                  |
| Default without exactly one match            | `.edge :by {.edge+ :snakecase}_id` when `within` has no `organization_id` | Defaults never guess; state it explicitly                                         |
| `:by` column missing from the source table   | `within :by user_ref`                                                     | A bare column is looked up in the edge's source table                             |
| Two primary keys                             | `User.(id, email) :pk`                                                    | The plain group gives each column the key; a composite key is `Table.(a, b)! :pk` |
| Path used as a key                           | `User.(email nick) :unique`                                               | Juxtaposition is a path; a composite key is a product, `User.(email, nick)!`      |
| Exclusive member not nullable                | `Comment.(post_id, photo_id)? :required` without `:nullable`              | Only one member is set, so the others must be able to be empty                    |

## Examples

In this spec, each line of a code block is an independent diagram. A real program defines each diagram once.

**Mathematical diagrams**

```fab
Sq   :: f h, +f/g k/h+          // commutative square: f;h and g;k from A to D
Tri  :: f g, +f/h/g+            // triangle: f;g and h from A to C
Iso  :: f/g                     // f : A → B, g : B → A
Endo :: f/f                     // f : A → A
Pair :: f, +f/g/f+              // parallel pair f, g : A ⇉ B
```

In `Tri`, h is a bare edge attached at both ends: `+f/h` starts it at dom(f), and `/g+` ends it at cod(g). This is legal because h itself is declared; only a `/` between two references is forbidden.

**Flow diagrams**

```fab
If    :: f? (fg g, fh h)? k              // decision, two branches, merge
While :: f? (b/f+, e)                    // body b returns to the test; e exits
Exit  :: f? (fg g*, fh h) k              // g's branch stops; only h continues to k
Loop  :: f? (fg g/g, fh h/h' k/+f)       // k : N4 → dom(f)
Par   :: *s! (a, b)! t*                  // start, fork, two parallel branches, join, stop
```

### A flowchart: order fulfilment

An order is validated, then payment and stock reservation run in parallel, each with its own retry loop, before the order ships. Every state is a named node, so the format block can label it directly.

```fab
Order :: *receive #Received validate #Valid? (
    yes #Accepted! (
        charge #Charged? (paid, declined #Waiting retry/charge+)
      , reserve #InStock? (reserved, short #Backorder restock/reserve+)
    )! #Ready ship #Shipped close*
  , no #Rejected notify*
)

Order.format {
  #Received  :label "Order received"
  #Valid     :label "Valid?"
  #Charged   :label "Payment accepted?"
  #Waiting   :label "Wait 10 min"
  #InStock   :label "In stock?"
  #Backorder :label "Backorder"
  #Shipped   :label "Shipped"
  #Rejected  :label "Rejected"
  yes, paid, reserved  :label "yes"
  no, declined, short  :label "no"
  retry, restock       :arrow -->  :label "retry"
}
```

What each construct does here:

- `*receive` and `close*`, `notify*` are the start and the two ends.
- `#Valid?`, `#Charged?` and `#InStock?` are decisions; `#Accepted!` forks and `)!` joins, and the join is named `#Ready`.
- `retry/charge+` jumps back to the payment check and closes its branch, so only `paid` reaches the join. The same holds for `restock/reserve+`.
- The fork is matched by a join, and both loops are choice loops, so the diagram is well-structured.

### A database schema: documents and comments

Users belong to organizations through memberships, projects belong to organizations, and documents live in projects, with comments that can reply to each other and tags attached through a join table.

```
T :: #UUID7, #DTZ, #String, #Text, #JSONB, #Bool

User         :: @ (id T.#UUID7, email T.#String, nick T.#String, name T.#String, created_at T.#DTZ)
Organization :: @ (id T.#UUID7, name T.#String)
Membership   :: @ (id T.#UUID7, user_id T.#UUID7, org_id T.#UUID7, admin T.#Bool)
Project      :: @ (id T.#UUID7, org_id T.#UUID7, name T.#String)
Document     :: @ (id T.#UUID7, project_id T.#UUID7, author_id T.#UUID7, title T.#String, body T.#JSONB)
Comment      :: @ (id T.#UUID7, document_id T.#UUID7, author_id T.#UUID7, parent_id T.#UUID7, text T.#Text)
Tag          :: @ (id T.#UUID7, label T.#String)
Tagging      :: @ (id T.#UUID7, document_id T.#UUID7, tag_id T.#UUID7)

Db :: (
  Membership (member User, within Organization),
  Project under Organization,
  Document (in_project Project, author User),
  Comment (on Document, writer User, reply_to Comment),
  Tagging (tagged Document, tag Tag)
)

Db.proof {
  .node.id :pk
  .edge :by {.edge+ :snakecase}_id  :card 0..* 1

  User.(email, nick)! :unique
  Tag.label :unique
  Membership.(user_id, org_id)! :unique
  Tagging.(document_id, tag_id)! :unique
  Comment.parent_id :nullable

  within     :by org_id
  under      :by org_id
  author     :by author_id
  writer     :by author_id
  reply_to   :by parent_id  :card 0..* 0..1

  reply_to on = on      // a reply is on the same document as its parent
}

User.format { User :label "users"  :fill muted }
Db.format   { Db :layout layered  :direction right }
```

What each construct does here:

- Every relationship edge goes from the table holding the foreign key to the table it references, so edges compose like functions and `reply_to on = on` is a real path equation: both sides go from Comment to Document.
- `Comment (…, reply_to Comment)` is a self-reference: the repeated name glues, so `reply_to` is a loop on one cluster.
- Membership and Tagging are join tables; many-to-many relationships are two many-to-one edges.
- No arrow styles are written: the crow's feet come from `:card`. Tables draw their columns as rows through the `table` layout, the default for diagrams with an `@` in the schema kind.

### A git history: commits as arrows

A commit is a change, so it is an edge from one state of the code to the next, and branches and tags are names for states. A branch is a fork, and a merge is the one place where history stops being a tree: both branches reach the merged state, and the square they form is a pushout, as in categorical theories of patches.

```fab
Repo :: (
  *init readme #Fork (fix #Main, login session #Feature),
  (#Main merge, #Feature merge') #Merged bump #V1 (hotfix #Head, spike #Spike)
)

Repo.format {
  Repo :layout layered  :direction right
  .node :shape point
  .ref  :shape round  :fill muted
  #Head    :class ref  :label "main"
  #Feature :class ref  :label "feature/auth"
  #V1      :class ref  :label "v1.0"
  #Spike   :class ref  :label "spike/cache"
  init    :label "a1f3 init"
  readme  :label "b27c add readme"
  fix     :label "c90e fix typo"
  login   :label "d4a1 login form"
  session :label "e5b2 sessions"
  merge   :label "f6c3 merge feature/auth"
  merge'  :arrow -->
  bump    :label "0a7d bump to 1.0"
  hotfix  :label "1b8e hotfix"
  spike   :label "2c9f try cache"
}

Repo.proof {
  fix merge = login session merge'     // both paths from the fork reach the same state
  #Merged :pushout                      // the merge is clean: the least common state
}
```

What each construct does here:

- `*init` starts the history from nothing: before the first commit there is no state.
- `#Fork (fix #Main, login session #Feature)` is a branch: main gets `fix`, and feature/auth gets two commits.
- `(#Main merge, #Feature merge') #Merged` is the merge. A merge commit has two parents, so it has two legs: `merge` from main and `merge'` from the feature, drawn dashed as the second parent link. The repeated names `#Main` and `#Feature` glue the merge onto the branch heads.
- `#V1 (hotfix #Head, spike #Spike)` leaves an unmerged branch, spike/cache, beside main.
- Commits are labelled with their short hash and message. States are drawn as points, except those that branches and tags name.
- The proof states that the merge square commutes and that `#Merged` is its pushout. A merge conflict is exactly the case where no such pushout exists, so a checker could refuse the second statement.

## Mathematical reading

A diagram denotes a directed multigraph presented by its edges, the shape from which a free category or a commutative diagram is built.

**Nodes as a quotient.** Let E be the declared edges. The ends are P = E × {dom, cod}, and the syntax generates an equivalence \~ on P. The nodes are the classes, and source and target are the maps that send an edge to the class of its end:

```latex
V = P / {\sim}, \qquad s, t : E \to V
```

In Set this quotient is a coequalizer, so a diagram is a graph obtained by gluing free edges.

**Correspondences.**

| fAB                        | Mathematics                                                 |
| -------------------------- | ----------------------------------------------------------- |
| Edges first, nodes derived | Arrows-only (single-sorted) definition of a category        |
| `+f`, `f+`                 | s(f), t(f): the identities on dom(f) and cod(f)             |
| `s t`                      | Gluing along an interface (pushout of open graphs)          |
| `s, t`                     | Coproduct in the category of graphs                         |
| `f/f`                      | Endomorphism                                                |
| `f/g`                      | A pair of arrows A ⇄ B, the shape of an iso or a retraction |
| `s/e`                      | Feedback, with the returning edge named                     |
| `?`                        | Choice: exactly one branch, coproduct-like                  |
| `!`                        | Parallel: all branches, product- or tensor-like             |
| `t*`                       | Removes an end from the interface: a term with no output    |

## Open questions

- [ ] **Header syntax.** How kind, strictness and boundary are written.

  **Pinned: styling proof-derived marks.** A mark such as ⌟ exists only because the proof layer says `:pullback`. The format layer comes before the proof layer, so styling the mark would name something the format layer cannot yet see.

- [ ] **Explicit cones.** How a universal property names its square when it can't be inferred from the node.
- [ ] **Format vocabulary.** Review the method catalogue and the arrow grammar under Format layer.
- [ ] **Meaning of 2-cells.** What edge-to-edge relations express, and how deep `[[ ]]` nesting can go before it stops being readable.
- [ ] **Well-structuredness.** Whether to warn on a `!` fork with no matching `!` join, especially inside a loop, where tokens multiply without bound.
- [x] **Name scope.** Whether edge names are local to their diagram, so two diagrams can each have their own f.
- [ ] **Diagram composition.** How one diagram is used inside another, through its boundary.
- [x] **Precedence of `/` chains.** `+f/h/g+` reads left to right as `(+f/h)/g+`; confirm that chained `/` always associates to the left.

* [x] **The `#` sigil.** Colours (`#f5f5f5`) and named nodes (`#User`) both use `#`, and `#ADD` is both. One of them needs another form.
* [ ] **Open name sets.** Whether a diagram may admit names on mention. Deferred: types are listed explicitly for now.
* [ ] **Proof vocabulary per kind.** Whether the proof layer says `:mono` or `:pk`; the header's kind is the natural place to choose.

- [ ] **Proof equations.** Equalities, inequalities and their reading over partial edges: `reply_to on = on` holds only where `reply_to` is defined.

* [ ] **Undirected edges in equations.** An undirected edge has no composition order, so it is open whether it may appear in a path equation, and in which direction it is read there.
