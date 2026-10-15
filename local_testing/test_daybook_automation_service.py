#!/usr/bin/env python3
"""daybook/automation-runner.f and automation-service.f: schedules on time.

The runner checks take explicit clock readings, so they can place a look
exactly: on time, after a jump back or forward, after a restart, with the
clock unset, and either side of the jump threshold.  The service checks
drive the simulator's real clock from the host, as Desk's ticks would see
it: an unset clock, idle ticks, one second at a time up to a reminder, a
wall clock set forward, the notices, and an Agent run with no broker to
hand it to.
"""

from __future__ import annotations

import pytest

from native_forth import NativeForth
from test_daybook_automation_owner import (
    ACTIVATION,
    CLOCK,
    CONTINUOUS,
    DUE,
    ENDED,
    IO,
    JUMP,
    MISSED,
    NOW,
    O_BLOCKED,
    OK,
    ON_TIME,
    PRELUDE as OWNER_PRELUDE,
    R_AGENT_UNAVAILABLE,
    ms,
)


CLOCK_UNKNOWN, CLOCK_SET, CLOCK_UNSET = range(3)

PRELUDE = OWNER_PRELUDE + r"""
CREATE RN-RAW DBRUN-SIZE 7 + ALLOT  RN-RAW 7 + -8 AND CONSTANT RN
CREATE SV-RAW DBSVC-SIZE 7 + ALLOT  SV-RAW 7 + -8 AND CONSTANT SV
\ An owner over no file with the base draft, and a runner over it.
: R-FRESH  ( -- ) O-FRESH OW RN DBRUN-INIT ;
\ A look, then what it found due accepted as the service would: the
\ status and how many fired.
VARIABLE L-WALL
: LOOK.  ( uptime wall valid? -- )
    OVER L-WALL ! RN DBRUN-LOOK IF L-WALL @ SWAP T-ACCEPT-ALL ELSE DROP 0 0 THEN
    . . ;
\ The base draft: a daily reminder at 09:00 UTC from 2026-10-11, key 1.
: S-DRAFT  ( -- )
    DR DBAO-DRAFT-SIZE 0 FILL DBAS-ACTION-REMINDER DR DBAO-D.ACTION !
    DBREC-DAILY D-RULE DBREC.FREQ ! 1 D-RULE DBREC.INTERVAL !
    2026 10 11 DT-YMD>EPOCH-S DROP 32400 + D-RULE DBREC.START !
    S" Water the plants" D-TITLE S" UTC0" D-ZONE 1 KEY1 K! ;
\ A service over no file, and the base draft.
: S-FRESH  ( -- status )
    SV DBSVC-VALID? IF SV DBSVC-CLOSE THEN
    T-OPS-RESET T-PATH T-RM S-DRAFT TV @ SV DBSVC-OPEN ;
: SOW  ( -- owner ) SV DBSVC-OWNER ;
: S-GEN  ( -- n ) SOW DBAO-STORE DBAS-GENERATION@ ;
: S-CREATE  ( -- status ) KEY1 DR DBSVC-NOW RID1 SOW DBAO-CREATE ;
: TICKS  ( n -- ) 0 ?DO SV DBSVC-TICK DROP LOOP ;
\ Item ID's phase, review state, outcome and reason.
: S-RUN.  ( id -- )
    SOW DBAO-STORE DBAS-FIND-OCCURRENCE DROP SOW DBAO-STORE DBAS-OCCURRENCE
    DUP DBAS-O.PHASE @ . DUP DBAS-O.STATE @ . DUP DBAS-O.OUTCOME @ .
    DBAS-O.REASON @ . ;
: NOTHING  ( n -- ) 0 ?DO 0 DROP LOOP ;
"""

SUITE = NativeForth(("tui/applets/daybook/automation-service.f",),
                    prelude=tuple(PRELUDE.strip().splitlines()))


@pytest.fixture(scope="module")
def forth():
    return SUITE.shared()


def run(forth, lines: list[str], max_steps: int = 8_000_000_000) -> list[list[int]]:
    output = forth.run(lines, max_steps).decode("latin-1")
    assert "??" not in output, output[-3000:]
    return [[int(token) for token in line.split()]
            for line in output.replace("\r", "").split("\n") if line.strip()]


def test_a_reminder_fires_once_and_never_again_after_a_jump_back(forth):
    rows = run(forth, [
        f"R-FRESH {NOW} CREATE1 . CR",
        # An unset clock: nothing fires, nothing is written.
        "0 0 0 LOOK. RN DBRUN-CLOCK@ . RN DBRUN-NEXT@ . GEN . CR",
        f"1000 {ms(2026, 10, 11, 8, 59, 59)} -1 LOOK. RN DBRUN-CLOCK@ . "
        "RN DBRUN-NEXT@ . CR",
        f"2000 {ms(2026, 10, 11, 9)} -1 LOOK. ITEMS . 1 ITEM. CR",
        f"3000 {ms(2026, 10, 11, 9, 0, 1)} -1 LOOK. GEN . CR",
        # The wall clock goes back an hour, then runs on past 09:00 again.
        f"4000 {ms(2026, 10, 11, 8)} -1 LOOK. GEN . CR",
        f"5000 {ms(2026, 10, 11, 8, 0, 1)} -1 LOOK. "
        f"6000 {ms(2026, 10, 11, 9, 0, 1)} -1 LOOK. ITEMS . GEN . CR",
    ])
    gen = 2
    assert rows == [
        [OK],
        [OK, 0, CLOCK_UNSET, 1000, 1],
        [OK, 0, CLOCK_SET, 2000],
        [OK, 1, 1, 1, 1, 1, ON_TIME, CONTINUOUS, DUE],
        [OK, 0, gen],
        [OK, 0, gen],
        [OK, 0, OK, 0, 1, gen],
    ]


def test_a_jump_forward_and_a_restart_each_give_one_missed_item(forth):
    rows = run(forth, [
        f"R-FRESH {NOW} CREATE1 . "
        f"1000 {ms(2026, 10, 11, 8, 59, 59)} -1 LOOK. "
        f"2000 {ms(2026, 10, 11, 9)} -1 LOOK. "
        f"1 1 {ms(2026, 10, 11, 9, 5)} OW DBAO-REVIEW . CR",
        # Three days ahead in one second of uptime.
        f"3000 {ms(2026, 10, 14, 10)} -1 LOOK. ITEMS . 2 ITEM. CR",
        f"2 4 {ms(2026, 10, 14, 10, 5)} OW DBAO-REVIEW . CR",
        # A restart: the owner reopens and a new runner starts at uptime 0.
        f"O-REOPEN . OW RN DBRUN-INIT 0 {ms(2026, 10, 15, 9, 0, 5)} -1 LOOK. "
        "ITEMS . 3 ITEM. CR",
        # Setting the clock again starts over: no history, so missed.
        f"3 5 {ms(2026, 10, 15, 9, 5)} OW DBAO-REVIEW . "
        f"1000 0 0 LOOK. 2000 {ms(2026, 10, 16, 9)} -1 LOOK. 4 ITEM. CR",
    ])
    assert rows == [
        [OK, OK, 0, OK, 1, OK],
        [OK, 1, 2, 2, 4, 3, MISSED, JUMP, DUE],
        [OK],
        [OK, OK, 1, 3, 5, 5, 1, MISSED, ACTIVATION, DUE],
        [OK, OK, 0, OK, 1, 6, 6, 1, MISSED, ACTIVATION, DUE],
    ]


def test_the_jump_threshold(forth):
    """Two seconds of disagreement is drift; a millisecond more is a jump."""

    lines = []
    for extra in (0, 1):
        before = ms(2026, 10, 11, 8, 59, 57) - extra
        lines.append(
            f"R-FRESH {NOW} CREATE1 . 1000 {before} -1 LOOK. "
            f"2000 {ms(2026, 10, 11, 9)} -1 LOOK. 1 ITEM. CR")
    rows = run(forth, lines)
    assert rows == [
        [OK, OK, 0, OK, 1, 1, 1, 1, ON_TIME, CONTINUOUS, DUE],
        [OK, OK, 0, OK, 1, 1, 1, 1, MISSED, JUMP, DUE],
    ]


def test_a_new_reminder_is_seen_at_the_next_look(forth):
    rows = run(forth, [
        f"R-FRESH {NOW} CREATE1 . 1000 {NOW} -1 LOOK. CR",
        # Due in one second, created after the runner read the due time.
        f"DBREC-ONCE D-RULE DBREC.FREQ ! {(NOW + 1000) // 1000} D-RULE DBREC.START ! "
        f"2 KEY1 K! KEY1 DR {NOW} RID2 OW DBAO-CREATE . "
        f"2000 {NOW + 1000} -1 LOOK. ITEMS . CR",
    ])
    assert rows == [
        [OK, OK, 0],
        [OK, OK, 1, 1],
    ]


@pytest.fixture()
def clocked():
    """A machine of its own whose clock starts unset, as a board's does."""

    return SUITE.shared()


def _advance(machine, uptime_ms: int, wall_ms: int | None = None) -> None:
    rtc = machine.runtime.rtc
    rtc.advance_uptime_ms(uptime_ms)
    rtc.advance_ms(uptime_ms if wall_ms is None else wall_ms)


def _steps(machine, source: str) -> int:
    result = machine.runtime.evaluate(source.encode(), source_name="steps",
                                      step_budget=100_000_000)
    machine.runtime.drain_uart_output()
    return result.semantic_steps


# An idle tick is one uptime read and a compare: a few dozen steps of word
# calls, whatever the reminders.
IDLE_TICK_STEPS = 40


def _idle_tick_steps(machine) -> float:
    ticks = _steps(machine, "1000 TICKS") - _steps(machine, "1000 NOTHING")
    return ticks / 1000


def test_the_service_on_the_real_clock(clocked):
    rtc = clocked.runtime.rtc
    assert not rtc.epoch_valid
    rows = run(clocked, [
        "S-FRESH . SV DBSVC-TICK . SV DBSVC-CLOCK@ . S-GEN . "
        "T-PATH T-THERE? . DBSVC-NOW . S-CREATE . CR",
    ])
    assert rows == [[OK, 0, CLOCK_UNSET, 0, 0, -1, CLOCK]]

    # The clock is set; a reminder for 30 seconds later.
    rtc.set_epoch_ms(NOW)
    _advance(clocked, 1000, 0)
    rows = run(clocked, [
        'SV DBSVC-TICK . SV DBSVC-CLOCK@ . S" Take the medicine" D-TITLE '
        f"DBREC-ONCE D-RULE DBREC.FREQ ! {NOW // 1000 + 30} D-RULE DBREC.START ! "
        "S-CREATE . S-GEN . CR",
    ])
    assert rows == [[0, CLOCK_SET, OK, 1]]

    # Ticks before the next look read uptime, compare, and write nothing.
    assert _idle_tick_steps(clocked) <= IDLE_TICK_STEPS
    assert run(clocked, ["S-GEN . CR"]) == [[1]]

    # One second at a time: the reminder fires once, at its second.
    fired = []
    for second in range(1, 36):
        _advance(clocked, 1000)
        rows = run(clocked, ["SV DBSVC-TICK . CR"])
        if rows == [[-1]]:
            fired.append(second)
    assert fired == [30]
    output = clocked.run(["SV DBSVC-NOTICE TYPE CR"], 10_000_000).decode()
    assert output.strip() == "Reminder: Take the medicine"
    assert run(clocked, ["SV DBSVC-NOTICE-SEVERITY . CR"]) == [[0]]

    # Two daily reminders at 09:00 tomorrow; the clock is set two days on.
    rows = run(clocked, [
        'S" Water the plants" D-TITLE DBREC-DAILY D-RULE DBREC.FREQ ! '
        "2026 10 11 DT-YMD>EPOCH-S DROP 32400 + D-RULE DBREC.START ! "
        "2 KEY1 K! S-CREATE . "
        'S" Feed the cat" D-TITLE 3 KEY1 K! S-CREATE . CR',
    ])
    assert rows == [[OK, OK]]
    _advance(clocked, 1000, 2 * 86_400_000)
    rows = run(clocked, ["SV DBSVC-TICK . SOW DBAO-STORE DBAS-OCCURRENCE-COUNT@ . CR"])
    assert rows == [[-1, 3]]
    output = clocked.run(["SV DBSVC-NOTICE TYPE CR"], 10_000_000).decode()
    assert output.strip() in ("Reminders: Water the plants and 1 more",
                              "Reminders: Feed the cat and 1 more")

    # Nothing more until tomorrow's 09:00, which one of them reviews.
    rows = run(clocked, [
        "SV DBSVC-TICK . 2 2 DBSVC-NOW SOW DBAO-REVIEW . CR",
    ])
    assert rows == [[0, OK]]


def test_a_missed_notice(clocked):
    rtc = clocked.runtime.rtc
    rtc.set_epoch_ms(NOW)
    _advance(clocked, 1000, 0)
    rows = run(clocked, [
        "S-FRESH . SV DBSVC-TICK . S-CREATE . CR",
    ])
    assert rows == [[OK, 0, OK]]
    _advance(clocked, 1000, 86_400_000)
    rows = run(clocked, ["SV DBSVC-TICK . CR"])
    assert rows == [[-1]]
    output = clocked.run(["SV DBSVC-NOTICE TYPE CR"], 10_000_000).decode()
    assert output.strip() == "Missed: Water the plants"
    # A missed reminder warns.
    assert run(clocked, ["SV DBSVC-NOTICE-SEVERITY . CR"]) == [[3]]


def test_idle_ticks_cost_the_same_with_many_reminders(clocked):
    rtc = clocked.runtime.rtc
    rtc.set_epoch_ms(NOW)
    _advance(clocked, 1000, 0)
    assert run(clocked, ["S-FRESH . SV DBSVC-TICK . S-CREATE . CR"]) == [[OK, 0, OK]]
    one = _idle_tick_steps(clocked)
    rows = run(clocked, [
        ": MANY 50 2 DO I KEY1 K! S-CREATE DROP LOOP ; MANY "
        "SOW DBAO-STORE DBAS-SCHEDULE-COUNT@ . S-GEN . CR",
    ])
    assert rows == [[49, 49]]
    many = _idle_tick_steps(clocked)
    assert one == many <= IDLE_TICK_STEPS
    assert run(clocked, ["S-GEN . CR"]) == [[49]]

    # All of them due in one look, more than a page of them.
    _advance(clocked, 1000, 21 * 3_600_000)
    rows = run(clocked, ["SV DBSVC-TICK . SV DBSVC-STATUS@ . "
                         "SOW DBAO-STORE DBAS-OCCURRENCE-COUNT@ . S-GEN . CR"])
    assert rows == [[-1, OK, 49, 98]]
    output = clocked.run(["SV DBSVC-NOTICE TYPE CR"], 10_000_000).decode()
    assert output.strip() == "Reminders: Water the plants and 48 more"


def test_a_look_whose_commit_fails_tries_again(clocked):
    rtc = clocked.runtime.rtc
    rtc.set_epoch_ms(NOW)
    _advance(clocked, 1000, 0)
    rows = run(clocked, [
        "S-FRESH . SV DBSVC-TICK . DBREC-ONCE D-RULE DBREC.FREQ ! "
        f"{NOW // 1000 + 5} D-RULE DBREC.START ! S-CREATE . CR",
    ])
    assert rows == [[OK, 0, OK]]
    _advance(clocked, 5000)
    rows = run(clocked, ["1 T-SYNC-N ! SV DBSVC-TICK . SV DBSVC-STATUS@ . "
                         "SOW DBAO-STORE DBAS-OCCURRENCE-COUNT@ . S-GEN . CR"])
    assert rows == [[0, IO, 0, 1]]
    _advance(clocked, 1000)
    rows = run(clocked, ["SV DBSVC-TICK . SV DBSVC-STATUS@ . "
                         "SOW DBAO-STORE DBAS-OCCURRENCE-COUNT@ . S-GEN . CR"])
    assert rows == [[-1, OK, 1, 2]]


def test_an_agent_run_with_no_broker_needs_review(clocked):
    """Until Desk gives the service a broker, the Agent is unavailable."""

    rtc = clocked.runtime.rtc
    rtc.set_epoch_ms(NOW)
    _advance(clocked, 1000, 0)
    rows = run(clocked, [
        'S-FRESH . SV DBSVC-TICK . S" Read the news" D-TITLE DBREC-ONCE D-RULE DBREC.FREQ ! '
        f"{NOW // 1000 + 5} D-RULE DBREC.START ! D-AGENT S-CREATE . CR",
    ])
    assert rows == [[OK, 0, OK]]
    _advance(clocked, 5000)
    assert run(clocked, ["SV DBSVC-TICK . SV DBSVC-STATUS@ . 1 S-RUN. CR"]) == [
        [-1, OK, ENDED, DUE, O_BLOCKED, R_AGENT_UNAVAILABLE]]
    output = clocked.run(["SV DBSVC-NOTICE TYPE CR"], 10_000_000).decode()
    assert output.strip() == "Needs review: Read the news"
    assert run(clocked, ["SV DBSVC-NOTICE-SEVERITY . CR"]) == [[3]]

    # A reminder and an Agent run due together.
    rows = run(clocked, [
        f"{NOW // 1000 + 10} D-RULE DBREC.START ! 2 KEY1 K! S-CREATE . "
        "DBAS-ACTION-REMINDER DR DBAO-D.ACTION ! 0 0 DR DBAO-D.OPERANDS SACT-D! "
        'S" Water the plants" D-TITLE 3 KEY1 K! S-CREATE . CR',
    ])
    assert rows == [[OK, OK]]
    _advance(clocked, 5000)
    assert run(clocked, ["SV DBSVC-TICK . CR"]) == [[-1]]
    output = clocked.run(["SV DBSVC-NOTICE TYPE CR"], 10_000_000).decode()
    assert output.strip() in ("Automations: Read the news and 1 more",
                              "Automations: Water the plants and 1 more")
    # Several at once say no more than that they came due.
    assert run(clocked, ["SV DBSVC-NOTICE-SEVERITY . CR"]) == [[0]]

    # Then two reminders due together, and no Agent run.
    rows = run(clocked, [
        f"{NOW // 1000 + 15} D-RULE DBREC.START ! 4 KEY1 K! S-CREATE . "
        "5 KEY1 K! S-CREATE . CR",
    ])
    assert rows == [[OK, OK]]
    _advance(clocked, 5000)
    assert run(clocked, ["SV DBSVC-TICK . CR"]) == [[-1]]
    output = clocked.run(["SV DBSVC-NOTICE TYPE CR"], 10_000_000).decode()
    assert output.strip() == "Reminders: Water the plants and 1 more"



def test_a_schedule_named_for_desk(forth):
    rows = run(forth, [
        # A schedule Daybook has, one it does not, and no service.
        f"S-FRESH . KEY1 DR {NOW} RID1 SOW DBAO-CREATE . "
        "RID1 SV DBSVC-LABEL S\" Water the plants\" COMPARE . "
        "RID2 32 0 FILL RID2 SV DBSVC-LABEL . . RID1 0 DBSVC-LABEL . . CR",
    ])
    assert rows == [[OK, OK, 0, 0, 0, 0, 0]]
