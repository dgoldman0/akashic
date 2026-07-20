#!/usr/bin/env python3
"""Fresh-process cost evidence for bounded Library maintenance.

The guest measures the public ``INSPECT``, ``RAW-EXPORT``, and ``REPAIR``
calls with the CPU's 64-bit ``PERF-CYCLES`` counter.  A one-byte handshake
around each operation also gives host emulator steps and wall time without
folding multiple maintenance calls into one polling batch.

The provisioned V1 topology fixes the dominant byte work independently of
logical corpus size: one head, both 403,968-byte banks, and the 655,360-byte
content arena total 1,463,808 bytes.  The bounded seven-object namespace adds
at most two more 512-byte head images and one 64-byte marker, for the public
1,464,896-byte ceiling.  The content-bound shape commits nine maximum-size
frames, the largest count that fits, and covers 90.8% of the arena payload.
The separate ``library-managed-capacity`` contract owns construction and full
validation at the 128-record catalog bound; this profiler does not repeat 128
public durable mutations merely to time the same maintenance calls.

Clock divisions printed here are CPU-model interpretations only.  The
emulator does not model target storage latency, shared-memory arbitration, or
external-memory latency.
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
    _forth_line_tokens,
    _linked_autoexec,
    _linked_chunks,
    build_image,
    dependency_order,
)


PROFILE_NAME = "_library-maintenance-efficiency"
GENERATED_LEAF_PREFIX = "lme-"
GENERATED_LEAF_BYTES = 5 * 1024
SETUP_DONE = "LME SETUP PASS"
PROFILE_DONE = "LME PROFILE PASS"
FAILURES = (
    "LME FAIL",
    " ? (not found)",
    "dictionary full",
    "EVALUATE depth limit exceeded",
    "exception",
)

RAW_MAX = 1_464_896
PROVISIONED_RAW = 512 + 2 * 403_968 + 655_360
RECOVERY_RAW = PROVISIONED_RAW + 512

OPERATIONS = {
    "inspect-first",
    "inspect-repeat",
    "raw-export-exact",
    "raw-export-repeat",
    "repair-head-transaction",
}


@dataclass(frozen=True)
class Shape:
    name: str
    documents: int
    body_bytes: int
    collections: int

    @property
    def generation(self) -> int:
        return 1 + self.documents + self.collections

    @property
    def content_tail(self) -> int:
        frame_bytes = ((160 + self.body_bytes + 511) // 512) * 512
        return 512 + self.documents * frame_bytes


SHAPES = {
    "representative": Shape("representative", 8, 4096, 1),
    "content-bound": Shape("content-bound", 9, 65_536, 0),
}


def setup_source(shape: Shape) -> str:
    """Return a deterministic durable corpus builder for one shape."""
    collection_flag = -1 if shape.collections else 0
    member_bytes = max(1, shape.documents * 32)
    return rf'''\ deterministic MP64FS Library-maintenance corpus
ENTER-USERLAND
REQUIRE library/vfs-store.f
REQUIRE utils/fs/drivers/vfs-mp64fs.f

{shape.documents} CONSTANT _lme-document-count
{shape.body_bytes} CONSTANT _lme-body-bytes
{collection_flag} CONSTANT _lme-create-collection?
{shape.generation} CONSTANT _lme-expected-generation

VARIABLE _lme-fails
VARIABLE _lme-checks
VARIABLE _lme-index
VARIABLE _lme-vfs
CREATE _lme-bd /BLOCK-DEVICE ALLOT
CREATE _lme-volume /VOLUME ALLOT
CREATE _lme-arena-id LIB-DIGEST-SIZE ALLOT
CREATE _lme-key LIB-OPERATION-KEY-SIZE ALLOT
CREATE _lme-request LIBRARY-MANAGED-CREATE-REQUEST-SIZE ALLOT
CREATE _lme-entry LIB-ENTRY-SIZE ALLOT
CREATE _lme-store LIBRARY-VFS-STORE-SIZE ALLOT
CREATE _lme-collection-request
    LIBRARY-COLLECTION-CREATE-REQUEST-SIZE ALLOT
CREATE _lme-collection-view LIBRARY-COLLECTION-VIEW-SIZE ALLOT
{shape.body_bytes} XBUF _lme-body
{member_bytes} XBUF _lme-members

: _lme-assert  ( flag -- )
    1 _lme-checks +!
    0= IF
        1 _lme-fails +!
        ." LME FAIL setup-assertion=" _lme-checks @ . CR
    THEN ;

: _lme-key!  ( value -- )
    _lme-key LIB-OPERATION-KEY-SIZE 0 FILL _lme-key ! ;

: _lme-body!  ( -- )
    _lme-body _lme-body-bytes [CHAR] m FILL
    S" maintenance-evidence" DROP _lme-body
        _lme-body-bytes 20 MIN MOVE ;

: _lme-create-one  ( index -- )
    _lme-index !
    _lme-request LIBRARY-MANAGED-CREATE-REQUEST-INIT
    _lme-index @ 1+ _lme-request
        LIBMCR.EXPECTED-CATALOG-GENERATION !
    _lme-index @ 1+ _lme-key!
    _lme-key _lme-request LIBRARY-MANAGED-CREATE-OPERATION-KEY!
        LIBSTORE-S-OK = _lme-assert
    S" Maintenance evidence document" _lme-request
        LIBRARY-MANAGED-CREATE-TITLE! LIBSTORE-S-OK = _lme-assert
    _lme-body _lme-body-bytes _lme-request
        LIBRARY-MANAGED-CREATE-CONTENT! LIBSTORE-S-OK = _lme-assert
    LIB-MEDIA-TEXT-PLAIN _lme-request LIBMCR.MEDIA !
    _lme-request LIBRARY-MANAGED-CREATE-REQUEST-VALID? _lme-assert
    _lme-request _lme-entry _lme-store
        LIBRARY-VFS-STORE-CREATE-MANAGED
        LIBSTORE-S-OK = _lme-assert
    _lme-entry LIBE.ID
        _lme-members _lme-index @ LIB-DIGEST-SIZE * + RID-COPY ;

: _lme-create-one-collection  ( -- )
    _lme-create-collection? 0= IF EXIT THEN
    _lme-collection-request LIBRARY-COLLECTION-CREATE-REQUEST-INIT
    _lme-document-count 1+ _lme-collection-request
        LIBCCR.EXPECTED-CATALOG-GENERATION !
    0x7001 _lme-key!
    _lme-key _lme-collection-request
        LIBRARY-COLLECTION-CREATE-OPERATION-KEY!
        LIBSTORE-S-OK = _lme-assert
    S" Maintenance evidence collection" _lme-collection-request
        LIBRARY-COLLECTION-CREATE-TITLE! LIBSTORE-S-OK = _lme-assert
    _lme-members _lme-document-count _lme-collection-request
        LIBRARY-COLLECTION-CREATE-MEMBERS!
        LIBSTORE-S-OK = _lme-assert
    _lme-collection-request LIBRARY-COLLECTION-CREATE-REQUEST-VALID?
        _lme-assert
    _lme-collection-request _lme-collection-view _lme-store
        LIBRARY-VFS-STORE-CREATE-COLLECTION
        LIBSTORE-S-OK = _lme-assert ;

: _lme-setup  ( -- )
    0 _lme-fails ! 0 _lme-checks !
    _lme-arena-id LIB-DIGEST-SIZE 0x9A FILL
    _lme-body!
    _lme-bd BD-OPEN THROW
    _lme-bd _lme-volume VOL-RAW THROW
    4194304 A-XMEM ARENA-NEW IF -7881 THROW THEN
    _lme-volume VMP-NEW ?DUP IF THROW THEN
    DUP _lme-vfs ! VFS-USE
    _lme-vfs @ _lme-store LIBRARY-VFS-STORE-INIT
        LIBSTORE-S-OK = _lme-assert
    _lme-store LIBRARY-VFS-STORE-LOAD
        LIBSTORE-S-ABSENT = _lme-assert
    _lme-arena-id _lme-store LIBRARY-VFS-STORE-PROVISION
        LIBSTORE-S-OK = _lme-assert
    _lme-document-count 0 ?DO I _lme-create-one LOOP
    _lme-create-one-collection
    _lme-vfs @ VFS-SYNC 0= _lme-assert
    _lme-store LIBRARY-VFS-STORE.GENERATION @
        _lme-expected-generation = _lme-assert
    _lme-fails @ IF
        ." LME FAIL setup-total=" _lme-fails @ .
        ."  checks=" _lme-checks @ . CR
    ELSE
        ." LME SETUP PASS docs=" _lme-document-count .
        ."  collections=" {shape.collections} .
        ."  body=" _lme-body-bytes .
        ."  generation=" _lme-expected-generation .
        ."  checks=" _lme-checks @ . CR
    THEN ;

_lme-setup
'''


def profile_source(shape: Shape) -> str:
    """Return the fresh-activation maintenance profiling program."""
    return rf'''\ fresh-process bounded Library-maintenance profile
ENTER-USERLAND
REQUIRE library/vfs-store.f
REQUIRE utils/fs/drivers/vfs-mp64fs.f

{shape.documents} CONSTANT _lme-expected-documents
{shape.collections} CONSTANT _lme-expected-collections
{shape.generation} CONSTANT _lme-expected-generation
{shape.content_tail} CONSTANT _lme-expected-content-tail

VARIABLE _lme-fails
VARIABLE _lme-checks
VARIABLE _lme-vfs
VARIABLE _lme-fd
VARIABLE _lme-status
VARIABLE _lme-expected-status
VARIABLE _lme-required
VARIABLE _lme-cycles
VARIABLE _lme-stalls
VARIABLE _lme-extmem
VARIABLE _lme-current-report
VARIABLE _lme-export-crc

CREATE _lme-bd /BLOCK-DEVICE ALLOT
CREATE _lme-volume /VOLUME ALLOT
CREATE _lme-store LIBRARY-VFS-STORE-SIZE ALLOT
CREATE _lme-report-a LIBRARY-INSPECTION-SIZE ALLOT
CREATE _lme-report-b LIBRARY-INSPECTION-SIZE ALLOT
CREATE _lme-report-c LIBRARY-INSPECTION-SIZE ALLOT
CREATE _lme-report-final LIBRARY-INSPECTION-SIZE ALLOT
CREATE _lme-head 512 ALLOT
LIBRARY-RAW-EXPORT-MAX XBUF _lme-export

: _lme-assert  ( flag -- )
    1 _lme-checks +!
    0= IF
        1 _lme-fails +!
        ." LME FAIL profile-assertion=" _lme-checks @ . CR
    THEN ;

: _lme-stage-present?  ( -- flag )
    _LIBVFS-HEAD-STAGE-PATH$ _lme-vfs @ VFS-RESOLVE 0<> ;

: _lme-start  ( -- ) PERF-RESET ;

: _lme-stop  ( -- )
    PERF-CYCLES _lme-cycles !
    PERF-STALLS _lme-stalls !
    PERF-EXTMEM _lme-extmem ! ;

: _lme-gate  ( label-a label-u -- )
    ." LME MEASURE " TYPE CR KEY DROP ;

: _lme-report  ( label-a label-u -- )
    ." LME RESULT " TYPE
    ."  cycles=" _lme-cycles @ .
    ."  stalls=" _lme-stalls @ .
    ."  extmem=" _lme-extmem @ .
    ."  status=" _lme-status @ .
    ."  expected-status=" _lme-expected-status @ .
    ."  required=" _lme-required @ .
    ."  health=" _lme-current-report @ LIBINS.HEALTH @ .
    ."  repair-mask=" _lme-current-report @ LIBINS.REPAIR-MASK @ .
    ."  raw-required=" _lme-current-report @ LIBINS.RAW-REQUIRED @ .
    ."  generation=" _lme-current-report @ LIBINS.HEAD-GENERATION @ .
    ."  catalog=" _lme-current-report @ LIBINS.CATALOG-COUNT @ .
    ."  collections=" _lme-current-report @ LIBINS.COLLECTION-COUNT @ .
    ."  content-records=" _lme-current-report @
        LIBINS.CONTENT-RECORD-COUNT @ .
    ."  content-tail=" _lme-current-report @ LIBINS.CONTENT-TAIL @ .
    ."  stage-present=" _lme-stage-present? .
    ."  loaded=" _lme-store LIBRARY-VFS-STORE-LOADED? .
    ."  blocked=" _lme-store LIBRARY-VFS-STORE-BLOCKED? . CR ;

: _lme-report-healthy?  ( report -- flag )
    DUP LIBINS.HEALTH @ LIBSTORE-S-OK =
    OVER LIBINS.FLAGS @ LIBRARY-INSPECTION-F-RECOGNIZED-V1 = AND
    OVER LIBINS.REPAIR-MASK @ 0= AND
    OVER LIBINS.RAW-REQUIRED @ 1463808 = AND
    OVER LIBINS.HEAD-GENERATION @ _lme-expected-generation = AND
    OVER LIBINS.CATALOG-COUNT @ _lme-expected-documents = AND
    OVER LIBINS.COLLECTION-COUNT @ _lme-expected-collections = AND
    OVER LIBINS.CONTENT-RECORD-COUNT @ _lme-expected-documents = AND
    SWAP LIBINS.CONTENT-TAIL @ _lme-expected-content-tail = AND ;

: _lme-read-head  ( -- )
    _LIBVFS-HEAD-PATH$ VFS-OPEN DUP _lme-fd ! 0<> _lme-assert
    _lme-fd @ 0= IF EXIT THEN
    _lme-fd @ VFS-SIZE 512 = _lme-assert
    _lme-head 512 _lme-fd @ VFS-READ-EXACT 0= _lme-assert
    _lme-fd @ VFS-CLOSE ;

: _lme-write-stage  ( -- )
    _LIBVFS-HEAD-STAGE-PATH$ _lme-vfs @ VFS-RESOLVE IF
        _LIBVFS-HEAD-STAGE-PATH$ _lme-vfs @ VFS-RM 0= _lme-assert
    THEN
    _LIBVFS-HEAD-STAGE-PATH$ _lme-vfs @ VFS-CREATE
        DUP 0<> _lme-assert DUP 0= IF DROP EXIT THEN DROP
    _LIBVFS-HEAD-STAGE-PATH$ VFS-OPEN DUP _lme-fd ! 0<> _lme-assert
    _lme-fd @ 0= IF EXIT THEN
    _lme-head 512 _lme-fd @ VFS-WRITE-EXACT 0= _lme-assert
    _lme-fd @ VFS-CLOSE
    _lme-vfs @ VFS-SYNC 0= _lme-assert ;

: _lme-inspect-first  ( -- )
    S" inspect-first" _lme-gate
    _lme-report-a LIBRARY-INSPECTION-INIT
    _lme-start
    _lme-report-a _lme-store LIBRARY-VFS-STORE-INSPECT _lme-status !
    _lme-stop
    LIBSTORE-S-OK _lme-expected-status !
    _lme-report-a _lme-current-report !
    _lme-report-a LIBINS.RAW-REQUIRED @ _lme-required !
    _lme-status @ _lme-expected-status @ = _lme-assert
    _lme-report-a _lme-report-healthy? _lme-assert
    S" inspect-first" _lme-report ;

: _lme-inspect-repeat  ( -- )
    S" inspect-repeat" _lme-gate
    _lme-report-b LIBRARY-INSPECTION-INIT
    _lme-start
    _lme-report-b _lme-store LIBRARY-VFS-STORE-INSPECT _lme-status !
    _lme-stop
    LIBSTORE-S-OK _lme-expected-status !
    _lme-report-b _lme-current-report !
    _lme-report-b LIBINS.RAW-REQUIRED @ _lme-required !
    _lme-status @ _lme-expected-status @ = _lme-assert
    _lme-report-b _lme-report-healthy? _lme-assert
    S" inspect-repeat" _lme-report
    _lme-report-a LIBINS.EVIDENCE-SEAL
        _lme-report-b LIBINS.EVIDENCE-SEAL SHA3-256-COMPARE _lme-assert ;

: _lme-activate  ( -- )
    _lme-store LIBRARY-VFS-STORE-LOAD
        LIBSTORE-S-OK = _lme-assert
    _lme-store LIBRARY-VFS-STORE-LOADED? _lme-assert
    _lme-store LIBRARY-VFS-STORE.GENERATION @
        _lme-expected-generation = _lme-assert ;

: _lme-raw-first  ( -- )
    S" raw-export-exact" _lme-gate
    _lme-start
    _lme-export LIBRARY-RAW-EXPORT-MAX _lme-report-b _lme-store
        LIBRARY-VFS-STORE-RAW-EXPORT
    _lme-status ! _lme-required !
    _lme-stop
    LIBSTORE-S-OK _lme-expected-status !
    _lme-report-b _lme-current-report !
    _lme-status @ _lme-expected-status @ = _lme-assert
    _lme-required @ 1463808 = _lme-assert
    S" raw-export-exact" _lme-report
    _lme-export _lme-required @ CRC32 _lme-export-crc ! ;

: _lme-raw-repeat  ( -- )
    S" raw-export-repeat" _lme-gate
    _lme-start
    _lme-export LIBRARY-RAW-EXPORT-MAX _lme-report-b _lme-store
        LIBRARY-VFS-STORE-RAW-EXPORT
    _lme-status ! _lme-required !
    _lme-stop
    LIBSTORE-S-OK _lme-expected-status !
    _lme-report-b _lme-current-report !
    _lme-status @ _lme-expected-status @ = _lme-assert
    _lme-required @ 1463808 = _lme-assert
    S" raw-export-repeat" _lme-report
    _lme-export _lme-required @ CRC32 _lme-export-crc @ = _lme-assert ;

: _lme-prepare-repair  ( -- )
    _lme-read-head _lme-write-stage
    _lme-stage-present? _lme-assert
    _lme-report-c LIBRARY-INSPECTION-INIT
    _lme-report-c _lme-store LIBRARY-VFS-STORE-INSPECT
        LIBSTORE-S-OK = _lme-assert
    _lme-report-c LIBINS.HEALTH @ LIBSTORE-S-RECOVERY = _lme-assert
    _lme-report-c LIBINS.REPAIR-MASK @
        LIBRARY-REPAIR-F-HEAD-TRANSACTION = _lme-assert
    _lme-report-c LIBINS.RAW-REQUIRED @ 1464320 = _lme-assert
    _lme-report-c LIBINS.REPAIRED-SEAL RID-PRESENT? _lme-assert ;

: _lme-repair  ( -- )
    S" repair-head-transaction" _lme-gate
    _lme-start
    _lme-report-c _lme-store LIBRARY-VFS-STORE-REPAIR _lme-status !
    _lme-stop
    LIBSTORE-S-OK _lme-expected-status !
    _lme-report-c _lme-current-report !
    _lme-report-c LIBINS.RAW-REQUIRED @ _lme-required !
    _lme-status @ _lme-expected-status @ = _lme-assert
    _lme-stage-present? 0= _lme-assert
    _lme-store LIBRARY-VFS-STORE-LOADED? _lme-assert
    _lme-store LIBRARY-VFS-STORE-BLOCKED? 0= _lme-assert
    S" repair-head-transaction" _lme-report ;

: _lme-final-check  ( -- )
    _lme-report-final LIBRARY-INSPECTION-INIT
    _lme-report-final _lme-store LIBRARY-VFS-STORE-INSPECT
        LIBSTORE-S-OK = _lme-assert
    _lme-report-final _lme-report-healthy? _lme-assert
    _lme-report-c LIBINS.REPAIRED-SEAL
        _lme-report-final LIBINS.EVIDENCE-SEAL
        SHA3-256-COMPARE _lme-assert
    ." LME FINAL health=" _lme-report-final LIBINS.HEALTH @ .
    ."  raw-required=" _lme-report-final LIBINS.RAW-REQUIRED @ .
    ."  generation=" _lme-report-final LIBINS.HEAD-GENERATION @ .
    ."  catalog=" _lme-report-final LIBINS.CATALOG-COUNT @ .
    ."  collections=" _lme-report-final LIBINS.COLLECTION-COUNT @ .
    ."  content-records=" _lme-report-final
        LIBINS.CONTENT-RECORD-COUNT @ . CR ;

: _lme-run  ( -- )
    0 _lme-fails ! 0 _lme-checks !
    _lme-bd BD-OPEN THROW
    _lme-bd _lme-volume VOL-RAW THROW
    4194304 A-XMEM ARENA-NEW IF -7882 THROW THEN
    _lme-volume VMP-NEW ?DUP IF THROW THEN
    DUP _lme-vfs ! VFS-USE
    _lme-vfs @ _lme-store LIBRARY-VFS-STORE-INIT
        LIBSTORE-S-OK = _lme-assert
    _lme-store LIBRARY-VFS-STORE-LOADED? 0= _lme-assert
    ." LME MEMORY maintenance-static=" 124784 .
    ."  activation-backups=" 122880 .
    ."  maintenance-staging-and-control=" 1904 .
    ."  caller-report=" LIBRARY-INSPECTION-SIZE .
    ."  optional-export-xmem=" LIBRARY-RAW-EXPORT-MAX .
    ."  profiler-vfs-xmem-arena=" 4194304 . CR
    ." LME COST raw-provisioned=" 1463808 .
    ."  raw-seven-object-max=" LIBRARY-RAW-EXPORT-MAX .
    ."  optional-transaction-budget="
        LIBRARY-RAW-EXPORT-MAX 1463808 - .
    ."  evidence-objects=" LIBRARY-EVIDENCE-OBJECT-N .
    ."  catalog-count=" _lme-expected-documents .
    ."  catalog-max=" LIB-CATALOG-MAX .
    ."  collection-count=" _lme-expected-collections .
    ."  collection-max=" LIB-COLLECTION-MAX .
    ."  content-tail=" _lme-expected-content-tail .
    ."  content-arena=" LIB-ARENA-SIZE . CR
    ." LME WORK inspect=raw-hash-plus-full-v1-validation"
    ."  raw-export=inspect-plus-exact-copy-plus-coherence-hash"
    ."  repair=fresh-inspect-plus-vrepl-reopen-load-post-inspect" CR
    ." LME PROFILE READY" CR
    _lme-inspect-first
    _lme-activate
    _lme-inspect-repeat
    _lme-raw-first
    _lme-raw-repeat
    _lme-prepare-repair
    _lme-repair
    _lme-final-check
    _lme-fails @ IF
        ." LME FAIL profile-total=" _lme-fails @ .
        ."  checks=" _lme-checks @ . CR
    ELSE
        ." LME PROFILE PASS checks=" _lme-checks @ . CR
    THEN ;

_lme-run
'''


def linked_layout(profile: Profile) -> tuple[tuple[str, ...], dict[str, bytes]]:
    """Reproduce and qualify the linked layout installed by ``build_image``."""
    if not profile.linked:
        raise ValueError("maintenance efficiency profile must be linked")
    modules = dependency_order(profile.roots)
    chunks = _linked_chunks(modules, profile.link_chunk_bytes)
    if not chunks:
        raise RuntimeError("maintenance linked closure produced no chunks")
    return modules, chunks


def assert_linked_manifest(
    filesystem: MP64FS, chunks: dict[str, bytes]
) -> tuple[str, ...]:
    """Ensure replacement retains the exact verified chunks from the build."""
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


def generated_leaf_chunks(
    source: str,
    modules: tuple[str, ...],
    maximum_bytes: int = GENERATED_LEAF_BYTES,
) -> dict[str, bytes]:
    """Split generated Forth only between complete top-level source units."""
    leaf_source = "\n".join(
        line
        for line in source.splitlines()
        if line.strip().upper() != "ENTER-USERLAND"
    )
    linked = _linked_autoexec(leaf_source + "\n", (), modules)
    units: list[bytearray] = []
    unit = bytearray()
    definition_depth = 0
    conditional_depth = 0
    for line in linked.splitlines(keepends=True):
        encoded = line.encode("utf-8")
        unit.extend(encoded)
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
            units.append(unit)
            unit = bytearray()
    if unit:
        raise RuntimeError("generated maintenance source ends inside a unit")

    chunks: list[bytearray] = []
    current = bytearray()
    for source_unit in units:
        if len(source_unit) > maximum_bytes:
            raise RuntimeError(
                "generated maintenance source unit exceeds "
                f"{maximum_bytes} bytes"
            )
        if current and len(current) + len(source_unit) > maximum_bytes:
            chunks.append(current)
            current = bytearray()
        current.extend(source_unit)
    if current:
        chunks.append(current)
    if not chunks:
        raise RuntimeError("generated maintenance source produced no chunks")
    return {
        f"{GENERATED_LEAF_PREFIX}{index:02d}.f": bytes(content)
        for index, content in enumerate(chunks)
    }


def install_linked_leaf(image: Path, profile: Profile, source: str) -> None:
    """Put generated units behind a tiny linked-loader autoexec leaf."""
    filesystem = MP64FS(bytearray(image.read_bytes()))
    modules, chunks = linked_layout(profile)
    chunk_names = assert_linked_manifest(filesystem, chunks)
    leaves = generated_leaf_chunks(source, modules)
    lines = ["ENTER-USERLAND"]
    lines.extend(f"REQUIRE {name}" for name in chunk_names)
    lines.extend(f"REQUIRE {name}" for name in leaves)
    autoexec = "\n".join(lines) + "\n"
    autoexec_bytes = autoexec.encode("utf-8")

    autoexec_match = filesystem.find_file("autoexec.f")
    if autoexec_match is None:
        raise RuntimeError("image has no autoexec.f to replace")
    for index in range(100):
        name = f"{GENERATED_LEAF_PREFIX}{index:02d}.f"
        if filesystem.find_file(name) is not None:
            filesystem.delete_file(name)
    filesystem.delete_file("autoexec.f")
    autoexec_entry = filesystem.inject_file(
        "autoexec.f", autoexec_bytes, ftype=FTYPE_FORTH
    )
    for name, content in leaves.items():
        filesystem.inject_file(name, content, ftype=FTYPE_FORTH)
    filesystem.save(image)
    print(
        f"LME IMAGE LAYOUT autoexec-start={autoexec_entry.start_sector} "
        f"autoexec-bytes={len(autoexec_bytes)} "
        f"generated-leaves={len(leaves)} "
        f"generated-leaf-bytes={','.join(str(len(item)) for item in leaves.values())}",
        flush=True,
    )


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
    next_progress_steps = 500_000_000
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
                f"LME RESULT {active_label} "
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
            if total_steps >= next_progress_steps:
                print(
                    f"LME HOST PROGRESS marker={marker!r} "
                    f"steps={total_steps} wall={time.perf_counter() - start:.6f} "
                    f"active={active_label or 'boot/setup'} "
                    f"transcript-bytes={len(raw.encode('utf-8'))}",
                    flush=True,
                )
                while total_steps >= next_progress_steps:
                    next_progress_steps += 500_000_000
            failure = next((item for item in FAILURES if item in raw), None)
            if failure is not None:
                raise RuntimeError(f"guest reported {failure!r}\n{raw[-8000:]}")
            now = time.perf_counter()
            lines = raw.splitlines()
            if active_label is not None and any(
                line.startswith(f"LME RESULT {active_label} ")
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
    """Run exactly one emulator in a spawn-isolated host process."""
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
        name=f"akashic-lme-{marker.lower().replace(' ', '-')}",
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
        if not line.startswith("LME RESULT "):
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
            "extmem",
            "status",
            "expected-status",
            "required",
            "health",
            "repair-mask",
            "raw-required",
            "generation",
            "catalog",
            "collections",
            "content-records",
            "content-tail",
            "stage-present",
            "loaded",
            "blocked",
        }
        missing = required - fields.keys()
        if missing:
            raise RuntimeError(
                f"guest result {label!r} lacks fields {sorted(missing)}"
            )
        results[label] = fields
    return results


def require_equal(
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
    missing = OPERATIONS - results.keys()
    if missing:
        raise RuntimeError(f"missing guest results: {sorted(missing)}")
    for operation in OPERATIONS:
        fields = results[operation]
        require_equal(
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
        require_equal(shape, operation, "stalls", fields["stalls"], 0)
        require_equal(shape, operation, "catalog", fields["catalog"], shape.documents)
        require_equal(
            shape,
            operation,
            "collections",
            fields["collections"],
            shape.collections,
        )
        require_equal(
            shape,
            operation,
            "content-records",
            fields["content-records"],
            shape.documents,
        )
        require_equal(
            shape,
            operation,
            "content-tail",
            fields["content-tail"],
            shape.content_tail,
        )
        require_equal(
            shape,
            operation,
            "generation",
            fields["generation"],
            shape.generation,
        )
        require_equal(shape, operation, "blocked", fields["blocked"], 0)

    require_equal(
        shape, "inspect-first", "loaded", results["inspect-first"]["loaded"], 0
    )
    for operation in OPERATIONS - {"inspect-first"}:
        require_equal(
            shape, operation, "loaded", results[operation]["loaded"], -1
        )

    for operation in OPERATIONS - {"repair-head-transaction"}:
        fields = results[operation]
        require_equal(
            shape, operation, "raw-required", fields["raw-required"], PROVISIONED_RAW
        )
        require_equal(shape, operation, "health", fields["health"], 0)
        require_equal(shape, operation, "repair-mask", fields["repair-mask"], 0)

    for operation in {"raw-export-exact", "raw-export-repeat"}:
        require_equal(
            shape, operation, "required", results[operation]["required"], PROVISIONED_RAW
        )

    repair = results["repair-head-transaction"]
    require_equal(
        shape,
        "repair-head-transaction",
        "raw-required",
        repair["raw-required"],
        RECOVERY_RAW,
    )
    require_equal(shape, "repair-head-transaction", "health", repair["health"], 10)
    require_equal(shape, "repair-head-transaction", "repair-mask", repair["repair-mask"], 1)
    require_equal(shape, "repair-head-transaction", "stage-present", repair["stage-present"], 0)
    require_equal(shape, "repair-head-transaction", "loaded", repair["loaded"], -1)
    require_equal(shape, "repair-head-transaction", "blocked", repair["blocked"], 0)

    if shape.name == "content-bound" and shape.content_tail != 594_944:
        raise RuntimeError(
            "content-bound shape no longer reaches nine maximum frames"
        )

    for first, repeat in (
        ("inspect-first", "inspect-repeat"),
        ("raw-export-exact", "raw-export-repeat"),
    ):
        first_cycles = results[first]["cycles"]
        repeat_cycles = results[repeat]["cycles"]
        limit = first_cycles * 2
        if repeat_cycles > limit:
            raise RuntimeError(
                f"{shape.name}/{repeat} used {repeat_cycles} cycles; "
                f"same-evidence 2x guard is {limit}"
            )
        print(
            f"LME QUALIFY shape={shape.name} operation={repeat} "
            f"cycles={repeat_cycles} first-cycles={first_cycles} "
            f"limit={limit} rule=same-evidence-at-most-2x result=PASS"
        )

    coverage = PROVISIONED_RAW / RAW_MAX
    print(
        f"LME QUALIFY shape={shape.name} raw-provisioned={PROVISIONED_RAW} "
        f"raw-seven-object-max={RAW_MAX} coverage={coverage:.6%} "
        f"catalog={shape.documents}/128 "
        f"content-payload={shape.content_tail - 512}/654848 result=PASS"
    )


def print_host_events(
    shape: Shape,
    phase: str,
    steps: int,
    wall: float,
    events: list[tuple[str, int, float]],
) -> None:
    print(
        f"LME HOST shape={shape.name} phase={phase} "
        f"scope=machine-session-inclusive steps={steps} wall={wall:.6f}"
    )
    for label, event_steps, event_wall in events:
        print(
            f"LME HOST EVENT shape={shape.name} phase={phase} "
            f"operation={label} steps={event_steps} wall={event_wall:.6f} "
            "sampling-steps=250000"
        )


def print_clock_interpretations(
    shape: Shape, results: dict[str, dict[str, int]]
) -> None:
    print(
        "LME CLOCK NOTE measured-hardware=false "
        "shared-memory-stalls-modeled=false "
        "external-memory-latency-modeled=false storage-io-modeled=false"
    )
    for operation, fields in results.items():
        cycles = fields["cycles"]
        print(
            f"LME CLOCK shape={shape.name} operation={operation} "
            f"at-100mhz-seconds={cycles / 100_000_000:.6f} "
            f"at-50mhz-seconds={cycles / 50_000_000:.6f} "
            f"reported-stalls={fields['stalls']} "
            f"reported-extmem={fields['extmem']}"
        )


def print_guest_model(shape: Shape, output: str) -> None:
    for line in output.splitlines():
        if line.startswith(
            ("LME MEMORY ", "LME COST ", "LME WORK ", "LME FINAL ")
        ):
            print(f"{shape.name} {line}")


def run_shape(shape: Shape, timeout: float, keep_image: bool) -> None:
    image = Path(
        f"/tmp/library-maintenance-efficiency-{shape.name}-{os.getpid()}.img"
    )
    previous = PROFILES.get(PROFILE_NAME)
    profile = Profile(
        roots=("library/vfs-store.f", "utils/fs/drivers/vfs-mp64fs.f"),
        resources=(),
        autoexec=setup_source(shape),
        ready_markers=(SETUP_DONE,),
        stable_markers=(SETUP_DONE,),
        failure_markers=FAILURES,
        linked=True,
        include_large_sample=False,
        total_sectors=8192,
    )
    PROFILES[PROFILE_NAME] = profile
    try:
        build_image(PROFILE_NAME, image)
    finally:
        if previous is None:
            del PROFILES[PROFILE_NAME]
        else:
            PROFILES[PROFILE_NAME] = previous

    # Keep generated setup/profile source behind the same verified linked
    # manifest and ordinary REQUIRE path used by real linked applications.
    install_linked_leaf(image, profile, setup_source(shape))
    print(f"LME HOST START shape={shape.name} phase=setup", flush=True)
    disk, _, steps, wall, events = run_in_fresh_process(
        image, SETUP_DONE, timeout
    )
    image.write_bytes(disk)
    print_host_events(shape, "setup", steps, wall, events)

    install_linked_leaf(image, profile, profile_source(shape))
    print(f"LME HOST START shape={shape.name} phase=profile", flush=True)
    _, output, steps, wall, events = run_in_fresh_process(
        image, PROFILE_DONE, timeout, "LME MEASURE "
    )
    print_host_events(shape, "profile", steps, wall, events)
    results = parse_results(output)
    for line in output.splitlines():
        if line.startswith("LME RESULT "):
            print(f"{shape.name} {line}")
    print_guest_model(shape, output)
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
        help="shape to run; defaults to representative and content-bound",
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
