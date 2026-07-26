#!/usr/bin/env python3
"""Prove the composed SR2/SR3 journey across two isolated cold boots.

The first one-core process creates exact SR2 outputs, admits three durable
attempts, exercises independent outbox and runtime pressure, and terminalizes
two attempts while leaving one exact 4,097-byte attempt READY.  The parent
retains only serialized MP64FS bytes and the three printed attempt RIDs.  A
fresh process and Forth dictionary must reopen the same current-format
authority, inspect the terminal evidence, dispatch the remaining exact bytes
through a fitting standard cell, and release all runtime state.

The emulator processes run strictly sequentially.  This module never creates
more than one guest worker and every guest machine has exactly one core.
"""

from __future__ import annotations

import argparse
import multiprocessing
import re
import time
import traceback
from multiprocessing.connection import Connection
from pathlib import Path
from typing import Final

from akashic_tui import (
    FTYPE_FORTH,
    MEGAPAD_ROOT,
    MP64FS,
    PROFILES,
    MachineSession,
    Profile,
    _linked_autoexec,
    _linked_chunks,
    build_image,
    dependency_order,
)


LOCAL_TESTING: Final = Path(__file__).resolve().parent
PROFILE_NAME: Final = "_streams-sr3-composed-two-cold-processes"
GUEST_FIXTURE: Final = "local_testing/streams-sr3-composed.f"
FIRST_MARKER: Final = "STREAMS SR3 COMPOSED FIRST BOOT PASS"
COLD_MARKER: Final = "STREAMS SR3 COMPOSED COLD BOOT PASS"
FAILURES: Final = (
    "STREAMS SR3 COMPOSED FIRST BOOT FAIL",
    "STREAMS SR3 COMPOSED COLD BOOT FAIL",
    "STREAMS SR3 COMPOSED FIRST ASSERT",
    "STREAMS SR3 COMPOSED COLD ASSERT",
    "STREAMS SR3 COMPOSED STACK",
    "STREAMS SR3 COMPOSED AUDIT GEOMETRY",
    "EVALUATE input exceeds",
    "EVALUATE depth limit exceeded",
    " ? (not found)",
    "dictionary full",
    "exception",
)
DELIVERED_RID_RE: Final = re.compile(
    r"STREAMS SR3 COMPOSED DELIVERED RID +([0-9A-F]{64})"
)
FAILURE_RID_RE: Final = re.compile(
    r"STREAMS SR3 COMPOSED FAILURE RID +([0-9A-F]{64})"
)
LARGE_RID_RE: Final = re.compile(
    r"STREAMS SR3 COMPOSED LARGE RID +([0-9A-F]{64})"
)
MAX_STEPS: Final = 4_000_000_000
EXT_MEM_MIB: Final = 128


FIRST_AUTOEXEC = rf"""\ autoexec.f - first composed SR2/SR3 boot
ENTER-USERLAND
REQUIRE tui/applets/streams/operational-dispatch.f
REQUIRE utils/fs/drivers/vfs-mp64fs.f
REQUIRE {GUEST_FIXTURE}
_SR3C-FIRST-RUN
0 0xFFFFFF0000000006 C!
"""


def _forth_bytes(data: bytes) -> str:
    """Return exact bytes as bounded readable Forth ``C,`` rows."""
    return "\n".join(
        " ".join(f"0x{byte:02X} C," for byte in data[offset : offset + 8])
        for offset in range(0, len(data), 8)
    )


def _cold_autoexec(
    delivered_id: bytes,
    failure_id: bytes,
    large_id: bytes,
) -> str:
    ids = (delivered_id, failure_id, large_id)
    if any(len(attempt_id) != 32 for attempt_id in ids):
        raise ValueError("every Streams attempt RID must contain 32 bytes")
    return rf"""\ autoexec.f - cold composed SR2/SR3 readback
ENTER-USERLAND
REQUIRE tui/applets/streams/operational-dispatch.f
REQUIRE utils/fs/drivers/vfs-mp64fs.f
REQUIRE {GUEST_FIXTURE}

CREATE _sr3c-driver-delivered-id
{_forth_bytes(delivered_id)}
CREATE _sr3c-driver-failure-id
{_forth_bytes(failure_id)}
CREATE _sr3c-driver-large-id
{_forth_bytes(large_id)}

_sr3c-driver-delivered-id
_sr3c-driver-failure-id
_sr3c-driver-large-id
_SR3C-COLD-RUN
0 0xFFFFFF0000000006 C!
"""


def _profile() -> Profile:
    return Profile(
        roots=(
            "tui/applets/streams/operational-dispatch.f",
            "utils/fs/drivers/vfs-mp64fs.f",
        ),
        resources=(),
        autoexec=FIRST_AUTOEXEC,
        ready_markers=(FIRST_MARKER,),
        stable_markers=(FIRST_MARKER,),
        failure_markers=FAILURES,
        initial_files=(
            (
                GUEST_FIXTURE,
                (LOCAL_TESTING / Path(GUEST_FIXTURE).name).read_bytes(),
            ),
        ),
        linked=True,
        link_chunk_bytes=192 * 1024,
        include_large_sample=False,
        total_sectors=8192,
    )


def _linked_layout(
    profile: Profile,
) -> tuple[tuple[str, ...], dict[str, bytes]]:
    if not profile.linked:
        raise ValueError("Streams SR3 composed profile must be linked")
    modules = dependency_order(profile.roots)
    chunks = _linked_chunks(modules, profile.link_chunk_bytes)
    if not chunks:
        raise RuntimeError("Streams SR3 linked closure produced no chunks")
    return modules, chunks


def _assert_linked_manifest(
    filesystem: MP64FS,
    chunks: dict[str, bytes],
) -> tuple[str, ...]:
    parent = filesystem.resolve_path("/.akashic")
    expected_names = tuple(Path(path).name for path in chunks)
    actual_names = tuple(
        sorted(entry.name for entry in filesystem.list_files(parent=parent))
    )
    if actual_names != tuple(sorted(expected_names)):
        raise RuntimeError(
            "first-boot linked chunk manifest changed: "
            f"expected {expected_names!r}, found {actual_names!r}"
        )
    for path, expected_content in chunks.items():
        name = Path(path).name
        actual_content = filesystem.read_file(name, parent=parent)
        if actual_content != expected_content:
            raise RuntimeError(f"first-boot linked chunk changed: {path}")
    return tuple(chunks)


def _linked_cold_autoexec(
    filesystem: MP64FS,
    profile: Profile,
    attempt_ids: tuple[bytes, bytes, bytes],
) -> str:
    modules, chunks = _linked_layout(profile)
    chunk_names = _assert_linked_manifest(filesystem, chunks)
    return _linked_autoexec(
        _cold_autoexec(*attempt_ids),
        chunk_names,
        modules,
    )


def _run_until(
    image: Path,
    marker: str,
    timeout: float,
) -> tuple[bytes, str, int, float]:
    """Run one fresh single-core emulator until a terminal marker."""
    started = time.monotonic()
    deadline = started + timeout
    steps = 0
    with MachineSession.from_bios(
        MEGAPAD_ROOT / "bios.asm",
        storage_image=image,
        cols=108,
        rows=34,
        batch_steps=500_000,
        ext_mem_size=EXT_MEM_MIB << 20,
        num_cores=1,
    ) as session:
        session.boot()
        while time.monotonic() < deadline and steps < MAX_STEPS:
            report = session.run(
                max_steps=min(50_000_000, MAX_STEPS - steps),
                wall_timeout_s=min(
                    2.0,
                    max(0.05, deadline - time.monotonic()),
                ),
                advance_idle=True,
            )
            steps += report.steps
            screen = session.snapshot().text()
            failure = next((item for item in FAILURES if item in screen), None)
            if failure is not None:
                raw = session.raw_text()
                raise RuntimeError(
                    f"guest reported {failure!r} after {steps:,} steps "
                    f"in {time.monotonic() - started:.2f}s\n"
                    f"{screen}\n{raw[-12000:]}"
                )
            if marker in screen:
                raw = session.raw_text()
                failure = next(
                    (item for item in FAILURES if item in screen + "\n" + raw),
                    None,
                )
                if failure is not None:
                    raise RuntimeError(
                        f"guest reported {failure!r} after {steps:,} steps "
                        f"in {time.monotonic() - started:.2f}s\n"
                        f"{screen}\n{raw[-4000:]}"
                    )
                return (
                    bytes(session.system.storage._image_data),
                    screen + "\n" + raw,
                    steps,
                    time.monotonic() - started,
                )
            if report.reason in ("halted", "stalled"):
                break
        raw = session.raw_text()
        screen = session.snapshot().text()
        raise RuntimeError(
            f"timed out waiting for {marker!r} after {steps:,} steps "
            f"in {time.monotonic() - started:.2f}s\n"
            f"{screen}\n{raw[-4000:]}"
        )


def _worker(
    image: str,
    marker: str,
    timeout: float,
    sender: Connection,
) -> None:
    try:
        disk, output, steps, elapsed = _run_until(
            Path(image),
            marker,
            timeout,
        )
        sender.send(("ok", disk, output, steps, elapsed))
    except BaseException:
        sender.send(("error", traceback.format_exc()))
    finally:
        sender.close()


def _run_in_fresh_process(
    image: Path,
    marker: str,
    timeout: float,
) -> tuple[bytes, str, int, float]:
    """Spawn exactly one process and join it before any later boot."""
    context = multiprocessing.get_context("spawn")
    receiver, sender = context.Pipe(duplex=False)
    process = context.Process(
        target=_worker,
        args=(str(image), marker, timeout, sender),
        name=f"akashic-{marker.lower().replace(' ', '-')}",
    )
    process.start()
    sender.close()
    deadline = time.monotonic() + timeout + 60.0
    payload: tuple[object, ...] | None = None
    try:
        while time.monotonic() < deadline:
            if receiver.poll(0.2):
                payload = receiver.recv()
                break
            if not process.is_alive():
                if receiver.poll():
                    payload = receiver.recv()
                break
    finally:
        receiver.close()
        if process.is_alive() and payload is None:
            process.terminate()
        process.join(timeout=10.0)
        if process.is_alive():
            process.kill()
            process.join()

    if payload is None:
        raise RuntimeError(
            f"cold-boot worker exited without evidence (exit {process.exitcode})"
        )
    if payload[0] == "error":
        raise RuntimeError(str(payload[1]))
    if payload[0] != "ok" or len(payload) != 5:
        raise RuntimeError(f"invalid cold-boot result: {payload[0]!r}")
    disk, output, steps, elapsed = payload[1:]
    if (
        not isinstance(disk, bytes)
        or not isinstance(output, str)
        or not isinstance(steps, int)
        or not isinstance(elapsed, float)
    ):
        raise RuntimeError("cold-boot worker returned malformed evidence")
    if process.exitcode != 0:
        raise RuntimeError(f"cold-boot worker exited with {process.exitcode}")
    return disk, output, steps, elapsed


def _first_attempt_ids(output: str) -> tuple[bytes, bytes, bytes]:
    matches = (
        DELIVERED_RID_RE.search(output),
        FAILURE_RID_RE.search(output),
        LARGE_RID_RE.search(output),
    )
    if any(match is None for match in matches):
        raise RuntimeError(
            "first boot passed without printing all three attempt RIDs"
        )
    attempt_ids = tuple(
        bytes.fromhex(match.group(1))
        for match in matches
        if match is not None
    )
    if len(attempt_ids) != 3:
        raise RuntimeError("first boot returned malformed attempt evidence")
    if len(set(attempt_ids)) != 3:
        raise RuntimeError("first boot returned duplicate attempt RIDs")
    return attempt_ids


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--image",
        type=Path,
        default=Path("/tmp/akashic-streams-sr3-composed.img"),
    )
    parser.add_argument("--timeout", type=float, default=180.0)
    args = parser.parse_args()
    if args.timeout <= 0:
        parser.error("--timeout must be greater than zero")

    fixture_name = Path(GUEST_FIXTURE).name
    if len(fixture_name) > 23:
        raise AssertionError(
            f"MP64FS fixture component is too long: {fixture_name}"
        )

    profile = _profile()
    previous = PROFILES.get(PROFILE_NAME)
    PROFILES[PROFILE_NAME] = profile
    try:
        image = build_image(PROFILE_NAME, args.image)
    finally:
        if previous is None:
            del PROFILES[PROFILE_NAME]
        else:
            PROFILES[PROFILE_NAME] = previous

    first_disk, first_output, first_steps, first_elapsed = (
        _run_in_fresh_process(image, FIRST_MARKER, args.timeout)
    )
    attempt_ids = _first_attempt_ids(first_output)

    filesystem = MP64FS(bytearray(first_disk))
    if filesystem.find_file("autoexec.f") is None:
        raise RuntimeError("first-boot image has no autoexec.f to replace")
    cold_autoexec = _linked_cold_autoexec(
        filesystem,
        profile,
        attempt_ids,
    )
    filesystem.delete_file("autoexec.f")
    filesystem.inject_file(
        "autoexec.f",
        cold_autoexec.encode("utf-8"),
        ftype=FTYPE_FORTH,
    )
    filesystem.save(image)

    _, _, cold_steps, cold_elapsed = _run_in_fresh_process(
        image,
        COLD_MARKER,
        args.timeout,
    )
    print(
        "Streams SR3 composed two-process cold gate: PASS "
        f"({image}; "
        f"delivered {attempt_ids[0].hex()}, "
        f"failure {attempt_ids[1].hex()}, "
        f"large {attempt_ids[2].hex()}; "
        f"first {first_steps:,} steps/{first_elapsed:.2f}s, "
        f"cold {cold_steps:,} steps/{cold_elapsed:.2f}s)"
    )
    return 0


if __name__ == "__main__":
    multiprocessing.freeze_support()
    raise SystemExit(main())
