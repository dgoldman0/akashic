#!/usr/bin/env python3
"""Sandbox digests against Python's SHA3-256.

Each identity domain hashes its ASCII name, one zero byte and the exact
source bytes; RAW hashes the bytes alone.  The generated Forth fixture
hashes messages around the SHA3-256 block size in every domain, the
pure-computation profile fixture against its documented golden digests,
and checks refusals, aliasing and that the workspace is wiped.
"""

from __future__ import annotations

import hashlib
import sys
from pathlib import Path


LOCAL_TESTING = Path(__file__).resolve().parent
REPO_ROOT = LOCAL_TESTING.parent
sys.path.insert(0, str(LOCAL_TESTING))

from akashic_tui import Profile, PROFILES, build_image, smoke  # noqa: E402


DOMAINS = {
    "RAW": None,
    "PROFILE": "akashic.sandbox.profile",
    "ARTIFACT": "akashic.sandbox.artifact",
    "SCHEMA": "akashic.sandbox.schema",
    "DECLARATION": "akashic.sandbox.declaration",
    "VALUE-INPUT": "akashic.sandbox.value.input",
    "VALUE-OUTPUT": "akashic.sandbox.value.output",
}

PROFILE_FIXTURE = REPO_ROOT / "docs" / "sandbox" / "fixtures" / "pure-compute.profile"
# profile-format.md publishes these for the pure-computation descriptor.
PROFILE_RAW = "5a8b87d56a697778d894ad344790b0de6008c3c4c46a94a59ccfade85f957889"
PROFILE_DIGEST = "6e35c668e130473b9f2ef941da2c84941e6460f2b64bcce56526e31cd509e357"

# SHA3-256 absorbs 136 bytes a block, so these straddle the padding edges.
MESSAGES = [
    b"",
    b"abc",
    bytes(range(135)),
    bytes(range(136)),
    bytes(range(137)),
    bytes(i % 251 for i in range(300)),
]


def digest(domain: str | None, data: bytes) -> bytes:
    prefix = b"" if domain is None else domain.encode("ascii") + b"\x00"
    return hashlib.sha3_256(prefix + data).digest()


def test_the_reference_reproduces_the_published_digests() -> None:
    assert hashlib.sha3_256(b"").hexdigest() == (
        "a7ffc6f8bf1ed76651c14756a061d662f580ff4de43b49fa82d80a4b80f8434a"
    )
    fixture = PROFILE_FIXTURE.read_bytes()
    assert len(fixture) == 8416
    assert digest(None, fixture).hex() == PROFILE_RAW
    assert digest("akashic.sandbox.profile", fixture).hex() == PROFILE_DIGEST


def hex_load(data: bytes) -> list[str]:
    text = data.hex()
    lines = ["_bx-begin"]
    lines += [f'S" {text[i:i + 96]}" _bx-add' for i in range(0, len(text), 96)]
    return lines + ["_bx-end"]


PRELUDE = r"""\ Generated: sandbox digests against Python's SHA3-256.
PROVIDED sbox-digest-tests

VARIABLE _sd-fails
VARIABLE _sd-checks
VARIABLE _sd-case
VARIABLE _sd-depth
VARIABLE _sd-xt
VARIABLE _sd-ea

CREATE _bx-pool 32768 ALLOT
VARIABLE _bx-top
VARIABLE _bx-start
CREATE _sd-work-raw SBOX-DIGEST-WORKSPACE-SIZE 15 + ALLOT
CREATE _sd-out-raw 64 7 + ALLOT

: _sd-work  ( -- a ) _sd-work-raw 7 + -8 AND ;
: _sd-out  ( -- a ) _sd-out-raw 7 + -8 AND ;

: _sd-assert  ( flag -- )
    1 _sd-checks +!
    0= IF
        1 _sd-fails +!
        ." SDIG ASSERT case " _sd-case @ . ." check " _sd-checks @ . CR
    THEN ;

: _bx-reset  ( -- ) 0 _bx-top ! ;
: _bx-begin  ( -- ) _bx-top @ _bx-start ! ;
: _hexval  ( c -- n )
    DUP [CHAR] a >= IF [CHAR] a - 10 + ELSE [CHAR] 0 - THEN ;
: _bx-add  ( c-addr u -- )
    2 / 0 ?DO
        DUP I 2 * + C@ _hexval 4 LSHIFT
        OVER I 2 * + 1+ C@ _hexval OR
        _bx-pool _bx-top @ + C!
        1 _bx-top +!
    LOOP DROP ;
: _bx-end  ( -- addr n )
    _bx-pool _bx-start @ + _bx-top @ _bx-start @ - ;

\ The byte stays on the data stack: inside DO, R@ is the loop index.
: _sd-filled?  ( a u byte -- flag )
    SWAP 0 ?DO OVER I + C@ OVER <> IF 2DROP 0 UNLOOP EXIT THEN LOOP
    2DROP -1 ;

\ Hashing DATA with XT publishes EXPECTED and leaves the workspace wiped.
: _sd-ok  ( data data-u xt expected expected-u -- )
    32 = _sd-assert _sd-ea ! _sd-xt !
    _sd-work SBOX-DIGEST-WORKSPACE-SIZE 0xA5 FILL
    _sd-out 32 0x5A FILL
    _sd-out _sd-work _sd-xt @ EXECUTE SBOX-DIGEST-S-OK = _sd-assert
    _sd-out 32 _sd-ea @ 32 COMPARE 0= _sd-assert
    _sd-work SBOX-DIGEST-WORKSPACE-SIZE 0 _sd-filled? _sd-assert ;

\ A refusal leaves both the workspace and the destination as they were.
: _sd-refused  ( source source-u digest workspace xt status -- )
    >R >R
    _sd-work SBOX-DIGEST-WORKSPACE-SIZE 0xA5 FILL
    _sd-out 32 0x5A FILL
    R> EXECUTE R> = _sd-assert
    _sd-work SBOX-DIGEST-WORKSPACE-SIZE 0xA5 _sd-filled? _sd-assert
    _sd-out 32 0x5A _sd-filled? _sd-assert ;

: _sd-refusals  ( -- )
    0 _sd-case !
    S" abc" _sd-out 0 ['] SBOX-DIGEST-RAW SBOX-DIGEST-S-INVALID _sd-refused
    S" abc" _sd-out _sd-work 1+ ['] SBOX-DIGEST-RAW
        SBOX-DIGEST-S-INVALID _sd-refused
    S" abc" 0 _sd-work ['] SBOX-DIGEST-PROFILE
        SBOX-DIGEST-S-INVALID _sd-refused
    0 5 _sd-out _sd-work ['] SBOX-DIGEST-SCHEMA
        SBOX-DIGEST-S-INVALID _sd-refused
    _sd-out -1 _sd-out 32 + _sd-work ['] SBOX-DIGEST-RAW
        SBOX-DIGEST-S-INVALID _sd-refused
    \ The destination inside the workspace, the source over the
    \ destination, and the source over the workspace.
    S" abc" _sd-work 8 + _sd-work ['] SBOX-DIGEST-ARTIFACT
        SBOX-DIGEST-S-ALIAS _sd-refused
    _sd-out 8 + 4 _sd-out _sd-work ['] SBOX-DIGEST-DECLARATION
        SBOX-DIGEST-S-ALIAS _sd-refused
    _sd-work 16 _sd-out _sd-work ['] SBOX-DIGEST-VALUE-INPUT
        SBOX-DIGEST-S-ALIAS _sd-refused
    \ The workspace can be wiped on its own.
    _sd-work SBOX-DIGEST-WORKSPACE-SIZE 0xA5 FILL
    _sd-work SBOX-DIGEST-WORKSPACE-CLEAR SBOX-DIGEST-S-OK = _sd-assert
    _sd-work SBOX-DIGEST-WORKSPACE-SIZE 0 _sd-filled? _sd-assert
    _sd-work 1+ SBOX-DIGEST-WORKSPACE-CLEAR
        SBOX-DIGEST-S-INVALID = _sd-assert ;
"""

EPILOGUE = r"""
: _sd-finish  ( -- )
    _sd-refusals
    0 _sd-case !
    DEPTH _sd-depth @ = _sd-assert
    _sd-fails @ IF
        ." SDIG FAIL " _sd-fails @ . ." / " _sd-checks @ . CR
    ELSE
        ." SDIG PASS " _sd-checks @ . CR
    THEN ;

_sd-finish
"""


def cases() -> list[tuple[bytes, str, bytes]]:
    """(data, digest word, expected) for every domain and message."""
    out = []
    for name, domain in DOMAINS.items():
        for message in MESSAGES:
            out.append((message, f"SBOX-DIGEST-{name}", digest(domain, message)))
    fixture = PROFILE_FIXTURE.read_bytes()
    out.append((fixture, "SBOX-DIGEST-RAW", bytes.fromhex(PROFILE_RAW)))
    out.append((fixture, "SBOX-DIGEST-PROFILE", bytes.fromhex(PROFILE_DIGEST)))
    return out


def fixture_bytes() -> bytes:
    lines = [PRELUDE, "0 _sd-fails ! 0 _sd-checks ! DEPTH _sd-depth !"]
    for number, (data, word, expected) in enumerate(cases(), start=1):
        lines.append("MARKER _sd-mark")
        lines.append(f": _sd-case-{number}  ( -- )")
        lines.append(f"    {number} _sd-case ! _bx-reset")
        lines.extend("    " + line for line in hex_load(data))
        lines.append(f"    ['] {word}")
        lines.extend("    " + line for line in hex_load(expected))
        lines.append("    _sd-ok")
        lines.append(";")
        lines.append(f"_sd-case-{number}")
        lines.append("_sd-mark")
    lines.append(EPILOGUE)
    return ("\n".join(lines) + "\n").encode()


PROFILE_NAME = "sandbox-digest"


def test_digests_match_the_reference(tmp_path: Path) -> None:
    PROFILES[PROFILE_NAME] = Profile(
        roots=("sandbox/digest.f",),
        resources=(),
        autoexec=r"""\ autoexec.f - sandbox digests
ENTER-USERLAND
." [akashic] loading sandbox digests" CR TX-FLUSH
REQUIRE sandbox/digest.f
REQUIRE local_testing/sbox-digest-test.f
""",
        ready_markers=("SDIG PASS",),
        stable_markers=("SDIG PASS",),
        failure_markers=(
            "SDIG FAIL",
            "SDIG ASSERT",
            "? (not found)",
            "Branch offset overflow",
            "dictionary full",
            "exception",
        ),
        linked=True,
        include_large_sample=False,
        initial_files=(("local_testing/sbox-digest-test.f", fixture_bytes()),),
    )
    image = build_image(PROFILE_NAME, tmp_path / "sandbox-digest.img")
    assert smoke(
        PROFILE_NAME,
        image,
        cols=100,
        rows=30,
        max_steps=800_000_000,
        timeout=120.0,
    )
