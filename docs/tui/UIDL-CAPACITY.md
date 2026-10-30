# UIDL capacity at production size — design, 2026-10-30

Status: proposed on 2026-10-30. Nothing in it is built. It assumes that
slice 9a.4 of [FRAMES-FOLLOW-CHANGE](../rich-terminal/FRAMES-FOLLOW-CHANGE.md)
is done: the rich adapter's (RUHA's) snapshot banks grow from Desk's memory
source to what the snapshots need, and no longer follow UIDL's limits. This
plan does not cover the banks. RUHA's work spans still follow those limits
(section 6). Each slice is approved on its own. Decisions lists what is open.

Line references are to e5908dc7. Source paths are under `akashic/`;
`docs/` and `local_testing/` paths start at the repository's root; MegaPad
paths say so. `tui/desk-apt1.f` and `tui/rich-terminal/uidl-hybrid-adapter.f`
were read at that commit, before 9a.4 changed them in 53ab9ef7. Counts of
today's documents are calculated from their `.uidl` files. Counts of
switches and cycles are estimates from reading the code. Slice 0 measures
both.

Related: [uidl.md](../liraq/uidl.md), the document model;
[uidl-tui.md](uidl-tui.md), the TUI backend and its contexts;
[applet-host.md](applet-host.md); [app-catalog.md](app-catalog.md).

## Summary

UIDL keeps each document in fixed pools: 256 elements, 512 attributes,
12,288 bytes of strings and a 256-slot ID table (`liraq/uidl.f:314-317`).
UIDL-TUI keeps a record beside each of the 256 elements, and fixed tables
for shortcuts, actions and the overlays a paint defers. Every document's
context takes the same 115,968 bytes, whatever the document holds. Desk's
catalog holds at most 32 applications, and several other tables follow that
32.

Today's documents are small. Pad's is the largest: 87 elements, 160
attribute nodes and 1,938 bytes of strings at load. At load no document
comes near the element, attribute or string limits. Two tables are close:
Pad's document has 51 shortcuts of the 64 the table holds, and Pad's 32
actions take 1,025 of the action arena's 1,536 bytes. Several tables drop
an entry without a word when they fill, and one refusal empties a value
that was already on screen.

The largest cost is on the device. UIDL's elements, attributes and strings
point at each other by address, so a document's storage cannot move. Desk
therefore switches documents by copying the live one out and the next one
in: 231,904 bytes a switch. The simulator charges two steps for a block copy
of any length, so the step counts the plans use do not show this cost.
MegaPad's string engine moves one byte at a time, in at least four clock
cycles. By that rule one switch costs at least 0.93 million cycles. Daybook
and Sound Lab both tick while nothing changes, so with both open each 50 ms
tick switches into one and then the other, and an idle Desktop would spend
more than a third of a 100 MHz core copying contexts. These figures are
estimates; slice 0 counts the switches.

This design makes three changes.

- **A context is a record, and a switch stores a pointer.** Each document's
  storage belongs to its context, and nothing is copied when the live
  document changes (slices 2 and 3).
- **Pools are measured at load and grow in chunks that never move.** A scan
  of the document's text sizes each pool before the parse. A pool that must
  grow later adds a chunk, so every element, attribute and string keeps its
  address (slices 4 to 7).
- **A host policy bounds what documents hold.** Desk's settings give a total
  for all documents and a ceiling for one. Each document takes only what it
  measured. Desk's catalog, and everything else sized by its 32, grows too
  (slices 8 and 9).

Estimated effect: a switch copies nothing. Pad's context falls from 115,968
bytes to about 40 KB, and a Desk screen's to about 3 KB. About 113 KiB of
pools leave the dictionary. Nothing per document stays fixed but its budget.
Steps per frame should stay about the same; slices 2 to 4 measure them.

## Rules

Kept from earlier work:

- The workspace AGENTS.md rules: capacity design, resource safety, drive
  wear and the rich-terminal vertical. The same applet sources and UIDL
  documents serve CELL and rich output.
- From FRAMES-FOLLOW-CHANGE: storage is sized from what the content needs
  now and grows on demand, and nothing reserves a guessed maximum. Storage
  taken from a memory source needs no proof that it lies apart from other
  live storage. Storage a caller lends is proved apart when it is lent.

New:

- **Every limit is classified.** An interface or format rule may stay
  fixed, sized for production. A resource bound becomes dynamic: a host
  policy sized for the device, narrowed for each use, with work space
  measured from the input.
- **Addresses stay valid.** An element, attribute or string keeps its
  address until its document resets or its context is freed.
- **A refusal changes nothing.** A load that cannot get its memory fails
  whole and gives back what it took. A later change that cannot get memory
  leaves the document as it was, and is reported. Paint, layout and capture
  take nothing from a document's budget, so no frame fails for it.
- **Each slice sends what it sent before.** The typing run sends the same
  DELTAs and bytes, and the canonical journey with the shadow check finds no
  difference.
- **A speed-up removes only work that is provably repeated,** and states its
  proof. No check goes. One is added: a write to an element of a context
  that is not live is refused.
- **Device cost comes first.** Each measurement reports bytes moved and
  memory held beside steps, since steps do not see block copies.

## What exists now

### UIDL's document pools

All are in `liraq/uidl.f`, allotted in the dictionary (352-374) and cleared
by `UIDL-RESET` at every load (385-394). The last column is Pad's use at
load, counted from `pad.uidl`.

| Pool | Size | Bytes | Lines | Pad |
| --- | --- | ---: | --- | --- |
| Elements | 256 × 128 | 32,768 | 314, 319-336, 352 | 87 |
| Attribute nodes | 512 × 48 | 24,576 | 315, 338-348, 353 | 160 |
| Strings: IDs, roles, binds, names, values | 12,288 | 12,288 | 316, 354 | 1,938 |
| ID table: an element a slot | 256 × 8 | 2,048 | 317, 355 | 18 IDs |
| ID table: each ID's string span | 256 × 16 | 4,096 | 356 | 18 |
| Element revisions | 256 × 8 | 2,048 | 363-368 | 87 |
| Subscriptions | 128 × 24 | 3,072 | 373-374 | 0 |

An element record holds the addresses of its parent, siblings, children and
first attribute (319-336). An attribute node holds the address of the next
node and of its name and value in the string pool (338-348), and `VAL-CAP`
lets a later value reuse its room (1101-1133). The ID table holds element
addresses and the addresses of the ID strings (501-544). Allocation is
append-only within a document (428-446), and an element's pool index is its
public identity (`docs/liraq/uidl.md:86-110`).

The element type registry is not per document, but it is built the same
way: 64 types and 512 bytes of names (150-155), with the 64 written again as
`63 AND` in its hash (167-174). 42 types are registered, with 253 bytes of
names: 21 in `liraq/uidl.f:267-287` and 21 in `liraq/uidl-chrome.f:31-75`.

### UIDL-TUI's per-document tables

All are in `tui/uidl-tui.f`.

| Table | Size | Bytes | Lines | Largest use today |
| --- | --- | ---: | --- | --- |
| Sidecars: layout, style, widget | 256 × 96 | 24,576 | 122-124, 166-172 | one an element |
| Widget revisions | 256 × 8 | 2,048 | 125-128, 2859 | one an element |
| Mounted-source state | 256 × 16 | 4,096 | 4350-4354, 4423 | one an element |
| Action arena | 1,536 | 1,536 | 771-772, 820-848 | Pad: 32 actions, 1,025 bytes |
| Shortcuts | 64 × 32 | 2,048 | 904-905, 973-987 | Pad: 51 |
| Overlays one paint defers | 32 × 16 | 512 | 2841-2851 | an open menu, a dialog |
| The resolved walk's marks | 256 | 256 | 6334, 6347 | one an element |

Pad's action figure is a calculation: its 32 `UTUI-DO!` calls
(`tui/applets/pad/pad.f:2433-2464`) take 24 bytes each and 257 bytes of
names. Its shortcut figure counts the `key=` attributes in `pad.uidl`.
Daybook, File Explorer and Library have 22 to 24.

### Today's documents

Calculated from the `.uidl` files in `tui/applets/*/`. Attribute nodes leave
out `id`, `role`, `arrange`, `bind` and `xmlns`, which UIDL keeps in the
element record. Strings are the bytes the parse copies.

| Document | Bytes | Elements | Attribute nodes | Strings | IDs | Shortcuts |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| pad | 3,693 | 87 | 160 | 1,938 | 18 | 51 |
| daybook | 2,002 | 53 | 94 | 1,239 | 5 | 22 |
| fexplorer | 1,726 | 51 | 82 | 937 | 13 | 24 |
| library | 1,791 | 48 | 84 | 1,081 | 6 | 24 |
| agent | 1,765 | 46 | 81 | 1,048 | 14 | 20 |
| streams | 1,647 | 40 | 69 | 1,054 | 7 | 12 |
| grid | 1,080 | 30 | 51 | 617 | 5 | 14 |
| soundlab | 992 | 27 | 41 | 574 | 6 | 8 |
| worlds | 699 | 20 | 26 | 387 | 6 | 2 |
| observatory | 479 | 12 | 15 | 266 | 5 | 3 |

Desk's own screens are inline and smaller still. The launcher and the
sandbox and schedule screens have five or six elements each
(`tui/applets/desk/desk.f:2500-2501`, `sandbox-surface.f:341-342`,
`schedule-surface.f:502-503`). Desk itself has no document
(`desk.f:3059-3060`). No document uses `bind=`. How far documents grow at
runtime, as attribute values change, is not known yet; slice 0 measures it.

### When a table fills

- **At load.** A full element, attribute or string pool sets an error, and
  `UIDL-PARSE` returns false (`liraq/uidl.f:400-420, 467-488, 747-762`).
  The load fails whole. This is clean.
- **A value grows at runtime.** When `UIDL-SET-ATTR` cannot get room for a
  longer value, it empties the attribute (1116-1121). The screen loses text
  it showed.
- **One error stops every new attribute.** `_UDL-ERR` is one global (93),
  not part of a context, and only `UIDL-RESET` clears it (385-386). While it
  is set, `_UDL-STORE-ATTR` refuses every new attribute (596-597). So one
  refusal or failed parse in any document stops new attributes in every
  document until the next load.
- **Silent drops.** A shortcut past 64 (`tui/uidl-tui.f:975-977`), an action
  that does not fit (820-848), a subscription past 128
  (`liraq/uidl.f:1277`) and a type name past 512 bytes (158-165) are dropped
  with no error. The validation report keeps 16 errors, and its count stops
  there (898-905).
- **An overlay is not painted.** A paint that defers more than 32 elements
  drops the rest, and skips their subtrees too (`tui/uidl-tui.f:2846-2851,
  3026-3036`).
- **Latent faults.** A full ID table would return 0 without an error, and
  the parse would go on without the element (`liraq/uidl.f:501-524`). That
  cannot happen while the table has as many slots as the element pool.
  `UIDL-REMOVE-ELEM` zeroes an element but leaves its ID in the table, so
  `UIDL-BY-ID` returns the zeroed record (1089-1099, 526-544). No
  application removes elements today.
- **The UIDL file loader.** `ASHELL-LOAD-UIDL` reads at most 8,192 bytes and
  parses what it read (`tui/app-shell.f:695, 720-731`). Nothing checks for
  more, and the parser ends an element where its input ends
  (`liraq/uidl.f:663-745`), so a longer file would load cut short. All ten
  applications load their documents this way; the largest is 3,693 bytes.

### Contexts and how they switch

Each slot with a document gets a context buffer (`UCTX-ALLOC`,
`tui/uidl-tui.f:5817-5819`, called at `tui/applet-host/host.f:838`). The
buffer holds 32 variables, 256 bytes, and copies of 13 pools, 115,712
bytes: 115,968 in all (`tui/uidl-tui.f:5665-5712, 5731-5811`). UIDL's seven
pools take 80,896 bytes of it and UIDL-TUI's six take 34,816. The pools that
follow the element count take 256 bytes an element, 65,536 bytes in all.

`ASHELL-CTX-SWITCH` saves the live context and restores the next, unless the
next is already live (`tui/app-shell.f:147-158`). `UCTX-SAVE` copies 30
variables and every pool into the buffer, and `UCTX-RESTORE` copies them
back (`tui/uidl-tui.f:5921-5966`). So a switch moves 2 × (240 + 115,712) =
231,904 bytes. `ASHELL-CTX-SAVE` copies half of that without a switch
(`tui/app-shell.f:168-178`); the host calls it after a launch, a quiesce and
a close (`tui/applet-host/host.f:117-118, 403, 486, 506, 589, 875`).

The copy is needed because the pools sit at fixed addresses. Every document
lies at the same addresses while it is live, so the links inside it stay
valid. The same fact means that an address names whichever document is
live. A capability handler that ran in the wrong context wrote another
application's elements, until 61059533 gave the request bus a scope.

The host switches wherever it runs a slot's code: a key or a click
(`host.f:1158, 1201`), a tick (1240-1270), a service pass (1280-1298), a
paint (1308-1316, through `tui/app-shell.f:210`) and a capability call
(`host.f:317-327`). RUHA's captures switch to each document they read and
back (`tui/rich-terminal/uidl-hybrid-adapter.f:3283, 3368, 3453, 4249, 4289`
and others). Daybook, Sound Lab, Streams and Worlds tick even when nothing
changed (`APP-F-TICK-WHEN-CLEAN`: `daybook.f:2514`, `soundlab.f:1638`,
`streams.f:5165`, `worlds.f:1061`), and the shell ticks every 50 ms
(`tui/app-shell.f:402-403, 1279-1283`).

### What a switch costs

Three models of the machine charge a copy differently:

- The simulator charges a block copy two steps, whatever its length
  (MegaPad `simulator/accel/semantic_executor.cpp:562-564`). So the plans'
  step counts do not show it.
- The emulator charges one cycle a byte (MegaPad
  `emulator/megapad64.py:2292-2306`, `emulator/accel/mp64_accel.cpp:
  10862-10880`).
- The RTL's string engine moves each byte through four states: read, wait,
  write, wait (MegaPad `rtl/core/mp64_string.v:13, 49-56, 141-300`). With
  memory that answers at once, that is four cycles a byte.

Estimate, by the RTL rule: a switch takes at least 927,616 cycles, about
9.3 ms at the 100 MHz clock of today's FPGA target (MegaPad
`docs/architecture.md:249`). With Daybook and Sound Lab open, each tick
switches into both: at least two switches every 50 ms, so at least 18.6 ms
of every 50 ms, while nothing on the screen changes.

### Desk's catalog and what its 32 sizes

| Table | Size | Lines | When full |
| --- | ---: | --- | --- |
| Installed applications | 32 | `tui/applets/desk/desk.f:309, 363-364, 578` | `DESK-INSTALL` returns `CREG-E-FULL` |
| Built-ins queued before `DESK-RUN` | 32 | `desk.f:195-197, 230` | dropped silently |
| Startup launches | 8 | `desk.f:237-239, 3066-3074` | dropped silently |
| Catalog rows | 32 | `tui/app-catalog.f:79, 120-121, 164-168, 472, 716, 780` | `ACAT-S-FULL`; a file with more rows is refused |
| Component types | 32 | `runtime/registry.f:11, 60-71` | `CREG-E-FULL` |
| Live component instances | 64 | `runtime/registry.f:12, 80-90` | `CREG-E-FULL` |
| Visible tiles collected for tiling | 64 | `desk.f:635-648` | left out silently |
| RUHA's document records | 32 | `tui/desk-apt1.f:88, 299-300` | attach answers `RUHA-S-UNAVAILABLE` (`uidl-hybrid-adapter.f:1402`) |
| The screen producer's documents | 32, never grows | `desk-apt1.f:310, 723`; `tui/rich-terminal/hybrid-screen-producer.f:1539, 9522` | the candidate is refused |

The component types are shared. Desk's own type and the sandbox
capability's come from the same registry as installed applications
(`desk.f:579, 1405, 1811`), and so do the types of the resource owner pools
Desk lends it to (`desk.f:1545-1551`, `interop/resource-owner-pool.f:470`).
So fewer than 32 applications can be installed today. The resource owner
pool also checks a registry's counts against the two registry maximums
(310-311, 906-907), and proves the registry apart as one `CREG-SIZE` span
(948-990).

### Capacity math in other modules

- **`tui/desk-apt1.f`.** It takes its bindings from `_DESK-MAX-INSTALLED`,
  its records from `_UTUI-MAX-ELEMS` and its text from `_UCTX-STRS-SZ`
  (88-94). The product overrides `APT1-DESK-*-NATIVE-CAPACITY` default to
  aggregates of these (100-135). The transmit buffer is sized for the
  largest payload those allow (195-213, 323): 917,648 bytes with the
  defaults. That is a calculation: the data-graphics default, 32 × 256 ×
  112 = 917,504 bytes, plus 104 for an instrument's fixed payload and 40 for
  the frame header. After 9a.4, Desk still carves RUHA's record and its
  document records (FRAMES-FOLLOW-CHANGE, 9a.4).
- **Snapshot modules.** They size their work from the document's element
  count, as they should, and report a span that is too short
  (`tui/uidl-menu-snapshot.f:360-372`,
  `tui/uidl-collection-snapshot.f:174-191`). Two places compute an
  element's address from its index with UIDL's private layout:
  `uidl-collection-snapshot.f:802` and `tui/uidl-root-facts.f:92-99,
  232-236`. Others check counts against `_UTUI-MAX-ELEMS`:
  `uidl-collection-snapshot.f:957` and `tui/uidl-tui.f:4518, 4785, 4868,
  4942, 6519, 6609, 7185, 7364, 7787, 7972`.
- **Storage proofs.** `UIDL-STORAGE-DISJOINT?` lists every fixed pool
  (`liraq/uidl.f:1310-1340`). `UTUI-STORAGE-DISJOINT?` treats the module's
  dictionary from its sidecars to its end as one span, and the live context
  buffer as another (`tui/uidl-tui.f:6047-6073`). `tui/shell-snapshot.f:
  75-76, 497, 841` treats each slot's buffer as one span too.
- **Applications.** Desk, File Explorer and Pad set an element's style by
  writing UIDL-TUI's private sidecar (`desk.f:2550-2553`,
  `tui/applets/fexplorer/fexplorer.f:281-284`, `pad.f:398-400`).

### What pins the numbers

- The refactor ratchet's capacity list pins `_UDL-MAX-ELEMS` 256,
  `_UDL-MAX-ATTRS` 512, `_DESK-MAX-INSTALLED` 32, `_DESK-BUILTIN-MAX` 32,
  `_DESK-PEND-MAX` 8, `_DESK-MAX-VIS` 64, `CREG-MAX-TYPES` 32 and
  `CREG-MAX-INSTANCES` 64 (`local_testing/refactor_architecture.json`,
  "capacities"). `refactor_inventory.py --check` fails when one changes.
- Structure tests pin the context's layout, the action arena and the proof
  spans: `test_uidl_resolved_projection_structure.py` (370-371, 721,
  1175-1304), `test_uidl_retained_architecture.py` (363, 369-378, 478,
  843-845), `test_uidl_semantic_structure.py` (98-104).
- Tests use the sizes: `test_uidl_revisions.py:197`,
  `test_shell_snapshot.py:260-261`, `test_uidl_mounted_association.py:53`,
  and `test_desk_host_characterization.py` near 205-220, where a whole
  context cannot fit.
- Tests read UIDL's private string position: `test_uidl.py:1195-1225`,
  `test_uidl_menu_checked.py:96-104`.
- Tests drive the save and restore: `test_applet_host.py`,
  `test_app_shell_dialog_hosting.py:40-48`,
  `test_uidl_collection_snapshot.py:388-540, 1369-1386`.
- Documents: `docs/liraq/uidl.md` (350-360, 805-830),
  `docs/tui/uidl-tui.md` (65, 85, 1408-1446, 1565-1571),
  `docs/tui/app-shell.md` (80-82), `docs/tui/applet-host.md` (136),
  `docs/tui/applets/desk/desk.md` (695-720), `docs/tui/app-catalog.md` (4).

Part of `local_testing` is untracked, so a search there uses plain `grep`.

## Each limit, classified

| Limit | Kind | Production rule |
| --- | --- | --- |
| Elements, attribute nodes, string bytes | resource | measured at load; grow in chunks; bounded by the document's budget |
| ID table slots, and its copy of each ID | resource: an index | sized from the IDs at load, at most half full; holds element addresses only |
| ID format, `[a-z][a-z0-9-]*` up to 64 bytes (`liraq/uidl.f:920-939`) | format rule | kept |
| Element record 128 bytes, attribute node 48 | internal layout | kept |
| Revisions, sidecars, widget revisions, mounted-source state | resource, one an element | in the element's slot; grow with the elements |
| Subscriptions | resource, unused | removed (decision 4) |
| Shortcuts | resource | sized from the document's `key=` elements at load |
| Shortcut syntax: `Ctrl+`, `Shift+`, `Alt+`, F1 to F12, named keys | interface rule | kept |
| Overlays a paint defers | resource, per paint | a link in each element; never drops |
| Action arena | resource | first size from the document; grows; a refusal fails the launch |
| Walk marks | resource, per walk | a mark in each element |
| Validation report | resource | counts and keeps every error |
| Type registry: 64 types, 512 name bytes | registry the code fills at load | grows; a name that does not fit is an error |
| UIDL file buffer, 8,192 bytes | resource | the file's own size |
| Context, 115,968 bytes | resource | a small record plus what the document holds |
| Installed applications, built-ins, startup launches | resource | growable lists; nothing dropped |
| Catalog rows | resource | sized from the row count |
| Catalog row fields: ID 63, title 63, version 31, path 255 bytes (`app-catalog.f:80-83`) | format rule shared with manifests (`docs/tui/app-manifest.md:52-63`) | kept |
| Component types and instances | resource | growable arrays |
| Visible tiles | resource | sized from the visible slots |
| Hotbar pins, 12 (`desk.f:308`) | presentation rule: what the hotbar shows | kept |
| RUHA's document records; the producer's documents | resource | grow with the documents |
| Transmit buffer | resource bounded by an interface rule | grows to the largest frame, never past the terminal's maximum payload (decision 6) |
| APT-1 maximum payload, at most 0x00100000 (`docs/rich-terminal/APT-1-WIRE.md:77, 104`) | interface rule, negotiated | kept |

## The design

### 1. A context is a record, and a switch stores a pointer

UIDL gets a document record of its own, in `liraq/uidl.f`, and UIDL-TUI's
context record in `tui/uidl-tui.f` holds one. Each layer reaches its state
through one live pointer: UIDL through the live document, UIDL-TUI through
the live context. Today `uidl-tui.f` must enumerate `uidl.f`'s private names
to copy them (5675-5678). After this, each layer owns its own record.

Where today's context goes (`tui/uidl-tui.f:5731-5811`):

| Today | After |
| --- | --- |
| `_UDL-ECNT`, `_UDL-ACNT`, `_UDL-SPOS`, `_UDL-ROOT` | fields of UIDL's document record |
| element, attribute, string and ID pools; revisions | UIDL's document record: chunk lists and an ID table (section 2) |
| `_UDL-SUB-CNT` and the subscription pool | removed (decision 4) |
| `_UTUI-ELEM-BASE` | removed; the element chunk list replaces it |
| the 20 document variables: state, focus, region, projection, menu, overlay and dialog | fields of UIDL-TUI's context record |
| `_UTUI-ACT-CNT` and the action arena | the context record: the arena's address, size and count |
| `_UTUI-SHORT-CNT` and the shortcut table | the context record: the array's address and count |
| `_UTUI-MC-HEAD`, `_UTUI-MC-COUNT` | fields of the context record |
| sidecars, widget revisions, mounted-source state | each element's slot (section 2) |
| `_UTUI-OVERLAY-CNT`, the overlay buffer, `_UTUI-SKIP-CHILDREN` | out of the context: paint scratch |

**A switch.** `UCTX-RESTORE` keeps its checks: who owns the live state, and
no draw observation under way (5943-5966). Then it stores the context in the
live pointer, today's `_UCTX-LIVE-OWNER` (5720), and selects its document in
UIDL. `UCTX-SAVE`, `ASHELL-CTX-SAVE` and `AHS-CTX-SAVE` go, with the host's
five calls of the last: no second copy is left to bring up to date.
`UCTX-LIVE-DISOWN` keeps only its checks, since the relation chain and the
dialog already belong to the record (5890-5902). `ASHELL-CTX-SWITCH` keeps
its contract and its authority checks.

**Proof that the copy is repeated work.** `UCTX-SAVE` writes a buffer's
pools, and only `UCTX-RESTORE` reads them (5921-5966). `UCTX-FREE` and
`UCTX-CLEAR` read only the relation and dialog cells (5824-5832,
5904-5905). Every other reader reads the live state. The shell snapshot
reads a buffer only as a span, to prove that a lent span lies apart from it
(`tui/shell-snapshot.f:497, 841`). So when a context's own storage is the
live storage, every reader gets the bytes it got before, and dropping the
copy loses nothing. A structure test keeps the property: no module but the
context code reads a context's pools.

**Proof that paint scratch needs no saving.** `UTUI-PAINT` clears the
overlay count before its first pass (3115), and only the paint reads the
buffer (3026-3083). `_UTUI-PAINT-ELEM` clears the skip flag first (2992),
and the paint loop reads it right after (3120). The values saved with each
context were never read.

**Writes to a context that is not live.** Once each document has its own
storage, an element's address names that element for good. A write through
it then lands in its own document while another is live. `UIDL-SET-ATTR`
would take room from the live document's strings for the other document's
attribute: a pointer across contexts, left dangling when either resets. So
every public word that writes an element or its attributes first checks
that the element lies in the live document, as `UIDL-TOUCH` already does
through `UIDL-ELEM-INDEX?` (`liraq/uidl.f:464-465`). An element of another
document is refused: nothing changes, and the context counts the refusal.
The words are `UIDL-SET-ATTR`, `UIDL-REMOVE-ATTR`, `UIDL-ADD-ELEM` for its
parent, `UIDL-REMOVE-ELEM`, `UIDL-MOVE-ELEM`, `UIDL-BIND-WRITE`,
`UIDL-MARK!` and `UIDL-CLEAN!` (1054-1252), and UIDL-TUI's wrappers. The
check is one range test a write. Writes come a few a key, and the check can
find a real fault each time it runs.

**The default document.** A standalone application and the unit tests use
UIDL with no context. UIDL creates a default document the first time it
needs one, from the system allocator with no budget. Desk itself has no
document, so in Desk the default is never created. Nothing is allocated
while the module loads, so the module can still join a compiled shard
(AGENTS.md, Forth test performance).

**Storage proofs.** One word, `UCTX-STORAGE-DISJOINT? ( a u ctx -- flag )`
(proposed), tests a span against a context's record, its chunk lists, its
chunks and its ID table. `UIDL-STORAGE-DISJOINT?`, `UTUI-STORAGE-DISJOINT?`
and the shell snapshot's per-slot checks use it, and keep their own
dictionary spans. A proof costs one span test a chunk. After section 2 a
current document has one chunk a pool.

**What the pointer costs.** An element's fields stay its address plus an
offset, so tree walks do not change, and attributes and strings are read
through their addresses as today. Layout, paint and capture also reach an
element's sidecar, revision or index for most elements they visit. The
operations below are counted by reading the words; they are estimates.

| Access | Uses in source | Today | After |
| --- | ---: | --- | --- |
| Element's sidecar, `_UTUI-SIDECAR` | 150 | fetch a base, subtract, divide by 128, multiply by 96, add | add a constant |
| Element's revision, `_UDL-REV-AT`, `_URF-REV` | about 10 | subtract, divide, scale, add | add a constant |
| Element to index, `UIDL-ELEM-INDEX?` | 25 | three range tests, a remainder, a division | a range test on the first chunk, a mask, a shift |
| Index to element, `UIDL-ELEM-AT?`, `_URF-ELEM` | a few | multiply, add | one compare more |
| A document variable, such as `_UDL-ECNT @` | many | push an address, fetch | fetch the live record, add, fetch |
| A pool or table address, such as `_UTUI-ACTS` | about 140 | push an address | fetch the live record, add, fetch |

The first four become cheaper or stay about the same with section 2's
slots. The last two cost about two operations more each. Whether the total
moves is measured, not argued:

- the profiled typing run before and after slices 2, 3 and 4, with the same
  hash seed: the frame build's steps, and the steps of the words above in
  the profile's call chains;
- Desk with Pad, profiled: the steps of Pad's load, layout and full repaint;
- switches and bytes copied, from the profile's counts of `UCTX-SAVE` and
  `UCTX-RESTORE` calls, since steps do not see copies.

A hot loop that pays for the pointer fetches the live record once before
the loop. Copying does not come back (decision 1).

### 2. Pools measured at load, growing in chunks that never move

Links by index instead of address would let a pool move when it grows. But
applications keep element addresses, from `UTUI-BY-ID` and the like, and
every step of a tree walk would pay for index arithmetic. So the design
keeps addresses and grows pools in chunks that never move.

**Element slots.** Each element takes one 256-byte slot. It holds UIDL's
record and a part the backend registers:

| Bytes | Owner | Holds | Today |
| --- | --- | --- | --- |
| 0-127 | UIDL | the element record | `liraq/uidl.f:319-336` |
| 128-135 | UIDL | the element's revision | `_UDL-REVS`, 363-368 |
| 136-231 | UIDL-TUI | the sidecar, 96 bytes | `_UTUI-SIDECARS`, `tui/uidl-tui.f:122-124` |
| 232-239 | UIDL-TUI | the widget's revision when last painted | `_UTUI-WREVS`, 125-128 |
| 240-255 | UIDL-TUI | the mounted source's generation and next key | `_UTUI-MC-SOURCES`, 4350-4354 |

That is the 256 bytes an element takes today across five arrays, so memory
per element does not change. UIDL-TUI registers its part once, before any
document exists (`UIDL-ELEM-EXTENSION!`, proposed). UIDL treats those bytes
as opaque and zeroes them with the record. They hold the TUI backend's
state only, never rich-terminal storage. A slot's size is UIDL's 136 bytes
plus the registered part, rounded up to a power of two: with UIDL-TUI's 120
bytes it is exactly 256, so index to address is a shift, and address to
index a mask and a shift. After its slots, each chunk keeps 16 bytes for
each slot, for two marks only a pass uses: the paint's link in its list of
deferred elements, and the resolved walk's visit mark. Keeping them apart
keeps the slot at 256 bytes.

**Chunks.** A pool is a short list of chunks. Each entry holds a chunk's
address, its first index and its count. The first chunk comes from the scan
at load, and a later chunk doubles the pool. Chunks never move. The list
doubles when it fills, so it sets no limit. Index to element finds the chunk
whose range holds the index: one compare for a one-chunk document, one more
for each chunk after. Element to index tests the chunks the same way. Loops
in pool order, such as `UIDL-VALIDATE`, the menubar count, the walk's
completeness check and `UTUI-RESOLVED-TYPE-EACH`, run chunk by chunk.
Indices stay append-only (decision 3), so an index stays an element's
identity, as `docs/liraq/uidl.md:86-99` promises and root facts rely on.

**Measuring at load.** Before the parse, one pass over the text counts what
the document needs: its start tags, the attributes in each tag, the bytes of
their names and values, and its `id=`, `key=` and `do=` attributes. The
pass skips comments and processing instructions. Its counts are upper
bounds, since an `id`, `role`, `arrange` or `bind` attribute takes no node.
The parse then needs nothing more, so it takes its chunks before it starts
and none during it. For Pad's document the pass finds 87 elements, at most
179 attribute nodes (160 are used), about 2,000 string bytes (1,938 are
used) and 18 IDs. The first string chunk takes what was measured and half
again, since values grow at
runtime, as Pad's status text does. Every other first chunk takes what was
measured.

**Attributes and strings.** Attribute nodes live in chunks too. A removed
attribute's node goes on a free list; an attribute has no identity outside
an iteration, so a node can be reused. Rooms keep today's rule: a value's
first room is its length, and a longer value takes twice the old room or its
own length (`liraq/uidl.f:1111-1123`). A room a value outgrows, and the
rooms of a removed attribute, go on a free list kept by size class. A new
room takes a freed one of its class or larger before it takes from a chunk.
A room never crosses chunks: one larger than the newest chunk's free tail
opens a chunk of at least its size. One attribute's rooms still add up to
less than four times its longest value, and the rooms it outgrew now serve
other values. `_UDL-SPOS` goes, and `UIDL-USAGE ( -- elements attributes
string-bytes )` (proposed) reports use.

**IDs.** The table holds element addresses only. Each element already holds
its ID (`UE.ID-A`, `UE.ID-L`), so the array of copies goes. The table's size
is the smallest power of two at least twice the ID count, and at least 8.
The hash stays FNV-1a masked by the size (`liraq/uidl.f:492-498`). A removed
element is zeroed (1099), so it matches no ID, and its slot acts as a
tombstone: a lookup probes past it, and an insert may take it. So
`UIDL-BY-ID` no longer returns a removed element. An insert that would fill
the table past half builds a table twice the size, inserts the live entries
again and then gives the old table back. A refusal keeps the old table and
fails the insert. IDs come only from the parse today, so the table a load
builds is in practice final. A full table sets an error.

**Shortcuts.** The pass that registers them at load (`_UTUI-WIRE-SUBS`,
`tui/uidl-tui.f:2806-2830`) counts the `key=` elements first, takes an array
of that size, and fills it in the same order, so the first match still wins
(989-1003). An element added later registers no shortcut, as now.

**Actions.** The arena's first size comes from the document's `do=`
attributes, which name the actions its application registers. It doubles
when the application registers more, and keeps its layout: entries from the
front and names from the back (820-848). Entries hold name offsets, so
growing moves the names and adds the growth to each offset. When the
context cannot grow the arena, `UTUI-DO!` throws. Applications register
their actions as they start (Pad's `PAD-INIT-CB`, `pad.f:2318-2464`), and the
host rolls back a launch that throws.

**Overlays.** The paint's first pass links each deferred element into a list
kept in z order, with ties in tree order, which is the order today's sort
gives (`tui/uidl-tui.f:3051-3074`). The second pass walks the list. There is
no table, nothing is allocated, and nothing is dropped.

**Walk marks.** The resolved walk marks each element it visits with the
walk's number, from a count that only rises, so nothing is cleared before a
walk (today 6347). That removes repeated work, and the proof is that a mark
equals the current number only if this walk set it. The completeness check
reads the marks (6504-6511).

### 3. What a refusal does

- **At load.** If the memory source refuses a first chunk, the load gives
  back what it took and fails with `UIDL-E-NOMEM` (proposed). That code
  replaces `UIDL-E-FULL`, `UIDL-E-STR-FULL` and `UIDL-E-ATTR-FULL`, which no
  longer describe anything (`liraq/uidl.f:84-91`). The host reports the
  failure as `AHOST-LAUNCH-E-CONTEXT` (`host.f:838`), which Desk already
  reports as `DESK-LAUNCH-E-CONTEXT` (`desk.f:880`), and not as a malformed
  document.
- **At runtime.** A growth that is refused leaves the document as it was.
  `UTUI-ADD-ELEM` returns 0, as its contract says. `UIDL-SET-ATTR` keeps the
  old value, and a new attribute is not added. Each call reports its own
  outcome through `UIDL-ERR`, and no error makes a later call refuse.
- **In paint, layout and capture.** Nothing is taken from the budget.
  Overlay links and walk marks live in the chunks, and capture spans belong
  to their callers.
- **Reporting.** Each context counts its refusals (`UCTX-REFUSALS@`,
  proposed). The host reads the count after a slot's code runs, as it reads
  `_UTUI-NEEDS-PAINT` today (`tui/applet-host/host.f:1255-1260`), and Desk
  shows a notice that names the application.

### 4. Budgets

**The documents' memory source.** Desk owns one memory source for its
documents (`utils/memory-source.f`), over the system allocator, with the
total budget. It lends it to its host (`AHOST-DOCUMENTS! ( memory host -- )`,
proposed, beside `AHOST-REGISTRY!`). Each context gets a memory source of
its own, whose allocator is the parent's `MSRC-ALLOC` and whose budget is
the ceiling for one document. `MSRC-ALLOC` and `MSRC-FREE` have exactly the
stack effects a memory source's allocator and release need
(`memory-source.f:11-14`). A context's `MSRC-HELD@` is what its document
holds. Desk's rich-path source (`tui/desk-apt1.f:353-354`) stays apart, so
documents and frames cannot starve each other.

**Who sets it.** Desk's system settings on the settings disk, which only the
host changes (`tui/desk-system-settings.f:1-10`), gain two keys:
`[desk.documents] memory-bytes` and `document-bytes`. When a key is missing,
Desk derives it from the memory free when it starts. That measure must
count extended memory, which `HEAP-FREE-BYTES` alone misses. Today only the
rich composition reads these settings, so plain Desk reads the two keys as
well. The defaults are decision 5.

**How it narrows.** Three levels apply, from the device down:

1. the device: the total for all documents;
2. the document: the ceiling, the same for every application and for Desk's
   own screens;
3. the content: a document takes what its scan measured, and grows only
   when it changes.

A manifest could later ask for less than the ceiling, never more. Nothing
needs that yet, so it is not built. A standalone application and the tests
use a source with no budget, which a memory source reads as "the allocator
is the only limit" (`memory-source.f:13-14`).

### 5. Desk's catalog and what its 32 sizes

- **Installed applications.** A growable array in Desk's state, with its
  address, count and capacity, replaces the 32-cell field
  (`desk.f:363-364`). `DESK-INSTALL` doubles it when full, and a refusal
  returns `CREG-E-NOMEM` (`runtime/registry.f:14`).
- **Built-ins and startup launches.** Both lists grow. A refusal stops the
  boot with a message instead of dropping an application (`desk.f:230,
  3071-3074`).
- **The catalog.** Its live and candidate tables are sized from the row
  count and grow on insert (`app-catalog.f:164-168`). Its codec buffer
  follows the row count when it encodes, and the file's length when it
  decodes; decoding already demands the exact length
  (`docs/tui/app-catalog.md:4-7`). `ACAT-MAX` goes. The row layout stays,
  since its field limits are format rules shared with manifests. The file
  keeps version 1: nothing released reads the old bound.
- **Component registry.** Its type and instance arrays double when full.
  Callers reach them only through `CREG-TYPE-NTH` and `CREG-INST-NTH`
  (`runtime/registry.f:39-45`), so the arrays may move. The resource owner
  pool checks counts against the registry's capacity instead of the two
  maximums, and proves the registry apart through a registry word that
  covers its header and its arrays.
- **Visible tiles.** The buffer is sized from the visible slot count at each
  relayout (`desk.f:635-648`), so no slot is left out.
- **RUHA's document records.** They grow when a document attaches, from
  RUHA's memory source, as 9a.4 grows its banks. Today Desk carves 32
  (`desk-apt1.f:299-300`), and a 33rd document is refused at attach
  (`uidl-hybrid-adapter.f:1402`), so CELL shows it.
- **The screen producer's documents.** The capacity grows with the
  snapshot's directory, as the producer's other capacities do
  (`hybrid-screen-producer.f:9519-9545`), from a first capacity of one
  (3788-3797). Today it stays at the 32 Desk passes.
- **The transmit buffer.** Decision 6.

### 6. What 9a.4 leaves to this plan

9a.4 grows RUHA's banks from Desk's memory source, doubling a family's
spans when a build runs short of room. These uses of UIDL's limits outlast
it:

- RUHA's work spans: the menu capture's work holds `_UTUI-MAX-ELEMS`
  entries, its text work `_UCTX-STRS-SZ` bytes, and the collections' capture
  work is sized for `_UTUI-MAX-ELEMS` elements (`_RUHA-G-DERIVE`). When
  slices 4 and 5 remove those constants, these spans follow the largest
  live document instead, growing as the banks do when a capture reports its
  work too short;
- the product overrides `APT1-DESK-*-NATIVE-CAPACITY`, which since 9a.4
  bound only the transport's frames, go with the aggregates they default
  to;
- RUHA's document records, which Desk lends, one for each of
  `_DESK-MAX-INSTALLED`, and the transmit buffer move in slice 9.

### 7. How the choices follow the rules

- **Production-scale limits.** Each limit in the classification table is
  either an interface or format rule, kept at production size, or a
  resource bound, made dynamic.
- **Capacity design.** The bounds left are the caller's: the memory source
  each document is lent, and the payload the terminal negotiated.
- **Negotiated capacity.** Each pool asks for what its document measured
  and grows when the document grows. No first size is a guess.
- **Real device first.** The largest gain, the copy on every switch, shows
  only in cycles and bytes. It is measured in those terms, and it comes
  first in the order.
- **True redundancy.** The copy, the saved paint scratch and the walk's
  clearing are removed with proofs. The sidecar offset changes a layout and
  removes no check. One check is added.
- **The full capability.** The plan covers every per-document table, the
  catalog, the registries and the transmit buffer, and it reclaims
  attribute and string storage now.
- **KDOS traps.** Risk 6.

## Slices

Each slice sends what it sent before, and is committed once it is green.

### Slice 0. Measure

No source change. On the commit after 9a.4:

- switches: `UCTX-SAVE` and `UCTX-RESTORE` calls for each typed frame
  (typing run, profiled), and for each second of an idle Desk with Pad,
  Daybook and Sound Lab (profiled). Bytes are calls times what each call
  copies; cycles follow by the RTL rule, labeled as an estimate;
- each document's use at load and its highest during the canonical journey:
  elements, attribute nodes, string bytes, IDs, shortcuts, action bytes, and
  the most overlays one paint deferred. A probe that is not committed prints
  them from each context into the final guest diagnostics;
- baselines: a typed letter's frame build; Pad's load, layout and full
  repaint (Desk with Pad, profiled); memory held: contexts × 115,968, the
  transmit buffer, and the dictionary pools.

Record: `local_testing/evidence/uidl-capacity-0-<date>.md`.

### Slice 1. Nothing is lost silently at today's sizes

- `ASHELL-LOAD-UIDL` reads the file's size (`VFS-SIZE`,
  `utils/fs/vfs.f:1945`), takes a buffer of that size and reads all of it,
  and refuses a file whose read runs past that size (`tui/app-shell.f:
  695-750`). The slot keeps the buffer for its life (`host.f:600-601, 864`),
  though nothing found reads it after the parse, which copies every string
  it keeps. If a check confirms that, the buffer goes back right after the
  parse.
- A refusal is reported instead of dropped. A load whose shortcuts do not
  fit fails with an error. `UTUI-DO!` throws when the arena is full. A type
  name that does not fit fails its registration with `UIDL-E-REG-FULL`. The
  validation report counts every error, though it keeps 16 until slice 10.
- `UIDL-SET-ATTR` keeps the old value when it cannot get room.
- `_UDL-ERR`'s refusal of new attributes stays inside the parse. At runtime
  each call reports its own error.
- `UIDL-REMOVE-ELEM` takes its element's ID out of the table, and a full ID
  table sets an error.

The overlay table cannot fill with today's documents, which slice 0 checks;
slice 4 removes it. Sends: the same, since no current document reaches a
limit.

Tests: for each refusal, a unit test that fills its table one past its size
and checks the refusal and that nothing else changed; a 9 KB document that
loads whole; a removed element whose ID no longer resolves; every test file
that loads `liraq/uidl.f`, `tui/uidl-tui.f` or `tui/app-shell.f`; the
ratchet. Runs: the typing run, Desk with Pad, the canonical journey with the
shadow check, and safe mode.

### Slice 2. UIDL's document is a record behind a pointer

- `liraq/uidl.f`'s counters and pools become a document record, at today's
  sizes, taken from the system allocator as the context is today
  (`UIDL-DOC-SIZE`, `UIDL-DOC-INIT`, `UIDL-DOC-USE`, `UIDL-DOC-FREE`,
  proposed). Every `_UDL-` pool and counter is reached through the live
  document.
- UIDL-TUI's context holds a document, and `UCTX-RESTORE` selects it.
  `UCTX-SAVE` copies only UIDL-TUI's part, so a switch moves 70,032 bytes:
  UIDL-TUI's 34,816 bytes of pools and 25 variables, twice (calculation).
- The write check, the default document, and `UIDL-STORAGE-DISJOINT?` over
  the live document.
- UIDL's pools leave the dictionary.

Proof: The design, section 1, for UIDL's half. Sends: the same.

Tests: every test file that loads `liraq/uidl.f`;
`test_uidl_semantic_structure.py:98-104`; new tests: two documents used in
turn keep their own addresses; a write to an element of a document that is
not live is refused and changes neither document; the ratchet. Runs: the
profiled typing run; Desk with Pad, Daybook and Sound Lab; the journey with
the shadow check; safe mode.

### Slice 3. UIDL-TUI's context is a record; a switch copies nothing

- UIDL-TUI's variables become fields of its context record, and its six
  tables, at today's sizes, live in the record's block.
- `UCTX-SAVE`, `ASHELL-CTX-SAVE`, `AHS-CTX-SAVE` and their calls go
  (`tui/app-shell.f:168-178`; `host.f:117-118, 403, 486, 506, 589, 875`).
  `UCTX-LIVE-DISOWN` keeps its checks. Paint scratch leaves the context.
  `UCTX-TOTAL` goes, and `UCTX-STORAGE-DISJOINT?` replaces the span tests.
- Each context gets a memory source of its own, with no budget until slice
  8, and a refusal count.
- `docs/tui/uidl-tui.md`, `app-shell.md`, `applet-host.md` and
  `applets/desk/desk.md` describe the record.

Proof: The design, section 1. Sends: the same.

Tests: `test_uidl_resolved_projection_structure.py`,
`test_uidl_retained_architecture.py`, `test_uidl_revisions.py`,
`test_shell_snapshot.py`, `test_uidl_collection_snapshot.py`,
`test_applet_host.py`, `test_app_shell_dialog_hosting.py` and
`test_desk_host_characterization.py`, whose allocation fault moves to the
context's first chunk; every test file that loads `tui/uidl-tui.f`,
`tui/app-shell.f`, `tui/applet-host/host.f` or `tui/shell-snapshot.f`; the
ratchet. Runs: the profiled typing run; the profiled idle Desk with Pad,
Daybook and Sound Lab, where the bytes copied should now be zero; the
journey with the shadow check; safe mode. Record: switches and steps,
before and after.

### Slice 4. Elements in measured chunks

- Element slots, the chunk list, the scan for elements, and the words from
  index to address and back.
- Every computation of an element's address from its index goes through
  those words: `liraq/uidl.f:428-475`; `tui/uidl-tui.f:166-172, 2859,
  4423-4424, 6504-6511`; `tui/uidl-root-facts.f:92-99, 232-236`;
  `tui/uidl-collection-snapshot.f:802`. A module that loops inside an
  observation uses a form with no guard of its own, as the resolved-tree
  visitors do: in a guarded build a guarded call costs 372 steps where the
  work alone costs 49 (`docs/pdf/textstr.md:39-43`).
- `_UDL-MAX-ELEMS`, `_UTUI-MAX-ELEMS`, `_UTUI-ELEM-BASE` and the checks on
  them go (`tui/uidl-tui.f:1253, 4518, 4785, 4868, 4942, 6153, 6515, 6519,
  6605, 6609, 7183, 7185, 7364, 7786, 7787, 7971, 7972`;
  `uidl-collection-snapshot.f:957`).
- Overlay links and walk marks move into the chunks.
- Desk, File Explorer and Pad set styles through a public `UTUI-STYLE!
  ( fg bg attrs elem -- )` (proposed), which counts the change.

Sends: the same; indices and pool order do not change.

Tests: every test file that loads `liraq/uidl.f`, `tui/uidl-tui.f`,
`tui/uidl-root-facts.f`, `tui/uidl-collection-snapshot.f`, `desk.f`,
`fexplorer.f` or `pad.f`; `test_uidl_mounted_association.py:53`; new tests:
a generated document of 2,000 elements loads, lays out, paints off screen
and has its families captured; `UTUI-ADD-ELEM` past the first chunk opens a
second, and every earlier address and index still answers; a source that
refuses the second chunk leaves the document as it was. The ratchet's
`uidl.elements` entry goes. Runs: the profiled typing run; Desk with Pad,
profiled; Desk with File Explorer; the journey with the shadow check; safe
mode. Record: the steps of the changed words, and the memory each context
holds.

### Slice 5. Attributes and strings in measured chunks, with reuse

Attribute chunks, string chunks with first sizes from the scan, the free
lists, and `UIDL-USAGE`. Sends: the same.

Tests: `test_uidl.py:1195-1225` and `test_uidl_menu_checked.py:96-104` read
`UIDL-USAGE`; new tests: a value that grows and shrinks a thousand times
holds less than four times its longest; a removed attribute's rooms serve
the next value; a refused room keeps the old value; every test file that
loads `liraq/uidl.f`. The ratchet's `uidl.attributes` entry goes. Runs: the
typing run; Desk with Pad, and with the Agent, which sets attributes in 13
places (`tui/applets/agent/agent.f`); the journey with the shadow check;
safe mode.

### Slice 6. IDs sized from the document

The ID table as section 2 describes it. Sends: the same.

Tests: a document with 500 IDs; a removed element's ID; a duplicate ID,
still refused; growth by rehash, and a refused rehash that keeps the old
table; every test file that loads `liraq/uidl.f`. Runs: the typing run; Desk
with Pad; the journey with the shadow check; safe mode.

### Slice 7. UIDL-TUI's tables measured

Shortcuts sized at load, a growing action arena, and the subscription table
removed (decision 4). After this slice nothing per document is fixed.
Sends: the same.

Tests: `test_uidl_retained_architecture.py:363-378`, which pins the arena's
constant; a document with 200 shortcuts and 100 actions; a refused arena
that rolls a launch back; every test file that loads `tui/uidl-tui.f`.
Runs: the typing run; Desk with each of the ten applications; the journey
with the shadow check; safe mode.

### Slice 8. Budgets

The documents' memory source, each context's own source with its ceiling,
the two settings keys, `AHOST-LAUNCH-E-CONTEXT` for a refused load, and
Desk's notice. Sends: the same, unless a budget refuses.

Tests: the settings keys and their defaults; a budget smaller than Pad's
document refuses its launch, Desk says so, and the documents' source then
holds what it held before, by `MSRC-HELD@` and by the full free measure; a
runtime refusal keeps the old value and shows one notice. Runs: Desk with
Pad, with the default budget and with a small one from a test settings
disk; the journey with the shadow check; safe mode.

### Slice 9. Desk's catalog and what its 32 sizes

Section 5's changes, with the transmit buffer by decision 6. If decision 6
is (a), MegaPad's transport change lands first, in its own commit there.
Sends: the same.

Tests: the catalog's tests with 40 rows (encode, decode, publish, recovery);
registry tests with 100 types and 200 instances;
`test_desk_host_characterization.py`; the resource owner pool's tests; RUHA
attach and producer tests with 40 documents; every test file that loads a
changed module. The ratchet's Desk and registry entries go. Runs: Desk with
Pad and the launcher; the journey with the shadow check; safe mode.

### Slice 10. The remaining fixed tables

The type registry grows: its size and hash mask come from the table, not
from 64 and 63 (`liraq/uidl.f:150-245`), and its name pool grows. The
validation report keeps every error (889-905). `docs/liraq/uidl.md` loses
its tables of fixed pools. Tests: every test file that loads
`liraq/uidl.f`. Runs: the typing run.

## Order and checks

The slices run in their numbered order. Slice 1 makes refusals honest
before any size changes. Slices 2 and 3 come before growth (decision 8).
Slices 4 to 7 remove the fixed per-document tables, slice 8 bounds what they
may take, and slices 9 and 10 do the rest.

| Slice | Content | State |
| --- | --- | --- |
| 0 | Measure | proposed |
| 1 | Nothing lost silently at today's sizes | proposed |
| 2 | UIDL's document behind a pointer | proposed |
| 3 | UIDL-TUI's context behind a pointer; no copying | proposed |
| 4 | Elements in measured chunks | proposed |
| 5 | Attributes and strings, with reuse | proposed |
| 6 | IDs | proposed |
| 7 | UIDL-TUI's tables | proposed |
| 8 | Budgets | proposed |
| 9 | Desk's catalog and what its 32 sizes | proposed |
| 10 | The remaining fixed tables | proposed |

For each slice:

- every test file that loads a file the slice changes, found by searching
  for the file's name, each run in its own pytest process, with `TMPDIR`
  under `/dev/shm` and `PYTHONPATH` naming the MegaPad worktree;
- the refactor ratchet, with the slice's capacity entries and hashes updated
  in the slice's own commit;
- the slice's runs, one at a time, within the 900-second watchdog and the
  3.5 GiB guard, with output under `/dev/shm`, `--screen-profile` only where
  the slice measures, and the same hash seed for any comparison;
- no emulator smokes; the device estimates rest on counted switches and the
  RTL rule.

At the end: the whole UIDL and rich test set, one file a process; Desk with
each application; the journey with and without the shadow check, and in
safe mode; and one record for the plan.

## Memory and expected effect

| | Today | After (estimate) |
| --- | ---: | ---: |
| Bytes copied a switch | 231,904 | 0 |
| RTL cycles a switch | at least 927,616 | 0 |
| Copying on an idle Desktop with Daybook and Sound Lab | at least 18.6 ms of every 50 ms | 0 |
| Pad's context | 115,968 | about 40,000 |
| A Desk screen's context | 115,968 | about 3,000 |
| UIDL's and UIDL-TUI's pools in the dictionary | 115,968 | 0 |
| Transmit buffer | 917,648 | the largest frame and half again (decision 6) |
| A typed letter's frame build | slice 0's baseline | about the same, measured in slices 2 to 4 |
| One document | 256 elements, 512 attribute nodes, 12,288 string bytes, 64 shortcuts, 1,536 action bytes, 32 overlays a paint | its budget |
| Installed applications | 32, fewer in practice | memory |

The first column is calculated from source, except the RTL and idle figures,
which are estimates. Pad's estimate adds 87 slots and their marks (23,664
bytes), 179 attribute nodes (8,592), about 2,000 string bytes and half
again, a 64-slot ID table (512), 51 shortcuts (1,632), an action arena of about 2 KB,
and about 1 KB of record.

## Risks

1. **The pointer costs steps on hot paths.** Each document variable costs
   about two operations more. Slices 2 and 3 measure it on the typing run
   and on Pad's repaint, and a loop that pays fetches the record once.
2. **Writes through old addresses.** Once storage is per context, a write to
   another context's element would leave pointers across contexts. Slice 2
   adds the check to every write word in the commit that makes UIDL's pools
   per document, with a test that writes to a document that is not live.
3. **Use after free.** A context's chunks go back when its slot closes. The
   host runs the application's shutdown before the final detach
   (`tui/uidl-tui.f:5644`), and the write check refuses an element of a
   freed context, since it lies in no live chunk. A read through such an
   address stays the caller's fault, as for any freed block.
4. **Proof cost follows placement.** Chunks come from extended memory and
   can land between other blocks. A proof over blocks with other storage
   between them splits and costs more, which is why Desk carved all of
   RUHA's storage in one block until 9a.4 (`desk-apt1.f:388-394`); since
   then RUHA's banks lie in a block of their own. Storage from a memory
   source needs no per-frame proof in normal mode, so this touches safe mode
   and tests; slice 4 measures safe mode's frames.
5. **Allocation while a module loads.** It would keep the module out of a
   compiled shard. The default document is created on first use.
6. **KDOS traps.** `FREE` returns no ior, so chunks go back through
   `MSRC-FREE` with their sizes. `0 ALLOCATE` fails, so an empty pool takes
   no chunk. `ARENA-NEW` builds at `HERE` for good, so contexts never use
   it. `HEAP-FREE-BYTES` misses extended memory, so leak tests read
   `MSRC-HELD@` and the full free measure.
7. **Large documents.** Some captures size their work by the whole element
   count (`UMSN-WORK-BYTES`, `UCSN-WORK-BYTES`), and the walk checks every
   element. For documents far larger than today's, that work follows the
   document, not the family captured. Slice 4's large test measures it;
   indexing work by a family's own roots would be a change of its own.
8. **Many small chunks.** First-fit allocation can scatter them. Doubling
   keeps a pool to a few chunks, and the scan gives most documents one
   chunk a pool.
9. **Tests missed.** A slice changes files that dozens of tests load. Each
   slice finds them by name, with plain `grep` under `local_testing`, and
   runs each file alone.
10. **Two repositories.** Decision 6's option (a) changes MegaPad's
    transport, which lands there first.
11. **Private reaches.** Applications write UIDL-TUI's private sidecar
    style, and other modules read `_UTUI-FOCUS-P`, `_UTUI-NEEDS-PAINT` and
    `_UTUI-MENU-OPEN`. Those names keep working as fields of the live
    context. The style writes move to a public word in slice 4.

## Not in this design

- RUHA's banks, which 9a.4 grows; its work spans are section 6's.
- The state tree's and LEL's own tables (`liraq/state-tree.f`,
  `liraq/lel.f`).
- Widgets' content limits, such as a materialized input's 256-byte buffer,
  which aborts when it cannot be allocated (`tui/uidl-tui.f:3637-3651`).
- Desk's service namespace (16), the resource registry (64), the request bus
  (32) and the shell's deferred actions (16): registries and queues not tied
  to documents or the catalog. Each needs the same classification.
- The receive buffer, 8,192 bytes (`tui/desk-apt1.f:39-40`).
- Applications' own limits in the ratchet, such as Pad's buffers, Daybook's
  entries and Grid's sheet.

## Decisions

Open on 2026-10-30:

1. **Document variables: through the live record, or copied.** About 25
   variables a document keeps (its counts, and its focus, region,
   projection, menu and dialog state) can be fields reached through the live
   record, or stay globals copied in and out at each switch, about 400
   bytes. Through the record, no copy and no save step remain, so the live
   state can never differ from a saved one; each access costs about two
   operations more. Copied, the accesses stay as they are, and a switch
   moves a fixed few hundred bytes that do not grow with capacity. Options:
   (a) every variable through the live record; (b) variables copied, pools
   by pointer. Recommendation: (a), with slices 2 and 3 measuring it.
2. **Where per-element state lives.** (a) One 256-byte slot holds UIDL's
   record and the backend's part: a sidecar or revision is an offset from
   its element, each chunk is one allocation with one list, and an element
   takes the 256 bytes it takes today; UIDL holds bytes it does not
   interpret. (b) Parallel arrays that share the element chunks' boundaries
   keep the modules apart, at the cost of a lookup in each array.
   Recommendation: (a).
3. **Reusing a removed element's slot.** (a) Indices stay append-only, as
   the UIDL contract says (`docs/liraq/uidl.md:93-95`): a removed slot stays
   until the document resets, and the budget bounds the waste. (b) A free
   list reuses slots, with a generation added to root keys, so that a reused
   index never joins a control of the element it replaced. No application
   adds and removes elements today. Recommendation: (a) now, and (b) when an
   ordinary use needs it.
4. **The subscription table.** Nothing calls `UIDL-NOTIFY`, and no document
   uses `bind=`, yet the table is filled at load and copied with every
   context. Bound state marking its own elements lies outside
   FRAMES-FOLLOW-CHANGE. Options: (a) remove the table, `UIDL-SUBSCRIBE`,
   `UIDL-NOTIFY` and `UIDL-RESET-SUBS`; (b) keep it, sized from the
   document's `bind=` elements at load. Recommendation: (a). A later design
   can find bound elements by the `bind` field each element already holds.
5. **The budget's defaults.** Options: (a) Desk's settings keys, with
   defaults from the memory free when Desk starts, proposed as a sixteenth
   of it for one document and a quarter for all documents: about 11 and 44
   MiB on the simulated rich Desktop, which has about 178 MiB free once
   loaded (FRAMES-FOLLOW-CHANGE, Memory); (b) fixed constants; (c) no budget,
   the allocator alone. (b) is a guessed maximum, and (c) lets one document
   starve Desk. Recommendation: (a), with the fractions themselves settings,
   and no per-application table until an application needs one.
6. **The transmit buffer.** It holds one frame, and today follows UIDL's
   aggregates: 917,648 bytes. The transport borrows it for the whole session
   (MegaPad `rich-terminal.f:976-1004`). Options: (a) grow it to the largest
   frame Desk sends and half again, never past the terminal's negotiated
   maximum payload, which needs a MegaPad word that swaps the buffer while
   no frame is pending; (b) fix it at the largest frame APT-1 allows, 1 MiB
   and its header, an interface bound held for good; (c) a Desk constant.
   Recommendation: (a), with (b) as a bridge if the MegaPad change has to
   wait.
7. **Sizing at load: a scan, or growth during the parse.** (a) One pass over
   the text gives each pool one exact chunk; Pad's text is 3,693 bytes. (b)
   Growth during the parse spreads most documents over several chunks,
   which every index lookup then walks. Recommendation: (a).
8. **Contexts before growth.** (a) Slices 2 and 3 make contexts records at
   today's sizes, and slices 4 to 7 then grow the pools. (b) Growth first.
   (a) brings the largest device saving first, needs no growth, measures the
   pointer's cost alone, and lets growth land in storage that is already per
   context. Recommendation: (a).
