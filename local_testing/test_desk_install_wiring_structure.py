#!/usr/bin/env python3
"""Static contracts for the question before an install.

The applet builder installs only a project the user allowed; Pad asks
instead of installing and builds once the answer allows it; Desk shows the
question through its one screen slot, before the sandbox's and the
schedules' questions, and its screen answers the builder.
"""

from __future__ import annotations

import re
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
TUI = REPO_ROOT / "akashic" / "tui"
DESK = TUI / "applets" / "desk" / "desk.f"
SURFACE = TUI / "applets" / "desk" / "install-surface.f"
PAD = TUI / "applets" / "pad" / "pad.f"
BUILDER = TUI / "app-builder.f"


def _source(path: Path) -> str:
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


def test_the_builder_installs_only_what_was_allowed() -> None:
    builder = _source(BUILDER)
    install = _definition(builder, "ABUILD-INSTALL")
    _in_order(install, "_ab-busy @ IF", "_AB-ALLOWED? 0= IF",
              "ABUILD-E-UNCONFIRMED", "ABUILD-WITHDRAW", "_ab-place !",
              "_AB-INSTALL-BODY")
    allowed = _definition(builder, "_AB-ALLOWED?")
    _in_order(allowed, "ABUILD-Q-ALLOWED <>", "_ab-q-place @ <>", "COMPARE 0=")


def test_pad_asks_and_builds_once_allowed() -> None:
    pad = _source(PAD)
    start = _definition(pad, "_PAD-DO-BUILD-INSTALL")
    assert "_PAD-BUILD-ASK" in start and "ABUILD-INSTALL" not in start
    ask = _definition(pad, "_PAD-BUILD-ASK")
    _in_order(ask, "ABUILD-ASK", "_PAD-BUILD-PATH SWAP MOVE", "-1 _PAD-BUILD-ASKED !")
    tick = _definition(pad, "_PAD-BUILD-TICK")
    _in_order(tick, "_PAD-BUILD-ASKED @ 0= IF EXIT THEN", "ABUILD-QUESTION@",
              "ABUILD-Q-ALLOWED OF _PAD-BUILD-RUN", "ABUILD-Q-REFUSED OF",
              "ABUILD-WITHDRAW")
    run = _definition(pad, "_PAD-BUILD-RUN")
    assert "_PAD-BUILD-PATH _PAD-BUILD-PATH-U @ _PAD-BUILD-PLACE @" in run
    assert "ABUILD-INSTALL" in run
    assert "_PAD-BUILD-TICK" in _definition(pad, "PAD-TICK-CB")
    shutdown = _definition(pad, "PAD-SHUTDOWN-CB")
    assert "_PAD-BUILD-ASKED @ IF ABUILD-WITHDRAW" in shutdown


def test_desk_shows_the_question_in_its_screen_slot() -> None:
    desk = _source(DESK)
    surface = _source(SURFACE)
    assert "REQUIRE install-surface.f" in desk
    assert "LST-NEW" in surface
    for word in ("APT1", "PT-", "RICH", "DRW-", "PRM-"):
        assert not re.search(rf"(?<![\w-]){re.escape(word)}", surface), word
    assert "ABUILD-STATEMENT" in surface
    service = _definition(surface, "KIS-SERVICE")
    _in_order(service, "ABUILD-QUESTION@ ABUILD-Q-ASKING <>", "_KIS-C-INSTALL = ABUILD-ANSWER")

    tick = _definition(desk, "_DESK-SCREENS-TICK")
    _in_order(tick, "_DESK-SCREEN-ID @ IF _DESK-SCREEN-SERVICE EXIT THEN",
              "PRM-ACTIVE?",
              "ABUILD-QUESTION@ ABUILD-Q-ASKING = IF _DESK-SHOW-INSTALL-QUESTION",
              "SBOX-CAPABILITY-ASK", "SBRK-ASKING")
    screen = _definition(desk, "_DESK-SCREEN-SERVICE")
    _in_order(screen, "KIS-OVERLAY?", "KIS-SERVICE IF _DESK-SCREEN-CLOSE THEN",
              "SBXS-OVERLAY?")
    assert "KIS-OVERLAY? IF KIS-BOX" in _definition(desk, "_DESK-OVERLAY-BOX")
    show = _definition(desk, "_DESK-SHOW-INSTALL-QUESTION")
    _in_order(show, "KIS-DESC _DESK-HOST AHOST-TRY-LAUNCH-OVERLAY",
              "_DESK-SCREEN-ID !", "KIS-BIND")
