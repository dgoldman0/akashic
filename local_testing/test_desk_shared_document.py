#!/usr/bin/env python3
"""Supported Desk-boundary contract for the shared Daybook document.

The probe is an ordinary queued ``APP-DESC``.  It receives only the endpoint
which Desk gives every launched child and discovers the activation-local
Context, resource registry, request bus, and semantic Daybook RID through
that endpoint.  It then attaches its own lens binding and reads the initial
MP64FS document through the generic ``resource.snapshot`` capability.
"""

from __future__ import annotations

from pathlib import Path
import sys


LOCAL_TESTING = Path(__file__).resolve().parent
sys.path.insert(0, str(LOCAL_TESTING))

from akashic_tui import Profile, PROFILES, build_image, smoke  # noqa: E402


PROFILE_NAME = "desk-shared-document-contract"

AUTOEXEC = r'''\ autoexec.f - Desk shared Daybook boundary contract
ENTER-USERLAND
." [akashic] loading Desk shared document contract" CR
REQUIRE tui/applets/desk/desk.f
REQUIRE interop/lens-binding.f

\ Provision the same healthy, durable Practice head used by the desktop.
\ Existing media is never rewritten by this development-image step.
CREATE _dsc-practice-head PHEAD-SIZE ALLOT
CREATE _dsc-practice-out PHEAD-SIZE ALLOT
CREATE _dsc-practice-store PHEADVFS-SIZE ALLOT

: _dsc-practice-id!  ( value id -- ) DUP RID-CLEAR ! ;

: _dsc-practice-slot?  ( path-a path-u -- flag )
    VFS-OPEN DUP IF VFS-CLOSE -1 ELSE DROP 0 THEN ;

: _dsc-practice-present?  ( -- flag )
    S" /practice-head-a.bin" _dsc-practice-slot?
    S" /practice-head-b.bin" _dsc-practice-slot? OR ;

: _dsc-practice-provision  ( -- )
    _dsc-practice-present? IF EXIT THEN
    VFS-CUR _dsc-practice-store PHEADVFS-INIT
        PHEADVFS-S-OK <> ABORT" Practice store init failed"
    _dsc-practice-out _dsc-practice-store PHEADVFS-LOAD
        PHEADVFS-S-RECOVERY <> ABORT" blank Practice did not enter recovery"
    _dsc-practice-head PHEAD-INIT
    1 _dsc-practice-head PHEAD.ID _dsc-practice-id!
    2 _dsc-practice-head PHEAD.CURRENT-ROOT _dsc-practice-id!
    _dsc-practice-head _dsc-practice-store PHEADVFS-REINITIALIZE
        PHEADVFS-S-OK <> ABORT" Practice provision failed" ;

_dsc-practice-provision

\ The probe owns only its result counters.  Every resource object below is
\ discovered or constructed through public runtime contracts.
 0 CONSTANT _DSC-S-PASS
 8 CONSTANT _DSC-S-CHECKS
16 CONSTANT _DSC-S-FAILS
24 CONSTANT _DSC-S-QUIT
32 CONSTANT _DSC-STATE-SIZE

CREATE _dsc-ref RREF-SIZE ALLOT
CREATE _dsc-binding LBIND-SIZE ALLOT
CREATE _dsc-expected-rid RID-SIZE ALLOT

VARIABLE _dsc-state
VARIABLE _dsc-instance
VARIABLE _dsc-context
VARIABLE _dsc-creg
VARIABLE _dsc-rreg
VARIABLE _dsc-bus
VARIABLE _dsc-rid
VARIABLE _dsc-owner
VARIABLE _dsc-cap
VARIABLE _dsc-request
VARIABLE _dsc-depth
VARIABLE _dsc-final-pass

: _dsc-check  ( flag -- )
    1 _dsc-state @ _DSC-S-CHECKS + +!
    0= IF 1 _dsc-state @ _DSC-S-FAILS + +! THEN ;

: _dsc-request-free  ( -- )
    _dsc-request DUP @ SWAP 0 SWAP ! ?DUP IF CBR-FREE THEN ;

: _dsc-expected-rid!  ( -- )
    SHA3-256-BEGIN
    _dsc-context @ CTX.PRACTICE @ PHEAD.ID RID-SIZE SHA3-256-ADD
    S" org.akashic.resource.daybook" SHA3-256-ADD
    _dsc-expected-rid SHA3-256-END ;

: _dsc-init  ( instance -- )
    DUP _dsc-instance ! CINST-STATE DUP _dsc-state !
    _DSC-STATE-SIZE 0 FILL
    0 _dsc-request !
    DEPTH _dsc-depth !

    \ A normal child receives a live endpoint before its INIT callback.
    _dsc-instance @ CINST.ENDPOINT @ 0<> DUP _dsc-check
    0= IF EXIT THEN

    S" org.akashic.runtime.context" _dsc-instance @ CINST-SERVICE
        DUP _dsc-context ! 0<> DUP _dsc-check 0= IF EXIT THEN
    _dsc-context @ CTX-VALID? _dsc-check
    _dsc-context @ CTX.FLAGS @ CTX-F-ACTIVE AND 0<> _dsc-check
    _dsc-context @ CTX.PRACTICE @ PHEAD-VALID? _dsc-check

    S" org.akashic.runtime.registry" _dsc-instance @ CINST-SERVICE
        DUP _dsc-creg ! 0<> DUP _dsc-check 0= IF EXIT THEN
    S" org.akashic.runtime.resource-registry"
        _dsc-instance @ CINST-SERVICE
        DUP _dsc-rreg ! 0<> DUP _dsc-check 0= IF EXIT THEN
    _dsc-rreg @ RREG-VALID? _dsc-check
    _dsc-context @ _dsc-rreg @ RREG-CONTEXT? _dsc-check
    _dsc-rreg @ RREG.COMPONENTS @ _dsc-creg @ = _dsc-check

    S" org.akashic.interop.request-bus" _dsc-instance @ CINST-SERVICE
        DUP _dsc-bus ! 0<> DUP _dsc-check 0= IF EXIT THEN
    _dsc-bus @ CBUS.REGISTRY @ _dsc-creg @ = _dsc-check

    S" org.akashic.resource.daybook" _dsc-instance @ CINST-SERVICE
        DUP _dsc-rid ! 0<> DUP _dsc-check 0= IF EXIT THEN
    _dsc-rid @ RID-PRESENT? _dsc-check
    _dsc-expected-rid!
    _dsc-rid @ _dsc-expected-rid RID= _dsc-check
    S" org.akashic.resource.daybook" _dsc-instance @ CINST-SERVICE
        _dsc-rid @ = _dsc-check

    \ Resolve the semantic RID without receiving the owner's private state.
    _dsc-rid @ _dsc-context @ _dsc-ref _dsc-rreg @ RREG-REF
        DUP RREG-S-OK = _dsc-check
    ?DUP IF DROP EXIT THEN
    _dsc-ref _dsc-context @ _dsc-rreg @ RREG-RESOLVE
        DUP RREG-S-OK = _dsc-check
    DUP IF 2DROP EXIT THEN
    DROP _dsc-owner !
    _dsc-owner @ 0<> _dsc-check
    _dsc-owner @ _dsc-instance @ <> _dsc-check
    _dsc-owner @ CINST-DESC SDOC-COMP-DESC = _dsc-check
    _dsc-owner @ SDOC-VALID? _dsc-check

    \ The probe creates an independent pointer-free lens binding.
    _dsc-ref _dsc-context @ _dsc-rreg @ _dsc-binding LBIND-ATTACH
        DUP LBIND-S-OK = _dsc-check
    ?DUP IF DROP EXIT THEN
    _dsc-binding LBIND-VALID? _dsc-check
    _dsc-binding LBIND.RESOURCE-ID _dsc-rid @ RID= _dsc-check
    _dsc-binding LBIND.TARGET-ID @ _dsc-owner @ CINST.ID @ = _dsc-check
    _dsc-binding LBIND.TARGET-GEN @
        _dsc-owner @ CINST.GENERATION @ = _dsc-check

    S" resource.snapshot" _dsc-owner @ CINST-DESC COMP-CAP-FIND
        DUP _dsc-cap ! 0<> DUP _dsc-check 0= IF EXIT THEN
    _dsc-cap @ CAP.EFFECTS @ CAP-E-OBSERVE = _dsc-check

    CBR-NEW DUP 0= _dsc-check
    DUP IF 2DROP EXIT THEN
    DROP DUP _dsc-request ! 0<> _dsc-check
    _dsc-binding _dsc-context @ _dsc-request @ LBIND-REQUEST!
        DUP LBIND-S-OK = _dsc-check
    ?DUP IF DROP _dsc-request-free EXIT THEN
    CPRINC-COMPONENT _dsc-request @ CBR.PRINCIPAL !
    _dsc-instance @ _dsc-request @ CBR-CALLER!
    _dsc-cap @ _dsc-request @ CBR.CAP !
    _dsc-request @ _dsc-bus @ CBUS-DISPATCH
        DUP CBUS-S-OK = _dsc-check
    ?DUP IF DROP _dsc-request-free EXIT THEN

    _dsc-request @ CBR.RESULT CV-TYPE@ CV-T-STRING = _dsc-check
    _dsc-request @ CBR.RESULT DUP CV-DATA@ SWAP CV-LEN@
        S" # Daybook" STR-STR-CONTAINS _dsc-check
    _dsc-request @ CBR.RESULT DUP CV-DATA@ SWAP CV-LEN@
        S" Project review" STR-STR-CONTAINS _dsc-check
    _dsc-request @ CBR.RESULT DUP CV-DATA@ SWAP CV-LEN@
        S" Plan the next release" STR-STR-CONTAINS _dsc-check
    _dsc-request @ CBR.ACTUAL-REV @
        _dsc-owner @ CINST.REVISION @ = _dsc-check
    _dsc-owner @ CINST.REVISION @ 1 = _dsc-check
    _dsc-request @ _dsc-context @ _dsc-binding LBIND-ADVANCE
        LBIND-S-OK = _dsc-check
    _dsc-binding LBIND.REVISION @ 1 = _dsc-check
    _dsc-owner @ _dsc-instance @ <> _dsc-check
    _dsc-request-free

    DEPTH _dsc-depth @ = _dsc-check
    _dsc-state @ _DSC-S-FAILS + @ 0= IF
        -1 _dsc-state @ _DSC-S-PASS + !
        -1 _dsc-final-pass !
    THEN ;

: _dsc-tick  ( instance -- )
    CINST-STATE DUP _DSC-S-PASS + @
    OVER _DSC-S-QUIT + @ 0= AND IF
        -1 OVER _DSC-S-QUIT + !
        ASHELL-QUIT
    THEN DROP ;

: _dsc-paint  ( instance -- )
    CINST-STATE
    DRW-STYLE-SAVE
    231 17 1 DRW-STYLE!
    DUP _DSC-S-PASS + @ IF
        S" DESK SHARED DOCUMENT PASS"
    ELSE
        S" DESK SHARED DOCUMENT FAIL"
    THEN
    1 2 DRW-TEXT
    250 17 0 DRW-STYLE!
    S" endpoint -> RID -> owner -> independent lens snapshot"
        3 2 DRW-TEXT
    DRW-STYLE-RESTORE
    DROP ;

: _dsc-shutdown  ( instance -- ) DROP _dsc-request-free ;

CREATE _dsc-comp COMP-DESC ALLOT
CREATE _dsc-desc APP-DESC ALLOT

\ Descriptor strings are compiled into dictionary storage.  Storing an
\ interpreted S" pointer here would retain KDOS's reused input buffer.
: _dsc-descriptors  ( -- )
    _dsc-comp COMP-DESC-INIT
    S" org.akashic.test.desk-shared-document"
        _dsc-comp COMP.ID-U ! _dsc-comp COMP.ID-A !
    S" 1.0.0" _dsc-comp COMP.VERSION-U ! _dsc-comp COMP.VERSION-A !
    _DSC-STATE-SIZE _dsc-comp COMP.STATE-SIZE !

    _dsc-desc APP-DESC-INIT
    _dsc-comp _dsc-desc APP.COMP-DESC !
    APP-F-TICK-WHEN-CLEAN _dsc-desc APP.FLAGS !
    ['] _dsc-init _dsc-desc APP.INIT-XT !
    ['] _dsc-paint _dsc-desc APP.PAINT-XT !
    ['] _dsc-tick _dsc-desc APP.TICK-XT !
    ['] _dsc-shutdown _dsc-desc APP.SHUTDOWN-XT !
    S" Resource Probe" _dsc-desc APP.TITLE-U ! _dsc-desc APP.TITLE-A ! ;

_dsc-descriptors

0 _dsc-final-pass !
_dsc-desc DESK-QUEUE-LAUNCH
DESK-RUN
_dsc-final-pass @ IF
    ." DESK SHARED DOCUMENT SHUTDOWN PASS" CR
ELSE
    ." DESK SHARED DOCUMENT SHUTDOWN FAIL" CR
THEN
'''


def test_desk_shared_document_contract(tmp_path: Path) -> None:
    PROFILES[PROFILE_NAME] = Profile(
        roots=(
            "tui/applets/desk/desk.f",
            "interop/lens-binding.f",
        ),
        resources=(),
        autoexec=AUTOEXEC,
        ready_markers=("DESK SHARED DOCUMENT SHUTDOWN PASS",),
        stable_markers=("DESK SHARED DOCUMENT SHUTDOWN PASS",),
        linked=True,
        failure_markers=(
            "DESK SHARED DOCUMENT FAIL",
            "DESK SHARED DOCUMENT SHUTDOWN FAIL",
        ),
    )
    image = build_image(PROFILE_NAME, tmp_path / "desk-shared-document.img")
    assert smoke(
        PROFILE_NAME,
        image,
        cols=100,
        rows=30,
        max_steps=4_000_000_000,
        timeout=180.0,
    )


if __name__ == "__main__":
    import tempfile

    with tempfile.TemporaryDirectory() as directory:
        test_desk_shared_document_contract(Path(directory))
