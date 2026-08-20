#!/usr/bin/env python3
"""Focused seam-backed qualification for the Streams AT text-post output."""

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
from forth_dependencies import dependency_order  # noqa: E402


PROFILE = "streams-atproto-text-post"
IMAGE = Path("/tmp/akashic-streams-atproto-text-post.img")
SOURCE = (
    SOURCE_ROOT
    / "tui"
    / "applets"
    / "streams"
    / "atproto-text-post-connector.f"
)
SEAM = LOCAL_TESTING / "atpost-cr-seam.f"
CONTRACT = LOCAL_TESTING / "atpost-egress-test.f"

BOOT_MARKER = "AT TEXT POST EGRESS USERLAND READY"
PASS_MARKER = "AT TEXT POST EGRESS PASS"
MAX_PHASE_STEPS = 120_000_000
EXT_MEM_SIZE = 64 << 20
NUM_CORES = 1
BUNDLE_BYTES = 120 * 1024

# Keep all composition logic real while replacing only the already-qualified
# authenticated createRecord boundary.  In particular, flow-core, trusted
# datetime formatting, JSON/UTF-8 admission, and TID allocation execute here.
RUNTIME_ROOTS = (
    "tui/applets/streams/flow-core.f",
    "tui/applets/streams/atproto.f",
    "atproto/bluesky-text-record.f",
    "atproto/tid.f",
    "net/external-io.f",
)
RUNTIME_MODULES = dependency_order(SOURCE_ROOT, RUNTIME_ROOTS)
EXPECTED_RUNTIME_MODULES = (
    "runtime/identity.f",
    "utils/uint-range.f",
    "utils/memory-span.f",
    "concurrency/event.f",
    "concurrency/semaphore.f",
    "concurrency/guard.f",
    "math/sha3.f",
    "tui/applets/streams/runtime-profile.f",
    "tui/applets/streams/payload-carrier.f",
    "tui/applets/streams/flow-core.f",
    "tui/applets/streams/atproto.f",
    "utils/caller-span.f",
    "utils/buffer-writer.f",
    "text/utf8.f",
    "utils/json-writer.f",
    "utils/datetime.f",
    "atproto/bluesky-text-record.f",
    "atproto/tid.f",
    "net/external-io.f",
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


def _word_body(source: str, name: str) -> str:
    match = re.search(
        rf"(?ms)^:[ \t]+{re.escape(name)}(?=[ \t\r\n(])"
        rf"(?P<body>.*?)[ \t]+;",
        source,
    )
    assert match is not None, f"missing Forth word {name}"
    return match.group("body")


def _assert_physical_comments(path: Path, source: str) -> None:
    for line_number, line in enumerate(source.splitlines(), start=1):
        forth_code = line.split("\\", 1)[0]
        if "(" in forth_code:
            assert ")" in forth_code.split("(", 1)[1], (
                "KDOS parenthesized comments must close on their physical "
                f"line: {path}:{line_number}"
            )


def _source_bytes(path: Path) -> bytes:
    return harness._minify_forth(  # noqa: SLF001
        path.read_text(encoding="utf-8"),
        remove_requires=True,
    ).encode("utf-8")


def _bundle_files() -> tuple[tuple[str, bytes], ...]:
    sources = [
        _source_bytes(SOURCE_ROOT / module)
        for module in RUNTIME_MODULES
    ]
    sources.extend((_source_bytes(SEAM), _source_bytes(SOURCE), _source_bytes(CONTRACT)))
    chunks: list[bytes] = []
    current = bytearray()
    for source in sources:
        if len(source) > BUNDLE_BYTES:
            raise RuntimeError("AT text-post source item exceeds bundle bound")
        if current and len(current) + len(source) > BUNDLE_BYTES:
            chunks.append(bytes(current))
            current.clear()
        current.extend(source)
    if current:
        chunks.append(bytes(current))
    return tuple(
        (
            f"local_testing/atp-link-{index:02d}.f",
            harness._coalesce_audited_forth_lines(  # noqa: SLF001
                source,
                harness.MEGAPAD_EVALUATE_SOURCE_MAX_BYTES,
            ),
        )
        for index, source in enumerate(chunks)
    )


def _bundle_marker(index: int) -> str:
    return f"AT TEXT POST EGRESS BUNDLE {index:02d} READY"


def _assert_static() -> None:
    source = SOURCE.read_text(encoding="utf-8")
    seam = SEAM.read_text(encoding="utf-8")
    fixture = CONTRACT.read_text(encoding="utf-8")
    source_code = _forth_code(source)

    assert RUNTIME_MODULES == EXPECTED_RUNTIME_MODULES
    assert "atproto/create-record.f" not in RUNTIME_MODULES
    production_modules = dependency_order(
        SOURCE_ROOT,
        ("tui/applets/streams/atproto-text-post-connector.f",),
    )
    assert production_modules[-1] == (
        "tui/applets/streams/atproto-text-post-connector.f"
    )
    assert "atproto/create-record.f" in production_modules
    assert "atproto/bluesky-text-record.f" in production_modules
    assert "atproto/tid.f" in production_modules
    assert "tui/applets/streams/flow-core.f" in production_modules

    assert NUM_CORES == 1
    assert EXT_MEM_SIZE == 64 << 20
    assert MAX_PHASE_STEPS == 120_000_000
    assert BUNDLE_BYTES == 120 * 1024

    requires = _requires(SOURCE)
    for required in (
        "../../../atproto/create-record.f",
        "../../../atproto/bluesky-text-record.f",
        "../../../atproto/tid.f",
        "flow-core.f",
        "atproto.f",
    ):
        assert required in requires

    assert "PROVIDED akashic-streams-atpost" in source
    assert not re.search(
        r"(?mi)^[ \t]*(?:CREATE|VARIABLE|VALUE|DEFER|GUARD)\b",
        source_code,
    ), "the production connector must keep all mutable state in its owner"
    for forbidden in (
        "OWNER-POOL",
        "OWNER-TABLE",
        "OWNER-SLOTS",
        "INSTANCE-COUNT",
        "MAX-INSTANCES",
        "SLOT-COUNT",
    ):
        assert forbidden not in source_code.upper()
    assert "SEVT.RECEIVED-MS" not in source_code
    assert " ATCR." not in source_code
    assert "CONSTANT _ATTPC-TARGET-OFF" in source
    assert "DUP R@ ATTPC.TARGET HTARGET-SIZE MOVE DROP" in source
    assert "ATTPC.TARGET @" not in source_code
    assert "_ATTPC-RESULT-GEOMETRY" in source
    assert "_ATTPC-OP-PRESAVE-STATUS" in source
    assert "_ATTPC-EVENT-PAYLOAD-SPAN-DISJOINT?" in source

    for word in (
        "AT-TEXT-POST-CONNECTOR-SIZE",
        "AT-TEXT-POST-CONNECTOR-INIT",
        "AT-TEXT-POST-CONNECTOR-VALID?",
        "AT-TEXT-POST-CONNECTOR-CONNECTOR@",
        "AT-TEXT-POST-CONNECTOR-LAST-STATUS@",
        "AT-TEXT-POST-CONNECTOR-CLEANUP-ERROR@",
        "AT-TEXT-POST-CONNECTOR-CREATE-OUTCOME@",
        "AT-TEXT-POST-CONNECTOR-URI@",
        "AT-TEXT-POST-CONNECTOR-CID@",
        "AT-TEXT-POST-CONNECTOR-LAST-EPOCH-MS@",
    ):
        assert word in source
    for status in (
        "OK",
        "INVALID",
        "BUSY",
        "CAPACITY",
        "ALIAS",
        "CLOCK",
        "TID",
        "RECORD",
        "CREATE",
        "STATE",
        "TARGET",
        "CLEANUP",
        "RANGE",
        "PROTECTED",
        "PLATFORM",
        "INTERNAL",
    ):
        assert f"AT-TEXT-POST-CONNECTOR-S-{status}" in source

    for marker in (
        "SCON.START-XT !",
        "SCON.POLL-XT !",
        "SCON.CANCEL-XT !",
        "SCON.CLEANUP-XT !",
        "STREAMS-CONNECTOR-DIRECTION-OUTPUT",
        "XIO-OP-SIZE",
        "STREAMS-PROTOCOL-ATPROTO",
        "STREAMS-EVENT-PAYLOAD-COPY",
        "BSKY-TEXT-RECORD-ENCODE",
        "TID-CLOCK-NEXT-MS",
        "app.bsky.feed.post",
        "1000 /",
        "AT-CREATE-RECORD-PREPARE",
        "AT-CREATE-RECORD-XIO-START",
        "AT-CREATE-RECORD-XIO-POLL",
        "AT-CREATE-RECORD-XIO-CANCEL",
        "AT-CREATE-RECORD-XIO-WIPE",
        "AT-CREATE-RECORD-RESULT-OUTCOME@",
        "AT-CREATE-RECORD-RESULT-URI@",
        "AT-CREATE-RECORD-RESULT-CID@",
        "AT-CREATE-RECORD-OUTCOME-CREATED",
        "AT-CREATE-RECORD-OUTCOME-NO-EFFECT",
        "AT-CREATE-RECORD-OUTCOME-UNCERTAIN",
        "STREAMS-CONNECTOR-COMPLETION-DELIVERED",
        "STREAMS-CONNECTOR-COMPLETION-FAILED",
        "STREAMS-CONNECTOR-COMPLETION-CANCELLED",
        "STREAMS-CONNECTOR-COMPLETION-INDETERMINATE",
        "STREAMS-EFFECT-APPLIED",
        "STREAMS-EFFECT-NOT-APPLIED",
        "STREAMS-EFFECT-UNCERTAIN",
    ):
        assert marker in source

    init = _word_body(source, "AT-TEXT-POST-CONNECTOR-INIT")
    assert "AT-CREATE-RECORD-EXTERNAL-SPAN-STATUS" in source
    assert "STREAMS-CONNECTOR-SEAL" in init

    assert "PROVIDED akashic-at-create-rec" in seam
    for word in (
        "ATPCS-INIT",
        "ATPCS-MODE!",
        "ATPCS-WIPE-IOR!",
        "AT-CREATE-RECORD-VALID?",
        "AT-CREATE-RECORD-STATE@",
        "AT-CREATE-RECORD-CLEANUP-ERROR@",
        "AT-CREATE-RECORD-TARGET?",
        "AT-CREATE-RECORD-EXTERNAL-SPAN-STATUS",
        "AT-CREATE-RECORD-RESULT@",
        "AT-CREATE-RECORD-PREPARE",
        "AT-CREATE-RECORD-XIO-START",
        "AT-CREATE-RECORD-XIO-POLL",
        "AT-CREATE-RECORD-XIO-CANCEL",
        "AT-CREATE-RECORD-XIO-WIPE",
        "AT-CREATE-RECORD-RESULT-OUTCOME@",
        "AT-CREATE-RECORD-RESULT-URI@",
        "AT-CREATE-RECORD-RESULT-CID@",
    ):
        assert word in seam

    assert "PROVIDED akashic-atpost-egress-test" in fixture
    for word in (
        "_ATPET-START",
        "_ATPET-SETUP",
        "_ATPET-PREFLIGHT",
        "_ATPET-CREATED",
        "_ATPET-OUTCOMES",
        "_ATPET-CANCEL-CLEANUP",
        "_ATPET-FINISH",
    ):
        assert word in fixture
    for evidence in (
        "3kuxxnvrfns2b",
        "3kuxxppt6us2f",
        "3kuxxnvrfnt2b",
        "2024-06-15T15:30:00Z",
        "2024-06-15T15:31:00Z",
        "ATPCS-MODE-NO-EFFECT",
        "ATPCS-MODE-UNCERTAIN",
        "ATPCS-MODE-CANCEL-NO-EFFECT",
        "ATPCS-MODE-CANCEL-UNCERTAIN",
        "AT-TEXT-POST-CONNECTOR-S-TARGET",
        "AT-TEXT-POST-CONNECTOR-S-ALIAS",
        "AT-TEXT-POST-CONNECTOR-LAST-EPOCH-MS@",
        "_atpet-operation-alias-preflight",
        "_atpet-result-payload-alias-preflight",
        "SCON.START-XT @ EXECUTE",
        "SCON.POLL-XT @ EXECUTE",
        "SCON.CANCEL-XT @ EXECUTE",
        "SCON.CLEANUP-XT @ EXECUTE",
    ):
        assert evidence in fixture

    all_paths = tuple(SOURCE_ROOT / module for module in RUNTIME_MODULES) + (
        SEAM,
        SOURCE,
        CONTRACT,
    )
    forbidden_line_parsers = {
        "SOURCE",
        ">IN",
        "REFILL",
        "PARSE",
        "WORD",
        "EVALUATE",
    }
    for path in all_paths:
        text = path.read_text(encoding="utf-8")
        _assert_physical_comments(path, text)
        assert not forbidden_line_parsers & set(_forth_code(text).split()), path

    bundle_files = _bundle_files()
    assert 2 <= len(bundle_files) <= 5
    assert all(len(source_bytes) <= BUNDLE_BYTES for _, source_bytes in bundle_files)
    assert sum(len(source_bytes) for _, source_bytes in bundle_files) < 400_000
    assert all(len(Path(name).name.encode("utf-8")) <= 23 for name, _ in bundle_files)


RUNTIME_STAGES = (
    ("setup", "_ATPET-START _ATPET-SETUP", "AT TEXT POST EGRESS SETUP READY"),
    (
        "preflight",
        "_ATPET-PREFLIGHT",
        "AT TEXT POST EGRESS PREFLIGHT READY",
    ),
    ("created", "_ATPET-CREATED", "AT TEXT POST EGRESS CREATED READY"),
    ("outcomes", "_ATPET-OUTCOMES", "AT TEXT POST EGRESS OUTCOMES READY"),
    (
        "cancel-cleanup",
        "_ATPET-CANCEL-CLEANUP",
        "AT TEXT POST EGRESS CANCEL CLEANUP READY",
    ),
    ("finish", "_ATPET-FINISH", PASS_MARKER),
)

FAILURE_MARKERS = (
    "AT TEXT POST EGRESS FAIL",
    "AT TEXT POST EGRESS ASSERT",
    "AT TEXT POST EGRESS STACK",
    "AT TEXT POST EGRESS LOAD STACK FAIL",
    "DRIVER THROW",
    "Branch offset overflow",
    "dictionary full",
    "exception",
    "Module not found",
    "Path component not found",
    "? (not found)",
    "(not found)",
)


def _autoexec(bundle_files: tuple[tuple[str, bytes], ...]) -> str:
    lines = [
        "\\ autoexec.f - focused AT text-post Streams qualification\n",
        "ENTER-USERLAND\n",
        f'." {BOOT_MARKER}" CR TX-FLUSH\n',
        "KEY DROP\n",
    ]
    for index, (guest, _) in enumerate(bundle_files, start=1):
        lines.extend(
            (
                f"REQUIRE {guest}\n",
                (
                    'DEPTH IF ." AT TEXT POST EGRESS LOAD STACK FAIL '
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
    bundle_files = _bundle_files()
    harness.PROFILES[PROFILE] = harness.Profile(
        roots=(),
        resources=(),
        autoexec=_autoexec(bundle_files),
        ready_markers=(PASS_MARKER,),
        stable_markers=(PASS_MARKER,),
        failure_markers=FAILURE_MARKERS,
        initial_files=bundle_files,
        linked=False,
        include_large_sample=False,
        total_sectors=4096,
    )
    image = harness.build_image(PROFILE, IMAGE)
    profile = harness.PROFILES[PROFILE]
    stages = (
        ("boot", BOOT_MARKER),
        *(
            (f"bundle-{index:02d}", _bundle_marker(index))
            for index in range(1, len(bundle_files) + 1)
        ),
        *((name, marker) for name, _, marker in RUNTIME_STAGES),
    )

    with harness.MachineSession.from_bios(
        harness.MEGAPAD_ROOT / "bios.asm",
        storage_image=image,
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
            raw = machine.raw_text()
            failures = tuple(
                dict.fromkeys(
                    (
                        *harness._has_forth_error(raw),  # noqa: SLF001
                        *harness._matched_failure_markers(  # noqa: SLF001
                            profile,
                            raw,
                            machine.screen_text(),
                        ),
                    )
                )
            )
            if marker not in raw or failures:
                print(f"AT TEXT POST EGRESS {stage_name}: FAIL")
                print(
                    f"  {report.steps:,} steps in {report.elapsed_s:.2f}s; "
                    f"stop={report.reason}"
                )
                for failure in failures:
                    print(f"  {failure}")
                print(raw[-5000:])
                return 1
            print(
                f"AT TEXT POST EGRESS {stage_name}: PASS "
                f"({report.steps:,} steps, {report.elapsed_s:.2f}s)",
                flush=True,
            )
    print("AT TEXT POST EGRESS vertical: PASS")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument("--static-only", action="store_true")
    mode.add_argument(
        "--vertical",
        action="store_true",
        help="run the staged single-core seam-backed emulator gate",
    )
    parser.add_argument("--timeout", type=float, default=120.0)
    args = parser.parse_args()

    _assert_static()
    if not args.vertical:
        print("AT TEXT POST EGRESS STATIC PASS")
        return 0
    return _run_vertical(args.timeout)


if __name__ == "__main__":
    raise SystemExit(main())
