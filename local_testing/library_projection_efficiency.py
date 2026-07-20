#!/usr/bin/env python3
"""Fresh-process cost evidence for the Library projection lifecycle.

The guest measures the public projection-owner and resource-client calls with
the CPU's 64-bit ``PERF-CYCLES`` counter.  A host/guest handshake around every
operation also reports emulator steps and wall time without folding several
short calls into one polling batch.

The acceptance rules are deliberately about bounded work, not speculative
hardware latency: unchanged projection calls may not trigger a full Library
validation, index rebuild, or arena scan, and an exact acquire or snapshot may
read its target frame once.  Successful replacement separately records its
required complete durable publication/readback.  The bound shape additionally
exercises all eight live projection slots plus a ninth refusal and all 64
leases plus a 65th refusal.  Clock divisions printed by this program are
CPU-model interpretations only; the emulator does not model the target's
shared-memory arbitration, external-memory latency, or storage I/O.
"""

from __future__ import annotations

import argparse
import multiprocessing
import os
import sys
import time
import traceback
from dataclasses import dataclass
from multiprocessing.connection import Connection
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO / "local_testing"))

from akashic_tui import (  # noqa: E402
    FTYPE_FORTH,
    MEGAPAD_ROOT,
    MP64FS,
    PROFILES,
    MachineSession,
    Profile,
    build_image,
)


PROFILE_NAME = "_library-projection-efficiency"
SETUP_DONE = "LPE SETUP PASS"
PROFILE_DONE = "LPE PROFILE PASS"
FAILURES = (
    "LPE FAIL",
    " ? (not found)",
    "dictionary full",
    "EVALUATE depth limit exceeded",
    "exception",
)


@dataclass(frozen=True)
class Shape:
    name: str
    documents: int
    body_bytes: int
    exercise_bounds: bool = False

    @property
    def generation(self) -> int:
        return 1 + self.documents


SHAPES = {
    "representative": Shape("representative", 1, 128),
    "byte-bound": Shape("byte-bound", 1, 65_536),
    # Nine records let the guest hold the architectural eight-owner bound and
    # then qualify a distinct ninth RID before measuring explicit refusal.
    "owner-lease-bound": Shape("owner-lease-bound", 9, 4_096, True),
}

COMMON_OPERATIONS = {
    "cold-store-load",
    "root-init",
    "cold-acquire",
    "describe-first",
    "describe-repeat",
    "snapshot-first",
    "snapshot-repeat",
    "warm-shared-acquire",
    "replace-success",
    "replace-stale-first",
    "replace-stale-repeat",
    "release-shared",
    "release-final",
    "root-fini",
}

BOUND_OPERATIONS = {
    "acquire-owner-bound",
    "acquire-owner-over-capacity",
    "release-owner-bound",
    "acquire-lease-bound",
    "acquire-lease-over-capacity",
    "release-lease-bound",
}

DIRECT_ONCE = {
    "cold-acquire",
    "snapshot-first",
    "snapshot-repeat",
    "warm-shared-acquire",
    "replace-success",
    "replace-stale-first",
    "replace-stale-repeat",
}

NO_AUTHORITY_REBUILD = COMMON_OPERATIONS - {
    "cold-store-load",
    "replace-success",
}


def setup_source(shape: Shape) -> str:
    """Build a deterministic durable corpus without profiling setup writes."""
    return rf'''\ deterministic MP64FS projection-efficiency corpus
ENTER-USERLAND
REQUIRE library/vfs-store.f
REQUIRE utils/fs/drivers/vfs-mp64fs.f

{shape.documents} CONSTANT _lpe-document-count
{shape.body_bytes} CONSTANT _lpe-body-bytes

VARIABLE _lpe-vfs
VARIABLE _lpe-fails
VARIABLE _lpe-index
CREATE _lpe-bd /BLOCK-DEVICE ALLOT
CREATE _lpe-volume /VOLUME ALLOT
CREATE _lpe-arena-id LIB-DIGEST-SIZE ALLOT
CREATE _lpe-key LIB-OPERATION-KEY-SIZE ALLOT
CREATE _lpe-request LIBRARY-MANAGED-CREATE-REQUEST-SIZE ALLOT
CREATE _lpe-entry LIB-ENTRY-SIZE ALLOT
CREATE _lpe-store LIBRARY-VFS-STORE-SIZE ALLOT
{shape.body_bytes} XBUF _lpe-body

: _lpe-assert  ( flag -- )
    0= IF
        1 _lpe-fails +!
        ." LPE FAIL setup-assertion=" _lpe-fails @ . CR
    THEN ;

: _lpe-body!  ( -- )
    _lpe-body _lpe-body-bytes [CHAR] x FILL
    S" projection-profile" DROP _lpe-body
        _lpe-body-bytes 18 MIN MOVE ;

: _lpe-key!  ( value -- )
    _lpe-key LIB-OPERATION-KEY-SIZE 0 FILL _lpe-key ! ;

: _lpe-create-one  ( index -- )
    _lpe-index !
    _lpe-request LIBRARY-MANAGED-CREATE-REQUEST-INIT
    _lpe-index @ 1+ _lpe-request
        LIBMCR.EXPECTED-CATALOG-GENERATION !
    _lpe-index @ 1+ _lpe-key!
    _lpe-key _lpe-request LIBRARY-MANAGED-CREATE-OPERATION-KEY!
        LIBSTORE-S-OK = _lpe-assert
    S" Projection efficiency" _lpe-request
        LIBRARY-MANAGED-CREATE-TITLE! LIBSTORE-S-OK = _lpe-assert
    _lpe-body _lpe-body-bytes _lpe-request
        LIBRARY-MANAGED-CREATE-CONTENT! LIBSTORE-S-OK = _lpe-assert
    LIB-MEDIA-TEXT-PLAIN _lpe-request LIBMCR.MEDIA !
    _lpe-request LIBRARY-MANAGED-CREATE-REQUEST-VALID? _lpe-assert
    _lpe-request _lpe-entry _lpe-store
        LIBRARY-VFS-STORE-CREATE-MANAGED
        LIBSTORE-S-OK = _lpe-assert
    _lpe-entry LIB-ENTRY-VALID? _lpe-assert ;

: _lpe-setup  ( -- )
    0 _lpe-fails !
    _lpe-arena-id LIB-DIGEST-SIZE 0xC7 FILL
    _lpe-body!
    _lpe-bd BD-OPEN THROW
    _lpe-bd _lpe-volume VOL-RAW THROW
    4194304 A-XMEM ARENA-NEW IF -7761 THROW THEN
    _lpe-volume VMP-NEW ?DUP IF THROW THEN
    DUP _lpe-vfs ! DUP 0= IF -7762 THROW THEN VFS-USE
    _lpe-vfs @ _lpe-store LIBRARY-VFS-STORE-INIT
        LIBSTORE-S-OK = _lpe-assert
    _lpe-store LIBRARY-VFS-STORE-LOAD
        LIBSTORE-S-ABSENT = _lpe-assert
    _lpe-arena-id _lpe-store LIBRARY-VFS-STORE-PROVISION
        LIBSTORE-S-OK = _lpe-assert
    _lpe-document-count 0 ?DO I _lpe-create-one LOOP
    _lpe-vfs @ VFS-SYNC 0= _lpe-assert
    _lpe-store LIBRARY-VFS-STORE.GENERATION @
        {shape.generation} = _lpe-assert
    _lpe-fails @ IF
        ." LPE FAIL setup-total=" _lpe-fails @ . CR
    ELSE
        ." LPE SETUP PASS docs=" _lpe-document-count .
        ."  body=" _lpe-body-bytes .
        ."  generation=" _lpe-store LIBRARY-VFS-STORE.GENERATION @ . CR
    THEN ;

_lpe-setup
'''


def profile_source(shape: Shape) -> str:
    """Return the fresh-activation profiling program for one corpus shape."""
    bounds_flag = -1 if shape.exercise_bounds else 0
    return rf'''\ fresh-process Library projection-efficiency profile
ENTER-USERLAND
\ Loading the resource client first keeps linked EVALUATE nesting shallow.
REQUIRE interop/resource-client.f
REQUIRE library/projection-owner.f
REQUIRE utils/fs/drivers/vfs-mp64fs.f

{shape.documents} CONSTANT _lpe-document-count
{shape.body_bytes} CONSTANT _lpe-body-bytes
{shape.generation} CONSTANT _lpe-expected-generation
{bounds_flag} CONSTANT _lpe-exercise-bounds

VARIABLE _lpe-fails
VARIABLE _lpe-checks
VARIABLE _lpe-vfs
VARIABLE _lpe-context
VARIABLE _lpe-creg
VARIABLE _lpe-rreg
VARIABLE _lpe-bus
VARIABLE _lpe-request
VARIABLE _lpe-status
VARIABLE _lpe-expected-status
VARIABLE _lpe-count
VARIABLE _lpe-next
VARIABLE _lpe-generation
VARIABLE _lpe-cycles
VARIABLE _lpe-stalls
VARIABLE _lpe-extmem
VARIABLE _lpe-label-a
VARIABLE _lpe-label-u
VARIABLE _lpe-op-xt
VARIABLE _lpe-locator-index
VARIABLE _lpe-lease-index
VARIABLE _lpe-batch-status

CREATE _lpe-bd /BLOCK-DEVICE ALLOT
CREATE _lpe-volume /VOLUME ALLOT
CREATE _lpe-store LIBRARY-VFS-STORE-SIZE ALLOT
CREATE _lpe-head PHEAD-SIZE ALLOT
CREATE _lpe-root LIBRARY-PROJECTION-ROOT-SIZE ALLOT
CREATE _lpe-ref RREF-SIZE ALLOT
CREATE _lpe-summaries
    LIBRARY-PROJECTION-OWNER-MAX 1+ LIBRARY-QUERY-SUMMARY-SIZE * ALLOT
CREATE _lpe-locators
    LIBRARY-PROJECTION-OWNER-MAX 1+ QLOC-SIZE * ALLOT
CREATE _lpe-bindings
    LIBRARY-PROJECTION-LEASE-MAX 1+ LBIND-SIZE * ALLOT
CREATE _lpe-results
    LIBRARY-PROJECTION-LEASE-MAX 1+ RACQ-RESULT-SIZE * ALLOT
CREATE _lpe-client RCLI-SIZE ALLOT
CREATE _lpe-replace-locator QLOC-SIZE ALLOT
CREATE _lpe-replacement-digest LIB-DIGEST-SIZE ALLOT
{shape.body_bytes} XBUF _lpe-replacement

: _lpe-summary  ( index -- summary )
    LIBRARY-QUERY-SUMMARY-SIZE * _lpe-summaries + ;

: _lpe-locator  ( index -- locator ) QLOC-SIZE * _lpe-locators + ;
: _lpe-binding  ( index -- binding ) LBIND-SIZE * _lpe-bindings + ;
: _lpe-result  ( index -- result ) RACQ-RESULT-SIZE * _lpe-results + ;

: _lpe-assert  ( flag -- )
    1 _lpe-checks +!
    0= IF
        1 _lpe-fails +!
        ." LPE FAIL assertion=" _lpe-checks @ . CR
    THEN ;

: _lpe-start  ( -- ) _LIBPQ-RESET PERF-RESET ;

: _lpe-stop  ( -- )
    PERF-CYCLES _lpe-cycles !
    PERF-STALLS _lpe-stalls !
    PERF-EXTMEM _lpe-extmem ! ;

: _lpe-rid-zero  ( -- rid )
    0 _lpe-locator QLOC.REF RREF.ID ;

: _lpe-report  ( -- )
    ." LPE RESULT " _lpe-label-a @ _lpe-label-u @ TYPE
    ."  cycles=" _lpe-cycles @ .
    ."  stalls=" _lpe-stalls @ .
    ."  extmem=" _lpe-extmem @ .
    ."  status=" _lpe-status @ .
    ."  expected-status=" _lpe-expected-status @ .
    ."  live=" _lpe-root LIBRARY-PROJECTION-ROOT-LIVE@ .
    ."  leases=" _lpe-root LIBRARY-PROJECTION-ROOT-LEASES@ .
    ."  refs=" _lpe-rid-zero _lpe-root
        LIBRARY-PROJECTION-ROOT-REFS@ .
    ."  acquire-calls=" _lpe-root
        LIBRARY-PROJECTION-ROOT-ACQUIRE-CALLS@ .
    ."  release-calls=" _lpe-root
        LIBRARY-PROJECTION-ROOT-RELEASE-CALLS@ .
    ."  quiescent-calls=" _lpe-root
        LIBRARY-PROJECTION-ROOT-QUIESCENT-CALLS@ .
    ."  full=" _LIBPQ-FULL-VALIDATION@ .
    ."  warm=" _LIBPQ-WARM-ASSURANCE@ .
    ."  index=" _LIBPQ-INDEX-REBUILD@ .
    ."  entry=" _LIBPQ-ENTRY-READ@ .
    ."  direct=" _LIBPQ-DIRECT-FRAME-READ@ .
    ."  direct-bytes=" _LIBPQ-DIRECT-FRAME-BYTES@ .
    ."  scans=" _LIBPQ-ARENA-SCAN@ .
    ."  scan-frames=" _LIBPQ-ARENA-SCAN-FRAME@ .
    ."  scan-bytes=" _LIBPQ-ARENA-SCAN-BYTES@ . CR ;

: _lpe-gate  ( -- )
    ." LPE MEASURE " _lpe-label-a @ _lpe-label-u @ TYPE CR KEY DROP ;

: _lpe-measure  ( expected-status xt label-a label-u -- )
    _lpe-label-u ! _lpe-label-a ! _lpe-op-xt ! _lpe-expected-status !
    _lpe-gate
    _lpe-start _lpe-op-xt @ EXECUTE _lpe-status ! _lpe-stop
    _lpe-status @ _lpe-expected-status @ = _lpe-assert
    _lpe-report ;

: _lpe-no-rebuild  ( -- )
    _LIBPQ-FULL-VALIDATION@ 0= _lpe-assert
    _LIBPQ-INDEX-REBUILD@ 0= _lpe-assert
    _LIBPQ-ARENA-SCAN@ 0= _lpe-assert ;

: _lpe-no-store-read  ( -- )
    _lpe-no-rebuild
    _LIBPQ-ENTRY-READ@ 0= _lpe-assert
    _LIBPQ-DIRECT-FRAME-READ@ 0= _lpe-assert ;

: _lpe-one-direct-frame  ( -- )
    _lpe-no-rebuild
    _LIBPQ-DIRECT-FRAME-READ@ 1 = _lpe-assert
    _LIBPQ-DIRECT-FRAME-BYTES@
        _lpe-body-bytes LIB-CONTENT-RECORD-SIZE
        LIB-CONTENT-FRAME-SIZE = _lpe-assert ;

: _lpe-discover  ( -- )
    0 0 _lpe-summaries _lpe-document-count _lpe-store
        LIBRARY-VFS-STORE-QUERY-ACTIVE
    _lpe-status ! _lpe-generation ! _lpe-next ! _lpe-count !
    _lpe-status @ LIBSTORE-S-OK = _lpe-assert
    _lpe-count @ _lpe-document-count = _lpe-assert
    _lpe-generation @ _lpe-expected-generation = _lpe-assert
    _lpe-next @ -1 = _lpe-assert
    _lpe-document-count 0 ?DO
        _lpe-ref RREF-INIT
        I _lpe-summary LIBQS.REF RREF.ID
            _lpe-ref RREF.ID RID-COPY
        LIBRARY-PROJECTION-OWNER$ _lpe-ref
            I _lpe-summary LIBQS.DOMAIN-REVISION @
            I _lpe-summary LIBQS.CONTENT-DIGEST
            QLOC-DK-PROJECTION-CONTENT
            LIBRARY-PROJECTION-CONTRACT$
            I _lpe-locator QLOC-EXACT!
            QLOC-S-OK = _lpe-assert
        I _lpe-locator QLOC-VALID? _lpe-assert
    LOOP ;

: _lpe-runtime-objects  ( -- )
    _lpe-head PHEAD-INIT
    _lpe-head PHEAD.ID LIB-DIGEST-SIZE 0x61 FILL
    _lpe-head PHEAD.CURRENT-ROOT LIB-DIGEST-SIZE 0x62 FILL
    601 CTX-NEW DUP 0= _lpe-assert DROP _lpe-context !
    _lpe-head _lpe-context @ CTX.PRACTICE !
    CTX-F-ACTIVE _lpe-context @ CTX.FLAGS !
    CREG-NEW DUP 0= _lpe-assert DROP _lpe-creg !
    _lpe-creg @ _lpe-context @ RREG-NEW
        DUP 0= _lpe-assert DROP _lpe-rreg !
    _lpe-creg @ 0 CBUS-NEW DUP 0= _lpe-assert DROP _lpe-bus !
    _lpe-bus @ _lpe-context @ CTX.QUEUE !
    CBR-NEW DUP 0= _lpe-assert DROP _lpe-request ! ;

: _lpe-attach-i  ( locator-index lease-index -- status )
    _lpe-lease-index ! _lpe-locator-index !
    _lpe-locator-index @ _lpe-locator _lpe-root
    _lpe-context @ _lpe-rreg @
    _lpe-lease-index @ _lpe-binding
    _lpe-lease-index @ _lpe-result LIBRARY-PROJECTION-ATTACH ;

: _lpe-detach-i  ( lease-index -- status )
    DUP _lpe-binding SWAP _lpe-result RACQ-DETACH ;

: _lpe-op-load  ( -- status )
    _lpe-store LIBRARY-VFS-STORE-LOAD ;

: _lpe-op-root-init  ( -- status )
    _lpe-store _lpe-context @ _lpe-creg @ _lpe-rreg @ _lpe-bus @
        _lpe-root LIBRARY-PROJECTION-ROOT-INIT ;

: _lpe-op-cold-acquire  ( -- status ) 0 0 _lpe-attach-i ;
: _lpe-op-shared-acquire  ( -- status ) 0 1 _lpe-attach-i ;

: _lpe-op-describe  ( -- status )
    CPRINC-USER _lpe-request @ _lpe-client RCLI-DESCRIBE ;

: _lpe-op-snapshot  ( -- status )
    0 _lpe-locator CPRINC-USER _lpe-request @ _lpe-client
        RCLI-SNAPSHOT-CALL ;

: _lpe-op-replace  ( -- status )
    _lpe-replace-locator _lpe-replacement _lpe-body-bytes
        _lpe-replacement-digest CPRINC-USER _lpe-request @ _lpe-client
        RCLI-REPLACE-CALL ;

: _lpe-op-release-shared  ( -- status ) 1 _lpe-detach-i ;
: _lpe-op-release-final  ( -- status ) _lpe-client RCLI-FINI ;
: _lpe-op-root-fini  ( -- status )
    _lpe-root LIBRARY-PROJECTION-ROOT-FINI ;

: _lpe-op-acquire-owner-bound  ( -- status )
    RACQ-S-OK _lpe-batch-status !
    LIBRARY-PROJECTION-OWNER-MAX 0 ?DO
        I I _lpe-attach-i DUP IF
            _lpe-batch-status ! LEAVE
        THEN DROP
    LOOP
    _lpe-batch-status @ ;

: _lpe-op-acquire-owner-over  ( -- status )
    LIBRARY-PROJECTION-OWNER-MAX DUP _lpe-attach-i ;

: _lpe-op-release-owner-bound  ( -- status )
    RACQ-S-OK _lpe-batch-status !
    LIBRARY-PROJECTION-OWNER-MAX 0 ?DO
        LIBRARY-PROJECTION-OWNER-MAX 1- I - _lpe-detach-i DUP IF
            _lpe-batch-status ! LEAVE
        THEN DROP
    LOOP
    _lpe-batch-status @ ;

: _lpe-op-acquire-lease-bound  ( -- status )
    RACQ-S-OK _lpe-batch-status !
    LIBRARY-PROJECTION-LEASE-MAX 0 ?DO
        0 I _lpe-attach-i DUP IF
            _lpe-batch-status ! LEAVE
        THEN DROP
    LOOP
    _lpe-batch-status @ ;

: _lpe-op-acquire-lease-over  ( -- status )
    0 LIBRARY-PROJECTION-LEASE-MAX _lpe-attach-i ;

: _lpe-op-release-lease-bound  ( -- status )
    RACQ-S-OK _lpe-batch-status !
    LIBRARY-PROJECTION-LEASE-MAX 0 ?DO
        LIBRARY-PROJECTION-LEASE-MAX 1- I - _lpe-detach-i DUP IF
            _lpe-batch-status ! LEAVE
        THEN DROP
    LOOP
    _lpe-batch-status @ ;

: _lpe-check-describe  ( -- )
    _lpe-request @ CBR.RESULT RCON-DESCRIBE-RESULT? _lpe-assert
    S" size" _lpe-request @ CBR.RESULT CV-MAP-FIND
        DUP 0<> _lpe-assert
    ?DUP IF CV-DATA@ _lpe-body-bytes = _lpe-assert THEN ;

: _lpe-check-snapshot  ( -- )
    0 _lpe-locator _lpe-request @ CBR.RESULT
        RCON-SNAPSHOT-RESULT? _lpe-assert
    S" content" _lpe-request @ CBR.RESULT CV-MAP-FIND
        DUP 0<> _lpe-assert
    ?DUP IF CV-LEN@ _lpe-body-bytes = _lpe-assert THEN
    S" content_digest" _lpe-request @ CBR.RESULT CV-MAP-FIND
        DUP 0<> _lpe-assert
    ?DUP IF
        DUP CV-LEN@ LIB-DIGEST-SIZE = _lpe-assert
        CV-DATA@ 0 _lpe-locator QLOC.STATE-DIGEST
            SHA3-256-COMPARE _lpe-assert
    THEN ;

: _lpe-check-replace  ( -- )
    _lpe-replace-locator _lpe-replacement-digest
        _lpe-request @ CBR.RESULT RCON-REPLACE-RESULT? _lpe-assert
    S" domain_revision" _lpe-request @ CBR.RESULT CV-MAP-FIND
        DUP 0<> _lpe-assert
    ?DUP IF CV-DATA@ 2 = _lpe-assert THEN
    _lpe-ref RREF-INIT
    _lpe-rid-zero _lpe-ref RREF.ID RID-COPY
    LIBRARY-PROJECTION-OWNER$ _lpe-ref
        S" domain_revision" _lpe-request @ CBR.RESULT
            CV-MAP-FIND CV-DATA@
        S" state_digest" _lpe-request @ CBR.RESULT CV-MAP-FIND CV-DATA@
        QLOC-DK-PROJECTION-CONTENT LIBRARY-PROJECTION-CONTRACT$
        0 _lpe-locator QLOC-EXACT! QLOC-S-OK = _lpe-assert
    0 _lpe-locator QLOC-VALID? _lpe-assert
    _lpe-store LIBRARY-VFS-STORE.GENERATION @
        _lpe-expected-generation 1+ = _lpe-assert
    _lpe-client RCLI.BIND LBIND.REVISION @ 2 = _lpe-assert ;

: _lpe-base-profile  ( -- )
    LIBSTORE-S-OK ['] _lpe-op-load S" cold-store-load" _lpe-measure
    _LIBPQ-FULL-VALIDATION@ 1 = _lpe-assert
    _LIBPQ-INDEX-REBUILD@ 1 = _lpe-assert
    _lpe-store LIBRARY-VFS-STORE.GENERATION @
        _lpe-expected-generation = _lpe-assert

    _lpe-discover
    _lpe-runtime-objects

    RACQ-S-OK ['] _lpe-op-root-init S" root-init" _lpe-measure
    _lpe-no-store-read
    _lpe-root LIBRARY-PROJECTION-ROOT-VALID? _lpe-assert
    _lpe-root LIBRARY-PROJECTION-ROOT-LIVE@ 0= _lpe-assert

    RACQ-S-OK ['] _lpe-op-cold-acquire S" cold-acquire" _lpe-measure
    _lpe-one-direct-frame
    _lpe-root LIBRARY-PROJECTION-ROOT-LIVE@ 1 = _lpe-assert
    _lpe-root LIBRARY-PROJECTION-ROOT-LEASES@ 1 = _lpe-assert
    _lpe-rid-zero _lpe-root LIBRARY-PROJECTION-ROOT-REFS@
        1 = _lpe-assert

    0 _lpe-result 0 _lpe-binding _lpe-context @ _lpe-bus @
        _lpe-client RCLI-INIT CBUS-S-OK = _lpe-assert
    _lpe-client RCLI-VALID? _lpe-assert
    0 _lpe-locator _lpe-replace-locator QLOC-SIZE MOVE
    _lpe-replacement _lpe-body-bytes [CHAR] y FILL
    S" projection-replacement" DROP _lpe-replacement
        _lpe-body-bytes 22 MIN MOVE
    _lpe-replacement _lpe-body-bytes _lpe-replacement-digest
        SHA3-256-HASH

    CBUS-S-OK ['] _lpe-op-describe S" describe-first" _lpe-measure
    _lpe-no-rebuild
    _LIBPQ-DIRECT-FRAME-READ@ 0= _lpe-assert
    _lpe-check-describe

    CBUS-S-OK ['] _lpe-op-describe S" describe-repeat" _lpe-measure
    _lpe-no-rebuild
    _LIBPQ-DIRECT-FRAME-READ@ 0= _lpe-assert
    _lpe-check-describe

    CBUS-S-OK ['] _lpe-op-snapshot S" snapshot-first" _lpe-measure
    _lpe-one-direct-frame
    _lpe-check-snapshot

    CBUS-S-OK ['] _lpe-op-snapshot S" snapshot-repeat" _lpe-measure
    _lpe-one-direct-frame
    _lpe-check-snapshot

    RACQ-S-OK ['] _lpe-op-shared-acquire
        S" warm-shared-acquire" _lpe-measure
    _lpe-one-direct-frame
    _lpe-root LIBRARY-PROJECTION-ROOT-LIVE@ 1 = _lpe-assert
    _lpe-root LIBRARY-PROJECTION-ROOT-LEASES@ 2 = _lpe-assert
    _lpe-rid-zero _lpe-root LIBRARY-PROJECTION-ROOT-REFS@
        2 = _lpe-assert

    CBUS-S-OK ['] _lpe-op-replace S" replace-success" _lpe-measure
    _LIBPQ-FULL-VALIDATION@ 2 = _lpe-assert
    _LIBPQ-INDEX-REBUILD@ 2 = _lpe-assert
    _LIBPQ-ARENA-SCAN@ 0= _lpe-assert
    _LIBPQ-DIRECT-FRAME-READ@ 1 = _lpe-assert
    _LIBPQ-DIRECT-FRAME-BYTES@
        _lpe-body-bytes LIB-CONTENT-RECORD-SIZE
        LIB-CONTENT-FRAME-SIZE = _lpe-assert
    _lpe-check-replace

    CBUS-S-STALE-REVISION ['] _lpe-op-replace
        S" replace-stale-first" _lpe-measure
    _lpe-one-direct-frame

    CBUS-S-STALE-REVISION ['] _lpe-op-replace
        S" replace-stale-repeat" _lpe-measure
    _lpe-one-direct-frame
    _lpe-store LIBRARY-VFS-STORE.GENERATION @
        _lpe-expected-generation 1+ = _lpe-assert

    RACQ-S-OK ['] _lpe-op-release-shared
        S" release-shared" _lpe-measure
    _lpe-no-store-read
    _lpe-root LIBRARY-PROJECTION-ROOT-LIVE@ 1 = _lpe-assert
    _lpe-root LIBRARY-PROJECTION-ROOT-LEASES@ 1 = _lpe-assert

    RACQ-S-OK ['] _lpe-op-release-final S" release-final" _lpe-measure
    _lpe-no-store-read
    _lpe-root LIBRARY-PROJECTION-ROOT-LIVE@ 0= _lpe-assert
    _lpe-root LIBRARY-PROJECTION-ROOT-LEASES@ 0= _lpe-assert
    _lpe-client RCLI-VALID? 0= _lpe-assert ;

: _lpe-bound-profile  ( -- )
    _lpe-exercise-bounds 0= IF EXIT THEN
    RACQ-S-OK ['] _lpe-op-acquire-owner-bound
        S" acquire-owner-bound" _lpe-measure
    _lpe-no-rebuild
    _LIBPQ-DIRECT-FRAME-READ@
        LIBRARY-PROJECTION-OWNER-MAX = _lpe-assert
    _lpe-root LIBRARY-PROJECTION-ROOT-LIVE@
        LIBRARY-PROJECTION-OWNER-MAX = _lpe-assert
    _lpe-root LIBRARY-PROJECTION-ROOT-LEASES@
        LIBRARY-PROJECTION-OWNER-MAX = _lpe-assert

    RACQ-S-CAPACITY ['] _lpe-op-acquire-owner-over
        S" acquire-owner-over-capacity" _lpe-measure
    _lpe-one-direct-frame
    _lpe-root LIBRARY-PROJECTION-ROOT-LIVE@
        LIBRARY-PROJECTION-OWNER-MAX = _lpe-assert
    _lpe-root LIBRARY-PROJECTION-ROOT-LEASES@
        LIBRARY-PROJECTION-OWNER-MAX = _lpe-assert

    RACQ-S-OK ['] _lpe-op-release-owner-bound
        S" release-owner-bound" _lpe-measure
    _lpe-no-store-read
    _lpe-root LIBRARY-PROJECTION-ROOT-LIVE@ 0= _lpe-assert
    _lpe-root LIBRARY-PROJECTION-ROOT-LEASES@ 0= _lpe-assert

    RACQ-S-OK ['] _lpe-op-acquire-lease-bound
        S" acquire-lease-bound" _lpe-measure
    _lpe-no-rebuild
    _LIBPQ-DIRECT-FRAME-READ@
        LIBRARY-PROJECTION-LEASE-MAX = _lpe-assert
    _lpe-root LIBRARY-PROJECTION-ROOT-LIVE@ 1 = _lpe-assert
    _lpe-root LIBRARY-PROJECTION-ROOT-LEASES@
        LIBRARY-PROJECTION-LEASE-MAX = _lpe-assert
    _lpe-rid-zero _lpe-root LIBRARY-PROJECTION-ROOT-REFS@
        LIBRARY-PROJECTION-LEASE-MAX = _lpe-assert

    RACQ-S-CAPACITY ['] _lpe-op-acquire-lease-over
        S" acquire-lease-over-capacity" _lpe-measure
    _lpe-one-direct-frame
    _lpe-root LIBRARY-PROJECTION-ROOT-LIVE@ 1 = _lpe-assert
    _lpe-root LIBRARY-PROJECTION-ROOT-LEASES@
        LIBRARY-PROJECTION-LEASE-MAX = _lpe-assert

    RACQ-S-OK ['] _lpe-op-release-lease-bound
        S" release-lease-bound" _lpe-measure
    _lpe-no-store-read
    _lpe-root LIBRARY-PROJECTION-ROOT-LIVE@ 0= _lpe-assert
    _lpe-root LIBRARY-PROJECTION-ROOT-LEASES@ 0= _lpe-assert ;

: _lpe-teardown  ( -- )
    RACQ-S-OK ['] _lpe-op-root-fini S" root-fini" _lpe-measure
    _lpe-no-store-read
    _lpe-root LIBRARY-PROJECTION-ROOT-VALID? 0= _lpe-assert
    _lpe-request @ CBR-FREE
    _lpe-bus @ CBUS-FREE
    _lpe-rreg @ RREG-FREE
    _lpe-creg @ CREG-FREE
    _lpe-context @ CTX-FREE
    _lpe-store LIBRARY-VFS-STORE-FINI
        LIBSTORE-S-OK = _lpe-assert ;

: _lpe-run  ( -- )
    0 _lpe-fails ! 0 _lpe-checks !
    _lpe-bd BD-OPEN THROW
    _lpe-bd _lpe-volume VOL-RAW THROW
    4194304 A-XMEM ARENA-NEW IF -7763 THROW THEN
    _lpe-volume VMP-NEW ?DUP IF THROW THEN
    DUP _lpe-vfs ! DUP 0= IF -7764 THROW THEN VFS-USE
    _lpe-vfs @ _lpe-store LIBRARY-VFS-STORE-INIT
        LIBSTORE-S-OK = _lpe-assert
    ." LPE MEMORY root-bytes=" LIBRARY-PROJECTION-ROOT-SIZE .
    ."  per-live-owner-bytes="
        COMP-INST LIBRARY-PROJECTION-STATE-SIZE + .
    ."  max-live-dynamic-bytes="
        COMP-INST LIBRARY-PROJECTION-STATE-SIZE +
        LIBRARY-PROJECTION-OWNER-MAX * .
    ."  owner-max=" LIBRARY-PROJECTION-OWNER-MAX .
    ."  lease-max=" LIBRARY-PROJECTION-LEASE-MAX .
    ."  projection-index-rebuild-bytes=0" CR
    _lpe-base-profile
    _lpe-bound-profile
    _lpe-teardown
    _lpe-fails @ IF
        ." LPE FAIL total=" _lpe-fails @ .
        ."  checks=" _lpe-checks @ . CR
    ELSE
        ." LPE PROFILE PASS checks=" _lpe-checks @ . CR
    THEN ;

_lpe-run
'''


def replace_autoexec(image: Path, source: str) -> None:
    fs = MP64FS(bytearray(image.read_bytes()))
    if fs.find_file("autoexec.f") is not None:
        fs.delete_file("autoexec.f")
    fs.inject_file("autoexec.f", source.encode("utf-8"), ftype=FTYPE_FORTH)
    fs.save(image)


def run_image(
    image: Path,
    marker: str,
    timeout: float,
    gate_prefix: str | None = None,
) -> tuple[bytes, str, int, float, list[tuple[str, int, float]]]:
    start = time.perf_counter()
    total_steps = 0
    events: list[tuple[str, int, float]] = []
    seen_gates: set[str] = set()
    active_label: str | None = None
    active_steps = 0
    active_wall = 0.0
    with MachineSession.from_bios(
        MEGAPAD_ROOT / "bios.asm",
        storage_image=image,
        cols=120,
        rows=44,
        batch_steps=250_000,
    ) as session:
        session.boot()
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline and total_steps < 40_000_000_000:
            result_marker = (
                f"LPE RESULT {active_label} "
                if active_label is not None
                else None
            )
            report = session.run(
                max_steps=2_000_000,
                wall_timeout_s=min(
                    0.5, max(0.05, deadline - time.monotonic())
                ),
                until_text=result_marker,
                advance_idle=True,
            )
            total_steps += report.steps
            raw = session.raw_text()
            failure = next((item for item in FAILURES if item in raw), None)
            if failure is not None:
                raise RuntimeError(f"guest reported {failure!r}\n{raw[-8000:]}")
            now = time.perf_counter()
            lines = raw.splitlines()
            if active_label is not None and any(
                line.startswith(f"LPE RESULT {active_label} ")
                for line in lines
            ):
                events.append(
                    (
                        active_label,
                        total_steps - active_steps,
                        now - active_wall,
                    )
                )
                active_label = None
            if gate_prefix is not None and active_label is None:
                gate_line = next(
                    (
                        line
                        for line in lines
                        if line.startswith(gate_prefix)
                        and line not in seen_gates
                    ),
                    None,
                )
                if gate_line is not None:
                    seen_gates.add(gate_line)
                    active_label = gate_line[len(gate_prefix) :].strip()
                    active_steps = total_steps
                    active_wall = now
                    session.send_text(" ")
            if marker in raw and active_label is None:
                return (
                    bytes(session.system.storage._image_data),
                    raw,
                    total_steps,
                    time.perf_counter() - start,
                    events,
                )
            if report.reason in ("halted", "stalled"):
                break
        raise RuntimeError(
            f"timed out waiting for {marker!r}\n{session.raw_text()[-8000:]}"
        )


def _worker(
    image: str,
    marker: str,
    timeout: float,
    gate_prefix: str | None,
    sender: Connection,
) -> None:
    """Run exactly one machine in a spawn-isolated host process."""
    try:
        sender.send(
            ("ok", *run_image(Path(image), marker, timeout, gate_prefix))
        )
    except BaseException:  # Preserve child evidence for the CLI caller.
        sender.send(("error", traceback.format_exc()))
    finally:
        sender.close()


def run_in_fresh_process(
    image: Path,
    marker: str,
    timeout: float,
    gate_prefix: str | None = None,
) -> tuple[bytes, str, int, float, list[tuple[str, int, float]]]:
    context = multiprocessing.get_context("spawn")
    receiver, sender = context.Pipe(duplex=False)
    process = context.Process(
        target=_worker,
        args=(str(image), marker, timeout, gate_prefix, sender),
        name=f"akashic-lpe-{marker.lower().replace(' ', '-')}",
    )
    process.start()
    sender.close()
    deadline = time.monotonic() + timeout + 60.0
    payload: tuple[object, ...] | None = None
    try:
        while time.monotonic() < deadline:
            if receiver.poll(0.2):
                payload = receiver.recv()
                break
            if not process.is_alive():
                if receiver.poll():
                    payload = receiver.recv()
                break
    finally:
        receiver.close()
        if process.is_alive() and payload is None:
            process.terminate()
        process.join(timeout=10.0)
        if process.is_alive():
            process.kill()
            process.join()

    if payload is None:
        raise RuntimeError(
            "profiling worker exited without evidence "
            f"(exit {process.exitcode})"
        )
    if payload[0] == "error":
        raise RuntimeError(str(payload[1]))
    if payload[0] != "ok" or len(payload) != 6:
        raise RuntimeError(f"invalid profiling worker result: {payload[0]!r}")
    disk, output, steps, wall, events = payload[1:]
    if (
        not isinstance(disk, bytes)
        or not isinstance(output, str)
        or not isinstance(steps, int)
        or not isinstance(wall, float)
        or not isinstance(events, list)
    ):
        raise RuntimeError("profiling worker returned malformed evidence")
    if process.exitcode != 0:
        raise RuntimeError(
            f"profiling worker exited with status {process.exitcode}"
        )
    return disk, output, steps, wall, events


def parse_results(output: str) -> dict[str, dict[str, int]]:
    results: dict[str, dict[str, int]] = {}
    for line in output.splitlines():
        if not line.startswith("LPE RESULT "):
            continue
        words = line.split()
        label = words[2]
        if label in results:
            raise RuntimeError(f"duplicate guest result {label!r}")
        fields: dict[str, int] = {}
        for word in words[3:]:
            key, separator, value = word.partition("=")
            if not separator:
                raise RuntimeError(f"malformed guest result field {word!r}")
            fields[key] = int(value)
        required = {
            "cycles",
            "stalls",
            "status",
            "expected-status",
            "live",
            "leases",
            "full",
            "index",
            "direct",
            "scans",
        }
        missing = required - fields.keys()
        if missing:
            raise RuntimeError(
                f"guest result {label!r} lacks fields {sorted(missing)}"
            )
        results[label] = fields
    return results


def _require_equal(
    shape: Shape,
    operation: str,
    field: str,
    actual: int,
    expected: int,
) -> None:
    if actual != expected:
        raise RuntimeError(
            f"{shape.name}/{operation} reported {field}={actual}; "
            f"expected {expected}"
        )


def qualify_results(shape: Shape, results: dict[str, dict[str, int]]) -> None:
    required = set(COMMON_OPERATIONS)
    if shape.exercise_bounds:
        required.update(BOUND_OPERATIONS)
    missing = required - results.keys()
    if missing:
        raise RuntimeError(f"missing guest results: {sorted(missing)}")

    for operation in required:
        fields = results[operation]
        _require_equal(
            shape,
            operation,
            "status",
            fields["status"],
            fields["expected-status"],
        )
        if fields["cycles"] <= 0:
            raise RuntimeError(
                f"{shape.name}/{operation} reported no PERF cycles"
            )
        _require_equal(shape, operation, "stalls", fields["stalls"], 0)

    for operation in NO_AUTHORITY_REBUILD:
        fields = results[operation]
        _require_equal(shape, operation, "full", fields["full"], 0)
        _require_equal(shape, operation, "index", fields["index"], 0)
        _require_equal(shape, operation, "scans", fields["scans"], 0)

    for operation in DIRECT_ONCE:
        _require_equal(
            shape, operation, "direct", results[operation]["direct"], 1
        )

    # A successful mutation deliberately performs the complete durable
    # publication/readback cycle.  The stale repeats below must not do so.
    for field, expected in (("full", 2), ("index", 2), ("scans", 0)):
        _require_equal(
            shape,
            "replace-success",
            field,
            results["replace-success"][field],
            expected,
        )

    # These are same-activation cost-shape guards, not target-latency claims.
    for first, repeat in (
        ("describe-first", "describe-repeat"),
        ("snapshot-first", "snapshot-repeat"),
        ("replace-stale-first", "replace-stale-repeat"),
    ):
        first_cycles = results[first]["cycles"]
        repeat_cycles = results[repeat]["cycles"]
        limit = first_cycles * 2 + 1_000_000
        if repeat_cycles > limit:
            raise RuntimeError(
                f"{shape.name}/{repeat} used {repeat_cycles} cycles; "
                f"unchanged-call 2x guard is {limit}"
            )
        print(
            f"LPE QUALIFY shape={shape.name} operation={repeat} "
            f"cycles={repeat_cycles} first-cycles={first_cycles} "
            f"limit={limit} rule=unchanged-call-at-most-2x result=PASS"
        )

    if shape.exercise_bounds:
        owner_acquire = results["acquire-owner-bound"]
        _require_equal(
            shape, "acquire-owner-bound", "live", owner_acquire["live"], 8
        )
        _require_equal(
            shape,
            "acquire-owner-bound",
            "leases",
            owner_acquire["leases"],
            8,
        )
        _require_equal(
            shape,
            "acquire-owner-bound",
            "direct",
            owner_acquire["direct"],
            8,
        )
        owner_over = results["acquire-owner-over-capacity"]
        _require_equal(
            shape,
            "acquire-owner-over-capacity",
            "live",
            owner_over["live"],
            8,
        )
        _require_equal(
            shape,
            "acquire-owner-over-capacity",
            "leases",
            owner_over["leases"],
            8,
        )
        _require_equal(
            shape,
            "acquire-owner-over-capacity",
            "direct",
            owner_over["direct"],
            1,
        )
        lease_acquire = results["acquire-lease-bound"]
        _require_equal(
            shape, "acquire-lease-bound", "live", lease_acquire["live"], 1
        )
        _require_equal(
            shape,
            "acquire-lease-bound",
            "leases",
            lease_acquire["leases"],
            64,
        )
        _require_equal(
            shape,
            "acquire-lease-bound",
            "direct",
            lease_acquire["direct"],
            64,
        )
        over = results["acquire-lease-over-capacity"]
        _require_equal(
            shape, "acquire-lease-over-capacity", "live", over["live"], 1
        )
        _require_equal(
            shape,
            "acquire-lease-over-capacity",
            "leases",
            over["leases"],
            64,
        )
        _require_equal(
            shape,
            "acquire-lease-over-capacity",
            "direct",
            over["direct"],
            1,
        )
        for operation in BOUND_OPERATIONS:
            fields = results[operation]
            _require_equal(shape, operation, "full", fields["full"], 0)
            _require_equal(shape, operation, "index", fields["index"], 0)
            _require_equal(shape, operation, "scans", fields["scans"], 0)


def print_host_events(
    shape: Shape,
    phase: str,
    steps: int,
    wall: float,
    events: list[tuple[str, int, float]],
) -> None:
    print(
        f"LPE HOST shape={shape.name} phase={phase} "
        f"scope=machine-session-inclusive steps={steps} wall={wall:.6f}"
    )
    for label, event_steps, event_wall in events:
        print(
            f"LPE HOST EVENT shape={shape.name} phase={phase} "
            f"operation={label} steps={event_steps} wall={event_wall:.6f} "
            "sampling-steps=250000"
        )


def print_clock_interpretations(
    shape: Shape, results: dict[str, dict[str, int]]
) -> None:
    print(
        "LPE CLOCK NOTE measured-hardware=false "
        "shared-memory-stalls-modeled=false "
        "external-memory-latency-modeled=false storage-io-modeled=false"
    )
    for operation, fields in results.items():
        cycles = fields["cycles"]
        print(
            f"LPE CLOCK shape={shape.name} operation={operation} "
            f"at-100mhz-seconds={cycles / 100_000_000:.6f} "
            f"at-50mhz-seconds={cycles / 50_000_000:.6f} "
            f"reported-stalls={fields['stalls']}"
        )


def print_cost_model(shape: Shape, results: dict[str, dict[str, int]]) -> None:
    print(
        f"LPE COST shape={shape.name} interaction=root-init "
        "fixed=full-root-and-borrow-validation per-record=0 per-byte=0 "
        f"cycles={results['root-init']['cycles']}"
    )
    print(
        f"LPE COST shape={shape.name} interaction=acquire "
        "fixed=root-and-lease-validation per-record=one-identity "
        f"per-byte=one-exact-frame body-bytes={shape.body_bytes} "
        f"cold-cycles={results['cold-acquire']['cycles']} "
        f"warm-cycles={results['warm-shared-acquire']['cycles']}"
    )
    print(
        f"LPE COST shape={shape.name} interaction=describe "
        "fixed=typed-dispatch per-record=one-identity per-byte=0 "
        f"first-cycles={results['describe-first']['cycles']} "
        f"repeat-cycles={results['describe-repeat']['cycles']}"
    )
    print(
        f"LPE COST shape={shape.name} interaction=snapshot "
        "fixed=typed-dispatch per-record=one-identity "
        f"per-byte=one-exact-frame body-bytes={shape.body_bytes} "
        f"first-cycles={results['snapshot-first']['cycles']} "
        f"repeat-cycles={results['snapshot-repeat']['cycles']}"
    )
    print(
        f"LPE COST shape={shape.name} interaction=replace "
        "fixed=typed-dispatch-and-exact-precondition "
        "per-record=complete-catalog-bank-publication "
        f"per-byte=hash-write-readback body-bytes={shape.body_bytes} "
        f"success-cycles={results['replace-success']['cycles']} "
        f"stale-first-cycles={results['replace-stale-first']['cycles']} "
        f"stale-repeat-cycles={results['replace-stale-repeat']['cycles']} "
        f"success-full-validations={results['replace-success']['full']} "
        f"success-index-rebuilds={results['replace-success']['index']} "
        f"success-fallback-scans={results['replace-success']['scans']}"
    )
    print(
        f"LPE COST shape={shape.name} interaction=release "
        "fixed=bounded-lease-scan per-record=0 per-byte=0 "
        f"shared-cycles={results['release-shared']['cycles']} "
        f"final-cycles={results['release-final']['cycles']}"
    )
    print(
        f"LPE COST shape={shape.name} interaction=root-fini "
        "fixed=empty-ledger-validation-and-root-wipe per-record=0 per-byte=0 "
        f"cycles={results['root-fini']['cycles']}"
    )
    if shape.exercise_bounds:
        print(
            f"LPE SCALE shape={shape.name} dimension=live-owners count=8 "
            f"total-acquire-cycles="
            f"{results['acquire-owner-bound']['cycles']} "
            f"cycles-per-owner="
            f"{results['acquire-owner-bound']['cycles'] / 8:.3f}"
        )
        print(
            f"LPE SCALE shape={shape.name} dimension=live-owners-over "
            f"count=9 refusal-cycles="
            f"{results['acquire-owner-over-capacity']['cycles']} "
            f"status={results['acquire-owner-over-capacity']['status']}"
        )
        print(
            f"LPE SCALE shape={shape.name} dimension=leases count=64 "
            f"total-acquire-cycles="
            f"{results['acquire-lease-bound']['cycles']} "
            f"cycles-per-lease="
            f"{results['acquire-lease-bound']['cycles'] / 64:.3f}"
        )


def print_byte_scaling(
    representative: dict[str, dict[str, int]],
    byte_bound: dict[str, dict[str, int]],
) -> None:
    byte_delta = (
        SHAPES["byte-bound"].body_bytes
        - SHAPES["representative"].body_bytes
    )
    for operation in (
        "cold-acquire",
        "snapshot-repeat",
        "replace-success",
        "replace-stale-repeat",
    ):
        cycle_delta = (
            byte_bound[operation]["cycles"]
            - representative[operation]["cycles"]
        )
        print(
            f"LPE SCALE dimension=content-bytes operation={operation} "
            f"byte-delta={byte_delta} cycle-delta={cycle_delta} "
            f"incremental-cycles-per-byte={cycle_delta / byte_delta:.6f}"
        )


def _profile() -> Profile:
    return Profile(
        roots=(
            "interop/resource-client.f",
            "library/projection-owner.f",
            "utils/fs/drivers/vfs-mp64fs.f",
        ),
        resources=(),
        autoexec="",
        ready_markers=(SETUP_DONE,),
        stable_markers=(SETUP_DONE,),
        failure_markers=FAILURES,
        include_large_sample=False,
        total_sectors=8192,
    )


def run_shape(
    shape: Shape, timeout: float, keep_image: bool
) -> dict[str, dict[str, int]]:
    image = Path(
        f"/tmp/library-projection-efficiency-{shape.name}-{os.getpid()}.img"
    )
    previous = PROFILES.get(PROFILE_NAME)
    profile = _profile()
    PROFILES[PROFILE_NAME] = Profile(
        roots=profile.roots,
        resources=profile.resources,
        autoexec=setup_source(shape),
        ready_markers=profile.ready_markers,
        stable_markers=profile.stable_markers,
        failure_markers=profile.failure_markers,
        include_large_sample=profile.include_large_sample,
        total_sectors=profile.total_sectors,
    )
    try:
        build_image(PROFILE_NAME, image)
    finally:
        if previous is None:
            del PROFILES[PROFILE_NAME]
        else:
            PROFILES[PROFILE_NAME] = previous

    disk, _, steps, wall, events = run_in_fresh_process(
        image, SETUP_DONE, timeout
    )
    image.write_bytes(disk)
    print_host_events(shape, "setup", steps, wall, events)

    replace_autoexec(image, profile_source(shape))
    _, output, steps, wall, events = run_in_fresh_process(
        image, PROFILE_DONE, timeout, "LPE MEASURE "
    )
    print_host_events(shape, "profile", steps, wall, events)
    results = parse_results(output)
    for line in output.splitlines():
        if line.startswith(("LPE MEMORY ", "LPE RESULT ")):
            print(f"{shape.name} {line}")
    qualify_results(shape, results)
    print_cost_model(shape, results)
    print_clock_interpretations(shape, results)
    if not keep_image:
        image.unlink(missing_ok=True)
    return results


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--shape",
        action="append",
        choices=tuple(SHAPES),
        help="shape to run; defaults to all three",
    )
    parser.add_argument("--timeout", type=float, default=600.0)
    parser.add_argument("--keep-images", action="store_true")
    args = parser.parse_args()
    if args.timeout <= 0:
        parser.error("--timeout must be greater than zero")
    names = args.shape or list(SHAPES)
    results_by_shape: dict[str, dict[str, dict[str, int]]] = {}
    for name in names:
        results_by_shape[name] = run_shape(
            SHAPES[name], args.timeout, args.keep_images
        )
    if {"representative", "byte-bound"} <= results_by_shape.keys():
        print_byte_scaling(
            results_by_shape["representative"],
            results_by_shape["byte-bound"],
        )
    return 0


if __name__ == "__main__":
    multiprocessing.freeze_support()
    raise SystemExit(main())
