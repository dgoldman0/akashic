#!/usr/bin/env python3
"""Build, smoke-test, and serve bootable Akashic TUI environments.

This is the supported cross-repository harness.  It imports the sibling
MegaPad checkout (or ``MEGAPAD_ROOT``), computes the transitive REQUIRE
closure for the selected app profile, and preserves Akashic's paths in an
MP64FS image.  No private emulator copy is required.
"""

from __future__ import annotations

import argparse
import json
import os
import posixpath
import re
import sys
import time
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path, PurePosixPath


AKASHIC_ROOT = Path(__file__).resolve().parents[1]
SOURCE_ROOT = AKASHIC_ROOT / "akashic"
DEFAULT_MEGAPAD_ROOT = AKASHIC_ROOT.parent / "megapad"
OUTPUT_ROOT = AKASHIC_ROOT / "local_testing" / "out"
REQUIRE_RE = re.compile(r"^\s*REQUIRE\s+(\S+)", re.MULTILINE)
PROVIDED_RE = re.compile(r"^\s*PROVIDED\s+(\S+)", re.MULTILINE)
# KDOS stores a terminating NUL in its 24-byte NAMEBUF, leaving 23 key bytes.
MODULE_KEY_BYTES = 23
# KDOS's module loader performs one 8-bit sector-count transfer.  Leave
# headroom below its 255-sector ceiling when linking deployment chunks.
LINK_CHUNK_BYTES = 120 * 1024
CODEX_AUTH_CHECKPOINT_FORMAT = "akashic-local-codex-auth-checkpoint"


def _megapad_root() -> Path:
    configured = os.environ.get("MEGAPAD_ROOT")
    root = Path(configured).expanduser() if configured else DEFAULT_MEGAPAD_ROOT
    root = root.resolve()
    required = ("bios.asm", "kdos.f", "diskutil.py", "session.py")
    missing = [name for name in required if not (root / name).is_file()]
    if missing:
        detail = ", ".join(missing)
        raise RuntimeError(
            f"MegaPad checkout not found at {root} (missing: {detail}). "
            "Set MEGAPAD_ROOT to the emulator repository."
        )
    return root


MEGAPAD_ROOT = _megapad_root()
DEFAULT_EXT_MEM_MIB = 32
sys.path.insert(0, str(MEGAPAD_ROOT))

from diskutil import (  # noqa: E402
    FLAG_SYSTEM,
    FTYPE_FORTH,
    FTYPE_TEXT,
    MAX_FILES,
    MAX_NAME_LEN,
    MP64FS,
)
from session import MachineSession  # noqa: E402


@dataclass(frozen=True)
class Profile:
    roots: tuple[str, ...]
    resources: tuple[str, ...]
    autoexec: str
    ready_markers: tuple[str, ...]
    stable_markers: tuple[str, ...]
    linked: bool = False
    requires_tap: bool = False
    failure_markers: tuple[str, ...] = ()
    initial_files: tuple[tuple[str, bytes], ...] = ()


def _practice_crc32(data: bytes) -> int:
    crc = 0xFFFFFFFF
    for byte in data:
        crc ^= byte << 24
        for _ in range(8):
            if crc & 0x80000000:
                crc = ((crc << 1) ^ 0x04C11DB7) & 0xFFFFFFFF
            else:
                crc = (crc << 1) & 0xFFFFFFFF
    return crc ^ 0xFFFFFFFF


def _practice_head_snapshot(generation: int) -> bytes:
    import struct

    head = bytearray(352)
    struct.pack_into("<Q", head, 0, 1095454792)  # PHEAD-MAGIC
    struct.pack_into("<Q", head, 8, 1)
    struct.pack_into("<Q", head, 16, len(head))
    struct.pack_into("<Q", head, 32, 1)  # Practice ID
    struct.pack_into("<Q", head, 64, 1)  # revision
    struct.pack_into("<Q", head, 72, 2)  # current root
    snapshot = bytearray(64 + len(head))
    snapshot[:8] = b"AKPHS001"
    struct.pack_into("<Q", snapshot, 8, 1)
    struct.pack_into("<Q", snapshot, 16, 64)
    struct.pack_into("<Q", snapshot, 24, generation)
    struct.pack_into("<Q", snapshot, 32, len(head))
    snapshot[64:] = head
    checksum_data = bytes(snapshot[:40] + snapshot[48:])
    struct.pack_into("<Q", snapshot, 40, _practice_crc32(checksum_data))
    return bytes(snapshot)


PROFILES = {
    "credential": Profile(
        roots=("security/credential.f",),
        resources=(),
        autoexec=r"""\ autoexec.f - native credential ownership tests
ENTER-USERLAND
." [akashic] loading credential owner" CR
REQUIRE security/credential.f

VARIABLE _ct-fails
VARIABLE _ct-checks
VARIABLE _ct-depth
: _ct-assert  ( flag -- )
    1 _ct-checks +!
    0= IF 1 _ct-fails +! ." ASSERT " _ct-checks @ . CR THEN ;
: _ct-stack  ( -- ) DEPTH _ct-depth @ = _ct-assert ;

CREATE _ct-credential CREDENTIAL-SIZE ALLOT
CREATE _ct-long CRED-SECRET-CAPACITY 1+ ALLOT
VARIABLE _ct-callbacks

: _ct-use  ( secret-a secret-u context -- status )
    77 = _ct-assert
    S" second" COMPARE 0= _ct-assert
    1 _ct-callbacks +! 9 ;
: _ct-throw  ( secret-a secret-u context -- status )
    DROP 2DROP -88 THROW 0 ;

: _ct-zero?  ( addr len -- flag )
    -1 -ROT 0 ?DO
        DUP I + C@ IF SWAP DROP 0 SWAP THEN
    LOOP
    DROP ;

: _ct-run  ( -- )
    0 _ct-fails ! 0 _ct-checks ! 0 _ct-callbacks ! DEPTH _ct-depth !
    _ct-credential CRED-INIT
    _ct-credential CRED-PRESENT? 0= _ct-assert
    ['] _ct-use 77 _ct-credential CRED-WITH CRED-S-ABSENT = _ct-assert

    S" first credential value" _ct-credential CRED-SET CRED-S-OK = _ct-assert
    _ct-credential CRED-PRESENT? _ct-assert
    _ct-credential CRED.LENGTH @ 22 = _ct-assert
    _ct-credential CRED.GENERATION @ 1 = _ct-assert

    S" second" _ct-credential CRED-SET CRED-S-OK = _ct-assert
    _ct-credential CRED.LENGTH @ 6 = _ct-assert
    _ct-credential _CRED-SECRET-A 6 + CRED-SECRET-CAPACITY 6 -
    _ct-zero? _ct-assert
    ['] _ct-use 77 _ct-credential CRED-WITH 9 = _ct-assert
    _ct-callbacks @ 1 = _ct-assert
    _ct-credential CRED.USES @ 1 = _ct-assert
    _ct-credential CRED.LAST-STATUS @ 9 = _ct-assert

    ['] _ct-throw 0 _ct-credential CRED-WITH CRED-S-CALLBACK = _ct-assert
    _ct-credential CRED.USES @ 2 = _ct-assert
    _ct-credential _CRED-SECRET-A 6 _ct-credential CRED-SET
    CRED-S-OVERLAP = _ct-assert

    _ct-long CRED-SECRET-CAPACITY 1+ 65 FILL
    _ct-long CRED-SECRET-CAPACITY 1+ _ct-credential CRED-SET
    CRED-S-TOO-LONG = _ct-assert
    0 1 _ct-credential CRED-SET CRED-S-INVALID = _ct-assert

    _ct-credential CRED-CLEAR
    _ct-credential CRED-PRESENT? 0= _ct-assert
    _ct-credential CRED.LENGTH @ 0= _ct-assert
    _ct-credential _CRED-SECRET-A CRED-SECRET-CAPACITY _ct-zero? _ct-assert
    _ct-credential CRED.GENERATION @ 3 = _ct-assert

    CRED-NEW DUP 0= _ct-assert DROP
    DUP CRED-PRESENT? 0= _ct-assert CRED-FREE
    _ct-stack
    _ct-fails @ 0= IF
        ." CREDENTIAL PASS " _ct-checks @ .
    ELSE
        ." CREDENTIAL FAIL " _ct-fails @ . ." / " _ct-checks @ .
    THEN CR ;

_ct-run
""",
        ready_markers=("CREDENTIAL PASS",),
        stable_markers=("CREDENTIAL PASS",),
    ),
    "agent-context": Profile(
        roots=("agent/turn-request.f", "agent/providers/devtools/scripted.f"),
        resources=(),
        autoexec=r"""\ autoexec.f - model context and structured turn contract
ENTER-USERLAND
." [akashic] loading agent context" CR
REQUIRE agent/turn-request.f
REQUIRE agent/providers/devtools/scripted.f

VARIABLE _cx-fails
VARIABLE _cx-checks
VARIABLE _cx-depth
VARIABLE _cx-context
VARIABLE _cx-item
VARIABLE _cx-provider
VARIABLE _cx-queue
CREATE _cx-turn AGENT-TURN-REQUEST-SIZE ALLOT
CREATE _cx-value CV-SIZE ALLOT

: _cx-assert  ( flag -- )
    1 _cx-checks +!
    0= IF 1 _cx-fails +! ." ASSERT " _cx-checks @ . CR THEN ;
: _cx-stack  ( -- )
    DEPTH DUP _cx-depth @ <> IF
        ." STACK " _cx-depth @ . ." -> " DUP . CR .S CR
    THEN
    _cx-depth @ = _cx-assert ;

: _cx-run  ( -- )
    0 _cx-fails ! 0 _cx-checks ! DEPTH _cx-depth !
    ACTX-NEW DUP ACTX-S-OK = _cx-assert DROP DUP _cx-context ! DROP
    AROLE-USER 1 S" first question" _cx-context @ ACTX-APPEND-MESSAGE
    DUP ACTX-S-OK = _cx-assert DROP DUP _cx-item ! DROP
    _cx-item @ ACTXI-VALID? _cx-assert
    _cx-context @ ACTX.COUNT @ 1 = _cx-assert
    _cx-stack

    _cx-value CV-INIT S" task input" _cx-value CV-STRING! 0= _cx-assert
    2 S" org.akashic.test" S" daybook.task.capture" S" call-2"
    _cx-value _cx-context @ ACTX-APPEND-TOOL-CALL-VALUE
    DUP ACTX-S-OK = _cx-assert DROP DROP
    2 S" daybook.task.capture"
    _cx-context @ ACTX-LAST-TOOL-CALL DUP 0<> _cx-assert DROP
    2 S" org.akashic.test" S" daybook.task.capture" S" call-2"
    _cx-value 0 _cx-context @ ACTX-APPEND-TOOL-RESULT-VALUE
    DUP ACTX-S-OK = _cx-assert DROP DROP
    _cx-context @ ACTX.COUNT @ 3 = _cx-assert
    _cx-stack

    _cx-turn ATURN-INIT
    1 _cx-turn ATURN.THREAD-ID ! 3 _cx-turn ATURN.RUN-ID !
    S" second question" _cx-turn ATURN.PROMPT-U ! _cx-turn ATURN.PROMPT-A !
    _cx-context @ _cx-turn ATURN.CONTEXT !
    _cx-context @ ACTX.COUNT @ _cx-turn ATURN.CONTEXT-N !
    _cx-context @ ACTX.REVISION @ _cx-turn ATURN.CONTEXT-REVISION !
    _cx-turn ATURN-VALID? _cx-assert
    _cx-stack

    SCRIPTED-PROVIDER-NEW DUP 0= _cx-assert DROP _cx-provider !
    AEQ-NEW DUP 0= _cx-assert DROP _cx-queue !
    _cx-turn _cx-queue @ _cx-provider @ APROV-START
    DUP 0= _cx-assert DROP
    _cx-provider @ SCRIPTED-LAST-CONTEXT-N 3 = _cx-assert
    _cx-stack
    _cx-provider @ APROV-FREE _cx-queue @ AEQ-FREE

    2 _cx-context @ ACTX-DROP-RUN
    _cx-context @ ACTX.COUNT @ 1 = _cx-assert
    _cx-context @ ACTX-DROP-LAST
    _cx-context @ ACTX.COUNT @ 0= _cx-assert
    _cx-value CV-FREE _cx-context @ ACTX-FREE
    _cx-stack
    _cx-fails @ 0= IF
        ." AGENT CONTEXT PASS " _cx-checks @ .
    ELSE
        ." AGENT CONTEXT FAIL " _cx-fails @ . ." / " _cx-checks @ .
    THEN CR ;

_cx-run
""",
        ready_markers=("AGENT CONTEXT PASS",),
        stable_markers=("AGENT CONTEXT PASS",),
    ),
    "conversation-store": Profile(
        roots=("agent/storage/vfs-conversation.f",),
        resources=(),
        autoexec=r"""\ autoexec.f - durable conversation snapshots
ENTER-USERLAND
." [akashic] loading conversation store" CR
REQUIRE agent/storage/vfs-conversation.f

VARIABLE _ts-fails
VARIABLE _ts-checks
VARIABLE _ts-depth
VARIABLE _ts-vfs
VARIABLE _ts-conv
VARIABLE _ts-loaded
VARIABLE _ts-store
VARIABLE _ts-store2
VARIABLE _ts-store3
VARIABLE _ts-store4
VARIABLE _ts-fd
VARIABLE _ts-snapshot-u
VARIABLE _ts-other-vfs
VARIABLE _ts-fault-buffer
VARIABLE _ts-fault-generation
VARIABLE _ts-fault-slot
VARIABLE _ts-fault-fd-head
VARIABLE _ts-fault-fd-next
VARIABLE _ts-fault-use-count
VARIABLE _ts-fault-read-count
VARIABLE _ts-fault-decode-count
VARIABLE _ts-fault-heap
VARIABLE _ts-fault-conv
VARIABLE _ts-probe-store
VARIABLE _ts-probe-conv
VARIABLE _ts-read-conv
VARIABLE _ts-read-generation
VARIABLE _ts-read-status
CREATE _ts-bad 8 ALLOT

: _ts-assert  ( flag -- )
    1 _ts-checks +!
    0= IF 1 _ts-fails +! ." ASSERT " _ts-checks @ . CR THEN ;
: _ts-stack  ( -- )
    DEPTH DUP _ts-depth @ <> IF
        ." STACK " _ts-depth @ . ." -> " DUP . CR .S CR
    THEN
    _ts-depth @ = _ts-assert ;

: _ts-new-store  ( -- store )
    _ts-vfs @ AVFSSTORE-NEW
    DUP ACSTORE-S-OK = _ts-assert DROP ;

: _ts-corrupt  ( path-a path-u -- )
    _ts-vfs @ VFS-USE
    VFS-OPEN DUP _ts-fd ! 0<> _ts-assert
    _ts-bad 8 88 FILL
    _ts-fd @ VFS-REWIND
    _ts-bad 8 _ts-fd @ VFS-WRITE 8 = _ts-assert
    _ts-fd @ VFS-CLOSE
    _ts-vfs @ VFS-SYNC 0= _ts-assert ;

: _ts-buffer-reusable?  ( size -- flag )
    ALLOCATE DUP IF 2DROP 0 EXIT THEN DROP
    DUP _ts-fault-buffer @ = >R FREE R> ;

: _ts-fault-begin  ( -- )
    0 _ts-fault-buffer !
    _ts-store @ AVFSSTORE.GENERATION @ _ts-fault-generation !
    _ts-store @ AVFSSTORE.ACTIVE-SLOT @ _ts-fault-slot !
    _ts-vfs @ V.FDFREE @ DUP _ts-fault-fd-head !
    ?DUP IF FD.FREE @ ELSE 0 THEN _ts-fault-fd-next !
    HEAP-FREE-BYTES _ts-fault-heap !
    _ts-other-vfs @ VFS-USE ;

: _ts-save-clean?  ( -- )
    VFS-CUR _ts-other-vfs @ = _ts-assert
    _AVW-FD @ 0= _ts-assert
    _AVW-BUF @ 0= _ts-assert
    _AVW-HAVE-OLD-VFS @ 0= _ts-assert
    _ts-vfs @ V.FDFREE @ DUP _ts-fault-fd-head @ = _ts-assert
    ?DUP IF FD.FREE @ ELSE 0 THEN
    _ts-fault-fd-next @ = _ts-assert
    HEAP-FREE-BYTES _ts-fault-heap @ = _ts-assert
    _ts-store @ AVFSSTORE.GENERATION @
    _ts-fault-generation @ = _ts-assert
    _ts-store @ AVFSSTORE.ACTIVE-SLOT @
    _ts-fault-slot @ = _ts-assert ;

: _ts-read-clean?  ( -- )
    VFS-CUR _ts-other-vfs @ = _ts-assert
    _AVR-FD @ 0= _ts-assert
    _AVR-BUF @ 0= _ts-assert
    _AVR-HAVE-OLD-VFS @ 0= _ts-assert
    _ts-vfs @ V.FDFREE @ DUP _ts-fault-fd-head @ = _ts-assert
    ?DUP IF FD.FREE @ ELSE 0 THEN
    _ts-fault-fd-next @ = _ts-assert
    HEAP-FREE-BYTES _ts-fault-heap @ = _ts-assert
    _ts-store @ AVFSSTORE.GENERATION @
    _ts-fault-generation @ = _ts-assert
    _ts-store @ AVFSSTORE.ACTIVE-SLOT @
    _ts-fault-slot @ = _ts-assert ;

: _ts-save-published-clean?  ( -- )
    VFS-CUR _ts-other-vfs @ = _ts-assert
    _AVW-FD @ 0= _ts-assert
    _AVW-BUF @ 0= _ts-assert
    _AVW-HAVE-OLD-VFS @ 0= _ts-assert
    _ts-vfs @ V.FDFREE @ DUP _ts-fault-fd-head @ = _ts-assert
    ?DUP IF FD.FREE @ ELSE 0 THEN
    _ts-fault-fd-next @ = _ts-assert
    HEAP-FREE-BYTES _ts-fault-heap @ = _ts-assert
    _ts-store @ AVFSSTORE.GENERATION @
    _ts-fault-generation @ 1+ = _ts-assert
    _ts-store @ AVFSSTORE.ACTIVE-SLOT @
    _ts-fault-slot @ = 0= _ts-assert ;

: _ts-throw-use  ( vfs -- )
    _AVW-BUF @ _ts-fault-buffer !
    DUP VFS-USE DROP -701 THROW ;
: _ts-throw-use-on-restore  ( vfs -- )
    1 _ts-fault-use-count +!
    DUP VFS-USE
    _ts-fault-use-count @ 2 = IF
        DROP _AVW-BUF @ _ts-fault-buffer ! -709 THROW
    THEN
    DROP ;
: _ts-throw-open  ( path-a path-u -- fd )
    2DROP _AVW-BUF @ _ts-fault-buffer ! -702 THROW ;
: _ts-open-missing  ( path-a path-u -- fd )
    2DROP 0 ;
: _ts-throw-create  ( path-a path-u vfs -- inode )
    DROP 2DROP _AVW-BUF @ _ts-fault-buffer ! -710 THROW ;
: _ts-throw-read  ( buf len fd -- ior )
    2DROP _ts-fault-buffer ! -703 THROW ;
: _ts-throw-read-second  ( buf len fd -- ior )
    1 _ts-fault-read-count +!
    _ts-fault-read-count @ 2 = IF
        2DROP _ts-fault-buffer ! -703 THROW
    THEN
    VFS-READ-EXACT ;
: _ts-throw-write  ( buf len fd -- ior )
    2DROP _ts-fault-buffer ! -704 THROW ;
: _ts-throw-close  ( fd -- )
    _AVW-BUF @ _ts-fault-buffer ! VFS-CLOSE -705 THROW ;
: _ts-throw-sync  ( vfs -- ior )
    _AVW-BUF @ _ts-fault-buffer ! VFS-SYNC DROP -706 THROW ;
: _ts-fail-sync  ( vfs -- ior )
    DROP 1 ;
: _ts-throw-encode-size  ( conversation -- length status )
    DROP -711 THROW ;
: _ts-throw-encode  ( generation conversation buf capacity -- len status )
    DROP _ts-fault-buffer ! 2DROP -707 THROW ;
: _ts-throw-decode  ( buf len -- conversation generation status )
    DROP _ts-fault-buffer ! -708 THROW ;
: _ts-throw-decode-second  ( buf len -- conversation generation status )
    1 _ts-fault-decode-count +!
    _ts-fault-decode-count @ 2 = IF
        DROP _ts-fault-buffer ! -708 THROW
    THEN
    ATHREAD-DECODE ;
: _ts-throw-conv-free  ( conversation -- )
    ACONV-FREE -712 THROW ;
: _ts-throw-guard-release  ( guard -- )
    DUP GUARD-RELEASE DROP -713 THROW ;

: _ts-probe-newer  ( -- )
    _ts-vfs @ AVFSSTORE-NEW
    DUP ACSTORE-S-OK = _ts-assert DROP _ts-probe-store !
    _ts-probe-store @ ACSTORE-LOAD
    DUP ACSTORE-S-OK = _ts-assert DROP
    DUP 0<> _ts-assert _ts-probe-conv !
    _ts-probe-store @ AVFSSTORE.GENERATION @
    _ts-fault-generation @ 1+ = _ts-assert
    _ts-probe-store @ AVFSSTORE.ACTIVE-SLOT @
    _ts-fault-slot @ = 0= _ts-assert
    _ts-probe-conv @ ACONV-FREE
    _ts-probe-store @ ACSTORE-FREE
    0 _ts-probe-conv ! 0 _ts-probe-store !
    HEAP-FREE-BYTES _ts-fault-heap @ = _ts-assert ;

: _ts-test-load-guard-release  ( -- )
    _ts-vfs @ AVFSSTORE-NEW
    DUP ACSTORE-S-OK = _ts-assert DROP _ts-probe-store !
    _ts-fault-begin
    ['] _ts-throw-guard-release _AVFS-GUARD-RELEASE-XT !
    _ts-probe-store @ ACSTORE-LOAD
    DUP ACSTORE-S-IO = _ts-assert DROP 0= _ts-assert
    _AVFS-RESET-DEPENDENCIES _ts-read-clean?
    _ts-probe-store @ AVFSSTORE.GENERATION @
    _ts-fault-generation @ 1+ = _ts-assert
    _ts-probe-store @ AVFSSTORE.ACTIVE-SLOT @
    _ts-fault-slot @ = 0= _ts-assert
    _ts-probe-store @ ACSTORE-FREE 0 _ts-probe-store !
    _ts-stack ;

: _ts-read-result!  ( conversation generation status -- )
    _ts-read-status ! _ts-read-generation ! _ts-read-conv ! ;

: _ts-test-fault-cleanup  ( -- )
    ACONV-NEW DUP 0= _ts-assert DROP _ts-fault-conv !
    \ Re-establish one known-valid generation after the corruption tests.
    _ts-vfs @ VFS-USE
    _ts-fault-conv @ _ts-store @ ACSTORE-SAVE ACSTORE-S-OK = _ts-assert

    524288 A-XMEM ARENA-NEW DUP 0= _ts-assert DROP
    VFS-RAM-VTABLE VFS-NEW DUP _ts-other-vfs ! DROP

    _ts-fault-begin ['] _ts-throw-encode-size _AVFS-ENCODE-SIZE-XT !
    _ts-fault-conv @ _ts-store @ ACSTORE-SAVE ACSTORE-S-IO = _ts-assert
    _AVFS-RESET-DEPENDENCIES _ts-save-clean? _ts-stack

    _ts-fault-begin ['] _ts-throw-encode _AVFS-ENCODE-XT !
    _ts-fault-conv @ _ts-store @ ACSTORE-SAVE ACSTORE-S-IO = _ts-assert
    _AVFS-RESET-DEPENDENCIES _ts-save-clean?
    _ts-fault-buffer @ 0<> _ts-assert
    _AVW-SIZE @ _ts-buffer-reusable? _ts-assert _ts-stack

    _ts-fault-begin ['] _ts-throw-use _AVFS-USE-XT !
    _ts-fault-conv @ _ts-store @ ACSTORE-SAVE ACSTORE-S-IO = _ts-assert
    _AVFS-RESET-DEPENDENCIES _ts-save-clean?
    _ts-fault-buffer @ 0<> _ts-assert
    _AVW-SIZE @ _ts-buffer-reusable? _ts-assert _ts-stack

    _ts-fault-begin 0 _ts-fault-use-count !
    ['] _ts-throw-use-on-restore _AVFS-USE-XT !
    _ts-fault-conv @ _ts-store @ ACSTORE-SAVE
    ACSTORE-S-UNCERTAIN = _ts-assert
    _AVFS-RESET-DEPENDENCIES _ts-save-clean?
    _ts-fault-buffer @ 0<> _ts-assert
    _AVW-SIZE @ _ts-buffer-reusable? _ts-assert _ts-stack

    _ts-fault-begin ['] _ts-throw-open _AVFS-OPEN-XT !
    _ts-fault-conv @ _ts-store @ ACSTORE-SAVE ACSTORE-S-IO = _ts-assert
    _AVFS-RESET-DEPENDENCIES _ts-save-clean?
    _ts-fault-buffer @ 0<> _ts-assert
    _AVW-SIZE @ _ts-buffer-reusable? _ts-assert _ts-stack

    _ts-fault-begin
    ['] _ts-open-missing _AVFS-OPEN-XT !
    ['] _ts-throw-create _AVFS-CREATE-XT !
    _ts-fault-conv @ _ts-store @ ACSTORE-SAVE ACSTORE-S-IO = _ts-assert
    _AVFS-RESET-DEPENDENCIES _ts-save-clean?
    _ts-fault-buffer @ 0<> _ts-assert
    _AVW-SIZE @ _ts-buffer-reusable? _ts-assert _ts-stack

    _ts-fault-begin ['] _ts-throw-write _AVFS-WRITE-XT !
    _ts-fault-conv @ _ts-store @ ACSTORE-SAVE
    ACSTORE-S-UNCERTAIN = _ts-assert
    _AVFS-RESET-DEPENDENCIES _ts-save-clean?
    _ts-fault-buffer @ 0<> _ts-assert
    _AVW-SIZE @ _ts-buffer-reusable? _ts-assert _ts-stack

    _ts-fault-begin ['] _ts-throw-close _AVFS-CLOSE-XT !
    _ts-fault-conv @ _ts-store @ ACSTORE-SAVE
    ACSTORE-S-UNCERTAIN = _ts-assert
    _AVFS-RESET-DEPENDENCIES _ts-save-clean?
    _ts-fault-buffer @ 0<> _ts-assert
    _AVW-SIZE @ _ts-buffer-reusable? _ts-assert
    _ts-probe-newer _ts-stack

    _ts-fault-begin ['] _ts-throw-sync _AVFS-SYNC-XT !
    _ts-fault-conv @ _ts-store @ ACSTORE-SAVE
    ACSTORE-S-UNCERTAIN = _ts-assert
    _AVFS-RESET-DEPENDENCIES _ts-save-clean?
    _ts-fault-buffer @ 0<> _ts-assert
    _AVW-SIZE @ _ts-buffer-reusable? _ts-assert _ts-stack

    _ts-fault-begin ['] _ts-fail-sync _AVFS-SYNC-XT !
    _ts-fault-conv @ _ts-store @ ACSTORE-SAVE
    ACSTORE-S-UNCERTAIN = _ts-assert
    _AVFS-RESET-DEPENDENCIES _ts-save-clean? _ts-stack

    _ts-fault-begin 0 _ts-fault-read-count !
    ['] _ts-throw-read-second _AVFS-READ-XT !
    _ts-store @ ACSTORE-LOAD
    DUP ACSTORE-S-IO = _ts-assert DROP 0= _ts-assert
    _AVFS-RESET-DEPENDENCIES
    _ts-read-clean?
    _ts-fault-buffer @ 0<> _ts-assert
    _ts-stack

    _ts-fault-begin 0 _ts-fault-decode-count !
    ['] _ts-throw-decode-second _AVFS-DECODE-XT !
    _ts-store @ ACSTORE-LOAD
    DUP ACSTORE-S-IO = _ts-assert DROP 0= _ts-assert
    _AVFS-RESET-DEPENDENCIES
    _ts-read-clean?
    _ts-fault-buffer @ 0<> _ts-assert
    _ts-stack

    _ts-fault-begin ['] _ts-throw-conv-free _AVFS-CONV-FREE-XT !
    _ts-store @ ACSTORE-LOAD
    DUP ACSTORE-S-IO = _ts-assert DROP 0= _ts-assert
    _AVFS-RESET-DEPENDENCIES _ts-read-clean? _ts-stack

    _ts-test-load-guard-release

    _ts-fault-begin
    ['] _ts-throw-guard-release _AVFS-GUARD-RELEASE-XT !
    _ts-fault-conv @ _ts-store @ ACSTORE-SAVE
    ACSTORE-S-UNCERTAIN = _ts-assert
    _AVFS-RESET-DEPENDENCIES _ts-save-published-clean?
    _ts-store @ ACSTORE.LAST-STATUS @
    ACSTORE-S-UNCERTAIN = _ts-assert _ts-stack

    \ Ordinary use remains possible after contained and post-body faults.
    _ts-fault-begin
    _ts-fault-conv @ _ts-store @ ACSTORE-SAVE ACSTORE-S-OK = _ts-assert
    VFS-CUR _ts-other-vfs @ = _ts-assert
    _ts-store @ AVFSSTORE.GENERATION @
    _ts-fault-generation @ 1+ = _ts-assert
    _ts-store @ AVFSSTORE.ACTIVE-SLOT @
    _ts-fault-slot @ = 0= _ts-assert
    _ts-fault-conv @ ACONV-FREE 0 _ts-fault-conv !
    _ts-stack ;

: _ts-run  ( -- )
    0 _ts-fails ! 0 _ts-checks ! DEPTH _ts-depth !
    524288 A-XMEM ARENA-NEW
    DUP 0= _ts-assert DROP
    VFS-RAM-VTABLE VFS-NEW DUP _ts-vfs ! VFS-USE
    ACONV-NEW DUP 0= _ts-assert DROP _ts-conv !

    AROLE-USER AMSG-S-COMPLETE 1 S" first durable message"
    _ts-conv @ ACONV-APPEND DUP 0= _ts-assert DROP
    DUP AMSG-F-AUDIT SWAP AMSG.FLAGS ! DROP
    AROLE-USER 1 S" first durable message"
    _ts-conv @ ACONV.MODEL-CONTEXT @ ACTX-APPEND-MESSAGE
    DUP ACTX-S-OK = _ts-assert DROP DROP
    1 S" org.akashic.test" S" reasoning" S" {}"
    _ts-conv @ ACONV.MODEL-CONTEXT @ ACTX-APPEND-PROVIDER
    DUP ACTX-S-OK = _ts-assert DROP DROP
    1 S" org.akashic.test" S" daybook.task.capture" S" call-1" S" {}"
    _ts-conv @ ACONV.MODEL-CONTEXT @ ACTX-APPEND-TOOL-CALL
    DUP ACTX-S-OK = _ts-assert DROP DROP
    1 S" org.akashic.test" S" daybook.task.capture" S" call-1"
    S" true" 0 _ts-conv @ ACONV.MODEL-CONTEXT @
    ACTX-APPEND-TOOL-RESULT DUP ACTX-S-OK = _ts-assert DROP DROP
    AROLE-ASSISTANT 1 S" first durable answer"
    _ts-conv @ ACONV.MODEL-CONTEXT @ ACTX-APPEND-MESSAGE
    DUP ACTX-S-OK = _ts-assert DROP DROP
    _ts-conv @ ATHREAD-ENCODE-SIZE
    DUP ATHREAD-S-OK = _ts-assert DROP DUP _ts-snapshot-u !
    ATHREAD-HEADER-SIZE > _ts-assert
    _ts-new-store DUP _ts-store !
    _ts-conv @ SWAP ACSTORE-SAVE ACSTORE-S-OK = _ts-assert
    _ts-store @ AVFSSTORE.GENERATION @ 1 = _ts-assert
    _ts-store @ AVFSSTORE.ACTIVE-SLOT @ 0= _ts-assert
    _AVFS-PATH-A VFS-OPEN DUP _ts-fd ! 0<> _ts-assert
    _ts-fd @ VFS-SIZE _ts-snapshot-u @ = _ts-assert
    _ts-fd @ VFS-CLOSE

    AROLE-ASSISTANT AMSG-S-STREAMING 2 S" interrupted output"
    _ts-conv @ ACONV-APPEND DUP 0= _ts-assert DROP DROP
    AROLE-USER 2 S" interrupted question"
    _ts-conv @ ACONV.MODEL-CONTEXT @ ACTX-APPEND-MESSAGE
    DUP ACTX-S-OK = _ts-assert DROP DROP
    _ts-conv @ _ts-store @ ACSTORE-SAVE ACSTORE-S-OK = _ts-assert
    _ts-store @ AVFSSTORE.GENERATION @ 2 = _ts-assert
    _ts-store @ AVFSSTORE.ACTIVE-SLOT @ 1 = _ts-assert

    _ts-new-store DUP _ts-store2 ! ACSTORE-LOAD
    DUP ACSTORE-S-OK = _ts-assert DROP DUP _ts-loaded ! DROP
    _ts-store2 @ AVFSSTORE.GENERATION @ 2 = _ts-assert
    _ts-loaded @ ACONV.COUNT @ 3 = _ts-assert
    _ts-loaded @ ACONV.MODEL-CONTEXT @ ACTX.COUNT @ 5 = _ts-assert
    1 _ts-loaded @ ACONV.MODEL-CONTEXT @ ACTX-NTH
    ACTXI-DATA-TEXT S" {}" STR-STR= _ts-assert
    2 _ts-loaded @ ACONV.MODEL-CONTEXT @ ACTX-NTH
    ACTXI-CALL-ID-TEXT S" call-1" STR-STR= _ts-assert
    1 _ts-loaded @ ACONV-NTH DUP AMSG.STATE @ AMSG-S-CANCELLED = _ts-assert
    AMSG.FLAGS @ AMSG-F-RECOVERED AND 0<> _ts-assert
    2 _ts-loaded @ ACONV-NTH AMSG-TEXT
    S" interrupted before completion" STR-STR-CONTAINS _ts-assert
    _ts-loaded @ ACONV-FREE

    _AVFS-PATH-B _ts-corrupt
    _ts-new-store DUP _ts-store3 ! ACSTORE-LOAD
    DUP ACSTORE-S-OK = _ts-assert DROP DUP _ts-loaded ! DROP
    _ts-store3 @ AVFSSTORE.GENERATION @ 1 = _ts-assert
    _ts-loaded @ ACONV.COUNT @ 1 = _ts-assert
    _ts-loaded @ ACONV.MODEL-CONTEXT @ ACTX.COUNT @ 5 = _ts-assert
    0 _ts-loaded @ ACONV-NTH AMSG-TEXT
    S" first durable message" STR-STR= _ts-assert
    _ts-loaded @ ACONV-FREE

    _AVFS-PATH-A _ts-corrupt
    _ts-new-store DUP _ts-store4 ! ACSTORE-LOAD
    ACSTORE-S-INVALID = _ts-assert 0= _ts-assert

    _ts-test-fault-cleanup

    _ts-store4 @ ACSTORE-FREE
    _ts-store3 @ ACSTORE-FREE
    _ts-store2 @ ACSTORE-FREE
    _ts-store @ ACSTORE-FREE
    _ts-conv @ ACONV-FREE
    0 VFS-USE
    _ts-other-vfs @ VFS-DESTROY
    _ts-vfs @ VFS-DESTROY
    _ts-stack
    _ts-fails @ 0= IF
        ." CONVERSATION STORE PASS " _ts-checks @ .
    ELSE
        ." CONVERSATION STORE FAIL " _ts-fails @ . ." / " _ts-checks @ .
    THEN CR ;

_ts-run
""",
        ready_markers=("CONVERSATION STORE PASS",),
        stable_markers=("CONVERSATION STORE PASS",),
    ),
    "agent-persistence": Profile(
        roots=(
            "agent/storage/vfs-conversation.f",
            "agent/runtime.f",
            "agent/providers/devtools/scripted.f",
        ),
        resources=(),
        autoexec=r"""\ autoexec.f - durable agent runtime lifecycle
ENTER-USERLAND
." [akashic] loading agent persistence lifecycle" CR
REQUIRE agent/storage/vfs-conversation.f
REQUIRE agent/providers/devtools/scripted.f
REQUIRE agent/runtime.f

VARIABLE _ap-fails
VARIABLE _ap-checks
VARIABLE _ap-depth
VARIABLE _ap-vfs
VARIABLE _ap-source
VARIABLE _ap-provider
VARIABLE _ap-runtime
VARIABLE _ap-store
VARIABLE _ap-conv
VARIABLE _ap-msg

: _ap-assert  ( flag -- )
    1 _ap-checks +!
    0= IF 1 _ap-fails +! ." ASSERT " _ap-checks @ . CR THEN ;
: _ap-stack  ( -- )
    DEPTH DUP _ap-depth @ <> IF
        ." STACK " _ap-depth @ . ." -> " DUP . CR .S CR
    THEN
    _ap-depth @ = _ap-assert ;

: _ap-open  ( -- )
    SCRIPTED-SOURCE-NEW DUP 0= _ap-assert DROP _ap-source !
    _ap-source @ APSOURCE-PROVIDER-NEW
    DUP 0= _ap-assert DROP _ap-provider !
    _ap-provider @ ARUNTIME-NEW
    DUP 0= _ap-assert DROP _ap-runtime !
    _ap-vfs @ AVFSSTORE-NEW
    DUP ACSTORE-S-OK = _ap-assert DROP DUP _ap-store !
    _ap-runtime @ ARUNTIME-CONVERSATION-STORE!
    ACSTORE-S-OK = _ap-assert
    _ap-runtime @ ARUNTIME.CONVERSATION @ _ap-conv ! ;

: _ap-close  ( -- )
    _ap-runtime @ ARUNTIME-FREE
    _ap-provider @ APROV-FREE
    _ap-source @ APSOURCE-FREE
    0 _ap-runtime ! 0 _ap-provider ! 0 _ap-source ! 0 _ap-store ! ;

: _ap-pump  ( count -- )
    0 ?DO 8 _ap-runtime @ ARUNTIME-PUMP DROP LOOP ;
: _ap-message  ( index -- message )
    _ap-conv @ ACONV-NTH ;

: _ap-check-audit  ( -- )
    3 _ap-message DUP 0<> _ap-assert _ap-msg !
    _ap-msg @ AMSG.ROLE @ AROLE-SYSTEM = _ap-assert
    _ap-msg @ AMSG.FLAGS @ DUP AMSG-F-AUDIT AND 0<> _ap-assert
    AMSG-F-APPROVED AND 0<> _ap-assert
    _ap-msg @ AMSG-TEXT
    S" Approved agent action: Persist the simulated change?" STR-STR=
    _ap-assert ;

: _ap-run  ( -- )
    0 _ap-fails ! 0 _ap-checks ! DEPTH _ap-depth !
    524288 A-XMEM ARENA-NEW DUP 0= _ap-assert DROP
    VFS-RAM-VTABLE VFS-NEW DUP _ap-vfs ! VFS-USE

    _ap-open 2 _ap-pump
    _ap-runtime @ ARUNTIME.STATUS @ ARUN-S-IDLE = _ap-assert
    S" approval durable history" _ap-runtime @ ARUNTIME-SEND 0= _ap-assert
    4 _ap-pump
    _ap-runtime @ ARUNTIME.STATUS @ ARUN-S-APPROVAL = _ap-assert
    -1 _ap-runtime @ ARUNTIME-RESOLVE 0= _ap-assert
    2 _ap-pump
    _ap-runtime @ ARUNTIME.STATUS @ ARUN-S-IDLE = _ap-assert
    _ap-conv @ ACONV.COUNT @ 4 = _ap-assert
    _ap-runtime @ ARUNTIME-MODEL-CONTEXT ACTX.COUNT @ 2 = _ap-assert
    _ap-check-audit
    _ap-runtime @ ARUNTIME.STORE-STATUS @ ACSTORE-S-OK = _ap-assert
    _ap-close _ap-stack

    _ap-open 2 _ap-pump
    _ap-conv @ ACONV.COUNT @ 4 = _ap-assert
    _ap-runtime @ ARUNTIME-MODEL-CONTEXT ACTX.COUNT @ 2 = _ap-assert
    _ap-check-audit
    _ap-runtime @ ARUNTIME.NEXT-RUN @ 2 = _ap-assert
    S" approval interrupted persistence" _ap-runtime @ ARUNTIME-SEND
    0= _ap-assert
    _ap-provider @ SCRIPTED-LAST-CONTEXT-N 2 = _ap-assert
    4 _ap-pump
    _ap-runtime @ ARUNTIME.STATUS @ ARUN-S-APPROVAL = _ap-assert
    _ap-conv @ ACONV.COUNT @ 7 = _ap-assert
    _ap-runtime @ ARUNTIME-MODEL-CONTEXT ACTX.COUNT @ 3 = _ap-assert
    _ap-runtime @ ARUNTIME-PERSIST-FORCE ACSTORE-S-OK = _ap-assert
    _ap-close _ap-stack

    _ap-open 2 _ap-pump
    _ap-runtime @ ARUNTIME.STATUS @ ARUN-S-IDLE = _ap-assert
    _ap-conv @ ACONV.COUNT @ 8 = _ap-assert
    5 _ap-message DUP AMSG.STATE @ AMSG-S-CANCELLED = _ap-assert
    AMSG.FLAGS @ AMSG-F-RECOVERED AND 0<> _ap-assert
    6 _ap-message DUP AMSG.STATE @ AMSG-S-CANCELLED = _ap-assert
    AMSG.FLAGS @ AMSG-F-RECOVERED AND 0<> _ap-assert
    7 _ap-message AMSG.FLAGS @ DUP AMSG-F-AUDIT AND 0<> _ap-assert
    AMSG-F-RECOVERED AND 0<> _ap-assert
    7 _ap-message AMSG-TEXT
    S" Previous agent run was interrupted before completion." STR-STR=
    _ap-assert
    _ap-runtime @ ARUNTIME.NEXT-RUN @ 3 = _ap-assert
    _ap-runtime @ ARUNTIME-MODEL-CONTEXT ACTX.COUNT @ 2 = _ap-assert
    _ap-runtime @ ARUNTIME-CLEAR 0= _ap-assert
    _ap-conv @ ACONV.COUNT @ 0= _ap-assert
    _ap-runtime @ ARUNTIME-MODEL-CONTEXT ACTX.COUNT @ 0= _ap-assert
    _ap-close _ap-stack

    _ap-open 2 _ap-pump
    _ap-conv @ ACONV.COUNT @ 0= _ap-assert
    _ap-runtime @ ARUNTIME-MODEL-CONTEXT ACTX.COUNT @ 0= _ap-assert
    _ap-runtime @ ARUNTIME.STORE-STATUS @ ACSTORE-S-OK = _ap-assert
    _ap-close
    _ap-vfs @ VFS-DESTROY
    _ap-stack
    _ap-fails @ 0= IF
        ." AGENT PERSISTENCE PASS " _ap-checks @ .
    ELSE
        ." AGENT PERSISTENCE FAIL " _ap-fails @ . ." / " _ap-checks @ .
    THEN CR ;

_ap-run
""",
        ready_markers=("AGENT PERSISTENCE PASS",),
        stable_markers=("AGENT PERSISTENCE PASS",),
    ),
    "http-request": Profile(
        roots=("net/http-request.f",),
        resources=(),
        autoexec=r"""\ autoexec.f - native bounded HTTP request tests
ENTER-USERLAND
." [akashic] loading HTTP request writer" CR
REQUIRE net/http-request.f

VARIABLE _rt-fails
VARIABLE _rt-checks
VARIABLE _rt-depth
: _rt-assert  ( flag -- )
    1 _rt-checks +!
    0= IF 1 _rt-fails +! ." ASSERT " _rt-checks @ . CR THEN ;
: _rt-stack  ( -- )
    DEPTH DUP _rt-depth @ <> IF
        ." STACK " _rt-depth @ . ." -> " DUP . CR .S CR
    THEN
    _rt-depth @ = _rt-assert ;

CREATE _rt-request HTTP-REQUEST-SIZE ALLOT
CREATE _rt-buffer 1024 ALLOT
CREATE _rt-small 66 ALLOT
CREATE _rt-port NET-IO-PORT-SIZE ALLOT
CREATE _rt-sink 1024 ALLOT
CREATE _rt-expected 1024 ALLOT
VARIABLE _rt-sink-u
VARIABLE _rt-expected-u
VARIABLE _rt-polls
VARIABLE _rt-mode
VARIABLE _rt-send-a
VARIABLE _rt-send-u
VARIABLE _rt-send-n
VARIABLE _rt-zero
VARIABLE _rt-result

: _rt-e,  ( addr len -- )
    DUP >R _rt-expected _rt-expected-u @ + SWAP CMOVE
    R> _rt-expected-u +! ;
: _rt-ec,  ( c -- )
    _rt-expected _rt-expected-u @ + C! 1 _rt-expected-u +! ;
: _rt-crlf,  ( -- ) 13 _rt-ec, 10 _rt-ec, ;

: _rt-build-expected  ( -- )
    0 _rt-expected-u !
    S" POST /v1/responses HTTP/1.1" _rt-e, _rt-crlf,
    S" Host: api.openai.com" _rt-e, _rt-crlf,
    S" Authorization: Bearer test-secret" _rt-e, _rt-crlf,
    S" Content-Type: application/json" _rt-e, _rt-crlf,
    S" Accept: text/event-stream" _rt-e, _rt-crlf,
    S" Connection: close" _rt-e, _rt-crlf,
    S" Content-Length: 2" _rt-e, _rt-crlf,
    _rt-crlf, S" {}" _rt-e, ;

: _rt-poll  ( context -- ) DROP 1 _rt-polls +! ;
: _rt-close  ( context -- ) DROP ;
: _rt-send  ( buffer length context -- count status )
    DROP _rt-send-u ! _rt-send-a !
    _rt-mode @ 1 = IF 0 NIO-S-OK EXIT THEN
    _rt-mode @ 2 = IF 0 NIO-S-FAILED EXIT THEN
    _rt-mode @ 3 = IF 0 NIO-S-CANCELLED EXIT THEN
    _rt-mode @ 4 = IF _rt-send-u @ 1+ NIO-S-OK EXIT THEN
    _rt-mode @ 5 = IF -77 THROW THEN
    _rt-send-u @ 7 MIN _rt-send-n !
    _rt-send-a @ _rt-sink _rt-sink-u @ + _rt-send-n @ CMOVE
    _rt-send-n @ _rt-sink-u +!
    _rt-send-n @ NIO-S-OK ;

: _rt-port-reset  ( mode -- )
    _rt-mode ! 0 _rt-sink-u ! 0 _rt-polls !
    _rt-port NIO-INIT
    ['] _rt-send _rt-port NIO.SEND-XT !
    ['] _rt-poll _rt-port NIO.POLL-XT !
    ['] _rt-close _rt-port NIO.CLOSE-XT ! ;

: _rt-request-reset  ( -- )
    _rt-buffer 1024 _rt-request HREQ-INIT HREQ-S-OK = _rt-assert ;

: _rt-build  ( -- )
    S" POST" S" /v1/responses" _rt-request HREQ-BEGIN
    HREQ-S-OK = _rt-assert
    S" api.openai.com" _rt-request HREQ-HOST HREQ-S-OK = _rt-assert
    S" test-secret" _rt-request HREQ-AUTH-BEARER HREQ-S-OK = _rt-assert
    S" application/json" _rt-request HREQ-CONTENT-TYPE
    HREQ-S-OK = _rt-assert
    S" text/event-stream" _rt-request HREQ-ACCEPT HREQ-S-OK = _rt-assert
    _rt-request HREQ-CONNECTION-CLOSE HREQ-S-OK = _rt-assert
    S" {}" _rt-request HREQ-BODY HREQ-S-OK = _rt-assert ;

: _rt-all-zero?  ( addr len -- flag )
    -1 -ROT 0 ?DO DUP I + C@ IF SWAP DROP 0 SWAP THEN LOOP DROP ;

: _rt-run  ( -- )
    0 _rt-fails ! 0 _rt-checks ! DEPTH _rt-depth !
    _rt-build-expected _rt-request-reset _rt-build
    _rt-request HREQ.STATE @ HREQ-STATE-SEALED = _rt-assert
    _rt-request HREQ.BUFFER @ _rt-request HREQ.LENGTH @
    _rt-expected _rt-expected-u @ STR-STR= _rt-assert

    0 _rt-port-reset
    200 0 DO
        _rt-port _rt-request HREQ-SEND-STEP _rt-result !
        _rt-result @ HREQ-PUMP-ERROR <> _rt-assert
        _rt-result @ HREQ-PUMP-CANCELLED <> _rt-assert
        _rt-result @ HREQ-PUMP-DONE = IF LEAVE THEN
    LOOP
    _rt-request HREQ.STATE @ HREQ-STATE-SENT = _rt-assert
    _rt-sink _rt-sink-u @ _rt-expected _rt-expected-u @ STR-STR= _rt-assert
    _rt-polls @ 1 > _rt-assert
    _rt-port _rt-request HREQ-SEND-STEP HREQ-PUMP-DONE = _rt-assert

    _rt-request HREQ-CLEAR
    _rt-request HREQ.STATE @ HREQ-STATE-EMPTY = _rt-assert
    _rt-buffer 1024 _rt-all-zero? _rt-assert
    _rt-request HREQ.BUFFER @ _rt-buffer = _rt-assert
    _rt-request HREQ.CAPACITY @ 1024 = _rt-assert

    _rt-request-reset
    S" GET" S" /bad path" _rt-request HREQ-BEGIN
    HREQ-S-INVALID = _rt-assert
    _rt-request HREQ.STATE @ HREQ-STATE-ERROR = _rt-assert

    _rt-request-reset
    S" GET" S" /" _rt-request HREQ-BEGIN HREQ-S-OK = _rt-assert
    13 _rt-expected C! 10 _rt-expected 1+ C!
    S" X-Test" _rt-expected 2 _rt-request HREQ-HEADER
    HREQ-S-INVALID = _rt-assert

    _rt-small 66 _rt-request HREQ-INIT HREQ-S-OK = _rt-assert
    91 _rt-small 64 + C! 92 _rt-small 65 + C!
    S" POST" S" /" _rt-request HREQ-BEGIN HREQ-S-OK = _rt-assert
    S" this-value-is-deliberately-too-large-for-the-small-request-buffer"
    _rt-request HREQ-AUTH-BEARER HREQ-S-CAPACITY = _rt-assert
    _rt-small 64 + C@ 91 = _rt-assert _rt-small 65 + C@ 92 = _rt-assert

    _rt-request-reset _rt-build 1 _rt-port-reset
    _rt-port _rt-request HREQ-SEND-STEP HREQ-PUMP-IDLE = _rt-assert
    _rt-request HREQ-CLEAR _rt-request-reset _rt-build 2 _rt-port-reset
    _rt-port _rt-request HREQ-SEND-STEP HREQ-PUMP-ERROR = _rt-assert
    _rt-request HREQ.STATUS @ HREQ-S-TRANSPORT = _rt-assert
    _rt-request HREQ-CLEAR _rt-request-reset _rt-build 3 _rt-port-reset
    _rt-port _rt-request HREQ-SEND-STEP HREQ-PUMP-CANCELLED = _rt-assert
    _rt-request HREQ-CLEAR _rt-request-reset _rt-build 4 _rt-port-reset
    _rt-port _rt-request HREQ-SEND-STEP HREQ-PUMP-ERROR = _rt-assert
    _rt-request HREQ-CLEAR _rt-request-reset _rt-build 5 _rt-port-reset
    _rt-port _rt-request HREQ-SEND-STEP HREQ-PUMP-ERROR = _rt-assert

    _rt-stack
    _rt-fails @ 0= IF
        ." HTTP REQUEST PASS " _rt-checks @ .
    ELSE
        ." HTTP REQUEST FAIL " _rt-fails @ . ." / " _rt-checks @ .
    THEN CR ;

_rt-run
""",
        ready_markers=("HTTP REQUEST PASS",),
        stable_markers=("HTTP REQUEST PASS",),
    ),
    "tls-port": Profile(
        roots=("net/transports/kdos-tls.f", "utils/string.f"),
        resources=(),
        autoexec=r"""\ autoexec.f - KDOS TLS NIO adapter tests
ENTER-USERLAND
." [akashic] loading KDOS TLS transport" CR
REQUIRE net/transports/kdos-tls.f
REQUIRE utils/string.f

VARIABLE _mt-fails
VARIABLE _mt-checks
VARIABLE _mt-depth
: _mt-assert  ( flag -- )
    1 _mt-checks +!
    0= IF 1 _mt-fails +! ." ASSERT " _mt-checks @ . CR THEN ;
: _mt-stack  ( -- )
    DEPTH DUP _mt-depth @ <> IF
        ." STACK " _mt-depth @ . ." -> " DUP . CR .S CR
    THEN
    _mt-depth @ = _mt-assert ;

CREATE _mt-a KDOSTLS-SIZE ALLOT
CREATE _mt-b KDOSTLS-SIZE ALLOT
CREATE _mt-recv 32 ALLOT
CREATE _mt-sent 256 ALLOT
CREATE _mt-native-ctx /TLS-CTX ALLOT
CREATE _mt-native-tcb /TCB ALLOT
VARIABLE _mt-sent-u
VARIABLE _mt-in-pos
VARIABLE _mt-dns-hits
VARIABLE _mt-connect-hits
VARIABLE _mt-close-hits
VARIABLE _mt-poll-hits
VARIABLE _mt-link
VARIABLE _mt-old-trust
VARIABLE _mt-op-a
VARIABLE _mt-op-b
VARIABLE _mt-op-u
VARIABLE _mt-op-n

: _mt-dns  ( host-a host-u adapter -- ip )
    DROP 1 _mt-dns-hits +!
    S" api.openai.com" STR-STR= _mt-assert
    0x01020304 ;

: _mt-dns-zero  ( host-a host-u adapter -- ip )
    DROP 2DROP 0 ;

: _mt-dns-throw  ( host-a host-u adapter -- ip )
    DROP 2DROP -777 THROW ;

: _mt-connect  ( ip remote-port local-port adapter -- ctx )
    _mt-op-a ! _mt-op-n ! _mt-op-u ! _mt-op-b !
    1 _mt-connect-hits +!
    _mt-op-b @ 0x01020304 = _mt-assert
    _mt-op-u @ 443 = _mt-assert
    _mt-op-n @ 49152 >= _mt-assert
    _mt-op-n @ 65535 <= _mt-assert
    _mt-op-a @ ;

: _mt-connect-zero  ( ip remote-port local-port adapter -- 0 )
    2DROP 2DROP
    TLS-CONNECT-E-TCP-OPEN TLS-CONNECT-LAST-ERROR !
    0 ;

: _mt-status  ( ctx adapter -- link-status )
    2DROP _mt-link @ ;

: _mt-send  ( ctx buffer length adapter -- count )
    DROP _mt-op-u ! _mt-op-b ! DROP
    _mt-op-u @ 17 MIN _mt-op-n !
    _mt-sent-u @ _mt-op-n @ + 256 > IF 0 EXIT THEN
    _mt-op-b @ _mt-sent _mt-sent-u @ + _mt-op-n @ CMOVE
    _mt-op-n @ _mt-sent-u +!
    _mt-op-n @ ;

: _mt-send-bad  ( ctx buffer length adapter -- count )
    DROP >R 2DROP R> 1+ ;

: _mt-send-zero  ( ctx buffer length adapter -- count )
    2DROP 2DROP 0 ;

: _mt-recv-op  ( ctx buffer capacity adapter -- count )
    DROP _mt-op-u ! _mt-op-b ! DROP
    5 _mt-in-pos @ - DUP 0> 0= IF DROP 0 EXIT THEN
    _mt-op-u @ MIN 3 MIN _mt-op-n !
    S" hello" DROP _mt-in-pos @ + _mt-op-b @ _mt-op-n @ CMOVE
    _mt-op-n @ _mt-in-pos +!
    _mt-op-n @ ;

: _mt-recv-bad  ( ctx buffer capacity adapter -- count )
    2DROP 2DROP -1 ;

: _mt-close  ( ctx adapter -- )
    2DROP 1 _mt-close-hits +! ;

: _mt-close-throw  ( ctx adapter -- )
    2DROP -778 THROW ;

: _mt-poll  ( adapter -- )
    DROP 1 _mt-poll-hits +! ;

VARIABLE _mt-bind-a

: _mt-bind  ( adapter -- )
    _mt-bind-a !
    _mt-bind-a @ KDOSTLS-INIT
    S" api.openai.com" 443 _mt-bind-a @ KDOSTLS-CONFIGURE
    KDOSTLS-E-OK = _mt-assert
    ['] _mt-dns _mt-bind-a @ KDOSTLS.DNS-XT !
    ['] _mt-connect _mt-bind-a @ KDOSTLS.CONNECT-XT !
    ['] _mt-send _mt-bind-a @ KDOSTLS.SEND-XT !
    ['] _mt-recv-op _mt-bind-a @ KDOSTLS.RECV-XT !
    ['] _mt-close _mt-bind-a @ KDOSTLS.CLOSE-XT !
    ['] _mt-poll _mt-bind-a @ KDOSTLS.POLL-XT !
    ['] _mt-status _mt-bind-a @ KDOSTLS.STATUS-XT ! ;

: _mt-test-config  ( -- )
    _mt-b KDOSTLS-INIT
    S" bad host" 443 _mt-b KDOSTLS-CONFIGURE KDOSTLS-E-INVALID = _mt-assert
    S" api.openai.com" 0 _mt-b KDOSTLS-CONFIGURE
    KDOSTLS-E-INVALID = _mt-assert
    S" api.openai.com" 443 KDOSTLS-NEW
    DUP KDOSTLS-E-OK = _mt-assert DROP
    DUP KDOSTLS-HOST S" api.openai.com" STR-STR= _mt-assert
    DUP KDOSTLS.REMOTE-PORT @ 443 = _mt-assert
    KDOSTLS-FREE ;

: _mt-test-open-and-io  ( -- )
    _mt-a _mt-bind _mt-b _mt-bind
    1 TLS-TRUST-COUNT ! KDOSTLS-LINK-OPEN _mt-link !
    _mt-a KDOSTLS.PORT NIO-OPEN NIO-S-OK = _mt-assert
    _mt-a KDOSTLS.STATE @ KDOSTLS-STATE-OPEN = _mt-assert
    _mt-a KDOSTLS.LAST-ERROR @ KDOSTLS-E-OK = _mt-assert
    TLS-SNI-HOST TLS-SNI-LEN @ S" api.openai.com" STR-STR= _mt-assert
    _mt-dns-hits @ 1 = _mt-assert
    _mt-connect-hits @ 1 = _mt-assert

    _mt-b KDOSTLS.PORT NIO-OPEN NIO-S-FAILED = _mt-assert
    _mt-b KDOSTLS.LAST-ERROR @ KDOSTLS-E-BUSY = _mt-assert

    S" 0123456789abcdefghijkl" _mt-a KDOSTLS.PORT NIO-SEND
    NIO-S-OK = _mt-assert 17 = _mt-assert
    _mt-sent _mt-sent-u @ S" 0123456789abcdefg" STR-STR= _mt-assert

    _mt-recv 32 _mt-a KDOSTLS.PORT NIO-RECV
    NIO-S-OK = _mt-assert 3 = _mt-assert
    _mt-recv 32 _mt-a KDOSTLS.PORT NIO-RECV
    NIO-S-OK = _mt-assert 2 = _mt-assert
    _mt-recv 32 _mt-a KDOSTLS.PORT NIO-RECV
    NIO-S-OK = _mt-assert 0= _mt-assert
    KDOSTLS-LINK-CLOSED _mt-link !
    _mt-recv 32 _mt-a KDOSTLS.PORT NIO-RECV
    NIO-S-EOF = _mt-assert 0= _mt-assert
    _mt-a KDOSTLS.PORT NIO-CLOSE
    _mt-close-hits @ 1 = _mt-assert

    KDOSTLS-LINK-OPEN _mt-link !
    _mt-b KDOSTLS.PORT NIO-OPEN NIO-S-OK = _mt-assert
    _mt-b KDOSTLS.PORT NIO-POLL
    _mt-poll-hits @ 1 = _mt-assert
    ['] _mt-close-throw _mt-b KDOSTLS.CLOSE-XT !
    _mt-b KDOSTLS.PORT NIO-CLOSE
    _mt-b KDOSTLS.STATE @ KDOSTLS-STATE-CLOSED = _mt-assert
    _mt-a KDOSTLS.PORT NIO-OPEN NIO-S-OK = _mt-assert
    _mt-a KDOSTLS.PORT NIO-CLOSE ;

: _mt-test-errors  ( -- )
    _mt-a _mt-bind
    0 TLS-TRUST-COUNT !
    _mt-a KDOSTLS.PORT NIO-OPEN NIO-S-FAILED = _mt-assert
    _mt-a KDOSTLS.LAST-ERROR @ KDOSTLS-E-NO-TRUST = _mt-assert
    1 TLS-TRUST-COUNT !
    ['] _mt-dns-zero _mt-a KDOSTLS.DNS-XT !
    _mt-a KDOSTLS.PORT NIO-OPEN NIO-S-FAILED = _mt-assert
    _mt-a KDOSTLS.LAST-ERROR @ KDOSTLS-E-DNS = _mt-assert
    ['] _mt-dns-throw _mt-a KDOSTLS.DNS-XT !
    _mt-a KDOSTLS.PORT NIO-OPEN NIO-S-FAILED = _mt-assert
    _mt-a KDOSTLS.LAST-ERROR @ KDOSTLS-E-FAULT = _mt-assert

    _mt-a _mt-bind 1 TLS-TRUST-COUNT !
    ['] _mt-connect-zero _mt-a KDOSTLS.CONNECT-XT !
    _mt-a KDOSTLS.PORT NIO-OPEN NIO-S-FAILED = _mt-assert
    _mt-a KDOSTLS.LAST-ERROR @ KDOSTLS-E-CONNECT = _mt-assert
    _mt-a KDOSTLS.NATIVE-ERROR @ TLS-CONNECT-E-TCP-OPEN = _mt-assert

    _mt-a _mt-bind 1 TLS-TRUST-COUNT !
    ['] _mt-dns _mt-a KDOSTLS.DNS-XT !
    KDOSTLS-LINK-OPEN _mt-link !
    _mt-a KDOSTLS.PORT NIO-OPEN NIO-S-OK = _mt-assert
    ['] _mt-send-bad _mt-a KDOSTLS.SEND-XT !
    S" bad" _mt-a KDOSTLS.PORT NIO-SEND
    NIO-S-FAILED = _mt-assert 0= _mt-assert
    _mt-a KDOSTLS.PORT NIO-CLOSE

    _mt-a _mt-bind 1 TLS-TRUST-COUNT ! KDOSTLS-LINK-OPEN _mt-link !
    _mt-a KDOSTLS.PORT NIO-OPEN NIO-S-OK = _mt-assert
    ['] _mt-recv-bad _mt-a KDOSTLS.RECV-XT !
    _mt-recv 32 _mt-a KDOSTLS.PORT NIO-RECV
    NIO-S-FAILED = _mt-assert 0= _mt-assert
    _mt-a KDOSTLS.PORT NIO-CLOSE ;

: _mt-test-native-link-close  ( -- )
    _mt-native-ctx /TLS-CTX 0 FILL
    _mt-native-tcb /TCB 0 FILL
    TLSS-ESTABLISHED _mt-native-ctx TLS-CTX.STATE !
    1 _mt-native-ctx TLS-CTX.PEER-AUTH !
    _mt-native-tcb _mt-native-ctx TLS-CTX.TCB !
    TCPS-ESTABLISHED _mt-native-tcb TCB.STATE !
    _mt-native-ctx 0 _KDOSTLS-STATUS-DEFAULT
    KDOSTLS-LINK-OPEN = _mt-assert
    TCPS-CLOSED _mt-native-tcb TCB.STATE !
    _mt-native-ctx 0 _KDOSTLS-STATUS-DEFAULT
    KDOSTLS-LINK-CLOSED = _mt-assert

    _mt-a KDOSTLS-INIT
    KDOSTLS-STATE-OPEN _mt-a KDOSTLS.STATE !
    _mt-native-ctx _mt-a KDOSTLS.CONTEXT !
    ['] _mt-send-zero _mt-a KDOSTLS.SEND-XT !
    S" stalled" _mt-a KDOSTLS.PORT NIO-SEND
    NIO-S-FAILED = _mt-assert 0= _mt-assert
    _mt-a KDOSTLS.LAST-ERROR @ KDOSTLS-E-IO = _mt-assert
    0 _mt-a KDOSTLS.CONTEXT !
    _mt-a KDOSTLS.PORT NIO-CLOSE ;

: _mt-run  ( -- )
    0 _mt-fails ! 0 _mt-checks ! DEPTH _mt-depth !
    TLS-TRUST-COUNT @ _mt-old-trust !
    0 _mt-sent-u ! 0 _mt-in-pos ! 0 _mt-dns-hits !
    0 _mt-connect-hits ! 0 _mt-close-hits ! 0 _mt-poll-hits !
    _mt-test-config
    _mt-test-open-and-io
    _mt-test-errors
    _mt-test-native-link-close
    _mt-a KDOSTLS.PORT NIO-CLOSE
    _mt-b KDOSTLS.PORT NIO-CLOSE
    _mt-old-trust @ TLS-TRUST-COUNT !
    _mt-stack
    _mt-fails @ 0= IF
        ." TLS PORT PASS " _mt-checks @ .
    ELSE
        ." TLS PORT FAIL " _mt-fails @ . ." / " _mt-checks @ .
    THEN CR ;

_mt-run
""",
        ready_markers=("TLS PORT PASS",),
        stable_markers=("TLS PORT PASS",),
    ),
    "openai-codec": Profile(
        roots=(
            "agent/auth/api-key.f",
            "agent/providers/openai/request-codec.f",
            "agent/providers/openai/event-codec.f",
            "agent/providers/openai/responses.f",
            "agent/runtime.f",
        ),
        resources=(),
        autoexec=r"""\ autoexec.f - native OpenAI Responses codec tests
ENTER-USERLAND
." [akashic] loading OpenAI Responses codecs" CR
REQUIRE agent/providers/openai/config.f
REQUIRE agent/auth/api-key.f
REQUIRE agent/tool-gateway.f
REQUIRE interop/codecs/json-schema.f
REQUIRE agent/providers/openai/request-codec.f
REQUIRE agent/providers/openai/event-codec.f
REQUIRE agent/providers/openai/responses.f
REQUIRE agent/runtime.f

VARIABLE _oc-fails
VARIABLE _oc-checks
VARIABLE _oc-depth
: _oc-assert  ( flag -- )
    1 _oc-checks +!
    0= IF 1 _oc-fails +! ." ASSERT " _oc-checks @ . CR THEN ;
: _oc-stack  ( -- )
    DEPTH DUP _oc-depth @ <> IF
        ." STACK " _oc-depth @ . ." -> " DUP . CR .S CR
    THEN
    _oc-depth @ = _oc-assert ;

CREATE _oc-config OPENAI-CONFIG-SIZE ALLOT
CREATE _oc-credential CREDENTIAL-SIZE ALLOT
CREATE _oc-auth APIKEY-AUTH-SIZE ALLOT
CREATE _oc-event OPENAI-EVENT-SIZE ALLOT
CREATE _oc-port NET-IO-PORT-SIZE ALLOT
CREATE _oc-out 65536 ALLOT
VARIABLE _oc-out-u
CREATE _oc-input 32768 ALLOT
VARIABLE _oc-input-u
CREATE _oc-json 32768 ALLOT
VARIABLE _oc-json-u
CREATE _oc-name OAI-TOOL-NAME-CAPACITY ALLOT
VARIABLE _oc-name-u

CREATE _oc-component COMP-DESC ALLOT
CREATE _oc-capability CAP-DESC ALLOT
CREATE _oc-schema CS-SIZE ALLOT
CREATE _oc-policy CPOLICY-SIZE ALLOT
VARIABLE _oc-registry
VARIABLE _oc-instance
VARIABLE _oc-bus
VARIABLE _oc-gateway
VARIABLE _oc-provider
VARIABLE _oc-runtime
VARIABLE _oc-context
CREATE _oc-turn AGENT-TURN-REQUEST-SIZE ALLOT

: _oc-handler  ( request instance -- status )
    2DROP CBUS-S-OK ;

: _oc-setup-tools  ( -- )
    _oc-schema CS-INIT CV-T-RESOURCE _oc-schema CS-ALLOW!
    256 _oc-schema CS-MAX-LEN!
    _oc-component COMP-DESC-INIT
    S" org.akashic.test.openai"
    _oc-component COMP.ID-U ! _oc-component COMP.ID-A !
    S" 1.0.0" _oc-component COMP.VERSION-U ! _oc-component COMP.VERSION-A !
    8 _oc-component COMP.STATE-SIZE !
    _oc-capability CAP-DESC-INIT
    CAP-K-COMMAND _oc-capability CAP.KIND !
    S" daybook.task.capture"
    _oc-capability CAP.ID-U ! _oc-capability CAP.ID-A !
    S" Capture task" _oc-capability CAP.TITLE-U ! _oc-capability CAP.TITLE-A !
    S" Capture a task in Daybook"
    _oc-capability CAP.DESC-U ! _oc-capability CAP.DESC-A !
    _oc-schema _oc-capability CAP.IN-SCHEMA !
    CAP-E-MUTATE CAP-E-PERSIST OR _oc-capability CAP.EFFECTS !
    ['] _oc-handler _oc-capability CAP.HANDLER-XT !
    _oc-capability _oc-component COMP.CAPS-A !
    1 _oc-component COMP.CAPS-N !
    _oc-policy CPOLICY-INIT
    CREG-NEW DROP _oc-registry !
    _oc-component _oc-registry @ CREG-TYPE+ DROP
    _oc-component CINST-NEW DROP _oc-instance !
    _oc-instance @ _oc-registry @ CREG-INST+ DROP
    _oc-registry @ _oc-policy CBUS-NEW DROP _oc-bus !
    _oc-registry @ _oc-bus @ _oc-instance @ ATOOLG-NEW
    DROP _oc-gateway ! ;

: _oc-json-begin  ( -- )
    JSON-BUILD-RESET _oc-json 32768 JSON-SET-OUTPUT ;
: _oc-json-end  ( -- ) JSON-OUTPUT-RESULT NIP _oc-json-u ! ;

: _oc-setup-turn  ( -- )
    ACTX-NEW DUP ACTX-S-OK = _oc-assert DROP _oc-context !
    AROLE-USER 1 S" Earlier question" _oc-context @ ACTX-APPEND-MESSAGE
    DUP ACTX-S-OK = _oc-assert DROP DROP
    AROLE-ASSISTANT 1 S" Earlier answer" _oc-context @ ACTX-APPEND-MESSAGE
    DUP ACTX-S-OK = _oc-assert DROP DROP
    _oc-json-begin JSON-{
        S" type" S" reasoning" JSON-KV-ESTR
        S" encrypted_content" S" abc" JSON-KV-ESTR
    JSON-} _oc-json-end
    1 S" org.akashic.agent.openai.responses" S" reasoning"
    _oc-json _oc-json-u @ _oc-context @ ACTX-APPEND-PROVIDER
    DUP ACTX-S-OK = _oc-assert DROP DROP
    1 S" org.akashic.agent.openai.responses" S" daybook.task.capture"
    S" call-old" S" {}" _oc-context @ ACTX-APPEND-TOOL-CALL
    DUP ACTX-S-OK = _oc-assert DROP DROP
    1 S" org.akashic.agent.openai.responses" S" daybook.task.capture"
    S" call-old" S" true" 0 _oc-context @ ACTX-APPEND-TOOL-RESULT
    DUP ACTX-S-OK = _oc-assert DROP DROP
    _oc-turn ATURN-INIT
    1 _oc-turn ATURN.THREAD-ID ! 2 _oc-turn ATURN.RUN-ID !
    S" Add milk to tomorrow's list"
    _oc-turn ATURN.PROMPT-U ! _oc-turn ATURN.PROMPT-A !
    _oc-context @ _oc-turn ATURN.CONTEXT !
    _oc-context @ ACTX.COUNT @ _oc-turn ATURN.CONTEXT-N !
    _oc-context @ ACTX.REVISION @ _oc-turn ATURN.CONTEXT-REVISION !
    _oc-gateway @ _oc-turn ATURN.TOOL-GATEWAY ! ;

: _oc-start-request  ( -- status )
    _oc-turn S" org.akashic.agent.openai.responses" _oc-config _oc-gateway @
    _oc-out 65536 OAI-RESPONSES-START-JSON
    SWAP _oc-out-u ! ;

: _oc-test-config-and-request  ( -- )
    _oc-config OAIC-INIT
    _oc-credential CRED-INIT
    S" test-api-key" _oc-credential CRED-SET DROP
    _oc-credential _oc-auth APIKEY-AUTH-INIT AAUTH-S-OK = _oc-assert
    _oc-config OAIC-HOST S" api.openai.com" STR-STR= _oc-assert
    _oc-config OAIC-PATH S" /v1/responses" STR-STR= _oc-assert
    _oc-config OAIC-MODEL S" gpt-5.5" STR-STR= _oc-assert
    _oc-config OAIC.MAX-OUTPUT @ 262144 = _oc-assert
    S" You assist the active Akashic applet."
    _oc-config OAIC-INSTRUCTIONS! OAIC-S-OK = _oc-assert
    S" bad host" _oc-config OAIC-HOST! OAIC-S-INVALID = _oc-assert
    _oc-setup-tools
    _oc-setup-turn
    _oc-gateway @ ATOOLG-TOOL-N 1 = _oc-assert
    0 _oc-gateway @ ATOOLG-TOOL-NTH _oc-capability = _oc-assert
    _oc-gateway @ OAI-GATEWAY-TOOLS-VALID? _oc-assert
    _oc-port NIO-INIT
    _oc-config _oc-auth APIKEY-AUTH.PORT _oc-port OPENAI-PROVIDER-NEW
    DUP OAIR-S-OK = _oc-assert DROP DUP _oc-provider !
    _oc-gateway @ OVER APROV-BIND-TOOLS OAIR-S-OK = _oc-assert
    DUP ARUNTIME-NEW
    DUP 0= _oc-assert DROP DUP _oc-runtime !
    _oc-gateway @ OVER ARUNTIME-TOOL-GATEWAY!
    ARUNTIME-FREE
    APROV-FREE 0 _oc-provider ! 0 _oc-runtime !
    _oc-capability _oc-name OAI-TOOL-NAME-CAPACITY OAI-TOOL-NAME
    DUP OAIREQ-S-OK = _oc-assert DROP
    DUP _oc-name-u !
    DUP 64 <= _oc-assert
    _oc-name SWAP 46 STR-INDEX 0< _oc-assert

    _oc-start-request OAIREQ-S-OK = _oc-assert
    _oc-out _oc-out-u @ JSON-VALID? _oc-assert
    _oc-out _oc-out-u @ JSON-ENTER S" model" JSON-KEY JSON-GET-STRING
    S" gpt-5.5" STR-STR= _oc-assert
    _oc-out _oc-out-u @ JSON-ENTER S" stream" JSON-KEY
    JSON-GET-BOOL _oc-assert
    _oc-out _oc-out-u @ JSON-ENTER S" store" JSON-KEY
    JSON-GET-BOOL 0= _oc-assert
    _oc-out _oc-out-u @ JSON-ENTER S" include" JSON-KEY
    JSON-ENTER JSON-COUNT 1 = _oc-assert
    _oc-out _oc-out-u @ JSON-ENTER S" parallel_tool_calls" JSON-KEY
    JSON-GET-BOOL 0= _oc-assert
    _oc-out _oc-out-u @ JSON-ENTER S" tools" JSON-KEY
    JSON-ENTER JSON-COUNT 1 = _oc-assert
    _oc-out _oc-out-u @ JSON-ENTER S" tools" JSON-KEY JSON-ENTER
    0 JSON-NTH JSON-ENTER
    S" type" JSON-KEY JSON-GET-STRING S" function" STR-STR= _oc-assert
    _oc-out _oc-out-u @ JSON-ENTER S" tools" JSON-KEY JSON-ENTER
    0 JSON-NTH JSON-ENTER S" strict" JSON-KEY JSON-GET-BOOL _oc-assert
    _oc-out _oc-out-u @ JSON-ENTER S" tools" JSON-KEY JSON-ENTER
    0 JSON-NTH JSON-ENTER S" parameters" JSON-KEY JSON-OBJECT? _oc-assert
    _oc-out _oc-out-u @ S" format" STR-STR-CONTAINS 0= _oc-assert
    _oc-out _oc-out-u @ JSON-ENTER S" input" JSON-KEY JSON-ENTER
    JSON-COUNT 6 = _oc-assert
    _oc-out _oc-out-u @ JSON-ENTER S" input" JSON-KEY JSON-ENTER
    0 JSON-NTH JSON-ENTER S" content" JSON-KEY JSON-GET-STRING
    S" Earlier question" STR-STR= _oc-assert
    _oc-out _oc-out-u @ JSON-ENTER S" input" JSON-KEY JSON-ENTER
    2 JSON-NTH JSON-ENTER S" type" JSON-KEY JSON-GET-STRING
    S" reasoning" STR-STR= _oc-assert
    _oc-out _oc-out-u @ JSON-ENTER S" input" JSON-KEY JSON-ENTER
    3 JSON-NTH JSON-ENTER S" call_id" JSON-KEY JSON-GET-STRING
    S" call-old" STR-STR= _oc-assert
    _oc-out _oc-out-u @ JSON-ENTER S" input" JSON-KEY JSON-ENTER
    3 JSON-NTH JSON-ENTER S" name" JSON-KEY JSON-GET-STRING
    _oc-name _oc-name-u @ STR-STR= _oc-assert
    _oc-out _oc-out-u @ JSON-ENTER S" input" JSON-KEY JSON-ENTER
    3 JSON-NTH JSON-ENTER S" name" JSON-KEY JSON-GET-STRING
    46 STR-INDEX 0< _oc-assert

    _oc-json-begin JSON-[
        JSON-{ S" type" S" reasoning" JSON-KV-ESTR
        S" encrypted_content" S" abc" JSON-KV-ESTR JSON-}
        JSON-{ S" type" S" function_call" JSON-KV-ESTR
        S" call_id" S" call_1" JSON-KV-ESTR
        S" name" S" test" JSON-KV-ESTR
        S" arguments" S" {}" JSON-KV-ESTR JSON-}
    JSON-] _oc-json-end
    _oc-turn S" org.akashic.agent.openai.responses"
    _oc-input 32768 OAI-TURN-INPUT-JSON
    DUP OAIREQ-S-OK = _oc-assert DROP _oc-input-u !
    _oc-input _oc-input-u @ _oc-json _oc-json-u @
    S" call_1" S" ok" _oc-config _oc-gateway @
    _oc-out 65536 OAI-RESPONSES-CONTINUE-JSON
    DUP OAIREQ-S-OK = _oc-assert DROP _oc-out-u !
    _oc-out _oc-out-u @ JSON-VALID? _oc-assert
    _oc-out _oc-out-u @ JSON-ENTER S" input" JSON-KEY JSON-ENTER
    JSON-COUNT 9 = _oc-assert
    _oc-out _oc-out-u @ JSON-ENTER S" input" JSON-KEY JSON-ENTER
    8 JSON-NTH JSON-ENTER S" type" JSON-KEY JSON-GET-STRING
    S" function_call_output" STR-STR= _oc-assert
    _oc-out _oc-out-u @ JSON-ENTER S" input" JSON-KEY JSON-ENTER
    8 JSON-NTH JSON-ENTER S" call_id" JSON-KEY JSON-GET-STRING
    S" call_1" STR-STR= _oc-assert

    _oc-config OAIC.FLAGS DUP @ OAIC-F-STORE OR SWAP !
    _oc-start-request OAIREQ-S-OK = _oc-assert
    _oc-out _oc-out-u @ S" include" JSON-FIELD
    DUP 0= _oc-assert DROP 0= _oc-assert 2DROP
    _oc-turn S" org.akashic.agent.openai.responses"
    _oc-config 0 _oc-out 8 OAI-RESPONSES-START-JSON
    OAIREQ-S-CAPACITY = _oc-assert DROP ;

: _oc-event-created  ( -- )
    _oc-json-begin JSON-{
    S" type" S" response.created" JSON-KV-ESTR
    S" response" JSON-KEY: JSON-{ S" id" S" resp_1" JSON-KV-ESTR JSON-}
    JSON-} _oc-json-end ;

: _oc-event-text  ( -- )
    _oc-json-begin JSON-{
    S" type" S" response.output_text.delta" JSON-KV-ESTR
    S" response_id" S" resp_1" JSON-KV-ESTR
    S" output_index" 0 JSON-KV-NUM
    S" delta" JSON-KEY: S" Hello" JSON-ESTR
    JSON-} _oc-json-end ;

: _oc-event-item  ( done? -- )
    _oc-json-begin JSON-{
    IF S" type" S" response.output_item.done" JSON-KV-ESTR
    ELSE S" type" S" response.output_item.added" JSON-KV-ESTR THEN
    S" response_id" S" resp_1" JSON-KV-ESTR
    S" output_index" 0 JSON-KV-NUM
    S" item" JSON-KEY: JSON-{
        S" type" S" function_call" JSON-KV-ESTR
        S" id" S" fc_1" JSON-KV-ESTR
        S" call_id" S" call_1" JSON-KV-ESTR
        S" name" JSON-KEY: _oc-name _oc-name-u @ JSON-ESTR
        S" arguments" S" {}" JSON-KV-ESTR
    JSON-} JSON-} _oc-json-end ;

: _oc-event-arguments  ( done? -- )
    _oc-json-begin JSON-{
    IF S" type" S" response.function_call_arguments.done" JSON-KV-ESTR
       S" arguments" S" {}" JSON-KV-ESTR
    ELSE S" type" S" response.function_call_arguments.delta" JSON-KV-ESTR
       S" delta" S" {" JSON-KV-ESTR THEN
    S" response_id" S" resp_1" JSON-KV-ESTR
    S" output_index" 0 JSON-KV-NUM
    JSON-} _oc-json-end ;

: _oc-event-error  ( -- )
    _oc-json-begin JSON-{
    S" type" S" response.failed" JSON-KV-ESTR
    S" response" JSON-KEY: JSON-{
        S" id" S" resp_1" JSON-KV-ESTR
        S" error" JSON-KEY: JSON-{ S" message" S" denied" JSON-KV-ESTR JSON-}
    JSON-} JSON-} _oc-json-end ;

: _oc-event-metadata  ( -- )
    _oc-json-begin JSON-{
    S" type" S" response.metadata" JSON-KV-ESTR
    S" headers" JSON-KEY: JSON-{
        S" x-codex-turn-state" JSON-KEY:
        JSON-[ S" streamed-state" JSON-ESTR JSON-]
    JSON-}
    JSON-} _oc-json-end ;

: _oc-parse-event  ( -- status )
    _oc-json _oc-json-u @ _oc-event OAIEV-PARSE ;

: _oc-test-events  ( -- )
    _oc-event OAIEV-INIT
    _oc-event-created _oc-parse-event OAIEV-S-OK = _oc-assert
    _oc-event OAIEV.KIND @ OAIEV-K-RESPONSE-CREATED = _oc-assert
    _oc-event OAIEV-RESPONSE-ID S" resp_1" STR-STR= _oc-assert
    _oc-event-text _oc-parse-event OAIEV-S-OK = _oc-assert
    _oc-event OAIEV.KIND @ OAIEV-K-TEXT-DELTA = _oc-assert
    _oc-event OAIEV-DELTA S" Hello" STR-STR= _oc-assert
    0 _oc-event-item _oc-parse-event OAIEV-S-OK = _oc-assert
    _oc-event OAIEV.KIND @ OAIEV-K-OUTPUT-ADDED = _oc-assert
    _oc-event OAIEV-CALL-ID S" call_1" STR-STR= _oc-assert
    _oc-event OAIEV-NAME NIP 0> _oc-assert
    _oc-event OAIEV-ITEM JSON-OBJECT? _oc-assert
    0 _oc-event-arguments _oc-parse-event OAIEV-S-OK = _oc-assert
    _oc-event OAIEV-DELTA S" {" STR-STR= _oc-assert
    -1 _oc-event-arguments _oc-parse-event OAIEV-S-OK = _oc-assert
    _oc-event OAIEV-ARGUMENTS S" {}" STR-STR= _oc-assert
    -1 _oc-event-item _oc-parse-event OAIEV-S-OK = _oc-assert
    _oc-event OAIEV.KIND @ OAIEV-K-OUTPUT-DONE = _oc-assert
    _oc-event-error _oc-parse-event OAIEV-S-OK = _oc-assert
    _oc-event OAIEV.KIND @ OAIEV-K-RESPONSE-FAILED = _oc-assert
    _oc-event OAIEV-MESSAGE S" denied" STR-STR= _oc-assert
    _oc-event-metadata _oc-parse-event OAIEV-S-OK = _oc-assert
    _oc-event OAIEV.KIND @ OAIEV-K-RESPONSE-METADATA = _oc-assert
    _oc-event OAIEV-TURN-STATE S" streamed-state" STR-STR= _oc-assert
    S" {" _oc-event OAIEV-PARSE OAIEV-S-INVALID = _oc-assert ;

: _oc-cleanup  ( -- )
    _oc-context @ ACTX-FREE
    _oc-auth APIKEY-AUTH.PORT AAUTH-DESTROY
    _oc-gateway @ ATOOLG-FREE
    _oc-bus @ CBUS-FREE
    _oc-instance @ _oc-registry @ CREG-INST- DROP
    _oc-registry @ CREG-FREE
    _oc-instance @ CINST-FREE
    _oc-credential CRED-CLEAR ;

: _oc-run  ( -- )
    0 _oc-fails ! 0 _oc-checks ! DEPTH _oc-depth !
    _oc-test-config-and-request
    _oc-test-events
    _oc-cleanup _oc-stack
    _oc-fails @ 0= IF
        ." OPENAI CODEC PASS " _oc-checks @ .
    ELSE
        ." OPENAI CODEC FAIL " _oc-fails @ . ." / " _oc-checks @ .
    THEN CR ;

_oc-run
""",
        ready_markers=("OPENAI CODEC PASS",),
        stable_markers=("OPENAI CODEC PASS",),
    ),
    "openai-provider": Profile(
        roots=(
            "security/credential.f",
            "agent/providers/openai/responses.f",
            "agent/runtime.f",
        ),
        resources=(),
        autoexec=r"""\ autoexec.f - native OpenAI provider fixture
ENTER-USERLAND
." [akashic] loading OpenAI provider fixture" CR
REQUIRE security/credential.f
REQUIRE agent/providers/openai/responses.f
REQUIRE agent/runtime.f

VARIABLE _op-fails
VARIABLE _op-checks
VARIABLE _op-depth
: _op-assert  ( flag -- )
    1 _op-checks +!
    0= IF 1 _op-fails +! ." ASSERT " _op-checks @ . CR THEN ;
: _op-stack  ( -- )
    DEPTH DUP _op-depth @ <> IF
        ." STACK " _op-depth @ . ." -> " DUP . CR .S CR
    THEN
    _op-depth @ = _op-assert ;

CREATE _op-port NET-IO-PORT-SIZE ALLOT
CREATE _op-response 49152 ALLOT
VARIABLE _op-response-u
VARIABLE _op-response-pos
CREATE _op-body 32768 ALLOT
VARIABLE _op-body-u
CREATE _op-json 16384 ALLOT
VARIABLE _op-json-u
CREATE _op-args 1024 ALLOT
VARIABLE _op-args-u
CREATE _op-request 67584 ALLOT
VARIABLE _op-request-u
CREATE _op-retry-request 67584 ALLOT
VARIABLE _op-retry-request-u
CREATE _op-turn-state 1024 ALLOT
VARIABLE _op-opens
VARIABLE _op-closes
VARIABLE _op-polls
VARIABLE _op-response-mode
VARIABLE _op-send-fail-once
VARIABLE _op-send-failures
VARIABLE _op-send-a
VARIABLE _op-send-u
VARIABLE _op-send-n
VARIABLE _op-recv-a
VARIABLE _op-recv-u
VARIABLE _op-recv-n

CREATE _op-config OPENAI-CONFIG-SIZE ALLOT
CREATE _op-credential CREDENTIAL-SIZE ALLOT
CREATE _op-auth AGENT-PROVIDER-AUTH-SIZE ALLOT
CREATE _op-component COMP-DESC ALLOT
CREATE _op-capability CAP-DESC ALLOT
CREATE _op-schema CS-SIZE ALLOT
CREATE _op-policy CPOLICY-SIZE ALLOT
CREATE _op-tool-name OAI-TOOL-NAME-CAPACITY ALLOT
VARIABLE _op-tool-name-u
VARIABLE _op-registry
VARIABLE _op-instance
VARIABLE _op-bus
VARIABLE _op-gateway
VARIABLE _op-provider
VARIABLE _op-runtime
VARIABLE _op-handler-hits
VARIABLE _op-found-text
VARIABLE _op-refreshes
VARIABLE _op-auth-polls
VARIABLE _op-auth-cb
VARIABLE _op-auth-context

: _op-auth-with  ( callback callback-context context -- status )
    DROP _op-auth-context ! _op-auth-cb !
    _op-auth-cb @ _op-auth-context @ _op-credential CRED-WITH
    CRED-S-OK = IF AAUTH-S-OK ELSE AAUTH-S-INVALID THEN ;

: _op-auth-refresh  ( context -- status )
    DROP 1 _op-refreshes +!
    AAUTH-STATE-REFRESHING _op-auth AAUTH.STATE !
    AAUTH-S-PENDING DUP _op-auth AAUTH.LAST-STATUS !
    1 _op-auth AAUTH.REVISION +! ;

: _op-auth-poll  ( context -- status )
    DROP 1 _op-auth-polls +!
    S" fresh-test-token" _op-credential CRED-SET CRED-S-OK <> IF
        AAUTH-STATE-ERROR _op-auth AAUTH.STATE !
        AAUTH-S-CAPACITY DUP _op-auth AAUTH.LAST-STATUS !
        1 _op-auth AAUTH.REVISION +! EXIT
    THEN
    AAUTH-STATE-READY _op-auth AAUTH.STATE !
    AAUTH-S-OK DUP _op-auth AAUTH.LAST-STATUS !
    1 _op-auth AAUTH.REVISION +! ;

: _op-auth-init  ( -- )
    _op-auth AAUTH-INIT
    AAUTH-M-DEVICE _op-auth AAUTH.METHODS !
    _op-auth _op-auth AAUTH.CONTEXT !
    ['] _op-auth-with _op-auth AAUTH.WITH-ACCESS-XT !
    ['] _op-auth-refresh _op-auth AAUTH.REFRESH-XT !
    ['] _op-auth-poll _op-auth AAUTH.POLL-XT !
    AAUTH-STATE-READY _op-auth AAUTH.STATE ! ;

: _op-b,  ( addr len -- )
    _op-body-u @ OVER + 32768 > IF 2DROP EXIT THEN
    DUP >R _op-body _op-body-u @ + SWAP CMOVE R> _op-body-u +! ;
: _op-bc,  ( c -- )
    _op-body _op-body-u @ + C! 1 _op-body-u +! ;
: _op-r,  ( addr len -- )
    _op-response-u @ OVER + 49152 > IF 2DROP EXIT THEN
    DUP >R _op-response _op-response-u @ + SWAP CMOVE
    R> _op-response-u +! ;
: _op-rc,  ( c -- )
    _op-response _op-response-u @ + C! 1 _op-response-u +! ;
: _op-crlf-r,  ( -- ) 13 _op-rc, 10 _op-rc, ;

: _op-json-begin  ( -- )
    JSON-BUILD-RESET _op-json 16384 JSON-SET-OUTPUT ;
: _op-json-end  ( -- ) JSON-OUTPUT-RESULT NIP _op-json-u ! ;

: _op-sse-event,  ( -- )
    S" data: " _op-b,
    _op-json _op-json-u @ _op-b,
    10 _op-bc, 10 _op-bc, ;

: _op-args-build  ( -- )
    JSON-BUILD-RESET _op-args 1024 JSON-SET-OUTPUT
    JSON-{ S" value" S" buy milk" JSON-KV-ESTR JSON-}
    JSON-OUTPUT-RESULT NIP _op-args-u ! ;

: _op-created,  ( id-a id-u -- )
    _op-json-begin JSON-{
    S" type" S" response.created" JSON-KV-ESTR
    S" response" JSON-KEY: JSON-{ S" id" 2SWAP JSON-KV-ESTR JSON-}
    JSON-} _op-json-end _op-sse-event, ;

: _op-completed,  ( id-a id-u -- )
    _op-json-begin JSON-{
    S" type" S" response.completed" JSON-KV-ESTR
    S" response" JSON-KEY: JSON-{ S" id" 2SWAP JSON-KV-ESTR JSON-}
    JSON-} _op-json-end _op-sse-event, ;

: _op-tool-item,  ( -- )
    _op-json-begin JSON-{
    S" type" S" response.output_item.done" JSON-KV-ESTR
    S" response_id" S" resp_tool" JSON-KV-ESTR
    S" output_index" 0 JSON-KV-NUM
    S" item" JSON-KEY: JSON-{
        S" type" S" function_call" JSON-KV-ESTR
        S" id" S" fc_1" JSON-KV-ESTR
        S" call_id" S" call_1" JSON-KV-ESTR
        S" name" JSON-KEY: _op-tool-name _op-tool-name-u @ JSON-ESTR
        S" arguments" JSON-KEY: _op-args _op-args-u @ JSON-ESTR
    JSON-} JSON-} _op-json-end _op-sse-event, ;

: _op-reasoning-item,  ( -- )
    _op-json-begin JSON-{
    S" type" S" response.output_item.done" JSON-KV-ESTR
    S" response_id" S" resp_tool" JSON-KV-ESTR
    S" output_index" 0 JSON-KV-NUM
    S" item" JSON-KEY: JSON-{
        S" type" S" reasoning" JSON-KV-ESTR
        S" id" S" rs_1" JSON-KV-ESTR
        S" encrypted_content" S" encrypted-test-state" JSON-KV-ESTR
    JSON-} JSON-} _op-json-end _op-sse-event, ;

: _op-text,  ( -- )
    _op-json-begin JSON-{
    S" type" S" response.output_text.delta" JSON-KV-ESTR
    S" response_id" S" resp_final" JSON-KV-ESTR
    S" output_index" 0 JSON-KV-NUM
    S" delta" S" Task captured." JSON-KV-ESTR
    JSON-} _op-json-end _op-sse-event, ;

: _op-http-wrap  ( -- )
    0 _op-response-u !
    S" HTTP/1.1 200 OK" _op-r, _op-crlf-r,
    S" x-codex-turn-state: " _op-r,
    _op-turn-state 1024 _op-r, _op-crlf-r,
    S" Content-Length: " _op-r,
    _op-body-u @ NUM>STR _op-r, _op-crlf-r,
    S" Connection: close" _op-r, _op-crlf-r,
    _op-crlf-r,
    _op-body _op-body-u @ _op-r, ;

: _op-build-first-response  ( -- )
    0 _op-body-u ! _op-args-build
    S" resp_tool" _op-created,
    _op-reasoning-item,
    _op-tool-item,
    S" resp_tool" _op-completed,
    _op-http-wrap ;

: _op-build-final-response  ( -- )
    0 _op-body-u !
    S" resp_final" _op-created,
    _op-text,
    S" resp_final" _op-completed,
    _op-http-wrap ;

: _op-build-unauthorized  ( -- )
    0 _op-body-u ! S" expired access token" _op-b,
    0 _op-response-u !
    S" HTTP/1.1 401 Unauthorized" _op-r, _op-crlf-r,
    S" Content-Type: text/plain" _op-r, _op-crlf-r,
    S" Content-Length: " _op-r,
    _op-body-u @ NUM>STR _op-r, _op-crlf-r,
    S" Connection: close" _op-r, _op-crlf-r,
    _op-crlf-r,
    _op-body _op-body-u @ _op-r, ;

: _op-open  ( context -- status )
    DROP
    _op-response-mode @ 0= _op-opens @ 2 = AND IF
        _op-request-u @ DUP _op-retry-request-u !
        _op-request _op-retry-request ROT CMOVE
    THEN
    1 _op-opens +! 0 _op-response-pos ! 0 _op-request-u !
    _op-response-mode @ 2 = IF
        _op-build-final-response
    ELSE _op-response-mode @ IF
        _op-build-unauthorized
    ELSE
        _op-opens @ 1 = IF
            _op-build-first-response
        ELSE
            _op-opens @ 2 = IF
                _op-build-unauthorized
            ELSE
                _op-build-final-response
            THEN
        THEN
    THEN THEN
    NIO-S-OK ;

: _op-close  ( context -- ) DROP 1 _op-closes +! ;
: _op-poll  ( context -- ) DROP 1 _op-polls +! ;

: _op-send  ( buffer length context -- count status )
    DROP _op-send-u ! _op-send-a !
    _op-send-fail-once @ _op-send-failures @ 0= AND IF
        1 _op-send-failures +! 0 NIO-S-FAILED EXIT
    THEN
    _op-request-u @ _op-send-u @ + 67584 > IF 0 NIO-S-FAILED EXIT THEN
    _op-send-u @ 97 MIN _op-send-n !
    _op-send-a @ _op-request _op-request-u @ + _op-send-n @ CMOVE
    _op-send-n @ _op-request-u +!
    _op-send-n @ NIO-S-OK ;

: _op-recv  ( buffer capacity context -- count status )
    DROP _op-recv-u ! _op-recv-a !
    _op-response-pos @ _op-response-u @ >= IF 0 NIO-S-EOF EXIT THEN
    _op-response-u @ _op-response-pos @ - _op-recv-u @ MIN 53 MIN
    _op-recv-n !
    _op-response _op-response-pos @ + _op-recv-a @ _op-recv-n @ CMOVE
    _op-recv-n @ _op-response-pos +!
    _op-recv-n @ NIO-S-OK ;

: _op-handler  ( request instance -- status )
    DROP 1 _op-handler-hits +!
    DUP CBR.ARGS DUP CV-TYPE@ CV-T-STRING = _op-assert
    DUP CV-DATA@ SWAP CV-LEN@ S" buy milk" STR-STR= _op-assert
    S" captured" 2 PICK CBR.RESULT CV-STRING! IF
        DROP CBUS-S-FAILED EXIT
    THEN
    DROP CBUS-S-OK ;

: _op-setup  ( -- )
    0 _op-opens ! 0 _op-closes ! 0 _op-polls ! 0 _op-handler-hits !
    0 _op-response-mode ! 0 _op-retry-request-u !
    0 _op-send-fail-once ! 0 _op-send-failures !
    0 _op-refreshes ! 0 _op-auth-polls !
    _op-turn-state 1024 65 FILL
    _op-port NIO-INIT
    ['] _op-open _op-port NIO.OPEN-XT !
    ['] _op-close _op-port NIO.CLOSE-XT !
    ['] _op-poll _op-port NIO.POLL-XT !
    ['] _op-send _op-port NIO.SEND-XT !
    ['] _op-recv _op-port NIO.RECV-XT !
    ." [openai-provider] port" CR

    _op-config OAIC-INIT
    _op-credential CRED-INIT
    S" stale-test-token" _op-credential CRED-SET DROP
    _op-auth-init
    ." [openai-provider] config" CR

    _op-schema CS-INIT CV-T-STRING _op-schema CS-ALLOW!
    256 _op-schema CS-MAX-LEN!
    _op-component COMP-DESC-INIT
    S" org.akashic.test.openai-provider"
    _op-component COMP.ID-U ! _op-component COMP.ID-A !
    S" 1.0.0" _op-component COMP.VERSION-U ! _op-component COMP.VERSION-A !
    8 _op-component COMP.STATE-SIZE !
    _op-capability CAP-DESC-INIT
    CAP-K-COMMAND _op-capability CAP.KIND !
    S" daybook.task.capture"
    _op-capability CAP.ID-U ! _op-capability CAP.ID-A !
    S" Capture task" _op-capability CAP.TITLE-U ! _op-capability CAP.TITLE-A !
    S" Capture a task in Daybook"
    _op-capability CAP.DESC-U ! _op-capability CAP.DESC-A !
    _op-schema _op-capability CAP.IN-SCHEMA !
    CAP-E-MUTATE CAP-E-PERSIST OR _op-capability CAP.EFFECTS !
    ['] _op-handler _op-capability CAP.HANDLER-XT !
    _op-capability _op-component COMP.CAPS-A !
    1 _op-component COMP.CAPS-N !
    _op-policy CPOLICY-INIT
    ." [openai-provider] descriptors" CR
    CREG-NEW DROP _op-registry !
    _op-component _op-registry @ CREG-TYPE+ DROP
    _op-component CINST-NEW DROP _op-instance !
    _op-instance @ _op-registry @ CREG-INST+ DROP
    _op-registry @ _op-policy CBUS-NEW DROP _op-bus !
    _op-registry @ _op-bus @ _op-instance @ ATOOLG-NEW DROP _op-gateway !
    ." [openai-provider] gateway" CR
    _op-capability _op-tool-name OAI-TOOL-NAME-CAPACITY OAI-TOOL-NAME
    DROP _op-tool-name-u !

    _op-config _op-auth _op-port OPENAI-PROVIDER-NEW
    DROP _op-provider !
    ." [openai-provider] provider" CR
    ." [openai-provider] tools " _op-gateway @ ATOOLG-TOOL-N . CR
    _op-gateway @ OAI-GATEWAY-TOOLS-VALID? _op-assert
    ." [openai-provider] tools-valid" CR
    _op-gateway @ _op-provider @ APROV-BIND-TOOLS OAIR-S-OK = _op-assert
    ." [openai-provider] bound" CR
    _op-provider @ ARUNTIME-NEW DROP _op-runtime !
    ." [openai-provider] runtime-new" CR
    _op-gateway @ _op-runtime @ ARUNTIME-TOOL-GATEWAY!
    ." [openai-provider] runtime" CR ;

: _op-pump-until-review  ( -- )
    3000 0 DO
        8 _op-runtime @ ARUNTIME-PUMP DROP
        8 _op-bus @ CBUS-PUMP DROP
        _op-runtime @ ARUNTIME.STATUS @ ARUN-S-APPROVAL = IF LEAVE THEN
    LOOP ;

: _op-pump-until-idle  ( -- )
    5000 0 DO
        8 _op-runtime @ ARUNTIME-PUMP DROP
        8 _op-bus @ CBUS-PUMP DROP
        _op-runtime @ ARUNTIME.STATUS @ ARUN-S-IDLE = IF LEAVE THEN
    LOOP ;

VARIABLE _op-scan-a
VARIABLE _op-scan-u
VARIABLE _op-old-body-a
VARIABLE _op-old-body-u
VARIABLE _op-new-body-a
VARIABLE _op-new-body-u
VARIABLE _op-history-seen

: _op-request-body  ( request-a request-u -- body-a body-u )
    _op-scan-u ! _op-scan-a !
    _op-scan-u @ 4 < IF 0 0 EXIT THEN
    _op-scan-u @ 3 - 0 DO
        _op-scan-a @ I + C@ 13 =
        _op-scan-a @ I 1+ + C@ 10 = AND
        _op-scan-a @ I 2 + + C@ 13 = AND
        _op-scan-a @ I 3 + + C@ 10 = AND IF
            _op-scan-a @ I 4 + +
            _op-scan-u @ I 4 + - UNLOOP EXIT
        THEN
    LOOP
    0 0 ;

: _op-check-replayed-request  ( -- )
    _op-retry-request _op-retry-request-u @ _op-request-body
    _op-old-body-u ! _op-old-body-a !
    _op-request _op-request-u @ _op-request-body
    _op-new-body-u ! _op-new-body-a !
    _op-old-body-u @ 0> _op-assert
    _op-new-body-u @ 0> _op-assert
    _op-old-body-a @ _op-old-body-u @
    _op-new-body-a @ _op-new-body-u @ STR-STR= _op-assert
    _op-retry-request _op-retry-request-u @ S" stale-test-token"
    STR-STR-CONTAINS _op-assert
    _op-request _op-request-u @ S" fresh-test-token"
    STR-STR-CONTAINS _op-assert ;

: _op-pump-until-auth-wait  ( -- )
    5000 0 DO
        8 _op-runtime @ ARUNTIME-PUMP DROP
        8 _op-bus @ CBUS-PUMP DROP
        _op-provider @ APROV.CONTEXT @ OAIR-C.STATE @
        OAIR-STATE-WAITING-AUTH = IF LEAVE THEN
    LOOP
    _op-provider @ APROV.CONTEXT @ OAIR-C.STATE @
    OAIR-STATE-WAITING-AUTH = _op-assert
    _op-provider @ APROV.CONTEXT @ OAIR-C.SESSION @ DUP 0<> _op-assert
    DUP OAIR-S.AUTH-RETRIED @ 0<> _op-assert
    DUP OAIR-S.HISTORY-COMMITTED @ 0= _op-assert
    OAIR-S.BODY-U @ 0> _op-assert ;

: _op-pump-until-history  ( -- )
    0 _op-history-seen !
    5000 0 DO
        8 _op-runtime @ ARUNTIME-PUMP DROP
        8 _op-bus @ CBUS-PUMP DROP
        _op-provider @ APROV.CONTEXT @ OAIR-C.SESSION @ ?DUP IF
            DUP OAIR-S.HISTORY-COMMITTED @ IF
                OAIR-S.HISTORY-N @ 3 = _op-assert
                -1 _op-history-seen ! LEAVE
            THEN
            DROP
        THEN
    LOOP
    _op-history-seen @ _op-assert ;

: _op-pump-until-error  ( -- )
    5000 0 DO
        8 _op-runtime @ ARUNTIME-PUMP DROP
        8 _op-bus @ CBUS-PUMP DROP
        _op-runtime @ ARUNTIME.STATUS @ ARUN-S-ERROR = IF LEAVE THEN
    LOOP ;

: _op-test-run  ( -- )
    4 _op-runtime @ ARUNTIME-PUMP DROP
    _op-runtime @ ARUNTIME.STATUS @ ARUN-S-IDLE = _op-assert
    S" Please capture a milk task" _op-runtime @ ARUNTIME-SEND 0= _op-assert
    _op-pump-until-review
    _op-runtime @ ARUNTIME.STATUS @ ARUN-S-APPROVAL = _op-assert
    _op-provider @ APROV.CONTEXT @ OAIR-C.SESSION @ DUP
    OAIR-S.TURN-STATE-U @ 1024 = _op-assert
    OAIR-S.TURN-STATE 1024 _op-turn-state 1024 STR-STR= _op-assert
    -1 _op-runtime @ ARUNTIME-RESOLVE 0= _op-assert
    _op-pump-until-auth-wait
    _op-provider @ APROV.CONTEXT @ OAIR-C.SESSION @
    OAIR-S.HISTORY-N @ 2 = _op-assert
    _op-refreshes @ 1 = _op-assert
    _op-auth-polls @ 0= _op-assert
    _op-auth AAUTH.STATE @ AAUTH-STATE-REFRESHING = _op-assert
    _op-pump-until-history
    _op-check-replayed-request
    _op-pump-until-idle
    _op-runtime @ ARUNTIME.STATUS @ ARUN-S-IDLE = _op-assert
    _op-opens @ 3 = _op-assert
    _op-closes @ 3 >= _op-assert
    _op-handler-hits @ 1 = _op-assert
    _op-refreshes @ 1 = _op-assert
    _op-auth-polls @ 1 = _op-assert
    _op-auth AAUTH-READY? _op-assert
    _op-credential CRED.USES @ 3 = _op-assert
    _op-request _op-request-u @ S" Authorization: Bearer "
    STR-STR-CONTAINS _op-assert
    _op-runtime @ ARUNTIME.CONVERSATION @ DUP ACONV.COUNT @ 0> _op-assert
    0 _op-found-text !
    DUP ACONV.COUNT @ 0 ?DO
        I OVER ACONV-NTH AMSG-TEXT S" Task captured."
        STR-STR-CONTAINS IF -1 _op-found-text ! THEN
    LOOP
    DROP _op-found-text @ _op-assert
    _op-runtime @ ARUNTIME-MODEL-CONTEXT ACTX.COUNT @ 5 = _op-assert

    S" cancel now" _op-runtime @ ARUNTIME-SEND 0= _op-assert
    _op-provider @ APROV.CONTEXT @ OAIR-C.SESSION @ DUP 0<> _op-assert
    DUP OAIR-S.INPUT SWAP OAIR-S.INPUT-U @ JSON-ENTER
    2DUP JSON-COUNT 6 = _op-assert
    2DUP 0 JSON-NTH JSON-ENTER S" content" JSON-KEY JSON-GET-STRING
    S" Please capture a milk task" STR-STR= _op-assert
    5 JSON-NTH JSON-ENTER S" content" JSON-KEY JSON-GET-STRING
    S" cancel now" STR-STR= _op-assert
    _op-runtime @ ARUNTIME-CANCEL 0= _op-assert
    4 _op-runtime @ ARUNTIME-PUMP DROP
    _op-runtime @ ARUNTIME.STATUS @ ARUN-S-CANCELLED = _op-assert ;

: _op-test-send-retry  ( -- )
    2 _op-response-mode !
    0 _op-opens ! 0 _op-closes ! 0 _op-request-u !
    0 _op-send-failures ! -1 _op-send-fail-once !
    S" retry an incomplete send" _op-runtime @ ARUNTIME-SEND 0= _op-assert
    _op-pump-until-idle
    _op-runtime @ ARUNTIME.STATUS @ ARUN-S-IDLE = _op-assert
    _op-opens @ 2 = _op-assert
    _op-closes @ 2 >= _op-assert
    _op-send-failures @ 1 = _op-assert
    _op-provider @ APROV.CONTEXT @ OAIR-C.SESSION @ 0= _op-assert
    0 _op-send-fail-once ! ;

: _op-test-second-401  ( -- )
    1 _op-response-mode !
    0 _op-opens ! 0 _op-closes ! 0 _op-refreshes ! 0 _op-auth-polls !
    0 _op-request-u ! 0 _op-retry-request-u !
    0 _op-credential CRED.USES !
    S" stale-second-token" _op-credential CRED-SET CRED-S-OK = _op-assert
    AAUTH-STATE-READY _op-auth AAUTH.STATE !
    S" reject the retry" _op-runtime @ ARUNTIME-SEND 0= _op-assert
    _op-pump-until-auth-wait
    _op-refreshes @ 1 = _op-assert
    _op-auth-polls @ 0= _op-assert
    _op-pump-until-error
    _op-runtime @ ARUNTIME.STATUS @ ARUN-S-ERROR = _op-assert
    _op-opens @ 2 = _op-assert
    _op-closes @ 2 >= _op-assert
    _op-refreshes @ 1 = _op-assert
    _op-auth-polls @ 1 = _op-assert
    _op-credential CRED.USES @ 2 = _op-assert
    _op-provider @ APROV.CONTEXT @ OAIR-C.SESSION @ 0= _op-assert
    _op-provider @ APROV.CONTEXT @ OAIR-C.STATE @
    OAIR-STATE-IDLE = _op-assert
    0 _op-found-text !
    _op-runtime @ ARUNTIME.CONVERSATION @ DUP ACONV.COUNT @ 0 ?DO
        I OVER ACONV-NTH AMSG-TEXT
        S" Provider remained unauthorized after refresh"
        STR-STR-CONTAINS IF -1 _op-found-text ! THEN
    LOOP
    DROP _op-found-text @ _op-assert
    8 _op-runtime @ ARUNTIME-PUMP DROP
    _op-opens @ 2 = _op-assert ;

: _op-cleanup  ( -- )
    _op-runtime @ ARUNTIME-FREE
    _op-provider @ APROV-FREE
    _op-gateway @ ATOOLG-FREE
    _op-bus @ CBUS-FREE
    _op-instance @ _op-registry @ CREG-INST- DROP
    _op-registry @ CREG-FREE
    _op-instance @ CINST-FREE
    _op-auth AAUTH-DESTROY
    _op-credential CRED-CLEAR ;

: _op-run  ( -- )
    0 _op-fails ! 0 _op-checks ! DEPTH _op-depth !
    ." [openai-provider] setup" CR
    _op-setup
    ." [openai-provider] run" CR
    _op-test-run
    ." [openai-provider] send retry" CR
    _op-test-send-retry
    ." [openai-provider] unauthorized" CR
    _op-test-second-401
    ." [openai-provider] cleanup" CR
    _op-cleanup _op-stack
    _op-fails @ 0= IF
        ." OPENAI PROVIDER PASS " _op-checks @ .
    ELSE
        ." OPENAI PROVIDER FAIL " _op-fails @ . ." / " _op-checks @ .
    THEN CR ;

_op-run
""",
        ready_markers=("OPENAI PROVIDER PASS",),
        stable_markers=("OPENAI PROVIDER PASS",),
    ),
    "openai-source": Profile(
        roots=(
            "agent/providers/openai/source.f",
            "agent/runtime.f",
            "utils/string.f",
        ),
        resources=(),
        autoexec=r"""\ autoexec.f - owned OpenAI provider source
ENTER-USERLAND
." [akashic] loading OpenAI provider source" CR
REQUIRE agent/providers/openai/source.f
REQUIRE agent/runtime.f
REQUIRE utils/string.f

VARIABLE _om-fails
VARIABLE _om-checks
VARIABLE _om-depth
VARIABLE _om-source
VARIABLE _om-provider
VARIABLE _om-runtime

: _om-assert  ( flag -- )
    1 _om-checks +!
    0= IF 1 _om-fails +! ." ASSERT " _om-checks @ . CR THEN ;

: _om-stack  ( -- )
    DEPTH DUP _om-depth @ <> IF
        ." STACK " _om-depth @ . ." -> " DUP . CR .S CR
    THEN
    _om-depth @ = _om-assert ;

: _om-zero?  ( addr len -- flag )
    -1 -ROT 0 ?DO
        DUP I + C@ IF SWAP DROP 0 SWAP THEN
    LOOP
    DROP ;

: _om-run  ( -- )
    0 _om-fails ! 0 _om-checks ! DEPTH _om-depth !
    OPENAI-SOURCE-NEW
    DUP APSOURCE-S-OK = _om-assert DROP _om-source !
    _om-source @ DUP APSOURCE.ID-A @ SWAP APSOURCE.ID-U @
    S" org.akashic.agent.source.openai" STR-STR= _om-assert
    _om-source @ OPENAI-SOURCE-CONFIG OAIC-HOST
    S" api.openai.com" STR-STR= _om-assert
    _om-source @ OPENAI-SOURCE-TRANSPORT KDOSTLS-HOST
    S" api.openai.com" STR-STR= _om-assert
    _om-source @ OPENAI-SOURCE-TRANSPORT KDOSTLS.REMOTE-PORT @
    443 = _om-assert

    _om-source @ APSOURCE-PROVIDER-NEW
    DUP OAIR-S-OK = _om-assert DROP _om-provider !
    _om-provider @ APROV.FEATURES @ APROV-F-AUTH AND 0<> _om-assert
    _om-provider @ APROV-AUTH AAUTH-READY? 0= _om-assert
    _om-provider @ APROV-AUTH AAUTH.CONTEXT @ APIKEY-AUTH.CREDENTIAL @
    _om-source @ OPENAI-SOURCE-CREDENTIAL = _om-assert
    _om-provider @ APROV.CONTEXT @ OAIR-C.PORT @
    _om-source @ OPENAI-SOURCE-TRANSPORT KDOSTLS.PORT = _om-assert

    _om-provider @ ARUNTIME-NEW
    DUP 0= _om-assert DROP _om-runtime !
    _om-runtime @ ARUNTIME.STATUS @ ARUN-S-ERROR = _om-assert
    _om-runtime @ ARUNTIME-AUTH-PRESENT? 0= _om-assert
    S" local-fixture-secret" _om-runtime @ ARUNTIME-AUTH-SET
    AAUTH-S-OK = _om-assert
    _om-runtime @ ARUNTIME-AUTH-PRESENT? _om-assert
    _om-source @ OPENAI-SOURCE-CREDENTIAL CRED.LENGTH @
    20 = _om-assert
    8 _om-runtime @ ARUNTIME-PUMP DROP
    _om-runtime @ ARUNTIME.STATUS @ ARUN-S-IDLE = _om-assert

    _om-runtime @ ARUNTIME-AUTH-CLEAR AAUTH-S-OK = _om-assert
    _om-runtime @ ARUNTIME.STATUS @ ARUN-S-OFFLINE = _om-assert
    _om-runtime @ ARUNTIME-AUTH-PRESENT? 0= _om-assert
    _om-source @ OPENAI-SOURCE-CREDENTIAL _CRED-SECRET-A
    CRED-SECRET-CAPACITY _om-zero? _om-assert

    _om-runtime @ ARUNTIME-FREE
    _om-provider @ APROV-FREE
    _om-source @ APSOURCE-FREE
    _om-stack
    _om-fails @ 0= IF
        ." OPENAI SOURCE PASS " _om-checks @ .
    ELSE
        ." OPENAI SOURCE FAIL " _om-fails @ . ." / " _om-checks @ .
    THEN CR ;

_om-run
""",
        ready_markers=("OPENAI SOURCE PASS",),
        stable_markers=("OPENAI SOURCE PASS",),
    ),
    "codex-auth": Profile(
        roots=("agent/providers/codex/auth.f",),
        resources=(),
        autoexec=r"""\ autoexec.f - native Codex device authentication fixture
ENTER-USERLAND
." [akashic] loading Codex device authentication" CR
REQUIRE agent/providers/codex/auth.f

VARIABLE _ca-fails
VARIABLE _ca-checks
VARIABLE _ca-depth
: _ca-assert  ( flag -- )
    1 _ca-checks +!
    0= IF 1 _ca-fails +! ." ASSERT " _ca-checks @ . CR THEN ;
: _ca-stack  ( -- )
    DEPTH DUP _ca-depth @ <> IF
        ." STACK " _ca-depth @ . ." -> " DUP . CR .S CR
    THEN
    _ca-depth @ = _ca-assert ;

CREATE _ca-port NET-IO-PORT-SIZE ALLOT
CREATE _ca-response 49152 ALLOT
VARIABLE _ca-response-u
VARIABLE _ca-response-pos
CREATE _ca-body 32768 ALLOT
VARIABLE _ca-body-u
CREATE _ca-json 16384 ALLOT
VARIABLE _ca-json-u
CREATE _ca-request 32768 ALLOT
VARIABLE _ca-request-u
VARIABLE _ca-force-close
CREATE _ca-id-token 8192 ALLOT
VARIABLE _ca-id-token-u
CREATE _ca-access-token 8192 ALLOT
VARIABLE _ca-access-token-u
CREATE _ca-payload 4096 ALLOT
VARIABLE _ca-payload-u
CREATE _ca-b64 8192 ALLOT
VARIABLE _ca-b64-u
VARIABLE _ca-auth
VARIABLE _ca-opens
VARIABLE _ca-closes
VARIABLE _ca-requests
VARIABLE _ca-send-a
VARIABLE _ca-send-u
VARIABLE _ca-send-n
VARIABLE _ca-recv-a
VARIABLE _ca-recv-u
VARIABLE _ca-recv-n
VARIABLE _ca-jwt-d
VARIABLE _ca-jwt-cap
VARIABLE _ca-jwt-w

: _ca-b,  ( addr len -- )
    DUP >R _ca-body _ca-body-u @ + SWAP CMOVE R> _ca-body-u +! ;
: _ca-r,  ( addr len -- )
    DUP >R _ca-response _ca-response-u @ + SWAP CMOVE R> _ca-response-u +! ;
: _ca-rc,  ( c -- )
    _ca-response _ca-response-u @ + C! 1 _ca-response-u +! ;
: _ca-crlf,  ( -- ) 13 _ca-rc, 10 _ca-rc, ;
: _ca-json-begin  ( -- )
    JSON-BUILD-RESET _ca-json 16384 JSON-SET-OUTPUT ;
: _ca-json-end  ( -- ) JSON-OUTPUT-RESULT NIP _ca-json-u ! ;

: _ca-jwt  ( payload-a payload-u destination capacity -- length )
    _ca-jwt-cap ! _ca-jwt-d ! 0 _ca-jwt-w !
    S" e30." _ca-jwt-d @ SWAP CMOVE 4 _ca-jwt-w !
    _ca-jwt-d @ _ca-jwt-w @ + _ca-jwt-cap @ _ca-jwt-w @ -
    B64-ENCODE-URL DUP _ca-b64-u ! _ca-jwt-w +!
    46 _ca-jwt-d @ _ca-jwt-w @ + C! 1 _ca-jwt-w +!
    S" sig" _ca-jwt-d @ _ca-jwt-w @ + SWAP CMOVE 3 _ca-jwt-w +!
    _ca-jwt-w @ ;

: _ca-build-tokens  ( -- )
    JSON-BUILD-RESET _ca-payload 4096 JSON-SET-OUTPUT
    JSON-{ S" exp" 4102444800 JSON-KV-NUM JSON-}
    JSON-OUTPUT-RESULT NIP _ca-payload-u !
    _ca-payload _ca-payload-u @ _ca-access-token 8192 _ca-jwt
    _ca-access-token-u !
    JSON-BUILD-RESET _ca-payload 4096 JSON-SET-OUTPUT
    JSON-{
    S" email" S" user@example.com" JSON-KV-ESTR
    S" https://api.openai.com/auth" JSON-KEY: JSON-{
        S" chatgpt_plan_type" S" pro" JSON-KV-ESTR
        S" chatgpt_account_id" S" account-fixture" JSON-KV-ESTR
    JSON-}
    JSON-}
    JSON-OUTPUT-RESULT NIP _ca-payload-u !
    _ca-payload _ca-payload-u @ _ca-id-token 8192 _ca-jwt
    _ca-id-token-u ! ;

: _ca-http-wrap  ( success? -- )
    0 _ca-response-u !
    IF S" HTTP/1.1 200 OK" ELSE S" HTTP/1.1 403 Forbidden" THEN
    _ca-r, _ca-crlf,
    S" Content-Type: application/json" _ca-r, _ca-crlf,
    S" Content-Length: " _ca-r, _ca-body-u @ NUM>STR _ca-r, _ca-crlf,
    _ca-force-close @ IF S" Connection: close" ELSE
        S" Connection: keep-alive"
    THEN _ca-r, _ca-crlf, _ca-crlf,
    0 _ca-force-close !
    _ca-body _ca-body-u @ _ca-r, ;

: _ca-user-code-response  ( -- )
    _ca-json-begin JSON-{
    S" device_auth_id" S" device-fixture" JSON-KV-ESTR
    S" user_code" S" TEST-CODE" JSON-KV-ESTR
    S" interval" S" 1" JSON-KV-ESTR
    JSON-} _ca-json-end
    0 _ca-body-u ! _ca-json _ca-json-u @ _ca-b, -1 _ca-http-wrap ;

: _ca-pending-response  ( -- )
    0 _ca-body-u ! S" {}" _ca-b, -1 _ca-force-close ! 0 _ca-http-wrap ;

: _ca-code-response  ( -- )
    _ca-json-begin JSON-{
    S" authorization_code" S" authorization-fixture" JSON-KV-ESTR
    S" code_challenge" S" challenge-fixture" JSON-KV-ESTR
    S" code_verifier" S" verifier-fixture" JSON-KV-ESTR
    JSON-} _ca-json-end
    0 _ca-body-u ! _ca-json _ca-json-u @ _ca-b, -1 _ca-http-wrap ;

: _ca-token-response  ( -- )
    _ca-json-begin JSON-{
    S" id_token" JSON-KEY: _ca-id-token _ca-id-token-u @ JSON-ESTR
    S" access_token" JSON-KEY: _ca-access-token _ca-access-token-u @ JSON-ESTR
    S" refresh_token" S" refresh-fixture" JSON-KV-ESTR
    JSON-} _ca-json-end
    0 _ca-body-u ! _ca-json _ca-json-u @ _ca-b, -1 _ca-http-wrap ;

: _ca-next-response  ( -- )
    1 _ca-requests +!
    _ca-requests @ CASE
        1 OF _ca-user-code-response ENDOF
        2 OF _ca-pending-response ENDOF
        3 OF _ca-code-response ENDOF
        _ca-token-response
    ENDCASE ;
: _ca-open  ( context -- status )
    DROP 1 _ca-opens +! 0 _ca-response-u ! 0 _ca-response-pos !
    0 _ca-request-u !
    NIO-S-OK ;
: _ca-close  ( context -- ) DROP 1 _ca-closes +! ;
: _ca-poll-port  ( context -- ) DROP ;
: _ca-send  ( addr len context -- count status )
    DROP _ca-send-u ! _ca-send-a !
    _ca-response-pos @ _ca-response-u @ >= IF
        0 _ca-response-pos ! 0 _ca-request-u ! _ca-next-response
    THEN
    _ca-request-u @ _ca-send-u @ + 32768 > IF 0 NIO-S-FAILED EXIT THEN
    _ca-send-u @ 101 MIN _ca-send-n !
    _ca-send-a @ _ca-request _ca-request-u @ + _ca-send-n @ CMOVE
    _ca-send-n @ _ca-request-u +!
    _ca-send-n @ NIO-S-OK ;
: _ca-recv  ( addr cap context -- count status )
    DROP _ca-recv-u ! _ca-recv-a !
    _ca-response-pos @ _ca-response-u @ >= IF 0 NIO-S-EOF EXIT THEN
    _ca-response-u @ _ca-response-pos @ - _ca-recv-u @ MIN 47 MIN
    _ca-recv-n !
    _ca-response _ca-response-pos @ + _ca-recv-a @ _ca-recv-n @ CMOVE
    _ca-recv-n @ _ca-response-pos +!
    _ca-recv-n @ NIO-S-OK ;

: _ca-pump-to-pending  ( -- )
    400 0 DO
        _ca-auth @ CDA.AUTH AAUTH-POLL DROP
        _ca-auth @ CDA.AUTH AAUTH.STATE @ AAUTH-STATE-PENDING = IF LEAVE THEN
        _ca-auth @ CDA.AUTH AAUTH.STATE @ AAUTH-STATE-ERROR = IF LEAVE THEN
    LOOP ;
: _ca-pump-poll-once  ( -- )
    4000 0 DO
        _ca-auth @ CDA.AUTH AAUTH-POLL DROP
        _ca-auth @ CDA.SUBSTATE @ CDA-SUB-IDLE = IF LEAVE THEN
    LOOP ;
: _ca-pump-to-ready  ( -- )
    8000 0 DO
        _ca-auth @ CDA.AUTH AAUTH-POLL DROP
        _ca-auth @ CDA.AUTH AAUTH.STATE @ AAUTH-STATE-READY = IF LEAVE THEN
    LOOP ;

VARIABLE _ca-access-seen
: _ca-access-callback  ( addr len context -- status )
    DROP _ca-access-token _ca-access-token-u @ STR-STR= _ca-access-seen ! 0 ;

: _ca-zero?  ( addr len -- flag )
    -1 -ROT 0 ?DO DUP I + C@ IF SWAP DROP 0 SWAP THEN LOOP DROP ;

: _ca-run  ( -- )
    0 _ca-fails ! 0 _ca-checks ! DEPTH _ca-depth !
    0 _ca-opens ! 0 _ca-closes ! 0 _ca-requests ! 0 _ca-force-close !
    _ca-build-tokens
    _ca-port NIO-INIT
    ['] _ca-open _ca-port NIO.OPEN-XT !
    ['] _ca-close _ca-port NIO.CLOSE-XT !
    ['] _ca-poll-port _ca-port NIO.POLL-XT !
    ['] _ca-send _ca-port NIO.SEND-XT !
    ['] _ca-recv _ca-port NIO.RECV-XT !
    CODEX-DEVICE-AUTH-SIZE ALLOCATE DUP 0= _ca-assert DROP _ca-auth !
    _ca-port _ca-auth @ CODEX-DEVICE-AUTH-INIT AAUTH-S-OK = _ca-assert
    _ca-auth @ CDA.AUTH AAUTH.STATE @ AAUTH-STATE-SIGNED-OUT = _ca-assert
    _ca-auth @ CDA.AUTH AAUTH-BEGIN AAUTH-S-PENDING = _ca-assert
    _ca-pump-to-pending
    _ca-auth @ CDA.AUTH AAUTH.STATE @ AAUTH-STATE-PENDING = _ca-assert
    _ca-auth @ CDA.AUTH AAUTH.USER-CODE DUP CV-DATA@ SWAP CV-LEN@
    S" TEST-CODE" STR-STR= _ca-assert
    _ca-auth @ CDA.AUTH AAUTH.VERIFY-URI DUP CV-DATA@ SWAP CV-LEN@
    CODEX-AUTH-VERIFY-URI STR-STR= _ca-assert

    _ca-auth @ CDA.AUTH AAUTH-POLL DROP
    _ca-pump-poll-once
    _ca-auth @ CDA.AUTH AAUTH.STATE @ AAUTH-STATE-PENDING = _ca-assert
    0 _ca-auth @ CDA.NEXT-POLL-MS !
    _ca-pump-to-ready
    _ca-auth @ CDA.AUTH AAUTH-READY? _ca-assert
    _ca-auth @ CDA.AUTH AAUTH.ACCOUNT-ID DUP CV-DATA@ SWAP CV-LEN@
    S" account-fixture" STR-STR= _ca-assert
    _ca-auth @ CDA.AUTH AAUTH.ACCOUNT-LABEL DUP CV-DATA@ SWAP CV-LEN@
    S" user@example.com" STR-STR= _ca-assert
    _ca-auth @ CDA.AUTH AAUTH.PLAN DUP CV-DATA@ SWAP CV-LEN@
    S" pro" STR-STR= _ca-assert
    0 _ca-access-seen !
    ['] _ca-access-callback 0 _ca-auth @ CDA.AUTH AAUTH-WITH-ACCESS
    AAUTH-S-OK = _ca-assert _ca-access-seen @ _ca-assert
    _ca-opens @ 2 = _ca-assert
    _ca-requests @ 4 = _ca-assert
    _ca-request _ca-request-u @ S" grant_type=authorization_code"
    STR-STR-CONTAINS _ca-assert
    _ca-request _ca-request-u @ S" code=authorization-fixture"
    STR-STR-CONTAINS _ca-assert
    _ca-request _ca-request-u @ S" code=%22authorization-fixture%22"
    STR-STR-CONTAINS 0= _ca-assert
    _ca-request _ca-request-u @ S" code_verifier=verifier-fixture"
    STR-STR-CONTAINS _ca-assert
    _ca-auth @ CDA.WORK @ 0= _ca-assert

    _ca-auth @ CDA.AUTH AAUTH-REFRESH AAUTH-S-PENDING = _ca-assert
    _ca-pump-to-ready
    _ca-auth @ CDA.AUTH AAUTH-READY? _ca-assert
    _ca-opens @ 3 = _ca-assert
    _ca-requests @ 5 = _ca-assert
    _ca-request _ca-request-u @ S" refresh_token" STR-STR-CONTAINS _ca-assert

    _ca-auth @ CDA.AUTH AAUTH-LOGOUT AAUTH-S-OK = _ca-assert
    _ca-auth @ CDA.TOKENS O2TOK-PRESENT? 0= _ca-assert
    _ca-id-token _ca-id-token-u @
    _ca-access-token _ca-access-token-u @
    S" refresh-fixture" 4102444800000 _ca-auth @
    CODEX-DEVICE-AUTH-RESTORE AAUTH-S-OK = _ca-assert
    _ca-auth @ CDA.AUTH AAUTH-READY? _ca-assert
    _ca-auth @ CDA.TOKENS O2TOK-PRESENT? _ca-assert
    _ca-auth @ CDA.WORK @ 0= _ca-assert
    _ca-auth @ CDA.AUTH AAUTH.ACCOUNT-ID DUP CV-DATA@ SWAP CV-LEN@
    S" account-fixture" STR-STR= _ca-assert
    _ca-auth @ CDA.AUTH AAUTH-LOGOUT AAUTH-S-OK = _ca-assert
    _ca-auth @ CDA.AUTH AAUTH-BEGIN AAUTH-S-PENDING = _ca-assert
    _ca-auth @ CDA.AUTH AAUTH-CANCEL AAUTH-S-CANCELLED = _ca-assert
    _ca-auth @ CDA.AUTH AAUTH.STATE @ AAUTH-STATE-SIGNED-OUT = _ca-assert
    _ca-auth @ CDA.AUTH AAUTH-DESTROY
    _ca-auth @ FREE
    _ca-stack
    _ca-fails @ 0= IF
        ." CODEX AUTH PASS " _ca-checks @ .
    ELSE
        ." CODEX AUTH FAIL " _ca-fails @ . ." / " _ca-checks @ .
    THEN CR ;

_ca-run
""",
        ready_markers=("CODEX AUTH PASS",),
        stable_markers=("CODEX AUTH PASS",),
    ),
    "codex-catalog": Profile(
        roots=("agent/providers/codex/model-catalog.f",),
        resources=(),
        autoexec=r"""\ autoexec.f - native Codex model catalog fixture
ENTER-USERLAND
." [akashic] loading Codex model catalog" CR
REQUIRE agent/providers/codex/model-catalog.f

VARIABLE _cc-fails
VARIABLE _cc-checks
VARIABLE _cc-depth
: _cc-assert  ( flag -- )
    1 _cc-checks +!
    0= IF 1 _cc-fails +! ." ASSERT " _cc-checks @ . CR THEN ;
: _cc-stack  ( -- )
    DEPTH DUP _cc-depth @ <> IF
        ." STACK " _cc-depth @ . ."  -> " DUP . CR .S CR
    THEN
    _cc-depth @ = _cc-assert ;

CREATE _cc-auth AGENT-PROVIDER-AUTH-SIZE ALLOT
CREATE _cc-port NET-IO-PORT-SIZE ALLOT
CREATE _cc-config OPENAI-CONFIG-SIZE ALLOT
VARIABLE _cc-catalog
CREATE _cc-json 32768 ALLOT
VARIABLE _cc-json-u
CREATE _cc-body 32768 ALLOT
VARIABLE _cc-body-u
CREATE _cc-response 49152 ALLOT
VARIABLE _cc-response-u
VARIABLE _cc-response-pos
CREATE _cc-requests 49152 ALLOT
CREATE _cc-request-us 24 ALLOT
VARIABLE _cc-opens
VARIABLE _cc-closes
VARIABLE _cc-mode
VARIABLE _cc-send-a
VARIABLE _cc-send-u
VARIABLE _cc-send-n
VARIABLE _cc-recv-a
VARIABLE _cc-recv-u
VARIABLE _cc-recv-n
VARIABLE _cc-current-a
VARIABLE _cc-current-u
VARIABLE _cc-token-n
VARIABLE _cc-refresh-hits
VARIABLE _cc-refresh-polls
VARIABLE _cc-callback
VARIABLE _cc-callback-context
VARIABLE _cc-pump-status
VARIABLE _cc-large

JSON-MAX-DOCUMENT 1024 + CONSTANT _CC-LARGE-U

: _cc-settings  ( -- settings ) _cc-catalog @ CDMC.SETTINGS ;
: _cc-b,  ( addr len -- )
    DUP >R _cc-body _cc-body-u @ + SWAP CMOVE R> _cc-body-u +! ;
: _cc-r,  ( addr len -- )
    DUP >R _cc-response _cc-response-u @ + SWAP CMOVE
    R> _cc-response-u +! ;
: _cc-rc,  ( c -- )
    _cc-response _cc-response-u @ + C! 1 _cc-response-u +! ;
: _cc-crlf,  ( -- ) 13 _cc-rc, 10 _cc-rc, ;

: _cc-build-catalog  ( -- )
    JSON-BUILD-RESET _cc-json 32768 JSON-SET-OUTPUT
    JSON-{ S" models" JSON-KEY: JSON-[
        JSON-{
            S" slug" S" gpt-slow" JSON-KV-ESTR
            S" display_name" S" Deliberate" JSON-KV-ESTR
            S" description" S" Careful general work" JSON-KV-ESTR
            S" visibility" S" list" JSON-KV-ESTR
            S" priority" 20 JSON-KV-NUM
            S" context_window" 200000 JSON-KV-NUM
            S" use_responses_lite" 0 JSON-KV-BOOL
            S" support_verbosity" -1 JSON-KV-BOOL
            S" default_verbosity" S" medium" JSON-KV-ESTR
            S" default_reasoning_summary" S" auto" JSON-KV-ESTR
            S" base_instructions" S" Slow instructions." JSON-KV-ESTR
            \ Preserve JSON-KEY's historical first-match behavior.
            S" slug" S" ignored-late-duplicate" JSON-KV-ESTR
            S" default_reasoning_level" S" high" JSON-KV-ESTR
            S" supported_reasoning_levels" JSON-KEY: JSON-[
                JSON-{ S" effort" S" low" JSON-KV-ESTR
                    S" description" S" Quicker" JSON-KV-ESTR JSON-}
                JSON-{ S" effort" S" high" JSON-KV-ESTR
                    S" description" S" More reasoning" JSON-KV-ESTR JSON-}
            JSON-]
            S" service_tiers" JSON-KEY: JSON-[
                JSON-{ S" id" S" priority" JSON-KV-ESTR
                    S" name" S" Fast" JSON-KV-ESTR
                    S" description" S" Faster responses" JSON-KV-ESTR JSON-}
            JSON-]
            S" default_service_tier" JSON-KV-NULL
        JSON-}
        JSON-{
            S" visibility" S" hide" JSON-KV-ESTR
            S" priority" 0 JSON-KV-NUM
            \ Hidden entries must not validate fields that are never consumed.
            S" base_instructions" 7 JSON-KV-NUM
        JSON-}
        JSON-{
            S" slug" S" gpt-fast" JSON-KV-ESTR
            S" display_name" S" Swift" JSON-KV-ESTR
            S" description" S" Fast everyday work" JSON-KV-ESTR
            S" priority" 1 JSON-KV-NUM
            S" context_window" 100000 JSON-KV-NUM
            S" use_responses_lite" -1 JSON-KV-BOOL
            S" support_verbosity" -1 JSON-KV-BOOL
            S" default_verbosity" S" low" JSON-KV-ESTR
            S" default_reasoning_summary" S" none" JSON-KV-ESTR
            S" base_instructions" S" Fast instructions." JSON-KV-ESTR
            S" default_reasoning_level" S" low" JSON-KV-ESTR
            S" supported_reasoning_levels" JSON-KEY: JSON-[
                JSON-{ S" effort" S" low" JSON-KV-ESTR
                    S" description" S" Quick" JSON-KV-ESTR JSON-}
                JSON-{ S" effort" S" medium" JSON-KV-ESTR
                    S" description" S" Balanced" JSON-KV-ESTR JSON-}
            JSON-]
            S" service_tiers" JSON-KEY: JSON-[ JSON-]
            S" default_service_tier" JSON-KV-NULL
            \ Exercise order independence by placing visibility last.
            S" visibility" S" list" JSON-KV-ESTR
        JSON-}
    JSON-] JSON-}
    JSON-OUTPUT-RESULT NIP _cc-json-u ! ;

: _cc-http-wrap  ( code -- )
    0 _cc-response-u !
    DUP 200 = IF
        DROP S" HTTP/1.1 200 OK"
    ELSE
        DROP S" HTTP/1.1 401 Unauthorized"
    THEN
    _cc-r, _cc-crlf,
    S" Content-Type: application/json" _cc-r, _cc-crlf,
    S" Content-Length: " _cc-r, _cc-body-u @ NUM>STR _cc-r, _cc-crlf,
    S" Connection: close" _cc-r, _cc-crlf, _cc-crlf,
    _cc-body _cc-body-u @ _cc-r, ;

: _cc-catalog-response  ( -- )
    0 _cc-body-u ! _cc-json _cc-json-u @ _cc-b, 200 _cc-http-wrap ;
: _cc-unauthorized-response  ( -- )
    0 _cc-body-u ! S" {}" _cc-b, 401 _cc-http-wrap ;
: _cc-malformed-response  ( -- )
    0 _cc-body-u ! S" {" _cc-b, 200 _cc-http-wrap ;

: _cc-reset-io  ( -- )
    0 _cc-opens ! 0 _cc-closes !
    _cc-request-us 24 0 FILL _cc-requests 49152 0 FILL ;

: _cc-request  ( index -- addr len )
    DUP 8 * _cc-request-us + @ >R 16384 * _cc-requests + R> ;

: _cc-open  ( context -- status )
    DROP 1 _cc-opens +! 0 _cc-response-pos !
    _cc-opens @ 1- 2 MIN DUP 16384 * _cc-requests + _cc-current-a !
    8 * _cc-request-us + DUP _cc-current-u ! 0 SWAP !
    _cc-mode @ 2 = IF _cc-unauthorized-response NIO-S-OK EXIT THEN
    _cc-mode @ 1 = _cc-opens @ 1 = AND IF
        _cc-unauthorized-response NIO-S-OK EXIT
    THEN
    _cc-mode @ 3 = IF _cc-malformed-response NIO-S-OK EXIT THEN
    _cc-catalog-response NIO-S-OK ;
: _cc-close  ( context -- ) DROP 1 _cc-closes +! ;
: _cc-poll-port  ( context -- ) DROP ;
: _cc-send  ( addr len context -- count status )
    DROP _cc-send-u ! _cc-send-a !
    _cc-send-u @ _cc-send-n !
    _cc-current-u @ @ _cc-send-n @ + 16384 > IF
        0 NIO-S-FAILED EXIT
    THEN
    _cc-send-a @ _cc-current-a @ _cc-current-u @ @ +
    _cc-send-n @ CMOVE
    _cc-send-n @ _cc-current-u @ +!
    _cc-send-n @ NIO-S-OK ;
: _cc-recv  ( addr cap context -- count status )
    DROP _cc-recv-u ! _cc-recv-a !
    _cc-response-pos @ _cc-response-u @ >= IF 0 NIO-S-EOF EXIT THEN
    _cc-response-u @ _cc-response-pos @ - _cc-recv-u @ MIN
    _cc-recv-n !
    _cc-response _cc-response-pos @ + _cc-recv-a @ _cc-recv-n @ CMOVE
    _cc-recv-n @ _cc-response-pos +!
    _cc-recv-n @ NIO-S-OK ;

: _cc-with-access  ( callback callback-context context -- status )
    DROP _cc-callback-context ! _cc-callback !
    _cc-token-n @ 1 = IF S" token-one" ELSE S" token-two" THEN
    _cc-callback-context @ _cc-callback @ EXECUTE ;

: _cc-auth-refresh  ( context -- status )
    DROP 1 _cc-refresh-hits +! 0 _cc-refresh-polls !
    AAUTH-STATE-REFRESHING _cc-auth AAUTH.STATE !
    1 _cc-auth AAUTH.REVISION +! AAUTH-S-PENDING ;

: _cc-auth-poll  ( context -- status )
    DROP _cc-auth AAUTH.STATE @ AAUTH-STATE-REFRESHING <> IF
        AAUTH-S-OK EXIT
    THEN
    1 _cc-refresh-polls +!
    _cc-refresh-polls @ 2 < IF AAUTH-S-PENDING EXIT THEN
    2 _cc-token-n ! AAUTH-STATE-READY _cc-auth AAUTH.STATE !
    1 _cc-auth AAUTH.REVISION +! AAUTH-S-OK ;

: _cc-auth-ready  ( -- )
    1 _cc-token-n ! 0 _cc-refresh-hits ! 0 _cc-refresh-polls !
    AAUTH-STATE-READY _cc-auth AAUTH.STATE ! ;

: _cc-pump  ( -- status )
    ARSET-S-PENDING _cc-pump-status !
    12000 0 DO
        _cc-settings ARSET-POLL _cc-pump-status !
        _cc-pump-status @ ARSET-S-PENDING <> IF
            _cc-pump-status @ UNLOOP EXIT
        THEN
    LOOP
    _cc-pump-status @ ;

: _cc-setup  ( -- )
    _cc-build-catalog
    _cc-port NIO-INIT
    ['] _cc-open _cc-port NIO.OPEN-XT !
    ['] _cc-close _cc-port NIO.CLOSE-XT !
    ['] _cc-poll-port _cc-port NIO.POLL-XT !
    ['] _cc-send _cc-port NIO.SEND-XT !
    ['] _cc-recv _cc-port NIO.RECV-XT !
    _cc-auth AAUTH-INIT
    _cc-auth _cc-auth AAUTH.CONTEXT !
    AAUTH-M-DEVICE _cc-auth AAUTH.METHODS !
    ['] _cc-with-access _cc-auth AAUTH.WITH-ACCESS-XT !
    ['] _cc-auth-refresh _cc-auth AAUTH.REFRESH-XT !
    ['] _cc-auth-poll _cc-auth AAUTH.POLL-XT !
    S" account-fixture" _cc-auth AAUTH.ACCOUNT-ID CV-STRING! 0= _cc-assert
    _cc-auth-ready
    _cc-config CODEX-CONFIG-INIT OAIC-S-OK = _cc-assert
    CODEX-MODEL-CATALOG-SIZE ALLOCATE
    DUP 0= _cc-assert DROP _cc-catalog !
    _cc-auth _cc-port _cc-catalog @ CDMC-INIT ARSET-S-OK = _cc-assert
    _cc-config _cc-catalog @ CDMC-CONFIG! ;

: _cc-test-catalog  ( -- )
    0 _cc-mode ! _cc-reset-io
    _cc-settings ARSET-REFRESH ARSET-S-PENDING = _cc-assert
    _cc-pump ARSET-S-OK = _cc-assert
    _cc-settings ARSET.STATE @ ARSET-STATE-READY = _cc-assert
    _cc-settings ARSET-MODEL-N 2 = _cc-assert
    0 _cc-settings ARSET-MODEL-NTH ARMODEL-ID
    S" gpt-fast" STR-STR= _cc-assert
    1 _cc-settings ARSET-MODEL-NTH ARMODEL-ID
    S" gpt-slow" STR-STR= _cc-assert
    _cc-settings ARSET-SELECTED-MODEL
    0 _cc-settings ARSET-MODEL-NTH = _cc-assert
    _cc-config OAIC-MODEL S" gpt-fast" STR-STR= _cc-assert
    _cc-config OAIC-EFFORT S" low" STR-STR= _cc-assert
    _cc-config OAIC-TIER NIP 0= _cc-assert
    _cc-config OAIC-SUMMARY NIP 0= _cc-assert
    _cc-config OAIC-VERBOSITY S" low" STR-STR= _cc-assert
    _cc-config OAIC-INSTRUCTIONS S" Fast instructions." STR-STR= _cc-assert
    _cc-config OAIC-RESPONSES-LITE? _cc-assert
    0 _cc-request CODEX-MODELS-PATH STR-STR-CONTAINS _cc-assert
    0 _cc-request S" Authorization: Bearer token-one" STR-STR-CONTAINS
    _cc-assert
    0 _cc-request S" ChatGPT-Account-ID: account-fixture"
    STR-STR-CONTAINS _cc-assert ;

: _cc-test-large-catalog  ( -- )
    _CC-LARGE-U ALLOCATE
    DUP 0= _cc-assert DROP _cc-large !
    _cc-json-u @ 1- >R
    _cc-json _cc-large @ R@ CMOVE
    _cc-large @ R@ + _CC-LARGE-U R@ - 1- 32 FILL
    125 _cc-large @ _CC-LARGE-U 1- + C! R> DROP
    _cc-large @ _CC-LARGE-U JSON-VALID? 0= _cc-assert
    _cc-large @ _CC-LARGE-U CDMC-BODY-CAPACITY JSON-VALID-LIMIT? _cc-assert
    _cc-large @ _CC-LARGE-U _cc-catalog @ _CDMC-PARSE
    ARSET-S-OK = _cc-assert
    _cc-settings ARSET-MODEL-N 2 = _cc-assert
    _cc-large @ FREE 0 _cc-large ! ;

: _cc-test-selection  ( -- )
    1 _cc-settings ARSET-MODEL! ARSET-S-OK = _cc-assert
    _cc-config OAIC-MODEL S" gpt-slow" STR-STR= _cc-assert
    _cc-config OAIC-EFFORT S" high" STR-STR= _cc-assert
    _cc-config OAIC-SUMMARY S" auto" STR-STR= _cc-assert
    _cc-config OAIC-VERBOSITY S" medium" STR-STR= _cc-assert
    _cc-config OAIC-RESPONSES-LITE? 0= _cc-assert
    0 _cc-settings ARSET-EFFORT! ARSET-S-OK = _cc-assert
    _cc-config OAIC-EFFORT S" low" STR-STR= _cc-assert
    0 _cc-settings ARSET-TIER! ARSET-S-OK = _cc-assert
    _cc-config OAIC-TIER S" priority" STR-STR= _cc-assert
    -1 _cc-settings ARSET-TIER! ARSET-S-OK = _cc-assert
    _cc-config OAIC-TIER NIP 0= _cc-assert
    ARVERB-HIGH _cc-settings ARSET-VERBOSITY! ARSET-S-OK = _cc-assert
    _cc-config OAIC-VERBOSITY S" high" STR-STR= _cc-assert
    ARVERB-AUTO _cc-settings ARSET-VERBOSITY! ARSET-S-OK = _cc-assert
    _cc-config OAIC-VERBOSITY S" medium" STR-STR= _cc-assert
    -1 _cc-settings ARSET-MODEL! ARSET-S-INVALID = _cc-assert
    2 _cc-settings ARSET-MODEL! ARSET-S-INVALID = _cc-assert
    -1 _cc-settings ARSET-EFFORT! ARSET-S-INVALID = _cc-assert
    1 _cc-settings ARSET-TIER! ARSET-S-INVALID = _cc-assert
    9 _cc-settings ARSET-VERBOSITY! ARSET-S-INVALID = _cc-assert ;

: _cc-test-auth-retry  ( -- )
    1 _cc-mode ! _cc-reset-io _cc-auth-ready
    _cc-settings ARSET-REFRESH ARSET-S-PENDING = _cc-assert
    _cc-pump ARSET-S-OK = _cc-assert
    _cc-opens @ 2 = _cc-assert
    _cc-refresh-hits @ 1 = _cc-assert
    0 _cc-request S" Bearer token-one" STR-STR-CONTAINS _cc-assert
    1 _cc-request S" Bearer token-two" STR-STR-CONTAINS _cc-assert

    2 _cc-mode ! _cc-reset-io _cc-auth-ready
    _cc-settings ARSET-REFRESH ARSET-S-PENDING = _cc-assert
    _cc-pump ARSET-S-AUTH = _cc-assert
    _cc-opens @ 2 = _cc-assert
    _cc-settings ARSET.STATE @ ARSET-STATE-ERROR = _cc-assert
    _cc-settings ARSET-ERROR NIP 0> _cc-assert ;

: _cc-test-recovery  ( -- )
    3 _cc-mode ! _cc-reset-io _cc-auth-ready
    _cc-settings ARSET-REFRESH ARSET-S-PENDING = _cc-assert
    _cc-pump ARSET-S-PROTOCOL = _cc-assert
    _cc-settings ARSET.STATE @ ARSET-STATE-ERROR = _cc-assert
    0 _cc-mode ! _cc-reset-io
    _cc-settings ARSET-REFRESH ARSET-S-PENDING = _cc-assert
    _cc-pump ARSET-S-OK = _cc-assert
    _cc-settings ARSET.STATE @ ARSET-STATE-READY = _cc-assert ;

: _cc-cleanup  ( -- )
    _cc-settings ARSET-DESTROY
    _cc-catalog @ FREE
    _cc-auth AAUTH-DESTROY ;

: _cc-run  ( -- )
    0 _cc-fails ! 0 _cc-checks ! DEPTH _cc-depth !
    _cc-setup
    _cc-test-catalog
    _cc-test-large-catalog
    _cc-test-selection
    _cc-test-auth-retry
    _cc-test-recovery
    _cc-cleanup _cc-stack
    _cc-fails @ 0= IF
        ." CODEX CATALOG PASS " _cc-checks @ .
    ELSE
        ." CODEX CATALOG FAIL " _cc-fails @ . ." / " _cc-checks @ .
    THEN CR ;

_cc-run
""",
        ready_markers=("CODEX CATALOG PASS",),
        stable_markers=("CODEX CATALOG PASS",),
    ),
    "codex-source": Profile(
        roots=("agent/providers/codex/source.f", "agent/runtime.f"),
        resources=(),
        autoexec=r"""\ autoexec.f - owned Codex provider source
ENTER-USERLAND
." [akashic] loading Codex provider source" CR
REQUIRE agent/providers/codex/source.f
REQUIRE agent/runtime.f

VARIABLE _cm-fails
VARIABLE _cm-checks
VARIABLE _cm-depth
VARIABLE _cm-source
VARIABLE _cm-provider
VARIABLE _cm-runtime
CREATE _cm-wire 4096 ALLOT
CREATE _cm-request HTTP-REQUEST-SIZE ALLOT
CREATE _cm-session 200 ALLOT
: _cm-assert  ( flag -- )
    1 _cm-checks +!
    0= IF 1 _cm-fails +! ." ASSERT " _cm-checks @ . CR THEN ;
: _cm-stack  ( -- )
    DEPTH DUP _cm-depth @ <> IF
        ." STACK " _cm-depth @ . ." -> " DUP . CR .S CR
    THEN
    _cm-depth @ = _cm-assert ;

: _cm-run  ( -- )
    0 _cm-fails ! 0 _cm-checks ! DEPTH _cm-depth !
    CODEX-SOURCE-NEW
    DUP APSOURCE-S-OK = _cm-assert DROP _cm-source !
    _cm-source @ CODEX-SOURCE-CONFIG OAIC-HOST
    CODEX-BACKEND-HOST STR-STR= _cm-assert
    _cm-source @ CODEX-SOURCE-AUTH-TRANSPORT KDOSTLS-HOST
    CODEX-AUTH-HOST STR-STR= _cm-assert
    _cm-source @ CODEX-SOURCE-MODEL-TRANSPORT KDOSTLS-HOST
    CODEX-BACKEND-HOST STR-STR= _cm-assert
    _cm-source @ CODEX-SOURCE-AUTH CDA.AUTH AAUTH.METHODS @
    AAUTH-M-DEVICE AND 0<> _cm-assert

    _cm-source @ APSOURCE-PROVIDER-NEW
    DUP OAIR-S-OK = _cm-assert DROP _cm-provider !
    _cm-provider @ DUP APROV.ID-A @ SWAP APROV.ID-U @
    CODEX-PROVIDER-ID STR-STR= _cm-assert
    _cm-provider @ APROV-AUTH
    _cm-source @ CODEX-SOURCE-AUTH CDA.AUTH = _cm-assert
    TLS-TRUST-COUNT @ 2 = _cm-assert
    TLS-TRUST-VERSION @ 1 = _cm-assert
    TLS-TRUST-GENERATION @ CODEX-TRUST-GENERATION = _cm-assert
    S" auth.openai.com" 0 TLS-TRUST@ _TLS-SCOPE-MATCH? _cm-assert
    S" chatgpt.com" 1 TLS-TRUST@ _TLS-SCOPE-MATCH? _cm-assert
    S" api.openai.com" 0 TLS-TRUST@ _TLS-SCOPE-MATCH? 0= _cm-assert
    S" auth.openai.com.evil" 0 TLS-TRUST@ _TLS-SCOPE-MATCH? 0= _cm-assert
    _cm-provider @ APROV-RUN-SETTINGS
    _cm-source @ CODEX-SOURCE-CATALOG CDMC.SETTINGS = _cm-assert
    _cm-source @ CODEX-SOURCE-CATALOG CDMC.CONFIG @
    _cm-provider @ OPENAI-PROVIDER-CONFIG = _cm-assert
    _cm-provider @ APROV.FEATURES @ APROV-F-CONTEXT AND 0<> _cm-assert
    _cm-provider @ ARUNTIME-NEW DUP 0= _cm-assert DROP _cm-runtime !
    _cm-runtime @ ARUNTIME-AUTH DUP 0<> _cm-assert
    AAUTH.STATE @ AAUTH-STATE-SIGNED-OUT = _cm-assert
    _cm-runtime @ ARUNTIME-RUN-SETTINGS
    _cm-source @ CODEX-SOURCE-CATALOG CDMC.SETTINGS = _cm-assert
    S" hello" _cm-runtime @ ARUNTIME-SEND 4 = _cm-assert

    S" account-fixture"
    _cm-source @ CODEX-SOURCE-AUTH CDA.AUTH AAUTH.ACCOUNT-ID CV-STRING!
    0= _cm-assert
    _cm-provider @ OPENAI-PROVIDER-CONFIG OAIC.FLAGS DUP @
    OAIC-F-RESPONSES-LITE OR SWAP !
    _cm-wire 4096 _cm-request HREQ-INIT HREQ-S-OK = _cm-assert
    S" POST" CODEX-RESPONSES-PATH _cm-request HREQ-BEGIN
    HREQ-S-OK = _cm-assert
    _cm-session 200 0 FILL 42 _cm-session OAIR-S.THREAD-ID !
    _cm-request _cm-session _cm-provider @ _CODEX-HEADERS
    OAIR-S-OK = _cm-assert
    _cm-wire _cm-request HREQ.LENGTH @
    S" x-openai-internal-codex-responses-lite: true"
    STR-STR-CONTAINS _cm-assert
    _cm-runtime @ ARUNTIME-FREE
    _cm-provider @ APROV-FREE
    _cm-source @ APSOURCE-FREE
    _cm-stack
    _cm-fails @ 0= IF
        ." CODEX SOURCE PASS " _cm-checks @ .
    ELSE
        ." CODEX SOURCE FAIL " _cm-fails @ . ." / " _cm-checks @ .
    THEN CR ;

_cm-run
""",
        ready_markers=("CODEX SOURCE PASS",),
        stable_markers=("CODEX SOURCE PASS",),
    ),
    "net-stream": Profile(
        roots=("net/sse.f", "net/http-stream.f", "net/http.f"),
        resources=(),
        autoexec=r"""\ autoexec.f - native streaming protocol tests
ENTER-USERLAND
." [akashic] loading streaming parsers" CR
REQUIRE net/sse.f
REQUIRE net/http-stream.f
REQUIRE net/http.f

VARIABLE _ns-fails
VARIABLE _ns-checks
VARIABLE _ns-depth
: _ns-assert  ( flag -- )
    1 _ns-checks +!
    0= IF 1 _ns-fails +! ." ASSERT " _ns-checks @ . CR THEN ;
: _ns-stack  ( -- )
    DEPTH DUP _ns-depth @ <> IF
        ." STACK " _ns-depth @ . ." -> " DUP . CR .S CR
    THEN
    _ns-depth @ = _ns-assert ;

CREATE _ns-sse SSE-PARSER-SIZE ALLOT
CREATE _ns-fixture 512 ALLOT
VARIABLE _ns-fixture-u
CREATE _ns-expected 64 ALLOT
VARIABLE _ns-expected-u
VARIABLE _ns-events
VARIABLE _ns-split

: _ns-fc,  ( c -- )
    _ns-fixture _ns-fixture-u @ + C! 1 _ns-fixture-u +! ;
: _ns-f,  ( addr len -- )
    DUP >R _ns-fixture _ns-fixture-u @ + SWAP CMOVE
    R> _ns-fixture-u +! ;
: _ns-ec,  ( c -- )
    _ns-expected _ns-expected-u @ + C! 1 _ns-expected-u +! ;
: _ns-e,  ( addr len -- )
    DUP >R _ns-expected _ns-expected-u @ + SWAP CMOVE
    R> _ns-expected-u +! ;

: _ns-build-sse  ( -- )
    0 _ns-fixture-u !
    239 _ns-fc, 187 _ns-fc, 191 _ns-fc,
    S" : ping" _ns-f, 13 _ns-fc, 10 _ns-fc,
    S" retry: 1500" _ns-f, 10 _ns-fc,
    S" event: delta" _ns-f, 13 _ns-fc, 10 _ns-fc,
    S" id: 42" _ns-f, 13 _ns-fc, 10 _ns-fc,
    S" data: first" _ns-f, 10 _ns-fc,
    S" data:second" _ns-f, 13 _ns-fc, 10 _ns-fc,
    13 _ns-fc, 10 _ns-fc,
    S" id" _ns-f, 13 _ns-fc,
    S" retry: nope" _ns-f, 13 _ns-fc,
    S" data:  leading" _ns-f, 13 _ns-fc,
    13 _ns-fc,
    0 _ns-expected-u !
    S" first" _ns-e, 10 _ns-ec, S" second" _ns-e, ;

: _ns-sse-event  ( parser context -- status )
    DROP
    _ns-events @ 0= IF
        DUP SSE-EVENT S" delta" COMPARE 0= _ns-assert
        DUP SSE-DATA _ns-expected _ns-expected-u @ COMPARE 0= _ns-assert
        DUP SSE-LAST-ID S" 42" COMPARE 0= _ns-assert
        DUP SSE.RETRY @ 1500 = _ns-assert
    ELSE
        DUP SSE-EVENT S" message" COMPARE 0= _ns-assert
        DUP SSE-DATA S"  leading" COMPARE 0= _ns-assert
        DUP SSE-LAST-ID NIP 0= _ns-assert
        DUP SSE.RETRY @ 1500 = _ns-assert
    THEN
    DROP 1 _ns-events +! 0 ;

: _ns-sse-reset  ( -- )
    _ns-sse SSE-RESET 0 _ns-events ! ;

: _ns-sse-split  ( split -- )
    _ns-split ! _ns-sse-reset
    _ns-fixture _ns-split @ _ns-sse SSE-FEED SSE-S-OK = _ns-assert
    _ns-fixture _ns-split @ +
    _ns-fixture-u @ _ns-split @ - _ns-sse SSE-FEED
    SSE-S-OK = _ns-assert
    _ns-events @ 2 = _ns-assert
    _ns-sse SSE.STATE @ SSE-STATE-OPEN = _ns-assert ;

CREATE _ns-overflow SSE-LINE-CAPACITY 1+ ALLOT
CREATE _ns-large-line 2048 ALLOT
VARIABLE _ns-large-events
CREATE _ns-id-stream 64 ALLOT
VARIABLE _ns-id-u
: _ns-ic,  ( c -- )
    _ns-id-stream _ns-id-u @ + C! 1 _ns-id-u +! ;
: _ns-i,  ( addr len -- )
    DUP >R _ns-id-stream _ns-id-u @ + SWAP CMOVE R> _ns-id-u +! ;

: _ns-stop-event  ( parser context -- status ) 2DROP 1 ;
: _ns-throw-event  ( parser context -- status ) 2DROP -77 THROW 0 ;
: _ns-large-event  ( parser context -- status )
    DROP DUP SSE-DATA NIP 1500 = _ns-assert
    DROP 1 _ns-large-events +! 0 ;

: _ns-run-sse  ( -- )
    _ns-build-sse
    _ns-sse SSE-INIT ['] _ns-sse-event 0 _ns-sse SSE-ON-EVENT!
    _ns-fixture-u @ 1+ 0 DO I _ns-sse-split LOOP

    _ns-sse-reset
    _ns-fixture-u @ 0 DO
        _ns-fixture I + 1 _ns-sse SSE-FEED SSE-S-OK = _ns-assert
    LOOP
    _ns-events @ 2 = _ns-assert

    _ns-sse-reset
    S" data: pending" _ns-sse SSE-FEED SSE-S-OK = _ns-assert
    10 _ns-sse _SSE-BYTE
    _ns-sse SSE-EOF SSE-S-OK = _ns-assert
    _ns-events @ 0= _ns-assert
    _ns-sse SSE.STATE @ SSE-STATE-EOF = _ns-assert
    S" x" _ns-sse SSE-FEED SSE-S-CLOSED = _ns-assert

    _ns-overflow SSE-LINE-CAPACITY 1+ 65 FILL
    _ns-sse-reset
    _ns-overflow SSE-LINE-CAPACITY 1+ _ns-sse SSE-FEED
    SSE-S-LINE-OVERFLOW = _ns-assert

    _ns-sse SSE-RESET ['] _ns-large-event 0 _ns-sse SSE-ON-EVENT!
    _ns-large-line 2048 0 FILL
    S" data: " _ns-large-line SWAP CMOVE
    _ns-large-line 6 + 1500 65 FILL
    10 _ns-large-line 1506 + C! 10 _ns-large-line 1507 + C!
    0 _ns-large-events !
    _ns-large-line 1508 _ns-sse SSE-FEED SSE-S-OK = _ns-assert
    _ns-large-events @ 1 = _ns-assert

    _ns-sse SSE-RESET 0 _ns-id-u !
    S" id: keep" _ns-i, 10 _ns-ic,
    S" id: bad" _ns-i, 0 _ns-ic, S" value" _ns-i, 10 _ns-ic,
    _ns-id-stream _ns-id-u @ _ns-sse SSE-FEED SSE-S-OK = _ns-assert
    _ns-sse SSE-LAST-ID S" keep" COMPARE 0= _ns-assert

    _ns-sse SSE-RESET ['] _ns-stop-event 0 _ns-sse SSE-ON-EVENT!
    0 _ns-id-u ! S" data: stop" _ns-i, 10 _ns-ic, 10 _ns-ic,
    _ns-id-stream _ns-id-u @ _ns-sse SSE-FEED SSE-S-CALLBACK = _ns-assert
    _ns-sse SSE.STATE @ SSE-STATE-STOPPED = _ns-assert

    _ns-sse SSE-RESET ['] _ns-throw-event 0 _ns-sse SSE-ON-EVENT!
    _ns-id-stream _ns-id-u @ _ns-sse SSE-FEED SSE-S-CALLBACK = _ns-assert
    _ns-sse SSE.STATE @ SSE-STATE-STOPPED = _ns-assert ;

CREATE _nh-parser HSTR-PARSER-SIZE ALLOT
CREATE _nh-response 1024 ALLOT
VARIABLE _nh-response-u
CREATE _nh-output 256 ALLOT
VARIABLE _nh-output-u
VARIABLE _nh-headers
VARIABLE _nh-kind
VARIABLE _nh-split

: _nh-c,  ( c -- )
    _nh-response _nh-response-u @ + C! 1 _nh-response-u +! ;
: _nh-r,  ( addr len -- )
    DUP >R _nh-response _nh-response-u @ + SWAP CMOVE
    R> _nh-response-u +! ;
: _nh-crlf  ( -- ) 13 _nh-c, 10 _nh-c, ;
: _nh-out+  ( addr len -- )
    DUP _nh-output-u @ + 256 <= _ns-assert
    DUP >R _nh-output _nh-output-u @ + SWAP CMOVE R> _nh-output-u +! ;

: _nh-header-cb  ( parser context -- status )
    DROP >R 1 _nh-headers +!
    _nh-kind @ 1 = IF
        R@ HSTR.CODE @ 200 = _ns-assert
        R@ HSTR.VERSION @ 11 = _ns-assert
        R@ HSTR.BODY-MODE @ HSTR-BODY-LENGTH = _ns-assert
        S" Content-Type" R@ HSTR-HEADER IF
            S" text/event-stream; charset=utf-8" COMPARE 0= _ns-assert
        ELSE
            2DROP 0 _ns-assert
        THEN
        S" X-Test" R@ HSTR-HEADER IF
            S" yes" COMPARE 0= _ns-assert
        ELSE
            2DROP 0 _ns-assert
        THEN
    THEN
    _nh-kind @ 2 = IF
        R@ HSTR.BODY-MODE @ HSTR-BODY-CHUNKED = _ns-assert
    THEN
    _nh-kind @ 3 = IF
        R@ HSTR.CODE @ 204 = _ns-assert
        R@ HSTR.BODY-MODE @ HSTR-BODY-NONE = _ns-assert
    THEN
    _nh-kind @ 4 = IF
        R@ HSTR.VERSION @ 10 = _ns-assert
        R@ HSTR.BODY-MODE @ HSTR-BODY-CLOSE = _ns-assert
    THEN
    R> DROP 0 ;

: _nh-body-cb  ( parser context -- status )
    DROP HSTR-BODY-SLICE _nh-out+ 0 ;
: _nh-stop-cb  ( parser context -- status ) 2DROP 1 ;

: _nh-reset  ( -- )
    _nh-parser HSTR-RESET
    0 _nh-output-u ! 0 _nh-headers ! ;

: _nh-build-length  ( -- )
    0 _nh-response-u !
    S" HTTP/1.1 200 OK" _nh-r, _nh-crlf
    S" Content-Type: text/event-stream; charset=utf-8" _nh-r, _nh-crlf
    S" Content-Length: 11" _nh-r, _nh-crlf
    S" X-Test: yes" _nh-r, _nh-crlf _nh-crlf
    S" hello world" _nh-r, ;

: _nh-build-chunked  ( -- )
    0 _nh-response-u !
    S" HTTP/1.1 200 OK" _nh-r, _nh-crlf
    S" Transfer-Encoding: chunked" _nh-r, _nh-crlf
    S" Content-Type: text/plain" _nh-r, _nh-crlf _nh-crlf
    S" 5;foo=bar" _nh-r, _nh-crlf S" hello" _nh-r, _nh-crlf
    S" 6" _nh-r, _nh-crlf S"  world" _nh-r, _nh-crlf
    S" 0" _nh-r, _nh-crlf S" X-Trailer: yes" _nh-r, _nh-crlf _nh-crlf ;

: _nh-build-interim  ( -- )
    0 _nh-response-u !
    S" HTTP/1.1 100 Continue" _nh-r, _nh-crlf _nh-crlf
    S" HTTP/1.1 204 No Content" _nh-r, _nh-crlf
    S" X-Final: yes" _nh-r, _nh-crlf _nh-crlf ;

: _nh-build-close  ( -- )
    0 _nh-response-u !
    S" HTTP/1.0 200 OK" _nh-r, _nh-crlf _nh-crlf
    S" close body" _nh-r, ;

: _nh-check-body  ( -- )
    _nh-output _nh-output-u @ S" hello world" COMPARE 0= _ns-assert
    _nh-parser HSTR.BODY-TOTAL @ 11 = _ns-assert ;

: _nh-run-split  ( split -- )
    _nh-split ! _nh-reset
    _nh-response _nh-split @ _nh-parser HSTR-FEED HSTR-S-OK = _ns-assert
    _nh-response _nh-split @ + _nh-response-u @ _nh-split @ -
    _nh-parser HSTR-FEED HSTR-S-OK = _ns-assert
    _nh-parser HSTR.STATE @ HSTR-STATE-DONE = _ns-assert
    _nh-headers @ 1 = _ns-assert _nh-check-body ;

: _nh-feed-all  ( -- status )
    _nh-reset _nh-response _nh-response-u @ _nh-parser HSTR-FEED ;

: _nh-run-http-positive  ( -- )
    _nh-parser HSTR-INIT
    ['] _nh-header-cb _nh-parser HSTR-ON-HEADERS!
    ['] _nh-body-cb _nh-parser HSTR-ON-BODY!
    0 _nh-parser HSTR-CONTEXT!

    1 _nh-kind ! _nh-build-length
    _nh-response-u @ 1+ 0 DO I _nh-run-split LOOP

    2 _nh-kind ! _nh-build-chunked
    _nh-response-u @ 1+ 0 DO I _nh-run-split LOOP
    _nh-reset
    _nh-response-u @ 0 DO
        _nh-response I + 1 _nh-parser HSTR-FEED HSTR-S-OK = _ns-assert
    LOOP
    _nh-parser HSTR.STATE @ HSTR-STATE-DONE = _ns-assert
    _nh-check-body

    3 _nh-kind ! _nh-build-interim _nh-feed-all HSTR-S-OK = _ns-assert
    _nh-parser HSTR.STATE @ HSTR-STATE-DONE = _ns-assert
    _nh-parser HSTR.INTERIMS @ 1 = _ns-assert
    _nh-headers @ 1 = _ns-assert
    _nh-output-u @ 0= _ns-assert

    4 _nh-kind ! _nh-build-close _nh-feed-all HSTR-S-OK = _ns-assert
    _nh-parser HSTR.STATE @ HSTR-STATE-CLOSE = _ns-assert
    _nh-parser HSTR-EOF HSTR-S-OK = _ns-assert
    _nh-parser HSTR.STATE @ HSTR-STATE-DONE = _ns-assert
    _nh-output _nh-output-u @ S" close body" COMPARE 0= _ns-assert

    0 _nh-kind ! HSTR-F-HEAD _nh-parser HSTR.FLAGS !
    0 _nh-response-u ! S" HTTP/1.1 200 OK" _nh-r, _nh-crlf
    S" Content-Length: 99" _nh-r, _nh-crlf _nh-crlf
    _nh-feed-all HSTR-S-OK = _ns-assert
    _nh-parser HSTR.STATE @ HSTR-STATE-DONE = _ns-assert
    _nh-parser HSTR.BODY-MODE @ HSTR-BODY-NONE = _ns-assert
    0 _nh-parser HSTR.FLAGS ! ;

: _nh-run-http-negative  ( -- )
    0 _nh-kind !
    0 _nh-response-u ! S" HTTP/1.1 200 OK" _nh-r, _nh-crlf
    S" Content-Length: 2" _nh-r, _nh-crlf
    S" Content-Length: 3" _nh-r, _nh-crlf _nh-crlf S" xx" _nh-r,
    _nh-feed-all HSTR-S-FRAMING = _ns-assert

    0 _nh-response-u ! S" HTTP/1.1 200 OK" _nh-r, _nh-crlf
    S" Transfer-Encoding: chunked" _nh-r, _nh-crlf
    S" Content-Length: 1" _nh-r, _nh-crlf _nh-crlf
    _nh-feed-all HSTR-S-FRAMING = _ns-assert

    0 _nh-response-u ! S" HTTP/1.1 200 OK" _nh-r, _nh-crlf
    S" Transfer-Encoding: gzip" _nh-r, _nh-crlf _nh-crlf
    _nh-feed-all HSTR-S-UNSUPPORTED = _ns-assert

    0 _nh-response-u ! S" HTTP/1.1 200 OK" _nh-r, 10 _nh-c,
    S" Content-Length: 0" _nh-r, 10 _nh-c, 10 _nh-c,
    _nh-feed-all HSTR-S-MALFORMED = _ns-assert

    0 _nh-response-u ! S" HTTP/1.1 200 OK" _nh-r, _nh-crlf
    S"  Folded: no" _nh-r, _nh-crlf _nh-crlf
    _nh-feed-all HSTR-S-MALFORMED = _ns-assert

    0 _nh-response-u ! S" HTTP/1.1 200 OK" _nh-r, _nh-crlf
    S" Transfer-Encoding: chunked" _nh-r, _nh-crlf _nh-crlf
    S" Z" _nh-r, _nh-crlf
    _nh-feed-all HSTR-S-FRAMING = _ns-assert

    0 _nh-response-u ! S" HTTP/1.1 200 OK" _nh-r, _nh-crlf
    S" Transfer-Encoding: chunked" _nh-r, _nh-crlf _nh-crlf
    S" 1" _nh-r, _nh-crlf S" x" _nh-r, _nh-crlf
    S" 0" _nh-r, _nh-crlf S" Content-Length: 9" _nh-r, _nh-crlf _nh-crlf
    _nh-feed-all HSTR-S-FRAMING = _ns-assert

    0 _nh-response-u ! S" HTTP/1.1 200 OK" _nh-r, _nh-crlf
    S" Content-Length: 5" _nh-r, _nh-crlf _nh-crlf S" abc" _nh-r,
    _nh-feed-all HSTR-S-OK = _ns-assert
    _nh-parser HSTR-EOF HSTR-S-TRUNCATED = _ns-assert

    4 _nh-parser HSTR-BODY-LIMIT!
    0 _nh-response-u ! S" HTTP/1.1 200 OK" _nh-r, _nh-crlf
    S" Content-Length: 5" _nh-r, _nh-crlf _nh-crlf S" abcde" _nh-r,
    _nh-feed-all HSTR-S-BODY-OVERFLOW = _ns-assert
    HSTR-DEFAULT-BODY-LIMIT _nh-parser HSTR-BODY-LIMIT!

    _nh-parser HSTR-RESET _nh-parser HSTR-CANCEL
    _nh-parser HSTR.STATUS @ HSTR-S-CANCELLED = _ns-assert

    ['] _nh-stop-cb _nh-parser HSTR-ON-BODY!
    0 _nh-response-u ! S" HTTP/1.1 200 OK" _nh-r, _nh-crlf
    S" Content-Length: 1" _nh-r, _nh-crlf _nh-crlf S" x" _nh-r,
    _nh-feed-all HSTR-S-CALLBACK = _ns-assert
    ['] _nh-body-cb _nh-parser HSTR-ON-BODY! ;

: _nh-run-http  ( -- )
    _nh-run-http-positive _nh-run-http-negative ;

CREATE _nh-long-host 65 ALLOT
VARIABLE _nh-zero
: _nh-run-http-guards  ( -- )
    S" native-secret" HTTP-SET-BEARER
    _HTTP-BEARER-LEN @ 13 = _ns-assert
    _HTTP-BEARER C@ 110 = _ns-assert
    HTTP-CLEAR-BEARER
    _HTTP-BEARER-LEN @ 0= _ns-assert
    -1 _nh-zero !
    512 0 DO _HTTP-BEARER I + C@ IF 0 _nh-zero ! THEN LOOP
    _nh-zero @ _ns-assert
    _nh-long-host 65 97 FILL HTTP-CLEAR-ERR
    _nh-long-host 65 443 -1 HTTP-CONNECT 0= _ns-assert
    HTTP-ERR @ HTTP-E-CONNECT = _ns-assert ;

CREATE _np-port NET-IO-PORT-SIZE ALLOT
CREATE _np-buffer 128 ALLOT
VARIABLE _np-position
VARIABLE _np-mode
VARIABLE _np-calls
VARIABLE _np-polls
VARIABLE _np-buffer-a
VARIABLE _np-capacity
VARIABLE _np-count
VARIABLE _np-result

: _np-poll  ( context -- ) DROP 1 _np-polls +! ;
: _np-close  ( context -- ) DROP ;
: _np-recv  ( buffer capacity context -- count status )
    DROP _np-capacity ! _np-buffer-a ! 1 _np-calls +!
    _np-mode @ 1 = IF 0 NIO-S-OK EXIT THEN
    _np-mode @ 2 = IF 0 NIO-S-FAILED EXIT THEN
    _np-mode @ 3 = IF 0 NIO-S-CANCELLED EXIT THEN
    _np-mode @ 4 = IF _np-capacity @ 1+ NIO-S-OK EXIT THEN
    _np-mode @ 5 = IF -91 THROW THEN
    _np-position @ _nh-response-u @ >= IF 0 NIO-S-EOF EXIT THEN
    _nh-response-u @ _np-position @ - _np-capacity @ MIN 7 MIN
    _np-count !
    _nh-response _np-position @ + _np-buffer-a @ _np-count @ CMOVE
    _np-count @ _np-position +!
    _np-count @ NIO-S-OK ;

: _np-reset  ( mode -- )
    _np-mode ! 0 _np-position ! 0 _np-calls ! 0 _np-polls !
    _nh-reset ;

: _np-run  ( -- )
    _np-port NIO-INIT
    ['] _np-recv _np-port NIO.RECV-XT !
    ['] _np-poll _np-port NIO.POLL-XT !
    ['] _np-close _np-port NIO.CLOSE-XT !
    0 _np-port NIO.CONTEXT !

    1 _nh-kind ! _nh-build-length 0 _np-reset
    100 0 DO
        _nh-parser _np-port _np-buffer 128 HSTR-PUMP _np-result !
        _np-result @ HSTR-PUMP-PARSER-ERROR = 0= _ns-assert
        _np-result @ HSTR-PUMP-TRANSPORT-ERROR = 0= _ns-assert
    LOOP
    _nh-parser HSTR.STATE @ HSTR-STATE-DONE = _ns-assert
    _nh-check-body
    _np-calls @ 1 > _ns-assert
    _np-polls @ _np-calls @ = _ns-assert

    0 _nh-kind ! _nh-build-length 1 _np-reset
    _nh-parser _np-port _np-buffer 128 HSTR-PUMP
    HSTR-PUMP-IDLE = _ns-assert

    2 _np-reset _nh-parser _np-port _np-buffer 128 HSTR-PUMP
    HSTR-PUMP-TRANSPORT-ERROR = _ns-assert

    3 _np-reset _nh-parser _np-port _np-buffer 128 HSTR-PUMP
    HSTR-PUMP-CANCELLED = _ns-assert
    _nh-parser HSTR.STATUS @ HSTR-S-CANCELLED = _ns-assert

    4 _np-reset _nh-parser _np-port _np-buffer 128 HSTR-PUMP
    HSTR-PUMP-TRANSPORT-ERROR = _ns-assert

    5 _np-reset _nh-parser _np-port _np-buffer 128 HSTR-PUMP
    HSTR-PUMP-TRANSPORT-ERROR = _ns-assert ;

: _ns-run  ( -- )
    0 _ns-fails ! 0 _ns-checks ! DEPTH _ns-depth !
    _ns-run-sse _ns-stack _nh-run-http _ns-stack
    _nh-run-http-guards _ns-stack _np-run _ns-stack
    _ns-fails @ 0= IF
        ." NET STREAM PASS " _ns-checks @ .
    ELSE
        ." NET STREAM FAIL " _ns-fails @ . ." / " _ns-checks @ .
    THEN CR ;

_ns-run
""",
        ready_markers=("NET STREAM PASS",),
        stable_markers=("NET STREAM PASS",),
    ),
    "mcp-component": Profile(
        roots=("interop/mcp/component-adapter.f",),
        resources=(),
        autoexec=r"""\ autoexec.f - native MCP component adapter
ENTER-USERLAND
." [akashic] loading MCP component adapter" CR
REQUIRE interop/mcp/component-adapter.f

VARIABLE _ma-fails
VARIABLE _ma-checks
VARIABLE _ma-depth
: _ma-assert  ( flag -- )
    1 _ma-checks +!
    0= IF 1 _ma-fails +! ." ASSERT " _ma-checks @ . CR THEN ;
: _ma-stack  ( -- )
    DEPTH DUP _ma-depth @ <> IF
        ." STACK DEPTH " _ma-depth @ . ." -> " DUP . CR .S CR
    THEN
    _ma-depth @ = _ma-assert ;

VARIABLE _ma-registry
VARIABLE _ma-bus
VARIABLE _ma-server
VARIABLE _ma-adapter
VARIABLE _ma-instance
VARIABLE _ma-review-hits
CREATE _ma-policy CPOLICY-SIZE ALLOT
CREATE _ma-text-schema CS-SIZE ALLOT
CREATE _ma-int-schema CS-SIZE ALLOT
CREATE _ma-caps CAP-DESC 2 * ALLOT
CREATE _ma-desc COMP-DESC ALLOT
CREATE _ma-call MCP-CALL-SIZE ALLOT
CREATE _ma-read MCP-READ-SIZE ALLOT
CREATE _ma-args 512 ALLOT
VARIABLE _ma-args-u
VARIABLE _ma-tool
VARIABLE _ma-resource

: _ma-persist-cap  ( -- cap ) _ma-caps ;
: _ma-observe-cap  ( -- cap ) _ma-caps CAP-DESC + ;

VARIABLE _mah-req
VARIABLE _mah-inst

: _ma-persist  ( request instance -- status )
    _mah-inst ! _mah-req !
    _mah-inst @ CINST-STATE DUP @ 1+ DUP >R SWAP !
    R> _mah-req @ CBR.RESULT CV-INT!
    CBUS-S-OK ;

: _ma-observe  ( request instance -- status )
    DROP S" native component resource" ROT CBR.RESULT CV-STRING!
    IF CBUS-S-FAILED ELSE CBUS-S-OK THEN ;

: _ma-review-allow  ( request context -- decision )
    SWAP DROP 1 SWAP +! MCPA-REVIEW-ALLOW ;

: _ma-review-deny  ( request context -- decision )
    SWAP DROP 1 SWAP +! MCPA-REVIEW-DENY ;

: _ma-review-cancel  ( request context -- decision )
    SWAP DROP 1 SWAP +! MCPA-REVIEW-CANCEL ;

: _ma-setup  ( -- )
    _ma-text-schema CS-INIT CV-T-STRING _ma-text-schema CS-ALLOW!
    256 _ma-text-schema CS-MAX-LEN!
    _ma-int-schema CS-INIT CV-T-INT _ma-int-schema CS-ALLOW!

    _ma-persist-cap CAP-DESC-INIT
    CAP-K-COMMAND _ma-persist-cap CAP.KIND !
    S" test.note.append"
    _ma-persist-cap CAP.ID-U ! _ma-persist-cap CAP.ID-A !
    S" Append note"
    _ma-persist-cap CAP.TITLE-U ! _ma-persist-cap CAP.TITLE-A !
    S" Append a reviewed persistent note"
    _ma-persist-cap CAP.DESC-U ! _ma-persist-cap CAP.DESC-A !
    _ma-text-schema _ma-persist-cap CAP.IN-SCHEMA !
    _ma-int-schema _ma-persist-cap CAP.OUT-SCHEMA !
    CAP-E-MUTATE CAP-E-PERSIST OR _ma-persist-cap CAP.EFFECTS !
    ['] _ma-persist _ma-persist-cap CAP.HANDLER-XT !

    _ma-observe-cap CAP-DESC-INIT
    CAP-K-RESOURCE _ma-observe-cap CAP.KIND !
    S" test.note.current"
    _ma-observe-cap CAP.ID-U ! _ma-observe-cap CAP.ID-A !
    S" Current note"
    _ma-observe-cap CAP.TITLE-U ! _ma-observe-cap CAP.TITLE-A !
    S" Read the native component resource"
    _ma-observe-cap CAP.DESC-U ! _ma-observe-cap CAP.DESC-A !
    _ma-text-schema _ma-observe-cap CAP.OUT-SCHEMA !
    CAP-E-OBSERVE _ma-observe-cap CAP.EFFECTS !
    CAP-F-IDEMPOTENT _ma-observe-cap CAP.FLAGS !
    ['] _ma-observe _ma-observe-cap CAP.HANDLER-XT !

    _ma-desc COMP-DESC-INIT
    S" org.akashic.test-component" _ma-desc COMP.ID-U ! _ma-desc COMP.ID-A !
    S" 1.0.0" _ma-desc COMP.VERSION-U ! _ma-desc COMP.VERSION-A !
    8 _ma-desc COMP.STATE-SIZE !
    _ma-caps _ma-desc COMP.CAPS-A ! 2 _ma-desc COMP.CAPS-N ! ;

: _ma-args-valid  ( -- )
    JSON-BUILD-RESET _ma-args 512 JSON-SET-OUTPUT
    JSON-{ S" value" S" reviewed entry" JSON-KV-ESTR JSON-}
    JSON-OUTPUT-RESULT NIP _ma-args-u ! ;

: _ma-args-empty  ( -- )
    S" {}" _ma-args SWAP CMOVE 2 _ma-args-u ! ;

: _ma-call-reset  ( -- )
    _ma-call MCP-CALL-FREE _ma-call MCP-CALL-INIT
    _ma-args _ma-call MCALL.ARGS-A !
    _ma-args-u @ _ma-call MCALL.ARGS-U ! ;

: _ma-invoke  ( binding -- status )
    MCPB.TOOL _ma-tool !
    _ma-call _ma-tool @ MTOOL.CONTEXT @
    _ma-tool @ MTOOL.CALL-XT @ EXECUTE ;

: _ma-read-resource  ( binding -- status )
    MCPB.RESOURCE _ma-resource !
    _ma-read _ma-resource @ MRES.CONTEXT @
    _ma-resource @ MRES.READ-XT @ EXECUTE ;

: _ma-run  ( -- )
    0 _ma-fails ! 0 _ma-checks ! 0 _ma-review-hits !
    DEPTH _ma-depth ! _ma-setup
    _ma-call MCP-CALL-INIT _ma-read MCP-READ-INIT
    CREG-NEW DUP 0= _ma-assert DROP _ma-registry !
    _ma-desc _ma-registry @ CREG-TYPE+ 0= _ma-assert
    _ma-desc CINST-NEW DUP 0= _ma-assert DROP
    DUP _ma-instance ! _ma-registry @ CREG-INST+ 0= _ma-assert
    _ma-policy CPOLICY-INIT
    _ma-registry @ _ma-policy CBUS-NEW DUP 0= _ma-assert DROP _ma-bus !
    S" component-test" S" 1.0.0" MCP-SERVER-NEW
    DUP 0= _ma-assert DROP _ma-server !
    _ma-registry @ _ma-bus @ _ma-server @ MCPA-NEW
    DUP 0= _ma-assert DROP _ma-adapter !
    ['] _ma-review-allow _ma-review-hits _ma-adapter @ MCPA-REVIEWER!
    _ma-adapter @ MCPA-REFRESH MCP-S-OK = _ma-assert
    _ma-adapter @ MCPA.BINDING-N @ 2 = _ma-assert
    _ma-server @ MSERVER.TOOL-N @ 2 = _ma-assert
    _ma-server @ MSERVER.RESOURCE-N @ 1 = _ma-assert
    0 _ma-adapter @ MCPA-BINDING-NTH MCPB.TOOL MCP-TOOL-NAME
    2DUP MCP-TOOL-NAME-VALID? _ma-assert
    S" .i" STR-STR-CONTAINS _ma-assert
    1 _ma-adapter @ MCPA-BINDING-NTH MCPB.RESOURCE MCP-RESOURCE-URI
    MCP-URI-VALID? _ma-assert

    _ma-args-valid _ma-call-reset
    0 _ma-adapter @ MCPA-BINDING-NTH _ma-invoke MCP-S-OK = _ma-assert
    _ma-call MCALL.RESULT CV-TYPE@ CV-T-INT = _ma-assert
    _ma-call MCALL.RESULT CV-DATA@ 1 = _ma-assert
    _ma-review-hits @ 1 = _ma-assert
    _ma-instance @ CINST-STATE @ 1 = _ma-assert

    _ma-read MCP-READ-FREE _ma-read MCP-READ-INIT
    1 _ma-adapter @ MCPA-BINDING-NTH _ma-read-resource MCP-S-OK = _ma-assert
    _ma-read MREAD.CONTENT CV-TYPE@ CV-T-STRING = _ma-assert

    ['] _ma-review-deny _ma-review-hits _ma-adapter @ MCPA-REVIEWER!
    _ma-call-reset
    0 _ma-adapter @ MCPA-BINDING-NTH _ma-invoke MCP-S-DENIED = _ma-assert
    _ma-instance @ CINST-STATE @ 1 = _ma-assert

    0 0 _ma-adapter @ MCPA-REVIEWER!
    _ma-call-reset
    0 _ma-adapter @ MCPA-BINDING-NTH _ma-invoke MCP-S-APPROVAL = _ma-assert
    _ma-instance @ CINST-STATE @ 1 = _ma-assert

    ['] _ma-review-cancel _ma-review-hits _ma-adapter @ MCPA-REVIEWER!
    _ma-call-reset
    0 _ma-adapter @ MCPA-BINDING-NTH _ma-invoke MCP-S-CANCELLED = _ma-assert
    _ma-instance @ CINST-STATE @ 1 = _ma-assert

    -1 _ma-persist-cap CAP.MAX-MS !
    ['] _ma-review-allow _ma-review-hits _ma-adapter @ MCPA-REVIEWER!
    _ma-call-reset
    0 _ma-adapter @ MCPA-BINDING-NTH _ma-invoke MCP-S-TIMEOUT = _ma-assert
    0 _ma-persist-cap CAP.MAX-MS !
    _ma-instance @ CINST-STATE @ 1 = _ma-assert

    _ma-args-empty _ma-call-reset
    0 _ma-adapter @ MCPA-BINDING-NTH _ma-invoke MCP-S-INVALID = _ma-assert
    _ma-args-valid _ma-call-reset
    _ma-instance @ _ma-registry @ CREG-INST- 0= _ma-assert
    0 _ma-adapter @ MCPA-BINDING-NTH _ma-invoke MCP-S-NOT-FOUND = _ma-assert

    _ma-call MCP-CALL-FREE _ma-read MCP-READ-FREE
    _ma-adapter @ MCPA-FREE _ma-server @ MCP-SERVER-FREE
    _ma-bus @ CBUS-FREE _ma-registry @ CREG-FREE _ma-instance @ CINST-FREE
    _ma-stack
    _ma-fails @ 0= IF
        ." MCP COMPONENT PASS"
    ELSE
        ." MCP COMPONENT FAIL " _ma-fails @ .
    THEN CR ;

_ma-run
""",
        ready_markers=("MCP COMPONENT PASS",),
        stable_markers=("MCP COMPONENT PASS",),
    ),
    "mcp": Profile(
        roots=("interop/mcp/server.f", "interop/mcp/client.f"),
        resources=(),
        autoexec=r"""\ autoexec.f - native MCP server contracts
ENTER-USERLAND
." [akashic] loading MCP server" CR
REQUIRE interop/mcp/server.f
REQUIRE interop/mcp/client.f

VARIABLE _mt-fails
VARIABLE _mt-checks
VARIABLE _mt-depth
: _mt-assert  ( flag -- )
    1 _mt-checks +!
    0= IF 1 _mt-fails +! ." ASSERT " _mt-checks @ . CR THEN ;
: _mt-stack  ( -- )
    DEPTH DUP _mt-depth @ <> IF
        ." STACK DEPTH " _mt-depth @ . ." -> " DUP . CR .S CR
    THEN
    _mt-depth @ = _mt-assert ;

CREATE _mt-in 8192 ALLOT
VARIABLE _mt-in-u
CREATE _mt-out 32768 ALLOT
VARIABLE _mt-out-u
CREATE _mt-params 4096 ALLOT
VARIABLE _mt-params-u
CREATE _mt-msg JRPC-MESSAGE-SIZE ALLOT
VARIABLE _mt-server
VARIABLE _mt-status
VARIABLE _mt-tool-hits
VARIABLE _mt-read-hits
VARIABLE _mt-client

CREATE _mt-string-schema CS-SIZE ALLOT
CREATE _mt-null-schema CS-SIZE ALLOT
CREATE _mt-tool MCP-TOOL-DESC-SIZE ALLOT
CREATE _mt-resource MCP-RESOURCE-DESC-SIZE ALLOT
CREATE _mt-template MCP-RESOURCE-TEMPLATE-SIZE ALLOT
CREATE _mt-transport MCP-TRANSPORT-SIZE ALLOT

0 CONSTANT _MTL-SERVER
8 CONSTANT _MTL-LEN
16 CONSTANT _MTL-STATUS
24 CONSTANT _MTL-CLOSED
32 CONSTANT _MTL-BUF
_MTL-BUF 32768 + CONSTANT _MTL-SIZE
CREATE _mt-loop _MTL-SIZE ALLOT

: _MTL.SERVER  ( loop -- a ) _MTL-SERVER + ;
: _MTL.LEN     ( loop -- a ) _MTL-LEN + ;
: _MTL.STATUS  ( loop -- a ) _MTL-STATUS + ;
: _MTL.CLOSED  ( loop -- a ) _MTL-CLOSED + ;
: _MTL.BUF     ( loop -- a ) _MTL-BUF + ;

VARIABLE _mtl-a
VARIABLE _mtl-u
VARIABLE _mtl-c

: _mt-loop-send  ( addr len loop -- status )
    _mtl-c ! _mtl-u ! _mtl-a !
    _mtl-a @ _mtl-u @ _mtl-c @ _MTL.BUF 32768
    _mtl-c @ _MTL.SERVER @ MCP-SERVER-HANDLE
    _mtl-c @ _MTL.STATUS ! _mtl-c @ _MTL.LEN !
    _mtl-c @ _MTL.STATUS @ ;

: _mt-loop-recv  ( buffer capacity loop -- len status )
    _mtl-c ! _mtl-u ! _mtl-a !
    _mtl-c @ _MTL.STATUS @ IF 0 _mtl-c @ _MTL.STATUS @ EXIT THEN
    _mtl-c @ _MTL.LEN @ _mtl-u @ > IF 0 MCP-S-CAPACITY EXIT THEN
    _mtl-c @ _MTL.BUF _mtl-a @ _mtl-c @ _MTL.LEN @ CMOVE
    _mtl-c @ _MTL.LEN @ MCP-S-OK ;

: _mt-loop-close  ( loop -- ) -1 SWAP _MTL.CLOSED ! ;

: _mt-tool-call  ( call context -- status )
    1 SWAP +!
    S" hello from native tool" ROT MCALL.RESULT CV-STRING!
    IF MCP-S-FAILED ELSE MCP-S-OK THEN ;

: _mt-resource-read  ( read context -- status )
    1 SWAP +!
    S" native resource body" ROT MREAD.CONTENT CV-STRING!
    IF MCP-S-FAILED ELSE MCP-S-OK THEN ;

: _mt-params-begin  ( -- )
    JSON-BUILD-RESET _mt-params 4096 JSON-SET-OUTPUT ;
: _mt-params-end  ( -- )
    JSON-OUTPUT-RESULT NIP _mt-params-u ! ;

: _mt-request  ( id method-a method-u params-a params-u -- )
    _mt-in 8192 JRPC-BUILD-REQUEST
    _mt-status ! _mt-in-u !
    _mt-status @ IF EXIT THEN
    _mt-in _mt-in-u @ _mt-out 32768 _mt-server @ MCP-SERVER-HANDLE
    _mt-status ! _mt-out-u ! ;

: _mt-notification  ( method-a method-u params-a params-u -- )
    _mt-in 8192 JRPC-BUILD-NOTIFICATION
    _mt-status ! _mt-in-u !
    _mt-status @ IF EXIT THEN
    _mt-in _mt-in-u @ _mt-out 32768 _mt-server @ MCP-SERVER-HANDLE
    _mt-status ! _mt-out-u ! ;

: _mt-parse  ( -- ior )
    _mt-out _mt-out-u @ _mt-msg JRPC-PARSE ;

: _mt-setup  ( -- )
    _mt-string-schema CS-INIT
    CV-T-STRING _mt-string-schema CS-ALLOW!
    256 _mt-string-schema CS-MAX-LEN!
    _mt-null-schema CS-INIT
    CV-T-NULL _mt-null-schema CS-ALLOW!

    _mt-tool MCP-TOOL-INIT
    S" echo.native" _mt-tool MTOOL.NAME-U ! _mt-tool MTOOL.NAME-A !
    S" Native echo" _mt-tool MTOOL.TITLE-U ! _mt-tool MTOOL.TITLE-A !
    S" Return a native test value"
    _mt-tool MTOOL.DESC-U ! _mt-tool MTOOL.DESC-A !
    _mt-null-schema _mt-tool MTOOL.IN-SCHEMA !
    _mt-string-schema _mt-tool MTOOL.OUT-SCHEMA !
    MCP-TOOL-F-READ-ONLY MCP-TOOL-F-IDEMPOTENT OR
    _mt-tool MTOOL.FLAGS !
    ['] _mt-tool-call _mt-tool MTOOL.CALL-XT !
    _mt-tool-hits _mt-tool MTOOL.CONTEXT !

    _mt-resource MCP-RESOURCE-INIT
    S" akashic://test/notes"
    _mt-resource MRES.URI-U ! _mt-resource MRES.URI-A !
    S" notes" _mt-resource MRES.NAME-U ! _mt-resource MRES.NAME-A !
    S" Native notes"
    _mt-resource MRES.TITLE-U ! _mt-resource MRES.TITLE-A !
    S" text/plain" _mt-resource MRES.MIME-U ! _mt-resource MRES.MIME-A !
    ['] _mt-resource-read _mt-resource MRES.READ-XT !
    _mt-read-hits _mt-resource MRES.CONTEXT !

    _mt-template MCP-RESOURCE-TEMPLATE-INIT
    S" akashic://test/{name}"
    _mt-template MRT.URI-U ! _mt-template MRT.URI-A !
    S" test-template"
    _mt-template MRT.NAME-U ! _mt-template MRT.NAME-A ! ;

: _mt-initialize-params  ( -- )
    _mt-params-begin JSON-{
    S" protocolVersion" MCP-PROTOCOL-VERSION JSON-KV-ESTR
    S" capabilities" JSON-KEY: JSON-{ JSON-}
    S" clientInfo" JSON-KEY: JSON-{
        S" name" S" native-test" JSON-KV-ESTR
        S" version" S" 1.0.0" JSON-KV-ESTR
    JSON-}
    JSON-} _mt-params-end ;

: _mt-call-params  ( -- )
    _mt-params-begin JSON-{
    S" name" S" echo.native" JSON-KV-ESTR
    S" arguments" JSON-KEY: JSON-{
        S" value" S" ignored" JSON-KV-ESTR
    JSON-}
    JSON-} _mt-params-end ;

: _mt-read-params  ( -- )
    _mt-params-begin JSON-{
    S" uri" S" akashic://test/notes" JSON-KV-ESTR
    JSON-} _mt-params-end ;

: _mt-run  ( -- )
    0 _mt-fails ! 0 _mt-checks ! 0 _mt-tool-hits ! 0 _mt-read-hits !
    DEPTH _mt-depth ! _mt-setup
    S" akashic-native-test" S" 1.0.0" MCP-SERVER-NEW
    DUP 0= _mt-assert DROP _mt-server !
    _mt-tool _mt-server @ MCP-SERVER-TOOL+ MCP-S-OK = _mt-assert
    _mt-resource _mt-server @ MCP-SERVER-RESOURCE+ MCP-S-OK = _mt-assert
    _mt-template _mt-server @ MCP-SERVER-TEMPLATE+ MCP-S-OK = _mt-assert

    1 S" tools/list" S" {}" _mt-request
    _mt-status @ MCP-S-OK = _mt-assert
    _mt-parse 0= _mt-assert
    _mt-msg JRPC.KIND @ JRPC-K-ERROR = _mt-assert
    _mt-msg JRPC.ERROR-CODE @ MCP-E-NOT-INITIALIZED = _mt-assert

    20 S" initialize" S" {}" _mt-request
    _mt-status @ MCP-S-OK = _mt-assert
    _mt-parse 0= _mt-assert
    _mt-msg JRPC.ERROR-CODE @ JRPC-E-INVALID-PARAMS = _mt-assert
    _mt-server @ MSERVER.STATE @ MCP-STATE-NEW = _mt-assert

    _mt-initialize-params
    2 S" initialize" _mt-params _mt-params-u @ _mt-request
    _mt-status @ MCP-S-OK = _mt-assert
    _mt-parse 0= _mt-assert
    _mt-msg JRPC.KIND @ JRPC-K-RESULT = _mt-assert
    _mt-msg JRPC.RESULT-A @ _mt-msg JRPC.RESULT-U @ JSON-OBJECT? _mt-assert
    _mt-server @ MSERVER.STATE @ MCP-STATE-INITIALIZING = _mt-assert

    3 S" ping" S" {}" _mt-request
    _mt-status @ MCP-S-OK = _mt-assert
    _mt-parse 0= _mt-assert
    _mt-msg JRPC.KIND @ JRPC-K-RESULT = _mt-assert

    S" notifications/initialized" S" " _mt-notification
    _mt-status @ MCP-S-OK = _mt-assert
    _mt-out-u @ 0= _mt-assert
    _mt-server @ MSERVER.STATE @ MCP-STATE-READY = _mt-assert

    4 S" tools/list" S" {}" _mt-request
    _mt-status @ MCP-S-OK = _mt-assert
    _mt-parse 0= _mt-assert
    _mt-msg JRPC.RESULT-A @ _mt-msg JRPC.RESULT-U @ JSON-ENTER
    S" tools" JSON-KEY JSON-ARRAY? _mt-assert

    _mt-params-begin JSON-{
    S" cursor" S" 99" JSON-KV-ESTR JSON-} _mt-params-end
    40 S" tools/list" _mt-params _mt-params-u @ _mt-request
    _mt-status @ MCP-S-OK = _mt-assert
    _mt-parse 0= _mt-assert
    _mt-msg JRPC.ERROR-CODE @ JRPC-E-INVALID-PARAMS = _mt-assert

    41 S" tools/call" S" {}" _mt-request
    _mt-status @ MCP-S-OK = _mt-assert
    _mt-parse 0= _mt-assert
    _mt-msg JRPC.ERROR-CODE @ JRPC-E-INVALID-PARAMS = _mt-assert

    _mt-call-params
    5 S" tools/call" _mt-params _mt-params-u @ _mt-request
    _mt-status @ MCP-S-OK = _mt-assert
    _mt-parse 0= _mt-assert
    _mt-tool-hits @ 1 = _mt-assert
    _mt-msg JRPC.RESULT-A @ _mt-msg JRPC.RESULT-U @ JSON-ENTER
    S" isError" JSON-KEY JSON-GET-BOOL 0= _mt-assert

    6 S" resources/list" S" {}" _mt-request
    _mt-status @ MCP-S-OK = _mt-assert
    _mt-parse 0= _mt-assert
    _mt-msg JRPC.RESULT-A @ _mt-msg JRPC.RESULT-U @ JSON-ENTER
    S" resources" JSON-KEY JSON-ARRAY? _mt-assert

    7 S" resources/templates/list" S" {}" _mt-request
    _mt-status @ MCP-S-OK = _mt-assert
    _mt-parse 0= _mt-assert
    _mt-msg JRPC.RESULT-A @ _mt-msg JRPC.RESULT-U @ JSON-ENTER
    S" resourceTemplates" JSON-KEY JSON-ARRAY? _mt-assert

    _mt-read-params
    8 S" resources/read" _mt-params _mt-params-u @ _mt-request
    _mt-status @ MCP-S-OK = _mt-assert
    _mt-parse 0= _mt-assert
    _mt-read-hits @ 1 = _mt-assert
    _mt-msg JRPC.RESULT-A @ _mt-msg JRPC.RESULT-U @ JSON-ENTER
    S" contents" JSON-KEY JSON-ARRAY? _mt-assert

    S" {" _mt-in SWAP CMOVE
    _mt-in 1 _mt-out 32768 _mt-server @ MCP-SERVER-HANDLE
    _mt-status ! _mt-out-u !
    _mt-status @ MCP-S-OK = _mt-assert
    _mt-parse 0= _mt-assert
    _mt-msg JRPC.ERROR-CODE @ JRPC-E-PARSE = _mt-assert

    _mt-server @ MCP-SERVER-FREE

    S" akashic-loopback" S" 1.0.0" MCP-SERVER-NEW
    DUP 0= _mt-assert DROP DUP _mt-server ! _mt-loop _MTL.SERVER !
    _mt-tool _mt-server @ MCP-SERVER-TOOL+ MCP-S-OK = _mt-assert
    _mt-resource _mt-server @ MCP-SERVER-RESOURCE+ MCP-S-OK = _mt-assert
    _mt-template _mt-server @ MCP-SERVER-TEMPLATE+ MCP-S-OK = _mt-assert
    _mt-transport MCP-TRANSPORT-INIT
    _mt-loop _mt-transport MTRANS.CONTEXT !
    ['] _mt-loop-send _mt-transport MTRANS.SEND-XT !
    ['] _mt-loop-recv _mt-transport MTRANS.RECV-XT !
    ['] _mt-loop-close _mt-transport MTRANS.CLOSE-XT !
    _mt-transport S" akashic-client-test" S" 1.0.0" MCP-CLIENT-NEW
    DUP 0= _mt-assert DROP _mt-client !
    _mt-client @ MCP-CLIENT-INITIALIZE MCP-S-OK = _mt-assert
    _mt-client @ MCLIENT.STATE @ MCP-STATE-READY = _mt-assert
    _mt-server @ MSERVER.STATE @ MCP-STATE-READY = _mt-assert
    _mt-client @ MCLIENT.SERVER-CAPS @
    MCP-CAP-TOOLS MCP-CAP-RESOURCES OR = _mt-assert

    _mt-client @ MCP-CLIENT-PING
    DUP MCP-S-OK = _mt-assert DROP JSON-OBJECT? _mt-assert
    S" 0" _mt-client @ MCP-CLIENT-TOOLS-LIST
    DUP MCP-S-OK = _mt-assert DROP JSON-OBJECT? _mt-assert
    S" echo.native" S" {}" _mt-client @ MCP-CLIENT-TOOLS-CALL
    DUP MCP-S-OK = _mt-assert DROP JSON-OBJECT? _mt-assert
    _mt-tool-hits @ 2 = _mt-assert
    4 S" already completed" _mt-client @ MCP-CLIENT-CANCEL
    MCP-S-OK = _mt-assert
    _mt-server @ MSERVER.STATE @ MCP-STATE-READY = _mt-assert
    S" " _mt-client @ MCP-CLIENT-RESOURCES-LIST
    DUP MCP-S-OK = _mt-assert DROP JSON-OBJECT? _mt-assert
    S" " _mt-client @ MCP-CLIENT-TEMPLATES-LIST
    DUP MCP-S-OK = _mt-assert DROP JSON-OBJECT? _mt-assert
    S" akashic://test/notes" _mt-client @ MCP-CLIENT-RESOURCE-READ
    DUP MCP-S-OK = _mt-assert DROP JSON-OBJECT? _mt-assert
    _mt-read-hits @ 2 = _mt-assert

    _mt-client @ MCP-CLIENT-CLOSE
    _mt-loop _MTL.CLOSED @ 0<> _mt-assert
    _mt-client @ MCP-CLIENT-FREE
    _mt-server @ MCP-SERVER-FREE
    _mt-stack
    _mt-fails @ 0= IF
        ." MCP SERVER PASS"
    ELSE
        ." MCP SERVER FAIL " _mt-fails @ .
    THEN CR ;

_mt-run
""",
        ready_markers=("MCP SERVER PASS",),
        stable_markers=("MCP SERVER PASS",),
    ),
    "codec-json": Profile(
        roots=("interop/codecs/json-schema.f",),
        resources=(),
        autoexec=r"""\ autoexec.f - native interoperability JSON codecs
ENTER-USERLAND
." [akashic] loading JSON codecs" CR
REQUIRE interop/codecs/json-schema.f

VARIABLE _ct-fails
VARIABLE _ct-checks
VARIABLE _ct-depth
: _ct-assert  ( flag -- )
    1 _ct-checks +!
    0= IF 1 _ct-fails +! ." ASSERT " _ct-checks @ . CR THEN ;
: _ct-stack  ( -- )
    DEPTH DUP _ct-depth @ <> IF
        ." STACK DEPTH " _ct-depth @ . ." -> " DUP . CR .S CR
    THEN
    _ct-depth @ = _ct-assert ;

CREATE _ct-json 2048 ALLOT
VARIABLE _ct-json-u
CREATE _ct-out 4096 ALLOT
VARIABLE _ct-out-u
CREATE _ct-val CV-SIZE ALLOT
CREATE _ct-copy CV-SIZE ALLOT
CREATE _ct-keybuf 3 ALLOT
CREATE _ct-resource-schema CS-SIZE ALLOT
CREATE _ct-null-schema CS-SIZE ALLOT

: _ct-reset  ( -- ) 0 _ct-json-u ! ;
: _ct-c  ( c -- ) _ct-json _ct-json-u @ + C! 1 _ct-json-u +! ;
: _ct-s  ( addr len -- )
    DUP >R _ct-json _ct-json-u @ + SWAP CMOVE R> _ct-json-u +! ;
: _ct-q  ( addr len -- ) 34 _ct-c _ct-s 34 _ct-c ;
: _ct-key  ( addr len -- ) _ct-q 58 _ct-c ;
: _ct-comma  ( -- ) 44 _ct-c ;

: _ct-document  ( -- )
    _ct-reset 123 _ct-c
    S" name" _ct-key S" Alpha" _ct-q _ct-comma
    S" items" _ct-key 91 _ct-c 49 _ct-c _ct-comma
        S" true" _ct-s _ct-comma S" null" _ct-s 93 _ct-c _ct-comma
    S" uri" _ct-key S" vfs:/notes.txt" _ct-q
    125 _ct-c ;

: _ct-duplicate  ( -- )
    _ct-reset 123 _ct-c S" x" _ct-key 49 _ct-c _ct-comma
    S" x" _ct-key 50 _ct-c 125 _ct-c ;

: _ct-unicode  ( -- )
    _ct-reset 34 _ct-c 92 _ct-c S" uD83D" _ct-s
    92 _ct-c S" uDE00" _ct-s 34 _ct-c ;

: _ct-bad-unicode  ( -- )
    _ct-reset 34 _ct-c 92 _ct-c S" uD800" _ct-s 34 _ct-c ;

: _ct-escaped-key  ( -- )
    97 _ct-keybuf C! 34 _ct-keybuf 1+ C! 98 _ct-keybuf 2 + C!
    _ct-reset 123 _ct-c 34 _ct-c 97 _ct-c 92 _ct-c 34 _ct-c
    98 _ct-c 34 _ct-c 58 _ct-c 49 _ct-c 125 _ct-c ;

: _ct-run  ( -- )
    0 _ct-fails ! 0 _ct-checks ! DEPTH _ct-depth !
    _ct-val CV-INIT _ct-copy CV-INIT

    _ct-document _ct-json _ct-json-u @ _ct-val IVJSON-DECODE
    0= _ct-assert
    _ct-val CV-TYPE@ CV-T-MAP = _ct-assert
    _ct-val CV-LEN@ 3 = _ct-assert
    S" name" _ct-val CV-MAP-FIND DUP 0<> _ct-assert
    DUP CV-TYPE@ CV-T-STRING = _ct-assert
    DUP CV-DATA@ SWAP CV-LEN@ S" Alpha" STR-STR= _ct-assert
    S" items" _ct-val CV-MAP-FIND DUP CV-TYPE@ CV-T-LIST = _ct-assert
    DUP CV-LEN@ 3 = _ct-assert
    0 OVER CV-LIST-NTH CV-DATA@ 1 = _ct-assert
    1 OVER CV-LIST-NTH CV-DATA@ 0<> _ct-assert
    2 SWAP CV-LIST-NTH CV-TYPE@ CV-T-NULL = _ct-assert

    _ct-val _ct-out 4096 IVJSON-ENCODE
    DUP 0= _ct-assert DROP DUP _ct-out-u ! 0> _ct-assert
    _ct-out _ct-out-u @ JSON-VALID? _ct-assert
    _ct-out _ct-out-u @ _ct-copy IVJSON-DECODE 0= _ct-assert
    _ct-copy CV-TYPE@ CV-T-MAP = _ct-assert
    _ct-stack

    _ct-val _ct-out 4 IVJSON-ENCODE
    IVJSON-E-CAPACITY = _ct-assert DROP

    _ct-duplicate _ct-json _ct-json-u @ _ct-copy IVJSON-DECODE
    IVJSON-E-INVALID = _ct-assert
    _ct-reset S" 1.5" _ct-s
    _ct-json _ct-json-u @ _ct-copy IVJSON-DECODE
    IVJSON-E-UNSUPPORTED = _ct-assert

    _ct-unicode _ct-json _ct-json-u @ _ct-copy IVJSON-DECODE 0= _ct-assert
    _ct-copy CV-LEN@ 4 = _ct-assert
    _ct-copy CV-DATA@ C@ 240 = _ct-assert
    _ct-bad-unicode _ct-json _ct-json-u @ _ct-copy IVJSON-DECODE
    IVJSON-E-INVALID = _ct-assert

    _ct-reset 34 _ct-c 195 _ct-c 169 _ct-c 34 _ct-c
    _ct-json _ct-json-u @ UTF8-VALID? _ct-assert
    _ct-json _ct-json-u @ JSON-VALID? _ct-assert
    _ct-reset 34 _ct-c 240 _ct-c 159 _ct-c 152 _ct-c 128 _ct-c 34 _ct-c
    _ct-json _ct-json-u @ JSON-VALID? _ct-assert
    _ct-reset 34 _ct-c 192 _ct-c 175 _ct-c 34 _ct-c
    _ct-json _ct-json-u @ UTF8-VALID? 0= _ct-assert
    _ct-json _ct-json-u @ JSON-VALID? 0= _ct-assert
    _ct-reset 34 _ct-c 237 _ct-c 160 _ct-c 128 _ct-c 34 _ct-c
    _ct-json _ct-json-u @ JSON-VALID? 0= _ct-assert
    _ct-reset 34 _ct-c 244 _ct-c 144 _ct-c 128 _ct-c 128 _ct-c 34 _ct-c
    _ct-json _ct-json-u @ JSON-VALID? 0= _ct-assert

    _ct-escaped-key _ct-json _ct-json-u @ _ct-copy IVJSON-DECODE
    0= _ct-assert
    _ct-keybuf 3 _ct-copy CV-MAP-FIND DUP 0<> _ct-assert
    CV-DATA@ 1 = _ct-assert
    _ct-copy _ct-out 4096 IVJSON-ENCODE
    DUP 0= _ct-assert DROP DUP _ct-out-u ! 0> _ct-assert
    _ct-out _ct-out-u @ JSON-VALID? _ct-assert

    _ct-resource-schema CS-INIT
    CV-T-RESOURCE _ct-resource-schema CS-ALLOW!
    128 _ct-resource-schema CS-MAX-LEN!
    _ct-reset S" vfs:/notes.txt" _ct-q
    _ct-json _ct-json-u @ _ct-resource-schema _ct-copy
    IVJSON-DECODE-AS 0= _ct-assert
    _ct-copy CV-TYPE@ CV-T-RESOURCE = _ct-assert

    _ct-resource-schema _ct-out 4096 CSJSON-ENCODE
    DUP 0= _ct-assert DROP DUP _ct-out-u ! 0> _ct-assert
    _ct-out _ct-out-u @ JSON-VALID? _ct-assert
    _ct-out _ct-out-u @ JSON-ENTER S" format" JSON-KEY
    S" uri" JSON-STRING= _ct-assert

    _ct-resource-schema _ct-out 4096 CSJSON-INPUT-ENCODE
    DUP 0= _ct-assert DROP DUP _ct-out-u ! 0> _ct-assert
    _ct-out _ct-out-u @ JSON-VALID? _ct-assert
    _ct-out _ct-out-u @ JSON-ENTER S" properties" JSON-KEY
    JSON-OBJECT? _ct-assert

    _ct-resource-schema _ct-out 4096 CSJSON-STRUCTURAL-INPUT-ENCODE
    DUP 0= _ct-assert DROP DUP _ct-out-u ! 0> _ct-assert
    _ct-out _ct-out-u @ JSON-VALID? _ct-assert
    _ct-out _ct-out-u @ S" format" STR-STR-CONTAINS 0= _ct-assert
    _ct-out _ct-out-u @ S" maxLength" STR-STR-CONTAINS _ct-assert

    _ct-null-schema CS-INIT
    CV-T-NULL _ct-null-schema CS-ALLOW!
    _ct-null-schema _ct-out 4096 CSJSON-INPUT-ENCODE
    DUP 0= _ct-assert DROP DUP _ct-out-u ! 0> _ct-assert
    _ct-out _ct-out-u @ JSON-VALID? _ct-assert
    _ct-out _ct-out-u @ JSON-ENTER S" properties" JSON-KEY
    JSON-ENTER JSON-COUNT 0= _ct-assert
    _ct-out _ct-out-u @ JSON-ENTER S" required" JSON-KEY
    JSON-ENTER JSON-COUNT 0= _ct-assert

    _ct-val CV-FREE _ct-copy CV-FREE
    _ct-stack
    _ct-fails @ 0= IF
        ." CODEC JSON PASS"
    ELSE
        ." CODEC JSON FAIL " _ct-fails @ .
    THEN CR ;

_ct-run
""",
        ready_markers=("CODEC JSON PASS",),
        stable_markers=("CODEC JSON PASS",),
    ),
    "jsonrpc": Profile(
        roots=("interop/jsonrpc/dispatcher.f",),
        resources=(),
        autoexec=r"""\ autoexec.f - native JSON-RPC contracts
ENTER-USERLAND
." [akashic] loading JSON-RPC contracts" CR
REQUIRE interop/jsonrpc/dispatcher.f

VARIABLE _jt-fails
VARIABLE _jt-checks
VARIABLE _jt-depth
: _jt-assert  ( flag -- )
    1 _jt-checks +!
    0= IF 1 _jt-fails +! ." ASSERT " _jt-checks @ . CR THEN ;
: _jt-stack  ( -- )
    DEPTH DUP _jt-depth @ <> IF
        ." STACK DEPTH " _jt-depth @ . ." -> " DUP . CR .S CR
    THEN
    _jt-depth @ = _jt-assert ;

CREATE _jt-json 2048 ALLOT
VARIABLE _jt-json-u
CREATE _jt-out 2048 ALLOT
VARIABLE _jt-out-u
CREATE _jt-msg JRPC-MESSAGE-SIZE ALLOT
VARIABLE _jt-disp
VARIABLE _jt-hits

: _jt-reset  ( -- ) 0 _jt-json-u ! ;
: _jt-c  ( c -- ) _jt-json _jt-json-u @ + C! 1 _jt-json-u +! ;
: _jt-s  ( addr len -- )
    DUP >R _jt-json _jt-json-u @ + SWAP CMOVE R> _jt-json-u +! ;
: _jt-q  ( addr len -- ) 34 _jt-c _jt-s 34 _jt-c ;
: _jt-key  ( addr len -- ) _jt-q 58 _jt-c ;
: _jt-comma  ( -- ) 44 _jt-c ;
: _jt-common  ( -- )
    123 _jt-c S" jsonrpc" _jt-key S" 2.0" _jt-q ;
: _jt-parse  ( -- ior )
    _jt-json _jt-json-u @ _jt-msg JRPC-PARSE ;

: _jt-request  ( -- )
    _jt-reset _jt-common _jt-comma
    S" id" _jt-key 55 _jt-c _jt-comma
    S" method" _jt-key S" echo" _jt-q _jt-comma
    S" params" _jt-key 123 _jt-c
        S" text" _jt-key S" hi" _jt-q
    125 _jt-c 125 _jt-c ;

: _jt-notification  ( -- )
    _jt-reset _jt-common _jt-comma
    S" method" _jt-key S" echo" _jt-q
    125 _jt-c ;

: _jt-result  ( -- )
    _jt-reset _jt-common _jt-comma
    S" id" _jt-key S" abc" _jt-q _jt-comma
    S" result" _jt-key 91 _jt-c 49 _jt-c _jt-comma 50 _jt-c 93 _jt-c
    125 _jt-c ;

: _jt-error  ( -- )
    _jt-reset _jt-common _jt-comma
    S" id" _jt-key S" null" _jt-s _jt-comma
    S" error" _jt-key 123 _jt-c
        S" code" _jt-key S" -32602" _jt-s _jt-comma
        S" message" _jt-key S" Bad params" _jt-q _jt-comma
        S" data" _jt-key 123 _jt-c S" field" _jt-key S" name" _jt-q 125 _jt-c
    125 _jt-c 125 _jt-c ;

: _jt-escaped-method  ( -- )
    _jt-reset _jt-common _jt-comma
    S" id" _jt-key 49 _jt-c _jt-comma
    S" method" _jt-key 34 _jt-c S" ec" _jt-s 92 _jt-c
        S" u0068o" _jt-s 34 _jt-c
    125 _jt-c ;

: _jt-escaped-fields  ( -- )
    _jt-reset 123 _jt-c
    34 _jt-c S" json" _jt-s 92 _jt-c S" u0072pc" _jt-s 34 _jt-c
    58 _jt-c 34 _jt-c S" 2" _jt-s 92 _jt-c S" u002e0" _jt-s 34 _jt-c
    _jt-comma S" id" _jt-key 50 _jt-c
    _jt-comma 34 _jt-c S" meth" _jt-s 92 _jt-c S" u006fd" _jt-s
    34 _jt-c 58 _jt-c S" echo" _jt-q 125 _jt-c ;

: _jt-duplicate-id  ( -- )
    _jt-reset _jt-common _jt-comma
    S" id" _jt-key 49 _jt-c _jt-comma S" id" _jt-key 50 _jt-c
    _jt-comma S" method" _jt-key S" echo" _jt-q 125 _jt-c ;

: _jt-wide-id  ( -- )
    _jt-reset _jt-common _jt-comma S" id" _jt-key
    S" 1234567890123456789" _jt-s _jt-comma
    S" method" _jt-key S" echo" _jt-q 125 _jt-c ;

: _jt-invalid-version  ( -- )
    _jt-reset 123 _jt-c S" jsonrpc" _jt-key S" 1.0" _jt-q _jt-comma
    S" id" _jt-key 49 _jt-c _jt-comma S" method" _jt-key S" echo" _jt-q
    125 _jt-c ;

: _jt-invalid-params  ( -- )
    _jt-reset _jt-common _jt-comma S" id" _jt-key 49 _jt-c _jt-comma
    S" method" _jt-key S" echo" _jt-q _jt-comma
    S" params" _jt-key 49 _jt-c 125 _jt-c ;

: _jt-result-and-error  ( -- )
    _jt-reset _jt-common _jt-comma S" id" _jt-key 49 _jt-c _jt-comma
    S" result" _jt-key S" null" _jt-s _jt-comma
    S" error" _jt-key 123 _jt-c S" code" _jt-key S" -1" _jt-s
    _jt-comma S" message" _jt-key S" no" _jt-q 125 _jt-c 125 _jt-c ;

: _jt-too-deep  ( -- )
    _jt-reset 17 0 DO 91 _jt-c LOOP 48 _jt-c 17 0 DO 93 _jt-c LOOP ;

: _jt-handler  ( message context -- error-code )
    SWAP DROP 1 SWAP +! 0 ;
: _jt-throwing-handler  ( message context -- error-code )
    2DROP -99 THROW ;

: _jt-run  ( -- )
    0 _jt-fails ! 0 _jt-checks ! DEPTH _jt-depth !

    _jt-request _jt-json _jt-json-u @ JRPC-JSON-VALID? _jt-assert
    _jt-parse 0= _jt-assert
    _jt-msg JRPC.KIND @ JRPC-K-REQUEST = _jt-assert
    _jt-msg JRPC.ID-KIND @ JRPC-ID-INT = _jt-assert
    _jt-msg JRPC.ID-INT @ 7 = _jt-assert
    _jt-msg JRPC-METHOD S" echo" STR-STR= _jt-assert
    _jt-msg JRPC.PARAMS-A @ _jt-msg JRPC.PARAMS-U @ JSON-OBJECT? _jt-assert
    _jt-stack

    _jt-notification _jt-parse 0= _jt-assert
    _jt-msg JRPC.KIND @ JRPC-K-NOTIFICATION = _jt-assert
    _jt-msg JRPC.ID-KIND @ JRPC-ID-ABSENT = _jt-assert

    _jt-result _jt-parse 0= _jt-assert
    _jt-msg JRPC.KIND @ JRPC-K-RESULT = _jt-assert
    _jt-msg JRPC.ID-KIND @ JRPC-ID-STRING = _jt-assert
    _jt-msg JRPC-ID-TEXT S" abc" STR-STR= _jt-assert
    _jt-msg JRPC.RESULT-A @ _jt-msg JRPC.RESULT-U @ JSON-ARRAY? _jt-assert

    _jt-error _jt-parse 0= _jt-assert
    _jt-msg JRPC.KIND @ JRPC-K-ERROR = _jt-assert
    _jt-msg JRPC.ID-KIND @ JRPC-ID-NULL = _jt-assert
    _jt-msg JRPC.ERROR-CODE @ -32602 = _jt-assert
    _jt-msg DUP JRPC.ERROR-MESSAGE-A @ SWAP JRPC.ERROR-MESSAGE-U @
    S" Bad params" STR-STR= _jt-assert
    _jt-msg JRPC.ERROR-DATA-A @ _jt-msg JRPC.ERROR-DATA-U @
    JSON-OBJECT? _jt-assert
    _jt-stack

    _jt-escaped-method _jt-parse 0= _jt-assert
    _jt-msg JRPC-METHOD S" echo" STR-STR= _jt-assert
    _jt-escaped-fields _jt-parse 0= _jt-assert
    _jt-msg JRPC.ID-INT @ 2 = _jt-assert
    _jt-msg JRPC-METHOD S" echo" STR-STR= _jt-assert
    _jt-duplicate-id _jt-parse JRPC-E-INVALID-REQUEST = _jt-assert
    _jt-wide-id _jt-parse JRPC-E-INVALID-REQUEST = _jt-assert

    _jt-invalid-version _jt-parse JRPC-E-INVALID-REQUEST = _jt-assert
    _jt-invalid-params _jt-parse JRPC-E-INVALID-PARAMS = _jt-assert
    _jt-result-and-error _jt-parse JRPC-E-INVALID-REQUEST = _jt-assert
    _jt-reset 123 _jt-c _jt-parse JRPC-E-PARSE = _jt-assert
    _jt-too-deep _jt-json _jt-json-u @ JRPC-JSON-VALID? 0= _jt-assert
    _jt-reset 34 _jt-c 255 _jt-c 34 _jt-c
    _jt-json _jt-json-u @ JRPC-JSON-VALID? 0= _jt-assert
    _jt-stack

    42 S" echo" S" {}" _jt-out 2048 JRPC-BUILD-REQUEST
    DUP 0= _jt-assert DROP DUP _jt-out-u ! 0> _jt-assert
    _jt-out _jt-out-u @ _jt-msg JRPC-PARSE 0= _jt-assert
    _jt-msg JRPC.ID-INT @ 42 = _jt-assert
    _jt-msg JRPC-METHOD S" echo" STR-STR= _jt-assert

    S" tick" S" []" _jt-out 2048 JRPC-BUILD-NOTIFICATION
    DUP 0= _jt-assert DROP DUP _jt-out-u ! 0> _jt-assert
    _jt-out _jt-out-u @ _jt-msg JRPC-PARSE 0= _jt-assert
    _jt-msg JRPC.KIND @ JRPC-K-NOTIFICATION = _jt-assert

    1 S" echo" S" {}" _jt-out 8 JRPC-BUILD-REQUEST
    JRPC-IOR-CAPACITY = _jt-assert DROP
    _jt-stack

    JRPC-DISPATCHER-NEW DUP 0= _jt-assert DROP _jt-disp !
    0 _jt-hits !
    S" echo" ['] _jt-handler _jt-hits 0 _jt-disp @
    JRPC-DISPATCH-REGISTER 0= _jt-assert
    S" boom" ['] _jt-throwing-handler 0 0 _jt-disp @
    JRPC-DISPATCH-REGISTER 0= _jt-assert
    S" echo" ['] _jt-handler _jt-hits 0 _jt-disp @
    JRPC-DISPATCH-REGISTER JRPC-IOR-VALUE = _jt-assert

    _jt-request _jt-parse 0= _jt-assert
    _jt-msg _jt-disp @ JRPC-DISPATCH 0= _jt-assert
    _jt-hits @ 1 = _jt-assert

    _jt-notification _jt-parse 0= _jt-assert
    _jt-msg _jt-disp @ JRPC-DISPATCH 0= _jt-assert
    _jt-hits @ 2 = _jt-assert

    8 S" absent" S" {}" _jt-out 2048 JRPC-BUILD-REQUEST
    DROP _jt-out-u !
    _jt-out _jt-out-u @ _jt-msg JRPC-PARSE 0= _jt-assert
    _jt-msg _jt-disp @ JRPC-DISPATCH
    JRPC-E-METHOD-NOT-FOUND = _jt-assert

    9 S" boom" S" {}" _jt-out 2048 JRPC-BUILD-REQUEST
    DROP _jt-out-u !
    _jt-out _jt-out-u @ _jt-msg JRPC-PARSE 0= _jt-assert
    _jt-msg _jt-disp @ JRPC-DISPATCH JRPC-E-INTERNAL = _jt-assert
    _jt-disp @ JRPC-DISPATCHER-FREE
    _jt-stack

    _jt-fails @ 0= IF
        ." JSONRPC PASS"
    ELSE
        ." JSONRPC FAIL " _jt-fails @ .
    THEN CR ;

_jt-run
""",
        ready_markers=("JSONRPC PASS",),
        stable_markers=("JSONRPC PASS",),
    ),
    "agent": Profile(
        roots=(
            "agent/event.f",
            "agent/provider.f",
            "agent/conversation.f",
            "agent/runtime.f",
            "agent/providers/offline.f",
            "agent/providers/devtools/scripted.f",
        ),
        resources=(),
        autoexec=r"""\ autoexec.f - provider-neutral agent runtime
ENTER-USERLAND
." [akashic] loading agent runtime" CR
REQUIRE agent/providers/offline.f
REQUIRE agent/providers/devtools/scripted.f
REQUIRE agent/runtime.f

VARIABLE _at-fails
VARIABLE _at-check
: _at-assert  ( flag -- )
    1 _at-check +!
    0= IF 1 _at-fails +! ." ASSERT " _at-check @ . CR THEN ;

VARIABLE _at-provider
VARIABLE _at-source
VARIABLE _at-runtime
VARIABLE _at-offline-provider
VARIABLE _at-offline-runtime
VARIABLE _at-conv
VARIABLE _at-registry
VARIABLE _at-instance
VARIABLE _at-bus
VARIABLE _at-gateway
VARIABLE _at-authority
VARIABLE _at-tool-value
VARIABLE _at-stack-depth

CREATE _at-component COMP-DESC ALLOT
CREATE _at-capability CAP-DESC ALLOT
CREATE _at-policy CPOLICY-SIZE ALLOT

: _at-tool-handler  ( request instance -- status )
    DROP
    DUP CBR.ARGS CV-LEN@ _at-tool-value !
    1 OVER CBR.RESULT CV-INT!
    DROP CBUS-S-OK ;

: _at-tool-setup  ( -- )
    _at-component COMP-DESC-INIT
    S" org.akashic.test.agent-tools"
    _at-component COMP.ID-U ! _at-component COMP.ID-A !
    S" 1.0.0"
    _at-component COMP.VERSION-U ! _at-component COMP.VERSION-A !
    8 _at-component COMP.STATE-SIZE !
    _at-capability CAP-DESC-INIT
    CAP-K-COMMAND _at-capability CAP.KIND !
    S" daybook.task.capture"
    _at-capability CAP.ID-U ! _at-capability CAP.ID-A !
    CAP-E-MUTATE CAP-E-PERSIST OR _at-capability CAP.EFFECTS !
    ['] _at-tool-handler _at-capability CAP.HANDLER-XT !
    _at-capability _at-component COMP.CAPS-A !
    1 _at-component COMP.CAPS-N !
    _at-policy CPOLICY-INIT ;

: _at-pump  ( count -- )
    0 ?DO 8 _at-runtime @ ARUNTIME-PUMP DROP LOOP ;

: _at-stack-clean  ( -- )
    DEPTH DUP _at-stack-depth @ <> IF
        ." STACK DEPTH " _at-stack-depth @ . ." -> " DUP . CR
    THEN
    _at-stack-depth @ = _at-assert ;

: _at-run  ( -- )
    0 _at-fails ! 0 _at-check !
    DEPTH _at-stack-depth !
    OFFLINE-PROVIDER-NEW DUP 0= _at-assert DROP _at-offline-provider !
    _at-offline-provider @ ARUNTIME-NEW
    DUP 0= _at-assert DROP _at-offline-runtime !
    _at-offline-runtime @ ARUNTIME.STATUS @ ARUN-S-OFFLINE = _at-assert
    _at-offline-runtime @ ARUNTIME-FREE
    _at-offline-provider @ APROV-FREE
    _at-stack-clean
    SCRIPTED-SOURCE-NEW DUP 0= _at-assert DROP _at-source !
    _at-source @ APSOURCE-PROVIDER-NEW
    DUP 0= _at-assert DROP _at-provider !
    _at-provider @ DUP APROV.ID-A @ SWAP APROV.ID-U @
    S" org.akashic.agent.testing.scripted" STR-STR= _at-assert
    _at-provider @ ARUNTIME-NEW DUP 0= _at-assert DROP _at-runtime !
    _at-stack-clean
    2 _at-pump
    _at-stack-clean
    _at-runtime @ ARUNTIME.STATUS @ ARUN-S-IDLE = _at-assert
    S" hello runtime" _at-runtime @ ARUNTIME-SEND 0= _at-assert
    _at-stack-clean
    6 _at-pump
    _at-stack-clean
    _at-runtime @ ARUNTIME.STATUS @ ARUN-S-IDLE = _at-assert
    _at-runtime @ ARUNTIME.CONVERSATION @ DUP _at-conv !
    ACONV.COUNT @ 2 = _at-assert
    _at-runtime @ ARUNTIME-MODEL-CONTEXT ACTX.COUNT @ 2 = _at-assert
    1 _at-conv @ ACONV-NTH AMSG-TEXT
    S" hello runtime" STR-STR-CONTAINS _at-assert
    _at-stack-clean

    S" request approval" _at-runtime @ ARUNTIME-SEND 0= _at-assert
    _at-provider @ SCRIPTED-LAST-CONTEXT-N 2 = _at-assert
    4 _at-pump
    _at-stack-clean
    _at-runtime @ ARUNTIME.STATUS @ ARUN-S-APPROVAL = _at-assert
    -1 _at-runtime @ ARUNTIME-RESOLVE 0= _at-assert
    2 _at-pump
    _at-stack-clean
    _at-runtime @ ARUNTIME.STATUS @ ARUN-S-IDLE = _at-assert
    _at-runtime @ ARUNTIME-MODEL-CONTEXT ACTX.COUNT @ 4 = _at-assert

    _at-tool-setup
    _at-stack-clean
    CREG-NEW DUP 0= _at-assert DROP _at-registry !
    _at-component _at-registry @ CREG-TYPE+ 0= _at-assert
    _at-component CINST-NEW DUP 0= _at-assert DROP _at-instance !
    _at-instance @ _at-registry @ CREG-INST+ 0= _at-assert
    _at-registry @ _at-policy CBUS-NEW
    DUP 0= _at-assert DROP _at-bus !
    77 305419896 AHT-NEW DUP 0= _at-assert DROP _at-authority !
    _at-authority @ _at-bus @ CBUS-AUTHORITY!
    _at-registry @ _at-bus @ _at-instance @ ATOOLG-NEW
    DUP 0= _at-assert DROP _at-gateway !
    _at-gateway @ _at-runtime @ ARUNTIME-TOOL-GATEWAY!
    _at-gateway @ _at-provider @ APROV-BIND-TOOLS 0= _at-assert
    _at-stack-clean

    S" task gateway test" _at-runtime @ ARUNTIME-SEND 0= _at-assert
    _at-provider @ SCRIPTED-LAST-CONTEXT-N 4 = _at-assert
    4 0 DO 1 _at-pump _at-stack-clean LOOP
    _at-gateway @ ATOOLG.STATE @ ATOOLG-S-QUEUED = _at-assert
    _at-stack-clean
    8 _at-bus @ CBUS-PUMP 1 = _at-assert
    _at-stack-clean
    1 _at-pump
    _at-runtime @ ARUNTIME.STATUS @ ARUN-S-APPROVAL = _at-assert
    _at-stack-clean
    -1 _at-runtime @ ARUNTIME-RESOLVE 0= _at-assert
    _at-stack-clean
    _at-gateway @ ATOOLG.STATE @ ATOOLG-S-QUEUED = _at-assert
    8 _at-bus @ CBUS-PUMP 1 = _at-assert
    2 _at-pump
    _at-stack-clean
    _at-runtime @ ARUNTIME.STATUS @ ARUN-S-IDLE = _at-assert
    _at-tool-value @ 17 = _at-assert
    _at-runtime @ ARUNTIME.CONVERSATION @ DUP _at-conv !
    ACONV.COUNT @ 0> _at-assert
    _at-conv @ ACONV.COUNT @ 1- _at-conv @ ACONV-NTH AMSG-TEXT
    S" Daybook task captured." STR-STR-CONTAINS _at-assert
    _at-runtime @ ARUNTIME-MODEL-CONTEXT ACTX.COUNT @ 8 = _at-assert

    S" cancel this" _at-runtime @ ARUNTIME-SEND 0= _at-assert
    _at-provider @ SCRIPTED-LAST-CONTEXT-N 8 = _at-assert
    _at-runtime @ ARUNTIME-CANCEL 0= _at-assert
    2 _at-pump
    _at-runtime @ ARUNTIME.STATUS @ ARUN-S-CANCELLED = _at-assert
    _at-runtime @ ARUNTIME-MODEL-CONTEXT ACTX.COUNT @ 8 = _at-assert

    _at-runtime @ ARUNTIME-FREE
    _at-provider @ APROV-FREE
    _at-source @ APSOURCE-FREE
    _at-gateway @ ATOOLG-FREE
    _at-bus @ CBUS-FREE
    _at-authority @ AHT-FREE
    _at-instance @ _at-registry @ CREG-INST- DROP
    _at-registry @ CREG-FREE
    _at-instance @ CINST-FREE
    _at-fails @ 0= IF
        ." AGENT RUNTIME PASS"
    ELSE
        ." AGENT RUNTIME FAIL " _at-fails @ .
    THEN CR ;

_at-run
""",
        ready_markers=("AGENT RUNTIME PASS",),
        stable_markers=("AGENT RUNTIME PASS",),
    ),
    "practice-contracts": Profile(
        roots=(
            "runtime/context.f",
            "runtime/practice-head.f",
            "runtime/vfs-practice-head.f",
            "runtime/practice-activation.f",
            "interop/mandate.f",
            "interop/capability-facet.f",
            "interop/authority.f",
            "interop/practice-turn.f",
            "interop/request-bus.f",
            "agent/mandate-run.f",
        ),
        resources=(),
        autoexec=r"""\ autoexec.f - Practice authority and Turn contracts
ENTER-USERLAND
." [akashic] loading Practice contracts" CR
REQUIRE runtime/context.f
REQUIRE runtime/practice-head.f
REQUIRE runtime/vfs-practice-head.f
REQUIRE runtime/practice-activation.f
REQUIRE interop/mandate.f
REQUIRE interop/capability-facet.f
REQUIRE interop/authority.f
REQUIRE interop/practice-turn.f
REQUIRE interop/request-bus.f
REQUIRE agent/mandate-run.f

VARIABLE _pc-fails
VARIABLE _pc-checks
VARIABLE _pc-depth
: _pc-assert  ( flag -- )
    1 _pc-checks +!
    0= IF 1 _pc-fails +! ." ASSERT " _pc-checks @ . CR THEN ;
: _pc-stack  ( -- )
    DEPTH DUP _pc-depth @ <> IF
        ." STACK " _pc-depth @ . ." -> " DUP . CR .S CR
    THEN
    _pc-depth @ = _pc-assert ;

: _pc-id!  ( value id -- )
    DUP RID-CLEAR ! ;

CREATE _pc-head PHEAD-SIZE ALLOT
VARIABLE _pc-context
VARIABLE _pc-child
CREATE _pc-mandate MAND-SIZE ALLOT
CREATE _pc-run-mandate MAND-SIZE ALLOT
CREATE _pc-facet CFACET-SIZE ALLOT
VARIABLE _pc-run-child
VARIABLE _pc-amrun
VARIABLE _pc-fentry
CREATE _pc-turn PTURN-SIZE ALLOT
CREATE _pc-binding AUTH-BINDING-SIZE ALLOT
CREATE _pc-grant AUTH-GRANT-SIZE ALLOT
CREATE _pc-handle INVOCATION-HANDLE-SIZE ALLOT
CREATE _pc-handle2 INVOCATION-HANDLE-SIZE ALLOT
VARIABLE _pc-table

VARIABLE _pc-pvfs
VARIABLE _pc-pvfs-fd
CREATE _pc-pstore PHEADVFS-SIZE ALLOT
CREATE _pc-pstore2 PHEADVFS-SIZE ALLOT
CREATE _pc-pstore3 PHEADVFS-SIZE ALLOT
CREATE _pc-persist-head PHEAD-SIZE ALLOT
CREATE _pc-persist-out PHEAD-SIZE ALLOT
CREATE _pc-persist-bad 8 ALLOT

VARIABLE _pc-avfs
CREATE _pc-astore PHEADVFS-SIZE ALLOT
CREATE _pc-ahead PHEAD-SIZE ALLOT
CREATE _pc-aout PHEAD-SIZE ALLOT
CREATE _pc-arejected PHEAD-SIZE ALLOT
CREATE _pc-pact PACT-SIZE ALLOT
VARIABLE _pc-validator-reject
VARIABLE _pc-first-epoch

: _pc-semantic-validator  ( head data -- status )
    @ DUP -1 = IF 2DROP 91 EXIT THEN
    SWAP PHEAD.REVISION @ = IF 91 ELSE PHEADVFS-S-OK THEN ;

: _pc-activation-run  ( -- )
    524288 A-XMEM ARENA-NEW DUP 0= _pc-assert DROP
    VFS-RAM-VTABLE VFS-NEW DUP _pc-avfs ! VFS-USE
    _pc-ahead PHEAD-INIT
    31 _pc-ahead PHEAD.ID _pc-id!
    41 _pc-ahead PHEAD.CURRENT-ROOT _pc-id!
    _pc-avfs @ _pc-astore PHEADVFS-INIT
        PHEADVFS-S-OK = _pc-assert
    _pc-ahead _pc-astore PHEADVFS-SAVE
        PHEADVFS-S-OK = _pc-assert
    2 _pc-ahead PHEAD.REVISION !
    42 _pc-ahead PHEAD.CURRENT-ROOT _pc-id!
    _pc-ahead _pc-astore PHEADVFS-SAVE
        PHEADVFS-S-OK = _pc-assert

    2 _pc-validator-reject !
    _pc-aout _pc-arejected ['] _pc-semantic-validator
        _pc-validator-reject _pc-astore PHEADVFS-LOAD-VALIDATED
        PHEADVFS-S-OK = _pc-assert
    _pc-astore PHEADVFS-FALLBACK? _pc-assert
    _pc-astore PHEADVFS.GENERATION @ 1 = _pc-assert
    _pc-astore PHEADVFS.REJECTED-GENERATION @ 2 = _pc-assert
    _pc-astore PHEADVFS.REJECTED-STATUS @ 91 = _pc-assert
    _pc-aout PHEAD.REVISION @ 1 = _pc-assert
    _pc-aout PHEAD.CURRENT-ROOT @ 41 = _pc-assert
    _pc-arejected PHEAD.REVISION @ 2 = _pc-assert
    _pc-arejected PHEAD.CURRENT-ROOT @ 42 = _pc-assert

    _pc-pact PACT-INIT
    ['] _pc-semantic-validator _pc-validator-reject
        PACT-TRUST-STRUCTURAL _pc-pact PACT-VALIDATOR!
        PACT-S-OK = _pc-assert
    _pc-avfs @ _pc-pact PACT-ACTIVATE PACT-S-OK = _pc-assert
    _pc-pact PACT-ACTIVE? _pc-assert
    _pc-pact PACT-FALLBACK? _pc-assert
    _pc-pact PACT-RECOVERY? 0= _pc-assert
    _pc-pact PACT-READONLY? 0= _pc-assert
    _pc-pact PACT-AUTHENTICATED? 0= _pc-assert
    _pc-pact PACT-HEAD PHEAD.REVISION @ 1 = _pc-assert
    _pc-pact PACT-REJECTED-HEAD PHEAD.REVISION @ 2 = _pc-assert
    _pc-pact PACT.CONTEXT @ DUP CTX-VALID? _pc-assert
    DUP CTX.EPOCH @ _pc-pact PACT.EPOCH @ = _pc-assert
    DUP CTX.PRACTICE @ _pc-pact PACT-HEAD = _pc-assert
    CTX.VFS @ _pc-avfs @ = _pc-assert
    _pc-pact PACT.EPOCH @ DUP 0> _pc-assert _pc-first-epoch !
    _pc-pact PACT-DEACTIVATE
    _pc-avfs @ _pc-pact PACT-ACTIVATE PACT-S-OK = _pc-assert
    _pc-pact PACT.EPOCH @ DUP 0> _pc-assert
    _pc-first-epoch @ <> _pc-assert
    _pc-pact PACT-DEACTIVATE

    -1 _pc-validator-reject !
    _pc-avfs @ _pc-pact PACT-ACTIVATE
        PACT-S-RECOVERY = _pc-assert
    _pc-pact PACT-ACTIVE? _pc-assert
    _pc-pact PACT-RECOVERY? _pc-assert
    _pc-pact PACT-FALLBACK? 0= _pc-assert
    _pc-pact PACT-READONLY? _pc-assert
    _pc-pact PACT-AUTHENTICATED? 0= _pc-assert
    _pc-pact PACT.CONTEXT @ CTX.FLAGS @
        CTX-F-ACTIVE CTX-F-READONLY OR CTX-F-RECOVERY OR = _pc-assert
    _pc-avfs @ V.FLAGS @ VFS-F-RO AND 0<> _pc-assert
    _pc-pact PACT.REJECTED-GENERATION @ 2 = _pc-assert
    _pc-pact PACT-REJECTED-HEAD PHEAD.REVISION @ 2 = _pc-assert
    _pc-pact PACT-DEACTIVATE
    _pc-avfs @ VFS-DESTROY ;

: _pc-persist-corrupt  ( path-a path-u -- )
    _pc-pvfs @ VFS-USE VFS-OPEN DUP _pc-pvfs-fd ! 0<> _pc-assert
    _pc-persist-bad 8 88 FILL _pc-pvfs-fd @ VFS-REWIND
    _pc-persist-bad 8 _pc-pvfs-fd @ VFS-WRITE 8 = _pc-assert
    _pc-pvfs-fd @ VFS-CLOSE ;

: _pc-persist-run  ( -- )
    524288 A-XMEM ARENA-NEW DUP 0= _pc-assert DROP
    VFS-RAM-VTABLE VFS-NEW DUP _pc-pvfs ! VFS-USE
    _pc-persist-head PHEAD-INIT
    11 _pc-persist-head PHEAD.ID _pc-id!
    22 _pc-persist-head PHEAD.CURRENT-ROOT _pc-id!
    _pc-pvfs @ _pc-pstore PHEADVFS-INIT
        PHEADVFS-S-OK = _pc-assert
    _pc-persist-head _pc-pstore PHEADVFS-SAVE
        PHEADVFS-S-OK = _pc-assert
    _pc-pstore PHEADVFS.GENERATION @ 1 = _pc-assert
    _pc-pstore PHEADVFS.ACTIVE-SLOT @ 0= _pc-assert
    _pc-pstore PHEADVFS-FALLBACK? _pc-assert
    2 _pc-persist-head PHEAD.REVISION !
    _pc-persist-head _pc-pstore PHEADVFS-SAVE
        PHEADVFS-S-OK = _pc-assert
    _pc-pstore PHEADVFS.GENERATION @ 2 = _pc-assert
    _pc-pstore PHEADVFS.ACTIVE-SLOT @ 1 = _pc-assert
    _pc-pstore PHEADVFS-FALLBACK? 0= _pc-assert
    _pc-pvfs @ _pc-pstore2 PHEADVFS-INIT
        PHEADVFS-S-OK = _pc-assert
    _pc-persist-out _pc-pstore2 PHEADVFS-LOAD
        PHEADVFS-S-OK = _pc-assert
    _pc-pstore2 PHEADVFS.GENERATION @ 2 = _pc-assert
    _pc-persist-out PHEAD.REVISION @ 2 = _pc-assert
    S" /practice-head-b.bin" _pc-persist-corrupt
    _pc-pvfs @ _pc-pstore3 PHEADVFS-INIT
        PHEADVFS-S-OK = _pc-assert
    _pc-persist-out _pc-pstore3 PHEADVFS-LOAD
        PHEADVFS-S-OK = _pc-assert
    _pc-pstore3 PHEADVFS-FALLBACK? _pc-assert
    _pc-pstore3 PHEADVFS.GENERATION @ 1 = _pc-assert
    S" /practice-head-a.bin" _pc-persist-corrupt
    _pc-persist-out _pc-pstore3 PHEADVFS-LOAD
        PHEADVFS-S-RECOVERY = _pc-assert
    _pc-pstore3 PHEADVFS-READONLY? _pc-assert
    _pc-pstore3 PHEADVFS-RECOVERY? _pc-assert
    _pc-persist-head _pc-pstore3 PHEADVFS-SAVE
        PHEADVFS-S-READONLY = _pc-assert
    _pc-persist-head _pc-pstore3 PHEADVFS-REINITIALIZE
        PHEADVFS-S-OK = _pc-assert
    _pc-pstore3 PHEADVFS.GENERATION @ 2 = _pc-assert
    _pc-pstore3 PHEADVFS-FALLBACK? 0= _pc-assert
    _pc-pvfs @ _pc-pstore2 PHEADVFS-INIT
        PHEADVFS-S-OK = _pc-assert
    _pc-persist-out _pc-pstore2 PHEADVFS-LOAD
        PHEADVFS-S-OK = _pc-assert
    _pc-pstore2 PHEADVFS.GENERATION @ 2 = _pc-assert
    _pc-persist-out PHEAD.REVISION @ 2 = _pc-assert
    _pc-pvfs @ VFS-DESTROY ;

: _pc-binding-setup  ( -- )
    _pc-binding ABIND-INIT
    77 _pc-binding ABIND.EPOCH !
    CPRINC-AGENT _pc-binding ABIND.PRINCIPAL !
    11 _pc-binding ABIND.CONTEXT-ID !
    2 _pc-binding ABIND.CONTEXT-GEN !
    31 _pc-binding ABIND.TARGET-ID !
    7 _pc-binding ABIND.TARGET-GEN !
    CAP-E-MUTATE CAP-E-PERSIST OR _pc-binding ABIND.EFFECTS !
    9 _pc-binding ABIND.EXPECT-REV !
    S" practice.test.mutate" _pc-binding ABIND-OP! AUTH-S-OK = _pc-assert
    101 _pc-binding ABIND.INVOCATION-ID _pc-id!
    102 _pc-binding ABIND.PRACTICE-ID _pc-id!
    103 _pc-binding ABIND.MANDATE-ID _pc-id! ;

: _pc-grant-setup  ( -- )
    _pc-grant AGR-INIT
    _pc-binding _pc-grant AGR-BIND! AUTH-S-OK = _pc-assert
    AGR-F-REVIEWED-COMMIT _pc-grant AGR.FLAGS !
    MS@ 10000 + _pc-grant AGR.EXPIRES ! ;

CREATE _pc-cap CAP-DESC ALLOT
CREATE _pc-comp COMP-DESC ALLOT
VARIABLE _pc-inst
VARIABLE _pc-registry
VARIABLE _pc-bus
VARIABLE _pc-request
VARIABLE _pc-applied

: _pc-handler  ( request instance -- status )
    2DROP 1 _pc-applied +! CBUS-S-OK ;

: _pc-runtime-setup  ( -- )
    _pc-cap CAP-DESC-INIT
    CAP-K-COMMAND _pc-cap CAP.KIND !
    S" practice.test.mutate" _pc-cap CAP.ID-U ! _pc-cap CAP.ID-A !
    CAP-E-MUTATE CAP-E-PERSIST OR _pc-cap CAP.EFFECTS !
    ['] _pc-handler _pc-cap CAP.HANDLER-XT !
    _pc-comp COMP-DESC-INIT
    S" org.akashic.practice-test"
        _pc-comp COMP.ID-U ! _pc-comp COMP.ID-A !
    S" 1.0.0" _pc-comp COMP.VERSION-U ! _pc-comp COMP.VERSION-A !
    _pc-cap _pc-comp COMP.CAPS-A ! 1 _pc-comp COMP.CAPS-N !
    _pc-comp CINST-NEW DUP 0= _pc-assert DROP _pc-inst !
    CREG-NEW DUP 0= _pc-assert DROP _pc-registry !
    _pc-comp _pc-registry @ CREG-TYPE+ 0= _pc-assert
    _pc-inst @ _pc-registry @ CREG-INST+ 0= _pc-assert
    _pc-registry @ 0 CBUS-NEW DUP 0= _pc-assert DROP _pc-bus !
    _pc-table @ _pc-bus @ CBUS-AUTHORITY!
    CBR-NEW DUP 0= _pc-assert DROP _pc-request !
    CPRINC-AGENT _pc-request @ CBR.PRINCIPAL !
    77 _pc-request @ CBR.EPOCH !
    11 _pc-request @ CBR.CONTEXT-ID !
    2 _pc-request @ CBR.CONTEXT-GEN !
    _pc-inst @ CINST.ID @ _pc-request @ CBR.TARGET-ID !
    _pc-inst @ CINST.GENERATION @ _pc-request @ CBR.TARGET-GEN !
    _pc-inst @ CINST.REVISION @ _pc-request @ CBR.EXPECT-REV !
    _pc-cap _pc-request @ CBR.CAP !
    201 _pc-request @ CBR.INVOCATION-ID _pc-id!
    202 _pc-request @ CBR.PRACTICE-ID _pc-id!
    203 _pc-request @ CBR.MANDATE-ID _pc-id! ;

: _pc-run  ( -- )
    0 _pc-fails ! 0 _pc-checks ! 0 _pc-applied ! DEPTH _pc-depth !

    _pc-head PHEAD-INIT
    1 _pc-head PHEAD.ID _pc-id!
    2 _pc-head PHEAD.CURRENT-ROOT _pc-id!
    _pc-head PHEAD-VALID? _pc-assert
    0 _pc-head PHEAD.FORMAT !
    _pc-head PHEAD-VALID? 0= _pc-assert
    PHEAD-FORMAT-V1 _pc-head PHEAD.FORMAT !

    77 CTX-NEW DUP 0= _pc-assert DROP DUP _pc-context ! DROP
    _pc-head _pc-context @ CTX.PRACTICE !
    9 _pc-context @ CTX.AUTHORITY !
    10 _pc-context @ CTX.VFS !
    CTX-F-READONLY _pc-context @ CTX.FLAGS !
    _pc-context @ CTX-CHILD-NEW DUP 0= _pc-assert DROP
        DUP _pc-child ! DROP
    _pc-child @ CTX.AUTHORITY @ 0= _pc-assert
    _pc-child @ CTX.VFS @ 0= _pc-assert
    _pc-child @ CTX-READONLY? _pc-assert
    _pc-stack

    _pc-mandate MAND-INIT
    3 _pc-mandate MAND.ID _pc-id!
    77 _pc-mandate MAND.ACTIVATION-EPOCH !
    CPRINC-AGENT _pc-mandate MAND.PRINCIPAL !
    11 _pc-mandate MAND.CONTEXT-ID !
    2 _pc-mandate MAND.CONTEXT-GENERATION !
    6 _pc-mandate MAND.PRACTICE-ID _pc-id!
    7 _pc-mandate MAND.INPUT-FACET-ID _pc-id!
    8 _pc-mandate MAND.DISCLOSURE-FACET-ID _pc-id!
    CAP-E-MUTATE CAP-E-PERSIST OR _pc-mandate MAND.EFFECTS !
    MAND-D-PROPOSAL _pc-mandate MAND.DISPOSITION !
    _pc-mandate MAND-STRUCTURAL-VALID? _pc-assert
    CAP-E-MUTATE 77 MS@ _pc-mandate MAND-COMMIT-VALID? 0= _pc-assert
    MAND-D-COMMIT _pc-mandate MAND.DISPOSITION !
    CAP-E-MUTATE 77 MS@ _pc-mandate MAND-COMMIT-VALID? _pc-assert

    _pc-turn PTURN-INIT
    4 _pc-turn PTURN.INVOCATION-ID _pc-id!
    77 _pc-turn PTURN.ACTIVATION-EPOCH !
    11 _pc-turn PTURN.CONTEXT-ID ! 2 _pc-turn PTURN.CONTEXT-GENERATION !
    31 _pc-turn PTURN.TARGET-ID ! 7 _pc-turn PTURN.TARGET-GENERATION !
    S" practice.test.mutate" _pc-turn PTURN-OP! _pc-assert
    9 _pc-turn PTURN.EXPECTED-REVISION !
    CAP-E-MUTATE _pc-turn PTURN.EFFECTS !
    5 _pc-turn PTURN.GRANT-ID _pc-id!
    _pc-turn PTURN-STRUCTURAL-VALID? _pc-assert
    8 MS@ _pc-turn PTURN-BEGIN 0= _pc-assert
    9 MS@ _pc-turn PTURN-BEGIN _pc-assert
    MAND-D-PROPOSAL _pc-mandate MAND.DISPOSITION !
    _pc-mandate 77 MS@ _pc-turn PTURN-COMMIT-VALID? 0= _pc-assert
    MAND-D-COMMIT _pc-mandate MAND.DISPOSITION !
    10 _pc-mandate 77 MS@ _pc-turn PTURN-COMMIT _pc-assert
    _pc-turn PTURN.STATE @ PTURN-S-COMMITTED = _pc-assert
    _pc-stack

    _pc-context @ CTX-CHILD-NEW DUP 0= _pc-assert DROP
        DUP _pc-run-child ! DROP
    _pc-facet CFACET-INIT
    7 _pc-facet CFACET.ID _pc-id!
    1 _pc-facet CFACET.PRACTICE-ID _pc-id!
    77 _pc-facet CFACET.EPOCH !
    _pc-run-child @ CTX.ID @ _pc-facet CFACET.CONTEXT-ID !
    _pc-run-child @ CTX.GENERATION @ _pc-facet CFACET.CONTEXT-GEN !
    1 _pc-facet CFACET.REVISION !
    31 7 CAP-E-MUTATE CAP-E-PERSIST OR
    CFENTRY-F-VISIBLE CFENTRY-F-INVOKE OR
        CFENTRY-F-REVIEW-COMMIT OR CFENTRY-F-DISCLOSE-RESULT OR
    64 S" practice.test.mutate" _pc-facet CFACET-ADD
        CFACET-S-OK = _pc-assert
    _pc-stack
    _pc-facet CFACET-VALID? _pc-assert
    _pc-stack
    31 8 S" practice.test.mutate" _pc-facet CFACET-FIND
        0= _pc-assert
    31 7 S" practice.test.mutate" _pc-facet CFACET-FIND
        DUP 0<> _pc-assert _pc-fentry !
    _pc-stack

    _pc-run-mandate MAND-INIT
    9 _pc-run-mandate MAND.ID _pc-id!
    1 _pc-run-mandate MAND.PRACTICE-ID _pc-id!
    7 _pc-run-mandate MAND.INPUT-FACET-ID _pc-id!
    7 _pc-run-mandate MAND.DISCLOSURE-FACET-ID _pc-id!
    77 _pc-run-mandate MAND.ACTIVATION-EPOCH !
    CPRINC-AGENT _pc-run-mandate MAND.PRINCIPAL !
    _pc-run-child @ CTX.ID @ _pc-run-mandate MAND.CONTEXT-ID !
    _pc-run-child @ CTX.GENERATION @
        _pc-run-mandate MAND.CONTEXT-GENERATION !
    CAP-E-MUTATE CAP-E-PERSIST OR _pc-run-mandate MAND.EFFECTS !
    MAND-D-PROPOSAL _pc-run-mandate MAND.DISPOSITION !
    10000 _pc-run-mandate MAND.TIME-BUDGET-MS !
    2 _pc-run-mandate MAND.TOOL-BUDGET !
    128 _pc-run-mandate MAND.DISCLOSURE-BUDGET !
    _pc-head _pc-run-child @ _pc-run-mandate _pc-facet AMRUN-NEW
        DUP 0= _pc-assert DROP DUP _pc-amrun ! DROP
    _pc-amrun @ AMRUN-ACTIVE? _pc-assert
    _pc-stack
    _pc-amrun @ AMRUN-TOOL-RESERVE AMRUN-S-OK = _pc-assert
    _pc-amrun @ AMRUN-TOOL-RESERVE AMRUN-S-OK = _pc-assert
    _pc-amrun @ AMRUN-TOOL-RESERVE AMRUN-S-BUDGET = _pc-assert
    64 _pc-fentry @ _pc-amrun @ AMRUN-DISCLOSE-RESERVE
        AMRUN-S-OK = _pc-assert
    64 _pc-fentry @ _pc-amrun @ AMRUN-DISCLOSE-RESERVE
        AMRUN-S-OK = _pc-assert
    1 _pc-fentry @ _pc-amrun @ AMRUN-DISCLOSE-RESERVE
        AMRUN-S-BUDGET = _pc-assert
    _pc-amrun @ AMRUN-FREE
    _pc-stack

    _pc-binding-setup _pc-grant-setup
    77 305419896 AHT-NEW DUP 0= _pc-assert DROP _pc-table !
    _pc-grant _pc-handle _pc-table @ AHT-ISSUE AUTH-S-OK = _pc-assert
    _pc-handle IH.SEAL DUP C@ 1 XOR SWAP C!
    MS@ _pc-binding _pc-handle _pc-table @ AHT-RESOLVE
    AUTH-S-STALE-HANDLE = _pc-assert DROP
    _pc-handle IH.SEAL DUP C@ 1 XOR SWAP C!
    MS@ _pc-binding _pc-handle _pc-table @ AHT-RESOLVE
    DUP AUTH-S-OK = _pc-assert DROP DUP 0<> _pc-assert DROP
    32 _pc-binding ABIND.TARGET-ID !
    MS@ _pc-binding _pc-handle _pc-table @ AHT-RESOLVE
    AUTH-S-MISMATCH = _pc-assert DROP
    31 _pc-binding ABIND.TARGET-ID !
    8 _pc-binding ABIND.TARGET-GEN !
    MS@ _pc-binding _pc-handle _pc-table @ AHT-RESOLVE
    AUTH-S-MISMATCH = _pc-assert DROP
    7 _pc-binding ABIND.TARGET-GEN !
    MS@ _pc-binding _pc-handle _pc-table @ AHT-CONSUME
    AUTH-S-OK = _pc-assert DROP
    MS@ _pc-binding _pc-handle _pc-table @ AHT-CONSUME
    AUTH-S-CONSUMED = _pc-assert DROP

    _pc-grant-setup
    _pc-grant _pc-handle2 _pc-table @ AHT-ISSUE AUTH-S-OK = _pc-assert
    _pc-handle2 _pc-table @ AHT-REVOKE AUTH-S-OK = _pc-assert
    MS@ _pc-binding _pc-handle2 _pc-table @ AHT-RESOLVE
    AUTH-S-REVOKED = _pc-assert DROP
    _pc-grant-setup
    MS@ 1- _pc-grant AGR.EXPIRES !
    _pc-grant _pc-handle2 _pc-table @ AHT-ISSUE AUTH-S-OK = _pc-assert
    MS@ _pc-binding _pc-handle2 _pc-table @ AHT-RESOLVE
    AUTH-S-EXPIRED = _pc-assert DROP
    78 2271560481 _pc-table @ AHT-RESET
    MS@ _pc-binding _pc-handle _pc-table @ AHT-RESOLVE
    AUTH-S-STALE-HANDLE = _pc-assert DROP
    _pc-stack

    77 305419896 _pc-table @ AHT-RESET
    _pc-runtime-setup
    _pc-request @ _pc-bus @ CBUS-DISPATCH
        CBUS-S-NEEDS-APPROVAL = _pc-assert
    _pc-applied @ 0= _pc-assert
    _pc-request @ _pc-binding CBR-AUTH-BIND! AUTH-S-OK = _pc-assert
    _pc-grant AGR-INIT
    _pc-binding _pc-grant AGR-BIND! AUTH-S-OK = _pc-assert
    AGR-F-MANDATE-AUTO _pc-grant AGR.FLAGS !
    MS@ 10000 + _pc-grant AGR.EXPIRES !
    _pc-grant _pc-request @ CBR.HANDLE _pc-table @ AHT-ISSUE
        AUTH-S-OK = _pc-assert
    _pc-request @ _pc-bus @ CBUS-DISPATCH
        CBUS-S-DENIED = _pc-assert
    _pc-applied @ 0= _pc-assert
    _pc-request @ CBR.HANDLE IH-INIT
    _pc-grant AGR-INIT
    _pc-binding _pc-grant AGR-BIND! AUTH-S-OK = _pc-assert
    AGR-F-REVIEWED-COMMIT _pc-grant AGR.FLAGS !
    MS@ 10000 + _pc-grant AGR.EXPIRES !
    _pc-grant _pc-request @ CBR.HANDLE _pc-table @ AHT-ISSUE
        AUTH-S-OK = _pc-assert
    _pc-request @ _pc-bus @ CBUS-DISPATCH CBUS-S-OK = _pc-assert
    _pc-applied @ 1 = _pc-assert
    _pc-inst @ CINST.REVISION @ 2 = _pc-assert
    _pc-request @ CBR.TURN @ PTURN.STATE @
        PTURN-S-COMMITTED = _pc-assert
    _pc-request @ CBR.TURN @ PTURN.OBSERVED-REVISION @ 1 = _pc-assert
    _pc-request @ CBR.TURN @ PTURN.COMMITTED-REVISION @ 2 = _pc-assert
    _pc-request @ CBR.TURN @ PTURN.GRANT-ID RID-PRESENT? _pc-assert
    2 _pc-request @ CBR.EXPECT-REV !
    _pc-request @ _pc-bus @ CBUS-DISPATCH
        CBUS-S-CONSUMED-AUTHORITY = _pc-assert
    _pc-applied @ 1 = _pc-assert
    _pc-request @ CBR.TURN @ PTURN.STATE @
        PTURN-S-COMMITTED = _pc-assert
    _pc-stack

    _pc-request @ CBR-FREE
    _pc-bus @ CBUS-FREE
    _pc-inst @ _pc-registry @ CREG-INST- DROP
    _pc-registry @ CREG-FREE
    _pc-inst @ CINST-FREE
    _pc-table @ AHT-FREE
    _pc-child @ CTX-FREE _pc-context @ CTX-FREE
    _pc-persist-run
    _pc-activation-run
    _pc-stack
    _pc-fails @ 0= IF
        ." PRACTICE CONTRACTS PASS " _pc-checks @ .
    ELSE
        ." PRACTICE CONTRACTS FAIL " _pc-fails @ . ." / " _pc-checks @ .
    THEN CR ;

_pc-run
""",
        ready_markers=("PRACTICE CONTRACTS PASS",),
        stable_markers=("PRACTICE CONTRACTS PASS",),
    ),
    "resource-contracts": Profile(
        roots=(
            "runtime/resource-ref.f",
            "runtime/resource-registry.f",
            "interop/resource.f",
            "interop/lens-binding.f",
        ),
        resources=(),
        autoexec=r"""\ autoexec.f - resource/lens substrate contracts
ENTER-USERLAND
." [akashic] loading resource contracts" CR
REQUIRE runtime/resource-ref.f
REQUIRE runtime/resource-registry.f
REQUIRE interop/resource.f
REQUIRE interop/lens-binding.f

VARIABLE _rc-fails
VARIABLE _rc-checks
VARIABLE _rc-depth

: _rc-assert  ( flag -- )
    1 _rc-checks +!
    0= IF 1 _rc-fails +! ." ASSERT " _rc-checks @ . CR THEN ;

: _rc-stack  ( -- )
    DEPTH DUP _rc-depth @ <> IF
        ." STACK " _rc-depth @ . ." -> " DUP . CR .S CR
    THEN
    _rc-depth @ = _rc-assert ;

: _rc-id!  ( value id -- )
    DUP RID-CLEAR ! ;

CREATE _rc-head PHEAD-SIZE ALLOT
CREATE _rc-resource-id RID-SIZE ALLOT
CREATE _rc-resource-id2 RID-SIZE ALLOT
CREATE _rc-seen-resource-id RID-SIZE ALLOT
CREATE _rc-ref RREF-SIZE ALLOT
CREATE _rc-ref2 RREF-SIZE ALLOT
CREATE _rc-ref3 RREF-SIZE ALLOT
CREATE _rc-bind LBIND-SIZE ALLOT
CREATE _rc-bind2 LBIND-SIZE ALLOT
CREATE _rc-value CV-SIZE ALLOT
CREATE _rc-cap CAP-DESC ALLOT
CREATE _rc-comp COMP-DESC ALLOT

VARIABLE _rc-context
VARIABLE _rc-cold-context
VARIABLE _rc-components
VARIABLE _rc-instance
VARIABLE _rc-resources
VARIABLE _rc-request
VARIABLE _rc-bus
VARIABLE _rc-cap-depth
VARIABLE _rc-handler-request
VARIABLE _rc-running-rebind
VARIABLE _rc-saw-running

: _rc-handler  ( request instance -- status )
    DROP _rc-handler-request !
    _rc-handler-request @ CBR.RESOURCE-ID
        _rc-seen-resource-id RID-COPY
    _rc-handler-request @ CBR.FLAGS @ CBR-F-RUNNING AND 0<>
        _rc-saw-running !
    _rc-bind _rc-context @ _rc-handler-request @ LBIND-REQUEST!
        _rc-running-rebind !
    CBUS-S-OK ;

: _rc-cap-setup  ( -- )
    _rc-cap CAP-DESC-INIT
    CAP-K-RESOURCE _rc-cap CAP.KIND !
    S" resource.snapshot" _rc-cap CAP.ID-U ! _rc-cap CAP.ID-A !
    CAP-E-OBSERVE _rc-cap CAP.EFFECTS !
    CAP-F-IDEMPOTENT CAP-F-NEEDS-TARGET OR _rc-cap CAP.FLAGS !
    ['] _rc-handler _rc-cap CAP.HANDLER-XT ! ;

: _rc-comp-setup  ( -- )
    _rc-comp COMP-DESC-INIT
    S" org.akashic.test.resource"
        _rc-comp COMP.ID-U ! _rc-comp COMP.ID-A !
    S" 1.0.0" _rc-comp COMP.VERSION-U ! _rc-comp COMP.VERSION-A !
    _rc-cap _rc-comp COMP.CAPS-A !
    1 _rc-comp COMP.CAPS-N ! ;

: _rc-resolve-ok  ( ref -- )
    _rc-context @ _rc-resources @ RREG-RESOLVE
    DUP RREG-S-OK = _rc-assert
    DROP _rc-instance @ = _rc-assert ;

: _rc-run  ( -- )
    0 _rc-fails ! 0 _rc-checks ! DEPTH _rc-depth !
    _rc-value CV-INIT
    _rc-head PHEAD-INIT
    11 _rc-head PHEAD.ID _rc-id!
    12 _rc-head PHEAD.CURRENT-ROOT _rc-id!
    41 _rc-resource-id _rc-id!
    42 _rc-resource-id2 _rc-id!

    _rc-ref RREF-INIT
    _rc-ref RREF-VALID? 0= _rc-assert
    _rc-resource-id _rc-ref RREF.ID RID-COPY
    1 _rc-ref RREF.REVISION !
    _rc-ref RREF-VALID? _rc-assert
    _rc-ref _rc-ref2 RREF-COPY RREF-S-OK = _rc-assert
    _rc-ref _rc-ref2 RREF= _rc-assert
    _rc-ref _rc-ref2 RREF-ID= _rc-assert
    1 _rc-ref2 RREF.FLAGS !
    _rc-ref2 RREF-VALID? 0= _rc-assert
    _rc-ref2 _rc-ref3 RREF-COPY RREF-S-INVALID = _rc-assert
    0 _rc-ref2 RREF.FLAGS !
    _rc-stack

    _rc-ref _rc-value IRES-RREF! IRES-S-OK = _rc-assert
    _rc-value _rc-ref2 IRES-RREF@ IRES-S-OK = _rc-assert
    _rc-ref _rc-ref2 RREF= _rc-assert
    0x7FFFFFFFFFFFFFFF _rc-ref RREF.REVISION !
    _rc-ref _rc-value IRES-RREF! IRES-S-OK = _rc-assert
    _rc-value CV-LEN@ IRES-RREF-URI-MAX = _rc-assert
    _rc-value _rc-ref2 IRES-RREF@ IRES-S-OK = _rc-assert
    _rc-ref _rc-ref2 RREF= _rc-assert
    1 _rc-ref RREF.REVISION !
    _rc-ref _rc-value IRES-RREF! IRES-S-OK = _rc-assert
    [CHAR] A _rc-value CV-DATA@ IRES-RREF-PREFIX-U 1+ + C!
    _rc-value _rc-ref2 IRES-RREF@ IRES-S-INVALID = _rc-assert
    _rc-ref2 RREF-VALID? 0= _rc-assert
    _rc-ref _rc-value IRES-RREF! IRES-S-OK = _rc-assert
    S" /backing-only" _rc-value IRES-VFS! 0= _rc-assert
    _rc-value _rc-ref2 IRES-RREF@ IRES-S-INVALID = _rc-assert
    S" vfs:/backing-only" IRES-VFS-PATH _rc-assert 2DROP
    0 5 IRES-VFS-PATH 0= _rc-assert 2DROP
    0 1 _rc-value IRES-VFS! IRES-S-INVALID = _rc-assert
    S" path" 0 IRES-VFS! IRES-S-INVALID = _rc-assert
    0 IRES-RREF-URI-MIN _rc-ref2 IRES-RREF-PARSE
        IRES-S-INVALID = _rc-assert
    _rc-value CV-FREE
    CV-T-RESOURCE _rc-value CV.TYPE !
    1 _rc-value CV.LEN !
    _rc-value _rc-ref2 IRES-RREF@ IRES-S-INVALID = _rc-assert
    _rc-value CV-INIT
    _rc-stack

    _rc-cap-setup _rc-comp-setup
    DEPTH _rc-cap-depth !
    _rc-cap CAP-DESC-VALID? _rc-assert
    DEPTH _rc-cap-depth @ = _rc-assert
    _rc-cap CAP.CONCURRENCY @ CCLASS-OWNER-COMMIT = _rc-assert
    _rc-cap CAP-CONCURRENCY-EFFECTIVE CCLASS-OWNER-COMMIT = _rc-assert
    CCLASS-PURE _rc-cap CAP.CONCURRENCY !
    _rc-cap CAP-DESC-VALID? _rc-assert
    _rc-cap CAP-CONCURRENCY-EFFECTIVE CCLASS-PURE = _rc-assert
    10 _rc-cap CAP.CONCURRENCY !
    _rc-cap CAP-DESC-VALID? 0= _rc-assert
    0 _rc-cap CAP.CONCURRENCY !
    0 _rc-cap CAP.ID-U !
    _rc-cap CAP-DESC-VALID? 0= _rc-assert
    DEPTH _rc-cap-depth @ = _rc-assert
    S" resource.snapshot" _rc-cap CAP.ID-U ! _rc-cap CAP.ID-A !
    128 _rc-cap CAP.FLAGS !
    _rc-cap CAP-DESC-VALID? 0= _rc-assert
    DEPTH _rc-cap-depth @ = _rc-assert
    CAP-F-IDEMPOTENT CAP-F-NEEDS-TARGET OR _rc-cap CAP.FLAGS !

    77 CTX-NEW DUP 0= _rc-assert DROP _rc-context !
    _rc-head _rc-context @ CTX.PRACTICE !
    CTX-F-ACTIVE _rc-context @ CTX.FLAGS !
    CREG-NEW DUP 0= _rc-assert DROP _rc-components !
    128 _rc-cap CAP.FLAGS !
    _rc-comp _rc-components @ CREG-TYPE+
        CREG-E-NOT-FOUND = _rc-assert
    CAP-F-IDEMPOTENT CAP-F-NEEDS-TARGET OR _rc-cap CAP.FLAGS !
    65 _rc-comp COMP.CAPS-N !
    _rc-comp _rc-components @ CREG-TYPE+
        CREG-E-NOT-FOUND = _rc-assert
    1 _rc-comp COMP.CAPS-N !
    0 _rc-comp COMP.CAPS-A !
    _rc-comp _rc-components @ CREG-TYPE+
        CREG-E-NOT-FOUND = _rc-assert
    _rc-cap _rc-comp COMP.CAPS-A !
    0x7FFFFFFFFFFFFFF0 _rc-comp COMP.CAPS-A !
    _rc-comp _rc-components @ CREG-TYPE+
        CREG-E-NOT-FOUND = _rc-assert
    _rc-cap _rc-comp COMP.CAPS-A !
    _rc-comp _rc-components @ CREG-TYPE+ 0= _rc-assert
    _rc-comp CINST-NEW DUP 0= _rc-assert DROP _rc-instance !
    _rc-instance @ _rc-components @ CREG-INST+ 0= _rc-assert
    _rc-components @ _rc-context @ RREG-NEW
        DUP 0= _rc-assert DROP _rc-resources !
    _rc-resources @ RREG-VALID? _rc-assert
    _rc-context @ _rc-resources @ RREG-CONTEXT? _rc-assert

    _rc-resource-id _rc-instance @ _rc-context @ _rc-resources @
        RREG-PUBLISH RREG-S-OK = _rc-assert
    _rc-resource-id _rc-instance @ _rc-context @ _rc-resources @
        RREG-PUBLISH RREG-S-DUPLICATE = _rc-assert
    _rc-resource-id2 _rc-instance @ _rc-context @ _rc-resources @
        RREG-PUBLISH RREG-S-DUPLICATE = _rc-assert
    _rc-resources @ RREG.COUNT @ 1 = _rc-assert
    _rc-resources @ RREG.ENTRIES
    _rc-resources @ RREG.ENTRIES RREG-ENTRY-SIZE +
        RREG-ENTRY-SIZE MOVE
    2 _rc-resources @ RREG.COUNT !
    _rc-resources @ RREG-VALID? 0= _rc-assert
    1 _rc-resources @ RREG.COUNT !
    _rc-resources @ RREG.ENTRIES RREG-ENTRY-SIZE +
        RREG-ENTRY-SIZE 0 FILL
    _rc-resource-id _rc-context @ _rc-ref2 _rc-resources @ RREG-REF
        RREG-S-OK = _rc-assert
    _rc-ref2 RREF.REVISION @ 1 = _rc-assert
    _rc-ref2 _rc-resolve-ok
    _rc-ref3 RREF-INIT
    _rc-resource-id _rc-ref3 RREF.ID RID-COPY
    _rc-ref3 _rc-resolve-ok
    2 _rc-ref2 RREF.REVISION !
    _rc-ref2 _rc-context @ _rc-resources @ RREG-RESOLVE
    DUP RREG-S-STALE-REVISION = _rc-assert
    SWAP 0= _rc-assert DROP
    78 CTX-NEW DUP 0= _rc-assert DROP _rc-cold-context !
    _rc-head _rc-cold-context @ CTX.PRACTICE !
    CTX-F-ACTIVE _rc-cold-context @ CTX.FLAGS !
    _rc-ref3 _rc-cold-context @ _rc-resources @ RREG-RESOLVE
    DUP RREG-S-STALE-EPOCH = _rc-assert
    SWAP 0= _rc-assert DROP
    _rc-stack

    _rc-instance @ CINST-TOUCH
    _rc-resource-id _rc-context @ _rc-ref2 _rc-resources @ RREG-REF
        RREG-S-OK = _rc-assert
    _rc-ref2 RREF.REVISION @ 2 = _rc-assert
    _rc-ref RREF-INIT
    _rc-resource-id _rc-ref RREF.ID RID-COPY
    _rc-ref _rc-context @ _rc-resources @ _rc-bind LBIND-ATTACH
        LBIND-S-OK = _rc-assert
    _rc-bind LBIND-VALID? _rc-assert
    _rc-bind LBIND.REVISION @ 2 = _rc-assert
    _rc-context @ _rc-bind LBIND-CONTEXT? _rc-assert
    _rc-bind _rc-bind2 LBIND-COPY LBIND-S-OK = _rc-assert
    _rc-bind _rc-ref3 LBIND-REF LBIND-S-OK = _rc-assert
    _rc-ref3 RREF.REVISION @ 2 = _rc-assert

    CBR-NEW DUP 0= _rc-assert DROP _rc-request !
    CBR-SIZE 464 = _rc-assert
    _rc-request @ CBR.RESOURCE-ID RID-ZERO? _rc-assert
    _rc-bind _rc-context @ _rc-request @ LBIND-REQUEST!
        LBIND-S-OK = _rc-assert
    _rc-request @ CBR.EPOCH @ 77 = _rc-assert
    _rc-request @ CBR.CONTEXT-ID @ _rc-context @ CTX.ID @ = _rc-assert
    _rc-request @ CBR.CONTEXT-GEN @
        _rc-context @ CTX.GENERATION @ = _rc-assert
    _rc-request @ CBR.PRACTICE-ID _rc-head PHEAD.ID RID= _rc-assert
    _rc-request @ CBR.RESOURCE-ID _rc-resource-id RID= _rc-assert
    _rc-request @ CBR.TARGET-ID @ _rc-instance @ CINST.ID @ = _rc-assert
    _rc-request @ CBR.TARGET-GEN @
        _rc-instance @ CINST.GENERATION @ = _rc-assert
    _rc-request @ CBR.EXPECT-REV @ 2 = _rc-assert

    \ Re-stamping a reused request must erase every terminal/authority field
    \ which could make a prior success look current.
    91 _rc-request @ CBR.ID !
    CBR-F-APPROVED CBR-F-CANCELLED OR _rc-request @ CBR.FLAGS !
    CBUS-S-OK _rc-request @ CBR.STATUS !
    99 _rc-request @ CBR.ACTUAL-REV !
    7 _rc-request @ CBR.START-MS ! 8 _rc-request @ CBR.END-MS !
    123 _rc-request @ CBR.RESULT CV-INT!
    S" stale" 17 _rc-request @ CBR-ERROR!
    1 _rc-request @ CBR.HANDLE IH.EPOCH !
    _rc-bind _rc-context @ _rc-request @ LBIND-REQUEST!
        LBIND-S-OK = _rc-assert
    _rc-request @ CBR.ID @ 0= _rc-assert
    _rc-request @ CBR.FLAGS @ 0= _rc-assert
    _rc-request @ CBR.STATUS @ CBUS-S-INVALID = _rc-assert
    _rc-request @ CBR.ACTUAL-REV @ 0= _rc-assert
    _rc-request @ CBR.START-MS @ 0= _rc-assert
    _rc-request @ CBR.END-MS @ 0= _rc-assert
    _rc-request @ CBR.RESULT CV-TYPE@ CV-T-NULL = _rc-assert
    _rc-request @ CBR.ERROR-A @ 0= _rc-assert
    _rc-request @ CBR.ERROR-U @ 0= _rc-assert
    _rc-request @ CBR.ERROR-CODE @ 0= _rc-assert
    _rc-request @ CBR.HANDLE IH-VALID? 0= _rc-assert
    _rc-request @ _rc-context @ _rc-bind LBIND-ADVANCE
        LBIND-S-MISMATCH = _rc-assert

    \ The semantic RID remains exact at the owner handler and advancement
    \ boundaries, while RREG keeps the one-resource-per-owner invariant.
    _rc-components @ 0 CBUS-NEW DUP 0= _rc-assert DROP _rc-bus !
    CPRINC-USER _rc-request @ CBR.PRINCIPAL !
    _rc-cap _rc-request @ CBR.CAP !
    _rc-request @ _rc-bus @ CBUS-POST CBUS-S-OK = _rc-assert
    _rc-request @ CBR.FLAGS @ CBR-F-QUEUED AND 0<> _rc-assert
    _rc-bind _rc-context @ _rc-request @ LBIND-REQUEST!
        LBIND-S-BUSY = _rc-assert
    _rc-request @ CBR.FLAGS @ CBR-F-QUEUED AND 0<> _rc-assert
    1 _rc-bus @ CBUS-PUMP 1 = _rc-assert
    _rc-running-rebind @ LBIND-S-BUSY = _rc-assert
    _rc-saw-running @ _rc-assert
    _rc-request @ CBR.FLAGS @ CBR-F-COMPLETE AND 0<> _rc-assert
    _rc-request @ CBR-LIFECYCLE-BUSY? 0= _rc-assert
    _rc-seen-resource-id _rc-resource-id RID= _rc-assert
    _rc-resource-id2 _rc-request @ CBR.RESOURCE-ID RID-COPY
    _rc-request @ _rc-context @ _rc-bind LBIND-ADVANCE
        LBIND-S-MISMATCH = _rc-assert
    _rc-resource-id _rc-request @ CBR.RESOURCE-ID RID-COPY
    _rc-request @ _rc-context @ _rc-bind LBIND-ADVANCE
        LBIND-S-OK = _rc-assert

    _rc-bind _rc-context @ _rc-request @ LBIND-REQUEST!
        LBIND-S-OK = _rc-assert
    _rc-request @ CBR.FLAGS @ 0= _rc-assert
    _rc-request @ CBR.STATUS @ CBUS-S-INVALID = _rc-assert
    _rc-request @ CBR.ACTUAL-REV @ 0= _rc-assert
    _rc-instance @ CINST-TOUCH
    CBUS-S-OK _rc-request @ CBR.STATUS !
    3 _rc-request @ CBR.ACTUAL-REV !
    _rc-request @ _rc-context @ _rc-bind LBIND-ADVANCE
        LBIND-S-OK = _rc-assert
    _rc-bind LBIND.REVISION @ 3 = _rc-assert
    4 _rc-request @ CBR.ACTUAL-REV !
    _rc-request @ _rc-context @ _rc-bind LBIND-ADVANCE
        LBIND-S-STALE-REVISION = _rc-assert
    _rc-bind _rc-cold-context @ _rc-request @ LBIND-REQUEST!
        LBIND-S-STALE-EPOCH = _rc-assert
    _rc-stack

    _rc-instance @ _rc-components @ CREG-INST- 0= _rc-assert
    _rc-ref _rc-context @ _rc-resources @ RREG-RESOLVE
    DUP RREG-S-STALE-INSTANCE = _rc-assert
    SWAP 0= _rc-assert DROP
    _rc-instance @ _rc-components @ CREG-INST+ 0= _rc-assert
    _rc-resource-id _rc-context @ _rc-resources @ RREG-UNPUBLISH
        RREG-S-OK = _rc-assert
    _rc-ref _rc-context @ _rc-resources @ RREG-RESOLVE
    DUP RREG-S-NOT-FOUND = _rc-assert
    SWAP 0= _rc-assert DROP
    _rc-stack

    _rc-request @ CBR-FREE
    _rc-bus @ CBUS-FREE
    _rc-value CV-FREE
    _rc-resources @ RREG-FREE
    _rc-instance @ _rc-components @ CREG-INST- DROP
    _rc-instance @ CINST-FREE
    _rc-components @ CREG-FREE
    _rc-cold-context @ CTX-FREE
    _rc-context @ CTX-FREE
    _rc-stack
    _rc-fails @ 0= IF
        ." RESOURCE CONTRACTS PASS " _rc-checks @ .
    ELSE
        ." RESOURCE CONTRACTS FAIL " _rc-fails @ . ." / " _rc-checks @ .
    THEN CR ;

_rc-run
""",
        ready_markers=("RESOURCE CONTRACTS PASS",),
        stable_markers=("RESOURCE CONTRACTS PASS",),
    ),
    "interop": Profile(
        roots=(
            "runtime/state-layout.f",
            "runtime/instance.f",
            "runtime/registry.f",
            "interop/value.f",
            "interop/schema.f",
            "interop/capability.f",
            "interop/policy.f",
            "interop/request-bus.f",
            "interop/intent.f",
            "interop/job.f",
            "interop/endpoint.f",
            "interop/resource.f",
        ),
        resources=(),
        autoexec=r"""\ autoexec.f - runtime and interoperability contracts
ENTER-USERLAND
." [akashic] loading runtime and interop contracts" CR
REQUIRE runtime/state-layout.f
REQUIRE runtime/instance.f
REQUIRE runtime/registry.f
REQUIRE interop/value.f
REQUIRE interop/schema.f
REQUIRE interop/capability.f
REQUIRE interop/policy.f
REQUIRE interop/request-bus.f
REQUIRE interop/intent.f
REQUIRE interop/job.f
REQUIRE interop/endpoint.f
REQUIRE interop/resource.f

VARIABLE _ct-fails
VARIABLE _ct-check
: _ct-assert  ( flag -- )
    1 _ct-check +!
    0= IF 1 _ct-fails +! ." ASSERT " _ct-check @ . CR THEN ;

VARIABLE _ct-cur
CMP-LAYOUT-BEGIN
_ct-cur CMP-CELL: _ct-value
_ct-cur 24 CMP-FIELD: _ct-buffer
CMP-LAYOUT-SIZE CONSTANT _ct-state-size

CREATE _ct-comp COMP-DESC ALLOT
: _ct-comp-setup  ( -- )
    _ct-comp COMP-DESC-INIT
    S" org.akashic.test.runtime"
    _ct-comp COMP.ID-U ! _ct-comp COMP.ID-A !
    S" 1.0.0" _ct-comp COMP.VERSION-U ! _ct-comp COMP.VERSION-A !
    _ct-state-size _ct-comp COMP.STATE-SIZE ! ;

VARIABLE _ct-i1
VARIABLE _ct-i2
VARIABLE _ct-reg
VARIABLE _ct-bus
VARIABLE _ct-req
VARIABLE _ct-router

: _ct-handler  ( request instance -- status )
    DUP CINST-STATE _ct-cur ! DROP
    DUP CBR.ARGS CV-DATA@ _ct-value !
    DROP CBUS-S-OK ;

CREATE _ct-cap CAP-DESC ALLOT
CREATE _ct-intent CINT-DESC-SIZE ALLOT
: _ct-cap-setup  ( -- )
    _ct-cap CAP-DESC-INIT
    CAP-K-COMMAND _ct-cap CAP.KIND !
    S" org.akashic.test/set"
    _ct-cap CAP.ID-U ! _ct-cap CAP.ID-A !
    CAP-E-OBSERVE _ct-cap CAP.EFFECTS !
    ['] _ct-handler _ct-cap CAP.HANDLER-XT ! ;

: _ct-intent-setup  ( -- )
    _ct-intent CINT-DESC-INIT
    S" resource.test"
    _ct-intent CINTD.ID-U ! _ct-intent CINTD.ID-A !
    _ct-cap _ct-intent CINTD.CAP !
    10 _ct-intent CINTD.PRIORITY !
    _ct-intent _ct-comp COMP.INTENTS-A !
    1 _ct-comp COMP.INTENTS-N ! ;

: _ct-run  ( -- )
    0 _ct-fails ! 0 _ct-check !
    S" vfs:/example.f" IRES-VFS-PATH _ct-assert
    DUP 10 = _ct-assert
    DROP C@ [CHAR] / = _ct-assert
    S" file:/example.f" IRES-VFS-PATH 0= _ct-assert 2DROP
    S" vfs" IRES-VFS-PATH 0= _ct-assert 2DROP
    _ct-comp-setup _ct-cap-setup _ct-intent-setup
    _ct-cap _ct-comp COMP.CAPS-A !
    1 _ct-comp COMP.CAPS-N !
    _ct-state-size 32 = _ct-assert
    _ct-comp COMP-DESC-VALID? _ct-assert
    _ct-comp CINST-NEW DUP 0= _ct-assert DROP _ct-i1 !
    _ct-comp CINST-NEW DUP 0= _ct-assert DROP _ct-i2 !
    _ct-i1 @ CINST-STATE _ct-cur ! 11 _ct-value !
    _ct-i2 @ CINST-STATE _ct-cur ! 22 _ct-value !
    _ct-i1 @ CINST-STATE _ct-cur ! _ct-value @ 11 = _ct-assert
    _ct-i2 @ CINST-STATE _ct-cur ! _ct-value @ 22 = _ct-assert
    CREG-NEW DUP 0= _ct-assert DROP _ct-reg !
    128 _ct-cap CAP.FLAGS !
    _ct-comp _ct-reg @ CREG-TYPE+ CREG-E-NOT-FOUND = _ct-assert
    0 _ct-cap CAP.FLAGS !
    _ct-comp _ct-reg @ CREG-TYPE+ 0= _ct-assert
    _ct-i1 @ _ct-reg @ CREG-INST+ 0= _ct-assert
    _ct-i2 @ _ct-reg @ CREG-INST+ 0= _ct-assert
    _ct-i1 @ CINST.ID @ _ct-i1 @ CINST.GENERATION @ _ct-reg @
    CREG-INST-FIND _ct-i1 @ = _ct-assert
    CINT-NEW DUP 0= _ct-assert DROP _ct-router !
    _ct-comp _ct-router @ CINT-REGISTER-COMP 0= _ct-assert
    S" resource.test" _ct-router @ CINT-RESOLVE
    DUP 0<> _ct-assert CIE.CAP @ _ct-cap = _ct-assert
    _ct-reg @ 0 CBUS-NEW DUP 0= _ct-assert DROP _ct-bus !
    CBR-NEW DUP 0= _ct-assert DROP _ct-req !
    CBR-SIZE 464 = _ct-assert
    _ct-req @ CBR.RESOURCE-ID RID-ZERO? _ct-assert
    CPRINC-AGENT _ct-req @ CBR.PRINCIPAL !
    _ct-i2 @ _ct-req @ CBR-CALLER!
    _ct-i1 @ _ct-req @ CBR-TARGET!
    _ct-cap _ct-req @ CBR.CAP !
    77 _ct-req @ CBR.ARGS CV-INT!
    _ct-req @ _ct-bus @ CBUS-POST CBUS-S-OK = _ct-assert
    _ct-req @ CBR.FLAGS @ CBR-F-QUEUED AND 0<> _ct-assert
    _ct-req @ _ct-bus @ CBUS-POST CBUS-S-BUSY = _ct-assert
    _ct-bus @ CBUS.COUNT @ 1 = _ct-assert
    1 _ct-bus @ CBUS-PUMP 1 = _ct-assert
    _ct-req @ CBR.FLAGS @ CBR-F-COMPLETE AND 0<> _ct-assert
    _ct-req @ CBR-LIFECYCLE-BUSY? 0= _ct-assert
    _ct-i1 @ CINST-STATE _ct-cur ! _ct-value @ 77 = _ct-assert
    _ct-req @ CBR.STATUS @ CBUS-S-OK = _ct-assert
    _ct-i1 @ CINST.REVISION @ 1 = _ct-assert
    128 _ct-cap CAP.FLAGS !
    78 _ct-req @ CBR.ARGS CV-INT!
    _ct-req @ _ct-bus @ CBUS-POST CBUS-S-OK = _ct-assert
    1 _ct-bus @ CBUS-PUMP 1 = _ct-assert
    _ct-req @ CBR.STATUS @ CBUS-S-INVALID = _ct-assert
    _ct-i1 @ CINST-STATE _ct-cur ! _ct-value @ 77 = _ct-assert
    _ct-i1 @ CINST.REVISION @ 1 = _ct-assert
    0 _ct-cap CAP.FLAGS !
    CAP-E-NAVIGATE _ct-cap CAP.EFFECTS !
    88 _ct-req @ CBR.ARGS CV-INT!
    _ct-req @ _ct-bus @ CBUS-POST CBUS-S-OK = _ct-assert
    1 _ct-bus @ CBUS-PUMP 1 = _ct-assert
    _ct-i1 @ CINST.REVISION @ 2 = _ct-assert
    CAP-E-OBSERVE _ct-cap CAP.EFFECTS !
    99 _ct-req @ CBR.ARGS CV-INT!
    _ct-req @ _ct-bus @ CBUS-DISPATCH CBUS-S-OK = _ct-assert
    _ct-i1 @ CINST-STATE _ct-cur ! _ct-value @ 99 = _ct-assert
    _ct-req @ CBR.FLAGS @ CBR-F-COMPLETE AND 0<> _ct-assert
    _ct-req @ CBR-FREE
    _ct-bus @ CBUS-FREE
    _ct-router @ CINT-FREE
    _ct-i1 @ _ct-reg @ CREG-INST- 0= _ct-assert
    _ct-i1 @ CINST.ID @ _ct-i1 @ CINST.GENERATION @ _ct-reg @
    CREG-INST-FIND 0= _ct-assert
    _ct-reg @ CREG-FREE
    _ct-i1 @ CINST-FREE _ct-i2 @ CINST-FREE
    _ct-fails @ 0= IF
        ." RUNTIME INTEROP PASS"
    ELSE
        ." RUNTIME INTEROP FAIL " _ct-fails @ .
    THEN CR ;

_ct-run
""",
        ready_markers=("RUNTIME INTEROP PASS",),
        stable_markers=("RUNTIME INTEROP PASS",),
    ),
    "desktop": Profile(
        roots=(
            "tui/applets/desk/desk.f",
            "tui/applets/pad/pad.f",
            "tui/applets/fexplorer/fexplorer.f",
            "tui/applets/daybook/daybook.f",
            "tui/applets/grid/grid.f",
            "tui/applets/agent/agent.f",
            "agent/providers/devtools/scripted.f",
        ),
        resources=(
            "tui/applets/desk/desk.toml",
            "tui/applets/pad/pad.uidl",
            "tui/applets/pad/pad.toml",
            "tui/applets/fexplorer/fexplorer.uidl",
            "tui/applets/fexplorer/fexplorer.toml",
            "tui/applets/daybook/daybook.uidl",
            "tui/applets/grid/grid.uidl",
            "tui/applets/agent/agent.uidl",
        ),
        autoexec=r"""\ autoexec.f - Akashic desktop profile
ENTER-USERLAND
." [akashic] loading desktop" CR
REQUIRE tui/applets/desk/desk.f
REQUIRE tui/applets/pad/pad.f
REQUIRE tui/applets/fexplorer/fexplorer.f
REQUIRE tui/applets/daybook/daybook.f
REQUIRE tui/applets/grid/grid.f
REQUIRE tui/applets/agent/agent.f
REQUIRE agent/providers/devtools/scripted.f
: _boot-agent-source  ( -- )
    SCRIPTED-SOURCE-NEW 0<> ABORT" scripted source allocation failed"
    DESK-AGENT-SOURCE! ;
_boot-agent-source

\ Development-image installation step: provision only genuinely blank media.
\ Existing but invalid slots are deliberately left for Desk recovery.
CREATE _boot-practice-head PHEAD-SIZE ALLOT
CREATE _boot-practice-out PHEAD-SIZE ALLOT
CREATE _boot-practice-store PHEADVFS-SIZE ALLOT
: _boot-practice-id!  ( value id -- ) DUP RID-CLEAR ! ;
: _boot-practice-slot?  ( path-a path-u -- flag )
    VFS-OPEN DUP IF VFS-CLOSE -1 ELSE DROP 0 THEN ;
: _boot-practice-present?  ( -- flag )
    S" /practice-head-a.bin" _boot-practice-slot?
    S" /practice-head-b.bin" _boot-practice-slot? OR ;
: _boot-practice-provision  ( -- )
    _boot-practice-present? IF EXIT THEN
    VFS-CUR _boot-practice-store PHEADVFS-INIT
        PHEADVFS-S-OK <> ABORT" Practice store init failed"
    _boot-practice-out _boot-practice-store PHEADVFS-LOAD
        PHEADVFS-S-RECOVERY <> ABORT" blank Practice did not enter recovery"
    _boot-practice-head PHEAD-INIT
    1 _boot-practice-head PHEAD.ID _boot-practice-id!
    2 _boot-practice-head PHEAD.CURRENT-ROOT _boot-practice-id!
    _boot-practice-head _boot-practice-store PHEADVFS-REINITIALIZE
        PHEADVFS-S-OK <> ABORT" Practice provision failed" ;
_boot-practice-provision

CREATE _boot-pad-desc APP-DESC ALLOT
_boot-pad-desc PAD-ENTRY
_boot-pad-desc DESK-QUEUE-LAUNCH

CREATE _boot-fexp-desc APP-DESC ALLOT
_boot-fexp-desc FEXP-ENTRY
_boot-fexp-desc DESK-QUEUE-LAUNCH

CREATE _boot-daybook-desc APP-DESC ALLOT
_boot-daybook-desc DAYBOOK-ENTRY
_boot-daybook-desc DESK-QUEUE-LAUNCH

CREATE _boot-grid-desc APP-DESC ALLOT
_boot-grid-desc GRID-ENTRY
_boot-grid-desc DESK-QUEUE-LAUNCH

CREATE _boot-agent-desc APP-DESC ALLOT
_boot-agent-desc AGENT-ENTRY
_boot-agent-desc DESK-QUEUE-LAUNCH

." [akashic] starting desktop" CR
: _boot-run-desktop  ( -- ) DESK-RUN ;
' _boot-run-desktop CATCH ?DUP IF
    ." [akashic] desktop exception " . CR
THEN
." [akashic] desktop exited" CR
""",
        ready_markers=(
            "Selection",
            "Untitled",
            "Details",
            "Tools",
            "Entry",
            "Data",
            "Grid",
            "Agent",
        ),
        stable_markers=(
            "Selection",
            "UTF-8",
            "Details",
            "Tools",
            "Entry",
            "Data",
            "Grid",
            "Agent",
        ),
        linked=True,
    ),
    "agent-widgets": Profile(
        roots=(
            "tui/widgets/agent-auth.f",
            "tui/widgets/agent-settings.f",
        ),
        resources=(),
        autoexec=r"""\ autoexec.f - agent account and settings widgets
ENTER-USERLAND
REQUIRE tui/widgets/agent-auth.f
REQUIRE tui/widgets/agent-settings.f

VARIABLE _aw-fails
VARIABLE _aw-checks
: _aw-assert  ( flag -- )
    1 _aw-checks +!
    0= IF 1 _aw-fails +! ." ASSERT " _aw-checks @ . CR THEN ;
CREATE _aw-provider AGENT-PROVIDER-SIZE ALLOT
CREATE _aw-runtime AGENT-RUNTIME-SIZE ALLOT
CREATE _aw-settings AGENT-RUN-SETTINGS-SIZE ALLOT
CREATE _aw-auth AGENT-PROVIDER-AUTH-SIZE ALLOT
CREATE _aw-event 24 ALLOT
CREATE _aw-sync-provider AGENT-PROVIDER-SIZE ALLOT
CREATE _aw-sync-settings AGENT-RUN-SETTINGS-SIZE ALLOT
CREATE _aw-model AGENT-RUN-MODEL-SIZE ALLOT
CREATE _aw-choice AGENT-RUN-CHOICE-SIZE ALLOT
CREATE _aw-model-list 8 ALLOT
CREATE _aw-choice-list 8 ALLOT
VARIABLE _aw-sync-runtime
VARIABLE _aw-sync-connects
VARIABLE _aw-region
VARIABLE _aw-widget
VARIABLE _aw-screen

: _aw-sync-refresh  ( context -- status )
    DROP ARSET-STATE-READY _aw-sync-settings ARSET.STATE !
    1 _aw-sync-settings ARSET.REVISION +! ARSET-S-OK ;

: _aw-sync-connect  ( queue context -- status )
    2DROP 1 _aw-sync-connects +!
    APROV-S-READY _aw-sync-provider APROV.STATE ! 0 ;

: _aw-test-sync-settings  ( -- )
    0 _aw-sync-connects !
    _aw-sync-provider APROV-INIT
    _aw-sync-settings ARSET-INIT
    ['] _aw-sync-refresh _aw-sync-settings ARSET.REFRESH-XT !
    _aw-sync-settings _aw-sync-provider APROV.RUN-SETTINGS !
    ['] _aw-sync-connect _aw-sync-provider APROV.CONNECT-XT !
    _aw-sync-provider ARUNTIME-NEW
    DUP 0= _aw-assert DROP _aw-sync-runtime !
    _aw-sync-settings ARSET.STATE @ ARSET-STATE-READY = _aw-assert
    _aw-sync-connects @ 1 = _aw-assert
    _aw-sync-runtime @ ARUNTIME-FREE ;

: _aw-ready-settings  ( -- )
    _aw-model AGENT-RUN-MODEL-SIZE 0 FILL
    _aw-choice AGENT-RUN-CHOICE-SIZE 0 FILL
    S" test-model" _aw-model ARMODEL.ID-U ! _aw-model ARMODEL.ID-A !
    S" Test model" _aw-model ARMODEL.LABEL-U ! _aw-model ARMODEL.LABEL-A !
    S" Model used to exercise the ready settings renderer."
    _aw-model ARMODEL.DESC-U ! _aw-model ARMODEL.DESC-A !
    ARMODEL-F-SELECTED ARMODEL-F-VERBOSITY OR
    _aw-model ARMODEL.FLAGS !
    S" balanced" _aw-choice ARCH.ID-U ! _aw-choice ARCH.ID-A !
    S" Balanced" _aw-choice ARCH.LABEL-U ! _aw-choice ARCH.LABEL-A !
    S" Balanced reasoning" _aw-choice ARCH.DESC-U ! _aw-choice ARCH.DESC-A !
    ARCH-F-SELECTED _aw-choice ARCH.FLAGS !
    _aw-choice _aw-choice-list !
    _aw-choice-list _aw-model ARMODEL.EFFORTS-A !
    1 _aw-model ARMODEL.EFFORTS-N !
    _aw-choice-list _aw-model ARMODEL.TIERS-A !
    1 _aw-model ARMODEL.TIERS-N !
    _aw-model _aw-model-list !
    ARSET-STATE-READY _aw-settings ARSET.STATE !
    _aw-model-list _aw-settings ARSET.MODELS-A !
    1 _aw-settings ARSET.MODELS-N !
    0 _aw-settings ARSET.SELECTED ! ;

: _aw-run  ( -- )
    0 _aw-fails ! 0 _aw-checks !
    _aw-test-sync-settings
    _aw-provider APROV-INIT
    _aw-runtime AGENT-RUNTIME-SIZE 0 FILL
    _aw-settings ARSET-INIT
    _aw-auth AAUTH-INIT
    _aw-provider _aw-runtime ARUNTIME.PROVIDER !
    _aw-settings _aw-provider APROV.RUN-SETTINGS !
    _aw-auth _aw-provider APROV.AUTH !
    80 20 SCR-NEW DUP _aw-screen ! SCR-USE
    0 0 20 80 RGN-NEW _aw-region !
    _aw-runtime _aw-region @ ARSP-NEW DUP _aw-widget ! ARSP-SHOW
    _aw-widget @ ARSP-ACTIVE? _aw-assert
    11111 _aw-widget @ WDG-DRAW
    11111 = _aw-assert
    _aw-ready-settings
    12345 _aw-widget @ WDG-DRAW
    12345 = _aw-assert
    _aw-event KEY-T-SPECIAL KEY-ESC 0 _KEY-SET-EV
    _aw-event _aw-widget @ WDG-HANDLE _aw-assert
    _aw-widget @ ARSP-ACTIVE? 0= _aw-assert
    _aw-widget @ ARSP-FREE
    _aw-runtime _aw-region @ AAUTHP-NEW DUP _aw-widget ! AAUTHP-SHOW
    _aw-widget @ AAUTHP-ACTIVE? _aw-assert
    _aw-event _aw-widget @ WDG-HANDLE _aw-assert
    _aw-widget @ AAUTHP-ACTIVE? 0= _aw-assert
    _aw-widget @ AAUTHP-FREE
    _aw-region @ RGN-FREE
    _aw-screen @ SCR-FREE
    _aw-auth AAUTH-DESTROY
    _aw-fails @ 0= IF ." AGENT WIDGETS PASS" ELSE
        ." AGENT WIDGETS FAIL " _aw-fails @ .
    THEN CR ;

_aw-run
""",
        ready_markers=("AGENT WIDGETS PASS",),
        stable_markers=("AGENT WIDGETS PASS",),
    ),
    "agent-ui": Profile(
        roots=(
            "tui/applets/agent/agent.f",
            "agent/providers/devtools/scripted.f",
        ),
        resources=("tui/applets/agent/agent.uidl",),
        autoexec=r"""\ autoexec.f - standalone Agent applet profile
ENTER-USERLAND
." [akashic] loading Agent applet" CR
REQUIRE agent/providers/devtools/scripted.f
REQUIRE agent/runtime.f
REQUIRE tui/applets/agent/agent.f
: _boot-agent-source  ( -- )
    SCRIPTED-SOURCE-NEW 0<> ABORT" scripted source allocation failed"
    AGENT-SOURCE! ;
_boot-agent-source
." [akashic] starting Agent applet" CR
AGENT-RUN
." [akashic] Agent applet exited" CR
""",
        ready_markers=("Agent", "Run", "Review", "Ready"),
        stable_markers=("Agent", "Run", "Review", "Ready"),
    ),
    "agent-auth-ui": Profile(
        roots=(
            "tui/applets/agent/agent.f",
            "agent/providers/openai/source.f",
        ),
        resources=("tui/applets/agent/agent.uidl",),
        autoexec=r"""\ autoexec.f - native provider credential UI
ENTER-USERLAND
." [akashic] loading Agent credential UI" CR
REQUIRE agent/providers/openai/source.f
REQUIRE tui/applets/agent/agent.f
: _boot-openai-source  ( -- )
    OPENAI-SOURCE-NEW
    0<> ABORT" OpenAI source allocation failed"
    AGENT-SOURCE! ;
_boot-openai-source
." [akashic] starting Agent credential UI" CR
AGENT-RUN
." [akashic] Agent credential UI exited" CR
""",
        ready_markers=("Agent", "Connection", "Credential required"),
        stable_markers=("Agent", "Connection", "Credential required"),
    ),
    "agent-device-ui": Profile(
        roots=(
            "tui/applets/agent/agent.f",
            "agent/providers/devtools/device-flow.f",
        ),
        resources=("tui/applets/agent/agent.uidl",),
        autoexec=r"""\ autoexec.f - native device-flow and model-settings UI
ENTER-USERLAND
." [akashic] loading Agent device-flow UI" CR
REQUIRE agent/providers/devtools/device-flow.f
REQUIRE tui/applets/agent/agent.f
: _boot-device-source  ( -- )
    DEVFLOW-SOURCE-NEW
    0<> ABORT" device-flow source allocation failed"
    AGENT-SOURCE! ;
_boot-device-source
." [akashic] starting Agent device-flow UI" CR
AGENT-RUN
." [akashic] Agent device-flow UI exited" CR
""",
        ready_markers=("Agent", "Connection", "Sign-in required"),
        stable_markers=("Agent", "Connection"),
    ),
    "uidl-lifecycle": Profile(
        roots=("tui/uidl-tui.f",),
        resources=(),
        autoexec=r"""\ autoexec.f - UIDL widget ownership contracts
ENTER-USERLAND
REQUIRE tui/uidl-tui.f

VARIABLE _ulc-fails VARIABLE _ulc-checks
VARIABLE _ulc-screen VARIABLE _ulc-rgn
CREATE _ulc-borrowed-widget 40 ALLOT

: _ulc-assert  ( flag -- )
    1 _ulc-checks +! 0= IF
        1 _ulc-fails +! ." UIDL LIFECYCLE ASSERT " _ulc-checks @ . CR
    THEN ;

: _ulc-run  ( -- )
    0 _ulc-fails ! 0 _ulc-checks !
    80 24 SCR-NEW DUP _ulc-screen ! SCR-USE
    0 0 24 80 RGN-NEW DUP _ulc-rgn !

    \ UTUI-WIDGET-SET borrows applet-owned state.  Pad's editor panel is
    \ an embedded 40-byte descriptor with this exact ownership shape.
    S" <uidl><region></region></uidl>" _ulc-rgn @ UTUI-LOAD 0<> _ulc-assert
    _ulc-borrowed-widget UIDL-ROOT UIDL-FIRST-CHILD UTUI-WIDGET-SET
    UIDL-ROOT UIDL-FIRST-CHILD _UTUI-SIDECAR
        _UTUI-SC-WOWNER@ _UTUI-WOWNER-CALLER = _ulc-assert
    ['] UTUI-DETACH CATCH 0= _ulc-assert

    \ UIDL's own materialized widgets retain the opposite contract and
    \ are still reclaimed by document teardown.
    S" <uidl><region><input></input></region></uidl>"
        _ulc-rgn @ UTUI-LOAD 0<> _ulc-assert
    UIDL-ROOT UIDL-FIRST-CHILD UIDL-FIRST-CHILD _UTUI-SIDECAR
    DUP _UTUI-SC-WOWNER@ _UTUI-WOWNER-UIDL = _ulc-assert
    _UTUI-SC-WPTR@ 0<> _ulc-assert
    ['] UTUI-DETACH CATCH 0= _ulc-assert

    _ulc-rgn @ RGN-FREE _ulc-screen @ SCR-FREE
    _ulc-fails @ 0= IF
        ." UIDL LIFECYCLE PASS " _ulc-checks @ .
    ELSE
        ." UIDL LIFECYCLE FAIL " _ulc-fails @ . ." / " _ulc-checks @ .
    THEN CR ;

_ulc-run
""",
        ready_markers=("UIDL LIFECYCLE PASS",),
        stable_markers=("UIDL LIFECYCLE PASS",),
        failure_markers=("UIDL LIFECYCLE FAIL", "UIDL LIFECYCLE ASSERT"),
    ),
    "pad-contracts": Profile(
        roots=("tui/applets/pad/pad.f",),
        resources=(),
        autoexec=r"""\ autoexec.f - Pad checked persistence contracts
ENTER-USERLAND
REQUIRE tui/applets/pad/pad.f

VARIABLE _pc-fails VARIABLE _pc-checks VARIABLE _pc-depth
: _pc-assert  ( flag -- )
    1 _pc-checks +! 0= IF
        1 _pc-fails +! ." PAD ASSERT " _pc-checks @ . CR
    THEN ;

CREATE _pc-state _PAD-STATE-SIZE ALLOT
CREATE _pc-io 128 ALLOT
CREATE _pc-desc APP-DESC ALLOT
VARIABLE _pc-vfs VARIABLE _pc-other-vfs VARIABLE _pc-screen VARIABLE _pc-rgn
VARIABLE _pc-a VARIABLE _pc-u VARIABLE _pc-pa VARIABLE _pc-pu
VARIABLE _pc-fd VARIABLE _pc-calls VARIABLE _pc-orig VARIABLE _pc-loaded
VARIABLE _pc-fdfree VARIABLE _pc-heap VARIABLE _pc-xmem VARIABLE _pc-arena-used
VARIABLE _pc-xfree VARIABLE _pc-lines
VARIABLE _pc-close-calls VARIABLE _pc-use-calls VARIABLE _pc-use-throw-at

: _pc-xmem-avail  ( -- u )
    0 _pc-xfree ! XMEM-FL @
    BEGIN DUP WHILE
        DUP @ _pc-xfree +! 8 + @
    REPEAT DROP
    XMEM-FREE _pc-xfree @ + ;

: _pc-put  ( data-a data-u path-a path-u -- )
    _pc-pu ! _pc-pa ! _pc-u ! _pc-a !
    _pc-pa @ _pc-pu @ _pc-vfs @ VFS-CREATE 0<> _pc-assert
    _pc-pa @ _pc-pu @ VFS-OPEN DUP 0<> _pc-assert _pc-fd !
    _pc-a @ _pc-u @ _pc-fd @ VFS-WRITE-EXACT 0= _pc-assert
    _pc-fd @ VFS-CLOSE _pc-vfs @ VFS-SYNC 0= _pc-assert ;

: _pc-file=  ( expected-a expected-u path-a path-u -- flag )
    _pc-pu ! _pc-pa ! _pc-u ! _pc-a !
    _pc-pa @ _pc-pu @ VFS-OPEN DUP 0= IF DROP 0 EXIT THEN _pc-fd !
    _pc-fd @ VFS-SIZE _pc-u @ <> IF _pc-fd @ VFS-CLOSE 0 EXIT THEN
    _pc-u @ 128 > IF _pc-fd @ VFS-CLOSE 0 EXIT THEN
    _pc-io _pc-u @ _pc-fd @ VFS-READ-EXACT IF
        _pc-fd @ VFS-CLOSE 0 EXIT
    THEN
    _pc-fd @ VFS-CLOSE
    _pc-io _pc-u @ _pc-a @ _pc-u @ COMPARE 0= ;

: _pc-text=  ( expected-a expected-u -- flag )
    _pc-u ! _pc-a !
    _PAD-TXTA @ TXTA-GET-TEXT
    2DUP _pc-a @ _pc-u @ COMPARE 0= >R
    DROP FREE R> ;

: _pc-zero-read  ( buf len offset inode vfs -- actual )
    2DROP 2DROP DROP 1 _pc-calls +! 0 ;
: _pc-throw-read  ( buf len offset inode vfs -- actual )
    2DROP 2DROP DROP 1 _pc-calls +! -91 THROW ;
: _pc-fail-sync  ( inode vfs -- ior ) 2DROP -1 ;
: _pc-close-after  ( fd -- )
    VFS-CLOSE 1 _pc-close-calls +! -92 THROW ;
: _pc-use-after  ( vfs -- )
    VFS-USE 1 _pc-use-calls +!
    _pc-use-calls @ _pc-use-throw-at @ = IF -93 THROW THEN ;

: _pc-arm-marked-rollback  ( -- )
    S" /recover.txt" _PAD-REPL VREPL-DERIVE-PATHS!
        VREPL-S-OK = _pc-assert
    _PAD-REPL _VRO-R !
    S" candidate" _PAD-REPL VREPL-STAGE$ _VREPL-CREATE-WRITE
        VREPL-S-OK = _pc-assert
    S" candidate" _VRO-LEN ! _VRO-DATA !
    -1 _VRO-ORIGINAL !
    _VREPL-WRITE-MARKER VREPL-S-OK = _pc-assert
    _pc-vfs @ VFS-SYNC 0= _pc-assert
    _VRO-TARGET>BACKUP 0= _pc-assert
    _pc-vfs @ VFS-SYNC 0= _pc-assert ;

: _pc-setup  ( -- )
    _pc-state _PAD-STATE-SIZE 0 FILL
    _pc-state _PAD-CURRENT-STATE !
    524288 A-XMEM ARENA-NEW IF -1 THROW THEN
    VFS-RAM-VTABLE VFS-NEW DUP _pc-vfs ! VFS-USE
    _pc-vfs @ _PAD-VFS !
    _pc-vfs @ _PAD-REPL VREPL-INIT VREPL-S-OK = _pc-assert
    ['] VFS-CLOSE _PAD-LOAD-CLOSE-XT !
    ['] VFS-USE _PAD-LOAD-USE-XT !
    _PAD-INIT-BUF-TABLE
    _PAD-ARENA-SIZE A-XMEM ARENA-NEW
    DUP 0= _pc-assert DROP _PAD-ARENA !
    80 20 SCR-NEW DUP _pc-screen ! SCR-USE
    0 0 10 40 RGN-NEW DUP _pc-rgn !
    _PAD-DUMMY-BUF _PAD-DUMMY-CAP TXTA-NEW _PAD-TXTA !
    _PAD-BUF-OPEN DUP 0= _pc-assert DROP ;

: _pc-run  ( -- )
    0 _pc-fails ! 0 _pc-checks ! DEPTH _pc-depth !
    _pc-setup
    S" note.txt" _PAD-CANON-PATH DUP 0= _pc-assert DROP
    S" /note.txt" STR-STR= _pc-assert
    S" keep" _PAD-TXTA @ TXTA-SET-TEXT
    -1 _PAD-ACTIVE @ _PAD-BUF-ENTRY _PBE-DIRTY + !
    S" ../escape" _PAD-DO-SAVE-TO 0<> _pc-assert
    S" /escape" _pc-vfs @ VFS-RESOLVE 0= _pc-assert

    65537 ALLOCATE IF -2 THROW THEN DUP >R 65537 88 FILL
    R@ 65537 S" /huge.txt" _pc-put R> FREE
    _PAD-ACTIVE @ _pc-orig ! 0 _pc-calls !
    ['] _pc-zero-read VFS-RAM-VTABLE VFS-VT-READ CELLS + !
    S" /huge.txt" _PAD-OPEN-PATH -4 = _pc-assert
    ['] _VFS-RAM-READ VFS-RAM-VTABLE VFS-VT-READ CELLS + !
    _pc-calls @ 0= _pc-assert
    _PAD-ACTIVE @ _pc-orig @ = _pc-assert
    S" keep" _pc-text= _pc-assert
    _PAD-ACTIVE @ _PAD-BUF-ENTRY _PBE-DIRTY + @ 0<> _pc-assert

    S" short" S" /short.txt" _pc-put 0 _pc-calls !
    ['] _pc-zero-read VFS-RAM-VTABLE VFS-VT-READ CELLS + !
    S" /short.txt" _PAD-OPEN-PATH -5 = _pc-assert
    ['] _VFS-RAM-READ VFS-RAM-VTABLE VFS-VT-READ CELLS + !
    _pc-calls @ 0> _pc-assert
    _PAD-ACTIVE @ _pc-orig @ = _pc-assert
    S" keep" _pc-text= _pc-assert

    \ Recovery happens before the existence probe: target is deliberately
    \ absent while a durable rollback marker, stage, and backup remain.
    S" recovered" S" /recover.txt" _pc-put
    _pc-arm-marked-rollback
    _PAD-REPL VREPL-TARGET$ _pc-vfs @ VFS-RESOLVE 0= _pc-assert
    _PAD-REPL VREPL-BACKUP$ _pc-vfs @ VFS-RESOLVE 0<> _pc-assert
    _PAD-REPL VREPL-MARKER$ _pc-vfs @ VFS-RESOLVE 0<> _pc-assert
    S" /recover.txt" _PAD-OPEN-PATH 0= _pc-assert
    _PAD-ACTIVE @ DUP _pc-loaded ! _pc-orig @ <> _pc-assert
    S" recovered" _pc-text= _pc-assert
    _PAD-REPL VREPL-TARGET$ _pc-vfs @ VFS-RESOLVE 0<> _pc-assert
    _PAD-REPL VREPL-BACKUP$ _pc-vfs @ VFS-RESOLVE 0= _pc-assert
    _PAD-REPL VREPL-MARKER$ _pc-vfs @ VFS-RESOLVE 0= _pc-assert
    _pc-loaded @ _PAD-BUF-CLOSE
    _PAD-ACTIVE @ _pc-orig @ = _pc-assert
    S" keep" _pc-text= _pc-assert

    \ A thrown transfer is contained after allocating/opening.  The newly
    \ opened buffer is rolled back, owned I/O state is released, and the
    \ caller's active-VFS selector is restored even when it names another VFS.
    _pc-vfs @ VFS-USE S" throw" S" /throw.txt" _pc-put
    524288 A-XMEM ARENA-NEW IF -3 THROW THEN
    VFS-RAM-VTABLE VFS-NEW _pc-other-vfs !
    _pc-vfs @ V.FDFREE @ _pc-fdfree !
    HEAP-FREE-BYTES _pc-heap !
    _pc-xmem-avail _pc-xmem !
    _PAD-ARENA @ ARENA-USED _pc-arena-used !
    0 _pc-calls !
    ['] _pc-throw-read VFS-RAM-VTABLE VFS-VT-READ CELLS + !
    _pc-other-vfs @ VFS-USE
    S" /throw.txt" _PAD-OPEN-PATH -7 = _pc-assert
    ['] _VFS-RAM-READ VFS-RAM-VTABLE VFS-VT-READ CELLS + !
    _pc-calls @ 0> _pc-assert
    VFS-CUR _pc-other-vfs @ = _pc-assert
    _PIO-FD @ 0= _pc-assert _PIO-BUF @ 0= _pc-assert
    _pc-vfs @ V.FDFREE @ _pc-fdfree @ = _pc-assert
    HEAP-FREE-BYTES _pc-heap @ = _pc-assert
    _pc-xmem-avail _pc-xmem @ = _pc-assert
    _PAD-ARENA @ ARENA-USED _pc-arena-used @ = _pc-assert
    _PAD-ACTIVE @ _pc-orig @ = _pc-assert
    S" keep" _pc-text= _pc-assert
    _pc-vfs @ VFS-USE

    \ A close implementation may recycle the descriptor and only then
    \ throw.  Ownership is cleared before the call, so cleanup neither
    \ double-closes it nor skips the remaining buffer/selector stages.
    S" after" S" /after.txt" _pc-put
    _pc-vfs @ V.FDFREE @ _pc-fdfree !
    HEAP-FREE-BYTES _pc-heap ! _pc-xmem-avail _pc-xmem !
    _PAD-ARENA @ ARENA-USED _pc-arena-used !
    0 _pc-close-calls !
    ['] _pc-close-after _PAD-LOAD-CLOSE-XT !
    _pc-other-vfs @ VFS-USE
    S" /after.txt" _PAD-OPEN-PATH -7 = _pc-assert
    ['] VFS-CLOSE _PAD-LOAD-CLOSE-XT !
    _pc-close-calls @ 1 = _pc-assert
    _PIO-THROW @ -92 = _pc-assert
    _PIO-CLEANUP-THROW @ 0= _pc-assert
    VFS-CUR _pc-other-vfs @ = _pc-assert
    _PIO-FD @ 0= _pc-assert _PIO-BUF @ 0= _pc-assert
    _pc-vfs @ V.FDFREE @ _pc-fdfree @ = _pc-assert
    HEAP-FREE-BYTES _pc-heap @ = _pc-assert
    _pc-xmem-avail _pc-xmem @ = _pc-assert
    _PAD-ARENA @ ARENA-USED _pc-arena-used @ = _pc-assert
    _PAD-ACTIVE @ _pc-orig @ = _pc-assert
    S" keep" _pc-text= _pc-assert

    \ Cleanup-only selector failure is normalized to -7.  The injected use
    \ switches first and throws second, so the old selector invariant still
    \ holds and the successfully loaded scratch tab is rolled back.
    _pc-vfs @ V.FDFREE @ _pc-fdfree !
    HEAP-FREE-BYTES _pc-heap ! _pc-xmem-avail _pc-xmem !
    0 _pc-use-calls ! 2 _pc-use-throw-at !
    ['] _pc-use-after _PAD-LOAD-USE-XT !
    _pc-other-vfs @ VFS-USE
    S" /after.txt" _PAD-OPEN-PATH -7 = _pc-assert
    ['] VFS-USE _PAD-LOAD-USE-XT !
    _pc-use-calls @ 2 = _pc-assert
    _PIO-THROW @ 0= _pc-assert
    _PIO-CLEANUP-THROW @ -93 = _pc-assert
    VFS-CUR _pc-other-vfs @ = _pc-assert
    _PIO-FD @ 0= _pc-assert _PIO-BUF @ 0= _pc-assert
    _pc-vfs @ V.FDFREE @ _pc-fdfree @ = _pc-assert
    HEAP-FREE-BYTES _pc-heap @ = _pc-assert
    _pc-xmem-avail _pc-xmem @ = _pc-assert
    _PAD-ACTIVE @ _pc-orig @ = _pc-assert
    S" keep" _pc-text= _pc-assert

    \ A specific primary transfer result wins over a later restoration
    \ THROW, while cleanup still restores the selector and all ownership.
    0 _pc-calls ! 0 _pc-use-calls ! 2 _pc-use-throw-at !
    ['] _pc-zero-read VFS-RAM-VTABLE VFS-VT-READ CELLS + !
    ['] _pc-use-after _PAD-LOAD-USE-XT !
    _pc-other-vfs @ VFS-USE
    S" /short.txt" _PAD-OPEN-PATH -5 = _pc-assert
    ['] VFS-USE _PAD-LOAD-USE-XT !
    ['] _VFS-RAM-READ VFS-RAM-VTABLE VFS-VT-READ CELLS + !
    _pc-calls @ 0> _pc-assert _pc-use-calls @ 2 = _pc-assert
    _PIO-CLEANUP-THROW @ -93 = _pc-assert
    VFS-CUR _pc-other-vfs @ = _pc-assert
    _PIO-FD @ 0= _pc-assert _PIO-BUF @ 0= _pc-assert
    _PAD-ACTIVE @ _pc-orig @ = _pc-assert
    S" keep" _pc-text= _pc-assert
    _pc-vfs @ VFS-USE

    S" old" S" /save.txt" _pc-put
    S" new" _PAD-TXTA @ TXTA-SET-TEXT
    -1 _PAD-ACTIVE @ _PAD-BUF-ENTRY _PBE-DIRTY + !
    ['] _pc-fail-sync VFS-RAM-VTABLE VFS-VT-SYNC CELLS + !
    S" /save.txt" _PAD-SAVE-CURRENT-AS 0<> _pc-assert
    ['] _VFS-RAM-SYNC VFS-RAM-VTABLE VFS-VT-SYNC CELLS + !
    S" old" S" /save.txt" _pc-file= _pc-assert
    _PAD-ACTIVE @ _PAD-BUF-ENTRY _PBE-DIRTY + @ 0<> _pc-assert
    S" /save.txt" _PAD-SAVE-CURRENT-AS 0= _pc-assert
    S" new" S" /save.txt" _pc-file= _pc-assert
    _PAD-ACTIVE @ _PAD-BUF-ENTRY _PBE-DIRTY + @ 0= _pc-assert

    \ Every advertised tab must hold an exact-limit, newline-dense file.
    \ Packed line indexes grow directly to the required 65,537 entries;
    \ they no longer consume or abandon blocks in Pad's shared text arena.
    _PAD-BUF-CAP ALLOCATE IF -4 THROW THEN DUP _pc-lines !
    _PAD-BUF-CAP 10 FILL
    _PAD-MAX-BUFS 0 DO
        I IF _PAD-BUF-OPEN I = _pc-assert ELSE 0 _PAD-BUF-SWITCH THEN
        _pc-lines @ _PAD-BUF-CAP _PAD-TXTA @ TXTA-SET-TEXT
        I _PAD-BUF-ENTRY _PBE-GB + @
        DUP GB-LEN _PAD-BUF-CAP = _pc-assert
        DUP GB-LINES _PAD-BUF-CAP 1+ = _pc-assert
        DUP _GB-O-LCAP + @ _PAD-BUF-CAP 1+ = _pc-assert
        _PAD-BUF-CAP OVER GB-LINE-OFF _PAD-BUF-CAP = _pc-assert
        DROP
    LOOP
    _pc-lines @ FREE 0 _pc-lines !
    _PAD-BUF-CNT @ _PAD-MAX-BUFS = _pc-assert
    _PAD-BUF-OPEN -1 = _pc-assert
    _PAD-ARENA @ ARENA-USED
    _PAD-MAX-BUFS _PAD-BUF-CAP _GB-DESC-SZ + * = _pc-assert

    \ Roll back the same inactive slot repeatedly after it has held the
    \ worst-case document.  Both allocators, the VFS descriptor pool, the
    \ active selector, and the arena high-water mark must remain unchanged.
    _PAD-MAX-BUFS 1- _PAD-BUF-CLOSE
    _pc-vfs @ V.FDFREE @ _pc-fdfree !
    HEAP-FREE-BYTES _pc-heap !
    _pc-xmem-avail _pc-xmem !
    _PAD-ARENA @ ARENA-USED _pc-arena-used !
    0 _pc-calls !
    ['] _pc-throw-read VFS-RAM-VTABLE VFS-VT-READ CELLS + !
    _pc-other-vfs @ VFS-USE
    32 0 DO S" /throw.txt" _PAD-OPEN-PATH -7 = _pc-assert LOOP
    ['] _VFS-RAM-READ VFS-RAM-VTABLE VFS-VT-READ CELLS + !
    _pc-calls @ 32 = _pc-assert
    VFS-CUR _pc-other-vfs @ = _pc-assert
    _PIO-FD @ 0= _pc-assert _PIO-BUF @ 0= _pc-assert
    _pc-vfs @ V.FDFREE @ _pc-fdfree @ = _pc-assert
    HEAP-FREE-BYTES _pc-heap @ = _pc-assert
    _pc-xmem-avail _pc-xmem @ = _pc-assert
    _PAD-ARENA @ ARENA-USED _pc-arena-used @ = _pc-assert
    _PAD-BUF-CNT @ _PAD-MAX-BUFS 1- = _pc-assert
    _PAD-ACTIVE @ 0= _pc-assert
    _pc-vfs @ VFS-USE

    \ Leave the normal one-tab state for the remaining descriptor checks.
    _PAD-MAX-BUFS 1- 1 DO I _PAD-BUF-CLOSE LOOP
    _PAD-BUF-CNT @ 1 = _pc-assert

    _pc-desc PAD-ENTRY
    _pc-desc APP.REQUEST-CLOSE-XT @ ['] PAD-REQUEST-CLOSE-CB = _pc-assert
    DEPTH _pc-depth @ <> IF
        ." PAD STACK DELTA " DEPTH _pc-depth @ - . CR .S CR
    THEN
    DEPTH _pc-depth @ = _pc-assert
    _pc-fails @ 0= IF
        ." PAD CONTRACT PASS " _pc-checks @ .
    ELSE
        ." PAD CONTRACT FAIL " _pc-fails @ . ." / " _pc-checks @ .
    THEN CR ;

_pc-run
""",
        ready_markers=("PAD CONTRACT PASS",),
        stable_markers=("PAD CONTRACT PASS",),
        failure_markers=("PAD CONTRACT FAIL", "PAD ASSERT"),
    ),
    "pad-resource-contracts": Profile(
        roots=(
            "tui/applets/pad/pad.f",
            "interop/shared-document.f",
        ),
        resources=(),
        autoexec=r"""\ autoexec.f - Pad semantic Daybook lens contracts
ENTER-USERLAND
REQUIRE tui/applets/pad/pad.f
REQUIRE interop/shared-document.f

VARIABLE _pr-fails VARIABLE _pr-checks VARIABLE _pr-depth
VARIABLE _pr-call-depth VARIABLE _pr-status
VARIABLE _pr-vfs VARIABLE _pr-context VARIABLE _pr-creg VARIABLE _pr-rreg
VARIABLE _pr-bus VARIABLE _pr-owner VARIABLE _pr-pad VARIABLE _pr-request
VARIABLE _pr-ext-request VARIABLE _pr-screen VARIABLE _pr-rgn
VARIABLE _pr-fd VARIABLE _pr-a VARIABLE _pr-u VARIABLE _pr-pa VARIABLE _pr-pu
VARIABLE _pr-shared-index VARIABLE _pr-owner-revision VARIABLE _pr-service-mode
VARIABLE _pr-pad-binding-revision

CREATE _pr-head PHEAD-SIZE ALLOT
CREATE _pr-rid RID-SIZE ALLOT
CREATE _pr-ref RREF-SIZE ALLOT
CREATE _pr-opened-ref RREF-SIZE ALLOT
CREATE _pr-result-ref RREF-SIZE ALLOT
CREATE _pr-ext-bind LBIND-SIZE ALLOT
CREATE _pr-policy CPOLICY-SIZE ALLOT
CREATE _pr-endpoint IENDPOINT-SIZE ALLOT
CREATE _pr-io 256 ALLOT

: _pr-assert  ( flag -- )
    1 _pr-checks +! 0= IF
        1 _pr-fails +! ." PAD RESOURCE ASSERT " _pr-checks @ . CR
    THEN ;

: _pr-stack  ( -- )
    DEPTH DUP _pr-depth @ <> IF
        ." PAD RESOURCE STACK " _pr-depth @ . ." -> " DUP . CR .S CR
    THEN
    _pr-depth @ = _pr-assert ;

: _pr-id!  ( value id -- )
    DUP RID-CLEAR ! ;

: _pr-put  ( data-a data-u path-a path-u -- )
    _pr-pu ! _pr-pa ! _pr-u ! _pr-a !
    _pr-pa @ _pr-pu @ _pr-vfs @ VFS-CREATE 0<> _pr-assert
    _pr-pa @ _pr-pu @ VFS-OPEN DUP 0<> _pr-assert _pr-fd !
    _pr-a @ _pr-u @ _pr-fd @ VFS-WRITE-EXACT 0= _pr-assert
    _pr-fd @ VFS-CLOSE _pr-vfs @ VFS-SYNC 0= _pr-assert ;

: _pr-file=  ( expected-a expected-u path-a path-u -- flag )
    _pr-pu ! _pr-pa ! _pr-u ! _pr-a !
    _pr-pa @ _pr-pu @ VFS-OPEN DUP 0= IF DROP 0 EXIT THEN _pr-fd !
    _pr-fd @ VFS-SIZE _pr-u @ <> IF _pr-fd @ VFS-CLOSE 0 EXIT THEN
    _pr-u @ 256 > IF _pr-fd @ VFS-CLOSE 0 EXIT THEN
    _pr-io _pr-u @ _pr-fd @ VFS-READ-EXACT IF
        _pr-fd @ VFS-CLOSE 0 EXIT
    THEN
    _pr-fd @ VFS-CLOSE
    _pr-io _pr-u @ _pr-a @ _pr-u @ COMPARE 0= ;

: _pr-text=  ( expected-a expected-u -- flag )
    _pr-u ! _pr-a !
    _PAD-TXTA @ TXTA-GET-TEXT
    2DUP _pr-a @ _pr-u @ COMPARE 0= >R
    DROP FREE R> ;

VARIABLE _pr-service-a VARIABLE _pr-service-u

: _pr-service  ( id-a id-u ignored -- service | 0 )
    DROP _pr-service-u ! _pr-service-a !
    _pr-service-a @ _pr-service-u @
        S" org.akashic.runtime.context" STR-STR= IF
        _pr-service-mode @ 2 = IF 0 ELSE _pr-context @ THEN EXIT
    THEN
    _pr-service-a @ _pr-service-u @
        S" org.akashic.runtime.resource-registry" STR-STR= IF
        _pr-rreg @ EXIT
    THEN
    _pr-service-a @ _pr-service-u @
        S" org.akashic.interop.request-bus" STR-STR= IF
        _pr-service-mode @ 1 = IF 0 ELSE _pr-bus @ THEN EXIT
    THEN
    _pr-service-a @ _pr-service-u @
        S" org.akashic.resource.daybook" STR-STR= IF
        _pr-rid EXIT
    THEN
    0 ;

: _pr-open-request!  ( reference -- )
    _pr-request @ ?DUP IF CBR-FREE THEN
    CBR-NEW DUP 0= _pr-assert DROP _pr-request !
    CPRINC-USER _pr-request @ CBR.PRINCIPAL !
    _pr-pad @ _pr-request @ CBR-TARGET!
    PAD-CAP-OPEN _pr-request @ CBR.CAP !
    _pr-request @ CBR.ARGS IRES-RREF! IRES-S-OK = _pr-assert ;

: _pr-dispatch-open  ( -- status )
    DEPTH _pr-call-depth !
    _pr-request @ _pr-bus @ CBUS-DISPATCH _pr-status !
    DEPTH _pr-call-depth @ = _pr-assert
    _pr-status @ ;

: _pr-active-request!  ( -- )
    _pr-request @ ?DUP IF CBR-FREE THEN
    CBR-NEW DUP 0= _pr-assert DROP _pr-request !
    CPRINC-USER _pr-request @ CBR.PRINCIPAL !
    _pr-pad @ _pr-request @ CBR-TARGET!
    PAD-CAP-ACTIVE _pr-request @ CBR.CAP !
    _pr-request @ CBR.ARGS CV-NULL! ;

: _pr-fail-advance  ( request context binding -- status )
    2DROP DROP LBIND-S-MISMATCH ;

: _pr-owner-snapshot  ( -- )
    _pr-ext-bind _pr-context @ _pr-ext-request @ LBIND-REQUEST!
        LBIND-S-OK = _pr-assert
    CPRINC-USER _pr-ext-request @ CBR.PRINCIPAL !
    S" resource.snapshot" _pr-owner @ CINST-DESC COMP-CAP-FIND
        _pr-ext-request @ CBR.CAP !
    _pr-ext-request @ CBR.ARGS CV-NULL!
    DEPTH _pr-call-depth !
    _pr-ext-request @ _pr-bus @ CBUS-DISPATCH CBUS-S-OK = _pr-assert
    DEPTH _pr-call-depth @ = _pr-assert
    _pr-ext-request @ CBR.RESULT DUP CV-TYPE@ CV-T-STRING = _pr-assert
    DUP CV-DATA@ SWAP CV-LEN@
    S" # Daybook\n\n> 2026-07-13 | Daybook edit\n" STR-STR= _pr-assert ;

: _pr-pad-storage-setup  ( -- )
    _pr-pad @ _PAD-ACTIVATE
    _pr-vfs @ VFS-USE _pr-vfs @ _PAD-VFS !
    _pr-vfs @ _PAD-REPL VREPL-INIT VREPL-S-OK = _pr-assert
    _PAD-INIT-BUF-TABLE
    _PAD-ARENA-SIZE A-XMEM ARENA-NEW
    DUP 0= _pr-assert DROP _PAD-ARENA !
    80 20 SCR-NEW DUP _pr-screen ! SCR-USE
    0 0 10 40 RGN-NEW DUP _pr-rgn !
    _PAD-DUMMY-BUF _PAD-DUMMY-CAP TXTA-NEW _PAD-TXTA !
    _PAD-BUF-OPEN DUP 0= _pr-assert DROP
    _PAD-SHARED-INIT
    _PAD-RESOURCE-MODE @ SDLENS-M-SHARED = _pr-assert ;

: _pr-pad-storage-free  ( -- )
    _pr-pad @ _PAD-ACTIVATE
    _PAD-UNBIND _PAD-SHARED-FINI
    _PAD-MAX-BUFS 0 DO
        I _PAD-BUF-ENTRY _PBE-GB + @ ?DUP IF GB-FREE THEN
        I _PAD-BUF-ENTRY _PBE-UNDO + @ ?DUP IF UNDO-FREE THEN
    LOOP
    _PAD-ARENA @ ?DUP IF ARENA-DESTROY THEN
    _PAD-TXTA @ ?DUP IF TXTA-FREE THEN
    _pr-rgn @ RGN-FREE _pr-screen @ SCR-FREE ;

: _pr-mode-controls  ( -- )
    1 _pr-service-mode !
    PAD-COMP-DESC CINST-NEW DUP 0= _pr-assert DROP >R
    _pr-endpoint R@ CINST.ENDPOINT !
    R@ _PAD-ACTIVATE _PAD-SHARED-INIT
    _PAD-RESOURCE-MODE @ SDLENS-M-BLOCKED = _pr-assert
    _PAD-SHARED-FINI R> CINST-FREE
    2 _pr-service-mode !
    PAD-COMP-DESC CINST-NEW DUP 0= _pr-assert DROP >R
    _pr-endpoint R@ CINST.ENDPOINT !
    R@ _PAD-ACTIVATE _PAD-SHARED-INIT
    _PAD-RESOURCE-MODE @ SDLENS-M-BLOCKED = _pr-assert
    _PAD-SHARED-FINI R> CINST-FREE
    PAD-COMP-DESC CINST-NEW DUP 0= _pr-assert DROP >R
    R@ _PAD-ACTIVATE _PAD-SHARED-INIT
    _PAD-RESOURCE-MODE @ SDLENS-M-DIRECT = _pr-assert
    _PAD-SHARED-FINI R> CINST-FREE
    0 _pr-service-mode !
    _pr-pad @ _PAD-ACTIVATE ;

: _pr-run  ( -- )
    0 _pr-fails ! 0 _pr-checks ! 0 _pr-request ! 0 _pr-ext-request !
    0 _pr-service-mode ! DEPTH _pr-depth !
    524288 A-XMEM ARENA-NEW IF -201 THROW THEN
    VFS-RAM-VTABLE VFS-NEW DUP _pr-vfs ! VFS-USE
    S" # Daybook\n" S" /daybook.md" _pr-put

    _pr-head PHEAD-INIT
    101 _pr-head PHEAD.ID _pr-id!
    102 _pr-head PHEAD.CURRENT-ROOT _pr-id!
    777 CTX-NEW DUP 0= _pr-assert DROP _pr-context !
    _pr-head _pr-context @ CTX.PRACTICE !
    CTX-F-ACTIVE _pr-context @ CTX.FLAGS !
    _pr-vfs @ _pr-context @ CTX.VFS !
    CREG-NEW DUP 0= _pr-assert DROP _pr-creg !
    _pr-creg @ _pr-context @ RREG-NEW
        DUP 0= _pr-assert DROP _pr-rreg !
    103 _pr-rid _pr-id!
    _pr-vfs @ _pr-rid _pr-context @ _pr-rreg @ _pr-creg @
        SDOC-ACTIVATE DUP SDOC-S-OK = _pr-assert DROP _pr-owner !
    _pr-policy CPOLICY-INIT
    _pr-creg @ _pr-policy CBUS-NEW DUP 0= _pr-assert DROP _pr-bus !
    _pr-bus @ _pr-context @ CTX.QUEUE !
    _pr-policy _pr-context @ CTX.POLICY !

    _pr-endpoint IENDPOINT-INIT
    ['] _pr-service _pr-endpoint IEND.SERVICE-XT !
    _PAD-COMP-SETUP
    PAD-COMP-DESC _pr-creg @ CREG-TYPE+ 0= _pr-assert
    PAD-COMP-DESC CINST-NEW DUP 0= _pr-assert DROP _pr-pad !
    _pr-endpoint _pr-pad @ CINST.ENDPOINT !
    _pr-pad @ _pr-creg @ CREG-INST+ 0= _pr-assert
    _pr-pad-storage-setup
    _pr-mode-controls

    \ Route an exact semantic resource through the real bus.  Pad's handler
    \ synchronously dispatches resource.snapshot on that same bus.
    _pr-rid _pr-context @ _pr-ref _pr-rreg @ RREG-REF
        RREG-S-OK = _pr-assert
    _pr-ref _pr-open-request!
    _pr-dispatch-open CBUS-S-OK = _pr-assert
    _pr-request @ CBR.RESULT _pr-result-ref IRES-RREF@
        IRES-S-OK = _pr-assert
    _pr-result-ref _pr-ref RREF= _pr-assert
    _pr-result-ref _pr-opened-ref RREF-COPY RREF-S-OK = _pr-assert
    _PAD-FIND-SHARED-BUFFER DUP 0>= _pr-assert _pr-shared-index !
    _PAD-BUF-CNT @ 2 = _pr-assert
    S" # Daybook\n" _pr-text= _pr-assert
    _PAD-ACTIVE @ _PAD-BUF-ENTRY _PBE-RESERVED + @ 0<> _pr-assert
    _PAD-SHARED-BIND LBIND.REVISION @
        _pr-opened-ref RREF.REVISION @ = _pr-assert

    \ The public active-document capability reports the same exact semantic
    \ identity retained by the shared buffer, never its VFS backing path.
    _pr-active-request!
    DEPTH _pr-call-depth !
    _pr-request @ _pr-bus @ CBUS-DISPATCH CBUS-S-OK = _pr-assert
    DEPTH _pr-call-depth @ = _pr-assert
    _pr-request @ CBR.RESULT _pr-result-ref IRES-RREF@
        IRES-S-OK = _pr-assert
    _pr-result-ref _pr-opened-ref RREF= _pr-assert

    \ A successful save advances only after resource.replace commits.
    S" # Daybook\n\n> 2026-07-13 | Pad committed edit\n"
        _PAD-TXTA @ TXTA-SET-TEXT
    -1 _PAD-ACTIVE @ _PAD-BUF-ENTRY _PBE-DIRTY + !
    DEPTH _pr-call-depth !
    S" /daybook.md" _PAD-SAVE-CURRENT-AS _pr-status !
    DEPTH _pr-call-depth @ = _pr-assert
    _pr-status @ 0= _pr-assert
    _PAD-ACTIVE @ _PAD-BUF-ENTRY _PBE-DIRTY + @ 0= _pr-assert
    _PAD-SHARED-BIND LBIND.REVISION @ DUP _pr-pad-binding-revision !
        _pr-owner @ CINST.REVISION @ = _pr-assert
    S" # Daybook\n\n> 2026-07-13 | Pad committed edit\n"
        S" /daybook.md" _pr-file= _pr-assert

    \ Commit a competing owner edit from the current revision.
    _pr-rid _pr-context @ _pr-ref _pr-rreg @ RREG-REF
        RREG-S-OK = _pr-assert
    _pr-ext-bind LBIND-INIT
    _pr-ref _pr-context @ _pr-rreg @ _pr-ext-bind LBIND-ATTACH
        LBIND-S-OK = _pr-assert
    CBR-NEW DUP 0= _pr-assert DROP _pr-ext-request !
    _pr-ext-bind _pr-context @ _pr-ext-request @ LBIND-REQUEST!
        LBIND-S-OK = _pr-assert
    CPRINC-USER _pr-ext-request @ CBR.PRINCIPAL !
    S" resource.replace" _pr-owner @ CINST-DESC COMP-CAP-FIND
        _pr-ext-request @ CBR.CAP !
    S" # Daybook\n\n> 2026-07-13 | Daybook edit\n"
        _pr-ext-request @ CBR.ARGS CV-STRING! 0= _pr-assert
    _pr-ext-request @ _pr-bus @ CBUS-DISPATCH CBUS-S-OK = _pr-assert
    _pr-ext-request @ _pr-context @ _pr-ext-bind LBIND-ADVANCE
        LBIND-S-OK = _pr-assert
    _pr-owner @ CINST.REVISION @ DUP _pr-owner-revision ! 3 = _pr-assert
    S" # Daybook\n\n> 2026-07-13 | Daybook edit\n"
        S" /daybook.md" _pr-file= _pr-assert
    _pr-owner-snapshot

    \ Pad remains bound to the prior revision.  Its stale save preserves the
    \ dirty text while leaving owner revision, owner content, and backing bytes
    \ exactly as committed by the competing Daybook edit.
    S" # Daybook\n\n> 2026-07-13 | stale Pad edit\n"
        _PAD-TXTA @ TXTA-SET-TEXT
    -1 _PAD-ACTIVE @ _PAD-BUF-ENTRY _PBE-DIRTY + !
    DEPTH _pr-call-depth !
    S" /daybook.md" _PAD-SAVE-CURRENT-AS _pr-status !
    DEPTH _pr-call-depth @ = _pr-assert
    _pr-status @ _PAD-E-STALE = _pr-assert
    _PAD-ACTIVE @ _PAD-BUF-ENTRY _PBE-DIRTY + @ 0<> _pr-assert
    _PAD-SHARED-STALE @ 0<> _pr-assert
    _PAD-SHARED-BIND LBIND.REVISION @
        _pr-pad-binding-revision @ = _pr-assert
    S" # Daybook\n\n> 2026-07-13 | stale Pad edit\n" _pr-text= _pr-assert
    _pr-owner @ CINST.REVISION @ _pr-owner-revision @ = _pr-assert
    S" # Daybook\n\n> 2026-07-13 | Daybook edit\n"
        S" /daybook.md" _pr-file= _pr-assert
    _pr-owner-snapshot

    \ The old exact semantic reference fails without disturbing the live tab.
    _pr-opened-ref _pr-open-request!
    _pr-dispatch-open CBUS-S-STALE-REVISION = _pr-assert
    _PAD-ACTIVE @ _PAD-BUF-ENTRY _PBE-DIRTY + @ 0<> _pr-assert
    S" # Daybook\n\n> 2026-07-13 | stale Pad edit\n" _pr-text= _pr-assert

    \ Close/discard and reopen the current exact reference to reload safely.
    _pr-shared-index @ _PAD-BUF-CLOSE
    _pr-rid _pr-context @ _pr-ref _pr-rreg @ RREG-REF
        RREG-S-OK = _pr-assert
    _pr-ref _pr-open-request!
    _pr-dispatch-open CBUS-S-OK = _pr-assert
    S" # Daybook\n\n> 2026-07-13 | Daybook edit\n" _pr-text= _pr-assert
    _PAD-ACTIVE @ _PAD-BUF-ENTRY _PBE-DIRTY + @ 0= _pr-assert
    _PAD-SHARED-STALE @ 0= _pr-assert
    _PAD-FIND-SHARED-BUFFER DUP 0>= _pr-assert _pr-shared-index !

    \ If revision advancement itself fails after a successful owner commit,
    \ Pad treats the commit as authoritative, invalidates the lens, clears the
    \ retryable dirty bit, and blocks every later write until a fresh reload.
    ['] _pr-fail-advance _PAD-SHARED-ADVANCE-XT !
    S" # Daybook\n\n> 2026-07-13 | post-commit Pad edit\n"
        _PAD-TXTA @ TXTA-SET-TEXT
    -1 _PAD-ACTIVE @ _PAD-BUF-ENTRY _PBE-DIRTY + !
    S" /daybook.md" _PAD-SAVE-CURRENT-AS 0= _pr-assert
    ['] LBIND-ADVANCE _PAD-SHARED-ADVANCE-XT !
    _PAD-ACTIVE @ _PAD-BUF-ENTRY _PBE-DIRTY + @ 0= _pr-assert
    _PAD-SHARED-STALE @ 0<> _pr-assert
    _PAD-SHARED-BIND LBIND-VALID? 0= _pr-assert
    _pr-owner @ CINST.REVISION @ DUP _pr-owner-revision ! 4 = _pr-assert
    S" # Daybook\n\n> 2026-07-13 | post-commit Pad edit\n"
        S" /daybook.md" _pr-file= _pr-assert
    S" retry must wait for reload" _PAD-TXTA @ TXTA-SET-TEXT
    -1 _PAD-ACTIVE @ _PAD-BUF-ENTRY _PBE-DIRTY + !
    S" /daybook.md" _PAD-SAVE-CURRENT-AS _PAD-E-STALE = _pr-assert
    _pr-owner @ CINST.REVISION @ _pr-owner-revision @ = _pr-assert
    _pr-shared-index @ _PAD-BUF-CLOSE
    _pr-rid _pr-context @ _pr-ref _pr-rreg @ RREG-REF
        RREG-S-OK = _pr-assert
    _pr-ref _pr-open-request!
    _pr-dispatch-open CBUS-S-OK = _pr-assert
    S" # Daybook\n\n> 2026-07-13 | post-commit Pad edit\n"
        _pr-text= _pr-assert
    _PAD-FIND-SHARED-BUFFER DUP 0>= _pr-assert _pr-shared-index !

    \ An unrelated Pad buffer remains ordinary VFS data and cannot Save As
    \ over the canonical shared backing path while running inside Desk.
    _PAD-BUF-OPEN DUP 0>= _pr-assert DROP
    S" ordinary Pad bytes" _PAD-TXTA @ TXTA-SET-TEXT
    -1 _PAD-ACTIVE @ _PAD-BUF-ENTRY _PBE-DIRTY + !
    S" /ordinary.txt" _PAD-SAVE-CURRENT-AS 0= _pr-assert
    S" ordinary Pad bytes" S" /ordinary.txt" _pr-file= _pr-assert
    S" cannot clobber Daybook" _PAD-TXTA @ TXTA-SET-TEXT
    -1 _PAD-ACTIVE @ _PAD-BUF-ENTRY _PBE-DIRTY + !
    S" /daybook.md" _PAD-SAVE-CURRENT-AS
        _PAD-E-DAYBOOK-PROTECTED = _pr-assert
    _PAD-ACTIVE @ _PAD-BUF-ENTRY _PBE-DIRTY + @ 0<> _pr-assert
    S" # Daybook\n\n> 2026-07-13 | post-commit Pad edit\n"
        S" /daybook.md" _pr-file= _pr-assert
    SDLENS-M-BLOCKED _PAD-RESOURCE-MODE !
    S" /daybook.md" _PAD-SAVE-CURRENT-AS
        _PAD-E-SHARED-UNAVAILABLE = _pr-assert
    SDLENS-M-SHARED _PAD-RESOURCE-MODE !

    _pr-stack
    _pr-request @ ?DUP IF CBR-FREE THEN
    _pr-ext-request @ ?DUP IF CBR-FREE THEN
    _pr-pad-storage-free
    _pr-pad @ _pr-creg @ CREG-INST- 0= _pr-assert
    _pr-pad @ CINST-FREE
    _pr-owner @ SDOC-DEACTIVATE SDOC-S-OK = _pr-assert
    _pr-bus @ CBUS-FREE _pr-rreg @ RREG-FREE
    _pr-creg @ CREG-FREE _pr-context @ CTX-FREE
    _pr-vfs @ VFS-DESTROY
    _pr-stack
    _pr-fails @ 0= IF
        ." PAD RESOURCE CONTRACTS PASS " _pr-checks @ .
    ELSE
        ." PAD RESOURCE CONTRACTS FAIL " _pr-fails @ . ." / " _pr-checks @ .
    THEN CR ;

_pr-run
""",
        ready_markers=("PAD RESOURCE CONTRACTS PASS",),
        stable_markers=("PAD RESOURCE CONTRACTS PASS",),
        failure_markers=(
            "PAD RESOURCE CONTRACTS FAIL",
            "PAD RESOURCE ASSERT",
            "PAD RESOURCE STACK",
        ),
    ),
    "pad": Profile(
        roots=("tui/applets/pad/pad.f",),
        resources=(
            "tui/applets/pad/pad.uidl",
            "tui/applets/pad/pad.toml",
        ),
        autoexec=r"""\ autoexec.f - standalone Akashic Pad profile
ENTER-USERLAND
." [akashic] loading pad" CR
REQUIRE tui/applets/pad/pad.f
." [akashic] starting pad" CR
PAD-RUN
." [akashic] pad exited" CR
""",
        ready_markers=("File", "Edit", "UTF-8"),
        stable_markers=("File", "Edit", "UTF-8"),
    ),
    "fexplorer": Profile(
        roots=("tui/applets/fexplorer/fexplorer.f",),
        resources=(
            "tui/applets/fexplorer/fexplorer.uidl",
            "tui/applets/fexplorer/fexplorer.toml",
        ),
        autoexec=r"""\ autoexec.f - standalone File Explorer profile
ENTER-USERLAND
." [akashic] loading file explorer" CR
REQUIRE tui/applets/fexplorer/fexplorer.f
." [akashic] starting file explorer" CR
FEXP-RUN
." [akashic] file explorer exited" CR
""",
        ready_markers=("File", "Edit", "View", "Tools"),
        stable_markers=("File", "Edit", "View", "Tools"),
    ),
    "daybook": Profile(
        roots=("tui/applets/daybook/daybook.f",),
        resources=("tui/applets/daybook/daybook.uidl",),
        autoexec=r"""\ autoexec.f - standalone Daybook profile
ENTER-USERLAND
." [akashic] loading daybook" CR
REQUIRE tui/applets/daybook/daybook.f
." [akashic] starting daybook" CR
DAYBOOK-RUN
." [akashic] daybook exited" CR
""",
        ready_markers=("File", "Entry", "Go", "4 entries"),
        stable_markers=("File", "Entry", "Go", "entries"),
    ),
    "daybook-contracts": Profile(
        roots=("tui/applets/daybook/daybook.f",),
        resources=(),
        autoexec=r"""\ autoexec.f - strict Daybook import/persistence fixture
ENTER-USERLAND
." [akashic] loading Daybook contracts" CR
REQUIRE tui/applets/daybook/daybook.f

VARIABLE _dt-fails
VARIABLE _dt-checks
VARIABLE _dt-depth
VARIABLE _dt-inst
VARIABLE _dt-fd
VARIABLE _dt-old-vtable
VARIABLE _dt-read-calls
VARIABLE _dt-close-calls
VARIABLE _dt-use-calls
VARIABLE _dt-fd-head
VARIABLE _dt-fd-next
VARIABLE _dt-close-prompt
VARIABLE _dt-close-rgn
CREATE _dt-big _DB-IO-CAP 1+ ALLOT
CREATE _dt-vtable VFS-VT-SIZE ALLOT

: _dt-assert  ( flag -- )
    1 _dt-checks +!
    0= IF 1 _dt-fails +! ." ASSERT " _dt-checks @ . CR THEN ;
: _dt-stack  ( -- )
    DEPTH DUP _dt-depth @ <> IF
        ." STACK " _dt-depth @ . ." -> " DUP . CR .S CR
    THEN
    _dt-depth @ = _dt-assert ;
: _dt-line  ( a u -- ) _DB-IO-APPEND 10 _DB-IO-CHAR ;
: _dt-header  ( -- ) _DB-IO-RESET S" # Daybook" _dt-line 10 _DB-IO-CHAR ;
: _dt-canonical  ( -- )
    _dt-header
    S" - 2026-07-10 09:30 | Project review" _dt-line
    S" - [ ] 2026-07-10 | Send the draft" _dt-line
    S" > 2026-07-10 | A durable note" _dt-line ;
: _dt-seed  ( -- )
    _DB-CLEAR
    _DB-K-TASK 0 2026 7 10 DT-YMD>EPOCH -1 S" sentinel" _DB-ADD
    0= _dt-assert
    -1 _DB-DIRTY ! ;
: _dt-short-read  ( buf len offset inode vfs -- actual )
    DROP DROP DROP NIP
    1 _dt-read-calls +!
    _dt-read-calls @ 1 = IF 1- 0 MAX ELSE DROP 0 THEN ;
: _dt-short-reads-on  ( -- )
    _DB-VFS @ V.VTABLE @ DUP _dt-old-vtable !
    _dt-vtable VFS-VT-SIZE CMOVE
    ['] _dt-short-read _dt-vtable VFS-VT-READ CELLS + !
    _dt-vtable _DB-VFS @ V.VTABLE ! ;
: _dt-short-reads-off  ( -- )
    _dt-old-vtable @ _DB-VFS @ V.VTABLE ! ;
: _dt-after-close  ( fd -- )
    1 _dt-close-calls +! VFS-CLOSE -801 THROW ;
: _dt-after-restore  ( vfs -- )
    1 _dt-use-calls +!
    DUP VFS-USE
    _dt-use-calls @ 2 = IF DROP -802 THROW THEN
    DROP ;
: _dt-fd-snapshot  ( -- )
    _DB-VFS @ V.FDFREE @ DUP _dt-fd-head !
    ?DUP IF FD.FREE @ ELSE 0 THEN _dt-fd-next ! ;
: _dt-load-failure-clean?  ( -- )
    VFS-CUR 0= _dt-assert
    _DB-LOAD-FD @ 0= _dt-assert
    _DB-LOAD-HAVE-OLD-VFS @ 0= _dt-assert
    _DB-VFS @ V.FDFREE @ DUP _dt-fd-head @ = _dt-assert
    ?DUP IF FD.FREE @ ELSE 0 THEN _dt-fd-next @ = _dt-assert
    _DB-COUNT @ 1 = _dt-assert
    0 _DB-ENTRY _DB-E-TEXT + 8 S" sentinel" STR-STR= _dt-assert
    _DB-DIRTY @ _dt-assert _DB-SOURCE-BLOCKED @ _dt-assert ;
: _dt-model-canonical?  ( -- flag )
    _DB-COUNT @ 3 =
    0 _DB-ENTRY _DB-E-KIND + @ _DB-K-EVENT = AND
    1 _DB-ENTRY _DB-E-KIND + @ _DB-K-TASK = AND
    2 _DB-ENTRY _DB-E-KIND + @ _DB-K-NOTE = AND ;

: _dt-test-strict-import  ( -- )
    _dt-seed _dt-canonical _DB-PARSE-FILE _DB-L-S-OK = _dt-assert
    _dt-model-canonical? _dt-assert
    _DB-DIRTY @ _dt-assert

    _DB-COUNT @ >R -1 _DB-DIRTY !
    _dt-header S" unsupported markdown" _dt-line
    _DB-PARSE-FILE _DB-L-S-INVALID = _dt-assert
    _DB-COUNT @ R> = _dt-assert _DB-DIRTY @ _dt-assert
    _dt-model-canonical? _dt-assert

    _dt-header S" - [X] 2026-07-10 | not canonical" _dt-line
    _DB-PARSE-FILE _DB-L-S-INVALID = _dt-assert
    _dt-model-canonical? _dt-assert

    _dt-header S" - [ ] 2026-07-10 | " _DB-IO-APPEND
    121 0 DO [CHAR] a _DB-IO-CHAR LOOP 10 _DB-IO-CHAR
    _DB-PARSE-FILE _DB-L-S-TEXT = _dt-assert
    _dt-model-canonical? _dt-assert

    _dt-header
    97 0 DO S" - [ ] 2026-07-10 | x" _dt-line LOOP
    _DB-PARSE-FILE _DB-L-S-CAPACITY = _dt-assert
    _dt-model-canonical? _dt-assert _DB-DIRTY @ _dt-assert
    _dt-stack ;

: _dt-write-oversize  ( -- )
    _dt-big _DB-IO-CAP 1+ [CHAR] z FILL
    S" /daybook.md" VFS-OPEN DUP 0= IF
        DROP S" /daybook.md" _DB-VFS @ VFS-CREATE DROP
        S" /daybook.md" VFS-OPEN
    THEN
    DUP 0<> _dt-assert _dt-fd !
    0 _dt-fd @ VFS-TRUNCATE 0= _dt-assert
    _dt-big _DB-IO-CAP 1+ _dt-fd @ VFS-WRITE-EXACT 0= _dt-assert
    _dt-fd @ VFS-CLOSE ;

: _dt-test-load-and-replace  ( -- )
    _dt-seed _dt-write-oversize
    90 _DB-IO-BUF C! 0 _dt-read-calls ! _dt-short-reads-on
    _DB-READ-FILE _DB-L-S-TOO-LARGE = _dt-assert
    _dt-short-reads-off
    _dt-read-calls @ 0= _dt-assert
    _DB-IO-BUF C@ 90 = _dt-assert
    _DB-LOAD _DB-L-S-TOO-LARGE = _dt-assert
    _DB-COUNT @ 1 = _dt-assert _DB-DIRTY @ _dt-assert
    _DB-SOURCE-BLOCKED @ _dt-assert
    0 _DB-ENTRY _DB-E-TEXT + 8 S" sentinel" STR-STR= _dt-assert

    _dt-canonical _DB-PARSE-FILE _DB-L-S-OK = _dt-assert
    _DB-SERIALIZE _DB-WRITE 0<> _dt-assert
    _DB-READ-FILE _DB-L-S-TOO-LARGE = _dt-assert
    0 _DB-SOURCE-BLOCKED !
    _DB-SERIALIZE _DB-WRITE 0= _dt-assert
    _DB-CLEAR _DB-COUNT @ 0= _dt-assert
    _DB-LOAD _DB-L-S-OK = _dt-assert
    _dt-model-canonical? _dt-assert
    _DB-REPLACE VREPL-STAGE$ _DB-VFS @ VFS-RESOLVE 0= _dt-assert
    _DB-REPLACE VREPL-BACKUP$ _DB-VFS @ VFS-RESOLVE 0= _dt-assert
    _DB-REPLACE VREPL-MARKER$ _DB-VFS @ VFS-RESOLVE 0= _dt-assert

    -1 _DB-DIRTY ! 0 _dt-read-calls ! _dt-short-reads-on
    _DB-LOAD _DB-L-S-IO = _dt-assert
    _dt-short-reads-off
    _dt-read-calls @ 2 = _dt-assert
    _dt-model-canonical? _dt-assert _DB-DIRTY @ _dt-assert
    _DB-SOURCE-BLOCKED @ _dt-assert
    _DB-LOAD _DB-L-S-OK = _dt-assert
    _DB-SOURCE-BLOCKED @ 0= _dt-assert

    _DB-REPLACE _VRO-R !
    _VRO-TARGET>BACKUP 0= _dt-assert
    _DB-VFS @ VFS-SYNC 0= _dt-assert
    _DB-REPLACE VREPL-TARGET$ _DB-VFS @ VFS-RESOLVE 0= _dt-assert
    _DB-LOAD _DB-L-S-OK = _dt-assert
    _dt-model-canonical? _dt-assert
    _DB-REPLACE VREPL-TARGET$ _DB-VFS @ VFS-RESOLVE 0<> _dt-assert
    _DB-REPLACE VREPL-BACKUP$ _DB-VFS @ VFS-RESOLVE 0= _dt-assert

    _DB-REPLACE _VRO-R !
    S" bad" _DB-REPLACE VREPL-MARKER$ _VREPL-CREATE-WRITE
    VREPL-S-OK = _dt-assert
    -1 _DB-DIRTY !
    _DB-LOAD _DB-L-S-RECOVERY = _dt-assert
    _dt-model-canonical? _dt-assert _DB-DIRTY @ _dt-assert
    _DB-SOURCE-BLOCKED @ _dt-assert
    _DB-REPLACE VREPL-MARKER$ _DB-VFS @ VFS-RM 0= _dt-assert
    _DB-VFS @ VFS-SYNC 0= _dt-assert
    _dt-stack ;

: _dt-test-load-cleanup-faults  ( -- )
    _dt-seed 0 _DB-SOURCE-BLOCKED ! _dt-fd-snapshot
    0 _dt-close-calls ! 0 VFS-USE
    ['] _dt-after-close _DB-LOAD-CLOSE-XT !
    _DB-LOAD _DB-L-S-IO = _dt-assert
    _DB-RESET-LOAD-DEPENDENCIES
    _dt-close-calls @ 1 = _dt-assert
    _dt-load-failure-clean? _dt-stack
    _DB-VFS @ VFS-USE

    _dt-seed 0 _DB-SOURCE-BLOCKED ! _dt-fd-snapshot
    0 _dt-use-calls ! 0 VFS-USE
    ['] _dt-after-restore _DB-LOAD-USE-XT !
    _DB-LOAD _DB-L-S-IO = _dt-assert
    _DB-RESET-LOAD-DEPENDENCIES
    _dt-use-calls @ 2 = _dt-assert
    _dt-load-failure-clean? _dt-stack
    _DB-VFS @ VFS-USE
    _DB-LOAD _DB-L-S-OK = _dt-assert
    _DB-SOURCE-BLOCKED @ 0= _dt-assert ;

: _dt-test-close  ( -- )
    0 _DB-DIRTY !
    APP-CLOSE-R-WINDOW _dt-inst @ DAYBOOK-REQUEST-CLOSE-CB
    APP-CLOSE-D-ALLOW = _dt-assert
    -1 _DB-DIRTY ! 0 _DB-PROMPT ! 0 _DB-DISCARD-ARMED !
    APP-CLOSE-R-WINDOW _dt-inst @ DAYBOOK-REQUEST-CLOSE-CB
    APP-CLOSE-D-CANCEL = _dt-assert

    0 0 1 80 RGN-NEW DUP _dt-close-rgn ! _DB-PROMPT-RGN !
    _DB-PROMPT-BUF _DB-PROMPT-CAP PRM-NEW
    DUP _dt-close-prompt ! _DB-PROMPT !
    0 _DB-DO-RELOAD
    _DB-PROMPT-MODE @ _DB-PRM-DISCARD-RELOAD = _dt-assert
    _DB-PROMPT @ PRM-ACTIVE? _dt-assert _DB-DIRTY @ _dt-assert
    S" RELOAD" _DB-PROMPT @ _PRM-O-INPUT + @ INP-SET-TEXT
    _DB-PROMPT @ PRM-HIDE _DB-PROMPT @ _DB-PROMPT-SUBMIT
    _DB-DIRTY @ 0= _dt-assert _dt-model-canonical? _dt-assert

    -1 _DB-DIRTY !
    APP-CLOSE-R-WINDOW _dt-inst @ DAYBOOK-REQUEST-CLOSE-CB
    APP-CLOSE-D-DEFER = _dt-assert
    _DB-PROMPT-MODE @ _DB-PRM-DISCARD-CLOSE = _dt-assert
    _DB-PROMPT @ PRM-ACTIVE? _dt-assert
    APP-CLOSE-R-WINDOW _dt-inst @ DAYBOOK-REQUEST-CLOSE-CB
    APP-CLOSE-D-DEFER = _dt-assert

    S" discard" _DB-PROMPT @ _PRM-O-INPUT + @ INP-SET-TEXT
    _DB-PROMPT @ PRM-HIDE _DB-PROMPT @ _DB-PROMPT-SUBMIT
    _DB-DISCARD-ARMED @ 0= _dt-assert
    _DB-PROMPT @ PRM-ACTIVE? _dt-assert
    S" DISCARD" _DB-PROMPT @ _PRM-O-INPUT + @ INP-SET-TEXT
    _DB-PROMPT @ PRM-HIDE _DB-PROMPT @ _DB-PROMPT-SUBMIT
    _DB-DISCARD-ARMED @ _dt-assert
    ASHELL-QUIT-PENDING? _dt-assert
    APP-CLOSE-R-WINDOW _dt-inst @ DAYBOOK-REQUEST-CLOSE-CB
    APP-CLOSE-D-ALLOW = _dt-assert
    _DB-DISCARD-ARMED @ 0= _dt-assert
    ASHELL-CANCEL-QUIT
    _dt-close-prompt @ PRM-FREE 0 _DB-PROMPT !
    _dt-close-rgn @ RGN-FREE 0 _DB-PROMPT-RGN !
    _dt-stack ;

: _dt-run  ( -- )
    0 _dt-fails ! 0 _dt-checks ! DEPTH _dt-depth !
    _DAYBOOK-COMP-SETUP
    DAYBOOK-COMP-DESC CINST-NEW DUP 0= _dt-assert DROP _dt-inst !
    _dt-inst @ _DB-ACTIVATE
    VFS-CUR DUP 0<> _dt-assert _DB-VFS !
    _DB-VFS @ _DB-REPLACE VREPL-INIT VREPL-S-OK = _dt-assert
    S" /daybook.md" _DB-REPLACE VREPL-DERIVE-PATHS!
    VREPL-S-OK = _dt-assert
    _dt-test-strict-import
    _dt-test-load-and-replace
    _dt-test-load-cleanup-faults
    _dt-test-close
    _dt-inst @ CINST-FREE
    _dt-stack
    _dt-fails @ 0= IF
        ." DAYBOOK CONTRACTS PASS " _dt-checks @ .
    ELSE
        ." DAYBOOK CONTRACTS FAIL " _dt-fails @ . ." / " _dt-checks @ .
    THEN CR ;

_dt-run
""",
        ready_markers=("DAYBOOK CONTRACTS PASS",),
        stable_markers=("DAYBOOK CONTRACTS PASS",),
    ),
    "grid-eval": Profile(
        roots=("tui/applets/grid/grid.f",),
        resources=(),
        autoexec=r"""\ autoexec.f - focused Grid dependency evaluator bounds
ENTER-USERLAND
." [akashic] loading grid evaluator" CR
REQUIRE tui/applets/grid/grid.f

VARIABLE _gt-fails
VARIABLE _gt-checks
VARIABLE _gt-depth
VARIABLE _gt-canary
CREATE _gt-state _GRID-STATE-SIZE ALLOT

: _gt-assert  ( flag -- )
    1 _gt-checks +!
    0= IF 1 _gt-fails +! ." ASSERT " _gt-checks @ . CR THEN ;
: _gt-stack  ( -- )
    DEPTH DUP _gt-depth @ <> IF
        ." STACK " _gt-depth @ . ." -> " DUP . CR .S CR
    THEN
    _gt-depth @ = _gt-assert ;
: _gt-status  ( row col -- status )
    _GRID-CELL _GC-STATUS + @ ;
: _gt-value  ( row col -- value )
    _GRID-CELL _GC-VALUE + @ ;

: _gt-links-19  ( -- )
    S" =A2"   0 0 _GRID-SET-CELL
    S" =A3"   1 0 _GRID-SET-CELL
    S" =A4"   2 0 _GRID-SET-CELL
    S" =A5"   3 0 _GRID-SET-CELL
    S" =A6"   4 0 _GRID-SET-CELL
    S" =A7"   5 0 _GRID-SET-CELL
    S" =A8"   6 0 _GRID-SET-CELL
    S" =A9"   7 0 _GRID-SET-CELL
    S" =A10"  8 0 _GRID-SET-CELL
    S" =A11"  9 0 _GRID-SET-CELL
    S" =A12" 10 0 _GRID-SET-CELL
    S" =A13" 11 0 _GRID-SET-CELL
    S" =A14" 12 0 _GRID-SET-CELL
    S" =A15" 13 0 _GRID-SET-CELL
    S" =A16" 14 0 _GRID-SET-CELL
    S" =A17" 15 0 _GRID-SET-CELL
    S" =A18" 16 0 _GRID-SET-CELL
    S" =A19" 17 0 _GRID-SET-CELL
    S" =A20" 18 0 _GRID-SET-CELL ;

: _gt-chain-20  ( -- )
    _GRID-CLEAR-MODEL _gt-links-19
    S" 7" 19 0 _GRID-SET-CELL
    _GRID-RECALCULATE ;

: _gt-chain-21  ( -- )
    _GRID-CLEAR-MODEL _gt-links-19
    S" =A21" 19 0 _GRID-SET-CELL
    S" 7" 20 0 _GRID-SET-CELL
    _GRID-RECALCULATE ;

: _gt-capacity-reject  ( -- )
    _GE-CELL-STACK _GRID-EVAL-DEPTH CELLS + @ _gt-canary !
    _GRID-EVAL-DEPTH _GE-DEPTH !
    _GRID-CELLS @ _GE-PUSH 0= _gt-assert DROP
    _GE-DEPTH @ _GRID-EVAL-DEPTH = _gt-assert
    _GE-CELL-STACK _GRID-EVAL-DEPTH CELLS + @
    _gt-canary @ = _gt-assert
    0 _GE-DEPTH ! ;

: _gt-run  ( -- )
    0 _gt-fails ! 0 _gt-checks ! DEPTH _gt-depth !
    _gt-state _GRID-STATE-SIZE 0 FILL
    _gt-state _GRID-CURRENT-STATE !
    _GRID-ROWS _GRID-COLS * _GRID-CELL-SZ * ALLOCATE
    DUP 0= _gt-assert
    0<> IF DROP 1 _gt-fails +! EXIT THEN
    _GRID-CELLS !

    _gt-capacity-reject
    _gt-stack

    _gt-chain-20
    0 0 _gt-status _GRID-ST-FORMULA = _gt-assert
    0 0 _gt-value 7 = _gt-assert
    19 0 _gt-status _GRID-ST-NUMBER = _gt-assert
    _GE-DEPTH @ 0= _gt-assert
    _GP-DEPTH @ 0= _gt-assert
    _gt-stack

    _gt-chain-21
    0 0 _gt-status _GRID-ST-DEPTH = _gt-assert
    19 0 _gt-status _GRID-ST-DEPTH = _gt-assert
    20 0 _gt-status _GRID-ST-DEPTH = _gt-assert
    0 0 _gt-status _GRID-ST-ERROR? _gt-assert
    _GE-DEPTH @ 0= _gt-assert
    _GP-DEPTH @ 0= _gt-assert
    _GRID-RECALCULATE
    0 0 _gt-status _GRID-ST-DEPTH = _gt-assert
    _gt-stack

    _GRID-CLEAR-MODEL
    S" =A2" 0 0 _GRID-SET-CELL
    S" =A1" 1 0 _GRID-SET-CELL
    _GRID-RECALCULATE
    0 0 _gt-status _GRID-ST-CYCLE = _gt-assert
    1 0 _gt-status _GRID-ST-CYCLE = _gt-assert
    0 0 _gt-status _GRID-ST-ERROR? _gt-assert
    _GE-DEPTH @ 0= _gt-assert
    _GP-DEPTH @ 0= _gt-assert
    _gt-stack

    _GRID-CLEAR-MODEL
    S" =1/0" 0 0 _GRID-SET-CELL
    _GRID-RECALCULATE
    0 0 _gt-status _GRID-ST-ERROR = _gt-assert

    S" =A2" 0 0 _GRID-SET-CELL
    S" 7" 1 0 _GRID-SET-CELL
    _GRID-RECALCULATE
    0 0 _gt-status _GRID-ST-FORMULA = _gt-assert
    0 0 _gt-value 7 = _gt-assert
    _gt-stack

    _GRID-CELLS @ FREE 0 _GRID-CELLS !
    _gt-stack
    _gt-fails @ 0= IF
        ." GRID EVAL PASS " _gt-checks @ .
    ELSE
        ." GRID EVAL FAIL " _gt-fails @ . ." / " _gt-checks @ .
    THEN CR ;

_gt-run
""",
        ready_markers=("GRID EVAL PASS",),
        stable_markers=("GRID EVAL PASS",),
        failure_markers=("GRID EVAL FAIL",),
    ),
    "grid-contracts": Profile(
        roots=("tui/applets/grid/grid.f",),
        resources=(),
        autoexec=r"""\ autoexec.f - strict Grid import/persistence contracts
ENTER-USERLAND
." [akashic] loading Grid contracts" CR
REQUIRE tui/applets/grid/grid.f

VARIABLE _gcx-fails
VARIABLE _gcx-checks
VARIABLE _gcx-depth
VARIABLE _gcx-inst
VARIABLE _gcx-fd
VARIABLE _gcx-a
VARIABLE _gcx-u
VARIABLE _gcx-r
VARIABLE _gcx-c
VARIABLE _gcx-old-vtable
VARIABLE _gcx-read-calls
VARIABLE _gcx-close-calls
VARIABLE _gcx-use-calls
VARIABLE _gcx-fd-head
VARIABLE _gcx-fd-next
CREATE _gcx-vtable VFS-VT-SIZE ALLOT
CREATE _gcx-check 256 ALLOT
CREATE _gcx-corrupt 7 ALLOT
CREATE _gcx-quoted 6 ALLOT
CREATE _gcx-saved 4 ALLOT
CREATE _gcx-desc APP-DESC ALLOT

: _gcx-assert  ( flag -- )
    1 _gcx-checks +!
    0= IF 1 _gcx-fails +! ." ASSERT " _gcx-checks @ . CR THEN ;
: _gcx-stack  ( -- )
    DEPTH DUP _gcx-depth @ <> IF
        ." STACK " _gcx-depth @ . ." -> " DUP . CR .S CR
    THEN
    _gcx-depth @ = _gcx-assert ;
: _gcx-cell=  ( a u row col -- flag )
    _gcx-c ! _gcx-r ! _gcx-u ! _gcx-a !
    _gcx-r @ _gcx-c @ _GRID-CELL
    DUP _GC-LEN + @ _gcx-u @ <> IF DROP 0 EXIT THEN
    _GC-SOURCE + _gcx-u @ _gcx-a @ _gcx-u @ COMPARE 0= ;
: _gcx-model-canonical?  ( -- flag )
    S" alpha" 0 0 _gcx-cell=
    S" be,ta" 0 1 _gcx-cell= AND
    _gcx-quoted 6 1 0 _gcx-cell= AND
    S" =A1" 1 1 _gcx-cell= AND
    _GRID-MAX-ROW @ 1 = AND _GRID-MAX-COL @ 1 = AND ;

: _gcx-artifacts-init  ( -- )
    [CHAR] " _gcx-corrupt C!
    [CHAR] x _gcx-corrupt 1+ C!
    [CHAR] " _gcx-corrupt 2 + C!
    [CHAR] j _gcx-corrupt 3 + C!
    [CHAR] u _gcx-corrupt 4 + C!
    [CHAR] n _gcx-corrupt 5 + C!
    [CHAR] k _gcx-corrupt 6 + C!
    [CHAR] q _gcx-quoted C!
    [CHAR] " _gcx-quoted 1+ C!
    [CHAR] u _gcx-quoted 2 + C!
    [CHAR] o _gcx-quoted 3 + C!
    [CHAR] t _gcx-quoted 4 + C!
    [CHAR] e _gcx-quoted 5 + C!
    S" new" _gcx-saved SWAP CMOVE
    10 _gcx-saved 3 + C! ;

: _gcx-canonical-io  ( -- )
    0 _GRID-IO-ERROR ! _GIO-RESET
    S" alpha," _GIO-APPEND
    [CHAR] " _GIO-CHAR S" be,ta" _GIO-APPEND [CHAR] " _GIO-CHAR
    13 _GIO-CHAR 10 _GIO-CHAR
    [CHAR] " _GIO-CHAR S" q" _GIO-APPEND
    [CHAR] " _GIO-CHAR [CHAR] " _GIO-CHAR
    S" uote" _GIO-APPEND [CHAR] " _GIO-CHAR
    [CHAR] , _GIO-CHAR S" =A1" _GIO-APPEND 10 _GIO-CHAR ;

: _gcx-seed  ( -- )
    _GRID-CLEAR-MODEL
    S" sentinel" 0 0 _GRID-SET-CELL
    _GRID-RECALCULATE -1 _GRID-DIRTY ! 0 _GRID-SOURCE-BLOCKED ! ;

: _gcx-invalid  ( expected-status -- )
    _GRID-PARSE-CSV = _gcx-assert
    _gcx-model-canonical? _gcx-assert
    _GRID-DIRTY @ _gcx-assert
    _GRID-SOURCE-BLOCKED @ 0= _gcx-assert ;

: _gcx-put  ( a u -- )
    _gcx-u ! _gcx-a !
    S" /grid.csv" VFS-OPEN DUP 0= IF
        DROP S" /grid.csv" _GRID-VFS @ VFS-CREATE 0<> _gcx-assert
        S" /grid.csv" VFS-OPEN
    THEN
    DUP 0<> _gcx-assert _gcx-fd !
    0 _gcx-fd @ VFS-TRUNCATE 0= _gcx-assert
    _gcx-a @ _gcx-u @ _gcx-fd @ VFS-WRITE-EXACT 0= _gcx-assert
    _gcx-fd @ VFS-CLOSE
    _GRID-VFS @ VFS-SYNC 0= _gcx-assert ;

: _gcx-file=  ( a u -- flag )
    _gcx-u ! _gcx-a !
    S" /grid.csv" VFS-OPEN DUP 0= IF DROP 0 EXIT THEN _gcx-fd !
    _gcx-fd @ VFS-SIZE _gcx-u @ <> IF
        _gcx-fd @ VFS-CLOSE 0 EXIT
    THEN
    _gcx-u @ 256 > IF _gcx-fd @ VFS-CLOSE 0 EXIT THEN
    _gcx-check _gcx-u @ _gcx-fd @ VFS-READ-EXACT IF
        _gcx-fd @ VFS-CLOSE 0 EXIT
    THEN
    _gcx-fd @ VFS-CLOSE
    _gcx-check _gcx-u @ _gcx-a @ _gcx-u @ COMPARE 0= ;

: _gcx-short-read  ( buf len offset inode vfs -- actual )
    DROP DROP DROP NIP
    1 _gcx-read-calls +!
    _gcx-read-calls @ 1 = IF 1- 0 MAX ELSE DROP 0 THEN ;
: _gcx-fail-sync  ( inode vfs -- ior ) 2DROP -1 ;
: _gcx-vtable-save  ( -- )
    _GRID-VFS @ V.VTABLE @ DUP _gcx-old-vtable !
    _gcx-vtable VFS-VT-SIZE CMOVE ;
: _gcx-vtable-restore  ( -- )
    _gcx-old-vtable @ _GRID-VFS @ V.VTABLE ! ;
: _gcx-short-reads-on  ( -- )
    _gcx-vtable-save
    ['] _gcx-short-read _gcx-vtable VFS-VT-READ CELLS + !
    _gcx-vtable _GRID-VFS @ V.VTABLE ! ;
: _gcx-sync-fails-on  ( -- )
    _gcx-vtable-save
    ['] _gcx-fail-sync _gcx-vtable VFS-VT-SYNC CELLS + !
    _gcx-vtable _GRID-VFS @ V.VTABLE ! ;
: _gcx-after-close  ( fd -- )
    1 _gcx-close-calls +! VFS-CLOSE -811 THROW ;
: _gcx-after-restore  ( vfs -- )
    1 _gcx-use-calls +!
    DUP VFS-USE
    _gcx-use-calls @ 2 = IF DROP -812 THROW THEN
    DROP ;
: _gcx-fd-snapshot  ( -- )
    _GRID-VFS @ V.FDFREE @ DUP _gcx-fd-head !
    ?DUP IF FD.FREE @ ELSE 0 THEN _gcx-fd-next ! ;
: _gcx-load-failure-clean?  ( -- )
    VFS-CUR 0= _gcx-assert
    _GRID-LOAD-FD @ 0= _gcx-assert
    _GRID-LOAD-HAVE-OLD-VFS @ 0= _gcx-assert
    _GRID-VFS @ V.FDFREE @ DUP _gcx-fd-head @ = _gcx-assert
    ?DUP IF FD.FREE @ ELSE 0 THEN _gcx-fd-next @ = _gcx-assert
    S" sentinel" 0 0 _gcx-cell= _gcx-assert
    _GRID-DIRTY @ _gcx-assert _GRID-SOURCE-BLOCKED @ _gcx-assert ;

: _gcx-test-parser  ( -- )
    _gcx-canonical-io
    _GRID-PARSE-CSV _GRID-L-S-OK = _gcx-assert
    _gcx-model-canonical? _gcx-assert
    -1 _GRID-DIRTY ! 0 _GRID-SOURCE-BLOCKED !

    0 _GRID-IO-ERROR ! _GIO-RESET
    41 0 DO [CHAR] a _GIO-CHAR LOOP
    _GRID-IO-BUF @ _GRID-IO-U @ 0 0 _GRID-SET-CELL
    _gcx-model-canonical? _gcx-assert
    _GRID-L-S-FIELD _gcx-invalid

    0 _GRID-IO-ERROR ! _GIO-RESET
    16 0 DO [CHAR] , _GIO-CHAR LOOP [CHAR] x _GIO-CHAR
    _GRID-L-S-CAPACITY _gcx-invalid

    0 _GRID-IO-ERROR ! _GIO-RESET
    65 0 DO S" x" _GIO-APPEND 10 _GIO-CHAR LOOP
    _GRID-L-S-CAPACITY _gcx-invalid

    0 _GRID-IO-ERROR ! _GIO-RESET
    _gcx-corrupt 7 _GIO-APPEND
    _GRID-L-S-INVALID _gcx-invalid

    0 _GRID-IO-ERROR ! _GIO-RESET
    [CHAR] " _GIO-CHAR S" x" _GIO-APPEND
    _GRID-L-S-INVALID _gcx-invalid

    0 _GRID-IO-ERROR ! _GIO-RESET
    S" a" _GIO-APPEND [CHAR] " _GIO-CHAR S" b" _GIO-APPEND
    _GRID-L-S-INVALID _gcx-invalid

    0 _GRID-IO-ERROR ! _GIO-RESET
    S" a" _GIO-APPEND 13 _GIO-CHAR S" b" _GIO-APPEND
    _GRID-L-S-INVALID _gcx-invalid

    0 _GRID-IO-ERROR ! _GIO-RESET
    [CHAR] " _GIO-CHAR S" x" _GIO-APPEND [CHAR] " _GIO-CHAR
    BL _GIO-CHAR
    _GRID-L-S-INVALID _gcx-invalid

    0 _GRID-IO-ERROR ! _GIO-RESET
    _GRID-ROWS 0 DO
        _GRID-COLS 0 DO
            S" x" _GIO-APPEND
            I _GRID-COLS 1- < IF [CHAR] , _GIO-CHAR THEN
        LOOP
        10 _GIO-CHAR
    LOOP
    _GRID-PARSE-CSV _GRID-L-S-OK = _gcx-assert
    _GRID-MAX-ROW @ _GRID-ROWS 1- = _gcx-assert
    _GRID-MAX-COL @ _GRID-COLS 1- = _gcx-assert

    0 _GRID-IO-ERROR ! _GIO-RESET
    _GRID-SOURCE-CAP 0 DO [CHAR] z _GIO-CHAR LOOP
    _GRID-PARSE-CSV _GRID-L-S-OK = _gcx-assert
    0 0 _GRID-CELL _GC-LEN + @ _GRID-SOURCE-CAP = _gcx-assert
    _gcx-stack ;

: _gcx-test-load-save  ( -- )
    _gcx-seed
    _GRID-IO-CAP 1+ ALLOCATE IF -2 THROW THEN
    DUP >R _GRID-IO-CAP 1+ [CHAR] z FILL
    R@ _GRID-IO-CAP 1+ _gcx-put R> FREE
    90 _GRID-IO-BUF @ C! 0 _gcx-read-calls ! _gcx-short-reads-on
    _GRID-LOAD _GRID-L-S-TOO-LARGE = _gcx-assert
    _gcx-vtable-restore
    _gcx-read-calls @ 0= _gcx-assert
    _GRID-IO-BUF @ C@ 90 = _gcx-assert
    S" sentinel" 0 0 _gcx-cell= _gcx-assert
    _GRID-DIRTY @ _gcx-assert _GRID-SOURCE-BLOCKED @ _gcx-assert

    _gcx-canonical-io
    _GRID-IO-BUF @ _GRID-IO-U @ _gcx-put
    _gcx-seed 0 _gcx-read-calls ! _gcx-short-reads-on
    _GRID-LOAD _GRID-L-S-IO = _gcx-assert
    _gcx-vtable-restore
    _gcx-read-calls @ 2 = _gcx-assert
    S" sentinel" 0 0 _gcx-cell= _gcx-assert
    _GRID-DIRTY @ _gcx-assert _GRID-SOURCE-BLOCKED @ _gcx-assert
    _GRID-LOAD _GRID-L-S-OK = _gcx-assert
    _gcx-model-canonical? _gcx-assert
    _GRID-SOURCE-BLOCKED @ 0= _gcx-assert _GRID-DIRTY @ _gcx-assert

    _gcx-corrupt 7 _gcx-put
    _GRID-LOAD _GRID-L-S-INVALID = _gcx-assert
    _gcx-model-canonical? _gcx-assert
    _GRID-DIRTY @ _gcx-assert _GRID-SOURCE-BLOCKED @ _gcx-assert
    _GRID-SERIALIZE _GRID-L-S-OK = _gcx-assert
    _GRID-WRITE _GRID-L-S-RECOVERY = _gcx-assert
    _gcx-corrupt 7 _gcx-file= _gcx-assert

    S" old" _gcx-put
    _GRID-LOAD _GRID-L-S-OK = _gcx-assert
    _GRID-SOURCE-BLOCKED @ 0= _gcx-assert
    S" new" 0 0 _GRID-SET-CELL -1 _GRID-DIRTY !
    _gcx-sync-fails-on
    _GRID-SAVE 0<> _gcx-assert
    _gcx-vtable-restore
    S" old" _gcx-file= _gcx-assert
    _GRID-DIRTY @ _gcx-assert _GRID-SOURCE-BLOCKED @ 0= _gcx-assert
    _GRID-SAVE 0= _gcx-assert
    _gcx-saved 4 _gcx-file= _gcx-assert
    _GRID-DIRTY @ 0= _gcx-assert _GRID-SOURCE-BLOCKED @ 0= _gcx-assert
    _GRID-REPLACE VREPL-STAGE$ _GRID-VFS @ VFS-RESOLVE 0= _gcx-assert
    _GRID-REPLACE VREPL-BACKUP$ _GRID-VFS @ VFS-RESOLVE 0= _gcx-assert
    _GRID-REPLACE VREPL-MARKER$ _GRID-VFS @ VFS-RESOLVE 0= _gcx-assert
    _gcx-stack ;

: _gcx-test-load-cleanup-faults  ( -- )
    _gcx-seed _gcx-fd-snapshot
    0 _gcx-close-calls ! 0 VFS-USE
    ['] _gcx-after-close _GRID-LOAD-CLOSE-XT !
    _GRID-LOAD _GRID-L-S-IO = _gcx-assert
    _GRID-RESET-LOAD-DEPENDENCIES
    _gcx-close-calls @ 1 = _gcx-assert
    _gcx-load-failure-clean? _gcx-stack
    _GRID-VFS @ VFS-USE

    _gcx-seed _gcx-fd-snapshot
    0 _gcx-use-calls ! 0 VFS-USE
    ['] _gcx-after-restore _GRID-LOAD-USE-XT !
    _GRID-LOAD _GRID-L-S-IO = _gcx-assert
    _GRID-RESET-LOAD-DEPENDENCIES
    _gcx-use-calls @ 2 = _gcx-assert
    _gcx-load-failure-clean? _gcx-stack
    _GRID-VFS @ VFS-USE
    _GRID-LOAD _GRID-L-S-OK = _gcx-assert
    _GRID-SOURCE-BLOCKED @ 0= _gcx-assert ;

: _gcx-run  ( -- )
    0 _gcx-fails ! 0 _gcx-checks ! DEPTH _gcx-depth !
    _gcx-artifacts-init
    _GRID-COMP-SETUP
    GRID-COMP-DESC CINST-NEW DUP 0= _gcx-assert DROP _gcx-inst !
    _gcx-inst @ _GRID-ACTIVATE
    _GRID-ROWS _GRID-COLS * _GRID-CELL-SZ * ALLOCATE
    IF -2 THROW THEN _GRID-CELLS !
    _GRID-IO-CAP ALLOCATE IF -2 THROW THEN _GRID-IO-BUF !
    VFS-CUR DUP 0<> _gcx-assert _GRID-VFS !
    _GRID-VFS @ _GRID-REPLACE VREPL-INIT VREPL-S-OK = _gcx-assert
    S" /grid.csv" _GRID-REPLACE VREPL-DERIVE-PATHS!
    VREPL-S-OK = _gcx-assert
    _GRID-CLEAR-MODEL 0 _GRID-DIRTY ! 0 _GRID-SOURCE-BLOCKED !

    _gcx-test-parser
    _gcx-test-load-save
    _gcx-test-load-cleanup-faults

    _gcx-desc GRID-ENTRY
    _gcx-desc APP.REQUEST-CLOSE-XT @
    ['] GRID-REQUEST-CLOSE-CB = _gcx-assert
    0 _GRID-DIRTY !
    APP-CLOSE-R-WINDOW _gcx-inst @ GRID-REQUEST-CLOSE-CB
    APP-CLOSE-D-ALLOW = _gcx-assert

    _GRID-CELLS @ FREE 0 _GRID-CELLS !
    _GRID-IO-BUF @ FREE 0 _GRID-IO-BUF !
    _gcx-inst @ CINST-FREE
    _gcx-stack
    _gcx-fails @ 0= IF
        ." GRID CONTRACTS PASS " _gcx-checks @ .
    ELSE
        ." GRID CONTRACTS FAIL " _gcx-fails @ . ." / " _gcx-checks @ .
    THEN CR ;

_gcx-run
""",
        ready_markers=("GRID CONTRACTS PASS",),
        stable_markers=("GRID CONTRACTS PASS",),
        failure_markers=("GRID CONTRACTS FAIL",),
    ),
    "grid": Profile(
        roots=("tui/applets/grid/grid.f",),
        resources=("tui/applets/grid/grid.uidl",),
        autoexec=r"""\ autoexec.f - standalone Grid profile
ENTER-USERLAND
." [akashic] loading grid" CR
REQUIRE tui/applets/grid/grid.f
." [akashic] starting grid" CR
GRID-RUN
." [akashic] grid exited" CR
""",
        ready_markers=("File", "Edit", "Data", "Grid"),
        stable_markers=("File", "Edit", "Data", "Grid"),
    ),
}

PROFILES["manifest-contracts"] = Profile(
    roots=(
        "tui/app-manifest.f",
        "utils/fs/drivers/vfs-mp64fs.f",
    ),
    resources=(),
    autoexec=r"""\ autoexec.f - trusted-local app manifest contracts
ENTER-USERLAND
REQUIRE tui/app-manifest.f
REQUIRE utils/fs/drivers/vfs-mp64fs.f

VARIABLE _mc-fails
VARIABLE _mc-checks
VARIABLE _mc-depth
VARIABLE _mc-vfs
VARIABLE _mc-fd
VARIABLE _mc-doc
VARIABLE _mc-doc-u
VARIABLE _mc-mft

: _mc-assert  ( flag -- )
    1 _mc-checks +!
    0= IF 1 _mc-fails +! ." ASSERT " _mc-checks @ . CR THEN ;
: _mc-stack  ( -- ) DEPTH _mc-depth @ = _mc-assert ;

: _mc-read  ( path-a path-u -- status )
    VFS-OPEN DUP _mc-fd ! 0= IF -1 EXIT THEN
    _mc-fd @ VFS-SIZE DUP _mc-doc-u !
    1 MAX ALLOCATE DUP IF
        2DROP _mc-fd @ VFS-CLOSE 0 _mc-fd ! -2 EXIT
    THEN
    DROP _mc-doc !
    _mc-doc @ _mc-doc-u @ _mc-fd @ VFS-READ-EXACT IF
        _mc-fd @ VFS-CLOSE 0 _mc-fd !
        _mc-doc @ FREE 0 _mc-doc ! -3 EXIT
    THEN
    _mc-fd @ VFS-CLOSE 0 _mc-fd ! 0 ;

: _mc-parse  ( path-a path-u -- status )
    _mc-read DUP IF EXIT THEN DROP
    _mc-doc @ _mc-doc-u @ MFT-PARSE
    DUP IF NIP 0 _mc-mft ! EXIT THEN
    DROP _mc-mft ! 0 ;

: _mc-clean  ( -- )
    _mc-mft @ ?DUP IF MFT-FREE 0 _mc-mft ! THEN
    _mc-doc @ ?DUP IF FREE 0 _mc-doc ! THEN ;

: _mc-project  ( -- )
    S" /project.toml" _mc-parse 0= _mc-assert
    _mc-mft @ 0<> _mc-assert
    _mc-mft @ MFT-VALIDATE-PROJECT MFT-S-OK = _mc-assert
    _mc-mft @ MFT-VALIDATE-INSTALLED MFT-E-DIGEST = _mc-assert
    _mc-mft @ MFT-ID S" local.hello" COMPARE 0= _mc-assert
    _mc-mft @ MFT-TITLE S" local.hello" COMPARE 0= _mc-assert
    _mc-mft @ MFT-ENTRY S" HELLO-ENTRY" COMPARE 0= _mc-assert
    _mc-mft @ MFT-SOURCE S" /hello.f" COMPARE 0= _mc-assert
    _mc-clean _mc-stack ;

: _mc-installed  ( -- )
    S" /installed.toml" _mc-parse 0= _mc-assert
    _mc-mft @ MFT-VALIDATE-INSTALLED MFT-S-OK = _mc-assert
    _mc-mft @ MFT-IMAGE S" /.i0123456789ab.m64" COMPARE 0= _mc-assert
    _mc-mft @ MFT-WIDTH 40 = _mc-assert
    _mc-mft @ MFT-HEIGHT 8 = _mc-assert
    _mc-clean _mc-stack ;

: _mc-reject  ( path-a path-u expected -- )
    >R _mc-parse R> = _mc-assert
    _mc-mft @ 0= _mc-assert
    _mc-clean _mc-stack ;

: _mc-run  ( -- )
    0 _mc-fails ! 0 _mc-checks ! DEPTH _mc-depth !
    MFT-SIZE 256 = _mc-assert
    2097152 A-XMEM ARENA-NEW
    DUP 0= _mc-assert DROP
    VMP-NEW DUP _mc-vfs ! VMP-INIT 0= _mc-assert
    _mc-project
    _mc-installed
    S" /bad-trust.toml" MFT-E-TRUST _mc-reject
    S" /bad-path.toml" MFT-E-BOUNDS _mc-reject
    S" /bad-type.toml" MFT-E-TYPE _mc-reject
    S" /missing.toml" MFT-E-MISSING _mc-reject
    _mc-fails @ 0= IF
        ." MANIFEST CONTRACTS PASS " _mc-checks @ .
    ELSE
        ." MANIFEST CONTRACTS FAIL " _mc-fails @ . ." / " _mc-checks @ .
    THEN CR ;

_mc-run
""",
    ready_markers=("MANIFEST CONTRACTS PASS",),
    stable_markers=("MANIFEST CONTRACTS PASS",),
    failure_markers=("MANIFEST CONTRACTS FAIL",),
    initial_files=(
        (
            "project.toml",
            b'''[package]\nformat = 1\ntrust = "local"\nsource = "/hello.f"\n\n[app]\nid = "local.hello"\nversion = "0.1.0"\nabi = 1\nentry = "HELLO-ENTRY"\n''',
        ),
        (
            "installed.toml",
            b'''[package]\nformat = 1\ntrust = "local"\nsource = "/hello.f"\nsource-sha3 = "0000000000000000000000000000000000000000000000000000000000000000"\nimage = "/.i0123456789ab.m64"\nimage-sha3 = "1111111111111111111111111111111111111111111111111111111111111111"\n\n[app]\nid = "local.hello"\ntitle = "Hello"\nversion = "0.1.0"\nabi = 1\nentry = "HELLO-ENTRY"\nwidth = 40\nheight = 8\n''',
        ),
        (
            "bad-trust.toml",
            b'''[package]\nformat = 1\ntrust = "remote"\nsource = "/hello.f"\n\n[app]\nid = "local.hello"\nversion = "0.1.0"\nabi = 1\nentry = "HELLO-ENTRY"\n''',
        ),
        (
            "bad-path.toml",
            b'''[package]\nformat = 1\ntrust = "local"\nsource = "/../hello.f"\n\n[app]\nid = "local.hello"\nversion = "0.1.0"\nabi = 1\nentry = "HELLO-ENTRY"\n''',
        ),
        (
            "bad-type.toml",
            b'''[package]\nformat = "one"\ntrust = "local"\nsource = "/hello.f"\n\n[app]\nid = "local.hello"\nversion = "0.1.0"\nabi = 1\nentry = "HELLO-ENTRY"\n''',
        ),
        (
            "missing.toml",
            b'''[package]\nformat = 1\ntrust = "local"\nsource = "/hello.f"\n\n[app]\nid = "local.hello"\nversion = "0.1.0"\nabi = 1\n''',
        ),
    ),
)

PROFILES["package-contracts"] = Profile(
    roots=(
        "tui/app-builder.f",
        "tui/app-loader.f",
        "tui/draw.f",
        "utils/fs/drivers/vfs-mp64fs.f",
    ),
    resources=(),
    autoexec=r"""\ autoexec.f - trusted-local creator spine contracts
ENTER-USERLAND
REQUIRE tui/app-builder.f
REQUIRE tui/app-loader.f
REQUIRE tui/draw.f
REQUIRE utils/fs/drivers/vfs-mp64fs.f

VARIABLE _pkg-fails
VARIABLE _pkg-checks
VARIABLE _pkg-depth
VARIABLE _pkg-vfs
VARIABLE _pkg-cat
VARIABLE _pkg-entry
VARIABLE _pkg-status
VARIABLE _pkg-desc
VARIABLE _pkg-inst
VARIABLE _pkg-doc
VARIABLE _pkg-doc-u
VARIABLE _pkg-fd
VARIABLE _pkg-mft
VARIABLE _pkg-mut
VARIABLE _pkg-byte
VARIABLE _pkg-here
VARIABLE _pkg-latest
VARIABLE _pkg-xfree

: _pkg-assert  ( flag -- )
    1 _pkg-checks +!
    0= IF 1 _pkg-fails +! ." ASSERT " _pkg-checks @ . CR THEN ;
: _pkg-stack  ( -- )
    DEPTH _pkg-depth @ -
    DUP IF ." DEPTH DELTA " DUP . CR THEN
    0= _pkg-assert ;

: _pkg-read-installed  ( -- status )
    ABUILD-INSTALLED-PATH VFS-OPEN DUP _pkg-fd ! 0= IF -1 EXIT THEN
    _pkg-fd @ VFS-SIZE DUP _pkg-doc-u !
    1 MAX ALLOCATE DUP IF
        2DROP _pkg-fd @ VFS-CLOSE 0 _pkg-fd ! -2 EXIT
    THEN
    DROP _pkg-doc !
    _pkg-doc @ _pkg-doc-u @ _pkg-fd @ VFS-READ-EXACT IF
        _pkg-fd @ VFS-CLOSE 0 _pkg-fd !
        _pkg-doc @ FREE 0 _pkg-doc ! -3 EXIT
    THEN
    _pkg-fd @ VFS-CLOSE 0 _pkg-fd ! 0 ;

: _pkg-load-fails  ( expected -- )
    >R _pkg-doc @ _pkg-doc-u @ ALOAD-MANIFEST
    R> = SWAP 0= AND _pkg-assert ;

: _pkg-resolver  ( entry context -- desc status )
    DROP ACE-MANIFEST$ ALOAD-PATH ;

: _pkg-cycle  ( -- )
    _pkg-desc @ APP.COMP-DESC @ CINST-NEW
    DUP 0= _pkg-assert DROP DUP 0<> _pkg-assert _pkg-inst !
    _pkg-desc @ APP.INIT-XT @ ?DUP IF _pkg-inst @ SWAP EXECUTE THEN
    _pkg-desc @ APP.REQUEST-CLOSE-XT @ ?DUP IF
        APP-CLOSE-R-WINDOW _pkg-inst @ ROT EXECUTE
        APP-CLOSE-D-ALLOW = _pkg-assert
    THEN
    _pkg-desc @ APP.SHUTDOWN-XT @ ?DUP IF
        _pkg-inst @ SWAP EXECUTE
    THEN
    _pkg-inst @ CINST-FREE 0 _pkg-inst ! ;

: _pkg-bad-build  ( -- )
    S" /bad.toml" ABUILD-INSTALL
    ABUILD-E-COMPILE = SWAP 0= AND _pkg-assert ;

: _pkg-throw-build  ( -- )
    S" /throw.toml" ABUILD-INSTALL _pkg-status ! _pkg-entry !
    _pkg-status @ ABUILD-E-COMPILE <>
    ABUILD-LAST-DETAIL EVAL-S-THROW <> OR
    ABUILD-EVAL-THROW -777 <> OR IF
        ." THROW BUILD STATUS " _pkg-status @ .
        ." DETAIL " ABUILD-LAST-DETAIL .
        ." THROW " ABUILD-EVAL-THROW . CR
    THEN
    _pkg-status @ ABUILD-E-COMPILE = _pkg-entry @ 0= AND _pkg-assert
    ABUILD-LAST-DETAIL EVAL-S-THROW = _pkg-assert
    ABUILD-EVAL-THROW -777 = _pkg-assert ;

: _pkg-run  ( -- )
    0 _pkg-fails ! 0 _pkg-checks !
    2097152 A-XMEM ARENA-NEW IF -1 THROW THEN
    VMP-NEW DUP _pkg-vfs !
    DUP VMP-INIT 0= _pkg-assert VFS-USE
    _pkg-vfs @ ACAT-NEW
    DUP ACAT-S-OK = _pkg-assert DROP DUP _pkg-cat !
    ACAT-ACTIVATE
    DUP ACAT-S-MISSING = SWAP ACAT-S-OK = OR _pkg-assert
    _pkg-cat @ ABUILD-CATALOG!
    DEPTH _pkg-depth !

    S" /hello.toml" ABUILD-INSTALL _pkg-status ! _pkg-entry !
    _pkg-status @ ABUILD-S-OK = _pkg-assert
    _pkg-entry @ 0<> _pkg-assert
    _pkg-cat @ ACAT-COUNT 1 = _pkg-assert
    _pkg-status @ IF
        ." BUILD STATUS " _pkg-status @ .
        ." DETAIL " ABUILD-LAST-DETAIL . CR
        ." PACKAGE CONTRACTS FAIL " _pkg-fails @ . ." / " _pkg-checks @ . CR
        EXIT
    THEN
    _pkg-stack
    _pkg-read-installed 0= _pkg-assert
    _pkg-doc @ _pkg-doc-u @ MFT-PARSE
    DUP MFT-S-OK = _pkg-assert DROP _pkg-mft !
    _pkg-stack

    \ Repeated digest failures must close every VFS descriptor and leave
    \ the dictionary untouched.  The 70th failure crosses VFS's 64 slots.
    _pkg-mft @ MFT-IMAGE-SHA3 DUP 64 = _pkg-assert DROP _pkg-mut !
    _pkg-mut @ C@ _pkg-byte !
    _pkg-byte @ [CHAR] 0 = IF [CHAR] 1 ELSE [CHAR] 0 THEN _pkg-mut @ C!
    HERE _pkg-here ! LATEST _pkg-latest !
    ALOAD-E-IMAGE-HASH _pkg-load-fails
    XMEM-FREE _pkg-xfree !
    69 0 DO ALOAD-E-IMAGE-HASH _pkg-load-fails LOOP
    XMEM-FREE _pkg-xfree @ = _pkg-assert
    HERE _pkg-here @ = _pkg-assert LATEST _pkg-latest @ = _pkg-assert
    _pkg-byte @ _pkg-mut @ C!
    _pkg-stack

    \ A valid digest with a different exact export fails before mutation.
    _pkg-mft @ MFT-ENTRY DUP 0<> _pkg-assert DROP _pkg-mut !
    _pkg-mut @ C@ _pkg-byte !
    [CHAR] X _pkg-mut @ C!
    ALOAD-E-EXPORT _pkg-load-fails
    HERE _pkg-here @ = _pkg-assert LATEST _pkg-latest @ = _pkg-assert
    _pkg-byte @ _pkg-mut @ C!
    _pkg-mft @ MFT-FREE 0 _pkg-mft !
    _pkg-doc @ FREE 0 _pkg-doc !
    _pkg-stack

    \ First resolve loads exactly once; later close/relaunch cycles reuse
    \ the cached descriptor without growing the dictionary.
    ['] _pkg-resolver 0 _pkg-cat @ ACAT-RESOLVER!
    _pkg-entry @ _pkg-cat @ ACAT-RESOLVE
    DUP ACAT-S-OK = _pkg-assert DROP DUP 0<> _pkg-assert _pkg-desc !
    _pkg-desc @ APP-DESC-VALID? _pkg-assert
    _pkg-cycle _pkg-cycle
    HERE _pkg-here ! LATEST _pkg-latest !
    _pkg-entry @ _pkg-cat @ ACAT-RESOLVE
    DUP ACAT-S-OK = _pkg-assert DROP _pkg-desc @ = _pkg-assert
    HERE _pkg-here @ = _pkg-assert LATEST _pkg-latest @ = _pkg-assert
    _pkg-stack

    \ Checked source failures discard the mark/relocation reservation and
    \ never add a catalog row.  Warm once, then prove allocator reuse.
    _pkg-bad-build
    HERE _pkg-here ! LATEST _pkg-latest ! XMEM-FREE _pkg-xfree !
    19 0 DO _pkg-bad-build LOOP
    5 0 DO _pkg-throw-build LOOP
    HERE _pkg-here @ = _pkg-assert LATEST _pkg-latest @ = _pkg-assert
    XMEM-FREE _pkg-xfree @ = _pkg-assert
    _pkg-cat @ ACAT-COUNT 1 = _pkg-assert
    _pkg-stack

    _pkg-fails @ 0= IF
        ." PACKAGE CONTRACTS PASS " _pkg-checks @ .
    ELSE
        ." PACKAGE CONTRACTS FAIL " _pkg-fails @ . ." / " _pkg-checks @ .
    THEN CR ;

_pkg-run
""",
    ready_markers=("PACKAGE CONTRACTS PASS",),
    stable_markers=("PACKAGE CONTRACTS PASS",),
    failure_markers=("PACKAGE CONTRACTS FAIL",),
    initial_files=(
        (
            "hello.toml",
            (AKASHIC_ROOT / "examples/trusted-local/project.toml").read_bytes(),
        ),
        (
            "hello.f",
            (AKASHIC_ROOT / "examples/trusted-local/hello.f").read_bytes(),
        ),
        (
            "bad.toml",
            b'''[package]\nformat = 1\ntrust = "local"\nsource = "/bad.f"\n\n[app]\nid = "local.bad"\ntitle = "Bad"\nversion = "0.1.0"\nabi = 1\nentry = "BAD-ENTRY"\nwidth = 20\nheight = 4\n''',
        ),
        (
            "bad.f",
            b''': BAD-ENTRY  ( deliberately unfinished )\n    1\n''',
        ),
        (
            "throw.toml",
            b'''[package]\nformat = 1\ntrust = "local"\nsource = "/throw.f"\n\n[app]\nid = "local.throw"\ntitle = "Throw"\nversion = "0.1.0"\nabi = 1\nentry = "THROW-ENTRY"\nwidth = 20\nheight = 4\n''',
        ),
        (
            "throw.f",
            b'''-777 THROW\n''',
        ),
    ),
)

# Same production-shaped image as desktop, with a focused agent/interop
# journey instead of the full applet regression tour.
PROFILES["desktop-agent"] = PROFILES["desktop"]
PROFILES["desktop-resource"] = PROFILES["desktop"]
PROFILES["desktop-local-applet"] = Profile(
    roots=PROFILES["desktop"].roots,
    resources=PROFILES["desktop"].resources,
    autoexec=PROFILES["desktop"].autoexec,
    ready_markers=PROFILES["desktop"].ready_markers,
    stable_markers=PROFILES["desktop"].stable_markers,
    linked=PROFILES["desktop"].linked,
    initial_files=(
        (
            "hello.toml",
            (AKASHIC_ROOT / "examples/trusted-local/project.toml").read_bytes(),
        ),
        (
            "hello.f",
            (AKASHIC_ROOT / "examples/trusted-local/hello.f").read_bytes(),
        ),
    ),
)
PROFILES["desktop-recovery"] = Profile(
    roots=PROFILES["desktop"].roots,
    resources=PROFILES["desktop"].resources,
    autoexec=PROFILES["desktop"].autoexec.replace(
        "\n_boot-practice-provision\n",
        "\n",
    ),
    ready_markers=("[Practice: recovery]",),
    stable_markers=("[Practice: recovery]",),
    linked=True,
    initial_files=(
        ("practice-head-a.bin", b"corrupt-a"),
        ("practice-head-b.bin", b"corrupt-b"),
    ),
)
PROFILES["desktop-fallback"] = Profile(
    roots=PROFILES["desktop"].roots,
    resources=PROFILES["desktop"].resources,
    autoexec=PROFILES["desktop"].autoexec.replace(
        "\n_boot-practice-provision\n",
        "\n",
    ),
    ready_markers=PROFILES["desktop"].ready_markers + ("[Practice: fallback]",),
    stable_markers=PROFILES["desktop"].stable_markers + ("[Practice: fallback]",),
    linked=True,
    initial_files=(
        ("practice-head-a.bin", _practice_head_snapshot(1)),
        ("practice-head-b.bin", b"corrupt-newest"),
    ),
)
PROFILES["desktop-codex"] = Profile(
    roots=tuple(
        "agent/providers/codex/source.f"
        if root == "agent/providers/devtools/scripted.f"
        else root
        for root in PROFILES["desktop"].roots
    ),
    resources=PROFILES["desktop"].resources,
    autoexec=(
        PROFILES["desktop"].autoexec
        .replace(
            "REQUIRE agent/providers/devtools/scripted.f",
            "REQUIRE agent/providers/codex/source.f",
        )
        .replace(
            "SCRIPTED-SOURCE-NEW 0<> ABORT\" scripted source allocation failed\"",
            "CODEX-SOURCE-NEW 0<> ABORT\" Codex source allocation failed\"",
        )
    ),
    ready_markers=PROFILES["desktop"].ready_markers,
    stable_markers=PROFILES["desktop"].stable_markers,
    linked=True,
)
PROFILES["desktop-codex-live"] = Profile(
    roots=PROFILES["desktop-codex"].roots,
    resources=PROFILES["desktop-codex"].resources,
    autoexec=PROFILES["desktop-codex"].autoexec.replace(
        "ENTER-USERLAND",
        "ENTER-USERLAND\n"
        "10 64 0 2 IP-SET\n"
        "10 64 0 1 GW-IP IP!\n"
        "255 255 255 0 NET-MASK IP!\n"
        "8 8 8 8 DNS-SERVER-IP IP!",
        1,
    ),
    ready_markers=PROFILES["desktop-codex"].ready_markers,
    stable_markers=PROFILES["desktop-codex"].stable_markers,
    linked=True,
    requires_tap=True,
)
PROFILES["codex-live-tls"] = Profile(
    roots=(
        "agent/providers/codex/auth.f",
        "agent/providers/codex/config.f",
        "agent/providers/codex/trust.f",
        "net/transports/kdos-tls.f",
    ),
    resources=(),
    autoexec=r"""\ autoexec.f - credential-free native Codex TLS gate
ENTER-USERLAND
." [akashic] loading Codex live TLS gate" CR
REQUIRE agent/providers/codex/auth.f
REQUIRE agent/providers/codex/config.f
REQUIRE agent/providers/codex/trust.f
REQUIRE net/transports/kdos-tls.f

CREATE _clt-auth KDOSTLS-SIZE ALLOT
CREATE _clt-backend KDOSTLS-SIZE ALLOT
VARIABLE _clt-adapter

: _clt-connect  ( host-a host-u adapter -- )
    DUP _clt-adapter ! KDOSTLS-INIT
    443 _clt-adapter @ KDOSTLS-CONFIGURE
    DUP KDOSTLS-E-OK <> IF
        ." CODEX TLS CONFIG FAIL status=" . CR TX-FLUSH ABORT
    THEN DROP
    _clt-adapter @ KDOSTLS.PORT NIO-OPEN
    DUP NIO-S-OK <> IF
        ." CODEX TLS OPEN FAIL status=" .
        ."  error=" _clt-adapter @ KDOSTLS.LAST-ERROR @ .
        ."  native=" _clt-adapter @ KDOSTLS.NATIVE-ERROR @ . CR
        TX-FLUSH ABORT
    THEN DROP
    _clt-adapter @ KDOSTLS.PORT NIO-CLOSE ;

10 64 0 2 IP-SET
10 64 0 1 GW-IP IP!
255 255 255 0 NET-MASK IP!
8 8 8 8 DNS-SERVER-IP IP!

CODEX-TRUST-INSTALL DUP TLS-CERT-OK <> IF
    ." CODEX TLS TRUST FAIL status=" . CR TX-FLUSH ABORT
THEN DROP
." CODEX TLS GATE READY" CR TX-FLUSH
CODEX-AUTH-HOST _clt-auth _clt-connect
." CODEX TLS AUTH OK" CR TX-FLUSH
CODEX-BACKEND-HOST _clt-backend _clt-connect
." CODEX TLS BACKEND OK" CR TX-FLUSH
." CODEX TLS LIVE PASS" CR TX-FLUSH
""",
    ready_markers=("CODEX TLS LIVE PASS",),
    stable_markers=(
        "CODEX TLS AUTH OK",
        "CODEX TLS BACKEND OK",
        "CODEX TLS LIVE PASS",
    ),
    requires_tap=True,
    failure_markers=(
        "CODEX TLS CONFIG FAIL",
        "CODEX TLS TRUST FAIL",
        "CODEX TLS OPEN FAIL",
    ),
)
PROFILES["codex-live-auth"] = Profile(
    roots=(
        "agent/providers/codex/auth.f",
        "agent/providers/codex/trust.f",
        "net/transports/kdos-tls.f",
    ),
    resources=(),
    autoexec=r"""\ autoexec.f - native Codex device-flow diagnostic
ENTER-USERLAND
." [akashic] loading Codex live authentication probe" CR
REQUIRE agent/providers/codex/auth.f
REQUIRE agent/providers/codex/trust.f
REQUIRE net/transports/kdos-tls.f

CREATE _cla-tls KDOSTLS-SIZE ALLOT
CREATE _cla-auth CODEX-DEVICE-AUTH-SIZE ALLOT
VARIABLE _cla-polls
VARIABLE _cla-code-shown

: _cla-dump  ( -- )
    ." auth=" _cla-auth CDA.AUTH AAUTH.STATE @ .
    ."  sub=" _cla-auth CDA.SUBSTATE @ .
    _cla-auth CDA.WORK @ IF
        ."  hbuf=" _cla-auth CDA.EXCHANGE HBUF.STATE @ .
        ." /" _cla-auth CDA.EXCHANGE HBUF.LAST-STATUS @ .
        ."  http=" _cla-auth CDA.EXCHANGE HBUF.HTTP-CODE @ .
    THEN
    ."  tls=" _cla-tls KDOSTLS.STATE @ .
    ." /" _cla-tls KDOSTLS.LAST-ERROR @ .
    ." /" _cla-tls KDOSTLS.NATIVE-ERROR @ . CR TX-FLUSH ;

: _cla-fail  ( -- )
    ." CODEX AUTH LIVE FAIL " _cla-dump
    _cla-auth CDA.AUTH AAUTH.ERROR DUP CV-DATA@ SWAP CV-LEN@ TYPE CR
    TX-FLUSH ABORT ;

: _cla-show-code  ( -- )
    _cla-code-shown @ IF EXIT THEN
    -1 _cla-code-shown !
    ." CODEX AUTH CODE READY" CR
    ." Open https://auth.openai.com/codex/device" CR
    ." Code: "
    _cla-auth CDA.AUTH AAUTH.USER-CODE DUP CV-DATA@ SWAP CV-LEN@ TYPE CR
    ." Waiting for browser authorization..." CR TX-FLUSH ;

: _cla-run  ( -- )
    0 _cla-polls ! 0 _cla-code-shown !
    10 64 0 2 IP-SET
    10 64 0 1 GW-IP IP!
    255 255 255 0 NET-MASK IP!
    8 8 8 8 DNS-SERVER-IP IP!
    CODEX-TRUST-INSTALL DUP TLS-CERT-OK <> IF
        ." CODEX AUTH TRUST FAIL status=" . CR TX-FLUSH ABORT
    THEN DROP
    _cla-tls KDOSTLS-INIT
    CODEX-AUTH-HOST 443 _cla-tls KDOSTLS-CONFIGURE
    DUP KDOSTLS-E-OK <> IF
        ." CODEX AUTH CONFIG FAIL status=" . CR TX-FLUSH ABORT
    THEN DROP
    _cla-tls KDOSTLS.PORT _cla-auth CODEX-DEVICE-AUTH-INIT
    DUP AAUTH-S-OK <> IF
        ." CODEX AUTH INIT FAIL status=" . CR TX-FLUSH ABORT
    THEN DROP
    ." CODEX AUTH BEGIN ENTER" CR TX-FLUSH
    _cla-auth CDA.AUTH AAUTH-BEGIN DUP
    ." CODEX AUTH BEGIN RETURN status=" . SPACE _cla-dump
    AAUTH-S-PENDING <> IF _cla-fail THEN
    BEGIN
        _cla-auth CDA.AUTH AAUTH.STATE @ DUP AAUTH-STATE-READY <
        SWAP AAUTH-STATE-ERROR <> AND
    WHILE
        1 _cla-polls +!
        _cla-polls @ 1 = IF
            ." CODEX AUTH POLL ENTER" CR TX-FLUSH
        THEN
        _cla-auth CDA.AUTH AAUTH-POLL DROP
        _cla-polls @ 1 = IF
            ." CODEX AUTH POLL RETURN " _cla-dump
        THEN
        _cla-auth CDA.AUTH AAUTH.STATE @ AAUTH-STATE-PENDING = IF
            _cla-show-code
        THEN
    REPEAT
    _cla-auth CDA.AUTH AAUTH.STATE @ AAUTH-STATE-ERROR = IF _cla-fail THEN
    ." CODEX AUTH LIVE PASS" CR
    ." Account: "
    _cla-auth CDA.AUTH AAUTH.ACCOUNT-LABEL DUP CV-DATA@ SWAP CV-LEN@ TYPE CR
    TX-FLUSH ;

_cla-run
""",
    ready_markers=("CODEX AUTH CODE READY",),
    stable_markers=("CODEX AUTH CODE READY",),
    requires_tap=True,
    failure_markers=(
        "CODEX AUTH TRUST FAIL",
        "CODEX AUTH CONFIG FAIL",
        "CODEX AUTH INIT FAIL",
        "CODEX AUTH LIVE FAIL",
    ),
)
LARGE_SAMPLE = b"".join(
    f"Large fixture line {line:03d}: Pad crosses MP64FS sector boundaries.\n".encode()
    for line in range(1, 49)
)

SAMPLE_DATE = datetime.now(timezone.utc).date().isoformat()
DAYBOOK_SAMPLE = (
    "# Daybook\n\n"
    f"- {SAMPLE_DATE} 09:30 | Project review\n"
    f"- [ ] {SAMPLE_DATE} | Plan the next release\n"
    f"- [x] {SAMPLE_DATE} | Morning walk\n"
    f"> {SAMPLE_DATE} | Keep the system small and legible\n"
).encode()

GRID_SAMPLE = (
    "Item,Qty,Price,Total\n"
    '"Paper, A4",3,12,=B2*C2\n'
    "Ink,2,25,=B3*C3\n"
    "Subtotal,,,=SUM(D2:D3)\n"
).encode()

SAMPLE_FILES = {
    "welcome.txt": b"Welcome to Akashic.\nThis file is editable in Pad.\n",
    "example.f": b": SQUARE DUP * ;\n9 SQUARE .\n",
    "large.txt": LARGE_SAMPLE,
    "daybook.md": DAYBOOK_SAMPLE,
    "grid.csv": GRID_SAMPLE,
}


def _normalize_module(module: str, requiring: str | None = None) -> str:
    if module.startswith("/"):
        normalized = posixpath.normpath(module.lstrip("/"))
    else:
        base = posixpath.dirname(requiring) if requiring else ""
        normalized = posixpath.normpath(posixpath.join(base, module))
    if normalized == ".." or normalized.startswith("../"):
        raise ValueError(f"REQUIRE escapes Akashic source root: {module!r}")
    return normalized


def dependency_closure(roots: tuple[str, ...]) -> tuple[str, ...]:
    """Return the deterministic transitive REQUIRE closure for *roots*."""
    pending = [_normalize_module(root) for root in reversed(roots)]
    seen: set[str] = set()

    while pending:
        module = pending.pop()
        if module in seen:
            continue
        host_path = SOURCE_ROOT / module
        if not host_path.is_file():
            raise FileNotFoundError(f"Missing Akashic module: {module}")
        seen.add(module)
        text = host_path.read_text(encoding="utf-8")
        dependencies = [
            _normalize_module(match.group(1), module)
            for match in REQUIRE_RE.finditer(text)
        ]
        pending.extend(reversed(dependencies))

    return tuple(sorted(seen))


def dependency_order(roots: tuple[str, ...]) -> tuple[str, ...]:
    """Return dependencies before their requiring modules."""
    ordered: list[str] = []
    visited: set[str] = set()
    visiting: set[str] = set()

    def visit(module: str, requiring: str | None = None):
        normalized = _normalize_module(module, requiring)
        if normalized in visited:
            return
        if normalized in visiting:
            raise RuntimeError(f"Cyclic linked REQUIRE dependency: {normalized}")
        host_path = SOURCE_ROOT / normalized
        if not host_path.is_file():
            raise FileNotFoundError(f"Missing Akashic module: {normalized}")
        visiting.add(normalized)
        text = host_path.read_text(encoding="utf-8")
        for match in REQUIRE_RE.finditer(text):
            visit(match.group(1), normalized)
        visiting.remove(normalized)
        visited.add(normalized)
        ordered.append(normalized)

    for root in roots:
        visit(root)
    return tuple(ordered)


def _minify_forth(text: str, *, remove_requires: bool = False) -> str:
    """Remove deployment-only line comments without rewriting Forth tokens."""
    lines: list[str] = []
    for line in text.splitlines():
        if not line.strip() or line.lstrip().startswith("\\"):
            continue
        if remove_requires and REQUIRE_RE.match(line):
            continue
        lines.append(line.rstrip())
    return "\n".join(lines) + "\n"


def _linked_chunks(modules: tuple[str, ...]) -> dict[str, bytes]:
    """Pack ordered modules into loader-safe native Forth source chunks."""
    chunks: list[bytearray] = []
    current = bytearray()
    for module in modules:
        source = _minify_forth(
            (SOURCE_ROOT / module).read_text(encoding="utf-8"),
            remove_requires=True,
        ).encode("utf-8")
        if len(source) > LINK_CHUNK_BYTES:
            raise RuntimeError(
                f"Linked module exceeds {LINK_CHUNK_BYTES} bytes: {module}"
            )
        if current and len(current) + len(source) > LINK_CHUNK_BYTES:
            chunks.append(current)
            current = bytearray()
        current.extend(source)
    if current:
        chunks.append(current)
    return {
        f".akashic/link-{index:02d}.f": bytes(content)
        for index, content in enumerate(chunks)
    }


def _linked_autoexec(autoexec: str, chunk_names: tuple[str, ...]) -> str:
    """Replace source REQUIREs with ordered deployment-chunk REQUIREs."""
    lines: list[str] = []
    inserted = False
    for line in autoexec.splitlines():
        if REQUIRE_RE.match(line):
            if not inserted:
                lines.extend(f"REQUIRE {name}" for name in chunk_names)
                inserted = True
            continue
        lines.append(line)
    if not inserted:
        lines[0:0] = [f"REQUIRE {name}" for name in chunk_names]
    return "\n".join(lines) + "\n"


def _directories(paths: set[str]) -> list[str]:
    directories: set[str] = set()
    for path in paths:
        parts = PurePosixPath(path).parts[:-1]
        for depth in range(1, len(parts) + 1):
            directories.add("/".join(parts[:depth]))
    return sorted(directories, key=lambda value: (value.count("/"), value))


def _validate_image_paths(paths: set[str], directories: list[str]):
    # Include kdos/autoexec and two temporary fragmentation fixtures.
    entries = len(paths) + len(directories) + len(SAMPLE_FILES) + 4
    if entries > MAX_FILES:
        raise RuntimeError(
            f"Profile needs {entries} MP64FS entries; filesystem limit is "
            f"{MAX_FILES}."
        )
    for path in paths | set(directories) | set(SAMPLE_FILES):
        name = PurePosixPath(path).name
        if len(name.encode("utf-8")) > MAX_NAME_LEN:
            raise RuntimeError(
                f"MP64FS name is too long ({len(name)} > {MAX_NAME_LEN}): {path}"
            )


def _validate_module_ids(modules: tuple[str, ...]):
    """Reject PROVIDED names that alias in KDOS's bounded module table."""
    keys: dict[bytes, tuple[str, str]] = {}
    for module in modules:
        text = (SOURCE_ROOT / module).read_text(encoding="utf-8")
        match = PROVIDED_RE.search(text)
        if not match:
            continue
        module_id = match.group(1)
        key = module_id.encode("utf-8")[:MODULE_KEY_BYTES].ljust(
            MODULE_KEY_BYTES, b"\0"
        )
        previous = keys.get(key)
        if previous and previous != (module, module_id):
            other_module, other_id = previous
            raise RuntimeError(
                "KDOS PROVIDED key collision: "
                f"{other_id!r} ({other_module}) and {module_id!r} ({module})"
            )
        keys[key] = (module, module_id)


def default_image_path(profile: str) -> Path:
    return OUTPUT_ROOT / f"akashic-{profile}.img"


def _load_codex_auth_checkpoint(path: Path) -> dict[str, str | int]:
    source = path.expanduser().resolve()
    if source.stat().st_mode & 0o077:
        raise RuntimeError(
            f"Codex auth checkpoint must be private (chmod 600): {source}"
        )
    payload = json.loads(source.read_text(encoding="utf-8"))
    if payload.get("format") != CODEX_AUTH_CHECKPOINT_FORMAT:
        raise RuntimeError(f"Unsupported Codex auth checkpoint: {source}")
    limits = {
        "access_token": 8192,
        "refresh_token": 4096,
        "id_token": 8192,
    }
    result: dict[str, str | int] = {}
    for key, capacity in limits.items():
        value = payload.get(key)
        if not isinstance(value, str) or not value or len(value.encode("utf-8")) > capacity:
            raise RuntimeError(f"Invalid {key} in Codex auth checkpoint")
        result[key] = value
    expires_ms = payload.get("expires_ms")
    if isinstance(expires_ms, bool) or not isinstance(expires_ms, int) or expires_ms <= 0:
        raise RuntimeError("Invalid expires_ms in Codex auth checkpoint")
    result["expires_ms"] = expires_ms
    return result


def _forth_byte_buffer(name: str, value: str) -> str:
    encoded = value.encode("utf-8")
    lines = [f"CREATE {name}"]
    for start in range(0, len(encoded), 24):
        chunk = encoded[start : start + 24]
        lines.append("  " + " ".join(f"{byte} C," for byte in chunk))
    lines.append(f"{len(encoded)} CONSTANT {name}-u")
    return "\n".join(lines)


def _with_codex_auth_checkpoint(autoexec: str, checkpoint: Path) -> str:
    payload = _load_codex_auth_checkpoint(checkpoint)
    definition_marker = ": _boot-agent-source  ( -- )"
    constructor_marker = (
        '    CODEX-SOURCE-NEW 0<> ABORT" Codex source allocation failed"'
    )
    if definition_marker not in autoexec or constructor_marker not in autoexec:
        raise RuntimeError("Selected profile cannot restore a Codex auth checkpoint")
    buffers = "\n".join(
        (
            _forth_byte_buffer("_boot-codex-id", str(payload["id_token"])),
            _forth_byte_buffer(
                "_boot-codex-access", str(payload["access_token"])
            ),
            _forth_byte_buffer(
                "_boot-codex-refresh", str(payload["refresh_token"])
            ),
        )
    )
    autoexec = autoexec.replace(
        definition_marker, f"{buffers}\n\n{definition_marker}", 1
    )
    restore = "\n".join(
        (
            constructor_marker,
            "    DUP CODEX-SOURCE-AUTH >R",
            "    _boot-codex-id _boot-codex-id-u",
            "    _boot-codex-access _boot-codex-access-u",
            "    _boot-codex-refresh _boot-codex-refresh-u",
            f'    {payload["expires_ms"]} R> CODEX-DEVICE-AUTH-RESTORE',
            '    AAUTH-S-OK <> ABORT" Codex checkpoint restore failed"',
            "    _boot-codex-id _boot-codex-id-u 0 FILL",
            "    _boot-codex-access _boot-codex-access-u 0 FILL",
            "    _boot-codex-refresh _boot-codex-refresh-u 0 FILL",
        )
    )
    return autoexec.replace(constructor_marker, restore, 1)


def build_image(
    profile_name: str,
    output: Path | None = None,
    codex_auth_checkpoint: Path | None = None,
) -> Path:
    profile = PROFILES[profile_name]
    autoexec = profile.autoexec
    if codex_auth_checkpoint is not None:
        autoexec = _with_codex_auth_checkpoint(autoexec, codex_auth_checkpoint)
    modules = (
        dependency_order(profile.roots)
        if profile.linked
        else dependency_closure(profile.roots)
    )
    resources = set(profile.resources)
    linked_chunks = _linked_chunks(modules) if profile.linked else {}
    paths = set(linked_chunks) | resources if profile.linked else set(modules) | resources
    initial_paths = {path for path, _ in profile.initial_files}
    image_paths = paths | initial_paths
    directories = _directories(image_paths)
    _validate_module_ids(modules)
    _validate_image_paths(image_paths, directories)

    target = (output or default_image_path(profile_name)).resolve()
    target.parent.mkdir(parents=True, exist_ok=True)

    fs = MP64FS(total_sectors=4096)
    fs.format()
    fs.inject_file(
        "kdos.f",
        (MEGAPAD_ROOT / "kdos.f").read_bytes(),
        ftype=FTYPE_FORTH,
        flags=FLAG_SYSTEM,
    )

    for directory in directories:
        fs.mkdir(directory)

    for path in sorted(paths):
        source = SOURCE_ROOT / path
        if path in linked_chunks:
            content = linked_chunks[path]
        else:
            if not source.is_file():
                raise FileNotFoundError(f"Missing Akashic resource: {path}")
            content = source.read_bytes()
        disk_path = PurePosixPath(path)
        file_type = FTYPE_FORTH if disk_path.suffix == ".f" else FTYPE_TEXT
        parent = "/" if str(disk_path.parent) == "." else "/" + str(disk_path.parent)
        fs.inject_file(
            disk_path.name,
            content,
            ftype=file_type,
            path=parent,
        )

    for path, content in profile.initial_files:
        disk_path = PurePosixPath(path)
        parent = "/" if str(disk_path.parent) == "." else "/" + str(disk_path.parent)
        fs.inject_file(disk_path.name, content, path=parent)

    fs.inject_file("large.txt", LARGE_SAMPLE, ftype=FTYPE_TEXT)

    # Leave two isolated one-sector holes in the generated test image.
    # Guest-created smoke.txt uses the first; the large Save As copy uses
    # the second and must grow through MP64FS's secondary extent.
    fs.inject_file(".growth-hole-1", bytes(512), flags=FLAG_SYSTEM)

    fs.inject_file(
        "autoexec.f",
        (
            _linked_autoexec(autoexec, tuple(linked_chunks))
            if profile.linked
            else autoexec
        ).encode("utf-8"),
        ftype=FTYPE_FORTH,
    )
    fs.inject_file(".growth-hole-2", bytes(512), flags=FLAG_SYSTEM)

    for name in sorted(SAMPLE_FILES.keys() - {"large.txt"}):
        fs.inject_file(name, SAMPLE_FILES[name], ftype=FTYPE_TEXT)

    fs.delete_file(".growth-hole-1")
    fs.delete_file(".growth-hole-2")
    fs.save(target)
    if codex_auth_checkpoint is not None:
        target.chmod(0o600)

    info = fs.info()
    print(
        f"Built {profile_name} image: {target}\n"
        f"  {len(modules)} modules"
        f"{f' linked in {len(linked_chunks)} chunks' if profile.linked else ''}, "
        f"{len(resources)} resources, "
        f"{len(directories)} directories\n"
        f"  {info['files']} MP64FS entries, {target.stat().st_size:,} bytes"
    )
    return target


def _has_forth_error(raw: str) -> list[str]:
    patterns = (
        re.compile(r"(?i)\b(abort|undefined word|stack underflow)\b"),
        re.compile(
            r"(?i)(\?\s+\(not found\)|branch offset overflow|"
            r"evaluate depth limit exceeded|dictionary full)"
        ),
        re.compile(r"(?m)^\s*\?\s*$"),
    )
    return [line for line in raw.splitlines() if any(p.search(line) for p in patterns)]


def smoke(
    profile_name: str,
    image_path: Path,
    *,
    cols: int,
    rows: int,
    max_steps: int,
    timeout: float,
    ext_mem_mib: int = DEFAULT_EXT_MEM_MIB,
    nic_tap: str | None = None,
) -> bool:
    profile = PROFILES[profile_name]
    if profile.requires_tap and not nic_tap:
        print(
            f"Smoke {profile_name}: FAIL\n"
            "  this opt-in live profile requires --nic-tap[=IFNAME]"
        )
        return False
    nic_backend = None
    if nic_tap:
        from nic_backends import TAPBackend, tap_available

        if not tap_available(nic_tap):
            print(
                f"Smoke {profile_name}: FAIL\n"
                f"  TAP device {nic_tap!r} does not exist or is not accessible"
            )
            return False
        nic_backend = TAPBackend(tap_name=nic_tap)
    started = time.perf_counter()
    total_steps = 0
    stop_reason = "budget"

    with MachineSession.from_bios(
        MEGAPAD_ROOT / "bios.asm",
        storage_image=image_path,
        cols=cols,
        rows=rows,
        batch_steps=500_000,
        ext_mem_size=ext_mem_mib << 20,
        nic_backend=nic_backend,
        realtime_clock=bool(nic_tap),
    ) as session:
        session.boot()
        deadline = time.monotonic() + timeout
        screen = session.snapshot()
        journey_errors: list[str] = []

        while total_steps < max_steps and time.monotonic() < deadline:
            remaining = max_steps - total_steps
            report = session.run(
                max_steps=min(50_000_000, remaining),
                wall_timeout_s=min(2.0, max(0.05, deadline - time.monotonic())),
                advance_idle=True,
            )
            total_steps += report.steps
            stop_reason = report.reason
            screen = session.snapshot()
            screen_text = screen.text()
            if all(marker in screen_text for marker in profile.ready_markers):
                stop_reason = "ready"
                break
            if any(marker in screen_text for marker in profile.failure_markers):
                stop_reason = "failed"
                break
            if report.reason in ("halted", "stalled"):
                break

        initial_text = screen.text()
        initial_ready = all(
            marker in initial_text for marker in profile.ready_markers
        )

        def wait_screen(
            marker: str,
            failure: str,
            *,
            step_budget: int = 250_000_000,
            wall_timeout: float = 8.0,
        ) -> bool:
            nonlocal total_steps, screen
            remaining = min(step_budget, max_steps - total_steps)
            if remaining <= 0 or time.monotonic() >= deadline:
                journey_errors.append(f"{failure} (journey budget exhausted)")
                return False
            local_deadline = min(deadline, time.monotonic() + wall_timeout)
            while remaining > 0 and time.monotonic() < local_deadline:
                screen = session.snapshot()
                if marker in screen.text():
                    return True
                chunk = min(50_000_000, remaining)
                report = session.run(
                    max_steps=chunk,
                    wall_timeout_s=min(
                        1.0, max(0.05, local_deadline - time.monotonic())
                    ),
                    advance_idle=True,
                )
                total_steps += report.steps
                remaining -= report.steps
                if report.reason == "halted":
                    break
                if report.steps == 0:
                    time.sleep(0.005)
            screen = session.snapshot()
            if marker in screen.text():
                return True
            journey_errors.append(failure)
            return False

        def wait_screen_gone(
            marker: str,
            failure: str,
            *,
            step_budget: int = 250_000_000,
            wall_timeout: float = 8.0,
        ) -> bool:
            nonlocal total_steps, screen
            remaining = min(step_budget, max_steps - total_steps)
            local_deadline = min(deadline, time.monotonic() + wall_timeout)
            while remaining > 0 and time.monotonic() < local_deadline:
                screen = session.snapshot()
                if marker not in screen.text():
                    return True
                chunk = min(10_000_000, remaining)
                report = session.run(
                    max_steps=chunk,
                    wall_timeout_s=min(
                        0.75, max(0.05, local_deadline - time.monotonic())
                    ),
                    advance_idle=True,
                )
                total_steps += report.steps
                remaining -= report.steps
                if report.reason == "halted":
                    break
                if report.steps == 0:
                    time.sleep(0.005)
            screen = session.snapshot()
            if marker not in screen.text():
                return True
            journey_errors.append(failure)
            return False

        def wait_screen_any(
            markers: tuple[str, ...],
            failure: str,
            *,
            step_budget: int = 250_000_000,
            wall_timeout: float = 8.0,
        ) -> str | None:
            nonlocal total_steps, screen
            remaining = min(step_budget, max_steps - total_steps)
            local_deadline = min(deadline, time.monotonic() + wall_timeout)
            while remaining > 0 and time.monotonic() < local_deadline:
                screen = session.snapshot()
                text = screen.text()
                for marker in markers:
                    if marker in text:
                        return marker
                chunk = min(50_000_000, remaining)
                report = session.run(
                    max_steps=chunk,
                    wall_timeout_s=min(
                        1.0, max(0.05, local_deadline - time.monotonic())
                    ),
                    advance_idle=True,
                )
                total_steps += report.steps
                remaining -= report.steps
                if report.reason == "halted":
                    break
                if report.steps == 0:
                    time.sleep(0.005)
            screen = session.snapshot()
            text = screen.text()
            for marker in markers:
                if marker in text:
                    return marker
            journey_errors.append(failure)
            return None

        def desktop_tile_contains(marker: str, tile: int) -> bool:
            tile_col = tile % 3
            tile_row = tile // 3
            content_rows = max(1, screen.rows - 1)
            left = tile_col * screen.cols // 3
            right = (tile_col + 1) * screen.cols // 3
            top = tile_row * content_rows // 2
            bottom = (tile_row + 1) * content_rows // 2
            return any(
                marker in line[left:right]
                for line in screen.lines()[top:bottom]
            )

        def wait_desktop_tile(
            marker: str,
            tile: int,
            failure: str,
            *,
            step_budget: int = 250_000_000,
            wall_timeout: float = 8.0,
        ) -> bool:
            nonlocal total_steps, screen
            remaining = min(step_budget, max_steps - total_steps)
            local_deadline = min(deadline, time.monotonic() + wall_timeout)
            while remaining > 0 and time.monotonic() < local_deadline:
                screen = session.snapshot()
                if desktop_tile_contains(marker, tile):
                    return True
                chunk = min(50_000_000, remaining)
                report = session.run(
                    max_steps=chunk,
                    wall_timeout_s=min(
                        1.0, max(0.05, local_deadline - time.monotonic())
                    ),
                    advance_idle=True,
                )
                total_steps += report.steps
                remaining -= report.steps
                if report.reason == "halted":
                    break
                if report.steps == 0:
                    time.sleep(0.005)
            screen = session.snapshot()
            if desktop_tile_contains(marker, tile):
                return True
            journey_errors.append(failure)
            return False

        def run_desk_agent_journey() -> None:
            session.send_key("alt+5")
            focused = wait_screen(
                "[5:Agent*]", "Desk did not focus Agent before composing"
            )
            if focused:
                session.send_key("ctrl+l")
            if focused and wait_screen(
                "Ask:", "Agent applet did not open its shared composer"
            ):
                session.send_text("task smoke")
                session.send_key("enter")
                if wait_screen(
                    "Review required",
                    "persistent app tool did not pause for approval",
                    step_budget=1_200_000_000,
                    wall_timeout=30.0,
                ):
                    wait_screen(
                        "daybook.task.capture",
                        "approval view did not identify the exact capability",
                    )
                    session.send_key("alt+5")
                    wait_screen(
                        "[5:Agent*]", "Desk did not keep Agent focused for review"
                    )
                    session.send_key("f6")
                    resolved = wait_screen(
                        "Request approved",
                        "F6 did not approve the app tool review request",
                        step_budget=800_000_000,
                        wall_timeout=20.0,
                    )
                    outcome = None
                    if resolved:
                        outcome = wait_screen_any(
                            (
                                "Daybook task captured.",
                                "Daybook persistence failed",
                                "Capability handler threw",
                                "Capability output schema rejected",
                                "Capability returned the wrong value type",
                            ),
                            "approved capability did not return a tool result",
                            step_budget=2_000_000_000,
                            wall_timeout=60.0,
                        )
                    if outcome == "Daybook task captured.":
                        live_fs = MP64FS(
                            bytearray(session.system.storage._image_data)
                        )
                        try:
                            daybook = live_fs.read_file("daybook.md")
                        except FileNotFoundError:
                            daybook = b""
                        if b"task smoke" not in daybook:
                            journey_errors.append(
                                "approved Daybook capability did not persist its task"
                            )
                    elif outcome:
                        journey_errors.append(
                            f"approved Daybook capability failed: {outcome}"
                        )
                        return

            session.send_key("alt+5")
            session.send_key("ctrl+l")
            if wait_screen(
                "Ask:", "Agent did not reopen its composer for the hidden-op probe"
            ):
                session.send_text("source smoke")
                session.send_key("enter")
                wait_screen(
                    "Tool handler was not",
                    "the raw Daybook source operation escaped the exact facet",
                    step_budget=1_000_000_000,
                    wall_timeout=25.0,
                )

            session.send_key("alt+2")
            session.send_key("ctrl+space")
            if wait_screen(
                "Ask:",
                "Desk's global Agent composer did not open over File Explorer",
            ):
                session.send_text("desk hi")
                session.send_key("enter")
                if wait_screen_gone(
                    "Ask:", "Desk's global Agent composer did not close"
                ):
                    wait_screen(
                        "desk hi",
                        "Desk's global prompt did not reach the shared conversation",
                        step_budget=900_000_000,
                        wall_timeout=20.0,
                    )
                    wait_screen(
                        "Ready", "Desk's shared agent runtime did not finish"
                    )

        def run_local_applet_journey() -> None:
            session.send_key("alt+1")
            if not wait_screen(
                "[1:Akashic Pa*]",
                "Desk did not focus Pad for the local applet journey",
            ):
                return
            session.send_key("ctrl+o")
            if not wait_screen(
                "Open:", "Pad did not open its project-manifest prompt"
            ):
                return
            session.send_text("/hello.toml")
            session.send_key("enter")
            if not wait_screen(
                "local.hell", "Pad could not open the local applet manifest"
            ):
                return
            session.send_key("ctrl+shift+b")
            if not wait_screen(
                "Applet installed",
                "Pad did not build and install the trusted-local applet",
                step_budget=1_500_000_000,
                wall_timeout=35.0,
            ):
                return

            session.send_key("alt+h")
            if not wait_screen(
                "Applets", "Desk did not open the installed-applet launcher"
            ):
                return
            session.send_key("end")
            if not wait_screen(
                "Hello", "Desk launcher did not expose the installed applet"
            ):
                return
            session.send_key("enter")
            if not wait_screen(
                "packaged applet",
                "Desk did not load and launch the installed applet",
                step_budget=1_000_000_000,
                wall_timeout=25.0,
            ):
                return
            if not wait_screen(
                "Hello*",
                "Desk did not focus the applet opened from its launcher",
            ):
                return

            session.send_key("alt+w")
            if not wait_screen_gone(
                "packaged applet", "Desk did not close the packaged applet"
            ):
                return
            session.send_key("alt+h")
            if not wait_screen(
                "Applets", "Desk did not reopen the applet launcher"
            ):
                return
            session.send_key("end")
            session.send_key("enter")
            relaunched = wait_screen(
                "packaged applet",
                "Desk did not relaunch the packaged applet",
                step_budget=800_000_000,
                wall_timeout=20.0,
            )
            if not relaunched:
                return

            # Pad mounts an embedded panel and app-owned Explorer through
            # UTUI-WIDGET-SET.  Closing it exercises the borrowed-widget
            # teardown boundary after several context switches and relayouts.
            session.send_key("alt+1")
            if not wait_screen(
                "[1:Akashic Pa*]",
                "Desk did not refocus Pad before its close regression",
            ):
                return
            session.send_key("alt+w")
            if not wait_screen_gone(
                "[1:Akashic Pa*]",
                "Desk did not close Pad after the local applet journey",
            ):
                return
            session.send_key("alt+h")
            if not wait_screen(
                "Applets", "Desk did not open the launcher to relaunch Pad"
            ):
                return
            session.send_key("home")
            session.send_key("enter")
            wait_screen(
                "UTF-8",
                "Desk did not relaunch Pad after closing its borrowed widgets",
                step_budget=1_000_000_000,
                wall_timeout=25.0,
            )

        def run_shared_resource_journey() -> None:
            stale_marker = "PADOLD"
            owner_marker = "DBNEW"
            ordinary_marker = "PADFILE"

            session.send_key("alt+3")
            if not wait_screen(
                "[3:Daybook*]",
                "Desk did not focus Daybook for the shared-resource journey",
            ):
                return
            session.send_key("ctrl+o")
            if not wait_screen(
                "[1:Akashic Pa*]",
                "Daybook Ctrl+O did not route its semantic source to Pad",
                step_budget=800_000_000,
                wall_timeout=20.0,
            ):
                return
            if not wait_desktop_tile(
                "# Daybook",
                0,
                "Pad did not show the Daybook semantic snapshot in its tile",
            ):
                return
            session.send_key("ctrl+a")
            session.send_text("# Daybook")
            session.send_key("enter")
            session.send_key("enter")
            session.send_text(f"> {SAMPLE_DATE} | {stale_marker}")
            if not wait_desktop_tile(
                stale_marker,
                0,
                "Pad did not retain the edited semantic snapshot",
            ):
                return

            session.send_key("alt+3")
            if not wait_screen(
                "[3:Daybook*]",
                "Desk did not return focus to Daybook before its competing edit",
            ):
                return
            session.send_key("ctrl+n")
            if not wait_desktop_tile(
                "New task:",
                2,
                "Daybook did not open its task prompt in its own tile",
            ):
                return
            session.send_text(owner_marker)
            session.send_key("enter")
            if not wait_desktop_tile(
                owner_marker,
                2,
                "Daybook did not publish its competing edit in its own tile",
                step_budget=1_200_000_000,
                wall_timeout=30.0,
            ):
                return

            # Pad must still display the exact old semantic snapshot.  Check
            # this in Pad's tile: a global search would also see Daybook's new
            # entry and could not distinguish a leaked refresh from ownership.
            screen = session.snapshot()
            if desktop_tile_contains(owner_marker, 0):
                journey_errors.append(
                    "Daybook's competing edit leaked into Pad's old snapshot"
                )
            if not desktop_tile_contains(stale_marker, 0):
                journey_errors.append(
                    "Pad lost its dirty old snapshot after Daybook committed"
                )

            live_fs = MP64FS(bytearray(session.system.storage._image_data))
            try:
                committed_daybook = live_fs.read_file("daybook.md")
            except FileNotFoundError:
                committed_daybook = b""
            expected_owner_record = (
                f"- [ ] {SAMPLE_DATE} | {owner_marker}\n"
            ).encode()
            if expected_owner_record not in committed_daybook:
                journey_errors.append(
                    "Daybook's competing semantic commit did not reach backing bytes"
                )
            if stale_marker.encode() in committed_daybook:
                journey_errors.append(
                    "Pad's unsaved old snapshot reached backing bytes prematurely"
                )

            # Close the lens-owning Daybook instance before Pad attempts its
            # old exact write.  A recreated revision-1 owner would accept that
            # write; stale refusal below therefore proves the Desk-owned owner
            # and revision survived Daybook teardown.
            session.send_key("alt+w")
            if not wait_screen_gone(
                "[3:Daybook",
                "Desk did not close the clean Daybook instance",
                step_budget=800_000_000,
                wall_timeout=20.0,
            ):
                return

            session.send_key("alt+1")
            if not wait_screen(
                "[1:Akashic Pa*]",
                "Desk did not refocus Pad for the stale save",
            ):
                return
            session.send_key("alt+f")
            if not wait_screen(
                stale_marker,
                "Desk full-frame did not preserve Pad's dirty semantic snapshot",
            ):
                session.send_key("alt+f")
                return
            session.send_key("ctrl+s")
            if not wait_screen(
                "changed elsewhere; reload before saving",
                "Pad did not report the exact stale semantic-save refusal",
                step_budget=800_000_000,
                wall_timeout=20.0,
            ):
                session.send_key("alt+f")
                return
            if "/daybook.md*" not in session.snapshot().text():
                journey_errors.append(
                    "Pad cleared the shared buffer's dirty state after a stale save"
                )

            live_fs = MP64FS(bytearray(session.system.storage._image_data))
            try:
                after_stale = live_fs.read_file("daybook.md")
            except FileNotFoundError:
                after_stale = b""
            if after_stale != committed_daybook:
                journey_errors.append(
                    "Pad's stale semantic save changed the Daybook backing bytes"
                )

            # A stale shared tab must not poison unrelated ordinary Pad I/O.
            session.send_key("ctrl+n")
            session.send_text(ordinary_marker)
            if not wait_screen(
                ordinary_marker,
                "Pad did not create the ordinary control buffer",
            ):
                session.send_key("alt+f")
                return
            session.send_key("ctrl+s")
            if not wait_screen(
                "Save as:",
                "Pad did not open Save As for the ordinary control buffer",
            ):
                session.send_key("alt+f")
                return
            session.send_text("/resource-control.txt")
            session.send_key("enter")
            if not wait_screen_gone(
                "Save as:",
                "Pad did not finish the ordinary control save",
            ):
                session.send_key("alt+f")
                return
            live_fs = MP64FS(bytearray(session.system.storage._image_data))
            try:
                ordinary_bytes = live_fs.read_file("resource-control.txt")
            except FileNotFoundError:
                ordinary_bytes = None
            if ordinary_bytes != ordinary_marker.encode():
                journey_errors.append(
                    "ordinary Pad control save did not persist exact bytes"
                )

            live_fs = MP64FS(bytearray(session.system.storage._image_data))
            try:
                after_ordinary = live_fs.read_file("daybook.md")
            except FileNotFoundError:
                after_ordinary = b""
            if after_ordinary != after_stale:
                journey_errors.append(
                    "ordinary Pad control save changed the shared Daybook bytes"
                )

            session.send_key("alt+f")
            session.send_key("alt+h")
            if not wait_screen(
                "Applets",
                "Desk did not open the launcher to relaunch Daybook",
            ):
                return
            session.send_key("home")
            session.send_key("down")
            session.send_key("down")
            session.send_key("enter")
            if not wait_screen(
                ":Daybook*]",
                "Desk did not relaunch and focus Daybook from its catalog",
                step_budget=1_200_000_000,
                wall_timeout=30.0,
            ):
                return
            wait_desktop_tile(
                owner_marker,
                4,
                "relaunched Daybook did not load the current owner snapshot",
                step_budget=1_200_000_000,
                wall_timeout=30.0,
            )

        if initial_ready and profile_name == "desktop-agent":
            run_desk_agent_journey()

        if initial_ready and profile_name == "desktop-local-applet":
            run_local_applet_journey()

        if initial_ready and profile_name == "desktop-resource":
            run_shared_resource_journey()

        if initial_ready and profile_name == "desktop-recovery":
            recovery_text = session.snapshot().text()
            if "[1:" in recovery_text or "Agent: " in recovery_text:
                journey_errors.append(
                    "Practice recovery launched an applet or Agent service"
                )

        if initial_ready and profile_name == "desktop-codex-live":
            session.send_key("alt+5")
            if wait_screen(
                "[5:Agent*]",
                "Desk did not focus Agent for the live auth diagnostic",
            ):
                session.send_key("f9")
                if wait_screen(
                    "Agent account",
                    "Agent did not open the live account panel",
                ):
                    session.send_key("enter")
                    wait_screen(
                        "Browser authorization is pending.",
                        "Desk did not advance native auth to the device-code state",
                        step_budget=4_000_000_000,
                        wall_timeout=120.0,
                    )

        if initial_ready and profile_name in ("desktop", "pad"):
            if profile_name == "desktop":
                session.send_key("alt+1")
                wait_screen(
                    "[1:Akashic Pa*]",
                    "Desk did not focus Pad before its edit journey",
                )
            session.send_text("smoke")
            if wait_screen("smoke", "typing did not reach Pad's textarea"):
                content_hits = [
                    (row, col)
                    for row, col in screen.find("smoke")
                    if row >= 3
                ]
                if not content_hits:
                    journey_errors.append("Pad content was not present in the editor grid")
                else:
                    row, col = content_hits[0]
                    caret_col = col + len("smoke")
                    if not (screen.cells[row][caret_col].attrs & 32):
                        journey_errors.append("Pad did not paint its software caret")
                    if screen.lines()[row][max(0, col - 4):col] != "  1 ":
                        journey_errors.append("Pad's compact line-number gutter is malformed")
                session.send_key("ctrl+z")
                if wait_screen_gone("smoke", "Ctrl+Z did not undo Pad input"):
                    session.send_key("ctrl+y")
                    if wait_screen("smoke", "Ctrl+Y did not redo Pad input"):
                        session.send_key("tab")
                        report = session.run(
                            max_steps=min(150_000_000, max_steps - total_steps),
                            wall_timeout_s=min(
                                4.0, max(0.05, deadline - time.monotonic())
                            ),
                        )
                        total_steps += report.steps
                        screen = session.snapshot()
                        tab_hits = [
                            (row, col)
                            for row, col in screen.find("smoke")
                            if row >= 3
                        ]
                        if not tab_hits or not (
                            screen.cells[tab_hits[0][0]][tab_hits[0][1] + 8].attrs
                            & 32
                        ):
                            journey_errors.append(
                                "Pad Tab did not advance to a four-column stop"
                            )
                        session.send_key("ctrl+z")
                        report = session.run(
                            max_steps=min(150_000_000, max_steps - total_steps),
                            wall_timeout_s=min(
                                4.0, max(0.05, deadline - time.monotonic())
                            ),
                        )
                        total_steps += report.steps
                        screen = session.snapshot()
                        undo_hits = [
                            (row, col)
                            for row, col in screen.find("smoke")
                            if row >= 3
                        ]
                        if not undo_hits or not (
                            screen.cells[undo_hits[0][0]][undo_hits[0][1] + 5].attrs
                            & 32
                        ):
                            journey_errors.append(
                                "Pad Tab indentation did not undo as one edit"
                            )
                        session.send_key("ctrl+s")
                        if wait_screen(
                            "Save as:", "Ctrl+S did not open Pad's Save As prompt"
                        ):
                            session.send_text("smoke.txt")
                            session.send_key("enter")
                            if wait_screen_gone(
                                "Save as:", "Pad did not close its Save As prompt"
                            ) and wait_screen(
                                "smoke.txt", "Pad did not adopt its saved filename"
                            ):
                                live_fs = MP64FS(
                                    bytearray(session.system.storage._image_data)
                                )
                                try:
                                    saved = live_fs.read_file("smoke.txt")
                                except FileNotFoundError:
                                    saved = None
                                if saved != b"smoke":
                                    journey_errors.append(
                                        "Pad Save As did not persist exact file bytes"
                                    )
                                try:
                                    welcome = live_fs.read_file("welcome.txt")
                                except FileNotFoundError:
                                    welcome = None
                                if welcome != SAMPLE_FILES["welcome.txt"]:
                                    journey_errors.append(
                                        "Pad Save As damaged an existing disk file"
                                    )
                                if live_fs.find_file("kdos.f") is None:
                                    journey_errors.append(
                                        "Pad Save As damaged the MP64FS directory"
                                    )

        if initial_ready and profile_name == "daybook":
            session.send_key("ctrl+n")
            if wait_screen(
                "New task:", "Ctrl+N did not open Daybook's task prompt"
            ):
                session.send_text("Ship the smoke journey")
                session.send_key("enter")
                if wait_screen(
                    "Ship the smoke journey",
                    "Daybook did not add the submitted task",
                ):
                    session.send_text(" ")
                    if wait_screen(
                        "[x] Ship the smoke journey",
                        "Daybook did not complete the selected task",
                    ):
                        live_fs = MP64FS(
                            bytearray(session.system.storage._image_data)
                        )
                        try:
                            daybook = live_fs.read_file("daybook.md")
                        except FileNotFoundError:
                            daybook = b""
                        expected = (
                            f"- [x] {SAMPLE_DATE} | "
                            "Ship the smoke journey\n"
                        ).encode()
                        if expected not in daybook:
                            journey_errors.append(
                                "Daybook did not persist the completed task"
                            )

        if initial_ready and profile_name == "grid":
            for _ in range(3):
                session.send_key("right")
            session.send_key("down")
            session.send_key("enter")
            if wait_screen(
                "Edit cell:", "Enter did not open Grid's cell editor"
            ):
                for _ in range(len("=B2*C2")):
                    session.send_key("backspace")
                session.send_text("=B2*C2+5")
                session.send_key("enter")
                if wait_screen(
                    "41",
                    "Grid did not evaluate the edited formula",
                    step_budget=600_000_000,
                    wall_timeout=15.0,
                ):
                    wait_screen(
                        "91", "Grid did not recalculate the dependent SUM range"
                    )
                    session.send_key("ctrl+s")
                    wait_screen(
                        "Grid saved", "Ctrl+S did not save Grid's worksheet"
                    )
                    session.send_key("ctrl+r")
                    wait_screen(
                        "Grid reloaded",
                        "Grid could not reload its autosaved worksheet",
                    )
                    live_fs = MP64FS(
                        bytearray(session.system.storage._image_data)
                    )
                    try:
                        worksheet = live_fs.read_file("grid.csv")
                    except FileNotFoundError:
                        worksheet = b""
                    if b'"Paper, A4",3,12,=B2*C2+5\n' not in worksheet:
                        journey_errors.append(
                            "Grid did not persist the edited formula as CSV"
                        )
                    session.send_key("ctrl+g")
                    if wait_screen(
                        "Go to cell:", "Grid did not reopen Go to Cell"
                    ):
                        for _ in range(len("D2")):
                            session.send_key("backspace")
                        session.send_text("A6")
                        session.send_key("enter")
                        if wait_screen("A6", "Grid did not navigate to A6"):
                            session.send_key("enter")
                            if wait_screen(
                                "Edit cell:",
                                "Grid did not edit the cycle-test cell",
                            ):
                                session.send_text("=A6")
                                session.send_key("enter")
                                if wait_screen(
                                    "#ERR",
                                    "Grid did not report a self-reference cycle",
                                ):
                                    session.send_key("delete")
                                    wait_screen_gone(
                                        "#ERR",
                                        "Grid did not recover after clearing the cycle",
                                    )
                                    session.send_key("ctrl+s")
                                    wait_screen(
                                        "Grid saved",
                                        "Grid did not save after cycle recovery",
                                    )
                                    for _ in range(4):
                                        session.send_key("up")
                                    for _ in range(3):
                                        session.send_key("right")
                                    wait_screen(
                                        "D2", "Grid did not return to the edited formula"
                                    )

        if initial_ready and profile_name == "agent-ui":
            session.send_key("ctrl+l")
            if wait_screen("Ask:", "Ctrl+L did not open Agent's composer"):
                session.send_text("hello agent")
                session.send_key("enter")
                if wait_screen(
                    "hello agent",
                    "Agent did not stream the provider response",
                    step_budget=600_000_000,
                    wall_timeout=15.0,
                ):
                    wait_screen("Ready", "Agent did not finish the streamed run")

            session.send_key("ctrl+l")
            if wait_screen("Ask:", "Agent did not reopen its composer"):
                session.send_text("approval check")
                session.send_key("enter")
                if wait_screen(
                    "Review required",
                    "Agent did not surface the provider approval request",
                    step_budget=600_000_000,
                    wall_timeout=15.0,
                ):
                    wait_screen(
                        "Persist the simulated change?",
                        "Agent did not show the approval reason",
                    )
                    session.send_key("f6")
                    if wait_screen_gone(
                        "Review required",
                        "F6 did not resolve Agent's approval request",
                    ):
                        wait_screen("Approved.", "Agent did not record approval")

            session.send_key("ctrl+l")
            if wait_screen("Ask:", "Agent did not open its denial composer"):
                session.send_text("approval denial check")
                session.send_key("enter")
                if wait_screen(
                    "Review required",
                    "Agent did not surface the denial review request",
                    step_budget=600_000_000,
                    wall_timeout=15.0,
                ):
                    session.send_key("f7")
                    if wait_screen_gone(
                        "Review required",
                        "F7 did not resolve Agent's denial request",
                    ):
                        wait_screen("Denied.", "Agent did not record denial")

            session.send_key("ctrl+l")
            if wait_screen("Ask:", "Agent did not open its third prompt"):
                session.send_text("cancel this run")
                session.send_key("enter")
                session.send_key("escape")
                if wait_screen(
                    "Cancelled", "Escape did not cancel Agent's active run"
                ):
                    session.send_key("ctrl+l")
                    if wait_screen(
                        "Ask:", "Agent could not compose after cancellation"
                    ):
                        session.send_text("recovered after cancel")
                        session.send_key("enter")
                        wait_screen(
                            "recovered after cancel",
                            "Agent could not start a run after cancellation",
                            step_budget=600_000_000,
                            wall_timeout=15.0,
                        )
                        wait_screen(
                            "Ready", "Agent did not recover to its ready state"
                        )

        if initial_ready and profile_name == "agent-auth-ui":
            fixture_secret = "credential-must-not-render"
            session.send_key("ctrl+k")
            if wait_screen(
                "Credential:", "Ctrl+K did not open the credential prompt"
            ):
                session.send_text(fixture_secret)
                if wait_screen(
                    "********",
                    "Credential input was not visibly masked",
                ):
                    masked_text = session.snapshot().text()
                    if fixture_secret in masked_text:
                        journey_errors.append(
                            "Credential plaintext appeared in the rendered screen"
                        )
                session.send_key("escape")
                if wait_screen_gone(
                    "Credential:", "Escape did not close the credential prompt"
                ):
                    if fixture_secret in session.snapshot().text():
                        journey_errors.append(
                            "Cancelled credential remained in the rendered screen"
                        )

            session.send_key("ctrl+k")
            if wait_screen(
                "Credential:", "Credential prompt could not be reopened"
            ):
                session.send_text(fixture_secret)
                session.send_key("enter")
                wait_screen("Ready", "Credential submission did not connect provider")
                wait_screen_gone(
                    "Credential required",
                    "Credential submission left the provider unauthenticated",
                )
                session.send_key("ctrl+shift+k")
                wait_screen(
                    "Credential required",
                    "Credential clear did not return to unauthenticated state",
                )

        if initial_ready and profile_name == "agent-device-ui":
            session.send_key("f9")
            if wait_screen(
                "Agent account", "F9 did not open the account panel"
            ):
                session.send_key("enter")
                if wait_screen(
                    "AKASHIC-7H2K",
                    "Device sign-in did not expose its user code",
                ):
                    wait_screen(
                        "https://auth.openai.com/codex/device",
                        "Device sign-in did not expose its verification address",
                    )
                    wait_screen(
                        "Connected",
                        "Device authorization did not complete",
                        step_budget=600_000_000,
                        wall_timeout=15.0,
                    )
                session.send_key("escape")
                wait_screen_gone(
                    "Agent account", "Escape did not close the account panel"
                )

            session.send_key("f8")
            if wait_screen(
                "Run settings", "F8 did not open run settings"
            ) and wait_screen(
                "Swift",
                "Run settings did not receive the discovered model catalog",
                step_budget=600_000_000,
                wall_timeout=15.0,
            ):
                session.send_key("right")
                wait_screen("Deliberate", "Model selection did not advance")
                session.send_key("down")
                session.send_key("right")
                wait_screen("Low", "Reasoning selection did not advance")
                session.send_key("down")
                session.send_key("right")
                wait_screen("Fast", "Speed selection did not advance")
                session.send_key("down")
                session.send_key("right")
                wait_screen("Verbosity", "Verbosity row was not interactive")
                session.send_key("escape")
                wait_screen_gone(
                    "Run settings", "Escape did not close run settings"
                )

            session.send_key("ctrl+l")
            if wait_screen("Ask:", "Authorized Agent could not compose"):
                session.send_text("device flow smoke")
                session.send_key("enter")
                wait_screen(
                    "device flow smoke",
                    "Authorized Agent did not complete a conversation",
                    step_budget=600_000_000,
                    wall_timeout=15.0,
                )

        if initial_ready and profile_name not in ("interop", "resource-contracts"):
            session.resize(cols + 8, rows + 2)
            resize_budget = min(250_000_000, max_steps - total_steps)
            if resize_budget > 0 and time.monotonic() < deadline:
                report = session.run(
                    max_steps=resize_budget,
                    wall_timeout_s=min(
                        8.0, max(0.05, deadline - time.monotonic())
                    ),
                )
                total_steps += report.steps
            screen = session.snapshot()
            resized_text = screen.text()
            if (screen.cols, screen.rows) != (cols + 8, rows + 2):
                journey_errors.append("host terminal did not resize")
            missing_after_resize = [
                marker
                for marker in profile.stable_markers
                if marker not in resized_text
            ]
            if missing_after_resize:
                journey_errors.append(
                    "layout lost after resize: " + ", ".join(missing_after_resize)
                )
            if profile_name in ("desktop", "pad") and "smoke" not in resized_text:
                journey_errors.append("Pad text was lost after resize")
            if (
                profile_name == "daybook"
                and "Ship the smoke journey" not in resized_text
            ):
                journey_errors.append("Daybook entries were lost after resize")
            if profile_name == "grid" and not all(
                marker in resized_text for marker in ("41", "91")
            ):
                journey_errors.append("Grid formula results were lost after resize")
            if profile_name == "agent-ui" and not all(
                marker in resized_text
                for marker in (
                    "hello agent",
                    "approval check",
                    "recovered after cancel",
                )
            ):
                journey_errors.append(
                    "Agent transcript or run state was lost after resize"
                )
            if (
                profile_name == "desktop"
                and resized_text.count("[1:Akashic Pa") != 1
            ):
                journey_errors.append("Desk left a stale taskbar after resize")

        if initial_ready and profile_name in ("desktop", "pad"):
            session.send_key("ctrl+o")
            if wait_screen("Open:", "Ctrl+O did not open Pad's path prompt"):
                session.send_text("/welcome.txt")
                session.send_key("enter")
                if wait_screen(
                    "Welcome to Ak", "Pad could not open /welcome.txt"
                ):
                    session.send_key("ctrl+f")
                    if wait_screen("Find:", "Ctrl+F did not open Find"):
                        session.send_text("editable")
                        session.send_key("enter")
                        if profile_name == "pad":
                            wait_screen(
                                "Ln 2",
                                "Pad did not move to the matched search line",
                                step_budget=500_000_000,
                                wall_timeout=15.0,
                            )
                        else:
                            wait_screen_gone(
                                "Find:", "Pad did not complete Find"
                            )
                    session.send_key("ctrl+g")
                    if wait_screen(
                        "Go to line:", "Ctrl+G did not open Go to Line"
                    ):
                        session.send_text("2")
                        session.send_key("enter")
                        wait_screen_gone(
                            "Go to line:", "Pad did not close Go to Line"
                        )

        if initial_ready and profile_name == "pad":
            session.send_key("ctrl+o")
            if wait_screen("Open:", "Pad did not reopen its path prompt"):
                session.send_text("/large.txt")
                session.send_key("enter")
                if wait_screen(
                    "Large fixture line 048",
                    "Pad could not open the large MP64FS fixture",
                ):
                    session.send_key("ctrl+shift+s")
                    if wait_screen(
                        "Save as:", "Ctrl+Shift+S did not open Save As"
                    ):
                        for _ in range(len("/large.txt")):
                            session.send_key("backspace")
                        session.send_text("large-copy.txt")
                        session.send_key("enter")
                        if wait_screen_gone(
                            "Save as:", "large Save As did not finish"
                        ) and wait_screen(
                            "large-copy.txt",
                            "Pad did not adopt the large copy filename",
                        ):
                            live_fs = MP64FS(
                                bytearray(session.system.storage._image_data)
                            )
                            try:
                                copied = live_fs.read_file("large-copy.txt")
                            except FileNotFoundError:
                                copied = None
                            if copied != LARGE_SAMPLE:
                                journey_errors.append(
                                    "fragmented Save As did not persist exact bytes"
                                )
                            found = live_fs.find_file("large-copy.txt")
                            if found is None or found[1].ext1_count == 0:
                                journey_errors.append(
                                    "large Save As did not exercise a secondary extent"
                                )

                            session.send_key("ctrl+g")
                            if wait_screen(
                                "Go to line:",
                                "word-selection setup did not open Go to Line",
                            ):
                                session.send_text("1")
                                session.send_key("enter")
                                wait_screen_gone(
                                    "Go to line:",
                                    "word-selection setup did not finish",
                                )
                            session.send_key("ctrl+d")
                            session.send_text("Wide")
                            word_expected = LARGE_SAMPLE.replace(
                                b"Large", b"Wide", 1
                            )
                            if wait_screen(
                                "Wide fixture line 001",
                                "Ctrl+D did not select exactly the current word",
                            ):
                                session.send_key("ctrl+s")
                                if wait_screen_gone(
                                    "large-copy.txt*",
                                    "word replacement did not save",
                                ):
                                    live_fs = MP64FS(
                                        bytearray(
                                            session.system.storage._image_data
                                        )
                                    )
                                    if live_fs.read_file(
                                        "large-copy.txt"
                                    ) != word_expected:
                                        journey_errors.append(
                                            "word replacement saved incorrect bytes"
                                        )

                            session.send_key("ctrl+g")
                            if wait_screen(
                                "Go to line:",
                                "line-selection setup did not open Go to Line",
                            ):
                                session.send_text("2")
                                session.send_key("enter")
                                wait_screen_gone(
                                    "Go to line:",
                                    "line-selection setup did not finish",
                                )
                            session.send_key("ctrl+l")
                            session.send_text("Replacement line.")
                            if wait_screen(
                                "Replacement line.",
                                "Ctrl+L did not replace the current line",
                            ):
                                session.send_key("enter")
                                if wait_screen(
                                    "Ln 3, Col 1",
                                    "line replacement did not retain a line break",
                                ):
                                    session.send_key("ctrl+s")
                                    if wait_screen_gone(
                                        "large-copy.txt*",
                                        "line replacement did not save",
                                    ):
                                        lines = word_expected.splitlines(
                                            keepends=True
                                        )
                                        lines[1] = b"Replacement line.\n"
                                        line_expected = b"".join(lines)
                                        live_fs = MP64FS(
                                            bytearray(
                                                session.system.storage._image_data
                                            )
                                        )
                                        if live_fs.read_file(
                                            "large-copy.txt"
                                        ) != line_expected:
                                            journey_errors.append(
                                                "line replacement saved incorrect bytes"
                                            )

        if initial_ready and profile_name == "desktop":
            run_desk_agent_journey()

        if initial_ready and profile_name in (
            "desktop",
            "desktop-agent",
            "fexplorer",
        ):
            if profile_name in (
                "desktop",
                "desktop-agent",
            ):
                session.send_key("alt+2")
            session.send_key("ctrl+g")
            if wait_screen(
                "Go to:", "File Explorer's Go to Path prompt did not open"
            ):
                session.send_text("example.f")
                session.send_key("enter")
                wait_screen("SQUARE", "File Explorer could not preview /example.f")

            if profile_name in (
                "desktop",
                "desktop-agent",
            ):
                session.send_key("ctrl+o")
                if wait_screen(
                    "[1:Akashic Pa*]",
                    "resource.open did not route File Explorer's selection to Pad",
                ):
                    wait_desktop_tile(
                        "SQUARE DUP",
                        0,
                        "Pad did not open the resource delivered by Desk",
                    )
                session.send_key("alt+2")
                wait_screen(
                    "[2:File Explo*]",
                    "Desk did not return to File Explorer after resource.open",
                )

            if profile_name == "fexplorer":
                session.send_key("ctrl+n")
                if wait_screen(
                    "New file:", "Ctrl+N did not open New File"
                ):
                    session.send_text("journey.txt")
                    session.send_key("enter")
                    if wait_screen_gone(
                        "New file:", "File Explorer did not create a file"
                    ):
                        wait_screen(
                            "journey.txt",
                            "created file did not appear in the detail list",
                        )

                session.send_key("f2")
                if wait_screen("Rename:", "F2 did not open Rename"):
                    for _ in range(len("journey.txt")):
                        session.send_key("backspace")
                    session.send_text("renamed.txt")
                    session.send_key("enter")
                    if wait_screen_gone(
                        "Rename:", "File Explorer did not finish Rename"
                    ):
                        wait_screen(
                            "renamed.txt",
                            "renamed file did not appear in the detail list",
                        )

                session.send_key("ctrl+c")
                wait_screen(
                    "Copied to clipboard",
                    "Ctrl+C did not capture the active file",
                )
                session.send_key("ctrl+shift+n")
                if wait_screen(
                    "New folder:", "Ctrl+Shift+N did not open New Folder"
                ):
                    session.send_text("dest")
                    session.send_key("enter")
                    if wait_screen_gone(
                        "New folder:", "File Explorer did not create a folder"
                    ):
                        wait_screen(
                            "dest", "created folder did not appear in the detail list"
                        )
                session.send_key("ctrl+v")
                wait_screen("Pasted!", "Ctrl+V did not copy into the new folder")

                live_fs = MP64FS(bytearray(session.system.storage._image_data))
                old_entry = live_fs.find_file("journey.txt")
                renamed_entry = live_fs.find_file("renamed.txt")
                dest_slot = None
                try:
                    dest_slot = live_fs.resolve_path("/dest")
                    nested = live_fs.read_file("renamed.txt", parent=dest_slot)
                except FileNotFoundError:
                    nested = None
                if old_entry is not None or renamed_entry is None:
                    root_names = [
                        entry.name
                        for entry in live_fs.list_files(parent=0xFF)
                    ]
                    journey_errors.append(
                        "Explorer rename was not persisted to MP64FS "
                        f"(root={root_names})"
                    )
                if nested != b"":
                    nested_names = []
                    if dest_slot is not None:
                        nested_names = [
                            entry.name
                            for entry in live_fs.list_files(parent=dest_slot)
                        ]
                    journey_errors.append(
                        "Explorer copy/paste did not persist the nested file "
                        f"(dest={nested_names})"
                    )

                session.send_key("ctrl+g")
                if wait_screen(
                    "Go to:", "delete setup did not open Go To"
                ):
                    session.send_text("dest/renamed.txt")
                    session.send_key("enter")
                    if wait_screen_gone(
                        "Go to:", "delete setup did not resolve the nested file"
                    ):
                        session.send_key("delete")
                        if wait_screen(
                            "Delete the selected item?",
                            "Delete did not open its confirmation dialog",
                        ):
                            session.send_key("enter")
                            wait_screen_gone(
                                "Delete the selected item?",
                                "nested file deletion did not finish",
                            )

                live_fs = MP64FS(bytearray(session.system.storage._image_data))
                try:
                    dest_slot = live_fs.resolve_path("/dest")
                    live_fs.read_file("renamed.txt", parent=dest_slot)
                except FileNotFoundError:
                    pass
                else:
                    journey_errors.append(
                        "Explorer delete did not remove the nested file"
                    )

                session.send_key("delete")
                if wait_screen(
                    "Delete the selected item?",
                    "empty-folder Delete did not open confirmation",
                ):
                    session.send_key("enter")
                    wait_screen_gone(
                        "Delete the selected item?",
                        "empty-folder deletion did not finish",
                    )
                live_fs = MP64FS(bytearray(session.system.storage._image_data))
                try:
                    live_fs.resolve_path("/dest")
                except FileNotFoundError:
                    pass
                else:
                    journey_errors.append(
                        "Explorer delete did not remove the empty destination folder"
                    )

                # Drive one ordinary post-dialog event before inspecting the
                # final list repaint; standalone Explorer has no Desk hotbar,
                # so Alt+1 is intentionally unclaimed here.
                session.send_key("alt+1")
                wait_screen(
                    "renamed.txt",
                    "File Explorer did not return to the populated Details view",
                )
                wait_screen_gone(
                    "Pasted!",
                    "File Explorer toast did not expire",
                    step_budget=150_000_000,
                    wall_timeout=3.0,
                )
            screen = session.snapshot()
            if profile_name in (
                "desktop",
                "desktop-agent",
            ):
                final_text = screen.text()
                if "1smoke2" in final_text or "smoke2" in final_text:
                    journey_errors.append(
                        "Desk global app shortcuts leaked digits into Pad"
                    )
                if "[2:File Explo*]" not in final_text:
                    journey_errors.append(
                        "Desk did not leave File Explorer focused after Alt+2"
                    )

        capture_root = OUTPUT_ROOT / f"smoke-{profile_name}"
        screen.write_text(capture_root.with_suffix(".txt"))
        screen.write_json(capture_root.with_suffix(".cells.json"))
        screen.write_png(
            capture_root.with_suffix(".png"),
            font_path=AKASHIC_ROOT / "assets/fonts/DejaVuSansMono.ttf",
        )

        raw = session.raw_text()
        capture_root.with_suffix(".raw.txt").write_text(
            raw, encoding="utf-8"
        )
        errors = _has_forth_error(raw)
        missing = [m for m in profile.stable_markers if m not in screen.text()]
        elapsed = time.perf_counter() - started
        ok = not errors and not missing and not journey_errors

        print(
            f"Smoke {profile_name}: {'PASS' if ok else 'FAIL'}\n"
            f"  {total_steps:,} steps in {elapsed:.2f}s; "
            f"screen={screen.cols}x{screen.rows}; raw={len(session.raw_output):,} bytes; "
            f"stop={stop_reason}"
        )
        if missing:
            print(f"  missing screen markers: {', '.join(missing)}")
        if errors:
            print("  guest errors:")
            for line in errors[-12:]:
                print(f"    {line}")
        if journey_errors:
            print("  journey errors:")
            for error in journey_errors:
                print(f"    {error}")
        if not ok and nic_backend is not None:
            stats = nic_backend.stats()
            print(
                "  TAP diagnostics: "
                f"tx={stats['tx_frames']} frames/{stats['tx_bytes']} bytes; "
                f"rx={stats['rx_frames']} frames/{stats['rx_bytes']} bytes; "
                f"errors={stats['tx_errors']}"
            )
            for label in (
                "first_tx_hex",
                "first_rx_hex",
                "last_tx_hex",
                "last_rx_hex",
            ):
                if stats[label] is not None:
                    print(f"    {label}: {stats[label]}")
            if stats["error"] is not None:
                print(f"    backend error: {stats['error']}")
            print("    bounded frame trace:")
            for index, frame in enumerate(stats["frame_trace"]):
                print(
                    f"      {index:02d} {frame['direction']} "
                    f"len={frame['length']}: {frame['prefix_hex']}"
                )
        print(f"  captures: {capture_root}.[txt|raw.txt|cells.json|png]")
        if not ok:
            print("  recent guest output:")
            excerpt = raw[-3000:].replace("\r", "")
            for line in excerpt.splitlines()[-30:]:
                print(f"    {line[:500]}")
        return ok


def serve(
    profile_name: str,
    image_path: Path,
    *,
    socket_path: str,
    cols: int,
    rows: int,
    ext_mem_mib: int = DEFAULT_EXT_MEM_MIB,
    nic_tap: str | None = None,
):
    if PROFILES[profile_name].requires_tap and not nic_tap:
        raise SystemExit(
            f"profile {profile_name!r} requires --nic-tap[=IFNAME]"
        )
    command = [
        sys.executable,
        str(MEGAPAD_ROOT / "session_server.py"),
        "--bios",
        str(MEGAPAD_ROOT / "bios.asm"),
        "--storage",
        str(image_path),
        "--socket",
        socket_path,
        "--cols",
        str(cols),
        "--rows",
        str(rows),
        "--batch-steps",
        "500000",
        "--ext-mem-mib",
        str(ext_mem_mib),
    ]
    if nic_tap:
        command.extend(("--nic-tap", nic_tap))
    os.execv(sys.executable, command)


def _positive_mib(value: str) -> int:
    try:
        parsed = int(value)
    except ValueError as exc:
        raise argparse.ArgumentTypeError("must be an integer") from exc
    if parsed <= 0:
        raise argparse.ArgumentTypeError("must be greater than zero")
    return parsed


def _parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)

    for name in ("build", "smoke", "serve"):
        command = commands.add_parser(name)
        command.add_argument(
            "--profile", choices=tuple(PROFILES), default="desktop"
        )
        command.add_argument("--output", type=Path)
        command.add_argument(
            "--codex-auth-checkpoint",
            type=Path,
            help="seed a private local Codex Desk image from a mode-0600 checkpoint",
        )
        if name in ("smoke", "serve"):
            command.add_argument("--cols", type=int, default=100)
            command.add_argument("--rows", type=int, default=32)
            command.add_argument(
                "--ext-mem-mib",
                type=_positive_mib,
                default=DEFAULT_EXT_MEM_MIB,
                help="emulated external memory in MiB (default: 32)",
            )
            command.add_argument(
                "--nic-tap",
                nargs="?",
                const="mp64tap0",
                help="attach a preconfigured Linux TAP device",
            )
        if name == "smoke":
            command.add_argument("--max-steps", type=int, default=4_000_000_000)
            command.add_argument("--timeout", type=float, default=75.0)
        if name == "serve":
            command.add_argument("--socket", default="/tmp/akashic-tui.sock")

    return parser


def main() -> int:
    args = _parser().parse_args()
    image_path = build_image(
        args.profile, args.output, args.codex_auth_checkpoint
    )
    if args.command == "build":
        return 0
    if args.command == "smoke":
        return 0 if smoke(
            args.profile,
            image_path,
            cols=args.cols,
            rows=args.rows,
            max_steps=args.max_steps,
            timeout=args.timeout,
            ext_mem_mib=args.ext_mem_mib,
            nic_tap=args.nic_tap,
        ) else 1
    serve(
        args.profile,
        image_path,
        socket_path=args.socket,
        cols=args.cols,
        rows=args.rows,
        ext_mem_mib=args.ext_mem_mib,
        nic_tap=args.nic_tap,
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
