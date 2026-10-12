#!/usr/bin/env python3
"""daybook/automation-view.f: a schedule opened in detail.

Over the dispatch suite's fake broker, as the create suite drives it: an
Agent run's facts, its title, when it runs and next runs, whether it is
approved, the model it names with its choices, its provider, its limits
and its prompt, exactly as stored; a reminder's fewer facts; each item
after them, newest first, with how it ended and its run's summary; facts
that follow the store and say when the schedule is gone; and the actions
on the opened schedule, which refuse while its facts are old.
"""

from __future__ import annotations

import pytest

from native_forth import NativeForth
from test_daybook_automation_dispatch import _schedule, _tick, run, text
from test_daybook_automation_owner import NOW, O_COMPLETED, O_FAILED, R_PROVIDER_ERROR
from test_daybook_automation_service import _advance
from test_daybook_automation_view_create import PRELUDE as CREATE_PRELUDE


OK, NONE, CHANGED, DELETED, NOMEM = 0, 41, 40, 10, 42
MODEL, EFFORT, TIER, VERBOSITY = 1, 2, 3, 4
SCHEDULE, ITEM = 1, 2

PRELUDE = CREATE_PRELUDE + r"""
\ Each fact of the opened schedule: label | text.
: FACTS  ( -- )
    VW DBAV-FACTS@ 0 ?DO
        I VW DBAV-FACT-LABEL TYPE ."  | " I VW DBAV-FACT-TEXT TYPE CR
    LOOP ;
\ Each fact's label and text, made and dropped.
: FACTS-MADE  ( -- )
    VW DBAV-FACTS@ 0 ?DO
        I VW DBAV-FACT-LABEL 2DROP I VW DBAV-FACT-TEXT 2DROP
    LOOP ;
\ N runs now of RID1, each ended completed by the fake broker at once, as
\ runs 9 onwards.
: RUNS  ( n -- )
    0 ?DO
        I 9 + FC-RUN-BYTE !
        RID1 RID1 SOW DBAO-FIND DBAS-S.REVISION @ SV DBSVC-RUN-NOW NIP
        ?DUP IF ." RUN-NOW " . THEN
    LOOP ;
\ The labels of the facts from FIRST on, a line each.
: LABELS-FROM  ( first -- )
    VW DBAV-FACTS@ SWAP ?DO I VW DBAV-FACT-LABEL TYPE CR LOOP ;
\ Opens the schedule whose row has TITLE.
: OPEN  ( title-a title-u -- status ) V-FIND VW DBAV-OPEN ;
"""

SUITE = NativeForth(("tui/applets/daybook/automation-view.f",),
                    prelude=tuple(PRELUDE.strip().splitlines()))


@pytest.fixture()
def machine():
    machine = SUITE.shared()
    machine.runtime.rtc.set_epoch_ms(NOW)
    _advance(machine, 1000, 0)
    return machine


def lines(machine, line: str) -> list[str]:
    output = machine.run([line], 8_000_000_000).decode("latin-1")
    assert "??" not in output, output[-3000:]
    return [row.rstrip() for row in output.replace("\r", "").split("\n") if row.strip()]


def _brief(machine) -> None:
    """The create suite's Agent run, Morning brief, daily at 09:00 UTC."""

    assert run(machine, ["C-FRESH CR"]) == [[OK, OK]]
    assert run(machine, [
        'C-BEGIN S" 09:00 Morning brief" VW DBAV-WHEN! . S" daily" VW DBAV-REPEAT! . '
        f'S" " VW DBAV-ZONE! . 0 {MODEL} VW DBAV-CHOOSE . 1 {EFFORT} VW DBAV-CHOOSE . '
        f'1 {TIER} VW DBAV-CHOOSE . 2 {VERBOSITY} VW DBAV-CHOOSE . '
        'S" 10" VW DBAV-MINUTES! . S" 16384" VW DBAV-REPLY! . '
        "BRIEF VW DBAV-PROMPT! . VW DBAV-CREATE . V-NEW CR"
    ]) == [[OK] * 14]


def test_an_agent_runs_facts(machine):
    _brief(machine)
    assert run(machine, ['VW DBAV-OPENED? . S" Morning brief" OPEN . VW DBAV-OPENED? . '
                         "VW DBAV-FACTS@ . CR"]) == [[0, OK, -1, 8]]
    assert lines(machine, "FACTS") == [
        "Schedule | Morning brief",
        "When | daily at 09:00 from 2026-10-11 (UTC0)",
        "Next | 2026-10-11 09:00",
        "Approval | Not approved",
        "Model | gpt-test, high effort, flex tier, medium verbosity",
        "Provider | org.akashic.agent.testing.scripted",
        "Limits | 10 min to run, 34 bytes to disclose, 16384 bytes of reply",
        "Prompt | Summarize the news.",
        "Keep it short.",
    ]
    # Closed, it has no facts.
    assert run(machine, ["VW DBAV-SHUT VW DBAV-OPENED? . VW DBAV-FACTS@ . CR"]) == [[0, 0]]


def test_a_reminders_facts_and_its_items(machine):
    _brief(machine)
    # A daily reminder at the next hour, which fires, is reviewed, then
    # misses two days.
    run(machine, ["A-REMINDER . CR"])
    _tick(machine, 3_599_000)
    _tick(machine, 1000)
    run(machine, [f"V-NEW {ITEM} V-KIND VW DBAV-REVIEW . CR"])
    _advance(machine, 1000, 2 * 86_400_000)
    run(machine, ["SV DBSVC-TICK . CR"])
    assert run(machine, ['V-NEW S" Water the plants" OPEN . VW DBAV-FACTS@ . CR']) == [
        [OK, OK, 5]]
    assert lines(machine, "FACTS") == [
        "Schedule | Water the plants",
        "When | daily at 13:00 from 2026-10-10 (UTC0)",
        "Next | 2026-10-13 13:00",
        "Missed | 2026-10-12 13:00, 2 times, needs review",
        "Fired | 2026-10-10 13:00",
    ]


def test_runs_newest_first_with_their_summaries(machine):
    # A daily Agent run, approved, first due five seconds from now.
    assert run(machine, [
        "S-FRESH . FC-RESET FC-ON SV DBSVC-TICK . "
        'S" Read the news" D-TITLE DBREC-DAILY D-RULE DBREC.FREQ ! '
        "DBSVC-NOW 1000 / 5 + D-RULE DBREC.START ! D-AGENT S-CREATE . "
        "R-PERMIT RID1 1 RS DBSVC-NOW SOW DBAO-AUTHORIZE . CR"]) == [[OK, 0, OK, OK]]
    # The first run ends failed, with a summary, and is reviewed; the
    # second, by hand, is running.
    run(machine, [f"S-ENDED FC-SUBMIT-STATUS ! 0 FC-RUN-BYTE ! {O_FAILED} FC-OUTCOME ! "
                  f"{R_PROVIDER_ERROR} FC-REASON ! 3 FC-SUMMARY-U ! CR"])
    _tick(machine, 5000)
    assert run(machine, [f"V-NEW {ITEM} V-KIND VW DBAV-REVIEW . "
                         "S-RUNNING FC-SUBMIT-STATUS ! 9 FC-RUN-BYTE ! "
                         'V-NEW S" Read the news" V-FIND VW DBAV-RUN-NOW . CR']) == [
        [OK, OK, OK, OK]]
    assert run(machine, ['V-NEW S" Read the news" OPEN . VW DBAV-FACTS@ . CR']) == [
        [OK, OK, 10]]
    facts = lines(machine, "FACTS")
    assert facts[0] == "Schedule | Read the news"
    assert facts[3] == "Approval | Approved"
    history = facts[facts.index("Prompt | Summarize the news."):]
    assert history[1].startswith("Run now | 2026-10-10 12:00, ")
    assert history[1].split(", ", 1)[1] in ("waiting", "running")
    assert history[2] == "Run | 2026-10-10 12:00, failed: provider error"
    assert history[3] == "sss"


def test_facts_follow_the_store(machine):
    _brief(machine)
    run(machine, ['S" Morning brief" OPEN . CR'])
    # A change to the store makes the facts old: actions refuse until they
    # are read again.
    assert run(machine, ["VW DBAV-OPENED-STALE? . A-REMINDER . VW DBAV-OPENED-STALE? . "
                         "VW DBAV-OPENED-ASK . VW DBAV-REREAD . "
                         "VW DBAV-OPENED-STALE? . CR"]) == [[0, OK, -1, CHANGED, OK, 0]]
    # Deleted, it is gone, and has no facts.
    assert run(machine, ['VW DBAV-REBUILD . S" Morning brief" V-FIND VW DBAV-DELETE . '
                         "VW DBAV-REREAD . VW DBAV-FACTS@ . "
                         "VW DBAV-OPENED-RUN-NOW . CR"]) == [[OK, OK, DELETED, 0, CHANGED]]


def test_actions_on_the_opened_schedule(machine):
    _schedule(machine, approve=False, due_s=3600)
    run(machine, ['V-NEW S" Read the news" OPEN . CR'])
    # Not approved, it does not run now; asked, Desk is asked.
    assert run(machine, ["VW DBAV-OPENED-RUN-NOW . VW DBAV-OPENED-ASK . FC-ASKS @ . "
                         "VW DBAV-OPENED-CANCEL . CR"]) == [[19, OK, 1, NONE]]
    # Approved, it runs now, and its run in flight cancels.
    run(machine, ["R-PERMIT RID1 1 RS DBSVC-NOW SOW DBAO-AUTHORIZE . CR"])
    assert run(machine, ["VW DBAV-REREAD . S-RUNNING FC-SUBMIT-STATUS ! "
                         "VW DBAV-OPENED-RUN-NOW . VW DBAV-REREAD . "
                         "VW DBAV-OPENED-CANCEL . FC-CANCELS @ . CR"]) == [[OK, OK, OK, OK, 1]]
    # A reminder's details take no Agent run's actions.
    assert run(machine, ['A-REMINDER . V-NEW S" Water the plants" OPEN . '
                         "VW DBAV-OPENED-RUN-NOW . VW DBAV-OPENED-ASK . "
                         "VW DBAV-OPENED-CANCEL . CR"]) == [[OK, OK, OK, NONE, NONE, NONE]]


def test_details_give_back_their_memory(machine):
    _brief(machine)
    assert run(machine, ['VW DBAV-FREE AVAILABLE V-NEW S" Morning brief" OPEN . '
                         "FACTS-MADE VW DBAV-REREAD . VW DBAV-FREE AVAILABLE = . CR"]) == [
        [OK, OK, OK, -1]]


def _daily(machine) -> None:
    """A daily Agent run, Read the news, approved, first due in an hour."""

    assert run(machine, [
        "S-FRESH . FC-RESET FC-ON SV DBSVC-TICK . "
        'S" Read the news" D-TITLE DBREC-DAILY D-RULE DBREC.FREQ ! '
        "DBSVC-NOW 1000 / 3600 + D-RULE DBREC.START ! D-AGENT S-CREATE . "
        "R-PERMIT RID1 1 RS DBSVC-NOW SOW DBAO-AUTHORIZE . CR"]) == [[OK, 0, OK, OK]]


def test_a_long_history(machine):
    # Seventeen runs, more than a page of ids, each completed at once.
    _daily(machine)
    run(machine, [f"S-ENDED FC-SUBMIT-STATUS ! {O_COMPLETED} FC-OUTCOME ! 0 FC-REASON ! "
                  "17 RUNS CR"])
    assert run(machine, ['VW DBAV-FREE AVAILABLE V-NEW S" Read the news" OPEN . '
                         "VW DBAV-FACTS@ . VW _DBAV.HISTORY @ 0<> . "
                         "VW DBAV-REREAD . VW DBAV-FACTS@ . "
                         "VW DBAV-FREE AVAILABLE = . CR"]) == [[OK, OK, 25, -1, OK, 25, -1]]
    run(machine, ['V-NEW S" Read the news" OPEN . CR'])
    labels = lines(machine, "8 LABELS-FROM")
    assert labels == ["Run now"] * 17
    # Nothing past the last fact.
    assert run(machine, ["VW DBAV-FACTS@ DUP VW DBAV-FACT-LABEL NIP . "
                         "VW DBAV-FACT-TEXT NIP . CR"]) == [[0, 0]]
    # An item no longer in the store, as facts read before a change
    # name, shows nothing.
    assert run(machine, ["999 VW _DBAV.HISTORY @ ! 8 VW DBAV-FACT-LABEL NIP . "
                         "8 VW DBAV-FACT-TEXT NIP . CR"]) == [[0, 0]]


def test_without_memory_a_schedule_stays_closed(machine):
    _daily(machine)
    run(machine, [f"S-ENDED FC-SUBMIT-STATUS ! {O_COMPLETED} FC-OUTCOME ! 0 FC-REASON ! "
                  "1 RUNS CR"])
    assert run(machine, ['VW DBAV-FREE V-NEW STARVE S" Read the news" OPEN FEED . '
                         "VW DBAV-OPENED? . CR"]) == [[OK, NOMEM, 0]]


def test_a_deleted_runs_details(machine):
    # Deleted after a run, its schedule stays as a tombstone with the run's
    # short record; its details say it was deleted.
    _daily(machine)
    run(machine, [f"S-ENDED FC-SUBMIT-STATUS ! {O_COMPLETED} FC-OUTCOME ! 0 FC-REASON ! "
                  "1 RUNS CR"])
    assert run(machine, ['V-NEW S" Read the news" OPEN . '
                         'S" Read the news" V-FIND VW DBAV-DELETE . '
                         "RID1 SOW DBAO-FIND 0<> . "
                         "VW DBAV-REREAD . VW DBAV-FACTS@ . CR"]) == [[OK, OK, OK, -1, DELETED, 0]]


def test_actions_name_the_schedule_opened(machine):
    # Reading again starts over, so the facts stay as many.
    _daily(machine)
    run(machine, ["S-RUNNING FC-SUBMIT-STATUS ! 1 RUNS CR"])
    assert run(machine, ['V-NEW S" Read the news" OPEN . VW DBAV-FACTS@ . '
                         "VW DBAV-REREAD . VW DBAV-FACTS@ . CR"]) == [[OK, OK, 9, OK, 9]]
    # Another Agent run opened, with no runs, cancels nothing, though its
    # ids' room still holds the first's run in flight.
    assert run(machine, ['S" Write the digest" D-TITLE 2 KEY1 K! S-CREATE . '
                         'VW DBAV-REBUILD . S" Read the news" OPEN . '
                         'S" Write the digest" OPEN . VW DBAV-FACTS@ . '
                         "8 VW DBAV-FACT-LABEL NIP . "
                         "VW DBAV-OPENED-CANCEL . FC-CANCELS @ . CR"]) == [
        [OK, OK, OK, OK, 8, 0, NONE, 0]]
    # A run that ended is not cancelled; closed, nothing is.
    run(machine, [f"S-ENDED FC-STATUS-STATUS ! {O_FAILED} FC-OUTCOME ! "
                  f"{R_PROVIDER_ERROR} FC-REASON ! CR"])
    _tick(machine)
    assert run(machine, ['V-NEW S" Read the news" OPEN . VW DBAV-OPENED-CANCEL . '
                         "VW DBAV-SHUT VW DBAV-OPENED-RUN-NOW . FC-CANCELS @ . CR"]) == [
        [OK, OK, NONE, NONE, 0]]


def test_a_missed_item_covering_one(machine):
    _brief(machine)
    # A reminder whose one occurrence passes during a jump: missed once.
    run(machine, ["A-REMINDER . CR"])
    _tick(machine, 3_600_000)
    run(machine, ['V-NEW S" Water the plants" OPEN . CR'])
    assert lines(machine, "FACTS")[3:] == ["Missed | 2026-10-10 13:00, needs review"]
