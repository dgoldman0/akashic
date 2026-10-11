#!/usr/bin/env python3
"""daybook/automation-store.f on a RAM filesystem.

The suite covers the store's lifecycle and its refusals, a round trip of
every table, table growth, every rule a file is checked against (by COMMIT,
which refuses to write what OPEN would refuse to read, and by OPEN for files
damaged on disk), files that are corrupt, truncated or from a newer format,
and a disk fault at each step of a replacement followed by a cold reopen.

The filesystem's operations are a copy of the RAM binding's, so a check can
make one fail: the Nth sync, every write, or every read.
"""

from __future__ import annotations

import pytest

from native_forth import NativeForth


OK, INVALID, NOMEM, IO, BLOCKED, STATE, ENTROPY = range(7)
CLOSED, READY, BLOCKED_STATE = range(3)
R_CORRUPT, R_FUTURE, R_UNCERTAIN, R_IO = 1, 2, 3, 4

# A RAM filesystem whose operations a check can replace, and words to
# read and write its files whole.  The owner's suite shares it.
RAM_VFS = r"""
CREATE TBUF-RAW 262151 ALLOT  TBUF-RAW 7 + -8 AND CONSTANT TBUF
VARIABLE TLEN
CREATE TV-OPS VFS-OPS-SIZE ALLOT
CREATE TV-BINDING VFS-BINDING-DESC-SIZE ALLOT
VARIABLE TV
VARIABLE T-SYNC-N
: T-OP!  ( xt slot -- ) CELLS TV-OPS + ! ;
\ The T-SYNC-Nth sync from now fails.
: T-SYNC  ( vfs -- ior )
    -1 T-SYNC-N +! T-SYNC-N @ 0= IF DROP VFS-E-IO EXIT THEN _VFS-RAM-SYNCFS ;
\ A write that reports success and stores nothing.
: T-LIE-WRITE  ( buf len off inode vfs -- actual ior ) 2DROP DROP NIP 0 ;
: T-FAIL-READ  ( buf len off inode vfs -- actual ior ) 2DROP 2DROP DROP 0 VFS-E-IO ;
: T-OPS-RESET  ( -- )
    VFS-RAM-OPS TV-OPS VFS-OPS-SIZE CMOVE
    ['] T-SYNC VFS-OP-SYNCFS T-OP!
    0 T-SYNC-N ! ;
T-OPS-RESET
VFS-RAM-BINDING TV-BINDING VFS-BINDING-DESC-SIZE CMOVE
TV-OPS TV-BINDING VB.OPS !
33554432 A-XMEM ARENA-NEW THROW TV-BINDING 0 VFS-NEW THROW DUP TV ! VFS-USE

: T-PATH  ( -- a u ) S" /daybook-automations.bin" ;
: T-RM  ( a u -- ) TV @ VFS-RM DROP ;
: T-THERE?  ( a u -- flag ) TV @ VFS-RESOLVE 0<> ;

\ The file's bytes in TBUF and TLEN, and back.
: T-GET  ( -- )
    T-PATH VFS-FF-READ TV @ VFS-OPEN? THROW
    DUP VFS-SIZE TLEN !
    TBUF TLEN @ 2 PICK VFS-READ-EXACT THROW
    VFS-CLOSE ;
: T-PUT-AT  ( a u -- )
    2DUP T-RM
    2DUP TV @ VFS-CREATE DROP
    VFS-FF-WRITE TV @ VFS-OPEN? THROW
    TBUF TLEN @ 2 PICK VFS-WRITE-EXACT THROW
    VFS-CLOSE ;
: T-PUT  ( -- ) T-PATH T-PUT-AT ;
"""

PRELUDE = RAM_VFS + r"""
CREATE ST-RAW DBAS-SIZE 7 + ALLOT  ST-RAW 7 + -8 AND CONSTANT ST
CREATE ST2-RAW DBAS-SIZE 7 + ALLOT  ST2-RAW 7 + -8 AND CONSTANT ST2
CREATE T-ID 32 ALLOT
CREATE T-ID2 32 ALLOT
VARIABLE T-SUMV  VARIABLE T-SUMV2  VARIABLE T-FILE

\ A configured, closed store over the file.
: T-INIT  ( -- status ) ST DBAS-SIZE 0 FILL TV @ T-PATH ST DBAS-INIT ;
: T-WIPE  ( -- )
    T-PATH T-RM
    ST _DBAS.REPL VREPL-STAGE$ T-RM
    ST _DBAS.REPL VREPL-BACKUP$ T-RM
    ST _DBAS.REPL VREPL-MARKER$ T-RM ;
\ A closed store and no file.
: T-FRESH  ( -- )
    ST DBAS-VALID? IF ST DBAS-CLOSE DROP THEN
    T-OPS-RESET T-INIT DROP T-WIPE ;
\ A cold start: a new descriptor over the same disk.
: T-REOPEN  ( -- status ) ST DBAS-CLOSE DROP T-INIT DROP ST DBAS-OPEN ;
\ Companion files left behind.
: T-LEFTOVERS  ( -- n )
    0 ST _DBAS.REPL VREPL-STAGE$ T-THERE? -
    ST _DBAS.REPL VREPL-BACKUP$ T-THERE? -
    ST _DBAS.REPL VREPL-MARKER$ T-THERE? - ;

\ Recomputes both CRCs of the record in TBUF.
: T-SEAL  ( -- )
    TBUF 64 + TBUF 32 + @ CRC32 TBUF 40 + !
    CRC32-BEGIN TBUF 48 CRC32-ADD TBUF 56 + 8 CRC32-ADD CRC32-END TBUF 48 + ! ;
: T-FILE-SUM  ( -- n ) T-GET TBUF TLEN @ CRC32 TLEN @ 32 LSHIFT + ;

\ Everything the store holds in memory.
: T-SUM  ( -- n )
    CRC32-BEGIN
    ST DBAS-HEADER DBAS-HEADER-SIZE CRC32-ADD
    ST _DBAS.SCHEDULES @ ST DBAS-SCHEDULE-COUNT@ DBAS-SCHEDULE-SIZE * CRC32-ADD
    ST _DBAS.OCCURRENCES @ ST DBAS-OCCURRENCE-COUNT@ DBAS-OCCURRENCE-SIZE *
        CRC32-ADD
    ST _DBAS.KEYS @ ST DBAS-KEY-COUNT@ DBAS-KEY-SIZE * CRC32-ADD
    CRC32-END ST DBAS-SCHEDULE-COUNT@ 32 LSHIFT + ;
: T-COUNTS  ( -- )
    ST DBAS-SCHEDULE-COUNT@ . ST DBAS-OCCURRENCE-COUNT@ . ST DBAS-KEY-COUNT@ . ;
: T-ORDER  ( -- ) ST DBAS-SCHEDULE-COUNT@ 0 ?DO I ST DBAS-SCHEDULE C@ . LOOP ;
: T-ASCENDING?  ( -- flag )
    -1 ST DBAS-SCHEDULE-COUNT@ 1 ?DO
        I 1- ST DBAS-SCHEDULE 32 I ST DBAS-SCHEDULE 32 COMPARE 0< AND
    LOOP ;

\ 2026-10-10 09:00 as local seconds.
2026 10 10 DT-YMD>EPOCH-S DROP 32400 + CONSTANT T-START

\ The 32-byte id whose every byte is N.
: T-ID!  ( n -- id ) T-ID 32 ROT FILL T-ID ;

\ Schedule N: a daily UTC reminder from T-START at revision 1, inserted in
\ order.
: T-SCHEDULE  ( n -- schedule )
    T-ID! ST DBAS-FIND-SCHEDULE DROP ST DBAS-INSERT-SCHEDULE DROP
    T-ID OVER RID-SIZE MOVE
    1 OVER DBAS-S.REVISION !
    ST DBAS-HEADER DBAS-H.SERIAL DUP @ 2 PICK DBAS-S.SERIAL ! 1 SWAP +!
    DBAS-ENABLED OVER DBAS-S.STATE !
    DBAS-ACTION-REMINDER OVER DBAS-S.ACTION !
    DBREC-DAILY OVER DBAS-S.RULE DBREC.FREQ !
    1 OVER DBAS-S.RULE DBREC.INTERVAL !
    T-START OVER DBAS-S.RULE DBREC.START !
    1 OVER DBAS-S.NEXT !
    T-START OVER DBAS-S.NEXT-UTC !
    S" Water the plants" 2 PICK DBAS-S.TITLE DBAS-TITLE-MAX DBAS-FIELD!
    S" UTC0" 2 PICK DBAS-S.ZONE TZ-STRING-MAX DBAS-FIELD! ;

\ Deletes a schedule, keeping its identity.
: T-TOMB  ( schedule -- )
    DUP DBAS-S.ARCHIVED OVER DBAS-S.CREATED OVER - 0 FILL
    DBAS-TOMBSTONE SWAP DBAS-S.STATE ! ;

\ An on-time firing of schedule N's first occurrence, awaiting review.
: T-OCCURRENCE  ( n -- occurrence )
    ST DBAS-APPEND-OCCURRENCE DROP
    ST DBAS-HEADER DBAS-H.OCCURRENCE DUP @ 2 PICK DBAS-O.ID ! 1 SWAP +!
    SWAP T-ID! OVER DBAS-O.RID RID-SIZE MOVE
    1 OVER DBAS-O.REVISION !
    1 OVER DBAS-O.FIRST ! 1 OVER DBAS-O.LAST !
    T-START OVER DBAS-O.FIRST-UTC ! T-START OVER DBAS-O.LAST-UTC !
    1 OVER DBAS-O.COUNT !
    DBAS-ON-TIME OVER DBAS-O.KIND !
    DBAS-DUE OVER DBAS-O.STATE !
    DBAS-CONTINUOUS OVER DBAS-O.BASIS ! ;

\ Create key K, naming schedule N.
: T-KEY  ( k n -- )
    SWAP T-ID! ST DBAS-FIND-KEY DROP ST DBAS-INSERT-KEY DROP
    T-ID OVER DBAS-K.KEY 32 MOVE
    SWAP T-ID! OVER DBAS-K.RID 32 MOVE
    DBAS-K.DIGEST 32 7 FILL ;

: S0 ( -- s ) 0 ST DBAS-SCHEDULE ;
: S1 ( -- s ) 1 ST DBAS-SCHEDULE ;
: S3 ( -- s ) 3 ST DBAS-SCHEDULE ;
: O0 ( -- o ) 0 ST DBAS-OCCURRENCE ;
: O1 ( -- o ) 1 ST DBAS-OCCURRENCE ;
: K0 ( -- k ) 0 ST DBAS-KEY ;
: K1 ( -- k ) 1 ST DBAS-KEY ;
: HD ( -- h ) ST DBAS-HEADER ;

\ Reminders 10, 20 and 30, deleted reminder 40, firings of 20 and 10, and
\ create keys 1 and 2 for 10 and 20, committed as generation 1.
: T-BASE  ( -- status )
    T-FRESH ST DBAS-OPEN DROP
    30 T-SCHEDULE DROP 10 T-SCHEDULE DROP 20 T-SCHEDULE DROP
    40 T-SCHEDULE T-TOMB
    20 T-OCCURRENCE DROP 10 T-OCCURRENCE DROP
    2 20 T-KEY 1 10 T-KEY
    ST DBAS-COMMIT ;
"""

SUITE = NativeForth(("tui/applets/daybook/automation-store.f",),
                    prelude=tuple(PRELUDE.strip().splitlines()))


@pytest.fixture(scope="module")
def forth():
    return SUITE.shared()


def run(forth, lines: list[str], max_steps: int = 4_000_000_000) -> list[list[int]]:
    output = forth.run(lines, max_steps).decode("latin-1")
    assert "??" not in output, output[-3000:]
    return [[int(token) for token in line.split()]
            for line in output.replace("\r", "").split("\n") if line.strip()]


def test_lifecycle_and_its_refusals(forth):
    rows = run(forth, [
        "T-FRESH",
        "TV @ T-PATH ST 1+ DBAS-INIT . TV @ T-PATH 0 DBAS-INIT .",
        "ST2 DBAS-SIZE 0 FILL 0 T-PATH ST2 DBAS-INIT .",
        'TV @ S" relative.bin" ST2 DBAS-INIT . ST2 DBAS-VALID? .',
        "TV @ T-PATH ST DBAS-INIT . CR",
        "ST DBAS-STATE@ . ST DBAS-COMMIT . ST DBAS-IDENTITY NIP . CR",
        "ST DBAS-OPEN . ST DBAS-STATE@ . ST DBAS-OPEN . CR",
        "ST DBAS-CLOSE . ST DBAS-STATE@ . ST DBAS-COMMIT . CR",
        "0 DBAS-OPEN . 0 DBAS-COMMIT . 0 DBAS-CLOSE . ST 1+ DBAS-OPEN . CR",
    ])
    assert rows == [
        [INVALID, INVALID, INVALID, INVALID, 0, STATE],
        [CLOSED, STATE, STATE],
        [OK, READY, STATE],
        [OK, CLOSED, STATE],
        [INVALID, INVALID, INVALID, INVALID],
    ]


def test_a_missing_file_is_an_empty_store(forth):
    rows = run(forth, [
        "T-FRESH ST DBAS-OPEN . ST DBAS-STATE@ . ST DBAS-GENERATION@ . T-COUNTS CR",
        "HD DBAS-H.SERIAL @ . HD DBAS-H.OCCURRENCE @ . HD DBAS-H.RETAIN @ . CR",
        'HD DBAS-H.ZONE DBAS-FIELD$ S" UTC0" COMPARE . '
        "HD DBAS-H.STORE-ID RID-ZERO? . T-PATH T-THERE? . CR",
        # The identity is drawn once and kept.
        "ST DBAS-IDENTITY . DUP RID-ZERO? . T-ID2 RID-SIZE MOVE",
        "ST DBAS-IDENTITY . T-ID2 RID= . CR",
        "ST DBAS-COMMIT . ST DBAS-GENERATION@ . T-PATH T-THERE? . T-LEFTOVERS . CR",
        "T-REOPEN . ST DBAS-GENERATION@ . T-COUNTS "
        "HD DBAS-H.STORE-ID T-ID2 RID= . CR",
        "ST DBAS-COMMIT . T-REOPEN . ST DBAS-GENERATION@ . CR",
    ])
    assert rows == [
        [OK, READY, 0, 0, 0, 0],
        [1, 1, 32],
        [0, -1, 0],
        [OK, 0, OK, -1],
        [OK, 1, -1, 0],
        [OK, 1, 0, 0, 0, -1],
        [OK, OK, 2],
    ]


def test_every_table_round_trips_and_grows(forth):
    rows = run(forth, [
        "T-BASE . ST DBAS-GENERATION@ . T-COUNTS T-SUM T-SUMV ! T-ORDER CR",
        "T-REOPEN . ST DBAS-GENERATION@ . T-COUNTS T-SUM T-SUMV @ = . T-ORDER CR",
        "20 T-ID! ST DBAS-FIND-SCHEDULE SWAP . . "
        "25 T-ID! ST DBAS-FIND-SCHEDULE SWAP . . CR",
        "2 T-ID! ST DBAS-FIND-KEY SWAP . . 3 T-ID! ST DBAS-FIND-KEY SWAP . . CR",
        "2 ST DBAS-FIND-OCCURRENCE SWAP . . 3 ST DBAS-FIND-OCCURRENCE SWAP . . CR",
        "1 ST DBAS-OCCURRENCE @ . 0 ST DBAS-DELETE-OCCURRENCE "
        "ST DBAS-OCCURRENCE-COUNT@ . 0 ST DBAS-OCCURRENCE @ . CR",
        # Forty more, each inserted in front of the last, past several
        # growths of the table.
        ": T-MANY 90 50 DO 139 I - T-SCHEDULE DROP LOOP ;",
        "T-MANY ST DBAS-COMMIT . ST DBAS-SCHEDULE-COUNT@ . T-ASCENDING? . CR",
        "T-SUM T-SUMV ! T-REOPEN . ST DBAS-GENERATION@ . T-COUNTS "
        "T-SUM T-SUMV @ = . T-ASCENDING? . CR",
        ": T-FIND-ALL -1 90 50 DO I T-ID! ST DBAS-FIND-SCHEDULE NIP AND LOOP ;",
        "T-FIND-ALL . 49 T-ID! ST DBAS-FIND-SCHEDULE SWAP . . CR",
    ])
    assert rows == [
        [OK, 1, 4, 2, 2, 10, 20, 30, 40],
        [OK, 1, 4, 2, 2, -1, 10, 20, 30, 40],
        [1, -1, 2, 0],
        [1, -1, 2, 0],
        [1, -1, 2, 0],
        [2, 1, 2],
        [OK, 44, -1],
        [OK, 2, 44, 1, 2, -1, -1],
        [-1, 4, 0],
    ]


# Edits COMMIT must refuse, each made to the committed base.
COMMIT_REFUSALS = {
    "zero RID": "S0 32 0 FILL",
    "RIDs out of order": "S0 T-ID2 32 MOVE S1 S0 32 MOVE T-ID2 S1 32 MOVE",
    "revision zero": "0 S0 DBAS-S.REVISION !",
    "serial zero": "0 S0 DBAS-S.SERIAL !",
    "serial not below the counter": "HD DBAS-H.SERIAL @ S0 DBAS-S.SERIAL !",
    "state zero": "0 S0 DBAS-S.STATE !",
    "state past tombstone": "5 S0 DBAS-S.STATE !",
    "archived not a flag": "2 S0 DBAS-S.ARCHIVED !",
    "unknown action": "2 S0 DBAS-S.ACTION !",
    "result without an occurrence": "DBAS-ON-TIME S0 DBAS-S.RESULT !",
    "occurrence without a result": "1 S0 DBAS-S.LAST !",
    "unknown result": "1 S0 DBAS-S.LAST ! 3 S0 DBAS-S.RESULT !",
    "last occurrence not below the counter":
        "HD DBAS-H.OCCURRENCE @ S0 DBAS-S.LAST ! DBAS-MISSED S0 DBAS-S.RESULT !",
    "negative pruned count": "-1 S0 DBAS-S.PRUNED !",
    "empty title": "0 S0 DBAS-S.TITLE !",
    "title too long": "DBAS-TITLE-MAX 1+ S0 DBAS-S.TITLE !",
    "control character in the title": "9 S0 DBAS-S.TITLE 8 + C!",
    "delete character in the title": "127 S0 DBAS-S.TITLE 8 + C!",
    "invalid UTF-8 in the title": "255 S0 DBAS-S.TITLE 8 + C!",
    "bytes after the title": "1 S0 DBAS-S.TITLE 8 + DBAS-TITLE-MAX + 1- C!",
    "empty zone": "0 S0 DBAS-S.ZONE !",
    "zone that does not parse":
        'S" EST" S0 DBAS-S.ZONE TZ-STRING-MAX DBAS-FIELD!',
    "bytes after the zone": "1 S0 DBAS-S.ZONE 8 + TZ-STRING-MAX + 1- C!",
    "invalid rule": "0 S0 DBAS-S.RULE DBREC.INTERVAL !",
    "rule that never fires":
        "DBREC-END-UNTIL S0 DBAS-S.RULE DBREC.END ! "
        "T-START 1- S0 DBAS-S.RULE DBREC.LIMIT !",
    "next instant off its rule": "1 S0 DBAS-S.NEXT-UTC +!",
    "next occurrence past UNTIL":
        "DBREC-END-UNTIL S0 DBAS-S.RULE DBREC.END ! "
        "T-START S0 DBAS-S.RULE DBREC.LIMIT ! 2 S0 DBAS-S.NEXT ! "
        "T-START 86400 + S0 DBAS-S.NEXT-UTC !",
    "next occurrence past COUNT":
        "DBREC-END-COUNT S0 DBAS-S.RULE DBREC.END ! "
        "1 S0 DBAS-S.RULE DBREC.LIMIT ! 2 S0 DBAS-S.NEXT ! "
        "T-START 86400 + S0 DBAS-S.NEXT-UTC !",
    "enabled with no next occurrence": "0 S0 DBAS-S.NEXT ! 0 S0 DBAS-S.NEXT-UTC !",
    "completed with a next occurrence": "DBAS-COMPLETED S0 DBAS-S.STATE !",
    "reserved schedule bytes": "1 S0 DBAS-SCHEDULE-SIZE + 1- C!",
    "tombstone keeping a title": "1 S3 DBAS-S.TITLE !",
    "tombstone keeping a next occurrence": "1 S3 DBAS-S.NEXT !",
    "occurrence id zero": "0 O0 DBAS-O.ID !",
    "occurrence id not below the counter": "HD DBAS-H.OCCURRENCE @ O1 DBAS-O.ID !",
    "occurrence ids out of order":
        "O0 DBAS-O.ID @ O1 DBAS-O.ID @ O0 DBAS-O.ID ! O1 DBAS-O.ID !",
    "occurrence of an unknown schedule": "99 T-ID! O0 DBAS-O.RID 32 MOVE",
    "occurrence of a deleted schedule": "S3 O0 DBAS-O.RID 32 MOVE",
    "occurrence ahead of its schedule's revision": "2 O0 DBAS-O.REVISION !",
    "occurrence revision zero": "0 O0 DBAS-O.REVISION !",
    "unknown occurrence kind": "3 O0 DBAS-O.KIND !",
    "unknown occurrence state": "3 O0 DBAS-O.STATE !",
    "unknown clock basis": "4 O0 DBAS-O.BASIS !",
    "first ordinal zero": "0 O0 DBAS-O.FIRST !",
    "last ordinal before the first": "2 O0 DBAS-O.FIRST !",
    "last instant before the first": "T-START 1- O0 DBAS-O.LAST-UTC !",
    "merged count zero": "0 O0 DBAS-O.COUNT !",
    "merged count beyond its ordinals": "2 O0 DBAS-O.COUNT !",
    "review time while awaiting review": "5 O0 DBAS-O.REVIEWED !",
    "zero create key": "K0 32 0 FILL",
    "create keys out of order": "K0 T-ID2 32 MOVE K1 K0 32 MOVE T-ID2 K1 32 MOVE",
    "create key for an unknown schedule": "99 T-ID! K0 DBAS-K.RID 32 MOVE",
    "serial counter zero": "0 HD DBAS-H.SERIAL !",
    "occurrence counter zero": "0 HD DBAS-H.OCCURRENCE !",
    "negative retention": "-1 HD DBAS-H.RETAIN !",
    "default zone that does not parse":
        'S" EST" HD DBAS-H.ZONE TZ-STRING-MAX DBAS-FIELD!',
    "reserved header bytes": "1 HD DBAS-HEADER-SIZE + 1- C!",
}

# Edits COMMIT accepts, so the refusals above are the edits' own.
COMMIT_ACCEPTS = {
    "a new title": 'S" Feed the cat" S0 DBAS-S.TITLE DBAS-TITLE-MAX DBAS-FIELD!',
    "an archived reminder": "1 S0 DBAS-S.ARCHIVED !",
    "a paused reminder": "DBAS-PAUSED S0 DBAS-S.STATE !",
    "a completed reminder":
        "DBAS-COMPLETED S0 DBAS-S.STATE ! 0 S0 DBAS-S.NEXT ! 0 S0 DBAS-S.NEXT-UTC !",
    "a reviewed firing": "DBAS-REVIEWED O0 DBAS-O.STATE ! 5 O0 DBAS-O.REVIEWED !",
    "a missed firing of three":
        "DBAS-MISSED O0 DBAS-O.KIND ! DBAS-JUMP O0 DBAS-O.BASIS ! "
        "3 O0 DBAS-O.LAST ! 3 O0 DBAS-O.COUNT ! T-START 172800 + O0 DBAS-O.LAST-UTC !",
    "the last firing recorded":
        "2 S1 DBAS-S.LAST ! DBAS-ON-TIME S1 DBAS-S.RESULT !",
    # New York keeps daylight time on 10 October: 09:00 is 13:00 UTC.
    "a zone with daylight time":
        'S" EST5EDT,M3.2.0,M11.1.0" S0 DBAS-S.ZONE TZ-STRING-MAX DBAS-FIELD! '
        "T-START 14400 + S0 DBAS-S.NEXT-UTC !",
    "no retention": "0 HD DBAS-H.RETAIN !",
    "a title of the most bytes allowed":
        "S0 DBAS-S.TITLE 8 + DBAS-TITLE-MAX 65 FILL DBAS-TITLE-MAX S0 DBAS-S.TITLE !",
}


def _commit_rows(forth, edits: dict[str, str]) -> dict[str, list[int]]:
    lines = [
        "T-BASE DROP T-SUM T-SUMV ! T-FILE-SUM T-FILE ! "
        f"{edit} ST DBAS-COMMIT . ST DBAS-STATE@ . ST DBAS-GENERATION@ . "
        "T-SUM T-SUMV @ = . T-FILE-SUM T-FILE @ = . CR"
        for edit in edits.values()
    ]
    rows = run(forth, lines, max_steps=16_000_000_000)
    assert len(rows) == len(edits), rows
    return dict(zip(edits, rows))


def test_commit_refuses_what_open_would_refuse(forth):
    """A refused commit writes nothing and reloads the committed file."""

    for name, row in _commit_rows(forth, COMMIT_REFUSALS).items():
        assert row == [INVALID, READY, 1, -1, -1], name


def test_commit_accepts_valid_edits(forth):
    for name, row in _commit_rows(forth, COMMIT_ACCEPTS).items():
        assert row == [OK, READY, 2, 0, 0], name


# Damage to the base's file on disk, and the reason OPEN gives for it.
LOAD_REFUSALS = {
    "a flipped payload byte": ("TBUF 300 + DUP C@ 1 XOR SWAP C!", R_CORRUPT),
    "a flipped header byte": ("TBUF 24 + DUP C@ 1 XOR SWAP C!", R_CORRUPT),
    "a newer format": ("2 TBUF 8 + ! T-SEAL", R_FUTURE),
    "an older format": ("0 TBUF 8 + ! T-SEAL", R_CORRUPT),
    "another magic": ("TBUF DUP C@ 1 XOR SWAP C! T-SEAL", R_CORRUPT),
    "generation zero": ("0 TBUF 24 + ! T-SEAL", R_CORRUPT),
    "a truncated file": ("TLEN @ 8 - TLEN !", R_CORRUPT),
    "a file shorter than a header": ("40 TLEN !", R_CORRUPT),
    "an empty file": ("0 TLEN !", R_CORRUPT),
    "trailing bytes": ("TBUF TLEN @ + 8 0 FILL 8 TLEN +!", R_CORRUPT),
    "a schedule count past the tables": ("5 TBUF 112 + ! T-SEAL", R_CORRUPT),
    "no store identity": ("TBUF 64 + 32 0 FILL T-SEAL", R_CORRUPT),
    "a reminder at revision zero": ("0 TBUF 320 + ! T-SEAL", R_CORRUPT),
}


def test_a_file_open_cannot_trust_blocks_the_store(forth):
    """Nothing loads, nothing is written, and reopening blocks again."""

    lines = [
        "T-BASE DROP ST DBAS-CLOSE DROP T-GET "
        f"{patch} T-PUT T-FILE-SUM T-FILE ! "
        "T-INIT DROP ST DBAS-OPEN . ST DBAS-STATE@ . ST DBAS-REASON@ . T-COUNTS "
        "ST DBAS-COMMIT . ST DBAS-IDENTITY NIP . T-FILE-SUM T-FILE @ = . "
        "ST DBAS-CLOSE DROP ST DBAS-OPEN . ST DBAS-REASON@ . CR"
        for patch, _ in LOAD_REFUSALS.values()
    ]
    rows = run(forth, lines, max_steps=8_000_000_000)
    assert len(rows) == len(LOAD_REFUSALS), rows
    for (name, (_, reason)), row in zip(LOAD_REFUSALS.items(), rows):
        assert row == [BLOCKED, BLOCKED_STATE, reason, 0, 0, 0,
                       BLOCKED, STATE, -1, BLOCKED, reason], name


def test_unreadable_file_and_unresolvable_marker_block(forth):
    rows = run(forth, [
        # A read fault.  Once reads work again, the file opens.
        "T-BASE DROP ST DBAS-CLOSE DROP ' T-FAIL-READ VFS-OP-READ T-OP! "
        "T-INIT DROP ST DBAS-OPEN . ST DBAS-STATE@ . ST DBAS-REASON@ . "
        "T-OPS-RESET ST DBAS-CLOSE DROP ST DBAS-OPEN . ST DBAS-GENERATION@ . CR",
        # A replacement marker nobody can read.
        "T-BASE DROP ST DBAS-CLOSE DROP TBUF 64 88 FILL 64 TLEN ! "
        "ST _DBAS.REPL VREPL-MARKER$ T-PUT-AT "
        "T-INIT DROP ST DBAS-OPEN . ST DBAS-STATE@ . ST DBAS-REASON@ . CR",
    ])
    assert rows == [
        [BLOCKED, BLOCKED_STATE, R_IO, OK, 1],
        [BLOCKED, BLOCKED_STATE, R_UNCERTAIN],
    ]


def _fault_line(start: str, sync: int) -> str:
    return (
        f"{start} T-SUM T-SUMV ! 99 T-SCHEDULE DROP ST DBAS-IDENTITY 2DROP "
        f"T-SUM T-SUMV2 ! {sync} T-SYNC-N ! ST DBAS-COMMIT . 0 T-SYNC-N ! "
        "ST DBAS-STATE@ . ST DBAS-REASON@ . ST DBAS-GENERATION@ . "
        "T-SUM T-SUMV @ = . "
        "T-REOPEN . ST DBAS-GENERATION@ . ST DBAS-SCHEDULE-COUNT@ . "
        "T-SUM T-SUMV2 @ = . T-LEFTOVERS . CR"
    )


def test_a_fault_at_each_replacement_step(forth):
    """Replacing a file syncs six times.  A fault up to the fourth rolls
    back and reloads the old file; at the fifth, when the commit point's
    durability is unknown, the store blocks until a reopen recovers the new
    file; at the sixth, cleanup, the commit stands."""

    rolled_back = [IO, READY, 0, 1, -1, OK, 1, 4, 0, 0]
    rows = run(forth, [_fault_line("T-BASE DROP", sync) for sync in range(1, 8)],
               max_steps=8_000_000_000)
    assert rows == [
        rolled_back,
        rolled_back,
        rolled_back,
        rolled_back,
        [BLOCKED, BLOCKED_STATE, R_UNCERTAIN, 1, 0, OK, 2, 5, -1, 0],
        [OK, READY, 0, 2, 0, OK, 2, 5, -1, 0],
        [OK, READY, 0, 2, 0, OK, 2, 5, -1, 0],
    ]


def test_a_fault_while_writing_the_first_file(forth):
    """With no file yet there is no backup to rotate: four syncs."""

    rolled_back = [IO, READY, 0, 0, -1, OK, 0, 0, 0, 0]
    start = "T-FRESH ST DBAS-OPEN DROP"
    rows = run(forth, [_fault_line(start, sync) for sync in range(1, 6)],
               max_steps=8_000_000_000)
    assert rows == [
        rolled_back,
        rolled_back,
        rolled_back,
        [BLOCKED, BLOCKED_STATE, R_UNCERTAIN, 0, 0, OK, 1, 1, -1, 0],
        [OK, READY, 0, 1, 0, OK, 1, 1, -1, 0],
    ]


def test_a_write_that_stores_nothing_is_caught(forth):
    rows = run(forth, [
        "T-BASE DROP T-SUM T-SUMV ! 99 T-SCHEDULE DROP "
        "' T-LIE-WRITE VFS-OP-WRITE T-OP! ST DBAS-COMMIT . T-OPS-RESET "
        "ST DBAS-STATE@ . ST DBAS-GENERATION@ . T-SUM T-SUMV @ = . "
        "T-REOPEN . ST DBAS-GENERATION@ . ST DBAS-SCHEDULE-COUNT@ . "
        "T-LEFTOVERS . CR",
    ])
    assert rows == [[IO, READY, 1, -1, OK, 1, 4, 0]]
