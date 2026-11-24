"""Contracts of the machine TLS trust registry, net/tls-trust-registry.f.

Each contract registers a profile of its own, builds its image in pytest's
temporary folder and boots it on the emulator: one composition that checks
registration, scoped anchors, the refusals of the pinned root set's import,
the freeze and its repeat, and one boot for each way an emitter can fail the
composition.  The root set's successful import, read from a file through a
place, is test_web_roots.py's.
"""

from __future__ import annotations

import base64
import sys
from pathlib import Path

import pytest

LOCAL_TESTING = Path(__file__).resolve().parent
sys.path.insert(0, str(LOCAL_TESTING))

import akashic_tui as harness  # noqa: E402
from contract_script import run_profile_smoke  # noqa: E402

PASS = "TRUST REGISTRY PASS"
FAILS = ("TRUST REGISTRY FAIL", "(not found)", "exception")


def _root_der() -> bytes:
    """A CA certificate: MegaPad's deterministic P-256 test root."""
    path = harness.MEGAPAD_ROOT / "tests" / "fixtures" / "tls" / "root.der.b64"
    return base64.b64decode(path.read_bytes())


def _bytes_forth(name: str, data: bytes) -> str:
    rows = [f"CREATE {name}"]
    for offset in range(0, len(data), 16):
        rows.append(" ".join(f"{b} C," for b in data[offset:offset + 16]))
    rows.append(f"{len(data)} CONSTANT {name}-u")
    return "\n".join(rows) + "\n"


HARNESS = r"""
VARIABLE _rc-fails
VARIABLE _rc-checks
VARIABLE _rc-depth
VARIABLE _rc-builder
VARIABLE _rc-generation
: _rc-assert  ( flag -- )
    1 _rc-checks +!
    0= IF 1 _rc-fails +! ." ASSERT " _rc-checks @ . CR THEN ;
: _rc-stack  ( -- )
    DEPTH _rc-depth @ <> IF ." STACK " .S CR THEN
    DEPTH _rc-depth @ = _rc-assert ;
: _rc-report  ( -- )
    _rc-fails @ 0= IF
        ." TRUST REGISTRY PASS " _rc-checks @ .
    ELSE
        ." TRUST REGISTRY FAIL " _rc-fails @ . ."  / " _rc-checks @ .
    THEN CR ;
"""

COMPOSITION = HARNESS + r"""
CREATE _rc-id 32 ALLOT
: _rc-id$  ( n -- a u )
    S" org.akashic.testing.c" _rc-id SWAP CMOVE
    DUP 10 / 48 + _rc-id 21 + C!  10 MOD 48 + _rc-id 22 + C!
    _rc-id 23 ;

: _rc-empty-emit  ( builder context -- status )  2DROP MTRUST-S-OK ;

: _rc-scoped-emit  ( builder context -- status )
    DROP _rc-builder !
    _rc-root 127 S" short.example" 0 _rc-builder @
        MTRUST-ANCHOR+ MTRUST-S-INVALID = _rc-assert
    _rc-root _rc-root-u S" bad..example" 0 _rc-builder @
        MTRUST-ANCHOR+ MTRUST-S-INVALID = _rc-assert
    _rc-root _rc-root-u S" flags.example" 2 _rc-builder @
        MTRUST-ANCHOR+ MTRUST-S-INVALID = _rc-assert
    \ A scoped anchor needs its scope; global anchors come only from the
    \ pinned root set.
    _rc-root _rc-root-u 0 0 0 _rc-builder @
        MTRUST-ANCHOR+ MTRUST-S-INVALID = _rc-assert
    _rc-root _rc-root-u S" private.example" 0 0
        MTRUST-ANCHOR+ MTRUST-S-INVALID = _rc-assert
    _rc-root _rc-root-u S" private.example" 0 _rc-builder @
        MTRUST-ANCHOR+ MTRUST-S-OK = _rc-assert
    _rc-root _rc-root-u S" PRIVATE.example" 0 _rc-builder @
        MTRUST-ANCHOR+ MTRUST-S-CONFLICT = _rc-assert
    _rc-root _rc-root-u S" corp.example" TTAF-SUBDOMAINS _rc-builder @
        MTRUST-ANCHOR+ MTRUST-S-OK = _rc-assert
    \ The root set's import takes only the pinned bundle.
    _rc-root _rc-root-u _rc-builder @
        MTRUST-WEB-ROOTS+ MTRUST-S-INVALID = _rc-assert
    WEB-ROOTS-BYTES ALLOCATE 0= _rc-assert
    DUP WEB-ROOTS-BYTES 0 FILL
    DUP WEB-ROOTS-BYTES _rc-builder @
        MTRUST-WEB-ROOTS+ MTRUST-S-INVALID = _rc-assert
    FREE
    MTRUST-S-OK ;

: _RC-RUN  ( -- )
    0 _rc-fails ! 0 _rc-checks ! DEPTH _rc-depth !
    TLS-TRUST-RESET
    MTRUST-STATE@ MTRUST-STATE-OPEN = _rc-assert
    \ Registration: bounds, idempotence, conflict, and more contributors
    \ than any fixed table held.
    0 0 ['] _rc-empty-emit 0 MTRUST-REGISTER MTRUST-S-INVALID = _rc-assert
    S" org.akashic.testing.scoped" 0 0 MTRUST-REGISTER
        MTRUST-S-INVALID = _rc-assert
    S" org.akashic.testing.scoped" ['] _rc-scoped-emit 0 MTRUST-REGISTER
        MTRUST-S-OK = _rc-assert
    S" org.akashic.testing.scoped" ['] _rc-scoped-emit 0 MTRUST-REGISTER
        MTRUST-S-OK = _rc-assert
    S" org.akashic.testing.scoped" ['] _rc-empty-emit 0 MTRUST-REGISTER
        MTRUST-S-CONFLICT = _rc-assert
    20 0 DO
        I _rc-id$ ['] _rc-empty-emit I MTRUST-REGISTER
            MTRUST-S-OK = _rc-assert
    LOOP
    _rc-stack
    \ The freeze composes once and loads KDOS.
    TLS-TRUST-COUNT @ 0= _rc-assert
    MTRUST-FREEZE MTRUST-S-OK = _rc-assert
    MTRUST-FROZEN? _rc-assert
    MTRUST-COUNT@ 2 = _rc-assert
    TLS-TRUST-COUNT @ 2 = _rc-assert
    TLS-TRUST-VERSION @ TLS-TRUST-FORMAT = _rc-assert
    MTRUST-GENERATION@ DUP _rc-generation ! 0<> _rc-assert
    TLS-TRUST-GENERATION @ _rc-generation @ = _rc-assert
    S" private.example" 0 TLS-TRUST@ _TLS-SCOPE-MATCH? _rc-assert
    S" a.private.example" 0 TLS-TRUST@ _TLS-SCOPE-MATCH? 0= _rc-assert
    S" a.corp.example" 1 TLS-TRUST@ _TLS-SCOPE-MATCH? _rc-assert
    S" corp.example.evil" 1 TLS-TRUST@ _TLS-SCOPE-MATCH? 0= _rc-assert
    \ Frozen is one-way: a repeat only checks KDOS.
    MTRUST-FREEZE MTRUST-S-OK = _rc-assert
    S" org.akashic.testing.late" ['] _rc-empty-emit 0 MTRUST-REGISTER
        MTRUST-S-FROZEN = _rc-assert
    _rc-root _rc-root-u S" late.example" 0 _rc-builder @
        MTRUST-ANCHOR+ MTRUST-S-INVALID = _rc-assert
    _rc-generation @ 1+ TLS-TRUST-GENERATION !
    MTRUST-FREEZE MTRUST-S-DIVERGED = _rc-assert
    _rc-generation @ TLS-TRUST-GENERATION !
    MTRUST-FREEZE MTRUST-S-OK = _rc-assert
    _rc-stack
    _rc-report ;
"""

# One emitter that fails the composition, and what the registry reports.
FAILURES = {
    "status": (
        ": _rc-bad-emit  ( builder context -- status )  2DROP 77 ;",
        "MTRUST-S-CONTRIBUTOR = _rc-assert  MTRUST-LAST-DETAIL@ 77 = _rc-assert",
    ),
    "throw": (
        ": _rc-bad-emit  ( builder context -- status )  2DROP -777 THROW ;",
        "MTRUST-S-CONTRIBUTOR = _rc-assert  "
        "MTRUST-LAST-DETAIL@ -777 = _rc-assert",
    ),
    "stack": (
        ": _rc-bad-emit  ( builder context -- extra status )"
        "  2DROP 123 MTRUST-S-OK ;",
        "MTRUST-S-CONTRIBUTOR = _rc-assert  "
        "MTRUST-LAST-DETAIL@ MTRUST-D-EMITTER-STACK = _rc-assert",
    ),
    "builder": (
        ": _rc-bad-emit  ( builder context -- status )"
        "  DROP _MTB.COUNT 99999 SWAP ! MTRUST-S-OK ;",
        "MTRUST-S-CONTRIBUTOR = _rc-assert  "
        "MTRUST-LAST-DETAIL@ MTRUST-D-EMITTER-BUILDER = _rc-assert",
    ),
}


def _failure_contract(emitter: str, expectation: str) -> str:
    return HARNESS + emitter + r"""
: _RC-RUN  ( -- )
    0 _rc-fails ! 0 _rc-checks ! DEPTH _rc-depth !
    TLS-TRUST-RESET
    S" org.akashic.testing.bad" ['] _rc-bad-emit 0 MTRUST-REGISTER
        MTRUST-S-OK = _rc-assert
    MTRUST-FREEZE """ + expectation + r"""
    MTRUST-STATE@ MTRUST-STATE-FAILED = _rc-assert
    TLS-TRUST-COUNT @ 0= _rc-assert
    MTRUST-COUNT@ 0= _rc-assert
    S" org.akashic.testing.after" ['] _rc-bad-emit 0 MTRUST-REGISTER
        MTRUST-S-STATE = _rc-assert
    MTRUST-FREEZE MTRUST-S-STATE = _rc-assert
    _rc-stack
    _rc-report ;
"""


def _register(name: str, contract: str) -> str:
    profile = f"trust-registry-{name}"
    harness.PROFILES[profile] = harness.Profile(
        roots=("net/tls-trust-registry.f",),
        resources=(),
        autoexec=(
            "\\ autoexec.f - machine TLS trust registry contracts\n"
            "ENTER-USERLAND\n"
            "REQUIRE net/tls-trust-registry.f\n"
            "REQUIRE local_testing/trust-registry-test.f\n"
            "_RC-RUN\n"
        ),
        ready_markers=(PASS,),
        stable_markers=(PASS,),
        failure_markers=FAILS,
        initial_files=(
            ("local_testing/trust-registry-test.f",
             (_bytes_forth("_rc-root", _root_der()) + contract).encode()),
        ),
        include_large_sample=False,
    )
    return profile


def test_composition(tmp_path: Path, monkeypatch) -> None:
    run_profile_smoke(_register("composition", COMPOSITION),
                      tmp_path, monkeypatch)


@pytest.mark.parametrize("failure", sorted(FAILURES))
def test_failed_emitter_fails_the_composition(
        failure: str, tmp_path: Path, monkeypatch) -> None:
    emitter, expectation = FAILURES[failure]
    run_profile_smoke(
        _register(failure, _failure_contract(emitter, expectation)),
        tmp_path, monkeypatch)
