# Akashic transactional cell-backend contract

Status: normative for the APT-1 CELL-1 Akashic implementation.

This document defines the boundary between Akashic's double-buffered screen
and an output backend. It does not define APT-1 byte encoding; that is
specified by the mirrored `APT-1-WIRE.md`.

The additive retained rich-terminal output path is specified separately by
`AKASHIC-RICH-TERMINAL.md`. It projects the same UIDL state, never replaces
the cell screen or ANSI fallback, and shares one atomic publisher with CELL
once retained discovery succeeds.

## 1. Goal

Application and widget painting continues to target the existing Akashic back
buffer. `SCR-FLUSH` projects the difference through a bound backend. ANSI and
APT-1 are backend implementations of the same transactional interface.

ANSI is the constructed default and is a complete supported mode. The generic
backend seam does not require APT-1, and loading Akashic does not imply that an
enhanced terminal exists.

Serialization does not create a second UI model. The screen front buffer
records only state accepted by a backend commit.

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

If `commit` returns `OK`, the whole transaction is displayed atomically and
front advances. If it returns another status, the backend has discarded all
staged mutations, front remains unchanged, and dirty remains set. `abort` is
not called after `commit`, because commit terminates the transaction for every
status.

Repeated flush after refusal derives a fresh diff from the latest back buffer.
Application paint callbacks need not run again. The shell therefore tracks
application-paint dirty state separately from pending screen output.

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

The reusable APT session/framing implementation lives in MegaPad's optional,
boot-loaded root-level `rich-terminal.f` userland module, not in KDOS
or Akashic. Akashic's APT backend is a small adapter over that already-loaded
public ABI. No Akashic source may `REQUIRE` the module or copy it into the
Akashic tree. The adapter is available only when the product profile loaded the
module explicitly and requested rich-terminal negotiation; baseline profiles
remain unaffected.

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

### Rich-terminal publication

The descriptor and flush algorithm above remain the complete ANSI and CELL-only
contract. Before RETAINED-1 is enabled, the APT adapter uses the legacy CELL
transaction and initial snapshot forms exactly as described.

After RETAINED-1 discovery succeeds, the adapter must not independently emit a
legacy CELL transaction or replacement snapshot. Its `begin`, `span`, and
`cursor` calls instead stage the exact CELL enumeration in the one internal
rich-terminal output coordinator. The UIDL retained backend stages semantic
operations in that same coordinator. One `PRESENT_BEGIN`/`PRESENT_COMMIT` then
publishes a CELL-only, retained-only, or mixed change under the shared
transaction ID and revision. Accepted resize recovery uses `CELL_REPLACE` in
that envelope.

The APT screen adapter exposes this coordinator through one optional borrowed
publisher descriptor. The descriptor carries the exact PT session, callback
context, normalized CELL transaction callbacks, an ordinary scheduler step,
and a distinct close-settlement callback. The baseline adapter does not depend
on a concrete rich engine. At each `begin` it selects the publisher only when
retained discovery is currently available; otherwise it selects the legacy
CELL path. That decision is latched through span, cursor, commit, or abort, so
discovery and reset transitions cannot split one transaction across paths.

`PT-SERVICE` remains owned by the APT screen adapter. Ordinary service calls it
before the publisher scheduler, which may reconcile a completion or admit one
queued lifecycle request. Synchronized close uses a separate operation: it
calls `PT-CLOSE` first to latch MegaPad's finite settlement/publication
deadline and writer barrier, then services PT's pending path and asks the
publisher to settle only an already-admitted result. Later service calls may
reconcile that result, complete a crossed reset, or publish CLOSE, but cannot
restart the bound. Settlement must not submit queued lifecycle work.
Captured or sealed local candidates and an open uncommitted CELL transaction
carry no emitted-result authority and do not block close; the synchronized
session retirement discards them. Once PT is `CLOSING`, only `PT-SERVICE` may
run until ANSI ownership is restored. At that proven boundary, one final
settlement call quarantines any remaining engine-local candidate or lifecycle
state before the adapter restores ANSI.
Every ANSI observation follows the same retirement path, including a
peer-initiated close reached through ordinary service: settlement is invoked
once as a best-effort local quarantine, the latched publisher route is cleared,
and only then is the ANSI screen backend restored. PT has already released wire
ownership at this point, so that callback cannot emit protocol work.

The screen front buffer and retained terminal state advance together only
after the complete unified commit has been accepted locally. Backpressure or a
semantic failure leaves both prior states authoritative, leaves screen dirty,
and discards all staging. The one post-commit `TX_RESULT` gate blocks both CELL
and retained publication. Clearing the screen force-snapshot latch cannot clear
retained replay, and clearing retained dirtiness cannot advance the screen
front buffer.

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

The `desktop-apt1` profile is one production composition boundary. MegaPad
boot-loads its canonical optional root `rich-terminal.f` as a separate
system module before Akashic's `desk-apt1.f` owner and linked Desktop closure
are loaded. Akashic consumes only the public PT ABI; it neither source-loads
nor vendors the module. The baseline `desktop` profile does neither and remains
ANSI-only.

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

Application dirty state means the back buffer needs repainting. Output pending
means front differs from back or a previous flush was refused.

The shell clears application dirty only after completing application paint.
It keeps output pending until `SCR-FLUSH` returns `SCB-S-OK`. A retry
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
