# akashic/tui/applets/desk/desk.f — TUI Multi-App Desktop

**Prefix:** `DESK-` (public), `_DESK-` / `_DTH-` / `_HB-` / `_DHBAR-` (internal)  
**Provider:** `akashic-tui-desk`  
**Location:** `akashic/tui/applets/desk/desk.f`  
**Dependencies:** [`app-shell.f`](../../app-shell.md), [`app-desc.f`](../../app-desc.md),
[`uidl-tui.f`](../../uidl-tui.md), [`screen.f`](../../screen.md),
[`region.f`](../../region.md), [`draw.f`](../../draw.md),
[`keys.f`](../../keys.md), [`color.f`](../../color.md),
[`toml.f`](../../../utils/toml.md), [`app-catalog.f`](../../app-catalog.md),
`app-loader.f`, `app-builder.f`,
[`tls-trust-registry.f`](../../../net/tls-trust-registry.md),
[`external-io.f`](../../../net/external-io.md),
`liraq/uidl.f`

## Why `applets/`?

Most Akashic TUI modules are standalone composable components — each
one provides a self-contained service.  Modules in `applets/` are
*applets*: APP-DESC applications hosted by
[`app-shell.f`](../../app-shell.md) (or by the desk itself).  They
are not independently composable components but complete applications
that depend on the shell lifecycle.

## Overview

Multi-app desktop with dynamic tiling.  Runs as a **normal APP-DESC
applet** inside [`app-shell.f`](../../app-shell.md) — no private
event loop.

The desk delegates all terminal ownership, event dispatch, paint
cycling, and tick timing to the shell:

## Ownership boundary

Desk owns applet installation policy and lifecycle, layout/focus, activation
sequencing, service composition, typed routing, review surfaces, and the
machine external-I/O lifecycle. It does not own Library records, Daybook
content or time semantics, Agent threads, Grid workbooks, Streams sources or
observations, Practice bindings/authority, or another applet's parsing and
storage merely because it constructs or retains a service.

A focused tile, active applet, selected row/date/cell, handler match, resource
discovery result, or Practice binding is not a mutation target and is not
authority. Consequential routed calls carry the exact domain owner, stable
resource/qualified locator, expected domain revision, and complete operands.
Create/import uses its separately sealed owner/catalog precondition and
idempotency key. Desk may resolve such a durable name to activation-local
services and bindings for a call, but it never persists an `LBIND`, live grant,
component pointer, or XIO handle as domain identity.

## Architecture

```
  app-shell.f           (terminal via term-init.f, event loop, paint cycle)
    └── DESK-DESC       (APP-DESC callbacks)
          ├── DESK-INIT-CB     → reset state
          ├── DESK-EVENT-CB    → shortcuts, route to focused sub-app
          ├── DESK-TICK-CB     → tick all alive sub-apps
          ├── DESK-PAINT-CB    → bg fill*, paint tiles, dividers, taskbar
          ├── DESK-REQUEST-CLOSE-CB → negotiate every child
          └── DESK-SHUTDOWN-CB → close all sub-apps
```

\* Background fill only runs when `_DESK-BG-DIRTY` is set (init,
relayout, resize).  `UTUI-PAINT` only redraws dirty UIDL elements, so an
unconditional fill would wipe content that clean elements wouldn't
repaint.  The flag ensures: fill runs → all elements are dirty (from
relayout) → full repaint over the fill.  Normal paint cycles skip
the fill entirely.

Sub-apps are isolated via per-app **UIDL context** buffers (~97 KiB each),
which save/restore the 15 UIDL scalar variables and 10 pool arrays.

## Tiling Algorithm

Given **N** visible apps and usable area **W × H** (H = SCR-H − 1 for taskbar):

- **V-pref** (default): `cols = ceil(√N)`, `rows = ceil(N / cols)`
- **H-pref**: `rows = ceil(√N)`, `cols = ceil(N / rows)`
- Tile size: `tw = (W − (cols−1)) / cols`, `th = (H − (rows−1)) / rows`
- Last column/row absorbs remainder pixels
- 1-cell dividers drawn between adjacent tiles

Toggle with `DESK-TOGGLE-VH`.  Full-frame mode (`DESK-FULLFRAME!`) shows
only the focused app and hides dividers.

## Slot Structure

Each sub-app occupies a heap-allocated 88-byte slot, linked in a singly
linked list.  Slot IDs are monotonic (1, 2, 3, …).

| Offset | Field | Description |
|--------|-------|-------------|
| +0 | `DESC` | APP-DESC pointer |
| +8 | `INST` | Generic component instance |
| +16 | `RGN` | Region handle (0 if no region) |
| +24 | `STATE` | 0=empty, 1=running, 2=minimized, 3=focused |
| +32 | `UCTX` | UIDL context pointer (0 = no UIDL) |
| +40 | `HAS-UIDL` | Flag: app has UIDL? |
| +48 | `NEXT` | → next slot in list (0 = tail) |
| +56 | `ID` | Unique slot ID |
| +64 | `UIDL-BUF` | Shell-loaded UIDL file buffer (0 = none) |
| +72 | `DIRTY` | Child surface needs repaint |
| +80 | `SEEN-REV` | Last painted component revision |

## ASHELL-QUIT Interception

When a sub-app calls `ASHELL-QUIT`, `DESK-EVENT-CB` intercepts it
via the public API:

1. Checks `ASHELL-QUIT-PENDING?` (returns true when quit is pending)
2. Calls `ASHELL-CANCEL-QUIT` (re-arms the event loop)
3. Calls `DESK-REQUEST-CLOSE-ID` with `APP-CLOSE-R-QUIT`
4. Returns −1 (consumed) to the shell

ALLOW shuts down and removes the tile.  CANCEL and DEFER preserve its entire
slot, component instance, and UIDL context.  The request and later shutdown
callbacks both run with that child's UIDL context and activation binding live.
Context entry, callback, save, and exit are fault boundaries: any failure while
negotiating is normalized to CANCEL, and Desk attempts to leave the child
context before returning.

Closing Desk itself is two-phase.  `DESK-REQUEST-CLOSE-CB` queries every
child with `APP-CLOSE-R-HOST-SHUTDOWN` without destroying any of them.  CANCEL
wins over DEFER, and DEFER wins over ALLOW.  Only an all-ALLOW pass lets the
shell enter `DESK-SHUTDOWN-CB`; shutdown then force-cleans those approved
children without prompting again, so it cannot loop forever on a refusal.
Force-close catches shutdown, UIDL detach, context-exit, and resource-release
faults independently.  It unlinks the slot and attempts every known release
before returning its first cleanup error.  Top-level Desk shutdown drains all
children and completes Desk cleanup before surfacing the first such error to
the shell.  If context entry/activation itself fails, Desk suppresses the
child-owned shutdown callback rather than invoke it against an uncertain
context.  UIDL detach has a stricter identity check of its own: it runs only
when the active UCTX is exactly the child's, allowing cleanup after an
activation failure without touching a wrong context.  Desk still unlinks the
slot and releases every host-owned handle it can identify.

## Theme System

The desk has 15 colour slot variables (`_DTH-*`) controlling the
desktop background, taskbar, active/minimized/pinned entries, dividers,
and clock.  `_DESK-THEME-DEFAULTS` sets a dark-blue palette.  All slots
can be overridden via a TOML config file under `[desk.theme]`.

| TOML Key | Slot | Default |
|----------|------|---------|
| `taskbar-fg` | Normal taskbar text | 15 (white) |
| `taskbar-bg` | Taskbar background | 17 (dark blue) |
| `active-fg` | Focused slot label | 0 (black) |
| `active-bg` | Focused slot background | 12 (bright blue) |
| `minimized-fg` | Minimized slot label | 8 (dark gray) |
| `minimized-bg` | Minimized slot background | 17 |
| `pinned-fg` | Hotbar pinned entry text | 244 (medium gray) |
| `pinned-bg` | Hotbar pinned background | 0 (black) |
| `divider-fg` | Tile divider lines | 240 (bright gray) |
| `divider-bg` | Divider background | 0 |
| `clock-fg` | Clock text | 14 (cyan) |
| `clock-bg` | Clock background | 17 |
| `desk-bg` | Desktop background (layer 0) | 17 |

Colour values are parsed by `TUI-PARSE-COLOR`: CSS named colours,
`#RRGGBB`, `#RGB`, or raw 0–255 xterm-256 indices.

## Durable Catalog, Hotbar, and Launcher

Desk owns one bounded catalog at `/app-catalog.bin`.  The catalog copies applet
identity, title, version, and installed-manifest path and durably records the
enabled, pinned, autostart, and quarantine flags.  The hotbar is now simply the
first twelve pinned catalog rows: `<Label>` is available, `[Label]` is running,
`(Label)` is disabled, and `!Label!` is quarantined or failed.  Closing an
applet clears only its live slot; its cached descriptor remains available for a
fast relaunch during the same Desk session.

The running-slot labels at the left edge of the taskbar are also live pointer
targets.  Painting and hit-testing use the same exact label builder, including
the focused `*` and minimized `~` suffixes.  A left press on one of those labels
focuses that exact slot and restores it first if minimized.  The one-cell
separators between labels are inert.  This does not yet make pinned catalog
entries pointer-launchable; their keyboard/launcher behavior is unchanged.

`Alt+H` opens a non-blocking modal over the desktop.  It lists every catalog
row and its status.  Up/Down, PgUp/PgDn, Home/End select; Enter focuses an
already-running row or lazily resolves and transactionally launches it; Esc
closes the modal.  Package resolution is manifest-bound:
`ACE-MANIFEST$ ALOAD-PATH`.  Desk does not evaluate catalog text or load any
package during catalog activation.  Built-ins bind only when the exact
component ID matches a queued descriptor.  The companion releaser calls
`ALOAD-DESC-FREE` for loader-created package descriptors on replacement or
teardown; static built-in descriptors are never released.

`DESK-QUEUE-LAUNCH` remains source-compatible with existing profiles.  It now
migrates the descriptor into the catalog with enabled, pinned, and autostart
defaults.  Once persisted, the row's flags are authoritative on later boots.
Pad's Build & Install workflow receives the live catalog only after activation;
the builder pointer is cleared before the catalog is freed.

## Desk-private service routing

Desk's interoperability endpoint resolves services through an activation-local
table in Desk component state. The table has a fixed capacity of 16 and Desk
currently installs eleven entries. Each entry borrows an immutable exact service
ID and stores a getter XT; it does not cache or own the returned service. Lookups
are exact byte matches, and an unknown ID returns `0`.

Getters evaluate owner availability at lookup time. An unbound external-I/O
service, absent Agent composition, or inactive/unowned Daybook resource therefore
returns `0` without changing the table. The table is private lifecycle-routing
metadata, not a general `interop/` registry: discovery confers no authority, and
each domain owner retains its own semantics and validation.

Desk fills the table after constructing its service owners and before publishing
the endpoint. During dispatch-quiesced teardown it zeroes every entry after
request cancellation and before deactivating or freeing those owners. A retained
endpoint can consequently expose neither a stale getter nor a freed service, and
the existing owner dependency order remains unchanged.

## Desk-hosted Agent composition

Desk constructs, retains, and tears down the shared Agent composition for its
activation: a host-retained provider source, an Agent-runtime instance, the
scoped tool gateway, and the visible access profile. The Agent domain owns run,
thread, provider-neutral execution, tool/review-ledger, and Mandate semantics;
Desk owns the host lifecycle and policy composition, not those records. The
composition starts with the exact `Chat only` preset. `Practice read only`
adds bounded observations from trusted built-in applet instances, while
`Practice assist` also adds fixed local operations that always require review.
Each scoped run receives a freshly compiled Practice Mandate; the selected
profile is policy input and is not itself authority.

Children can borrow the composition through the Desk interoperability endpoint:

| Service ID | Value |
|------------|-------|
| `org.akashic.agent.runtime` | Shared Agent runtime |
| `org.akashic.agent.tool-gateway` | Shared scoped tool gateway |
| `org.akashic.agent.provider-source` | Host-retained provider source |
| `org.akashic.agent.access-profile` | Current immutable profile descriptor |

The source remains host-retained; children must not free it. A preset change
is rejected while a run or review is active, and the runtime freezes the
compiled facet for the duration of each accepted run.

## Desk-hosted activation-local Daybook owner

On a healthy Practice activation, Desk creates one resource registry and hosts
one headless [Daybook document owner](../../../daybook/shared-document.md) for
the canonical Daybook document. Daybook owns the document and its planner
semantics; its concrete owner now lives in the Daybook domain even though Desk
constructs it. Its semantic RID is the SHA3-256 digest of the stable Practice
ID and `org.akashic.resource.daybook`; the activation epoch and applet instance
IDs are deliberately absent. The RID therefore remains the same across Desk
restarts while its RID-to-instance mapping and current component revision
remain activation-local.

Children receive borrowed services through their inherited interoperability
endpoint:

| Service ID | Value |
|------------|-------|
| `org.akashic.runtime.context` | Active root Context |
| `org.akashic.runtime.resource-registry` | Activation-local `RREG` |
| `org.akashic.interop.request-bus` | Desk request bus |
| `org.akashic.resource.daybook` | Stable Daybook RID |
| `org.akashic.net.external-io` | Machine-owned cooperative external-I/O service |

The endpoint does not expose the owner instance. A lens resolves the RID into
an exact `RREF`, attaches its own `LBIND`, and invokes `resource.snapshot` or
`resource.replace` through the bus. If resource activation fails, Desk can
still run, but it withholds the Daybook RID. A child which can see the Desk
Context must treat an incomplete service set as a blocked Practice resource;
falling back to direct `/daybook.md` access would erase the distinction this
experiment is meant to test.

The external-I/O service serializes bounded machine-network operations whose
platform implementation shares core-0 state. Desk advances it once per Desk
tick independently of whether a child is dirty, clean, focused, or minimized.
It is a lifecycle service, not a raw networking capability: children retain
their own request, parser, transport, and semantic state, and agents do not
receive its submission callbacks. Before freeing a child, Desk cancels or
releases only operations whose instance identity and generation match that
child. Final Desk teardown drains any remaining operation before unbinding the
machine singleton.

Before creating that service or publishing any interoperability endpoint, Desk
freezes the machine TLS trust registry. Reviewed provider/network modules must
register their scoped contributions before Desk activation; source constructors
and applet launch do not modify trust. Desk teardown unbinds external I/O but
does not reset or thaw the accepted machine snapshot.

Desk closes every lens before entering one dispatch-quiesced teardown boundary
which cancels requests, deactivates the owner, and frees the resource registry,
bus, and component registry in dependency order. No new synchronous dispatch
can enter between owner unpublication and bus free. Practice deactivation is
skipped if dependent interoperability teardown throws, so the Context is not
freed from underneath a live owner.

This is not yet enforced path ownership. File Explorer and arbitrary trusted
native code can still write `/daybook.md` directly, outside the owner's
revision sequence. The current claim is intentionally narrower: Daybook and
Pad lenses coordinate through one Daybook owner by convention. Desk hosts and
routes that owner but does not acquire its data or semantic authority.

## Config Loading

`DESK-LOAD-CONFIG ( addr len -- )` takes a TOML buffer and loads the theme.
Legacy `[[desk.hotbar]]` tables remain parseable for compatibility, but they
never override an active catalog and their file/descriptor strings are never
evaluated.

To supply a config before `DESK-RUN`, store the buffer address/length
in `_DESK-CFG-A` / `_DESK-CFG-L`.  `DESK-INIT-CB` will call
`DESK-LOAD-CONFIG` automatically if these are non-zero.

A sample config template is provided in
[desk.toml](../../../../akashic/tui/applets/desk/desk.toml).

## API Reference

### Sub-App Management

| Word | Stack | Description |
|------|-------|-------------|
| `DESK-LAUNCH` | `( desc -- id )` | Launch sub-app from APP-DESC.  Returns slot ID (−1 on failure). |
| `DESK-TRY-LAUNCH` | `( desc -- id ior )` | Transactional launch with an explicit error.  Every known host resource is rolled back on failure. |
| `DESK-CLOSE-ID` | `( id -- )` | Compatibility window-close request; CANCEL/DEFER leave the child live. |
| `DESK-REQUEST-CLOSE-ID` | `( id reason -- decision )` | Negotiate close; ALLOW shuts down/removes, CANCEL/DEFER preserve. |
| `DESK-FOCUS-ID` | `( id -- )` | Focus sub-app by slot ID.  Restores that exact slot if minimized; no-op if not found. |
| `DESK-MINIMIZE-ID` | `( id -- )` | Minimize sub-app (alive but hidden). |
| `DESK-RESTORE` | `( -- )` | Restore last minimized app. |

### Layout

| Word | Stack | Description |
|------|-------|-------------|
| `DESK-RELAYOUT` | `( -- )` | Recompute tile grid.  Called automatically on launch/close/minimize and minimized-slot focus/restore. |
| `DESK-FULLFRAME!` | `( flag -- )` | Toggle full-frame mode (show only focused app). |
| `DESK-TOGGLE-VH` | `( -- )` | Toggle V-pref / H-pref tiling. |

### Queries

| Word | Stack | Description |
|------|-------|-------------|
| `DESK-SLOT-COUNT` | `( -- n )` | Number of live slots (all states). |
| `DESK-VCOUNT` | `( -- n )` | Number of visible (non-minimized) slots. |
| `DESK-CATALOG` | `( -- catalog\|0 )` | Active installed-applet catalog. |

### Configuration

| Word | Stack | Description |
|------|-------|-------------|
| `DESK-LOAD-CONFIG` | `( addr len -- )` | Load presentation/theme TOML. |
| `DESK-AGENT-SOURCE!` | `( source -- )` | Transfer a provider source to Desk before run. Replacing a pending source frees the old one. |
| `DESK-AGENT-ACCESS-PRESET!` | `( preset -- status )` | Select one exact built-in Agent access preset; active runs and reviews reject changes. |
| `DESK-AGENT-ACCESS` | `( -- profile\|0 )` | Borrow the current Desk-owned immutable access profile. |

### Startup

| Word | Stack | Description |
|------|-------|-------------|
| `DESK-QUEUE-LAUNCH` | `( desc -- )` | Compatibly register a pinned/autostart built-in.  Call before `DESK-RUN`. |
| `DESK-QUEUE-BUILTIN` | `( desc flags -- )` | Queue an exact-ID built-in binding with caller-selected catalog defaults. |
| `DESK-PACKAGE-RESOLVER!` | `( xt context -- )` | Replace the lazy package resolver; hook is `( entry context -- desc status )`. |
| `DESK-PACKAGE-RELEASER!` | `( xt context -- )` | Before run, set the companion descriptor hook `( desc context -- )`. |
| `DESK-RUN` | `( -- )` | Fill `DESK-DESC`, call `ASHELL-RUN`.  Blocks until shell exits. |

The package hook setters are constructor-only.  Replacing the resolver clears
the pending releaser, so a custom resolver that allocates descriptors must then
install its matching releaser before `DESK-RUN`.

## Keyboard Shortcuts

All shortcuts require **Alt** modifier:

| Key | Action |
|-----|--------|
| Alt+1 … Alt+9 | Focus slot by ID |
| Alt+Tab | Cycle focus to next visible slot |
| Alt+M | Minimize focused slot |
| Alt+R | Restore last minimized |
| Alt+F | Toggle full-frame mode |
| Alt+L | Toggle V/H tiling preference |
| Alt+W | Close focused slot |
| Alt+H | Open the selectable catalog launcher |

Inside the launcher: Up/Down, PgUp/PgDn, Home/End move; Enter focuses or
launches; Esc closes it.  The modal consumes input without blocking Desk ticks.

Alt+Arrow, Alt+Del, Alt+End, and Alt+PgDn are reserved by&nbsp;the shell
cursor and never reach desk’s event handler.

## Mouse Dispatch

When the shell cursor synthesises a click (or a real mouse event
arrives), `DESK-EVENT-CB` detects the `KEY-T-MOUSE` type via
`ASHELL-MOUSE?` and routes to `_DESK-DISPATCH-MOUSE` before any
keyboard handling.

**Tile hit-test** — `_DESK-TILE-AT ( row col -- slot | 0 )` walks the
linked-list of visible slots and checks whether `(row, col)` falls
within each tile's region bounds.  Saves the region's row, col, h, w
into private variables (`_DTA-RR`/`RC`/`RH`/`RW`) to avoid stack
juggling, then performs four comparisons:
`rr <= row`, `rc <= col`, `rr+rh > row`, `rc+rw > col`.
Returns the first matching slot, or 0 on miss.

**Taskbar dispatch** — a left-button press on the taskbar row first scans the
rendered live-slot labels.  `_DESK-TASKBAR-LABEL` supplies the exact text and
length to both painting and `_DESK-TASKBAR-SLOT-AT`, so hit geometry cannot
drift from the visible labels.  A hit calls `DESK-FOCUS-ID`, consuming the
press; focusing a minimized label restores that exact slot and relayouts.
Separators, blank taskbar cells, pinned entries, and button releases are not
handled by this path.

**Tile dispatch** — `_DESK-DISPATCH-MOUSE` saves the event pointer in
`_DDM-EV`, extracts row/col for hit-testing, then drops the intermediate
values.  A left press focuses the winning tile before switching into its child
context and forwarding the same event to `UTUI-DISPATCH-MOUSE`.  This preserves
child click delivery while ensuring callbacks observe their tile as focused.
The press remains handled when focus changed even if the child has no UIDL or
declines the event.  Releases never change focus.  Focusing an already-visible
tile marks Desk dirty but does not relayout its peers; only restoring a
minimized target requires new tile geometry.  If no tile is hit, the event is
dropped.

## UIDL Context System

Each sub-app with a UIDL document gets a ~97 KiB context buffer that
captures:

- **15 scalar variables**: element count, attribute count, string position,
  root pointer, subscription count, elem base, doc-loaded flag, state,
  focus pointer, action count, shortcut count, overlay count, saved focus,
  skip-children flag, region handle.
- **10 pool arrays**: elements (32 KiB), attributes (20 KiB), strings
  (12 KiB), hash (2 KiB), hash-IDs (4 KiB), subscriptions (3 KiB),
  sidecars (20 KiB), actions (1.5 KiB), shortcuts (2 KiB), overlay
  buffer (0.5 KiB).

The UCTX system (`UCTX-ALLOC`, `UCTX-FREE`, `UCTX-SAVE`, `UCTX-RESTORE`,
`UCTX-CLEAR`, `UCTX-TOTAL`) is defined in `uidl-tui.f` §18b, which owns
the private variables being serialised.

Context switch (`_DESK-CTX-SWITCH`) saves the current sub-app's globals
via `CMOVE` and restores the target's.  Only one sub-app's context is
live at a time.  Desk delegates to `ASHELL-CTX-SWITCH` and
`ASHELL-CTX-SAVE` — it never calls `UCTX-SAVE`/`UCTX-RESTORE` directly.

## Internal Sections

| § | Title | Description |
|---|-------|-------------|
| 1 | Slot Struct | 88-byte linked-list node, state enum |
| 2 | DESK Global State | Head, focus, ID counter, layout prefs |
| 2b | Theme | 15 colour slot variables, defaults, TOML loader |
| 2c | Hotbar | Pinned catalog projection and legacy TOML compatibility |
| 2d | Config Loader | `DESK-LOAD-CONFIG` master loader |
| 3 | Linked-List Helpers | Find, unlink, append, count |
| 4 | Visible Collection Buffer | Up to 64 visible slots |
| 5 | Tiling Layout Engine | Grid, tile sizes, region assignment, dividers |
| 6 | Context Switching | Save/restore/switch helpers (delegates to shell) |
| 7 | Launch & Close | transactional `DESK-TRY-LAUNCH`, rollback, close negotiation |
| 8 | Focus/Minimize/Restore | State transitions, auto-focus |
| 9 | Taskbar Painter | Shared live-label geometry, per-item styled painting, hotbar + divider |
| 10 | APP-DESC Callbacks | Init, event, tick, paint, shutdown |
| 10b | Mouse Dispatch | Live-taskbar activation + focus-before-forward tile routing |
| 11 | Descriptor & Entry | `DESK-DESC`, `_DESK-FILL-DESC`, `DESK-RUN` |
| 12 | Guard | `WITH-GUARD` wrappers for concurrency safety |

## Guard-Protected Words

Under `[DEFINED] GUARDED`: `DESK-FOCUS-ID`,
`DESK-MINIMIZE-ID`, `DESK-RESTORE`, `DESK-FULLFRAME!`,
`DESK-TOGGLE-VH`, `DESK-RELAYOUT`, `DESK-SLOT-COUNT`, `DESK-VCOUNT`,
`DESK-AGENT-SOURCE!`, `DESK-AGENT-ACCESS-PRESET!`, `DESK-AGENT-ACCESS`,
`DESK-PRACTICE`, `DESK-CONTEXT`, and `DESK-RECOVERY?`.

`DESK-RUN`, `DESK-LAUNCH`, `DESK-TRY-LAUNCH`, `DESK-CLOSE-ID`, and
`DESK-REQUEST-CLOSE-ID` are owner-core lifecycle entries and remain unwrapped.
Launch/init and close callbacks may execute arbitrary applet code, so no
metadata guard is retained across them.  Cross-core producers must post these
requests to Desk's owner task.
