#!/usr/bin/env python3
"""Prove the public Library managed-document slice across two cold processes.

The first guest creates, queries, and exactly reads one managed document on
the real MP64FS-backed VFS.  Its owner-generated RID is printed as test
evidence.  The parent retains only the serialized disk image and that printed
RID, replaces ``autoexec.f`` with a cold-readback program, and starts a second
Python process containing a fresh emulator session.  No guest dictionary,
VFS descriptor, Library descriptor, or RAM arena crosses the boundary.
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


PROFILE_NAME: Final = "_library-managed-two-cold-processes"
FIRST_MARKER: Final = "LIBRARY MANAGED FIRST BOOT PASS"
COLD_MARKER: Final = "LIBRARY MANAGED COLD BOOT PASS"
FIRST_FAILURES: Final = (
    "LIBRARY MANAGED FIRST BOOT FAIL",
    "LIBRARY MANAGED FIRST ASSERT",
    "EVALUATE input exceeds",
    "EVALUATE depth limit exceeded",
    " ? (not found)",
    "dictionary full",
    "exception",
)
COLD_FAILURES: Final = (
    "LIBRARY MANAGED COLD BOOT FAIL",
    "LIBRARY MANAGED COLD ASSERT",
    "EVALUATE input exceeds",
    "EVALUATE depth limit exceeded",
    " ? (not found)",
    "dictionary full",
    "exception",
)
RID_RE: Final = re.compile(r"LIBRARY MANAGED FIRST RID +([0-9A-F]{64})")


FIRST_AUTOEXEC = r"""\ autoexec.f - first managed-document persistence boot
ENTER-USERLAND
REQUIRE library/vfs-store.f
REQUIRE utils/fs/drivers/vfs-mp64fs.f

VARIABLE _lmf-fails
VARIABLE _lmf-checks
VARIABLE _lmf-vfs
VARIABLE _lmf-count
VARIABLE _lmf-next
VARIABLE _lmf-generation
VARIABLE _lmf-status
VARIABLE _lmf-required

CREATE _lmf-arena-id LIB-DIGEST-SIZE ALLOT
CREATE _lmf-operation-key LIB-OPERATION-KEY-SIZE ALLOT
CREATE _lmf-request LIBRARY-MANAGED-CREATE-REQUEST-SIZE ALLOT
CREATE _lmf-result LIB-ENTRY-SIZE ALLOT
CREATE _lmf-summary LIBRARY-QUERY-SUMMARY-SIZE ALLOT
CREATE _lmf-read-entry LIB-ENTRY-SIZE ALLOT
CREATE _lmf-read-content LIB-CONTENT-SIZE ALLOT
CREATE _lmf-read-bytes 64 ALLOT
CREATE _lmf-store LIBRARY-VFS-STORE-SIZE ALLOT

: _lmf-assert  ( flag -- )
    1 _lmf-checks +!
    0= IF
        1 _lmf-fails +!
        ." LIBRARY MANAGED FIRST ASSERT " _lmf-checks @ . CR
    THEN ;

: _lmf-request!  ( -- )
    _lmf-request LIBRARY-MANAGED-CREATE-REQUEST-INIT
    1 _lmf-request LIBMCR.EXPECTED-CATALOG-GENERATION !
    LIB-MEDIA-TEXT-MARKDOWN _lmf-request LIBMCR.MEDIA !
    _lmf-operation-key _lmf-request
        LIBRARY-MANAGED-CREATE-OPERATION-KEY!
        LIBSTORE-S-OK = _lmf-assert
    S" Cold-process note" _lmf-request LIBRARY-MANAGED-CREATE-TITLE!
        LIBSTORE-S-OK = _lmf-assert
    S" durable managed content" _lmf-request
        LIBRARY-MANAGED-CREATE-CONTENT!
        LIBSTORE-S-OK = _lmf-assert
    _lmf-request LIBRARY-MANAGED-CREATE-REQUEST-VALID? _lmf-assert ;

: _lmf-query  ( -- )
    0 0 _lmf-summary 1 _lmf-store
        LIBRARY-VFS-STORE-QUERY-ACTIVE
    _lmf-status ! _lmf-generation ! _lmf-next ! _lmf-count ! ;

: _lmf-read  ( -- )
    _lmf-summary LIBQS.REF RREF.ID
    _lmf-summary LIBQS.DOMAIN-REVISION @
    _lmf-read-bytes 64 _lmf-read-entry _lmf-read-content _lmf-store
        LIBRARY-VFS-STORE-READ-MANAGED-EXACT
    _lmf-status ! _lmf-required ! ;

: _lmf-hex-digit  ( nibble -- )
    DUP 10 < IF [CHAR] 0 + ELSE 10 - [CHAR] A + THEN EMIT ;

: _lmf-hex-byte  ( byte -- )
    DUP 16 / _lmf-hex-digit 15 AND _lmf-hex-digit ;

: _lmf-rid.  ( rid -- )
    LIB-DIGEST-SIZE 0 DO DUP I + C@ _lmf-hex-byte LOOP DROP ;

: _lmf-run  ( -- )
    0 _lmf-fails ! 0 _lmf-checks !
    _lmf-arena-id LIB-DIGEST-SIZE 0xA4 FILL
    _lmf-operation-key LIB-OPERATION-KEY-SIZE 0x5C FILL
    2097152 A-XMEM ARENA-NEW IF -7701 THROW THEN
    VMP-NEW DUP _lmf-vfs !
    DUP 0<> _lmf-assert
    DUP VMP-INIT 0= _lmf-assert
    VFS-USE
    _lmf-vfs @ _lmf-store LIBRARY-VFS-STORE-INIT
        LIBSTORE-S-OK = _lmf-assert
    _lmf-store LIBRARY-VFS-STORE-LOAD
        LIBSTORE-S-ABSENT = _lmf-assert
    _lmf-arena-id _lmf-store LIBRARY-VFS-STORE-PROVISION
        LIBSTORE-S-OK = _lmf-assert
    _lmf-request!
    _lmf-request _lmf-result _lmf-store
        LIBRARY-VFS-STORE-CREATE-MANAGED
        LIBSTORE-S-OK = _lmf-assert
    _lmf-result LIB-ENTRY-VALID? _lmf-assert
    _lmf-result LIBE.ID RID-PRESENT? _lmf-assert
    _lmf-result LIBE.RECEIPT LIBR.OPERATION-KEY
        _lmf-operation-key RID= _lmf-assert
    _lmf-store LIBRARY-VFS-STORE.GENERATION @ 2 = _lmf-assert
    _lmf-query
    _lmf-status @ LIBSTORE-S-OK = _lmf-assert
    _lmf-count @ 1 = _lmf-assert
    _lmf-next @ -1 = _lmf-assert
    _lmf-generation @ 2 = _lmf-assert
    _lmf-summary LIBQS.REF RREF-VALID? _lmf-assert
    _lmf-summary LIBQS.REF RREF.ID
        _lmf-result LIBE.ID RID= _lmf-assert
    _lmf-summary LIBQS-TITLE$ S" Cold-process note"
        COMPARE 0= _lmf-assert
    _lmf-read
    _lmf-status @ LIBSTORE-S-OK = _lmf-assert
    _lmf-required @ S" durable managed content" NIP = _lmf-assert
    _lmf-read-entry LIB-ENTRY-SIZE _lmf-result LIB-ENTRY-SIZE
        COMPARE 0= _lmf-assert
    _lmf-read-content LIB-CONTENT-VALID? _lmf-assert
    _lmf-read-content LIBCT-DATA$ S" durable managed content"
        COMPARE 0= _lmf-assert
    _lmf-vfs @ VFS-SYNC 0= _lmf-assert
    _lmf-fails @ 0= IF
        ." LIBRARY MANAGED FIRST RID " _lmf-result LIBE.ID _lmf-rid. CR
        ." LIBRARY MANAGED FIRST BOOT PASS " _lmf-checks @ . CR
    ELSE
        ." LIBRARY MANAGED FIRST BOOT FAIL "
            _lmf-fails @ . ." / " _lmf-checks @ . CR
    THEN ;

_lmf-run
"""


def _cold_autoexec(expected_rid: bytes) -> str:
    if len(expected_rid) != 32:
        raise ValueError("a Library RID must contain exactly 32 bytes")
    rid_cells = "\n".join(
        " ".join(f"0x{byte:02X} C," for byte in expected_rid[offset : offset + 8])
        for offset in range(0, len(expected_rid), 8)
    )
    return rf"""\ autoexec.f - cold managed-document public readback
ENTER-USERLAND
REQUIRE library/vfs-store.f
REQUIRE utils/fs/drivers/vfs-mp64fs.f

VARIABLE _lmc-fails
VARIABLE _lmc-checks
VARIABLE _lmc-vfs
VARIABLE _lmc-count
VARIABLE _lmc-next
VARIABLE _lmc-generation
VARIABLE _lmc-status
VARIABLE _lmc-required

CREATE _lmc-expected-rid {rid_cells}
CREATE _lmc-operation-key LIB-OPERATION-KEY-SIZE ALLOT
CREATE _lmc-request LIBRARY-MANAGED-CREATE-REQUEST-SIZE ALLOT
CREATE _lmc-summary LIBRARY-QUERY-SUMMARY-SIZE ALLOT
CREATE _lmc-entry LIB-ENTRY-SIZE ALLOT
CREATE _lmc-content LIB-CONTENT-SIZE ALLOT
CREATE _lmc-retry-entry LIB-ENTRY-SIZE ALLOT
CREATE _lmc-bytes 64 ALLOT
CREATE _lmc-store LIBRARY-VFS-STORE-SIZE ALLOT

: _lmc-assert  ( flag -- )
    1 _lmc-checks +!
    0= IF
        1 _lmc-fails +!
        ." LIBRARY MANAGED COLD ASSERT " _lmc-checks @ . CR
    THEN ;

: _lmc-request!  ( -- )
    _lmc-request LIBRARY-MANAGED-CREATE-REQUEST-INIT
    \ This is deliberately stale after the first boot's generation-2 commit.
    1 _lmc-request LIBMCR.EXPECTED-CATALOG-GENERATION !
    LIB-MEDIA-TEXT-MARKDOWN _lmc-request LIBMCR.MEDIA !
    _lmc-operation-key _lmc-request
        LIBRARY-MANAGED-CREATE-OPERATION-KEY!
        LIBSTORE-S-OK = _lmc-assert
    S" Cold-process note" _lmc-request LIBRARY-MANAGED-CREATE-TITLE!
        LIBSTORE-S-OK = _lmc-assert
    S" durable managed content" _lmc-request
        LIBRARY-MANAGED-CREATE-CONTENT!
        LIBSTORE-S-OK = _lmc-assert
    _lmc-request LIBRARY-MANAGED-CREATE-REQUEST-VALID? _lmc-assert ;

: _lmc-query  ( expected-generation -- )
    0 _lmc-summary 1 _lmc-store LIBRARY-VFS-STORE-QUERY-ACTIVE
    _lmc-status ! _lmc-generation ! _lmc-next ! _lmc-count ! ;

: _lmc-read  ( -- )
    _lmc-summary LIBQS.REF RREF.ID
    _lmc-summary LIBQS.DOMAIN-REVISION @
    _lmc-bytes 64 _lmc-entry _lmc-content _lmc-store
        LIBRARY-VFS-STORE-READ-MANAGED-EXACT
    _lmc-status ! _lmc-required ! ;

: _lmc-run  ( -- )
    0 _lmc-fails ! 0 _lmc-checks !
    _lmc-operation-key LIB-OPERATION-KEY-SIZE 0x5C FILL
    2097152 A-XMEM ARENA-NEW IF -7702 THROW THEN
    VMP-NEW DUP _lmc-vfs !
    DUP 0<> _lmc-assert
    DUP VMP-INIT 0= _lmc-assert
    VFS-USE
    _lmc-vfs @ _lmc-store LIBRARY-VFS-STORE-INIT
        LIBSTORE-S-OK = _lmc-assert
    _lmc-store LIBRARY-VFS-STORE-LOAD
        LIBSTORE-S-OK = _lmc-assert
    _lmc-store LIBRARY-VFS-STORE.GENERATION @ 2 = _lmc-assert
    0 _lmc-query
    _lmc-status @ LIBSTORE-S-OK = _lmc-assert
    _lmc-count @ 1 = _lmc-assert
    _lmc-next @ -1 = _lmc-assert
    _lmc-generation @ 2 = _lmc-assert
    _lmc-summary LIBQS.REF RREF-VALID? _lmc-assert
    _lmc-summary LIBQS.REF RREF.ID
        _lmc-expected-rid RID= _lmc-assert
    _lmc-summary LIBQS.DOMAIN-REVISION @ 1 = _lmc-assert
    _lmc-summary LIBQS.KIND @
        LIB-KIND-MANAGED-DOCUMENT = _lmc-assert
    _lmc-summary LIBQS.LIFECYCLE @
        LIB-LIFECYCLE-ACTIVE = _lmc-assert
    _lmc-summary LIBQS-TITLE$ S" Cold-process note"
        COMPARE 0= _lmc-assert
    _lmc-read
    _lmc-status @ LIBSTORE-S-OK = _lmc-assert
    _lmc-required @ S" durable managed content" NIP = _lmc-assert
    _lmc-entry LIB-ENTRY-VALID? _lmc-assert
    _lmc-entry LIBE.ID _lmc-expected-rid RID= _lmc-assert
    _lmc-entry LIBE.RECEIPT LIBR.OPERATION-KEY
        _lmc-operation-key RID= _lmc-assert
    _lmc-entry LIBE.RECEIPT LIBR.EXPECTED-CATALOG-GENERATION @
        1 = _lmc-assert
    _lmc-content LIB-CONTENT-VALID? _lmc-assert
    _lmc-content LIBCT.DATA-A @ _lmc-bytes = _lmc-assert
    _lmc-content LIBCT-DATA$ S" durable managed content"
        COMPARE 0= _lmc-assert

    \ Same-key retry must win over the stale generation and return the
    \ original owner RID without publishing another generation.
    _lmc-request!
    _lmc-request _lmc-retry-entry _lmc-store
        LIBRARY-VFS-STORE-CREATE-MANAGED
        LIBSTORE-S-OK = _lmc-assert
    _lmc-retry-entry LIBE.ID _lmc-expected-rid RID= _lmc-assert
    _lmc-retry-entry LIB-ENTRY-SIZE _lmc-entry LIB-ENTRY-SIZE
        COMPARE 0= _lmc-assert
    _lmc-store LIBRARY-VFS-STORE.GENERATION @ 2 = _lmc-assert
    2 _lmc-query
    _lmc-status @ LIBSTORE-S-OK = _lmc-assert
    _lmc-count @ 1 = _lmc-assert
    _lmc-next @ -1 = _lmc-assert
    _lmc-generation @ 2 = _lmc-assert
    _lmc-summary LIBQS.REF RREF.ID
        _lmc-expected-rid RID= _lmc-assert
    _lmc-vfs @ VFS-SYNC 0= _lmc-assert
    _lmc-fails @ 0= IF
        ." LIBRARY MANAGED COLD BOOT PASS " _lmc-checks @ . CR
    ELSE
        ." LIBRARY MANAGED COLD BOOT FAIL "
            _lmc-fails @ . ." / " _lmc-checks @ . CR
    THEN ;

_lmc-run
"""


def _profile() -> Profile:
    """Return the exact build closure needed by both cold processes."""
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
    """Run one boot in a spawned process and return only serialized evidence."""
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


def _first_rid(output: str) -> bytes:
    match = RID_RE.search(output)
    if match is None:
        raise RuntimeError("first boot passed without printing its generated RID")
    return bytes.fromhex(match.group(1))


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--image",
        type=Path,
        default=Path("/tmp/akashic-library-managed-two-boot.img"),
    )
    parser.add_argument("--timeout", type=float, default=180.0)
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
    expected_rid = _first_rid(first_output)

    fs = MP64FS(bytearray(first_disk))
    if fs.find_file("autoexec.f") is None:
        raise RuntimeError("first-boot image has no autoexec.f to replace")
    fs.delete_file("autoexec.f")
    fs.inject_file(
        "autoexec.f",
        _cold_autoexec(expected_rid).encode("utf-8"),
        ftype=FTYPE_FORTH,
    )
    fs.save(image)

    _run_in_fresh_process(image, COLD_MARKER, COLD_FAILURES, args.timeout)
    print(
        "Library managed-document two-process cold acceptance: PASS "
        f"({image}, RID {expected_rid.hex()})"
    )
    return 0


if __name__ == "__main__":
    multiprocessing.freeze_support()
    raise SystemExit(main())
