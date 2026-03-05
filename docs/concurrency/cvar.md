# akashic-cvar — Concurrent Variables for KDOS / Megapad-64

Atomic cells with change notification.  A concurrent variable wraps
a memory cell with spinlock-protected read/write, compare-and-swap,
and wait-for-change semantics.

```forth
REQUIRE cvar.f
```

`PROVIDED akashic-cvar` — safe to include multiple times.
Automatically requires `event.f`.

---

## Table of Contents

- [Design Principles](#design-principles)
- [Data Structure](#data-structure)
- [CVAR — Define Concurrent Variable](#cvar--define-concurrent-variable)
- [CV@ — Atomic Read](#cv--atomic-read)
- [CV! — Atomic Write + Notify](#cv--atomic-write--notify)
- [CV-CAS — Compare-and-Swap](#cv-cas--compare-and-swap)
- [CV-ADD — Atomic Fetch-and-Add](#cv-add--atomic-fetch-and-add)
- [CV-WAIT — Block Until Changed](#cv-wait--block-until-changed)
- [CV-WAIT-TIMEOUT — Wait with Timeout](#cv-wait-timeout--wait-with-timeout)
- [CV-RESET — Reset for Testing](#cv-reset--reset-for-testing)
- [Debug](#debug)
- [Patterns](#patterns)
- [Concurrency Model](#concurrency-model)
- [Quick Reference](#quick-reference)

---

## Design Principles

| Principle | Implementation |
|-----------|---------------|
| **Spinlock-protected** | All reads and writes are guarded by a hardware spinlock (EVT-LOCK = 6 by default), ensuring atomicity even if 64-bit stores were not naturally atomic. |
| **Change notification** | Every write (`CV!`, `CV-ADD`, successful `CV-CAS`) pulses an embedded event, waking all `CV-WAIT` callers. |
| **Compare-and-swap** | `CV-CAS` provides lock-free-style programming patterns under the hood (still lock-protected, but the API supports CAS idioms). |
| **Lightweight** | 48 bytes per cvar (6 cells): value, lock#, and inline event. |
| **Prefix convention** | Public: `CV-`. Internal: `_CV-`. |

---

## Data Structure

Each concurrent variable occupies 6 cells = 48 bytes:

```
+0   value          Current value (one cell)
+8   lock#          Spinlock number (default: EVT-LOCK = 6)
+16  [event flag]   Embedded change-event (4 cells)
+24  [event wcnt]
+32  [event w0]
+40  [event w1]
```

The embedded event is pulsed (set then immediately reset) on every
successful mutation, enabling efficient `CV-WAIT` notification.

---

## CVAR — Define Concurrent Variable

```forth
0 CVAR request-count
42 CVAR threshold
```

**Signature:** `( initial "name" -- )`

Create a named concurrent variable initialized to `initial`.  Uses
`EVT-LOCK` (spinlock 6) for protection.

---

## CV@ — Atomic Read

```forth
request-count CV@   ( -- val )
```

**Signature:** `( cv -- val )`

Read the current value under spinlock protection.  On Megapad-64,
aligned 64-bit loads are naturally atomic, but the lock is included
for correctness on all platforms.

---

## CV! — Atomic Write + Notify

```forth
42 request-count CV!
```

**Signature:** `( val cv -- )`

Atomically store `val` and pulse the change-event to wake all
`CV-WAIT` callers.

---

## CV-CAS — Compare-and-Swap

```forth
0 1 my-flag CV-CAS   ( -- flag )
```

**Signature:** `( expected new cv -- flag )`

Atomically compare the current value with `expected`.  If they match,
store `new` and return TRUE (-1).  Otherwise, leave the value
unchanged and return FALSE (0).

On success, the change-event is pulsed.

```forth
\ Atomic toggle: 0 → 1
0 1 my-flag CV-CAS IF
    ." acquired" CR
ELSE
    ." contended" CR
THEN
```

---

## CV-ADD — Atomic Fetch-and-Add

```forth
1 request-count CV-ADD
```

**Signature:** `( n cv -- )`

Atomically add `n` to the value and pulse the change-event.  Works
with negative values for decrement.

```forth
\ Increment counter
1 request-count CV-ADD

\ Decrement counter
-1 request-count CV-ADD
```

---

## CV-WAIT — Block Until Changed

```forth
0 my-flag CV-WAIT   \ blocks until my-flag ≠ 0
```

**Signature:** `( expected cv -- )`

Block until the value differs from `expected`.  Uses the embedded
change-event for efficient notification.

**Protocol:**
1. Check current value — if already ≠ expected, return immediately.
2. `EVT-WAIT` on the change-event.
3. `EVT-RESET` the event.
4. Re-check value; if still = expected, loop.

On single-core, the value change must come from an ISR, timer, or
cooperative task (via `SCHEDULE`).  On multicore, another core can
call `CV!` or `CV-ADD`.

---

## CV-WAIT-TIMEOUT — Wait with Timeout

```forth
0 my-flag 5000 CV-WAIT-TIMEOUT   ( -- flag )
```

**Signature:** `( expected cv ms -- flag )`

Wait up to `ms` milliseconds for the value to differ from `expected`.
Returns TRUE (-1) if the value changed, FALSE (0) on timeout.

Includes a fast path: if the value already differs, returns TRUE
immediately without touching the event.

---

## CV-RESET — Reset for Testing

```forth
0 my-cvar CV-RESET
```

**Signature:** `( val cv -- )`

Force-set the value without notification and reset the embedded
event.  **Intended for testing and reinitialization only.**

---

## Debug

### CV-INFO

```forth
my-cvar CV-INFO
```

**Signature:** `( cv -- )`

Print status:

```
[cvar val=42  lock=6  evt:[event UNSET  waiters=0 ]
]
```

---

## Patterns

### Atomic Counter

```forth
0 CVAR request-count
: bump-count   1 request-count CV-ADD ;
: get-count    request-count CV@ ;
```

### Spin-CAS Lock

```forth
0 CVAR my-lock
: acquire  BEGIN 0 1 my-lock CV-CAS UNTIL ;
: release  0 my-lock CV! ;
```

### Wait for Threshold

```forth
0 CVAR progress
: wait-for-100  100 progress CV-WAIT ;
\ On another core:  100 progress CV!
```

### Cooperative Wait via SCHEDULE

```forth
\ Producer task body ( -- )
: producer  42 my-cvar CV! ;

\ Consumer code
0 my-cvar CV!
['] producer SPAWN SCHEDULE
my-cvar CV@ .    \ 42
```

---

## Concurrency Model

### Single-Core

On a single core, `CV-WAIT` will spin forever unless:
- The value was already different (fast path), or
- A cooperative task changes it (use `SPAWN` + `SCHEDULE`).

For single-core testing, use the fast-path pattern:

```forth
42 my-cvar CV!              \ set to 42
0 my-cvar CV-WAIT           \ returns immediately (42 ≠ 0)
```

### Multicore

On multicore, `CV-WAIT` spins with `YIELD?` checking the event.
Another core writes via `CV!` or `CV-ADD`, which pulses the
change-event and unblocks the waiter.

---

## Quick Reference

| Word | Signature | Description |
|------|-----------|-------------|
| `CVAR` | `( initial "name" -- )` | Create concurrent variable |
| `CV@` | `( cv -- val )` | Atomic read |
| `CV!` | `( val cv -- )` | Atomic write + notify |
| `CV-CAS` | `( exp new cv -- flag )` | Compare-and-swap |
| `CV-ADD` | `( n cv -- )` | Atomic fetch-and-add |
| `CV-WAIT` | `( exp cv -- )` | Block until value changes |
| `CV-WAIT-TIMEOUT` | `( exp cv ms -- flag )` | Wait with timeout |
| `CV-RESET` | `( val cv -- )` | Force-set without notify |
| `CV-INFO` | `( cv -- )` | Debug display |

### Constants

| Name | Value | Description |
|------|-------|-------------|
| `_CV-SIZE` | 48 | Bytes per cvar (6 cells) |

### Dependencies

- **event.f** — `EVT-PULSE`, `EVT-WAIT`, `EVT-RESET`, `EVT-LOCK`
