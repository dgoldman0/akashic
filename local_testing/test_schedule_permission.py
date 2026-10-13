#!/usr/bin/env python3
"""runtime/schedule-permission.f on a RAM filesystem.

The suite covers the store's lifecycle; grants, their replays and the
revision a changed grant moves on; the refusals of a request no Practice
may grant; every standing a request can have; revoking, after which a
schedule's next grant is a new permission; RIDs against hashlib; every
rule a file is checked against, by a write and by OPEN; damage on disk;
and disk faults.
"""

from __future__ import annotations

import hashlib
import struct

import pytest

from native_forth import NativeForth
from test_daybook_automation_owner import NOW
from test_daybook_automation_store import RAM_VFS


OK, INVALID, NOMEM, IO, BLOCKED, STATE, ENTROPY, NOT_FOUND = range(8)
CLOSED, READY, BLOCKED_STATE = range(3)
R_CORRUPT, R_FUTURE, R_UNCERTAIN, R_IO = 1, 2, 3, 4
APPROVED, NONE, WITHDRAWN, CHANGED, PRACTICE, UNAVAILABLE = range(1, 7)
AGENT_RUN = 2

PRELUDE = RAM_VFS + rf"""
{NOW} CONSTANT T-NOW
CREATE PS-RAW SPERM-SIZE 7 + ALLOT  PS-RAW 7 + -8 AND CONSTANT PS
: P-PATH  ( -- a u ) S" /schedule-perms.bin" ;
: P-INIT  ( -- status ) PS SPERM-SIZE 0 FILL TV @ P-PATH PS SPERM-INIT ;
: P-WIPE  ( -- )
    P-PATH T-RM
    PS _SPERM.REPL VREPL-STAGE$ T-RM
    PS _SPERM.REPL VREPL-BACKUP$ T-RM
    PS _SPERM.REPL VREPL-MARKER$ T-RM ;
\ An open store over no file.
: P-FRESH  ( -- )
    PS SPERM-VALID? IF PS SPERM-CLOSE DROP THEN
    T-OPS-RESET P-INIT DROP P-WIPE PS SPERM-OPEN DROP ;
\ A cold start over the same disk.
: P-REOPEN  ( -- status ) PS SPERM-CLOSE DROP P-INIT DROP PS SPERM-OPEN ;
\ The file's bytes in TBUF and TLEN, and back.
: P-GET  ( -- )
    P-PATH VFS-FF-READ TV @ VFS-OPEN? THROW
    DUP VFS-SIZE TLEN !
    TBUF TLEN @ 2 PICK VFS-READ-EXACT THROW
    VFS-CLOSE ;
: P-PUT  ( -- ) P-PATH T-PUT-AT ;
\ Recomputes both CRCs of the record in TBUF.
: T-SEAL  ( -- )
    TBUF 64 + TBUF 32 + @ CRC32 TBUF 40 + !
    CRC32-BEGIN TBUF 48 CRC32-ADD TBUF 56 + 8 CRC32-ADD CRC32-END TBUF 48 + ! ;
: P-FILE-SUM  ( -- n ) P-GET TBUF TLEN @ CRC32 TLEN @ 32 LSHIFT + ;
\ Everything the store holds in memory.
: P-SUM  ( -- n )
    CRC32-BEGIN
    PS SPERM-HEADER SPERM-HEADER-SIZE CRC32-ADD
    PS _SPERM.TABLE @ PS SPERM-COUNT@ SPERM-PERMISSION-SIZE * CRC32-ADD
    CRC32-END PS SPERM-COUNT@ 32 LSHIFT + ;
VARIABLE P-SUMV  VARIABLE P-FILE
: GEN  ( -- n ) PS SPERM-GENERATION@ ;
\ Reads fail until READY. prints the store's state and restores them: a
\ refusal that touched the disk would have reloaded and blocked.
: NO-READS  ( -- ) ['] T-FAIL-READ VFS-OP-READ T-OP! ;
: READY.  ( -- ) PS SPERM-STATE@ . T-OPS-RESET ;
: COUNT.  ( -- ) PS SPERM-COUNT@ . ;
: B32.  ( a -- ) 32 0 DO DUP I + C@ . LOOP DROP ;

\ Practices 4 and 5, and none.
CREATE PR1 32 ALLOT  PR1 32 4 FILL
CREATE PR2 32 ALLOT  PR2 32 5 FILL
CREATE PR0 32 ALLOT  PR0 32 0 FILL
CREATE RID1 32 ALLOT
CREATE P-TMP SPERM-PERMISSION-SIZE ALLOT

\ An Agent run's operands in OPS: five minutes, 4096 bytes disclosed and
\ 16384 kept, the scripted provider's gpt-test, and a short prompt.
CREATE AD-RAW SACT-DRAFT-SIZE 7 + ALLOT  AD-RAW 7 + -8 AND CONSTANT AD
CREATE OPS-RAW 1031 ALLOT  OPS-RAW 7 + -8 AND CONSTANT OPS
VARIABLE OPS-U
: A-OPS  ( -- )
    AD SACT-DRAFT-INIT
    300000 AD SACT-D.TIME ! 4096 AD SACT-D.DISCLOSURE ! 16384 AD SACT-D.OUTPUT !
    S" org.akashic.agent.testing.scripted" AD SACT-D.PROVIDER SACT-D!
    S" gpt-test" AD SACT-D.MODEL SACT-D!
    S" Summarize the news." AD SACT-D.PROMPT SACT-D!
    AD OPS 1024 SACT-AGENT-ENCODE DROP OPS-U ! ;
: A-PROMPT  ( a u -- )
    AD SACT-D.PROMPT SACT-D! AD OPS 1024 SACT-AGENT-ENCODE DROP OPS-U ! ;

\ An approval request in RQ from store bytes 3 for schedule bytes S, which
\ runs at trigger bytes 7 with OPS.
CREATE RQ-RAW 2063 ALLOT  RQ-RAW 7 + -8 AND CONSTANT RQ
: R-ASK  ( s -- )
    S" Read the news" NIP S" daily at 09:00" NIP OPS-U @ SDSP-REQUEST-SIZE
        RQ SDSP-REQUEST-INIT
    SACT-AGENT-RUN RQ SDSP-R.ACTION ! SACT-SCHEMA RQ SDSP-R.SCHEMA !
    RQ SDSP-R.STORE 32 3 FILL RQ SDSP-R.SCHEDULE 32 ROT FILL
    1 RQ SDSP-R.REVISION ! RQ SDSP-R.TRIGGER-DIGEST 32 7 FILL
    S" Read the news" RQ SDSP-TAIL+ S" daily at 09:00" RQ SDSP-TAIL+
    OPS OPS-U @ RQ SDSP-TAIL+
    SACT-AGENT-RUN SACT-SCHEMA OPS OPS-U @ RQ SDSP-R.OPERANDS-DIGEST SACT-DIGEST ;
\ Grants RQ in PRACTICE at NOW; PP is the permission.
VARIABLE PP
: GRANT  ( practice now -- status ) RQ -ROT PS SPERM-GRANT SWAP PP ! ;
\ RQ names permission P at its revision.
: NAME  ( p -- )
    DUP RQ SDSP-R.PERMISSION RID-COPY SPERM-P.REVISION @ RQ SDSP-R.PERMISSION-REVISION ! ;
: MATCH.  ( practice -- ) RQ SWAP PS SPERM-MATCH . ;
\ Revision, serial, Practice, store, schedule, action, schema, trigger,
\ effects, time, disclosure, output and when granted; then whether the
\ operand digest is RQ's.
: PERM.  ( p -- )
    DUP SPERM-P.REVISION @ . DUP SPERM-P.SERIAL @ . DUP SPERM-P.PRACTICE C@ .
    DUP SPERM-P.STORE C@ . DUP SPERM-P.SCHEDULE C@ . DUP SPERM-P.ACTION @ .
    DUP SPERM-P.SCHEMA @ . DUP SPERM-P.TRIGGER-DIGEST C@ . DUP SPERM-P.EFFECTS @ .
    DUP SPERM-P.TIME @ . DUP SPERM-P.DISCLOSURE @ . DUP SPERM-P.OUTPUT @ .
    DUP SPERM-P.GRANTED @ .
    SPERM-P.OPERANDS-DIGEST 32 RQ SDSP-R.OPERANDS-DIGEST 32 COMPARE . ;
: P0  ( -- p ) 0 PS SPERM-NTH ;
: P1  ( -- p ) 1 PS SPERM-NTH ;
: HD  ( -- h ) PS SPERM-HEADER ;
\ Schedules 1 and 2 granted in Practice 4, as generations 1 and 2.
: P-BASE  ( -- )
    P-FRESH A-OPS 1 R-ASK PR1 T-NOW GRANT DROP 2 R-ASK PR1 T-NOW GRANT DROP ;
\ Schedule 1 alone, as generation 1.
: P-ONE  ( -- ) P-FRESH A-OPS 1 R-ASK PR1 T-NOW GRANT DROP ;
\ A file that holds no permission: one granted, then revoked.
: P-EMPTY  ( -- )
    P-FRESH A-OPS 1 R-ASK PR1 T-NOW GRANT DROP PP @ RID1 RID-COPY
    RID1 PS SPERM-REVOKE DROP ;
"""

SUITE = NativeForth(("runtime/schedule-permission.f",),
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
        "P-FRESH PS SPERM-STATE@ . GEN . COUNT. P-PATH T-THERE? . CR",
        "TV @ P-PATH PS 1+ SPERM-INIT . TV @ P-PATH 0 SPERM-INIT . "
        "TV @ P-PATH PS SPERM-INIT . 0 P-PATH PS SPERM-INIT . CR",
        "PS SPERM-OPEN . PS SPERM-CLOSE . PS SPERM-STATE@ . "
        "RQ PR1 1 PS SPERM-GRANT . . RID1 PS SPERM-REVOKE . RID1 PS SPERM-FIND . "
        "PR1 MATCH. CR",
    ])
    assert rows == [
        [READY, 0, 0, 0],
        [INVALID, INVALID, STATE, STATE],
        [STATE, OK, CLOSED, STATE, 0, STATE, 0, UNAVAILABLE],
    ]


def test_a_grant_and_its_replays(forth):
    rows = run(forth, [
        f"P-FRESH A-OPS 1 R-ASK PR1 {NOW} GRANT . PP @ PERM. GEN . COUNT. CR",
        # The same grant again is the same permission, unwritten.
        f"PP @ RID1 RID-COPY PR1 {NOW + 1000} GRANT . PP @ RID1 RID= . "
        "PP @ SPERM-P.REVISION @ . PP @ SPERM-P.GRANTED @ . GEN . CR",
        # A changed prompt replaces the grant and moves the revision on.
        f'S" Summarize the town." A-PROMPT 1 R-ASK PR1 {NOW + 2000} GRANT . '
        "PP @ RID1 RID= . PP @ PERM. GEN . COUNT. CR",
        # Another schedule, and the first in another Practice.
        f"A-OPS 2 R-ASK PR1 {NOW} GRANT . PP @ SPERM-P.SERIAL @ . "
        f"1 R-ASK PR2 {NOW} GRANT . PP @ SPERM-P.SERIAL @ . PP @ SPERM-P.PRACTICE C@ . "
        "COUNT. GEN . PS _SPERM.TABLE @ PS SPERM-COUNT@ SPERM-PERMISSION-SIZE "
        "RTAB-ASCENDING? . CR",
        "P-SUM P-SUMV ! P-REOPEN . COUNT. GEN . P-SUM P-SUMV @ = . CR",
        # A request may name its own Practice, and with no clock the time is
        # unknown.
        "3 R-ASK RQ SDSP-R.PRACTICE 32 4 FILL PR1 -1 GRANT . "
        "PP @ SPERM-P.GRANTED @ . CR",
        # A new trigger replaces the grant too; schedule bytes 3 of another
        # store are another schedule.
        f"RQ SDSP-R.TRIGGER-DIGEST 32 8 FILL PR1 {NOW} GRANT . "
        "PP @ SPERM-P.REVISION @ . PP @ SPERM-P.SERIAL @ . "
        f"RQ SDSP-R.STORE 32 9 FILL PR1 {NOW} GRANT . PP @ SPERM-P.REVISION @ . "
        "PP @ SPERM-P.SERIAL @ . COUNT. CR",
    ])
    assert rows == [
        [OK, 1, 1, 4, 3, 1, AGENT_RUN, 1, 7, 0, 300_000, 4096, 16_384, NOW, 0, 1, 1],
        [OK, -1, 1, NOW, 1],
        [OK, -1, 2, 1, 4, 3, 1, AGENT_RUN, 1, 7, 0, 300_000, 4096, 16_384,
         NOW + 2000, 0, 2, 1],
        [OK, 2, OK, 3, 5, 3, 4, -1],
        [OK, 3, 4, -1],
        [OK, 0],
        [OK, 2, 4, OK, 1, 5, 5],
    ]


def test_rids_are_the_digest_of_identity_and_serial(forth):
    rows = run(forth, [
        "P-BASE HD B32. CR",
        "P0 DUP SPERM-P.SERIAL @ . B32. CR",
        "P1 DUP SPERM-P.SERIAL @ . B32. CR",
    ])
    store = bytes(rows[0])
    assert any(store)
    serials = []
    for row in rows[1:]:
        serial, rid = row[0], bytes(row[1:])
        serials.append(serial)
        assert rid == hashlib.sha3_256(
            b"akashic.sched.permission.v1" + store + struct.pack("<Q", serial)
        ).digest()
    assert sorted(serials) == [1, 2]


GRANT_REFUSALS = {
    "no Practice": ("", "PR0"),
    "a request naming another Practice": ("RQ SDSP-R.PRACTICE 32 5 FILL", "PR1"),
    "an occurrence": ("SDSP-K-ON-TIME RQ SDSP-R.KIND !", "PR1"),
    "no trigger digest": ("RQ SDSP-R.TRIGGER-DIGEST 32 0 FILL", "PR1"),
    "a size that is not its own": ("8 RQ SDSP-R.SIZE +!", "PR1"),
    "operands that are not the digest's": ("1 RQ SDSP-R.OPERANDS-DIGEST +!", "PR1"),
    "a reminder": ("SACT-REMINDER RQ SDSP-R.ACTION !", "PR1"),
    "no schedule": ("RQ SDSP-R.SCHEDULE 32 0 FILL", "PR1"),
}


def test_grant_refusals(forth):
    """Each refusal comes before any edit: over a store holding schedule
    1's permission, with reads failing, the store stays ready."""

    lines = [f"P-ONE 2 R-ASK {edit} NO-READS {practice} {NOW} GRANT . READY. PP @ . "
             "GEN . COUNT. CR"
             for edit, practice in GRANT_REFUSALS.values()]
    rows = run(forth, lines)
    assert len(rows) == len(GRANT_REFUSALS), rows
    for name, row in zip(GRANT_REFUSALS, rows):
        assert row == [INVALID, READY, 0, 1, 1], name


MATCHES = {
    "the permission": ("", "PR1", APPROVED),
    "a request naming its own Practice": ("RQ SDSP-R.PRACTICE 32 4 FILL", "PR1", APPROVED),
    "a request naming no permission": ("RQ SDSP-R.PERMISSION 32 0 FILL", "PR1", NONE),
    "an unknown permission": ("RQ SDSP-R.PERMISSION 32 9 FILL", "PR1", WITHDRAWN),
    "an older revision": ("2 RQ SDSP-R.PERMISSION-REVISION !", "PR1", CHANGED),
    "another prompt":
        ('S" Summarize the town." A-PROMPT 1 R-ASK PP @ NAME', "PR1", CHANGED),
    "another trigger": ("RQ SDSP-R.TRIGGER-DIGEST 32 8 FILL", "PR1", CHANGED),
    "another schedule": ("RQ SDSP-R.SCHEDULE 32 2 FILL", "PR1", CHANGED),
    "another store": ("RQ SDSP-R.STORE 32 2 FILL", "PR1", CHANGED),
    "another action": ("SACT-REMINDER RQ SDSP-R.ACTION !", "PR1", CHANGED),
    "another schema": ("2 RQ SDSP-R.SCHEMA !", "PR1", CHANGED),
    "Desk in another Practice": ("", "PR2", PRACTICE),
    "a request from another Practice": ("RQ SDSP-R.PRACTICE 32 5 FILL", "PR1", PRACTICE),
}


def test_how_a_request_stands(forth):
    lines = [f"P-FRESH A-OPS 1 R-ASK PR1 {NOW} GRANT DROP PP @ NAME {edit} {practice} MATCH. CR"
             for edit, practice, _ in MATCHES.values()]
    rows = run(forth, lines)
    assert len(rows) == len(MATCHES), rows
    for (name, (_, _, standing)), row in zip(MATCHES.items(), rows):
        assert row == [standing], name


def test_revoking(forth):
    rows = run(forth, [
        f"P-FRESH A-OPS 1 R-ASK PR1 {NOW} GRANT . PP @ NAME PP @ RID1 RID-COPY "
        "RID1 PS SPERM-REVOKE . COUNT. GEN . PR1 MATCH. RID1 PS SPERM-FIND . "
        "RID1 PS SPERM-REVOKE . GEN . CR",
        # The schedule's next grant is a new permission.
        f"PR1 {NOW} GRANT . PP @ SPERM-P.SERIAL @ . PP @ RID1 RID= . "
        "PP @ SPERM-P.REVISION @ . CR",
        "P-REOPEN . COUNT. RID1 PS SPERM-FIND . PR1 MATCH. CR",
    ])
    assert rows == [
        [OK, OK, 0, 2, WITHDRAWN, 0, NOT_FOUND, 2],
        [OK, 2, 0, 1],
        [OK, 1, 0, WITHDRAWN],
    ]


# Edits a write must refuse, each made to P-BASE.
COMMIT_REFUSALS = {
    "a RID its serial does not give":
        "P0 SPERM-P.SERIAL @ P1 SPERM-P.SERIAL @ P0 SPERM-P.SERIAL ! P1 SPERM-P.SERIAL !",
    "serial zero": "0 P0 SPERM-P.SERIAL !",
    "a serial the counter has not passed": "HD SPERM-H.SERIAL @ P0 SPERM-P.SERIAL !",
    "RIDs out of order":
        "P0 P-TMP SPERM-PERMISSION-SIZE MOVE P1 P0 SPERM-PERMISSION-SIZE MOVE "
        "P-TMP P1 SPERM-PERMISSION-SIZE MOVE",
    "no Practice": "P0 SPERM-P.PRACTICE 32 0 FILL",
    "no store": "P0 SPERM-P.STORE 32 0 FILL",
    "no schedule": "P0 SPERM-P.SCHEDULE 32 0 FILL",
    "revision zero": "0 P0 SPERM-P.REVISION !",
    "no operand digest": "P0 SPERM-P.OPERANDS-DIGEST 32 0 FILL",
    "no trigger digest": "P0 SPERM-P.TRIGGER-DIGEST 32 0 FILL",
    "granted before the epoch": "-1 P0 SPERM-P.GRANTED !",
    "reserved permission bytes": "1 P0 SPERM-PERMISSION-SIZE + 1- C!",
    "a reminder": "SACT-REMINDER P0 SPERM-P.ACTION !",
    "another schema": "2 P0 SPERM-P.SCHEMA !",
    "effects other than observing": "CAP-E-NAVIGATE P0 SPERM-P.EFFECTS !",
    "observing and more": "CAP-E-OBSERVE CAP-E-MUTATE OR P0 SPERM-P.EFFECTS !",
    "no time": "0 P0 SPERM-P.TIME !",
    "no disclosure": "0 P0 SPERM-P.DISCLOSURE !",
    "no output": "0 P0 SPERM-P.OUTPUT !",
    "two for one schedule": "P0 SPERM-P.SCHEDULE P1 SPERM-P.SCHEDULE 32 MOVE",
    "reserved header bytes": "1 HD SPERM-HEADER-SIZE + 1- C!",
}

# Edits to P-ONE a write must refuse: serials whose RIDs are recomputed, so
# only the serial's range is wrong.
ONE_COMMIT_REFUSALS = {
    "a serial the counter has not passed, with its RID":
        "HD SPERM-H.STORE-ID HD SPERM-H.SERIAL @ DUP P0 SPERM-P.SERIAL ! P0 _SPERM-RID!",
    "serial zero, with its RID":
        "HD SPERM-H.STORE-ID 0 DUP P0 SPERM-P.SERIAL ! P0 _SPERM-RID!",
}

# Edits a write accepts, so the refusals above are the edits' own.
COMMIT_ACCEPTS = {
    "granted at an unknown time": "0 P0 SPERM-P.GRANTED !",
    "a later revision": "5 P0 SPERM-P.REVISION !",
    "one schedule in two Practices":
        "P0 SPERM-P.PRACTICE 32 5 FILL P0 SPERM-P.SCHEDULE P1 SPERM-P.SCHEDULE 32 MOVE",
    "a longer time": "600000 P0 SPERM-P.TIME !",
    "observing a document": "CAP-E-OBSERVE P0 SPERM-P.EFFECTS !",
    "one schedule id in two stores":
        "P0 SPERM-P.STORE 32 9 FILL P0 SPERM-P.SCHEDULE P1 SPERM-P.SCHEDULE 32 MOVE",
}


def _commit_rows(forth, edits: dict[str, str], base: str = "P-BASE"
                 ) -> dict[str, list[int]]:
    lines = [
        f"{base} P-SUM P-SUMV ! P-FILE-SUM P-FILE ! "
        f"{edit} PS _SPERM-COMMIT . PS SPERM-STATE@ . GEN . "
        "P-SUM P-SUMV @ = . P-FILE-SUM P-FILE @ = . CR"
        for edit in edits.values()
    ]
    rows = run(forth, lines)
    assert len(rows) == len(edits), rows
    return dict(zip(edits, rows))


def test_a_write_refuses_what_open_would_refuse(forth):
    """A refused write changes nothing on disk and reloads memory."""

    for name, row in _commit_rows(forth, COMMIT_REFUSALS).items():
        assert row == [INVALID, READY, 2, -1, -1], name
    for name, row in _commit_rows(forth, ONE_COMMIT_REFUSALS, "P-ONE").items():
        assert row == [INVALID, READY, 1, -1, -1], name


def test_a_write_accepts_valid_edits(forth):
    for name, row in _commit_rows(forth, COMMIT_ACCEPTS).items():
        assert row == [OK, READY, 3, 0, 0], name


# Damage to the file on disk, the base it was made to, and the reason
# OPEN gives for it.
LOAD_REFUSALS = {
    "a flipped byte": ("P-BASE", "TBUF 200 + DUP C@ 1 XOR SWAP C!", R_CORRUPT),
    "a newer format": ("P-BASE", "2 TBUF 8 + ! T-SEAL", R_FUTURE),
    "format zero": ("P-BASE", "0 TBUF 8 + ! T-SEAL", R_CORRUPT),
    "a count past the permissions": ("P-BASE", "3 TBUF 104 + ! T-SEAL", R_CORRUPT),
    "a count short of the permissions": ("P-BASE", "1 TBUF 104 + ! T-SEAL", R_CORRUPT),
    # 272 times this count wraps to the payload's true size.
    "a count that wraps": ("P-BASE", "1 60 LSHIFT 2 + TBUF 104 + ! T-SEAL", R_CORRUPT),
    "bytes after the permissions":
        ("P-BASE", "8 TBUF 32 + +! TBUF TLEN @ + 8 0 FILL 8 TLEN +! T-SEAL", R_CORRUPT),
    "a truncated file": ("P-BASE", "TLEN @ 8 - TLEN !", R_CORRUPT),
    "no store identity": ("P-BASE", "TBUF 64 + 32 0 FILL T-SEAL", R_CORRUPT),
    "a serial counter at zero": ("P-EMPTY", "0 TBUF 96 + ! T-SEAL", R_CORRUPT),
    "no identity and no permissions": ("P-EMPTY", "TBUF 64 + 32 0 FILL T-SEAL", R_CORRUPT),
}


def test_a_file_open_cannot_trust_blocks_the_store(forth):
    """Nothing loads, nothing is written, and every operation refuses."""

    lines = [
        f"{base} PS SPERM-CLOSE DROP P-GET {patch} P-PUT P-FILE-SUM P-FILE ! "
        "P-INIT DROP PS SPERM-OPEN . PS SPERM-STATE@ . PS SPERM-REASON@ . COUNT. "
        f"PR1 {NOW} GRANT . RID1 PS SPERM-REVOKE . RID1 PS SPERM-FIND . PR1 MATCH. "
        "P-FILE-SUM P-FILE @ = . CR"
        for base, patch, _ in LOAD_REFUSALS.values()
    ]
    rows = run(forth, lines)
    assert len(rows) == len(LOAD_REFUSALS), rows
    for (name, (_, _, reason)), row in zip(LOAD_REFUSALS.items(), rows):
        assert row == [BLOCKED, BLOCKED_STATE, reason, 0, BLOCKED, BLOCKED, 0,
                       UNAVAILABLE, -1], name


def test_disk_faults(forth):
    rows = run(forth, [
        # A sync fault while granting: nothing changes.
        f"P-BASE P-SUM P-SUMV ! 1 T-SYNC-N ! 3 R-ASK PR1 {NOW} GRANT . 0 T-SYNC-N ! "
        "PS SPERM-STATE@ . COUNT. GEN . P-SUM P-SUMV @ = . P-REOPEN . COUNT. CR",
        # A fault at the commit point: nobody can tell which file stands, so
        # the store blocks and holds nothing; a reopen recovers the new one.
        f"P-BASE 5 T-SYNC-N ! 3 R-ASK PR1 {NOW} GRANT . 0 T-SYNC-N ! "
        "PS SPERM-STATE@ . PS SPERM-REASON@ . COUNT. P-REOPEN . COUNT. GEN . CR",
        # A read fault at open blocks; once reads work, the file opens.
        "P-BASE PS SPERM-CLOSE DROP ' T-FAIL-READ VFS-OP-READ T-OP! P-INIT DROP "
        "PS SPERM-OPEN . PS SPERM-STATE@ . PS SPERM-REASON@ . T-OPS-RESET "
        "PS SPERM-CLOSE DROP PS SPERM-OPEN . COUNT. GEN . CR",
    ])
    assert rows == [
        [IO, READY, 2, 2, -1, OK, 2],
        [BLOCKED, BLOCKED_STATE, R_UNCERTAIN, 0, OK, 3, 3],
        [BLOCKED, BLOCKED_STATE, R_IO, OK, 2, 2],
    ]
