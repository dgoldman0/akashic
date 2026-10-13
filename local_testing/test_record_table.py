#!/usr/bin/env python3
"""utils/record-table.f on the native executor.

Reserving room doubles it and keeps the records.  Inserting opens a zeroed
slot and moves later records up; deleting moves them down and wipes the
slot it frees.  A table put to memory and taken back is the same bytes.
The search words find a 32-byte key or a u64 id, or where it belongs, and
the ascending checks accept only strict order.  A table that cannot get
memory is left as it was.
"""

from __future__ import annotations

import pytest

from native_forth import NativeForth


OK, NOMEM = 0, 1

# Keyed records are 40 bytes: a 32-byte key of one repeated byte, then a
# value.  Id records are 16 bytes: an id, then a value.
PRELUDE = r"""
CREATE TB-RAW RTAB-SIZE 7 + ALLOT  TB-RAW 7 + -8 AND CONSTANT TB
CREATE TI-RAW RTAB-SIZE 7 + ALLOT  TI-RAW 7 + -8 AND CONSTANT TI
CREATE TC-RAW RTAB-SIZE 7 + ALLOT  TC-RAW 7 + -8 AND CONSTANT TC
CREATE TKEY 32 ALLOT
CREATE TOUT-RAW 4103 ALLOT  TOUT-RAW 7 + -8 AND CONSTANT TOUT
40 CONSTANT TU
16 CONSTANT TIU
: T-CLEAR  ( -- )
    TB TU RTAB-FREE  TI TIU RTAB-FREE  TC TU RTAB-FREE ;
T-CLEAR
: T-KEY  ( b -- ) TKEY 32 ROT FILL ;
: T-FIND  ( b -- index found? ) T-KEY TKEY TB @ TB RTAB-COUNT@ TU RTAB-SEARCH ;
\ Adds the record keyed by byte B with value V where it belongs.
: T-ADD  ( b v -- )
    SWAP DUP T-FIND DROP SWAP T-KEY        ( v index )
    TB TU RTAB-RESERVE THROW
    TB TU RTAB-INSERT                      ( v slot )
    TKEY OVER 32 MOVE  32 + ! ;
: T-VALUES  ( -- ) TB RTAB-COUNT@ 0 ?DO I TB TU RTAB-NTH 32 + @ . LOOP CR ;
: T-SHAPE  ( -- ) TB RTAB-COUNT@ . TB RTAB.ROOM @ . CR ;
\ Whether the U bytes at A are all zero.
: T-ZERO?  ( a u -- flag ) -1 -ROT 0 ?DO DUP I + C@ IF NIP 0 SWAP THEN LOOP DROP ;
\ Adds the record with id ID and value V at the end.
: T-ADD-ID  ( id v -- )
    TI TIU RTAB-RESERVE THROW
    TI RTAB-COUNT@ TI TIU RTAB-INSERT TUCK 8 + ! ! ;
: T-FIND-ID  ( id -- index found? ) TI @ TI RTAB-COUNT@ TIU RTAB-SEARCH-ID ;
"""

SUITE = NativeForth(("utils/record-table.f",),
                    prelude=tuple(PRELUDE.strip().splitlines()))


@pytest.fixture(scope="module")
def forth():
    return SUITE.shared()


def run(forth, lines: list[str], max_steps: int = 400_000_000) -> list[list[int]]:
    output = forth.run(["T-CLEAR", *lines], max_steps).decode("latin-1")
    assert "??" not in output, output[-3000:]
    return [[int(token) for token in line.split()]
            for line in output.replace("\r", "").split("\n") if line.strip()]


def test_inserting_keeps_order_and_doubles_the_room(forth):
    lines = run(forth, [
        "T-SHAPE",
        "5 50 T-ADD 3 30 T-ADD 9 90 T-ADD 1 10 T-ADD 7 70 T-ADD",
        "T-VALUES T-SHAPE",
        "2 20 T-ADD 4 40 T-ADD 6 60 T-ADD 8 80 T-ADD",
        "T-VALUES T-SHAPE",
    ])
    assert lines == [
        [0, 0],
        [10, 30, 50, 70, 90],
        [5, 8],
        [10, 20, 30, 40, 50, 60, 70, 80, 90],
        [9, 16],
    ]


def test_an_inserted_slot_is_zeroed(forth):
    lines = run(forth, [
        "1 10 T-ADD 3 30 T-ADD",
        "1 TB TU RTAB-RESERVE . 1 TB TU RTAB-INSERT TU T-ZERO? . CR",
        "T-VALUES",
    ])
    assert lines == [[OK, -1], [10, 0, 30]]


def test_deleting_moves_records_down_and_wipes_the_freed_slot(forth):
    lines = run(forth, [
        "1 10 T-ADD 2 20 T-ADD 3 30 T-ADD 4 40 T-ADD",
        "1 TB TU RTAB-DELETE T-VALUES T-SHAPE",
        "3 TB TU RTAB-NTH TU T-ZERO? . CR",
        "2 TB TU RTAB-DELETE 0 TB TU RTAB-DELETE T-VALUES T-SHAPE",
    ])
    assert lines == [[10, 30, 40], [3, 8], [-1], [30], [1, 8]]


def test_freeing_empties_the_table(forth):
    lines = run(forth, [
        "1 10 T-ADD 2 20 T-ADD",
        "TB TU RTAB-FREE TB RTAB-SIZE T-ZERO? . T-SHAPE",
        "5 50 T-ADD T-VALUES",
    ])
    assert lines == [[-1, 0, 0], [50]]


def test_a_table_put_and_taken_back_is_the_same_bytes(forth):
    lines = run(forth, [
        "3 30 T-ADD 1 10 T-ADD 2 20 T-ADD",
        "TOUT TB TU RTAB-PUT TOUT - . CR",
        "TOUT 3 TC TU RTAB-TAKE . TC RTAB-COUNT@ . TC RTAB.ROOM @ . CR",
        "TB @ TC @ 3 TU * TUCK COMPARE . CR",
        "TB @ TC @ <> . CR",
    ])
    assert lines == [[120], [OK, 3, 3], [0], [-1]]


def test_taking_nothing_allocates_nothing(forth):
    lines = run(forth, ["TOUT 0 TC TU RTAB-TAKE . TC RTAB-SIZE T-ZERO? . CR"])
    assert lines == [[OK, -1]]


def test_a_table_without_memory_is_left_as_it_was(forth):
    # Eight records fill the first room, so the next one must grow it.
    lines = run(forth, [
        "1 1 T-ADD 2 2 T-ADD 3 3 T-ADD 4 4 T-ADD",
        "5 5 T-ADD 6 6 T-ADD 7 7 T-ADD 8 8 T-ADD",
        "TB @ TB 1099511627776 RTAB-RESERVE . TB @ = . T-SHAPE",
        "TOUT 1099511627776 TC TU RTAB-TAKE . TC RTAB-SIZE T-ZERO? . CR",
        "T-VALUES",
    ])
    assert lines == [[NOMEM, -1, 8, 8], [NOMEM, -1], [1, 2, 3, 4, 5, 6, 7, 8]]


def test_a_key_is_found_or_placed(forth):
    lines = run(forth, [
        "2 20 T-ADD 4 40 T-ADD 6 60 T-ADD",
        "2 T-FIND . . 4 T-FIND . . 6 T-FIND . . CR",
        "1 T-FIND . . 3 T-FIND . . 5 T-FIND . . 7 T-FIND . . CR",
        "4 T-KEY TKEY TB @ TB RTAB-COUNT@ TU RTAB-RECORD TB @ TU + = . CR",
        "5 T-KEY TKEY TB @ TB RTAB-COUNT@ TU RTAB-RECORD . CR",
        "1 T-KEY TKEY TB @ 0 TU RTAB-SEARCH . . CR",
    ])
    assert lines == [
        [-1, 0, -1, 1, -1, 2],
        [0, 0, 0, 1, 0, 2, 0, 3],
        [-1],
        [0],
        [0, 0],
    ]


def test_an_id_is_found_or_placed(forth):
    lines = run(forth, [
        "10 100 T-ADD-ID 20 200 T-ADD-ID 30 300 T-ADD-ID",
        "10 T-FIND-ID . . 20 T-FIND-ID . . 30 T-FIND-ID . . CR",
        "5 T-FIND-ID . . 15 T-FIND-ID . . 25 T-FIND-ID . . 35 T-FIND-ID . . CR",
    ])
    assert lines == [[-1, 0, -1, 1, -1, 2], [0, 0, 0, 1, 0, 2, 0, 3]]


def test_only_strict_order_ascends(forth):
    lines = run(forth, [
        "TB @ 0 TU RTAB-ASCENDING? . 1 10 T-ADD TB @ 1 TU RTAB-ASCENDING? . CR",
        "3 30 T-ADD 5 50 T-ADD TB @ 3 TU RTAB-ASCENDING? . CR",
        "1 TB TU RTAB-NTH 0 TB TU RTAB-NTH 32 MOVE TB @ 3 TU RTAB-ASCENDING? . CR",
        "9 TKEY 32 ROT FILL TKEY 1 TB TU RTAB-NTH 32 MOVE TB @ 3 TU RTAB-ASCENDING? . CR",
        "10 1 T-ADD-ID 20 2 T-ADD-ID 30 3 T-ADD-ID TI @ 3 TIU RTAB-IDS-ASCENDING? . CR",
        "20 0 TI TIU RTAB-NTH ! TI @ 3 TIU RTAB-IDS-ASCENDING? . CR",
        "40 0 TI TIU RTAB-NTH ! TI @ 3 TIU RTAB-IDS-ASCENDING? . CR",
        "TI @ 1 TIU RTAB-IDS-ASCENDING? . CR",
    ])
    assert lines == [[-1, -1], [-1], [0], [0], [-1], [0], [0], [-1]]
