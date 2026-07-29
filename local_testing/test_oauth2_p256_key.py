#!/usr/bin/env python3
"""Static and staged qualification for the durable OAuth P-256 key owner."""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path


LOCAL_TESTING = Path(__file__).resolve().parent
ROOT = LOCAL_TESTING.parent
sys.path.insert(0, str(LOCAL_TESTING))

import akashic_tui as harness  # noqa: E402


SOURCE = ROOT / "akashic" / "security" / "oauth2" / "key-p256.f"
VAULT = ROOT / "akashic" / "security" / "credential-vault.f"
DEPS = LOCAL_TESTING / "cv-deps.f"
FIXTURE = LOCAL_TESTING / "oauth2-p256-key-test.f"

PROFILE = "oauth2-p256-key-owner"
IMAGE = Path("/tmp/akashic-oauth2-p256-key-owner.img")
PASS_MARKER = "OAUTH2 P256 KEY PASS"
MAX_PHASE_STEPS = 180_000_000
FINISH_STEPS = 20_000_000

LOAD_STAGES = (
    ("dependencies", "OAUTH2 P256 KEY DEPS READY"),
    ("vault", "OAUTH2 P256 KEY VAULT READY"),
    ("source", "OAUTH2 P256 KEY SOURCE READY"),
    ("fixture", "OAUTH2 P256 KEY FIXTURE READY"),
)

GROUP_STAGES = (
    ("binding", "_O2PKT-TEST-BINDING", "OAUTH2 P256 KEY BINDING READY"),
    ("client", "_O2PKT-TEST-CLIENT", "OAUTH2 P256 KEY CLIENT READY"),
    ("failures", "_O2PKT-TEST-FAILURES", "OAUTH2 P256 KEY NEGATIVE READY"),
    (
        "callbacks",
        "_O2PKT-TEST-CALLBACKS",
        "OAUTH2 P256 KEY CALLBACKS READY",
    ),
    ("dpop", "_O2PKT-TEST-DPOP", "OAUTH2 P256 KEY DPOP READY"),
    (
        "preflight",
        "_O2PKT-TEST-PREFLIGHT",
        "OAUTH2 P256 KEY PREFLIGHT READY",
    ),
)

FAILURE_MARKERS = (
    "OAUTH2 P256 KEY FAIL",
    "OAUTH2 P256 KEY ASSERT",
    "OAUTH2 P256 KEY STACK",
    "OAUTH2 P256 KEY LOAD STACK FAIL",
    "DRIVER THROW",
    "Branch offset overflow",
    "dictionary full",
    "exception",
    "Module not found",
    "Path component not found",
    "? (not found)",
)


# The P-256 and JWK implementations already have exhaustive linked
# qualification. This seam keeps their exact public geometry and status
# vocabularies while making key generation, derivation, and thumbprinting
# deterministic. The credential vault and key owner remain exact production
# bodies.
P256_JWK_DOUBLES = r"""

PROVIDED akashic-p256
PROVIDED akashic-jose-jwk-p256

32 CONSTANT P256-SCALAR-SIZE
32 CONSTANT P256-PRIVATE-SIZE
65 CONSTANT P256-PUBLIC-SIZE
1152 CONSTANT P256-WORKSPACE-SIZE

0 CONSTANT P256-S-OK
1 CONSTANT P256-S-RANGE
2 CONSTANT P256-S-PROTECTED
3 CONSTANT P256-S-PLATFORM
4 CONSTANT P256-S-ALIAS
5 CONSTANT P256-S-PRIVATE
6 CONSTANT P256-S-PUBLIC
7 CONSTANT P256-S-SCALAR
8 CONSTANT P256-S-IDENTITY
9 CONSTANT P256-S-ENTROPY
10 CONSTANT P256-S-INTERNAL

: P256-STATUS-VALID?  ( status -- flag )
    DUP P256-S-OK >= SWAP P256-S-INTERNAL <= AND ;

: P256-RESERVED-OVERLAP?  ( address length -- flag )
    2DROP 0 ;

VARIABLE _O2PKD-P256-KEYGEN-STATUS
VARIABLE _O2PKD-P256-DERIVE-STATUS
VARIABLE _O2PKD-P256-KEYGEN-CALLS
VARIABLE _O2PKD-P256-DERIVE-CALLS
VARIABLE _O2PKD-P256-MUTATE-A
VARIABLE _O2PKD-P256-MUTATE-BYTE
VARIABLE _O2PKD-JWK-STATUS
VARIABLE _O2PKD-JWK-CALLS

: _O2PKD-FILLED?  ( address length byte -- flag )
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

: _O2PKD-PUBLIC!  ( public -- )
    DUP P256-PUBLIC-SIZE 0x22 FILL
    0x04 SWAP C! ;

: P256-WORKSPACE-CLEAR  ( workspace -- status )
    DUP 0= IF DROP P256-S-RANGE EXIT THEN
    P256-WORKSPACE-SIZE 0 FILL
    P256-S-OK ;

: P256-KEYGEN  ( private public workspace -- status )
    >R
    R@ P256-WORKSPACE-SIZE 0 FILL
    1 _O2PKD-P256-KEYGEN-CALLS +!
    _O2PKD-P256-KEYGEN-STATUS @ DUP IF
        >R 2DROP R> R> DROP EXIT
    THEN
    DROP
    _O2PKD-P256-MUTATE-A @ ?DUP IF
        RID-SIZE _O2PKD-P256-MUTATE-BYTE @ FILL
    THEN
    OVER P256-PRIVATE-SIZE 0x11 FILL
    DUP _O2PKD-PUBLIC!
    2DROP R> DROP P256-S-OK ;

: P256-PUBLIC-FROM-PRIVATE  ( private public workspace -- status )
    >R
    R@ P256-WORKSPACE-SIZE 0 FILL
    1 _O2PKD-P256-DERIVE-CALLS +!
    _O2PKD-P256-DERIVE-STATUS @ DUP IF
        >R 2DROP R> R> DROP EXIT
    THEN
    DROP
    OVER P256-PRIVATE-SIZE 0x11 _O2PKD-FILLED? 0= IF
        2DROP R> DROP P256-S-PRIVATE EXIT
    THEN
    DUP _O2PKD-PUBLIC!
    2DROP R> DROP P256-S-OK ;

65 CONSTANT JOSE-JWK-P256-PUBLIC-SIZE
126 CONSTANT JOSE-JWK-P256-CANONICAL-SIZE
32 CONSTANT JOSE-JWK-P256-THUMBPRINT-SIZE
32 CONSTANT JOSE-JWK-P256-MAX-MEMBERS
15567 CONSTANT JOSE-JWK-P256-WORKSPACE-SIZE

0 CONSTANT JOSE-JWK-P256-S-OK
1 CONSTANT JOSE-JWK-P256-S-INVALID
2 CONSTANT JOSE-JWK-P256-S-CAPACITY
3 CONSTANT JOSE-JWK-P256-S-ALIAS
4 CONSTANT JOSE-JWK-P256-S-JSON
5 CONSTANT JOSE-JWK-P256-S-POLICY
6 CONSTANT JOSE-JWK-P256-S-ENCODING
7 CONSTANT JOSE-JWK-P256-S-PUBLIC
8 CONSTANT JOSE-JWK-P256-S-CRYPTO
9 CONSTANT JOSE-JWK-P256-S-INTERNAL
10 CONSTANT JOSE-JWK-P256-S-RANGE
11 CONSTANT JOSE-JWK-P256-S-PROTECTED
12 CONSTANT JOSE-JWK-P256-S-PLATFORM

: JOSE-JWK-P256-STATUS-VALID?  ( status -- flag )
    DUP JOSE-JWK-P256-S-OK >=
    SWAP JOSE-JWK-P256-S-PLATFORM <= AND ;

0x7FFFFFFFFFFEE000 CONSTANT _O2PKD-RANGE-WORKSPACE
0x7FFFFFFFFFFED000 CONSTANT _O2PKD-PROTECTED-WORKSPACE
0x7FFFFFFFFFFEC000 CONSTANT _O2PKD-PLATFORM-WORKSPACE
17879 CONSTANT _O2PKD-OWNER-WORKSPACE-SIZE

' CALLER-SPAN-STATUS CONSTANT _O2PKD-BASE-CALLER-SPAN-XT
VARIABLE _O2PKD-CALLER-A
VARIABLE _O2PKD-CALLER-U

: CALLER-SPAN-STATUS  ( address length -- status )
    2DUP _O2PKD-CALLER-U ! _O2PKD-CALLER-A !
    _O2PKD-CALLER-U @ _O2PKD-OWNER-WORKSPACE-SIZE = IF
        _O2PKD-CALLER-A @ _O2PKD-RANGE-WORKSPACE = IF
            2DROP CALLER-SPAN-S-RANGE EXIT
        THEN
        _O2PKD-CALLER-A @ _O2PKD-PROTECTED-WORKSPACE = IF
            2DROP CALLER-SPAN-S-PROTECTED EXIT
        THEN
        _O2PKD-CALLER-A @ _O2PKD-PLATFORM-WORKSPACE = IF
            2DROP CALLER-SPAN-S-PLATFORM EXIT
        THEN
    THEN
    _O2PKD-BASE-CALLER-SPAN-XT EXECUTE ;

: JOSE-JWK-P256-CALLER-SPAN-STATUS
  ( address length -- status )
    CALLER-SPAN-STATUS
    DUP CALLER-SPAN-S-OK = IF
        DROP JOSE-JWK-P256-S-OK EXIT
    THEN
    DUP CALLER-SPAN-S-RANGE = IF
        DROP JOSE-JWK-P256-S-RANGE EXIT
    THEN
    DUP CALLER-SPAN-S-PROTECTED = IF
        DROP JOSE-JWK-P256-S-PROTECTED EXIT
    THEN
    DUP CALLER-SPAN-S-PLATFORM = IF
        DROP JOSE-JWK-P256-S-PLATFORM EXIT
    THEN
    DROP JOSE-JWK-P256-S-PLATFORM ;

: JOSE-JWK-P256-WORKSPACE-CLEAR  ( workspace -- status )
    DUP 0= IF DROP JOSE-JWK-P256-S-RANGE EXIT THEN
    JOSE-JWK-P256-WORKSPACE-SIZE 0 FILL
    JOSE-JWK-P256-S-OK ;

: JOSE-JWK-P256-THUMBPRINT
  ( public digest-output workspace -- status )
    >R
    R@ JOSE-JWK-P256-WORKSPACE-SIZE 0 FILL
    1 _O2PKD-JWK-CALLS +!
    _O2PKD-JWK-STATUS @ DUP IF
        >R 2DROP R> R> DROP EXIT
    THEN
    DROP
    OVER C@ 0x04 <> IF
        2DROP R> DROP JOSE-JWK-P256-S-PUBLIC EXIT
    THEN
    OVER 1+ 64 0x22 _O2PKD-FILLED? 0= IF
        2DROP R> DROP JOSE-JWK-P256-S-PUBLIC EXIT
    THEN
    DUP JOSE-JWK-P256-THUMBPRINT-SIZE 0x33 FILL
    2DROP R> DROP JOSE-JWK-P256-S-OK ;

: _O2PKD-RESET  ( -- )
    0 _O2PKD-P256-KEYGEN-STATUS !
    0 _O2PKD-P256-DERIVE-STATUS !
    0 _O2PKD-P256-KEYGEN-CALLS !
    0 _O2PKD-P256-DERIVE-CALLS !
    0 _O2PKD-P256-MUTATE-A !
    0 _O2PKD-P256-MUTATE-BYTE !
    0 _O2PKD-JWK-STATUS !
    0 _O2PKD-JWK-CALLS ! ;
"""


def _word_body(source: str, name: str) -> str:
    match = re.search(
        rf"(?ms)^:[ \t]+{re.escape(name)}(?=[ \t\r\n(])"
        rf"(?P<body>.*?)[ \t]+;",
        source,
    )
    assert match is not None, f"missing Forth word {name}"
    return match.group("body")


def _requires(path: Path) -> list[str]:
    return re.findall(
        r"(?mi)^[ \t]*REQUIRE[ \t]+(\S+)",
        path.read_text(encoding="utf-8"),
    )


def _forth_code(source: str) -> str:
    return "\n".join(line.split("\\", 1)[0] for line in source.splitlines())


def _assert_physical_comments(path: Path, source: str) -> None:
    for line_number, line in enumerate(source.splitlines(), start=1):
        code = line.split("\\", 1)[0]
        if "(" in code:
            assert ")" in code.split("(", 1)[1], (
                "KDOS parenthesized comments must close on their physical "
                f"line: {path}:{line_number}"
            )


def _assert_static_contracts() -> None:
    source = SOURCE.read_text(encoding="utf-8")
    fixture = FIXTURE.read_text(encoding="utf-8")
    source_code = _forth_code(source)
    fixture_code = _forth_code(fixture)

    assert 0 < FINISH_STEPS <= MAX_PHASE_STEPS
    assert len({marker for _, marker in LOAD_STAGES}) == len(LOAD_STAGES)
    assert len({marker for _, _, marker in GROUP_STAGES}) == len(GROUP_STAGES)
    for marker in (
        *(marker for _, marker in LOAD_STAGES),
        *(marker for _, _, marker in GROUP_STAGES),
        PASS_MARKER,
    ):
        assert all(failure not in marker for failure in FAILURE_MARKERS)
    for staged_name in (
        "o2pko-deps.f",
        "o2pko-vault.f",
        "o2pko-source.f",
        "o2pko-test.f",
        FIXTURE.name,
    ):
        assert len(staged_name.encode("ascii")) <= 23

    assert "PROVIDED akashic-oauth2-key-p256" in source
    assert _requires(SOURCE) == [
        "../../utils/memory-span.f",
        "../../utils/caller-span.f",
        "../../runtime/identity.f",
        "../credential-vault.f",
        "../jose/jwk-p256.f",
        "../../math/p256.f",
    ]
    assert not re.search(
        r"(?mi)^[ \t]*(?:CREATE|VARIABLE|VALUE|DEFER|GUARD)\b",
        source,
    ), "the key owner must retain no module-owned mutable state"
    for forbidden in ("atproto", "streams", "xrpc", "http", "client-config"):
        assert forbidden not in "\n".join(_requires(SOURCE)).lower()

    for value, suffix in enumerate(
        (
            "OK",
            "INVALID",
            "CAPACITY",
            "ALIAS",
            "STATE",
            "ABSENT",
            "REVOKED",
            "CONFLICT",
            "BUSY",
            "CALLBACK",
            "LOCKED",
            "ENTROPY",
            "CRYPTO",
            "AUTH",
            "CORRUPT",
            "UNSUPPORTED",
            "IO",
            "RECOVERY",
            "ROLLBACK",
            "FORMAT",
            "KEY",
            "MISMATCH",
            "RANGE",
            "PROTECTED",
            "PLATFORM",
            "INTERNAL",
        )
    ):
        assert re.search(
            rf"(?m)^{value}[ \t]+CONSTANT[ \t]+"
            rf"OAUTH2-P256-KEY-S-{suffix}$",
            source,
        )

    for name, value in (
        ("OAUTH2-P256-KEY-SLOT-SIZE", 80),
        ("OAUTH2-P256-KEY-BINDING-SIZE", 192),
        ("OAUTH2-P256-KEY-RECORD-SIZE", 336),
        ("OAUTH2-P256-KEY-KID-CAPACITY", 256),
    ):
        assert re.search(
            rf"(?m)^{value}[ \t]+CONSTANT[ \t]+{re.escape(name)}$",
            source,
        )
    assert "OAUTH2-P256-KEY-WORKSPACE-SIZE 17879 <>" in source

    for word in (
        "OAUTH2-P256-KEY-STATUS-VALID?",
        "OAUTH2-P256-KEY-WORKSPACE-CLEAR",
        "OAUTH2-P256-KEY-BINDING-CLEAR",
        "OAUTH2-P256-KEY-BINDING-INIT",
        "OAUTH2-P256-KEY-BINDING-PRESENCE@",
        "OAUTH2-P256-KEY-PROVISION-CLIENT",
        "OAUTH2-P256-KEY-PROVISION-DPOP",
        "OAUTH2-P256-KEY-SLOT-LOAD-CLIENT",
        "OAUTH2-P256-KEY-SLOT-LOAD-DPOP",
        "OAUTH2-P256-KEY-WITH-CLIENT",
        "OAUTH2-P256-KEY-WITH-DPOP",
    ):
        assert word in source

    for mapper, required in (
        (
            "_O2PK-CVAULT>STATUS",
            (
                "CVAULT-S-ABSENT",
                "CVAULT-S-REVOKED",
                "CVAULT-S-CONFLICT",
                "CVAULT-S-BUSY",
                "CVAULT-S-RANGE",
                "CVAULT-S-PROTECTED",
                "CVAULT-S-PLATFORM",
                "OAUTH2-P256-KEY-S-INTERNAL SWAP",
            ),
        ),
        (
            "_O2PK-P256>STATUS",
            (
                "P256-S-PRIVATE",
                "P256-S-ENTROPY",
                "P256-S-RANGE",
                "P256-S-PROTECTED",
                "P256-S-PLATFORM",
                "OAUTH2-P256-KEY-S-INTERNAL SWAP",
            ),
        ),
        (
            "_O2PK-JWK>STATUS",
            (
                "JOSE-JWK-P256-S-PUBLIC",
                "JOSE-JWK-P256-S-CRYPTO",
                "JOSE-JWK-P256-S-RANGE",
                "JOSE-JWK-P256-S-PROTECTED",
                "JOSE-JWK-P256-S-PLATFORM",
                "OAUTH2-P256-KEY-S-INTERNAL SWAP",
            ),
        ),
    ):
        body = _word_body(source, mapper)
        for marker in required:
            assert marker in body

    provision_geometry = _word_body(source, "_O2PK-PROVISION-GEOMETRY")
    assert provision_geometry.index("_O2PK-ALIGNED-FIXED-STATUS") < (
        provision_geometry.index("_O2PK-VAULT-SPAN-STATUS")
    )
    assert "CVAULT-SECRET-CAPACITY@" in provision_geometry
    with_geometry = _word_body(source, "_O2PK-WITH-GEOMETRY")
    assert "_O2PK-VAULT-SPAN-STATUS" in with_geometry
    assert "MSPAN-OVERLAP?" in with_geometry

    provision = _word_body(source, "_O2PK-PROVISION-OP")
    assert provision.index("P256-KEYGEN") < provision.index(
        "JOSE-JWK-P256-THUMBPRINT"
    )
    assert provision.index("JOSE-JWK-P256-THUMBPRINT") < provision.index(
        "CVAULT-CREATE"
    )
    assert provision.index("_O2PKW.RID-SNAPSHOT") < provision.index(
        "P256-KEYGEN"
    )
    assert provision.count("_O2PK-WIPE") >= 3

    consumer = _word_body(source, "_O2PK-VAULT-CONSUMER")
    assert "P256-PUBLIC-FROM-PRIVATE" in consumer
    assert "JOSE-JWK-P256-THUMBPRINT" in consumer
    assert "_O2PK-CALLBACK" not in consumer
    with_op = _word_body(source, "_O2PK-WITH-OP")
    assert with_op.index("MOVE") < with_op.index(
        "_O2PK-STAGED-BINDING-STATUS"
    )
    assert with_op.index("_O2PK-STAGED-BINDING-STATUS") < with_op.index(
        "_O2PK-VAULT-WITH"
    )
    assert with_op.index("_O2PK-VAULT-WITH") < with_op.index(
        "_O2PK-CALLBACK-SAFE"
    )
    assert with_op.count("_O2PK-WIPE") >= 3
    callback = _word_body(source, "_O2PK-CALLBACK-RUN")
    assert "OAUTH2-P256-KEY-ROLE-CLIENT" in callback
    assert "_O2PKW.PUBLIC" in callback
    assert "_O2PKW.THUMBPRINT" in callback
    assert "EXECUTE" in callback

    record = _word_body(source, "_O2PK-RECORD-STRUCTURE?")
    for marker in (
        "_O2PKR.MAGIC",
        "_O2PKR.VERSION",
        "_O2PKR.TOTAL-U",
        "_O2PKR.ROLE",
        "_O2PKR.KID-U",
        "_O2PKR.FLAGS",
        "_O2PK-ZERO?",
    ):
        assert marker in record
    binding = _word_body(source, "_O2PK-BINDING-BODY?")
    assert "_O2PK-SLOTS-DISTINCT?" in binding
    assert binding.count("_O2PK-ZERO?") >= 2

    assert "PROVIDED akashic-o2p256key-test" in fixture
    for marker in (
        "_O2PKT-INIT",
        "_O2PKT-TEST-BINDING",
        "_O2PKT-TEST-CLIENT",
        "_O2PKT-TEST-FAILURES",
        "_O2PKT-TEST-CALLBACKS",
        "_O2PKT-TEST-DPOP",
        "_O2PKT-TEST-PREFLIGHT",
        "_O2PKT-FINISH",
        "CVAULT-METADATA",
        "OAUTH2-P256-KEY-S-MISMATCH",
        "OAUTH2-P256-KEY-S-FORMAT",
        "OAUTH2-P256-KEY-S-CALLBACK",
        PASS_MARKER,
    ):
        assert marker in fixture

    for code, label in (
        (source_code, "production owner"),
        (fixture_code, "owner fixture"),
        (_forth_code(P256_JWK_DOUBLES), "dependency doubles"),
    ):
        assert not re.search(
            r"(?i)(?<![A-Za-z0-9_-])(?:\?DO|DO|\+LOOP|LOOP)"
            r"(?![A-Za-z0-9_-])",
            code,
        ), f"{label} must not borrow the DO-loop return stack"

    _assert_physical_comments(SOURCE, source)
    _assert_physical_comments(FIXTURE, fixture)


def _packed(path: Path, *, remove_requires: bool = False) -> bytes:
    return harness._minify_forth(
        path.read_text(encoding="utf-8"),
        remove_requires=remove_requires,
    ).encode("utf-8")


def _run_lifecycle(timeout: float) -> int:
    dependency_source = (
        DEPS.read_text(encoding="utf-8")
        + "\n"
        + P256_JWK_DOUBLES
    )

    autoexec = [
        "\\ autoexec.f - staged OAuth P-256 key-owner seam\n",
        "ENTER-USERLAND\n",
        '." OAUTH2 P256 KEY LOAD START" CR TX-FLUSH\n',
    ]
    staged_modules = (
        ("local_testing/o2pko-deps.f", LOAD_STAGES[0][1]),
        ("local_testing/o2pko-vault.f", LOAD_STAGES[1][1]),
        ("local_testing/o2pko-source.f", LOAD_STAGES[2][1]),
        ("local_testing/o2pko-test.f", LOAD_STAGES[3][1]),
    )
    for module, marker in staged_modules:
        autoexec.extend(
            (
                f"REQUIRE {module}\n",
                (
                    'DEPTH IF ." OAUTH2 P256 KEY LOAD STACK FAIL" '
                    "CR TX-FLUSH THEN\n"
                ),
                f'." {marker}" CR TX-FLUSH\n',
                "KEY DROP\n",
            )
        )
    autoexec.extend(("_O2PKT-INIT\n",))
    for _, word, marker in GROUP_STAGES:
        autoexec.extend(
            (
                f"{word}\n",
                f'." {marker}" CR TX-FLUSH\n',
                "KEY DROP\n",
            )
        )
    autoexec.append("_O2PKT-FINISH\nTX-FLUSH\n")

    harness.PROFILES[PROFILE] = harness.Profile(
        roots=(),
        resources=(),
        autoexec="".join(autoexec),
        ready_markers=(PASS_MARKER,),
        stable_markers=(PASS_MARKER,),
        failure_markers=FAILURE_MARKERS,
        initial_files=(
            (
                "local_testing/o2pko-deps.f",
                harness._minify_forth(dependency_source).encode("utf-8"),
            ),
            (
                "local_testing/o2pko-vault.f",
                _packed(VAULT, remove_requires=True),
            ),
            (
                "local_testing/o2pko-source.f",
                _packed(SOURCE, remove_requires=True),
            ),
            ("local_testing/o2pko-test.f", _packed(FIXTURE)),
        ),
        linked=False,
        include_large_sample=False,
        total_sectors=4096,
    )
    image = harness.build_image(PROFILE, IMAGE)
    profile = harness.PROFILES[PROFILE]
    reports: list[tuple[str, object]] = []

    with harness.MachineSession.from_bios(
        harness.MEGAPAD_ROOT / "bios.asm",
        storage_image=image,
        cols=120,
        rows=44,
        batch_steps=500_000,
        ext_mem_size=128 << 20,
        num_cores=1,
    ) as machine:
        machine.boot()
        stages = (
            *(stage for stage in LOAD_STAGES),
            *(stage for stage in GROUP_STAGES),
        )
        for index, stage in enumerate(stages):
            stage_name = stage[0]
            marker = stage[-1]
            if index:
                machine.clear_output()
                machine.send_text("x")
            report = machine.run(
                max_steps=MAX_PHASE_STEPS,
                wall_timeout_s=timeout,
                until_text=marker,
                text_scope="raw",
            )
            raw = machine.raw_text()
            failures = tuple(
                dict.fromkeys(
                    (
                        *harness._has_forth_error(raw),
                        *harness._matched_failure_markers(
                            profile, raw, machine.screen_text()
                        ),
                    )
                )
            )
            reports.append((stage_name, report))
            if marker not in raw or failures:
                print(f"OAuth2 P256 key {stage_name}: FAIL")
                print(
                    f"  {report.steps:,} steps in {report.elapsed_s:.2f}s; "
                    f"stop={report.reason}"
                )
                for failure in failures:
                    print(f"  {failure}")
                print(raw[-5000:])
                return 1
            print(
                f"OAuth2 P256 key {stage_name}: PASS "
                f"({report.steps:,} steps, {report.elapsed_s:.2f}s)",
                flush=True,
            )

        machine.clear_output()
        machine.send_text("x")
        report = machine.run(
            max_steps=FINISH_STEPS,
            wall_timeout_s=timeout,
            until_text=PASS_MARKER,
            text_scope="raw",
        )
        raw = machine.raw_text()
        failures = tuple(
            dict.fromkeys(
                (
                    *harness._has_forth_error(raw),
                    *harness._matched_failure_markers(
                        profile, raw, machine.screen_text()
                    ),
                )
            )
        )
        reports.append(("finish", report))
        if PASS_MARKER not in raw or failures:
            print("OAuth2 P256 key finish: FAIL")
            print(
                f"  {report.steps:,} steps in {report.elapsed_s:.2f}s; "
                f"stop={report.reason}"
            )
            for failure in failures:
                print(f"  {failure}")
            print(raw[-5000:])
            return 1

    total_steps = sum(report.steps for _, report in reports)
    total_elapsed = sum(report.elapsed_s for _, report in reports)
    print(
        "OAuth2 P256 key lifecycle: PASS "
        f"({total_steps:,} steps, {total_elapsed:.2f}s)"
    )
    return 0


def main() -> int:
    parser = argparse.ArgumentParser()
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--static-only", action="store_true")
    mode.add_argument("--lifecycle", action="store_true")
    parser.add_argument("--timeout", type=float, default=240.0)
    args = parser.parse_args()

    _assert_static_contracts()
    print("OAUTH2 P256 KEY STATIC PASS", flush=True)
    if args.static_only:
        return 0
    return _run_lifecycle(args.timeout)


if __name__ == "__main__":
    raise SystemExit(main())
