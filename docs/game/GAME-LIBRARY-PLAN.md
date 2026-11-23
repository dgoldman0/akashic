# Repairing the game library and building a first game on it — plan, 2026-11-22

Status: Proposed, 2026-11-22. Nothing in it is built. The game is chosen
(decision 1) before any stage starts, and each stage is approved on its own.
The work runs alongside the first release and stays off its critical path.
Decisions lists what is open.

Related: the library's evaluation and the test-health catalogue of 2026-11-22
(`~/.cache/fantasy-engine/notes/game-library-evaluation-20261122.md`,
`test-health-catalogue-20261122.md`); [applet-host.md](../tui/applet-host.md);
[app-desc.md](../tui/app-desc.md); [uidl-tui.md](../tui/uidl-tui.md);
[text-grid.md](../tui/widgets/text-grid.md);
[GRID-CELLS-ADMISSION.md](../rich-terminal/GRID-CELLS-ADMISSION.md);
[FRAMES-FOLLOW-CHANGE.md](../rich-terminal/FRAMES-FOLLOW-CHANGE.md);
[places.md](../utils/fs/places.md);
[vfs-replace.md](../utils/fs/vfs-replace.md); the release plan's Parts 1d, 5,
6 and 7 (`fantasy-engine/dev/PLAN.md`).

## Summary

The game library is 28 Forth files and 7,782 lines: twelve files of game logic
under `akashic/game` (3,484 lines) and sixteen of terminal code under
`akashic/tui/game` (4,298 lines), nearly all written between 2026-03-24 and
2026-03-26. Its own documents, its suites and the refactor policy name it, and
no profile, applet or other module loads it. The evaluation of 2026-11-22
recommended retiring it. The project chose to repair it and to build an
original game on it, as work that runs beside the release.

Reading all 28 files and running the logic half on the emulator confirms the
evaluation's seven faults, with the corrections in 1.5, and finds others,
three of which change the repair. The fog of war's shadowcast lets sight pass
behind walls, and a single wall or the map's edge can black out an open
octant. A behaviour tree with one composite inside another runs the wrong
children, and freeing it frees two blocks twice. A\* spends time in proportion
to the map's area before it expands a node, and its per-search blocks, freed
and taken again at mixed sizes, grew the extended-memory heap by 32 KiB a
round of searches over two maps. `ECS-FREE` and `SYSRUN-FREE`, which no suite
calls, consume their caller's stack cells as the evaluation predicted.

The plan repairs the logic half in place and replaces the terminal half.
Fifteen of the terminal half's sixteen files paint screen cells directly, keep
process-wide state or duplicate a canonical widget or UIDL facility, so the
plan retires them; a board builder over the canonical text grid and a text map
reader take their place. Each game is an ordinary applet with its own
descriptor, as Grid is. The repairs cost 18 to 25.5 agent hours and the
recommended game, Folio Watch, 8 to 12 more. The six stages, which add the
game's skeleton, its measurement and its configuration entry, come to 27 to 39
hours, with an optional stage of 3 to 5 hours that teaches the text grid to
follow change.

On the device the logic half is cheap and the screen is the cost. In the
emulator's cycles, by Appendix A's measured calls and the estimates of 3.1,
one turn's light, pathing and decisions for six creatures stay under a million
cycles, 10 ms at 100 MHz, while rebuilding, validating and drawing a 24 by 12
board as a canonical text grid takes 6.9 million, 69 ms, before the rich frame
is built. Every concept here is therefore turn-based, and decision 3 sets the
turn's budget.

## Method and inputs

The plan rests on reading the evaluation and the catalogue, the 28 files, the
six converted suites on Akashic branch `test-health-3` (a021760b, whose
7d20197c builds their disks from the REQUIRE closure and fixes
`game-canvas.f`'s comment), and the layers a repaired library sits on: the
applet host and descriptors, UIDL-TUI, the canonical text grid, list, status
and dialog widgets, the rich families the Desktop selects, places, checked
replacement and KDOS's allocation words.

Four probe scripts ran on the emulator, six runs in all, two of them repeated
after fixing a mistake in the probe itself. They ran from a worktree of
Akashic main 68cb727f with MegaPad main d8016c43, each run 2 to 4 seconds and
under 90 MiB, with their scratch images in `/dev/shm`. The game files they
load are the same on main and on `test-health-3`. The scripts and their output
are kept in `~/.cache/fantasy-engine/notes/` as `game-plan-probe-20261122`,
`game-plan-board-probe-20261122`, `game-plan-board24-probe-20261122` and
`game-plan-rows-probe-20261122`, each a `.py` with its `.txt`. Appendix A
lists every figure.

Cycle figures are differences of `PERF-CYCLES`, the emulator's cycle model,
and include the 527 cycles a measurement costs. Device time divides them by
10^8, the processor time of the 100 MHz SoC, as the project's evidence notes
do. The RTL's realized cycles per instruction may differ, and its string
engine moves a byte in four cycles.

## 1. What the library holds today

### 1.1 The logic half

| Module | Lines | What it does | State |
|---|---:|---|---|
| `game/ecs.f` | 306 | Entities with generation counters, component pools in bitfield-indexed arrays, iteration | Sound core. `ECS-FREE` uses `FREE DROP` six times. `ECS-EACH` and `ECS-EACH2` keep their callback and ECS in variables, so iteration inside a callback breaks the outer loop. `ECS-ATTACH` hands a new entity the bytes a killed one left. Sixteen components at most. |
| `game/components.f` | 125 | Field offsets of eight common components | Sound |
| `game/systems.f` | 275 | A runner that ticks systems in priority order; velocity, timer and cull systems | `SYSRUN-FREE` uses `FREE DROP` twice. The component bindings `SYS-C-POS` and its kin are process-wide, and `steer.f` and `tile-physics.f` read them. Sixteen systems at most; enable and disable take an index that the insertion sort moves. |
| `game/2d/collide.f` | 154 | Collision map, point-in-rectangle and box overlap | Sound |
| `game/2d/tile-physics.f` | 219 | One-tile moves with wall sliding, gravity, one-way tiles and a collision callback | Correct for unit steps. A move of several tiles tests only its destination. Move state sits in variables across the collision callback, so a callback that moves another entity corrupts the move. |
| `game/2d/pathfind.f` | 408 | A\* with a node budget, four- or eight-connected | Finds paths; cost, memory and heuristic faults in 1.2 |
| `game/2d/steer.f` | 192 | Seek, flee, wander, follow a path, patrol | Each behaviour steps one tile toward or away from its target. The AI component binding and the wander generator are process-wide. |
| `game/2d/camera.f` | 261 | A viewport that follows a target with smoothing, shake and clamping | Sound, except that each `CAM-X` or `CAM-Y` query advances the shake generator and a shake of amplitude zero divides by zero |
| `game/2d/fog.f` | 334 | Per-tile visibility with memory, by shadowcasting | Wrong (1.2) |
| `game/ai/fsm.f` | 281 | States with enter, tick and leave callbacks; guarded transitions | Correct for one machine per entity. `FSM-START` gives the first state's enter callback 0 as its entity and 0 as its ECS. Sixteen states and 32 transitions at most, and each machine holds its definition and its current state together. |
| `game/ai/btree.f` | 397 | Action, condition, sequence, selector, parallel, invert, repeat and cooldown nodes | Wrong for nested trees (1.2) |
| `game/save.f` | 532 | Key-value saves and loads as CBOR | Faults in 1.3 |

The ECS, the collision map, the camera, the components and the state machine's
transition logic stay, with the fixes the table names; the fog, the behaviour
trees, A\* and the saves need the larger repairs of section 2. The six suites
hold 472 checks, all passing on `test-health-3`.

### 1.2 What the probes found

**The fog of war.** `FOG-REVEAL` scans each octant row by row from low slope
to high. When an open tile follows a blocked run it recurses with a start
slope below its end slope, and the recursive call returns at once; when a row
ends on an open tile, the next row is scanned over the whole original slope
range. A wall therefore casts a shadow only when it is the last tile of its
row, and then the rest of the octant goes dark. The map's edge counts as a
wall, so an octant that reaches the edge ends there. On a 10×10 map with a
wall across (3,3) to (5,3), a reveal from (1,3) with radius 8 marked (6,3) and
(8,3) visible behind it. With one wall at (2,2), a reveal from (0,0) left
(5,1), (3,0) and (0,5) unseen, though nothing stands between them and the
viewer; on the same map without the wall, (3,0) and (5,1) were visible. The
phase 7 suite's check `fog:behind-wall-blocked` asserts a constant true, which
is how its 64 checks pass. The blocking test is an execution token that
receives only a position, so the code it runs must find its map through a
global, and `FOG-HIDE-ALL` walks the whole map, 221,401 cycles on 40×20.

**Behaviour trees.** `BT-RUN` calls itself on each child and keeps its loop
index, child count and child array in variables, so a composite inside a
composite overwrites its parent's loop. A sequence of a selector and two
counting actions returned success without running either action, and by the
code a decorator nested in a decorator loses its counter the same way.
`BT-FREE` has the same shape: freeing that tree made six `FREE` calls, two on
blocks already freed, and left four blocks allocated. The suite builds only
flat trees. `REPEAT` and `COOLDOWN` also keep their counters in the node
itself, so one tree serves only one entity.

**A\*.** Each search allocates five blocks, fills the g-score and parent
arrays across the whole map, and keeps its open set in an unsorted array that
it scans for every pop. A five-step path cost 191,066 cycles on a 40×20 map
and 611,052 on a 64×64 one, nearly all of it the fills; a 54-step detour
around a wall on 40×20 cost 6.12 million, and a 79-step path across an open
64×64 map 17.66 million, 0.18 s at 100 MHz. The open set holds only as many
entries as the node budget and drops neighbours once it is full, so a search
that would finish within its budget can still fail, and a failed search and a
spent budget both return `0 0`. With diagonal moves on, the Manhattan
heuristic overestimates, so a path can be longer than the shortest, and a
diagonal step passes between two walls that meet at a corner: the probe got a
two-tile path through such a corner. The blocks also fragment memory. KDOS
sends every `ALLOCATE` to the extended-memory heap when there is one, and that
heap never merges holes, so searches alternating between a 40×20 and a 64×64
map raised `XMEM-HERE` by 32,784 bytes a round, 655,680 bytes over 20 rounds.

**Teardown.** Running the code confirms the evaluation's first fault. With
seven cells below its argument, `ECS-FREE` on an ECS with one component left
one of them and called `FREE` six times on addresses read from the wrong
cells; `SYSRUN-FREE` consumed two cells of three.

### 1.3 Saves and maps

`save.f` writes its entries into a 16 KiB buffer without a bound check, so a
large save overruns it. It encodes into one 16 KiB extended-memory buffer
allotted for good at load time, writes the file before it checks whether the
encoding fitted, stores lengths in 16 bits and encodes negative integers as
unsigned CBOR. It opens files by `EVALUATE`ing `OPEN name` and
`64 5 MKFILE name`, KDOS's MP64FS words, so every save is a 64-sector file on
the boot disk, outside every place on the user volume. All load contexts share
a single 16 KiB read buffer.

`tui/game/map-loader.f` reads maps into a 16 KiB buffer in the dictionary,
which a single-layer 45×45 map at eight bytes a tile already exceeds. It
ignores the length of each layer and collision blob and reads past a short
one, names spawns and triggers with a single digit, so ten of each at most,
and resolves tiles through the atlas into screen cells as it loads.

### 1.4 The terminal half

The terminal half predates the applet host, the rich terminal and places. Its
widgets paint cells through `SCR-SET` and its own draw words, its loop and
input tables are process-wide, and its applet builder wraps `APP-DESC` in a
layout of its own. The rich-terminal vertical requires the same ordinary
applet sources, UIDL documents, mounted widgets and draw lifecycle for CELL
and rich output, with no applet-specific scene or direct terminal API, so
repairing these files means replacing them.

| File | Lines | What it does | Plan |
|---|---:|---|---|
| `loop.f` | 311 | Fixed-timestep loop, blocking `GAME-RUN`, eight-slot deferred queue that drops the ninth | Delete: Desk ticks its applets, and the games are turn-based (decision 6) |
| `scene.f` | 189 | Process-wide scene stack eight deep | Delete: UIDL documents, overlays and dialogs |
| `input.f` | 257 | Process-wide table of 64 actions with four keys each | Delete: UIDL actions and shortcuts, keys through `APP.EVENT-XT` |
| `game-applet.f` | 195 | An `APP-DESC` extension with its own callbacks and a process-wide current descriptor | Delete: each game fills `APP-DESC` and `COMP-DESC` itself (repair 10) |
| `game-view.f` | 224 | Widget with its own timing loop, type 17, the prompt's number | Delete |
| `game-canvas.f` | 203 | Braille canvas game view, type 18, Agent sign-in's number; reads the canvas's fields at raw offsets 48 and 56 | Delete: the canvas has no rich projection |
| `atlas.f` | 133 | Tile id to packed screen cell | Fold into the board builder's glyph table |
| `tilemap.f` | 225 | Map of packed screen cells, blitted with `SCR-SET` | Delete |
| `sprite.f` | 394 | Sprites and a pool drawn with `SCR-SET`; its guard section names an undefined `_spool-guard` | Delete: entities in the ECS, glyphs on the board |
| `world-render.f` | 227 | Draws layers and sprites; reads the pool's count at +16 and its array at +0, where `sprite.f` keeps the array and the maximum, and each sprite's flags at +88, past its 64 bytes | Delete |
| `fog-render.f` | 89 | Dims or blanks cells after the world is drawn | Delete: unseen tiles become unavailable items of the board |
| `map-loader.f` | 463 | CBOR map loader (1.3) | Rewrite as `game/map.f` over the VFS (repair 8) |
| `widgets/hud.f` | 345 | Bars and text, type 19, Agent settings' number | Delete: UIDL status labels, published as status fields |
| `widgets/dialog-box.f` | 381 | Dialog with a typewriter reveal, type 20 | Delete: the canonical dialog |
| `widgets/inventory.f` | 386 | Grid inventory, type 22 | Delete: the canonical list |
| `widgets/minimap.f` | 276 | Canvas minimap, type 21 | Delete: canvas output is CELL only |

The viewport moves to the logic half's `camera.f`, which already tracks one:
the board builder shows the part of a larger map that the camera selects.

### 1.5 Corrections to the evaluation

- The node budget bounds A\*'s expansions; each search also costs time in
  proportion to the map's area and to the square of the open set.
- `fog.f`, `fsm.f`, `btree.f` and `fog-render.f` have no document, and
  `save.md` sits under `docs/tui/game` although `save.f` lives in `game/`.
- Type numbers already overlap by accepted practice. Since fd761ec4 a partial
  drawer declines a widget that only carries its kind's number, and the
  panels of Observatory (29), Daybook, Worlds and Library (30) reuse
  canonical numbers. The game widgets' overlap remains a hazard for any other
  type dispatch; deleting them ends it.
- Three of the twelve logic modules, the fog, the behaviour trees and A\*,
  give wrong or costly results in ordinary use, so "largely sound" holds for
  the other nine.

## 2. Repairs

The repairs are ranked by value for cost and by dependency. Each estimate
includes its tests and one reading of the change in context. Each repair is
written to KDOS's allocation rules: `FREE` returns nothing, so a `FREE` stands
alone; a size measured as zero skips `ALLOCATE`, since `0 ALLOCATE` fails;
anything that runs more than once makes its arena with `ARENA-NEW-AT` in
storage of its own, since `ARENA-NEW` builds its descriptor in the dictionary
for good; tables made with `CREATE` are read as bytes or carved with
`7 + -8 AND`, since `CREATE` leaves `HERE` unaligned; and anything allocated
and freed repeatedly is allocated once and reused, or keeps one block size,
since the extended-memory heap never merges holes.

| # | Repair | Hours |
|---:|---|---:|
| 1 | Teardown: the eight `FREE DROP`s, with stack-depth checks | 0.5 |
| 2 | Behaviour trees: per-call state, nested trees, `BT-FREE`, one tree for many entities | 1.5–2 |
| 3 | Fog of war: a correct shadowcast, a blocking test with context, hiding in proportion to the last reveal | 2–3 |
| 4 | Callbacks that re-enter: ECS iteration, systems, tile physics, state machines; `ECS-ATTACH` clearing its bytes | 1–1.5 |
| 5 | A\*: a reusable search, a heap, honest results, an admissible heuristic, a corner rule, a distance field, terrain costs | 3–4 |
| 6 | Per-instance state and capacities from need | 2–3 |
| 7 | Saves through the VFS on the user volume | 1.5–2 |
| 8 | Maps through the VFS, as text | 1–1.5 |
| 9 | The rich-terminal path: a board builder over the canonical text grid | 2.5–3.5 |
| 10 | The game applet through an ordinary descriptor | 1.5–2 |
| 11 | Retiring the terminal half | 0.5–1 |
| 12 | Widget types | 0 |
| 13 | Tests through the test tool | 0.5 |
| 14 | Smaller fixes and missing documents | 0.5–1 |
| | **All** | **18–25.5** |

The evaluation's 9 to 17 hours for its steps 1 to 7 predate the faults of 1.2
and the board builder. Optional work outside the total: a widget-kind
registration word in the core (0.5 to 1 hour, decision 8) and a text grid that
follows change (3 to 5 hours, decision 3).

**1. Teardown.** `ECS-FREE`, its component helper and `SYSRUN-FREE` lose the
`DROP` after each `FREE`. The suites gain a teardown check that pushes
sentinels, frees, and compares the depth and the sentinels, and a logging
`FREE`, loaded before the module as in the probe, that counts the frees and
finds any repeated address.

**2. Behaviour trees.** `BT-RUN` and `BT-FREE` keep their loop state on the
data and return stacks, so a call at any depth leaves its caller's iteration
intact. Each node that needs per-entity state, `REPEAT`'s count and
`COOLDOWN`'s countdown and last result, gets a slot index when the tree is
built; `BT-STATE-CELLS ( root -- n )` sizes a block from the tree, and each
entity keeps its block in a component, so
`BT-RUN ( node state eid ecs -- status )` serves any number of entities from
one tree. Tests run nested shapes (a selector inside a sequence inside a
selector, a repeat over a cooldown, a parallel of composites) against traces a
host model computes, run one tree for two entities with different counts, and
free each tree with the logging `FREE`: every node and child array exactly
once.

**3. Fog of war.** `FOG-REVEAL` becomes symmetric shadowcasting with exact
rational slopes: a tile is visible from the viewer exactly when the viewer is
visible from it, walls cast their full shadows, and the map's edge ends sight
without darkening the tiles inside it. The scan keeps its rows on an explicit
stack in the descriptor, sized from the radius, and reads only the descriptor
and its arguments. The descriptor names its blocking source: a collision map
read directly, the fast path, or a token with a context cell. Each reveal
records the tiles it lit, so hiding them costs the size of the last reveal;
several sources, such as lamps or relays, reveal into one layer between hides.
A host oracle implementing the same definition checks fixed and seeded random
maps, symmetry and the edges, and real checks replace the suite's empty one.

**4. Callbacks that re-enter.** `ECS-EACH` and `ECS-EACH2` keep their ECS,
token and second descriptor on the return stack; the systems receive their
step on the stack; tile physics passes its mover and position to the collision
callback and keeps them across it; the state machine keeps its loop and
transition on the stacks. `ECS-ATTACH` zeroes the component it attaches. Tests
nest an `ECS-EACH` inside another, move a second entity from a collision
callback, and tick a machine from another machine's tick.

**5. A\*.** `ASTAR-NEW ( cmap -- search )` allocates one search's arrays once
for its map. A generation stamp on every tile marks which g-score and parent
belong to the current search, so a new search begins by advancing the
generation, whatever the map's size. The open set is a binary heap that
doubles when it fills, the budget counts expansions, and `ASTAR-RUN` returns a
status that tells a found path, a proven absence and a spent budget apart,
with the path in the search's own buffer, grown from need. Diagonal searches
use the octile heuristic, diagonal steps between two blocked neighbours are
refused by default, and ties break toward the larger g, which shortens
searches across open ground. `ASTAR-FIELD ( sources count search -- status )`
fills a distance field from several sources in one breadth-first pass, so any
number of creatures chasing the same targets share one pass a turn. A cost
table of 256 entries, indexed by the collision value, gives terrain its cost;
the default keeps today's meaning, zero open and every other value solid.
Tests compare lengths with a host Dijkstra oracle on seeded maps, check that
`XMEM-HERE` stays flat over 20 alternating rounds, and record cycles against
Appendix A.

**6. Per-instance state and capacities.** The runner holds the component ids
its built-in systems use; steering takes a context with its AI component and a
seeded generator; tile physics holds its position component. The state machine
splits into a shared definition and a per-entity current state kept in the
entity's AI component, and `FSM-START` takes the entity and ECS that its enter
callback receives, where today it passes zeros. Components, systems, states
and transitions grow as their creator registers them, and the runner hands out
a handle for each system it adds. Variables that only a leaf word uses between
its entry and its exit, in `collide.f` and the encoders, stay, as they do
across the TUI library. Tests run two ECS instances with different bindings in
one runner pass and one definition for two entities.

**7. Saves.** `save.f` keeps its key-value interface and changes underneath. A
save context's entry buffer grows from need; the encoding buffer is sized from
the entries, whose CBOR form has a computable bound; the file goes through
checked replacement in the applet's home (`PLACE-VREPL!`, `VREPL-REPLACE`), as
Grid saves, on whichever volume holds the home, ext4 in the shipping form. A
load reads the file's size first, allocates exactly that, parses with a cursor
of its own (`CBOR-SAVE` and `CBOR-RESTORE`); negative integers go out through
`CBOR-NINT` and come back through `CBOR-NEXT-NINT`. Every call answers a
status. The `EVALUATE`d commands, the 64-sector files and the shared buffers
go. A save costs 1.25 to 1.35 s of
processor time for 2 to 16 KiB on the user volume
(`local_testing/evidence/user-volume-writer-profile-20261119.md`), so games
save at explicit points, such as a night's end or the player's Save. Tests
round-trip saves on MP64FS and on an ext4 fixture and refuse truncated,
corrupt and mistyped files.

**8. Maps.** `game/map.f` reads a map as UTF-8 text through the VFS, from the
applet's origin for shipped maps or its home for a player's own: a header of
`key: value` lines, a legend that gives each glyph a tile kind, a collision
value and whether it blocks sight, and rows of exactly the declared width,
with spawn marks among them. The reader checks the size before reading, reads
exactly that, validates the whole text as Grid validates CSV, and returns a
collision map, a kind layer and a spawn list sized from the text. Text maps
can be written in Pad and read in the Workshop (decision 4).

**9. The board.** `tui/game/board.f` builds a canonical text grid
(`USCOL-F-TEXT-GRID`, mounted with `TGRID-NEW` into a UIDL region element)
from the game's state, following Grid's pattern of two caller-owned banks, an
inactive one rebuilt and published only after `TGRID-BIND` validates it. Each
visible tile is one item. A caller token `( x y ctx -- text-a text-u state )`
supplies the glyph and state; the board marks the player's tile `CURRENT`,
tiles out of sight `UNAVAILABLE`, which draws dim and refuses selection, and
the cursor as the primary item. The camera chooses the visible window, the
banks are sized from the region in measure mode and resized when the region
changes. A pointer press or a rich `PLACE` selects a tile through `TGRID`'s
ordinary selection, and the board passes the game that tile's map position.
CELL output is `TGRID`'s own draw, so it stays complete. The status, log and
dialogs are UIDL status labels, the canonical list and the canonical dialog,
which the Desktop's rich families already publish. Tests check the model's
items against the map, the CELL draw against an expected screen, and, in a
headless Desk run, that the board goes out as `GRID_CELLS` and that an
acknowledged `PLACE` selects a tile, as `run_headless_grid_acceptance.py`
checks Grid.

**10. The applet.** A game is an ordinary applet: its entry word fills
`APP-DESC` and `COMP-DESC` with a component id, version and instance size from
`CMP-FIELD:` and `CMP-CELL:` layouts, binds instance-relative state in
`APP.ACTIVATE-XT`, asks for a home with `PLACES-NEED-HOME`, negotiates close
with `APP.REQUEST-CLOSE-XT` while a night is unsaved, and names its UIDL file.
The host region comes from the UIDL region element and its relayout, as Grid's
does. Until Part 5a lands, a profile queues the game with
`DESK-QUEUE-BUILTIN`; afterwards the Practice declares it, so Desk's code
never names it (Part 5e). Since the simulator refuses machine-code packages,
the game ships as source and tokens on the system volume, as the built-ins do.

**11. Retiring the terminal half.** An annotated `archive/` tag keeps the
fifteen files and their documents reachable, and the files, documents and
suite checks are removed from the tree. The refactor policy's entries for
`tui/game/` in `local_testing/refactor_architecture.json`, the inventory
test's assertions on `tui/game/game-applet.f` and the architecture baseline's
deferral of the game direction change with them.

**12. Widget types.** After repair 11 the library defines no widget type, and
the board mounts the canonical `TGRID`. A game that needs a widget kind of its
own later takes its number from a registration word (decision 8).

**13. Tests through the test tool.** The six suites converted on
`test-health-3` land first. Each repair adds its checks to its module's suite
or a new unit; the game adds a headless unit that replays scripted turns to an
expected state, and a journey of Desk with the game. Each stage ends with
`python3 -m fantasy_engine.testing run --recorded` and patterns for the units
its changes reach.

**14. Smaller fixes and documents.** The camera computes its shake offset once
a tick and refuses a zero amplitude; steering's document says that each
behaviour takes one step; the fog, state machine and behaviour tree modules
get the documents they lack, and `save.md` moves beside `save.f`.

## 3. Game concepts

The three designs below are the project's own. A web search on 2026-11-22
found games where light holds creatures back, among them
[Lanternbound](https://csaf.itch.io/lanternbound) and [Brought to
Light](https://gdiac.cis.cornell.edu/gallery/2016/BroughtToLight/manual.pdf),
and games of charting an island, such as [Maps of
Misterra](https://en.boardgamearena.com/gamepanel?game=mapsofmisterra), and
nothing with these premises. A fourth idea, a survey party racing a rising
tide across an island, came too close to existing island games, and the plan
drops it. All three designs are turn-based: a turn runs when the player acts,
and Desk paints the one frame that follows, as frames follow change.

The per-turn tables combine Appendix A's measurements with estimates for the
parts still unmeasured, chiefly the rich frame. As a reference for that frame,
a typed letter's frame builds in 2.05 million steps in a typing burst and in
4.0 to 6.5 million when it stands alone
(`local_testing/evidence/frames-follow-change-part10-20261101.md`).

### 3.1 Folio Watch (working name)

At night an archive's reading rooms lie dark, and inkmites, small creatures
that shun light, creep from the shelves' shadows toward folios left on the
desks and eat their ink. The player is the night archivist with a hand lamp.
Each turn the archivist steps, relights a wall lamp from a limited store of
oil, carries a folio back to its shelf, or rings a hand bell that scatters
nearby inkmites. A relit lamp lights its part of the room until dawn, so the
player spends oil to make safe ground and plans routes through it. Inkmites
cross only dark tiles, head for the nearest unguarded folio, feed while it
stays dark around them, and flee the moment light reaches them. Dawn comes
after a fixed number of turns, and the night's score counts the folios
rehoused whole. Three rooms ship as text maps: a reading room, a map room and
the stacks.

The fog of war has two uses. Lamps and the hand lamp reveal into one layer,
which the board shows the player and which the inkmites read as the light they
fear, so the shadowcast's correctness becomes part of the game's rules. Each
inkmite has a state machine (lurking, creeping, feeding, scattering) and a
behaviour tree that orders its choices (flee if lit, feed if beside a folio,
creep along the distance field, else lurk). One A\* distance field from the
unguarded folios across dark tiles serves every inkmite, and the archivist's
walk to a selected tile is an A\* path over lit ground. Steering's flee moves
a lit inkmite, the ECS holds the archivist, inkmites, folios and lamps, the
collision map holds shelves and desks, and saves keep a night in the home. The
camera stays idle while a room fits the board.

The board is one `TGRID` of 24 by 12 tiles, two cells each, so 48 by 12 cells:
the archivist is the current item, dark tiles are unavailable and show what
the archivist remembers, and the cursor is the primary item. A UIDL status bar
shows folios rehoused and lost, oil and turns to dawn, a list logs the night's
events, a dialog closes the night, and a menu starts, saves and loads nights.
Every one of these is a canonical widget or UIDL element the Desktop already
publishes, and the text grid holds every state the game shows.

Size: 1,200 to 1,600 lines of Forth and UIDL and three maps, 8 to 12 hours
after the library stages.

| Per turn | Cycles | At 100 MHz | Basis |
|---|---:|---:|---|
| Hand lamp, radius 4, and hiding the last reveal | 0.3–0.5 M | 3–5 ms | estimate from 0.71 M measured for radius 6 on 40×20 |
| A lamp relit (that turn only) | 0.5–1 M | 5–10 ms | estimate |
| Distance field over 288 tiles | 0.1–0.3 M | 1–3 ms | estimate |
| Six inkmites' trees, machines and steps | about 0.1 M | 1 ms | measured 4,372 for a tree and 4,727 for a machine |
| Board rebuild, validation and CELL draw | 6.86 M | 69 ms | measured |
| Rich frame | 3–8 M | 30–80 ms | estimate |
| **Turn** | **10–16 M** | **0.10–0.16 s** | |

Fit: Folio Watch belongs in the Workshop (Part 7) as a worked example of the
game library, beside the sliding-tile solver: its sources join the shipped
libraries' sources, read-only, and once Part 7 loads modules from the user
area a learner can copy an inkmite's behaviour tree there, change it, reload,
and watch the creatures play differently. It also serves as a pastime in
Everyday. It needs a home for saves and its origin for maps.

### 3.2 Valley Relay (working name)

A storm has scattered a hiking party across a mountain valley, and the player
is the ranger at the hut with a few portable radio relays. Radio travels only
by line of sight, so each relay placed on high ground covers what it can see,
and ridges cast radio shadows. A hiker inside coverage appears on the ranger's
map and can be talked home along a route the ranger chooses; outside it,
hikers act alone: they wander toward trails, shelter when tired and panic as
night nears. Weather moves through clear, mist and storm and shrinks every
relay's range, relays run down their batteries, and the night ends the rescue.
The score is the hikers home before dark.

Coverage is the fog of war from several sources, the union of each relay's
shadowcast, recomputed only when a relay moves or the weather changes; the
remembered layer is the map of where coverage once reached. Routes are A\*
with terrain costs, cheap on trails, dear on scree and closed at cliffs, so
repair 5's cost table matters here. Hikers have state machines (calm, lost,
panicked, exhausted) and behaviour trees, steering moves them along trails,
the valley is 48 by 24 tiles shown through a 24 by 12 board that the camera
moves, and the ECS holds hikers and relays. This concept exercises the camera
and weighted search that Folio Watch leaves idle.

Widgets: the board; a canonical list of hikers, from which the ranger picks
one to route; status labels for the time to nightfall, relays left and the
weather; dialogs; a menu, all canonical widgets and UIDL elements already in
use.

Size: 1,600 to 2,200 lines, 11 to 15 hours. Per turn, about 10 to 15 million
cycles (0.10 to 0.15 s), the board and frame as in Folio Watch; turns that
place a relay or change the weather add the union of four relays' reveals, an
estimated 4 to 7 million, and an issued route adds 0.5 to 3 million after the
A\* repair (6.12 million today for a 54-step detour on 40×20).

Fit: a pastime in Everyday, and a second Workshop example that shows the board
over a world larger than its tile.

### 3.3 Garden Automata (working name)

A walled garden spreads weeds a little every turn, and gardener automata tend
it. The player never moves a piece: in the Workshop the learner writes each
gardener's brain as a Forth module from the library's behaviour tree, state
machine, steering and A\* words, loads it into the garden applet, and runs a
season turn by turn or straight through. Each gardener sees only its own
surroundings and remembers what it has seen, so a brain must explore, share
out the beds and come back to weeds it saw before. A season replays exactly
from its seed, so two brains can be compared fairly. The arena measures every
brain's cycles each turn and shows them beside its score, which makes the
device's cost part of the lesson.

Per-gardener fog is the per-instance repair's proving use: four fogs, four
memories, one map. The behaviour trees and state machines are the learner's
material, A\* moves the gardeners, steering wanders them, and the ECS holds
gardeners and weeds, with the weed growth a rule over the kind layer.

Widgets: the board; a list of gardeners with their last turn's cycles; status
labels for the season's day and the garden's health; controls through menu
actions (step, run, reset), again all canonical.

Size: an arena of 900 to 1,200 lines and two example brains of about 150 lines
each, 9 to 13 hours. Per turn with a frame, 12 to 18 million cycles; a season
run without frames costs about 3 million cycles a turn, so a 100-turn season
finishes in about 3 s on the device.

Fit: the Workshop's capstone exercise. It depends on Part 7's loading of
modules from the user area, which is unbuilt, and on a design for running a
learner's code: a native brain runs inside the arena's tick, so a brain that
loops forever stops Desk and one that writes wild memory corrupts it. The
sandbox could run brains under a step budget if the library's words gained
sandbox bindings, or the Workshop could accept native brains at the learner's
own risk, as its Forth console will. Later, brains written in Lisp on LM1
(Part 9e) would put both engines in one program, as the sliding-tile solver
does.

### 3.4 Recommendation

Build Folio Watch first. It uses every logic module, and it uses the fog of
war twice, as the player's view and as the creatures' fear, so the repaired
shadowcast is tested by play. Its applet has the simplest shape, one board,
one status bar, one log, and it needs neither a new canonical widget nor
anything from Part 7. It is the smallest of the three, and it gives the
Workshop a worked example of the library that Part 1d needs before the library
can ship. Its board, map reader and save path are the ones Valley Relay and
Garden Automata would reuse.

## 4. Stages

| Stage | Builds | Tests | Hours | Unblocks |
|---|---|---|---:|---|
| 0 | `test-health-3` lands; decision 1 is taken | — | — | Stage 1 |
| 1 | Repairs 1 to 4 and the camera fix | Teardown depths and frees; nested trees against a host model; nested iteration and callbacks; fog against a host oracle | 5–7 | Any use of the AI or the fog |
| 2 | Repairs 5 and 6 | A\* against a Dijkstra oracle; flat `XMEM-HERE` over 20 rounds; cycles against Appendix A; two ECS instances; one definition for two entities | 5–7 | Many creatures within a turn's budget |
| 3 | Repairs 7 and 8 | Save round trips on MP64FS and ext4; refused files; map validation | 2.5–3.5 | Saved nights and shipped maps |
| 4 | Repairs 9 to 11; the chosen game's skeleton (a map, a player who moves, fog, save and load, close negotiation); its first per-turn measurement | Board model and CELL draw; headless rich run with `GRID_CELLS` and a `PLACE`; Desk with the game | 5–7 | Stage 5; decision 3's measurement |
| 4b | On decision 3: the text grid follows change | Grid, Daybook and the game; the physical Desktop journey once | 3–5 | A turn within budget at a larger board |
| 5 | The game: rules, creatures, three maps, dialogs, status, log, seeds, save points | Headless turn replay; per-turn cycles; Desk with the game through a short night | 8–12 | Inclusion in a configuration |
| 6 | Configuration entry, documents, closing runs | `run --recorded` with patterns; the physical Desktop journey if a composition it gates includes the game | 1.5–2.5 | Part 1d status "ships" for the library |

Stages 1 to 6 come to 27 to 39 hours with Folio Watch, and stage 4b to 3 to 5
more. Decision 4 is due before stage 3, decisions 2, 6 and 7 before stage 4,
decision 3 once stage 4 has measured a turn, and decision 5 before stage 6.

**Stage 1** fixes everything that gives wrong results today. It changes the
interfaces of `BT-RUN` and `FOG-NEW`, which only the library's suites call.
Its tests include their own oracles, a host model of tree traces and a host
shadowcast, so each test checks the specified result. Commits follow the
modules: teardown, behaviour trees, fog, callbacks.

**Stage 2** makes the library cheap enough for many creatures and fit for
several instances. The probe's figures in Appendix A are its baseline, and the
stage records the same calls afterwards, so each saving is a count on the
device's cost model.

**Stage 3** moves persistence onto places. Its ext4 cases use a small fixture
on the simulator, in the narrow tests, and leave the four ext4 harness files
alone, since no ext4 code changes.

**Stage 4** retires the terminal half and stands up the chosen game as an
ordinary applet with enough rules to move and save. It then measures a whole
turn: the logic and the board in emulator cycles, as Appendix A does, and the
rich frame in guest steps on the simulator, as the frames plan measures
frames, converted at the emulator's ratio of cycles to steps for the same
code. That measurement decides whether stage 4b runs, since the text grid at
present validates and draws every item whenever its model changes.

**Stage 4b**, if taken, registers a partial drawer for `TGRID` through
`WDG-PARTIAL!` and validates a new bank against the bound one only where items
changed, as part 7 of the frames plan did for fills. Grid and Daybook gain the
same saving. It touches the rich path, so the physical Desktop journey runs
once at its end.

**Stage 5** builds the game itself. The turn engine stays a module apart from
the applet, so the headless unit can replay scripted nights without UIDL.

**Stage 6** places the game in its configuration (decision 5), rewrites the
library's reference pages, and runs the closing checks.

## 5. Decisions

**1. Which game.** The repairs serve all three concepts, but the choice of
game determines stage 4's skeleton and stage 5's work, so it comes first.
Options: Folio Watch (8 to 12 hours), Valley Relay (11 to 15) or Garden
Automata (9 to 13, plus Part 7's module loading and a design for running
learner code). Recommendation: Folio Watch, for the reasons in 3.4. The names
are working names, and choosing the game includes choosing its name.

**2. How the board reaches the screen.** The board must go through an ordinary
canonical widget, and each form has a different device cost and a different
set of states. Options: (a) a `TGRID` item for each tile, with per-tile
current, unavailable and selection states, at 6.86 million cycles a move on
the CELL path at 24 by 12 and 12.13 million at 32 by 16; (b) a `TGRID` item
for each row, 3.86 million cycles at 32 by 16, with no state or pointer target
for a single tile, so fog shows only by glyph; (c) a new canonical board
widget and rich family with compact tiles and semantic tile kinds that a
renderer could colour, which needs an APT-1 contract, a MegaPad terminal side,
a producer and qualification, an estimated 15 to 25 hours, and a second
ordinary Desk use to justify it. Recommendation: (a) at 24 by 12 tiles, since
it is the ordinary widget the Desktop already publishes and it carries every
state the concepts need. Cost: inside stage 4.

**3. A turn's budget, and whether the text grid follows change.** The board
dominates a turn's cost, so a budget decides how large a board may be.
Options: a budget of 10 million cycles (0.1 s at 100 MHz), 15 million (0.15 s)
or none; and, if stage 4's turn exceeds the budget, stage 4b, a smaller board,
or both. Recommendation: 15 million cycles for a whole turn including its rich
frame, measured in stage 4, with stage 4b if the turn exceeds it, because a
board that answers its key within about 0.15 s keeps a turn-based game
responsive, and stage 4b improves a canonical widget that Grid and Daybook
share. Cost: stage 4b's 3 to 5 hours and one physical Desktop journey.

**4. The map format.** The loader is rewritten in either case, and the format
decides who can make maps. Options: text maps with a legend, or CBOR maps as
today. Recommendation: text, because a person can write and read a map in Pad
and a learner can read one in the Workshop, while CBOR needs a writing tool
the project lacks; saves stay CBOR, since only the machine writes them. Cost:
the same 1 to 1.5 hours either way.

**5. Where the game ships.** Under Part 1d a library ships when something that
ships uses it, so the game's placement settles the library's status. Options:
the Workshop as a worked example, Everyday as a pastime, both, or after the
first release. Recommendation: the Workshop, with Everyday optional, provided
stage 6 lands before Part 7 closes; should Part 7 close first, it goes ahead
and the game and the library wait for the next release. Cost: about an hour
within stage 6 for the entry and a narrow journey.

**6. Real-time play.** Deleting `loop.f` removes the library's real-time loop.
Options: turn-based games only, or a real-time loop kept for later games.
Recommendation: turn-based only. At 30 frames a second a frame has 3.3 million
cycles, half a measured 24 by 12 board move before its rich frame, so
real-time play exceeds the device until the screen path costs a fraction of
today's. Cost: none.

**7. What to keep of the terminal half.** Options: retire fifteen files and
rewrite the map loader, as 1.4 proposes; keep `input.f` or `scene.f` as
conveniences; or patch all sixteen. Recommendation: retire fifteen, because
every one paints cells directly, keeps process-wide state or repeats what UIDL
and the canonical widgets already do, and the rich-terminal rules give an
applet its UI only through ordinary UIDL documents and canonical widgets.
Cost: 0.5 to 1 hour, within stage 4.

**8. A registration word for widget kinds.** The game needs none after repair
11, while applets' own panels still reuse canonical type numbers. Options: add
`WDG-T-NEW ( -- type )` to `widget.f` and move those panels to it, or leave
the accepted practice that fd761ec4 made safe for partial drawers.
Recommendation: leave it out of this plan and take it up with the next Desk
cleanup, since no fault depends on it today. Cost: 0.5 to 1 hour when taken.

## Appendix A. Measurements

Emulator cycles, `PERF-CYCLES` differences, Akashic 68cb727f and MegaPad
d8016c43, 2026-11-22. Each figure is one call, measured once in the emulator's
cycle model, which counts exactly; where code lands in memory moves such
counts by about 1%.

| Call | Cycles | At 100 MHz |
|---|---:|---:|
| A\* on 40×20, five-step path | 191,066 | 1.9 ms |
| A\* on 40×20, 54-step detour around a wall | 6,119,379 | 61 ms |
| A\* on 64×64, five-step path | 611,052 | 6.1 ms |
| A\* on 64×64, 79-step path across open ground | 17,660,202 | 177 ms |
| `FOG-HIDE-ALL` on 40×20 | 221,401 | 2.2 ms |
| `FOG-REVEAL` radius 6 on 40×20 | 714,108 | 7.1 ms |
| `FOG-REVEAL` radius 10 on 40×20 | 1,677,446 | 16.8 ms |
| `FOG-HIDE-ALL` on 64×64 | 1,123,899 | 11.2 ms |
| `FOG-REVEAL` radius 10 on 64×64 | 1,695,718 | 17.0 ms |
| 64 × `ECS-SPAWN` with two attaches | 694,061 | 6.9 ms |
| `SYSRUN-TICK` with `SYS-VELOCITY`, 64 entities | 99,836 | 1.0 ms |
| `ECS-EACH` over 64 entities, empty callback | 49,849 | 0.5 ms |
| `ECS-COUNT` over 64 slots | 19,544 | 0.2 ms |
| `FSM-TICK`, four transitions from the state | 4,727 | 0.05 ms |
| `BT-RUN`, a selector of three actions | 4,372 | 0.04 ms |
| Board 32×16, an item a tile: build | 5,107,666 | 51 ms |
| … `TGRID-BIND` | 8,680,463 | 87 ms |
| … first CELL draw | 7,017,465 | 70 ms |
| … a move: rebuild, bind and draw | 12,133,894 | 121 ms |
| Board 24×12, an item a tile: build | 2,878,130 | 29 ms |
| … `TGRID-BIND` | 4,676,019 | 47 ms |
| … first CELL draw | 3,969,077 | 40 ms |
| … a move: rebuild, bind and draw | 6,855,970 | 69 ms |
| Board 32×16, an item a row: build | 1,703,401 | 17 ms |
| … `TGRID-BIND` | 918,277 | 9 ms |
| … first CELL draw | 2,150,840 | 22 ms |
| … a move: rebuild, bind and draw | 3,863,004 | 39 ms |

The fog figures come from today's scan. On the open 64×64 map, where nothing
blocks sight, it visits the tiles a correct scan visits; on 40×20, whose wall
it mishandles, its set of tiles differs, so those figures are approximate. A
board entry took 41,128 bytes at 32 by 16 with an item a tile, 23,208 at 24 by
12, and 2,344 at 32 by 16 with an item a row. A move cost less than the first
build, bind and draw together. The probe timed each move as one figure, so how
the saving divides among the three is unmeasured; the second draw meets a
screen that already holds most of the board. `XMEM-HERE` rose 327,840 bytes
over ten rounds of one 40×20 and one 64×64 search, and 655,680 over twenty.
