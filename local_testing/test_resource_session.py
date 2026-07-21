#!/usr/bin/env python3
"""Focused contracts for the retained, protocol-neutral resource session."""

from __future__ import annotations

from pathlib import Path
import sys


LOCAL_TESTING = Path(__file__).resolve().parent
sys.path.insert(0, str(LOCAL_TESTING))

from akashic_tui import Profile, PROFILES, build_image, smoke  # noqa: E402


PROFILE_NAME = "resource-session-contracts"

AUTOEXEC = r'''\ autoexec.f - resource session contracts
ENTER-USERLAND
." [akashic] loading resource session contracts" CR
REQUIRE interop/resource-session.f

VARIABLE _rs-fails
VARIABLE _rs-checks
VARIABLE _rs-depth

: _rs-assert  ( flag -- )
    1 _rs-checks +!
    0= IF 1 _rs-fails +! ." ASSERT " _rs-checks @ . CR THEN ;

: _rs-stack  ( -- )
    DEPTH DUP _rs-depth @ <> IF
        ." RESOURCE SESSION STACK " _rs-depth @ . ." -> " DUP . CR .S CR
    THEN
    _rs-depth @ = _rs-assert ;

: _rs-id!  ( value id -- ) DUP RID-CLEAR ! ;

\ ---------------------------------------------------------------------
\ A deliberately compact resource protocol and an exact RCON descriptor
\ ---------------------------------------------------------------------

CREATE _rs-null-schema CS-SIZE ALLOT
CREATE _rs-text-schema CS-SIZE ALLOT
CREATE _rs-bool-schema CS-SIZE ALLOT
CREATE _rs-compact-caps 2 CAP-DESC * ALLOT
CREATE _rs-compact-desc COMP-DESC ALLOT

: _rs-compact-snapshot  ( -- cap ) _rs-compact-caps ;
: _rs-compact-replace   ( -- cap ) _rs-compact-caps CAP-DESC + ;

  0 CONSTANT _RSO-TEXT-U
  8 CONSTANT _RSO-REPLACE-N
 16 CONSTANT _RSO-TEXT
144 CONSTANT _RSO-SIZE
CREATE _rs-owner-data _RSO-SIZE ALLOT

VARIABLE _rs-handler-request
VARIABLE _rs-handler-instance
VARIABLE _rs-handler-member

: _rs-handler-end  ( status -- status )
    >R _rs-handler-member @ ROPOOL-HANDLER-END DROP R> ;

: _rs-snapshot-handler  ( request instance -- status )
    _rs-handler-instance ! _rs-handler-request !
    _rs-handler-request @ _rs-handler-instance @ ROPOOL-HANDLER-BEGIN
    0= IF DROP CBUS-S-INVALID EXIT THEN _rs-handler-member !
    _rs-owner-data _RSO-TEXT +
    _rs-owner-data _RSO-TEXT-U + @
    _rs-handler-request @ CBR.RESULT CV-STRING! IF
        CBUS-S-FAILED
    ELSE
        CBUS-S-OK
    THEN _rs-handler-end ;

: _rs-replace-handler  ( request instance -- status )
    _rs-handler-instance ! _rs-handler-request !
    _rs-handler-request @ _rs-handler-instance @ ROPOOL-HANDLER-BEGIN
    0= IF DROP CBUS-S-INVALID EXIT THEN _rs-handler-member !
    _rs-handler-request @ CBR.ARGS DUP CV-LEN@ DUP 0< OVER 128 > OR IF
        2DROP CBUS-S-INVALID _rs-handler-end EXIT
    THEN
    DUP _rs-owner-data _RSO-TEXT-U + !
    SWAP CV-DATA@ _rs-owner-data _RSO-TEXT + ROT CMOVE
    1 _rs-owner-data _RSO-REPLACE-N + +!
    -1 _rs-handler-request @ CBR.RESULT CV-BOOL!
    CBUS-S-OK _rs-handler-end ;

: _rs-canonical-unused  ( request instance -- status )
    2DROP CBUS-S-FAILED ;

CREATE _rs-canonical-caps 3 CAP-DESC * ALLOT
CREATE _rs-canonical-desc COMP-DESC ALLOT
CREATE _rs-canonical-configs 3 RCON-CAP-CONFIG-SIZE * ALLOT
CREATE _rs-canonical-workspaces 3 RCON-CAP-WORKSPACE-SIZE * ALLOT

: _rs-can-cap  ( index -- cap ) CAP-DESC * _rs-canonical-caps + ;
: _rs-can-config  ( index -- config )
    RCON-CAP-CONFIG-SIZE * _rs-canonical-configs + ;
: _rs-can-workspace  ( index -- workspace )
    RCON-CAP-WORKSPACE-SIZE * _rs-canonical-workspaces + ;

: _rs-build-fail  ( status -- ) ?DUP IF THROW THEN ;

: _rs-config-meta  ( config -- )
    >R
    S" Test resource" R@ RCONCC.TITLE-U ! R@ RCONCC.TITLE-A !
    S" Focused resource-session contract"
        R@ RCONCC.DESC-U ! R@ RCONCC.DESC-A !
    R> DROP ;

: _rs-descriptors  ( -- )
    _rs-null-schema CSC-NULL!
    128 _rs-text-schema CSC-UTF8!
    _rs-bool-schema CSC-BOOL!

    _rs-compact-snapshot CAP-DESC-INIT
    CAP-K-RESOURCE _rs-compact-snapshot CAP.KIND !
    S" resource.snapshot" _rs-compact-snapshot CAP.ID-U !
        _rs-compact-snapshot CAP.ID-A !
    _rs-null-schema _rs-compact-snapshot CAP.IN-SCHEMA !
    _rs-text-schema _rs-compact-snapshot CAP.OUT-SCHEMA !
    CAP-E-OBSERVE _rs-compact-snapshot CAP.EFFECTS !
    CAP-F-IDEMPOTENT CAP-F-NEEDS-TARGET OR
        _rs-compact-snapshot CAP.FLAGS !
    ['] _rs-snapshot-handler _rs-compact-snapshot CAP.HANDLER-XT !

    _rs-compact-replace CAP-DESC-INIT
    CAP-K-COMMAND _rs-compact-replace CAP.KIND !
    S" resource.replace" _rs-compact-replace CAP.ID-U !
        _rs-compact-replace CAP.ID-A !
    _rs-text-schema _rs-compact-replace CAP.IN-SCHEMA !
    _rs-bool-schema _rs-compact-replace CAP.OUT-SCHEMA !
    CAP-E-MUTATE CAP-E-PERSIST OR _rs-compact-replace CAP.EFFECTS !
    CAP-F-NEEDS-TARGET _rs-compact-replace CAP.FLAGS !
    ['] _rs-replace-handler _rs-compact-replace CAP.HANDLER-XT !

    _rs-compact-desc COMP-DESC-INIT
    S" org.akashic.test.compact-resource"
        _rs-compact-desc COMP.ID-U ! _rs-compact-desc COMP.ID-A !
    S" 1.0.0" _rs-compact-desc COMP.VERSION-U !
        _rs-compact-desc COMP.VERSION-A !
    ROPOOL-MEMBER-SIZE _rs-compact-desc COMP.STATE-SIZE !
    _rs-compact-caps _rs-compact-desc COMP.CAPS-A !
    2 _rs-compact-desc COMP.CAPS-N !

    3 0 DO
        I _rs-can-workspace RCON-CAP-WORKSPACE-INIT _rs-build-fail
    LOOP
    ['] _rs-canonical-unused
        CAP-F-IDEMPOTENT CAP-F-NEEDS-TARGET OR CAP-F-CONTEXT-DEFAULT OR
        0 _rs-can-config RCON-CAP-CONFIG-INIT _rs-build-fail
    0 _rs-can-config _rs-config-meta
    ['] _rs-canonical-unused
        CAP-F-IDEMPOTENT CAP-F-NEEDS-TARGET OR CAP-F-CONTEXT-DEFAULT OR
        1 _rs-can-config RCON-CAP-CONFIG-INIT _rs-build-fail
    1 _rs-can-config _rs-config-meta
    ['] _rs-canonical-unused CAP-F-NEEDS-TARGET
        2 _rs-can-config RCON-CAP-CONFIG-INIT _rs-build-fail
    2 _rs-can-config _rs-config-meta
    0 _rs-can-config 0 _rs-can-cap 0 _rs-can-workspace
        RCON-DESCRIBE-CAP! _rs-build-fail
    1 _rs-can-config 1 _rs-can-cap 1 _rs-can-workspace
        RCON-SNAPSHOT-CAP! _rs-build-fail
    2 _rs-can-config 2 _rs-can-cap 2 _rs-can-workspace
        RCON-REPLACE-CAP! _rs-build-fail

    _rs-canonical-desc COMP-DESC-INIT
    S" org.akashic.test.canonical-resource"
        _rs-canonical-desc COMP.ID-U ! _rs-canonical-desc COMP.ID-A !
    S" 1.0.0" _rs-canonical-desc COMP.VERSION-U !
        _rs-canonical-desc COMP.VERSION-A !
    ROPOOL-MEMBER-SIZE _rs-canonical-desc COMP.STATE-SIZE !
    _rs-canonical-caps _rs-canonical-desc COMP.CAPS-A !
    3 _rs-canonical-desc COMP.CAPS-N ! ;

_rs-descriptors

\ ---------------------------------------------------------------------
\ Pool policy callbacks and runtime wiring
\ ---------------------------------------------------------------------

CREATE _rs-head PHEAD-SIZE ALLOT
CREATE _rs-rid-a RID-SIZE ALLOT
CREATE _rs-rid-b RID-SIZE ALLOT
CREATE _rs-policy CPOLICY-SIZE ALLOT
CREATE _rs-pool-config-a ROPOOL-CONFIG-SIZE ALLOT
CREATE _rs-pool-config-b ROPOOL-CONFIG-SIZE ALLOT
CREATE _rs-pool-a ROPOOL-SIZE ALLOT
CREATE _rs-pool-b ROPOOL-SIZE ALLOT
CREATE _rs-slots-a ROPOOL-SLOT-SIZE ALLOT
CREATE _rs-slots-b ROPOOL-SLOT-SIZE ALLOT
CREATE _rs-leases-a 4 ROPOOL-LEASE-SIZE * ALLOT
CREATE _rs-leases-b 4 ROPOOL-LEASE-SIZE * ALLOT
CREATE _rs-offer-a ROFFER-SIZE ALLOT
CREATE _rs-offer-b ROFFER-SIZE ALLOT

VARIABLE _rs-context
VARIABLE _rs-creg
VARIABLE _rs-rreg
VARIABLE _rs-bus
VARIABLE _rs-named-a-calls
VARIABLE _rs-context-calls
VARIABLE _rs-rreg-calls
VARIABLE _rs-bus-calls
VARIABLE _rs-named-seen
VARIABLE _rs-mutate-after-named
VARIABLE _rs-after-named-runtime

: _rs-query-counts-clear  ( -- )
    0 _rs-named-a-calls !
    0 _rs-context-calls !
    0 _rs-rreg-calls !
    0 _rs-bus-calls !
    0 _rs-named-seen !
    0 _rs-mutate-after-named !
    0 _rs-after-named-runtime ! ;

: _rs-runtime-observe  ( -- )
    _rs-mutate-after-named @ _rs-named-seen @ 0<> AND IF
        _rs-offer-b _rs-offer-a ROFFER-SIZE CMOVE
        1 _rs-after-named-runtime +!
        0 _rs-mutate-after-named !
    THEN ;

: _rs-admit  ( locator owner-data -- tag status )
    DROP
    DUP QLOC-VALID? 0= IF DROP 0 RACQ-S-UNQUALIFIED EXIT THEN
    DUP QLOC-OWNER$ S" org.akashic.test.owner" STR-STR= 0= IF
        DROP 0 RACQ-S-OWNER-MISMATCH EXIT
    THEN
    QLOC.REF RREF.ID @ DUP 71 = OVER 72 = OR IF
        RACQ-S-OK
    ELSE
        DROP 0 RACQ-S-NOT-FOUND
    THEN ;

: _rs-descriptor  ( tag owner-data -- descriptor | 0 )
    DROP
    DUP 71 = IF DROP _rs-compact-desc EXIT THEN
    72 = IF _rs-canonical-desc ELSE 0 THEN ;

: _rs-state-init  ( locator tag instance owner-data -- status )
    2DROP 2DROP RACQ-S-OK ;

: _rs-runtime-service  ( id-a id-u -- service | 0 )
    _rs-runtime-observe
    2DUP S" org.akashic.runtime.context" STR-STR= IF
        1 _rs-context-calls +!
        2DROP _rs-context @ EXIT
    THEN
    2DUP S" org.akashic.runtime.resource-registry" STR-STR= IF
        1 _rs-rreg-calls +!
        2DROP _rs-rreg @ EXIT
    THEN
    2DUP S" org.akashic.interop.request-bus" STR-STR= IF
        1 _rs-bus-calls +!
        2DROP _rs-bus @ EXIT
    THEN
    2DROP 0 ;

: _rs-service-a  ( id-a id-u offer -- service | 0 )
    >R
    2DUP S" org.akashic.resource.test-a" STR-STR= IF
        1 _rs-named-a-calls +!
        -1 _rs-named-seen !
        2DROP R> EXIT
    THEN
    R> DROP _rs-runtime-service ;

: _rs-service-b  ( id-a id-u offer -- service | 0 )
    >R
    2DUP S" org.akashic.resource.test-b" STR-STR= IF
        2DROP R> EXIT
    THEN
    R> DROP _rs-runtime-service ;

: _rs-blocked-service  ( id-a id-u context -- service | 0 )
    DROP
    S" org.akashic.runtime.context" STR-STR= IF
        _rs-context @
    ELSE
        0
    THEN ;

CREATE _rs-endpoint-a IENDPOINT-SIZE ALLOT
CREATE _rs-endpoint-b IENDPOINT-SIZE ALLOT
CREATE _rs-blocked-endpoint IENDPOINT-SIZE ALLOT
CREATE _rs-client-desc COMP-DESC ALLOT

: _rs-client-descriptor  ( -- )
    _rs-client-desc COMP-DESC-INIT
    S" org.akashic.test.resource-session-client"
        _rs-client-desc COMP.ID-U ! _rs-client-desc COMP.ID-A !
    S" 1.0.0" _rs-client-desc COMP.VERSION-U !
        _rs-client-desc COMP.VERSION-A ! ;

: _rs-new-client  ( endpoint | 0 -- instance )
    >R _rs-client-desc CINST-NEW
    DUP 0= _rs-assert DROP
    DUP R> SWAP CINST.ENDPOINT ! ;

CREATE _rs-seed-ref-a RREF-SIZE ALLOT
CREATE _rs-seed-ref-b RREF-SIZE ALLOT
CREATE _rs-seed-locator-a QLOC-SIZE ALLOT
CREATE _rs-seed-locator-b QLOC-SIZE ALLOT
CREATE _rs-seed-bind-a LBIND-SIZE ALLOT
CREATE _rs-seed-bind-b LBIND-SIZE ALLOT
CREATE _rs-seed-result-a RACQ-RESULT-SIZE ALLOT
CREATE _rs-seed-result-b RACQ-RESULT-SIZE ALLOT

: _rs-seed-a  ( -- status )
    _rs-seed-ref-a RREF-INIT
    _rs-rid-a _rs-seed-ref-a RREF.ID RID-COPY
    S" org.akashic.test.owner" _rs-seed-ref-a _rs-seed-locator-a
        QLOC-IDENTITY! QLOC-S-OK <> IF RACQ-S-INVALID EXIT THEN
    _rs-seed-locator-a _rs-pool-a _rs-context @ _rs-rreg @
        _rs-seed-bind-a _rs-seed-result-a ROPOOL-ATTACH ;

: _rs-seed-b  ( -- status )
    _rs-seed-ref-b RREF-INIT
    _rs-rid-b _rs-seed-ref-b RREF.ID RID-COPY
    S" org.akashic.test.owner" _rs-seed-ref-b _rs-seed-locator-b
        QLOC-IDENTITY! QLOC-S-OK <> IF RACQ-S-INVALID EXIT THEN
    _rs-seed-locator-b _rs-pool-b _rs-context @ _rs-rreg @
        _rs-seed-bind-b _rs-seed-result-b ROPOOL-ATTACH ;

\ ---------------------------------------------------------------------
\ Session journeys
\ ---------------------------------------------------------------------

CREATE _rs-direct-session RSES-SIZE ALLOT
CREATE _rs-blocked-session RSES-SIZE ALLOT
CREATE _rs-session-a RSES-SIZE ALLOT
CREATE _rs-session-b RSES-SIZE ALLOT
CREATE _rs-canonical-session RSES-SIZE ALLOT
CREATE _rs-alias-session RSES-SIZE ALLOT
CREATE _rs-alias-before RSES-SIZE ALLOT
CREATE _rs-held-before RSES-SIZE ALLOT
CREATE _rs-instance-before COMP-INST ALLOT
CREATE _rs-exact-ref RREF-SIZE ALLOT
CREATE _rs-bad-ref RREF-SIZE ALLOT

VARIABLE _rs-direct-client
VARIABLE _rs-blocked-client
VARIABLE _rs-client-a
VARIABLE _rs-client-b
VARIABLE _rs-canonical-client
VARIABLE _rs-alias-client
VARIABLE _rs-saved-runtime
VARIABLE _rs-old-revision
VARIABLE _rs-request-before-fini

: _rs-result=  ( expected-a expected-u session -- flag )
    >R R@ RSES.REQUEST @ CBR.RESULT DUP CV-DATA@ SWAP CV-LEN@
    STR-STR= R> DROP ;

: _rs-advance-fail  ( request context binding -- status )
    2DROP DROP LBIND-S-INVALID ;

: _rs-alias-pattern  ( -- )
    _rs-alias-session RSES-SIZE 0xA5 FILL
    _rs-alias-session _rs-alias-before RSES-SIZE CMOVE ;

: _rs-alias-unchanged?  ( -- flag )
    _rs-alias-session RSES-SIZE _rs-alias-before RSES-SIZE STR-STR= ;

: _rs-alias-init-rejected  ( -- )
    S" org.akashic.resource.test-a" _rs-alias-client @
        _rs-alias-session RSES-INIT RSES-S-INVALID = _rs-assert
    _rs-alias-unchanged? _rs-assert ;

: _rs-runtime-init  ( -- )
    _rs-head PHEAD-INIT
    41 _rs-head PHEAD.ID _rs-id!
    42 _rs-head PHEAD.CURRENT-ROOT _rs-id!
    71 _rs-rid-a _rs-id!
    72 _rs-rid-b _rs-id!
    S" seed" DUP _rs-owner-data _RSO-TEXT-U + !
        _rs-owner-data _RSO-TEXT + SWAP CMOVE
    0 _rs-owner-data _RSO-REPLACE-N + !

    77 CTX-NEW DUP 0= _rs-assert DROP _rs-context !
    _rs-head _rs-context @ CTX.PRACTICE !
    CTX-F-ACTIVE _rs-context @ CTX.FLAGS !
    CREG-NEW DUP 0= _rs-assert DROP _rs-creg !
    _rs-creg @ _rs-context @ RREG-NEW
        DUP RREG-S-OK = _rs-assert DROP _rs-rreg !
    _rs-policy CPOLICY-INIT
    _rs-creg @ _rs-policy CBUS-NEW
        DUP 0= _rs-assert DROP _rs-bus !
    _rs-policy _rs-context @ CTX.POLICY !
    _rs-bus @ _rs-context @ CTX.QUEUE !

    _rs-pool-config-a ROPOOL-CONFIG-INIT
    S" org.akashic.test.owner" _rs-pool-config-a ROPC.OWNER-U !
        _rs-pool-config-a ROPC.OWNER-A !
    _rs-owner-data _rs-pool-config-a ROPC.OWNER-DATA !
    _rs-context @ _rs-pool-config-a ROPC.CONTEXT !
    _rs-creg @ _rs-pool-config-a ROPC.CREG !
    _rs-rreg @ _rs-pool-config-a ROPC.RREG !
    _rs-slots-a _rs-pool-config-a ROPC.SLOTS !
    1 _rs-pool-config-a ROPC.SLOT-CAP !
    _rs-leases-a _rs-pool-config-a ROPC.LEASES !
    4 _rs-pool-config-a ROPC.LEASE-CAP !
    ['] _rs-admit _rs-pool-config-a ROPC.ADMIT-XT !
    ['] _rs-descriptor _rs-pool-config-a ROPC.DESCRIPTOR-XT !
    ['] _rs-state-init _rs-pool-config-a ROPC.STATE-INIT-XT !
    _rs-pool-config-a _rs-pool-a ROPOOL-INIT RACQ-S-OK = _rs-assert

    _rs-pool-config-b ROPOOL-CONFIG-INIT
    S" org.akashic.test.owner" _rs-pool-config-b ROPC.OWNER-U !
        _rs-pool-config-b ROPC.OWNER-A !
    _rs-owner-data _rs-pool-config-b ROPC.OWNER-DATA !
    _rs-context @ _rs-pool-config-b ROPC.CONTEXT !
    _rs-creg @ _rs-pool-config-b ROPC.CREG !
    _rs-rreg @ _rs-pool-config-b ROPC.RREG !
    _rs-slots-b _rs-pool-config-b ROPC.SLOTS !
    1 _rs-pool-config-b ROPC.SLOT-CAP !
    _rs-leases-b _rs-pool-config-b ROPC.LEASES !
    4 _rs-pool-config-b ROPC.LEASE-CAP !
    ['] _rs-admit _rs-pool-config-b ROPC.ADMIT-XT !
    ['] _rs-descriptor _rs-pool-config-b ROPC.DESCRIPTOR-XT !
    ['] _rs-state-init _rs-pool-config-b ROPC.STATE-INIT-XT !
    _rs-pool-config-b _rs-pool-b ROPOOL-INIT RACQ-S-OK = _rs-assert

    _rs-rid-a _rs-pool-a _rs-offer-a ROFFER-INIT
        RACQ-S-OK = _rs-assert
    _rs-rid-b _rs-pool-b _rs-offer-b ROFFER-INIT
        RACQ-S-OK = _rs-assert

    _rs-endpoint-a IENDPOINT-INIT
    _rs-offer-a _rs-endpoint-a IEND.CONTEXT !
    ['] _rs-service-a _rs-endpoint-a IEND.SERVICE-XT !
    _rs-endpoint-b IENDPOINT-INIT
    _rs-offer-b _rs-endpoint-b IEND.CONTEXT !
    ['] _rs-service-b _rs-endpoint-b IEND.SERVICE-XT !
    _rs-blocked-endpoint IENDPOINT-INIT
    ['] _rs-blocked-service _rs-blocked-endpoint IEND.SERVICE-XT !
    _rs-client-descriptor

    _rs-compact-desc COMP-CAPS-VALID? _rs-assert
    _rs-canonical-desc COMP-CAPS-VALID? _rs-assert
    _rs-seed-a RACQ-S-OK = _rs-assert
    _rs-seed-b RACQ-S-OK = _rs-assert
    _rs-pool-a ROPOOL-LIVE@ 1 = _rs-assert
    _rs-pool-a ROPOOL-LEASES@ 1 = _rs-assert
    _rs-pool-b ROPOOL-LIVE@ 1 = _rs-assert
    _rs-pool-b ROPOOL-LEASES@ 1 = _rs-assert ;

: _rs-run  ( -- )
    0 _rs-fails ! 0 _rs-checks !
    _rs-runtime-init
    DEPTH _rs-depth !

    \ INIT rejects an absent or wrapping output before dereferencing it.
    \ Every alias rejection below is byte-for-byte nonmutating.
    _rs-endpoint-a _rs-new-client DUP _rs-alias-client ! DROP
    S" org.akashic.resource.test-a" _rs-alias-client @ 0 RSES-INIT
        RSES-S-INVALID = _rs-assert
    S" org.akashic.resource.test-a" _rs-alias-client @ -1 RSES-INIT
        RSES-S-INVALID = _rs-assert
    0 RSES-CLEAR
    -1 RSES-CLEAR

    \ Borrowed identifier bytes cannot occupy any part of the output.
    _rs-alias-pattern
    _rs-alias-session 16 + 8 _rs-alias-client @
        _rs-alias-session RSES-INIT RSES-S-INVALID = _rs-assert
    _rs-alias-unchanged? _rs-assert

    \ The output may live in CINST state, but never over its live header.
    _rs-alias-client @ _rs-instance-before COMP-INST CMOVE
    S" org.akashic.resource.test-a" _rs-alias-client @ DUP RSES-INIT
        RSES-S-INVALID = _rs-assert
    _rs-alias-client @ COMP-INST _rs-instance-before COMP-INST STR-STR=
        _rs-assert

    \ The endpoint and each service-returned runtime record are staged and
    \ checked before reset as well.  None may be used as session storage.
    _rs-alias-pattern
    _rs-alias-session _rs-alias-client @ CINST.ENDPOINT !
    S" org.akashic.resource.test-a" _rs-alias-client @
        _rs-alias-session RSES-INIT RSES-S-INVALID = _rs-assert
    _rs-alias-unchanged? _rs-assert
    _rs-endpoint-a _rs-alias-client @ CINST.ENDPOINT !

    \ A named service is discovered before reset.  Even a returned offer
    \ that aliases the output is rejected before ROFFER validation or copy.
    _rs-alias-pattern
    _rs-alias-session _rs-endpoint-a IEND.CONTEXT !
    S" org.akashic.resource.test-a" _rs-alias-client @
        _rs-alias-session RSES-INIT RSES-S-INVALID = _rs-assert
    _rs-alias-unchanged? _rs-assert
    _rs-offer-a _rs-endpoint-a IEND.CONTEXT !

    _rs-alias-pattern
    _rs-context @ _rs-saved-runtime !
    _rs-alias-session _rs-context !
    S" org.akashic.resource.test-a" _rs-alias-client @
        _rs-alias-session RSES-INIT RSES-S-INVALID = _rs-assert
    _rs-saved-runtime @ _rs-context !
    _rs-alias-unchanged? _rs-assert

    _rs-alias-pattern
    _rs-rreg @ _rs-saved-runtime !
    _rs-alias-session _rs-rreg !
    S" org.akashic.resource.test-a" _rs-alias-client @
        _rs-alias-session RSES-INIT RSES-S-INVALID = _rs-assert
    _rs-saved-runtime @ _rs-rreg !
    _rs-alias-unchanged? _rs-assert

    _rs-alias-pattern
    _rs-bus @ _rs-saved-runtime !
    _rs-alias-session _rs-bus !
    S" org.akashic.resource.test-a" _rs-alias-client @
        _rs-alias-session RSES-INIT RSES-S-INVALID = _rs-assert
    _rs-saved-runtime @ _rs-bus !
    _rs-alias-unchanged? _rs-assert

    \ Malformed nested pointers are still aliases, not permission to turn the
    \ output into a BLOCKED session.  Raw offer/pool geometry is checked before
    \ ROFFER/ROPOOL validators can reject the surrounding graph.
    _rs-alias-pattern
    _rs-offer-a ROFFER.POOL @ _rs-saved-runtime !
    _rs-alias-session _rs-offer-a ROFFER.POOL !
    _rs-alias-init-rejected
    _rs-saved-runtime @ _rs-offer-a ROFFER.POOL !

    _rs-alias-pattern
    _rs-pool-a ROPOOL.SLOTS @ _rs-saved-runtime !
    _rs-alias-session _rs-pool-a ROPOOL.SLOTS !
    _rs-alias-init-rejected
    _rs-saved-runtime @ _rs-pool-a ROPOOL.SLOTS !

    _rs-alias-pattern
    _rs-pool-a ROPOOL.LEASES @ _rs-saved-runtime !
    _rs-alias-session _rs-pool-a ROPOOL.LEASES !
    _rs-alias-init-rejected
    _rs-saved-runtime @ _rs-pool-a ROPOOL.LEASES !

    _rs-alias-pattern
    _rs-pool-a ROPOOL.CONTEXT @ _rs-saved-runtime !
    _rs-alias-session _rs-pool-a ROPOOL.CONTEXT !
    _rs-alias-init-rejected
    _rs-saved-runtime @ _rs-pool-a ROPOOL.CONTEXT !

    _rs-alias-pattern
    _rs-pool-a ROPOOL.CREG @ _rs-saved-runtime !
    _rs-alias-session _rs-pool-a ROPOOL.CREG !
    _rs-alias-init-rejected
    _rs-saved-runtime @ _rs-pool-a ROPOOL.CREG !

    _rs-alias-pattern
    _rs-pool-a ROPOOL.RREG @ _rs-saved-runtime !
    _rs-alias-session _rs-pool-a ROPOOL.RREG !
    _rs-alias-init-rejected
    _rs-saved-runtime @ _rs-pool-a ROPOOL.RREG !

    \ Every pointer derived from the staged runtime headers is protected before
    \ graph comparisons.  A contradictory graph cannot hide an output alias.
    _rs-alias-pattern
    _rs-rreg @ RREG.CONTEXT @ _rs-saved-runtime !
    _rs-alias-session _rs-rreg @ RREG.CONTEXT !
    _rs-alias-init-rejected
    _rs-saved-runtime @ _rs-rreg @ RREG.CONTEXT !

    _rs-alias-pattern
    _rs-rreg @ RREG.COMPONENTS @ _rs-saved-runtime !
    _rs-alias-session _rs-rreg @ RREG.COMPONENTS !
    _rs-alias-init-rejected
    _rs-saved-runtime @ _rs-rreg @ RREG.COMPONENTS !

    _rs-alias-pattern
    _rs-bus @ CBUS.REGISTRY @ _rs-saved-runtime !
    _rs-alias-session _rs-bus @ CBUS.REGISTRY !
    _rs-alias-init-rejected
    _rs-saved-runtime @ _rs-bus @ CBUS.REGISTRY !

    _rs-alias-pattern
    _rs-bus @ CBUS.POLICY @ _rs-saved-runtime !
    _rs-alias-session _rs-bus @ CBUS.POLICY !
    _rs-alias-init-rejected
    _rs-saved-runtime @ _rs-bus @ CBUS.POLICY !

    _rs-alias-pattern
    _rs-context @ CTX.QUEUE @ _rs-saved-runtime !
    _rs-alias-session _rs-context @ CTX.QUEUE !
    _rs-alias-init-rejected
    _rs-saved-runtime @ _rs-context @ CTX.QUEUE !

    _rs-alias-pattern
    _rs-context @ CTX.POLICY @ _rs-saved-runtime !
    _rs-alias-session _rs-context @ CTX.POLICY !
    _rs-alias-init-rejected
    _rs-saved-runtime @ _rs-context @ CTX.POLICY !
    _rs-stack

    \ Runtime services are each queried once before the named offer is queried
    \ once.  A callback armed to mutate the offer only after named discovery
    \ must therefore never run in that dangerous phase.
    _rs-query-counts-clear
    -1 _rs-mutate-after-named !
    S" org.akashic.resource.test-a" _rs-alias-client @
        _rs-blocked-session RSES-INIT RSES-S-OK = _rs-assert
    _rs-context-calls @ 1 = _rs-assert
    _rs-rreg-calls @ 1 = _rs-assert
    _rs-bus-calls @ 1 = _rs-assert
    _rs-named-a-calls @ 1 = _rs-assert
    _rs-after-named-runtime @ 0= _rs-assert
    _rs-mutate-after-named @ _rs-assert
    _rs-blocked-session RSES.RID _rs-rid-a RID= _rs-assert
    _rs-blocked-session RSES.POOL @ _rs-pool-a = _rs-assert
    _rs-blocked-session RSES-FINI RSES-S-OK = _rs-assert
    _rs-rid-a _rs-pool-a _rs-offer-a ROFFER-INIT
        RACQ-S-OK = _rs-assert
    0 _rs-mutate-after-named ! 0 _rs-named-seen !
    _rs-pool-a ROPOOL-LEASES@ 1 = _rs-assert
    _rs-stack

    \ Endpoint-free is the only DIRECT mode.  An endpoint with an incomplete
    \ runtime service graph is BLOCKED and cannot retain anything.
    0 _rs-new-client DUP _rs-direct-client ! DROP
    S" org.akashic.resource.test-a" _rs-direct-client @
        _rs-direct-session RSES-INIT
        RSES-S-OK = _rs-assert
    _rs-direct-session RSES.MODE @ RSES-M-DIRECT = _rs-assert
    _rs-direct-session RSES-VALID? _rs-assert
    _rs-direct-session RSES-HELD? 0= _rs-assert
    _rs-direct-session RSES-FINI RSES-S-OK = _rs-assert

    _rs-blocked-endpoint _rs-new-client DUP _rs-blocked-client ! DROP
    S" org.akashic.resource.test-a" _rs-blocked-client @
        _rs-blocked-session RSES-INIT
        RSES-S-BLOCKED = _rs-assert
    _rs-blocked-session RSES.MODE @ RSES-M-BLOCKED = _rs-assert
    _rs-blocked-session RSES-VALID? _rs-assert
    _rs-blocked-session RSES-HELD? 0= _rs-assert
    _rs-pool-a ROPOOL-LEASES@ 1 = _rs-assert
    _rs-pool-b ROPOOL-LEASES@ 1 = _rs-assert
    _rs-blocked-session RSES-FINI RSES-S-OK = _rs-assert
    _rs-stack

    \ Compact schemas remain compact while sharing RACQ lifetime machinery.
    _rs-endpoint-a _rs-new-client DUP _rs-client-a ! DROP
    S" org.akashic.resource.test-b" _rs-client-a @
        _rs-blocked-session RSES-INIT RSES-S-BLOCKED = _rs-assert
    _rs-pool-a ROPOOL-LEASES@ 1 = _rs-assert
    _rs-pool-b ROPOOL-LEASES@ 1 = _rs-assert
    _rs-blocked-session RSES-FINI RSES-S-OK = _rs-assert
    S" org.akashic.resource.test-a" _rs-client-a @ _rs-session-a RSES-INIT
        RSES-S-OK = _rs-assert
    _rs-offer-a ROFFER-SIZE 0 FILL
    _rs-offer-a ROFFER-VALID? 0= _rs-assert
    _rs-session-a RSES-VALID? _rs-assert
    _rs-session-a RSES-CANONICAL? 0= _rs-assert
    _rs-session-a RSES-HELD? _rs-assert
    _rs-session-a RSES.RID _rs-rid-a RID= _rs-assert
    _rs-session-a RSES.REF RREF.REVISION @ 1 = _rs-assert
    _rs-session-a RSES.BIND LBIND.REVISION @ 1 = _rs-assert
    _rs-session-a RSES.POOL @ _rs-pool-a = _rs-assert
    _rs-session-a RSES.ROOT @ _rs-pool-a ROPOOL-RACQ = _rs-assert
    _rs-pool-a ROPOOL-LEASES@ 2 = _rs-assert

    \ Public CLEAR is only a fresh/final initialization operation.  A live
    \ request/token pair is byte-for-byte preserved, and INIT independently
    \ refuses to reuse the held session without orphaning its lease.
    _rs-session-a _rs-held-before RSES-SIZE CMOVE
    _rs-session-a RSES.REQUEST @ _rs-request-before-fini !
    _rs-session-a RSES-CLEAR
    _rs-session-a RSES-SIZE _rs-held-before RSES-SIZE STR-STR= _rs-assert
    _rs-session-a RSES-VALID? _rs-assert
    _rs-session-a RSES-HELD? _rs-assert
    _rs-session-a RSES.REQUEST @ _rs-request-before-fini @ = _rs-assert
    _rs-pool-a ROPOOL-LEASES@ 2 = _rs-assert
    S" org.akashic.resource.test-a" _rs-client-a @ _rs-session-a RSES-INIT
        RSES-S-INVALID = _rs-assert
    _rs-session-a RSES-SIZE _rs-held-before RSES-SIZE STR-STR= _rs-assert
    _rs-session-a RSES-HELD? _rs-assert
    _rs-pool-a ROPOOL-LEASES@ 2 = _rs-assert
    _rs-stack

    _rs-session-a RSES.SNAPSHOT @ CPRINC-USER _rs-session-a RSES-PREPARE
        RSES-S-OK = _rs-assert
    _rs-session-a RSES.REQUEST @ CBR.ARGS CV-NULL!
    _rs-session-a RSES-DISPATCH CBUS-S-OK = _rs-assert
    S" seed" _rs-session-a _rs-result= _rs-assert
    _rs-session-a RSES-ADVANCE RSES-S-OK = _rs-assert

    _rs-session-a RSES.REPLACE @ CPRINC-USER _rs-session-a RSES-PREPARE
        RSES-S-OK = _rs-assert
    S" one" _rs-session-a RSES.REQUEST @ CBR.ARGS CV-STRING! 0= _rs-assert
    _rs-session-a RSES-DISPATCH CBUS-S-OK = _rs-assert
    _rs-session-a RSES-ADVANCE RSES-S-OK = _rs-assert
    _rs-session-a RSES.BIND LBIND.REVISION @ 2 = _rs-assert
    _rs-session-a RSES.REF RREF.REVISION @ 2 = _rs-assert
    _rs-owner-data _RSO-REPLACE-N + @ 1 = _rs-assert
    _rs-stack

    \ Exact RCON capabilities arm the embedded typed client without changing
    \ the surrounding pool/session lifetime.
    _rs-endpoint-b _rs-new-client DUP _rs-canonical-client ! DROP
    0 1 _rs-can-cap CAP.EFFECTS !
    S" org.akashic.resource.test-b" _rs-canonical-client @
        _rs-blocked-session RSES-INIT RSES-S-BLOCKED = _rs-assert
    _rs-pool-b ROPOOL-ACQUIRE-CALLS@ 2 = _rs-assert
    _rs-pool-b ROPOOL-RELEASE-CALLS@ 1 = _rs-assert
    _rs-pool-b ROPOOL-LEASES@ 1 = _rs-assert
    _rs-blocked-session RSES-HELD? 0= _rs-assert
    _rs-blocked-session RSES.CANDIDATE-BIND LBIND-VALID? 0= _rs-assert
    CAP-E-OBSERVE 1 _rs-can-cap CAP.EFFECTS !
    _rs-blocked-session RSES-FINI RSES-S-OK = _rs-assert
    S" org.akashic.resource.test-b" _rs-canonical-client @
        _rs-canonical-session RSES-INIT
        RSES-S-OK = _rs-assert
    _rs-offer-b ROFFER-SIZE 0 FILL
    _rs-offer-b ROFFER-VALID? 0= _rs-assert
    _rs-canonical-session RSES-CANONICAL? _rs-assert
    _rs-canonical-session RSES.CLIENT RCLI-VALID? _rs-assert
    _rs-canonical-session RSES.RID _rs-rid-b RID= _rs-assert
    _rs-canonical-session RSES.POOL @ _rs-pool-b = _rs-assert
    _rs-canonical-session RSES.ROOT @ _rs-pool-b ROPOOL-RACQ = _rs-assert
    _rs-canonical-session RSES.BIND LBIND.REVISION @ 1 = _rs-assert
    _rs-pool-b ROPOOL-LEASES@ 2 = _rs-assert
    _rs-canonical-session RSES-FINI RSES-S-OK = _rs-assert
    _rs-pool-b ROPOOL-LEASES@ 1 = _rs-assert
    _rs-stack

    \ A failed candidate never overwrites the live authoritative state.
    _rs-session-a RSES.REF _rs-bad-ref RREF-COPY RREF-S-OK = _rs-assert
    99 _rs-bad-ref RREF.REVISION +!
    _rs-session-a RSES.BIND LBIND.REVISION @ _rs-old-revision !
    _rs-bad-ref _rs-session-a RSES-CANDIDATE-ATTACH
        RSES-S-STALE = _rs-assert
    _rs-session-a RSES-ACTIVE? _rs-assert
    _rs-session-a RSES.BIND LBIND.REVISION @
        _rs-old-revision @ = _rs-assert
    _rs-session-a 0 RSES-REFRESH-N RSES-S-INVALID = _rs-assert

    \ Independently valid, same-revision candidate fields are not enough:
    \ a forged ref for RID B must never publish beside RID A's binding.
    _rs-session-a RSES.REF _rs-session-a RSES-CANDIDATE-ATTACH
        RSES-S-OK = _rs-assert
    _rs-rid-b _rs-session-a RSES.CANDIDATE-REF RREF.ID RID-COPY
    _rs-session-a RSES.CANDIDATE-REF RREF-VALID? _rs-assert
    _rs-session-a RSES.CANDIDATE-BIND LBIND-VALID? _rs-assert
    _rs-session-a RSES.CANDIDATE-REF RREF.REVISION @
        _rs-session-a RSES.CANDIDATE-BIND LBIND.REVISION @ = _rs-assert
    _rs-session-a RSES-CANDIDATE-COMMIT RSES-S-STALE = _rs-assert
    _rs-session-a RSES-ACTIVE? _rs-assert
    _rs-session-a RSES.REF RREF.ID _rs-rid-a RID= _rs-assert
    _rs-session-a RSES.BIND LBIND.RESOURCE-ID _rs-rid-a RID= _rs-assert
    _rs-session-a RSES.CANDIDATE-REF RREF-VALID? 0= _rs-assert
    _rs-session-a RSES-VALID? _rs-assert

    \ Public candidate attachment is alias-safe for Pad's exact journey:
    \ the input reference may already occupy the embedded candidate slot.
    _rs-session-a RSES.REF _rs-session-a RSES.CANDIDATE-REF RREF-COPY
        RREF-S-OK = _rs-assert
    _rs-session-a RSES.CANDIDATE-REF _rs-session-a
        RSES-CANDIDATE-ATTACH RSES-S-OK = _rs-assert
    _rs-session-a RSES.CANDIDATE-REF RREF-VALID? _rs-assert
    _rs-session-a RSES.CANDIDATE-BIND LBIND-VALID? _rs-assert
    _rs-session-a RSES-CANDIDATE-COMMIT RSES-S-OK = _rs-assert
    _rs-session-a RSES-VALID? _rs-assert

    \ Pad-style candidate snapshot becomes authoritative only at COMMIT.
    _rs-rid-a _rs-context @ _rs-exact-ref _rs-rreg @ RREG-REF
        RREG-S-OK = _rs-assert
    _rs-exact-ref _rs-session-a RSES-CANDIDATE-ATTACH
        RSES-S-OK = _rs-assert
    _rs-session-a RSES.SNAPSHOT @ CPRINC-USER
        _rs-session-a RSES-CANDIDATE-PREPARE RSES-S-OK = _rs-assert
    _rs-session-a RSES.REQUEST @ CBR.ARGS CV-NULL!
    _rs-session-a RSES-DISPATCH CBUS-S-OK = _rs-assert
    S" one" _rs-session-a _rs-result= _rs-assert
    _rs-session-a RSES-CANDIDATE-COMMIT RSES-S-OK = _rs-assert
    _rs-session-a RSES.BIND LBIND.REVISION @ 2 = _rs-assert

    \ Two sessions own distinct tokens.  A stale pre-dispatch write changes
    \ neither owner content nor mutation count, and explicit refresh reuses
    \ the same retained lease.
    _rs-rid-a _rs-pool-a _rs-offer-a ROFFER-INIT
        RACQ-S-OK = _rs-assert
    _rs-endpoint-a _rs-new-client DUP _rs-client-b ! DROP
    S" org.akashic.resource.test-a" _rs-client-b @ _rs-session-b RSES-INIT
        RSES-S-OK = _rs-assert
    _rs-session-b RSES.RID _rs-rid-a RID= _rs-assert
    _rs-session-b RSES.POOL @ _rs-pool-a = _rs-assert
    _rs-session-a RSES.ACQUISITION RACQ.RESULT-TOKEN
        _rs-session-b RSES.ACQUISITION RACQ.RESULT-TOKEN <> _rs-assert
    _rs-pool-a ROPOOL-LEASES@ 3 = _rs-assert

    _rs-session-a RSES.REPLACE @ CPRINC-USER _rs-session-a RSES-PREPARE
        RSES-S-OK = _rs-assert
    S" two" _rs-session-a RSES.REQUEST @ CBR.ARGS CV-STRING! 0= _rs-assert
    _rs-session-a RSES-DISPATCH CBUS-S-OK = _rs-assert
    _rs-session-a RSES-ADVANCE RSES-S-OK = _rs-assert
    _rs-owner-data _RSO-REPLACE-N + @ 2 = _rs-assert

    _rs-session-b RSES.REPLACE @ CPRINC-USER _rs-session-b RSES-PREPARE
        RSES-S-OK = _rs-assert
    S" stale" _rs-session-b RSES.REQUEST @ CBR.ARGS CV-STRING! 0= _rs-assert
    _rs-session-b RSES-DISPATCH CBUS-S-STALE-REVISION = _rs-assert
    _rs-session-b RSES-STALE? _rs-assert
    _rs-owner-data _RSO-REPLACE-N + @ 2 = _rs-assert
    _rs-session-b RSES.REPLACE @ CPRINC-USER _rs-session-b RSES-PREPARE
        RSES-S-STALE = _rs-assert
    _rs-session-b RSES-REFRESH RSES-S-OK = _rs-assert
    _rs-session-b RSES-ACTIVE? _rs-assert
    _rs-session-b RSES.BIND LBIND.REVISION @ 3 = _rs-assert
    _rs-pool-a ROPOOL-LEASES@ 3 = _rs-assert
    _rs-stack

    \ Owner success followed by local advance failure is explicitly
    \ COMMITTED-STALE.  The lease remains releasable, ordinary prepare is
    \ blocked, and explicit refresh recovers exactly the one mutation.
    _rs-session-a RSES.REPLACE @ CPRINC-USER _rs-session-a RSES-PREPARE
        RSES-S-OK = _rs-assert
    S" three" _rs-session-a RSES.REQUEST @ CBR.ARGS CV-STRING! 0= _rs-assert
    _rs-session-a RSES-DISPATCH CBUS-S-OK = _rs-assert
    ['] _rs-advance-fail _rs-session-a RSES.ADVANCE-XT !
    _rs-session-a RSES-ADVANCE RSES-S-COMMITTED-STALE = _rs-assert
    ['] LBIND-ADVANCE _rs-session-a RSES.ADVANCE-XT !
    _rs-session-a RSES-STALE? _rs-assert
    _rs-session-a RSES.BIND LBIND-VALID? 0= _rs-assert
    _rs-session-a RSES.REF RREF-VALID? 0= _rs-assert
    _rs-session-a RSES-HELD? _rs-assert
    _rs-owner-data _RSO-REPLACE-N + @ 3 = _rs-assert
    _rs-session-a RSES.REPLACE @ CPRINC-USER _rs-session-a RSES-PREPARE
        RSES-S-STALE = _rs-assert
    _rs-owner-data _RSO-REPLACE-N + @ 3 = _rs-assert
    _rs-session-a RSES-REFRESH RSES-S-OK = _rs-assert
    _rs-session-a RSES.BIND LBIND.REVISION @ 4 = _rs-assert
    _rs-session-a RSES.SNAPSHOT @ CPRINC-USER _rs-session-a RSES-PREPARE
        RSES-S-OK = _rs-assert
    _rs-session-a RSES.REQUEST @ CBR.ARGS CV-NULL!
    _rs-session-a RSES-DISPATCH CBUS-S-OK = _rs-assert
    S" three" _rs-session-a _rs-result= _rs-assert
    _rs-session-a RSES-ADVANCE RSES-S-OK = _rs-assert
    _rs-stack

    \ Finalization failure leaves the exact request/token/binding retryable.
    _rs-session-b RSES.REQUEST @ _rs-request-before-fini !
    1 _rs-pool-a ROPOOL-RELEASE-FAILURES! RACQ-S-OK = _rs-assert
    _rs-session-b RSES-FINI RSES-S-RELEASE = _rs-assert
    _rs-session-b RSES-HELD? _rs-assert
    _rs-session-b RSES.REQUEST @ _rs-request-before-fini @ = _rs-assert
    _rs-pool-a ROPOOL-LEASES@ 3 = _rs-assert
    _rs-session-b RSES-FINI RSES-S-OK = _rs-assert
    _rs-pool-a ROPOOL-LEASES@ 2 = _rs-assert
    _rs-session-a RSES-FINI RSES-S-OK = _rs-assert
    _rs-pool-a ROPOOL-LEASES@ 1 = _rs-assert

    _rs-seed-bind-a _rs-seed-result-a RACQ-DETACH RACQ-S-OK = _rs-assert
    _rs-seed-bind-b _rs-seed-result-b RACQ-DETACH RACQ-S-OK = _rs-assert
    _rs-pool-a ROPOOL-LIVE@ 0= _rs-assert
    _rs-pool-a ROPOOL-LEASES@ 0= _rs-assert
    _rs-pool-b ROPOOL-LIVE@ 0= _rs-assert
    _rs-pool-b ROPOOL-LEASES@ 0= _rs-assert
    _rs-pool-a ROPOOL-FINI RACQ-S-OK = _rs-assert
    _rs-pool-b ROPOOL-FINI RACQ-S-OK = _rs-assert

    _rs-direct-client @ CINST-FREE
    _rs-blocked-client @ CINST-FREE
    _rs-client-a @ CINST-FREE
    _rs-client-b @ CINST-FREE
    _rs-canonical-client @ CINST-FREE
    _rs-alias-client @ CINST-FREE
    _rs-bus @ CBUS-FREE
    _rs-rreg @ RREG-FREE
    _rs-creg @ CREG-FREE
    _rs-context @ CTX-FREE
    _rs-stack

    _rs-fails @ 0= IF
        ." RESOURCE SESSION PASS " _rs-checks @ .
    ELSE
        ." RESOURCE SESSION FAIL " _rs-fails @ . ." / " _rs-checks @ .
    THEN CR ;

_rs-run
'''


def test_resource_session_contracts(tmp_path: Path) -> None:
    PROFILES[PROFILE_NAME] = Profile(
        roots=("interop/resource-session.f",),
        resources=(),
        autoexec=AUTOEXEC,
        ready_markers=("RESOURCE SESSION PASS",),
        stable_markers=("RESOURCE SESSION PASS",),
        failure_markers=("RESOURCE SESSION FAIL",),
    )
    image = build_image(PROFILE_NAME, tmp_path / "resource-session.img")
    assert smoke(
        PROFILE_NAME,
        image,
        cols=100,
        rows=30,
        max_steps=2_500_000_000,
        timeout=240.0,
    )


if __name__ == "__main__":
    import tempfile

    with tempfile.TemporaryDirectory() as directory:
        test_resource_session_contracts(Path(directory))
