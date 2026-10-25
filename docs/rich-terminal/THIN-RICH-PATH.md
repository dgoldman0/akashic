# A thin rich path, with a safe mode — design, 2026-10-25

Status: proposed on 2026-10-25. Nothing in it is approved, and its
decisions are open (see Decisions). Its numbers come from
[the check measurement](../../local_testing/evidence/rich-path-checks-20261025.md)
of the same day and from part 0 of
[FRAMES-FOLLOW-CHANGE](FRAMES-FOLLOW-CHANGE.md).

## Summary

A character typed into Pad on the rich Desktop costs the guest about 19
million steps a frame, and 16 million of them build the rich frame. Of those
16 million, 9.85 million are checks. Most of the rest rebuilds the whole
screen for one changed letter. Each frame passes the screen through five
whole copies: RUHA's bank, the producer's arena, its target bank, the
shell's work space and the shell's frozen bank. It builds the screen twice,
once for the applications and once more for Desk's shell, and checks it
again at each step.

This design makes the path thin in two ways.

- **Each check runs when it can find something.** State and fit are checked
  on every frame. New data is checked once, when an item changes. Memory
  layout is proved when memory is lent, allocated or grows. The checks that
  can only find a bug that wrote where it should not, today about half of
  all checking, run in tests and in safe mode.
- **The frame follows change.** One projection, fed by the change counts that
  parts 2 to 4 of FRAMES-FOLLOW-CHANGE give widgets and UIDL, lowers only the
  elements that changed into one candidate, with Desk's chrome in the same
  projection. The renderer keeps one acknowledged frame, and the changes
  themselves are the DELTA.

The full path stays, as one of two drivers over the same capture, check and
lowering code. The change driver visits the elements that changed. The full
driver visits every element, as today's path does. It builds complete
frames (STARTs), and three more things use it:

- **safe mode** runs the full driver, with every check, on every frame of an
  ordinary session, and sends its result. The screen then always shows the
  live state, whether or not a change was reported, and the rich path's own
  records are checked again on every frame.
- **the occasional full refresh** runs the full driver in normal mode at a
  bounded interval. It sends any difference it finds and reports it as a
  missed change, so a missed change can stay on screen for one interval at
  most.
- **the shadow check** (FRAMES-FOLLOW-CHANGE part 1) runs it beside the change
  driver in tests and compares the two byte for byte.

**Target:** a typed letter's frame build from 16 million steps to about 2
million. This is an estimate; each part replaces it with measurement. Safe
mode costs about what today's path costs.

## Rules

Kept from earlier work:

- The rich-terminal rules in the workspace AGENTS.md. The same applet
  sources, UIDL documents, mounted widgets and draw lifecycle serve CELL and
  rich output. One renderer-neutral projection comes from the ordinary draw
  lifecycle and covers Desk's chrome, UIDL renderers, mounted widgets and
  applet painting. The renderer owns representation, allocation within the
  caller's bounds, clipping and presentation. CELL stays the complete
  fallback. No applet gains a terminal API or scene.
- Storage starts from what the screen needs and grows on demand, by
  negotiation with the terminal where the terminal's space is concerned.
  Nothing reserves a guessed maximum.
- A missed change gives a stale screen, never an unsafe one: every item a
  frame sends has passed its first check.
- When every change is counted, the change driver sends exactly the frames
  the full driver would send. The shadow check tests this on every frame of
  every test run.

Changed:

- FRAMES-FOLLOW-CHANGE's rule that every boundary check stays at every
  boundary becomes: **each check runs at the moment it can find something
  new** (the table below). This gives up one thing in normal sessions: the
  per-frame checks that notice a bug writing where it should not. Safe mode
  and tests keep them.
- Storage the rich path takes from a memory source needs no proof that it
  lies apart from other live storage. That rests on the allocator's contract
  that live blocks do not overlap. Storage a caller lends is proved apart
  when it is lent.

## Where each check runs

The groups are those of the check measurement. Millions of steps are per
burst frame of a typed letter, as measured on 2026-10-25.

| Group | Today | Normal mode | Safe mode | Tests |
| --- | --- | --- | --- | --- |
| State and fit (0.10) | every frame | every frame | every frame | every frame |
| Item checks (1.74) | every item, every frame | each changed item, once | every item, every frame | each changed item, and every item through the shadow check |
| Handover proofs (2.95) | at every entry, several times a frame | when memory is lent, allocated or grows | every frame | every frame |
| Repeats (5.08) | every frame | off | every frame | every frame |
| Full rebuild | every frame, with some reuse | at each full refresh | every frame | every frame, beside the change driver |

The item checks a thin frame keeps are the record and text checks of the
items that changed, about 0.07 million steps for a typed letter's controls
in the measurement, and the captures' checks of the elements that changed.
Text that reaches the wire is still read once for valid UTF-8 and for the
characters the wire refuses.

Input that comes back from the terminal is checked as it is today, in every
mode: the owner, generation and frame a click or key names, and the control
it names in that frame.

## The two drivers

Both drivers use the same capture, check and lowering code. They differ in
which elements they visit and in where their result goes.

### The change driver

- **What changed.** The change driver reads the revisions that
  FRAMES-FOLLOW-CHANGE parts 2 and 3 add: each canonical widget's, and each
  UIDL element's. It also reads the shell model's revision, each document's
  geometry, visibility, focus and occlusion, and the CELL rows a draw
  changed (`ROW-DAMAGE`).
- **What the projection keeps.** For each element that projects, the
  projection keeps the revisions it last projected and the wire items they
  became (decision 4).
- **A frame.** The driver visits only the elements whose revisions moved.
  It captures each into scratch, checks what it captured, lowers it, checks
  that the items fit what the terminal accepted, and compares them with the
  items that element sent before. The items that differ, and their
  operations, go into the pending change set. Residual glyphs are planned
  once, for damaged rows only.
- **One candidate.** Desk's chrome (panes, taskbar bands and status) comes
  from the shell model through the same projection. The shell's second
  candidate, its work space and its frozen banks go. How application items
  are placed in their pane regions within one candidate needs its own look
  (part 4b).
- **The renderer.** The renderer keeps the acknowledged frame, with its items
  and input targets. The DELTA is the pending change set, so no comparison of
  the whole screen is needed. On ACK the change set is applied to the
  acknowledged frame. When a change cannot go out as a DELTA, for the reasons
  that send a START today (a refocused task, storage growth, moving pictures,
  changed instruments, changed membership), the full driver builds a START.

### The full driver

The full driver visits every element. It captures, checks and lowers each,
builds a complete candidate, and compares it with the acknowledged frame
through today's comparison, which then decides between a DELTA and a START.
STARTs, safe mode, the full refresh and the shadow check use it.

## Safe mode

**What it does.** Every frame goes through the full driver with every check
on, and the full driver's result is what the terminal receives. The screen
shows the live state of every element, whether or not anything reported a
change, and every check of the rich path's memory runs on every frame.

**What it costs.** About what today's path costs, or somewhat more, since
it reuses nothing. In the measurement today's path took 16 million steps for
a burst frame and 26 million for an isolated character, against the target
of about 2 million for a thin frame.

**How it is turned on** (decision 2):

- a Desk setting, kept across sessions, which an administrator can fix;
- a boot option;
- by itself, when the thin path meets an anomaly: a full refresh that finds a
  missed change, or a handover proof that fails. Desk then says that it is in
  safe mode, and records why. A first check that refuses outside data, such
  as a file's broken text, is not an anomaly.

**What it cannot do.** Safe mode makes the screen match what the
applications hold. It cannot make an application's own data right, and it
cannot stop a native application that means harm, since such an application
shares Desk's memory.

**Why keep it.** A missed change is silent. The old picture is valid, so
every check passes and nothing looks wrong. Suppose an approval application
shows a payment of 1,200 with an Approve button. An update from the server
changes the held amount to 120,000, through a path that, by a bug, does not
move the list's revision. In normal mode the screen keeps showing 1,200 until
that row changes again or the next refresh, and an approver who clicks
Approve approves 120,000. In safe mode the next frame is built from the held
record, so the screen shows 120,000 before anyone can act on the old figure.
Where a wrong screen costs more than the steps, such as approvals,
operations consoles or audits, safe mode is worth its cost.

A second danger is memory damage. A bug in a native application can
overwrite part of the rich path's memory, such as its record of the frame
the terminal holds, which later frames build on and which tells a click
which control it reached. In normal mode nothing checks that record again,
so the damage can spread into what the screen shows or where a click goes.
In safe mode the rich path's records are checked on every frame and every
frame is rebuilt from the live state. A check that catches the damage
refuses the frame, falls back to plain text and names the damaged structure.

## The occasional full refresh

**When.** In normal mode, once input has settled, and at least once per
refresh interval while the screen is shown (decision 3). Each is one full
build. Like every frame, it runs at the end of an ordinary draw: when
nothing has drawn, the refresh asks for one.

**What it does.** It runs the full driver into scratch and compares the
result with the acknowledged frame. Any difference is a missed change. The
refresh sends it like any other change, records a report that names the
element, its family and the revisions that did not move, and turns safe mode
on if the setting asks for that (decision 2).

**What it bounds.** A missed change stays on screen for one interval at
most, and every missed change leaves a report that points at the code that
failed to count it.

**What it costs.** One full build per interval, run while input is idle
where it can be. With the repeats off it costs less than today's frame
build, which took 16 to 26 million steps in the measurement.

## Tests

- The shadow check compares the change driver with the full driver on every
  frame of every test run, with the repeats on.
- A unit test changes a widget's borrowed data without its change word, and
  expects the next refresh to find the change, send it and report it.
- A unit test damages a record of the acknowledged frame, and expects safe
  mode to catch it on the next frame, refuse that frame and name the
  structure.
- Each slice runs the typing run and Desk with the applications it touches,
  and the refactor ratchet. At the end the full Desktop journey runs once in
  normal mode with the shadow check and once in safe mode, one run at a
  time under the existing guards.

## Parts

Each part is approved on its own.

### Part 1. Checks by moment, in today's path

**Change.** The repeats go behind a switch that tests and safe mode turn on.
The handover proofs run when storage is lent, allocated or grows, instead of
at every entry. Storage taken from a memory source is no longer proved apart
from other live storage.

**Kind.** A trade, not a removal of repeated work. Normal sessions stop
noticing a bug that writes into the rich path's memory between handovers.

**Effect.** The check measurement's rows put the saving at about 8 million
steps of a typed letter's 16 million. This part does not depend on the
others and could land first.

### Part 2. Safe mode

**Change.** A switch that sends the full driver's frame, with every check on,
on every frame of an ordinary session, and the ways to turn it on of
decision 2. In today's path, the full driver is today's build with its reuse
shortcuts off, which is what the shadow check already runs beside them.

**Effect.** None in normal mode. In safe mode, about today's cost.

### Part 3. The occasional full refresh

**Change.** The refresh, its missed-change report, and the setting that lets
a report turn on safe mode.

**Effect.** One full build per interval in normal mode.

### Part 4. One projection, two drivers

This is the part that makes the frame follow change. It needs parts 2 and 3
of FRAMES-FOLLOW-CHANGE.

- **4a.** The change driver for application documents: the projection's
  record of revisions and items, capture of changed elements into scratch,
  and the pending change set. RUHA's banks go.
- **4b.** Desk's chrome through the same projection, as one candidate. The
  shell's second candidate, its work space and its frozen banks go.
- **4c.** The renderer sends the pending change set as the DELTA and applies
  it on ACK. The whole-screen comparison remains for the full driver alone.

**Effect.** Most of the 6.28 million steps of building, copying and
comparing in a typed letter's frame, and the copies' memory.

### Part 5. Today's structure retires

Once the change driver passes the typing run, Desk with every application
and the full Desktop journey with the shadow check, and safe mode passes the
same journeys, the structures parts 4a to 4c replaced are removed. Nothing is
kept for compatibility. The full driver remains the one full path.

## Expected effect

Millions of steps in a typed letter's burst frame. The figures after part 1
and part 4 are estimates.

| | Today | After part 1 | After part 4 |
| --- | ---: | ---: | ---: |
| Checks | 9.85 | about 1.9 | about 0.2 |
| Building, copying and comparing | 6.28 | 6.28 | about 2 |
| Fit | 0.03 | 0.03 | 0.03 |
| Frame build | 16.16 | about 8 | about 2 |

After part 1, the item checks still visit every item on every frame. Part 4
makes them follow change.

## Relation to FRAMES-FOLLOW-CHANGE

- Parts 2 to 4 (widgets and UIDL count their changes; applications stop
  bridging) are this design's inputs. They are in progress and stay as
  planned.
- Part 9 (a repaint fills each cell once) concerns Desk's painting and stays
  as planned.
- Parts 5 to 8 speed up stages that this design replaces. Part 1 here takes
  out the repeats that parts 5, 7 and 8 would remove one by one, and part 4
  replaces the reuse that parts 5 to 7 would add inside today's copies.
  Whether to drop them is decision 5.
- Part 0's measurement stays the baseline, and part 1's shadow check is the
  test tool here too.

## Decisions

1. **Where checks run.** The table above replaces the rule that every
   boundary check stays at every boundary. Normal sessions then stop noticing
   a bug that writes into the rich path's memory between handovers, and
   safe mode and tests keep that.
2. **How safe mode turns on.** A Desk setting that an administrator can fix,
   a boot option, and whether an anomaly turns it on by itself.
3. **The refresh interval.** Proposed: once input settles, and at least every
   few seconds while the screen is shown. The exact default is to be chosen,
   and it is a setting.
4. **What the projection keeps.** Proposed: only the revisions each element
   last projected and the wire items they became, with content captured into
   scratch when it changes. The alternative keeps a renderer-neutral copy of
   each element's content, which costs memory and buys nothing a current
   renderer reads.
5. **FRAMES-FOLLOW-CHANGE parts 5 to 8.** Proposed: dropped in favour of
   parts 1 and 4 here, once parts 2 to 4 there are done.

## Not in this design

- **The CELL flush,** 51 to 488 million steps over part 0's runs. It needs
  its own design.
- **New kinds of DELTA.** About 40% of the canonical journey's changed frames
  still go out as STARTs, and most of those need the terminal to accept more
  kinds of change in a DELTA.
- **Applications' own work,** such as a Worlds step or a Sound Lab render.
