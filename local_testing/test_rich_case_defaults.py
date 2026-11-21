#!/usr/bin/env python3
"""CASE defaults in the rich terminal that keep their word's stack effect.

BIOS's ENDCASE drops the selector, so a CASE default must leave its
selector on top for the default to have the effect of the other branches.
The stack-effect checker of toolchain/language found four rich-terminal
words whose default fell through to ENDCASE with the wrong cells:

- _RTAPT-SG-BIND ( a u kind -- ), which binds engine storage by kind,
  left the span of a kind it does not bind;
- the instrument planner's _RUIP-KIND>RTE, _RUIP-READOUT-MODE>RTE,
  _RUIP-METER-MODE>RTE and _RUIP-STATUS-MODE>RTE dropped the selector
  before pushing 0, so ENDCASE took the 0 and they returned nothing;
- the hybrid producer's _RTHP-UB-SH-SPAN ( item -- a u ) returned the
  producer alone for an item past its last.

Each case feeds an unlisted selector and checks the cells left, with a
listed one beside it where that shows the word's ordinary result.
"""

from __future__ import annotations

from forth_snapshot import (
    ForthSnapshot,
    megapad_module_lines,
    module_source_lines,
    run_file_tests,
    transcript_checks,
)


DEPTH = (
    "VARIABLE T-DEPTH",
    ": T{  ( -- )  DEPTH T-DEPTH ! ;",
    ': }T  ( -- )  DEPTH T-DEPTH @ - ." cells=" . ;',
)

# The engine reads MegaPad's rich-terminal system module, which a booted
# system loads before Akashic.
ENGINE = ForthSnapshot(
    (),
    prelude=tuple(
        megapad_module_lines("rich-terminal.f")
        + module_source_lines(("tui/rich-terminal/apt1-engine.f",))
    ) + DEPTH + (
        "CREATE T-E RTAPT-ENGINE-SIZE ALLOT",
        "CREATE T-OPS 80 ALLOT",
    ),
)

engine_check, _, _ = transcript_checks(ENGINE.run)


def test_engine_storage_bind_of_an_unlisted_kind():
    engine_check("kind 1", [
        ": T1  T-E RTAPT-ENGINE-SIZE 0 FILL  T-E _RTAPT-SG-E !",
        "      T-OPS RTAPT-OP-SIZE 2* 1 T{ _RTAPT-SG-BIND }T",
        '      T-E _RTAPT-E.OPS-U @ ." ops-u=" . T-E _RTAPT-E.OP-CAP @ ." cap=" .',
        '      T-E _RTAPT-E.OPS-A @ T-OPS = ." ops-a=" . ;',
        "T1",
    ], "cells=-3 ops-u=80 cap=2 ops-a=-1")
    engine_check("kind 3", [
        ": T1  T-E RTAPT-ENGINE-SIZE 0 FILL  T-E _RTAPT-SG-E !",
        "      7 T-OPS 80 3 T{ _RTAPT-SG-BIND }T",
        '      T-E _RTAPT-E.OPS-U @ ." ops-u=" . T-E _RTAPT-E.COPY-U @ ." copy-u=" .',
        '      ." below=" . ;',
        "T1",
    ], "cells=-3 ops-u=0 copy-u=0 below=7")


PLANNER = ForthSnapshot(("tui/rich-terminal/uidl-instrument-planner.f",), prelude=DEPTH)

planner_check, _, _ = transcript_checks(PLANNER.run)


def test_instrument_mappings_of_unlisted_values():
    planner_check("kind", [
        ': T1  7 99 T{ _RUIP-KIND>RTE }T ." rte=" . ." below=" .',
        '      UDG-K-METER _RUIP-KIND>RTE RTE-INSTRUMENT-METER = ." meter=" . ;',
        "T1",
    ], "cells=0 rte=0 below=7 meter=-1")
    planner_check("modes", [
        ': T1  99 T{ _RUIP-READOUT-MODE>RTE }T ." readout=" .',
        '      99 T{ _RUIP-METER-MODE>RTE }T ." meter=" .',
        '      99 T{ _RUIP-STATUS-MODE>RTE }T ." status=" . ;',
        "T1",
    ], "cells=0 readout=0 cells=0 meter=0 cells=0 status=0")


PRODUCER = ForthSnapshot(("tui/rich-terminal/hybrid-screen-producer.f",), prelude=DEPTH)

producer_check, _, _ = transcript_checks(PRODUCER.run)


def test_producer_span_past_the_last_item():
    producer_check("item 20", [
        ': T1  7 20 T{ _RTHP-UB-SH-SPAN }T ." u=" . ." a=" . ." below=" . ;',
        "T1",
    ], "cells=1 u=0 a=0 below=7")


if __name__ == "__main__":
    run_file_tests(__file__)
