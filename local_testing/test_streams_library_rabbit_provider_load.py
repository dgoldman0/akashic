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
        ." STREAMS LIBRARY RABBIT PROVIDER SOURCE PASS"
    ELSE
        ." STREAMS LIBRARY RABBIT PROVIDER LOAD FAIL"
    THEN
    CR ." STREAMS LIBRARY RABBIT PROVIDER LOAD DONE" CR TX-FLUSH ;
_slrp-load
VARIABLE _slrp-slab-a
VARIABLE _slrp-slab-u
VARIABLE _slrp-slab-status
VARIABLE _slrp-init-status
VARIABLE _slrp-preflight-status
VARIABLE _slrp-preflight-detail
VARIABLE _slrp-preflight-depth
VARIABLE _slrp-slab-fails
VARIABLE _slrp-caller
VARIABLE _slrp-target
CREATE _slrp-storage-raw SLRGP-STORAGE-SIZE 7 + ALLOT
CREATE _slrp-context-raw SLRGP-SIZE 7 + ALLOT
CREATE _slrp-spec-raw SRBPROV-GRAPH-SPEC-SIZE 7 + ALLOT
CREATE _slrp-caller-desc-raw COMP-DESC 7 + ALLOT
CREATE _slrp-target-desc-raw COMP-DESC 7 + ALLOT
CREATE _slrp-facet RID-SIZE ALLOT
CREATE _slrp-practice RID-SIZE ALLOT
: _slrp-storage  ( -- storage ) _slrp-storage-raw 7 + -8 AND ;
: _slrp-context  ( -- context ) _slrp-context-raw 7 + -8 AND ;
: _slrp-spec  ( -- spec ) _slrp-spec-raw 7 + -8 AND ;
: _slrp-caller-desc  ( -- desc ) _slrp-caller-desc-raw 7 + -8 AND ;
: _slrp-target-desc  ( -- desc ) _slrp-target-desc-raw 7 + -8 AND ;
: _slrp-auth  ( -- decision ) 0 ;
: _slrp-spec-init  ( -- )
    _slrp-spec SRBPROV-GRAPH-SPEC-INIT
    1 _slrp-spec SRBPROV-SPEC.COLLECTION !
    1 _slrp-spec SRBPROV-SPEC.COLLECTION-REVISION !
    1 _slrp-spec SRBPROV-SPEC.REQUEST-DIGEST !
    1 _slrp-spec SRBPROV-SPEC.PEER-CAPACITY ! ;
: _slrp-slab-assert  ( flag -- )
    0= IF 1 _slrp-slab-fails +! THEN ;
: _slrp-slab-test  ( -- )
    DEPTH _slrp-depth !
    _slrp-storage SLRGP-STORAGE-INIT
    1 1 1 1 1 SLRGP-GRAPH-SLAB-BYTES
    DUP 0> DUP _slrp-slab-assert 0= IF DROP EXIT THEN
    DUP _slrp-slab-u ! ALLOCATE DUP IF
        2DROP 1 _slrp-slab-fails +! EXIT
    THEN
    DROP DUP _slrp-slab-a ! _slrp-slab-u @ 0 FILL
    _slrp-slab-a @ _slrp-slab-u @ 1 1 1 1 1 _slrp-storage
        SLRGP-STORAGE-BIND-SLAB
    DUP _slrp-slab-status ! SRBPROV-S-NONE = _slrp-slab-assert
    _slrp-storage SLRGP-STORAGE-BOUND? _slrp-slab-assert
    _slrp-storage SLRGP-GRAPH-BASELINE? _slrp-slab-assert

    _slrp-caller-desc COMP-DESC-INIT
    _slrp-target-desc COMP-DESC-INIT
    _slrp-caller-desc CINST-NEW DUP 0= _slrp-slab-assert
    DUP IF 2DROP EXIT THEN DROP _slrp-caller !
    _slrp-target-desc CINST-NEW DUP 0= _slrp-slab-assert
    DUP IF 2DROP _slrp-caller @ CINST-FREE 0 _slrp-caller ! EXIT THEN
    DROP _slrp-target !
    _slrp-facet RID-SIZE 0 FILL 1 _slrp-facet !
    _slrp-practice RID-SIZE 0 FILL 1 _slrp-practice !
    _slrp-context SLRGP-SIZE 0 FILL
    _slrp-storage _slrp-caller @ _slrp-target @ 1 2 3
    _slrp-facet _slrp-practice 1 1 1 ['] _slrp-auth _slrp-context
    4 5 6 _slrp-context SLRGP-INIT
    DUP _slrp-init-status ! SRBPROV-S-NONE =
    DUP _slrp-slab-assert IF
        _slrp-context SLRGP-VALID? _slrp-slab-assert
        _slrp-spec-init
        _slrp-spec SRBPROV-GRAPH-SPEC-VALID? _slrp-slab-assert
        DEPTH _slrp-preflight-depth !
        _slrp-spec _slrp-context _SLRGBLD-PREFLIGHT
        _slrp-preflight-detail ! _slrp-preflight-status !
        _slrp-preflight-status @ SRBPROV-S-NONE = _slrp-slab-assert
        _slrp-preflight-detail @ SRBPROV-D-NONE = _slrp-slab-assert
        DEPTH _slrp-preflight-depth @ = _slrp-slab-assert
        _slrp-context SLRGP-FINI SRBPROV-S-NONE = _slrp-slab-assert
    THEN
    _slrp-storage SLRGP-STORAGE-FINI
        SRBPROV-S-NONE = _slrp-slab-assert
    _slrp-target @ CINST-FREE 0 _slrp-target !
    _slrp-caller @ CINST-FREE 0 _slrp-caller !
    _slrp-slab-a @ FREE
    0 _slrp-slab-a ! 0 _slrp-slab-u !
    DEPTH _slrp-depth @ = _slrp-slab-assert ;
: _slrp-slab-run  ( -- )
    0 _slrp-slab-fails ! 0 _slrp-slab-status ! 0 _slrp-init-status !
    0 _slrp-preflight-status ! 0 _slrp-preflight-detail !
    0 _slrp-caller ! 0 _slrp-target !
    _slrp-slab-test
    ." STREAMS LIBRARY RABBIT PROVIDER SLAB status="
        _slrp-slab-status @ . ." fails=" _slrp-slab-fails @ .
        ." init=" _slrp-init-status @ .
        ." preflight=" _slrp-preflight-status @ .
        ." detail=" _slrp-preflight-detail @ .
        ." depth=" DEPTH . CR TX-FLUSH
    _slrp-slab-fails @ 0= IF
        ." STREAMS LIBRARY RABBIT PROVIDER LOAD PASS"
    ELSE
        ." STREAMS LIBRARY RABBIT PROVIDER SLAB FAIL"
    THEN
    CR ." STREAMS LIBRARY RABBIT PROVIDER SLAB DONE" CR TX-FLUSH ;
_slrp-slab-run
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
    provider_source = PROVIDER.read_text(encoding="utf-8")
    queue_planner = provider_source.split(": _SLRSL-ADD-QUEUE", 1)[1].split(
        ";", 1
    )[0]
    queue_binder = provider_source.split(": _SLRSL-BIND-QUEUE", 1)[1].split(
        ";", 1
    )[0]
    acquire_preflight = provider_source.split(
        ": _SLRGBLD-PREFLIGHT", 1
    )[1].split(";", 1)[0]
    lease_validator = provider_source.split(
        ": _SLRGP-LEASE-STATIC?", 1
    )[1].split(";", 1)[0]

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
    assert "SLRGP-GRAPH-SLAB-BYTES" in AUTOEXEC
    assert "SLRGP-STORAGE-BIND-SLAB" in AUTOEXEC
    assert "SLRGP-INIT" in AUTOEXEC
    assert "SLRGP-FINI" in AUTOEXEC
    assert "SLRGP-STORAGE-FINI" in AUTOEXEC
    assert "DUP _SLRSL-WIRE !" not in queue_planner
    assert "_SLRSL-WIRE !" in queue_planner
    assert "_SLRSL-QUEUE ! _SLRSL-WIRE !" in queue_binder
    assert queue_binder.count("_SLRSL-QUEUE @") == 3
    assert "DUP 1 <> IF" not in acquire_preflight
    assert "1 <> IF" in acquire_preflight
    assert (
        "_SLRGBLD-PEERS @\n"
        "    _SLRGBLD-STORAGE @ SLRGS.BURROW-ROWS SLRGB.U @ U>"
    ) in acquire_preflight
    assert "_SLRGBLD-PREFLIGHT" in AUTOEXEC
    assert "DEPTH _slrp-preflight-depth @ = _slrp-slab-assert" in AUTOEXEC
    assert "STREAMS-RABBIT-CONNECTOR-S-OK = AND NIP" in lease_validator
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
