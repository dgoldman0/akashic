#!/usr/bin/env python3
"""Seconds-scale target oracle for RUHA semantic descriptor ordering.

The target runs the production descriptor ABI and production in-place
heapsort words extracted from the adapter.  It does not load Desk, applets, a
renderer, or a persistence surface.
"""

from __future__ import annotations

from pathlib import Path
import re
import sys


LOCAL_TESTING = Path(__file__).resolve().parent
AKASHIC_ROOT = LOCAL_TESTING.parent
ADAPTER = AKASHIC_ROOT / "akashic/tui/rich-terminal/uidl-hybrid-adapter.f"
sys.path.insert(0, str(LOCAL_TESTING))

from akashic_tui import Profile, PROFILES, build_image, smoke  # noqa: E402


PROFILE_NAME = "rich-terminal-ruha-descriptor-target"
ORACLE_PATH = "local_testing/ruha-desc-oracle.f"
SMOKE_MAX_STEPS = 80_000_000
SMOKE_TIMEOUT_SECONDS = 10.0

SOURCE = ADAPTER.read_text(encoding="utf-8")


def _section(start: str, end_word: str) -> str:
    match = re.search(
        rf"(?ms)^{re.escape(start)}.*?^: {re.escape(end_word)}(?=\s).*?;\s*$",
        SOURCE,
    )
    assert match is not None, (start, end_word)
    return match.group(0)


DESCRIPTOR_ABI = _section(
    ": _RUHA-C.SOURCE-INDEX", "RUHA-SEMANTIC-SUMMARY"
)
SORT_WORDS = _section(
    "VARIABLE _RUHA-B-SORT-BASE", "_RUHA-B-SORT-DESCRIPTORS"
)


ORACLE_SOURCE = rf'''\ Production RUHA descriptor ABI and canonical sorter.
PROVIDED rich-terminal-ruha-descriptor-oracle

0 CONSTANT RUHA-S-OK
5 CONSTANT RUHA-S-INVALID

: USCOL-SUMMARY-ROOT-KEY@  ( summary -- key )  8 + @ ;

{DESCRIPTOR_ABI}

{SORT_WORDS}

VARIABLE _rhd-fails
VARIABLE _rhd-checks
VARIABLE _rhd-depth
VARIABLE _rhd-fill-byte

CREATE _rhd-descriptor-storage 367 ALLOT
CREATE _rhd-native-storage 263 ALLOT
: _rhd-descriptors  _rhd-descriptor-storage 7 + -8 AND ;
: _rhd-native       _rhd-native-storage 7 + -8 AND ;

: _rhd-assert  ( flag -- )
    1 _rhd-checks +!
    0= IF
        1 _rhd-fails +!
        ." RUHA-DESC ASSERT " _rhd-checks @ . CR
    THEN ;

: _rhd-stack  ( -- )
    DEPTH DUP _rhd-depth @ <> IF
        ." RUHA-DESC STACK " _rhd-depth @ . ." -> " DUP . CR .S CR
    THEN
    _rhd-depth @ = _rhd-assert ;

: _rhd-filled?  ( address length byte -- flag )
    _rhd-fill-byte !
    0 ?DO
        DUP I + C@ _rhd-fill-byte @ <> IF
            DROP 0 UNLOOP EXIT
        THEN
    LOOP
    DROP -1 ;

: _rhd-d0  _rhd-descriptors ;
: _rhd-d1  _rhd-descriptors RUHA-SEMANTIC-DESCRIPTOR-SIZE + ;
: _rhd-d2  _rhd-d1 RUHA-SEMANTIC-DESCRIPTOR-SIZE + ;

: _rhd-write  ( source root row marker descriptor -- )
    DUP RUHA-SEMANTIC-DESCRIPTOR-SIZE 0 FILL
    >R
    R@ 112 + !
    R@ 32 + !
    R@ RUHA-SEMANTIC-SUMMARY 8 + !
    R> ! ;

: _rhd-build-inverted  ( -- )
    7 20 700 71 _rhd-d0 _rhd-write
    3 30 330 32 _rhd-d1 _rhd-write
    3 10 310 31 _rhd-d2 _rhd-write ;

: _rhd-sort-case  ( -- )
    _rhd-native 256 0xA5 FILL
    _rhd-build-inverted
    _rhd-descriptors 360 _RUHA-B-SORT-DESCRIPTORS
        RUHA-S-OK = _rhd-assert
    _rhd-d0 RUHA-SEMANTIC-SOURCE-INDEX@ 3 = _rhd-assert
    _rhd-d0 RUHA-SEMANTIC-SUMMARY USCOL-SUMMARY-ROOT-KEY@
        10 = _rhd-assert
    _rhd-d0 RUHA-SEMANTIC-ELEMENT-ROW@ 310 = _rhd-assert
    _rhd-d0 112 + @ 31 = _rhd-assert
    _rhd-d1 RUHA-SEMANTIC-SOURCE-INDEX@ 3 = _rhd-assert
    _rhd-d1 RUHA-SEMANTIC-SUMMARY USCOL-SUMMARY-ROOT-KEY@
        30 = _rhd-assert
    _rhd-d1 RUHA-SEMANTIC-ELEMENT-ROW@ 330 = _rhd-assert
    _rhd-d2 RUHA-SEMANTIC-SOURCE-INDEX@ 7 = _rhd-assert
    _rhd-d2 RUHA-SEMANTIC-ELEMENT-ROW@ 700 = _rhd-assert
    _rhd-native 256 0xA5 _rhd-filled? _rhd-assert ;

: _rhd-corruption-case  ( -- )
    _rhd-build-inverted
    10 _rhd-d1 RUHA-SEMANTIC-SUMMARY 8 + !
    _rhd-descriptors 360 _RUHA-B-SORT-DESCRIPTORS
        RUHA-S-INVALID = _rhd-assert
    _rhd-descriptors 359 _RUHA-B-SORT-DESCRIPTORS
        RUHA-S-INVALID = _rhd-assert ;

: _rhd-run  ( -- )
    0 _rhd-fails ! 0 _rhd-checks ! DEPTH _rhd-depth !
    _rhd-sort-case _rhd-stack
    _rhd-corruption-case _rhd-stack
    _rhd-fails @ 0= IF
        ." RUHA-DESC PASS " _rhd-checks @ .
    ELSE
        ." RUHA-DESC FAIL " _rhd-fails @ . ." / " _rhd-checks @ .
    THEN CR ;

_rhd-run
'''


AUTOEXEC = rf'''\ autoexec.f - bounded RUHA descriptor target oracle
ENTER-USERLAND
." [akashic] loading RUHA descriptor target oracle" CR
REQUIRE {ORACLE_PATH}
'''


def test_ruha_descriptor_target_oracle(tmp_path: Path) -> None:
    assert "_RUHA-B-DESCRIPTOR-SIFT" in SORT_WORDS
    assert "_RUHA-B-DESCRIPTORS-STRICT?" in SORT_WORDS
    assert "_RUHA-B-NATIVE" not in SORT_WORDS
    assert max(len(line.encode("utf-8")) for line in ORACLE_SOURCE.splitlines()) <= 255

    previous = PROFILES.get(PROFILE_NAME)
    PROFILES[PROFILE_NAME] = Profile(
        roots=(),
        resources=(),
        autoexec=AUTOEXEC,
        ready_markers=("RUHA-DESC PASS",),
        stable_markers=("RUHA-DESC PASS",),
        failure_markers=(
            "RUHA-DESC FAIL",
            "RUHA-DESC ASSERT",
            "RUHA-DESC STACK",
            "dictionary full",
            "exception",
            "? (not found)",
        ),
        initial_files=((ORACLE_PATH, ORACLE_SOURCE.encode("utf-8")),),
        linked=False,
        include_large_sample=False,
    )
    try:
        image = build_image(PROFILE_NAME, tmp_path / "ruha-descriptor.img")
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
        test_ruha_descriptor_target_oracle(Path(directory))
