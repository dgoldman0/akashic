#!/usr/bin/env python3
"""Qualify the stateless restricted AT URI boundary."""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path


LOCAL_TESTING = Path(__file__).resolve().parent
ROOT = LOCAL_TESTING.parent
SOURCE = ROOT / "akashic" / "atproto" / "aturi.f"

PROFILE = "atproto-aturi"
IMAGE = Path("/tmp/akashic-atproto-aturi.img")
PASS_MARKER = "ATPROTO ATURI PASS"

FIXTURE = r"""
\ Restricted normalized AT URI validation, views, and construction.
PROVIDED atproto-aturi-test

VARIABLE _AUT-FAILS
VARIABLE _AUT-CHECKS
VARIABLE _AUT-DEPTH
VARIABLE _AUT-WRITTEN

CREATE _AUT-DEST 4096 ALLOT
CREATE _AUT-SNAPSHOT 4096 ALLOT
CREATE _AUT-WRITER CBW-SIZE ALLOT
CREATE _AUT-LONG AT-RKEY-LENGTH-MAX ALLOT
CREATE _AUT-OVERSIZE ATURI-LENGTH-MAX 1+ ALLOT
CREATE _AUT-ARENA 128 ALLOT
CREATE _AUT-ALIAS 64 ALLOT

: _AUT-ASSERT  ( flag -- )
    1 _AUT-CHECKS +!
    0= IF
        1 _AUT-FAILS +!
        ." ATPROTO ATURI ASSERT " _AUT-CHECKS @ . CR
    THEN ;

: _AUT-STATUS  ( actual expected -- )
    = _AUT-ASSERT ;

: _AUT-STACK  ( -- )
    DEPTH DUP _AUT-DEPTH @ <> IF
        ." ATPROTO ATURI STACK "
        _AUT-DEPTH @ . ."  -> " DUP . CR .S CR
    THEN
    _AUT-DEPTH @ = _AUT-ASSERT ;

: _AUT-BYTES?  ( address length byte -- flag )
    >R
    BEGIN
        DUP
    WHILE
        OVER C@ R@ <> IF
            2DROP R> DROP 0 EXIT
        THEN
        1- SWAP 1+ SWAP
    REPEAT
    2DROP R> DROP -1 ;

: _AUT-VALIDATION  ( -- )
    S" at://did:plc:abcdefghijklmnopqrstuvwx"
        ATURI-VALID? _AUT-ASSERT
    S" at://alice.test" ATURI-VALID? _AUT-ASSERT
    S" at://alice.test/app.bsky.feed.post"
        ATURI-VALID? _AUT-ASSERT
    S" at://alice.test/app.bsky.feed.Post/Key_1"
        ATURI-VALID? _AUT-ASSERT
    S" at://did:future:value/com.example.Record/r:Key"
        ATURI-VALID? _AUT-ASSERT
    S" at://did:web:example.com%2Fusers%2Falice"
        ATURI-VALID? _AUT-ASSERT

    S" AT://alice.test" ATURI-VALIDATE
        ATURI-S-SYNTAX _AUT-STATUS
    S" at://Alice.Test" ATURI-VALIDATE
        ATURI-S-NORMALIZATION _AUT-STATUS
    S" at://alice.test/App.bsky.feed.post/key" ATURI-VALIDATE
        ATURI-S-NORMALIZATION _AUT-STATUS
    S" at://did:web:example.com%2fusers" ATURI-VALIDATE
        ATURI-S-NORMALIZATION _AUT-STATUS
    S" at://did:web:example.com%41" ATURI-VALIDATE
        ATURI-S-NORMALIZATION _AUT-STATUS
    S" at://did:web:example.com%252Fusers" ATURI-VALIDATE
        ATURI-S-NORMALIZATION _AUT-STATUS

    S" at://" ATURI-VALIDATE ATURI-S-AUTHORITY _AUT-STATUS
    S" at://computer" ATURI-VALIDATE
        ATURI-S-AUTHORITY _AUT-STATUS
    S" at://alice.test/" ATURI-VALIDATE
        ATURI-S-SYNTAX _AUT-STATUS
    S" at://alice.test//key" ATURI-VALIDATE
        ATURI-S-SYNTAX _AUT-STATUS
    S" at://alice.test/app.bsky.feed.post/" ATURI-VALIDATE
        ATURI-S-SYNTAX _AUT-STATUS
    S" at://alice.test/not-an-nsid/key" ATURI-VALIDATE
        ATURI-S-COLLECTION _AUT-STATUS
    S" at://alice.test/app.bsky.feed.post/bad/key" ATURI-VALIDATE
        ATURI-S-RKEY _AUT-STATUS
    S" at://alice.test?query=true" ATURI-VALID? 0= _AUT-ASSERT
    S" at://alice.test#fragment" ATURI-VALID? 0= _AUT-ASSERT
    _AUT-OVERSIZE ATURI-LENGTH-MAX 1+ [CHAR] a FILL
    _AUT-OVERSIZE ATURI-LENGTH-MAX 1+ ATURI-VALIDATE
        ATURI-S-CAPACITY _AUT-STATUS
    _AUT-OVERSIZE ATURI-LENGTH-MAX ATURI-VALIDATE
        ATURI-S-SYNTAX _AUT-STATUS
    0 0 ATURI-VALIDATE ATURI-S-SYNTAX _AUT-STATUS
    0 1 ATURI-VALIDATE ATURI-S-INVALID _AUT-STATUS

    ATURI-S-OK ATURI-STATUS-VALID? _AUT-ASSERT
    ATURI-S-INTERNAL ATURI-STATUS-VALID? _AUT-ASSERT
    -1 ATURI-STATUS-VALID? 0= _AUT-ASSERT
    ATURI-S-INTERNAL 1+ ATURI-STATUS-VALID? 0= _AUT-ASSERT
    _AUT-STACK ;

: _AUT-SPLITS  ( -- )
    S" at://did:plc:abcdefghijklmnopqrstuvwx/app.bsky.feed.post/3key"
    ATURI-SPLIT
    DUP ATURI-S-OK _AUT-STATUS DROP
    2DUP S" 3key" COMPARE 0= _AUT-ASSERT 2DROP
    2DUP S" app.bsky.feed.post" COMPARE 0= _AUT-ASSERT 2DROP
    2DUP S" did:plc:abcdefghijklmnopqrstuvwx"
        COMPARE 0= _AUT-ASSERT 2DROP

    S" at://alice.test/app.bsky.feed.Post" ATURI-SPLIT
    DUP ATURI-S-OK _AUT-STATUS DROP
    OR 0= _AUT-ASSERT
    2DUP S" app.bsky.feed.Post" COMPARE 0= _AUT-ASSERT 2DROP
    2DUP S" alice.test" COMPARE 0= _AUT-ASSERT 2DROP

    S" at://alice.test" ATURI-SPLIT
    DUP ATURI-S-OK _AUT-STATUS DROP
    OR 0= _AUT-ASSERT
    OR 0= _AUT-ASSERT
    2DUP S" alice.test" COMPARE 0= _AUT-ASSERT 2DROP

    S" at://Alice.Test" ATURI-SPLIT
    DUP ATURI-S-NORMALIZATION _AUT-STATUS DROP
    OR OR OR OR OR 0= _AUT-ASSERT
    _AUT-STACK ;

: _AUT-BUILD-EXACT  ( -- )
    _AUT-DEST 4096 0xA5 FILL
    _AUT-WRITER CBW-SIZE 0x5A FILL
    S" did:plc:abcdefghijklmnopqrstuvwx"
    S" app.bsky.feed.post" S" 3key"
    _AUT-DEST 4096 _AUT-WRITER ATURI-BUILD
    DUP ATURI-S-OK _AUT-STATUS DROP
    DUP _AUT-WRITTEN !
    S" at://did:plc:abcdefghijklmnopqrstuvwx/app.bsky.feed.post/3key"
        NIP = _AUT-ASSERT
    _AUT-DEST _AUT-WRITTEN @
    S" at://did:plc:abcdefghijklmnopqrstuvwx/app.bsky.feed.post/3key"
        COMPARE 0= _AUT-ASSERT
    _AUT-DEST _AUT-WRITTEN @ + C@ 0xA5 = _AUT-ASSERT
    _AUT-WRITER CBW-RESULT
    DUP CBW-S-OK _AUT-STATUS DROP
    2DUP _AUT-DEST _AUT-WRITTEN @ COMPARE 0= _AUT-ASSERT
    2DROP
    _AUT-DEST _AUT-WRITTEN @ ATURI-VALID? _AUT-ASSERT

    \ Exact capacity succeeds without touching the adjacent byte.
    _AUT-DEST 4096 0xA5 FILL
    S" did:plc:abcdefghijklmnopqrstuvwx"
    S" app.bsky.feed.post" S" 3key"
    _AUT-DEST
    S" at://did:plc:abcdefghijklmnopqrstuvwx/app.bsky.feed.post/3key"
        NIP
    _AUT-WRITER ATURI-BUILD
    DUP ATURI-S-OK _AUT-STATUS DROP
    DUP _AUT-WRITTEN !
    S" at://did:plc:abcdefghijklmnopqrstuvwx/app.bsky.feed.post/3key"
        NIP = _AUT-ASSERT
    _AUT-DEST _AUT-WRITTEN @ + C@ 0xA5 = _AUT-ASSERT

    \ Collection-only construction is a first-class restricted shape.
    _AUT-DEST 4096 0xA5 FILL
    S" alice.test" S" app.bsky.feed.Post" 0 0
    _AUT-DEST 4096 _AUT-WRITER ATURI-BUILD
    DUP ATURI-S-OK _AUT-STATUS DROP
    DUP _AUT-WRITTEN !
    _AUT-DEST _AUT-WRITTEN @
    S" at://alice.test/app.bsky.feed.Post"
        COMPARE 0= _AUT-ASSERT
    _AUT-DEST _AUT-WRITTEN @ ATURI-VALID? _AUT-ASSERT

    _AUT-DEST 4096 0xA5 FILL
    _AUT-WRITER CBW-SIZE 0x5A FILL
    S" did:plc:abcdefghijklmnopqrstuvwx"
    S" app.bsky.feed.post" S" 3key"
    _AUT-DEST
    S" at://did:plc:abcdefghijklmnopqrstuvwx/app.bsky.feed.post/3key"
        NIP 1-
    _AUT-WRITER ATURI-BUILD
    DUP ATURI-S-CAPACITY _AUT-STATUS DROP
    0= _AUT-ASSERT
    _AUT-DEST 4096 0xA5 _AUT-BYTES? _AUT-ASSERT
    _AUT-WRITER CBW-SIZE 0x5A _AUT-BYTES? _AUT-ASSERT

    _AUT-DEST 4096 0xA5 FILL
    _AUT-WRITER CBW-SIZE 0x5A FILL
    S" Alice.Test" 0 0 0 0
    _AUT-DEST 4096 _AUT-WRITER ATURI-BUILD
    DUP ATURI-S-NORMALIZATION _AUT-STATUS DROP
    0= _AUT-ASSERT
    _AUT-DEST 4096 0xA5 _AUT-BYTES? _AUT-ASSERT
    _AUT-WRITER CBW-SIZE 0x5A _AUT-BYTES? _AUT-ASSERT
    _AUT-STACK ;

: _AUT-BUILD-LARGE  ( -- )
    _AUT-LONG AT-RKEY-LENGTH-MAX [CHAR] a FILL
    _AUT-DEST 4096 0xA5 FILL
    S" did:plc:abc" S" app.bsky.feed.post"
    _AUT-LONG AT-RKEY-LENGTH-MAX
    _AUT-DEST 4096 _AUT-WRITER ATURI-BUILD
    DUP ATURI-S-OK _AUT-STATUS DROP
    DUP _AUT-WRITTEN ! 548 = _AUT-ASSERT
    _AUT-DEST _AUT-WRITTEN @ ATURI-VALID? _AUT-ASSERT
    _AUT-DEST _AUT-WRITTEN @ ATURI-SPLIT
    DUP ATURI-S-OK _AUT-STATUS DROP
    DUP AT-RKEY-LENGTH-MAX = _AUT-ASSERT
    2DROP 2DROP 2DROP
    _AUT-STACK ;

: _AUT-BUILD-ALIASES  ( -- )
    _AUT-DEST 256 0xA5 FILL
    S" alice.test" _AUT-DEST 2 + SWAP MOVE
    _AUT-DEST _AUT-SNAPSHOT 256 CMOVE
    _AUT-WRITER CBW-SIZE 0x5A FILL
    _AUT-DEST 2 + 10 0 0 0 0
    _AUT-DEST 256 _AUT-WRITER ATURI-BUILD
    DUP ATURI-S-ALIAS _AUT-STATUS DROP
    0= _AUT-ASSERT
    _AUT-DEST 256 _AUT-SNAPSHOT 256 COMPARE 0= _AUT-ASSERT
    _AUT-WRITER CBW-SIZE 0x5A _AUT-BYTES? _AUT-ASSERT

    \ The same alias rule applies to later component pairs.
    _AUT-DEST 256 0xA5 FILL
    S" app.bsky.feed.post" _AUT-DEST 2 + SWAP MOVE
    _AUT-DEST _AUT-SNAPSHOT 256 CMOVE
    S" alice.test" _AUT-DEST 2 + 18 0 0
    _AUT-DEST 256 _AUT-WRITER ATURI-BUILD
    DUP ATURI-S-ALIAS _AUT-STATUS DROP
    0= _AUT-ASSERT
    _AUT-DEST 256 _AUT-SNAPSHOT 256 COMPARE 0= _AUT-ASSERT

    _AUT-DEST 256 0xA5 FILL
    S" key" _AUT-DEST 2 + SWAP MOVE
    _AUT-DEST _AUT-SNAPSHOT 256 CMOVE
    S" alice.test" S" app.bsky.feed.post" _AUT-DEST 2 + 3
    _AUT-DEST 256 _AUT-WRITER ATURI-BUILD
    DUP ATURI-S-ALIAS _AUT-STATUS DROP
    0= _AUT-ASSERT
    _AUT-DEST 256 _AUT-SNAPSHOT 256 COMPARE 0= _AUT-ASSERT

    _AUT-ARENA 128 0xA5 FILL
    S" alice.test" _AUT-ARENA 15 + SWAP MOVE
    _AUT-ARENA 15 + 10 0 0 0 0
    _AUT-ARENA 15 _AUT-WRITER ATURI-BUILD
    DUP ATURI-S-OK _AUT-STATUS DROP
    15 = _AUT-ASSERT
    _AUT-ARENA 15 S" at://alice.test" COMPARE 0= _AUT-ASSERT

    _AUT-ALIAS 64 0xA5 FILL
    S" alice.test" _AUT-ALIAS SWAP MOVE
    _AUT-DEST 64 0xA5 FILL
    _AUT-ALIAS 10 0 0 0 0
    _AUT-DEST 64 _AUT-ALIAS ATURI-BUILD
    DUP ATURI-S-ALIAS _AUT-STATUS DROP
    0= _AUT-ASSERT
    _AUT-DEST 64 0xA5 _AUT-BYTES? _AUT-ASSERT

    _AUT-DEST 64 0xA5 FILL
    S" alice.test" 0 0 0 0
    _AUT-DEST 64 _AUT-DEST ATURI-BUILD
    DUP ATURI-S-ALIAS _AUT-STATUS DROP
    0= _AUT-ASSERT
    _AUT-DEST 64 0xA5 _AUT-BYTES? _AUT-ASSERT
    _AUT-STACK ;

: _AUT-RUN  ( -- )
    0 _AUT-FAILS !
    0 _AUT-CHECKS !
    DEPTH _AUT-DEPTH !
    _AUT-VALIDATION
    _AUT-SPLITS
    _AUT-BUILD-EXACT
    _AUT-BUILD-LARGE
    _AUT-BUILD-ALIASES
    _AUT-FAILS @ 0= IF
        ." ATPROTO ATURI PASS " _AUT-CHECKS @ . CR
    ELSE
        ." ATPROTO ATURI FAIL " _AUT-FAILS @ .
        ."  / " _AUT-CHECKS @ . CR
    THEN ;
"""


def _word_body(source: str, name: str) -> str:
    match = re.search(
        rf"(?ms)^:[ \t]+{re.escape(name)}(?=[ \t\r\n(])"
        rf"(?P<body>.*?)[ \t]+;",
        source,
    )
    assert match is not None, f"missing definition for {name}"
    return match.group("body")


def _assert_physical_comments(path: Path, source: str) -> None:
    for line_number, line in enumerate(source.splitlines(), start=1):
        forth_code = line.split("\\", 1)[0]
        if "(" in forth_code:
            assert ")" in forth_code.split("(", 1)[1], (
                "KDOS parenthesized comments must close on their "
                f"physical line: {path}:{line_number}"
            )


def test_atproto_aturi_source_contract() -> None:
    source = SOURCE.read_text(encoding="utf-8")
    executable = "\n".join(
        line
        for line in source.splitlines()
        if not line.lstrip().startswith("\\")
    )

    assert re.findall(
        r"(?mi)^[ \t]*REQUIRE[ \t]+(\S+)", source
    ) == [
        "../utils/memory-span.f",
        "../utils/caller-span.f",
        "../utils/buffer-writer.f",
        "did.f",
        "handle.f",
        "nsid.f",
        "record-key.f",
    ]
    assert "PROVIDED akashic-atproto-aturi" in source
    assert not re.search(
        r"(?mi)^[ \t]*(?:CREATE|VARIABLE|VALUE|DEFER|GUARD)\b",
        executable,
    ), "restricted AT URI utility owns mutable module state"

    for word in (
        "8192 CONSTANT ATURI-LENGTH-MAX",
        "ATURI-S-OK",
        "ATURI-S-INVALID",
        "ATURI-S-CAPACITY",
        "ATURI-S-SYNTAX",
        "ATURI-S-AUTHORITY",
        "ATURI-S-COLLECTION",
        "ATURI-S-RKEY",
        "ATURI-S-NORMALIZATION",
        "ATURI-S-ALIAS",
        "ATURI-S-RANGE",
        "ATURI-S-PROTECTED",
        "ATURI-S-PLATFORM",
        "ATURI-S-INTERNAL",
        "ATURI-STATUS-VALID?",
        "ATURI-VALIDATE",
        "ATURI-VALID?",
        "ATURI-SPLIT",
        "ATURI-BUILD",
    ):
        assert word in source

    assert not re.search(r"(?m)^:[ \t]+ATURI-PARSE\b", executable)
    assert not re.search(
        r"(?m)^[ \t]*(?:CREATE|VARIABLE)[ \t]+"
        r"ATURI-(?:AUTHORITY|AUTH-LEN|COLLECTION|COLL-LEN|RKEY|RKEY-LEN)\b",
        executable,
    )
    assert "../net/uri.f" not in source
    assert "../utils/string.f" not in source
    build = _word_body(source, "ATURI-BUILD")
    assert "MIN" not in build
    assert "CBW-INIT" in build
    assert "_ATURI-MEASURE" in build
    assert "MSPAN-OVERLAP?" in build
    assert build.index("_ATURI-MEASURE") < build.index("CBW-INIT")
    assert "DID-VALIDATE" in source
    assert "AT-HANDLE-NORMALIZED?" in source
    assert "NSID-CHECK" in source
    assert "NSID-SPLIT" in source
    assert "AT-RKEY-VALIDATE" in source
    validate = _word_body(source, "ATURI-VALIDATE")
    assert validate.index("ATURI-LENGTH-MAX U>") < validate.index(
        "_ATURI-PREFIX?"
    )
    assert validate.index("ATURI-LENGTH-MAX U>") < validate.index(
        "_ATURI-SPLIT-RAW"
    )
    assert "[CHAR] ?" not in source
    assert "[CHAR] #" not in source
    _assert_physical_comments(SOURCE, source)
    _assert_physical_comments(Path("atproto-aturi-test"), FIXTURE)


def _run_vertical(timeout: float) -> int:
    sys.path.insert(0, str(LOCAL_TESTING))
    import akashic_tui as harness

    autoexec = r"""\ autoexec.f - restricted AT URI qualification
ENTER-USERLAND
REQUIRE atproto/aturi.f
REQUIRE local_testing/aturi-test.f
_AUT-RUN
TX-FLUSH
"""
    harness.PROFILES[PROFILE] = harness.Profile(
        roots=("atproto/aturi.f",),
        resources=(),
        autoexec=autoexec,
        ready_markers=(PASS_MARKER,),
        stable_markers=(PASS_MARKER,),
        failure_markers=(
            "ATPROTO ATURI FAIL",
            "ATPROTO ATURI ASSERT",
            "ATPROTO ATURI STACK",
            "DRIVER THROW",
            "dictionary full",
            "exception",
            "Module not found",
            "Path component not found",
            "? (not found)",
            "(not found)",
        ),
        initial_files=(
            (
                "local_testing/aturi-test.f",
                harness._minify_forth(FIXTURE).encode("utf-8"),
            ),
        ),
        linked=True,
        include_large_sample=False,
        total_sectors=2048,
    )
    image = harness.build_image(PROFILE, IMAGE)
    ok = harness.smoke(
        PROFILE,
        image,
        cols=120,
        rows=40,
        max_steps=250_000_000,
        timeout=timeout,
        ext_mem_mib=64,
    )
    return 0 if ok else 1


def main() -> int:
    parser = argparse.ArgumentParser()
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument("--static-only", action="store_true")
    mode.add_argument("--vertical", action="store_true")
    parser.add_argument("--timeout", type=float, default=120.0)
    args = parser.parse_args()

    test_atproto_aturi_source_contract()
    if args.vertical:
        return _run_vertical(args.timeout)
    print("ATPROTO ATURI STATIC PASS")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
