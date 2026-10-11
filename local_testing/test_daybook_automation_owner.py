#!/usr/bin/env python3
"""daybook/automation-owner.f: reminder operations and firing.

The suite drives the owner over a RAM filesystem with explicit clock
values, so every operation sees exactly the time a check gives it.  It
covers creating with a retry key, every edit and its refusals, firing on
time, catching up after a jump or a restart, a clock that moves back,
series that end, review and retention, and failed commits.  Instants in
zones with daylight time come from zoneinfo.
"""

from __future__ import annotations

import calendar
from datetime import datetime, timezone
from zoneinfo import ZoneInfo

import pytest

from native_forth import NativeForth
from test_daybook_automation_store import RAM_VFS


OK, INVALID, NOMEM, IO, BLOCKED, STATE, ENTROPY = range(7)
CLOCK, NOT_FOUND, CONFLICT, DELETED, TITLE, ZONE, RULE, NEVER = range(7, 15)
ENABLED, PAUSED, COMPLETED, TOMBSTONE = 1, 2, 3, 4
ON_TIME, MISSED = 1, 2
DUE, REVIEWED = 1, 2
CONTINUOUS, ACTIVATION, JUMP = 1, 2, 3
ONCE, DAILY, WEEKLY = 0, 1, 2
END_NEVER, END_UNTIL, END_COUNT = 0, 1, 2


def utc(*fields: int) -> int:
    """UTC seconds for a date and time."""

    return calendar.timegm(datetime(*fields, tzinfo=timezone.utc).timetuple())


def ms(*fields: int) -> int:
    return utc(*fields) * 1000


def local(*fields: int) -> int:
    """Local seconds: a local date and time encoded as if it were UTC."""

    return utc(*fields)


def new_york(*fields: int) -> int:
    """UTC seconds for a New York local time that occurs once."""

    moment = datetime(*fields, tzinfo=ZoneInfo("America/New_York"))
    return int(moment.timestamp())


NOW = ms(2026, 10, 10, 12)

PRELUDE = RAM_VFS + r"""
CREATE OW-RAW DBAO-SIZE 7 + ALLOT  OW-RAW 7 + -8 AND CONSTANT OW
CREATE DR-RAW DBAO-DRAFT-SIZE 7 + ALLOT  DR-RAW 7 + -8 AND CONSTANT DR
CREATE KEY1 32 ALLOT
CREATE RID1 32 ALLOT
CREATE RID2 32 ALLOT

: K!  ( n key -- ) 32 ROT FILL ;
: O-WIPE  ( -- )
    T-PATH T-RM
    OW DBAO-STORE _DBAS.REPL VREPL-STAGE$ T-RM
    OW DBAO-STORE _DBAS.REPL VREPL-BACKUP$ T-RM
    OW DBAO-STORE _DBAS.REPL VREPL-MARKER$ T-RM ;
: O-INIT  ( -- ) OW DBAO-SIZE 0 FILL TV @ T-PATH OW DBAO-INIT DROP ;
\ An open owner over no file, and the base draft: a daily reminder at
\ 09:00 UTC from 2026-10-11, created as key 1.
: O-FRESH  ( -- )
    OW DBAO-VALID? IF OW DBAO-CLOSE DROP THEN
    T-OPS-RESET O-INIT O-WIPE OW DBAO-OPEN DROP
    DR DBAO-DRAFT-SIZE 0 FILL
    DBREC-DAILY DR DBAO-D.RULE DBREC.FREQ !
    1 DR DBAO-D.RULE DBREC.INTERVAL !
    2026 10 11 DT-YMD>EPOCH-S DROP 32400 + DR DBAO-D.RULE DBREC.START !
    S" Water the plants" DR DBAO-D.TITLE DBAS-TITLE-MAX DBAS-FIELD!
    S" UTC0" DR DBAO-D.ZONE TZ-STRING-MAX DBAS-FIELD!
    1 KEY1 K! ;
\ A cold start over the same disk.
: O-REOPEN  ( -- status ) OW DBAO-CLOSE DROP O-INIT OW DBAO-OPEN ;
: D-TITLE  ( a u -- ) DR DBAO-D.TITLE DBAS-TITLE-MAX DBAS-FIELD! ;
: D-ZONE  ( a u -- ) DR DBAO-D.ZONE TZ-STRING-MAX DBAS-FIELD! ;
: D-RULE  ( -- rule ) DR DBAO-D.RULE ;
\ Creates the draft as key 1 into RID1.
: CREATE1  ( now -- status ) KEY1 DR ROT RID1 OW DBAO-CREATE ;
: S1  ( -- schedule ) RID1 OW DBAO-FIND ;
: S2  ( -- schedule ) RID2 OW DBAO-FIND ;
: REV1  ( -- revision ) S1 DBAS-S.REVISION @ ;
: GEN  ( -- n ) OW DBAO-STORE DBAS-GENERATION@ ;
: ITEMS  ( -- n ) OW DBAO-STORE DBAS-OCCURRENCE-COUNT@ ;
: ITEM  ( id -- item )
    OW DBAO-STORE DBAS-FIND-OCCURRENCE DROP OW DBAO-STORE DBAS-OCCURRENCE ;
\ State, revision, next ordinal, next instant, last item and result.
: SCHED.  ( schedule -- )
    DUP DBAS-S.STATE @ . DUP DBAS-S.REVISION @ . DUP DBAS-S.NEXT @ .
    DUP DBAS-S.NEXT-UTC @ . DUP DBAS-S.LAST @ . DBAS-S.RESULT @ . ;
\ First and last ordinals, count, kind, basis and state.
: ITEM.  ( id -- )
    ITEM DUP DBAS-O.FIRST @ . DUP DBAS-O.LAST @ . DUP DBAS-O.COUNT @ .
    DUP DBAS-O.KIND @ . DUP DBAS-O.BASIS @ . DBAS-O.STATE @ . ;
: ACCEPT.  ( now basis -- ) OW DBAO-ACCEPT . . ;
"""

SUITE = NativeForth(("tui/applets/daybook/automation-owner.f",),
                    prelude=tuple(PRELUDE.strip().splitlines()))


@pytest.fixture(scope="module")
def forth():
    return SUITE.shared()


def run(forth, lines: list[str], max_steps: int = 8_000_000_000) -> list[list[int]]:
    output = forth.run(lines, max_steps).decode("latin-1")
    assert "??" not in output, output[-3000:]
    return [[int(token) for token in line.split()]
            for line in output.replace("\r", "").split("\n") if line.strip()]


def test_create_and_its_retry_key(forth):
    rows = run(forth, [
        f"O-FRESH {NOW} CREATE1 . RID1 RID-ZERO? . GEN . CR",
        "S1 SCHED. S1 DBAS-S.SERIAL @ . S1 DBAS-S.CREATED @ . "
        "S1 DBAS-S.MODIFIED @ . CR",
        'S1 DBAS-S.TITLE DBAS-FIELD$ S" Water the plants" COMPARE . '
        'S1 DBAS-S.ZONE DBAS-FIELD$ S" UTC0" COMPARE . CR',
        # The same key and draft again: the reminder it made, no write.
        f"KEY1 DR {NOW + 5000} RID2 OW DBAO-CREATE . RID1 RID2 RID= . GEN . "
        "OW DBAO-STORE DBAS-SCHEDULE-COUNT@ . CR",
        # The same key with another draft.
        f'S" Feed the cat" D-TITLE {NOW} CREATE1 . GEN . CR',
        # Another key, the same draft: another reminder.
        f'S" Water the plants" D-TITLE 2 KEY1 K! KEY1 DR {NOW} RID2 OW DBAO-CREATE . '
        "RID1 RID2 RID= . S2 DBAS-S.SERIAL @ . GEN . CR",
        # After a cold start the first key still answers with its reminder.
        f"O-REOPEN . 1 KEY1 K! KEY1 DR {NOW} RID2 OW DBAO-CREATE . "
        "RID1 RID2 RID= . GEN . CR",
    ])
    assert rows == [
        [OK, 0, 1],
        [ENABLED, 1, 1, utc(2026, 10, 11, 9), 0, 0, 1, NOW, NOW],
        [0, 0],
        [OK, -1, 1, 1],
        [CONFLICT, 1],
        [OK, 0, 2, 2],
        [OK, OK, -1, 2],
    ]


CREATE_REFUSALS = {
    "an unset clock": ("", "-1 CREATE1", CLOCK),
    "a zero key": ("0 KEY1 K!", f"{NOW} CREATE1", INVALID),
    "an empty title": ("0 DR DBAO-D.TITLE !", f"{NOW} CREATE1", TITLE),
    "a title too long": ("DBAS-TITLE-MAX 1+ DR DBAO-D.TITLE !", f"{NOW} CREATE1",
                         TITLE),
    "a control character": ("10 DR DBAO-D.TITLE 9 + C!", f"{NOW} CREATE1", TITLE),
    "invalid UTF-8": ("192 DR DBAO-D.TITLE 9 + C!", f"{NOW} CREATE1", TITLE),
    "an unknown zone": ('S" Mars" D-ZONE', f"{NOW} CREATE1", ZONE),
    "a zone too long": ("TZ-STRING-MAX 1+ DR DBAO-D.ZONE !", f"{NOW} CREATE1", ZONE),
    "an interval of zero": ("0 D-RULE DBREC.INTERVAL !", f"{NOW} CREATE1", RULE),
    "an unknown frequency": ("9 D-RULE DBREC.FREQ !", f"{NOW} CREATE1", RULE),
    "an UNTIL before the start":
        (f"DBREC-END-UNTIL D-RULE DBREC.END ! {utc(2026, 10, 11)} "
         "D-RULE DBREC.LIMIT !", f"{NOW} CREATE1", NEVER),
    "a one-off in the past":
        (f"DBREC-ONCE D-RULE DBREC.FREQ ! {local(2026, 10, 9, 9)} "
         "D-RULE DBREC.START !", f"{NOW} CREATE1", NEVER),
    "a series already over":
        (f"DBREC-END-COUNT D-RULE DBREC.END ! 3 D-RULE DBREC.LIMIT ! "
         f"{local(2026, 1, 1, 9)} D-RULE DBREC.START !", f"{NOW} CREATE1", NEVER),
}


def test_create_refusals(forth):
    lines = [f"O-FRESH {edit} {call} . GEN . OW DBAO-STORE DBAS-SCHEDULE-COUNT@ . "
             "OW DBAO-STORE DBAS-KEY-COUNT@ . CR"
             for edit, call, _ in CREATE_REFUSALS.values()]
    rows = run(forth, lines)
    assert len(rows) == len(CREATE_REFUSALS), rows
    for (name, (_, _, status)), row in zip(CREATE_REFUSALS.items(), rows):
        assert row == [status, 0, 0, 0], name


def test_zones_are_kept_canonical(forth):
    rows = run(forth, [
        f'O-FRESH S" EST+5EDT,M3.2.0/2,M11.1.0/2" D-ZONE {NOW} CREATE1 . '
        'S1 DBAS-S.ZONE DBAS-FIELD$ S" EST5EDT,M3.2.0,M11.1.0" COMPARE . '
        "S1 DBAS-S.NEXT-UTC @ . CR",
        # A retry spelling the zone canonically is the same request.
        f'S" EST5EDT,M3.2.0,M11.1.0" D-ZONE KEY1 DR {NOW} RID2 OW DBAO-CREATE . '
        "RID1 RID2 RID= . CR",
        'S" CET-1CEST,M3.5.0,M10.5.0/3" OW DBAO-DEFAULT-ZONE! . '
        'OW DBAO-STORE DBAS-HEADER DBAS-H.ZONE DBAS-FIELD$ '
        'S" CET-1CEST,M3.5.0,M10.5.0/3" COMPARE . '
        'S" nowhere" OW DBAO-DEFAULT-ZONE! . GEN . CR',
        "O-REOPEN . OW DBAO-STORE DBAS-HEADER DBAS-H.ZONE DBAS-FIELD$ "
        'S" CET-1CEST,M3.5.0,M10.5.0/3" COMPARE . CR',
    ])
    assert rows == [
        [OK, 0, new_york(2026, 10, 11, 9)],
        [OK, -1],
        [OK, 0, ZONE, 2],
        [OK, 0],
    ]


def test_a_start_in_the_past_fires_from_now(forth):
    """Nothing before NOW fires; an occurrence at NOW itself is next."""

    start = local(2026, 1, 1, 9)
    rows = run(forth, [
        f"O-FRESH {start} D-RULE DBREC.START ! {NOW} CREATE1 . "
        "S1 DBAS-S.NEXT @ . S1 DBAS-S.NEXT-UTC @ . CR",
        f"O-FRESH {start} D-RULE DBREC.START ! {ms(2026, 10, 10, 9)} CREATE1 . "
        "S1 DBAS-S.NEXT @ . S1 DBAS-S.NEXT-UTC @ . CR",
    ])
    assert rows == [
        [OK, 284, utc(2026, 10, 11, 9)],
        [OK, 283, utc(2026, 10, 10, 9)],
    ]


def test_edits_name_the_revision_they_change(forth):
    later = ms(2026, 10, 15, 12)
    much_later = ms(2026, 10, 20, 12)
    rows = run(forth, [
        f"O-FRESH {NOW} CREATE1 .",
        f"RID1 2 {NOW} OW DBAO-PAUSE . RID1 1 {NOW} OW DBAO-PAUSE . "
        f"RID1 2 {NOW} OW DBAO-PAUSE . S1 SCHED. CR",
        # Resuming skips what fell during the pause.
        f"RID1 2 -1 OW DBAO-RESUME . RID1 2 {later} OW DBAO-RESUME . S1 SCHED. "
        "S1 DBAS-S.MODIFIED @ . CR",
        # An archived reminder is not due.
        f"RID1 3 -1 OW DBAO-ARCHIVE . RID1 4 {later} OW DBAO-ARCHIVE . "
        "S1 DBAS-S.ARCHIVED @ . OW DBAO-DUE . . S1 DBAS-S.MODIFIED @ . CR",
        f"RID1 4 -1 OW DBAO-UNARCHIVE . RID1 4 {much_later} OW DBAO-UNARCHIVE . "
        "S1 DBAS-S.ARCHIVED @ . S1 SCHED. OW DBAO-DUE . . CR",
        # A replace places the new rule from NOW.
        f'S" Feed the cat" D-TITLE 2 D-RULE DBREC.INTERVAL ! '
        f"RID1 4 DR {much_later} OW DBAO-REPLACE . "
        f"RID1 5 DR -1 OW DBAO-REPLACE . RID1 5 DR {much_later} OW DBAO-REPLACE . "
        'S1 SCHED. S1 DBAS-S.TITLE DBAS-FIELD$ S" Feed the cat" COMPARE . CR',
        f"RID1 5 {much_later} OW DBAO-DELETE . RID1 6 {much_later} OW DBAO-DELETE . "
        "S1 DBAS-S.STATE @ . S1 DBAS-S.REVISION @ . S1 DBAS-S.TITLE @ . CR",
        f"RID1 7 {much_later} OW DBAO-PAUSE . RID1 7 DR {much_later} OW DBAO-REPLACE . "
        f"99 RID2 K! RID2 1 {much_later} OW DBAO-PAUSE . GEN . CR",
        "O-REOPEN . S1 DBAS-S.STATE @ . S1 DBAS-S.REVISION @ . CR",
    ])
    assert rows == [
        [OK, CONFLICT, OK, STATE, PAUSED, 2, 1, utc(2026, 10, 11, 9), 0, 0],
        [CLOCK, OK, ENABLED, 3, 6, utc(2026, 10, 16, 9), 0, 0, later],
        [OK, STATE, 1, 0, 0, later],
        [CLOCK, OK, 0, ENABLED, 5, 11, utc(2026, 10, 21, 9), 0, 0, -1,
         utc(2026, 10, 21, 9)],
        [CONFLICT, CLOCK, OK, ENABLED, 6, 6, utc(2026, 10, 21, 9), 0, 0, 0],
        [CONFLICT, OK, TOMBSTONE, 7, 0],
        [DELETED, DELETED, NOT_FOUND, 7],
        [OK, TOMBSTONE, 7],
    ]


def test_firing_catching_up_and_review(forth):
    first = ms(2026, 10, 11, 9)
    rows = run(forth, [
        f"O-FRESH {NOW} CREATE1 . OW DBAO-DUE . . CR",
        # Not yet; then on time; then nothing again.
        f"{first - 1000} DBAS-CONTINUOUS ACCEPT. GEN . "
        f"{first} DBAS-CONTINUOUS ACCEPT. GEN . OW DBAO-LAST-FIRED@ . CR",
        "1 ITEM. 1 ITEM DBAS-O.ACCEPTED @ . S1 SCHED. CR",
        f"{first + 30000} DBAS-CONTINUOUS ACCEPT. GEN . CR",
        # The clock moves back an hour: nothing fires twice.
        f"{first - 3600000} DBAS-CONTINUOUS ACCEPT. GEN . CR",
        # A jump three days on merges three missed occurrences into the
        # item still awaiting review.
        f"{ms(2026, 10, 14, 10)} DBAS-JUMP ACCEPT. ITEMS . 1 ITEM. S1 SCHED. CR",
        f"1 3 {NOW} OW DBAO-REVIEW . 1 4 {ms(2026, 10, 14, 11)} OW DBAO-REVIEW . "
        f"1 4 {NOW} OW DBAO-REVIEW . 9 1 {NOW} OW DBAO-REVIEW . "
        "1 ITEM DBAS-O.STATE @ . 1 ITEM DBAS-O.REVIEWED @ . CR",
        # A reviewed item takes no more firings.
        f"{ms(2026, 10, 15, 9)} DBAS-CONTINUOUS ACCEPT. ITEMS . 2 ITEM. CR",
        # A restart catches up: missed even for one occurrence.
        f"O-REOPEN . {ms(2026, 10, 16, 9, 0, 5)} DBAS-ACTIVATION ACCEPT. 2 ITEM. "
        "S1 SCHED. CR",
    ])
    assert rows == [
        [OK, -1, utc(2026, 10, 11, 9)],
        [OK, 0, 1, OK, 1, 2, 1],
        [1, 1, 1, ON_TIME, CONTINUOUS, DUE, first,
         ENABLED, 1, 2, utc(2026, 10, 12, 9), 1, ON_TIME],
        [OK, 0, 2],
        [OK, 0, 2],
        [OK, 1, 1, 1, 4, 4, MISSED, JUMP, DUE,
         ENABLED, 1, 5, utc(2026, 10, 15, 9), 1, MISSED],
        [CONFLICT, OK, STATE, NOT_FOUND, REVIEWED, ms(2026, 10, 14, 11)],
        [OK, 1, 2, 5, 5, 1, ON_TIME, CONTINUOUS, DUE],
        [OK, OK, 1, 5, 6, 2, MISSED, ACTIVATION, DUE,
         ENABLED, 1, 7, utc(2026, 10, 17, 9), 2, MISSED],
    ]


def test_series_that_end(forth):
    rows = run(forth, [
        # A count of three caught up in one firing, then complete.
        f"O-FRESH DBREC-END-COUNT D-RULE DBREC.END ! 3 D-RULE DBREC.LIMIT ! "
        f"{NOW} CREATE1 . {ms(2026, 10, 20)} DBAS-JUMP ACCEPT. 1 ITEM. "
        "S1 SCHED. OW DBAO-DUE . . CR",
        # UNTIL the second occurrence.
        f"O-FRESH DBREC-END-UNTIL D-RULE DBREC.END ! {utc(2026, 10, 12, 9)} "
        f"D-RULE DBREC.LIMIT ! {NOW} CREATE1 . {ms(2026, 10, 20)} DBAS-JUMP "
        "ACCEPT. 1 ITEM. S1 SCHED. CR",
        # A one-off on time.
        f"O-FRESH DBREC-ONCE D-RULE DBREC.FREQ ! {NOW} CREATE1 . "
        f"{ms(2026, 10, 11, 9)} DBAS-CONTINUOUS ACCEPT. 1 ITEM. S1 SCHED. CR",
        # A completed reminder is given a new rule.
        f"{local(2026, 10, 12, 9)} D-RULE DBREC.START ! "
        f"RID1 1 DR {ms(2026, 10, 11, 10)} OW DBAO-REPLACE . S1 SCHED. CR",
    ])
    assert rows == [
        [OK, OK, 1, 1, 3, 3, MISSED, JUMP, DUE, COMPLETED, 1, 0, 0, 1, MISSED, 0, 0],
        [OK, OK, 1, 1, 2, 2, MISSED, JUMP, DUE, COMPLETED, 1, 0, 0, 1, MISSED],
        [OK, OK, 1, 1, 1, 1, ON_TIME, CONTINUOUS, DUE,
         COMPLETED, 1, 0, 0, 1, ON_TIME],
        [OK, ENABLED, 2, 1, utc(2026, 10, 12, 9), 1, ON_TIME],
    ]


def test_paused_and_archived_reminders_do_not_fire(forth):
    rows = run(forth, [
        f"O-FRESH {NOW} CREATE1 . RID1 1 {NOW} OW DBAO-PAUSE . "
        f"{ms(2026, 10, 13, 12)} DBAS-CONTINUOUS ACCEPT. OW DBAO-DUE . . CR",
        f"RID1 2 {ms(2026, 10, 13, 12)} OW DBAO-RESUME . "
        f"{ms(2026, 10, 13, 12, 0, 1)} DBAS-CONTINUOUS ACCEPT. "
        f"{ms(2026, 10, 14, 9)} DBAS-CONTINUOUS ACCEPT. 1 ITEM. CR",
        f"RID1 3 {NOW} OW DBAO-ARCHIVE . {ms(2026, 10, 20)} DBAS-JUMP ACCEPT. "
        "ITEMS . CR",
    ])
    assert rows == [
        [OK, OK, OK, 0, 0, 0],
        [OK, OK, 0, OK, 1, 4, 4, 1, ON_TIME, CONTINUOUS, DUE],
        [OK, OK, 0, 1],
    ]


def test_replace_and_delete_with_items_awaiting_review(forth):
    rows = run(forth, [
        # A firing at the old revision is not merged with the new one's.
        f"O-FRESH {NOW} CREATE1 . {ms(2026, 10, 11, 9)} DBAS-CONTINUOUS ACCEPT. "
        f"RID1 1 DR {ms(2026, 10, 11, 10)} OW DBAO-REPLACE . "
        f"{ms(2026, 10, 12, 9)} DBAS-CONTINUOUS ACCEPT. ITEMS . "
        "1 ITEM DBAS-O.REVISION @ . 2 ITEM DBAS-O.REVISION @ . 2 ITEM. CR",
        f"RID1 2 {NOW} OW DBAO-DELETE . ITEMS . O-REOPEN . ITEMS . CR",
    ])
    assert rows == [
        [OK, OK, 1, OK, OK, 1, 2, 1, 2, 2, 2, 1, ON_TIME, CONTINUOUS, DUE],
        [OK, 0, OK, 0],
    ]


def test_retention_prunes_the_oldest_reviewed_items(forth):
    lines = [
        f"O-FRESH {NOW} CREATE1 . 2 OW DBAO-STORE DBAS-HEADER DBAS-H.RETAIN ! "
        "OW DBAO-STORE DBAS-COMMIT .",
    ]
    for day, item in ((11, 1), (12, 2), (13, 3)):
        lines.append(f"{ms(2026, 10, day, 9)} DBAS-CONTINUOUS ACCEPT. "
                     f"{item} {day - 10} {ms(2026, 10, day, 10)} OW DBAO-REVIEW .")
    lines.append("CR ITEMS . 0 OW DBAO-STORE DBAS-OCCURRENCE @ . "
                 "S1 DBAS-S.PRUNED @ . O-REOPEN . ITEMS . S1 DBAS-S.PRUNED @ . CR")
    rows = run(forth, lines)
    assert rows == [
        [OK, OK, OK, 1, OK, OK, 1, OK, OK, 1, OK],
        [2, 2, 1, OK, 2, 1],
    ]


def test_daylight_time_moves_the_instant_not_the_hour(forth):
    """09:00 in New York is 13:00 UTC before the November change and
    14:00 UTC after it."""

    rows = run(forth, [
        f'O-FRESH S" EST5EDT,M3.2.0,M11.1.0" D-ZONE {local(2026, 10, 31, 9)} '
        f"D-RULE DBREC.START ! {NOW} CREATE1 . S1 DBAS-S.NEXT-UTC @ . "
        f"{new_york(2026, 10, 31, 9) * 1000} DBAS-CONTINUOUS ACCEPT. "
        "S1 DBAS-S.NEXT-UTC @ . 1 ITEM DBAS-O.LAST-UTC @ . CR",
    ])
    assert rows == [[OK, new_york(2026, 10, 31, 9), OK, 1,
                     new_york(2026, 11, 1, 9), new_york(2026, 10, 31, 9)]]
    assert new_york(2026, 11, 1, 9) - new_york(2026, 10, 31, 9) == 25 * 3600


def test_a_failed_commit_changes_nothing(forth):
    rows = run(forth, [
        f"O-FRESH {NOW} CREATE1 . GEN . CR",
        f"1 T-SYNC-N ! RID1 1 {NOW} OW DBAO-PAUSE . S1 SCHED. GEN . "
        f"RID1 1 {NOW} OW DBAO-PAUSE . S1 DBAS-S.STATE @ . CR",
        f"2 KEY1 K! 1 T-SYNC-N ! KEY1 DR {NOW} RID2 OW DBAO-CREATE . "
        "OW DBAO-STORE DBAS-SCHEDULE-COUNT@ . OW DBAO-STORE DBAS-KEY-COUNT@ . "
        f"KEY1 DR {NOW} RID2 OW DBAO-CREATE . OW DBAO-STORE DBAS-KEY-COUNT@ . CR",
        f"RID1 2 {NOW} OW DBAO-RESUME . 1 T-SYNC-N ! "
        f"{ms(2026, 10, 11, 9)} DBAS-CONTINUOUS ACCEPT. ITEMS . S1 DBAS-S.NEXT @ . "
        f"{ms(2026, 10, 11, 9)} DBAS-CONTINUOUS ACCEPT. ITEMS . CR",
    ])
    assert rows == [
        [OK, 1],
        [IO, ENABLED, 1, 1, utc(2026, 10, 11, 9), 0, 0, 1, OK, PAUSED],
        [IO, 1, 1, OK, 2],
        [OK, IO, 0, 0, 1, OK, 2, 2],
    ]


def test_a_blocked_store_refuses_everything(forth):
    rows = run(forth, [
        f"O-FRESH {NOW} CREATE1 . OW DBAO-CLOSE . T-GET TBUF 100 + DUP C@ 1 XOR "
        "SWAP C! T-PUT O-INIT OW DBAO-OPEN . CR",
        f"KEY1 DR {NOW} RID2 OW DBAO-CREATE . RID1 1 {NOW} OW DBAO-PAUSE . "
        f"1 1 {NOW} OW DBAO-REVIEW . "
        'S" UTC0" OW DBAO-DEFAULT-ZONE! . OW DBAO-DUE . . '
        f"{NOW} DBAS-CONTINUOUS ACCEPT. CR",
    ])
    assert rows == [
        [OK, OK, BLOCKED],
        [BLOCKED, BLOCKED, BLOCKED, BLOCKED, 0, 0, BLOCKED, 0],
    ]
