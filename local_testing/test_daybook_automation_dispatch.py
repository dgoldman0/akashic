#!/usr/bin/env python3
"""daybook/automation-service.f: Agent runs handed to Desk's broker.

A scripted fake broker stands behind the dispatch client.  The checks
drive the simulator's clock from the host, as Desk's ticks would see it,
and follow a due run through the broker's answers: handed over and
followed to its end; waiting, then started; a broker that cannot take it;
permission standings; runs left in flight when Desk stopped; Run Now and
cancelling; asking for an approval; a summary larger than the response;
and the model list.
"""

from __future__ import annotations

import pytest

from native_forth import NativeForth
from test_daybook_automation_owner import (
    ACCEPTED,
    CLEAR,
    DUE,
    ENDED,
    IN_FLIGHT,
    MANUAL,
    NOW,
    O_BLOCKED,
    O_CANCELLED,
    O_COMPLETED,
    O_FAILED,
    O_INDETERMINATE,
    O_NOT_STARTED,
    OK,
    ON_TIME,
    R_AGENT_UNAVAILABLE,
    R_NOT_APPROVED,
    R_PROVIDER_ERROR,
    R_REVOKED,
    RUNNING,
    STATE,
)
from test_daybook_automation_service import PRELUDE as SERVICE_PRELUDE, _advance


(S_OK, S_INVALID, S_UNAVAILABLE, S_STARTED, S_WAITING, S_ENDED, S_RUNNING,
 S_UNKNOWN, S_PENDING, S_ALLOWED, S_REFUSED, S_GONE, S_SMALL) = range(13)
A_APPROVED, A_NONE, A_WITHDRAWN = 1, 2, 3
NOT_FOUND, CONFLICT, MANUAL_S = 8, 9, 18
R_INVALID, R_RESTART, R_USER, R_AGENT_LOST = 9, 13, 14, 28
SVC_UNAVAILABLE, SVC_PENDING = 30, 31
ASK_NONE, ASK_PENDING, ASK_ALLOWED, ASK_REFUSED, ASK_GONE, ASK_FAILED = range(6)

PRELUDE = SERVICE_PRELUDE + r"""
\ The dispatch contract's answers, by short names.
SDSP-S-OK CONSTANT S-OK  SDSP-S-INVALID CONSTANT S-INVALID
SDSP-S-UNAVAILABLE CONSTANT S-UNAVAILABLE  SDSP-S-STARTED CONSTANT S-STARTED
SDSP-S-WAITING CONSTANT S-WAITING  SDSP-S-ENDED CONSTANT S-ENDED
SDSP-S-RUNNING CONSTANT S-RUNNING  SDSP-S-UNKNOWN CONSTANT S-UNKNOWN
SDSP-S-PENDING CONSTANT S-PENDING  SDSP-S-ALLOWED CONSTANT S-ALLOWED
SDSP-S-REFUSED CONSTANT S-REFUSED  SDSP-S-GONE CONSTANT S-GONE
SDSP-S-SMALL CONSTANT S-SMALL
SDSP-A-APPROVED CONSTANT A-APPROVED  SDSP-A-WITHDRAWN CONSTANT A-WITHDRAWN
\ A fake broker whose answers each check sets.
CREATE FC-RAW SDSP-CLIENT-SIZE 7 + ALLOT  FC-RAW 7 + -8 AND CONSTANT FC
VARIABLE FC-STANDING          \ what a standing check answers
VARIABLE FC-CHECK-STATUS      \ and whether it could
VARIABLE FC-SUBMIT-STATUS     \ what a hand-over answers
VARIABLE FC-STATUS-STATUS     \ what a status check answers
VARIABLE FC-CANCEL-STATUS
VARIABLE FC-ASK-STATUS
VARIABLE FC-ASKED-STATUS
VARIABLE FC-OUTCOME  VARIABLE FC-REASON
VARIABLE FC-RUN-BYTE          \ the run's RID bytes, or 0 for none
VARIABLE FC-SUMMARY-U         \ the summary: that many "s"
VARIABLE FC-PERMISSION-REV    \ a permission revision an end names, or 0
VARIABLE FC-SUBMITS  VARIABLE FC-STATUSES  VARIABLE FC-CANCELS
VARIABLE FC-CHECKS  VARIABLE FC-ASKS  VARIABLE FC-ASKEDS
VARIABLE FC-LAST-OK           \ how the latest request checked
CREATE FC-KEY 32 ALLOT        \ the latest key asked about
CREATE FC-TEXT 1024 ALLOT  FC-TEXT 1024 CHAR s FILL
CREATE FC-REQ-RAW 4103 ALLOT  FC-REQ-RAW 7 + -8 AND CONSTANT FC-REQ
: FC-COPY  ( request -- ) DUP SDSP-REQUEST-U FC-REQ SWAP MOVE ;
\ The scripted end, with its summary; SMALL when the summary does not fit.
: FC-FILL  ( response -- status )
    FC-OUTCOME @ OVER SDSP-P.OUTCOME ! FC-REASON @ OVER SDSP-P.REASON !
    FC-RUN-BYTE @ ?DUP IF OVER SDSP-P.RUN 32 ROT FILL THEN
    FC-PERMISSION-REV @ ?DUP IF
        OVER SDSP-P.PERMISSION-REVISION ! DUP SDSP-P.PERMISSION 32 6 FILL
    THEN
    FC-TEXT FC-SUMMARY-U @ ROT SDSP-SUMMARY! ;
: FC-SUBMIT  ( request response context -- status )
    DROP 1 FC-SUBMITS +!
    OVER -1 SDSP-REQUEST-OK? FC-LAST-OK ! OVER FC-COPY
    SWAP SDSP-R.KEY FC-KEY 32 MOVE
    FC-SUBMIT-STATUS @ DUP S-ENDED = OVER S-STARTED = OR IF
        SWAP FC-FILL DROP
    ELSE NIP THEN ;
: FC-STATUS  ( key response context -- status )
    DROP 1 FC-STATUSES +!
    SWAP FC-KEY 32 MOVE
    FC-STATUS-STATUS @ DUP S-ENDED = OVER S-RUNNING = OR IF
        SWAP FC-FILL IF DROP S-SMALL THEN
    ELSE NIP THEN ;
: FC-CANCEL  ( key context -- status )
    DROP 1 FC-CANCELS +! FC-KEY 32 MOVE FC-CANCEL-STATUS @ ;
: FC-CHECK  ( request context -- standing status )
    DROP 1 FC-CHECKS +! DUP 0 SDSP-REQUEST-OK? FC-LAST-OK ! FC-COPY
    FC-STANDING @ FC-CHECK-STATUS @ ;
: FC-ASK  ( request context -- ask-id status )
    DROP 1 FC-ASKS +! DUP 0 SDSP-REQUEST-OK? FC-LAST-OK ! FC-COPY
    77 FC-ASK-STATUS @ ;
: FC-ASKED  ( ask-id response context -- status )
    DROP 1 FC-ASKEDS +! NIP
    FC-ASKED-STATUS @ S-ALLOWED = IF
        DUP SDSP-P.PRACTICE 32 4 FILL DUP SDSP-P.PERMISSION 32 6 FILL
        1 SWAP SDSP-P.PERMISSION-REVISION !
    ELSE DROP THEN
    FC-ASKED-STATUS @ ;
: FC-MODELS  ( buffer capacity context -- bytes status ) DROP 2DROP 99 S-OK ;
: FC-RESET  ( -- )
    A-APPROVED FC-STANDING ! S-OK FC-CHECK-STATUS !
    S-STARTED FC-SUBMIT-STATUS ! S-RUNNING FC-STATUS-STATUS !
    S-OK FC-CANCEL-STATUS ! S-PENDING FC-ASK-STATUS ! S-PENDING FC-ASKED-STATUS !
    0 FC-OUTCOME ! 0 FC-REASON ! 9 FC-RUN-BYTE ! 0 FC-SUMMARY-U ! 0 FC-PERMISSION-REV !
    0 FC-SUBMITS ! 0 FC-STATUSES ! 0 FC-CANCELS ! 0 FC-CHECKS ! 0 FC-ASKS !
    0 FC-ASKEDS ! -99 FC-LAST-OK ! FC-KEY 32 0 FILL ;
\ The fake behind the service's client.
: FC-ON  ( -- )
    0 FC SDSP-CLIENT-INIT
    ['] FC-SUBMIT FC SDSP-C.SUBMIT-XT ! ['] FC-STATUS FC SDSP-C.STATUS-XT !
    ['] FC-CANCEL FC SDSP-C.CANCEL-XT ! ['] FC-ASK FC SDSP-C.ASK-XT !
    ['] FC-ASKED FC SDSP-C.ASKED-XT ! ['] FC-CHECK FC SDSP-C.CHECK-XT !
    ['] FC-MODELS FC SDSP-C.MODELS-XT !
    FC SV DBSVC-CLIENT! ;
: FC.  ( -- )
    FC-CHECKS @ . FC-SUBMITS @ . FC-STATUSES @ . FC-CANCELS @ . FC-ASKS @ .
    FC-ASKEDS @ . ;
\ Item ID's key is the one the broker was last asked about.
: KEY-ASKED.  ( id -- )
    SOW DBAO-STORE DBAS-FIND-OCCURRENCE DROP SOW DBAO-STORE DBAS-OCCURRENCE
    DBAS-O.KEY 32 FC-KEY 32 COMPARE 0= . ;
\ Item ID: phase, review state, outcome, reason, kind, run byte, summary
\ length.
: S-ITEM.  ( id -- )
    SOW DBAO-STORE DBAS-FIND-OCCURRENCE DROP SOW DBAO-STORE DBAS-OCCURRENCE
    DUP DBAS-O.PHASE @ . DUP DBAS-O.STATE @ . DUP DBAS-O.OUTCOME @ .
    DUP DBAS-O.REASON @ . DUP DBAS-O.KIND @ . DUP DBAS-O.RUN C@ .
    DBAS-O.SUMMARY 8 + @ . ;
: S-AUTH.  ( -- ) RID1 SOW DBAO-ACTION DBAS-A.AUTHORIZED @ . ;
\ A cold start of the service over the same disk, with the fake.
: S-REOPEN  ( -- status ) SV DBSVC-CLOSE TV @ SV DBSVC-OPEN FC-ON ;
"""

SUITE = NativeForth(("tui/applets/daybook/automation-service.f",),
                    prelude=tuple(PRELUDE.strip().splitlines()))


@pytest.fixture()
def machine():
    machine = SUITE.shared()
    machine.runtime.rtc.set_epoch_ms(NOW)
    _advance(machine, 1000, 0)
    return machine


def run(machine, lines: list[str], max_steps: int = 8_000_000_000) -> list[list[int]]:
    output = machine.run(lines, max_steps).decode("latin-1")
    assert "??" not in output, output[-3000:]
    return [[int(token) for token in line.split()]
            for line in output.replace("\r", "").split("\n") if line.strip()]


def text(machine, line: str) -> str:
    output = machine.run([line], 10_000_000).decode("latin-1")
    assert "??" not in output, output
    return output.strip()


def _schedule(machine, *, approve: bool = True, due_s: int = 5) -> None:
    """An Agent run of "Read the news", once, DUE_S seconds from now,
    with the fake broker behind the service."""

    rows = run(machine, [
        "S-FRESH . FC-RESET FC-ON SV DBSVC-TICK . "
        'S" Read the news" D-TITLE DBREC-ONCE D-RULE DBREC.FREQ ! '
        f"DBSVC-NOW 1000 / {due_s} + D-RULE DBREC.START ! D-AGENT S-CREATE . CR",
    ])
    assert rows == [[OK, 0, OK]]
    if approve:
        assert run(machine, ["R-PERMIT RID1 1 RS DBSVC-NOW SOW DBAO-AUTHORIZE . CR"]) == [[OK]]


def _tick(machine, ms: int = 1000) -> int:
    _advance(machine, ms)
    [[notice]] = run(machine, ["SV DBSVC-TICK . CR"])
    return notice


def test_a_due_run_is_handed_over_and_followed_to_its_end(machine):
    _schedule(machine)
    assert _tick(machine, 5000) == -1
    assert text(machine, "SV DBSVC-NOTICE TYPE") == "Agent run: Read the news"
    assert text(machine, "SV DBSVC-NOTICE-SEVERITY .") == "0"
    # Asked for its standing, handed over as an occurrence, started.
    assert run(machine, ["FC. FC-LAST-OK @ . 1 KEY-ASKED. 1 S-ITEM. "
                         "SV DBSVC-IN-FLIGHT? . CR"]) == [
        [1, 1, 1, 0, 0, 0, OK, -1, RUNNING, IN_FLIGHT, 0, 0, ON_TIME, 9, 0, -1]]
    assert text(machine, "FC-REQ SDSP-TITLE$ TYPE") == "Read the news"
    assert text(machine, "FC-REQ SDSP-TRIGGER$ TYPE") == "once on 2026-10-10 at 12:00 (UTC0)"
    assert run(machine, ["FC-REQ SDSP-R.KIND @ . FC-REQ SDSP-R.OCCURRENCE @ . "
                         "FC-REQ SDSP-R.PRACTICE C@ . FC-REQ SDSP-R.PERMISSION C@ . "
                         "FC-REQ SDSP-R.PERMISSION-REVISION @ . "
                         "RID1 SOW DBAO-FIND KEYY DBAO-TRIGGER-DIGEST "
                         "FC-REQ SDSP-R.TRIGGER-DIGEST 32 KEYY 32 COMPARE . CR"]) == [
        [ON_TIME, 1, 4, 6, 1, 0]]
    # Still running a second later.
    assert _tick(machine) == 0
    assert run(machine, ["FC-STATUSES @ . 1 KEY-ASKED. CR"]) == [[2, -1]]
    # It completes.
    run(machine, [f"S-ENDED FC-STATUS-STATUS ! {O_COMPLETED} FC-OUTCOME ! 13 FC-SUMMARY-U ! CR"])
    assert _tick(machine) == -1
    assert text(machine, "SV DBSVC-NOTICE TYPE") == "Agent run done: Read the news"
    assert text(machine, "SV DBSVC-NOTICE-SEVERITY .") == "0"
    assert run(machine, ["1 S-ITEM. SV DBSVC-IN-FLIGHT? . CR"]) == [
        [ENDED, CLEAR, O_COMPLETED, 0, ON_TIME, 9, 13, 0]]
    # Nothing in flight: nothing more to ask.
    assert _tick(machine) == 0
    assert run(machine, ["FC-STATUSES @ . CR"]) == [[3]]


def test_a_waiting_run_starts_then_fails(machine):
    _schedule(machine)
    run(machine, ["S-WAITING FC-SUBMIT-STATUS ! S-WAITING FC-STATUS-STATUS ! CR"])
    assert _tick(machine, 5000) == -1
    assert run(machine, ["1 S-ITEM. CR"]) == [[ACCEPTED, IN_FLIGHT, 0, 0, ON_TIME, 0, 0]]
    assert _tick(machine) == 0
    run(machine, ["S-RUNNING FC-STATUS-STATUS ! CR"])
    assert _tick(machine) == 0
    assert run(machine, ["1 S-ITEM. CR"]) == [[RUNNING, IN_FLIGHT, 0, 0, ON_TIME, 9, 0]]
    run(machine, [f"S-ENDED FC-STATUS-STATUS ! {O_FAILED} FC-OUTCOME ! "
                  f"{R_PROVIDER_ERROR} FC-REASON ! CR"])
    assert _tick(machine) == -1
    assert text(machine, "SV DBSVC-NOTICE TYPE") == "Needs review: Read the news"
    assert text(machine, "SV DBSVC-NOTICE-SEVERITY .") == "3"
    assert run(machine, ["1 S-ITEM. S-AUTH. CR"]) == [
        [ENDED, DUE, O_FAILED, R_PROVIDER_ERROR, ON_TIME, 9, 0, 1]]


@pytest.mark.parametrize("answer, outcome, reason, kept", [
    ("S-UNAVAILABLE", O_BLOCKED, R_AGENT_UNAVAILABLE, 1),
    ("S-INVALID", O_BLOCKED, R_INVALID, 1),
    # The broker refuses the very permission Daybook holds.
    ("S-ENDED 0 FC-RUN-BYTE ! 1 FC-PERMISSION-REV ! "
     f"{O_BLOCKED} FC-OUTCOME ! {R_REVOKED} FC-REASON !", O_BLOCKED, R_REVOKED, 0),
])
def test_a_run_the_broker_does_not_take(machine, answer, outcome, reason, kept):
    _schedule(machine)
    run(machine, [f"{answer} FC-SUBMIT-STATUS ! CR"])
    assert _tick(machine, 5000) == -1
    assert text(machine, "SV DBSVC-NOTICE TYPE") == "Needs review: Read the news"
    assert text(machine, "SV DBSVC-NOTICE-SEVERITY .") == "3"
    assert run(machine, ["1 S-ITEM. S-AUTH. SV DBSVC-IN-FLIGHT? . CR"]) == [
        [ENDED, DUE, outcome, reason, ON_TIME, 0, 0, kept, 0]]


def test_a_run_whose_permission_does_not_stand_is_never_handed_over(machine):
    _schedule(machine)
    run(machine, ["A-WITHDRAWN FC-STANDING ! CR"])
    assert _tick(machine, 5000) == -1
    assert run(machine, ["FC. 1 S-ITEM. S-AUTH. CR"]) == [
        [1, 0, 0, 0, 0, 0, ENDED, DUE, O_BLOCKED, R_REVOKED, ON_TIME, 0, 0, 0]]
    # A broker that cannot answer the check: the Agent is unavailable.
    _schedule(machine)
    run(machine, ["S-UNAVAILABLE FC-CHECK-STATUS ! CR"])
    assert _tick(machine, 5000) == -1
    assert run(machine, ["FC. 1 S-ITEM. S-AUTH. CR"]) == [
        [1, 0, 0, 0, 0, 0, ENDED, DUE, O_BLOCKED, R_AGENT_UNAVAILABLE, ON_TIME, 0, 0, 1]]
    # A schedule Daybook does not hold approved is not even asked about.
    _schedule(machine, approve=False)
    assert _tick(machine, 5000) == -1
    assert run(machine, ["FC. 1 S-ITEM. CR"]) == [
        [0, 0, 0, 0, 0, 0, ENDED, DUE, O_BLOCKED, R_NOT_APPROVED, ON_TIME, 0, 0]]


def test_runs_left_in_flight_are_settled(machine):
    """After a restart the broker answers for what it knows; what it does
    not know never started, or is indeterminate if it had."""

    _schedule(machine)
    run(machine, ["S-WAITING FC-SUBMIT-STATUS ! S-WAITING FC-STATUS-STATUS ! CR"])
    assert _tick(machine, 5000) == -1
    assert run(machine, ["1 S-ITEM. SV DBSVC-IN-FLIGHT? . CR"]) == [
        [ACCEPTED, IN_FLIGHT, 0, 0, ON_TIME, 0, 0, -1]]
    # The broker no longer knows it after a restart.
    assert run(machine, ["S-REOPEN . FC-RESET S-UNKNOWN FC-STATUS-STATUS ! CR"]) == [[OK]]
    assert _tick(machine) == -1
    assert text(machine, "SV DBSVC-NOTICE TYPE") == "Needs review: Read the news"
    assert text(machine, "SV DBSVC-NOTICE-SEVERITY .") == "3"
    assert run(machine, ["1 S-ITEM. SV DBSVC-IN-FLIGHT? . CR"]) == [
        [ENDED, DUE, O_NOT_STARTED, R_RESTART, ON_TIME, 0, 0, 0]]
    # A run that had started is indeterminate.
    _schedule(machine)
    assert _tick(machine, 5000) == -1
    assert run(machine, ["S-REOPEN . S-UNKNOWN FC-STATUS-STATUS ! CR"]) == [[OK]]
    assert _tick(machine) == -1
    assert run(machine, ["1 S-ITEM. CR"]) == [
        [ENDED, DUE, O_INDETERMINATE, R_AGENT_LOST, ON_TIME, 9, 0]]
    # A broker that cannot answer yet leaves it in flight; one that knows
    # it is believed.
    _schedule(machine)
    run(machine, ["S-WAITING FC-SUBMIT-STATUS ! S-WAITING FC-STATUS-STATUS ! CR"])
    assert _tick(machine, 5000) == -1
    assert run(machine, ["S-REOPEN . S-UNAVAILABLE FC-STATUS-STATUS ! CR"]) == [[OK]]
    assert _tick(machine) == 0
    assert run(machine, ["1 S-ITEM. CR"]) == [[ACCEPTED, IN_FLIGHT, 0, 0, ON_TIME, 0, 0]]
    run(machine, ["S-RUNNING FC-STATUS-STATUS ! CR"])
    assert _tick(machine) == 0
    assert run(machine, ["1 S-ITEM. CR"]) == [[RUNNING, IN_FLIGHT, 0, 0, ON_TIME, 9, 0]]


def test_run_now_and_cancelling(machine):
    _schedule(machine, due_s=3600)
    assert run(machine, ["RID1 1 SV DBSVC-RUN-NOW . . FC. FC-LAST-OK @ . "
                         "FC-REQ SDSP-R.KIND @ . 1 S-ITEM. CR"]) == [
        [OK, 1, 0, 1, 0, 0, 0, 0, OK, MANUAL, RUNNING, IN_FLIGHT, 0, 0, MANUAL, 9, 0]]
    # One run at a time.
    assert run(machine, ["RID1 1 SV DBSVC-RUN-NOW . . CR"]) == [[16, 0]]
    # Cancelling asks the broker; the end comes with a later look.
    assert run(machine, ["1 SV DBSVC-CANCEL . FC-CANCELS @ . 1 KEY-ASKED. CR"]) == [[OK, 1, -1]]
    run(machine, [f"S-ENDED FC-STATUS-STATUS ! {O_CANCELLED} FC-OUTCOME ! "
                  f"{R_USER} FC-REASON ! CR"])
    assert _tick(machine) == -1
    assert run(machine, ["1 S-ITEM. CR"]) == [[ENDED, DUE, O_CANCELLED, R_USER, MANUAL, 9, 0]]
    # A run the broker does not know is cancelled here.
    run(machine, ["S-UNKNOWN FC-CANCEL-STATUS ! S-WAITING FC-SUBMIT-STATUS ! "
                  "S-WAITING FC-STATUS-STATUS ! CR"])
    assert run(machine, ["RID1 1 SV DBSVC-RUN-NOW . . 2 SV DBSVC-CANCEL . 2 S-ITEM. CR"]) == [
        [OK, 2, OK, ENDED, DUE, O_CANCELLED, R_USER, MANUAL, 0, 0]]
    # Refusals: a run no longer in flight, an unknown one, and one in
    # flight with no broker to ask.
    assert run(machine, ["2 SV DBSVC-CANCEL . 9 SV DBSVC-CANCEL . "
                         "RID1 1 SV DBSVC-RUN-NOW . . 0 SV DBSVC-CLIENT! "
                         "3 SV DBSVC-CANCEL . CR"]) == [
        [STATE, NOT_FOUND, OK, 3, SVC_UNAVAILABLE]]
    # Without a broker, a run asked for by hand ends at once.
    assert run(machine, ["FC-ON 3 SV DBSVC-CANCEL . 0 SV DBSVC-CLIENT! "
                         "RID1 1 SV DBSVC-RUN-NOW . . 4 S-ITEM. CR"]) == [
        [OK, OK, 4, ENDED, DUE, O_BLOCKED, R_AGENT_UNAVAILABLE, MANUAL, 0, 0]]


def test_asking_for_an_approval(machine):
    _schedule(machine, approve=False, due_s=3600)
    assert run(machine, ["RID1 1 SV DBSVC-ASK . SV DBSVC-ASK-STATE@ . FC. FC-LAST-OK @ . "
                         "RID1 1 SV DBSVC-ASK . CR"]) == [
        [OK, ASK_PENDING, 0, 0, 0, 0, 1, 0, OK, SVC_PENDING]]
    assert _tick(machine) == 0
    assert run(machine, ["SV DBSVC-ASK-STATE@ . FC-ASKEDS @ . S-AUTH. CR"]) == [
        [ASK_PENDING, 1, 0]]
    run(machine, ["S-ALLOWED FC-ASKED-STATUS ! CR"])
    assert _tick(machine) == 0
    assert run(machine, ["SV DBSVC-ASK-STATE@ . S-AUTH. "
                         "SV DBSVC-ASK-RID RID1 RID= . CR"]) == [[ASK_ALLOWED, 1, -1]]
    # Refused, or withdrawn unanswered.
    for answer, state in (("S-REFUSED", ASK_REFUSED), ("S-GONE", ASK_GONE)):
        run(machine, [f"RID1 1 SV DBSVC-ASK DROP {answer} FC-ASKED-STATUS ! CR"])
        assert _tick(machine) == 0
        assert run(machine, ["SV DBSVC-ASK-STATE@ . CR"]) == [[state]]
    # Allowed, but the schedule changed meanwhile.
    run(machine, ["S-PENDING FC-ASKED-STATUS ! RID1 1 SV DBSVC-ASK DROP "
                  'S" Read the papers" D-TITLE RID1 1 DR DBSVC-NOW SOW DBAO-REPLACE DROP '
                  "S-ALLOWED FC-ASKED-STATUS ! CR"])
    assert _tick(machine) == 0
    assert run(machine, ["SV DBSVC-ASK-STATE@ . CR"]) == [[ASK_FAILED]]
    # Refusals.
    assert run(machine, ["RID1 1 SV DBSVC-ASK . 9 RID2 K! RID2 1 SV DBSVC-ASK . "
                         "0 SV DBSVC-CLIENT! RID1 2 SV DBSVC-ASK . RID2 1 SV DBSVC-ASK . CR"]) == [
        [CONFLICT, NOT_FOUND, SVC_UNAVAILABLE, SVC_UNAVAILABLE]]
    run(machine, ["FC-ON S-INVALID FC-ASK-STATUS ! CR"])
    assert run(machine, ["RID1 2 SV DBSVC-ASK . CR"]) == [[1]]


def test_a_reminder_takes_no_approval(machine):
    run(machine, ["S-FRESH DROP FC-RESET FC-ON S-CREATE DROP CR"])
    assert run(machine, ["RID1 1 SV DBSVC-ASK . FC-ASKS @ . CR"]) == [[MANUAL_S, 0]]


def test_a_summary_larger_than_the_response_is_asked_for_again(machine):
    _schedule(machine)
    assert _tick(machine, 5000) == -1
    run(machine, [f"S-ENDED FC-STATUS-STATUS ! {O_COMPLETED} FC-OUTCOME ! "
                  "300 FC-SUMMARY-U ! CR"])
    # The summary does not fit: the next look asks again with room for it.
    assert _tick(machine) == 0
    assert run(machine, ["1 S-ITEM. CR"]) == [[RUNNING, IN_FLIGHT, 0, 0, ON_TIME, 9, 0]]
    assert _tick(machine) == -1
    assert run(machine, ["1 S-ITEM. FC-STATUSES @ . CR"]) == [
        [ENDED, CLEAR, O_COMPLETED, 0, ON_TIME, 9, 300, 3]]
    # A hand-over that ends at once with a long summary is asked about
    # again, in the same look, with room for it.
    _schedule(machine)
    run(machine, [f"S-ENDED FC-SUBMIT-STATUS ! {O_BLOCKED} FC-OUTCOME ! "
                  f"{R_REVOKED} FC-REASON ! 0 FC-RUN-BYTE ! 500 FC-SUMMARY-U ! "
                  "S-ENDED FC-STATUS-STATUS ! CR"])
    assert _tick(machine, 5000) == -1
    assert run(machine, ["1 S-ITEM. FC-STATUSES @ . CR"]) == [
        [ENDED, DUE, O_BLOCKED, R_REVOKED, ON_TIME, 0, 500, 1]]


def test_the_model_list_comes_from_the_broker(machine):
    run(machine, ["S-FRESH DROP FC-RESET CR"])
    assert run(machine, ["FC-TEXT 64 SV DBSVC-MODELS . . FC-ON FC-TEXT 64 SV DBSVC-MODELS . . "
                         "CR"]) == [
        [S_UNAVAILABLE, 0, S_OK, 99]]
