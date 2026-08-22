#!/usr/bin/env python3
"""Cold-source compile gate for the Checkpoint-5 Rabbit graph provider."""

from __future__ import annotations

import argparse
import sys
from pathlib import Path


LOCAL_TESTING = Path(__file__).resolve().parent
sys.path.insert(0, str(LOCAL_TESTING))

import akashic_tui as harness  # noqa: E402


PROFILE = "streams-library-rabbit-provider-load"
IMAGE = Path("/tmp/akashic-streams-library-rabbit-provider-load.img")
PROVIDER = LOCAL_TESTING / "streams-library-rabbit-provider.f"
PROVIDER_IMAGE_PATH = "local_testing/streams-lib-rabbit.f"
ROOTS = (
    "tui/applets/streams/rabbit-capabilities.f",
    "tui/applets/streams/rabbit-library-profile.f",
    "net/transports/memory-duplex.f",
    "tui/applets/streams/rabbit-connector.f",
)
MAX_STEPS = harness.DEFAULT_SMOKE_MAX_STEPS
DEFAULT_TIMEOUT = 180.0
PASS_MARKER = "STREAMS LIBRARY RABBIT PROVIDER LOAD PASS"

AUTOEXEC = r"""\ autoexec.f - checked Checkpoint-5 provider compile
ENTER-USERLAND
REQUIRE tui/applets/streams/rabbit-capabilities.f
REQUIRE tui/applets/streams/rabbit-library-profile.f
REQUIRE net/transports/memory-duplex.f
REQUIRE tui/applets/streams/rabbit-connector.f
VARIABLE _slrp-status
VARIABLE _slrp-depth
VARIABLE _slrp-depth-ok
: _slrp-load  ( -- )
    DEPTH _slrp-depth !
    ." STREAMS LIBRARY RABBIT PROVIDER LOAD BEFORE eval-status="
        EVAL-STATUS @ . ." state=" STATE @ . CR TX-FLUSH
    S" REQUIRE local_testing/streams-lib-rabbit.f"
        SOURCE-EVALUATE-CHECKED _slrp-status !
    DEPTH _slrp-depth @ = _slrp-depth-ok !
    ." STREAMS LIBRARY RABBIT PROVIDER LOAD AFTER eval-status="
        EVAL-STATUS @ . ." returned-status=" _slrp-status @ .
        ." state=" STATE @ . ." depth=" DEPTH .
        ." line=" EVAL-LINE @ . ." column=" EVAL-COLUMN @ .
        ." throw=" EVAL-THROW @ . ." token=" EVAL-TOKEN TYPE
        CR TX-FLUSH
    _slrp-status @ 0= STATE @ 0= AND _slrp-depth-ok @ AND IF
        ." STREAMS LIBRARY RABBIT PROVIDER LOAD PASS"
    ELSE
        ." STREAMS LIBRARY RABBIT PROVIDER LOAD FAIL"
    THEN
    CR ." STREAMS LIBRARY RABBIT PROVIDER LOAD DONE" CR TX-FLUSH ;
_slrp-load
"""


def _provider_bytes() -> bytes:
    return harness._minify_forth(
        PROVIDER.read_text(encoding="utf-8")
    ).encode("utf-8")


def _profile() -> harness.Profile:
    return harness.Profile(
        roots=ROOTS,
        resources=(),
        autoexec=AUTOEXEC,
        ready_markers=(PASS_MARKER,),
        stable_markers=(PASS_MARKER,),
        failure_markers=(
            "STREAMS LIBRARY RABBIT PROVIDER LOAD FAIL",
            "COLD SOURCE LOAD FAIL",
            "Module not found",
            "Path component not found",
            "branch offset overflow",
            "EVALUATE depth limit exceeded",
            "dictionary full",
            "exception",
            "? (not found)",
        ),
        initial_files=((PROVIDER_IMAGE_PATH, _provider_bytes()),),
        linked=True,
        cold_source_packed=True,
        include_large_sample=False,
        total_sectors=4096,
    )


def _assert_static_contracts() -> None:
    profile = harness.PROFILES[PROFILE]
    capstone = harness.PROFILES["desktop-library-burrow-capstone"]
    deployed_provider = dict(capstone.cold_source_initial_files)[
        "c5-slrabbit.f.lz"
    ]

    assert profile.roots == ROOTS
    assert profile.linked is True
    assert profile.cold_source_packed is True
    assert profile.include_large_sample is False
    assert profile.total_sectors == 4096
    assert profile.audited_link_line_bytes is None
    assert profile.audited_initial_forth_line_bytes is None
    assert profile.initial_files == ((PROVIDER_IMAGE_PATH, _provider_bytes()),)
    assert profile.initial_files[0][1] == deployed_provider
    assert max(map(len, _provider_bytes().splitlines())) <= 255
    assert "SOURCE-EVALUATE-CHECKED" in AUTOEXEC
    assert "returned-status=" in AUTOEXEC
    assert "EVAL-TOKEN TYPE" in AUTOEXEC
    assert tuple(
        line.removeprefix("REQUIRE ")
        for line in AUTOEXEC.splitlines()
        if line.startswith("REQUIRE ")
    ) == ROOTS
    assert MAX_STEPS == 9_000_000_000


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--static-only", action="store_true")
    parser.add_argument("--timeout", type=float, default=DEFAULT_TIMEOUT)
    args = parser.parse_args()
    if args.timeout <= 0:
        parser.error("--timeout must be greater than zero")

    harness.PROFILES[PROFILE] = _profile()
    _assert_static_contracts()
    if args.static_only:
        print("STREAMS LIBRARY RABBIT PROVIDER LOAD STATIC PASS")
        return 0

    image = harness.build_image(PROFILE, IMAGE)
    ok = harness.smoke(
        PROFILE,
        image,
        cols=120,
        rows=34,
        max_steps=MAX_STEPS,
        timeout=args.timeout,
        ext_mem_mib=128,
    )
    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
