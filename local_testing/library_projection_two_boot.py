#!/usr/bin/env python3
"""Prove Library projection reacquisition across two cold processes.

The first guest creates one managed document on the real MP64FS-backed
Library store, builds its stable exact projection-content locator, exercises
one fresh projection root acquisition/release, and prints only the locator's
durable RID, domain revision, and digest.  The parent retains the serialized
disk plus those printed bytes, replaces ``autoexec.f``, and starts a second
Python process containing a fresh emulator, dictionary, runtime, registries,
and Library projection root.

The cold guest reconstructs the locator from the durable evidence, attaches
through the Library RACQ root, snapshots through ``RCLI``, and verifies the
original content.  Empty registries before each acquisition, distinct context
epochs, self-bound tokens, and complete teardown prove that neither a live
component instance nor an acquisition token crossed the process boundary.
"""

from __future__ import annotations

import argparse
import multiprocessing
import re
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
    _linked_autoexec,
    _linked_chunks,
    build_image,
    dependency_order,
)


PROFILE_NAME: Final = "_library-projection-two-cold-processes"
FIRST_MARKER: Final = "LIBRARY PROJECTION FIRST BOOT PASS"
COLD_MARKER: Final = "LIBRARY PROJECTION COLD BOOT PASS"
FIRST_FAILURES: Final = (
    "LIBRARY PROJECTION FIRST BOOT FAIL",
    "LIBRARY PROJECTION FIRST ASSERT",
    "EVALUATE input exceeds",
    "EVALUATE depth limit exceeded",
    " ? (not found)",
    "dictionary full",
    "exception",
)
COLD_FAILURES: Final = (
    "LIBRARY PROJECTION COLD BOOT FAIL",
    "LIBRARY PROJECTION COLD ASSERT",
    "EVALUATE input exceeds",
    "EVALUATE depth limit exceeded",
    " ? (not found)",
    "dictionary full",
    "exception",
)
RID_RE: Final = re.compile(
    r"LIBRARY PROJECTION FIRST RID +([0-9A-F]{64})"
)
DOMAIN_RE: Final = re.compile(
    r"LIBRARY PROJECTION FIRST DOMAIN +([1-9][0-9]*)"
)
DIGEST_RE: Final = re.compile(
    r"LIBRARY PROJECTION FIRST DIGEST +([0-9A-F]{64})"
)


@dataclass(frozen=True)
class LocatorEvidence:
    """The only first-activation values admitted to the cold locator."""

    rid: bytes
    domain_revision: int
    digest: bytes


FIRST_AUTOEXEC = r"""\ autoexec.f - first Library projection persistence boot
ENTER-USERLAND
REQUIRE concurrency/guard.f
REQUIRE interop/request-bus.f
REQUIRE interop/resource-acquisition.f
REQUIRE library/vfs-store.f
REQUIRE library/projection-owner.f
REQUIRE utils/fs/drivers/vfs-mp64fs.f

VARIABLE _lpf-fails
VARIABLE _lpf-checks
VARIABLE _lpf-vfs
VARIABLE _lpf-context
VARIABLE _lpf-creg
VARIABLE _lpf-rreg
VARIABLE _lpf-bus
/BLOCK-DEVICE XBUF _lpf-bd
/VOLUME XBUF _lpf-volume

LIB-DIGEST-SIZE XBUF _lpf-arena-id
LIB-OPERATION-KEY-SIZE XBUF _lpf-operation-key
LIB-DIGEST-SIZE XBUF _lpf-check-digest
LIBRARY-MANAGED-CREATE-REQUEST-SIZE XBUF _lpf-request
LIB-ENTRY-SIZE XBUF _lpf-entry
LIBRARY-VFS-STORE-SIZE XBUF _lpf-store
PHEAD-SIZE XBUF _lpf-head
LIBRARY-PROJECTION-ROOT-SIZE XBUF _lpf-root
RREF-SIZE XBUF _lpf-ref
QLOC-SIZE XBUF _lpf-locator
LBIND-SIZE XBUF _lpf-binding
RACQ-RESULT-SIZE XBUF _lpf-result

: _lpf-assert  ( flag -- )
    1 _lpf-checks +!
    0= IF
        1 _lpf-fails +!
        ." LIBRARY PROJECTION FIRST ASSERT " _lpf-checks @ . CR
    THEN ;

: _lpf-hex-digit  ( nibble -- )
    DUP 10 < IF [CHAR] 0 + ELSE 10 - [CHAR] A + THEN EMIT ;

: _lpf-hex-byte  ( byte -- )
    DUP 16 / _lpf-hex-digit 15 AND _lpf-hex-digit ;

: _lpf-digest.  ( digest -- )
    LIB-DIGEST-SIZE 0 DO DUP I + C@ _lpf-hex-byte LOOP DROP ;

: _lpf-create-managed  ( -- )
    _lpf-request LIBRARY-MANAGED-CREATE-REQUEST-INIT
    1 _lpf-request LIBMCR.EXPECTED-CATALOG-GENERATION !
    LIB-MEDIA-TEXT-MARKDOWN _lpf-request LIBMCR.MEDIA !
    _lpf-operation-key _lpf-request
        LIBRARY-MANAGED-CREATE-OPERATION-KEY!
        LIBSTORE-S-OK = _lpf-assert
    S" Cold projection document" _lpf-request
        LIBRARY-MANAGED-CREATE-TITLE!
        LIBSTORE-S-OK = _lpf-assert
    S" durable projection content" _lpf-request
        LIBRARY-MANAGED-CREATE-CONTENT!
        LIBSTORE-S-OK = _lpf-assert
    _lpf-request LIBRARY-MANAGED-CREATE-REQUEST-VALID? _lpf-assert
    _lpf-request _lpf-entry _lpf-store
        LIBRARY-VFS-STORE-CREATE-MANAGED
        LIBSTORE-S-OK = _lpf-assert
    _lpf-entry LIB-ENTRY-VALID? _lpf-assert
    _lpf-entry LIBE.DOMAIN-REVISION @ 1 = _lpf-assert
    _lpf-entry LIBE.KIND @ LIB-KIND-MANAGED-DOCUMENT = _lpf-assert
    S" durable projection content" _lpf-check-digest SHA3-256-HASH
    _lpf-entry LIBE.CONTENT-DIGEST _lpf-check-digest
        SHA3-256-COMPARE _lpf-assert ;

: _lpf-build-locator  ( -- )
    _lpf-ref RREF-INIT
    _lpf-entry LIBE.ID _lpf-ref RREF.ID RID-COPY
    LIBRARY-PROJECTION-OWNER$ _lpf-ref
        _lpf-entry LIBE.DOMAIN-REVISION @
        _lpf-entry LIBE.CONTENT-DIGEST
        QLOC-DK-PROJECTION-CONTENT
        LIBRARY-PROJECTION-CONTRACT$ _lpf-locator QLOC-EXACT!
        QLOC-S-OK = _lpf-assert
    _lpf-locator QLOC-VALID? _lpf-assert
    _lpf-locator QLOC.MODE @ QLOC-M-EXACT-DOMAIN = _lpf-assert
    _lpf-locator QLOC.REF RREF.REVISION @ 0= _lpf-assert
    _lpf-locator QLOC-OWNER$ LIBRARY-PROJECTION-OWNER$
        STR-STR= _lpf-assert
    _lpf-locator QLOC-PROJECTION$ LIBRARY-PROJECTION-CONTRACT$
        STR-STR= _lpf-assert ;

: _lpf-runtime-init  ( -- )
    _lpf-head PHEAD-INIT
    _lpf-head PHEAD.ID LIB-DIGEST-SIZE 0x31 FILL
    _lpf-head PHEAD.CURRENT-ROOT LIB-DIGEST-SIZE 0x32 FILL
    _lpf-head PHEAD-VALID? _lpf-assert
    401 CTX-NEW DUP 0= _lpf-assert DROP _lpf-context !
    _lpf-head _lpf-context @ CTX.PRACTICE !
    CTX-F-ACTIVE _lpf-context @ CTX.FLAGS !
    _lpf-context @ CTX-VALID? _lpf-assert
    CREG-NEW DUP 0= _lpf-assert DROP _lpf-creg !
    _lpf-creg @ _lpf-context @ RREG-NEW
        DUP 0= _lpf-assert DROP _lpf-rreg !
    _lpf-creg @ 0 CBUS-NEW DUP 0= _lpf-assert DROP _lpf-bus !
    _lpf-bus @ _lpf-context @ CTX.QUEUE !
    _lpf-creg @ CREG.INST-N @ 0= _lpf-assert
    _lpf-rreg @ RREG.COUNT @ 0= _lpf-assert
    _lpf-store _lpf-context @ _lpf-creg @ _lpf-rreg @ _lpf-bus @
        _lpf-root LIBRARY-PROJECTION-ROOT-INIT
        RACQ-S-OK = _lpf-assert
    _lpf-root LIBRARY-PROJECTION-ROOT-VALID? _lpf-assert
    _lpf-root LIBRARY-PROJECTION-ROOT-RACQ RACQ-ROOT-VALID? _lpf-assert
    _lpf-root LIBRARY-PROJECTION-ROOT-LIVE@ 0= _lpf-assert
    _lpf-root LIBRARY-PROJECTION-ROOT-LEASES@ 0= _lpf-assert
    _lpf-creg @ CREG.INST-N @ 0= _lpf-assert
    _lpf-rreg @ RREG.COUNT @ 0= _lpf-assert ;

: _lpf-acquire-release  ( -- )
    _lpf-locator _lpf-root _lpf-context @ _lpf-rreg @
        _lpf-binding _lpf-result LIBRARY-PROJECTION-ATTACH
        RACQ-S-OK = _lpf-assert
    _lpf-result RACQ-RESULT-VALID? _lpf-assert
    _lpf-binding LBIND-VALID? _lpf-assert
    _lpf-binding LBIND.EPOCH @ 401 = _lpf-assert
    _lpf-result RACQ.RESULT-TOKEN RACQ.TOKEN-SELF @
        _lpf-result RACQ.RESULT-TOKEN = _lpf-assert
    _lpf-result RACQ.RESULT-TOKEN RACQ.TOKEN-ROOT @
        _lpf-root LIBRARY-PROJECTION-ROOT-RACQ = _lpf-assert
    _lpf-root LIBRARY-PROJECTION-ROOT-LIVE@ 1 = _lpf-assert
    _lpf-root LIBRARY-PROJECTION-ROOT-LEASES@ 1 = _lpf-assert
    _lpf-creg @ CREG.INST-N @ 1 = _lpf-assert
    _lpf-rreg @ RREG.COUNT @ 1 = _lpf-assert
    _lpf-binding _lpf-result RACQ-DETACH RACQ-S-OK = _lpf-assert
    _lpf-result RACQ.RESULT-TOKEN RACQ-TOKEN-ACTIVE? 0= _lpf-assert
    _lpf-binding LBIND-VALID? 0= _lpf-assert
    _lpf-root LIBRARY-PROJECTION-ROOT-LIVE@ 0= _lpf-assert
    _lpf-root LIBRARY-PROJECTION-ROOT-LEASES@ 0= _lpf-assert
    _lpf-creg @ CREG.INST-N @ 0= _lpf-assert
    _lpf-rreg @ RREG.COUNT @ 0= _lpf-assert ;

: _lpf-runtime-fini  ( -- )
    _lpf-root LIBRARY-PROJECTION-ROOT-FINI
        RACQ-S-OK = _lpf-assert
    _lpf-root LIBRARY-PROJECTION-ROOT-VALID? 0= _lpf-assert
    _lpf-creg @ CREG.INST-N @ 0= _lpf-assert
    _lpf-rreg @ RREG.COUNT @ 0= _lpf-assert
    _lpf-bus @ CBUS-FREE
    _lpf-rreg @ RREG-FREE
    _lpf-creg @ CREG-FREE
    _lpf-context @ CTX-FREE ;

: _lpf-evidence.  ( -- )
    ." LIBRARY PROJECTION FIRST RID "
        _lpf-entry LIBE.ID _lpf-digest. CR
    ." LIBRARY PROJECTION FIRST DOMAIN "
        _lpf-entry LIBE.DOMAIN-REVISION @ . CR
    ." LIBRARY PROJECTION FIRST DIGEST "
        _lpf-entry LIBE.CONTENT-DIGEST _lpf-digest. CR ;

: _lpf-run  ( -- )
    0 _lpf-fails ! 0 _lpf-checks !
    _lpf-arena-id LIB-DIGEST-SIZE 0xA9 FILL
    _lpf-operation-key LIB-OPERATION-KEY-SIZE 0x63 FILL
    _lpf-bd BD-OPEN THROW
    _lpf-bd _lpf-volume VOL-RAW THROW
    2097152 A-XMEM ARENA-NEW IF -7741 THROW THEN
    _lpf-volume VMP-NEW ?DUP IF THROW THEN
    DUP _lpf-vfs ! DUP 0<> _lpf-assert VFS-USE
    _lpf-vfs @ _lpf-store LIBRARY-VFS-STORE-INIT
        LIBSTORE-S-OK = _lpf-assert
    _lpf-store LIBRARY-VFS-STORE-LOAD
        LIBSTORE-S-ABSENT = _lpf-assert
    _lpf-arena-id _lpf-store LIBRARY-VFS-STORE-PROVISION
        LIBSTORE-S-OK = _lpf-assert
    _lpf-create-managed
    _lpf-build-locator
    _lpf-runtime-init
    _lpf-acquire-release
    _lpf-runtime-fini
    _lpf-vfs @ VFS-SYNC 0= _lpf-assert
    _lpf-store LIBRARY-VFS-STORE-FINI LIBSTORE-S-OK = _lpf-assert
    _lpf-vfs @ VFS-SYNC 0= _lpf-assert
    _lpf-fails @ 0= IF
        _lpf-evidence.
        ." LIBRARY PROJECTION FIRST BOOT PASS " _lpf-checks @ . CR
    ELSE
        ." LIBRARY PROJECTION FIRST BOOT FAIL "
            _lpf-fails @ . ." / " _lpf-checks @ . CR
    THEN ;

_lpf-run
"""


def _forth_bytes(data: bytes) -> str:
    """Return bounded bytes as readable ``C,`` rows for generated Forth."""
    return "\n".join(
        " ".join(f"0x{byte:02X} C," for byte in data[offset : offset + 8])
        for offset in range(0, len(data), 8)
    )


def _cold_autoexec(evidence: LocatorEvidence) -> str:
    if len(evidence.rid) != 32 or len(evidence.digest) != 32:
        raise ValueError("Library RID and content digest must each be 32 bytes")
    if evidence.domain_revision <= 0:
        raise ValueError("Library domain revision must be positive")
    rid_cells = _forth_bytes(evidence.rid)
    digest_cells = _forth_bytes(evidence.digest)
    return rf"""\ autoexec.f - cold Library projection reacquisition boot
ENTER-USERLAND
REQUIRE concurrency/guard.f
REQUIRE interop/request-bus.f
REQUIRE interop/resource-acquisition.f
REQUIRE interop/resource-client.f
REQUIRE library/vfs-store.f
REQUIRE library/projection-owner.f
REQUIRE utils/fs/drivers/vfs-mp64fs.f

VARIABLE _lpc-fails
VARIABLE _lpc-checks
VARIABLE _lpc-vfs
VARIABLE _lpc-context
VARIABLE _lpc-creg
VARIABLE _lpc-rreg
VARIABLE _lpc-bus
VARIABLE _lpc-request
/BLOCK-DEVICE XBUF _lpc-bd
/VOLUME XBUF _lpc-volume

CREATE _lpc-expected-rid {rid_cells}
CREATE _lpc-expected-digest {digest_cells}
{evidence.domain_revision} CONSTANT _lpc-expected-domain
LIBRARY-VFS-STORE-SIZE XBUF _lpc-store
PHEAD-SIZE XBUF _lpc-head
LIBRARY-PROJECTION-ROOT-SIZE XBUF _lpc-root
RREF-SIZE XBUF _lpc-ref
QLOC-SIZE XBUF _lpc-locator
LBIND-SIZE XBUF _lpc-binding
RACQ-RESULT-SIZE XBUF _lpc-result
RCLI-SIZE XBUF _lpc-client

: _lpc-assert  ( flag -- )
    1 _lpc-checks +!
    0= IF
        1 _lpc-fails +!
        ." LIBRARY PROJECTION COLD ASSERT " _lpc-checks @ . CR
    THEN ;

: _lpc-build-locator  ( -- )
    _lpc-ref RREF-INIT
    _lpc-expected-rid _lpc-ref RREF.ID RID-COPY
    LIBRARY-PROJECTION-OWNER$ _lpc-ref _lpc-expected-domain
        _lpc-expected-digest QLOC-DK-PROJECTION-CONTENT
        LIBRARY-PROJECTION-CONTRACT$ _lpc-locator QLOC-EXACT!
        QLOC-S-OK = _lpc-assert
    _lpc-locator QLOC-VALID? _lpc-assert
    _lpc-locator QLOC.REF RREF.ID _lpc-expected-rid RID= _lpc-assert
    _lpc-locator QLOC.DOMAIN-REVISION @
        _lpc-expected-domain = _lpc-assert
    _lpc-locator QLOC.STATE-DIGEST _lpc-expected-digest
        SHA3-256-COMPARE _lpc-assert
    _lpc-locator QLOC-OWNER$ LIBRARY-PROJECTION-OWNER$
        STR-STR= _lpc-assert
    _lpc-locator QLOC-PROJECTION$ LIBRARY-PROJECTION-CONTRACT$
        STR-STR= _lpc-assert ;

: _lpc-runtime-init  ( -- )
    _lpc-head PHEAD-INIT
    _lpc-head PHEAD.ID LIB-DIGEST-SIZE 0x31 FILL
    _lpc-head PHEAD.CURRENT-ROOT LIB-DIGEST-SIZE 0x32 FILL
    _lpc-head PHEAD-VALID? _lpc-assert
    402 CTX-NEW DUP 0= _lpc-assert DROP _lpc-context !
    _lpc-head _lpc-context @ CTX.PRACTICE !
    CTX-F-ACTIVE _lpc-context @ CTX.FLAGS !
    _lpc-context @ CTX-VALID? _lpc-assert
    CREG-NEW DUP 0= _lpc-assert DROP _lpc-creg !
    _lpc-creg @ _lpc-context @ RREG-NEW
        DUP 0= _lpc-assert DROP _lpc-rreg !
    _lpc-creg @ 0 CBUS-NEW DUP 0= _lpc-assert DROP _lpc-bus !
    _lpc-bus @ _lpc-context @ CTX.QUEUE !
    \ A cold process starts with no live projection state to recover.
    _lpc-creg @ CREG.INST-N @ 0= _lpc-assert
    _lpc-rreg @ RREG.COUNT @ 0= _lpc-assert
    _lpc-store _lpc-context @ _lpc-creg @ _lpc-rreg @ _lpc-bus @
        _lpc-root LIBRARY-PROJECTION-ROOT-INIT
        RACQ-S-OK = _lpc-assert
    _lpc-root LIBRARY-PROJECTION-ROOT-VALID? _lpc-assert
    _lpc-root LIBRARY-PROJECTION-ROOT-RACQ RACQ-ROOT-VALID? _lpc-assert
    _lpc-root LIBRARY-PROJECTION-ROOT-LIVE@ 0= _lpc-assert
    _lpc-root LIBRARY-PROJECTION-ROOT-LEASES@ 0= _lpc-assert
    _lpc-creg @ CREG.INST-N @ 0= _lpc-assert
    _lpc-rreg @ RREG.COUNT @ 0= _lpc-assert ;

: _lpc-attach  ( -- )
    _lpc-locator _lpc-root _lpc-context @ _lpc-rreg @
        _lpc-binding _lpc-result LIBRARY-PROJECTION-ATTACH
        RACQ-S-OK = _lpc-assert
    _lpc-result RACQ-RESULT-VALID? _lpc-assert
    _lpc-binding LBIND-VALID? _lpc-assert
    \ The binding belongs to the cold epoch, not the first boot's epoch 401.
    _lpc-binding LBIND.EPOCH @ 402 = _lpc-assert
    _lpc-binding LBIND.EPOCH @ 401 <> _lpc-assert
    \ Token validity is self-addressed and rooted in this cold root instance.
    _lpc-result RACQ.RESULT-TOKEN RACQ.TOKEN-SELF @
        _lpc-result RACQ.RESULT-TOKEN = _lpc-assert
    _lpc-result RACQ.RESULT-TOKEN RACQ.TOKEN-ROOT @
        _lpc-root LIBRARY-PROJECTION-ROOT-RACQ = _lpc-assert
    _lpc-result RACQ.RESULT-TOKEN RACQ.TOKEN-COOKIE @ 0> _lpc-assert
    _lpc-result RACQ.RESULT-TOKEN RACQ.TOKEN-GENERATION @ 0> _lpc-assert
    _lpc-result RACQ.RESULT-REF RREF.ID
        _lpc-expected-rid RID= _lpc-assert
    _lpc-root LIBRARY-PROJECTION-ROOT-LIVE@ 1 = _lpc-assert
    _lpc-root LIBRARY-PROJECTION-ROOT-LEASES@ 1 = _lpc-assert
    _lpc-creg @ CREG.INST-N @ 1 = _lpc-assert
    _lpc-rreg @ RREG.COUNT @ 1 = _lpc-assert ;

: _lpc-snapshot  ( -- )
    CBR-NEW DUP 0= _lpc-assert DROP _lpc-request !
    _lpc-result _lpc-binding _lpc-context @ _lpc-bus @ _lpc-client
        RCLI-INIT CBUS-S-OK = _lpc-assert
    _lpc-client RCLI-VALID? _lpc-assert
    _lpc-client RCLI-REPLACE? _lpc-assert
    _lpc-locator CPRINC-USER _lpc-request @ _lpc-client
        RCLI-SNAPSHOT-CALL CBUS-S-OK = _lpc-assert
    _lpc-locator _lpc-request @ CBR.RESULT
        RCON-SNAPSHOT-RESULT? _lpc-assert
    S" content" _lpc-request @ CBR.RESULT CV-MAP-FIND DUP 0<> _lpc-assert
    ?DUP IF
        DUP CV-TYPE@ CV-T-BYTES = _lpc-assert
        DUP CV-DATA@ SWAP CV-LEN@
            S" durable projection content" STR-STR= _lpc-assert
    THEN
    S" content_digest" _lpc-request @ CBR.RESULT CV-MAP-FIND
        DUP 0<> _lpc-assert
    ?DUP IF
        DUP CV-LEN@ LIB-DIGEST-SIZE = _lpc-assert
        CV-DATA@ _lpc-expected-digest SHA3-256-COMPARE _lpc-assert
    THEN ;

: _lpc-release-fini  ( -- )
    \ RCLI-FINI detaches its copied LBIND and releases the one live token.
    _lpc-client RCLI-FINI CBUS-S-OK = _lpc-assert
    _lpc-client RCLI-VALID? 0= _lpc-assert
    _lpc-result RACQ.RESULT-TOKEN RACQ-TOKEN-ACTIVE? 0= _lpc-assert
    _lpc-root LIBRARY-PROJECTION-ROOT-LIVE@ 0= _lpc-assert
    _lpc-root LIBRARY-PROJECTION-ROOT-LEASES@ 0= _lpc-assert
    _lpc-creg @ CREG.INST-N @ 0= _lpc-assert
    _lpc-rreg @ RREG.COUNT @ 0= _lpc-assert
    \ Clearing the caller's original binding and re-releasing are idempotent.
    _lpc-binding _lpc-result RACQ-DETACH RACQ-S-OK = _lpc-assert
    _lpc-binding LBIND-VALID? 0= _lpc-assert
    _lpc-result RACQ.RESULT-TOKEN RACQ-RELEASE
        RACQ-S-OK = _lpc-assert
    _lpc-request @ CBR-FREE
    _lpc-root LIBRARY-PROJECTION-ROOT-FINI
        RACQ-S-OK = _lpc-assert
    _lpc-root LIBRARY-PROJECTION-ROOT-VALID? 0= _lpc-assert
    _lpc-creg @ CREG.INST-N @ 0= _lpc-assert
    _lpc-rreg @ RREG.COUNT @ 0= _lpc-assert
    _lpc-bus @ CBUS-FREE
    _lpc-rreg @ RREG-FREE
    _lpc-creg @ CREG-FREE
    _lpc-context @ CTX-FREE ;

: _lpc-run  ( -- )
    0 _lpc-fails ! 0 _lpc-checks !
    _lpc-bd BD-OPEN THROW
    _lpc-bd _lpc-volume VOL-RAW THROW
    2097152 A-XMEM ARENA-NEW IF -7742 THROW THEN
    _lpc-volume VMP-NEW ?DUP IF THROW THEN
    DUP _lpc-vfs ! DUP 0<> _lpc-assert VFS-USE
    _lpc-vfs @ _lpc-store LIBRARY-VFS-STORE-INIT
        LIBSTORE-S-OK = _lpc-assert
    _lpc-store LIBRARY-VFS-STORE-LOAD
        LIBSTORE-S-OK = _lpc-assert
    _lpc-build-locator
    _lpc-runtime-init
    _lpc-attach
    _lpc-snapshot
    _lpc-release-fini
    _lpc-vfs @ VFS-SYNC 0= _lpc-assert
    _lpc-store LIBRARY-VFS-STORE-FINI LIBSTORE-S-OK = _lpc-assert
    _lpc-vfs @ VFS-SYNC 0= _lpc-assert
    _lpc-fails @ 0= IF
        ." LIBRARY PROJECTION COLD BOOT PASS " _lpc-checks @ . CR
    ELSE
        ." LIBRARY PROJECTION COLD BOOT FAIL "
            _lpc-fails @ . ." / " _lpc-checks @ . CR
    THEN ;

_lpc-run
"""


def _profile() -> Profile:
    """Return the exact build closure needed by both cold processes."""
    return Profile(
        roots=(
            "library/projection-owner.f",
            "interop/resource-client.f",
            "utils/fs/drivers/vfs-mp64fs.f",
        ),
        resources=(),
        autoexec=FIRST_AUTOEXEC,
        ready_markers=(FIRST_MARKER,),
        stable_markers=(FIRST_MARKER,),
        failure_markers=FIRST_FAILURES,
        linked=True,
        include_large_sample=False,
        total_sectors=8192,
    )


def _linked_layout(
    profile: Profile,
) -> tuple[tuple[str, ...], dict[str, bytes]]:
    """Reproduce ``build_image``'s deterministic linked module layout."""
    if not profile.linked:
        raise ValueError("Library projection two-boot profile must be linked")
    modules = dependency_order(profile.roots)
    chunks = _linked_chunks(modules, profile.link_chunk_bytes)
    if not chunks:
        raise RuntimeError("Library projection linked closure produced no chunks")
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
            "first-boot linked chunk manifest changed: "
            f"expected {expected_names!r}, found {actual_names!r}"
        )
    for path, expected_content in chunks.items():
        name = Path(path).name
        actual_content = filesystem.read_file(name, parent=parent)
        if actual_content != expected_content:
            raise RuntimeError(f"first-boot linked chunk content changed: {path}")
    return tuple(chunks)


def _linked_cold_autoexec(
    filesystem: MP64FS,
    profile: Profile,
    evidence: LocatorEvidence,
) -> str:
    """Link the cold script against the exact verified first-boot chunks."""
    modules, chunks = _linked_layout(profile)
    chunk_names = _assert_linked_manifest(filesystem, chunks)
    return _linked_autoexec(_cold_autoexec(evidence), chunk_names, modules)


def _run_until(
    image: Path,
    marker: str,
    failures: tuple[str, ...],
    timeout: float,
) -> tuple[bytes, str]:
    """Run one fresh emulator until its guest reports a terminal marker."""
    deadline = time.monotonic() + timeout
    steps = 0
    with MachineSession.from_bios(
        MEGAPAD_ROOT / "bios.asm",
        storage_image=image,
        cols=108,
        rows=34,
        batch_steps=500_000,
    ) as session:
        session.boot()
        while time.monotonic() < deadline and steps < 5_000_000_000:
            report = session.run(
                max_steps=50_000_000,
                wall_timeout_s=min(2.0, max(0.05, deadline - time.monotonic())),
                advance_idle=True,
            )
            steps += report.steps
            screen = session.snapshot().text()
            failure = next((item for item in failures if item in screen), None)
            if failure is not None:
                raise RuntimeError(f"guest reported {failure!r}\n{screen}")
            if marker in screen:
                raw = session.raw_text()
                return bytes(session.system.storage._image_data), screen + "\n" + raw
            if report.reason in ("halted", "stalled"):
                break
        raw = session.raw_text()
        raise RuntimeError(f"timed out waiting for {marker!r}\n{raw[-4000:]}")


def _worker(
    image: str,
    marker: str,
    failures: tuple[str, ...],
    timeout: float,
    sender: Connection,
) -> None:
    """Run one boot in a spawned process and return serialized evidence."""
    try:
        disk, output = _run_until(Path(image), marker, failures, timeout)
        sender.send(("ok", disk, output))
    except BaseException:  # Preserve the child traceback for the CLI caller.
        sender.send(("error", traceback.format_exc()))
    finally:
        sender.close()


def _run_in_fresh_process(
    image: Path,
    marker: str,
    failures: tuple[str, ...],
    timeout: float,
) -> tuple[bytes, str]:
    """Start one spawn-isolated process containing exactly one machine boot."""
    context = multiprocessing.get_context("spawn")
    receiver, sender = context.Pipe(duplex=False)
    process = context.Process(
        target=_worker,
        args=(str(image), marker, failures, timeout, sender),
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


def _locator_evidence(output: str) -> LocatorEvidence:
    rid_match = RID_RE.search(output)
    domain_match = DOMAIN_RE.search(output)
    digest_match = DIGEST_RE.search(output)
    if rid_match is None or domain_match is None or digest_match is None:
        raise RuntimeError(
            "first boot passed without complete durable locator evidence"
        )
    evidence = LocatorEvidence(
        rid=bytes.fromhex(rid_match.group(1)),
        domain_revision=int(domain_match.group(1)),
        digest=bytes.fromhex(digest_match.group(1)),
    )
    if len(evidence.rid) != 32 or len(evidence.digest) != 32:
        raise RuntimeError("first boot printed malformed Library locator bytes")
    return evidence


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--image",
        type=Path,
        default=Path("/tmp/akashic-library-projection-two-boot.img"),
    )
    parser.add_argument("--timeout", type=float, default=240.0)
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
        image, FIRST_MARKER, FIRST_FAILURES, args.timeout
    )
    evidence = _locator_evidence(first_output)

    fs = MP64FS(bytearray(first_disk))
    if fs.find_file("autoexec.f") is None:
        raise RuntimeError("first-boot image has no autoexec.f to replace")
    cold_autoexec = _linked_cold_autoexec(fs, profile, evidence)
    fs.delete_file("autoexec.f")
    fs.inject_file(
        "autoexec.f",
        cold_autoexec.encode("utf-8"),
        ftype=FTYPE_FORTH,
    )
    fs.save(image)

    _run_in_fresh_process(image, COLD_MARKER, COLD_FAILURES, args.timeout)
    print(
        "Library projection two-process cold acceptance: PASS "
        f"({image}, RID {evidence.rid.hex()}, "
        f"domain {evidence.domain_revision}, digest {evidence.digest.hex()})"
    )
    return 0


if __name__ == "__main__":
    multiprocessing.freeze_support()
    raise SystemExit(main())
