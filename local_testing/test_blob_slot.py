#!/usr/bin/env python3
"""utils/blob-slot.f on the native executor.

A slot owns a copy of its bytes, and setting it from its own bytes or to
nothing works.  Writing a table's slots puts their bytes in a region in
order, each zero-padded to a cell, and turns each slot into an offset.
Reading the region back walks it with a cursor that accepts only slots
naming exactly its next part; every way a slot can be out of place breaks
the walk for good.  Taking the records gives each slot its own copy, and
forgetting empties the slots that still hold offsets.
"""

from __future__ import annotations

import pytest

from native_forth import NativeForth


OK, NOMEM = 0, 1

# Records are 24 bytes: an id, then a slot at offset 8.
PRELUDE = r"""
CREATE SL-RAW 23 ALLOT  SL-RAW 7 + -8 AND CONSTANT SL
CREATE REGION-RAW 263 ALLOT  REGION-RAW 7 + -8 AND CONSTANT REGION
CREATE CUR-RAW 31 ALLOT  CUR-RAW 7 + -8 AND CONSTANT CUR
CREATE TB-RAW RTAB-SIZE 7 + ALLOT  TB-RAW 7 + -8 AND CONSTANT TB
CREATE TC-RAW RTAB-SIZE 7 + ALLOT  TC-RAW 7 + -8 AND CONSTANT TC
CREATE WR-RAW 263 ALLOT  WR-RAW 7 + -8 AND CONSTANT WR
24 CONSTANT TU  8 CONSTANT TOFF
: HELLO  ( -- a u ) S" hello" ;
: TEN  ( -- a u ) S" abcdefghij" ;
: TYPE.  ( a u -- ) DUP IF TYPE ELSE 2DROP ." -" THEN SPACE ;
\ A table of three records: "hello", nothing, and ten letters.
: T-ADD  ( a u id -- )
    TB TU RTAB-RESERVE THROW TB RTAB-COUNT@ TB TU RTAB-INSERT
    TUCK ! TOFF + BSLOT! THROW ;
: T-FILL  ( -- )
    TB TU TOFF BSLOT-TABLE-FREE TB TU RTAB-FREE
    HELLO 1 T-ADD 0 0 2 T-ADD TEN 3 T-ADD ;
\ The table written: its records copied to WR, their slots put in REGION.
: T-WRITE  ( -- )
    REGION 256 255 FILL WR 256 0 FILL
    WR TB TU RTAB-PUT DROP
    REGION TB TU TOFF BSLOT-TABLE-U CUR BSLOT-CURSOR-INIT
    WR 3 TU TOFF CUR BSLOT-PUT-RECORDS ;
: W  ( i -- slot ) TU * WR + TOFF + ;
: W.  ( i -- ) W DUP @ . 8 + @ . ;
: R.  ( u -- ) 0 ?DO REGION I + C@ . LOOP ;
\ Walks the written slots over SIZE bytes of REGION: each part's offset
\ and length, or -1 for none, then where the cursor ends.
: WALK  ( size -- )
    REGION SWAP CUR BSLOT-CURSOR-INIT
    3 0 DO
        I W CUR BSLOT-NEXT DUP IF SWAP REGION - . . ELSE 2DROP -1 . THEN
    LOOP
    CUR BSLOT-AT@ . ;
"""

SUITE = NativeForth(("utils/blob-slot.f",),
                    prelude=tuple(PRELUDE.strip().splitlines()))


@pytest.fixture(scope="module")
def forth():
    return SUITE.shared()


def run(forth, lines: list[str], max_steps: int = 400_000_000) -> list[list[str]]:
    output = forth.run(lines, max_steps).decode("latin-1")
    assert "??" not in output, output[-3000:]
    return [line.split() for line in output.replace("\r", "").split("\n") if line.strip()]


def test_a_slot_owns_a_copy(forth):
    rows = run(forth, [
        "SL 16 0 FILL HELLO SL BSLOT! . SL BSLOT$ TYPE. SL @ HELLO DROP <> . CR",
        # From its own bytes, and to nothing.
        "SL BSLOT$ 1- SWAP 1+ SWAP SL BSLOT! . SL BSLOT$ TYPE. "
        "0 0 SL BSLOT! . SL BSLOT$ . . CR",
        "TEN SL BSLOT! . SL BSLOT-FREE SL BSLOT$ . . CR",
        "0 BSLOT-PADDED . 1 BSLOT-PADDED . 8 BSLOT-PADDED . 9 BSLOT-PADDED . CR",
    ])
    assert rows == [
        ["0", "hello", "-1"],
        ["0", "ello", "0", "0", "0"],
        ["0", "0", "0"],
        ["0", "8", "8", "16"],
    ]


def test_writing_puts_each_slot_in_order(forth):
    rows = run(forth, [
        "T-FILL TB TU TOFF BSLOT-TABLE-U . T-WRITE CUR BSLOT-AT@ . CR",
        "0 W. 1 W. 2 W. CR",
        "24 R. CR",
    ])
    assert rows[0] == ["24", "24"]
    assert rows[1] == ["0", "5", "0", "0", "8", "10"]
    assert [int(b) for b in rows[2]] == (
        list(b"hello") + [0] * 3 + list(b"abcdefghij") + [0] * 6)


def test_reading_walks_exactly_the_parts(forth):
    rows = run(forth, ["T-FILL T-WRITE 24 WALK CR"])
    assert rows == [["0", "5", "-1", "8", "10", "24"]]


DAMAGE = {
    # edit after writing, region size, the walk
    "an empty slot with an offset": ("8 1 W !", 24, ["0", "5", "-1", "-1", "-1"]),
    "an offset past the next part": ("16 2 W !", 24, ["0", "5", "-1", "-1", "-1"]),
    "an offset before it": ("0 2 W !", 24, ["0", "5", "-1", "-1", "-1"]),
    "a length past the region": ("300 2 W 8 + !", 24, ["0", "5", "-1", "-1", "-1"]),
    "padding past the region": ("", 22, ["0", "5", "-1", "-1", "-1"]),
    "a byte in the padding": ("120 REGION 6 + C!", 24, ["-1", "-1", "-1", "-1"]),
    "a byte in the last padding": ("120 REGION 23 + C!", 24, ["0", "5", "-1", "-1", "-1"]),
    "a length that wraps": ("-8 2 W 8 + !", 24, ["0", "5", "-1", "-1", "-1"]),
    # Once broken, the walk stays broken: here a slot then claims the
    # cursor's offset of -1, with zeroes where its padding would be.
    "a slot claiming the broken offset":
        ("8 0 W ! 0 0 W 8 + ! REGION 8 0 FILL -1 2 W ! 1 2 W 8 + !", 24,
         ["-1", "-1", "-1", "-1"]),
}


def test_every_slot_out_of_place_breaks_the_walk(forth):
    lines = [f"T-FILL T-WRITE {edit} {size} WALK CR" for edit, size, _ in DAMAGE.values()]
    lines.append("T-FILL T-WRITE 32 WALK CR")
    rows = run(forth, lines)
    assert len(rows) == len(DAMAGE) + 1, rows
    for name, (_, _, walk), row in zip(DAMAGE, DAMAGE.values(), rows):
        assert row == walk, name
    # Bytes left over end the walk short of the region: the caller sees
    # where the cursor stopped.
    assert rows[-1] == ["0", "5", "-1", "8", "10", "24"]


def test_taking_records_gives_slots_their_own_copies(forth):
    rows = run(forth, [
        "T-FILL T-WRITE TC TU TOFF BSLOT-TABLE-FREE TC TU RTAB-FREE "
        "WR 3 TC TU RTAB-TAKE . REGION TC TU TOFF BSLOT-TABLE-OWN . "
        "0 TC TU RTAB-NTH TOFF + DUP BSLOT$ TYPE. @ REGION <> . "
        "1 TC TU RTAB-NTH TOFF + BSLOT$ . . "
        "2 TC TU RTAB-NTH TOFF + BSLOT$ TYPE. CR",
        # The copies are the records' own: changing the region leaves them.
        "REGION 24 0 FILL 0 TC TU RTAB-NTH TOFF + BSLOT$ TYPE. "
        "TC TU TOFF BSLOT-TABLE-FREE 0 TC TU RTAB-NTH TOFF + BSLOT$ . . CR",
        # Forgetting empties the slots from an index on.
        "T-FILL T-WRITE TC TU RTAB-FREE WR 3 TC TU RTAB-TAKE . "
        "1 TC TU TOFF BSLOT-TABLE-FORGET "
        "0 TC TU RTAB-NTH TOFF + 8 + @ . 2 TC TU RTAB-NTH TOFF + DUP @ . 8 + @ . CR",
    ])
    assert rows[0] == ["0", "0", "hello", "-1", "0", "0", "abcdefghij"]
    assert rows[1] == ["hello", "0", "0"]
    assert rows[2] == ["0", "5", "0", "0"]
