#!/usr/bin/env python3
"""Math paths that left the wrong cells, held to their stack comments.

The stack-effect checker of toolchain/language found two words in Akashic's
math library whose early or malformed-input paths broke their effects:

- STAT-ONLINE-MERGE ( ctx1 ctx2 dst -- ) took its return address with a
  second R> when ctx1 was empty, and wrote nothing to DST when ctx2 was;
  each empty side now copies the other context to DST.
- COLOR-HEX-PARSE ( addr len -- r g b flag ) returned five or three cells
  for a malformed #RGB or #RRGGBB, and the length in place of the red
  channel for a string of another length; every refusal is now four cells
  with a false flag.  It also read the byte at an empty string's address
  to look for a leading #, which faults where nothing is mapped.
"""

from __future__ import annotations

from forth_snapshot import ForthSnapshot, run_file_tests, transcript_checks


SNAPSHOT = ForthSnapshot(
    ("math/stats.f", "math/color.f"),
    prelude=(
        "VARIABLE T-DEPTH",
        ": T{  ( -- )  DEPTH T-DEPTH ! ;",
        ': }T  ( -- )  DEPTH T-DEPTH @ - ." cells=" . ;',
        "CREATE T-A STAT-ONLINE-SIZE ALLOT",
        "CREATE T-B STAT-ONLINE-SIZE ALLOT",
        "CREATE T-M STAT-ONLINE-SIZE ALLOT",
        # 1.0, 2.0 and 3.0 in FP16
        ": T-FILL  ( ctx -- )  DUP 0x3C00 STAT-ONLINE-PUSH"
        "    DUP 0x4000 STAT-ONLINE-PUSH  0x4200 STAT-ONLINE-PUSH ;",
        ": T-SAME?  ( ctx1 ctx2 -- flag )"
        "    STAT-ONLINE-SIZE SWAP STAT-ONLINE-SIZE COMPARE 0= ;",
        ": T-SETUP  ( -- )  T-A STAT-ONLINE-INIT  T-B STAT-ONLINE-INIT"
        "    T-M STAT-ONLINE-SIZE 165 FILL ;",
    ),
)

check, check_fn, check_emitted = transcript_checks(SNAPSHOT.run)


def test_merge_with_an_empty_first_context_copies_the_second():
    check("ctx1 empty", [
        ": T1  T-SETUP T-B T-FILL"
        "      T-A T-B T-M T{ STAT-ONLINE-MERGE }T"
        "      T-M T-B T-SAME? . T-M STAT-ONLINE-COUNT . ;",
        "T1",
    ], "cells=-3 -1 3")


def test_merge_with_an_empty_second_context_copies_the_first():
    check("ctx2 empty", [
        ": T1  T-SETUP T-A T-FILL"
        "      T-A T-B T-M T{ STAT-ONLINE-MERGE }T"
        "      T-M T-A T-SAME? . T-M STAT-ONLINE-COUNT . ;",
        "T1",
    ], "cells=-3 -1 3")


def test_merge_of_two_contexts_counts_both():
    check("both filled", [
        ": T1  T-SETUP T-A T-FILL T-B T-FILL"
        "      T-A T-B T-M T{ STAT-ONLINE-MERGE }T"
        "      T-M STAT-ONLINE-COUNT . ;",
        "T1",
    ], "cells=-3 6")


# Each refusal leaves four cells: a false flag above three channels.  The
# strings fail at their first channel, or at their last after zero channels,
# so every channel is zero.
REFUSED = ("#g00", "#00g", "#gg0000", "#0000gg", "#12345", "")


def test_hex_parse_refusals_give_four_cells():
    for text in REFUSED:
        check(f"refuses {text!r}", [
            f': T1  S" {text}" T{{ COLOR-HEX-PARSE }}T . . . . ;',
            "T1",
        ], "cells=2 0 0 0 0")


def test_hex_parse_accepts_both_lengths():
    for text in ("#fff", "ffffff"):
        check(f"accepts {text!r}", [
            f': T1  S" {text}" T{{ COLOR-HEX-PARSE }}T . DROP DROP DROP ;',
            "T1",
        ], "cells=2 -1")


def test_hex_parse_reads_no_byte_of_an_empty_string():
    # Nothing is mapped at this address, so reading it is a bus fault.
    check("empty at an unmapped address", [
        ": T1  0x7FFF000000000000 0 T{ COLOR-HEX-PARSE }T . . . . ;",
        "T1",
    ], "cells=2 0 0 0 0")


if __name__ == "__main__":
    run_file_tests(__file__)
