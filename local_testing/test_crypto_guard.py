#!/usr/bin/env python3
"""Focused linked qualification for scoped SHA-256/SHA-512 operations."""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path


LOCAL_TESTING = Path(__file__).resolve().parent
sys.path.insert(0, str(LOCAL_TESTING))

import akashic_tui as harness  # noqa: E402
from asm import assemble  # noqa: E402


PROFILE_PREFIX = "sha-scoped-contracts"
MATH = LOCAL_TESTING.parent / "akashic" / "math"
SHA256 = MATH / "sha256.f"
SHA512 = MATH / "sha512.f"
BIOS = harness.MEGAPAD_ROOT / "bios.asm"

AUTOEXEC = r"""\ autoexec.f - scoped SHA operation contract
ENTER-USERLAND
: _SHA-CONTRACT-BOOT ." SHA CONTRACT BOOT" CR ;
_SHA-CONTRACT-BOOT
{context_address} CONSTANT _SHA-CONTRACT-CONTEXT
REQUIRE math/{module}.f
: _SHA-MODULE-LOADED ." SHA MODULE LOADED" CR ;
_SHA-MODULE-LOADED
REQUIRE local_testing/{contract}
: _SHA-FIXTURE-LOADED ." SHA FIXTURE LOADED" CR ;
_SHA-FIXTURE-LOADED
{entrypoint}
"""


def _word_body(source: str, name: str) -> str:
    match = re.search(
        rf"(?ms)^:[ \t]+{re.escape(name)}(?=[ \t\r\n(])"
        rf"(?P<body>.*?)[ \t]+;",
        source,
    )
    assert match is not None, f"missing definition for {name}"
    return match.group("body")


def _assert_checked_source(path: Path, prefix: str, short: str) -> None:
    source = path.read_text(encoding="utf-8")
    assert "REQUIRE crypto-acc.f" in source
    assert "REQUIRE ../utils/memory-span.f" in source
    assert re.search(
        rf"(?m)^GUARD-BLOCKING _{prefix.lower()}-guard$",
        source,
    )

    for status in (
        "OK",
        "STATE",
        "RANGE",
        "ALIAS",
        "LENGTH-OVERFLOW",
        "INVALID",
        "CRYPTO",
    ):
        assert f"{prefix}-S-{status}" in source
    assert f"{prefix}-STATUS-VALID?" in source

    local_reserved = _word_body(
        source, f"_{short}-LOCAL-RESERVED-OVERLAP?"
    )
    assert "CRYPTO-ACC-RESERVED-OVERLAP?" in local_reserved
    assert "GUARD-BLOCKING-SIZE MSPAN-OVERLAP?" in local_reserved

    bios_span = _word_body(source, f"_{short}-BIOS-SPAN-STATUS")
    assert "['] SHA2-SPAN-STATUS CATCH" in bios_span
    assert f"_{short}-DROP3" in bios_span
    for admitted in ("OK", "RANGE", "ALIAS"):
        assert f"{prefix}-S-{admitted}" in bios_span
    for impossible in ("STATE", "LENGTH-OVERFLOW", "INVALID"):
        assert f"{prefix}-S-{impossible}" not in bios_span
    assert f"{prefix}-S-CRYPTO" in bios_span

    caller_span = _word_body(source, f"{prefix}-CALLER-SPAN-STATUS")
    input_check = caller_span.index(f"_{short}-INPUT-SPAN?")
    local_check = caller_span.index(
        f"_{short}-LOCAL-RESERVED-OVERLAP?"
    )
    bios_check = caller_span.index(f"_{short}-BIOS-SPAN-STATUS")
    assert input_check < local_check < bios_check
    assert f"{prefix}-S-INVALID" in caller_span
    assert f"{prefix}-S-ALIAS" in caller_span
    assert f"{prefix}-INIT" not in caller_span

    for removed in ("BEGIN", "ADD", "END"):
        assert not re.search(
            rf"(?m)^:\s+{prefix}-{removed}\b",
            source,
        ), f"unsafe public streaming word {prefix}-{removed} still exists"
    assert f"_{prefix}-RAW-" not in source

    compare = _word_body(source, f"{prefix}-COMPARE")
    assert ">R" not in compare
    assert "R>" not in compare
    assert compare.count("2 PICK I + C@") == 2
    assert "XOR OR" in compare

    finish = _word_body(source, f"_{short}-FINISH")
    assert f"['] {prefix}-FINAL CATCH" in finish
    assert f"_{short}-CLEAR-AFTER-FAILURE" in finish
    assert "R> THROW" in finish

    clear = _word_body(source, f"_{short}-CLEAR-STATUS")
    assert f"['] {prefix}-CLEAR CATCH" in clear

    for number, updates in ((1, 1), (2, 2), (3, 3)):
        prefix_body = _word_body(source, f"_{short}-PREFIX-{number}")
        assert prefix_body.count(f"{prefix}-INIT") == 1
        assert prefix_body.count(f"{prefix}-UPDATE") == updates

        unit = _word_body(source, f"_{short}-UNIT-{number}")
        assert unit.index("GUARD-ACQUIRE") < unit.index(
            f"_{short}-PREFIX-{number} CATCH"
        )
        assert f"_{short}-CLEAR-AFTER-FAILURE" in unit

    for suffix, number in (("HASH", 1), ("HASH-2", 2), ("HASH-3", 3)):
        public = _word_body(source, f"{prefix}-{suffix}")
        assert public.index(f"_{short}-PREFLIGHT-{number}") < public.index(
            "CRYPTO-ACC-WITH-TRANSACTION"
        )
        assert f"_{short}-UNIT-{number}" in public
        preflight = _word_body(source, f"_{short}-PREFLIGHT-{number}")
        assert preflight.count(
            f"{prefix}-CALLER-SPAN-STATUS"
        ) == number + 1


def _assert_fixture_source(
    path: Path, prefix: str, short: str, later_offset: int
) -> None:
    source = path.read_text(encoding="utf-8")
    caller_span = _word_body(
        source, f"_{short.lower()}t-test-caller-span-status"
    )
    assert f"{prefix}-CALLER-SPAN-STATUS" in caller_span
    for status in ("OK", "RANGE", "ALIAS", "INVALID"):
        assert f"{prefix}-S-{status}" in caller_span
    assert "EXT-MEM-BASE EXT-MEM-SIZE + 1 - 2" in caller_span
    assert "_SHA-CONTRACT-CONTEXT" in caller_span
    assert f"{prefix}-INIT" in caller_span
    assert f"{prefix}-UPDATE" in caller_span
    assert f"{prefix}-CLEAR" in caller_span

    compare = _word_body(source, f"_{short.lower()}t-test-compare")
    assert f"_s{short[1:]}t-copy {later_offset} +" in compare
    assert compare.count(f"{prefix}-COMPARE 0=") == 2


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--timeout", type=float, default=900.0)
    parser.add_argument(
        "--part",
        choices=("all", "sha256", "sha512"),
        default="all",
        help="run one bounded image or both images serially",
    )
    args = parser.parse_args()

    _assert_checked_source(SHA256, "SHA256", "S256")
    _assert_checked_source(SHA512, "SHA512", "S512")
    _assert_fixture_source(
        LOCAL_TESTING / "sha256-scoped-test.f", "SHA256", "S256", 17
    )
    _assert_fixture_source(
        LOCAL_TESTING / "sha512-scoped-test.f", "SHA512", "S512", 41
    )
    sha512_source = SHA512.read_text(encoding="utf-8")
    for removed_software_state in (
        "_S512-K",
        "_S512-IV",
        "_S512-H ",
        "_S512-W ",
        "_S512-BUF",
        "_S512-COMPRESS",
    ):
        assert removed_software_state not in sha512_source
    bios_labels: dict[str, int] = {}
    assemble(BIOS.read_text(encoding="utf-8"), labels_out=bios_labels)

    parts = (
        (
            "sha256",
            "sha256-scoped-test.f",
            "_S256T-RUN",
            "SHA256 SCOPED",
            "sha256_contexts",
        ),
        (
            "sha512",
            "sha512-scoped-test.f",
            "_S512T-RUN",
            "SHA512 SCOPED",
            "sha512_contexts",
        ),
    )
    selected_parts = (
        parts if args.part == "all" else tuple(p for p in parts if p[0] == args.part)
    )
    for part, contract_name, entrypoint, marker, context_label in selected_parts:
        profile = f"{PROFILE_PREFIX}-{part}"
        image_path = Path(f"/tmp/akashic-{profile}.img")
        contract = LOCAL_TESTING / contract_name
        harness.PROFILES[profile] = harness.Profile(
            roots=(f"math/{part}.f",),
            resources=(),
            autoexec=AUTOEXEC.format(
                module=part,
                contract=contract_name,
                entrypoint=entrypoint,
                context_address=bios_labels[context_label],
            ),
            ready_markers=(f"{marker} PASS",),
            stable_markers=(f"{marker} PASS",),
            failure_markers=(
                f"{marker} FAIL",
                f"{marker} ASSERT",
                f"{marker} STACK",
                "DRIVER THROW",
                "dictionary full",
                "exception",
                "(not found)",
            ),
            initial_files=(
                (f"local_testing/{contract_name}", contract.read_bytes()),
            ),
            linked=True,
            include_large_sample=False,
            total_sectors=2048,
        )
        image = harness.build_image(profile, image_path)
        if not harness.smoke(
            profile,
            image,
            cols=120,
            rows=40,
            max_steps=800_000_000,
            timeout=args.timeout,
            ext_mem_mib=128,
        ):
            return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
