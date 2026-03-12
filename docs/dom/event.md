# akashic-dom-event — W3C-Style DOM Event System for KDOS / Megapad-64

Three-phase event dispatch (capture → target → bubble) with
listener registration, type interning, and pool-based allocation.
Companion to `dom.f` — uses the same arena, string pool, and
coding conventions.  Does **not** modify `dom.f`.

```forth
REQUIRE event.f
```

`PROVIDED akashic-dom-event` — safe to include multiple times.
Automatically loads `akashic-dom`.

**BIOS words used:** `MS@` (millisecond uptime counter, for event
timestamps).

---

## Table of Contents

- [Design Overview](#design-overview)
- [Dependencies](#dependencies)
- [Memory Architecture](#memory-architecture)
- [Constants](#constants)
- [DOME Lifecycle](#dome-lifecycle)
- [Event Objects](#event-objects)
- [Propagation Control](#propagation-control)
- [Type Interning](#type-interning)
- [Listener Registration](#listener-registration)
- [Dispatch](#dispatch)
- [Quick Reference](#quick-reference)
- [Internal Words](#internal-words)
- [Cookbook](#cookbook)

---

## Design Overview

| Principle | Detail |
|---|---|
| **Three-phase dispatch** | W3C model: capture (root → target), target, bubble (target → root). |
| **Pool-based** | Events, listeners, shadow table, and type registry are carved from the DOM document's string-pool region — no separate arena. |
| **Type interning** | Event type names are interned into the DOM string pool.  16 standard types are pre-registered; custom types can be added at runtime. |
| **Nested dispatch** | Up to 3 levels of re-entrant dispatch (e.g. a listener firing another event). |
| **Once listeners** | `DOME-LISTEN-ONCE` auto-removes the listener after first fire, cleaned up via a post-dispatch sweep. |
| **No DOM mutation** | event.f reads DOM node fields (parent chain, node base) but never modifies them. |

---

## Dependencies

```
event.f
└── dom.f   (akashic-dom)
```

Loaded automatically via `REQUIRE`.

---

## Memory Architecture

`DOME-INIT` carves all its structures from the **top** of the DOM
document's string pool (shrinking `D.STR-END` downward), so no
additional arena is required.

```
String pool (in DOM arena)
┌──────────────────────────────────────────────┐
│  strings grow →                  ← DOME data │
│  D.STR-PTR →              ← D.STR-END        │
│                                              │
│                  ┌───────────────────────────┤
│                  │ Type registry (256 B)     │
│                  │ Shadow table (8 × nodes)  │
│                  │ Event pool (640 B)        │
│                  │ Listener pool (40 × N)    │
│                  │ DOME descriptor (80 B)    │
│                  └───────────────────────────┘
└──────────────────────────────────────────────┘
```

### DOME Descriptor Layout (10 cells = 80 bytes)

| Offset | Field | Purpose |
|---|---|---|
| +0 | `ED.DOC` | Back-pointer to DOM document descriptor |
| +8 | `ED.LST-BASE` | Listener pool start address |
| +16 | `ED.LST-MAX` | Max listener slots |
| +24 | `ED.LST-FREE` | Listener free-list head |
| +32 | `ED.EVT-BASE` | Event object pool start |
| +40 | `ED.EVT-FREE` | Event object free-list head |
| +48 | `ED.SHADOW` | Shadow table base (1 cell per DOM node slot) |
| +56 | `ED.FOCUS` | Currently focused DOM node (0 = none) |
| +64 | `ED.TYPE-TBL` | Type registry array base |
| +72 | `ED.TYPE-CNT` | Number of registered types |

### Event Object Layout (10 cells = 80 bytes)

| Offset | Field | Purpose |
|---|---|---|
| +0 | `E.TYPE` | Interned type handle (string address) |
| +8 | `E.TARGET` | Node where event was dispatched |
| +16 | `E.CURRENT` | Node whose listener is currently executing |
| +24 | `E.PHASE` | Current `DOME-PHASE-*` value |
| +32 | `E.FLAGS` | `DOME-F-*` flag bits |
| +40 | `E.TSTAMP` | `MS@` value at creation |
| +48 | `E.DETAIL` | Generic payload cell 1 |
| +56 | `E.DETAIL2` | Generic payload cell 2 |
| +64 | `E.DETAIL3` | Generic payload cell 3 |
| +72 | `E.RELATED` | Related node (e.g. relatedTarget) |

### Listener Entry Layout (5 cells = 40 bytes)

| Offset | Field | Purpose |
|---|---|---|
| +0 | `L.TYPE` | Event type handle |
| +8 | `L.XT` | Execution token `( event node -- )` |
| +16 | `L.FLAGS` | `DOME-LF-*` flag bits |
| +24 | `L.NEXT` | Next listener in node's list (0 = end) |
| +32 | `L.NODE` | Back-pointer to owning DOM node |

---

## Constants

### Dispatch Phases

| Constant | Value | Description |
|---|---|---|
| `DOME-PHASE-CAPTURE` | 1 | Capture phase (root → target) |
| `DOME-PHASE-TARGET` | 2 | Target phase |
| `DOME-PHASE-BUBBLE` | 3 | Bubble phase (target → root) |

### Event Flags (in `E.FLAGS`)

| Constant | Value | Description |
|---|---|---|
| `DOME-F-BUBBLES` | 1 | Event will bubble |
| `DOME-F-CANCELABLE` | 2 | `preventDefault` is allowed |
| `DOME-F-STOPPED` | 4 | `stopPropagation` was called |
| `DOME-F-IMMEDIATE` | 8 | `stopImmediatePropagation` was called |
| `DOME-F-PREVENTED` | 16 | `preventDefault` was called |

### Listener Flags (in `L.FLAGS`)

| Constant | Value | Description |
|---|---|---|
| `DOME-LF-CAPTURE` | 1 | Listener fires during capture phase |
| `DOME-LF-ONCE` | 2 | Auto-remove after first fire |

### Standard Type Indices (slots 0–15)

| Constant | Index | Type Name |
|---|---|---|
| `DOME-TI-CLICK` | 0 | `"click"` |
| `DOME-TI-DBLCLICK` | 1 | `"dblclick"` |
| `DOME-TI-MOUSEDOWN` | 2 | `"mousedown"` |
| `DOME-TI-MOUSEUP` | 3 | `"mouseup"` |
| `DOME-TI-MOUSEMOVE` | 4 | `"mousemove"` |
| `DOME-TI-KEYDOWN` | 5 | `"keydown"` |
| `DOME-TI-KEYUP` | 6 | `"keyup"` |
| `DOME-TI-KEYPRESS` | 7 | `"keypress"` |
| `DOME-TI-FOCUS` | 8 | `"focus"` |
| `DOME-TI-BLUR` | 9 | `"blur"` |
| `DOME-TI-INPUT` | 10 | `"input"` |
| `DOME-TI-CHANGE` | 11 | `"change"` |
| `DOME-TI-SUBMIT` | 12 | `"submit"` |
| `DOME-TI-SCROLL` | 13 | `"scroll"` |
| `DOME-TI-RESIZE` | 14 | `"resize"` |
| `DOME-TI-CUSTOM` | 15 | `"custom"` |

### Pool/Size Constants

| Constant | Value | Description |
|---|---|---|
| `DOME-EVT-SIZE` | 80 | Bytes per event object |
| `DOME-LST-SIZE` | 40 | Bytes per listener entry |
| `DOME-DESC-SIZE` | 80 | Bytes per DOME descriptor |
| `DOME-EVT-POOL-COUNT` | 8 | Recycling pool capacity |
| `DOME-MAX-TYPES` | 32 | Type registry capacity |
| `DOME-MAX-DEPTH` | 64 | Max ancestor path depth |

---

## DOME Lifecycle

| Word | Stack | Description |
|---|---|---|
| `DOME-INIT` | `( doc max-listeners -- dome )` | Create a DOME instance for the given DOM document.  Carves all pools from the string pool.  Registers 16 standard event types.  Calls `DOME-USE` and `DOM-USE`. |
| `DOME-INIT-DEFAULT` | `( doc -- dome )` | Shorthand: `256 DOME-INIT`. |
| `DOME-USE` | `( dome -- )` | Set `dome` as the current DOME for all subsequent operations. |
| `DOME-CUR` | `( -- dome )` | Return the current DOME handle. |

### Example

```forth
my-arena 64 64 DOM-DOC-NEW CONSTANT my-doc
DOM-HTML-INIT
my-doc DOME-INIT-DEFAULT CONSTANT my-dome
```

Teardown: destroying the arena frees everything (DOM + DOME).

---

## Event Objects

| Word | Stack | Description |
|---|---|---|
| `DOME-EVENT-NEW` | `( type bubbles? cancelable? -- event )` | Allocate an event from the pool.  `type` is an interned handle (use `DOME-TYPE@`).  Flags are set from the boolean args.  Timestamp set to `MS@`. |
| `DOME-EVENT-FREE` | `( event -- )` | Return an event to the pool. |

### Event Getters

| Word | Stack | Description |
|---|---|---|
| `DOME-EVENT-TYPE` | `( event -- type )` | Interned type handle |
| `DOME-EVENT-TARGET` | `( event -- node )` | Original target node |
| `DOME-EVENT-CURRENT` | `( event -- node )` | Node whose listener is executing |
| `DOME-EVENT-PHASE` | `( event -- phase )` | Current dispatch phase |
| `DOME-EVENT-TSTAMP` | `( event -- ms )` | Creation timestamp |
| `DOME-EVENT-DETAIL` | `( event -- d )` | Detail payload cell 1 |
| `DOME-EVENT-DETAIL2` | `( event -- d )` | Detail payload cell 2 |
| `DOME-EVENT-DETAIL3` | `( event -- d )` | Detail payload cell 3 |
| `DOME-EVENT-RELATED` | `( event -- node\|0 )` | Related target node |

### Event Setters

| Word | Stack | Description |
|---|---|---|
| `DOME-EVENT-DETAIL!` | `( d event -- )` | Set detail cell 1 |
| `DOME-EVENT-DETAIL2!` | `( d event -- )` | Set detail cell 2 |
| `DOME-EVENT-DETAIL3!` | `( d event -- )` | Set detail cell 3 |
| `DOME-EVENT-RELATED!` | `( node event -- )` | Set related target |

---

## Propagation Control

| Word | Stack | Description |
|---|---|---|
| `DOME-STOP` | `( event -- )` | Stop propagation after current node's listeners finish. |
| `DOME-STOP-IMMEDIATE` | `( event -- )` | Stop propagation immediately — remaining listeners on the current node are skipped. |
| `DOME-PREVENT` | `( event -- )` | Prevent default action (only if event is cancelable). |
| `DOME-STOPPED?` | `( event -- flag )` | True if `DOME-STOP` was called. |
| `DOME-IMMEDIATE?` | `( event -- flag )` | True if `DOME-STOP-IMMEDIATE` was called. |
| `DOME-PREVENTED?` | `( event -- flag )` | True if `DOME-PREVENT` was called. |

---

## Type Interning

Event types are interned strings stored in the DOM string pool.  The
16 standard types are pre-registered at indices 0–15 during
`DOME-INIT`.

| Word | Stack | Description |
|---|---|---|
| `DOME-INTERN-TYPE` | `( addr len -- type-handle )` | Intern a type name.  Returns existing handle on match (case-insensitive), or allocates a new slot. |
| `DOME-TYPE-NAME` | `( type-handle -- addr len )` | Retrieve the string for an interned type. |
| `DOME-TYPE@` | `( index -- handle )` | Look up a type handle by registry index (e.g. `DOME-TI-CLICK DOME-TYPE@`). |

### Example

```forth
\ Use a standard type
DOME-TI-CLICK DOME-TYPE@    \ handle for "click"

\ Register a custom type
S" dragstart" DOME-INTERN-TYPE CONSTANT my-drag-type
```

---

## Listener Registration

Listener callbacks have the signature: `( event node -- )`.

| Word | Stack | Description |
|---|---|---|
| `DOME-LISTEN` | `( node type xt -- )` | Register a bubble-phase listener. |
| `DOME-LISTEN-CAPTURE` | `( node type xt -- )` | Register a capture-phase listener. |
| `DOME-LISTEN-ONCE` | `( node type xt -- )` | Register a one-shot listener (auto-removed after first fire). |
| `DOME-UNLISTEN` | `( node type xt -- )` | Remove the first listener matching type + xt. |
| `DOME-UNLISTEN-ALL` | `( node -- )` | Remove every listener from a node. |
| `DOME-HAS-LISTENER?` | `( node type -- flag )` | True if node has any listener for the given type. |

### Example

```forth
: on-click  ( event node -- )
    DROP DOME-EVENT-DETAIL . CR ;

DOM-BODY  DOME-TI-CLICK DOME-TYPE@  ['] on-click  DOME-LISTEN
```

---

## Dispatch

### Three-Phase Dispatch

`DOME-DISPATCH` implements the full W3C dispatch algorithm:

1. **Build path** — walk `N.PARENT` from target to root.
2. **Capture phase** — fire matching capture listeners from root down
   to the target's parent.
3. **Target phase** — fire all matching listeners on the target
   (both capture and bubble listeners fire at target phase).
4. **Bubble phase** — if the event has `DOME-F-BUBBLES`, fire matching
   non-capture listeners from target's parent up to root.
5. **Cleanup** — sweep dead once-listeners from all path nodes.

`stopPropagation` halts dispatch at the end of the current node.
`stopImmediatePropagation` halts dispatch immediately (remaining
listeners on the current node are skipped).

| Word | Stack | Description |
|---|---|---|
| `DOME-DISPATCH` | `( node event -- prevented? )` | Full three-phase dispatch.  Returns true if `preventDefault` was called. |
| `DOME-FIRE` | `( node type detail -- prevented? )` | Convenience: creates a bubbling+cancelable event, dispatches it, frees it.  `type` is a handle (use `DOME-TYPE@`). |

### Example

```forth
\ Manual dispatch
DOME-TI-CLICK DOME-TYPE@  -1 -1  DOME-EVENT-NEW
42 OVER DOME-EVENT-DETAIL!
my-div SWAP DOME-DISPATCH
IF ." default prevented" CR THEN

\ Quick fire
my-div  DOME-TI-CLICK DOME-TYPE@  42  DOME-FIRE
IF ." default prevented" CR THEN
```

---

## Quick Reference

```
DOME-INIT           ( doc max-listeners -- dome )
DOME-INIT-DEFAULT   ( doc -- dome )
DOME-USE            ( dome -- )
DOME-CUR            ( -- dome )

DOME-EVENT-NEW      ( type bubbles? cancelable? -- event )
DOME-EVENT-FREE     ( event -- )
DOME-EVENT-TYPE     ( event -- type )
DOME-EVENT-TARGET   ( event -- node )
DOME-EVENT-CURRENT  ( event -- node )
DOME-EVENT-PHASE    ( event -- phase )
DOME-EVENT-DETAIL   ( event -- d )
DOME-EVENT-DETAIL!  ( d event -- )
DOME-EVENT-TSTAMP   ( event -- ms )

DOME-STOP           ( event -- )
DOME-STOP-IMMEDIATE ( event -- )
DOME-PREVENT        ( event -- )
DOME-STOPPED?       ( event -- flag )
DOME-IMMEDIATE?     ( event -- flag )
DOME-PREVENTED?     ( event -- flag )

DOME-INTERN-TYPE    ( addr len -- type-handle )
DOME-TYPE-NAME      ( type-handle -- addr len )
DOME-TYPE@          ( index -- handle )

DOME-LISTEN         ( node type xt -- )
DOME-LISTEN-CAPTURE ( node type xt -- )
DOME-LISTEN-ONCE    ( node type xt -- )
DOME-UNLISTEN       ( node type xt -- )
DOME-UNLISTEN-ALL   ( node -- )
DOME-HAS-LISTENER?  ( node type -- flag )

DOME-DISPATCH       ( node event -- prevented? )
DOME-FIRE           ( node type detail -- prevented? )
```

---

## Internal Words

These are implementation details and should not be called directly.

| Word | Purpose |
|---|---|
| `_DOME-CARVE` | Carve bytes from string pool top |
| `_DOME-EVT-INIT-FREE` | Build event pool free-list |
| `_DOME-LST-INIT-FREE` | Build listener pool free-list |
| `_DOME-LST-ALLOC` | Allocate a listener from the pool |
| `_DOME-LST-FREE` | Return a listener to the pool |
| `_DOME-SHADOW` | Compute shadow table cell address for a node |
| `_DOME-BUILD-PATH` | Build ancestor path array for dispatch |
| `_DOME-SHOULD-FIRE?` | Check if a listener fires in a given phase |
| `_DOME-FIRE-ON` | Fire all matching listeners on a single node |
| `_DOME-CLEANUP-ONCE` | Sweep dead once-listeners after dispatch |
| `_DOME-INTERN-STD-TYPES` | Register the 16 standard type names |
| `_DOME-LISTEN-INNER` | Shared listener registration core |

---

## Cookbook

### Click handler with detail

```forth
: on-click  ( event node -- )
    DROP
    ." Clicked! detail=" DOME-EVENT-DETAIL . CR ;

DOM-BODY  DOME-TI-CLICK DOME-TYPE@  ['] on-click  DOME-LISTEN

\ Fire a click with detail=99
DOM-BODY  DOME-TI-CLICK DOME-TYPE@  99  DOME-FIRE DROP
```

### Capture listener (intercept before target)

```forth
: log-capture  ( event node -- )
    DROP ." [capture] " DOME-EVENT-PHASE . CR ;

DOM-BODY  DOME-TI-KEYDOWN DOME-TYPE@  ['] log-capture  DOME-LISTEN-CAPTURE
```

### One-shot listener

```forth
: once-handler  ( event node -- )
    2DROP ." fired once!" CR ;

my-div  DOME-TI-CLICK DOME-TYPE@  ['] once-handler  DOME-LISTEN-ONCE
\ First dispatch fires it; second dispatch does nothing.
```

### Prevent default

```forth
: block-submit  ( event node -- )
    DROP DOME-PREVENT ;

my-form  DOME-TI-SUBMIT DOME-TYPE@  ['] block-submit  DOME-LISTEN

my-form  DOME-TI-SUBMIT DOME-TYPE@  0  DOME-FIRE
IF ." submit was blocked" CR THEN
```

### Custom event type

```forth
S" tab-switch" DOME-INTERN-TYPE CONSTANT MY-TAB-SWITCH

: on-tab  ( event node -- )
    DROP ." switching to tab " DOME-EVENT-DETAIL . CR ;

my-tabbar  MY-TAB-SWITCH  ['] on-tab  DOME-LISTEN

\ Fire with tab index 3
my-tabbar  MY-TAB-SWITCH  3  DOME-FIRE DROP
```
