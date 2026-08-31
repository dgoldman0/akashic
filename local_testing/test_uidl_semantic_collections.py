#!/usr/bin/env python3
"""Minimal target byte/validator oracle for neutral semantic collections.

The oracle loads the production lower family module verbatim except for its
two normal utility dependencies. The module itself owns the status and entry
vocabulary exercised by this seconds-scale selector.
"""

from __future__ import annotations

from pathlib import Path
import sys


LOCAL_TESTING = Path(__file__).resolve().parent
AKASHIC_ROOT = LOCAL_TESTING.parent
MODULE = AKASHIC_ROOT / "akashic" / "tui" / "semantic-collections.f"
sys.path.insert(0, str(LOCAL_TESTING))

from akashic_tui import Profile, PROFILES, build_image, smoke  # noqa: E402


PROFILE_NAME = "semantic-collections-byte-oracle"
ORACLE_PATH = "local_testing/uscol-byte-oracle.f"
SMOKE_MAX_STEPS = 120_000_000
SMOKE_TIMEOUT_SECONDS = 12.0


_MODULE_TEXT = MODULE.read_text(encoding="utf-8")
_MODULE_BODY = "\n".join(
    line
    for line in _MODULE_TEXT.splitlines()
    if not line.startswith("PROVIDED ") and not line.startswith("REQUIRE ")
)


ORACLE_STUBS = r'''\ Standalone oracle identity.
PROVIDED semantic-collections-oracle
'''


ORACLE_CASES = r'''\ Focused native-byte and deep-validation cases.
VARIABLE _usc-fails
VARIABLE _usc-checks
VARIABLE _usc-depth
VARIABLE _usc-text-dst

CREATE _usc-output-storage 2055 ALLOT
CREATE _usc-work-storage 1031 ALLOT
CREATE _usc-summary-storage USCOL-SUMMARY-SIZE 7 + ALLOT
CREATE _usc-builder-storage USCOL-BUILDER-SIZE 7 + ALLOT
\ Native semantic collection records deliberately require eight-byte starts;
\ this target dictionary does not promise CREATE more than byte alignment.
: _usc-output  _usc-output-storage 7 + -8 AND ;
: _usc-work    _usc-work-storage 7 + -8 AND ;
: _usc-summary _usc-summary-storage 7 + -8 AND ;
: _usc-builder _usc-builder-storage 7 + -8 AND ;

: _usc-assert  ( flag -- )
    1 _usc-checks +!
    0= IF
        1 _usc-fails +!
        ." USCOL ASSERT " _usc-checks @ . CR
    THEN ;

: _usc-stack  ( -- )
    DEPTH DUP _usc-depth @ <> IF
        ." USCOL STACK " _usc-depth @ . ." -> " DUP . CR .S CR
    THEN
    _usc-depth @ = _usc-assert ;

VARIABLE _usc-fill-byte
: _usc-filled?  ( address length byte -- flag )
    _usc-fill-byte !
    0 ?DO
        DUP I + C@ _usc-fill-byte @ <> IF
            DROP 0 UNLOOP EXIT
        THEN
    LOOP
    DROP -1 ;

: _usc-ok  ( status -- )
    DUP USCOL-S-OK <> IF ." USCOL STATUS " DUP . CR THEN
    USCOL-S-OK = _usc-assert ;

: _usc-text-case  ( -- )
    _usc-output 2048 _usc-builder USCOL-BUILDER-INIT _usc-ok
    USCOL-F-TEXT-AREA 10 2 3 4 20
        USCOL-STATE-VISIBLE USCOL-STATE-ENABLED OR
        _usc-builder USCOL-TEXT-BEGIN _usc-ok
    0 3 8 0 0 3 8 _usc-builder USCOL-TEXT-SHAPE _usc-ok
    101 0 2 0 _usc-builder USCOL-TEXT-POSITIONS _usc-ok

    101 0 0 1 8 USCOL-ROLE-CONTENT 0 3 _usc-builder
        USCOL-TEXT-ITEM-BEGIN _usc-ok
    DUP 0<> _usc-assert _usc-text-dst !
    S" abc" _usc-text-dst @ SWAP MOVE
    _usc-builder USCOL-TEXT-ITEM-END _usc-ok

    102 1 0 1 8 USCOL-ROLE-CONTENT 0 4 _usc-builder
        USCOL-TEXT-ITEM-BEGIN _usc-ok
    DUP 0<> _usc-assert _usc-text-dst !
    S" de" _usc-text-dst @ SWAP MOVE
    S" fg" _usc-text-dst @ 2 + SWAP MOVE
    _usc-builder USCOL-TEXT-ITEM-END _usc-ok
    _usc-builder USCOL-TEXT-END _usc-ok
    _usc-builder USCOL-BUILDER-FINISH _usc-ok 312 = _usc-assert

    _usc-output @ 312 = _usc-assert
    _usc-output 8 + @ USCOL-F-TEXT-AREA = _usc-assert
    _usc-output 16 + @ USCOL-FAMILY-ABI = _usc-assert
    _usc-output 24 + @ 10 = _usc-assert
    _usc-output USCOL-TEXT-ITEM-COUNT@ 2 = _usc-assert
    _usc-output USCOL-TEXT-FIRST USCOL-ITEM-TEXT-BYTES@ 3 = _usc-assert
    _usc-output USCOL-TEXT-FIRST USCOL-ITEM-TEXT-OFFSET + C@
        [CHAR] a = _usc-assert
    _usc-output USCOL-TEXT-FIRST USCOL-ITEM-NEXT
        USCOL-ITEM-TEXT-BYTES@ 4 = _usc-assert

    _usc-output 312 USCOL-VALIDATION-WORK-BYTES
        _usc-ok 16 = _usc-assert
    _usc-output 312 _usc-work 16 _usc-summary
        USCOL-ENTRY-VALIDATE _usc-ok
    _usc-summary USCOL-SUMMARY-FAMILY@ USCOL-F-TEXT-AREA = _usc-assert
    _usc-summary USCOL-SUMMARY-ENTRY-BYTES@ 312 = _usc-assert
    _usc-summary USCOL-SUMMARY-ITEM-COUNT@ 2 = _usc-assert
    _usc-summary USCOL-SUMMARY-UTF8-BYTES@ 7 = _usc-assert
    _usc-summary USCOL-SUMMARY-STX1-BYTES _usc-ok 143 = _usc-assert

    10 _usc-output USCOL-TEXT-FIRST USCOL-ITEM-TEXT-OFFSET + C!
    _usc-summary USCOL-SUMMARY-SIZE 0xA5 FILL
    _usc-output 312 _usc-work 16 _usc-summary USCOL-ENTRY-VALIDATE
        USCOL-S-INVALID = _usc-assert
    _usc-summary USCOL-SUMMARY-SIZE 0 _usc-filled? _usc-assert
    [CHAR] a _usc-output USCOL-TEXT-FIRST USCOL-ITEM-TEXT-OFFSET + C! ;

: _usc-measure-case  ( -- )
    0 0 _usc-builder USCOL-BUILDER-INIT _usc-ok
    USCOL-F-TEXT-AREA 11 0 0 2 8 0 _usc-builder USCOL-TEXT-BEGIN _usc-ok
    0 1 8 0 0 1 8 _usc-builder USCOL-TEXT-SHAPE _usc-ok
    0 0 0 0 _usc-builder USCOL-TEXT-POSITIONS _usc-ok
    111 0 0 1 8 USCOL-ROLE-CONTENT 0 5 _usc-builder
        USCOL-TEXT-ITEM-BEGIN _usc-ok 0= _usc-assert
    _usc-builder USCOL-TEXT-ITEM-END _usc-ok
    _usc-builder USCOL-TEXT-END _usc-ok
    _usc-builder USCOL-BUILDER-FINISH _usc-ok 240 = _usc-assert ;

: _usc-grid-build  ( -- )
    _usc-output 2048 _usc-builder USCOL-BUILDER-INIT _usc-ok
    USCOL-F-TEXT-GRID 20 0 0 4 6 3 _usc-builder USCOL-TEXT-BEGIN _usc-ok
    0 4 6 0 0 4 6 _usc-builder USCOL-TEXT-SHAPE _usc-ok
    303 0 0 0 _usc-builder USCOL-TEXT-POSITIONS _usc-ok
    301 0 0 1 2 USCOL-ROLE-CONTENT 0 0 0 _usc-builder
        USCOL-TEXT-ITEM _usc-ok
    302 0 2 1 2 USCOL-ROLE-ROW-HEADER 0 0 0 _usc-builder
        USCOL-TEXT-ITEM _usc-ok
    303 1 2 1 2 USCOL-ROLE-CONTENT USCOL-ITEM-CURRENT 0 0 _usc-builder
        USCOL-TEXT-ITEM _usc-ok
    _usc-builder USCOL-TEXT-END _usc-ok
    _usc-builder USCOL-BUILDER-FINISH _usc-ok 360 = _usc-assert ;

: _usc-grid-case  ( -- )
    _usc-grid-build
    _usc-output 360 USCOL-VALIDATION-WORK-BYTES
        _usc-ok 24 = _usc-assert
    _usc-output 360 _usc-work 24 _usc-summary
        USCOL-ENTRY-VALIDATE _usc-ok
    _usc-summary USCOL-SUMMARY-ITEM-COUNT@ 3 = _usc-assert

    1 _usc-output 248 + !
    _usc-summary USCOL-SUMMARY-SIZE 0xA5 FILL
    _usc-output 360 _usc-work 24 _usc-summary USCOL-ENTRY-VALIDATE
        USCOL-S-INVALID = _usc-assert
    _usc-summary USCOL-SUMMARY-SIZE 0 _usc-filled? _usc-assert
    2 _usc-output 248 + !
    _usc-output 360 _usc-work 24 _usc-summary
        USCOL-ENTRY-VALIDATE _usc-ok

    2 _usc-output 192 + !
    _usc-output 360 _usc-work 24 _usc-summary USCOL-ENTRY-VALIDATE
        USCOL-S-INVALID = _usc-assert
    1 _usc-output 192 + !

    301 _usc-output 296 + !
    _usc-output 360 _usc-work 24 _usc-summary USCOL-ENTRY-VALIDATE
        USCOL-S-INVALID = _usc-assert
    303 _usc-output 296 + ! ;

: _usc-tabs-build  ( -- )
    _usc-output 2048 _usc-builder USCOL-BUILDER-INIT _usc-ok
    30 0 0 1 20 3 _usc-builder USCOL-TABSET-BEGIN _usc-ok
    200 5 7 S" One" S" 1" _usc-builder USCOL-TAB _usc-ok
    100 9 3 S" Two" 0 0 _usc-builder USCOL-TAB _usc-ok
    _usc-builder USCOL-TABSET-END _usc-ok
    _usc-builder USCOL-BUILDER-FINISH _usc-ok 176 = _usc-assert ;

: _usc-tabs-case  ( -- )
    _usc-tabs-build
    _usc-output USCOL-TABSET-COUNT@ 2 = _usc-assert
    _usc-output USCOL-TABSET-FIRST USCOL-TAB-KEY@ 200 = _usc-assert
    _usc-output USCOL-TABSET-FIRST USCOL-TAB-NEXT USCOL-TAB-KEY@
        100 = _usc-assert
    _usc-output 176 USCOL-VALIDATION-WORK-BYTES _usc-ok 16 = _usc-assert
    _usc-output 176 _usc-work 16 _usc-summary USCOL-ENTRY-VALIDATE _usc-ok
    _usc-summary USCOL-SUMMARY-CHILD-COUNT@ 2 = _usc-assert
    _usc-summary USCOL-SUMMARY-UTF8-BYTES@ 7 = _usc-assert

    200 _usc-output 128 + !
    _usc-output 176 _usc-work 16 _usc-summary USCOL-ENTRY-VALIDATE
        USCOL-S-INVALID = _usc-assert
    100 _usc-output 128 + !
    4 _usc-output 136 + !
    _usc-output 176 _usc-work 16 _usc-summary USCOL-ENTRY-VALIDATE
        USCOL-S-INVALID = _usc-assert
    9 _usc-output 136 + ! ;

: _usc-capacity-case  ( -- )
    _usc-output 167 _usc-builder USCOL-BUILDER-INIT _usc-ok
    USCOL-F-TEXT-AREA 40 0 0 1 1 0 _usc-builder USCOL-TEXT-BEGIN
        USCOL-S-CAPACITY = _usc-assert
    _usc-builder USCOL-BUILDER-INVALID
        USCOL-S-CAPACITY = _usc-assert
    _usc-builder USCOL-BUILDER-FINISH
        USCOL-S-CAPACITY = _usc-assert 0= _usc-assert ;

: _usc-run  ( -- )
    0 _usc-fails ! 0 _usc-checks ! DEPTH _usc-depth !
    _usc-text-case _usc-stack
    _usc-measure-case _usc-stack
    _usc-grid-case _usc-stack
    _usc-tabs-case _usc-stack
    _usc-capacity-case _usc-stack
    _usc-fails @ 0= IF
        ." USCOL PASS " _usc-checks @ .
    ELSE
        ." USCOL FAIL " _usc-fails @ . ." / " _usc-checks @ .
    THEN CR ;

_usc-run
'''


ORACLE_SOURCE = "\n\n".join(
    (ORACLE_STUBS.strip(), _MODULE_BODY.strip(), ORACLE_CASES.strip())
) + "\n"

AUTOEXEC = rf'''\ autoexec.f - neutral semantic collection byte oracle
ENTER-USERLAND
." [akashic] loading neutral semantic collection byte oracle" CR
REQUIRE utils/memory-span.f
REQUIRE text/utf8.f
REQUIRE {ORACLE_PATH}
'''


def test_uidl_semantic_collections_byte_oracle(tmp_path: Path) -> None:
    assert _MODULE_TEXT.count("PROVIDED akashic-tui-semantic-collections") == 1
    assert "REQUIRE uidl-tui.f" not in _MODULE_TEXT
    assert "UTUI-" not in _MODULE_TEXT
    assert "USCOL-TEXT-ITEM-BEGIN" in _MODULE_BODY
    assert "USCOL-ENTRY-VALIDATE" in _MODULE_BODY
    assert "REQUIRE uidl-tui.f" not in ORACLE_SOURCE
    assert max(len(line.encode("utf-8")) for line in ORACLE_SOURCE.splitlines()) <= 255

    previous = PROFILES.get(PROFILE_NAME)
    PROFILES[PROFILE_NAME] = Profile(
        roots=("utils/memory-span.f", "text/utf8.f"),
        resources=(),
        autoexec=AUTOEXEC,
        ready_markers=("USCOL PASS",),
        stable_markers=("USCOL PASS",),
        failure_markers=(
            "USCOL FAIL",
            "USCOL ASSERT",
            "USCOL STACK",
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
            tmp_path / "semantic-collections.img",
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

    with tempfile.TemporaryDirectory() as directory:
        test_uidl_semantic_collections_byte_oracle(Path(directory))
