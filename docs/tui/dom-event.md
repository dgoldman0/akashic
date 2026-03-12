# akashic-tui-dom-event — DOM Event Routing for TUI / KDOS / Megapad-64

TUI-specific adapter that feeds keyboard and mouse events from the
TUI input system (`keys.f`) into the general-purpose DOM event system
(`dom/event.f`).  Translates `KEY-READ` events into `keydown` /
`keypress` DOM events, mouse reports into `mousedown` / `click`, and
manages DOM-level focus with Tab / Shift-Tab cycling through
`DTUI-F-FOCUSABLE` elements.

```forth
REQUIRE dom-event.f
```

`PROVIDED akashic-tui-dom-event` — safe to include multiple times.
Automatically loads `dom-tui.f`, `dom-render.f`, `keys.f`, and
`../dom/event.f`.

---

## Table of Contents

- [Design Overview](#design-overview)
- [Dependencies](#dependencies)
- [Initialization](#initialization)
- [Focus Management](#focus-management)
- [Focus Traversal](#focus-traversal)
- [Hit Testing](#hit-testing)
- [Key Dispatch](#key-dispatch)
- [Mouse Dispatch](#mouse-dispatch)
- [Guard Wrappers](#guard-wrappers)
- [Internal State](#internal-state)
- [Quick Reference](#quick-reference)
- [Cookbook](#cookbook)

---

## Design Overview

| Principle | Detail |
|---|---|
| **Two-system bridge** | Connects TUI key events (24-byte descriptors from `keys.f`) with the W3C-style DOM event system (`dom/event.f`). |
| **Focus model** | A single `_DEVT-FOCUS` variable tracks the currently focused DOM node. Focus changes fire `blur` and `focus` DOM events with correct `relatedTarget`. |
| **Tab cycling** | Tab and Shift-Tab / Backtab are intercepted before dispatch. A DFS walk collects up to 64 focusable nodes into a ring buffer for O(n) traversal. |
| **Hit testing** | DFS walk from `BODY`, checking sidecar bounds (row/col/w/h). Deepest matching node wins (paint-order correct). |
| **Event translation** | Key events become `keydown` (always) + `keypress` (if char and not prevented). Mouse events become `mousedown` + `click`. |
| **Auto-focus on click** | Clicking a `DTUI-F-FOCUSABLE` element automatically focuses it before dispatching mouse events. |

---

## Dependencies

```
dom-event.f
├── tui/dom-tui.f    (DTUI sidecars, DTUI-F-FOCUSABLE, DTUI-SC-*)
├── tui/dom-render.f (layout — provides sidecar row/col/w/h)
├── tui/keys.f       (KEY-READ, KEY-CODE@, KEY-MODS@, KEY-IS-CHAR?, etc.)
└── dom/event.f      (DOME-DISPATCH, DOME-EVENT-NEW, DOME-FIRE, etc.)
```

Transitive: `dom.f`, `html5.f`, `css.f`, `bridge.f`, `cell.f`,
`draw.f`, `box.f`, `region.f`, `screen.f`.

---

## Initialization

### DEVT-INIT

```forth
DEVT-INIT  ( doc dome -- )
```

Bind DOM event routing to a document and DOME descriptor.  Stores
both references and zeroes the focus pointer.  Must be called before
any other `DEVT-` word.

```forth
my-doc  my-dome  DEVT-INIT
```

---

## Focus Management

### DEVT-FOCUS

```forth
DEVT-FOCUS  ( -- node|0 )
```

Return the currently focused DOM element, or 0 if nothing is focused.

### DEVT-FOCUS!

```forth
DEVT-FOCUS!  ( node -- )
```

Set focus to a specific element.  If `node` differs from the current
focus, fires:

1. **blur** on the old focus — `relatedTarget` = new node
2. **focus** on the new node — `relatedTarget` = old node

Both events are non-bubbling and non-cancelable (per W3C spec).
Passing 0 blurs the current element without focusing anything.

```forth
my-button DEVT-FOCUS!
DEVT-FOCUS .                        \ → address of my-button
0 DEVT-FOCUS!                       \ blur, no new focus
```

### _DEVT-FOCUSABLE?

```forth
_DEVT-FOCUSABLE?  ( node -- flag )
```

Internal.  Returns true if `node` is an element with a sidecar whose
flags include both `DTUI-F-VISIBLE` and `DTUI-F-FOCUSABLE`, and the
`DTUI-F-HIDDEN` flag is **not** set.

---

## Focus Traversal

Focus traversal collects focusable nodes into a 64-element ring
buffer (`_DEVT-FRING`) via a DFS walk from `BODY`.

### DEVT-FOCUS-NEXT

```forth
DEVT-FOCUS-NEXT  ( -- )
```

Move focus to the next focusable element in DFS order.  Wraps around
from last to first.  If nothing is currently focused, focuses the
first focusable element.

### DEVT-FOCUS-PREV

```forth
DEVT-FOCUS-PREV  ( -- )
```

Move focus to the previous focusable element (Shift-Tab direction).
Wraps around from first to last.

```forth
\ Typical Tab handling (automatic when using DEVT-DISPATCH):
DEVT-FOCUS-NEXT     \ Tab
DEVT-FOCUS-PREV     \ Shift-Tab
```

---

## Hit Testing

### DEVT-HIT-TEST

```forth
DEVT-HIT-TEST  ( row col -- node|0 )
```

Find the deepest visible element whose sidecar bounds contain
`(row, col)`.  Returns 0 if no element covers that cell.

The walk is depth-first from `BODY`.  Later DFS siblings overwrite
earlier matches, giving correct paint-order resolution (the visually
topmost / last-painted element wins).

A node qualifies if:
- It is an element (`DOM-T-ELEMENT`)
- It has a sidecar (`N.AUX` ≠ 0)
- `DTUI-F-VISIBLE` is set, `DTUI-F-HIDDEN` is **not** set
- `row` ∈ `[sc.ROW, sc.ROW + sc.H)` and `col` ∈ `[sc.COL, sc.COL + sc.W)`

```forth
10 20 DEVT-HIT-TEST  DUP IF  ." Hit: " . CR  ELSE  DROP ." Miss" CR  THEN
```

---

## Key Dispatch

### DEVT-DISPATCH

```forth
DEVT-DISPATCH  ( key-ev-addr -- prevented? )
```

Translate a 24-byte TUI key event (from `KEY-READ`) into DOM events
and dispatch to the focused element (or `BODY` if unfocused).

**Flow:**

1. If the key is **Tab** → call `DEVT-FOCUS-NEXT`, return 0.
2. If the key is **Shift-Tab** or **Backtab** → call `DEVT-FOCUS-PREV`, return 0.
3. Create a **keydown** event (bubbles, cancelable) with:
   - `E.DETAIL` = key code (codepoint or special-key constant)
   - `E.DETAIL2` = modifier flags (`KEY-MOD-SHIFT`, etc.)
   - `E.DETAIL3` = key type (`KEY-T-CHAR`, `KEY-T-SPECIAL`, etc.)
4. Dispatch keydown to target.  If prevented, return true.
5. If the event is a **character** (`KEY-IS-CHAR?`) and not prevented,
   fire an additional **keypress** event with the same detail fields.
6. Return the prevented flag from the last dispatched event.

```forth
CREATE _my-ke  24 ALLOT
KEY-T-CHAR _my-ke !   65 _my-ke 8 + !   0 _my-ke 16 + !   \ 'A', no mods
_my-ke DEVT-DISPATCH .   \ → 0 (not prevented)
```

---

## Mouse Dispatch

### DEVT-DISPATCH-MOUSE

```forth
DEVT-DISPATCH-MOUSE  ( row col button -- prevented? )
```

Hit-test at `(row, col)`, then dispatch mouse DOM events to the
found element.  Returns 0 if no element was hit.

**Flow:**

1. Call `DEVT-HIT-TEST` — if miss, return 0.
2. If the target is focusable, call `DEVT-FOCUS!` on it.
3. Fire **mousedown** (bubbles, cancelable) with:
   - `E.DETAIL` = row
   - `E.DETAIL2` = col
   - `E.DETAIL3` = button (0=left, 1=middle, 2=right)
4. Fire **click** with the same detail fields.
5. Return the prevented flag from the click event.

```forth
10 20 0 DEVT-DISPATCH-MOUSE .   \ left-click at row 10, col 20
```

---

## Guard Wrappers

When `GUARDED` is defined, all public words are wrapped with
`_devt-guard WITH-GUARD` to serialise access in concurrent
environments.  The guard is created from `../concurrency/guard.f`.

Wrapped words: `DEVT-INIT`, `DEVT-FOCUS`, `DEVT-FOCUS!`,
`DEVT-FOCUS-NEXT`, `DEVT-FOCUS-PREV`, `DEVT-HIT-TEST`,
`DEVT-DISPATCH`, `DEVT-DISPATCH-MOUSE`.

---

## Internal State

| Variable | Purpose |
|----------|---------|
| `_DEVT-DOC` | DOM document pointer |
| `_DEVT-DOME` | DOME event descriptor pointer |
| `_DEVT-FOCUS` | Currently focused DOM node (0 = none) |
| `_DFS-OLD` / `_DFS-NEW` / `_DFS-EVT` | Scratch for `DEVT-FOCUS!` blur/focus dispatch |
| `_DEVT-FRING` | Focus ring buffer (64 × 8 bytes) |
| `_DEVT-FCOUNT` | Number of focusable nodes in the ring |
| `_DHT-ROW` / `_DHT-COL` / `_DHT-BEST` / `_DHT-SC` | Hit-test scratch |
| `_DKD-EVT` / `_DKD-TGT` / `_DKD-KE` | Key dispatch scratch |
| `_DMD-EVT` / `_DMD-TGT` / `_DMD-ROW` / `_DMD-COL` / `_DMD-BTN` | Mouse dispatch scratch |

---

## Quick Reference

| Word | Stack | Description |
|------|-------|-------------|
| `DEVT-INIT` | `( doc dome -- )` | Bind to document + DOME |
| `DEVT-FOCUS` | `( -- node\|0 )` | Get focused element |
| `DEVT-FOCUS!` | `( node -- )` | Set focus (fires blur/focus) |
| `DEVT-FOCUS-NEXT` | `( -- )` | Tab to next focusable |
| `DEVT-FOCUS-PREV` | `( -- )` | Shift-Tab to previous |
| `DEVT-HIT-TEST` | `( row col -- node\|0 )` | Find element at cell |
| `DEVT-DISPATCH` | `( key-ev -- prevented? )` | Dispatch TUI key event |
| `DEVT-DISPATCH-MOUSE` | `( row col btn -- prevented? )` | Dispatch mouse event |

---

## Cookbook

### Minimal event loop

```forth
\ After DOM tree is built, sidecars attached, and layout computed:
my-doc  my-dome  DEVT-INIT

CREATE _ke  24 ALLOT

: MY-EVENT-LOOP  ( -- )
    BEGIN
        _ke KEY-READ
        _ke KEY-IS-MOUSE? IF
            \ Extract row/col/button from mouse report
            _ke KEY-CODE@  DUP 8 RSHIFT  SWAP 255 AND  0
            DEVT-DISPATCH-MOUSE DROP
        ELSE
            _ke DEVT-DISPATCH DROP
        THEN
    AGAIN ;
```

### Register a click handler

```forth
: ON-BTN-CLICK  ( event node -- )
    DROP
    E.DETAIL2 @  . ." col clicked" CR ;

my-dome DOME-USE
DOME-TI-CLICK DOME-TYPE@  CONSTANT _t-click
my-button  _t-click  ' ON-BTN-CLICK  DOME-LISTEN
```

### Focus first input on load

```forth
my-doc  my-dome  DEVT-INIT
DEVT-FOCUS-NEXT                     \ focuses first DTUI-F-FOCUSABLE element
DEVT-FOCUS .                        \ → address of that element
```

---

## See Also

- [dom-tui.md](dom-tui.md) — Sidecar allocation and CSS resolution
- [dom-render.md](dom-render.md) — Layout and paint engine
- [keys.md](keys.md) — TUI keyboard / mouse input
- [event.md](../dom/event.md) — W3C-style DOM event dispatch
- [dom.md](../dom/dom.md) — DOM core (nodes, attributes, tree walk)
