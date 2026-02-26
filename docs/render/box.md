# akashic-box — CSS Box Model for KDOS / Megapad-64

Maps DOM elements to CSS box descriptors.  Each element that generates
visual output gets a box with resolved dimensions, margins, padding,
and border widths.  Boxes form a tree mirroring the DOM tree, minus
`display:none` elements.

```forth
REQUIRE render/box.f
```

`PROVIDED akashic-box` — safe to include multiple times.
Automatically requires `dom.f` (and transitively `css.f`, `markup/`,
`utils/string.f`).

---

## Table of Contents

- [Design Principles](#design-principles)
- [Memory Layout](#memory-layout)
- [Constants](#constants)
- [Creation & Destruction](#creation--destruction)
- [Accessors](#accessors)
- [Setters](#setters)
- [Style Resolution](#style-resolution)
- [Rectangle Queries](#rectangle-queries)
- [Tree Building](#tree-building)
- [Quick Reference](#quick-reference)
- [Cookbook](#cookbook)

---

## Design Principles

| Principle | Detail |
|---|---|
| **Integer pixels** | All dimensions are integer pixels.  CSS values are parsed and truncated: `"10px"` → `10`, `"auto"` → `-1` (`BOX-AUTO`). |
| **Variable-based state** | Internal scratch uses `VARIABLE`s — not re-entrant.  Recursive helpers save/restore state on the return stack. |
| **Heap-allocated** | `BOX-CREATE` allocates 176 bytes via `ALLOCATE`.  `BOX-DESTROY` calls `FREE`.  `BOX-FREE-TREE` frees an entire subtree. |
| **Style from DOM** | `BOX-RESOLVE-STYLE` reads inline styles from the DOM node via `DOM-STYLE@` and parses them into box fields. |
| **Prefix convention** | Public: `BOX-`.  Internal: `_BOX-`.  Field accessors: `B.xxx`. |

---

## Memory Layout

A box descriptor occupies 22 cells = 176 bytes:

```
Offset  Size  Field
──────  ────  ──────────────
+0      8     dom-node      — back-pointer to DOM node
+8      8     parent        — parent box (or 0)
+16     8     first-child   — first child box (or 0)
+24     8     next          — next sibling box (or 0)
+32     8     display       — display type (see Constants)
+40     8     x             — content origin X (integer px)
+48     8     y             — content origin Y (integer px)
+56     8     width         — content width (px, or BOX-AUTO = -1)
+64     8     height        — content height (px, or BOX-AUTO = -1)
+72     8     margin-t      — margin top
+80     8     margin-r      — margin right
+88     8     margin-b      — margin bottom
+96     8     margin-l      — margin left
+104    8     padding-t     — padding top
+112    8     padding-r     — padding right
+120    8     padding-b     — padding bottom
+128    8     padding-l     — padding left
+136    8     border-t      — border width top
+144    8     border-r      — border width right
+152    8     border-b      — border width bottom
+160    8     border-l      — border width left
+168    8     flags         — bit 0: text box (content is text)
```

Field accessor words (`B.DOM`, `B.X`, `B.MT`, ...) return the
address of each field for use with `@` and `!`.

---

## Constants

| Constant | Value | Description |
|---|---|---|
| `BOX-D-BLOCK` | 0 | Block-level display |
| `BOX-D-INLINE` | 1 | Inline display |
| `BOX-D-INLINE-BLOCK` | 2 | Inline-block display |
| `BOX-D-NONE` | 3 | Element generates no box |
| `BOX-AUTO` | -1 | Auto dimension (resolved by layout) |
| `BOX-DESC-SIZE` | 176 | Box descriptor size in bytes |

---

## Creation & Destruction

### BOX-CREATE

```forth
BOX-CREATE  ( dom-node -- box )
```

Allocate a new box descriptor for the given DOM node.  All fields are
zeroed, then defaults are applied: `display = BOX-D-BLOCK`,
`width = BOX-AUTO`, `height = BOX-AUTO`.  The DOM back-pointer is set.

Aborts with `"BOX-CREATE: alloc failed"` on allocation failure.

### BOX-DESTROY

```forth
BOX-DESTROY  ( box -- )
```

Free a single box descriptor.  Does **not** recurse into children.

### BOX-FREE-TREE

```forth
BOX-FREE-TREE  ( box -- )
```

Free an entire box tree rooted at `box`.  Uses iterative post-order
traversal (no return-stack pressure).  Handles `box = 0` gracefully.

---

## Accessors

All accessors read a field from a box descriptor.

| Word | Signature | Description |
|---|---|---|
| `BOX-DOM` | `( box -- node )` | DOM node back-pointer |
| `BOX-PARENT` | `( box -- box\|0 )` | Parent box |
| `BOX-FIRST-CHILD` | `( box -- box\|0 )` | First child box |
| `BOX-NEXT` | `( box -- box\|0 )` | Next sibling box |
| `BOX-DISPLAY` | `( box -- disp )` | Display type constant |
| `BOX-X` | `( box -- x )` | Content area X origin |
| `BOX-Y` | `( box -- y )` | Content area Y origin |
| `BOX-W` | `( box -- w )` | Content width |
| `BOX-H` | `( box -- h )` | Content height |
| `BOX-MARGIN-T` | `( box -- n )` | Margin top |
| `BOX-MARGIN-R` | `( box -- n )` | Margin right |
| `BOX-MARGIN-B` | `( box -- n )` | Margin bottom |
| `BOX-MARGIN-L` | `( box -- n )` | Margin left |
| `BOX-PADDING-T` | `( box -- n )` | Padding top |
| `BOX-PADDING-R` | `( box -- n )` | Padding right |
| `BOX-PADDING-B` | `( box -- n )` | Padding bottom |
| `BOX-PADDING-L` | `( box -- n )` | Padding left |
| `BOX-BORDER-T` | `( box -- n )` | Border width top |
| `BOX-BORDER-R` | `( box -- n )` | Border width right |
| `BOX-BORDER-B` | `( box -- n )` | Border width bottom |
| `BOX-BORDER-L` | `( box -- n )` | Border width left |

---

## Setters

Used by the layout engine to position and size boxes after style
resolution.

| Word | Signature | Description |
|---|---|---|
| `BOX-X!` | `( x box -- )` | Set content X origin |
| `BOX-Y!` | `( y box -- )` | Set content Y origin |
| `BOX-W!` | `( w box -- )` | Set content width |
| `BOX-H!` | `( h box -- )` | Set content height |

---

## Style Resolution

### BOX-RESOLVE-STYLE

```forth
BOX-RESOLVE-STYLE  ( box -- )
```

Read CSS properties from the box's DOM node and populate box fields:

| CSS Property | Box Field(s) | Notes |
|---|---|---|
| `display` | `B.DISPLAY` | Parsed: `block`, `inline`, `inline-block`, `none`.  Default = block. |
| `width` | `B.W` | Parsed as integer px.  `"auto"` → `BOX-AUTO`. |
| `height` | `B.H` | Same as width. |
| `margin` | `B.MT B.MR B.MB B.ML` | TRBL shorthand via `CSS-EXPAND-TRBL`. |
| `padding` | `B.PT B.PR B.PB B.PL` | Same. |
| `border-width` | `B.BT B.BR B.BB B.BL` | Same. |

Text nodes (`DOM-T-TEXT`) get the `_BOX-F-TEXT` flag set in `B.FLAGS`
and their display is forced to `BOX-D-INLINE` (regardless of any CSS
`display` value) so that the layout engine treats them as inline
content within their parent's inline formatting context.

**Supported units:** `px`, unitless (treated as px), and `%`
(percentage).  Other units (`em`, `rem`) are left for the layout
engine.

### Percentage Encoding

`_BOX-PARSE-PX` detects a trailing `%` character and encodes the
value as a marker for later resolution by the layout engine:

$$\text{marker} = -(\text{percentage} + 2)$$

Examples:

| CSS Value | Stored in `B.W` | Meaning |
|---|---|---|
| `50%` | `-52` | 50 percent |
| `100%` | `-102` | 100 percent |
| `25%` | `-27` | 25 percent |
| `auto` | `-1` (`BOX-AUTO`) | Auto (not a percentage) |

The layout engine (`LAYO-RESOLVE-WIDTH`) checks for `BOX-W <= -2`
and resolves the percentage against the containing block width.

---

## Rectangle Queries

Each query returns `( x y w h )` for a different CSS box model area.
Internally, the box pointer is saved in a variable to avoid stack
juggling.

### BOX-CONTENT-RECT

```forth
BOX-CONTENT-RECT  ( box -- x y w h )
```

The content area: `(x, y, w, h)` as stored in the box.

### BOX-PADDING-RECT

```forth
BOX-PADDING-RECT  ( box -- x y w h )
```

Content area extended by padding on all sides.

### BOX-BORDER-RECT

```forth
BOX-BORDER-RECT  ( box -- x y w h )
```

Content + padding + border width.

### BOX-MARGIN-RECT

```forth
BOX-MARGIN-RECT  ( box -- x y w h )
```

Full margin box — the outermost rectangle.

**Relationships:**

$$\text{margin-rect} \supseteq \text{border-rect} \supseteq \text{padding-rect} \supseteq \text{content-rect}$$

---

## Tree Building

### BOX-BUILD-TREE

```forth
BOX-BUILD-TREE  ( dom-root -- box-root )
```

Generate a box tree from a DOM tree.  Walks depth-first:

1. For each `DOM-T-ELEMENT`: creates a box, resolves style.  If
   `display:none`, unlinks the box and skips the entire subtree.
2. For each `DOM-T-TEXT` with non-empty text: creates a leaf box with
   the `_BOX-F-TEXT` flag.
3. Fragments/documents: iterates top-level children.

The resulting tree mirrors the DOM tree minus hidden elements.  Call
`BOX-FREE-TREE` to release it when done.

**Recursion safety:** `_BOX-BUILD-REC` saves `_BBT-CUR-PAR` and
`_BBT-LAST` on the return stack before descending, and saves the
DOM next-sibling pointer with `>R` before each recursive call.

---

## Quick Reference

```
BOX-CREATE        ( dom-node -- box )
BOX-DESTROY       ( box -- )
BOX-FREE-TREE     ( box -- )
BOX-RESOLVE-STYLE ( box -- )
BOX-BUILD-TREE    ( dom-root -- box-root )

BOX-CONTENT-RECT  ( box -- x y w h )
BOX-PADDING-RECT  ( box -- x y w h )
BOX-BORDER-RECT   ( box -- x y w h )
BOX-MARGIN-RECT   ( box -- x y w h )

BOX-X! / BOX-Y! / BOX-W! / BOX-H!   ( val box -- )

BOX-DOM / BOX-PARENT / BOX-FIRST-CHILD / BOX-NEXT
BOX-DISPLAY / BOX-X / BOX-Y / BOX-W / BOX-H
BOX-MARGIN-T/R/B/L  BOX-PADDING-T/R/B/L  BOX-BORDER-T/R/B/L
```

---

## Cookbook

### Create a box tree from HTML

```forth
S" <div style='width:200px;padding:10px'><p>Hello</p></div>"
  DOM-PARSE-HTML BOX-BUILD-TREE
  DUP BOX-FIRST-CHILD BOX-W .  \ -1 (auto — not yet laid out)
  BOX-FREE-TREE
```

### Inspect all four rectangles

```forth
\ After layout has set x, y, w, h:
box BOX-CONTENT-RECT  CR ." Content: " . . . .
box BOX-PADDING-RECT  CR ." Padding: " . . . .
box BOX-BORDER-RECT   CR ." Border:  " . . . .
box BOX-MARGIN-RECT   CR ." Margin:  " . . . .
```

### Walk the box tree

```forth
: WALK-BOXES  ( box -- )
    DUP 0= IF DROP EXIT THEN
    DUP BOX-DISPLAY . CR
    DUP BOX-FIRST-CHILD
    BEGIN DUP 0<> WHILE
        DUP BOX-NEXT >R
        RECURSE
        R>
    REPEAT DROP ;
```
