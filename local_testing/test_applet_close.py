#!/usr/bin/env python3
"""Focused production-image regressions for APP-DESC close negotiation.

The shell and Desk contracts are deliberately separate profiles.  This keeps
their failure domains and assertion totals independent while ensuring the
linked Desk lifecycle is exercised by this focused driver rather than being
left as dormant Forth source.
"""

from __future__ import annotations

import sys
import argparse
from pathlib import Path


LOCAL_TESTING = Path(__file__).resolve().parent
sys.path.insert(0, str(LOCAL_TESTING))

import akashic_tui as harness  # noqa: E402


SHELL_PROFILE = "applet-close-shell"
SHELL_IMAGE = Path("/tmp/akashic-applet-close-shell.img")
DESK_PROFILE = "applet-close-desk"
DESK_IMAGE = Path("/tmp/akashic-applet-close-desk.img")

AUTOEXEC = r"""\ autoexec.f - applet close negotiation regression
ENTER-USERLAND
REQUIRE tui/applets/desk/desk.f
." LC-M1-REQUIRE" CR

VARIABLE _lc-fails
VARIABLE _lc-checks
: _lc-assert  ( flag -- )
    1 _lc-checks +!
    0= IF 1 _lc-fails +! ." CLOSE ASSERT " _lc-checks @ . CR THEN ;

\ Descriptor ABI: offset 152 is now close negotiation, size remains 160.
APP-DESC 160 = _lc-assert
CREATE _lc-abi APP-DESC ALLOT
_lc-abi APP-DESC-INIT
_lc-abi APP.REQUEST-CLOSE-XT _lc-abi - 152 = _lc-assert
_lc-abi APP.REQUEST-CLOSE-XT @ 0= _lc-assert
APP-CLOSE-D-ALLOW APP-CLOSE-DECISION-VALID? _lc-assert
APP-CLOSE-D-CANCEL APP-CLOSE-DECISION-VALID? _lc-assert
APP-CLOSE-D-DEFER APP-CLOSE-DECISION-VALID? _lc-assert
99 APP-CLOSE-DECISION-VALID? 0= _lc-assert

\ A valid minimal component/app pair for direct shell tests.
CREATE _lc-comp COMP-DESC ALLOT
_lc-comp COMP-DESC-INIT
S" test.close.shell" _lc-comp COMP.ID-U ! _lc-comp COMP.ID-A !
CREATE _lc-desc APP-DESC ALLOT

VARIABLE _lc-instance
VARIABLE _lc-requests
VARIABLE _lc-shutdowns
VARIABLE _lc-mode

: _lc-requit  ( -- ) ASHELL-QUIT ;
: _lc-arm-requit  ( -- ) ['] _lc-requit ASHELL-POST ;

: _lc-init  ( instance -- )
    _lc-instance ! ASHELL-QUIT ;

: _lc-shutdown  ( instance -- )
    _lc-instance @ = _lc-assert
    1 _lc-shutdowns +! ;

: _lc-request  ( reason instance -- decision )
    _lc-instance @ = _lc-assert
    APP-CLOSE-R-QUIT = _lc-assert
    1 _lc-requests +!
    _lc-mode @ 0= IF
        _lc-requests @ 1 = IF
            _lc-arm-requit APP-CLOSE-D-CANCEL EXIT
        THEN
        _lc-requests @ 2 = IF
            _lc-arm-requit APP-CLOSE-D-DEFER EXIT
        THEN
        APP-CLOSE-D-ALLOW EXIT
    THEN
    _lc-mode @ 1 = IF
        _lc-requests @ 1 = IF
            _lc-arm-requit -77 THROW
        THEN
        APP-CLOSE-D-ALLOW EXIT
    THEN
    _lc-requests @ 1 = IF
        _lc-arm-requit 99 EXIT
    THEN
    APP-CLOSE-D-ALLOW ;

: _lc-fill  ( -- )
    _lc-desc APP-DESC-INIT
    _lc-comp _lc-desc APP.COMP-DESC !
    ['] _lc-init _lc-desc APP.INIT-XT !
    ['] _lc-shutdown _lc-desc APP.SHUTDOWN-XT !
    ['] _lc-request _lc-desc APP.REQUEST-CLOSE-XT ! ;

: _lc-shell-case  ( mode expected-requests -- )
    >R _lc-mode ! 0 _lc-requests ! 0 _lc-shutdowns !
    _lc-fill _lc-desc ASHELL-RUN
    _lc-requests @ R> = _lc-assert
    _lc-shutdowns @ 1 = _lc-assert
    ASHELL-DESC 0= _lc-assert ;

: _lc-run-shell-case  ( -- )
    _LC-FULL-PROFILE 0= IF
        0 3 _lc-shell-case         \ CANCEL, DEFER, then ALLOW
    THEN ;
_lc-run-shell-case

\ Validate THROW and invalid-return normalization directly; the loop case
\ above proves that fail-closed decisions preserve a running app.
_lc-fill
_lc-comp CINST-NEW 0= _lc-assert _lc-instance !
_lc-desc _ASHELL-DESC ! _lc-instance @ _ASHELL-INST !
1 _lc-mode ! 0 _lc-requests !
APP-CLOSE-R-QUIT ASHELL-REQUEST-CLOSE
    APP-CLOSE-D-CANCEL = _lc-assert
_lc-requests @ 1 = _lc-assert
0 _ASHELL-POST-HEAD ! 0 _ASHELL-POST-TAIL !
2 _lc-mode ! 0 _lc-requests !
APP-CLOSE-R-QUIT ASHELL-REQUEST-CLOSE
    APP-CLOSE-D-CANCEL = _lc-assert
_lc-requests @ 1 = _lc-assert
0 _ASHELL-DESC ! 0 _ASHELL-INST !
0 _ASHELL-POST-HEAD ! 0 _ASHELL-POST-TAIL !
_lc-instance @ CINST-FREE

\ Teardown containment: cleanup-only faults surface after all shell-owned
\ state is reset, while setup/loop faults retain precedence.
CREATE _lf-comp COMP-DESC ALLOT
_lf-comp COMP-DESC-INIT
S" test.close.fault" _lf-comp COMP.ID-U ! _lf-comp COMP.ID-A !
CREATE _lf-desc APP-DESC ALLOT
VARIABLE _lf-instance
VARIABLE _lf-mode
VARIABLE _lf-shutdowns

: _lf-loop-fault  ( -- ) -81 THROW ;
: _lf-init  ( instance -- )
    _lf-instance !
    _lf-mode @ 2 = IF -83 THROW THEN
    _lf-mode @ 1 = IF ['] _lf-loop-fault ASHELL-POST EXIT THEN
    ASHELL-QUIT ;
: _lf-shutdown  ( instance -- )
    _lf-instance @ = _lc-assert
    1 _lf-shutdowns +!
    -82 THROW ;
: _lf-fill  ( -- )
    _lf-desc APP-DESC-INIT
    _lf-comp _lf-desc APP.COMP-DESC !
    ['] _lf-init _lf-desc APP.INIT-XT !
    ['] _lf-shutdown _lf-desc APP.SHUTDOWN-XT ! ;
: _lf-run  ( -- ) _lf-fill _lf-desc ASHELL-RUN ;
: _lf-structural-clean?  ( -- flag )
    _ASHELL-DESC @ 0=
    _ASHELL-INST @ 0= AND
    _ASHELL-RGN @ 0= AND
    _ASHELL-UIDL-BUF @ 0= AND
    _ASHELL-HAS-UIDL @ 0= AND
    ASHELL-ACTIVE-CTX 0= AND
    _ASHELL-RUNNING @ 0= AND
    APP-SCREEN 0= AND ;
: _lf-case  ( mode expected-ior -- )
    >R _lf-mode ! 0 _lf-shutdowns !
    ['] _lf-run CATCH R> = _lc-assert
    _lf-shutdowns @ 1 = _lc-assert
    _lf-structural-clean? _lc-assert ;

: _lf-run-cases  ( -- )
    _LC-FULL-PROFILE 0= IF
        0 -82 _lf-case             \ no primary: cleanup error surfaces
        1 -81 _lf-case             \ loop primary beats cleanup error
        2 -83 _lf-case             \ setup primary beats cleanup error
    THEN ;
_lf-run-cases

\ Deferred actions stop at a close boundary.  The second action remains
\ queued across CANCEL and runs only after the owner loop is re-armed.
CREATE _lb-desc APP-DESC ALLOT
VARIABLE _lb-second
VARIABLE _lb-requests
: _lb-first  ( -- ) ASHELL-QUIT ;
: _lb-second-action  ( -- ) 1 _lb-second +! ASHELL-QUIT ;
: _lb-init  ( instance -- )
    DROP
    ['] _lb-first ASHELL-POST
    ['] _lb-second-action ASHELL-POST ;
: _lb-request  ( reason instance -- decision )
    2DROP 1 _lb-requests +!
    _lb-requests @ 1 = IF
        _lb-second @ 0= _lc-assert
        APP-CLOSE-D-CANCEL EXIT
    THEN
    _lb-second @ 1 = _lc-assert
    APP-CLOSE-D-ALLOW ;
: _lb-fill  ( -- )
    _lb-desc APP-DESC-INIT
    _lf-comp _lb-desc APP.COMP-DESC !
    ['] _lb-init _lb-desc APP.INIT-XT !
    ['] _lb-request _lb-desc APP.REQUEST-CLOSE-XT ! ;
: _lb-run-case  ( -- )
    _LC-FULL-PROFILE 0= IF
        0 _lb-second ! 0 _lb-requests !
        _lb-fill _lb-desc ASHELL-RUN
        _lb-second @ 1 = _lc-assert
        _lb-requests @ 2 = _lc-assert
    THEN ;
_lb-run-case

\ A tick-triggered quit must negotiate before another paint callback.
CREATE _lt-desc APP-DESC ALLOT
VARIABLE _lt-paints
: _lt-init  ( instance -- )
    DROP 1 ASHELL-TICK-MS! 0 _ASHELL-LAST-TICK ! ;
: _lt-tick  ( instance -- ) DROP ASHELL-QUIT ;
: _lt-paint  ( instance -- ) DROP 1 _lt-paints +! ;
: _lt-fill  ( -- )
    _lt-desc APP-DESC-INIT
    _lf-comp _lt-desc APP.COMP-DESC !
    ['] _lt-init _lt-desc APP.INIT-XT !
    ['] _lt-tick _lt-desc APP.TICK-XT !
    ['] _lt-paint _lt-desc APP.PAINT-XT ! ;
: _lt-run-case  ( -- )
    _LC-FULL-PROFILE 0= IF
        0 _lt-paints ! _lt-fill _lt-desc ASHELL-RUN
        _lt-paints @ 1 = _lc-assert
        50 ASHELL-TICK-MS!
    THEN ;
_lt-run-case

\ Provision the blank Practice store required by a real Desk instance.
CREATE _lc-practice-head PHEAD-SIZE ALLOT
CREATE _lc-practice-out PHEAD-SIZE ALLOT
CREATE _lc-practice-store PHEADVFS-SIZE ALLOT
: _lc-practice-id!  ( value id -- ) DUP RID-CLEAR ! ;
: _lc-practice-slot?  ( path-a path-u -- flag )
    VFS-OPEN DUP IF VFS-CLOSE -1 ELSE DROP 0 THEN ;
: _lc-practice-present?  ( -- flag )
    S" /practice-head-a.bin" _lc-practice-slot?
    S" /practice-head-b.bin" _lc-practice-slot? OR ;
: _lc-practice-provision  ( -- )
    _lc-practice-present? IF EXIT THEN
    VFS-CUR _lc-practice-store PHEADVFS-INIT
        PHEADVFS-S-OK = _lc-assert
    _lc-practice-out _lc-practice-store PHEADVFS-LOAD
        PHEADVFS-S-RECOVERY = _lc-assert
    _lc-practice-head PHEAD-INIT
    1 _lc-practice-head PHEAD.ID _lc-practice-id!
    2 _lc-practice-head PHEAD.CURRENT-ROOT _lc-practice-id!
    _lc-practice-head _lc-practice-store PHEADVFS-REINITIALIZE
        PHEADVFS-S-OK = _lc-assert ;
_lc-practice-provision
." LC-M2-PROVISION" CR

\ Real child with inline UIDL: request-close and shutdown must both see
\ this child's context and activation binding, never Desk/another child.
CREATE _dc-comp COMP-DESC ALLOT
_dc-comp COMP-DESC-INIT
S" test.close.child" _dc-comp COMP.ID-U ! _dc-comp COMP.ID-A !
CREATE _dc-comp-b COMP-DESC ALLOT
_dc-comp-b COMP-DESC-INIT
S" test.close.child.b" _dc-comp-b COMP.ID-U ! _dc-comp-b COMP.ID-A !
CREATE _dc-desc APP-DESC ALLOT
CREATE _dc-desc-b APP-DESC ALLOT
VARIABLE _dc-active
VARIABLE _dc-expected-reason
VARIABLE _dc-decision
VARIABLE _dc-mode
VARIABLE _dc-requests
VARIABLE _dc-shutdowns
VARIABLE _dc-quit-init
VARIABLE _dc-activate-throws
VARIABLE _dc-shutdown-throws

: _dc-uidl  ( -- a u )
    S" <uidl><region><label id=close-marker text=Close/></region></uidl>" ;
: _dc-activate  ( instance -- )
    _dc-active !
    _dc-activate-throws @ IF -90 THROW THEN ;
: _dc-init  ( instance -- )
    DROP _dc-quit-init @ IF ASHELL-QUIT THEN ;
: _dc-context-ok  ( -- flag )
    S" close-marker" UTUI-BY-ID 0<> ;
: _dc-request  ( reason instance -- decision )
    _dc-active @ = _lc-assert
    _dc-expected-reason @ = _lc-assert
    _dc-context-ok _lc-assert
    1 _dc-requests +!
    _dc-mode @ 1 = IF
        _dc-requests @ 1 = IF
            _lc-arm-requit APP-CLOSE-D-CANCEL EXIT
        THEN
        APP-CLOSE-D-ALLOW EXIT
    THEN
    _dc-mode @ 2 = IF -92 THROW THEN
    _dc-mode @ 3 = IF 99 EXIT THEN
    _dc-decision @ ;
: _dc-shutdown  ( instance -- )
    _dc-active @ = _lc-assert
    _dc-context-ok _lc-assert
    1 _dc-shutdowns +!
    _dc-shutdown-throws @ _dc-shutdowns @ 1 = AND IF -91 THROW THEN ;
: _dc-fill-one  ( desc -- )
    DUP APP-DESC-INIT
    _dc-comp OVER APP.COMP-DESC !
    ['] _dc-init OVER APP.INIT-XT !
    ['] _dc-shutdown OVER APP.SHUTDOWN-XT !
    ['] _dc-activate OVER APP.ACTIVATE-XT !
    ['] _dc-request OVER APP.REQUEST-CLOSE-XT !
    _dc-uidl NIP OVER APP.UIDL-U !
    _dc-uidl DROP SWAP APP.UIDL-A ! ;
: _dc-fill  ( -- ) _dc-desc _dc-fill-one ;
: _dc-fill-b  ( -- )
    _dc-desc-b APP-DESC-INIT
    _dc-comp-b _dc-desc-b APP.COMP-DESC !
    ['] _dc-init _dc-desc-b APP.INIT-XT !
    ['] _dc-shutdown _dc-desc-b APP.SHUTDOWN-XT !
    ['] _dc-activate _dc-desc-b APP.ACTIVATE-XT !
    ['] _dc-request _dc-desc-b APP.REQUEST-CLOSE-XT !
    _dc-uidl NIP _dc-desc-b APP.UIDL-U !
    _dc-uidl DROP _dc-desc-b APP.UIDL-A ! ;

\ Direct Desk child close: CANCEL/DEFER preserve the whole slot; ALLOW
\ shuts it down exactly once and removes it.
VARIABLE _dc-id
VARIABLE _dc-slot
VARIABLE _dc-inst
VARIABLE _dc-uctx
VARIABLE _dc-rgn
VARIABLE _dc-state
VARIABLE _dc-focus
VARIABLE _dc-desk-inst

: _dc-snapshot  ( -- )
    _dc-id @ _DESK-FIND-ID DUP _dc-slot !
    DUP _SL-INST @ _dc-inst !
    DUP _SL-UCTX @ _dc-uctx !
    DUP _SL-RGN @ _dc-rgn !
    _SL-STATE @ _dc-state !
    _DESK-FOCUS-SA @ _dc-focus ! ;

: _dc-preserved?  ( -- flag )
    _dc-id @ _DESK-FIND-ID DUP _dc-slot @ =
    OVER _SL-INST @ _dc-inst @ = AND
    OVER _SL-UCTX @ _dc-uctx @ = AND
    OVER _SL-RGN @ _dc-rgn @ = AND
    OVER _SL-STATE @ _dc-state @ = AND
    SWAP DROP
    _DESK-FOCUS-SA @ _dc-focus @ = AND ;

\ Two distinct children pin aggregate host-close precedence and prove that
\ each callback runs in its own UIDL context.  Negotiation alone must not
\ mutate either slot; finalization must not ask either child a second time.
CREATE _mx-comp-a COMP-DESC ALLOT
CREATE _mx-comp-b COMP-DESC ALLOT
CREATE _mx-desc-a APP-DESC ALLOT
CREATE _mx-desc-b APP-DESC ALLOT
VARIABLE _mx-ai  VARIABLE _mx-bi
VARIABLE _mx-aid VARIABLE _mx-bid
VARIABLE _mx-as  VARIABLE _mx-bs
VARIABLE _mx-au  VARIABLE _mx-bu
VARIABLE _mx-ar  VARIABLE _mx-br
VARIABLE _mx-ad  VARIABLE _mx-bd
VARIABLE _mx-requests-a VARIABLE _mx-requests-b
VARIABLE _mx-shutdowns-a VARIABLE _mx-shutdowns-b

: _mx-ctx-a?  ( -- flag )
    S" close-a" UTUI-BY-ID 0<>
    S" close-b" UTUI-BY-ID 0= AND ;
: _mx-ctx-b?  ( -- flag )
    S" close-b" UTUI-BY-ID 0<>
    S" close-a" UTUI-BY-ID 0= AND ;
: _mx-init-a  ( instance -- ) _mx-ai @ = _lc-assert ;
: _mx-init-b  ( instance -- ) _mx-bi @ = _lc-assert ;
: _mx-activate-a  ( instance -- )
    _mx-ai @ ?DUP IF = _lc-assert ELSE _mx-ai ! THEN ;
: _mx-activate-b  ( instance -- )
    _mx-bi @ ?DUP IF = _lc-assert ELSE _mx-bi ! THEN ;
: _mx-request-a  ( reason instance -- decision )
    _mx-ai @ = _lc-assert
    APP-CLOSE-R-HOST-SHUTDOWN = _lc-assert
    _mx-ctx-a? _lc-assert
    1 _mx-requests-a +! _mx-ad @ ;
: _mx-request-b  ( reason instance -- decision )
    _mx-bi @ = _lc-assert
    APP-CLOSE-R-HOST-SHUTDOWN = _lc-assert
    _mx-ctx-b? _lc-assert
    1 _mx-requests-b +! _mx-bd @ ;
: _mx-shutdown-a  ( instance -- )
    _mx-ai @ = _lc-assert _mx-ctx-a? _lc-assert
    1 _mx-shutdowns-a +! ;
: _mx-shutdown-b  ( instance -- )
    _mx-bi @ = _lc-assert _mx-ctx-b? _lc-assert
    1 _mx-shutdowns-b +! ;
: _mx-fill  ( -- )
    _mx-comp-a COMP-DESC-INIT
    S" test.close.mixed.a" _mx-comp-a COMP.ID-U ! _mx-comp-a COMP.ID-A !
    _mx-comp-b COMP-DESC-INIT
    S" test.close.mixed.b" _mx-comp-b COMP.ID-U ! _mx-comp-b COMP.ID-A !
    _mx-desc-a APP-DESC-INIT
    _mx-comp-a _mx-desc-a APP.COMP-DESC !
    ['] _mx-init-a _mx-desc-a APP.INIT-XT !
    ['] _mx-activate-a _mx-desc-a APP.ACTIVATE-XT !
    ['] _mx-request-a _mx-desc-a APP.REQUEST-CLOSE-XT !
    ['] _mx-shutdown-a _mx-desc-a APP.SHUTDOWN-XT !
    S" <uidl><region><label id=close-a text=A/></region></uidl>"
        _mx-desc-a APP.UIDL-U ! _mx-desc-a APP.UIDL-A !
    _mx-desc-b APP-DESC-INIT
    _mx-comp-b _mx-desc-b APP.COMP-DESC !
    ['] _mx-init-b _mx-desc-b APP.INIT-XT !
    ['] _mx-activate-b _mx-desc-b APP.ACTIVATE-XT !
    ['] _mx-request-b _mx-desc-b APP.REQUEST-CLOSE-XT !
    ['] _mx-shutdown-b _mx-desc-b APP.SHUTDOWN-XT !
    S" <uidl><region><label id=close-b text=B/></region></uidl>"
        _mx-desc-b APP.UIDL-U ! _mx-desc-b APP.UIDL-A ! ;
: _mx-snapshot  ( -- )
    _mx-aid @ _DESK-FIND-ID DUP _mx-as !
        DUP _SL-UCTX @ _mx-au ! _SL-RGN @ _mx-ar !
    _mx-bid @ _DESK-FIND-ID DUP _mx-bs !
        DUP _SL-UCTX @ _mx-bu ! _SL-RGN @ _mx-br ! ;
: _mx-a-preserved?  ( -- flag )
    _mx-aid @ _DESK-FIND-ID DUP _mx-as @ =
    OVER _SL-INST @ _mx-ai @ = AND
    OVER _SL-UCTX @ _mx-au @ = AND
    SWAP _SL-RGN @ _mx-ar @ = AND ;
: _mx-b-preserved?  ( -- flag )
    _mx-bid @ _DESK-FIND-ID DUP _mx-bs @ =
    OVER _SL-INST @ _mx-bi @ = AND
    OVER _SL-UCTX @ _mx-bu @ = AND
    SWAP _SL-RGN @ _mx-br @ = AND ;
: _mx-preserved?  ( -- flag )
    _mx-a-preserved? _mx-b-preserved? AND ;
: _mx-negotiate  ( -- decision )
    APP-CLOSE-R-HOST-SHUTDOWN _dc-desk-inst @ DESK-REQUEST-CLOSE-CB ;
: _mx-run  ( -- )
    _mx-fill
    0 _mx-requests-a ! 0 _mx-requests-b !
    0 _mx-shutdowns-a ! 0 _mx-shutdowns-b !
    _mx-desc-a DESK-LAUNCH _mx-aid !
    _mx-desc-b DESK-LAUNCH _mx-bid !
    _mx-snapshot
    APP-CLOSE-D-ALLOW _mx-ad ! APP-CLOSE-D-DEFER _mx-bd !
    _mx-negotiate APP-CLOSE-D-DEFER = _lc-assert
    _mx-preserved? _lc-assert
    APP-CLOSE-D-DEFER _mx-ad ! APP-CLOSE-D-CANCEL _mx-bd !
    _mx-negotiate APP-CLOSE-D-CANCEL = _lc-assert
    _mx-preserved? _lc-assert
    APP-CLOSE-D-ALLOW _mx-ad ! APP-CLOSE-D-ALLOW _mx-bd !
    _mx-negotiate APP-CLOSE-D-ALLOW = _lc-assert
    _mx-preserved? _lc-assert
    _mx-requests-a @ 3 = _lc-assert _mx-requests-b @ 3 = _lc-assert
    _DESK-HOST AHOST-DRAIN 0= _lc-assert
    DESK-RELAYOUT
    DESK-SLOT-COUNT 0= _lc-assert
    _mx-shutdowns-a @ 1 = _lc-assert _mx-shutdowns-b @ 1 = _lc-assert
    _mx-requests-a @ 3 = _lc-assert _mx-requests-b @ 3 = _lc-assert
    ASHELL-ACTIVE-CTX 0= _lc-assert ;

: _dc-desk-init  ( desk-instance -- )
    DUP _dc-desk-inst ! DESK-INIT-CB
    _dc-fill
    0 _dc-mode ! 0 _dc-quit-init ! 0 _dc-requests ! 0 _dc-shutdowns !
    0 _dc-activate-throws ! 0 _dc-shutdown-throws !
    APP-CLOSE-R-WINDOW _dc-expected-reason !
    _dc-desc DESK-LAUNCH _dc-id !
    _dc-snapshot
    \ Activation/context-entry failure is a fail-closed negotiation, not
    \ a stranded active context or a partially destroyed slot.
    -1 _dc-activate-throws !
    _dc-id @ APP-CLOSE-R-WINDOW DESK-REQUEST-CLOSE-ID
        APP-CLOSE-D-CANCEL = _lc-assert
    DESK-SLOT-COUNT 1 = _lc-assert
    _dc-requests @ 0= _lc-assert
    _dc-preserved? _lc-assert
    ASHELL-ACTIVE-CTX 0= _lc-assert
    0 _dc-activate-throws !
    APP-CLOSE-D-CANCEL _dc-decision !
    _dc-id @ APP-CLOSE-R-WINDOW DESK-REQUEST-CLOSE-ID
        APP-CLOSE-D-CANCEL = _lc-assert
    DESK-SLOT-COUNT 1 = _lc-assert _dc-shutdowns @ 0= _lc-assert
    _dc-preserved? _lc-assert
    APP-CLOSE-D-DEFER _dc-decision !
    _dc-id @ APP-CLOSE-R-WINDOW DESK-REQUEST-CLOSE-ID
        APP-CLOSE-D-DEFER = _lc-assert
    DESK-SLOT-COUNT 1 = _lc-assert _dc-shutdowns @ 0= _lc-assert
    _dc-preserved? _lc-assert
    \ Callback THROW and invalid return normalize to CANCEL and preserve
    \ exact slot identity, ownership, geometry, focus, and context.
    2 _dc-mode !
    _dc-id @ APP-CLOSE-R-WINDOW DESK-REQUEST-CLOSE-ID
        APP-CLOSE-D-CANCEL = _lc-assert
    _dc-preserved? _lc-assert _dc-shutdowns @ 0= _lc-assert
    3 _dc-mode !
    _dc-id @ APP-CLOSE-R-WINDOW DESK-REQUEST-CLOSE-ID
        APP-CLOSE-D-CANCEL = _lc-assert
    _dc-preserved? _lc-assert _dc-shutdowns @ 0= _lc-assert
    0 _dc-mode !
    APP-CLOSE-D-ALLOW _dc-decision !
    _dc-id @ APP-CLOSE-R-WINDOW DESK-REQUEST-CLOSE-ID
        APP-CLOSE-D-ALLOW = _lc-assert
    DESK-SLOT-COUNT 0= _lc-assert _dc-shutdowns @ 1 = _lc-assert
    _dc-requests @ 5 = _lc-assert
    \ Force-finalization after activation entry fails must not call a child
    \ shutdown callback in an uncertain context, but must still unlink and
    \ release the host-owned slot.
    _dc-desc DESK-LAUNCH _dc-id !
    -1 _dc-activate-throws !
    _DESK-HOST AHOST-DRAIN -90 = _lc-assert
    DESK-SLOT-COUNT 0= _lc-assert
    _dc-shutdowns @ 1 = _lc-assert
    ASHELL-ACTIVE-CTX 0= _lc-assert
    0 _dc-activate-throws !
    _mx-run
    ASHELL-QUIT ;

." LC-M3-BEFORE-FILL" CR
_DESK-FILL-DESC
." LC-M4-AFTER-FILL" CR
' _dc-desk-init DESK-DESC APP.INIT-XT !
." LC-M5-BEFORE-ASHELL" CR
DESK-DESC ASHELL-RUN
." LC-M6-AFTER-ASHELL" CR

\ Top-level Desk close negotiates every child first.  The first child
\ CANCEL keeps Desk alive; the second pass ALLOW is remembered by the
\ shell, and Desk shutdown force-cleans without a third prompt.
_dc-fill
1 _dc-mode ! -1 _dc-quit-init ! 0 _dc-requests ! 0 _dc-shutdowns !
0 _dc-activate-throws ! 0 _dc-shutdown-throws !
APP-CLOSE-R-HOST-SHUTDOWN _dc-expected-reason !
_dc-desc DESK-QUEUE-LAUNCH
." LC-M7-BEFORE-DESK" CR
DESK-RUN
." LC-M8-AFTER-DESK" CR
_dc-requests @ 2 = _lc-assert
_dc-shutdowns @ 1 = _lc-assert

\ Top-level fault containment: the first child shutdown throws, but Desk
\ still unlinks/frees it, closes the second child, drains the list, and only
\ then surfaces the first cleanup error through ASHELL-RUN.
VARIABLE _dc-top-inst
VARIABLE _dc-top-ior
VARIABLE _dc-top-slots
: _dc-call-desk-shutdown  ( -- )
    _dc-top-inst @ DESK-SHUTDOWN-CB ;
: _dc-desk-shutdown-wrap  ( instance -- )
    _dc-top-inst !
    ['] _dc-call-desk-shutdown CATCH _dc-top-ior !
    DESK-SLOT-COUNT _dc-top-slots !
    _dc-top-ior @ ?DUP IF THROW THEN ;
: _dc-run-fault-desk  ( -- ) DESK-DESC ASHELL-RUN ;

_dc-fill _dc-fill-b
0 _dc-mode ! -1 _dc-quit-init ! 0 _dc-requests ! 0 _dc-shutdowns !
0 _dc-activate-throws ! -1 _dc-shutdown-throws !
APP-CLOSE-D-ALLOW _dc-decision !
APP-CLOSE-R-HOST-SHUTDOWN _dc-expected-reason !
_dc-desc DESK-QUEUE-LAUNCH
_dc-desc-b DESK-QUEUE-LAUNCH
_DESK-FILL-DESC
' _dc-desk-shutdown-wrap DESK-DESC APP.SHUTDOWN-XT !
' _dc-run-fault-desk CATCH -91 = _lc-assert
_dc-top-ior @ -91 = _lc-assert
_dc-top-slots @ 0= _lc-assert
_dc-requests @ 2 = _lc-assert
_dc-shutdowns @ 2 = _lc-assert
ASHELL-ACTIVE-CTX 0= _lc-assert
_lf-structural-clean? _lc-assert

_lc-fails @ 0= IF
    ." APPLET CLOSE PASS " _lc-checks @ .
ELSE
    ." APPLET CLOSE FAIL " _lc-fails @ .
THEN CR
"""

_DESK_MARKER = "\\ Provision the blank Practice store required by a real Desk instance."
_RUNTIME_MARKER = '." LC-M1-REQUIRE" CR\n'
_SHELL_PREFIX = AUTOEXEC.split(_DESK_MARKER, 1)[0]
_SHELL_PREFIX = _SHELL_PREFIX.replace(
    "REQUIRE tui/applets/desk/desk.f",
    "REQUIRE tui/app-shell.f",
    1,
).replace(
    "ENTER-USERLAND\n",
    "ENTER-USERLAND\n-1 CONSTANT GUARDED\n",
    1,
).replace(
    _RUNTIME_MARKER,
    _RUNTIME_MARKER + "0 CONSTANT _LC-FULL-PROFILE\n",
    1,
)
SHELL_AUTOEXEC = _SHELL_PREFIX + r"""
_lc-fails @ 0= IF
    ." APPLET SHELL CLOSE PASS " _lc-checks @ .
ELSE
    ." APPLET SHELL CLOSE FAIL " _lc-fails @ .
THEN CR
"""

DESK_AUTOEXEC = AUTOEXEC.replace(
    _RUNTIME_MARKER,
    _RUNTIME_MARKER + "-1 CONSTANT _LC-FULL-PROFILE\n",
    1,
)


def _register_profiles() -> None:
    harness.PROFILES[SHELL_PROFILE] = harness.Profile(
        roots=("tui/app-shell.f",),
        resources=(),
        autoexec=SHELL_AUTOEXEC,
        ready_markers=("APPLET SHELL CLOSE PASS",),
        stable_markers=("APPLET SHELL CLOSE PASS",),
        failure_markers=("APPLET SHELL CLOSE FAIL", "CLOSE ASSERT"),
        linked=True,
    )
    harness.PROFILES[DESK_PROFILE] = harness.Profile(
        roots=("tui/applets/desk/desk.f",),
        resources=(),
        autoexec=DESK_AUTOEXEC,
        ready_markers=("APPLET CLOSE PASS",),
        stable_markers=("APPLET CLOSE PASS",),
        failure_markers=("APPLET CLOSE FAIL", "CLOSE ASSERT"),
        linked=True,
    )


def _run_profile(name: str, image_path: Path, timeout: float) -> bool:
    image = harness.build_image(name, image_path)
    return harness.smoke(
        name,
        image,
        cols=100,
        rows=32,
        max_steps=(8_000_000_000 if name == DESK_PROFILE else 3_000_000_000),
        timeout=timeout,
    )

def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--timeout", type=float)
    parser.add_argument(
        "--profile",
        choices=("shell", "desk", "all"),
        default="all",
        help="run one independently-built close profile or both (default)",
    )
    args = parser.parse_args()
    _register_profiles()
    timeout = args.timeout or 120.0
    ok = True
    if args.profile in ("shell", "all"):
        ok = _run_profile(SHELL_PROFILE, SHELL_IMAGE, timeout) and ok
    if args.profile in ("desk", "all"):
        ok = _run_profile(DESK_PROFILE, DESK_IMAGE, timeout) and ok
    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
