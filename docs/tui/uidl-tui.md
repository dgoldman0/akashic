# akashic/tui/uidl-tui.f — UIDL TUI Backend

**Layer:** 8  
**Lines:** ~2875  
**Prefix:** `UTUI-` (public), `_UTUI-` (internal)  
**Provider:** `akashic-tui-uidl-tui`  
**Dependencies:** `uidl.f`, `uidl-chrome.f`, `state-tree.f`, `lel.f`,
`screen.f`, `draw.f`, `box.f`, `region.f`, `layout.f`, `keys.f`,
`widgets/tree.f`, `css/css.f`, `color.f`

## Overview

The TUI rendering backend for UIDL.  Installs real `render-xt`,
`event-xt`, and `layout-xt` implementations into the Element Registry,
then provides focus management, hit-testing, dirty-rect repaint,
action dispatch, shortcut registration, and the subscription-driven
reactive loop.  Operates directly on the UIDL element tree with no
DOM intermediary.

```forth
REQUIRE tui/uidl-tui.f
```

`PROVIDED akashic-tui-uidl-tui` — safe to include multiple times.

---

## Table of Contents

- [Design Overview](#design-overview)
- [Sidecar Layout](#sidecar-layout)
- [Sidecar Field Accessors](#sidecar-field-accessors)
- [Style Packing](#style-packing)
- [Proxy Region](#proxy-region)
- [Widget Materialization](#widget-materialization)
- [Lifecycle](#lifecycle)
- [Focus Management](#focus-management)
- [Hit Testing](#hit-testing)
- [Paint & Layout](#paint--layout)
- [Event Dispatch](#event-dispatch)
- [Dialog Management](#dialog-management)
- [Actions & Shortcuts](#actions--shortcuts)
- [Dynamic DOM Mutation](#dynamic-dom-mutation)
- [Attribute Mutation](#attribute-mutation)
- [Widget Attachment](#widget-attachment)
- [Element Region Accessor](#element-region-accessor)
- [Automatic Dirty Propagation](#automatic-dirty-propagation)
- [CSS Style Attributes](#css-style-attributes)
- [Element-Specific Rendering](#element-specific-rendering)
- [Guard Wrappers](#guard-wrappers)
- [Quick Reference](#quick-reference)
- [Cookbook](#cookbook)
- [See Also](#see-also)

---

## Design Overview

| Principle | Detail |
|---|---|
| **One sidecar per element** | Every UIDL element receives an 80-byte sidecar in a parallel array, indexed by pool position. |
| **No DOM intermediary** | Unlike `dom-tui.f`, this backend reads UIDL elements directly — no N.AUX, no DOM node walk. |
| **Adapter, not materialization** | Most widget types (status, split, scroll) are rendered inline by adapter words that read UIDL attributes. Only `tree` and `tabs` allocate real widget state. |
| **Sidecar wptr** | The `+48` cell in each sidecar holds an optional widget-struct pointer (tree widget, input, textarea, manually attached widget) or mini state block (tabs active index). Zero means "no widget state". |
| **Proxy region** | A single static 40-byte region (`_UTUI-PROXY-RGN`) is synced from sidecar geometry before calling widget `_*-DRAW` / `_*-HANDLE`. Safe because the TUI is single-threaded. |
| **Dynamic DOM** | `UTUI-ADD-ELEM` and `UTUI-REMOVE-ELEM` wrap the base UIDL tree operations with sidecar allocation, style resolution, materialization, and dirty propagation. Apps manipulate the tree like JavaScript's `appendChild` / `removeChild`. |
| **Auto-dirty** | `_UTUI-NEEDS-PAINT` flag is set by any DOM / widget mutation. The shell converts this to `ASHELL-DIRTY!` at tick and paint time — apps never call `ASHELL-DIRTY!`. |
| **Packed style** | FG (8 bits) + BG (8 bits) + attrs (8 bits) + text-align (2 bits) + position (2 bits) + z-index (8 bits) packed into one cell at `+32`. |
| **CSS inheritance** | `_UTUI-RESOLVE-STYLES-REC` propagates inheritable properties (fg, bg, attrs, text-align — bits 0-25) from parent to child before resolving the child's `style=`. Non-inheritable properties (position, z-index) are preserved from prelayout. |
| **Registry patching** | `UTUI-INSTALL-XTS` writes render/event/layout XTs into Element Registry definitions. Each chrome element type gets its own adapter. |
| **Guard safety** | When `GUARDED` is defined, all public words are serialized through `_utui-guard`. |

---

## Sidecar Layout

Each sidecar is 80 bytes (10 cells), stored in the parallel array
`_UTUI-SIDECARS` (capacity: 256 elements).

| Offset | Field | Type | Description |
|--------|-------|------|-------------|
| +0 | `row` | u | Computed screen row |
| +8 | `col` | u | Computed screen column |
| +16 | `width` | u | Width in character cells |
| +24 | `height` | u | Height in character cells |
| +32 | `style` | packed | FG(8), BG(8), attrs(8), text-align(2), position(2), z-index(8) |
| +40 | `flags` | bitfield | HAS / VIS / FOC / HIDE / overflow-clip |
| +48 | `wptr` | address | Widget struct pointer or mini state block (0 = none) |
| +56 | `padding` | packed | PT(8), PR(8), PB(8), PL(8) in bits 0-31 |
| +64 | `offsets` | packed | top(16s), right(16s), bottom(16s), left(16s) |
| +72 | `margin` | packed | MT(8), MR(8), MB(8), ML(8) in bits 0-31 |

### Sidecar Flag Bits

| Constant | Value | Description |
|----------|-------|-------------|
| `_UTUI-SCF-HAS` | 1 | Sidecar allocated |
| `_UTUI-SCF-VIS` | 2 | Visible |
| `_UTUI-SCF-FOC` | 4 | Focused |
| `_UTUI-SCF-HIDE` | 8 | display:none |

### Element → Sidecar Mapping

```forth
_UTUI-SC-IDX   ( elem -- idx )   \ (elem - _UDL-ELEMS) / _UDL-ELEMSZ
_UTUI-SIDECAR  ( elem -- sc )    \ idx * 80 + _UTUI-SIDECARS
```

`_UTUI-ELEM-BASE` is set to `_UDL-ELEMS` during `UTUI-LOAD`.

---

## Sidecar Field Accessors

All take a sidecar address.

### Getters — `( sc -- value )`

| Word | Field |
|------|-------|
| `_UTUI-SC-ROW@` | screen row |
| `_UTUI-SC-COL@` | screen column |
| `_UTUI-SC-W@` | width |
| `_UTUI-SC-H@` | height |
| `_UTUI-SC-STYLE@` | packed style |
| `_UTUI-SC-FLAGS@` | flags |
| `_UTUI-SC-WPTR@` | widget pointer / state block |

### Setters — `( value sc -- )`

| Word | Field |
|------|-------|
| `_UTUI-SC-ROW!` | screen row |
| `_UTUI-SC-COL!` | screen column |
| `_UTUI-SC-W!` | width |
| `_UTUI-SC-H!` | height |
| `_UTUI-SC-STYLE!` | packed style |
| `_UTUI-SC-FLAGS!` | flags |
| `_UTUI-SC-WPTR!` | widget pointer / state block |

### Predicates

| Word | Stack | Description |
|------|-------|-------------|
| `_UTUI-SC-VIS?` | `( sc -- flag )` | Is the VIS flag set? |

---

## Style Packing

A single cell encodes foreground, background, attributes, and
layout-affecting properties:

```
bits  0– 7:  FG colour index   (0–255)
bits  8–15:  BG colour index   (0–255)
bits 16–23:  Cell attributes    (bold, italic, etc.)
bits 24–25:  text-align         (0=left, 1=center, 2=right)
bits 26–27:  position           (0=static, 1=absolute, 2=fixed)
bits 28–35:  z-index            (unsigned 0–255)
```

| Word | Stack | Description |
|------|-------|-------------|
| `_UTUI-PACK-STYLE` | `( fg bg attrs -- packed )` | Pack three values (bits 0-23) |
| `_UTUI-UNPACK-STYLE` | `( packed -- fg bg attrs )` | Extract fg, bg, attrs |
| `_UTUI-APPLY-STYLE` | `( sc -- )` | Read sidecar style and call `DRW-STYLE!` |
| `_UTUI-INHERIT-MASK` | `( -- mask )` | Constant `0x03FFFFFF` — inheritable bits |

Default style: `253 236 0` (light gray on dark gray, no attributes).

### CSS Inheritance

`_UTUI-RESOLVE-STYLES-REC` performs a preorder depth-first walk.
After resolving a parent's own `style=`, the inheritable bits
(fg, bg, attrs, text-align — bits 0-25) are copied into each
child's sidecar *before* resolving the child's `style=`.
Non-inheritable properties (position bits 26-27, z-index bits 28-35)
are preserved from the prelayout pass.

This means:
- A child with no `style=` inherits its parent's fg/bg/attrs/text-align
- A child with `style="color:1"` overrides only fg; bg and attrs inherit
- Inheritance flows through arbitrary depth
- The root element receives `_UTUI-DEFAULT-STYLE` (fg=253, bg=236, no attrs)

### Public Style Accessors

Convenience words to read the resolved style from an element
(available after `UTUI-LOAD` returns):

| Word | Stack | Description |
|------|-------|-------------|
| `UTUI-SC-FG@` | `( elem -- fg )` | Computed foreground colour (0-255) |
| `UTUI-SC-BG@` | `( elem -- bg )` | Computed background colour (0-255) |
| `UTUI-SC-ATTRS@` | `( elem -- attrs )` | Computed attributes (bold, etc.) |

```forth
S" status" UTUI-BY-ID ?DUP IF
    DUP UTUI-SC-FG@ .    \ e.g. 75
    UTUI-SC-BG@ .        \ e.g. 234
THEN
```

---

## Proxy Region

```forth
CREATE _UTUI-PROXY-RGN  _RGN-DESC-SIZE ALLOT    \ 40 bytes
```

A single static region shared by all materialized widgets.  Before
calling any widget's `_*-DRAW` or `_*-HANDLE`, the proxy is synced
from the current sidecar:

```forth
_UTUI-SYNC-PROXY  ( sc -- )
```

Copies row, col, height, width from the sidecar into
`_UTUI-PROXY-RGN`.  The proxy is then passed to `RGN-USE` so
widget draw code operates in region-relative coordinates.

Tree and other materialized widgets store `_UTUI-PROXY-RGN` as
their `WDG-REGION` (+8).

---

## Widget Materialization

Two types of UIDL elements need heap-allocated state beyond the
sidecar:

| Element | wptr contents | Size | Lifecycle |
|---------|---------------|------|-----------|
| `<tree>` | Full `TREE-NEW` widget struct | 112 bytes | `TREE-NEW` at load, `TREE-FREE` at detach |
| `<tabs>` | 8-byte state block (1 cell: active index) | 8 bytes | `ALLOCATE` at load, `FREE` at detach |
| `<input>` | `INP-NEW` widget struct + 256-byte buffer | varies | `INP-NEW` at load/add, free buffer+struct at detach/remove |
| `<textarea>` | `TXTA-NEW` widget struct + 4096-byte buffer | varies | `TXTA-NEW` at load/add, free buffer+struct at detach/remove |
| `<region>` (manual) | Any widget attached via `UTUI-WIDGET-SET` | varies | App manages creation; `_UTUI-DEMATERIALIZE-ONE` frees by type |

All other element types (status, split, scroll, dialog, etc.) use
inline adapters that read UIDL attributes directly — `wptr` stays 0.

### _UTUI-MATERIALIZE-ONE — `( elem -- )`

Materialize a single element by type dispatch.  Used by both the bulk
`_UTUI-MATERIALIZE` walk and the dynamic `UTUI-ADD-ELEM`.

| Type | Action |
|------|--------|
| tree | Sync proxy region, `TREE-NEW` with 4 UIDL callbacks, store at wptr |
| input | Allocate 256-byte buffer, `INP-NEW`, set text=/placeholder= attrs |
| textarea | Allocate 4096-byte buffer, `TXTA-NEW`, set text= attr |
| tabs | Allocate 8 bytes, zero (active = 0) |
| other | No-op |

### _UTUI-DEMATERIALIZE-ONE — `( elem -- )`

Free the widget attached to a single element.  Used by both the bulk
`_UTUI-DEMATERIALIZE` and `UTUI-REMOVE-ELEM`.

| Type | Action |
|------|--------|
| tree | `TREE-FREE` |
| input / textarea | `FREE` buffer (widget+40), `FREE` descriptor |
| other | `FREE` (generic heap block) |

Always zeroes the wptr cell after freeing.

### _UTUI-MATERIALIZE — `( -- )`

DFS walk of the UIDL tree after layout.  For each element:
- **tree:** syncs proxy region, calls `TREE-NEW` with four UIDL
  tree-walk callbacks (`_UTUI-TREE-CHILD`, `_UTUI-TREE-NEXT`,
  `_UTUI-TREE-LABEL`, `_UTUI-TREE-LEAF?`), stores widget at wptr.
- **tabs:** allocates 8 bytes, zeroes it (active = 0), stores at wptr.

Called by `UTUI-LOAD` after `UTUI-RELAYOUT`.

### _UTUI-DEMATERIALIZE — `( -- )`

DFS walk.  For each element whose wptr ≠ 0:
- **tree:** calls `TREE-FREE`.
- **other:** calls `FREE DROP`.
- Zeroes the wptr cell.

Called by `UTUI-DETACH` before `_UTUI-SC-CLEAR-ALL`.

### UIDL Tree Callbacks

These adapt UIDL traversal to the tree widget's callback protocol:

| Word | Stack | Description |
|------|-------|-------------|
| `_UTUI-TREE-CHILD` | `( node -- child\|0 )` | → `UIDL-FIRST-CHILD` |
| `_UTUI-TREE-NEXT` | `( node -- sib\|0 )` | → `UIDL-NEXT-SIB` |
| `_UTUI-TREE-LABEL` | `( node -- addr len )` | `label=` attr, fallback `text=`, fallback `"?"` |
| `_UTUI-TREE-LEAF?` | `( node -- flag )` | `UIDL-FIRST-CHILD 0=` |

---

## Lifecycle

### UTUI-LOAD — `( xml-a xml-u rgn -- flag )`

Parse a UIDL XML document and prepare the TUI backend:

1. Store root region
2. Call `UIDL-PARSE`
3. Set `_UTUI-ELEM-BASE` to pool base
4. Clear sidecars and action table
5. Run `UTUI-RELAYOUT` (compute geometry for all elements)
6. Run `_UTUI-MATERIALIZE` (allocate tree/tabs state)
7. Wire subscriptions (`_UTUI-WIRE-SUBS`)
8. Set initial focus via `UTUI-FOCUS-NEXT`

Returns `-1` on success, `0` on parse failure.

### UTUI-DETACH — `( -- )`

Tear down the TUI backend:

1. Run `_UTUI-DEMATERIALIZE` (free tree/tabs state)
2. Clear sidecars
3. Clear action table and shortcut table
4. Reset subscriptions
5. Zero focus, loaded flag, root region

### UTUI-BIND-STATE — `( st -- )`

Bind a state-tree instance.  All `bind=` and `when=` expressions
will evaluate against this state tree.

### UTUI-INSTALL-XTS — `( -- )`

Write render/event/layout execution tokens into the Element Registry
for all chrome types (tabs, split, status, tree, scroll, dialog,
menu, toast, etc.).  Called once at load time.

### UTUI-WIDGET@ — `( elem -- wptr | 0 )`

Return the widget struct pointer stored in the element's sidecar
`wptr` cell (+48).  Returns 0 if the element has no materialized
widget.  Useful for accessing widget-specific state (e.g. obtaining
a textarea's cursor position via `TXTA-CURSOR-LINE`).

> **Note:** Widget pointers are only valid after the first
> `UTUI-PAINT` call, which triggers materialization.  Calling
> `UTUI-WIDGET@` before painting returns 0.

---

## Focus Management

| Word | Stack | Description |
|------|-------|-------------|
| `UTUI-FOCUS` | `( -- elem\|0 )` | Get currently focused element |
| `UTUI-FOCUS!` | `( elem -- )` | Set focus to element; updates sidecar FOC flags |
| `UTUI-FOCUS-NEXT` | `( -- )` | Advance focus to next focusable element (DFS order) |
| `UTUI-FOCUS-PREV` | `( -- )` | Move focus to previous focusable element |

Focusability is determined by the `EL-F-FOCUS` bit in the element's
registry definition.  `UTUI-FOCUS!` clears the old element's FOC
flag and sets the new one's.

---

## Hit Testing

### UTUI-HIT-TEST — `( row col -- elem | 0 )`

Walk all elements and return the deepest (last in DFS order) whose
sidecar geometry contains the given screen coordinates.  Returns 0
if no element is hit.

---

## Paint & Layout

### UTUI-PAINT — `( -- )`

Full repaint cycle:

1. Walk UIDL tree in DFS order
2. For each visible element with a sidecar, apply style and call
   the element's `render-xt` from the registry
3. Elements with `when=` conditions are re-evaluated; hidden
   elements are skipped

### UTUI-RELAYOUT — `( -- )`

Recompute sidecar geometry for all elements based on the root region
and arrangement modes (`dock`, `flex`, `stack`, `flow`, `grid`).
Layout-specific handlers (e.g. `_UTUI-LAYOUT-TABS`) are called for
elements with custom layout words.

---

## Event Dispatch

### UTUI-DISPATCH-KEY — `( ev -- handled? )`

1. Check global shortcut table
2. If focused element exists, call its `event-xt` from the registry
3. Return `-1` if consumed, `0` otherwise

### UTUI-DISPATCH-MOUSE — `( row col btn -- handled? )`

1. `UTUI-HIT-TEST` to find element under cursor
2. If found and focusable, set focus and dispatch click event
3. Return `-1` if consumed, `0` otherwise

---

## Dialog Management

| Word | Stack | Description |
|------|-------|---------|
| `UTUI-SHOW-DIALOG` | `( id-a id-l -- )` | Legacy wrapper — delegates to `UTUI-SHOW` |
| `UTUI-HIDE-DIALOG` | `( id-a id-l -- )` | Legacy wrapper — delegates to `UTUI-HIDE` |

---

## Overlay System

Any UIDL element with `z-index > 0` or type `<dialog>` is treated
as an overlay.  Overlays are managed via `UTUI-SHOW` / `UTUI-HIDE`
(generic versions, not dialog-specific).

### UTUI-SHOW — `( id-a id-l -- )`

Show an overlay element by string ID:

1. Save current focus to `_UTUI-SAVED-FOCUS`
2. Set `VIS` flag on the element and all its descendants
3. Mark the entire subtree dirty for repaint
4. Move focus to the first focusable descendant (if any)

### UTUI-HIDE — `( id-a id-l -- )`

Hide an overlay element by string ID:

1. Snapshot the overlay's bounding rectangle
2. Clear `VIS` flag on the element and all its descendants
3. Dirty-rect scan: mark all visible base-layer elements whose
   bounding rect overlaps the overlay as dirty
4. Clear the overlay's screen area (`DRW-CLEAR-RECT`)
5. Restore focus to the saved element (if it's still visible)

### How Overlay Paint Works

The paint cycle (`UTUI-PAINT`) uses a two-pass approach:

- **Pass 1**: DFS walk paints normal-flow elements (z-index 0).
  When an overlay is encountered (z-index > 0 or dialog), the
  element is deferred to the overlay buffer and its **entire
  subtree is skipped** in Pass 1.
- **Pass 2**: Deferred overlays are sorted by z-index (ascending)
  and painted as **complete subtrees** (element + all descendants
  in tree order).

This ensures:
- Overlay children don't paint under base content in Pass 1
- Overlay backgrounds don't overwrite children painted too early
- Higher z-index overlays draw on top of lower ones

### Internal Words

| Word | Stack | Description |
|------|-------|---------|
| `_UTUI-SHOW-ELEM` | `( elem -- )` | Show by element pointer |
| `_UTUI-HIDE-ELEM` | `( elem -- )` | Hide by element pointer |
| `_UTUI-VIS-SUBTREE!` | `( flag elem -- )` | Set/clear VIS on elem + descendants |
| `_UTUI-DIRTY-SUBTREE` | `( elem -- )` | Mark elem + descendants dirty |
| `_UTUI-DIRTY-RECT` | `( row col h w -- )` | Dirty all visible elements overlapping rect |
| `_UTUI-PAINT-SUBTREE` | `( elem -- )` | DFS paint of elem + descendants (Pass 2) |
| `_UTUI-SKIP-SUBTREE` | `( elem -- next\|0 )` | Advance DFS past all descendants |
| `_UTUI-SKIP-CHILDREN` | `( -- addr )` | Variable: flag for Pass 1 subtree skip |
| `_UTUI-SAVED-FOCUS` | `( -- addr )` | Variable: stashed focus for overlay |

### Usage Example

```xml
<uidl>
<region arrange="stack">
  <label text="Main content"/>
  <group id="popup" style="z-index:10; color:1; background-color:4">
    <label text="Popup message!"/>
    <action id="close" text="OK" do="close"/>
  </group>
</region>
</uidl>
```

```forth
\ Show the popup — it paints on top, focus jumps inside
S" popup" UTUI-SHOW

\ Later, hide it — base content repaints automatically
S" popup" UTUI-HIDE
```

---

## Actions & Shortcuts

### UTUI-DO! — `( do-a do-l xt -- )`

Register a named action.  When an element with a matching
`on-activate` attribute is activated, the xt is called.

---

## Dynamic DOM Mutation

The base `uidl.f` has `UIDL-ADD-ELEM` and `UIDL-REMOVE-ELEM`, but
they only manipulate the element tree (nodes, pointers, attributes).
The TUI backend is unaware of raw additions — no sidecar, no style,
no materialization, no paint.

The TUI-aware wrappers handle the full lifecycle:

### UTUI-ADD-ELEM — `( parent type -- elem | 0 )`

Create a new child element under *parent* with element type *type*.
Returns the new element address, or 0 if the element pool is full.

Steps performed:
1. `UIDL-ADD-ELEM` — allocate node in tree
2. `_UTUI-SC-ALLOC` — zero-fill sidecar, set HAS flag
3. `_UTUI-INHERIT-PARENT-STYLE` — seed inheritable CSS bits from parent
4. `_UTUI-RESOLVE-STYLE` — run CSS cascade for the element
5. `_UTUI-MATERIALIZE-ONE` — create widget if needed
6. Set VIS flag in sidecar
7. `UIDL-DIRTY!` on parent — triggers relayout
8. `_UTUI-NEEDS-PAINT ON` — framework auto-repaints

```forth
\ Add a label child dynamically
S" my-group" UTUI-BY-ID  UIDL-T-LABEL  UTUI-ADD-ELEM
DUP S" text" S" New item" UTUI-SET-ATTR
```

### UTUI-REMOVE-ELEM — `( elem -- )`

Remove an element from the tree and free all associated resources.

Steps performed:
1. `_UTUI-DEMATERIALIZE-ONE` — free widget if any
2. `UIDL-DIRTY!` on parent — triggers relayout
3. `_UTUI-SC-FREE` — zero sidecar
4. `UIDL-REMOVE-ELEM` — unlink and zero node
5. `_UTUI-NEEDS-PAINT ON`

---

## Attribute Mutation

### UTUI-SET-ATTR — `( elem name-a name-l val-a val-l -- )`

Set an attribute on an element with automatic dirty propagation.
Wraps `UIDL-SET-ATTR` and then calls `UIDL-DIRTY!` on the element.

Apps should always use `UTUI-SET-ATTR` instead of raw `UIDL-SET-ATTR`
to ensure the framework knows about the change and repaints.

```forth
S" title" UTUI-BY-ID  S" text" S" Hello World"  UTUI-SET-ATTR
```

This is the Forth equivalent of JavaScript's `element.setAttribute()`
— it modifies the DOM and the engine notices.

---

## Widget Attachment

### UTUI-WIDGET-SET — `( wptr elem -- )`

Attach an app-created widget to a `<region>` element.  The widget
pointer is stored in the element's sidecar `wptr` field.  On the
next paint, `_UTUI-RENDER-REGION` automatically detects the attached
widget, syncs a proxy region from the sidecar geometry, and calls
the widget's `draw-xt` — the app never paints.

Pass 0 as *wptr* to detach a widget from an element.

```forth
\ In app init callback:
EXPL-NEW _pad-expl-w !
_pad-expl-w @  S" sb-tree" UTUI-BY-ID  UTUI-WIDGET-SET

\ Detach later:
0  S" sb-tree" UTUI-BY-ID  UTUI-WIDGET-SET
```

### Paint Integration for Attached Widgets

When `_UTUI-RENDER-REGION` encounters an element with a non-zero
wptr, it:

1. Fills the background
2. Syncs `_UTUI-PROXY-RGN` from the `_UR-*` temp vars
3. Calls `RGN-USE` on the proxy
4. Calls the widget's `draw-xt` (via `_WDG-O-DRAW-XT`)
5. Resets to `RGN-ROOT`

The app never needs a `PAINT-XT` callback.  Widget state changes
propagate automatically through `UIDL-DIRTY!` → `_UTUI-NEEDS-PAINT`
→ `ASHELL-DIRTY!`.

---

## Element Region Accessor

### UTUI-ELEM-RGN — `( elem -- row col h w )`

Return the computed screen geometry of an element from its sidecar.
Useful for positioning popups, cursors, or other elements relative
to a UIDL element without reaching into sidecar internals.

```forth
S" sidebar" UTUI-BY-ID UTUI-ELEM-RGN   \ ( row col h w )
```

---

## Automatic Dirty Propagation

`_UTUI-NEEDS-PAINT` is a global flag in `uidl-tui.f`.  It is set
whenever any UIDL element is dirtied, via a hook variable
(`_UDL-DIRTY-HOOK`) installed in `UIDL-DIRTY!`.

The flag is also set explicitly by:
- `UTUI-ADD-ELEM`
- `UTUI-REMOVE-ELEM`
- `UTUI-WIDGET-SET`

The shell checks `_UTUI-NEEDS-PAINT` after `TICK-XT` and at the
start of `_ASHELL-PAINT`, converting it to `ASHELL-DIRTY!`.  Apps
never need to call `ASHELL-DIRTY!` themselves.

### Internal Helpers (Sidecar Management)

| Word | Stack | Description |
|------|-------|-------------|
| `_UTUI-SC-ALLOC` | `( elem -- )` | Zero-fill sidecar slot, set HAS flag |
| `_UTUI-SC-FREE` | `( elem -- )` | Zero-fill sidecar slot |
| `_UTUI-INHERIT-PARENT-STYLE` | `( elem -- )` | Seed sidecar with parent's inheritable CSS bits |

---

## CSS Style Attributes

When an element carries a `style="…"` attribute in the UIDL markup,
`UTUI-LOAD` resolves the inline CSS declarations into the element's
sidecar after the layout pass completes.  Resolution is a depth-first
walk of the full element tree (`_UTUI-RESOLVE-STYLES-REC`), so
parent styles are applied before children.

### Supported Properties

| CSS Property | Sidecar Effect | Value Syntax |
|--------------|---------------|--------------|
| `color` | FG byte (bits 0–7) of packed style | `#RGB`, `#RRGGBB`, named colour, integer 0-255 |
| `background-color` | BG byte (bits 8–15) of packed style | `#RGB`, `#RRGGBB`, named colour, integer 0-255 |
| `font-weight` | Bold bit (bit 16) in attrs | `bold` (case-insensitive) |
| `text-align` | Bits 24-25 of packed style | `left`, `center`, `right` |
| `width` | Sidecar W field | Integer (cells) or `N%` of parent W |
| `height` | Sidecar H field | Integer (cells) or `N%` of parent H |
| `position` | Bits 26-27 of style (prelayout) | `static`, `absolute`, `fixed` |
| `z-index` | Bits 28-35 of style (prelayout) | Integer 0-255 |
| `display` | HIDE flag in sidecar flags (prelayout) | `none` |
| `padding` | Sidecar padding field (prelayout) | 1-4 integer values |
| `margin` | Sidecar margin field (prelayout) | 1-4 integer values |

Colours are parsed by `TUI-PARSE-COLOR` from [color.f](color.md) —
all 148 CSS named colours, `#RRGGBB` / `#RGB` hex notation, and
raw integer palette indices (0-255) are accepted.  Percentage
dimensions are resolved against the parent element's already-computed
sidecar size (`width: 50%` on a child whose parent has W = 80 →
child W = 40).

Properties marked **(prelayout)** are resolved before the layout pass;
all others are resolved after layout.

**Inheritable properties**: `color`, `background-color`, `font-weight`,
`text-align`.  These propagate from parent to child automatically.

**Non-inheritable properties**: `position`, `z-index`, `display`,
`padding`, `margin`, `width`, `height`.  These apply only to the
element that declares them.

### Resolution Flow

```
UTUI-LOAD
  ├── Parse UIDL markup
  ├── Allocate sidecars
  ├── _UTUI-PRELAYOUT-STYLES  ← position, display, padding, margin
  ├── UTUI-RELAYOUT           ← geometry pass (row/col/w/h)
  └── _UTUI-RESOLVE-STYLES    ← CSS style= pass (post-layout, with inheritance)
        └── _UTUI-RESOLVE-STYLES-REC (preorder DFS)
              ├── _UTUI-RESOLVE-ELEM-STYLE on parent
              │     ├── CSS-DECL-FIND "color"            → TUI-PARSE-COLOR → fg
              │     ├── CSS-DECL-FIND "background-color" → TUI-PARSE-COLOR → bg
              │     ├── CSS-DECL-FIND "font-weight"      → bold bit
              │     ├── CSS-DECL-FIND "text-align"       → align bits
              │     ├── CSS-DECL-FIND "width"            → CSS-PARSE-NUMBER → sidecar W
              │     └── CSS-DECL-FIND "height"           → CSS-PARSE-NUMBER → sidecar H
              ├── Extract inheritable bits (mask 0x03FFFFFF)
              └── For each child:
                    ├── Seed child sidecar with parent's inheritable bits
                    └── Recurse (_UTUI-RESOLVE-STYLES-REC on child)
```

### UIDL Example

```xml
<panel id="status" style="color:#5fafff; background-color:#1c1c1c; font-weight:bold">
  <label style="width:50%">Left half</label>
  <label style="color:white">Right text</label>
</panel>
```

After `UTUI-LOAD`, the status panel's sidecar has:

- FG = palette index of `#5fafff` (75)
- BG = palette index of `#1c1c1c` (234)
- Bold bit set

Both child labels **inherit** the panel's FG, BG, and bold via
CSS inheritance.  The first label then has `width: 50%` which
halves its sidecar W field.  The second label overrides only FG
to white (231) — BG and bold are still inherited from the parent.

### Internal Words

| Word | Stack | Description |
|------|-------|-------------|
| `_UTUI-RESOLVE-STYLES` | `( -- )` | Entry point: walk from `UIDL-ROOT` |
| `_UTUI-RESOLVE-STYLES-REC` | `( elem -- )` | Recursive DFS — inherits, resolves, recurses |
| `_UTUI-RESOLVE-ELEM-STYLE` | `( elem -- )` | Read `style=`, apply each CSS declaration |
| `_UTUI-CSS-SET-FG` | `( val-a val-u -- )` | Parse colour → FG bits |
| `_UTUI-CSS-SET-BG` | `( val-a val-u -- )` | Parse colour → BG bits |
| `_UTUI-CSS-SET-BOLD` | `( val-a val-u -- )` | Check for `bold` → attrs bit 16 |
| `_UTUI-CSS-SET-ALIGN` | `( val-a val-u -- )` | Parse text-align → bits 24-25 |
| `_UTUI-CSS-SET-POSITION` | `( val-a val-u -- )` | Parse position → bits 26-27 |
| `_UTUI-CSS-SET-ZINDEX` | `( val-a val-u -- )` | Parse z-index → bits 28-35 |
| `_UTUI-CSS-SET-DISPLAY` | `( val-a val-u -- )` | Parse display:none → HIDE flag |
| `_UTUI-CSS-SET-DIM` | `( val-a val-u pdim off -- )` | Parse number+unit → sidecar W or H |
| `_UTUI-CSS-SET-PAD` | `( val-a val-u -- )` | Parse padding shorthand → sidecar |
| `_UTUI-CSS-SET-MARGIN` | `( val-a val-u -- )` | Parse margin shorthand → sidecar |

---

## Element-Specific Rendering

Each chrome element type has dedicated render, event, and layout
adapter words installed via `UTUI-INSTALL-XTS`.

### Tree (`UIDL-T-TREE`)

| Phase | Adapter | Behaviour |
|-------|---------|-----------|
| Render | `_UTUI-RENDER-TREE` | Fills bg, syncs proxy region, calls `_TREE-DRAW` via wptr |
| Event | `_UTUI-H-TREE` | Syncs proxy, delegates to `_TREE-HANDLE` via wptr |
| Layout | (stack) | Standard stack layout |

The tree widget struct is fully materialized via `TREE-NEW` during
`_UTUI-MATERIALIZE`.  The four UIDL tree callbacks
(`_UTUI-TREE-CHILD`, etc.) let the widget walk the UIDL element
tree as if it were its own node graph.

### Tabs (`UIDL-T-TABS`)

| Phase | Adapter | Behaviour |
|-------|---------|-----------|
| Render | `_UTUI-RENDER-TABS` | Fills bg, draws `label=` per child with active highlight, underline on row 1 |
| Event | `_UTUI-H-TABS` | Left/Right keys switch active tab index in wptr state |
| Layout | `_UTUI-LAYOUT-TABS` | 2-row header; active tab child gets content area (row+2, col, w, h-2); inactive children get 0×0 |

State: 8-byte block at wptr, single cell holding the active tab
index (0-based).  Inline adapter — no `TAB-NEW` widget allocated.

### Split (`UIDL-T-SPLIT`)

| Phase | Adapter | Behaviour |
|-------|---------|-----------|
| Render | `_UTUI-RENDER-SPLIT` | Reads `ratio=` attr (default 50), draws `│` divider at computed column |
| Event | (stub) | Not interactive |
| Layout | (stack) | Standard stack layout |

Pure inline adapter — no widget struct.

### Status (`UIDL-T-STATUS`)

| Phase | Adapter | Behaviour |
|-------|---------|-----------|
| Render | `_UTUI-RENDER-STATUS` | Fills 1-row bg, first child's text left-aligned, last child's text right-aligned |
| Event | (stub) | Not interactive |
| Layout | (stack) | Standard stack layout |

Pure inline adapter — reads child element `text=` attributes.

### Scroll (`UIDL-T-SCROLL`)

| Phase | Adapter | Behaviour |
|-------|---------|-----------|
| Render | `_UTUI-RENDER-SCROLL` | Fills bg (scroll indicators TODO) |
| Event | (stub) | Not yet wired |
| Layout | (stack) | Standard stack layout |

Scroll indicators are planned but not yet implemented.

### Input (`UIDL-T-INPUT`)

| Phase | Adapter | Behaviour |
|-------|---------|----------|
| Render | `_UTUI-RENDER-INPUT` | Fills bg, syncs proxy region + focus, delegates to `_INP-DRAW` via wptr |
| Event | `_UTUI-H-INPUT` | Syncs proxy + focus, delegates to `_INP-HANDLE` via wptr |
| Layout | (stack) | Standard stack layout |

Materialized via `_UTUI-MAT-INPUT`: allocates a 256-byte buffer,
calls `INP-NEW`, sets `text=` and `placeholder=` from UIDL attrs.
Dematerialization frees the buffer (widget+40) then the descriptor.

### Textarea (`UIDL-T-TEXTAREA`)

| Phase | Adapter | Behaviour |
|-------|---------|----------|
| Render | `_UTUI-RENDER-TEXTAREA` | Fills bg, syncs proxy region + focus, delegates to `_TXTA-DRAW` via wptr |
| Event | `_UTUI-H-TEXTAREA` | Syncs proxy + focus, delegates to `_TXTA-HANDLE` via wptr |
| Layout | (stack) | Standard stack layout |

Materialized via `_UTUI-MAT-TXTA`: allocates a 4096-byte buffer,
calls `TXTA-NEW`, sets `text=` from UIDL attrs.
Dematerialization frees the buffer (widget+40) then the descriptor.

### Collection, Dialog, Menu, Toast

These remain stub adapters (background fill for render, no-op for
events) pending future implementation.

---

## UIDL Context (UCTX) System

Defined in §18b of `uidl-tui.f`.  Provides per-app serialisation of
the 15 global UIDL/UTUI variables and 10 pool arrays (~97 KiB per
context).  This lives in `uidl-tui.f` because it must enumerate every
private `_UDL-*` and `_UTUI-*` variable.

| Word | Stack | Description |
|------|-------|-------------|
| `UCTX-ALLOC` | `( -- ctx \| 0 )` | Heap-allocate a context buffer.  Returns 0 on failure. |
| `UCTX-FREE` | `( ctx -- )` | Free a context buffer. |
| `UCTX-SAVE` | `( ctx -- )` | Copy all 15 globals + 10 pools into `ctx`. |
| `UCTX-RESTORE` | `( ctx -- )` | Restore all 15 globals + 10 pools from `ctx`. |
| `UCTX-CLEAR` | `( ctx -- )` | Zero-fill entire context buffer. |
| `UCTX-TOTAL` | `( -- n )` | Total byte size of one context (~99,448). |

Used by `app-shell.f` (§1: `ASHELL-CTX-SWITCH`, `ASHELL-CTX-SAVE`)
and by `desk.f` (`UCTX-ALLOC`, `UCTX-FREE`, `UCTX-CLEAR`).

---

## Region Setter

| Word | Stack | Description |
|------|-------|-------------|
| `UTUI-RGN!` | `( rgn -- )` | Set the root region for the current UIDL document.  Used by desk when reassigning tile regions. |

---

## Guard Wrappers

When `GUARDED` is defined, all public words are wrapped with a
single guard (`_utui-guard`) for thread-safe access:

`UTUI-LOAD`, `UTUI-BIND-STATE`, `UTUI-PAINT`, `UTUI-RELAYOUT`,
`UTUI-DISPATCH-KEY`, `UTUI-DISPATCH-MOUSE`, `UTUI-FOCUS`,
`UTUI-FOCUS!`, `UTUI-FOCUS-NEXT`, `UTUI-FOCUS-PREV`,
`UTUI-HIT-TEST`, `UTUI-BY-ID`, `UTUI-DETACH`, `UTUI-DO!`,
`UTUI-SHOW-DIALOG`, `UTUI-HIDE-DIALOG`,
`UTUI-ADD-ELEM`, `UTUI-REMOVE-ELEM`, `UTUI-SET-ATTR`,
`UTUI-WIDGET-SET`, `UTUI-ELEM-RGN`, `UTUI-WIDGET@`,
`UTUI-INSTALL-XTS`.

`UTUI-SHOW` and `UTUI-HIDE` are **not** guarded — they are thin
wrappers that delegate to the guarded `UTUI-SHOW-DIALOG` and
`UTUI-HIDE-DIALOG`.

---

## Quick Reference

```
UTUI-LOAD              ( xml-a xml-u rgn -- flag )   Parse UIDL, build sidecars + widgets
UTUI-DETACH            ( -- )                        Free widgets, clear sidecars
UTUI-BIND-STATE        ( st -- )                     Bind state-tree for expressions
UTUI-INSTALL-XTS       ( -- )                        Patch Element Registry with TUI adapters
UTUI-PAINT             ( -- )                        Full repaint
UTUI-RELAYOUT          ( -- )                        Recompute all geometry
UTUI-RGN!             ( rgn -- )                     Set root region
UTUI-DISPATCH-KEY      ( ev -- handled? )            Dispatch keyboard event
UTUI-DISPATCH-MOUSE    ( row col btn -- handled? )   Dispatch mouse event
UTUI-FOCUS             ( -- elem | 0 )               Get focused element
UTUI-FOCUS!            ( elem -- )                   Set focused element
UTUI-FOCUS-NEXT        ( -- )                        Advance focus (DFS)
UTUI-FOCUS-PREV        ( -- )                        Retreat focus (DFS)
UTUI-HIT-TEST          ( row col -- elem | 0 )       Deepest element at screen pos
UTUI-BY-ID             ( id-a id-l -- elem | 0 )     Look up element by ID
UTUI-WIDGET@           ( elem -- wptr | 0 )          Get widget pointer from element sidecar
UTUI-ADD-ELEM          ( parent type -- elem | 0 )    Create child with sidecar + style + materialize
UTUI-REMOVE-ELEM       ( elem -- )                    Dematerialize + free sidecar + unlink
UTUI-SET-ATTR          ( elem na nl va vl -- )         Set attribute with auto-dirty
UTUI-WIDGET-SET        ( wptr elem -- )                Attach/detach widget to region element
UTUI-ELEM-RGN          ( elem -- row col h w )         Computed screen geometry from sidecar
UTUI-DO!               ( do-a do-l xt -- )           Register named action
UTUI-SHOW              ( id-a id-l -- )              Show overlay (set VIS, dirty, focus)
UTUI-HIDE              ( id-a id-l -- )              Hide overlay (clear VIS, dirty-rect, restore focus)
UTUI-SHOW-DIALOG       ( id-a id-l -- )              Show dialog by ID (legacy wrapper)
UTUI-HIDE-DIALOG       ( id-a id-l -- )              Hide dialog by ID (legacy wrapper)
UTUI-SC-FG@            ( elem -- fg )                Computed foreground colour
UTUI-SC-BG@            ( elem -- bg )                Computed background colour
UTUI-SC-ATTRS@         ( elem -- attrs )             Computed attributes
UCTX-ALLOC             ( -- ctx | 0 )               Allocate context buffer (~97 KiB)
UCTX-FREE              ( ctx -- )                    Free context buffer
UCTX-SAVE              ( ctx -- )                    Save globals + pools into ctx
UCTX-RESTORE           ( ctx -- )                    Restore globals + pools from ctx
UCTX-CLEAR             ( ctx -- )                    Zero-fill context buffer
UCTX-TOTAL             ( -- n )                      Context buffer byte size (99448)
```

---

## Cookbook

### Load a UIDL document

```forth
REQUIRE tui/uidl-tui.f

\ Create root region (full terminal)
0 0 24 80 RGN-NEW CONSTANT my-rgn

\ Parse and display
S" <uidl><region id='main'><label text='Hello'/></region></uidl>"
my-rgn UTUI-LOAD  .  \ -1 on success
```

### Bind a state tree and repaint

```forth
ST-NEW CONSTANT my-st
my-st S" title" S" Akashic" ST-SET-PATH-STR

my-st UTUI-BIND-STATE
UTUI-PAINT
```

### Dispatch keyboard input

```forth
BEGIN
    KEY-READ              \ ( event )
    UTUI-DISPATCH-KEY     \ ( handled? )
    DROP
    UTUI-PAINT
AGAIN
```

### Register an action handler

```forth
: my-save  ( -- )  ." Saved!" CR ;
S" save" ['] my-save UTUI-DO!
```

### Show/hide an overlay

```forth
\ Any element with z-index or type=dialog
S" popup" UTUI-SHOW    \ shows, dirties, captures focus
S" popup" UTUI-HIDE    \ hides, clear-rects, restores focus
```

### Show/hide a dialog (legacy)

```forth
\ In UIDL: <dialog id="help-dlg"> ... </dialog>
S" help-dlg" UTUI-SHOW-DIALOG   \ delegates to UTUI-SHOW
\ later:
S" help-dlg" UTUI-HIDE-DIALOG   \ delegates to UTUI-HIDE
```

### Clean up

```forth
UTUI-DETACH
my-rgn RGN-FREE
```

---

## See Also

- [uidl.md](../liraq/uidl.md) — UIDL document model and element registry
- [color.md](color.md) — Shared RGB → xterm-256 color resolution
- [dom-tui.md](dom-tui.md) — DOM-to-TUI backend (alternative path)
- [widget.md](widget.md) — Widget common header
- [region.md](region.md) — Region primitives
- [draw.md](draw.md) — Draw engine
- [tree.md](widgets/tree.md) — Tree widget (materialized by UIDL-TUI)
- [tabs.md](widgets/tabs.md) — Tabs widget
- [split.md](widgets/split.md) — Split pane widget
- [status.md](widgets/status.md) — Status bar widget
- [scroll.md](widgets/scroll.md) — Scroll viewport widget
