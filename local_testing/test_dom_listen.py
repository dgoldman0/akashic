#!/usr/bin/env python3
"""DOM listeners leave nothing on the stack (dom/event.f).

The stack-effect checker of toolchain/language found _DOME-LISTEN-INNER
keeping a copy of the listener it allocates, so DOME-LISTEN,
DOME-LISTEN-CAPTURE and DOME-LISTEN-ONCE ( node type xt -- ) each left a
cell behind.  Each case registers a listener on a node, takes the three
cells it was given, and the listener runs when the event fires.
"""

from __future__ import annotations

from forth_snapshot import ForthSnapshot, run_file_tests, transcript_checks


SNAPSHOT = ForthSnapshot(
    ("dom/event.f",),
    prelude=(
        "VARIABLE T-DEPTH",
        ": T{  ( -- )  DEPTH T-DEPTH ! ;",
        ': }T  ( -- )  DEPTH T-DEPTH @ - ." cells=" . ;',
        "524288 A-XMEM ARENA-NEW DROP CONSTANT T-ARENA",
        "T-ARENA 64 64 DOM-DOC-NEW CONSTANT T-DOC",
        "T-DOC DOM-USE",
        "T-DOC 16 DOME-INIT CONSTANT T-DOME",
        'S" div" DOM-CREATE-ELEMENT CONSTANT T-NODE',
        "VARIABLE T-HITS",
        ": T-ON  ( event node -- )  2DROP 1 T-HITS +! ;",
        ": T-CLICK  ( -- )  T-NODE DOME-TI-CLICK DOME-TYPE@ 0 DOME-FIRE DROP ;",
    ),
)

check, check_fn, check_emitted = transcript_checks(SNAPSHOT.run)


def test_listen_takes_its_cells():
    for word in ("DOME-LISTEN", "DOME-LISTEN-CAPTURE", "DOME-LISTEN-ONCE"):
        check(word, [
            ": T1  0 T-HITS !"
            f"      T-NODE DOME-TI-CLICK DOME-TYPE@ ['] T-ON T{{ {word} }}T"
            '      T-CLICK ." hits=" T-HITS @ . ;',
            "T1",
        ], "cells=-3 hits=1")


if __name__ == "__main__":
    run_file_tests(__file__)
