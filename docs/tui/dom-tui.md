# akashic-tui-dom-tui — DOM-to-TUI Node Mapping for KDOS / Megapad-64

Maps DOM element nodes to TUI **sidecar descriptors**.  Walks the
DOM tree, allocates a sidecar for each visible element, and resolves
CSS properties into character-cell attributes (fg/bg colour, border
style, text decoration, display mode, visibility, dimensions).

```forth
REQUIRE dom-tui.f
```

`PROVIDED akashic-tui-dom-tui` — safe to include multiple times.
Automatically loads `akashic-dom`, `akashic-dom-html5`,
`akashic-css`, `akashic-css-bridge`, `akashic-utils-string`,
`cell.f`, and `region.f`.

---

## Table of Contents

- [Design Overview](#design-overview)
- [Dependencies](#dependencies)
- [Sidecar Layout](#sidecar-layout)
- [Constants](#constants)
- [Sidecar Field Accessors](#sidecar-field-accessors)
- [Style Packing](#style-packing)
- [Color Resolution](#color-resolution)
- [Lifecycle — Attach / Detach / Refresh](#lifecycle)
- [Query Words](#query-words)
- [Style Override](#style-override)
- [Dirty Marking](#dirty-marking)
- [Convenience Wrappers](#convenience-wrappers)
- [Class Helpers](#class-helpers)
- [Guard Wrappers](#guard-wrappers)
- [Internal Words](#internal-words)
- [Quick Reference](#quick-reference)
- [Cookbook](#cookbook)

---

## Design Overview

| Principle | Detail |
|---|---|
| **One sidecar per element** | Every DOM element (type 1) receives a 72-byte sidecar during `DTUI-ATTACH`. Non-element nodes (text, document) are skipped. |
| **N.AUX storage** | Sidecar pointer is stored in the DOM node's `N.AUX` field. `DTUI-DETACH` zeroes all `N.AUX` fields. |
| **CSS resolution** | Inline styles are read via `DOM-STYLE@` → `DOM-COMPUTE-STYLE`. Properties resolved: `display`, `visibility`, `color`, `background-color`, `font-weight`, `font-style`, `text-decoration`, `border-style`, `width`, `height`. |
| **Packed style word** | FG (8 bits) + BG (8 bits) + cell attributes (16 bits) + border index (8 bits) packed into a single 64-bit cell. |
| **256-colour palette** | RGB values are mapped to xterm-256 via nearest-match over the 6×6×6 colour cube and 24-step grayscale ramp. |
| **Pool allocation** | Sidecar memory is carved from the DOM string pool (`_DCS-V`). No separate arena is needed. |

---

## Dependencies

```
dom-tui.f
├── dom/dom.f        (DOM core — nodes, attributes, tree walk)
├── dom/html5.f      (DOM-HTML-INIT — HTML/HEAD/BODY skeleton)
├── css/css.f        (CSS tokeniser / property constants)
├── css/bridge.f     (CSSB-APPLY-INLINE — inline style parsing)
├── utils/string.f   (STR-PARSE-TOKEN, STR-STR= — class helpers)
├── tui/cell.f       (CELL-A-* attribute flags)
└── tui/region.f     (screen region primitives)
```

---

## Sidecar Layout

Each sidecar is 72 bytes (9 cells of 8 bytes):

| Offset | Field | Description |
|--------|-------|-------------|
| +0 | `node` | Back-pointer to the DOM element node |
| +8 | `flags` | Bitfield: DIRTY / VISIBLE / BLOCK / HIDDEN / FOCUSABLE / GEOM-DIRTY |
| +16 | `row` | Computed screen row (set by layout engine) |
| +24 | `col` | Computed screen column |
| +32 | `width` | Width in character cells (from CSS `width` property) |
| +40 | `height` | Height in character cells (from CSS `height` property) |
| +48 | `style` | Packed style word (see [Style Packing](#style-packing)) |
| +56 | `draw-xt` | Custom draw execution token (0 = use default) |
| +64 | `udata` | User-defined data cell (application payload) |

---

## Constants

### Sidecar Size

| Constant | Value | Description |
|----------|-------|-------------|
| `DTUI-SC-SIZE` | 72 | Sidecar descriptor size in bytes |

### Flag Bits

| Constant | Value | Description |
|----------|-------|-------------|
| `DTUI-F-DIRTY` | 1 | Needs repaint |
| `DTUI-F-VISIBLE` | 2 | Element is visible (not `display:none`) |
| `DTUI-F-BLOCK` | 4 | `display:block` (else inline) |
| `DTUI-F-HIDDEN` | 8 | `visibility:hidden` (space reserved, not painted) |
| `DTUI-F-FOCUSABLE` | 16 | Can receive keyboard focus |
| `DTUI-F-GEOM-DIRTY` | 32 | Geometry changed — needs relayout |

### Border Style Indices

| Constant | Value | Box-drawing set |
|----------|-------|-----------------|
| `DTUI-BORDER-NONE` | 0 | No border |
| `DTUI-BORDER-SINGLE` | 1 | `─│┌┐└┘` |
| `DTUI-BORDER-DOUBLE` | 2 | `═║╔╗╚╝` |
| `DTUI-BORDER-ROUNDED` | 3 | `─│╭╮╰╯` |
| `DTUI-BORDER-HEAVY` | 4 | `━┃┏┓┗┛` |

### Default Colours

| Constant | Value | Description |
|----------|-------|-------------|
| `_DTUI-DEFAULT-FG` | 7 | White (palette index) |
| `_DTUI-DEFAULT-BG` | 0 | Black (palette index) |

---

## Sidecar Field Accessors

All accessors take a sidecar address.

### Getters — `( sc -- value )`

| Word | Field |
|------|-------|
| `DTUI-SC-NODE` | back-pointer to DOM node |
| `DTUI-SC-FLAGS` | flag bitfield |
| `DTUI-SC-ROW` | screen row |
| `DTUI-SC-COL` | screen column |
| `DTUI-SC-W` | width (cells) |
| `DTUI-SC-H` | height (cells) |
| `DTUI-SC-STYLE` | packed style word |
| `DTUI-SC-DRAW` | draw xt or 0 |
| `DTUI-SC-UDATA` | user data cell |

### Setters — `( value sc -- )`

| Word | Field |
|------|-------|
| `DTUI-SC-FLAGS!` | flag bitfield |
| `DTUI-SC-ROW!` | screen row |
| `DTUI-SC-COL!` | screen column |
| `DTUI-SC-W!` | width |
| `DTUI-SC-H!` | height |
| `DTUI-SC-STYLE!` | packed style word |
| `DTUI-SC-DRAW!` | draw xt |
| `DTUI-SC-UDATA!` | user data cell |

---

## Style Packing

A single 64-bit cell encodes foreground colour, background colour,
cell attributes, and border style:

```
bits  0– 7:  FG colour index  (0–255)
bits  8–15:  BG colour index  (0–255)
bits 16–31:  CELL-A-* attribute flags (bold, italic, underline, etc.)
bits 32–39:  border style index (DTUI-BORDER-*)
```

### `DTUI-PACK-STYLE` — `( fg bg attrs border -- packed )`

Pack four components into one cell.

### `DTUI-UNPACK-FG` — `( packed -- fg )`

Extract FG colour index (bits 0–7).

### `DTUI-UNPACK-BG` — `( packed -- bg )`

Extract BG colour index (bits 8–15).

### `DTUI-UNPACK-ATTRS` — `( packed -- attrs )`

Extract cell attribute flags (bits 16–31).

### `DTUI-UNPACK-BORDER` — `( packed -- border-idx )`

Extract border style index (bits 32–39).

---

## Color Resolution

### `DTUI-RESOLVE-COLOR` — `( r g b -- palette-index )`

Map an RGB triplet (each 0–255) to the nearest xterm-256 palette
entry.  Searches both the 6×6×6 colour cube (indices 16–231) and the
24-step grayscale ramp (indices 232–255), returning whichever is
closest by sum-of-absolute-differences.

---

## Lifecycle

### `DTUI-ATTACH` — `( doc -- )`

Walk the DOM tree depth-first starting from `D.HTML` (or
`DOM-FIRST-CHILD` of the document node if `D.HTML` is 0).
For every element node:

1. Carve a 72-byte sidecar from the string pool.
2. Resolve CSS properties into sidecar fields.
3. Store sidecar address in `N.AUX`.

Call once after building or loading a DOM tree.

### `DTUI-DETACH` — `( doc -- )`

Walk the DOM tree and zero every element's `N.AUX` field.
Sidecar memory remains in the pool until the arena is destroyed.
Must be called before destroying the DOM to avoid stale pointers.

### `DTUI-REFRESH` — `( doc -- )`

Re-resolve CSS properties into existing sidecars (after inline style
or class attribute changes).  Does **not** allocate new sidecars.

---

## Query Words

### `DTUI-SIDECAR` — `( node -- sidecar | 0 )`

Return the TUI sidecar for a DOM node, or 0 if none is attached.

### `DTUI-VISIBLE?` — `( node -- flag )`

True if the node has a sidecar with `DTUI-F-VISIBLE` set.

---

## Style Override

### `DTUI-STYLE!` — `( node fg bg attrs -- )`

Override the resolved FG, BG, and cell attributes for one node's
sidecar.  Preserves the existing border style index.  Does nothing
if the node has no sidecar (e.g. `display:none`).

---

## Dirty Marking

Dirty marking is explicit — the application (or convenience wrappers)
must mark nodes dirty after mutation.  The paint engine checks and
clears the flag.

### `DTUI-MARK-DIRTY` — `( node -- )`

Set `DTUI-F-DIRTY` on the node's sidecar.  Does nothing if the node
has no sidecar.

### `DTUI-MARK-GEOM-DIRTY` — `( node -- )`

Set both `DTUI-F-DIRTY` and `DTUI-F-GEOM-DIRTY`.  Use when a
mutation affects position or size (e.g. width, height, display change).

### `DTUI-CLEAR-DIRTY` — `( sc -- )`

Clear the `DTUI-F-DIRTY` flag on a sidecar.  Called automatically by
the paint engine after painting a node.

### `DTUI-CLEAR-GEOM-DIRTY` — `( sc -- )`

Clear the `DTUI-F-GEOM-DIRTY` flag.  Called automatically by
`DREN-RELAYOUT` after a full relayout.

---

## Convenience Wrappers

These combine a DOM mutation with automatic dirty marking in one call.

### `DTUI-SET-TEXT!` — `( node txt-a txt-u -- )`

Call `DOM-SET-TEXT` then `DTUI-MARK-DIRTY`.  Use for updating text
content without forgetting to dirty the node.

### `DTUI-ATTR!` — `( node name-a name-u val-a val-u -- )`

Call `DOM-ATTR!` then `DTUI-MARK-DIRTY`.  Use for setting any DOM
attribute with auto-dirty.

### `DTUI-ATTR-DEL!` — `( node name-a name-u -- )`

Call `DOM-ATTR-DEL` then `DTUI-MARK-DIRTY`.

---

## Class Helpers

### `DTUI-CLASS-ADD` — `( node addr len -- )`

Append a CSS class to the node's existing `class` attribute
(space-separated) and re-resolve its sidecar.  If no class attribute
exists yet, simply sets it.  Does not check for duplicates.
Overflow beyond 256 bytes is silently ignored.

### `DTUI-CLASS-REMOVE` — `( node addr len -- )`

Remove a single CSS class from the node's space-separated `class`
attribute.  Walks the existing class string token by token using
`STR-PARSE-TOKEN`, skips tokens matching the target (via `STR-STR=`),
and rebuilds the result.  Deletes the `class` attribute entirely if
the result is empty.  Re-resolves the sidecar afterwards.

---

## Guard Wrappers

When `GUARDED` is defined, all public words are wrapped with a
single guard (`_dtui-guard`) for thread-safe access.  The guard
is a mutual-exclusion lock from `concurrency/guard.f`.

Protected words: `DTUI-ATTACH`, `DTUI-DETACH`, `DTUI-REFRESH`,
`DTUI-SIDECAR`, `DTUI-VISIBLE?`, `DTUI-STYLE!`,
`DTUI-RESOLVE-COLOR`, `DTUI-CLASS-ADD`, `DTUI-CLASS-REMOVE`,
`DTUI-PACK-STYLE`, `DTUI-UNPACK-FG`, `DTUI-UNPACK-BG`,
`DTUI-UNPACK-ATTRS`, `DTUI-UNPACK-BORDER`,
`DTUI-MARK-DIRTY`, `DTUI-MARK-GEOM-DIRTY`,
`DTUI-SET-TEXT!`, `DTUI-ATTR!`, `DTUI-ATTR-DEL!`,
`DTUI-SC-UDATA`, `DTUI-SC-UDATA!`.

---

## Internal Words

| Word | Stack | Description |
|------|-------|-------------|
| `_DTUI-SC-ALLOC` | `( -- addr )` | Allocate one sidecar from pool |
| `_DTUI-CARVE` | `( -- )` | Initial pool carve from string-pool free space |
| `_DTUI-RESOLVE-NODE` | `( node sc -- )` | Full CSS → sidecar resolution |
| `_DTUI-RESOLVE-DISPLAY` | `( node -- flags )` | Parse `display` property |
| `_DTUI-RESOLVE-VISIBILITY` | `( node flags -- flags' )` | Parse `visibility` |
| `_DTUI-RESOLVE-FG` | `( node -- index )` | CSS `color` → palette index |
| `_DTUI-RESOLVE-BG` | `( node -- index )` | CSS `background-color` → palette index |
| `_DTUI-RESOLVE-ATTRS` | `( node -- attrs )` | CSS text properties → CELL-A-* |
| `_DTUI-RESOLVE-BORDER` | `( node -- idx )` | CSS `border-style` → DTUI-BORDER-* |
| `_DTUI-RESOLVE-DIM` | `( node prop-a prop-u -- n\|0 )` | CSS dimension → integer |
| `_DTUI-PARSE-DIM` | `( val-a val-u -- n )` | Strip "px"/"ch"/"em" suffix, parse int |
| `_DPD-TRIM` | `( addr u -- addr u' )` | Trim trailing non-digit chars |
| `_DTUI-PARSE-CSS-COLOR` | `( val-a val-u -- index )` | CSS colour value → palette |
| `_DTUI-PARSE-DISPLAY` | `( val-a val-u -- flags )` | "none"/"block"/"inline" → flags |

---

## Quick Reference

```
DTUI-ATTACH        ( doc -- )              Walk tree, allocate sidecars
DTUI-DETACH        ( doc -- )              Clear all N.AUX fields
DTUI-REFRESH       ( doc -- )              Re-resolve CSS into existing sidecars
DTUI-SIDECAR       ( node -- sc|0 )        Get sidecar for node
DTUI-VISIBLE?      ( node -- flag )        Sidecar has VISIBLE flag?
DTUI-STYLE!        ( node fg bg a -- )     Override fg/bg/attrs in sidecar
DTUI-RESOLVE-COLOR ( r g b -- idx )        RGB → xterm-256 palette index
DTUI-PACK-STYLE    ( fg bg a b -- p )      Pack style into one cell
DTUI-UNPACK-FG     ( p -- fg )             Extract FG from packed
DTUI-UNPACK-BG     ( p -- bg )             Extract BG from packed
DTUI-UNPACK-ATTRS  ( p -- attrs )          Extract attrs from packed
DTUI-UNPACK-BORDER ( p -- border )         Extract border index from packed
DTUI-MARK-DIRTY    ( node -- )             Set DIRTY on sidecar
DTUI-MARK-GEOM-DIRTY ( node -- )           Set DIRTY + GEOM-DIRTY
DTUI-CLEAR-DIRTY   ( sc -- )               Clear DIRTY flag
DTUI-CLEAR-GEOM-DIRTY ( sc -- )            Clear GEOM-DIRTY flag
DTUI-SET-TEXT!     ( node txt-a u -- )     DOM-SET-TEXT + mark dirty
DTUI-ATTR!         ( node na nu va vu -- ) DOM-ATTR! + mark dirty
DTUI-ATTR-DEL!     ( node na nu -- )       DOM-ATTR-DEL + mark dirty
DTUI-CLASS-ADD     ( node a u -- )         Append class + re-resolve
DTUI-CLASS-REMOVE  ( node a u -- )         Remove class token + re-resolve
DTUI-SC-NODE       ( sc -- node )          Read back-pointer
DTUI-SC-FLAGS      ( sc -- fl )            Read flags
DTUI-SC-ROW        ( sc -- row )           Read row
DTUI-SC-COL        ( sc -- col )           Read col
DTUI-SC-W          ( sc -- w )             Read width
DTUI-SC-H          ( sc -- h )             Read height
DTUI-SC-STYLE      ( sc -- packed )        Read packed style
DTUI-SC-DRAW       ( sc -- xt|0 )          Read draw hook
DTUI-SC-UDATA      ( sc -- udata )         Read user data cell
DTUI-SC-UDATA!     ( val sc -- )           Write user data cell
```

---

## Cookbook

### Attach TUI mapping to a DOM document

```forth
\ Create document
arena 64 64 DOM-DOC-NEW CONSTANT my-doc
DOM-HTML-INIT

\ Build some elements …
S" div" DOM-CREATE-ELEMENT CONSTANT my-div
my-div S" style" S" color:red;display:block" DOM-ATTR!
my-div DOM-BODY DOM-APPEND

\ Attach sidecars
my-doc DTUI-ATTACH
```

### Read resolved properties

```forth
my-div DTUI-SIDECAR DTUI-SC-FLAGS  DTUI-F-BLOCK AND  .  \ 4 if block
my-div DTUI-SIDECAR DTUI-SC-STYLE DTUI-UNPACK-FG .     \ FG palette index
my-div DTUI-SIDECAR DTUI-SC-W .                         \ width (0 if unset)
```

### Override style at runtime

```forth
my-div 196 21 CELL-A-BOLD  DTUI-STYLE!   \ red FG, blue BG, bold
```

### Update after style change

```forth
my-div S" style" S" color:green" DOM-ATTR!
my-doc DTUI-REFRESH
my-div DTUI-SIDECAR DTUI-SC-STYLE DTUI-UNPACK-FG .   \ new FG index
```

### Mark dirty and repaint

```forth
\ After changing text content:
my-div S" New text" DTUI-SET-TEXT!    \ mutate + auto-dirty

\ Or manually:
my-div S" style" S" color:blue" DOM-ATTR!
my-div DTUI-MARK-DIRTY

\ For geometry changes (width/height):
my-div DTUI-MARK-GEOM-DIRTY
```

### Store application data in sidecar

```forth
my-div DTUI-SIDECAR  42 SWAP DTUI-SC-UDATA!   \ store 42
my-div DTUI-SIDECAR  DTUI-SC-UDATA .           \ prints 42
```

### Clean up before destroying DOM

```forth
my-doc DTUI-DETACH
```

---

## See Also

- [dom.md](../dom/dom.md) — DOM core (nodes, attributes, tree walk)
- [html5.md](../dom/html5.md) — `DOM-HTML-INIT` skeleton
- [event.md](../dom/event.md) — W3C event dispatch
- [uidl-tui.md](uidl-tui.md) — UIDL-TUI backend (alternative path, no DOM)
- [cell.md](cell.md) — Cell attribute flags (`CELL-A-*`)
- [screen.md](screen.md) — Screen abstraction
- [region.md](region.md) — Region primitives
