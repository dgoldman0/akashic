# Part 8: The occasional full refresh — 2026-10-27

Part 8 of [FRAMES-FOLLOW-CHANGE](../../docs/rich-terminal/FRAMES-FOLLOW-CHANGE.md)
bounds how long a change nothing reported can stay on the rich screen. At
quiet moments the rich terminal's owner runs a check that captures every
visible document in full and compares the capture with the snapshot the
screen was built from; a difference is reported and turns safe mode on.
The code is in ab0e4429, with a fix the physical runs found in 19b4b765. This note records the design choice, the tests
and the physical runs. All of it is simulator evidence. None of it is UART,
panel or touch evidence. Steps are the simulator's semantic steps.

## Why the refresh checks without drawing

The plan had the refresh ride a draw, build that frame by the full path and
compare it with the frame on screen. Two findings changed that before any
code was written (decision 14):

- Every draw sends a frame. The wire forbids an empty DELTA, so a draw that
  changed nothing goes out as a one-operation revision fence
  (`_RTHP-D-PLAN-REVISION-FENCE?`). A refresh that drew would send one at
  every check.
- A full build compared with the frame on screen cannot tell a missed change
  from a counted one not yet sent. Telling them apart takes the shadow
  check's comparisons at each shortcut, beside an ordinary build: about two
  builds a refresh.

The check instead compares two captures of what the documents hold, at a
moment when no paint is pending: every change counted since the screen's
last draw asked for a paint, so at such a moment the snapshot of that draw
and a live capture agree unless a change went uncounted.

## The check

`RUHA-REFRESH-CHECK` (`tui/rich-terminal/uidl-hybrid-adapter.f`) checks
the snapshot of the screen's last draw. It refuses a snapshot older than
that draw: the screen may hold a change the adapter has not captured yet.
Otherwise it captures every visible document into the adapter's spare bank,
under the snapshot's own generation, with the shadow check's full capture
(`_RUHA-B-FULL`), and compares the result with the snapshot document by
document: where each document shows, then each family's records and native
bytes. It publishes nothing. The active bank, the generation, the last draw
and its status stay as they were, and the records' flags, which a capture
stages, are put back, so the next draw's ordinary capture reuses what it
would have reused.

A difference names the family, the document's owner and slot, and, where
the family's records say which element they came from, the element's index.
UIDL's new `UIDL-ELEM-AT?` turns the index back into the element, whose id
and revision are read in its document's context. A difference only in a
data-graphics descriptor's native bytes names no element: the adapter
carries those descriptors opaquely and reads none of their native bounds.
Desk reads the application's title from the slot.

## When it runs

`tui/rich-terminal/frame-refresh.f` decides when a check falls due: once
input has been quiet for `full-refresh-quiet-ms` (1,000) after the last
input, and at least every `full-refresh-interval-ms` (5,000) after the last
check. Both are in Desk's system settings and keep their defaults when
absent or not whole milliseconds above zero. The rich terminal's owner
(`tui/app-shell-apt1.f`) runs a due check from its pass service, on a live
rich session, when the shell's new `ASHELL-PAINT-PENDING?` is false and no
part of an input event is held back. A modal key read between polls never
runs it: the application waiting for the key may have its documents half
changed. Every event the owner gives counts as input. The terminal owner
interface gained a `deadline` callback, which the shell's idle sleep now
wakes for, so an application without a tick still gets its checks.

A check that compares and finds nothing is counted. One that finds a
difference is counted as missed, keeps the session's first report and turns
safe mode on with `CHK-WHY-MISSED`; the owner's notice then names the
application, the family and the element. A check that cannot compare, such
as one against a snapshot the screen has drawn past, is counted as skipped,
and the next falls due an interval later. In safe mode no check runs, since
every frame is built in full.

## Tests

- **The plan's test.** `test_frame_refresh.py` runs the adapter's
  production words in the native simulator over a UIDL document with one
  text area, `note`, holding "aggregate alpha". The test overwrites "alpha"
  with "omega" in the buffer the text area borrows, without
  `TXTA-SET-TEXT`, so nothing counts the change and the document does not
  draw. The check finds it and names the collections family, the
  document's owner and slot, and the element `note` with its live revision.
  The adapter's held snapshot is untouched, the next ordinary capture still
  holds "alpha", as the screen would, and with safe mode on the capture
  holds "omega".
- **No false alarm.** An unchanged document matches its snapshot, and the
  next draw still reuses its slices. The same change made through
  `TXTA-SET-TEXT` and drawn matches too. A screen that drew past its
  snapshot is not checked.
- **Timing.** Against a fake clock: no check without a registered one; the
  first falls due an interval after registration and each next an interval
  after the last; input moves the quiet deadline on while the interval
  still bounds it; the quiet after input is checked once; a due check waits
  for a quiet service; a check that could not compare is skipped; a
  difference turns safe mode on, after which no check falls due; and safe
  mode keeps the reason it was given first.
- **The report** keeps the first difference and cuts names at 64 bytes.
- **The fix** (19b4b765): the refresh's service says whether a check
  ran, and the owner's service runs again after a check, and only then,
  with the pass service giving the second service's results.
- **The owner** (`test_app_shell_apt1_refresh.py`) runs a due check only on
  a live rich session whose service went well, with no paint pending and
  nothing held back; its deadline is the next check's on a live rich screen
  and -1 otherwise; and every event it gives is input. Its notice names
  the application, the family and the element, and says what it can when
  the title or the element is unknown.
- **The shell** wakes from its idle sleep at the owner's deadline, with or
  without a tick (`test_app_shell_idle.py`). **The settings** set both
  times, and absent, zero, negative, wrong-typed or malformed ones keep the
  defaults (`test_desk_system_settings.py`).

The part's test selection, 120 files covering the shell, its APT-1 owner,
the snapshot adapter, UIDL, Desk and the system settings, ran one file at a
time with `TMPDIR` in `/dev/shm`: 2,960 tests passed and 28 failed, in seven
files, and one file collected no tests. They found three faults of the
change, fixed before its commit: the new module's provided name collided
with the shadow check's within KDOS's 23-byte key, which broke Desk's image
build; the notice's new word stood after the word that uses it, which only
Desk's cold source load, compiling in file order, found, since the unit
harnesses order words by their dependencies; and the shell's doc named the
rich terminal, which the lower layers' docs keep out. Three tests pinned
what the change moved or read, and were updated: the owner's poll body, the
adapter's bank setup, and the adapter's rule that it reads no
data-graphics descriptor's native bounds, which the check now keeps.
`test_vfs_ext4.py`'s 18 failures, a MegaPad storage API mismatch and source
counts in the ext4 module, and `test_markup_progress.py`'s empty collection
are the same at 95a4b849. After the fixes the failing files, the ratchet and
the focused suites passed. Not run: the 16 emulator smoke scripts in the
selection.

## Physical runs

Every physical run went through `physical_desktop_acceptance.py` or
`physical_typing_cadence.py`, one at a time, from RAM clones of the commits
named, with output in `/dev/shm`. BASE is 95a4b849, part 7's end. From the
Streams diagnosis on, the clones also held ab19fba6, which opens the
viewers minimized and lets the screen sleep; the guest's code is the same,
so runs compared with each other ran under one viewer.

### Desk with each application

Desk with each of the ten applications ran at ab0e4429 with the shadow
check on. Nine passed, with no shadow difference, no missed change and no
check skipped:

| Application | Seconds | Shadow comparisons | Refresh checks |
| --- | ---: | ---: | ---: |
| Pad | 49.3 | 407 | 13 |
| File Explorer | 148.7 | 1,519 | 48 |
| Daybook | 137.5 | 367 | 31 |
| Agent | 75.8 | 672 | 23 |
| Sound Lab | 31.2 | 140 | 5 |
| Observatory | 38.4 | 201 | 6 |
| Small Terminal | 32.5 | 114 | 6 |
| Photo | 31.7 | 79 | 3 |
| Damaged | 28.8 | 191 | 4 |

Streams failed twice at ab0e4429, at its 300-second timeout, at the stage
where its journey ticks a source's check box and waits for it to clear: the
box stayed ticked, in CELL's cells too, so Streams never got the click. It
passed at BASE in 98.3 seconds, and at ab0e4429 with both refresh times set
to 100,000,000 ms, so that no check ran, in 100.6 seconds.

### Why the click was lost

Five more runs at ab0e4429, from a RAM copy whose guest kept diagnostic
variables for the timeout record, found the cause. The shell candidate's
lookup refused the click as stale: the screen's draw generation had moved
past the draw of the frame the terminal had acknowledged, the frame the
click was sent against. The refresh check marked no widget changed, set no
paint request and left the shell's paint state as it found it. A history of
the shell's busy passes, taken when the click was refused, gave the order:
the last pass before it ran a check, then Desk's tick, then a paint that
drew, and the click was read in the pass after. The check, about 8 million
steps, was running when the click arrived. The owner had serviced the
terminal before the check, so the click stayed in the stream for the next
pass while the tick and paint later in the same pass drew a frame in which
nothing had changed. That draw sent nothing: the frame on screen was still
the acknowledged one, now older than the screen's last draw, and the click
bound to it was dropped. The journey sends the click once.

19b4b765 has the owner run its service again after a check, so input that
came during the check reaches the application before the pass's tick and
paint. Desk with Streams then passed in 93.6 seconds, 214 shadow
comparisons with no difference and 10 refresh checks, none missed.

The stall also exposed a defect older than the refresh, which stays open: a
draw that changes nothing and sends nothing leaves input sent against the
frame on screen refused until a newer frame goes out, whatever made that
draw. The fix stops the refresh from setting that up.

### The typing run and the check's cost

At ab0e4429 the profiled typing run made two checks of 6.23 million steps
each. The typing run then ran at BASE and at ab19fba6 under one viewer,
profiled with every call chain kept and `PYTHONHASHSEED=0`. Both sent and
showed all 19 keys. The whole run took 429.7 and 435.9 million steps; the
6.2 million between them are its one check, 6.23 million steps under
`RUHA-REFRESH-CHECK`, and the frame build took 192.7 million in both. They
committed 19 and 18 DELTAs, 516,952 and 516,157 bytes. Part 8's plan put a
check at 3 to 4 million steps; it costs 6.2 million steps in the typing run
and about 8.0 million in the Desktop journey, where more documents show.

### The canonical Desktop journey

At ab0e4429 the journey passed with the shadow check, in 234.8 seconds,
4,361 comparisons with no difference and 80 refresh checks, none missed or
skipped, and without it, in 204.6 seconds and 79 checks. Profiled at BASE
and at ab0e4429 it took 204.9 and 210.2 seconds. Both committed the same
presents, 48 DELTAs, 37 STARTs, 36 CONTINUEs and one NONE, in 6,368,915 and
6,369,365 bytes. Ten windows differ by a few cells each, all in File
Explorer's list, whose size column shows the disk image's `source-NN.src`
files, and those that hold sources part 8 grew show more, such as 120K
instead of 117K. The
whole run took 3,478.7 and 4,112.8 million steps. Of the 634.0 million
between them, 637.9 million are under `RUHA-REFRESH-CHECK`, 80 checks of
about 8.0 million each, while the frame build took 2,093.6 and 2,093.5
million and the owner's deadline and the shell's paint-pending query 0.3
million together.

At 19b4b765 the journey passed with the shadow check in 185.0 seconds,
4,361 comparisons with no difference and 79 checks, none missed or skipped;
without it in 173.0 seconds and 77 checks; and in safe mode, which part 8
changes by a reason and a notice, in 308.2 seconds with no check, as safe
mode builds every frame in full.

## Files

The runs' output stayed in `/dev/shm` and was deleted once its numbers were
read, with the RAM clones of the trees they ran and the diagnostic copy. By
their shells' `write_bytes`, none of the part's 29 physical runs wrote to
the drive.
