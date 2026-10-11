#!/usr/bin/env python3
"""Static contracts for how Desk hosts scheduled runs.

Desk opens the Agent's dispatcher and the schedule broker once the
runtime exists, gives Daybook the broker's client, pumps them after the
runtime, lends the dispatcher to the Agent alone, shows the schedule
screens through its one screen slot, asks before closing while a run is
in flight, and closes them before Daybook's service and the runtime go.
"""

from __future__ import annotations

import re
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
DESK = REPO_ROOT / "akashic" / "tui" / "applets" / "desk" / "desk.f"
SURFACE = REPO_ROOT / "akashic" / "tui" / "applets" / "desk" / "schedule-surface.f"


def _source(path: Path = DESK) -> str:
    return path.read_text(encoding="utf-8")


def _definition(source: str, word: str) -> str:
    match = re.search(
        rf"^:\s+{re.escape(word)}(?:\s|$).*?;\s*$",
        source,
        re.MULTILINE | re.DOTALL,
    )
    assert match is not None, word
    return match.group(0)


def _in_order(text: str, *parts: str) -> None:
    positions = [text.index(part) for part in parts]
    assert positions == sorted(positions), parts


def test_desk_opens_scheduled_runs_once_the_runtime_exists() -> None:
    source = _source()
    for field in ("ADISP-SIZE CMP-FIELD: _DESK-AGENT-DISPATCH",
                  "SBRK-HANDLER-SIZE CMP-FIELD: _DESK-SCHEDULE-HANDLER",
                  "SBRK-SIZE CMP-FIELD: _DESK-BROKER"):
        assert field in source

    init = _definition(source, "_DESK-SCHEDULES-INIT")
    _in_order(init, "ADISP-INIT", "DSAG-HANDLER-INIT", "SBRK-INIT",
              "SBRK-VALID? 0= IF EXIT THEN", "SBRK-HANDLER!", "DBSVC-CLIENT!")
    interop = _definition(source, "_DESK-INTEROP-INIT")
    _in_order(interop, "ARUNTIME-NEW", "_DESK-SCHEDULES-INIT",
              "_DESK-SERVICE-TABLE-SETUP")


def test_scheduled_runs_follow_the_runtime_each_tick() -> None:
    tick = _definition(_source(), "DESK-TICK-CB")
    _in_order(tick, "ARUNTIME-PUMP", "_DESK-AGENT-DISPATCH ADISP-PUMP",
              "_DESK-BROKER SBRK-TICK", "_DESK-SCREENS-TICK",
              "_DESK-REMINDERS-TICK", "_DESK-HOST AHOST-TICK")


def test_desk_closes_them_before_daybook_and_the_runtime() -> None:
    source = _source()
    fini = _definition(source, "_DESK-SCHEDULES-FINI")
    _in_order(fini, "0 _DESK-REMINDERS DBSVC-CLIENT!", "_DESK-BROKER SBRK-FINI",
              "_DESK-AGENT-DISPATCH ADISP-FINI")
    quiesced = _definition(source, "_DESK-INTEROP-FINI-QUIESCED")
    _in_order(quiesced, "_DESK-SCHEDULES-FINI", "_DESK-REMINDERS DBSVC-CLOSE",
              "ARUNTIME-FREE")


def test_the_dispatcher_goes_to_the_agent_alone() -> None:
    setup = _definition(_source(), "_DESK-SERVICE-TABLE-SETUP")
    assert re.search(
        r'S" org\.akashic\.agent\.dispatch" _DESK-AGENT\$\s+'
        r"\['\] _DESK-SERVICE-AGENT-DISPATCH@", setup
    )
    getter = _definition(_source(), "_DESK-SERVICE-AGENT-DISPATCH@")
    assert "ADISP-VALID?" in getter


def test_the_schedule_screens_share_desks_screen_slot() -> None:
    source = _source()
    surface = _source(SURFACE)
    assert "LST-NEW" in surface
    for word in ("APT1", "PT-", "RICH", "DRW-"):
        assert not re.search(rf"(?<![\w-]){re.escape(word)}", surface), word

    service = _definition(source, "_DESK-SCREEN-SERVICE")
    _in_order(service, "SBXS-OVERLAY?", "SBXS-SERVICE", "DBSVC-NOW SWAP SCHS-SERVICE")
    tick = _definition(source, "_DESK-SCREENS-TICK")
    _in_order(tick, "_DESK-SCREEN-ID @ IF _DESK-SCREEN-SERVICE EXIT THEN",
              "SBOX-CAPABILITY-ASK", "SBRK-ASKING")
    assert "PRM-ACTIVE?" in tick
    box = _definition(source, "_DESK-OVERLAY-BOX")
    assert "SCHS-OVERLAY? IF SCHS-BOX" in box

    shortcut = _definition(source, "_DESK-SHORTCUT?")
    assert re.search(
        r"112\s+_DESK-ALT\?\s+IF\s+DROP\s+_DESK-SHOW-SCHEDULE-PERMISSIONS", shortcut
    )
    permissions = _definition(source, "_DESK-SHOW-SCHEDULE-PERMISSIONS")
    assert "['] DBSVC-LABEL _DESK-REMINDERS" in permissions


def test_a_close_asks_first_while_a_run_is_in_flight() -> None:
    source = _source()
    close = _definition(source, "DESK-REQUEST-CLOSE-CB")
    _in_order(close, "_DESK-SHUTDOWN-ARMED @ 0 _DESK-SHUTDOWN-ARMED !",
              "_DESK-BROKER SBRK-ACTIVE?", "_DESK-SHOW-SHUTDOWN-QUESTION APP-CLOSE-D-DEFER",
              "AHOST-REQUEST-CLOSE-ALL")
    confirmed = _definition(source, "_DESK-SHUTDOWN-CONFIRMED")
    _in_order(confirmed, "-1 _DESK-SHUTDOWN-ARMED !", "ASHELL-QUIT")
    question = _definition(source, "_DESK-SHOW-SHUTDOWN-QUESTION")
    assert "['] _DESK-SHUTDOWN-CONFIRMED" in question
    assert "SCHS-SHUTDOWN-BIND" in question
