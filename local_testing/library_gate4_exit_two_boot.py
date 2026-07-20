#!/usr/bin/env python3
"""Prove the literal Gate 4 Library exit across real cold processes.

The seed guest creates one managed document with six content revisions and
archives it, imports one active immutable capture, and creates then
destructively tombstones a separate managed RID.  A fresh process reloads the
MP64FS image and proves bounded active/archived/all discovery, exact retained
history and ``GONE``, immutable capture provenance, and tombstone resolution,
receipt preservation, non-discovery, and same-key non-reuse.

The clean disk is then cloned four times.  The host damages the committed head,
the selected catalog bank body, one committed content-frame payload, or installs
a checksum-valid future head payload.  A fresh guest for each clone proves that
maintenance inspection still reports the evidence, bounded opaque export is
byte exact, and ordinary load fails closed without publishing a corpus.  The
host independently verifies the export hash and every private Library object's
post-boot bytes.  The focused maintenance contract owns repair mechanics and
short-buffer export permutations; this exit driver does not repeat them.
"""

from __future__ import annotations

import argparse
import hashlib
import multiprocessing
import re
import struct
import time
import traceback
from dataclasses import dataclass
from multiprocessing.connection import Connection
from pathlib import Path
from typing import Final

from akashic_tui import (
    FTYPE_FORTH,
    MEGAPAD_ROOT,
    MP64FS,
    PROFILES,
    MachineSession,
    Profile,
    _forth_line_tokens,
    _linked_autoexec,
    _linked_chunks,
    build_image,
    dependency_order,
)


PROFILE_NAME: Final = "_library-gate4-exit-two-cold-processes"
GENERATED_LEAF_PREFIX: Final = "gate4-leaf-"
GENERATED_LEAF_BYTES: Final = 6 * 1024
FIRST_MARKER: Final = "LIBRARY GATE4 FIRST BOOT PASS"
COLD_MARKER: Final = "LIBRARY GATE4 COLD BOOT PASS"
COMMON_FAILURES: Final = (
    "LIBRARY GATE4 FIRST BOOT FAIL",
    "LIBRARY GATE4 COLD BOOT FAIL",
    "LIBRARY GATE4 DAMAGE FAIL",
    "LIBRARY GATE4 FIRST ASSERT",
    "LIBRARY GATE4 COLD ASSERT",
    "LIBRARY GATE4 DAMAGE ASSERT",
    "EVALUATE input exceeds",
    "EVALUATE depth limit exceeded",
    " ? (not found)",
    "Dictionary full",
    "dictionary full",
    "exception",
)
MANAGED_RID_RE: Final = re.compile(
    r"LIBRARY GATE4 FIRST MANAGED RID +([0-9A-F]{64})"
)
CAPTURE_RID_RE: Final = re.compile(
    r"LIBRARY GATE4 FIRST CAPTURE RID +([0-9A-F]{64})"
)
TOMBSTONE_RID_RE: Final = re.compile(
    r"LIBRARY GATE4 FIRST TOMBSTONE RID +([0-9A-F]{64})"
)
SELECTED_BANK_RE: Final = re.compile(
    r"LIBRARY GATE4 FIRST SELECTED BANK +([01])"
)
DAMAGE_RAW_RE: Final = re.compile(
    r"LIBRARY GATE4 DAMAGE RAW +([0-9]+) +([0-9A-F]{64})"
)
WAIT_RE: Final = re.compile(r"G4 WAIT +([0-9]+)")

LIBRARY_DIRECTORY: Final = "/library"
LIBRARY_OBJECT_NAMES: Final = (
    "head.bin",
    ".s-6rmqm5qfh6dxiytnh65y",
    ".b-6rmqm5qfh6dxiytnh65y",
    ".m-6rmqm5qfh6dxiytnh65y",
    "catalog-a.bin",
    "catalog-b.bin",
    "content.bin",
)


@dataclass(frozen=True)
class SeedEvidence:
    """Stable identifiers and committed bank selection printed by the seed."""

    managed_rid: bytes
    capture_rid: bytes
    tombstone_rid: bytes
    selected_bank: int


@dataclass(frozen=True)
class DamageCase:
    """One isolated evidence mutation and its public inspection result."""

    slug: str
    label: str
    object_id: str
    object_state: str
    health: str


DAMAGE_CASES: Final = (
    DamageCase(
        "head",
        "HEAD",
        "LIBRARY-EVIDENCE-HEAD",
        "LIBRARY-EVIDENCE-S-CORRUPT",
        "LIBSTORE-S-CORRUPT",
    ),
    DamageCase(
        "selected-bank",
        "SELECTED BANK",
        "_SELECTED_OBJECT_",
        # The bounded object classifier recognizes the V1 header; the full
        # corpus probe is what detects the independently damaged bank body.
        "LIBRARY-EVIDENCE-S-RECOGNIZED",
        "LIBSTORE-S-CORRUPT",
    ),
    DamageCase(
        "content-frame",
        "CONTENT FRAME",
        "LIBRARY-EVIDENCE-CONTENT",
        # Likewise, the arena header remains recognized while the committed
        # frame/chain validation drives overall health to CORRUPT.
        "LIBRARY-EVIDENCE-S-RECOGNIZED",
        "LIBSTORE-S-CORRUPT",
    ),
    DamageCase(
        "future-head",
        "FUTURE HEAD",
        "LIBRARY-EVIDENCE-HEAD",
        "LIBRARY-EVIDENCE-S-FUTURE",
        "LIBSTORE-S-UNSUPPORTED",
    ),
)


FIRST_AUTOEXEC = r"""\ autoexec.f - seed the literal Gate 4 exit corpus
ENTER-USERLAND
REQUIRE library/vfs-store.f
REQUIRE utils/fs/drivers/vfs-mp64fs.f

VARIABLE _g4f-fails
VARIABLE _g4f-checks
VARIABLE _g4f-vfs
VARIABLE _g4f-expected
VARIABLE _g4f-input-a
VARIABLE _g4f-input-u
/BLOCK-DEVICE XBUF _g4f-bd
/VOLUME XBUF _g4f-volume
LIB-DIGEST-SIZE XBUF _g4f-arena-id
LIB-OPERATION-KEY-SIZE XBUF _g4f-managed-key
LIB-OPERATION-KEY-SIZE XBUF _g4f-capture-key
LIB-OPERATION-KEY-SIZE XBUF _g4f-tombstone-key
LIB-DIGEST-SIZE XBUF _g4f-managed-rid
LIB-DIGEST-SIZE XBUF _g4f-capture-rid
LIB-DIGEST-SIZE XBUF _g4f-tombstone-rid
LIBRARY-MANAGED-CREATE-REQUEST-SIZE XBUF _g4f-managed-request
LIBRARY-CAPTURE-IMPORT-REQUEST-SIZE XBUF _g4f-capture-request
LIBRARY-MANAGED-CREATE-REQUEST-SIZE XBUF _g4f-tombstone-request
LIB-ORIGIN-SIZE XBUF _g4f-origin
LIB-ENTRY-SIZE XBUF _g4f-entry
LIBRARY-VFS-STORE-SIZE XBUF _g4f-store

: _g4f-assert  ( flag -- )
    1 _g4f-checks +!
    0= IF
        1 _g4f-fails +!
        ." LIBRARY GATE4 FIRST ASSERT " _g4f-checks @ . CR
    THEN ;

: _g4f-hex-digit  ( nibble -- )
    DUP 10 < IF [CHAR] 0 + ELSE 10 - [CHAR] A + THEN EMIT ;

: _g4f-hex-byte  ( byte -- )
    DUP 16 / _g4f-hex-digit 15 AND _g4f-hex-digit ;

: _g4f-rid.  ( rid -- )
    LIB-DIGEST-SIZE 0 DO DUP I + C@ _g4f-hex-byte LOOP DROP ;

: _g4f-replace  ( expected-domain a u -- )
    _g4f-input-u ! _g4f-input-a ! _g4f-expected !
    _g4f-managed-rid _g4f-expected @ _g4f-input-a @ _g4f-input-u @
        _g4f-entry _g4f-store LIBRARY-VFS-STORE-REPLACE-MANAGED
        LIBSTORE-S-OK = _g4f-assert
    _g4f-entry LIBE.DOMAIN-REVISION @
        _g4f-expected @ 1+ = _g4f-assert ;

: _g4f-create-managed  ( -- )
    _g4f-managed-request LIBRARY-MANAGED-CREATE-REQUEST-INIT
    1 _g4f-managed-request LIBMCR.EXPECTED-CATALOG-GENERATION !
    LIB-MEDIA-TEXT-MARKDOWN _g4f-managed-request LIBMCR.MEDIA !
    _g4f-managed-key _g4f-managed-request
        LIBRARY-MANAGED-CREATE-OPERATION-KEY!
        LIBSTORE-S-OK = _g4f-assert
    S" Gate four retained document" _g4f-managed-request
        LIBRARY-MANAGED-CREATE-TITLE! LIBSTORE-S-OK = _g4f-assert
    S" revision one" _g4f-managed-request
        LIBRARY-MANAGED-CREATE-CONTENT! LIBSTORE-S-OK = _g4f-assert
    _g4f-managed-request LIBRARY-MANAGED-CREATE-REQUEST-VALID?
        _g4f-assert
    _g4f-managed-request _g4f-entry _g4f-store
        LIBRARY-VFS-STORE-CREATE-MANAGED
        LIBSTORE-S-OK = _g4f-assert
    _g4f-entry LIBE.ID _g4f-managed-rid RID-COPY
    _g4f-entry LIBE.DOMAIN-REVISION @ 1 = _g4f-assert ;

: _g4f-revise-and-archive  ( -- )
    1 S" revision two" _g4f-replace
    2 S" revision three" _g4f-replace
    3 S" revision four" _g4f-replace
    4 S" revision five" _g4f-replace
    5 S" revision six" _g4f-replace
    _g4f-entry LIBE.CURRENT-CONTENT-REVISION @ 6 = _g4f-assert
    _g4f-entry LIBE.OLDEST-CONTENT-REVISION @ 3 = _g4f-assert
    _g4f-managed-rid 6 _g4f-entry _g4f-store
        LIBRARY-VFS-STORE-ARCHIVE LIBSTORE-S-OK = _g4f-assert
    _g4f-entry LIBE.DOMAIN-REVISION @ 7 = _g4f-assert
    _g4f-entry LIBE.LIFECYCLE @ LIB-LIFECYCLE-ARCHIVED = _g4f-assert ;

: _g4f-build-origin  ( -- )
    _g4f-origin LIB-ORIGIN-INIT
    LIB-ORIGIN-VFS-SNAPSHOT _g4f-origin LIBO.KIND !
    S" /gate4/immutable-capture.md" DUP
        _g4f-origin LIBO.VFS LIBV.PATH-U !
        _g4f-origin LIBO.VFS LIBV.PATH SWAP CMOVE
    S" immutable gate four capture" DUP
        _g4f-origin LIBO.VFS LIBV.CONTENT-U !
        _g4f-origin LIBO.VFS LIBV.CONTENT-DIGEST SHA3-256-HASH
    QLOC-DK-PROJECTION-CONTENT
        _g4f-origin LIBO.VFS LIBV.DIGEST-KIND !
    _g4f-origin LIB-ORIGIN-VALID? _g4f-assert ;

: _g4f-import-capture  ( -- )
    _g4f-build-origin
    _g4f-capture-request LIBRARY-CAPTURE-IMPORT-REQUEST-INIT
    8 _g4f-capture-request LIBCIR.EXPECTED-CATALOG-GENERATION !
    LIB-MEDIA-TEXT-MARKDOWN _g4f-capture-request LIBCIR.MEDIA !
    _g4f-capture-key _g4f-capture-request
        LIBRARY-CAPTURE-IMPORT-OPERATION-KEY!
        LIBSTORE-S-OK = _g4f-assert
    S" Gate four immutable capture" _g4f-capture-request
        LIBRARY-CAPTURE-IMPORT-TITLE! LIBSTORE-S-OK = _g4f-assert
    S" immutable gate four capture" _g4f-capture-request
        LIBRARY-CAPTURE-IMPORT-CONTENT! LIBSTORE-S-OK = _g4f-assert
    _g4f-origin _g4f-capture-request LIBRARY-CAPTURE-IMPORT-ORIGIN!
        LIBSTORE-S-OK = _g4f-assert
    _g4f-capture-request LIBRARY-CAPTURE-IMPORT-REQUEST-VALID?
        _g4f-assert
    _g4f-capture-request _g4f-entry _g4f-store
        LIBRARY-VFS-STORE-IMPORT-CAPTURE
        LIBSTORE-S-OK = _g4f-assert
    _g4f-entry LIBE.ID _g4f-capture-rid RID-COPY
    _g4f-entry LIBE.DOMAIN-REVISION @ 1 = _g4f-assert ;

: _g4f-create-tombstone  ( -- )
    _g4f-tombstone-request LIBRARY-MANAGED-CREATE-REQUEST-INIT
    9 _g4f-tombstone-request LIBMCR.EXPECTED-CATALOG-GENERATION !
    LIB-MEDIA-TEXT-MARKDOWN _g4f-tombstone-request LIBMCR.MEDIA !
    _g4f-tombstone-key _g4f-tombstone-request
        LIBRARY-MANAGED-CREATE-OPERATION-KEY!
        LIBSTORE-S-OK = _g4f-assert
    S" Gate four retired identity" _g4f-tombstone-request
        LIBRARY-MANAGED-CREATE-TITLE! LIBSTORE-S-OK = _g4f-assert
    S" retired bytes" _g4f-tombstone-request
        LIBRARY-MANAGED-CREATE-CONTENT! LIBSTORE-S-OK = _g4f-assert
    _g4f-tombstone-request LIBRARY-MANAGED-CREATE-REQUEST-VALID?
        _g4f-assert
    _g4f-tombstone-request _g4f-entry _g4f-store
        LIBRARY-VFS-STORE-CREATE-MANAGED
        LIBSTORE-S-OK = _g4f-assert
    _g4f-entry LIBE.ID _g4f-tombstone-rid RID-COPY
    _g4f-tombstone-rid 1 _g4f-entry _g4f-store
        LIBRARY-VFS-STORE-TOMBSTONE-DESTRUCTIVE
        LIBSTORE-S-OK = _g4f-assert
    _g4f-entry LIBE.DOMAIN-REVISION @ 2 = _g4f-assert
    _g4f-entry LIBE.LIFECYCLE @ LIB-LIFECYCLE-TOMBSTONED = _g4f-assert ;

: _g4f-run  ( -- )
    0 _g4f-fails ! 0 _g4f-checks !
    _g4f-arena-id LIB-DIGEST-SIZE 0xA4 FILL
    _g4f-managed-key LIB-OPERATION-KEY-SIZE 0x51 FILL
    _g4f-capture-key LIB-OPERATION-KEY-SIZE 0x62 FILL
    _g4f-tombstone-key LIB-OPERATION-KEY-SIZE 0x73 FILL
    _g4f-bd BD-OPEN THROW
    _g4f-bd _g4f-volume VOL-RAW THROW
    4194304 A-XMEM ARENA-NEW IF -7861 THROW THEN
    _g4f-volume VMP-NEW ?DUP IF THROW THEN
    DUP _g4f-vfs ! DUP 0<> _g4f-assert VFS-USE
    _g4f-vfs @ _g4f-store LIBRARY-VFS-STORE-INIT
        LIBSTORE-S-OK = _g4f-assert
    _g4f-store LIBRARY-VFS-STORE-LOAD
        LIBSTORE-S-ABSENT = _g4f-assert
    _g4f-arena-id _g4f-store LIBRARY-VFS-STORE-PROVISION
        LIBSTORE-S-OK = _g4f-assert
    _g4f-create-managed
    _g4f-revise-and-archive
    _g4f-import-capture
    _g4f-create-tombstone
    _g4f-store LIBRARY-VFS-STORE.GENERATION @ 11 = _g4f-assert
    _g4f-vfs @ VFS-SYNC 0= _g4f-assert
    _g4f-fails @ 0= IF
        ." LIBRARY GATE4 FIRST MANAGED RID "
            _g4f-managed-rid _g4f-rid. CR
        ." LIBRARY GATE4 FIRST CAPTURE RID "
            _g4f-capture-rid _g4f-rid. CR
        ." LIBRARY GATE4 FIRST TOMBSTONE RID "
            _g4f-tombstone-rid _g4f-rid. CR
        ." LIBRARY GATE4 FIRST SELECTED BANK "
            _g4f-store LIBRARY-VFS-STORE.HEAD LIBHF.BANK-SELECTOR @ . CR
        ." LIBRARY GATE4 FIRST BOOT PASS " _g4f-checks @ . CR
    ELSE
        ." LIBRARY GATE4 FIRST BOOT FAIL "
            _g4f-fails @ . ." / " _g4f-checks @ . CR
    THEN ;

_g4f-run
"""


def _forth_bytes(data: bytes) -> str:
    """Return comma-compiled Forth bytes in short readable rows."""
    return "\n".join(
        " ".join(f"0x{byte:02X} C," for byte in data[offset : offset + 8])
        for offset in range(0, len(data), 8)
    )


def _cold_autoexec(evidence: SeedEvidence) -> str:
    managed = _forth_bytes(evidence.managed_rid)
    capture = _forth_bytes(evidence.capture_rid)
    tombstone = _forth_bytes(evidence.tombstone_rid)
    return rf"""\ autoexec.f - literal Gate 4 cold semantic exit
ENTER-USERLAND
REQUIRE library/vfs-store.f
REQUIRE utils/fs/drivers/vfs-mp64fs.f

VARIABLE _g4c-fails
VARIABLE _g4c-checks
VARIABLE _g4c-vfs
VARIABLE _g4c-status
VARIABLE _g4c-required
VARIABLE _g4c-count
VARIABLE _g4c-next
VARIABLE _g4c-generation
VARIABLE _g4c-saved-next
VARIABLE _g4c-saved-generation
/BLOCK-DEVICE XBUF _g4c-bd
/VOLUME XBUF _g4c-volume
CREATE _g4c-managed-rid {managed}
CREATE _g4c-capture-rid {capture}
CREATE _g4c-tombstone-rid {tombstone}
LIB-OPERATION-KEY-SIZE XBUF _g4c-managed-key
LIB-OPERATION-KEY-SIZE XBUF _g4c-capture-key
LIB-OPERATION-KEY-SIZE XBUF _g4c-tombstone-key
LIB-DIGEST-SIZE XBUF _g4c-rid-out
LIB-DIGEST-SIZE XBUF _g4c-digest
LIB-RECEIPT-SIZE XBUF _g4c-receipt
LIB-ENTRY-SIZE XBUF _g4c-entry
LIB-CONTENT-SIZE XBUF _g4c-content
CREATE _g4c-bytes 64 ALLOT
LIBRARY-REVISION-SUMMARY-SIZE LIB-RETAINED-REVISION-MAX * XBUF _g4c-history
LIBRARY-CORPUS-QUERY-REQUEST-SIZE XBUF _g4c-query
LIBRARY-QUERY-SUMMARY-SIZE XBUF _g4c-summary
LIBRARY-MANAGED-CREATE-REQUEST-SIZE XBUF _g4c-tombstone-request
LIBRARY-VFS-STORE-SIZE XBUF _g4c-store

: _g4c-assert  ( flag -- )
    1 _g4c-checks +!
    0= IF
        1 _g4c-fails +!
        ." LIBRARY GATE4 COLD ASSERT " _g4c-checks @ . CR
    THEN ;

: _g4c-zero?  ( a u -- flag )
    0 ?DO DUP I + C@ IF DROP 0 UNLOOP EXIT THEN LOOP DROP -1 ;

: _g4c-history@  ( index -- summary )
    LIBRARY-REVISION-SUMMARY-SIZE * _g4c-history + ;

: _g4c-query-call  ( -- )
    _g4c-query _g4c-summary 1 _g4c-store
        LIBRARY-VFS-STORE-QUERY-CORPUS
    _g4c-status ! _g4c-generation ! _g4c-next ! _g4c-count ! ;

: _g4c-query-one  ( lifecycle expected-rid -- )
    >R _g4c-query LIBRARY-CORPUS-QUERY-REQUEST-INIT
    _g4c-query LIBCQR.LIFECYCLE-MASK !
    _g4c-query LIBRARY-CORPUS-QUERY-REQUEST-VALID? _g4c-assert
    _g4c-query-call
    _g4c-status @ LIBSTORE-S-OK = _g4c-assert
    _g4c-count @ 1 = _g4c-assert
    _g4c-next @ DUP 0>= _g4c-assert
        _g4c-query LIBCQR.START-SLOT !
    _g4c-generation @ 11 = _g4c-assert
    _g4c-summary LIBQS.REF RREF.ID R> RID= _g4c-assert
    11 _g4c-query LIBCQR.EXPECTED-CATALOG-GENERATION !
    _g4c-query LIBRARY-CORPUS-QUERY-REQUEST-VALID? _g4c-assert
    _g4c-query-call
    _g4c-status @ LIBSTORE-S-OK = _g4c-assert
    _g4c-count @ 0= _g4c-assert
    _g4c-next @ -1 = _g4c-assert
    _g4c-generation @ 11 = _g4c-assert ;

: _g4c-query-proof  ( -- )
    LIBRARY-CORPUS-LIFECYCLE-ACTIVE _g4c-capture-rid _g4c-query-one
    LIBRARY-CORPUS-LIFECYCLE-ARCHIVED _g4c-managed-rid _g4c-query-one

    _g4c-query LIBRARY-CORPUS-QUERY-REQUEST-INIT
    LIBRARY-CORPUS-LIFECYCLE-ALL
        _g4c-query LIBCQR.LIFECYCLE-MASK !
    _g4c-query LIBRARY-CORPUS-QUERY-REQUEST-VALID? _g4c-assert
    _g4c-query-call
    _g4c-status @ LIBSTORE-S-OK = _g4c-assert
    _g4c-count @ 1 = _g4c-assert
    _g4c-next @ 0>= _g4c-assert
    _g4c-generation @ 11 = _g4c-assert
    _g4c-summary LIBQS.REF RREF.ID _g4c-managed-rid RID= _g4c-assert
    _g4c-next @ _g4c-saved-next !
    _g4c-generation @ _g4c-saved-generation !

    _g4c-saved-generation @
        _g4c-query LIBCQR.EXPECTED-CATALOG-GENERATION !
    _g4c-saved-next @ _g4c-query LIBCQR.START-SLOT !
    _g4c-query LIBRARY-CORPUS-QUERY-REQUEST-VALID? _g4c-assert
    _g4c-query-call
    _g4c-status @ LIBSTORE-S-OK = _g4c-assert
    _g4c-count @ 1 = _g4c-assert
    _g4c-next @ DUP 0>= _g4c-assert
        _g4c-query LIBCQR.START-SLOT !
    _g4c-generation @ 11 = _g4c-assert
    _g4c-summary LIBQS.REF RREF.ID _g4c-capture-rid RID= _g4c-assert

    _g4c-query LIBRARY-CORPUS-QUERY-REQUEST-VALID? _g4c-assert
    _g4c-query-call
    _g4c-status @ LIBSTORE-S-OK = _g4c-assert
    _g4c-count @ 0= _g4c-assert
    _g4c-next @ -1 = _g4c-assert
    _g4c-generation @ 11 = _g4c-assert ;

: _g4c-managed-proof  ( -- )
    _g4c-managed-rid 7 _g4c-bytes 64
        _g4c-entry _g4c-content _g4c-store
        LIBRARY-VFS-STORE-READ-MANAGED-EXACT
    _g4c-status ! _g4c-required !
    _g4c-status @ LIBSTORE-S-OK = _g4c-assert
    _g4c-required @ S" revision six" NIP = _g4c-assert
    _g4c-entry LIBE.ID _g4c-managed-rid RID= _g4c-assert
    _g4c-entry LIBE.DOMAIN-REVISION @ 7 = _g4c-assert
    _g4c-entry LIBE.LIFECYCLE @ LIB-LIFECYCLE-ARCHIVED = _g4c-assert
    _g4c-entry LIBE.CURRENT-CONTENT-REVISION @ 6 = _g4c-assert
    _g4c-entry LIBE.OLDEST-CONTENT-REVISION @ 3 = _g4c-assert
    _g4c-content LIBCT.CONTENT-REVISION @ 6 = _g4c-assert
    _g4c-content LIBCT-DATA$ S" revision six" COMPARE 0= _g4c-assert

    _g4c-managed-rid 7 _g4c-history LIB-RETAINED-REVISION-MAX
        _g4c-store LIBRARY-VFS-STORE-LIST-RETAINED-REVISIONS
    _g4c-status ! _g4c-required !
    _g4c-status @ LIBSTORE-S-OK = _g4c-assert
    _g4c-required @ 4 = _g4c-assert
    0 _g4c-history@ LIBRS.DOMAIN-REVISION @ 6 = _g4c-assert
    1 _g4c-history@ LIBRS.DOMAIN-REVISION @ 5 = _g4c-assert
    2 _g4c-history@ LIBRS.DOMAIN-REVISION @ 4 = _g4c-assert
    3 _g4c-history@ LIBRS.DOMAIN-REVISION @ 3 = _g4c-assert

    _g4c-managed-rid 3 _g4c-bytes 64
        _g4c-content _g4c-store LIBRARY-VFS-STORE-READ-RETAINED-EXACT
    _g4c-status ! _g4c-required !
    _g4c-status @ LIBSTORE-S-OK = _g4c-assert
    _g4c-content LIBCT-DATA$ S" revision three" COMPARE 0= _g4c-assert
    _g4c-managed-rid 2 _g4c-bytes 64
        _g4c-content _g4c-store LIBRARY-VFS-STORE-READ-RETAINED-EXACT
    _g4c-status ! _g4c-required !
    _g4c-status @ LIBSTORE-S-GONE = _g4c-assert
    _g4c-required @ 0= _g4c-assert ;

: _g4c-receipt-proof  ( -- )
    _g4c-managed-key _g4c-rid-out _g4c-receipt _g4c-store
        LIBRARY-VFS-STORE-LOOKUP-RECEIPT
        LIBSTORE-S-OK = _g4c-assert
    _g4c-rid-out _g4c-managed-rid RID= _g4c-assert
    _g4c-receipt LIB-RECEIPT-VALID? _g4c-assert
    _g4c-receipt LIBR.OPERATION-KEY _g4c-managed-key RID= _g4c-assert
    _g4c-receipt LIBR.METHOD @ LIB-IMPORT-CREATED = _g4c-assert

    _g4c-capture-key _g4c-rid-out _g4c-receipt _g4c-store
        LIBRARY-VFS-STORE-LOOKUP-RECEIPT
        LIBSTORE-S-OK = _g4c-assert
    _g4c-rid-out _g4c-capture-rid RID= _g4c-assert
    _g4c-receipt LIB-RECEIPT-VALID? _g4c-assert
    _g4c-receipt LIBR.OPERATION-KEY _g4c-capture-key RID= _g4c-assert
    _g4c-receipt LIBR.METHOD @
        LIB-IMPORT-VFS-SNAPSHOT = _g4c-assert ;

: _g4c-tombstone-receipt-proof  ( -- )
    _g4c-tombstone-key _g4c-rid-out _g4c-receipt _g4c-store
        LIBRARY-VFS-STORE-LOOKUP-RECEIPT
        LIBSTORE-S-TOMBSTONED = _g4c-assert
    _g4c-rid-out _g4c-tombstone-rid RID= _g4c-assert
    _g4c-receipt LIB-RECEIPT-VALID? _g4c-assert
    _g4c-receipt LIBR.OPERATION-KEY _g4c-tombstone-key RID= _g4c-assert
    _g4c-receipt LIBR.METHOD @ LIB-IMPORT-CREATED = _g4c-assert ;

: _g4c-capture-proof  ( -- )
    _g4c-capture-rid 1 _g4c-bytes 64
        _g4c-entry _g4c-content _g4c-store
        LIBRARY-VFS-STORE-READ-EXACT
    _g4c-status ! _g4c-required !
    _g4c-status @ LIBSTORE-S-OK = _g4c-assert
    _g4c-entry LIBE.KIND @ LIB-KIND-CAPTURE = _g4c-assert
    _g4c-entry LIBE.LIFECYCLE @ LIB-LIFECYCLE-ACTIVE = _g4c-assert
    _g4c-content LIBCT-DATA$
        S" immutable gate four capture" COMPARE 0= _g4c-assert
    _g4c-entry LIBE.ORIGIN LIB-ORIGIN-VALID? _g4c-assert
    _g4c-entry LIBE.ORIGIN LIBO.VFS LIBV-PATH$
        S" /gate4/immutable-capture.md" COMPARE 0= _g4c-assert
    _g4c-entry LIBE.ORIGIN LIBO.VFS LIBV.CONTENT-U @
        S" immutable gate four capture" NIP = _g4c-assert
    S" immutable gate four capture" _g4c-digest SHA3-256-HASH
    _g4c-entry LIBE.ORIGIN LIBO.VFS LIBV.CONTENT-DIGEST
        _g4c-digest SHA3-256-COMPARE _g4c-assert ;

: _g4c-tombstone-request!  ( -- )
    _g4c-tombstone-request LIBRARY-MANAGED-CREATE-REQUEST-INIT
    9 _g4c-tombstone-request LIBMCR.EXPECTED-CATALOG-GENERATION !
    LIB-MEDIA-TEXT-MARKDOWN _g4c-tombstone-request LIBMCR.MEDIA !
    _g4c-tombstone-key _g4c-tombstone-request
        LIBRARY-MANAGED-CREATE-OPERATION-KEY!
        LIBSTORE-S-OK = _g4c-assert
    S" Gate four retired identity" _g4c-tombstone-request
        LIBRARY-MANAGED-CREATE-TITLE! LIBSTORE-S-OK = _g4c-assert
    S" retired bytes" _g4c-tombstone-request
        LIBRARY-MANAGED-CREATE-CONTENT! LIBSTORE-S-OK = _g4c-assert
    _g4c-tombstone-request LIBRARY-MANAGED-CREATE-REQUEST-VALID?
        _g4c-assert ;

: _g4c-tombstone-proof  ( -- )
    _g4c-tombstone-rid _g4c-entry _g4c-store
        LIBRARY-VFS-STORE-READ-IDENTITY
        LIBSTORE-S-TOMBSTONED = _g4c-assert
    _g4c-entry LIBE.ID _g4c-tombstone-rid RID= _g4c-assert
    _g4c-entry LIBE.LIFECYCLE @
        LIB-LIFECYCLE-TOMBSTONED = _g4c-assert

    _g4c-tombstone-rid 2 _g4c-bytes 64
        _g4c-entry _g4c-content _g4c-store LIBRARY-VFS-STORE-READ-EXACT
    _g4c-status ! _g4c-required !
    _g4c-status @ LIBSTORE-S-TOMBSTONED = _g4c-assert
    _g4c-required @ 0= _g4c-assert
    _g4c-content LIB-CONTENT-SIZE _g4c-zero? _g4c-assert

    _g4c-tombstone-receipt-proof
    _g4c-tombstone-request!
    _g4c-tombstone-request _g4c-entry _g4c-store
        LIBRARY-VFS-STORE-CREATE-MANAGED
        LIBSTORE-S-TOMBSTONED = _g4c-assert
    _g4c-entry LIBE.ID _g4c-tombstone-rid RID= _g4c-assert
    _g4c-store LIBRARY-VFS-STORE.GENERATION @ 11 = _g4c-assert ;

: _g4c-run  ( -- )
    ." G4 PHASE 3" CR
    0 _g4c-fails ! 0 _g4c-checks !
    _g4c-managed-key LIB-OPERATION-KEY-SIZE 0x51 FILL
    _g4c-capture-key LIB-OPERATION-KEY-SIZE 0x62 FILL
    _g4c-tombstone-key LIB-OPERATION-KEY-SIZE 0x73 FILL
    _g4c-bd BD-OPEN THROW
    _g4c-bd _g4c-volume VOL-RAW THROW
    4194304 A-XMEM ARENA-NEW IF -7862 THROW THEN
    _g4c-volume VMP-NEW ?DUP IF THROW THEN
    DUP _g4c-vfs ! DUP 0<> _g4c-assert VFS-USE
    _g4c-vfs @ _g4c-store LIBRARY-VFS-STORE-INIT
        LIBSTORE-S-OK = _g4c-assert
    ." G4 PHASE 4" CR
    _g4c-store LIBRARY-VFS-STORE-LOAD
        LIBSTORE-S-OK = _g4c-assert
    _g4c-store LIBRARY-VFS-STORE.GENERATION @ 11 = _g4c-assert
    ." G4 PHASE 5" CR
    _g4c-query-proof
    ." G4 PHASE 6" CR
    _g4c-managed-proof
    _g4c-receipt-proof
    ." G4 PHASE 7" CR
    _g4c-capture-proof
    ." G4 PHASE 8" CR
    _g4c-tombstone-proof
    ." G4 PHASE 9" CR
    _g4c-vfs @ VFS-SYNC 0= _g4c-assert
    _g4c-fails @ 0= IF
        ." LIBRARY GATE4 COLD BOOT PASS " _g4c-checks @ . CR
    ELSE
        ." LIBRARY GATE4 COLD BOOT FAIL "
            _g4c-fails @ . ." / " _g4c-checks @ . CR
    THEN ;

_g4c-run
"""


def _damage_autoexec(case: DamageCase, selected_bank: int) -> str:
    object_id = case.object_id
    if object_id == "_SELECTED_OBJECT_":
        object_id = (
            "LIBRARY-EVIDENCE-BANK-A"
            if selected_bank == 0
            else "LIBRARY-EVIDENCE-BANK-B"
        )
    marker = f"LIBRARY GATE4 DAMAGE {case.label} PASS"
    return rf"""\ autoexec.f - isolated Gate 4 {case.slug} evidence damage
ENTER-USERLAND
REQUIRE library/vfs-store.f
REQUIRE utils/fs/drivers/vfs-mp64fs.f

VARIABLE _g4d-fails
VARIABLE _g4d-checks
VARIABLE _g4d-vfs
VARIABLE _g4d-required
VARIABLE _g4d-status
/BLOCK-DEVICE XBUF _g4d-bd
/VOLUME XBUF _g4d-volume
LIBRARY-INSPECTION-SIZE XBUF _g4d-inspection
LIBRARY-RAW-EXPORT-MAX XBUF _g4d-raw
LIB-DIGEST-SIZE XBUF _g4d-digest
LIBRARY-VFS-STORE-SIZE XBUF _g4d-store

: _g4d-assert  ( flag -- )
    1 _g4d-checks +!
    0= IF
        1 _g4d-fails +!
        ." LIBRARY GATE4 DAMAGE ASSERT " _g4d-checks @ . CR
    THEN ;

: _g4d-zero?  ( a u -- flag )
    0 ?DO DUP I + C@ IF DROP 0 UNLOOP EXIT THEN LOOP DROP -1 ;

: _g4d-hex-digit  ( nibble -- )
    DUP 10 < IF [CHAR] 0 + ELSE 10 - [CHAR] A + THEN EMIT ;

: _g4d-hex-byte  ( byte -- )
    DUP 16 / _g4d-hex-digit 15 AND _g4d-hex-digit ;

: _g4d-digest.  ( digest -- )
    LIB-DIGEST-SIZE 0 DO DUP I + C@ _g4d-hex-byte LOOP DROP ;

: _g4d-inspect  ( -- )
    _g4d-inspection LIBRARY-INSPECTION-INIT
    _g4d-inspection _g4d-store LIBRARY-VFS-STORE-INSPECT
        LIBSTORE-S-OK = _g4d-assert
    _g4d-inspection LIBINS.HEALTH @ {case.health} = _g4d-assert
    _g4d-inspection LIBINS.REPAIR-MASK @ 0= _g4d-assert
    _g4d-inspection LIBINS.RAW-REQUIRED @ DUP 0> SWAP
        LIBRARY-RAW-EXPORT-MAX <= AND _g4d-assert
    _g4d-inspection LIBINS.HEAD-GENERATION @ 0= _g4d-assert
    _g4d-inspection LIBINS.SELECTED-BANK @ 0= _g4d-assert
    _g4d-inspection LIBINS.CATALOG-COUNT @ 0= _g4d-assert
    _g4d-inspection LIBINS.COLLECTION-COUNT @ 0= _g4d-assert
    _g4d-inspection LIBINS.MUTATION-SEQUENCE @ 0= _g4d-assert
    _g4d-inspection LIBINS.CONTENT-TAIL @ 0= _g4d-assert
    _g4d-inspection LIBINS.CONTENT-RECORD-COUNT @ 0= _g4d-assert
    {object_id} _g4d-inspection LIBINS-OBJECT LIBEO.STATE @
        {case.object_state} = _g4d-assert
    {object_id} _g4d-inspection LIBINS-OBJECT LIBEO.RAW-U @
        0> _g4d-assert ;

: _g4d-export  ( -- )
    _g4d-raw LIBRARY-RAW-EXPORT-MAX _g4d-inspection _g4d-store
        LIBRARY-VFS-STORE-RAW-EXPORT
    _g4d-status ! _g4d-required !
    _g4d-status @ LIBSTORE-S-OK = _g4d-assert
    _g4d-required @ _g4d-inspection LIBINS.RAW-REQUIRED @ = _g4d-assert
    _g4d-raw _g4d-required @ _g4d-digest SHA3-256-HASH ;

: _g4d-run  ( -- )
    0 _g4d-fails ! 0 _g4d-checks !
    _g4d-bd BD-OPEN THROW
    _g4d-bd _g4d-volume VOL-RAW THROW
    4194304 A-XMEM ARENA-NEW IF -7863 THROW THEN
    _g4d-volume VMP-NEW ?DUP IF THROW THEN
    DUP _g4d-vfs ! DUP 0<> _g4d-assert VFS-USE
    _g4d-vfs @ _g4d-store LIBRARY-VFS-STORE-INIT
        LIBSTORE-S-OK = _g4d-assert
    _g4d-store LIBRARY-VFS-STORE-LOADED? 0= _g4d-assert
    _g4d-store LIBRARY-VFS-STORE.GENERATION @ 0= _g4d-assert
    _g4d-inspect
    _g4d-export
    _g4d-store LIBRARY-VFS-STORE-LOAD
        {case.health} = _g4d-assert
    _g4d-store LIBRARY-VFS-STORE-BLOCKED? _g4d-assert
    _g4d-store LIBRARY-VFS-STORE-PROVISIONED? 0= _g4d-assert
    _g4d-store LIBRARY-VFS-STORE-LOADED? 0= _g4d-assert
    _g4d-store LIBRARY-VFS-STORE.GENERATION @ 0= _g4d-assert
    _g4d-store LIBRARY-VFS-STORE.HEAD LIB-HEAD-FACT-SIZE
        _g4d-zero? _g4d-assert
    _g4d-store LIBRARY-VFS-STORE.BANK LIB-BANK-FACT-SIZE
        _g4d-zero? _g4d-assert
    _g4d-vfs @ VFS-SYNC 0= _g4d-assert
    _g4d-fails @ 0= IF
        ." LIBRARY GATE4 DAMAGE RAW " _g4d-required @ . SPACE
            _g4d-digest _g4d-digest. CR
        ." {marker} " _g4d-checks @ . CR
    ELSE
        ." LIBRARY GATE4 DAMAGE FAIL "
            _g4d-fails @ . ." / " _g4d-checks @ . CR
    THEN ;

_g4d-run
"""


def _profile() -> Profile:
    """Return the linked closure shared by every isolated process."""
    return Profile(
        roots=(
            "library/vfs-store.f",
            "utils/fs/drivers/vfs-mp64fs.f",
        ),
        resources=(),
        autoexec=FIRST_AUTOEXEC,
        ready_markers=(FIRST_MARKER,),
        stable_markers=(FIRST_MARKER,),
        failure_markers=COMMON_FAILURES,
        linked=True,
        include_large_sample=False,
        total_sectors=8192,
    )


def _linked_layout(
    profile: Profile,
) -> tuple[tuple[str, ...], dict[str, bytes]]:
    """Reproduce ``build_image``'s deterministic linked module layout."""
    if not profile.linked:
        raise ValueError("Gate 4 exit profile must be linked")
    modules = dependency_order(profile.roots)
    chunks = _linked_chunks(modules, profile.link_chunk_bytes)
    if not chunks:
        raise RuntimeError("Gate 4 linked closure produced no chunks")
    return modules, chunks


def _assert_linked_manifest(
    filesystem: MP64FS,
    chunks: dict[str, bytes],
) -> tuple[str, ...]:
    """Verify every deterministic linked chunk before replacing autoexec."""
    parent = filesystem.resolve_path("/.akashic")
    expected_names = tuple(Path(path).name for path in chunks)
    actual_names = tuple(
        sorted(entry.name for entry in filesystem.list_files(parent=parent))
    )
    if actual_names != tuple(sorted(expected_names)):
        raise RuntimeError(
            "linked chunk manifest changed: "
            f"expected {expected_names!r}, found {actual_names!r}"
        )
    for path, expected_content in chunks.items():
        name = Path(path).name
        actual_content = filesystem.read_file(name, parent=parent)
        if actual_content != expected_content:
            raise RuntimeError(f"linked chunk content changed: {path}")
    return tuple(chunks)


def _generated_leaf_chunks(source: str) -> tuple[bytes, ...]:
    """Split minified fixture source only at complete top-level units."""
    units: list[bytes] = []
    unit = bytearray()
    definition_depth = 0
    conditional_depth = 0
    for line in source.splitlines(keepends=True):
        unit.extend(line.encode("utf-8"))
        text = line.rstrip("\r\n")
        tokens = _forth_line_tokens(text)
        if tokens and (tokens[0] == ":" or tokens[0].upper() == ":NONAME"):
            definition_depth = 1
        if definition_depth and any(
            token == ";"
            and (
                index == 0
                or tokens[index - 1].upper() not in {"CHAR", "[CHAR]"}
            )
            for index, token in enumerate(tokens)
        ):
            definition_depth = 0
        for token in text.split(" "):
            upper = token.upper()
            if upper == "[IF]":
                conditional_depth += 1
            elif upper == "[THEN]" and conditional_depth:
                conditional_depth -= 1
        if definition_depth == 0 and conditional_depth == 0:
            units.append(bytes(unit))
            unit.clear()
    if unit:
        raise RuntimeError("generated Gate 4 fixture ends inside a source unit")

    chunks: list[bytearray] = []
    current = bytearray()
    for source_unit in units:
        if len(source_unit) > GENERATED_LEAF_BYTES:
            raise RuntimeError(
                "generated Gate 4 source unit exceeds the leaf bound: "
                f"{len(source_unit)} > {GENERATED_LEAF_BYTES}"
            )
        if current and len(current) + len(source_unit) > GENERATED_LEAF_BYTES:
            chunks.append(current)
            current = bytearray()
        current.extend(source_unit)
    if current:
        chunks.append(current)
    if not chunks:
        raise RuntimeError("generated Gate 4 fixture produced no leaf chunks")
    return tuple(bytes(chunk) for chunk in chunks)


def _install_linked_leaf(
    filesystem: MP64FS, profile: Profile, source: str
) -> None:
    """Install generated leaves behind a tiny manifest-linked autoexec.

    Generated Gate 4 proofs are intentionally kept behind ordinary bounded
    ``REQUIRE`` leaves.  Keep autoexec to the verified chunk list plus those
    leaf names and let the module loader own the generated source.
    """
    modules, chunks = _linked_layout(profile)
    chunk_names = _assert_linked_manifest(filesystem, chunks)
    for entry in tuple(filesystem.list_files()):
        if entry.name == "gate4-leaf.f" or entry.name.startswith(
            GENERATED_LEAF_PREFIX
        ):
            filesystem.delete_file(entry.name)
    leaf_source = "\n".join(
        line
        for line in source.splitlines()
        if line.strip().upper() != "ENTER-USERLAND"
    )
    leaf = _linked_autoexec(leaf_source + "\n", (), modules)
    leaf_chunks = _generated_leaf_chunks(leaf)
    leaf_names = [
        f"{GENERATED_LEAF_PREFIX}{index:02d}.f"
        for index in range(len(leaf_chunks))
    ]
    # Keep userland selection unambiguously ahead of every chunk.  Detailed
    # proof source belongs in ordinary REQUIRE leaves, while this bootstrap
    # carries only deterministic loader order and explicit host handshakes.
    lines = [
        "ENTER-USERLAND",
        '." G4 WAIT 0" CR KEY DROP',
    ]
    for name in chunk_names:
        lines.append(f"REQUIRE {name}")
    lines.append('." G4 WAIT 1" CR KEY DROP')
    for index, name in enumerate(leaf_names):
        lines.append(f"REQUIRE {name}")
        if index + 1 < len(leaf_names):
            lines.append(f'." G4 WAIT {index + 2}" CR KEY DROP')
    lines.append('." G4 PHASE 10" CR')
    autoexec = "\n".join(lines) + "\n"
    # Reclaim and refill the bootstrap before allocating generated fixtures so
    # repeated host builds retain one deterministic MP64FS packing order.
    _replace_autoexec(filesystem, autoexec)
    for name, content in zip(leaf_names, leaf_chunks, strict=True):
        filesystem.inject_file(name, content, ftype=FTYPE_FORTH)


def _replace_autoexec(filesystem: MP64FS, source: str) -> None:
    """Replace only the root boot leaf in an in-memory image."""
    if filesystem.find_file("autoexec.f") is None:
        raise RuntimeError("image has no autoexec.f to replace")
    filesystem.delete_file("autoexec.f")
    filesystem.inject_file(
        "autoexec.f", source.encode("utf-8"), ftype=FTYPE_FORTH
    )


def _run_until(
    image: Path,
    marker: str,
    timeout: float,
) -> tuple[bytes, str]:
    """Run one fresh emulator until its guest reports a terminal marker."""
    deadline = time.monotonic() + timeout
    steps = 0
    progress_seen: set[str] = set()
    waits_seen: set[str] = set()
    prompt_probe_sent = False
    with MachineSession.from_bios(
        MEGAPAD_ROOT / "bios.asm",
        storage_image=image,
        cols=116,
        rows=44,
        batch_steps=500_000,
    ) as session:
        session.boot()
        while time.monotonic() < deadline:
            report = session.run(
                max_steps=10_000_000,
                wall_timeout_s=min(0.5, max(0.05, deadline - time.monotonic())),
                advance_idle=True,
            )
            steps += report.steps
            screen = session.snapshot().text()
            raw = session.raw_text()
            observed = screen + "\n" + raw
            progress = {
                line.strip()
                for line in observed.splitlines()
                if "LIBRARY GATE4" in line
                or "G4 WAIT" in line
                or "G4 PHASE" in line
            }
            for line in sorted(progress - progress_seen):
                print(f"[guest progress] {line}", flush=True)
            progress_seen.update(progress)
            for match in WAIT_RE.finditer(observed):
                wait = match.group(0)
                if wait not in waits_seen:
                    waits_seen.add(wait)
                    session.send_text(" ")
                    print(
                        f"[guest release] {wait} "
                        f"rx={session.system.uart.has_rx_data}",
                        flush=True,
                    )
            failure = next(
                (item for item in COMMON_FAILURES if item in observed), None
            )
            if failure is not None:
                raise RuntimeError(f"guest reported {failure!r}\n{screen}")
            if marker in observed:
                return bytes(session.system.storage._image_data), screen + "\n" + raw
            if (
                waits_seen
                and not prompt_probe_sent
                and session.system.all_idle_or_halted
                and not session.system.uart.has_rx_data
            ):
                # Batched UART output can remain unpublished when autoexec
                # returns directly to the interactive input wait.  One empty
                # line wakes that prompt so terminal evidence or a hidden
                # evaluator error becomes observable; it is never used to
                # advance a semantic phase.
                prompt_probe_sent = True
                session.send_text("\r")
                print("[guest prompt probe]", flush=True)
            if report.reason in ("halted", "stalled"):
                break
        raw = session.raw_text()
        screen = session.snapshot().text()
        cpu = session.system.cpu
        raise RuntimeError(
            f"timed out waiting for {marker!r} after {steps} steps\n"
            f"progress={sorted(progress_seen)!r}\n"
            f"machine=pc:{cpu.pc} sp:{cpu.sp} idle:{cpu.idle} "
            f"halted:{cpu.halted} rx:{session.system.uart.has_rx_data}\n"
            f"{screen}\n{raw[-6000:]}"
        )


def _worker(
    image: str,
    marker: str,
    timeout: float,
    sender: Connection,
) -> None:
    """Run one boot in a spawned process and return serialized evidence."""
    try:
        disk, output = _run_until(Path(image), marker, timeout)
        sender.send(("ok", disk, output))
    except BaseException:  # Preserve the child traceback for the CLI caller.
        sender.send(("error", traceback.format_exc()))
    finally:
        sender.close()


def _run_in_fresh_process(
    image: Path,
    marker: str,
    timeout: float,
) -> tuple[bytes, str]:
    """Start one spawn-isolated process containing exactly one machine boot."""
    context = multiprocessing.get_context("spawn")
    receiver, sender = context.Pipe(duplex=False)
    process = context.Process(
        target=_worker,
        args=(str(image), marker, timeout, sender),
        name=f"akashic-{marker.lower().replace(' ', '-')}",
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
            f"cold-boot worker exited without evidence (exit {process.exitcode})"
        )
    if payload[0] == "error":
        raise RuntimeError(str(payload[1]))
    if payload[0] != "ok" or len(payload) != 3:
        raise RuntimeError(f"invalid cold-boot worker result: {payload[0]!r}")
    disk, output = payload[1], payload[2]
    if not isinstance(disk, bytes) or not isinstance(output, str):
        raise RuntimeError("cold-boot worker returned malformed evidence")
    if process.exitcode != 0:
        raise RuntimeError(f"cold-boot worker exited with status {process.exitcode}")
    return disk, output


def _seed_evidence(output: str) -> SeedEvidence:
    """Parse the complete stable evidence printed by a passing seed guest."""
    managed = MANAGED_RID_RE.search(output)
    capture = CAPTURE_RID_RE.search(output)
    tombstone = TOMBSTONE_RID_RE.search(output)
    selected = SELECTED_BANK_RE.search(output)
    if managed is None or capture is None or tombstone is None or selected is None:
        raise RuntimeError("seed guest passed without complete Gate 4 evidence")
    return SeedEvidence(
        managed_rid=bytes.fromhex(managed.group(1)),
        capture_rid=bytes.fromhex(capture.group(1)),
        tombstone_rid=bytes.fromhex(tombstone.group(1)),
        selected_bank=int(selected.group(1)),
    )


def _library_objects(filesystem: MP64FS) -> tuple[bytes | None, ...]:
    """Read private object bytes in the maintenance ABI's sealed order."""
    parent = filesystem.resolve_path(LIBRARY_DIRECTORY)
    result: list[bytes | None] = []
    for name in LIBRARY_OBJECT_NAMES:
        result.append(
            None
            if filesystem.find_file(name, parent=parent) is None
            else filesystem.read_file(name, parent=parent)
        )
    return tuple(result)


def _raw_bundle(objects: tuple[bytes | None, ...]) -> bytes:
    """Construct the specified unframed export from present object bytes."""
    return b"".join(item for item in objects if item is not None)


def _replace_library_object(filesystem: MP64FS, name: str, data: bytes) -> None:
    """Replace one Library file while retaining its MP64FS metadata class."""
    parent = filesystem.resolve_path(LIBRARY_DIRECTORY)
    found = filesystem.find_file(name, parent=parent)
    if found is None:
        raise RuntimeError(f"Library object is absent: {name}")
    _, entry = found
    ftype, flags = entry.ftype, entry.flags
    filesystem.delete_file(name, parent=parent)
    filesystem.inject_file(
        name,
        data,
        ftype=ftype,
        flags=flags,
        path=LIBRARY_DIRECTORY,
    )


def _crc32_bzip2(data: bytes) -> int:
    """Return the MSB-first CRC-32/BZIP2 used by Library store codecs."""
    crc = 0xFFFFFFFF
    for byte in data:
        crc ^= byte << 24
        for _ in range(8):
            crc = (
                ((crc << 1) ^ 0x04C11DB7) & 0xFFFFFFFF
                if crc & 0x80000000
                else (crc << 1) & 0xFFFFFFFF
            )
    return crc ^ 0xFFFFFFFF


def _future_head(record: bytes) -> bytes:
    """Advance only the checked Library payload format and reseal both CRCs."""
    if len(record) != 512:
        raise RuntimeError(f"unexpected Library head size: {len(record)}")
    result = bytearray(record)
    payload = bytearray(result[64:])
    if payload[:8] != b"AKLHEA01":
        raise RuntimeError("Library head payload has unexpected magic")
    if struct.unpack_from("<Q", payload, 8)[0] != 1:
        raise RuntimeError("Library golden head is not store format V1")
    struct.pack_into("<Q", payload, 8, 2)
    payload_crc = _crc32_bzip2(bytes(payload[:320] + payload[328:]))
    struct.pack_into("<Q", payload, 320, payload_crc)
    result[64:] = payload
    struct.pack_into("<Q", result, 40, _crc32_bzip2(bytes(payload)))
    header_crc = _crc32_bzip2(bytes(result[:48] + result[56:64]))
    struct.pack_into("<Q", result, 48, header_crc)
    return bytes(result)


def _apply_damage(
    filesystem: MP64FS,
    case: DamageCase,
    selected_bank: int,
) -> None:
    """Apply one narrow mutation below the MP64FS file-integrity layer."""
    parent = filesystem.resolve_path(LIBRARY_DIRECTORY)
    if case.slug == "head":
        data = bytearray(filesystem.read_file("head.bin", parent=parent))
        data[64 + 104] ^= 0x01
        _replace_library_object(filesystem, "head.bin", bytes(data))
    elif case.slug == "selected-bank":
        name = "catalog-a.bin" if selected_bank == 0 else "catalog-b.bin"
        data = bytearray(filesystem.read_file(name, parent=parent))
        data[512 + 17] ^= 0x01
        _replace_library_object(filesystem, name, bytes(data))
    elif case.slug == "content-frame":
        data = bytearray(filesystem.read_file("content.bin", parent=parent))
        data[512 + 160] ^= 0x01
        _replace_library_object(filesystem, "content.bin", bytes(data))
    elif case.slug == "future-head":
        data = filesystem.read_file("head.bin", parent=parent)
        _replace_library_object(filesystem, "head.bin", _future_head(data))
    else:  # Keep additions explicit and auditable.
        raise ValueError(f"unknown damage case: {case.slug}")


def _damage_path(image: Path, slug: str) -> Path:
    suffix = image.suffix or ".img"
    stem = image.name[: -len(suffix)] if image.suffix else image.name
    return image.with_name(f"{stem}-damage-{slug}{suffix}")


def _run_damage_case(
    golden_disk: bytes,
    base_image: Path,
    profile: Profile,
    evidence: SeedEvidence,
    case: DamageCase,
    timeout: float,
) -> None:
    """Run and independently verify one fresh-process damage branch."""
    filesystem = MP64FS(bytearray(golden_disk))
    _apply_damage(filesystem, case, evidence.selected_bank)
    filesystem_errors = filesystem.check()
    unexpected_errors = [
        error
        for error in filesystem_errors
        if not (
            "stored=0x00000000" in error
            and any(f"'{name}'" in error for name in LIBRARY_OBJECT_NAMES)
        )
    ]
    if unexpected_errors:
        raise RuntimeError(
            f"{case.slug} mutation damaged MP64FS integrity: "
            + "; ".join(unexpected_errors)
        )
    expected_objects = _library_objects(filesystem)
    expected_bundle = _raw_bundle(expected_objects)
    expected_digest = hashlib.sha3_256(expected_bundle).digest()

    _install_linked_leaf(
        filesystem,
        profile,
        _damage_autoexec(case, evidence.selected_bank),
    )
    path = _damage_path(base_image, case.slug)
    filesystem.save(path)

    marker = f"LIBRARY GATE4 DAMAGE {case.label} PASS"
    final_disk, output = _run_in_fresh_process(path, marker, timeout)
    match = DAMAGE_RAW_RE.search(output)
    if match is None:
        raise RuntimeError(f"{case.slug} guest passed without raw export evidence")
    required = int(match.group(1))
    digest = bytes.fromhex(match.group(2))
    if required != len(expected_bundle):
        raise RuntimeError(
            f"{case.slug} raw length {required} != host length {len(expected_bundle)}"
        )
    if digest != expected_digest:
        raise RuntimeError(f"{case.slug} raw export differs from damaged evidence")
    final_objects = _library_objects(MP64FS(bytearray(final_disk)))
    if final_objects != expected_objects:
        raise RuntimeError(f"{case.slug} load or repair mutated Library evidence")
    print(
        f"Library Gate 4 damage branch {case.slug}: PASS "
        f"({required} raw bytes, sha3 {digest.hex()})"
    )


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--image",
        type=Path,
        default=Path("/tmp/akashic-library-gate4-exit.img"),
    )
    parser.add_argument("--timeout", type=float, default=600.0)
    parser.add_argument(
        "--damage",
        action="append",
        choices=tuple(case.slug for case in DAMAGE_CASES),
        help="run only selected damage branch(es); default is the full matrix",
    )
    args = parser.parse_args()
    if args.timeout <= 0:
        parser.error("--timeout must be greater than zero")

    profile = _profile()
    previous = PROFILES.get(PROFILE_NAME)
    PROFILES[PROFILE_NAME] = profile
    try:
        image = build_image(PROFILE_NAME, args.image)
    finally:
        if previous is None:
            del PROFILES[PROFILE_NAME]
        else:
            PROFILES[PROFILE_NAME] = previous

    first_disk, first_output = _run_in_fresh_process(
        image, FIRST_MARKER, args.timeout
    )
    evidence = _seed_evidence(first_output)

    first_filesystem = MP64FS(bytearray(first_disk))
    first_objects = _library_objects(first_filesystem)
    _install_linked_leaf(first_filesystem, profile, _cold_autoexec(evidence))
    first_filesystem.save(image)

    golden_disk, _ = _run_in_fresh_process(image, COLD_MARKER, args.timeout)
    golden_filesystem = MP64FS(bytearray(golden_disk))
    if _library_objects(golden_filesystem) != first_objects:
        raise RuntimeError("clean cold verification mutated Library evidence")

    requested = set(args.damage or (case.slug for case in DAMAGE_CASES))
    for case in DAMAGE_CASES:
        if case.slug in requested:
            _run_damage_case(
                golden_disk,
                image,
                profile,
                evidence,
                case,
                args.timeout,
            )

    print(
        "Library Gate 4 literal cold exit: PASS "
        f"({image}, managed {evidence.managed_rid.hex()}, "
        f"capture {evidence.capture_rid.hex()}, "
        f"tombstone {evidence.tombstone_rid.hex()}, "
        f"selected bank {evidence.selected_bank}, "
        f"damage {sorted(requested)})"
    )
    return 0


if __name__ == "__main__":
    multiprocessing.freeze_support()
    raise SystemExit(main())
