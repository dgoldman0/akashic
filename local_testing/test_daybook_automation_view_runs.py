#!/usr/bin/env python3
"""daybook/automation-view.f: the view's Agent runs.

The view reads the Daybook dispatch suite's service, with its scripted
fake broker behind the dispatch client, on the simulator's clock: an
Agent run's schedule row, approved or not; a run waiting, running, then
over and awaiting review, its detail saying how it went in full; and the
actions an Agent run's rows take through the service (Run Now, asking
for approval and where that stands, cancelling a run in flight) with
their refusals and messages.
"""

from __future__ import annotations

import pytest

from native_forth import NativeForth
from test_daybook_automation_dispatch import (
    PRELUDE as DISPATCH_PRELUDE,
    _schedule,
    _tick,
    run,
    text,
)
from test_daybook_automation_owner import NOW, O_FAILED, O_STOPPED, R_PROVIDER_ERROR
from test_daybook_automation_service import _advance


OK, NOT_FOUND, STATE = 0, 8, 5
APPROVAL, BUSY = 19, 16
CHANGED, NONE = 40, 41
HEADING, SCHEDULE, ITEM = 0, 1, 2
R_TOOL = 16

PRELUDE = DISPATCH_PRELUDE + r"""
CREATE VW-RAW DBAV-SIZE 7 + ALLOT  VW-RAW 7 + -8 AND CONSTANT VW
VW DBAV-SIZE 0 FILL
\ The view over the service, built now.
: V-NEW  ( -- ) VW DBAV-FREE SV VW DBAV-INIT VW DBAV-REBUILD . ;
\ Each row: its kind, then title | detail.
: V-ROWS  ( -- )
    VW DBAV-COUNT@ 0 ?DO
        I VW DBAV-ROW DROP .
        I VW DBAV-TITLE TYPE ."  | " I VW DBAV-DETAIL TYPE CR
    LOOP ;
\ Every row's detail, made and dropped.
: DETAILS  ( -- ) VW DBAV-COUNT@ 0 ?DO I VW DBAV-DETAIL 2DROP LOOP ;
\ Whether every row's detail, each made in a fresh buffer, stays within
\ the room it grew to.
: WITHIN-ROOM?  ( -- flag )
    -1 VW DBAV-COUNT@ 0 ?DO
        VW _DBAV.TEXT @ ?DUP IF FREE THEN 0 VW _DBAV.TEXT ! 0 VW _DBAV.CAP !
        I VW DBAV-DETAIL NIP VW _DBAV.CAP @ > IF DROP 0 THEN
    LOOP ;
\ Takes every block external memory can give, largest first; FEED gives
\ them back.
VARIABLE HOG
: STARVE  ( -- )
    0 HOG !
    1099511627776 BEGIN DUP 0> WHILE
        DUP ALLOCATE 0= IF HOG @ OVER ! HOG ! ELSE DROP 2/ THEN
    REPEAT DROP ;
: FEED  ( -- ) BEGIN HOG @ ?DUP WHILE DUP @ HOG ! FREE REPEAT ;
\ A daily reminder at the next hour, under create key 3.
: A-REMINDER  ( -- status )
    DR DBAO-DRAFT-SIZE 0 FILL DBAS-ACTION-REMINDER DR DBAO-D.ACTION !
    DBREC-DAILY DR DBAO-D.RULE DBREC.FREQ ! 1 DR DBAO-D.RULE DBREC.INTERVAL !
    DBSVC-NOW 1000 / 3600 + DR DBAO-D.RULE DBREC.START !
    S" Water the plants" DR DBAO-D.TITLE DBAS-TITLE-MAX DBAS-FIELD!
    S" UTC0" DR DBAO-D.ZONE TZ-STRING-MAX DBAS-FIELD!
    3 KEY1 K! KEY1 DR DBSVC-NOW RID3 SOW DBAO-CREATE ;
\ The row whose title is TITLE, or -1.
: V-FIND  ( title-a title-u -- index )
    VW DBAV-COUNT@ 0 ?DO
        I VW DBAV-ROW DROP DBAV-SCHEDULE = IF
            2DUP I VW DBAV-TITLE COMPARE 0= IF 2DROP I UNLOOP EXIT THEN
        THEN
    LOOP
    2DROP -1 ;
\ The first row of KIND.
: V-KIND  ( kind -- index )
    VW DBAV-COUNT@ 0 ?DO I VW DBAV-ROW DROP OVER = IF DROP I UNLOOP EXIT THEN LOOP
    DROP -1 ;
\ Bytes ALLOCATE can still hand out: the bank-0 heap, the unused tail of
\ external memory and every reclaimed external block.
: AVAILABLE  ( -- u )
    HEAP-FREE-BYTES XMEM-FREE +
    XMEM-FL @ BEGIN ?DUP WHILE DUP @ ROT + SWAP 8 + @ REPEAT ;
"""

SUITE = NativeForth(("tui/applets/daybook/automation-view.f",),
                    prelude=tuple(PRELUDE.strip().splitlines()))


@pytest.fixture()
def machine():
    machine = SUITE.shared()
    machine.runtime.rtc.set_epoch_ms(NOW)
    _advance(machine, 1000, 0)
    return machine


def rows(machine, line: str) -> list[str]:
    output = machine.run([line], 8_000_000_000).decode("latin-1")
    assert "??" not in output, output[-3000:]
    return [row.rstrip() for row in output.replace("\r", "").split("\n") if row.strip()]


def test_an_agent_runs_schedule(machine):
    _schedule(machine, approve=False)
    assert rows(machine, "V-NEW CR V-ROWS") == [
        "0",
        "0 ACTIVE |",
        "1 Read the news | Agent run, not approved, next 2026-10-10 12:00",
    ]
    assert run(machine, [f"{SCHEDULE} V-KIND DUP VW DBAV-AGENT? . VW DBAV-SCHEDULE? . "
                         "0 VW DBAV-AGENT? . 9 VW DBAV-AGENT? . CR"]) == [[-1, -1, 0, 0]]
    # Approved, it says no more than when it runs.
    run(machine, ["R-PERMIT RID1 1 RS DBSVC-NOW SOW DBAO-AUTHORIZE . CR"])
    assert rows(machine, "V-NEW CR V-ROWS")[2] == (
        "1 Read the news | Agent run, next 2026-10-10 12:00")


def test_a_run_waits_runs_and_ends_for_review(machine):
    _schedule(machine)
    run(machine, ["S-WAITING FC-SUBMIT-STATUS ! S-WAITING FC-STATUS-STATUS ! CR"])
    assert _tick(machine, 5000) == -1
    assert rows(machine, "V-NEW CR V-ROWS") == [
        "0",
        "0 IN PROGRESS |",
        "2 Read the news | waiting, 2026-10-10 12:00",
        "0 COMPLETED |",
        "1 Read the news | Agent run, done",
    ]
    assert run(machine, [f"{ITEM} V-KIND VW DBAV-IN-FLIGHT? . "
                         f"{SCHEDULE} V-KIND VW DBAV-IN-FLIGHT? . CR"]) == [[-1, 0]]
    run(machine, ["S-RUNNING FC-STATUS-STATUS ! CR"])
    _tick(machine)
    assert rows(machine, "V-NEW CR V-ROWS")[2] == (
        "2 Read the news | running, 2026-10-10 12:00")
    # It stops for review: the whole outcome and reason show.
    run(machine, [f"S-ENDED FC-STATUS-STATUS ! {O_STOPPED} FC-OUTCOME ! "
                  f"{R_TOOL} FC-REASON ! CR"])
    _tick(machine)
    shown = rows(machine, "V-NEW CR V-ROWS")
    assert shown[1:3] == [
        "0 NEEDS REVIEW |",
        "2 Read the news | stopped for review: asked to use a tool, 2026-10-10 12:00",
    ]
    # Reviewed, it leaves.
    assert run(machine, [f"{ITEM} V-KIND VW DBAV-REVIEW . VW DBAV-REBUILD . "
                         f"{ITEM} V-KIND . CR"]) == [[OK, OK, -1]]


def test_run_now_and_cancel(machine):
    _schedule(machine, due_s=3600)
    assert rows(machine, "V-NEW CR") == ["0"]
    # Run Now hands a run to Desk at once; it then shows in progress.
    assert run(machine, [f"{SCHEDULE} V-KIND VW DBAV-RUN-NOW . FC-SUBMITS @ . "
                         "VW DBAV-STALE? . VW DBAV-REBUILD . CR"]) == [[OK, 1, -1, OK]]
    assert rows(machine, "V-ROWS")[0:2] == [
        "0 IN PROGRESS |",
        "2 Read the news | running, 2026-10-10 12:00",
    ]
    # Another while it is in flight is refused.
    assert run(machine, [f"{SCHEDULE} V-KIND VW DBAV-RUN-NOW . CR"]) == [[BUSY]]
    # Cancelled through Desk; a run Desk does not know ends here, by you,
    # for review.
    assert run(machine, [f"{ITEM} V-KIND VW DBAV-CANCEL . FC-CANCELS @ . CR"]) == [[OK, 1]]
    assert run(machine, ["S-UNKNOWN FC-CANCEL-STATUS ! "
                         f"{ITEM} V-KIND VW DBAV-CANCEL . VW DBAV-REBUILD . CR"]) == [[OK, OK]]
    assert rows(machine, "V-ROWS")[0:2] == [
        "0 NEEDS REVIEW |",
        "2 Read the news | cancelled: by you, 2026-10-10 12:00",
    ]


def test_asking_for_approval(machine):
    _schedule(machine, approve=False, due_s=3600)
    assert rows(machine, "V-NEW VW DBAV-ASK-NOTE TYPE CR") == ["0"]
    # Unapproved, it does not run now; asking reaches Desk.
    assert run(machine, [f"{SCHEDULE} V-KIND VW DBAV-RUN-NOW . "
                         f"{SCHEDULE} V-KIND VW DBAV-ASK . FC-ASKS @ . CR"]) == [
        [APPROVAL, OK, 1]]
    assert text(machine, "VW DBAV-ASK-NOTE TYPE") == "Waiting for approval in Desk"
    # Refused in Desk, the next look says so.
    run(machine, ["S-REFUSED FC-ASKED-STATUS ! CR"])
    _tick(machine)
    assert text(machine, "VW DBAV-ASK-NOTE TYPE") == "Not approved: refused in Desk"
    # Asked again and allowed, it is recorded approved.
    run(machine, [f"S-PENDING FC-ASKED-STATUS ! {SCHEDULE} V-KIND VW DBAV-ASK DROP "
                  "S-ALLOWED FC-ASKED-STATUS ! CR"])
    _tick(machine)
    assert text(machine, "VW DBAV-ASK-NOTE TYPE") == "Approved"
    assert rows(machine, "V-NEW CR V-ROWS")[2] == (
        "1 Read the news | Agent run, next 2026-10-10 13:00")


def test_refusals(machine):
    _schedule(machine, due_s=3600)
    # Rows that are not an Agent run's, rows out of range, and rows older
    # than the store.
    assert run(machine, [
        "V-NEW 0 VW DBAV-RUN-NOW . 0 VW DBAV-ASK . 0 VW DBAV-CANCEL . "
        "9 VW DBAV-RUN-NOW . -1 VW DBAV-CANCEL . "
        f"{SCHEDULE} V-KIND VW DBAV-CANCEL . CR"]) == [[OK, NONE, NONE, NONE, NONE, NONE, NONE]]
    run(machine, ['S" Read the news again" D-TITLE 2 KEY1 K! KEY1 DR DBSVC-NOW RID2 SOW '
                  "DBAO-CREATE . CR"])
    assert run(machine, [f"{SCHEDULE} V-KIND VW DBAV-RUN-NOW . "
                         f"{SCHEDULE} V-KIND VW DBAV-ASK . CR"]) == [[CHANGED, CHANGED]]
    # Without a broker, nothing reaches Desk.
    assert run(machine, ["V-NEW 0 SV DBSVC-CLIENT! "
                         f"{SCHEDULE} V-KIND VW DBAV-ASK . FC-ON CR"]) == [[OK, 30]]


def test_messages():
    expected = {
        16: "A run of it is already in progress",
        17: "Review its last run first",
        19: "It is not approved yet; Y asks Desk",
        8: "That run is over",
        30: "Desk's scheduler is unavailable",
        31: "An approval is already being asked for",
    }
    machine = SUITE.shared()
    for status, message in expected.items():
        assert text(machine, f"{status} DBAV-MESSAGE TYPE") == message


def test_the_view_gives_back_its_text(machine):
    _schedule(machine)
    run(machine, [f"S-ENDED FC-SUBMIT-STATUS ! 0 FC-RUN-BYTE ! {O_FAILED} FC-OUTCOME ! "
                  f"{R_PROVIDER_ERROR} FC-REASON ! CR"])
    _tick(machine, 5000)
    assert run(machine, ["VW DBAV-FREE AVAILABLE V-NEW DETAILS "
                         "VW DBAV-FREE AVAILABLE = . CR"]) == [[OK, -1]]


def test_details_grow_to_what_they_say(machine):
    _schedule(machine, approve=False)
    # Each detail fits the room it grew to; asked again, it takes the
    # room it left.
    assert run(machine, ["V-NEW WITHIN-ROOM? . 0 VW DBAV-DETAIL DROP "
                         f"{SCHEDULE} V-KIND VW DBAV-DETAIL DROP VW _DBAV.TEXT @ "
                         f"{SCHEDULE} V-KIND VW DBAV-DETAIL DROP VW _DBAV.TEXT @ = . CR"]) == [
        [OK, -1, -1]]
    assert rows(machine, "V-ROWS")[1] == (
        "1 Read the news | Agent run, not approved, next 2026-10-10 12:00")
    # Without memory for a detail, it says what fitted, and nothing more.
    assert run(machine, ["VW DBAV-FREE SV VW DBAV-INIT VW DBAV-REBUILD . "
                         f"STARVE {SCHEDULE} V-KIND VW DBAV-DETAIL NIP . FEED CR"]) == [[OK, 0]]
    # A reminder's "next " and date fill a fresh buffer exactly; the space
    # after them grows it.
    assert run(machine, ["A-REMINDER . V-NEW WITHIN-ROOM? . CR"]) == [[OK, OK, -1]]


def test_rows_an_action_does_not_take(machine):
    # A run in progress, then over: only one in flight cancels or shows
    # in flight.
    _schedule(machine)
    run(machine, ["S-RUNNING FC-SUBMIT-STATUS ! CR"])
    _tick(machine, 5000)
    assert run(machine, ["V-NEW CR"]) == [[OK]]
    # Rows older than the store take nothing.
    run(machine, ["A-REMINDER . CR"])
    assert run(machine, [f"{ITEM} V-KIND VW DBAV-CANCEL . CR"]) == [[CHANGED]]
    run(machine, [f"S-ENDED FC-STATUS-STATUS ! {O_FAILED} FC-OUTCOME ! "
                  f"{R_PROVIDER_ERROR} FC-REASON ! CR"])
    _tick(machine)
    assert run(machine, [f"V-NEW {ITEM} V-KIND DUP VW DBAV-IN-FLIGHT? . "
                         "VW DBAV-CANCEL . CR"]) == [[OK, 0, NONE]]
    # A reminder does not run now, nor ask for approval.
    assert run(machine, ['S" Water the plants" V-FIND VW DBAV-RUN-NOW . '
                         'S" Water the plants" V-FIND VW DBAV-ASK . CR']) == [[NONE, NONE]]


def test_a_deleted_runs_records_do_not_show(machine):
    _schedule(machine)
    run(machine, [f"S-ENDED FC-SUBMIT-STATUS ! 0 FC-RUN-BYTE ! {O_FAILED} FC-OUTCOME ! "
                  f"{R_PROVIDER_ERROR} FC-REASON ! CR"])
    _tick(machine, 5000)
    assert rows(machine, "V-NEW CR V-ROWS")[1] == "0 NEEDS REVIEW |"
    # Deleted, its run becomes a short record, which no section shows.
    assert run(machine, ['S" Read the news" V-FIND DUP . VW DBAV-DELETE . VW DBAV-REBUILD . '
                         "VW DBAV-COUNT@ . CR"]) == [[3, OK, OK, 0]]
