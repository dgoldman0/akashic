#!/usr/bin/env python3
"""tui/applets/agent/storage/dispatch-store.f on a RAM filesystem.

The suite covers the store's lifecycle; accepting a run, the same
hand-over again and a conflicting one; the refusals of a request that is
no occurrence's hand-over; transcripts and every end a recorded run may
or may not have; keeping the newest runs whole as the setting says;
reconciling runs left in flight; RIDs and request digests against
hashlib; the file's layout; every rule a file is checked against, by a
write and by OPEN; damage on disk; and disk faults.
"""

from __future__ import annotations

import hashlib
import struct

import pytest

from native_forth import NativeForth
from test_daybook_automation_owner import NOW
from test_daybook_automation_store import RAM_VFS


(OK, INVALID, NOMEM, IO, BLOCKED, STATE, ENTROPY, EXISTING, CONFLICT,
 NOT_FOUND) = range(10)
CLOSED, READY, BLOCKED_STATE = range(3)
R_CORRUPT, R_FUTURE, R_UNCERTAIN, R_IO = 1, 2, 3, 4
ACCEPTED, ENDED = 1, 2
(COMPLETED, FAILED, CANCELLED, EXPIRED, STOPPED, BLOCKED_END, INDETERMINATE,
 NOT_STARTED) = range(1, 9)
(R_NONE, R_REVOKED, R_MODEL_UNAVAILABLE, R_USER, R_TOOL, R_TIME,
 R_PROVIDER_ERROR, R_INTERRUPTED) = 0, 2, 6, 14, 16, 19, 22, 26

PRELUDE = RAM_VFS + rf"""
{NOW} CONSTANT T-NOW
CREATE AS-RAW ADST-SIZE 7 + ALLOT  AS-RAW 7 + -8 AND CONSTANT AS
: A-PATH  ( -- a u ) S" /agent-dispatch.bin" ;
: A-INIT  ( -- status ) AS ADST-SIZE 0 FILL TV @ A-PATH AS ADST-INIT ;
: A-WIPE  ( -- )
    A-PATH T-RM
    AS _ADST.REPL VREPL-STAGE$ T-RM
    AS _ADST.REPL VREPL-BACKUP$ T-RM
    AS _ADST.REPL VREPL-MARKER$ T-RM ;
\ An open store over no file.
: A-FRESH  ( -- )
    AS ADST-VALID? IF AS ADST-CLOSE DROP THEN
    T-OPS-RESET A-INIT DROP A-WIPE AS ADST-OPEN DROP ;
\ A cold start over the same disk.
: A-REOPEN  ( -- status ) AS ADST-CLOSE DROP A-INIT DROP AS ADST-OPEN ;
\ The file's bytes in TBUF and TLEN, and back.
: A-GET  ( -- )
    A-PATH VFS-FF-READ TV @ VFS-OPEN? THROW
    DUP VFS-SIZE TLEN !
    TBUF TLEN @ 2 PICK VFS-READ-EXACT THROW
    VFS-CLOSE ;
: A-PUT  ( -- ) A-PATH T-PUT-AT ;
\ Recomputes both CRCs of the record in TBUF.
: T-SEAL  ( -- )
    TBUF 64 + TBUF 32 + @ CRC32 TBUF 40 + !
    CRC32-BEGIN TBUF 48 CRC32-ADD TBUF 56 + 8 CRC32-ADD CRC32-END TBUF 48 + ! ;
: A-FILE-SUM  ( -- n ) A-GET TBUF TLEN @ CRC32 TLEN @ 32 LSHIFT + ;
\ Everything the store holds in memory, with each blob's bytes in place of
\ its address, which a reload changes.
: A-SUM  ( -- n )
    CRC32-BEGIN
    AS ADST-HEADER ADST-HEADER-SIZE CRC32-ADD
    AS ADST-COUNT@ 0 ?DO
        I AS ADST-NTH
        DUP 224 CRC32-ADD
        DUP ADST-R.REQUEST 8 + 8 CRC32-ADD DUP ADST-REQUEST$ CRC32-ADD
        DUP ADST-R.TRANSCRIPT 8 + 8 CRC32-ADD DUP ADST-TRANSCRIPT$ CRC32-ADD
        256 + 8 CRC32-ADD
    LOOP
    AS _ADST.KEYS @ AS _ADST.KEYS RTAB-COUNT@ 40 * CRC32-ADD
    CRC32-END AS ADST-COUNT@ 32 LSHIFT + ;
VARIABLE A-SUMV  VARIABLE A-FILE
: GEN  ( -- n ) AS ADST-GENERATION@ ;
\ Reads fail until READY. prints the store's state and restores them: a
\ refusal that touched the disk would have reloaded and blocked.
: NO-READS  ( -- ) ['] T-FAIL-READ VFS-OP-READ T-OP! ;
: READY.  ( -- ) AS ADST-STATE@ . T-OPS-RESET ;
: COUNT.  ( -- ) AS ADST-COUNT@ . ;
: B32.  ( a -- ) 32 0 DO DUP I + C@ . LOOP DROP ;

CREATE KEY1 32 ALLOT
CREATE A-TMP ADST-RUN-SIZE ALLOT

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

\ Occurrence N of schedule bytes S in store bytes 3, handed over in RQ in
\ Practice 4 under permission bytes 6 at revision 1.
CREATE RQ-RAW 2063 ALLOT  RQ-RAW 7 + -8 AND CONSTANT RQ
: R-OCC  ( s n -- )
    >R
    S" Read the news" NIP S" daily at 09:00" NIP OPS-U @ SDSP-REQUEST-SIZE
        RQ SDSP-REQUEST-INIT
    SACT-AGENT-RUN RQ SDSP-R.ACTION ! SACT-SCHEMA RQ SDSP-R.SCHEMA !
    RQ SDSP-R.STORE 32 3 FILL RQ SDSP-R.SCHEDULE 32 ROT FILL
    1 RQ SDSP-R.REVISION ! RQ SDSP-R.TRIGGER-DIGEST 32 7 FILL
    S" Read the news" RQ SDSP-TAIL+ S" daily at 09:00" RQ SDSP-TAIL+
    OPS OPS-U @ RQ SDSP-TAIL+
    SACT-AGENT-RUN SACT-SCHEMA OPS OPS-U @ RQ SDSP-R.OPERANDS-DIGEST SACT-DIGEST
    RQ SDSP-R.PRACTICE 32 4 FILL
    SDSP-K-ON-TIME RQ SDSP-R.KIND !
    R> RQ SDSP-R.OCCURRENCE !
    RQ SDSP-R.STORE RQ SDSP-R.SCHEDULE RQ SDSP-R.OCCURRENCE @ RQ SDSP-R.KEY SDSP-KEY
    RQ SDSP-R.PERMISSION 32 6 FILL 1 RQ SDSP-R.PERMISSION-REVISION ! ;
: RQ.  ( -- ) RQ SDSP-REQUEST-U 0 ?DO RQ I + C@ . LOOP ;

\ Accepts RQ at NOW; RN is the run.
VARIABLE RN
: ACC  ( now -- status ) RQ SWAP AS ADST-ACCEPT SWAP RN ! ;
: HELLO  ( -- a u ) S" hello" ;
: PARTIAL  ( -- a u ) S" partial" ;
\ Sets RN's transcript.
: SAY  ( a u -- status ) RN @ AS ADST-TRANSCRIPT! ;
\ Ends RN at NOW with OUTCOME for REASON, keeping REPLY-U.
: END  ( outcome reason reply-u now -- status ) RN @ AS ADST-FINISH ;
: R0  ( -- run ) 0 AS ADST-NTH ;
: R1  ( -- run ) 1 AS ADST-NTH ;
: K0  ( -- key ) AS _ADST.KEYS @ ;
: K1  ( -- key ) AS _ADST.KEYS @ 40 + ;
: HD  ( -- h ) AS ADST-HEADER ;
\ Serial, phase, outcome, reason, Practice, permission, revision, accepted,
\ ended, reply bytes; whether it keeps its request, and whether that is
\ RQ's bytes; then the transcript's length.
: RUN.  ( run -- )
    DUP ADST-R.SERIAL @ . DUP ADST-R.PHASE @ . DUP ADST-R.OUTCOME @ .
    DUP ADST-R.REASON @ . DUP ADST-R.PRACTICE C@ . DUP ADST-R.PERMISSION C@ .
    DUP ADST-R.REVISION @ . DUP ADST-R.ACCEPTED @ . DUP ADST-R.ENDED @ .
    DUP ADST-R.REPLY-U @ . DUP ADST-KEPT? .
    DUP ADST-REQUEST$ RQ DUP SDSP-REQUEST-U COMPARE 0= .
    ADST-TRANSCRIPT$ NIP . ;
\ For each run: whether it keeps its request, and whether it has a
\ transcript.
: KEPT.  ( -- )
    AS ADST-COUNT@ 0 ?DO
        I AS ADST-NTH DUP ADST-KEPT? . ADST-TRANSCRIPT$ NIP 0<> .
    LOOP ;
\ RUN's key record.
: KEY-OF  ( run -- key )
    ADST-R.KEY AS _ADST.KEYS @ AS _ADST.KEYS RTAB-COUNT@ 40 RTAB-RECORD ;
\ Recomputes RUN's RID from its Practice and key.
: RE-RID  ( run -- )
    HD ADST-H.STORE-ID OVER ADST-R.PRACTICE 2 PICK ADST-R.KEY 3 PICK ADST-R.RID
    _ADST-RID! DROP ;
\ Gives RUN the dispatch key whose every byte is N, with the RID that
\ gives; its key record follows, and the keys stay in order.
: REKEY  ( n run -- )
    DUP KEY-OF >R
    TUCK ADST-R.KEY 32 ROT FILL
    DUP RE-RID
    ADST-R.KEY R> 32 MOVE
    K0 32 K1 32 COMPARE 0> IF K0 A-TMP 40 MOVE K1 K0 40 MOVE A-TMP K1 40 MOVE THEN ;
\ R0 trimmed to its row.
: TRIM0  ( -- ) R0 ADST-R.REQUEST BSLOT-FREE R0 ADST-R.TRANSCRIPT BSLOT-FREE ;
\ Occurrence 1 accepted, as generation 1.
: A-ONE  ( -- ) A-FRESH A-OPS 1 1 R-OCC T-NOW ACC DROP ;
\ A setting and no runs, as generation 1.
: A-EMPTY  ( -- ) A-FRESH 2 AS ADST-KEEP! DROP ;
\ Occurrence N of schedule 1 accepted, told "hello", and ended completed.
: RUN-ONE  ( n -- )
    1 SWAP R-OCC T-NOW ACC DROP HELLO SAY DROP
    SACT-O-COMPLETED SACT-R-NONE 5 T-NOW END DROP ;
\ Occurrence 1 ended with its transcript, and occurrence 2 in flight, as
\ generation 3.  RQ is occurrence 2's request, and RN its run.
: A-BASE  ( -- ) A-FRESH A-OPS 1 RUN-ONE 1 2 R-OCC T-NOW ACC DROP ;
"""

SUITE = NativeForth(("tui/applets/agent/storage/dispatch-store.f",),
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
        "A-FRESH AS ADST-STATE@ . GEN . COUNT. A-PATH T-THERE? . "
        "HD ADST-H.SERIAL @ . HD ADST-H.KEEP @ . HD RID-ZERO? . CR",
        "TV @ A-PATH AS 1+ ADST-INIT . TV @ A-PATH 0 ADST-INIT . "
        "TV @ A-PATH AS ADST-INIT . 0 A-PATH AS ADST-INIT . CR",
        "AS ADST-OPEN . AS ADST-CLOSE . AS ADST-STATE@ . "
        "A-OPS 1 1 R-OCC T-NOW ACC . RN @ . RQ SDSP-R.KEY AS ADST-FIND . "
        "HELLO RQ AS ADST-TRANSCRIPT! . 1 0 0 0 RQ AS ADST-FINISH . "
        "T-NOW AS ADST-RECONCILE . . 4 AS ADST-KEEP! . CR",
    ])
    assert rows == [
        [READY, 0, 0, 0, 1, 32, -1],
        [INVALID, INVALID, STATE, STATE],
        [STATE, OK, CLOSED, STATE, 0, 0, STATE, STATE, STATE, 0, STATE],
    ]


def test_accepting_a_run_and_its_replays(forth):
    rows = run(forth, [
        "A-FRESH A-OPS 1 1 R-OCC T-NOW ACC . RN @ RUN. GEN . COUNT. CR",
        # The same hand-over again is the same run, unwritten.
        "T-NOW 1000 + ACC . RN @ R0 = . RN @ ADST-R.ACCEPTED @ . GEN . COUNT. CR",
        # Another request under the key conflicts, and changes nothing.
        "2 RQ SDSP-R.PERMISSION-REVISION ! T-NOW ACC . RN @ R0 = . "
        "R0 ADST-R.REVISION @ . GEN . COUNT. CR",
        "RQ SDSP-R.PRACTICE 32 5 FILL 1 RQ SDSP-R.PERMISSION-REVISION ! "
        "T-NOW ACC . RN @ R0 = . GEN . CR",
        # Another occurrence is another run; with no clock, its time is
        # unknown.
        "1 2 R-OCC -1 ACC . RN @ RUN. GEN . COUNT. CR",
        # Each is found by its key, and a reopen holds the same.
        "RQ SDSP-R.KEY AS ADST-FIND R1 = . 1 1 R-OCC RQ SDSP-R.KEY AS ADST-FIND R0 = . "
        "KEY1 32 9 FILL KEY1 AS ADST-FIND . "
        "A-SUM A-SUMV ! A-REOPEN . A-SUM A-SUMV @ = . GEN . COUNT. CR",
        "AS _ADST.KEYS @ 2 40 RTAB-ASCENDING? . HD ADST-H.SERIAL @ . "
        "K0 32 + @ K1 32 + @ + . CR",
    ])
    assert rows == [
        [OK, 1, ACCEPTED, 0, 0, 4, 6, 1, NOW, 0, 0, -1, -1, 0, 1, 1],
        [EXISTING, -1, NOW, 1, 1],
        [CONFLICT, -1, 1, 1, 1],
        [CONFLICT, -1, 1],
        [OK, 2, ACCEPTED, 0, 0, 4, 6, 1, 0, 0, 0, -1, -1, 0, 2, 2],
        [-1, -1, 0, OK, -1, 2, 2],
        [-1, 3, 3],
    ]


def test_rids_and_digests_against_hashlib(forth):
    rows = run(forth, [
        "A-ONE HD B32. CR",
        "R0 ADST-R.RID B32. CR",
        "R0 ADST-R.KEY B32. CR",
        "R0 ADST-R.DIGEST B32. CR",
        "RQ. CR",
        "RQ R0 ADST-R.DIGEST ADST-DIGEST R0 ADST-R.DIGEST B32. CR",
    ])
    store, rid, key, digest, request, again = (bytes(b & 0xFF for b in row) for row in rows)
    assert any(store)
    assert key == hashlib.sha3_256(
        b"akashic.daybook.dispatch.v1" + bytes([3]) * 32 + bytes([1]) * 32
        + struct.pack("<Q", 1)).digest()
    assert rid == hashlib.sha3_256(
        b"akashic.agent.dispatch-run.v1" + store + bytes([4]) * 32 + key).digest()
    assert digest == hashlib.sha3_256(
        b"akashic.agent.dispatch-request.v1" + request).digest()
    assert again == digest


ACCEPT_REFUSALS = {
    "no occurrence kind": "0 RQ SDSP-R.KIND !",
    "occurrence zero": "0 RQ SDSP-R.OCCURRENCE !",
    "a key that is not the occurrence's": "RQ SDSP-R.KEY 32 9 FILL",
    "no Practice": "RQ SDSP-R.PRACTICE 32 0 FILL",
    "no permission": "RQ SDSP-R.PERMISSION 32 0 FILL",
    "permission revision zero": "0 RQ SDSP-R.PERMISSION-REVISION !",
    "a size that is not its own": "8 RQ SDSP-R.SIZE +!",
    "operands that are not the digest's": "1 RQ SDSP-R.OPERANDS-DIGEST +!",
    "a reminder": "SACT-REMINDER RQ SDSP-R.ACTION !",
}


def test_accept_refusals(forth):
    """Each refusal comes before any edit: over a store holding one run,
    with reads failing, the store stays ready."""

    lines = [f"A-ONE 1 2 R-OCC {edit} NO-READS T-NOW ACC . READY. RN @ . GEN . COUNT. CR"
             for edit in ACCEPT_REFUSALS.values()]
    rows = run(forth, lines)
    assert len(rows) == len(ACCEPT_REFUSALS), rows
    for name, row in zip(ACCEPT_REFUSALS, rows):
        assert row == [INVALID, READY, 0, 1, 1], name


def test_a_transcript_and_an_end(forth):
    rows = run(forth, [
        # The transcript is the run's own copy, replaced whole, and written
        # with the end.
        "A-ONE PARTIAL SAY . HELLO SAY . GEN . RN @ ADST-TRANSCRIPT$ HELLO COMPARE . "
        "RN @ ADST-TRANSCRIPT$ DROP HELLO DROP <> . CR",
        "SACT-O-COMPLETED SACT-R-NONE 1234 T-NOW 5000 + END . RN @ RUN. GEN . CR",
        # An ended run takes no transcript and no second end.
        "PARTIAL SAY . SACT-O-FAILED SACT-R-PROVIDER-ERROR 0 T-NOW END . GEN . "
        "RN @ ADST-TRANSCRIPT$ HELLO COMPARE . CR",
        "A-REOPEN . R0 ADST-TRANSCRIPT$ HELLO COMPARE . R0 RUN. CR",
        # With no clock, the end's time is unknown.
        "A-ONE SACT-O-CANCELLED SACT-R-USER 0 -1 END . RN @ ADST-R.ENDED @ . "
        "RN @ ADST-TRANSCRIPT$ NIP . CR",
    ])
    assert rows == [
        [OK, OK, 1, 0, -1],
        [OK, 1, ENDED, COMPLETED, R_NONE, 4, 6, 1, NOW, NOW + 5000, 1234, -1, -1, 5, 2],
        [STATE, STATE, 2, 0],
        [OK, 0, 1, ENDED, COMPLETED, R_NONE, 4, 6, 1, NOW, NOW + 5000, 1234, -1, -1, 5],
        [OK, 0, 0],
    ]


END_REFUSALS = {
    "not started": "SACT-O-NOT-STARTED 13 0 T-NOW RN @",
    "a pair the catalog does not allow": "SACT-O-COMPLETED SACT-R-TOOL 0 T-NOW RN @",
    "no outcome": "0 SACT-R-NONE 0 T-NOW RN @",
    "an unknown reason": "SACT-O-FAILED 30 0 T-NOW RN @",
    "a negative reply": "SACT-O-COMPLETED SACT-R-NONE -1 T-NOW RN @",
    "a run not the store's": "SACT-O-COMPLETED SACT-R-NONE 0 T-NOW RQ",
    "a run between runs": "SACT-O-COMPLETED SACT-R-NONE 0 T-NOW RN @ 8 +",
    "a run past the runs": "SACT-O-COMPLETED SACT-R-NONE 0 T-NOW RN @ ADST-RUN-SIZE +",
    "a run one place before the runs":
        "SACT-O-COMPLETED SACT-R-NONE 0 T-NOW RN @ ADST-RUN-SIZE -",
    "no run": "SACT-O-COMPLETED SACT-R-NONE 0 T-NOW 0",
}


def test_end_and_transcript_refusals(forth):
    lines = [f"A-ONE NO-READS {args} AS ADST-FINISH . READY. R0 ADST-R.PHASE @ . GEN . CR"
             for args in END_REFUSALS.values()]
    lines.append("A-ONE NO-READS HELLO RQ AS ADST-TRANSCRIPT! . "
                 "HELLO DROP -1 RN @ AS ADST-TRANSCRIPT! . "
                 "HELLO RN @ 8 + AS ADST-TRANSCRIPT! . "
                 "HELLO RN @ ADST-RUN-SIZE - AS ADST-TRANSCRIPT! . READY. "
                 "RN @ ADST-TRANSCRIPT$ NIP . CR")
    rows = run(forth, lines)
    assert len(rows) == len(END_REFUSALS) + 1, rows
    for name, row in zip(END_REFUSALS, rows):
        assert row == [INVALID, READY, ACCEPTED, 1], name
    assert rows[-1] == [INVALID, INVALID, INVALID, INVALID, READY, 0]


# Every outcome a recorded run may end with, with a reason for it.
ENDS = [
    (COMPLETED, R_NONE), (FAILED, R_PROVIDER_ERROR), (CANCELLED, R_USER),
    (CANCELLED, R_REVOKED), (EXPIRED, R_TIME), (STOPPED, R_TOOL),
    (BLOCKED_END, R_MODEL_UNAVAILABLE), (INDETERMINATE, R_INTERRUPTED),
]


def test_every_end_a_recorded_run_may_have(forth):
    lines = [f"A-ONE {outcome} {reason} 0 T-NOW END . RN @ ADST-R.OUTCOME @ . "
             "RN @ ADST-R.REASON @ . GEN . A-REOPEN . R0 ADST-R.PHASE @ . CR"
             for outcome, reason in ENDS]
    rows = run(forth, lines)
    assert rows == [[OK, outcome, reason, 2, OK, ENDED] for outcome, reason in ENDS]


def test_keeping_the_newest_runs_whole(forth):
    rows = run(forth, [
        # A fresh store's first write may be its setting.
        "A-FRESH 2 AS ADST-KEEP! . GEN . HD ADST-H.KEEP @ . HD RID-ZERO? . "
        "A-REOPEN . HD ADST-H.KEEP @ . COUNT. CR",
        # The same setting writes nothing, and one below zero is refused.
        "2 AS ADST-KEEP! . GEN . -1 AS ADST-KEEP! . HD ADST-H.KEEP @ . GEN . CR",
        # Past the setting, the oldest ended runs keep only their row.
        "A-OPS 1 RUN-ONE 2 RUN-ONE 3 RUN-ONE KEPT. GEN . 4 RUN-ONE KEPT. GEN . CR",
        "1 1 R-OCC R0 RUN. CR",
        # A run in flight is never trimmed, even with the setting at zero.
        "1 5 R-OCC T-NOW ACC . 0 AS ADST-KEEP! . KEPT. GEN . CR",
        # Raising it brings nothing back.  A trimmed run is still known by
        # its key, and its digest still tells the same hand-over from
        # another.
        "32 AS ADST-KEEP! . KEPT. 1 1 R-OCC T-NOW ACC . RN @ R0 = . "
        "2 RQ SDSP-R.PERMISSION-REVISION ! T-NOW ACC . CR",
        "A-SUM A-SUMV ! A-REOPEN . A-SUM A-SUMV @ = . KEPT. HD ADST-H.KEEP @ . CR",
        # Only ended runs count against the setting, and only they are
        # trimmed, even when a run in flight is older.
        "A-BASE 1 AS ADST-KEEP! . KEPT. CR",
        "A-FRESH A-OPS 1 1 R-OCC T-NOW ACC DROP 2 RUN-ONE 0 AS ADST-KEEP! . KEPT. CR",
        # A setting below zero is refused before anything is written: with
        # reads failing, a write's reload would have blocked the store.
        "NO-READS -1 AS ADST-KEEP! . READY. HD ADST-H.KEEP @ . CR",
    ])
    assert rows == [
        [OK, 1, 2, 0, OK, 2, 0],
        [OK, 1, INVALID, 2, 1],
        [0, 0, -1, -1, -1, -1, 7, 0, 0, 0, 0, -1, -1, -1, -1, 9],
        [1, ENDED, COMPLETED, R_NONE, 4, 6, 1, NOW, NOW, 5, 0, 0, 0],
        [OK, OK, 0, 0, 0, 0, 0, 0, 0, 0, -1, 0, 11],
        [OK, 0, 0, 0, 0, 0, 0, 0, 0, -1, 0, EXISTING, -1, CONFLICT],
        [OK, -1, 0, 0, 0, 0, 0, 0, 0, 0, -1, 0, 32],
        [OK, -1, -1, -1, 0],
        [OK, -1, 0, 0, 0],
        [INVALID, READY, 0],
    ]


def test_finding_runs_across_a_gap_in_the_serials(forth):
    """Serials only ascend: a key finds its run by search, not by place."""

    rows = run(forth, [
        "A-BASE 5 HD ADST-H.SERIAL ! 4 R1 ADST-R.SERIAL ! 4 R1 KEY-OF 32 + ! "
        "AS _ADST-COMMIT . A-REOPEN . RQ SDSP-R.KEY AS ADST-FIND R1 = . "
        "R1 ADST-R.SERIAL @ . 1 1 R-OCC RQ SDSP-R.KEY AS ADST-FIND R0 = . "
        "1 3 R-OCC T-NOW ACC . RN @ ADST-R.SERIAL @ . CR",
    ])
    assert rows == [[OK, OK, -1, 4, -1, OK, 5]]


def test_reconciling_runs_left_in_flight(forth):
    rows = run(forth, [
        # Occurrence 2's partial transcript is written with occurrence 3's
        # acceptance.
        "A-FRESH A-OPS 1 RUN-ONE 1 2 R-OCC T-NOW ACC DROP PARTIAL SAY DROP "
        "1 3 R-OCC T-NOW ACC DROP GEN . CR",
        "A-REOPEN . T-NOW 9000 + AS ADST-RECONCILE . . GEN . R1 RUN. "
        "2 AS ADST-NTH RUN. R1 ADST-TRANSCRIPT$ PARTIAL COMPARE . R0 RUN. CR",
        # Nothing in flight: nothing to write.
        "T-NOW AS ADST-RECONCILE . . GEN . A-REOPEN . R1 ADST-R.PHASE @ . CR",
        # With no clock, the end's time is unknown.
        "A-ONE -1 AS ADST-RECONCILE . . R0 ADST-R.ENDED @ . R0 ADST-R.OUTCOME @ . CR",
    ])
    assert rows == [
        [4],
        [OK, OK, 2, 5,
         2, ENDED, INDETERMINATE, R_INTERRUPTED, 4, 6, 1, NOW, NOW + 9000, 0, -1, 0, 7,
         3, ENDED, INDETERMINATE, R_INTERRUPTED, 4, 6, 1, NOW, NOW + 9000, 0, -1, -1, 0,
         0,
         1, ENDED, COMPLETED, R_NONE, 4, 6, 1, NOW, NOW, 5, -1, 0, 5],
        [OK, 0, 5, OK, ENDED],
        [OK, 1, 0, INDETERMINATE],
    ]


def test_the_files_layout(forth):
    """A header, the runs in serial order, their keys in key order, then
    each kept run's request and each one's transcript, padded to a cell."""

    rows = run(forth, [
        "A-BASE A-GET RQ SDSP-REQUEST-U . TBUF 32 + @ . TBUF 112 + @ . TBUF 120 + @ . "
        "TBUF 128 + @ . TBUF 392 + @ . CR",
        # Each run's request and transcript slots: offset and length.
        "TBUF 352 + @ . TBUF 360 + @ . TBUF 368 + @ . TBUF 376 + @ . "
        "TBUF 616 + @ . TBUF 624 + @ . TBUF 632 + @ . TBUF 640 + @ . CR",
        "TBUF 656 + 32 TBUF 696 + 32 COMPARE . TBUF 688 + @ TBUF 728 + @ + . CR",
        # The blob holds the requests and the transcript.
        "TBUF 736 + TBUF 352 + @ + TBUF 360 + @ R0 ADST-REQUEST$ COMPARE . "
        "TBUF 736 + TBUF 616 + @ + TBUF 624 + @ RQ DUP SDSP-REQUEST-U COMPARE . "
        "TBUF 736 + TBUF 368 + @ + 5 HELLO COMPARE . CR",
    ])
    request_u = rows[0][0]
    padded = (request_u + 7) & ~7
    blob = 2 * padded + 8
    assert rows[0] == [request_u, 64 + 2 * 304 + blob, 2, blob, 1, 2]
    assert rows[1] == [0, request_u, 2 * padded, 5, padded, request_u, 0, 0]
    assert rows[2] == [-1, 3]
    assert rows[3] == [0, 0, 0]


# Edits a write must refuse, each made to A-BASE: R0 is occurrence 1's
# ended run, R1 occurrence 2's in flight, and RQ occurrence 2's request.
# Each edit keeps the rest of the file consistent, so only the rule it
# names refuses it: the run's RID and key record follow its key and
# Practice, and a trimmed run has no request to check against.
COMMIT_REFUSALS = {
    "a RID its key does not give": "R0 ADST-R.RID DUP C@ 1 XOR SWAP C!",
    "a RID for another Practice": "R0 ADST-R.PRACTICE 32 5 FILL",
    "serial zero, with its key": "0 R0 ADST-R.SERIAL ! 0 R0 KEY-OF 32 + !",
    "a serial the counter has not passed, with its key":
        "HD ADST-H.SERIAL @ DUP R1 ADST-R.SERIAL ! R1 KEY-OF 32 + !",
    "serials out of order, with their keys":
        "R0 ADST-R.SERIAL @ R1 ADST-R.SERIAL @ R0 ADST-R.SERIAL ! R1 ADST-R.SERIAL ! "
        "R0 ADST-R.SERIAL @ R0 KEY-OF 32 + ! R1 ADST-R.SERIAL @ R1 KEY-OF 32 + !",
    "phase zero": "0 R0 ADST-R.PHASE !",
    "phase three": "3 R0 ADST-R.PHASE !",
    "no key, trimmed": "TRIM0 0 R0 REKEY",
    "no digest, trimmed": "TRIM0 R0 ADST-R.DIGEST 32 0 FILL",
    "no Practice, trimmed": "TRIM0 R0 ADST-R.PRACTICE 32 0 FILL R0 RE-RID",
    "no permission, trimmed": "TRIM0 R0 ADST-R.PERMISSION 32 0 FILL",
    "revision zero, trimmed": "TRIM0 0 R0 ADST-R.REVISION !",
    "a digest that is not its request's": "1 R0 ADST-R.DIGEST +!",
    "a key that is not its request's": "9 R1 REKEY",
    "a Practice that is not its request's": "R1 ADST-R.PRACTICE 32 5 FILL R1 RE-RID",
    "a permission that is not its request's": "R0 ADST-R.PERMISSION 32 7 FILL",
    "a revision that is not its request's": "2 R0 ADST-R.REVISION !",
    "accepted before the epoch": "-1 R0 ADST-R.ACCEPTED !",
    "ended before the epoch": "-1 R0 ADST-R.ENDED !",
    "a reply below zero": "-1 R0 ADST-R.REPLY-U !",
    "reserved run bytes": "1 R0 ADST-RUN-SIZE + 1- C!",
    "an end not started":
        "SACT-O-NOT-STARTED R0 ADST-R.OUTCOME ! SACT-R-RESTART R0 ADST-R.REASON !",
    "an end the catalog does not pair": "SACT-R-TOOL R0 ADST-R.REASON !",
    "in flight with an outcome": "SACT-O-COMPLETED R1 ADST-R.OUTCOME !",
    "in flight with a reason": "SACT-R-TOOL R1 ADST-R.REASON !",
    "in flight with an end": "5 R1 ADST-R.ENDED !",
    "in flight with a reply": "5 R1 ADST-R.REPLY-U !",
    "in flight without its request": "R1 ADST-R.REQUEST BSLOT-FREE",
    "ended with a transcript and no request": "R0 ADST-R.REQUEST BSLOT-FREE",
    "a request too short for its header": "RQ 16 R1 ADST-R.REQUEST BSLOT! DROP",
    "a request one byte short": "R1 ADST-REQUEST$ 1- R1 ADST-R.REQUEST BSLOT! DROP",
    "another occurrence's request":
        "1 3 R-OCC RQ DUP SDSP-REQUEST-U R1 ADST-R.REQUEST BSLOT! DROP",
    "a request that is no hand-over, with its digest":
        "R1 ADST-REQUEST$ DROP DUP SDSP-R.KIND 0 SWAP ! R1 ADST-R.DIGEST ADST-DIGEST",
    "keys out of order": "K0 A-TMP 40 MOVE K1 K0 40 MOVE A-TMP K1 40 MOVE",
    "two keys for one run": "K1 32 + @ K0 32 + !",
    "a key for no run": "99 K0 32 + !",
    "a key naming its run by another serial": "0 R0 KEY-OF 32 + !",
    "more kept than the setting": "0 HD ADST-H.KEEP !",
    "a setting below zero": "-1 HD ADST-H.KEEP !",
    "no identity": "HD 32 0 FILL",
    "serial counter zero": "0 HD ADST-H.SERIAL !",
}

# Edits a write accepts, so the refusals above are the edits' own.
COMMIT_ACCEPTS = {
    "accepted at an unknown time": "0 R0 ADST-R.ACCEPTED !",
    "ended at an unknown time": "0 R0 ADST-R.ENDED !",
    "ended without a transcript": "R0 ADST-R.TRANSCRIPT BSLOT-FREE",
    "ended and trimmed": "R0 ADST-R.REQUEST BSLOT-FREE R0 ADST-R.TRANSCRIPT BSLOT-FREE",
    "in flight with a transcript": "RQ 5 R1 ADST-R.TRANSCRIPT BSLOT! DROP",
    "a blocked end":
        "SACT-O-BLOCKED R0 ADST-R.OUTCOME ! SACT-R-MODEL-UNAVAILABLE R0 ADST-R.REASON !",
    "a setting at exactly the kept": "1 HD ADST-H.KEEP !",
    "a later serial counter": "9 HD ADST-H.SERIAL !",
    "a larger reply": "99999 R0 ADST-R.REPLY-U !",
    "a gap in the serials, with its key":
        "5 HD ADST-H.SERIAL ! 4 R1 ADST-R.SERIAL ! 4 R1 KEY-OF 32 + !",
    "another key, trimmed": "TRIM0 9 R0 REKEY",
    "another Practice, trimmed": "TRIM0 R0 ADST-R.PRACTICE 32 5 FILL R0 RE-RID",
    "another permission and revision, trimmed":
        "TRIM0 R0 ADST-R.PERMISSION 32 7 FILL 2 R0 ADST-R.REVISION !",
}


def _commit_rows(forth, edits: dict[str, str]) -> dict[str, list[int]]:
    rows = []
    names = list(edits)
    # A-BASE writes three times per line; a few lines per program keep
    # each well inside its step budget.
    for start in range(0, len(names), 8):
        chunk = names[start:start + 8]
        lines = [
            "A-BASE A-SUM A-SUMV ! A-FILE-SUM A-FILE ! "
            f"{edits[name]} AS _ADST-COMMIT . AS ADST-STATE@ . GEN . "
            "A-SUM A-SUMV @ = . A-FILE-SUM A-FILE @ = . CR"
            for name in chunk
        ]
        rows.extend(run(forth, lines))
    assert len(rows) == len(edits), rows
    return dict(zip(names, rows))


def test_a_write_refuses_what_open_would_refuse(forth):
    """A refused write changes nothing on disk and reloads memory."""

    for name, row in _commit_rows(forth, COMMIT_REFUSALS).items():
        assert row == [INVALID, READY, 3, -1, -1], name


def test_a_write_accepts_valid_edits(forth):
    for name, row in _commit_rows(forth, COMMIT_ACCEPTS).items():
        assert row == [OK, READY, 4, 0, 0], name


# Damage to a file on disk, the base it was made to, and the reason OPEN
# gives for it.  The payload starts at byte 64 with the header: the
# identity, then the serial counter at 96, the setting at 104, the count
# at 112 and the blob's size at 120.  A-BASE's two 264-byte runs follow
# from byte 128, their keys from byte 656, and the blob from byte 736.
LOAD_REFUSALS = {
    "a flipped byte": ("A-BASE", "TBUF 200 + DUP C@ 1 XOR SWAP C!", R_CORRUPT),
    "a newer format": ("A-BASE", "2 TBUF 8 + ! T-SEAL", R_FUTURE),
    "format zero": ("A-BASE", "0 TBUF 8 + ! T-SEAL", R_CORRUPT),
    "a count past the runs": ("A-BASE", "3 TBUF 112 + ! T-SEAL", R_CORRUPT),
    "a count short of the runs": ("A-BASE", "1 TBUF 112 + ! T-SEAL", R_CORRUPT),
    "a count that wraps": ("A-BASE", "1 60 LSHIFT 2 + TBUF 112 + ! T-SEAL", R_CORRUPT),
    "a blob past the payload": ("A-BASE", "8 TBUF 120 + +! T-SEAL", R_CORRUPT),
    # Without its own check, this one's count of -1 would describe the
    # payload exactly.
    "a blob past the payload, and a count below zero":
        ("A-BASE", "TBUF 32 + @ 64 - 304 + TBUF 120 + ! -1 TBUF 112 + ! T-SEAL", R_CORRUPT),
    "a blob below zero": ("A-BASE", "-8 TBUF 120 + ! T-SEAL", R_CORRUPT),
    "a blob that swallows a run":
        ("A-BASE", "304 TBUF 120 + +! -1 TBUF 112 + +! T-SEAL", R_CORRUPT),
    "bytes after the blob":
        ("A-BASE", "8 TBUF 32 + +! TBUF TLEN @ + 8 0 FILL 8 TLEN +! T-SEAL", R_CORRUPT),
    "blob bytes no part names":
        ("A-BASE",
         "8 TBUF 32 + +! TBUF TLEN @ + 8 0 FILL 8 TLEN +! 8 TBUF 120 + +! T-SEAL",
         R_CORRUPT),
    "a request byte flipped":
        ("A-BASE", "TBUF 1032 + DUP C@ 1 XOR SWAP C! T-SEAL", R_CORRUPT),
    "a truncated file": ("A-BASE", "TLEN @ 8 - TLEN !", R_CORRUPT),
    "no store identity": ("A-BASE", "TBUF 64 + 32 0 FILL T-SEAL", R_CORRUPT),
    "no identity and no runs": ("A-EMPTY", "TBUF 64 + 32 0 FILL T-SEAL", R_CORRUPT),
    "a serial counter at zero and no runs": ("A-EMPTY", "0 TBUF 96 + ! T-SEAL", R_CORRUPT),
    "a setting below zero and no runs": ("A-EMPTY", "-1 TBUF 104 + ! T-SEAL", R_CORRUPT),
}


def test_a_file_open_cannot_trust_blocks_the_store(forth):
    """Nothing loads, nothing is written, and every operation refuses."""

    lines = [
        f"{base} AS ADST-CLOSE DROP A-GET {patch} A-PUT A-FILE-SUM A-FILE ! "
        "A-INIT DROP AS ADST-OPEN . AS ADST-STATE@ . AS ADST-REASON@ . COUNT. "
        "A-OPS 1 1 R-OCC T-NOW ACC . RQ SDSP-R.KEY AS ADST-FIND . "
        "HELLO RQ AS ADST-TRANSCRIPT! . "
        "1 0 0 0 RQ AS ADST-FINISH . T-NOW AS ADST-RECONCILE . . 4 AS ADST-KEEP! . "
        "A-FILE-SUM A-FILE @ = . CR"
        for base, patch, _ in LOAD_REFUSALS.values()
    ]
    rows = run(forth, lines)
    assert len(rows) == len(LOAD_REFUSALS), rows
    for (name, (_, _, reason)), row in zip(LOAD_REFUSALS.items(), rows):
        assert row == [BLOCKED, BLOCKED_STATE, reason, 0, BLOCKED, 0, BLOCKED, BLOCKED,
                       BLOCKED, 0, BLOCKED, -1], name


def test_a_transcript_byte_is_the_runs_own(forth):
    """Transcripts are opaque: a changed byte in one is no damage."""

    rows = run(forth, [
        "A-BASE AS ADST-CLOSE DROP A-GET TBUF 736 + TBUF 368 + @ + DUP C@ 1 XOR SWAP C! "
        "T-SEAL A-PUT A-INIT DROP AS ADST-OPEN . R0 ADST-TRANSCRIPT$ HELLO COMPARE 0= . CR",
    ])
    assert rows == [[OK, 0]]


def test_disk_faults(forth):
    rows = run(forth, [
        # A sync fault while accepting: nothing changes.
        "A-BASE A-SUM A-SUMV ! 1 T-SYNC-N ! 1 3 R-OCC T-NOW ACC . RN @ . 0 T-SYNC-N ! "
        "AS ADST-STATE@ . COUNT. GEN . A-SUM A-SUMV @ = . A-REOPEN . COUNT. CR",
        # A sync fault while finishing reloads the run in flight, without the
        # transcript it was given: whoever retries gives it again.
        "A-BASE PARTIAL SAY DROP 1 T-SYNC-N ! SACT-O-COMPLETED SACT-R-NONE 7 T-NOW END . "
        "0 T-SYNC-N ! R1 ADST-R.PHASE @ . R1 ADST-TRANSCRIPT$ NIP . GEN . CR",
        # A fault at the commit point: nobody can tell which file stands, so
        # the store blocks and holds nothing; a reopen recovers the new one.
        "A-BASE 5 T-SYNC-N ! 1 3 R-OCC T-NOW ACC . 0 T-SYNC-N ! "
        "AS ADST-STATE@ . AS ADST-REASON@ . COUNT. A-REOPEN . COUNT. GEN . CR",
        # A read fault at open blocks; once reads work, the file opens.
        "A-BASE AS ADST-CLOSE DROP ' T-FAIL-READ VFS-OP-READ T-OP! A-INIT DROP "
        "AS ADST-OPEN . AS ADST-STATE@ . AS ADST-REASON@ . T-OPS-RESET "
        "AS ADST-CLOSE DROP AS ADST-OPEN . COUNT. GEN . CR",
    ])
    assert rows == [
        [IO, 0, READY, 2, 3, -1, OK, 2],
        [IO, ACCEPTED, 0, 3],
        [BLOCKED, BLOCKED_STATE, R_UNCERTAIN, 0, OK, 3, 4],
        [BLOCKED, BLOCKED_STATE, R_IO, OK, 2, 3],
    ]
