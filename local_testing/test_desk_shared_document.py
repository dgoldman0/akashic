#!/usr/bin/env python3
"""Supported Desk-boundary contract for the shared Daybook document.

The probe is an ordinary queued ``APP-DESC``. It receives only the endpoint
which Desk gives every launched child and discovers the activation-local
Context, resource registry, request bus, and Daybook resource offer through
that endpoint. The offer identifies both the semantic RID and its owning pool;
the probe retains the owner through a neutral resource session and reads the
initial MP64FS document through the existing compact ``resource.snapshot``
capability.
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
REQUIRE interop/resource-session.f

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
32 CONSTANT _DSC-S-SESSION
32 RSES-SIZE + CONSTANT _DSC-STATE-SIZE

CREATE _dsc-expected-rid RID-SIZE ALLOT
CREATE _dsc-rid RID-SIZE ALLOT

VARIABLE _dsc-state
VARIABLE _dsc-instance
VARIABLE _dsc-context
VARIABLE _dsc-creg
VARIABLE _dsc-rreg
VARIABLE _dsc-bus
VARIABLE _dsc-pool
VARIABLE _dsc-offer
VARIABLE _dsc-owner
VARIABLE _dsc-cap
VARIABLE _dsc-depth
VARIABLE _dsc-final-pass
VARIABLE _dsc-run-count
VARIABLE _dsc-rollback-forced
VARIABLE _dsc-live-retry-forced

: _dsc-session  ( -- session ) _dsc-state @ _DSC-S-SESSION + ;

: _dsc-check  ( flag -- )
    1 _dsc-state @ _DSC-S-CHECKS + +!
    0= IF 1 _dsc-state @ _DSC-S-FAILS + +! THEN ;

: _dsc-expected-rid!  ( -- )
    SHA3-256-BEGIN
    _dsc-context @ CTX.PRACTICE @ PHEAD.ID RID-SIZE SHA3-256-ADD
    S" org.akashic.resource.daybook" SHA3-256-ADD
    _dsc-expected-rid SHA3-256-END ;

: _dsc-init  ( instance -- )
    1 _dsc-run-count +!
    DUP _dsc-instance ! CINST-STATE DUP _dsc-state !
    _DSC-STATE-SIZE 0 FILL
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
        DUP _dsc-offer ! 0<> DUP _dsc-check 0= IF EXIT THEN
    _dsc-offer @ ROFFER-VALID? _dsc-check
    _dsc-offer @ ROFFER-POOL@ DUP _dsc-pool !
        ROPOOL-VALID? _dsc-check
    _dsc-offer @ ROFFER-RID DUP RID-PRESENT? _dsc-check
        _dsc-rid RID-COPY
    _dsc-expected-rid!
    _dsc-rid _dsc-expected-rid RID= _dsc-check
    S" org.akashic.resource.daybook" _dsc-instance @ CINST-SERVICE
        _dsc-offer @ = _dsc-check

    \ Retention precedes owner resolution and descriptor borrowing.
    S" org.akashic.resource.daybook" _dsc-instance @ _dsc-session RSES-INIT
        DUP RSES-S-OK = _dsc-check
    ?DUP IF DROP EXIT THEN
    _dsc-session RSES-ACTIVE? _dsc-check
    _dsc-session RSES-HELD? _dsc-check
    _dsc-session RSES-VALID? _dsc-check
    _dsc-session RSES.POOL @ _dsc-pool @ = _dsc-check
    _dsc-session RSES.RID _dsc-rid RID= _dsc-check
    _dsc-pool @ ROPOOL-LEASES@ 2 >= _dsc-check

    _dsc-session RSES.OWNER @ _dsc-owner !
    _dsc-owner @ 0<> _dsc-check
    _dsc-owner @ _dsc-instance @ <> _dsc-check
    _dsc-owner @ CINST-DESC SDOC-COMP-DESC = _dsc-check
    _dsc-owner @ SDOC-VALID? _dsc-check

    _dsc-session RSES.BIND LBIND-VALID? _dsc-check
    _dsc-session RSES.BIND LBIND.RESOURCE-ID _dsc-rid RID= _dsc-check
    _dsc-session RSES.BIND LBIND.TARGET-ID @
        _dsc-owner @ CINST.ID @ = _dsc-check
    _dsc-session RSES.BIND LBIND.TARGET-GEN @
        _dsc-owner @ CINST.GENERATION @ = _dsc-check

    S" resource.snapshot" _dsc-owner @ CINST-DESC COMP-CAP-FIND
        DUP _dsc-cap ! 0<> DUP _dsc-check 0= IF EXIT THEN
    _dsc-cap @ CAP.EFFECTS @ CAP-E-OBSERVE = _dsc-check

    _dsc-cap @ CPRINC-COMPONENT _dsc-session RSES-PREPARE
        DUP RSES-S-OK = _dsc-check
    ?DUP IF DROP EXIT THEN
    _dsc-session RSES.REQUEST @ DUP 0<> _dsc-check
    DUP CBR.ARGS CV-NULL!
    _dsc-instance @ SWAP CBR-CALLER!
    _dsc-session RSES-DISPATCH DUP CBUS-S-OK = _dsc-check
    ?DUP IF DROP EXIT THEN

    _dsc-session RSES.REQUEST @ CBR.RESULT CV-TYPE@ CV-T-STRING = _dsc-check
    _dsc-session RSES.REQUEST @ CBR.RESULT DUP CV-DATA@ SWAP CV-LEN@
        S" # Daybook" STR-STR-CONTAINS _dsc-check
    _dsc-session RSES.REQUEST @ CBR.RESULT DUP CV-DATA@ SWAP CV-LEN@
        S" Project review" STR-STR-CONTAINS _dsc-check
    _dsc-session RSES.REQUEST @ CBR.RESULT DUP CV-DATA@ SWAP CV-LEN@
        S" Plan the next release" STR-STR-CONTAINS _dsc-check
    _dsc-session RSES.REQUEST @ CBR.ACTUAL-REV @
        _dsc-owner @ CINST.REVISION @ = _dsc-check
    _dsc-owner @ CINST.REVISION @ 1 = _dsc-check
    _dsc-session RSES-ADVANCE RSES-S-OK = _dsc-check
    _dsc-session RSES.BIND LBIND.REVISION @ 1 = _dsc-check
    _dsc-owner @ _dsc-instance @ <> _dsc-check

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
    S" endpoint -> RID -> retained resource session snapshot"
        3 2 DRW-TEXT
    DRW-STYLE-RESTORE
    DROP ;

: _dsc-shutdown  ( instance -- )
    CINST-STATE DUP _dsc-state ! _DSC-S-SESSION +
    RSES-FINI RSES-S-OK = DUP _dsc-check
    0= IF 0 _dsc-final-pass ! THEN

    \ Model the exact unpublished-owner state left by an activation whose
    \ rollback hit a retryable anchor-release failure.  Desk has no owner
    \ instance to deactivate, while the retained pool still borrows this
    \ activation's Context and registries.  Two forced failures make Desk's
    \ cleanup boundary itself observe and retry the second one.
    _dsc-run-count @ 1 = IF
        0 _SDOC-LIVE !
        0 _DESK-DAYBOOK-OWNER !
        _SDOC-OFFER ROFFER-SIZE 0 FILL
        2 _dsc-pool @ ROPOOL-RELEASE-FAILURES!
            RACQ-S-OK = _dsc-check
        _SDOC-ACTIVATE-RELEASE
        _SDOC-POOL ROPOOL-VALID? _dsc-check
        _SDOC-POOL ROPOOL-CONTEXT@ _dsc-context @ = _dsc-check
        _SDOC-POOL ROPOOL-RREG@ _dsc-rreg @ = _dsc-check
        _SDOC-POOL ROPOOL-CREG@ _dsc-creg @ = _dsc-check
        _SDOC-ANCHOR-RESULT RACQ.RESULT-TOKEN
            RACQ-TOKEN-ACTIVE? _dsc-check
        -1 _dsc-rollback-forced !
    ELSE
        \ The ordinary live-owner path must also consume a retryable final
        \ anchor-release failure before Desk frees the borrowed graph.
        1 _dsc-pool @ ROPOOL-RELEASE-FAILURES!
            RACQ-S-OK = _dsc-check
        -1 _dsc-live-retry-forced !
    THEN
    _dsc-state @ _DSC-S-FAILS + @ IF 0 _dsc-final-pass ! THEN ;

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

0 _dsc-final-pass ! 0 _dsc-run-count ! 0 _dsc-rollback-forced !
0 _dsc-live-retry-forced !
_dsc-desc DESK-QUEUE-LAUNCH
DESK-RUN
_dsc-final-pass @ 0= ABORT" first Desk resource pass failed"
_dsc-rollback-forced @ 0= ABORT" activation rollback was not forced"
_SDOC-POOL ROPOOL-VALID? ABORT" Desk freed dependencies before rollback"

\ A second complete Desk activation proves that the static Daybook owner did
\ not retain dangling dependencies from the first activation.
0 _dsc-final-pass !
_dsc-desc DESK-QUEUE-LAUNCH
DESK-RUN
_dsc-run-count @ 2 <> ABORT" second Desk activation did not launch probe"
_dsc-live-retry-forced @ 0= ABORT" live owner release retry was not forced"
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
            "interop/resource-session.f",
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
