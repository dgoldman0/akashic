# Desk startup's second cell screen — 2026-11-01

[desk-startup-20261030.md](desk-startup-20261030.md) traced the second complete
cell screen Desk sends at startup to `_APTSCB-RETAINED-HANDOFF`, which called
`SCR-FORCE` when RETAINED-1 became available, and proposed `SCR-REQUEST-FLUSH`
in its place. cec8f16f made that change, and a profiled typing run showed the
second screen still sent. This note records that run and the one before it,
the force they exposed, the fix (MegaPad c3e8ef5f and Akashic 1dd520c8), and
the runs that measured it. It is simulator evidence; steps are the
simulator's semantic steps, and the profile charges them at host boundaries
roughly every 65,536 steps.

## Bindings

| Run | Akashic | MegaPad |
| --- | --- | --- |
| Before | `085ac145` | `728cc265` |
| Handoff only | `cec8f16f` | `728cc265` |
| Fixed | `1dd520c8` | `c3e8ef5f` |

MegaPad b5b84c25, between the two MegaPad commits, changes only KDOS's
free-run search, which Desk does not use. Every typing run was
`physical_typing_cadence.py run --screen-profile`, from a RAM clone of Akashic
main, with MegaPad's main checkout, `PYTHONHASHSEED=0` and every call chain
kept (`MEGAPAD_PROFILE_CHAINS=0 MEGAPAD_PROFILE_CHAIN_DEPTH=0`), and its
output stayed in `/dev/shm`.

## What the runs sent

| Before the first typed key | Before | Handoff only | Fixed |
| --- | ---: | ---: | ---: |
| CELL `REPLACE` of 23,520 cells, no retained part | 192,744 bytes | 192,744 bytes | not sent |
| `REPLACE_START` | 115,690 bytes | 115,690 bytes | 115,690 bytes |
| `REPLACE_CONTINUE` | 160 bytes | 160 bytes | 160 bytes |
| Guest steps | 170.51M | 170.84M | 147.52M |
| Steps under `SCR-FLUSH?` | 86.11M | 86.51M | 63.57M |

| Whole run | Before | Handoff only | Fixed |
| --- | ---: | ---: | ---: |
| `CELL_SPAN` frames received | 199 | 198 | 126 |
| Their bytes | 387,076 | 387,000 | 195,384 |
| Seconds | 30.6 | 32.1 | 22.9 |
| Shell `write_bytes` | 40,960 | 0 | 0 |

Before the fix, each run received two complete screens of 84 rows and the
typing deltas. The first is the legacy CELL snapshot that Desk's setup
paint sends by the direct route, under `_ASHELL-SETUP`, about 15.8 million
steps of `SCR-FLUSH?` in each run. The second is the CELL replace, which the
shell's loop writes through the rich publisher under `_ASHELL-PASS`, about
22 million steps. Between them, after the setup flush, a flush under
`_ASHELL-PASS` counts every row as a snapshot (`_SCR-COUNT-CHANGES` with
`_SCR-CELLS-WORDS`) and goes no further; in the handoff-only run it ran at
5.13 s and the CELL replace began at 5.64 s. The handoff change left all of
this as it was.

With the fix, the setup paint's legacy snapshot is the only complete
screen. The run received 126 `CELL_SPAN` frames carrying 195,384 bytes, one
screen and the typing deltas, and reached its first typed key in 23.3
million fewer steps, 13.7% of the startup. Its typing burst matches the end
of part 10: 18 DELTAs and 13,158 bytes, each frame built in 2.05 million
steps, and the isolated letter's frame in 6.49 million. The runs' seconds
follow the machine's load, which other work varied through the day.

## The force that remained

`APTSCB-SERVICE` ended its turn with `PT-SNAPSHOT-NEEDED? IF SCR-FORCE THEN`,
the path that answers a soft reset. PT sets that flag when it accepts the
terminal's offer, and clears it only when a successful `TX_RESULT` for a
complete snapshot arrives. The setup flush sends the legacy snapshot and
commits it locally, which clears the screen's force flag. The next service
turn, before the terminal's result had come back, found PT's flag still set
and forced again. The next flush counted every row as a snapshot, and PT
refused its begin with `PT-S-WOULD-BLOCK` while the result was outstanding.
By the time the flush went, RETAINED-1 discovery had completed, so it went
through the publisher as the CELL-only replace. `SCR-FORCE` is idempotent,
and the handoff's call found the flag already set, so removing that call
changed nothing in these runs.

The profile cannot see `SCR-FORCE` itself, so this caller was inferred from
the code and the samples: the screen's force flag is set only by
`SCR-FORCE`; its other callers are the backend bind, whose force the setup
flush consumed, the ANSI fallback, which did not run, and `SCR-RESIZE`, whose
allocation and copy of every cell would appear in the samples and did not;
and the refused snapshot-mode flush sat where the service's force predicts
it. The fixed run confirms it: with only that force gated, the second screen
is gone.

## The fix

PT already kept the fact the service lacked: its admission barrier,
`_PT-RESULT-BUSY?`, is true while a result, lifecycle reply or completion is
outstanding, or a soft reset or close is pending, and every begin it would
otherwise admit returns `PT-S-WOULD-BLOCK` then. MegaPad c3e8ef5f makes it
public as `PT-RESULT-BUSY?`. `PT-SNAPSHOT-NEEDED?` keeps its meaning, true
until the snapshot's successful result: MegaPad's module note defines it so,
and its PT tests wait for that result through it.

Akashic 1dd520c8 forces only while `PT-RESULT-BUSY?` is false. While a
committed snapshot awaits its result, no begin could be admitted anyway.
When the result arrives, the need is gone if the snapshot succeeded and
remains if it failed, and a reset or resize raises it again for the next
turn. cec8f16f remains part of the fix: with the service quiet, the screen is
clean at discovery, and the handoff's former `SCR-FORCE` would otherwise
send the second screen by itself.

cec8f16f's message describes the second screen as removed by the handoff
change. The handoff-only run shows it was not, for the reason above; it was
removed by 1dd520c8 on top of cec8f16f.

## The journeys

The canonical Desktop journey (`physical_desktop_acceptance.py`) ran once on
the handoff-only state with MegaPad b5b84c25, and once on the fixed state.

| Journey | Seconds | Presents D/S/C/N | Bytes | Peak RSS | `write_bytes` |
| --- | ---: | --- | ---: | ---: | ---: |
| Part 10, 3d916720 | 228.3 | 61/25/25/1 | 4,786,258 | — | 0 |
| Handoff only, cec8f16f | 380.4 | 60/25/25/1 | 4,783,838 | 552 MiB | 0 |
| Fixed, 1dd520c8 | 214.2 | 61/25/25/0 | 4,592,346 | 552 MiB | 0 |

The one NONE present of the earlier journeys was the startup's CELL-only
replace: the fixed journey sends none, and 193,912 bytes fewer than part
10's. The handoff-only journey ran while another project's
tests held the machine's load average near 13, the likely cause of its longer
time.
