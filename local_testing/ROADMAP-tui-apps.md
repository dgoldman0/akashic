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
│  APP-SHELL  (the browser engine)                 │
│  Owns: terminal, screen buffer, event loop,      │
│        YIELD?, paint cycle, UIDL integration     │
│                                                  │
│  ┌── ONE event loop ────────────────────────┐    │
│  │  1. KEY-POLL                             │    │
│  │  2. app EVENT-XT (first crack)           │    │
│  │  3. UIDL dispatch (shortcuts, focus)     │    │
│  │  4. drain deferred actions               │    │
│  │  5. app TICK-XT                          │    │
│  │  6. UTUI-PAINT + app PAINT-XT → FLUSH    │    │
│  │  7. YIELD?  (KDOS cooperative sched)     │    │
│  └──────────────────────────────────────────┘    │
│                                                  │
│  Runs exactly ONE app at a time via APP-DESC.    │
│  That app can be a simple single-document app    │
│  or the DESK (which manages sub-apps internally).│
│                                                  │
│  ┌── Single app ──┐   ┌── DESK (multi-app) ─┐   │
│  │  APP-DESC       │   │  APP-DESC            │   │
│  │  UIDL doc       │   │  manages N sub-apps  │   │
│  │  callbacks      │   │  tiling, taskbar     │   │
│  └─────────────────┘   │  ctx-swap per tile   │   │
│         OR             └──────────────────────┘   │
│                                                  │
│  ┌── Inside DESK ─────────────────────────────┐  │
│  │  ┌─ App A ─────┐  ┌─ App B ─────────┐     │  │
│  │  │ APP-DESC     │  │ APP-DESC        │     │  │
│  │  │ UIDL context │  │ UIDL context    │     │  │
│  │  │ screen region│  │ screen region   │     │  │
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

### Stage 4 — TUI Desktop (DESK)

> Renamed from "compositor".  The old `app-compositor.f` had its own
> event loop — a copy of the shell's loop.  That was wrong.  The shell
> is the browser engine; the DESK is a regular APP-DESC app that
> happens to manage sub-apps, just as a browser tab manager is JS
> running inside the engine, not a second engine.

**Goal**: Multiple apps share the screen, each in its own tiled
region with its own UIDL context.  An always-on taskbar occupies
the last row.  All sizes are dynamic — derived from
`ASHELL-REGION` at runtime, recomputed on every resize.

**Key architectural rule**: The DESK has **no event loop**.
It is an APP-DESC.  The shell calls its 5 callbacks.
`YIELD?` is the shell's concern.  `KEY-POLL` is the shell's concern.
The DESK never touches either.

#### How it works

The DESK is launched with `ASHELL-RUN` like any other app:

```forth
DESK-DESC-SETUP
DESK-DESC ASHELL-RUN      \ blocks until ASHELL-QUIT
```

The shell's single event loop calls the DESK's callbacks:

| Shell calls | DESK does |
|-------------|----------|
| `DESK.INIT-XT` | Allocate slot list, paint taskbar template |
| `DESK.EVENT-XT ( ev -- flag )` | Intercept desk shortcuts (Alt+Tab, Alt+W, …); if not a shortcut, ctx-switch to focused sub-app, call its EVENT-XT, ctx-switch back; return consumed flag |
| `DESK.TICK-XT` | Walk all live slots, ctx-switch to each, call its TICK-XT, ctx-switch back |
| `DESK.PAINT-XT` | Walk visible slots, ctx-switch + RGN-USE each, call UTUI-PAINT + PAINT-XT, ctx-switch back; draw dividers; draw taskbar |
| `DESK.SHUTDOWN-XT` | Walk all slots, call each sub-app's SHUTDOWN-XT, free UIDL contexts, free slot list |

The shell handles everything else: terminal init/shutdown, `YIELD?`,
`KEY-POLL`, `SCR-FLUSH`, dirty-flag gating, resize (`_ASHELL-ON-RESIZE`
calls `UTUI-RELAYOUT` — the DESK's own EVENT-XT can listen for a
resize pseudo-event or re-tile in PAINT-XT when dimensions change).

#### No duplicate loop

The old `app-compositor.f` had `_COMP-LOOP` which was a near-identical
copy of `_ASHELL-LOOP`: poll → dispatch → tick → paint → flush → yield.
This is eliminated.  There is exactly **one** loop: the shell's.

Comparison:

```
OLD (wrong):                         NEW (correct):

app-shell.f  _ASHELL-LOOP            app-shell.f  _ASHELL-LOOP
  KEY-POLL                             KEY-POLL
  app EVENT-XT                         app EVENT-XT  ← DESK's
  UTUI dispatch                        UTUI dispatch ← DESK's doc
  tick                                 tick          ← DESK's
  paint if dirty                       paint if dirty← DESK's
  SCR-FLUSH                            SCR-FLUSH
  YIELD?                               YIELD?

app-compositor.f  _COMP-LOOP         (deleted — no second loop)
  KEY-POLL
  compositor shortcuts
  route to slot
  tick all
  paint all
  SCR-FLUSH
  YIELD?
```

#### Design decisions

1. **Divider lines** — 1-cell dividers between tiled panes.
2. **Auto-tiling** — grid dimensions chosen automatically by visible
   count and screen aspect; `Alt+L` toggles V/H preference.
3. **App launcher** — overlay (Stage 3 dialog system).
4. **Full-frame override** — other visible apps hidden from paint but
   still ticked; they are NOT minimized.
5. **All-Task-0 execution** — every sub-app callback runs
   cooperatively inside the DESK's own callbacks, which themselves
   run inside the shell's single Task 0 loop.
6. **No artificial slot limit** — heap-allocated linked list.
   Practical limits: memory (~97 KiB per UIDL context) and usable
   screen space.

#### Screen Budget

The DESK receives its region from `ASHELL-REGION`.  It reserves
the last row for the taskbar → usable area is
`region-W × (region-H - 1)` for app tiles.

Nothing is hardcoded to 80×24.

#### Taskbar (last row, always on)

```
[1:Pad*] [2:Explore~] [3:--]  ...            HH:MM
```

- One label per live slot.  Scrolls if labels overflow width.
- `*` = focused, `~` = minimized, no suffix = running.
- Right-aligned: optional clock / status.
- Painted by `DESK.PAINT-XT` via direct `DRW-*` calls.

#### Dynamic Tiling Algorithm

Given **N** visible (non-minimized) sub-apps and usable area
**W × H** (from `ASHELL-REGION`, minus taskbar row):

1. **Pick grid dimensions `(rows, cols)`.**
   Choose the smallest grid where `rows × cols ≥ N`:
   - Default preference `_DESK-VH = 0` (vertical-first):
     `cols = ceil(sqrt(N))`, `rows = ceil(N / cols)`.
   - Preference `_DESK-VH = 1` (horizontal-first):
     `rows = ceil(sqrt(N))`, `cols = ceil(N / rows)`.

2. **Compute base tile size.**
   Account for 1-cell dividers between adjacent tiles:
   - `tile-w = (W - (cols - 1)) / cols`
   - `tile-h = (H - (rows - 1)) / rows`
   - Remainder goes to the last column / row.

3. **Assign regions.**
   Walk visible slots left-to-right, top-to-bottom.  Each gets
   `RGN-NEW ( row col h w )`.  Last grid row may be partial.

4. **Draw dividers.**
   `DRW-VLINE` / `DRW-HLINE` with box-drawing characters.

**Example** — 4 apps on 80×24 (usable 80×23):
- Grid: 2×2. tile-w = 39, tile-h = 11.
- Regions: (0,0,11,39), (0,40,11,40), (12,0,11,39), (12,40,11,40).

#### Minimize & Full-Frame

- **Minimize**: sub-app stays alive, not painted, no key events
  routed, ticks still called.  Taskbar shows `~`.
- **Full-frame** (`Alt+F`): focused sub-app gets the full usable
  area; others hidden from paint, still ticked.

#### Slot Management

Heap-allocated via `ALLOCATE`.  Prefix: `_DESK-` (was `_COMP-`).

```forth
\ Per-slot struct (7 cells = 56 bytes)
 0 CONSTANT _SL-O-DESC        \ sub-app APP-DESC pointer
 8 CONSTANT _SL-O-RGN         \ sub-region (0 if minimized)
16 CONSTANT _SL-O-STATE       \ 0=empty 1=running 2=min 3=focused
24 CONSTANT _SL-O-UCTX        \ UIDL context buffer (~97 KiB)
32 CONSTANT _SL-O-HAS-UIDL    \ flag
40 CONSTANT _SL-O-NEXT        \ → next slot or 0
48 CONSTANT _SL-O-ID          \ unique monotonic ID
56 CONSTANT _SL-SZ
```

Linked list `_DESK-HEAD`.  `DESK-LAUNCH ( desc -- id )` allocates
and links.  `DESK-CLOSE ( id -- )` calls sub-app SHUTDOWN-XT,
unlinks, frees.

#### Keyboard Shortcuts (DESK-intercepted in EVENT-XT)

| Key | Action |
|-----|--------|
| `Alt+<digit>` | Focus slot with that ID (1-9) |
| `Alt+Tab` | Cycle focus forward through live slots |
| `Alt+M` | Minimize focused sub-app |
| `Alt+R` | Restore most-recently-minimized |
| `Alt+F` | Toggle full-frame for focused sub-app |
| `Alt+L` | Toggle V/H tiling preference |
| `Alt+W` | Close focused sub-app (shutdown) |
| `Alt+N` | Open app launcher overlay |

These are checked in `_DESK-EVENT-CB` **before** forwarding to the
focused sub-app.  If a shortcut matches, the DESK handles it
internally and returns `consumed = true` to the shell.

#### UIDL Multi-Instance (Context Swap)

Each sub-app with a UIDL document gets a context buffer (~97 KiB)
holding all UIDL/UTUI scalar globals + pool arrays.
`UCTX-SAVE` / `UCTX-RESTORE` copy between live globals and the
buffer.  `_DESK-CTX-SWITCH ( slot -- )` saves the outgoing context
and restores the incoming one.

Since everything runs in Task 0 (the shell's single loop) there
are no races.  Memory cost: ~97 KiB × N sub-apps.

#### App Descriptor (DESK itself)

The DESK is just an APP-DESC:

```forth
CREATE DESK-DESC  APP-DESC ALLOT

: DESK-DESC-SETUP  ( -- )
    DESK-DESC APP-DESC-INIT
    ['] _DESK-INIT-CB      DESK-DESC APP.INIT-XT !
    ['] _DESK-EVENT-CB     DESK-DESC APP.EVENT-XT !
    ['] _DESK-TICK-CB      DESK-DESC APP.TICK-XT !
    ['] _DESK-PAINT-CB     DESK-DESC APP.PAINT-XT !
    ['] _DESK-SHUTDOWN-CB  DESK-DESC APP.SHUTDOWN-XT !
    S" KDOS Desktop"       DESK-DESC APP.TITLE-A !
                           DESK-DESC APP.TITLE-U !
    \ No UIDL doc for the DESK itself (it manages sub-app docs)
    0 DESK-DESC APP.UIDL-A ! ;
```

The 5 callbacks:

```forth
: _DESK-INIT-CB  ( -- )
    0 _DESK-HEAD !
    1 _DESK-NEXT-ID !
    0 _DESK-VH !
    0 _DESK-FULLFRAME ! ;

: _DESK-EVENT-CB  ( ev -- flag )
    DUP _DESK-SHORTCUT? IF DROP -1 EXIT THEN
    \ Forward to focused sub-app
    _DESK-FOCUS-SLOT @ ?DUP IF
        DUP _DESK-CTX-SWITCH
        _SL-O-DESC + @ APP.EVENT-XT @ ?DUP IF
            SWAP EXECUTE
        ELSE DROP 0 THEN
        _DESK-CTX-SAVE
    ELSE DROP 0 THEN ;

: _DESK-TICK-CB  ( -- )
    \ Tick ALL live sub-apps (even minimized)
    _DESK-HEAD @ BEGIN ?DUP WHILE
        DUP _DESK-CTX-SWITCH
        DUP _SL-O-DESC + @ APP.TICK-XT @ ?DUP IF EXECUTE THEN
        _DESK-CTX-SAVE
        _SL-O-NEXT + @
    REPEAT ;

: _DESK-PAINT-CB  ( -- )
    \ Paint visible sub-apps into their regions
    _DESK-HEAD @ BEGIN ?DUP WHILE
        DUP _SL-O-STATE + @ _ST-RUNNING >= IF
            DUP _DESK-CTX-SWITCH
            DUP _SL-O-RGN + @ RGN-USE
            DUP _SL-O-HAS-UIDL + @ IF UTUI-PAINT THEN
            DUP _SL-O-DESC + @ APP.PAINT-XT @ ?DUP IF EXECUTE THEN
            _DESK-CTX-SAVE
        THEN
        _SL-O-NEXT + @
    REPEAT
    _DESK-PAINT-DIVIDERS
    _DESK-PAINT-TASKBAR ;

: _DESK-SHUTDOWN-CB  ( -- )
    BEGIN _DESK-HEAD @ ?DUP WHILE
        DUP _SL-O-ID + @ DESK-CLOSE
    REPEAT ;
```

#### Resize Handling

The shell's `_ASHELL-ON-RESIZE` rebuilds the root region and calls
`UTUI-RELAYOUT`.  Since the DESK has no UIDL document, the shell's
resize is a no-op for the DESK's own layout.  The DESK detects the
new dimensions in its next `PAINT-XT` call (or via a resize
pseudo-event forwarded by the shell) and calls `DESK-RELAYOUT`
which recomputes the grid, reassigns sub-regions, and for each
UIDL-bearing sub-app ctx-switches and calls `UTUI-RELAYOUT`.

#### What replaces `app-compositor.f`

`tui/desk.f` — Prefix: `DESK-` / `_DESK-`.  Requires: `app-desc.f`
(Phase 0), `app-shell.f` (for `ASHELL-REGION`, `ASHELL-QUIT`).
**No** `KEY-POLL`, **no** `YIELD?`, **no** `SCR-FLUSH`, **no**
`BEGIN...REPEAT` loop.

**Files**: `tui/desk.f` (slot list, tiling, taskbar, context swap,
5 APP-DESC callbacks).  The old `tui/app-compositor.f` is retired.

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
- **No artificial app limit.** DESK uses heap-allocated linked list.
  Practical limits: memory and usable tile size.
- **One event loop.** The shell owns the only `BEGIN...REPEAT` loop.
  The DESK and all apps are passive callbacks — no app ever calls
  `KEY-POLL`, `SCR-FLUSH`, or `YIELD?`.

---

## Priority

**Stage 1** ✅ — App lifecycle protocol delivered.
**Stage 2** ✅ — Style inheritance for widgets delivered.
**Stage 3** ✅ — Overlays (prompts, menus, tooltips) delivered.
**Stage 4** — TUI Desktop / DESK (next).
**Stage 5** — Shared services (clipboard, mounted VFS, IPC, config).

Each stage is independently valuable and shippable.
