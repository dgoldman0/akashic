#!/usr/bin/env python3
"""Prove a current Library seed and exact replay across two cold processes.

The first guest provisions the current MP64FS-backed repository, creates one
managed document through the semantic service, and verifies bounded query,
exact read, content delivery, and its operation receipt.  The parent keeps
only serialized disk bytes and the printed RID, replaces ``autoexec.f``, and
starts a second Python process with a fresh emulator and Forth dictionary.

The cold guest reconstructs the exact public request, reopens and repeats the
semantic readback, then replays the create key with deliberately stale expected
logical generation zero.  Replay must return the original value without
physical, logical, mutation-sequence, or document-count change.

Broader lifecycle, retained-history, capture, collection, query, applet, and
projection-owner parity stays in focused same-VFS gates.  This test supplies
their bounded missing fact: current repository/service state survives a real
fresh-process boundary before those higher layers consume it.
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
    DEFAULT_EXT_MEM_MIB,
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
PROFILE_NAME: Final = "_library-managed-two-cold-processes"
GUEST_FIXTURE: Final = "local_testing/lib-cold-l12-test.f"
FIRST_MARKER: Final = "LIBRARY MANAGED FIRST BOOT PASS"
COLD_MARKER: Final = "LIBRARY MANAGED COLD BOOT PASS"
FIRST_FAILURES: Final = (
    "LIBRARY MANAGED FIRST BOOT FAIL",
    "LIBRARY MANAGED FIRST ASSERT",
    "EVALUATE input exceeds",
    "EVALUATE depth limit exceeded",
    " ? (not found)",
    "dictionary full",
    "exception",
)
COLD_FAILURES: Final = (
    "LIBRARY MANAGED COLD BOOT FAIL",
    "LIBRARY MANAGED COLD ASSERT",
    "EVALUATE input exceeds",
    "EVALUATE depth limit exceeded",
    " ? (not found)",
    "dictionary full",
    "exception",
)
RID_RE: Final = re.compile(r"LIBRARY MANAGED FIRST RID +([0-9A-F]{64})")


FIRST_AUTOEXEC = rf"""\ autoexec.f - first current Library persistence boot
ENTER-USERLAND
REQUIRE tui/applets/library/service.f
REQUIRE utils/fs/drivers/vfs-mp64fs.f
REQUIRE {GUEST_FIXTURE}
_LC12-FIRST-RUN
0 0xFFFFFF0000000006 C!
"""


def _forth_bytes(data: bytes) -> str:
    """Return bounded bytes as readable ``C,`` rows for generated Forth."""
    return "\n".join(
        " ".join(f"0x{byte:02X} C," for byte in data[offset : offset + 8])
        for offset in range(0, len(data), 8)
    )


def _cold_autoexec(expected_rid: bytes) -> str:
    if len(expected_rid) != 32:
        raise ValueError("a Library RID must contain exactly 32 bytes")
    return rf"""\ autoexec.f - cold current Library persistence readback
ENTER-USERLAND
REQUIRE tui/applets/library/service.f
REQUIRE utils/fs/drivers/vfs-mp64fs.f
REQUIRE {GUEST_FIXTURE}

CREATE _lmc-expected-rid
{_forth_bytes(expected_rid)}

_lmc-expected-rid _LC12-COLD-RUN
0 0xFFFFFF0000000006 C!
"""


def _profile() -> Profile:
    """Return the current linked Library closure used by both processes."""
    return Profile(
        roots=(
            "tui/applets/library/service.f",
            "utils/fs/drivers/vfs-mp64fs.f",
        ),
        resources=(),
        autoexec=FIRST_AUTOEXEC,
        ready_markers=(FIRST_MARKER,),
        stable_markers=(FIRST_MARKER,),
        failure_markers=FIRST_FAILURES,
        initial_files=(
            (
                GUEST_FIXTURE,
                (LOCAL_TESTING / Path(GUEST_FIXTURE).name).read_bytes(),
            ),
        ),
        linked=True,
        include_large_sample=False,
        total_sectors=8192,
    )


def _linked_layout(
    profile: Profile,
) -> tuple[tuple[str, ...], dict[str, bytes]]:
    """Reproduce the deterministic linked module layout built for both boots."""
    if not profile.linked:
        raise ValueError("Library managed two-boot profile must be linked")
    modules = dependency_order(profile.roots)
    chunks = _linked_chunks(modules, profile.link_chunk_bytes)
    if not chunks:
        raise RuntimeError("Library managed linked closure produced no chunks")
    return modules, chunks


def _assert_linked_manifest(
    filesystem: MP64FS,
    chunks: dict[str, bytes],
) -> tuple[str, ...]:
    """Verify and return the exact persisted linked chunks from the first boot."""
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
            raise RuntimeError(f"first-boot linked chunk content changed: {path}")
    return tuple(chunks)


def _linked_cold_autoexec(
    filesystem: MP64FS,
    profile: Profile,
    expected_rid: bytes,
) -> str:
    """Link the cold script against the exact verified first-boot chunks."""
    modules, chunks = _linked_layout(profile)
    chunk_names = _assert_linked_manifest(filesystem, chunks)
    return _linked_autoexec(_cold_autoexec(expected_rid), chunk_names, modules)


def _run_until(
    image: Path,
    marker: str,
    failures: tuple[str, ...],
    timeout: float,
) -> tuple[bytes, str, int, float]:
    """Run one fresh emulator until its guest reports a terminal marker."""
    started = time.monotonic()
    deadline = time.monotonic() + timeout
    steps = 0
    with MachineSession.from_bios(
        MEGAPAD_ROOT / "bios.asm",
        storage_image=image,
        cols=108,
        rows=34,
        batch_steps=500_000,
        ext_mem_size=DEFAULT_EXT_MEM_MIB << 20,
        num_cores=1,
    ) as session:
        session.boot()
        while time.monotonic() < deadline and steps < 12_000_000_000:
            report = session.run(
                max_steps=50_000_000,
                wall_timeout_s=min(2.0, max(0.05, deadline - time.monotonic())),
                advance_idle=True,
            )
            steps += report.steps
            screen = session.snapshot().text()
            failure = next((item for item in failures if item in screen), None)
            if failure is not None:
                raise RuntimeError(
                    f"guest reported {failure!r} after {steps:,} steps "
                    f"in {time.monotonic() - started:.2f}s\n{screen}"
                )
            if marker in screen:
                raw = session.raw_text()
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
    failures: tuple[str, ...],
    timeout: float,
    sender: Connection,
) -> None:
    """Run one boot in a spawned process and return serialized evidence."""
    try:
        disk, output, steps, elapsed = _run_until(
            Path(image), marker, failures, timeout
        )
        sender.send(("ok", disk, output, steps, elapsed))
    except BaseException:  # Preserve the child traceback for the CLI caller.
        sender.send(("error", traceback.format_exc()))
    finally:
        sender.close()


def _run_in_fresh_process(
    image: Path,
    marker: str,
    failures: tuple[str, ...],
    timeout: float,
) -> tuple[bytes, str, int, float]:
    """Start one spawn-isolated process containing exactly one machine boot."""
    context = multiprocessing.get_context("spawn")
    receiver, sender = context.Pipe(duplex=False)
    process = context.Process(
        target=_worker,
        args=(str(image), marker, failures, timeout, sender),
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
        raise RuntimeError(f"invalid cold-boot worker result: {payload[0]!r}")
    disk, output, steps, elapsed = payload[1:]
    if (
        not isinstance(disk, bytes)
        or not isinstance(output, str)
        or not isinstance(steps, int)
        or not isinstance(elapsed, float)
    ):
        raise RuntimeError("cold-boot worker returned malformed evidence")
    if process.exitcode != 0:
        raise RuntimeError(f"cold-boot worker exited with status {process.exitcode}")
    return disk, output, steps, elapsed


def _first_rid(output: str) -> bytes:
    match = RID_RE.search(output)
    if match is None:
        raise RuntimeError("first boot passed without printing its durable RID")
    return bytes.fromhex(match.group(1))


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--image",
        type=Path,
        default=Path("/tmp/akashic-library-managed-two-boot.img"),
    )
    parser.add_argument("--timeout", type=float, default=360.0)
    args = parser.parse_args()
    if args.timeout <= 0:
        parser.error("--timeout must be greater than zero")

    fixture_name = Path(GUEST_FIXTURE).name
    if len(fixture_name) > 23:
        raise AssertionError(f"MP64FS fixture component is too long: {fixture_name}")

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
        _run_in_fresh_process(
            image, FIRST_MARKER, FIRST_FAILURES, args.timeout
        )
    )
    expected_rid = _first_rid(first_output)

    filesystem = MP64FS(bytearray(first_disk))
    if filesystem.find_file("autoexec.f") is None:
        raise RuntimeError("first-boot image has no autoexec.f to replace")
    cold_autoexec = _linked_cold_autoexec(filesystem, profile, expected_rid)
    filesystem.delete_file("autoexec.f")
    filesystem.inject_file(
        "autoexec.f",
        cold_autoexec.encode("utf-8"),
        ftype=FTYPE_FORTH,
    )
    filesystem.save(image)

    _, _, cold_steps, cold_elapsed = _run_in_fresh_process(
        image, COLD_MARKER, COLD_FAILURES, args.timeout
    )
    print(
        "Library current-format two-process cold acceptance: PASS "
        f"({image}, RID {expected_rid.hex()}; "
        f"first {first_steps:,} steps/{first_elapsed:.2f}s, "
        f"cold {cold_steps:,} steps/{cold_elapsed:.2f}s)"
    )
    return 0


if __name__ == "__main__":
    multiprocessing.freeze_support()
    raise SystemExit(main())
