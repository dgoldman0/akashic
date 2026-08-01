#!/usr/bin/env python3
"""Qualify the concrete authenticated Streams provider and app boundary."""

from __future__ import annotations

import argparse
import re
import sys
from dataclasses import dataclass
from pathlib import Path


LOCAL_TESTING = Path(__file__).resolve().parent
ROOT = LOCAL_TESTING.parent
SOURCE_ROOT = ROOT / "akashic"
sys.path.insert(0, str(LOCAL_TESTING))

import akashic_tui as harness  # noqa: E402
import test_at_xrpc_auth_read as auth_read  # noqa: E402
import test_at_xrpc_exchange as xrpc_exchange  # noqa: E402
from forth_dependencies import dependency_order  # noqa: E402
from test_oauth2_p256_key import P256_JWK_DOUBLES  # noqa: E402


PROFILE = "at-authenticated-provider-vertical"
IMAGE = Path("/tmp/akashic-at-authenticated-provider-vertical.img")
BOOT_MARKER = "AT AUTH PROVIDER USERLAND READY"
PASS_MARKER = "AT AUTH PROVIDER VERTICAL PASS"
MAX_PHASE_STEPS = 180_000_000
EXT_MEM_SIZE = 128 << 20
NUM_CORES = 1
LINKED = False
COMPILE_CHECKPOINT_BYTES = 12 * 1024
BUNDLE_BYTES = 32 * 1024
CHECKPOINTS_PER_BUNDLE = 2
# The deterministic fake PDS completes this request in four cooperative XIO
# polls.  Keep each phase below the unchanged emulator step ceiling without
# turning the owner's broader poll guard into dozens of empty test stages.
POST_DRIVE_CHECKPOINTS = 2


@dataclass(frozen=True)
class SourceBundle:
    guest: str
    payload: bytes
    stages: tuple[tuple[str, str], ...]

PROVIDER = (
    SOURCE_ROOT
    / "tui"
    / "applets"
    / "streams"
    / "atproto-authenticated-provider.f"
)
INTERFACE = (
    SOURCE_ROOT
    / "tui"
    / "applets"
    / "streams"
    / "authenticated-provider.f"
)
STREAMS = SOURCE_ROOT / "tui" / "applets" / "streams" / "streams.f"
STREAMS_ONLINE = (
    SOURCE_ROOT / "tui" / "applets" / "streams" / "streams-online.f"
)
CONTRACT = LOCAL_TESTING / "at-authenticated-provider-vertical.f"
BIDIRECTIONAL_FIXTURE = LOCAL_TESTING / "at-bidirectional-vertical.f"
TIMELINE = LOCAL_TESTING / "fixtures" / "atproto" / "timeline.json"
TIMELINE_GUEST = "atbv-feed.json"

REPLACED_CRYPTO_MODULES = auth_read.REPLACED_CRYPTO_MODULES
REPLACED_TRANSPORT_MODULES = frozenset({"net/transports/kdos-tls.f"})
TRANSPORT_DOUBLE = xrpc_exchange.TRANSPORT_DOUBLE + r"""

\ The native networking module normally owns this validator.  The concrete
\ gate replaces that whole module at the transport boundary, so retain its
\ exact hostname admission needed by the public provider composition.
253 CONSTANT DNS-NAME-MAX
VARIABLE _SATPT-DNV-A
VARIABLE _SATPT-DNV-U
VARIABLE _SATPT-DNV-WILDCARD
VARIABLE _SATPT-DNV-LABEL-U
VARIABLE _SATPT-DNV-DOTS

: _SATPT-DNV-ALNUM?  ( c -- flag )
    DUP 65 91 WITHIN OVER 97 123 WITHIN OR SWAP 48 58 WITHIN OR ;

: DNS-NAME-VALID?  ( addr len allow-wildcard -- flag )
    _SATPT-DNV-WILDCARD ! _SATPT-DNV-U ! _SATPT-DNV-A !
    _SATPT-DNV-U @ 1 < _SATPT-DNV-U @ DNS-NAME-MAX > OR IF
        FALSE EXIT
    THEN
    0 _SATPT-DNV-LABEL-U ! 0 _SATPT-DNV-DOTS !
    _SATPT-DNV-U @ 0 DO
        _SATPT-DNV-A @ I + C@
        DUP 46 = IF
            DROP
            _SATPT-DNV-LABEL-U @ 0= IF FALSE UNLOOP EXIT THEN
            _SATPT-DNV-A @ I + 1- C@ 45 = IF FALSE UNLOOP EXIT THEN
            0 _SATPT-DNV-LABEL-U ! 1 _SATPT-DNV-DOTS +!
        ELSE
            DUP 42 = IF
                DROP
                _SATPT-DNV-WILDCARD @ 0= I 0<> OR IF
                    FALSE UNLOOP EXIT
                THEN
                _SATPT-DNV-U @ 3 <
                _SATPT-DNV-A @ 1+ C@ 46 <> OR IF
                    FALSE UNLOOP EXIT
                THEN
            ELSE
                DUP _SATPT-DNV-ALNUM? SWAP 45 = OR 0= IF
                    FALSE UNLOOP EXIT
                THEN
                _SATPT-DNV-LABEL-U @ 0=
                _SATPT-DNV-A @ I + C@ 45 = AND IF
                    FALSE UNLOOP EXIT
                THEN
            THEN
            1 _SATPT-DNV-LABEL-U +!
            _SATPT-DNV-LABEL-U @ 63 > IF FALSE UNLOOP EXIT THEN
        THEN
    LOOP
    _SATPT-DNV-LABEL-U @ 0= IF FALSE EXIT THEN
    _SATPT-DNV-A @ _SATPT-DNV-U @ + 1- C@ 45 = IF FALSE EXIT THEN
    _SATPT-DNV-A @ C@ 42 = _SATPT-DNV-DOTS @ 2 < AND IF FALSE EXIT THEN
    TRUE ;

\ The configured syndication provider inspects cleanup state and owns the
\ heap descriptor even when this gate never starts its transport.  Sharing
\ the always-zero closed-state cell is sufficient for the deterministic seam.
: KDOSTLS.CLEANUP-ERROR  ( adapter -- field ) KDOSTLS.STATE ;
: KDOSTLS-FREE  ( adapter -- )
    DUP 0= IF DROP EXIT THEN
    DUP KDOSTLS-SIZE 0 FILL FREE ;
"""

RAW_MODULES = dependency_order(
    SOURCE_ROOT,
    (
        "tui/applets/streams/atproto-authenticated-provider.f",
        "tui/applets/streams/streams-online.f",
        "utils/fs/vfs.f",
    ),
)


def _module_items() -> tuple[auth_read.LoadItem, ...]:
    """Preserve production dependency order around deterministic seams."""
    items: list[auth_read.LoadItem] = []
    sequence = 0
    crypto_seam_inserted = False
    transport_seam_inserted = False
    for module in RAW_MODULES:
        if module in REPLACED_CRYPTO_MODULES:
            continue
        if module in REPLACED_TRANSPORT_MODULES:
            items.append(
                auth_read.LoadItem(
                    name="deterministic-transport-seam",
                    guest="local_testing/satpv-net.f",
                    marker="AT AUTH PROVIDER TRANSPORT SEAM READY",
                    inline=TRANSPORT_DOUBLE,
                    remove_requires=False,
                )
            )
            transport_seam_inserted = True
            continue
        if module == "security/oauth2/key-p256.f":
            items.append(
                auth_read.LoadItem(
                    name="deterministic-crypto-seam",
                    guest="local_testing/satpv-seam.f",
                    marker="AT AUTH PROVIDER CRYPTO SEAM READY",
                    inline=P256_JWK_DOUBLES,
                    remove_requires=False,
                )
            )
            crypto_seam_inserted = True
        sequence += 1
        items.append(
            auth_read.LoadItem(
                name=f"module-{sequence:02d}",
                guest=f"local_testing/satpv-m{sequence:02d}.f",
                marker=f"AT AUTH PROVIDER MODULE {sequence:02d} READY",
                source=SOURCE_ROOT / module,
            )
        )
    assert crypto_seam_inserted
    assert transport_seam_inserted
    return tuple(items)


MODULE_ITEMS = _module_items()
FIXTURE_ITEMS = (
    auth_read.LoadItem(
        name="profile-fixture",
        guest="local_testing/satpv-prof.f",
        marker="AT AUTH PROVIDER PROFILE FIXTURE READY",
        source=auth_read.PROFILE_FIXTURE,
        remove_requires=False,
    ),
    auth_read.LoadItem(
        name="client-fixture",
        guest="local_testing/satpv-client.f",
        marker="AT AUTH PROVIDER CLIENT FIXTURE READY",
        source=auth_read.CLIENT_FIXTURE,
        remove_requires=False,
    ),
    auth_read.LoadItem(
        name="authenticated-session-fixture",
        guest="local_testing/satpv-auth.f",
        marker="AT AUTH PROVIDER SESSION FIXTURE READY",
        source=auth_read.CONTRACT,
    ),
    auth_read.LoadItem(
        name="bidirectional-peer-fixture",
        guest="local_testing/satpv-peer.f",
        marker="AT AUTH PROVIDER PEER FIXTURE READY",
        source=BIDIRECTIONAL_FIXTURE,
    ),
    auth_read.LoadItem(
        name="provider-vertical-fixture",
        guest="local_testing/satpv-test.f",
        marker="AT AUTH PROVIDER FIXTURE READY",
        source=CONTRACT,
    ),
)


def _bundle_source(item: auth_read.LoadItem) -> bytes:
    if item.inline is not None:
        source = item.inline
    else:
        assert item.source is not None
        source = item.source.read_text(encoding="utf-8")
    return harness._minify_forth(  # noqa: SLF001
        source,
        remove_requires=True,
    ).encode("utf-8")


def _structural_tokens(text: str) -> tuple[str, ...]:
    """Discard comment/string bodies before recognizing Forth structure."""
    tokens = harness._forth_line_tokens(text)  # noqa: SLF001
    structural: list[str] = []
    in_parenthesis = False
    in_string = False
    for token in tokens:
        if in_parenthesis:
            if token.endswith(")"):
                in_parenthesis = False
            continue
        if in_string:
            if token.endswith('"'):
                in_string = False
            continue
        upper = token.upper()
        if token.startswith("(") or upper == ".(":
            in_parenthesis = not token.endswith(")")
            continue
        if upper in {'S"', '."', 'C"', 'ABORT"'}:
            in_string = True
            continue
        structural.append(token)
    return tuple(structural)


def _safe_top_level_boundary(
    tokens: tuple[str, ...],
    *,
    ended_definition: bool,
    closed_conditional: bool,
) -> bool:
    """Recognize declarations and complete evaluator control structures."""
    if ended_definition or closed_conditional:
        return True
    if tokens and tokens[-1].upper() == "C,":
        return True
    upper = {token.upper() for token in tokens}
    return bool(
        upper
        & {
            "CONSTANT",
            "2CONSTANT",
            "VARIABLE",
            "2VARIABLE",
            "FVARIABLE",
            "VALUE",
            "2VALUE",
            "CREATE",
            "ALLOT",
            "PROVIDED",
            "DEFER",
        }
    )


def _top_level_units(payload: bytes) -> tuple[bytes, ...]:
    """Split only after a complete definition, conditional, or declaration."""
    units: list[bytearray] = []
    unit = bytearray()
    definition_depth = 0
    conditional_depth = 0
    for line in payload.splitlines(keepends=True):
        unit.extend(line)
        text = line.decode("utf-8").rstrip("\r\n")
        tokens = _structural_tokens(text)
        ended_definition = False
        closed_conditional = False
        if tokens and (
            tokens[0] == ":" or tokens[0].upper() == ":NONAME"
        ):
            definition_depth = 1
        if definition_depth and any(
            token == ";"
            and (
                index == 0
                or tokens[index - 1].upper() not in {"CHAR", "[CHAR]"}
            )
            for index, token in enumerate(tokens)
        ):
            definition_depth = 0
            ended_definition = True
        for token in tokens:
            upper = token.upper()
            if upper == "[IF]":
                conditional_depth += 1
            elif upper == "[THEN]" and conditional_depth:
                conditional_depth -= 1
                if conditional_depth == 0:
                    closed_conditional = True
        if (
            definition_depth == 0
            and conditional_depth == 0
            and _safe_top_level_boundary(
                tokens,
                ended_definition=ended_definition,
                closed_conditional=closed_conditional,
            )
        ):
            units.append(unit)
            unit = bytearray()
    if unit:
        if definition_depth or conditional_depth:
            raise RuntimeError("Prepared provider source ends inside a unit")
        units.append(unit)
    return tuple(bytes(source_unit) for source_unit in units)


def _source_fragments() -> tuple[bytes, ...]:
    """Pack complete top-level units into bounded compile checkpoints."""
    fragments: list[bytes] = []
    current = bytearray()
    for item in (*MODULE_ITEMS, *FIXTURE_ITEMS):
        for source_unit in _top_level_units(_bundle_source(item)):
            if len(source_unit) > COMPILE_CHECKPOINT_BYTES:
                raise RuntimeError(
                    f"authenticated provider source unit too large: {item.name}"
                )
            if (
                current
                and len(current) + len(source_unit)
                > COMPILE_CHECKPOINT_BYTES
            ):
                fragments.append(bytes(current))
                current.clear()
            current.extend(source_unit)
    if current:
        fragments.append(bytes(current))
    return tuple(fragments)


SOURCE_FRAGMENTS = _source_fragments()


def _bundle_marker(index: int) -> str:
    return f"AT AUTH PROVIDER BUNDLE {index:02d} READY"


def _internal_marker(index: int, part: int) -> str:
    return f"AT AUTH PROVIDER BUNDLE {index:02d} PART {part:02d} READY"


def _source_bundles() -> tuple[SourceBundle, ...]:
    """Pair checkpoints so the image remains below the MP64FS entry limit."""
    bundles: list[SourceBundle] = []
    for offset in range(0, len(SOURCE_FRAGMENTS), CHECKPOINTS_PER_BUNDLE):
        index = len(bundles) + 1
        fragments = SOURCE_FRAGMENTS[
            offset : offset + CHECKPOINTS_PER_BUNDLE
        ]
        payload = bytearray()
        stages: list[tuple[str, str]] = []
        for part, fragment in enumerate(fragments, start=1):
            payload.extend(fragment)
            if part == len(fragments):
                continue
            marker = _internal_marker(index, part)
            stages.append((f"bundle-{index:02d}-part-{part:02d}", marker))
            payload.extend(
                (
                    "\nDEPTH IF .\" AT AUTH PROVIDER LOAD STACK FAIL "
                    f"bundle-{index:02d}-part-{part:02d}"
                    "\" CR TX-FLUSH THEN\n"
                    f'." {marker}" CR TX-FLUSH\nKEY DROP\n'
                ).encode("utf-8")
            )
        stages.append((f"bundle-{index:02d}", _bundle_marker(index)))
        coalesced = harness._coalesce_audited_forth_lines(  # noqa: SLF001
            bytes(payload),
            harness.MEGAPAD_EVALUATE_SOURCE_MAX_BYTES,
        )
        if len(coalesced) > BUNDLE_BYTES:
            raise RuntimeError(
                f"authenticated provider bundle too large: bundle {index}"
            )
        bundles.append(
            SourceBundle(
                guest=f"local_testing/satpv-b{index:02d}.f",
                payload=coalesced,
                stages=tuple(stages),
            )
        )
    return tuple(bundles)


BUNDLES = _source_bundles()
BUNDLE_FILES = tuple((bundle.guest, bundle.payload) for bundle in BUNDLES)

POST_DRIVE_STAGES = tuple(
    (
        f"delivered-post-drive-{index:02d}",
        "_SATPT-POST-DRIVE-CHUNK",
        f"AT AUTH PROVIDER POST DRIVE {index:02d} READY",
    )
    for index in range(1, POST_DRIVE_CHECKPOINTS + 1)
)


RUNTIME_STAGES = (
    ("fixture-load", "_ATBV-LOAD", "AT AUTH PROVIDER DOCUMENT READY"),
    ("setup", "_ATXR-SETUP", "AT AUTH PROVIDER AUTH SETUP READY"),
    ("provision", "_ATXR-PROVISION", "AT AUTH PROVIDER KEY READY"),
    ("install", "_ATXR-INSTALL", "AT AUTH PROVIDER SESSION READY"),
    ("owner-restart", "_ATXR-RESTART", "AT AUTH PROVIDER REOPEN READY"),
    ("provider-setup", "_SATPT-SETUP", "AT AUTH PROVIDER SETUP READY"),
    ("authenticated-feed", "_SATPT-FEED", "AT AUTH PROVIDER FEED READY"),
    (
        "repeat-feed",
        "_SATPT-FEED-REPEAT",
        "AT AUTH PROVIDER REPEAT FEED READY",
    ),
    (
        "stale-feed",
        "_SATPT-STALE-FEED",
        "AT AUTH PROVIDER STALE FEED READY",
    ),
    (
        "failed-publish",
        "_SATPT-FAILED-PUBLISH",
        "AT AUTH PROVIDER FAILED PUBLISH READY",
    ),
    (
        "delivered-post-start",
        "_SATPT-POST-START",
        "AT AUTH PROVIDER POST START READY",
    ),
    (
        "delivered-post-drive-begin",
        "_SATPT-POST-DRIVE-FIRST",
        "AT AUTH PROVIDER POST DRIVE BEGIN READY",
    ),
    *POST_DRIVE_STAGES,
    (
        "delivered-post-drive-finish",
        "_SATPT-POST-DRIVE",
        "AT AUTH PROVIDER POST DRIVE READY",
    ),
    (
        "delivered-post-finish",
        "_SATPT-POST-FINISH",
        "AT AUTH PROVIDER POST READY",
    ),
    (
        "mutation-cancel",
        "_SATPT-POST-MUTATION-CANCEL",
        "AT AUTH PROVIDER MUTATION CANCEL READY",
    ),
    (
        "close-active",
        "_SATPT-CLOSE-ACTIVE",
        "AT AUTH PROVIDER ACTIVE CLOSE READY",
    ),
    ("release", "_SATPT-RELEASE", "AT AUTH PROVIDER RELEASE READY"),
    ("finish", "_SATPT-FINISH", PASS_MARKER),
)

FAILURE_MARKERS = (
    *auth_read.FAILURE_MARKERS,
    "AT AUTH PROVIDER VERTICAL FAIL",
    "AT AUTH PROVIDER ASSERT",
    "AT AUTH PROVIDER STATUS",
    "AT AUTH PROVIDER STACK",
    "AT AUTH PROVIDER LOAD STACK FAIL",
)


def _requires(path: Path) -> list[str]:
    return re.findall(
        r"(?mi)^[ \t]*REQUIRE[ \t]+(\S+)",
        path.read_text(encoding="utf-8"),
    )


def _forth_code(source: str) -> str:
    return "\n".join(
        line.split("\\", 1)[0] for line in source.splitlines()
    )


def _assert_static() -> None:
    provider = PROVIDER.read_text(encoding="utf-8")
    interface = INTERFACE.read_text(encoding="utf-8")
    streams = STREAMS.read_text(encoding="utf-8")
    streams_online = STREAMS_ONLINE.read_text(encoding="utf-8")
    fixture = CONTRACT.read_text(encoding="utf-8")
    timeline = TIMELINE.read_bytes()

    for module in (
        "tui/applets/streams/atproto-authenticated-provider.f",
        "tui/applets/streams/authenticated-provider.f",
        "tui/applets/streams/atproto-author-feed-connector.f",
        "tui/applets/streams/atproto-author-feed-present.f",
        "tui/applets/streams/atproto-text-post-connector.f",
        "tui/applets/streams/streams.f",
        "tui/applets/streams/streams-online.f",
        "tui/applets/streams/bluesky-public.f",
        "tui/applets/streams/syndication-http.f",
        "atproto/create-record.f",
        "utils/fs/vfs.f",
    ):
        assert module in RAW_MODULES
    assert REPLACED_CRYPTO_MODULES < set(RAW_MODULES)
    assert NUM_CORES == 1
    assert EXT_MEM_SIZE == 128 << 20
    assert MAX_PHASE_STEPS == 180_000_000
    assert LINKED is False
    assert COMPILE_CHECKPOINT_BYTES == 12 * 1024
    assert BUNDLE_BYTES == 32 * 1024
    assert CHECKPOINTS_PER_BUNDLE == 2
    assert POST_DRIVE_CHECKPOINTS == 2
    assert SOURCE_FRAGMENTS
    assert BUNDLE_FILES
    assert all(
        len(source) <= COMPILE_CHECKPOINT_BYTES
        for source in SOURCE_FRAGMENTS
    )
    assert all(len(source) <= BUNDLE_BYTES for _, source in BUNDLE_FILES)

    for marker in (
        "PROVIDED akashic-streams-atowner",
        "STREAMS-AT-ACCOUNT-SEAL",
        "STREAMS-AT-AUTH-PROVIDER-NEW",
        "STREAMS-AUTH-SOURCE-ADMISSIBLE?",
        "AT-AUTHOR-FEED-CONNECTOR-PUBLISH",
        "STREAMS-AT-AUTHOR-FEED-PRESENT",
        "AT-TEXT-POST-CONNECTOR-INIT",
        "AT-TEXT-POST-CONNECTOR-URI@",
        "AT-TEXT-POST-CONNECTOR-CID@",
        "SATP.FEED-SEQUENCE",
        "_SATP-INSTANCE-EXACT-OR-UNBOUND?",
        "_SATP-CALL-SCRATCH-CLEAR",
        "['] _SATP-CB-PUBLISH",
        "_SATP-CONTEXT-DISPOSE DUP SAUTH-S-OK <> IF",
        "_SATP-NEW-CLEAR R> DROP SAUTH-S-CLEANUP EXIT",
        "SAUTH-STATE-POST-DELIVERED",
        "SAUTH-STATE-POST-NO-EFFECT",
    ):
        assert marker in provider or marker in streams
    for marker in (
        "STREAMS-ONLINE-ENTRY-WITH-PROVIDERS",
        "STREAMS-ONLINE-COMP-SETUP-WITH-PROVIDERS",
        "STREAMS-ONLINE-E-FACTORY-CONFLICT",
    ):
        assert marker in streams_online
    for marker in (
        "SAUTH-SOURCE-BUILD",
        "SAUTH-REFRESH",
        "SAUTH-PUBLISH",
        "SAUTH-TICK",
        "SAUTH-CANCEL",
        "SAUTH-RELEASABLE?",
        "SAUTH-RELEASE",
    ):
        assert marker in interface

    assert _requires(CONTRACT) == [
        "at-bidirectional-vertical.f",
        "../akashic/tui/applets/streams/atproto-authenticated-provider.f",
        "../akashic/tui/applets/streams/streams-online.f",
    ]
    for marker in (
        "PROVIDED at-auth-provider-vert",
        "STREAMS-AT-ACCOUNT-SEAL",
        "STREAMS-ONLINE-ENTRY-WITH-PROVIDERS",
        "STREAMS-ONLINE-COMP-SETUP-WITH-PROVIDERS",
        "STREAMS-ONLINE-E-FACTORY-CONFLICT",
        "STREAMS-ONLINE-COMP-DESC CINST-NEW",
        "STREAMS-SOURCE-CREATE-OWNER",
        "STREAMS-SOURCE-REPLACE-OWNER",
        "STREAMS-AUTH-SOURCE-ADMISSIBLE?",
        "_SATPT-FEED",
        "_SATPT-FEED-REPEAT",
        "_SATPT-STALE-FEED",
        "_SATPT-FAILED-PUBLISH",
        "_SATPT-POST-START",
        "_SATPT-POST-DRIVE-FIRST",
        "_SATPT-POST-DRIVE-CHUNK",
        "_SATPT-POST-DRIVE",
        "_SATPT-POST-FINISH",
        "_SATPT-POST-MUTATION-CANCEL",
        "_SATPT-CLOSE-ACTIVE",
        "_satpt-other-instance @ _satpt-provider @ SAUTH-TICK",
        "_satpt-other-instance @ _satpt-provider @ SAUTH-CANCEL",
        "_satpt-publish-scratch-clear?",
        "SATP.LOCAL-EVENT",
        "STREAMS-REQUEST-CLOSE-CB",
        "APP-CLOSE-D-ALLOW",
        "_STM-AUTH-QUIESCE-STATUS @ SAUTH-S-POST",
        "SAUTH-STATE-FEED-READY",
        "SAUTH-STATE-FAILED",
        "SAUTH-STATE-POST-DELIVERED",
        "SAUTH-STATE-POST-NO-EFFECT",
        "ATBVT.CAPTURE-U @ 0=",
        "HEAP-FREE-BYTES _satpt-heap-before @ =",
        "XIO-SERVICE-FINI",
        "_SATPT-FINISH",
    ):
        assert marker in fixture
    assert timeline
    assert b'"cursor": "page-2-token"' in timeline
    assert b"Injected fixtures make network behavior reviewable." in timeline
    assert TIMELINE_GUEST.encode("ascii") in BIDIRECTIONAL_FIXTURE.read_bytes()

    all_items = (*MODULE_ITEMS, *FIXTURE_ITEMS)
    assert len({item.name for item in all_items}) == len(all_items)
    for item in all_items:
        assert len(Path(item.guest).name.encode("utf-8")) <= 23
        assert (item.source is None) != (item.inline is None)
    for guest, _ in BUNDLE_FILES:
        assert len(Path(guest).name.encode("utf-8")) <= 23
    assert len(Path(TIMELINE_GUEST).name.encode("ascii")) <= 23

    for path in {
        *(item.source for item in all_items if item.source),
        PROVIDER,
        INTERFACE,
        STREAMS,
        STREAMS_ONLINE,
        CONTRACT,
    }:
        auth_read._assert_physical_comments(  # noqa: SLF001
            path,
            path.read_text(encoding="utf-8"),
        )

    forbidden_line_parsers = {
        "SOURCE",
        ">IN",
        "REFILL",
        "PARSE",
        "WORD",
        "EVALUATE",
    }
    for item in all_items:
        if item.inline is not None:
            source = item.inline
        else:
            assert item.source is not None
            source = item.source.read_text(encoding="utf-8")
        assert not forbidden_line_parsers & set(_forth_code(source).split())


def _initial_files() -> tuple[tuple[str, bytes], ...]:
    return (
        (TIMELINE_GUEST, TIMELINE.read_bytes()),
        *BUNDLE_FILES,
    )


def _autoexec() -> str:
    lines = [
        "\\ autoexec.f - concrete authenticated provider qualification\n",
        "ENTER-USERLAND\n",
        f'." {BOOT_MARKER}" CR TX-FLUSH\n',
        "KEY DROP\n",
    ]
    for index, (guest, _) in enumerate(BUNDLE_FILES, start=1):
        lines.extend(
            (
                f"REQUIRE {guest}\n",
                (
                    'DEPTH IF ." AT AUTH PROVIDER LOAD STACK FAIL '
                    f'bundle-{index:02d}" CR TX-FLUSH THEN\n'
                ),
                f'." {_bundle_marker(index)}" CR TX-FLUSH\n',
                "KEY DROP\n",
            )
        )
    for _, word, marker in RUNTIME_STAGES:
        if marker == PASS_MARKER:
            lines.extend((f"{word}\n", "TX-FLUSH\n"))
        else:
            lines.extend(
                (
                    f"{word}\n",
                    f'." {marker}" CR TX-FLUSH\n',
                    "KEY DROP\n",
                )
            )
    return "".join(lines)


def _run_vertical(timeout: float) -> int:
    harness.PROFILES[PROFILE] = harness.Profile(
        roots=(),
        resources=(),
        autoexec=_autoexec(),
        ready_markers=(PASS_MARKER,),
        stable_markers=(PASS_MARKER,),
        failure_markers=FAILURE_MARKERS,
        initial_files=_initial_files(),
        linked=LINKED,
        include_large_sample=False,
        total_sectors=8192,
    )
    image_path = harness.build_image(PROFILE, IMAGE)
    profile = harness.PROFILES[PROFILE]
    stages = (
        ("boot", BOOT_MARKER),
        *(stage for bundle in BUNDLES for stage in bundle.stages),
        *((name, marker) for name, _, marker in RUNTIME_STAGES),
    )

    with harness.MachineSession.from_bios(
        harness.MEGAPAD_ROOT / "bios.asm",
        storage_image=image_path,
        cols=120,
        rows=44,
        batch_steps=500_000,
        ext_mem_size=EXT_MEM_SIZE,
        num_cores=NUM_CORES,
    ) as machine:
        machine.boot()
        for index, (stage_name, marker) in enumerate(stages):
            if index:
                machine.clear_output()
                machine.send_text("x")
            report = machine.run(
                max_steps=MAX_PHASE_STEPS,
                wall_timeout_s=timeout,
                until_text=marker,
                text_scope="raw",
            )
            raw_text = machine.raw_text()
            failures = tuple(
                dict.fromkeys(
                    (
                        *harness._has_forth_error(raw_text),  # noqa: SLF001
                        *harness._matched_failure_markers(  # noqa: SLF001
                            profile,
                            raw_text,
                            machine.screen_text(),
                        ),
                    )
                )
            )
            if marker not in raw_text or failures:
                print(f"AT AUTH PROVIDER {stage_name}: FAIL")
                print(
                    f"  {report.steps:,} steps in {report.elapsed_s:.2f}s; "
                    f"stop={report.reason}"
                )
                for failure in failures:
                    print(f"  {failure}")
                print(raw_text[-5000:])
                return 1
            print(
                f"AT AUTH PROVIDER {stage_name}: PASS "
                f"({report.steps:,} steps, {report.elapsed_s:.2f}s)",
                flush=True,
            )
    print("AT authenticated provider vertical: PASS")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--static-only", action="store_true")
    mode.add_argument(
        "--vertical",
        action="store_true",
        help="run the staged one-core source-mode provider gate",
    )
    parser.add_argument("--timeout", type=float, default=180.0)
    args = parser.parse_args()

    _assert_static()
    if args.static_only:
        print("AT AUTH PROVIDER STATIC PASS")
        return 0
    return _run_vertical(args.timeout)


if __name__ == "__main__":
    raise SystemExit(main())
