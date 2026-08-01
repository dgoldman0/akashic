#!/usr/bin/env python3
"""Real-image tests for the read-only ext4 ABI-1 VFS binding."""

from __future__ import annotations

import errno
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
    STORAGE_STATUS_PRESENT,
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


def _crc32c_raw(data: bytes, seed: int = 0xFFFF_FFFF) -> int:
    crc = seed
    for byte in data:
        crc ^= byte
        for _ in range(8):
            crc = (crc >> 1) ^ (0x82F63B78 if crc & 1 else 0)
    return crc & 0xFFFF_FFFF


def _write_sparse_bytes(
    path: Path, data: bytes | bytearray, *, durable: bool = False
) -> None:
    """Serialize exact bytes without allocating runs that are entirely zero."""
    view = memoryview(data)
    chunk_size = 64 * 1024
    with path.open("wb") as destination:
        destination.truncate(len(view))
        for offset in range(0, len(view), chunk_size):
            chunk = view[offset : offset + chunk_size]
            if not any(chunk):
                continue
            destination.seek(offset)
            written = destination.write(chunk)
            if written != len(chunk):
                raise OSError(
                    f"short sparse image write: {written} of {len(chunk)} bytes"
                )
        destination.flush()
        if durable:
            os.fsync(destination.fileno())


def _copy_sparse_file(source: Path, destination: Path) -> None:
    """Copy a disk image while preserving filesystem holes when supported."""
    size = source.stat().st_size
    if not hasattr(os, "SEEK_DATA") or not hasattr(os, "SEEK_HOLE"):
        shutil.copyfile(source, destination)
        return

    unsupported = {errno.EINVAL, errno.ENOTSUP, errno.EOPNOTSUPP}
    extents: list[tuple[int, int]] = []
    with source.open("rb") as source_file:
        offset = 0
        while offset < size:
            try:
                data_offset = os.lseek(source_file.fileno(), offset, os.SEEK_DATA)
            except OSError as error:
                if error.errno == errno.ENXIO:
                    break
                if error.errno in unsupported:
                    shutil.copyfile(source, destination)
                    return
                raise
            try:
                hole_offset = os.lseek(
                    source_file.fileno(), data_offset, os.SEEK_HOLE
                )
            except OSError as error:
                if error.errno == errno.ENXIO:
                    hole_offset = size
                elif error.errno in unsupported:
                    shutil.copyfile(source, destination)
                    return
                else:
                    raise
            extent_end = min(hole_offset, size)
            extents.append((data_offset, extent_end))
            offset = extent_end

        with destination.open("wb") as destination_file:
            destination_file.truncate(size)
            for extent_start, extent_end in extents:
                source_file.seek(extent_start)
                destination_file.seek(extent_start)
                remaining = extent_end - extent_start
                while remaining:
                    chunk = source_file.read(min(1 << 20, remaining))
                    if not chunk:
                        raise OSError("short sparse image read")
                    written = destination_file.write(chunk)
                    if written != len(chunk):
                        raise OSError(
                            "short sparse image copy: "
                            f"{written} of {len(chunk)} bytes"
                        )
                    remaining -= len(chunk)

    if destination.stat().st_size != size:
        raise OSError("sparse image copy changed the logical size")


def _jbd2_metadata_with_checksum(
    block: bytes | bytearray, journal_uuid: bytes
) -> bytes:
    """Stamp a checksum-v2/v3 descriptor or revoke block."""
    assert len(journal_uuid) == 16
    result = bytearray(block)
    assert len(result) >= 1024
    struct.pack_into(">I", result, len(result) - 4, 0)
    seed = _crc32c_raw(journal_uuid)
    struct.pack_into(">I", result, len(result) - 4, _crc32c_raw(result, seed))
    return bytes(result)


def _jbd2_commit_with_checksum(
    block: bytes | bytearray, journal_uuid: bytes, sequence: int
) -> bytes:
    """Restamp a checksum-v2/v3 commit block for one transaction ID."""
    assert len(journal_uuid) == 16
    result = bytearray(block)
    assert len(result) >= 1024
    assert struct.unpack_from(">II", result, 0x00) == (0xC03B3998, 2)
    struct.pack_into(">I", result, 0x08, sequence & 0xFFFF_FFFF)
    struct.pack_into(">I", result, 0x10, 0)
    seed = _crc32c_raw(journal_uuid)
    struct.pack_into(">I", result, 0x10, _crc32c_raw(result, seed))
    return bytes(result)


def _relocate_jbd2_transaction(
    source: Path,
    destination: Path,
    physical_map: dict[int, int],
    destination_slots: tuple[int, int, int],
) -> None:
    """Move one debugfs-authored descriptor/data/commit tuple unchanged."""
    block_size = 1024
    source_slots = (1, 2, 3)
    assert len(set(destination_slots)) == 3
    assert 0 not in destination_slots
    with source.open("rb") as image:
        transaction = []
        for logical in source_slots:
            image.seek(physical_map[logical] * block_size)
            transaction.append(image.read(block_size))
        image.seek(physical_map[0] * block_size)
        journal_superblock = bytearray(image.read(block_size))
    assert all(len(block) == block_size for block in transaction)
    assert struct.unpack_from(">I", transaction[0], 0x00)[0] == 0xC03B3998
    assert struct.unpack_from(">I", transaction[0], 0x04)[0] == 1
    assert struct.unpack_from(">I", transaction[2], 0x00)[0] == 0xC03B3998
    assert struct.unpack_from(">I", transaction[2], 0x04)[0] == 2
    assert struct.unpack_from(">I", transaction[0], 0x08)[0] == struct.unpack_from(
        ">I", transaction[2], 0x08
    )[0]

    _copy_sparse_file(source, destination)
    with destination.open("r+b") as image:
        for logical in source_slots:
            if logical not in destination_slots:
                image.seek(physical_map[logical] * block_size)
                image.write(bytes(block_size))
        for block, logical in zip(transaction, destination_slots, strict=True):
            image.seek(physical_map[logical] * block_size)
            image.write(block)
        struct.pack_into(">I", journal_superblock, 0x1C, destination_slots[0])
        struct.pack_into(">I", journal_superblock, 0xFC, 0)
        struct.pack_into(">I", journal_superblock, 0xFC, _crc32c_raw(journal_superblock))
        image.seek(physical_map[0] * block_size)
        image.write(journal_superblock)


def _ext4_super_with_checksum(superblock: bytes | bytearray) -> bytes:
    result = bytearray(superblock)
    assert len(result) == 1024
    struct.pack_into("<I", result, 0x3FC, _crc32c_raw(result[:0x3FC]))
    return bytes(result)


def _group_descriptor_with_checksum(
    superblock: bytes, descriptor: bytes | bytearray, group: int
) -> bytes:
    result = bytearray(descriptor)
    assert len(superblock) == 1024
    assert len(result) == 64
    seed = struct.unpack_from("<I", superblock, 0x270)[0]
    struct.pack_into("<H", result, 0x1E, 0)
    checksum = _crc32c_raw(struct.pack("<I", group), seed)
    checksum = _crc32c_raw(result, checksum)
    struct.pack_into("<H", result, 0x1E, checksum & 0xFFFF)
    return bytes(result)


def _inode_with_checksum(
    superblock: bytes, inode_number: int, inode: bytes | bytearray
) -> bytes:
    result = bytearray(inode)
    assert len(superblock) == 1024
    assert len(result) >= 128
    assert inode_number > 0
    seed = struct.unpack_from("<I", superblock, 0x270)[0]
    struct.pack_into("<H", result, 0x7C, 0)
    has_checksum_high = len(result) > 128
    if has_checksum_high:
        extra_size = struct.unpack_from("<H", result, 0x80)[0]
        assert extra_size >= 4 and extra_size % 4 == 0
        assert 128 + extra_size <= len(result)
        struct.pack_into("<H", result, 0x82, 0)
    checksum = _crc32c_raw(struct.pack("<I", inode_number), seed)
    checksum = _crc32c_raw(result[0x64:0x68], checksum)
    checksum = _crc32c_raw(result, checksum)
    struct.pack_into("<H", result, 0x7C, checksum & 0xFFFF)
    if has_checksum_high:
        struct.pack_into("<H", result, 0x82, checksum >> 16)
    return bytes(result)


def _ext4_sparse_group(group: int) -> bool:
    if group in (0, 1):
        return True
    for base in (3, 5, 7):
        value = group
        while value > 1 and value % base == 0:
            value //= base
        if value == 1:
            return True
    return False


def _ext4_recovery_layout(path: Path) -> dict[str, int]:
    with path.open("rb") as source:
        source.seek(1024)
        superblock = source.read(1024)
    assert len(superblock) == 1024
    block_size = 1024 << struct.unpack_from("<I", superblock, 0x18)[0]
    blocks = struct.unpack_from("<I", superblock, 0x04)[0]
    assert struct.unpack_from("<I", superblock, 0x150)[0] == 0
    first = struct.unpack_from("<I", superblock, 0x14)[0]
    blocks_per_group = struct.unpack_from("<I", superblock, 0x20)[0]
    groups = (blocks - first + blocks_per_group - 1) // blocks_per_group
    descriptor_size = struct.unpack_from("<H", superblock, 0xFE)[0]
    assert descriptor_size == 64
    witness_super = first + blocks_per_group
    witness_gdt = witness_super + 1
    witness_gdt_span = (
        groups * descriptor_size + block_size - 1
    ) // block_size
    with path.open("rb") as source:
        source.seek(witness_gdt * block_size)
        group0_descriptor = source.read(descriptor_size)
    assert len(group0_descriptor) == descriptor_size
    inode_size = struct.unpack_from("<H", superblock, 0x58)[0]
    inode_index = 7
    inode_table_base = struct.unpack_from("<I", group0_descriptor, 0x08)[0]
    journal_root = superblock[0x10C : 0x10C + 60]
    assert struct.unpack_from("<H", journal_root, 0x00)[0] == 0xF30A
    assert struct.unpack_from("<H", journal_root, 0x06)[0] == 0

    def map_journal_block(logical: int) -> int:
        entries = struct.unpack_from("<H", journal_root, 0x02)[0]
        for index in range(entries):
            entry = 0x0C + index * 0x0C
            first_logical = struct.unpack_from("<I", journal_root, entry)[0]
            raw_length = struct.unpack_from("<H", journal_root, entry + 0x04)[0]
            assert 0 < raw_length <= 0x8000
            if first_logical <= logical < first_logical + raw_length:
                first_physical = (
                    struct.unpack_from("<H", journal_root, entry + 0x06)[0]
                    << 32
                ) | struct.unpack_from("<I", journal_root, entry + 0x08)[0]
                return first_physical + logical - first_logical
        raise AssertionError(f"journal logical block {logical} is unmapped")

    journal_block = map_journal_block(0)
    journal_commit_block = map_journal_block(3)
    return {
        "block_size": block_size,
        "blocks": blocks,
        "first": first,
        "blocks_per_group": blocks_per_group,
        "groups": groups,
        "descriptor_size": descriptor_size,
        "inode_size": inode_size,
        "primary_super": 1 if block_size == 1024 else 0,
        "primary_gdt": 2 if block_size == 1024 else 1,
        "witness_super": witness_super,
        "witness_gdt": witness_gdt,
        "witness_gdt_span": witness_gdt_span,
        "block_bitmap": struct.unpack_from("<I", group0_descriptor, 0x00)[0],
        "inode_bitmap": struct.unpack_from("<I", group0_descriptor, 0x04)[0],
        "inode_table_base": inode_table_base,
        "journal_inode_block": (
            inode_table_base + inode_index * inode_size // block_size
        ),
        "journal_inode_offset": inode_index * inode_size % block_size,
        "journal_block": journal_block,
        "journal_commit_block": journal_commit_block,
    }


def _ext4_journal_physical_map(
    path: Path, logical_blocks: tuple[int, ...]
) -> dict[int, int]:
    with path.open("rb") as source:
        source.seek(1024)
        superblock = source.read(1024)
    assert len(superblock) == 1024
    block_size = 1024 << struct.unpack_from("<I", superblock, 0x18)[0]
    journal_root = superblock[0x10C : 0x10C + 60]
    assert struct.unpack_from("<H", journal_root, 0x00)[0] == 0xF30A
    assert struct.unpack_from("<H", journal_root, 0x06)[0] == 0
    entries = struct.unpack_from("<H", journal_root, 0x02)[0]
    maximum = struct.unpack_from("<H", journal_root, 0x04)[0]
    assert 1 <= entries <= maximum <= 4
    journal_bytes = (
        struct.unpack_from("<I", superblock, 0x10C + 60)[0] << 32
    ) | struct.unpack_from("<I", superblock, 0x10C + 64)[0]
    assert journal_bytes > 0 and journal_bytes % block_size == 0
    journal_blocks = journal_bytes // block_size

    result: dict[int, int] = {}
    for logical in logical_blocks:
        assert 0 <= logical < journal_blocks
        for index in range(entries):
            entry = 0x0C + index * 0x0C
            first_logical = struct.unpack_from("<I", journal_root, entry)[0]
            raw_length = struct.unpack_from("<H", journal_root, entry + 0x04)[0]
            assert 0 < raw_length <= 0x8000
            if first_logical <= logical < first_logical + raw_length:
                first_physical = (
                    struct.unpack_from("<H", journal_root, entry + 0x06)[0]
                    << 32
                ) | struct.unpack_from("<I", journal_root, entry + 0x08)[0]
                result[logical] = first_physical + logical - first_logical
                break
        else:
            raise AssertionError(f"journal logical block {logical} is unmapped")
    return result


def _journal_metadata_alias_patches(
    image: Path, target_block: int
) -> tuple[tuple[tuple[int, bytes], ...], str]:
    """Relocate one committed journal data block onto ext4 metadata."""
    layout = _ext4_recovery_layout(image)
    block_size = layout["block_size"]
    assert block_size == 1024
    media = image.read_bytes()

    def read_block(block: int) -> bytes:
        start = block * block_size
        result = media[start : start + block_size]
        assert len(result) == block_size
        return result

    primary_super = read_block(layout["primary_super"])
    assert struct.unpack_from("<I", primary_super, 0x3FC)[0] == _crc32c_raw(
        primary_super[:0x3FC]
    )
    assert struct.unpack_from("<I", primary_super, 0x60)[0] & 0x04
    original_tuple = primary_super[0x10C : 0x10C + 68]
    original_root = original_tuple[:60]
    assert struct.unpack_from("<H", original_root, 0x00)[0] == 0xF30A
    assert struct.unpack_from("<H", original_root, 0x02)[0] == 1
    assert struct.unpack_from("<H", original_root, 0x04)[0] == 4
    assert struct.unpack_from("<H", original_root, 0x06)[0] == 0
    assert struct.unpack_from("<I", original_root, 0x0C)[0] == 0
    journal_bytes = (
        struct.unpack_from("<I", original_tuple, 0x3C)[0] << 32
    ) | struct.unpack_from("<I", original_tuple, 0x40)[0]
    assert journal_bytes > 3 * block_size
    assert journal_bytes % block_size == 0
    journal_blocks = journal_bytes // block_size
    assert struct.unpack_from("<H", original_root, 0x10)[0] == journal_blocks
    assert struct.unpack_from("<H", original_root, 0x12)[0] == 0
    journal_base = struct.unpack_from("<I", original_root, 0x14)[0]
    assert journal_base == layout["journal_block"]
    assert journal_base + journal_blocks <= layout["blocks"]
    assert 0 < target_block < layout["blocks"]
    assert not journal_base <= target_block < journal_base + journal_blocks

    physical_group = (target_block - layout["first"]) // layout[
        "blocks_per_group"
    ]
    assert 0 <= physical_group < layout["groups"]
    descriptor_offset = (
        layout["witness_gdt"] * block_size
        + physical_group * layout["descriptor_size"]
    )
    descriptor = media[
        descriptor_offset : descriptor_offset + layout["descriptor_size"]
    ]
    assert descriptor == _group_descriptor_with_checksum(
        primary_super, descriptor, physical_group
    )
    block_bitmap = struct.unpack_from("<I", descriptor, 0x00)[0]
    group_first = layout["first"] + physical_group * layout[
        "blocks_per_group"
    ]
    target_index = target_block - group_first
    bitmap = read_block(block_bitmap)
    assert bitmap[target_index // 8] & (1 << (target_index % 8))

    descriptor_block = read_block(journal_base + 1)
    journal_data = read_block(journal_base + 2)
    commit_block = read_block(journal_base + 3)
    assert read_block(target_block) != journal_data
    assert struct.unpack_from(">II", descriptor_block, 0x00) == (
        0xC03B3998,
        1,
    )
    assert struct.unpack_from(">II", commit_block, 0x00) == (
        0xC03B3998,
        2,
    )
    assert struct.unpack_from(">I", descriptor_block, 0x08)[0] == (
        struct.unpack_from(">I", commit_block, 0x08)[0]
    )

    relocated_root = bytearray(original_root)
    relocated_root[0x0C:] = bytes(48)
    struct.pack_into("<H", relocated_root, 0x02, 3)
    struct.pack_into(
        "<IHHI", relocated_root, 0x0C, 0, 2, 0, journal_base
    )
    struct.pack_into(
        "<IHHI", relocated_root, 0x18, 2, 1, 0, target_block
    )
    struct.pack_into(
        "<IHHI",
        relocated_root,
        0x24,
        3,
        journal_blocks - 3,
        0,
        journal_base + 3,
    )

    patches: list[tuple[int, bytes]] = []
    for group in range(layout["groups"]):
        if not _ext4_sparse_group(group):
            continue
        super_block = (
            layout["primary_super"]
            if group == 0
            else layout["first"] + group * layout["blocks_per_group"]
        )
        superblock = bytearray(read_block(super_block))
        assert struct.unpack_from("<H", superblock, 0x5A)[0] == group
        assert struct.unpack_from("<I", superblock, 0x3FC)[0] == _crc32c_raw(
            superblock[:0x3FC]
        )
        assert superblock[0x10C : 0x10C + 68] == original_tuple
        superblock[0x10C : 0x10C + 60] = relocated_root
        updated_super = _ext4_super_with_checksum(superblock)
        assert struct.unpack_from("<I", updated_super, 0x3FC)[0] == (
            _crc32c_raw(updated_super[:0x3FC])
        )
        assert updated_super[0x10C : 0x10C + 60] == relocated_root
        patches.append((super_block * block_size, updated_super))

    inode_block = bytearray(read_block(layout["journal_inode_block"]))
    inode_start = layout["journal_inode_offset"]
    inode_end = inode_start + layout["inode_size"]
    inode = bytearray(inode_block[inode_start:inode_end])
    assert len(inode) == layout["inode_size"]
    assert inode == _inode_with_checksum(primary_super, 8, inode)
    assert inode[0x28 : 0x28 + 60] == original_root
    assert struct.unpack_from("<I", inode, 0x04)[0] == (
        struct.unpack_from("<I", original_tuple, 0x40)[0]
    )
    assert struct.unpack_from("<I", inode, 0x6C)[0] == (
        struct.unpack_from("<I", original_tuple, 0x3C)[0]
    )
    inode[0x28 : 0x28 + 60] = relocated_root
    updated_inode = _inode_with_checksum(primary_super, 8, inode)
    assert updated_inode == _inode_with_checksum(
        primary_super, 8, updated_inode
    )
    assert updated_inode[0x28 : 0x28 + 60] == relocated_root
    inode_block[inode_start:inode_end] = updated_inode
    patches.append(
        (layout["journal_inode_block"] * block_size, bytes(inode_block))
    )

    # Apply this last when TARGET is itself a sparse-super/GDT block: the
    # intended hostile alias, rather than a stale tuple, is the sole damage.
    patches.append((target_block * block_size, journal_data))
    expected = bytearray(media)
    for offset, payload in patches:
        expected[offset : offset + len(payload)] = payload
    assert expected[
        target_block * block_size : (target_block + 1) * block_size
    ] == journal_data
    return tuple(patches), hashlib.sha256(expected).hexdigest()


def _author_jbd2_transactions(
    *,
    debugfs: Path,
    env: dict[str, str],
    source: Path,
    directory: Path,
    name: str,
    block_size: int,
    transactions: tuple[tuple[tuple[int, ...], bytes], ...],
) -> Path:
    image = directory / f"{name}.img"
    _copy_sparse_file(source, image)
    commands = ["journal_open -c -v 3"]
    for index, (blocks, payload) in enumerate(transactions):
        assert blocks
        assert len(payload) == len(blocks) * block_size
        payload_path = directory / f"{name}-{index}.bin"
        payload_path.write_bytes(payload)
        block_list = ",".join(str(block) for block in blocks)
        commands.append(f"journal_write -b {block_list} {payload_path}")
    commands.extend(("journal_close", "close"))
    command_path = directory / f"{name}.cmd"
    command_path.write_text("\n".join(commands) + "\n", encoding="utf-8")
    authored = subprocess.run(
        [str(debugfs), "-w", "-f", str(command_path), str(image)],
        env=env,
        text=True,
        capture_output=True,
        check=False,
    )
    assert authored.returncode == 0, authored.stdout + authored.stderr
    assert "Command not found" not in authored.stdout + authored.stderr
    return image


def _assert_e2fsck_clean(
    image: Path, jbd2_toolchain: dict[str, object]
) -> None:
    e2fsck = jbd2_toolchain["e2fsck"]
    env = jbd2_toolchain["env"]
    assert isinstance(e2fsck, Path)
    assert isinstance(env, dict)
    checked = subprocess.run(
        [str(e2fsck), "-f", "-n", str(image)],
        env=env,
        text=True,
        capture_output=True,
        check=False,
    )
    assert checked.returncode == 0, checked.stdout + checked.stderr


def _recover_with_e2fsck(
    source: Path,
    destination: Path,
    jbd2_toolchain: dict[str, object],
) -> None:
    e2fsck = jbd2_toolchain["e2fsck"]
    env = jbd2_toolchain["env"]
    assert isinstance(e2fsck, Path)
    assert isinstance(env, dict)
    _copy_sparse_file(source, destination)
    recovered = subprocess.run(
        [str(e2fsck), "-E", "journal_only", "-y", str(destination)],
        env=env,
        text=True,
        capture_output=True,
        check=False,
    )
    assert recovered.returncode in (0, 1), recovered.stdout + recovered.stderr
    _assert_e2fsck_clean(destination, jbd2_toolchain)


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

    def save_sparse_media() -> None:
        if (
            system.storage.image_path is not None
            and system.storage.status & STORAGE_STATUS_PRESENT
        ):
            _write_sparse_bytes(
                Path(system.storage.image_path),
                system.storage._image_data,
                durable=True,
            )

    system.storage.save_image = save_sparse_media
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
        _write_sparse_bytes(capture_media, media)
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
def jbd2_toolchain() -> dict[str, object]:
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
    e2fsck = Path(tools["e2fsck"]["path"])
    return {
        "tool_dir": tool_dir,
        "debugfs": debugfs,
        "e2fsck": e2fsck,
        "env": env,
    }


@pytest.fixture(scope="session")
def replay_fixture(
    canonical_images: dict[str, Path],
    jbd2_toolchain: dict[str, object],
    tmp_path_factory: pytest.TempPathFactory,
) -> dict[str, object]:
    debugfs = jbd2_toolchain["debugfs"]
    env = jbd2_toolchain["env"]
    assert isinstance(debugfs, Path)
    assert isinstance(env, dict)

    directory = tmp_path_factory.mktemp("ext4-jbd2-replay")
    image = directory / "replay-csum3-64bit.img"
    _copy_sparse_file(canonical_images["primary-1k-i256"], image)
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
def revoke_replay_fixture(
    canonical_images: dict[str, Path],
    jbd2_toolchain: dict[str, object],
    tmp_path_factory: pytest.TempPathFactory,
) -> dict[str, object]:
    """Build standard checksum-v3 revoke logs from debugfs transactions."""
    debugfs = jbd2_toolchain["debugfs"]
    env = jbd2_toolchain["env"]
    assert isinstance(debugfs, Path)
    assert isinstance(env, dict)
    source_image = canonical_images["primary-1k-i256"]
    block_size = 1024
    target_block = 30000
    directory = tmp_path_factory.mktemp("ext4-jbd2-revoke")
    first_payload = (
        b"JBD2-AKASHIC-REVOKED-FIRST\n" + bytes(range(256)) * 4
    )[:block_size].ljust(block_size, b"\x51")
    discarded_payload = (
        b"JBD2-AKASHIC-REVOKE-CARRIER\n" + bytes(reversed(range(256))) * 4
    )[:block_size].ljust(block_size, b"\x52")
    later_payload = (
        b"JBD2-AKASHIC-AFTER-REVOKE\n" + bytes(range(255, -1, -1)) * 4
    )[:block_size].ljust(block_size, b"\x53")
    authored = _author_jbd2_transactions(
        debugfs=debugfs,
        env=env,
        source=source_image,
        directory=directory,
        name="revoke-source",
        block_size=block_size,
        transactions=(
            ((target_block,), first_payload),
            ((target_block,), discarded_payload),
            ((target_block,), later_payload),
        ),
    )
    physical_map = _ext4_journal_physical_map(authored, tuple(range(10)))

    with authored.open("rb") as source:
        journal_blocks: dict[int, bytes] = {}
        for logical, physical in physical_map.items():
            source.seek(physical * block_size)
            journal_blocks[logical] = source.read(block_size)
        source.seek(target_block * block_size)
        home_before = source.read(block_size)
        source.seek(1024)
        ext4_superblock = source.read(1024)
    assert all(len(block) == block_size for block in journal_blocks.values())
    journal_superblock = bytearray(journal_blocks[0])
    assert struct.unpack_from(">II", journal_superblock, 0x00) == (
        0xC03B3998,
        4,
    )
    assert struct.unpack_from(">I", journal_superblock, 0x1C)[0] == 1
    assert struct.unpack_from(">I", journal_superblock, 0x28)[0] == 0x12
    journal_uuid = bytes(journal_superblock[0x30:0x40])
    sequences: list[int] = []
    for descriptor_logical, commit_logical in ((1, 3), (4, 6), (7, 9)):
        descriptor = journal_blocks[descriptor_logical]
        commit = journal_blocks[commit_logical]
        assert struct.unpack_from(">II", descriptor, 0x00) == (
            0xC03B3998,
            1,
        )
        assert struct.unpack_from(">II", commit, 0x00) == (
            0xC03B3998,
            2,
        )
        sequence = struct.unpack_from(">I", descriptor, 0x08)[0]
        assert struct.unpack_from(">I", commit, 0x08)[0] == sequence
        sequences.append(sequence)
    assert sequences[1] == (sequences[0] + 1) & 0xFFFF_FFFF
    assert sequences[2] == (sequences[1] + 1) & 0xFFFF_FFFF
    assert struct.unpack_from(">I", journal_superblock, 0x18)[0] == sequences[0]
    assert journal_superblock[0x50] == 4
    assert home_before not in (first_payload, discarded_payload, later_payload)

    struct.pack_into(">I", journal_superblock, 0x28, 0x13)
    struct.pack_into(">I", journal_superblock, 0xFC, 0)
    struct.pack_into(
        ">I", journal_superblock, 0xFC, _crc32c_raw(journal_superblock)
    )
    stored_super_checksum = struct.unpack_from(">I", journal_superblock, 0xFC)[0]
    checked_superblock = bytearray(journal_superblock)
    struct.pack_into(">I", checked_superblock, 0xFC, 0)
    assert stored_super_checksum == _crc32c_raw(checked_superblock)

    def make_revoke(blocks: tuple[int, ...]) -> bytes:
        result = bytearray(block_size)
        struct.pack_into(
            ">IIII", result, 0, 0xC03B3998, 5, sequences[1], 16 + 8 * len(blocks)
        )
        for index, block in enumerate(blocks):
            struct.pack_into(">Q", result, 16 + 8 * index, block)
        return _jbd2_metadata_with_checksum(result, journal_uuid)

    revoke = make_revoke((target_block,))

    zero = bytes(block_size)

    def variant(name: str, replacements: dict[int, bytes]) -> Path:
        image = directory / f"{name}.img"
        _copy_sparse_file(authored, image)
        complete = {0: bytes(journal_superblock), **replacements}
        with image.open("r+b") as destination:
            for logical, payload in complete.items():
                assert len(payload) == block_size
                destination.seek(physical_map[logical] * block_size)
                destination.write(payload)
        return image

    revoked_image = variant(
        "revoked",
        {
            4: bytes(revoke),
            5: journal_blocks[6],
            6: zero,
            7: zero,
            8: zero,
            9: zero,
        },
    )
    rewritten_image = variant(
        "revoked-then-rewritten",
        {
            4: bytes(revoke),
            5: journal_blocks[6],
            6: journal_blocks[7],
            7: journal_blocks[8],
            8: journal_blocks[9],
            9: zero,
        },
    )
    incomplete_image = variant(
        "incomplete-revoke",
        {4: bytes(revoke), 5: zero, 6: zero, 7: zero, 8: zero, 9: zero},
    )
    corrupt_revoke = bytearray(revoke)
    corrupt_revoke[23] ^= 0x80
    corrupt_image = variant(
        "corrupt-revoke",
        {
            4: bytes(corrupt_revoke),
            5: journal_blocks[6],
            6: zero,
            7: zero,
            8: zero,
            9: zero,
        },
    )
    collision_block = target_block + 4
    assert collision_block % 4 == target_block % 4
    multi_revoke_image = variant(
        "multi-revoke-collision",
        {
            4: make_revoke((target_block, collision_block)),
            5: journal_blocks[6],
            6: zero,
            7: zero,
            8: zero,
            9: zero,
        },
    )
    filesystem_blocks = (
        struct.unpack_from("<I", ext4_superblock, 0x150)[0] << 32
    ) | struct.unpack_from("<I", ext4_superblock, 0x04)[0]
    malformed_records: dict[str, tuple[bytes, str]] = {}

    def malformed_count(name: str, count: int) -> None:
        record = bytearray(revoke)
        struct.pack_into(">I", record, 0x0C, count)
        malformed_records[name] = (
            _jbd2_metadata_with_checksum(record, journal_uuid),
            "VFS-R-CORRUPT",
        )

    malformed_count("short-count", 15)
    malformed_count("long-count", block_size)
    malformed_count("unaligned-count", 25)
    malformed_records["high-block"] = (
        make_revoke(((1 << 32) | target_block,)),
        "VFS-R-UNSUPPORTED",
    )
    malformed_records["outside-filesystem"] = (
        make_revoke((filesystem_blocks,)),
        "VFS-R-CORRUPT",
    )
    malformed_records["journal-owned"] = (
        make_revoke((physical_map[0],)),
        "VFS-R-CORRUPT",
    )
    malformed_images = {
        name: (
            variant(
                f"malformed-revoke-{name}",
                {
                    4: record,
                    5: journal_blocks[6],
                    6: zero,
                    7: zero,
                    8: zero,
                    9: zero,
                },
            ),
            reason,
        )
        for name, (record, reason) in malformed_records.items()
    }
    return {
        "revoked_image": revoked_image,
        "rewritten_image": rewritten_image,
        "incomplete_image": incomplete_image,
        "corrupt_image": corrupt_image,
        "multi_revoke_image": multi_revoke_image,
        "malformed_images": malformed_images,
        "target_block": target_block,
        "collision_block": collision_block,
        "home_before": home_before,
        "first_payload": first_payload,
        "later_payload": later_payload,
        "journal_block": physical_map[0],
        "journal_sequence": sequences[0],
    }


@pytest.fixture(scope="session")
def recovery_authority_fixture(
    canonical_images: dict[str, Path],
    jbd2_toolchain: dict[str, object],
    tmp_path_factory: pytest.TempPathFactory,
) -> dict[str, object]:
    """Author committed repairs and forbidden recovery-authority payloads."""
    source_image = canonical_images["primary-1k-i256"]
    layout = _ext4_recovery_layout(source_image)
    block_size = layout["block_size"]
    assert block_size == 1024
    debugfs = jbd2_toolchain["debugfs"]
    env = jbd2_toolchain["env"]
    assert isinstance(debugfs, Path)
    assert isinstance(env, dict)

    def read_block(block: int) -> bytes:
        with source_image.open("rb") as source:
            source.seek(block * block_size)
            payload = source.read(block_size)
        assert len(payload) == block_size
        return payload

    primary_super = read_block(layout["primary_super"])
    primary_gdt = read_block(layout["primary_gdt"])
    witness_super = read_block(layout["witness_super"])
    witness_gdt = read_block(layout["witness_gdt"])
    with source_image.open("rb") as source:
        source.seek(layout["witness_gdt"] * block_size)
        witness_gdt_blocks = source.read(
            layout["witness_gdt_span"] * block_size
        )
    assert len(witness_gdt_blocks) == layout["witness_gdt_span"] * block_size
    inode_bitmap = read_block(layout["inode_bitmap"])

    dirty_super = bytearray(primary_super)
    struct.pack_into(
        "<I",
        dirty_super,
        0x60,
        struct.unpack_from("<I", dirty_super, 0x60)[0] | 0x04,
    )
    dirty_super = bytearray(_ext4_super_with_checksum(dirty_super))

    super_repair = bytearray(dirty_super)
    struct.pack_into(
        "<I",
        super_repair,
        0x30,
        struct.unpack_from("<I", super_repair, 0x30)[0] ^ 0x01010101,
    )
    super_repair = _ext4_super_with_checksum(super_repair)

    changed_tuple = bytearray(dirty_super)
    tuple_start = struct.unpack_from("<I", changed_tuple, 0x120)[0]
    struct.pack_into("<I", changed_tuple, 0x120, tuple_start + 1)
    changed_tuple = _ext4_super_with_checksum(changed_tuple)

    stranded_orphan = bytearray(dirty_super)
    struct.pack_into("<I", stranded_orphan, 0xE8, 11)
    stranded_orphan = _ext4_super_with_checksum(stranded_orphan)
    assert struct.unpack_from("<I", stranded_orphan, 0xE8)[0] == 11
    assert struct.unpack_from("<I", stranded_orphan, 0x3FC)[0] == _crc32c_raw(
        stranded_orphan[:0x3FC]
    )

    unbounded_counters = bytearray(dirty_super)
    blocks = struct.unpack_from("<I", unbounded_counters, 0x04)[0]
    struct.pack_into("<I", unbounded_counters, 0x0C, blocks + 1)
    unbounded_counters = _ext4_super_with_checksum(unbounded_counters)
    assert struct.unpack_from("<I", unbounded_counters, 0x0C)[0] > blocks
    assert struct.unpack_from(
        "<I", unbounded_counters, 0x3FC
    )[0] == _crc32c_raw(unbounded_counters[:0x3FC])

    changed_gdt = bytearray(primary_gdt)
    descriptor = bytearray(changed_gdt[:64])
    inode_table = struct.unpack_from("<I", descriptor, 0x08)[0]
    struct.pack_into("<I", descriptor, 0x08, inode_table + 1)
    descriptor = _group_descriptor_with_checksum(primary_super, descriptor, 0)
    changed_gdt[:64] = descriptor

    cleared_inode_bitmap = bytearray(inode_bitmap)
    cleared_inode_bitmap[0] &= ~0x80

    directory = tmp_path_factory.mktemp("ext4-recovery-authority")

    def author(
        name: str, blocks: tuple[int, ...], payload: bytes
    ) -> Path:
        return _author_jbd2_transactions(
            debugfs=debugfs,
            env=env,
            source=source_image,
            directory=directory,
            name=name,
            block_size=block_size,
            transactions=((blocks, payload),),
        )

    bootstrap_repair_image = author(
        "bootstrap-repair",
        (layout["primary_gdt"], layout["inode_bitmap"]),
        primary_gdt + inode_bitmap,
    )
    authority_images = {
        "backup-super": author(
            "forbidden-backup-super",
            (layout["witness_super"],),
            witness_super,
        ),
        "backup-gdt": author(
            "forbidden-backup-gdt",
            (layout["witness_gdt"],),
            witness_gdt,
        ),
        "primary-super-tuple": author(
            "forbidden-primary-super-tuple",
            (layout["primary_super"],),
            changed_tuple,
        ),
        "primary-super-orphan": author(
            "forbidden-primary-super-orphan",
            (layout["primary_super"],),
            stranded_orphan,
        ),
        "primary-super-counters": author(
            "forbidden-primary-super-counters",
            (layout["primary_super"],),
            unbounded_counters,
        ),
        "primary-gdt-locator": author(
            "forbidden-primary-gdt-locator",
            (layout["primary_gdt"],),
            bytes(changed_gdt),
        ),
        "journal-inode-bit": author(
            "forbidden-journal-inode-bit",
            (layout["inode_bitmap"],),
            bytes(cleared_inode_bitmap),
        ),
    }
    primary_super_repair_image = author(
        "primary-super-repair",
        (layout["primary_super"],),
        super_repair,
    )
    repair_map = _ext4_journal_physical_map(
        primary_super_repair_image, tuple(range(5))
    )
    with primary_super_repair_image.open("rb") as source:
        source.seek(1024)
        repair_home_super = source.read(block_size)
        source.seek(repair_map[0] * block_size)
        repair_journal_super = bytearray(source.read(block_size))
        source.seek(repair_map[1] * block_size)
        repair_descriptor = source.read(block_size)
        source.seek(repair_map[2] * block_size)
        repair_data = source.read(block_size)
        source.seek(repair_map[3] * block_size)
        repair_commit = source.read(block_size)
    assert struct.unpack_from("<I", repair_home_super, 0x60)[0] & 0x04
    assert struct.unpack_from(">II", repair_descriptor, 0x00) == (
        0xC03B3998,
        1,
    )
    assert struct.unpack_from(">II", repair_commit, 0x00) == (
        0xC03B3998,
        2,
    )
    assert struct.unpack_from(">II", repair_journal_super, 0x00) == (
        0xC03B3998,
        4,
    )
    assert struct.unpack_from(">I", repair_journal_super, 0x28)[0] == 0x12
    assert repair_journal_super[0x50] == 4
    repair_sequence = struct.unpack_from(">I", repair_commit, 0x08)[0]
    assert struct.unpack_from(">I", repair_descriptor, 0x08)[0] == repair_sequence
    assert struct.unpack_from(">I", repair_journal_super, 0x18)[0] == repair_sequence
    assert struct.unpack_from(">I", repair_journal_super, 0x1C)[0] == 1
    assert struct.unpack_from(">I", repair_descriptor, 0x0C)[0] == layout[
        "primary_super"
    ]
    assert struct.unpack_from(">I", repair_descriptor, 0x14)[0] == 0
    repair_tag_flags = struct.unpack_from(">I", repair_descriptor, 0x10)[0]
    assert repair_tag_flags & 0x08
    assert repair_tag_flags & 0x01 == 0
    assert repair_data == super_repair
    repair_journal_uuid = bytes(repair_journal_super[0x30:0x40])
    assert repair_descriptor == _jbd2_metadata_with_checksum(
        repair_descriptor, repair_journal_uuid
    )
    assert repair_commit == _jbd2_commit_with_checksum(
        repair_commit, repair_journal_uuid, repair_sequence
    )
    assert repair_commit[0x0C:0x0E] == bytes(2)
    repair_tag_seed = _crc32c_raw(repair_journal_uuid)
    repair_tag_seed = _crc32c_raw(
        struct.pack(">I", repair_sequence), repair_tag_seed
    )
    assert struct.unpack_from(">I", repair_descriptor, 0x18)[0] == _crc32c_raw(
        repair_data, repair_tag_seed
    )
    struct.pack_into(">I", repair_journal_super, 0x28, 0x13)
    struct.pack_into(">I", repair_journal_super, 0xFC, 0)
    struct.pack_into(
        ">I",
        repair_journal_super,
        0xFC,
        _crc32c_raw(repair_journal_super),
    )
    repair_super_checksum = struct.unpack_from(">I", repair_journal_super, 0xFC)[
        0
    ]
    checked_repair_super = bytearray(repair_journal_super)
    struct.pack_into(">I", checked_repair_super, 0xFC, 0)
    assert repair_super_checksum == _crc32c_raw(checked_repair_super)
    repair_revoke = bytearray(block_size)
    struct.pack_into(
        ">IIIIQ",
        repair_revoke,
        0,
        0xC03B3998,
        5,
        repair_sequence,
        24,
        layout["primary_super"],
    )
    repair_revoke = _jbd2_metadata_with_checksum(
        repair_revoke, repair_journal_uuid
    )
    assert repair_revoke == _jbd2_metadata_with_checksum(
        repair_revoke, repair_journal_uuid
    )
    assert struct.unpack_from(">IIIIQ", repair_revoke, 0x00) == (
        0xC03B3998,
        5,
        repair_sequence,
        24,
        layout["primary_super"],
    )
    revoked_primary_super_repair_image = directory / "revoked-super-repair.img"
    _copy_sparse_file(
        primary_super_repair_image, revoked_primary_super_repair_image
    )
    with revoked_primary_super_repair_image.open("r+b") as destination:
        for logical, payload in (
            (0, bytes(repair_journal_super)),
            (3, repair_revoke),
            (4, repair_commit),
        ):
            destination.seek(repair_map[logical] * block_size)
            destination.write(payload)
    return {
        "source_image": source_image,
        "layout": layout,
        "primary_gdt": primary_gdt,
        "inode_bitmap": inode_bitmap,
        "witness_super": witness_super,
        "witness_gdt": witness_gdt,
        "witness_gdt_blocks": witness_gdt_blocks,
        "bootstrap_repair_image": bootstrap_repair_image,
        "authority_images": authority_images,
        "primary_super_repair_image": primary_super_repair_image,
        "revoked_primary_super_repair_image": (
            revoked_primary_super_repair_image
        ),
        "primary_super_repair": super_repair,
    }


@pytest.fixture(scope="session")
def journal_inode_table_replay_fixture(
    canonical_images: dict[str, Path],
    jbd2_toolchain: dict[str, object],
    tmp_path_factory: pytest.TempPathFactory,
) -> dict[str, object]:
    """Author valid replay payloads that preserve or alter journal inode 8."""
    debugfs = jbd2_toolchain["debugfs"]
    env = jbd2_toolchain["env"]
    assert isinstance(debugfs, Path)
    assert isinstance(env, dict)
    source_image = canonical_images["primary-1k-i256"]
    located = subprocess.run(
        [str(debugfs), "-R", "imap <8>", str(source_image)],
        env=env,
        text=True,
        capture_output=True,
        check=False,
    )
    assert located.returncode == 0, located.stdout + located.stderr
    match = re.search(
        r"located at block\s+(\d+),\s+offset\s+0x([0-9a-fA-F]+)",
        located.stdout,
    )
    assert match, located.stdout
    inode_table_block = int(match.group(1))
    inode_offset = int(match.group(2), 16)
    inode_size = IMAGE_ROWS["primary-1k-i256"]["inode_size"]
    assert inode_offset + inode_size <= 1024
    with source_image.open("rb") as source:
        source.seek(inode_table_block * 1024)
        original_payload = source.read(1024)
    assert len(original_payload) == 1024
    directory = tmp_path_factory.mktemp("ext4-jbd2-inode-table")
    neighbor_candidate = directory / "neighbor-inode-update.img"
    _copy_sparse_file(source_image, neighbor_candidate)
    updated = subprocess.run(
        [
            str(debugfs),
            "-w",
            "-R",
            "set_inode_field <7> atime 20260101000000",
            str(neighbor_candidate),
        ],
        env=env,
        text=True,
        capture_output=True,
        check=False,
    )
    assert updated.returncode == 0, updated.stdout + updated.stderr
    with neighbor_candidate.open("rb") as source:
        source.seek(inode_table_block * 1024)
        preserved_payload = source.read(1024)
    assert preserved_payload != original_payload
    assert (
        preserved_payload[inode_offset : inode_offset + inode_size]
        == original_payload[inode_offset : inode_offset + inode_size]
    )
    altered_payload = bytearray(preserved_payload)
    altered_payload[inode_offset] ^= 0x01

    images: dict[str, Path] = {}
    for case_name, payload in (
        ("preserved", preserved_payload),
        ("altered", bytes(altered_payload)),
    ):
        image = directory / f"replay-inode-table-{case_name}.img"
        _copy_sparse_file(source_image, image)
        payload_path = directory / f"inode-table-{case_name}.bin"
        payload_path.write_bytes(payload)
        commands = directory / f"journal-inode-table-{case_name}.cmd"
        commands.write_text(
            "\n".join(
                (
                    "journal_open -c -v 3",
                    f"journal_write -b {inode_table_block} {payload_path}",
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
        images[case_name] = image
    return {
        "preserved_image": images["preserved"],
        "altered_image": images["altered"],
        "inode_table_block": inode_table_block,
        "inode_offset": inode_offset,
        "inode_size": inode_size,
        "preserved_payload": preserved_payload,
    }


@pytest.fixture(scope="session")
def large_journal_replay_fixture(
    jbd2_toolchain: dict[str, object],
    tmp_path_factory: pytest.TempPathFactory,
) -> dict[str, object]:
    """Author recovery on a real 8 MiB journal, beyond the old 4096-block pin."""
    tool_dir = jbd2_toolchain["tool_dir"]
    debugfs = jbd2_toolchain["debugfs"]
    env = jbd2_toolchain["env"]
    assert isinstance(tool_dir, Path)
    assert isinstance(debugfs, Path)
    assert isinstance(env, dict)
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
    for logical in (0, 1, 2, 3, 5000, 5001, 5002, 8190, 8191):
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
    high_slot_image = directory / "replay-csum3-64bit-j8-high.img"
    _relocate_jbd2_transaction(
        image, high_slot_image, mapped, (5000, 5001, 5002)
    )
    wraparound_image = directory / "replay-csum3-64bit-j8-wrap.img"
    _relocate_jbd2_transaction(
        image, wraparound_image, mapped, (8190, 8191, 1)
    )
    with image.open("rb") as source:
        transaction = []
        for logical in (1, 2, 3):
            source.seek(mapped[logical] * 1024)
            transaction.append(source.read(1024))
    descriptor, journal_data, first_commit = transaction
    assert all(len(block) == 1024 for block in transaction)
    first_sequence = struct.unpack_from(">I", descriptor, 0x08)[0]
    assert struct.unpack_from(">I", first_commit, 0x08)[0] == first_sequence
    second_sequence = (first_sequence + 1) & 0xFFFF_FFFF
    journal_uuid = journal_superblock[0x30:0x40]
    revoke = bytearray(1024)
    struct.pack_into(
        ">IIIIQ", revoke, 0, 0xC03B3998, 5, second_sequence, 24, 30000
    )
    revoke = _jbd2_metadata_with_checksum(revoke, journal_uuid)
    second_commit = _jbd2_commit_with_checksum(
        first_commit, journal_uuid, second_sequence
    )
    revoke_superblock = bytearray(journal_superblock)
    struct.pack_into(">I", revoke_superblock, 0x1C, 8190)
    struct.pack_into(">I", revoke_superblock, 0x28, 0x13)
    struct.pack_into(">I", revoke_superblock, 0xFC, 0)
    struct.pack_into(
        ">I", revoke_superblock, 0xFC, _crc32c_raw(revoke_superblock)
    )
    revoke_wrap_image = directory / "replay-csum3-64bit-j8-revoke-wrap.img"
    _copy_sparse_file(image, revoke_wrap_image)
    with revoke_wrap_image.open("r+b") as destination:
        for logical, block in (
            (0, bytes(revoke_superblock)),
            (8190, descriptor),
            (8191, journal_data),
            (1, first_commit),
            (2, revoke),
            (3, second_commit),
        ):
            destination.seek(mapped[logical] * 1024)
            destination.write(block)
    return {
        "image": image,
        "high_slot_image": high_slot_image,
        "wraparound_image": wraparound_image,
        "revoke_wrap_image": revoke_wrap_image,
        "payload": payload,
        "home_before": home_before,
        "target_block": 30000,
        "journal_block": mapped[0],
        "journal_tail_block": mapped[8191],
        "journal_map": mapped,
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


def test_jbd2_committed_revoke_suppresses_earlier_home_write(
    revoke_replay_fixture: dict[str, object],
    jbd2_toolchain: dict[str, object],
    tmp_path: Path,
) -> None:
    image = revoke_replay_fixture["revoked_image"]
    assert isinstance(image, Path)
    target_block = revoke_replay_fixture["target_block"]
    home_before = revoke_replay_fixture["home_before"]
    assert isinstance(target_block, int)
    assert isinstance(home_before, bytes)
    oracle = tmp_path / "revoked-e2fsck-oracle.img"
    _recover_with_e2fsck(image, oracle, jbd2_toolchain)
    with oracle.open("rb") as source:
        source.seek(target_block * 1024)
        assert source.read(1024) == home_before
    backing = tmp_path / "revoked-recovered.img"
    output, trace, _ = run_recovery_forth(
        image,
        backing,
        [
            "T-ARENA T-VOLUME EXT4-NEW CONSTANT _M-IOR CONSTANT _V",
            (
                "_M-IOR 0= _V V.LIFECYCLE @ VFS-L-MOUNTED = AND "
                "_V _EXT4-CTX _EXT4-C.J.REVOKE-COUNT + @ 1 = AND "
                "_V _EXT4-CTX _EXT4-C.J.REVOKE-HITS + @ 1 = AND "
                "_V _EXT4-CTX _EXT4-C.J.HOME-WRITES + @ 0= AND "
                'IF ." EXT4-JBD2-REVOKE-SUPPRESSED" THEN'
            ),
        ],
    )
    _assert_emitted(output, "EXT4-JBD2-REVOKE-SUPPRESSED")
    assert trace and trace[0] == ("flush", 0, 0)
    with backing.open("rb") as source:
        source.seek(target_block * 1024)
        assert source.read(1024) == home_before
    _assert_e2fsck_clean(backing, jbd2_toolchain)


def test_jbd2_later_write_replays_after_earlier_revoke(
    revoke_replay_fixture: dict[str, object],
    jbd2_toolchain: dict[str, object],
    tmp_path: Path,
) -> None:
    image = revoke_replay_fixture["rewritten_image"]
    assert isinstance(image, Path)
    target_block = revoke_replay_fixture["target_block"]
    later_payload = revoke_replay_fixture["later_payload"]
    assert isinstance(target_block, int)
    assert isinstance(later_payload, bytes)
    oracle = tmp_path / "revoke-later-e2fsck-oracle.img"
    _recover_with_e2fsck(image, oracle, jbd2_toolchain)
    with oracle.open("rb") as source:
        source.seek(target_block * 1024)
        assert source.read(1024) == later_payload
    backing = tmp_path / "revoke-later-write.img"
    output, trace, _ = run_recovery_forth(
        image,
        backing,
        [
            "T-ARENA T-VOLUME EXT4-NEW CONSTANT _M-IOR CONSTANT _V",
            (
                "_M-IOR 0= _V V.LIFECYCLE @ VFS-L-MOUNTED = AND "
                "_V _EXT4-CTX _EXT4-C.J.REVOKE-COUNT + @ 1 = AND "
                "_V _EXT4-CTX _EXT4-C.J.REVOKE-HITS + @ 1 = AND "
                "_V _EXT4-CTX _EXT4-C.J.HOME-WRITES + @ 1 = AND "
                'IF ." EXT4-JBD2-REVOKE-LATER-WRITE" THEN'
            ),
        ],
    )
    _assert_emitted(output, "EXT4-JBD2-REVOKE-LATER-WRITE")
    assert trace and trace[0] == ("write", target_block * 2, 2)
    assert trace[1] == ("flush", 0, 0)
    with backing.open("rb") as source:
        source.seek(target_block * 1024)
        assert source.read(1024) == later_payload
    _assert_e2fsck_clean(backing, jbd2_toolchain)


def test_jbd2_incomplete_revoke_does_not_suppress_committed_write(
    revoke_replay_fixture: dict[str, object],
    jbd2_toolchain: dict[str, object],
    tmp_path: Path,
) -> None:
    image = revoke_replay_fixture["incomplete_image"]
    assert isinstance(image, Path)
    target_block = revoke_replay_fixture["target_block"]
    first_payload = revoke_replay_fixture["first_payload"]
    assert isinstance(target_block, int)
    assert isinstance(first_payload, bytes)
    oracle = tmp_path / "incomplete-revoke-e2fsck-oracle.img"
    _recover_with_e2fsck(image, oracle, jbd2_toolchain)
    with oracle.open("rb") as source:
        source.seek(target_block * 1024)
        assert source.read(1024) == first_payload
    backing = tmp_path / "incomplete-revoke.img"
    output, trace, _ = run_recovery_forth(
        image,
        backing,
        [
            "T-ARENA T-VOLUME EXT4-NEW CONSTANT _M-IOR CONSTANT _V",
            (
                "_M-IOR 0= _V V.LIFECYCLE @ VFS-L-MOUNTED = AND "
                "_V _EXT4-CTX _EXT4-C.J.COMMITTED + @ 1 = AND "
                "_V _EXT4-CTX _EXT4-C.J.REVOKE-COUNT + @ 0= AND "
                "_V _EXT4-CTX _EXT4-C.J.REVOKE-HITS + @ 0= AND "
                "_V _EXT4-CTX _EXT4-C.J.HOME-WRITES + @ 1 = AND "
                'IF ." EXT4-JBD2-INCOMPLETE-REVOKE-DISCARDED" THEN'
            ),
        ],
    )
    _assert_emitted(output, "EXT4-JBD2-INCOMPLETE-REVOKE-DISCARDED")
    assert trace and trace[0] == ("write", target_block * 2, 2)
    with backing.open("rb") as source:
        source.seek(target_block * 1024)
        assert source.read(1024) == first_payload
    _assert_e2fsck_clean(backing, jbd2_toolchain)


def test_jbd2_corrupt_revoke_refuses_before_any_media_write(
    revoke_replay_fixture: dict[str, object], tmp_path: Path
) -> None:
    image = revoke_replay_fixture["corrupt_image"]
    assert isinstance(image, Path)
    output, trace, media_sha256 = run_recovery_forth(
        image,
        tmp_path / "corrupt-revoke-must-not-persist.img",
        [
            "T-ARENA T-VOLUME EXT4-NEW CONSTANT _M-IOR CONSTANT _V",
            (
                "_M-IOR VFS-IOR-REASON VFS-R-CORRUPT = "
                "_M-IOR VFS-IOR-DETAIL EXT4-D-JOURNAL = AND "
                "_V V.LIFECYCLE @ VFS-L-NEW = AND "
                'IF ." EXT4-JBD2-CORRUPT-REVOKE-NO-WRITE" THEN'
            ),
        ],
    )
    _assert_emitted(output, "EXT4-JBD2-CORRUPT-REVOKE-NO-WRITE")
    assert trace == ()
    assert media_sha256 == _sha256(image)


def test_jbd2_multi_record_revoke_probes_collisions(
    revoke_replay_fixture: dict[str, object],
    jbd2_toolchain: dict[str, object],
    tmp_path: Path,
) -> None:
    image = revoke_replay_fixture["multi_revoke_image"]
    target_block = revoke_replay_fixture["target_block"]
    home_before = revoke_replay_fixture["home_before"]
    assert isinstance(image, Path)
    assert isinstance(target_block, int)
    assert isinstance(home_before, bytes)
    oracle = tmp_path / "multi-revoke-e2fsck-oracle.img"
    _recover_with_e2fsck(image, oracle, jbd2_toolchain)
    with oracle.open("rb") as source:
        source.seek(target_block * 1024)
        assert source.read(1024) == home_before

    backing = tmp_path / "multi-revoke-collision.img"
    output, trace, _ = run_recovery_forth(
        image,
        backing,
        [
            "T-ARENA T-VOLUME EXT4-NEW CONSTANT _M-IOR CONSTANT _V",
            (
                "_M-IOR 0= _V V.LIFECYCLE @ VFS-L-MOUNTED = AND "
                "_V _EXT4-CTX _EXT4-C.J.REVOKE-COUNT + @ 2 = AND "
                "_V _EXT4-CTX _EXT4-C.J.REVOKE-SLOTS + @ 4 = AND "
                "_V _EXT4-CTX _EXT4-C.J.REVOKE-HITS + @ 1 = AND "
                "_V _EXT4-CTX _EXT4-C.J.HOME-WRITES + @ 0= AND "
                'IF ." EXT4-JBD2-MULTI-REVOKE-COLLISION" THEN'
            ),
        ],
    )
    _assert_emitted(output, "EXT4-JBD2-MULTI-REVOKE-COLLISION")
    assert trace and trace[0] == ("flush", 0, 0)
    with backing.open("rb") as source:
        source.seek(target_block * 1024)
        assert source.read(1024) == home_before
    _assert_e2fsck_clean(backing, jbd2_toolchain)


@pytest.mark.parametrize(
    "case_name",
    (
        "short-count",
        "long-count",
        "unaligned-count",
        "high-block",
        "outside-filesystem",
        "journal-owned",
    ),
)
def test_jbd2_malformed_revoke_refuses_before_any_media_write(
    revoke_replay_fixture: dict[str, object],
    tmp_path: Path,
    case_name: str,
) -> None:
    malformed_images = revoke_replay_fixture["malformed_images"]
    assert isinstance(malformed_images, dict)
    image, reason = malformed_images[case_name]
    assert isinstance(image, Path)
    assert isinstance(reason, str)
    output, trace, media_sha256 = run_recovery_forth(
        image,
        tmp_path / f"malformed-revoke-{case_name}.img",
        [
            "T-ARENA T-VOLUME EXT4-NEW CONSTANT _M-IOR CONSTANT _V",
            (
                f"_M-IOR VFS-IOR-REASON {reason} = "
                "_M-IOR VFS-IOR-DETAIL EXT4-D-JOURNAL = AND "
                "_V V.LIFECYCLE @ VFS-L-NEW = AND "
                "_V _EXT4-CTX _EXT4-C.J.HOME-WRITES + @ 0= AND "
                'IF ." EXT4-JBD2-MALFORMED-REVOKE-NO-WRITE" THEN'
            ),
        ],
    )
    _assert_emitted(output, "EXT4-JBD2-MALFORMED-REVOKE-NO-WRITE")
    assert trace == ()
    assert media_sha256 == _sha256(image)


@pytest.mark.parametrize(
    ("alias_kind", "case_name"),
    (
        ("group2-inode-table", "later-inode-table"),
        ("group3-backup-gdt", "later-sparse-gdt"),
    ),
)
def test_jbd2_tuple_map_rejects_later_metadata_alias_before_write(
    replay_fixture: dict[str, object],
    tmp_path: Path,
    alias_kind: str,
    case_name: str,
) -> None:
    image = replay_fixture["image"]
    assert isinstance(image, Path)
    layout = _ext4_recovery_layout(image)
    block_size = layout["block_size"]
    assert block_size == 1024
    media = image.read_bytes()
    primary_start = layout["primary_super"] * block_size
    primary_super = media[primary_start : primary_start + block_size]
    assert len(primary_super) == block_size

    if alias_kind == "group2-inode-table":
        group = 2
        assert group < layout["groups"]
        descriptor_start = (
            layout["witness_gdt"] * block_size
            + group * layout["descriptor_size"]
        )
        descriptor = media[
            descriptor_start : descriptor_start + layout["descriptor_size"]
        ]
        assert descriptor == _group_descriptor_with_checksum(
            primary_super, descriptor, group
        )
        inode_table_base = struct.unpack_from("<I", descriptor, 0x08)[0]
        inode_table_blocks = (
            struct.unpack_from("<I", primary_super, 0x28)[0]
            * layout["inode_size"]
            + block_size
            - 1
        ) // block_size
        assert inode_table_blocks > 1
        assert inode_table_base + inode_table_blocks <= layout["blocks"]
        target_block = inode_table_base + inode_table_blocks - 1
        assert target_block >= inode_table_base
        assert target_block != layout["journal_inode_block"]
    elif alias_kind == "group3-backup-gdt":
        group = 3
        assert group < layout["groups"]
        assert _ext4_sparse_group(group)
        backup_super_block = (
            layout["first"] + group * layout["blocks_per_group"]
        )
        target_block = backup_super_block + 1
        backup_super_start = backup_super_block * block_size
        backup_super = media[
            backup_super_start : backup_super_start + block_size
        ]
        assert len(backup_super) == block_size
        assert struct.unpack_from("<H", backup_super, 0x5A)[0] == group
        assert struct.unpack_from("<I", backup_super, 0x3FC)[0] == (
            _crc32c_raw(backup_super[:0x3FC])
        )
        target_start = target_block * block_size
        backup_descriptor = media[
            target_start : target_start + layout["descriptor_size"]
        ]
        assert backup_descriptor == _group_descriptor_with_checksum(
            backup_super, backup_descriptor, 0
        )
    else:
        raise AssertionError(f"unknown journal alias case {alias_kind}")

    assert target_block not in {
        layout["primary_super"],
        layout["primary_gdt"],
        layout["witness_super"],
        layout["witness_gdt"],
        layout["block_bitmap"],
        layout["inode_bitmap"],
        layout["journal_inode_block"],
    }
    patches, expected_sha256 = _journal_metadata_alias_patches(
        image, target_block
    )
    assert expected_sha256 != hashlib.sha256(media).hexdigest()

    output, trace, media_sha256 = run_recovery_forth(
        image,
        tmp_path / f"journal-map-alias-{case_name}.img",
        [
            "T-ARENA T-VOLUME EXT4-NEW CONSTANT _M-IOR CONSTANT _V",
            (
                "_M-IOR VFS-IOR-REASON VFS-R-CORRUPT = "
                "_M-IOR VFS-IOR-DETAIL EXT4-D-JOURNAL = AND "
                "_V V.LIFECYCLE @ VFS-L-NEW = AND "
                "_V _EXT4-CTX _EXT4-C.J.HOME-WRITES + @ 0= AND "
                "_V _EXT4-CTX _EXT4-C.J.REPLAYED + @ 0= AND "
                'IF ." EXT4-JBD2-METADATA-ALIAS-REJECTED" THEN'
            ),
        ],
        patches=patches,
    )
    _assert_emitted(output, "EXT4-JBD2-METADATA-ALIAS-REJECTED")
    assert trace == ()
    assert media_sha256 == expected_sha256


def test_jbd2_torn_primary_requires_committed_super_repair(
    replay_fixture: dict[str, object], tmp_path: Path
) -> None:
    image = replay_fixture["image"]
    assert isinstance(image, Path)
    checksum_byte = 1024 + 0x3FC
    with image.open("rb") as source:
        source.seek(checksum_byte)
        replacement = bytes((source.read(1)[0] ^ 1,))
    patched = bytearray(image.read_bytes())
    patched[checksum_byte : checksum_byte + 1] = replacement

    output, trace, media_sha256 = run_recovery_forth(
        image,
        tmp_path / "unproven-super-repair.img",
        [
            "T-ARENA T-VOLUME EXT4-NEW CONSTANT _M-IOR CONSTANT _V",
            (
                "_M-IOR VFS-IOR-REASON VFS-R-CORRUPT = "
                "_M-IOR VFS-IOR-DETAIL EXT4-D-SUPER-CHECKSUM = AND "
                "_V V.LIFECYCLE @ VFS-L-NEW = AND "
                "_V _EXT4-CTX _EXT4-C.J.HOME-WRITES + @ 0= AND "
                'IF ." EXT4-JBD2-SUPER-REPAIR-UNPROVEN" THEN'
            ),
        ],
        patches=((checksum_byte, replacement),),
    )
    _assert_emitted(output, "EXT4-JBD2-SUPER-REPAIR-UNPROVEN")
    assert trace == ()
    assert media_sha256 == hashlib.sha256(patched).hexdigest()


def test_jbd2_recovery_rejects_checksum_valid_journal_backup_mismatch(
    replay_fixture: dict[str, object], tmp_path: Path
) -> None:
    image = replay_fixture["image"]
    assert isinstance(image, Path)
    output, trace, _ = run_recovery_forth(
        image,
        tmp_path / "refused-journal-backup-mismatch.img",
        [
            "T-ARENA T-VOLUME EXT4-NEW CONSTANT _M-IOR CONSTANT _V",
            (
                "_M-IOR VFS-IOR-REASON . _M-IOR VFS-IOR-DETAIL . "
                "_V V.LIFECYCLE @ ."
            ),
        ],
        patches=((1024, _super_with_xor(image, 0x10C + 20)),),
    )
    assert "10 12 0" in output, output[-1500:]
    assert trace == ()


@pytest.mark.parametrize(
    ("witness_field", "field_offset", "detail"),
    (
        ("witness_super", 0x3FC, 9),
        ("witness_gdt", 0x1E, 6),
    ),
)
def test_dirty_recovery_requires_checksum_valid_sparse_witness(
    replay_fixture: dict[str, object],
    tmp_path: Path,
    witness_field: str,
    field_offset: int,
    detail: int,
) -> None:
    image = replay_fixture["image"]
    assert isinstance(image, Path)
    layout = _ext4_recovery_layout(image)
    offset = layout[witness_field] * layout["block_size"] + field_offset
    with image.open("rb") as source:
        source.seek(offset)
        replacement = bytes((source.read(1)[0] ^ 1,))
    patched = bytearray(image.read_bytes())
    patched[offset : offset + 1] = replacement
    output, trace, media_sha256 = run_recovery_forth(
        image,
        tmp_path / f"corrupt-{witness_field}.img",
        [
            "T-ARENA T-VOLUME EXT4-NEW CONSTANT _M-IOR CONSTANT _V",
            (
                "_M-IOR VFS-IOR-REASON VFS-R-CORRUPT = "
                f"_M-IOR VFS-IOR-DETAIL {detail} = AND "
                "_V V.LIFECYCLE @ VFS-L-NEW = AND "
                'IF ." EXT4-SPARSE-WITNESS-REQUIRED" THEN'
            ),
        ],
        patches=((offset, replacement),),
    )
    _assert_emitted(output, "EXT4-SPARSE-WITNESS-REQUIRED")
    assert trace == ()
    assert media_sha256 == hashlib.sha256(patched).hexdigest()


def test_jbd2_sparse_witness_bootstraps_primary_metadata_repairs(
    recovery_authority_fixture: dict[str, object], tmp_path: Path
) -> None:
    image = recovery_authority_fixture["bootstrap_repair_image"]
    layout = recovery_authority_fixture["layout"]
    primary_gdt = recovery_authority_fixture["primary_gdt"]
    inode_bitmap = recovery_authority_fixture["inode_bitmap"]
    witness_super = recovery_authority_fixture["witness_super"]
    witness_gdt_blocks = recovery_authority_fixture["witness_gdt_blocks"]
    assert isinstance(image, Path)
    assert isinstance(layout, dict)
    assert isinstance(primary_gdt, bytes)
    assert isinstance(inode_bitmap, bytes)
    assert isinstance(witness_super, bytes)
    assert isinstance(witness_gdt_blocks, bytes)
    block_size = layout["block_size"]
    gdt_checksum = layout["primary_gdt"] * block_size + 0x1E
    inode_bitmap_byte = layout["inode_bitmap"] * block_size + 2
    with image.open("rb") as source:
        source.seek(layout["primary_super"] * block_size)
        dirty_super = source.read(block_size)
        source.seek(layout["primary_gdt"] * block_size)
        dirty_gdt = bytearray(source.read(block_size))
        source.seek(layout["inode_bitmap"] * block_size)
        dirty_inode_bitmap = bytearray(source.read(block_size))
        source.seek(gdt_checksum)
        gdt_replacement = bytes((source.read(1)[0] ^ 1,))
        source.seek(inode_bitmap_byte)
        bitmap_replacement = bytes((source.read(1)[0] ^ 1,))
    assert len(dirty_super) == block_size
    assert primary_gdt[:64] == _group_descriptor_with_checksum(
        dirty_super, primary_gdt[:64], 0
    )
    dirty_gdt[0x1E] = gdt_replacement[0]
    assert bytes(dirty_gdt[:64]) != _group_descriptor_with_checksum(
        dirty_super, dirty_gdt[:64], 0
    )
    assert dirty_inode_bitmap[0] & 0x80
    dirty_inode_bitmap[2] = bitmap_replacement[0]
    checksum_seed = struct.unpack_from("<I", dirty_super, 0x270)[0]
    inode_bitmap_bytes = struct.unpack_from("<I", dirty_super, 0x28)[0] // 8
    stored_inode_bitmap_checksum = (
        struct.unpack_from("<H", primary_gdt, 0x1A)[0]
        | struct.unpack_from("<H", primary_gdt, 0x3A)[0] << 16
    )
    assert (
        _crc32c_raw(inode_bitmap[:inode_bitmap_bytes], checksum_seed)
        == stored_inode_bitmap_checksum
    )
    assert (
        _crc32c_raw(dirty_inode_bitmap[:inode_bitmap_bytes], checksum_seed)
        != stored_inode_bitmap_checksum
    )

    backing = tmp_path / "sparse-witness-bootstrap-repaired.img"
    output, trace, media_sha256 = run_recovery_forth(
        image,
        backing,
        [
            "T-ARENA T-VOLUME EXT4-NEW CONSTANT _M-IOR CONSTANT _V",
            (
                "_M-IOR 0= _V V.LIFECYCLE @ VFS-L-MOUNTED = AND "
                "_V _EXT4-CTX _EXT4-C.J.HOME-WRITES + @ 2 = AND "
                "_V _EXT4-CTX _EXT4-C.J.REPLAYED + @ 0<> AND "
                'IF ." EXT4-SPARSE-WITNESS-BOOTSTRAP-OK" THEN'
            ),
        ],
        patches=(
            (gdt_checksum, gdt_replacement),
            (inode_bitmap_byte, bitmap_replacement),
        ),
    )
    _assert_emitted(output, "EXT4-SPARSE-WITNESS-BOOTSTRAP-OK")
    assert trace[:3] == (
        ("write", layout["primary_gdt"] * 2, 2),
        ("write", layout["inode_bitmap"] * 2, 2),
        ("flush", 0, 0),
    )
    assert backing.is_file()
    assert _sha256(backing) == media_sha256
    with backing.open("rb") as source:
        source.seek(layout["primary_gdt"] * block_size)
        assert source.read(block_size) == primary_gdt
        source.seek(layout["inode_bitmap"] * block_size)
        assert source.read(block_size) == inode_bitmap
        source.seek(layout["witness_super"] * block_size)
        assert source.read(block_size) == witness_super
        source.seek(layout["witness_gdt"] * block_size)
        assert source.read(len(witness_gdt_blocks)) == witness_gdt_blocks


@pytest.mark.parametrize(
    "case_name",
    (
        "backup-super",
        "backup-gdt",
        "primary-super-tuple",
        "primary-super-orphan",
        "primary-super-counters",
        "primary-gdt-locator",
        "journal-inode-bit",
    ),
)
def test_jbd2_preflight_freezes_recovery_authority(
    recovery_authority_fixture: dict[str, object],
    tmp_path: Path,
    case_name: str,
) -> None:
    authority_images = recovery_authority_fixture["authority_images"]
    assert isinstance(authority_images, dict)
    image = authority_images[case_name]
    assert isinstance(image, Path)
    output, trace, media_sha256 = run_recovery_forth(
        image,
        tmp_path / f"refused-{case_name}.img",
        [
            "T-ARENA T-VOLUME EXT4-NEW CONSTANT _M-IOR CONSTANT _V",
            (
                "_M-IOR VFS-IOR-REASON VFS-R-CORRUPT = "
                "_M-IOR VFS-IOR-DETAIL EXT4-D-JOURNAL = AND "
                "_V V.LIFECYCLE @ VFS-L-NEW = AND "
                "_V _EXT4-CTX _EXT4-C.J.HOME-WRITES + @ 0= AND "
                'IF ." EXT4-RECOVERY-AUTHORITY-FROZEN" THEN'
            ),
        ],
    )
    _assert_emitted(output, "EXT4-RECOVERY-AUTHORITY-FROZEN")
    assert trace == ()
    assert media_sha256 == _sha256(image)


def test_jbd2_committed_primary_super_payload_repairs_prefix_tear(
    recovery_authority_fixture: dict[str, object], tmp_path: Path
) -> None:
    image = recovery_authority_fixture["primary_super_repair_image"]
    candidate = recovery_authority_fixture["primary_super_repair"]
    layout = recovery_authority_fixture["layout"]
    assert isinstance(image, Path)
    assert isinstance(candidate, bytes)
    assert isinstance(layout, dict)
    block_size = layout["block_size"]
    primary_offset = layout["primary_super"] * block_size
    with image.open("rb") as source:
        source.seek(primary_offset)
        torn = bytearray(source.read(block_size))
    torn[:0x34] = candidate[:0x34]
    assert struct.unpack_from("<I", torn, 0x3FC)[0] != _crc32c_raw(torn[:0x3FC])

    backing = tmp_path / "committed-primary-super-repaired.img"
    output, trace, media_sha256 = run_recovery_forth(
        image,
        backing,
        [
            "T-ARENA T-VOLUME EXT4-NEW CONSTANT _M-IOR CONSTANT _V",
            (
                "_M-IOR 0= _V V.LIFECYCLE @ VFS-L-MOUNTED = AND "
                "_V _EXT4-CTX _EXT4-C.J.HOME-WRITES + @ 1 = AND "
                "_V _EXT4-CTX _EXT4-C.J.REPLAYED + @ 0<> AND "
                'IF ." EXT4-COMMITTED-SUPER-REPAIR-OK" THEN'
            ),
        ],
        patches=((primary_offset, bytes(torn)),),
    )
    _assert_emitted(output, "EXT4-COMMITTED-SUPER-REPAIR-OK")
    assert trace[0] == ("write", layout["primary_super"] * 2, 2)
    assert backing.is_file()
    assert _sha256(backing) == media_sha256
    with backing.open("rb") as source:
        source.seek(primary_offset)
        repaired = source.read(block_size)
    assert struct.unpack_from("<I", repaired, 0x30)[0] == struct.unpack_from(
        "<I", candidate, 0x30
    )[0]
    assert struct.unpack_from("<I", repaired, 0x60)[0] & 0x04 == 0
    assert struct.unpack_from("<I", repaired, 0x3FC)[0] == _crc32c_raw(
        repaired[:0x3FC]
    )


def test_jbd2_revoked_primary_super_payload_grants_no_repair_authority(
    recovery_authority_fixture: dict[str, object], tmp_path: Path
) -> None:
    image = recovery_authority_fixture["revoked_primary_super_repair_image"]
    candidate = recovery_authority_fixture["primary_super_repair"]
    layout = recovery_authority_fixture["layout"]
    assert isinstance(image, Path)
    assert isinstance(candidate, bytes)
    assert isinstance(layout, dict)
    block_size = layout["block_size"]
    primary_offset = layout["primary_super"] * block_size
    with image.open("rb") as source:
        source.seek(primary_offset)
        torn = bytearray(source.read(block_size))
    torn[:0x34] = candidate[:0x34]
    assert struct.unpack_from("<I", torn, 0x3FC)[0] != _crc32c_raw(
        torn[:0x3FC]
    )
    patched = bytearray(image.read_bytes())
    patched[primary_offset : primary_offset + block_size] = torn

    output, trace, media_sha256 = run_recovery_forth(
        image,
        tmp_path / "revoked-primary-super-repair.img",
        [
            "T-ARENA T-VOLUME EXT4-NEW CONSTANT _M-IOR CONSTANT _V",
            (
                "_M-IOR VFS-IOR-REASON VFS-R-CORRUPT = "
                "_M-IOR VFS-IOR-DETAIL EXT4-D-SUPER-CHECKSUM = AND "
                "_V V.LIFECYCLE @ VFS-L-NEW = AND "
                "_V _EXT4-CTX _EXT4-C.J.REVOKE-COUNT + @ 1 = AND "
                "_V _EXT4-CTX _EXT4-C.J.HOME-WRITES + @ 0= AND "
                "_V _EXT4-CTX _EXT4-C.J.REVOKE-READY + @ 0= AND "
                'IF ." EXT4-REVOKED-SUPER-REPAIR-UNPROVEN" THEN'
            ),
        ],
        patches=((primary_offset, bytes(torn)),),
    )
    _assert_emitted(output, "EXT4-REVOKED-SUPER-REPAIR-UNPROVEN")
    assert trace == ()
    assert media_sha256 == hashlib.sha256(patched).hexdigest()


def test_jbd2_incomplete_primary_super_payload_grants_no_repair_authority(
    recovery_authority_fixture: dict[str, object], tmp_path: Path
) -> None:
    image = recovery_authority_fixture["primary_super_repair_image"]
    candidate = recovery_authority_fixture["primary_super_repair"]
    layout = recovery_authority_fixture["layout"]
    assert isinstance(image, Path)
    assert isinstance(candidate, bytes)
    assert isinstance(layout, dict)
    block_size = layout["block_size"]
    primary_offset = layout["primary_super"] * block_size
    with image.open("rb") as source:
        source.seek(primary_offset)
        torn = bytearray(source.read(block_size))
    torn[:0x34] = candidate[:0x34]
    commit_magic = layout["journal_commit_block"] * block_size
    patched = bytearray(image.read_bytes())
    assert struct.unpack_from(">I", patched, commit_magic)[0] == 0xC03B3998
    assert struct.unpack_from(">I", patched, commit_magic + 4)[0] == 2
    patched[primary_offset : primary_offset + block_size] = torn
    patched[commit_magic : commit_magic + 4] = bytes(4)

    output, trace, media_sha256 = run_recovery_forth(
        image,
        tmp_path / "incomplete-primary-super-repair.img",
        [
            "T-ARENA T-VOLUME EXT4-NEW CONSTANT _M-IOR CONSTANT _V",
            (
                "_M-IOR VFS-IOR-REASON VFS-R-CORRUPT = "
                "_M-IOR VFS-IOR-DETAIL EXT4-D-SUPER-CHECKSUM = AND "
                "_V V.LIFECYCLE @ VFS-L-NEW = AND "
                "_V _EXT4-CTX _EXT4-C.J.HOME-WRITES + @ 0= AND "
                'IF ." EXT4-INCOMPLETE-SUPER-REPAIR-UNPROVEN" THEN'
            ),
        ],
        patches=(
            (primary_offset, bytes(torn)),
            (commit_magic, bytes(4)),
        ),
    )
    _assert_emitted(output, "EXT4-INCOMPLETE-SUPER-REPAIR-UNPROVEN")
    assert trace == ()
    assert media_sha256 == hashlib.sha256(patched).hexdigest()


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


@pytest.mark.parametrize(
    ("image_key", "expected_start", "case_name"),
    (
        ("high_slot_image", 5000, "high"),
        ("wraparound_image", 8190, "wrap"),
    ),
)
def test_jbd2_replay_scans_high_slots_and_wraps_at_ring_end(
    large_journal_replay_fixture: dict[str, object],
    tmp_path: Path,
    image_key: str,
    expected_start: int,
    case_name: str,
) -> None:
    image = large_journal_replay_fixture[image_key]
    payload = large_journal_replay_fixture["payload"]
    target_block = large_journal_replay_fixture["target_block"]
    journal_map = large_journal_replay_fixture["journal_map"]
    assert isinstance(image, Path)
    assert isinstance(payload, bytes)
    assert isinstance(target_block, int)
    assert isinstance(journal_map, dict)
    with image.open("rb") as source:
        source.seek(journal_map[0] * 1024)
        journal_superblock = source.read(1024)
    assert struct.unpack_from(">I", journal_superblock, 0x1C)[0] == expected_start

    backing = tmp_path / f"recovered-j8-{case_name}.img"
    output, trace, _ = run_recovery_forth(
        image,
        backing,
        [
            "T-ARENA T-VOLUME EXT4-NEW CONSTANT _M-IOR CONSTANT _V",
            (
                "_M-IOR 0= _V V.LIFECYCLE @ VFS-L-MOUNTED = AND "
                "_V _EXT4-CTX _EXT4-C.J.REPLAYED + @ 0<> AND "
                "_V _EXT4-CTX _EXT4-C.J.HOME-WRITES + @ 1 = AND "
                "_V _EXT4-CTX _EXT4-C.J.MAXLEN + @ 8192 = AND "
                'IF ." EXT4-JBD2-J8-RING-REPLAY-OK" THEN'
            ),
        ],
    )
    _assert_emitted(output, "EXT4-JBD2-J8-RING-REPLAY-OK")
    assert ("write", target_block * 2, 2) in trace
    with backing.open("rb") as source:
        source.seek(target_block * 1024)
        assert source.read(1024) == payload


def test_jbd2_revoke_scan_wraps_across_large_journal_ring(
    large_journal_replay_fixture: dict[str, object],
    jbd2_toolchain: dict[str, object],
    tmp_path: Path,
) -> None:
    image = large_journal_replay_fixture["revoke_wrap_image"]
    target_block = large_journal_replay_fixture["target_block"]
    home_before = large_journal_replay_fixture["home_before"]
    journal_map = large_journal_replay_fixture["journal_map"]
    assert isinstance(image, Path)
    assert isinstance(target_block, int)
    assert isinstance(home_before, bytes)
    assert isinstance(journal_map, dict)
    with image.open("rb") as source:
        source.seek(journal_map[0] * 1024)
        journal_superblock = source.read(1024)
    assert struct.unpack_from(">I", journal_superblock, 0x1C)[0] == 8190
    assert struct.unpack_from(">I", journal_superblock, 0x28)[0] == 0x13
    oracle = tmp_path / "j8-revoke-wrap-e2fsck-oracle.img"
    _recover_with_e2fsck(image, oracle, jbd2_toolchain)
    with oracle.open("rb") as source:
        source.seek(target_block * 1024)
        assert source.read(1024) == home_before

    backing = tmp_path / "recovered-j8-revoke-wrap.img"
    output, trace, _ = run_recovery_forth(
        image,
        backing,
        [
            "T-ARENA T-VOLUME EXT4-NEW CONSTANT _M-IOR CONSTANT _V",
            (
                "_M-IOR 0= _V V.LIFECYCLE @ VFS-L-MOUNTED = AND "
                "_V _EXT4-CTX _EXT4-C.J.MAXLEN + @ 8192 = AND "
                "_V _EXT4-CTX _EXT4-C.J.COMMITTED + @ 2 = AND "
                "_V _EXT4-CTX _EXT4-C.J.REVOKE-COUNT + @ 1 = AND "
                "_V _EXT4-CTX _EXT4-C.J.REVOKE-HITS + @ 1 = AND "
                "_V _EXT4-CTX _EXT4-C.J.HOME-WRITES + @ 0= AND "
                "_V _EXT4-CTX _EXT4-C.J.CURSOR + @ 4 = AND "
                'IF ." EXT4-JBD2-J8-REVOKE-WRAP" THEN'
            ),
        ],
    )
    _assert_emitted(output, "EXT4-JBD2-J8-REVOKE-WRAP")
    assert trace and trace[0] == ("flush", 0, 0)
    with backing.open("rb") as source:
        source.seek(target_block * 1024)
        assert source.read(1024) == home_before
    _assert_e2fsck_clean(backing, jbd2_toolchain)


def test_jbd2_replay_allows_shared_inode_table_when_inode_8_is_preserved(
    journal_inode_table_replay_fixture: dict[str, object], tmp_path: Path
) -> None:
    image = journal_inode_table_replay_fixture["preserved_image"]
    inode_table_block = journal_inode_table_replay_fixture["inode_table_block"]
    preserved_payload = journal_inode_table_replay_fixture["preserved_payload"]
    assert isinstance(image, Path)
    assert isinstance(inode_table_block, int)
    assert isinstance(preserved_payload, bytes)
    backing = tmp_path / "recovered-inode-table-preserved.img"
    output, trace, _ = run_recovery_forth(
        image,
        backing,
        [
            "T-ARENA T-VOLUME EXT4-NEW CONSTANT _M-IOR CONSTANT _V",
            (
                "_M-IOR 0= _V V.LIFECYCLE @ VFS-L-MOUNTED = AND "
                "_V _EXT4-CTX _EXT4-C.J.REPLAYED + @ 0<> AND "
                "_V _EXT4-CTX _EXT4-C.J.HOME-WRITES + @ 1 = AND "
                'IF ." EXT4-JBD2-INODE-TABLE-PRESERVED" THEN'
            ),
        ],
    )
    _assert_emitted(output, "EXT4-JBD2-INODE-TABLE-PRESERVED")
    assert ("write", inode_table_block * 2, 2) in trace
    with backing.open("rb") as source:
        source.seek(inode_table_block * 1024)
        assert source.read(1024) == preserved_payload


def test_jbd2_preflight_rejects_journal_inode_rewrite_before_any_write(
    journal_inode_table_replay_fixture: dict[str, object], tmp_path: Path
) -> None:
    image = journal_inode_table_replay_fixture["altered_image"]
    assert isinstance(image, Path)
    output, trace, media_sha256 = run_recovery_forth(
        image,
        tmp_path / "refused-inode-table-altered.img",
        [
            "T-ARENA T-VOLUME EXT4-NEW CONSTANT _M-IOR CONSTANT _V",
            (
                "_M-IOR VFS-IOR-REASON VFS-R-CORRUPT = "
                "_M-IOR VFS-IOR-DETAIL EXT4-D-JOURNAL = AND "
                "_V V.LIFECYCLE @ VFS-L-NEW = AND "
                "_V _EXT4-READY? 0= AND "
                'IF ." EXT4-JBD2-INODE-REWRITE-REFUSED" THEN'
            ),
        ],
    )
    _assert_emitted(output, "EXT4-JBD2-INODE-REWRITE-REFUSED")
    assert trace == ()
    assert media_sha256 == _sha256(image)


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


def test_jbd2_revoke_workspace_is_arena_derived_and_wrap_aware(
    tmp_path: Path,
) -> None:
    blank = tmp_path / "revoke-workspace.img"
    blank.write_bytes(bytes(4 * 512))
    output = run_forth(
        blank,
        [
            "CREATE _E4-RCTX _EXT4-CTX-SIZE ALLOT",
            "_E4-RCTX _EXT4-CTX-SIZE 0 FILL",
            "1000 _E4-RCTX _EXT4-C.BLOCKS + !",
            (
                "8 2* CELLS 2 CELLS + A-XMEM ARENA-NEW "
                "THROW CONSTANT _E4-R-ARENA"
            ),
            "_E4-R-ARENA _E4-RCTX _EXT4-C.ARENA + !",
            (
                "3 _E4-RCTX _EXT4-ENSURE-REVOKE-WORKSPACE "
                "CONSTANT _E4-R-IOR"
            ),
            "42 0xFFFFFFFF _E4-RCTX _EXT4-REVOKE-PUT CONSTANT _E4-R-P1",
            "42 0 _E4-RCTX _EXT4-REVOKE-PUT CONSTANT _E4-R-P2",
            "43 5 _E4-RCTX _EXT4-REVOKE-PUT CONSTANT _E4-R-P3",
            "42 0xFFFFFFFF _E4-RCTX _EXT4-JOURNAL-REVOKED? CONSTANT _E4-R-A",
            "42 0 _E4-RCTX _EXT4-JOURNAL-REVOKED? CONSTANT _E4-R-B",
            "42 1 _E4-RCTX _EXT4-JOURNAL-REVOKED? 0= CONSTANT _E4-R-C",
            "43 4 _E4-RCTX _EXT4-JOURNAL-REVOKED? CONSTANT _E4-R-D",
            "43 6 _E4-RCTX _EXT4-JOURNAL-REVOKED? 0= CONSTANT _E4-R-E",
            (
                "0 0xFFFFFFFF _EXT4-JOURNAL-TID-AFTER? "
                "0xFFFFFFFF 0 _EXT4-JOURNAL-TID-AFTER? 0= AND "
                "CONSTANT _E4-R-WRAP"
            ),
            (
                "_E4-R-IOR 0= _E4-RCTX _EXT4-C.J.REVOKE-SLOTS + @ 8 = AND "
                "_E4-R-P1 0= AND _E4-R-P2 0= AND _E4-R-P3 0= AND "
                "_E4-R-A AND _E4-R-B AND _E4-R-C AND "
                "_E4-R-D AND _E4-R-E AND _E4-R-WRAP AND "
                'IF ." EXT4-REVOKE-WORKSPACE-OK" THEN'
            ),
            "_E4-RCTX _EXT4-C.J.REVOKE-TABLE + @ CONSTANT _E4-R-PTR",
            "_E4-R-ARENA ARENA-USED CONSTANT _E4-R-USED",
            (
                "2 _E4-RCTX _EXT4-ENSURE-REVOKE-WORKSPACE "
                "CONSTANT _E4-R-REUSE-IOR"
            ),
            (
                "42 0 _E4-RCTX _EXT4-JOURNAL-REVOKED? 0= "
                "CONSTANT _E4-R-CLEARED"
            ),
            (
                "_EXT4-JSCAN-REPLAY _E4-RCTX _EXT4-JSCAN "
                "CONSTANT _E4-R-NOT-READY"
            ),
            (
                "_E4-R-REUSE-IOR 0= _E4-R-CLEARED AND "
                "_E4-RCTX _EXT4-C.J.REVOKE-TABLE + @ _E4-R-PTR = AND "
                "_E4-RCTX _EXT4-C.J.REVOKE-SLOTS + @ 8 = AND "
                "_E4-R-ARENA ARENA-USED _E4-R-USED = AND "
                "_E4-RCTX _EXT4-C.J.REVOKE-READY + @ 0= AND "
                "_E4-R-NOT-READY VFS-IOR-REASON VFS-R-CORRUPT = AND "
                "_E4-R-NOT-READY VFS-IOR-DETAIL EXT4-D-JOURNAL = AND "
                'IF ." EXT4-REVOKE-WORKSPACE-REUSED" THEN'
            ),
            (
                "5 _E4-RCTX _EXT4-ENSURE-REVOKE-WORKSPACE "
                "CONSTANT _E4-R-GROW-IOR"
            ),
            (
                "_E4-R-GROW-IOR VFS-E-NOMEM = "
                "_E4-RCTX _EXT4-C.J.REVOKE-TABLE + @ _E4-R-PTR = AND "
                "_E4-RCTX _EXT4-C.J.REVOKE-SLOTS + @ 8 = AND "
                "_E4-R-ARENA ARENA-USED _E4-R-USED = AND "
                "_E4-RCTX _EXT4-C.J.REVOKE-READY + @ 0= AND "
                'IF ." EXT4-REVOKE-WORKSPACE-GROWTH-REFUSED" THEN'
            ),
            "CREATE _E4-RNCTX _EXT4-CTX-SIZE ALLOT",
            "_E4-RNCTX _EXT4-CTX-SIZE 0 FILL",
            (
                "16 2* CELLS 1 CELLS - A-XMEM ARENA-NEW "
                "THROW CONSTANT _E4-RN-ARENA"
            ),
            (
                "_E4-RN-ARENA _E4-RNCTX _EXT4-C.ARENA + ! "
                "_E4-RN-ARENA ARENA-USED CONSTANT _E4-RN-BEFORE"
            ),
            (
                "5 _E4-RNCTX _EXT4-ENSURE-REVOKE-WORKSPACE "
                "CONSTANT _E4-RN-IOR"
            ),
            "_E4-RN-ARENA ARENA-USED CONSTANT _E4-RN-AFTER",
            (
                "_E4-RN-IOR VFS-E-NOMEM = "
                "_E4-RN-BEFORE _E4-RN-AFTER = AND "
                "_E4-RNCTX _EXT4-C.J.REVOKE-TABLE + @ 0= AND "
                "_E4-RNCTX _EXT4-C.J.REVOKE-SLOTS + @ 0= AND "
                'IF ." EXT4-REVOKE-WORKSPACE-NOMEM" THEN'
            ),
            "CREATE _E4-RGCTX _EXT4-CTX-SIZE ALLOT",
            "_E4-RGCTX _EXT4-CTX-SIZE 0 FILL",
            "1 _E4-RGCTX _EXT4-C.J.REVOKE-TABLE + !",
            (
                "1 _E4-RGCTX _EXT4-ENSURE-REVOKE-WORKSPACE "
                "CONSTANT _E4-RG-IOR"
            ),
            (
                "_E4-RG-IOR VFS-IOR-REASON VFS-R-CORRUPT = "
                "_E4-RG-IOR VFS-IOR-DETAIL EXT4-D-JOURNAL = AND "
                "_E4-RGCTX _EXT4-C.J.REVOKE-READY + @ 0= AND "
                'IF ." EXT4-REVOKE-WORKSPACE-GEOMETRY" THEN'
            ),
        ],
    )
    _assert_emitted(output, "EXT4-REVOKE-WORKSPACE-OK")
    _assert_emitted(output, "EXT4-REVOKE-WORKSPACE-REUSED")
    _assert_emitted(output, "EXT4-REVOKE-WORKSPACE-GROWTH-REFUSED")
    _assert_emitted(output, "EXT4-REVOKE-WORKSPACE-NOMEM")
    _assert_emitted(output, "EXT4-REVOKE-WORKSPACE-GEOMETRY")


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
            "1000 _E4CTX _EXT4-C.BLOCKS + !",
            "12 _E4CTX _EXT4-C.J.MAXLEN + !",
            (
                "_E4CTX _EXT4-C.J.WITNESS-SUPER + "
                "_EXT4-SB.JOURNAL-BLOCKS + CONSTANT _E4-JOURNAL-ROOT"
            ),
            "_E4-JOURNAL-ROOT 60 0 FILL",
            "_EXT4-EXTENT-MAGIC _E4-JOURNAL-ROOT W!",
            "1 _E4-JOURNAL-ROOT 2 + W! 4 _E4-JOURNAL-ROOT 4 + W!",
            "12 _E4-JOURNAL-ROOT 16 + W! 100 _E4-JOURNAL-ROOT 20 + L!",
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
            "100 _E4CTX _EXT4-JOURNAL-DATA? CONSTANT _LJM-HOME",
            "999 _E4CTX _EXT4-JOURNAL-DATA? 0= CONSTANT _LJM-NONHOME",
            "2 _E4-JOURNAL-ROOT 2 + W! 11 _E4-JOURNAL-ROOT 16 + W!",
            (
                "11 _E4-JOURNAL-ROOT 24 + L! "
                "1 _E4-JOURNAL-ROOT 28 + W! "
                "100 _E4-JOURNAL-ROOT 32 + L!"
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
                'IF ." EXT4-TUPLE-JOURNAL-MAP-OK" THEN'
            ),
            (
                "200 _E4CTX _EXT4-C.J.WITNESS-SUPER-BLOCK + ! "
                "201 _E4CTX _EXT4-C.J.WITNESS-GDT-BLOCK + ! "
                "2 _E4CTX _EXT4-C.J.WITNESS-GDT-SPAN + !"
            ),
            (
                "200 _E4CTX _EXT4-RECOVERY-FROZEN-BLOCK? "
                "201 _E4CTX _EXT4-RECOVERY-FROZEN-BLOCK? AND "
                "202 _E4CTX _EXT4-RECOVERY-FROZEN-BLOCK? AND "
                "203 _E4CTX _EXT4-RECOVERY-FROZEN-BLOCK? 0= AND "
                'IF ." EXT4-RECOVERY-AUTHORITY-SPAN-OK" THEN'
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
                'IF ." EXT4-JOURNAL-WORKSPACE-NOMEM" THEN'
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
        ],
    )
    _assert_emitted(output, "EXT4-PARSER-TOTAL-OK")
    _assert_emitted(output, "EXT4-HUGE-BLOCKS-OK")
    _assert_emitted(output, "EXT4-TIMESTAMP-SIGN-OK")
    _assert_emitted(output, "EXT4-TUPLE-JOURNAL-MAP-OK")
    _assert_emitted(output, "EXT4-RECOVERY-AUTHORITY-SPAN-OK")
    _assert_emitted(output, "EXT4-JOURNAL-WORKSPACE-NOMEM")
    _assert_emitted(output, "EXT4-JOURNAL-EXTENT-EOF-BOUND-OK")


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
def test_canonical_images_publish_journal_recovery_authority(
    canonical_images: dict[str, Path], image_id: str
) -> None:
    observed = ext4_fixture_generator.read_superblock(canonical_images[image_id])
    ext4_fixture_generator.validate_observed_superblock(
        PROFILE, IMAGE_ROWS[image_id], observed
    )


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


def test_journal_backup_root_rejects_non_authoritative_shapes(
    canonical_images: dict[str, Path],
) -> None:
    path = canonical_images["primary-1k-i256"]
    output = run_forth(
        path,
        [
            "CREATE _T-JBR-SAVED 60 ALLOT",
            "T-ARENA T-VOLUME EXT4-NEW CONSTANT _M-IOR CONSTANT _V",
            "_V _EXT4-CTX CONSTANT _T-JBR-CTX",
            (
                "_T-JBR-CTX _EXT4-C.SB + _EXT4-SB.JOURNAL-BLOCKS + "
                "CONSTANT _T-JBR-ROOT"
            ),
            "_T-JBR-ROOT _T-JBR-SAVED 60 CMOVE",
            (
                "_T-JBR-ROOT _T-JBR-CTX "
                "_EXT4-VALIDATE-JOURNAL-BACKUP-ROOT-AT 0= "
                "CONSTANT _T-JBR-GOOD"
            ),
            (
                "1 _T-JBR-ROOT 6 + W! "
                "_T-JBR-ROOT _T-JBR-CTX "
                "_EXT4-VALIDATE-JOURNAL-BACKUP-ROOT-AT 0<> "
                "CONSTANT _T-JBR-DEPTH-BAD"
            ),
            "_T-JBR-SAVED _T-JBR-ROOT 60 CMOVE",
            (
                "1 _T-JBR-ROOT 12 + L! "
                "_T-JBR-ROOT _T-JBR-CTX "
                "_EXT4-VALIDATE-JOURNAL-BACKUP-ROOT-AT 0<> "
                "CONSTANT _T-JBR-GAP-BAD"
            ),
            "_T-JBR-SAVED _T-JBR-ROOT 60 CMOVE",
            (
                "32769 _T-JBR-ROOT 16 + W! "
                "_T-JBR-ROOT _T-JBR-CTX "
                "_EXT4-VALIDATE-JOURNAL-BACKUP-ROOT-AT 0<> "
                "CONSTANT _T-JBR-UNWRITTEN-BAD"
            ),
            "_T-JBR-SAVED _T-JBR-ROOT 60 CMOVE",
            (
                "_T-JBR-CTX _EXT4-C.BLOCKS + @ _T-JBR-ROOT 20 + L! "
                "_T-JBR-ROOT _T-JBR-CTX "
                "_EXT4-VALIDATE-JOURNAL-BACKUP-ROOT-AT 0<> "
                "CONSTANT _T-JBR-BOUNDS-BAD"
            ),
            "_T-JBR-SAVED _T-JBR-ROOT 60 CMOVE",
            (
                "2 _T-JBR-ROOT 2 + W! 2048 _T-JBR-ROOT 16 + W! "
                "2048 _T-JBR-ROOT 24 + L! 2048 _T-JBR-ROOT 28 + W! "
                "0 _T-JBR-ROOT 30 + W! _T-JBR-ROOT 20 + L@ "
                "_T-JBR-ROOT 32 + L!"
            ),
            (
                "_T-JBR-ROOT _T-JBR-CTX "
                "_EXT4-VALIDATE-JOURNAL-BACKUP-ROOT-AT 0<> "
                "CONSTANT _T-JBR-ALIAS-BAD"
            ),
            (
                "_M-IOR 0= _T-JBR-GOOD AND _T-JBR-DEPTH-BAD AND "
                "_T-JBR-GAP-BAD AND _T-JBR-UNWRITTEN-BAD AND "
                "_T-JBR-BOUNDS-BAD AND _T-JBR-ALIAS-BAD AND "
                'IF ." EXT4-JOURNAL-BACKUP-ROOT-STRICT" THEN'
            ),
        ],
    )
    _assert_emitted(output, "EXT4-JOURNAL-BACKUP-ROOT-STRICT")


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


def _super_with_mask(path: Path, field_offset: int, value: int) -> bytes:
    return _super_with_bytes(path, field_offset, struct.pack("<I", value))


def _super_with_bytes(path: Path, field_offset: int, value: bytes) -> bytes:
    with path.open("rb") as source:
        source.seek(1024)
        superblock = bytearray(source.read(1024))
    assert 0 <= field_offset <= len(superblock) - len(value)
    superblock[field_offset : field_offset + len(value)] = value
    struct.pack_into("<I", superblock, 0x3FC, _crc32c_raw(superblock[:0x3FC]))
    return bytes(superblock)


def _super_with_xor(path: Path, field_offset: int, value: int = 1) -> bytes:
    with path.open("rb") as source:
        source.seek(1024 + field_offset)
        original = source.read(1)
    assert len(original) == 1
    return _super_with_bytes(path, field_offset, bytes((original[0] ^ value,)))


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


def test_checksum_valid_primary_journal_backup_disagreement_is_rejected(
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
        patches=((1024, _super_with_xor(path, 0x10C + 20)),),
    )
    assert "10 3 4 9 0" in output, output[-1500:]


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
            "7 _RETRY-CTX _EXT4-C.J.REVOKE-COUNT + !",
            "8 _RETRY-CTX _EXT4-C.J.REVOKE-HITS + !",
            "-1 _RETRY-CTX _EXT4-C.J.REVOKE-READY + !",
            "_RETRY-V _EXT4-MOUNT CONSTANT _RETRY-IOR-2",
            "_RETRY-ARENA ARENA-USED CONSTANT _RETRY-USED-2",
            (
                "_RETRY-IOR-1 VFS-IOR-DETAIL EXT4-D-ROOT-INODE = "
                "_RETRY-IOR-2 VFS-IOR-DETAIL EXT4-D-ROOT-INODE = AND "
                "_RETRY-USED-1 _RETRY-USED-2 = AND "
                "_RETRY-V _EXT4-CTX _RETRY-CTX = AND "
                "_RETRY-CTX _EXT4-C.J.MAP + @ _RETRY-MAP = AND "
                "_RETRY-CTX _EXT4-C.J.MAP-HASH + @ _RETRY-HASH = AND "
                "_RETRY-MAP 0<> AND "
                "_RETRY-CTX _EXT4-C.J.REVOKE-COUNT + @ 0= AND "
                "_RETRY-CTX _EXT4-C.J.REVOKE-HITS + @ 0= AND "
                "_RETRY-CTX _EXT4-C.J.REVOKE-READY + @ 0= AND "
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


def test_sparse_image_helpers_preserve_bytes_and_holes(tmp_path: Path) -> None:
    logical_size = 8 * (1 << 20)
    source = tmp_path / "sparse-source.img"
    with source.open("wb") as image:
        image.truncate(logical_size)
        image.seek(4096)
        image.write(b"first sparse extent")
        image.seek(logical_size - 4096)
        image.write(b"last sparse extent")

    expected = source.read_bytes()
    copied = tmp_path / "sparse-copied.img"
    _copy_sparse_file(source, copied)
    serialized = tmp_path / "sparse-serialized.img"
    _write_sparse_bytes(serialized, expected, durable=True)

    assert copied.read_bytes() == expected
    assert serialized.read_bytes() == expected
    if source.stat().st_blocks * 512 < logical_size // 4:
        assert copied.stat().st_blocks * 512 < logical_size // 4
        assert serialized.stat().st_blocks * 512 < logical_size // 4
