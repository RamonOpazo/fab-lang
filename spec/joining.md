# fAB design decisions, 2026-11-01: the grammar of joining

Decided in the design session of 1 November 2026. This note settles how terms join: what a space does, what `/` does, what pinches do, and where nodes may meet. It replaces parts of [`statements.md`](statements.md) (section 5 and parts of 4 and 7), listed at the end. The spec ([`spec.md`](spec.md), revision of 1 November) was rewritten from this note. The code does not implement it yet. Section 12, an addendum of 2 November, revises null nodes, moves kinds to the right (`f/? +(a, b)`), and makes a space that reaches one branch of several a warning.

Status words as before: **Decided**, **Open**, **Rejected**.

---

## 1. The principles behind it

**Decided.** The user's chain of reasoning, which the rest follows from:

1. Pinching is a visual and type-safe way of declaring a collapse.
2. So pinching is necessary, and so it is mandatory: anonymous ends merge only where a pinch says so.
3. Pinching needs at least one edge, so a single edge can't be pinched on both sides.
4. Nodes are references. A pinched single edge _is_ a reference, so it needs an edge declared before it.
5. Named nodes are free: in principle they are edgeless, and only attaching an edge connects them to the graph.
6. `*` is free by nature, because it is private to one edge end.

And the guiding view of category theory: "CT fixes on the edges, and the nodes can get names later when creating the style, which is actually a label, not a named node. CT is crucially a theory on edges and edge references are more important than node references."

## 2. Space: typed, open

**Decided.**

- **A space writes paths.** It never closes a cycle.
- **A space joins exactly one end to exactly one end.** Every term has a left side and a right side; `f (g, h)` is an error (one against two). Several ends become one only through a pinch: `f +(g, h)`, `(f, g)+ h`.
- **What meets at a space is edges.** Each side is an edge end, possibly already sitting on a node: a pinch, or a named node attached by `/`. So `receive/#Received validate` is a path through Received, and `f ?(a, b)` puts a choice node at cod(f).
- **A node on its own never stands beside a space.** `#A f`, `* f`, `@ (…)`, `k +f` are errors.
- **A space with nothing on one side is an error:** `f/g h` (a cycle exposes nothing on its right), `(f/*) g`.
- **Closed branches are skipped when counting:** `(f/*, g) h` attaches h to g only. A branch ending on a node (`k/+f`) still exposes that node. (Since §12.3, this warns.)

Mathematically: terms are cospans of finite sets; a space is composition along one point (a pushout over a point). "Juxtaposition always merges; fAB has no arities" is replaced by this arity check.

## 3. Slash: attachment and cycles

**Decided.** `/` closes; space stays open.

- **One edge in a chain is attached to the nodes beside it:** `#A/f` (A → N1), `f/#B`, `#A/f/#B`, `+f/g`, `g/f+`, `+f/g/f+`, `*/f`, `f/*`.
- **Two or more edges in a chain form a cycle:** the chain must end where it began. Ending on an edge, that edge closes on the chain's start; ending on a node, that node must be the start.
  - `f/g`: f : N1 → N2, g : N2 → N1.
  - `f/#Z/g`: same as `f/#Z, #Z/g/+f`.
  - `#A/f/#B/g`: same as `#A/f/#B/g/#A`.
  - `f/g/h`: a directed triangle.
  - `#A/f/#B/g/#C`: error, the chain ends away from its start.
- **`f/f` is not a special case.** `f/g` says dom(g) = cod(f) and cod(g) = dom(f); with g = f both say dom(f) = cod(f). "The return path is the same as the go path, with no other option but to share the same node at both ends."
- **`f/` is the undirected edge:** f is its own way back, reversed. The trailing `/` ends a chain of one edge, so the edge may be attached first: `#A/f/`, `#A/f/#B/`, `#A/f/ g/` (amended later the same day). **Amended 6 November:** a trailing `/` makes every edge of its chain undirected, so a cycle may be undirected too: `f/g/` is an undirected two-cycle, `f/g/h/` an undirected triangle, `#A/f/#B/g/` the same through named nodes. The old reading, `f/ g/f+/`, is a loop, not a cycle. A mixed cycle names its nodes: `#A/f/#B/, #B/g/#A`.
- **A cycle closes on its start.** It exposes that node on its left and nothing on its right (amended later the same day). So `h f/g` is legal, and a pinch gathers a cycle by its start: in `f ?(b/b, e)`, b : ◇ → ◇ loops on the decision, and in `charge ?(paid, declined/#Waiting/retry)`, retry closes on the payment decision. To continue from another node, use a comma and a reference: `f/g, f+/h`.
- **The pair is a cycle:** `+f/α/g+/β` at level 1, `f/α/g/β` at level 2. `+f/α β/g+` is, by precedence, `(+f/α) (β/g+)`: a path through a fresh node. At level 2, `f/α β/g` is an error (it needs an anonymous 1-cell). Vertical composition is two attachments: `f/α/g, g/β/h`.
- **`/` distributes over groups:** `#X/(g1, f, g2)`, `f+/(p1/g1+, p2/g2+)`, `F/(α, β)/G`, `(#Main/merge, #Feature/merge')/#Merged`. Every branch lands on a written node, so no anonymous ends merge and no pinch is needed. Gluing to a node distributes over coproducts. "It looks like a structure for distribution."
- **Two notations for one graph are fine:** `+(f, g)+` and `f, +f/g/f+`; `a/#N b` and `a #N/b`. "The grammar is not ambiguous here, it just allows two notations, and the two notations center the focus on different things for the author."

## 4. Nodes

**Decided.**

- **Every node term takes a slash:** `#A`, `@`, diagram names, `+f`, `f+`, `*`. "Any node reference, either named node or edge pinching side, requires a slash. The former is made so it aligns with the necessity of the latter."
- **Free nodes:** named nodes, `@` and diagram names need nothing before them; references need their edge declared earlier.
- **`*` is a fresh node private to one end:** `*/f`, `close/*`. Replaces the 23 October form `* f` (written alone). `*/(f, g)`, `(f, g)/*`, `f/* g` are errors.
- **`@` behaves like `*` in taking a slash,** but is shared: `User :: @/(id/T.#UUID7, …)`.
- **Diagram names likewise:** `Membership/(member/User, within/Organization)`.
- **A node continues a flow with a space;** this holds for references too: `g/+f h` continues from dom(f). The 23 October rule "a reference closes the side it is on" (goto) is dropped.
- **Named nodes are states:** always plain, never a decision or a bar. "A node cannot connect directly to a <>, it needs an edge." Decisions and bars are anonymous and labelled through their canonical ends (`validate+ :label "Valid?"`).
- **Lone nodes** may stand as a whole branch: `T :: #UUID7, #DTZ`.

## 5. Pinching

**Decided.**

- **A pinch is the only collapse of anonymous ends.**
- **`?` and `!` are `+` with a kind,** prefix or postfix on groups: `f ?(a, b)`, `(a, b)? k`, `!(…)`, `(…)!`. Replaces "postfix only".
- **A pinched single edge is a reference node:** `+f`, `f+`, `+(f) = +f`. It needs its edge declared, so `f? (g, h)` with f new is an error; the decision is `f ?(g, h)`. It has one side: `+f+`, `+(f)+` are errors. `?` and `!` never touch a single edge.
- **A marker touching both sides is an error:** `f?(g, h)`, `(a, b)!(c, d)`.
- **A pinch with several branches declares them,** and the first branch names the pinched nodes (unchanged).

## 6. Where nodes meet

**Decided.** When a space joins two sides, the node carries what each side brings:

| Side                                                 | Brings                        |
| ---------------------------------------------------- | ----------------------------- |
| a free end, a `+` pinch                              | nothing                       |
| a `?` or `!` pinch                                   | its kind                      |
| an end attached to a named node, `@`, a diagram name | that name, and the kind plain |
| an end attached to `*`                               | null, which meets nothing     |

> At most one name, and kinds that agree.

```fab
(a, b)+ +(c, d)              // a bowtie: correct "and it is beautiful"
(a, b)! !(c, d)              // one bar that joins and forks
(a, b)! ?(c, d)              // error: kinds disagree
validate/#Valid +(yes, no)   // legal: a fan out of Valid
validate/#Valid ?(yes, no)   // error: plain against choice
a/#A #B/b                    // error: two names
```

Two nodes meeting at a space (a pinch with a pinch, a name with a pinch) is not an exception: "it follows from first principles". Mathematically the labels form a partial commutative monoid with "nothing" as the unit; a meeting is defined exactly when the join is.

## 7. Examples under the new grammar

```fab
Sq   :: +(f h, g k)+
Tri  :: +(f g, h)+
Iso  :: f/g
Endo :: f/f
Und  :: f/
Cyc  :: f/g/h
Pair :: +(f, g)+                            // with names: #A/(f, g)/#B
Nat  :: +(f, g)+ | f/α/g
Eq   :: +(f, g)+ | f/α/g/β
Mod  :: +(F, G)+ | F/(α, β)/G | α/m/β
Pr   :: #X/(g1, f, g2), f+/(p1/g1+, p2/g2+)
W    :: +(f h, k, g)+ | k/α/g

If    :: f ?(fg g, fh h)? k
While :: f ?(b/b, e) k
Exit  :: f ?(fg g/*, fh h) k
Par   :: */s !(a, b)! t/*

Order :: */receive/#Received validate ?(
    yes/#Accepted fork !(
        charge ?(paid, declined/#Waiting/retry)
      , reserve ?(reserved, short/#Backorder/restock)
    )! ready/#Ready ship/#Shipped close/*
  , no/#Rejected notify/*
)
```

`declined/#Waiting/retry` is a cycle: retry closes on the payment decision with no reference needed.

Comparison with the 23 October forms: the category-theory core (squares, triangles, pairs, cones, 2-cells) is unchanged, because it was already built from pinches. What changes is anything with named objects (a slash at each attachment), the 2-cell pair (`f/α/g/β`), and the shortcuts around pinching (`e (f, g)+`, `(f, g)+ q`, `#X (…)`).

## 8. Rejected

- **Redundant pinches being fine** (23 October, evening): replaced by the mandatory pinch, with a principled reason this time: a pinch declares a collapse.
- **The first mandatory-pinch proposal** (23 October): rejected then for its look (`f ? +(g, h)`). Accepted now together with prefix `?(…)` and `!(…)`, which removes the ugly forms.
- **A second operator for open chains** (`-`, `>`, `\`): keeping only `/` and using space for open structure is enough. `-` would also have taken hyphens from edge names, `:` clashes with attributes, `//` with comments, `~` with `~=`.
- **A closing mark at the end of a chain** (a trailing `/` or `<`): unnecessary once `/` is always closed and space always open; it would also have taken `f/` from undirected edges.
- **Pair spelled `+f/α β/g+`**: by precedence it is a path through a fresh node; reading it as "there and back" would give space a second meaning.
- **Nameless edges:** "cannot be a thing, because the grammar is made such that it reflects CT strictness: edges are the only known thing."

## 9. What this replaces in the 23 October note

| 23 October                                      | Now                                               |
| ----------------------------------------------- | ------------------------------------------------- |
| Juxtaposition always merges; fAB has no arities | A space joins one end to one end                  |
| Redundant pinches are fine                      | A pinch is required to merge anonymous ends       |
| `f? (g, h)` declares f                          | `f ?(g, h)`; a pinched single edge is a reference |
| `?` and `!` postfix only                        | Prefix or postfix, on groups only                 |
| The pair `f/α/β/g`, `+f/m/n/g+`                 | `f/α/g/β`, `+f/m/g+/n`                            |
| Warning: straight back `f/a/g/b/f`              | Gone: that is the pair, closed explicitly         |
| Error: three new names between sides            | Replaced by "a cycle must close"                  |
| Vertical composition `f/α/g/β/h`                | `f/α/g, g/β/h`                                    |
| `*` written alone (`* f`)                       | `*/f`, `f/*`                                      |
| A reference closes its side (goto)              | A node continues with a space                     |
| `#A f g #C`, `#X (…)`, `@ (…)`                  | `#A/f g/#C`, `#X/(…)`, `@/(…)`                    |
| Named choice and parallel nodes (`#Valid?`)     | Named nodes are plain; decisions are anonymous    |
| `/` distributes "as juxtaposition does"         | Only `/` distributes; a space never does          |

## 10. Open

- **Patterns of edges,** such as `f +(3/g)` for g1, g2, g3: a convenience, not decided. If it comes, `3/g` reads like a slash chain, so it may want another spelling.
- Everything listed as open on 23 October that this note doesn't touch (declaring nodes and edges, the `:prove` layer, schemas, `:place`, the header).

## 11. Plan

Unchanged in order: the grammar in fab-core (lexer, parser, analyser) follows the spec, now including the arity check, the cycle rule, the label join for meeting nodes, and node terms with slashes.

---

## 12. Addendum, 2 November: sorts, null nodes and kinds on the right

Decided while designing the analyser's rule 1 (plan step 5.1), which gives every term a sort: a **node** (`#A`, `@`, `*`, a diagram name, a reference `+f`, `f+`) or **edges** (everything else). Writing that rule down showed where the 1 November wording ranked one error above another badly, and led to one change of syntax: kinds are written on the right.

### 12.1 Null nodes

**Decided.**

- **`*` exposes nothing.** So `f/* g` is "nothing to join", the same error as `(f/*) g`; the group changes nothing, since `/` binds tighter than a space. It leaves the `*` row, and the null label leaves the meeting table: a null node never meets anything.
- **`*` holds exactly one end,** never none and never several. The row is renamed "`*` not on exactly one end": a lone `*` holds none; `f/*/g`, `*/f/g` (in a cycle) and `*/(f, g)` hold several. Whether the side beside `*` holds one end is counted with the interfaces, so `*/+(f, g)` is caught too.

### 12.2 Kinds on the right

**Decided.** The user: "the left side `?` bugs me"; and then two constraints that decide the syntax in one stroke.

1. **`?` and `!` only on the right; `+` on either side.** `+` is structural (the bowtie, the square) and keeps both sides: `+(a, b)`, `(a, b)+`, and the references `+f`, `f+`. `?` and `!` are flow, which has a direction: a kind is written where flow arrives.
2. **`?` and `!` are node terms, after a single edge only.** `f/?` ends f at a fresh choice node; `f/!` at a fresh bar. After a group, the kind is the postfix pinch: `(a, b)?`, `(a, b)!`.

| Construct                  | Written             | Was                 |
| -------------------------- | ------------------- | ------------------- |
| Decision                   | `f/? +(a, b)`       | `f ?(a, b)`         |
| Merge                      | `(a, b)? k`         | unchanged           |
| Fork                       | `f/! +(a, b)`       | `f !(a, b)`         |
| Join                       | `(a, b)! k`         | unchanged           |
| One bar that joins and forks | `(a, b)! +(c, d)` | `(a, b)! !(c, d)`   |
| A loop on a decision       | `f/? +(b/b, e) k`   | `f ?(b/b, e) k`     |

Consequences:

- **One spelling for each construct.** `f/?(a, b)`, `?/(a, b)` and `(a, b)/?` are not alternatives: the first two put a kind on the left, the third after a group.
- **Kind and collapse are separate.** A pinch collapses ends; a kind is a label of a node, as a name is, set where the node is created. So the branches of a decision may be written as separate items: `G :: f/?, f+/a, f+/b`.
- **`f/?`, not `f?`.** `f+` is a reference to an existing node, so `f?` would change the kind of a node that exists. `f/?` creates the node. `f?` stays an error, with the hint `f/?`; so does `A.f/?`, which would change another diagram's node.
- **Where a kind may stand.** As a node term, `?` or `!` is the last element of a closed chain, right after a single edge: `f/?`, `#A/f/?`, `*/s/!`. `f/?/g` and `?/f` put it on the left; a lone `?` holds no end.
- **Its errors say which rule is broken:** a kind on the left (`?/f`, `f/?/g`), closing a cycle (`f/g/?`, which would put it on the left of f), lone (`?`), on a reference (`f?`), after a group (`(a, b)/?`). A group of one is its item, so `(f)/?` is allowed, with a warning.
- **Kinds meet less.** At a space only the left term's right side can bring a kind, so two kinds meet only through a pinch of kinded branches, `(a/?, b/!)+`, and a kind meets a name as in `f/? #A/g`.
- **Not a node term: `+`.** `f/+` would be `f`, and `+/f` would read like the reference `+f` and mean something else: "redundant and confusing".

### 12.3 A space that reaches one branch of several

**Decided.** Skipping closed branches stays: `(f/*, g) h` is valid and attaches h to g only. So is a lone node in a group, `(f, #A) g`: it exposes nothing on either side, and a discrete piece beside a path is a correct diagram. But both read as if the space joined the group, so they **warn**, with the clearer spelling as the hint.

- **The rule.** A space warns when one of its sides is a group's side with several branches, unpinched, where every branch but one exposes nothing: a stop, a cycle's right side, a lone node. The space really joins that one branch, so the step belongs inside it.
- **The rewrites.** `(f/*, g) h` is `f/*, g h`; `(f, #A) g` is `f g, #A`; `f/? +(b/b, e) k` is `f/? +(b/b, e k)`. The spec's `While` and `Exit` examples are rewritten so.
- **A pinch is quiet here.** In `(a, b/b)! k` the pinch gathers the branches into one node first, so the space joins that node, not a branch. The pinch itself gathers one end only, and warns as a pinch of one end (rule 4): `a/! k, b/b`. A pinch of nothing is an error.
- **An interface check.** It needs the count of branches on a side, so it belongs with the arity errors (`ends_dont_match`, `nothing_to_join`), not with sorts. A side with a hole in it is unknown, and stays quiet.

**Rejected.** A lone node in a group as an error ("isolated nodes join nothing"): the ontology says it is a correct diagram, so the language warns instead of refusing.

### 12.4 Rejected

- **Markers on groups as `/` to an anonymous node** (`?(a, b)` = `?/(a, b)`): coherent, but it gave a decision four spellings. With kinds on the right, the pinch stays a primitive.
- **`+` as a node term,** for the reasons above.
