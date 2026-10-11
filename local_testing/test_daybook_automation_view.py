#!/usr/bin/env python3
"""daybook/automation-view.f: the rows Daybook shows for its automations.

A service runs over a RAM filesystem on the simulator's clock, set from the
host.  The checks build the view from reminders in every state and read its
sections, order, titles, details and keys.  They then work every action,
including refusals for a heading, a row out of range, and rows older than
the store, and check the notes for a missing service, an unset clock and a
blocked store.
"""

from __future__ import annotations

import pytest

from native_forth import NativeForth
from test_daybook_automation_owner import NOW, OK, local, ms
from test_daybook_automation_store import RAM_VFS


CHANGED, NONE, NOMEM, WHEN, REPEAT = range(40, 45)

PRELUDE = RAM_VFS + r"""
CREATE SV-RAW DBSVC-SIZE 7 + ALLOT  SV-RAW 7 + -8 AND CONSTANT SV
CREATE VW-RAW DBAV-SIZE 7 + ALLOT  VW-RAW 7 + -8 AND CONSTANT VW
CREATE DR-RAW DBAO-DRAFT-SIZE 7 + ALLOT  DR-RAW 7 + -8 AND CONSTANT DR
CREATE KEY1 32 ALLOT
CREATE RID1 32 ALLOT
VARIABLE KEYN
: SOW  ( -- owner ) SV DBSVC-OWNER ;
: V-FRESH  ( -- status )
    SV DBSVC-VALID? IF SV DBSVC-CLOSE THEN
    T-OPS-RESET T-PATH T-RM 0 KEYN !
    VW DBAV-SIZE 0 FILL
    TV @ SV DBSVC-OPEN SV VW DBAV-INIT ;
\ Creates a reminder TITLE repeating at FREQ from local START seconds, in
\ UTC, under the next create key.
: V-CREATE  ( start title-a title-u freq -- status )
    DR DBAO-DRAFT-SIZE 0 FILL DBAS-ACTION-REMINDER DR DBAO-D.ACTION !
    DR DBAO-D.RULE DBREC.FREQ !
    DR DBAO-D.TITLE DBAS-TITLE-MAX DBAS-FIELD!
    S" UTC0" DR DBAO-D.ZONE TZ-STRING-MAX DBAS-FIELD!
    1 DR DBAO-D.RULE DBREC.INTERVAL !
    DR DBAO-D.RULE DBREC.START !
    1 KEYN +! KEYN @ KEY1 32 ROT FILL
    KEY1 DR DBSVC-NOW RID1 SOW DBAO-CREATE ;
: V-DAILY  ( start title-a title-u -- status ) DBREC-DAILY V-CREATE ;
: V-ONCE  ( start title-a title-u -- status ) DBREC-ONCE V-CREATE ;
\ Accepts every schedule due at NOW with clock evidence BASIS, as the
\ service does: how many fired, and the first status not OK.
CREATE V-PAGE DBAO-DUE-SIZE 4 * ALLOT
VARIABLE V-NOW  VARIABLE V-BASIS  VARIABLE V-FIRED  VARIABLE V-CURSOR
: V-ACCEPT-PAGE  ( n -- status )
    0 ?DO
        V-PAGE I DBAO-DUE-SIZE * + V-BASIS @ 0 V-NOW @ SOW DBAO-OCC-ACCEPT
        ?DUP IF NIP UNLOOP EXIT THEN
        DROP 1 V-FIRED +!
    LOOP
    0 ;
: V-ACCEPT  ( now basis -- fired status )
    V-BASIS ! V-NOW ! 0 V-FIRED ! 0 V-CURSOR !
    BEGIN
        V-NOW @ 1000 / V-CURSOR @ V-PAGE 4 SOW DBAO-DUE-QUERY
        ?DUP IF NIP NIP V-FIRED @ SWAP EXIT THEN
        V-CURSOR ! ?DUP
    WHILE
        V-ACCEPT-PAGE ?DUP IF V-FIRED @ SWAP EXIT THEN
    REPEAT
    V-FIRED @ 0 ;
\ Each row: its kind, then title | detail.
: V-ROWS  ( -- )
    VW DBAV-COUNT@ 0 ?DO
        I VW DBAV-ROW DROP .
        I VW DBAV-TITLE TYPE ."  | " I VW DBAV-DETAIL TYPE CR
    LOOP ;
: V-KEYS  ( -- ) VW DBAV-COUNT@ 0 ?DO I VW DBAV-KEY . LOOP CR ;
\ The row whose title is TITLE, or -1.
: V-FIND  ( title-a title-u -- index )
    VW DBAV-COUNT@ 0 ?DO
        I VW DBAV-ROW DROP DBAV-HEADING <> IF
            2DUP I VW DBAV-TITLE COMPARE 0= IF 2DROP I UNLOOP EXIT THEN
        THEN
    LOOP
    2DROP -1 ;
\ The first row of kind KIND whose title is TITLE.
: V-FIND-KIND  ( title-a title-u kind -- index )
    VW DBAV-COUNT@ 0 ?DO
        I VW DBAV-ROW DROP OVER = IF
            2 PICK 2 PICK I VW DBAV-TITLE COMPARE 0= IF
                DROP 2DROP I UNLOOP EXIT
            THEN
        THEN
    LOOP
    DROP 2DROP -1 ;
"""

SUITE = NativeForth(("tui/applets/daybook/automation-view.f",),
                    prelude=tuple(PRELUDE.strip().splitlines()))


def run_text(machine, lines: list[str], max_steps: int = 8_000_000_000) -> list[str]:
    output = machine.run(lines, max_steps).decode("utf-8", errors="replace")
    assert "??" not in output, output[-3000:]
    return [line.rstrip() for line in output.replace("\r", "").split("\n")
            if line.strip()]


@pytest.fixture()
def clocked():
    machine = SUITE.shared()
    machine.runtime.rtc.set_epoch_ms(NOW)
    return machine


def _setup(machine) -> list[str]:
    """Reminders in every state, built into the view, on 2026-10-10 at
    12:30 UTC: Delta fired on time and completed; Charlie is paused; Echo
    is archived; Alpha and Bravo are active."""

    lines = run_text(machine, [
        "V-FRESH .",
        f'{local(2026, 10, 11, 10)} S" Alpha" V-DAILY .',
        f'{local(2026, 10, 11, 8)} S" Bravo" V-DAILY .',
        f'{local(2026, 10, 11, 7)} S" Charlie" V-DAILY .',
        f'{local(2026, 10, 10, 12, 30)} S" Delta" V-ONCE .',
        f'{local(2026, 10, 11, 6)} S" Echo" V-DAILY .',
        "CR",
    ])
    assert lines == ["0 0 0 0 0 0"], lines
    return lines


def test_sections_order_and_text(clocked):
    _setup(clocked)
    clocked.runtime.rtc.set_epoch_ms(ms(2026, 10, 10, 12, 30))
    lines = run_text(clocked, [
        # Pause Charlie and archive Echo through the owner, then fire Delta.
        'S" Charlie" VW DBAV-REBUILD DROP V-FIND VW DBAV-PAUSE . '
        'VW DBAV-REBUILD DROP S" Echo" V-FIND VW DBAV-ARCHIVE . CR',
        f"{ms(2026, 10, 10, 12, 30)} DBAS-CONTINUOUS V-ACCEPT . . CR",
        "VW DBAV-STALE? . VW DBAV-REBUILD . VW DBAV-STALE? . CR",
        "V-ROWS",
    ])
    assert lines == [
        "0 0",
        "0 1",
        "-1 0 0",
        "0 NEEDS REVIEW |",
        "2 Delta | fired 2026-10-10 12:30",
        "0 ACTIVE |",
        "1 Bravo | next 2026-10-11 08:00",
        "1 Alpha | next 2026-10-11 10:00",
        "0 PAUSED |",
        "1 Charlie | paused",
        "0 COMPLETED |",
        "1 Delta | done",
    ]
    lines = run_text(clocked, [
        "-1 VW DBAV-ARCHIVED! VW DBAV-STALE? . VW DBAV-REBUILD . CR",
        "V-ROWS",
    ])
    assert lines[0] == "-1 0"
    assert lines[-2:] == ["0 ARCHIVED |", "1 Echo | archived"]


def test_keys_are_unique_and_survive_rebuilds(clocked):
    _setup(clocked)
    lines = run_text(clocked, [
        "VW DBAV-REBUILD . V-KEYS",
        'S" Alpha" V-FIND VW DBAV-KEY . S" Alpha" V-FIND VW DBAV-PAUSE . '
        'VW DBAV-REBUILD . S" Alpha" V-FIND VW DBAV-KEY . CR',
    ])
    keys = [int(token) for token in lines[0].split()[1:]]
    assert len(keys) == len(set(keys)) and all(keys), keys
    before, paused, rebuilt, after = lines[1].split()[:4]
    assert (paused, rebuilt) == ("0", "0") and before == after


def test_actions_and_their_refusals(clocked):
    _setup(clocked)
    clocked.runtime.rtc.set_epoch_ms(ms(2026, 10, 10, 12, 30))
    lines = run_text(clocked, [
        f"{ms(2026, 10, 10, 12, 30)} DBAS-CONTINUOUS V-ACCEPT 2DROP "
        "VW DBAV-REBUILD DROP",
        # A heading, a row past the end, and a reminder row for review.
        "0 VW DBAV-PAUSE . 99 VW DBAV-PAUSE . -1 VW DBAV-REVIEW . "
        'S" Alpha" V-FIND VW DBAV-REVIEW . CR',
        # Review the firing; the section goes.
        'S" Delta" DBAV-FIRING V-FIND-KIND VW DBAV-REVIEW . VW DBAV-REBUILD . '
        "0 VW DBAV-TITLE TYPE CR",
        # Rows older than the store do nothing.
        'S" Bravo" V-FIND DUP VW DBAV-PAUSE . VW DBAV-PAUSE . '
        "VW DBAV-REBUILD DROP CR",
        # Resume, archive, show archived, bring back, delete.
        'S" Bravo" V-FIND VW DBAV-PAUSE . VW DBAV-REBUILD DROP '
        'S" Alpha" V-FIND VW DBAV-ARCHIVE . VW DBAV-REBUILD DROP '
        'S" Alpha" V-FIND . -1 VW DBAV-ARCHIVED! VW DBAV-REBUILD DROP '
        'S" Alpha" V-FIND VW DBAV-ARCHIVE . VW DBAV-REBUILD DROP '
        'S" Charlie" V-FIND VW DBAV-DELETE . VW DBAV-REBUILD DROP '
        'S" Charlie" V-FIND . CR',
        "V-ROWS",
        'S" Bravo" V-FIND VW DBAV-REMINDER? . 0 VW DBAV-REMINDER? . '
        "-1 VW DBAV-REMINDER? . CR",
    ])
    assert lines[0] == f"{NONE} {NONE} {NONE} {NONE}"
    assert lines[1] == "0 0 ACTIVE"
    assert lines[2] == f"0 {CHANGED}"
    assert lines[3] == "0 0 -1 0 0 -1"
    assert lines[4:] == [
        "0 ACTIVE |",
        "1 Echo | next 2026-10-11 06:00",
        "1 Bravo | next 2026-10-11 08:00",
        "1 Alpha | next 2026-10-11 10:00",
        "0 COMPLETED |",
        "1 Delta | done",
        "-1 0 0",
    ]


def test_missed_firings_read_as_missed(clocked):
    _setup(clocked)
    lines = run_text(clocked, [
        f"{ms(2026, 10, 14, 11)} DBAS-JUMP V-ACCEPT . . "
        "VW DBAV-REBUILD . CR",
        'S" Bravo" DBAV-FIRING V-FIND-KIND VW DBAV-DETAIL TYPE CR',
        'S" Alpha" DBAV-FIRING V-FIND-KIND VW DBAV-DETAIL TYPE CR',
    ])
    assert lines == [
        "0 5 0",
        "missed 4, last 2026-10-14 08:00",
        "missed 4, last 2026-10-14 10:00",
    ]


def test_notes():
    machine = SUITE.shared()
    lines = run_text(machine, [
        "VW DBAV-SIZE 0 FILL 0 VW DBAV-INIT VW DBAV-NOTE TYPE CR",
        "VW DBAV-REBUILD . VW DBAV-COUNT@ . VW DBAV-STALE? . CR",
        # A set clock is unknown until the service looks; then unset.
        "V-FRESH . VW DBAV-NOTE NIP . SV DBSVC-TICK DROP VW DBAV-NOTE TYPE CR",
    ])
    assert lines == [
        "Automations run inside Desk",
        "0 0 0",
        "0 0 The clock is not set; automations wait",
    ]
    lines = run_text(machine, [
        'SV DBSVC-CLOSE T-PATH T-RM TBUF 80 65 FILL 80 TLEN ! T-PUT '
        "TV @ SV DBSVC-OPEN . VW DBAV-NOTE TYPE CR",
        "VW DBAV-REBUILD . VW DBAV-COUNT@ . CR",
    ])
    assert lines == [
        "4 Automations unavailable: the file is damaged",
        "0 0",
    ]


TITLE, ZONE, NEVER = 11, 12, 14
ONCE, DAILY, WEEKLY, MONTHLY, YEARLY = 0, 1, 2, 3, 4


def _when(machine, text: str) -> list[int]:
    lines = run_text(machine, [
        f'S" {text}" VW DBAV-WHEN! . VW _DBAV.DAY @ . VW _DBAV.MINUTE @ . CR',
    ])
    return [int(token) for token in lines[0].split()]


def test_when_and_title(clocked):
    run_text(clocked, ["V-FRESH DROP VW DBAV-BEGIN . CR"])
    assert _when(clocked, "09:30 Water") == [OK, -1, 570]
    assert run_text(clocked, ["VW _DBAV.DRAFT DBAO-D.TITLE DBAS-FIELD$ TYPE CR"]) == [
        "Water"]
    assert _when(clocked, "2026-10-12 07:05 Call home") == [
        OK, local(2026, 10, 12), 425]
    assert run_text(clocked, ["VW _DBAV.DRAFT DBAO-D.TITLE DBAS-FIELD$ TYPE CR"]) == [
        "Call home"]
    for text in ("9:30 Water", "24:00 Late", "09:60 Late", "09:30",
                 "09:30Water", "2026-02-30 09:00 Never"):
        assert _when(clocked, text)[0] == WHEN, text
    assert _when(clocked, "09:30 " + "x" * 121)[0] == TITLE


def test_repeat_words(clocked):
    run_text(clocked, ["V-FRESH DROP VW DBAV-BEGIN DROP"])
    rule = "VW _DBAV.DRAFT DBAO-D.RULE"
    cases = {"": (ONCE, 0), "once": (ONCE, 0), "Daily": (DAILY, 0),
             "WEEKDAYS": (WEEKLY, 62), "weekly": (WEEKLY, 0),
             "monthly": (MONTHLY, 0), "yearly": (YEARLY, 0)}
    for word, (freq, weekdays) in cases.items():
        lines = run_text(clocked, [
            f'S" {word}" VW DBAV-REPEAT! . {rule} DBREC.FREQ @ . '
            f"{rule} DBREC.WEEKDAYS @ . {rule} DBREC.INTERVAL @ . CR",
        ])
        assert lines == [f"0 {freq} {weekdays} 1"], word
    assert run_text(clocked, ['S" fortnightly" VW DBAV-REPEAT! . CR']) == [
        str(REPEAT)]


def _create(machine, when: str, repeat: str, zone: str) -> list[str]:
    return run_text(machine, [
        f'VW DBAV-BEGIN DROP S" {when}" VW DBAV-WHEN! . '
        f'S" {repeat}" VW DBAV-REPEAT! . S" {zone}" VW DBAV-CREATE . '
        "VW _DBAV.RID SOW DBAO-FIND ?DUP IF DBAS-S.NEXT-UTC @ . "
        "ELSE 0 . THEN CR",
    ])


def test_create_places_the_next_such_time(clocked):
    """At 12:00 UTC, 11:00 is tomorrow and 13:00 today; a date in the past
    is refused; a zone moves the instant; the default zone applies to an
    empty answer."""

    from test_daybook_automation_owner import new_york, utc

    run_text(clocked, ["V-FRESH DROP"])
    assert _create(clocked, "11:00 Early", "", "") == [
        f"0 0 0 {utc(2026, 10, 11, 11)}"]
    assert _create(clocked, "13:00 Later", "daily", "") == [
        f"0 0 0 {utc(2026, 10, 10, 13)}"]
    assert _create(clocked, "2026-10-09 09:00 Past", "once", "")[0].split()[:3] == [
        "0", "0", str(NEVER)]
    assert _create(clocked, "09:00 New York", "", "EST5EDT,M3.2.0,M11.1.0") == [
        f"0 0 0 {new_york(2026, 10, 10, 9)}"]
    assert _create(clocked, "09:00 Mars", "", "Mars")[0].split()[:3] == [
        "0", "0", str(ZONE)]
    lines = run_text(clocked, [
        'S" CET-1CEST,M3.5.0,M10.5.0/3" VW DBAV-DEFAULT-ZONE! . '
        "VW DBAV-DEFAULT-ZONE$ TYPE CR",
    ])
    assert lines == ["0 CET-1CEST,M3.5.0,M10.5.0/3"]
    # 15:00 in Paris on 10 October is 13:00 UTC.
    assert _create(clocked, "15:00 Paris", "", "") == [
        f"0 0 0 {utc(2026, 10, 10, 13)}"]


def test_a_create_submitted_twice_makes_one_reminder(clocked):
    lines = run_text(clocked, [
        'V-FRESH DROP VW DBAV-BEGIN . S" 13:00 Once only" VW DBAV-WHEN! . '
        'S" daily" VW DBAV-REPEAT! . S" " VW DBAV-CREATE . '
        'S" " VW DBAV-CREATE . SOW DBAO-STORE DBAS-SCHEDULE-COUNT@ . '
        "VW DBAV-BEGIN . VW _DBAV.KEY 32 TBUF 32 MOVE VW DBAV-BEGIN . "
        "VW _DBAV.KEY 32 TBUF 32 COMPARE 0<> . CR",
    ])
    assert lines == ["0 0 0 0 0 1 0 0 -1"]
