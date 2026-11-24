#!/usr/bin/env python3
"""tui/applets/desk/keyring-surface.f: Desk's screen for the keyring.

The suite drives the screen's state over a real passphrase keyring on a
RAM volume of its own, without a screen: the rows each state of the
keyring offers and their text, the status line and a derivation's share
done, the rows following the keyring when its state moves, Enter choosing
a row's action and Escape choosing none.  The overlay's drawing and
Desk's prompts run in Desk's smokes.
"""

from __future__ import annotations

from pathlib import Path

import pytest

from native_forth import NativeForth


LOCAL_TESTING = Path(__file__).resolve().parent

PRELUDE = (LOCAL_TESTING / "test-root-place.f").read_text(encoding="utf-8") + r"""
CREATE KS-RAW _KRS-SIZE 7 + ALLOT  KS-RAW 7 + -8 AND CONSTANT KS
CREATE KI COMP-INST ALLOT  KI COMP-INST 0 FILL  KS KI CINST.STATE !
VARIABLE KR  VARIABLE KRGN
2097152 A-XMEM ARENA-NEW THROW VFS-RAM-BINDING 0 VFS-NEW THROW
S" ks" _t-root-place CONSTANT KPLACE
KEYRING-SIZE ALLOCATE THROW KR !
\ The keyring over FILE, read afresh.
: K-OPEN  ( file-a file-u -- )
    KR @ KEYRING-FINI KPLACE KR @ KEYRING-INIT . ;
\ Run the derivation to its end.
: K-RUN  ( -- status )
    BEGIN 64 KR @ KEYRING-STEP DUP KEYRING-S-PENDING = WHILE DROP REPEAT ;
\ The screen's state over the keyring, with its list, as Desk binds it.
: LIST-ON  ( -- )
    KS _KRS-SIZE 0 FILL  KR @ KS _KRS.KEYRING !
    0 0 6 60 RGN-NEW DUP KRGN !
    ['] _KRS-KEY ['] _KRS-FIELD LST-NEW
    ['] _KRS-OPENED OVER LST-ON-OPEN
    _KRS-COLUMNS 1 2 PICK LST-COLUMNS!
    KS OVER LST-CONTEXT! KS _KRS.LIST !
    KS _KRS-ROWS KS _KRS-STATUS! ;
: LIST-OFF  ( -- )
    KS _KRS.LIST @ ?DUP IF LST-FREE THEN 0 KS _KRS.LIST !
    KRGN @ ?DUP IF RGN-FREE THEN 0 KRGN ! ;
\ The rows, as the list shows them, then the status line.
: ROWS.  ( -- )
    KS _KRS.LIST @ LST-COUNT 0 ?DO
        I 0 KS _KRS.LIST @ _KRS-FIELD TYPE ." |"
    LOOP CR ;
: STATUS.  ( -- ) KS _KRS.STATUS KS _KRS.STATUS-U @ TYPE CR ;
: SCREEN.  ( -- ) KS _KRS-ROWS KS _KRS-STATUS! ROWS. STATUS. ;
\ Enter on row INDEX; then what the service says, and the action chosen.
: OPEN-ROW  ( index -- ) KS _KRS.LIST @ _KRS-OPENED ;
: SERVICE.  ( -- ) KI KRS-SERVICE . KI KRS-CHOSEN . CR ;
CREATE EV 24 ALLOT
: ESCAPE  ( -- ) KEY-T-SPECIAL EV ! KEY-ESC EV 8 + ! 0 EV 16 + ! EV KI _KRS-EVENT . ;
"""

SUITE = NativeForth(
    ("tui/applets/desk/keyring-surface.f", "utils/fs/vfs.f"),
    prelude=tuple(PRELUDE.strip().splitlines()),
)


@pytest.fixture(scope="module")
def forth():
    return SUITE.shared()


def run(forth, lines: list[str], max_steps: int = 2_000_000_000) -> list[str]:
    output = forth.run(lines, max_steps).decode("latin-1")
    assert "??" not in output, output[-3000:]
    return [line.rstrip() for line in output.replace("\r", "").split("\n")
            if line.strip()]


def test_each_state_offers_its_rows(forth):
    rows = run(forth, [
        # Not set up: one row, and the status says no passphrase is set.
        'S" /k1" K-OPEN CR LIST-ON SCREEN.',
        # Setting up: Cancel, with the share done.
        'S" correct horse" 64 KR @ KEYRING-SETUP . CR SCREEN.',
        '16 KR @ KEYRING-STEP . CR SCREEN.',
        # Unlocked: Lock now, then Change the passphrase.
        'K-RUN . CR SCREEN.',
        # Locked: Unlock.
        'KR @ KEYRING-LOCK SCREEN.',
        # Unlocking: Cancel again.
        'S" correct horse" KR @ KEYRING-UNLOCK . CR SCREEN.',
        'K-RUN . CR SCREEN. LIST-OFF',
    ])
    assert rows == [
        "0",
        "Set up a passphrase|",
        "No passphrase is set. Set one up to keep secrets on this machine.",
        "3",
        "Cancel|",
        "Setting up: 1%",
        "3",
        "Cancel|",
        "Setting up: 26%",
        "0",
        "Lock now|Change the passphrase|",
        "Unlocked. Applets can open the secrets they saved.",
        "Unlock|",
        "Locked. Unlock it so that applets can open their saved secrets.",
        "3",
        "Cancel|",
        "Unlocking: 1%",
        "0",
        "Lock now|Change the passphrase|",
        "Unlocked. Applets can open the secrets they saved.",
    ]


def test_a_changing_keyring_says_so(forth):
    rows = run(forth, [
        'S" /k2" K-OPEN CR LIST-ON',
        'S" correct horse" 64 KR @ KEYRING-SETUP DROP K-RUN DROP',
        'S" battery staple" 96 KR @ KEYRING-CHANGE . CR SCREEN. LIST-OFF',
    ])
    assert rows == [
        "0",
        "3",
        "Cancel|",
        "Changing the passphrase: 1%",
    ]


def test_enter_chooses_and_escape_closes(forth):
    rows = run(forth, [
        'S" /k3" K-OPEN CR LIST-ON',
        # Nothing chosen yet: the screen stays.
        'SERVICE.',
        '0 OPEN-ROW SERVICE.',
        'S" correct horse" 64 KR @ KEYRING-SETUP DROP K-RUN DROP',
        'LIST-OFF LIST-ON 0 OPEN-ROW SERVICE.',
        'LIST-OFF LIST-ON 1 OPEN-ROW SERVICE.',
        # A row past the state's rows chooses nothing.
        'LIST-OFF LIST-ON 2 OPEN-ROW SERVICE.',
        'KR @ KEYRING-LOCK LIST-OFF LIST-ON 0 OPEN-ROW SERVICE.',
        'S" correct horse" KR @ KEYRING-UNLOCK DROP',
        'LIST-OFF LIST-ON 0 OPEN-ROW SERVICE. KR @ KEYRING-CANCEL',
        # Escape closes with no action.
        'LIST-OFF LIST-ON ESCAPE CR SERVICE. LIST-OFF',
    ])
    # The actions: NONE 0, SETUP 1, UNLOCK 2, LOCK 3, CHANGE 4, CANCEL 5.
    assert rows == [
        "0",
        "0 0",
        "-1 1",
        "-1 3",
        "-1 4",
        "0 0",
        "-1 2",
        "-1 5",
        "-1",
        "-1 0",
    ]


def test_the_rows_follow_the_keyring(forth):
    rows = run(forth, [
        'S" /k4" K-OPEN CR LIST-ON',
        'S" correct horse" 64 KR @ KEYRING-SETUP DROP',
        # The screen made its rows while the key was derived; the
        # derivation ends, and the next activation finds a new state.
        'KS _KRS-ROWS ROWS. K-RUN DROP',
        'KS _KRS-KEYRING-STATE KS _KRS.STATE @ <> . CR',
        'KS _KRS-ROWS ROWS. KS _KRS.LIST @ LST-SELECTED . CR LIST-OFF',
    ])
    assert rows == [
        "0",
        "Cancel|",
        "-1",
        "Lock now|Change the passphrase|",
        "0",
    ]
