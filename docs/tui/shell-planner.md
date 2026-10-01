# Canonical shell planner

`akashic/tui/rich-terminal/shell-planner.f` converts one frozen canonical
SHM snapshot into tentative renderer-neutral PANE, TASKBAR, TASK and LAUNCHER
records. It allocates nothing, calls no facade or transport, reads no host or
UCTX, and never inspects application names or parses labels.

The source must pass `SHSN-FROZEN-VALIDATE`. The caller supplies retained
owner/generation and first IDs independently of ordinary shell/component
identities. Every display and launcher-action string is copied into caller
storage. Output records survive source-bank reuse; their borrowed text
pointers remain valid only while the output text bank remains unchanged.

## Admission authority

The planner does not authenticate a terminal publication. Its caller must
retain the exact completed draw and source attachment authority, and set only
the eligibility proven for that draw:

- A nonzero pane eligibility cell means the source pane's signed slot,
  component owner/generation and exact content rectangle have been associated
  with the corresponding frozen document. RUHA ABI9 carries the ordinary
  component tuple. Slot numbers, positive display keys, titles and attachment
  tokens alone do not prove that association.
- A selected taskbar band requires a successful final-writer-clear check for
  its complete rectangle using `SHSN-RECT-CLEAR?`. Every gap returned by
  `RSHPL-GAP-BOUNDS` must contain canonical ordinary space cells. A later
  writer or unexpected nonblank gap requires whole-band CELL fallback.
- Every emitted pane chrome strip needs the same completed-draw
  final-writer proof. If a strip cannot be represented, omit that pane before
  assigning IDs. Keep its complete content/region membership consistent with
  whichever semantic or CELL path is actually admitted.

Claims are tentative until the complete provider transaction succeeds.
Publication failure does not authorize suppressing any CELL rectangle.
Dispatch must validate the committed control/revision, current completed
SHSN source and exact lifecycle/action tuple before invoking the ordinary
shell action. Copied launcher action text never authorizes launching directly.

## Geometry and ownership

All neutral regions retain logical origin `(0,0)` and the complete surface
dimensions. One chrome region precedes distinct pane-content regions; each
content region has the exact explicit physical clip from SHM. Actual applet
controls, static objects, glyphs and instruments must name their corresponding
content region. A canonical genuinely empty content region is valid; unrelated
objects may not be assigned to an invented empty region.

Pane bounds and content offsets are exact. The title is metadata; content at
the outer origin reserves no title row. Chrome claims are the four disjoint
rectangles of outer-minus-content, omitting empty pieces. Existing Desk
geometry normally produces only bottom and right strips; a zero-chrome pane
produces no chrome claim. Signed origins are checked without imposing a signed
limit on exact wider endpoints. Overlay identity remains signed, and overlay
content sorts one level after ordinary content.

The taskbar uses at most two roots:

| Band | Root interval |
|---|---|
| TASK | `[0, DIVIDER-COL)`, or `[0, END-COL)` when no divider exists |
| LAUNCHER | `[DIVIDER-COL+2, END-COL)`, or `[0, END-COL)` without a divider |

Only nonempty selected bands emit roots. Source slots must fit their entire
band; child columns are relative to that band's origin, with no repacking.
The explicit two-cell divider range and everything at or after `END-COL`
remain outside claims. Internal blank spacing keeps its exact geometry and
may receive semantic material/background.

Taskbar roots are disabled while the source blocks input. TASK selection and
minimization map to their canonical state bits. Disabled/actionless launchers
remain visible and inert. Native RUNNING and ERROR flags remain in correlation;
they do not invent another wire state. Authored label bytes, including any
brackets, are copied exactly.

## Caller storage and API

Status values are `OK=0`, `CAPACITY=1`, `INVALID=2`; the gap enumerator
also returns `END=3` with all-zero geometry.

```forth
RSHPL-REQUEST-CLEAR ( request -- )
RSHPL-REQUEST-SOURCE!
  ( model bytes attachment draw eligible-a eligible-u bands request -- )
RSHPL-REQUEST-IDENTITY!
  ( owner generation first-region first-object first-control request -- )
RSHPL-REQUEST-Z! ( chrome-z content-z taskbar-z request -- )
RSHPL-REQUEST-OUTPUT!
  ( regions-a/u panes-a/u controls-a/u text-a/u correlations-a/u
    claims-a/u actions-a/u result-a/u request -- )
RSHPL-BUILD ( request -- status )

RSHPL-BAND-BOUNDS
  ( SHM-kind model bytes -- row col height width status )
RSHPL-GAP-BOUNDS
  ( ordinal SHM-kind model bytes -- row col height width status )
RSHPL-STORAGE-DISJOINT? ( address bytes -- flag )
```

`RSHPL-REQUEST-SIZE=256`; `RSHPL-RESULT-SIZE=152`.

`RSHPL-BAND-BOUNDS` and `RSHPL-GAP-BOUNDS` validate the frozen model on every
call. Their internal peers `_RSHPL-BAND-BOUNDS-PROVED` and
`_RSHPL-GAP-BOUNDS-PROVED` leave out only that validation, for a caller that
validated the model and has not written it since. The shell sidecar validates
its model copy once per candidate and then walks the band gaps with them.
Eligible storage is either canonical `0 0` (no panes) or exactly one u64 per
source entry. Values are zero or one; non-pane entries must be zero. Band mask
bit 0 selects TASK and bit 1 selects LAUNCHER. Hidden taskbar entries are omitted.
All record storage is 8-byte aligned; text/action storage need not be aligned.
Zero spans are canonical `0 0`.

Every input, output, request and full output capacity is pairwise disjoint and
disjoint from invoked module scratch. Malformed or overlapping storage is
rejected before caller outputs are touched. After that proof, all output
capacities are cleared; semantic failure, insufficient capacity or a caught
exception leaves those proved output capacities zero. Source and eligibility
bytes are never modified.

For P admitted panes, E admitted task/launcher entries and G nonempty bands
(`0..2`), required storage is:

| Bank | Exact count or safe bound |
|---|---|
| Regions, 96 bytes | `(P ? P+1 : 0) + (G ? 1 : 0)` |
| PANE, 184 bytes | `P` |
| CONTROL, 200 bytes | `E+G` |
| Correlations, 192 bytes | `P+E+G` |
| Claims, 64 bytes | actual nonempty pane strips plus G; at most `4P+G` |
| Display text | exact admitted pane titles followed by exact entry labels |
| Action text | exact admitted launcher action bytes, separately owned |
| Result | 152 bytes |

The result exposes used counts, all three retained ID high-waters, source
owner/generation/epoch, attachment and draw. `PANE-UTF8` gives the display
bank's pane-title prefix; `CONTROL-UTF8` gives its label suffix;
`ACTION-BYTES` gives the separate action-bank use. Thus each neutral family
can be supplied its exact byte authority without charging launcher dispatch
data as visible text.

Correlations retain source ordinal/kind/key, signed identity, component
owner/generation, retained ID and region/content-region, source tuple/epoch,
draw, attachment, exact ordinary slot, source flags and action selector.
`TEXT-OFFSET/BYTES` name the display bank; `ACTION-OFFSET/BYTES` name the
action bank. Synthetic roots use source indices −1/−2 and distinct kinds
4/5, with no action. Claims retain source index, claim kind, retained ID,
region and exact rectangle; they contain no source pointer.

Tests in `local_testing/test_shell_planner.py` execute the actual KDOS and
complete module dependency closure. They cover deep source validation, exact
bands/strips, copied action lifetime, alias rejection, capacity rollback,
independent omission, modal input state, signed overlay identity and wider
geometry endpoints.

The shared chrome region sorts below every selected content region. The
planner therefore rejects any selected pane whose chrome intersects another
selected pane's content; the caller must omit the conflicting pane or use a
future representation with separate chrome order. This also covers a
nonempty overlay border placed inside a normal pane. The publisher must
extend this ordering proof to every other region in the complete candidate.
The regression gate includes native planner PANE and TASKBAR descriptors
published through the actual RTAPT provider and decoded by the retained host,
including canonical flags, exact child slots and display-only UTF8 charges.
