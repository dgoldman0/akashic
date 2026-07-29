#!/usr/bin/env python3
"""Static and staged qualification for checked public P-256 JWK Sets."""

from __future__ import annotations

import argparse
import base64
import hashlib
import json
import re
import sys
from pathlib import Path


LOCAL_TESTING = Path(__file__).resolve().parent
ROOT = LOCAL_TESTING.parent
sys.path.insert(0, str(LOCAL_TESTING))

import akashic_tui as harness  # noqa: E402


PROFILE = "jose-jwk-set-p256-contracts"
IMAGE = Path("/tmp/akashic-jose-jwk-set-p256-contracts.img")
SOURCE = ROOT / "akashic" / "security" / "jose" / "jwk-set-p256.f"
JWK_SOURCE = ROOT / "akashic" / "security" / "jose" / "jwk-p256.f"
DOC = ROOT / "docs" / "security" / "jose-jwk-set-p256.md"
CONTRACT = LOCAL_TESTING / "jwk-set-p256-test.f"

PASS_MARKER = "JOSE JWK SET P256 PASS"
MAX_PHASE_STEPS = 300_000_000
FINISH_STEPS = 20_000_000

LOAD_STAGES = (
    ("memory-span", "utils/memory-span.f", "JJKS MEMORY SPAN READY"),
    ("caller-span", "utils/caller-span.f", "JJKS CALLER SPAN READY"),
    (
        "base64url",
        "security/jose/base64url.f",
        "JJKS BASE64URL READY",
    ),
    (
        "json-object",
        "security/jose/json-object.f",
        "JJKS JSON OBJECT READY",
    ),
    ("sha256", "math/sha256.f", "JJKS SHA256 READY"),
    ("p256", "math/p256.f", "JJKS P256 READY"),
    (
        "jwk-p256",
        "security/jose/jwk-p256.f",
        "JJKS JWK P256 READY",
    ),
    (
        "jwk-set-p256",
        "security/jose/jwk-set-p256.f",
        "JJKS SOURCE READY",
    ),
    (
        "fixture",
        "local_testing/jwk-set-p256-test.f",
        "JJKS FIXTURE READY",
    ),
)

GROUP_STAGES = (
    ("statuses", "_jjkst-test-statuses", "JJKS STATUSES READY"),
    ("successes", "_jjkst-test-successes", "JJKS SUCCESSES READY"),
    ("envelope", "_jjkst-test-envelope", "JJKS ENVELOPE READY"),
    ("policy", "_jjkst-test-policy", "JJKS POLICY READY"),
    (
        "preflight-ownership",
        "_jjkst-test-preflight-ownership",
        "JJKS PREFLIGHT OWNERSHIP READY",
    ),
    ("key-bound", "_jjkst-test-key-bound", "JJKS KEY BOUND READY"),
)


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


def _create_bytes(source: str, name: str) -> bytes:
    match = re.search(
        rf"(?ms)^CREATE[ \t]+{re.escape(name)}[ \t]*\n"
        rf"(?P<body>.*?)(?=^(?:CREATE|:|[ \t]*\\ [=]{{5,}})|\Z)",
        source,
    )
    assert match is not None, f"missing fixture byte table {name}"
    return bytes(
        int(value, 16)
        for value in re.findall(
            r"0x([0-9A-Fa-f]{2})[ \t]+C,", match.group("body")
        )
    )


def _independent_vectors() -> tuple[tuple[bytes, bytes], ...]:
    x = bytes.fromhex(
        "60FED4BA255A9D31C961EB74C6356D68"
        "C049B8923B61FA6CE669622E60F29FB6"
    )
    y_values = (
        bytes.fromhex(
            "7903FE1008B8BC99A41AE9E95628BC64"
            "F2F1B20C2D7E9F5177A3C294D4462299"
        ),
        bytes.fromhex(
            "86FC01EEF74743675BE51616A9D7439B"
            "0D0E4DF4D28160AE885C3D6B2BB9DD66"
        ),
    )

    def b64url(value: bytes) -> str:
        return base64.urlsafe_b64encode(value).rstrip(b"=").decode("ascii")

    vectors: list[tuple[bytes, bytes]] = []
    for y in y_values:
        canonical = json.dumps(
            {
                "crv": "P-256",
                "kty": "EC",
                "x": b64url(x),
                "y": b64url(y),
            },
            sort_keys=True,
            separators=(",", ":"),
        ).encode("ascii")
        vectors.append((b"\x04" + x + y, hashlib.sha256(canonical).digest()))
    return tuple(vectors)


def _assert_static_contracts() -> None:
    source = SOURCE.read_text(encoding="utf-8")
    jwk_source = JWK_SOURCE.read_text(encoding="utf-8")
    fixture = CONTRACT.read_text(encoding="utf-8")
    doc = DOC.read_text(encoding="utf-8")
    fixture_code = _forth_code(fixture)

    assert 0 < FINISH_STEPS <= MAX_PHASE_STEPS
    assert len({name for name, _, _ in LOAD_STAGES}) == len(LOAD_STAGES)
    assert len({name for name, _, _ in GROUP_STAGES}) == len(GROUP_STAGES)
    markers = tuple(
        marker for _, _, marker in (*LOAD_STAGES, *GROUP_STAGES)
    )
    assert len(set(markers)) == len(markers)
    assert len(CONTRACT.name.encode("utf-8")) <= 23

    assert "PROVIDED akashic-jose-jwks-p256" in source
    assert _requires(SOURCE) == [
        "../../utils/memory-span.f",
        "json-object.f",
        "jwk-p256.f",
    ]
    assert not re.search(
        r"(?mi)^[ \t]*(?:CREATE|VARIABLE|VALUE|DEFER|GUARD)\b",
        source,
    ), "the selector must own no module-state storage"
    assert not any(
        marker in requirement.lower()
        for requirement in _requires(SOURCE)
        for marker in (
            "atproto",
            "oauth",
            "streams",
            "session",
            "xrpc",
            "http",
        )
    )
    assert not re.search(
        r"(?i)\b(?:\?DO|DO|\+LOOP|LOOP)\b", _forth_code(source)
    ), "production iteration must not borrow the DO-loop return stack"

    for word in (
        "JOSE-JWK-SET-P256-PUBLIC-SIZE",
        "JOSE-JWK-SET-P256-THUMBPRINT-SIZE",
        "JOSE-JWK-SET-P256-MAX-DOCUMENT-BYTES",
        "JOSE-JWK-SET-P256-MAX-KEYS",
        "JOSE-JWK-SET-P256-MAX-MEMBERS",
        "JOSE-JWK-SET-P256-KID-CAPACITY",
        "JOSE-JWK-SET-P256-WORKSPACE-SIZE",
        "JOSE-JWK-SET-P256-STATUS-VALID?",
        "JOSE-JWK-SET-P256-WORKSPACE-CLEAR",
        "JOSE-JWK-SET-P256-SELECT",
    ):
        assert word in source
    for status in (
        "OK",
        "INVALID",
        "CAPACITY",
        "ALIAS",
        "JSON",
        "MISSING",
        "TYPE",
        "EMPTY",
        "SENSITIVE",
        "UNSUPPORTED",
        "KEY",
        "DUPLICATE",
        "USE",
        "ALGORITHM",
        "KEY-OPS",
        "NOT-FOUND",
        "CRYPTO",
        "INTERNAL",
        "RANGE",
        "PROTECTED",
        "PLATFORM",
    ):
        assert f"JOSE-JWK-SET-P256-S-{status}" in source

    assert re.search(
        r"(?m)^JOSE-JWK-SET-P256-WORKSPACE-SIZE 39528 <> \[IF\]$",
        source,
    )
    for offset in (
        "_JJKSW-DESCRIPTOR-OFF",
        "_JJKSW-CANDIDATES-OFF",
        "_JJKSW-JWK-OFF",
    ):
        assert f"{offset} 7 AND [IF]" in source

    admit = _word_body(source, "_JJKS-ADMIT-SPAN")
    assert "JOSE-JWK-P256-CALLER-SPAN-STATUS" in admit
    assert "JOSE-JWK-P256-CALLER-SPAN-STATUS" in jwk_source
    span_map = _word_body(source, "_JJKS-JWK-SPAN>STATUS")
    for source_status, set_status in (
        ("JOSE-JWK-P256-S-ALIAS", "JOSE-JWK-SET-P256-S-ALIAS"),
        ("JOSE-JWK-P256-S-CRYPTO", "JOSE-JWK-SET-P256-S-CRYPTO"),
        ("JOSE-JWK-P256-S-RANGE", "JOSE-JWK-SET-P256-S-RANGE"),
        (
            "JOSE-JWK-P256-S-PROTECTED",
            "JOSE-JWK-SET-P256-S-PROTECTED",
        ),
        ("JOSE-JWK-P256-S-PLATFORM", "JOSE-JWK-SET-P256-S-PLATFORM"),
    ):
        assert source_status in span_map and set_status in span_map
    geometry = _word_body(source, "_JJKS-SELECT-GEOMETRY")
    assert geometry.count("_JJKS-SPAN-STATUS") >= 4
    assert geometry.count("MSPAN-OVERLAP?") >= 9
    assert "_JJKS-FIXED-STATUS" in geometry

    json_map = _word_body(source, "_JJKS-JSON>STATUS")
    for status in (
        "JOSE-JSON-S-CAPACITY",
        "JOSE-JSON-S-DEPTH",
        "JOSE-JSON-S-MEMBERS",
        "JOSE-JSON-S-STRING",
        "JOSE-JSON-S-DOCUMENT",
    ):
        assert status in json_map

    root = _word_body(source, "_JJKS-ROOT-STAGE")
    assert root.index("_JJKS-OBJECT-PARSE") < root.index(
        "_JJKS-COLLECT-CANDIDATES"
    )
    collect = _word_body(source, "_JJKS-COLLECT-CANDIDATES")
    assert "JOSE-JWK-SET-P256-MAX-KEYS" in collect
    assert "JOSE-JSON-T-OBJECT" in collect
    assert "_JJKSE-TOKEN-OFFSET" in collect
    assert "JOSE-JWK-P256-PUBLIC-PARSE" not in collect

    candidate = _word_body(source, "_JJKS-PROCESS-CANDIDATE")
    policy_order = (
        "_JJKS-OBJECT-PARSE",
        "_JJKS-CHECK-SENSITIVE",
        "_JJKS-CHECK-UNSUPPORTED",
        "_JJKS-VALIDATE-PUBLIC",
        "_JJKS-PROCESS-KID",
        "_JJKS-PROCESS-USE",
        "_JJKS-PROCESS-ALGORITHM",
        "_JJKS-PROCESS-KEY-OPS",
    )
    assert [candidate.index(word) for word in policy_order] == sorted(
        candidate.index(word) for word in policy_order
    )
    assert "JOSE-JWK-P256-PUBLIC-PARSE" in _word_body(
        source, "_JJKS-VALIDATE-PUBLIC"
    )
    process_all = _word_body(source, "_JJKS-PROCESS-ALL")
    assert "_JJKS-PROCESS-CANDIDATE" in process_all
    assert "JOSE-JWK-SET-P256-S-NOT-FOUND" in process_all
    assert "EXIT" not in process_all[
        process_all.index("_JJKSW.MATCH-COUNT") :
        process_all.index("_JJKS-PROCESS-CANDIDATE")
    ]

    sensitive = _word_body(source, "_JJKS-SENSITIVE-NAME?")
    for name in ("d", "k", "p", "q", "dp", "dq", "qi", "oth", "priv"):
        assert f'S" {name}"' in sensitive
    unsupported = _word_body(source, "_JJKS-UNSUPPORTED-NAME?")
    for name in (
        "x5u",
        "x5c",
        "x5t",
        "x5t#S256",
        "nbf",
        "exp",
        "revoked",
    ):
        assert f'S" {name}"' in unsupported

    key_ops = _word_body(source, "_JJKS-PROCESS-KEY-OPS")
    assert key_ops.count("_JJKS-ARRAY-NEXT") == 2
    assert 'S" verify"' in key_ops
    assert "_JJKS-DECODE-SPAN" in key_ops
    assert "_JJKS-STORE-KID" in _word_body(source, "_JJKS-PROCESS-KID")
    assert "COMPARE" in _word_body(source, "_JJKS-KID-DUPLICATE?")

    stage = _word_body(source, "_JJKS-SELECT-STAGE")
    assert "MOVE" not in stage
    assert stage.index("_JJKS-PROCESS-ALL") < stage.index(
        "_JJKS-THUMBPRINT-STAGE"
    )
    publish = _word_body(source, "_JJKS-SELECT-PUBLISH")
    assert publish.count("MOVE") == 2
    wrapper = _word_body(source, "_JJKS-SELECT-CALL")
    assert "CATCH" in wrapper
    assert "_JJKS-CALL-FINALLY" in wrapper
    assert "JOSE-JWK-SET-P256-S-INTERNAL" in wrapper

    assert "PROVIDED jwk-set-p256-test" in fixture
    for group, _, _ in GROUP_STAGES:
        assert group
    run = _word_body(fixture, "_JJKST-RUN")
    for _, word, _ in GROUP_STAGES:
        assert word in fixture
        assert word in run
    for marker in (
        "_jjkst-build-three",
        "_jjkst-build-key-count",
        "_jjkst-emit-nested-trap",
        "_jjkst-set-start-escaped",
        "JOSE-JWK-SET-P256-S-SENSITIVE",
        "JOSE-JWK-SET-P256-S-UNSUPPORTED",
        "JOSE-JWK-SET-P256-S-DUPLICATE",
        "JOSE-JWK-SET-P256-S-NOT-FOUND",
        "JOSE-JWK-SET-P256-MAX-DOCUMENT-BYTES 1+",
        "_jjkst-inputs-unchanged?",
        "_jjkst-outputs-unchanged?",
        "_jjkst-work-zero?",
        "_jjkst-work-tail-unchanged?",
        "_jjkst-work 1+",
        "33 15 _jjkst-build-key-count",
    ):
        assert marker in fixture
    private_tokens = set(
        re.findall(
            r"(?<![A-Za-z0-9-])_[A-Za-z0-9.-]+",
            fixture_code,
        )
    )
    assert all(
        token.lower().startswith("_jjkst") for token in private_tokens
    ), "fixture must not call private production words"
    assert not re.search(
        r"(?i)\b(?:\?DO|DO|\+LOOP|LOOP)\b", fixture_code
    ), "fixture iteration must not borrow the DO-loop return stack"

    vectors = _independent_vectors()
    assert _create_bytes(fixture, "_jjkst-public-1") == vectors[0][0]
    assert _create_bytes(fixture, "_jjkst-public-2") == vectors[1][0]
    assert _create_bytes(fixture, "_jjkst-thumbprint-1") == vectors[0][1]
    assert _create_bytes(fixture, "_jjkst-thumbprint-2") == vectors[1][1]

    for marker in (
        "strict selection profile",
        "39,528",
        "globally unique",
        "`priv`",
        "`nbf`, `exp`, and `revoked`",
        "`[\"verify\"]`",
        "full validation of every key",
        "publication `THROW`",
        "JOSE-JWK-P256-CALLER-SPAN-STATUS",
    ):
        assert marker in doc

    _assert_physical_comments(SOURCE, source)
    _assert_physical_comments(CONTRACT, fixture)


def _run_lifecycle(timeout: float) -> int:
    autoexec = [
        "\\ autoexec.f - staged checked P-256 JWK Set contracts\n",
        "ENTER-USERLAND\n",
    ]
    for stage_name, module, marker in LOAD_STAGES:
        autoexec.extend(
            (
                f"REQUIRE {module}\n",
                (
                    'DEPTH IF ." JOSE JWK SET P256 LOAD STACK FAIL '
                    f'{stage_name}" CR TX-FLUSH THEN\n'
                ),
                f'." {marker}" CR TX-FLUSH\n',
                "KEY DROP\n",
            )
        )
    autoexec.append("_JJKST-INIT\n")
    for _, word, marker in GROUP_STAGES:
        autoexec.extend(
            (
                f"{word}\n",
                f'." {marker}" CR TX-FLUSH\n',
                "KEY DROP\n",
            )
        )
    autoexec.append("_JJKST-FINISH\nTX-FLUSH\n")

    harness.PROFILES[PROFILE] = harness.Profile(
        roots=("security/jose/jwk-set-p256.f",),
        resources=(),
        autoexec="".join(autoexec),
        ready_markers=(PASS_MARKER,),
        stable_markers=(PASS_MARKER,),
        failure_markers=(
            "JOSE JWK SET P256 FAIL",
            "JOSE JWK SET P256 ASSERT",
            "JOSE JWK SET P256 STATUS",
            "JOSE JWK SET P256 STACK",
            "JOSE JWK SET P256 LOAD STACK FAIL",
            "DRIVER THROW",
            "Branch offset overflow",
            "dictionary full",
            "exception",
            "Module not found",
            "Path component not found",
            "? (not found)",
        ),
        initial_files=(
            (
                f"local_testing/{CONTRACT.name}",
                harness._minify_forth(
                    CONTRACT.read_text(encoding="utf-8")
                ).encode("utf-8"),
            ),
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
        stages = (*LOAD_STAGES, *GROUP_STAGES)
        for index, (stage_name, _, marker) in enumerate(stages):
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
                print(f"JOSE JWK Set P256 {stage_name}: FAIL")
                print(
                    f"  {report.steps:,} steps in {report.elapsed_s:.2f}s; "
                    f"stop={report.reason}"
                )
                for failure in failures:
                    print(f"  {failure}")
                print(raw[-5000:])
                return 1
            print(
                f"JOSE JWK Set P256 {stage_name}: PASS "
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
            print("JOSE JWK Set P256 finish: FAIL")
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
        "JOSE JWK Set P256 lifecycle: PASS "
        f"({total_steps:,} steps, {total_elapsed:.2f}s)"
    )
    return 0


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--timeout", type=float, default=600.0)
    parser.add_argument("--static-only", action="store_true")
    args = parser.parse_args()

    _assert_static_contracts()
    print("JOSE JWK Set P256 static contracts: PASS", flush=True)
    if args.static_only:
        return 0
    return _run_lifecycle(args.timeout)


if __name__ == "__main__":
    raise SystemExit(main())
