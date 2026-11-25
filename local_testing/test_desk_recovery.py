#!/usr/bin/env python3
"""Desk composes over read-only places while the Practice is in recovery.

A linked Desk starts on a volume whose home holds no Practice head, so the
activation finds no head and enters recovery, narrowing every place of its
set to read-only.  Desk then composes its stores and the applets it was
asked to start, as it does outside recovery, with two exceptions: it builds
no Agent runtime and no sandbox, and it refuses to start the Agent.  The
profile queues a reader applet, which records whether its places are all
read-only, and an applet with the Agent's component id.  It checks what
Desk composed, that the applet catalog is read-only, that a launch of the
Agent is refused with DESK-LAUNCH-E-RECOVERY, and that Desk's teardown
returns the stack depth, heap and extended memory it found.  Machine trust
is composed first, as a boot composition composes it, since KDOS keeps the
global root set for the boot.

The profile runs through the harness's smoke command, on the emulator, with
its captures (screen text, cells, PNG and the raw transcript) under
``OUTPUT_ROOT``, which this test points at its own temporary folder.
"""

from __future__ import annotations

from pathlib import Path
import sys

import pytest

LOCAL_TESTING = Path(__file__).resolve().parent
sys.path.insert(0, str(LOCAL_TESTING))

import akashic_tui as harness  # noqa: E402

PROFILE = "desk-recovery"
COLS, ROWS = 100, 32
MAX_STEPS = 12_000_000_000
TIMEOUT = 480.0

AUTOEXEC = r'''\ autoexec.f - Desk composes in a Practice's recovery
ENTER-USERLAND
REQUIRE tui/applets/desk/desk.f
." DR-REQUIRE" CR

VARIABLE _dr-fails
VARIABLE _dr-checks
\ Count a check; report its number when FLAG is false.
: _dr-check  ( flag n -- )
    1 _dr-checks +!
    SWAP IF DROP EXIT THEN
    1 _dr-fails +! ." DESK RECOVERY ASSERT " . CR ;

\ Extended memory free: the unclaimed tail and every block on the free list.
VARIABLE _dr-xfree
VARIABLE _dr-xwalk
: _dr-xmem-available  ( -- u )
    0 _dr-xfree ! 0 _dr-xwalk ! XMEM-FL @
    BEGIN DUP _dr-xwalk @ 4096 < AND WHILE
        DUP @ _dr-xfree +! 8 + @
        1 _dr-xwalk +!
    REPEAT
    0= 30 _dr-check
    XMEM-FREE _dr-xfree @ + ;

\ Whether every place of SET is read-only.
: _dr-read-only?  ( set -- flag )
    -1 SWAP PLSET-FIRST BEGIN ?DUP WHILE
        DUP PLACE-WRITABLE? IF NIP 0 SWAP THEN PLACE-NEXT
    REPEAT ;

\ A reader applet that needs its home and the documents place, and an
\ applet with the Agent's component id.
CREATE _dr-comp-r COMP-DESC ALLOT
CREATE _dr-app-r APP-DESC ALLOT
CREATE _dr-comp-a COMP-DESC ALLOT
CREATE _dr-app-a APP-DESC ALLOT
VARIABLE _dr-reader
VARIABLE _dr-reader-ro
VARIABLE _dr-agent-starts
: _dr-reader-init  ( instance -- )
    DUP _dr-reader !
    CINST-PLACES ?DUP IF _dr-read-only? ELSE 0 THEN _dr-reader-ro ! ;
: _dr-agent-init  ( instance -- )
    DROP 1 _dr-agent-starts +! ;
: _dr-fill  ( -- )
    _dr-comp-r COMP-DESC-INIT
    S" test.desk.recovery.reader" _dr-comp-r COMP.ID-U ! _dr-comp-r COMP.ID-A !
    PLACES-NEED-HOME PLACES-NEED-DOCUMENTS OR _dr-comp-r COMP.PLACE-NEEDS !
    _dr-app-r APP-DESC-INIT _dr-comp-r _dr-app-r APP.COMP-DESC !
    ['] _dr-reader-init _dr-app-r APP.INIT-XT !
    S" <uidl><region><label id=reader text=R/></region></uidl>"
        _dr-app-r APP.UIDL-U ! _dr-app-r APP.UIDL-A !
    _dr-comp-a COMP-DESC-INIT
    S" org.akashic.agent" _dr-comp-a COMP.ID-U ! _dr-comp-a COMP.ID-A !
    _dr-app-a APP-DESC-INIT _dr-comp-a _dr-app-a APP.COMP-DESC !
    ['] _dr-agent-init _dr-app-a APP.INIT-XT !
    S" <uidl><region><label id=agent text=A/></region></uidl>"
        _dr-app-a APP.UIDL-U ! _dr-app-a APP.UIDL-A ! ;
_dr-fill

VARIABLE _dr-desk
VARIABLE _dr-id
VARIABLE _dr-ior
: _dr-cases  ( -- )
    DESK-RECOVERY? 1 _dr-check
    DESK-PRACTICE 0= 2 _dr-check
    PLACES-DEFAULT _dr-read-only? 3 _dr-check
    \ The reader started, over places that are all read-only.
    _dr-reader @ 0<> 4 _dr-check
    _dr-reader-ro @ 5 _dr-check
    \ The Agent did not start, and nothing of it or of the sandbox exists.
    _dr-agent-starts @ 0= 6 _dr-check
    DESK-SLOT-COUNT 1 = 7 _dr-check
    _DESK-AGENT-RUNTIME @ 0= 8 _dr-check
    _DESK-TOOL-GATEWAY @ 0= 9 _dr-check
    _DESK-SANDBOX @ 0= 10 _dr-check
    \ The catalog serves its built-ins and keeps nothing new.
    DESK-CATALOG ?DUP IF ACAT-READONLY? ELSE 0 THEN 11 _dr-check
    \ Daybook's document is named from the Practice, so Desk hosts none.
    _DESK-DAYBOOK-OWNER @ 0= 15 _dr-check
    \ Asked again, Desk refuses the Agent and starts nothing.
    _dr-app-a DESK-TRY-LAUNCH _dr-ior ! _dr-id !
    _dr-ior @ DESK-LAUNCH-E-RECOVERY = 12 _dr-check
    _dr-agent-starts @ 0= 13 _dr-check
    DESK-SLOT-COUNT 1 = 14 _dr-check ;
: _dr-driver  ( -- )
    _dr-desk @ DESK-INIT-CB
    _dr-cases ;
: _dr-desk-init  ( desk-instance -- )
    _dr-desk !
    ['] _dr-driver CATCH ?DUP IF
        1 _dr-fails +! ." DESK RECOVERY DRIVER THROW " . CR
    THEN
    ASHELL-QUIT ;

_DESK-FILL-DESC
' _dr-desk-init DESK-DESC APP.INIT-XT !
_dr-app-r DESK-QUEUE-LAUNCH
_dr-app-a DESK-QUEUE-LAUNCH

\ The machine's trust, composed before the baseline as a boot composition
\ composes it: the global root set read from the origin, then the freeze.
\ KDOS keeps the root set for the boot, so the balance measures only what
\ Desk takes and gives back; Desk then finds the registry frozen.
: _dr-machine-trust  ( -- )
    PLACES-DEFAULT DUP 0= ABORT" DESK RECOVERY FAIL no places"
    PLSET-ORIGIN DUP 0= ABORT" DESK RECOVERY FAIL no origin"
    WEB-ROOTS-REGISTER MTRUST-S-OK <> ABORT" DESK RECOVERY FAIL root set"
    MTRUST-FREEZE MTRUST-S-OK <> ABORT" DESK RECOVERY FAIL machine trust" ;
_dr-machine-trust

VARIABLE _dr-depth
VARIABLE _dr-heap
VARIABLE _dr-xmem
: _dr-shell-run  ( -- ) DESK-DESC ASHELL-RUN ;
DEPTH _dr-depth !
HEAP-FREE-BYTES _dr-heap !
_dr-xmem-available _dr-xmem !
' _dr-shell-run CATCH ?DUP IF
    1 _dr-fails +! ." DESK RECOVERY SHELL THROW " . CR
THEN
DEPTH _dr-depth @ = 20 _dr-check
HEAP-FREE-BYTES DUP _dr-heap @ <> IF
    ." DESK RECOVERY HEAP " DUP . ." expected " _dr-heap @ . CR
THEN
_dr-heap @ = 21 _dr-check
_dr-xmem-available DUP _dr-xmem @ <> IF
    ." DESK RECOVERY XMEM " DUP . ." expected " _dr-xmem @ . CR
THEN
_dr-xmem @ = 22 _dr-check

_dr-fails @ 0= IF
    ." DESK RECOVERY PASS " _dr-checks @ .
ELSE
    ." DESK RECOVERY FAIL " _dr-fails @ .
THEN CR
'''


def test_desk_composes_over_read_only_places_in_recovery(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    monkeypatch.setattr(harness, "OUTPUT_ROOT", tmp_path)
    monkeypatch.setitem(harness.PROFILES, PROFILE, harness.Profile(
        roots=("tui/applets/desk/desk.f",),
        resources=(),
        autoexec=AUTOEXEC,
        ready_markers=("DESK RECOVERY PASS",),
        stable_markers=("DESK RECOVERY PASS",),
        failure_markers=(
            "DESK RECOVERY FAIL",
            "DESK RECOVERY ASSERT",
            "DESK RECOVERY DRIVER THROW",
            "DESK RECOVERY SHELL THROW",
        ),
        linked=True,
        include_large_sample=False,
        total_sectors=16384,
    ))
    image = harness.build_image(PROFILE, tmp_path / "desk-recovery.img")
    assert harness.smoke(
        PROFILE,
        image,
        cols=COLS,
        rows=ROWS,
        max_steps=MAX_STEPS,
        timeout=TIMEOUT,
    )
