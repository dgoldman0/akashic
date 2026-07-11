#!/usr/bin/env python3
"""Build, smoke-test, and serve bootable Akashic TUI environments.

This is the supported cross-repository harness.  It imports the sibling
MegaPad checkout (or ``MEGAPAD_ROOT``), computes the transitive REQUIRE
closure for the selected app profile, and preserves Akashic's paths in an
MP64FS image.  No private emulator copy is required.
"""

from __future__ import annotations

import argparse
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

: _ts-run  ( -- )
    0 _ts-fails ! 0 _ts-checks ! DEPTH _ts-depth !
    524288 A-XMEM ARENA-NEW
    DUP 0= _ts-assert DROP
    VFS-RAM-VTABLE VFS-NEW DUP _ts-vfs ! VFS-USE
    ACONV-NEW DUP 0= _ts-assert DROP _ts-conv !

    AROLE-USER AMSG-S-COMPLETE 1 S" first durable message"
    _ts-conv @ ACONV-APPEND DUP 0= _ts-assert DROP
    DUP AMSG-F-AUDIT SWAP AMSG.FLAGS ! DROP
    _ts-new-store DUP _ts-store !
    _ts-conv @ SWAP ACSTORE-SAVE ACSTORE-S-OK = _ts-assert
    _ts-store @ AVFSSTORE.GENERATION @ 1 = _ts-assert
    _ts-store @ AVFSSTORE.ACTIVE-SLOT @ 0= _ts-assert

    AROLE-ASSISTANT AMSG-S-STREAMING 2 S" interrupted output"
    _ts-conv @ ACONV-APPEND DUP 0= _ts-assert DROP DROP
    _ts-conv @ _ts-store @ ACSTORE-SAVE ACSTORE-S-OK = _ts-assert
    _ts-store @ AVFSSTORE.GENERATION @ 2 = _ts-assert
    _ts-store @ AVFSSTORE.ACTIVE-SLOT @ 1 = _ts-assert

    _ts-new-store DUP _ts-store2 ! ACSTORE-LOAD
    DUP ACSTORE-S-OK = _ts-assert DROP DUP _ts-loaded ! DROP
    _ts-store2 @ AVFSSTORE.GENERATION @ 2 = _ts-assert
    _ts-loaded @ ACONV.COUNT @ 3 = _ts-assert
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
    0 _ts-loaded @ ACONV-NTH AMSG-TEXT
    S" first durable message" STR-STR= _ts-assert
    _ts-loaded @ ACONV-FREE

    _AVFS-PATH-A _ts-corrupt
    _ts-new-store DUP _ts-store4 ! ACSTORE-LOAD
    ACSTORE-S-INVALID = _ts-assert 0= _ts-assert

    _ts-store4 @ ACSTORE-FREE
    _ts-store3 @ ACSTORE-FREE
    _ts-store2 @ ACSTORE-FREE
    _ts-store @ ACSTORE-FREE
    _ts-conv @ ACONV-FREE
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
            "agent/providers/testing/scripted.f",
        ),
        resources=(),
        autoexec=r"""\ autoexec.f - durable agent runtime lifecycle
ENTER-USERLAND
." [akashic] loading agent persistence lifecycle" CR
REQUIRE agent/storage/vfs-conversation.f
REQUIRE agent/providers/testing/scripted.f
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
    _ap-check-audit
    _ap-runtime @ ARUNTIME.STORE-STATUS @ ACSTORE-S-OK = _ap-assert
    _ap-close _ap-stack

    _ap-open 2 _ap-pump
    _ap-conv @ ACONV.COUNT @ 4 = _ap-assert
    _ap-check-audit
    _ap-runtime @ ARUNTIME.NEXT-RUN @ 2 = _ap-assert
    S" approval interrupted persistence" _ap-runtime @ ARUNTIME-SEND
    0= _ap-assert
    4 _ap-pump
    _ap-runtime @ ARUNTIME.STATUS @ ARUN-S-APPROVAL = _ap-assert
    _ap-conv @ ACONV.COUNT @ 7 = _ap-assert
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
    _ap-runtime @ ARUNTIME-CLEAR 0= _ap-assert
    _ap-conv @ ACONV.COUNT @ 0= _ap-assert
    _ap-close _ap-stack

    _ap-open 2 _ap-pump
    _ap-conv @ ACONV.COUNT @ 0= _ap-assert
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
        roots=("net/transports/megapad-tls.f", "utils/string.f"),
        resources=(),
        autoexec=r"""\ autoexec.f - MegaPad native TLS NIO adapter tests
ENTER-USERLAND
." [akashic] loading MegaPad TLS transport" CR
REQUIRE net/transports/megapad-tls.f
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

CREATE _mt-a MPTLS-SIZE ALLOT
CREATE _mt-b MPTLS-SIZE ALLOT
CREATE _mt-recv 32 ALLOT
CREATE _mt-sent 256 ALLOT
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
    _mt-bind-a @ MPTLS-INIT
    S" api.openai.com" 443 _mt-bind-a @ MPTLS-CONFIGURE
    MPTLS-E-OK = _mt-assert
    ['] _mt-dns _mt-bind-a @ MPTLS.DNS-XT !
    ['] _mt-connect _mt-bind-a @ MPTLS.CONNECT-XT !
    ['] _mt-send _mt-bind-a @ MPTLS.SEND-XT !
    ['] _mt-recv-op _mt-bind-a @ MPTLS.RECV-XT !
    ['] _mt-close _mt-bind-a @ MPTLS.CLOSE-XT !
    ['] _mt-poll _mt-bind-a @ MPTLS.POLL-XT !
    ['] _mt-status _mt-bind-a @ MPTLS.STATUS-XT ! ;

: _mt-test-config  ( -- )
    _mt-b MPTLS-INIT
    S" bad host" 443 _mt-b MPTLS-CONFIGURE MPTLS-E-INVALID = _mt-assert
    S" api.openai.com" 0 _mt-b MPTLS-CONFIGURE
    MPTLS-E-INVALID = _mt-assert
    S" api.openai.com" 443 MPTLS-NEW
    DUP MPTLS-E-OK = _mt-assert DROP
    DUP MPTLS-HOST S" api.openai.com" STR-STR= _mt-assert
    DUP MPTLS.REMOTE-PORT @ 443 = _mt-assert
    MPTLS-FREE ;

: _mt-test-open-and-io  ( -- )
    _mt-a _mt-bind _mt-b _mt-bind
    1 TLS-TRUST-COUNT ! MPTLS-LINK-OPEN _mt-link !
    _mt-a MPTLS.PORT NIO-OPEN NIO-S-OK = _mt-assert
    _mt-a MPTLS.STATE @ MPTLS-STATE-OPEN = _mt-assert
    _mt-a MPTLS.LAST-ERROR @ MPTLS-E-OK = _mt-assert
    TLS-SNI-HOST TLS-SNI-LEN @ S" api.openai.com" STR-STR= _mt-assert
    _mt-dns-hits @ 1 = _mt-assert
    _mt-connect-hits @ 1 = _mt-assert

    _mt-b MPTLS.PORT NIO-OPEN NIO-S-FAILED = _mt-assert
    _mt-b MPTLS.LAST-ERROR @ MPTLS-E-BUSY = _mt-assert

    S" 0123456789abcdefghijkl" _mt-a MPTLS.PORT NIO-SEND
    NIO-S-OK = _mt-assert 17 = _mt-assert
    _mt-sent _mt-sent-u @ S" 0123456789abcdefg" STR-STR= _mt-assert

    _mt-recv 32 _mt-a MPTLS.PORT NIO-RECV
    NIO-S-OK = _mt-assert 3 = _mt-assert
    _mt-recv 32 _mt-a MPTLS.PORT NIO-RECV
    NIO-S-OK = _mt-assert 2 = _mt-assert
    _mt-recv 32 _mt-a MPTLS.PORT NIO-RECV
    NIO-S-OK = _mt-assert 0= _mt-assert
    MPTLS-LINK-CLOSED _mt-link !
    _mt-recv 32 _mt-a MPTLS.PORT NIO-RECV
    NIO-S-EOF = _mt-assert 0= _mt-assert
    _mt-a MPTLS.PORT NIO-CLOSE
    _mt-close-hits @ 1 = _mt-assert

    MPTLS-LINK-OPEN _mt-link !
    _mt-b MPTLS.PORT NIO-OPEN NIO-S-OK = _mt-assert
    _mt-b MPTLS.PORT NIO-POLL
    _mt-poll-hits @ 1 = _mt-assert
    ['] _mt-close-throw _mt-b MPTLS.CLOSE-XT !
    _mt-b MPTLS.PORT NIO-CLOSE
    _mt-b MPTLS.STATE @ MPTLS-STATE-CLOSED = _mt-assert
    _mt-a MPTLS.PORT NIO-OPEN NIO-S-OK = _mt-assert
    _mt-a MPTLS.PORT NIO-CLOSE ;

: _mt-test-errors  ( -- )
    _mt-a _mt-bind
    0 TLS-TRUST-COUNT !
    _mt-a MPTLS.PORT NIO-OPEN NIO-S-FAILED = _mt-assert
    _mt-a MPTLS.LAST-ERROR @ MPTLS-E-NO-TRUST = _mt-assert
    1 TLS-TRUST-COUNT !
    ['] _mt-dns-zero _mt-a MPTLS.DNS-XT !
    _mt-a MPTLS.PORT NIO-OPEN NIO-S-FAILED = _mt-assert
    _mt-a MPTLS.LAST-ERROR @ MPTLS-E-DNS = _mt-assert
    ['] _mt-dns-throw _mt-a MPTLS.DNS-XT !
    _mt-a MPTLS.PORT NIO-OPEN NIO-S-FAILED = _mt-assert
    _mt-a MPTLS.LAST-ERROR @ MPTLS-E-FAULT = _mt-assert
    ['] _mt-dns _mt-a MPTLS.DNS-XT !
    MPTLS-LINK-OPEN _mt-link !
    _mt-a MPTLS.PORT NIO-OPEN NIO-S-OK = _mt-assert
    ['] _mt-send-bad _mt-a MPTLS.SEND-XT !
    S" bad" _mt-a MPTLS.PORT NIO-SEND
    NIO-S-FAILED = _mt-assert 0= _mt-assert
    _mt-a MPTLS.PORT NIO-CLOSE

    _mt-a _mt-bind 1 TLS-TRUST-COUNT ! MPTLS-LINK-OPEN _mt-link !
    _mt-a MPTLS.PORT NIO-OPEN NIO-S-OK = _mt-assert
    ['] _mt-recv-bad _mt-a MPTLS.RECV-XT !
    _mt-recv 32 _mt-a MPTLS.PORT NIO-RECV
    NIO-S-FAILED = _mt-assert 0= _mt-assert
    _mt-a MPTLS.PORT NIO-CLOSE ;

: _mt-run  ( -- )
    0 _mt-fails ! 0 _mt-checks ! DEPTH _mt-depth !
    TLS-TRUST-COUNT @ _mt-old-trust !
    0 _mt-sent-u ! 0 _mt-in-pos ! 0 _mt-dns-hits !
    0 _mt-connect-hits ! 0 _mt-close-hits ! 0 _mt-poll-hits !
    _mt-test-config
    _mt-test-open-and-io
    _mt-test-errors
    _mt-a MPTLS.PORT NIO-CLOSE
    _mt-b MPTLS.PORT NIO-CLOSE
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
CREATE _oc-event OPENAI-EVENT-SIZE ALLOT
CREATE _oc-port NET-IO-PORT-SIZE ALLOT
CREATE _oc-out 65536 ALLOT
VARIABLE _oc-out-u
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

: _oc-handler  ( request instance -- status )
    2DROP CBUS-S-OK ;

: _oc-setup-tools  ( -- )
    _oc-schema CS-INIT CV-T-STRING _oc-schema CS-ALLOW!
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

: _oc-start-request  ( -- status )
    S" Add milk to tomorrow's list" _oc-config _oc-gateway @
    _oc-out 65536 OAI-RESPONSES-START-JSON
    SWAP _oc-out-u ! ;

: _oc-test-config-and-request  ( -- )
    _oc-config OAIC-INIT
    _oc-credential CRED-INIT
    S" test-api-key" _oc-credential CRED-SET DROP
    _oc-credential _oc-config OAIC-CREDENTIAL! DROP
    _oc-config OAIC-HOST S" api.openai.com" STR-STR= _oc-assert
    _oc-config OAIC-PATH S" /v1/responses" STR-STR= _oc-assert
    _oc-config OAIC-MODEL S" gpt-5.5" STR-STR= _oc-assert
    _oc-config OAIC.MAX-OUTPUT @ 262144 = _oc-assert
    S" You assist the active Akashic applet."
    _oc-config OAIC-INSTRUCTIONS! OAIC-S-OK = _oc-assert
    S" bad host" _oc-config OAIC-HOST! OAIC-S-INVALID = _oc-assert
    _oc-setup-tools
    _oc-gateway @ ATOOLG-TOOL-N 1 = _oc-assert
    0 _oc-gateway @ ATOOLG-TOOL-NTH _oc-capability = _oc-assert
    _oc-gateway @ OAI-GATEWAY-TOOLS-VALID? _oc-assert
    _oc-port NIO-INIT
    _oc-config _oc-port OPENAI-PROVIDER-NEW
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

    _oc-json-begin JSON-[
        JSON-{ S" type" S" reasoning" JSON-KV-ESTR
        S" encrypted_content" S" abc" JSON-KV-ESTR JSON-}
        JSON-{ S" type" S" function_call" JSON-KV-ESTR
        S" call_id" S" call_1" JSON-KV-ESTR
        S" name" S" test" JSON-KV-ESTR
        S" arguments" S" {}" JSON-KV-ESTR JSON-}
    JSON-] _oc-json-end
    S" Add milk to tomorrow's list" _oc-json _oc-json-u @
    S" call_1" S" ok" _oc-config _oc-gateway @
    _oc-out 65536 OAI-RESPONSES-CONTINUE-JSON
    DUP OAIREQ-S-OK = _oc-assert DROP _oc-out-u !
    _oc-out _oc-out-u @ JSON-VALID? _oc-assert
    _oc-out _oc-out-u @ JSON-ENTER S" input" JSON-KEY JSON-ENTER
    JSON-COUNT 4 = _oc-assert
    _oc-out _oc-out-u @ JSON-ENTER S" input" JSON-KEY JSON-ENTER
    3 JSON-NTH JSON-ENTER S" type" JSON-KEY JSON-GET-STRING
    S" function_call_output" STR-STR= _oc-assert
    _oc-out _oc-out-u @ JSON-ENTER S" input" JSON-KEY JSON-ENTER
    3 JSON-NTH JSON-ENTER S" call_id" JSON-KEY JSON-GET-STRING
    S" call_1" STR-STR= _oc-assert

    _oc-config OAIC.FLAGS DUP @ OAIC-F-STORE OR SWAP !
    _oc-start-request OAIREQ-S-OK = _oc-assert
    _oc-out _oc-out-u @ S" include" JSON-FIELD
    DUP 0= _oc-assert DROP 0= _oc-assert 2DROP
    S" short" _oc-config 0 _oc-out 8 OAI-RESPONSES-START-JSON
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
    S" {" _oc-event OAIEV-PARSE OAIEV-S-INVALID = _oc-assert ;

: _oc-cleanup  ( -- )
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
            "agent/providers/openai/responses.f",
            "agent/runtime.f",
        ),
        resources=(),
        autoexec=r"""\ autoexec.f - native OpenAI provider fixture
ENTER-USERLAND
." [akashic] loading OpenAI provider fixture" CR
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
VARIABLE _op-opens
VARIABLE _op-closes
VARIABLE _op-polls
VARIABLE _op-send-a
VARIABLE _op-send-u
VARIABLE _op-send-n
VARIABLE _op-recv-a
VARIABLE _op-recv-u
VARIABLE _op-recv-n

CREATE _op-config OPENAI-CONFIG-SIZE ALLOT
CREATE _op-credential CREDENTIAL-SIZE ALLOT
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
    S" Content-Type: text/event-stream" _op-r, _op-crlf-r,
    S" Content-Length: " _op-r,
    _op-body-u @ NUM>STR _op-r, _op-crlf-r,
    S" Connection: close" _op-r, _op-crlf-r,
    _op-crlf-r,
    _op-body _op-body-u @ _op-r, ;

: _op-build-first-response  ( -- )
    0 _op-body-u ! _op-args-build
    S" resp_tool" _op-created,
    _op-tool-item,
    S" resp_tool" _op-completed,
    _op-http-wrap ;

: _op-build-final-response  ( -- )
    0 _op-body-u !
    S" resp_final" _op-created,
    _op-text,
    S" resp_final" _op-completed,
    _op-http-wrap ;

: _op-open  ( context -- status )
    DROP 1 _op-opens +! 0 _op-response-pos ! 0 _op-request-u !
    _op-opens @ 1 = IF _op-build-first-response ELSE _op-build-final-response THEN
    NIO-S-OK ;

: _op-close  ( context -- ) DROP 1 _op-closes +! ;
: _op-poll  ( context -- ) DROP 1 _op-polls +! ;

: _op-send  ( buffer length context -- count status )
    DROP _op-send-u ! _op-send-a !
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
    _op-port NIO-INIT
    ['] _op-open _op-port NIO.OPEN-XT !
    ['] _op-close _op-port NIO.CLOSE-XT !
    ['] _op-poll _op-port NIO.POLL-XT !
    ['] _op-send _op-port NIO.SEND-XT !
    ['] _op-recv _op-port NIO.RECV-XT !
    ." [openai-provider] port" CR

    _op-config OAIC-INIT
    _op-credential CRED-INIT
    S" test-api-key" _op-credential CRED-SET DROP
    _op-credential _op-config OAIC-CREDENTIAL! DROP
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

    _op-config _op-port OPENAI-PROVIDER-NEW DROP _op-provider !
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

: _op-test-run  ( -- )
    4 _op-runtime @ ARUNTIME-PUMP DROP
    _op-runtime @ ARUNTIME.STATUS @ ARUN-S-IDLE = _op-assert
    S" Please capture a milk task" _op-runtime @ ARUNTIME-SEND 0= _op-assert
    _op-pump-until-review
    _op-runtime @ ARUNTIME.STATUS @ ARUN-S-APPROVAL = _op-assert
    -1 _op-runtime @ ARUNTIME-RESOLVE 0= _op-assert
    _op-pump-until-idle
    _op-runtime @ ARUNTIME.STATUS @ ARUN-S-IDLE = _op-assert
    _op-opens @ 2 = _op-assert
    _op-closes @ 2 >= _op-assert
    _op-handler-hits @ 1 = _op-assert
    _op-credential CRED.USES @ 2 = _op-assert
    _op-request _op-request-u @ S" Authorization: Bearer "
    STR-STR-CONTAINS _op-assert
    _op-runtime @ ARUNTIME.CONVERSATION @ DUP ACONV.COUNT @ 0> _op-assert
    0 _op-found-text !
    DUP ACONV.COUNT @ 0 ?DO
        I OVER ACONV-NTH AMSG-TEXT S" Task captured."
        STR-STR-CONTAINS IF -1 _op-found-text ! THEN
    LOOP
    DROP _op-found-text @ _op-assert

    S" cancel now" _op-runtime @ ARUNTIME-SEND 0= _op-assert
    _op-runtime @ ARUNTIME-CANCEL 0= _op-assert
    4 _op-runtime @ ARUNTIME-PUMP DROP
    _op-runtime @ ARUNTIME.STATUS @ ARUN-S-CANCELLED = _op-assert ;

: _op-cleanup  ( -- )
    _op-runtime @ ARUNTIME-FREE
    _op-provider @ APROV-FREE
    _op-gateway @ ATOOLG-FREE
    _op-bus @ CBUS-FREE
    _op-instance @ _op-registry @ CREG-INST- DROP
    _op-registry @ CREG-FREE
    _op-instance @ CINST-FREE
    _op-credential CRED-CLEAR ;

: _op-run  ( -- )
    0 _op-fails ! 0 _op-checks ! DEPTH _op-depth !
    ." [openai-provider] setup" CR
    _op-setup
    ." [openai-provider] run" CR
    _op-test-run
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
    "openai-megapad": Profile(
        roots=(
            "agent/providers/openai/megapad.f",
            "agent/runtime.f",
            "utils/string.f",
        ),
        resources=(),
        autoexec=r"""\ autoexec.f - physical MegaPad OpenAI composition
ENTER-USERLAND
." [akashic] loading OpenAI MegaPad composition" CR
REQUIRE agent/providers/openai/megapad.f
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
    OPENAI-MEGAPAD-SOURCE-NEW
    DUP APSOURCE-S-OK = _om-assert DROP _om-source !
    _om-source @ DUP APSOURCE.ID-A @ SWAP APSOURCE.ID-U @
    S" org.akashic.agent.source.openai.megapad" STR-STR= _om-assert
    _om-source @ OPENAI-MEGAPAD-SOURCE-CONFIG OAIC-HOST
    S" api.openai.com" STR-STR= _om-assert
    _om-source @ OPENAI-MEGAPAD-SOURCE-TRANSPORT MPTLS-HOST
    S" api.openai.com" STR-STR= _om-assert
    _om-source @ OPENAI-MEGAPAD-SOURCE-TRANSPORT MPTLS.REMOTE-PORT @
    443 = _om-assert

    _om-source @ APSOURCE-PROVIDER-NEW
    DUP OAIR-S-OK = _om-assert DROP _om-provider !
    _om-provider @ APROV.FEATURES @ APROV-F-AUTH AND 0<> _om-assert
    _om-provider @ APROV-AUTH-PRESENT? 0= _om-assert
    _om-provider @ OPENAI-PROVIDER-CONFIG OAIC.CREDENTIAL @
    _om-source @ OPENAI-MEGAPAD-SOURCE-CREDENTIAL = _om-assert
    _om-provider @ APROV.CONTEXT @ OAIR-C.PORT @
    _om-source @ OPENAI-MEGAPAD-SOURCE-TRANSPORT MPTLS.PORT = _om-assert

    _om-provider @ ARUNTIME-NEW
    DUP 0= _om-assert DROP _om-runtime !
    _om-runtime @ ARUNTIME.STATUS @ ARUN-S-ERROR = _om-assert
    _om-runtime @ ARUNTIME-AUTH-PRESENT? 0= _om-assert
    S" local-fixture-secret" _om-runtime @ ARUNTIME-AUTH-SET
    APROV-AUTH-S-OK = _om-assert
    _om-runtime @ ARUNTIME-AUTH-PRESENT? _om-assert
    _om-source @ OPENAI-MEGAPAD-SOURCE-CREDENTIAL CRED.LENGTH @
    20 = _om-assert
    8 _om-runtime @ ARUNTIME-PUMP DROP
    _om-runtime @ ARUNTIME.STATUS @ ARUN-S-IDLE = _om-assert

    _om-runtime @ ARUNTIME-AUTH-CLEAR APROV-AUTH-S-OK = _om-assert
    _om-runtime @ ARUNTIME.STATUS @ ARUN-S-OFFLINE = _om-assert
    _om-runtime @ ARUNTIME-AUTH-PRESENT? 0= _om-assert
    _om-source @ OPENAI-MEGAPAD-SOURCE-CREDENTIAL _CRED-SECRET-A
    CRED-SECRET-CAPACITY _om-zero? _om-assert

    _om-runtime @ ARUNTIME-FREE
    _om-provider @ APROV-FREE
    _om-source @ APSOURCE-FREE
    _om-stack
    _om-fails @ 0= IF
        ." OPENAI MEGAPAD PASS " _om-checks @ .
    ELSE
        ." OPENAI MEGAPAD FAIL " _om-fails @ . ." / " _om-checks @ .
    THEN CR ;

_om-run
""",
        ready_markers=("OPENAI MEGAPAD PASS",),
        stable_markers=("OPENAI MEGAPAD PASS",),
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
CREATE _ns-id-stream 64 ALLOT
VARIABLE _ns-id-u
: _ns-ic,  ( c -- )
    _ns-id-stream _ns-id-u @ + C! 1 _ns-id-u +! ;
: _ns-i,  ( addr len -- )
    DUP >R _ns-id-stream _ns-id-u @ + SWAP CMOVE R> _ns-id-u +! ;

: _ns-stop-event  ( parser context -- status ) 2DROP 1 ;
: _ns-throw-event  ( parser context -- status ) 2DROP -77 THROW 0 ;

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

    _ct-null-schema CS-INIT
    CV-T-NULL _ct-null-schema CS-ALLOW!
    _ct-null-schema _ct-out 4096 CSJSON-INPUT-ENCODE
    DUP 0= _ct-assert DROP DUP _ct-out-u ! 0> _ct-assert
    _ct-out _ct-out-u @ JSON-VALID? _ct-assert

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
            "agent/providers/testing/scripted.f",
        ),
        resources=(),
        autoexec=r"""\ autoexec.f - provider-neutral agent runtime
ENTER-USERLAND
." [akashic] loading agent runtime" CR
REQUIRE agent/providers/offline.f
REQUIRE agent/providers/testing/scripted.f
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
    1 _at-conv @ ACONV-NTH AMSG-TEXT
    S" hello runtime" STR-STR-CONTAINS _at-assert
    _at-stack-clean

    S" request approval" _at-runtime @ ARUNTIME-SEND 0= _at-assert
    4 _at-pump
    _at-stack-clean
    _at-runtime @ ARUNTIME.STATUS @ ARUN-S-APPROVAL = _at-assert
    -1 _at-runtime @ ARUNTIME-RESOLVE 0= _at-assert
    2 _at-pump
    _at-stack-clean
    _at-runtime @ ARUNTIME.STATUS @ ARUN-S-IDLE = _at-assert

    _at-tool-setup
    _at-stack-clean
    CREG-NEW DUP 0= _at-assert DROP _at-registry !
    _at-component _at-registry @ CREG-TYPE+ 0= _at-assert
    _at-component CINST-NEW DUP 0= _at-assert DROP _at-instance !
    _at-instance @ _at-registry @ CREG-INST+ 0= _at-assert
    _at-registry @ _at-policy CBUS-NEW
    DUP 0= _at-assert DROP _at-bus !
    _at-registry @ _at-bus @ _at-instance @ ATOOLG-NEW
    DUP 0= _at-assert DROP _at-gateway !
    _at-gateway @ _at-runtime @ ARUNTIME-TOOL-GATEWAY!
    _at-gateway @ _at-provider @ APROV-BIND-TOOLS 0= _at-assert
    _at-stack-clean

    S" task gateway test" _at-runtime @ ARUNTIME-SEND 0= _at-assert
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
    _at-runtime @ ARUNTIME.STATUS @ ARUN-S-IDLE = _at-assert
    _at-tool-value @ 17 = _at-assert
    _at-runtime @ ARUNTIME.CONVERSATION @ DUP _at-conv !
    ACONV.COUNT @ 0> _at-assert
    _at-conv @ ACONV.COUNT @ 1- _at-conv @ ACONV-NTH AMSG-TEXT
    S" Daybook task captured." STR-STR-CONTAINS _at-assert

    S" cancel this" _at-runtime @ ARUNTIME-SEND 0= _at-assert
    _at-runtime @ ARUNTIME-CANCEL 0= _at-assert
    2 _at-pump
    _at-runtime @ ARUNTIME.STATUS @ ARUN-S-CANCELLED = _at-assert

    _at-runtime @ ARUNTIME-FREE
    _at-provider @ APROV-FREE
    _at-source @ APSOURCE-FREE
    _at-gateway @ ATOOLG-FREE
    _at-bus @ CBUS-FREE
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
    CPRINC-AGENT _ct-req @ CBR.PRINCIPAL !
    _ct-i2 @ _ct-req @ CBR-CALLER!
    _ct-i1 @ _ct-req @ CBR-TARGET!
    _ct-cap _ct-req @ CBR.CAP !
    77 _ct-req @ CBR.ARGS CV-INT!
    _ct-req @ _ct-bus @ CBUS-POST CBUS-S-OK = _ct-assert
    1 _ct-bus @ CBUS-PUMP 1 = _ct-assert
    _ct-i1 @ CINST-STATE _ct-cur ! _ct-value @ 77 = _ct-assert
    _ct-req @ CBR.STATUS @ CBUS-S-OK = _ct-assert
    _ct-i1 @ CINST.REVISION @ 1 = _ct-assert
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
            "agent/providers/testing/scripted.f",
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
REQUIRE agent/providers/testing/scripted.f
: _boot-agent-source  ( -- )
    SCRIPTED-SOURCE-NEW 0<> ABORT" scripted source allocation failed"
    DESK-AGENT-SOURCE! ;
_boot-agent-source

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
    ),
    "agent-ui": Profile(
        roots=(
            "tui/applets/agent/agent.f",
            "agent/providers/testing/scripted.f",
        ),
        resources=("tui/applets/agent/agent.uidl",),
        autoexec=r"""\ autoexec.f - standalone Agent applet profile
ENTER-USERLAND
." [akashic] loading Agent applet" CR
REQUIRE agent/providers/testing/scripted.f
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
            "agent/providers/openai/megapad.f",
        ),
        resources=("tui/applets/agent/agent.uidl",),
        autoexec=r"""\ autoexec.f - native provider credential UI
ENTER-USERLAND
." [akashic] loading Agent credential UI" CR
REQUIRE agent/providers/openai/megapad.f
REQUIRE tui/applets/agent/agent.f
: _boot-openai-source  ( -- )
    OPENAI-MEGAPAD-SOURCE-NEW
    0<> ABORT" OpenAI MegaPad source allocation failed"
    AGENT-SOURCE! ;
_boot-openai-source
." [akashic] starting Agent credential UI" CR
AGENT-RUN
." [akashic] Agent credential UI exited" CR
""",
        ready_markers=("Agent", "Connection", "Credential required"),
        stable_markers=("Agent", "Connection", "Credential required"),
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

# Same production-shaped image as desktop, with a focused agent/interop
# journey instead of the full applet regression tour.
PROFILES["desktop-agent"] = PROFILES["desktop"]
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


def build_image(profile_name: str, output: Path | None = None) -> Path:
    profile = PROFILES[profile_name]
    modules = dependency_closure(profile.roots)
    resources = set(profile.resources)
    paths = set(modules) | resources
    directories = _directories(paths)
    _validate_module_ids(modules)
    _validate_image_paths(paths, directories)

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
        if not source.is_file():
            raise FileNotFoundError(f"Missing Akashic resource: {path}")
        disk_path = PurePosixPath(path)
        file_type = FTYPE_FORTH if source.suffix == ".f" else FTYPE_TEXT
        parent = "/" + str(disk_path.parent)
        fs.inject_file(
            disk_path.name,
            source.read_bytes(),
            ftype=file_type,
            path=parent,
        )

    fs.inject_file("large.txt", LARGE_SAMPLE, ftype=FTYPE_TEXT)

    # Leave two isolated one-sector holes in the generated test image.
    # Guest-created smoke.txt uses the first; the large Save As copy uses
    # the second and must grow through MP64FS's secondary extent.
    fs.inject_file(".growth-hole-1", bytes(512), flags=FLAG_SYSTEM)

    fs.inject_file(
        "autoexec.f",
        profile.autoexec.encode("utf-8"),
        ftype=FTYPE_FORTH,
    )
    fs.inject_file(".growth-hole-2", bytes(512), flags=FLAG_SYSTEM)

    for name in sorted(SAMPLE_FILES.keys() - {"large.txt"}):
        fs.inject_file(name, SAMPLE_FILES[name], ftype=FTYPE_TEXT)

    fs.delete_file(".growth-hole-1")
    fs.delete_file(".growth-hole-2")
    fs.save(target)

    info = fs.info()
    print(
        f"Built {profile_name} image: {target}\n"
        f"  {len(modules)} modules, {len(resources)} resources, "
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
) -> bool:
    profile = PROFILES[profile_name]
    started = time.perf_counter()
    total_steps = 0
    stop_reason = "budget"

    with MachineSession.from_bios(
        MEGAPAD_ROOT / "bios.asm",
        storage_image=image_path,
        cols=cols,
        rows=rows,
        batch_steps=500_000,
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

        if initial_ready and profile_name == "desktop-agent":
            run_desk_agent_journey()

        if initial_ready and profile_name in ("desktop", "pad"):
            if profile_name == "desktop":
                session.send_key("alt+1")
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

        if initial_ready and profile_name != "interop":
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
                        wait_screen(
                            "Ln 2",
                            "Pad did not move to the matched search line",
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

        if initial_ready and profile_name in ("desktop", "fexplorer"):
            if profile_name == "desktop":
                session.send_key("alt+2")
            session.send_key("ctrl+g")
            if wait_screen(
                "Go to:", "File Explorer's Go to Path prompt did not open"
            ):
                session.send_text("example.f")
                session.send_key("enter")
                wait_screen("SQUARE", "File Explorer could not preview /example.f")

            if profile_name == "desktop":
                session.send_key("ctrl+o")
                if wait_screen(
                    "[1:Akashic Pa*]",
                    "resource.open did not route File Explorer's selection to Pad",
                ):
                    wait_screen(
                        "/example.f",
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
            if profile_name == "desktop":
                run_desk_agent_journey()

                session.send_key("alt+3")
                wait_screen(
                    "[3:Daybook*]",
                    "Desk could not focus Daybook with Alt+3",
                )
                session.send_key("alt+4")
                wait_screen(
                    "[4:Grid*]",
                    "Desk could not focus Grid with Alt+4",
                )
                session.send_key("alt+2")
                wait_screen(
                    "[2:File Explo*]",
                    "Desk could not return focus to File Explorer",
                )
                screen = session.snapshot()
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
):
    os.execv(
        sys.executable,
        [
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
        ],
    )


def _parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)

    for name in ("build", "smoke", "serve"):
        command = commands.add_parser(name)
        command.add_argument(
            "--profile", choices=tuple(PROFILES), default="desktop"
        )
        command.add_argument("--output", type=Path)
        if name in ("smoke", "serve"):
            command.add_argument("--cols", type=int, default=100)
            command.add_argument("--rows", type=int, default=32)
        if name == "smoke":
            command.add_argument("--max-steps", type=int, default=3_000_000_000)
            command.add_argument("--timeout", type=float, default=75.0)
        if name == "serve":
            command.add_argument("--socket", default="/tmp/akashic-tui.sock")

    return parser


def main() -> int:
    args = _parser().parse_args()
    image_path = build_image(args.profile, args.output)
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
        ) else 1
    serve(
        args.profile,
        image_path,
        socket_path=args.socket,
        cols=args.cols,
        rows=args.rows,
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
