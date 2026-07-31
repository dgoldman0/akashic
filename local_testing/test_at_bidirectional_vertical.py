#!/usr/bin/env python3
"""Qualify the authenticated AT Protocol ingress-to-egress SR4 slice."""

from __future__ import annotations

import argparse
import re
import sys
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


PROFILE = "at-bidirectional-vertical"
IMAGE = Path("/tmp/akashic-at-bidirectional-vertical.img")
PASS_MARKER = "AT BIDIRECTIONAL VERTICAL PASS"
BOOT_MARKER = "AT BIDIRECTIONAL USERLAND READY"
MAX_PHASE_STEPS = 180_000_000
EXT_MEM_SIZE = 128 << 20
NUM_CORES = 1
LINKED = False
COALESCED_LOAD = True
# Keep compilation checkpoints comfortably below MAX_PHASE_STEPS.  This does
# not change the ordered source stream; it only yields control more often.
BUNDLE_BYTES = 64 * 1024

FEED_CONNECTOR = (
    SOURCE_ROOT
    / "tui"
    / "applets"
    / "streams"
    / "atproto-author-feed-connector.f"
)
POST_CONNECTOR = (
    SOURCE_ROOT
    / "tui"
    / "applets"
    / "streams"
    / "atproto-text-post-connector.f"
)
CONTRACT = LOCAL_TESTING / "at-bidirectional-vertical.f"
TIMELINE = LOCAL_TESTING / "fixtures" / "atproto" / "timeline.json"
TIMELINE_GUEST = "atbv-feed.json"

REPLACED_CRYPTO_MODULES = auth_read.REPLACED_CRYPTO_MODULES
REPLACED_TRANSPORT_MODULES = frozenset({"net/transports/kdos-tls.f"})
TRANSPORT_DOUBLE = xrpc_exchange.TRANSPORT_DOUBLE

RAW_MODULES = dependency_order(
    SOURCE_ROOT,
    (
        "tui/applets/streams/atproto-author-feed-connector.f",
        "tui/applets/streams/atproto-text-post-connector.f",
        "utils/fs/vfs.f",
    ),
)


def _module_items() -> tuple[auth_read.LoadItem, ...]:
    """Preserve dependency and seam order before coalescing source."""
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
                    guest="local_testing/atbv-net.f",
                    marker="AT BIDIRECTIONAL TRANSPORT SEAM READY",
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
                    guest="local_testing/atbv-seam.f",
                    marker="AT BIDIRECTIONAL CRYPTO SEAM READY",
                    inline=P256_JWK_DOUBLES,
                    remove_requires=False,
                )
            )
            crypto_seam_inserted = True
        sequence += 1
        items.append(
            auth_read.LoadItem(
                name=f"module-{sequence:02d}",
                guest=f"local_testing/atbv-m{sequence:02d}.f",
                marker=f"AT BIDIRECTIONAL MODULE {sequence:02d} READY",
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
        guest="local_testing/atbv-prof.f",
        marker="AT BIDIRECTIONAL PROFILE FIXTURE READY",
        source=auth_read.PROFILE_FIXTURE,
        remove_requires=False,
    ),
    auth_read.LoadItem(
        name="client-fixture",
        guest="local_testing/atbv-client.f",
        marker="AT BIDIRECTIONAL CLIENT FIXTURE READY",
        source=auth_read.CLIENT_FIXTURE,
        remove_requires=False,
    ),
    auth_read.LoadItem(
        name="authenticated-session-fixture",
        guest="local_testing/atbv-auth.f",
        marker="AT BIDIRECTIONAL AUTH FIXTURE READY",
        source=auth_read.CONTRACT,
    ),
    auth_read.LoadItem(
        name="bidirectional-fixture",
        guest="local_testing/atbv-test.f",
        marker="AT BIDIRECTIONAL FIXTURE READY",
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


def _top_level_units(payload: bytes) -> tuple[bytes, ...]:
    """Split prepared Forth only where the evaluator is at top level."""
    units: list[bytearray] = []
    unit = bytearray()
    definition_depth = 0
    conditional_depth = 0
    for line in payload.splitlines(keepends=True):
        unit.extend(line)
        text = line.decode("utf-8").rstrip("\r\n")
        tokens = harness._forth_line_tokens(text)  # noqa: SLF001
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
        for token in tokens:
            upper = token.upper()
            if upper == "[IF]":
                conditional_depth += 1
            elif upper == "[THEN]" and conditional_depth:
                conditional_depth -= 1
        if definition_depth == 0 and conditional_depth == 0:
            units.append(unit)
            unit = bytearray()
    if unit:
        raise RuntimeError("Prepared bidirectional source ends inside a unit")
    return tuple(bytes(source_unit) for source_unit in units)


def _bundle_files() -> tuple[tuple[str, bytes], ...]:
    """Greedily pack ordered top-level units under the audited ceiling."""
    bundles: list[bytes] = []
    current = bytearray()
    for item in (*MODULE_ITEMS, *FIXTURE_ITEMS):
        for source_unit in _top_level_units(_bundle_source(item)):
            if len(source_unit) > BUNDLE_BYTES:
                raise RuntimeError(
                    f"bidirectional source unit too large: {item.name}"
                )
            if current and len(current) + len(source_unit) > BUNDLE_BYTES:
                bundles.append(bytes(current))
                current.clear()
            current.extend(source_unit)
    if current:
        bundles.append(bytes(current))
    return tuple(
        (
            f"local_testing/atbv-b{index:02d}.f",
            harness._coalesce_audited_forth_lines(  # noqa: SLF001
                source,
                harness.MEGAPAD_EVALUATE_SOURCE_MAX_BYTES,
            ),
        )
        for index, source in enumerate(bundles, start=1)
    )


BUNDLE_FILES = _bundle_files()


def _bundle_marker(index: int) -> str:
    return f"AT BIDIRECTIONAL BUNDLE {index:02d} READY"


RUNTIME_STAGES = (
    ("fixture-load", "_ATBV-LOAD", "AT BIDIRECTIONAL DOCUMENT READY"),
    ("setup", "_ATXR-SETUP", "AT BIDIRECTIONAL SETUP READY"),
    ("provision", "_ATXR-PROVISION", "AT BIDIRECTIONAL KEY READY"),
    ("install", "_ATXR-INSTALL", "AT BIDIRECTIONAL SESSION READY"),
    ("owner-restart", "_ATXR-RESTART", "AT BIDIRECTIONAL REOPEN READY"),
    ("graph-setup", "_ATBV-SETUP", "AT BIDIRECTIONAL GRAPHS READY"),
    ("authenticated-ingress", "_ATBV-INGRESS", "AT BIDIRECTIONAL INGRESS READY"),
    (
        "interleave-admit",
        "_ATBV-INTERLEAVE-ADMIT",
        "AT BIDIRECTIONAL EGRESS ADMITTED",
    ),
    (
        "interleave-start",
        "_ATBV-INTERLEAVE-START",
        "AT BIDIRECTIONAL EGRESS STARTED",
    ),
    (
        "interleave-drive-first",
        "_ATBV-INTERLEAVE-DRIVE-FIRST",
        "AT BIDIRECTIONAL EGRESS POLLED",
    ),
    (
        "interleave-drive",
        "_ATBV-INTERLEAVE-DRIVE",
        "AT BIDIRECTIONAL EGRESS TERMINAL",
    ),
    (
        "interleave-check",
        "_ATBV-INTERLEAVE-CHECK",
        "AT BIDIRECTIONAL EGRESS VERIFIED",
    ),
    ("no-effect", "_ATBV-NO-EFFECT", "AT BIDIRECTIONAL NO EFFECT READY"),
    ("flow-release", "_ATBV-RELEASE-FLOWS", "AT BIDIRECTIONAL FLOWS RELEASED"),
    ("graph-release", "_ATBV-RELEASE-GRAPHS", "AT BIDIRECTIONAL GRAPHS RELEASED"),
    ("finish", "_ATBV-FINISH", PASS_MARKER),
)

FAILURE_MARKERS = (
    *auth_read.FAILURE_MARKERS,
    "AT BIDIRECTIONAL FAIL",
    "AT BIDIRECTIONAL ASSERT",
    "AT BIDIRECTIONAL STATUS",
    "AT BIDIRECTIONAL STACK",
    "AT BIDIRECTIONAL LOAD STACK FAIL",
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
    feed = FEED_CONNECTOR.read_text(encoding="utf-8")
    post = POST_CONNECTOR.read_text(encoding="utf-8")
    fixture = CONTRACT.read_text(encoding="utf-8")
    timeline = TIMELINE.read_bytes()

    assert "tui/applets/streams/atproto-author-feed-connector.f" in RAW_MODULES
    assert "tui/applets/streams/atproto-text-post-connector.f" in RAW_MODULES
    assert "atproto/create-record.f" in RAW_MODULES
    assert "atproto/bluesky-text-record.f" in RAW_MODULES
    assert "atproto/tid.f" in RAW_MODULES
    assert "tui/applets/streams/flow-core.f" in RAW_MODULES
    assert "tui/applets/streams/atproto-author-feed-present.f" not in RAW_MODULES
    assert "tui/applets/streams/streams.f" not in RAW_MODULES
    assert REPLACED_CRYPTO_MODULES < set(RAW_MODULES)
    assert NUM_CORES == 1
    assert EXT_MEM_SIZE == 128 << 20
    assert MAX_PHASE_STEPS == 180_000_000
    assert LINKED is False
    assert COALESCED_LOAD is True
    assert BUNDLE_BYTES == 64 * 1024
    assert BUNDLE_FILES
    assert all(len(source) <= BUNDLE_BYTES for _, source in BUNDLE_FILES)

    for marker in (
        "AT-AUTHOR-FEED-CONNECTOR-BIND",
        "AT-AUTHOR-FEED-CONNECTOR-PUBLISH",
        "AT-AUTHOR-FEED-CONNECTOR-FEED@",
        "AT-AUTHOR-FEED-CONNECTOR-XIO-WIPE",
    ):
        assert marker in feed
    for marker in (
        "AT-TEXT-POST-CONNECTOR-INIT",
        "AT-TEXT-POST-CONNECTOR-CONNECTOR@",
        "AT-TEXT-POST-CONNECTOR-CREATE-OUTCOME@",
        "AT-TEXT-POST-CONNECTOR-URI@",
        "AT-TEXT-POST-CONNECTOR-CID@",
        "AT-TEXT-POST-CONNECTOR-LAST-EPOCH-MS@",
    ):
        assert marker in post

    assert _requires(CONTRACT) == ["at-xrpc-auth-read-test.f"]
    for marker in (
        "_ATBV-LOAD",
        "_ATBV-SETUP",
        "_ATBV-INGRESS",
        "_ATBV-INTERLEAVE-ADMIT",
        "_ATBV-INTERLEAVE-START",
        "_ATBV-INTERLEAVE-DRIVE-FIRST",
        "_ATBV-INTERLEAVE-DRIVE",
        "_ATBV-INTERLEAVE-CHECK",
        "_ATBV-NO-EFFECT",
        "_ATBV-RELEASE-FLOWS",
        "_ATBV-RELEASE-GRAPHS",
        "_ATBV-FINISH",
        "AT-AUTHOR-FEED-CONNECTOR-PUBLISH",
        "AT-TEXT-POST-CONNECTOR-INIT",
        "STREAMS-FLOW-STEP",
        "STREAMS-FLOW-S-DELIVERED",
        "STREAMS-FLOW-S-INDETERMINATE",
        "AT-CREATE-RECORD-OUTCOME-NO-EFFECT",
        "AT-CREATE-RECORD-OUTCOME-UNCERTAIN",
        "POST /xrpc/com.atproto.repo.createRecord HTTP/1.1",
        "Authorization: DPoP access-vertical",
        "3ke6km2rsns2l",
        "3ke6km33xu22x",
        "2023-11-14T22:16:40Z",
        "Injected fixtures make network behavior reviewable.",
        "fixture-only",
        "NIO.CONTEXT !",
    ):
        assert marker in fixture
    assert timeline
    assert b'"cursor": "page-2-token"' in timeline
    assert b"Injected fixtures make network behavior reviewable." in timeline
    assert TIMELINE_GUEST.encode("ascii") in fixture.encode("utf-8")
    assert not re.search(
        r"(?i)(?<![A-Za-z0-9_-])(?:\?DO|DO|\+LOOP|LOOP)"
        r"(?![A-Za-z0-9_-])",
        _forth_code(fixture),
    ), "fixture must not borrow the DO-loop return stack"

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
        FEED_CONNECTOR,
        POST_CONNECTOR,
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
            item_source = item.inline
        else:
            assert item.source is not None
            item_source = item.source.read_text(encoding="utf-8")
        assert not forbidden_line_parsers & set(_forth_code(item_source).split())


def _initial_files() -> tuple[tuple[str, bytes], ...]:
    return (
        (TIMELINE_GUEST, TIMELINE.read_bytes()),
        *BUNDLE_FILES,
    )


def _autoexec() -> str:
    lines = [
        "\\ autoexec.f - focused authenticated bidirectional qualification\n",
        "ENTER-USERLAND\n",
        f'." {BOOT_MARKER}" CR TX-FLUSH\n',
        "KEY DROP\n",
    ]
    for index, (guest, _) in enumerate(BUNDLE_FILES, start=1):
        lines.extend(
            (
                f"REQUIRE {guest}\n",
                (
                    'DEPTH IF ." AT BIDIRECTIONAL LOAD STACK FAIL '
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
        *(
            (f"bundle-{index:02d}", _bundle_marker(index))
            for index in range(1, len(BUNDLE_FILES) + 1)
        ),
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
                print(f"AT BIDIRECTIONAL {stage_name}: FAIL")
                print(
                    f"  {report.steps:,} steps in {report.elapsed_s:.2f}s; "
                    f"stop={report.reason}"
                )
                for failure in failures:
                    print(f"  {failure}")
                print(raw_text[-5000:])
                return 1
            print(
                f"AT BIDIRECTIONAL {stage_name}: PASS "
                f"({report.steps:,} steps, {report.elapsed_s:.2f}s)",
                flush=True,
            )
    print("AT BIDIRECTIONAL vertical: PASS")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser()
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--static-only", action="store_true")
    mode.add_argument(
        "--vertical",
        action="store_true",
        help="run the staged one-core authenticated capstone",
    )
    parser.add_argument("--timeout", type=float, default=180.0)
    args = parser.parse_args()

    _assert_static()
    if args.static_only:
        print("AT BIDIRECTIONAL STATIC PASS")
        return 0
    return _run_vertical(args.timeout)


if __name__ == "__main__":
    raise SystemExit(main())
