#!/usr/bin/env python3
"""daybook/automation-owner.f: schedule operations, firing and Agent runs.

The suite drives the owner over a RAM filesystem with explicit clock
values, so every operation sees exactly the time a check gives it.  It
covers creating with a retry key, every edit and its refusals, firing on
time, catching up after a jump or a restart, a clock that moves back,
series that end, review and retention, and failed commits.  For Agent
runs it covers operands, approval and what clears it, accepting with a
dispatch key, blocked and missed runs, a run in flight, the broker's
started and finished reports, Run Now, deleting with short records, and
paged reads.  Instants in zones with daylight time come from zoneinfo.
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
ACCEPTED_S, BUSY, REVIEW, MANUAL_S, APPROVAL, OPERANDS, ACTION = range(15, 22)
ENABLED, PAUSED, COMPLETED, TOMBSTONE = 1, 2, 3, 4
REMINDER, AGENT = 1, 2
ON_TIME, MISSED, MANUAL = 1, 2, 3
IN_FLIGHT, DUE, REVIEWED, CLEAR = 0, 1, 2, 3
CONTINUOUS, ACTIVATION, JUMP, USER = 1, 2, 3, 4
ACCEPTED, RUNNING, ENDED = 1, 2, 3
(O_COMPLETED, O_FAILED, O_CANCELLED, O_EXPIRED, O_STOPPED, O_BLOCKED,
 O_INDETERMINATE, O_NOT_STARTED) = range(1, 9)
R_NOT_APPROVED, R_REVOKED, R_CHANGED, R_PRACTICE, R_AGENT_UNAVAILABLE = 1, 2, 3, 4, 5
R_OVERLAP, R_MISSED, R_PROVIDER_ERROR, R_PROVIDER_START = 10, 12, 22, 23
R_INTERRUPTED = 26
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
CREATE RID3 32 ALLOT

: K!  ( n key -- ) 32 ROT FILL ;
\ Accepts every schedule due at NOW, a page at a time, as the service
\ does, with T-STANDING as each Agent run's standing.  Answers how many
\ fired, and stops at the first status that is not OK; T-LAST is the
\ last item made or added to.
VARIABLE T-STANDING
VARIABLE T-LAST
VARIABLE T-NOW
VARIABLE T-BASIS
VARIABLE T-FIRED
VARIABLE T-CURSOR
CREATE T-PAGE DBAO-DUE-SIZE 4 * ALLOT
: T-ACCEPT-PAGE  ( n -- status )
    0 ?DO
        T-PAGE I DBAO-DUE-SIZE * + T-BASIS @ T-STANDING @ T-NOW @ OW
        DBAO-OCC-ACCEPT ?DUP IF NIP UNLOOP EXIT THEN
        T-LAST ! 1 T-FIRED +!
    LOOP
    0 ;
: T-ACCEPT-ALL  ( now basis -- fired status )
    T-BASIS ! T-NOW ! 0 T-FIRED ! 0 T-CURSOR !
    BEGIN
        T-NOW @ 1000 / T-CURSOR @ T-PAGE 4 OW DBAO-DUE-QUERY
        ?DUP IF NIP NIP T-FIRED @ SWAP EXIT THEN
        T-CURSOR ! ?DUP
    WHILE
        T-ACCEPT-PAGE ?DUP IF T-FIRED @ SWAP EXIT THEN
    REPEAT
    T-FIRED @ 0 ;
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
    DBAS-ACTION-REMINDER DR DBAO-D.ACTION !
    SDSP-A-APPROVED T-STANDING ! 0 T-LAST !
    DBREC-DAILY DR DBAO-D.RULE DBREC.FREQ !
    1 DR DBAO-D.RULE DBREC.INTERVAL !
    2026 10 11 DT-YMD>EPOCH-S DROP 32400 + DR DBAO-D.RULE DBREC.START !
    S" Water the plants" DR DBAO-D.TITLE DBAS-TITLE-MAX DBAS-FIELD!
    S" UTC0" DR DBAO-D.ZONE TZ-STRING-MAX DBAS-FIELD!
    1 KEY1 K! ;
\ Reads fail until T-OPS-RESET: a store that tried to commit and reload
\ would block, so a refusal that leaves it ready touched nothing.
: NO-READS  ( -- ) ['] T-FAIL-READ VFS-OP-READ T-OP! ;
: READY.  ( -- ) OW DBAO-STORE DBAS-STATE@ . T-OPS-RESET ;
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
: ACCEPT.  ( now basis -- ) T-ACCEPT-ALL . . ;


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
\ The draft runs the Agent with those operands.
: D-AGENT  ( -- )
    A-OPS DBAS-ACTION-AGENT DR DBAO-D.ACTION ! OPS OPS-U @ DR DBAO-D.OPERANDS SACT-D! ;
\ The draft's operands with another prompt.
: A-PROMPT  ( a u -- )
    AD SACT-D.PROMPT SACT-D!
    AD OPS 1024 SACT-AGENT-ENCODE DROP OPS-U ! OPS OPS-U @ DR DBAO-D.OPERANDS SACT-D! ;
\ Whether RID1's stored operands are those in OPS.
: OPS-SAME.  ( -- )
    RID1 OW DBAO-ACTION DBAS-A.OPERANDS BSLOT$ OPS OPS-U @ COMPARE . ;
\ A response from Desk's broker.
CREATE RS-RAW 263 ALLOT  RS-RAW 7 + -8 AND CONSTANT RS
: R-INIT  ( -- ) 120 RS SDSP-RESPONSE-INIT ;
\ An approval: Practice bytes 4, permission bytes 6 at revision 1.
: R-PERMIT  ( -- )
    R-INIT RS SDSP-P.PRACTICE 32 4 FILL RS SDSP-P.PERMISSION 32 6 FILL
    1 RS SDSP-P.PERMISSION-REVISION ! ;
\ An end: OUTCOME for REASON, with the run whose bytes are B, or none.
: R-END  ( outcome reason b -- )
    R-INIT ROT RS SDSP-P.OUTCOME ! SWAP RS SDSP-P.REASON !
    ?DUP IF RS SDSP-P.RUN 32 ROT FILL THEN ;
CREATE KEYX 32 ALLOT
CREATE KEYY 32 ALLOT
CREATE RUNID 32 ALLOT
CREATE HIST 64 ALLOT
CREATE QRY 96 ALLOT
VARIABLE QC
\ Item ID's summary.
: SUM$  ( id -- a u ) ITEM DBAS-O.SUMMARY BSLOT$ ;
\ Item ID's dispatch key into KEYX.
: KEYX!  ( id -- ) ITEM DBAS-O.KEY KEYX 32 MOVE ;
\ Whether item ID's key is the one its store, schedule and id give.
: KEY-OK.  ( id -- )
    DUP >R OW DBAO-STORE DBAS-HEADER DBAS-H.STORE-ID OVER ITEM DBAS-O.RID R>
    KEYY SDSP-KEY KEYY 32 ROT ITEM DBAS-O.KEY 32 COMPARE 0= . ;
\ Phase, review state, outcome, reason, kind, count, whether it has no
\ run, flags and summary length.
: RUN.  ( id -- )
    ITEM DUP DBAS-O.PHASE @ . DUP DBAS-O.STATE @ . DUP DBAS-O.OUTCOME @ .
    DUP DBAS-O.REASON @ . DUP DBAS-O.KIND @ . DUP DBAS-O.COUNT @ .
    DUP DBAS-O.RUN RID-ZERO? . DUP DBAS-O.FLAGS @ . DBAS-O.SUMMARY 8 + @ . ;
\ Whether RID1 is approved, and its Practice, permission and revision.
: AUTH.  ( -- )
    RID1 OW DBAO-ACTION DUP DBAS-A.AUTHORIZED @ . DUP DBAS-A.PRACTICE C@ .
    DUP DBAS-A.PERMISSION C@ . DBAS-A.PERMISSION-REVISION @ . ;
\ An approved Agent run created at NOW as RID1, with its first run
\ accepted at FIRST as item 1 and that run's key in KEYX.
: A-ACCEPTED  ( now first -- )
    SWAP O-FRESH D-AGENT DUP CREATE1 DROP     ( first now )
    R-PERMIT RID1 1 RS 3 ROLL OW DBAO-AUTHORIZE DROP
    DBAS-CONTINUOUS T-ACCEPT-ALL 2DROP 1 KEYX! ;
\ The same, which the Agent started at FIRST as run 9.
: A-RUNNING  ( now first -- )
    DUP >R A-ACCEPTED 9 RUNID K! KEYX RUNID R> OW DBAO-OCC-STARTED DROP ;
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
    "no action": ("0 DR DBAO-D.ACTION !", f"{NOW} CREATE1", ACTION),
    "an action outside the catalog": ("3 DR DBAO-D.ACTION !", f"{NOW} CREATE1", ACTION),
    "a reminder with operands": ("OPS 8 DR DBAO-D.OPERANDS SACT-D!", f"{NOW} CREATE1",
                                 OPERANDS),
    "an Agent run without operands": ("DBAS-ACTION-AGENT DR DBAO-D.ACTION !",
                                      f"{NOW} CREATE1", OPERANDS),
    "operands that break their rules": ("D-AGENT 0 OPS SACT-O.TIME !",
                                        f"{NOW} CREATE1", OPERANDS),
}


def test_create_refusals(forth):
    """Each refusal comes before any edit, over a store holding one
    schedule made with key 2."""

    lines = [f"O-FRESH 2 KEY1 K! {NOW} CREATE1 DROP 1 KEY1 K! {edit} NO-READS {call} . "
             "READY. GEN . OW DBAO-STORE DBAS-SCHEDULE-COUNT@ . "
             "OW DBAO-STORE DBAS-KEY-COUNT@ . CR"
             for edit, call, _ in CREATE_REFUSALS.values()]
    rows = run(forth, lines)
    assert len(rows) == len(CREATE_REFUSALS), rows
    for (name, (_, _, status)), row in zip(CREATE_REFUSALS.items(), rows):
        assert row == [status, 1, 1, 1, 1], name


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
        f"{first} DBAS-CONTINUOUS ACCEPT. GEN . T-LAST @ . CR",
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


def test_an_agent_schedule_keeps_its_operands(forth):
    rows = run(forth, [
        f"O-FRESH D-AGENT {NOW} CREATE1 . S1 DBAS-S.ACTION @ . "
        "OW DBAO-STORE DBAS-ACTION-COUNT@ . RID1 OW DBAO-ACTION DBAS-A.SCHEMA @ . "
        "OPS-SAME. AUTH. CR",
        # A retry with the same operands finds it; other operands conflict.
        f"KEY1 DR {NOW} RID2 OW DBAO-CREATE . RID1 RID2 RID= . "
        f'S" Summarize the town." A-PROMPT KEY1 DR {NOW} RID2 OW DBAO-CREATE . CR',
        "O-REOPEN . A-OPS OPS-SAME. OW DBAO-STORE DBAS-ACTION-COUNT@ . CR",
        # A replace keeps the schedule's action.
        "DBAS-ACTION-REMINDER DR DBAO-D.ACTION ! 0 0 DR DBAO-D.OPERANDS SACT-D! "
        f"RID1 1 DR {NOW} OW DBAO-REPLACE . REV1 . "
        f"O-FRESH {NOW} CREATE1 . D-AGENT RID1 1 DR {NOW} OW DBAO-REPLACE . "
        "OW DBAO-STORE DBAS-ACTION-COUNT@ . CR",
    ])
    assert rows == [
        [OK, AGENT, 1, 1, 0, 0, 0, 0, 0],
        [OK, -1, CONFLICT],
        [OK, 0, 1],
        [ACTION, 1, OK, ACTION, 0],
    ]


def test_approval_and_what_clears_it(forth):
    rows = run(forth, [
        f"O-FRESH D-AGENT {NOW} CREATE1 . R-PERMIT RID1 1 RS {NOW} OW DBAO-AUTHORIZE . "
        "AUTH. REV1 . GEN . CR",
        # An approval names the revision it saw and a whole permission.
        f"NO-READS RID1 2 RS {NOW} OW DBAO-AUTHORIZE . "
        f"R-PERMIT RS SDSP-P.PRACTICE RID-CLEAR RID1 1 RS {NOW} OW DBAO-AUTHORIZE . "
        f"R-PERMIT 0 RS SDSP-P.PERMISSION-REVISION ! RID1 1 RS {NOW} OW DBAO-AUTHORIZE . "
        f"R-PERMIT RS SDSP-P.PERMISSION RID-CLEAR RID1 1 RS {NOW} OW DBAO-AUTHORIZE . "
        "READY. GEN . CR",
        # A new title keeps it, and so does a cold start.
        f'S" Read the news" D-TITLE RID1 1 DR {NOW} OW DBAO-REPLACE . AUTH. '
        "O-REOPEN . AUTH. CR",
        # A new prompt, rule or zone clears it.
        f'R-PERMIT RID1 2 RS {NOW} OW DBAO-AUTHORIZE . S" Water the lawn." A-PROMPT '
        f"RID1 2 DR {NOW} OW DBAO-REPLACE . AUTH. OPS-SAME. CR",
        f"R-PERMIT RID1 3 RS {NOW} OW DBAO-AUTHORIZE . 2 D-RULE DBREC.INTERVAL ! "
        f"RID1 3 DR {NOW} OW DBAO-REPLACE . AUTH. "
        f'R-PERMIT RID1 4 RS {NOW} OW DBAO-AUTHORIZE . S" EST5EDT,M3.2.0,M11.1.0" D-ZONE '
        f"RID1 4 DR {NOW} OW DBAO-REPLACE . AUTH. CR",
        # A reminder takes none.
        f"O-FRESH {NOW} CREATE1 . R-PERMIT RID1 1 RS {NOW} OW DBAO-AUTHORIZE . CR",
    ])
    assert rows == [
        [OK, OK, 1, 4, 6, 1, 1, 2],
        [CONFLICT, INVALID, INVALID, INVALID, 1, 2],
        [OK, 1, 4, 6, 1, OK, 1, 4, 6, 1],
        [OK, OK, 0, 0, 0, 0, 0],
        [OK, OK, 0, 0, 0, 0, OK, OK, 0, 0, 0, 0],
        [OK, MANUAL_S],
    ]


def test_accept_checks_its_entry(forth):
    first = ms(2026, 10, 11, 9)
    rows = run(forth, [
        f"O-FRESH {NOW} CREATE1 . RID1 T-PAGE RID-COPY 1 T-PAGE DBAO-E.REVISION ! "
        "1 T-PAGE DBAO-E.ORDINAL ! CR",
        # Not yet due; no clock; a basis that is not one.
        f"NO-READS T-PAGE DBAS-CONTINUOUS 0 {first - 1000} OW DBAO-OCC-ACCEPT . . "
        "T-PAGE DBAS-CONTINUOUS 0 -1 OW DBAO-OCC-ACCEPT . . "
        f"T-PAGE 0 0 {first} OW DBAO-OCC-ACCEPT . . "
        f"T-PAGE DBAS-USER 0 {first} OW DBAO-OCC-ACCEPT . . READY. GEN . CR",
        # An ordinal past the next, or a stale revision.
        f"2 T-PAGE DBAO-E.ORDINAL ! T-PAGE DBAS-CONTINUOUS 0 {first} OW DBAO-OCC-ACCEPT . . "
        "1 T-PAGE DBAO-E.ORDINAL ! 2 T-PAGE DBAO-E.REVISION ! "
        f"T-PAGE DBAS-CONTINUOUS 0 {first} OW DBAO-OCC-ACCEPT . . "
        "1 T-PAGE DBAO-E.REVISION ! CR",
        # Accepted once; the same entry again names the item and writes nothing.
        f"T-PAGE DBAS-CONTINUOUS 0 {first} OW DBAO-OCC-ACCEPT . . GEN . "
        f"T-PAGE DBAS-CONTINUOUS 0 {first + 5000} OW DBAO-OCC-ACCEPT . . GEN . CR",
        # Paused, deleted, unknown.
        f"RID1 1 {NOW} OW DBAO-PAUSE . 2 T-PAGE DBAO-E.REVISION ! 2 T-PAGE DBAO-E.ORDINAL ! "
        f"T-PAGE DBAS-CONTINUOUS 0 {first + 86400000} OW DBAO-OCC-ACCEPT . . "
        f"RID1 2 {NOW} OW DBAO-DELETE . 3 T-PAGE DBAO-E.REVISION ! "
        f"T-PAGE DBAS-CONTINUOUS 0 {first + 86400000} OW DBAO-OCC-ACCEPT . . "
        f"9 T-PAGE K! T-PAGE DBAS-CONTINUOUS 0 {first + 86400000} OW DBAO-OCC-ACCEPT . . CR",
    ])
    assert rows == [
        [OK],
        [STATE, 0, CLOCK, 0, INVALID, 0, INVALID, 0, 1, 1],
        [CONFLICT, 0, CONFLICT, 0],
        [OK, 1, 2, ACCEPTED_S, 1, 2],
        [OK, STATE, 0, OK, DELETED, 0, NOT_FOUND, 0],
    ]


def test_an_on_time_run_is_accepted_with_its_dispatch_key(forth):
    first = ms(2026, 10, 11, 9)
    day = 86400000
    rows = run(forth, [
        f"O-FRESH D-AGENT {NOW} CREATE1 . R-PERMIT RID1 1 RS {NOW} OW DBAO-AUTHORIZE . "
        f"{first} DBAS-CONTINUOUS ACCEPT. T-LAST @ . CR",
        "1 RUN. 1 KEY-OK. 1 ITEM DBAS-O.ACCEPTED @ . S1 SCHED. CR",
        # The next day's run finds the first still in flight, and so does the
        # day after's, which joins it.
        f"{first + day} DBAS-CONTINUOUS ACCEPT. 2 RUN. 2 ITEM DBAS-O.ENDED @ . CR",
        f"{first + 2 * day} DBAS-CONTINUOUS ACCEPT. ITEMS . 2 RUN. "
        "2 ITEM DBAS-O.ENDED @ . CR",
        # A block has no key, and no report names it.
        f"9 RUNID K! 0 KEYY K! KEYY RUNID {first} OW DBAO-OCC-STARTED . "
        f"{O_BLOCKED} {R_OVERLAP} 0 R-END KEYY RS {first} OW DBAO-OCC-FINISH . CR",
        "O-REOPEN . 1 RUN. 1 KEY-OK. CR",
        # Once it ends, a block for another reason is an item of its own.
        f"1 KEYX! {O_FAILED} {R_PROVIDER_START} 0 R-END "
        f"KEYX RS {first + 2 * day} OW DBAO-OCC-FINISH . "
        f"{O_FAILED} {R_PROVIDER_ERROR} 0 R-END KEYX RS {first + 2 * day} OW DBAO-OCC-FINISH . "
        f"SDSP-A-NONE T-STANDING ! {first + 3 * day} DBAS-CONTINUOUS ACCEPT. ITEMS . 3 RUN. CR",
    ])
    assert rows == [
        [OK, OK, OK, 1, 1],
        [ACCEPTED, IN_FLIGHT, 0, 0, ON_TIME, 1, -1, 0, 0, -1, first,
         ENABLED, 1, 2, utc(2026, 10, 12, 9), 1, ON_TIME],
        [OK, 1, ENDED, DUE, O_BLOCKED, R_OVERLAP, ON_TIME, 1, -1, 0, 0, first + day],
        [OK, 1, 2, ENDED, DUE, O_BLOCKED, R_OVERLAP, ON_TIME, 2, -1, 0, 0,
         first + 2 * day],
        [NOT_FOUND, NOT_FOUND],
        [OK, ACCEPTED, IN_FLIGHT, 0, 0, ON_TIME, 1, -1, 0, 0, -1],
        [OK, CONFLICT, OK, 1, 3, ENDED, DUE, O_BLOCKED, R_NOT_APPROVED, ON_TIME, 1, -1, 0, 0],
    ]


def test_runs_of_different_schedules_are_independent(forth):
    first = ms(2026, 10, 11, 9)
    rows = run(forth, [
        f"O-FRESH D-AGENT {NOW} CREATE1 . 2 KEY1 K! KEY1 DR {NOW} RID2 OW DBAO-CREATE . "
        f"R-PERMIT RID1 1 RS {NOW} OW DBAO-AUTHORIZE . RID2 1 RS {NOW} OW DBAO-AUTHORIZE . "
        f"{first} DBAS-CONTINUOUS ACCEPT. 1 RUN. 2 RUN. CR",
        "1 KEY-OK. 2 KEY-OK. 1 KEYX! 2 ITEM DBAS-O.KEY 32 KEYX 32 COMPARE 0<> . CR",
    ])
    assert rows == [
        [OK, OK, OK, OK, OK, 2, ACCEPTED, IN_FLIGHT, 0, 0, ON_TIME, 1, -1, 0, 0,
         ACCEPTED, IN_FLIGHT, 0, 0, ON_TIME, 1, -1, 0, 0],
        [-1, -1, -1],
    ]


STANDINGS = {
    "no permission": ("SDSP-A-NONE", R_NOT_APPROVED, 0),
    "a withdrawn permission": ("SDSP-A-WITHDRAWN", R_REVOKED, 0),
    "a changed permission": ("SDSP-A-CHANGED", R_CHANGED, 0),
    "another Practice": ("SDSP-A-PRACTICE", R_PRACTICE, 0),
    "no Agent": ("SDSP-A-UNAVAILABLE", R_AGENT_UNAVAILABLE, 1),
}


def test_a_run_whose_permission_does_not_stand_is_blocked(forth):
    """Desk refusing the permission clears Daybook's approval; an Agent
    that cannot be reached leaves it."""

    first = ms(2026, 10, 11, 9)
    lines = [f"O-FRESH D-AGENT {NOW} CREATE1 . R-PERMIT RID1 1 RS {NOW} OW DBAO-AUTHORIZE . "
             f"{standing} T-STANDING ! {first} DBAS-CONTINUOUS ACCEPT. 1 RUN. "
             "RID1 OW DBAO-ACTION DBAS-A.AUTHORIZED @ . CR"
             for standing, _, _ in STANDINGS.values()]
    # Desk approves, but Daybook holds no approval.
    lines.append(f"O-FRESH D-AGENT {NOW} CREATE1 . {first} DBAS-CONTINUOUS ACCEPT. 1 RUN. CR")
    rows = run(forth, lines)
    for (name, (_, reason, kept)), row in zip(STANDINGS.items(), rows):
        assert row == [OK, OK, OK, 1, ENDED, DUE, O_BLOCKED, reason, ON_TIME, 1, -1, 0, 0,
                       kept], name
    assert rows[-1] == [OK, OK, 1, ENDED, DUE, O_BLOCKED, R_NOT_APPROVED, ON_TIME, 1,
                        -1, 0, 0]


def test_a_missed_run_never_starts(forth):
    rows = run(forth, [
        f"O-FRESH D-AGENT {NOW} CREATE1 . R-PERMIT RID1 1 RS {NOW} OW DBAO-AUTHORIZE . "
        f"{ms(2026, 10, 14, 10)} DBAS-JUMP ACCEPT. 1 RUN. 1 ITEM DBAS-O.BASIS @ . "
        "1 ITEM DBAS-O.KEY RID-ZERO? . AUTH. CR",
        # A restart that catches up one more joins it.
        f"O-REOPEN . {ms(2026, 10, 15, 9, 0, 5)} DBAS-ACTIVATION ACCEPT. ITEMS . 1 RUN. CR",
        # The next on time starts.
        f"{ms(2026, 10, 16, 9)} DBAS-CONTINUOUS ACCEPT. 2 RUN. CR",
    ])
    assert rows == [
        [OK, OK, OK, 1, ENDED, DUE, O_NOT_STARTED, R_MISSED, MISSED, 4, -1, 0, 0, JUMP, -1,
         1, 4, 6, 1],
        [OK, OK, 1, 1, ENDED, DUE, O_NOT_STARTED, R_MISSED, MISSED, 5, -1, 0, 0],
        [OK, 1, ACCEPTED, IN_FLIGHT, 0, 0, ON_TIME, 1, -1, 0, 0],
    ]


def test_the_broker_reports_a_run_started_and_ended(forth):
    first = ms(2026, 10, 11, 9)
    later = first + 60000
    rows = run(forth, [
        f"{NOW} {first} A-ACCEPTED 9 RUNID K! GEN . "
        f"KEYX RUNID {first + 1000} OW DBAO-OCC-STARTED . 1 RUN. "
        "1 ITEM DBAS-O.STARTED @ . 1 ITEM DBAS-O.RUN C@ . GEN . CR",
        # The same report again changes nothing; another run conflicts.
        f"KEYX RUNID {first + 2000} OW DBAO-OCC-STARTED . 8 RUNID K! "
        f"KEYX RUNID {first + 2000} OW DBAO-OCC-STARTED . 7 KEYY K! "
        f"KEYY RUNID {first} OW DBAO-OCC-STARTED . 0 KEYY K! "
        f"KEYY RUNID {first} OW DBAO-OCC-STARTED . 0 RUNID K! "
        f"KEYX RUNID {first} OW DBAO-OCC-STARTED . GEN . "
        "1 ITEM DBAS-O.STARTED @ . CR",
        # It completed: nothing to review.
        f'{O_COMPLETED} 0 9 R-END S" Read 3 items." RS SDSP-SUMMARY! . '
        f"KEYX RS {later} OW DBAO-OCC-FINISH . 1 RUN. 1 ITEM DBAS-O.ENDED @ . "
        '1 SUM$ S" Read 3 items." COMPARE . GEN . CR',
        f"KEYX RS {later + 1000} OW DBAO-OCC-FINISH . GEN . "
        f"{O_FAILED} {R_PROVIDER_ERROR} 9 R-END KEYX RS {later} OW DBAO-OCC-FINISH . "
        f"9 RUNID K! KEYX RUNID {later} OW DBAO-OCC-STARTED . "
        f"8 RUNID K! KEYX RUNID {later} OW DBAO-OCC-STARTED . GEN . CR",
        'O-REOPEN . 1 RUN. 1 SUM$ S" Read 3 items." COMPARE . 1 KEY-OK. CR',
        # The next run is accepted.
        f"{first + 86400000} DBAS-CONTINUOUS ACCEPT. 2 RUN. CR",
    ])
    assert rows == [
        [3, OK, RUNNING, IN_FLIGHT, 0, 0, ON_TIME, 1, 0, 0, 0, first + 1000, 9, 4],
        [OK, CONFLICT, NOT_FOUND, NOT_FOUND, INVALID, 4, first + 1000],
        [0, OK, ENDED, CLEAR, O_COMPLETED, 0, ON_TIME, 1, 0, 0, 13, later, 0, 5],
        [OK, 5, CONFLICT, OK, CONFLICT, 5],
        [OK, ENDED, CLEAR, O_COMPLETED, 0, ON_TIME, 1, 0, 0, 13, 0, -1],
        [OK, 1, ACCEPTED, IN_FLIGHT, 0, 0, ON_TIME, 1, -1, 0, 0],
    ]


def test_an_end_names_a_run_daybook_never_heard_start(forth):
    first = ms(2026, 10, 11, 9)
    rows = run(forth, [
        f"{NOW} {first} A-ACCEPTED {O_COMPLETED} 0 9 R-END "
        f"KEYX RS {first + 1000} OW DBAO-OCC-FINISH . 1 RUN. 1 ITEM DBAS-O.RUN C@ . "
        "1 ITEM DBAS-O.STARTED @ . O-REOPEN . 1 ITEM DBAS-O.RUN C@ . CR",
    ])
    assert rows == [[OK, ENDED, CLEAR, O_COMPLETED, 0, ON_TIME, 1, 0, 0, 0, 9, 0, OK, 9]]


FINISH_REFUSALS = {
    "a pair outside the table": (f"{O_COMPLETED} {R_REVOKED} 9 R-END", INVALID),
    "a summary past its capacity": (f'{O_COMPLETED} 0 9 R-END S" abcde" RS SDSP-SUMMARY! '
                                    "DROP 4 RS SDSP-P.CAPACITY !", INVALID),
    "a summary of two lines": (f'{O_COMPLETED} 0 9 R-END S" a" RS SDSP-SUMMARY! DROP '
                               "10 RS SDSP-P.SUMMARY C!", INVALID),
    "a block once it ran": (f"{O_BLOCKED} {R_REVOKED} 9 R-END", INVALID),
    "a block once it ran, naming no run": (f"{O_BLOCKED} {R_REVOKED} 0 R-END", INVALID),
    "not started once it ran": (f"{O_NOT_STARTED} {R_MISSED} 0 R-END", INVALID),
    "another run": (f"{O_COMPLETED} 0 8 R-END", CONFLICT),
}

UNSTARTED_REFUSALS = {
    "completed": f"{O_COMPLETED} 0 0 R-END",
    "ran out of time": f"{O_EXPIRED} 19 0 R-END",
    "stopped for review": f"{O_STOPPED} 16 0 R-END",
}


def test_finish_checks_what_it_is_told(forth):
    """A refusal touches neither memory nor the disk: with reads failing,
    a store that tried to write and reload would block."""

    first = ms(2026, 10, 11, 9)
    finish = (f"' T-FAIL-READ VFS-OP-READ T-OP! KEYX RS {first} OW DBAO-OCC-FINISH . "
              "OW DBAO-STORE DBAS-STATE@ . T-OPS-RESET GEN . 1 RUN. CR")
    lines = [f"{NOW} {first} A-RUNNING {edit} {finish}"
             for edit, _ in FINISH_REFUSALS.values()]
    lines += [f"{NOW} {first} A-ACCEPTED {edit} {finish}"
              for edit in UNSTARTED_REFUSALS.values()]
    rows = run(forth, lines)
    assert len(rows) == len(FINISH_REFUSALS) + len(UNSTARTED_REFUSALS), rows
    for (name, (_, status)), row in zip(FINISH_REFUSALS.items(), rows):
        assert row == [status, 1, 4, RUNNING, IN_FLIGHT, 0, 0, ON_TIME, 1, 0, 0, 0], name
    for name, row in zip(UNSTARTED_REFUSALS, rows[len(FINISH_REFUSALS):]):
        assert row == [INVALID, 1, 3, ACCEPTED, IN_FLIGHT, 0, 0, ON_TIME, 1, -1, 0, 0], name


def test_a_refusal_clears_only_the_approval_it_refused(forth):
    first = ms(2026, 10, 11, 9)
    rows = run(forth, [
        # Revoked while it ran, under the permission Daybook holds.
        f"{NOW} {first} A-RUNNING {O_CANCELLED} {R_REVOKED} 9 R-END "
        "RS SDSP-P.PERMISSION 32 6 FILL 1 RS SDSP-P.PERMISSION-REVISION ! "
        f"KEYX RS {first} OW DBAO-OCC-FINISH . 1 RUN. AUTH. "
        # The next day's block for the same reason is an item of its own.
        f"SDSP-A-WITHDRAWN T-STANDING ! {first + 86400000} DBAS-CONTINUOUS ACCEPT. "
        "ITEMS . 2 RUN. CR",
        # Refused at an older revision of the permission than Daybook holds.
        f"{NOW} {first} A-ACCEPTED {O_BLOCKED} {R_CHANGED} 0 R-END "
        "RS SDSP-P.PERMISSION 32 6 FILL 2 RS SDSP-P.PERMISSION-REVISION ! "
        f"KEYX RS {first} OW DBAO-OCC-FINISH . 1 RUN. AUTH. CR",
        # Another end leaves it.
        f"{NOW} {first} A-RUNNING {O_FAILED} {R_PROVIDER_ERROR} 9 R-END "
        "RS SDSP-P.PERMISSION 32 6 FILL 1 RS SDSP-P.PERMISSION-REVISION ! "
        f"KEYX RS {first} OW DBAO-OCC-FINISH . 1 RUN. AUTH. CR",
    ])
    assert rows == [
        [OK, ENDED, DUE, O_CANCELLED, R_REVOKED, ON_TIME, 1, 0, 0, 0, 0, 0, 0, 0,
         OK, 1, 2, ENDED, DUE, O_BLOCKED, R_REVOKED, ON_TIME, 1, -1, 0, 0],
        [OK, ENDED, DUE, O_BLOCKED, R_CHANGED, ON_TIME, 1, -1, 0, 0, 1, 4, 6, 1],
        [OK, ENDED, DUE, O_FAILED, R_PROVIDER_ERROR, ON_TIME, 1, 0, 0, 0, 1, 4, 6, 1],
    ]


def test_run_now(forth):
    rows = run(forth, [
        f"O-FRESH {NOW} CREATE1 . RID1 1 {NOW} OW DBAO-RUN-NOW . . "
        f"O-FRESH D-AGENT {NOW} CREATE1 . RID1 1 {NOW} OW DBAO-RUN-NOW . . CR",
        f"R-PERMIT RID1 1 RS {NOW} OW DBAO-AUTHORIZE . RID1 2 {NOW} OW DBAO-RUN-NOW . . "
        "RID1 1 -1 OW DBAO-RUN-NOW . . GEN . CR",
        f"RID1 1 {NOW} OW DBAO-RUN-NOW . . 1 RUN. 1 KEY-OK. 1 ITEM DBAS-O.BASIS @ . "
        "1 ITEM DBAS-O.FIRST @ . 1 ITEM DBAS-O.FIRST-UTC @ . S1 SCHED. CR",
        # One run at a time, by hand or on time.
        f"RID1 1 {NOW} OW DBAO-RUN-NOW . . {ms(2026, 10, 11, 9)} DBAS-CONTINUOUS ACCEPT. "
        "2 RUN. CR",
        "O-REOPEN . 1 RUN. CR",
        # A paused or archived schedule is not run.
        f"O-FRESH D-AGENT {NOW} CREATE1 . R-PERMIT RID1 1 RS {NOW} OW DBAO-AUTHORIZE . "
        f"RID1 1 {NOW} OW DBAO-PAUSE . RID1 2 {NOW} OW DBAO-RUN-NOW . . "
        f"RID1 2 {NOW} OW DBAO-RESUME . RID1 3 {NOW} OW DBAO-ARCHIVE . "
        f"RID1 4 {NOW} OW DBAO-RUN-NOW . . CR",
    ])
    assert rows == [
        [OK, MANUAL_S, 0, OK, APPROVAL, 0],
        [OK, CONFLICT, 0, CLOCK, 0, 2],
        [OK, 1, ACCEPTED, IN_FLIGHT, 0, 0, MANUAL, 1, -1, 0, 0, -1, USER, 0, NOW // 1000,
         ENABLED, 1, 1, utc(2026, 10, 11, 9), 1, MANUAL],
        [BUSY, 0, OK, 1, ENDED, DUE, O_BLOCKED, R_OVERLAP, ON_TIME, 1, -1, 0, 0],
        [OK, ACCEPTED, IN_FLIGHT, 0, 0, MANUAL, 1, -1, 0, 0],
        [OK, OK, OK, STATE, 0, OK, OK, STATE, 0],
    ]


def test_delete_keeps_short_records_of_runs(forth):
    day = 86400000
    first = ms(2026, 10, 11, 9)
    gone = ms(2026, 10, 14, 12)
    rows = run(forth, [
        f"{NOW} {first} A-RUNNING {O_COMPLETED} 0 9 R-END "
        f'S" Read 3 items." RS SDSP-SUMMARY! . KEYX RS {first + 60000} OW DBAO-OCC-FINISH . '
        f"{first + day} DBAS-CONTINUOUS ACCEPT. 2 KEYX! 8 RUNID K! "
        f"KEYX RUNID {first + day} OW DBAO-OCC-STARTED . {O_FAILED} {R_PROVIDER_ERROR} 8 R-END "
        f'S" The provider failed." RS SDSP-SUMMARY! . '
        f"KEYX RS {first + day + 60000} OW DBAO-OCC-FINISH . CR",
        # A run in flight keeps the schedule, and so does an indeterminate
        # one awaiting review.
        f"{first + 2 * day} DBAS-CONTINUOUS ACCEPT. RID1 1 {gone} OW DBAO-DELETE . "
        f"3 KEYX! {O_INDETERMINATE} {R_INTERRUPTED} 0 R-END "
        f"KEYX RS {gone} OW DBAO-OCC-FINISH . RID1 1 {gone} OW DBAO-DELETE . "
        f"3 3 {gone} OW DBAO-REVIEW . RID1 1 {gone} OW DBAO-DELETE . CR",
        "ITEMS . 1 RUN. 2 RUN. 2 ITEM DBAS-O.REVIEWED @ . 3 RUN. "
        "OW DBAO-STORE DBAS-ACTION-COUNT@ . S1 DBAS-S.STATE @ . "
        "1 ITEM DBAS-O.RUN C@ . 2 ITEM DBAS-O.RUN C@ . CR",
        "O-REOPEN . ITEMS . 2 RUN. 2 ITEM DBAS-O.ENDED @ . 1 ITEM DBAS-O.STARTED @ . "
        "1 ITEM DBAS-O.ACCEPTED @ . CR",
    ])
    assert rows == [
        [0, OK, OK, 1, OK, 0, OK],
        [OK, 1, BUSY, OK, REVIEW, OK, OK],
        [3, ENDED, CLEAR, O_COMPLETED, 0, ON_TIME, 1, 0, 1, 0,
         ENDED, REVIEWED, O_FAILED, R_PROVIDER_ERROR, ON_TIME, 1, 0, 1, 0, gone,
         ENDED, REVIEWED, O_INDETERMINATE, R_INTERRUPTED, ON_TIME, 1, -1, 1, 0,
         0, TOMBSTONE, 9, 8],
        [OK, 3, ENDED, REVIEWED, O_FAILED, R_PROVIDER_ERROR, ON_TIME, 1, 0, 1, 0,
         first + day + 60000, first, first],
    ]


def test_retention_prunes_only_settled_runs(forth):
    day = 86400000
    first = ms(2026, 10, 11, 9)
    rows = run(forth, [
        f"{NOW} {first} A-RUNNING 1 OW DBAO-STORE DBAS-HEADER DBAS-H.RETAIN ! "
        f"{O_COMPLETED} 0 9 R-END KEYX RS {first + 1000} OW DBAO-OCC-FINISH . "
        f"{first + day} DBAS-CONTINUOUS ACCEPT. 2 KEYX! "
        f"KEYX RUNID {first + day} OW DBAO-OCC-STARTED . "
        f"KEYX RS {first + day + 1000} OW DBAO-OCC-FINISH . "
        f"{first + 2 * day} DBAS-CONTINUOUS ACCEPT. 3 KEYX! "
        f"{O_FAILED} {R_PROVIDER_START} 0 R-END KEYX RS {first + 2 * day} OW DBAO-OCC-FINISH . "
        f"{first + 3 * day} DBAS-CONTINUOUS ACCEPT. CR",
        "ITEMS . 0 OW DBAO-STORE DBAS-OCCURRENCE @ . S1 DBAS-S.PRUNED @ . CR",
        # Deleting settles what awaited review, then keeps the retention.
        f"4 KEYX! KEYX RS {first + 3 * day} OW DBAO-OCC-FINISH . "
        f"RID1 1 {first + 3 * day} OW DBAO-DELETE . ITEMS . "
        "0 OW DBAO-STORE DBAS-OCCURRENCE @ . 4 RUN. O-REOPEN . ITEMS . CR",
    ])
    assert rows == [
        [OK, OK, 1, OK, OK, OK, 1, OK, OK, 1],
        [3, 2, 1],
        [OK, OK, 1, 4, ENDED, REVIEWED, O_FAILED, R_PROVIDER_START, ON_TIME, 1, -1, 1, 0,
         OK, 1],
    ]


def test_paged_reads(forth):
    rows = run(forth, [
        f"O-FRESH {NOW} CREATE1 . {local(2026, 10, 11, 10)} D-RULE DBREC.START ! "
        f"2 KEY1 K! KEY1 DR {NOW} RID2 OW DBAO-CREATE . "
        f"3 KEY1 K! KEY1 DR {NOW} RID3 OW DBAO-CREATE . RID3 1 {NOW} OW DBAO-DELETE . CR",
        # Live schedules in RID order.
        "0 QRY 3 OW DBAO-QUERY . . . QRY RID1 RID= QRY RID2 RID= OR . "
        "QRY 32 + RID1 RID= QRY 32 + RID2 RID= OR . QRY 32 QRY 32 + 32 COMPARE . CR",
        # A page at a time.
        "0 QRY 64 + 1 OW DBAO-QUERY . QC ! . QRY 64 + QRY RID= . "
        "QC @ QRY 64 + 1 OW DBAO-QUERY . QC ! . QRY 64 + QRY 32 + RID= . "
        "QC @ QRY 64 + 1 OW DBAO-QUERY . . . CR",
        # Each schedule's items, newest first.
        f"{ms(2026, 10, 11, 9)} DBAS-CONTINUOUS ACCEPT. {ms(2026, 10, 11, 10)} "
        f"DBAS-CONTINUOUS ACCEPT. 1 1 {NOW} OW DBAO-REVIEW . 2 1 {NOW} OW DBAO-REVIEW . "
        f"{ms(2026, 10, 12, 9)} DBAS-CONTINUOUS ACCEPT. {ms(2026, 10, 12, 10)} "
        f"DBAS-CONTINUOUS ACCEPT. 3 2 {NOW} OW DBAO-REVIEW . 4 2 {NOW} OW DBAO-REVIEW . "
        f"{ms(2026, 10, 13, 9)} DBAS-CONTINUOUS ACCEPT. CR",
        "RID1 0 HIST 8 OW DBAO-HISTORY . . . HIST @ . HIST 8 + @ . HIST 16 + @ . CR",
        "RID1 1 HIST 1 OW DBAO-HISTORY . . . HIST @ . "
        "RID1 3 HIST 8 OW DBAO-HISTORY . . . RID2 0 HIST 8 OW DBAO-HISTORY . . . "
        "HIST @ . HIST 8 + @ . CR",
    ])
    assert rows == [
        [OK, OK, OK, OK],
        [OK, 3, 2, -1, -1, -1],
        [OK, 1, -1, OK, 1, -1, OK, 3, 0],
        [OK, 1, OK, 1, OK, OK, OK, 1, OK, 1, OK, OK, OK, 1],
        [OK, 3, 3, 5, 3, 1],
        [OK, 2, 1, 3, OK, 3, 0, OK, 2, 2, 4, 2],
    ]

