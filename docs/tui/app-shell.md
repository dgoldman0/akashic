# akashic/tui/app-shell.f — TUI Application Shell Runtime

**Layer:** 7 (above term-init.f)  
**Lines:** ~1,380
**Prefix:** `ASHELL-` (public), `_ASHELL-` (internal)  
**Provider:** `akashic-tui-app-shell`  
**Dependencies:** `app-desc.f`, [`cogs/term-init.f`](cogs/term-init.md), `keys.f`, `screen.f`, `region.f`, `draw.f`,
`focus.f`, `uidl-tui.f`, `utils/term.f`, `utils/fs/vfs.f`

## Overview

Headless runtime that owns the terminal, event loop, paint cycle, and
UIDL integration.  Apps provide callbacks via an **APP-DESC** descriptor;
the shell has no UI of its own.

Terminal management (alternate screen, screen buffer, cursor) comes
from [`cogs/term-init.f`](cogs/term-init.md) — the same cog that
`app.f` uses for standalone apps.  This means app-shell.f does **not**
depend on `app.f`; the standalone and applet paths are fully
independent.

`ASHELL-RUN` blocks until a normal `ASHELL-QUIT` is approved or a callback
throws. Teardown first calls `UTUI-QUIESCE` for the optional projection owned
by the active UIDL context, then runs the descriptor's bounded quiesce barrier.
Only after both succeed does it close the optional terminal owner and enter
arbitrary application shutdown. A barrier, terminal-close,
application-shutdown, or `UTUI-DETACH` failure preserves the complete active
shell state in quarantine and skips all later destructors.

Not reentrant.  One app at a time.

The shell consumes the abstract `utils/fs/vfs.f` interface for UIDL file
loading.  It does not choose or mount a storage driver.  MegaPad-64 product
images compose [`platform/mp64fs-vfs.f`](platform/mp64fs-vfs.md) before
loading applet modules; other hosts may supply a different active VFS.

> **Standalone vs Applet.**  Standalone TUI apps use [`app.f`](app.md)
> directly (they own the event loop via `APP-RUN`).  Applets are hosted
> here — one at a time via `ASHELL-RUN`, or composited by
> [`desk.f`](applets/desk/desk.md).  Both paths share terminal init from
> [`cogs/term-init.f`](cogs/term-init.md).

## APP-DESC — Application Descriptor

The 168-byte APP-DESC struct is defined in
[app-desc.f](app-desc.md) and pulled in via `REQUIRE app-desc.f`.

168 bytes (21 cells).  Allocate with `CREATE my-desc APP-DESC ALLOT`,
zero-fill with `APP-DESC-INIT`.  Unused callback fields must be 0
(the shell skips them).

| Offset | Field | Stack | Description |
|--------|-------|-------|-------------|
The descriptor begins with its ABI header and required `APP.COMP-DESC`.
Lifecycle callbacks receive the live component instance.
`APP.REQUEST-CLOSE-XT` is `( reason instance -- decision )`, and the final
`APP.QUIESCE-XT` field is `( instance -- ior )`; see
[app-desc.md](app-desc.md) for the complete offset table.

Each field accessor takes `( desc -- addr )` and returns the address of
that field within the descriptor, suitable for `@` or `!`.

## API Reference

### Lifecycle

| Word | Stack | Description |
|------|-------|-------------|
| `ASHELL-RUN` | `( desc -- )` | Owner-core lifecycle driver. Blocks until an approved quit or throw, then either completes ordered teardown or preserves the complete live shell in quarantine at the first dependent-gate failure. |
| `ASHELL-QUIT` | `( -- )` | Lock-free, idempotent normal-close signal. Safe from callbacks, including init. |
| `ASHELL-QUIT-PENDING?` | `( -- flag )` | True if a sub-app has called `ASHELL-QUIT` but the host hasn't processed it yet. |
| `ASHELL-CANCEL-QUIT` | `( -- )` | Owner-lifecycle re-arm signal used by Desk and close negotiation. |
| `ASHELL-REQUEST-CLOSE` | `( reason -- decision )` | Query the live descriptor; THROW/invalid decisions fail closed. |

### Context Switch & Child Painting

| Word | Stack | Description |
|------|-------|-------------|
| `ASHELL-ACTIVE-CTX` | `( -- uctx )` | Return the active child UIDL context identity, or 0. |
| `ASHELL-CTX-FORGET` | `( uctx -- )` | Clear a matching active identity only after it is no longer live. A matching live UCTX throws `ASHELL-CTX-E-AUTHORITY`; zero or nonmatching input is a no-op. Does not save, restore, or free it. |
| `ASHELL-CTX-SWITCH` | `( uctx -- )` | Save and disown the current UIDL context (if any), then restore `uctx` as the unique live owner. Pass 0 to deactivate without loading a new context. Re-selecting the shell-tracked identity after its live ownership diverged throws `ASHELL-CTX-E-AUTHORITY`; UCTX rejects other ownership violations. |
| `ASHELL-CTX-SAVE` | `( uctx -- )` | Force-save the current globals, pools, and mounted-canonical relation aliases into the exact active/live `uctx`; an ownership mismatch throws. No switch happens. |
| `ASHELL-PAINT-CHILD` | `( uctx rgn has-uidl desc instance -- )` | Per-child paint primitive. Context-switches to `uctx`, selects the region, activates `instance`, and runs ordinary `UTUI-PAINT` plus `APP.PAINT-XT`. When an optional projection is attached, a UIDL child runs that complete draw under generic mounted-canonical observation and publishes only after observation succeeds. |
| `ASHELL-REPAINT-CHILD` | `( uctx rgn has-uidl desc instance -- )` | As `ASHELL-PAINT-CHILD`, but first marks the whole document with `UTUI-INVALIDATE`, for a child something else drew over since its last paint, such as an applet-host overlay. |

`ASHELL-PAINT-CHILD` is the supported observation scope for Desk children. When
installed, the observer sees the same ordinary widget calls made by Pad,
Daybook, or any other child while that child's UCTX is live; applets do not
register a provider and receive no renderer or scene API. The generic
mounted-canonical relation ledger records canonical `TXTA`, `TGRID`, and `TAB`
instances, and `UCSN-CAPTURE` revalidates and enumerates those relations into
pointer-free `TEXT_AREA`, `TEXT_GRID`, and `TABSET` snapshots. The selected hybrid
aggregate/publication path consumes that collection bank through the shared
AREA|GRID|TABSET lowering path; app-shell remains unaware of the selected
renderer.

The standalone top-level `_ASHELL-PAINT` path still publishes its direct UIDL
projection, but it is not yet wrapped in mounted-canonical draw observation.
Standalone top-level mounted discovery is therefore deferred; that does not
limit the supported Desk child UCTX scope above.

### State Queries

| Word | Stack | Description |
|------|-------|-------------|
| `ASHELL-DESC` | `( -- desc )` | Current app descriptor (0 if not running). |
| `ASHELL-REGION` | `( -- rgn )` | Root region (full screen). |
| `ASHELL-UIDL?` | `( -- flag )` | True if a UIDL document is loaded. |

### Paint & Tick

| Word | Stack | Description |
|------|-------|-------------|
| `ASHELL-DIRTY!` | `( -- )` | Request repaint next frame. |
| `ASHELL-TICK-MS!` | `( ms -- )` | Set tick interval (default 50 ms). |

### UIDL File Loading

| Word | Stack | Description |
|------|-------|-------------|
| `ASHELL-LOAD-UIDL` | `( path-a path-u rgn -- buf \| 0 )` | Open a file through the active VFS, read it through a 512-byte DMA-safe bounce buffer, and parse it as UIDL into `rgn`. Returns retained XMEM or 0. |
| `ASHELL-FREE-UIDL-BUF` | `( buf -- )` | Release retained storage returned by `ASHELL-LOAD-UIDL`; 0 is a no-op. Callers do not depend on the shell's private allocation size. |

### Notices

| Word | Stack | Description |
|------|-------|-------------|
| `ASHELL-NOTICE` | `( addr u ms severity -- )` | Show a notice for *ms* milliseconds from when the first output that shows it has gone out, with its meaning: `ASHELL-SEVERITY-NEUTRAL`, `-INFO`, `-SUCCESS`, `-WARNING` or `-ERROR`, 0 to 4, a status field's severities. Another value is neutral. The shell keeps its own copy of the text. |
| `ASHELL-TOAST` | `( addr u ms -- )` | A neutral notice. |
| `ASHELL-TOAST-WARNING` | `( addr u ms -- )` | A notice that warns. |
| `ASHELL-TOAST-ERROR` | `( addr u ms -- )` | A notice that something failed. |
| `ASHELL-TOAST-VISIBLE?` | `( -- flag )` | True while the notice raised last has not ended. |
| `ASHELL-NOTICE-SHOWN?` | `( -- flag )` | Whether the paint shows a notice. |
| `ASHELL-NOTICE-ROOT` | `( -- row col height width )` | The cells the paint's notice lies in; all zero when it shows none. |
| `ASHELL-NOTICE-CAPTURE` | `( dst cap -- bytes status )` | The notice the paint shows, as a [UDLG model](dialog-model.md) at DST; with DST 0 and CAP 0 only measure it. |

### Deferred Actions

| Word | Stack | Description |
|------|-------|-------------|
| `ASHELL-POST` | `( xt -- )` | Enqueue xt for execution before next paint. FIFO, max 16 entries. Drops silently if full. |

### Descriptor Helpers

| Word | Stack | Description |
|------|-------|-------------|
| `APP-DESC` | `( -- 168 )` | Descriptor size constant. |
| `APP-DESC-INIT` | `( desc -- )` | Zero-fill a descriptor. |

## Lifecycle Sequence

### ASHELL-RUN

```
ASHELL-RUN
  ├── _ASHELL-SETUP (via CATCH)
  │     1. Store descriptor
  │     2. APP-INIT (terminal + screen buffer, from term-init.f)
  │     3. Set terminal title (if provided)
  │     4. Create root region (full screen)
  │     5. UTUI-LOAD UIDL document (if provided)
  │     6. Set RUNNING flag, init tick timer
  │     7. Call APP.INIT-XT (app may ASHELL-QUIT here)
  │     8. KEY-TIMEOUT! for ESC sequences
  │     9. Mark dirty, initial paint + flush
  │
  ├── _ASHELL-LOOP-UNTIL-CLOSED (via CATCH)
  │     BEGIN RUNNING WHILE
  │       1. KEY-POLL → resize / dispatch
  │       2. Hardware resize poll
  │       3. Drain deferred actions
  │       4. UTUI-SERVICE (with a UIDL document), then APP.SERVICE-XT, if set
  │       5. Timer tick check
  │       6. Paint if dirty
  │       7. IDLE-UNTIL next deadline, if the pass did nothing
  │       8. YIELD?
  │     REPEAT
  │     APP.REQUEST-CLOSE-XT(APP-CLOSE-R-QUIT)
  │       ALLOW  → teardown
  │       CANCEL → re-arm loop
  │       DEFER  → re-arm loop; app may issue quit when ready
  │
  └── _ASHELL-TEARDOWN (always runs)
        1. UTUI-QUIESCE, then APP.QUIESCE-XT
        2. Close the optional terminal owner and prove ANSI safety
        3. Claim and call APP.SHUTDOWN-XT
        4. UTUI-DETACH (if UIDL loaded)
        5. Free shell-loaded UIDL buffer
        6. RGN-FREE root region
        7. APP-SHUTDOWN (terminal restore, from term-init.f)
        8. CINST-FREE component instance
        9. Reset all shell ownership/state
```

UIDL projection quiesce, descriptor quiesce, terminal close, application
shutdown, and `UTUI-DETACH` are dependent gates. The projection barrier runs
even if setup loaded UIDL but did not reach application init. If any gate
refuses or throws, teardown records the exact first error,
marks the live instance quarantined, and returns immediately without clearing
the descriptor, instance, root region, UIDL ownership, active UCTX, terminal
owner, posted work, or screen state. A quarantined shell rejects another run,
terminal-owner replacement, or owner release until the required external
recovery boundary. No projection-provider soft reset or output-adapter reset
repairs that host lifecycle: no in-process shell retry, terminal-owner release,
or projection soft-reset operation clears the latch, and there is no public
clear API.
Recovery requires an externally confirmed attachment hard-reset/drain followed
by fresh module or image
initialization. The shell deliberately does not retry an arbitrary shutdown
callback after it has been claimed.

After those gates succeed, local host-owned releases remain best-effort and the
first cleanup error is reported after reset. If setup or the event loop threw,
that primary error still takes precedence. A distinct application-init-started
latch is set immediately before looking up `APP.INIT-XT`, so setup failure
before that boundary calls neither `APP.QUIESCE-XT` nor `APP.SHUTDOWN-XT`.

### Event Dispatch Order

For each key event:

0. **Shell cursor** — `_ASHELL-CUR-KEY?` intercepts Alt+Arrow (move),
   Alt+Del/End/PgDn (click).  The shell owns these before any app sees
   them.  Any non-Alt key hides the cursor.
1. **Dialog** — a dialog the app shows takes every event
   (`DLG-HOST-EVENT`) until a button is chosen; then it closes and calls
   the app back.
2. **App handler** — `APP.EVENT-XT` gets first crack.  If it returns
   true, the event is consumed and the screen is marked dirty.
3. **UIDL dispatch** — `UTUI-DISPATCH-KEY` routes to shortcuts and
   focused elements.  If it returns true, the screen is marked dirty.
4. **Drop** — unhandled events are discarded.

For mouse events (synthesised by cursor clicks):

0. **Dialog** — as for keys; a press on one of its buttons chooses it.
1. **App handler** — `APP.EVENT-XT` gets first crack (e.g.
   `DESK-EVENT-CB` routes to the tile under the cursor).
2. **UIDL dispatch** — `UTUI-DISPATCH-MOUSE` hit-tests the element
   tree, focuses, and fires `do=`.  Only runs if the app didn't consume.

An application handler takes only the pointer events meant for overlays it
paints itself, such as an active prompt, and returns the rest unconsumed.
Taking a press meant for a UIDL element would skip UIDL's hit-test and
focus.  Desk's applet host routes hosted children in the same order.

### Paint Order

0. `_ASHELL-CUR-RESTORE` — restore cell saved under cursor last frame
1. `RGN-ROOT` — reset region to full screen
2. `UTUI-PAINT` — UIDL elements (if loaded)
3. `APP.PAINT-XT` — app's custom widget drawing (on top of UIDL)
3a. `DLG-HOST-PAINT` — a dialog the app shows, over everything it paints
4. The notice — `_ASHELL-DRAW-TOAST` (if the paint shows one)
5. Cursor overlay — `_ASHELL-DRAW-CURSOR` (save cell + draw glyph)
6. `UTUI-DRAW-COMPLETE` — publish the direct UIDL projection after the complete draw (if UIDL is loaded)
7. `SCR-DRAW-COMPLETE`, then `RGN-ROOT` — finish the CELL draw and reset the region
8. `SCR-FLUSH` — diff and emit to terminal

### Resize Handling

Two resize detection paths:

- **Structured resize events** from `KEY-POLL` — the event carries
  the new width and height.
- **Hardware poll** via `TERM-RESIZED?` — catches SIGWINCH-style
  resizes that don't arrive as key events.

Both call `_ASHELL-ON-RESIZE`, which resizes the screen buffer, updates the
root region bounds in place, relayouts UIDL (if loaded), and marks dirty. The
stable descriptor identity remains valid for UIDL and optional output bindings.

### Automatic Dirty Propagation

Apps following the browser model never call `ASHELL-DIRTY!` directly.
Instead, the framework detects changes automatically:

- **`_UTUI-NEEDS-PAINT` flag** — set by the `UIDL-DIRTY!` hook
  (in `uidl.f`) whenever any element is dirtied.  Also set by
  `UTUI-ADD-ELEM`, `UTUI-REMOVE-ELEM`, `UTUI-SET-ATTR`, and
  `UTUI-WIDGET-SET`.
- **After TICK-XT** — `_ASHELL-CHECK-TICK` checks
  `_UTUI-NEEDS-PAINT` and converts it to `ASHELL-DIRTY!`.
- **At paint start** — `_ASHELL-PAINT` also checks the flag, so
  changes made outside the tick cycle are still caught.

This means: modify the DOM or widget state, and the framework repaints.
No manual dirty signalling needed.

## Notices

`ASHELL-NOTICE` shows a short message for a while, with its meaning.  The
app passes the text, a duration in milliseconds and a severity; the shell
handles drawing and timing.  `ASHELL-TOAST` raises a neutral notice, and
an application marks a failure or a warning where it raises it, with
`ASHELL-TOAST-ERROR` or `ASHELL-TOAST-WARNING`.

```forth
S" Saved" 2000 ASHELL-TOAST                 \ neutral, for 2 seconds
S" Could not save" 3000 ASHELL-TOAST-ERROR  \ a failure
```

The shell copies the text into a buffer it owns, which grows when a longer
one is raised, so the caller may reuse its own.  Without memory for the
copy the notice is not shown.  A later notice replaces an earlier one.  The
first paint after a notice ends gives its memory back, so a notice holds
memory only while it lasts.

A notice's time counts from when the first output that shows it has gone
out, not from when it was raised or painted.  Until then it has not begun
to end and sets no deadline of its own; raising it asks for the paint that
shows it.  The paint's flush succeeds once that output has gone out: at
once for plain cells, and for a terminal that shows a frame only when all
of it has arrived, when the frame carrying the notice is shown, which on a
busy screen can come more than a second after the paint.  So a late paint
or a slow frame still shows the notice for its whole time instead of
letting it end unseen.

Each paint decides once, as it begins, which notice it shows, and lays it
out for the screen's width: a bar on the bottom row, centred, four cells
wider than its text, which starts two cells in.  Text wider than the
screen allows is cut between characters and ends in an ellipsis.  The bar
takes its severity's colours, grey when neutral, then blue, green, amber
and red from info to error, and the text is drawn as untrusted text
(`DRW-TEXT-UNTRUSTED`).  The paint's text is a second owned copy, so a
notice raised while a paint runs shows from the next paint and never
changes what this one draws or publishes.  A screen too narrow for the
padding and a cell of text shows none.  The notice is drawn after
everything else but the shell cursor.  When it ends, `_ASHELL-CHECK-TICK`
has its cells repainted.

A press or a wheel turn on the notice the screen shows lands on the
notice, which takes none, as it does where a renderer shows the notice in a
region of its own.  A gesture begun elsewhere goes on: drags, releases and
the positions a renderer names still reach their targets.

`ASHELL-NOTICE-CAPTURE` gives a renderer the notice the paint shows as a
UDLG notice: flagged `NOTICE`, of the severity it was raised with, keyed by
its serial number, with a revision new at every layout, one row high and
as wide as its bar, its text the message's one line in a slot two cells
in.  The text's direction controls go out as inert stand-ins
(`BIDI-INERT`), as the paint ignored them.  A paint that shows no notice,
or whose text is not clean single-line text, gives `UDLG-S-UNSUPPORTED`,
and the notice stays painted.  Desk puts the notice in its shell model
([shell-model.md](shell-model.md)).

## Shell Cursor

The shell provides a keyboard-driven pointer for mouse-less
environments.  The cursor is a single-cell glyph (⊹ U+22B9)
that moves with **Alt+Arrows** and synthesises click events with
**Alt+Del** (left), **Alt+End** (middle), **Alt+PgDn** (right).

The cursor is only visible while Alt-modified keys are being pressed.
Any non-Alt key event hides it immediately.  This makes the cursor a
transient overlay that never interferes with normal editing.

### Key Bindings

| Key | Action |
|-----|--------|
| Alt+↑/↓/←/→ | Move cursor one cell |
| Alt+Del | Left click at cursor position |
| Alt+End | Middle click at cursor position |
| Alt+PgDn | Right click at cursor position |

### Click Synthesis

`ASHELL-CUR-CLICK` builds a synthetic mouse event in the shell's
event buffer (`_ASHELL-EV`) and routes it through
`_ASHELL-DISPATCH-MOUSE`.  The event format matches real mouse
input:

| Offset | Field | Value |
|--------|-------|-------|
| +0 | type | `KEY-T-MOUSE` |
| +8 | code | button (0=left, 1=middle, 2=right) |
| +16 | mods | `row << 16 \| col` |

The dispatch chain is: app event handler first (so desk can do
tile routing), then UIDL `UTUI-DISPATCH-MOUSE` (hit-test → focus →
fire `do=`).

### Non-Destructive Overlay

The cursor does not rely on the UIDL dirty system to repaint
underneath.  `UTUI-PAINT` only redraws elements whose own dirty flag
is set, so if the cursor moved but the underlying element didn't
change, the old glyph would persist as a ghost.

Instead the cursor saves and restores the back-buffer cell:

1. **Draw** — `_ASHELL-DRAW-CURSOR` reads the cell at `(row, col)`
   via `SCR-GET`, stashes it in `_ASHELL-CUR-SAVED`, then overwrites
   the cell with the ⊹ glyph.
2. **Restore** — at the *start* of the next `_ASHELL-PAINT`, before
   `UTUI-PAINT` or any app painting, `_ASHELL-CUR-RESTORE` writes
   the saved cell back via `SCR-SET`.
3. If `UTUI-PAINT` or the app then repaints that cell (because the
   element is dirty), the fresh content wins.  If not, the restored
   cell is already correct.

This makes the cursor a zero-waste overlay — it never leaves artefacts.

### Mouse Event Helpers

| Word | Stack | Purpose |
|------|-------|---------|
| `ASHELL-MOUSE?` | `( ev -- flag )` | True if event type = `KEY-T-MOUSE` |
| `ASHELL-MOUSE-ROW` | `( ev -- row )` | Extract row from mods field |
| `ASHELL-MOUSE-COL` | `( ev -- col )` | Extract col from mods field |
| `ASHELL-MOUSE-BTN` | `( ev -- btn )` | Extract button from code field |

### Internal Words

| Word | Stack | Purpose |
|------|-------|---------|
| `_ASHELL-CUR-CLAMP` | `( -- )` | Clamp cursor to screen bounds |
| `_ASHELL-CUR-INIT` | `( -- )` | Centre cursor, clear visibility |
| `_ASHELL-CUR-MOVE` | `( drow dcol -- )` | Move + clamp + show + dirty |
| `_ASHELL-CUR-KEY?` | `( ev -- flag )` | Handle cursor keys, return consumed? |
| `_ASHELL-CUR-RESTORE` | `( -- )` | Restore saved cell under cursor |
| `_ASHELL-DRAW-CURSOR` | `( -- )` | Save cell + draw ⊹ glyph |
| `_ASHELL-DISPATCH-MOUSE-IMPL` | `( ev -- )` | Mouse event routing (resolves DEFER) |

## Cooperative Multitasking

One `YIELD?` per loop iteration.  `YIELD?` checks the per-core KDOS
preemption flag (set by the timer ISR at the `TIME-SLICE` interval).
If set, context-switches to the scheduler.  Otherwise no-op.

The loop is non-blocking — `KEY-POLL` returns immediately, paint
only runs when dirty, tick only fires at interval.  Other KDOS tasks
get regular time slices.

### Idle Waiting

A pass that consumed no input, ran no posted action or tick, and had nothing
to paint or flush ends with `IDLE-UNTIL`, so an idle shell sleeps instead of
holding a core.  The deadline is the next tick (when the app has a tick
callback) or a visible toast's expiry, whichever comes first.  Input, a
network frame, or any requested interrupt ends the sleep at once, and
`IDLE-UNTIL` may return early, so the loop always re-checks its sources.

Every pass skipped this way would have found the same state and done
nothing, so timing does not change: ticks fire at the same moments and toasts
expire on time.  The loop does not sleep while posted actions are queued,
while paint is still due or a refused flush is pending, or while a live
terminal owner's `pending` callback reports work for its next service or poll
that no input interrupt announces.  An owner reports resizes as input.
Without one, a terminal resize sets a hardware flag that wakes nothing, so
the sleep is capped at one tick interval to keep polling it.

Code on another core that posts an action or requests a quit must also wake
the shell's core, for example with an IPI.

An app whose work can become due between ticks without any input sets
`APP.SERVICE-XT ( instance -- worked? )`. The shell calls it on every pass,
after the posted actions and before the tick, so it must be cheap when
nothing is due. A true result counts as work, so the loop takes another pass
instead of sleeping. Desk uses it for sandbox jobs on worker cores: a worker
that finishes wakes Desk's core with an IPI, and the next pass takes the job
back and completes its run instead of waiting for the tick. Desk also calls
`AHOST-SERVICE` from it, so its applets' pictures decode as a standalone
app's do.

Before the app's service, a shell with a UIDL document calls `UTUI-SERVICE`,
which decodes one bounded slice of each picture a `<media>` element is
showing, or reads the next part or makes more of a picture's file for a
document one shows. A slice counts as work, so the loop keeps taking passes until the
pictures are ready, and no app needs a service of its own for them.

### Events Given in Steps

A terminal owner may give one input event as several ordinary events, a
poll each: a scroll of three detents as three wheel steps, or a text as a
paste of its characters.  While the owner's `held` callback reports that it
holds the rest of such an event, a pass takes the next step and runs its
posted actions, service and tick as usual, but does not paint; the pass that
takes the last step paints.  So a paint shows the event whole.  A frame of
the steps between would be overtaken by the next step before a terminal
could show it.

### Deferred Action Queue

`ASHELL-POST` enqueues an xt into a 16-slot FIFO.  All queued
actions drain every loop iteration, after event dispatch and before
tick/paint.  Use for work that shouldn't run inside a callback
(e.g., modifying the UIDL tree, opening dialogs).

A posted action that calls `ASHELL-QUIT` stops the drain immediately.  Any
remaining actions stay queued until close negotiation either re-arms the loop
or teardown clears the queue.  A quit from the tick callback likewise returns
to negotiation before paint or `YIELD?`.  These stop checks make a pending
close a hard callback boundary.

## Concurrency Guards

When `GUARDED` is defined, bounded public operations use `WITH-GUARD`.
`ASHELL-RUN` and `ASHELL-REQUEST-CLOSE` are intentionally owner-core-only and
unwrapped.  KDOS exception state is task-aware, so lifecycle `CATCH` may safely
span `YIELD?`; a lifetime metadata guard still must not span the loop or close
callback because either may park for scheduling or user confirmation.
Cross-core code posts lifecycle work to the owner.  `ASHELL-QUIT` and
`ASHELL-CANCEL-QUIT` are lock-free aligned lifecycle signals, not general
cross-core synchronization primitives.

The bounded guarded operations are `ASHELL-DIRTY!`, `ASHELL-REGION`,
`ASHELL-TICK-MS!`, `ASHELL-POST`,
`ASHELL-UIDL?`, `ASHELL-DESC`, `ASHELL-INSTANCE`, `ASHELL-NOTICE`,
`ASHELL-TOAST`, `ASHELL-TOAST-WARNING`, `ASHELL-TOAST-ERROR`,
`ASHELL-TOAST-VISIBLE?`.  The capture words are paint-time helpers of the
UI owner core and are not guarded.

`ASHELL-REQUEST-CLOSE`, `ASHELL-QUIT-PENDING?`, `ASHELL-CANCEL-QUIT`,
`ASHELL-LOAD-UIDL`, `ASHELL-ACTIVE-CTX`, `ASHELL-CTX-FORGET`,
`ASHELL-CTX-SWITCH`, `ASHELL-CTX-SAVE`, `ASHELL-PAINT-CHILD`, and
`ASHELL-FREE-UIDL-BUF` are **not** guarded. Close negotiation, context
switch/save/forget, child painting, and buffer release are owner-core lifecycle
work. The remaining words are lightweight accessors or owner-loop helpers. In
particular, callers must not infer cross-core safety from the public
context/paint/release seams; the applet host uses them only while serialized on
its owner core.

The event loop and all descriptor callbacks remain serialized on the host
owner core.  Worker jobs publish results for that owner to apply; they do not
call applet lifecycle callbacks directly.

## Usage Examples

### Minimal App (No UIDL)

```forth
REQUIRE tui/app-shell.f

: my-event  ( ev instance -- flag )
    DROP @ 113 = IF     \ 'q' pressed
        ASHELL-QUIT -1
    ELSE 0 THEN ;

CREATE my-comp COMP-DESC ALLOT  my-comp COMP-DESC-INIT
CREATE my-desc APP-DESC ALLOT  my-desc APP-DESC-INIT
my-comp   my-desc APP.COMP-DESC !
' my-event  my-desc APP.EVENT-XT !

my-desc ASHELL-RUN
```

### UIDL App

```forth
REQUIRE tui/app-shell.f

CREATE my-uidl 256 ALLOT
S" <uidl><region><label text=Hello/></region></uidl>"
my-uidl SWAP MOVE

: my-init  ( instance -- )
    DROP
    S" lbl" UTUI-BY-ID  ( elem )
    \ ... wire up widgets ...
    ;

: my-event  ( ev instance -- flag )
    DROP @ 27 = IF ASHELL-QUIT -1 ELSE 0 THEN ;

CREATE my-comp COMP-DESC ALLOT  my-comp COMP-DESC-INIT
CREATE my-desc APP-DESC ALLOT  my-desc APP-DESC-INIT
my-comp   my-desc APP.COMP-DESC !
' my-init   my-desc APP.INIT-XT !
' my-event  my-desc APP.EVENT-XT !
my-uidl     my-desc APP.UIDL-A !
49          my-desc APP.UIDL-U !

my-desc ASHELL-RUN
```

### Quit From Init

```forth
: my-init  ( instance -- )
    DROP
    \ do setup, decide to bail
    ASHELL-QUIT ;
```

This works because the RUNNING flag is set *before* the init callback.

## Internal State

| Variable | Default | Purpose |
|----------|---------|---------|
| `_ASHELL-DESC` | 0 | Current descriptor |
| `_ASHELL-RGN` | 0 | Root region address |
| `_ASHELL-RUNNING` | 0 | Loop active flag |
| `_ASHELL-DIRTY` | 0 | Repaint needed flag |
| `_ASHELL-HAS-UIDL` | 0 | UIDL document loaded flag |
| `_ASHELL-TICK-MS` | 50 | Tick interval (ms) |
| `_ASHELL-LAST-TICK` | 0 | `MS@` of last tick |
| `_ASHELL-EV` | — | 24-byte key event buffer |
| `_ASHELL-POST-Q` | — | 16-slot deferred action FIFO |

| `_ASHELL-TOAST-MSG` | 0 0 | The notice's owned text, addr + len (2 cells) |
| `_ASHELL-TOAST-EXPIRY` | 0 | The notice's `MS@` deadline |
| `_ASHELL-TOAST-WAS-VIS` | 0 | Was-visible flag for expiry detection |
| `_ASHELL-TOAST-SEVERITY` | 0 | Its severity |
| `_ASHELL-TOAST-SERIAL` | 0 | One more for each notice raised |
| `_ASHELL-TOAST-SHOWN` | 0 | The last paint showed a notice |
| `_ASHELL-CUR-ROW` | mid | Cursor row position |
| `_ASHELL-CUR-COL` | mid | Cursor column position |
| `_ASHELL-CUR-VIS` | 0 | Cursor visible flag |
| `_ASHELL-CUR-SAVED` | 0 | Back-buffer cell saved before cursor draw |
| `_ASHELL-CUR-SROW` | 0 | Row of saved cell |
| `_ASHELL-CUR-SCOL` | 0 | Col of saved cell |
| `_ASHELL-CUR-ACTIVE` | 0 | -1 if a saved cell needs restoring |

After every dependent gate succeeds, `_ASHELL-TEARDOWN` resets state to its
defaults. At a hard-gate failure it instead preserves the complete live state
and latches the quarantine described above.

## Completed root draw observation

`ASHELL-DRAW-OBSERVE! ( callback context -- )` installs an optional ordinary
observer; `ASHELL-DRAW-OBSERVER@ ( -- callback context )` reports its owner.
Callbacks receive `( phase root-instance context -- )` synchronously on the
UI owner core, return no values, and must not mutate shell state.

- `ASHELL-DRAW-BEGIN=0` runs before any write of an actual dirty root paint.
- `ASHELL-DRAW-COMPLETE=1` runs after app paint, toast, cursor and
  `SCR-DRAW-COMPLETE` all finish successfully. A throwing paint omits it.

Observers may stage copied metadata on BEGIN and publish it only on
COMPLETE. Callback exceptions are
caught and cannot interrupt ordinary CELL output. The installer must check
existing ownership before installing and remove its callback before freeing
its context. `ASHELL-STORAGE-DISJOINT? ( address bytes -- flag )` protects
module storage for such bounded observers. The independent
[shell snapshot](shell-snapshot.md) consumer combines this transaction with
ordinary host observation without using a child UIDL context.
