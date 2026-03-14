# akashic/tui/uidl-tui.f — UIDL TUI Backend

**Layer:** 8  
**Lines:** ~1630  
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
| **One sidecar per element** | Every UIDL element receives a 56-byte sidecar in a parallel array, indexed by pool position. |
| **No DOM intermediary** | Unlike `dom-tui.f`, this backend reads UIDL elements directly — no N.AUX, no DOM node walk. |
| **Adapter, not materialization** | Most widget types (status, split, scroll) are rendered inline by adapter words that read UIDL attributes. Only `tree` and `tabs` allocate real widget state. |
| **Sidecar wptr** | The `+48` cell in each sidecar holds an optional widget-struct pointer (tree widget) or mini state block (tabs active index). Zero means "no widget state". |
| **Proxy region** | A single static 40-byte region (`_UTUI-PROXY-RGN`) is synced from sidecar geometry before calling widget `_*-DRAW` / `_*-HANDLE`. Safe because the TUI is single-threaded. |
| **Packed style** | FG (8 bits) + BG (8 bits) + attrs (8 bits) packed into one cell at `+32`. |
| **Registry patching** | `UTUI-INSTALL-XTS` writes render/event/layout XTs into Element Registry definitions. Each chrome element type gets its own adapter. |
| **Guard safety** | When `GUARDED` is defined, all public words are serialized through `_utui-guard`. |

---

## Sidecar Layout

Each sidecar is 56 bytes (7 cells), stored in the parallel array
`_UTUI-SIDECARS` (capacity: 256 elements).

| Offset | Field | Type | Description |
|--------|-------|------|-------------|
| +0 | `row` | u | Computed screen row |
| +8 | `col` | u | Computed screen column |
| +16 | `width` | u | Width in character cells |
| +24 | `height` | u | Height in character cells |
| +32 | `style` | packed | FG(8), BG(8), attrs(8) |
| +40 | `flags` | bitfield | HAS / VIS / FOC |
| +48 | `wptr` | address | Widget struct pointer or mini state block (0 = none) |

### Sidecar Flag Bits

| Constant | Value | Description |
|----------|-------|-------------|
| `_UTUI-SCF-HAS` | 1 | Sidecar allocated |
| `_UTUI-SCF-VIS` | 2 | Visible |
| `_UTUI-SCF-FOC` | 4 | Focused |

### Element → Sidecar Mapping

```forth
_UTUI-SC-IDX   ( elem -- idx )   \ (elem - _UDL-ELEMS) / _UDL-ELEMSZ
_UTUI-SIDECAR  ( elem -- sc )    \ idx * 56 + _UTUI-SIDECARS
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

A single cell encodes foreground, background, and attributes:

```
bits  0– 7:  FG colour index   (0–255)
bits  8–15:  BG colour index   (0–255)
bits 16–23:  Cell attributes    (bold, italic, etc.)
```

| Word | Stack | Description |
|------|-------|-------------|
| `_UTUI-PACK-STYLE` | `( fg bg attrs -- packed )` | Pack three values |
| `_UTUI-UNPACK-STYLE` | `( packed -- fg bg attrs )` | Extract all three |
| `_UTUI-APPLY-STYLE` | `( sc -- )` | Read sidecar style and call `DRW-STYLE!` |

Default style: `253 236 0` (light gray on dark gray, no attributes).

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

All other element types (status, split, scroll, dialog, etc.) use
inline adapters that read UIDL attributes directly — `wptr` stays 0.

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
|------|-------|-------------|
| `UTUI-SHOW-DIALOG` | `( id-a id-l -- )` | Look up dialog by ID, mark visible, set focus |
| `UTUI-HIDE-DIALOG` | `( id-a id-l -- )` | Look up dialog by ID, hide, restore previous focus |

---

## Actions & Shortcuts

### UTUI-DO! — `( do-a do-l xt -- )`

Register a named action.  When an element with a matching
`on-activate` attribute is activated, the xt is called.

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
| `color` | FG byte (bits 0–7) of packed style | `#RGB`, `#RRGGBB`, named colour |
| `background-color` | BG byte (bits 8–15) of packed style | `#RGB`, `#RRGGBB`, named colour |
| `font-weight` | Bold bit (bit 16) in attrs | `bold` (case-insensitive) |
| `width` | Sidecar W field | Integer (cells) or `N%` of parent W |
| `height` | Sidecar H field | Integer (cells) or `N%` of parent H |

Colours are parsed by `TUI-PARSE-COLOR` from [color.f](color.md) —
all 148 CSS named colours and `#RRGGBB` / `#RGB` hex notation are
accepted.  Percentage dimensions are resolved against the parent
element's already-computed sidecar size (`width: 50%` on a child
whose parent has W = 80 → child W = 40).

### Resolution Flow

```
UTUI-LOAD
  ├── Parse UIDL markup
  ├── Allocate sidecars
  ├── UTUI-RELAYOUT          ← geometry pass
  └── _UTUI-RESOLVE-STYLES   ← CSS style= pass (post-layout)
        └── depth-first walk
              └── _UTUI-RESOLVE-ELEM-STYLE per element
                    ├── UIDL-ATTR "style" → val-a val-u
                    ├── CSS-DECL-FIND "color"            → TUI-PARSE-COLOR → fg
                    ├── CSS-DECL-FIND "background-color" → TUI-PARSE-COLOR → bg
                    ├── CSS-DECL-FIND "font-weight"      → bold bit
                    ├── CSS-DECL-FIND "width"             → CSS-PARSE-NUMBER → sidecar W
                    └── CSS-DECL-FIND "height"            → CSS-PARSE-NUMBER → sidecar H
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

The first label inherits parent dimensions via layout, then
`width: 50%` halves the sidecar W field.  The second label
overrides only FG to white (231).

### Internal Words

| Word | Stack | Description |
|------|-------|-------------|
| `_UTUI-RESOLVE-STYLES` | `( -- )` | Entry point: walk from `UIDL-ROOT` |
| `_UTUI-RESOLVE-STYLES-REC` | `( elem -- )` | Recursive depth-first walker |
| `_UTUI-RESOLVE-ELEM-STYLE` | `( elem -- )` | Read `style=`, apply each CSS declaration |
| `_UTUI-CSS-SET-FG` | `( val-a val-u -- )` | Parse colour → FG bits |
| `_UTUI-CSS-SET-BG` | `( val-a val-u -- )` | Parse colour → BG bits |
| `_UTUI-CSS-SET-BOLD` | `( val-a val-u -- )` | Check for `bold` → attrs bit 16 |
| `_UTUI-CSS-SET-DIM` | `( val-a val-u pdim off -- )` | Parse number+unit → sidecar W or H |

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

## Guard Wrappers

When `GUARDED` is defined, all public words are wrapped with a
single guard (`_utui-guard`) for thread-safe access:

`UTUI-LOAD`, `UTUI-BIND-STATE`, `UTUI-PAINT`, `UTUI-RELAYOUT`,
`UTUI-DISPATCH-KEY`, `UTUI-DISPATCH-MOUSE`, `UTUI-FOCUS`,
`UTUI-FOCUS!`, `UTUI-FOCUS-NEXT`, `UTUI-FOCUS-PREV`,
`UTUI-HIT-TEST`, `UTUI-BY-ID`, `UTUI-DETACH`, `UTUI-DO!`,
`UTUI-SHOW-DIALOG`, `UTUI-HIDE-DIALOG`.

---

## Quick Reference

```
UTUI-LOAD              ( xml-a xml-u rgn -- flag )   Parse UIDL, build sidecars + widgets
UTUI-DETACH            ( -- )                        Free widgets, clear sidecars
UTUI-BIND-STATE        ( st -- )                     Bind state-tree for expressions
UTUI-INSTALL-XTS       ( -- )                        Patch Element Registry with TUI adapters
UTUI-PAINT             ( -- )                        Full repaint
UTUI-RELAYOUT          ( -- )                        Recompute all geometry
UTUI-DISPATCH-KEY      ( ev -- handled? )            Dispatch keyboard event
UTUI-DISPATCH-MOUSE    ( row col btn -- handled? )   Dispatch mouse event
UTUI-FOCUS             ( -- elem | 0 )               Get focused element
UTUI-FOCUS!            ( elem -- )                   Set focused element
UTUI-FOCUS-NEXT        ( -- )                        Advance focus (DFS)
UTUI-FOCUS-PREV        ( -- )                        Retreat focus (DFS)
UTUI-HIT-TEST          ( row col -- elem | 0 )       Deepest element at screen pos
UTUI-BY-ID             ( id-a id-l -- elem | 0 )     Look up element by ID
UTUI-WIDGET@           ( elem -- wptr | 0 )          Get widget pointer from element sidecar
UTUI-DO!               ( do-a do-l xt -- )           Register named action
UTUI-SHOW-DIALOG       ( id-a id-l -- )              Show dialog by ID
UTUI-HIDE-DIALOG       ( id-a id-l -- )              Hide dialog by ID
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

### Show/hide a dialog

```forth
\ In UIDL: <dialog id="help-dlg"> ... </dialog>
S" help-dlg" UTUI-SHOW-DIALOG
\ later:
S" help-dlg" UTUI-HIDE-DIALOG
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
