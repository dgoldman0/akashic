#!/usr/bin/env python3
"""Fresh-process MP64FS profiling for the Library efficiency rework.

The guest reports exact ``PERF-CYCLES`` values.  A one-byte handshake before
each measured operation also lets the host report emulator steps and wall time
without attributing several fast guest operations to one coarse polling batch.
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


PROFILE_NAME = "_library-query-efficiency"
SETUP_READY = "LQE SETUP READY"
SETUP_DONE = "LQE SETUP PASS"
PROFILE_READY = "LQE PROFILE READY"
PROFILE_DONE = "LQE PROFILE PASS"
FAILURES = ("LQE FAIL", " ? (not found)", "dictionary full", "exception")


@dataclass(frozen=True)
class Shape:
    name: str
    documents: int
    body_bytes: int

    @property
    def collections(self) -> int:
        return int(self.documents > 0)

    @property
    def generation(self) -> int:
        return 1 + self.documents + self.collections


SHAPES = {
    "empty": Shape("empty", 0, 0),
    "one-64k": Shape("one-64k", 1, 65536),
    "thirtytwo-4k": Shape("thirtytwo-4k", 32, 4096),
}

THIRTYTWO_BASELINE_CYCLES = {
    "cold-load": 155_900_000,
    "title-first": 167_300_000,
    "title-repeat": 167_300_000,
    "title-miss": 155_900_000,
    "empty-browse": 155_900_000,
    "collection-enum": 155_900_000,
    "collection-filter": 155_900_000,
    "body-3byte-miss": 156_800_000,
    "body-hit": 863_400_000,
    "body-1byte-miss": 886_400_000,
    "body-2byte-miss": 886_400_000,
}


def setup_source(shape: Shape) -> str:
    body_alloc = max(1, shape.body_bytes)
    member_alloc = max(1, shape.documents * 32)
    return rf'''\ deterministic MP64FS Library efficiency corpus
ENTER-USERLAND
REQUIRE library/vfs-store.f
REQUIRE utils/fs/drivers/vfs-mp64fs.f

{shape.documents} CONSTANT _lqe-document-count
{shape.body_bytes} CONSTANT _lqe-body-bytes

VARIABLE _lqe-vfs
VARIABLE _lqe-fails
VARIABLE _lqe-index
CREATE _lqe-bd /BLOCK-DEVICE ALLOT
CREATE _lqe-volume /VOLUME ALLOT
CREATE _lqe-arena-id LIB-DIGEST-SIZE ALLOT
CREATE _lqe-key LIB-OPERATION-KEY-SIZE ALLOT
CREATE _lqe-request LIBRARY-MANAGED-CREATE-REQUEST-SIZE ALLOT
CREATE _lqe-entry LIB-ENTRY-SIZE ALLOT
CREATE _lqe-store LIBRARY-VFS-STORE-SIZE ALLOT
CREATE _lqe-collection-request
    LIBRARY-COLLECTION-CREATE-REQUEST-SIZE ALLOT
CREATE _lqe-collection-view LIBRARY-COLLECTION-VIEW-SIZE ALLOT
{body_alloc} XBUF _lqe-body
{member_alloc} XBUF _lqe-members

: _lqe-ok  ( status -- )
    DUP LIBSTORE-S-OK <> IF
        1 _lqe-fails +! ." LQE SETUP STATUS " . CR
    ELSE
        DROP
    THEN ;

: _lqe-key!  ( value -- )
    _lqe-key LIB-OPERATION-KEY-SIZE 0 FILL _lqe-key ! ;

: _lqe-body!  ( -- )
    _lqe-body-bytes IF
        _lqe-body _lqe-body-bytes [CHAR] x FILL
        S" commonneedle" DROP _lqe-body
            _lqe-body-bytes 12 MIN MOVE
    THEN ;

: _lqe-create-one  ( index -- )
    _lqe-index !
    _lqe-request LIBRARY-MANAGED-CREATE-REQUEST-INIT
    _lqe-index @ 1+ _lqe-request
        LIBMCR.EXPECTED-CATALOG-GENERATION !
    _lqe-index @ 1+ _lqe-key!
    _lqe-key _lqe-request LIBRARY-MANAGED-CREATE-OPERATION-KEY!
        _lqe-ok
    S" commonneedle profile document" _lqe-request
        LIBRARY-MANAGED-CREATE-TITLE! _lqe-ok
    _lqe-body _lqe-body-bytes _lqe-request
        LIBRARY-MANAGED-CREATE-CONTENT! _lqe-ok
    LIB-MEDIA-TEXT-PLAIN _lqe-request LIBMCR.MEDIA !
    _lqe-request LIBRARY-MANAGED-CREATE-REQUEST-VALID? 0=
        IF 1 _lqe-fails +! THEN
    _lqe-request _lqe-entry _lqe-store
        LIBRARY-VFS-STORE-CREATE-MANAGED _lqe-ok
    _lqe-entry LIBE.ID
        _lqe-members _lqe-index @ LIB-DIGEST-SIZE * +
        RID-COPY ;

: _lqe-create-collection  ( -- )
    _lqe-document-count 0= IF EXIT THEN
    _lqe-collection-request LIBRARY-COLLECTION-CREATE-REQUEST-INIT
    _lqe-document-count 1+ _lqe-collection-request
        LIBCCR.EXPECTED-CATALOG-GENERATION !
    0x7000 _lqe-key!
    _lqe-key _lqe-collection-request
        LIBRARY-COLLECTION-CREATE-OPERATION-KEY! _lqe-ok
    S" Efficiency corpus" _lqe-collection-request
        LIBRARY-COLLECTION-CREATE-TITLE! _lqe-ok
    _lqe-members _lqe-document-count _lqe-collection-request
        LIBRARY-COLLECTION-CREATE-MEMBERS! _lqe-ok
    _lqe-collection-request LIBRARY-COLLECTION-CREATE-REQUEST-VALID? 0=
        IF 1 _lqe-fails +! THEN
    _lqe-collection-request _lqe-collection-view _lqe-store
        LIBRARY-VFS-STORE-CREATE-COLLECTION _lqe-ok ;

: _lqe-setup  ( -- )
    0 _lqe-fails !
    _lqe-arena-id LIB-DIGEST-SIZE 0xA5 FILL
    _lqe-body!
    _lqe-bd BD-OPEN THROW
    _lqe-bd _lqe-volume VOL-RAW THROW
    4194304 A-XMEM ARENA-NEW IF -7890 THROW THEN
    _lqe-volume VMP-NEW ?DUP IF THROW THEN
    DUP _lqe-vfs ! DUP 0= IF -7891 THROW THEN VFS-USE
    _lqe-vfs @ _lqe-store LIBRARY-VFS-STORE-INIT
        DUP ." LQE SETUP INIT " . CR _lqe-ok
    _lqe-store LIBRARY-VFS-STORE-LOAD DUP
        LIBSTORE-S-ABSENT <> IF
        1 _lqe-fails +! ." LQE SETUP LOAD STATUS " . CR
    ELSE
        DROP
    THEN
    _lqe-arena-id _lqe-store LIBRARY-VFS-STORE-PROVISION
        DUP ." LQE SETUP PROVISION " . CR _lqe-ok
    ." LQE SETUP READY" CR
    _lqe-document-count 0 ?DO I _lqe-create-one LOOP
    _lqe-create-collection
    _lqe-vfs @ VFS-SYNC IF 1 _lqe-fails +! THEN
    _lqe-store LIBRARY-VFS-STORE.GENERATION @
        {shape.generation} <> IF 1 _lqe-fails +! THEN
    _lqe-fails @ IF
        ." LQE FAIL setup=" _lqe-fails @ . CR
    ELSE
        ." LQE SETUP PASS docs=" _lqe-document-count .
        ."  body=" _lqe-body-bytes .
        ."  generation=" _lqe-store LIBRARY-VFS-STORE.GENERATION @ . CR
    THEN ;

_lqe-setup
'''


def profile_source(shape: Shape) -> str:
    return rf'''\ fresh-process MP64FS Library efficiency profile
ENTER-USERLAND
REQUIRE library/vfs-store.f
REQUIRE utils/fs/drivers/vfs-mp64fs.f

{shape.documents} CONSTANT _lqe-document-count
{shape.body_bytes} CONSTANT _lqe-body-bytes
{shape.generation} CONSTANT _lqe-expected-generation

VARIABLE _lqe-vfs
VARIABLE _lqe-fails
CREATE _lqe-bd /BLOCK-DEVICE ALLOT
CREATE _lqe-volume /VOLUME ALLOT
VARIABLE _lqe-status
VARIABLE _lqe-count
VARIABLE _lqe-next
VARIABLE _lqe-generation
VARIABLE _lqe-cycles
VARIABLE _lqe-stalls
VARIABLE _lqe-extmem
VARIABLE _lqe-expected-count
VARIABLE _lqe-label-a
VARIABLE _lqe-label-u
CREATE _lqe-store LIBRARY-VFS-STORE-SIZE ALLOT
CREATE _lqe-request LIBRARY-CORPUS-QUERY-REQUEST-SIZE ALLOT
CREATE _lqe-collection-page LIBRARY-COLLECTION-SUMMARY-SIZE ALLOT
LIBRARY-QUERY-PAGE-MAX LIBRARY-QUERY-SUMMARY-SIZE * XBUF _lqe-page
LIBRARY-QUERY-PAGE-MAX LIBRARY-QUERY-SUMMARY-SIZE * XBUF _lqe-baseline
LIBRARY-QUERY-PAGE-MAX LIBRARY-QUERY-SUMMARY-SIZE * XBUF _lqe-active

: _lqe-assert  ( flag -- )
    0= IF
        1 _lqe-fails +!
        ." LQE FAIL assertion=" _lqe-fails @ . CR
    THEN ;

: _lqe-start  ( -- )
    _LIBPQ-RESET PERF-RESET ;

: _lqe-stop  ( -- )
    PERF-CYCLES _lqe-cycles !
    PERF-STALLS _lqe-stalls !
    PERF-EXTMEM _lqe-extmem ! ;

: _lqe-report  ( label-a label-u -- )
    ." LQE RESULT " TYPE
    ."  cycles=" _lqe-cycles @ .
    ."  stalls=" _lqe-stalls @ .
    ."  extmem=" _lqe-extmem @ .
    ."  status=" _lqe-status @ .
    ."  count=" _lqe-count @ .
    ."  next=" _lqe-next @ .
    ."  generation=" _lqe-generation @ .
    ."  full=" _LIBPQ-FULL-VALIDATION@ .
    ."  warm=" _LIBPQ-WARM-ASSURANCE@ .
    ."  index=" _LIBPQ-INDEX-REBUILD@ .
    ."  entry=" _LIBPQ-ENTRY-READ@ .
    ."  collection=" _LIBPQ-COLLECTION-READ@ .
    ."  direct=" _LIBPQ-DIRECT-FRAME-READ@ .
    ."  direct-bytes=" _LIBPQ-DIRECT-FRAME-BYTES@ .
    ."  scans=" _LIBPQ-ARENA-SCAN@ .
    ."  frames=" _LIBPQ-ARENA-SCAN-FRAME@ .
    ."  scan-bytes=" _LIBPQ-ARENA-SCAN-BYTES@ . CR ;

: _lqe-gate  ( label-a label-u -- )
    ." LQE MEASURE " TYPE CR KEY DROP ;

: _lqe-request!  ( term-a term-u field-mask -- )
    >R
    _lqe-request LIBRARY-CORPUS-QUERY-REQUEST-INIT
    _lqe-request LIBRARY-CORPUS-QUERY-TERM!
        LIBSTORE-S-OK = _lqe-assert
    R> _lqe-request LIBCQR.FIELD-MASK !
    _lqe-request LIBRARY-CORPUS-QUERY-REQUEST-VALID? _lqe-assert ;

: _lqe-query  ( -- )
    _lqe-request _lqe-page 32 _lqe-store
        LIBRARY-VFS-STORE-QUERY-CORPUS
    _lqe-status ! _lqe-generation ! _lqe-next ! _lqe-count ! ;

: _lqe-query-ok  ( expected-count -- )
    _lqe-count @ = _lqe-assert
    _lqe-status @ LIBSTORE-S-OK = _lqe-assert
    _lqe-next @ -1 = _lqe-assert
    _lqe-generation @ _lqe-expected-generation = _lqe-assert ;

: _lqe-page-shape  ( -- )
    _lqe-document-count 0 ?DO
        _lqe-page I LIBRARY-QUERY-SUMMARY-SIZE * +
        DUP LIBQS.REF RREF.ID RID-PRESENT? _lqe-assert
        DUP LIBQS.DOMAIN-REVISION @ 1 = _lqe-assert
        DUP LIBQS.KIND @ LIB-KIND-MANAGED-DOCUMENT = _lqe-assert
        DUP LIBQS.LIFECYCLE @ LIB-LIFECYCLE-ACTIVE = _lqe-assert
        DUP LIBQS.MEDIA @ LIB-MEDIA-TEXT-PLAIN = _lqe-assert
        DUP LIBQS.CONTENT-U @ _lqe-body-bytes = _lqe-assert
        LIBQS-TITLE$ S" commonneedle profile document"
            COMPARE 0= _lqe-assert
    LOOP ;

: _lqe-warm  ( -- )
    _LIBPQ-FULL-VALIDATION@ 0= _lqe-assert
    _LIBPQ-WARM-ASSURANCE@ 1 = _lqe-assert
    _LIBPQ-INDEX-REBUILD@ 0= _lqe-assert
    _LIBPQ-ARENA-SCAN@ 0= _lqe-assert ;

: _lqe-profile-query  ( label-a label-u expected-count -- )
    _lqe-expected-count ! _lqe-label-u ! _lqe-label-a !
    _lqe-label-a @ _lqe-label-u @ _lqe-gate
    _lqe-start _lqe-query _lqe-stop
    _lqe-expected-count @ _lqe-query-ok
    _lqe-label-a @ _lqe-label-u @ _lqe-report ;

: _lqe-run  ( -- )
    0 _lqe-fails !
    _lqe-bd BD-OPEN THROW
    _lqe-bd _lqe-volume VOL-RAW THROW
    4194304 A-XMEM ARENA-NEW IF -7893 THROW THEN
    _lqe-volume VMP-NEW ?DUP IF THROW THEN
    DUP _lqe-vfs ! DUP 0= IF -7894 THROW THEN VFS-USE
    _lqe-vfs @ _lqe-store LIBRARY-VFS-STORE-INIT
        LIBSTORE-S-OK = _lqe-assert
    ." LQE PROFILE READY" CR

    S" cold-load" _lqe-gate
    _lqe-start
    _lqe-store LIBRARY-VFS-STORE-LOAD _lqe-status !
    _lqe-stop
    0 _lqe-count ! 0 _lqe-next !
    _lqe-store LIBRARY-VFS-STORE.GENERATION @ _lqe-generation !
    _lqe-status @ LIBSTORE-S-OK = _lqe-assert
    _lqe-generation @ _lqe-expected-generation = _lqe-assert
    _LIBPQ-FULL-VALIDATION@ 1 = _lqe-assert
    _LIBPQ-WARM-ASSURANCE@ 0= _lqe-assert
    _LIBPQ-INDEX-REBUILD@ 1 = _lqe-assert
    S" cold-load" _lqe-report

    S" commonneedle" LIBRARY-CORPUS-FIELD-TITLE _lqe-request!
    S" title-first" _lqe-document-count _lqe-profile-query
    _lqe-page-shape _lqe-warm
    _lqe-page _lqe-baseline
        LIBRARY-QUERY-SUMMARY-SIZE _lqe-document-count * CMOVE

    0 0 _lqe-active 32 _lqe-store
        LIBRARY-VFS-STORE-QUERY-ACTIVE
    _lqe-status ! _lqe-generation ! _lqe-next ! _lqe-count !
    _lqe-document-count _lqe-query-ok
    _lqe-active LIBRARY-QUERY-SUMMARY-SIZE _lqe-document-count *
        _lqe-baseline LIBRARY-QUERY-SUMMARY-SIZE _lqe-document-count *
        COMPARE 0= _lqe-assert

    S" title-repeat" _lqe-document-count _lqe-profile-query
    _lqe-warm
    _lqe-page LIBRARY-QUERY-SUMMARY-SIZE _lqe-document-count *
        _lqe-baseline LIBRARY-QUERY-SUMMARY-SIZE _lqe-document-count *
        COMPARE 0= _lqe-assert

    S" zzz" LIBRARY-CORPUS-FIELD-TITLE _lqe-request!
    S" title-miss" 0 _lqe-profile-query
    _lqe-warm
    _LIBPQ-ENTRY-READ@ 0= _lqe-assert

    0 0 LIBRARY-CORPUS-FIELD-ALL _lqe-request!
    S" empty-browse" _lqe-document-count _lqe-profile-query
    _lqe-page-shape _lqe-warm
    _lqe-page LIBRARY-QUERY-SUMMARY-SIZE _lqe-document-count *
        _lqe-baseline LIBRARY-QUERY-SUMMARY-SIZE _lqe-document-count *
        COMPARE 0= _lqe-assert

    S" collection-enum" _lqe-gate
    _lqe-start
    0 0 _lqe-collection-page 1 _lqe-store
        LIBRARY-VFS-STORE-QUERY-COLLECTIONS
    _lqe-status ! _lqe-generation ! _lqe-next ! _lqe-count !
    _lqe-stop
    {shape.collections} _lqe-query-ok
    _lqe-warm
    S" collection-enum" _lqe-report

    _lqe-document-count IF
        S" commonneedle" LIBRARY-CORPUS-FIELD-TITLE _lqe-request!
        _lqe-collection-page LIBCS.REF RREF.ID _lqe-request
            LIBRARY-CORPUS-QUERY-COLLECTION!
            LIBSTORE-S-OK = _lqe-assert
        S" collection-filter" _lqe-document-count _lqe-profile-query
        _lqe-page-shape _lqe-warm
        _lqe-page LIBRARY-QUERY-SUMMARY-SIZE _lqe-document-count *
            _lqe-baseline LIBRARY-QUERY-SUMMARY-SIZE _lqe-document-count *
            COMPARE 0= _lqe-assert
    THEN

    S" zzz" LIBRARY-CORPUS-FIELD-BODY _lqe-request!
    S" body-3byte-miss" 0 _lqe-profile-query
    _lqe-warm
    _LIBPQ-ENTRY-READ@ 0= _lqe-assert
    _LIBPQ-DIRECT-FRAME-READ@ 0= _lqe-assert

    S" commonneedle" LIBRARY-CORPUS-FIELD-BODY _lqe-request!
    S" body-hit" _lqe-document-count _lqe-profile-query
    _lqe-page-shape _lqe-warm
    _lqe-page LIBRARY-QUERY-SUMMARY-SIZE _lqe-document-count *
        _lqe-baseline LIBRARY-QUERY-SUMMARY-SIZE _lqe-document-count *
        COMPARE 0= _lqe-assert
    _LIBPQ-DIRECT-FRAME-READ@ _lqe-document-count = _lqe-assert
    _LIBPQ-DIRECT-FRAME-BYTES@
        _lqe-body-bytes LIB-CONTENT-RECORD-SIZE
        LIB-CONTENT-FRAME-SIZE _lqe-document-count * =
        _lqe-assert

    S" z" LIBRARY-CORPUS-FIELD-BODY _lqe-request!
    S" body-1byte-miss" 0 _lqe-profile-query
    _lqe-warm
    _LIBPQ-DIRECT-FRAME-READ@ _lqe-document-count = _lqe-assert

    S" zz" LIBRARY-CORPUS-FIELD-BODY _lqe-request!
    S" body-2byte-miss" 0 _lqe-profile-query
    _lqe-warm
    _LIBPQ-DIRECT-FRAME-READ@ _lqe-document-count = _lqe-assert

    _lqe-fails @ IF
        ." LQE FAIL total=" _lqe-fails @ . CR
    ELSE
        ." LQE PROFILE PASS" CR
    THEN ;

_lqe-run
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
                f"LQE RESULT {active_label} "
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
                line.startswith(f"LQE RESULT {active_label} ")
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
    """Run exactly one machine session in a spawn-isolated process."""
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
    """Run one boot with no inherited emulator or guest runtime state."""
    context = multiprocessing.get_context("spawn")
    receiver, sender = context.Pipe(duplex=False)
    process = context.Process(
        target=_worker,
        args=(str(image), marker, timeout, gate_prefix, sender),
        name=f"akashic-lqe-{marker.lower().replace(' ', '-')}",
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


def print_host_events(
    shape: Shape,
    phase: str,
    steps: int,
    wall: float,
    events: list[tuple[str, int, float]],
) -> None:
    print(
        f"LQE HOST shape={shape.name} phase={phase} "
        f"scope=machine-session-inclusive steps={steps} wall={wall:.6f}"
    )
    for label, event_steps, event_wall in events:
        print(
            f"LQE HOST EVENT shape={shape.name} phase={phase} "
            f"operation={label} steps={event_steps} "
            f"wall={event_wall:.6f} sampling-steps=250000"
        )


def parse_results(output: str) -> dict[str, dict[str, int]]:
    """Parse the guest's deterministic cycle and qualification counters."""
    results: dict[str, dict[str, int]] = {}
    for line in output.splitlines():
        if not line.startswith("LQE RESULT "):
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
        missing = {"cycles", "stalls"} - fields.keys()
        if missing:
            raise RuntimeError(
                f"guest result {label!r} lacks fields {sorted(missing)}"
            )
        results[label] = fields
    return results


def qualify_results(shape: Shape, results: dict[str, dict[str, int]]) -> None:
    """Enforce the handoff's fixed 32x4KiB cycle acceptance gates."""
    required = {
        "cold-load",
        "title-first",
        "title-repeat",
        "title-miss",
        "empty-browse",
        "collection-enum",
        "body-3byte-miss",
        "body-hit",
        "body-1byte-miss",
        "body-2byte-miss",
    }
    if shape.documents:
        required.add("collection-filter")
    missing = required - results.keys()
    if missing:
        raise RuntimeError(f"missing guest results: {sorted(missing)}")

    if shape.name != "thirtytwo-4k":
        return
    for operation, baseline in THIRTYTWO_BASELINE_CYCLES.items():
        cycles = results[operation]["cycles"]
        if operation == "cold-load":
            limit = baseline * 110 // 100
            rule = "cold-at-most-110pct"
            ratio = cycles / baseline
        else:
            limit = baseline // 5
            rule = "warm-at-least-5x"
            ratio = baseline / cycles
        if cycles > limit:
            raise RuntimeError(
                f"{operation} used {cycles} cycles; {rule} limit is {limit}"
            )
        print(
            f"LQE QUALIFY shape={shape.name} operation={operation} "
            f"cycles={cycles} baseline={baseline} limit={limit} "
            f"ratio={ratio:.3f} rule={rule} result=PASS"
        )


def print_clock_interpretations(
    shape: Shape, results: dict[str, dict[str, int]]
) -> None:
    """Print clock projections without presenting them as hardware latency."""
    print(
        "LQE CLOCK NOTE measured-hardware=false shared-memory-stalls-modeled=false "
        "external-memory-latency-modeled=false"
    )
    for operation, fields in results.items():
        cycles = fields["cycles"]
        print(
            f"LQE CLOCK shape={shape.name} operation={operation} "
            f"at-100mhz-seconds={cycles / 100_000_000:.6f} "
            f"at-50mhz-seconds={cycles / 50_000_000:.6f} "
            f"reported-stalls={fields['stalls']}"
        )


def run_shape(shape: Shape, timeout: float, keep_image: bool) -> None:
    image = Path(
        f"/tmp/library-query-efficiency-{shape.name}-{os.getpid()}.img"
    )
    previous = PROFILES.get(PROFILE_NAME)
    PROFILES[PROFILE_NAME] = Profile(
        roots=("library/vfs-store.f", "utils/fs/drivers/vfs-mp64fs.f"),
        resources=(),
        autoexec=setup_source(shape),
        ready_markers=(SETUP_DONE,),
        stable_markers=(SETUP_DONE,),
        failure_markers=FAILURES,
        include_large_sample=False,
        total_sectors=8192,
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
        image, PROFILE_DONE, timeout, "LQE MEASURE "
    )
    print_host_events(shape, "profile", steps, wall, events)
    results = parse_results(output)
    for line in output.splitlines():
        if line.startswith("LQE RESULT "):
            print(f"{shape.name} {line}")
    qualify_results(shape, results)
    print_clock_interpretations(shape, results)
    if not keep_image:
        image.unlink(missing_ok=True)


def main() -> int:
    parser = argparse.ArgumentParser()
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
    for name in names:
        run_shape(SHAPES[name], args.timeout, args.keep_images)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
