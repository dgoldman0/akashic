#!/usr/bin/env python3
"""tui/applets/desk/schedule-broker.f with a fake handler.

The suite covers the broker's lifecycle; approvals, their answers, their
order and the one an approval asked again withdraws; how requests stand;
every refusal before a run reaches the handler; the authority a started
run gets, and its IDs against hashlib; each answer the handler can give;
runs that wait, start in order once the handler is idle, and are checked
again as they start; cancelling, revoking and closing; and whether a run
is in flight.

The fake handler retains each run it is given, as a gateway would, so a
run the broker keeps is seen to be released by the broker and a run the
handler took is seen to be left alone.
"""

from __future__ import annotations

import hashlib
import struct

import pytest

from native_forth import NativeForth
from test_daybook_automation_owner import NOW
from test_daybook_automation_store import RAM_VFS


# Dispatch statuses and standings.
(S_OK, S_INVALID, S_UNAVAILABLE, S_STARTED, S_WAITING, S_ENDED, S_RUNNING,
 S_UNKNOWN, S_PENDING, S_ALLOWED, S_REFUSED, S_GONE, S_SMALL) = range(13)
APPROVED, NONE, WITHDRAWN, CHANGED, PRACTICE, UNAVAILABLE = range(1, 7)
# Permission store statuses and states.
OK, INVALID, NOMEM, IO, BLOCKED, STATE, ENTROPY, NOT_FOUND = range(8)
READY = 1
# Outcomes and reasons.
COMPLETED, FAILED, CANCELLED, EXPIRED, STOPPED, O_BLOCKED, INDETERMINATE = range(1, 8)
(R_NOT_APPROVED, R_REVOKED, R_CHANGED, R_PRACTICE, R_AGENT_UNAVAILABLE,
 R_MODEL_UNAVAILABLE) = range(1, 7)
R_TOO_LARGE, R_CAPACITY, R_USER, R_SHUTDOWN, R_PROVIDER_START, R_INTERNAL = 7, 8, 14, 15, 23, 25

PRELUDE = RAM_VFS + rf"""
{NOW} CONSTANT T-NOW

\ Desk's Practice, bytes 4, and its root Context at epoch 777; HD2 is
\ another Practice's head.
CREATE HD-RAW PHEAD-SIZE 7 + ALLOT  HD-RAW 7 + -8 AND CONSTANT HD
CREATE HD2-RAW PHEAD-SIZE 7 + ALLOT  HD2-RAW 7 + -8 AND CONSTANT HD2
VARIABLE ROOT
: HD-INIT  ( -- )
    HD PHEAD-INIT HD PHEAD.ID 32 4 FILL HD PHEAD.CURRENT-ROOT 32 9 FILL
    HD2 PHEAD-INIT HD2 PHEAD.ID 32 5 FILL HD2 PHEAD.CURRENT-ROOT 32 9 FILL
    ROOT @ 0= IF 777 CTX-NEW THROW ROOT ! THEN
    HD ROOT @ CTX.PRACTICE ! ;

CREATE B-RAW SBRK-SIZE 7 + ALLOT  B-RAW 7 + -8 AND CONSTANT B
CREATE PS-RAW SPERM-SIZE 7 + ALLOT  PS-RAW 7 + -8 AND CONSTANT PS
: P-PATH  ( -- a u ) S" /schedule-perms.bin" ;
\ No permission file, and nothing left of a replacement.
: P-WIPE  ( -- )
    PS SPERM-SIZE 0 FILL TV @ P-PATH PS SPERM-INIT DROP
    P-PATH T-RM
    PS _SPERM.REPL VREPL-STAGE$ T-RM
    PS _SPERM.REPL VREPL-BACKUP$ T-RM
    PS _SPERM.REPL VREPL-MARKER$ T-RM
    PS SPERM-SIZE 0 FILL ;
: BS  ( -- store ) B SBRK-STORE ;
: BC  ( -- client ) B SBRK-CLIENT ;
\ How many runs the broker remembers.
: RUNS  ( -- n ) 0 B _SBRK.RUNS @ BEGIN ?DUP WHILE SWAP 1+ SWAP @ REPEAT ;

\ The fake handler.  Each word records its context; start records the
\ run it was given and retains it, and a copy of the request.
CREATE FH-RAW SBRK-HANDLER-SIZE 7 + ALLOT  FH-RAW 7 + -8 AND CONSTANT FH
VARIABLE FH-START-ANS  VARIABLE FH-STATUS-ANS  VARIABLE FH-CANCEL-ANS
VARIABLE FH-IDLE  VARIABLE FH-OUTCOME  VARIABLE FH-WHY  VARIABLE FH-NAMES
VARIABLE FH-STARTS  VARIABLE FH-STATUSES  VARIABLE FH-CANCELS
VARIABLE FH-RUN  VARIABLE FH-REASON  VARIABLE FH-CTX
CREATE FH-KEY 32 ALLOT
CREATE FH-RID 32 ALLOT
CREATE FH-REQ-RAW 4103 ALLOT  FH-REQ-RAW 7 + -8 AND CONSTANT FH-REQ

\ Lets go of the run the fake was given: its own reference, and the
\ owner's too when it took the run.
: FH-DONE  ( -- )
    FH-RUN @ ?DUP IF
        DUP AMRUN.FREE-PENDING @ 0= IF DUP AMRUN-FREE THEN AMRUN-RELEASE
    THEN
    0 FH-RUN ! ;
\ The run for STARTED and RUNNING, and how it ended for ENDED.  With
\ FH-NAMES set, any answer names the run and a summary's length.
: FH-FILL  ( response status -- status )
    DUP SDSP-S-STARTED = OVER SDSP-S-RUNNING = OR FH-NAMES @ OR IF
        OVER SDSP-P.RUN FH-RID SWAP RID-COPY
    THEN
    FH-NAMES @ IF 5 2 PICK SDSP-P.SUMMARY-U ! THEN
    DUP SDSP-S-ENDED = IF
        FH-OUTCOME @ 2 PICK SDSP-P.OUTCOME ! FH-WHY @ 2 PICK SDSP-P.REASON !
    THEN
    NIP ;
: FH-START  ( request run response context -- status )
    FH-CTX ! >R FH-DONE DUP FH-RUN ! AMRUN-RETAIN DROP
    DUP SDSP-R.KEY FH-KEY 32 MOVE
    DUP SDSP-REQUEST-U FH-REQ SWAP MOVE
    1 FH-STARTS +!
    R> FH-START-ANS @ DUP SDSP-S-STARTED = IF 0 FH-IDLE ! THEN FH-FILL ;
: FH-STATUS  ( key response context -- status )
    FH-CTX ! SWAP FH-KEY 32 MOVE 1 FH-STATUSES +! FH-STATUS-ANS @ FH-FILL ;
: FH-CANCEL  ( key reason context -- status )
    FH-CTX ! FH-REASON ! FH-KEY 32 MOVE 1 FH-CANCELS +! FH-CANCEL-ANS @ ;
: FH-MODELS  ( buffer capacity context -- bytes status )
    FH-CTX ! 2DROP 77 SDSP-S-OK ;
: FH-IDLE?  ( context -- flag ) FH-CTX ! FH-IDLE @ ;
VARIABLE FH-VETTED
: FH-VET  ( request context -- reason ) FH-CTX ! FH-VETTED ! SACT-R-TOO-LARGE ;
: FH-RESET  ( -- )
    FH-DONE
    SDSP-S-STARTED FH-START-ANS ! SDSP-S-RUNNING FH-STATUS-ANS !
    SDSP-S-OK FH-CANCEL-ANS ! -1 FH-IDLE ! 0 FH-NAMES !
    SACT-O-BLOCKED FH-OUTCOME ! SACT-R-MODEL-UNAVAILABLE FH-WHY !
    0 FH-STARTS ! 0 FH-STATUSES ! 0 FH-CANCELS ! 0 FH-REASON ! 0 FH-CTX !
    FH-KEY 32 0 FILL FH-RID 32 171 FILL ;
: FH-ON  ( -- )
    4242 FH SBRK-HANDLER-INIT
    ['] FH-START FH SBRK-H.START-XT !
    ['] FH-STATUS FH SBRK-H.STATUS-XT !
    ['] FH-CANCEL FH SBRK-H.CANCEL-XT !
    ['] FH-MODELS FH SBRK-H.MODELS-XT !
    ['] FH-IDLE? FH SBRK-H.IDLE-XT !
    FH B SBRK-HANDLER! ;
\ Starts, status asks and cancels.
: FH.  ( -- ) FH-STARTS @ . FH-STATUSES @ . FH-CANCELS @ . ;
\ Whether the broker let go of the run it offered: its owner reference
\ is closed.
: LET-GO.  ( -- ) FH-RUN @ AMRUN.FREE-PENDING @ . ;

\ A broker over no permission file, with the fake handler.
: B-FRESH  ( -- )
    B SBRK-VALID? IF B SBRK-FINI THEN
    T-OPS-RESET HD-INIT P-WIPE FH-RESET
    TV @ HD ROOT @ B SBRK-INIT DROP FH-ON ;
\ A broker over a damaged permission file.
: B-DAMAGED  ( -- status )
    B SBRK-VALID? IF B SBRK-FINI THEN
    T-OPS-RESET HD-INIT P-WIPE FH-RESET
    TBUF 64 7 FILL 64 TLEN ! P-PATH T-PUT-AT
    TV @ HD ROOT @ B SBRK-INIT FH-ON ;

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

\ The permission requests name, and the ones schedules 1 and 2 got.
CREATE PERM 32 ALLOT  VARIABLE PREV
CREATE P1 32 ALLOT  VARIABLE P1REV
CREATE P2 32 ALLOT  VARIABLE P2REV
: SAVE1  ( -- ) PERM P1 RID-COPY PREV @ P1REV ! ;
: SAVE2  ( -- ) PERM P2 RID-COPY PREV @ P2REV ! ;
: USE1  ( -- ) P1 PERM RID-COPY P1REV @ PREV ! ;
: USE2  ( -- ) P2 PERM RID-COPY P2REV @ PREV ! ;
\ RQ names PERM at PREV.
: NAMED  ( -- )
    PERM RQ SDSP-R.PERMISSION RID-COPY PREV @ RQ SDSP-R.PERMISSION-REVISION ! ;
\ The hand-over in RQ of occurrence ID of schedule bytes S, in Practice
\ 4, naming PERM.
: R-OCC  ( s id -- )
    SWAP R-ASK
    DUP RQ SDSP-R.OCCURRENCE ! SDSP-K-ON-TIME RQ SDSP-R.KIND !
    RQ SDSP-R.PRACTICE 32 4 FILL NAMED
    RQ SDSP-R.STORE RQ SDSP-R.SCHEDULE ROT RQ SDSP-R.KEY SDSP-KEY ;

CREATE RSP-RAW 1031 ALLOT  RSP-RAW 7 + -8 AND CONSTANT RSP
: R0  ( -- ) 256 RSP SDSP-RESPONSE-INIT ;
\ The outcome and reason, whether it names PERM, the revision, and the
\ Practice's byte.
: RSP.  ( -- )
    RSP SDSP-P.OUTCOME @ . RSP SDSP-P.REASON @ .
    RSP SDSP-P.PERMISSION PERM RID= . RSP SDSP-P.PERMISSION-REVISION @ .
    RSP SDSP-P.PRACTICE C@ . ;

VARIABLE ASK-ID
\ Asks for approval of schedule S and allows it; PERM and PREV are what
\ was granted.
: APPROVE  ( s -- )
    R-ASK RQ BC SDSP-ASK DROP DUP ASK-ID !
    -1 T-NOW B SBRK-ANSWER DROP
    R0 ASK-ID @ RSP BC SDSP-ASKED DROP
    RSP SDSP-P.PERMISSION PERM RID-COPY RSP SDSP-P.PERMISSION-REVISION @ PREV ! ;

: SUBMIT  ( -- status ) R0 RQ RSP BC SDSP-SUBMIT ;
: STATUS  ( -- status ) R0 RQ SDSP-R.KEY RSP BC SDSP-STATUS ;
: CANCEL  ( -- status ) RQ SDSP-R.KEY BC SDSP-CANCEL ;
: CHECK.  ( -- ) RQ BC SDSP-CHECK SWAP . . ;
\ Whether the fake last heard RQ's dispatch key.
: KEY?  ( -- flag ) FH-KEY RQ SDSP-R.KEY RID= ;
: B32.  ( a -- ) 32 0 DO DUP I + C@ . LOOP DROP ;
"""

SUITE = NativeForth(("tui/applets/desk/schedule-broker.f",),
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
        "B-FRESH B SBRK-VALID? . BS SPERM-STATE@ . BC SDSP-CLIENT-VALID? . "
        "B SBRK-ASKING . . B SBRK-ACTIVE? . RUNS . CR",
        "TV @ HD ROOT @ 0 SBRK-INIT . TV @ HD ROOT @ B 1+ SBRK-INIT . "
        "TV @ HD ROOT @ B SBRK-INIT . CR",
        # Closed, its client answers nothing.
        "B SBRK-FINI B SBRK-VALID? . BC SDSP-CLIENT-VALID? . "
        "1 R-ASK RQ BC SDSP-CHECK . . CR",
        # The root's head made invalid, no root, a root that is not the
        # head's, and a root that is not valid.
        "HD PHEAD.ID 32 0 FILL TV @ HD ROOT @ B SBRK-INIT . HD-INIT "
        "TV @ HD 0 B SBRK-INIT . TV @ HD2 ROOT @ B SBRK-INIT . "
        "ROOT @ CTX.EPOCH @ 0 ROOT @ CTX.EPOCH ! TV @ HD ROOT @ B SBRK-INIT . "
        "ROOT @ CTX.EPOCH ! B SBRK-VALID? . CR",
        "TV @ HD ROOT @ B SBRK-INIT . B SBRK-VALID? . CR",
        # A damaged permission file blocks the store, not the broker.
        "B-DAMAGED . B SBRK-VALID? . BS SPERM-STATE@ . BC SDSP-CLIENT-VALID? . CR",
    ])
    assert rows == [
        [-1, READY, -1, 0, 0, 0, 0],
        [INVALID, INVALID, STATE],
        [0, 0, S_UNAVAILABLE, UNAVAILABLE],
        [INVALID, INVALID, INVALID, INVALID, 0],
        [OK, -1],
        [BLOCKED, -1, 2, -1],
    ]


def test_approvals_and_their_answers(forth):
    rows = run(forth, [
        "B-FRESH A-OPS 1 R-ASK RQ BC SDSP-ASK . . CR",
        # Desk shows a copy of the request.
        "B SBRK-ASKING SWAP . DUP RQ <> . DUP DUP SDSP-REQUEST-U RQ OVER COMPARE . "
        "SDSP-REQUEST-U RQ SDSP-REQUEST-U = . CR",
        "R0 1 RSP BC SDSP-ASKED . BS SPERM-COUNT@ . CR",
        # Allowed: the permission is granted in Desk's Practice, and Daybook
        # hears it once.
        "1 -1 T-NOW B SBRK-ANSWER . BS SPERM-COUNT@ . "
        "R0 1 RSP BC SDSP-ASKED . RSP SDSP-P.PERMISSION 0 BS SPERM-NTH RID= . "
        "RSP SDSP-P.PERMISSION-REVISION @ . RSP SDSP-P.PRACTICE C@ . "
        "0 BS SPERM-NTH SPERM-P.PRACTICE C@ . 0 BS SPERM-NTH SPERM-P.GRANTED @ . CR",
        "R0 1 RSP BC SDSP-ASKED . 1 -1 T-NOW B SBRK-ANSWER . B SBRK-ASKING . . CR",
        # Refused: nothing is granted.
        "RQ BC SDSP-ASK . . 2 0 T-NOW B SBRK-ANSWER . 2 -1 T-NOW B SBRK-ANSWER . "
        "R0 2 RSP BC SDSP-ASKED . BS SPERM-COUNT@ . 2 0 T-NOW B SBRK-ANSWER . "
        "99 -1 T-NOW B SBRK-ANSWER . CR",
        # The same approval allowed again is the same permission.
        "1 APPROVE BS SPERM-COUNT@ . PERM 0 BS SPERM-NTH RID= . PREV @ . CR",
    ])
    assert rows == [
        [S_PENDING, 1],
        [1, -1, 0, -1],
        [S_PENDING, 0],
        [OK, 1, S_ALLOWED, -1, 1, 4, 4, NOW],
        [S_GONE, NOT_FOUND, 0, 0],
        [S_PENDING, 2, OK, NOT_FOUND, S_REFUSED, 1, NOT_FOUND, NOT_FOUND],
        [1, -1, 1],
    ]


def test_approvals_wait_in_order(forth):
    rows = run(forth, [
        # Schedules 2, 3 and 2 again: the second ask for schedule 2
        # withdraws the first.
        "B-FRESH A-OPS 2 R-ASK RQ BC SDSP-ASK . . 3 R-ASK RQ BC SDSP-ASK . . "
        "2 R-ASK RQ BC SDSP-ASK . . CR",
        "R0 1 RSP BC SDSP-ASKED . 1 -1 T-NOW B SBRK-ANSWER . CR",
        "B SBRK-ASKING SDSP-R.SCHEDULE C@ . . 2 0 T-NOW B SBRK-ANSWER . "
        "B SBRK-ASKING SDSP-R.SCHEDULE C@ . . CR",
        # Another store's schedule 2 is another schedule.
        "2 R-ASK RQ SDSP-R.STORE 32 9 FILL RQ BC SDSP-ASK . . "
        "R0 3 RSP BC SDSP-ASKED . R0 4 RSP BC SDSP-ASKED . CR",
        # An approval answered keeps its answer when its schedule is asked
        # about again.
        "B-FRESH 5 R-ASK RQ BC SDSP-ASK . . 1 0 T-NOW B SBRK-ANSWER . "
        "5 R-ASK RQ BC SDSP-ASK . . R0 1 RSP BC SDSP-ASKED . "
        "R0 2 RSP BC SDSP-ASKED . CR",
    ])
    assert rows == [
        [S_PENDING, 1, S_PENDING, 2, S_PENDING, 3],
        [S_GONE, NOT_FOUND],
        [3, 2, OK, 2, 3],
        [S_PENDING, 4, S_PENDING, S_PENDING],
        [S_PENDING, 1, OK, S_PENDING, 2, S_REFUSED, S_PENDING],
    ]


ASK_REFUSALS = {
    "an occurrence": "SDSP-K-ON-TIME RQ SDSP-R.KIND !",
    "no trigger digest": "RQ SDSP-R.TRIGGER-DIGEST 32 0 FILL",
    "another Practice": "RQ SDSP-R.PRACTICE 32 5 FILL",
    "operands that are not the digest's": "1 RQ SDSP-R.OPERANDS-DIGEST +!",
    "a reminder": "SACT-REMINDER RQ SDSP-R.ACTION !",
}


def test_ask_refusals(forth):
    lines = [f"B-FRESH A-OPS 1 R-ASK {edit} RQ BC SDSP-ASK . . B SBRK-ASKING . . CR"
             for edit in ASK_REFUSALS.values()]
    # A request may name Desk's own Practice.
    lines.append("B-FRESH A-OPS 1 R-ASK RQ SDSP-R.PRACTICE 32 4 FILL "
                 "RQ BC SDSP-ASK . . B SBRK-ASKING DROP . CR")
    rows = run(forth, lines)
    assert len(rows) == len(ASK_REFUSALS) + 1, rows
    for name, row in zip(ASK_REFUSALS, rows):
        assert row == [S_INVALID, 0, 0, 0], name
    assert rows[-1] == [S_PENDING, 1, 1]


def test_a_grant_the_store_refuses_keeps_the_approval_waiting(forth):
    rows = run(forth, [
        "B-FRESH A-OPS 1 R-ASK RQ BC SDSP-ASK . . "
        "1 T-SYNC-N ! 1 -1 T-NOW B SBRK-ANSWER . 0 T-SYNC-N ! "
        "BS SPERM-STATE@ . BS SPERM-COUNT@ . B SBRK-ASKING DROP . "
        "R0 1 RSP BC SDSP-ASKED . CR",
        "1 -1 T-NOW B SBRK-ANSWER . R0 1 RSP BC SDSP-ASKED . BS SPERM-COUNT@ . CR",
        # A blocked store grants nothing.
        "B-DAMAGED DROP 1 R-ASK RQ BC SDSP-ASK . . 1 -1 T-NOW B SBRK-ANSWER . "
        "B SBRK-ASKING DROP . CR",
    ])
    assert rows == [
        [S_PENDING, 1, IO, READY, 0, 1, S_PENDING],
        [OK, S_ALLOWED, 1],
        [S_PENDING, 1, BLOCKED, 1],
    ]


STANDINGS = {
    "no permission named": ("", [NONE, S_OK]),
    "the permission": ("NAMED", [APPROVED, S_OK]),
    "another revision": ("NAMED 2 RQ SDSP-R.PERMISSION-REVISION !", [CHANGED, S_OK]),
    "another schedule": ("NAMED RQ SDSP-R.SCHEDULE 32 2 FILL", [CHANGED, S_OK]),
    "an unknown permission": ("NAMED RQ SDSP-R.PERMISSION 32 9 FILL", [WITHDRAWN, S_OK]),
    "an occurrence": ("NAMED SDSP-K-ON-TIME RQ SDSP-R.KIND !", [UNAVAILABLE, S_INVALID]),
}

# Limits altered in memory past the operand digest: each is a change.
LIMITS = ("SPERM-P.EFFECTS", "SPERM-P.TIME", "SPERM-P.DISCLOSURE", "SPERM-P.OUTPUT")


def test_how_requests_stand(forth):
    lines = [f"B-FRESH A-OPS 1 APPROVE 1 R-ASK {edit} CHECK. CR"
             for edit, _ in STANDINGS.values()]
    lines += [f"B-FRESH A-OPS 1 APPROVE 1 R-ASK NAMED "
              f"PERM BS SPERM-FIND {field} 1 SWAP +! CHECK. CR" for field in LIMITS]
    lines += [
        # A permission of another Practice.
        "B-FRESH A-OPS 1 R-ASK RQ HD2 PHEAD.ID T-NOW BS SPERM-GRANT DROP "
        "DUP SPERM-P.RID PERM RID-COPY SPERM-P.REVISION @ PREV ! "
        "1 R-ASK NAMED CHECK. CR",
        # Revoked.
        "B-FRESH A-OPS 1 APPROVE PERM B SBRK-REVOKE . 1 R-ASK NAMED CHECK. CR",
        # The store cannot answer.
        "B-DAMAGED DROP 1 R-ASK NAMED CHECK. CR",
    ]
    rows = run(forth, lines)
    expected = [want for _, want in STANDINGS.values()]
    expected += [[CHANGED, S_OK]] * len(LIMITS)
    expected += [[PRACTICE, S_OK], [OK, WITHDRAWN, S_OK], [UNAVAILABLE, S_OK]]
    assert rows == expected


SUBMIT_REFUSALS = {
    # edit, outcome, reason, names PERM, at revision
    "no permission named":
        ("RQ SDSP-R.PERMISSION 32 0 FILL 0 RQ SDSP-R.PERMISSION-REVISION !",
         O_BLOCKED, R_NOT_APPROVED, 0, 0),
    "a revoked permission": ("PERM B SBRK-REVOKE DROP", O_BLOCKED, R_REVOKED, -1, 1),
    "another revision": ("1 PREV +! NAMED", O_BLOCKED, R_CHANGED, -1, 2),
    "limits that are not the request's":
        ("PERM BS SPERM-FIND SPERM-P.TIME 1 SWAP +!", O_BLOCKED, R_CHANGED, -1, 1),
    "a request in another Practice":
        ("RQ SDSP-R.PRACTICE 32 5 FILL", O_BLOCKED, R_PRACTICE, -1, 1),
    "no handler": ("0 B SBRK-HANDLER!", O_BLOCKED, R_AGENT_UNAVAILABLE, -1, 1),
    "a handler that cannot start": ("0 FH SBRK-H.START-XT !", O_BLOCKED,
                                    R_AGENT_UNAVAILABLE, -1, 1),
    "a handler record that is not one": ("0 FH !", O_BLOCKED, R_AGENT_UNAVAILABLE, -1, 1),
    "a handler record that moved": ("FH 8 + DUP @ 8 + SWAP !", O_BLOCKED,
                                    R_AGENT_UNAVAILABLE, -1, 1),
    "a broken root Context": ("0 ROOT @ CTX.EPOCH !", FAILED, R_INTERNAL, -1, 1),
    "a Practice head no longer valid":
        ("HD PHEAD.CURRENT-ROOT 32 0 FILL", FAILED, R_INTERNAL, -1, 1),
}


def test_submit_refusals(forth):
    """Each refusal comes before the handler is offered anything: nothing
    starts, and the broker remembers no run."""

    lines = [f"B-FRESH A-OPS 1 APPROVE 1 1 R-OCC {edit} SUBMIT . RSP. FH. RUNS . "
             "777 ROOT @ CTX.EPOCH ! CR"
             for edit, _, _, _, _ in SUBMIT_REFUSALS.values()]
    lines += [
        # A request with the wrong key, or naming no occurrence, is invalid.
        "B-FRESH A-OPS 1 APPROVE 1 1 R-OCC 1 RQ SDSP-R.KEY +! SUBMIT . "
        "1 R-ASK NAMED SUBMIT . FH. RUNS . CR",
        # A store that cannot answer.
        "B-DAMAGED DROP 1 1 R-OCC SUBMIT . RSP. FH. RUNS . CR",
        # An authority that could not be made frees its child Context.
        "B-FRESH A-OPS 1 APPROVE 1 1 R-OCC HD PHEAD.CURRENT-ROOT 32 0 FILL SUBMIT . "
        "B _SBRK.CHILD @ CTX-VALID? . HD-INIT CR",
    ]
    rows = run(forth, lines)
    assert len(rows) == len(SUBMIT_REFUSALS) + 3, rows
    assert rows.pop() == [S_ENDED, 0]
    for name, (_, outcome, reason, named, revision), row in zip(
            SUBMIT_REFUSALS, SUBMIT_REFUSALS.values(), rows):
        assert row == [S_ENDED, outcome, reason, named, revision, 4, 0, 0, 0, 0], name
    assert rows[-2] == [S_INVALID, S_INVALID, 0, 0, 0, 0]
    assert rows[-1] == [S_ENDED, O_BLOCKED, R_AGENT_UNAVAILABLE, -1, 1, 4, 0, 0, 0, 0]


def test_a_run_starts_under_its_permission_alone(forth):
    rows = run(forth, [
        "B-FRESH A-OPS 1 APPROVE 1 1 R-OCC SUBMIT . FH. KEY? . "
        "RSP SDSP-P.RUN FH-RID RID= . FH-CTX @ . LET-GO. RUNS . CR",
        "FH-REQ RQ SDSP-REQUEST-U RQ OVER COMPARE . CR",
        # The authority: active, the Agent's, read-only, no effects and no
        # tools, the permission's time and disclosure limits and no others;
        # it and its facet are Desk's Practice's, and the facet is empty.
        "FH-RUN @ DUP AMRUN-ACTIVE? . AMRUN.MANDATE DUP MAND.PRINCIPAL @ . "
        "DUP MAND.DISPOSITION @ . DUP MAND.EFFECTS @ . DUP MAND.TOOL-BUDGET @ . "
        "DUP MAND.TIME-BUDGET-MS @ . DUP MAND.DISCLOSURE-BUDGET @ . "
        "DUP MAND.MEMORY-BUDGET @ . DUP MAND.TOKEN-BUDGET @ . DUP MAND.EXPIRES-MS @ . "
        "MAND.PRACTICE-ID HD PHEAD.ID RID= . "
        "FH-RUN @ AMRUN.FACET DUP CFACET.PRACTICE-ID HD PHEAD.ID RID= . "
        "CFACET.COUNT @ . CR",
        # Its Context: an active child of the root, in Desk's Practice, with
        # no filesystem.
        "FH-RUN @ AMRUN.CONTEXT @ DUP ROOT @ <> . DUP CTX.FLAGS @ CTX-F-ACTIVE AND 0<> . "
        "DUP CTX.PARENT-ID @ ROOT @ CTX.ID @ = . DUP CTX.PRACTICE @ HD = . "
        "DUP CTX.EPOCH @ . CTX.VFS @ . CR",
        # The run's IDs.
        "RQ SDSP-R.KEY B32. CR",
        "FH-RUN @ AMRUN.CONTEXT @ DUP CTX.ID @ . CTX.GENERATION @ . CR",
        "FH-RUN @ AMRUN.MANDATE MAND.ID B32. CR",
        "FH-RUN @ AMRUN.FACET CFACET.ID B32. CR",
        "FH-RUN @ AMRUN.MANDATE DUP MAND.INPUT-FACET-ID FH-RUN @ AMRUN.FACET CFACET.ID "
        "RID= . MAND.DISCLOSURE-FACET-ID FH-RUN @ AMRUN.FACET CFACET.ID RID= . CR",
        # The same occurrence again is the same run.
        "SUBMIT . FH. B SBRK-ACTIVE? . FH-DONE CR",
    ])
    assert rows[:4] == [
        [S_STARTED, 1, 0, 0, -1, -1, 4242, 0, 1],
        [0],
        [-1, 4, 1, 0, 0, 300_000, 4096, 0, 0, 0, -1, -1, 0],
        [-1, -1, -1, -1, 777, 0],
    ]
    key = bytes(rows[4])
    context_id, generation = rows[5]
    practice = bytes([4]) * 32
    for row, tag in ((rows[6], b"desk.schedule.mandate"), (rows[7], b"desk.schedule.facet")):
        assert bytes(row) == hashlib.sha3_256(
            practice + struct.pack("<q", 777) + key
            + struct.pack("<qq", context_id, generation) + tag
        ).digest(), tag
    assert rows[8] == [-1, -1]
    assert rows[9] == [S_RUNNING, 1, 1, 0, -1]


HANDLER_ANSWERS = {
    # answer setup, status, outcome, reason, runs kept
    "a refusal": ("SDSP-S-ENDED FH-START-ANS !", S_ENDED, O_BLOCKED, R_MODEL_UNAVAILABLE, 0),
    "a run that exists": ("SDSP-S-RUNNING FH-START-ANS !", S_RUNNING, 0, 0, 1),
    "an ended run too long to tell": ("SDSP-S-SMALL FH-START-ANS !", S_SMALL, 0, 0, 1),
    "no answer": ("SDSP-S-UNAVAILABLE FH-START-ANS !", S_ENDED, O_BLOCKED,
                  R_AGENT_UNAVAILABLE, 0),
    "nonsense": ("99 FH-START-ANS !", S_ENDED, O_BLOCKED, R_AGENT_UNAVAILABLE, 0),
}


def test_each_answer_but_started_leaves_the_run_to_the_broker(forth):
    lines = [f"B-FRESH A-OPS 1 APPROVE 1 1 R-OCC {setup} SUBMIT . "
             "RSP SDSP-P.OUTCOME @ . RSP SDSP-P.REASON @ . LET-GO. RUNS . FH. CR"
             for setup, _, _, _, _ in HANDLER_ANSWERS.values()]
    # Nonsense that wrote a run and a summary into the response: the
    # broker's answer names neither.
    lines.append("B-FRESH A-OPS 1 APPROVE 1 1 R-OCC 99 FH-START-ANS ! -1 FH-NAMES ! "
                 "SUBMIT . RSP. RSP SDSP-P.RUN RID-ZERO? . RSP SDSP-P.SUMMARY-U @ . CR")
    rows = run(forth, lines)
    assert len(rows) == len(HANDLER_ANSWERS) + 1, rows
    for name, (_, status, outcome, reason, kept), row in zip(
            HANDLER_ANSWERS, HANDLER_ANSWERS.values(), rows):
        assert row == [status, outcome, reason, -1, kept, 1, 0, 0], name
    assert rows[-1] == [S_ENDED, O_BLOCKED, R_AGENT_UNAVAILABLE, -1, 1, 4, -1, 0]


def test_status_keeps_a_run_until_it_ends(forth):
    rows = run(forth, [
        "B-FRESH A-OPS 1 APPROVE 1 1 R-OCC SUBMIT . STATUS . RUNS . FH. CR",
        "SDSP-S-SMALL FH-STATUS-ANS ! STATUS . RUNS . CR",
        "0 B SBRK-HANDLER! STATUS . RUNS . FH-ON CR",
        # Ended: the handler's answer, then the broker forgets the run, and
        # asks the handler about it again.
        "SDSP-S-ENDED FH-STATUS-ANS ! SACT-O-COMPLETED FH-OUTCOME ! 0 FH-WHY ! "
        "-1 FH-NAMES ! STATUS . RSP SDSP-P.OUTCOME @ . RSP SDSP-P.RUN FH-RID RID= . "
        "RUNS . STATUS . FH. CR",
        "B-FRESH A-OPS 1 APPROVE 1 1 R-OCC SUBMIT . SDSP-S-UNKNOWN FH-STATUS-ANS ! "
        "STATUS . RUNS . FH-DONE CR",
    ])
    assert rows == [
        [S_STARTED, S_RUNNING, 1, 1, 1, 0],
        [S_SMALL, 1],
        [S_UNAVAILABLE, 1],
        [S_ENDED, COMPLETED, -1, 0, S_ENDED, 1, 4, 0],
        [S_STARTED, S_UNKNOWN, 0],
    ]


def test_waiting_runs_start_in_order_once_the_handler_is_idle(forth):
    rows = run(forth, [
        "B-FRESH A-OPS 1 APPROVE SAVE1 2 APPROVE SAVE2 "
        "SDSP-S-WAITING FH-START-ANS ! USE1 1 1 R-OCC SUBMIT . LET-GO. "
        "STATUS . FH. B SBRK-ACTIVE? . RUNS . CR",
        "USE2 2 1 R-OCC SUBMIT . FH. RUNS . CR",
        # Busy: nothing starts.
        "0 FH-IDLE ! B SBRK-TICK FH. CR",
        # Idle, but the first must wait on: the second is not offered.
        "SDSP-S-WAITING FH-START-ANS ! -1 FH-IDLE ! B SBRK-TICK FH. LET-GO. RUNS . CR",
        # The first starts, under a newly compiled authority, and lets go of
        # its request; the second waits on.
        "SDSP-S-STARTED FH-START-ANS ! -1 FH-IDLE ! B SBRK-TICK FH. "
        "FH-REQ SDSP-R.SCHEDULE C@ . LET-GO. FH-RUN @ AMRUN-ACTIVE? . "
        "B _SBRK.RUNS @ _SBR.REQUEST @ . B _SBRK.RUNS @ @ _SBR.REQUEST @ 0<> . CR",
        "USE1 1 1 R-OCC STATUS . USE2 2 1 R-OCC STATUS . FH. CR",
        "B SBRK-TICK FH. -1 FH-IDLE ! B SBRK-TICK FH. FH-REQ SDSP-R.SCHEDULE C@ . "
        "LET-GO. KEY? . RUNS . STATUS . FH-DONE CR",
    ])
    assert rows == [
        [S_WAITING, -1, S_WAITING, 1, 0, 0, -1, 1],
        [S_WAITING, 2, 0, 0, 2],
        [2, 0, 0],
        [3, 0, 0, -1, 2],
        [4, 0, 0, 1, 0, -1, 0, -1],
        [S_RUNNING, S_WAITING, 4, 1, 0],
        [4, 1, 0, 5, 1, 0, 2, 0, -1, 2, S_RUNNING],
    ]


RELEASE_ENDS = {
    # edit while it waits, outcome, reason, starts
    "a changed permission":
        ('S" Summarize the town." A-PROMPT 1 APPROVE', O_BLOCKED, R_CHANGED, 1),
    "a refusal": ("SDSP-S-ENDED FH-START-ANS !", O_BLOCKED, R_MODEL_UNAVAILABLE, 2),
    "nonsense": ("99 FH-START-ANS !", O_BLOCKED, R_AGENT_UNAVAILABLE, 2),
}


def test_a_waiting_run_is_checked_again_as_it_starts(forth):
    # The run ends at the broker, which tells Daybook once, naming the
    # permission at the revision the run asked for; the handler gives up
    # the run's place.
    lines = [f"B-FRESH A-OPS 1 APPROVE SAVE1 SDSP-S-WAITING FH-START-ANS ! "
             f"1 1 R-OCC SUBMIT DROP {edit} B SBRK-TICK USE1 1 1 R-OCC "
             "RUNS . FH. KEY? . FH-REASON @ . STATUS . RSP. RUNS . CR"
             for edit, _, _, _ in RELEASE_ENDS.values()]
    lines += [
        # A handler that ended it as a run it knows keeps it, and is asked.
        "B-FRESH A-OPS 1 APPROVE SDSP-S-WAITING FH-START-ANS ! 1 1 R-OCC SUBMIT DROP "
        "SDSP-S-ENDED FH-START-ANS ! SACT-O-FAILED FH-OUTCOME ! "
        "SACT-R-PROVIDER-START FH-WHY ! -1 FH-NAMES ! SDSP-S-ENDED FH-STATUS-ANS ! "
        "B SBRK-TICK RUNS . FH. "
        "STATUS . FH. RUNS . CR",
        # With no handler, nothing starts and nothing ends.
        "B-FRESH A-OPS 1 APPROVE SDSP-S-WAITING FH-START-ANS ! 1 1 R-OCC SUBMIT DROP "
        "0 B SBRK-HANDLER! B SBRK-TICK STATUS . RUNS . CR",
    ]
    rows = run(forth, lines)
    assert len(rows) == len(RELEASE_ENDS) + 2, rows
    for name, (_, outcome, reason, starts), row in zip(
            RELEASE_ENDS, RELEASE_ENDS.values(), rows):
        assert row == [1, starts, 0, 1, -1, reason, S_ENDED, outcome, reason,
                       -1, 1, 4, 0], name
    assert rows[-2] == [1, 2, 0, 0, S_ENDED, 2, 1, 0, 0]
    assert rows[-1] == [S_WAITING, 1]


def test_cancelling(forth):
    rows = run(forth, [
        # A waiting run ends at the broker, and gives up its place.
        "B-FRESH A-OPS 1 APPROVE SDSP-S-WAITING FH-START-ANS ! 1 1 R-OCC SUBMIT DROP "
        "CANCEL . FH. KEY? . FH-REASON @ . B SBRK-ACTIVE? . CANCEL . FH. "
        "STATUS . RSP. RUNS . CR",
        # A started run is the handler's to cancel.
        "B-FRESH A-OPS 1 APPROVE 1 1 R-OCC SUBMIT DROP SDSP-S-UNKNOWN FH-CANCEL-ANS ! "
        "CANCEL . FH. KEY? . FH-REASON @ . FH-CTX @ . RUNS . FH-DONE CR",
        # An unknown run too; with no handler, no one can.
        "B-FRESH A-OPS 1 1 R-OCC CANCEL . FH. 0 B SBRK-HANDLER! CANCEL . CR",
    ])
    assert rows == [
        [S_OK, 1, 0, 1, -1, R_USER, 0, S_OK, 1, 0, 1,
         S_ENDED, CANCELLED, R_USER, -1, 1, 4, 0],
        [S_UNKNOWN, 1, 0, 1, -1, R_USER, 4242, 1],
        [S_OK, 0, 0, 1, S_UNAVAILABLE],
    ]


def test_revoking_stops_the_runs_under_it(forth):
    rows = run(forth, [
        # Schedule 1 has a run started and one waiting; schedule 2 one
        # waiting.
        "B-FRESH A-OPS 1 APPROVE SAVE1 2 APPROVE SAVE2 USE1 1 1 R-OCC SUBMIT . "
        "SDSP-S-WAITING FH-START-ANS ! 1 2 R-OCC SUBMIT . USE2 2 1 R-OCC SUBMIT . "
        "FH. RUNS . CR",
        "P1 B SBRK-REVOKE . FH. FH-REASON @ . BS SPERM-COUNT@ . P1 BS SPERM-FIND . CR",
        # The waiting run ended, revoked; the started one is the handler's;
        # schedule 2's waits on.
        "USE1 1 2 R-OCC STATUS . RSP. 1 1 R-OCC STATUS . "
        "USE2 2 1 R-OCC STATUS . RUNS . CR",
        "P1 B SBRK-REVOKE . 1 T-SYNC-N ! P2 B SBRK-REVOKE . 0 T-SYNC-N ! FH. "
        "BS SPERM-COUNT@ . USE2 2 1 R-OCC STATUS . FH-DONE CR",
    ])
    assert rows == [
        [S_STARTED, S_WAITING, S_WAITING, 3, 0, 0, 3],
        [OK, 3, 0, 2, R_REVOKED, 1, 0],
        [S_ENDED, CANCELLED, R_REVOKED, -1, 1, 4, S_RUNNING, S_WAITING, 2],
        [NOT_FOUND, IO, 3, 1, 2, 1, S_WAITING],
    ]


def test_whether_a_run_is_in_flight(forth):
    rows = run(forth, [
        "B-FRESH B SBRK-ACTIVE? . A-OPS 1 APPROVE 1 1 R-OCC SUBMIT DROP "
        "B SBRK-ACTIVE? . SDSP-S-ENDED FH-STATUS-ANS ! B SBRK-ACTIVE? . "
        "SDSP-S-SMALL FH-STATUS-ANS ! B SBRK-ACTIVE? . "
        "SDSP-S-UNKNOWN FH-STATUS-ANS ! B SBRK-ACTIVE? . "
        "0 B SBRK-HANDLER! B SBRK-ACTIVE? . FH-ON RUNS . FH-DONE CR",
        # Waiting counts; ended at the broker does not.
        "B-FRESH A-OPS 1 APPROVE SDSP-S-WAITING FH-START-ANS ! 1 1 R-OCC SUBMIT DROP "
        "B SBRK-ACTIVE? . CANCEL DROP B SBRK-ACTIVE? . FH. CR",
    ])
    assert rows == [
        [0, -1, 0, 0, 0, -1, 1],
        [-1, 0, 1, 0, 1],
    ]


def test_closing_cancels_what_is_in_flight(forth):
    rows = run(forth, [
        "B-FRESH A-OPS 1 APPROVE SAVE1 2 APPROVE SAVE2 USE1 1 1 R-OCC SUBMIT DROP "
        "SDSP-S-WAITING FH-START-ANS ! USE2 2 1 R-OCC SUBMIT DROP "
        "3 R-ASK RQ BC SDSP-ASK 2DROP "
        "B SBRK-FINI FH. FH-REASON @ . B SBRK-VALID? . BC SDSP-CLIENT-VALID? . CR",
        # The permissions stay on disk.
        "TV @ HD ROOT @ B SBRK-INIT . BS SPERM-COUNT@ . RUNS . B SBRK-ASKING . . "
        "FH-DONE CR",
    ])
    assert rows == [
        [2, 0, 2, R_SHUTDOWN, 0, 0],
        [OK, 2, 0, 0, 0],
    ]


def test_models_come_from_the_handler(forth):
    rows = run(forth, [
        "B-FRESH TBUF 100 BC SDSP-MODELS . . FH-CTX @ . "
        "0 B SBRK-HANDLER! TBUF 100 BC SDSP-MODELS . . CR",
    ])
    assert rows == [[S_OK, 77, 4242, S_UNAVAILABLE, 0]]


def test_why_the_handler_could_not_run_an_approval(forth):
    rows = run(forth, [
        # The fake has no word to say: the Agent is unavailable.  Given one,
        # the broker asks it about the request, with its context.
        "B-FRESH 1 R-ASK RQ B SBRK-VET . "
        "' FH-VET FH SBRK-H.VET-XT ! 0 FH-VETTED ! RQ B SBRK-VET . "
        "FH-VETTED @ RQ = . FH-CTX @ . CR",
        # A broker damaged, with its handler still set; no handler; and no
        # broker.
        "B _SBRK.MAGIC @ 0 B _SBRK.MAGIC ! RQ B SBRK-VET . B _SBRK.MAGIC ! "
        "0 B SBRK-HANDLER! RQ B SBRK-VET . RQ 0 SBRK-VET . RQ B 1+ SBRK-VET . CR",
    ])
    assert rows == [
        [R_AGENT_UNAVAILABLE, R_TOO_LARGE, -1, 4242],
        [R_AGENT_UNAVAILABLE] * 4,
    ]
