#!/usr/bin/env python3
"""Focused production-image regression for APP-DESC close negotiation.

The deterministic profile exercises the real guarded APP-SHELL lifecycle.
Desk's larger linked lifecycle is covered by the production ``desktop`` smoke
journey; keeping it out of this focused fixture avoids conflating a shell
contract failure with full-image bootstrap/linking failures.
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
    _ASHELL-ACTIVE-CTX @ 0= AND
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
CREATE _dc-desc APP-DESC ALLOT
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
    _dc-mode @ IF
        _dc-requests @ 1 = IF
            _lc-arm-requit APP-CLOSE-D-CANCEL EXIT
        THEN
        APP-CLOSE-D-ALLOW EXIT
    THEN
    _dc-decision @ ;
: _dc-shutdown  ( instance -- )
    _dc-active @ = _lc-assert
    _dc-context-ok _lc-assert
    1 _dc-shutdowns +!
    _dc-shutdown-throws @ _dc-shutdowns @ 1 = AND IF -91 THROW THEN ;
: _dc-fill  ( -- )
    _dc-desc APP-DESC-INIT
    _dc-comp _dc-desc APP.COMP-DESC !
    ['] _dc-init _dc-desc APP.INIT-XT !
    ['] _dc-shutdown _dc-desc APP.SHUTDOWN-XT !
    ['] _dc-activate _dc-desc APP.ACTIVATE-XT !
    ['] _dc-request _dc-desc APP.REQUEST-CLOSE-XT !
    _dc-uidl NIP _dc-desc APP.UIDL-U !
    _dc-uidl DROP _dc-desc APP.UIDL-A ! ;

\ Direct Desk child close: CANCEL/DEFER preserve the whole slot; ALLOW
\ shuts it down exactly once and removes it.
VARIABLE _dc-id
: _dc-desk-init  ( desk-instance -- )
    DUP DESK-INIT-CB DROP
    _dc-fill
    0 _dc-mode ! 0 _dc-quit-init ! 0 _dc-requests ! 0 _dc-shutdowns !
    0 _dc-activate-throws ! 0 _dc-shutdown-throws !
    APP-CLOSE-R-WINDOW _dc-expected-reason !
    _dc-desc DESK-LAUNCH _dc-id !
    \ Activation/context-entry failure is a fail-closed negotiation, not
    \ a stranded active context or a partially destroyed slot.
    -1 _dc-activate-throws !
    _dc-id @ APP-CLOSE-R-WINDOW DESK-REQUEST-CLOSE-ID
        APP-CLOSE-D-CANCEL = _lc-assert
    DESK-SLOT-COUNT 1 = _lc-assert
    _dc-requests @ 0= _lc-assert
    _ASHELL-ACTIVE-CTX @ 0= _lc-assert
    0 _dc-activate-throws !
    APP-CLOSE-D-CANCEL _dc-decision !
    _dc-id @ APP-CLOSE-R-WINDOW DESK-REQUEST-CLOSE-ID
        APP-CLOSE-D-CANCEL = _lc-assert
    DESK-SLOT-COUNT 1 = _lc-assert _dc-shutdowns @ 0= _lc-assert
    APP-CLOSE-D-DEFER _dc-decision !
    _dc-id @ APP-CLOSE-R-WINDOW DESK-REQUEST-CLOSE-ID
        APP-CLOSE-D-DEFER = _lc-assert
    DESK-SLOT-COUNT 1 = _lc-assert _dc-shutdowns @ 0= _lc-assert
    APP-CLOSE-D-ALLOW _dc-decision !
    _dc-id @ APP-CLOSE-R-WINDOW DESK-REQUEST-CLOSE-ID
        APP-CLOSE-D-ALLOW = _lc-assert
    DESK-SLOT-COUNT 0= _lc-assert _dc-shutdowns @ 1 = _lc-assert
    _dc-requests @ 3 = _lc-assert
    \ Force-finalization after activation entry fails must not call a child
    \ shutdown callback in an uncertain context, but must still unlink and
    \ release the host-owned slot.
    _dc-desc DESK-LAUNCH _dc-id !
    -1 _dc-activate-throws !
    _dc-id @ _DESK-FIND-ID _DESK-CLOSE-SA-FORCE -90 = _lc-assert
    DESK-SLOT-COUNT 0= _lc-assert
    _dc-shutdowns @ 1 = _lc-assert
    _ASHELL-ACTIVE-CTX @ 0= _lc-assert
    0 _dc-activate-throws !
    ASHELL-QUIT ;

." LC-M3-BEFORE-FILL" CR
_DESK-FILL-DESC
." LC-M4-AFTER-FILL" CR
['] _dc-desk-init DESK-DESC APP.INIT-XT !
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

_dc-fill
0 _dc-mode ! -1 _dc-quit-init ! 0 _dc-requests ! 0 _dc-shutdowns !
0 _dc-activate-throws ! -1 _dc-shutdown-throws !
APP-CLOSE-D-ALLOW _dc-decision !
APP-CLOSE-R-HOST-SHUTDOWN _dc-expected-reason !
_dc-desc DESK-QUEUE-LAUNCH
_dc-desc DESK-QUEUE-LAUNCH
_DESK-FILL-DESC
['] _dc-desk-shutdown-wrap DESK-DESC APP.SHUTDOWN-XT !
['] _dc-run-fault-desk CATCH -91 = _lc-assert
_dc-top-ior @ -91 = _lc-assert
_dc-top-slots @ 0= _lc-assert
_dc-requests @ 2 = _lc-assert
_dc-shutdowns @ 2 = _lc-assert
_ASHELL-ACTIVE-CTX @ 0= _lc-assert
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

def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--timeout", type=float)
    args = parser.parse_args()
    harness.PROFILES[SHELL_PROFILE] = harness.Profile(
        roots=("tui/app-shell.f",),
        resources=(),
        autoexec=SHELL_AUTOEXEC,
        ready_markers=("APPLET SHELL CLOSE PASS",),
        stable_markers=("APPLET SHELL CLOSE PASS",),
        failure_markers=("APPLET SHELL CLOSE FAIL", "CLOSE ASSERT"),
        linked=True,
    )
    image = harness.build_image(SHELL_PROFILE, SHELL_IMAGE)
    return 0 if harness.smoke(
        SHELL_PROFILE,
        image,
        cols=100,
        rows=32,
        max_steps=3_000_000_000,
        timeout=args.timeout or 120.0,
    ) else 1


if __name__ == "__main__":
    raise SystemExit(main())
