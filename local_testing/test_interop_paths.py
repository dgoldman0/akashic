#!/usr/bin/env python3
"""Interoperability paths that left the wrong cells, held to their comments.

The stack-effect checker of toolchain/language found three words here whose
uncommon paths broke their stack effects:

- _CSJ-TYPE-NAME ( cv-type -- addr len ) dropped the selector of its CASE
  default, so ENDCASE dropped the name's length for a type it does not
  list;
- MCP-CALL-ERROR! ( addr len call -- ) left the copied length behind;
- the sandbox value writer's shaping words returned three cells where a
  size overflowed, keeping the arithmetic's status under their own.

The overflow cases set the writer's work record and limits directly, with
counts and payloads near the largest byte length, since no real value of
that size fits in memory.
"""

from __future__ import annotations

from forth_snapshot import ForthSnapshot, run_file_tests, transcript_checks


SNAPSHOT = ForthSnapshot(
    ("interop/mcp/protocol.f", "sandbox/value.f"),
    prelude=(
        "VARIABLE T-DEPTH",
        ": T{  ( -- )  DEPTH T-DEPTH ! ;",
        ': }T  ( -- )  DEPTH T-DEPTH @ - ." cells=" . ;',
        "CREATE T-CALL MCP-CALL-SIZE ALLOT",
        "CREATE T-LIM SBOX-VALUE-LIMITS-SIZE ALLOT",
        "CREATE T-WORK 256 ALLOT",
        ": T-WORK!  ( count payload -- )",
        "    T-WORK 256 0 FILL  T-LIM SBOX-VALUE-LIMITS-SIZE 0 FILL",
        "    SBOX-BYTE-LENGTH-MAX SBOX-VALUE-LIMIT-LIST-COUNT T-LIM _SVL-NTH !",
        "    SBOX-BYTE-LENGTH-MAX SBOX-VALUE-LIMIT-BLOB-BYTES T-LIM _SVL-NTH !",
        "    T-LIM T-WORK _SVW.LIMITS !",
        "    T-WORK _SVW.TEMP-PAYLOAD !  T-WORK _SVW.TEMP-COUNT ! ;",
        ': T-SHAPED.  ( aggregate? status -- )',
        '    SBOX-VALUE-S-INVALID = ." invalid=" .  ." aggregate=" . ;',
    ),
)

check, check_fn, check_emitted = transcript_checks(SNAPSHOT.run)


def test_schema_type_name_default_gives_a_name():
    check("unlisted type", [
        ": T1  99 T{ _CSJ-TYPE-NAME }T TYPE ;",
        "T1",
    ], "cells=1 object")
    check("listed type", [
        ": T1  CV-T-INT T{ _CSJ-TYPE-NAME }T TYPE ;",
        "T1",
    ], "cells=1 integer")


def test_call_error_keeps_the_text_and_leaves_nothing():
    check("error text", [
        ': T1  T-CALL MCP-CALL-INIT S" boom" T-CALL T{ MCP-CALL-ERROR! }T',
        "      T-CALL MCALL.ERROR-A @ T-CALL MCALL.ERROR-U @ TYPE ;",
        "T1",
    ], "cells=-3 boom")


def test_aggregate_overflows_give_two_cells():
    # count times the stride passes the largest byte length
    check("count overflow", [
        ": T1  1 61 LSHIFT 0 T-WORK!",
        "      8 SBOX-VALUE-LIMIT-LIST-COUNT T-WORK T{ _SVW-SHAPE-AGGREGATE }T",
        "      T-SHAPED. ;",
        "T1",
    ], "cells=-1 invalid=-1 aggregate=0")
    # the storage plus its 16-byte header passes it
    check("storage overflow", [
        ": T1  SBOX-BYTE-LENGTH-MAX 8 - 0 T-WORK!",
        "      1 SBOX-VALUE-LIMIT-LIST-COUNT T-WORK T{ _SVW-SHAPE-AGGREGATE }T",
        "      T-SHAPED. ;",
        "T1",
    ], "cells=-1 invalid=-1 aggregate=0")


def test_blob_overflows_give_two_cells():
    check("padding overflow", [
        ": T1  0 SBOX-BYTE-LENGTH-MAX T-WORK!",
        "      0 T-WORK T{ _SVW-SHAPE-BLOB }T T-SHAPED. ;",
        "T1",
    ], "cells=0 invalid=-1 aggregate=0")
    check("storage overflow", [
        ": T1  0 SBOX-BYTE-LENGTH-MAX 15 - T-WORK!",
        "      0 T-WORK T{ _SVW-SHAPE-BLOB }T T-SHAPED. ;",
        "T1",
    ], "cells=0 invalid=-1 aggregate=0")


if __name__ == "__main__":
    run_file_tests(__file__)
