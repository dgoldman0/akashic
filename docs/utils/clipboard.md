# akashic-clipboard — Clipboard Ring Buffer for KDOS / Megapad-64

A general-purpose clipboard with a configurable ring of entries.
Each entry holds an independent, XMEM-allocated byte buffer —
no precious Bank 0 heap space is consumed for content storage.
Content is untyped bytes — the caller decides semantics.

```forth
REQUIRE clipboard.f
```

`PROVIDED akashic-clipboard` — safe to include multiple times.

---

## Table of Contents

- [Design Principles](#design-principles)
- [Ring Layout](#ring-layout)
- [Initialisation](#initialisation)
- [Copy](#copy)
- [Paste / Query](#paste--query)
- [Drop](#drop)
- [Lifecycle](#lifecycle)
- [Diagnostics](#diagnostics)
- [Quick Reference](#quick-reference)
- [Usage Examples](#usage-examples)

---

## Design Principles

| Principle | Implementation |
|-----------|---------------|
| **Ring buffer** | Fixed number of slots (default 8).  Newest at logical 0, oldest evicted on overflow. |
| **XMEM-backed** | Each entry uses `XMEM-ALLOT` / `XMEM-FREE-BLOCK`.  No arenas — entries have independent lifetimes.  Keeps Bank 0 heap free. |
| **Grow-reuse** | If an existing slot buffer has sufficient capacity, it is reused without reallocation. |
| **64-byte rounding** | Allocation sizes are rounded up to 64-byte boundaries to reduce churn. |
| **Zero-copy paste** | `CLIP-PASTE` returns a direct pointer into the XMEM buffer.  Valid until the next `CLIP-COPY` that evicts that slot. |
| **Untyped** | Content is raw bytes + length.  No MIME types, no metadata. |
| **Single global instance** | KDOS is single-process; one clipboard serves all widgets and apps. |
| **Prefix convention** | Public: `CLIP-`.  Internal: `_CLIP-`. |

---

## Ring Layout

The ring occupies a statically `ALLOT`'d block in the dictionary.
Each of the `CLIP-RING-SIZE` (default 8) slots is 24 bytes:

```
Offset  Size   Field
──────  ─────  ─────────────
+0      8      addr     XMEM pointer to content (0 if empty)
+8      8      len      Current content length (bytes)
+16     8      cap      Allocated capacity in bytes (XMEM block size)
```

Total static footprint: `CLIP-RING-SIZE × 24` = 192 bytes.

The XMEM buffers are allocated on demand via `XMEM-ALLOT` and freed
individually via `XMEM-FREE-BLOCK`.  There is no XMEM RESIZE, so
growing a slot allocates a new block, copies data, then frees the old.

### Indexing

- **Physical index**: position in the `_CLIP-RING` array (0..7).
- **Logical index**: 0 = most recent copy, 1 = previous, etc.
- `_CLIP-HEAD` tracks the physical index of the most recent entry.
- Conversion: `physical = (head - logical + RING-SIZE) mod RING-SIZE`.

---

## Initialisation

### `CLIP-INIT`

```forth
CLIP-INIT ( -- )
```

Free all slot buffers and reset the ring to empty.
Called automatically at load time (the ring is zeroed).
Call explicitly to reset the clipboard at runtime.

---

## Copy

### `CLIP-COPY`

```forth
CLIP-COPY ( addr len -- ior )
```

Push a new entry onto the ring.  Copies `len` bytes from `addr`
into an XMEM-allocated buffer in the next ring slot.

**Behaviour:**

1. Advances the head pointer to the next physical slot.
2. If the ring is full (`CLIP-COUNT = CLIP-RING-SIZE`), evicts the
   oldest entry — frees its XMEM buffer via `XMEM-FREE-BLOCK`.
3. If the target slot already has a buffer with sufficient capacity,
   reuses it (no allocation).  Otherwise allocates a new XMEM block
   via `XMEM-ALLOT`, copies data, then frees the old block.
4. `CMOVE`s the source bytes into the slot buffer.
5. Returns `0` on success, `-1` on XMEM allocation failure.

Zero-length copies are permitted — they store an empty entry (no
allocation) that reads back as `0 0` from `CLIP-PASTE`.

```forth
S" Hello, world!" CLIP-COPY DROP   \ push 13-byte entry
```

---

## Paste / Query

### `CLIP-PASTE`

```forth
CLIP-PASTE ( -- addr len )
```

Return the most recent clipboard entry.  Returns `0 0` if empty.

The returned `addr` points directly into the XMEM buffer.  It is
valid until the next `CLIP-COPY` that overwrites or evicts that
physical slot.  If you need the data to survive beyond that, copy
it out.

```forth
CLIP-PASTE TYPE    \ print most recent clipboard content
```

### `CLIP-PASTE-N`

```forth
CLIP-PASTE-N ( n -- addr len )
```

Return the Nth most recent entry.  `0 CLIP-PASTE-N` is equivalent
to `CLIP-PASTE`.  Returns `0 0` if `n >= CLIP-COUNT`.

```forth
2 CLIP-PASTE-N TYPE    \ print the entry from 2 copies ago
```

### `CLIP-LEN`

```forth
CLIP-LEN ( -- n )
```

Length of the most recent entry in bytes.  `0` if empty.

### `CLIP-COUNT`

```forth
CLIP-COUNT ( -- n )
```

Number of occupied entries in the ring (0..`CLIP-RING-SIZE`).

### `CLIP-EMPTY?`

```forth
CLIP-EMPTY? ( -- flag )
```

True if the ring has no entries.

---

## Drop

### `CLIP-DROP`

```forth
CLIP-DROP ( -- )
```

Discard the most recent entry — free its XMEM buffer, rewind the
head pointer, decrement the count.  No-op if empty.

```forth
CLIP-DROP    \ remove the last thing copied
```

---

## Lifecycle

### `CLIP-CLEAR`

```forth
CLIP-CLEAR ( -- )
```

Free all entries and reset the ring.  Alias for `CLIP-INIT`.

### `CLIP-DESTROY`

```forth
CLIP-DESTROY ( -- )
```

Teardown — free all entries.  Call on application exit.
Alias for `CLIP-INIT`.

---

## Diagnostics

### `.CLIP`

```forth
.CLIP ( -- )
```

Print the clipboard status and all occupied ring entries:

```
Clipboard: count=3  ring-size=8  head=2
  [0 ] addr=54321 len=13 cap=64
  [1 ] addr=54400 len=7 cap=64
  [2 ] addr=54480 len=256 cap=320
```

---

## Quick Reference

| Word | Stack Effect | Description |
|------|-------------|-------------|
| `CLIP-INIT` | `( -- )` | Free all entries, reset ring |
| `CLIP-COPY` | `( addr len -- ior )` | Push new entry (copy bytes) |
| `CLIP-PASTE` | `( -- addr len )` | Most recent entry (zero-copy) |
| `CLIP-PASTE-N` | `( n -- addr len )` | Nth most recent entry |
| `CLIP-LEN` | `( -- n )` | Length of most recent entry |
| `CLIP-COUNT` | `( -- n )` | Number of occupied entries |
| `CLIP-EMPTY?` | `( -- flag )` | True if ring is empty |
| `CLIP-DROP` | `( -- )` | Discard most recent entry |
| `CLIP-CLEAR` | `( -- )` | Free all entries (= `CLIP-INIT`) |
| `CLIP-DESTROY` | `( -- )` | Teardown (= `CLIP-INIT`) |
| `.CLIP` | `( -- )` | Print ring status |
| `CLIP-RING-SIZE` | `( -- 8 )` | Constant: ring capacity |

---

## Usage Examples

### Basic copy/paste

```forth
REQUIRE clipboard.f

CREATE my-buf 256 ALLOT
S" First copy" my-buf SWAP CMOVE
my-buf 10 CLIP-COPY DROP

S" Second copy" my-buf SWAP CMOVE
my-buf 11 CLIP-COPY DROP

CLIP-PASTE TYPE CR          \ → Second copy
1 CLIP-PASTE-N TYPE CR      \ → First copy
CLIP-COUNT .                \ → 2
```

### Ring eviction

```forth
\ With CLIP-RING-SIZE = 8, the 9th CLIP-COPY evicts the 1st.
\ The caller does not need to manage this — it happens automatically.
```

### Integration with a text widget

```forth
\ In a Ctrl+C handler:
: MY-COPY  ( sel-addr sel-len -- )
    CLIP-COPY DROP ;

\ In a Ctrl+V handler:
: MY-PASTE  ( -- )
    CLIP-PASTE  DUP 0= IF 2DROP EXIT THEN
    \ ... insert addr len into the edit buffer ...
    ;
```
