#!/usr/bin/env python3
"""Linked regression contract for malformed-markup scanner progress."""

from __future__ import annotations

import argparse
import sys
from pathlib import Path


LOCAL_TESTING = Path(__file__).resolve().parent
sys.path.insert(0, str(LOCAL_TESTING))

import akashic_tui as harness  # noqa: E402


PROFILE = "markup-progress-contracts"
IMAGE = Path("/tmp/akashic-markup-progress-contracts.img")

AUTOEXEC = r'''\ autoexec.f - malformed markup forward-progress contracts
ENTER-USERLAND
REQUIRE markup/html.f
REQUIRE liraq/uidl.f
." MP-M1-REQUIRE" CR

VARIABLE _mp-fails
VARIABLE _mp-checks
VARIABLE _mp-depth
VARIABLE _mp-start
VARIABLE _mp-end
VARIABLE _mp-uidl-result
VARIABLE _mp-uidl-reached

: _mp-assert  ( flag -- )
    1 _mp-checks +!
    0= IF 1 _mp-fails +! ." MARKUP PROGRESS ASSERT " _mp-checks @ . CR THEN ;

: _mp-stack  ( -- )
    DEPTH DUP _mp-depth @ <> IF
        ." MARKUP PROGRESS STACK " _mp-depth @ . ." -> " DUP . CR .S CR
    THEN
    _mp-depth @ = _mp-assert ;

: _mp-uidl-truncated  ( -- )
    S" <uidl><region><label" UIDL-PARSE _mp-uidl-result !
    -1 _mp-uidl-reached ! ;

: _mp-run  ( -- )
    0 _mp-fails ! 0 _mp-checks ! DEPTH _mp-depth !

    \ The low-level text scan retains its boundary contract and malformed
    \ classification; progress is supplied only by depth-scanner fallback.
    S" text<child" OVER _mp-start ! MU-SKIP-TO-TAG
    DUP 6 = _mp-assert
    SWAP _mp-start @ 4 + = _mp-assert DROP
    S" <child" MU-TAG-TYPE MU-T-TEXT = _mp-assert

    \ Core depth scans must consume a truncated nested tag and still leave
    \ an ordinary matching close tag at the cursor.
    S" <outer>text<child" 2DUP + _mp-end ! MU-SKIP-ELEMENT
    DUP 0= _mp-assert
    SWAP _mp-end @ = _mp-assert DROP
    S" text<child" 2DUP + _mp-end ! S" outer" MU-FIND-CLOSE
    DUP 0= _mp-assert
    SWAP _mp-end @ = _mp-assert DROP
    S" text<b/></outer>tail" S" outer" MU-FIND-CLOSE
        S" </outer>tail" STR-STR= _mp-assert

    \ HTML's void-aware variants carry the same progress guarantee without
    \ changing case-insensitive matching or close-tag positioning.
    S" <div>text<span" 2DUP + _mp-end ! _HTML-SKIP-ELEMENT
    DUP 0= _mp-assert
    SWAP _mp-end @ = _mp-assert DROP
    S" text<span" 2DUP + _mp-end ! S" div" _HTML-FIND-CLOSE
    DUP 0= _mp-assert
    SWAP _mp-end @ = _mp-assert DROP
    S" text<br></DIV>tail" S" div" _HTML-FIND-CLOSE
        S" </DIV>tail" STR-STR= _mp-assert

    \ HTML-INNER must return only its documented pair for both ordinary and
    \ raw-text elements; the internal close cursor is not caller-visible.
    S" <DIV>Hello <b>World</b></div>tail" HTML-INNER
        S" Hello <b>World</b>" STR-STR= _mp-assert
    _mp-stack
    S" <script>if (a < b) x();</SCRIPT>tail" HTML-INNER
        S" if (a < b) x();" STR-STR= _mp-assert
    _mp-stack

    \ UIDL keeps its current recovery result while proving the real parser
    \ reaches completion instead of spinning on the nested '<label' suffix.
    0 _mp-uidl-result ! 0 _mp-uidl-reached !
    ['] _mp-uidl-truncated CATCH 0= _mp-assert
    _mp-uidl-reached @ -1 = _mp-assert
    _mp-uidl-result @ -1 = _mp-assert
    UIDL-ELEM-COUNT 2 = _mp-assert
    UIDL-ERR UIDL-E-OK = _mp-assert

    _mp-stack
    _mp-fails @ 0= IF
        ." MARKUP PROGRESS PASS " _mp-checks @ .
    ELSE
        ." MARKUP PROGRESS FAIL " _mp-fails @ .
    THEN CR ;

: _mp-driver  ( -- )
    ['] _mp-run CATCH ?DUP IF
        ." MARKUP PROGRESS DRIVER THROW " . CR
    THEN ;

_mp-driver
'''


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--timeout", type=float, default=60.0)
    args = parser.parse_args()
    harness.PROFILES[PROFILE] = harness.Profile(
        roots=("markup/html.f", "liraq/uidl.f"),
        resources=(),
        autoexec=AUTOEXEC,
        ready_markers=("MARKUP PROGRESS PASS",),
        stable_markers=("MARKUP PROGRESS PASS",),
        failure_markers=(
            "MARKUP PROGRESS FAIL",
            "MARKUP PROGRESS ASSERT",
            "MARKUP PROGRESS STACK",
            "MARKUP PROGRESS DRIVER THROW",
        ),
        linked=True,
        include_large_sample=False,
        total_sectors=2048,
    )
    image = harness.build_image(PROFILE, IMAGE)
    ok = harness.smoke(
        PROFILE,
        image,
        cols=100,
        rows=32,
        max_steps=1_000_000_000,
        timeout=args.timeout,
    )
    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
