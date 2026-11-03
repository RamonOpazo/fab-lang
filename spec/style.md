# fAB `:style`: the complete vocabulary, 2026-10-23

Decided in the design session of 23 October 2026. This document formalizes the `:style` layer: every attribute, which subjects it applies to, its values and its default, plus the arrow grammar and themes. It builds on the general decisions in [`statements.md`](statements.md) (statements, values, subjects and classes), which it assumes. Its example (section 11) predates the grammar of joining ([`joining.md`](joining.md)); the spec's own example is current.

Status words: **Decided**, **Open**, **Rejected** (with the reason).

---

## 1. Principles

**Decided.**

1. **`:style` describes how things look, never where they are or what they mean.** Position belongs to `:place`; facts belong to `:prove`. "Else-branches, probabilities and guards are meaning, not appearance."
2. **`:style` is non-relational.** A style value describes one element and never names another element. (`:order [g1,f,g2]` or `:right-of` would name structure; such statements belong to `:place`.)
3. **`:style` is direction-agnostic.** No attribute or value refers to a direction on the page (up, down, left, right, horizontal, vertical). Everything is relative to the element itself, to its text, or to the diagram's own shape. A diagram can be laid out flowing towards any cardinal point and every style still means the same.
4. **One word per concept, no shared words.** Text attributes (`:font`, `:face`, `:size`, `:ink`) and line attributes (`:pen`, `:stroke`, `:arrow`, `:line`) never borrow each other's words. Line words are shared on purpose: `:line` on nodes and the line of an arrow use the same vocabulary.
5. **Values are never bare:** `"…"`, `$…$` or `[…]`, except flags, which take no value.
6. **Bindings follow the general rules:** each (subject, attribute) pair is bound once within a layer; overlapping subjects are resolved by specificity (section 2.3); layers compose in order (section 7); definitions come before use.
7. **Renderer limits are not part of this spec.** It says what a style _is_. How a backend approximates something it cannot draw (DOT has no wavy lines) is the transpiler's job, reported with a note.

---

## 2. Subjects

### 2.1 What can be styled

| Subject                      | Written                         | Example                                              |
| ---------------------------- | ------------------------------- | ---------------------------------------------------- |
| a zone                       | its name                        | `G :style := { … }`                                  |
| an edge or a cell            | its name, qualified by its zone | `G.f :stroke := [red]`                               |
| a node, by its canonical end | `+f`, `f+`                      | `G.+f :label := $P$`                                 |
| a named node                 | `#Name`                         | `G.#Done :shape := [box]`                            |
| a class                      | `&name`                         | `&node :shape := [circle]`, `G.&edge :pen := [thin]` |

Inside a block, the owner's prefix is factored out: `G :style := { f :stroke [red] }` binds `G.f :stroke`.

### 2.2 Built-in classes

| Class        | Covers                                                                    |
| ------------ | ------------------------------------------------------------------------- |
| `&node`      | every node                                                                |
| `&plain`     | plain nodes                                                               |
| `&choice`    | choice nodes (`?`)                                                        |
| `&parallel`  | parallel nodes (`!`)                                                      |
| `&start`     | null nodes no edge arrives at                                             |
| `&end`       | null nodes some edge arrives at                                           |
| `&hole`      | nodes left by analysis errors                                             |
| `&canonical` | nodes labelled by their canonical end (a cross-cutting class, not a kind) |
| `&edge`      | 1-cells                                                                   |
| `&cell`      | 2-cells and above                                                         |
| `&zone`      | diagrams, standalone or drawn inside another                              |

The node kinds partition `&node`: every node is in exactly one of `&plain`, `&choice`, `&parallel`, `&start`, `&end`, `&hole`. `&canonical` cuts across them. The by-kind classes replace the spec's `.junction` and `.null`.

### 2.3 Specificity

From general to narrow; a narrower subject wins where subjects overlap:

1. a class (`&node`)
2. a narrower class (`&choice`, `&canonical`)
3. a class inside a zone (`G.&node`)
4. a single element (`G.+f`, `G.#Done`, `G.f`)
   Specificity orders bindings _within_ a layer. Layers (base theme, themes, the program) compose on top of that (section 7).

**Open.** When two classes of the same specificity overlap (`&choice` and `&canonical` on one node) and set the same attribute, which wins: an error, or a fixed precedence (kind classes below `&canonical`)? The current formatter applies `&canonical` over kind defaults.

---

## 3. Value types

| Type     | Written                                                                                                | Notes                                                     |
| -------- | ------------------------------------------------------------------------------------------------------ | --------------------------------------------------------- |
| text     | `"…"`                                                                                                  | inline math allowed: `"x = $\alpha$"`; `\n` breaks a line |
| math     | `$…$`                                                                                                  | LaTeX                                                     |
| colour   | `[#c0392b]`, `[#f00]`, a prelude name (`[red]`), a theme token (`[ink]` `[soft]` `[muted]` `[accent]`) |                                                           |
| number   | `[2]`, `[0.5]`, `[30]`                                                                                 | never negative (3.2)                                      |
| length   | a number, in **em**                                                                                    | relative to the theme's text size                         |
| angle    | a number, in **degrees**                                                                               | `!` for the inner side: `[30!]`                           |
| fraction | a number from `0` to `1`                                                                               | a position along an edge                                  |
| keyword  | `[dashed]`, `[italic]`, `[outer]`, …                                                                   | from the prelude; each attribute lists its own            |
| arrow    | `[tail/line/head]`                                                                                     | section 4.6                                               |
| theme    | `[dark]`, or several: `[dark,compact]`                                                                 | section 7                                                 |
| flag     | no value                                                                                               | `:hide`                                                   |

### 3.1 How a bracket is read

**Decided.** One rule, by shape, decides what a bracket holds. It refines the names-versus-literals rule of the general decisions:

| Bracket                            | Is                           | Examples                                        |
| ---------------------------------- | ---------------------------- | ----------------------------------------------- |
| contains exactly two `/`           | an arrow                     | `[/solid/>]`, `[?/solid/>]`, `[>/wavy/X]`       |
| starts with a **lowercase** letter | a name                       | `[red]`, `[circle]`, `[warn-bg]`, `[epi]`       |
| starts with `#`                    | a colour                     | `[#c0392b]`                                     |
| starts with a digit                | a number; with `..`, a range | `[2]`, `[30]`, `[30!]`, `[0..*]`, `[0..*/1..1]` |

- **Names start with a lowercase letter.** So uppercase glyphs such as `O` and `X` can never be mistaken for names.
- **Two slashes identify an arrow,** whatever its first character. Ranges contain one `/` at most, and nothing else contains one. Recognizing arrows does not depend on first characters, and digits are irrelevant to them.
- Every bracket therefore has exactly one kind, so `[x] := […]` infers its type.

### 3.2 `!` inverts what it follows

**Decided.** Inside brackets, `!` has one meaning, as `/` does: **it inverts what it follows.**

| After             | Inverts                                  | Example                       |
| ----------------- | ---------------------------------------- | ----------------------------- |
| a line word       | its meaning: struck, "does not"          | `[/solid!/>]` ↛               |
| a hook or harpoon | its side: `[inner]` instead of `[outer]` | `[/solid/^!]`, `[?!/solid/>]` |
| an angle          | its side: inward instead of outward      | `:bend [30!]`                 |

**There are no negative numbers.** The only signed value was `:bend`'s angle, and its sign meant a side, which `!` now says. Lengths, sizes and fractions are never negative. So a number always starts with a digit, and `-` never starts a number.

Because brackets are opaque, `!` inside them never clashes with `!` (parallel) in structure.

**Theme tokens** are names in the prelude whose colour the theme decides: `[ink]` lines and text (#333333 in the base theme), `[soft]` edge labels (#555555), `[muted]` canonical labels (#888888), `[accent]` (#1f6feb).

---

## 4. Attributes

Applies to: **N** nodes, **E** edges, **C** cells, **Z** zones.

### 4.1 Text

| Attribute | Applies to | Values                                          | Default                                                                                                                                                                         |
| --------- | ---------- | ----------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `:label`  | N E C Z    | text, math                                      | node: its name without `#`, else its canonical end; edge, cell: its name; zone: its name. Marks (`&choice` `&parallel` `&start` `&end`) have no label unless `:label` gives one |
| `:font`   | N E C Z    | text (a font name)                              | theme                                                                                                                                                                           |
| `:face`   | N E C Z    | `[regular]` `[italic]` `[bold]` `[bold-italic]` | `[regular]`; `[italic]` for `&canonical`                                                                                                                                        |
| `:size`   | N E C Z    | length                                          | theme (edge and cell labels smaller than node labels)                                                                                                                           |
| `:ink`    | N E C Z    | colour                                          | `[ink]`; `[soft]` for edge and cell labels; `[muted]` for `&canonical`                                                                                                          |

`:size` is the size of the lettering, and only that. Nodes are sized by their label, or explicitly with `:width` and `:height`.

### 4.2 Nodes

| Attribute           | Values                                                                                                                                                                                          | Default                           |
| ------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | --------------------------------- |
| `:shape`            | `[none]` `[box]` `[round]` `[circle]` `[double-circle]` `[ellipse]` `[stadium]` `[diamond]` `[hexagon]` `[parallelogram]` `[cylinder]` `[document]` `[bar]` `[point]` `[terminal]` `[bullseye]` | by kind (section 6)               |
| `:fill`             | colour                                                                                                                                                                                          | none                              |
| `:stroke`           | colour                                                                                                                                                                                          | `[ink]`                           |
| `:pen`              | `[thin]` `[normal]` `[thick]`                                                                                                                                                                   | `[normal]`                        |
| `:line`             | `[solid]` `[dashed]` `[dotted]` `[double]` `[wavy]` `[none]`                                                                                                                                    | `[solid]`; `[dashed]` for `&hole` |
| `:width`, `:height` | length, as minimums                                                                                                                                                                             | fitted to the label               |
| `:padding`          | length                                                                                                                                                                                          | theme                             |
| `:align`            | `[start]` `[center]` `[end]`                                                                                                                                                                    | `[center]`                        |
| `:wrap`             | length                                                                                                                                                                                          | none                              |

`:align` uses `[start]` and `[end]`, not left and right: the start of a line of text, whatever the script's direction.

### 4.3 Edges and cells

| Attribute                    | Values                                                           | Default                                                                      |
| ---------------------------- | ---------------------------------------------------------------- | ---------------------------------------------------------------------------- |
| `:arrow`                     | arrow (4.6)                                                      | `[/solid/>]` for edges, `[/double/>]` for 2-cells, `[/triple/>]` for 3-cells |
| `:stroke`                    | colour                                                           | `[ink]`                                                                      |
| `:pen`                       | `[thin]` `[normal]` `[thick]`                                    | `[normal]`                                                                   |
| `:bend`                      | `[outer]` `[inner]`, or an angle: `[30]` outward, `[30!]` inward | none: straight                                                               |
| `:label-start`, `:label-end` | text, math                                                       | none                                                                         |
| `:label-at`                  | `[start]` `[mid]` `[end]`, or a fraction                         | `[mid]`                                                                      |
| `:side`                      | `[outer]` `[inner]` `[on]`                                       | `[outer]`                                                                    |
| `:shorten`                   | length                                                           | none                                                                         |

An edge has no `:line`: its line is part of `:arrow` (`[/dashed/>]`, `[/double/>]`).

### 4.4 Zones

| Attribute  | Values                                         | Default                                      |
| ---------- | ---------------------------------------------- | -------------------------------------------- |
| `:as`      | `[flat]` `[cluster]` `[node]` `[table]`        | `[cluster]`                                  |
| `:fill`    | colour                                         | none                                         |
| `:stroke`  | colour                                         | none: an unframed cluster                    |
| `:pen`     | `[thin]` `[normal]` `[thick]`                  | `[normal]`                                   |
| `:line`    | as for nodes                                   | `[solid]` once framed                        |
| `:padding` | length                                         | theme                                        |
| `:caption` | text, math                                     | none                                         |
| `:theme`   | theme names, applied left to right (section 7) | none: the base theme alone                   |
| `:marks`   | `[all]` `[none]`                               | `[all]`: draw marks from `:prove`, such as ⌟ |
| `:cross`   | `[gap]` `[plain]`                              | `[gap]`                                      |

A zone is drawn framed only if it has a `:stroke` or a `:fill`: borders are always explicit.

### 4.5 Behaviour

| Attribute | Applies to | Values       | Effect                                      |
| --------- | ---------- | ------------ | ------------------------------------------- |
| `:hide`   | N E C      | flag         | kept in the graph and the layout, not drawn |
| `:note`   | N E C Z    | text         | shown on hover, never drawn                 |
| `:link`   | N E C Z    | text (a URL) | the subject links to it                     |
| `:step`   | N E C      | number       | reveal order when presenting                |
| `:alt`    | Z          | text         | a description for screen readers            |

These are neither looks nor positions, but they are presentation, so they live in `:style`. A fourth layer for five attributes would be premature.

### 4.6 Arrows: `[tail/line/head]`

**Decided.** An arrow is three fields separated by `/`:

```
[tail/line/head]
```

- **Ends are symbolic glyphs; the line is a word.** Arrowheads are small closed shapes everyone recognizes, which glyphs suit. Lines are an open-ended family (wavy, double, triple), which no glyph scheme covers.
- **`tail` and `head` may be empty:** `[/solid/>]` is a plain arrow, `[/solid/]` a bare line. **`line` is required.**
- **The arrow only draws.** The edge's direction always comes from the relations; `:arrow` never changes it.
  **The line.** The same words as `:line` on nodes, plus `triple`, because levels need it:

| Word                       | Draws                             |
| -------------------------- | --------------------------------- |
| `solid`                    | a plain line                      |
| `dashed`, `dotted`, `wavy` | as named                          |
| `double`                   | two lines: 2-cells, implication ⇒ |
| `triple`                   | three lines: 3-cells ⇛            |
| `none`                     | no line, only the ends            |

**A mark is a `!` suffix on the line word:** `[/solid!/>]` is the struck arrow ↛ ("does not"), and it composes: `[/dashed!/>]`. This is the general rule of 3.2. Further marks, if ever needed, would be other suffix glyphs in the same place.

**The ends are read as a picture, left to right.** Each end is written as it looks when reading the arrow from tail to head, and **any glyph may go at either end**. So `[/solid/<]` puts a backward-pointing head at the target end, `[</solid/>]` points both ways, and `[>/solid/>]` has a tail pointing forward (mono ↣).

| Glyph                                                          | End                                                      |
| -------------------------------------------------------------- | -------------------------------------------------------- |
| `>` `<`                                                        | arrowhead, pointing as drawn                             |
| `>>` `<<`                                                      | two heads                                                |
| `\|>` `<\|`                                                    | hollow triangle                                          |
| `\|`                                                           | bar                                                      |
| `O`                                                            | hollow circle                                            |
| `@`                                                            | filled circle                                            |
| `X`                                                            | cross                                                    |
| `<>`                                                           | hollow diamond                                           |
| `<@>`                                                          | filled diamond                                           |
| `?`                                                            | hook                                                     |
| `^`                                                            | harpoon                                                  |
| `\|\|` `O\|` `\|{` `O{` (and as tails `\|\|` `\|O` `}\|` `}O`) | crow's feet: one, zero or one, one or more, zero or more |

**Hooks and harpoons have a side.** `?` and `^` are the only ends that curl or barb to one side. Their side follows the geometry of section 5.1, never the page:

- by default, the hook or barb is on the **`[outer]`** side;
- a **`!` suffix** puts it on the **`[inner]`** side: `?!`, `^!` (3.2).
- So a classic pair of harpoons ⇌ between two parallel arrows has each barb facing out, automatically.
  **Examples.**

| Arrow                         | Reads as                                   |
| ----------------------------- | ------------------------------------------ |
| `[/solid/>]`                  | → plain                                    |
| `[>/solid/>]`                 | ↣ mono                                     |
| `[/solid/>>]`                 | ↠ epi                                      |
| `[?/solid/>]`                 | ↪ inclusion                                |
| `[\|/solid/>]`                | ↦ maps to                                  |
| `[</solid/>]`                 | ↔ both ways                                |
| `[/dashed/>]`                 | ⇢ unique existence                         |
| `[/double/>]`                 | ⇒ 2-cell, implication                      |
| `[/triple/>]`                 | ⇛ 3-cell                                   |
| `[/wavy/>]`                   | ⇝ wavy                                     |
| `[/solid!/>]`                 | ↛ does not                                 |
| `[/solid/^]`, `[/solid/^!]`   | ⇀ harpoon, outer or inner                  |
| `[/solid/O]`, `[/solid/@]`    | lollipop, solid lollipop                   |
| `[/solid/X]`                  | cross                                      |
| `[/solid/\|]`                 | ⊣ inhibition                               |
| `[/solid/\|>]`                | generalization (UML)                       |
| `[<>/solid/]`, `[<@>/solid/]` | aggregation, composition (UML)             |
| `[\|\|/solid/O{]`             | one to zero-or-more                        |
| `[>/wavy/X]`                  | a wavy line from a forward tail to a cross |

**Names for the common arrows.** The literal is precise but heavy for everyday use, so the prelude defines names, in fAB, like any value:

```
[mono]   := [>/solid/>]
[epi]    := [/solid/>>]
[incl]   := [?/solid/>]
[mapsto] := [|/solid/>]
[unique] := [/dashed/>]
[iso]    := [</solid/>]
…
f :arrow [epi]
```

The literal covers anything unusual; names cover everyday use.

---

## 5. Geometry without directions

### 5.1 Inner and outer

**Decided.** Sides are measured against the diagram's own shape, never against the page or a chosen orientation.

- **`[outer]`**: the side away from the region the edge borders.
- **`[inner]`**: the side facing it.
- **The region an edge borders:** for an edge on a cycle, the cycle's face; otherwise the side facing the zone's centre. For a lone edge where neither exists, the renderer falls back to a fixed rule (open: which).
  **Why not left and right of travel.** "Left of travel" survives rotation but not reflection: flip the flow from east to west and every label jumps to the other side of the screen. Inner and outer depend only on the diagram's geometry, so they are invariant under every rotation and reflection. Mathematically, left-of-travel needs a chosen orientation of the plane; inner/outer needs none.

The same reference is used by `:side` (5.2), `:bend` (5.3), and the side of hooks and harpoons (4.6). `!` always means "the inner side instead" (3.2).

### 5.2 Labels: `:side`

`:side [outer]` is the default, matching how mathematicians draw by hand: labels outside a square or a triangle. `[on]` places the label on the line, cut out by a gap (5.4).

### 5.3 Bending: `:bend`

- `:bend [outer]` and `:bend [inner]` bow the edge outward or inward by a default angle (the theme's).
- `:bend [30]` gives the angle in degrees, bowing **outward**; `:bend [30!]` bows **inward** by the same angle (3.2). There are no negative angles.
- Bending changes the shape of the curve and moves no node, so it is style.
- Consequence: `+(f, g)+` with `&edge :bend [outer]` bows the two arrows apart into a lens, with no side bookkeeping.

### 5.4 Crossings: `:cross`

**Decided.** How crossings are drawn is one decision per diagram, not a per-subject border, so every crossing in a diagram looks the same.

- `:cross [gap]` (default): where two lines cross, the **upper** one is drawn with a gap cut around it, so the lower line visibly passes underneath.
- `:cross [plain]`: lines simply cross.
- **Which line is upper:** the one drawn later. Stacking between subjects follows source order (what is written later is drawn on top); stacking is a `:place` concern (section 8).
- **Text shares the decision.** Labels that cross a line, or sit on one (`:side [on]`), get the same gap around their lettering.
- **The gap's colour is the zone's background:** its `:fill`, else the theme's. Never a hard-coded white, so dark themes work.
- It is a zone attribute, so it cascades: a nested zone may override it.

### 5.5 Drawing order inside one subject

**Decided.** Fixed, not configurable: gap (if any), fill, line, label on top. It is the only order that works, and an option nobody needs is noise.

---

## 6. Kind defaults

The first bindings of the base theme (section 7). These match what the formatter does today (implemented 2026-10-22), expressed in this vocabulary.

| Class        | `:shape`                 | Other defaults                                                                             |
| ------------ | ------------------------ | ------------------------------------------------------------------------------------------ |
| `&plain`     | `[circle]`               | label inside; every circle in a diagram drawn at one diameter, fitted to the longest label |
| `&choice`    | `[diamond]`              | no label                                                                                   |
| `&parallel`  | `[bar]`                  | no label; as wide as its busier side needs                                                 |
| `&start`     | `[point]` (a filled dot) | no label                                                                                   |
| `&end`       | `[bullseye]`             | no label                                                                                   |
| `&hole`      | `[circle]`               | `:line [dashed]`; labelled by its canonical end if it has one                              |
| `&canonical` |                          | `:face [italic]`, `:ink [muted]`                                                           |
| `&edge`      |                          | `:arrow [/solid/>]`, `:ink [soft]`, smaller `:size`                                        |
| `&cell`      |                          | `:arrow [/double/>]` (2-cells), `[/triple/>]` (3-cells), `:ink [soft]`, smaller `:size`    |
| `&zone`      |                          | `:as [cluster]`, unframed, `:cross [gap]`                                                  |

A start is a null node no edge arrives at; an end is one some edge arrives at (as in UML activity diagrams).

---

## 7. Themes and the prelude

### 7.1 A theme is a named style

**Decided.** A theme is a value: a block of subjects with attributes, bound to a name:

```
[dark] := {
  &zone :fill [#1e1e1e],
  &node :stroke [#dddddd],
  &edge :ink [#aaaaaa]
}
```

A theme and a bundle are both blocks, but different types, told apart by their contents:

- **a bundle** (`:terminal := { :shape [circle] }`) holds attributes only, and applies to one subject;
- **a theme** (`[dark] := { &node :fill … }`) holds subjects with attributes, and applies to a diagram.

### 7.2 The base theme always applies

**Decided.**

- **The base theme is the kind defaults** (section 6) and every other default of section 4, written as ordinary fAB bindings.
- **It always applies,** first. It is never removed, only overridden.
- **It binds every attribute for every kind.** So the cascade always ends in a value: mathematically, the style is a **total** function on elements and attributes, and themes and programs only override parts of it. "Missing value" is never a state a renderer has to handle.

### 7.3 Composition

**Decided.** Layers apply in order, the later winning wherever both set a value:

```
base  <  themes, left to right  <  the program's own bindings
```

- This is the cascade monoid of fab-core (`Attrs.over`, identity `empty`) one level up: a theme is an element of it, and composing themes is `over`.
- **"Each binding once" holds within a layer.** Across layers, the later one wins, deliberately and in order. So a theme and a program may both bind `&node :shape` with no conflict.
- **Choosing themes:** `:theme` takes theme names, several composing left to right in one token:
  ```
  [compact] := { &node :padding [0.2] }
  Order :theme := [dark,compact]
  ```
- `:theme` is a zone attribute, so it cascades to nested zones, which may choose their own.

### 7.4 The prelude is a fAB file

**Decided.** The prelude is ordinary fAB source, kept as a readable `.fab` file in the repository and compiled into the binary. It contains:

- the base theme (section 7.2);
- the built-in values: theme tokens, colour names, keywords;
- the named arrows (`[epi]`, `[mono]`, `[incl]`, …);
- the built-in themes (`[dark]`, `[print]`, …).
  So the defaults are documented by being written in the language itself, the formatter's hard-coded table (`kindDefault` in fab-core) becomes data, and the language is used to define itself. Names defined in the prelude cannot be redefined by a program.

---

## 8. Not in `:style`

**Moved to `:place`** (vocabulary open; layout uses a cardinal point for the overall flow, and relative ranks along and across it, without the words vertical and horizontal):

- `:at`, `:rank`, `:layout`, `:direction`, `:routing`, `:spacing`;
- `:loop` (which side of a node an endomorphism's loop sits on: a position relative to the node);
- **stacking between subjects** (formerly `:z`): relational ("f over g"); default source order.
  **Removed:**
- `:class`: classes are `&` subjects, and named sets of attributes are bundles, applied by writing them.
- `:weight`: split into `:pen` (line thickness) and `:face` (bold type).
- `:line` on edges: part of `:arrow`.
- `:z`: within one subject the order is fixed (5.5); between subjects it is `:place`.
- `:flip`: the side of a hook or harpoon is written in the arrow (`?!`, `^!`).

---

## 9. Flags and bundles

**Decided.** An attribute written with no value means **apply it**:

- a built-in flag: `G.f :hide`;
- a bundle: `:terminal := { :shape [circle], :fill [ink] }`, then `G.#Done :terminal`.
  So `:hide` needs no `[on]`/`[off]`, and flags and bundles read the same way. Bundles can be refined afterwards; the later setting wins: `G.#Done { :terminal, :fill [red] }`.

---

## 10. Errors

- Unknown attribute: "`:colour` is not an attribute; did you mean `:ink`, `:stroke` or `:fill`?"
- An attribute that does not apply to the subject: "`:fill` does not apply to an edge"; "`:arrow` does not apply to a node"; "`:line` does not apply to an edge; its line is part of `:arrow`".
- A value of the wrong type: "a colour where a shape is expected".
- A keyword not among the attribute's values: "`[sideways]` is not a value of `:side`; expected `[outer]`, `[inner]` or `[on]`".
- A flag given a value, or a valued attribute given none: "`:hide` takes no value"; "`:shape` needs a value".
- A relational value (one that names structure): "`:style` cannot refer to `g`; placement belongs in `:place`".
- A direction word in a style: "`[left]` is a direction on the page; use `[outer]` or `[inner]`".
- A binding made twice in one layer: "`G.#Done :shape` is already defined".
- A non-canonical node reference: "`+g` is not canonical; this node is `f+`".
- An unknown class: "`&nodes` is not a class".
- A negative number: "`[-30]`: numbers are never negative; for the inner side, write `[30!]`".
- `!` after a number whose attribute has no side: "`:size [2!]`: only `:bend` angles have a side to invert".
- A name starting with an uppercase letter: "`[Warn]`: names start with a lowercase letter".
- A prelude name redefined: "`[epi]` is built in and cannot be redefined".
- **Arrows:**
  - a missing line: "`[//>]`: an arrow needs a line, such as `solid`";
  - an unknown line word: "`[/zigzag/>]`: `zigzag` is not a line; expected `solid`, `dashed`, `dotted`, `wavy`, `double`, `triple` or `none`";
  - an unknown end glyph: "`[/solid/%]`: `%` is not an arrow end";
  - `!` after an end that has no side: "`>!`: only hooks `?` and harpoons `^` have a side to invert";
  - more or fewer than three fields is not an arrow at all (a bracket with one `/` is a range).
- **Themes:** an unknown theme name in `:theme`; a theme whose block holds a bare attribute with no subject (that is a bundle); a bundle used as a theme.
- A subject of another zone styled from this one (open: whether a zone may style its own nested zones' contents; the spec says each diagram styles itself).

---

## 11. Example

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

[warn] := [#c0392b]
:terminal := { :stroke [warn], :pen [thick] }

Order :theme := [print]
Order :style := {
  &node :shape [round],
  validate+ :label "Valid?",
  charge+ :label "Payment accepted?",
  #Rejected :terminal,
  (retry, restock) { :arrow [/dashed/>], :bend [20!] },
  (yes, paid, reserved) :label "yes",
  (no, declined, short) :label "no"
}
```

---

## 12. Open

1. **Equal-specificity overlaps** between classes (2.3): error or fixed precedence.
2. **`:as` and node declarations.** If declaring a node (`#User :: …`) comes to mean "a graph inside a point", `[node]` and `[table]` may move from `:as` to structure.
3. **The fallback rule for `[outer]`** on a lone edge with no region.
4. **The prelude's contents:** which colour names, the exact keyword lists, the named arrows, and which built-in themes ship.
5. **Styling nested zones from outside** (section 10, last error).
6. **The `:place` vocabulary**, including stacking and `:loop` (separate document).

---

## 13. Rejected

- **`:weight`** for line thickness: clashed with font weight. Replaced by `:pen`.
- **`:scale`** for text size: does not convey the size of lettering. `:size` kept, for text only.
- **`:pt`, `:type`, `:letter`, `:glyph`** for text size: unit-bound, overloaded, long or obscure.
- **Left and right of travel** for `:side` and `:bend`: not invariant under reflection (5.1).
- **`[close]`/`[far]`**: the right idea; `[outer]`/`[inner]` names what they are measured against.
- **`:z` in `:style`:** inside one subject the order is fixed; between subjects it is relational, so `:place`.
- **A per-subject border or halo attribute** for crossings: one per-diagram decision (`:cross`) keeps every crossing consistent.
- **`[on]`/`[off]` for flags:** an attribute with no value already means "apply it".
- **The all-glyph arrow grammar** of the spec (`->`, `-->`, `=>`, `~>`, `>->`): lines are an open family no glyph scheme covers (wavy, triple, and future ones), and glyph lines made arrow recognition depend on first characters. Replaced by `[tail/line/head]`.
- **`0` for the hollow circle and `*` for the cross:** digits in arrows broke literal disjointness; `O` and `X` are also what DOT and Mermaid use.
- **`(` and `)` for hooks, `\` and `/` for upper and lower harpoons:** mirrored pairs encode left and right of travel, which is not reflection-invariant. One glyph each (`?`, `^`) with `!` for the inner side.
- **A `:flip` attribute** for hooks and harpoons: the side is part of the arrow, so `:arrow` alone describes it.
- **`line` as the word for a plain line:** `[/line/>]` says "the line is a line"; `solid` matches `:line [solid]` on nodes.
- **A fourth arrow field for marks:** a mark is rare; a suffix on the line word (`solid!`) keeps three fields.
- **Negative numbers** (`:bend [-30]` for an inward bend): the sign meant a side, which `!` says uniformly (3.2). Without them every number starts with a digit.
- **A closed list of theme names** (`[light]`, `[dark]`, `[print]`, `[auto]`) for `:theme`: themes are values, built in or user-defined, and compose.
