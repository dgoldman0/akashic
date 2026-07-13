#!/usr/bin/env python3
"""Focused synchronous request-bus reentrancy contracts."""

from __future__ import annotations

from pathlib import Path
import sys


LOCAL_TESTING = Path(__file__).resolve().parent
sys.path.insert(0, str(LOCAL_TESTING))

from akashic_tui import Profile, PROFILES, build_image, smoke  # noqa: E402


PROFILE_NAME = "request-bus-reentrancy"

AUTOEXEC = r'''\ autoexec.f - synchronous request-bus reentrancy contracts
ENTER-USERLAND
." [akashic] loading request-bus reentrancy contracts" CR
REQUIRE interop/endpoint.f

VARIABLE _rb-fails
VARIABLE _rb-checks
VARIABLE _rb-depth

: _rb-assert  ( flag -- )
    1 _rb-checks +!
    0= IF 1 _rb-fails +! ." ASSERT " _rb-checks @ . CR THEN ;

: _rb-stack  ( -- ) DEPTH _rb-depth @ = _rb-assert ;

VARIABLE _rb-registry
VARIABLE _rb-outer-bus
VARIABLE _rb-inner-bus
VARIABLE _rb-outer-instance
VARIABLE _rb-inner-instance
VARIABLE _rb-nested-request
VARIABLE _rb-nested-status
VARIABLE _rb-inner-ok-calls
VARIABLE _rb-handler-request
VARIABLE _rb-handler-nests

CREATE _rb-policy CPOLICY-SIZE ALLOT
VARIABLE _rb-policy-enabled
VARIABLE _rb-policy-calls
VARIABLE _rb-policy-nested-status

VARIABLE _rb-outer-ok
VARIABLE _rb-inner-ok
VARIABLE _rb-outer-stale
VARIABLE _rb-inner-stale
VARIABLE _rb-outer-throw
VARIABLE _rb-inner-throw
VARIABLE _rb-outer-policy
VARIABLE _rb-inner-policy

VARIABLE _rb-outer-ok-done
VARIABLE _rb-inner-ok-done
VARIABLE _rb-outer-stale-done
VARIABLE _rb-inner-stale-done
VARIABLE _rb-outer-throw-done
VARIABLE _rb-inner-throw-done
VARIABLE _rb-outer-policy-done
VARIABLE _rb-inner-policy-done

: _rb-complete  ( request -- )
    CBR.COMPLETE-DATA @ 1 SWAP +! ;

: _rb-outer-handler  ( request instance -- status )
    DROP _rb-handler-request !
    CBUS-DISPATCHING? _rb-assert
    _rb-handler-nests @ IF
        _rb-nested-request @ _rb-inner-bus @ CBUS-DISPATCH
        _rb-nested-status !
    THEN
    \ Whether nesting happened in policy or in this handler, the complete
    \ outer frame must be current before handler execution resumes.
    _rb-handler-request @ _CBD-REQ @ = _rb-assert
    _rb-outer-instance @ _CBD-INST @ = _rb-assert
    _rb-handler-request @ CBR.CAP @ _CBD-CAP @ = _rb-assert
    _rb-outer-bus @ _CBD-BUS @ = _rb-assert
    CBUS-S-OK ;

: _rb-inner-ok-handler  ( request instance -- status )
    2DROP 1 _rb-inner-ok-calls +! CBUS-S-OK ;

: _rb-inner-throw-handler  ( request instance -- status )
    2DROP -731 THROW ;

: _rb-policy-decide  ( principal effects context -- decision )
    2DROP DROP
    CBUS-DISPATCHING? _rb-assert
    _rb-policy-enabled @ IF
        1 _rb-policy-calls +!
        0 _rb-policy-enabled !
        _rb-inner-policy @ _rb-inner-bus @ CBUS-DISPATCH
            _rb-policy-nested-status !
    THEN
    CPOL-ALLOW ;

CREATE _rb-outer-cap CAP-DESC ALLOT
CREATE _rb-inner-caps CAP-DESC 2 * ALLOT

: _rb-inner-ok-cap     ( -- cap ) _rb-inner-caps ;
: _rb-inner-throw-cap  ( -- cap ) _rb-inner-caps CAP-DESC + ;

CREATE _rb-outer-component COMP-DESC ALLOT
CREATE _rb-inner-component COMP-DESC ALLOT

: _rb-capabilities-init  ( -- )
    _rb-outer-cap CAP-DESC-INIT
    CAP-K-COMMAND _rb-outer-cap CAP.KIND !
    S" org.akashic.test/nested-outer"
        _rb-outer-cap CAP.ID-U ! _rb-outer-cap CAP.ID-A !
    CAP-E-OBSERVE _rb-outer-cap CAP.EFFECTS !
    ['] _rb-outer-handler _rb-outer-cap CAP.HANDLER-XT !

    _rb-inner-ok-cap CAP-DESC-INIT
    CAP-K-COMMAND _rb-inner-ok-cap CAP.KIND !
    S" org.akashic.test/nested-ok"
        _rb-inner-ok-cap CAP.ID-U ! _rb-inner-ok-cap CAP.ID-A !
    CAP-E-OBSERVE _rb-inner-ok-cap CAP.EFFECTS !
    ['] _rb-inner-ok-handler _rb-inner-ok-cap CAP.HANDLER-XT !

    _rb-inner-throw-cap CAP-DESC-INIT
    CAP-K-COMMAND _rb-inner-throw-cap CAP.KIND !
    S" org.akashic.test/nested-throw"
        _rb-inner-throw-cap CAP.ID-U ! _rb-inner-throw-cap CAP.ID-A !
    CAP-E-OBSERVE _rb-inner-throw-cap CAP.EFFECTS !
    ['] _rb-inner-throw-handler _rb-inner-throw-cap CAP.HANDLER-XT ! ;

: _rb-components-init  ( -- )
    _rb-outer-component COMP-DESC-INIT
    S" org.akashic.test.request-bus.outer"
        _rb-outer-component COMP.ID-U ! _rb-outer-component COMP.ID-A !
    S" 1.0.0"
        _rb-outer-component COMP.VERSION-U !
        _rb-outer-component COMP.VERSION-A !
    _rb-outer-cap _rb-outer-component COMP.CAPS-A !
    1 _rb-outer-component COMP.CAPS-N !

    _rb-inner-component COMP-DESC-INIT
    S" org.akashic.test.request-bus.inner"
        _rb-inner-component COMP.ID-U ! _rb-inner-component COMP.ID-A !
    S" 1.0.0"
        _rb-inner-component COMP.VERSION-U !
        _rb-inner-component COMP.VERSION-A !
    _rb-inner-caps _rb-inner-component COMP.CAPS-A !
    2 _rb-inner-component COMP.CAPS-N ! ;

VARIABLE _rb-new-cap
VARIABLE _rb-new-instance

: _rb-request-new  ( cap instance -- request )
    _rb-new-instance ! _rb-new-cap !
    CBR-NEW DUP 0= _rb-assert DROP
    CPRINC-USER OVER CBR.PRINCIPAL !
    _rb-new-instance @ OVER CBR-TARGET!
    _rb-new-cap @ OVER CBR.CAP !
    ['] _rb-complete OVER CBR.COMPLETE-XT ! ;

: _rb-frame-restored  ( -- )
    CBUS-DISPATCHING? 0= _rb-assert
    _CBD-REQ @ 101 = _rb-assert
    _CBD-INST @ 102 = _rb-assert
    _CBD-CAP @ 103 = _rb-assert
    _CBD-BUS @ 104 = _rb-assert ;

: _rb-request-completed?  ( request -- flag )
    CBR.FLAGS @ CBR-F-COMPLETE AND 0<> ;

: _rb-setup  ( -- )
    _rb-capabilities-init _rb-components-init
    _rb-outer-component CINST-NEW DUP 0= _rb-assert DROP
        _rb-outer-instance !
    _rb-inner-component CINST-NEW DUP 0= _rb-assert DROP
        _rb-inner-instance !
    CREG-NEW DUP 0= _rb-assert DROP _rb-registry !
    _rb-outer-instance @ _rb-registry @ CREG-INST+ 0= _rb-assert
    _rb-inner-instance @ _rb-registry @ CREG-INST+ 0= _rb-assert
    _rb-registry @ 0 CBUS-NEW DUP 0= _rb-assert DROP _rb-outer-bus !
    _rb-registry @ 0 CBUS-NEW DUP 0= _rb-assert DROP _rb-inner-bus !
    _rb-policy CPOLICY-INIT
    ['] _rb-policy-decide _rb-policy CPOL.DECIDE-XT !
    _rb-policy _rb-outer-bus @ CBUS.POLICY !

    _rb-outer-cap _rb-outer-instance @ _rb-request-new
        DUP _rb-outer-ok ! _rb-outer-ok-done OVER CBR.COMPLETE-DATA ! DROP
    _rb-inner-ok-cap _rb-inner-instance @ _rb-request-new
        DUP _rb-inner-ok ! _rb-inner-ok-done OVER CBR.COMPLETE-DATA ! DROP
    _rb-outer-cap _rb-outer-instance @ _rb-request-new
        DUP _rb-outer-stale !
        _rb-outer-stale-done OVER CBR.COMPLETE-DATA ! DROP
    _rb-inner-ok-cap _rb-inner-instance @ _rb-request-new
        DUP _rb-inner-stale !
        _rb-inner-stale-done OVER CBR.COMPLETE-DATA ! DROP
    2 _rb-inner-stale @ CBR.EXPECT-REV !
    _rb-outer-cap _rb-outer-instance @ _rb-request-new
        DUP _rb-outer-throw !
        _rb-outer-throw-done OVER CBR.COMPLETE-DATA ! DROP
    _rb-inner-throw-cap _rb-inner-instance @ _rb-request-new
        DUP _rb-inner-throw !
        _rb-inner-throw-done OVER CBR.COMPLETE-DATA ! DROP
    _rb-outer-cap _rb-outer-instance @ _rb-request-new
        DUP _rb-outer-policy !
        _rb-outer-policy-done OVER CBR.COMPLETE-DATA ! DROP
    _rb-inner-ok-cap _rb-inner-instance @ _rb-request-new
        DUP _rb-inner-policy !
        _rb-inner-policy-done OVER CBR.COMPLETE-DATA ! DROP ;

: _rb-success-case  ( -- )
    -1 _rb-handler-nests !
    _rb-inner-ok @ _rb-nested-request !
    _rb-outer-ok @ _rb-outer-bus @ CBUS-DISPATCH
        CBUS-S-OK = _rb-assert
    _rb-nested-status @ CBUS-S-OK = _rb-assert
    _rb-outer-ok @ CBR.STATUS @ CBUS-S-OK = _rb-assert
    _rb-inner-ok @ CBR.STATUS @ CBUS-S-OK = _rb-assert
    _rb-outer-ok @ _rb-request-completed? _rb-assert
    _rb-inner-ok @ _rb-request-completed? _rb-assert
    _rb-outer-ok @ CBR-LIFECYCLE-BUSY? 0= _rb-assert
    _rb-inner-ok @ CBR-LIFECYCLE-BUSY? 0= _rb-assert
    _rb-outer-ok-done @ 1 = _rb-assert
    _rb-inner-ok-done @ 1 = _rb-assert
    _rb-inner-ok-calls @ 1 = _rb-assert
    _rb-frame-restored
    _rb-stack ;

: _rb-stale-case  ( -- )
    -1 _rb-handler-nests !
    _rb-inner-stale @ _rb-nested-request !
    _rb-outer-stale @ _rb-outer-bus @ CBUS-DISPATCH
        CBUS-S-OK = _rb-assert
    _rb-nested-status @ CBUS-S-STALE-REVISION = _rb-assert
    _rb-outer-stale @ CBR.STATUS @ CBUS-S-OK = _rb-assert
    _rb-inner-stale @ CBR.STATUS @ CBUS-S-STALE-REVISION = _rb-assert
    _rb-outer-stale @ _rb-request-completed? _rb-assert
    _rb-inner-stale @ _rb-request-completed? _rb-assert
    _rb-outer-stale-done @ 1 = _rb-assert
    _rb-inner-stale-done @ 1 = _rb-assert
    _rb-inner-ok-calls @ 1 = _rb-assert
    _rb-inner-instance @ CINST.REVISION @ 1 = _rb-assert
    _rb-frame-restored
    _rb-stack ;

: _rb-throw-case  ( -- )
    -1 _rb-handler-nests !
    _rb-inner-throw @ _rb-nested-request !
    _rb-outer-throw @ _rb-outer-bus @ CBUS-DISPATCH
        CBUS-S-OK = _rb-assert
    _rb-nested-status @ CBUS-S-FAILED = _rb-assert
    _rb-outer-throw @ CBR.STATUS @ CBUS-S-OK = _rb-assert
    _rb-inner-throw @ CBR.STATUS @ CBUS-S-FAILED = _rb-assert
    _rb-inner-throw @ CBR.ERROR-CODE @ -731 = _rb-assert
    _rb-inner-throw @ CBR.ERROR-U @ 0> _rb-assert
    _rb-outer-throw @ CBR.ERROR-CODE @ 0= _rb-assert
    _rb-outer-throw @ _rb-request-completed? _rb-assert
    _rb-inner-throw @ _rb-request-completed? _rb-assert
    _rb-outer-throw @ CBR-LIFECYCLE-BUSY? 0= _rb-assert
    _rb-inner-throw @ CBR-LIFECYCLE-BUSY? 0= _rb-assert
    _rb-outer-throw-done @ 1 = _rb-assert
    _rb-inner-throw-done @ 1 = _rb-assert
    _rb-frame-restored
    _rb-stack ;

: _rb-policy-case  ( -- )
    0 _rb-handler-nests !
    -1 _rb-policy-enabled !
    _rb-outer-policy @ _rb-outer-bus @ CBUS-DISPATCH
        CBUS-S-OK = _rb-assert
    _rb-policy-calls @ 1 = _rb-assert
    _rb-policy-nested-status @ CBUS-S-OK = _rb-assert
    _rb-outer-policy @ CBR.STATUS @ CBUS-S-OK = _rb-assert
    _rb-inner-policy @ CBR.STATUS @ CBUS-S-OK = _rb-assert
    _rb-outer-policy-done @ 1 = _rb-assert
    _rb-inner-policy-done @ 1 = _rb-assert
    _rb-frame-restored
    _rb-stack ;

: _rb-cleanup  ( -- )
    _rb-outer-ok @ CBR-FREE _rb-inner-ok @ CBR-FREE
    _rb-outer-stale @ CBR-FREE _rb-inner-stale @ CBR-FREE
    _rb-outer-throw @ CBR-FREE _rb-inner-throw @ CBR-FREE
    _rb-outer-policy @ CBR-FREE _rb-inner-policy @ CBR-FREE
    _rb-outer-bus @ CBUS-FREE _rb-inner-bus @ CBUS-FREE
    _rb-outer-instance @ _rb-registry @ CREG-INST- 0= _rb-assert
    _rb-inner-instance @ _rb-registry @ CREG-INST- 0= _rb-assert
    _rb-registry @ CREG-FREE
    _rb-outer-instance @ CINST-FREE
    _rb-inner-instance @ CINST-FREE
    _rb-stack ;

: _rb-run  ( -- )
    0 _rb-fails ! 0 _rb-checks ! 0 _rb-inner-ok-calls !
    0 _rb-policy-calls ! 0 _rb-policy-enabled !
    _rb-setup
    101 _CBD-REQ ! 102 _CBD-INST ! 103 _CBD-CAP ! 104 _CBD-BUS !
    DEPTH _rb-depth !
    _rb-success-case
    _rb-stale-case
    _rb-throw-case
    _rb-policy-case
    _rb-cleanup
    _rb-fails @ 0= IF
        ." REQUEST BUS REENTRANCY PASS " _rb-checks @ .
    ELSE
        ." REQUEST BUS REENTRANCY FAIL " _rb-fails @ .
        ." / " _rb-checks @ .
    THEN CR ;

_rb-run
'''


def test_request_bus_reentrancy(tmp_path: Path) -> None:
    PROFILES[PROFILE_NAME] = Profile(
        roots=("interop/endpoint.f",),
        resources=(),
        autoexec=AUTOEXEC,
        ready_markers=("REQUEST BUS REENTRANCY PASS",),
        stable_markers=("REQUEST BUS REENTRANCY PASS",),
        failure_markers=("REQUEST BUS REENTRANCY FAIL",),
    )
    image = build_image(PROFILE_NAME, tmp_path / "request-bus-reentrancy.img")
    assert smoke(
        PROFILE_NAME,
        image,
        cols=100,
        rows=30,
        max_steps=800_000_000,
        timeout=35.0,
    )


if __name__ == "__main__":
    import tempfile

    with tempfile.TemporaryDirectory() as directory:
        test_request_bus_reentrancy(Path(directory))
