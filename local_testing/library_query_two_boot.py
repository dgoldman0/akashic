#!/usr/bin/env python3
"""Prove Library corpus-query reconstruction across two cold processes.

The first guest provisions three authoritative resources in catalog order.  The
term ``constellation`` occurs only in the first title, the second body, and the
third resource's exact tag; the tagged capture is archived.  A collection names
the first and third resources.  The guest exercises bounded 2+1 corpus paging,
field/lifecycle/kind/media filters, collection filtering, and collection
enumeration, then prints the exact ordered result RIDs.

The parent retains only the serialized MP64FS image and the printed stable RIDs,
replaces ``autoexec.f``, and launches a fresh emulator in a spawned process.  The
cold guest loads the authoritative store, thereby rebuilding activation-local
query state, repeats the same public queries, and proves the same ordered result
sequence and collection result without inheriting guest RAM or dictionary state.
"""

from __future__ import annotations

import argparse
import multiprocessing
import re
import time
import traceback
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
    build_image,
)


PROFILE_NAME: Final = "_library-query-two-cold-processes"
FIRST_MARKER: Final = "LIBRARY QUERY FIRST PASS"
COLD_MARKER: Final = "LIBRARY QUERY COLD PASS"
COMMON_FAILURES: Final = (
    "LIBRARY QUERY ASSERT",
    "EVALUATE input exceeds",
    "EVALUATE depth limit exceeded",
    " ? (not found)",
    "dictionary full",
    "exception",
)
FIRST_FAILURES: Final = (
    "LIBRARY QUERY FIRST FAIL",
    *COMMON_FAILURES,
)
COLD_FAILURES: Final = (
    "LIBRARY QUERY COLD FAIL",
    *COMMON_FAILURES,
)
FIRST_RESULT_RE: Final = re.compile(
    r"LIBRARY QUERY FIRST RESULT ([0-2]) +([0-9A-F]{64})"
)
COLD_RESULT_RE: Final = re.compile(
    r"LIBRARY QUERY COLD RESULT ([0-2]) +([0-9A-F]{64})"
)
FIRST_COLLECTION_RE: Final = re.compile(
    r"LIBRARY QUERY FIRST COLLECTION +([0-9A-F]{64})"
)
COLD_COLLECTION_RE: Final = re.compile(
    r"LIBRARY QUERY COLD COLLECTION +([0-9A-F]{64})"
)


QUERY_PROOF_WORDS = r"""
: _lq-summary  ( index -- summary )
    LIBRARY-QUERY-SUMMARY-SIZE * _lq-summaries + ;

: _lq-collection-summary  ( index -- summary )
    LIBRARY-COLLECTION-SUMMARY-SIZE * _lq-collection-summaries + ;

: _lq-result-rid  ( index -- rid )
    LIB-DIGEST-SIZE * _lq-result-rids + ;

: _lq-base-request  ( lifecycle-mask field-mask -- )
    _lq-request LIBRARY-CORPUS-QUERY-REQUEST-INIT
    _lq-request LIBCQR.FIELD-MASK !
    _lq-request LIBCQR.LIFECYCLE-MASK ! ;

: _lq-term!  ( a u -- )
    _lq-request LIBRARY-CORPUS-QUERY-TERM!
        LIBSTORE-S-OK = _lq-assert
    _lq-request LIBRARY-CORPUS-QUERY-REQUEST-VALID? _lq-assert ;

: _lq-call2  ( -- )
    _lq-request _lq-summaries 2 _lq-store
        LIBRARY-VFS-STORE-QUERY-CORPUS
    _lq-status ! _lq-generation ! _lq-next ! _lq-count ! ;

: _lq-call4  ( -- )
    _lq-request _lq-summaries 4 _lq-store
        LIBRARY-VFS-STORE-QUERY-CORPUS
    _lq-status ! _lq-generation ! _lq-next ! _lq-count ! ;

: _lq-expect-one  ( rid -- )
    _lq-expected-rid !
    _lq-call4
    _lq-status @ LIBSTORE-S-OK = _lq-assert
    _lq-count @ 1 = _lq-assert
    _lq-next @ -1 = _lq-assert
    0 _lq-summary LIBQS.REF RREF.ID
        _lq-expected-rid @ RID= _lq-assert ;

: _lq-all-fields-paged  ( -- )
    _lq-result-rids LIB-DIGEST-SIZE 3 * 0 FILL
    LIBRARY-CORPUS-LIFECYCLE-ALL LIBRARY-CORPUS-FIELD-ALL
        _lq-base-request
    S" constellation" _lq-term!
    _lq-call2
    _lq-status @ LIBSTORE-S-OK = _lq-assert
    _lq-count @ 2 = _lq-assert
    _lq-next @ 2 = _lq-assert
    _lq-generation @ 8 = _lq-assert
    0 _lq-summary LIBQS.REF RREF.ID 0 _lq-result-rid RID-COPY
    1 _lq-summary LIBQS.REF RREF.ID 1 _lq-result-rid RID-COPY

    _lq-generation @ _lq-request LIBCQR.EXPECTED-CATALOG-GENERATION !
    _lq-next @ _lq-request LIBCQR.START-SLOT !
    _lq-request LIBRARY-CORPUS-QUERY-REQUEST-VALID? _lq-assert
    _lq-call2
    _lq-status @ LIBSTORE-S-OK = _lq-assert
    _lq-count @ 1 = _lq-assert
    _lq-next @ -1 = _lq-assert
    _lq-generation @ 8 = _lq-assert
    0 _lq-summary LIBQS.REF RREF.ID 2 _lq-result-rid RID-COPY

    0 _lq-result-rid _lq-rid-a RID= _lq-assert
    1 _lq-result-rid _lq-rid-b RID= _lq-assert
    2 _lq-result-rid _lq-rid-c RID= _lq-assert ;

: _lq-title-proof  ( -- )
    LIBRARY-CORPUS-LIFECYCLE-ACTIVE LIBRARY-CORPUS-FIELD-TITLE
        _lq-base-request
    LIBRARY-CORPUS-KIND-MANAGED _lq-request LIBCQR.KIND-MASK !
    LIBRARY-CORPUS-MEDIA-MARKDOWN _lq-request LIBCQR.MEDIA-MASK !
    S" constellation" _lq-term!
    _lq-rid-a _lq-expect-one ;

: _lq-body-proof  ( -- )
    LIBRARY-CORPUS-LIFECYCLE-ACTIVE LIBRARY-CORPUS-FIELD-BODY
        _lq-base-request
    LIBRARY-CORPUS-KIND-MANAGED _lq-request LIBCQR.KIND-MASK !
    LIBRARY-CORPUS-MEDIA-PLAIN _lq-request LIBCQR.MEDIA-MASK !
    S" constellation" _lq-term!
    _lq-rid-b _lq-expect-one ;

: _lq-tag-proof  ( -- )
    LIBRARY-CORPUS-LIFECYCLE-ARCHIVED LIBRARY-CORPUS-FIELD-TAGS
        _lq-base-request
    LIBRARY-CORPUS-KIND-CAPTURE _lq-request LIBCQR.KIND-MASK !
    LIBRARY-CORPUS-MEDIA-MARKDOWN _lq-request LIBCQR.MEDIA-MASK !
    S" constellation" _lq-term!
    _lq-rid-c _lq-expect-one ;

: _lq-collection-filter-proof  ( -- )
    LIBRARY-CORPUS-LIFECYCLE-ALL LIBRARY-CORPUS-FIELD-ALL
        _lq-base-request
    _lq-collection-rid _lq-request LIBRARY-CORPUS-QUERY-COLLECTION!
        LIBSTORE-S-OK = _lq-assert
    _lq-request LIBRARY-CORPUS-QUERY-REQUEST-VALID? _lq-assert
    _lq-call4
    _lq-status @ LIBSTORE-S-OK = _lq-assert
    _lq-count @ 2 = _lq-assert
    _lq-next @ -1 = _lq-assert
    _lq-generation @ 8 = _lq-assert
    0 _lq-summary LIBQS.REF RREF.ID _lq-rid-a RID= _lq-assert
    1 _lq-summary LIBQS.REF RREF.ID _lq-rid-c RID= _lq-assert ;

: _lq-collection-list-proof  ( -- )
    0 0 _lq-collection-summaries 4 _lq-store
        LIBRARY-VFS-STORE-QUERY-COLLECTIONS
    _lq-status ! _lq-generation ! _lq-next ! _lq-count !
    _lq-status @ LIBSTORE-S-OK = _lq-assert
    _lq-count @ 1 = _lq-assert
    _lq-next @ -1 = _lq-assert
    _lq-generation @ 8 = _lq-assert
    0 _lq-collection-summary LIBCS.REF RREF.ID
        _lq-collection-rid RID= _lq-assert
    0 _lq-collection-summary LIBCS.REVISION @ 1 = _lq-assert
    0 _lq-collection-summary LIBCS.MEMBER-N @ 2 = _lq-assert
    0 _lq-collection-summary LIBCS-TITLE$
        S" Cold query pair" COMPARE 0= _lq-assert ;

: _lq-query-proof  ( -- )
    _lq-all-fields-paged
    _lq-title-proof
    _lq-body-proof
    _lq-tag-proof
    _lq-collection-filter-proof
    _lq-collection-list-proof ;
"""


FIRST_AUTOEXEC = rf"""\ autoexec.f - first Library milestone-three query boot
ENTER-USERLAND
REQUIRE library/vfs-store.f
REQUIRE utils/fs/drivers/vfs-mp64fs.f

VARIABLE _lq-fails
VARIABLE _lq-checks
VARIABLE _lq-vfs
VARIABLE _lq-status
VARIABLE _lq-count
VARIABLE _lq-next
VARIABLE _lq-generation
VARIABLE _lq-expected-rid

CREATE _lq-arena-id LIB-DIGEST-SIZE ALLOT
CREATE _lq-key-a LIB-OPERATION-KEY-SIZE ALLOT
CREATE _lq-key-b LIB-OPERATION-KEY-SIZE ALLOT
CREATE _lq-key-c LIB-OPERATION-KEY-SIZE ALLOT
CREATE _lq-collection-key LIB-OPERATION-KEY-SIZE ALLOT
CREATE _lq-rid-a LIB-DIGEST-SIZE ALLOT
CREATE _lq-rid-b LIB-DIGEST-SIZE ALLOT
CREATE _lq-rid-c LIB-DIGEST-SIZE ALLOT
CREATE _lq-collection-rid LIB-DIGEST-SIZE ALLOT
CREATE _lq-members LIB-DIGEST-SIZE 2 * ALLOT
CREATE _lq-managed-request LIBRARY-MANAGED-CREATE-REQUEST-SIZE ALLOT
CREATE _lq-capture-request LIBRARY-CAPTURE-IMPORT-REQUEST-SIZE ALLOT
CREATE _lq-collection-request LIBRARY-COLLECTION-CREATE-REQUEST-SIZE ALLOT
CREATE _lq-metadata LIBRARY-METADATA-SIZE ALLOT
CREATE _lq-origin LIB-ORIGIN-SIZE ALLOT
CREATE _lq-entry LIB-ENTRY-SIZE ALLOT
CREATE _lq-collection-view LIBRARY-COLLECTION-VIEW-SIZE ALLOT
CREATE _lq-request LIBRARY-CORPUS-QUERY-REQUEST-SIZE ALLOT
CREATE _lq-summaries LIBRARY-QUERY-SUMMARY-SIZE 4 * ALLOT
CREATE _lq-result-rids LIB-DIGEST-SIZE 3 * ALLOT
CREATE _lq-collection-summaries LIBRARY-COLLECTION-SUMMARY-SIZE 4 * ALLOT
CREATE _lq-store LIBRARY-VFS-STORE-SIZE ALLOT

: _lq-assert  ( flag -- )
    1 _lq-checks +!
    0= IF
        1 _lq-fails +!
        ." LIBRARY QUERY ASSERT " _lq-checks @ . CR
    THEN ;

: _lq-hex-digit  ( nibble -- )
    DUP 10 < IF [CHAR] 0 + ELSE 10 - [CHAR] A + THEN EMIT ;

: _lq-hex-byte  ( byte -- )
    DUP 16 / _lq-hex-digit 15 AND _lq-hex-digit ;

: _lq-rid.  ( rid -- )
    LIB-DIGEST-SIZE 0 DO DUP I + C@ _lq-hex-byte LOOP DROP ;

{QUERY_PROOF_WORDS}

: _lq-create-a  ( -- )
    _lq-managed-request LIBRARY-MANAGED-CREATE-REQUEST-INIT
    1 _lq-managed-request LIBMCR.EXPECTED-CATALOG-GENERATION !
    LIB-MEDIA-TEXT-MARKDOWN _lq-managed-request LIBMCR.MEDIA !
    _lq-key-a _lq-managed-request LIBRARY-MANAGED-CREATE-OPERATION-KEY!
        LIBSTORE-S-OK = _lq-assert
    S" provisional atlas" _lq-managed-request
        LIBRARY-MANAGED-CREATE-TITLE! LIBSTORE-S-OK = _lq-assert
    S" alpha body without the shared search word" _lq-managed-request
        LIBRARY-MANAGED-CREATE-CONTENT! LIBSTORE-S-OK = _lq-assert
    _lq-managed-request LIBRARY-MANAGED-CREATE-REQUEST-VALID? _lq-assert
    _lq-managed-request _lq-entry _lq-store
        LIBRARY-VFS-STORE-CREATE-MANAGED
        LIBSTORE-S-OK = _lq-assert
    _lq-entry LIBE.ID _lq-rid-a RID-COPY

    _lq-metadata LIBRARY-METADATA-INIT
    S" constellation atlas" _lq-metadata
        LIBRARY-METADATA-TITLE! LIBSTORE-S-OK = _lq-assert
    S" alpha" 0 _lq-metadata LIBRARY-METADATA-TAG!
        LIBSTORE-S-OK = _lq-assert
    _lq-metadata LIBRARY-METADATA-VALID? _lq-assert
    _lq-rid-a 1 _lq-metadata _lq-entry _lq-store
        LIBRARY-VFS-STORE-REPLACE-METADATA
        LIBSTORE-S-OK = _lq-assert
    _lq-entry LIBE.DOMAIN-REVISION @ 2 = _lq-assert ;

: _lq-create-b  ( -- )
    _lq-managed-request LIBRARY-MANAGED-CREATE-REQUEST-INIT
    3 _lq-managed-request LIBMCR.EXPECTED-CATALOG-GENERATION !
    LIB-MEDIA-TEXT-PLAIN _lq-managed-request LIBMCR.MEDIA !
    _lq-key-b _lq-managed-request LIBRARY-MANAGED-CREATE-OPERATION-KEY!
        LIBSTORE-S-OK = _lq-assert
    S" plain field log" _lq-managed-request
        LIBRARY-MANAGED-CREATE-TITLE! LIBSTORE-S-OK = _lq-assert
    S" the body carries constellation and no metadata tag" _lq-managed-request
        LIBRARY-MANAGED-CREATE-CONTENT! LIBSTORE-S-OK = _lq-assert
    _lq-managed-request LIBRARY-MANAGED-CREATE-REQUEST-VALID? _lq-assert
    _lq-managed-request _lq-entry _lq-store
        LIBRARY-VFS-STORE-CREATE-MANAGED
        LIBSTORE-S-OK = _lq-assert
    _lq-entry LIBE.ID _lq-rid-b RID-COPY
    _lq-entry LIBE.DOMAIN-REVISION @ 1 = _lq-assert ;

: _lq-build-origin  ( -- )
    _lq-origin LIB-ORIGIN-INIT
    LIB-ORIGIN-VFS-SNAPSHOT _lq-origin LIBO.KIND !
    S" /cold/query-capture.md" DUP
        _lq-origin LIBO.VFS LIBV.PATH-U !
        _lq-origin LIBO.VFS LIBV.PATH SWAP CMOVE
    S" archived capture body without the shared token" DUP
        _lq-origin LIBO.VFS LIBV.CONTENT-U !
        _lq-origin LIBO.VFS LIBV.CONTENT-DIGEST SHA3-256-HASH
    QLOC-DK-PROJECTION-CONTENT _lq-origin LIBO.VFS LIBV.DIGEST-KIND !
    _lq-origin LIB-ORIGIN-VALID? _lq-assert ;

: _lq-create-c  ( -- )
    _lq-build-origin
    _lq-capture-request LIBRARY-CAPTURE-IMPORT-REQUEST-INIT
    4 _lq-capture-request LIBCIR.EXPECTED-CATALOG-GENERATION !
    LIB-MEDIA-TEXT-MARKDOWN _lq-capture-request LIBCIR.MEDIA !
    _lq-key-c _lq-capture-request LIBRARY-CAPTURE-IMPORT-OPERATION-KEY!
        LIBSTORE-S-OK = _lq-assert
    S" capture card" _lq-capture-request
        LIBRARY-CAPTURE-IMPORT-TITLE! LIBSTORE-S-OK = _lq-assert
    S" archived capture body without the shared token" _lq-capture-request
        LIBRARY-CAPTURE-IMPORT-CONTENT! LIBSTORE-S-OK = _lq-assert
    _lq-origin _lq-capture-request LIBRARY-CAPTURE-IMPORT-ORIGIN!
        LIBSTORE-S-OK = _lq-assert
    _lq-capture-request LIBRARY-CAPTURE-IMPORT-REQUEST-VALID? _lq-assert
    _lq-capture-request _lq-entry _lq-store
        LIBRARY-VFS-STORE-IMPORT-CAPTURE
        LIBSTORE-S-OK = _lq-assert
    _lq-entry LIBE.ID _lq-rid-c RID-COPY

    _lq-metadata LIBRARY-METADATA-INIT
    S" archived observatory card" _lq-metadata
        LIBRARY-METADATA-TITLE! LIBSTORE-S-OK = _lq-assert
    S" constellation" 0 _lq-metadata LIBRARY-METADATA-TAG!
        LIBSTORE-S-OK = _lq-assert
    _lq-metadata LIBRARY-METADATA-VALID? _lq-assert
    _lq-rid-c 1 _lq-metadata _lq-entry _lq-store
        LIBRARY-VFS-STORE-REPLACE-METADATA
        LIBSTORE-S-OK = _lq-assert
    _lq-rid-c 2 _lq-entry _lq-store LIBRARY-VFS-STORE-ARCHIVE
        LIBSTORE-S-OK = _lq-assert
    _lq-entry LIBE.DOMAIN-REVISION @ 3 = _lq-assert
    _lq-entry LIBE.LIFECYCLE @ LIB-LIFECYCLE-ARCHIVED = _lq-assert ;

: _lq-create-collection  ( -- )
    _lq-rid-a _lq-members RID-COPY
    _lq-rid-c _lq-members LIB-DIGEST-SIZE + RID-COPY
    _lq-collection-request LIBRARY-COLLECTION-CREATE-REQUEST-INIT
    7 _lq-collection-request LIBCCR.EXPECTED-CATALOG-GENERATION !
    _lq-collection-key _lq-collection-request
        LIBRARY-COLLECTION-CREATE-OPERATION-KEY!
        LIBSTORE-S-OK = _lq-assert
    S" Cold query pair" _lq-collection-request
        LIBRARY-COLLECTION-CREATE-TITLE! LIBSTORE-S-OK = _lq-assert
    _lq-members 2 _lq-collection-request
        LIBRARY-COLLECTION-CREATE-MEMBERS!
        LIBSTORE-S-OK = _lq-assert
    _lq-collection-request LIBRARY-COLLECTION-CREATE-REQUEST-VALID?
        _lq-assert
    _lq-collection-request _lq-collection-view _lq-store
        LIBRARY-VFS-STORE-CREATE-COLLECTION
        LIBSTORE-S-OK = _lq-assert
    _lq-collection-view LIBCV.ID _lq-collection-rid RID-COPY
    _lq-collection-view LIBCV.MEMBER-N @ 2 = _lq-assert ;

: _lq-first-run  ( -- )
    0 _lq-fails ! 0 _lq-checks !
    _lq-arena-id LIB-DIGEST-SIZE 0xA7 FILL
    _lq-key-a LIB-OPERATION-KEY-SIZE 0x31 FILL
    _lq-key-b LIB-OPERATION-KEY-SIZE 0x42 FILL
    _lq-key-c LIB-OPERATION-KEY-SIZE 0x53 FILL
    _lq-collection-key LIB-OPERATION-KEY-SIZE 0x64 FILL
    2097152 A-XMEM ARENA-NEW IF -7811 THROW THEN
    VMP-NEW DUP _lq-vfs ! DUP 0<> _lq-assert
    DUP VMP-INIT 0= _lq-assert VFS-USE
    _lq-vfs @ _lq-store LIBRARY-VFS-STORE-INIT
        LIBSTORE-S-OK = _lq-assert
    _lq-store LIBRARY-VFS-STORE-LOAD LIBSTORE-S-ABSENT = _lq-assert
    _lq-arena-id _lq-store LIBRARY-VFS-STORE-PROVISION
        LIBSTORE-S-OK = _lq-assert
    _lq-create-a
    _lq-create-b
    _lq-create-c
    _lq-create-collection
    _lq-store LIBRARY-VFS-STORE.GENERATION @ 8 = _lq-assert
    _lq-query-proof
    _lq-vfs @ VFS-SYNC 0= _lq-assert
    _lq-fails @ 0= IF
        ." LIBRARY QUERY FIRST RESULT 0 " 0 _lq-result-rid _lq-rid. CR
        ." LIBRARY QUERY FIRST RESULT 1 " 1 _lq-result-rid _lq-rid. CR
        ." LIBRARY QUERY FIRST RESULT 2 " 2 _lq-result-rid _lq-rid. CR
        ." LIBRARY QUERY FIRST COLLECTION " _lq-collection-rid _lq-rid. CR
        ." LIBRARY QUERY FIRST PASS " _lq-checks @ . CR
    ELSE
        ." LIBRARY QUERY FIRST FAIL " _lq-fails @ .
            ." / " _lq-checks @ . CR
    THEN ;

_lq-first-run
"""


def _rid_definition(rid: bytes) -> str:
    """Return comma-compiled Forth bytes for one exact Library RID."""
    if len(rid) != 32:
        raise ValueError("a Library RID must contain exactly 32 bytes")
    return "\n".join(
        " ".join(f"0x{byte:02X} C," for byte in rid[offset : offset + 8])
        for offset in range(0, len(rid), 8)
    )


def _cold_autoexec(results: tuple[bytes, bytes, bytes], collection: bytes) -> str:
    rid_a, rid_b, rid_c = (_rid_definition(rid) for rid in results)
    collection_rid = _rid_definition(collection)
    return rf"""\ autoexec.f - cold Library milestone-three query rebuild boot
ENTER-USERLAND
REQUIRE library/vfs-store.f
REQUIRE utils/fs/drivers/vfs-mp64fs.f

VARIABLE _lq-fails
VARIABLE _lq-checks
VARIABLE _lq-vfs
VARIABLE _lq-status
VARIABLE _lq-count
VARIABLE _lq-next
VARIABLE _lq-generation
VARIABLE _lq-expected-rid

CREATE _lq-rid-a {rid_a}
CREATE _lq-rid-b {rid_b}
CREATE _lq-rid-c {rid_c}
CREATE _lq-collection-rid {collection_rid}
CREATE _lq-request LIBRARY-CORPUS-QUERY-REQUEST-SIZE ALLOT
CREATE _lq-summaries LIBRARY-QUERY-SUMMARY-SIZE 4 * ALLOT
CREATE _lq-result-rids LIB-DIGEST-SIZE 3 * ALLOT
CREATE _lq-collection-summaries LIBRARY-COLLECTION-SUMMARY-SIZE 4 * ALLOT
CREATE _lq-store LIBRARY-VFS-STORE-SIZE ALLOT

: _lq-assert  ( flag -- )
    1 _lq-checks +!
    0= IF
        1 _lq-fails +!
        ." LIBRARY QUERY ASSERT " _lq-checks @ . CR
    THEN ;

: _lq-hex-digit  ( nibble -- )
    DUP 10 < IF [CHAR] 0 + ELSE 10 - [CHAR] A + THEN EMIT ;

: _lq-hex-byte  ( byte -- )
    DUP 16 / _lq-hex-digit 15 AND _lq-hex-digit ;

: _lq-rid.  ( rid -- )
    LIB-DIGEST-SIZE 0 DO DUP I + C@ _lq-hex-byte LOOP DROP ;

{QUERY_PROOF_WORDS}

: _lq-cold-run  ( -- )
    0 _lq-fails ! 0 _lq-checks !
    2097152 A-XMEM ARENA-NEW IF -7812 THROW THEN
    VMP-NEW DUP _lq-vfs ! DUP 0<> _lq-assert
    DUP VMP-INIT 0= _lq-assert VFS-USE
    _lq-vfs @ _lq-store LIBRARY-VFS-STORE-INIT
        LIBSTORE-S-OK = _lq-assert
    _lq-store LIBRARY-VFS-STORE-LOAD LIBSTORE-S-OK = _lq-assert
    _lq-store LIBRARY-VFS-STORE.GENERATION @ 8 = _lq-assert
    _lq-query-proof
    _lq-vfs @ VFS-SYNC 0= _lq-assert
    _lq-fails @ 0= IF
        ." LIBRARY QUERY COLD RESULT 0 " 0 _lq-result-rid _lq-rid. CR
        ." LIBRARY QUERY COLD RESULT 1 " 1 _lq-result-rid _lq-rid. CR
        ." LIBRARY QUERY COLD RESULT 2 " 2 _lq-result-rid _lq-rid. CR
        ." LIBRARY QUERY COLD COLLECTION " _lq-collection-rid _lq-rid. CR
        ." LIBRARY QUERY COLD PASS " _lq-checks @ . CR
    ELSE
        ." LIBRARY QUERY COLD FAIL " _lq-fails @ .
            ." / " _lq-checks @ . CR
    THEN ;

_lq-cold-run
"""


def _profile() -> Profile:
    """Return the exact build closure used by both isolated processes."""
    return Profile(
        roots=(
            "library/vfs-store.f",
            "utils/fs/drivers/vfs-mp64fs.f",
        ),
        resources=(),
        autoexec=FIRST_AUTOEXEC,
        ready_markers=(FIRST_MARKER,),
        stable_markers=(FIRST_MARKER,),
        failure_markers=FIRST_FAILURES,
        include_large_sample=False,
        total_sectors=8192,
    )


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
        cols=112,
        rows=42,
        batch_steps=500_000,
    ) as session:
        session.boot()
        while time.monotonic() < deadline and steps < 20_000_000_000:
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
        raise RuntimeError(f"timed out waiting for {marker!r}\n{raw[-5000:]}")


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


def _extract_results(
    pattern: re.Pattern[str], output: str, phase: str
) -> tuple[bytes, bytes, bytes]:
    """Extract one unambiguous three-RID ordered result sequence."""
    found: dict[int, bytes] = {}
    for index_text, rid_text in pattern.findall(output):
        index = int(index_text)
        rid = bytes.fromhex(rid_text)
        prior = found.get(index)
        if prior is not None and prior != rid:
            raise RuntimeError(f"{phase} printed conflicting result RID {index}")
        found[index] = rid
    if set(found) != {0, 1, 2}:
        raise RuntimeError(f"{phase} did not print its complete ordered RID sequence")
    return found[0], found[1], found[2]


def _extract_collection(
    pattern: re.Pattern[str], output: str, phase: str
) -> bytes:
    """Extract one unambiguous collection RID from guest output."""
    matches = {bytes.fromhex(item) for item in pattern.findall(output)}
    if len(matches) != 1:
        raise RuntimeError(f"{phase} did not print one unambiguous collection RID")
    return matches.pop()


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--image",
        type=Path,
        default=Path("/tmp/akashic-library-query-two-boot.img"),
    )
    parser.add_argument("--timeout", type=float, default=600.0)
    args = parser.parse_args()
    if args.timeout <= 0:
        parser.error("--timeout must be greater than zero")

    previous = PROFILES.get(PROFILE_NAME)
    PROFILES[PROFILE_NAME] = _profile()
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
    first_results = _extract_results(FIRST_RESULT_RE, first_output, "first boot")
    first_collection = _extract_collection(
        FIRST_COLLECTION_RE, first_output, "first boot"
    )
    print(
        "Library query first-boot evidence: "
        f"image={image}, ordered={[rid.hex() for rid in first_results]}, "
        f"collection={first_collection.hex()}"
    )

    fs = MP64FS(bytearray(first_disk))
    if fs.find_file("autoexec.f") is None:
        raise RuntimeError("first-boot image has no autoexec.f to replace")
    fs.delete_file("autoexec.f")
    fs.inject_file(
        "autoexec.f",
        _cold_autoexec(first_results, first_collection).encode("utf-8"),
        ftype=FTYPE_FORTH,
    )
    fs.save(image)

    _, cold_output = _run_in_fresh_process(
        image, COLD_MARKER, COLD_FAILURES, args.timeout
    )
    cold_results = _extract_results(COLD_RESULT_RE, cold_output, "cold boot")
    cold_collection = _extract_collection(
        COLD_COLLECTION_RE, cold_output, "cold boot"
    )
    if cold_results != first_results:
        raise RuntimeError("cold query result order differs from first boot")
    if cold_collection != first_collection:
        raise RuntimeError("cold collection query differs from first boot")

    print(
        "Library query two-process cold acceptance: PASS "
        f"({image}, ordered {[rid.hex() for rid in cold_results]}, "
        f"collection {cold_collection.hex()})"
    )
    return 0


if __name__ == "__main__":
    multiprocessing.freeze_support()
    raise SystemExit(main())
