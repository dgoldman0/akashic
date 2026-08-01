#!/usr/bin/env python3
"""Real-image tests for the read-only ext4 ABI-1 VFS binding."""

from __future__ import annotations

import hashlib
import json
import mmap
import os
import re
import shutil
import struct
import subprocess
import sys
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[1]
LOCAL_TESTING = Path(__file__).resolve().parent
if str(LOCAL_TESTING) not in sys.path:
    sys.path.insert(0, str(LOCAL_TESTING))

import test_vfs_fat as fat_harness  # noqa: E402
import generate_ext4_profile_fixtures as ext4_fixture_generator  # noqa: E402
from devices import (  # noqa: E402
    STORAGE_CMD_WRITE,
    STORAGE_RESULT_MEDIA_FAILURE,
)


EXT4_F = ROOT / "akashic" / "utils" / "fs" / "drivers" / "vfs-ext4.f"
MANIFEST = ROOT / "local_testing" / "fixtures" / "ext4-profile" / "manifest.json"
IMAGE_DIR = ROOT / "local_testing" / "out" / "ext4-profile"

with MANIFEST.open("r", encoding="utf-8") as source:
    PROFILE = json.load(source)

IMAGE_ROWS = {row["id"]: row for row in PROFILE["images"]}
IMAGE_IDS = tuple(
    image_id
    for image_id, row in IMAGE_ROWS.items()
    if row.get("fixture_role") != "read_side"
)
READ_SIDE_IMAGE_IDS = tuple(
    image_id
    for image_id, row in IMAGE_ROWS.items()
    if row.get("fixture_role") == "read_side"
)

_snapshot = None

FORTH_DIAGNOSTICS = (
    "? (not found)",
    "Stack underflow",
    "Branch offset overflow",
    "dictionary full",
    "EVALUATE depth limit exceeded",
)


def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for chunk in iter(lambda: source.read(1 << 20), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _feed_until_idle(system, payload: bytes, max_steps: int) -> int:
    position = 0
    steps = 0
    while steps < max_steps:
        if system.cpu.halted:
            break
        if system.cpu.idle and not system.uart.has_rx_data:
            if position < len(payload):
                chunk = fat_harness._next_line_chunk(payload, position)
                system.uart.inject_input(chunk)
                position += len(chunk)
            else:
                break
            continue
        batch = system.run_batch(min(100_000, max_steps - steps))
        steps += max(batch, 1)
    return steps


def _assert_no_forth_diagnostics(output: str) -> None:
    found = [marker for marker in FORTH_DIAGNOSTICS if marker.lower() in output.lower()]
    assert not found, f"Forth diagnostics {found}:\n{output[-4000:]}"


def build_snapshot():
    """Extend the proven FAT/VFS snapshot with the ext4 binding once."""
    global _snapshot
    if _snapshot is not None:
        return _snapshot

    fat_harness.build_snapshot()
    bios, memory, cpu_state, ext_memory = fat_harness._snapshot
    system = fat_harness.MegapadSystem(
        ram_size=1024 * 1024,
        ext_mem_size=fat_harness.VFS_EXT_MEM_SIZE,
        storage_image=fat_harness._boot_img_path,
    )
    uart = fat_harness.capture_uart(system)
    system.load_binary(0, bios)
    system.boot()
    for _ in range(5_000_000):
        if system.cpu.idle and not system.uart.has_rx_data:
            break
        system.run_batch(10_000)
    system.cpu.mem[: len(memory)] = memory
    system._ext_mem[: len(ext_memory)] = ext_memory
    fat_harness.restore_cpu_state(system.cpu, cpu_state)
    uart.clear()

    lines = fat_harness._load_forth_lines(str(EXT4_F))
    _feed_until_idle(system, ("\n".join(lines) + "\n").encode(), 800_000_000)
    transcript = fat_harness.uart_text(uart)
    _assert_no_forth_diagnostics(transcript)

    _snapshot = (
        bios,
        bytes(system.cpu.mem),
        fat_harness.save_cpu_state(system.cpu),
        bytes(system._ext_mem),
    )
    return _snapshot


def run_forth(
    image: Path,
    lines: list[str],
    *,
    patches: tuple[tuple[int, bytes], ...] = (),
    storage_faults: tuple[dict, ...] = (),
    max_steps: int = 800_000_000,
) -> str:
    """Run against a COW mapping so even the 512 MiB fixture stays bounded."""
    bios, memory, cpu_state, ext_memory = build_snapshot()
    system = fat_harness.MegapadSystem(
        ram_size=1024 * 1024,
        ext_mem_size=fat_harness.VFS_EXT_MEM_SIZE,
        storage_image=fat_harness._boot_img_path,
    )
    uart = fat_harness.capture_uart(system)
    system.load_binary(0, bios)
    system.boot()
    for _ in range(5_000_000):
        if system.cpu.idle and not system.uart.has_rx_data:
            break
        system.run_batch(10_000)
    system.cpu.mem[: len(memory)] = memory
    system._ext_mem[: len(ext_memory)] = ext_memory
    fat_harness.restore_cpu_state(system.cpu, cpu_state)

    with image.open("rb") as source, mmap.mmap(
        source.fileno(), 0, access=mmap.ACCESS_COPY
    ) as mapped:
        for offset, data in patches:
            mapped[offset : offset + len(data)] = data
        system.storage._replace_media(mapped, str(image))
        system.storage.write_protected = False
        write_requests = 0
        flush_requests = 0
        start_dma = system.storage._start_dma
        run_flush = system.storage._run_flush

        def track_dma(request, phase):
            nonlocal write_requests
            if phase == "write":
                write_requests += 1
            return start_dma(request, phase)

        def track_flush(request):
            nonlocal flush_requests
            flush_requests += 1
            return run_flush(request)

        system.storage._start_dma = track_dma
        system.storage._run_flush = track_flush
        for fault in storage_faults:
            system.storage.inject_fault(**fault)
        uart.clear()
        stack_check = (
            'DEPTH DUP 0= IF DROP ." EXT4-STACK-CLEAN" '
            'ELSE ." EXT4-STACK-LEAK " . THEN'
        )
        payload = ("\n".join((*lines, stack_check, "BYE")) + "\n").encode()
        _feed_until_idle(system, payload, max_steps)
        output = fat_harness.uart_text(uart)
        _assert_no_forth_diagnostics(output)
        if not system.cpu.halted or not output.endswith("Bye!\r\n"):
            raise AssertionError(
                "ext4 Forth journey did not consume BYE and halt:\n"
                + output[-2000:]
            )
        assert write_requests == 0
        assert flush_requests == 0
        _assert_emitted(output, "EXT4-STACK-CLEAN")
        return output


def run_recovery_forth(
    image: Path,
    backing: Path,
    lines: list[str],
    *,
    patches: tuple[tuple[int, bytes], ...] = (),
    write_protected: bool = False,
    storage_faults: tuple[dict, ...] = (),
    write_faults_by_ordinal: dict[int, dict] | None = None,
    capture_media: Path | None = None,
    max_steps: int = 800_000_000,
) -> tuple[str, tuple[tuple[str, int, int], ...], str]:
    """Run recovery on private mutable media and return its ordered I/O trace."""
    bios, memory, cpu_state, ext_memory = build_snapshot()
    system = fat_harness.MegapadSystem(
        ram_size=1024 * 1024,
        ext_mem_size=fat_harness.VFS_EXT_MEM_SIZE,
        storage_image=fat_harness._boot_img_path,
    )
    uart = fat_harness.capture_uart(system)
    system.load_binary(0, bios)
    system.boot()
    for _ in range(5_000_000):
        if system.cpu.idle and not system.uart.has_rx_data:
            break
        system.run_batch(10_000)
    system.cpu.mem[: len(memory)] = memory
    system._ext_mem[: len(ext_memory)] = ext_memory
    fat_harness.restore_cpu_state(system.cpu, cpu_state)

    media = bytearray(image.read_bytes())
    for offset, data in patches:
        media[offset : offset + len(data)] = data
    system.storage._replace_media(media, str(backing))
    system.storage.write_protected = write_protected
    trace: list[tuple[str, int, int]] = []
    start_dma = system.storage._start_dma
    run_flush = system.storage._run_flush
    write_ordinal = 0

    def track_dma(request, phase):
        nonlocal write_ordinal
        if phase == "write":
            write_ordinal += 1
            trace.append(("write", request[1], request[3]))
            if write_faults_by_ordinal and write_ordinal in write_faults_by_ordinal:
                system.storage.inject_fault(
                    **write_faults_by_ordinal[write_ordinal]
                )
        return start_dma(request, phase)

    def track_flush(request):
        trace.append(("flush", 0, 0))
        return run_flush(request)

    system.storage._start_dma = track_dma
    system.storage._run_flush = track_flush
    for fault in storage_faults:
        system.storage.inject_fault(**fault)
    uart.clear()
    stack_check = (
        'DEPTH DUP 0= IF DROP ." EXT4-STACK-CLEAN" '
        'ELSE ." EXT4-STACK-LEAK " . THEN'
    )
    payload = ("\n".join((*lines, stack_check, "BYE")) + "\n").encode()
    _feed_until_idle(system, payload, max_steps)
    output = fat_harness.uart_text(uart)
    _assert_no_forth_diagnostics(output)
    if not system.cpu.halted or not output.endswith("Bye!\r\n"):
        raise AssertionError(
            "ext4 recovery journey did not consume BYE and halt:\n"
            + output[-2000:]
        )
    _assert_emitted(output, "EXT4-STACK-CLEAN")
    if capture_media is not None:
        capture_media.write_bytes(media)
    return output, tuple(trace), hashlib.sha256(media).hexdigest()


def _assert_emitted(output: str, marker: str) -> None:
    """Require executed output, not the marker text echoed in Forth source."""
    assert f"\r\n{marker} ok\r\n" in output, output[-4000:]


@pytest.fixture(scope="session")
def canonical_images() -> dict[str, Path]:
    paths: dict[str, Path] = {}
    missing = []
    for image_id in IMAGE_IDS:
        row = IMAGE_ROWS[image_id]
        path = IMAGE_DIR / row["filename"]
        if not path.is_file():
            missing.append(str(path))
            continue
        assert path.stat().st_size == row["image_bytes"]
        assert _sha256(path) == row["expected_sha256"]
        paths[image_id] = path
    if missing:
        pytest.skip(
            "canonical ext4 images are absent; run "
            "generate_ext4_profile_fixtures.py with the pinned tool suite: "
            + ", ".join(missing)
        )
    return paths


@pytest.fixture(scope="session")
def read_side_image() -> Path:
    assert READ_SIDE_IMAGE_IDS == ("read-side-1k-i256",)
    image_id = READ_SIDE_IMAGE_IDS[0]
    row = IMAGE_ROWS[image_id]
    path = IMAGE_DIR / row["filename"]
    if not path.is_file():
        pytest.skip(
            "the supplemental ext4 read-side image is absent; run "
            "generate_ext4_profile_fixtures.py with --image " + image_id
        )
    assert path.stat().st_size == row["image_bytes"]
    assert _sha256(path) == row["expected_sha256"]
    return path


@pytest.fixture(scope="session")
def replay_fixture(
    canonical_images: dict[str, Path], tmp_path_factory: pytest.TempPathFactory
) -> dict[str, object]:
    tool_dir_value = os.environ.get("AKASHIC_E2FSPROGS_TOOL_DIR")
    if not tool_dir_value:
        pytest.skip("set AKASHIC_E2FSPROGS_TOOL_DIR for JBD2 recovery tests")
    debugfs = Path(tool_dir_value).resolve() / "debugfs"
    if not debugfs.is_file() or not os.access(debugfs, os.X_OK):
        pytest.skip(f"pinned debugfs is absent: {debugfs}")
    env = os.environ.copy()
    env["LANG"] = "C"
    env["PATH"] = f"{debugfs.parent}:/usr/bin:/bin"
    version = subprocess.run(
        [str(debugfs), "-V"],
        env=env,
        text=True,
        capture_output=True,
        check=False,
    )
    banner = version.stdout + version.stderr
    assert version.returncode == 0
    assert "debugfs 1.47.4" in banner
    assert "Using EXT2FS Library version 1.47.4" in banner

    directory = tmp_path_factory.mktemp("ext4-jbd2-replay")
    image = directory / "replay-csum3-64bit.img"
    shutil.copyfile(canonical_images["primary-1k-i256"], image)
    payload = (
        b"JBD2-AKASHIC-REPLAY\n" + bytes(range(256)) * 4
    )[:1024].ljust(1024, b"\xa5")
    payload_path = directory / "home-block.bin"
    payload_path.write_bytes(payload)
    commands = directory / "journal.cmd"
    commands.write_text(
        "\n".join(
            (
                "journal_open -c -v 3",
                f"journal_write -b 30000 {payload_path}",
                "journal_close",
                "close",
            )
        )
        + "\n",
        encoding="utf-8",
    )
    authored = subprocess.run(
        [str(debugfs), "-w", "-f", str(commands), str(image)],
        env=env,
        text=True,
        capture_output=True,
        check=False,
    )
    assert authored.returncode == 0, authored.stdout + authored.stderr
    assert "Command not found" not in authored.stdout + authored.stderr

    mapped = subprocess.run(
        [str(debugfs), "-R", "bmap <8> 0", str(image)],
        env=env,
        text=True,
        capture_output=True,
        check=False,
    )
    assert mapped.returncode == 0, mapped.stdout + mapped.stderr
    journal_block = int(mapped.stdout.strip().splitlines()[-1])
    with image.open("rb") as source:
        source.seek(30000 * 1024)
        home_before = source.read(1024)
        source.seek(1024)
        superblock = source.read(1024)
        source.seek(journal_block * 1024)
        journal_superblock = source.read(1024)
    assert struct.unpack_from("<I", superblock, 0x60)[0] & 0x04
    assert struct.unpack_from(">I", journal_superblock, 0x00)[0] == 0xC03B3998
    assert struct.unpack_from(">I", journal_superblock, 0x28)[0] == 0x12
    assert struct.unpack_from(">I", journal_superblock, 0x1C)[0] == 1
    journal_sequence = struct.unpack_from(">I", journal_superblock, 0x18)[0]
    return {
        "image": image,
        "payload": payload,
        "home_before": home_before,
        "target_block": 30000,
        "journal_block": journal_block,
        "journal_sequence": journal_sequence,
    }


@pytest.fixture(scope="session")
def large_journal_replay_fixture(
    tmp_path_factory: pytest.TempPathFactory,
) -> dict[str, object]:
    """Author recovery on a real 8 MiB journal, beyond the old 4096-block pin."""
    tool_dir_value = os.environ.get("AKASHIC_E2FSPROGS_TOOL_DIR")
    if not tool_dir_value:
        pytest.skip("set AKASHIC_E2FSPROGS_TOOL_DIR for JBD2 recovery tests")
    tool_dir = Path(tool_dir_value).resolve()
    env = ext4_fixture_generator.pinned_environment(PROFILE, tool_dir, MANIFEST)
    try:
        tools = ext4_fixture_generator.verify_toolchain(PROFILE, tool_dir, env)
    except ext4_fixture_generator.ProfileError as error:
        pytest.fail(str(error))
    debugfs = Path(tools["debugfs"]["path"])
    config = MANIFEST.parent / "mke2fs.conf"
    assert _sha256(config) == PROFILE["generator"]["mke2fs_config_sha256"]
    directory = tmp_path_factory.mktemp("ext4-jbd2-replay-8m")
    image = directory / "replay-csum3-64bit-j8.img"
    with image.open("wb") as destination:
        destination.truncate(64 * (1 << 20))
    image_spec = {
        "id": "replay-csum3-64bit-j8",
        "profile": "primary",
        "filename": image.name,
        "image_bytes": 64 * (1 << 20),
        "block_size": 1024,
        "block_count": 65536,
        "blocks_per_group": 8192,
        "expected_groups": 8,
        "expected_inodes": 4096,
        "inode_size": 256,
        "uuid": "71111111-1111-4111-8111-111111111111",
        "hash_seed": "72111111-1111-4111-8111-111111111111",
        "label": "AKEXT4-J8",
    }
    context = dict(image_spec)
    context.update(
        {
            "tool_dir": tool_dir,
            "image": image,
            "feature_names": ",".join(
                ext4_fixture_generator.profile_feature_names(PROFILE, image_spec)
            ),
        }
    )
    mkfs_argv = ext4_fixture_generator.render_argv(
        PROFILE["generator"]["mkfs_argv"], context
    )
    assert mkfs_argv.count("size=4") == 1
    mkfs_argv[mkfs_argv.index("size=4")] = "size=8"
    made = subprocess.run(
        mkfs_argv,
        env=env,
        text=True,
        capture_output=True,
        check=False,
    )
    assert made.returncode == 0, made.stdout + made.stderr
    observed = ext4_fixture_generator.read_superblock(image)
    ext4_fixture_generator.validate_observed_superblock(
        PROFILE, image_spec, observed
    )

    payload = (
        b"JBD2-AKASHIC-REPLAY-J8\n" + bytes(range(256)) * 4
    )[:1024].ljust(1024, b"\x8a")
    payload_path = directory / "home-block-j8.bin"
    payload_path.write_bytes(payload)
    commands = directory / "journal-j8.cmd"
    commands.write_text(
        "\n".join(
            (
                "journal_open -c -v 3",
                f"journal_write -b 30000 {payload_path}",
                "journal_close",
                "close",
            )
        )
        + "\n",
        encoding="utf-8",
    )
    authored = subprocess.run(
        [str(debugfs), "-w", "-f", str(commands), str(image)],
        env=env,
        text=True,
        capture_output=True,
        check=False,
    )
    assert authored.returncode == 0, authored.stdout + authored.stderr
    assert "Command not found" not in authored.stdout + authored.stderr

    journal_stat = subprocess.run(
        [str(debugfs), "-R", "stat <8>", str(image)],
        env=env,
        text=True,
        capture_output=True,
        check=False,
    )
    assert journal_stat.returncode == 0, journal_stat.stdout + journal_stat.stderr
    assert re.search(r"\bSize:\s+8388608\b", journal_stat.stdout)

    mapped: dict[int, int] = {}
    for logical in (0, 8191):
        result = subprocess.run(
            [str(debugfs), "-R", f"bmap <8> {logical}", str(image)],
            env=env,
            text=True,
            capture_output=True,
            check=False,
        )
        assert result.returncode == 0, result.stdout + result.stderr
        mapped[logical] = int(result.stdout.strip().splitlines()[-1])
        assert mapped[logical] != 0
    with image.open("rb") as source:
        source.seek(30000 * 1024)
        home_before = source.read(1024)
        source.seek(mapped[0] * 1024)
        journal_superblock = source.read(1024)
    assert struct.unpack_from(">I", journal_superblock, 0x00)[0] == 0xC03B3998
    assert struct.unpack_from(">I", journal_superblock, 0x10)[0] == 8192
    assert struct.unpack_from(">I", journal_superblock, 0x28)[0] == 0x12
    assert home_before != payload
    return {
        "image": image,
        "payload": payload,
        "home_before": home_before,
        "target_block": 30000,
        "journal_block": mapped[0],
        "journal_tail_block": mapped[8191],
    }


def test_jbd2_checksum_v3_replay_is_durable_and_idempotent(
    replay_fixture: dict[str, object], tmp_path: Path
) -> None:
    image = replay_fixture["image"]
    assert isinstance(image, Path)
    target_block = replay_fixture["target_block"]
    journal_block = replay_fixture["journal_block"]
    journal_sequence = replay_fixture["journal_sequence"]
    payload = replay_fixture["payload"]
    assert isinstance(target_block, int)
    assert isinstance(journal_block, int)
    assert isinstance(journal_sequence, int)
    assert isinstance(payload, bytes)
    backing = tmp_path / "recovered.img"
    output, trace, media_sha256 = run_recovery_forth(
        image,
        backing,
        [
            "T-ARENA T-VOLUME EXT4-NEW CONSTANT _M-IOR CONSTANT _V",
            (
                "_M-IOR 0= _V V.LIFECYCLE @ VFS-L-MOUNTED = AND "
                "_V _EXT4-CTX _EXT4-C.J.REPLAYED + @ 0<> AND "
                "_V _EXT4-CTX _EXT4-C.J.HOME-WRITES + @ 1 = AND "
                'IF ." EXT4-JBD2-REPLAY-OK" THEN'
            ),
        ],
    )
    _assert_emitted(output, "EXT4-JBD2-REPLAY-OK")
    assert trace == (
        ("write", target_block * 2, 2),
        ("flush", 0, 0),
        ("write", (journal_block + 4) * 2, 2),
        ("flush", 0, 0),
        ("write", (journal_block + 4) * 2, 2),
        ("flush", 0, 0),
        ("write", journal_block * 2, 2),
        ("flush", 0, 0),
        ("write", 2, 2),
        ("flush", 0, 0),
        ("write", journal_block * 2, 2),
        ("flush", 0, 0),
        ("write", (journal_block + 4) * 2, 2),
        ("flush", 0, 0),
    )
    assert backing.is_file()
    assert _sha256(backing) == media_sha256
    with backing.open("rb") as source:
        source.seek(target_block * 1024)
        assert source.read(1024) == payload
        source.seek(1024)
        superblock = source.read(1024)
        source.seek(journal_block * 1024)
        journal_superblock = source.read(1024)
        source.seek((journal_block + 4) * 1024)
        retired_anchor = source.read(1024)
    assert struct.unpack_from("<I", superblock, 0x60)[0] & 0x04 == 0
    assert struct.unpack_from(">I", journal_superblock, 0x18)[0] == (
        journal_sequence + 2
    ) & 0xFFFF_FFFF
    assert struct.unpack_from(">I", journal_superblock, 0x1C)[0] == 0
    assert struct.unpack_from(">I", journal_superblock, 0x58)[0] == 4
    assert journal_superblock[0x5C:0x70] == bytes(20)
    assert retired_anchor == bytes(1024)

    second = run_forth(
        backing,
        [
            "T-ARENA T-VOLUME EXT4-NEW CONSTANT _M-IOR CONSTANT _V",
            (
                "_M-IOR 0= _V V.LIFECYCLE @ VFS-L-MOUNTED = AND "
                'IF ." EXT4-JBD2-SECOND-MOUNT-OK" THEN'
            ),
        ],
    )
    _assert_emitted(second, "EXT4-JBD2-SECOND-MOUNT-OK")


def test_jbd2_replay_accepts_arena_bounded_8m_journal(
    large_journal_replay_fixture: dict[str, object], tmp_path: Path
) -> None:
    image = large_journal_replay_fixture["image"]
    payload = large_journal_replay_fixture["payload"]
    target_block = large_journal_replay_fixture["target_block"]
    journal_tail_block = large_journal_replay_fixture["journal_tail_block"]
    assert isinstance(image, Path)
    assert isinstance(payload, bytes)
    assert isinstance(target_block, int)
    assert isinstance(journal_tail_block, int)

    backing = tmp_path / "recovered-j8.img"
    output, trace, media_sha256 = run_recovery_forth(
        image,
        backing,
        [
            "T-ARENA T-VOLUME EXT4-NEW CONSTANT _M-IOR CONSTANT _V",
            (
                "_M-IOR 0= _V V.LIFECYCLE @ VFS-L-MOUNTED = AND "
                "_V _EXT4-CTX _EXT4-C.J.REPLAYED + @ 0<> AND "
                "_V _EXT4-CTX _EXT4-C.J.HOME-WRITES + @ 1 = AND "
                "_V _EXT4-CTX _EXT4-C.J.MAXLEN + @ 8192 = AND "
                "_V _EXT4-CTX _EXT4-C.J.MAP-CAPACITY + @ 8192 = AND "
                "_V _EXT4-CTX _EXT4-C.J.MAP-HASH-SLOTS + @ 16384 = AND "
                "8191 _V _EXT4-CTX _EXT4-JOURNAL-MAP@ 0<> AND "
                'IF ." EXT4-JBD2-J8-REPLAY-OK" THEN'
            ),
        ],
    )
    _assert_emitted(output, "EXT4-JBD2-J8-REPLAY-OK")
    assert ("write", target_block * 2, 2) in trace
    assert any(operation == "flush" for operation, _, _ in trace)
    assert backing.is_file()
    assert _sha256(backing) == media_sha256
    with backing.open("rb") as source:
        source.seek(target_block * 1024)
        assert source.read(1024) == payload

    second = run_forth(
        backing,
        [
            "T-ARENA T-VOLUME EXT4-NEW CONSTANT _M-IOR CONSTANT _V",
            (
                "_M-IOR 0= _V V.LIFECYCLE @ VFS-L-MOUNTED = AND "
                "_V _EXT4-CTX _EXT4-C.J.MAXLEN + @ 8192 = AND "
                "_V _EXT4-CTX _EXT4-C.J.MAP-CAPACITY + @ 8192 = AND "
                "8191 _V _EXT4-CTX _EXT4-JOURNAL-MAP@ "
                f"{journal_tail_block} = AND "
                'IF ." EXT4-JBD2-J8-SECOND-MOUNT-OK" THEN'
            ),
        ],
    )
    _assert_emitted(second, "EXT4-JBD2-J8-SECOND-MOUNT-OK")


def test_jbd2_recovery_repairs_torn_ext4_superblock_clear(
    replay_fixture: dict[str, object], tmp_path: Path
) -> None:
    image = replay_fixture["image"]
    target_block = replay_fixture["target_block"]
    journal_block = replay_fixture["journal_block"]
    payload = replay_fixture["payload"]
    assert isinstance(image, Path)
    assert isinstance(target_block, int)
    assert isinstance(journal_block, int)
    assert isinstance(payload, bytes)

    torn = tmp_path / "torn-superblock-clear.img"
    output, trace, _media_sha256 = run_recovery_forth(
        image,
        tmp_path / "pre-tear-superblock.img",
        [
            "T-ARENA T-VOLUME EXT4-NEW CONSTANT _M-IOR CONSTANT _V",
            (
                "_M-IOR VFS-IOR-DOMAIN VFS-IOR-D-VOLUME = "
                "_M-IOR VFS-IOR-REASON VFS-R-IO = AND "
                "_M-IOR VFS-IOR-FLAGS VFS-IOR-F-PARTIAL AND 0<> AND "
                "_V V.LIFECYCLE @ VFS-L-NEW = AND "
                'IF ." EXT4-JBD2-SUPER-TEAR-CAUGHT" THEN'
            ),
        ],
        write_faults_by_ordinal={
            5: {
                "stage": "media",
                "sector_index": 1,
                "byte_index": 0,
                "result": STORAGE_RESULT_MEDIA_FAILURE,
                "command": STORAGE_CMD_WRITE,
            }
        },
        capture_media=torn,
    )
    _assert_emitted(output, "EXT4-JBD2-SUPER-TEAR-CAUGHT")
    assert trace == (
        ("write", target_block * 2, 2),
        ("flush", 0, 0),
        ("write", (journal_block + 4) * 2, 2),
        ("flush", 0, 0),
        ("write", (journal_block + 4) * 2, 2),
        ("flush", 0, 0),
        ("write", journal_block * 2, 2),
        ("flush", 0, 0),
        ("write", 2, 2),
    )
    assert torn.is_file()

    repaired = tmp_path / "repaired-superblock-clear.img"
    output, retry_trace, repaired_sha256 = run_recovery_forth(
        torn,
        repaired,
        [
            "T-ARENA T-VOLUME EXT4-NEW CONSTANT _M-IOR CONSTANT _V",
            (
                "_M-IOR 0= _V V.LIFECYCLE @ VFS-L-MOUNTED = AND "
                "_V _EXT4-CTX _EXT4-C.J.HOME-WRITES + @ 0= AND "
                'IF ." EXT4-JBD2-SUPER-TEAR-REPAIRED" THEN'
            ),
        ],
    )
    _assert_emitted(output, "EXT4-JBD2-SUPER-TEAR-REPAIRED")
    assert retry_trace == (
        ("write", 2, 2),
        ("flush", 0, 0),
        ("write", journal_block * 2, 2),
        ("flush", 0, 0),
        ("write", (journal_block + 4) * 2, 2),
        ("flush", 0, 0),
    )
    assert _sha256(repaired) == repaired_sha256
    with repaired.open("rb") as source:
        source.seek(target_block * 1024)
        assert source.read(1024) == payload
        source.seek(1024 + 0x60)
        assert struct.unpack("<I", source.read(4))[0] & 0x04 == 0


def test_jbd2_retry_skips_rewriting_an_already_durable_reset(
    replay_fixture: dict[str, object], tmp_path: Path
) -> None:
    image = replay_fixture["image"]
    target_block = replay_fixture["target_block"]
    journal_block = replay_fixture["journal_block"]
    assert isinstance(image, Path)
    assert isinstance(target_block, int)
    assert isinstance(journal_block, int)

    interrupted = tmp_path / "before-superblock-clear.img"
    output, trace, _media_sha256 = run_recovery_forth(
        image,
        tmp_path / "pre-superblock-clear.img",
        [
            "T-ARENA T-VOLUME EXT4-NEW CONSTANT _M-IOR CONSTANT _V",
            (
                "_M-IOR VFS-IOR-DOMAIN VFS-IOR-D-VOLUME = "
                "_M-IOR VFS-IOR-REASON VFS-R-IO = AND "
                "_M-IOR VFS-IOR-FLAGS VFS-IOR-F-PARTIAL AND 0<> AND "
                "_V V.LIFECYCLE @ VFS-L-NEW = AND "
                'IF ." EXT4-JBD2-BEFORE-SUPER-CLEAR" THEN'
            ),
        ],
        write_faults_by_ordinal={
            5: {
                "stage": "media",
                "sector_index": 0,
                "byte_index": 1,
                "result": STORAGE_RESULT_MEDIA_FAILURE,
                "command": STORAGE_CMD_WRITE,
            }
        },
        capture_media=interrupted,
    )
    _assert_emitted(output, "EXT4-JBD2-BEFORE-SUPER-CLEAR")
    assert trace == (
        ("write", target_block * 2, 2),
        ("flush", 0, 0),
        ("write", (journal_block + 4) * 2, 2),
        ("flush", 0, 0),
        ("write", (journal_block + 4) * 2, 2),
        ("flush", 0, 0),
        ("write", journal_block * 2, 2),
        ("flush", 0, 0),
        ("write", 2, 2),
    )

    repaired = tmp_path / "already-reset-repaired.img"
    output, retry_trace, repaired_sha256 = run_recovery_forth(
        interrupted,
        repaired,
        [
            "T-ARENA T-VOLUME EXT4-NEW CONSTANT _M-IOR CONSTANT _V",
            (
                "_M-IOR 0= _V V.LIFECYCLE @ VFS-L-MOUNTED = AND "
                "_V _EXT4-CTX _EXT4-C.J.HOME-WRITES + @ 0= AND "
                'IF ." EXT4-JBD2-ALREADY-RESET-REPAIRED" THEN'
            ),
        ],
    )
    _assert_emitted(output, "EXT4-JBD2-ALREADY-RESET-REPAIRED")
    assert retry_trace == (
        ("flush", 0, 0),
        ("write", 2, 2),
        ("flush", 0, 0),
        ("write", journal_block * 2, 2),
        ("flush", 0, 0),
        ("write", (journal_block + 4) * 2, 2),
        ("flush", 0, 0),
    )
    assert _sha256(repaired) == repaired_sha256


def test_jbd2_recovery_uses_anchor_after_torn_primary_journal_reset(
    replay_fixture: dict[str, object], tmp_path: Path
) -> None:
    image = replay_fixture["image"]
    target_block = replay_fixture["target_block"]
    journal_block = replay_fixture["journal_block"]
    payload = replay_fixture["payload"]
    assert isinstance(image, Path)
    assert isinstance(target_block, int)
    assert isinstance(journal_block, int)
    assert isinstance(payload, bytes)

    torn = tmp_path / "torn-primary-journal-reset.img"
    output, trace, _media_sha256 = run_recovery_forth(
        image,
        tmp_path / "pre-tear-journal.img",
        [
            "T-ARENA T-VOLUME EXT4-NEW CONSTANT _M-IOR CONSTANT _V",
            (
                "_M-IOR VFS-IOR-DOMAIN VFS-IOR-D-VOLUME = "
                "_M-IOR VFS-IOR-REASON VFS-R-IO = AND "
                "_M-IOR VFS-IOR-FLAGS VFS-IOR-F-PARTIAL AND 0<> AND "
                "_V V.LIFECYCLE @ VFS-L-NEW = AND "
                'IF ." EXT4-JBD2-PRIMARY-TEAR-CAUGHT" THEN'
            ),
        ],
        write_faults_by_ordinal={
            4: {
                "stage": "media",
                "sector_index": 0,
                "byte_index": 200,
                "result": STORAGE_RESULT_MEDIA_FAILURE,
                "command": STORAGE_CMD_WRITE,
            }
        },
        capture_media=torn,
    )
    _assert_emitted(output, "EXT4-JBD2-PRIMARY-TEAR-CAUGHT")
    assert trace == (
        ("write", target_block * 2, 2),
        ("flush", 0, 0),
        ("write", (journal_block + 4) * 2, 2),
        ("flush", 0, 0),
        ("write", (journal_block + 4) * 2, 2),
        ("flush", 0, 0),
        ("write", journal_block * 2, 2),
    )
    assert torn.is_file()

    repaired = tmp_path / "repaired-primary-journal.img"
    output, retry_trace, repaired_sha256 = run_recovery_forth(
        torn,
        repaired,
        [
            "T-ARENA T-VOLUME EXT4-NEW CONSTANT _M-IOR CONSTANT _V",
            (
                "_M-IOR 0= _V V.LIFECYCLE @ VFS-L-MOUNTED = AND "
                "_V _EXT4-CTX _EXT4-C.J.REPLAYED + @ 0<> AND "
                "_V _EXT4-CTX _EXT4-C.J.HOME-WRITES + @ 0= AND "
                'IF ." EXT4-JBD2-PRIMARY-TEAR-REPAIRED" THEN'
            ),
        ],
    )
    _assert_emitted(output, "EXT4-JBD2-PRIMARY-TEAR-REPAIRED")
    assert retry_trace == (
        ("flush", 0, 0),
        ("write", journal_block * 2, 2),
        ("flush", 0, 0),
        ("write", 2, 2),
        ("flush", 0, 0),
        ("write", journal_block * 2, 2),
        ("flush", 0, 0),
        ("write", (journal_block + 4) * 2, 2),
        ("flush", 0, 0),
    )
    assert _sha256(repaired) == repaired_sha256
    with repaired.open("rb") as source:
        source.seek(target_block * 1024)
        assert source.read(1024) == payload
        source.seek(1024 + 0x60)
        assert struct.unpack("<I", source.read(4))[0] & 0x04 == 0
        source.seek(journal_block * 1024 + 0x1C)
        assert struct.unpack(">I", source.read(4))[0] == 0


def test_jbd2_corrupt_descriptor_refuses_before_mutation(
    replay_fixture: dict[str, object], tmp_path: Path
) -> None:
    image = replay_fixture["image"]
    journal_block = replay_fixture["journal_block"]
    assert isinstance(image, Path)
    assert isinstance(journal_block, int)
    offset = (journal_block + 1) * 1024 + 1023
    with image.open("rb") as source:
        source.seek(offset)
        replacement = bytes((source.read(1)[0] ^ 1,))
    patched = bytearray(image.read_bytes())
    patched[offset : offset + 1] = replacement
    output, trace, media_sha256 = run_recovery_forth(
        image,
        tmp_path / "must-not-flush.img",
        [
            "T-ARENA T-VOLUME EXT4-NEW CONSTANT _M-IOR CONSTANT _V",
            (
                "_M-IOR VFS-IOR-REASON VFS-R-CORRUPT = "
                "_M-IOR VFS-IOR-DETAIL EXT4-D-JOURNAL = AND "
                "_V V.LIFECYCLE @ VFS-L-NEW = AND "
                "_V _EXT4-CTX _EXT4-C.READY + @ 0= AND "
                'IF ." EXT4-JBD2-CORRUPT-NO-WRITE" THEN'
            ),
        ],
        patches=((offset, replacement),),
    )
    _assert_emitted(output, "EXT4-JBD2-CORRUPT-NO-WRITE")
    assert trace == ()
    assert media_sha256 == hashlib.sha256(patched).hexdigest()


@pytest.mark.parametrize(
    ("phase", "write_ordinal", "byte_index"),
    (("preseed", 2, 8), ("publish", 3, 1)),
)
def test_jbd2_prefix_torn_anchor_install_is_retryable(
    replay_fixture: dict[str, object],
    tmp_path: Path,
    phase: str,
    write_ordinal: int,
    byte_index: int,
) -> None:
    image = replay_fixture["image"]
    target_block = replay_fixture["target_block"]
    journal_block = replay_fixture["journal_block"]
    assert isinstance(image, Path)
    assert isinstance(target_block, int)
    assert isinstance(journal_block, int)

    interrupted = tmp_path / f"prefix-torn-anchor-{phase}.img"
    output, trace, _media_sha256 = run_recovery_forth(
        image,
        tmp_path / f"pre-anchor-{phase}-tear.img",
        [
            "T-ARENA T-VOLUME EXT4-NEW CONSTANT _M-IOR CONSTANT _V",
            (
                "_M-IOR VFS-IOR-DOMAIN VFS-IOR-D-VOLUME = "
                "_M-IOR VFS-IOR-REASON VFS-R-IO = AND "
                "_M-IOR VFS-IOR-FLAGS VFS-IOR-F-PARTIAL AND 0<> AND "
                "_V V.LIFECYCLE @ VFS-L-NEW = AND "
                'IF ." EXT4-JBD2-ANCHOR-INSTALL-TEAR" THEN'
            ),
        ],
        write_faults_by_ordinal={
            write_ordinal: {
                "stage": "media",
                "sector_index": 0,
                "byte_index": byte_index,
                "result": STORAGE_RESULT_MEDIA_FAILURE,
                "command": STORAGE_CMD_WRITE,
            }
        },
        capture_media=interrupted,
    )
    _assert_emitted(output, "EXT4-JBD2-ANCHOR-INSTALL-TEAR")
    expected_trace = (
        ("write", target_block * 2, 2),
        ("flush", 0, 0),
        ("write", (journal_block + 4) * 2, 2),
    )
    if phase == "publish":
        expected_trace += (
            ("flush", 0, 0),
            ("write", (journal_block + 4) * 2, 2),
        )
    assert trace == expected_trace

    repaired = tmp_path / f"anchor-{phase}-repaired.img"
    output, retry_trace, repaired_sha256 = run_recovery_forth(
        interrupted,
        repaired,
        [
            "T-ARENA T-VOLUME EXT4-NEW CONSTANT _M-IOR CONSTANT _V",
            (
                "_M-IOR 0= _V V.LIFECYCLE @ VFS-L-MOUNTED = AND "
                'IF ." EXT4-JBD2-ANCHOR-INSTALL-REPAIRED" THEN'
            ),
        ],
    )
    _assert_emitted(output, "EXT4-JBD2-ANCHOR-INSTALL-REPAIRED")
    assert retry_trace == (
        ("write", target_block * 2, 2),
        ("flush", 0, 0),
        ("write", (journal_block + 4) * 2, 2),
        ("flush", 0, 0),
        ("write", (journal_block + 4) * 2, 2),
        ("flush", 0, 0),
        ("write", journal_block * 2, 2),
        ("flush", 0, 0),
        ("write", 2, 2),
        ("flush", 0, 0),
        ("write", journal_block * 2, 2),
        ("flush", 0, 0),
        ("write", (journal_block + 4) * 2, 2),
        ("flush", 0, 0),
    )
    assert _sha256(repaired) == repaired_sha256


def test_jbd2_primary_reset_tear_before_locator_fails_closed(
    replay_fixture: dict[str, object], tmp_path: Path
) -> None:
    image = replay_fixture["image"]
    target_block = replay_fixture["target_block"]
    journal_block = replay_fixture["journal_block"]
    assert isinstance(image, Path)
    assert isinstance(target_block, int)
    assert isinstance(journal_block, int)

    torn = tmp_path / "primary-tear-before-locator.img"
    output, trace, _media_sha256 = run_recovery_forth(
        image,
        tmp_path / "pre-early-primary-tear.img",
        [
            "T-ARENA T-VOLUME EXT4-NEW CONSTANT _M-IOR CONSTANT _V",
            (
                "_M-IOR VFS-IOR-DOMAIN VFS-IOR-D-VOLUME = "
                "_M-IOR VFS-IOR-REASON VFS-R-IO = AND "
                "_M-IOR VFS-IOR-FLAGS VFS-IOR-F-PARTIAL AND 0<> AND "
                "_V V.LIFECYCLE @ VFS-L-NEW = AND "
                'IF ." EXT4-JBD2-EARLY-PRIMARY-TEAR" THEN'
            ),
        ],
        write_faults_by_ordinal={
            4: {
                "stage": "media",
                "sector_index": 0,
                "byte_index": 50,
                "result": STORAGE_RESULT_MEDIA_FAILURE,
                "command": STORAGE_CMD_WRITE,
            }
        },
        capture_media=torn,
    )
    _assert_emitted(output, "EXT4-JBD2-EARLY-PRIMARY-TEAR")
    assert trace == (
        ("write", target_block * 2, 2),
        ("flush", 0, 0),
        ("write", (journal_block + 4) * 2, 2),
        ("flush", 0, 0),
        ("write", (journal_block + 4) * 2, 2),
        ("flush", 0, 0),
        ("write", journal_block * 2, 2),
    )

    output, retry_trace, media_sha256 = run_recovery_forth(
        torn,
        tmp_path / "early-tear-refused.img",
        [
            "T-ARENA T-VOLUME EXT4-NEW CONSTANT _M-IOR CONSTANT _V",
            (
                "_M-IOR VFS-IOR-REASON VFS-R-CORRUPT = "
                "_M-IOR VFS-IOR-DETAIL EXT4-D-JOURNAL = AND "
                "_V V.LIFECYCLE @ VFS-L-NEW = AND "
                'IF ." EXT4-JBD2-EARLY-TEAR-FAIL-CLOSED" THEN'
            ),
        ],
    )
    _assert_emitted(output, "EXT4-JBD2-EARLY-TEAR-FAIL-CLOSED")
    assert retry_trace == ()
    assert media_sha256 == _sha256(torn)


def test_jbd2_incomplete_tail_is_discarded_without_home_write(
    replay_fixture: dict[str, object], tmp_path: Path
) -> None:
    image = replay_fixture["image"]
    target_block = replay_fixture["target_block"]
    journal_block = replay_fixture["journal_block"]
    home_before = replay_fixture["home_before"]
    assert isinstance(image, Path)
    assert isinstance(target_block, int)
    assert isinstance(journal_block, int)
    assert isinstance(home_before, bytes)

    commit_magic = (journal_block + 3) * 1024
    recovered = tmp_path / "discarded-incomplete-tail.img"
    output, trace, media_sha256 = run_recovery_forth(
        image,
        recovered,
        [
            "T-ARENA T-VOLUME EXT4-NEW CONSTANT _M-IOR CONSTANT _V",
            (
                "_M-IOR 0= _V V.LIFECYCLE @ VFS-L-MOUNTED = AND "
                "_V _EXT4-CTX _EXT4-C.J.REPLAYED + @ 0<> AND "
                "_V _EXT4-CTX _EXT4-C.J.HOME-WRITES + @ 0= AND "
                'IF ." EXT4-JBD2-INCOMPLETE-DISCARDED" THEN'
            ),
        ],
        patches=((commit_magic, b"\x00\x00\x00\x00"),),
    )
    _assert_emitted(output, "EXT4-JBD2-INCOMPLETE-DISCARDED")
    assert trace == (
        ("flush", 0, 0),
        ("write", (journal_block + 1) * 2, 2),
        ("flush", 0, 0),
        ("write", (journal_block + 1) * 2, 2),
        ("flush", 0, 0),
        ("write", journal_block * 2, 2),
        ("flush", 0, 0),
        ("write", 2, 2),
        ("flush", 0, 0),
        ("write", journal_block * 2, 2),
        ("flush", 0, 0),
        ("write", (journal_block + 1) * 2, 2),
        ("flush", 0, 0),
    )
    assert _sha256(recovered) == media_sha256
    with recovered.open("rb") as source:
        source.seek(target_block * 1024)
        assert source.read(1024) == home_before


def test_jbd2_torn_witness_removal_repairs_exact_prefix(
    replay_fixture: dict[str, object], tmp_path: Path
) -> None:
    image = replay_fixture["image"]
    target_block = replay_fixture["target_block"]
    journal_block = replay_fixture["journal_block"]
    assert isinstance(image, Path)
    assert isinstance(target_block, int)
    assert isinstance(journal_block, int)

    torn = tmp_path / "torn-witness-removal.img"
    output, trace, _media_sha256 = run_recovery_forth(
        image,
        tmp_path / "pre-witness-removal-tear.img",
        [
            "T-ARENA T-VOLUME EXT4-NEW CONSTANT _M-IOR CONSTANT _V",
            (
                "_M-IOR VFS-IOR-DOMAIN VFS-IOR-D-VOLUME = "
                "_M-IOR VFS-IOR-REASON VFS-R-IO = AND "
                "_M-IOR VFS-IOR-FLAGS VFS-IOR-F-PARTIAL AND 0<> AND "
                "_V V.LIFECYCLE @ VFS-L-NEW = AND "
                'IF ." EXT4-JBD2-WITNESS-REMOVE-TEAR" THEN'
            ),
        ],
        write_faults_by_ordinal={
            6: {
                "stage": "media",
                "sector_index": 0,
                "byte_index": 200,
                "result": STORAGE_RESULT_MEDIA_FAILURE,
                "command": STORAGE_CMD_WRITE,
            }
        },
        capture_media=torn,
    )
    _assert_emitted(output, "EXT4-JBD2-WITNESS-REMOVE-TEAR")
    assert trace == (
        ("write", target_block * 2, 2),
        ("flush", 0, 0),
        ("write", (journal_block + 4) * 2, 2),
        ("flush", 0, 0),
        ("write", (journal_block + 4) * 2, 2),
        ("flush", 0, 0),
        ("write", journal_block * 2, 2),
        ("flush", 0, 0),
        ("write", 2, 2),
        ("flush", 0, 0),
        ("write", journal_block * 2, 2),
    )

    unrelated_offset = journal_block * 1024 + 0x80
    with torn.open("rb") as source:
        source.seek(unrelated_offset)
        unrelated_replacement = bytes((source.read(1)[0] ^ 1,))
    nonprefix = bytearray(torn.read_bytes())
    nonprefix[unrelated_offset : unrelated_offset + 1] = unrelated_replacement
    output, refused_trace, refused_sha256 = run_recovery_forth(
        torn,
        tmp_path / "witness-removal-nonprefix-refused.img",
        [
            "T-ARENA T-VOLUME EXT4-NEW CONSTANT _M-IOR CONSTANT _V",
            (
                "_M-IOR VFS-IOR-REASON VFS-R-CORRUPT = "
                "_M-IOR VFS-IOR-DETAIL EXT4-D-JOURNAL = AND "
                "_V V.LIFECYCLE @ VFS-L-NEW = AND "
                'IF ." EXT4-JBD2-WITNESS-NONPREFIX-REFUSED" THEN'
            ),
        ],
        patches=((unrelated_offset, unrelated_replacement),),
    )
    _assert_emitted(output, "EXT4-JBD2-WITNESS-NONPREFIX-REFUSED")
    assert refused_trace == ()
    assert refused_sha256 == hashlib.sha256(nonprefix).hexdigest()

    retried_torn = tmp_path / "witness-removal-retry-torn.img"
    output, retry_trace, _media_sha256 = run_recovery_forth(
        torn,
        tmp_path / "pre-witness-removal-retry-tear.img",
        [
            "T-ARENA T-VOLUME EXT4-NEW CONSTANT _M-IOR CONSTANT _V",
            (
                "_M-IOR VFS-IOR-DOMAIN VFS-IOR-D-VOLUME = "
                "_M-IOR VFS-IOR-REASON VFS-R-IO = AND "
                "_M-IOR VFS-IOR-FLAGS VFS-IOR-F-PARTIAL AND 0<> AND "
                "_V V.LIFECYCLE @ VFS-L-NEW = AND "
                'IF ." EXT4-JBD2-WITNESS-REMOVE-RETRY-TEAR" THEN'
            ),
        ],
        write_faults_by_ordinal={
            1: {
                "stage": "media",
                "sector_index": 0,
                "byte_index": 220,
                "result": STORAGE_RESULT_MEDIA_FAILURE,
                "command": STORAGE_CMD_WRITE,
            }
        },
        capture_media=retried_torn,
    )
    _assert_emitted(output, "EXT4-JBD2-WITNESS-REMOVE-RETRY-TEAR")
    assert retry_trace == (("write", journal_block * 2, 2),)

    repaired = tmp_path / "witness-removal-repaired.img"
    output, final_trace, media_sha256 = run_recovery_forth(
        retried_torn,
        repaired,
        [
            "T-ARENA T-VOLUME EXT4-NEW CONSTANT _M-IOR CONSTANT _V",
            (
                "_M-IOR 0= _V V.LIFECYCLE @ VFS-L-MOUNTED = AND "
                "_V _EXT4-CTX _EXT4-C.J.HOME-WRITES + @ 0= AND "
                'IF ." EXT4-JBD2-WITNESS-REMOVE-REPAIRED" THEN'
            ),
        ],
    )
    _assert_emitted(output, "EXT4-JBD2-WITNESS-REMOVE-REPAIRED")
    assert final_trace == (
        ("write", journal_block * 2, 2),
        ("flush", 0, 0),
        ("write", (journal_block + 4) * 2, 2),
        ("flush", 0, 0),
    )
    assert _sha256(repaired) == media_sha256
    with repaired.open("rb") as source:
        source.seek(1024 + 0x60)
        assert struct.unpack("<I", source.read(4))[0] & 0x04 == 0
        source.seek(journal_block * 1024)
        journal_superblock = source.read(1024)
        source.seek((journal_block + 4) * 1024)
        retired_anchor = source.read(1024)
    assert journal_superblock[0x5C:0x70] == bytes(20)
    assert retired_anchor == bytes(1024)


def test_jbd2_recovery_refuses_physical_read_only_media(
    replay_fixture: dict[str, object], tmp_path: Path
) -> None:
    image = replay_fixture["image"]
    assert isinstance(image, Path)
    output, trace, media_sha256 = run_recovery_forth(
        image,
        tmp_path / "read-only-must-not-flush.img",
        [
            "T-ARENA T-VOLUME EXT4-NEW CONSTANT _M-IOR CONSTANT _V",
            (
                "_M-IOR VFS-IOR-DOMAIN VFS-IOR-D-VOLUME = "
                "_M-IOR VFS-IOR-REASON VFS-R-READONLY = AND "
                "_M-IOR VFS-IOR-FLAGS VFS-IOR-F-READONLY AND 0<> AND "
                "_V V.LIFECYCLE @ VFS-L-NEW = AND "
                'IF ." EXT4-JBD2-PHYSICAL-RO" THEN'
            ),
        ],
        write_protected=True,
    )
    _assert_emitted(output, "EXT4-JBD2-PHYSICAL-RO")
    assert trace == ()
    assert media_sha256 == _sha256(image)


def test_binding_descriptor_is_valid_and_truthfully_read_only(
    tmp_path: Path,
) -> None:
    blank = tmp_path / "descriptor-storage.img"
    blank.write_bytes(bytes(4 * 512))
    output = run_forth(
        blank,
        [
            (
                "VFS-CAP-PROBE VFS-CAP-MOUNT OR VFS-CAP-UNMOUNT OR "
                "VFS-CAP-READDIR OR VFS-CAP-OPEN OR VFS-CAP-RELEASE OR "
                "VFS-CAP-READ OR VFS-CAP-GETATTR OR VFS-CAP-READLINK OR "
                "VFS-CAP-SYNCFS OR VFS-CAP-FSYNC OR VFS-CAP-STATFS OR "
                "VFS-CAP-LISTXATTR OR VFS-CAP-GETXATTR OR "
                "VFS-CAP-SPARSE OR VFS-CAP-STABLE-HANDLES OR "
                "CONSTANT _EXPECTED-E4-CAPS"
            ),
            (
                "VFS-BF-NEEDS-VOLUME VFS-BF-READ-ONLY OR "
                "VFS-BF-STABLE-IDS OR CONSTANT _EXPECTED-E4-FLAGS"
            ),
            (
                "EXT4-BINDING VFS-BINDING-VALID? "
                "EXT4-CAPS _EXPECTED-E4-CAPS = AND "
                "EXT4-BINDING VB.FLAGS @ _EXPECTED-E4-FLAGS = AND "
                'IF ." EXT4-DESCRIPTOR-OK" THEN'
            ),
        ],
    )
    _assert_emitted(output, "EXT4-DESCRIPTOR-OK")


def test_zero_count_loops_and_invalid_dirent_type_are_total(tmp_path: Path) -> None:
    blank = tmp_path / "parser-storage.img"
    blank.write_bytes(bytes(4 * 512))
    output = run_forth(
        blank,
        [
            "CREATE _E4CTX _EXT4-CTX-SIZE ALLOT",
            "_E4CTX _EXT4-CTX-SIZE 0 FILL",
            (
                "_EXT4-EXTENT-MAGIC _E4CTX _EXT4-C.INODE + "
                "_EXT4-I.BLOCK + W!"
            ),
            "4 _E4CTX _EXT4-C.INODE + _EXT4-I.BLOCK + 4 + W!",
            "1 _E4CTX _EXT4-C.GROUPS + !",
            (
                "_E4CTX _EXT4-VALIDATE-INLINE-EXTENTS 0= "
                "0 _E4CTX _EXT4-MAP-INLINE "
                "0= SWAP 0= AND SWAP 0= AND AND "
                "_E4CTX _EXT4-VALIDATE-BACKUPS 0= AND "
                "9 _EXT4-DIRENT>TYPE 0= SWAP 0= AND AND "
                'IF ." EXT4-PARSER-TOTAL-OK" THEN'
            ),
            "8 _E4CTX _EXT4-C.SPB + ! 100 _E4CTX _EXT4-C.BLOCKS + !",
            (
                "5 _E4CTX _EXT4-C.INODE + _EXT4-I.BLOCKS-LO + L! "
                "_EXT4-HUGE-FILE-FL _E4CTX _EXT4-C.INODE + "
                "_EXT4-I.FLAGS + L!"
            ),
            (
                "_E4CTX _EXT4-C.INODE + _E4CTX "
                "_EXT4-DECODE-I-BLOCKS CONSTANT _IB-IOR CONSTANT _IBLOCKS"
            ),
            (
                "_IB-IOR 0= _IBLOCKS 40 = AND "
                'IF ." EXT4-HUGE-BLOCKS-OK" THEN'
            ),
            "256 _E4CTX _EXT4-C.ISIZE + !",
            "0x81A4 _E4CTX _EXT4-C.INODE + _EXT4-I.MODE + W!",
            "1 _E4CTX _EXT4-C.INODE + _EXT4-I.LINKS + W!",
            "16 _E4CTX _EXT4-C.INODE + _EXT4-I.EXTRA-SIZE + W!",
            "0xFFFFFFFF _E4CTX _EXT4-C.INODE + _EXT4-I.ATIME + L!",
            (
                "_EXT4-EXTENTS-FL _E4CTX _EXT4-C.INODE + "
                "_EXT4-I.FLAGS + L!"
            ),
            (
                "_E4CTX _EXT4-STAGE-CURRENT-INODE "
                "CONSTANT _TS-IOR CONSTANT _TS-TYPE"
            ),
            (
                "_TS-IOR 0= _TS-TYPE VFS-T-FILE = AND "
                "_E4CTX _EXT4-C.R.ATIME + @ -1 = AND "
                'IF ." EXT4-TIMESTAMP-SIGN-OK" THEN'
            ),
            (
                ": _E4-SET-LEGACY-JOURNAL-MAP 12 0 DO "
                "100 I + _E4CTX _EXT4-C.INODE + _EXT4-I.BLOCK + "
                "I 4 * + L! LOOP ;"
            ),
            "_E4-SET-LEGACY-JOURNAL-MAP",
            "0 _E4CTX _EXT4-C.INODE + _EXT4-I.FLAGS + L!",
            "1000 _E4CTX _EXT4-C.BLOCKS + !",
            "12 _E4CTX _EXT4-C.J.MAXLEN + !",
            (
                "12 CELLS 32 CELLS + 2 CELLS + A-XMEM ARENA-NEW "
                "THROW CONSTANT _E4-JOURNAL-ARENA"
            ),
            (
                "_E4-JOURNAL-ARENA _E4CTX _EXT4-C.ARENA + ! "
                "12 _E4CTX _EXT4-ENSURE-JOURNAL-WORKSPACE "
                "CONSTANT _LJM-WORK-IOR"
            ),
            (
                "_E4CTX _EXT4-SNAPSHOT-JOURNAL-MAP "
                "CONSTANT _LJM-IOR"
            ),
            "0 _E4CTX _EXT4-JOURNAL-MAP@ CONSTANT _LJM-FIRST",
            "11 _E4CTX _EXT4-JOURNAL-MAP@ CONSTANT _LJM-LAST",
            "100 _E4CTX _EXT4-JOURNAL-HOME? CONSTANT _LJM-HOME",
            "999 _E4CTX _EXT4-JOURNAL-HOME? 0= CONSTANT _LJM-NONHOME",
            (
                "100 _E4CTX _EXT4-C.INODE + _EXT4-I.BLOCK + "
                "11 4 * + L!"
            ),
            (
                "_E4CTX _EXT4-SNAPSHOT-JOURNAL-MAP "
                "CONSTANT _LJM-DUP-IOR"
            ),
            (
                "_LJM-WORK-IOR 0= "
                "_E4CTX _EXT4-C.J.MAP-CAPACITY + @ 12 = AND "
                "_E4CTX _EXT4-C.J.MAP-HASH-SLOTS + @ 32 = AND "
                "_LJM-IOR 0= AND _LJM-FIRST 100 = AND "
                "_LJM-LAST 111 = AND _LJM-HOME AND _LJM-NONHOME AND "
                "_LJM-DUP-IOR VFS-IOR-REASON VFS-R-CORRUPT = AND "
                "_LJM-DUP-IOR VFS-IOR-DETAIL EXT4-D-JOURNAL = AND "
                'IF ." EXT4-LEGACY-JOURNAL-MAP-OK" THEN'
            ),
            "CREATE _E4-NOMEM-CTX _EXT4-CTX-SIZE ALLOT",
            "_E4-NOMEM-CTX _EXT4-CTX-SIZE 0 FILL",
            (
                "12 CELLS 32 CELLS + 1 CELLS - A-XMEM ARENA-NEW "
                "THROW CONSTANT _E4-NOMEM-ARENA"
            ),
            (
                "_E4-NOMEM-ARENA _E4-NOMEM-CTX _EXT4-C.ARENA + ! "
                "_E4-NOMEM-ARENA ARENA-USED CONSTANT _E4-NOMEM-BEFORE"
            ),
            (
                "12 _E4-NOMEM-CTX _EXT4-ENSURE-JOURNAL-WORKSPACE "
                "CONSTANT _E4-NOMEM-IOR"
            ),
            "_E4-NOMEM-ARENA ARENA-USED CONSTANT _E4-NOMEM-AFTER",
            (
                "_E4-NOMEM-IOR VFS-E-NOMEM = "
                "_E4-NOMEM-BEFORE _E4-NOMEM-AFTER = AND "
                "_E4-NOMEM-CTX _EXT4-C.J.MAP + @ 0= AND "
                "_E4-NOMEM-CTX _EXT4-C.J.MAP-HASH + @ 0= AND "
                "_E4-NOMEM-CTX _EXT4-C.J.MAP-CAPACITY + @ 0= AND "
                "_E4-NOMEM-CTX _EXT4-C.J.MAP-HASH-SLOTS + @ 0= AND "
                "_E4-NOMEM-CTX _EXT4-C.J.METADATA-HASH + @ 0= AND "
                "_E4-NOMEM-CTX _EXT4-C.J.METADATA-CAPACITY + @ 0= AND "
                "_E4-NOMEM-CTX _EXT4-C.J.METADATA-HASH-SLOTS + @ 0= AND "
                'IF ." EXT4-JOURNAL-WORKSPACE-NOMEM" THEN'
            ),
            "_E4CTX _EXT4-C.INODE + _EXT4-I.BLOCK + 60 0 FILL",
            "11 _E4CTX _EXT4-C.J.MAXLEN + !",
            (
                "777 _E4CTX _EXT4-C.INODE + _EXT4-I.BLOCK + "
                "11 4 * + L!"
            ),
            (
                "_E4CTX _EXT4-VALIDATE-JOURNAL-INODE-MAP "
                "CONSTANT _E4-BEYOND-EOF-IOR"
            ),
            (
                "_E4-BEYOND-EOF-IOR VFS-IOR-REASON VFS-R-CORRUPT = "
                "_EXT4-MAP-VALIDATION-LIMIT @ 0= AND "
                'IF ." EXT4-JOURNAL-EOF-BOUND-OK" THEN'
            ),
            "_E4CTX _EXT4-C.INODE + _EXT4-I.BLOCK + 60 0 FILL",
            (
                "_EXT4-EXTENT-MAGIC _E4CTX _EXT4-C.INODE + "
                "_EXT4-I.BLOCK + W!"
            ),
            "1 _E4CTX _EXT4-C.INODE + _EXT4-I.BLOCK + 2 + W!",
            "4 _E4CTX _EXT4-C.INODE + _EXT4-I.BLOCK + 4 + W!",
            "13 _E4CTX _EXT4-C.INODE + _EXT4-I.BLOCK + 16 + W!",
            "1 _E4CTX _EXT4-C.INODE + _EXT4-I.BLOCK + 20 + L!",
            (
                "_EXT4-EXTENTS-FL _E4CTX _EXT4-C.INODE + "
                "_EXT4-I.FLAGS + L!"
            ),
            "12 _E4CTX _EXT4-C.J.MAXLEN + !",
            (
                "_E4CTX _EXT4-VALIDATE-JOURNAL-INODE-MAP "
                "CONSTANT _E4-EXTENT-BEYOND-EOF-IOR"
            ),
            (
                "_E4-EXTENT-BEYOND-EOF-IOR VFS-IOR-REASON "
                "VFS-R-CORRUPT = "
                "_EXT4-MAP-VALIDATION-LIMIT @ 0= AND "
                'IF ." EXT4-JOURNAL-EXTENT-EOF-BOUND-OK" THEN'
            ),
            "_E4CTX _EXT4-C.INODE + _EXT4-I.BLOCK + 60 0 FILL",
            "0 _E4CTX _EXT4-C.INODE + _EXT4-I.FLAGS + L!",
            "100 _E4CTX _EXT4-C.INODE + _EXT4-I.BLOCK + 12 4 * + L!",
            "13 _E4CTX _EXT4-C.J.MAXLEN + !",
            "1 _E4CTX _EXT4-C.J.METADATA-COUNT + !",
            (
                "_E4CTX _EXT4-PREPARE-JOURNAL-METADATA-HASH "
                "CONSTANT _E4-METADATA-PREP-IOR"
            ),
            "500 _E4CTX _EXT4-JOURNAL-METADATA-UNIQUE? CONSTANT _E4-META-ADD",
            "500 _E4CTX _EXT4-JOURNAL-HOME? CONSTANT _E4-META-HOME",
            (
                "_E4CTX _EXT4-VERIFY-JOURNAL-METADATA-DISJOINT "
                "CONSTANT _E4-METADATA-ALIAS-IOR"
            ),
            (
                "_E4-METADATA-PREP-IOR 0= _E4-META-ADD AND "
                "_E4-META-HOME AND "
                "_E4-METADATA-ALIAS-IOR VFS-IOR-REASON "
                "VFS-R-CORRUPT = AND "
                "_E4-METADATA-ALIAS-IOR VFS-IOR-DETAIL "
                "EXT4-D-JOURNAL = AND "
                'IF ." EXT4-JOURNAL-METADATA-ALIAS-OK" THEN'
            ),
        ],
    )
    _assert_emitted(output, "EXT4-PARSER-TOTAL-OK")
    _assert_emitted(output, "EXT4-HUGE-BLOCKS-OK")
    _assert_emitted(output, "EXT4-TIMESTAMP-SIGN-OK")
    _assert_emitted(output, "EXT4-LEGACY-JOURNAL-MAP-OK")
    _assert_emitted(output, "EXT4-JOURNAL-WORKSPACE-NOMEM")
    _assert_emitted(output, "EXT4-JOURNAL-EOF-BOUND-OK")
    _assert_emitted(output, "EXT4-JOURNAL-EXTENT-EOF-BOUND-OK")
    _assert_emitted(output, "EXT4-JOURNAL-METADATA-ALIAS-OK")


def test_htree_and_internal_extent_parser_semantics_are_total(
    tmp_path: Path,
) -> None:
    blank = tmp_path / "tree-parser-storage.img"
    blank.write_bytes(bytes(4 * 512))
    output = run_forth(
        blank,
        [
            "CREATE _TREECTX _EXT4-CTX-SIZE ALLOT",
            "_TREECTX _EXT4-CTX-SIZE 0 FILL",
            "CREATE _DXENTRIES 32 ALLOT",
            "_DXENTRIES 32 0 FILL",
            "4 _DXENTRIES W! 3 _DXENTRIES 2 + W!",
            "1 _DXENTRIES 4 + L!",
            "0x1000 _DXENTRIES 8 + L! 2 _DXENTRIES 12 + L!",
            "0x1001 _DXENTRIES 16 + L! 3 _DXENTRIES 20 + L!",
            (
                "_DXENTRIES 4 8 _TREECTX _EXT4-VALIDATE-DX-ENTRIES "
                "CONSTANT _DX-VALID"
            ),
            "0x1000 _DXENTRIES 16 + L!",
            (
                "_DXENTRIES 4 8 _TREECTX _EXT4-VALIDATE-DX-ENTRIES "
                "CONSTANT _DX-BROKEN-CONT"
            ),
            "0x0800 _DXENTRIES 16 + L!",
            (
                "_DXENTRIES 4 8 _TREECTX _EXT4-VALIDATE-DX-ENTRIES "
                "CONSTANT _DX-UNORDERED"
            ),
            "0x2000 _DXENTRIES 16 + L! 2 _DXENTRIES 20 + L!",
            (
                "_DXENTRIES 4 8 _TREECTX _EXT4-VALIDATE-DX-ENTRIES "
                "CONSTANT _DX-DUP-BLOCK"
            ),
            "8 _DXENTRIES 20 + L!",
            (
                "_DXENTRIES 4 8 _TREECTX _EXT4-VALIDATE-DX-ENTRIES "
                "CONSTANT _DX-OOB-BLOCK"
            ),
            "1024 _TREECTX _EXT4-C.BSIZE + !",
            "11 _EXT4-DX-DIRINO ! 2 _EXT4-DX-PARINO !",
            "11 _TREECTX _EXT4-C.DIR-BLOCK + L!",
            "12 _TREECTX _EXT4-C.DIR-BLOCK + 4 + W!",
            "1 _TREECTX _EXT4-C.DIR-BLOCK + 6 + C!",
            "2 _TREECTX _EXT4-C.DIR-BLOCK + 7 + C!",
            "46 _TREECTX _EXT4-C.DIR-BLOCK + 8 + C!",
            "2 _TREECTX _EXT4-C.DIR-BLOCK + 12 + L!",
            "1012 _TREECTX _EXT4-C.DIR-BLOCK + 16 + W!",
            "2 _TREECTX _EXT4-C.DIR-BLOCK + 18 + C!",
            "2 _TREECTX _EXT4-C.DIR-BLOCK + 19 + C!",
            "46 _TREECTX _EXT4-C.DIR-BLOCK + 20 + C!",
            "46 _TREECTX _EXT4-C.DIR-BLOCK + 21 + C!",
            "1 _TREECTX _EXT4-C.DIR-BLOCK + 28 + C!",
            "8 _TREECTX _EXT4-C.DIR-BLOCK + 29 + C!",
            "2 _TREECTX _EXT4-C.DIR-BLOCK + 30 + C!",
            (
                "_TREECTX 8 _EXT4-VALIDATE-DX-ROOT "
                "CONSTANT _DX-DEEP-ROOT"
            ),
            "CREATE _EMPTY-INDEX 60 ALLOT",
            "_EMPTY-INDEX 60 0 FILL",
            "_EXT4-EXTENT-MAGIC _EMPTY-INDEX W!",
            "4 _EMPTY-INDEX 4 + W! 1 _EMPTY-INDEX 6 + W!",
            (
                "_EMPTY-INDEX 4 1 _TREECTX _EXT4-VALIDATE-EXTENT-NODE "
                "CONSTANT _EMPTY-INDEX-IOR"
            ),
            (
                "_DX-VALID 0= "
                "_DX-BROKEN-CONT VFS-IOR-REASON VFS-R-CORRUPT = AND "
                "_DX-BROKEN-CONT VFS-IOR-DETAIL EXT4-D-DIRECTORY = AND "
                "_DX-UNORDERED VFS-IOR-REASON VFS-R-CORRUPT = AND "
                "_DX-DUP-BLOCK VFS-IOR-REASON VFS-R-CORRUPT = AND "
                "_DX-OOB-BLOCK VFS-IOR-REASON VFS-R-CORRUPT = AND "
                "_DX-DEEP-ROOT VFS-IOR-REASON VFS-R-CORRUPT = AND "
                "_EMPTY-INDEX-IOR VFS-IOR-REASON VFS-R-CORRUPT = AND "
                'IF ." EXT4-TREE-PARSER-SEMANTICS-OK" THEN'
            ),
        ],
    )
    _assert_emitted(output, "EXT4-TREE-PARSER-SEMANTICS-OK")


def test_indexed_flag_is_admitted_only_on_directories(
    canonical_images: dict[str, Path],
) -> None:
    path = canonical_images["primary-1k-i256"]
    output = run_forth(
        path,
        [
            "T-ARENA T-VOLUME EXT4-NEW CONSTANT _M-IOR CONSTANT _V",
            "2 _V _EXT4-CTX _EXT4-LOAD-INODE CONSTANT _ROOT-L-IOR",
            (
                "_V _EXT4-CTX _EXT4-C.INODE + _EXT4-I.FLAGS + "
                "DUP @ _EXT4-INDEX-FL OR SWAP !"
            ),
            (
                "_V _EXT4-CTX _EXT4-STAGE-CURRENT-INODE "
                "CONSTANT _ROOT-S-IOR CONSTANT _ROOT-TYPE"
            ),
            "14 _V _EXT4-CTX _EXT4-LOAD-INODE CONSTANT _FILE-L-IOR",
            (
                "_V _EXT4-CTX _EXT4-C.INODE + _EXT4-I.FLAGS + "
                "DUP @ _EXT4-INDEX-FL OR SWAP !"
            ),
            (
                "_V _EXT4-CTX _EXT4-STAGE-CURRENT-INODE "
                "CONSTANT _FILE-S-IOR CONSTANT _FILE-TYPE"
            ),
            (
                "_M-IOR 0= _ROOT-L-IOR 0= AND "
                "_ROOT-S-IOR 0= AND _ROOT-TYPE VFS-T-DIR = AND "
                "_FILE-L-IOR 0= AND _FILE-TYPE 0= AND "
                "_FILE-S-IOR VFS-IOR-REASON VFS-R-CORRUPT = AND "
                "_FILE-S-IOR VFS-IOR-DETAIL EXT4-D-FEATURE = AND "
                'IF ." EXT4-HTREE-FLAG-POLICY-OK" THEN'
            ),
        ],
    )
    _assert_emitted(output, "EXT4-HTREE-FLAG-POLICY-OK")


def _canonical_lines(row: dict) -> list[str]:
    block_size = row["block_size"]
    inode_size = row["inode_size"]
    groups = row["expected_groups"]
    return [
        "CREATE _E4BUF 16384 ALLOT",
        "CREATE _E4STAT VFS-STATFS-SIZE ALLOT",
        "T-ARENA T-VOLUME EXT4-NEW CONSTANT _M-IOR CONSTANT _V",
        (
            "_M-IOR 0= _V V.LIFECYCLE @ VFS-L-MOUNTED = AND "
            "_V V.FLAGS @ VFS-F-RO AND 0<> AND "
            f"_V EXT4-BLOCK-SIZE@ {block_size} = AND "
            f"_V EXT4-INODE-SIZE@ {inode_size} = AND "
            f"_V EXT4-GROUP-COUNT@ {groups} = AND "
            'IF ." EXT4-MOUNT-OK" THEN'
        ),
        'S" /fixture/payload.txt" _V VFS-RESOLVE? CONSTANT _P-IOR CONSTANT _P',
        'S" /fixture/hardlink.txt" _V VFS-RESOLVE? CONSTANT _H-IOR CONSTANT _H',
        (
            "_P-IOR 0= _H-IOR 0= AND _P IN.BID @ 14 = AND "
            "_P D.VNODE @ _H D.VNODE @ = AND "
            "_P D.VNODE @ VN.NLINK @ 2 = AND "
            'IF ." EXT4-HARDLINK-OK" THEN'
        ),
        "_P _V VFS-GETATTR CONSTANT _GA-IOR",
        (
            "_GA-IOR 0= _P IN.SIZE-LO @ 54 = AND "
            "_P IN.MODE @ 0xF000 AND 0x8000 = AND "
            "_P D.VNODE @ VN.NLINK @ 2 = AND "
            "_P D.VNODE @ VN.ATIME-NS @ 1000000000 U< AND "
            "_P D.VNODE @ VN.MTIME-NS @ 1000000000 U< AND "
            "_P D.VNODE @ VN.CTIME-NS @ 1000000000 U< AND "
            'IF ." EXT4-METADATA-OK" THEN'
        ),
        (
            'S" /fixture/payload.txt" VFS-FF-READ _V VFS-OPEN? '
            "CONSTANT _O-IOR CONSTANT _FD"
        ),
        "_E4BUF 128 _FD VFS-READ? CONSTANT _R-IOR CONSTANT _RN",
        (
            "_O-IOR 0= _R-IOR 0= AND _RN 54 = AND "
            "_E4BUF C@ 65 = AND _E4BUF 53 + C@ 10 = AND "
            'IF ." EXT4-PAYLOAD-OK" THEN'
        ),
        "_FD VFS-CLOSE? DROP",
        'S" /fixture/sparse.bin" VFS-FF-READ _V VFS-OPEN? DROP CONSTANT _SFD',
        f"_E4BUF {block_size * 3} _SFD VFS-READ? CONSTANT _S-IOR CONSTANT _SN",
        (
            f"_S-IOR 0= _SN {block_size * 3} = AND "
            f"_E4BUF C@ 65 = AND _E4BUF {block_size} + C@ 0= AND "
            f"_E4BUF {block_size * 2} + C@ 67 = AND "
            'IF ." EXT4-SPARSE-OK" THEN'
        ),
        "_SFD VFS-CLOSE? DROP",
        (
            'S" /fixture/fast-link" VFS-RP-NOFOLLOW-FINAL _V '
            "VFS-RESOLVE-POLICY? DROP CONSTANT _FL"
        ),
        "_E4BUF 128 _FL _V VFS-READLINK CONSTANT _FL-IOR CONSTANT _FLN",
        (
            'S" /fixture/slow-link" VFS-RP-NOFOLLOW-FINAL _V '
            "VFS-RESOLVE-POLICY? DROP CONSTANT _SL"
        ),
        "_E4BUF 128 _SL _V VFS-READLINK CONSTANT _SL-IOR CONSTANT _SLN",
        (
            "_FL-IOR 0= _FLN 11 = AND _SL-IOR 0= AND _SLN 96 = AND "
            'IF ." EXT4-SYMLINKS-OK" THEN'
        ),
        "0 0 _P _V VFS-LISTXATTR CONSTANT _LX-IOR CONSTANT _LXN",
        'S" user.akashic" _E4BUF 32 _P _V VFS-GETXATTR CONSTANT _GX-IOR CONSTANT _GXN',
        (
            "_LX-IOR 0= _LXN 32 = AND _GX-IOR 0= AND _GXN 10 = AND "
            'S" profile-v1" DROP _E4BUF 10 _EXT4-BYTES=? AND '
            'IF ." EXT4-XATTR-SMALL-OK" THEN'
        ),
        (
            'S" user.akashic.large" _E4BUF 400 _P _V VFS-GETXATTR '
            "CONSTANT _GL-IOR CONSTANT _GLN"
        ),
        (
            "_GL-IOR 0= _GLN 300 = AND _E4BUF C@ 120 = AND "
            "_E4BUF 299 + C@ 120 = AND "
            'IF ." EXT4-XATTR-LARGE-OK" THEN'
        ),
        "_E4STAT VFS-STATFS-SIZE _V VFS-STATFS CONSTANT _SF-IOR",
        (
            f"_SF-IOR 0= _E4STAT VSF.BSIZE @ {block_size} = AND "
            f"_E4STAT VSF.BLOCKS @ {row['block_count']} = AND "
            f"_E4STAT VSF.FILES @ {row['expected_inodes']} = AND "
            "_E4STAT VSF.NAMEMAX @ 255 = AND "
            'IF ." EXT4-STATFS-OK" THEN'
        ),
        (
            'S" /fixture/payload.txt" VFS-FF-WRITE _V VFS-OPEN? '
            "CONSTANT _W-IOR CONSTANT _WFD"
        ),
        (
            "_WFD 0= _W-IOR VFS-IOR-REASON VFS-R-READONLY = AND "
            'IF ." EXT4-READONLY-OK" THEN'
        ),
    ]


@pytest.mark.parametrize("image_id", IMAGE_IDS)
def test_canonical_images_are_fully_inspectable(
    canonical_images: dict[str, Path], image_id: str
) -> None:
    row = IMAGE_ROWS[image_id]
    path = canonical_images[image_id]
    before = _sha256(path)
    output = run_forth(path, _canonical_lines(row))
    for marker in (
        "EXT4-MOUNT-OK",
        "EXT4-HARDLINK-OK",
        "EXT4-METADATA-OK",
        "EXT4-PAYLOAD-OK",
        "EXT4-SPARSE-OK",
        "EXT4-SYMLINKS-OK",
        "EXT4-XATTR-SMALL-OK",
        "EXT4-XATTR-LARGE-OK",
        "EXT4-STATFS-OK",
        "EXT4-READONLY-OK",
    ):
        _assert_emitted(output, marker)
    assert _sha256(path) == before


def _read_side_lines() -> list[str]:
    read_side = PROFILE["generator"]["read_side_population"]
    acl_access = bytes.fromhex(read_side["acl_access_value_hex"])
    acl_default = bytes.fromhex(read_side["acl_default_value_hex"])
    acl_access_create = "CREATE _ACL-ACCESS " + " ".join(
        f"0x{byte:02X} C," for byte in acl_access
    )
    acl_default_create = "CREATE _ACL-DEFAULT " + " ".join(
        f"0x{byte:02X} C," for byte in acl_default
    )
    return [
        "CREATE _E4BUF 16384 ALLOT",
        acl_access_create,
        acl_default_create,
        "T-ARENA T-VOLUME EXT4-NEW CONSTANT _M-IOR CONSTANT _V",
        (
            "_M-IOR 0= _V V.LIFECYCLE @ VFS-L-MOUNTED = AND "
            '_V V.FLAGS @ VFS-F-RO AND 0<> AND IF ." EXT4-READ-SIDE-MOUNT-OK" THEN'
        ),
        'S" /fixture/payload.txt" _V VFS-RESOLVE? CONSTANT _P-IOR CONSTANT _P',
        (
            'S" /fixture/indexed/collision-068446" _V VFS-RESOLVE? '
            "CONSTANT _HC1-IOR CONSTANT _HC1"
        ),
        (
            'S" /fixture/indexed/collision-083826" _V VFS-RESOLVE? '
            "CONSTANT _HC2-IOR CONSTANT _HC2"
        ),
        (
            'S" /fixture/indexed/candidate-000069" _V VFS-RESOLVE? '
            "CONSTANT _HL-IOR CONSTANT _HL"
        ),
        (
            'S" /fixture/indexed/candidate-000064" _V VFS-RESOLVE? '
            "CONSTANT _HH-IOR CONSTANT _HH"
        ),
        (
            "_P-IOR 0= _HC1-IOR 0= AND _HC2-IOR 0= AND "
            "_HL-IOR 0= AND _HH-IOR 0= AND "
            "_HC1 D.VNODE @ _HC2 D.VNODE @ = AND "
            "_HC1 D.VNODE @ _HL D.VNODE @ = AND "
            "_HC1 D.VNODE @ _HH D.VNODE @ = AND "
            "_HC1 D.VNODE @ VN.NLINK @ 100 = AND "
            'IF ." EXT4-HTREE-OK" THEN'
        ),
        (
            'S" /fixture/extent-tree.bin" VFS-FF-READ _V VFS-OPEN? '
            "CONSTANT _ET-IOR CONSTANT _ETFD"
        ),
        "_E4BUF 12288 _ETFD VFS-READ? CONSTANT _ER-IOR CONSTANT _ERN",
        (
            "_ET-IOR 0= _ER-IOR 0= AND _ERN 12288 = AND "
            "_E4BUF C@ 65 = AND _E4BUF 1024 + C@ 0= AND "
            "_E4BUF 2048 + C@ 67 = AND _E4BUF 3072 + C@ 0= AND "
            "_E4BUF 4096 + C@ 69 = AND _E4BUF 5120 + C@ 0= AND "
            "_E4BUF 6144 + C@ 71 = AND _E4BUF 7168 + C@ 0= AND "
            "_E4BUF 8192 + C@ 73 = AND _E4BUF 9216 + C@ 0= AND "
            "_E4BUF 10240 + C@ 75 = AND _E4BUF 11264 + C@ 76 = AND "
            "_E4BUF 12287 + C@ 76 = AND "
            'IF ." EXT4-EXTERNAL-EXTENTS-OK" THEN'
        ),
        "_ETFD VFS-CLOSE? DROP",
        (
            'S" /fixture/legacy-map.bin" VFS-FF-READ _V VFS-OPEN? '
            "CONSTANT _LM-IOR CONSTANT _LMFD"
        ),
        "0 _LMFD VFS-SEEK? CONSTANT _LS0",
        "_E4BUF 1 _LMFD VFS-READ? CONSTANT _LR0-IOR CONSTANT _LR0-N",
        "_E4BUF C@ CONSTANT _LB0",
        "1024 _LMFD VFS-SEEK? CONSTANT _LSH",
        "_E4BUF 1 _LMFD VFS-READ? CONSTANT _LRH-IOR CONSTANT _LRH-N",
        "_E4BUF C@ CONSTANT _LBH",
        "12288 _LMFD VFS-SEEK? CONSTANT _LS1",
        "_E4BUF 1 _LMFD VFS-READ? CONSTANT _LR1-IOR CONSTANT _LR1-N",
        "_E4BUF C@ CONSTANT _LB1",
        "274432 _LMFD VFS-SEEK? CONSTANT _LS2",
        "_E4BUF 1 _LMFD VFS-READ? CONSTANT _LR2-IOR CONSTANT _LR2-N",
        "_E4BUF C@ CONSTANT _LB2",
        "67383296 _LMFD VFS-SEEK? CONSTANT _LS3",
        "_E4BUF 1 _LMFD VFS-READ? CONSTANT _LR3-IOR CONSTANT _LR3-N",
        "_E4BUF C@ CONSTANT _LB3",
        "67384320 _LMFD VFS-SEEK? CONSTANT _LS4",
        "_E4BUF 1 _LMFD VFS-READ? CONSTANT _LR4-IOR CONSTANT _LR4-N",
        "_E4BUF C@ CONSTANT _LB4",
        (
            "_LM-IOR 0= _LMFD VFS-SIZE 67385344 = AND "
            "_LS0 0= AND _LR0-IOR 0= AND _LR0-N 1 = AND _LB0 65 = AND "
            "_LSH 0= AND _LRH-IOR 0= AND _LRH-N 1 = AND _LBH 0= AND "
            "_LS1 0= AND _LR1-IOR 0= AND _LR1-N 1 = AND _LB1 83 = AND "
            "_LS2 0= AND _LR2-IOR 0= AND _LR2-N 1 = AND _LB2 68 = AND "
            "_LS3 0= AND _LR3-IOR 0= AND _LR3-N 1 = AND _LB3 84 = AND "
            "_LS4 0= AND _LR4-IOR 0= AND _LR4-N 1 = AND _LB4 85 = AND "
            'IF ." EXT4-LEGACY-MAP-OK" THEN'
        ),
        "_LMFD VFS-CLOSE? DROP",
        'S" /fixture/char-old" _V VFS-RESOLVE? DROP CONSTANT _CHAR',
        'S" /fixture/block-new" _V VFS-RESOLVE? DROP CONSTANT _BLOCK',
        'S" /fixture/fifo" _V VFS-RESOLVE? DROP CONSTANT _FIFO',
        (
            "_CHAR IN.TYPE @ VFS-T-SPECIAL = "
            "_CHAR D.VNODE @ VN.RDEV @ VFS-RDEV-MAJOR 5 = AND "
            "_CHAR D.VNODE @ VN.RDEV @ VFS-RDEV-MINOR 1 = AND "
            "_BLOCK IN.TYPE @ VFS-T-SPECIAL = AND "
            "_BLOCK D.VNODE @ VN.RDEV @ VFS-RDEV-MAJOR 259 = AND "
            "_BLOCK D.VNODE @ VN.RDEV @ VFS-RDEV-MINOR 513 = AND "
            "_FIFO IN.TYPE @ VFS-T-SPECIAL = AND "
            "_FIFO D.VNODE @ VN.RDEV @ 0= AND "
            'IF ." EXT4-SPECIAL-METADATA-OK" THEN'
        ),
        (
            'S" /fixture/char-old" VFS-FF-READ _V VFS-OPEN? '
            "CONSTANT _COPEN-IOR CONSTANT _CFD"
        ),
        (
            "_CFD 0= _COPEN-IOR VFS-IOR-REASON VFS-R-UNSUPPORTED = AND "
            'IF ." EXT4-SPECIAL-OPEN-UNSUPPORTED" THEN'
        ),
        "0 0 _P _V VFS-LISTXATTR CONSTANT _XL-IOR CONSTANT _XL-N",
        (
            'S" user.akashic" _E4BUF 400 _P _V VFS-GETXATTR '
            "CONSTANT _XU-IOR CONSTANT _XU-N"
        ),
        (
            "_XU-IOR 0= _XU-N 10 = AND "
            'S" profile-v1" DROP _E4BUF 10 _EXT4-BYTES=? AND '
            "CONSTANT _XU-OK"
        ),
        (
            'S" user.akashic.large2" _E4BUF 400 _P _V VFS-GETXATTR '
            "CONSTANT _XY-IOR CONSTANT _XY-N"
        ),
        (
            "_XY-IOR 0= _XY-N 260 = AND _E4BUF C@ 121 = AND "
            "_E4BUF 259 + C@ 121 = AND CONSTANT _XY-OK"
        ),
        (
            'S" trusted.akashic" _E4BUF 400 _P _V VFS-GETXATTR '
            "CONSTANT _XT-IOR CONSTANT _XT-N"
        ),
        (
            "_XT-IOR 0= _XT-N 10 = AND "
            'S" trusted-v1" DROP _E4BUF 10 _EXT4-BYTES=? AND '
            "CONSTANT _XT-OK"
        ),
        (
            'S" security.akashic" _E4BUF 400 _P _V VFS-GETXATTR '
            "CONSTANT _XS-IOR CONSTANT _XS-N"
        ),
        (
            "_XS-IOR 0= _XS-N 11 = AND "
            'S" security-v1" DROP _E4BUF 11 _EXT4-BYTES=? AND '
            "CONSTANT _XS-OK"
        ),
        (
            'S" system.posix_acl_access" _E4BUF 400 _P _V VFS-GETXATTR '
            "CONSTANT _XA-IOR CONSTANT _XA-N"
        ),
        (
            f"_XA-IOR 0= _XA-N {len(acl_access)} = AND "
            f"_ACL-ACCESS _E4BUF {len(acl_access)} _EXT4-BYTES=? AND "
            "CONSTANT _XA-OK"
        ),
        'S" /fixture" _V VFS-RESOLVE? DROP CONSTANT _FIXTURE',
        (
            'S" system.posix_acl_default" _E4BUF 400 _FIXTURE _V '
            "VFS-GETXATTR CONSTANT _XD-IOR CONSTANT _XD-N"
        ),
        (
            f"_XD-IOR 0= _XD-N {len(acl_default)} = AND "
            f"_ACL-DEFAULT _E4BUF {len(acl_default)} _EXT4-BYTES=? AND "
            "CONSTANT _XD-OK"
        ),
        (
            "_XL-IOR 0= _XL-N 109 = AND _XU-OK AND _XY-OK AND "
            "_XT-OK AND _XS-OK AND _XA-OK AND _XD-OK AND "
            'IF ." EXT4-XATTR-NAMESPACES-OK" THEN'
        ),
        'S" /fixture/fast-link" _V VFS-RESOLVE? DROP CONSTANT _SF',
        'S" /fixture/absolute-link" _V VFS-RESOLVE? DROP CONSTANT _SA',
        'S" /fixture/chain-a" _V VFS-RESOLVE? DROP CONSTANT _SC',
        'S" /fixture/live-slow-link" _V VFS-RESOLVE? DROP CONSTANT _SSL',
        'S" /fixture-dir/payload.txt" _V VFS-RESOLVE? DROP CONSTANT _SD',
        (
            'S" /fixture/fast-link" VFS-RP-NOFOLLOW-FINAL _V '
            "VFS-RESOLVE-POLICY? DROP CONSTANT _SNF"
        ),
        "_E4BUF 128 _SNF _V VFS-READLINK CONSTANT _SR-IOR CONSTANT _SR-N",
        'S" /fixture/dangling-link" _V VFS-RESOLVE? CONSTANT _DG-IOR CONSTANT _DG',
        'S" /fixture/loop-a" _V VFS-RESOLVE? CONSTANT _LOOP-IOR CONSTANT _LOOP',
        (
            "_SF D.VNODE @ _P D.VNODE @ = "
            "_SA D.VNODE @ _P D.VNODE @ = AND "
            "_SC D.VNODE @ _P D.VNODE @ = AND "
            "_SSL D.VNODE @ _P D.VNODE @ = AND "
            "_SD D.VNODE @ _P D.VNODE @ = AND "
            "_SNF IN.TYPE @ VFS-T-SYMLINK = AND "
            "_SR-IOR 0= AND _SR-N 11 = AND "
            'S" payload.txt" DROP _E4BUF 11 _EXT4-BYTES=? AND '
            "_DG 0= AND _DG-IOR VFS-IOR-REASON VFS-R-NOENT = AND "
            "_LOOP 0= AND _LOOP-IOR VFS-IOR-REASON VFS-R-LOOP = AND "
            'IF ." EXT4-GENERIC-SYMLINKS-OK" THEN'
        ),
    ]


def test_supplemental_image_closes_read_side_structural_gaps(
    read_side_image: Path,
) -> None:
    before = _sha256(read_side_image)
    output = run_forth(read_side_image, _read_side_lines(), max_steps=1_600_000_000)
    for marker in (
        "EXT4-READ-SIDE-MOUNT-OK",
        "EXT4-HTREE-OK",
        "EXT4-EXTERNAL-EXTENTS-OK",
        "EXT4-LEGACY-MAP-OK",
        "EXT4-SPECIAL-METADATA-OK",
        "EXT4-SPECIAL-OPEN-UNSUPPORTED",
        "EXT4-XATTR-NAMESPACES-OK",
        "EXT4-GENERIC-SYMLINKS-OK",
    ):
        _assert_emitted(output, marker)
    assert _sha256(read_side_image) == before


def _crc32c_raw(data: bytes, seed: int = 0xFFFF_FFFF) -> int:
    crc = seed
    for byte in data:
        crc ^= byte
        for _ in range(8):
            crc = (crc >> 1) ^ (0x82F63B78 if crc & 1 else 0)
    return crc & 0xFFFF_FFFF


def _super_with_mask(path: Path, field_offset: int, value: int) -> bytes:
    with path.open("rb") as source:
        source.seek(1024)
        superblock = bytearray(source.read(1024))
    struct.pack_into("<I", superblock, field_offset, value)
    struct.pack_into("<I", superblock, 0x3FC, _crc32c_raw(superblock[:0x3FC]))
    return bytes(superblock)


REFUSED_FEATURES = (
    [(0x5C, 0x103C | bit) for bit in (1, 2, 0x40, 0x80, 0x100, 0x200, 0x400, 0x800)]
    + [
        (0x64, 0x046B | bit)
        for bit in (4, 0x10, 0x80, 0x100, 0x200, 0x800, 0x2000, 0x4000, 0x8000)
    ]
    + [
        (0x60, 0x22C2 | bit)
        for bit in (1, 8, 0x10, 0x100, 0x400, 0x1000, 0x4000, 0x8000, 0x10000, 0x20000)
    ]
)


@pytest.mark.parametrize(("field_offset", "mask"), REFUSED_FEATURES)
def test_every_known_refused_feature_fails_before_mount_publication(
    canonical_images: dict[str, Path], field_offset: int, mask: int
) -> None:
    path = canonical_images["primary-1k-i256"]
    patched = _super_with_mask(path, field_offset, mask)
    output = run_forth(
        path,
        [
            "T-ARENA T-VOLUME EXT4-NEW CONSTANT _IOR CONSTANT _V",
            (
                "_IOR VFS-IOR-REASON . _IOR VFS-IOR-DETAIL . "
                "_V V.LIFECYCLE @ ."
            ),
        ],
        patches=((1024, patched),),
    )
    assert "11 4 0" in output, output[-1500:]


def test_orphan_recovery_required_state_is_a_distinct_refusal(
    canonical_images: dict[str, Path]
) -> None:
    path = canonical_images["primary-1k-i256"]
    patched = _super_with_mask(path, 0x64, 0x1046B)
    output = run_forth(
        path,
        [
            "T-ARENA T-VOLUME EXT4-NEW CONSTANT _IOR CONSTANT _V",
            "_IOR VFS-IOR-REASON . _IOR VFS-IOR-DETAIL . _V V.LIFECYCLE @ .",
        ],
        patches=((1024, patched),),
    )
    assert "11 5 0" in output, output[-1500:]


def test_recover_without_checksum_v3_journal_refuses_before_writes(
    canonical_images: dict[str, Path]
) -> None:
    path = canonical_images["primary-1k-i256"]
    patched = _super_with_mask(path, 0x60, 0x22C6)
    output = run_forth(
        path,
        [
            "T-ARENA T-VOLUME EXT4-NEW CONSTANT _IOR CONSTANT _V",
            "_IOR VFS-IOR-REASON . _IOR VFS-IOR-DETAIL . _V V.LIFECYCLE @ .",
        ],
        patches=((1024, patched),),
    )
    assert "11 12 0" in output, output[-1500:]


def test_superblock_checksum_corruption_is_not_published(
    canonical_images: dict[str, Path],
) -> None:
    path = canonical_images["primary-1k-i256"]
    output = run_forth(
        path,
        [
            "T-ARENA T-VOLUME EXT4-NEW CONSTANT _IOR CONSTANT _V",
            (
                "_IOR VFS-IOR-REASON . _IOR VFS-IOR-DOMAIN . "
                "_IOR VFS-IOR-FLAGS . _IOR VFS-IOR-DETAIL . "
                "_V V.LIFECYCLE @ ."
            ),
        ],
        patches=((1024 + 0x78, b"X"),),
    )
    assert "10 3 4 2 0" in output, output[-1500:]


MOUNT_CORRUPTION_CASES = (
    (0x00081E, 0xF1, 6),
    (0x040C00, 0xFF, 7),
    (0x8007FC, 0xDB, 9),
    (0x80081E, 0x37, 6),
    (0x044D7C, 0xAA, 10),
    (0x1000400, 0xC0, 12),
    (0x1000443, 0x01, 12),
    (0x1000450, 0x00, 12),
    (0x1000458, 0x00, 12),
    (0x1487F8, 0x04, 13),
    (0x1487FC, 0xA9, 13),
)


def _one_byte_xor(path: Path, offset: int, expected: int) -> tuple[int, bytes]:
    with path.open("rb") as source:
        source.seek(offset)
        actual = source.read(1)
    assert actual == bytes((expected,))
    return offset, bytes((expected ^ 1,))


def _verified_patches(
    path: Path,
    edits: tuple[tuple[int, bytes, bytes], ...],
) -> tuple[tuple[int, bytes], ...]:
    patches = []
    with path.open("rb") as source:
        for offset, expected, replacement in edits:
            source.seek(offset)
            actual = source.read(len(expected))
            assert actual == expected, (
                f"fixture bytes at 0x{offset:x} changed: "
                f"expected {expected.hex()}, observed {actual.hex()}"
            )
            assert len(replacement) == len(expected)
            patches.append((offset, replacement))
    return tuple(patches)


@pytest.mark.parametrize(("offset", "expected", "detail"), MOUNT_CORRUPTION_CASES)
def test_mount_rejects_independently_corrupted_metadata(
    canonical_images: dict[str, Path],
    offset: int,
    expected: int,
    detail: int,
) -> None:
    path = canonical_images["primary-1k-i256"]
    output = run_forth(
        path,
        [
            "T-ARENA T-VOLUME EXT4-NEW CONSTANT _IOR CONSTANT _V",
            (
                "_IOR VFS-IOR-REASON . _IOR VFS-IOR-DOMAIN . "
                "_IOR VFS-IOR-FLAGS . _IOR VFS-IOR-DETAIL . "
                "_V V.LIFECYCLE @ ."
            ),
        ],
        patches=(_one_byte_xor(path, offset, expected),),
    )
    assert f"10 3 4 {detail} 0" in output, output[-1500:]


def test_journal_feature_variant_is_unsupported_not_corrupt(
    canonical_images: dict[str, Path],
) -> None:
    path = canonical_images["primary-1k-i256"]
    output = run_forth(
        path,
        [
            "T-ARENA T-VOLUME EXT4-NEW CONSTANT _IOR CONSTANT _V",
            (
                "_IOR VFS-IOR-REASON . _IOR VFS-IOR-DOMAIN . "
                "_IOR VFS-IOR-FLAGS . _IOR VFS-IOR-DETAIL . "
                "_V V.LIFECYCLE @ ."
            ),
        ],
        patches=(_one_byte_xor(path, 0x1000427, 0x00),),
    )
    assert "11 3 0 12 0" in output, output[-1500:]


def test_feature_zero_journal_rejects_private_recovery_witness(
    canonical_images: dict[str, Path],
) -> None:
    path = canonical_images["primary-1k-i256"]
    with path.open("rb") as source:
        source.seek(1024 + 0x3FC)
        intended_super_checksum = struct.unpack("<I", source.read(4))[0]
    witness = struct.pack(
        ">IIIIII",
        1,
        0x414B5231,
        intended_super_checksum,
        (~intended_super_checksum) & 0xFFFF_FFFF,
        1,
        0xFFFF_FFFE,
    )
    journal_witness_offset = 0x1000400 + 0x58
    output = run_forth(
        path,
        [
            "T-ARENA T-VOLUME EXT4-NEW CONSTANT _IOR CONSTANT _V",
            (
                "_IOR VFS-IOR-REASON . _IOR VFS-IOR-DOMAIN . "
                "_IOR VFS-IOR-FLAGS . _IOR VFS-IOR-DETAIL . "
                "_V V.LIFECYCLE @ ."
            ),
        ],
        patches=_verified_patches(
            path,
            ((journal_witness_offset, bytes(24), witness),),
        ),
    )
    assert "10 3 4 12 0" in output, output[-1500:]


def test_mount_rejects_checksum_valid_nondirectory_root(
    canonical_images: dict[str, Path],
) -> None:
    path = canonical_images["primary-1k-i256"]
    output = run_forth(
        path,
        [
            "T-ARENA T-VOLUME EXT4-NEW CONSTANT _IOR CONSTANT _V",
            "_IOR VFS-IOR-REASON . _IOR VFS-IOR-DETAIL . _V V.LIFECYCLE @ .",
        ],
        patches=(
            (0x044D01, b"\x81"),
            (0x044D7C, b"\x85\x95"),
            (0x044D82, b"\xC9\x51"),
        ),
    )
    assert "10 11 0" in output, output[-1500:]


def test_failed_mount_retry_reuses_journal_workspace(
    canonical_images: dict[str, Path],
) -> None:
    path = canonical_images["primary-1k-i256"]
    output = run_forth(
        path,
        [
            "T-ARENA CONSTANT _RETRY-ARENA",
            (
                "_RETRY-ARENA T-VOLUME EXT4-NEW "
                "CONSTANT _RETRY-IOR-1 CONSTANT _RETRY-V"
            ),
            "_RETRY-V _EXT4-CTX CONSTANT _RETRY-CTX",
            "_RETRY-ARENA ARENA-USED CONSTANT _RETRY-USED-1",
            "_RETRY-CTX _EXT4-C.J.MAP + @ CONSTANT _RETRY-MAP",
            "_RETRY-CTX _EXT4-C.J.MAP-HASH + @ CONSTANT _RETRY-HASH",
            (
                "_RETRY-CTX _EXT4-C.J.METADATA-HASH + @ "
                "CONSTANT _RETRY-METADATA-HASH"
            ),
            "_RETRY-V _EXT4-MOUNT CONSTANT _RETRY-IOR-2",
            "_RETRY-ARENA ARENA-USED CONSTANT _RETRY-USED-2",
            (
                "_RETRY-IOR-1 VFS-IOR-DETAIL EXT4-D-ROOT-INODE = "
                "_RETRY-IOR-2 VFS-IOR-DETAIL EXT4-D-ROOT-INODE = AND "
                "_RETRY-USED-1 _RETRY-USED-2 = AND "
                "_RETRY-V _EXT4-CTX _RETRY-CTX = AND "
                "_RETRY-CTX _EXT4-C.J.MAP + @ _RETRY-MAP = AND "
                "_RETRY-CTX _EXT4-C.J.MAP-HASH + @ _RETRY-HASH = AND "
                "_RETRY-CTX _EXT4-C.J.METADATA-HASH + @ "
                "_RETRY-METADATA-HASH = AND "
                "_RETRY-MAP 0<> AND "
                "_RETRY-CTX _EXT4-C.READY + @ 0= AND "
                "_RETRY-V V.LIFECYCLE @ VFS-L-NEW = AND "
                'IF ." EXT4-MOUNT-RETRY-WORKSPACE-OK" THEN'
            ),
        ],
        patches=(
            (0x044D01, b"\x81"),
            (0x044D7C, b"\x85\x95"),
            (0x044D82, b"\xC9\x51"),
        ),
    )
    _assert_emitted(output, "EXT4-MOUNT-RETRY-WORKSPACE-OK")


def test_directory_checksum_failure_rolls_back_cache_publication(
    canonical_images: dict[str, Path],
) -> None:
    path = canonical_images["primary-1k-i256"]
    output = run_forth(
        path,
        [
            "T-ARENA T-VOLUME EXT4-NEW CONSTANT _M-IOR CONSTANT _V",
            'S" /fixture" _V VFS-RESOLVE? CONSTANT _IOR CONSTANT _D',
            (
                "_M-IOR 0= _D 0= AND "
                "_IOR VFS-IOR-REASON VFS-R-CORRUPT = AND "
                "_IOR VFS-IOR-DOMAIN VFS-IOR-D-FORMAT = AND "
                "_IOR VFS-IOR-FLAGS VFS-IOR-F-CORRUPT = AND "
                "_IOR VFS-IOR-DETAIL EXT4-D-DIRECTORY = AND "
                "_V V.ROOT @ D.CHILD @ 0= AND "
                "_V V.ROOT @ IN.FLAGS @ VFS-IF-CHILDREN AND 0= AND "
                'IF ." EXT4-DIRECTORY-ROLLBACK-OK" THEN'
            ),
        ],
        patches=(_one_byte_xor(path, 0x144FFC, 0x23),),
    )
    _assert_emitted(output, "EXT4-DIRECTORY-ROLLBACK-OK")


def test_external_xattr_checksum_failure_is_reported_at_access_time(
    canonical_images: dict[str, Path],
) -> None:
    path = canonical_images["primary-1k-i256"]
    output = run_forth(
        path,
        [
            "CREATE _E4BUF 400 ALLOT",
            "T-ARENA T-VOLUME EXT4-NEW CONSTANT _M-IOR CONSTANT _V",
            'S" /fixture/payload.txt" _V VFS-RESOLVE? CONSTANT _P-IOR CONSTANT _P',
            (
                'S" user.akashic.large" _E4BUF 400 _P _V VFS-GETXATTR '
                "CONSTANT _IOR CONSTANT _N"
            ),
            (
                "_M-IOR 0= _P-IOR 0= AND _N 0= AND "
                "_IOR VFS-IOR-REASON VFS-R-CORRUPT = AND "
                "_IOR VFS-IOR-DOMAIN VFS-IOR-D-FORMAT = AND "
                "_IOR VFS-IOR-FLAGS VFS-IOR-F-CORRUPT = AND "
                "_IOR VFS-IOR-DETAIL EXT4-D-XATTR = AND "
                'IF ." EXT4-XATTR-CHECKSUM-OK" THEN'
            ),
        ],
        patches=(_one_byte_xor(path, 0x151410, 0xB6),),
    )
    _assert_emitted(output, "EXT4-XATTR-CHECKSUM-OK")


def test_checksum_valid_data_bitmap_disagreement_is_rejected_on_lookup(
    canonical_images: dict[str, Path],
) -> None:
    path = canonical_images["primary-1k-i256"]
    patches = _verified_patches(
        path,
        (
            (0x40CA8, b"\x3f", b"\x7d"),
            (0x818, b"\xc4\x3f", b"\x65\x60"),
            (0x838, b"\xa2\xaf", b"\x2e\x0c"),
            (0x81E, b"\xf1\x49", b"\x3d\x3b"),
        ),
    )
    output = run_forth(
        path,
        [
            "T-ARENA T-VOLUME EXT4-NEW CONSTANT _M-IOR CONSTANT _V",
            (
                'S" /fixture/payload.txt" _V VFS-RESOLVE? '
                "CONSTANT _IOR CONSTANT _P"
            ),
            (
                "_M-IOR 0= _P 0= AND "
                "_IOR VFS-IOR-REASON VFS-R-CORRUPT = AND "
                "_IOR VFS-IOR-DETAIL EXT4-D-DATA-MAP = AND "
                'IF ." EXT4-DATA-BITMAP-CROSSCHECK-OK" THEN'
            ),
        ],
        patches=patches,
    )
    _assert_emitted(output, "EXT4-DATA-BITMAP-CROSSCHECK-OK")


def test_checksum_valid_xattr_bitmap_disagreement_is_rejected_on_access(
    canonical_images: dict[str, Path],
) -> None:
    path = canonical_images["primary-1k-i256"]
    patches = _verified_patches(
        path,
        (
            (0x40CA8, b"\x3f", b"\x6f"),
            (0x818, b"\xc4\x3f", b"\xcb\xf8"),
            (0x838, b"\xa2\xaf", b"\x71\x9f"),
            (0x81E, b"\xf1\x49", b"\x4e\xc4"),
        ),
    )
    output = run_forth(
        path,
        [
            "CREATE _E4BUF 400 ALLOT",
            "T-ARENA T-VOLUME EXT4-NEW CONSTANT _M-IOR CONSTANT _V",
            'S" /fixture/payload.txt" _V VFS-RESOLVE? DROP CONSTANT _P',
            (
                'S" user.akashic.large" _E4BUF 400 _P _V VFS-GETXATTR '
                "CONSTANT _IOR CONSTANT _N"
            ),
            (
                "_M-IOR 0= _N 0= AND "
                "_IOR VFS-IOR-REASON VFS-R-CORRUPT = AND "
                "_IOR VFS-IOR-DETAIL EXT4-D-XATTR = AND "
                'IF ." EXT4-XATTR-BITMAP-CROSSCHECK-OK" THEN'
            ),
        ],
        patches=patches,
    )
    _assert_emitted(output, "EXT4-XATTR-BITMAP-CROSSCHECK-OK")


def test_duplicate_xattr_across_inline_and_external_storage_is_corrupt(
    canonical_images: dict[str, Path],
) -> None:
    path = canonical_images["primary-1k-i256"]
    original_entry = bytes.fromhex(
        "0d01d402000000002c01000083c6ab37"
        "616b61736869632e6c61726765000000"
    )
    duplicate_entry = bytes.fromhex(
        "0701d402000000002c01000000000000"
        "616b6173686963000000000000000000"
    )
    patches = _verified_patches(
        path,
        (
            (0x151420, original_entry, duplicate_entry),
            (0x151410, b"\xb6\xad\xf2\x86", b"\x8e\x44\x4a\xac"),
        ),
    )
    output = run_forth(
        path,
        [
            "CREATE _E4BUF 400 ALLOT",
            "T-ARENA T-VOLUME EXT4-NEW DROP CONSTANT _V",
            'S" /fixture/payload.txt" _V VFS-RESOLVE? DROP CONSTANT _P',
            (
                'S" user.akashic" _E4BUF 400 _P _V VFS-GETXATTR '
                "CONSTANT _IOR CONSTANT _N"
            ),
            (
                "_N 0= _IOR VFS-IOR-REASON VFS-R-CORRUPT = AND "
                "_IOR VFS-IOR-DETAIL EXT4-D-XATTR = AND "
                'IF ." EXT4-XATTR-DUPLICATE-OK" THEN'
            ),
        ],
        patches=patches,
    )
    _assert_emitted(output, "EXT4-XATTR-DUPLICATE-OK")


@pytest.mark.parametrize(
    ("replacement", "checksum"),
    (
        (
            bytes.fromhex("0701d4020000000001000000000000006f7665726c617000"),
            bytes.fromhex("5e79177c"),
        ),
        (
            bytes.fromhex("070140000000000001000000000000006f7665726c617000"),
            bytes.fromhex("092df811"),
        ),
    ),
)
def test_checksum_valid_xattr_value_overlaps_are_corrupt(
    canonical_images: dict[str, Path], replacement: bytes, checksum: bytes
) -> None:
    path = canonical_images["primary-1k-i256"]
    patches = _verified_patches(
        path,
        (
            (0x151440, bytes(24), replacement),
            (0x151410, b"\xb6\xad\xf2\x86", checksum),
        ),
    )
    output = run_forth(
        path,
        [
            "T-ARENA T-VOLUME EXT4-NEW DROP CONSTANT _V",
            'S" /fixture/payload.txt" _V VFS-RESOLVE? DROP CONSTANT _P',
            "0 0 _P _V VFS-LISTXATTR CONSTANT _IOR CONSTANT _N",
            (
                "_N 0= _IOR VFS-IOR-REASON VFS-R-CORRUPT = AND "
                "_IOR VFS-IOR-DETAIL EXT4-D-XATTR = AND "
                'IF ." EXT4-XATTR-OVERLAP-OK" THEN'
            ),
        ],
        patches=patches,
    )
    _assert_emitted(output, "EXT4-XATTR-OVERLAP-OK")


def test_external_extent_node_checksum_failure_is_detected(
    read_side_image: Path,
) -> None:
    # The qualified fixture oracle pins ETB0 at physical block 1353. Mutate an
    # otherwise-unused byte so semantic fields remain valid and checksum
    # verification is the only possible rejection path.
    offset = 1353 * 1024 + 100
    output = run_forth(
        read_side_image,
        [
            "T-ARENA T-VOLUME EXT4-NEW CONSTANT _M-IOR CONSTANT _V",
            (
                'S" /fixture/extent-tree.bin" _V VFS-RESOLVE? '
                "CONSTANT _IOR CONSTANT _IN"
            ),
            (
                "_M-IOR 0= _IN 0= AND "
                "_IOR VFS-IOR-REASON VFS-R-CORRUPT = AND "
                "_IOR VFS-IOR-DETAIL EXT4-D-DATA-MAP = AND "
                'IF ." EXT4-EXTENT-NODE-CHECKSUM-OK" THEN'
            ),
        ],
        patches=(_one_byte_xor(read_side_image, offset, 0),),
    )
    _assert_emitted(output, "EXT4-EXTENT-NODE-CHECKSUM-OK")


def test_htree_root_checksum_failure_rolls_back_directory_publication(
    read_side_image: Path,
) -> None:
    # The qualified fixture oracle maps indexed logical block zero to physical
    # block 1355; byte 40 is the first continuation hash covered by dx checksum.
    offset = 1355 * 1024 + 40
    output = run_forth(
        read_side_image,
        [
            "T-ARENA T-VOLUME EXT4-NEW CONSTANT _M-IOR CONSTANT _V",
            (
                'S" /fixture/indexed/collision-068446" _V VFS-RESOLVE? '
                "CONSTANT _IOR CONSTANT _IN"
            ),
            (
                "_M-IOR 0= _IN 0= AND "
                "_IOR VFS-IOR-REASON VFS-R-CORRUPT = AND "
                "_IOR VFS-IOR-DETAIL EXT4-D-DIRECTORY = AND "
                'IF ." EXT4-HTREE-CHECKSUM-OK" THEN'
            ),
        ],
        patches=(_one_byte_xor(read_side_image, offset, 0x81),),
    )
    _assert_emitted(output, "EXT4-HTREE-CHECKSUM-OK")


def test_probe_nonmatch_and_checked_io_error(
    canonical_images: dict[str, Path], tmp_path: Path
) -> None:
    zero = tmp_path / "not-ext4.img"
    zero.write_bytes(bytes(4 * 512))
    output = run_forth(
        zero,
        [
            "EXT4-BINDING T-VOLUME VFS-PROBE CONSTANT _I CONSTANT _S",
            '_I 0= _S 0= AND IF ." EXT4-PROBE-NOMATCH" THEN',
        ],
    )
    _assert_emitted(output, "EXT4-PROBE-NOMATCH")

    output = run_forth(
        canonical_images["primary-1k-i256"],
        [
            "EXT4-BINDING T-VOLUME VFS-PROBE CONSTANT _I CONSTANT _S",
            (
                "_S 0= _I VFS-IOR-DOMAIN VFS-IOR-D-VOLUME = AND "
                "_I VFS-IOR-REASON VFS-R-IO = AND "
                'IF ." EXT4-PROBE-IO" THEN'
            ),
        ],
        storage_faults=(
            {
                "stage": "start",
                "result": fat_harness.STORAGE_RESULT_MEDIA_FAILURE,
                "command": fat_harness.STORAGE_CMD_READ,
            },
        ),
    )
    _assert_emitted(output, "EXT4-PROBE-IO")


def test_private_crc32c_matches_ext4_raw_vector(tmp_path: Path) -> None:
    blank = tmp_path / "crc-storage.img"
    blank.write_bytes(bytes(4 * 512))
    output = run_forth(
        blank,
        [
            'S" 123456789" 0xFFFFFFFF _EXT4-CRC-START ',
            "_EXT4-CRC-ADD _EXT4-CRC@ 0x1CF96D7C = ",
            'IF ." EXT4-CRC32C-OK" THEN',
        ],
    )
    _assert_emitted(output, "EXT4-CRC32C-OK")
