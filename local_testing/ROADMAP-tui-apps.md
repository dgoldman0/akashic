# ROADMAP — TUI App Shell & Runtime

> Akashic has a DOM, CSS engine, layout system, paint cycle, focus chain,
> channels, structured concurrency, futures, app manifests, and binary images.
> But there is no **runtime** running them — no browser for the DOM.
> This roadmap builds that runtime.

---

## The Gap

Akashic's TUI stack has two halves that don't connect:

**Infrastructure that exists:**
- UIDL DOM with element types, attributes, dirty tracking, tree walks
- CSS style parser with inheritance, color/attr resolution
- Layout engine (`UTUI-RELAYOUT`) — computes absolute row/col/w/h for every element
- Paint cycle (`UTUI-PAINT`) — DFS dirty-repaint with z-index overlay support
- Focus chain (`FOC-*`) and keyboard dispatch (`UTUI-DISPATCH-KEY`)
- Widgets: textarea, tree, input, selector, toggle, range, table, toast, dialog
- App manifest (`app-manifest.f`) — TOML with name/title/version/entry/deps
- Binary app images (`app-image.f`) — freeze/thaw compiled apps as `.m64`
- Full concurrency toolkit — channels, futures, structured concurrency, parallel combinators

**What's missing: a runtime that manages these.**

Today every app must manually:
1. Init the terminal (`APP-INIT`)
2. Parse and load a UIDL document (`UTUI-LOAD`)
3. Create and place widgets by hand
4. Run its own blocking `KEY-READ` event loop
5. Orchestrate paint: call `UTUI-PAINT`, then `WDG-DRAW` per widget, then `SCR-FLUSH`
6. Manage focus with ad-hoc variables
7. Clean up everything in reverse order

This is like writing a web app that also has to implement `requestAnimationFrame`,
the focus manager, and the compositor. The result: every app reinvents the same
plumbing and the same bugs.

---

## Architecture Target

```
┌──────────────────────────────────────────────────┐
│  APP-SHELL  (Task 0 — owns screen + input)       │
│                                                  │
│  ┌── event loop (KEY-POLL + tick) ──────────┐    │
│  │  1. poll input                           │    │
│  │  2. route to focused app                 │    │
│  │  3. each app: APP.EVENT-XT               │    │
│  │  4. each app: APP.PAINT-XT if dirty      │    │
│  │  5. composite → SCR-FLUSH                │    │
│  │  6. YIELD?                               │    │
│  └──────────────────────────────────────────┘    │
│                                                  │
│  ┌── App A ───────┐  ┌── App B ───────────┐     │
│  │  UIDL document  │  │  UIDL document     │     │
│  │  screen region  │  │  screen region     │     │
│  │  APP-DESC       │  │  APP-DESC          │     │
│  │  channel ←→     │  │  channel ←→        │     │
│  └─────────────────┘  └────────────────────┘     │
└──────────────────────────────────────────────────┘
```

### App Descriptor

```forth
BEGIN-STRUCTURE APP-DESC
    FIELD: APP.UIDL-A       \ UIDL source address
    FIELD: APP.UIDL-U       \ UIDL source length
    FIELD: APP.REGION        \ assigned screen region
    FIELD: APP.INIT-XT       \ ( app -- )          init callback
    FIELD: APP.EVENT-XT      \ ( ev app -- flag )   input handler
    FIELD: APP.PAINT-XT      \ ( app -- )          paint callback
    FIELD: APP.TICK-XT       \ ( app -- )          per-frame tick (timers, animation)
    FIELD: APP.SHUTDOWN-XT   \ ( app -- )          cleanup
    FIELD: APP.CHAN          \ input channel from shell
    FIELD: APP.DIRTY?        \ paint-needed flag (cvar for notification)
END-STRUCTURE
```

### Apps Become Passive

Apps export callbacks. The runtime owns the loop.

```forth
: MY-APP-EVENT  ( ev app -- handled? )
    DROP  UTUI-DISPATCH-KEY ;

: MY-APP-PAINT  ( app -- )
    DROP  UTUI-PAINT ;
```

---

## Staged Plan

### Stage 1 — App Lifecycle Protocol  ✅ DONE

**Goal**: Define a standard app contract so the runtime can manage any app
uniformly.

**Delivered**: `tui/app-shell.f` (411 lines, 16/16 tests passing).

**The contract**:
- App provides an `APP-DESC` (96-byte struct, 12 fields) with callback XTs
- `ASHELL-RUN ( desc -- )` — blocks until quit or throw;
  terminal always restored
- Runtime calls `APP.INIT-XT` once during setup
- Runtime calls `APP.EVENT-XT` when input arrives (app gets first crack,
  then UIDL dispatch)
- Runtime calls `APP.TICK-XT` at configurable interval (default 50 ms)
- Runtime calls `APP.PAINT-XT` when dirty flag is set
- Runtime calls `APP.SHUTDOWN-XT` on quit or crash

**Key features**:
- Non-blocking event loop (`KEY-POLL`), cooperative yield (`YIELD?`)
- `CATCH`-guarded teardown — terminal always restored on throw
- UIDL integration: optional `APP.UIDL-A/U` to auto-load document
- Deferred action queue (`ASHELL-POST`, 16-slot FIFO)
- Root region auto-created, resize handling built in
- `ASHELL-QUIT` safe to call from init callback

**Bug fixes shipped alongside**:
- `_ASHELL-SETUP`: two `ELSE DROP` patterns that consumed the descriptor
  when title-a / uidl-a were 0 (stack imbalance → corrupted EXECUTE target)
- `UTUI-LOAD`: five internal functions leaked 1 item each on the stack
  (net +6 items corrupting callers). Fixed by adding DROP after each.

**Files**: `tui/app-shell.f`, `tui/uidl-tui.f` (UTUI-LOAD fix).
**Docs**: `docs/tui/app-shell.md`.
**Tests**: `local_testing/test_app_shell.py` (16 tests).

---

### Stage 2 — Style Inheritance for Widgets  ✅ DONE

**Goal**: Widgets inherit fg/bg/attrs from their parent UIDL element's
computed style instead of hardcoding colors.

**Delivered**: CSS inheritance in `_UTUI-RESOLVE-STYLES-REC`, public
style accessors, `DRW-STYLE-SAVE`/`DRW-STYLE-RESTORE`, widget updates,
`TUI-PARSE-COLOR` stack-bug fix + raw integer palette index support.
57/57 UIDL-TUI tests (11 new inheritance tests), 408/408 TUI tests,
16/16 app-shell tests, 221/221 CSS tests — all passing.

**Part A — CSS Inheritance** (`uidl-tui.f`):

`_UTUI-RESOLVE-STYLES-REC` now propagates inheritable properties from
parent to child before resolving the child's own `style=` attribute.
Inheritable properties (bits 0-25): fg, bg, attrs, text-align.
Non-inheritable (preserved from prelayout): position (bits 26-27),
z-index (bits 28-35).

`_UTUI-INHERIT-MASK` constant (`0x03FFFFFF`) defines which bits inherit.
The 4 layout-time style copies (stack, flex, tabs, split) were removed;
inheritance now works for ALL element types uniformly.

`TUI-PARSE-COLOR` had a pre-existing stack imbalance bug: when
`CSS-COLOR-FIND` failed, it returned 4 items instead of 2, leaking
+2 items per failed color parse. With multiple CSS color properties
this corrupted the resolver stack → infinite loop. Fixed all
failure paths (hex parse and named-color) to return exactly 2 items.
Also added raw integer palette index support (0-255).

**Part B — Widget Style Convention**:

Added `DRW-STYLE-SAVE` / `DRW-STYLE-RESTORE` to `draw.f`.
`_UTUI-STASH-SC` (UIDL paint path) calls `DRW-STYLE-SAVE` after
applying sidecar style, so widgets can call `DRW-STYLE-RESTORE`
to return to the inherited theme style after drawing highlights.

Updated widgets to use `DRW-STYLE-RESTORE` instead of hardcoded colors:
- tree.f: normal (non-selected) row style
- scroll.f: indicator drawing style
- split.f: horizontal and vertical divider style
- list.f: baseline clear, non-selected items, post-loop reset

Selection/cursor/focus highlights (reverse video) kept hardcoded —
these are semantic UI states, not theme-dependent.

**New public API**:
- `UTUI-SC-FG@` `( elem -- color )` — get computed foreground
- `UTUI-SC-BG@` `( elem -- color )` — get computed background
- `UTUI-SC-ATTRS@` `( elem -- attrs )` — get computed attributes
- `DRW-STYLE-SAVE` `( -- )` — save current fg/bg/attrs
- `DRW-STYLE-RESTORE` `( -- )` — restore saved fg/bg/attrs

**Files**: `tui/uidl-tui.f`, `tui/color.f`, `tui/draw.f`,
`tui/widgets/tree.f`, `tui/widgets/scroll.f`, `tui/widgets/split.f`,
`tui/widgets/list.f`.
**Tests**: `local_testing/test_uidl_tui.py` (11 new inheritance tests).

### Stage 3 — UIDL Overlays (Prompts, Menus, Tooltips)  ✅ DONE

**Goal**: Any transient UI (prompts, context menus, autocomplete, tooltips)
is a UIDL element with z-index — not raw `DRW-*` writes over other content.

**Delivered**: Generic overlay show/hide (`UTUI-SHOW`/`UTUI-HIDE`),
corrected two-pass overlay paint (Pass 1 skips overlay subtrees,
Pass 2 paints full subtrees), dirty-rect based repaint on hide,
focus capture/restore for overlays.
69/69 UIDL-TUI tests (12 new overlay tests), 408/408 TUI tests,
16/16 app-shell tests, 221/221 CSS tests — all passing.

**Overlay Paint Fix** (`uidl-tui.f` §13):

The two-pass paint previously had a bug: Pass 1 continued to visit
children of deferred overlay elements, painting them in the wrong
order (under base content).  Fixed by adding `_UTUI-SKIP-CHILDREN`
flag — when `_UTUI-PAINT-ELEM` defers an element, it sets the flag.
The Pass 1 DFS checks the flag and calls `_UTUI-SKIP-SUBTREE` to
advance past all descendants.  Pass 2 now uses `_UTUI-PAINT-SUBTREE`
to render the full subtree (element + all descendants in tree order)
instead of just the root element.

**Generic Show / Hide** (`uidl-tui.f` §16):

`UTUI-SHOW ( id-a id-l -- )` — sets VIS flag on element and all
descendants via `_UTUI-VIS-SUBTREE!`, marks entire subtree dirty
via `_UTUI-DIRTY-SUBTREE`, saves current focus in `_UTUI-SAVED-FOCUS`,
then scans for the first focusable descendant and sets focus there.

`UTUI-HIDE ( id-a id-l -- )` — snapshots the overlay's bounding
rect, clears VIS on entire subtree, calls `_UTUI-DIRTY-RECT` to find
and dirty all visible base-layer elements whose rects overlap the
overlay, calls `DRW-CLEAR-RECT` to erase the area, then restores
saved focus (if the saved element is still visible).

`UTUI-SHOW-DIALOG` / `UTUI-HIDE-DIALOG` are now thin wrappers
that delegate to the generic `UTUI-SHOW` / `UTUI-HIDE`.

**Dirty Helpers**:

- `_UTUI-DIRTY-SUBTREE ( elem -- )` — DFS walk, sets UIDL-DIRTY!
  on every element in the subtree.
- `_UTUI-DIRTY-RECT ( row col h w -- )` — full-tree scan, marks
  all visible elements whose bounding rects overlap the given
  rectangle as dirty.  Uses proper AABB overlap test.

**New public API**:
- `UTUI-SHOW` `( id-a id-l -- )` — show overlay by ID
- `UTUI-HIDE` `( id-a id-l -- )` — hide overlay by ID

**Files**: `tui/uidl-tui.f`.
**Tests**: `local_testing/test_uidl_tui.py` (12 new overlay tests).

### Stage 4 — Multi-App Compositor

**Goal**: Unlimited apps share the screen, each in its own region with
its own UIDL context.  An always-on taskbar occupies the last row.
All sizes are dynamic — derived from `SCR-W` / `SCR-H` at runtime,
recomputed on every resize.

**Design decisions** (finalized):

1. **Divider lines** — 1-cell dividers between tiled panes.
2. **Auto-tiling** — grid dimensions chosen automatically by visible
   count and screen aspect; `Alt+L` toggles V/H preference.
3. **App launcher** — overlay (Stage 3 dialog system).
4. **Full-frame override** — other visible apps hidden from paint but
   still ticked; they are NOT minimized.
5. **All-Task-0 execution** — every app callback (init, event, tick,
   paint, shutdown) runs cooperatively in the shell's task.
   Channels / BG-SLOT deferred to Stage 5.
6. **No artificial slot limit** — the only limits are memory
   (~97 KiB per UIDL context) and usable screen space.
   A linked-list or dynamically-sized slot array replaces the old
   fixed-3 `CREATE` table.

#### Screen Budget

Screen size comes from `SCR-W` / `SCR-H` (updated by `SCR-RESIZE`
on terminal resize).  The last row (`SCR-H - 1`) is reserved for the
taskbar → **`SCR-W × (SCR-H - 1)` usable** for app tiles.

Nothing is hardcoded to 80×24.

#### Taskbar (last row, always on)

```
[1:Pad*] [2:Explore~] [3:--]  ...            HH:MM
```

- One label per live slot.  Scrolls if labels overflow `SCR-W`.
- `*` = focused, `~` = minimized, no suffix = running.
- Right-aligned: optional clock / status.
- Shell-owned, painted via direct `DRW-*` calls (no UIDL).
- Painted last every frame, after all app panes.

#### Dynamic Tiling Algorithm

Given **N** visible (non-minimized) apps and usable area
**W × H** (`SCR-W × (SCR-H - 1)`):

1. **Pick grid dimensions `(rows, cols)`.**
   Choose the smallest grid where `rows × cols ≥ N`:
   - Default preference `_COMP-VH = 0` (vertical-first):
     `cols = ceil(sqrt(N))`, `rows = ceil(N / cols)`.
   - Preference `_COMP-VH = 1` (horizontal-first):
     `rows = ceil(sqrt(N))`, `cols = ceil(N / rows)`.

2. **Compute base tile size.**
   Account for 1-cell dividers between adjacent tiles:
   - `tile-w = (W - (cols - 1)) / cols`
   - `tile-h = (H - (rows - 1)) / rows`
   - Remainder pixels go to the *last* column / row:
     `last-w = W - (cols - 1) - tile-w * (cols - 1)`,
     `last-h = H - (rows - 1) - tile-h * (rows - 1)`.

3. **Assign regions.**
   Walk visible slots left-to-right, top-to-bottom.  Each gets
   `RGN-NEW ( row col h w )` with the computed position and size.
   The last row of the grid may be partially filled (empty cells on
   the right are unused).

4. **Draw dividers.**
   Vertical divider columns: `col = x × (tile-w + 1) - 1` for each
   split.  Horizontal divider rows: `row = y × (tile-h + 1) - 1`.
   Use `DRW-VLINE` / `DRW-HLINE` with box-drawing characters.

**Example** — 4 apps on 80×24 (usable 80×23):
- Grid: 2×2. tile-w = (80-1)/2 = 39, tile-h = (23-1)/2 = 11.
- Regions: (0,0,11,39), (0,40,11,40), (12,0,11,39), (12,40,11,40).
- Dividers: col 39 vertical full-height, row 11 horizontal full-width.

**Example** — 5 apps on 120×40 (usable 120×39):
- Grid: 3×2 (cols=3, rows=2). tile-w = (120-2)/3 = 39, tile-h = (39-1)/2 = 19.
- Row 0: slots at (0,0,19,39), (0,40,19,39), (0,80,19,40).
- Row 1: slots at (20,0,19,39), (20,40,19,39).  Third cell empty.

This scales to any screen size and any number of apps.

#### Minimize & Full-Frame

- **Minimize**: app stays alive, not painted, no key events routed,
  ticks still called.  Taskbar shows `~`.  Remaining visible apps
  re-tile via the algorithm above.
- **Full-frame** (`Alt+F`): focused app gets the full usable area;
  other visible apps hidden from paint, still ticked.

#### Slot Management

No fixed-size table.  Slots are heap-allocated via `ALLOCATE`:

```forth
\ Per-slot struct (7 cells = 56 bytes)
 0 CONSTANT _SLOT-O-DESC       \ APP-DESC pointer
 8 CONSTANT _SLOT-O-RGN        \ region handle (0 if minimized)
16 CONSTANT _SLOT-O-STATE      \ 0=empty 1=running 2=minimized 3=focused
24 CONSTANT _SLOT-O-UCTX       \ UIDL context pointer (0 = no UIDL)
32 CONSTANT _SLOT-O-HAS-UIDL   \ flag
40 CONSTANT _SLOT-O-NEXT       \ → next slot (linked list) or 0
48 CONSTANT _SLOT-O-ID         \ unique slot ID (monotonic counter)
56 CONSTANT _SLOT-SZ
```

A singly-linked list (`_COMP-SLOT-HEAD`) holds all live slots.
`COMP-LAUNCH` allocates and links; `COMP-CLOSE` unlinks and frees.
Slot IDs are assigned from a monotonic counter so keyboard shortcuts
can address them by number (Alt+1 = ID 1, etc.).

#### Keyboard Shortcuts (shell-intercepted)

| Key | Action |
|-----|--------|
| `Alt+<digit>` | Focus slot with that ID (1-9) |
| `Alt+Tab` | Cycle focus forward through live slots |
| `Alt+M` | Minimize focused app |
| `Alt+R` | Restore most-recently-minimized |
| `Alt+F` | Toggle full-frame for focused app |
| `Alt+L` | Toggle V/H tiling preference |
| `Alt+W` | Close focused app (shutdown) |
| `Alt+N` | Open app launcher overlay |

#### UIDL Multi-Instance (Context Swap)

Each app with a UIDL document gets a context buffer (~97 KiB)
holding all 15 UIDL/UTUI scalar globals + 10 pool arrays.
`UCTX-SAVE` / `UCTX-RESTORE` copy between live globals and the
buffer.  `_COMP-CTX-SWITCH ( slot -- )` saves the outgoing app's
context and restores the incoming app's.

Since everything runs in Task 0 there are no races.  Memory cost
is ~97 KiB × N\_apps.  For 8 apps ≈ 776 KiB — well within budget
on a 64-bit system.

#### Event Loop (sketch)

```forth
: _COMP-LOOP  ( -- )
  BEGIN  _COMP-RUNNING @  WHILE
    KEY-POLL IF
      _COMP-EV COMP-SHORTCUT? 0= IF
        _COMP-EV COMP-ROUTE-KEY
      THEN
    THEN
    TERM-RESIZED? IF TERM-SIZE _COMP-ON-RESIZE THEN
    COMP-TICK-ALL
    COMP-PAINT-ALL      \ ctx-swap + RGN-USE per visible app
    _COMP-PAINT-TASKBAR  \ last row
    SCR-FLUSH
    YIELD?
  REPEAT ;
```

#### Resize Handling

`_COMP-ON-RESIZE ( w h -- )` calls `SCR-RESIZE`, then
`COMP-RELAYOUT` which recomputes the grid and reassigns regions
from the new `SCR-W` / `SCR-H`.  Each UIDL-bearing app's layout
tree is re-laid-out via `UTUI-RELAYOUT` in its context.

**Files**: `tui/app-compositor.f` (layout engine, taskbar, key
routing, slot list, UIDL context swap, event loop).

### Stage 5 — Shared Services & Environment

**Goal**: The shell provides shared system services that apps consume
through a uniform API rather than each wiring their own.

**5A — Shared Clipboard** (existing infrastructure):

`utils/clipboard.f` already provides `CLIP-COPY ( addr u -- ior )`,
`CLIP-PASTE ( -- addr u )`, and an 8-slot ring buffer backed by XMEM.
Today the pad wires this directly. In the multi-app world, the shell
owns the single clipboard instance and mediates access so copy in App A
→ paste in App B works without conflicts.

Shell API:
- `ASHELL-CLIP-COPY ( addr u -- ior )` — copy to shared clipboard
- `ASHELL-CLIP-PASTE ( -- addr u )` — paste from shared clipboard
- Guard-protected for multi-task safety

**5B — Mounted VFS**:

`utils/fs/vfs-mount.f` provides a mount table (`VMNT-MOUNT`,
`VMNT-RESOLVE`, up to 64 mount points × 256-byte prefix).
`utils/fs/drivers/vfs-mp64fs.f` bridges to the Megapad-64 native
filesystem.

The shell mounts a default filesystem at startup so apps get a
working `VMNT-OPEN` / `VMNT-RESOLVE` without configuring storage
themselves. Mount configuration comes from a simple config source
(initially hardcoded defaults, later from a config file — see 5D).

```forth
\ Shell startup mounts the SD card at /sd
S" /sd" MY-VFS VMNT-MOUNT     ( ior )
```

**5C — Notifications & IPC**:

Apps communicate via named channels. The shell provides:
- **Notifications** — apps send toast messages to the shell
- **File dialogs** — shell-provided Open/Save using the mounted VFS
- **Theme broadcast** — shell sends style-change events to all apps

Uses `conc-map.f` for a service registry:

```forth
S" clipboard" SVC-LOOKUP  ( chan )
S" hello" 5 CHAN-SEND-BUF
```

**5D — Shell Configuration** (later):

A settings system for the shell itself: default mount points, theme,
key bindings, tick interval, UIDL defaults. Likely TOML-based (we
have a TOML parser in `app-manifest.f`). Config loaded at shell
startup before any apps launch. Not required for initial stages —
hardcoded defaults work first, config file comes when there's enough
to configure.

**Files**: `tui/app-services.f` (clipboard/notification wrappers),
`utils/fs/vfs-mount.f` (already exists), `conc-map.f` integration,
eventually `tui/app-config.f`.

---

## Concurrency Primitives Available

| Module | Primitives | Role in Runtime |
|--------|-----------|-----------------|
| `channel.f` | `CHAN-SEND/RECV`, `CHAN-SELECT`, `CHAN-CLOSE` | Input routing, app↔shell signals |
| `scope.f` | `TASK-GROUP`, `TG-SPAWN`, `TG-WAIT`, `TG-CANCEL` | App lifecycle, crash isolation |
| `coroutine.f` | `WITH-BACKGROUND`, `BG-POLL`, `BG-WAIT-DONE` | Background app execution (BIOS slots) |
| `future.f` | `PROMISE`, `FULFILL`, `AWAIT`, `ASYNC` | App launch returns future; await exit |
| `cvar.f` | `CVAR`, `CV-WAIT` | Dirty-flag notification |
| `guard.f` | `WITH-GUARD` | Screen buffer protection |
| `conc-map.f` | `CMAP-PUT/GET` | Service registry |
| `event.f` | `EVT-WAIT/SET` | Low-level sync |

## Constraints

- **Cooperative only.** No preemption (`YIELD?`, `PAUSE`).
- **`KEY-READ` blocks the core.** Runtime must use `KEY-POLL` or `KEY-WAIT`.
- **Shared address space.** Guards protect state; no sandboxing.
- **Single screen buffer.** One `SCR-USE`. Software compositing only.
- **Dynamic screen size.** Use `SCR-W` / `SCR-H`; never hardcode 80×24.
- **UIDL single-instance.** One document per `UTUI-LOAD`. Multi-app
  solved by per-app UIDL context swap (~97 KiB each).
- **No artificial app limit.** Compositor uses heap-allocated linked
  list.  Practical limits: memory and usable tile size.

---

## Priority

**Stage 1** ✅ — App lifecycle protocol delivered.
**Stage 2** ✅ — Style inheritance for widgets delivered.
**Stage 3** ✅ — Overlays (prompts, menus, tooltips) delivered.
**Stage 4** — Multi-app compositor (next).
**Stage 5** — Shared services (clipboard, mounted VFS, IPC, config).

Each stage is independently valuable and shippable.
