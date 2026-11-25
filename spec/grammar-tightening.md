# Tightening the grammar, 2026-11-20 (revised 2026-11-25)

A refinement of `spec.md` toward a tighter grammar: fewer sorts, sigils that each do one thing, punctuation that only builds the tree, and one way to describe anything. The graph calculus was sound, but the rest of the language grew beside it as a parallel syntax:

- four sub-languages (terms, brackets, types, records) used the same symbols with different meanings;
- `:` marked types, descriptors and the three statements, and the zone was a sort beside the node;
- `!` meant a parallel node in terms and a twin elsewhere;
- braces meant a table and also "keep reading past the line end";
- subjects came before descriptors, with a distribution rule of their own.

This document holds **what is settled**, and lists at the end what is still open. `spec.md` stays the truth until a part of this one is folded into it, with its decision note. The examples in this syntax are `examples/.r2-*.fab`, the prelude among them (`.r2-prelude.fab`, still being polished). They are dotfiles, so `make examples` skips them.

## 1. Names by shape

| Shape          | Is                                                     | Example                       |
| -------------- | ------------------------------------------------------ | ----------------------------- |
| `PascalCase`   | a node in a graph; a type in a type position           | `User`, `Label`               |
| `kebab-case`   | an edge                                                | `writer`, `commit1`           |
| `&kebab-case`  | a class: a set of a program's elements                 | `&edge`, `&choice`            |
| `key:`         | a key taking arguments                                 | `label:`, `axiom/pk:`         |
| `key/`         | a key opening a block of keys                          | `style/`, `proof/`            |
| `.x`           | an element of the description's owner; `.` the owner   | `.User`, `.(user \| org)`     |
| `@X`           | a node from the root                                   | `@T.UUID7`, `@Db`             |
| `[x]`          | a value: a named value, a label, a literal             | `[muted]`, `[0..*/1]`, `[>]`  |
| `"…"`, `$…$`   | text, math                                             | `"users"`                     |

- **The lexer reads shapes, not sorts.** `PASCAL` (upper case first) and `KEBAB` (lower case, `_` or non-ASCII first) share one name body (letters, digits, `_`, `'`, non-ASCII, `-`). Sigils are symbols touching a name. The parser and the analyser give the sorts.
- **Nodes and types share PascalCase, in separate namespaces chosen by position.** A graph term holds nodes, and a type position holds types. In a description, an element is always written with `.`, so a bare `PascalCase` there is a type. `T := …, Text, …` makes a node Text; `@T.Text` is not the type `Text`.
- **A case mistake is a name error,** reported where the name is (*no node `user`*), not a lexing failure.
- **`#` is gone.** Named nodes are bare.

## 2. Statements

| Statement           | Says                                                       |
| ------------------- | ---------------------------------------------------------- |
| `G := …`            | defines a node by its inside                               |
| `[x] :: T := v`     | defines a value of type T                                  |
| `[x] :: T`          | declares a value of T, bound later: a token                |
| `T :: { … }`        | defines a type, once                                       |
| `@X :> …`           | describes X                                                |
| `&c :> …`           | describes every element of the class &c: the defaults      |
| `&c/key: [v] :> …`  | a case: describes the elements of &c whose key is [v]      |

- **`:=` defines, `::` types, `:>` describes.** A node is a value of the graph, so it is defined with `:=`, as a named value is. `::` is the judgement "belongs to": a value to its type, or a type to the new set its braces make (§9). `:>` reads "then".
- **Every statement starts its line, and its operator is loose:** `G := f`, never `G:=f`. A key's colon touches its name, so `f::` would lex as `f:` and `:`.
- **A body is indented under its head** when it spans lines (§5).

## 3. Graphs

### 3.1 Nodes and edges

- **A graph has two sorts, nodes and edges, both bare.** `A/f/B` is f : A → B.
- **There is no zone sort. A node may have an inside, and an edge never has one.** In category theory an object may itself be a category, given by a presentation or not. Cells lie between edges, never in them.
- **Defining a node gives it its inside,** at any depth. `G := f g` is the node G with the inside `f g`, and `G.A := x y` gives G's inner A its own. Defining an edge stays reserved.
- **An edge between nodes with insides is a morphism between them,** a functor where they are categories. Its action is unstated, as an edge's always is.

### 3.2 Scope and `@`

- **A bare name binds in the node being defined,** made at its first use. `G` inside G is another node, G's own.
- **`@` references from the root, and never creates:** `@G`, `@G.A`, `@G.A.B`. Paths go down with `.`, so `@G.A` is the same node wherever it is written.
- **`@` may reference forward:** `Repo := @Main, @FeatOne` before Main is defined. A bare name never does.
- **A node is never inside itself.** `@G` inside G is an error, and so is a cycle of members through forward references (`A := @B`, `B := @A`): containment is a tree.

### 3.3 Members, and reaching in

- **`@G`, a whole node, is a member** of the node that names it: its own node, standing for G, drawn inside the first node that names it.
- **`@G.A`, a part, stays G's.** The container only reaches it.
- **No node writes into another's inside.** Every edge of K has an end on K's own nodes, members included.

| Written                                    |                                                      |
| ------------------------------------------ | ---------------------------------------------------- |
| `Db := Membership/user/User`               | Db's own nodes; `Db.User := *(id/@T.UUID7, …)` gives User its inside |
| `FeatOne := (@Main.commit2+)/commit1 …`    | commit1 starts in Main and runs on in FeatOne        |
| `K := @G.A/f/@G.B`                         | error: an edge between G's parts, declared outside G |

Parentheses around a reference, `(@Main.commit2+)`, change nothing: they show where the node is.

### 3.4 Levels

A level is a whole graph read against the level before it, one dimension up: its new names are cells, its sides names of the level below. `|` puts the levels together (§4):

```
Nat := +(f, g)+ | f/α/g
Mod := +(f, g)+ | f/(α, β)/g | α/m/β
```

## 4. Punctuation

Punctuation builds the tree and computes nothing: `( )`, `[ ]`, `{ }`, `,`, `|`, `/`, `.` and the space.

| Separator | Spacing | Relation                                                        |
| --------- | ------- | --------------------------------------------------------------- |
| `/`       | tight   | a train: in order, each touching the next                       |
| `.`       | tight   | a path: a part of its container                                 |
| `,`       | loose   | beside: a sum, each part on its own                             |
| `\|`      | loose   | together: one whole of ordered parts                            |
| the space | loose   | then: through something new, composition; between arguments, the next |

- **`/` keeps one meaning: in order, tight.** It is a train in a graph, a tuple in a bracket (`[/dashed/>]`), and a path of keys in a description (`proof/axiom/pk:`), since a key path is a train of morphisms out of the subject.
- **`,` is beside and `|` together.** Anything applied distributes over `,` and never over `|`.
  - In a graph, `|` holds the levels: the i-th part is level i, each read against the one before, so the cells go deeper.
  - In a description, `.(user | org)` is one subject made of two edges, as a key sees it.
  - `|` is ordered everywhere; a key may ignore the order.
- **A context holds what its spacing admits.** A bracket is one token with no spaces, so it holds trains and never a sum. `( )` and `{ }` are loose.
- **`/` attaches nodes that exist** (named, `@`, references to ends) and closes cycles. Markers attach by touching (§6).
- **A group distributes under every tight separator, under description, and over the arguments of a key:**
  - `A/(f, g)` is `A/f, A/g`, and `(f, g)/B` is `f/B, g/B`;
  - `@G.(A, B)` is `@G.A, @G.B`, and `.(f h)` is `.f .h`;
  - `label: (.yes, .paid) "yes"` is two entries;
  - `fill: (&node, &zone) Color?` is two declarations.

## 5. Lines and blocks

- **A body spanning lines is indented under its head,** Python's way: no braces around a body.
- **Inside `( )`, `{ }` and `[ ]`, indentation and line ends are ignored,** so a group may span lines freely.
- **A graph's body reads as if its line ends did not exist:** its lines are joined by the commas they always had.

  ```
  Db :=
      Membership/(user/User, org/Organization),
      Project/owner/Organization
  ```

- **In a description, and in a record type's braces, a `key:` entry is one line.** The next line starting with a key is the next entry, so entries need no separators.

## 6. Markers

A marker pinches the ends it touches into one node of its kind.

| Marker | Touches     | The node is | Examples                         |
| ------ | ----------- | ----------- | -------------------------------- |
| `+`    | either side | plain       | `+(f, g)`, `(f, g)+`, `+f/g`     |
| `*`    | either side | null        | `*init`, `close*`, `*(id/…, …)`  |
| `?`    | the right   | a choice    | `f? +(a, b)`, `+(…)?`            |
| `!`    | the right   | parallel    | `f! +(a, b)`, `+(…)!`            |

- **`?` and `!` are pure postfixes, and never reference.** `f/? +(a, b)` is now `f? +(a, b)`, and a lone `?` or `!` goes.
- **`*` touches, as `+` does.** Each `*` is one node: `*(f, g)` starts f and g at the same null node. One edge may carry a marker on each side: `*s! +(a, b)! t*`.
- **The graph's `?` and `!` are not the data's.** In a type, `T?` is "or nothing" and `T!` adds the twins (§9). In a value, `!` is the twin. The contexts never share a position, and they are different nodes in the CST.
- **Operators touch what they change.** Statements and the relations (`==`, `~=`) are loose.

## 7. Canonical references

- **`+` alone makes canonical references,** since a pinch is always one node.
- **A node's starts are principal,** since reading goes left to right: `+f`, or `+(a, m)` when several edges start there, in reading order. A node where no edge starts is named by its ends: `f+`, or `(b, n)+`.
  - In `f g` the middle node is `+g` (today `f+`).
  - In `+(a b, m n)`: `+(a, m)`, `+b`, `+n`, `b+`, `n+`.
  - In `(a b, m n)+`: `+a`, `+m`, `+b`, `+n`, `(b, n)+`.
- **In a term, any end reaches its node.** Canonical references are what descriptions must use, as today: `@Main.commit2+` reaches the node canonically `+commit3`.

## 8. Classes

A class is a set of a program's elements. Classes are built in, given by the program's structure, and never declared:

| Class        | Covers                                                          |
| ------------ | --------------------------------------------------------------- |
| `&node`      | a node without an inside                                        |
| `&zone`      | a node with an inside                                           |
| `&edge`      | an edge                                                         |
| `&cell`      | a cell, level 2 and above                                       |
| `&canonical` | a node named by its ends                                        |

- **The kinds lie inside `&node`:** `&plain`, `&choice`, `&parallel`, `&start`, `&end`, `&hole`. A node with an inside is named, so plain.
- **Which class an element is in follows from the program:** a node has an inside exactly when it is defined. No one writes the class.
- **A zone may be drawn as a node** (`style/as: [node]`): its class says what it is, its style how it looks.
- **Class and type are kept apart:** a class holds elements, a type holds values. A key's subject slot takes a class, and its value slots take types (§10).

## 9. Types

A type is a set of values, as in set theory.

- **Braces make a new set, partitioned into its entries.** A value is a block of one, and a type a block of its values. So `{ … }` is the sum of its entries as a new set, which is what `,` means in a graph.

  ```
  Line   :: { [solid], [dashed], [dotted], [double], [triple], [wavy] }
  Facing :: { [outer], [inner] }
  Side   :: { Facing, On }        // [outer] is a Side through Facing
  Length :: { Number }            // a new set: a length is no angle
  Angle  :: { Number! }
  ```

- **A value belongs to exactly one braced set.** Words two types share get a type of their own, which both hold (Facing).
- **A type is defined once.** Repeating a definition is *defined twice*, and nothing adds to a type later.
- **Outside braces, a type expression makes no new set.** These appear in slots and are never a definition's body:
  - `A, B` is a union, `[A/B]` a tuple, and `A | B` the values together;
  - `T?` is T or nothing (`T, Nil`), so `Nil` is rarely written;
  - `T!` adds T's twins (`[30!]`, `[?!]`);
  - `T*` marks a key that takes many entries (§10).
- **Values are typed by `::`.** `[pink] :: Color := [#bf3989]` defines one. `[ink] :: Color`, with no value, declares a token, bound by a style (`[ink] := [#333333]`). The groups distribute: `[ink], [soft] :: Color`.
- **A record type's braces hold keys, never values** (§10). A type holds values or keys, never both.
- **Built in:** `Text` `"…"`, `Math` `$…$`, `Color` `[#…]`, `Number` `[2]` `[0.5]`, `Range` `[0..*]`, `Nil` `[]`, `Equation` (`a == b`, `a ~= b`).

## 10. Keys

A key is declared in a record type's braces, with its subject's class first, then the types of its slots:

```
Style :: {
    label: (&node, &zone, &edge, &cell) Label?   // on an element, a label
    hide:  (&node, &edge, &cell)                 // a class only: a flag
}
Proof :: {
    axiom: Proposition*                          // a type only: the owner's own key
}
```

- **A flag is a key with a subject only,** true when written. `Flag` as a type goes.
- **A key without a subject class is the owner's own:** `style:`, `axiom:`.
- **A key's declaration is told by where it is,** inside a type's braces. Anywhere else a key is used.
- **Each `key:` is a new entry.** A key typed `T*` takes many entries, each one adding. Otherwise a later entry for the same subject replaces the earlier one. Entries are not keyed: `axiom.[a]` goes.
- **A use gives the arguments in order, separated by spaces:** the subject, then the values. `label: .User "users"`.
  - The subject may be left out, and is then the owner: `label: "users"`, `style: [dark]`. It is decidable by shape, since a subject is a class (`&edge`), an element (`.x`), or a group of those, and a value never is.
  - An argument with a space in it is grouped: `.(parent document)`.
  - An equation runs to the line's end: `axiom: .(fix merge) == .(login session merge')`.
- **Keys nest, by `/`.** `style/label: .Received "Order received"` is the one-line form of a `style/` block holding the entry. A path ending in `/` opens a block, and the flat form and the block are one entry. This is the same law as `G.A :=` against defining inside G.
- **A key nested in another specifies the outer one's entry.** `axiom/pk: &zone.id` is one axiom whose proposition is `pk:`. An `axiom/` block holding several keys is one axiom stating them all.
- **Tables compose by juxtaposition, the later one overriding** what both bind and adding the rest. `style: [dark]` then entries is `[dark]` with the entries written over it. A named table is a value of its record type: `[dark] :: Style :=` and an indented block.

## 11. Descriptions and layers

`@X :>` opens X's description, an indented block whose top keys are the layers:

```
@Order :>
    class: [flow]
    style: [dark]
    style/label: .validate+ "Valid?"
    style/arrow: (.retry, .restock) [/dashed/>]
```

- **The layers are keys on zones,** declared once in the prelude as a record type: `class: &zone Kind`, `style: &zone Style`, `place: &zone Place`, `proof: &zone Proof`.
- **A layer is a key whose type holds keys.** Layers are not a syntax of their own: `layer@`, `:style { … }` and braces around a layer go.
- **`.` marks the owner's elements:** `.User`, `.writer`, `.(user | org)`. A bare kebab name in a description is always a key, so `.Tag.label` (a column) and `label:` (a key) never clash.
- **`&c :>` describes every element of a class.** `&zone :>` holds the defaults, which `[base]` was: the prelude binds every key for every class there, the place defaults (`grid: [4]`, `metric: [1]`, `flow: [S]`) included.
- **A case, `&zone/class: [flow] :>`, describes the zones whose `class:` is `[flow]`,** and passes down to the diagrams they hold.
- **The cascade reads in order of narrowing:**

  ```
  computed < &zone :> < the kind's case < the tables composed < @X :>
  ```

- **Proofs are a layer like the others.** `axiom:` and `lemma:` each take many propositions. A proposition is an equation, or a fact its kind declares (`pk:`, `reachable:`, `pushout:`), each kind's facts a record type of their own. Axioms are stated, and lemmas checked against the axioms and the lemmas before them.

## 12. Examples

```
T := UUID7, DTZ, String, Text, JSONB, Bool

Db :=
    Membership/(user/User, org/Organization),
    Comment/(document/Document, writer/User, parent/Comment)

Db.User    := *(id/@T.UUID7, email/@T.String, nick/@T.String)
Db.Comment := *(id/@T.UUID7, text/@T.Text)

@Db :>
    class: [schema]
    style/
        label: .writer "author_id"
        label: .User   "users"
    proof/
        axiom: .(parent document) == .document
        axiom/pk: &zone.id
        axiom/
            uk: .User.(email | nick)
            uk: .(user | org)

Order :=
    *receive/Received validate? +(
        yes/Accepted ready/Ready close*,
        no/Rejected notify*
    )

Repo    := @Main, @FeatOne
Main    := *init commit1 commit2 commit3
FeatOne := (@Main.commit2+)/commit1 commit2
```

## Open

**The graph**
1. **A name and the canonical reference:** does a name replace it, or alias it with both valid? Today referring to a named node by an end is an error.
2. **Partial references:** does `+a` still reach the node `+(a, m)`? In a term, `+(a, m)` with a and m already declared must be a reference where their starts already meet, not a new pinch. Where they don't meet, it is an error, or a gluing.

**Lines**

3. **Tabs in indentation:** forbidden, or counted.

**Classes**

4. **`&element`, every element.** Without it, the prelude writes `(&node, &zone, &edge, &cell)` about fifteen times.
5. **Where further classes come from:** η's findings (`&refutable`, `&undecidable`), flow's `&dead-end`. Are classes only the built-in ones plus what a layer produces, or can a program declare them?
6. **The key `class:` holds a Kind, not a class.** Either rename it `kind:`, or make kinds classes: `class: &schema`, with a case being `&schema :>`.
7. **A class with a path:** `&zone.id` is every zone's part `id`. How far does a class reach: the owner's own elements, or the insides of its zones too (`.&edge` against `&edge`)?

**Types**

8. **Braces mean two things:** a sum of values and types, or a record of keys. "Never both" keeps them apart.
9. **The width of `|` in a type:** `uk:` takes one column or several together (`(&edge, &edge | &edge)` stops at two).
10. **Lists:** `metric:` was `[1/2/3]`, and the flow's bearings came in any number.

**Keys and descriptions**

11. **Admitting a kind's facts.** `axiom: (Equation, FlowFact)` reads as an entry of a key typed `*`, which would add to the default rather than replace it. Admission may need the typing judgement instead: `proof/axiom :: Equation, FlowFact`.
12. **Tokens bound inside a table:** `[ink] := [#333333]` is a statement inside a description.
13. **Element bundles:** git-history's `:ref` became a group. A named table composed onto an element would need `style:` on more than `&zone`.
14. **Entries without keys:** a failed lemma is reported by its line, not its name.
15. **`Layer`, the type of a description's top,** is a name the language must know. It could later admit `&node` too.
