# akashic-tui-screen — Virtual Screen Buffer

Double-buffered character-cell screen. Widgets write to the back buffer via
`SCR-SET` or a bounded mutable-plane borrow. `SCR-FLUSH?` admits an exact
transaction for the selected backend; ANSI is the default backend, while the
same CELL lifecycle can feed an attached rich publisher.

```forth
REQUIRE tui/screen.f
```

`PROVIDED akashic-tui-screen` — safe to include multiple times.

**Dependencies:** `cell.f`, `ansi.f`, `../text/utf8.f`,
`../text/cell-width.f`, `../utils/term.f`, `../utils/memory-span.f`

---

## Table of Contents

- [Design Principles](#design-principles)
- [Screen Descriptor](#screen-descriptor)
- [Constructor / Destructor](#constructor--destructor)
- [Current Screen](#current-screen)
- [Accessors](#accessors)
- [Storage Authority](#storage-authority)
- [Cell Read / Write](#cell-read--write)
- [Fill / Clear](#fill--clear)
- [Cursor Management](#cursor-management)
- [Flush Algorithm](#flush-algorithm)
- [Force Redraw](#force-redraw)
- [Resize](#resize)
- [Memory](#memory)
- [Quick Reference](#quick-reference)

---

## Design Principles

| Principle | Implementation |
|-----------|---------------|
| **Double-buffered** | Front buffer = screen state, back buffer = pending state. Flush diffs. |
| **Differential flush** | Writes union conservative candidate rows; admission compares only those rows and emits exact changed spans. |
| **One current screen** | `SCR-USE` selects the target. All drawing words use `_SCR-CUR`. |
| **Owned allocation** | Descriptor and buffers use the platform `ALLOCATE`/`FREE` path. |
| **Prefix convention** | Public: `SCR-`. Internal: `_SCR-`. |
| **Not reentrant** | Scratch `VARIABLE`s are shared; call from one task only. |

---

## Screen Descriptor

Each screen is a 29-cell (232-byte) descriptor, four cell buffers, three
one-byte-per-row maps, one byte of foreground provenance per cell, and,
once it holds a character of several scalars, a cluster pool of two more
allocations.  All use the platform allocator, which selects reclaiming XMEM
when it is available and the Bank 0 heap otherwise.

| Offset | Field | Description |
|--------|-------|-------------|
| +0 | width | Columns |
| +8 | height | Rows |
| +16 | front | Address of front buffer (width × height cells) |
| +24 | back | Address of back buffer (width × height cells) |
| +32 | cursor-row | Current cursor row (0-based) |
| +40 | cursor-col | Current cursor column (0-based) |
| +48 | cursor-vis | Cursor visible flag (0 = hidden, -1 = visible) |
| +56 | dirty | Global dirty flag |
| +64 | force | Next accepted transaction is a complete snapshot |
| +72 | backend | Borrowed transactional backend descriptor |
| +80 | flush-request | Retained-only work requests a neutral transaction |
| +88 | draw-generation | Latest completed ordinary top-level draw |
| +96 | front-generation | Draw generation accepted into the front plane |
| +104 | damage | Exact admitted one-byte-per-row retry plan |
| +112 | touched | Conservative rows written since accepted commit |
| +120 | occlusion | Final-writer foreground provenance, one byte per cell |
| +128 | residue | Ordinary pixels beneath independently replaceable paint |
| +136 | residue-dirty | Pending or exact residue difference from accepted commit |
| +144 | residue-damage | Candidate rows, resolved to exact final differences before projection |
| +152 | residue-front | Residue baseline from the accepted transaction |
| +160 | cluster tables | ID and content hash tables, or 0 |
| +168 | cluster slots | Slots per table |
| +176 | cluster arena | Cluster entries, or 0 |
| +184 | arena capacity | Arena bytes |
| +192 | arena used | Arena bytes in use |
| +200 | cluster count | Clusters in the arena |
| +208 | next ID | Next cluster ID |
| +216 | pass number | Mark passes made |
| +224 | pass trigger | Count that starts the next pass |

---

## Constructor / Destructor

### SCR-NEW

```
( w h -- scr )
```

Allocate the descriptor, four cell buffers, three row maps, and provenance
through `ALLOCATE`. All CELL planes start with `CELL-BLANK`; the maps and
provenance start empty. Capacity follows the caller's dimensions. Partial construction
releases every allocation already acquired before reporting failure.

```forth
80 24 SCR-NEW   \ standard 80×24 terminal
```

### SCR-FREE

```
( scr -- )
```

Detach the screen if it is current, then return all cell buffers, row maps,
provenance, and the descriptor through `FREE`.

---

## Current Screen

### SCR-USE

```
( scr -- )
```

Set `scr` as the current screen.  All cell read/write, fill, flush,
and cursor words operate on the current screen.

```forth
80 24 SCR-NEW DUP SCR-USE   \ create and activate
```

---

## Accessors

| Word | Stack | Description |
|------|-------|-------------|
| `SCR-W` | `( -- w )` | Width of current screen in columns |
| `SCR-H` | `( -- h )` | Height of current screen in rows |
| `SCR-PROJECTION-DIRTY?` | `( -- flag )` | Final residue differs from accepted commit, including when BACK is unchanged |

`SCR-WITH-PROJECTION-PLANES ( xt -- ... )` lends
`( back-a residue-a cols rows draw-generation residue-dirty? -- ... )` to one
synchronous read-only callback. `SCR-WITH-PROJECTION-FRAME-PLANES` lends
`( front-a back-a cols rows front-draw draw force? damage-a damage-u residue-a residue-damage-a residue-damage-u -- ... )`.
Each callback holds one screen guard; pointers must not escape, mutate the
screen, or survive a yield. Existing BACK and FRAME borrow signatures remain
unchanged.

Ordinary writes update both BACK and residue. A neutral `DRW-REPLACEMENT`
scope still updates BACK completely, while preserving the underlying residue.
This works across partial redraws; it does not recapture an old popup as its
own background. Post-semantic foreground paint remains in both planes.
Projection queries compare candidate rows against the accepted residue plane.
A clear followed by restoration of the same content resolves to clean; an
underlay change remains dirty even if the final BACK bytes are unchanged.
The borrowed damage map contains zero for equal rows and nonzero for unequal
rows. Refused transactions retain the accepted baseline, so a later redraw
can still restore it. Only accepted commit advances that baseline. Resize
copies BACK and residue, initializes both committed planes blank, and forces
a complete snapshot before incremental reuse.

---

## Characters in Cells

Cells follow the shared text rules (`docs/rich-terminal/APT-1-TEXT.md`).  A
character is a grapheme cluster.  A wide character takes a lead cell with
`CELL-A-WIDE` and the cell to its right, a `CELL-A-CONT` cell with codepoint 0
and the lead's style.  Every write keeps each row's pairs whole: a wide lead
writes its continuation, a continuation restyles its lead, a write that breaks
a pair turns the other half into a space in its own style, and a wide lead
that would not fit at the right edge becomes a space.  A one-scalar cell's
`WIDE` bit is set from its width, and a scalar that the text rules replace
(`Cc`, `Zl`, `Zp`, or not a scalar at all) becomes U+FFFD.

A character of several scalars lives in the screen's **cluster pool**: its
cell's codepoint field has `CELL-CP-CLUSTER` (bit 31) set and holds the
cluster's ID.  Clusters are interned, so equal characters make equal cells
and the flush diff compares them exactly.  IDs are never reused.  After an
accepted flush that finds enough new clusters, one mark-and-sweep pass over
the four CELL planes frees each cluster that neither that pass nor the one
before found, and compacts the rest.

| Word | Stack | Description |
|------|-------|-------------|
| `SCR-CLUSTER` | `( a n -- cp )` | Intern `n` ≥ 2 u32 scalars at `a`; U+FFFD if the pool is full |
| `SCR-CLUSTER@` | `( cell -- a n )` | A cluster cell's scalars, valid until the next draw or flush; `0 0` if unknown |
| `SCR-CLUSTER-WORDS` | `( cell -- n )` | Its CELL-1 cluster-tail words; 0 for one scalar |

The drawing layer writes borrowed planes through `SCR-CELL-NORMALIZE`,
`SCR-CELL-PAIR?`, `SCR-CELL-SPACE`, and `SCR-ROW-PUT ( cell col row-a cols --
lo hi )`, which apply the same rules to one plane row inside
`SCR-WITH-BACK-MUTATION`.

---

## Storage Authority

`SCR-STORAGE-DISJOINT? ( a u -- flag )` validates the active screen and proves
that a canonical caller span does not overlap screen-owned module storage, the
current descriptor, all four CELL planes, all row maps, provenance, the cluster
pool, or the bound backend descriptor. `(0,0)` is the only accepted empty span and still requires
a structurally valid active screen. The backend context is opaque; callers
must also use its owning API when that context is in their storage graph.

---

## Cell Read / Write

### SCR-SET

```
( cell row col -- )
```

Write a cell to the back buffer at the given (row, col) position.
Row and column are 0-based.  Wide pairs stay whole, as described under
[Characters in Cells](#characters-in-cells).

```forth
65 14 0 CELL-A-BOLD CELL-MAKE  0 0 SCR-SET   \ bold yellow 'A' at top-left
```

### SCR-GET

```
( row col -- cell )
```

Read a cell from the back buffer.

### SCR-FRONT@

```
( row col -- cell )
```

Read a cell from the front buffer (the last-flushed state).

---

## Fill / Clear

### SCR-FILL

```
( cell -- )
```

Fill the entire back buffer with the given cell value.  A wide cell fills
as a space in its style.

### SCR-CLEAR

```
( -- )
```

Fill the back buffer with `CELL-BLANK` (space, white on black, no
attributes).

```forth
SCR-CLEAR   \ erase all pending content
```

---

## Cursor Management

### SCR-CURSOR-AT

```
( row col -- )
```

Set the logical cursor position (0-based).  The physical terminal
cursor will be moved here after the next `SCR-FLUSH` (if visible).

### SCR-CURSOR-ON / SCR-CURSOR-OFF

```
( -- )
```

Show or hide the cursor on the next flush.  The cursor is hidden
during flush regardless; `SCR-CURSOR-ON` restores it at the end.

---

## Flush Algorithm

### SCR-FLUSH

```
( -- )
```

Transactional screen update. Ordinary writes accumulate a conservative
per-screen set of touched rows. DELTA admission compares only those rows,
records an exact immutable damage map, and counts exact changed spans. A forced
SNAPSHOT deliberately marks every row without consulting the candidate map.
The selected backend then receives the admitted transaction:

```
BEGIN   ( mode cols rows span-count cell-count cluster-words span-peak
          context -- status )
SPAN    ( cells count row col cluster-words context -- status )
CURSOR  ( row col visible context -- status )
COMMIT  ( context -- status )
ABORT   ( context -- )
```

`cluster-words` counts the CELL-1 cluster-tail words of the transaction or
span, and `span-peak` is the largest span body in 32-bit words, two per cell
plus its cluster words.  A BEGIN may return `SCB-S-TOO-LARGE` when the
transaction fits only without its tails; the flush then retries it degraded,
with zero cluster words, and a backend sends each cluster cell of such a span
as U+FFFD.  `SCR-FLUSH?` never returns that status.

For the default ANSI backend, each changed cell is emitted as follows:

1. **Position cursor** via `ANSI-AT` (skipped if already at the
   correct position — consecutive dirty cells need no extra
   positioning).
2. **Emit attribute/color changes** — only the diff from the last
   emitted cell.  If attributes change, `ANSI-RESET` is emitted
   first, then individual SGR codes for each set flag.  Foreground
   and background colors are emitted via `ANSI-FG256` / `ANSI-BG256`
   only when they differ from the last emitted state.
3. **Emit the cell's whole character**: its scalars as UTF-8 (`EMIT` for
   ASCII).  A continuation cell emits nothing, since the terminal draws the
   wide character across both cells.  Where the terminal would join this
   character to the one before it, the backend repositions the cursor first;
   any escape sequence ends the terminal's open character.

After an accepted commit, exact damaged rows are copied from `back[]` to
`front[]`, and only then is the touched-row union cleared. Backend refusal
retains both the exact retry plan and its candidates. The cursor is hidden
during an ANSI update
(`ANSI-CURSOR-OFF`) and optionally restored at the logical position
with `ANSI-CURSOR-ON`. Finally, `TERM-FLUSH` commits the BIOS UART ring's
partial batch so the host observes the complete frame immediately.

```forth
\ Typical frame loop:
SCR-CLEAR
\ ... draw widgets into back buffer ...
SCR-FLUSH
```

---

## Force Redraw

### SCR-FORCE

```
( -- )
```

Force a full snapshot on the next accepted flush without corrupting the
committed front plane.

```forth
SCR-FORCE SCR-FLUSH   \ full repaint
```

---

## Resize

### SCR-RESIZE

```
( w h -- )
```

Resize the current screen. Allocates new planes and row maps, copies the
overlapping region from the old back plane to the replacement back plane, and
atomically replaces the descriptor fields. The new touched map starts with
every row marked and `SCR-FORCE` makes the next transaction a full snapshot.

All replacement allocations are acquired before the descriptor changes. Any
partial failure releases only the new allocation set; after a successful copy,
both superseded planes and both superseded row maps are returned to the
platform allocator.

```forth
132 50 SCR-RESIZE   \ switch to 132-column mode
```

---

## Memory

Each cell is 8 bytes. Four CELL buffers per screen, plus one provenance byte
per cell, three bytes per row, and the descriptor:

| Size | Cells | Buffer bytes | CELL planes (×4) |
|------|-------|-------------|------------|
| 80×24 | 1,920 | 15,360 | **61,440** (60 KiB) |
| 132×50 | 6,600 | 52,800 | **211,200** (~206 KiB) |
| 200×60 | 12,000 | 96,000 | **384,000** (375 KiB) |

All screen storage is acquired through the platform `ALLOCATE` path and
returned by `FREE`. With XMEM enabled, the descriptor and buffers use its
reclaiming free list; otherwise they use the Bank 0 heap.

---

## Quick Reference

| Word | Stack | Short |
|------|-------|-------|
| `SCR-NEW` | `( w h -- scr )` | Create screen |
| `SCR-FREE` | `( scr -- )` | Destroy screen |
| `SCR-USE` | `( scr -- )` | Set current |
| `SCR-W` | `( -- w )` | Get width |
| `SCR-H` | `( -- h )` | Get height |
| `SCR-STORAGE-DISJOINT?` | `( a u -- flag )` | Prove caller storage cannot mutate the active screen graph |
| `SCR-SET` | `( cell row col -- )` | Write back buf |
| `SCR-CLUSTER` | `( a n -- cp )` | Intern a cluster |
| `SCR-CLUSTER@` | `( cell -- a n )` | Read a cluster cell |
| `SCR-GET` | `( row col -- cell )` | Read back buf |
| `SCR-FRONT@` | `( row col -- cell )` | Read front buf |
| `SCR-FILL` | `( cell -- )` | Fill back buf |
| `SCR-CLEAR` | `( -- )` | Clear to blank |
| `SCR-FLUSH` | `( -- )` | Publish through selected backend |
| `SCR-FORCE` | `( -- )` | Mark all dirty |
| `SCR-RESIZE` | `( w h -- )` | Reallocate |
| `SCR-CURSOR-AT` | `( row col -- )` | Set cursor pos |
| `SCR-CURSOR-ON` | `( -- )` | Show cursor |
| `SCR-CURSOR-OFF` | `( -- )` | Hide cursor |
