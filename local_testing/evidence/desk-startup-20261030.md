# Desk startup: the free-space search and the repeated cell screen — 2026-10-30

This note records two findings about the guest work Desk does between starting
and taking its first typed key. The first is fixed: MP64FS looked for free disk
space one sector at a time, and Desk's first-boot catalog writes spent most of
their steps there. The second is traced but deliberately left unfixed: Desk
writes and sends its complete cell screen twice at startup, and the second copy
changes nothing the terminal shows. Its fix waits for the frames-follow-change
work, which owns the rich path.

Both findings come from profiled typing runs
(`physical_typing_cadence.py run --screen-profile`, with full call chains from
`MEGAPAD_PROFILE_CHAINS=0 MEGAPAD_PROFILE_CHAIN_DEPTH=0`). Steps are the native
simulator's semantic steps. The profile charges them at host boundaries roughly
every 65,536 steps, so figures below about 0.1M carry noise. Times are the
simulator's, not a device's. "Startup" means the profile from Desk's start to
its first typed-letter frame.

## Bindings

| Binding | Value |
| --- | --- |
| Akashic | `1e9a6a8a8dab9d5cb33743b2b9901722bb85d623` (tree `4b7d9baa367f7654877dac3f04079ff865000538`) |
| MegaPad | `a1a97b50f9dc15fa2f0573f0d4889496476f5566` (tree `cc3969861f323f4f4d91f40f46c4dc6d80651d2c`) |
| Native extension SHA-256 | `70f973571d88a580584ff748ded12d5bfb57d1eca00443a063d6650056220caa` |
| Font | DejaVuSansMono.ttf, SHA-256 `b4a6c3e4faab8773f4ff761d56451646409f29abedd68f05d38c2df667d3c582` |

Both trees were clean and unchanged at exit.

## The free-space search, fixed in Akashic 1e9a6a8a

Before the fix, `_VMP-FIND-FREE` tested one sector at a time from the data
start, and every test re-ran the whole bitmap view check through
`BITSET-TEST?`. The canonical Desktop image keeps the system sources in its
first data sectors: of its 65,536 sectors, data starts at 29 and the first free
sector after boot is 14,725, so each search walked about 14,700 used sectors.
On a fresh disk Desk binds each built-in applet into its catalog with a replace
transaction of its own, and each transaction creates and grows files. 1e9a6a8a
makes the search one call to `BITSET-FIND-CLEAR-RUN?`, which checks the view
once and passes full bitmap bytes eight sectors at a time, and applies
deferred frees a cell at a time.

| Steps at startup | Before | After |
| --- | ---: | ---: |
| `_VMP-FIND-FREE` | 59.24M | 1.51M |
| `_DESK-CATALOG-INIT` | 63.64M | 7.47M |
| `DESK-INIT-CB` | 87.23M | 29.43M |
| `_VMP-APPLY-DEFERRED-FREES` | 4.06M | 0.20M |
| `_VFS-INODE-IN-FREELIST?` (unchanged) | 2.95M | 3.01M |

The before column was read from a profiled typing run that the
frames-follow-change session made earlier the same day on its copy of that
branch; a second run of that session put 59.18M in the search. That session
has since deleted both profiles, so these are the figures read from them then.
The files involved (`utils/bitset.f`, `utils/fs/drivers/vfs-mp64fs.f`,
`utils/fs/vfs.f`, `tui/app-catalog.f`) were the same on both branches, so the
search's own cost compares fairly. Startup totals do not, because the rich path
differs: 211M on that branch, 177M on main after the fix. In simulator time the
catalog phase took about 1.2 s before and 0.3 s after.

The same search ran whenever a file was created or grew while Desk ran. Before
the fix, the Agent saving its conversation from a Desk tick spent about 2.8M
steps in it, more than a typed-letter frame on that branch (about 2M).

KDOS's own `FIND-FREE` has the same per-sector pattern, and its `BIT-MASK`
builds each mask with a loop of doublings. Desk never writes files through
KDOS, so neither is on Desk's path. Every `kdos.f` edit moves the source pins
that MegaPad's simulator tests share, which the frames-follow-change branch has
moved for its own KDOS change, so this change is scheduled for after that
branch lands, when the pins are recomputed once.

`_VFS-INODE-IN-FREELIST?` is a separate cost and was left alone. `VFS-SYNC`
walks the inode free list once for every cached inode slot. Testing an inode's
dirty flag first would cut the walks, but `IN.FLAGS` reads through the slot's
`D.VNODE` pointer, so that order would read through free slots' pointers; it
needs its own proof before anyone relies on it.

## The repeated cell screen, traced and not fixed

At startup Desk sends its whole cell screen, all 23,520 cells, twice:

| Time | Guest work | Sent |
| --- | --- | --- |
| 1.80–2.29 s | The setup paint writes every cell by the direct route: 15.99M steps under `SCR-FLUSH?`. | The legacy CELL snapshot (`SNAPSHOT_BEGIN` … `SNAPSHOT_COMMIT`). |
| 2.29–2.59 s | A tick, then idle. RETAINED-1 discovery completes in this gap. | |
| 2.59–2.99 s | The first loop pass writes every cell again, through the rich publisher: 22.68M steps under `SCR-FLUSH?`. | PRESENT 3: a CELL replacement with no retained part, 192,744 bytes. |
| 3.19–3.77 s | Neutral offers build the hidden replacement: about 41M steps of `RTHP-PREPARE`. | PRESENT 4: `REPLACE_START`, 115,727 bytes. |
| 4.09 s | The replacement's continuation. | PRESENT 5: `REPLACE_CONTINUE`, 160 bytes. |

The terminal's counters agree. It received 204 `CELL_SPAN` frames carrying
387,520 bytes, two full screens of 84 rows plus the typing deltas, and committed
one present whose retained mode is NONE. It accepted both screens, which hold
the same picture. The profiled runs on the frames-follow-change branch show the
same two writes, and the handoff code described below is the same blob
(`4468fde0`) on both branches.

`_APTSCB-RETAINED-HANDOFF` in `akashic/tui/screen-backend-apt1.f` causes the
second write. When RETAINED-1 becomes available after the initial snapshot, it
calls `SCR-FORCE` once. Commit 77af3573 (2026-08-30) added the call so that a
clean screen cannot leave the publisher's surface at generation zero: the
publisher records the surface only from a screen offer that reaches it, and a
clean screen makes none. `SCR-FORCE` turns the next offer into a complete
snapshot. The producer seals nothing on that offer, and
`_RTAPTSCB-AUTHORITATIVE-PREPARE` lets an unsealed producer pass in the CELL
phase, so `RTAPT-CELL-BEGIN`, finding the engine idle, opens a CELL-only
PRESENT, into which every cell is written and sent. The hidden replacement is
then built from neutral offers (cell mode NONE) through
`_RTAPTSCB-NEUTRAL-BEGIN`.

Neither contract asks for the copy. APT-1-RETAINED-1 orders startup as the CELL
snapshot and its result, discovery, owner open, resource replay, the hidden
replacement, then the reveal; until the reveal, "the committed CELL snapshot is
the complete visible terminal output" (sections 14.1 and 16.2). The Akashic
contract (`docs/rich-terminal/AKASHIC-RICH-TERMINAL.md`, section 0.1) allows
retained-only updates while CELL is unchanged and reserves complete replacement
for initial construction, reset, resize and genuinely uncertain topology.

The copy costs 22.7M guest steps and 192,744 link bytes at every startup, and
again after any soft reset that rediscovers RETAINED-1. On main that is 13% of
the 177M startup steps.

### Proposed fix

On the discovery edge, `_APTSCB-RETAINED-HANDOFF` would request a neutral flush
with `SCR-REQUEST-FLUSH` instead of calling `SCR-FORCE`. A neutral offer still
reaches `_RTAPTSCB-BEGIN`, which records the offered dimensions as surface
generation one before it takes the neutral path, so the generation-zero problem
stays solved without sending cells; in this run the neutral path already built
the hidden replacement. The change needs these checks:

- 77af3573's structural and state tests in
  `local_testing/test_rich_terminal_screen_publisher_structure.py` pin the
  forced snapshot and its one-shot behavior, and need restating for the
  request.
- A screen that changes between the snapshot and discovery must still reach
  the terminal. The screen's dirty flag offers those cells as a delta, and the
  reveal may carry a final CELL delta.
- A publisher with no producer bound refuses a neutral offer and leaves the
  request pending, where a forced snapshot went through. The surface is still
  recorded at that BEGIN, but the shell must not spin on the refused request.
- The handoff edge is cleared on soft reset, on CELL-only operation and on ANSI
  retirement; those paths must keep working with the request.

### A related cost

Full-screen CELL frames pay a per-cell rate: about 660 steps a cell by the
direct route and about 950 through the rich publisher (15.53M and 22.35M of
span emission for 23,520 cells). Each cell passes through separate calls in
the APT-1 backend, the engine and `PT-CELL`, and each of them checks it.
Startup, resize and terminals without RETAINED-1 send such frames.

## Checks

The canonical Desktop journey (`physical_desktop_acceptance.py`) passed at
the bindings above: 65 checked frames and 79 inputs in 190 s, with a peak
aggregate RSS of 589 MB. It runs every canonical applet through the changed
driver, including Daybook's task additions and File Explorer's delete step. The
profiled typing run that supplied the figures above passed in 17 s. Both runs
kept their output in `/dev/shm` and wrote nothing to the drive.

The module tests of the free-space fix are listed in the message of 1e9a6a8a.
Not run: the emulator smoke scripts, the ext4 suite and the composed Streams
emulator script.
