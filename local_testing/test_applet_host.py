#!/usr/bin/env python3
"""Focused linked guest contract for the generic caller-owned applet host."""

from __future__ import annotations

import argparse
import sys
from pathlib import Path


LOCAL_TESTING = Path(__file__).resolve().parent
sys.path.insert(0, str(LOCAL_TESTING))

import akashic_tui as harness  # noqa: E402


PROFILE = "applet-host-contracts"
IMAGE = Path("/tmp/akashic-applet-host-contracts.img")

AUTOEXEC = r'''\ autoexec.f - generic applet-host contracts
ENTER-USERLAND
REQUIRE tui/applet-host/host.f
." AH-M1-REQUIRE" CR

VARIABLE _ah-fails
VARIABLE _ah-checks
VARIABLE _ah-depth
: _ah-assert  ( flag -- )
    1 _ah-checks +!
    0= IF 1 _ah-fails +! ." APPLET HOST ASSERT " _ah-checks @ . CR THEN ;
: _ah-stack  ( -- )
    DEPTH DUP _ah-depth @ <> IF
        ." APPLET HOST STACK " _ah-depth @ . ." -> " DUP . CR .S CR
    THEN
    _ah-depth @ = _ah-assert ;

CREATE _ah-host AHOST-SIZE ALLOT
CREATE _ah-context 8 ALLOT
CREATE _ah-endpoint 8 ALLOT
VARIABLE _ah-reg
VARIABLE _ah-screen
VARIABLE _ah-relayouts
VARIABLE _ah-layout-index
VARIABLE _ah-heap-before
VARIABLE _ah-xmem-before
VARIABLE _ah-xfree
VARIABLE _ah-xwalk

VARIABLE _ah-inst-a
VARIABLE _ah-inst-b
VARIABLE _ah-id-a
VARIABLE _ah-id-b
VARIABLE _ah-launch-id
VARIABLE _ah-launch-ior
VARIABLE _ah-slot-a
VARIABLE _ah-slot-b
VARIABLE _ah-state-inits
VARIABLE _ah-state-finis
VARIABLE _ah-inits
VARIABLE _ah-activates
VARIABLE _ah-events-a
VARIABLE _ah-events-b
VARIABLE _ah-ticks-a
VARIABLE _ah-ticks-b
VARIABLE _ah-paints-a
VARIABLE _ah-paints-b
VARIABLE _ah-requests
VARIABLE _ah-shutdowns-a
VARIABLE _ah-shutdowns-b
VARIABLE _ah-releases-a
VARIABLE _ah-releases-b
VARIABLE _ah-closed-a
VARIABLE _ah-closed-b
VARIABLE _ah-close-mode
VARIABLE _ah-close-target
VARIABLE _ah-close-reason
VARIABLE _ah-expected-close-reason
VARIABLE _ah-relayout-before

: _ah-known-instance?  ( instance -- flag )
    DUP _ah-inst-a @ = SWAP _ah-inst-b @ = OR ;

: _ah-xmem-available  ( -- u )
    0 _ah-xfree ! 0 _ah-xwalk ! XMEM-FL @
    BEGIN DUP _ah-xwalk @ 4096 < AND WHILE
        DUP @ _ah-xfree +! 8 + @
        1 _ah-xwalk +!
    REPEAT
    DUP 0= _ah-assert DROP
    XMEM-FREE _ah-xfree @ + ;
: _ah-memory-snapshot  ( -- )
    HEAP-FREE-BYTES _ah-heap-before !
    _ah-xmem-available _ah-xmem-before ! ;
: _ah-memory-clean  ( -- )
    HEAP-FREE-BYTES DUP _ah-heap-before @ <> IF
        ." APPLET HOST HEAP " DUP . ." expected " _ah-heap-before @ . CR
    THEN
    _ah-heap-before @ = _ah-assert
    _ah-xmem-available DUP _ah-xmem-before @ <> IF
        ." APPLET HOST XMEM " DUP . ." expected " _ah-xmem-before @ . CR
    THEN
    _ah-xmem-before @ = _ah-assert ;

\ The host owns no layout policy.  This injected policy frees superseded
\ regions, then assigns two deliberately nonadjacent caller-chosen tiles.
: _ah-relayout  ( context -- )
    _ah-context = _ah-assert
    1 _ah-relayouts +! 0 _ah-layout-index !
    _ah-host AHOST.HEAD @
    BEGIN ?DUP WHILE
        DUP AHS.RGN DUP @ ?DUP IF RGN-FREE THEN 0 SWAP !
        DUP AHS-VISIBLE? IF
            _ah-layout-index @ 0= IF 2 3 5 7 ELSE 10 20 6 8 THEN
            RGN-NEW OVER AHS.RGN !
            1 _ah-layout-index +!
        THEN
        AHS.NEXT @
    REPEAT ;

: _ah-relayout-without-region  ( context -- )
    _ah-context = _ah-assert
    1 _ah-relayouts +! ;

: _ah-state-init  ( state -- ior )
    DUP 0<> _ah-assert
    0xA110CA7E SWAP !
    1 _ah-state-inits +! 0 ;
: _ah-state-fini  ( state -- )
    @ 0xA110CA7E = _ah-assert
    1 _ah-state-finis +! ;

CREATE _ah-comp COMP-DESC ALLOT
CREATE _ah-app APP-DESC ALLOT

: _ah-init  ( instance -- )
    DUP CINST-DESC _ah-comp = _ah-assert
    DUP CINST-STATE @ 0xA110CA7E = _ah-assert
    DUP CINST.ENDPOINT @ _ah-endpoint = _ah-assert
    _ah-inst-a @ 0= IF
        DUP _ah-inst-a !
    ELSE
        DUP _ah-inst-b !
    THEN
    DROP 1 _ah-inits +! ;

: _ah-activate  ( instance -- )
    _ah-known-instance? _ah-assert
    1 _ah-activates +! ;

: _ah-event  ( event instance -- handled? )
    DUP _ah-inst-a @ = IF
        1 _ah-events-a +!
    ELSE
        DUP _ah-inst-b @ = _ah-assert
        1 _ah-events-b +!
    THEN
    DROP
    DUP 778 = IF DROP ASHELL-QUIT 0 EXIT THEN
    777 = _ah-assert -1 ;

: _ah-tick  ( instance -- )
    DUP _ah-inst-a @ = IF
        DROP 1 _ah-ticks-a +!
    ELSE
        _ah-inst-b @ = _ah-assert
        1 _ah-ticks-b +!
    THEN ;

: _ah-paint  ( instance -- )
    DUP _ah-inst-a @ = IF
        DROP 1 _ah-paints-a +!
    ELSE
        _ah-inst-b @ = _ah-assert
        1 _ah-paints-b +!
    THEN ;

: _ah-request-close  ( reason instance -- decision )
    _ah-close-target @ = _ah-assert
    DUP _ah-close-reason ! _ah-expected-close-reason @ = _ah-assert
    1 _ah-requests +!
    _ah-close-mode @ CASE
        0 OF APP-CLOSE-D-CANCEL ENDOF
        1 OF APP-CLOSE-D-DEFER ENDOF
        2 OF -77 THROW ENDOF
        3 OF 99 ENDOF
        APP-CLOSE-D-ALLOW SWAP
    ENDCASE ;

: _ah-shutdown  ( instance -- )
    DUP _ah-inst-a @ = IF
        DROP 1 _ah-shutdowns-a +!
    ELSE
        _ah-inst-b @ = _ah-assert
        1 _ah-shutdowns-b +!
    THEN ;

: _ah-release  ( instance context -- ior )
    _ah-context = _ah-assert
    DUP _ah-inst-a @ = IF
        _ah-shutdowns-a @ 1 = _ah-assert
        1 _ah-releases-a +!
    ELSE
        DUP _ah-inst-b @ = _ah-assert
        _ah-shutdowns-b @ 1 = _ah-assert
        1 _ah-releases-b +!
    THEN
    DROP 0 ;

: _ah-closed  ( slot-id context -- )
    _ah-context = _ah-assert
    DUP _ah-id-a @ = IF
        _ah-releases-a @ 1 = _ah-assert
        1 _ah-closed-a +!
    ELSE
        DUP _ah-id-b @ = _ah-assert
        _ah-releases-b @ 1 = _ah-assert
        1 _ah-closed-b +!
    THEN
    DROP ;

: _ah-fill-descriptor  ( -- )
    _ah-comp COMP-DESC-INIT
    S" test.generic.applet-host" _ah-comp COMP.ID-U ! _ah-comp COMP.ID-A !
    8 _ah-comp COMP.STATE-SIZE !
    ['] _ah-state-init _ah-comp COMP.STATE-INIT-XT !
    ['] _ah-state-fini _ah-comp COMP.STATE-FINI-XT !
    _ah-app APP-DESC-INIT
    _ah-comp _ah-app APP.COMP-DESC !
    ['] _ah-init _ah-app APP.INIT-XT !
    ['] _ah-activate _ah-app APP.ACTIVATE-XT !
    ['] _ah-event _ah-app APP.EVENT-XT !
    ['] _ah-tick _ah-app APP.TICK-XT !
    ['] _ah-paint _ah-app APP.PAINT-XT !
    ['] _ah-request-close _ah-app APP.REQUEST-CLOSE-XT !
    ['] _ah-shutdown _ah-app APP.SHUTDOWN-XT ! ;

: _ah-try-launch  ( -- )
    _ah-app _ah-host AHOST-TRY-LAUNCH
    _ah-launch-ior ! _ah-launch-id ! ;

VARIABLE _ah-er
VARIABLE _ah-ec
VARIABLE _ah-eh
VARIABLE _ah-ew
: _ah-region=  ( slot row col h w -- flag )
    _ah-ew ! _ah-eh ! _ah-ec ! _ah-er !
    AHS.RGN @ DUP 0= IF DROP 0 EXIT THEN
    DUP RGN-ROW _ah-er @ =
    OVER RGN-COL _ah-ec @ = AND
    OVER RGN-H _ah-eh @ = AND
    SWAP RGN-W _ah-ew @ = AND ;

: _ah-run  ( -- )
    0 _ah-fails ! 0 _ah-checks ! DEPTH _ah-depth !
    40 20 SCR-NEW DUP _ah-screen ! SCR-USE

    \ Caller-owned initialization is a complete wipe with monotonic ID 1.
    _ah-host AHOST-SIZE 0x5A FILL
    _ah-host AHOST-INIT
    _ah-host AHOST.HEAD @ 0= _ah-assert
    _ah-host AHOST.FOCUS @ 0= _ah-assert
    _ah-host AHOST.LAST-MIN @ 0= _ah-assert
    _ah-host AHOST.REGISTRY @ 0= _ah-assert
    _ah-host AHOST.NEXT-ID @ 1 = _ah-assert
    _ah-host AHOST-SLOT-COUNT 0= _ah-assert
    _ah-host AHOST-VCOUNT 0= _ah-assert
    2 3 _ah-host AHOST-TILE-AT 0= _ah-assert

    CREG-NEW DUP 0= _ah-assert DROP _ah-reg !
    _ah-fill-descriptor
    _ah-comp _ah-reg @ CREG-TYPE+ 0= _ah-assert
    \ UCTX arenas are process-lifetime shared pools.  Prime that documented
    \ one-time allocation so the host accounting below measures only the
    \ allocations it must recycle on failure and close.
    UCTX-ALLOC DUP 0<> _ah-assert UCTX-FREE
    _ah-memory-snapshot

    \ Relayout is a required preflight: its absence consumes no host ID and
    \ allocates no observable instance, slot, or component state.
    _ah-reg @ _ah-host AHOST-REGISTRY!
    _ah-endpoint _ah-host AHOST-ENDPOINT!
    _ah-context _ah-host AHOST-CONTEXT!
    ['] _ah-release _ah-host AHOST-RELEASE!
    ['] _ah-closed _ah-host AHOST-CLOSED!
    _ah-try-launch
    _ah-launch-id @ -1 = _ah-assert
    _ah-launch-ior @ AHOST-LAUNCH-E-RELAYOUT = _ah-assert
    _ah-host AHOST.NEXT-ID @ 1 = _ah-assert
    _ah-host AHOST-SLOT-COUNT 0= _ah-assert
    _ah-host AHOST.HEAD @ 0= _ah-assert
    _ah-host AHOST.FOCUS @ 0= _ah-assert
    _ah-reg @ CREG.INST-N @ 0= _ah-assert
    _ah-state-inits @ 0= _ah-assert
    _ah-state-finis @ 0= _ah-assert
    _ah-inits @ 0= _ah-assert
    _ah-relayouts @ 0= _ah-assert
    _ah-memory-clean
    _ah-stack
    ." AH-M2-RELAYOUT-FAIL" CR

    \ With relayout supplied, a missing registry fails after temporary state
    \ creation; rollback must balance it and leave the host retryable.
    ['] _ah-relayout _ah-host AHOST-RELAYOUT!
    0 _ah-host AHOST-REGISTRY!
    _ah-try-launch
    _ah-launch-id @ -1 = _ah-assert
    _ah-launch-ior @ AHOST-LAUNCH-E-REGISTRY = _ah-assert
    _ah-host AHOST.NEXT-ID @ 1 = _ah-assert
    _ah-host AHOST-SLOT-COUNT 0= _ah-assert
    _ah-host AHOST-VCOUNT 0= _ah-assert
    _ah-host AHOST.HEAD @ 0= _ah-assert
    _ah-host AHOST.FOCUS @ 0= _ah-assert
    _ah-host AHOST.LAST-MIN @ 0= _ah-assert
    _ah-reg @ CREG.INST-N @ 0= _ah-assert
    _ah-state-inits @ 1 = _ah-assert
    _ah-state-finis @ 1 = _ah-assert
    _ah-state-inits @ _ah-state-finis @ = _ah-assert
    _ah-inits @ 0= _ah-assert
    _ah-memory-clean
    _ah-stack
    ." AH-M3-REGISTRY-FAIL" CR

    \ Reinstalling the registry immediately after rollback is the retry.
    _ah-reg @ _ah-host AHOST-REGISTRY!
    _ah-host AHOST.REGISTRY @ _ah-reg @ = _ah-assert
    _ah-host AHOST.ENDPOINT @ _ah-endpoint = _ah-assert
    _ah-host AHOST.CONTEXT @ _ah-context = _ah-assert
    _ah-host AHOST.RELAYOUT-XT @ ['] _ah-relayout = _ah-assert
    _ah-host AHOST.RELEASE-XT @ ['] _ah-release = _ah-assert
    _ah-host AHOST.CLOSED-XT @ ['] _ah-closed = _ah-assert
    _ah-stack
    ." AH-M4-INJECTED" CR

    \ Two real instances share one minimal descriptor and live registry.
    _ah-app _ah-host AHOST-TRY-LAUNCH DUP 0= _ah-assert DROP _ah-id-a !
    _ah-app _ah-host AHOST-TRY-LAUNCH DUP 0= _ah-assert DROP _ah-id-b !
    _ah-id-a @ 1 = _ah-assert _ah-id-b @ 2 = _ah-assert
    _ah-state-inits @ 3 = _ah-assert _ah-state-finis @ 1 = _ah-assert
    _ah-inits @ 2 = _ah-assert
    _ah-host AHOST-SLOT-COUNT 2 = _ah-assert
    _ah-host AHOST-VCOUNT 2 = _ah-assert
    _ah-reg @ CREG.INST-N @ 2 = _ah-assert
    _ah-id-a @ _ah-host AHOST-FIND-ID DUP _ah-slot-a ! 0<> _ah-assert
    _ah-id-b @ _ah-host AHOST-FIND-ID DUP _ah-slot-b ! 0<> _ah-assert
    _ah-slot-a @ AHS.INST @ _ah-inst-a @ = _ah-assert
    _ah-slot-b @ AHS.INST @ _ah-inst-b @ = _ah-assert
    _ah-host AHOST.FOCUS @ _ah-slot-a @ = _ah-assert
    _ah-host AHOST-FOCUSED-INSTANCE _ah-inst-a @ = _ah-assert
    _ah-slot-a @ 2 3 5 7 _ah-region= _ah-assert
    _ah-slot-b @ 10 20 6 8 _ah-region= _ah-assert
    2 3 _ah-host AHOST-TILE-AT _ah-slot-a @ = _ah-assert
    15 27 _ah-host AHOST-TILE-AT _ah-slot-b @ = _ah-assert
    9 9 _ah-host AHOST-TILE-AT 0= _ah-assert
    99 99 _ah-host AHOST-TILE-AT 0= _ah-assert
    _ah-stack
    ." AH-M5-LAUNCHED" CR

    \ Event, tick, paint and revision/dirty accounting remain host-generic.
    ASHELL-CANCEL-QUIT
    777 _ah-host AHOST-DISPATCH-KEY _ah-assert
    _ah-events-a @ 1 = _ah-assert _ah-events-b @ 0= _ah-assert
    _ah-slot-a @ AHS.DIRTY @ -1 = _ah-assert
    _ah-host AHOST-TICK
    _ah-ticks-a @ 1 = _ah-assert _ah-ticks-b @ 1 = _ah-assert
    _ah-slot-a @ AHS.DIRTY @ -1 = _ah-assert
    _ah-slot-b @ AHS.DIRTY @ -1 = _ah-assert
    0 0 _ah-host AHOST-PAINT
    _ah-paints-a @ 1 = _ah-assert _ah-paints-b @ 1 = _ah-assert
    _ah-slot-a @ AHS.DIRTY @ 0= _ah-assert
    _ah-slot-b @ AHS.DIRTY @ 0= _ah-assert
    _ah-slot-a @ AHS.SEEN-REV @ _ah-inst-a @ CINST.REVISION @ = _ah-assert
    _ah-slot-b @ AHS.SEEN-REV @ _ah-inst-b @ CINST.REVISION @ = _ah-assert
    _ah-host AHOST-TICK
    _ah-ticks-a @ 1 = _ah-assert _ah-ticks-b @ 1 = _ah-assert
    _ah-inst-a @ CINST-TOUCH _ah-host AHOST-TICK
    _ah-ticks-a @ 2 = _ah-assert _ah-ticks-b @ 1 = _ah-assert
    _ah-slot-a @ AHS.DIRTY @ -1 = _ah-assert
    _ah-stack
    ." AH-M6-DISPATCH" CR

    \ Focus, minimize and restore preserve caller slots and re-enter layout.
    _ah-id-b @ _ah-host AHOST-FOCUS-ID
    _ah-host AHOST.FOCUS @ _ah-slot-b @ = _ah-assert
    _ah-slot-a @ AHS.STATE @ AHS-S-RUNNING = _ah-assert
    _ah-slot-b @ AHS.STATE @ AHS-S-FOCUSED = _ah-assert
    _ah-id-b @ _ah-host AHOST-MINIMIZE-ID
    _ah-slot-b @ AHS.STATE @ AHS-S-MINIMIZED = _ah-assert
    _ah-host AHOST.LAST-MIN @ _ah-slot-b @ = _ah-assert
    _ah-host AHOST.FOCUS @ _ah-slot-a @ = _ah-assert
    _ah-slot-a @ 2 3 5 7 _ah-region= _ah-assert
    _ah-slot-b @ AHS.RGN @ 0= _ah-assert
    10 20 _ah-host AHOST-TILE-AT 0= _ah-assert
    _ah-host AHOST-RESTORE
    _ah-slot-b @ AHS.STATE @ AHS-S-RUNNING = _ah-assert
    _ah-host AHOST.LAST-MIN @ 0= _ah-assert
    _ah-host AHOST.FOCUS @ _ah-slot-a @ = _ah-assert
    _ah-id-b @ _ah-host AHOST-FOCUS-ID
    _ah-host AHOST.FOCUS @ _ah-slot-b @ = _ah-assert
    _ah-host AHOST-MARK-ALL
    0 -1 _ah-host AHOST-PAINT
    _ah-slot-a @ AHS.DIRTY @ -1 = _ah-assert
    _ah-slot-b @ AHS.DIRTY @ 0= _ah-assert
    _ah-paints-a @ 1 = _ah-assert _ah-paints-b @ 2 = _ah-assert
    0 0 _ah-host AHOST-PAINT
    _ah-slot-a @ AHS.DIRTY @ 0= _ah-assert
    _ah-paints-a @ 2 = _ah-assert _ah-paints-b @ 2 = _ah-assert
    _ah-stack
    ." AH-M7-STATE" CR

    \ Every fail-closed result preserves the exact slot; ALLOW alone drains
    \ it and calls shutdown, owner release, and close projection once.
    _ah-inst-a @ _ah-close-target !
    0 _ah-requests ! 0 _ah-close-mode !
    \ A child-requested shell quit is intercepted by key dispatch, routed
    \ through close negotiation, and canceled at the outer shell boundary.
    _ah-id-a @ _ah-host AHOST-FOCUS-ID
    APP-CLOSE-R-QUIT _ah-expected-close-reason !
    ASHELL-CANCEL-QUIT
    778 _ah-host AHOST-DISPATCH-KEY _ah-assert
    ASHELL-QUIT-PENDING? 0= _ah-assert
    _ah-id-a @ _ah-host AHOST-FIND-ID _ah-slot-a @ = _ah-assert
    _ah-requests @ 1 = _ah-assert
    APP-CLOSE-R-WINDOW _ah-expected-close-reason !
    _ah-id-a @ APP-CLOSE-R-WINDOW _ah-host AHOST-REQUEST-CLOSE-ID
        APP-CLOSE-D-CANCEL = _ah-assert
    _ah-id-a @ _ah-host AHOST-FIND-ID _ah-slot-a @ = _ah-assert
    1 _ah-close-mode !
    _ah-id-a @ APP-CLOSE-R-WINDOW _ah-host AHOST-REQUEST-CLOSE-ID
        APP-CLOSE-D-DEFER = _ah-assert
    _ah-id-a @ _ah-host AHOST-FIND-ID _ah-slot-a @ = _ah-assert
    2 _ah-close-mode !
    _ah-id-a @ APP-CLOSE-R-WINDOW _ah-host AHOST-REQUEST-CLOSE-ID
        APP-CLOSE-D-CANCEL = _ah-assert
    _ah-id-a @ _ah-host AHOST-FIND-ID _ah-slot-a @ = _ah-assert
    3 _ah-close-mode !
    _ah-id-a @ APP-CLOSE-R-WINDOW _ah-host AHOST-REQUEST-CLOSE-ID
        APP-CLOSE-D-CANCEL = _ah-assert
    _ah-id-a @ _ah-host AHOST-FIND-ID _ah-slot-a @ = _ah-assert
    _ah-shutdowns-a @ 0= _ah-assert _ah-releases-a @ 0= _ah-assert
    _ah-closed-a @ 0= _ah-assert _ah-reg @ CREG.INST-N @ 2 = _ah-assert
    4 _ah-close-mode !
    _ah-id-a @ APP-CLOSE-R-WINDOW _ah-host AHOST-REQUEST-CLOSE-ID
        APP-CLOSE-D-ALLOW = _ah-assert
    _ah-requests @ 6 = _ah-assert
    _ah-close-reason @ APP-CLOSE-R-WINDOW = _ah-assert
    _ah-shutdowns-a @ 1 = _ah-assert
    _ah-releases-a @ 1 = _ah-assert
    _ah-closed-a @ 1 = _ah-assert
    _ah-id-a @ _ah-host AHOST-FIND-ID 0= _ah-assert
    _ah-host AHOST-SLOT-COUNT 1 = _ah-assert
    _ah-reg @ CREG.INST-N @ 1 = _ah-assert
    _ah-id-a @ APP-CLOSE-R-WINDOW _ah-host AHOST-REQUEST-CLOSE-ID
        APP-CLOSE-D-ALLOW = _ah-assert
    _ah-requests @ 6 = _ah-assert
    _ah-shutdowns-a @ 1 = _ah-assert
    _ah-releases-a @ 1 = _ah-assert
    _ah-closed-a @ 1 = _ah-assert
    _ah-stack
    ." AH-M8-CLOSE" CR

    \ Drain is force-clean, callback-exact, idempotent, and registry-clean.
    _ah-host AHOST-DRAIN 0= _ah-assert
    _ah-shutdowns-b @ 1 = _ah-assert
    _ah-releases-b @ 1 = _ah-assert
    _ah-closed-b @ 1 = _ah-assert
    _ah-state-finis @ 3 = _ah-assert
    _ah-state-inits @ _ah-state-finis @ = _ah-assert
    _ah-host AHOST-SLOT-COUNT 0= _ah-assert
    _ah-host AHOST-VCOUNT 0= _ah-assert
    _ah-host AHOST.HEAD @ 0= _ah-assert
    _ah-host AHOST.FOCUS @ 0= _ah-assert
    _ah-host AHOST.LAST-MIN @ 0= _ah-assert
    _ah-host AHOST-FOCUSED-INSTANCE 0= _ah-assert
    _ah-reg @ CREG.INST-N @ 0= _ah-assert
    ASHELL-ACTIVE-CTX 0= _ah-assert
    _ah-host AHOST-DRAIN 0= _ah-assert
    _ah-shutdowns-b @ 1 = _ah-assert
    _ah-releases-b @ 1 = _ah-assert
    _ah-closed-b @ 1 = _ah-assert
    _ah-memory-clean
    _ah-stack

    \ A callback that returns without publishing the new child region is
    \ also a relayout failure.
    _ah-memory-snapshot
    _ah-relayouts @ _ah-relayout-before !
    ['] _ah-relayout-without-region _ah-host AHOST-RELAYOUT!
    0 _ah-host AHOST-RELEASE!
    0 _ah-host AHOST-CLOSED!
    _ah-try-launch
    _ah-launch-id @ -1 = _ah-assert
    _ah-launch-ior @ AHOST-LAUNCH-E-RELAYOUT = _ah-assert
    _ah-host AHOST.NEXT-ID @ 4 = _ah-assert
    _ah-host AHOST-SLOT-COUNT 0= _ah-assert
    _ah-host AHOST.HEAD @ 0= _ah-assert
    _ah-host AHOST.FOCUS @ 0= _ah-assert
    _ah-reg @ CREG.INST-N @ 0= _ah-assert
    _ah-state-inits @ 4 = _ah-assert
    _ah-state-finis @ 4 = _ah-assert
    _ah-relayouts @ _ah-relayout-before @ 2 + = _ah-assert
    _ah-memory-clean
    _ah-stack
    ." AH-M9-REGION-FAIL" CR

    ASHELL-QUIT RGN-ROOT 0 SCR-USE
    _ah-screen @ SCR-FREE _ah-reg @ CREG-FREE
    _ah-fails @ 0= IF
        ." APPLET HOST PASS " _ah-checks @ .
    ELSE
        ." APPLET HOST FAIL " _ah-fails @ .
    THEN CR ;

: _ah-driver  ( -- )
    ['] _ah-run CATCH ?DUP IF
        ." APPLET HOST DRIVER THROW " . CR
    THEN ;

_ah-driver
'''


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--timeout", type=float, default=180.0)
    args = parser.parse_args()
    harness.PROFILES[PROFILE] = harness.Profile(
        roots=("tui/applet-host/host.f",),
        resources=(),
        autoexec=AUTOEXEC,
        ready_markers=("APPLET HOST PASS",),
        stable_markers=("APPLET HOST PASS",),
        failure_markers=(
            "APPLET HOST FAIL",
            "APPLET HOST ASSERT",
            "APPLET HOST STACK",
            "APPLET HOST DRIVER THROW",
        ),
        linked=True,
        include_large_sample=False,
        total_sectors=2048,
    )
    image = harness.build_image(PROFILE, IMAGE)
    ok = harness.smoke(
        PROFILE,
        image,
        cols=100,
        rows=32,
        max_steps=3_000_000_000,
        timeout=args.timeout,
    )
    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
