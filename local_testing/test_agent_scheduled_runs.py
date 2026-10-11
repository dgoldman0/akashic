#!/usr/bin/env python3
"""tui/applets/agent/scheduled-runs.f: the Agent's view of its scheduled runs.

The suite reuses the dispatch suite's runtime, provider, run store and
authority, and runs scheduled runs through a real dispatcher before
reading them back through the view: rows newest first, titles and
details, staleness, transcripts opened and closed, runs past the keep
setting, and what the view says when it has nothing to show.
"""

from __future__ import annotations

import pytest

from native_forth import NativeForth
from test_agent_dispatch import PRELUDE as DISPATCH_PRELUDE


OK, NONE, INVALID, NOMEM = range(4)

PRELUDE = DISPATCH_PRELUDE + r"""
CREATE VW-RAW ASRV-SIZE 7 + ALLOT  VW-RAW 7 + -8 AND CONSTANT VW
: VIEW  ( -- ) VW ASRV-FREE DS VW ASRV-INIT VW ASRV-REBUILD ;
: TITLE.  ( i -- ) VW ASRV-TITLE TYPE ;
: DETAIL.  ( i -- ) VW ASRV-DETAIL TYPE ;
: NOTE.  ( -- ) VW ASRV-NOTE TYPE ;
\ Three runs as generations go: one completed, one stopped for review, and
\ one still running.
: THREE  ( -- )
    FRESH T-NOW EPOCH-SET
    1 1 R-OCC GO DROP 8 STEPS
    TASK$ OPS! 1 2 R-OCC GO DROP 8 STEPS
    LINGER$ OPS! 1 3 R-OCC KEEP1 GO DROP 2 STEPS ;
\ Bytes ALLOCATE can still hand out: the bank-0 heap, the unused tail of
\ external memory and every reclaimed external block.
: AVAILABLE  ( -- u )
    HEAP-FREE-BYTES XMEM-FREE +
    XMEM-FL @ BEGIN ?DUP WHILE DUP @ ROT + SWAP 8 + @ REPEAT ;
VARIABLE RUN1
\ Whether text the view wrote fills exactly the room it asked for.
: FILLS-ROOM?  ( a u -- flag ) NIP VW _ASRV.CAP @ = ;
\ Takes every block external memory can give, which is all ALLOCATE uses
\ when there is any, largest first; FEED gives them back.  Freed blocks
\ are not joined again, so the largest go first, to keep them large.
VARIABLE HOG
: STARVE  ( -- )
    0 HOG !
    1099511627776 BEGIN DUP 0> WHILE
        DUP ALLOCATE 0= IF HOG @ OVER ! HOG ! ELSE DROP 2/ THEN
    REPEAT DROP ;
: FEED  ( -- ) BEGIN HOG @ ?DUP WHILE DUP @ HOG ! FREE REPEAT ;
"""

SUITE = NativeForth(("tui/applets/agent/scheduled-runs.f",
                     "tui/applets/agent/providers/devtools/device-flow.f"),
                    prelude=tuple(PRELUDE.strip().splitlines()))


@pytest.fixture(scope="module")
def forth():
    return SUITE.shared()


def run(forth, lines: list[str], max_steps: int = 4_000_000_000) -> list[str]:
    output = forth.run(lines, max_steps).decode("latin-1")
    assert "??" not in output, output[-3000:]
    return [line for line in output.replace("\r", "").split("\n") if line.strip()]


def test_rows_newest_first(forth):
    rows = run(forth, [
        "THREE VIEW VW ASRV-COUNT@ . VW ASRV-STALE? . CR",
        "0 TITLE. CR", "0 DETAIL. CR",
        "1 TITLE. CR", "1 DETAIL. CR",
        "2 TITLE. CR", "2 DETAIL. CR",
        "NOTE. CR",
        # Each row names its run by its dispatch key.
        "0 VW ASRV-KEY RQ SDSP-R.KEY 32 TUCK COMPARE . CR",
    ])
    assert rows[0].split() == ["3", "0"]
    assert rows[1] == "Read the news"
    assert rows[2] == "2026-10-10 12:00 UTC  running  gpt-slow"
    assert rows[3] == "Read the news"
    assert rows[4] == ("2026-10-10 12:00 UTC  stopped for review: asked to use a tool  "
                       "gpt-slow")
    assert rows[5] == "Read the news"
    assert rows[6] == "2026-10-10 12:00 UTC  completed  gpt-slow"
    assert rows[7] == "Enter opens a run's transcript; Escape returns"
    assert rows[8].split() == ["0"]


def test_rows_go_stale_when_the_store_writes(forth):
    rows = run(forth, [
        "THREE VIEW VW ASRV-STALE? . 8 STEPS VW ASRV-STALE? . "
        "KEY1 SACT-R-USER DS ADISP-CANCEL DROP VW ASRV-STALE? . "
        "VW ASRV-REBUILD VW ASRV-STALE? . VW ASRV-COUNT@ . CR",
        "0 DETAIL. CR",
    ])
    # A run that keeps running writes nothing; its end does.
    assert rows[0].split() == ["0", "0", "-1", "0", "3"]
    assert rows[1] == "2026-10-10 12:00 UTC  cancelled: by you  gpt-slow"


def test_a_transcript_opens_and_closes(forth):
    rows = run(forth, [
        "THREE 8 STEPS VIEW 2 VW ASRV-OPEN . VW ASRV-SHOWN ACONV.COUNT @ . "
        "0 VW ASRV-SHOWN ACONV-NTH AMSG-TEXT NEWS$ COMPARE . CR",
        # Opening another replaces it; closing leaves none.
        "1 VW ASRV-OPEN . VW ASRV-SHOWN ACONV.COUNT @ . VW ASRV-CLOSE VW ASRV-SHOWN . CR",
        # No row, and rows that went stale, open nothing.
        "3 VW ASRV-OPEN . -1 VW ASRV-OPEN . KEY1 SACT-R-USER DS ADISP-CANCEL DROP "
        "0 VW ASRV-OPEN . VW ASRV-SHOWN . CR",
    ])
    assert rows[0].split() == [str(OK), "2", "0"]
    assert rows[1].split() == [str(OK), "3", "0"]
    assert rows[2].split() == [str(NONE), str(NONE), str(NONE), "0"]


def test_a_run_past_the_keep_setting(forth):
    rows = run(forth, [
        "THREE 8 STEPS 0 DS ADISP-STORE ADST-KEEP! . VIEW 2 TITLE. CR",
        "2 DETAIL. CR",
        "2 VW ASRV-OPEN . VW ASRV-SHOWN . CR",
    ])
    assert rows[0] == "0 Run 1 (transcript not kept)"
    assert rows[1] == "2026-10-10 12:00 UTC  completed"
    assert rows[2].split() == [str(NONE), "0"]


def test_what_the_view_says_without_rows(forth):
    rows = run(forth, [
        # Outside Desk there is no dispatcher.
        "VW ASRV-FREE 0 VW ASRV-INIT VW ASRV-REBUILD VW ASRV-COUNT@ . VW ASRV-STALE? . NOTE. CR",
        "FRESH VIEW NOTE. CR",
        # A record that cannot be read.
        "DS ADISP-FINI TBUF 16 0 FILL 16 TLEN ! D-PATH T-PUT-AT RT @ TV @ DS ADISP-INIT DROP "
        "VIEW VW ASRV-COUNT@ . NOTE. CR",
        # The clock not set when the run was accepted.
        "FRESH 0 EPOCH-SET 1 1 R-OCC GO DROP 8 STEPS VIEW 0 DETAIL. CR",
        # A dispatcher Desk closed.
        "VIEW DS ADISP-FINI NOTE. CR",
    ])
    assert rows[0] == "0 0 Scheduled runs come through Desk"
    assert rows[1] == "No scheduled runs yet"
    assert rows[2] == "0 The record of scheduled runs cannot be read"
    assert rows[3] == "time unknown  completed  gpt-slow"
    assert rows[4] == "Scheduled runs come through Desk"


def test_a_view_starts_from_any_record(forth):
    rows = run(forth, [
        "VW ASRV-FREE VW ASRV-SIZE 255 FILL 0 VW ASRV-INIT "
        "VW ASRV-COUNT@ . VW ASRV-SHOWN . VW _ASRV.BUF @ . VW _ASRV.CAP @ . CR",
    ])
    assert rows[0].split() == ["0"] * 4


def test_a_time_past_what_a_date_can_say(forth):
    rows = run(forth, [
        # Accepted, by the store's own word, after the year 9999.
        "FRESH 1 1 R-OCC RQ 253402300800000 DS ADISP-STORE ADST-ACCEPT . DROP CR",
        "VIEW 0 DETAIL. CR",
    ])
    assert rows[0].split() == ["0"]
    assert rows[1] == "time unknown  running  gpt-slow"


def test_a_store_that_stops_being_readable(forth):
    rows = run(forth, [
        "THREE VIEW DS ADISP-STORE ADST-CLOSE DROP VW ASRV-STALE? . VW ASRV-REBUILD "
        "VW ASRV-COUNT@ . VW ASRV-STALE? . NOTE. CR",
        # Open again over the same file: the rows come back.
        "DS ADISP-STORE ADST-OPEN . VW ASRV-STALE? . VW ASRV-REBUILD VW ASRV-COUNT@ . CR",
    ])
    assert rows[0] == "-1 0 0 The record of scheduled runs cannot be read"
    assert rows[1].split() == [str(OK), "-1", "3"]


def test_a_transcript_that_cannot_be_read(forth):
    rows = run(forth, [
        # A run whose transcript is not one: the store keeps any bytes.
        "FRESH T-NOW EPOCH-SET 1 1 R-OCC RQ T-NOW DS ADISP-STORE ADST-ACCEPT . RUN1 ! "
        'S" junk" RUN1 @ DS ADISP-STORE ADST-TRANSCRIPT! . '
        "SACT-O-COMPLETED 0 0 T-NOW RUN1 @ DS ADISP-STORE ADST-FINISH . CR",
        "VIEW 0 VW ASRV-OPEN . VW ASRV-SHOWN . CR",
    ])
    assert rows[0].split() == ["0", "0", "0"]
    assert rows[1].split() == [str(INVALID), "0"]


def test_text_fills_the_room_it_asks_for(forth):
    rows = run(forth, [
        # Of the runs that ended, the newest keeps its transcript, and the
        # oldest only its row.  Each text is asked of a view with no room.
        "THREE 8 STEPS 1 DS ADISP-STORE ADST-KEEP! . CR",
        "VIEW 0 VW ASRV-DETAIL FILLS-ROOM? . VIEW 1 VW ASRV-DETAIL FILLS-ROOM? . "
        "VIEW 2 VW ASRV-DETAIL FILLS-ROOM? . VIEW 2 VW ASRV-TITLE FILLS-ROOM? . CR",
        # A shorter text takes the room a longer one left.
        "VIEW 1 VW ASRV-DETAIL 2DROP VW _ASRV.BUF @ 0 VW ASRV-DETAIL 2DROP "
        "VW _ASRV.BUF @ = . CR",
    ])
    assert rows[0].split() == ["0"]
    assert rows[1].split() == ["-1"] * 4
    assert rows[2].split() == ["-1"]


def test_text_and_transcripts_without_memory(forth):
    rows = run(forth, [
        "THREE 8 STEPS VIEW 0 DETAIL. CR",
        # Room the heap cannot give leaves the buffer as it was.
        "VW _ASRV.BUF @ VW _ASRV.CAP @ 1099511627776 VW _ASRV-ROOM . "
        "VW _ASRV.CAP @ = . VW _ASRV.BUF @ = . CR",
        "0 DETAIL. CR",
        # With no memory at all: no text and no transcript.
        "VIEW STARVE 0 VW ASRV-DETAIL NIP . 2 VW ASRV-OPEN . VW ASRV-SHOWN . FEED CR",
        "0 DS ADISP-STORE ADST-KEEP! . VIEW STARVE 2 VW ASRV-TITLE NIP . FEED 2 TITLE. CR",
    ])
    assert rows[1].split() == [str(NOMEM), "-1", "-1"]
    assert rows[2] == rows[0] == "2026-10-10 12:00 UTC  running  gpt-slow"
    assert rows[3].split() == ["0", str(NOMEM), "0"]
    assert rows[4] == "0 0 Run 1 (transcript not kept)"


def test_the_view_gives_back_all_it_takes(forth):
    rows = run(forth, [
        # Of the runs that ended, the newest keeps its transcript, and the
        # oldest only its row.
        "THREE 8 STEPS 1 DS ADISP-STORE ADST-KEEP! . CR",
        "VW ASRV-FREE AVAILABLE DS VW ASRV-INIT VW ASRV-REBUILD",
        # A short text, then a longer one that grows the buffer.
        "2 TITLE. CR 1 DETAIL. CR",
        # A transcript opened in place of itself, closed, and opened again.
        "1 VW ASRV-OPEN . 1 VW ASRV-OPEN . VW ASRV-CLOSE 1 VW ASRV-OPEN . CR",
        "VW ASRV-FREE AVAILABLE = . VW ASRV-COUNT@ . VW ASRV-SHOWN . NOTE. CR",
    ])
    assert rows[0].split() == ["0"]
    assert rows[1] == "Run 1 (transcript not kept)"
    assert rows[2] == ("2026-10-10 12:00 UTC  stopped for review: asked to use a tool  "
                       "gpt-slow")
    assert rows[3].split() == [str(OK)] * 3
    assert rows[4] == "-1 0 0 Scheduled runs come through Desk"
