#!/usr/bin/env python3
"""Qualify the transport-neutral authenticated Streams applet seam."""

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
from forth_dependencies import dependency_order  # noqa: E402


PROFILE = "streams-authenticated-applet"
IMAGE = Path("/tmp/akashic-streams-authenticated-applet.img")
PASS_MARKER = "STREAMS AUTH APPLET PASS"
BOOT_MARKER = "STREAMS AUTH APPLET USERLAND READY"
MAX_PHASE_STEPS = 180_000_000
EXT_MEM_SIZE = 128 << 20
NUM_CORES = 1
LINKED = False
BUNDLE_BYTES = 64 * 1024
COMPILE_CHECKPOINT_BYTES = 12 * 1024

STREAMS = SOURCE_ROOT / "tui" / "applets" / "streams" / "streams.f"
STREAMS_ONLINE = (
    SOURCE_ROOT / "tui" / "applets" / "streams" / "streams-online.f"
)
STREAMS_UIDL = SOURCE_ROOT / "tui" / "applets" / "streams" / "streams.uidl"
AUTH_PROVIDER = (
    SOURCE_ROOT
    / "tui"
    / "applets"
    / "streams"
    / "authenticated-provider.f"
)
SOURCE_REGISTRY = (
    SOURCE_ROOT / "tui" / "applets" / "streams" / "source-registry.f"
)
CONTRACT = LOCAL_TESTING / "streams-authenticated-applet.f"
TIMELINE = LOCAL_TESTING / "fixtures" / "atproto" / "timeline.json"
TIMELINE_GUEST = "saa-feed.json"

RAW_MODULES = dependency_order(
    SOURCE_ROOT,
    (
        "tui/applets/streams/streams.f",
        "utils/fs/vfs.f",
    ),
)
MODULE_PATHS = tuple(SOURCE_ROOT / module for module in RAW_MODULES)


@dataclass(frozen=True)
class SourceFragment:
    payload: bytes
    origin: str


@dataclass(frozen=True)
class SourceBundle:
    guest: str
    payload: bytes
    stages: tuple[tuple[str, str], ...]
    phase_bytes: tuple[int, ...]


def _prepared_source(path: Path) -> bytes:
    return harness._minify_forth(  # noqa: SLF001
        path.read_text(encoding="utf-8"),
        remove_requires=True,
    ).encode("utf-8")


def _top_level_units(payload: bytes, origin: str) -> tuple[bytes, ...]:
    """Split prepared Forth only while its evaluator is at top level."""
    units: list[bytearray] = []
    unit = bytearray()
    definition_depth = 0
    conditional_depth = 0
    for line in payload.splitlines(keepends=True):
        unit.extend(line)
        text = line.decode("utf-8").rstrip("\r\n")
        tokens = harness._forth_line_tokens(text)  # noqa: SLF001
        if tokens and (tokens[0] == ":" or tokens[0].upper() == ":NONAME"):
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
        raise RuntimeError(f"prepared source ends inside a unit: {origin}")
    return tuple(bytes(source_unit) for source_unit in units)


def _source_fragments() -> tuple[SourceFragment, ...]:
    """Pack complete top-level units below the compile checkpoint ceiling."""
    fragments: list[SourceFragment] = []
    current = bytearray()
    origins: list[str] = []
    for path in (*MODULE_PATHS, CONTRACT):
        relative = path.relative_to(ROOT).as_posix()
        for source_unit in _top_level_units(_prepared_source(path), relative):
            if len(source_unit) > COMPILE_CHECKPOINT_BYTES:
                raise RuntimeError(
                    "authenticated applet source unit exceeds the 12 KiB "
                    f"checkpoint ceiling: {relative}"
                )
            if (
                current
                and len(current) + len(source_unit) > COMPILE_CHECKPOINT_BYTES
            ):
                fragments.append(
                    SourceFragment(bytes(current), ", ".join(origins))
                )
                current.clear()
                origins.clear()
            current.extend(source_unit)
            if not origins or origins[-1] != relative:
                origins.append(relative)
    if current:
        fragments.append(SourceFragment(bytes(current), ", ".join(origins)))
    return tuple(fragments)


SOURCE_FRAGMENTS = _source_fragments()


def _bundle_marker(index: int) -> str:
    return f"STREAMS AUTH APPLET BUNDLE {index:02d} READY"


def _internal_marker(index: int, part: int) -> str:
    return f"STREAMS AUTH APPLET BUNDLE {index:02d} PART {part:02d} READY"


def _source_bundles() -> tuple[SourceBundle, ...]:
    """Pair 12 KiB fragments, leaving ample room below the 64 KiB bound."""
    bundles: list[SourceBundle] = []
    for offset in range(0, len(SOURCE_FRAGMENTS), 2):
        index = len(bundles) + 1
        fragments = SOURCE_FRAGMENTS[offset : offset + 2]
        payload = bytearray()
        internal_stages: list[tuple[str, str]] = []
        for part, fragment in enumerate(fragments, start=1):
            payload.extend(fragment.payload)
            if part == len(fragments):
                continue
            marker = _internal_marker(index, part)
            internal_stages.append(
                (f"bundle-{index:02d}-part-{part:02d}", marker)
            )
            payload.extend(
                (
                    "\nDEPTH IF .\" STREAMS AUTH APPLET LOAD STACK FAIL "
                    f"bundle-{index:02d}-part-{part:02d}"
                    "\" CR TX-FLUSH THEN\n"
                    f'." {marker}" CR TX-FLUSH\nKEY DROP\n'
                ).encode("utf-8")
            )
        coalesced = harness._coalesce_audited_forth_lines(  # noqa: SLF001
            bytes(payload),
            harness.MEGAPAD_EVALUATE_SOURCE_MAX_BYTES,
        )
        final_marker = _bundle_marker(index)
        bundle = SourceBundle(
            guest=f"local_testing/saa-b{index:02d}.f",
            payload=coalesced,
            stages=(
                *internal_stages,
                (f"bundle-{index:02d}", final_marker),
            ),
            phase_bytes=tuple(len(fragment.payload) for fragment in fragments),
        )
        if len(bundle.payload) > BUNDLE_BYTES:
            raise RuntimeError(
                f"authenticated applet bundle exceeds 64 KiB: {bundle.guest}"
            )
        bundles.append(bundle)
    return tuple(bundles)


BUNDLES = _source_bundles()

RUNTIME_STAGES = (
    ("document", "_SATC-LOAD", "STREAMS AUTH APPLET DOCUMENT READY"),
    ("setup", "_SATC-SETUP", "STREAMS AUTH APPLET SETUP READY"),
    ("source", "_SATC-SOURCE", "STREAMS AUTH APPLET SOURCE READY"),
    ("refresh", "_SATC-REFRESH", "STREAMS AUTH APPLET FEED READY"),
    ("publish", "_SATC-PUBLISH", "STREAMS AUTH APPLET OUTCOMES READY"),
    (
        "stale-start",
        "_SATC-STALE-START",
        "STREAMS AUTH APPLET STALE START READY",
    ),
    (
        "stale-mutate",
        "_SATC-STALE-MUTATE",
        "STREAMS AUTH APPLET STALE MUTATION READY",
    ),
    (
        "stale-recover",
        "_SATC-STALE-RECOVER",
        "STREAMS AUTH APPLET STALE RECOVERY READY",
    ),
    ("post-race", "_SATC-POST-RACE", "STREAMS AUTH APPLET POST RACE READY"),
    ("close", "_SATC-CLOSE", "STREAMS AUTH APPLET CLOSE READY"),
    ("relaunch", "_SATC-RELAUNCH", "STREAMS AUTH APPLET RELAUNCH READY"),
    ("finish", "_SATC-FINISH", PASS_MARKER),
)

FAILURE_MARKERS = (
    "STREAMS AUTH APPLET FAIL",
    "STREAMS AUTH APPLET ASSERT",
    "STREAMS AUTH APPLET STACK",
    "STREAMS AUTH APPLET LOAD STACK FAIL",
    "DRIVER THROW",
    "Branch offset overflow",
    "dictionary full",
    "exception",
    "Module not found",
    "Path component not found",
    "? (not found)",
)


def _forth_code(source: str) -> str:
    return "\n".join(line.split("\\", 1)[0] for line in source.splitlines())


def _word_count(source: str, name: str) -> int:
    return len(
        re.findall(
            rf"(?<![A-Za-z0-9_-]){re.escape(name)}"
            rf"(?![A-Za-z0-9_-])",
            _forth_code(source),
        )
    )


def _assert_physical_comments(path: Path, source: str) -> None:
    for line_number, line in enumerate(source.splitlines(), start=1):
        code = line.split("\\", 1)[0]
        code = code.replace("[CHAR] (", "")
        if "(" in code:
            assert ")" in code.split("(", 1)[1], (
                "KDOS parenthesized comments must close on their physical "
                f"line: {path}:{line_number}"
            )


def _assert_static() -> None:
    fixture = CONTRACT.read_text(encoding="utf-8")
    streams = STREAMS.read_text(encoding="utf-8")
    online = STREAMS_ONLINE.read_text(encoding="utf-8")
    uidl = STREAMS_UIDL.read_text(encoding="utf-8")
    provider = AUTH_PROVIDER.read_text(encoding="utf-8")
    registry = SOURCE_REGISTRY.read_text(encoding="utf-8")
    timeline = TIMELINE.read_bytes()

    assert LINKED is False
    assert NUM_CORES == 1
    assert EXT_MEM_SIZE == 128 << 20
    assert MAX_PHASE_STEPS == 180_000_000
    assert BUNDLE_BYTES == 64 * 1024
    assert COMPILE_CHECKPOINT_BYTES == 12 * 1024
    assert RAW_MODULES[-1] == "tui/applets/streams/streams.f"
    assert "tui/applets/streams/authenticated-provider.f" in RAW_MODULES
    assert "utils/fs/vfs.f" in RAW_MODULES
    assert not {
        "tui/applets/streams/atproto-author-feed-connector.f",
        "tui/applets/streams/atproto-text-post-connector.f",
        "tui/applets/streams/streams-online.f",
        "net/transports/kdos-tls.f",
    } & set(RAW_MODULES)

    for word in (
        "SAUTH-SEAL",
        "SAUTH-SOURCE-BUILD",
        "SAUTH-REFRESH",
        "SAUTH-PUBLISH",
        "SAUTH-TICK",
        "SAUTH-CANCEL",
        "SAUTH-RELEASE",
    ):
        assert _word_count(provider, word) >= 1
    for word in (
        "STREAMS-AUTH-FACTORY-STATE!",
        "_STM-APPLY-AUTH-SOURCE-CREATE",
        "_STM-AUTH-REFRESH-START",
        "_STM-PUBLISH-ACTION",
        "_STM-LOAD-AUTHOR-FEED-JSON",
        "_STM-AUTH-QUIESCE?",
    ):
        assert _word_count(streams, word) >= 1
    assert "4 CONSTANT SSOURCE-KIND-BLUESKY-PUBLIC" in registry
    assert "5 CONSTANT SSOURCE-KIND-ATPROTO-AUTHENTICATED" in registry
    assert "SSOURCE-FORMAT-ATPROTO-JSON" in registry
    assert "1 CONSTANT STREAMS-SOURCE-REGISTRY-ABI" in registry
    assert streams.count(
        'SSOURCE-KIND-BLUESKY-PUBLIC OF S" bluesky-public" ENDOF'
    ) == 2
    assert streams.count("SSOURCE-KIND-ATPROTO-AUTHENTICATED OF") == 2
    for word in (
        "_STREAMS-ONLINE-COMP-TRY-SETUP-WITH-PROVIDERS",
        "STREAMS-ONLINE-COMP-SETUP-WITH-PROVIDERS",
        "STREAMS-ONLINE-ENTRY-WITH-PROVIDERS",
        "STREAMS-ONLINE-E-FACTORY-CONFLICT",
    ):
        assert _word_count(online, word) >= 1
    assert "do=source-add-atproto" in uidl
    assert "do=publish" in uidl

    for marker in (
        "PROVIDED streams-auth-app-test",
        "_SATC-FAKE-NEW",
        "_satc-fake-source-build",
        "_satc-fake-refresh",
        "_satc-fake-publish",
        "_satc-fake-tick",
        "_STM-LOAD-AUTHOR-FEED-JSON",
        "_SATC-OUTCOME-DELIVERED",
        "_SATC-OUTCOME-NO-EFFECT",
        "_SATC-OUTCOME-UNCERTAIN",
        "STREAMS-SOURCE-REPLACE-OWNER",
        "APP.REQUEST-CLOSE-XT",
        "HEAP-FREE-BYTES",
        "STREAMS AUTH APPLET PASS",
    ):
        assert marker in fixture
    for word in ("_SATC-LOAD", *(word for _, word, _ in RUNTIME_STAGES[1:])):
        assert _word_count(fixture, word) >= 1

    assert timeline.count(b'"post": {') == 2
    assert b"Injected fixtures make network behavior reviewable." in timeline
    assert len(Path(TIMELINE_GUEST).name.encode("utf-8")) <= 23
    assert BUNDLES
    assert SOURCE_FRAGMENTS
    assert all(
        0 < len(fragment.payload) <= COMPILE_CHECKPOINT_BYTES
        for fragment in SOURCE_FRAGMENTS
    )
    assert all(0 < len(bundle.payload) <= BUNDLE_BYTES for bundle in BUNDLES)
    assert all(
        0 < phase_bytes <= COMPILE_CHECKPOINT_BYTES
        for bundle in BUNDLES
        for phase_bytes in bundle.phase_bytes
    )
    assert sum(len(bundle.payload) for bundle in BUNDLES) < 4 * 1024 * 1024
    assert all(
        len(Path(bundle.guest).name.encode("utf-8")) <= 23
        for bundle in BUNDLES
    )
    stages = (
        ("boot", BOOT_MARKER),
        *(stage for bundle in BUNDLES for stage in bundle.stages),
        *((name, marker) for name, _, marker in RUNTIME_STAGES),
    )
    assert len({name for name, _ in stages}) == len(stages)
    assert len({marker for _, marker in stages}) == len(stages)

    for path in (*MODULE_PATHS, STREAMS_ONLINE, CONTRACT):
        _assert_physical_comments(path, path.read_text(encoding="utf-8"))


def _initial_files() -> tuple[tuple[str, bytes], ...]:
    return (
        (TIMELINE_GUEST, TIMELINE.read_bytes()),
        *((bundle.guest, bundle.payload) for bundle in BUNDLES),
    )


def _autoexec() -> str:
    lines = [
        "\\ autoexec.f - transport-neutral authenticated Streams applet\n",
        "ENTER-USERLAND\n",
        f'." {BOOT_MARKER}" CR TX-FLUSH\n',
        "KEY DROP\n",
    ]
    for index, bundle in enumerate(BUNDLES, start=1):
        lines.extend(
            (
                f"REQUIRE {bundle.guest}\n",
                (
                    'DEPTH IF ." STREAMS AUTH APPLET LOAD STACK FAIL '
                    f'bundle-{index:02d}" CR TX-FLUSH THEN\n'
                ),
                f'." {_bundle_marker(index)}" CR TX-FLUSH\n',
                "KEY DROP\n",
            )
        )
    for _, word, marker in RUNTIME_STAGES:
        invocation = (
            f"' {word} CATCH DUP IF "
            '." STREAMS AUTH APPLET DRIVER THROW " DUP . CR TX-FLUSH '
            "THEN ?DUP IF THROW THEN\n"
        )
        if marker == PASS_MARKER:
            lines.extend((invocation, "TX-FLUSH\n"))
        else:
            lines.extend(
                (
                    invocation,
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
                print(f"STREAMS AUTH APPLET {stage_name}: FAIL")
                print(
                    f"  {report.steps:,} steps in {report.elapsed_s:.2f}s; "
                    f"stop={report.reason}"
                )
                for failure in failures:
                    print(f"  {failure}")
                print(raw_text[-5000:])
                return 1
            print(
                f"STREAMS AUTH APPLET {stage_name}: PASS "
                f"({report.steps:,} steps, {report.elapsed_s:.2f}s)",
                flush=True,
            )
    print("Streams authenticated applet vertical: PASS")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser()
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--static-only", action="store_true")
    mode.add_argument(
        "--vertical",
        action="store_true",
        help="run the staged one-core source-mode applet contract",
    )
    parser.add_argument("--timeout", type=float, default=180.0)
    args = parser.parse_args()

    _assert_static()
    if args.static_only:
        print("STREAMS AUTH APPLET STATIC PASS")
        return 0
    return _run_vertical(args.timeout)


if __name__ == "__main__":
    raise SystemExit(main())
