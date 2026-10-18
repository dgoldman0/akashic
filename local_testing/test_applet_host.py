#!/usr/bin/env python3
"""Focused linked guest contract for the generic caller-owned applet host."""

from __future__ import annotations

import argparse
import sys
from pathlib import Path


LOCAL_TESTING = Path(__file__).resolve().parent
sys.path.insert(0, str(LOCAL_TESTING))

import akashic_tui as harness  # noqa: E402
import qoi_codec  # noqa: E402

# A picture of 200 by 120 pixels in bands, which QOI stores in about a
# kilobyte, so it decodes over more than one service slice.
PICTURE = qoi_codec.encode(
    [[(row * 2, 255 - row * 2, (row // 8) * 16, 255)] * 200 for row in range(120)]
)


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
VARIABLE _ah-vfs
VARIABLE _ah-service-passes
\ PICTURE-BYTES
VARIABLE _ah-screen
VARIABLE _ah-temp-screen
CREATE _ah-context-ptrs 17 CELLS ALLOT
VARIABLE _ah-relayouts
VARIABLE _ah-layout-index
VARIABLE _ah-heap-before
VARIABLE _ah-xmem-before
VARIABLE _ah-xfree
VARIABLE _ah-xwalk

VARIABLE _ah-inst-a
VARIABLE _ah-inst-b
VARIABLE _ah-scoped-ctx
VARIABLE _ah-scoped-calls
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
VARIABLE _ah-pointers-a
VARIABLE _ah-pointers-b
VARIABLE _ah-pointer-mark
VARIABLE _ah-overlay
VARIABLE _ah-pointer-quit
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
VARIABLE _ah-semantic-menu-b
VARIABLE _ah-semantic-input-b
VARIABLE _ah-semantic-row
VARIABLE _ah-semantic-col
CREATE _ah-semantic-event 3 CELLS ALLOT
CREATE _ah-semantic-escape 3 CELLS ALLOT
CREATE _ah-semantic-printable 3 CELLS ALLOT

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
    DUP _ah-known-instance?
    SWAP CINST-DESC _ah-comp = OR _ah-assert
    1 _ah-activates +! ;

\ Like a real applet, the sample takes pointer input only for an overlay it
\ paints itself, and returns the rest for UIDL.
: _ah-event  ( event instance -- handled? )
    OVER @ KEY-T-MOUSE = IF
        _ah-inst-a @ = IF 1 _ah-pointers-a +! ELSE 1 _ah-pointers-b +! THEN
        DROP _ah-pointer-quit @ IF ASHELL-QUIT 0 EXIT THEN
        _ah-overlay @ EXIT
    THEN
    DUP _ah-inst-a @ = IF
        1 _ah-events-a +!
    ELSE
        DUP _ah-inst-b @ = _ah-assert
        1 _ah-events-b +!
    THEN
    DROP
    DUP _ah-semantic-escape = OVER _ah-semantic-printable = OR IF
        DROP 0 EXIT
    THEN
    DUP 778 = IF DROP ASHELL-QUIT 0 EXIT THEN
    777 = _ah-assert -1 ;

VARIABLE _ah-tick-touch
: _ah-tick  ( instance -- )
    DUP _ah-tick-touch @ = IF DUP CINST-TOUCH THEN
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
    S" <uidl><input id=semantic-input/><menubar><menu id=semantic-menu label=File><item text=New/></menu></menubar><media id=picture/></uidl>"
        _ah-app APP.UIDL-U ! _ah-app APP.UIDL-A !
    ['] _ah-init _ah-app APP.INIT-XT !
    ['] _ah-activate _ah-app APP.ACTIVATE-XT !
    ['] _ah-event _ah-app APP.EVENT-XT !
    ['] _ah-tick _ah-app APP.TICK-XT !
    ['] _ah-paint _ah-app APP.PAINT-XT !
    ['] _ah-request-close _ah-app APP.REQUEST-CLOSE-XT !
    ['] _ah-shutdown _ah-app APP.SHUTDOWN-XT ! ;

\ A dialog child A asks, answered through ordinary host dispatch.
VARIABLE _ah-dialog-answer
VARIABLE _ah-dialog-saved
CREATE _ah-dialog-btn 4 CELLS ALLOT  _ah-dialog-btn 4 CELLS 0 FILL
: _ah-dialog-answered  ( index context -- )
    55 = _ah-assert _ah-dialog-answer ! ;
: _ah-dialog-ask  ( -- ok? )
    S" OK" _ah-dialog-btn 8 + ! _ah-dialog-btn !
    DLG-B-DEFAULT DLG-B-CANCEL OR _ah-dialog-btn 16 + !
    S" Question" S" Answer it" _ah-dialog-btn 1
        ['] _ah-dialog-answered 55 DLG-ASK ;
: _ah-inside?  ( rgn outer -- flag )
    OVER RGN-ROW OVER RGN-ROW >=
    2 PICK RGN-COL 2 PICK RGN-COL >= AND
    2 PICK RGN-ROW 3 PICK RGN-H + 2 PICK RGN-ROW 3 PICK RGN-H + <= AND
    2 PICK RGN-COL 3 PICK RGN-W + 2 PICK RGN-COL 3 PICK RGN-W + <= AND
    NIP NIP ;

: _ah-semantic-event!  ( row col -- )
    KEY-T-MOUSE _ah-semantic-event !
    KEY-MOUSE-LEFT _ah-semantic-event 8 + !
    SWAP 16 LSHIFT OR _ah-semantic-event 16 + ! ;

: _ah-pointer!  ( code row col -- )
    SWAP 16 LSHIFT OR _ah-semantic-event 16 + !
    _ah-semantic-event 8 + !
    KEY-T-MOUSE _ah-semantic-event ! ;

: _ah-semantic-key!  ( type code event -- )
    DUP >R 3 CELLS 0 FILL
    R@ 8 + ! R> ! ;

: _ah-try-launch  ( -- )
    _ah-app _ah-host AHOST-TRY-LAUNCH
    _ah-launch-ior ! _ah-launch-id ! ;

\ Like Pad with unsaved work, a child asks before it closes, and agreeing
\ to discard arms the next close and quits again.
VARIABLE _ah-q-armed-a
VARIABLE _ah-q-armed-b
VARIABLE _ah-q-asks
: _ah-q-armed  ( instance -- a )
    _ah-inst-a @ = IF _ah-q-armed-a ELSE _ah-q-armed-b THEN ;
: _ah-q-answered  ( confirmed? instance -- )
    SWAP IF -1 SWAP _ah-q-armed ! ASHELL-QUIT ELSE DROP THEN ;
: _ah-q-request-close  ( reason instance -- decision )
    NIP DUP _ah-q-armed @ IF 0 SWAP _ah-q-armed ! APP-CLOSE-D-ALLOW EXIT THEN
    1 _ah-q-asks +!
    >R S" Close and discard?" S" Discard" ['] _ah-q-answered R> DLG-CONFIRM
    IF APP-CLOSE-D-DEFER ELSE APP-CLOSE-D-CANCEL THEN ;
\ Send the focused child a key.
: _ah-q-key  ( code -- )
    KEY-T-SPECIAL SWAP _ah-semantic-escape _ah-semantic-key!
    _ah-semantic-escape _ah-host AHOST-DISPATCH-KEY _ah-assert ;
: _ah-q-launch-two  ( -- )
    0 _ah-inst-a ! 0 _ah-inst-b !
    _ah-try-launch _ah-launch-ior @ 0= _ah-assert
    _ah-launch-id @ DUP _ah-id-a ! _ah-host AHOST-FIND-ID _ah-slot-a !
    _ah-try-launch _ah-launch-ior @ 0= _ah-assert
    _ah-launch-id @ DUP _ah-id-b ! _ah-host AHOST-FIND-ID _ah-slot-b !
    0 _ah-q-armed-a ! 0 _ah-q-armed-b ! 0 _ah-q-asks ! ;

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

\ What a capability handler does with its own UIDL elements.
: _ah-scoped-touch  ( -- )
    1 _ah-scoped-calls +! ASHELL-ACTIVE-CTX _ah-scoped-ctx !
    S" picture" UTUI-BY-ID DUP 0<> _ah-assert UIDL-DIRTY! ;
: _ah-scoped-throw  ( -- ) _ah-scoped-touch -733 THROW ;
: _ah-scoped-plain  ( -- )
    1 _ah-scoped-calls +! ASHELL-ACTIVE-CTX _ah-scoped-ctx ! ;

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
    _ah-host AHOST.NEXT-OVERLAY-ID @ -2 = _ah-assert
    _ah-host AHOST-SLOT-COUNT 0= _ah-assert
    _ah-host AHOST-VCOUNT 0= _ah-assert
    2 3 _ah-host AHOST-TILE-AT 0= _ah-assert

    CREG-NEW DUP 0= _ah-assert DROP _ah-reg !
    _ah-fill-descriptor
    _ah-comp _ah-reg @ CREG-TYPE+ 0= _ah-assert

    \ A RAM VFS holds the picture the media milestone shows.  It lives for
    \ the whole run, so the memory baselines below include it.
    524288 A-XMEM ARENA-NEW IF -1 THROW THEN
    VFS-RAM-BINDING 0 VFS-NEW ?DUP IF THROW THEN _ah-vfs !
    S" /pic.qoi" _ah-vfs @ VFS-CREATE 0<> _ah-assert
    S" /pic.qoi" VFS-FF-WRITE _ah-vfs @ VFS-OPEN? 0= _ah-assert
    _ah-picture _ah-picture-u 2 PICK VFS-WRITE-EXACT 0= _ah-assert VFS-CLOSE

    \ Context ownership has no fixed pool ceiling.  Exceed the former
    \ sixteen-context arena cap, then prove exact allocator recovery.
    _ah-memory-snapshot
    17 0 DO
        UCTX-ALLOC DUP 0<> _ah-assert
        I CELLS _ah-context-ptrs + !
    LOOP
    17 0 DO I CELLS _ah-context-ptrs + @ UCTX-FREE LOOP
    _ah-memory-clean

    \ Screen destruction and resizing both return their front/back storage.
    20 10 SCR-NEW DUP _ah-temp-screen ! SCR-USE
    30 12 SCR-RESIZE
    _ah-temp-screen @ SCR-FREE
    _ah-screen @ SCR-USE
    _ah-memory-clean

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

    \ Overlapping presentation regions route the pointer to focus rather
    \ than whichever live slot happens to occur first in the host list.
    _ah-slot-a @ AHS.RGN @ RGN-FREE
    _ah-slot-b @ AHS.RGN @ RGN-FREE
    0 0 20 30 RGN-NEW _ah-slot-a @ AHS.RGN !
    0 0 20 30 RGN-NEW _ah-slot-b @ AHS.RGN !
    5 5 _ah-host AHOST-TILE-AT _ah-slot-a @ = _ah-assert
    _ah-id-b @ _ah-host AHOST-FOCUS-ID
    5 5 _ah-host AHOST-TILE-AT _ah-slot-b @ = _ah-assert
    _ah-context _ah-relayout
    _ah-id-a @ _ah-host AHOST-FOCUS-ID
    _ah-stack
    ." AH-M5-LAUNCHED" CR

    \ A semantic rich-control activation resolves to an absolute cell in
    \ the acknowledged target's UIDL context.  Prove that when that cell
    \ belongs to a nonfocused child, one ordinary synthetic mouse event both
    \ moves host focus and opens that child's real UIDL menu.
    _ah-slot-b @ AHS-CTX-SWITCH
    S" semantic-input" UTUI-BY-ID
    DUP 0<> _ah-assert DUP _ah-semantic-input-b ! UTUI-FOCUS!
    UTUI-FOCUS _ah-semantic-input-b @ = _ah-assert
    S" semantic-menu" UTUI-BY-ID
    DUP 0<> _ah-assert DUP _ah-semantic-menu-b !
    _UTUI-SIDECAR
    DUP _UTUI-SC-ROW@ _ah-semantic-row !
    _UTUI-SC-COL@ _ah-semantic-col !
    _ah-semantic-row @ _ah-semantic-col @ _ah-host AHOST-TILE-AT
        _ah-slot-b @ = _ah-assert
    _ah-id-a @ _ah-host AHOST-FOCUS-ID
    _ah-host AHOST.FOCUS @ _ah-slot-a @ = _ah-assert
    _ah-slot-a @ AHS-CTX-SWITCH
    _UTUI-MENU-OPEN @ 0= _ah-assert
    \ Pointer dispatch, like key dispatch, reads a pending quit as the
    \ child's own request, so clear the one earlier scenarios left.
    ASHELL-CANCEL-QUIT
    _ah-semantic-row @ _ah-semantic-col @ _ah-semantic-event!
    _ah-semantic-event _ah-host AHOST-DISPATCH-MOUSE _ah-assert
    _ah-pointers-b @ 1 = _ah-assert
    _ah-host AHOST.FOCUS @ _ah-slot-b @ = _ah-assert
    _ah-slot-b @ AHS-CTX-SWITCH
    _UTUI-MENU-OPEN @ _ah-semantic-menu-b @ = _ah-assert
    _UTUI-MENU-SAVED-FOC @ _ah-semantic-input-b @ = _ah-assert
    _ah-semantic-input-b @ _UTUI-SIDECAR _UTUI-SC-VIS? _ah-assert
    _ah-slot-b @ AHS.DIRTY @ -1 = _ah-assert
    ASHELL-CANCEL-QUIT
    KEY-T-SPECIAL KEY-ESC _ah-semantic-escape _ah-semantic-key!
    _ah-semantic-escape _ah-host AHOST-DISPATCH-KEY _ah-assert
    _UTUI-MENU-OPEN @ 0= _ah-assert
    UTUI-FOCUS _ah-semantic-input-b @ = _ah-assert
    0 _ah-slot-b @ AHS.DIRTY !
    KEY-T-CHAR [CHAR] ~ _ah-semantic-printable _ah-semantic-key!
    _ah-semantic-printable _ah-host AHOST-DISPATCH-KEY _ah-assert
    _ah-slot-b @ AHS.DIRTY @ -1 = _ah-assert
    _ah-slot-a @ AHS-CTX-SWITCH
    _UTUI-MENU-OPEN @ 0= _ah-assert
    _ah-id-a @ _ah-host AHOST-FOCUS-ID
    _ah-stack
    ." AH-M5B-CROSS-FOCUS-MENU" CR

    \ A dialog a child shows takes its keys before the child's handler,
    \ paints inside the child's document region, and once answered runs
    \ its callback with that child current.
    ASHELL-CANCEL-QUIT
    _ah-slot-a @ AHS-CTX-SWITCH
    -1 _ah-dialog-answer !
    _ah-dialog-ask _ah-assert DLG-SHOWN 0<> _ah-assert
    _ah-events-a @ _ah-dialog-saved !
    KEY-T-SPECIAL KEY-UP _ah-semantic-escape _ah-semantic-key!
    _ah-semantic-escape _ah-host AHOST-DISPATCH-KEY _ah-assert
    _ah-events-a @ _ah-dialog-saved @ = _ah-assert
    _ah-dialog-answer @ -1 = _ah-assert DLG-SHOWN 0<> _ah-assert
    \ It centres in the child's document region.
    _ah-slot-a @ AHS-CTX-SWITCH DLG-HOST-PAINT
    DLG-SHOWN WDG-REGION _UTUI-RGN @ _ah-inside? _ah-assert
    KEY-T-SPECIAL KEY-ESC _ah-semantic-escape _ah-semantic-key!
    _ah-semantic-escape _ah-host AHOST-DISPATCH-KEY _ah-assert
    _ah-events-a @ _ah-dialog-saved @ = _ah-assert
    _ah-dialog-answer @ 0= _ah-assert
    DLG-SHOWN 0= _ah-assert
    _ah-slot-a @ AHS.DIRTY @ -1 = _ah-assert
    _ah-stack
    ." AH-DIALOG" CR

    \ Event, tick, paint and revision/dirty accounting remain host-generic.
    ASHELL-CANCEL-QUIT
    777 _ah-host AHOST-DISPATCH-KEY _ah-assert
    _ah-events-a @ 1 = _ah-assert _ah-events-b @ 2 = _ah-assert
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

    \ Any press captures its slot, so the drag and release that follow reach
    \ that slot even over another tile.  Only a primary press moves focus,
    \ and the wheel never does.  The M5B menu press has had no release, so
    \ slot B still holds its capture until one arrives.
    _ah-host AHOST.CAPTURE @ _ah-slot-b @ = _ah-assert
    KEY-MOUSE-RELEASE 0 0 _ah-pointer!
    _ah-semantic-event _ah-host AHOST-DISPATCH-MOUSE DROP
    _ah-host AHOST.CAPTURE @ 0= _ah-assert
    KEY-MOUSE-MIDDLE 3 4 _ah-pointer!
    _ah-semantic-event _ah-host AHOST-DISPATCH-MOUSE DROP
    _ah-host AHOST.CAPTURE @ _ah-slot-a @ = _ah-assert
    _ah-host AHOST.CAPTURE-ROW @ 3 = _ah-assert
    _ah-host AHOST.CAPTURE-COL @ 4 = _ah-assert
    _ah-host AHOST.FOCUS @ _ah-slot-b @ = _ah-assert
    KEY-MOUSE-DRAG 11 21 _ah-pointer!
    _ah-semantic-event _ah-host AHOST-DISPATCH-MOUSE DROP
    _ah-host AHOST.CAPTURE @ _ah-slot-a @ = _ah-assert
    KEY-MOUSE-RELEASE 11 21 _ah-pointer!
    _ah-semantic-event _ah-host AHOST-DISPATCH-MOUSE DROP
    _ah-host AHOST.CAPTURE @ 0= _ah-assert
    \ Without a capture a release reaches no slot.
    KEY-MOUSE-RELEASE 3 4 _ah-pointer!
    _ah-semantic-event _ah-host AHOST-DISPATCH-MOUSE 0= _ah-assert
    KEY-MOUSE-SCROLL-DN 3 4 _ah-pointer!
    _ah-semantic-event _ah-host AHOST-DISPATCH-MOUSE DROP
    _ah-host AHOST.FOCUS @ _ah-slot-b @ = _ah-assert
    \ A child paints overlays such as a prompt above its UIDL elements, so
    \ its own handler sees pointer input first.  A press the overlay takes
    \ never reaches UIDL: the menu under it stays closed.
    _ah-pointers-b @ _ah-pointer-mark !
    -1 _ah-overlay !
    0 _ah-slot-b @ AHS.DIRTY !
    _ah-semantic-row @ _ah-semantic-col @ _ah-semantic-event!
    _ah-semantic-event _ah-host AHOST-DISPATCH-MOUSE _ah-assert
    _ah-pointers-b @ _ah-pointer-mark @ 1+ = _ah-assert
    _ah-slot-b @ AHS.DIRTY @ -1 = _ah-assert
    _ah-slot-b @ AHS-CTX-SWITCH
    _UTUI-MENU-OPEN @ 0= _ah-assert
    0 _ah-overlay !
    KEY-MOUSE-RELEASE _ah-semantic-row @ _ah-semantic-col @ _ah-pointer!
    _ah-semantic-event _ah-host AHOST-DISPATCH-MOUSE DROP
    _ah-host AHOST.CAPTURE @ 0= _ah-assert
    \ This capture is still held when slot A closes below.
    KEY-MOUSE-MIDDLE 3 4 _ah-pointer!
    _ah-semantic-event _ah-host AHOST-DISPATCH-MOUSE DROP
    _ah-host AHOST.CAPTURE @ _ah-slot-a @ = _ah-assert
    _ah-stack
    ." AH-M7B-CAPTURE" CR

    \ A picture a child's <media> element shows decodes from the host's
    \ per-pass service, one bounded slice a pass, and only the slot whose
    \ document changed is marked for repaint.  With nothing decoding the
    \ service does nothing.
    _ah-host AHOST-SERVICE 0= _ah-assert
    _ah-slot-a @ AHS-CTX-SWITCH
    S" /pic.qoi" _ah-vfs @ S" picture" UTUI-BY-ID UTUI-WIDGET@
        MEDIA-OPEN-VFS 0= _ah-assert
    S" picture" UTUI-BY-ID UIDL-DIRTY!
    _ah-host AHOST-SERVICE 0= _ah-assert
    -1 0 _ah-host AHOST-PAINT
    PICT-WORK? _ah-assert
    0 _ah-slot-a @ AHS.DIRTY !  0 _ah-slot-b @ AHS.DIRTY !
    0 _ah-service-passes !
    BEGIN _ah-host AHOST-SERVICE WHILE 1 _ah-service-passes +! REPEAT
    _ah-service-passes @ 2 = _ah-assert
    PICT-WORK? 0= _ah-assert
    _ah-slot-a @ AHS.DIRTY @ -1 = _ah-assert
    _ah-slot-b @ AHS.DIRTY @ 0= _ah-assert
    _ah-slot-a @ AHS-CTX-SWITCH
    S" picture" UTUI-BY-ID DUP UIDL-DIRTY? _ah-assert
    UTUI-WIDGET@ MEDIA-PICTURE@ PICT-CELL-COPY@ PIC-STATE@
        PIC-ST-READY = _ah-assert
    0 0 _ah-host AHOST-PAINT
    _ah-slot-a @ AHS.DIRTY @ 0= _ah-assert
    _ah-stack
    ." AH-M7C-SERVICE" CR

    \ A capability handler the request bus runs for a child runs as the
    \ child's own callbacks do: in its UIDL context, where its elements are,
    \ and a repaint it asks for marks its slot.  The child context live
    \ before is live again after, even when the handler throws.
    _ah-slot-b @ AHS-CTX-SWITCH
    0 _ah-slot-a @ AHS.DIRTY !  0 _ah-slot-b @ AHS.DIRTY !
    0 _UTUI-NEEDS-PAINT !  0 _ah-scoped-calls !
    _ah-inst-a @ _ah-host AHOST-FIND-INSTANCE _ah-slot-a @ = _ah-assert
    _ah-inst-b @ _ah-host AHOST-FIND-INSTANCE _ah-slot-b @ = _ah-assert
    12345 _ah-host AHOST-FIND-INSTANCE 0= _ah-assert
    ['] _ah-scoped-touch _ah-inst-a @ _ah-host AHOST-CALL-SCOPED
    _ah-scoped-calls @ 1 = _ah-assert
    _ah-scoped-ctx @ _ah-slot-a @ AHS.UCTX @ = _ah-assert
    ASHELL-ACTIVE-CTX _ah-slot-b @ AHS.UCTX @ = _ah-assert
    _ah-slot-a @ AHS.DIRTY @ -1 = _ah-assert
    _ah-slot-b @ AHS.DIRTY @ 0= _ah-assert
    _UTUI-NEEDS-PAINT @ _ah-assert
    0 _ah-slot-a @ AHS.DIRTY !  0 _UTUI-NEEDS-PAINT !
    ['] _ah-scoped-throw _ah-inst-a @ _ah-host ['] AHOST-CALL-SCOPED CATCH
        -733 = _ah-assert 2DROP DROP
    _ah-scoped-calls @ 2 = _ah-assert
    ASHELL-ACTIVE-CTX _ah-slot-b @ AHS.UCTX @ = _ah-assert
    _ah-slot-a @ AHS.DIRTY @ -1 = _ah-assert
    \ With no child context live before, the child's context stays current,
    \ as after a paint.  An instance no slot holds runs as it is.
    0 ASHELL-CTX-SWITCH
    ['] _ah-scoped-plain _ah-inst-a @ _ah-host AHOST-CALL-SCOPED
    ASHELL-ACTIVE-CTX _ah-slot-a @ AHS.UCTX @ = _ah-assert
    ['] _ah-scoped-plain 12345 _ah-host AHOST-CALL-SCOPED
    _ah-scoped-calls @ 4 = _ah-assert
    _ah-scoped-ctx @ _ah-slot-a @ AHS.UCTX @ = _ah-assert
    0 0 _ah-host AHOST-PAINT
    0 _UTUI-NEEDS-PAINT !
    _ah-stack
    ." AH-M7D-SCOPED" CR

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
    \ Pointer dispatch intercepts a quit the child requests the same way.
    -1 _ah-pointer-quit !
    KEY-MOUSE-LEFT 3 4 _ah-pointer!
    _ah-semantic-event _ah-host AHOST-DISPATCH-MOUSE _ah-assert
    0 _ah-pointer-quit !
    ASHELL-QUIT-PENDING? 0= _ah-assert
    _ah-id-a @ _ah-host AHOST-FIND-ID _ah-slot-a @ = _ah-assert
    _ah-requests @ 2 = _ah-assert
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
    _ah-requests @ 7 = _ah-assert
    _ah-close-reason @ APP-CLOSE-R-WINDOW = _ah-assert
    _ah-shutdowns-a @ 1 = _ah-assert
    _ah-releases-a @ 1 = _ah-assert
    _ah-closed-a @ 1 = _ah-assert
    _ah-id-a @ _ah-host AHOST-FIND-ID 0= _ah-assert
    _ah-host AHOST.CAPTURE @ 0= _ah-assert
    _ah-host AHOST-SLOT-COUNT 1 = _ah-assert
    _ah-reg @ CREG.INST-N @ 1 = _ah-assert
    _ah-id-a @ APP-CLOSE-R-WINDOW _ah-host AHOST-REQUEST-CLOSE-ID
        APP-CLOSE-D-ALLOW = _ah-assert
    _ah-requests @ 7 = _ah-assert
    _ah-shutdowns-a @ 1 = _ah-assert
    _ah-releases-a @ 1 = _ah-assert
    _ah-closed-a @ 1 = _ah-assert
    _ah-stack
    ." AH-M8-CLOSE" CR

    \ A fully successful drain is callback-exact, idempotent, and registry-clean.
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

    \ An overlay takes its ID from its own range below the failure ID -1,
    \ so opening one never shifts the numbers ordinary children receive.
    \ The sample callbacks track two live instances at a time.
    ['] _ah-relayout _ah-host AHOST-RELAYOUT!
    _ah-memory-snapshot
    0 _ah-inst-a ! 0 _ah-inst-b !
    _ah-app _ah-host AHOST-TRY-LAUNCH-OVERLAY 0= _ah-assert
    DUP -2 = _ah-assert
    _ah-host AHOST-FIND-ID DUP 0<> _ah-assert AHS-OVERLAY? _ah-assert
    _ah-try-launch
    _ah-launch-ior @ 0= _ah-assert
    _ah-launch-id @ 4 = _ah-assert
    _ah-host AHOST-DRAIN 0= _ah-assert
    0 _ah-inst-a ! 0 _ah-inst-b !
    _ah-app _ah-host AHOST-TRY-LAUNCH-OVERLAY 0= _ah-assert
    -3 = _ah-assert
    _ah-host AHOST.NEXT-ID @ 5 = _ah-assert
    _ah-host AHOST-DRAIN 0= _ah-assert
    _ah-host AHOST-SLOT-COUNT 0= _ah-assert
    _ah-memory-clean
    _ah-stack
    ." AH-M10-OVERLAY-ID" CR

    \ A child that touches itself as it ticks is drawn in that pass, and
    \ only then: a minimized child left unpainted does not ask again.
    _ah-memory-snapshot
    0 _ah-inst-a ! 0 _ah-inst-b !
    _ah-try-launch _ah-launch-ior @ 0= _ah-assert
    _ah-launch-id @ DUP _ah-id-a ! _ah-host AHOST-FIND-ID _ah-slot-a !
    _ah-try-launch _ah-launch-ior @ 0= _ah-assert
    _ah-launch-id @ DUP _ah-id-b ! _ah-host AHOST-FIND-ID _ah-slot-b !
    APP-F-TICK-WHEN-CLEAN _ah-app APP.FLAGS !
    -1 0 _ah-host AHOST-PAINT
    _ah-slot-a @ AHS.DIRTY @ 0= _ah-assert
    _ah-slot-b @ AHS.DIRTY @ 0= _ah-assert
    0 _ASHELL-DIRTY !
    _ah-inst-a @ _ah-tick-touch ! _ah-host AHOST-TICK
    _ah-slot-a @ AHS.DIRTY @ -1 = _ah-assert
    _ah-slot-b @ AHS.DIRTY @ 0= _ah-assert
    _ASHELL-DIRTY @ _ah-assert
    0 _ASHELL-DIRTY ! 0 _ah-tick-touch ! _ah-host AHOST-TICK
    _ASHELL-DIRTY @ 0= _ah-assert
    _ah-id-b @ _ah-host AHOST-MINIMIZE-ID
    0 _ASHELL-DIRTY !
    _ah-inst-b @ _ah-tick-touch ! _ah-host AHOST-TICK
    _ASHELL-DIRTY @ _ah-assert
    0 _ASHELL-DIRTY ! 0 _ah-tick-touch ! _ah-host AHOST-TICK
    _ah-slot-b @ AHS.DIRTY @ -1 = _ah-assert
    _ASHELL-DIRTY @ 0= _ah-assert
    0 _ah-app APP.FLAGS !
    _ah-host AHOST-DRAIN 0= _ah-assert
    _ah-host AHOST-SLOT-COUNT 0= _ah-assert
    _ah-memory-clean
    _ah-stack
    ." AH-M11-TICK-TOUCH" CR

    \ A child launched minimized has its INIT and is ticked, but takes no
    \ tile and no focus, and is not the slot restored next; focusing it by
    \ its ID restores it.
    _ah-memory-snapshot
    0 _ah-inst-a ! 0 _ah-inst-b !
    _ah-try-launch _ah-launch-ior @ 0= _ah-assert
    _ah-launch-id @ DUP _ah-id-a ! _ah-host AHOST-FIND-ID _ah-slot-a !
    _ah-app _ah-host AHOST-TRY-LAUNCH-MINIMIZED 0= _ah-assert
    DUP _ah-id-b ! _ah-host AHOST-FIND-ID DUP _ah-slot-b ! 0<> _ah-assert
    _ah-inst-b @ 0<> _ah-assert
    _ah-slot-b @ AHS.STATE @ AHS-S-MINIMIZED = _ah-assert
    _ah-slot-b @ AHS.RGN @ 0= _ah-assert
    _ah-slot-b @ AHS-CALLABLE? _ah-assert
    _ah-host AHOST.FOCUS @ _ah-slot-a @ = _ah-assert
    _ah-host AHOST.LAST-MIN @ 0= _ah-assert
    _ah-ticks-b @ _ah-inst-b @ CINST-TOUCH _ah-host AHOST-TICK
    _ah-ticks-b @ 1- = _ah-assert
    _ah-id-b @ _ah-host AHOST-FOCUS-ID
    _ah-slot-b @ AHS.STATE @ AHS-S-FOCUSED = _ah-assert
    _ah-slot-b @ AHS.RGN @ 0<> _ah-assert
    _ah-host AHOST-DRAIN 0= _ah-assert
    _ah-host AHOST-SLOT-COUNT 0= _ah-assert
    _ah-memory-clean
    _ah-stack
    ." AH-M12-MINIMIZED" CR

    \ Children that ask before they close hold the host's shutdown: it
    \ waits on their questions and asks neither again, a child that says
    \ to discard closes at once, and once none still asks the host quits
    \ again so its shutdown goes on.
    _ah-memory-snapshot
    ['] _ah-q-request-close _ah-app APP.REQUEST-CLOSE-XT !
    ASHELL-CANCEL-QUIT
    _ah-q-launch-two
    APP-CLOSE-R-HOST-SHUTDOWN _ah-host AHOST-REQUEST-CLOSE-ALL
        APP-CLOSE-D-DEFER = _ah-assert
    _ah-q-asks @ 2 = _ah-assert
    _ah-host AHOST-SHUTDOWN-PENDING? _ah-assert
    _ah-slot-a @ AHS.DEFERRED @ APP-CLOSE-R-HOST-SHUTDOWN = _ah-assert
    _ah-slot-b @ AHS.DEFERRED @ APP-CLOSE-R-HOST-SHUTDOWN = _ah-assert
    APP-CLOSE-R-HOST-SHUTDOWN _ah-host AHOST-REQUEST-CLOSE-ALL
        APP-CLOSE-D-DEFER = _ah-assert
    _ah-q-asks @ 2 = _ah-assert
    _ah-id-a @ _ah-host AHOST-FOCUS-ID
    KEY-LEFT _ah-q-key KEY-ENTER _ah-q-key
    _ah-id-a @ _ah-host AHOST-FIND-ID 0= _ah-assert
    ASHELL-QUIT-PENDING? 0= _ah-assert
    _ah-host AHOST-SHUTDOWN-PENDING? _ah-assert
    _ah-id-b @ _ah-host AHOST-FOCUS-ID
    KEY-LEFT _ah-q-key KEY-ENTER _ah-q-key
    _ah-id-b @ _ah-host AHOST-FIND-ID 0= _ah-assert
    ASHELL-QUIT-PENDING? _ah-assert
    ASHELL-CANCEL-QUIT
    _ah-q-asks @ 2 = _ah-assert
    APP-CLOSE-R-HOST-SHUTDOWN _ah-host AHOST-REQUEST-CLOSE-ALL
        APP-CLOSE-D-ALLOW = _ah-assert
    _ah-host AHOST-SHUTDOWN-PENDING? 0= _ah-assert
    _ah-host AHOST-SLOT-COUNT 0= _ah-assert
    _ah-memory-clean
    _ah-stack
    ." AH-M13-SHUTDOWN-GOES-ON" CR

    \ A child that declines ends the shutdown: the other child's open
    \ question then answers only its own close, which quits nothing more.
    _ah-memory-snapshot
    _ah-q-launch-two
    APP-CLOSE-R-HOST-SHUTDOWN _ah-host AHOST-REQUEST-CLOSE-ALL
        APP-CLOSE-D-DEFER = _ah-assert
    _ah-id-a @ _ah-host AHOST-FOCUS-ID
    KEY-ESC _ah-q-key
    _ah-id-a @ _ah-host AHOST-FIND-ID _ah-slot-a @ = _ah-assert
    _ah-slot-a @ AHS.DEFERRED @ 0= _ah-assert
    _ah-slot-b @ AHS.DEFERRED @ APP-CLOSE-R-QUIT = _ah-assert
    _ah-host AHOST-SHUTDOWN-PENDING? 0= _ah-assert
    ASHELL-QUIT-PENDING? 0= _ah-assert
    _ah-id-b @ _ah-host AHOST-FOCUS-ID
    KEY-LEFT _ah-q-key KEY-ENTER _ah-q-key
    _ah-id-b @ _ah-host AHOST-FIND-ID 0= _ah-assert
    ASHELL-QUIT-PENDING? 0= _ah-assert
    _ah-host AHOST-SLOT-COUNT 1 = _ah-assert
    \ Its own close asks it again.
    _ah-id-a @ APP-CLOSE-R-WINDOW _ah-host AHOST-REQUEST-CLOSE-ID
        APP-CLOSE-D-DEFER = _ah-assert
    _ah-q-asks @ 3 = _ah-assert
    _ah-slot-a @ AHS.DEFERRED @ APP-CLOSE-R-WINDOW = _ah-assert
    KEY-LEFT _ah-q-key KEY-ENTER _ah-q-key
    _ah-id-a @ _ah-host AHOST-FIND-ID 0= _ah-assert
    ASHELL-QUIT-PENDING? 0= _ah-assert
    ['] _ah-request-close _ah-app APP.REQUEST-CLOSE-XT !
    _ah-host AHOST-SLOT-COUNT 0= _ah-assert
    _ah-memory-clean
    _ah-stack
    ." AH-M14-SHUTDOWN-DECLINED" CR

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


AUTOEXEC = AUTOEXEC.replace(
    "\\ PICTURE-BYTES\n",
    "CREATE _ah-picture\n"
    + "".join(
        " ".join(f"{byte} C," for byte in PICTURE[at:at + 32]) + "\n"
        for at in range(0, len(PICTURE), 32)
    )
    + f"{len(PICTURE)} CONSTANT _ah-picture-u\n",
)


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
        total_sectors=4096,
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
