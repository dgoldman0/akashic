#!/usr/bin/env python3
"""Desk's keyring: its prompts, its ticks and its notices (desk.f).

The suite loads Desk natively and drives its keyring words over a fresh
Desk state block, a real prompt and a real keyring on a RAM volume of its
own, typing into the prompt as keys do.  Desk opens the keyring in its own
home; its setup prompt checks a new passphrase's length and that both
entries match, starts the setup at Desk's count, and leaves no passphrase
in the prompt or in Desk; its ticks run the derivation and tell how far it
has come, and the screen's Cancel stops it.  A keyring something asked
while locked brings the unlock prompt, which asks again after a wrong
passphrase and stops asking on Escape.  The screen's own rows are
test_desk_keyring_surface.py's; the overlay and the prompt on a running
Desk run in Desk's smokes.
"""

from __future__ import annotations

from pathlib import Path

import pytest

from native_forth import NativeForth


LOCAL_TESTING = Path(__file__).resolve().parent

PRELUDE = (LOCAL_TESTING / "test-root-place.f").read_text(encoding="utf-8") + r"""
_DESK-STATE-SIZE ALLOCATE THROW CONSTANT _T-DS
: T-DESK  ( -- ) _T-DS _DESK-STATE-SIZE 0 FILL  _T-DS _DESK-CURRENT-STATE ! ;
\ A RAM volume, and a set whose home is a place over its root.
: T-VOLUME  ( -- set )
    2097152 A-XMEM ARENA-NEW THROW VFS-RAM-BINDING 0 VFS-NEW THROW
    S" tkr" _t-root-set ;
T-VOLUME CONSTANT T-SET
T-SET PLSET-HOME CONSTANT T-PLACE
0 0 1 80 RGN-NEW CONSTANT T-RGN
\ A fresh Desk with its prompt, as Desk makes it, and a keyring over FILE.
: T-START  ( file-a file-u -- )
    T-DESK
    T-RGN _DESK-AGENT-PROMPT-BUF _DESK-AGENT-PROMPT-CAP PRM-NEW
    ['] _DESK-AGENT-PROMPT-SUBMIT OVER PRM-ON-SUBMIT
    ['] _DESK-AGENT-PROMPT-CANCEL OVER PRM-ON-CANCEL
    _DESK-AGENT-PROMPT !
    KEYRING-SIZE ALLOCATE THROW >R
    T-PLACE R@ KEYRING-INIT THROW R> _DESK-KEYRING ! ;
: T-END  ( -- ) _DESK-KEYRING-FINI _DESK-AGENT-PROMPT @ PRM-FREE ;
\ Keys into Desk's prompt, as the shell hands them over.
CREATE T-EV 32 ALLOT
: T-KEY  ( code type -- )
    T-EV 32 0 FILL T-EV ! T-EV 8 + ! T-EV _DESK-AGENT-PROMPT @ WDG-HANDLE DROP ;
: T-TYPE  ( a u -- ) OVER + SWAP ?DO I C@ KEY-T-CHAR T-KEY LOOP ;
: T-ENTER  ( -- ) KEY-ENTER KEY-T-SPECIAL T-KEY ;
: T-ESC  ( -- ) KEY-ESC KEY-T-SPECIAL T-KEY ;
: T-ZERO?  ( a u -- flag ) 0 -ROT OVER + SWAP ?DO I C@ OR LOOP 0= ;
: T-MODE.  ( -- ) _DESK-PROMPT-MODE @ . ;
: T-ACTIVE.  ( -- ) _DESK-AGENT-PROMPT @ PRM-ACTIVE? . ;
: T-MASK.  ( -- ) _DESK-AGENT-PROMPT @ _PRM-O-INPUT + @ INP-MASK@ . ;
: T-TEXT.  ( -- ) _DESK-AGENT-PROMPT @ PRM-GET-TEXT NIP . ;
\ Whether no passphrase is left in the prompt's buffer or in Desk.
: T-WIPED.  ( -- )
    _DESK-AGENT-PROMPT-BUF _DESK-AGENT-PROMPT-CAP T-ZERO?
    _DESK-KEYRING-FIRST _DESK-AGENT-PROMPT-CAP T-ZERO? AND
    _DESK-KEYRING-FIRST-U @ 0= AND . ;
: T-NOTICE.  ( -- ) _ASHELL-TOAST-MSG 2@ TYPE ;
: T-STATE.  ( -- ) _DESK-KEYRING @ KEYRING-STATE@ . ;
\ Desk's ticks until the derivation it started ends.
: T-RUN  ( -- ) BEGIN _DESK-KEYRING-OP @ WHILE _DESK-KEYRING-TICK REPEAT ;
\ The keyring's own steps, without Desk.
: T-STEPS  ( -- status )
    BEGIN 64 _DESK-KEYRING @ KEYRING-STEP DUP KEYRING-S-PENDING = WHILE DROP REPEAT ;
: T-CONSUME  ( key u context -- status ) 2DROP DROP 0 ;
"""

# Desk's net modules use the constants MegaPad's networking module defines.
SUITE = NativeForth(("tui/applets/desk/desk.f",), system_modules=("networking.f",),
                    prelude=tuple(PRELUDE.strip().splitlines()),
                    load_steps=1_500_000_000)


@pytest.fixture(scope="module")
def desk():
    return SUITE.shared()


def run(desk, lines: list[str], max_steps: int = 400_000_000) -> list[str]:
    output = desk.run(lines, max_steps).decode("latin-1")
    assert "??" not in output, output[-3000:]
    return [line.rstrip() for line in output.replace("\r", "").split("\n")
            if line.strip()]


def test_desk_opens_the_keyring_in_its_own_home(desk):
    rows = run(desk, [
        "T-DESK T-SET _DESK-OWN-PLACES ! _DESK-KEYRING-INIT",
        "_DESK-KEYRING-STATUS @ . _DESK-KEYRING @ 0<> . T-STATE. CR",
        "_DESK-KEYRING-FINI _DESK-KEYRING @ . CR",
        # Without a home there is no keyring, and the screen says so.
        "0 _DESK-OWN-PLACES ! _DESK-KEYRING-INIT _DESK-KEYRING @ . CR",
        "_DESK-SHOW-KEYRING T-NOTICE. CR",
        "KEYRING-S-CORRUPT _DESK-KEYRING-STATUS ! _DESK-SHOW-KEYRING T-NOTICE. CR",
    ])
    assert rows == [
        "0 -1 0",
        "0",
        "0",
        "The keyring is unavailable",
        "The keyring file is damaged",
    ]


def test_a_setup_asks_twice_and_keeps_no_passphrase(desk):
    rows = run(desk, [
        'S" /setup" T-START T-STATE. CR',
        "_DESK-PM-SETUP _DESK-KEYRING-ASK T-MODE. T-ACTIVE. T-MASK. CR",
        # Too short: asked for afresh.
        'S" short" T-TYPE T-ENTER T-MODE. T-ACTIVE. T-TEXT. CR T-NOTICE. CR',
        # The first entry is kept, and asked for again.
        'S" correct horse" T-TYPE T-ENTER T-MODE. T-ACTIVE. T-TEXT. CR',
        # A different second entry asks for both again, keeping neither.
        'S" correct horsf" T-TYPE T-ENTER T-MODE. T-WIPED. CR T-NOTICE. CR',
        'S" correct horse" T-TYPE T-ENTER S" correct horse" T-TYPE T-ENTER',
        "T-MODE. T-ACTIVE. T-MASK. T-WIPED. _DESK-KEYRING-OP @ . T-STATE. CR",
        # Desk's count; the start ran the first iteration.
        "_DESK-KEYRING @ KEYRING-PROGRESS . . CR",
        "_DESK-KEYRING-TICK T-NOTICE. CR",
        "_DESK-KEYRING @ KEYRING-PROGRESS DROP . CR",
        # The screen's Cancel stops it, and the keyring is as it was.
        "KRS-CANCEL _DESK-KEYRING-CARRY-OUT T-NOTICE. CR",
        "T-STATE. _DESK-KEYRING-OP @ . CR T-END",
    ])
    assert rows == [
        "0",
        "2 -1 42",
        "2 -1 0",
        "A passphrase takes at least 8 characters",
        "3 -1 0",
        "2 -1",
        "The two passphrases differ",
        "0 0 0 -1 1 3",
        "100000 1",
        "Setting up the keyring: 0%",
        "1001",
        "Stopped; the keyring is as it was",
        "0 0",
    ]


def test_a_wanted_keyring_asks_for_its_passphrase(desk):
    rows = run(desk, [
        'S" /unlock" T-START',
        'S" correct horse" 64 _DESK-KEYRING @ KEYRING-SETUP DROP T-STEPS .',
        "_DESK-KEYRING @ KEYRING-LOCK T-STATE. CR",
        # Nothing asked for the key: Desk asks for nothing.
        "_DESK-KEYRING-TICK T-ACTIVE. CR",
        # Something asks the locked keyring for its key.
        "_DESK-KEYRING @ KEYRING-ID ' T-CONSUME 0 _DESK-KEYRING @ KEYRING-RESOLVER .",
        "_DESK-KEYRING @ KEYRING-WANTED? . CR",
        "_DESK-KEYRING-TICK T-MODE. T-ACTIVE. T-MASK. CR",
        # A wrong passphrase: taken, wiped, and asked for again.
        'S" wrong horse" T-TYPE T-ENTER T-MODE. _DESK-KEYRING-OP @ . T-WIPED. CR',
        "T-RUN T-NOTICE. CR T-MODE. T-ACTIVE. T-STATE. CR",
        # Escape stops asking until something asks again.
        "T-ESC T-MODE. T-ACTIVE. _DESK-KEYRING @ KEYRING-WANTED? . T-WIPED. CR",
        "_DESK-KEYRING-TICK T-ACTIVE. CR",
        # The screen's Unlock, with the right passphrase.
        "KRS-UNLOCK _DESK-KEYRING-CARRY-OUT T-MODE. T-ACTIVE. CR",
        'S" correct horse" T-TYPE T-ENTER T-RUN T-NOTICE. CR',
        "T-STATE. _DESK-KEYRING @ KEYRING-WANTED? . T-WIPED. CR",
        "KRS-LOCK _DESK-KEYRING-CARRY-OUT T-NOTICE. CR T-STATE. CR T-END",
    ])
    assert rows == [
        "0 1",
        "0",
        "5 -1",
        "1 -1 42",
        "0 2 -1",
        "Wrong passphrase",
        "1 -1 1",
        "0 0 0 -1",
        "0",
        "1 -1",
        "Keyring unlocked",
        "5 0 -1",
        "Keyring locked",
        "1",
    ]


def test_a_change_runs_in_desks_ticks(desk):
    rows = run(desk, [
        'S" /change" T-START',
        'S" correct horse" 64 _DESK-KEYRING @ KEYRING-SETUP DROP T-STEPS . CR',
        "KRS-CHANGE _DESK-KEYRING-CARRY-OUT T-MODE. T-ACTIVE. CR",
        'S" battery staple" T-TYPE T-ENTER S" battery staple" T-TYPE T-ENTER',
        "T-MODE. T-WIPED. _DESK-KEYRING-OP @ . T-STATE. CR",
        "_DESK-KEYRING-TICK T-NOTICE. CR",
        # Stopped, the keyring is unlocked under its old passphrase.
        "KRS-CANCEL _DESK-KEYRING-CARRY-OUT T-STATE. _DESK-KEYRING @ KEYRING-ITERATIONS@ . CR",
        "T-END",
    ])
    assert rows == [
        "0",
        "4 -1",
        "0 -1 4 4",
        "Changing the passphrase: 0%",
        "5 64",
    ]
