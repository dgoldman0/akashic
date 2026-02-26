# akashic-paint — CSS Box Tree Painter

Walks a laid-out box tree and paints to a surface following CSS 2.1
Appendix E painting order: background, borders, block children
(recursive), then inline/text content.

```forth
REQUIRE render/paint.f
```

`PROVIDED akashic-paint` — safe to include multiple times.
Automatically requires `box.f`, `surface.f`, `draw.f`, and
`layout.f` (and transitively `dom.f`, `css.f`, `markup/`,
`utils/string.f`).

---

## Table of Contents

- [Design Principles](#design-principles)
- [Dependencies](#dependencies)
- [CSS Properties Consumed](#css-properties-consumed)
- [Public API](#public-api)
  - [PAINT-RENDER](#paint-render)
  - [PAINT-BOX](#paint-box)
  - [PAINT-BG-COLOR](#paint-bg-color)
  - [PAINT-BORDERS](#paint-borders)
  - [PAINT-TEXT](#paint-text)
  - [PAINT-CSS-COLOR](#paint-css-color)
- [Painting Algorithm](#painting-algorithm)
- [Internals](#internals)
  - [_PNT-GET-COLOR](#_pnt-get-color)
  - [_PNT-GET-FONT-SIZE](#_pnt-get-font-size)
  - [_PNT-BORDER-COLOR](#_pnt-border-color)
  - [_PNT-HAS-BORDER-STYLE?](#_pnt-has-border-style)
- [Quick Reference](#quick-reference)
- [Cookbook](#cookbook)

---

## Design Principles

| Principle | Detail |
|---|---|
| **CSS 2.1 Appendix E order** | Background → borders → block children → inline/text → outline (future). |
| **Integer RGBA** | Colours are packed into a single 64-bit cell as `0xRRGGBBAA`. Alpha is always `0xFF` (opaque) for parsed colours; `0x00000000` for transparent. |
| **Variable-based state** | Shared `VARIABLE`s for scratch — no locals, no heap allocation during painting. |
| **Recursive tree walk** | `PAINT-RENDER` walks depth-first, saving/restoring state on the return stack at each level. |
| **Prefix convention** | Public: `PAINT-`.  Internal: `_PNT-`, `_PBC-`, `_PBD-`, `_PTX-`, `_PR-`, `_PGC-`. |
| **Surface-backed** | All drawing goes through `SURF-FILL-RECT` and `DRAW-TEXT` — the painter never touches pixel buffers directly. |

---

## Dependencies

```
paint.f
├── box.f         (akashic-box — tree structure, rect queries)
├── surface.f     (akashic-surface — SURF-FILL-RECT)
├── draw.f        (akashic-draw — DRAW-TEXT)
└── layout.f      (akashic-layout-engine — must run before paint)
```

Transitively loads: `dom.f`, `css.f`, `bridge.f`, `html.f`,
`core.f`, `string.f`, `line.f`, `color.f`, `fp16.f`, etc.

---

## CSS Properties Consumed

| Property | Parsed by | Notes |
|---|---|---|
| `background-color` | `PAINT-CSS-COLOR` | Hex `#RGB`/`#RRGGBB`, named colours, `transparent` |
| `border-color` | `_PNT-BORDER-COLOR` | Shorthand fallback |
| `border-top-color` | `_PNT-BORDER-COLOR` | Per-side override |
| `border-right-color` | `_PNT-BORDER-COLOR` | Per-side override |
| `border-bottom-color` | `_PNT-BORDER-COLOR` | Per-side override |
| `border-left-color` | `_PNT-BORDER-COLOR` | Per-side override |
| `border-style` | `_PNT-HAS-BORDER-STYLE?` | Only `"solid"` supported; anything else = no border |
| `color` | `_PNT-GET-COLOR` | Text foreground; border fallback |
| `font-size` | `_PNT-GET-FONT-SIZE` | Integer `px` only; default 16 |

---

## Public API

### PAINT-RENDER

```forth
PAINT-RENDER  ( box-root surf -- )
```

Top-level entry point.  Walk the entire box tree depth-first and
paint to `surf`.

For each box, in order:
1. If not a text box: paint background + borders via `PAINT-BOX`
2. If a text box: paint text via `PAINT-TEXT` (leaf — no children)
3. Otherwise: recurse into children

Boxes with `display:none` are skipped entirely.

### PAINT-BOX

```forth
PAINT-BOX  ( box surf -- )
```

Paint a single non-text box: background colour then borders.
Equivalent to:

```forth
2DUP PAINT-BG-COLOR  PAINT-BORDERS
```

### PAINT-BG-COLOR

```forth
PAINT-BG-COLOR  ( box surf -- )
```

Fill the **padding rectangle** of `box` with its `background-color`.
Does nothing if:
- No `background-color` property set
- Value is `"transparent"` or `0x00000000`
- Padding rect has zero width or height

### PAINT-BORDERS

```forth
PAINT-BORDERS  ( box surf -- )
```

Draw the four border edges as filled rectangles.  Each side is drawn
independently using the **border rectangle** coordinates and the
per-side border widths from `BOX-BORDER-T/R/B/L`.

Does nothing if:
- `border-style` is not set or not `"solid"`
- All border widths are zero

**Border geometry:**

```
┌──────────────────────────────┐  ← border-rect top (y)
│  TOP BORDER (full width)     │  height = border-top
├────┬────────────────┬────────┤
│ L  │                │   R    │
│ E  │   content /    │   I    │
│ F  │   padding      │   G    │
│ T  │   area         │   H    │
│    │                │   T    │
├────┴────────────────┴────────┤
│  BOTTOM BORDER (full width)  │  height = border-bottom
└──────────────────────────────┘
```

Top and bottom borders span the full width.  Left and right borders
fill the gap between top and bottom borders (no overlap at corners).

### PAINT-TEXT

```forth
PAINT-TEXT  ( box surf -- )
```

Render the text content of a text-flagged box.  Reads the text
string from the DOM node via `DOM-TEXT`, then calls `DRAW-TEXT`
with the box's content origin (`B.X`, `B.Y`).

Silently does nothing for non-text boxes or empty text.

- **Foreground:** from CSS `color` property, default `0x000000FF` (black)
- **Font size:** from CSS `font-size` property, default 16

### PAINT-CSS-COLOR

```forth
PAINT-CSS-COLOR  ( val-a val-u -- rgba flag )
```

Parse a CSS colour value string into a packed RGBA word.

| Input | Result |
|---|---|
| `"#FF0000"` | `0xFF0000FF -1` |
| `"#F00"` | `0xFF0000FF -1` |
| `"red"` | `0xFF0000FF -1` |
| `"transparent"` | `0x00000000 -1` |
| `"xyz"` | `0 0` |
| `""` (empty) | `0 0` |

Delegates to `CSS-PARSE-HEX-COLOR` for hex values and
`CSS-COLOR-FIND` for named colours.

**Packed RGBA format:**

$$\text{rgba} = (r \ll 24) \mathbin{|} (g \ll 16) \mathbin{|} (b \ll 8) \mathbin{|} \alpha$$

where $\alpha = \texttt{0xFF}$ for all parsed colours.

---

## Painting Algorithm

`PAINT-RENDER` implements a simplified CSS 2.1 Appendix E painting
order via a recursive depth-first walk:

```
PAINT-RENDER(box, surf):
    if box.display == none: return

    if box is NOT a text box:
        PAINT-BG-COLOR(box, surf)    ← step 1: background
        PAINT-BORDERS(box, surf)     ← step 3: borders

    if box IS a text box:
        PAINT-TEXT(box, surf)        ← step 5: inline content
        return                       ← text boxes are leaves

    for each child of box:           ← step 4: block children
        PAINT-RENDER(child, surf)
```

Steps 2 (background image) and 6 (outline) are reserved for future
implementation.

---

## Internals

### _PNT-GET-COLOR

```forth
_PNT-GET-COLOR  ( box prop-a prop-u default -- rgba )
```

Look up a CSS colour property on a box's DOM node via `DOM-STYLE@`.
If the property is not found or fails to parse, return `default`.

### _PNT-GET-FONT-SIZE

```forth
_PNT-GET-FONT-SIZE  ( box -- size )
```

Read `font-size` from the box's DOM node.  Parses the integer
prefix of the value (e.g. `"24px"` → `24`).  Returns `16` if
the property is missing or has no digits.

### _PNT-BORDER-COLOR

```forth
_PNT-BORDER-COLOR  ( box side-prop-a side-prop-u -- rgba )
```

Resolve the border colour for a specific side with a three-level
fallback chain:

1. Side-specific property (e.g. `"border-top-color"`)
2. Shorthand `"border-color"`
3. Foreground `"color"` (default `0x000000FF` = black)

### _PNT-HAS-BORDER-STYLE?

```forth
_PNT-HAS-BORDER-STYLE?  ( box -- flag )
```

Return true (`-1`) if the box has `border-style` set to `"solid"`.
Returns false (`0`) for any other value or if the property is
missing.

---

## Quick Reference

| Word | Stack | Description |
|---|---|---|
| `PAINT-RENDER` | `( box surf -- )` | Paint entire tree recursively |
| `PAINT-BOX` | `( box surf -- )` | Paint one box (bg + borders) |
| `PAINT-BG-COLOR` | `( box surf -- )` | Fill padding rect with background |
| `PAINT-BORDERS` | `( box surf -- )` | Draw four border edges |
| `PAINT-TEXT` | `( box surf -- )` | Render text content |
| `PAINT-CSS-COLOR` | `( a u -- rgba flag )` | Parse CSS colour string |
| `_PNT-GET-COLOR` | `( box a u def -- rgba )` | Look up colour property |
| `_PNT-GET-FONT-SIZE` | `( box -- size )` | Read font-size (default 16) |
| `_PNT-BORDER-COLOR` | `( box a u -- rgba )` | Resolve border colour |
| `_PNT-HAS-BORDER-STYLE?` | `( box -- flag )` | Check for solid border |

---

## Cookbook

### Render a simple red box

```forth
\ Set up DOM + box tree + layout
S" <div style='width:100px;height:80px;background-color:red'></div>"
DOM-PARSE-HTML
BOX-BUILD-TREE
DUP 320 240 LAYO-LAYOUT

\ Create surface & paint
320 240 SURF-CREATE
DUP 0xFFFFFFFF SURF-CLEAR    \ white background
SWAP OVER PAINT-RENDER
```

### Nested boxes with borders

```forth
S" <div style='width:200px;height:150px;padding:10px;background-color:#CCCCCC;border-width:2px;border-style:solid;border-color:#333333'>"
S" <div style='width:180px;height:60px;background-color:#336699'></div>"
S" </div>"
\ ... parse, build tree, layout, then PAINT-RENDER
```

### Parse a CSS colour without a DOM

```forth
S" #FF6600" PAINT-CSS-COLOR   \ → 0xFF6600FF -1
S" blue"    PAINT-CSS-COLOR   \ → 0x0000FFFF -1
S" invalid" PAINT-CSS-COLOR   \ → 0 0
```
