# akashic-tui-dom-render — DOM-to-TUI Layout & Paint for KDOS / Megapad-64

Walks the DOM tree with attached DTUI sidecars, computes simplified
block/inline character-cell layout within a target region, and paints
the results into the TUI screen back buffer using `draw.f` / `box.f`
primitives.

```forth
REQUIRE dom-render.f
```

`PROVIDED akashic-tui-dom-render` — safe to include multiple times.
Automatically loads `akashic-tui-dom-tui`, `draw.f`, `box.f`,
`region.f`, and `screen.f`.

---

## Table of Contents

- [Design Overview](#design-overview)
- [Dependencies](#dependencies)
- [Layout Model](#layout-model)
- [Public API](#public-api)
- [Internal State](#internal-state)
- [Border Mapping](#border-mapping)
- [Text Helpers](#text-helpers)
- [Guard Wrappers](#guard-wrappers)
- [Quick Reference](#quick-reference)
- [Cookbook](#cookbook)

---

## Design Overview

| Principle | Detail |
|---|---|
| **Sidecar-driven** | Layout reads CSS-resolved values from DTUI sidecars (width, height, border, display mode, visibility) and writes computed row/col/W/H back. |
| **Block / inline flow** | Block elements stack vertically; inline elements flow side-by-side on the current line. Mixed flow triggers automatic line breaks. |
| **Region-scoped** | All positions are relative to a TUI region (`RGN-NEW`). Layout respects region width/height. |
| **DFS paint order** | Paint walks depth-first: background → border → text → children. Later siblings overdraw earlier ones. |
| **R-stack recursion** | 8 global layout variables are saved/restored on the return stack during child recursion, making nested layout safe without dynamic allocation. |
| **One-pass layout** | A single depth-first traversal computes all positions. No second pass. |

---

## Dependencies

```
dom-render.f
├── tui/dom-tui.f   (DTUI-ATTACH — sidecar allocation + CSS resolution)
├── tui/draw.f       (DRW-TEXT, DRW-FILL-RECT, DRW-STYLE!)
├── tui/box.f        (BOX-DRAW, BOX-SINGLE, etc.)
├── tui/region.f     (RGN-USE, RGN-ROOT, RGN-W, RGN-H)
└── tui/screen.f     (SCR-USE, SCR-GET)
```

Transitive: `dom.f`, `html5.f`, `css.f`, `bridge.f`, `cell.f`,
`utf8.f`, `string.f`, `core.f`, `html.f`.

---

## Layout Model

### Block Flow

Block elements (`DTUI-F-BLOCK` set in sidecar flags) behave like
CSS `display:block`:

1. If the cursor is past the left margin (inline content on the
   current line), force a newline first.
2. Width defaults to the full available content area unless an
   explicit CSS `width` is set.
3. Height defaults to 1 row (or 3 with border) unless explicit
   CSS `height` is set.
4. After the element, the cursor advances down by the element's
   height.

### Inline Flow

Inline elements (`DTUI-F-BLOCK` clear) flow left-to-right:

1. Width is the text content width (UTF-8 codepoint count) plus
   border insets.
2. Elements share the same row until the line runs out of space.
3. After each element, the cursor advances right by the element's
   width.
4. The tallest element on the line determines the line height.

### Border Insets

When a border style is set (`border-style:solid`, etc.), the layout
adds a 1-cell inset on each side:

- Width: content width + 2 (left + right border)
- Height: content height + 2 (top + bottom border)
- Children are positioned 1 cell inward from the parent's top-left.

### display:none / visibility:hidden

- `display:none` (`DTUI-F-VISIBLE` clear): element is skipped
  entirely — occupies no space, not painted.
- `visibility:hidden` (`DTUI-F-HIDDEN` set): element reserves its
  space in layout but is not painted.

---

## Public API

### `DREN-LAYOUT` — `( doc rgn -- )`

Compute character-cell layout for the entire DOM tree within the
given region.  Sets row/col/W/H in every element's sidecar.

- `doc` — DOM document created with `DOM-DOC-NEW`
- `rgn` — Region created with `RGN-NEW` (defines viewport dimensions)

Walks from `D.BODY` downward.  Skips the HTML/HEAD subtree.

### `DREN-PAINT` — `( doc -- )`

Paint all laid-out nodes into the screen back buffer.  Activates
the region stored during `DREN-LAYOUT` for clipping, then walks
the tree depth-first: background (space fill) → border (box draw) →
text → children.

`DREN-LAYOUT` must have been called first.

### `DREN-RENDER` — `( doc rgn -- )`

Layout + paint in one call.  Equivalent to:

```forth
2DUP DREN-LAYOUT  DROP DREN-PAINT
```

### `DREN-RELAYOUT` — `( doc rgn -- )`

Re-layout after DOM mutation or viewport resize.  Same as
`DREN-LAYOUT` — recomputes all positions from scratch.

### `DREN-DIRTY?` — `( doc -- flag )`

Returns true if any sidecar in the tree has the `DTUI-F-DIRTY`
flag set.  Uses `DOM-WALK-DEPTH` to scan from BODY.

### `DREN-PAINT-NODE` — `( node -- )`

Paint a single element node and its children.  The caller must
have activated the appropriate region with `RGN-USE` first.

---

## Internal State

Layout uses 8 global VARIABLEs, all saved/restored per recursion
level via the return stack:

| Variable | Purpose |
|----------|---------|
| `_DREN-RGN` | Target region address |
| `_DREN-VW` | Available content width for current level |
| `_DREN-VH` | Viewport height (from region) |
| `_DREN-ROW` | Current cursor row (absolute) |
| `_DREN-COL` | Current cursor column (absolute) |
| `_DREN-LINE-H` | Tallest element on the current inline line |
| `_DREN-LMAR` | Left margin of current content area (absolute) |
| `_DREN-ND` | Current node being laid out |
| `_DREN-SC` | Current sidecar address |
| `_DREN-FL` | Cached sidecar flags |

---

## Border Mapping

`_DREN-BSTYLES` is a 5-entry table mapping DTUI border indices to
`BOX-*` style addresses:

| Index | Border | BOX-* Style |
|-------|--------|-------------|
| 0 | none | 0 (no draw) |
| 1 | single | `BOX-SINGLE` |
| 2 | double | `BOX-DOUBLE` |
| 3 | rounded | `BOX-ROUND` |
| 4 | heavy | `BOX-HEAVY` |

### `_DREN-BOX-STYLE` — `( border-idx -- style-addr|0 )`

Look up the BOX-* style address from a border index.

---

## Text Helpers

### `_DREN-COLLECT-TEXT` — `( node -- addr len )`

Concatenate text content from immediate text-node children into a
1024-byte buffer (`_DREN-TXTBUF`).  Overflow is silently truncated.

### `_DREN-TEXT-WIDTH` — `( addr len -- n )`

Count character cells (UTF-8 codepoints) in a string.
Delegates to `UTF8-LEN`.

---

## Guard Wrappers

When `GUARDED` is defined and a guard module is loaded, all public
words are wrapped with `WITH-GUARD` for concurrency safety:

- `DREN-LAYOUT`, `DREN-PAINT`, `DREN-RENDER`, `DREN-RELAYOUT`,
  `DREN-DIRTY?`, `DREN-PAINT-NODE`

---

## Quick Reference

| Word | Stack | Description |
|------|-------|-------------|
| `DREN-LAYOUT` | `( doc rgn -- )` | Compute layout for entire tree |
| `DREN-PAINT` | `( doc -- )` | Paint tree into back buffer |
| `DREN-RENDER` | `( doc rgn -- )` | Layout + paint in one call |
| `DREN-RELAYOUT` | `( doc rgn -- )` | Re-layout (same as DREN-LAYOUT) |
| `DREN-DIRTY?` | `( doc -- flag )` | Any sidecar dirty? |
| `DREN-PAINT-NODE` | `( node -- )` | Paint single node subtree |

---

## Cookbook

### Basic Render

```forth
\ Create document and screen
524288 A-XMEM ARENA-NEW DROP CONSTANT my-arena
my-arena 64 64 DOM-DOC-NEW CONSTANT my-doc
DOM-HTML-INIT
80 24 SCR-NEW CONSTANT my-scr
my-scr SCR-USE
0 0 24 80 RGN-NEW CONSTANT my-rgn

\ Build DOM
S" div" DOM-CREATE-ELEMENT CONSTANT my-div
S" Hello, world!" DOM-CREATE-TEXT CONSTANT my-txt
my-txt my-div DOM-APPEND
my-div DOM-BODY DOM-APPEND

\ Attach sidecars (CSS → sidecar fields)
my-doc DTUI-ATTACH

\ Layout and paint
my-doc my-rgn DREN-RENDER

\ Show on terminal
SCR-FLUSH
```

### Relayout After Mutation

```forth
\ After adding / removing DOM nodes:
my-doc DTUI-REFRESH     \ re-resolve CSS on changed nodes
my-doc my-rgn DREN-RELAYOUT
my-doc DREN-PAINT
SCR-FLUSH
```

### Check if Repaint Needed

```forth
my-doc DREN-DIRTY? IF
    my-doc my-rgn DREN-RENDER
    SCR-FLUSH
THEN
```

### Partial Update

```forth
my-rgn RGN-USE
my-div DREN-PAINT-NODE
RGN-ROOT
SCR-FLUSH
```
