#!/usr/bin/env python3
"""Prove the Gate 4 milestone-two Library slice across two cold processes.

The first guest creates a managed document, replaces its content five times,
archives it, imports an immutable capture, and creates a collection containing
both resources.  It prints the three owner-generated RIDs as evidence.  The
parent retains only the serialized MP64FS image and those RID bytes, replaces
``autoexec.f``, and starts a fresh emulator process.  The cold guest reloads
the public Library owner and proves archived exact reads, four-revision
retention and ``GONE``, durable receipt lookup, capture readback, and exact
collection membership without inheriting any guest RAM or dictionary state.
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


PROFILE_NAME: Final = "_library-lifecycle-two-cold-processes"
FIRST_MARKER: Final = "LIBRARY LIFECYCLE FIRST BOOT PASS"
COLD_MARKER: Final = "LIBRARY LIFECYCLE COLD BOOT PASS"
FIRST_FAILURES: Final = (
    "LIBRARY LIFECYCLE FIRST BOOT FAIL",
    "LIBRARY LIFECYCLE FIRST ASSERT",
    "EVALUATE input exceeds",
    "EVALUATE depth limit exceeded",
    " ? (not found)",
    "dictionary full",
    "exception",
)
COLD_FAILURES: Final = (
    "LIBRARY LIFECYCLE COLD BOOT FAIL",
    "LIBRARY LIFECYCLE COLD ASSERT",
    "EVALUATE input exceeds",
    "EVALUATE depth limit exceeded",
    " ? (not found)",
    "dictionary full",
    "exception",
)
MANAGED_RID_RE: Final = re.compile(
    r"LIBRARY LIFECYCLE FIRST MANAGED RID +([0-9A-F]{64})"
)
CAPTURE_RID_RE: Final = re.compile(
    r"LIBRARY LIFECYCLE FIRST CAPTURE RID +([0-9A-F]{64})"
)
COLLECTION_RID_RE: Final = re.compile(
    r"LIBRARY LIFECYCLE FIRST COLLECTION RID +([0-9A-F]{64})"
)


FIRST_AUTOEXEC = r"""\ autoexec.f - first Library milestone-two persistence boot
ENTER-USERLAND
REQUIRE library/vfs-store.f
REQUIRE utils/fs/drivers/vfs-mp64fs.f

VARIABLE _llf-fails
VARIABLE _llf-checks
VARIABLE _llf-vfs
VARIABLE _llf-expected
VARIABLE _llf-input-a
VARIABLE _llf-input-u
VARIABLE _llf-status

CREATE _llf-arena-id LIB-DIGEST-SIZE ALLOT
CREATE _llf-managed-key LIB-OPERATION-KEY-SIZE ALLOT
CREATE _llf-capture-key LIB-OPERATION-KEY-SIZE ALLOT
CREATE _llf-collection-key LIB-OPERATION-KEY-SIZE ALLOT
CREATE _llf-managed-rid LIB-DIGEST-SIZE ALLOT
CREATE _llf-capture-rid LIB-DIGEST-SIZE ALLOT
CREATE _llf-collection-rid LIB-DIGEST-SIZE ALLOT
CREATE _llf-members LIB-DIGEST-SIZE 2 * ALLOT
CREATE _llf-managed-request LIBRARY-MANAGED-CREATE-REQUEST-SIZE ALLOT
CREATE _llf-capture-request LIBRARY-CAPTURE-IMPORT-REQUEST-SIZE ALLOT
CREATE _llf-collection-request LIBRARY-COLLECTION-CREATE-REQUEST-SIZE ALLOT
CREATE _llf-origin LIB-ORIGIN-SIZE ALLOT
CREATE _llf-entry LIB-ENTRY-SIZE ALLOT
CREATE _llf-view LIBRARY-COLLECTION-VIEW-SIZE ALLOT
CREATE _llf-store LIBRARY-VFS-STORE-SIZE ALLOT

: _llf-assert  ( flag -- )
    1 _llf-checks +!
    0= IF
        1 _llf-fails +!
        ." LIBRARY LIFECYCLE FIRST ASSERT " _llf-checks @ . CR
    THEN ;

: _llf-hex-digit  ( nibble -- )
    DUP 10 < IF [CHAR] 0 + ELSE 10 - [CHAR] A + THEN EMIT ;

: _llf-hex-byte  ( byte -- )
    DUP 16 / _llf-hex-digit 15 AND _llf-hex-digit ;

: _llf-rid.  ( rid -- )
    LIB-DIGEST-SIZE 0 DO DUP I + C@ _llf-hex-byte LOOP DROP ;

: _llf-replace  ( expected-domain a u -- )
    _llf-input-u ! _llf-input-a ! _llf-expected !
    _llf-managed-rid _llf-expected @ _llf-input-a @ _llf-input-u @
        _llf-entry _llf-store LIBRARY-VFS-STORE-REPLACE-MANAGED
        LIBSTORE-S-OK = _llf-assert
    _llf-entry LIBE.DOMAIN-REVISION @
        _llf-expected @ 1+ = _llf-assert ;

: _llf-create-managed  ( -- )
    _llf-managed-request LIBRARY-MANAGED-CREATE-REQUEST-INIT
    1 _llf-managed-request LIBMCR.EXPECTED-CATALOG-GENERATION !
    LIB-MEDIA-TEXT-MARKDOWN _llf-managed-request LIBMCR.MEDIA !
    _llf-managed-key _llf-managed-request
        LIBRARY-MANAGED-CREATE-OPERATION-KEY!
        LIBSTORE-S-OK = _llf-assert
    S" Cold lifecycle document" _llf-managed-request
        LIBRARY-MANAGED-CREATE-TITLE! LIBSTORE-S-OK = _llf-assert
    S" revision one" _llf-managed-request
        LIBRARY-MANAGED-CREATE-CONTENT! LIBSTORE-S-OK = _llf-assert
    _llf-managed-request LIBRARY-MANAGED-CREATE-REQUEST-VALID?
        _llf-assert
    _llf-managed-request _llf-entry _llf-store
        LIBRARY-VFS-STORE-CREATE-MANAGED
        LIBSTORE-S-OK = _llf-assert
    _llf-entry LIBE.ID _llf-managed-rid RID-COPY
    _llf-entry LIBE.DOMAIN-REVISION @ 1 = _llf-assert
    _llf-entry LIBE.CURRENT-CONTENT-REVISION @ 1 = _llf-assert ;

: _llf-replace-and-archive  ( -- )
    1 S" revision two" _llf-replace
    2 S" revision three" _llf-replace
    3 S" revision four" _llf-replace
    4 S" revision five" _llf-replace
    5 S" revision six" _llf-replace
    _llf-entry LIBE.CURRENT-CONTENT-REVISION @ 6 = _llf-assert
    _llf-entry LIBE.OLDEST-CONTENT-REVISION @ 3 = _llf-assert
    _llf-managed-rid 6 _llf-entry _llf-store
        LIBRARY-VFS-STORE-ARCHIVE LIBSTORE-S-OK = _llf-assert
    _llf-entry LIBE.DOMAIN-REVISION @ 7 = _llf-assert
    _llf-entry LIBE.LIFECYCLE @ LIB-LIFECYCLE-ARCHIVED = _llf-assert ;

: _llf-build-origin  ( -- )
    _llf-origin LIB-ORIGIN-INIT
    LIB-ORIGIN-VFS-SNAPSHOT _llf-origin LIBO.KIND !
    S" /cold/frozen-capture.md" DUP
        _llf-origin LIBO.VFS LIBV.PATH-U !
        _llf-origin LIBO.VFS LIBV.PATH SWAP CMOVE
    S" frozen capture bytes" DUP
        _llf-origin LIBO.VFS LIBV.CONTENT-U !
        _llf-origin LIBO.VFS LIBV.CONTENT-DIGEST SHA3-256-HASH
    QLOC-DK-PROJECTION-CONTENT
        _llf-origin LIBO.VFS LIBV.DIGEST-KIND !
    _llf-origin LIB-ORIGIN-VALID? _llf-assert ;

: _llf-import-capture  ( -- )
    _llf-build-origin
    _llf-capture-request LIBRARY-CAPTURE-IMPORT-REQUEST-INIT
    8 _llf-capture-request LIBCIR.EXPECTED-CATALOG-GENERATION !
    LIB-MEDIA-TEXT-MARKDOWN _llf-capture-request LIBCIR.MEDIA !
    _llf-capture-key _llf-capture-request
        LIBRARY-CAPTURE-IMPORT-OPERATION-KEY!
        LIBSTORE-S-OK = _llf-assert
    S" Frozen cold capture" _llf-capture-request
        LIBRARY-CAPTURE-IMPORT-TITLE! LIBSTORE-S-OK = _llf-assert
    S" frozen capture bytes" _llf-capture-request
        LIBRARY-CAPTURE-IMPORT-CONTENT! LIBSTORE-S-OK = _llf-assert
    _llf-origin _llf-capture-request LIBRARY-CAPTURE-IMPORT-ORIGIN!
        LIBSTORE-S-OK = _llf-assert
    _llf-capture-request LIBRARY-CAPTURE-IMPORT-REQUEST-VALID?
        _llf-assert
    _llf-capture-request _llf-entry _llf-store
        LIBRARY-VFS-STORE-IMPORT-CAPTURE
        LIBSTORE-S-OK = _llf-assert
    _llf-entry LIBE.ID _llf-capture-rid RID-COPY
    _llf-entry LIBE.KIND @ LIB-KIND-CAPTURE = _llf-assert
    _llf-entry LIBE.DOMAIN-REVISION @ 1 = _llf-assert ;

: _llf-create-collection  ( -- )
    _llf-managed-rid _llf-members RID-COPY
    _llf-capture-rid _llf-members LIB-DIGEST-SIZE + RID-COPY
    _llf-collection-request LIBRARY-COLLECTION-CREATE-REQUEST-INIT
    9 _llf-collection-request LIBCCR.EXPECTED-CATALOG-GENERATION !
    _llf-collection-key _llf-collection-request
        LIBRARY-COLLECTION-CREATE-OPERATION-KEY!
        LIBSTORE-S-OK = _llf-assert
    S" Cold milestone resources" _llf-collection-request
        LIBRARY-COLLECTION-CREATE-TITLE! LIBSTORE-S-OK = _llf-assert
    _llf-members 2 _llf-collection-request
        LIBRARY-COLLECTION-CREATE-MEMBERS!
        LIBSTORE-S-OK = _llf-assert
    _llf-collection-request LIBRARY-COLLECTION-CREATE-REQUEST-VALID?
        _llf-assert
    _llf-collection-request _llf-view _llf-store
        LIBRARY-VFS-STORE-CREATE-COLLECTION
        DUP _llf-status ! LIBSTORE-S-OK = _llf-assert
    _llf-view LIBCV.ID _llf-collection-rid RID-COPY
    _llf-view LIBCV.REVISION @ 1 = _llf-assert
    _llf-view LIBCV.MEMBER-N @ 2 = _llf-assert
    0 _llf-view LIBCV-MEMBER _llf-managed-rid RID= _llf-assert
    1 _llf-view LIBCV-MEMBER _llf-capture-rid RID= _llf-assert ;

: _llf-run  ( -- )
    0 _llf-fails ! 0 _llf-checks !
    _llf-arena-id LIB-DIGEST-SIZE 0xA6 FILL
    _llf-managed-key LIB-OPERATION-KEY-SIZE 0x51 FILL
    _llf-capture-key LIB-OPERATION-KEY-SIZE 0x62 FILL
    _llf-collection-key LIB-OPERATION-KEY-SIZE 0x73 FILL
    2097152 A-XMEM ARENA-NEW IF -7801 THROW THEN
    VMP-NEW DUP _llf-vfs ! DUP 0<> _llf-assert
    DUP VMP-INIT 0= _llf-assert VFS-USE
    _llf-vfs @ _llf-store LIBRARY-VFS-STORE-INIT
        LIBSTORE-S-OK = _llf-assert
    _llf-store LIBRARY-VFS-STORE-LOAD
        LIBSTORE-S-ABSENT = _llf-assert
    _llf-arena-id _llf-store LIBRARY-VFS-STORE-PROVISION
        LIBSTORE-S-OK = _llf-assert
    _llf-create-managed
    _llf-replace-and-archive
    _llf-import-capture
    _llf-create-collection
    _llf-store LIBRARY-VFS-STORE.GENERATION @ 10 = _llf-assert
    _llf-vfs @ VFS-SYNC 0= _llf-assert
    _llf-fails @ 0= IF
        ." LIBRARY LIFECYCLE FIRST MANAGED RID "
            _llf-managed-rid _llf-rid. CR
        ." LIBRARY LIFECYCLE FIRST CAPTURE RID "
            _llf-capture-rid _llf-rid. CR
        ." LIBRARY LIFECYCLE FIRST COLLECTION RID "
            _llf-collection-rid _llf-rid. CR
        ." LIBRARY LIFECYCLE FIRST BOOT PASS " _llf-checks @ . CR
    ELSE
        ." LIBRARY LIFECYCLE FIRST COLLECTION STATUS "
            _llf-status @ . CR
        ." LIBRARY LIFECYCLE FIRST BOOT FAIL "
            _llf-fails @ . ." / " _llf-checks @ . CR
    THEN ;

_llf-run
"""


def _rid_definition(rid: bytes) -> str:
    """Return comma-compiled Forth bytes for one exact Library RID."""
    if len(rid) != 32:
        raise ValueError("a Library RID must contain exactly 32 bytes")
    return "\n".join(
        " ".join(f"0x{byte:02X} C," for byte in rid[offset : offset + 8])
        for offset in range(0, len(rid), 8)
    )


def _cold_autoexec(managed_rid: bytes, capture_rid: bytes, collection_rid: bytes) -> str:
    managed_cells = _rid_definition(managed_rid)
    capture_cells = _rid_definition(capture_rid)
    collection_cells = _rid_definition(collection_rid)
    return rf"""\ autoexec.f - cold Library milestone-two public readback
ENTER-USERLAND
REQUIRE library/vfs-store.f
REQUIRE utils/fs/drivers/vfs-mp64fs.f

VARIABLE _llc-fails
VARIABLE _llc-checks
VARIABLE _llc-vfs
VARIABLE _llc-status
VARIABLE _llc-required

CREATE _llc-managed-rid {managed_cells}
CREATE _llc-capture-rid {capture_cells}
CREATE _llc-collection-rid {collection_cells}
CREATE _llc-managed-key LIB-OPERATION-KEY-SIZE ALLOT
CREATE _llc-capture-key LIB-OPERATION-KEY-SIZE ALLOT
CREATE _llc-rid-out LIB-DIGEST-SIZE ALLOT
CREATE _llc-receipt LIB-RECEIPT-SIZE ALLOT
CREATE _llc-entry LIB-ENTRY-SIZE ALLOT
CREATE _llc-content LIB-CONTENT-SIZE ALLOT
CREATE _llc-history
    LIBRARY-REVISION-SUMMARY-SIZE LIB-RETAINED-REVISION-MAX * ALLOT
CREATE _llc-view LIBRARY-COLLECTION-VIEW-SIZE ALLOT
CREATE _llc-bytes 64 ALLOT
CREATE _llc-store LIBRARY-VFS-STORE-SIZE ALLOT

: _llc-assert  ( flag -- )
    1 _llc-checks +!
    0= IF
        1 _llc-fails +!
        ." LIBRARY LIFECYCLE COLD ASSERT " _llc-checks @ . CR
    THEN ;

: _llc-summary  ( index -- summary )
    LIBRARY-REVISION-SUMMARY-SIZE * _llc-history + ;

: _llc-read-managed  ( -- )
    _llc-managed-rid 7 _llc-bytes 64 _llc-entry _llc-content _llc-store
        LIBRARY-VFS-STORE-READ-MANAGED-EXACT
    _llc-status ! _llc-required ! ;

: _llc-read-capture  ( -- )
    _llc-capture-rid 1 _llc-bytes 64 _llc-entry _llc-content _llc-store
        LIBRARY-VFS-STORE-READ-EXACT
    _llc-status ! _llc-required ! ;

: _llc-read-retained  ( domain -- )
    _llc-managed-rid SWAP _llc-bytes 64 _llc-content _llc-store
        LIBRARY-VFS-STORE-READ-RETAINED-EXACT
    _llc-status ! _llc-required ! ;

: _llc-managed-proof  ( -- )
    _llc-read-managed
    _llc-status @ LIBSTORE-S-OK = _llc-assert
    _llc-required @ S" revision six" NIP = _llc-assert
    _llc-entry LIBE.ID _llc-managed-rid RID= _llc-assert
    _llc-entry LIBE.DOMAIN-REVISION @ 7 = _llc-assert
    _llc-entry LIBE.LIFECYCLE @ LIB-LIFECYCLE-ARCHIVED = _llc-assert
    _llc-entry LIBE.CURRENT-CONTENT-REVISION @ 6 = _llc-assert
    _llc-entry LIBE.OLDEST-CONTENT-REVISION @ 3 = _llc-assert
    _llc-content LIBCT.CONTENT-REVISION @ 6 = _llc-assert
    _llc-content LIBCT-DATA$ S" revision six" COMPARE 0= _llc-assert

    _llc-managed-rid 7 _llc-history LIB-RETAINED-REVISION-MAX _llc-store
        LIBRARY-VFS-STORE-LIST-RETAINED-REVISIONS
    _llc-status ! _llc-required !
    _llc-status @ LIBSTORE-S-OK = _llc-assert
    _llc-required @ 4 = _llc-assert
    0 _llc-summary LIBRS.DOMAIN-REVISION @ 6 = _llc-assert
    0 _llc-summary LIBRS.CONTENT-REVISION @ 6 = _llc-assert
    1 _llc-summary LIBRS.DOMAIN-REVISION @ 5 = _llc-assert
    2 _llc-summary LIBRS.DOMAIN-REVISION @ 4 = _llc-assert
    3 _llc-summary LIBRS.DOMAIN-REVISION @ 3 = _llc-assert

    3 _llc-read-retained
    _llc-status @ LIBSTORE-S-OK = _llc-assert
    _llc-content LIBCT-DATA$ S" revision three" COMPARE 0= _llc-assert
    2 _llc-read-retained
    _llc-status @ LIBSTORE-S-GONE = _llc-assert
    _llc-required @ 0= _llc-assert ;

: _llc-receipt-proof  ( -- )
    _llc-managed-key _llc-rid-out _llc-receipt _llc-store
        LIBRARY-VFS-STORE-LOOKUP-RECEIPT
        LIBSTORE-S-OK = _llc-assert
    _llc-rid-out _llc-managed-rid RID= _llc-assert
    _llc-receipt LIB-RECEIPT-VALID? _llc-assert
    _llc-receipt LIBR.OPERATION-KEY _llc-managed-key RID= _llc-assert
    _llc-receipt LIBR.METHOD @ LIB-IMPORT-CREATED = _llc-assert

    _llc-capture-key _llc-rid-out _llc-receipt _llc-store
        LIBRARY-VFS-STORE-LOOKUP-RECEIPT
        LIBSTORE-S-OK = _llc-assert
    _llc-rid-out _llc-capture-rid RID= _llc-assert
    _llc-receipt LIB-RECEIPT-VALID? _llc-assert
    _llc-receipt LIBR.OPERATION-KEY _llc-capture-key RID= _llc-assert
    _llc-receipt LIBR.METHOD @ LIB-IMPORT-VFS-SNAPSHOT = _llc-assert ;

: _llc-capture-proof  ( -- )
    _llc-read-capture
    _llc-status @ LIBSTORE-S-OK = _llc-assert
    _llc-required @ S" frozen capture bytes" NIP = _llc-assert
    _llc-entry LIBE.ID _llc-capture-rid RID= _llc-assert
    _llc-entry LIBE.KIND @ LIB-KIND-CAPTURE = _llc-assert
    _llc-entry LIBE.DOMAIN-REVISION @ 1 = _llc-assert
    _llc-entry LIBE.CURRENT-CONTENT-REVISION @ 1 = _llc-assert
    _llc-entry LIBE.ORIGIN LIB-ORIGIN-VALID? _llc-assert
    _llc-entry LIBE.ORIGIN LIBO.VFS LIBV-PATH$
        S" /cold/frozen-capture.md" COMPARE 0= _llc-assert
    _llc-content LIBCT-DATA$
        S" frozen capture bytes" COMPARE 0= _llc-assert ;

: _llc-collection-proof  ( -- )
    _llc-collection-rid 1 _llc-view _llc-store
        LIBRARY-VFS-STORE-READ-COLLECTION-EXACT
        LIBSTORE-S-OK = _llc-assert
    _llc-view LIBCV.ID _llc-collection-rid RID= _llc-assert
    _llc-view LIBCV.REVISION @ 1 = _llc-assert
    _llc-view LIBCV-TITLE$ S" Cold milestone resources"
        COMPARE 0= _llc-assert
    _llc-view LIBCV.MEMBER-N @ 2 = _llc-assert
    0 _llc-view LIBCV-MEMBER _llc-managed-rid RID= _llc-assert
    1 _llc-view LIBCV-MEMBER _llc-capture-rid RID= _llc-assert ;

: _llc-run  ( -- )
    0 _llc-fails ! 0 _llc-checks !
    _llc-managed-key LIB-OPERATION-KEY-SIZE 0x51 FILL
    _llc-capture-key LIB-OPERATION-KEY-SIZE 0x62 FILL
    2097152 A-XMEM ARENA-NEW IF -7802 THROW THEN
    VMP-NEW DUP _llc-vfs ! DUP 0<> _llc-assert
    DUP VMP-INIT 0= _llc-assert VFS-USE
    _llc-vfs @ _llc-store LIBRARY-VFS-STORE-INIT
        LIBSTORE-S-OK = _llc-assert
    _llc-store LIBRARY-VFS-STORE-LOAD LIBSTORE-S-OK = _llc-assert
    _llc-store LIBRARY-VFS-STORE.GENERATION @ 10 = _llc-assert
    _llc-managed-proof
    _llc-receipt-proof
    _llc-capture-proof
    _llc-collection-proof
    _llc-vfs @ VFS-SYNC 0= _llc-assert
    _llc-fails @ 0= IF
        ." LIBRARY LIFECYCLE COLD BOOT PASS " _llc-checks @ . CR
    ELSE
        ." LIBRARY LIFECYCLE COLD BOOT FAIL "
            _llc-fails @ . ." / " _llc-checks @ . CR
    THEN ;

_llc-run
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


def _extract_rid(pattern: re.Pattern[str], output: str, label: str) -> bytes:
    match = pattern.search(output)
    if match is None:
        raise RuntimeError(f"first boot passed without printing its {label} RID")
    return bytes.fromhex(match.group(1))


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--image",
        type=Path,
        default=Path("/tmp/akashic-library-lifecycle-two-boot.img"),
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
    managed_rid = _extract_rid(MANAGED_RID_RE, first_output, "managed")
    capture_rid = _extract_rid(CAPTURE_RID_RE, first_output, "capture")
    collection_rid = _extract_rid(
        COLLECTION_RID_RE, first_output, "collection"
    )

    fs = MP64FS(bytearray(first_disk))
    if fs.find_file("autoexec.f") is None:
        raise RuntimeError("first-boot image has no autoexec.f to replace")
    fs.delete_file("autoexec.f")
    fs.inject_file(
        "autoexec.f",
        _cold_autoexec(managed_rid, capture_rid, collection_rid).encode("utf-8"),
        ftype=FTYPE_FORTH,
    )
    fs.save(image)

    _run_in_fresh_process(image, COLD_MARKER, COLD_FAILURES, args.timeout)
    print(
        "Library lifecycle two-process cold acceptance: PASS "
        f"({image}, managed {managed_rid.hex()}, capture {capture_rid.hex()}, "
        f"collection {collection_rid.hex()})"
    )
    return 0


if __name__ == "__main__":
    multiprocessing.freeze_support()
    raise SystemExit(main())
