# akashic-layout — CSS Block & Inline Flow Layout

Implements CSS 2.1 normal flow layout: block formatting context and
inline formatting context.  Takes a box tree (from `box.f`) and
computes positions $(x, y)$ and resolved dimensions (width, height)
for every box.

```forth
REQUIRE render/layout.f
```

`PROVIDED akashic-layout-engine` — safe to include multiple times.
Automatically requires `box.f`, `line.f`, and `text/layout.f` (and
transitively `dom.f`, `css.f`, `markup/`, `utils/string.f`).

---

## Table of Contents

- [Design Principles](#design-principles)
- [Dependencies](#dependencies)
- [Public API](#public-api)
  - [LAYO-LAYOUT](#layo-layout)
  - [LAYO-BLOCK](#layo-block)
  - [LAYO-INLINE-CONTEXT](#layo-inline-context)
  - [LAYO-RESOLVE-WIDTH](#layo-resolve-width)
  - [LAYO-RESOLVE-HEIGHT](#layo-resolve-height)
  - [LAYO-COLLAPSE-MARGINS](#layo-collapse-margins)
  - [LAYO-CONTAINING-W](#layo-containing-w)
- [Layout Algorithm](#layout-algorithm)
- [Margin Collapsing](#margin-collapsing)
- [Inline Formatting Context](#inline-formatting-context)
- [Internals](#internals)
- [Quick Reference](#quick-reference)
- [Cookbook](#cookbook)

---

## Dependencies

```
layout.f
├── box.f          (akashic-box)
├── line.f         (akashic-line)
└── text/layout.f  (akashic-text-layout — LAY-TEXT-WIDTH, LAY-SCALE!)
```

---

## Design Principles

| Principle | Detail |
|---|---|
| **CSS 2.1 normal flow** | Block and inline formatting contexts.  No floats, no absolute/fixed positioning (future). |
| **Integer pixels** | All positions and dimensions are integer pixels, matching `box.f`. |
| **Variable-based state** | Shared `VARIABLE`s for scratch.  Recursive `LAYO-BLOCK` saves/restores state on the return stack. |
| **Top-down traversal** | Width resolved top-down (parent before children).  Height resolved bottom-up (children before parent). |
| **Prefix convention** | Public: `LAYO-`.  Internal: `_LAYO-`, `_LB-`, `_LIC-`. |

---

## Public API

### LAYO-LAYOUT

```forth
LAYO-LAYOUT  ( box-root vp-w vp-h -- )
```

Top-level entry point.  Sets the viewport dimensions, positions the
root box (applying its margin + border + padding offsets), runs a
**text measurement pre-pass** on the entire tree, then runs block
layout.

The text measurement pre-pass (`_LAYO-MEASURE-TEXT-REC`) walks the
box tree recursively and sets `BOX-W` / `BOX-H` on every text box
by measuring glyph advance widths via `LAY-TEXT-WIDTH` from
`text/layout.f`.  Font size is read from the parent element's CSS
`font-size` property (text nodes have no CSS of their own).

| Parameter | Description |
|---|---|
| `box-root` | Root of the box tree (from `BOX-BUILD-TREE`) |
| `vp-w` | Viewport width in pixels |
| `vp-h` | Viewport height in pixels |

---

### LAYO-BLOCK

```forth
LAYO-BLOCK  ( box -- )
```

Lay out a block-level box and all its children.

**Algorithm:**

1. Resolve width (`auto` → fill containing block).
2. Set content origin X from parent's X + own margin-left +
   border-left + padding-left.
3. Classify children:
   - **All inline** → enter inline formatting context.
   - **Any block** → iterate children in block formatting context.
4. For block children: collapse vertical margins, set Y positions,
   recurse into each child, advance Y cursor.
5. Resolve height (`auto` → final Y cursor value).

Saves and restores all iteration state on the return stack before
recursive calls, making it safe for arbitrary nesting depth.

---

### LAYO-INLINE-CONTEXT

```forth
LAYO-INLINE-CONTEXT  ( box -- )
```

Enter inline formatting context for a block box whose children are
all inline or text.  Builds `LINE-RUN-*` runs from children, breaks
into lines via `LINE-BREAK`, positions lines vertically, applies
text alignment via `LINE-ALIGN` (reading `text-align` from the
parent box's CSS), and maps run positions back to child boxes.

---

### LAYO-RESOLVE-WIDTH

```forth
LAYO-RESOLVE-WIDTH  ( box -- )
```

Resolve a box's content width.

**Percentage widths:** If the width was encoded as a percentage marker
by `_BOX-PARSE-PX` (i.e. `BOX-W <= -2`), the percentage is resolved
against the containing block width:

$$w = \left\lfloor \frac{w_{\text{containing}} \times \text{pct}}{100} \right\rfloor$$

**Auto width:** If `width = auto`:

$$w = w_{\text{containing}} - m_L - m_R - p_L - p_R - b_L - b_R$$

Clamped to $\geq 0$.  If width is already a concrete value (positive
or zero), this is a no-op.

---

### LAYO-RESOLVE-HEIGHT

```forth
LAYO-RESOLVE-HEIGHT  ( box -- )
```

Resolve a box's content height.  If `height = auto`, sets it to the
current Y cursor value (`_LAYO-CUR-Y`), representing the total
height consumed by children.

---

### LAYO-COLLAPSE-MARGINS

```forth
LAYO-COLLAPSE-MARGINS  ( margin-a margin-b -- collapsed )
```

CSS 2.1 vertical margin collapsing:

| Case | Rule |
|---|---|
| Both $\geq 0$ | $\max(a, b)$ |
| Both $< 0$ | $\min(a, b)$ — most negative |
| Mixed signs | $a + b$ |

---

### LAYO-CONTAINING-W

```forth
LAYO-CONTAINING-W  ( box -- w )
```

Returns the content width of the containing block.  For the root box
(no parent), returns the viewport width.  If the parent's width is
still `BOX-AUTO`, falls back to viewport width.

---

## Layout Algorithm

The full layout pass for a document:

```
HTML string
  → DOM-PARSE-HTML      → DOM tree (fragment)
  → BOX-BUILD-TREE      → box tree (styled)
  → LAYO-LAYOUT         → positioned box tree
  → PAINT-RENDER        → pixels on surface
```

Block layout follows CSS 2.1 §10.3.3 (block-level, normal flow):

1. **Width**: auto width fills the containing block minus
   margins/padding/borders.
2. **Position**: each child's X is parent's content X + child's
   left margin + border + padding.  Y advances downward with
   margin collapsing between siblings.
3. **Height**: auto height = total Y extent of children.

---

## Margin Collapsing

Adjacent vertical margins collapse per CSS 2.1 §8.3.1:

- First child's top margin collapses with parent's top margin
  (not yet implemented — parent padding/border separates them).
- Adjacent sibling margins collapse: tracked via `_LAYO-PREV-MB`.
- The final child's bottom margin is added to the Y cursor.

---

## Inline Formatting Context

When all children of a block are inline or text boxes:

1. Each child produces a **run** (`LINE-RUN-TEXT` or `LINE-RUN-BOX`).
2. Runs are linked into a list and broken into **line boxes** via
   `LINE-BREAK` using the parent's content width.
3. Lines are stacked vertically from Y = 0.
4. **Text alignment** is applied via `LINE-ALIGN`, reading the
   parent box's CSS `text-align` property:
   - `left` (default) — runs stay at their break positions.
   - `center` — runs are shifted right by half the available space.
   - `right` — runs are shifted right by all available space.
5. Child boxes receive X and Y positions from their corresponding
   runs and line boxes.
6. Text boxes with auto width/height get dimensions from run metrics;
   default text height is 16px with ~80% ascender.

---

## Internals

### Variables

| Variable | Purpose |
|---|---|
| `_LAYO-VP-W` / `_LAYO-VP-H` | Viewport dimensions |
| `_LAYO-CUR-Y` | Running Y cursor within current block |
| `_LAYO-PREV-MB` | Previous sibling's margin-bottom (for collapsing) |
| `_LAYO-COLLAPSED` | Latest collapsed margin value |
| `_LB-BOX` | Current box in `LAYO-BLOCK` |
| `_LB-CHILD` | Current child during block iteration |
| `_LB-ALL-INLINE` | Flag: all children are inline |
| `_LIC-BOX` | Parent box in inline context |
| `_LIC-CHILD` | Current child in inline iteration |
| `_LIC-RUN-HEAD` | Head of run list for `LINE-BREAK` |

### Helpers

| Word | Purpose |
|---|---|
| `_LAYO-IS-INLINE` | `( display -- flag )` Check if inline or inline-block |
| `_LAYO-ALL-CHILDREN-INLINE` | `( box -- flag )` Scan children for block types |
| `_LAYO-MAKE-INLINE-RUN` | `( child -- run\|0 )` Create line run from box |
| `_LAYO-GET-TEXT-FONT-SIZE` | `( text-box -- font-size )` Read parent's CSS `font-size` (default 16) |
| `_LAYO-MEASURE-TEXT-REC` | `( box -- )` Recursive text measurement pre-pass |
| `_LAYO-PARSE-TEXT-ALIGN` | `( box -- align-const )` Read CSS `text-align` → `LINE-A-LEFT`/`CENTER`/`RIGHT` |

---

## Quick Reference

```
LAYO-LAYOUT          ( box-root vp-w vp-h -- )   Full layout pass
LAYO-BLOCK           ( box -- )                   Block formatting context
LAYO-INLINE-CONTEXT  ( box -- )                   Inline formatting context
LAYO-RESOLVE-WIDTH   ( box -- )                   Resolve auto width
LAYO-RESOLVE-HEIGHT  ( box -- )                   Resolve auto height
LAYO-COLLAPSE-MARGINS( a b -- collapsed )         Margin collapsing
LAYO-CONTAINING-W    ( box -- w )                 Containing block width
```

---

## Cookbook

### Lay out a simple document

```forth
\ Parse HTML and run full layout at 800×600
REQUIRE render/layout.f

: LAYOUT-EXAMPLE
  S" <div style='width:600px;padding:10px'>"
  S" <p style='margin:5px'>Hello</p>"
  S" <p style='margin:5px'>World</p>"
  S" </div>"
  \ ... build string, parse, build tree, layout
  DOM-PARSE-HTML
  BOX-BUILD-TREE DUP
  800 600 LAYO-LAYOUT
  \ Now all boxes have final x, y, w, h
  BOX-FREE-TREE ;
```

### Check child positions after layout

```forth
\ After LAYO-LAYOUT, query positions:
  root BOX-FIRST-CHILD DUP
  BOX-X .   \ child content X
  BOX-Y .   \ child content Y
  BOX-W .   \ resolved width
```
