#!/usr/bin/env python3
"""Linked characterization of the current Desk launch and layout host.

This is intentionally a test-only contract.  It pins the failure outcomes,
rollback shape, retryability, tiling, focus/minimize/fullframe behavior, and
UIDL-context isolation across the host extraction.
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path


LOCAL_TESTING = Path(__file__).resolve().parent
sys.path.insert(0, str(LOCAL_TESTING))

import akashic_tui as harness  # noqa: E402


PROFILE = "desk-host-characterization"
IMAGE = Path("/tmp/akashic-desk-host-characterization.img")

AUTOEXEC = r'''\ autoexec.f - current Desk host characterization
ENTER-USERLAND
REQUIRE tui/applets/desk/desk.f
." DH-M1-REQUIRE" CR

VARIABLE _dh-fails
VARIABLE _dh-checks
VARIABLE _dh-depth
: _dh-assert  ( flag -- )
    1 _dh-checks +!
    0= IF 1 _dh-fails +! ." DESK HOST ASSERT " _dh-checks @ . CR THEN ;
: _dh-stack  ( -- )
    DEPTH DUP _dh-depth @ <> IF
        ." DESK HOST STACK " _dh-depth @ . ." -> " DUP . CR .S CR
    THEN
    _dh-depth @ = _dh-assert ;

\ A healthy blank Practice is the only persistence prerequisite of a real
\ Desk instance.  Existing media is never rewritten.
CREATE _dh-practice-head PHEAD-SIZE ALLOT
CREATE _dh-practice-out PHEAD-SIZE ALLOT
CREATE _dh-practice-store PHEADVFS-SIZE ALLOT
: _dh-practice-id!  ( value id -- ) DUP RID-CLEAR ! ;
: _dh-practice-slot?  ( path-a path-u -- flag )
    VFS-OPEN DUP IF VFS-CLOSE -1 ELSE DROP 0 THEN ;
: _dh-practice-present?  ( -- flag )
    S" /practice-head-a.bin" _dh-practice-slot?
    S" /practice-head-b.bin" _dh-practice-slot? OR ;
: _dh-practice-provision  ( -- )
    _dh-practice-present? IF EXIT THEN
    VFS-CUR _dh-practice-store PHEADVFS-INIT PHEADVFS-S-OK = _dh-assert
    _dh-practice-out _dh-practice-store PHEADVFS-LOAD
        PHEADVFS-S-RECOVERY = _dh-assert
    _dh-practice-head PHEAD-INIT
    1 _dh-practice-head PHEAD.ID _dh-practice-id!
    2 _dh-practice-head PHEAD.CURRENT-ROOT _dh-practice-id!
    _dh-practice-head _dh-practice-store PHEADVFS-REINITIALIZE
        PHEADVFS-S-OK = _dh-assert ;
_dh-practice-provision
." DH-M2-PROVISION" CR

VARIABLE _dh-desk
VARIABLE _dh-id
VARIABLE _dh-ior
VARIABLE _dh-heap
VARIABLE _dh-xmem
VARIABLE _dh-regn
VARIABLE _dh-next
VARIABLE _dh-xfree
VARIABLE _dh-xwalk

: _dh-xmem-available  ( -- u )
    0 _dh-xfree ! 0 _dh-xwalk ! XMEM-FL @
    BEGIN DUP _dh-xwalk @ 4096 < AND WHILE
        DUP @ _dh-xfree +! 8 + @
        1 _dh-xwalk +!
    REPEAT
    DUP 0= _dh-assert DROP
    XMEM-FREE _dh-xfree @ + ;
: _dh-snapshot  ( -- )
    HEAP-FREE-BYTES _dh-heap !
    _dh-xmem-available _dh-xmem !
    _DESK-REGISTRY @ CREG.INST-N @ _dh-regn !
    _DESK-NEXT-ID @ _dh-next ! ;
: _dh-try  ( desc -- )
    DESK-TRY-LAUNCH _dh-ior ! _dh-id ! ;
: _dh-structural-clean  ( -- )
    DESK-SLOT-COUNT 0= _dh-assert
    _DESK-HEAD @ 0= _dh-assert
    _DESK-FOCUS-SA @ 0= _dh-assert
    _DESK-LAST-MIN-SA @ 0= _dh-assert
    ASHELL-ACTIVE-CTX 0= _dh-assert
    _DESK-REGISTRY @ CREG.INST-N @ _dh-regn @ = _dh-assert
    HEAP-FREE-BYTES DUP _dh-heap @ <> IF
        ." DH-HEAP " DUP . ." expected " _dh-heap @ . CR
    THEN
    _dh-heap @ = _dh-assert ;
: _dh-memory-clean  ( -- )
    _dh-structural-clean
    _dh-xmem-available DUP _dh-xmem @ <> IF
        ." DH-XMEM " DUP . ." expected " _dh-xmem @ . CR
    THEN
    _dh-xmem @ = _dh-assert ;

CREATE _dh-comp COMP-DESC ALLOT
CREATE _dh-app APP-DESC ALLOT
: _dh-base-fill  ( -- )
    _dh-comp COMP-DESC-INIT
    S" test.desk.host.failure" _dh-comp COMP.ID-U ! _dh-comp COMP.ID-A !
    _dh-app APP-DESC-INIT
    _dh-comp _dh-app APP.COMP-DESC ! ;

: _dh-retry  ( -- )
    _dh-base-fill _dh-snapshot
    _dh-app _dh-try
    _dh-ior @ 0= _dh-assert
    _dh-id @ _dh-next @ = _dh-assert
    DESK-SLOT-COUNT 1 = _dh-assert
    _dh-id @ _DESK-FIND-ID 0<> _dh-assert
    _dh-id @ APP-CLOSE-R-WINDOW DESK-REQUEST-CLOSE-ID
        APP-CLOSE-D-ALLOW = _dh-assert
    _DESK-NEXT-ID @ _dh-next @ 1+ = _dh-assert
    _dh-memory-clean ;

: _dh-state-fail  ( state -- ior ) DROP 77 ;

VARIABLE _dh-save-arena
VARIABLE _dh-save-free
VARIABLE _dh-save-arena-n
VARIABLE _dh-save-xfl
VARIABLE _dh-save-xhere
VARIABLE _dh-probe
VARIABLE _dh-injected-throw

: _dh-call-app-try  ( -- ) _dh-app _dh-try ;
: _dh-registry-fault  ( -- )
    CREG-MAX-INSTANCES _DESK-REGISTRY @ CREG.INST-N !
    _dh-call-app-try ;
: _dh-xmem-fault  ( -- )
    0 XMEM-FL !
    80 ALLOCATE DUP 0= _dh-assert DROP DUP _dh-probe ! FREE
    XMEM-LIMIT @ XMEM-HERE !
    _dh-call-app-try ;
: _dh-uctx-fault  ( -- )
    0 _UCTX-ARENA ! 0 _UCTX-FREELIST !
    _UCTX-MAX-ARENAS _UCTX-ARENA-N !
    _dh-call-app-try ;

VARIABLE _dh-fi
VARIABLE _dh-fi-inits
VARIABLE _dh-fi-activates
VARIABLE _dh-fi-shutdowns
: _dh-fi-activate  ( instance -- )
    _dh-fi ! 1 _dh-fi-activates +! ;
: _dh-fi-context?  ( -- flag )
    S" failed-init-marker" UTUI-BY-ID 0<> ;
: _dh-fi-init  ( instance -- )
    _dh-fi @ = _dh-assert _dh-fi-context? _dh-assert
    1 _dh-fi-inits +! -1709 THROW ;
: _dh-fi-shutdown  ( instance -- )
    _dh-fi @ = _dh-assert _dh-fi-context? _dh-assert
    1 _dh-fi-shutdowns +! ;

: _dh-failure-cases  ( -- )
    \ Invalid descriptor: canonical Desk validation outcome, no ID consumed.
    _dh-snapshot 0 _dh-try
    _dh-id @ -1 = _dh-assert _dh-ior @ DESK-LAUNCH-E-DESC = _dh-assert
    _DESK-NEXT-ID @ _dh-next @ = _dh-assert _dh-memory-clean
    _dh-retry

    \ Component state construction returns CINST's current raw status.
    _dh-base-fill 8 _dh-comp COMP.STATE-SIZE !
    ['] _dh-state-fail _dh-comp COMP.STATE-INIT-XT !
    _dh-snapshot _dh-app _dh-try
    _dh-id @ -1 = _dh-assert _dh-ior @ COMP-E-INIT = _dh-assert
    _DESK-NEXT-ID @ _dh-next @ = _dh-assert _dh-memory-clean
    _dh-retry

    \ Registry saturation currently propagates CREG-E-FULL unchanged.
    _dh-base-fill _dh-snapshot
    ['] _dh-registry-fault CATCH _dh-injected-throw !
    _dh-regn @ _DESK-REGISTRY @ CREG.INST-N !
    _dh-injected-throw @ ?DUP IF THROW THEN
    _dh-id @ -1 = _dh-assert _dh-ior @ CREG-E-FULL = _dh-assert
    _DESK-NEXT-ID @ _dh-next @ = _dh-assert _dh-memory-clean
    _dh-retry

    \ Isolate one exact 80-byte instance block, exhaust the bump tail, and
    \ let the following 88-byte slot allocation fail naturally.  Restoring
    \ both allocator roots discards the temporary probe after rollback.
    _dh-base-fill _dh-snapshot
    XMEM-FL @ _dh-save-xfl ! XMEM-HERE @ _dh-save-xhere !
    ['] _dh-xmem-fault CATCH _dh-injected-throw !
    _dh-save-xhere @ XMEM-HERE ! _dh-save-xfl @ XMEM-FL !
    _dh-injected-throw @ ?DUP IF THROW THEN
    _dh-id @ -1 = _dh-assert _dh-ior @ -1 = _dh-assert
    _DESK-NEXT-ID @ _dh-next @ = _dh-assert _dh-memory-clean
    _dh-retry

    \ Exhausting the UCTX arena is canonicalized by Desk.  Slot IDs are
    \ assigned immediately before this boundary and therefore advance once.
    _dh-base-fill
    S" <uidl><region><label id=context-marker text=C/></region></uidl>"
        _dh-app APP.UIDL-U ! _dh-app APP.UIDL-A !
    _dh-snapshot
    _UCTX-ARENA @ _dh-save-arena !
    _UCTX-FREELIST @ _dh-save-free !
    _UCTX-ARENA-N @ _dh-save-arena-n !
    ['] _dh-uctx-fault CATCH _dh-injected-throw !
    _dh-save-arena @ _UCTX-ARENA !
    _dh-save-free @ _UCTX-FREELIST !
    _dh-save-arena-n @ _UCTX-ARENA-N !
    _dh-injected-throw @ ?DUP IF THROW THEN
    _dh-id @ -1 = _dh-assert _dh-ior @ DESK-LAUNCH-E-CONTEXT = _dh-assert
    _DESK-NEXT-ID @ _dh-next @ 1+ = _dh-assert _dh-memory-clean
    _dh-retry

    \ Malformed inline UIDL and a missing UIDL file share the current public
    \ Desk UIDL outcome.  Each rollback recycles its exact UCTX.
    _dh-base-fill
    \ This incomplete root tag is the existing terminating bad-XML fixture;
    \ nested truncated tags exercise markup recovery rather than host rollback.
    S" <bad"
        _dh-app APP.UIDL-U ! _dh-app APP.UIDL-A !
    _dh-snapshot _dh-app _dh-try
    _dh-id @ -1 = _dh-assert _dh-ior @ DESK-LAUNCH-E-UIDL = _dh-assert
    _DESK-NEXT-ID @ _dh-next @ 1+ = _dh-assert
    _UCTX-FREELIST @ 0<> _dh-assert _dh-structural-clean
    _dh-retry

    _dh-base-fill
    S" /definitely-missing-desk-host.uidl"
        _dh-app APP.UIDL-FILE-U ! _dh-app APP.UIDL-FILE-A !
    _dh-snapshot _UCTX-FREELIST @ _dh-save-free !
    _dh-app _dh-try
    _dh-id @ -1 = _dh-assert _dh-ior @ DESK-LAUNCH-E-UIDL = _dh-assert
    _DESK-NEXT-ID @ _dh-next @ 1+ = _dh-assert
    _UCTX-FREELIST @ _dh-save-free @ = _dh-assert _dh-structural-clean
    _dh-retry

    \ An INIT throw is retained, shutdown runs once in the same UIDL context,
    \ and the failed slot is wholly removed before the caller sees the error.
    0 _dh-fi-inits ! 0 _dh-fi-activates ! 0 _dh-fi-shutdowns !
    _dh-base-fill
    ['] _dh-fi-activate _dh-app APP.ACTIVATE-XT !
    ['] _dh-fi-init _dh-app APP.INIT-XT !
    ['] _dh-fi-shutdown _dh-app APP.SHUTDOWN-XT !
    S" <uidl><region><label id=failed-init-marker text=F/></region></uidl>"
        _dh-app APP.UIDL-U ! _dh-app APP.UIDL-A !
    _dh-snapshot _UCTX-FREELIST @ _dh-save-free !
    _dh-app _dh-try
    _dh-id @ -1 = _dh-assert _dh-ior @ -1709 = _dh-assert
    _DESK-NEXT-ID @ _dh-next @ 1+ = _dh-assert
    _dh-fi-inits @ 1 = _dh-assert
    _dh-fi-activates @ 3 = _dh-assert
    _dh-fi-shutdowns @ 1 = _dh-assert
    _UCTX-FREELIST @ _dh-save-free @ = _dh-assert
    _dh-structural-clean
    _dh-retry
    ;

\ Two long-lived children characterize exact layout and context behavior.
CREATE _dh-comp-a COMP-DESC ALLOT
CREATE _dh-comp-b COMP-DESC ALLOT
CREATE _dh-app-a APP-DESC ALLOT
CREATE _dh-app-b APP-DESC ALLOT
VARIABLE _dh-ai VARIABLE _dh-bi
VARIABLE _dh-aid VARIABLE _dh-bid
VARIABLE _dh-as VARIABLE _dh-bs
VARIABLE _dh-au VARIABLE _dh-bu
VARIABLE _dh-shutdown-a VARIABLE _dh-shutdown-b
VARIABLE _dh-er VARIABLE _dh-ec VARIABLE _dh-eh VARIABLE _dh-ew

: _dh-ctx-a?  ( -- flag )
    S" host-marker-a" UTUI-BY-ID 0<>
    S" host-marker-b" UTUI-BY-ID 0= AND ;
: _dh-ctx-b?  ( -- flag )
    S" host-marker-b" UTUI-BY-ID 0<>
    S" host-marker-a" UTUI-BY-ID 0= AND ;
: _dh-activate-a  ( instance -- ) _dh-ai ! ;
: _dh-activate-b  ( instance -- ) _dh-bi ! ;
: _dh-init-a  ( instance -- )
    _dh-ai @ = _dh-assert _dh-ctx-a? _dh-assert ;
: _dh-init-b  ( instance -- )
    _dh-bi @ = _dh-assert _dh-ctx-b? _dh-assert ;
: _dh-shutdown-a-cb  ( instance -- )
    _dh-ai @ = _dh-assert _dh-ctx-a? _dh-assert
    1 _dh-shutdown-a +! ;
: _dh-shutdown-b-cb  ( instance -- )
    _dh-bi @ = _dh-assert _dh-ctx-b? _dh-assert
    1 _dh-shutdown-b +! ;
: _dh-fill-sentinels  ( -- )
    _dh-comp-a COMP-DESC-INIT
    S" test.desk.host.a" _dh-comp-a COMP.ID-U ! _dh-comp-a COMP.ID-A !
    _dh-app-a APP-DESC-INIT _dh-comp-a _dh-app-a APP.COMP-DESC !
    ['] _dh-activate-a _dh-app-a APP.ACTIVATE-XT !
    ['] _dh-init-a _dh-app-a APP.INIT-XT !
    ['] _dh-shutdown-a-cb _dh-app-a APP.SHUTDOWN-XT !
    S" <uidl><region><label id=host-marker-a text=A/></region></uidl>"
        _dh-app-a APP.UIDL-U ! _dh-app-a APP.UIDL-A !
    _dh-comp-b COMP-DESC-INIT
    S" test.desk.host.b" _dh-comp-b COMP.ID-U ! _dh-comp-b COMP.ID-A !
    _dh-app-b APP-DESC-INIT _dh-comp-b _dh-app-b APP.COMP-DESC !
    ['] _dh-activate-b _dh-app-b APP.ACTIVATE-XT !
    ['] _dh-init-b _dh-app-b APP.INIT-XT !
    ['] _dh-shutdown-b-cb _dh-app-b APP.SHUTDOWN-XT !
    S" <uidl><region><label id=host-marker-b text=B/></region></uidl>"
        _dh-app-b APP.UIDL-U ! _dh-app-b APP.UIDL-A ! ;

: _dh-region=  ( slot row col h w -- flag )
    _dh-ew ! _dh-eh ! _dh-ec ! _dh-er !
    _SL-RGN @ DUP 0= IF DROP 0 EXIT THEN
    DUP RGN-ROW _dh-er @ =
    OVER RGN-COL _dh-ec @ = AND
    OVER RGN-H _dh-eh @ = AND
    SWAP RGN-W _dh-ew @ = AND ;
: _dh-sentinel-a-stable?  ( -- flag )
    _dh-aid @ _DESK-FIND-ID DUP _dh-as @ =
    OVER _SL-INST @ _dh-ai @ = AND
    SWAP _SL-UCTX @ _dh-au @ = AND ;
: _dh-sentinel-b-stable?  ( -- flag )
    _dh-bid @ _DESK-FIND-ID DUP _dh-bs @ =
    OVER _SL-INST @ _dh-bi @ = AND
    SWAP _SL-UCTX @ _dh-bu @ = AND ;
: _dh-sentinels-stable?  ( -- flag )
    _dh-sentinel-a-stable? _dh-sentinel-b-stable? AND ;
: _dh-isolation  ( -- )
    _dh-as @ _DESK-CTX-SWITCH
    ASHELL-ACTIVE-CTX _dh-au @ = _dh-assert _dh-ctx-a? _dh-assert
    _dh-bs @ _DESK-CTX-SWITCH
    ASHELL-ACTIVE-CTX _dh-bu @ = _dh-assert _dh-ctx-b? _dh-assert ;

: _dh-layout-cases  ( -- )
    _dh-fill-sentinels
    0 _dh-shutdown-a ! 0 _dh-shutdown-b !
    _dh-snapshot
    _dh-app-a DESK-LAUNCH _dh-aid !
    _dh-app-b DESK-LAUNCH _dh-bid !
    _dh-aid @ _DESK-FIND-ID DUP _dh-as ! DUP _SL-UCTX @ _dh-au ! DROP
    _dh-bid @ _DESK-FIND-ID DUP _dh-bs ! DUP _SL-UCTX @ _dh-bu ! DROP
    SCR-W 100 = _dh-assert SCR-H 32 = _dh-assert
    DESK-SLOT-COUNT 2 = _dh-assert DESK-VCOUNT 2 = _dh-assert
    _DESK-VH @ 0= _dh-assert
    _DESK-FOCUS-SA @ _dh-as @ = _dh-assert
    _dh-as @ _SL-STATE @ _ST-FOCUSED = _dh-assert
    _dh-bs @ _SL-STATE @ _ST-RUNNING = _dh-assert
    _dh-as @ 0 0 31 49 _dh-region= _dh-assert
    _dh-bs @ 0 50 31 50 _dh-region= _dh-assert
    _dh-sentinels-stable? _dh-assert _dh-isolation

    _dh-bid @ DESK-FOCUS-ID
    _DESK-FOCUS-SA @ _dh-bs @ = _dh-assert
    _dh-as @ _SL-STATE @ _ST-RUNNING = _dh-assert
    _dh-bs @ _SL-STATE @ _ST-FOCUSED = _dh-assert
    _dh-sentinels-stable? _dh-assert

    DESK-TOGGLE-VH
    _DESK-VH @ -1 = _dh-assert
    _dh-as @ 0 0 15 100 _dh-region= _dh-assert
    _dh-bs @ 16 0 15 100 _dh-region= _dh-assert
    _dh-sentinels-stable? _dh-assert _dh-isolation
    DESK-TOGGLE-VH
    _DESK-VH @ 0= _dh-assert
    _dh-as @ 0 0 31 49 _dh-region= _dh-assert
    _dh-bs @ 0 50 31 50 _dh-region= _dh-assert

    _dh-bid @ DESK-MINIMIZE-ID
    _dh-bs @ _SL-STATE @ _ST-MINIMIZED = _dh-assert
    _DESK-LAST-MIN-SA @ _dh-bs @ = _dh-assert
    _DESK-FOCUS-SA @ _dh-as @ = _dh-assert
    _dh-as @ _SL-STATE @ _ST-FOCUSED = _dh-assert
    _dh-as @ 0 0 31 100 _dh-region= _dh-assert
    _dh-bs @ _SL-RGN @ 0= _dh-assert
    DESK-VCOUNT 1 = _dh-assert _dh-sentinels-stable? _dh-assert
    _dh-as @ _DESK-CTX-SWITCH _dh-ctx-a? _dh-assert

    DESK-RESTORE
    _dh-bs @ _SL-STATE @ _ST-RUNNING = _dh-assert
    _DESK-LAST-MIN-SA @ 0= _dh-assert
    _DESK-FOCUS-SA @ _dh-as @ = _dh-assert
    _dh-as @ 0 0 31 49 _dh-region= _dh-assert
    _dh-bs @ 0 50 31 50 _dh-region= _dh-assert
    _dh-sentinels-stable? _dh-assert _dh-isolation

    _dh-bid @ DESK-FOCUS-ID
    -1 DESK-FULLFRAME!
    _DESK-FULLFRAME @ -1 = _dh-assert DESK-VCOUNT 2 = _dh-assert
    _dh-desk @ DESK-PAINT-CB
    _dh-as @ _SL-DIRTY @ -1 = _dh-assert
    _dh-bs @ _SL-DIRTY @ 0= _dh-assert
    0 DESK-FULLFRAME!
    _dh-desk @ DESK-PAINT-CB
    _DESK-FULLFRAME @ 0= _dh-assert
    _dh-as @ _SL-DIRTY @ 0= _dh-assert
    _dh-bs @ _SL-DIRTY @ 0= _dh-assert
    _dh-sentinels-stable? _dh-assert _dh-isolation

    _dh-aid @ APP-CLOSE-R-WINDOW DESK-REQUEST-CLOSE-ID
        APP-CLOSE-D-ALLOW = _dh-assert
    _dh-shutdown-a @ 1 = _dh-assert _dh-shutdown-b @ 0= _dh-assert
    DESK-SLOT-COUNT 1 = _dh-assert
    _dh-bid @ _DESK-FIND-ID _dh-bs @ = _dh-assert
    _dh-bs @ _SL-INST @ _dh-bi @ = _dh-assert
    _dh-bs @ _SL-UCTX @ _dh-bu @ = _dh-assert
    _dh-bs @ 0 0 31 100 _dh-region= _dh-assert
    _dh-bs @ _DESK-CTX-SWITCH _dh-ctx-b? _dh-assert
    _dh-bid @ APP-CLOSE-R-WINDOW DESK-REQUEST-CLOSE-ID
        APP-CLOSE-D-ALLOW = _dh-assert
    _dh-shutdown-b @ 1 = _dh-assert
    _dh-memory-clean
    ;

: _dh-driver-body  ( -- )
    _dh-desk @ DESK-INIT-CB
    DEPTH _dh-depth !
    _dh-failure-cases
    _dh-stack
    _dh-layout-cases
    _dh-stack ;

: _dh-desk-init  ( desk-instance -- )
    _dh-desk !
    ['] _dh-driver-body CATCH ?DUP IF
        1 _dh-fails +! ." DESK HOST DRIVER THROW " . CR
    THEN
    ASHELL-QUIT ;

_DESK-FILL-DESC
' _dh-desk-init DESK-DESC APP.INIT-XT !
: _dh-shell-run  ( -- ) DESK-DESC ASHELL-RUN ;
' _dh-shell-run CATCH ?DUP IF
    1 _dh-fails +! ." DESK HOST SHELL THROW " . CR
THEN

_dh-fails @ 0= IF
    ." DESK HOST CHARACTERIZATION PASS " _dh-checks @ .
ELSE
    ." DESK HOST CHARACTERIZATION FAIL " _dh-fails @ .
THEN CR
'''


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--timeout", type=float, default=480.0)
    args = parser.parse_args()
    harness.PROFILES[PROFILE] = harness.Profile(
        roots=("tui/applets/desk/desk.f",),
        resources=(),
        autoexec=AUTOEXEC,
        ready_markers=("DESK HOST CHARACTERIZATION PASS",),
        stable_markers=("DESK HOST CHARACTERIZATION PASS",),
        failure_markers=(
            "DESK HOST CHARACTERIZATION FAIL",
            "DESK HOST ASSERT",
            "DESK HOST STACK",
            "DESK HOST DRIVER THROW",
            "DESK HOST SHELL THROW",
        ),
        linked=True,
        include_large_sample=False,
    )
    image = harness.build_image(PROFILE, IMAGE)
    ok = harness.smoke(
        PROFILE,
        image,
        cols=100,
        rows=32,
        max_steps=12_000_000_000,
        timeout=args.timeout,
    )
    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
