#!/usr/bin/env python3
"""Focused qualification for the caller-owned AT Protocol DID document profile."""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path


LOCAL_TESTING = Path(__file__).resolve().parent
ROOT = LOCAL_TESTING.parent
SOURCE = ROOT / "akashic" / "atproto" / "did-document.f"
DOC = ROOT / "docs" / "atproto" / "did-document.md"

EXPECTED_DID = "did:plc:abc123"
KEY = "z123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz"
PASS_MARKER = "ATPROTO DID DOCUMENT PASS"
MAX_PHASE_STEPS = 180_000_000
LIFECYCLE_MAX_STEPS = 180_000_000
LOAD_STAGES = (
    (
        "memory-span",
        "utils/memory-span.f",
        "ATPROTO DIDDOC MEMORY SPAN READY",
        120_000_000,
    ),
    (
        "caller-span",
        "utils/caller-span.f",
        "ATPROTO DIDDOC CALLER SPAN READY",
        120_000_000,
    ),
    (
        "string",
        "utils/string.f",
        "ATPROTO DIDDOC STRING READY",
        120_000_000,
    ),
    (
        "json-object",
        "security/jose/json-object.f",
        "ATPROTO DIDDOC JSON OBJECT READY",
        180_000_000,
    ),
    (
        "http-target",
        "net/http-target.f",
        "ATPROTO DIDDOC HTTP TARGET READY",
        120_000_000,
    ),
    (
        "did",
        "atproto/did.f",
        "ATPROTO DIDDOC DID READY",
        120_000_000,
    ),
    (
        "handle",
        "atproto/handle.f",
        "ATPROTO DIDDOC HANDLE READY",
        120_000_000,
    ),
    (
        "did-document",
        "atproto/did-document.f",
        "ATPROTO DID DOCUMENT MODULE READY",
        180_000_000,
    ),
    (
        "fixture",
        "local_testing/at-diddoc-test.f",
        "ATPROTO DID DOCUMENT FIXTURE READY",
        120_000_000,
    ),
)


def _requires(path: Path) -> set[str]:
    return set(
        re.findall(
            r"(?mi)^[ \t]*REQUIRE[ \t]+(\S+)",
            path.read_text(encoding="utf-8"),
        )
    )


def _word_body(source: str, name: str) -> str:
    match = re.search(
        rf"(?ms)^:[ \t]+{re.escape(name)}\b(.*?)[ \t]+;",
        source,
    )
    assert match, f"missing Forth word {name}"
    return match.group(1)


def _assert_static_contracts() -> None:
    source = SOURCE.read_text(encoding="utf-8")
    doc = DOC.read_text(encoding="utf-8")

    assert 0 < LIFECYCLE_MAX_STEPS <= MAX_PHASE_STEPS
    assert LOAD_STAGES
    assert all(
        0 < stage_max_steps <= MAX_PHASE_STEPS
        for _, _, _, stage_max_steps in LOAD_STAGES
    )
    assert len({stage_name for stage_name, _, _, _ in LOAD_STAGES}) == len(
        LOAD_STAGES
    )
    assert len({stage_marker for _, _, stage_marker, _ in LOAD_STAGES}) == len(
        LOAD_STAGES
    )

    for marker in (
        "PROVIDED akashic-atproto-diddoc",
        "AT-DIDDOC-SIZE",
        "AT-DIDDOC-WORKSPACE-SIZE",
        "AT-DIDDOC-PARSE",
        "AT-DIDDOC-VALID?",
        "AT-DIDDOC-EVIDENCE@",
        "AT-DIDDOC-PARTICIPATION-STATUS",
        "AT-DIDDOC-DID@",
        "AT-DIDDOC-HANDLE@",
        "AT-DIDDOC-PUBLIC-KEY-MULTIBASE@",
        "AT-DIDDOC-PDS-TARGET@",
        "AT-DIDDOC-PDS-ORIGIN@",
        "AT-DIDDOC-S-KEY",
        "AT-DIDDOC-S-PDS",
        "AT-DIDDOC-E-MISSING",
    ):
        assert marker in source
    assert "AT-DIDDOC-S-HANDLE" not in source

    assert {
        "../utils/memory-span.f",
        "../utils/caller-span.f",
        "../security/jose/json-object.f",
        "../net/http-target.f",
        "did.f",
        "handle.f",
    }.issubset(_requires(SOURCE))

    assert not re.search(
        r"(?mi)^[ \t]*(VARIABLE|VALUE|DEFER|CREATE|GUARD)\b",
        source,
    ), "DID document parser owns mutable module state"
    assert "publicKeyJwk is not a modern Multikey value" in source
    assert "JOSE-JSON-OBJECT-PARSE" in source
    assert "AT-HANDLE-NORMALIZE" in source
    assert "HTARGET-PARSE" in source
    assert "_ATDD-ORIGIN-TARGET?" in source
    assert "_ATDD-FRAGMENT-ID?" in source

    parse = _word_body(source, "AT-DIDDOC-PARSE")
    assert "_ATDD-PARSE-GEOMETRY" in parse
    assert "_ATDD-PARSE-CALL" in parse
    publish = _word_body(source, "_ATDD-PUBLISH")
    assert publish.index("0 OVER _ATDDW.OUTPUT @ _ATDD.MAGIC !") < publish.index(
        "MOVE"
    )
    assert publish.rindex("_ATDD-MAGIC-VALUE") > publish.index("MOVE")
    parse_call = _word_body(source, "_ATDD-PARSE-CALL")
    assert "_ATDD-WIPE" in parse_call
    assert "_ATDD-PUBLISH" in parse_call
    assert "_ATDD-CALL-FINALLY" in parse_call

    for line_number, line in enumerate(source.splitlines(), start=1):
        forth_code = line.split("\\", 1)[0]
        if "(" in forth_code:
            assert ")" in forth_code.split("(", 1)[1], (
                "KDOS parenthesized comments must close on their physical "
                f"line: {SOURCE}:{line_number}"
            )

    for phrase in (
        "first valid",
        "relative or fully qualified",
        "AT-DIDDOC-E-MISSING",
        "independently",
        "participation",
        "publicKeyJwk",
        "no path, query, or fragment",
    ):
        assert phrase in doc


def _builder_word(name: str, value: str) -> str:
    lines = [f": {name}  ( -- )", "    _DDT-RESET"]
    parts = value.split('"')
    for index, part in enumerate(parts):
        for start in range(0, len(part), 72):
            chunk = part[start : start + 72]
            if chunk:
                lines.append(f'    S" {chunk}" _DDT-TEXT')
        if index != len(parts) - 1:
            lines.append("    34 _DDT-CHAR")
    lines.append(";")
    return "\n".join(lines)


def _compact(value: object) -> str:
    return json.dumps(value, separators=(",", ":"), ensure_ascii=True)


def _fixture_source() -> str:
    valid = {
        "id": EXPECTED_DID,
        "alsoKnownAs": [
            "https://example.invalid/alice",
            "at://bad_handle.test",
            "at://Alice.Example",
            "at://Later.Example",
        ],
        "verificationMethod": [
            {
                "id": "#atproto",
                "type": "EcdsaVerificationKey2019",
                "controller": EXPECTED_DID,
                "publicKeyJwk": {"kty": "EC"},
            },
            {
                "id": "#atproto",
                "type": "Multikey",
                "controller": EXPECTED_DID,
                "publicKeyMultibase": "z0notbase58",
            },
            {
                "id": f"{EXPECTED_DID}#atproto",
                "type": "Multikey",
                "controller": EXPECTED_DID,
                "publicKeyMultibase": KEY,
                "unknown": {"nested": [True, None, {"x": 1}]},
            },
            {
                "id": "#atproto",
                "type": "Multikey",
                "controller": EXPECTED_DID,
                "publicKeyMultibase": "z2222222222222222",
            },
        ],
        "service": [
            {
                "id": "#atproto_pds",
                "type": "AtprotoPersonalDataServer",
                "serviceEndpoint": "https://wrong.example/path",
            },
            {
                "id": f"{EXPECTED_DID}#atproto_pds",
                "type": "AtprotoPersonalDataServer",
                "serviceEndpoint": "HTTPS://PDS.Example:443",
            },
            {
                "id": "#atproto_pds",
                "type": "AtprotoPersonalDataServer",
                "serviceEndpoint": "https://later.example",
            },
        ],
        "unknownTop": {"strict": [{"value": False}]},
    }
    missing_handle = {
        "id": EXPECTED_DID,
        "verificationMethod": [
            {
                "id": "#atproto",
                "type": "Multikey",
                "controller": EXPECTED_DID,
                "publicKeyMultibase": KEY,
            }
        ],
        "service": [
            {
                "id": "#atproto_pds",
                "type": "AtprotoPersonalDataServer",
                "serviceEndpoint": "https://pds.example",
            }
        ],
    }
    bad_id = dict(missing_handle)
    bad_id["id"] = "did:plc:someone-else"
    missing_key = {
        "id": EXPECTED_DID,
        "verificationMethod": [
            {
                "id": "#atproto",
                "type": "Multikey",
                "controller": "did:plc:someone-else",
                "publicKeyMultibase": KEY,
            }
        ],
        "service": missing_handle["service"],
    }
    missing_pds = {
        "id": EXPECTED_DID,
        "verificationMethod": missing_handle["verificationMethod"],
        "service": [
            {
                "id": "#atproto_pds",
                "type": "AtprotoPersonalDataServer",
                "serviceEndpoint": "https://pds.example/x",
            }
        ],
    }
    identity_only = {"id": EXPECTED_DID}
    bad_handle_shape = dict(missing_handle)
    bad_handle_shape["alsoKnownAs"] = "at://alice.example"
    duplicate_unknown = (
        '{"id":"did:plc:abc123","verificationMethod":[],"service":[],'
        '"unknown":{"x":1,"x":2}}'
    )

    builders = "\n\n".join(
        (
            _builder_word("_DDT-BUILD-VALID", _compact(valid)),
            _builder_word(
                "_DDT-BUILD-MISSING-HANDLE", _compact(missing_handle)
            ),
            _builder_word("_DDT-BUILD-BAD-ID", _compact(bad_id)),
            _builder_word("_DDT-BUILD-MISSING-KEY", _compact(missing_key)),
            _builder_word("_DDT-BUILD-MISSING-PDS", _compact(missing_pds)),
            _builder_word("_DDT-BUILD-IDENTITY-ONLY", _compact(identity_only)),
            _builder_word(
                "_DDT-BUILD-BAD-HANDLE-SHAPE", _compact(bad_handle_shape)
            ),
            _builder_word("_DDT-BUILD-DUPLICATE", duplicate_unknown),
        )
    )

    return (
        r"""
\ Focused AT Protocol DID document contracts.
PROVIDED atproto-diddoc-test

VARIABLE _DDT-FAILS
VARIABLE _DDT-CHECKS
VARIABLE _DDT-DEPTH
VARIABLE _DDT-JSON-U
VARIABLE _DDT-COPY-U

CREATE _DDT-JSON 8192 ALLOT
CREATE _DDT-RESULT AT-DIDDOC-SIZE ALLOT
CREATE _DDT-PRIOR AT-DIDDOC-SIZE ALLOT
CREATE _DDT-WORK AT-DIDDOC-WORKSPACE-SIZE ALLOT

: _DDT-ASSERT  ( flag -- )
    1 _DDT-CHECKS +!
    0= IF
        1 _DDT-FAILS +!
        ." ATPROTO DID DOCUMENT ASSERT " _DDT-CHECKS @ . CR
    THEN ;

: _DDT-STACK  ( -- )
    DEPTH DUP _DDT-DEPTH @ <> IF
        ." ATPROTO DID DOCUMENT STACK "
        _DDT-DEPTH @ . ." -> " DUP . CR .S CR
    THEN
    _DDT-DEPTH @ = _DDT-ASSERT ;

: _DDT-RESET  ( -- ) 0 _DDT-JSON-U ! ;

: _DDT-CHAR  ( byte -- )
    _DDT-JSON _DDT-JSON-U @ + C!
    1 _DDT-JSON-U +! ;

: _DDT-TEXT  ( address length -- )
    DUP _DDT-COPY-U !
    _DDT-JSON _DDT-JSON-U @ + SWAP MOVE
    _DDT-COPY-U @ _DDT-JSON-U +! ;

: _DDT-FILLED?  ( address length byte -- flag )
    >R
    BEGIN DUP WHILE
        OVER C@ R@ <> IF
            2DROP R> DROP 0 EXIT
        THEN
        1- SWAP 1+ SWAP
    REPEAT
    2DROP R> DROP -1 ;

: _DDT-PARSE  ( -- status )
    _DDT-JSON _DDT-JSON-U @
    S" did:plc:abc123"
    _DDT-RESULT _DDT-WORK
    AT-DIDDOC-PARSE ;
"""
        + builders
        + r"""

: _DDT-EXPECT-FAILURE  ( expected-status -- )
    >R
    _DDT-RESULT AT-DIDDOC-SIZE 0xA5 FILL
    _DDT-PARSE R> = _DDT-ASSERT
    _DDT-RESULT AT-DIDDOC-SIZE 0xA5
        _DDT-FILLED? _DDT-ASSERT
    _DDT-WORK AT-DIDDOC-WORKSPACE-SIZE 0
        _DDT-FILLED? _DDT-ASSERT ;

: _DDT-VALID  ( -- )
    _DDT-BUILD-VALID
    _DDT-PARSE AT-DIDDOC-S-OK = _DDT-ASSERT
    _DDT-RESULT AT-DIDDOC-VALID? _DDT-ASSERT

    _DDT-RESULT AT-DIDDOC-EVIDENCE@
    AT-DIDDOC-S-OK = _DDT-ASSERT
    AT-DIDDOC-E-VALID = _DDT-ASSERT
    AT-DIDDOC-E-VALID = _DDT-ASSERT
    AT-DIDDOC-E-VALID = _DDT-ASSERT
    AT-DIDDOC-E-VALID = _DDT-ASSERT

    _DDT-RESULT AT-DIDDOC-DID@
    DUP AT-DIDDOC-S-OK = _DDT-ASSERT DROP
    S" did:plc:abc123" COMPARE 0= _DDT-ASSERT

    _DDT-RESULT AT-DIDDOC-HANDLE@
    DUP AT-DIDDOC-S-OK = _DDT-ASSERT DROP
    S" alice.example" COMPARE 0= _DDT-ASSERT
    _DDT-RESULT _ATDD.HANDLE 13 +
    256 13 - 0 _DDT-FILLED? _DDT-ASSERT

    _DDT-RESULT AT-DIDDOC-PUBLIC-KEY-MULTIBASE@
    DUP AT-DIDDOC-S-OK = _DDT-ASSERT DROP
    S" z123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz"
        COMPARE 0= _DDT-ASSERT
    _DDT-RESULT _ATDD.KEY
    _DDT-RESULT _ATDD.KEY-U @ +
    AT-DIDDOC-KEY-CAPACITY
    _DDT-RESULT _ATDD.KEY-U @ - 0 _DDT-FILLED? _DDT-ASSERT

    _DDT-RESULT AT-DIDDOC-PDS-ORIGIN@
    DUP AT-DIDDOC-S-OK = _DDT-ASSERT DROP
    S" https://pds.example/" COMPARE 0= _DDT-ASSERT
    _DDT-RESULT AT-DIDDOC-PARTICIPATION-STATUS
    AT-DIDDOC-S-OK = _DDT-ASSERT
    _DDT-WORK AT-DIDDOC-WORKSPACE-SIZE 0
        _DDT-FILLED? _DDT-ASSERT
    _DDT-STACK ;

: _DDT-OPTIONAL-HANDLE  ( -- )
    _DDT-BUILD-MISSING-HANDLE
    _DDT-PARSE AT-DIDDOC-S-OK = _DDT-ASSERT
    _DDT-RESULT AT-DIDDOC-EVIDENCE@
    AT-DIDDOC-S-OK = _DDT-ASSERT
    AT-DIDDOC-E-VALID = _DDT-ASSERT
    AT-DIDDOC-E-VALID = _DDT-ASSERT
    AT-DIDDOC-E-MISSING = _DDT-ASSERT
    AT-DIDDOC-E-VALID = _DDT-ASSERT
    _DDT-RESULT AT-DIDDOC-HANDLE@
    DUP AT-DIDDOC-S-MISSING = _DDT-ASSERT
    DROP 2DROP
    _DDT-RESULT AT-DIDDOC-PARTICIPATION-STATUS
    AT-DIDDOC-S-OK = _DDT-ASSERT
    _DDT-STACK ;

: _DDT-OPTIONAL-PARTICIPATION  ( -- )
    _DDT-BUILD-MISSING-KEY
    _DDT-PARSE AT-DIDDOC-S-OK = _DDT-ASSERT
    _DDT-RESULT AT-DIDDOC-VALID? _DDT-ASSERT
    _DDT-RESULT AT-DIDDOC-EVIDENCE@
    AT-DIDDOC-S-OK = _DDT-ASSERT
    AT-DIDDOC-E-VALID = _DDT-ASSERT
    AT-DIDDOC-E-MISSING = _DDT-ASSERT
    AT-DIDDOC-E-MISSING = _DDT-ASSERT
    AT-DIDDOC-E-VALID = _DDT-ASSERT
    _DDT-RESULT AT-DIDDOC-PUBLIC-KEY-MULTIBASE@
    DUP AT-DIDDOC-S-MISSING = _DDT-ASSERT
    DROP 2DROP
    _DDT-RESULT AT-DIDDOC-PDS-TARGET@
    AT-DIDDOC-S-OK = _DDT-ASSERT DROP
    _DDT-RESULT AT-DIDDOC-PARTICIPATION-STATUS
    AT-DIDDOC-S-KEY = _DDT-ASSERT
    _DDT-RESULT _ATDD.KEY AT-DIDDOC-KEY-CAPACITY 0
        _DDT-FILLED? _DDT-ASSERT
    _DDT-RESULT _ATDD.HANDLE 256 0
        _DDT-FILLED? _DDT-ASSERT

    _DDT-BUILD-MISSING-PDS
    _DDT-PARSE AT-DIDDOC-S-OK = _DDT-ASSERT
    _DDT-RESULT AT-DIDDOC-VALID? _DDT-ASSERT
    _DDT-RESULT AT-DIDDOC-EVIDENCE@
    AT-DIDDOC-S-OK = _DDT-ASSERT
    AT-DIDDOC-E-MISSING = _DDT-ASSERT
    AT-DIDDOC-E-VALID = _DDT-ASSERT
    AT-DIDDOC-E-MISSING = _DDT-ASSERT
    AT-DIDDOC-E-VALID = _DDT-ASSERT
    _DDT-RESULT AT-DIDDOC-PDS-ORIGIN@
    DUP AT-DIDDOC-S-MISSING = _DDT-ASSERT
    DROP 2DROP
    _DDT-RESULT AT-DIDDOC-PUBLIC-KEY-MULTIBASE@
    DUP AT-DIDDOC-S-OK = _DDT-ASSERT DROP
    2DROP
    _DDT-RESULT AT-DIDDOC-PARTICIPATION-STATUS
    AT-DIDDOC-S-PDS = _DDT-ASSERT
    _DDT-RESULT _ATDD.TARGET HTARGET-SIZE 0
        _DDT-FILLED? _DDT-ASSERT

    _DDT-BUILD-BAD-HANDLE-SHAPE
    _DDT-PARSE AT-DIDDOC-S-OK = _DDT-ASSERT
    _DDT-RESULT AT-DIDDOC-EVIDENCE@
    AT-DIDDOC-S-OK = _DDT-ASSERT
    AT-DIDDOC-E-VALID = _DDT-ASSERT
    AT-DIDDOC-E-VALID = _DDT-ASSERT
    AT-DIDDOC-E-MISSING = _DDT-ASSERT
    AT-DIDDOC-E-VALID = _DDT-ASSERT
    _DDT-RESULT AT-DIDDOC-PARTICIPATION-STATUS
    AT-DIDDOC-S-OK = _DDT-ASSERT
    _DDT-STACK ;

: _DDT-IDENTITY-ONLY  ( -- )
    _DDT-BUILD-IDENTITY-ONLY
    _DDT-PARSE AT-DIDDOC-S-OK = _DDT-ASSERT
    _DDT-RESULT AT-DIDDOC-VALID? _DDT-ASSERT
    _DDT-RESULT AT-DIDDOC-EVIDENCE@
    AT-DIDDOC-S-OK = _DDT-ASSERT
    AT-DIDDOC-E-MISSING = _DDT-ASSERT
    AT-DIDDOC-E-MISSING = _DDT-ASSERT
    AT-DIDDOC-E-MISSING = _DDT-ASSERT
    AT-DIDDOC-E-VALID = _DDT-ASSERT
    _DDT-RESULT AT-DIDDOC-PUBLIC-KEY-MULTIBASE@
    DUP AT-DIDDOC-S-MISSING = _DDT-ASSERT
    DROP 2DROP
    _DDT-RESULT AT-DIDDOC-PDS-TARGET@
    DUP AT-DIDDOC-S-MISSING = _DDT-ASSERT
    2DROP
    _DDT-RESULT AT-DIDDOC-PARTICIPATION-STATUS
    AT-DIDDOC-S-KEY = _DDT-ASSERT
    _DDT-RESULT _ATDD.KEY AT-DIDDOC-KEY-CAPACITY 0
        _DDT-FILLED? _DDT-ASSERT
    _DDT-RESULT _ATDD.HANDLE 256 0
        _DDT-FILLED? _DDT-ASSERT
    _DDT-RESULT _ATDD.TARGET HTARGET-SIZE 0
        _DDT-FILLED? _DDT-ASSERT
    _DDT-STACK ;

: _DDT-STRICT-FAILURES  ( -- )
    _DDT-BUILD-BAD-ID
    AT-DIDDOC-S-ID _DDT-EXPECT-FAILURE
    _DDT-BUILD-DUPLICATE
    AT-DIDDOC-S-JSON _DDT-EXPECT-FAILURE
    _DDT-STACK ;

: _DDT-PRIOR-ATOMICITY  ( -- )
    _DDT-BUILD-VALID
    _DDT-PARSE AT-DIDDOC-S-OK = _DDT-ASSERT
    _DDT-RESULT _DDT-PRIOR AT-DIDDOC-SIZE MOVE
    _DDT-BUILD-BAD-ID
    _DDT-PARSE AT-DIDDOC-S-ID = _DDT-ASSERT
    _DDT-RESULT AT-DIDDOC-SIZE
    _DDT-PRIOR AT-DIDDOC-SIZE
    COMPARE 0= _DDT-ASSERT
    _DDT-WORK AT-DIDDOC-WORKSPACE-SIZE 0
        _DDT-FILLED? _DDT-ASSERT
    _DDT-STACK ;

: _DDT-CORRUPTION  ( -- )
    _DDT-BUILD-MISSING-KEY
    _DDT-PARSE AT-DIDDOC-S-OK = _DDT-ASSERT
    1 _DDT-RESULT _ATDD.KEY-U !
    _DDT-RESULT AT-DIDDOC-VALID? 0= _DDT-ASSERT
    _DDT-RESULT AT-DIDDOC-PARTICIPATION-STATUS
    AT-DIDDOC-S-INVALID = _DDT-ASSERT

    _DDT-BUILD-VALID
    _DDT-PARSE AT-DIDDOC-S-OK = _DDT-ASSERT
    0 _DDT-RESULT _ATDD.TARGET !
    _DDT-RESULT AT-DIDDOC-VALID? 0= _DDT-ASSERT
    _DDT-RESULT AT-DIDDOC-PARTICIPATION-STATUS
    AT-DIDDOC-S-INVALID = _DDT-ASSERT
    _DDT-STACK ;

: _DDT-GEOMETRY  ( -- )
    _DDT-BUILD-VALID
    _DDT-WORK AT-DIDDOC-WORKSPACE-SIZE 0x5A FILL
    _DDT-JSON _DDT-JSON-U @
    S" did:plc:abc123"
    _DDT-WORK _DDT-WORK
    AT-DIDDOC-PARSE AT-DIDDOC-S-ALIAS = _DDT-ASSERT
    _DDT-WORK AT-DIDDOC-WORKSPACE-SIZE 0x5A
        _DDT-FILLED? _DDT-ASSERT
    _DDT-STACK ;

: _DDT-RUN  ( -- )
    0 _DDT-FAILS !
    0 _DDT-CHECKS !
    DEPTH _DDT-DEPTH !
    _DDT-VALID
    _DDT-OPTIONAL-HANDLE
    _DDT-OPTIONAL-PARTICIPATION
    _DDT-IDENTITY-ONLY
    _DDT-STRICT-FAILURES
    _DDT-PRIOR-ATOMICITY
    _DDT-CORRUPTION
    _DDT-GEOMETRY
    _DDT-FAILS @ 0= IF
        ." ATPROTO DID DOCUMENT PASS " _DDT-CHECKS @ . CR
    ELSE
        ." ATPROTO DID DOCUMENT FAIL " _DDT-FAILS @ .
        ." / " _DDT-CHECKS @ . CR
    THEN ;
"""
    )


def _run_lifecycle(timeout: float) -> int:
    sys.path.insert(0, str(LOCAL_TESTING))
    import akashic_tui as harness

    fixture = harness._minify_forth(_fixture_source()).encode("utf-8")
    autoexec_parts = [
        "\\ autoexec.f - AT Protocol DID document profile\n",
        "ENTER-USERLAND\n",
    ]
    for stage_name, module, stage_marker, _ in LOAD_STAGES:
        autoexec_parts.extend(
            (
                f"REQUIRE {module}\n",
                "DEPTH IF\n",
                (
                    '  ." ATPROTO DID DOCUMENT LOAD STACK FAIL '
                    f'{stage_name}" CR TX-FLUSH\n'
                ),
                "THEN\n",
                f'." {stage_marker}" CR TX-FLUSH\n',
                "KEY DROP\n",
            )
        )
    autoexec_parts.append("_DDT-RUN\n")
    autoexec = "".join(autoexec_parts)

    profile_name = "atproto-did-document"
    image = Path("/tmp/akashic-atproto-did-document.img")
    harness.PROFILES[profile_name] = harness.Profile(
        roots=("atproto/did-document.f",),
        resources=(),
        autoexec=autoexec,
        ready_markers=(PASS_MARKER,),
        stable_markers=(PASS_MARKER,),
        failure_markers=(
            "ATPROTO DID DOCUMENT FAIL",
            "ATPROTO DID DOCUMENT ASSERT",
            "ATPROTO DID DOCUMENT STACK",
            "ATPROTO DID DOCUMENT LOAD STACK FAIL",
            "DRIVER THROW",
            "dictionary full",
            "exception",
            "Module not found",
            "Path component not found",
            "? (not found)",
        ),
        initial_files=(
            ("local_testing/at-diddoc-test.f", fixture),
        ),
        linked=False,
        include_large_sample=False,
        total_sectors=2048,
    )
    image_path = harness.build_image(profile_name, image)
    profile = harness.PROFILES[profile_name]

    def failures(machine: object) -> tuple[str, ...]:
        raw = machine.raw_text()
        screen = machine.screen_text()
        found = list(harness._has_forth_error(raw))
        found.extend(
            harness._matched_failure_markers(profile, raw, screen)
        )
        return tuple(dict.fromkeys(found))

    with harness.MachineSession.from_bios(
        harness.MEGAPAD_ROOT / "bios.asm",
        storage_image=image_path,
        cols=120,
        rows=44,
        batch_steps=500_000,
        ext_mem_size=64 << 20,
        num_cores=1,
    ) as machine:
        machine.boot()
        reports = []
        output = []
        for index, (
            stage_name,
            _,
            stage_marker,
            stage_max_steps,
        ) in enumerate(LOAD_STAGES):
            if index:
                machine.clear_output()
                machine.send_text("x")
            report = machine.run(
                max_steps=stage_max_steps,
                wall_timeout_s=timeout,
                until_text=stage_marker,
                text_scope="raw",
            )
            raw = machine.raw_text()
            stage_failures = failures(machine)
            reports.append((stage_name, report))
            output.extend((f"\n--- load {stage_name} ---\n", raw))
            if stage_marker not in raw or stage_failures:
                print(
                    "Staged atproto-did-document: FAIL\n"
                    f"  {stage_name}: {report.steps:,} steps in "
                    f"{report.elapsed_s:.2f}s; stop={report.reason}"
                )
                for failure in stage_failures:
                    print(f"  {stage_name} failure: {failure}")
                print(f"  recent guest output:\n{raw[-4000:]}")
                return 1

        machine.clear_output()
        machine.send_text("x")
        lifecycle = machine.run(
            max_steps=LIFECYCLE_MAX_STEPS,
            wall_timeout_s=timeout,
            until_text=PASS_MARKER,
            text_scope="raw",
        )
        raw = machine.raw_text()
        lifecycle_failures = failures(machine)
        output.extend(("\n--- lifecycle ---\n", raw))
        ok = PASS_MARKER in raw and not lifecycle_failures
        root = harness.OUTPUT_ROOT / f"smoke-{profile_name}"
        root.with_suffix(".raw.txt").write_text(
            "".join(output),
            encoding="utf-8",
        )
        print(f"Staged atproto-did-document: {'PASS' if ok else 'FAIL'}")
        for stage_name, report in reports:
            print(
                f"  {stage_name}: {report.steps:,} steps in "
                f"{report.elapsed_s:.2f}s; stop={report.reason}"
            )
        print(
            f"  lifecycle: {lifecycle.steps:,} steps in "
            f"{lifecycle.elapsed_s:.2f}s; stop={lifecycle.reason}"
        )
        if not ok:
            for failure in lifecycle_failures:
                print(f"  lifecycle failure: {failure}")
            print(f"  recent guest output:\n{raw[-4000:]}")
            return 1
    return 0


def main() -> int:
    parser = argparse.ArgumentParser()
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--static-only", action="store_true")
    mode.add_argument("--lifecycle", action="store_true")
    parser.add_argument("--timeout", type=float, default=180.0)
    args = parser.parse_args()

    _assert_static_contracts()
    if args.static_only:
        print("ATPROTO DID DOCUMENT STATIC PASS")
        return 0
    return _run_lifecycle(args.timeout)


if __name__ == "__main__":
    raise SystemExit(main())
