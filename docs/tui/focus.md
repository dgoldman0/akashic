# akashic/tui/focus.f — Focus Manager

**Layer:** 6  
**Lines:** 280  
**Prefix:** `FOC-` (public), `_FOC-` (internal)  
**Provider:** `akashic-tui-focus`  
**Dependencies:** `keys.f`, `widget.f`

## Overview

Manages which widget receives keyboard input.  Maintains a focus
chain as a circular singly-linked list stored in fixed-size parallel
arrays (max 32 entries).  Tab / Shift-Tab cycles focus; explicit
set/get is also available.

The chain lives outside the widget headers — each slot in the
parallel arrays stores a widget address and a next-index.  This
avoids adding fields to every widget descriptor.

## Data Model

```
_FOC-WIDGETS[0.._FOC-MAX]   — widget pointers  (index 0 = unused sentinel)
_FOC-NEXT-IDX[0.._FOC-MAX]  — next-index links
_FOC-CUR                     — index of the currently focused slot
_FOC-CNT                     — entry count
```

Ring topology: the chain is a circular singly-linked list.
Insertion with `FOC-ADD` places the new widget **after** the
current focus, so adding A → B → C yields ring order A → C → B → A.

## API Reference

### Chain Management

| Word | Stack | Description |
|------|-------|-------------|
| `FOC-ADD` | `( widget -- )` | Add widget after current in ring. Duplicate adds are ignored. Silently drops if chain is full (32). |
| `FOC-REMOVE` | `( widget -- )` | Remove widget from chain. If focused widget is removed, focus moves to next. If last widget, chain becomes empty. |
| `FOC-CLEAR` | `( -- )` | Zero all slots, reset current and count. Called automatically at load time. |
| `FOC-COUNT` | `( -- n )` | Number of widgets currently in the focus chain. |

### Focus Navigation

| Word | Stack | Description |
|------|-------|-------------|
| `FOC-NEXT` | `( -- )` | Move focus to next widget in ring. Clears FOCUSED flag on old, sets on new. No-op if empty. |
| `FOC-PREV` | `( -- )` | Move focus to previous widget (walks backward). Clears/sets flags. No-op if empty. |
| `FOC-SET` | `( widget -- )` | Explicitly set focus to widget. Ignored if widget not in chain. Clears old FOCUSED, sets new. |
| `FOC-GET` | `( -- widget \| 0 )` | Return currently focused widget address, or 0 if empty. |

### Event Dispatch

| Word | Stack | Description |
|------|-------|-------------|
| `FOC-DISPATCH` | `( event-addr -- )` | Call `WDG-HANDLE` on focused widget. No-op if empty. Consumed flag is dropped. |

### Iteration

| Word | Stack | Description |
|------|-------|-------------|
| `FOC-EACH` | `( xt -- )` | Call `xt ( widget -- )` once per chain entry. Iterates all occupied slots (not ring-order). |

## Guard Support

When `GUARDED` is defined, all public words are wrapped with
`_foc-guard WITH-GUARD` for thread-safety.

## Design Notes

- **Max 32 entries.**  The parallel arrays are statically allocated at
  compile time.  `_FOC-ALLOC` performs a linear scan for a free slot.
- **Insert-after-current.**  `FOC-ADD` inserts the new node between the
  current node and its successor.  This keeps the current focus stable.
- **FOC-REMOVE of focused widget** advances focus to the next node before
  unlinking, so the user never sees a dangling focus.
- **FOC-EACH** iterates by scanning all slots 1.._FOC-MAX (not by
  following ring links), so it visits every entry exactly once regardless
  of ring structure.  Used by `focus-2d.f` for spatial scanning.
- **WDG-FOCUSED flag** is managed automatically by `FOC-SET`, `FOC-NEXT`,
  `FOC-PREV`, and `FOC-REMOVE`.

## Test Coverage

34 tests in `local_testing/test_focus.py` (shared with focus-2d.f):

- §B: FOC-ADD / FOC-GET / FOC-COUNT (4 tests)
- §C: FOC-NEXT / FOC-PREV ring cycling (4 tests)
- §D: FOC-SET explicit focus (3 tests)
- §E: FOC-REMOVE (3 tests)
- §F: FOC-CLEAR (1 test)
- §G: FOC-DISPATCH (2 tests)
- §H: FOC-EACH (2 tests)
