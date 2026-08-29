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
LIBRARY_CAPABILITIES = (
    LOCAL_TESTING.parent / "akashic/tui/applets/library/capabilities.f"
)
PROVIDER_IMAGE_PATH = "local_testing/streams-lib-rabbit.f"
ROOTS = (
    "tui/applets/library/capabilities.f",
    "tui/applets/streams/rabbit-capabilities.f",
    "tui/applets/streams/rabbit-library-profile.f",
    "net/transports/memory-duplex.f",
    "tui/applets/streams/rabbit-connector.f",
)
MAX_STEPS = harness.DEFAULT_SMOKE_MAX_STEPS
DEFAULT_TIMEOUT = 300.0
PASS_MARKER = "STREAMS LIBRARY RABBIT PROVIDER LOAD PASS"

AUTOEXEC = r"""\ autoexec.f - checked Checkpoint-5 provider compile
ENTER-USERLAND
REQUIRE tui/applets/library/capabilities.f
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
VARIABLE _slrp-lease
VARIABLE _slrp-acquire-status
VARIABLE _slrp-acquire-detail
VARIABLE _slrp-open-status
VARIABLE _slrp-open-detail
VARIABLE _slrp-cleanup-status
VARIABLE _slrp-cleanup-detail
VARIABLE _slrp-profile-binding
VARIABLE _slrp-query-cap-ok
VARIABLE _slrp-read-cap-ok
VARIABLE _slrp-query-common
VARIABLE _slrp-read-common
VARIABLE _slrp-query-fields
VARIABLE _slrp-read-fields
VARIABLE _slrp-slab-fails
VARIABLE _slrp-caller
VARIABLE _slrp-target
VARIABLE _slrp-registry
VARIABLE _slrp-bus
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
: _slrp-auth  ( frame owner evidence facet entry mount context -- decision )
    2DROP 2DROP 2DROP DROP 0 ;
: _slrp-field-mask  ( schema query? -- mask )
    >R 0
    S" collection" 3 PICK _SRLP-REQUIRED-FIELD IF 1 OR THEN
    S" collection_domain_revision" 3 PICK _SRLP-REQUIRED-FIELD IF 2 OR THEN
    S" request_digest" 3 PICK _SRLP-REQUIRED-FIELD IF 4 OR THEN
    R@ IF S" after" ELSE S" resource" THEN
        3 PICK _SRLP-REQUIRED-FIELD IF 8 OR THEN
    R> IF S" limit" ELSE S" domain_revision" THEN
        3 PICK _SRLP-REQUIRED-FIELD IF 16 OR THEN
    NIP ;
: _slrp-desc-init  ( id-a id-u desc -- )
    >R R@ COMP-DESC-INIT
    R@ COMP.ID-U ! R@ COMP.ID-A !
    S" 1.0.0" R@ COMP.VERSION-U ! R> COMP.VERSION-A ! ;
: _slrp-spec-init  ( -- )
    _slrp-spec SRBPROV-GRAPH-SPEC-INIT
    1 _slrp-spec SRBPROV-SPEC.COLLECTION !
    1 _slrp-spec SRBPROV-SPEC.COLLECTION-REVISION !
    1 _slrp-spec SRBPROV-SPEC.REQUEST-DIGEST !
    1 _slrp-spec SRBPROV-SPEC.PEER-CAPACITY ! ;
: _slrp-slab-assert  ( flag -- )
    0= IF 1 _slrp-slab-fails +! THEN ;
64 CONSTANT _SLRP-CLEANUP-POLL-MAX
: _slrp-cleanup-ok?  ( -- flag )
    _slrp-cleanup-status @ SRBPROV-S-NONE =
    _slrp-cleanup-detail @ SRBPROV-D-NONE = AND ;
: _slrp-cancel-retained  ( -- flag )
    _SLRP-CLEANUP-POLL-MAX 0 ?DO
        _slrp-lease @ _slrp-context SLRGP-PROVIDER SRBPROV-CANCEL
        _slrp-cleanup-detail ! _slrp-cleanup-status !
        _slrp-cleanup-status @ SRBPROV-S-PENDING <> IF
            _slrp-cleanup-ok? UNLOOP EXIT
        THEN
    LOOP 0 ;
: _slrp-finalize-retained  ( -- flag )
    _SLRP-CLEANUP-POLL-MAX 0 ?DO
        _slrp-lease @ _slrp-context SLRGP-PROVIDER SRBPROV-FINALIZE
        _slrp-cleanup-detail ! _slrp-cleanup-status !
        _slrp-cleanup-status @ SRBPROV-S-PENDING <> IF
            _slrp-cleanup-ok? UNLOOP EXIT
        THEN
    LOOP 0 ;
: _slrp-release-only-retained  ( -- flag )
    _SLRP-CLEANUP-POLL-MAX 0 ?DO
        _slrp-lease @ _slrp-context SLRGP-PROVIDER SRBPROV-RELEASE
        _slrp-cleanup-detail ! _slrp-cleanup-status !
        _slrp-cleanup-status @ SRBPROV-S-PENDING <> IF
            _slrp-cleanup-ok? DUP IF 0 _slrp-lease ! THEN
            UNLOOP EXIT
        THEN
    LOOP 0 ;
: _slrp-release-retained  ( -- flag )
    _slrp-lease @ 0= IF -1 EXIT THEN
    _slrp-cancel-retained 0= IF 0 EXIT THEN
    _slrp-finalize-retained 0= IF 0 EXIT THEN
    _slrp-release-only-retained ;
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

    S" org.akashic.test.rabbit-caller" _slrp-caller-desc _slrp-desc-init
    S" org.akashic.test.rabbit-library" _slrp-target-desc _slrp-desc-init
    LIBRARY-APPLET-CAPABILITIES-SETUP
    LIBRARY-APPLET-CAPABILITIES 7 AND 0= _slrp-slab-assert
    LIBRARY-READ-V1-QUERY-CAPABILITY$
        LIBRARY-CAP-DOCUMENT-QUERY _SRLP-CAP-COMMON?
        _slrp-query-common !
    LIBRARY-CAP-DOCUMENT-QUERY CAP.IN-SCHEMA @ -1
        _slrp-field-mask _slrp-query-fields !
    LIBRARY-READ-V1-READ-CAPABILITY$
        LIBRARY-CAP-DOCUMENT-READ _SRLP-CAP-COMMON?
        _slrp-read-common !
    LIBRARY-CAP-DOCUMENT-READ CAP.IN-SCHEMA @ 0
        _slrp-field-mask _slrp-read-fields !
    LIBRARY-CAP-DOCUMENT-QUERY _SRLP-QUERY-CAP?
        _slrp-query-cap-ok !
    LIBRARY-CAP-DOCUMENT-READ _SRLP-READ-CAP?
        _slrp-read-cap-ok !
    _slrp-query-common @ _slrp-slab-assert
    _slrp-read-common @ _slrp-slab-assert
    _slrp-query-fields @ 31 = _slrp-slab-assert
    _slrp-read-fields @ 31 = _slrp-slab-assert
    _slrp-query-cap-ok @ _slrp-slab-assert
    _slrp-read-cap-ok @ _slrp-slab-assert
    LIBRARY-APPLET-CAPABILITIES _slrp-target-desc COMP.CAPS-A !
    LIBRARY-APPLET-CAPABILITY-COUNT _slrp-target-desc COMP.CAPS-N !
    _slrp-caller-desc CINST-NEW DUP 0= _slrp-slab-assert
    DUP IF 2DROP EXIT THEN DROP _slrp-caller !
    _slrp-target-desc CINST-NEW DUP 0= _slrp-slab-assert
    DUP IF 2DROP _slrp-caller @ CINST-FREE 0 _slrp-caller ! EXIT THEN
    DROP _slrp-target !
    CREG-NEW DUP IF
        2DROP 1 _slrp-slab-fails +!
        _slrp-target @ CINST-FREE _slrp-caller @ CINST-FREE
        0 _slrp-target ! 0 _slrp-caller ! EXIT
    THEN DROP _slrp-registry !
    _slrp-caller-desc _slrp-registry @ CREG-TYPE+ 0= _slrp-slab-assert
    _slrp-target-desc _slrp-registry @ CREG-TYPE+ 0= _slrp-slab-assert
    _slrp-caller @ _slrp-registry @ CREG-INST+ 0= _slrp-slab-assert
    _slrp-target @ _slrp-registry @ CREG-INST+ 0= _slrp-slab-assert
    _slrp-registry @ 0 CBUS-NEW DUP IF
        2DROP 1 _slrp-slab-fails +! EXIT
    THEN DROP _slrp-bus !
    _slrp-facet RID-SIZE 0 FILL 1 _slrp-facet !
    _slrp-practice RID-SIZE 0 FILL 1 _slrp-practice !
    _slrp-context SLRGP-SIZE 0 FILL
    _slrp-storage _slrp-caller @ _slrp-target @ _slrp-bus @
    LIBRARY-CAP-DOCUMENT-QUERY LIBRARY-CAP-DOCUMENT-READ
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

        DEPTH _slrp-preflight-depth !
        _slrp-spec _slrp-context SLRGP-PROVIDER SRBPROV-ACQUIRE
        _slrp-acquire-detail ! _slrp-acquire-status ! _slrp-lease !
        _slrp-lease @ 0<> _slrp-slab-assert
        _slrp-acquire-status @ SRBPROV-S-NONE = _slrp-slab-assert
        _slrp-acquire-detail @ SRBPROV-D-NONE = _slrp-slab-assert
        DEPTH _slrp-preflight-depth @ = _slrp-slab-assert
        _slrp-context SLRGP.STORAGE @ SLRGS.PROFILE @
            STREAMS-RABBIT-LIBRARY-PROFILE-BINDING-VALID?
            _slrp-profile-binding !
        _slrp-profile-binding @ _slrp-slab-assert
        _slrp-acquire-status @ SRBPROV-S-NONE =
        _slrp-acquire-detail @ SRBPROV-D-NONE = AND
        _slrp-lease @ 0<> AND IF
            _slrp-lease @ _slrp-context SLRGP-PROVIDER SRBPROV-OPEN
            _slrp-open-detail ! _slrp-open-status !
            _slrp-open-status @ SRBPROV-S-NONE = _slrp-slab-assert
            _slrp-open-detail @ SRBPROV-D-NONE = _slrp-slab-assert
        THEN
        _slrp-release-retained DUP _slrp-slab-assert 0= IF EXIT THEN
        _slrp-context SLRGP-FINI DUP SRBPROV-S-NONE =
            _slrp-slab-assert
        SRBPROV-S-NONE <> IF EXIT THEN
    THEN
    _slrp-storage SLRGP-STORAGE-FINI DUP SRBPROV-S-NONE =
        _slrp-slab-assert
    SRBPROV-S-NONE <> IF EXIT THEN
    _slrp-bus @ CBUS.COUNT @ DUP 0= _slrp-slab-assert IF EXIT THEN
    _slrp-bus @ CBUS-FREE 0 _slrp-bus !
    _slrp-target @ _slrp-registry @ CREG-INST-
        DUP 0= _slrp-slab-assert IF EXIT THEN
    _slrp-target @ CINST-FREE 0 _slrp-target !
    _slrp-caller @ _slrp-registry @ CREG-INST-
        DUP 0= _slrp-slab-assert IF EXIT THEN
    _slrp-caller @ CINST-FREE 0 _slrp-caller !
    _slrp-registry @ CREG-FREE 0 _slrp-registry !
    _slrp-slab-a @ FREE
    0 _slrp-slab-a ! 0 _slrp-slab-u !
    DEPTH _slrp-depth @ = _slrp-slab-assert ;
: _slrp-slab-run  ( -- )
    0 _slrp-slab-fails ! 0 _slrp-slab-status ! 0 _slrp-init-status !
    0 _slrp-preflight-status ! 0 _slrp-preflight-detail !
    0 _slrp-lease ! 0 _slrp-acquire-status ! 0 _slrp-acquire-detail !
    0 _slrp-open-status ! 0 _slrp-open-detail !
    0 _slrp-cleanup-status ! 0 _slrp-cleanup-detail !
    0 _slrp-profile-binding !
    0 _slrp-query-cap-ok ! 0 _slrp-read-cap-ok !
    0 _slrp-query-common ! 0 _slrp-read-common !
    0 _slrp-query-fields ! 0 _slrp-read-fields !
    0 _slrp-caller ! 0 _slrp-target !
    0 _slrp-registry ! 0 _slrp-bus !
    _slrp-slab-test
    ." STREAMS LIBRARY RABBIT PROVIDER SLAB status="
        _slrp-slab-status @ . ." fails=" _slrp-slab-fails @ .
        ." init=" _slrp-init-status @ .
        ." preflight=" _slrp-preflight-status @ .
        ." detail=" _slrp-preflight-detail @ .
        ." acquire=" _slrp-acquire-status @ .
        ." acquire-detail=" _slrp-acquire-detail @ .
        ." open=" _slrp-open-status @ .
        ." open-detail=" _slrp-open-detail @ .
        ." query-cap=" _slrp-query-cap-ok @ .
        ." read-cap=" _slrp-read-cap-ok @ .
        ." query-common=" _slrp-query-common @ .
        ." read-common=" _slrp-read-common @ .
        ." query-fields=" _slrp-query-fields @ .
        ." read-fields=" _slrp-read-fields @ .
        ." profile-binding=" _slrp-profile-binding @ .
        ." cleanup=" _slrp-cleanup-status @ .
        ." cleanup-detail=" _slrp-cleanup-detail @ .
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
            "STREAMS LIBRARY RABBIT PROVIDER SLAB FAIL",
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
        cold_source_codec=harness.COLD_SOURCE_CODEC_LZSS,
        include_large_sample=False,
        total_sectors=4096,
    )


def _assert_static_contracts() -> None:
    profile = harness.PROFILES[PROFILE]
    capstone = harness.PROFILES["desktop-library-burrow-capstone"]
    deployed_provider = dict(capstone.cold_source_initial_files)[
        "c5-slrabbit.f.src"
    ]
    provider_source = PROVIDER.read_text(encoding="utf-8")
    library_capabilities = LIBRARY_CAPABILITIES.read_text(encoding="utf-8")
    queue_planner = provider_source.split(": _SLRSL-ADD-QUEUE", 1)[1].split(
        ";", 1
    )[0]
    queue_binder = provider_source.split(": _SLRSL-BIND-QUEUE", 1)[1].split(
        ";", 1
    )[0]
    queue_finalizer = provider_source.split(": _SLRGP-FINI-QUEUE", 1)[1].split(
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
    assert profile.cold_source_codec == harness.COLD_SOURCE_CODEC_LZSS
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
    assert "CREATE _LIBRARY-APPLET-CAPABILITIES-RAW" in library_capabilities
    assert "CAP-DESC * 7 + ALLOT" in library_capabilities
    assert "_LIBRARY-APPLET-CAPABILITIES-RAW 7 + -8 AND" in (
        library_capabilities
    )
    assert "LIBRARY-APPLET-CAPABILITIES 7 AND 0=" in AUTOEXEC
    assert "SLRGP-STORAGE-BIND-SLAB" in AUTOEXEC
    assert "SLRGP-INIT" in AUTOEXEC
    assert "SLRGP-FINI" in AUTOEXEC
    assert "SLRGP-STORAGE-FINI" in AUTOEXEC
    assert "DUP _SLRSL-WIRE !" not in queue_planner
    assert "_SLRSL-WIRE !" in queue_planner
    assert "_SLRSL-QUEUE ! _SLRSL-WIRE !" in queue_binder
    assert queue_binder.count("_SLRSL-QUEUE @") == 3
    assert "_SLRGFIN-QB @ SLRGQ.QUEUE @ RCONN-TXQ-FINI" in (
        queue_finalizer
    )
    assert "DUP 1 <> IF" not in acquire_preflight
    assert "1 <> IF" in acquire_preflight
    assert (
        "_SLRGBLD-PEERS @\n"
        "    _SLRGBLD-STORAGE @ SLRGS.BURROW-ROWS SLRGB.U @ U>"
    ) in acquire_preflight
    assert "_SLRGBLD-PREFLIGHT" in AUTOEXEC
    assert "DEPTH _slrp-preflight-depth @ = _slrp-slab-assert" in AUTOEXEC
    assert "SRBPROV-ACQUIRE" in AUTOEXEC
    assert "SRBPROV-OPEN" in AUTOEXEC
    assert "SRBPROV-CANCEL" in AUTOEXEC
    assert "SRBPROV-FINALIZE" in AUTOEXEC
    assert "SRBPROV-RELEASE" in AUTOEXEC
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
