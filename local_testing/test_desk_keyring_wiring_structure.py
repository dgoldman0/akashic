#!/usr/bin/env python3
"""Static contracts for how Desk hosts the passphrase keyring.

Desk opens the keyring in its own home once its stores' places exist,
wipes it before its prompt goes, runs its derivation in the tick before
the other screens, opens its screen with Alt+K through the one screen
slot, and asks for passphrases in its own prompt, masked, wiping each
entry as soon as the keyring has taken it.
"""

from __future__ import annotations

import re
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
DESK = REPO_ROOT / "akashic" / "tui" / "applets" / "desk" / "desk.f"
SURFACE = REPO_ROOT / "akashic" / "tui" / "applets" / "desk" / "keyring-surface.f"


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


def test_desk_keeps_the_keyring_in_its_own_home() -> None:
    source = _source()
    assert "REQUIRE keyring-surface.f" in source
    assert 'S" /keyring.bin"' in _definition(source, "_DESK-KEYRING$")
    init = _definition(source, "_DESK-KEYRING-INIT")
    _in_order(init, "_DESK-OWN-PLACES _DESK-HOME-IN", "KEYRING-SIZE ALLOCATE",
              "R@ KEYRING-INIT", "DUP _DESK-KEYRING-STATUS !", "R> _DESK-KEYRING !")
    interop = _definition(source, "_DESK-INTEROP-INIT")
    _in_order(interop, "_DESK-STORE-PLACES-INIT", "_DESK-KEYRING-INIT")

    fini = _definition(source, "_DESK-KEYRING-FINI")
    _in_order(fini, "_DESK-KEYRING-PROMPT-END", "KEYRING-FINI FREE")
    teardown = _definition(source, "_DESK-INTEROP-FINI-QUIESCED")
    _in_order(teardown, "_DESK-KEYRING-FINI", "_DESK-AGENT-PROMPT @ ?DUP IF PRM-FREE",
              "_DESK-STORE-PLACES-FREE")


def test_the_keyring_runs_in_the_tick_before_the_screens() -> None:
    source = _source()
    tick = _definition(source, "DESK-TICK-CB")
    _in_order(tick, "_DESK-KEYRING-TICK", "_DESK-SCREENS-TICK", "_DESK-HOST AHOST-TICK")
    keyring_tick = _definition(source, "_DESK-KEYRING-TICK")
    # A choice waits for its screen to close; a derivation runs a budget a
    # tick; a wanted keyring is asked for only with nothing else open.
    _in_order(keyring_tick, "DUP PRM-ACTIVE? IF DROP ELSE _DESK-KEYRING-PROMPT-END",
              "_DESK-KEYRING-CHOSEN @ ?DUP IF", "_DESK-SCREEN-ID @ IF",
              "_DESK-KEYRING-CARRY-OUT",
              "_DESK-KEYRING-BUDGET _DESK-KEYRING @ KEYRING-STEP",
              "KEYRING-WANTED? 0= IF EXIT THEN",
              "_DESK-LAUNCHER-ID @ _DESK-SCREEN-ID @ OR",
              "PRM-ACTIVE? IF EXIT THEN", "KEYRING-STATE@ CASE")
    assert re.search(r"(\d+) CONSTANT _DESK-KEYRING-BUDGET", source)


def test_the_keyring_screen_shares_desks_screen_slot() -> None:
    source = _source()
    surface = _source(SURFACE)
    assert "LST-NEW" in surface
    for word in ("APT1", "PT-", "RICH", "DRW-", "PRM-"):
        assert not re.search(rf"(?<![\w-]){re.escape(word)}", surface), word
    # The screen asks for no passphrase and changes no keyring.
    for word in ("KEYRING-UNLOCK", "KEYRING-SETUP", "KEYRING-CHANGE",
                 "KEYRING-LOCK", "KEYRING-CANCEL"):
        assert not re.search(rf"(?<![\w-]){re.escape(word)}(?![\w-])", surface), word

    service = _definition(source, "_DESK-SCREEN-SERVICE")
    _in_order(service, "KRS-OVERLAY?", "_DESK-KEYRING-SCREEN-SERVICE", "SBXS-OVERLAY?")
    keyring_service = _definition(source, "_DESK-KEYRING-SCREEN-SERVICE")
    _in_order(keyring_service, "KRS-SERVICE", "KRS-CHOSEN _DESK-KEYRING-CHOSEN !",
              "_DESK-SCREEN-CLOSE")
    box = _definition(source, "_DESK-OVERLAY-BOX")
    assert "KRS-OVERLAY? IF KRS-BOX" in box
    show = _definition(source, "_DESK-SHOW-KEYRING")
    _in_order(show, "_DESK-LAUNCHER-ID @ _DESK-SCREEN-ID @ OR",
              "KRS-DESC _DESK-HOST AHOST-TRY-LAUNCH-OVERLAY", "_DESK-SCREEN-ID !",
              "KRS-BIND")

    shortcut = _definition(source, "_DESK-SHORTCUT?")
    assert re.search(r"107\s+_DESK-ALT\?\s+IF\s+DROP\s+_DESK-SHOW-KEYRING", shortcut)


def test_passphrases_go_through_desks_masked_prompt() -> None:
    source = _source()
    submit = _definition(source, "_DESK-AGENT-PROMPT-SUBMIT")
    _in_order(submit, "_DESK-KEYRING-PROMPT? IF _DESK-KEYRING-PROMPT-SUBMIT EXIT THEN",
              "ARUNTIME-SEND")
    cancel = _definition(source, "_DESK-AGENT-PROMPT-CANCEL")
    assert cancel.index("_DESK-KEYRING-PROMPT-CANCEL") < cancel.index("DROP ASHELL-DIRTY!")
    ask = _definition(source, "_DESK-AGENT-PROMPT-SUBMIT")
    assert "PRM-MASK" not in ask
    show_agent = _definition(source, "_DESK-SHOW-AGENT-PROMPT")
    _in_order(show_agent, "_DESK-KEYRING-PROMPT-END", 'S" Ask:"')

    keyring_ask = _definition(source, "_DESK-KEYRING-ASK")
    _in_order(keyring_ask, "PRM-WIPE", "42 R@ PRM-MASK!", "PRM-SHOW")
    end = _definition(source, "_DESK-KEYRING-PROMPT-END")
    _in_order(end, "PRM-WIPE", "0 SWAP PRM-MASK!", "_DESK-PM-ASK _DESK-PROMPT-MODE !",
              "_DESK-KEYRING-FIRST-WIPE")
    assert "_DESK-AGENT-PROMPT-CAP 0 FILL" in _definition(source, "_DESK-KEYRING-FIRST-WIPE")

    # Each entry leaves the prompt as soon as the keyring has taken it.
    unlock = _definition(source, "_DESK-KEYRING-UNLOCK-SUBMIT")
    _in_order(unlock, "PRM-GET-TEXT", "_DESK-KEYRING @ KEYRING-UNLOCK",
              "SWAP _DESK-KEYRING-PROMPT-END")
    again = _definition(source, "_DESK-KEYRING-AGAIN-SUBMIT")
    _in_order(again, "COMPARE", "KEYRING-SETUP", "KEYRING-CHANGE", "KEYRING-START-OVER",
              "ROT _DESK-KEYRING-PROMPT-END", "_DESK-KEYRING-STARTED")
    assert "KEYRING-ITERATIONS-DEFAULT" in again
    first = _definition(source, "_DESK-KEYRING-NEW-SUBMIT")
    _in_order(first, "_DESK-UTF8-CHARS _DESK-KEYRING-MIN-CHARS <",
              "_DESK-KEYRING-FIRST SWAP MOVE", "_DESK-PROMPT-MODE @ 1+ _DESK-KEYRING-ASK")
    # Escape stops Desk asking until something asks the keyring again.
    assert "KEYRING-WANT-CLEAR" in _definition(source, "_DESK-KEYRING-PROMPT-CANCEL")
