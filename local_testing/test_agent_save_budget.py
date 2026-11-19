#!/usr/bin/env python3
"""The Agent's save budget while a run streams.

While a run streams, the runtime saves its conversation again no sooner than
500 ms after its last save and no sooner than nine times as long as that save
took (docs/tui/applets/agent/persistence.md).  The machine's clock stays at
zero here, so a save takes no time and each case sets the time of the next
allowed save itself.
"""

from __future__ import annotations

from pathlib import Path

from native_forth import NativeForth

ROOT_PLACE = tuple(
    (Path(__file__).resolve().parent / "test-root-place.f")
    .read_text(encoding="utf-8").splitlines()
)

AGENT = NativeForth(
    (
        "tui/applets/agent/storage/vfs-conversation.f",
        "tui/applets/agent/runtime.f",
        "tui/applets/agent/providers/devtools/scripted.f",
    ),
    prelude=ROOT_PLACE + (
        "VARIABLE VA  VARIABLE R",
        "524288 A-XMEM ARENA-NEW IF -1 THROW THEN",
        "VFS-RAM-BINDING 0 VFS-NEW ?DUP IF THROW THEN VA !",
        ": T-OPEN  ( -- )",
        "    SCRIPTED-SOURCE-NEW THROW APSOURCE-PROVIDER-NEW THROW",
        "    ARUNTIME-NEW THROW R !",
        '    VA @ S" ag" _t-root-place AVFSSTORE-NEW',
        "        ACSTORE-S-OK <> IF -1 THROW THEN",
        "    R @ ARUNTIME-CONVERSATION-STORE! ACSTORE-S-OK <> IF -1 THROW THEN ;",
        # A change to the conversation the runtime has not saved yet.
        ": T-CHANGE  ( -- )  1 R @ ARUNTIME.CONVERSATION @ ACONV.REVISION +! ;",
        ": T-STREAMING  ( -- )  ARUN-S-RUNNING R @ ARUNTIME.STATUS !  T-CHANGE ;",
        ": SAVED?  ( -- flag )",
        "    R @ ARUNTIME.PERSISTED-REVISION @",
        "    R @ ARUNTIME.CONVERSATION @ ACONV.REVISION @ = ;",
    ),
)


def result(lines: list[str], max_steps: int = 2_000_000_000) -> str:
    raw = AGENT.run(['." RESULT: "', *lines, "CR"], max_steps)
    text = "".join(chr(b) if 0x20 <= b < 0x7F or b in (10, 13, 9) else ""
                   for b in raw)
    assert "RESULT:" in text, text[-600:]
    tail = text.rsplit("RESULT:", 1)[1]
    assert "??" not in tail, tail
    return " ".join(tail.split())


def test_the_next_save_waits_nine_times_the_last_saves_duration():
    """A 550 ms save puts the next one 4,950 ms after its end; a 10 ms
    save, or one that took no time, still waits 500 ms."""
    assert result([
        "1000 1550 _ARUNTIME-NEXT-PERSIST .",
        "1000 1010 _ARUNTIME-NEXT-PERSIST .",
        "0 0 _ARUNTIME-NEXT-PERSIST .",
    ]) == "6500 1510 500"


def test_a_streaming_run_saves_only_once_its_budget_has_passed():
    """Binding the store saves the first snapshot and sets the next save's
    time; a streaming change before it stays unsaved, and one after it
    saves and sets the time again."""
    assert result([
        ": T  T-OPEN  R @ ARUNTIME.NEXT-PERSIST-MS @ .",
        "     T-STREAMING  R @ ARUNTIME-PERSIST ACSTORE-S-OK = .  SAVED? .",
        "     -1 R @ ARUNTIME.NEXT-PERSIST-MS !",
        "     R @ ARUNTIME-PERSIST ACSTORE-S-OK = .  SAVED? .",
        "     R @ ARUNTIME.NEXT-PERSIST-MS @ .  DEPTH . ;",
        "T",
    ]) == "500 -1 0 -1 -1 500 0"


def test_a_runtime_that_is_not_streaming_saves_at_once():
    """Outside a streaming run the budget does not apply, however far off
    the next streaming save is."""
    assert result([
        ": T  T-OPEN  1000000 R @ ARUNTIME.NEXT-PERSIST-MS !  T-CHANGE",
        "     R @ ARUNTIME.STATUS @ ARUN-S-RUNNING <> .",
        "     R @ ARUNTIME-PERSIST ACSTORE-S-OK = .  SAVED? .  DEPTH . ;",
        "T",
    ]) == "-1 -1 -1 0"


def test_a_forced_save_ignores_the_budget():
    """The saves the runtime makes at once, a prompt's start, an approval,
    clearing and shutdown, go through ARUNTIME-PERSIST-FORCE."""
    assert result([
        ": T  T-OPEN  1000000 R @ ARUNTIME.NEXT-PERSIST-MS !  T-STREAMING",
        "     R @ ARUNTIME-PERSIST-FORCE ACSTORE-S-OK = .  SAVED? .",
        "     R @ ARUNTIME.NEXT-PERSIST-MS @ .  DEPTH . ;",
        "T",
    ]) == "-1 -1 500 0"
