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
MODULE_KEY_BYTES = 24


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
SCRIPTED-PROVIDER-USE

VARIABLE _at-fails
VARIABLE _at-check
: _at-assert  ( flag -- )
    1 _at-check +!
    0= IF 1 _at-fails +! ." ASSERT " _at-check @ . CR THEN ;

VARIABLE _at-provider
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
    APROV-NEW DUP 0= _at-assert DROP _at-provider !
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
SCRIPTED-PROVIDER-USE

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
SCRIPTED-PROVIDER-USE
." [akashic] starting Agent applet" CR
AGENT-RUN
." [akashic] Agent applet exited" CR
""",
        ready_markers=("Agent", "Run", "Review", "Ready"),
        stable_markers=("Agent", "Run", "Review", "Ready"),
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
            )
            total_steps += report.steps
            screen = session.snapshot()
            screen_text = screen.text()
            if all(marker in screen_text for marker in profile.ready_markers):
                break
            if report.reason in ("halted", "idle", "stalled"):
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
            f"screen={screen.cols}x{screen.rows}; raw={len(session.raw_output):,} bytes"
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
