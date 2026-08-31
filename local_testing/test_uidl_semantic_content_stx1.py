#!/usr/bin/env python3
"""Seconds-scale structural and target byte oracles for native-to-STX1."""

from __future__ import annotations

from pathlib import Path
import re
import struct
import sys


LOCAL_TESTING = Path(__file__).resolve().parent
AKASHIC_ROOT = LOCAL_TESTING.parent
COLLECTIONS = AKASHIC_ROOT / "akashic" / "tui" / "semantic-collections.f"
PACKER = (
    AKASHIC_ROOT
    / "akashic"
    / "tui"
    / "rich-terminal"
    / "uidl-semantic-content-stx1.f"
)
DOC = AKASHIC_ROOT / "docs" / "tui" / "semantic-collections.md"
sys.path.insert(0, str(LOCAL_TESTING))

from akashic_tui import Profile, PROFILES, build_image, smoke  # noqa: E402


PROFILE_NAME = "semantic-content-stx1-byte-oracle"
ORACLE_PATH = "local_testing/usstx-byte-oracle.f"
SMOKE_MAX_STEPS = 120_000_000
SMOKE_TIMEOUT_SECONDS = 12.0

# Exact canonical layouts from MegaPad rich_terminal/semantic_content.py.
MEGAPAD_CONTENT_HEADER = struct.Struct("<IHHQIIIIIIIIQQII")
MEGAPAD_ITEM_HEADER = struct.Struct("<QIIIIHHI")
STX1_TAG = 0x31585453
STX1_VERSION = 1
CONTENT_REVISION = 0x3132333435363738
ROOT_KEY = 0x2122232425262728
PRIMARY_KEY = 0x0102030405060708
ANCHOR_KEY = 0x1112131415161718

EXPECTED_STX1 = b"".join(
    (
        MEGAPAD_CONTENT_HEADER.pack(
            STX1_TAG,
            STX1_VERSION,
            0,
            CONTENT_REVISION,
            3,
            8,
            0,
            0,
            3,
            8,
            2,
            1,
            PRIMARY_KEY,
            ANCHOR_KEY,
            2,
            4,
        ),
        MEGAPAD_ITEM_HEADER.pack(
            PRIMARY_KEY,
            0,
            0,
            1,
            8,
            1,
            0,
            3,
        ),
        b"abc",
        MEGAPAD_ITEM_HEADER.pack(
            ANCHOR_KEY,
            1,
            0,
            1,
            8,
            1,
            0,
            4,
        ),
        b"defg",
    )
)


def _module_body(path: Path) -> str:
    return "\n".join(
        line
        for line in path.read_text(encoding="utf-8").splitlines()
        if not line.startswith("PROVIDED ") and not line.startswith("REQUIRE ")
    )


def _word(source: str, name: str) -> str:
    match = re.search(rf"(?ms)^: {re.escape(name)}(?=\s).*?;\s*$", source)
    assert match is not None, name
    return match.group(0)


def _forth_bytes(name: str, payload: bytes) -> str:
    lines = [f"CREATE {name}"]
    for offset in range(0, len(payload), 24):
        chunk = payload[offset : offset + 24]
        lines.append(" ".join(f"{byte} C," for byte in chunk))
    return "\n".join(lines)


COLLECTION_BODY = _module_body(COLLECTIONS)
PACKER_TEXT = PACKER.read_text(encoding="utf-8")
PACKER_BODY = _module_body(PACKER)


ORACLE_STUBS = r'''\ Standalone oracle identity.
PROVIDED semantic-content-stx1-oracle
'''


ORACLE_CASES = rf'''\ Frozen-entry to canonical MegaPad STX1 cases.
VARIABLE _uss-fails
VARIABLE _uss-checks
VARIABLE _uss-depth
VARIABLE _uss-text-dst
VARIABLE _uss-fill-byte

CREATE _uss-native-storage 519 ALLOT
CREATE _uss-work-storage 23 ALLOT
CREATE _uss-summary-storage USCOL-SUMMARY-SIZE 7 + ALLOT
CREATE _uss-builder-storage USCOL-BUILDER-SIZE 7 + ALLOT
CREATE _uss-wire-storage 263 ALLOT

: _uss-native  _uss-native-storage 7 + -8 AND ;
: _uss-work    _uss-work-storage 7 + -8 AND ;
: _uss-summary _uss-summary-storage 7 + -8 AND ;
: _uss-builder _uss-builder-storage 7 + -8 AND ;
: _uss-wire    _uss-wire-storage 7 + -8 AND ;

: _uss-assert  ( flag -- )
    1 _uss-checks +!
    0= IF
        1 _uss-fails +!
        ." USSTX ASSERT " _uss-checks @ . CR
    THEN ;

: _uss-stack  ( -- )
    DEPTH DUP _uss-depth @ <> IF
        ." USSTX STACK " _uss-depth @ . ." -> " DUP . CR .S CR
    THEN
    _uss-depth @ = _uss-assert ;

: _uss-ok  ( status -- )
    DUP USCOL-S-OK <> IF ." USSTX STATUS " DUP . CR THEN
    USCOL-S-OK = _uss-assert ;

: _uss-filled?  ( address length byte -- flag )
    _uss-fill-byte !
    0 ?DO
        DUP I + C@ _uss-fill-byte @ <> IF
            DROP 0 UNLOOP EXIT
        THEN
    LOOP
    DROP -1 ;

: _uss-bytes=  ( actual expected length -- flag )
    0 ?DO
        2DUP I + C@ SWAP I + C@ <> IF
            2DROP 0 UNLOOP EXIT
        THEN
    LOOP
    2DROP -1 ;

: _uss-build-text  ( -- )
    _uss-native 512 _uss-builder USCOL-BUILDER-INIT _uss-ok
    USCOL-F-TEXT-AREA 0x{ROOT_KEY:016X} 2 3 4 20
        USCOL-STATE-VISIBLE USCOL-STATE-ENABLED OR
        _uss-builder USCOL-TEXT-BEGIN _uss-ok
    USCOL-CONTENT-READ-ONLY 3 8 0 0 3 8
        _uss-builder USCOL-TEXT-SHAPE _uss-ok
    0x{PRIMARY_KEY:016X} 0x{ANCHOR_KEY:016X} 2 4
        _uss-builder USCOL-TEXT-POSITIONS _uss-ok

    0x{PRIMARY_KEY:016X} 0 0 1 8 USCOL-ROLE-CONTENT 0 3
        _uss-builder USCOL-TEXT-ITEM-BEGIN _uss-ok
    DUP 0<> _uss-assert _uss-text-dst !
    S" abc" _uss-text-dst @ SWAP MOVE
    _uss-builder USCOL-TEXT-ITEM-END _uss-ok

    0x{ANCHOR_KEY:016X} 1 0 1 8 USCOL-ROLE-CONTENT 0 4
        _uss-builder USCOL-TEXT-ITEM-BEGIN _uss-ok
    DUP 0<> _uss-assert _uss-text-dst !
    S" defg" _uss-text-dst @ SWAP MOVE
    _uss-builder USCOL-TEXT-ITEM-END _uss-ok
    _uss-builder USCOL-TEXT-END _uss-ok
    _uss-builder USCOL-BUILDER-FINISH _uss-ok 312 = _uss-assert

    _uss-native 312 _uss-work 16 _uss-summary
        USCOL-ENTRY-VALIDATE _uss-ok ;

: _uss-pack-case  ( -- )
    _uss-build-text
    _uss-summary USCOL-SUMMARY-ITEM-COUNT@ 2 = _uss-assert
    _uss-summary USCOL-SUMMARY-UTF8-BYTES@ 7 = _uss-assert
    _uss-summary USCOL-SUMMARY-STX1-BYTES _uss-ok 143 = _uss-assert

    _uss-wire 256 0xA5 FILL
    _uss-native 312 _uss-summary 0x{CONTENT_REVISION:016X} _uss-wire 256
        USSTX-PACK _uss-ok 143 = _uss-assert
    _uss-wire _uss-expected 143 _uss-bytes= _uss-assert
    _uss-wire 143 + 113 0xA5 _uss-filled? _uss-assert

    \ Native item padding is absent even from a byte-aligned destination.
    _uss-wire 256 0xA5 FILL
    _uss-native 312 _uss-summary 0x{CONTENT_REVISION:016X}
        _uss-wire 1+ 255 USSTX-PACK _uss-ok 143 = _uss-assert
    _uss-wire C@ 0xA5 = _uss-assert
    _uss-wire 1+ _uss-expected 143 _uss-bytes= _uss-assert
    _uss-wire 144 + 112 0xA5 _uss-filled? _uss-assert

    \ O(1) refusals occur before the destination is touched.
    _uss-wire 256 0xA5 FILL
    _uss-native 312 _uss-summary 0x{CONTENT_REVISION:016X} _uss-wire 142
        USSTX-PACK USCOL-S-CAPACITY = _uss-assert
        0= _uss-assert
    _uss-wire 256 0xA5 _uss-filled? _uss-assert

    _uss-native 312 _uss-summary 0 _uss-wire 256
        USSTX-PACK USCOL-S-INVALID = _uss-assert
        0= _uss-assert
    _uss-wire 256 0xA5 _uss-filled? _uss-assert

    1 _uss-summary USCOL-SUMMARY-ROOT-KEY-OFFSET + +!
    _uss-native 312 _uss-summary 0x{CONTENT_REVISION:016X} _uss-wire 256
        USSTX-PACK USCOL-S-INVALID = _uss-assert
        0= _uss-assert
    _uss-wire 256 0xA5 _uss-filled? _uss-assert
    -1 _uss-summary USCOL-SUMMARY-ROOT-KEY-OFFSET + +! ;

: _uss-build-tabs  ( -- )
    _uss-native 512 _uss-builder USCOL-BUILDER-INIT _uss-ok
    30 0 0 1 20 3 _uss-builder USCOL-TABSET-BEGIN _uss-ok
    200 5 7 S" One" S" 1" _uss-builder USCOL-TAB _uss-ok
    100 9 3 S" Two" 0 0 _uss-builder USCOL-TAB _uss-ok
    _uss-builder USCOL-TABSET-END _uss-ok
    _uss-builder USCOL-BUILDER-FINISH _uss-ok 176 = _uss-assert
    _uss-native 176 _uss-work 16 _uss-summary
        USCOL-ENTRY-VALIDATE _uss-ok ;

: _uss-unsupported-case  ( -- )
    _uss-build-tabs
    _uss-wire 256 0xA5 FILL
    _uss-native 176 _uss-summary 7 _uss-wire 256 USSTX-PACK
        USCOL-S-UNSUPPORTED = _uss-assert
        0= _uss-assert
    _uss-wire 256 0xA5 _uss-filled? _uss-assert ;

: _uss-run  ( -- )
    0 _uss-fails ! 0 _uss-checks ! DEPTH _uss-depth !
    _uss-pack-case _uss-stack
    _uss-unsupported-case _uss-stack
    _uss-fails @ 0= IF
        ." USSTX PASS " _uss-checks @ .
    ELSE
        ." USSTX FAIL " _uss-fails @ . ." / " _uss-checks @ .
    THEN CR ;

_uss-run
'''


ORACLE_SOURCE = "\n\n".join(
    (
        ORACLE_STUBS.strip(),
        COLLECTION_BODY.strip(),
        PACKER_BODY.strip(),
        _forth_bytes("_uss-expected", EXPECTED_STX1),
        ORACLE_CASES.strip(),
    )
) + "\n"

AUTOEXEC = rf'''\ autoexec.f - native semantic content STX1 byte oracle
ENTER-USERLAND
." [akashic] loading native semantic content STX1 byte oracle" CR
REQUIRE utils/memory-span.f
REQUIRE text/utf8.f
REQUIRE {ORACLE_PATH}
'''


def test_uidl_semantic_content_stx1_structure() -> None:
    source = PACKER_TEXT
    correlate = _word(source, "_USSTX-CORRELATE")
    one = _word(source, "_USSTX-PACK-ONE?")
    items = _word(source, "_USSTX-PACK-ITEMS?")
    body = _word(source, "_USSTX-PACK-BODY")
    public = _word(source, "USSTX-PACK")
    doc = DOC.read_text(encoding="utf-8")

    assert re.findall(r"(?m)^REQUIRE (.+)$", source) == [
        "../semantic-collections.f"
    ]
    for declaration in (
        "0x31585453 CONSTANT USSTX-TAG",
        "1 CONSTANT USSTX-VERSION",
        "72 CONSTANT USSTX-CONTENT-HEADER-SIZE",
        "32 CONSTANT USSTX-ITEM-HEADER-SIZE",
    ):
        assert declaration in source
    assert MEGAPAD_CONTENT_HEADER.size == 72
    assert MEGAPAD_ITEM_HEADER.size == 32
    assert len(EXPECTED_STX1) == 143
    assert EXPECTED_STX1[:4] == b"STX1"

    for correlation in (
        "USCOL-ENTRY-BYTES@",
        "USCOL-ENTRY-FAMILY@",
        "USCOL-ENTRY-FAMILY-ABI@",
        "USCOL-ENTRY-KEY@",
        "USCOL-SUMMARY-ENTRY-BYTES@",
        "USCOL-SUMMARY-FAMILY@",
        "USCOL-SUMMARY-ROOT-KEY@",
        "USCOL-SUMMARY-STX1-BYTES",
        "MSPAN-NONWRAPPING?",
        "_USSTX-DISJOINT?",
    ):
        assert correlation in correlate
    for forbidden in ("?DO", "MOVE", "USCOL-ITEM-KEY@", "USCOL-ITEM-NEXT"):
        assert forbidden not in correlate

    assert items.count("0 ?DO") == 1
    assert "_USSTX-PACK-ONE?" in items
    assert one.count("MOVE") == 1
    assert "USCOL-ITEM-ROW-SPAN@" not in source
    assert "1 _USSTX-WIRE @ 16 + _USSTX-LE32!" in one
    assert "USCOL-TEXT-ITEM-BYTES" in one
    assert "_USSTX-COPIED-UTF8" in one
    assert "_USSTX-NATIVE-U @ 0=" in items
    assert "_USSTX-WIRE-U @ 0=" in items

    packed_words = "\n".join((correlate, one, items, body, public))
    for forbidden in (
        "USCOL-ENTRY-VALIDATE",
        "USCOL-VALIDATION-WORK-BYTES",
        "UTF8-VALID?",
        "UTF8-DECODE",
        "_USCOL-UNIQUE-CELLS?",
    ):
        assert forbidden not in packed_words
    assert " L!" not in source
    assert " W!" not in source
    assert "ALLOCATE" not in source
    assert " FREE" not in source
    assert body.index("_USSTX-CORRELATE") < body.index("_USSTX-HEADER!")
    assert body.index("_USSTX-PACK-ITEMS?") < body.index("USSTX-TAG")
    assert "0 _USSTX-DST @ _USSTX-LE32!" in _word(source, "_USSTX-HEADER!")
    assert "same frozen native entry and summary" in doc
    assert "does not call `USCOL-ENTRY-VALIDATE`" in doc


def test_uidl_semantic_content_stx1_byte_oracle(tmp_path: Path) -> None:
    assert PACKER_TEXT.count("PROVIDED akashic-tui-rterm-usstx") == 1
    assert "UTUI-" not in COLLECTION_BODY
    assert "UTUI-" not in PACKER_BODY
    assert "USCOL-ENTRY-VALIDATE" not in PACKER_BODY
    assert "UTF8-VALID?" not in PACKER_BODY
    assert max(len(line.encode("utf-8")) for line in ORACLE_SOURCE.splitlines()) <= 255

    previous = PROFILES.get(PROFILE_NAME)
    PROFILES[PROFILE_NAME] = Profile(
        roots=("utils/memory-span.f", "text/utf8.f"),
        resources=(),
        autoexec=AUTOEXEC,
        ready_markers=("USSTX PASS",),
        stable_markers=("USSTX PASS",),
        failure_markers=(
            "USSTX FAIL",
            "USSTX ASSERT",
            "USSTX STACK",
            "dictionary full",
            "exception",
            "? (not found)",
        ),
        initial_files=((ORACLE_PATH, ORACLE_SOURCE.encode("utf-8")),),
        linked=False,
        include_large_sample=False,
    )
    try:
        image = build_image(
            PROFILE_NAME,
            tmp_path / "uidl-semantic-content-stx1.img",
        )
        assert smoke(
            PROFILE_NAME,
            image,
            cols=80,
            rows=24,
            max_steps=SMOKE_MAX_STEPS,
            timeout=SMOKE_TIMEOUT_SECONDS,
        )
    finally:
        if previous is None:
            PROFILES.pop(PROFILE_NAME, None)
        else:
            PROFILES[PROFILE_NAME] = previous


if __name__ == "__main__":
    import tempfile

    test_uidl_semantic_content_stx1_structure()
    with tempfile.TemporaryDirectory() as directory:
        test_uidl_semantic_content_stx1_byte_oracle(Path(directory))
