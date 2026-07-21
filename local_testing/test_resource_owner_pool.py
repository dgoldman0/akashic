#!/usr/bin/env python3
"""Focused contracts for the caller-owned neutral resource-owner pool."""

from __future__ import annotations

from pathlib import Path
import sys


LOCAL_TESTING = Path(__file__).resolve().parent
sys.path.insert(0, str(LOCAL_TESTING))

from akashic_tui import Profile, PROFILES, build_image, smoke  # noqa: E402


PROFILE_NAME = "resource-owner-pool-contracts"

AUTOEXEC = r'''\ autoexec.f - resource-owner-pool contracts
ENTER-USERLAND
." [akashic] loading resource-owner-pool contracts" CR
REQUIRE interop/resource-owner-pool.f

VARIABLE _rp-fails
VARIABLE _rp-checks
VARIABLE _rp-depth

: _rp-assert  ( flag -- )
    1 _rp-checks +!
    0= IF 1 _rp-fails +! ." ASSERT " _rp-checks @ . CR THEN ;

: _rp-stack  ( -- ) DEPTH _rp-depth @ = _rp-assert ;
: _rp-id!  ( value rid -- ) DUP RID-CLEAR ! ;

2 CONSTANT _RP-SLOT-CAP
4 CONSTANT _RP-LEASE-CAP
1 CONSTANT _RP2-SLOT-CAP
2 CONSTANT _RP2-LEASE-CAP
7 CONSTANT _RP-TAG
ROPOOL-CONFIG-SIZE ROPOOL-SLOT-SIZE + CONSTANT _RP-HOSTILE-REGION-SIZE

CREATE _rp-head PHEAD-SIZE ALLOT
CREATE _rp-rid-a RID-SIZE ALLOT
CREATE _rp-rid-b RID-SIZE ALLOT
CREATE _rp-rid-c RID-SIZE ALLOT
CREATE _rp-rid-rollback RID-SIZE ALLOT
CREATE _rp-ref-a RREF-SIZE ALLOT
CREATE _rp-ref-b RREF-SIZE ALLOT
CREATE _rp-ref-c RREF-SIZE ALLOT
CREATE _rp-ref-rollback RREF-SIZE ALLOT
CREATE _rp-locator-a QLOC-SIZE ALLOT
CREATE _rp-locator-b QLOC-SIZE ALLOT
CREATE _rp-locator-c QLOC-SIZE ALLOT
CREATE _rp-locator-rollback QLOC-SIZE ALLOT

CREATE _rp-desc COMP-DESC ALLOT
CREATE _rp-cap CAP-DESC ALLOT
CREATE _rp-desc-snapshot COMP-DESC ALLOT
CREATE _rp-cap-snapshot CAP-DESC ALLOT
CREATE _rp-config ROPOOL-CONFIG-SIZE ALLOT
CREATE _rp-pool ROPOOL-SIZE ALLOT
CREATE _rp-slots _RP-SLOT-CAP ROPOOL-SLOT-SIZE * ALLOT
CREATE _rp-leases _RP-LEASE-CAP ROPOOL-LEASE-SIZE * ALLOT
CREATE _rp-config2 ROPOOL-CONFIG-SIZE ALLOT
CREATE _rp-pool2 ROPOOL-SIZE ALLOT
CREATE _rp-slots2 _RP2-SLOT-CAP ROPOOL-SLOT-SIZE * ALLOT
CREATE _rp-leases2 _RP2-LEASE-CAP ROPOOL-LEASE-SIZE * ALLOT
CREATE _rp-offer ROFFER-SIZE ALLOT
CREATE _rp-offer-bad ROFFER-SIZE ALLOT
CREATE _rp-malformed-member ROPOOL-MEMBER-SIZE ALLOT
CREATE _rp-malformed-pool ROPOOL-SIZE ALLOT
CREATE _rp-hostile-config ROPOOL-CONFIG-SIZE ALLOT
CREATE _rp-hostile-pool ROPOOL-SIZE ALLOT
CREATE _rp-hostile-slots ROPOOL-SLOT-SIZE ALLOT
CREATE _rp-hostile-leases ROPOOL-LEASE-SIZE ALLOT
CREATE _rp-hostile-config-snapshot ROPOOL-CONFIG-SIZE ALLOT
CREATE _rp-hostile-pool-snapshot ROPOOL-SIZE ALLOT
CREATE _rp-hostile-slots-snapshot ROPOOL-SLOT-SIZE ALLOT
CREATE _rp-hostile-leases-snapshot ROPOOL-LEASE-SIZE ALLOT
CREATE _rp-hostile-region _RP-HOSTILE-REGION-SIZE ALLOT
CREATE _rp-hostile-region-snapshot _RP-HOSTILE-REGION-SIZE ALLOT
CREATE _rp-runtime-before RREG-SIZE ALLOT
CREATE _rp-runtime-staged RREG-SIZE ALLOT

CREATE _rp-bind-a LBIND-SIZE ALLOT
CREATE _rp-bind-a2 LBIND-SIZE ALLOT
CREATE _rp-bind-b LBIND-SIZE ALLOT
CREATE _rp-bind-c LBIND-SIZE ALLOT
CREATE _rp-bind-fail LBIND-SIZE ALLOT
CREATE _rp-result-a RACQ-RESULT-SIZE ALLOT
CREATE _rp-result-a2 RACQ-RESULT-SIZE ALLOT
CREATE _rp-result-b RACQ-RESULT-SIZE ALLOT
CREATE _rp-result-c RACQ-RESULT-SIZE ALLOT
CREATE _rp-result-fail RACQ-RESULT-SIZE ALLOT
CREATE _rp-forged RACQ-TOKEN-SIZE ALLOT

VARIABLE _rp-context
VARIABLE _rp-creg
VARIABLE _rp-rreg
VARIABLE _rp-owner-data
VARIABLE _rp-admit-status
VARIABLE _rp-state-status
VARIABLE _rp-admit-throw
VARIABLE _rp-desc-throw
VARIABLE _rp-state-throw
VARIABLE _rp-admit-calls
VARIABLE _rp-state-calls
VARIABLE _rp-old-generation
VARIABLE _rp-instance
VARIABLE _rp-instance2
VARIABLE _rp-member
VARIABLE _rp-member2
VARIABLE _rp-request
VARIABLE _rp-request2
VARIABLE _rp-foreign
VARIABLE _rp-n
VARIABLE _rp-j
VARIABLE _rp-request-rid
VARIABLE _rp-hostile-status
VARIABLE _rp-alias-a
VARIABLE _rp-alias-u
VARIABLE _rp-alias-slots
VARIABLE _rp-alias-config

: _rp-member-fini  ( state -- ) ROPOOL-MEMBER-CLEAR ;

: _rp-admit  ( locator owner-data -- tag status )
    _rp-owner-data <> IF DROP 0 RACQ-S-INVALID EXIT THEN
    1 _rp-admit-calls +!
    _rp-admit-throw @ IF -701 THROW THEN
    DUP QLOC-VALID? 0= IF DROP 0 RACQ-S-INVALID EXIT THEN
    DROP _RP-TAG _rp-admit-status @ ;

: _rp-descriptor  ( tag owner-data -- descriptor|0 )
    _rp-owner-data <> IF DROP 0 EXIT THEN
    _rp-desc-throw @ IF -702 THROW THEN
    _RP-TAG = IF _rp-desc ELSE 0 THEN ;

: _rp-state-init  ( locator tag instance owner-data -- status )
    _rp-owner-data <> IF 2DROP DROP RACQ-S-INVALID EXIT THEN
    1 _rp-state-calls +!
    _rp-state-throw @ IF -703 THROW THEN
    >R
    DUP _RP-TAG <> IF R> DROP 2DROP RACQ-S-INVALID EXIT THEN
    DROP
    DUP QLOC-VALID? 0= IF DROP R> DROP RACQ-S-INVALID EXIT THEN
    DROP
    R> CINST-STATE ROPOOL-MEMBER-SIZE + 0xC0FFEE SWAP !
    _rp-state-status @ ;

: _rp-desc-init-must-not-run  ( state -- ior )
    DROP -704 THROW ;

: _rp-owner$  ( -- a u ) S" org.example.resource-pool" ;
: _rp-cap-id$  ( -- a u ) S" org.example.pool.inspect" ;

: _rp-locator!  ( rid ref locator -- )
    >R >R
    R@ RREF-INIT
    DUP R@ RREF.ID RID-COPY
    DROP
    _rp-owner$ R> R> QLOC-IDENTITY! QLOC-S-OK = _rp-assert ;

: _rp-attach  ( locator binding result -- status )
    >R >R _rp-pool _rp-context @ _rp-rreg @ R> R> ROPOOL-ATTACH ;

: _rp-attach2  ( locator binding result -- status )
    >R >R _rp-pool2 _rp-context @ _rp-rreg @ R> R> ROPOOL-ATTACH ;

: _rp-detach  ( binding result -- status ) RACQ-DETACH ;

: _rp-request-for  ( rid -- request )
    _rp-request-rid !
    CBR-NEW DUP 0= _rp-assert DROP
    DUP >R _rp-request-rid @ R@ CBR.RESOURCE-ID RID-COPY R> DROP ;

: _rp-setup-desc  ( -- )
    _rp-cap CAP-DESC-INIT
    CAP-K-RESOURCE _rp-cap CAP.KIND !
    _rp-cap-id$ _rp-cap CAP.ID-U ! _rp-cap CAP.ID-A !
    _rp-desc COMP-DESC-INIT
    S" org.example.pool.fixture" _rp-desc COMP.ID-U !
        _rp-desc COMP.ID-A !
    S" 1.0.0" _rp-desc COMP.VERSION-U !
        _rp-desc COMP.VERSION-A !
    ROPOOL-MEMBER-SIZE 8 + _rp-desc COMP.STATE-SIZE !
    ['] _rp-member-fini _rp-desc COMP.STATE-FINI-XT !
    _rp-cap _rp-desc COMP.CAPS-A !
    1 _rp-desc COMP.CAPS-N ! ;

: _rp-setup-runtime  ( -- )
    _rp-head PHEAD-INIT
    700 _rp-head PHEAD.ID _rp-id!
    701 _rp-head PHEAD.CURRENT-ROOT _rp-id!
    900 CTX-NEW DUP 0= _rp-assert DROP _rp-context !
    _rp-head _rp-context @ CTX.PRACTICE !
    CTX-F-ACTIVE _rp-context @ CTX.FLAGS !
    CREG-NEW DUP 0= _rp-assert DROP _rp-creg !
    _rp-creg @ _rp-context @ RREG-NEW
        DUP RREG-S-OK = _rp-assert DROP _rp-rreg ! ;

: _rp-setup-locators  ( -- )
    710 _rp-rid-a _rp-id!
    711 _rp-rid-b _rp-id!
    712 _rp-rid-c _rp-id!
    713 _rp-rid-rollback _rp-id!
    _rp-rid-a _rp-ref-a _rp-locator-a _rp-locator!
    _rp-rid-b _rp-ref-b _rp-locator-b _rp-locator!
    _rp-rid-c _rp-ref-c _rp-locator-c _rp-locator!
    _rp-rid-rollback _rp-ref-rollback _rp-locator-rollback _rp-locator! ;

: _rp-setup-pool  ( -- )
    ROPOOL-SLOT-SIZE 96 = _rp-assert
    ROPOOL-LEASE-SIZE 48 = _rp-assert
    ROPOOL-MEMBER-SIZE 48 = _rp-assert
    ROFFER-SIZE 80 = _rp-assert
    _rp-desc COMP.STATE-INIT-XT @ 0= _rp-assert
    _rp-config ROPOOL-CONFIG-INIT
    _rp-owner$ _rp-config ROPC.OWNER-U ! _rp-config ROPC.OWNER-A !
    _rp-owner-data _rp-config ROPC.OWNER-DATA !
    _rp-context @ _rp-config ROPC.CONTEXT !
    _rp-creg @ _rp-config ROPC.CREG !
    _rp-rreg @ _rp-config ROPC.RREG !
    _rp-slots _rp-config ROPC.SLOTS !
    _RP-SLOT-CAP _rp-config ROPC.SLOT-CAP !
    _rp-leases _rp-config ROPC.LEASES !
    _RP-LEASE-CAP _rp-config ROPC.LEASE-CAP !
    ['] _rp-admit _rp-config ROPC.ADMIT-XT !
    ['] _rp-descriptor _rp-config ROPC.DESCRIPTOR-XT !
    ['] _rp-state-init _rp-config ROPC.STATE-INIT-XT !
    _rp-config ROPOOL-CONFIG-VALID? _rp-assert
    _rp-config _rp-pool ROPOOL-INIT RACQ-S-OK = _rp-assert
    _rp-pool ROPOOL-VALID? _rp-assert
    _rp-pool ROPOOL-RACQ RACQ-ROOT-VALID? _rp-assert
    _rp-pool ROPOOL-LIVE@ 0= _rp-assert
    _rp-pool ROPOOL-LEASES@ 0= _rp-assert

    _rp-config2 ROPOOL-CONFIG-INIT
    _rp-owner$ _rp-config2 ROPC.OWNER-U ! _rp-config2 ROPC.OWNER-A !
    _rp-owner-data _rp-config2 ROPC.OWNER-DATA !
    _rp-context @ _rp-config2 ROPC.CONTEXT !
    _rp-creg @ _rp-config2 ROPC.CREG !
    _rp-rreg @ _rp-config2 ROPC.RREG !
    _rp-slots2 _rp-config2 ROPC.SLOTS !
    _RP2-SLOT-CAP _rp-config2 ROPC.SLOT-CAP !
    _rp-leases2 _rp-config2 ROPC.LEASES !
    _RP2-LEASE-CAP _rp-config2 ROPC.LEASE-CAP !
    ['] _rp-admit _rp-config2 ROPC.ADMIT-XT !
    ['] _rp-descriptor _rp-config2 ROPC.DESCRIPTOR-XT !
    ['] _rp-state-init _rp-config2 ROPC.STATE-INIT-XT !
    _rp-config2 ROPOOL-CONFIG-VALID? _rp-assert
    _rp-config2 _rp-pool2 ROPOOL-INIT RACQ-S-OK = _rp-assert
    _rp-pool2 ROPOOL-VALID? _rp-assert
    _rp-pool2 ROPOOL-LIVE@ 0= _rp-assert
    _rp-pool2 ROPOOL-LEASES@ 0= _rp-assert ;

: _rp-config-clone  ( config -- )
    >R
    _rp-config R@ ROPOOL-CONFIG-SIZE MOVE
    _rp-hostile-slots R@ ROPC.SLOTS !
    1 R@ ROPC.SLOT-CAP !
    _rp-hostile-leases R@ ROPC.LEASES !
    1 R@ ROPC.LEASE-CAP !
    R> DROP ;

: _rp-hostile-reset  ( -- )
    _rp-hostile-pool ROPOOL-SIZE 0xA5 FILL
    _rp-hostile-slots ROPOOL-SLOT-SIZE 0xB6 FILL
    _rp-hostile-leases ROPOOL-LEASE-SIZE 0xC7 FILL
    _rp-hostile-config _rp-config-clone ;

: _rp-hostile-snapshot  ( -- )
    _rp-hostile-config _rp-hostile-config-snapshot
        ROPOOL-CONFIG-SIZE MOVE
    _rp-hostile-pool _rp-hostile-pool-snapshot ROPOOL-SIZE MOVE
    _rp-hostile-slots _rp-hostile-slots-snapshot ROPOOL-SLOT-SIZE MOVE
    _rp-hostile-leases _rp-hostile-leases-snapshot ROPOOL-LEASE-SIZE MOVE ;

: _rp-hostile-same?  ( -- flag )
    _rp-hostile-config ROPOOL-CONFIG-SIZE
        _rp-hostile-config-snapshot ROPOOL-CONFIG-SIZE COMPARE 0=
    _rp-hostile-pool ROPOOL-SIZE
        _rp-hostile-pool-snapshot ROPOOL-SIZE COMPARE 0= AND
    _rp-hostile-slots ROPOOL-SLOT-SIZE
        _rp-hostile-slots-snapshot ROPOOL-SLOT-SIZE COMPARE 0= AND
    _rp-hostile-leases ROPOOL-LEASE-SIZE
        _rp-hostile-leases-snapshot ROPOOL-LEASE-SIZE COMPARE 0= AND ;

: _rp-hostile-restore  ( -- )
    _rp-hostile-config-snapshot _rp-hostile-config
        ROPOOL-CONFIG-SIZE MOVE
    _rp-hostile-pool-snapshot _rp-hostile-pool ROPOOL-SIZE MOVE
    _rp-hostile-slots-snapshot _rp-hostile-slots ROPOOL-SLOT-SIZE MOVE
    _rp-hostile-leases-snapshot _rp-hostile-leases ROPOOL-LEASE-SIZE MOVE ;

: _rp-hostile-call  ( config -- )
    _rp-hostile-snapshot
    _rp-hostile-pool ROPOOL-INIT _rp-hostile-status !
    _rp-hostile-status @ RACQ-S-INVALID = _rp-assert
    _rp-hostile-same? _rp-assert ;

: _rp-runtime-overlap-case  ( runtime size slots? -- )
    _rp-alias-slots ! _rp-alias-u ! _rp-alias-a !
    _rp-hostile-reset
    _rp-alias-slots @ IF
        _rp-alias-a @ _rp-hostile-config ROPC.SLOTS !
    ELSE
        _rp-alias-a @ _rp-hostile-config ROPC.LEASES !
    THEN
    _rp-alias-a @ _rp-runtime-before _rp-alias-u @ MOVE
    _rp-hostile-config _rp-hostile-call
    _rp-alias-a @ _rp-alias-u @ _rp-runtime-before _rp-alias-u @
        COMPARE 0= _rp-assert
    _rp-hostile-restore
    _rp-runtime-before _rp-alias-a @ _rp-alias-u @ MOVE ;

: _rp-config-runtime-overlap-case  ( runtime size -- )
    _rp-alias-u ! _rp-alias-a !
    _rp-alias-a @ _rp-runtime-before _rp-alias-u @ MOVE
    _rp-hostile-reset
    _rp-alias-a @ _rp-alias-u @ + ROPOOL-CONFIG-SIZE -
        DUP _rp-alias-config ! _rp-config-clone
    _rp-alias-config @ ROPOOL-CONFIG-VALID? _rp-assert
    _rp-alias-a @ _rp-runtime-staged _rp-alias-u @ MOVE
    _rp-hostile-snapshot
    _rp-alias-config @ _rp-hostile-pool ROPOOL-INIT
        _rp-hostile-status !
    _rp-hostile-status @ RACQ-S-INVALID = _rp-assert
    _rp-hostile-same? _rp-assert
    _rp-alias-a @ _rp-alias-u @ _rp-runtime-staged _rp-alias-u @
        COMPARE 0= _rp-assert
    _rp-hostile-restore
    _rp-runtime-before _rp-alias-a @ _rp-alias-u @ MOVE ;

: _rp-config-array-overlap-case  ( slots? -- )
    _rp-alias-slots !
    _rp-hostile-reset
    _rp-hostile-region _RP-HOSTILE-REGION-SIZE 0xD8 FILL
    _rp-hostile-region _rp-config-clone
    _rp-hostile-region 136 +
    _rp-alias-slots @ IF
        _rp-hostile-region ROPC.SLOTS !
    ELSE
        _rp-hostile-region ROPC.LEASES !
    THEN
    _rp-hostile-region _rp-hostile-region-snapshot
        _RP-HOSTILE-REGION-SIZE MOVE
    _rp-hostile-snapshot
    _rp-hostile-region _rp-hostile-pool ROPOOL-INIT
        _rp-hostile-status !
    _rp-hostile-status @ RACQ-S-INVALID = _rp-assert
    _rp-hostile-same? _rp-assert
    _rp-hostile-region _RP-HOSTILE-REGION-SIZE
        _rp-hostile-region-snapshot _RP-HOSTILE-REGION-SIZE
        COMPARE 0= _rp-assert
    _rp-hostile-restore ;

: _rp-owner-cleared-span-case  ( storage -- )
    _rp-alias-a !
    _rp-hostile-reset
    S" overlap-owner"
    DUP _rp-hostile-config ROPC.OWNER-U !
    _rp-alias-a @ _rp-hostile-config ROPC.OWNER-A !
    _rp-alias-a @ SWAP MOVE
    _rp-hostile-config ROPOOL-CONFIG-VALID? _rp-assert
    _rp-hostile-config _rp-hostile-call
    _rp-hostile-restore ;

: _rp-init-alias-contracts  ( -- )
    \ CONFIG may not share even its reserved tail with an owned array.
    -1 _rp-config-array-overlap-case
    0 _rp-config-array-overlap-case

    \ CONFIG itself may be staged in otherwise-unused runtime tail bytes;
    \ construction must reject it without changing the borrowed object.
    _rp-context @ CTX-SIZE _rp-config-runtime-overlap-case
    _rp-creg @ CREG-SIZE _rp-config-runtime-overlap-case
    _rp-rreg @ RREG-SIZE _rp-config-runtime-overlap-case

    \ Either owned array overlapping any borrowed runtime object is invalid
    \ and must leave every caller and runtime byte unchanged.
    _rp-context @ CTX-SIZE -1 _rp-runtime-overlap-case
    _rp-creg @ CREG-SIZE -1 _rp-runtime-overlap-case
    _rp-rreg @ RREG-SIZE -1 _rp-runtime-overlap-case
    _rp-context @ CTX-SIZE 0 _rp-runtime-overlap-case
    _rp-creg @ CREG-SIZE 0 _rp-runtime-overlap-case
    _rp-rreg @ RREG-SIZE 0 _rp-runtime-overlap-case

    \ The two owned arrays are also disjoint members of the init graph.
    _rp-hostile-reset
    _rp-hostile-slots 48 + _rp-hostile-config ROPC.LEASES !
    _rp-hostile-config _rp-hostile-call
    _rp-hostile-restore

    \ The retained owner identifier is an eighth known input span.  It may
    \ not be stored inside any destination that INIT clears before RACQ keeps
    \ its pointer.
    _rp-hostile-pool _rp-owner-cleared-span-case
    _rp-hostile-slots _rp-owner-cleared-span-case
    _rp-hostile-leases _rp-owner-cleared-span-case

    \ Null nonempty storage is rejected before public construction.
    _rp-hostile-reset
    0 _rp-hostile-config ROPC.SLOTS !
    _rp-hostile-config ROPOOL-CONFIG-VALID? 0= _rp-assert
    _rp-hostile-config _rp-hostile-call
    _rp-hostile-restore
    _rp-hostile-reset
    0 _rp-hostile-config ROPC.LEASES !
    _rp-hostile-config ROPOOL-CONFIG-VALID? 0= _rp-assert
    _rp-hostile-config _rp-hostile-call
    _rp-hostile-restore
    _rp-pool ROPOOL-VALID? _rp-assert
    _rp-pool2 ROPOOL-VALID? _rp-assert ;

: _rp-assert-member  ( instance -- )
    DUP _rp-instance ! ROPOOL-MEMBER DUP 0<> _rp-assert _rp-member !
    _rp-member @ ROPOOL-MEMBER-VALID? _rp-assert
    _rp-member @ ROPOOL-MEMBER-OWNER@ _rp-pool = _rp-assert
    _rp-instance @ ROPOOL-MEMBER-POOL@ _rp-pool = _rp-assert
    _rp-member @ ROPOOL-MEMBER-TAG@ _RP-TAG = _rp-assert
    _rp-member @ ROPOOL-MEMBER-RID _rp-rid-a RID= _rp-assert
    _rp-member @ ROPOOL-MEMBER-SIZE + @ 0xC0FFEE = _rp-assert ;

: _rp-offer-contracts  ( -- )
    _rp-rid-a _rp-pool _rp-offer ROFFER-INIT RACQ-S-OK = _rp-assert
    _rp-offer ROFFER-VALID? _rp-assert
    _rp-offer ROFFER-RID _rp-rid-a RID= _rp-assert
    _rp-offer ROFFER-POOL@ _rp-pool = _rp-assert
    _rp-rid-b _rp-pool2 _rp-offer-bad ROFFER-INIT
        RACQ-S-OK = _rp-assert
    1 _rp-offer-bad ROFFER.FLAGS !
    _rp-offer-bad ROFFER-VALID? 0= _rp-assert
    _rp-offer-bad ROFFER-RID 0= _rp-assert
    _rp-offer-bad ROFFER-POOL@ 0= _rp-assert
    0 ROFFER-VALID? 0= _rp-assert
    0 ROFFER-RID 0= _rp-assert
    0 ROFFER-POOL@ 0= _rp-assert
    _rp-rid-a _rp-pool _rp-rid-a ROFFER-INIT
        RACQ-S-INVALID = _rp-assert
    _rp-rid-a RID-PRESENT? _rp-assert
    _rp-rid-a _rp-pool _rp-pool ROFFER-INIT
        RACQ-S-INVALID = _rp-assert
    \ Retained owner bytes remain live root metadata and cannot be offer
    \ output, even though they are outside the fixed RACQ header.
    _rp-rid-a _rp-pool _rp-owner$ DROP ROFFER-INIT
        RACQ-S-INVALID = _rp-assert
    _rp-owner$ UTF8-VALID? _rp-assert
    _rp-pool ROPOOL-VALID? _rp-assert ;

: _rp-malformed-contracts  ( -- )
    0 ROPOOL-MEMBER-POOL@ 0= _rp-assert
    0 ROPOOL-MEMBER-OWNER@ 0= _rp-assert
    0 ROPOOL-MEMBER-TAG@ 0= _rp-assert
    0 ROPOOL-MEMBER-RID 0= _rp-assert
    0 0 ROPOOL-HANDLER-BEGIN OR 0= _rp-assert
    0 ROPOOL-HANDLER-END RACQ-S-INVALID = _rp-assert
    _rp-malformed-member ROPOOL-MEMBER-SIZE 0 FILL
    _rp-malformed-pool ROPOOL-SIZE 0 FILL
    ROPOOL-MEMBER-MAGIC _rp-malformed-member ROMEM.MAGIC !
    _rp-malformed-pool _rp-malformed-member ROMEM.POOL !
    _rp-malformed-member _ROPOOL-MEMBER-FAST? 0= _rp-assert
    0 _ROPOOL-INSTANCE-POOL-SHALLOW 0= _rp-assert ;

: _rp-acquire-and-share  ( -- )
    _rp-locator-a _rp-bind-a _rp-result-a _rp-attach
        RACQ-S-OK = _rp-assert
    _rp-result-a RACQ-RESULT-VALID? _rp-assert
    _rp-bind-a LBIND-VALID? _rp-assert
    _rp-pool ROPOOL-LIVE@ 1 = _rp-assert
    _rp-pool ROPOOL-LEASES@ 1 = _rp-assert
    _rp-rid-a _rp-pool ROPOOL-SLOT-FIND DUP 0>= _rp-assert
    DUP _rp-pool ROPOOL-SLOT-INSTANCE@ DUP 0<> _rp-assert
        _rp-assert-member
    DROP

    \ An active instance keeps both its component descriptor and the
    \ descriptor's reachable capability table live for dispatch.  Offer
    \ output may not overwrite either borrowed span, and rejection is
    \ exactly nonmutating.
    _rp-desc _rp-desc-snapshot COMP-DESC MOVE
    _rp-cap _rp-cap-snapshot CAP-DESC MOVE
    _rp-rid-a _rp-pool _rp-desc ROFFER-INIT
        RACQ-S-INVALID = _rp-assert
    _rp-desc COMP-DESC _rp-desc-snapshot COMP-DESC
        COMPARE 0= _rp-assert
    _rp-cap CAP-DESC _rp-cap-snapshot CAP-DESC
        COMPARE 0= _rp-assert
    _rp-rid-a _rp-pool _rp-cap ROFFER-INIT
        RACQ-S-INVALID = _rp-assert
    _rp-desc COMP-DESC _rp-desc-snapshot COMP-DESC
        COMPARE 0= _rp-assert
    _rp-cap CAP-DESC _rp-cap-snapshot CAP-DESC
        COMPARE 0= _rp-assert
    _rp-desc-snapshot _rp-desc COMP-DESC MOVE
    _rp-cap-snapshot _rp-cap CAP-DESC MOVE

    _rp-pool ROPOOL-ACQUIRE-CALLS@ _rp-n !
    0x55AA _rp-result-fail !
    _rp-locator-a _rp-instance @ _rp-result-fail _rp-attach
        RACQ-S-INVALID = _rp-assert
    _rp-result-fail @ 0x55AA = _rp-assert
    0xAA55 _rp-bind-fail !
    _rp-locator-a _rp-bind-fail _rp-member @ _rp-attach
        RACQ-S-INVALID = _rp-assert
    _rp-bind-fail @ 0xAA55 = _rp-assert
    _rp-pool ROPOOL-ACQUIRE-CALLS@ _rp-n @ = _rp-assert
    _rp-member @ ROPOOL-MEMBER-VALID? _rp-assert
    _rp-pool ROPOOL-LIVE@ 1 = _rp-assert
    _rp-pool ROPOOL-LEASES@ 1 = _rp-assert
    _rp-rid-a _rp-pool ROPOOL-REFS@ 1 = _rp-assert
    _rp-admit-calls @ 1 = _rp-assert
    _rp-state-calls @ 1 = _rp-assert

    _rp-locator-a _rp-bind-a2 _rp-result-a2 _rp-attach
        RACQ-S-OK = _rp-assert
    _rp-pool ROPOOL-LIVE@ 1 = _rp-assert
    _rp-pool ROPOOL-LEASES@ 2 = _rp-assert
    _rp-rid-a _rp-pool ROPOOL-REFS@ 2 = _rp-assert
    _rp-state-calls @ 1 = _rp-assert
    _rp-result-a RACQ.RESULT-REF RREF.ID
        _rp-result-a2 RACQ.RESULT-REF RREF.ID RID= _rp-assert

    _rp-result-a RACQ.RESULT-TOKEN _rp-pool ROPOOL-ANCHOR!
        RACQ-S-OK = _rp-assert
    _rp-result-a2 RACQ.RESULT-TOKEN _rp-pool ROPOOL-ANCHOR!
        RACQ-S-BUSY = _rp-assert
    _rp-bind-a _rp-result-a _rp-detach RACQ-S-BUSY = _rp-assert
    _rp-result-a RACQ.RESULT-TOKEN RACQ-TOKEN-ACTIVE? _rp-assert
    _rp-rid-a _rp-pool ROPOOL-REFS@ 2 = _rp-assert
    _rp-bind-a2 _rp-result-a2 _rp-detach RACQ-S-OK = _rp-assert
    _rp-rid-a _rp-pool ROPOOL-REFS@ 1 = _rp-assert
    _rp-pool ROPOOL-VALID? _rp-assert ;

: _rp-forgery-and-retry  ( -- )
    _rp-result-a RACQ.RESULT-TOKEN _rp-forged RACQ-TOKEN-SIZE MOVE
    _rp-forged RACQ-RELEASE RACQ-S-STALE-TOKEN = _rp-assert
    _rp-result-a RACQ.RESULT-TOKEN RACQ-TOKEN-ACTIVE? _rp-assert
    1 _rp-pool ROPOOL-RELEASE-FAILURES! RACQ-S-OK = _rp-assert
    _rp-bind-a _rp-result-a _rp-detach
        RACQ-S-RELEASE-FAILED = _rp-assert
    _rp-result-a RACQ.RESULT-TOKEN RACQ-TOKEN-ACTIVE? _rp-assert
    _rp-bind-a LBIND-VALID? _rp-assert
    _rp-bind-a _rp-result-a _rp-detach RACQ-S-OK = _rp-assert
    _rp-result-a RACQ.RESULT-TOKEN RACQ-TOKEN-ACTIVE? 0= _rp-assert
    _rp-bind-a LBIND-VALID? 0= _rp-assert
    _rp-pool ROPOOL-LIVE@ 0= _rp-assert
    _rp-pool ROPOOL-LEASES@ 0= _rp-assert
    _rp-pool ROPOOL-VALID? _rp-assert ;

: _rp-fault-snapshot  ( -- )
    _rp-creg @ CREG.INST-N @ _rp-n !
    _rp-rreg @ RREG.COUNT @ _rp-j ! ;

: _rp-fault-unchanged  ( -- )
    _rp-pool ROPOOL-LIVE@ 0= _rp-assert
    _rp-pool ROPOOL-LEASES@ 0= _rp-assert
    _rp-creg @ CREG.INST-N @ _rp-n @ = _rp-assert
    _rp-rreg @ RREG.COUNT @ _rp-j @ = _rp-assert
    _rp-pool ROPOOL-VALID? _rp-assert ;

: _rp-callback-faults  ( -- )
    _rp-fault-snapshot
    RACQ-S-UNQUALIFIED _rp-admit-status !
    _rp-locator-c _rp-bind-c _rp-result-c _rp-attach
        RACQ-S-UNQUALIFIED = _rp-assert
    RACQ-S-OK _rp-admit-status !
    _rp-fault-unchanged

    -1 _rp-admit-throw !
    _rp-locator-c _rp-bind-c _rp-result-c _rp-attach
        RACQ-S-INVALID = _rp-assert
    0 _rp-admit-throw !
    _rp-fault-unchanged

    -1 _rp-desc-throw !
    _rp-locator-c _rp-bind-c _rp-result-c _rp-attach
        RACQ-S-UNQUALIFIED = _rp-assert
    0 _rp-desc-throw !
    _rp-fault-unchanged

    ['] _rp-desc-init-must-not-run _rp-desc COMP.STATE-INIT-XT !
    _rp-locator-c _rp-bind-c _rp-result-c _rp-attach
        RACQ-S-UNQUALIFIED = _rp-assert
    0 _rp-desc COMP.STATE-INIT-XT !
    _rp-fault-unchanged

    RACQ-S-UNAVAILABLE _rp-state-status !
    _rp-locator-c _rp-bind-c _rp-result-c _rp-attach
        RACQ-S-UNAVAILABLE = _rp-assert
    RACQ-S-OK _rp-state-status !
    _rp-fault-unchanged

    -1 _rp-state-throw !
    _rp-locator-c _rp-bind-c _rp-result-c _rp-attach
        RACQ-S-INVALID = _rp-assert
    0 _rp-state-throw !
    _rp-fault-unchanged ;

: _rp-generation-and-inflight  ( -- )
    _rp-locator-a _rp-bind-a _rp-result-a _rp-attach
        RACQ-S-OK = _rp-assert
    _rp-result-a RACQ.RESULT-TOKEN RACQ.TOKEN-GENERATION @
        _rp-old-generation !
    _rp-rid-a _rp-request-for _rp-request !
    _rp-request @ _rp-result-a RACQ.RESULT-REF
        _rp-context @ _rp-rreg @ RREG-RESOLVE
    DUP RREG-S-OK = _rp-assert DROP
    ROPOOL-HANDLER-BEGIN DUP _rp-assert DROP _rp-member !
    _rp-result-a RACQ.RESULT-TOKEN _rp-pool
        _rp-pool ROPOOL-RACQ RACQ.ROOT-QUIESCENT-XT @ EXECUTE
        RACQ-S-BUSY = _rp-assert
    _rp-member @ ROPOOL-HANDLER-END RACQ-S-OK = _rp-assert
    _rp-member @ ROPOOL-HANDLER-END RACQ-S-STALE-TOKEN = _rp-assert
    _rp-request @ CBR-FREE 0 _rp-request !
    _rp-bind-a _rp-result-a _rp-detach RACQ-S-OK = _rp-assert
    _rp-locator-a _rp-bind-a _rp-result-a _rp-attach
        RACQ-S-OK = _rp-assert
    _rp-result-a RACQ.RESULT-TOKEN RACQ.TOKEN-GENERATION @
        _rp-old-generation @ > _rp-assert
    1 _rp-pool ROPOOL-QUIESCENT-BUSY! RACQ-S-OK = _rp-assert
    _rp-bind-a _rp-result-a _rp-detach RACQ-S-OK = _rp-assert
    _rp-pool ROPOOL-QUIESCENT-CALLS@ 3 >= _rp-assert ;

: _rp-interleaved-pools  ( -- )
    _rp-locator-a _rp-bind-a _rp-result-a _rp-attach
        RACQ-S-OK = _rp-assert
    _rp-locator-b _rp-bind-b _rp-result-b _rp-attach2
        RACQ-S-OK = _rp-assert
    _rp-rid-a _rp-pool ROPOOL-SLOT-FIND DUP 0>= _rp-assert
        _rp-pool ROPOOL-SLOT-INSTANCE@ DUP 0<> _rp-assert _rp-instance !
    _rp-rid-b _rp-pool2 ROPOOL-SLOT-FIND DUP 0>= _rp-assert
        _rp-pool2 ROPOOL-SLOT-INSTANCE@ DUP 0<> _rp-assert _rp-instance2 !
    _rp-rid-a _rp-request-for _rp-request !
    _rp-rid-b _rp-request-for _rp-request2 !
    _rp-request @ _rp-instance @ ROPOOL-HANDLER-BEGIN
        DUP _rp-assert DROP _rp-member !
    _rp-request2 @ _rp-instance2 @ ROPOOL-HANDLER-BEGIN
        DUP _rp-assert DROP _rp-member2 !
    _rp-member @ ROPOOL-MEMBER-OWNER@ _rp-pool = _rp-assert
    _rp-member2 @ ROPOOL-MEMBER-OWNER@ _rp-pool2 = _rp-assert
    _rp-member @ _rp-member2 @ <> _rp-assert
    _rp-result-a RACQ.RESULT-TOKEN _rp-pool
        _rp-pool ROPOOL-RACQ RACQ.ROOT-QUIESCENT-XT @ EXECUTE
        RACQ-S-BUSY = _rp-assert
    _rp-result-b RACQ.RESULT-TOKEN _rp-pool2
        _rp-pool2 ROPOOL-RACQ RACQ.ROOT-QUIESCENT-XT @ EXECUTE
        RACQ-S-BUSY = _rp-assert
    _rp-member2 @ ROPOOL-HANDLER-END RACQ-S-OK = _rp-assert
    _rp-member @ ROPOOL-HANDLER-END RACQ-S-OK = _rp-assert
    _rp-request2 @ CBR-FREE 0 _rp-request2 !
    _rp-request @ CBR-FREE 0 _rp-request !
    _rp-bind-b _rp-result-b _rp-detach RACQ-S-OK = _rp-assert
    _rp-bind-a _rp-result-a _rp-detach RACQ-S-OK = _rp-assert
    _rp-pool ROPOOL-LIVE@ 0= _rp-assert
    _rp-pool ROPOOL-LEASES@ 0= _rp-assert
    _rp-pool2 ROPOOL-LIVE@ 0= _rp-assert
    _rp-pool2 ROPOOL-LEASES@ 0= _rp-assert
    _rp-pool ROPOOL-VALID? _rp-assert
    _rp-pool2 ROPOOL-VALID? _rp-assert ;

: _rp-publication-rollback  ( -- )
    _rp-desc _rp-creg @ CREG-TYPE-ENSURE 0= _rp-assert
    _rp-desc CINST-NEW DUP 0= _rp-assert DROP DUP _rp-foreign !
    _rp-creg @ CREG-INST+ 0= _rp-assert
    _rp-rid-rollback _rp-foreign @ _rp-context @ _rp-rreg @
        RREG-PUBLISH RREG-S-OK = _rp-assert
    _rp-creg @ CREG.INST-N @ _rp-n !
    _rp-rreg @ RREG.COUNT @ _rp-j !
    _rp-locator-rollback _rp-bind-fail _rp-result-fail _rp-attach
        RACQ-S-UNAVAILABLE = _rp-assert
    _rp-pool ROPOOL-LIVE@ 0= _rp-assert
    _rp-pool ROPOOL-LEASES@ 0= _rp-assert
    _rp-creg @ CREG.INST-N @ _rp-n @ = _rp-assert
    _rp-rreg @ RREG.COUNT @ _rp-j @ = _rp-assert
    _rp-rid-rollback _rp-context @ _rp-rreg @ RREG-UNPUBLISH
        RREG-S-OK = _rp-assert
    _rp-foreign @ _rp-creg @ CREG-INST- 0= _rp-assert
    _rp-foreign @ CINST-FREE 0 _rp-foreign !
    _rp-pool ROPOOL-VALID? _rp-assert ;

: _rp-capacity  ( -- )
    _rp-locator-a _rp-bind-a _rp-result-a _rp-attach
        RACQ-S-OK = _rp-assert
    _rp-locator-b _rp-bind-b _rp-result-b _rp-attach
        RACQ-S-OK = _rp-assert
    _rp-locator-c _rp-bind-c _rp-result-c _rp-attach
        RACQ-S-CAPACITY = _rp-assert
    _rp-pool ROPOOL-LIVE@ _RP-SLOT-CAP = _rp-assert
    _rp-pool ROPOOL-FINI RACQ-S-BUSY = _rp-assert
    \ A failed finalization leaves the live pool and its guard usable; only
    \ successful destruction may clear the embedded guard after release.
    _rp-pool ROPOOL-VALID? _rp-assert
    _rp-pool ROPOOL-LIVE@ _RP-SLOT-CAP = _rp-assert
    _rp-bind-b _rp-result-b _rp-detach RACQ-S-OK = _rp-assert
    _rp-bind-a _rp-result-a _rp-detach RACQ-S-OK = _rp-assert
    _rp-pool ROPOOL-LIVE@ 0= _rp-assert
    _rp-pool ROPOOL-LEASES@ 0= _rp-assert ;

: _rp-teardown  ( -- )
    _rp-pool ROPOOL-ACQUIRE-CALLS@ 0> _rp-assert
    _rp-pool ROPOOL-RELEASE-CALLS@ 0> _rp-assert
    _rp-pool ROPOOL-VALID? _rp-assert
    _rp-pool2 ROPOOL-VALID? _rp-assert
    _rp-offer ROFFER-VALID? _rp-assert
    _rp-pool2 ROPOOL-FINI RACQ-S-OK = _rp-assert
    _rp-pool2 ROPOOL-VALID? 0= _rp-assert
    _rp-pool ROPOOL-FINI RACQ-S-OK = _rp-assert
    _rp-pool ROPOOL-VALID? 0= _rp-assert
    _rp-offer ROFFER-VALID? 0= _rp-assert
    _rp-offer ROFFER-RID 0= _rp-assert
    _rp-offer ROFFER-POOL@ 0= _rp-assert
    _rp-rreg @ RREG.COUNT @ 0= _rp-assert
    _rp-creg @ CREG.INST-N @ 0= _rp-assert
    _rp-rreg @ RREG-FREE
    _rp-creg @ CREG-FREE
    _rp-context @ CTX-FREE ;

: _rp-run  ( -- )
    0 _rp-fails ! 0 _rp-checks !
    RACQ-S-OK _rp-admit-status !
    RACQ-S-OK _rp-state-status !
    0 _rp-admit-throw ! 0 _rp-desc-throw ! 0 _rp-state-throw !
    _rp-setup-desc
    _rp-setup-runtime
    _rp-setup-locators
    _rp-setup-pool
    DEPTH _rp-depth !
    _rp-init-alias-contracts _rp-stack
    _rp-offer-contracts _rp-stack
    _rp-malformed-contracts _rp-stack
    _rp-acquire-and-share _rp-stack
    _rp-forgery-and-retry _rp-stack
    _rp-callback-faults _rp-stack
    _rp-generation-and-inflight _rp-stack
    _rp-interleaved-pools _rp-stack
    _rp-publication-rollback _rp-stack
    _rp-capacity _rp-stack
    _rp-teardown _rp-stack
    _rp-fails @ 0= IF
        ." RESOURCE OWNER POOL PASS " _rp-checks @ .
    ELSE
        ." RESOURCE OWNER POOL FAIL " _rp-fails @ . ." / " _rp-checks @ .
    THEN CR ;

_rp-run
'''


def test_resource_owner_pool_contracts(tmp_path: Path) -> None:
    PROFILES[PROFILE_NAME] = Profile(
        roots=("interop/resource-owner-pool.f",),
        resources=(),
        autoexec=AUTOEXEC,
        ready_markers=("RESOURCE OWNER POOL PASS",),
        stable_markers=("RESOURCE OWNER POOL PASS",),
        failure_markers=("RESOURCE OWNER POOL FAIL",),
    )
    image = build_image(PROFILE_NAME, tmp_path / "resource-owner-pool.img")
    assert smoke(
        PROFILE_NAME,
        image,
        cols=100,
        rows=30,
        max_steps=2_000_000_000,
        timeout=45.0,
    )


if __name__ == "__main__":
    import tempfile

    with tempfile.TemporaryDirectory() as directory:
        test_resource_owner_pool_contracts(Path(directory))
