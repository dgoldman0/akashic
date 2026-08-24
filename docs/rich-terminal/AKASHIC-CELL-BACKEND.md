# Akashic transactional cell-backend contract

Status: normative for the APT-1 CELL-1 Akashic implementation.

This document defines the boundary between Akashic's double-buffered screen
and a presentation backend. It does not define APT-1 byte encoding; that is
specified by the mirrored `APT-1-WIRE.md`.

## 1. Goal

Application and widget painting continues to target the existing Akashic back
buffer. `SCR-FLUSH` projects the difference through a bound backend. ANSI and
APT-1 are backend implementations of the same transactional interface.

ANSI is the constructed default and is a complete supported mode. The generic
backend seam does not require APT-1, and loading Akashic does not imply that an
enhanced terminal exists.

Serialization is not presentation. The screen front buffer records only state
accepted by a backend commit.

## 2. Status values

The interface uses these stable values:

| Value | Name | Meaning |
| ---: | --- | --- |
| 0 | `SCB-S-OK` | The operation was accepted. |
| 1 | `SCB-S-WOULD-BLOCK` | No state changed; retry after capacity or transient owner contention changes. |
| 2 | `SCB-S-SESSION-LOST` | The binding is stale or the enhanced session ended. |
| 3 | `SCB-S-INVALID` | Caller arguments or backend state violate the contract. |

Status returns are ordinary values. Capacity and session loss must not throw
through application paint. Programmer-invalid descriptor construction may
abort at bind time, before the backend becomes current.

Flush modes are `SCB-M-DELTA = 0` and `SCB-M-SNAPSHOT = 1`.

## 3. Backend descriptor

A backend descriptor contains a context pointer and five execution tokens.
Every token receives that context as its final argument:

```
begin   ( mode cols rows span-count cell-count context -- status )
span    ( cells count row col context -- status )
cursor  ( row col visible context -- status )
commit  ( context -- status )
abort   ( context -- )
```

`cells` addresses `count` consecutive native 64-bit cells. The backend must
read them before returning; it cannot retain the caller's pointer. The APT-1
backend encodes named fields and must never copy the native cell word as its
wire representation.

Only one backend transaction may be open. Calls are not reentrant.

## 4. Flush algorithm

`SCR-FLUSH` performs three bounded passes without allocating a change list:

1. Choose delta or snapshot mode. In delta mode, compare front and back rows
   and count maximal contiguous changed spans and their cells. In snapshot
   mode, count exactly one complete span per row and every cell. Call `begin`
   with the mode, exact counts, and current geometry.
2. If accepted, rescan and call `span` once per maximal changed span, followed
   by exactly one `cursor` and `commit`.
3. If commit succeeds, rescan changed rows and copy their complete back rows
   to front; snapshot mode copies every row. Then clear the screen dirty and
   force-snapshot flags.

Whole-row `COMPARE` remains the unchanged-row fast path in every pass. Counts
and address arithmetic use checked screen dimensions; there is no fixed span
array and no arbitrary changed-cell cap.

`SCR-FORCE` sets an explicit force-snapshot flag. Snapshot enumeration never
depends on poisoning front cells with a sentinel, because a native packed cell
could otherwise equal the sentinel. Binding the APT adapter after open, an
accepted resize, or a soft reset calls `SCR-FORCE` before the next flush.

The backend uses `span-count` and `cell-count` to reserve an upper bound for
the complete transaction before accepting `begin`. Therefore, after a
successful `begin`, valid matching `span` calls cannot return
`SCB-S-WOULD-BLOCK`.

For APT-1 this is exact: `176 + 52 * span-count + 8 * cell-count` complete
wire bytes from begin through commit. Negotiation guarantees that one complete
maximum-width row span fits a frame payload, so the adapter never splits a
screen span or changes the declared count.

## 5. Acceptance and failure

If `begin` returns `WOULD-BLOCK`, `SESSION-LOST`, or `INVALID`, no other token
is called, front remains unchanged, and the dirty flag remains set.

If `span` or `cursor` returns anything other than `OK`, `SCR-FLUSH` calls
`abort` exactly once. Front remains unchanged and dirty remains set.

If `commit` returns `OK`, the whole transaction is presented atomically and
front advances. If it returns another status, the backend has discarded all
staged mutations, front remains unchanged, and dirty remains set. `abort` is
not called after `commit`, because commit terminates the transaction for every
status.

Repeated flush after refusal derives a fresh diff from the latest back buffer.
Application paint callbacks need not run again. The shell therefore tracks
application-paint dirty state separately from pending screen presentation.

## 6. ANSI backend

The ANSI backend always admits a valid `begin` and commits synchronously. It
must preserve the current byte behavior:

* hide the physical cursor at begin;
* reset cursor/style tracking;
* emit changed cells in row-major order using width-one projection;
* restore the logical cursor when visible;
* emit final SGR reset; and
* call `TERM-FLUSH` at commit.

It does not buffer a whole screen transaction. Its `abort` restores a safe
terminal style/cursor state and flushes, though ordinary valid calls do not
exercise that path.

## 7. APT-1 backend

The reusable APT session/framing implementation lives in MegaPad's optional
root-level `presentation-terminal.f` userland module, not in KDOS. Akashic's
APT backend is a small adapter over that loaded service. It is available only
when the module was explicitly loaded and a caller requested presentation
negotiation.

The enhanced backend is bound only after successful negotiation. `begin`
checks the current session epoch and reserves sufficient transport and remote
transaction budget for the declared counts. A refusal has no wire effect.
Binding and non-ANSI service require `PT-OWNS?` for the adapter's exact
borrowed session. An ANSI-state adapter may rebind the ANSI backend only when
`PT-STREAM-OWNED?` also proves that no other session owns the global stream.

Each `span` applies `CW-CELL-CP` and serializes the CELL-1 codepoint, foreground
index, background index, and named wire attributes. Wide and continuation
native flags are not transmitted in the width-one CELL-1 profile.

`commit` queues the complete final commit frame within the prior reservation.
The Akashic front buffer may advance after local transport acceptance; it does
not wait for rendering or a remote paint acknowledgement.

The module permits only one locally committed transaction awaiting
`TX_RESULT`. Until it succeeds, the next backend `begin` returns
`SCB-S-WOULD-BLOCK`. A failed result maps to `SCB-S-SESSION-LOST` before any
later application event; no optimistic pipeline or rollback is permitted.

Negotiation refusal, a pre-`OPEN` timeout, or an ANSI-only physical terminal
keeps or restores the ANSI backend and is not an application error. Once
`OPEN` has crossed the binary switch boundary, session loss retains the APT
backend and input owner, suppresses application callbacks and raw terminal
output, and requires either an acknowledged framed close or an external hard
attachment reset and drain before ANSI may be rebound. A competing live APT
session is a transient `WOULD-BLOCK`, not proof that this idle adapter lost a
session. Because app shutdown and component state finalizers are arbitrary
callbacks, unsafe teardown does not invoke them: it retains the exact live
top-level component instance until the same whole-environment reset/reload
boundary. Raw-freeing that state without its finalizer is not permitted.

### Production opt-in composition

The `desktop-apt1` profile is the production composition boundary. It deploys
MegaPad's canonical root `presentation-terminal.f` as a separate system module,
then source-loads Akashic's `desk-apt1.f` owner with the linked Desktop closure.
The baseline `desktop` profile does neither and remains ANSI-only.

The profile owns one immutable host policy with a declared 400 by 200 maximum
geometry, geometry-derived payload/transaction/credit/publication bytes, and
explicit queue-event, input-byte, history, and service bounds. Both the smoke
runner and shared-session launcher consume that same policy; selecting the
profile may not silently fall back to an ANSI-only host configuration. The
guest's independent 8192-byte RX and TX streaming buffers admit the control
reserve and a complete maximum-width CELL span without buffering a whole
snapshot.

If Desk exits or throws after the binary switch but synchronized release is
not proven, the profile emits no diagnostic bytes. It remains in a silent
`IDLE` quarantine until the host performs the required attachment reset.

## 8. Cursor and geometry

Coordinates are zero-based. `visible` is zero or true. When visible, row and
column must be inside the current geometry; a hidden cursor's stored position
may be clamped by screen resize before projection.

The geometry passed to `begin` is the geometry of all spans in that
transaction. A resize cannot interleave with an open transaction.

## 9. Shell retry contract

Application dirty state means the back buffer needs repainting. Presentation
pending means front differs from back or a previous flush was refused.

The shell clears application dirty only after completing application paint.
It keeps presentation pending until `SCR-FLUSH` returns `SCB-S-OK`. A retry
calls `SCR-FLUSH` directly and does not rerun application paint unless the
application became dirty again.

## 10. Initial conformance cases

The lightweight suite must prove:

1. ANSI output remains byte-for-byte compatible for a representative styled
   screen and cursor;
2. a 2-by-2 changed screen emits maximal row spans and one commit;
3. an unchanged second flush emits no spans;
4. a refused begin leaves front and dirty unchanged;
5. retry after capacity succeeds without repaint;
6. a span failure calls abort and leaves front unchanged; and
7. a successful commit advances every changed row and clears dirty.
