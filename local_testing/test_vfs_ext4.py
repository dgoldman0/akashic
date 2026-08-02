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
    STORAGE_CMD_FLUSH,
    STORAGE_CMD_READ,
    STORAGE_CMD_WRITE,
    STORAGE_RESULT_FLUSH_FAILURE,
    STORAGE_RESULT_MEDIA_FAILURE,
    STORAGE_RESULT_OK,
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


def _ext4_inode_record(path: Path, inode_number: int) -> tuple[bytes, bytes, int]:
    """Return the primary super, one inode record, and its byte offset."""
    with path.open("rb") as source:
        source.seek(1024)
        superblock = source.read(1024)
    assert len(superblock) == 1024
    assert inode_number > 0
    block_size = 1024 << struct.unpack_from("<I", superblock, 0x18)[0]
    inode_size = struct.unpack_from("<H", superblock, 0x58)[0]
    inodes_per_group = struct.unpack_from("<I", superblock, 0x28)[0]
    descriptor_size = struct.unpack_from("<H", superblock, 0xFE)[0]
    assert descriptor_size == 64
    group, index = divmod(inode_number - 1, inodes_per_group)
    descriptor_table = 2 if block_size == 1024 else 1
    with path.open("rb") as source:
        source.seek(descriptor_table * block_size + group * descriptor_size)
        descriptor = source.read(descriptor_size)
    assert len(descriptor) == descriptor_size
    inode_table = (
        struct.unpack_from("<I", descriptor, 0x28)[0] << 32
    ) | struct.unpack_from("<I", descriptor, 0x08)[0]
    inode_offset = inode_table * block_size + index * inode_size
    with path.open("rb") as source:
        source.seek(inode_offset)
        inode = source.read(inode_size)
    assert len(inode) == inode_size
    return superblock, inode, inode_offset


def _extent_root_physical(inode: bytes, logical_block: int) -> int:
    """Map one logical block through the fixture's inline depth-zero root."""
    root = inode[0x28 : 0x28 + 60]
    magic, entries, maximum, depth = struct.unpack_from("<HHHH", root, 0)
    assert magic == 0xF30A
    assert 0 < entries <= maximum <= 4
    assert depth == 0
    for index in range(entries):
        offset = 0x0C + index * 0x0C
        first_logical = struct.unpack_from("<I", root, offset)[0]
        raw_length = struct.unpack_from("<H", root, offset + 0x04)[0]
        length = raw_length - 0x8000 if raw_length > 0x8000 else raw_length
        assert length > 0
        if first_logical <= logical_block < first_logical + length:
            first_physical = (
                struct.unpack_from("<H", root, offset + 0x06)[0] << 32
            ) | struct.unpack_from("<I", root, offset + 0x08)[0]
            return first_physical + logical_block - first_logical
    raise AssertionError(f"logical block {logical_block} is unmapped")


def _modern_orphan_patches(
    path: Path,
    entries: tuple[int, ...],
    *,
    orphan_present: bool = True,
) -> tuple[tuple[int, bytes], ...]:
    """Create a checksum-valid modern orphan block and transient super state."""
    with path.open("rb") as source:
        source.seek(1024)
        superblock = bytearray(source.read(1024))
    assert len(superblock) == 1024
    orphan_inode_number = struct.unpack_from("<I", superblock, 0x280)[0]
    assert orphan_inode_number > 0
    _, orphan_inode, _ = _ext4_inode_record(path, orphan_inode_number)
    block_size = 1024 << struct.unpack_from("<I", superblock, 0x18)[0]
    orphan_physical = _extent_root_physical(orphan_inode, 0)
    with path.open("rb") as source:
        source.seek(orphan_physical * block_size)
        orphan_block = bytearray(source.read(block_size))
    assert len(orphan_block) == block_size
    assert struct.unpack_from("<I", orphan_block, block_size - 8)[0] == 0x0B10CA04
    assert not any(orphan_block[: block_size - 8])
    assert len(entries) <= (block_size - 8) // 4
    for index, inode_number in enumerate(entries):
        assert 0 < inode_number <= 0xFFFF_FFFF
        struct.pack_into("<I", orphan_block, index * 4, inode_number)

    seed = struct.unpack_from("<I", superblock, 0x270)[0]
    generation = struct.unpack_from("<I", orphan_inode, 0x64)[0]
    checksum = _crc32c_raw(
        struct.pack("<IIQ", orphan_inode_number, generation, orphan_physical),
        seed,
    )
    checksum = _crc32c_raw(orphan_block[: block_size - 8], checksum)
    struct.pack_into("<I", orphan_block, block_size - 4, checksum)

    ro_compat = struct.unpack_from("<I", superblock, 0x64)[0]
    if orphan_present:
        ro_compat |= 0x0001_0000
    else:
        ro_compat &= ~0x0001_0000
    struct.pack_into("<I", superblock, 0x64, ro_compat)
    return (
        (1024, _ext4_super_with_checksum(superblock)),
        (orphan_physical * block_size, bytes(orphan_block)),
    )


def _zero_size_depth0_orphan_patches(
    path: Path,
) -> tuple[tuple[int, bytes], ...]:
    """Model a crash after inode 14's zero size reached disk first."""
    patches = list(_modern_orphan_patches(path, (14,)))
    superblock = patches[0][1]
    _, raw_inode, inode_offset = _ext4_inode_record(path, 14)
    inode = bytearray(raw_inode)
    block_size = 1024 << struct.unpack_from("<I", superblock, 0x18)[0]
    sectors_per_block = block_size // 512

    assert struct.unpack_from("<H", inode, 0x00)[0] & 0xF000 == 0x8000
    assert struct.unpack_from("<H", inode, 0x1A)[0] == 2
    assert struct.unpack_from("<I", inode, 0x04)[0] == 54
    assert struct.unpack_from("<I", inode, 0x6C)[0] == 0
    flags = struct.unpack_from("<I", inode, 0x20)[0]
    assert flags & 0x0008_0000
    assert not flags & 0x0000_4000
    assert not flags & 0x0004_0000
    assert struct.unpack_from("<H", inode, 0x76)[0] == 0
    assert struct.unpack_from("<I", inode, 0x68)[0] != 0
    assert struct.unpack_from("<I", inode, 0x1C)[0] == 2 * sectors_per_block
    assert struct.unpack_from("<H", inode, 0x74)[0] == 0
    assert struct.unpack_from("<HHHH", inode, 0x28) == (0xF30A, 1, 4, 0)
    assert struct.unpack_from("<I", inode, 0x34)[0] == 0
    raw_length = struct.unpack_from("<H", inode, 0x38)[0]
    assert raw_length == 1
    assert struct.unpack_from("<H", inode, 0x3A)[0] == 0

    struct.pack_into("<I", inode, 0x04, 0)
    struct.pack_into("<I", inode, 0x6C, 0)
    patches.append(
        (inode_offset, _inode_with_checksum(superblock, 14, inode))
    )
    return tuple(patches)


def _cross_group_depth0_orphan_patches(
    path: Path,
) -> tuple[tuple[int, bytes], ...]:
    """Move inode 14's retained extent across fixture groups 3 and 4."""
    patches = list(_zero_size_depth0_orphan_patches(path))
    superblock = bytearray(patches[0][1])
    inode_offset, raw_inode = patches[2]
    inode = bytearray(raw_inode)
    block_size = 1024 << struct.unpack_from("<I", superblock, 0x18)[0]
    assert block_size == 1024
    sectors_per_block = block_size // 512
    first_data = struct.unpack_from("<I", superblock, 0x14)[0]
    blocks_per_group = struct.unpack_from("<I", superblock, 0x20)[0]
    descriptor_size = struct.unpack_from("<H", superblock, 0xFE)[0]
    assert descriptor_size == 64
    seed = struct.unpack_from("<I", superblock, 0x270)[0]
    first_block = first_data + 4 * blocks_per_group - 1
    group_bits = ((3, blocks_per_group - 1), (4, 0))
    assert first_block == 32768

    def read_block(block: int) -> bytearray:
        with path.open("rb") as source:
            source.seek(block * block_size)
            result = bytearray(source.read(block_size))
        assert len(result) == block_size
        return result

    gdt_home = 2
    gdt = read_block(gdt_home)
    bitmap_patches: list[tuple[int, bytes]] = []
    for group, bit_index in group_bits:
        descriptor_offset = group * descriptor_size
        descriptor = bytearray(
            gdt[descriptor_offset : descriptor_offset + descriptor_size]
        )
        bitmap_home = struct.unpack_from("<I", descriptor, 0x00)[0]
        assert struct.unpack_from("<I", descriptor, 0x20)[0] == 0
        bitmap = read_block(bitmap_home)
        byte_index, bit_in_byte = divmod(bit_index, 8)
        assert bitmap[byte_index] & (1 << bit_in_byte) == 0
        bitmap[byte_index] |= 1 << bit_in_byte
        bitmap_checksum = _crc32c_raw(bitmap, seed)
        bitmap_patches.append((bitmap_home * block_size, bytes(bitmap)))

        flags = struct.unpack_from("<H", descriptor, 0x12)[0]
        if flags & 0x02:
            assert group == 4
            struct.pack_into("<H", descriptor, 0x12, flags & ~0x02)
        group_free = struct.unpack_from("<H", descriptor, 0x0C)[0] | (
            struct.unpack_from("<H", descriptor, 0x2C)[0] << 16
        )
        assert group_free > 0
        group_free -= 1
        struct.pack_into("<H", descriptor, 0x0C, group_free & 0xFFFF)
        struct.pack_into("<H", descriptor, 0x2C, group_free >> 16)
        struct.pack_into("<H", descriptor, 0x18, bitmap_checksum & 0xFFFF)
        struct.pack_into("<H", descriptor, 0x38, bitmap_checksum >> 16)
        descriptor = bytearray(
            _group_descriptor_with_checksum(superblock, descriptor, group)
        )
        gdt[descriptor_offset : descriptor_offset + descriptor_size] = descriptor

    super_free = struct.unpack_from("<I", superblock, 0x0C)[0]
    assert struct.unpack_from("<I", superblock, 0x158)[0] == 0
    assert super_free >= 2
    struct.pack_into("<I", superblock, 0x0C, super_free - 2)
    superblock = bytearray(_ext4_super_with_checksum(superblock))

    assert struct.unpack_from("<HHHH", inode, 0x28) == (0xF30A, 1, 4, 0)
    struct.pack_into("<H", inode, 0x38, 2)
    struct.pack_into("<H", inode, 0x3A, 0)
    struct.pack_into("<I", inode, 0x3C, first_block)
    struct.pack_into("<I", inode, 0x1C, 3 * sectors_per_block)
    struct.pack_into("<H", inode, 0x74, 0)
    inode = bytearray(_inode_with_checksum(superblock, 14, inode))

    patches[0] = (1024, bytes(superblock))
    patches[2] = (inode_offset, bytes(inode))
    patches.extend(bitmap_patches)
    patches.append((gdt_home * block_size, bytes(gdt)))
    return tuple(patches)


def _already_truncated_depth0_orphan_patches(
    path: Path,
) -> tuple[tuple[int, bytes], ...]:
    """Model a durable storage truncate whose modern slot remains active."""
    patches = list(_zero_size_depth0_orphan_patches(path))
    superblock = bytearray(patches[0][1])
    block_size = 1024 << struct.unpack_from("<I", superblock, 0x18)[0]
    sectors_per_block = block_size // 512
    first_data = struct.unpack_from("<I", superblock, 0x14)[0]
    blocks_per_group = struct.unpack_from("<I", superblock, 0x20)[0]
    descriptor_size = struct.unpack_from("<H", superblock, 0xFE)[0]
    seed = struct.unpack_from("<I", superblock, 0x270)[0]
    inode_offset, raw_inode = patches[2]
    inode = bytearray(raw_inode)
    assert struct.unpack_from("<HHHH", inode, 0x28) == (0xF30A, 1, 4, 0)
    data_block = struct.unpack_from("<I", inode, 0x3C)[0]
    assert struct.unpack_from("<H", inode, 0x3A)[0] == 0
    assert struct.unpack_from("<H", inode, 0x38)[0] == 1
    group, data_index = divmod(data_block - first_data, blocks_per_group)
    assert group == 0

    gdt_home = 2 if block_size == 1024 else 1
    with path.open("rb") as source:
        source.seek(gdt_home * block_size)
        gdt = bytearray(source.read(block_size))
    assert len(gdt) == block_size
    descriptor_offset = group * descriptor_size % block_size
    descriptor = bytearray(
        gdt[descriptor_offset : descriptor_offset + descriptor_size]
    )
    bitmap_home = struct.unpack_from("<I", descriptor, 0x00)[0]
    with path.open("rb") as source:
        source.seek(bitmap_home * block_size)
        bitmap = bytearray(source.read(block_size))
    assert len(bitmap) == block_size
    data_byte, data_bit = divmod(data_index, 8)
    assert bitmap[data_byte] & (1 << data_bit)
    bitmap[data_byte] &= ~(1 << data_bit)
    bitmap_checksum = _crc32c_raw(bitmap, seed)

    group_free = struct.unpack_from("<H", descriptor, 0x0C)[0] | (
        struct.unpack_from("<H", descriptor, 0x2C)[0] << 16
    )
    group_free += 1
    struct.pack_into("<H", descriptor, 0x0C, group_free & 0xFFFF)
    struct.pack_into("<H", descriptor, 0x2C, group_free >> 16)
    struct.pack_into("<H", descriptor, 0x18, bitmap_checksum & 0xFFFF)
    struct.pack_into("<H", descriptor, 0x38, bitmap_checksum >> 16)
    descriptor = bytearray(
        _group_descriptor_with_checksum(superblock, descriptor, group)
    )
    gdt[descriptor_offset : descriptor_offset + descriptor_size] = descriptor

    super_free = struct.unpack_from("<I", superblock, 0x0C)[0] | (
        struct.unpack_from("<I", superblock, 0x158)[0] << 32
    )
    super_free += 1
    struct.pack_into("<I", superblock, 0x0C, super_free & 0xFFFF_FFFF)
    struct.pack_into("<I", superblock, 0x158, super_free >> 32)
    superblock = bytearray(_ext4_super_with_checksum(superblock))

    struct.pack_into("<H", inode, 0x2A, 0)
    inode[0x34:0x64] = bytes(48)
    struct.pack_into("<I", inode, 0x1C, sectors_per_block)
    struct.pack_into("<H", inode, 0x74, 0)
    inode = bytearray(_inode_with_checksum(superblock, 14, inode))

    patches[0] = (1024, bytes(superblock))
    patches[2] = (inode_offset, bytes(inode))
    patches.extend(
        (
            (bitmap_home * block_size, bytes(bitmap)),
            (gdt_home * block_size, bytes(gdt)),
        )
    )
    return tuple(patches)


def _legacy_orphan_patches(
    path: Path,
    head: int,
    links: tuple[tuple[int, int], ...],
    *,
    modern_entries: tuple[int, ...] = (),
    bad_checksum_inode: int | None = None,
) -> tuple[tuple[int, bytes], ...]:
    """Author a legacy orphan chain, optionally sharing modern discovery."""
    modern = _modern_orphan_patches(
        path, modern_entries, orphan_present=bool(modern_entries)
    )
    superblock = bytearray(modern[0][1])
    assert len(superblock) == 1024
    inode_count = struct.unpack_from("<I", superblock, 0x00)[0]
    assert 0 <= head <= inode_count
    struct.pack_into("<I", superblock, 0xE8, head)

    patches: list[tuple[int, bytes]] = [
        (1024, _ext4_super_with_checksum(superblock)),
        modern[1],
    ]
    seen: set[int] = set()
    for inode_number, next_inode in links:
        assert inode_number not in seen
        seen.add(inode_number)
        assert 0 < inode_number <= inode_count
        assert 0 <= next_inode <= 0xFFFF_FFFF
        primary_super, inode, inode_offset = _ext4_inode_record(
            path, inode_number
        )
        updated_inode = bytearray(inode)
        struct.pack_into("<I", updated_inode, 0x14, next_inode)
        updated_inode = bytearray(
            _inode_with_checksum(primary_super, inode_number, updated_inode)
        )
        if inode_number == bad_checksum_inode:
            updated_inode[0x7C] ^= 1
        patches.append((inode_offset, bytes(updated_inode)))
    if bad_checksum_inode is not None:
        assert bad_checksum_inode in seen
    return tuple(patches)


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


def _jbd2_ring_advance(
    logical: int, count: int, *, first: int, maxlen: int
) -> int:
    """Advance within the usable JBD2 ring without assuming contiguous media."""
    assert 0 < first < maxlen
    assert first <= logical < maxlen
    assert count >= 0
    return first + (logical - first + count) % (maxlen - first)


def _jbd2_super_with_checksum(block: bytes | bytearray) -> bytes:
    """Stamp the standard CRC32C in a 1024-byte JBD2 superblock."""
    result = bytearray(block)
    assert len(result) == 1024
    struct.pack_into(">I", result, 0xFC, 0)
    struct.pack_into(">I", result, 0xFC, _crc32c_raw(result))
    return bytes(result)


def _jbd2_block_with_super_checksum(block: bytes | bytearray) -> bytes:
    """Stamp only the 1024-byte JBD2 super while preserving block padding."""
    result = bytearray(block)
    assert len(result) >= 1024
    result[:1024] = _jbd2_super_with_checksum(result[:1024])
    return bytes(result)


def _jbd2_super_checksum_valid(block: bytes) -> bool:
    if len(block) != 1024:
        return False
    stored = struct.unpack_from(">I", block, 0xFC)[0]
    unstamped = bytearray(block)
    struct.pack_into(">I", unstamped, 0xFC, 0)
    return stored == _crc32c_raw(unstamped)


def _sequential_prefix_merge(
    new: bytes, old: bytes, observed: bytes
) -> bool:
    """Match one new-image prefix followed by the untouched old suffix."""
    if not (len(new) == len(old) == len(observed)):
        return False
    old_phase = False
    for new_byte, old_byte, observed_byte in zip(
        new, old, observed, strict=True
    ):
        if new_byte == old_byte:
            if observed_byte != new_byte:
                return False
        elif old_phase:
            if observed_byte != old_byte:
                return False
        elif observed_byte == old_byte:
            old_phase = True
        elif observed_byte != new_byte:
            return False
    return True


def _build_jbd2_activation_fixture(path: Path) -> dict[str, object]:
    """Derive independent AKW1 activation images from one clean fixture."""
    layout = _ext4_recovery_layout(path)
    block_size = layout["block_size"]
    assert block_size == 1024
    journal0_physical = layout["journal_block"]
    with path.open("rb") as source:
        source.seek(layout["primary_super"] * block_size)
        clean_super = source.read(1024)
        source.seek(journal0_physical * block_size)
        source_journal = source.read(block_size)
    assert len(clean_super) == 1024
    assert len(source_journal) == block_size
    assert clean_super == _ext4_super_with_checksum(clean_super)
    assert struct.unpack_from("<I", clean_super, 0x60)[0] & 0x04 == 0
    assert struct.unpack_from(">II", source_journal, 0x00) == (
        0xC03B3998,
        4,
    )
    assert struct.unpack_from(">I", source_journal, 0x1C)[0] == 0
    assert struct.unpack_from(">I", source_journal, 0x28)[0] == 0
    assert source_journal[0x50:0x58] == bytes(8)
    assert source_journal[0x5C:0x88] == bytes(0x2C)
    assert struct.unpack_from(">I", source_journal, 0xFC)[0] == 0

    first = struct.unpack_from(">I", source_journal, 0x14)[0]
    maxlen = struct.unpack_from(">I", source_journal, 0x10)[0]
    assert struct.unpack_from(">I", source_journal, 0x58)[0] == 0
    guard_logical = first + 1
    assert 0 < first < guard_logical < maxlen
    old_journal_buffer = bytearray(source_journal)
    struct.pack_into(">I", old_journal_buffer, 0x58, guard_logical)
    old_journal = bytes(old_journal_buffer)
    source_patches = (
        (
            journal0_physical * block_size + 0x58,
            struct.pack(">I", guard_logical),
        ),
    )
    journal_map = _ext4_journal_physical_map(
        path, (0, guard_logical)
    )
    guard_physical = journal_map[guard_logical]
    with path.open("rb") as source:
        source.seek(guard_physical * block_size)
        old_guard = source.read(block_size)
    assert len(old_guard) == block_size

    dirty_super = bytearray(clean_super)
    struct.pack_into(
        "<I",
        dirty_super,
        0x60,
        struct.unpack_from("<I", dirty_super, 0x60)[0] | 0x04,
    )
    struct.pack_into("<H", dirty_super, 0x3A, 1)
    dirty_super = _ext4_super_with_checksum(dirty_super)

    clean_checksum = struct.unpack_from("<I", clean_super, 0x3FC)[0]
    dirty_checksum = struct.unpack_from("<I", dirty_super, 0x3FC)[0]
    anchor = bytearray(old_journal)
    anchor[0x78:0x7C] = old_journal[0x28:0x2C]
    anchor[0x7C:0x80] = old_journal[0x58:0x5C]
    anchor[0x80:0x84] = old_journal[0x50:0x54]
    anchor[0x84:0x88] = old_journal[0xFC:0x100]
    struct.pack_into(">I", anchor, 0x1C, 0)
    struct.pack_into(">I", anchor, 0x28, 0x13)
    anchor[0x50:0x54] = b"\x04\x00\x00\x00"
    struct.pack_into(">I", anchor, 0x54, 0)
    struct.pack_into(">I", anchor, 0x58, guard_logical)
    struct.pack_into(">I", anchor, 0x5C, 0x414B5731)
    struct.pack_into(">I", anchor, 0x60, clean_checksum)
    struct.pack_into(">I", anchor, 0x64, clean_checksum ^ 0xFFFF_FFFF)
    struct.pack_into(">I", anchor, 0x68, guard_logical)
    struct.pack_into(">I", anchor, 0x6C, guard_logical ^ 0xFFFF_FFFF)
    struct.pack_into(">I", anchor, 0x70, dirty_checksum)
    struct.pack_into(">I", anchor, 0x74, dirty_checksum ^ 0xFFFF_FFFF)
    anchor = _jbd2_super_with_checksum(anchor)

    preseed = bytearray(anchor)
    preseed[0] = 0
    standard = bytearray(anchor)
    standard[0x5C:0x88] = bytes(0x2C)
    standard = _jbd2_super_with_checksum(standard)

    success_trace = (
        ("write", guard_physical * 2, 2),
        ("flush", 0, 0),
        ("write", guard_physical * 2, 2),
        ("flush", 0, 0),
        ("write", journal0_physical * 2, 2),
        ("flush", 0, 0),
        ("write", 2, 2),
        ("flush", 0, 0),
        ("write", journal0_physical * 2, 2),
        ("flush", 0, 0),
        ("write", guard_physical * 2, 2),
        ("flush", 0, 0),
    )
    return {
        "image": path,
        "layout": layout,
        "journal0_physical": journal0_physical,
        "guard_logical": guard_logical,
        "guard_physical": guard_physical,
        "source_patches": source_patches,
        "clean_super": clean_super,
        "dirty_super": dirty_super,
        "old_journal": old_journal,
        "old_guard": old_guard,
        "anchor": anchor,
        "preseed": bytes(preseed),
        "standard": standard,
        "success_trace": success_trace,
    }


def _read_jbd2_activation_media(
    path: Path, fixture: dict[str, object]
) -> tuple[bytes, bytes, bytes]:
    layout = fixture["layout"]
    journal0_physical = fixture["journal0_physical"]
    guard_physical = fixture["guard_physical"]
    assert isinstance(layout, dict)
    assert isinstance(journal0_physical, int)
    assert isinstance(guard_physical, int)
    block_size = layout["block_size"]
    assert block_size == 1024
    with path.open("rb") as source:
        source.seek(layout["primary_super"] * block_size)
        superblock = source.read(1024)
        source.seek(journal0_physical * block_size)
        journal = source.read(block_size)
        source.seek(guard_physical * block_size)
        guard = source.read(block_size)
    assert len(superblock) == len(journal) == len(guard) == block_size
    return superblock, journal, guard


def _assert_activation_cleanup_trace(
    trace: tuple[tuple[str, int, int], ...],
    *,
    journal0_physical: int,
    guard_physical: int,
) -> None:
    allowed_writes = {
        ("write", 2, 2),
        ("write", journal0_physical * 2, 2),
        ("write", guard_physical * 2, 2),
    }
    for index, event in enumerate(trace):
        assert event[0] in {"write", "flush"}
        if event[0] != "write":
            continue
        assert event in allowed_writes
        assert index + 1 < len(trace)
        assert trace[index + 1] == ("flush", 0, 0)


def _activation_resolved_mount_lines(
    marker: str, expected_features: int
) -> list[str]:
    return [
        "T-ARENA T-VOLUME EXT4-NEW CONSTANT _M-IOR CONSTANT _V",
        "_V _EXT4-CTX CONSTANT _AR-CTX",
        (
            "_M-IOR 0= _V V.LIFECYCLE @ VFS-L-MOUNTED = AND "
            "_V _EXT4-READY? AND "
            "_AR-CTX _EXT4-C.RECOVERY + @ 0= AND "
            "_AR-CTX _EXT4-C.J.WRITE-ACTIVE + @ 0= AND "
            "_AR-CTX _EXT4-C.J.FEATURES + @ "
            f"{expected_features} = AND "
            "_AR-CTX _EXT4-C.J.START + @ 0= AND "
            "_AR-CTX _EXT4-C.J.WITNESS + @ _EXT4-JW-NONE = AND "
            "_AR-CTX _EXT4-C.J.WITNESS-CHECKSUM + @ 0= AND "
            "_AR-CTX _EXT4-C.J.WITNESS-NEW-CHECKSUM + @ 0= AND "
            "_AR-CTX _EXT4-C.J.ANCHOR + @ 0= AND "
            "_AR-CTX _EXT4-C.J.CLEANUP + @ _EXT4-JC-NONE = AND "
            "_AR-CTX _EXT4-C.SUPER-TORN + @ 0= AND "
            "_AR-CTX _EXT4-C.J.PRIMARY-TORN + @ 0= AND "
            "_AR-CTX _EXT4-C.J.HOME-WRITES + @ 0= AND "
            "_AR-CTX _EXT4-C.SB + _EXT4-SUPER-CHECKSUM? AND "
            "_AR-CTX _EXT4-C.SB + _EXT4-SB.INCOMPAT + L@ "
            "_EXT4-INCOMPAT-RECOVER AND 0= AND "
            f'IF ." {marker}" THEN'
        ),
    ]


def _assert_activation_landed_media(
    path: Path,
    fixture: dict[str, object],
    *,
    expected_features: int,
) -> None:
    clean_super = fixture["clean_super"]
    old_journal = fixture["old_journal"]
    guard_logical = fixture["guard_logical"]
    assert isinstance(clean_super, bytes)
    assert isinstance(old_journal, bytes)
    assert isinstance(guard_logical, int)

    superblock, journal, guard = _read_jbd2_activation_media(path, fixture)
    assert superblock == clean_super
    if expected_features == 0:
        assert journal == old_journal
        return

    assert expected_features == 0x13
    assert struct.unpack_from(">II", journal, 0x00) == (0xC03B3998, 4)
    assert struct.unpack_from(">I", journal, 0x0C)[0] == 1024
    assert journal[0x10:0x18] == old_journal[0x10:0x18]
    assert struct.unpack_from(">I", journal, 0x1C)[0] == 0
    assert struct.unpack_from(">I", journal, 0x28)[0] == expected_features
    assert journal[0x2C:0x50] == old_journal[0x2C:0x50]
    assert journal[0x50:0x54] == b"\x04\x00\x00\x00"
    assert struct.unpack_from(">I", journal, 0x54)[0] == 0
    assert struct.unpack_from(">I", journal, 0x58)[0] == guard_logical
    assert journal[0x5C:0x88] == bytes(0x2C)
    assert _jbd2_super_checksum_valid(journal)
    assert guard == bytes(1024)


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
    snippets: list[str] = []
    lowered = output.lower()
    for marker in found:
        offset = lowered.find(marker.lower())
        snippets.append(output[max(0, offset - 1000):offset + 1000])
    assert not found, (
        f"Forth diagnostics {found}:\n"
        + "\n--- diagnostic context ---\n".join(snippets)
        + f"\n--- transcript tail ---\n{output[-4000:]}"
    )


def _compact_source_load_lines(lines: list[str]) -> list[str]:
    """Preserve Forth tokens while amortizing per-line UART prompt work."""
    result: list[str] = []
    pending = ""
    for raw_line in lines:
        # vfs-ext4.f uses backslash only for Forth line comments.  Remove the
        # comment before packing so its prose is not echoed through the UART.
        # Its balanced parenthesized forms are likewise stack-effect comments,
        # never executable strings, and need not consume source-loader steps.
        source = raw_line.split("\\", 1)[0]
        source = re.sub(r"\([^)]*\)", " ", source)
        line = source.strip() if '"' in source else " ".join(source.split())
        if not line:
            continue
        line_size = len(line.encode("utf-8"))
        assert line_size <= 255, (
            "one ext4 Forth source unit exceeds the MegaPad BIOS TIB: "
            f"{line_size} bytes"
        )
        joined = f"{pending} {line}" if pending else line
        # MegaPad's BIOS TIB holds at most 255 source bytes; never rely on its
        # silent overflow behavior.
        if pending and len(joined.encode("utf-8")) > 255:
            result.append(pending)
            pending = line
        else:
            pending = joined
    if pending:
        result.append(pending)
    return result


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

    # Whitespace, comments, and per-line prompts have no executable Forth
    # semantics but every echoed UART byte consumes emulator steps.  The
    # packed input remains a real cold source-mode compilation.
    lines = _compact_source_load_lines(
        fat_harness._load_forth_lines(str(EXT4_F))
    )
    source_ready = "EXT4-SOURCE-READY"
    payload = "\n".join([*lines, f'." {source_ready}"']) + "\n"
    _feed_until_idle(system, payload.encode(), 800_000_000)
    transcript = fat_harness.uart_text(uart)
    _assert_no_forth_diagnostics(transcript)
    assert f"\r\n{source_ready} ok\r\n" in transcript, (
        "ext4 source load exceeded its checked-in step budget:\n"
        + transcript[-4000:]
    )

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
    read_faults_by_write_and_ordinal: (
        dict[tuple[int, int], dict] | None
    ) = None,
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
    pending_read_faults = dict(read_faults_by_write_and_ordinal or {})
    read_ordinals: dict[int, int] = {}

    def track_dma(request, phase):
        nonlocal write_ordinal
        if phase == "write":
            write_ordinal += 1
            trace.append(("write", request[1], request[3]))
            if write_faults_by_ordinal and write_ordinal in write_faults_by_ordinal:
                system.storage.inject_fault(
                    **write_faults_by_ordinal[write_ordinal]
                )
        elif phase == "read":
            read_ordinal = read_ordinals.get(write_ordinal, 0) + 1
            read_ordinals[write_ordinal] = read_ordinal
            fault = pending_read_faults.pop(
                (write_ordinal, read_ordinal), None
            )
            if fault is not None:
                system.storage.inject_fault(**fault)
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


def _forth_conjunction(checks: list[str]) -> str:
    """Join nonempty Forth predicates with postfix AND operations."""
    assert checks
    return " ".join((checks[0], *(f"{check} AND" for check in checks[1:])))


_EXT4_AUTH_ONLY_BINDING_FORTH = (
    (
        ": _EXT4-TEST-AUTH-MOUNT "
        "_EXT4-MOUNT-AUTHENTICATE ?DUP IF EXIT THEN "
        "EXT4-D-RECOVERY _EXT4-UNSUPPORTED ;"
    ),
    "CREATE _EXT4-TEST-AUTH-OPS VFS-OPS-SIZE ALLOT",
    "EXT4-OPS _EXT4-TEST-AUTH-OPS VFS-OPS-SIZE CMOVE",
    (
        "' _EXT4-TEST-AUTH-MOUNT _EXT4-TEST-AUTH-OPS "
        "VFS-OP-MOUNT CELLS + !"
    ),
    "CREATE _EXT4-TEST-AUTH-BINDING VFS-BINDING-DESC-SIZE ALLOT",
    (
        "EXT4-BINDING _EXT4-TEST-AUTH-BINDING "
        "VFS-BINDING-DESC-SIZE CMOVE"
    ),
    "_EXT4-TEST-AUTH-OPS _EXT4-TEST-AUTH-BINDING VB.OPS !",
    (
        ": EXT4-TEST-AUTH-NEW "
        "_EXT4-TEST-AUTH-BINDING SWAP VFS-NEW ;"
    ),
)


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
def writer_activation_fixture(
    canonical_images: dict[str, Path],
) -> dict[str, object]:
    return _build_jbd2_activation_fixture(
        canonical_images["primary-1k-i256"]
    )


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


def test_jbd2_writer_workspace_is_exact_reusable_and_geometry_bounded(
    tmp_path: Path,
) -> None:
    blank = tmp_path / "writer-workspace.img"
    blank.write_bytes(bytes(4 * 512))
    output = run_forth(
        blank,
        [
            "3 3 3 1024 _EXT4-JWR-MEASURE CONSTANT _JW-M-IOR CONSTANT _JW-BYTES",
            "CREATE _JW-CTX _EXT4-CTX-SIZE ALLOT",
            "_JW-CTX _EXT4-CTX-SIZE 0 FILL",
            "CREATE _JW-MAP 8 CELLS ALLOT _JW-MAP 8 CELLS 0 FILL",
            "CREATE _JW-HASH 16 CELLS ALLOT _JW-HASH 16 CELLS 0 FILL",
            "1000 _JW-CTX _EXT4-C.BLOCKS + !",
            "1024 _JW-CTX _EXT4-C.BSIZE + !",
            "8 _JW-CTX _EXT4-C.J.MAXLEN + !",
            "1 _JW-CTX _EXT4-C.J.FIRST + !",
            "7 _JW-CTX _EXT4-C.J.HEAD + !",
            "0xFFFFFFFF _JW-CTX _EXT4-C.J.SEQUENCE + !",
            "_JW-MAP _JW-CTX _EXT4-C.J.MAP + !",
            "8 _JW-CTX _EXT4-C.J.MAP-CAPACITY + !",
            "_JW-HASH _JW-CTX _EXT4-C.J.MAP-HASH + !",
            "16 _JW-CTX _EXT4-C.J.MAP-HASH-SLOTS + !",
            "-1 _JW-CTX _EXT4-C.J.WRITER-CURRENT + !",
            (
                "_JW-BYTES 2 CELLS + A-XMEM ARENA-NEW THROW "
                "CONSTANT _JW-ARENA"
            ),
            "_JW-ARENA _JW-CTX _EXT4-C.ARENA + !",
            "_JW-ARENA ARENA-USED CONSTANT _JW-BEFORE",
            (
                "1 1 1 _JW-CTX _EXT4-JTX-PREFLIGHT-CAPACITY "
                "CONSTANT _JW-PREFLIGHT-FIT"
            ),
            (
                "2 0 1 _JW-CTX _EXT4-JTX-PREFLIGHT-CAPACITY "
                "CONSTANT _JW-PREFLIGHT-EXACT"
            ),
            (
                "3 0 1 _JW-CTX _EXT4-JTX-PREFLIGHT-CAPACITY "
                "CONSTANT _JW-PREFLIGHT-SHORT"
            ),
            (
                "3 3 3 _JW-CTX _EXT4-JWR-ENSURE "
                "CONSTANT _JW-IOR CONSTANT _JW"
            ),
            "_JW-ARENA ARENA-USED CONSTANT _JW-AFTER",
            (
                "_JW-M-IOR 0= _JW-PREFLIGHT-FIT 0= AND "
                "_JW-PREFLIGHT-EXACT 0= AND "
                "_JW-PREFLIGHT-SHORT VFS-E-NOSPC = AND "
                "_JW-IOR 0= AND _JW 0<> AND "
                "_JW-CTX _EXT4-C.J.WRITER + @ _JW = AND "
                "_JW _EXT4-JWR.TOTAL + @ _JW-BYTES = AND "
                "_JW-AFTER _JW-BEFORE _JW-BYTES + = AND "
                "_JW _EXT4-JWR.META-SLOTS + @ 8 = AND "
                "_JW _EXT4-JWR.DATA-SLOTS + @ 8 = AND "
                "_JW _EXT4-JWR.REVOKE-SLOTS + @ 8 = AND "
                "_JW _EXT4-JWR.FREE + @ 6 = AND "
                "_JW _EXT4-JWR.HEAD + @ 7 = AND "
                "_JW _EXT4-JWR.NEXT-TID + @ 0= AND "
                'IF ." EXT4-JWR-EXACT" THEN'
            ),
            "_JW-ARENA ARENA-USED CONSTANT _JW-REUSE-BEFORE",
            "5 _JW-CTX _EXT4-C.J.HEAD + !",
            "41 _JW-CTX _EXT4-C.J.SEQUENCE + !",
            (
                "3 3 3 _JW-CTX _EXT4-JWR-ENSURE "
                "CONSTANT _JW-REUSE-IOR CONSTANT _JW-REUSE"
            ),
            "_JW-ARENA ARENA-USED CONSTANT _JW-REUSE-AFTER",
            (
                "_JW-REUSE-IOR 0= _JW-REUSE _JW = AND "
                "_JW _EXT4-JWR.HEAD + @ 5 = AND "
                "_JW _EXT4-JWR.TAIL + @ 5 = AND "
                "_JW _EXT4-JWR.FREE + @ 6 = AND "
                "_JW _EXT4-JWR.NEXT-TID + @ 42 = AND "
                "_JW-REUSE-AFTER _JW-REUSE-BEFORE = AND "
                'IF ." EXT4-JWR-REBASED" THEN'
            ),
            "7 _JW-CTX _EXT4-C.J.HEAD + !",
            "0xFFFFFFFF _JW-CTX _EXT4-C.J.SEQUENCE + !",
            (
                "3 3 3 _JW-CTX _EXT4-JWR-ENSURE "
                "CONSTANT _JW-WRAP-IOR CONSTANT _JW-WRAP"
            ),
            (
                "4 3 3 _JW-CTX _EXT4-JWR-ENSURE "
                "CONSTANT _JW-CONFLICT-IOR CONSTANT _JW-CONFLICT"
            ),
            (
                "_JW-WRAP-IOR 0= _JW-WRAP _JW = AND "
                "_JW-REUSE-AFTER _JW-REUSE-BEFORE = AND "
                "_JW _EXT4-JWR.HEAD + @ 7 = AND "
                "_JW _EXT4-JWR.NEXT-TID + @ 0= AND "
                "_JW-CONFLICT 0= AND _JW-CONFLICT-IOR VFS-E-CONFLICT = AND "
                "_JW-ARENA ARENA-USED _JW-REUSE-AFTER = AND "
                'IF ." EXT4-JWR-REUSED" THEN'
            ),
            "3 _JW-CTX _EXT4-C.J.MAP-HASH-SLOTS + !",
            (
                "3 3 3 _JW-CTX _EXT4-JWR-ENSURE "
                "CONSTANT _JW-BAD-HASH-IOR CONSTANT _JW-BAD-HASH"
            ),
            (
                "1 0 0 _JW _EXT4-JTX-BEGIN "
                "CONSTANT _JW-BAD-CTX-IOR CONSTANT _JW-BAD-CTX"
            ),
            "16 _JW-CTX _EXT4-C.J.MAP-HASH-SLOTS + !",
            "_EXT4-NONNEG-MAX 1+ _JW-CTX _EXT4-C.J.MAP-HASH-SLOTS + !",
            (
                "3 3 3 _JW-CTX _EXT4-JWR-ENSURE "
                "CONSTANT _JW-NEG-HASH-IOR CONSTANT _JW-NEG-HASH"
            ),
            "16 _JW-CTX _EXT4-C.J.MAP-HASH-SLOTS + !",
            "9 _JW _EXT4-JWR.MAXLEN + !",
            (
                "1 0 0 _JW _EXT4-JTX-BEGIN "
                "CONSTANT _JW-BAD-RING-IOR CONSTANT _JW-BAD-RING"
            ),
            "8 _JW _EXT4-JWR.MAXLEN + !",
            "-1 _JW-CTX _EXT4-C.BLOCKS + !",
            (
                "1 0 0 _JW _EXT4-JTX-BEGIN "
                "CONSTANT _JW-NEG-BLOCKS-IOR CONSTANT _JW-NEG-BLOCKS"
            ),
            "1000 _JW-CTX _EXT4-C.BLOCKS + !",
            "-1 _JW-CTX _EXT4-C.J.HEAD + !",
            (
                "3 3 3 _JW-CTX _EXT4-JWR-ENSURE "
                "CONSTANT _JW-NEG-HEAD-IOR CONSTANT _JW-NEG-HEAD"
            ),
            "7 _JW-CTX _EXT4-C.J.HEAD + !",
            (
                "_JW-BAD-HASH 0= _JW-BAD-HASH-IOR VFS-E-INVALID = AND "
                "_JW-BAD-CTX 0= AND _JW-BAD-CTX-IOR VFS-E-INVALID = AND "
                "_JW-NEG-HASH 0= AND "
                "_JW-NEG-HASH-IOR VFS-E-INVALID = AND "
                "_JW-BAD-RING 0= AND _JW-BAD-RING-IOR VFS-E-INVALID = AND "
                "_JW-NEG-BLOCKS 0= AND "
                "_JW-NEG-BLOCKS-IOR VFS-E-INVALID = AND "
                "_JW-NEG-HEAD 0= AND _JW-NEG-HEAD-IOR VFS-E-INVALID = AND "
                "_JW-CTX _EXT4-C.J.WRITER + @ _JW = AND "
                "_JW-ARENA ARENA-USED _JW-REUSE-AFTER = AND "
                'IF ." EXT4-JWR-CONTEXT-GEOMETRY" THEN'
            ),
            "_JW _EXT4-JWR.META-HASH + @ CONSTANT _JW-META-HASH",
            "1 _JW _EXT4-JWR.META-HASH + !",
            (
                "3 3 3 _JW-CTX _EXT4-JWR-ENSURE "
                "CONSTANT _JW-SHAPE-IOR CONSTANT _JW-SHAPE"
            ),
            "_JW-META-HASH _JW _EXT4-JWR.META-HASH + !",
            "4 _JW _EXT4-JWR.META-USED + !",
            "_JW _EXT4-JTX-ABORT CONSTANT _JW-COUNT-IOR",
            "0 _JW _EXT4-JWR.META-USED + !",
            (
                "_JW-SHAPE 0= _JW-SHAPE-IOR VFS-E-CORRUPT = AND "
                "_JW-COUNT-IOR VFS-E-INVALID = AND "
                "_JW _EXT4-JWR.STATE + @ _EXT4-JWR-IDLE = AND "
                "_JW _EXT4-JWR.FREE + @ 6 = AND "
                'IF ." EXT4-JWR-VALIDATION-GUARDS" THEN'
            ),
            (
                "_JW  _EXT4-JTX-TAGS/BLOCK 62 = "
                "_JW _EXT4-JTX-REVOKES/BLOCK 125 = AND "
                "62 0 _JW _EXT4-JTX-LOG-BLOCKS 0= SWAP 65 = AND AND "
                "63 0 _JW _EXT4-JTX-LOG-BLOCKS 0= SWAP 67 = AND AND "
                "0 126 _JW _EXT4-JTX-LOG-BLOCKS 0= SWAP 4 = AND AND "
                'IF ." EXT4-JWR-GEOMETRY" THEN'
            ),
            (
                "1 1 1 _JW _EXT4-JTX-BEGIN "
                "CONSTANT _JWT-IOR CONSTANT _JWT"
            ),
            (
                "1 0 0 _JW _EXT4-JTX-BEGIN "
                "CONSTANT _JW-BUSY-IOR CONSTANT _JW-BUSY"
            ),
            (
                "_JWT-IOR 0= _JWT _JW = AND "
                "_JW _EXT4-JWR.LOG-RESERVED + @ 5 = AND "
                "_JW _EXT4-JWR.FREE + @ 1 = AND "
                "_JW _EXT4-JWR.TX-START + @ 7 = AND "
                "_JW _EXT4-JWR.TX-TID + @ 0= AND "
                "7 _JW-CTX _EXT4-JOURNAL-NEXT 1 = AND "
                "_JW-BUSY 0= AND _JW-BUSY-IOR VFS-E-BUSY = AND "
                'IF ." EXT4-JWR-RESERVED" THEN'
            ),
            "_JW _EXT4-JTX-ABORT CONSTANT _JW-ABORT-IOR",
            (
                "_JW-ABORT-IOR 0= _JW _EXT4-JWR.STATE + @ "
                "_EXT4-JWR-IDLE = AND _JW _EXT4-JWR.FREE + @ 6 = AND "
                "_JW-ARENA ARENA-USED _JW-AFTER = AND "
                'IF ." EXT4-JWR-ABORT-REUSED" THEN'
            ),
            "2 0 1 _JW _EXT4-JTX-BEGIN CONSTANT _JW-FIT-IOR CONSTANT _JW-FIT",
            (
                "_JW-FIT-IOR 0= _JW-FIT _JW = AND "
                "_JW _EXT4-JWR.LOG-RESERVED + @ 6 = AND "
                "_JW _EXT4-JWR.FREE + @ 0= AND "
                'IF ." EXT4-JWR-EXACT-RING" THEN'
            ),
            "_JW _EXT4-JTX-ABORT DROP",
            "5 _JW _EXT4-JWR.FREE + !",
            (
                "2 0 1 _JW _EXT4-JTX-BEGIN "
                "CONSTANT _JW-SHORT-IOR CONSTANT _JW-SHORT"
            ),
            (
                "_JW-SHORT 0= _JW-SHORT-IOR VFS-E-NOSPC = AND "
                "_JW _EXT4-JWR.STATE + @ _EXT4-JWR-IDLE = AND "
                "_JW _EXT4-JWR.FREE + @ 5 = AND "
                'IF ." EXT4-JWR-RING-ATOMIC" THEN'
            ),
            "6 _JW _EXT4-JWR.FREE + !",
            "5 _JW-CTX _EXT4-C.J.MAX-TRANSACTION + !",
            (
                "3 0 1 _JW _EXT4-JTX-BEGIN "
                "CONSTANT _JW-MAX-IOR CONSTANT _JW-MAX"
            ),
            "0 _JW-CTX _EXT4-C.J.MAX-TRANSACTION + !",
            "1 _JW-CTX _EXT4-C.J.MAX-TRANS-DATA + !",
            (
                "0 2 0 _JW _EXT4-JTX-BEGIN "
                "CONSTANT _JW-DMAX-IOR CONSTANT _JW-DMAX"
            ),
            (
                "_JW-MAX 0= _JW-MAX-IOR VFS-E-NOSPC = AND "
                "_JW-DMAX 0= AND _JW-DMAX-IOR VFS-E-NOSPC = AND "
                "_JW _EXT4-JWR.STATE + @ _EXT4-JWR-IDLE = AND "
                "_JW _EXT4-JWR.FREE + @ 6 = AND "
                'IF ." EXT4-JWR-LIMITS" THEN'
            ),
            "CREATE _JWN-CTX _EXT4-CTX-SIZE ALLOT",
            "_JWN-CTX _EXT4-CTX-SIZE 0 FILL",
            "1000 _JWN-CTX _EXT4-C.BLOCKS + ! 1024 _JWN-CTX _EXT4-C.BSIZE + !",
            "8 _JWN-CTX _EXT4-C.J.MAXLEN + ! 1 _JWN-CTX _EXT4-C.J.FIRST + !",
            "_JW-MAP _JWN-CTX _EXT4-C.J.MAP + !",
            "8 _JWN-CTX _EXT4-C.J.MAP-CAPACITY + !",
            "_JW-HASH _JWN-CTX _EXT4-C.J.MAP-HASH + !",
            "16 _JWN-CTX _EXT4-C.J.MAP-HASH-SLOTS + !",
            "-1 _JWN-CTX _EXT4-C.J.WRITER-CURRENT + !",
            (
                "_JW-BYTES 1 CELLS - A-XMEM ARENA-NEW THROW "
                "CONSTANT _JWN-ARENA"
            ),
            "_JWN-ARENA _JWN-CTX _EXT4-C.ARENA + !",
            "_JWN-ARENA ARENA-USED CONSTANT _JWN-BEFORE",
            (
                "3 3 3 _JWN-CTX _EXT4-JWR-ENSURE "
                "CONSTANT _JWN-IOR CONSTANT _JWN"
            ),
            (
                "_JWN 0= _JWN-IOR VFS-E-NOMEM = AND "
                "_JWN-ARENA ARENA-USED _JWN-BEFORE = AND "
                "_JWN-CTX _EXT4-C.J.WRITER + @ 0= AND "
                'IF ." EXT4-JWR-NOMEM-ATOMIC" THEN'
            ),
        ],
    )
    _assert_emitted(output, "EXT4-JWR-EXACT")
    _assert_emitted(output, "EXT4-JWR-REBASED")
    _assert_emitted(output, "EXT4-JWR-REUSED")
    _assert_emitted(output, "EXT4-JWR-CONTEXT-GEOMETRY")
    _assert_emitted(output, "EXT4-JWR-VALIDATION-GUARDS")
    _assert_emitted(output, "EXT4-JWR-GEOMETRY")
    _assert_emitted(output, "EXT4-JWR-RESERVED")
    _assert_emitted(output, "EXT4-JWR-ABORT-REUSED")
    _assert_emitted(output, "EXT4-JWR-EXACT-RING")
    _assert_emitted(output, "EXT4-JWR-RING-ATOMIC")
    _assert_emitted(output, "EXT4-JWR-LIMITS")
    _assert_emitted(output, "EXT4-JWR-NOMEM-ATOMIC")


def test_jbd2_writer_arithmetic_and_4k_geometry_are_total(
    tmp_path: Path,
) -> None:
    blank = tmp_path / "writer-geometry.img"
    blank.write_bytes(bytes(4 * 512))
    output = run_forth(
        blank,
        [
            (
                "_EXT4-NONNEG-MAX 1 _EXT4-UADD? "
                "CONSTANT _JWG-A-IOR CONSTANT _JWG-A"
            ),
            (
                "_EXT4-NONNEG-MAX 2 _EXT4-UMUL? "
                "CONSTANT _JWG-M-IOR CONSTANT _JWG-M"
            ),
            (
                "_EXT4-NONNEG-MAX _EXT4-HASH-SLOTS "
                "CONSTANT _JWG-H-IOR CONSTANT _JWG-H"
            ),
            (
                "-1 0 0 4096 _EXT4-JWR-MEASURE "
                "CONSTANT _JWG-N-IOR CONSTANT _JWG-N"
            ),
            (
                "0 0 0 8192 _EXT4-JWR-MEASURE "
                "CONSTANT _JWG-B-IOR CONSTANT _JWG-B"
            ),
            (
                "_JWG-A 0= _JWG-A-IOR VFS-E-OVERFLOW = AND "
                "_JWG-M 0= AND _JWG-M-IOR VFS-E-OVERFLOW = AND "
                "_JWG-H 0= AND _JWG-H-IOR VFS-E-OVERFLOW = AND "
                "_JWG-N 0= AND _JWG-N-IOR VFS-E-INVALID = AND "
                "_JWG-B 0= AND _JWG-B-IOR VFS-E-INVALID = AND "
                'IF ." EXT4-JWR-ARITHMETIC-TOTAL" THEN'
            ),
            (
                "0 0 0 4096 _EXT4-JWR-MEASURE "
                "CONSTANT _JWG-4K-IOR CONSTANT _JWG-4K-BYTES"
            ),
            "CREATE _JWG-CTX _EXT4-CTX-SIZE ALLOT",
            "_JWG-CTX _EXT4-CTX-SIZE 0 FILL",
            "CREATE _JWG-MAP 500 CELLS ALLOT _JWG-MAP 500 CELLS 0 FILL",
            "CREATE _JWG-HASH 1024 CELLS ALLOT _JWG-HASH 1024 CELLS 0 FILL",
            "1000 _JWG-CTX _EXT4-C.BLOCKS + !",
            "4096 _JWG-CTX _EXT4-C.BSIZE + !",
            "500 _JWG-CTX _EXT4-C.J.MAXLEN + !",
            "1 _JWG-CTX _EXT4-C.J.FIRST + !",
            "_JWG-MAP _JWG-CTX _EXT4-C.J.MAP + !",
            "500 _JWG-CTX _EXT4-C.J.MAP-CAPACITY + !",
            "_JWG-HASH _JWG-CTX _EXT4-C.J.MAP-HASH + !",
            "1024 _JWG-CTX _EXT4-C.J.MAP-HASH-SLOTS + !",
            "-1 _JWG-CTX _EXT4-C.J.WRITER-CURRENT + !",
            (
                "_JWG-4K-BYTES 2 CELLS + A-XMEM ARENA-NEW THROW "
                "CONSTANT _JWG-ARENA"
            ),
            "_JWG-ARENA _JWG-CTX _EXT4-C.ARENA + !",
            (
                "0 0 0 _JWG-CTX _EXT4-JWR-ENSURE "
                "CONSTANT _JWG-W-IOR CONSTANT _JWG-W"
            ),
            (
                "_JWG-4K-IOR 0= _JWG-4K-BYTES _EXT4-JWR-SIZE 8192 + = AND "
                "_JWG-W-IOR 0= AND _JWG-W 0<> AND "
                "_JWG-W _EXT4-JTX-TAGS/BLOCK 254 = AND "
                "_JWG-W _EXT4-JTX-REVOKES/BLOCK 509 = AND "
                "254 0 _JWG-W _EXT4-JTX-LOG-BLOCKS 0= SWAP 257 = AND AND "
                "255 0 _JWG-W _EXT4-JTX-LOG-BLOCKS 0= SWAP 259 = AND AND "
                "0 510 _JWG-W _EXT4-JTX-LOG-BLOCKS 0= SWAP 4 = AND AND "
                "_JWG-W _EXT4-JWR.FREE + @ 498 = AND "
                'IF ." EXT4-JWR-4K-GEOMETRY" THEN'
            ),
            (
                "_JWG-W _EXT4-JWR.SCRATCH-A + @ -1 _JWG-CTX "
                "_EXT4-WRITE-JBLOCK CONSTANT _JWG-WRANGE"
            ),
            "0 0 _JWG-CTX _EXT4-WRITE-JBLOCK CONSTANT _JWG-WNULL",
            "-1 _JWG-CTX _EXT4-READ-JBLOCK CONSTANT _JWG-RRANGE",
            (
                "_JWG-WRANGE VFS-IOR-REASON VFS-R-CORRUPT = "
                "_JWG-WRANGE VFS-IOR-DETAIL EXT4-D-JOURNAL = AND "
                "_JWG-WNULL VFS-E-INVALID = AND "
                "_JWG-RRANGE VFS-IOR-REASON VFS-R-CORRUPT = AND "
                "_JWG-RRANGE VFS-IOR-DETAIL EXT4-D-JOURNAL = AND "
                'IF ." EXT4-JBLOCK-RANGE-GUARDS" THEN'
            ),
        ],
    )
    _assert_emitted(output, "EXT4-JWR-ARITHMETIC-TOTAL")
    _assert_emitted(output, "EXT4-JWR-4K-GEOMETRY")
    _assert_emitted(output, "EXT4-JBLOCK-RANGE-GUARDS")


def test_jbd2_writer_staging_coalesces_and_cancels_without_io(
    tmp_path: Path,
) -> None:
    blank = tmp_path / "writer-staging.img"
    blank.write_bytes(bytes(4 * 512))
    output = run_forth(
        blank,
        [
            "3 3 3 1024 _EXT4-JWR-MEASURE DROP CONSTANT _JST-BYTES",
            "CREATE _JST-CTX _EXT4-CTX-SIZE ALLOT",
            "_JST-CTX _EXT4-CTX-SIZE 0 FILL",
            "CREATE _JST-MAP 10 CELLS ALLOT _JST-MAP 10 CELLS 0 FILL",
            "CREATE _JST-HASH 32 CELLS ALLOT _JST-HASH 32 CELLS 0 FILL",
            "1000 _JST-CTX _EXT4-C.BLOCKS + !",
            "1024 _JST-CTX _EXT4-C.BSIZE + !",
            "10 _JST-CTX _EXT4-C.J.MAXLEN + !",
            "1 _JST-CTX _EXT4-C.J.FIRST + !",
            "_JST-MAP _JST-CTX _EXT4-C.J.MAP + !",
            "10 _JST-CTX _EXT4-C.J.MAP-CAPACITY + !",
            "_JST-HASH _JST-CTX _EXT4-C.J.MAP-HASH + !",
            "32 _JST-CTX _EXT4-C.J.MAP-HASH-SLOTS + !",
            "-1 _JST-CTX _EXT4-C.J.WRITER-CURRENT + !",
            "900 _JST-HASH 900 31 AND CELLS + !",
            (
                "_JST-BYTES 2 CELLS + A-XMEM ARENA-NEW THROW "
                "CONSTANT _JST-ARENA"
            ),
            "_JST-ARENA _JST-CTX _EXT4-C.ARENA + !",
            (
                "3 3 3 _JST-CTX _EXT4-JWR-ENSURE "
                "CONSTANT _JST-W-IOR CONSTANT _JST-W"
            ),
            "_JST-ARENA ARENA-USED CONSTANT _JST-ARENA-USED",
            "CREATE _JST-M1 1024 ALLOT _JST-M1 1024 0x11 FILL",
            "CREATE _JST-M2 1024 ALLOT _JST-M2 1024 0x22 FILL",
            "CREATE _JST-D1 1024 ALLOT _JST-D1 1024 0x33 FILL",
            "CREATE _JST-D2 1024 ALLOT _JST-D2 1024 0x44 FILL",
            (
                "2 2 2 _JST-W _EXT4-JTX-BEGIN "
                "CONSTANT _JST-T-IOR CONSTANT _JST-T"
            ),
            "_JST-W _EXT4-JWR.LOG-RESERVED + @ CONSTANT _JST-LOG",
            "_JST-LOG 1+ _JST-W _EXT4-JWR.LOG-RESERVED + !",
            (
                "_JST-M1 41 _JST-T _EXT4-JTX-META-PUT "
                "CONSTANT _JST-BAD-LOG"
            ),
            "_JST-LOG _JST-W _EXT4-JWR.LOG-RESERVED + !",
            "1 _JST-W _EXT4-JWR.TX-TID + +!",
            (
                "_JST-M1 41 _JST-T _EXT4-JTX-META-PUT "
                "CONSTANT _JST-BAD-TID"
            ),
            "-1 _JST-W _EXT4-JWR.TX-TID + +!",
            (
                "_JST-BAD-LOG VFS-E-INVALID = "
                "_JST-BAD-TID VFS-E-INVALID = AND "
                "_JST-W _EXT4-JWR.META-USED + @ 0= AND "
                'IF ." EXT4-JTX-RUNTIME-GUARDS" THEN'
            ),
            "_JST-M1 42 _JST-T _EXT4-JTX-META-PUT CONSTANT _JST-MP1",
            "0 _JST-W _EXT4-JWR.META-ACTIVE + !",
            (
                "_JST-M2 42 _JST-T _EXT4-JTX-META-PUT "
                "CONSTANT _JST-BAD-COUNT"
            ),
            "1 _JST-W _EXT4-JWR.META-ACTIVE + !",
            (
                "3 _JST-W _EXT4-JWR.META-HASH + @ "
                "42 _JST-W _EXT4-JWR.META-SLOTS + @ 1- AND CELLS + !"
            ),
            (
                "_JST-M2 42 _JST-T _EXT4-JTX-META-PUT "
                "CONSTANT _JST-BAD-HASH"
            ),
            (
                "1 _JST-W _EXT4-JWR.META-HASH + @ "
                "42 _JST-W _EXT4-JWR.META-SLOTS + @ 1- AND CELLS + !"
            ),
            "_JST-M2 42 _JST-T _EXT4-JTX-META-PUT CONSTANT _JST-MP2",
            "0 _JST-W _EXT4-JWR-META-IMAGE C@ CONSTANT _JST-META-LAST",
            "0 _JST-W _EXT4-JWR-META-ENTRY 2 CELLS + @ CONSTANT _JST-META-CRC",
            (
                "_JST-W _EXT4-JWR.META-IMAGES + @ _JST-W "
                "_EXT4-JTX-IMAGE-CRC CONSTANT _JST-META-CALC"
            ),
            (
                "_JST-W-IOR 0= _JST-T-IOR 0= AND _JST-MP1 0= AND "
                "_JST-BAD-COUNT VFS-E-CORRUPT = AND "
                "_JST-BAD-HASH VFS-E-CORRUPT = AND "
                "_JST-MP2 0= AND _JST-W _EXT4-JWR.META-USED + @ 1 = AND "
                "_JST-W _EXT4-JWR.META-ACTIVE + @ 1 = AND "
                "_JST-META-LAST 0x22 = AND "
                "_JST-META-CRC _JST-META-CALC = AND "
                'IF ." EXT4-JTX-META-COALESCED" THEN'
            ),
            "42 _JST-T _EXT4-JTX-REVOKE CONSTANT _JST-R1",
            "42 _JST-T _EXT4-JTX-REVOKE CONSTANT _JST-R2",
            (
                "_JST-R1 0= _JST-R2 0= AND "
                "_JST-W _EXT4-JWR.META-USED + @ 1 = AND "
                "_JST-W _EXT4-JWR.META-ACTIVE + @ 0= AND "
                "_JST-W _EXT4-JWR.REVOKE-USED + @ 1 = AND "
                "_JST-W _EXT4-JWR.REVOKE-ACTIVE + @ 1 = AND "
                "0 _JST-W _EXT4-JWR-META-ENTRY CELL+ @ "
                "_EXT4-JE-CANCELLED = AND "
                'IF ." EXT4-JTX-REVOKE-CANCELLED-META" THEN'
            ),
            "_JST-D1 42 _JST-T _EXT4-JTX-DATA-PUT CONSTANT _JST-DP1",
            "_JST-D2 42 _JST-T _EXT4-JTX-DATA-PUT CONSTANT _JST-DP2",
            (
                "_JST-DP1 VFS-E-CONFLICT = _JST-DP2 VFS-E-CONFLICT = AND "
                "_JST-W _EXT4-JWR.DATA-USED + @ 0= AND "
                "_JST-W _EXT4-JWR.DATA-ACTIVE + @ 0= AND "
                "_JST-W _EXT4-JWR.REVOKE-USED + @ 1 = AND "
                "_JST-W _EXT4-JWR.REVOKE-ACTIVE + @ 1 = AND "
                'IF ." EXT4-JTX-DATA-REVOKE-CONFLICT-ATOMIC" THEN'
            ),
            "_JST-D1 44 _JST-T _EXT4-JTX-DATA-PUT CONSTANT _JST-D44A",
            "_JST-D2 44 _JST-T _EXT4-JTX-DATA-PUT CONSTANT _JST-D44B",
            "44 _JST-T _EXT4-JTX-REVOKE CONSTANT _JST-R44",
            "_JST-M1 44 _JST-T _EXT4-JTX-META-PUT CONSTANT _JST-M44",
            (
                "_JST-D44A 0= _JST-D44B 0= AND "
                "_JST-W _EXT4-JWR.DATA-USED + @ 1 = AND "
                "_JST-W _EXT4-JWR.DATA-ACTIVE + @ 1 = AND "
                "0 _JST-W _EXT4-JWR-DATA-IMAGE C@ 0x44 = AND "
                "_JST-R44 VFS-E-CONFLICT = AND "
                "_JST-M44 VFS-E-CONFLICT = AND "
                "_JST-W _EXT4-JWR.META-USED + @ 1 = AND "
                "_JST-W _EXT4-JWR.META-ACTIVE + @ 0= AND "
                "_JST-W _EXT4-JWR.REVOKE-USED + @ 1 = AND "
                "_JST-W _EXT4-JWR.REVOKE-ACTIVE + @ 1 = AND "
                'IF ." EXT4-JTX-DATA-COALESCED-CONFLICT-ATOMIC" THEN'
            ),
            "43 _JST-T _EXT4-JTX-DATA-ZERO CONSTANT _JST-ZERO",
            "_JST-M2 58 _JST-T _EXT4-JTX-META-PUT CONSTANT _JST-M58",
            "58 _JST-T _EXT4-JTX-REVOKE CONSTANT _JST-R58",
            "_JST-M1 58 _JST-T _EXT4-JTX-META-PUT CONSTANT _JST-M58B",
            (
                "_JST-ZERO 0= 1 _JST-W _EXT4-JWR-DATA-IMAGE C@ 0= AND "
                "_JST-M58 0= AND _JST-R58 0= AND _JST-M58B 0= AND "
                "_JST-W _EXT4-JWR.META-USED + @ 2 = AND "
                "_JST-W _EXT4-JWR.META-ACTIVE + @ 1 = AND "
                "_JST-W _EXT4-JWR.REVOKE-USED + @ 2 = AND "
                "_JST-W _EXT4-JWR.REVOKE-ACTIVE + @ 1 = AND "
                "1 _JST-W _EXT4-JWR-META-IMAGE C@ 0x11 = AND "
                'IF ." EXT4-JTX-CANCELLATION-REACTIVATES" THEN'
            ),
            "_JST-M1 74 _JST-T _EXT4-JTX-META-PUT CONSTANT _JST-META-FULL",
            "74 _JST-T _EXT4-JTX-REVOKE CONSTANT _JST-REVOKE-FULL",
            "_JST-D1 900 _JST-T _EXT4-JTX-DATA-PUT CONSTANT _JST-JOURNAL-HOME",
            (
                "_JST-META-FULL VFS-E-NOSPC = "
                "_JST-REVOKE-FULL VFS-E-NOSPC = AND "
                "_JST-JOURNAL-HOME VFS-E-INVALID = AND "
                "_JST-W _EXT4-JWR.META-USED + @ 2 = AND "
                "_JST-W _EXT4-JWR.REVOKE-USED + @ 2 = AND "
                "_JST-W _EXT4-JWR.DATA-USED + @ 2 = AND "
                'IF ." EXT4-JTX-CAPACITY-ATOMIC" THEN'
            ),
            "_JST-T _EXT4-JTX-ABORT CONSTANT _JST-ABORT",
            (
                "_JST-ABORT 0= _JST-W _EXT4-JWR.STATE + @ "
                "_EXT4-JWR-IDLE = AND "
                "_JST-W _EXT4-JWR.META-USED + @ 0= AND "
                "_JST-W _EXT4-JWR.DATA-USED + @ 0= AND "
                "_JST-W _EXT4-JWR.REVOKE-USED + @ 0= AND "
                "_JST-W _EXT4-JWR.META-IMAGES + @ C@ 0= AND "
                "_JST-W _EXT4-JWR.DATA-IMAGES + @ C@ 0= AND "
                "_JST-ARENA ARENA-USED _JST-ARENA-USED = AND "
                'IF ." EXT4-JTX-ABORT-ZEROIZED" THEN'
            ),
            "2 2 2 _JST-W _EXT4-JTX-BEGIN DROP _EXT4-JTX-ABORT CONSTANT _JST-REPEAT",
            (
                "_JST-REPEAT 0= _JST-ARENA ARENA-USED _JST-ARENA-USED = AND "
                'IF ." EXT4-JTX-ARENA-REUSED" THEN'
            ),
        ],
    )
    _assert_emitted(output, "EXT4-JTX-META-COALESCED")
    _assert_emitted(output, "EXT4-JTX-RUNTIME-GUARDS")
    _assert_emitted(output, "EXT4-JTX-REVOKE-CANCELLED-META")
    _assert_emitted(output, "EXT4-JTX-DATA-REVOKE-CONFLICT-ATOMIC")
    _assert_emitted(output, "EXT4-JTX-DATA-COALESCED-CONFLICT-ATOMIC")
    _assert_emitted(output, "EXT4-JTX-CANCELLATION-REACTIVATES")
    _assert_emitted(output, "EXT4-JTX-CAPACITY-ATOMIC")
    _assert_emitted(output, "EXT4-JTX-ABORT-ZEROIZED")
    _assert_emitted(output, "EXT4-JTX-ARENA-REUSED")


def test_jbd2_writer_activation_is_ordered_and_publishes_after_cleanup(
    writer_activation_fixture: dict[str, object], tmp_path: Path
) -> None:
    image = writer_activation_fixture["image"]
    success_trace = writer_activation_fixture["success_trace"]
    source_patches = writer_activation_fixture["source_patches"]
    dirty_super = writer_activation_fixture["dirty_super"]
    standard = writer_activation_fixture["standard"]
    assert isinstance(image, Path)
    assert isinstance(success_trace, tuple)
    assert isinstance(source_patches, tuple)
    assert isinstance(dirty_super, bytes)
    assert isinstance(standard, bytes)

    activated = tmp_path / "jbd2-writer-activated.img"
    try:
        output, trace, media_sha256 = run_recovery_forth(
            image,
            activated,
            [
                "T-ARENA T-VOLUME EXT4-NEW CONSTANT _M-IOR CONSTANT _V",
                "_V _EXT4-CTX CONSTANT _AW-CTX",
                (
                    "1 0 0 _AW-CTX _EXT4-JWR-ENSURE "
                    "CONSTANT _AW-E-IOR CONSTANT _AW-W"
                ),
                "_AW-W _EXT4-JWR.HEAD + @ CONSTANT _AW-HEAD",
                "_AW-W _EXT4-JWR.TAIL + @ CONSTANT _AW-TAIL",
                "_AW-W _EXT4-JWR.FREE + @ CONSTANT _AW-FREE",
                "_AW-W _EXT4-JWR.NEXT-TID + @ CONSTANT _AW-NEXT-TID",
                "_AW-W _EXT4-JWR-ACTIVATE CONSTANT _AW-A-IOR",
                (
                    "1 0 0 _AW-W _EXT4-JTX-BEGIN "
                    "CONSTANT _AW-B-IOR CONSTANT _AW-T"
                ),
                "0 _V VFS-UNMOUNT CONSTANT _AW-UNMOUNT-IOR",
                (
                    "VFS-UNMOUNT-F-FORCE _V VFS-UNMOUNT "
                    "CONSTANT _AW-FORCE-IOR"
                ),
                "_AW-T _EXT4-JTX-ABORT CONSTANT _AW-ABORT-IOR",
                "_AW-W _EXT4-JWR-ACTIVATE CONSTANT _AW-AGAIN-IOR",
                (
                    "_M-IOR 0= _AW-E-IOR 0= AND _AW-A-IOR 0= AND "
                    "_AW-B-IOR 0= AND _AW-T _AW-W = AND "
                    "_AW-UNMOUNT-IOR VFS-E-BUSY = AND "
                    "_AW-FORCE-IOR VFS-E-BUSY = AND "
                    "_V V.LIFECYCLE @ VFS-L-MOUNTED = AND "
                    "_V V.BCTX @ _AW-CTX = AND "
                    "_AW-ABORT-IOR 0= AND "
                    "_AW-AGAIN-IOR VFS-E-BUSY = AND "
                    "_AW-W _EXT4-JWR-VALID? AND "
                    "_AW-W _EXT4-JWR.STATE + @ _EXT4-JWR-IDLE = AND "
                    "_AW-W _EXT4-JWR.PHASE + @ _EXT4-JWP-NONE = AND "
                    "_AW-W _EXT4-JWR.FAULT + @ 0= AND "
                    "_AW-W _EXT4-JWR.HEAD + @ _AW-HEAD = AND "
                    "_AW-W _EXT4-JWR.TAIL + @ _AW-TAIL = AND "
                    "_AW-W _EXT4-JWR.FREE + @ _AW-FREE = AND "
                    "_AW-W _EXT4-JWR.NEXT-TID + @ _AW-NEXT-TID = AND "
                    "_AW-CTX _EXT4-C.RECOVERY + @ 0<> AND "
                    "_AW-CTX _EXT4-C.J.WRITE-ACTIVE + @ 0<> AND "
                    "_AW-CTX _EXT4-C.J.FEATURES + @ "
                    "_EXT4-JBD2-I-RECOVERY-REVOKE = AND "
                    "_AW-CTX _EXT4-C.J.SEED + @ 0<> AND "
                    "_AW-CTX _EXT4-C.J.START + @ 0= AND "
                    "_AW-CTX _EXT4-C.J.HEAD + @ _AW-HEAD = AND "
                    "_AW-CTX _EXT4-C.J.WITNESS + @ _EXT4-JW-NONE = AND "
                    "_AW-CTX _EXT4-C.J.WITNESS-CHECKSUM + @ 0= AND "
                    "_AW-CTX _EXT4-C.J.WITNESS-NEW-CHECKSUM + @ 0= AND "
                    "_AW-CTX _EXT4-C.J.ANCHOR + @ 0= AND "
                    "_AW-CTX _EXT4-C.J.WRITER-CURRENT + @ 0<> AND "
                    "_AW-CTX _EXT4-C.READY + @ 0<> AND "
                    "_AW-CTX _EXT4-C.SB + _EXT4-SUPER-CHECKSUM? AND "
                    "_AW-CTX _EXT4-C.SB + _EXT4-SB.INCOMPAT + L@ "
                    "_EXT4-INCOMPAT-RECOVER AND 0<> AND "
                    'IF ." EXT4-JWR-ACTIVATION-OK" THEN'
                ),
            ],
            patches=source_patches,
            capture_media=activated,
        )
        _assert_emitted(output, "EXT4-JWR-ACTIVATION-OK")
        assert trace == success_trace
        assert activated.is_file()
        assert _sha256(activated) == media_sha256
        superblock, journal, guard = _read_jbd2_activation_media(
            activated, writer_activation_fixture
        )
        assert superblock == dirty_super
        assert journal == standard
        assert guard == bytes(1024)
    finally:
        activated.unlink(missing_ok=True)


def test_jbd2_writer_emits_one_ordered_transaction_and_retains_afterimages(
    writer_activation_fixture: dict[str, object], tmp_path: Path
) -> None:
    image = writer_activation_fixture["image"]
    layout = writer_activation_fixture["layout"]
    activation_trace = writer_activation_fixture["success_trace"]
    source_patches = writer_activation_fixture["source_patches"]
    dirty_super = writer_activation_fixture["dirty_super"]
    standard = writer_activation_fixture["standard"]
    guard_logical = writer_activation_fixture["guard_logical"]
    journal0_physical = writer_activation_fixture["journal0_physical"]
    assert isinstance(image, Path)
    assert isinstance(layout, dict)
    assert isinstance(activation_trace, tuple)
    assert isinstance(source_patches, tuple)
    assert isinstance(dirty_super, bytes)
    assert isinstance(standard, bytes)
    assert isinstance(guard_logical, int)
    assert isinstance(journal0_physical, int)

    block_size = layout["block_size"]
    assert block_size == 1024
    metadata_home = 30000
    data_home = 30001
    revoke_home = 30002
    assert revoke_home < layout["blocks"]

    first = struct.unpack_from(">I", standard, 0x14)[0]
    maxlen = struct.unpack_from(">I", standard, 0x10)[0]
    assert first <= guard_logical < maxlen
    logical = {
        "guard": guard_logical,
        "descriptor": _jbd2_ring_advance(
            guard_logical, 1, first=first, maxlen=maxlen
        ),
        "payload": _jbd2_ring_advance(
            guard_logical, 2, first=first, maxlen=maxlen
        ),
        "revoke": _jbd2_ring_advance(
            guard_logical, 3, first=first, maxlen=maxlen
        ),
        "commit": _jbd2_ring_advance(
            guard_logical, 4, first=first, maxlen=maxlen
        ),
        "sentinel": _jbd2_ring_advance(
            guard_logical, 5, first=first, maxlen=maxlen
        ),
    }
    assert len(set(logical.values())) == len(logical)
    journal_map = _ext4_journal_physical_map(image, (0, *logical.values()))
    physical = {name: journal_map[position] for name, position in logical.items()}

    metadata_image = struct.pack(">I", 0xC03B3998) + bytes((0xA5,)) * 1020
    data_image = bytes((0x5A,)) * block_size
    with image.open("rb") as source:
        source.seek(metadata_home * block_size)
        metadata_before = source.read(block_size)
        source.seek(data_home * block_size)
        data_before = source.read(block_size)
        source.seek(revoke_home * block_size)
        revoke_before = source.read(block_size)
    assert all(
        len(block) == block_size
        for block in (metadata_before, data_before, revoke_before)
    )
    assert data_before != data_image

    emitted = tmp_path / "jbd2-writer-one-transaction.img"
    try:
        output, trace, media_sha256 = run_recovery_forth(
            image,
            emitted,
            [
                "CREATE _EW-META 1024 ALLOT _EW-META 1024 0xA5 FILL",
                "0xC03B3998 _EW-META _EXT4-BE32!",
                "CREATE _EW-DATA 1024 ALLOT _EW-DATA 1024 0x5A FILL",
                "T-ARENA T-VOLUME EXT4-NEW CONSTANT _M-IOR CONSTANT _V",
                "_V _EXT4-CTX CONSTANT _EW-CTX",
                (
                    "1 1 1 _EW-CTX _EXT4-JWR-ENSURE "
                    "CONSTANT _EW-E-IOR CONSTANT _EW-W"
                ),
                "_EW-W _EXT4-JWR.HEAD + @ CONSTANT _EW-GUARD",
                "_EW-W _EXT4-JWR.FREE + @ CONSTANT _EW-FREE-BEFORE",
                "_EW-W _EXT4-JWR.NEXT-TID + @ CONSTANT _EW-TID",
                (
                    "_EW-GUARD _EW-CTX _EXT4-JOURNAL-NEXT "
                    "CONSTANT _EW-START"
                ),
                (
                    "_EW-GUARD 5 _EW-CTX _EXT4-JOURNAL-ADVANCE "
                    "CONSTANT _EW-SENTINEL"
                ),
                "_EW-W _EXT4-JWR-ACTIVATE CONSTANT _EW-A-IOR",
                (
                    "1 1 1 _EW-W _EXT4-JTX-BEGIN "
                    "CONSTANT _EW-B-IOR CONSTANT _EW-T"
                ),
                (
                    "_EW-META 30000 _EW-T _EXT4-JTX-META-PUT "
                    "CONSTANT _EW-M-IOR"
                ),
                (
                    "_EW-DATA 30001 _EW-T _EXT4-JTX-DATA-PUT "
                    "CONSTANT _EW-D-IOR"
                ),
                "30002 _EW-T _EXT4-JTX-REVOKE CONSTANT _EW-R-IOR",
                "_EW-T _EXT4-JTX-EMIT CONSTANT _EW-EMIT-IOR",
                "_EW-T _EXT4-JTX-EMIT CONSTANT _EW-RETRY-IOR",
                "_EW-T _EXT4-JTX-ABORT CONSTANT _EW-ABORT-IOR",
                (
                    "1 1 1 _EW-W _EXT4-JTX-BEGIN "
                    "CONSTANT _EW-NEW-IOR CONSTANT _EW-NEW-T"
                ),
                (
                    "_M-IOR 0= _EW-E-IOR 0= AND _EW-A-IOR 0= AND "
                    "_EW-B-IOR 0= AND _EW-T _EW-W = AND "
                    "_EW-M-IOR 0= AND _EW-D-IOR 0= AND "
                    "_EW-R-IOR 0= AND _EW-EMIT-IOR 0= AND "
                    'IF ." EXT4-JTX-EMIT-RESULT" THEN'
                ),
                (
                    "_EW-W _EXT4-JWR-VALID? "
                    "_EW-W _EXT4-JWR.STATE + @ _EXT4-JWR-COMMITTED = AND "
                    "_EW-W _EXT4-JWR.PHASE + @ _EXT4-JWP-NONE = AND "
                    "_EW-W _EXT4-JWR.FAULT + @ 0= AND "
                    "_EW-W _EXT4-JWR.LOG-RESERVED + @ 5 = AND "
                    "_EW-W _EXT4-JWR.FREE + @ _EW-FREE-BEFORE 5 - = AND "
                    "_EW-W _EXT4-JWR.TX-START + @ _EW-GUARD = AND "
                    "_EW-W _EXT4-JWR.TX-CURSOR + @ _EW-SENTINEL = AND "
                    "_EW-W _EXT4-JWR.HEAD + @ _EW-SENTINEL = AND "
                    "_EW-W _EXT4-JWR.TAIL + @ _EW-GUARD = AND "
                    "_EW-W _EXT4-JWR.NEXT-TID + @ "
                    "_EW-TID 1+ 0xFFFFFFFF AND = AND "
                    'IF ." EXT4-JTX-EMIT-WRITER-STATE" THEN'
                ),
                (
                    "_EW-CTX _EXT4-C.RECOVERY + @ 0<> "
                    "_EW-CTX _EXT4-C.J.WRITE-ACTIVE + @ 0<> AND "
                    "_EW-CTX _EXT4-C.J.START + @ _EW-START = AND "
                    "_EW-CTX _EXT4-C.J.SEQUENCE + @ _EW-TID = AND "
                    "_EW-CTX _EXT4-C.J.HEAD + @ _EW-GUARD = AND "
                    "_EW-CTX _EXT4-C.J.ANCHOR + @ _EW-GUARD = AND "
                    "_EW-CTX _EXT4-C.J.CURSOR + @ _EW-SENTINEL = AND "
                    "_EW-CTX _EXT4-C.J.COMMITTED + @ 1 = AND "
                    "_EW-CTX _EXT4-C.J.NEXT-SEQUENCE + @ "
                    "_EW-TID 2 + 0xFFFFFFFF AND = AND "
                    "_EW-CTX _EXT4-C.J.CLEANUP + @ _EXT4-JC-ACTIVE = AND "
                    'IF ." EXT4-JTX-EMIT-CONTEXT-STATE" THEN'
                ),
                (
                    "_EW-W _EXT4-JWR.META-USED + @ 1 = "
                    "_EW-W _EXT4-JWR.META-ACTIVE + @ 1 = AND "
                    "_EW-W _EXT4-JWR.DATA-USED + @ 1 = AND "
                    "_EW-W _EXT4-JWR.DATA-ACTIVE + @ 1 = AND "
                    "_EW-W _EXT4-JWR.REVOKE-USED + @ 1 = AND "
                    "_EW-W _EXT4-JWR.REVOKE-ACTIVE + @ 1 = AND "
                    "0 _EW-W _EXT4-JWR-META-ENTRY @ 30000 = AND "
                    "0 _EW-W _EXT4-JWR-DATA-ENTRY @ 30001 = AND "
                    "0 _EW-W _EXT4-JWR-REVOKE-ENTRY @ 30002 = AND "
                    "_EW-META _EW-W _EXT4-JWR.META-IMAGES + @ "
                    "1024 _EXT4-BYTES=? AND "
                    "_EW-DATA _EW-W _EXT4-JWR.DATA-IMAGES + @ "
                    "1024 _EXT4-BYTES=? AND "
                    'IF ." EXT4-JTX-EMIT-AFTERIMAGES" THEN'
                ),
                (
                    "_EW-RETRY-IOR VFS-E-BUSY = "
                    "_EW-ABORT-IOR VFS-E-BUSY = AND "
                    "_EW-NEW-T 0= AND _EW-NEW-IOR VFS-E-BUSY = AND "
                    'IF ." EXT4-JTX-EMIT-BUSY" THEN'
                ),
            ],
            patches=source_patches,
            capture_media=emitted,
        )
        _assert_emitted(output, "EXT4-JTX-EMIT-RESULT")
        _assert_emitted(output, "EXT4-JTX-EMIT-WRITER-STATE")
        _assert_emitted(output, "EXT4-JTX-EMIT-CONTEXT-STATE")
        _assert_emitted(output, "EXT4-JTX-EMIT-AFTERIMAGES")
        _assert_emitted(output, "EXT4-JTX-EMIT-BUSY")

        # Activation owns writes 1-6.  The emission ordinals are data 7,
        # descriptor 8, payload 9, revoke 10, commit preseed 11, sentinel 12,
        # active-guard preseed 13, active guard 14, active primary 15, and
        # final commit 16.  Ordered data and the log body share the body flush.
        emission_trace = (
            ("write", data_home * 2, 2),
            ("write", physical["descriptor"] * 2, 2),
            ("write", physical["payload"] * 2, 2),
            ("write", physical["revoke"] * 2, 2),
            ("write", physical["commit"] * 2, 2),
            ("write", physical["sentinel"] * 2, 2),
            ("flush", 0, 0),
            ("write", physical["guard"] * 2, 2),
            ("flush", 0, 0),
            ("write", physical["guard"] * 2, 2),
            ("flush", 0, 0),
            ("write", journal0_physical * 2, 2),
            ("flush", 0, 0),
            ("write", physical["commit"] * 2, 2),
            ("flush", 0, 0),
        )
        assert trace == activation_trace + emission_trace
        assert emitted.is_file()
        assert _sha256(emitted) == media_sha256

        superblock, journal, guard = _read_jbd2_activation_media(
            emitted, writer_activation_fixture
        )
        assert superblock == dirty_super
        expected_tid = (
            struct.unpack_from(">I", standard, 0x18)[0] + 1
        ) & 0xFFFF_FFFF
        expected_active = bytearray(standard)
        struct.pack_into(">I", expected_active, 0x18, expected_tid)
        struct.pack_into(">I", expected_active, 0x1C, logical["descriptor"])
        struct.pack_into(">I", expected_active, 0x28, 0x13)
        expected_active[0x50:0x54] = b"\x04\x00\x00\x00"
        struct.pack_into(">I", expected_active, 0x54, 0)
        struct.pack_into(">I", expected_active, 0x58, guard_logical)
        expected_active[0x5C:0x88] = bytes(0x2C)
        expected_active = _jbd2_super_with_checksum(expected_active)
        assert journal == expected_active
        assert guard == expected_active
        assert _jbd2_super_checksum_valid(journal)

        with emitted.open("rb") as source:
            def read_block(block: int) -> bytes:
                source.seek(block * block_size)
                result = source.read(block_size)
                assert len(result) == block_size
                return result

            metadata_after = read_block(metadata_home)
            data_after = read_block(data_home)
            revoke_after = read_block(revoke_home)
            descriptor = read_block(physical["descriptor"])
            payload = read_block(physical["payload"])
            revoke = read_block(physical["revoke"])
            commit = read_block(physical["commit"])
            sentinel = read_block(physical["sentinel"])

        assert metadata_after == metadata_before
        assert data_after == data_image
        assert revoke_after == revoke_before

        escaped_metadata = bytes(4) + metadata_image[4:]
        journal_uuid = expected_active[0x30:0x40]
        tag_seed = _crc32c_raw(journal_uuid)
        tag_seed = _crc32c_raw(struct.pack(">I", expected_tid), tag_seed)
        tag_checksum = _crc32c_raw(escaped_metadata, tag_seed)
        expected_descriptor = bytearray(block_size)
        struct.pack_into(
            ">IIIIIII",
            expected_descriptor,
            0,
            0xC03B3998,
            1,
            expected_tid,
            metadata_home,
            0x09,
            0,
            tag_checksum,
        )
        expected_descriptor[0x1C:0x2C] = journal_uuid
        expected_descriptor = _jbd2_metadata_with_checksum(
            expected_descriptor, journal_uuid
        )
        assert descriptor == expected_descriptor
        assert descriptor[0x1C:0x2C] == journal_uuid
        assert payload == escaped_metadata

        expected_revoke = bytearray(block_size)
        struct.pack_into(
            ">IIIIQ",
            expected_revoke,
            0,
            0xC03B3998,
            5,
            expected_tid,
            24,
            revoke_home,
        )
        expected_revoke = _jbd2_metadata_with_checksum(
            expected_revoke, journal_uuid
        )
        assert revoke == expected_revoke

        expected_commit = bytearray(block_size)
        struct.pack_into(
            ">III", expected_commit, 0, 0xC03B3998, 2, expected_tid
        )
        expected_commit = _jbd2_commit_with_checksum(
            expected_commit, journal_uuid, expected_tid
        )
        assert commit == expected_commit
        assert sentinel == bytes(block_size)
    finally:
        emitted.unlink(missing_ok=True)


def test_jbd2_writer_batches_descriptors_and_revokes_across_ring_wrap(
    writer_activation_fixture: dict[str, object], tmp_path: Path
) -> None:
    """Qualify the smallest two-batch transaction across an admitted wrap."""
    image = writer_activation_fixture["image"]
    layout = writer_activation_fixture["layout"]
    source_patches = writer_activation_fixture["source_patches"]
    clean_super = writer_activation_fixture["clean_super"]
    standard = writer_activation_fixture["standard"]
    fixture_guard = writer_activation_fixture["guard_logical"]
    journal0_physical = writer_activation_fixture["journal0_physical"]
    assert isinstance(image, Path)
    assert isinstance(layout, dict)
    assert isinstance(source_patches, tuple)
    assert isinstance(clean_super, bytes)
    assert isinstance(standard, bytes)
    assert isinstance(fixture_guard, int)
    assert isinstance(journal0_physical, int)

    block_size = layout["block_size"]
    assert block_size == 1024
    tags_per_block = (block_size - 32) // 16
    revokes_per_block = (block_size - 20) // 8
    metadata_count = tags_per_block + 1
    revoke_count = revokes_per_block + 1
    assert (tags_per_block, revokes_per_block) == (62, 125)
    assert (metadata_count, revoke_count) == (63, 126)

    metadata_base = 30000
    data_home = metadata_base + metadata_count
    revoke_base = data_home + 1
    assert revoke_base + revoke_count <= layout["blocks"]
    metadata_homes = tuple(
        range(metadata_base, metadata_base + metadata_count)
    )
    revoke_homes = tuple(range(revoke_base, revoke_base + revoke_count))
    assert len(set((*metadata_homes, data_home, *revoke_homes))) == (
        metadata_count + 1 + revoke_count
    )

    def metadata_image(index: int) -> bytes:
        assert 0 <= index < metadata_count
        result = bytearray((index + 1,) * block_size)
        if index in (0, tags_per_block):
            struct.pack_into(">I", result, 0, 0xC03B3998)
        return bytes(result)

    metadata_images = tuple(
        metadata_image(index) for index in range(metadata_count)
    )
    escaped_images = tuple(
        bytes(4) + payload[4:]
        if payload[:4] == struct.pack(">I", 0xC03B3998)
        else payload
        for payload in metadata_images
    )
    data_image = bytes((0x5A,)) * block_size
    with image.open("rb") as source:
        metadata_before = []
        for home in metadata_homes:
            source.seek(home * block_size)
            metadata_before.append(source.read(block_size))
        source.seek(data_home * block_size)
        data_before = source.read(block_size)
        revoke_before = []
        for home in revoke_homes:
            source.seek(home * block_size)
            revoke_before.append(source.read(block_size))
    metadata_before = tuple(metadata_before)
    revoke_before = tuple(revoke_before)
    assert all(len(payload) == block_size for payload in metadata_before)
    assert len(data_before) == block_size
    assert all(len(payload) == block_size for payload in revoke_before)
    assert all(
        before != after
        for before, after in zip(
            metadata_before, metadata_images, strict=True
        )
    )
    assert data_before != data_image

    first = struct.unpack_from(">I", standard, 0x14)[0]
    maxlen = struct.unpack_from(">I", standard, 0x10)[0]
    max_transaction = struct.unpack_from(">I", standard, 0x48)[0]
    max_trans_data = struct.unpack_from(">I", standard, 0x4C)[0]
    ring_capacity = maxlen - first
    descriptor_blocks = (
        metadata_count + tags_per_block - 1
    ) // tags_per_block
    revoke_blocks = (
        revoke_count + revokes_per_block - 1
    ) // revokes_per_block
    log_blocks = metadata_count + descriptor_blocks + revoke_blocks + 2
    assert descriptor_blocks == revoke_blocks == 2
    assert log_blocks == 69
    assert log_blocks <= ring_capacity - 1
    assert max_transaction == 0 or log_blocks - 1 <= max_transaction
    assert max_trans_data == 0 or 1 <= max_trans_data

    # The feature-zero primary's persisted private head is already the fixture's
    # admitted cursor.  Move only that checked field three slots from the end;
    # production validation, activation, and reservation then emit the first
    # descriptor and payload high before the next payload wraps naturally.
    # No live writer state or admission result is forged.
    wrap_guard = maxlen - 3
    assert first <= wrap_guard < maxlen
    assert struct.unpack_from(">I", standard, 0x58)[0] == fixture_guard
    head_offset = journal0_physical * block_size + 0x58
    matching_head_patches = [
        patch for patch in source_patches if patch[0] == head_offset
    ]
    assert matching_head_patches == [
        (head_offset, struct.pack(">I", fixture_guard))
    ]
    wrap_source_patches = tuple(
        (offset, struct.pack(">I", wrap_guard))
        if offset == head_offset
        else (offset, payload)
        for offset, payload in source_patches
    )

    descriptor_batches = (
        tuple(range(tags_per_block)),
        (tags_per_block,),
    )
    revoke_batches = (
        tuple(range(revokes_per_block)),
        (revokes_per_block,),
    )
    record_logicals: list[int] = []
    descriptor_logicals: list[int] = []
    payload_logicals: dict[int, int] = {}
    revoke_logicals: list[int] = []
    cursor = _jbd2_ring_advance(
        wrap_guard, 1, first=first, maxlen=maxlen
    )
    for batch in descriptor_batches:
        descriptor_logicals.append(cursor)
        record_logicals.append(cursor)
        cursor = _jbd2_ring_advance(cursor, 1, first=first, maxlen=maxlen)
        for index in batch:
            payload_logicals[index] = cursor
            record_logicals.append(cursor)
            cursor = _jbd2_ring_advance(
                cursor, 1, first=first, maxlen=maxlen
            )
    for _batch in revoke_batches:
        revoke_logicals.append(cursor)
        record_logicals.append(cursor)
        cursor = _jbd2_ring_advance(cursor, 1, first=first, maxlen=maxlen)
    commit_logical = cursor
    record_logicals.append(commit_logical)
    cursor = _jbd2_ring_advance(cursor, 1, first=first, maxlen=maxlen)
    sentinel_logical = cursor
    record_logicals.append(sentinel_logical)
    assert tuple(descriptor_logicals) == (4094, 62)
    assert payload_logicals[0] == 4095
    assert payload_logicals[1] == first
    assert tuple(revoke_logicals) == (64, 65)
    assert commit_logical == 66
    assert sentinel_logical == 67
    assert commit_logical == _jbd2_ring_advance(
        wrap_guard, log_blocks - 1, first=first, maxlen=maxlen
    )
    assert sentinel_logical == _jbd2_ring_advance(
        wrap_guard, log_blocks, first=first, maxlen=maxlen
    )
    assert len(record_logicals) == log_blocks
    assert len(set((wrap_guard, *record_logicals))) == log_blocks + 1

    journal_map = _ext4_journal_physical_map(
        image, (0, wrap_guard, *record_logicals)
    )
    wrap_guard_physical = journal_map[wrap_guard]
    activation_trace = (
        ("write", wrap_guard_physical * 2, 2),
        ("flush", 0, 0),
        ("write", wrap_guard_physical * 2, 2),
        ("flush", 0, 0),
        ("write", journal0_physical * 2, 2),
        ("flush", 0, 0),
        ("write", 2, 2),
        ("flush", 0, 0),
        ("write", journal0_physical * 2, 2),
        ("flush", 0, 0),
        ("write", wrap_guard_physical * 2, 2),
        ("flush", 0, 0),
    )
    source_sequence = struct.unpack_from(">I", standard, 0x18)[0]
    expected_tid = (source_sequence + 1) & 0xFFFF_FFFF
    descriptor_start = descriptor_logicals[0]
    journal_uuid = standard[0x30:0x40]
    client_uuid = clean_super[0x68:0x78]
    assert len(journal_uuid) == len(client_uuid) == 16
    assert journal_uuid == client_uuid

    media_path = tmp_path / "jbd2-writer-multi-batch-wrap.img"
    try:
        output, trace, media_sha256 = run_recovery_forth(
            image,
            media_path,
            [
                "CREATE _GB-META 1024 ALLOT",
                "CREATE _GB-DATA 1024 ALLOT _GB-DATA 1024 0x5A FILL",
                "VARIABLE _GB-I VARIABLE _GB-STAGE-IOR",
                (
                    ": _GB-BUILD-META ( index -- ) "
                    "DUP _GB-I ! 1+ _GB-META 1024 ROT FILL "
                    "_GB-I @ DUP 0= SWAP 62 = OR IF "
                    "0xC03B3998 _GB-META _EXT4-BE32! THEN ;"
                ),
                "T-ARENA CONSTANT _GB-ARENA",
                (
                    "_GB-ARENA T-VOLUME EXT4-NEW "
                    "CONSTANT _GB-MOUNT-IOR CONSTANT _GB-V"
                ),
                "_GB-V _EXT4-CTX CONSTANT _GB-CTX",
                (
                    "63 1 126 _GB-CTX _EXT4-JWR-ENSURE "
                    "CONSTANT _GB-E-IOR CONSTANT _GB-W"
                ),
                (
                    "63 126 _GB-W _EXT4-JTX-LOG-BLOCKS "
                    "CONSTANT _GB-LOG-IOR CONSTANT _GB-LOG"
                ),
                (
                    "_GB-MOUNT-IOR 0= _GB-E-IOR 0= AND "
                    "_GB-W _EXT4-JTX-TAGS/BLOCK 62 = AND "
                    "_GB-W _EXT4-JTX-REVOKES/BLOCK 125 = AND "
                    "_GB-LOG-IOR 0= AND _GB-LOG 69 = AND "
                    f"_GB-W _EXT4-JWR.HEAD + @ {wrap_guard} = AND "
                    f"_GB-W _EXT4-JWR.FREE + @ {ring_capacity - 1} = AND "
                    f"_GB-CTX _EXT4-C.J.MAX-TRANSACTION + @ "
                    f"{max_transaction} = AND "
                    f"_GB-CTX _EXT4-C.J.MAX-TRANS-DATA + @ "
                    f"{max_trans_data} = AND "
                    'IF ." EXT4-JTX-BATCH-LIMITS" THEN'
                ),
                "_GB-W _EXT4-JWR-ACTIVATE CONSTANT _GB-A-IOR",
                (
                    "63 1 126 _GB-W _EXT4-JTX-BEGIN "
                    "CONSTANT _GB-B-IOR CONSTANT _GB-T"
                ),
                (
                    ": _GB-STAGE-META ( -- ior ) "
                    "0 _GB-I ! 0 _GB-STAGE-IOR ! BEGIN "
                    "_GB-I @ 63 < _GB-STAGE-IOR @ 0= AND WHILE "
                    "_GB-I @ _GB-BUILD-META _GB-META "
                    "30000 _GB-I @ + _GB-T _EXT4-JTX-META-PUT "
                    "_GB-STAGE-IOR ! 1 _GB-I +! REPEAT "
                    "_GB-STAGE-IOR @ ;"
                ),
                "_GB-STAGE-META CONSTANT _GB-META-IOR",
                (
                    "_GB-DATA 30063 _GB-T _EXT4-JTX-DATA-PUT "
                    "CONSTANT _GB-DATA-IOR"
                ),
                (
                    ": _GB-STAGE-REVOKES ( -- ior ) "
                    "0 _GB-I ! 0 _GB-STAGE-IOR ! BEGIN "
                    "_GB-I @ 126 < _GB-STAGE-IOR @ 0= AND WHILE "
                    "30064 _GB-I @ + _GB-T _EXT4-JTX-REVOKE "
                    "_GB-STAGE-IOR ! 1 _GB-I +! REPEAT "
                    "_GB-STAGE-IOR @ ;"
                ),
                "_GB-STAGE-REVOKES CONSTANT _GB-REVOKE-IOR",
                ": _GB-RETAINED? ( -- flag )",
                (
                    "_GB-W _EXT4-JWR.META-USED + @ 63 = "
                    "_GB-W _EXT4-JWR.META-ACTIVE + @ 63 = AND "
                    "_GB-W _EXT4-JWR.DATA-USED + @ 1 = AND "
                    "_GB-W _EXT4-JWR.DATA-ACTIVE + @ 1 = AND"
                ),
                (
                    "_GB-W _EXT4-JWR.REVOKE-USED + @ 126 = AND "
                    "_GB-W _EXT4-JWR.REVOKE-ACTIVE + @ 126 = AND "
                    "0= IF FALSE EXIT THEN"
                ),
                "0 _GB-I ! BEGIN _GB-I @ 63 < WHILE",
                (
                    "_GB-I @ _GB-W _EXT4-JWR-META-ENTRY DUP @ "
                    "30000 _GB-I @ + = SWAP CELL+ @ "
                    "_EXT4-JE-ACTIVE = AND 0= IF FALSE EXIT THEN"
                ),
                (
                    "_GB-I @ _GB-BUILD-META _GB-META _GB-I @ _GB-W "
                    "_EXT4-JWR-META-IMAGE 1024 _EXT4-BYTES=? "
                    "0= IF FALSE EXIT THEN 1 _GB-I +! REPEAT"
                ),
                (
                    "0 _GB-W _EXT4-JWR-DATA-ENTRY DUP @ 30063 = "
                    "SWAP CELL+ @ _EXT4-JE-ACTIVE = AND "
                    "0= IF FALSE EXIT THEN"
                ),
                (
                    "_GB-DATA 0 _GB-W _EXT4-JWR-DATA-IMAGE "
                    "1024 _EXT4-BYTES=? 0= IF FALSE EXIT THEN"
                ),
                "0 _GB-I ! BEGIN _GB-I @ 126 < WHILE",
                (
                    "_GB-I @ _GB-W _EXT4-JWR-REVOKE-ENTRY DUP @ "
                    "30064 _GB-I @ + = SWAP CELL+ @ "
                    "_EXT4-JE-ACTIVE = AND 0= IF FALSE EXIT THEN"
                ),
                "1 _GB-I +! REPEAT TRUE ;",
                "_GB-T _EXT4-JTX-EMIT CONSTANT _GB-EMIT-IOR",
                "_GB-W _EXT4-JSCAN-BIND-BEGIN",
                (
                    "_EXT4-JSCAN-BINDING _GB-CTX _EXT4-JSCAN "
                    "_EXT4-JSCAN-BIND-FINISH CONSTANT _GB-BIND-IOR"
                ),
                (
                    "_GB-BIND-IOR 0= _EXT4-JSB-META-BOUND @ 63 = AND "
                    "_EXT4-JSB-REVOKE-BOUND @ 126 = AND "
                    "_EXT4-JSB-WRITER @ 0= AND "
                    'IF ." EXT4-JTX-BATCH-BOUND" THEN'
                ),
                (
                    "_GB-A-IOR 0= _GB-B-IOR 0= AND _GB-T _GB-W = AND "
                    "_GB-META-IOR 0= AND _GB-DATA-IOR 0= AND "
                    "_GB-REVOKE-IOR 0= AND _GB-EMIT-IOR 0= AND "
                    "_GB-BIND-IOR 0= AND "
                    "_GB-RETAINED? AND"
                ),
                (
                    "_GB-W _EXT4-JWR-VALID? AND "
                    "_GB-W _EXT4-JWR.STATE + @ _EXT4-JWR-COMMITTED = AND "
                    "_GB-W _EXT4-JWR.LOG-RESERVED + @ 69 = AND "
                    f"_GB-W _EXT4-JWR.FREE + @ "
                    f"{ring_capacity - 1 - log_blocks} = AND"
                ),
                (
                    f"_GB-W _EXT4-JWR.TX-START + @ {wrap_guard} = AND "
                    f"_GB-W _EXT4-JWR.TX-CURSOR + @ {sentinel_logical} "
                    "= AND _GB-W _EXT4-JWR.HEAD + @ "
                    f"{sentinel_logical} = AND "
                    f"_GB-W _EXT4-JWR.TAIL + @ {wrap_guard} = AND"
                ),
                (
                    f"_GB-CTX _EXT4-C.J.START + @ {descriptor_start} = AND "
                    f"_GB-CTX _EXT4-C.J.SEQUENCE + @ {expected_tid} = AND "
                    f"_GB-CTX _EXT4-C.J.HEAD + @ {wrap_guard} = AND "
                    f"_GB-CTX _EXT4-C.J.ANCHOR + @ {wrap_guard} = AND"
                ),
                (
                    f"_GB-CTX _EXT4-C.J.CURSOR + @ {sentinel_logical} "
                    "= AND _GB-CTX _EXT4-C.J.COMMITTED + @ 1 = AND "
                    f"_GB-CTX _EXT4-C.J.NEXT-SEQUENCE + @ "
                    f"{(expected_tid + 2) & 0xFFFF_FFFF} = AND"
                ),
                'IF ." EXT4-JTX-BATCH-EMITTED" THEN',
                "_GB-V _EXT4-MOUNT CONSTANT _GB-REMOUNT-IOR",
                "_GB-ARENA ARENA-USED CONSTANT _GB-USED-AFTER-REMOUNT",
                (
                    "_GB-CTX _EXT4-C.J.WRITER + @ _GB-W = "
                    "_GB-CTX _EXT4-C.J.WRITER-CURRENT + @ 0<> AND "
                    "_GB-W _EXT4-JWR-VALID? AND "
                    "_GB-W _EXT4-JWR.STATE + @ _EXT4-JWR-IDLE = AND "
                    "_GB-W _EXT4-JWR.FAULT + @ 0= AND"
                ),
                (
                    "_GB-W _EXT4-JWR.META-USED + @ 0= AND "
                    "_GB-W _EXT4-JWR.DATA-USED + @ 0= AND "
                    "_GB-W _EXT4-JWR.REVOKE-USED + @ 0= AND "
                    "0 _GB-W _EXT4-JWR-META-IMAGE C@ 0= AND "
                    "62 _GB-W _EXT4-JWR-META-IMAGE C@ 0= AND"
                ),
                (
                    "0 _GB-W _EXT4-JWR-DATA-IMAGE C@ 0= AND "
                    "0 _GB-W _EXT4-JWR-REVOKE-ENTRY @ 0= AND "
                    "125 _GB-W _EXT4-JWR-REVOKE-ENTRY @ 0= AND"
                ),
                (
                    "_GB-W _EXT4-JWR.HEAD + @ "
                    "_GB-CTX _EXT4-C.J.HEAD + @ = AND "
                    "_GB-W _EXT4-JWR.TAIL + @ "
                    "_GB-CTX _EXT4-C.J.HEAD + @ = AND"
                ),
                (
                    "_GB-W _EXT4-JWR.NEXT-TID + @ "
                    "_GB-CTX _EXT4-C.J.SEQUENCE + @ 1+ "
                    "0xFFFFFFFF AND = AND CONSTANT _GB-MOUNT-REBASED"
                ),
                (
                    ": _GB-HOMES? ( -- flag ) 0 _GB-I ! BEGIN "
                    "_GB-I @ 63 < WHILE 30000 _GB-I @ + _GB-CTX "
                    "_EXT4-READ-BLOCK ?DUP IF DROP FALSE EXIT THEN "
                    "_GB-I @ _GB-BUILD-META _GB-CTX _EXT4-C.BLOCK + "
                    "_GB-META 1024 _EXT4-BYTES=? "
                    "0= IF FALSE EXIT THEN 1 _GB-I +! REPEAT TRUE ;"
                ),
                (
                    "63 1 126 _GB-CTX _EXT4-JWR-ENSURE "
                    "CONSTANT _GB-REUSE-IOR CONSTANT _GB-REUSE-W"
                ),
                "_GB-ARENA ARENA-USED CONSTANT _GB-USED-AFTER-ENSURE",
                (
                    "_GB-REMOUNT-IOR 0= "
                    "_GB-V V.LIFECYCLE @ VFS-L-MOUNTED = AND "
                    "_GB-V _EXT4-READY? AND _GB-MOUNT-REBASED AND "
                    "_GB-CTX _EXT4-C.RECOVERY + @ 0= AND "
                    "_GB-CTX _EXT4-C.J.REPLAYED + @ 0<> AND"
                ),
                (
                    "_GB-CTX _EXT4-C.J.START + @ 0= AND "
                    "_GB-CTX _EXT4-C.J.WITNESS + @ _EXT4-JW-NONE = AND "
                    "_GB-CTX _EXT4-C.J.CLEANUP + @ _EXT4-JC-NONE = AND"
                ),
                (
                    "_GB-CTX _EXT4-C.J.FEATURES + @ "
                    "_EXT4-JBD2-I-RECOVERY-REVOKE = AND "
                    "_GB-CTX _EXT4-C.J.COMMITTED + @ 1 = AND "
                    "_GB-CTX _EXT4-C.J.HOME-WRITES + @ 63 = AND"
                ),
                (
                    "_GB-CTX _EXT4-C.J.REVOKE-COUNT + @ 126 = AND "
                    "_GB-CTX _EXT4-C.J.REVOKE-HITS + @ 0= AND "
                    "_GB-CTX _EXT4-C.J.REVOKE-READY + @ 0= AND"
                ),
                (
                    "_GB-CTX _EXT4-C.SB + _EXT4-SUPER-CHECKSUM? AND "
                    "_GB-CTX _EXT4-C.SB + _EXT4-SB.INCOMPAT + L@ "
                    "_EXT4-INCOMPAT-RECOVER AND 0= AND _GB-HOMES? AND"
                ),
                (
                    "_GB-REUSE-IOR 0= AND _GB-REUSE-W _GB-W = AND "
                    "_GB-USED-AFTER-ENSURE _GB-USED-AFTER-REMOUNT = AND"
                ),
                'IF ." EXT4-JTX-BATCH-REMOUNTED" THEN',
            ],
            patches=wrap_source_patches,
            capture_media=media_path,
        )
        _assert_emitted(output, "EXT4-JTX-BATCH-LIMITS")
        _assert_emitted(output, "EXT4-JTX-BATCH-BOUND")
        _assert_emitted(output, "EXT4-JTX-BATCH-EMITTED")
        _assert_emitted(output, "EXT4-JTX-BATCH-REMOUNTED")

        emission_trace = (
            (("write", data_home * 2, 2),)
            + tuple(
                ("write", journal_map[logical] * 2, 2)
                for logical in record_logicals
            )
            + (
                ("flush", 0, 0),
                ("write", wrap_guard_physical * 2, 2),
                ("flush", 0, 0),
                ("write", wrap_guard_physical * 2, 2),
                ("flush", 0, 0),
                ("write", journal0_physical * 2, 2),
                ("flush", 0, 0),
                ("write", journal_map[commit_logical] * 2, 2),
                ("flush", 0, 0),
            )
        )
        recovery_trace = (
            tuple(("write", home * 2, 2) for home in metadata_homes)
            + (
                ("flush", 0, 0),
                ("write", wrap_guard_physical * 2, 2),
                ("flush", 0, 0),
                ("write", wrap_guard_physical * 2, 2),
                ("flush", 0, 0),
                ("write", journal0_physical * 2, 2),
                ("flush", 0, 0),
                ("write", 2, 2),
                ("flush", 0, 0),
                ("write", journal0_physical * 2, 2),
                ("flush", 0, 0),
                ("write", wrap_guard_physical * 2, 2),
                ("flush", 0, 0),
            )
        )
        assert trace == activation_trace + emission_trace + recovery_trace
        assert ("write", data_home * 2, 2) not in recovery_trace
        assert not any(
            ("write", home * 2, 2) in recovery_trace
            for home in revoke_homes
        )

        assert media_path.is_file()
        media_stat = media_path.stat()
        assert media_stat.st_size == image.stat().st_size
        assert media_stat.st_blocks * 512 < media_stat.st_size
        assert _sha256(media_path) == media_sha256
        with media_path.open("rb") as source:
            def read_block(physical_block: int) -> bytes:
                source.seek(physical_block * block_size)
                result = source.read(block_size)
                assert len(result) == block_size
                return result

            final_super = read_block(layout["primary_super"])
            final_journal = read_block(journal0_physical)
            final_guard = read_block(wrap_guard_physical)
            descriptors = tuple(
                read_block(journal_map[logical])
                for logical in descriptor_logicals
            )
            payloads = tuple(
                read_block(journal_map[payload_logicals[index]])
                for index in range(metadata_count)
            )
            revokes = tuple(
                read_block(journal_map[logical])
                for logical in revoke_logicals
            )
            commit = read_block(journal_map[commit_logical])
            sentinel = read_block(journal_map[sentinel_logical])
            metadata_after = tuple(read_block(home) for home in metadata_homes)
            data_after = read_block(data_home)
            revoke_after = tuple(read_block(home) for home in revoke_homes)

        assert final_super == clean_super
        expected_final_journal = bytearray(standard)
        struct.pack_into(
            ">I",
            expected_final_journal,
            0x18,
            (expected_tid + 2) & 0xFFFF_FFFF,
        )
        struct.pack_into(">I", expected_final_journal, 0x1C, 0)
        struct.pack_into(">I", expected_final_journal, 0x58, wrap_guard)
        expected_final_journal = _jbd2_super_with_checksum(
            expected_final_journal
        )
        assert final_journal == expected_final_journal
        assert _jbd2_super_checksum_valid(final_journal)
        assert final_guard == bytes(block_size)

        tag_seed = _crc32c_raw(journal_uuid)
        tag_seed = _crc32c_raw(struct.pack(">I", expected_tid), tag_seed)
        for descriptor, batch in zip(
            descriptors, descriptor_batches, strict=True
        ):
            expected_descriptor = bytearray(block_size)
            struct.pack_into(
                ">III",
                expected_descriptor,
                0,
                0xC03B3998,
                1,
                expected_tid,
            )
            offset = 12
            for batch_index, metadata_index in enumerate(batch):
                flags = 0
                if metadata_index in (0, tags_per_block):
                    flags |= 0x01
                if batch_index:
                    flags |= 0x02
                if batch_index == len(batch) - 1:
                    flags |= 0x08
                tag_checksum = _crc32c_raw(
                    escaped_images[metadata_index], tag_seed
                )
                struct.pack_into(
                    ">IIII",
                    expected_descriptor,
                    offset,
                    metadata_homes[metadata_index],
                    flags,
                    0,
                    tag_checksum,
                )
                assert struct.unpack_from(">IIII", descriptor, offset) == (
                    metadata_homes[metadata_index],
                    flags,
                    0,
                    tag_checksum,
                )
                offset += 16
                if batch_index == 0:
                    expected_descriptor[offset : offset + 16] = client_uuid
                    assert descriptor[offset : offset + 16] == client_uuid
                    offset += 16
            assert descriptor[offset:-4] == bytes(block_size - 4 - offset)
            expected_descriptor = _jbd2_metadata_with_checksum(
                expected_descriptor, journal_uuid
            )
            assert descriptor == expected_descriptor
            assert descriptor == _jbd2_metadata_with_checksum(
                descriptor, journal_uuid
            )
        assert payloads == escaped_images

        for revoke, batch in zip(revokes, revoke_batches, strict=True):
            expected_revoke = bytearray(block_size)
            struct.pack_into(
                ">IIII",
                expected_revoke,
                0,
                0xC03B3998,
                5,
                expected_tid,
                16 + len(batch) * 8,
            )
            for batch_index, revoke_index in enumerate(batch):
                struct.pack_into(
                    ">Q",
                    expected_revoke,
                    16 + batch_index * 8,
                    revoke_homes[revoke_index],
                )
            expected_revoke = _jbd2_metadata_with_checksum(
                expected_revoke, journal_uuid
            )
            assert revoke == expected_revoke
            assert revoke == _jbd2_metadata_with_checksum(
                revoke, journal_uuid
            )
            assert struct.unpack_from(">I", revoke, 0x0C)[0] == (
                16 + len(batch) * 8
            )
            assert tuple(
                struct.unpack_from(">Q", revoke, 16 + index * 8)[0]
                for index in range(len(batch))
            ) == tuple(revoke_homes[index] for index in batch)

        expected_commit = bytearray(block_size)
        struct.pack_into(
            ">III", expected_commit, 0, 0xC03B3998, 2, expected_tid
        )
        expected_commit = _jbd2_commit_with_checksum(
            expected_commit, journal_uuid, expected_tid
        )
        assert commit == expected_commit
        assert sentinel == bytes(block_size)
        assert metadata_after == metadata_images
        assert data_after == data_image
        assert revoke_after == revoke_before
    finally:
        media_path.unlink(missing_ok=True)


def test_jbd2_checkpoint_reuses_ring_and_cleanly_unmounts_across_wrap(
    writer_activation_fixture: dict[str, object], tmp_path: Path
) -> None:
    """Checkpoint twice, then cleanly deactivate the write-active mount."""
    image = writer_activation_fixture["image"]
    layout = writer_activation_fixture["layout"]
    source_patches = writer_activation_fixture["source_patches"]
    clean_super = writer_activation_fixture["clean_super"]
    dirty_super = writer_activation_fixture["dirty_super"]
    standard = writer_activation_fixture["standard"]
    fixture_guard = writer_activation_fixture["guard_logical"]
    journal0_physical = writer_activation_fixture["journal0_physical"]
    assert isinstance(image, Path)
    assert isinstance(layout, dict)
    assert isinstance(source_patches, tuple)
    assert isinstance(clean_super, bytes)
    assert isinstance(dirty_super, bytes)
    assert isinstance(standard, bytes)
    assert isinstance(fixture_guard, int)
    assert isinstance(journal0_physical, int)

    block_size = layout["block_size"]
    assert block_size == 1024
    metadata_home = 30000
    data_home = 30001
    revoke_home = 30002
    assert revoke_home < layout["blocks"]
    metadata_image_1 = (
        struct.pack(">I", 0xC03B3998) + bytes((0xA5,)) * 1020
    )
    metadata_image_2 = (
        struct.pack(">I", 0xC03B3998) + bytes((0x3C,)) * 1020
    )
    data_image_1 = bytes((0x5A,)) * block_size
    data_image_2 = bytes((0xC3,)) * block_size
    with image.open("rb") as source:
        source.seek(metadata_home * block_size)
        metadata_before = source.read(block_size)
        source.seek(data_home * block_size)
        data_before = source.read(block_size)
        source.seek(revoke_home * block_size)
        revoke_before = source.read(block_size)
    assert all(
        len(payload) == block_size
        for payload in (metadata_before, data_before, revoke_before)
    )
    assert metadata_before not in {metadata_image_1, metadata_image_2}
    assert data_before not in {data_image_1, data_image_2}

    first = struct.unpack_from(">I", standard, 0x14)[0]
    maxlen = struct.unpack_from(">I", standard, 0x10)[0]
    ring_capacity = maxlen - first - 1
    wrap_guard = maxlen - 3
    assert first <= wrap_guard < maxlen
    assert struct.unpack_from(">I", standard, 0x58)[0] == fixture_guard
    logical = {
        "guard": wrap_guard,
        "descriptor": _jbd2_ring_advance(
            wrap_guard, 1, first=first, maxlen=maxlen
        ),
        "payload": _jbd2_ring_advance(
            wrap_guard, 2, first=first, maxlen=maxlen
        ),
        "revoke": _jbd2_ring_advance(
            wrap_guard, 3, first=first, maxlen=maxlen
        ),
        "commit": _jbd2_ring_advance(
            wrap_guard, 4, first=first, maxlen=maxlen
        ),
        "sentinel": _jbd2_ring_advance(
            wrap_guard, 5, first=first, maxlen=maxlen
        ),
    }
    assert tuple(logical.values()) == (
        wrap_guard,
        maxlen - 2,
        maxlen - 1,
        first,
        first + 1,
        first + 2,
    )
    assert len(set(logical.values())) == len(logical)
    journal_map = _ext4_journal_physical_map(
        image, (0, *logical.values())
    )
    physical = {
        name: journal_map[position] for name, position in logical.items()
    }
    head_offset = journal0_physical * block_size + 0x58
    matching_head_patches = [
        patch for patch in source_patches if patch[0] == head_offset
    ]
    assert matching_head_patches == [
        (head_offset, struct.pack(">I", fixture_guard))
    ]
    wrap_source_patches = tuple(
        (offset, struct.pack(">I", wrap_guard))
        if offset == head_offset
        else (offset, payload)
        for offset, payload in source_patches
    )
    sequence_offset = journal0_physical * block_size + 0x18
    source_sequence = 0xFFFF_FFFA
    wrap_source_patches += (
        (sequence_offset, struct.pack(">I", source_sequence)),
    )
    wrap_standard = bytearray(standard)
    struct.pack_into(">I", wrap_standard, 0x18, source_sequence)
    struct.pack_into(">I", wrap_standard, 0x58, wrap_guard)
    wrap_standard = _jbd2_super_with_checksum(wrap_standard)

    first_tid = (source_sequence + 1) & 0xFFFF_FFFF
    first_reset_sequence = (first_tid + 2) & 0xFFFF_FFFF
    second_tid = (first_tid + 3) & 0xFFFF_FFFF
    second_reset_sequence = (first_tid + 5) & 0xFFFF_FFFF
    final_next_tid = (first_tid + 6) & 0xFFFF_FFFF
    deactivation_sequence = (second_reset_sequence + 1) & 0xFFFF_FFFF
    deactivation_next_tid = (deactivation_sequence + 1) & 0xFFFF_FFFF
    assert (
        first_tid,
        first_reset_sequence,
        second_tid,
        second_reset_sequence,
        final_next_tid,
    ) == (0xFFFF_FFFB, 0xFFFF_FFFD, 0xFFFF_FFFE, 0, 1)
    media_path = tmp_path / "jbd2-checkpoint-persistent-wrap.img"
    try:
        output, trace, media_sha256 = run_recovery_forth(
            image,
            media_path,
            [
                "CREATE _PC-META1 1024 ALLOT _PC-META1 1024 0xA5 FILL",
                "0xC03B3998 _PC-META1 _EXT4-BE32!",
                "CREATE _PC-META2 1024 ALLOT _PC-META2 1024 0x3C FILL",
                "0xC03B3998 _PC-META2 _EXT4-BE32!",
                "CREATE _PC-DATA1 1024 ALLOT _PC-DATA1 1024 0x5A FILL",
                "CREATE _PC-DATA2 1024 ALLOT _PC-DATA2 1024 0xC3 FILL",
                "T-ARENA CONSTANT _PC-ARENA",
                (
                    "_PC-ARENA T-VOLUME EXT4-NEW "
                    "CONSTANT _PC-MOUNT-IOR CONSTANT _PC-V"
                ),
                "_PC-V _EXT4-CTX CONSTANT _PC-CTX",
                (
                    "1 1 1 _PC-CTX _EXT4-JWR-ENSURE "
                    "CONSTANT _PC-E-IOR CONSTANT _PC-W"
                ),
                "_PC-ARENA ARENA-USED CONSTANT _PC-ARENA-USED",
                "_PC-W _EXT4-JWR-ACTIVATE CONSTANT _PC-A-IOR",
                (
                    "1 1 1 _PC-W _EXT4-JTX-BEGIN "
                    "CONSTANT _PC-B1-IOR CONSTANT _PC-T1"
                ),
                (
                    "_PC-META1 30000 _PC-T1 _EXT4-JTX-META-PUT "
                    "CONSTANT _PC-M1-IOR"
                ),
                (
                    "_PC-DATA1 30001 _PC-T1 _EXT4-JTX-DATA-PUT "
                    "CONSTANT _PC-D1-IOR"
                ),
                "30002 _PC-T1 _EXT4-JTX-REVOKE CONSTANT _PC-R1-IOR",
                "_PC-T1 _EXT4-JTX-EMIT CONSTANT _PC-EMIT1-IOR",
                "_PC-T1 _EXT4-JTX-CHECKPOINT CONSTANT _PC-CP1-IOR",
                "_PC-ARENA ARENA-USED CONSTANT _PC-USED-AFTER-CP1",
                (
                    "_PC-MOUNT-IOR 0= _PC-E-IOR 0= AND "
                    "_PC-A-IOR 0= AND _PC-B1-IOR 0= AND "
                    "_PC-T1 _PC-W = AND _PC-M1-IOR 0= AND "
                    "_PC-D1-IOR 0= AND _PC-R1-IOR 0= AND "
                    "_PC-EMIT1-IOR 0= AND _PC-CP1-IOR 0= AND"
                ),
                (
                    "_PC-W _EXT4-JWR-VALID? AND "
                    "_PC-W _EXT4-JWR.STATE + @ _EXT4-JWR-IDLE = AND "
                    "_PC-W _EXT4-JWR-IDLE-CLEAN? AND "
                    "_PC-W _EXT4-JWR.FAULT + @ 0= AND "
                    "_PC-W _EXT4-JWR.EPOCH + @ 1 = AND"
                ),
                (
                    f"_PC-W _EXT4-JWR.HEAD + @ {wrap_guard} = AND "
                    f"_PC-W _EXT4-JWR.TAIL + @ {wrap_guard} = AND "
                    f"_PC-W _EXT4-JWR.FREE + @ {ring_capacity} = AND "
                    f"_PC-W _EXT4-JWR.NEXT-TID + @ "
                    f"{second_tid} = AND"
                ),
                (
                    "_PC-W _EXT4-JWR.META-ENTRIES + @ "
                    "_EXT4-JWR-IMAGE-ENTRY-CELLS CELLS "
                    "_EXT4-BYTES-ZERO? AND "
                    "_PC-W _EXT4-JWR.DATA-ENTRIES + @ "
                    "_EXT4-JWR-IMAGE-ENTRY-CELLS CELLS "
                    "_EXT4-BYTES-ZERO? AND "
                    "_PC-W _EXT4-JWR.REVOKE-ENTRIES + @ "
                    "_EXT4-JWR-REVOKE-ENTRY-CELLS CELLS "
                    "_EXT4-BYTES-ZERO? AND"
                ),
                (
                    "_PC-W _EXT4-JWR.META-HASH + @ "
                    "_PC-W _EXT4-JWR.META-SLOTS + @ CELLS "
                    "_EXT4-BYTES-ZERO? AND "
                    "_PC-W _EXT4-JWR.DATA-HASH + @ "
                    "_PC-W _EXT4-JWR.DATA-SLOTS + @ CELLS "
                    "_EXT4-BYTES-ZERO? AND "
                    "_PC-W _EXT4-JWR.REVOKE-HASH + @ "
                    "_PC-W _EXT4-JWR.REVOKE-SLOTS + @ CELLS "
                    "_EXT4-BYTES-ZERO? AND"
                ),
                (
                    "_PC-W _EXT4-JWR.META-IMAGES + @ "
                    "_PC-W _EXT4-JWR.BSIZE + @ _EXT4-BYTES-ZERO? AND "
                    "_PC-W _EXT4-JWR.DATA-IMAGES + @ "
                    "_PC-W _EXT4-JWR.BSIZE + @ _EXT4-BYTES-ZERO? AND"
                ),
                (
                    "_PC-CTX _EXT4-C.RECOVERY + @ 0<> AND "
                    "_PC-CTX _EXT4-C.J.WRITE-ACTIVE + @ 0<> AND "
                    "_PC-CTX _EXT4-C.J.START + @ 0= AND "
                    f"_PC-CTX _EXT4-C.J.SEQUENCE + @ "
                    f"{first_reset_sequence} = AND "
                    f"_PC-CTX _EXT4-C.J.NEXT-SEQUENCE + @ "
                    f"{second_tid} = AND"
                ),
                (
                    f"_PC-CTX _EXT4-C.J.HEAD + @ {wrap_guard} = AND "
                    f"_PC-CTX _EXT4-C.J.CURSOR + @ {wrap_guard} = AND "
                    "_PC-CTX _EXT4-C.J.WITNESS + @ _EXT4-JW-NONE = AND "
                    "_PC-CTX _EXT4-C.J.ANCHOR + @ 0= AND "
                    "_PC-CTX _EXT4-C.J.CLEANUP + @ _EXT4-JC-NONE = AND"
                ),
                (
                    "_PC-CTX _EXT4-C.J.PRIMARY-TORN + @ 0= AND "
                    "_PC-CTX _EXT4-C.SUPER-TORN + @ 0= AND "
                    "_PC-CTX _EXT4-C.J.WRITER-CURRENT + @ 0<> AND "
                    "_PC-CTX _EXT4-C.SB + _EXT4-SUPER-CHECKSUM? AND "
                    "_PC-CTX _EXT4-C.SB + _EXT4-SB.INCOMPAT + L@ "
                    "_EXT4-INCOMPAT-RECOVER AND 0<> AND"
                ),
                (
                    "_PC-V V.FLAGS @ VFS-F-DIRTY AND 0<> AND "
                    "_PC-V V.FLAGS @ VFS-F-RO AND 0<> AND "
                    "_PC-USED-AFTER-CP1 _PC-ARENA-USED = AND "
                    'IF ." EXT4-JTX-CHECKPOINT-FIRST-IDLE" THEN'
                ),
                (
                    "1 1 1 _PC-W _EXT4-JTX-BEGIN "
                    "CONSTANT _PC-B2-IOR CONSTANT _PC-T2"
                ),
                (
                    "_PC-META2 30000 _PC-T2 _EXT4-JTX-META-PUT "
                    "CONSTANT _PC-M2-IOR"
                ),
                (
                    "_PC-DATA2 30001 _PC-T2 _EXT4-JTX-DATA-PUT "
                    "CONSTANT _PC-D2-IOR"
                ),
                "30002 _PC-T2 _EXT4-JTX-REVOKE CONSTANT _PC-R2-IOR",
                "_PC-T2 _EXT4-JTX-EMIT CONSTANT _PC-EMIT2-IOR",
                "_PC-ARENA ARENA-USED CONSTANT _PC-USED-BEFORE-UNMOUNT",
                (
                    "_PC-B2-IOR 0= _PC-T2 _PC-W = AND "
                    "_PC-M2-IOR 0= AND _PC-D2-IOR 0= AND "
                    "_PC-R2-IOR 0= AND _PC-EMIT2-IOR 0= AND "
                    "_PC-W _EXT4-JWR-VALID? AND "
                    "_PC-W _EXT4-JWR.STATE + @ "
                    "_EXT4-JWR-COMMITTED = AND "
                    "_PC-W _EXT4-JWR-IDLE-CLEAN? 0= AND"
                ),
                (
                    "_PC-W _EXT4-JWR.FAULT + @ 0= AND "
                    "_PC-W _EXT4-JWR.EPOCH + @ 2 = AND "
                    "_PC-W _EXT4-JWR.META-USED + @ 1 = AND "
                    "_PC-W _EXT4-JWR.DATA-USED + @ 1 = AND "
                    "_PC-W _EXT4-JWR.REVOKE-USED + @ 1 = AND "
                    "_PC-W _EXT4-JWR.LOG-RESERVED + @ 0<> AND"
                ),
                (
                    "_PC-CTX _EXT4-C.RECOVERY + @ 0<> AND "
                    "_PC-CTX _EXT4-C.J.WRITE-ACTIVE + @ 0<> AND "
                    "_PC-CTX _EXT4-C.J.START + @ 0<> AND "
                    "_PC-CTX _EXT4-C.J.COMMITTED + @ 1 = AND "
                    "_PC-CTX _EXT4-C.J.WRITER-CURRENT + @ 0<> AND "
                    "_PC-CTX _EXT4-C.SB + _EXT4-SUPER-CHECKSUM? AND "
                    "_PC-CTX _EXT4-C.SB + _EXT4-SB.INCOMPAT + L@ "
                    "_EXT4-INCOMPAT-RECOVER AND 0<> AND"
                ),
                (
                    "_PC-V V.FLAGS @ VFS-F-DIRTY AND 0<> AND "
                    "_PC-V V.FLAGS @ VFS-F-RO AND 0<> AND "
                    "_PC-USED-BEFORE-UNMOUNT _PC-ARENA-USED = AND "
                    'IF ." EXT4-JTX-SECOND-COMMITTED" THEN'
                ),
                "_PC-W _EXT4-JWR-VALID? CONSTANT _PC-PRE-UNMOUNT-VALID",
                "0 _PC-V VFS-UNMOUNT CONSTANT _PC-UNMOUNT-IOR",
                (
                    "_PC-PRE-UNMOUNT-VALID _PC-UNMOUNT-IOR 0= AND "
                    "_PC-V V.LIFECYCLE @ VFS-L-UNMOUNTED = AND "
                    "_PC-V V.BCTX @ 0= AND "
                    "_PC-CTX _EXT4-C.RECOVERY + @ 0= AND "
                    "_PC-CTX _EXT4-C.J.WRITE-ACTIVE + @ 0= AND "
                    "_PC-CTX _EXT4-C.J.WRITER-CURRENT + @ 0= AND "
                    "_PC-CTX _EXT4-C.READY + @ 0= AND"
                ),
                (
                    "_PC-W _EXT4-JWR-SHAPE? AND "
                    "_PC-W _EXT4-JWR-VALID? 0= AND "
                    "_PC-W _EXT4-JWR.STATE + @ _EXT4-JWR-IDLE = AND "
                    "_PC-W _EXT4-JWR-IDLE-CLEAN? AND "
                    "_PC-W _EXT4-JWR.FAULT + @ 0= AND "
                    f"_PC-W _EXT4-JWR.HEAD + @ {wrap_guard} = AND "
                    f"_PC-W _EXT4-JWR.TAIL + @ {wrap_guard} = AND "
                    f"_PC-W _EXT4-JWR.FREE + @ {ring_capacity} = AND "
                    f"_PC-W _EXT4-JWR.NEXT-TID + @ "
                    f"{deactivation_next_tid} = AND"
                ),
                (
                    "_PC-V V.FLAGS @ VFS-F-DIRTY AND 0= AND "
                    "_PC-V V.FLAGS @ VFS-F-RO AND 0<> AND "
                    "_PC-ARENA ARENA-USED _PC-USED-BEFORE-UNMOUNT = AND "
                    'IF ." EXT4-JTX-CLEAN-UNMOUNTED" THEN'
                ),
            ],
            patches=wrap_source_patches,
            capture_media=media_path,
        )
        _assert_emitted(output, "EXT4-JTX-CHECKPOINT-FIRST-IDLE")
        _assert_emitted(output, "EXT4-JTX-SECOND-COMMITTED")
        _assert_emitted(output, "EXT4-JTX-CLEAN-UNMOUNTED")

        activation_trace = (
            ("write", physical["guard"] * 2, 2),
            ("flush", 0, 0),
            ("write", physical["guard"] * 2, 2),
            ("flush", 0, 0),
            ("write", journal0_physical * 2, 2),
            ("flush", 0, 0),
            ("write", 2, 2),
            ("flush", 0, 0),
            ("write", journal0_physical * 2, 2),
            ("flush", 0, 0),
            ("write", physical["guard"] * 2, 2),
            ("flush", 0, 0),
        )
        emission_trace = (
            ("write", data_home * 2, 2),
            ("write", physical["descriptor"] * 2, 2),
            ("write", physical["payload"] * 2, 2),
            ("write", physical["revoke"] * 2, 2),
            ("write", physical["commit"] * 2, 2),
            ("write", physical["sentinel"] * 2, 2),
            ("flush", 0, 0),
            ("write", physical["guard"] * 2, 2),
            ("flush", 0, 0),
            ("write", physical["guard"] * 2, 2),
            ("flush", 0, 0),
            ("write", journal0_physical * 2, 2),
            ("flush", 0, 0),
            ("write", physical["commit"] * 2, 2),
            ("flush", 0, 0),
        )
        checkpoint_trace = (
            ("write", metadata_home * 2, 2),
            ("flush", 0, 0),
            ("write", physical["guard"] * 2, 2),
            ("flush", 0, 0),
            ("write", physical["guard"] * 2, 2),
            ("flush", 0, 0),
            ("write", journal0_physical * 2, 2),
            ("flush", 0, 0),
            ("write", journal0_physical * 2, 2),
            ("flush", 0, 0),
            ("write", physical["guard"] * 2, 2),
            ("flush", 0, 0),
        )
        deactivation_trace = (
            ("flush", 0, 0),
            ("write", physical["guard"] * 2, 2),
            ("flush", 0, 0),
            ("write", physical["guard"] * 2, 2),
            ("flush", 0, 0),
            ("write", journal0_physical * 2, 2),
            ("flush", 0, 0),
            ("write", 2, 2),
            ("flush", 0, 0),
            ("write", journal0_physical * 2, 2),
            ("flush", 0, 0),
            ("write", physical["guard"] * 2, 2),
            ("flush", 0, 0),
        )
        assert trace == (
            activation_trace
            + emission_trace
            + checkpoint_trace
            + emission_trace
            + checkpoint_trace
            + deactivation_trace
        )
        assert trace.count(("write", 2, 2)) == 2
        assert media_path.is_file()
        assert media_path.stat().st_blocks * 512 < media_path.stat().st_size
        assert _sha256(media_path) == media_sha256

        with media_path.open("rb") as source:
            def read_block(physical_block: int) -> bytes:
                source.seek(physical_block * block_size)
                payload = source.read(block_size)
                assert len(payload) == block_size
                return payload

            final_super = read_block(layout["primary_super"])
            final_journal = read_block(journal0_physical)
            final_guard = read_block(physical["guard"])
            descriptor = read_block(physical["descriptor"])
            payload = read_block(physical["payload"])
            revoke = read_block(physical["revoke"])
            commit = read_block(physical["commit"])
            sentinel = read_block(physical["sentinel"])
            metadata_after = read_block(metadata_home)
            data_after = read_block(data_home)
            revoke_after = read_block(revoke_home)

        assert final_super == clean_super
        assert final_super != dirty_super
        expected_journal = bytearray(wrap_standard)
        struct.pack_into(">I", expected_journal, 0x18, deactivation_sequence)
        struct.pack_into(">I", expected_journal, 0x1C, 0)
        struct.pack_into(">I", expected_journal, 0x58, wrap_guard)
        expected_journal = _jbd2_super_with_checksum(expected_journal)
        assert final_journal == expected_journal
        assert final_guard == bytes(block_size)
        assert struct.unpack_from(">III", descriptor, 0) == (
            0xC03B3998,
            1,
            second_tid,
        )
        assert payload == bytes(4) + metadata_image_2[4:]
        assert struct.unpack_from(">III", revoke, 0) == (
            0xC03B3998,
            5,
            second_tid,
        )
        expected_commit = bytearray(block_size)
        struct.pack_into(">III", expected_commit, 0, 0xC03B3998, 2, second_tid)
        expected_commit = _jbd2_commit_with_checksum(
            expected_commit, expected_journal[0x30:0x40], second_tid
        )
        assert commit == expected_commit
        assert sentinel == bytes(block_size)
        assert metadata_after == metadata_image_2
        assert data_after == data_image_2
        assert revoke_after == revoke_before

        remount_output, remount_trace, remount_sha256 = run_recovery_forth(
            media_path,
            media_path,
            [
                (
                    "T-ARENA T-VOLUME EXT4-NEW "
                    "CONSTANT _CU-MOUNT-IOR CONSTANT _CU-V"
                ),
                "_CU-V _EXT4-CTX CONSTANT _CU-CTX",
                (
                    "_CU-MOUNT-IOR 0= "
                    "_CU-V V.LIFECYCLE @ VFS-L-MOUNTED = AND "
                    "_CU-V _EXT4-READY? AND "
                    "_CU-CTX _EXT4-C.RECOVERY + @ 0= AND "
                    "_CU-CTX _EXT4-C.J.WRITE-ACTIVE + @ 0= AND "
                    "_CU-CTX _EXT4-C.J.START + @ 0= AND "
                    "_CU-CTX _EXT4-C.J.WITNESS + @ _EXT4-JW-NONE = AND "
                    "_CU-CTX _EXT4-C.SB + _EXT4-SUPER-CHECKSUM? AND "
                    "_CU-CTX _EXT4-C.SB + _EXT4-SB.INCOMPAT + L@ "
                    "_EXT4-INCOMPAT-RECOVER AND 0= AND "
                    'IF ." EXT4-JTX-CLEAN-REMOUNTED" THEN'
                ),
            ],
            capture_media=media_path,
        )
        _assert_emitted(remount_output, "EXT4-JTX-CLEAN-REMOUNTED")
        assert remount_trace == ()
        assert remount_sha256 == media_sha256
    finally:
        media_path.unlink(missing_ok=True)


@pytest.mark.parametrize(
    (
        "case",
        "fault_kind",
        "deactivation_ordinal",
        "sector_index",
        "byte_index",
        "read_ordinal",
        "phase_word",
    ),
    (
        pytest.param(
            "preflight-flush",
            "flush",
            1,
            0,
            0,
            0,
            "_EXT4-JWP-DEACTIVATE-PREFLIGHT",
            id="preflight-flush",
        ),
        pytest.param(
            "reset-preseed",
            "write",
            1,
            0,
            8,
            0,
            "_EXT4-JWP-DEACTIVATE-RESET",
            id="W1-reset-preseed",
        ),
        pytest.param(
            "reset-guard",
            "write",
            2,
            0,
            1,
            0,
            "_EXT4-JWP-DEACTIVATE-RESET",
            id="W2-reset-guard",
        ),
        pytest.param(
            "reset-primary",
            "write",
            3,
            0,
            200,
            0,
            "_EXT4-JWP-DEACTIVATE-RESET",
            id="W3-reset-primary",
        ),
        pytest.param(
            "reset-flush",
            "flush",
            4,
            0,
            0,
            0,
            "_EXT4-JWP-DEACTIVATE-RESET-FLUSH",
            id="reset-flush",
        ),
        pytest.param(
            "ext4-super",
            "write",
            4,
            1,
            0,
            0,
            "_EXT4-JWP-DEACTIVATE-SUPER",
            id="W4-ext4-super",
        ),
        pytest.param(
            "super-flush",
            "flush",
            5,
            0,
            0,
            0,
            "_EXT4-JWP-DEACTIVATE-SUPER-FLUSH",
            id="super-flush",
        ),
        pytest.param(
            "primary-proof-read",
            "read",
            4,
            0,
            0,
            1,
            "_EXT4-JWP-DEACTIVATE-WITNESS-CLEAR",
            id="primary-proof-read",
        ),
        pytest.param(
            "anchor-proof-read",
            "read",
            4,
            0,
            0,
            2,
            "_EXT4-JWP-DEACTIVATE-WITNESS-CLEAR",
            id="anchor-proof-read",
        ),
        pytest.param(
            "witness-clear",
            "write",
            5,
            0,
            200,
            0,
            "_EXT4-JWP-DEACTIVATE-WITNESS-CLEAR",
            id="W5-witness-clear",
        ),
        pytest.param(
            "witness-flush",
            "flush",
            6,
            0,
            0,
            0,
            "_EXT4-JWP-DEACTIVATE-WITNESS-FLUSH",
            id="witness-flush",
        ),
        pytest.param(
            "guard-retire",
            "write",
            6,
            0,
            200,
            0,
            "_EXT4-JWP-DEACTIVATE-GUARD-RETIRE",
            id="W6-guard-retire",
        ),
        pytest.param(
            "guard-flush",
            "flush",
            7,
            0,
            0,
            0,
            "_EXT4-JWP-DEACTIVATE-GUARD-FLUSH",
            id="guard-flush",
        ),
        pytest.param(
            "final-proof-read",
            "read",
            6,
            0,
            0,
            1,
            "_EXT4-JWP-DEACTIVATE-FINAL-PROOF",
            id="final-proof-read",
        ),
    ),
)
def test_jbd2_writer_deactivation_faults_quarantine_and_remount(
    writer_activation_fixture: dict[str, object],
    tmp_path: Path,
    case: str,
    fault_kind: str,
    deactivation_ordinal: int,
    sector_index: int,
    byte_index: int,
    read_ordinal: int,
    phase_word: str,
) -> None:
    """Preserve exact landing faults and converge through a fresh mount."""
    image = writer_activation_fixture["image"]
    activation_trace = writer_activation_fixture["success_trace"]
    source_patches = writer_activation_fixture["source_patches"]
    clean_super = writer_activation_fixture["clean_super"]
    standard = writer_activation_fixture["standard"]
    guard_logical = writer_activation_fixture["guard_logical"]
    guard_physical = writer_activation_fixture["guard_physical"]
    journal0_physical = writer_activation_fixture["journal0_physical"]
    assert isinstance(image, Path)
    assert isinstance(activation_trace, tuple)
    assert isinstance(source_patches, tuple)
    assert isinstance(clean_super, bytes)
    assert isinstance(standard, bytes)
    assert isinstance(guard_logical, int)
    assert isinstance(guard_physical, int)
    assert isinstance(journal0_physical, int)

    deactivation_trace = (("flush", 0, 0),) + activation_trace
    base_writes = sum(event[0] == "write" for event in activation_trace)
    base_flushes = sum(event[0] == "flush" for event in activation_trace)
    write_faults: dict[int, dict] | None = None
    read_faults: dict[tuple[int, int], dict] | None = None
    storage_faults: tuple[dict, ...] = ()
    if fault_kind == "write":
        write_faults = {
            base_writes + deactivation_ordinal: {
                "stage": "media",
                "sector_index": sector_index,
                "byte_index": byte_index,
                "result": STORAGE_RESULT_MEDIA_FAILURE,
                "command": STORAGE_CMD_WRITE,
            }
        }
    elif fault_kind == "flush":
        flush_ordinal = base_flushes + deactivation_ordinal
        storage_faults = tuple(
            {
                "stage": "flush",
                "result": STORAGE_RESULT_OK,
                "command": STORAGE_CMD_FLUSH,
            }
            for _ in range(flush_ordinal - 1)
        ) + (
            {
                "stage": "flush",
                "result": STORAGE_RESULT_FLUSH_FAILURE,
                "command": STORAGE_CMD_FLUSH,
            },
        )
    else:
        assert fault_kind == "read"
        assert read_ordinal > 0
        read_faults = {
            (base_writes + deactivation_ordinal, read_ordinal): {
                "stage": "media",
                "sector_index": sector_index,
                "result": STORAGE_RESULT_MEDIA_FAILURE,
                "command": STORAGE_CMD_READ,
            }
        }

    if fault_kind in {"write", "flush"}:
        seen = 0
        trace_cut = 0
        for index, event in enumerate(deactivation_trace, start=1):
            if event[0] == fault_kind:
                seen += 1
                if seen == deactivation_ordinal:
                    trace_cut = index
                    break
        assert trace_cut
        failed_deactivation_trace = deactivation_trace[:trace_cut]
    else:
        seen = 0
        write_index = 0
        for index, event in enumerate(deactivation_trace):
            if event[0] == "write":
                seen += 1
                if seen == deactivation_ordinal:
                    write_index = index
                    break
        assert seen == deactivation_ordinal
        trace_cut = next(
            index + 1
            for index in range(write_index + 1, len(deactivation_trace))
            if deactivation_trace[index][0] == "flush"
        )
        failed_deactivation_trace = deactivation_trace[:trace_cut]

    source_sequence = struct.unpack_from(">I", standard, 0x18)[0]
    clean_journal = bytearray(standard)
    struct.pack_into(
        ">I", clean_journal, 0x18, (source_sequence + 1) & 0xFFFF_FFFF
    )
    struct.pack_into(">I", clean_journal, 0x1C, 0)
    struct.pack_into(">I", clean_journal, 0x58, guard_logical)
    clean_journal = _jbd2_super_with_checksum(clean_journal)
    clean_checksum = struct.unpack_from("<I", clean_super, 0x3FC)[0]
    reset_anchor = bytearray(clean_journal)
    struct.pack_into(">I", reset_anchor, 0x5C, 0x414B5231)
    struct.pack_into(">I", reset_anchor, 0x60, clean_checksum)
    struct.pack_into(
        ">I", reset_anchor, 0x64, clean_checksum ^ 0xFFFF_FFFF
    )
    struct.pack_into(">I", reset_anchor, 0x68, guard_logical)
    struct.pack_into(
        ">I", reset_anchor, 0x6C, guard_logical ^ 0xFFFF_FFFF
    )
    standard_crc = _crc32c_raw(standard)
    struct.pack_into(">I", reset_anchor, 0x70, 0x414B4531)
    struct.pack_into(">I", reset_anchor, 0x74, 0xBEB4BACE)
    struct.pack_into(">I", reset_anchor, 0x78, old_head)
    struct.pack_into(
        ">I", reset_anchor, 0x7C, old_head ^ 0xFFFF_FFFF
    )
    struct.pack_into(">I", reset_anchor, 0x80, standard_crc)
    struct.pack_into(
        ">I", reset_anchor, 0x84, standard_crc ^ 0xFFFF_FFFF
    )
    reset_anchor = _jbd2_super_with_checksum(reset_anchor)

    media_path = tmp_path / f"jbd2-deactivation-{case}.img"
    try:
        output, trace, media_sha256 = run_recovery_forth(
            image,
            media_path,
            [
                (
                    "T-ARENA T-VOLUME EXT4-NEW "
                    "CONSTANT _DF-MOUNT-IOR CONSTANT _DF-V"
                ),
                "_DF-V _EXT4-CTX CONSTANT _DF-CTX",
                (
                    "1 0 0 _DF-CTX _EXT4-JWR-ENSURE "
                    "CONSTANT _DF-E-IOR CONSTANT _DF-W"
                ),
                "T-ARENA ARENA-USED CONSTANT _DF-ARENA-USED",
                "_DF-W _EXT4-JWR-ACTIVATE CONSTANT _DF-A-IOR",
                "0 _DF-V VFS-UNMOUNT CONSTANT _DF-UNMOUNT-IOR",
                (
                    "VFS-UNMOUNT-F-FORCE _DF-V VFS-UNMOUNT "
                    "CONSTANT _DF-RETRY-IOR"
                ),
                (
                    "_DF-MOUNT-IOR 0= _DF-E-IOR 0= AND "
                    "_DF-A-IOR 0= AND _DF-UNMOUNT-IOR 0<> AND "
                    "_DF-UNMOUNT-IOR VFS-IOR-DOMAIN "
                    "VFS-IOR-D-VOLUME = AND "
                    "_DF-UNMOUNT-IOR VFS-IOR-REASON VFS-R-IO = AND "
                    + (
                        "_DF-UNMOUNT-IOR VFS-IOR-FLAGS "
                        "VFS-IOR-F-PARTIAL AND 0<> AND "
                        if fault_kind == "write"
                        else ""
                    )
                    +
                    "_DF-W _EXT4-JWR.FAULT + @ "
                    "_DF-UNMOUNT-IOR = AND"
                ),
                (
                    "_DF-W _EXT4-JWR.STATE + @ _EXT4-JWR-FAULTED = AND "
                    f"_DF-W _EXT4-JWR.PHASE + @ {phase_word} = AND "
                    "_DF-W _EXT4-JWR-VALID? AND "
                    "_DF-W _EXT4-JWR-IDLE-CLEAN? 0= AND "
                    "_DF-CTX _EXT4-C.J.WRITE-ACTIVE + @ 0<> AND"
                ),
                (
                    "_DF-CTX _EXT4-C.J.WRITER-CURRENT + @ 0<> AND "
                    "_DF-CTX _EXT4-C.READY + @ 0<> AND "
                    "_DF-V V.LIFECYCLE @ VFS-L-STALE = AND "
                    "_DF-V V.BCTX @ _DF-CTX = AND "
                    "_DF-RETRY-IOR VFS-E-STALE = AND "
                    "_DF-V V.FLAGS @ VFS-F-RO AND 0<> AND "
                    "_DF-V V.FLAGS @ VFS-F-DIRTY AND 0<> AND "
                    "T-ARENA ARENA-USED _DF-ARENA-USED = AND "
                    'IF ." EXT4-JWR-DEACTIVATION-FAULT" THEN'
                ),
            ],
            patches=source_patches,
            storage_faults=storage_faults,
            write_faults_by_ordinal=write_faults,
            read_faults_by_write_and_ordinal=read_faults,
            capture_media=media_path,
        )
        _assert_emitted(output, "EXT4-JWR-DEACTIVATION-FAULT")
        assert trace == activation_trace + failed_deactivation_trace
        assert media_path.is_file()
        assert media_path.stat().st_blocks * 512 < media_path.stat().st_size
        assert _sha256(media_path) == media_sha256

        remount_output, remount_trace, remount_sha256 = run_recovery_forth(
            media_path,
            media_path,
            [
                (
                    "T-ARENA T-VOLUME EXT4-NEW "
                    "CONSTANT _DR-MOUNT-IOR CONSTANT _DR-V"
                ),
                "_DR-V _EXT4-CTX CONSTANT _DR-CTX",
                "0 _DR-V VFS-UNMOUNT CONSTANT _DR-UNMOUNT-IOR",
                (
                    "_DR-MOUNT-IOR 0= _DR-UNMOUNT-IOR 0= AND "
                    "_DR-V V.LIFECYCLE @ VFS-L-UNMOUNTED = AND "
                    "_DR-V V.BCTX @ 0= AND "
                    "_DR-CTX _EXT4-C.RECOVERY + @ 0= AND "
                    "_DR-CTX _EXT4-C.J.WRITE-ACTIVE + @ 0= AND "
                    "_DR-CTX _EXT4-C.J.START + @ 0= AND "
                    "_DR-CTX _EXT4-C.J.WITNESS + @ _EXT4-JW-NONE = AND "
                    "_DR-CTX _EXT4-C.J.WRITER-CURRENT + @ 0= AND "
                    "_DR-CTX _EXT4-C.READY + @ 0= AND "
                    "_DR-V V.FLAGS @ VFS-F-DIRTY AND 0= AND "
                    'IF ." EXT4-JWR-DEACTIVATION-REMOUNTED" THEN'
                ),
            ],
            capture_media=media_path,
        )
        _assert_emitted(remount_output, "EXT4-JWR-DEACTIVATION-REMOUNTED")
        _assert_activation_cleanup_trace(
            remount_trace,
            journal0_physical=journal0_physical,
            guard_physical=guard_physical,
        )
        assert media_path.is_file()
        assert _sha256(media_path) == remount_sha256
        final_super, final_journal, final_guard = _read_jbd2_activation_media(
            media_path, writer_activation_fixture
        )
        assert final_super == clean_super
        assert final_journal == clean_journal
        if case == "witness-flush":
            assert final_guard == reset_anchor
        elif case == "guard-retire":
            assert _sequential_prefix_merge(
                bytes(1024), reset_anchor, final_guard
            )
            assert final_guard not in {bytes(1024), reset_anchor}
        else:
            assert final_guard == bytes(1024)
        if case in {
            "witness-flush",
            "guard-retire",
            "guard-flush",
            "final-proof-read",
        }:
            assert remount_trace == ()
    finally:
        media_path.unlink(missing_ok=True)


def test_jbd2_checkpoint_rejects_corrupt_retained_image_without_io(
    writer_activation_fixture: dict[str, object], tmp_path: Path
) -> None:
    """Do not turn damaged retained arena bytes into checkpoint authority."""
    image = writer_activation_fixture["image"]
    layout = writer_activation_fixture["layout"]
    activation_trace = writer_activation_fixture["success_trace"]
    source_patches = writer_activation_fixture["source_patches"]
    dirty_super = writer_activation_fixture["dirty_super"]
    standard = writer_activation_fixture["standard"]
    guard_logical = writer_activation_fixture["guard_logical"]
    guard_physical = writer_activation_fixture["guard_physical"]
    journal0_physical = writer_activation_fixture["journal0_physical"]
    assert isinstance(image, Path)
    assert isinstance(layout, dict)
    assert isinstance(activation_trace, tuple)
    assert isinstance(source_patches, tuple)
    assert isinstance(dirty_super, bytes)
    assert isinstance(standard, bytes)
    assert isinstance(guard_logical, int)
    assert isinstance(guard_physical, int)
    assert isinstance(journal0_physical, int)

    block_size = layout["block_size"]
    assert block_size == 1024
    metadata_home = 30000
    data_home = 30001
    revoke_home = 30002
    metadata_image = (
        struct.pack(">I", 0xC03B3998) + bytes((0xA5,)) * 1020
    )
    data_image = bytes((0x5A,)) * block_size
    with image.open("rb") as source:
        source.seek(metadata_home * block_size)
        metadata_before = source.read(block_size)
        source.seek(revoke_home * block_size)
        revoke_before = source.read(block_size)
    assert len(metadata_before) == len(revoke_before) == block_size

    first = struct.unpack_from(">I", standard, 0x14)[0]
    maxlen = struct.unpack_from(">I", standard, 0x10)[0]
    logical = {
        "guard": guard_logical,
        "descriptor": _jbd2_ring_advance(
            guard_logical, 1, first=first, maxlen=maxlen
        ),
        "payload": _jbd2_ring_advance(
            guard_logical, 2, first=first, maxlen=maxlen
        ),
        "revoke": _jbd2_ring_advance(
            guard_logical, 3, first=first, maxlen=maxlen
        ),
        "commit": _jbd2_ring_advance(
            guard_logical, 4, first=first, maxlen=maxlen
        ),
        "sentinel": _jbd2_ring_advance(
            guard_logical, 5, first=first, maxlen=maxlen
        ),
    }
    journal_map = _ext4_journal_physical_map(
        image, (0, *logical.values())
    )
    physical = {
        name: journal_map[position] for name, position in logical.items()
    }
    media_path = tmp_path / "jbd2-checkpoint-corrupt-retained.img"
    try:
        output, trace, media_sha256 = run_recovery_forth(
            image,
            media_path,
            [
                "CREATE _CI-META 1024 ALLOT _CI-META 1024 0xA5 FILL",
                "0xC03B3998 _CI-META _EXT4-BE32!",
                "CREATE _CI-DATA 1024 ALLOT _CI-DATA 1024 0x5A FILL",
                "T-ARENA CONSTANT _CI-ARENA",
                (
                    "_CI-ARENA T-VOLUME EXT4-NEW "
                    "CONSTANT _CI-MOUNT-IOR CONSTANT _CI-V"
                ),
                "_CI-V _EXT4-CTX CONSTANT _CI-CTX",
                (
                    "1 1 1 _CI-CTX _EXT4-JWR-ENSURE "
                    "CONSTANT _CI-E-IOR CONSTANT _CI-W"
                ),
                "_CI-ARENA ARENA-USED CONSTANT _CI-ARENA-USED",
                "_CI-W _EXT4-JWR-ACTIVATE CONSTANT _CI-A-IOR",
                (
                    "1 1 1 _CI-W _EXT4-JTX-BEGIN "
                    "CONSTANT _CI-B-IOR CONSTANT _CI-T"
                ),
                (
                    "_CI-META 30000 _CI-T _EXT4-JTX-META-PUT "
                    "CONSTANT _CI-M-IOR"
                ),
                (
                    "_CI-DATA 30001 _CI-T _EXT4-JTX-DATA-PUT "
                    "CONSTANT _CI-D-IOR"
                ),
                "30002 _CI-T _EXT4-JTX-REVOKE CONSTANT _CI-R-IOR",
                "_CI-T _EXT4-JTX-EMIT CONSTANT _CI-EMIT-IOR",
                (
                    "_CI-W _EXT4-JWR.META-IMAGES + @ 17 + "
                    "DUP C@ 1 XOR SWAP C!"
                ),
                "_CI-T _EXT4-JTX-CHECKPOINT CONSTANT _CI-CP-IOR",
                "_CI-T _EXT4-JTX-CHECKPOINT CONSTANT _CI-RETRY-IOR",
                "_CI-T _EXT4-JTX-ABORT CONSTANT _CI-ABORT-IOR",
                (
                    "1 1 1 _CI-W _EXT4-JTX-BEGIN "
                    "CONSTANT _CI-NEW-IOR CONSTANT _CI-NEW-T"
                ),
                (
                    "_CI-MOUNT-IOR 0= _CI-E-IOR 0= AND "
                    "_CI-A-IOR 0= AND _CI-B-IOR 0= AND "
                    "_CI-M-IOR 0= AND _CI-D-IOR 0= AND "
                    "_CI-R-IOR 0= AND _CI-EMIT-IOR 0= AND "
                    "_CI-CP-IOR VFS-E-CORRUPT = AND"
                ),
                (
                    "_CI-W _EXT4-JWR.STATE + @ _EXT4-JWR-FAULTED = AND "
                    "_CI-W _EXT4-JWR.PHASE + @ "
                    "_EXT4-JWP-CHECKPOINT-PREFLIGHT = AND "
                    "_CI-W _EXT4-JWR.FAULT + @ _CI-CP-IOR = AND "
                    "_CI-W _EXT4-JWR-VALID? AND"
                ),
                (
                    "_CI-W _EXT4-JWR.META-USED + @ 1 = AND "
                    "_CI-W _EXT4-JWR.DATA-USED + @ 1 = AND "
                    "_CI-W _EXT4-JWR.REVOKE-USED + @ 1 = AND "
                    "_CI-W _EXT4-JWR.META-IMAGES + @ 17 + C@ "
                    "0xA4 = AND"
                ),
                (
                    "_CI-RETRY-IOR VFS-E-BUSY = AND "
                    "_CI-ABORT-IOR VFS-E-BUSY = AND "
                    "_CI-NEW-T 0= AND _CI-NEW-IOR VFS-E-BUSY = AND "
                    "_CI-V V.FLAGS @ VFS-F-RO AND 0<> AND "
                    "_CI-V V.FLAGS @ VFS-F-DIRTY AND 0<> AND"
                ),
                (
                    "_CI-ARENA ARENA-USED _CI-ARENA-USED = AND "
                    'IF ." EXT4-JTX-CHECKPOINT-CORRUPT-NOIO" THEN'
                ),
            ],
            patches=source_patches,
            capture_media=media_path,
        )
        _assert_emitted(output, "EXT4-JTX-CHECKPOINT-CORRUPT-NOIO")
        emission_trace = (
            ("write", data_home * 2, 2),
            ("write", physical["descriptor"] * 2, 2),
            ("write", physical["payload"] * 2, 2),
            ("write", physical["revoke"] * 2, 2),
            ("write", physical["commit"] * 2, 2),
            ("write", physical["sentinel"] * 2, 2),
            ("flush", 0, 0),
            ("write", guard_physical * 2, 2),
            ("flush", 0, 0),
            ("write", guard_physical * 2, 2),
            ("flush", 0, 0),
            ("write", journal0_physical * 2, 2),
            ("flush", 0, 0),
            ("write", physical["commit"] * 2, 2),
            ("flush", 0, 0),
        )
        assert trace == activation_trace + emission_trace
        assert media_path.is_file()
        assert media_path.stat().st_blocks * 512 < media_path.stat().st_size
        assert _sha256(media_path) == media_sha256
        superblock, journal, guard = _read_jbd2_activation_media(
            media_path, writer_activation_fixture
        )
        assert superblock == dirty_super
        assert journal == guard
        assert _jbd2_super_checksum_valid(journal)
        with media_path.open("rb") as source:
            source.seek(metadata_home * block_size)
            metadata_after = source.read(block_size)
            source.seek(data_home * block_size)
            data_after = source.read(block_size)
            source.seek(revoke_home * block_size)
            revoke_after = source.read(block_size)
        assert metadata_after == metadata_before
        assert data_after == data_image
        assert revoke_after == revoke_before
    finally:
        media_path.unlink(missing_ok=True)


@pytest.mark.parametrize(
    "case",
    (
        "descriptor-home",
        "payload",
        "revoke-home",
        "revoke-high",
        "sentinel",
    ),
)
def test_jbd2_checkpoint_rejects_coherent_log_mismatch_without_io(
    writer_activation_fixture: dict[str, object], tmp_path: Path, case: str
) -> None:
    """Bind every logged identity and payload to the retained transaction."""
    image = writer_activation_fixture["image"]
    layout = writer_activation_fixture["layout"]
    activation_trace = writer_activation_fixture["success_trace"]
    source_patches = writer_activation_fixture["source_patches"]
    dirty_super = writer_activation_fixture["dirty_super"]
    standard = writer_activation_fixture["standard"]
    guard_logical = writer_activation_fixture["guard_logical"]
    guard_physical = writer_activation_fixture["guard_physical"]
    journal0_physical = writer_activation_fixture["journal0_physical"]
    assert isinstance(image, Path)
    assert isinstance(layout, dict)
    assert isinstance(activation_trace, tuple)
    assert isinstance(source_patches, tuple)
    assert isinstance(dirty_super, bytes)
    assert isinstance(standard, bytes)
    assert isinstance(guard_logical, int)
    assert isinstance(guard_physical, int)
    assert isinstance(journal0_physical, int)

    block_size = layout["block_size"]
    assert block_size == 1024
    metadata_home = 30000
    alternate_home = 30003
    data_home = 30001
    revoke_home = 30002
    assert alternate_home < layout["blocks"]
    metadata_image = (
        struct.pack(">I", 0xC03B3998) + bytes((0xA5,)) * 1020
    )
    data_image = bytes((0x5A,)) * block_size
    with image.open("rb") as source:
        source.seek(metadata_home * block_size)
        metadata_before = source.read(block_size)
        source.seek(revoke_home * block_size)
        revoke_before = source.read(block_size)
    assert len(metadata_before) == len(revoke_before) == block_size

    first = struct.unpack_from(">I", standard, 0x14)[0]
    maxlen = struct.unpack_from(">I", standard, 0x10)[0]
    logical = {
        "guard": guard_logical,
        "descriptor": _jbd2_ring_advance(
            guard_logical, 1, first=first, maxlen=maxlen
        ),
        "payload": _jbd2_ring_advance(
            guard_logical, 2, first=first, maxlen=maxlen
        ),
        "revoke": _jbd2_ring_advance(
            guard_logical, 3, first=first, maxlen=maxlen
        ),
        "commit": _jbd2_ring_advance(
            guard_logical, 4, first=first, maxlen=maxlen
        ),
        "sentinel": _jbd2_ring_advance(
            guard_logical, 5, first=first, maxlen=maxlen
        ),
    }
    journal_map = _ext4_journal_physical_map(
        image, (0, *logical.values())
    )
    physical = {
        name: journal_map[position] for name, position in logical.items()
    }

    read_block = (
        lambda name: (
            f"{logical[name]} _CB-CTX _EXT4-READ-JBLOCK _CB-KEEP-IOR"
        )
    )
    write_block = (
        lambda name: (
            "_CB-CTX _EXT4-C.BLOCK + "
            f"{logical[name]} _CB-CTX _EXT4-WRITE-JBLOCK _CB-KEEP-IOR"
        )
    )
    mutation_lines: dict[str, tuple[str, ...]] = {
        "descriptor-home": (
            read_block("descriptor"),
            f"{alternate_home} _CB-CTX _EXT4-C.BLOCK + 12 + _EXT4-BE32!",
            (
                "_CB-CTX _EXT4-C.BLOCK + _CB-CTX "
                "_EXT4-JBD2-STAMP-BLOCK-CHECKSUM"
            ),
            write_block("descriptor"),
        ),
        "payload": (
            read_block("payload"),
            (
                "_CB-CTX _EXT4-C.BLOCK + 17 + DUP C@ "
                "1 XOR SWAP C!"
            ),
            "_CB-CTX _EXT4-C.BLOCK + _CB-MUT 1024 MOVE",
            (
                f"_CB-MUT {logical['payload']} _CB-CTX "
                "_EXT4-WRITE-JBLOCK _CB-KEEP-IOR"
            ),
            read_block("descriptor"),
            (
                "_CB-MUT _CB-W _EXT4-JWR.TX-TID + @ _CB-CTX "
                "_EXT4-JBD2-EMIT-TAG-CHECKSUM "
                "_CB-CTX _EXT4-C.BLOCK + 24 + _EXT4-BE32!"
            ),
            (
                "_CB-CTX _EXT4-C.BLOCK + _CB-CTX "
                "_EXT4-JBD2-STAMP-BLOCK-CHECKSUM"
            ),
            write_block("descriptor"),
        ),
        "revoke-home": (
            read_block("revoke"),
            "0 _CB-CTX _EXT4-C.BLOCK + 16 + _EXT4-BE32!",
            f"{metadata_home} _CB-CTX _EXT4-C.BLOCK + 20 + _EXT4-BE32!",
            (
                "_CB-CTX _EXT4-C.BLOCK + _CB-CTX "
                "_EXT4-JBD2-STAMP-BLOCK-CHECKSUM"
            ),
            write_block("revoke"),
        ),
        "revoke-high": (
            read_block("revoke"),
            "1 _CB-CTX _EXT4-C.BLOCK + 16 + _EXT4-BE32!",
            (
                "_CB-CTX _EXT4-C.BLOCK + _CB-CTX "
                "_EXT4-JBD2-STAMP-BLOCK-CHECKSUM"
            ),
            write_block("revoke"),
        ),
        "sentinel": (
            read_block("sentinel"),
            "0x5A _CB-CTX _EXT4-C.BLOCK + 17 + C!",
            write_block("sentinel"),
        ),
    }
    expected_bound = {
        "descriptor-home": (0, 0),
        "payload": (0, 0),
        "revoke-home": (1, 0),
        "revoke-high": (1, 0),
        "sentinel": (1, 1),
    }
    expected_meta_bound, expected_revoke_bound = expected_bound[case]
    mutation_writes = {
        "descriptor-home": ("descriptor",),
        "payload": ("payload", "descriptor"),
        "revoke-home": ("revoke",),
        "revoke-high": ("revoke",),
        "sentinel": ("sentinel",),
    }[case]

    media_path = tmp_path / f"jbd2-checkpoint-log-mismatch-{case}.img"
    try:
        output, trace, media_sha256 = run_recovery_forth(
            image,
            media_path,
            [
                "CREATE _CB-META 1024 ALLOT _CB-META 1024 0xA5 FILL",
                "0xC03B3998 _CB-META _EXT4-BE32!",
                "CREATE _CB-DATA 1024 ALLOT _CB-DATA 1024 0x5A FILL",
                "CREATE _CB-MUT 1024 ALLOT",
                "VARIABLE _CB-MUT-IOR",
                (
                    ": _CB-KEEP-IOR ( ior -- ) DUP IF "
                    "_CB-MUT-IOR @ 0= IF _CB-MUT-IOR ! ELSE DROP THEN "
                    "ELSE DROP THEN ;"
                ),
                "T-ARENA CONSTANT _CB-ARENA",
                (
                    "_CB-ARENA T-VOLUME EXT4-NEW "
                    "CONSTANT _CB-MOUNT-IOR CONSTANT _CB-V"
                ),
                "_CB-V _EXT4-CTX CONSTANT _CB-CTX",
                (
                    "1 1 1 _CB-CTX _EXT4-JWR-ENSURE "
                    "CONSTANT _CB-E-IOR CONSTANT _CB-W"
                ),
                "_CB-ARENA ARENA-USED CONSTANT _CB-ARENA-USED",
                "_CB-W _EXT4-JWR-ACTIVATE CONSTANT _CB-A-IOR",
                (
                    "1 1 1 _CB-W _EXT4-JTX-BEGIN "
                    "CONSTANT _CB-B-IOR CONSTANT _CB-T"
                ),
                (
                    "_CB-META 30000 _CB-T _EXT4-JTX-META-PUT "
                    "CONSTANT _CB-M-IOR"
                ),
                (
                    "_CB-DATA 30001 _CB-T _EXT4-JTX-DATA-PUT "
                    "CONSTANT _CB-D-IOR"
                ),
                "30002 _CB-T _EXT4-JTX-REVOKE CONSTANT _CB-R-IOR",
                "_CB-T _EXT4-JTX-EMIT CONSTANT _CB-EMIT-IOR",
                *mutation_lines[case],
                "_EXT4-FLUSH _CB-KEEP-IOR",
                (
                    "_EXT4-JSCAN-PREFLIGHT _CB-CTX _EXT4-JSCAN "
                    "CONSTANT _CB-GENERIC-IOR"
                ),
                "_CB-T _EXT4-JTX-CHECKPOINT CONSTANT _CB-CP-IOR",
                "_CB-T _EXT4-JTX-CHECKPOINT CONSTANT _CB-RETRY-IOR",
                (
                    "1 1 1 _CB-W _EXT4-JTX-BEGIN "
                    "CONSTANT _CB-NEW-IOR CONSTANT _CB-NEW-T"
                ),
                (
                    "_CB-MOUNT-IOR 0= _CB-E-IOR 0= AND "
                    "_CB-A-IOR 0= AND _CB-B-IOR 0= AND "
                    "_CB-M-IOR 0= AND _CB-D-IOR 0= AND "
                    "_CB-R-IOR 0= AND _CB-EMIT-IOR 0= AND "
                    "_CB-MUT-IOR @ 0= AND _CB-GENERIC-IOR 0= AND "
                    "_CB-CP-IOR 0<> AND"
                ),
                (
                    "_CB-W _EXT4-JWR.STATE + @ _EXT4-JWR-FAULTED = AND "
                    "_CB-W _EXT4-JWR.PHASE + @ "
                    "_EXT4-JWP-CHECKPOINT-PREFLIGHT = AND "
                    "_CB-W _EXT4-JWR.FAULT + @ _CB-CP-IOR = AND "
                    "_CB-W _EXT4-JWR-VALID? AND"
                ),
                (
                    f"_EXT4-JSB-META-BOUND @ {expected_meta_bound} = AND "
                    f"_EXT4-JSB-REVOKE-BOUND @ {expected_revoke_bound} "
                    "= AND _EXT4-JSB-WRITER @ 0= AND"
                ),
                (
                    "_CB-W _EXT4-JWR.META-USED + @ 1 = AND "
                    "_CB-W _EXT4-JWR.DATA-USED + @ 1 = AND "
                    "_CB-W _EXT4-JWR.REVOKE-USED + @ 1 = AND "
                    "_CB-RETRY-IOR VFS-E-BUSY = AND"
                ),
                (
                    "_CB-NEW-T 0= AND _CB-NEW-IOR VFS-E-BUSY = AND "
                    "_CB-V V.FLAGS @ VFS-F-RO AND 0<> AND "
                    "_CB-V V.FLAGS @ VFS-F-DIRTY AND 0<> AND "
                    "_CB-ARENA ARENA-USED _CB-ARENA-USED = AND "
                    'IF ." EXT4-JTX-CHECKPOINT-LOG-MISMATCH-NOIO" THEN'
                ),
            ],
            patches=source_patches,
            capture_media=media_path,
        )
        _assert_emitted(output, "EXT4-JTX-CHECKPOINT-LOG-MISMATCH-NOIO")
        emission_trace = (
            ("write", data_home * 2, 2),
            ("write", physical["descriptor"] * 2, 2),
            ("write", physical["payload"] * 2, 2),
            ("write", physical["revoke"] * 2, 2),
            ("write", physical["commit"] * 2, 2),
            ("write", physical["sentinel"] * 2, 2),
            ("flush", 0, 0),
            ("write", guard_physical * 2, 2),
            ("flush", 0, 0),
            ("write", guard_physical * 2, 2),
            ("flush", 0, 0),
            ("write", journal0_physical * 2, 2),
            ("flush", 0, 0),
            ("write", physical["commit"] * 2, 2),
            ("flush", 0, 0),
        )
        mutation_trace = tuple(
            ("write", physical[name] * 2, 2) for name in mutation_writes
        ) + (("flush", 0, 0),)
        assert trace == activation_trace + emission_trace + mutation_trace
        assert media_path.is_file()
        assert media_path.stat().st_blocks * 512 < media_path.stat().st_size
        assert _sha256(media_path) == media_sha256
        superblock, journal, guard = _read_jbd2_activation_media(
            media_path, writer_activation_fixture
        )
        assert superblock == dirty_super
        assert journal == guard
        assert _jbd2_super_checksum_valid(journal)
        with media_path.open("rb") as source:
            source.seek(metadata_home * block_size)
            metadata_after = source.read(block_size)
            source.seek(data_home * block_size)
            data_after = source.read(block_size)
            source.seek(revoke_home * block_size)
            revoke_after = source.read(block_size)
        assert metadata_after == metadata_before
        assert data_after == data_image
        assert revoke_after == revoke_before
    finally:
        media_path.unlink(missing_ok=True)


@pytest.mark.parametrize(
    (
        "case",
        "fault_kind",
        "checkpoint_ordinal",
        "phase_word",
        "expected_current",
        "expected_valid",
    ),
    (
        pytest.param(
            "home-flush",
            "flush",
            1,
            "_EXT4-JWP-CHECKPOINT-HOME-FLUSH",
            True,
            True,
            id="home-flush",
        ),
        pytest.param(
            "guard-flush",
            "flush",
            6,
            "_EXT4-JWP-CHECKPOINT-GUARD-FLUSH",
            True,
            True,
            id="guard-flush",
        ),
        pytest.param(
            "post-home-proof-read",
            "read",
            1,
            "_EXT4-JWP-CHECKPOINT-PROOF",
            True,
            True,
            id="post-home-proof-read",
        ),
        pytest.param(
            "final-proof-read",
            "read",
            6,
            "_EXT4-JWP-CHECKPOINT-FINAL-PROOF",
            False,
            False,
            id="final-proof-read",
        ),
    ),
)
def test_jbd2_checkpoint_flush_and_proof_faults_quarantine(
    writer_activation_fixture: dict[str, object],
    tmp_path: Path,
    case: str,
    fault_kind: str,
    checkpoint_ordinal: int,
    phase_word: str,
    expected_current: bool,
    expected_valid: bool,
) -> None:
    """Latch representative flush and reread failures without releasing RAM."""
    image = writer_activation_fixture["image"]
    layout = writer_activation_fixture["layout"]
    activation_trace = writer_activation_fixture["success_trace"]
    source_patches = writer_activation_fixture["source_patches"]
    standard = writer_activation_fixture["standard"]
    guard_logical = writer_activation_fixture["guard_logical"]
    guard_physical = writer_activation_fixture["guard_physical"]
    journal0_physical = writer_activation_fixture["journal0_physical"]
    assert isinstance(image, Path)
    assert isinstance(layout, dict)
    assert isinstance(activation_trace, tuple)
    assert isinstance(source_patches, tuple)
    assert isinstance(standard, bytes)
    assert isinstance(guard_logical, int)
    assert isinstance(guard_physical, int)
    assert isinstance(journal0_physical, int)

    block_size = layout["block_size"]
    assert block_size == 1024
    metadata_home = 30000
    data_home = 30001
    revoke_home = 30002
    first = struct.unpack_from(">I", standard, 0x14)[0]
    maxlen = struct.unpack_from(">I", standard, 0x10)[0]
    logical = {
        "guard": guard_logical,
        "descriptor": _jbd2_ring_advance(
            guard_logical, 1, first=first, maxlen=maxlen
        ),
        "payload": _jbd2_ring_advance(
            guard_logical, 2, first=first, maxlen=maxlen
        ),
        "revoke": _jbd2_ring_advance(
            guard_logical, 3, first=first, maxlen=maxlen
        ),
        "commit": _jbd2_ring_advance(
            guard_logical, 4, first=first, maxlen=maxlen
        ),
        "sentinel": _jbd2_ring_advance(
            guard_logical, 5, first=first, maxlen=maxlen
        ),
    }
    journal_map = _ext4_journal_physical_map(
        image, (0, *logical.values())
    )
    physical = {
        name: journal_map[position] for name, position in logical.items()
    }
    emission_trace = (
        ("write", data_home * 2, 2),
        ("write", physical["descriptor"] * 2, 2),
        ("write", physical["payload"] * 2, 2),
        ("write", physical["revoke"] * 2, 2),
        ("write", physical["commit"] * 2, 2),
        ("write", physical["sentinel"] * 2, 2),
        ("flush", 0, 0),
        ("write", guard_physical * 2, 2),
        ("flush", 0, 0),
        ("write", guard_physical * 2, 2),
        ("flush", 0, 0),
        ("write", journal0_physical * 2, 2),
        ("flush", 0, 0),
        ("write", physical["commit"] * 2, 2),
        ("flush", 0, 0),
    )
    checkpoint_trace = (
        ("write", metadata_home * 2, 2),
        ("flush", 0, 0),
        ("write", guard_physical * 2, 2),
        ("flush", 0, 0),
        ("write", guard_physical * 2, 2),
        ("flush", 0, 0),
        ("write", journal0_physical * 2, 2),
        ("flush", 0, 0),
        ("write", journal0_physical * 2, 2),
        ("flush", 0, 0),
        ("write", guard_physical * 2, 2),
        ("flush", 0, 0),
    )
    expected_checkpoint_trace = checkpoint_trace[: checkpoint_ordinal * 2]
    base_flushes = sum(
        event[0] == "flush" for event in activation_trace + emission_trace
    )
    base_writes = sum(
        event[0] == "write" for event in activation_trace + emission_trace
    )
    storage_faults: tuple[dict, ...] = ()
    read_faults: dict[tuple[int, int], dict] | None = None
    if fault_kind == "flush":
        flush_ordinal = base_flushes + checkpoint_ordinal
        storage_faults = tuple(
            {
                "stage": "flush",
                "result": STORAGE_RESULT_OK,
                "command": STORAGE_CMD_FLUSH,
            }
            for _ in range(flush_ordinal - 1)
        ) + (
            {
                "stage": "flush",
                "result": STORAGE_RESULT_FLUSH_FAILURE,
                "command": STORAGE_CMD_FLUSH,
            },
        )
    else:
        assert fault_kind == "read"
        read_faults = {
            (base_writes + checkpoint_ordinal, 1): {
                "stage": "media",
                "sector_index": 0,
                "result": STORAGE_RESULT_MEDIA_FAILURE,
                "command": STORAGE_CMD_READ,
            }
        }

    expected_current_cell = -1 if expected_current else 0
    expected_valid_cell = -1 if expected_valid else 0
    media_path = tmp_path / f"jbd2-checkpoint-{case}.img"
    try:
        output, trace, media_sha256 = run_recovery_forth(
            image,
            media_path,
            [
                "CREATE _QF-META 1024 ALLOT _QF-META 1024 0xA5 FILL",
                "0xC03B3998 _QF-META _EXT4-BE32!",
                "CREATE _QF-DATA 1024 ALLOT _QF-DATA 1024 0x5A FILL",
                "T-ARENA CONSTANT _QF-ARENA",
                (
                    "_QF-ARENA T-VOLUME EXT4-NEW "
                    "CONSTANT _QF-MOUNT-IOR CONSTANT _QF-V"
                ),
                "_QF-V _EXT4-CTX CONSTANT _QF-CTX",
                (
                    "1 1 1 _QF-CTX _EXT4-JWR-ENSURE "
                    "CONSTANT _QF-E-IOR CONSTANT _QF-W"
                ),
                "_QF-ARENA ARENA-USED CONSTANT _QF-ARENA-USED",
                "_QF-W _EXT4-JWR-ACTIVATE CONSTANT _QF-A-IOR",
                (
                    "1 1 1 _QF-W _EXT4-JTX-BEGIN "
                    "CONSTANT _QF-B-IOR CONSTANT _QF-T"
                ),
                (
                    "_QF-META 30000 _QF-T _EXT4-JTX-META-PUT "
                    "CONSTANT _QF-M-IOR"
                ),
                (
                    "_QF-DATA 30001 _QF-T _EXT4-JTX-DATA-PUT "
                    "CONSTANT _QF-D-IOR"
                ),
                "30002 _QF-T _EXT4-JTX-REVOKE CONSTANT _QF-R-IOR",
                "_QF-T _EXT4-JTX-EMIT CONSTANT _QF-EMIT-IOR",
                "_QF-T _EXT4-JTX-CHECKPOINT CONSTANT _QF-CP-IOR",
                "_QF-T _EXT4-JTX-CHECKPOINT CONSTANT _QF-RETRY-IOR",
                (
                    "1 1 1 _QF-W _EXT4-JTX-BEGIN "
                    "CONSTANT _QF-NEW-IOR CONSTANT _QF-NEW-T"
                ),
                (
                    "_QF-MOUNT-IOR 0= _QF-E-IOR 0= AND "
                    "_QF-A-IOR 0= AND _QF-B-IOR 0= AND "
                    "_QF-M-IOR 0= AND _QF-D-IOR 0= AND "
                    "_QF-R-IOR 0= AND _QF-EMIT-IOR 0= AND "
                    "_QF-CP-IOR 0<> AND CONSTANT _QF-BASE"
                ),
                (
                    "_QF-W _EXT4-JWR.STATE + @ _EXT4-JWR-FAULTED = "
                    f"_QF-W _EXT4-JWR.PHASE + @ {phase_word} = AND "
                    "_QF-W _EXT4-JWR.FAULT + @ _QF-CP-IOR = AND "
                    "CONSTANT _QF-STATE"
                ),
                (
                    "_QF-CTX _EXT4-C.J.WRITER-CURRENT + @ "
                    f"{expected_current_cell} = "
                    "_QF-W _EXT4-JWR-VALID? "
                    f"{expected_valid_cell} = AND CONSTANT _QF-CURRENT"
                ),
                (
                    "_QF-W _EXT4-JWR.META-USED + @ 1 = "
                    "_QF-W _EXT4-JWR.DATA-USED + @ 1 = AND "
                    "_QF-W _EXT4-JWR.REVOKE-USED + @ 1 = AND "
                    "_QF-W _EXT4-JWR.META-IMAGES + @ 4 + C@ "
                    "0xA5 = AND CONSTANT _QF-RETAINED"
                ),
                (
                    "_QF-RETRY-IOR 0<> _QF-NEW-T 0= AND "
                    "_QF-NEW-IOR 0<> AND "
                    "_QF-V V.FLAGS @ VFS-F-RO AND 0<> AND "
                    "_QF-V V.FLAGS @ VFS-F-DIRTY AND 0<> AND "
                    "CONSTANT _QF-BLOCKED"
                ),
                (
                    "_QF-ARENA ARENA-USED _QF-ARENA-USED = "
                    "CONSTANT _QF-ARENA-SAME"
                ),
                '_QF-BASE IF ." EXT4-JTX-CHECKPOINT-IO-BASE" THEN',
                '_QF-STATE IF ." EXT4-JTX-CHECKPOINT-IO-STATE" THEN',
                '_QF-CURRENT IF ." EXT4-JTX-CHECKPOINT-IO-CURRENT" THEN',
                '_QF-RETAINED IF ." EXT4-JTX-CHECKPOINT-IO-RETAINED" THEN',
                '_QF-BLOCKED IF ." EXT4-JTX-CHECKPOINT-IO-BLOCKED" THEN',
                '_QF-ARENA-SAME IF ." EXT4-JTX-CHECKPOINT-IO-ARENA" THEN',
                (
                    "_QF-BASE _QF-STATE AND _QF-CURRENT AND "
                    "_QF-RETAINED AND _QF-BLOCKED AND "
                    "_QF-ARENA-SAME AND "
                    'IF ." EXT4-JTX-CHECKPOINT-IO-FAULT" THEN'
                ),
            ],
            patches=source_patches,
            storage_faults=storage_faults,
            read_faults_by_write_and_ordinal=read_faults,
            capture_media=media_path,
        )
        _assert_emitted(output, "EXT4-JTX-CHECKPOINT-IO-BASE")
        _assert_emitted(output, "EXT4-JTX-CHECKPOINT-IO-STATE")
        _assert_emitted(output, "EXT4-JTX-CHECKPOINT-IO-CURRENT")
        _assert_emitted(output, "EXT4-JTX-CHECKPOINT-IO-RETAINED")
        _assert_emitted(output, "EXT4-JTX-CHECKPOINT-IO-BLOCKED")
        _assert_emitted(output, "EXT4-JTX-CHECKPOINT-IO-ARENA")
        _assert_emitted(output, "EXT4-JTX-CHECKPOINT-IO-FAULT")
        assert trace == (
            activation_trace + emission_trace + expected_checkpoint_trace
        )
        assert media_path.is_file()
        assert media_path.stat().st_blocks * 512 < media_path.stat().st_size
        assert _sha256(media_path) == media_sha256
    finally:
        media_path.unlink(missing_ok=True)


@pytest.mark.parametrize(
    (
        "case",
        "checkpoint_write",
        "sector_index",
        "byte_index",
        "phase_word",
        "expected_home_writes",
        "recovery_kind",
        "final_sequence_delta",
    ),
    (
        pytest.param(
            "home-prefix",
            1,
            0,
            8,
            "_EXT4-JWP-CHECKPOINT-HOME",
            1,
            "active",
            2,
            id="home-prefix-before-flush",
        ),
        pytest.param(
            "reset-guard-preseed-prefix",
            2,
            0,
            8,
            "_EXT4-JWP-CHECKPOINT-RESET",
            1,
            "active",
            2,
            id="reset-guard-preseed-after-home-flush",
        ),
        pytest.param(
            "reset-guard-valid-endpoint",
            3,
            0,
            1,
            "_EXT4-JWP-CHECKPOINT-RESET",
            1,
            "active",
            2,
            id="reset-guard-valid-endpoint",
        ),
        pytest.param(
            "reset-primary-prefix",
            4,
            0,
            50,
            "_EXT4-JWP-CHECKPOINT-RESET",
            0,
            "primary-retry",
            2,
            id="reset-primary-prefix",
        ),
        pytest.param(
            "standard-primary-prefix",
            5,
            0,
            200,
            "_EXT4-JWP-CHECKPOINT-WITNESS-CLEAR",
            0,
            "primary-retry",
            2,
            id="standard-primary-prefix",
        ),
        pytest.param(
            "guard-retire-prefix",
            6,
            0,
            200,
            "_EXT4-JWP-CHECKPOINT-GUARD-RETIRE",
            0,
            "empty-recovery",
            3,
            id="guard-retire-prefix",
        ),
    ),
)
def test_jbd2_checkpoint_prefix_faults_remount_and_release(
    writer_activation_fixture: dict[str, object],
    tmp_path: Path,
    case: str,
    checkpoint_write: int,
    sector_index: int,
    byte_index: int,
    phase_word: str,
    expected_home_writes: int,
    recovery_kind: str,
    final_sequence_delta: int,
) -> None:
    """Resolve one admitted prefix at each checkpoint publication write."""
    image = writer_activation_fixture["image"]
    layout = writer_activation_fixture["layout"]
    activation_trace = writer_activation_fixture["success_trace"]
    source_patches = writer_activation_fixture["source_patches"]
    clean_super = writer_activation_fixture["clean_super"]
    standard = writer_activation_fixture["standard"]
    guard_logical = writer_activation_fixture["guard_logical"]
    guard_physical = writer_activation_fixture["guard_physical"]
    journal0_physical = writer_activation_fixture["journal0_physical"]
    assert isinstance(image, Path)
    assert isinstance(layout, dict)
    assert isinstance(activation_trace, tuple)
    assert isinstance(source_patches, tuple)
    assert isinstance(clean_super, bytes)
    assert isinstance(standard, bytes)
    assert isinstance(guard_logical, int)
    assert isinstance(guard_physical, int)
    assert isinstance(journal0_physical, int)

    block_size = layout["block_size"]
    assert block_size == 1024
    metadata_home = 30000
    data_home = 30001
    revoke_home = 30002
    metadata_image = (
        struct.pack(">I", 0xC03B3998) + bytes((0xA5,)) * 1020
    )
    data_image = bytes((0x5A,)) * block_size
    with image.open("rb") as source:
        source.seek(metadata_home * block_size)
        metadata_before = source.read(block_size)
        source.seek(data_home * block_size)
        data_before = source.read(block_size)
        source.seek(revoke_home * block_size)
        revoke_before = source.read(block_size)
    assert all(
        len(payload) == block_size
        for payload in (metadata_before, data_before, revoke_before)
    )
    assert metadata_before != metadata_image
    assert data_before != data_image

    first = struct.unpack_from(">I", standard, 0x14)[0]
    maxlen = struct.unpack_from(">I", standard, 0x10)[0]
    logical = {
        "guard": guard_logical,
        "descriptor": _jbd2_ring_advance(
            guard_logical, 1, first=first, maxlen=maxlen
        ),
        "payload": _jbd2_ring_advance(
            guard_logical, 2, first=first, maxlen=maxlen
        ),
        "revoke": _jbd2_ring_advance(
            guard_logical, 3, first=first, maxlen=maxlen
        ),
        "commit": _jbd2_ring_advance(
            guard_logical, 4, first=first, maxlen=maxlen
        ),
        "sentinel": _jbd2_ring_advance(
            guard_logical, 5, first=first, maxlen=maxlen
        ),
    }
    journal_map = _ext4_journal_physical_map(
        image, (0, *logical.values())
    )
    physical = {
        name: journal_map[position] for name, position in logical.items()
    }
    source_sequence = struct.unpack_from(">I", standard, 0x18)[0]
    transaction_tid = (source_sequence + 1) & 0xFFFF_FFFF
    final_sequence = (
        transaction_tid + final_sequence_delta
    ) & 0xFFFF_FFFF
    final_next_tid = (final_sequence + 1) & 0xFFFF_FFFF

    emission_trace = (
        ("write", data_home * 2, 2),
        ("write", physical["descriptor"] * 2, 2),
        ("write", physical["payload"] * 2, 2),
        ("write", physical["revoke"] * 2, 2),
        ("write", physical["commit"] * 2, 2),
        ("write", physical["sentinel"] * 2, 2),
        ("flush", 0, 0),
        ("write", guard_physical * 2, 2),
        ("flush", 0, 0),
        ("write", guard_physical * 2, 2),
        ("flush", 0, 0),
        ("write", journal0_physical * 2, 2),
        ("flush", 0, 0),
        ("write", physical["commit"] * 2, 2),
        ("flush", 0, 0),
    )
    checkpoint_trace = (
        ("write", metadata_home * 2, 2),
        ("flush", 0, 0),
        ("write", guard_physical * 2, 2),
        ("flush", 0, 0),
        ("write", guard_physical * 2, 2),
        ("flush", 0, 0),
        ("write", journal0_physical * 2, 2),
        ("flush", 0, 0),
        ("write", journal0_physical * 2, 2),
        ("flush", 0, 0),
        ("write", guard_physical * 2, 2),
        ("flush", 0, 0),
    )
    active_recovery_trace = (
        ("write", metadata_home * 2, 2),
        ("flush", 0, 0),
        ("write", guard_physical * 2, 2),
        ("flush", 0, 0),
        ("write", guard_physical * 2, 2),
        ("flush", 0, 0),
        ("write", journal0_physical * 2, 2),
        ("flush", 0, 0),
        ("write", 2, 2),
        ("flush", 0, 0),
        ("write", journal0_physical * 2, 2),
        ("flush", 0, 0),
        ("write", guard_physical * 2, 2),
        ("flush", 0, 0),
    )
    primary_retry_trace = (
        ("flush", 0, 0),
        ("write", journal0_physical * 2, 2),
        ("flush", 0, 0),
        ("flush", 0, 0),
        ("write", 2, 2),
        ("flush", 0, 0),
        ("write", journal0_physical * 2, 2),
        ("flush", 0, 0),
        ("write", guard_physical * 2, 2),
        ("flush", 0, 0),
    )
    empty_recovery_trace = (
        ("flush", 0, 0),
        ("write", guard_physical * 2, 2),
        ("flush", 0, 0),
        ("write", guard_physical * 2, 2),
        ("flush", 0, 0),
        ("write", journal0_physical * 2, 2),
        ("flush", 0, 0),
        ("write", 2, 2),
        ("flush", 0, 0),
        ("write", journal0_physical * 2, 2),
        ("flush", 0, 0),
        ("write", guard_physical * 2, 2),
        ("flush", 0, 0),
    )
    recovery_traces = {
        "active": active_recovery_trace,
        "primary-retry": primary_retry_trace,
        "empty-recovery": empty_recovery_trace,
    }
    recovery_trace = recovery_traces[recovery_kind]
    base_write_count = sum(
        event[0] == "write" for event in activation_trace + emission_trace
    )
    fault_write_ordinal = base_write_count + checkpoint_write
    checkpoint_prefix = checkpoint_trace[: 2 * (checkpoint_write - 1) + 1]

    media_path = tmp_path / f"jbd2-checkpoint-{case}.img"
    try:
        output, trace, media_sha256 = run_recovery_forth(
            image,
            media_path,
            [
                "CREATE _CF-META 1024 ALLOT _CF-META 1024 0xA5 FILL",
                "0xC03B3998 _CF-META _EXT4-BE32!",
                "CREATE _CF-DATA 1024 ALLOT _CF-DATA 1024 0x5A FILL",
                "T-ARENA CONSTANT _CF-ARENA",
                (
                    "_CF-ARENA T-VOLUME EXT4-NEW "
                    "CONSTANT _CF-MOUNT-IOR CONSTANT _CF-V"
                ),
                "_CF-V _EXT4-CTX CONSTANT _CF-CTX",
                (
                    "1 1 1 _CF-CTX _EXT4-JWR-ENSURE "
                    "CONSTANT _CF-E-IOR CONSTANT _CF-W"
                ),
                "_CF-ARENA ARENA-USED CONSTANT _CF-USED-BEFORE",
                "_CF-W _EXT4-JWR-ACTIVATE CONSTANT _CF-A-IOR",
                (
                    "1 1 1 _CF-W _EXT4-JTX-BEGIN "
                    "CONSTANT _CF-B-IOR CONSTANT _CF-T"
                ),
                (
                    "_CF-META 30000 _CF-T _EXT4-JTX-META-PUT "
                    "CONSTANT _CF-M-IOR"
                ),
                (
                    "_CF-DATA 30001 _CF-T _EXT4-JTX-DATA-PUT "
                    "CONSTANT _CF-D-IOR"
                ),
                "30002 _CF-T _EXT4-JTX-REVOKE CONSTANT _CF-R-IOR",
                "_CF-T _EXT4-JTX-EMIT CONSTANT _CF-EMIT-IOR",
                "_CF-T _EXT4-JTX-CHECKPOINT CONSTANT _CF-CP-IOR",
                "_CF-T _EXT4-JTX-CHECKPOINT CONSTANT _CF-RETRY-IOR",
                "_CF-T _EXT4-JTX-ABORT CONSTANT _CF-ABORT-IOR",
                "_CF-W _EXT4-JWR-ACTIVATE CONSTANT _CF-A2-IOR",
                (
                    "1 1 1 _CF-W _EXT4-JTX-BEGIN "
                    "CONSTANT _CF-NEW-IOR CONSTANT _CF-NEW-T"
                ),
                (
                    "_CF-MOUNT-IOR 0= _CF-E-IOR 0= AND "
                    "_CF-A-IOR 0= AND _CF-B-IOR 0= AND "
                    "_CF-M-IOR 0= AND _CF-D-IOR 0= AND "
                    "_CF-R-IOR 0= AND _CF-EMIT-IOR 0= AND"
                ),
                (
                    "_CF-CP-IOR VFS-IOR-DOMAIN VFS-IOR-D-VOLUME = AND "
                    "_CF-CP-IOR VFS-IOR-REASON VFS-R-IO = AND "
                    "_CF-CP-IOR VFS-IOR-FLAGS VFS-IOR-F-PARTIAL "
                    "AND 0<> AND _CF-W _EXT4-JWR.FAULT + @ "
                    "_CF-CP-IOR = AND"
                ),
                (
                    "_CF-W _EXT4-JWR.STATE + @ _EXT4-JWR-FAULTED = AND "
                    f"_CF-W _EXT4-JWR.PHASE + @ {phase_word} = AND "
                    "_CF-W _EXT4-JWR-VALID? AND "
                    "_CF-V V.FLAGS @ VFS-F-RO AND 0<> AND "
                    "_CF-V V.FLAGS @ VFS-F-DIRTY AND 0<> AND"
                ),
                (
                    "_CF-W _EXT4-JWR.META-USED + @ 1 = AND "
                    "_CF-W _EXT4-JWR.DATA-USED + @ 1 = AND "
                    "_CF-W _EXT4-JWR.REVOKE-USED + @ 1 = AND "
                    "_CF-META _CF-W _EXT4-JWR.META-IMAGES + @ "
                    "1024 _EXT4-BYTES=? AND "
                    "_CF-DATA _CF-W _EXT4-JWR.DATA-IMAGES + @ "
                    "1024 _EXT4-BYTES=? AND"
                ),
                (
                    "_CF-RETRY-IOR VFS-E-BUSY = AND "
                    "_CF-ABORT-IOR VFS-E-BUSY = AND "
                    "_CF-A2-IOR VFS-E-BUSY = AND "
                    "_CF-NEW-T 0= AND _CF-NEW-IOR VFS-E-BUSY = AND "
                    "_CF-ARENA ARENA-USED _CF-USED-BEFORE = AND "
                    'IF ." EXT4-JTX-CHECKPOINT-PREFIX-FAULT" THEN'
                ),
                "_CF-V _EXT4-MOUNT CONSTANT _CF-REMOUNT-IOR",
                "_CF-ARENA ARENA-USED CONSTANT _CF-USED-AFTER-REMOUNT",
                (
                    "30000 _CF-CTX _EXT4-READ-BLOCK "
                    "CONSTANT _CF-META-HOME-IOR"
                ),
                (
                    "_CF-CTX _EXT4-C.BLOCK + _CF-META "
                    "1024 _EXT4-BYTES=? CONSTANT _CF-META-HOME"
                ),
                (
                    "30001 _CF-CTX _EXT4-READ-BLOCK "
                    "CONSTANT _CF-DATA-HOME-IOR"
                ),
                (
                    "_CF-CTX _EXT4-C.BLOCK + _CF-DATA "
                    "1024 _EXT4-BYTES=? CONSTANT _CF-DATA-HOME"
                ),
                (
                    "1 1 1 _CF-CTX _EXT4-JWR-ENSURE "
                    "CONSTANT _CF-REUSE-IOR CONSTANT _CF-REUSE-W"
                ),
                "_CF-ARENA ARENA-USED CONSTANT _CF-USED-AFTER-ENSURE",
                (
                    "1 1 1 _CF-REUSE-W _EXT4-JTX-BEGIN "
                    "CONSTANT _CF-PROBE-IOR CONSTANT _CF-PROBE-T"
                ),
                (
                    "_CF-PROBE-T _EXT4-JTX-ABORT "
                    "CONSTANT _CF-PROBE-ABORT-IOR"
                ),
                (
                    "_CF-REMOUNT-IOR 0= "
                    "_CF-V V.LIFECYCLE @ VFS-L-MOUNTED = AND "
                    "_CF-V _EXT4-READY? AND "
                    "_CF-CTX _EXT4-C.RECOVERY + @ 0= AND "
                    "_CF-CTX _EXT4-C.J.WRITE-ACTIVE + @ 0= AND "
                    "_CF-CTX _EXT4-C.J.START + @ 0= AND"
                ),
                (
                    "_CF-CTX _EXT4-C.J.WITNESS + @ _EXT4-JW-NONE = AND "
                    "_CF-CTX _EXT4-C.J.ANCHOR + @ 0= AND "
                    "_CF-CTX _EXT4-C.J.CLEANUP + @ _EXT4-JC-NONE = AND "
                    "_CF-CTX _EXT4-C.J.PRIMARY-TORN + @ 0= AND "
                    "_CF-CTX _EXT4-C.SUPER-TORN + @ 0= AND"
                ),
                (
                    f"_CF-CTX _EXT4-C.J.SEQUENCE + @ "
                    f"{final_sequence} = AND "
                    f"_CF-CTX _EXT4-C.J.HEAD + @ {guard_logical} = AND "
                    f"_CF-CTX _EXT4-C.J.HOME-WRITES + @ "
                    f"{expected_home_writes} = AND "
                    "_CF-CTX _EXT4-C.J.REPLAYED + @ 0<> AND"
                ),
                (
                    "_CF-CTX _EXT4-C.SB + _EXT4-SUPER-CHECKSUM? AND "
                    "_CF-CTX _EXT4-C.SB + _EXT4-SB.INCOMPAT + L@ "
                    "_EXT4-INCOMPAT-RECOVER AND 0= AND "
                    "_CF-META-HOME-IOR 0= AND _CF-META-HOME AND "
                    "_CF-DATA-HOME-IOR 0= AND _CF-DATA-HOME AND"
                ),
                (
                    "_CF-CTX _EXT4-C.J.WRITER + @ _CF-W = AND "
                    "_CF-CTX _EXT4-C.J.WRITER-CURRENT + @ 0<> AND "
                    "_CF-W _EXT4-JWR-VALID? AND "
                    "_CF-W _EXT4-JWR.STATE + @ _EXT4-JWR-IDLE = AND "
                    "_CF-W _EXT4-JWR-IDLE-CLEAN? AND "
                    "_CF-W _EXT4-JWR.FAULT + @ 0= AND"
                ),
                (
                    f"_CF-W _EXT4-JWR.NEXT-TID + @ "
                    f"{final_next_tid} = AND "
                    "_CF-W _EXT4-JWR.META-ENTRIES + @ @ 0= AND "
                    "_CF-W _EXT4-JWR.DATA-ENTRIES + @ @ 0= AND "
                    "_CF-W _EXT4-JWR.REVOKE-ENTRIES + @ @ 0= AND "
                    "_CF-W _EXT4-JWR.META-IMAGES + @ C@ 0= AND "
                    "_CF-W _EXT4-JWR.DATA-IMAGES + @ C@ 0= AND"
                ),
                (
                    "_CF-REUSE-IOR 0= AND _CF-REUSE-W _CF-W = AND "
                    "_CF-USED-AFTER-ENSURE _CF-USED-AFTER-REMOUNT = AND "
                    "_CF-PROBE-IOR 0= AND _CF-PROBE-T _CF-W = AND "
                    "_CF-PROBE-ABORT-IOR 0= AND "
                    'IF ." EXT4-JTX-CHECKPOINT-PREFIX-REMOUNTED" THEN'
                ),
            ],
            patches=source_patches,
            write_faults_by_ordinal={
                fault_write_ordinal: {
                    "stage": "media",
                    "sector_index": sector_index,
                    "byte_index": byte_index,
                    "result": STORAGE_RESULT_MEDIA_FAILURE,
                    "command": STORAGE_CMD_WRITE,
                }
            },
            capture_media=media_path,
        )
        _assert_emitted(output, "EXT4-JTX-CHECKPOINT-PREFIX-FAULT")
        _assert_emitted(output, "EXT4-JTX-CHECKPOINT-PREFIX-REMOUNTED")
        assert trace == (
            activation_trace
            + emission_trace
            + checkpoint_prefix
            + recovery_trace
        )
        assert media_path.is_file()
        assert media_path.stat().st_blocks * 512 < media_path.stat().st_size
        assert _sha256(media_path) == media_sha256
        superblock, journal, guard = _read_jbd2_activation_media(
            media_path, writer_activation_fixture
        )
        assert superblock == clean_super
        expected_journal = bytearray(standard)
        struct.pack_into(">I", expected_journal, 0x18, final_sequence)
        struct.pack_into(">I", expected_journal, 0x1C, 0)
        struct.pack_into(">I", expected_journal, 0x58, guard_logical)
        expected_journal = _jbd2_super_with_checksum(expected_journal)
        assert journal == expected_journal
        assert guard == bytes(block_size)
        with media_path.open("rb") as source:
            source.seek(metadata_home * block_size)
            metadata_after = source.read(block_size)
            source.seek(data_home * block_size)
            data_after = source.read(block_size)
            source.seek(revoke_home * block_size)
            revoke_after = source.read(block_size)
        assert metadata_after == metadata_image
        assert data_after == data_image
        assert revoke_after == revoke_before
    finally:
        media_path.unlink(missing_ok=True)


def test_jbd2_active_reset_publication_retries_from_emitted_commit(
    writer_activation_fixture: dict[str, object], tmp_path: Path
) -> None:
    """Converge both AKG1 guard endpoints and a torn primary publication."""
    image = writer_activation_fixture["image"]
    layout = writer_activation_fixture["layout"]
    source_patches = writer_activation_fixture["source_patches"]
    clean_super = writer_activation_fixture["clean_super"]
    dirty_super = writer_activation_fixture["dirty_super"]
    standard = writer_activation_fixture["standard"]
    guard_logical = writer_activation_fixture["guard_logical"]
    guard_physical = writer_activation_fixture["guard_physical"]
    journal0_physical = writer_activation_fixture["journal0_physical"]
    assert isinstance(image, Path)
    assert isinstance(layout, dict)
    assert isinstance(source_patches, tuple)
    assert isinstance(clean_super, bytes)
    assert isinstance(dirty_super, bytes)
    assert isinstance(standard, bytes)
    assert isinstance(guard_logical, int)
    assert isinstance(guard_physical, int)
    assert isinstance(journal0_physical, int)

    block_size = layout["block_size"]
    assert block_size == 1024
    metadata_home = 30000
    data_home = 30001
    revoke_home = 30002
    assert revoke_home < layout["blocks"]
    metadata_image = struct.pack(">I", 0xC03B3998) + bytes((0xA5,)) * 1020
    data_image = bytes((0x5A,)) * block_size
    with image.open("rb") as source:
        source.seek(metadata_home * block_size)
        metadata_before = source.read(block_size)
        source.seek(data_home * block_size)
        data_before = source.read(block_size)
        source.seek(revoke_home * block_size)
        revoke_before = source.read(block_size)
    assert all(
        len(block) == block_size
        for block in (metadata_before, data_before, revoke_before)
    )
    assert metadata_before != metadata_image
    assert data_before != data_image

    first = struct.unpack_from(">I", standard, 0x14)[0]
    maxlen = struct.unpack_from(">I", standard, 0x10)[0]
    descriptor_logical = _jbd2_ring_advance(
        guard_logical, 1, first=first, maxlen=maxlen
    )
    expected_tid = (
        struct.unpack_from(">I", standard, 0x18)[0] + 1
    ) & 0xFFFF_FFFF
    expected_active = bytearray(standard)
    struct.pack_into(">I", expected_active, 0x18, expected_tid)
    struct.pack_into(">I", expected_active, 0x1C, descriptor_logical)
    struct.pack_into(">I", expected_active, 0x28, 0x13)
    expected_active[0x50:0x54] = b"\x04\x00\x00\x00"
    struct.pack_into(">I", expected_active, 0x54, 0)
    struct.pack_into(">I", expected_active, 0x58, guard_logical)
    expected_active[0x5C:0x88] = bytes(0x2C)
    expected_active = _jbd2_super_with_checksum(expected_active)

    clean_checksum = struct.unpack_from("<I", clean_super, 0x3FC)[0]
    active_crc = _crc32c_raw(expected_active)
    expected_reset = bytearray(expected_active)
    struct.pack_into(">I", expected_reset, 0x18, (expected_tid + 2) & 0xFFFF_FFFF)
    struct.pack_into(">I", expected_reset, 0x1C, 0)
    struct.pack_into(">I", expected_reset, 0x58, guard_logical)
    struct.pack_into(">I", expected_reset, 0x5C, 0x414B5231)
    struct.pack_into(">I", expected_reset, 0x60, clean_checksum)
    struct.pack_into(">I", expected_reset, 0x64, clean_checksum ^ 0xFFFF_FFFF)
    struct.pack_into(">I", expected_reset, 0x68, guard_logical)
    struct.pack_into(">I", expected_reset, 0x6C, guard_logical ^ 0xFFFF_FFFF)
    struct.pack_into(">I", expected_reset, 0x70, 0x414B4731)
    struct.pack_into(">I", expected_reset, 0x74, 0xBEB4B8CE)
    struct.pack_into(">I", expected_reset, 0x78, expected_tid)
    struct.pack_into(">I", expected_reset, 0x7C, expected_tid ^ 0xFFFF_FFFF)
    struct.pack_into(">I", expected_reset, 0x80, active_crc)
    struct.pack_into(">I", expected_reset, 0x84, active_crc ^ 0xFFFF_FFFF)
    expected_reset = _jbd2_super_with_checksum(expected_reset)
    expected_preseed = bytearray(expected_reset)
    expected_preseed[0] = 0
    expected_preseed = bytes(expected_preseed)
    expected_standard = bytearray(expected_reset)
    expected_standard[0x5C:0x88] = bytes(0x2C)
    expected_standard = _jbd2_super_with_checksum(expected_standard)
    assert _jbd2_super_checksum_valid(expected_active)
    assert _jbd2_super_checksum_valid(expected_reset)
    assert _jbd2_super_checksum_valid(expected_standard)
    assert expected_preseed[1:] == expected_reset[1:]

    committed = tmp_path / "jbd2-active-reset-committed.img"
    working = tmp_path / "jbd2-active-reset-working.img"
    try:
        output, _emit_trace, committed_sha256 = run_recovery_forth(
            image,
            committed,
            [
                "CREATE _RR-META 1024 ALLOT _RR-META 1024 0xA5 FILL",
                "0xC03B3998 _RR-META _EXT4-BE32!",
                "CREATE _RR-DATA 1024 ALLOT _RR-DATA 1024 0x5A FILL",
                "T-ARENA T-VOLUME EXT4-NEW CONSTANT _M-IOR CONSTANT _V",
                "_V _EXT4-CTX CONSTANT _RR-CTX",
                (
                    "1 1 1 _RR-CTX _EXT4-JWR-ENSURE "
                    "CONSTANT _RR-E-IOR CONSTANT _RR-W"
                ),
                "_RR-W _EXT4-JWR-ACTIVATE CONSTANT _RR-A-IOR",
                (
                    "1 1 1 _RR-W _EXT4-JTX-BEGIN "
                    "CONSTANT _RR-B-IOR CONSTANT _RR-T"
                ),
                (
                    "_RR-META 30000 _RR-T _EXT4-JTX-META-PUT "
                    "CONSTANT _RR-M-IOR"
                ),
                (
                    "_RR-DATA 30001 _RR-T _EXT4-JTX-DATA-PUT "
                    "CONSTANT _RR-D-IOR"
                ),
                "30002 _RR-T _EXT4-JTX-REVOKE CONSTANT _RR-R-IOR",
                "_RR-T _EXT4-JTX-EMIT CONSTANT _RR-EMIT-IOR",
                (
                    "_M-IOR 0= _RR-E-IOR 0= AND _RR-A-IOR 0= AND "
                    "_RR-B-IOR 0= AND _RR-M-IOR 0= AND "
                    "_RR-D-IOR 0= AND _RR-R-IOR 0= AND "
                    "_RR-EMIT-IOR 0= AND "
                    "_RR-W _EXT4-JWR.STATE + @ _EXT4-JWR-COMMITTED = AND "
                    "_RR-CTX _EXT4-C.J.CLEANUP + @ _EXT4-JC-ACTIVE = AND "
                    'IF ." EXT4-JBD2-ACTIVE-RESET-BASE" THEN'
                ),
            ],
            patches=source_patches,
            capture_media=committed,
        )
        _assert_emitted(output, "EXT4-JBD2-ACTIVE-RESET-BASE")
        assert committed.is_file()
        assert _sha256(committed) == committed_sha256
        superblock, journal, guard = _read_jbd2_activation_media(
            committed, writer_activation_fixture
        )
        assert superblock == dirty_super
        assert journal == expected_active
        assert guard == expected_active
        with committed.open("rb") as source:
            source.seek(metadata_home * block_size)
            assert source.read(block_size) == metadata_before
            source.seek(data_home * block_size)
            assert source.read(block_size) == data_image
            source.seek(revoke_home * block_size)
            assert source.read(block_size) == revoke_before

        recovery_trace = (
            ("write", metadata_home * 2, 2),
            ("flush", 0, 0),
            ("write", guard_physical * 2, 2),
            ("flush", 0, 0),
            ("write", guard_physical * 2, 2),
            ("flush", 0, 0),
            ("write", journal0_physical * 2, 2),
            ("flush", 0, 0),
            ("write", 2, 2),
            ("flush", 0, 0),
            ("write", journal0_physical * 2, 2),
            ("flush", 0, 0),
            ("write", guard_physical * 2, 2),
            ("flush", 0, 0),
        )
        primary_retry_trace = (
            ("flush", 0, 0),
            ("write", journal0_physical * 2, 2),
            ("flush", 0, 0),
            ("flush", 0, 0),
            ("write", 2, 2),
            ("flush", 0, 0),
            ("write", journal0_physical * 2, 2),
            ("flush", 0, 0),
            ("write", guard_physical * 2, 2),
            ("flush", 0, 0),
        )
        rows = (
            ("guard-preseed", 2, 8, 1),
            ("guard-valid", 3, 1, 1),
            ("primary", 4, 50, 0),
        )
        for phase, write_ordinal, byte_index, expected_home_writes in rows:
            try:
                output, interrupted_trace, interrupted_sha256 = (
                    run_recovery_forth(
                        committed,
                        working,
                        [
                            (
                                "T-ARENA T-VOLUME EXT4-NEW "
                                "CONSTANT _M-IOR CONSTANT _V"
                            ),
                            (
                                "_M-IOR VFS-IOR-DOMAIN VFS-IOR-D-VOLUME = "
                                "_M-IOR VFS-IOR-REASON VFS-R-IO = AND "
                                "_M-IOR VFS-IOR-FLAGS VFS-IOR-F-PARTIAL "
                                "AND 0<> AND "
                                "_V V.LIFECYCLE @ VFS-L-NEW = AND "
                                'IF ." EXT4-JBD2-ACTIVE-RESET-TEAR" THEN'
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
                        capture_media=working,
                    )
                )
                _assert_emitted(output, "EXT4-JBD2-ACTIVE-RESET-TEAR")
                assert interrupted_trace == recovery_trace[
                    : 2 * (write_ordinal - 1) + 1
                ]
                assert working.is_file()
                assert _sha256(working) == interrupted_sha256

                superblock, journal, guard = _read_jbd2_activation_media(
                    working, writer_activation_fixture
                )
                assert superblock == dirty_super
                if phase == "guard-preseed":
                    torn_guard = expected_preseed[:8] + expected_active[8:]
                    assert journal == expected_active
                    assert guard == torn_guard
                    assert _sequential_prefix_merge(
                        expected_preseed, expected_active, guard
                    )
                    assert guard not in {expected_active, expected_reset}
                    assert not _jbd2_super_checksum_valid(guard)
                elif phase == "guard-valid":
                    assert journal == expected_active
                    assert guard == expected_reset
                else:
                    assert phase == "primary"
                    torn_primary = expected_reset[:50] + expected_active[50:]
                    assert guard == expected_reset
                    assert journal == torn_primary
                    assert _sequential_prefix_merge(
                        expected_reset, expected_active, journal
                    )
                    assert journal not in {expected_active, expected_reset}
                    assert journal[0x5C:0x88] == bytes(0x2C)
                    assert not _jbd2_super_checksum_valid(journal)

                with working.open("rb") as source:
                    source.seek(metadata_home * block_size)
                    assert source.read(block_size) == metadata_image
                    source.seek(data_home * block_size)
                    assert source.read(block_size) == data_image
                    source.seek(revoke_home * block_size)
                    assert source.read(block_size) == revoke_before

                output, retry_trace, retry_sha256 = run_recovery_forth(
                    working,
                    working,
                    [
                        "T-ARENA T-VOLUME EXT4-NEW CONSTANT _M-IOR CONSTANT _V",
                        "_V _EXT4-CTX CONSTANT _RRR-CTX",
                        (
                            "_M-IOR 0= _V V.LIFECYCLE @ VFS-L-MOUNTED = AND "
                            "_V _EXT4-READY? AND "
                            "_RRR-CTX _EXT4-C.RECOVERY + @ 0= AND "
                            "_RRR-CTX _EXT4-C.J.WRITE-ACTIVE + @ 0= AND "
                            "_RRR-CTX _EXT4-C.J.FEATURES + @ "
                            "_EXT4-JBD2-I-RECOVERY-REVOKE = AND "
                            "_RRR-CTX _EXT4-C.J.START + @ 0= AND "
                            "_RRR-CTX _EXT4-C.J.WITNESS + @ "
                            "_EXT4-JW-NONE = AND "
                            "_RRR-CTX _EXT4-C.J.ANCHOR + @ 0= AND "
                            "_RRR-CTX _EXT4-C.J.CLEANUP + @ "
                            "_EXT4-JC-NONE = AND "
                            "_RRR-CTX _EXT4-C.J.PRIMARY-TORN + @ 0= AND "
                            "_RRR-CTX _EXT4-C.SUPER-TORN + @ 0= AND "
                            "_RRR-CTX _EXT4-C.J.REPLAYED + @ 0<> AND "
                            "_RRR-CTX _EXT4-C.J.HOME-WRITES + @ "
                            f"{expected_home_writes} = AND "
                            "_RRR-CTX _EXT4-C.SB + _EXT4-SUPER-CHECKSUM? AND "
                            "_RRR-CTX _EXT4-C.SB + _EXT4-SB.INCOMPAT + L@ "
                            "_EXT4-INCOMPAT-RECOVER AND 0= AND "
                            'IF ." EXT4-JBD2-ACTIVE-RESET-RETRIED" THEN'
                        ),
                    ],
                    capture_media=working,
                )
                _assert_emitted(output, "EXT4-JBD2-ACTIVE-RESET-RETRIED")
                assert retry_trace == (
                    primary_retry_trace
                    if phase == "primary"
                    else recovery_trace
                )
                assert _sha256(working) == retry_sha256
                superblock, journal, guard = _read_jbd2_activation_media(
                    working, writer_activation_fixture
                )
                assert superblock == clean_super
                assert journal == expected_standard
                assert guard == bytes(block_size)
                with working.open("rb") as source:
                    source.seek(metadata_home * block_size)
                    assert source.read(block_size) == metadata_image
                    source.seek(data_home * block_size)
                    assert source.read(block_size) == data_image
                    source.seek(revoke_home * block_size)
                    assert source.read(block_size) == revoke_before
            finally:
                working.unlink(missing_ok=True)
    finally:
        committed.unlink(missing_ok=True)


@pytest.mark.parametrize(
    (
        "case",
        "write_ordinal",
        "sector_index",
        "byte_index",
        "phase_word",
        "commit_durable",
    ),
    (
        pytest.param(
            "primary-early",
            15,
            0,
            50,
            "_EXT4-JWP-ACTIVE-PRIMARY",
            False,
            id="active-primary-early",
        ),
        pytest.param(
            "primary-checksum",
            15,
            0,
            254,
            "_EXT4-JWP-ACTIVE-PRIMARY",
            False,
            id="active-primary-checksum",
        ),
        pytest.param(
            "commit-invalid",
            16,
            0,
            0,
            "_EXT4-JWP-COMMIT",
            False,
            id="commit-invalid-endpoint",
        ),
        pytest.param(
            "commit-exact",
            16,
            0,
            1,
            "_EXT4-JWP-COMMIT",
            True,
            id="commit-exact-endpoint",
        ),
    ),
)
def test_jbd2_writer_publication_faults_remount_and_rebase_in_place(
    writer_activation_fixture: dict[str, object],
    tmp_path: Path,
    case: str,
    write_ordinal: int,
    sector_index: int,
    byte_index: int,
    phase_word: str,
    commit_durable: bool,
) -> None:
    """Resolve the four publication endpoints serially on one sparse image."""
    image = writer_activation_fixture["image"]
    layout = writer_activation_fixture["layout"]
    activation_trace = writer_activation_fixture["success_trace"]
    source_patches = writer_activation_fixture["source_patches"]
    standard = writer_activation_fixture["standard"]
    guard_logical = writer_activation_fixture["guard_logical"]
    guard_physical = writer_activation_fixture["guard_physical"]
    journal0_physical = writer_activation_fixture["journal0_physical"]
    assert isinstance(image, Path)
    assert isinstance(layout, dict)
    assert isinstance(activation_trace, tuple)
    assert isinstance(source_patches, tuple)
    assert isinstance(standard, bytes)
    assert isinstance(guard_logical, int)
    assert isinstance(guard_physical, int)
    assert isinstance(journal0_physical, int)

    block_size = layout["block_size"]
    assert block_size == 1024
    metadata_home = 30000
    data_home = 30001
    revoke_home = 30002
    assert revoke_home < layout["blocks"]
    metadata_image = struct.pack(">I", 0xC03B3998) + bytes((0xA5,)) * 1020
    data_image = bytes((0x5A,)) * block_size
    with image.open("rb") as source:
        source.seek(metadata_home * block_size)
        metadata_before = source.read(block_size)
        source.seek(data_home * block_size)
        data_before = source.read(block_size)
        source.seek(revoke_home * block_size)
        revoke_before = source.read(block_size)
    assert all(
        len(block) == block_size
        for block in (metadata_before, data_before, revoke_before)
    )
    assert data_before != data_image

    first = struct.unpack_from(">I", standard, 0x14)[0]
    maxlen = struct.unpack_from(">I", standard, 0x10)[0]
    logical = {
        "guard": guard_logical,
        "descriptor": _jbd2_ring_advance(
            guard_logical, 1, first=first, maxlen=maxlen
        ),
        "payload": _jbd2_ring_advance(
            guard_logical, 2, first=first, maxlen=maxlen
        ),
        "revoke": _jbd2_ring_advance(
            guard_logical, 3, first=first, maxlen=maxlen
        ),
        "commit": _jbd2_ring_advance(
            guard_logical, 4, first=first, maxlen=maxlen
        ),
        "sentinel": _jbd2_ring_advance(
            guard_logical, 5, first=first, maxlen=maxlen
        ),
    }
    assert len(set(logical.values())) == len(logical)
    journal_map = _ext4_journal_physical_map(image, (0, *logical.values()))
    physical = {name: journal_map[position] for name, position in logical.items()}

    expected_transactions = 1 if commit_durable else 0
    expected_metadata = "_EF-META" if commit_durable else "_EF-META-BEFORE"
    invalidate_expected_commit = (
        [] if commit_durable else ["0 _EF-COMMIT C!"]
    )
    media_path = tmp_path / f"jbd2-writer-{case}.img"
    try:
        output, trace, media_sha256 = run_recovery_forth(
            image,
            media_path,
            [
                "CREATE _EF-META 1024 ALLOT _EF-META 1024 0xA5 FILL",
                "0xC03B3998 _EF-META _EXT4-BE32!",
                "CREATE _EF-DATA 1024 ALLOT _EF-DATA 1024 0x5A FILL",
                "CREATE _EF-META-BEFORE 1024 ALLOT",
                "CREATE _EF-COMMIT 1024 ALLOT",
                "T-ARENA CONSTANT _EF-ARENA",
                (
                    "_EF-ARENA T-VOLUME EXT4-NEW "
                    "CONSTANT _EF-MOUNT-IOR CONSTANT _EF-V"
                ),
                "_EF-V _EXT4-CTX CONSTANT _EF-CTX",
                (
                    "1 1 1 _EF-CTX _EXT4-JWR-ENSURE "
                    "CONSTANT _EF-E-IOR CONSTANT _EF-W"
                ),
                (
                    "30000 _EF-CTX _EXT4-READ-BLOCK "
                    "CONSTANT _EF-BEFORE-IOR"
                ),
                (
                    "_EF-CTX _EXT4-C.BLOCK + _EF-META-BEFORE "
                    "1024 MOVE"
                ),
                "_EF-W _EXT4-JWR.HEAD + @ CONSTANT _EF-GUARD",
                (
                    "_EF-GUARD 4 _EF-CTX _EXT4-JOURNAL-ADVANCE "
                    "CONSTANT _EF-COMMIT-LOGICAL"
                ),
                "_EF-W _EXT4-JWR-ACTIVATE CONSTANT _EF-A-IOR",
                (
                    "1 1 1 _EF-W _EXT4-JTX-BEGIN "
                    "CONSTANT _EF-B-IOR CONSTANT _EF-T"
                ),
                (
                    "_EF-META 30000 _EF-T _EXT4-JTX-META-PUT "
                    "CONSTANT _EF-M-IOR"
                ),
                (
                    "_EF-DATA 30001 _EF-T _EXT4-JTX-DATA-PUT "
                    "CONSTANT _EF-D-IOR"
                ),
                "30002 _EF-T _EXT4-JTX-REVOKE CONSTANT _EF-R-IOR",
                "_EF-T _EXT4-JTX-EMIT CONSTANT _EF-EMIT-IOR",
                "_EF-T _EXT4-JTX-EMIT CONSTANT _EF-RETRY-IOR",
                "_EF-T _EXT4-JTX-ABORT CONSTANT _EF-ABORT-IOR",
                (
                    "1 1 1 _EF-W _EXT4-JTX-BEGIN "
                    "CONSTANT _EF-NEW-IOR CONSTANT _EF-NEW-T"
                ),
                (
                    "_EF-MOUNT-IOR 0= _EF-E-IOR 0= AND "
                    "_EF-BEFORE-IOR 0= AND _EF-A-IOR 0= AND "
                    "_EF-B-IOR 0= AND _EF-M-IOR 0= AND "
                    "_EF-D-IOR 0= AND _EF-R-IOR 0= AND "
                    "_EF-EMIT-IOR VFS-IOR-DOMAIN VFS-IOR-D-VOLUME = AND "
                    "_EF-EMIT-IOR VFS-IOR-REASON VFS-R-IO = AND "
                    "_EF-EMIT-IOR VFS-IOR-FLAGS VFS-IOR-F-PARTIAL "
                    "AND 0<> AND "
                    "_EF-W _EXT4-JWR.FAULT + @ _EF-EMIT-IOR = AND "
                    "_EF-W _EXT4-JWR.STATE + @ _EXT4-JWR-FAULTED = AND "
                    f"_EF-W _EXT4-JWR.PHASE + @ {phase_word} = AND "
                    "_EF-W _EXT4-JWR-VALID? AND "
                    "_EF-V V.FLAGS @ VFS-F-RO AND 0<> AND "
                    "_EF-V V.FLAGS @ VFS-F-DIRTY AND 0<> AND "
                    'IF ." EXT4-JTX-EMIT-FAULTED" THEN'
                ),
                (
                    "_EF-RETRY-IOR VFS-E-BUSY = "
                    "_EF-ABORT-IOR VFS-E-BUSY = AND "
                    "_EF-NEW-T 0= AND _EF-NEW-IOR VFS-E-BUSY = AND "
                    'IF ." EXT4-JTX-EMIT-FAULT-BUSY" THEN'
                ),
                (
                    "_EF-W _EXT4-JWR.META-USED + @ 1 = "
                    "_EF-W _EXT4-JWR.DATA-USED + @ 1 = AND "
                    "_EF-W _EXT4-JWR.REVOKE-USED + @ 1 = AND "
                    "_EF-META _EF-W _EXT4-JWR.META-IMAGES + @ "
                    "1024 _EXT4-BYTES=? AND "
                    "_EF-DATA _EF-W _EXT4-JWR.DATA-IMAGES + @ "
                    "1024 _EXT4-BYTES=? AND "
                    'IF ." EXT4-JTX-EMIT-FAULT-AFTERIMAGES" THEN'
                ),
                "_EF-COMMIT _EF-W _EXT4-JTX-BUILD-COMMIT",
                *invalidate_expected_commit,
                (
                    "30000 _EF-CTX _EXT4-READ-BLOCK "
                    "CONSTANT _EF-META-READ-IOR"
                ),
                (
                    "_EF-CTX _EXT4-C.BLOCK + _EF-META-BEFORE "
                    "1024 _EXT4-BYTES=? CONSTANT _EF-META-UNCHANGED"
                ),
                (
                    "30001 _EF-CTX _EXT4-READ-BLOCK "
                    "CONSTANT _EF-DATA-READ-IOR"
                ),
                (
                    "_EF-CTX _EXT4-C.BLOCK + _EF-DATA "
                    "1024 _EXT4-BYTES=? CONSTANT _EF-DATA-DURABLE"
                ),
                (
                    "_EF-COMMIT-LOGICAL _EF-CTX _EXT4-READ-JBLOCK "
                    "CONSTANT _EF-COMMIT-READ-IOR"
                ),
                (
                    "_EF-CTX _EXT4-C.BLOCK + _EF-COMMIT "
                    "1024 _EXT4-BYTES=? CONSTANT _EF-COMMIT-ENDPOINT"
                ),
                (
                    "_EF-META-READ-IOR 0= _EF-DATA-READ-IOR 0= AND "
                    "_EF-COMMIT-READ-IOR 0= AND "
                    "_EF-META-UNCHANGED AND _EF-DATA-DURABLE AND "
                    "_EF-COMMIT-ENDPOINT AND "
                    'IF ." EXT4-JTX-EMIT-FAULT-MEDIA" THEN'
                ),
                "_EF-W _EXT4-JWR.EPOCH + @ CONSTANT _EF-FAULT-EPOCH",
                (
                    "_EF-ARENA ARENA-USED "
                    "CONSTANT _EF-USED-BEFORE-FAILED-MOUNT"
                ),
                "_EF-V V.VOL-COOKIE @ CONSTANT _EF-VOL-COOKIE",
                "_EF-VOL-COOKIE INVERT _EF-V V.VOL-COOKIE !",
                (
                    "_EF-V _EXT4-MOUNT "
                    "CONSTANT _EF-FAILED-MOUNT-IOR"
                ),
                "_EF-VOL-COOKIE _EF-V V.VOL-COOKIE !",
                (
                    "1 1 1 _EF-CTX _EXT4-JWR-ENSURE "
                    "CONSTANT _EF-STALE-ENSURE-IOR "
                    "CONSTANT _EF-STALE-W"
                ),
                (
                    "_EF-FAILED-MOUNT-IOR "
                    "EXT4-D-ATTACHMENT _EXT4-CORRUPT = "
                    "_EF-CTX _EXT4-C.J.WRITER + @ _EF-W = AND "
                    "_EF-CTX _EXT4-C.J.WRITER-CURRENT + @ 0= AND "
                    "_EF-W _EXT4-JWR-SHAPE? AND "
                    "_EF-W _EXT4-JWR-VALID? 0= AND "
                    "_EF-STALE-W 0= AND "
                    "_EF-STALE-ENSURE-IOR VFS-E-INVALID = AND "
                    "_EF-W _EXT4-JWR.STATE + @ _EXT4-JWR-FAULTED = AND "
                    f"_EF-W _EXT4-JWR.PHASE + @ {phase_word} = AND "
                    "_EF-W _EXT4-JWR.FAULT + @ _EF-EMIT-IOR = AND "
                    "_EF-W _EXT4-JWR.EPOCH + @ _EF-FAULT-EPOCH = AND "
                    "_EF-W _EXT4-JWR.META-USED + @ 1 = AND "
                    "_EF-W _EXT4-JWR.DATA-USED + @ 1 = AND "
                    "_EF-W _EXT4-JWR.REVOKE-USED + @ 1 = AND "
                    "_EF-META _EF-W _EXT4-JWR.META-IMAGES + @ "
                    "1024 _EXT4-BYTES=? AND "
                    "_EF-DATA _EF-W _EXT4-JWR.DATA-IMAGES + @ "
                    "1024 _EXT4-BYTES=? AND "
                    "_EF-ARENA ARENA-USED "
                    "_EF-USED-BEFORE-FAILED-MOUNT = AND "
                    'IF ." EXT4-JTX-FAILED-MOUNT-PRESERVED" THEN'
                ),
                "_EF-V _EXT4-MOUNT CONSTANT _EF-REMOUNT-IOR",
                "_EF-ARENA ARENA-USED CONSTANT _EF-USED-AFTER-REMOUNT",
                (
                    "_EF-CTX _EXT4-C.J.WRITER + @ _EF-W = "
                    "_EF-CTX _EXT4-C.J.WRITER-CURRENT + @ 0<> AND "
                    "_EF-W _EXT4-JWR-VALID? AND "
                    "_EF-W _EXT4-JWR.STATE + @ _EXT4-JWR-IDLE = AND "
                    "_EF-W _EXT4-JWR.FAULT + @ 0= AND "
                    "_EF-W _EXT4-JWR.META-USED + @ 0= AND "
                    "_EF-W _EXT4-JWR.DATA-USED + @ 0= AND "
                    "_EF-W _EXT4-JWR.REVOKE-USED + @ 0= AND "
                    "_EF-W _EXT4-JWR.META-IMAGES + @ C@ 0= AND "
                    "_EF-W _EXT4-JWR.DATA-IMAGES + @ C@ 0= AND "
                    "_EF-W _EXT4-JWR.HEAD + @ "
                    "_EF-CTX _EXT4-C.J.HEAD + @ = AND "
                    "_EF-W _EXT4-JWR.TAIL + @ "
                    "_EF-CTX _EXT4-C.J.HEAD + @ = AND "
                    "_EF-W _EXT4-JWR.NEXT-TID + @ "
                    "_EF-CTX _EXT4-C.J.SEQUENCE + @ 1+ "
                    "0xFFFFFFFF AND = AND "
                    "CONSTANT _EF-MOUNT-REBASED"
                ),
                (
                    "30000 _EF-CTX _EXT4-READ-BLOCK "
                    "CONSTANT _EF-FINAL-META-IOR"
                ),
                (
                    f"_EF-CTX _EXT4-C.BLOCK + {expected_metadata} "
                    "1024 _EXT4-BYTES=? CONSTANT _EF-FINAL-META"
                ),
                (
                    "30001 _EF-CTX _EXT4-READ-BLOCK "
                    "CONSTANT _EF-FINAL-DATA-IOR"
                ),
                (
                    "_EF-CTX _EXT4-C.BLOCK + _EF-DATA "
                    "1024 _EXT4-BYTES=? CONSTANT _EF-FINAL-DATA"
                ),
                (
                    "1 1 1 _EF-CTX _EXT4-JWR-ENSURE "
                    "CONSTANT _EF-REUSE-IOR CONSTANT _EF-REUSE-W"
                ),
                "_EF-ARENA ARENA-USED CONSTANT _EF-USED-AFTER-ENSURE",
                (
                    "1 1 1 _EF-REUSE-W _EXT4-JTX-BEGIN "
                    "CONSTANT _EF-PROBE-IOR CONSTANT _EF-PROBE-T"
                ),
                (
                    "_EF-PROBE-T _EXT4-JTX-ABORT "
                    "CONSTANT _EF-PROBE-ABORT-IOR"
                ),
                (
                    "_EF-REMOUNT-IOR 0= "
                    "_EF-V V.LIFECYCLE @ VFS-L-MOUNTED = AND "
                    "_EF-V _EXT4-READY? AND "
                    "_EF-CTX _EXT4-C.RECOVERY + @ 0= AND "
                    "_EF-CTX _EXT4-C.J.START + @ 0= AND "
                    "_EF-CTX _EXT4-C.J.WITNESS + @ _EXT4-JW-NONE = AND "
                    "_EF-CTX _EXT4-C.J.CLEANUP + @ _EXT4-JC-NONE = AND "
                    "_EF-CTX _EXT4-C.J.PRIMARY-TORN + @ 0= AND "
                    "_EF-CTX _EXT4-C.SUPER-TORN + @ 0= AND "
                    "_EF-CTX _EXT4-C.J.WRITE-ACTIVE + @ 0= AND "
                    "_EF-CTX _EXT4-C.J.FEATURES + @ "
                    "_EXT4-JBD2-I-RECOVERY-REVOKE = AND "
                    f"_EF-CTX _EXT4-C.J.COMMITTED + @ {expected_transactions} "
                    "= AND "
                    f"_EF-CTX _EXT4-C.J.HOME-WRITES + @ "
                    f"{expected_transactions} = AND "
                    f"_EF-CTX _EXT4-C.J.REVOKE-COUNT + @ "
                    f"{expected_transactions} = AND "
                    "_EF-CTX _EXT4-C.J.REVOKE-HITS + @ 0= AND "
                    "_EF-CTX _EXT4-C.SB + _EXT4-SUPER-CHECKSUM? AND "
                    "_EF-CTX _EXT4-C.SB + _EXT4-SB.INCOMPAT + L@ "
                    "_EXT4-INCOMPAT-RECOVER AND 0= AND "
                    "_EF-FINAL-META-IOR 0= AND _EF-FINAL-META AND "
                    "_EF-FINAL-DATA-IOR 0= AND _EF-FINAL-DATA AND "
                    'IF ." EXT4-JTX-EMIT-FAULT-REMOUNTED" THEN'
                ),
                (
                    "_EF-MOUNT-REBASED "
                    "_EF-REUSE-IOR 0= AND _EF-REUSE-W _EF-W = AND "
                    "_EF-USED-AFTER-ENSURE _EF-USED-AFTER-REMOUNT = AND "
                    "_EF-PROBE-IOR 0= AND _EF-PROBE-T _EF-W = AND "
                    "_EF-PROBE-ABORT-IOR 0= AND "
                    'IF ." EXT4-JTX-EMIT-FAULT-REBASED" THEN'
                ),
                "_EF-W _EXT4-JWR-VALID? CONSTANT _EF-PRE-UNMOUNT-VALID",
                "0 _EF-V _EXT4-UNMOUNT CONSTANT _EF-UNMOUNT-IOR",
                (
                    "_EF-PRE-UNMOUNT-VALID _EF-UNMOUNT-IOR 0= AND "
                    "_EF-V V.BCTX @ 0= AND "
                    "_EF-CTX _EXT4-C.READY + @ 0= AND "
                    "_EF-CTX _EXT4-C.J.WRITER-CURRENT + @ 0= AND "
                    "_EF-W _EXT4-JWR-SHAPE? AND "
                    "_EF-W _EXT4-JWR-VALID? 0= AND "
                    'IF ." EXT4-JTX-UNMOUNT-INVALIDATED" THEN'
                ),
            ],
            patches=source_patches,
            write_faults_by_ordinal={
                write_ordinal: {
                    "stage": "media",
                    "sector_index": sector_index,
                    "byte_index": byte_index,
                    "result": STORAGE_RESULT_MEDIA_FAILURE,
                    "command": STORAGE_CMD_WRITE,
                }
            },
            capture_media=media_path,
        )
        _assert_emitted(output, "EXT4-JTX-EMIT-FAULTED")
        _assert_emitted(output, "EXT4-JTX-EMIT-FAULT-BUSY")
        _assert_emitted(output, "EXT4-JTX-EMIT-FAULT-AFTERIMAGES")
        _assert_emitted(output, "EXT4-JTX-EMIT-FAULT-MEDIA")
        _assert_emitted(output, "EXT4-JTX-FAILED-MOUNT-PRESERVED")
        _assert_emitted(output, "EXT4-JTX-EMIT-FAULT-REMOUNTED")
        _assert_emitted(output, "EXT4-JTX-EMIT-FAULT-REBASED")
        _assert_emitted(output, "EXT4-JTX-UNMOUNT-INVALIDATED")

        emission_trace = (
            ("write", data_home * 2, 2),
            ("write", physical["descriptor"] * 2, 2),
            ("write", physical["payload"] * 2, 2),
            ("write", physical["revoke"] * 2, 2),
            ("write", physical["commit"] * 2, 2),
            ("write", physical["sentinel"] * 2, 2),
            ("flush", 0, 0),
            ("write", physical["guard"] * 2, 2),
            ("flush", 0, 0),
            ("write", physical["guard"] * 2, 2),
            ("flush", 0, 0),
            ("write", journal0_physical * 2, 2),
            ("flush", 0, 0),
            ("write", physical["commit"] * 2, 2),
            ("flush", 0, 0),
        )
        expected_prefix = list(activation_trace)
        observed_writes = sum(
            event[0] == "write" for event in activation_trace
        )
        for event in emission_trace:
            expected_prefix.append(event)
            if event[0] == "write":
                observed_writes += 1
                if observed_writes == write_ordinal:
                    break
        expected_prefix = tuple(expected_prefix)
        assert trace[: len(expected_prefix)] == expected_prefix
        recovery_trace = trace[len(expected_prefix) :]

        allowed_recovery_writes = {
            ("write", 2, 2),
            ("write", journal0_physical * 2, 2),
            ("write", guard_physical * 2, 2),
        }
        if commit_durable:
            allowed_recovery_writes.add(("write", metadata_home * 2, 2))
        for index, event in enumerate(recovery_trace):
            assert event[0] in {"write", "flush"}
            if event[0] != "write":
                continue
            assert event in allowed_recovery_writes
            assert index + 1 < len(recovery_trace)
            assert recovery_trace[index + 1] == ("flush", 0, 0)
        assert recovery_trace.count(("write", metadata_home * 2, 2)) == (
            expected_transactions
        )
        assert ("write", data_home * 2, 2) not in recovery_trace
        assert ("write", revoke_home * 2, 2) not in recovery_trace

        assert media_path.is_file()
        assert _sha256(media_path) == media_sha256
        _assert_activation_landed_media(
            media_path,
            writer_activation_fixture,
            expected_features=0x13,
        )
        with media_path.open("rb") as source:
            source.seek(metadata_home * block_size)
            metadata_after = source.read(block_size)
            source.seek(data_home * block_size)
            data_after = source.read(block_size)
            source.seek(revoke_home * block_size)
            revoke_after = source.read(block_size)
        assert metadata_after == (
            metadata_image if commit_durable else metadata_before
        )
        assert data_after == data_image
        assert revoke_after == revoke_before
    finally:
        media_path.unlink(missing_ok=True)


@pytest.mark.parametrize(
    (
        "phase",
        "write_ordinal",
        "sector_index",
        "byte_index",
        "phase_word",
        "resolved_features",
    ),
    (
        (
            "preseed",
            1,
            0,
            8,
            "_EXT4-JWP-GUARD-PRESEED",
            0,
        ),
        ("guard", 2, 0, 1, "_EXT4-JWP-GUARD", 0),
        ("primary", 3, 0, 50, "_EXT4-JWP-PRIMARY", 0x13),
        ("ext4-super", 4, 1, 0, "_EXT4-JWP-EXT4-SUPER", 0x13),
        (
            "witness-clear",
            5,
            0,
            200,
            "_EXT4-JWP-WITNESS-CLEAR",
            0x13,
        ),
        (
            "guard-retire",
            6,
            0,
            200,
            "_EXT4-JWP-GUARD-RETIRE",
            0x13,
        ),
    ),
)
def test_jbd2_writer_activation_faults_quarantine_and_mount_resolves(
    writer_activation_fixture: dict[str, object],
    tmp_path: Path,
    phase: str,
    write_ordinal: int,
    sector_index: int,
    byte_index: int,
    phase_word: str,
    resolved_features: int,
) -> None:
    image = writer_activation_fixture["image"]
    success_trace = writer_activation_fixture["success_trace"]
    source_patches = writer_activation_fixture["source_patches"]
    clean_super = writer_activation_fixture["clean_super"]
    dirty_super = writer_activation_fixture["dirty_super"]
    old_journal = writer_activation_fixture["old_journal"]
    old_guard = writer_activation_fixture["old_guard"]
    anchor = writer_activation_fixture["anchor"]
    preseed = writer_activation_fixture["preseed"]
    standard = writer_activation_fixture["standard"]
    journal0_physical = writer_activation_fixture["journal0_physical"]
    guard_physical = writer_activation_fixture["guard_physical"]
    assert isinstance(image, Path)
    assert isinstance(success_trace, tuple)
    assert isinstance(source_patches, tuple)
    assert isinstance(clean_super, bytes)
    assert isinstance(dirty_super, bytes)
    assert isinstance(old_journal, bytes)
    assert isinstance(old_guard, bytes)
    assert isinstance(anchor, bytes)
    assert isinstance(preseed, bytes)
    assert isinstance(standard, bytes)
    assert isinstance(journal0_physical, int)
    assert isinstance(guard_physical, int)

    # The runner snapshots its input before writeback, so remount in place and
    # keep each fault row to one sparse image on disk.
    media_path = tmp_path / f"jbd2-activation-{phase}.img"
    try:
        output, trace, media_sha256 = run_recovery_forth(
            image,
            media_path,
            [
                "T-ARENA T-VOLUME EXT4-NEW CONSTANT _M-IOR CONSTANT _V",
                "_V _EXT4-CTX CONSTANT _AF-CTX",
                (
                    "1 0 0 _AF-CTX _EXT4-JWR-ENSURE "
                    "CONSTANT _AF-E-IOR CONSTANT _AF-W"
                ),
                "_AF-W _EXT4-JWR.HEAD + @ CONSTANT _AF-HEAD",
                "_AF-W _EXT4-JWR.TAIL + @ CONSTANT _AF-TAIL",
                "_AF-W _EXT4-JWR.FREE + @ CONSTANT _AF-FREE",
                "_AF-W _EXT4-JWR.NEXT-TID + @ CONSTANT _AF-NEXT-TID",
                "_AF-W _EXT4-JWR-ACTIVATE CONSTANT _AF-A-IOR",
                "_AF-W _EXT4-JWR-ACTIVATE CONSTANT _AF-AGAIN-IOR",
                "0 _V VFS-UNMOUNT CONSTANT _AF-UNMOUNT-IOR",
                (
                    "VFS-UNMOUNT-F-FORCE _V VFS-UNMOUNT "
                    "CONSTANT _AF-RETRY-IOR"
                ),
                (
                    "_M-IOR 0= _AF-E-IOR 0= AND "
                    "_AF-A-IOR VFS-IOR-DOMAIN VFS-IOR-D-VOLUME = AND "
                    "_AF-A-IOR VFS-IOR-REASON VFS-R-IO = AND "
                    "_AF-A-IOR VFS-IOR-FLAGS VFS-IOR-F-PARTIAL "
                    "AND 0<> AND "
                    "_AF-W _EXT4-JWR.FAULT + @ _AF-A-IOR = AND "
                    "_AF-W _EXT4-JWR.STATE + @ _EXT4-JWR-FAULTED = AND "
                    f"_AF-W _EXT4-JWR.PHASE + @ {phase_word} = AND "
                    "_AF-W _EXT4-JWR.HEAD + @ _AF-HEAD = AND "
                    "_AF-W _EXT4-JWR.TAIL + @ _AF-TAIL = AND "
                    "_AF-W _EXT4-JWR.FREE + @ _AF-FREE = AND "
                    "_AF-W _EXT4-JWR.NEXT-TID + @ _AF-NEXT-TID = AND "
                    "_AF-W _EXT4-JWR-VALID? AND "
                    "_AF-CTX _EXT4-C.RECOVERY + @ 0= AND "
                    "_AF-CTX _EXT4-C.J.WRITE-ACTIVE + @ 0= AND "
                    "_AF-CTX _EXT4-C.J.FEATURES + @ 0= AND "
                    "_AF-CTX _EXT4-C.J.WITNESS + @ _EXT4-JW-NONE = AND "
                    "_AF-AGAIN-IOR VFS-E-BUSY = AND "
                    "_AF-UNMOUNT-IOR _AF-A-IOR = AND "
                    "_AF-RETRY-IOR VFS-E-STALE = AND "
                    "_V V.LIFECYCLE @ VFS-L-STALE = AND "
                    "_V V.BCTX @ _AF-CTX = AND "
                    "_AF-CTX _EXT4-C.J.WRITER-CURRENT + @ 0<> AND "
                    "_AF-CTX _EXT4-C.READY + @ 0<> AND "
                    "_V V.FLAGS @ VFS-F-RO AND 0<> AND "
                    "_V V.FLAGS @ VFS-F-DIRTY AND 0<> AND "
                    'IF ." EXT4-JWR-ACTIVATION-FAULT" THEN'
                ),
            ],
            patches=source_patches,
            write_faults_by_ordinal={
                write_ordinal: {
                    "stage": "media",
                    "sector_index": sector_index,
                    "byte_index": byte_index,
                    "result": STORAGE_RESULT_MEDIA_FAILURE,
                    "command": STORAGE_CMD_WRITE,
                }
            },
            capture_media=media_path,
        )
        _assert_emitted(output, "EXT4-JWR-ACTIVATION-FAULT")
        assert trace == success_trace[: 2 * (write_ordinal - 1) + 1]
        assert media_path.is_file()
        assert _sha256(media_path) == media_sha256
        superblock, journal, guard = _read_jbd2_activation_media(
            media_path, writer_activation_fixture
        )
        if phase == "preseed":
            assert superblock == clean_super
            assert journal == old_journal
            assert _sequential_prefix_merge(preseed, old_guard, guard)
            assert guard != anchor
        elif phase == "guard":
            assert superblock == clean_super
            assert journal == old_journal
            assert guard == anchor
        elif phase == "primary":
            assert superblock == clean_super
            assert guard == anchor
            assert _sequential_prefix_merge(anchor, old_journal, journal)
            assert journal not in {old_journal, anchor}
        elif phase == "ext4-super":
            assert journal == anchor
            assert guard == anchor
            assert _sequential_prefix_merge(
                dirty_super, clean_super, superblock
            )
            assert superblock not in {clean_super, dirty_super}
        elif phase == "witness-clear":
            assert superblock == dirty_super
            assert guard == anchor
            assert _sequential_prefix_merge(standard, anchor, journal)
            assert journal not in {standard, anchor}
        else:
            assert phase == "guard-retire"
            assert superblock == dirty_super
            assert journal == standard
            assert _sequential_prefix_merge(bytes(1024), anchor, guard)
            assert guard not in {bytes(1024), anchor}

        output, resolution_trace, resolved_sha256 = run_recovery_forth(
            media_path,
            media_path,
            _activation_resolved_mount_lines(
                "EXT4-JWR-ACTIVATION-RESOLVED", resolved_features
            ),
            capture_media=media_path,
        )
        _assert_emitted(output, "EXT4-JWR-ACTIVATION-RESOLVED")
        _assert_activation_cleanup_trace(
            resolution_trace,
            journal0_physical=journal0_physical,
            guard_physical=guard_physical,
        )
        assert media_path.is_file()
        assert _sha256(media_path) == resolved_sha256
        _assert_activation_landed_media(
            media_path,
            writer_activation_fixture,
            expected_features=resolved_features,
        )
    finally:
        media_path.unlink(missing_ok=True)


# The resolver faults split the endpoint checksum itself, advancing the
# durable prefix while leaving a second-generation tear for the third mount.
@pytest.mark.parametrize(
    (
        "phase",
        "activation_write_ordinal",
        "activation_sector_index",
        "activation_byte_index",
        "activation_phase_word",
        "completion",
        "resolver_sector_index",
        "resolver_byte_index",
    ),
    (
        pytest.param(
            "ext4-super",
            4,
            1,
            0,
            "_EXT4-JWP-EXT4-SUPER",
            "D",
            1,
            510,
            id="W4-D-completion",
        ),
        pytest.param(
            "witness-clear",
            5,
            0,
            200,
            "_EXT4-JWP-WITNESS-CLEAR",
            "C",
            0,
            254,
            id="W5-C-completion",
        ),
    ),
)
def test_jbd2_writer_activation_resolver_retries_second_generation_tears(
    writer_activation_fixture: dict[str, object],
    tmp_path: Path,
    phase: str,
    activation_write_ordinal: int,
    activation_sector_index: int,
    activation_byte_index: int,
    activation_phase_word: str,
    completion: str,
    resolver_sector_index: int,
    resolver_byte_index: int,
) -> None:
    image = writer_activation_fixture["image"]
    success_trace = writer_activation_fixture["success_trace"]
    source_patches = writer_activation_fixture["source_patches"]
    clean_super = writer_activation_fixture["clean_super"]
    dirty_super = writer_activation_fixture["dirty_super"]
    anchor = writer_activation_fixture["anchor"]
    standard = writer_activation_fixture["standard"]
    journal0_physical = writer_activation_fixture["journal0_physical"]
    guard_physical = writer_activation_fixture["guard_physical"]
    assert isinstance(image, Path)
    assert isinstance(success_trace, tuple)
    assert isinstance(source_patches, tuple)
    assert isinstance(clean_super, bytes)
    assert isinstance(dirty_super, bytes)
    assert isinstance(anchor, bytes)
    assert isinstance(standard, bytes)
    assert isinstance(journal0_physical, int)
    assert isinstance(guard_physical, int)

    media_path = tmp_path / f"jbd2-activation-{phase}-second-tear.img"
    try:
        output, activation_trace, activation_sha256 = run_recovery_forth(
            image,
            media_path,
            [
                "T-ARENA T-VOLUME EXT4-NEW CONSTANT _M-IOR CONSTANT _V",
                "_V _EXT4-CTX CONSTANT _SG-CTX",
                (
                    "1 0 0 _SG-CTX _EXT4-JWR-ENSURE "
                    "CONSTANT _SG-E-IOR CONSTANT _SG-W"
                ),
                "_SG-W _EXT4-JWR-ACTIVATE CONSTANT _SG-A-IOR",
                (
                    "_M-IOR 0= _SG-E-IOR 0= AND "
                    "_SG-A-IOR VFS-IOR-DOMAIN VFS-IOR-D-VOLUME = AND "
                    "_SG-A-IOR VFS-IOR-REASON VFS-R-IO = AND "
                    "_SG-A-IOR VFS-IOR-FLAGS VFS-IOR-F-PARTIAL "
                    "AND 0<> AND "
                    "_SG-W _EXT4-JWR.STATE + @ _EXT4-JWR-FAULTED = AND "
                    f"_SG-W _EXT4-JWR.PHASE + @ {activation_phase_word} "
                    "= AND "
                    'IF ." EXT4-JWR-ACTIVATION-FIRST-TEAR" THEN'
                ),
            ],
            patches=source_patches,
            write_faults_by_ordinal={
                activation_write_ordinal: {
                    "stage": "media",
                    "sector_index": activation_sector_index,
                    "byte_index": activation_byte_index,
                    "result": STORAGE_RESULT_MEDIA_FAILURE,
                    "command": STORAGE_CMD_WRITE,
                }
            },
            capture_media=media_path,
        )
        _assert_emitted(output, "EXT4-JWR-ACTIVATION-FIRST-TEAR")
        assert activation_trace == success_trace[
            : 2 * (activation_write_ordinal - 1) + 1
        ]
        assert media_path.is_file()
        assert _sha256(media_path) == activation_sha256
        superblock, journal, guard = _read_jbd2_activation_media(
            media_path, writer_activation_fixture
        )
        if completion == "D":
            assert _sequential_prefix_merge(
                dirty_super, clean_super, superblock
            )
            assert superblock not in {clean_super, dirty_super}
            assert journal == anchor
        else:
            assert completion == "C"
            assert superblock == dirty_super
            assert _sequential_prefix_merge(standard, anchor, journal)
            assert journal not in {standard, anchor}
        assert guard == anchor

        completion_write = (
            ("write", 2, 2)
            if completion == "D"
            else ("write", journal0_physical * 2, 2)
        )
        output, resolver_trace, resolver_sha256 = run_recovery_forth(
            media_path,
            media_path,
            [
                "T-ARENA T-VOLUME EXT4-NEW CONSTANT _R-IOR CONSTANT _V",
                (
                    "_R-IOR VFS-IOR-DOMAIN VFS-IOR-D-VOLUME = "
                    "_R-IOR VFS-IOR-REASON VFS-R-IO = AND "
                    "_R-IOR VFS-IOR-FLAGS VFS-IOR-F-PARTIAL "
                    "AND 0<> AND "
                    "_V V.LIFECYCLE @ VFS-L-NEW = AND "
                    "_V _EXT4-READY? 0= AND "
                    'IF ." EXT4-JWR-ACTIVATION-SECOND-TEAR" THEN'
                ),
            ],
            write_faults_by_ordinal={
                1: {
                    "stage": "media",
                    "sector_index": resolver_sector_index,
                    "byte_index": resolver_byte_index,
                    "result": STORAGE_RESULT_MEDIA_FAILURE,
                    "command": STORAGE_CMD_WRITE,
                }
            },
            capture_media=media_path,
        )
        _assert_emitted(output, "EXT4-JWR-ACTIVATION-SECOND-TEAR")
        assert resolver_trace == (completion_write,)
        assert _sha256(media_path) == resolver_sha256
        assert resolver_sha256 != activation_sha256
        superblock, journal, guard = _read_jbd2_activation_media(
            media_path, writer_activation_fixture
        )
        if completion == "D":
            assert _sequential_prefix_merge(
                dirty_super, clean_super, superblock
            )
            assert superblock not in {clean_super, dirty_super}
            assert journal == anchor
        else:
            assert superblock == dirty_super
            assert _sequential_prefix_merge(standard, anchor, journal)
            assert journal not in {standard, anchor}
        assert guard == anchor

        output, convergence_trace, converged_sha256 = run_recovery_forth(
            media_path,
            media_path,
            _activation_resolved_mount_lines(
                "EXT4-JWR-ACTIVATION-RETRY-CONVERGED", 0x13
            ),
            capture_media=media_path,
        )
        _assert_emitted(output, "EXT4-JWR-ACTIVATION-RETRY-CONVERGED")
        assert convergence_trace[:2] == (
            completion_write,
            ("flush", 0, 0),
        )
        _assert_activation_cleanup_trace(
            convergence_trace,
            journal0_physical=journal0_physical,
            guard_physical=guard_physical,
        )
        assert ("write", 2, 2) in convergence_trace
        assert ("write", journal0_physical * 2, 2) in convergence_trace
        assert ("write", guard_physical * 2, 2) in convergence_trace
        assert _sha256(media_path) == converged_sha256
        _assert_activation_landed_media(
            media_path,
            writer_activation_fixture,
            expected_features=0x13,
        )
    finally:
        media_path.unlink(missing_ok=True)


def test_jbd2_writer_activation_primary_binding_rejects_stale_copies_without_io(
    writer_activation_fixture: dict[str, object], tmp_path: Path
) -> None:
    image = writer_activation_fixture["image"]
    source_patches = writer_activation_fixture["source_patches"]
    assert isinstance(image, Path)
    assert isinstance(source_patches, tuple)

    backing = tmp_path / "jbd2-activation-stale-primary.img"
    try:
        output, trace, _media_sha256 = run_recovery_forth(
            image,
            backing,
            [
                "T-ARENA T-VOLUME EXT4-NEW CONSTANT _M-IOR CONSTANT _V",
                "_V _EXT4-CTX CONSTANT _SP-CTX",
                (
                    "1 0 0 _SP-CTX _EXT4-JWR-ENSURE "
                    "CONSTANT _SP-E-IOR CONSTANT _SP-W"
                ),
                "_SP-W _EXT4-JWR.SCRATCH-A + @ CONSTANT _SP-BUF",
                "0 _SP-CTX _EXT4-READ-JBLOCK CONSTANT _SP-R-IOR",
                (
                    "_SP-CTX _EXT4-C.BLOCK + _SP-BUF "
                    "_SP-W _EXT4-JWR.BSIZE + @ MOVE"
                ),
                (
                    "_SP-BUF _SP-W _EXT4-JWR-ACTIVATION-PRIMARY? "
                    "CONSTANT _SP-EXACT"
                ),
                (
                    "_SP-CTX _EXT4-C.BLOCK + _SP-BUF "
                    "_SP-W _EXT4-JWR.BSIZE + @ MOVE"
                ),
                (
                    "_SP-BUF _EXT4-JS.UUID + DUP C@ 1 XOR SWAP C! "
                    "_SP-BUF _SP-W _EXT4-JWR-ACTIVATION-PRIMARY? "
                    "CONSTANT _SP-UUID"
                ),
                (
                    "_SP-CTX _EXT4-C.BLOCK + _SP-BUF "
                    "_SP-W _EXT4-JWR.BSIZE + @ MOVE"
                ),
                (
                    "_SP-BUF _EXT4-JS.SEQUENCE + DUP _EXT4-BE32@ "
                    "1+ 0xFFFFFFFF AND SWAP _EXT4-BE32! "
                    "_SP-BUF _SP-W _EXT4-JWR-ACTIVATION-PRIMARY? "
                    "CONSTANT _SP-SEQUENCE"
                ),
                (
                    "_M-IOR 0= _SP-E-IOR 0= AND _SP-R-IOR 0= AND "
                    "_SP-EXACT AND _SP-UUID 0= AND _SP-SEQUENCE 0= AND "
                    'IF ." EXT4-JWR-ACTIVATION-STALE-PRIMARY-REFUSED" THEN'
                ),
            ],
            patches=source_patches,
        )
        _assert_emitted(
            output, "EXT4-JWR-ACTIVATION-STALE-PRIMARY-REFUSED"
        )
        assert trace == ()
    finally:
        backing.unlink(missing_ok=True)


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


@pytest.mark.parametrize(
    "image_id",
    ("primary-1k-i256", "primary-2k-i256", "primary-4k-i256"),
)
def test_empty_modern_orphan_state_is_cleared_through_recovery_landing(
    canonical_images: dict[str, Path], tmp_path: Path, image_id: str
) -> None:
    path = canonical_images[image_id]
    patches = _modern_orphan_patches(path, ())
    layout = _ext4_recovery_layout(path)
    block_size = layout["block_size"]
    primary_block = layout["primary_super"]
    super_offset = 0 if block_size == 1024 else 1024
    journal_physical = layout["journal_block"]
    orphan_offset, orphan_afterimage = patches[1]
    media_path = tmp_path / f"{image_id}-empty-orphan-cleared.img"

    with path.open("rb") as source:
        source.seek(primary_block * block_size)
        original_primary = source.read(block_size)
        source.seek(journal_physical * block_size)
        source_journal = source.read(block_size)
    assert len(original_primary) == len(source_journal) == block_size
    first = struct.unpack_from(">I", source_journal, 0x14)[0]
    maxlen = struct.unpack_from(">I", source_journal, 0x10)[0]
    old_head = struct.unpack_from(">I", source_journal, 0x58)[0]
    guard_logical = first if old_head == 0 else old_head
    assert first <= guard_logical < maxlen
    guard_physical = _ext4_journal_physical_map(
        path, (guard_logical,)
    )[guard_logical]
    sectors_per_block = block_size // 512
    journal_write = (
        "write",
        journal_physical * sectors_per_block,
        sectors_per_block,
    )
    guard_write = (
        "write",
        guard_physical * sectors_per_block,
        sectors_per_block,
    )
    super_write = ("write", 2, 2)
    flush = ("flush", 0, 0)
    activation_trace = (
        guard_write,
        flush,
        guard_write,
        flush,
        journal_write,
        flush,
        super_write,
        flush,
        journal_write,
        flush,
        guard_write,
        flush,
    )
    landing_trace = (
        flush,
        guard_write,
        flush,
        guard_write,
        flush,
        journal_write,
        flush,
        super_write,
        flush,
        journal_write,
        flush,
        guard_write,
        flush,
    )

    output, trace, media_sha256 = run_recovery_forth(
        path,
        media_path,
        [
            "T-ARENA T-VOLUME EXT4-NEW CONSTANT _IOR CONSTANT _V",
            "_V _EXT4-CTX CONSTANT _OEC-CTX",
            (
                "_IOR 0= _V V.LIFECYCLE @ VFS-L-MOUNTED = AND "
                "_V _EXT4-READY? AND "
                "_OEC-CTX _EXT4-C.O.ACTIVE + @ 0= AND "
                "_OEC-CTX _EXT4-C.O.CLEAR-PENDING + @ 0= AND "
                "_OEC-CTX _EXT4-C.SB + _EXT4-SB.RO-COMPAT + L@ "
                "_EXT4-RO-ORPHAN-PRESENT AND 0= AND "
                "_OEC-CTX _EXT4-C.RECOVERY + @ 0= AND "
                "_OEC-CTX _EXT4-C.J.START + @ 0= AND "
                "_OEC-CTX _EXT4-C.J.WITNESS + @ _EXT4-JW-NONE = AND "
                "_OEC-CTX _EXT4-C.J.WRITER + @ 0= AND "
                'IF ." EXT4-EMPTY-ORPHAN-CLEARED" THEN'
            ),
        ],
        patches=patches,
        capture_media=media_path,
    )
    _assert_emitted(output, "EXT4-EMPTY-ORPHAN-CLEARED")
    assert trace == activation_trace + landing_trace

    with media_path.open("rb") as recovered:
        recovered.seek(primary_block * block_size)
        final_primary = recovered.read(block_size)
        recovered.seek(journal_physical * block_size)
        final_journal = recovered.read(block_size)
        recovered.seek(guard_physical * block_size)
        final_guard = recovered.read(block_size)
        recovered.seek(orphan_offset)
        final_orphan = recovered.read(len(orphan_afterimage))
    assert (
        len(final_primary)
        == len(final_journal)
        == len(final_guard)
        == block_size
    )
    final_super = final_primary[super_offset : super_offset + 1024]
    assert struct.unpack_from("<I", final_super, 0x60)[0] & 0x04 == 0
    assert struct.unpack_from("<I", final_super, 0x64)[0] & 0x0001_0000 == 0
    assert struct.unpack_from("<I", final_super, 0x3FC)[0] == _crc32c_raw(
        final_super[:0x3FC]
    )
    assert final_primary[:super_offset] == original_primary[:super_offset]
    assert final_primary[super_offset + 1024 :] == original_primary[
        super_offset + 1024 :
    ]
    assert final_orphan == orphan_afterimage
    assert struct.unpack_from(">I", final_journal, 0x1C)[0] == 0
    assert struct.unpack_from(">I", final_journal, 0x28)[0] == 0x13
    assert not any(final_journal[0x5C:0x88])
    assert _jbd2_super_checksum_valid(final_journal[:1024])
    assert final_journal[1024:] == source_journal[1024:]
    assert final_guard == bytes(block_size)

    remount_output, remount_trace, remount_sha256 = run_recovery_forth(
        media_path,
        media_path,
        [
            "T-ARENA T-VOLUME EXT4-NEW CONSTANT _R-IOR CONSTANT _R-V",
            (
                "_R-IOR 0= _R-V V.LIFECYCLE @ VFS-L-MOUNTED = AND "
                "_R-V _EXT4-READY? AND "
                'IF ." EXT4-EMPTY-ORPHAN-REMOUNTED" THEN'
            ),
        ],
        capture_media=media_path,
    )
    _assert_emitted(remount_output, "EXT4-EMPTY-ORPHAN-REMOUNTED")
    assert remount_trace == ()
    assert remount_sha256 == media_sha256


@pytest.mark.parametrize(
    ("case", "image_id", "write_ordinal", "sector_index", "byte_index"),
    (
        pytest.param(
            "akw1-primary",
            "primary-1k-i256",
            3,
            0,
            200,
            id="W3-AKW1-journal-primary-prefix",
        ),
        pytest.param(
            "akr1-primary",
            "primary-1k-i256",
            9,
            0,
            50,
            id="W9-AKR1-journal-primary-early-prefix-1k",
        ),
        pytest.param(
            "akr1-primary",
            "primary-4k-i256",
            9,
            0,
            50,
            id="W9-AKR1-journal-primary-early-prefix-4k",
        ),
        pytest.param(
            "akr1-super",
            "primary-1k-i256",
            10,
            1,
            0,
            id="W10-AKR1-recovered-super-prefix",
        ),
    ),
)
def test_empty_modern_orphan_mount_prefix_tears_remount_clean(
    canonical_images: dict[str, Path],
    tmp_path: Path,
    case: str,
    image_id: str,
    write_ordinal: int,
    sector_index: int,
    byte_index: int,
) -> None:
    path = canonical_images[image_id]
    patches = _modern_orphan_patches(path, ())
    layout = _ext4_recovery_layout(path)
    block_size = layout["block_size"]
    sectors_per_block = block_size // 512
    primary_block = layout["primary_super"]
    super_offset = 0 if block_size == 1024 else 1024
    journal_physical = layout["journal_block"]
    assert patches[0][0] == 1024
    orphan_super = patches[0][1]
    orphan_offset, orphan_afterimage = patches[1]
    assert len(orphan_super) == 1024
    assert len(orphan_afterimage) == block_size

    with path.open("rb") as source:
        source.seek(primary_block * block_size)
        original_primary = source.read(block_size)
        source.seek(journal_physical * block_size)
        old_journal = source.read(block_size)
    assert len(original_primary) == len(old_journal) == block_size
    first = struct.unpack_from(">I", old_journal, 0x14)[0]
    maxlen = struct.unpack_from(">I", old_journal, 0x10)[0]
    old_head = struct.unpack_from(">I", old_journal, 0x58)[0]
    guard_logical = first if old_head == 0 else old_head
    assert first <= guard_logical < maxlen
    guard_physical = _ext4_journal_physical_map(
        path, (guard_logical,)
    )[guard_logical]

    dirty_super = bytearray(orphan_super)
    struct.pack_into(
        "<I",
        dirty_super,
        0x60,
        struct.unpack_from("<I", dirty_super, 0x60)[0] | 0x04,
    )
    struct.pack_into("<H", dirty_super, 0x3A, 1)
    dirty_super = _ext4_super_with_checksum(dirty_super)
    recovered_super = bytearray(dirty_super)
    struct.pack_into(
        "<I",
        recovered_super,
        0x60,
        struct.unpack_from("<I", recovered_super, 0x60)[0] & ~0x04,
    )
    struct.pack_into(
        "<I",
        recovered_super,
        0x64,
        struct.unpack_from("<I", recovered_super, 0x64)[0] & ~0x0001_0000,
    )
    recovered_super = _ext4_super_with_checksum(recovered_super)
    orphan_checksum = struct.unpack_from("<I", orphan_super, 0x3FC)[0]
    dirty_checksum = struct.unpack_from("<I", dirty_super, 0x3FC)[0]
    recovered_checksum = struct.unpack_from("<I", recovered_super, 0x3FC)[0]

    activated_journal = bytearray(old_journal)
    struct.pack_into(">I", activated_journal, 0x1C, 0)
    struct.pack_into(">I", activated_journal, 0x28, 0x13)
    activated_journal[0x50:0x54] = b"\x04\x00\x00\x00"
    struct.pack_into(">I", activated_journal, 0x54, 0)
    struct.pack_into(">I", activated_journal, 0x58, guard_logical)
    activated_journal[0x5C:0x88] = bytes(0x2C)
    activated_journal = _jbd2_block_with_super_checksum(activated_journal)

    activation_anchor = bytearray(activated_journal)
    struct.pack_into(">I", activation_anchor, 0x5C, 0x414B5731)
    struct.pack_into(">I", activation_anchor, 0x60, orphan_checksum)
    struct.pack_into(
        ">I", activation_anchor, 0x64, orphan_checksum ^ 0xFFFF_FFFF
    )
    struct.pack_into(">I", activation_anchor, 0x68, guard_logical)
    struct.pack_into(
        ">I", activation_anchor, 0x6C, guard_logical ^ 0xFFFF_FFFF
    )
    struct.pack_into(">I", activation_anchor, 0x70, dirty_checksum)
    struct.pack_into(
        ">I", activation_anchor, 0x74, dirty_checksum ^ 0xFFFF_FFFF
    )
    struct.pack_into(
        ">I",
        activation_anchor,
        0x78,
        struct.unpack_from(">I", old_journal, 0x28)[0],
    )
    struct.pack_into(
        ">I",
        activation_anchor,
        0x7C,
        struct.unpack_from(">I", old_journal, 0x58)[0],
    )
    activation_anchor[0x80:0x84] = old_journal[0x50:0x54]
    struct.pack_into(
        ">I",
        activation_anchor,
        0x84,
        struct.unpack_from(">I", old_journal, 0xFC)[0],
    )
    activation_anchor = _jbd2_block_with_super_checksum(activation_anchor)

    old_sequence = struct.unpack_from(">I", activated_journal, 0x18)[0]
    old_full_crc = _crc32c_raw(activated_journal)
    reset_anchor = bytearray(activated_journal)
    struct.pack_into(">I", reset_anchor, 0x18, (old_sequence + 1) & 0xFFFF_FFFF)
    struct.pack_into(">I", reset_anchor, 0x5C, 0x414B5231)
    struct.pack_into(">I", reset_anchor, 0x60, recovered_checksum)
    struct.pack_into(
        ">I", reset_anchor, 0x64, recovered_checksum ^ 0xFFFF_FFFF
    )
    struct.pack_into(">I", reset_anchor, 0x68, guard_logical)
    struct.pack_into(
        ">I", reset_anchor, 0x6C, guard_logical ^ 0xFFFF_FFFF
    )
    struct.pack_into(">I", reset_anchor, 0x70, 0x414B4531)
    struct.pack_into(">I", reset_anchor, 0x74, 0xBEB4BACE)
    struct.pack_into(">I", reset_anchor, 0x78, guard_logical)
    struct.pack_into(
        ">I", reset_anchor, 0x7C, guard_logical ^ 0xFFFF_FFFF
    )
    struct.pack_into(">I", reset_anchor, 0x80, old_full_crc)
    struct.pack_into(
        ">I", reset_anchor, 0x84, old_full_crc ^ 0xFFFF_FFFF
    )
    reset_anchor = _jbd2_block_with_super_checksum(reset_anchor)
    final_journal = bytearray(reset_anchor)
    final_journal[0x5C:0x88] = bytes(0x2C)
    final_journal = _jbd2_block_with_super_checksum(final_journal)

    journal_write = (
        "write",
        journal_physical * sectors_per_block,
        sectors_per_block,
    )
    guard_write = (
        "write",
        guard_physical * sectors_per_block,
        sectors_per_block,
    )
    super_write = ("write", 2, 2)
    flush = ("flush", 0, 0)
    activation_trace = (
        guard_write,
        flush,
        guard_write,
        flush,
        journal_write,
        flush,
        super_write,
        flush,
        journal_write,
        flush,
        guard_write,
        flush,
    )

    torn = tmp_path / f"{image_id}-empty-orphan-{case}-torn.img"
    output, trace, media_sha256 = run_recovery_forth(
        path,
        torn,
        [
            "T-ARENA T-VOLUME EXT4-NEW CONSTANT _M-IOR CONSTANT _V",
            "_V _EXT4-CTX CONSTANT _T-CTX",
            (
                "_M-IOR VFS-IOR-DOMAIN VFS-IOR-D-VOLUME = "
                "_M-IOR VFS-IOR-REASON VFS-R-IO = AND "
                "_M-IOR VFS-IOR-FLAGS VFS-IOR-F-PARTIAL AND 0<> AND "
                "_V V.LIFECYCLE @ VFS-L-NEW = AND "
                "_V _EXT4-READY? 0= AND "
                "_T-CTX _EXT4-C.J.WRITER + @ 0= AND "
                'IF ." EXT4-EMPTY-ORPHAN-MOUNT-TEAR" THEN'
            ),
        ],
        patches=patches,
        write_faults_by_ordinal={
            write_ordinal: {
                "stage": "media",
                "sector_index": sector_index,
                "byte_index": byte_index,
                "result": STORAGE_RESULT_MEDIA_FAILURE,
                "command": STORAGE_CMD_WRITE,
            }
        },
        capture_media=torn,
    )
    _assert_emitted(output, "EXT4-EMPTY-ORPHAN-MOUNT-TEAR")
    if case == "akw1-primary":
        assert trace == activation_trace[:5]
    elif case == "akr1-primary":
        assert trace == activation_trace + (
            flush,
            guard_write,
            flush,
            guard_write,
            flush,
            journal_write,
        )
    else:
        assert case == "akr1-super"
        assert trace == activation_trace + (
            flush,
            guard_write,
            flush,
            guard_write,
            flush,
            journal_write,
            flush,
            super_write,
        )
    assert torn.is_file()
    assert _sha256(torn) == media_sha256

    with torn.open("rb") as source:
        source.seek(primary_block * block_size)
        observed_primary = source.read(block_size)
        source.seek(journal_physical * block_size)
        observed_journal = source.read(block_size)
        source.seek(guard_physical * block_size)
        observed_guard = source.read(block_size)
        source.seek(orphan_offset)
        observed_orphan = source.read(len(orphan_afterimage))
    assert len(observed_primary) == block_size
    observed_super = observed_primary[super_offset : super_offset + 1024]
    assert observed_orphan == orphan_afterimage
    orphan_sector = orphan_offset // 512
    orphan_sectors = len(orphan_afterimage) // 512
    assert all(
        event[0] != "write"
        or not (
            event[1] < orphan_sector + orphan_sectors
            and orphan_sector < event[1] + event[2]
        )
        for event in trace
    )

    if case == "akw1-primary":
        assert observed_super == orphan_super
        assert observed_guard == activation_anchor
        assert observed_journal == (
            activation_anchor[:byte_index] + old_journal[byte_index:]
        )
        assert _sequential_prefix_merge(
            activation_anchor, old_journal, observed_journal
        )
        assert not _jbd2_super_checksum_valid(observed_journal[:1024])
    elif case == "akr1-primary":
        assert observed_super == dirty_super
        assert observed_guard == reset_anchor
        assert observed_journal == (
            reset_anchor[:byte_index] + activated_journal[byte_index:]
        )
        assert struct.unpack_from(">I", observed_journal, 0x5C)[0] == 0
        assert _sequential_prefix_merge(
            reset_anchor, activated_journal, observed_journal
        )
        assert not _jbd2_super_checksum_valid(observed_journal[:1024])
    else:
        assert observed_guard == reset_anchor
        assert observed_journal == reset_anchor
        assert observed_super == recovered_super[:512] + dirty_super[512:]
        assert _sequential_prefix_merge(
            recovered_super, dirty_super, observed_super
        )
        assert observed_super not in {dirty_super, recovered_super}
        assert struct.unpack_from("<I", observed_super, 0x60)[0] & 0x04 == 0
        assert (
            struct.unpack_from("<I", observed_super, 0x64)[0]
            & 0x0001_0000
            == 0
        )
        assert struct.unpack_from("<I", observed_super, 0x3FC)[0] != _crc32c_raw(
            observed_super[:0x3FC]
        )

    repaired = tmp_path / f"{image_id}-empty-orphan-{case}-repaired.img"
    remount_output, retry_trace, repaired_sha256 = run_recovery_forth(
        torn,
        repaired,
        [
            "T-ARENA T-VOLUME EXT4-NEW CONSTANT _R-IOR CONSTANT _R-V",
            "_R-V _EXT4-CTX CONSTANT _R-CTX",
            (
                "_R-IOR 0= _R-V V.LIFECYCLE @ VFS-L-MOUNTED = AND "
                "_R-V _EXT4-READY? AND "
                "_R-CTX _EXT4-C.O.ACTIVE + @ 0= AND "
                "_R-CTX _EXT4-C.O.CLEAR-PENDING + @ 0= AND "
                "_R-CTX _EXT4-C.RECOVERY + @ 0= AND "
                "_R-CTX _EXT4-C.J.WRITE-ACTIVE + @ 0= AND "
                "_R-CTX _EXT4-C.J.START + @ 0= AND "
                "_R-CTX _EXT4-C.J.WITNESS + @ _EXT4-JW-NONE = AND "
                "_R-CTX _EXT4-C.J.WRITER + @ 0= AND "
                "_R-CTX _EXT4-C.SB + _EXT4-SUPER-CHECKSUM? AND "
                "_R-CTX _EXT4-C.SB + _EXT4-SB.INCOMPAT + L@ "
                "_EXT4-INCOMPAT-RECOVER AND 0= AND "
                "_R-CTX _EXT4-C.SB + _EXT4-SB.RO-COMPAT + L@ "
                "_EXT4-RO-ORPHAN-PRESENT AND 0= AND "
                "_R-V V.FLAGS @ VFS-F-DIRTY AND 0= AND "
                'IF ." EXT4-EMPTY-ORPHAN-TEAR-REMOUNTED" THEN'
            ),
        ],
        capture_media=repaired,
    )
    _assert_emitted(remount_output, "EXT4-EMPTY-ORPHAN-TEAR-REMOUNTED")
    if case == "akw1-primary":
        assert retry_trace == (
            journal_write,
            flush,
            super_write,
            flush,
            journal_write,
            flush,
            guard_write,
            flush,
            flush,
            guard_write,
            flush,
            guard_write,
            flush,
            journal_write,
            flush,
            super_write,
            flush,
            journal_write,
            flush,
            guard_write,
            flush,
        )
    elif case == "akr1-primary":
        assert retry_trace == (
            flush,
            journal_write,
            flush,
            flush,
            super_write,
            flush,
            journal_write,
            flush,
            guard_write,
            flush,
        )
    else:
        assert retry_trace == (
            super_write,
            flush,
            journal_write,
            flush,
            guard_write,
            flush,
        )
    assert repaired.is_file()
    assert _sha256(repaired) == repaired_sha256
    with repaired.open("rb") as source:
        source.seek(primary_block * block_size)
        final_super_block = source.read(block_size)
        source.seek(journal_physical * block_size)
        final_primary = source.read(block_size)
        source.seek(guard_physical * block_size)
        final_guard = source.read(block_size)
        source.seek(orphan_offset)
        final_orphan = source.read(len(orphan_afterimage))
    assert len(final_super_block) == block_size
    final_super = final_super_block[super_offset : super_offset + 1024]
    assert final_super == recovered_super
    assert final_super_block[:super_offset] == original_primary[:super_offset]
    assert final_super_block[super_offset + 1024 :] == original_primary[
        super_offset + 1024 :
    ]
    assert final_primary == final_journal
    assert final_guard == bytes(block_size)
    assert final_orphan == orphan_afterimage


def test_empty_modern_orphan_writer_free_activation_retries_same_binding(
    canonical_images: dict[str, Path], tmp_path: Path
) -> None:
    path = canonical_images["primary-1k-i256"]
    patches = _modern_orphan_patches(path, ())
    layout = _ext4_recovery_layout(path)
    block_size = layout["block_size"]
    assert block_size == 1024
    journal_physical = layout["journal_block"]
    orphan_offset, orphan_afterimage = patches[1]

    with path.open("rb") as source:
        source.seek(journal_physical * block_size)
        old_journal = source.read(block_size)
    assert len(old_journal) == block_size
    first = struct.unpack_from(">I", old_journal, 0x14)[0]
    maxlen = struct.unpack_from(">I", old_journal, 0x10)[0]
    old_head = struct.unpack_from(">I", old_journal, 0x58)[0]
    guard_logical = first if old_head == 0 else old_head
    assert first <= guard_logical < maxlen
    guard_physical = _ext4_journal_physical_map(
        path, (guard_logical,)
    )[guard_logical]

    journal_write = ("write", journal_physical * 2, 2)
    guard_write = ("write", guard_physical * 2, 2)
    super_write = ("write", 2, 2)
    flush = ("flush", 0, 0)
    first_mount_prefix = (
        guard_write,
        flush,
        guard_write,
        flush,
        journal_write,
    )
    retry_trace = (
        journal_write,
        flush,
        super_write,
        flush,
        journal_write,
        flush,
        guard_write,
        flush,
        flush,
        guard_write,
        flush,
        guard_write,
        flush,
        journal_write,
        flush,
        super_write,
        flush,
        journal_write,
        flush,
        guard_write,
        flush,
    )

    media_path = tmp_path / "empty-orphan-writer-free-same-binding.img"
    output, trace, media_sha256 = run_recovery_forth(
        path,
        media_path,
        [
            "T-ARENA CONSTANT _SR-ARENA",
            (
                "_SR-ARENA T-VOLUME EXT4-NEW "
                "CONSTANT _SR-FIRST-IOR CONSTANT _SR-V"
            ),
            "_SR-V _EXT4-CTX CONSTANT _SR-CTX",
            "_SR-ARENA ARENA-USED CONSTANT _SR-USED-BEFORE",
            "_SR-CTX _EXT4-C.J.MAP + @ CONSTANT _SR-MAP",
            "_SR-CTX _EXT4-C.J.MAP-HASH + @ CONSTANT _SR-HASH",
            "_SR-CTX _EXT4-C.J.WRITER + @ 0= CONSTANT _SR-NO-WRITER",
            "_SR-V V.FLAGS @ CONSTANT _SR-FLAGS-BEFORE",
            "_SR-V _EXT4-MOUNT CONSTANT _SR-RETRY-IOR",
            "_SR-ARENA ARENA-USED CONSTANT _SR-USED-AFTER",
            (
                "_SR-FIRST-IOR VFS-IOR-DOMAIN VFS-IOR-D-VOLUME = "
                "_SR-FIRST-IOR VFS-IOR-REASON VFS-R-IO = AND "
                "_SR-FIRST-IOR VFS-IOR-FLAGS VFS-IOR-F-PARTIAL "
                "AND 0<> AND _SR-RETRY-IOR 0= AND "
                "_SR-V _EXT4-CTX _SR-CTX = AND "
                "_SR-USED-BEFORE _SR-USED-AFTER = AND "
                "_SR-CTX _EXT4-C.J.MAP + @ _SR-MAP = AND "
                "_SR-CTX _EXT4-C.J.MAP-HASH + @ _SR-HASH = AND "
                "_SR-MAP 0<> AND _SR-HASH 0<> AND "
                "_SR-NO-WRITER AND "
                "_SR-CTX _EXT4-C.J.WRITER + @ 0= AND "
                "_SR-CTX _EXT4-C.J.WRITER-CURRENT + @ 0<> AND "
                "_SR-V _EXT4-READY? AND "
                "_SR-CTX _EXT4-C.RECOVERY + @ 0= AND "
                "_SR-CTX _EXT4-C.J.WRITE-ACTIVE + @ 0= AND "
                "_SR-CTX _EXT4-C.O.ACTIVE + @ 0= AND "
                "_SR-CTX _EXT4-C.O.CLEAR-PENDING + @ 0= AND "
                "_SR-FLAGS-BEFORE VFS-F-RO = AND "
                "_SR-V V.FLAGS @ _SR-FLAGS-BEFORE = AND "
                'IF ." EXT4-EMPTY-ORPHAN-SAME-BINDING-RETRIED" THEN'
            ),
        ],
        patches=patches,
        write_faults_by_ordinal={
            3: {
                "stage": "media",
                "sector_index": 0,
                "byte_index": 200,
                "result": STORAGE_RESULT_MEDIA_FAILURE,
                "command": STORAGE_CMD_WRITE,
            }
        },
        capture_media=media_path,
    )
    _assert_emitted(output, "EXT4-EMPTY-ORPHAN-SAME-BINDING-RETRIED")
    assert trace == first_mount_prefix + retry_trace
    assert media_path.is_file()
    assert _sha256(media_path) == media_sha256

    with media_path.open("rb") as source:
        source.seek(1024)
        final_super = source.read(block_size)
        source.seek(journal_physical * block_size)
        final_journal = source.read(block_size)
        source.seek(guard_physical * block_size)
        final_guard = source.read(block_size)
        source.seek(orphan_offset)
        final_orphan = source.read(len(orphan_afterimage))
    assert struct.unpack_from("<I", final_super, 0x60)[0] & 0x04 == 0
    assert struct.unpack_from("<I", final_super, 0x64)[0] & 0x0001_0000 == 0
    assert struct.unpack_from(">I", final_journal, 0x1C)[0] == 0
    assert struct.unpack_from(">I", final_journal, 0x28)[0] == 0x13
    assert not any(final_journal[0x5C:0x88])
    assert _jbd2_super_checksum_valid(final_journal)
    assert final_guard == bytes(block_size)
    assert final_orphan == orphan_afterimage


def test_active_modern_orphan_is_authenticated_before_recovery_refusal(
    canonical_images: dict[str, Path]
) -> None:
    path = canonical_images["primary-1k-i256"]
    output = run_forth(
        path,
        [
            "T-ARENA T-VOLUME EXT4-NEW CONSTANT _IOR CONSTANT _V",
            (
                "_IOR VFS-IOR-REASON . _IOR VFS-IOR-DETAIL . "
                "_V V.LIFECYCLE @ . _V V.BCTX @ DUP "
                "_EXT4-C.O.ACTIVE + @ . "
                "_EXT4-C.O.SLOTS + @ ."
            ),
        ],
        patches=_modern_orphan_patches(path, (11,)),
    )
    assert "11 5 0 1 2" in output, output[-1500:]


@pytest.mark.parametrize(
    ("entries", "orphan_present", "expected_state"),
    (
        ((11, 11), True, "2 4"),
        ((2,), True, "0 0"),
        ((11,), False, "0 0"),
    ),
)
def test_invalid_modern_orphan_sets_are_corruption(
    canonical_images: dict[str, Path],
    entries: tuple[int, ...],
    orphan_present: bool,
    expected_state: str,
) -> None:
    path = canonical_images["primary-1k-i256"]
    output = run_forth(
        path,
        [
            "T-ARENA T-VOLUME EXT4-NEW CONSTANT _IOR CONSTANT _V",
            (
                "_IOR VFS-IOR-REASON . _IOR VFS-IOR-DOMAIN . "
                "_IOR VFS-IOR-FLAGS . _IOR VFS-IOR-DETAIL . "
                "_V V.LIFECYCLE @ . _V V.BCTX @ DUP "
                "_EXT4-C.O.ACTIVE + @ . "
                "_EXT4-C.O.SLOTS + @ ."
            ),
        ],
        patches=_modern_orphan_patches(
            path, entries, orphan_present=orphan_present
        ),
    )
    assert f"10 3 4 13 0 {expected_state}" in output, output[-1500:]


@pytest.mark.parametrize(
    (
        "case",
        "links",
        "modern_entries",
        "expected_table",
        "expected_modern",
    ),
    (
        (
            "legacy-one",
            ((14, 0),),
            (),
            ((14, 1, 0, 0), (0, 0, 0, 0)),
            0,
        ),
        (
            "legacy-multi",
            ((14, 17), (17, 0)),
            (),
            (
                (0, 0, 0, 0),
                (17, 1, 0, 0),
                (14, 1, 17, 0),
                (0, 0, 0, 0),
            ),
            0,
        ),
        (
            "legacy-modern-union",
            ((14, 0),),
            (17,),
            (
                (0, 0, 0, 0),
                (17, 2, 0, 0),
                (14, 1, 0, 0),
                (0, 0, 0, 0),
            ),
            1,
        ),
    ),
)
def test_unified_orphan_plan_refuses_stably_and_reuses_workspace(
    canonical_images: dict[str, Path],
    tmp_path: Path,
    case: str,
    links: tuple[tuple[int, int], ...],
    modern_entries: tuple[int, ...],
    expected_table: tuple[tuple[int, int, int, int], ...],
    expected_modern: int,
) -> None:
    path = canonical_images["primary-1k-i256"]
    expected_legacy = len(links)
    expected_active = expected_legacy + expected_modern
    expected_slots = len(expected_table)
    patches = _legacy_orphan_patches(
        path, 14, links, modern_entries=modern_entries
    )

    plan_lines: list[str] = []
    plan_checks: list[str] = []
    for slot, fields in enumerate(expected_table):
        entry = f"_UO-PLAN-{slot}"
        check = f"{entry}-OK"
        plan_lines.append(
            f"{slot} _UO-CTX _EXT4-ORPHAN-TABLE-ENTRY CONSTANT {entry}"
        )
        field_checks = []
        for field, expected in enumerate(fields):
            address = entry if field == 0 else f"{entry} {field} CELLS +"
            field_checks.append(f"{address} @ {expected} =")
        plan_lines.append(_forth_conjunction(field_checks) + f" CONSTANT {check}")
        plan_checks.append(check)

    output, trace, _media_sha256 = run_recovery_forth(
        path,
        tmp_path / f"{case}-stable-refusal.img",
        [
            "T-ARENA CONSTANT _UO-ARENA",
            (
                "_UO-ARENA T-VOLUME EXT4-NEW "
                "CONSTANT _UO-FIRST-IOR CONSTANT _UO-V"
            ),
            "_UO-V _EXT4-CTX CONSTANT _UO-CTX",
            "_UO-ARENA ARENA-USED CONSTANT _UO-USED-BEFORE",
            "_UO-CTX _EXT4-C.O.TABLE + @ CONSTANT _UO-TABLE",
            "_UO-CTX _EXT4-C.O.SLOTS + @ CONSTANT _UO-SLOTS",
            "_UO-CTX _EXT4-C.O.ACTIVE + @ CONSTANT _UO-ACTIVE",
            (
                "_UO-CTX _EXT4-C.O.MODERN-ACTIVE + @ "
                "CONSTANT _UO-MODERN"
            ),
            (
                "_UO-CTX _EXT4-C.O.LEGACY-ACTIVE + @ "
                "CONSTANT _UO-LEGACY"
            ),
            "_UO-V _EXT4-MOUNT CONSTANT _UO-RETRY-IOR",
            "_UO-ARENA ARENA-USED CONSTANT _UO-USED-AFTER",
            *plan_lines,
            (
                _forth_conjunction(
                    [
                        "_UO-FIRST-IOR VFS-IOR-REASON "
                        "VFS-R-UNSUPPORTED =",
                        "_UO-FIRST-IOR VFS-IOR-DOMAIN "
                        "VFS-IOR-D-FORMAT =",
                        "_UO-FIRST-IOR VFS-IOR-FLAGS 0=",
                        "_UO-FIRST-IOR VFS-IOR-DETAIL "
                        "EXT4-D-RECOVERY =",
                        "_UO-RETRY-IOR VFS-IOR-REASON "
                        "VFS-R-UNSUPPORTED =",
                        "_UO-RETRY-IOR VFS-IOR-DOMAIN "
                        "VFS-IOR-D-FORMAT =",
                        "_UO-RETRY-IOR VFS-IOR-FLAGS 0=",
                        "_UO-RETRY-IOR VFS-IOR-DETAIL "
                        "EXT4-D-RECOVERY =",
                        "_UO-V V.LIFECYCLE @ VFS-L-NEW =",
                        "_UO-V _EXT4-READY? 0=",
                        "_UO-V _EXT4-CTX _UO-CTX =",
                        "_UO-USED-BEFORE _UO-USED-AFTER =",
                        "_UO-CTX _EXT4-C.O.TABLE + @ _UO-TABLE =",
                        "_UO-TABLE 0<>",
                        f"_UO-SLOTS {expected_slots} =",
                        (
                            "_UO-CTX _EXT4-C.O.SLOTS + @ "
                            f"{expected_slots} ="
                        ),
                        f"_UO-ACTIVE {expected_active} =",
                        (
                            "_UO-CTX _EXT4-C.O.ACTIVE + @ "
                            f"{expected_active} ="
                        ),
                        f"_UO-MODERN {expected_modern} =",
                        (
                            "_UO-CTX _EXT4-C.O.MODERN-ACTIVE + @ "
                            f"{expected_modern} ="
                        ),
                        f"_UO-LEGACY {expected_legacy} =",
                        (
                            "_UO-CTX _EXT4-C.O.LEGACY-ACTIVE + @ "
                            f"{expected_legacy} ="
                        ),
                        "_UO-CTX _EXT4-C.O.CLEAR-PENDING + @ 0=",
                        "_UO-CTX _EXT4-C.J.WRITER + @ 0=",
                        *plan_checks,
                    ]
                )
                + ' IF ." EXT4-UNIFIED-ORPHAN-STABLE" THEN'
            ),
        ],
        patches=patches,
    )
    _assert_emitted(output, "EXT4-UNIFIED-ORPHAN-STABLE")
    assert trace == ()


@pytest.mark.parametrize(
    (
        "case",
        "head",
        "links",
        "modern_entries",
        "bad_checksum_inode",
        "detail",
    ),
    (
        ("legacy-cycle", 14, ((14, 17), (17, 14)), (), None, 13),
        ("legacy-next-out-of-range", 14, ((14, -1),), (), None, 13),
        ("legacy-unallocated", 18, (), (), None, 8),
        ("legacy-inode-checksum", 14, ((14, 0),), (), 14, 10),
        ("cross-protocol-duplicate", 14, ((14, 0),), (14,), None, 13),
    ),
)
def test_unified_orphan_discovery_rejects_corruption_without_writes(
    canonical_images: dict[str, Path],
    tmp_path: Path,
    case: str,
    head: int,
    links: tuple[tuple[int, int], ...],
    modern_entries: tuple[int, ...],
    bad_checksum_inode: int | None,
    detail: int,
) -> None:
    path = canonical_images["primary-1k-i256"]
    layout = _ext4_recovery_layout(path)
    with path.open("rb") as source:
        source.seek(1024)
        superblock = source.read(1024)
    assert len(superblock) == 1024
    inode_count = struct.unpack_from("<I", superblock, 0x00)[0]

    if case == "legacy-next-out-of-range":
        links = ((14, inode_count + 1),)
    if case == "legacy-unallocated":
        inode_index = head - 1
        inodes_per_group = struct.unpack_from("<I", superblock, 0x28)[0]
        assert inode_index < inodes_per_group
        with path.open("rb") as source:
            source.seek(
                layout["inode_bitmap"] * layout["block_size"]
                + inode_index // 8
            )
            bitmap_byte = source.read(1)
        assert len(bitmap_byte) == 1
        assert bitmap_byte[0] & (1 << (inode_index % 8)) == 0

    patches = _legacy_orphan_patches(
        path,
        head,
        links,
        modern_entries=modern_entries,
        bad_checksum_inode=bad_checksum_inode,
    )
    cross_protocol_checks = []
    if case == "cross-protocol-duplicate":
        cross_protocol_checks = [
            "_UC-CTX _EXT4-C.O.ACTIVE + @ 2 =",
            "_UC-CTX _EXT4-C.O.MODERN-ACTIVE + @ 1 =",
            "_UC-CTX _EXT4-C.O.LEGACY-ACTIVE + @ 1 =",
            "_UC-CTX _EXT4-C.O.SLOTS + @ 4 =",
        ]

    output, trace, _media_sha256 = run_recovery_forth(
        path,
        tmp_path / f"{case}-rejected.img",
        [
            "T-ARENA T-VOLUME EXT4-NEW CONSTANT _UC-IOR CONSTANT _UC-V",
            "_UC-V _EXT4-CTX CONSTANT _UC-CTX",
            (
                _forth_conjunction(
                    [
                        "_UC-IOR VFS-IOR-REASON VFS-R-CORRUPT =",
                        "_UC-IOR VFS-IOR-DOMAIN VFS-IOR-D-FORMAT =",
                        "_UC-IOR VFS-IOR-FLAGS VFS-IOR-F-CORRUPT =",
                        f"_UC-IOR VFS-IOR-DETAIL {detail} =",
                        "_UC-V V.LIFECYCLE @ VFS-L-NEW =",
                        "_UC-V _EXT4-READY? 0=",
                        "_UC-CTX _EXT4-C.J.WRITER + @ 0=",
                        *cross_protocol_checks,
                    ]
                )
                + ' IF ." EXT4-UNIFIED-ORPHAN-CORRUPTION" THEN'
            ),
        ],
        patches=patches,
    )
    _assert_emitted(output, "EXT4-UNIFIED-ORPHAN-CORRUPTION")
    assert trace == ()


@pytest.mark.parametrize(
    "image_id",
    ("primary-1k-i256", "primary-2k-i256", "primary-4k-i256"),
)
def test_typed_orphan_afterimages_coalesce_and_abort_without_io(
    canonical_images: dict[str, Path], image_id: str,
) -> None:
    path = canonical_images[image_id]
    patches = _modern_orphan_patches(path, (13, 14))
    superblock = patches[0][1]
    assert len(superblock) == 1024
    block_size = 1024 << struct.unpack_from("<I", superblock, 0x18)[0]
    inode_size = struct.unpack_from("<H", superblock, 0x58)[0]
    assert block_size in (1024, 2048, 4096)
    assert inode_size == 256

    _, inode13, inode13_offset = _ext4_inode_record(path, 13)
    _, inode14, inode14_offset = _ext4_inode_record(path, 14)
    assert inode13_offset // block_size == inode14_offset // block_size
    inode_home = inode13_offset // block_size
    inode13_block_offset = inode13_offset % block_size
    inode14_block_offset = inode14_offset % block_size
    ctime13 = 0x1020_3040
    ctime14 = 0x5060_7080
    expected13 = bytearray(inode13)
    expected14 = bytearray(inode14)
    struct.pack_into("<I", expected13, 0x0C, ctime13)
    struct.pack_into("<I", expected14, 0x0C, ctime14)
    expected13 = bytearray(_inode_with_checksum(superblock, 13, expected13))
    expected14 = bytearray(_inode_with_checksum(superblock, 14, expected14))
    expected13_low = struct.unpack_from("<H", expected13, 0x7C)[0]
    expected13_high = struct.unpack_from("<H", expected13, 0x82)[0]
    expected14_low = struct.unpack_from("<H", expected14, 0x7C)[0]
    expected14_high = struct.unpack_from("<H", expected14, 0x82)[0]

    orphan_offset, authored_orphan = patches[1]
    assert orphan_offset % block_size == 0
    orphan_home = orphan_offset // block_size
    expected_orphan = bytearray(authored_orphan)
    assert struct.unpack_from("<II", expected_orphan, 0) == (13, 14)
    struct.pack_into("<I", expected_orphan, 0, 0)
    orphan_inode_number = struct.unpack_from("<I", superblock, 0x280)[0]
    _, orphan_inode, _ = _ext4_inode_record(path, orphan_inode_number)
    orphan_generation = struct.unpack_from("<I", orphan_inode, 0x64)[0]
    seed = struct.unpack_from("<I", superblock, 0x270)[0]
    orphan_checksum = _crc32c_raw(
        struct.pack(
            "<IIQ", orphan_inode_number, orphan_generation, orphan_home
        ),
        seed,
    )
    orphan_checksum = _crc32c_raw(
        expected_orphan[: block_size - 8], orphan_checksum
    )
    struct.pack_into("<I", expected_orphan, block_size - 4, orphan_checksum)

    output = run_forth(
        path,
        [
            (
                "T-ARENA T-VOLUME EXT4-NEW "
                "CONSTANT _TO-MOUNT-IOR CONSTANT _TO-V"
            ),
            "_TO-V _EXT4-CTX CONSTANT _TO-CTX",
            "1 _TO-CTX _EXT4-ORPHAN-TABLE-ENTRY CONSTANT _TO-R13",
            "2 _TO-CTX _EXT4-ORPHAN-TABLE-ENTRY CONSTANT _TO-R14",
            (
                _forth_conjunction(
                    [
                        "_TO-MOUNT-IOR VFS-IOR-REASON VFS-R-UNSUPPORTED =",
                        "_TO-MOUNT-IOR VFS-IOR-DETAIL EXT4-D-RECOVERY =",
                        "_TO-V V.LIFECYCLE @ VFS-L-NEW =",
                        "_TO-V _EXT4-READY? 0=",
                        "_TO-CTX _EXT4-C.O.ACTIVE + @ 2 =",
                        "_TO-CTX _EXT4-C.O.SLOTS + @ 4 =",
                        "_TO-R13 _EXT4-OE.INO + @ 13 =",
                        "_TO-R13 _EXT4-OE.KIND + @ _EXT4-OK-MODERN =",
                        "_TO-R13 _EXT4-OE.LOCATOR-A + @ 0=",
                        "_TO-R13 _EXT4-OE.LOCATOR-B + @ 0=",
                        "_TO-R14 _EXT4-OE.INO + @ 14 =",
                        "_TO-R14 _EXT4-OE.KIND + @ _EXT4-OK-MODERN =",
                        "_TO-R14 _EXT4-OE.LOCATOR-A + @ 0=",
                        "_TO-R14 _EXT4-OE.LOCATOR-B + @ 1 =",
                    ]
                )
                + ' IF ." EXT4-TYPED-PLAN-AUTHENTICATED" THEN'
            ),
            (
                "_TO-CTX _EXT4-VALIDATE-JOURNAL "
                "CONSTANT _TO-JOURNAL-IOR"
            ),
            "-1 _TO-CTX _EXT4-C.J.WRITER-CURRENT + !",
            (
                "2 0 0 _TO-CTX _EXT4-JWR-ENSURE "
                "CONSTANT _TO-WRITER-IOR CONSTANT _TO-WRITER"
            ),
            "_TO-WRITER _EXT4-JWR.FREE + @ CONSTANT _TO-FREE-BEFORE",
            (
                "2 0 0 _TO-WRITER _EXT4-JTX-BEGIN "
                "CONSTANT _TO-TX-IOR CONSTANT _TO-TX"
            ),
            "13 _TO-CTX _EXT4-LOAD-ORPHAN-INODE CONSTANT _TO-L13",
            "_EXT4-IR-BLOCK @ CONSTANT _TO-INODE-HOME",
            "_EXT4-IR-OFF @ CONSTANT _TO-OFF13",
            (
                f"{ctime13} _TO-CTX _EXT4-C.INODE + "
                "_EXT4-I.CTIME + L!"
            ),
            (
                "_TO-CTX _EXT4-C.INODE + _TO-R13 _TO-TX "
                "_EXT4-JTX-STAGE-ORPHAN-INODE CONSTANT _TO-S13"
            ),
            "14 _TO-CTX _EXT4-LOAD-ORPHAN-INODE CONSTANT _TO-L14",
            "_EXT4-IR-BLOCK @ CONSTANT _TO-INODE-HOME14",
            "_EXT4-IR-OFF @ CONSTANT _TO-OFF14",
            (
                f"{ctime14} _TO-CTX _EXT4-C.INODE + "
                "_EXT4-I.CTIME + L!"
            ),
            (
                "_TO-CTX _EXT4-C.INODE + _TO-R14 _TO-TX "
                "_EXT4-JTX-STAGE-ORPHAN-INODE CONSTANT _TO-S14"
            ),
            (
                "_TO-R13 _TO-TX _EXT4-JTX-CLEAR-MODERN-ORPHAN-SLOT "
                "CONSTANT _TO-SLOT-IOR"
            ),
            "_EXT4-OV-PHYS @ CONSTANT _TO-ORPHAN-HOME",
            "0 _TO-WRITER _EXT4-JWR-META-IMAGE CONSTANT _TO-INODE-IMAGE",
            "1 _TO-WRITER _EXT4-JWR-META-IMAGE CONSTANT _TO-ORPHAN-IMAGE",
            (
                _forth_conjunction(
                    [
                        "_TO-JOURNAL-IOR 0=",
                        "_TO-WRITER-IOR 0=",
                        "_TO-TX-IOR 0=",
                        "_TO-L13 0=",
                        "_TO-L14 0=",
                        "_TO-S13 0=",
                        "_TO-S14 0=",
                        "_TO-SLOT-IOR 0=",
                        f"_TO-INODE-HOME {inode_home} =",
                        "_TO-INODE-HOME14 _TO-INODE-HOME =",
                        f"_TO-OFF13 {inode13_block_offset} =",
                        f"_TO-OFF14 {inode14_block_offset} =",
                        f"_TO-ORPHAN-HOME {orphan_home} =",
                        "_TO-WRITER _EXT4-JWR.META-USED + @ 2 =",
                        "_TO-WRITER _EXT4-JWR.META-ACTIVE + @ 2 =",
                        "_TO-WRITER _EXT4-JTX-TABLES-VALID?",
                        (
                            "0 _TO-WRITER _EXT4-JWR-META-ENTRY @ "
                            "_TO-INODE-HOME ="
                        ),
                        (
                            "1 _TO-WRITER _EXT4-JWR-META-ENTRY @ "
                            "_TO-ORPHAN-HOME ="
                        ),
                        (
                            f"_TO-INODE-IMAGE _TO-OFF13 + "
                            f"_EXT4-I.CTIME + L@ {ctime13} ="
                        ),
                        (
                            f"_TO-INODE-IMAGE _TO-OFF14 + "
                            f"_EXT4-I.CTIME + L@ {ctime14} ="
                        ),
                        (
                            f"_TO-INODE-IMAGE _TO-OFF13 + "
                            f"_EXT4-I.CSUM-LO + W@ {expected13_low} ="
                        ),
                        (
                            f"_TO-INODE-IMAGE _TO-OFF13 + "
                            f"_EXT4-I.CSUM-HI + W@ {expected13_high} ="
                        ),
                        (
                            f"_TO-INODE-IMAGE _TO-OFF14 + "
                            f"_EXT4-I.CSUM-LO + W@ {expected14_low} ="
                        ),
                        (
                            f"_TO-INODE-IMAGE _TO-OFF14 + "
                            f"_EXT4-I.CSUM-HI + W@ {expected14_high} ="
                        ),
                        "_TO-ORPHAN-IMAGE L@ 0=",
                        "_TO-ORPHAN-IMAGE 4 + L@ 14 =",
                        (
                            f"_TO-ORPHAN-IMAGE {block_size - 8} + L@ "
                            "_EXT4-ORPHAN-MAGIC ="
                        ),
                        (
                            f"_TO-ORPHAN-IMAGE {block_size - 4} + L@ "
                            f"{orphan_checksum} ="
                        ),
                        (
                            "_TO-INODE-IMAGE _TO-WRITER "
                            "_EXT4-JTX-IMAGE-CRC 0 _TO-WRITER "
                            "_EXT4-JWR-META-ENTRY 2 CELLS + @ ="
                        ),
                        (
                            "_TO-ORPHAN-IMAGE _TO-WRITER "
                            "_EXT4-JTX-IMAGE-CRC 1 _TO-WRITER "
                            "_EXT4-JWR-META-ENTRY 2 CELLS + @ ="
                        ),
                    ]
                )
                + ' IF ." EXT4-TYPED-AFTERIMAGES-COALESCED" THEN'
            ),
            "_TO-TX _EXT4-JTX-ABORT CONSTANT _TO-ABORT-IOR",
            (
                _forth_conjunction(
                    [
                        "_TO-ABORT-IOR 0=",
                        (
                            "_TO-WRITER _EXT4-JWR.STATE + @ "
                            "_EXT4-JWR-IDLE ="
                        ),
                        (
                            "_TO-WRITER _EXT4-JWR.FREE + @ "
                            "_TO-FREE-BEFORE ="
                        ),
                        "_TO-WRITER _EXT4-JWR.META-USED + @ 0=",
                        "_TO-WRITER _EXT4-JWR.META-ACTIVE + @ 0=",
                        "_TO-WRITER _EXT4-JWR.META-IMAGES + @ C@ 0=",
                        "_TO-WRITER _EXT4-JWR.SCRATCH-A + @ C@ 0=",
                        "_TO-WRITER _EXT4-JWR.SCRATCH-B + @ C@ 0=",
                    ]
                )
                + ' IF ." EXT4-TYPED-AFTERIMAGES-ABORTED" THEN'
            ),
        ],
        patches=patches,
    )
    _assert_emitted(output, "EXT4-TYPED-PLAN-AUTHENTICATED")
    _assert_emitted(output, "EXT4-TYPED-AFTERIMAGES-COALESCED")
    _assert_emitted(output, "EXT4-TYPED-AFTERIMAGES-ABORTED")


def test_typed_orphan_staging_rejects_stale_and_conflicting_authority(
    canonical_images: dict[str, Path],
) -> None:
    path = canonical_images["primary-1k-i256"]
    patches = _modern_orphan_patches(path, (13, 14))
    output = run_forth(
        path,
        [
            (
                "T-ARENA T-VOLUME EXT4-NEW "
                "CONSTANT _TR-MOUNT-IOR CONSTANT _TR-V"
            ),
            "_TR-V _EXT4-CTX CONSTANT _TR-CTX",
            "1 _TR-CTX _EXT4-ORPHAN-TABLE-ENTRY CONSTANT _TR-R13",
            "_TR-CTX _EXT4-VALIDATE-JOURNAL CONSTANT _TR-JOURNAL-IOR",
            "-1 _TR-CTX _EXT4-C.J.WRITER-CURRENT + !",
            (
                "2 0 0 _TR-CTX _EXT4-JWR-ENSURE "
                "CONSTANT _TR-WRITER-IOR CONSTANT _TR-WRITER"
            ),
            (
                "2 0 0 _TR-WRITER _EXT4-JTX-BEGIN "
                "CONSTANT _TR-TX-IOR CONSTANT _TR-TX"
            ),
            "13 _TR-CTX _EXT4-LOAD-ORPHAN-INODE CONSTANT _TR-LOAD-IOR",
            "_EXT4-IR-BLOCK @ CONSTANT _TR-INODE-HOME",
            "_EXT4-IR-OFF @ CONSTANT _TR-INODE-OFF",
            "CREATE _TR-FIRST 256 ALLOT",
            (
                "_TR-CTX _EXT4-C.INODE + _TR-FIRST 256 CMOVE "
                "0x11223344 _TR-FIRST _EXT4-I.CTIME + L!"
            ),
            "CREATE _TR-SECOND 256 ALLOT",
            (
                "_TR-CTX _EXT4-C.INODE + _TR-SECOND 256 CMOVE "
                "0x55667788 _TR-SECOND _EXT4-I.CTIME + L!"
            ),
            "CREATE _TR-BAD-RECORD _EXT4-ORPHAN-RECORD-SIZE ALLOT",
            (
                "_TR-R13 _TR-BAD-RECORD _EXT4-ORPHAN-RECORD-SIZE CMOVE "
                "2 _TR-BAD-RECORD _EXT4-OE.LOCATOR-B + !"
            ),
            (
                "_TR-FIRST _TR-BAD-RECORD _TR-TX "
                "_EXT4-JTX-STAGE-ORPHAN-INODE CONSTANT _TR-STALE-IOR"
            ),
            "_TR-WRITER _EXT4-JWR.META-USED + @ CONSTANT _TR-USED-AFTER-STALE",
            (
                "_TR-FIRST _TR-R13 _TR-TX "
                "_EXT4-JTX-STAGE-ORPHAN-INODE CONSTANT _TR-FIRST-IOR"
            ),
            (
                "0 _TR-WRITER _EXT4-JWR-META-ENTRY 2 CELLS + @ "
                "CONSTANT _TR-FIRST-CRC"
            ),
            (
                "_TR-SECOND _TR-R13 _TR-TX "
                "_EXT4-JTX-STAGE-ORPHAN-INODE CONSTANT _TR-SECOND-IOR"
            ),
            (
                "_TR-R13 _TR-TX _EXT4-JTX-CLEAR-MODERN-ORPHAN-SLOT "
                "CONSTANT _TR-CLEAR-IOR"
            ),
            (
                "_TR-R13 _TR-TX _EXT4-JTX-CLEAR-MODERN-ORPHAN-SLOT "
                "CONSTANT _TR-RECLEAR-IOR"
            ),
            "1 0 _TR-WRITER _EXT4-JWR-META-ENTRY 2 CELLS + +!",
            "13 _TR-CTX _EXT4-LOAD-ORPHAN-INODE CONSTANT _TR-RELOAD-IOR",
            (
                "_TR-CTX _EXT4-C.BLOCK + _TR-INODE-HOME _TR-TX "
                "_EXT4-JTX-META-ACQUIRE "
                "CONSTANT _TR-ACQUIRE-IOR CONSTANT _TR-ACQUIRE-IMAGE"
            ),
            (
                "_TR-FIRST-CRC 0 _TR-WRITER _EXT4-JWR-META-ENTRY "
                "2 CELLS + !"
            ),
            (
                _forth_conjunction(
                    [
                        "_TR-MOUNT-IOR VFS-IOR-REASON VFS-R-UNSUPPORTED =",
                        "_TR-MOUNT-IOR VFS-IOR-DETAIL EXT4-D-RECOVERY =",
                        "_TR-JOURNAL-IOR 0=",
                        "_TR-WRITER-IOR 0=",
                        "_TR-TX-IOR 0=",
                        "_TR-LOAD-IOR 0=",
                        "_TR-STALE-IOR VFS-IOR-REASON VFS-R-CORRUPT =",
                        (
                            "_TR-STALE-IOR VFS-IOR-DETAIL "
                            "EXT4-D-ORPHAN-FILE ="
                        ),
                        "_TR-USED-AFTER-STALE 0=",
                        "_TR-FIRST-IOR 0=",
                        "_TR-SECOND-IOR VFS-E-CONFLICT =",
                        "_TR-CLEAR-IOR 0=",
                        "_TR-RECLEAR-IOR VFS-E-CONFLICT =",
                        "_TR-RELOAD-IOR 0=",
                        "_TR-ACQUIRE-IMAGE 0=",
                        "_TR-ACQUIRE-IOR VFS-E-CORRUPT =",
                        "_TR-WRITER _EXT4-JWR.META-USED + @ 2 =",
                        "_TR-WRITER _EXT4-JWR.META-ACTIVE + @ 2 =",
                        "_TR-WRITER _EXT4-JTX-TABLES-VALID?",
                        (
                            "0 _TR-WRITER _EXT4-JWR-META-IMAGE "
                            "_TR-INODE-OFF + _EXT4-I.CTIME + L@ "
                            "0x11223344 ="
                        ),
                        "1 _TR-WRITER _EXT4-JWR-META-IMAGE L@ 0=",
                    ]
                )
                + ' IF ." EXT4-TYPED-STALE-CONFLICT-ATOMIC" THEN'
            ),
            "_TR-TX _EXT4-JTX-ABORT CONSTANT _TR-ABORT-IOR",
            (
                _forth_conjunction(
                    [
                        "_TR-ABORT-IOR 0=",
                        (
                            "_TR-WRITER _EXT4-JWR.STATE + @ "
                            "_EXT4-JWR-IDLE ="
                        ),
                        "_TR-WRITER _EXT4-JWR.META-USED + @ 0=",
                        "_TR-WRITER _EXT4-JWR.SCRATCH-A + @ C@ 0=",
                        "_TR-WRITER _EXT4-JWR.SCRATCH-B + @ C@ 0=",
                    ]
                )
                + ' IF ." EXT4-TYPED-REJECTION-ABORTED" THEN'
            ),
        ],
        patches=patches,
    )
    _assert_emitted(output, "EXT4-TYPED-STALE-CONFLICT-ATOMIC")
    _assert_emitted(output, "EXT4-TYPED-REJECTION-ABORTED")


def test_typed_modern_orphan_slot_clear_rejects_target_xattr_alias(
    canonical_images: dict[str, Path],
) -> None:
    path = canonical_images["primary-1k-i256"]
    patches = list(_modern_orphan_patches(path, (14,)))
    superblock = patches[0][1]
    block_size = 1024 << struct.unpack_from("<I", superblock, 0x18)[0]
    orphan_home = patches[1][0] // block_size
    _, inode_bytes, inode_offset = _ext4_inode_record(path, 14)
    inode = bytearray(inode_bytes)
    assert struct.unpack_from("<H", inode, 0x76)[0] == 0
    assert struct.unpack_from("<I", inode, 0x68)[0] != orphan_home
    struct.pack_into("<I", inode, 0x68, orphan_home)
    patches.append(
        (inode_offset, _inode_with_checksum(superblock, 14, inode))
    )

    output = run_forth(
        path,
        [
            (
                "T-ARENA T-VOLUME EXT4-NEW "
                "CONSTANT _OX-MOUNT-IOR CONSTANT _OX-V"
            ),
            "_OX-V _EXT4-CTX CONSTANT _OX-CTX",
            "0 _OX-CTX _EXT4-ORPHAN-TABLE-ENTRY CONSTANT _OX-RECORD",
            "_OX-CTX _EXT4-VALIDATE-JOURNAL CONSTANT _OX-JOURNAL-IOR",
            "-1 _OX-CTX _EXT4-C.J.WRITER-CURRENT + !",
            (
                "1 0 0 _OX-CTX _EXT4-JWR-ENSURE "
                "CONSTANT _OX-WRITER-IOR CONSTANT _OX-WRITER"
            ),
            (
                "1 0 0 _OX-WRITER _EXT4-JTX-BEGIN "
                "CONSTANT _OX-TX-IOR CONSTANT _OX-TX"
            ),
            (
                "_OX-RECORD _OX-TX _EXT4-JTX-CLEAR-MODERN-ORPHAN-SLOT "
                "CONSTANT _OX-CLEAR-IOR"
            ),
            (
                _forth_conjunction(
                    [
                        (
                            "_OX-MOUNT-IOR VFS-IOR-REASON "
                            "VFS-R-UNSUPPORTED ="
                        ),
                        (
                            "_OX-MOUNT-IOR VFS-IOR-DETAIL "
                            "EXT4-D-RECOVERY ="
                        ),
                        "_OX-JOURNAL-IOR 0=",
                        "_OX-WRITER-IOR 0=",
                        "_OX-TX-IOR 0=",
                        (
                            "_OX-CLEAR-IOR VFS-IOR-REASON "
                            "VFS-R-CORRUPT ="
                        ),
                        (
                            "_OX-CLEAR-IOR VFS-IOR-DETAIL "
                            "EXT4-D-DATA-MAP ="
                        ),
                        (
                            "_OX-WRITER _EXT4-JWR.STATE + @ "
                            "_EXT4-JWR-STAGING ="
                        ),
                        "_OX-WRITER _EXT4-JWR.META-USED + @ 0=",
                        "_OX-WRITER _EXT4-JWR.META-ACTIVE + @ 0=",
                        "_OX-WRITER _EXT4-JTX-TABLES-VALID?",
                        "_OX-CTX _EXT4-C.J.HOME-WRITES + @ 0=",
                    ]
                )
                + ' IF ." EXT4-TYPED-ORPHAN-XATTR-ALIAS-REJECTED" THEN'
            ),
            "_OX-TX _EXT4-JTX-ABORT CONSTANT _OX-ABORT-IOR",
            (
                _forth_conjunction(
                    [
                        "_OX-ABORT-IOR 0=",
                        (
                            "_OX-WRITER _EXT4-JWR.STATE + @ "
                            "_EXT4-JWR-IDLE ="
                        ),
                    ]
                )
                + ' IF ." EXT4-TYPED-ORPHAN-XATTR-ALIAS-ABORTED" THEN'
            ),
        ],
        patches=tuple(patches),
    )
    _assert_emitted(output, "EXT4-TYPED-ORPHAN-XATTR-ALIAS-REJECTED")
    _assert_emitted(output, "EXT4-TYPED-ORPHAN-XATTR-ALIAS-ABORTED")


def test_mount_completes_singleton_modern_depth0_orphan_transaction(
    canonical_images: dict[str, Path], tmp_path: Path
) -> None:
    path = canonical_images["primary-1k-i256"]
    media_path = tmp_path / "modern-orphan-auto-cleanup.img"
    try:
        output, trace, _ = run_recovery_forth(
            path,
            media_path,
            [
                "T-ARENA CONSTANT _MA-ARENA",
                (
                    "_MA-ARENA T-VOLUME EXT4-NEW "
                    "CONSTANT _MA-IOR CONSTANT _MA-V"
                ),
                "_MA-V _EXT4-CTX CONSTANT _MA-CTX",
                (
                    _forth_conjunction(
                        [
                            "_MA-IOR 0=",
                            "_MA-V V.LIFECYCLE @ VFS-L-MOUNTED =",
                            "_MA-V _EXT4-READY?",
                            "_MA-V _EXT4-ATTACHED?",
                            "_MA-CTX _EXT4-C.RECOVERY + @ 0=",
                            "_MA-CTX _EXT4-C.J.WRITE-ACTIVE + @ 0=",
                            "_MA-CTX _EXT4-C.J.WRITER-CURRENT + @ -1 =",
                            "_MA-CTX _EXT4-C.J.WRITER + @ 0=",
                            "_MA-CTX _EXT4-C.ARENA + @ _MA-ARENA =",
                            "_EXT4-MOC-MARK-VALID @ 0=",
                            "_EXT4-MOC-MARK @ _MA-ARENA A.PTR @ =",
                            "_MA-CTX _EXT4-C.J.START + @ 0=",
                            "_MA-CTX _EXT4-C.J.WITNESS + @ 0=",
                            "_MA-CTX _EXT4-C.J.CLEANUP + @ 0=",
                            "_MA-CTX _EXT4-C.O.ACTIVE + @ 0=",
                            "_MA-CTX _EXT4-C.O.MODERN-ACTIVE + @ 0=",
                            "_MA-CTX _EXT4-C.O.LEGACY-ACTIVE + @ 0=",
                            "_MA-CTX _EXT4-C.O.CLEAR-PENDING + @ 0=",
                            (
                                "_MA-CTX _EXT4-C.SB + "
                                "_EXT4-SB.INCOMPAT + L@ "
                                "_EXT4-INCOMPAT-RECOVER AND 0="
                            ),
                            (
                                "_MA-CTX _EXT4-C.SB + "
                                "_EXT4-SB.RO-COMPAT + L@ "
                                "_EXT4-RO-ORPHAN-PRESENT AND 0="
                            ),
                        ]
                    )
                    + ' IF ." EXT4-MODERN-ORPHAN-AUTO-CLEANED" THEN'
                ),
            ],
            patches=_zero_size_depth0_orphan_patches(path),
        )
    finally:
        media_path.unlink(missing_ok=True)

    _assert_emitted(output, "EXT4-MODERN-ORPHAN-AUTO-CLEANED")
    assert any(kind == "write" for kind, _, _ in trace)
    assert any(kind == "flush" for kind, _, _ in trace)


def test_singleton_modern_depth0_cleanup_seals_and_freezes_transaction(
    canonical_images: dict[str, Path],
) -> None:
    path = canonical_images["primary-1k-i256"]
    output = run_forth(
        path,
        [
            *_EXT4_AUTH_ONLY_BINDING_FORTH,
            "T-ARENA CONSTANT _OF-ARENA",
            (
                "_OF-ARENA T-VOLUME EXT4-TEST-AUTH-NEW "
                "CONSTANT _OF-MOUNT-IOR CONSTANT _OF-V"
            ),
            "_OF-V _EXT4-CTX CONSTANT _OF-CTX",
            (
                _forth_conjunction(
                    [
                        (
                            "_OF-MOUNT-IOR VFS-IOR-REASON "
                            "VFS-R-UNSUPPORTED ="
                        ),
                        (
                            "_OF-MOUNT-IOR VFS-IOR-DETAIL "
                            "EXT4-D-RECOVERY ="
                        ),
                        "_OF-V V.LIFECYCLE @ VFS-L-NEW =",
                    ]
                )
                + ' IF ." EXT4-AUTH-ONLY-STOPPED" THEN'
            ),
            (
                _forth_conjunction(
                    [
                        "_OF-CTX _EXT4-C.READY + @ 0=",
                        "_OF-CTX _EXT4-C.J.WRITER + @ 0=",
                        "_OF-CTX _EXT4-C.J.WRITER-CURRENT + @ 0=",
                        "_OF-CTX _EXT4-C.J.WRITE-ACTIVE + @ 0=",
                        "_OF-CTX _EXT4-C.ARENA + @ _OF-ARENA =",
                    ]
                )
                + ' IF ." EXT4-AUTH-ONLY-WRITER-CLEAN" THEN'
            ),
            (
                _forth_conjunction(
                    [
                        "_OF-CTX _EXT4-C.O.ACTIVE + @ 1 =",
                        "_OF-CTX _EXT4-C.O.MODERN-ACTIVE + @ 1 =",
                        "_OF-CTX _EXT4-C.O.LEGACY-ACTIVE + @ 0=",
                    ]
                )
                + ' IF ." EXT4-AUTH-ONLY-ORPHAN" THEN'
            ),
            (
                _forth_conjunction(
                    [
                        "_OF-CTX _EXT4-C.RECOVERY + @ 0=",
                        "_OF-CTX _EXT4-C.J.START + @ 0=",
                        "_OF-CTX _EXT4-C.J.WITNESS + @ 0=",
                        "_OF-CTX _EXT4-C.J.CLEANUP + @ 0=",
                    ]
                )
                + ' IF ." EXT4-AUTH-ONLY-RECOVERY-CLEAN" THEN'
            ),
            "0 _OF-CTX _EXT4-ORPHAN-TABLE-ENTRY CONSTANT _OF-RECORD",
            "CREATE _OF-COPY _EXT4-ORPHAN-RECORD-SIZE ALLOT",
            (
                "_OF-RECORD _OF-COPY _EXT4-ORPHAN-RECORD-SIZE "
                "CMOVE"
            ),
            "_OF-CTX _EXT4-VALIDATE-JOURNAL CONSTANT _OF-JOURNAL-IOR",
            (
                "_OF-COPY _OF-CTX "
                "_EXT4-MEASURE-MODERN-ORPHAN-DEPTH0 "
                "CONSTANT _OF-COPY-IOR CONSTANT _OF-COPY-CREDIT"
            ),
            (
                "_OF-RECORD _OF-CTX "
                "_EXT4-MEASURE-MODERN-ORPHAN-DEPTH0 "
                "CONSTANT _OF-MEASURE-IOR CONSTANT _OF-CREDIT"
            ),
            (
                "_OF-CREDIT 0 0 _OF-CTX "
                "_EXT4-JTX-PREFLIGHT-CAPACITY "
                "CONSTANT _OF-CAPACITY-IOR"
            ),
            "-1 _OF-CTX _EXT4-C.J.WRITER-CURRENT + !",
            (
                "_OF-CREDIT 0 0 _OF-CTX _EXT4-JWR-ENSURE "
                "CONSTANT _OF-WRITER-IOR CONSTANT _OF-WRITER"
            ),
            (
                "_OF-CREDIT 0 0 _OF-WRITER _EXT4-JTX-BEGIN "
                "CONSTANT _OF-TX-IOR CONSTANT _OF-TX"
            ),
            (
                "_OF-RECORD _OF-TX "
                "_EXT4-JTX-STAGE-MODERN-ORPHAN-DEPTH0-FINAL "
                "CONSTANT _OF-STAGE-IOR"
            ),
            (
                "2000 _OF-TX _EXT4-JTX-DATA-ZERO "
                "CONSTANT _OF-MUTATE-IOR"
            ),
            (
                _forth_conjunction(
                    [
                        (
                            "_OF-MOUNT-IOR VFS-IOR-REASON "
                            "VFS-R-UNSUPPORTED ="
                        ),
                        (
                            "_OF-MOUNT-IOR VFS-IOR-DETAIL "
                            "EXT4-D-RECOVERY ="
                        ),
                        "_OF-JOURNAL-IOR 0=",
                        "_OF-COPY-CREDIT 0=",
                        (
                            "_OF-COPY-IOR VFS-IOR-REASON "
                            "VFS-R-CORRUPT ="
                        ),
                        (
                            "_OF-COPY-IOR VFS-IOR-DETAIL "
                            "EXT4-D-ORPHAN-FILE ="
                        ),
                        "_OF-MEASURE-IOR 0=",
                        "_OF-CREDIT 5 =",
                        "_OF-CAPACITY-IOR 0=",
                        "_OF-WRITER-IOR 0=",
                        "_OF-TX-IOR 0=",
                        "_OF-STAGE-IOR 0=",
                        "_OF-MUTATE-IOR VFS-E-BUSY =",
                        (
                            "_OF-WRITER _EXT4-JWR.STATE + @ "
                            "_EXT4-JWR-STAGING ="
                        ),
                        (
                            "_OF-WRITER _EXT4-JWR.CP-MODE + @ "
                            "_EXT4-JCPM-ORPHAN-MODERN-FINAL ="
                        ),
                        "_OF-WRITER _EXT4-JWR.META-USED + @ 5 =",
                        "_OF-WRITER _EXT4-JWR.META-ACTIVE + @ 5 =",
                        "_OF-WRITER _EXT4-JWR.DATA-USED + @ 0=",
                        "_OF-WRITER _EXT4-JWR.REVOKE-USED + @ 0=",
                        "_OF-WRITER _EXT4-JWR-CP-AUTHORITY?",
                        "_OF-WRITER _EXT4-JTX-TABLES-VALID?",
                        "_OF-CTX _EXT4-C.J.HOME-WRITES + @ 0=",
                    ]
                )
                + ' IF ." EXT4-MODERN-FINAL-SEALED" THEN'
            ),
            "_OF-TX _EXT4-JTX-ABORT CONSTANT _OF-ABORT-IOR",
            (
                _forth_conjunction(
                    [
                        "_OF-ABORT-IOR 0=",
                        (
                            "_OF-WRITER _EXT4-JWR.STATE + @ "
                            "_EXT4-JWR-IDLE ="
                        ),
                        (
                            "_OF-WRITER _EXT4-JWR.CP-MODE + "
                            "_EXT4-JWR-SIZE _EXT4-JWR.CP-MODE - "
                            "_EXT4-BYTES-ZERO?"
                        ),
                        "_OF-WRITER _EXT4-JWR-TRANSACTION-CLEAN?",
                        "_OF-WRITER _EXT4-JWR-VALID?",
                    ]
                )
                + ' IF ." EXT4-MODERN-FINAL-ABORT-SCRUBBED" THEN'
            ),
        ],
        patches=_zero_size_depth0_orphan_patches(path),
    )
    _assert_emitted(output, "EXT4-AUTH-ONLY-STOPPED")
    _assert_emitted(output, "EXT4-AUTH-ONLY-WRITER-CLEAN")
    _assert_emitted(output, "EXT4-AUTH-ONLY-ORPHAN")
    _assert_emitted(output, "EXT4-AUTH-ONLY-RECOVERY-CLEAN")
    _assert_emitted(output, "EXT4-MODERN-FINAL-SEALED")
    _assert_emitted(output, "EXT4-MODERN-FINAL-ABORT-SCRUBBED")


def test_singleton_modern_depth0_credit_counts_cross_group_homes_exactly(
    canonical_images: dict[str, Path],
) -> None:
    path = canonical_images["primary-1k-i256"]
    output = run_forth(
        path,
        [
            *_EXT4_AUTH_ONLY_BINDING_FORTH,
            (
                "T-ARENA T-VOLUME EXT4-TEST-AUTH-NEW "
                "CONSTANT _OM-MOUNT-IOR CONSTANT _OM-V"
            ),
            "_OM-V _EXT4-CTX CONSTANT _OM-CTX",
            "0 _OM-CTX _EXT4-ORPHAN-TABLE-ENTRY CONSTANT _OM-RECORD",
            "_OM-CTX _EXT4-VALIDATE-JOURNAL CONSTANT _OM-JOURNAL-IOR",
            (
                "_OM-RECORD _OM-CTX "
                "_EXT4-MEASURE-MODERN-ORPHAN-DEPTH0 "
                "CONSTANT _OM-MEASURE1-IOR CONSTANT _OM-CREDIT1"
            ),
            (
                "_OM-RECORD _OM-CTX "
                "_EXT4-MEASURE-MODERN-ORPHAN-DEPTH0 "
                "CONSTANT _OM-MEASURE2-IOR CONSTANT _OM-CREDIT2"
            ),
            "-1 _OM-CTX _EXT4-C.J.WRITER-CURRENT + !",
            (
                "_OM-CREDIT1 0 0 _OM-CTX _EXT4-JWR-ENSURE "
                "CONSTANT _OM-WRITER-IOR CONSTANT _OM-WRITER"
            ),
            (
                "_OM-CREDIT1 0 0 _OM-WRITER _EXT4-JTX-BEGIN "
                "CONSTANT _OM-BEGIN-IOR CONSTANT _OM-TX"
            ),
            (
                "_OM-RECORD _OM-TX "
                "_EXT4-JTX-STAGE-MODERN-ORPHAN-DEPTH0-FINAL "
                "CONSTANT _OM-STAGE-IOR"
            ),
            (
                _forth_conjunction(
                    [
                        (
                            "_OM-MOUNT-IOR VFS-IOR-REASON "
                            "VFS-R-UNSUPPORTED ="
                        ),
                        (
                            "_OM-MOUNT-IOR VFS-IOR-DETAIL "
                            "EXT4-D-RECOVERY ="
                        ),
                        "_OM-JOURNAL-IOR 0=",
                        "_OM-MEASURE1-IOR 0=",
                        "_OM-MEASURE2-IOR 0=",
                        "_OM-CREDIT1 6 =",
                        "_OM-CREDIT2 _OM-CREDIT1 =",
                        "_OM-WRITER-IOR 0=",
                        "_OM-BEGIN-IOR 0=",
                        "_OM-STAGE-IOR 0=",
                        (
                            "_OM-WRITER _EXT4-JWR.META-USED + @ "
                            "_OM-CREDIT1 ="
                        ),
                        (
                            "_OM-WRITER _EXT4-JWR.META-ACTIVE + @ "
                            "_OM-CREDIT1 ="
                        ),
                        "_OM-WRITER _EXT4-JWR-CP-AUTHORITY?",
                        "_OM-WRITER _EXT4-JTX-TABLES-VALID?",
                        "_OM-CTX _EXT4-C.J.HOME-WRITES + @ 0=",
                    ]
                )
                + ' IF ." EXT4-MODERN-FINAL-CROSS-GROUP-CREDIT" THEN'
            ),
            "_OM-TX _EXT4-JTX-ABORT CONSTANT _OM-ABORT-IOR",
            (
                _forth_conjunction(
                    [
                        "_OM-ABORT-IOR 0=",
                        (
                            "_OM-WRITER _EXT4-JWR.STATE + @ "
                            "_EXT4-JWR-IDLE ="
                        ),
                        "_OM-WRITER _EXT4-JWR-TRANSACTION-CLEAN?",
                        "_OM-WRITER _EXT4-JWR-VALID?",
                    ]
                )
                + ' IF ." EXT4-MODERN-FINAL-CROSS-GROUP-ABORTED" THEN'
            ),
        ],
        patches=_cross_group_depth0_orphan_patches(path),
    )
    _assert_emitted(output, "EXT4-MODERN-FINAL-CROSS-GROUP-CREDIT")
    _assert_emitted(output, "EXT4-MODERN-FINAL-CROSS-GROUP-ABORTED")


def test_singleton_modern_depth0_cleanup_checkpoints_and_deactivates(
    canonical_images: dict[str, Path], tmp_path: Path
) -> None:
    path = canonical_images["primary-1k-i256"]
    media_path = tmp_path / "modern-final-checkpoint.img"
    try:
        output, trace, _ = run_recovery_forth(
            path,
            media_path,
            [
                *_EXT4_AUTH_ONLY_BINDING_FORTH,
                (
                    "T-ARENA T-VOLUME EXT4-TEST-AUTH-NEW "
                    "CONSTANT _OC-MOUNT-IOR CONSTANT _OC-V"
                ),
                "_OC-V _EXT4-CTX CONSTANT _OC-CTX",
                (
                    "0 _OC-CTX _EXT4-ORPHAN-TABLE-ENTRY "
                    "CONSTANT _OC-RECORD"
                ),
                (
                    "_OC-CTX _EXT4-VALIDATE-JOURNAL "
                    "CONSTANT _OC-JOURNAL-IOR"
                ),
                "-1 _OC-CTX _EXT4-C.J.WRITER-CURRENT + !",
                (
                    "5 0 0 _OC-CTX _EXT4-JWR-ENSURE "
                    "CONSTANT _OC-WRITER-IOR CONSTANT _OC-WRITER"
                ),
                (
                    "_OC-WRITER _EXT4-JWR-ACTIVATE "
                    "CONSTANT _OC-ACTIVATE-IOR"
                ),
                (
                    "5 0 0 _OC-WRITER _EXT4-JTX-BEGIN "
                    "CONSTANT _OC-BEGIN-IOR CONSTANT _OC-TX"
                ),
                (
                    "_OC-RECORD _OC-TX "
                    "_EXT4-JTX-STAGE-MODERN-ORPHAN-DEPTH0-FINAL "
                    "CONSTANT _OC-STAGE-IOR"
                ),
                "_OC-TX _EXT4-JTX-EMIT CONSTANT _OC-EMIT-IOR",
                (
                    "_OC-TX _EXT4-JTX-CHECKPOINT "
                    "CONSTANT _OC-CHECKPOINT-IOR"
                ),
                (
                    "_OC-CTX _EXT4-EMPTY-ORPHAN-RECOVERY? "
                    "CONSTANT _OC-EMPTY-AFTER-CHECKPOINT"
                ),
                (
                    "_OC-CTX _EXT4-C.READY + @ "
                    "CONSTANT _OC-READY-AFTER-CHECKPOINT"
                ),
                (
                    "_OC-WRITER _OC-V _EXT4-JWR-DEACTIVATE "
                    "CONSTANT _OC-DEACTIVATE-IOR"
                ),
                (
                    _forth_conjunction(
                        [
                            (
                                "_OC-MOUNT-IOR VFS-IOR-REASON "
                                "VFS-R-UNSUPPORTED ="
                            ),
                            (
                                "_OC-MOUNT-IOR VFS-IOR-DETAIL "
                                "EXT4-D-RECOVERY ="
                            ),
                            "_OC-JOURNAL-IOR 0=",
                            "_OC-WRITER-IOR 0=",
                            "_OC-ACTIVATE-IOR 0=",
                            "_OC-BEGIN-IOR 0=",
                            "_OC-STAGE-IOR 0=",
                            "_OC-EMIT-IOR 0=",
                            "_OC-CHECKPOINT-IOR 0=",
                            "_OC-EMPTY-AFTER-CHECKPOINT",
                            "_OC-READY-AFTER-CHECKPOINT 0=",
                            "_OC-DEACTIVATE-IOR 0=",
                            (
                                "_OC-WRITER _EXT4-JWR.STATE + @ "
                                "_EXT4-JWR-IDLE ="
                            ),
                            "_OC-WRITER _EXT4-JWR-IDLE-CLEAN?",
                            "_OC-WRITER _EXT4-JWR-VALID? 0=",
                            "_OC-CTX _EXT4-C.RECOVERY + @ 0=",
                            "_OC-CTX _EXT4-C.J.WRITE-ACTIVE + @ 0=",
                            "_OC-CTX _EXT4-C.J.START + @ 0=",
                            "_OC-CTX _EXT4-C.O.ACTIVE + @ 0=",
                            "_OC-CTX _EXT4-C.O.MODERN-ACTIVE + @ 0=",
                            "_OC-CTX _EXT4-C.O.LEGACY-ACTIVE + @ 0=",
                            "_OC-CTX _EXT4-C.O.CLEAR-PENDING + @ 0=",
                            (
                                "_OC-CTX _EXT4-C.SB + "
                                "_EXT4-SB.RO-COMPAT + L@ "
                                "_EXT4-RO-ORPHAN-PRESENT AND 0="
                            ),
                        ]
                    )
                    + ' IF ." EXT4-MODERN-FINAL-CHECKPOINTED" THEN'
                ),
            ],
            patches=_zero_size_depth0_orphan_patches(path),
        )
    finally:
        media_path.unlink(missing_ok=True)

    _assert_emitted(output, "EXT4-MODERN-FINAL-CHECKPOINTED")
    assert any(kind == "write" for kind, _, _ in trace)
    assert any(kind == "flush" for kind, _, _ in trace)


def test_already_truncated_modern_orphan_uses_slot_only_final_transaction(
    canonical_images: dict[str, Path], tmp_path: Path
) -> None:
    path = canonical_images["primary-1k-i256"]
    media_path = tmp_path / "modern-final-already-truncated.img"
    try:
        output, _, _ = run_recovery_forth(
            path,
            media_path,
            [
                *_EXT4_AUTH_ONLY_BINDING_FORTH,
                (
                    "T-ARENA T-VOLUME EXT4-TEST-AUTH-NEW "
                    "CONSTANT _OE-MOUNT-IOR CONSTANT _OE-V"
                ),
                "_OE-V _EXT4-CTX CONSTANT _OE-CTX",
                (
                    "0 _OE-CTX _EXT4-ORPHAN-TABLE-ENTRY "
                    "CONSTANT _OE-RECORD"
                ),
                (
                    "_OE-CTX _EXT4-VALIDATE-JOURNAL "
                    "CONSTANT _OE-JOURNAL-IOR"
                ),
                (
                    "_OE-RECORD _OE-CTX "
                    "_EXT4-MEASURE-MODERN-ORPHAN-DEPTH0 "
                    "CONSTANT _OE-MEASURE-IOR CONSTANT _OE-CREDIT"
                ),
                "-1 _OE-CTX _EXT4-C.J.WRITER-CURRENT + !",
                (
                    "_OE-CREDIT 0 0 _OE-CTX _EXT4-JWR-ENSURE "
                    "CONSTANT _OE-WRITER-IOR CONSTANT _OE-WRITER"
                ),
                (
                    "_OE-WRITER _EXT4-JWR-ACTIVATE "
                    "CONSTANT _OE-ACTIVATE-IOR"
                ),
                (
                    "_OE-CREDIT 0 0 _OE-WRITER _EXT4-JTX-BEGIN "
                    "CONSTANT _OE-BEGIN-IOR CONSTANT _OE-TX"
                ),
                (
                    "_OE-RECORD _OE-TX "
                    "_EXT4-JTX-STAGE-MODERN-ORPHAN-DEPTH0-FINAL "
                    "CONSTANT _OE-STAGE-IOR"
                ),
                (
                    _forth_conjunction(
                        [
                            "_OE-STAGE-IOR 0=",
                            "_OE-WRITER _EXT4-JWR.META-USED + @ 1 =",
                            "_OE-WRITER _EXT4-JWR.META-ACTIVE + @ 1 =",
                            (
                                "_OE-WRITER "
                                "_EXT4-JWR.CP-TARGET-ENTRIES + @ 0="
                            ),
                            (
                                "_OE-WRITER "
                                "_EXT4-JWR.CP-TARGET-CRC + @ 0="
                            ),
                        ]
                    )
                    + ' IF ." EXT4-MODERN-FINAL-SLOT-ONLY-SEALED" THEN'
                ),
                "_OE-TX _EXT4-JTX-EMIT CONSTANT _OE-EMIT-IOR",
                (
                    "_OE-TX _EXT4-JTX-CHECKPOINT "
                    "CONSTANT _OE-CHECKPOINT-IOR"
                ),
                (
                    "_OE-CTX _EXT4-C.READY + @ "
                    "CONSTANT _OE-READY-AFTER-CHECKPOINT"
                ),
                (
                    "_OE-CTX _EXT4-EMPTY-ORPHAN-RECOVERY? "
                    "CONSTANT _OE-EMPTY-AFTER-CHECKPOINT"
                ),
                (
                    "_OE-WRITER _OE-V _EXT4-JWR-DEACTIVATE "
                    "CONSTANT _OE-DEACTIVATE-IOR"
                ),
                (
                    _forth_conjunction(
                        [
                            (
                                "_OE-MOUNT-IOR VFS-IOR-REASON "
                                "VFS-R-UNSUPPORTED ="
                            ),
                            (
                                "_OE-MOUNT-IOR VFS-IOR-DETAIL "
                                "EXT4-D-RECOVERY ="
                            ),
                            "_OE-JOURNAL-IOR 0=",
                            "_OE-MEASURE-IOR 0=",
                            "_OE-CREDIT 1 =",
                            "_OE-WRITER-IOR 0=",
                            "_OE-ACTIVATE-IOR 0=",
                            "_OE-BEGIN-IOR 0=",
                            "_OE-STAGE-IOR 0=",
                            "_OE-EMIT-IOR 0=",
                            "_OE-CHECKPOINT-IOR 0=",
                            "_OE-READY-AFTER-CHECKPOINT 0=",
                            "_OE-EMPTY-AFTER-CHECKPOINT",
                            "_OE-DEACTIVATE-IOR 0=",
                            "_OE-CTX _EXT4-C.RECOVERY + @ 0=",
                            (
                                "_OE-CTX _EXT4-C.SB + "
                                "_EXT4-SB.RO-COMPAT + L@ "
                                "_EXT4-RO-ORPHAN-PRESENT AND 0="
                            ),
                        ]
                    )
                    + ' IF ." EXT4-MODERN-FINAL-SLOT-ONLY-LANDED" THEN'
                ),
            ],
            patches=_already_truncated_depth0_orphan_patches(path),
        )
    finally:
        media_path.unlink(missing_ok=True)

    _assert_emitted(output, "EXT4-MODERN-FINAL-SLOT-ONLY-SEALED")
    _assert_emitted(output, "EXT4-MODERN-FINAL-SLOT-ONLY-LANDED")


def test_singleton_modern_cleanup_rejects_certificate_substitution_prehome(
    canonical_images: dict[str, Path], tmp_path: Path
) -> None:
    path = canonical_images["primary-1k-i256"]
    media_path = tmp_path / "modern-final-certificate-substitution.img"
    try:
        output, _, _ = run_recovery_forth(
            path,
            media_path,
            [
                *_EXT4_AUTH_ONLY_BINDING_FORTH,
                (
                    "T-ARENA T-VOLUME EXT4-TEST-AUTH-NEW "
                    "CONSTANT _OS-MOUNT-IOR CONSTANT _OS-V"
                ),
                "_OS-V _EXT4-CTX CONSTANT _OS-CTX",
                (
                    "0 _OS-CTX _EXT4-ORPHAN-TABLE-ENTRY "
                    "CONSTANT _OS-RECORD"
                ),
                (
                    "_OS-CTX _EXT4-VALIDATE-JOURNAL "
                    "CONSTANT _OS-JOURNAL-IOR"
                ),
                "-1 _OS-CTX _EXT4-C.J.WRITER-CURRENT + !",
                (
                    "5 0 0 _OS-CTX _EXT4-JWR-ENSURE "
                    "CONSTANT _OS-WRITER-IOR CONSTANT _OS-WRITER"
                ),
                (
                    "_OS-WRITER _EXT4-JWR-ACTIVATE "
                    "CONSTANT _OS-ACTIVATE-IOR"
                ),
                (
                    "5 0 0 _OS-WRITER _EXT4-JTX-BEGIN "
                    "CONSTANT _OS-BEGIN-IOR CONSTANT _OS-TX"
                ),
                (
                    "_OS-RECORD _OS-TX "
                    "_EXT4-JTX-STAGE-MODERN-ORPHAN-DEPTH0-FINAL "
                    "CONSTANT _OS-STAGE-IOR"
                ),
                "_OS-TX _EXT4-JTX-EMIT CONSTANT _OS-EMIT-IOR",
                (
                    "1 _OS-WRITER _EXT4-JWR.CP-O-SLOT + +! "
                    "_OS-WRITER _EXT4-JWR-VALID? "
                    "CONSTANT _OS-STRUCTURALLY-VALID"
                ),
                (
                    "_OS-TX _EXT4-JTX-CHECKPOINT "
                    "CONSTANT _OS-CHECKPOINT-IOR"
                ),
                (
                    "_OS-TX _EXT4-JTX-CHECKPOINT "
                    "CONSTANT _OS-RETRY-IOR"
                ),
                (
                    _forth_conjunction(
                        [
                            (
                                "_OS-MOUNT-IOR VFS-IOR-REASON "
                                "VFS-R-UNSUPPORTED ="
                            ),
                            (
                                "_OS-MOUNT-IOR VFS-IOR-DETAIL "
                                "EXT4-D-RECOVERY ="
                            ),
                            "_OS-JOURNAL-IOR 0=",
                            "_OS-WRITER-IOR 0=",
                            "_OS-ACTIVATE-IOR 0=",
                            "_OS-BEGIN-IOR 0=",
                            "_OS-STAGE-IOR 0=",
                            "_OS-EMIT-IOR 0=",
                            "_OS-STRUCTURALLY-VALID",
                            (
                                "_OS-CHECKPOINT-IOR VFS-IOR-REASON "
                                "VFS-R-CORRUPT ="
                            ),
                            (
                                "_OS-CHECKPOINT-IOR VFS-IOR-DETAIL "
                                "EXT4-D-ORPHAN-FILE ="
                            ),
                            "_OS-RETRY-IOR VFS-E-BUSY =",
                            (
                                "_OS-WRITER _EXT4-JWR.STATE + @ "
                                "_EXT4-JWR-FAULTED ="
                            ),
                            (
                                "_OS-WRITER _EXT4-JWR.PHASE + @ "
                                "_EXT4-JWP-CHECKPOINT-PREFLIGHT ="
                            ),
                            "_OS-CTX _EXT4-C.J.HOME-WRITES + @ 0=",
                        ]
                    )
                    + ' IF ." EXT4-MODERN-FINAL-SUBSTITUTION-REJECTED" THEN'
                ),
            ],
            patches=_zero_size_depth0_orphan_patches(path),
        )
    finally:
        media_path.unlink(missing_ok=True)

    _assert_emitted(output, "EXT4-MODERN-FINAL-SUBSTITUTION-REJECTED")


@pytest.mark.parametrize(
    ("image_id", "data_block", "xattr_block", "bitmap_home"),
    (
        ("primary-1k-i256", 1346, 1349, 259),
        ("primary-2k-i256", 1204, 1207, 129),
        ("primary-4k-i256", 2160, 2163, 65),
    ),
)
def test_typed_depth0_orphan_truncation_stages_exact_afterimages_without_io(
    canonical_images: dict[str, Path],
    image_id: str,
    data_block: int,
    xattr_block: int,
    bitmap_home: int,
) -> None:
    path = canonical_images[image_id]
    patches = _zero_size_depth0_orphan_patches(path)
    superblock = patches[0][1]
    orphan_home = patches[1][0] // (
        1024 << struct.unpack_from("<I", superblock, 0x18)[0]
    )
    inode_offset, zero_size_inode = patches[2]
    block_size = 1024 << struct.unpack_from("<I", superblock, 0x18)[0]
    sectors_per_block = block_size // 512
    first_data = struct.unpack_from("<I", superblock, 0x14)[0]
    blocks_per_group = struct.unpack_from("<I", superblock, 0x20)[0]
    seed = struct.unpack_from("<I", superblock, 0x270)[0]
    group, data_index = divmod(data_block - first_data, blocks_per_group)
    xattr_group, xattr_index = divmod(
        xattr_block - first_data, blocks_per_group
    )
    assert group == xattr_group == 0
    inode_home, inode_block_offset = divmod(inode_offset, block_size)
    gdt_home = 2 if block_size == 1024 else 1
    super_home = 1 if block_size == 1024 else 0
    super_offset = 0 if block_size == 1024 else 1024

    def read_block(block: int) -> bytearray:
        with path.open("rb") as source:
            source.seek(block * block_size)
            result = bytearray(source.read(block_size))
        assert len(result) == block_size
        return result

    terminal_inode = bytearray(zero_size_inode)
    assert struct.unpack_from("<HHHH", terminal_inode, 0x28) == (
        0xF30A,
        1,
        4,
        0,
    )
    assert struct.unpack_from("<I", terminal_inode, 0x1C)[0] == (
        2 * sectors_per_block
    )
    struct.pack_into("<H", terminal_inode, 0x2A, 0)
    terminal_inode[0x34:0x64] = bytes(48)
    struct.pack_into("<I", terminal_inode, 0x1C, sectors_per_block)
    struct.pack_into("<H", terminal_inode, 0x74, 0)
    terminal_inode = bytearray(
        _inode_with_checksum(superblock, 14, terminal_inode)
    )
    expected_inode_table = read_block(inode_home)
    expected_inode_table[
        inode_block_offset : inode_block_offset + len(terminal_inode)
    ] = terminal_inode

    expected_bitmap = read_block(bitmap_home)
    data_byte, data_bit = divmod(data_index, 8)
    xattr_byte, xattr_bit = divmod(xattr_index, 8)
    assert expected_bitmap[data_byte] & (1 << data_bit)
    assert expected_bitmap[xattr_byte] & (1 << xattr_bit)
    expected_bitmap[data_byte] &= ~(1 << data_bit)
    bitmap_checksum = _crc32c_raw(expected_bitmap, seed)

    expected_gdt = read_block(gdt_home)
    descriptor_offset = group * 64 % block_size
    descriptor = bytearray(
        expected_gdt[descriptor_offset : descriptor_offset + 64]
    )
    group_free_before = struct.unpack_from("<H", descriptor, 0x0C)[0] | (
        struct.unpack_from("<H", descriptor, 0x2C)[0] << 16
    )
    group_free_after = group_free_before + 1
    struct.pack_into("<H", descriptor, 0x0C, group_free_after & 0xFFFF)
    struct.pack_into("<H", descriptor, 0x2C, group_free_after >> 16)
    struct.pack_into("<H", descriptor, 0x18, bitmap_checksum & 0xFFFF)
    struct.pack_into("<H", descriptor, 0x38, bitmap_checksum >> 16)
    descriptor = bytearray(
        _group_descriptor_with_checksum(superblock, descriptor, group)
    )
    descriptor_checksum = struct.unpack_from("<H", descriptor, 0x1E)[0]
    expected_gdt[descriptor_offset : descriptor_offset + 64] = descriptor

    expected_super_home = read_block(super_home)
    expected_super_home[super_offset : super_offset + 1024] = superblock
    staged_super = bytearray(superblock)
    super_free_before = struct.unpack_from("<I", staged_super, 0x0C)[0]
    assert struct.unpack_from("<I", staged_super, 0x158)[0] == 0
    super_free_after = super_free_before + 1
    struct.pack_into("<I", staged_super, 0x0C, super_free_after)
    staged_super = bytearray(_ext4_super_with_checksum(staged_super))
    super_checksum = struct.unpack_from("<I", staged_super, 0x3FC)[0]
    expected_super_home[
        super_offset : super_offset + 1024
    ] = staged_super

    expected_inode_crc = _crc32c_raw(expected_inode_table)
    expected_gdt_crc = _crc32c_raw(expected_gdt)
    expected_bitmap_crc = _crc32c_raw(expected_bitmap)
    expected_super_crc = _crc32c_raw(expected_super_home)

    output = run_forth(
        path,
        [
            *_EXT4_AUTH_ONLY_BINDING_FORTH,
            (
                "T-ARENA T-VOLUME EXT4-TEST-AUTH-NEW "
                "CONSTANT _OT-MOUNT-IOR CONSTANT _OT-V"
            ),
            "_OT-V _EXT4-CTX CONSTANT _OT-CTX",
            "0 _OT-CTX _EXT4-ORPHAN-TABLE-ENTRY CONSTANT _OT-RECORD",
            "1 _OT-CTX _EXT4-ORPHAN-TABLE-ENTRY CONSTANT _OT-EMPTY",
            "CREATE _OT-COPY _EXT4-ORPHAN-RECORD-SIZE ALLOT",
            (
                "_OT-RECORD _OT-COPY _EXT4-ORPHAN-RECORD-SIZE "
                "CMOVE"
            ),
            (
                "_OT-RECORD _OT-EMPTY _EXT4-ORPHAN-RECORD-SIZE CMOVE "
                "_OT-EMPTY _OT-CTX _EXT4-ORPHAN-PLAN-MEMBER? "
                "CONSTANT _OT-INJECTED-MEMBER "
                "_OT-EMPTY _EXT4-ORPHAN-RECORD-SIZE 0 FILL"
            ),
            (
                "_OT-CTX _EXT4-C.FREE-BLOCKS + @ "
                "CONSTANT _OT-CONTEXT-FREE"
            ),
            (
                "_OT-CTX _EXT4-C.SB + _EXT4-SB.FREE-BLOCKS-LO + L@ "
                "CONSTANT _OT-CACHED-SUPER-FREE"
            ),
            "_OT-CTX _EXT4-VALIDATE-JOURNAL CONSTANT _OT-JOURNAL-IOR",
            "-1 _OT-CTX _EXT4-C.J.WRITER-CURRENT + !",
            (
                "4 0 0 _OT-CTX _EXT4-JWR-ENSURE "
                "CONSTANT _OT-WRITER-IOR CONSTANT _OT-WRITER"
            ),
            "_OT-WRITER _EXT4-JWR.FREE + @ CONSTANT _OT-FREE-BEFORE",
            (
                "4 0 0 _OT-WRITER _EXT4-JTX-BEGIN "
                "CONSTANT _OT-TX-IOR CONSTANT _OT-TX"
            ),
            (
                "_OT-COPY _OT-TX "
                "_EXT4-JTX-STAGE-ORPHAN-DEPTH0-TRUNCATE "
                "CONSTANT _OT-COPY-IOR"
            ),
            (
                "_OT-WRITER _EXT4-JWR.META-USED + @ "
                "CONSTANT _OT-USED-AFTER-COPY"
            ),
            (
                "_OT-RECORD _OT-TX "
                "_EXT4-JTX-STAGE-ORPHAN-DEPTH0-TRUNCATE "
                "CONSTANT _OT-STAGE-IOR"
            ),
            (
                "0 _OT-WRITER _EXT4-JWR-META-IMAGE "
                "CONSTANT _OT-INODE-IMAGE"
            ),
            (
                "1 _OT-WRITER _EXT4-JWR-META-IMAGE "
                "CONSTANT _OT-GDT-IMAGE"
            ),
            (
                "2 _OT-WRITER _EXT4-JWR-META-IMAGE "
                "CONSTANT _OT-BITMAP-IMAGE"
            ),
            (
                "3 _OT-WRITER _EXT4-JWR-META-IMAGE "
                "CONSTANT _OT-SUPER-IMAGE"
            ),
            (
                "_OT-CTX _EXT4-PREPARE-ORPHAN-FILE "
                "CONSTANT _OT-ORPHAN-PREP-IOR"
            ),
            (
                "0 _OT-CTX _EXT4-READ-ORPHAN-BLOCK "
                "CONSTANT _OT-ORPHAN-READ-IOR"
            ),
            "_OT-CTX _EXT4-C.BLOCK + L@ CONSTANT _OT-MEDIA-SLOT",
            (
                _forth_conjunction(
                    [
                        (
                            "_OT-MOUNT-IOR VFS-IOR-REASON "
                            "VFS-R-UNSUPPORTED ="
                        ),
                        (
                            "_OT-MOUNT-IOR VFS-IOR-DETAIL "
                            "EXT4-D-RECOVERY ="
                        ),
                        "_OT-JOURNAL-IOR 0=",
                        "_OT-WRITER-IOR 0=",
                        "_OT-TX-IOR 0=",
                        "_OT-RECORD _OT-CTX _EXT4-ORPHAN-PLAN-MEMBER?",
                        (
                            "_OT-COPY _OT-CTX "
                            "_EXT4-ORPHAN-PLAN-MEMBER? 0="
                        ),
                        (
                            "_OT-EMPTY _OT-CTX "
                            "_EXT4-ORPHAN-PLAN-MEMBER? 0="
                        ),
                        "_OT-INJECTED-MEMBER 0=",
                        (
                            "_OT-COPY-IOR VFS-IOR-REASON "
                            "VFS-R-CORRUPT ="
                        ),
                        (
                            "_OT-COPY-IOR VFS-IOR-DETAIL "
                            "EXT4-D-ORPHAN-FILE ="
                        ),
                        "_OT-USED-AFTER-COPY 0=",
                        "_OT-STAGE-IOR 0=",
                        "_OT-ORPHAN-PREP-IOR 0=",
                        "_OT-ORPHAN-READ-IOR 0=",
                        "_OT-MEDIA-SLOT 14 =",
                        "_OT-CTX _EXT4-C.O.ACTIVE + @ 1 =",
                        "_OT-RECORD _EXT4-OE.INO + @ 14 =",
                        (
                            "_OT-RECORD _EXT4-OE.KIND + @ "
                            "_EXT4-OK-MODERN ="
                        ),
                        "_OT-RECORD _EXT4-OE.LOCATOR-A + @ 0=",
                        "_OT-RECORD _EXT4-OE.LOCATOR-B + @ 0=",
                        "_OT-WRITER _EXT4-JWR.META-USED + @ 4 =",
                        "_OT-WRITER _EXT4-JWR.META-ACTIVE + @ 4 =",
                        "_OT-WRITER _EXT4-JTX-TABLES-VALID?",
                        (
                            "0 _OT-WRITER _EXT4-JWR-META-ENTRY @ "
                            f"{inode_home} ="
                        ),
                        (
                            "1 _OT-WRITER _EXT4-JWR-META-ENTRY @ "
                            f"{gdt_home} ="
                        ),
                        (
                            "2 _OT-WRITER _EXT4-JWR-META-ENTRY @ "
                            f"{bitmap_home} ="
                        ),
                        (
                            "3 _OT-WRITER _EXT4-JWR-META-ENTRY @ "
                            f"{super_home} ="
                        ),
                        (
                            f"0 _OT-WRITER _EXT4-JWR-META-ENTRY @ "
                            f"{orphan_home} <>"
                        ),
                        (
                            f"1 _OT-WRITER _EXT4-JWR-META-ENTRY @ "
                            f"{orphan_home} <>"
                        ),
                        (
                            f"2 _OT-WRITER _EXT4-JWR-META-ENTRY @ "
                            f"{orphan_home} <>"
                        ),
                        (
                            f"3 _OT-WRITER _EXT4-JWR-META-ENTRY @ "
                            f"{orphan_home} <>"
                        ),
                        (
                            f"_OT-INODE-IMAGE {inode_block_offset} + "
                            "_EXT4-I.SIZE-LO + L@ 0="
                        ),
                        (
                            f"_OT-INODE-IMAGE {inode_block_offset} + "
                            "_EXT4-I.SIZE-HI + L@ 0="
                        ),
                        (
                            f"_OT-INODE-IMAGE {inode_block_offset} + "
                            "_EXT4-I.BLOCKS-LO + L@ "
                            f"{sectors_per_block} ="
                        ),
                        (
                            f"_OT-INODE-IMAGE {inode_block_offset} + "
                            "_EXT4-I.BLOCKS-HI + W@ 0="
                        ),
                        (
                            f"_OT-INODE-IMAGE {inode_block_offset} + "
                            "_EXT4-I.FILE-ACL-LO + L@ "
                            f"{xattr_block} ="
                        ),
                        (
                            f"_OT-INODE-IMAGE {inode_block_offset} + "
                            "_EXT4-I.BLOCK + 2 + W@ 0="
                        ),
                        (
                            f"_OT-INODE-IMAGE {inode_block_offset} + "
                            "_EXT4-I.BLOCK + 12 + 48 "
                            "_EXT4-BYTES-ZERO?"
                        ),
                        (
                            f"_OT-BITMAP-IMAGE {data_index} 1 "
                            "_EXT4-BIT-RANGE-SET? 0="
                        ),
                        (
                            f"_OT-BITMAP-IMAGE {xattr_index} 1 "
                            "_EXT4-BIT-RANGE-SET?"
                        ),
                        (
                            f"_OT-GDT-IMAGE {descriptor_offset} + "
                            "_EXT4-GD.FREE-BLOCKS-LO + W@ "
                            f"{group_free_after & 0xFFFF} ="
                        ),
                        (
                            f"_OT-GDT-IMAGE {descriptor_offset} + "
                            "_EXT4-GD.FREE-BLOCKS-HI + W@ "
                            f"{group_free_after >> 16} ="
                        ),
                        (
                            f"_OT-GDT-IMAGE {descriptor_offset} + "
                            "_EXT4-GD.BLOCK-CSUM-LO + W@ "
                            f"{bitmap_checksum & 0xFFFF} ="
                        ),
                        (
                            f"_OT-GDT-IMAGE {descriptor_offset} + "
                            "_EXT4-GD.BLOCK-CSUM-HI + W@ "
                            f"{bitmap_checksum >> 16} ="
                        ),
                        (
                            f"_OT-GDT-IMAGE {descriptor_offset} + "
                            "_EXT4-GD.CHECKSUM + W@ "
                            f"{descriptor_checksum} ="
                        ),
                        (
                            f"_OT-SUPER-IMAGE {super_offset} + "
                            "_EXT4-SB.FREE-BLOCKS-LO + L@ "
                            f"{super_free_after} ="
                        ),
                        (
                            f"_OT-SUPER-IMAGE {super_offset} + "
                            f"_EXT4-SB.CHECKSUM + L@ {super_checksum} ="
                        ),
                        (
                            "_OT-INODE-IMAGE _OT-WRITER "
                            f"_EXT4-JTX-IMAGE-CRC {expected_inode_crc} ="
                        ),
                        (
                            "_OT-GDT-IMAGE _OT-WRITER "
                            f"_EXT4-JTX-IMAGE-CRC {expected_gdt_crc} ="
                        ),
                        (
                            "_OT-BITMAP-IMAGE _OT-WRITER "
                            f"_EXT4-JTX-IMAGE-CRC {expected_bitmap_crc} ="
                        ),
                        (
                            "_OT-SUPER-IMAGE _OT-WRITER "
                            f"_EXT4-JTX-IMAGE-CRC {expected_super_crc} ="
                        ),
                        "_OT-WRITER _EXT4-JWR.DATA-USED + @ 0=",
                        "_OT-WRITER _EXT4-JWR.REVOKE-USED + @ 0=",
                        "_OT-CTX _EXT4-C.J.HOME-WRITES + @ 0=",
                        (
                            "_OT-CTX _EXT4-C.FREE-BLOCKS + @ "
                            "_OT-CONTEXT-FREE ="
                        ),
                        (
                            "_OT-CTX _EXT4-C.SB + "
                            "_EXT4-SB.FREE-BLOCKS-LO + L@ "
                            "_OT-CACHED-SUPER-FREE ="
                        ),
                    ]
                )
                + ' IF ." EXT4-TYPED-DEPTH0-TRUNCATE" THEN'
            ),
            "_OT-TX _EXT4-JTX-ABORT CONSTANT _OT-ABORT-IOR",
            (
                _forth_conjunction(
                    [
                        "_OT-ABORT-IOR 0=",
                        (
                            "_OT-WRITER _EXT4-JWR.STATE + @ "
                            "_EXT4-JWR-IDLE ="
                        ),
                        (
                            "_OT-WRITER _EXT4-JWR.FREE + @ "
                            "_OT-FREE-BEFORE ="
                        ),
                        "_OT-WRITER _EXT4-JWR.META-USED + @ 0=",
                        "_OT-WRITER _EXT4-JWR.META-ACTIVE + @ 0=",
                        "_OT-WRITER _EXT4-JWR.META-IMAGES + @ C@ 0=",
                        "_OT-WRITER _EXT4-JWR.SCRATCH-A + @ C@ 0=",
                        "_OT-WRITER _EXT4-JWR.SCRATCH-B + @ C@ 0=",
                    ]
                )
                + ' IF ." EXT4-TYPED-DEPTH0-TRUNCATE-ABORTED" THEN'
            ),
        ],
        patches=patches,
    )
    _assert_emitted(output, "EXT4-TYPED-DEPTH0-TRUNCATE")
    _assert_emitted(output, "EXT4-TYPED-DEPTH0-TRUNCATE-ABORTED")


def test_typed_depth0_orphan_truncation_auto_aborts_partial_credit_failure(
    canonical_images: dict[str, Path],
) -> None:
    path = canonical_images["primary-1k-i256"]
    patches = _zero_size_depth0_orphan_patches(path)
    output = run_forth(
        path,
        [
            *_EXT4_AUTH_ONLY_BINDING_FORTH,
            (
                "T-ARENA T-VOLUME EXT4-TEST-AUTH-NEW "
                "CONSTANT _OA-MOUNT-IOR CONSTANT _OA-V"
            ),
            "_OA-V _EXT4-CTX CONSTANT _OA-CTX",
            "0 _OA-CTX _EXT4-ORPHAN-TABLE-ENTRY CONSTANT _OA-RECORD",
            "_OA-CTX _EXT4-VALIDATE-JOURNAL CONSTANT _OA-JOURNAL-IOR",
            "-1 _OA-CTX _EXT4-C.J.WRITER-CURRENT + !",
            (
                "4 0 0 _OA-CTX _EXT4-JWR-ENSURE "
                "CONSTANT _OA-WRITER-IOR CONSTANT _OA-WRITER"
            ),
            "_OA-WRITER _EXT4-JWR.FREE + @ CONSTANT _OA-FREE-BEFORE",
            (
                "3 0 0 _OA-WRITER _EXT4-JTX-BEGIN "
                "CONSTANT _OA-TX-IOR CONSTANT _OA-TX"
            ),
            (
                "_OA-RECORD _OA-TX "
                "_EXT4-JTX-STAGE-ORPHAN-DEPTH0-TRUNCATE "
                "CONSTANT _OA-STAGE-IOR"
            ),
            "_OA-TX _EXT4-JTX-EMIT CONSTANT _OA-EMIT-IOR",
            (
                _forth_conjunction(
                    [
                        (
                            "_OA-MOUNT-IOR VFS-IOR-REASON "
                            "VFS-R-UNSUPPORTED ="
                        ),
                        (
                            "_OA-MOUNT-IOR VFS-IOR-DETAIL "
                            "EXT4-D-RECOVERY ="
                        ),
                        "_OA-JOURNAL-IOR 0=",
                        "_OA-WRITER-IOR 0=",
                        "_OA-TX-IOR 0=",
                        "_OA-STAGE-IOR VFS-E-NOSPC =",
                        "_OA-EMIT-IOR VFS-E-BUSY =",
                        (
                            "_OA-WRITER _EXT4-JWR.STATE + @ "
                            "_EXT4-JWR-IDLE ="
                        ),
                        "_OA-WRITER _EXT4-JWR.FAULT + @ 0=",
                        (
                            "_OA-WRITER _EXT4-JWR.FREE + @ "
                            "_OA-FREE-BEFORE ="
                        ),
                        "_OA-WRITER _EXT4-JWR.META-USED + @ 0=",
                        "_OA-WRITER _EXT4-JWR.META-ACTIVE + @ 0=",
                        "_OA-WRITER _EXT4-JWR.DATA-USED + @ 0=",
                        "_OA-WRITER _EXT4-JWR.REVOKE-USED + @ 0=",
                        "_OA-WRITER _EXT4-JWR.META-IMAGES + @ C@ 0=",
                        "_OA-WRITER _EXT4-JWR.SCRATCH-A + @ C@ 0=",
                        "_OA-WRITER _EXT4-JWR.SCRATCH-B + @ C@ 0=",
                        "_OA-CTX _EXT4-C.J.HOME-WRITES + @ 0=",
                    ]
                )
                + ' IF ." EXT4-TYPED-DEPTH0-AUTO-ABORT" THEN'
            ),
            (
                "4 0 0 _OA-WRITER _EXT4-JTX-BEGIN "
                "CONSTANT _OA-RETRY-IOR CONSTANT _OA-RETRY"
            ),
            (
                "_OA-RECORD _OA-RETRY "
                "_EXT4-JTX-STAGE-ORPHAN-DEPTH0-TRUNCATE "
                "CONSTANT _OA-RETRY-STAGE-IOR"
            ),
            (
                "_OA-RETRY _EXT4-JTX-ABORT "
                "CONSTANT _OA-RETRY-ABORT-IOR"
            ),
            (
                _forth_conjunction(
                    [
                        "_OA-RETRY-IOR 0=",
                        "_OA-RETRY-STAGE-IOR 0=",
                        "_OA-RETRY-ABORT-IOR 0=",
                        (
                            "_OA-WRITER _EXT4-JWR.STATE + @ "
                            "_EXT4-JWR-IDLE ="
                        ),
                        "_OA-WRITER _EXT4-JWR.META-USED + @ 0=",
                        "_OA-WRITER _EXT4-JWR.FAULT + @ 0=",
                    ]
                )
                + ' IF ." EXT4-TYPED-DEPTH0-AUTO-ABORT-REUSABLE" THEN'
            ),
        ],
        patches=patches,
    )
    _assert_emitted(output, "EXT4-TYPED-DEPTH0-AUTO-ABORT")
    _assert_emitted(output, "EXT4-TYPED-DEPTH0-AUTO-ABORT-REUSABLE")


def test_typed_depth0_orphan_truncation_rejects_orphan_storage_alias(
    canonical_images: dict[str, Path],
) -> None:
    path = canonical_images["primary-1k-i256"]
    patches = list(_zero_size_depth0_orphan_patches(path))
    superblock = patches[0][1]
    block_size = 1024 << struct.unpack_from("<I", superblock, 0x18)[0]
    orphan_home = patches[1][0] // block_size
    inode_offset, inode_bytes = patches[2]
    inode = bytearray(inode_bytes)
    assert struct.unpack_from("<H", inode, 0x3A)[0] == 0
    assert struct.unpack_from("<I", inode, 0x3C)[0] == 1346
    struct.pack_into("<I", inode, 0x3C, orphan_home)
    patches[2] = (
        inode_offset,
        _inode_with_checksum(superblock, 14, inode),
    )

    output = run_forth(
        path,
        [
            (
                "T-ARENA T-VOLUME EXT4-NEW "
                "CONSTANT _OO-MOUNT-IOR CONSTANT _OO-V"
            ),
            "_OO-V _EXT4-CTX CONSTANT _OO-CTX",
            "0 _OO-CTX _EXT4-ORPHAN-TABLE-ENTRY CONSTANT _OO-RECORD",
            "_OO-CTX _EXT4-VALIDATE-JOURNAL CONSTANT _OO-JOURNAL-IOR",
            "-1 _OO-CTX _EXT4-C.J.WRITER-CURRENT + !",
            (
                "4 0 0 _OO-CTX _EXT4-JWR-ENSURE "
                "CONSTANT _OO-WRITER-IOR CONSTANT _OO-WRITER"
            ),
            (
                "4 0 0 _OO-WRITER _EXT4-JTX-BEGIN "
                "CONSTANT _OO-TX-IOR CONSTANT _OO-TX"
            ),
            (
                "_OO-RECORD _OO-TX "
                "_EXT4-JTX-STAGE-ORPHAN-DEPTH0-TRUNCATE "
                "CONSTANT _OO-STAGE-IOR"
            ),
            (
                _forth_conjunction(
                    [
                        (
                            "_OO-MOUNT-IOR VFS-IOR-REASON "
                            "VFS-R-UNSUPPORTED ="
                        ),
                        (
                            "_OO-MOUNT-IOR VFS-IOR-DETAIL "
                            "EXT4-D-RECOVERY ="
                        ),
                        "_OO-JOURNAL-IOR 0=",
                        "_OO-WRITER-IOR 0=",
                        "_OO-TX-IOR 0=",
                        (
                            "_OO-STAGE-IOR VFS-IOR-REASON "
                            "VFS-R-CORRUPT ="
                        ),
                        (
                            "_OO-STAGE-IOR VFS-IOR-DETAIL "
                            "EXT4-D-DATA-MAP ="
                        ),
                        (
                            "_OO-WRITER _EXT4-JWR.STATE + @ "
                            "_EXT4-JWR-STAGING ="
                        ),
                        "_OO-WRITER _EXT4-JWR.META-USED + @ 0=",
                        "_OO-WRITER _EXT4-JWR.META-ACTIVE + @ 0=",
                        "_OO-WRITER _EXT4-JTX-TABLES-VALID?",
                        "_OO-CTX _EXT4-C.J.HOME-WRITES + @ 0=",
                    ]
                )
                + ' IF ." EXT4-TYPED-DEPTH0-ORPHAN-ALIAS-REJECTED" THEN'
            ),
            "_OO-TX _EXT4-JTX-ABORT CONSTANT _OO-ABORT-IOR",
            (
                _forth_conjunction(
                    [
                        "_OO-ABORT-IOR 0=",
                        (
                            "_OO-WRITER _EXT4-JWR.STATE + @ "
                            "_EXT4-JWR-IDLE ="
                        ),
                        "_OO-WRITER _EXT4-JWR.META-USED + @ 0=",
                    ]
                )
                + ' IF ." EXT4-TYPED-DEPTH0-ORPHAN-ALIAS-ABORTED" THEN'
            ),
        ],
        patches=tuple(patches),
    )
    _assert_emitted(output, "EXT4-TYPED-DEPTH0-ORPHAN-ALIAS-REJECTED")
    _assert_emitted(output, "EXT4-TYPED-DEPTH0-ORPHAN-ALIAS-ABORTED")


def test_typed_depth0_orphan_truncation_rejects_xattr_orphan_preallocation(
    canonical_images: dict[str, Path],
) -> None:
    path = canonical_images["primary-1k-i256"]
    patches = list(_zero_size_depth0_orphan_patches(path))
    superblock = patches[0][1]
    block_size = 1024 << struct.unpack_from("<I", superblock, 0x18)[0]
    sectors_per_block = block_size // 512
    orphan_inode_number = struct.unpack_from("<I", superblock, 0x280)[0]
    _, raw_orphan_inode, orphan_inode_offset = _ext4_inode_record(
        path, orphan_inode_number
    )
    orphan_inode = bytearray(raw_orphan_inode)
    assert struct.unpack_from("<HHHH", orphan_inode, 0x28) == (
        0xF30A,
        1,
        4,
        0,
    )
    orphan_blocks = struct.unpack_from("<I", orphan_inode, 0x04)[0] // block_size
    assert orphan_blocks > 0
    first_length = struct.unpack_from("<H", orphan_inode, 0x38)[0]
    assert first_length == orphan_blocks
    target_inode = patches[2][1]
    assert struct.unpack_from("<H", target_inode, 0x76)[0] == 0
    target_xattr = struct.unpack_from("<I", target_inode, 0x68)[0]
    assert target_xattr > 0
    first_physical = struct.unpack_from("<I", orphan_inode, 0x3C)[0]
    assert not first_physical <= target_xattr < first_physical + first_length

    struct.pack_into("<H", orphan_inode, 0x2A, 2)
    struct.pack_into(
        "<IHHI",
        orphan_inode,
        0x40,
        orphan_blocks,
        1,
        0,
        target_xattr,
    )
    struct.pack_into(
        "<I",
        orphan_inode,
        0x1C,
        struct.unpack_from("<I", orphan_inode, 0x1C)[0] + sectors_per_block,
    )
    patches.append(
        (
            orphan_inode_offset,
            _inode_with_checksum(
                superblock, orphan_inode_number, orphan_inode
            ),
        )
    )

    output = run_forth(
        path,
        [
            (
                "T-ARENA T-VOLUME EXT4-NEW "
                "CONSTANT _OP-MOUNT-IOR CONSTANT _OP-V"
            ),
            "_OP-V _EXT4-CTX CONSTANT _OP-CTX",
            "0 _OP-CTX _EXT4-ORPHAN-TABLE-ENTRY CONSTANT _OP-RECORD",
            "_OP-CTX _EXT4-VALIDATE-JOURNAL CONSTANT _OP-JOURNAL-IOR",
            "-1 _OP-CTX _EXT4-C.J.WRITER-CURRENT + !",
            (
                "4 0 0 _OP-CTX _EXT4-JWR-ENSURE "
                "CONSTANT _OP-WRITER-IOR CONSTANT _OP-WRITER"
            ),
            (
                "4 0 0 _OP-WRITER _EXT4-JTX-BEGIN "
                "CONSTANT _OP-TX-IOR CONSTANT _OP-TX"
            ),
            (
                "_OP-RECORD _OP-TX "
                "_EXT4-JTX-STAGE-ORPHAN-DEPTH0-TRUNCATE "
                "CONSTANT _OP-STAGE-IOR"
            ),
            (
                _forth_conjunction(
                    [
                        (
                            "_OP-MOUNT-IOR VFS-IOR-REASON "
                            "VFS-R-UNSUPPORTED ="
                        ),
                        (
                            "_OP-MOUNT-IOR VFS-IOR-DETAIL "
                            "EXT4-D-RECOVERY ="
                        ),
                        "_OP-JOURNAL-IOR 0=",
                        "_OP-WRITER-IOR 0=",
                        "_OP-TX-IOR 0=",
                        (
                            "_OP-STAGE-IOR VFS-IOR-REASON "
                            "VFS-R-CORRUPT ="
                        ),
                        (
                            "_OP-STAGE-IOR VFS-IOR-DETAIL "
                            "EXT4-D-DATA-MAP ="
                        ),
                        (
                            "_OP-WRITER _EXT4-JWR.STATE + @ "
                            "_EXT4-JWR-STAGING ="
                        ),
                        "_OP-WRITER _EXT4-JWR.META-USED + @ 0=",
                        "_OP-WRITER _EXT4-JWR.META-ACTIVE + @ 0=",
                        "_OP-WRITER _EXT4-JTX-TABLES-VALID?",
                        "_OP-CTX _EXT4-C.J.HOME-WRITES + @ 0=",
                    ]
                )
                + ' IF ." EXT4-TYPED-DEPTH0-XATTR-PREALLOC-REJECTED" THEN'
            ),
            "_OP-TX _EXT4-JTX-ABORT CONSTANT _OP-ABORT-IOR",
            (
                _forth_conjunction(
                    [
                        "_OP-ABORT-IOR 0=",
                        (
                            "_OP-WRITER _EXT4-JWR.STATE + @ "
                            "_EXT4-JWR-IDLE ="
                        ),
                        "_OP-WRITER _EXT4-JWR.META-USED + @ 0=",
                    ]
                )
                + ' IF ." EXT4-TYPED-DEPTH0-XATTR-PREALLOC-ABORTED" THEN'
            ),
        ],
        patches=tuple(patches),
    )
    _assert_emitted(output, "EXT4-TYPED-DEPTH0-XATTR-PREALLOC-REJECTED")
    _assert_emitted(output, "EXT4-TYPED-DEPTH0-XATTR-PREALLOC-ABORTED")


@pytest.mark.parametrize(
    ("image_id", "first_block", "bitmap_home"),
    (
        ("primary-1k-i256", 1346, 259),
        ("primary-2k-i256", 1204, 129),
        ("primary-4k-i256", 2160, 65),
    ),
)
def test_typed_free_block_range_afterimages_compose_and_abort_without_io(
    canonical_images: dict[str, Path],
    image_id: str,
    first_block: int,
    bitmap_home: int,
) -> None:
    path = canonical_images[image_id]
    with path.open("rb") as source:
        source.seek(1024)
        superblock = source.read(1024)
    assert len(superblock) == 1024
    block_size = 1024 << struct.unpack_from("<I", superblock, 0x18)[0]
    first_data = struct.unpack_from("<I", superblock, 0x14)[0]
    blocks_per_group = struct.unpack_from("<I", superblock, 0x20)[0]
    seed = struct.unpack_from("<I", superblock, 0x270)[0]
    group, first_index = divmod(first_block - first_data, blocks_per_group)
    assert group == 0
    assert first_index + 5 <= blocks_per_group
    gdt_home = 2 if block_size == 1024 else 1
    super_home = 1 if block_size == 1024 else 0
    super_offset = 0 if block_size == 1024 else 1024

    def read_block(block: int) -> bytearray:
        with path.open("rb") as source:
            source.seek(block * block_size)
            result = bytearray(source.read(block_size))
        assert len(result) == block_size
        return result

    expected_bitmap = read_block(bitmap_home)
    for block_index in range(first_index, first_index + 5):
        byte_index, bit_index = divmod(block_index, 8)
        assert expected_bitmap[byte_index] & (1 << bit_index)
        expected_bitmap[byte_index] &= ~(1 << bit_index)
    bitmap_checksum = _crc32c_raw(expected_bitmap, seed)

    expected_gdt = read_block(gdt_home)
    descriptor_offset = group * 64 % block_size
    descriptor = bytearray(
        expected_gdt[descriptor_offset : descriptor_offset + 64]
    )
    group_free_before = struct.unpack_from("<H", descriptor, 0x0C)[0] | (
        struct.unpack_from("<H", descriptor, 0x2C)[0] << 16
    )
    group_free_after = group_free_before + 5
    struct.pack_into("<H", descriptor, 0x0C, group_free_after & 0xFFFF)
    struct.pack_into("<H", descriptor, 0x2C, group_free_after >> 16)
    struct.pack_into("<H", descriptor, 0x18, bitmap_checksum & 0xFFFF)
    struct.pack_into("<H", descriptor, 0x38, bitmap_checksum >> 16)
    descriptor = bytearray(
        _group_descriptor_with_checksum(superblock, descriptor, group)
    )
    descriptor_checksum = struct.unpack_from("<H", descriptor, 0x1E)[0]
    expected_gdt[descriptor_offset : descriptor_offset + 64] = descriptor

    expected_super_home = read_block(super_home)
    staged_super = bytearray(
        expected_super_home[super_offset : super_offset + 1024]
    )
    super_free_before = struct.unpack_from("<I", staged_super, 0x0C)[0]
    super_free_after = super_free_before + 5
    struct.pack_into("<I", staged_super, 0x0C, super_free_after)
    struct.pack_into("<I", staged_super, 0x158, 0)
    staged_super = bytearray(_ext4_super_with_checksum(staged_super))
    super_checksum = struct.unpack_from("<I", staged_super, 0x3FC)[0]
    expected_super_home[super_offset : super_offset + 1024] = staged_super

    expected_gdt_crc = _crc32c_raw(expected_gdt)
    expected_bitmap_crc = _crc32c_raw(expected_bitmap)
    expected_super_home_crc = _crc32c_raw(expected_super_home)

    output = run_forth(
        path,
        [
            (
                "T-ARENA T-VOLUME EXT4-NEW "
                "CONSTANT _FB-MOUNT-IOR CONSTANT _FB-V"
            ),
            "_FB-V _EXT4-CTX CONSTANT _FB-CTX",
            (
                "_FB-CTX _EXT4-C.FREE-BLOCKS + @ "
                "CONSTANT _FB-CONTEXT-FREE"
            ),
            (
                "_FB-CTX _EXT4-C.SB + _EXT4-SB.FREE-BLOCKS-LO + L@ "
                "CONSTANT _FB-CACHED-SUPER-FREE"
            ),
            (
                "3 0 0 _FB-CTX _EXT4-JWR-ENSURE "
                "CONSTANT _FB-WRITER-IOR CONSTANT _FB-WRITER"
            ),
            "_FB-WRITER _EXT4-JWR.FREE + @ CONSTANT _FB-FREE-BEFORE",
            (
                "3 0 0 _FB-WRITER _EXT4-JTX-BEGIN "
                "CONSTANT _FB-TX-IOR CONSTANT _FB-TX"
            ),
            (
                f"{first_block} 2 _FB-TX "
                "_EXT4-JTX-STAGE-FREE-BLOCK-RANGE CONSTANT _FB-FIRST-IOR"
            ),
            (
                f"{first_block + 2} 3 _FB-TX "
                "_EXT4-JTX-STAGE-FREE-BLOCK-RANGE CONSTANT _FB-SECOND-IOR"
            ),
            "0 _FB-WRITER _EXT4-JWR-META-IMAGE CONSTANT _FB-GDT-IMAGE",
            "1 _FB-WRITER _EXT4-JWR-META-IMAGE CONSTANT _FB-BITMAP-IMAGE",
            "2 _FB-WRITER _EXT4-JWR-META-IMAGE CONSTANT _FB-SUPER-IMAGE",
            (
                _forth_conjunction(
                    [
                        "_FB-MOUNT-IOR 0=",
                        "_FB-V V.LIFECYCLE @ VFS-L-MOUNTED =",
                        "_FB-WRITER-IOR 0=",
                        "_FB-TX-IOR 0=",
                        "_FB-FIRST-IOR 0=",
                        "_FB-SECOND-IOR 0=",
                        "_FB-WRITER _EXT4-JWR.META-USED + @ 3 =",
                        "_FB-WRITER _EXT4-JWR.META-ACTIVE + @ 3 =",
                        "_FB-WRITER _EXT4-JTX-TABLES-VALID?",
                        (
                            f"0 _FB-WRITER _EXT4-JWR-META-ENTRY @ "
                            f"{gdt_home} ="
                        ),
                        (
                            f"1 _FB-WRITER _EXT4-JWR-META-ENTRY @ "
                            f"{bitmap_home} ="
                        ),
                        (
                            f"2 _FB-WRITER _EXT4-JWR-META-ENTRY @ "
                            f"{super_home} ="
                        ),
                        (
                            f"_FB-BITMAP-IMAGE {first_index} 5 "
                            "_EXT4-BIT-RANGE-SET? 0="
                        ),
                        (
                            f"_FB-GDT-IMAGE {descriptor_offset} + "
                            f"_EXT4-GD.FREE-BLOCKS-LO + W@ "
                            f"{group_free_after & 0xFFFF} ="
                        ),
                        (
                            f"_FB-GDT-IMAGE {descriptor_offset} + "
                            f"_EXT4-GD.FREE-BLOCKS-HI + W@ "
                            f"{group_free_after >> 16} ="
                        ),
                        (
                            f"_FB-GDT-IMAGE {descriptor_offset} + "
                            f"_EXT4-GD.BLOCK-CSUM-LO + W@ "
                            f"{bitmap_checksum & 0xFFFF} ="
                        ),
                        (
                            f"_FB-GDT-IMAGE {descriptor_offset} + "
                            f"_EXT4-GD.BLOCK-CSUM-HI + W@ "
                            f"{bitmap_checksum >> 16} ="
                        ),
                        (
                            f"_FB-GDT-IMAGE {descriptor_offset} + "
                            f"_EXT4-GD.CHECKSUM + W@ "
                            f"{descriptor_checksum} ="
                        ),
                        (
                            f"_FB-SUPER-IMAGE {super_offset} + "
                            "_EXT4-SB.FREE-BLOCKS-LO + L@ "
                            f"{super_free_after} ="
                        ),
                        (
                            f"_FB-SUPER-IMAGE {super_offset} + "
                            "_EXT4-SB.FREE-BLOCKS-HI + L@ 0="
                        ),
                        (
                            f"_FB-SUPER-IMAGE {super_offset} + "
                            f"_EXT4-SB.CHECKSUM + L@ {super_checksum} ="
                        ),
                        (
                            f"_FB-GDT-IMAGE _FB-WRITER "
                            f"_EXT4-JTX-IMAGE-CRC {expected_gdt_crc} ="
                        ),
                        (
                            f"_FB-BITMAP-IMAGE _FB-WRITER "
                            f"_EXT4-JTX-IMAGE-CRC {expected_bitmap_crc} ="
                        ),
                        (
                            f"_FB-SUPER-IMAGE _FB-WRITER "
                            f"_EXT4-JTX-IMAGE-CRC {expected_super_home_crc} ="
                        ),
                        (
                            "_FB-CTX _EXT4-C.FREE-BLOCKS + @ "
                            "_FB-CONTEXT-FREE ="
                        ),
                        (
                            "_FB-CTX _EXT4-C.SB + "
                            "_EXT4-SB.FREE-BLOCKS-LO + L@ "
                            "_FB-CACHED-SUPER-FREE ="
                        ),
                    ]
                )
                + ' IF ." EXT4-TYPED-FREE-AFTERIMAGES" THEN'
            ),
            "_FB-TX _EXT4-JTX-ABORT CONSTANT _FB-ABORT-IOR",
            (
                _forth_conjunction(
                    [
                        "_FB-ABORT-IOR 0=",
                        (
                            "_FB-WRITER _EXT4-JWR.STATE + @ "
                            "_EXT4-JWR-IDLE ="
                        ),
                        (
                            "_FB-WRITER _EXT4-JWR.FREE + @ "
                            "_FB-FREE-BEFORE ="
                        ),
                        "_FB-WRITER _EXT4-JWR.META-USED + @ 0=",
                        "_FB-WRITER _EXT4-JWR.META-IMAGES + @ C@ 0=",
                        "_FB-WRITER _EXT4-JWR.SCRATCH-A + @ C@ 0=",
                        "_FB-WRITER _EXT4-JWR.SCRATCH-B + @ C@ 0=",
                    ]
                )
                + ' IF ." EXT4-TYPED-FREE-ABORTED" THEN'
            ),
        ],
    )
    _assert_emitted(output, "EXT4-TYPED-FREE-AFTERIMAGES")
    _assert_emitted(output, "EXT4-TYPED-FREE-ABORTED")


@pytest.mark.parametrize(
    ("image_id", "valid_block", "free_block", "bitmap_home", "journal_home"),
    (
        ("primary-1k-i256", 1346, 1351, 259, 16385),
        ("primary-2k-i256", 1204, 1209, 129, 32768),
        ("primary-4k-i256", 2160, 2165, 65, 65536),
    ),
)
def test_typed_free_block_range_rejects_stale_or_protected_ranges_without_io(
    canonical_images: dict[str, Path],
    image_id: str,
    valid_block: int,
    free_block: int,
    bitmap_home: int,
    journal_home: int,
) -> None:
    path = canonical_images[image_id]
    with path.open("rb") as source:
        source.seek(1024)
        superblock = source.read(1024)
    assert len(superblock) == 1024
    block_count = struct.unpack_from("<I", superblock, 0x04)[0]
    assert struct.unpack_from("<I", superblock, 0x150)[0] == 0

    output = run_forth(
        path,
        [
            (
                "T-ARENA T-VOLUME EXT4-NEW "
                "CONSTANT _FR-MOUNT-IOR CONSTANT _FR-V"
            ),
            "_FR-V _EXT4-CTX CONSTANT _FR-CTX",
            (
                "3 0 0 _FR-CTX _EXT4-JWR-ENSURE "
                "CONSTANT _FR-WRITER-IOR CONSTANT _FR-WRITER"
            ),
            (
                "3 0 0 _FR-WRITER _EXT4-JTX-BEGIN "
                "CONSTANT _FR-TX-IOR CONSTANT _FR-TX"
            ),
            (
                f"{valid_block} 0 _FR-TX "
                "_EXT4-JTX-STAGE-FREE-BLOCK-RANGE CONSTANT _FR-ZERO-IOR"
            ),
            "_FR-WRITER _EXT4-JWR.META-USED + @ CONSTANT _FR-USED-ZERO",
            (
                f"{block_count} 1 _FR-TX "
                "_EXT4-JTX-STAGE-FREE-BLOCK-RANGE CONSTANT _FR-BOUND-IOR"
            ),
            "_FR-WRITER _EXT4-JWR.META-USED + @ CONSTANT _FR-USED-BOUND",
            (
                f"{block_count - 1} 2 _FR-TX "
                "_EXT4-JTX-STAGE-FREE-BLOCK-RANGE CONSTANT _FR-TAIL-IOR"
            ),
            "_FR-WRITER _EXT4-JWR.META-USED + @ CONSTANT _FR-USED-TAIL",
            (
                f"{free_block} 1 _FR-TX "
                "_EXT4-JTX-STAGE-FREE-BLOCK-RANGE CONSTANT _FR-FREE-IOR"
            ),
            "_FR-WRITER _EXT4-JWR.META-USED + @ CONSTANT _FR-USED-FREE",
            (
                f"{bitmap_home} 1 _FR-TX "
                "_EXT4-JTX-STAGE-FREE-BLOCK-RANGE CONSTANT _FR-STATIC-IOR"
            ),
            "_FR-WRITER _EXT4-JWR.META-USED + @ CONSTANT _FR-USED-STATIC",
            (
                f"{journal_home} 1 _FR-TX "
                "_EXT4-JTX-STAGE-FREE-BLOCK-RANGE CONSTANT _FR-JOURNAL-IOR"
            ),
            "_FR-WRITER _EXT4-JWR.META-USED + @ CONSTANT _FR-USED-JOURNAL",
            (
                f"{valid_block} 1 _FR-TX "
                "_EXT4-JTX-STAGE-FREE-BLOCK-RANGE CONSTANT _FR-VALID-IOR"
            ),
            (
                "0 _FR-WRITER _EXT4-JWR-META-ENTRY 2 CELLS + @ "
                "CONSTANT _FR-CRC0"
            ),
            (
                "1 _FR-WRITER _EXT4-JWR-META-ENTRY 2 CELLS + @ "
                "CONSTANT _FR-CRC1"
            ),
            (
                "2 _FR-WRITER _EXT4-JWR-META-ENTRY 2 CELLS + @ "
                "CONSTANT _FR-CRC2"
            ),
            (
                f"{valid_block} 2 _FR-TX "
                "_EXT4-JTX-STAGE-FREE-BLOCK-RANGE CONSTANT _FR-DUP-IOR"
            ),
            (
                _forth_conjunction(
                    [
                        "_FR-MOUNT-IOR 0=",
                        "_FR-WRITER-IOR 0=",
                        "_FR-TX-IOR 0=",
                        "_FR-ZERO-IOR VFS-E-INVALID =",
                        "_FR-BOUND-IOR VFS-IOR-REASON VFS-R-CORRUPT =",
                        "_FR-BOUND-IOR VFS-IOR-DETAIL EXT4-D-BOUNDS =",
                        "_FR-TAIL-IOR VFS-IOR-REASON VFS-R-CORRUPT =",
                        "_FR-TAIL-IOR VFS-IOR-DETAIL EXT4-D-BOUNDS =",
                        "_FR-FREE-IOR VFS-IOR-REASON VFS-R-CORRUPT =",
                        "_FR-FREE-IOR VFS-IOR-DETAIL EXT4-D-DATA-MAP =",
                        "_FR-STATIC-IOR VFS-IOR-REASON VFS-R-CORRUPT =",
                        "_FR-STATIC-IOR VFS-IOR-DETAIL EXT4-D-DATA-MAP =",
                        "_FR-JOURNAL-IOR VFS-IOR-REASON VFS-R-CORRUPT =",
                        "_FR-JOURNAL-IOR VFS-IOR-DETAIL EXT4-D-JOURNAL =",
                        "_FR-USED-ZERO 0=",
                        "_FR-USED-BOUND 0=",
                        "_FR-USED-TAIL 0=",
                        "_FR-USED-FREE 0=",
                        "_FR-USED-STATIC 0=",
                        "_FR-USED-JOURNAL 0=",
                        "_FR-VALID-IOR 0=",
                        "_FR-DUP-IOR VFS-E-CONFLICT =",
                        "_FR-WRITER _EXT4-JWR.META-USED + @ 3 =",
                        "_FR-WRITER _EXT4-JWR.META-ACTIVE + @ 3 =",
                        "_FR-WRITER _EXT4-JTX-TABLES-VALID?",
                        (
                            "0 _FR-WRITER _EXT4-JWR-META-ENTRY "
                            "2 CELLS + @ _FR-CRC0 ="
                        ),
                        (
                            "1 _FR-WRITER _EXT4-JWR-META-ENTRY "
                            "2 CELLS + @ _FR-CRC1 ="
                        ),
                        (
                            "2 _FR-WRITER _EXT4-JWR-META-ENTRY "
                            "2 CELLS + @ _FR-CRC2 ="
                        ),
                    ]
                )
                + ' IF ." EXT4-TYPED-FREE-REJECTIONS" THEN'
            ),
            "_FR-TX _EXT4-JTX-ABORT CONSTANT _FR-ABORT-IOR",
            (
                _forth_conjunction(
                    [
                        "_FR-ABORT-IOR 0=",
                        (
                            "_FR-WRITER _EXT4-JWR.STATE + @ "
                            "_EXT4-JWR-IDLE ="
                        ),
                        "_FR-WRITER _EXT4-JWR.META-USED + @ 0=",
                    ]
                )
                + ' IF ." EXT4-TYPED-FREE-REJECTION-ABORTED" THEN'
            ),
        ],
    )
    _assert_emitted(output, "EXT4-TYPED-FREE-REJECTIONS")
    _assert_emitted(output, "EXT4-TYPED-FREE-REJECTION-ABORTED")


def test_typed_free_block_range_crosses_group_boundary_atomically_without_io(
    canonical_images: dict[str, Path],
) -> None:
    path = canonical_images["primary-1k-i256"]
    with path.open("rb") as source:
        source.seek(1024)
        superblock = source.read(1024)
    assert len(superblock) == 1024
    block_size = 1024 << struct.unpack_from("<I", superblock, 0x18)[0]
    assert block_size == 1024
    first_data = struct.unpack_from("<I", superblock, 0x14)[0]
    blocks_per_group = struct.unpack_from("<I", superblock, 0x20)[0]
    seed = struct.unpack_from("<I", superblock, 0x270)[0]
    first_block = first_data + 4 * blocks_per_group - 1
    group_bits = ((3, blocks_per_group - 1), (4, 0))
    assert first_block == 32768

    def read_block(block: int) -> bytearray:
        with path.open("rb") as source:
            source.seek(block * block_size)
            result = bytearray(source.read(block_size))
        assert len(result) == block_size
        return result

    gdt_home = 2
    super_home = 1
    canonical_gdt = read_block(gdt_home)
    expected_gdt = bytearray(canonical_gdt)
    patched_gdt = bytearray(canonical_gdt)
    bitmap_homes: list[int] = []
    bitmap_patches: list[tuple[int, bytes]] = []
    canonical_bitmap_crcs: list[int] = []
    for group, bit_index in group_bits:
        descriptor_offset = group * 64
        descriptor = bytearray(
            canonical_gdt[descriptor_offset : descriptor_offset + 64]
        )
        bitmap_home = struct.unpack_from("<I", descriptor, 0x00)[0]
        assert struct.unpack_from("<I", descriptor, 0x20)[0] == 0
        bitmap_homes.append(bitmap_home)
        canonical_bitmap = read_block(bitmap_home)
        byte_index, bit_in_byte = divmod(bit_index, 8)
        assert canonical_bitmap[byte_index] & (1 << bit_in_byte) == 0
        canonical_bitmap_crcs.append(_crc32c_raw(canonical_bitmap))
        canonical_bitmap_checksum = _crc32c_raw(canonical_bitmap, seed)

        flags = struct.unpack_from("<H", descriptor, 0x12)[0]
        if flags & 0x02:
            assert group == 4
            flags &= ~0x02
            struct.pack_into("<H", descriptor, 0x12, flags)
        expected_descriptor = bytearray(descriptor)
        struct.pack_into(
            "<H", expected_descriptor, 0x18, canonical_bitmap_checksum & 0xFFFF
        )
        struct.pack_into(
            "<H", expected_descriptor, 0x38, canonical_bitmap_checksum >> 16
        )
        expected_descriptor = bytearray(
            _group_descriptor_with_checksum(
                superblock, expected_descriptor, group
            )
        )
        expected_gdt[
            descriptor_offset : descriptor_offset + 64
        ] = expected_descriptor

        patched_bitmap = bytearray(canonical_bitmap)
        patched_bitmap[byte_index] |= 1 << bit_in_byte
        patched_bitmap_checksum = _crc32c_raw(patched_bitmap, seed)
        bitmap_patches.append(
            (bitmap_home * block_size, bytes(patched_bitmap))
        )

        group_free = struct.unpack_from("<H", descriptor, 0x0C)[0] | (
            struct.unpack_from("<H", descriptor, 0x2C)[0] << 16
        )
        assert group_free > 0
        patched_group_free = group_free - 1
        struct.pack_into(
            "<H", descriptor, 0x0C, patched_group_free & 0xFFFF
        )
        struct.pack_into("<H", descriptor, 0x2C, patched_group_free >> 16)
        struct.pack_into(
            "<H", descriptor, 0x18, patched_bitmap_checksum & 0xFFFF
        )
        struct.pack_into(
            "<H", descriptor, 0x38, patched_bitmap_checksum >> 16
        )
        descriptor = bytearray(
            _group_descriptor_with_checksum(superblock, descriptor, group)
        )
        patched_gdt[
            descriptor_offset : descriptor_offset + 64
        ] = descriptor

    assert bitmap_homes == [262, 263]
    canonical_super = read_block(super_home)
    assert canonical_super == bytearray(superblock)
    patched_super = bytearray(canonical_super)
    super_free = struct.unpack_from("<I", patched_super, 0x0C)[0]
    assert struct.unpack_from("<I", patched_super, 0x158)[0] == 0
    assert super_free >= 2
    struct.pack_into("<I", patched_super, 0x0C, super_free - 2)
    patched_super = bytearray(_ext4_super_with_checksum(patched_super))

    patches = tuple(
        (
            *bitmap_patches,
            (gdt_home * block_size, bytes(patched_gdt)),
            (super_home * block_size, bytes(patched_super)),
        )
    )
    expected_gdt_crc = _crc32c_raw(expected_gdt)
    canonical_super_crc = _crc32c_raw(canonical_super)

    output = run_forth(
        path,
        [
            (
                "T-ARENA T-VOLUME EXT4-NEW "
                "CONSTANT _FC-MOUNT-IOR CONSTANT _FC-V"
            ),
            "_FC-V _EXT4-CTX CONSTANT _FC-CTX",
            (
                "_FC-CTX _EXT4-C.FREE-BLOCKS + @ "
                "CONSTANT _FC-CONTEXT-FREE"
            ),
            (
                "_FC-CTX _EXT4-C.SB + _EXT4-SB.FREE-BLOCKS-LO + L@ "
                "CONSTANT _FC-CACHED-SUPER-FREE"
            ),
            (
                "4 0 0 _FC-CTX _EXT4-JWR-ENSURE "
                "CONSTANT _FC-WRITER-IOR CONSTANT _FC-WRITER"
            ),
            (
                "4 0 0 _FC-WRITER _EXT4-JTX-BEGIN "
                "CONSTANT _FC-TX-IOR CONSTANT _FC-TX"
            ),
            (
                f"{first_block} 2 _FC-TX "
                "_EXT4-JTX-STAGE-FREE-BLOCK-RANGE CONSTANT _FC-STAGE-IOR"
            ),
            "0 _FC-WRITER _EXT4-JWR-META-IMAGE CONSTANT _FC-GDT-IMAGE",
            "1 _FC-WRITER _EXT4-JWR-META-IMAGE CONSTANT _FC-BITMAP3-IMAGE",
            "2 _FC-WRITER _EXT4-JWR-META-IMAGE CONSTANT _FC-BITMAP4-IMAGE",
            "3 _FC-WRITER _EXT4-JWR-META-IMAGE CONSTANT _FC-SUPER-IMAGE",
            (
                _forth_conjunction(
                    [
                        "_FC-MOUNT-IOR 0=",
                        "_FC-WRITER-IOR 0=",
                        "_FC-TX-IOR 0=",
                        "_FC-STAGE-IOR 0=",
                        "_FC-WRITER _EXT4-JWR.META-USED + @ 4 =",
                        "_FC-WRITER _EXT4-JWR.META-ACTIVE + @ 4 =",
                        "_FC-WRITER _EXT4-JTX-TABLES-VALID?",
                        (
                            "0 _FC-WRITER _EXT4-JWR-META-ENTRY @ "
                            f"{gdt_home} ="
                        ),
                        (
                            "1 _FC-WRITER _EXT4-JWR-META-ENTRY @ "
                            f"{bitmap_homes[0]} ="
                        ),
                        (
                            "2 _FC-WRITER _EXT4-JWR-META-ENTRY @ "
                            f"{bitmap_homes[1]} ="
                        ),
                        (
                            "3 _FC-WRITER _EXT4-JWR-META-ENTRY @ "
                            f"{super_home} ="
                        ),
                        (
                            "_FC-GDT-IMAGE _FC-WRITER "
                            f"_EXT4-JTX-IMAGE-CRC {expected_gdt_crc} ="
                        ),
                        (
                            "_FC-BITMAP3-IMAGE _FC-WRITER "
                            "_EXT4-JTX-IMAGE-CRC "
                            f"{canonical_bitmap_crcs[0]} ="
                        ),
                        (
                            "_FC-BITMAP4-IMAGE _FC-WRITER "
                            "_EXT4-JTX-IMAGE-CRC "
                            f"{canonical_bitmap_crcs[1]} ="
                        ),
                        (
                            "_FC-SUPER-IMAGE _FC-WRITER "
                            f"_EXT4-JTX-IMAGE-CRC {canonical_super_crc} ="
                        ),
                        (
                            "_FC-CTX _EXT4-C.FREE-BLOCKS + @ "
                            "_FC-CONTEXT-FREE ="
                        ),
                        (
                            "_FC-CTX _EXT4-C.SB + "
                            "_EXT4-SB.FREE-BLOCKS-LO + L@ "
                            "_FC-CACHED-SUPER-FREE ="
                        ),
                    ]
                )
                + ' IF ." EXT4-TYPED-FREE-CROSS-GROUP" THEN'
            ),
            "_FC-TX _EXT4-JTX-ABORT CONSTANT _FC-ABORT-IOR",
            (
                _forth_conjunction(
                    [
                        "_FC-ABORT-IOR 0=",
                        (
                            "_FC-WRITER _EXT4-JWR.STATE + @ "
                            "_EXT4-JWR-IDLE ="
                        ),
                        "_FC-WRITER _EXT4-JWR.META-USED + @ 0=",
                        "_FC-WRITER _EXT4-JWR.META-IMAGES + @ C@ 0=",
                        "_FC-WRITER _EXT4-JWR.SCRATCH-A + @ C@ 0=",
                        "_FC-WRITER _EXT4-JWR.SCRATCH-B + @ C@ 0=",
                    ]
                )
                + ' IF ." EXT4-TYPED-FREE-CROSS-GROUP-ABORTED" THEN'
            ),
        ],
        patches=patches,
    )
    _assert_emitted(output, "EXT4-TYPED-FREE-CROSS-GROUP")
    _assert_emitted(output, "EXT4-TYPED-FREE-CROSS-GROUP-ABORTED")


def test_typed_free_block_range_auto_aborts_a_partial_credit_failure(
    canonical_images: dict[str, Path],
) -> None:
    path = canonical_images["primary-1k-i256"]
    output = run_forth(
        path,
        [
            (
                "T-ARENA T-VOLUME EXT4-NEW "
                "CONSTANT _FA-MOUNT-IOR CONSTANT _FA-V"
            ),
            "_FA-V _EXT4-CTX CONSTANT _FA-CTX",
            (
                "3 0 0 _FA-CTX _EXT4-JWR-ENSURE "
                "CONSTANT _FA-WRITER-IOR CONSTANT _FA-WRITER"
            ),
            "_FA-WRITER _EXT4-JWR.FREE + @ CONSTANT _FA-FREE-BEFORE",
            (
                "2 0 0 _FA-WRITER _EXT4-JTX-BEGIN "
                "CONSTANT _FA-TX-IOR CONSTANT _FA-TX"
            ),
            (
                "1346 1 _FA-TX _EXT4-JTX-STAGE-FREE-BLOCK-RANGE "
                "CONSTANT _FA-STAGE-IOR"
            ),
            "_FA-TX _EXT4-JTX-EMIT CONSTANT _FA-EMIT-IOR",
            (
                _forth_conjunction(
                    [
                        "_FA-MOUNT-IOR 0=",
                        "_FA-WRITER-IOR 0=",
                        "_FA-TX-IOR 0=",
                        "_FA-STAGE-IOR VFS-E-NOSPC =",
                        "_FA-EMIT-IOR VFS-E-BUSY =",
                        (
                            "_FA-WRITER _EXT4-JWR.STATE + @ "
                            "_EXT4-JWR-IDLE ="
                        ),
                        "_FA-WRITER _EXT4-JWR.FAULT + @ 0=",
                        (
                            "_FA-WRITER _EXT4-JWR.FREE + @ "
                            "_FA-FREE-BEFORE ="
                        ),
                        "_FA-WRITER _EXT4-JWR.META-USED + @ 0=",
                        "_FA-WRITER _EXT4-JWR.META-ACTIVE + @ 0=",
                        "_FA-WRITER _EXT4-JWR.META-IMAGES + @ C@ 0=",
                        "_FA-WRITER _EXT4-JWR.SCRATCH-A + @ C@ 0=",
                        "_FA-WRITER _EXT4-JWR.SCRATCH-B + @ C@ 0=",
                    ]
                )
                + ' IF ." EXT4-TYPED-FREE-AUTO-ABORT" THEN'
            ),
            (
                "3 0 0 _FA-WRITER _EXT4-JTX-BEGIN "
                "CONSTANT _FA-RETRY-IOR CONSTANT _FA-RETRY"
            ),
            (
                "1346 1 _FA-RETRY _EXT4-JTX-STAGE-FREE-BLOCK-RANGE "
                "CONSTANT _FA-RETRY-STAGE-IOR"
            ),
            "_FA-RETRY _EXT4-JTX-ABORT CONSTANT _FA-RETRY-ABORT-IOR",
            (
                _forth_conjunction(
                    [
                        "_FA-RETRY-IOR 0=",
                        "_FA-RETRY-STAGE-IOR 0=",
                        "_FA-RETRY-ABORT-IOR 0=",
                        (
                            "_FA-WRITER _EXT4-JWR.STATE + @ "
                            "_EXT4-JWR-IDLE ="
                        ),
                        "_FA-WRITER _EXT4-JWR.META-USED + @ 0=",
                    ]
                )
                + ' IF ." EXT4-TYPED-FREE-AUTO-ABORT-REUSABLE" THEN'
            ),
        ],
    )
    _assert_emitted(output, "EXT4-TYPED-FREE-AUTO-ABORT")
    _assert_emitted(output, "EXT4-TYPED-FREE-AUTO-ABORT-REUSABLE")


def test_typed_free_block_range_rejects_an_aliased_bitmap_home(
    canonical_images: dict[str, Path],
) -> None:
    path = canonical_images["primary-1k-i256"]
    with path.open("rb") as source:
        source.seek(1024)
        superblock = source.read(1024)
    assert len(superblock) == 1024
    block_size = 1024 << struct.unpack_from("<I", superblock, 0x18)[0]
    assert block_size == 1024
    block_count = struct.unpack_from("<I", superblock, 0x04)[0]
    first_data = struct.unpack_from("<I", superblock, 0x14)[0]
    blocks_per_group = struct.unpack_from("<I", superblock, 0x20)[0]
    seed = struct.unpack_from("<I", superblock, 0x270)[0]
    groups = (
        block_count - first_data + blocks_per_group - 1
    ) // blocks_per_group
    alias_owner = 3
    alias_home = 259
    original_home = 262
    descriptor_offset = alias_owner * 64

    def read_block(block: int) -> bytearray:
        with path.open("rb") as source:
            source.seek(block * block_size)
            result = bytearray(source.read(block_size))
        assert len(result) == block_size
        return result

    alias_bitmap = read_block(alias_home)
    alias_checksum = _crc32c_raw(alias_bitmap, seed)
    gdt_bases = [2]
    gdt_bases.extend(
        first_data + group * blocks_per_group + 1
        for group in range(1, groups)
        if _ext4_sparse_group(group)
    )
    patches: list[tuple[int, bytes]] = []
    for gdt_base in gdt_bases:
        gdt = read_block(gdt_base)
        descriptor = bytearray(
            gdt[descriptor_offset : descriptor_offset + 64]
        )
        assert struct.unpack_from("<I", descriptor, 0x00)[0] == original_home
        assert struct.unpack_from("<I", descriptor, 0x20)[0] == 0
        struct.pack_into("<I", descriptor, 0x00, alias_home)
        struct.pack_into("<H", descriptor, 0x18, alias_checksum & 0xFFFF)
        struct.pack_into("<H", descriptor, 0x38, alias_checksum >> 16)
        descriptor = bytearray(
            _group_descriptor_with_checksum(
                superblock, descriptor, alias_owner
            )
        )
        gdt[descriptor_offset : descriptor_offset + 64] = descriptor
        patches.append((gdt_base * block_size, bytes(gdt)))

    output = run_forth(
        path,
        [
            (
                "T-ARENA T-VOLUME EXT4-NEW "
                "CONSTANT _FAL-MOUNT-IOR CONSTANT _FAL-V"
            ),
            "_FAL-V _EXT4-CTX CONSTANT _FAL-CTX",
            (
                "3 0 0 _FAL-CTX _EXT4-JWR-ENSURE "
                "CONSTANT _FAL-WRITER-IOR CONSTANT _FAL-WRITER"
            ),
            (
                "3 0 0 _FAL-WRITER _EXT4-JTX-BEGIN "
                "CONSTANT _FAL-TX-IOR CONSTANT _FAL-TX"
            ),
            (
                "1346 1 _FAL-TX _EXT4-JTX-STAGE-FREE-BLOCK-RANGE "
                "CONSTANT _FAL-STAGE-IOR"
            ),
            (
                _forth_conjunction(
                    [
                        "_FAL-MOUNT-IOR 0=",
                        "_FAL-WRITER-IOR 0=",
                        "_FAL-TX-IOR 0=",
                        (
                            "_FAL-STAGE-IOR VFS-IOR-REASON "
                            "VFS-R-CORRUPT ="
                        ),
                        (
                            "_FAL-STAGE-IOR VFS-IOR-DETAIL "
                            "EXT4-D-DATA-MAP ="
                        ),
                        (
                            "_FAL-WRITER _EXT4-JWR.STATE + @ "
                            "_EXT4-JWR-STAGING ="
                        ),
                        "_FAL-WRITER _EXT4-JWR.META-USED + @ 0=",
                        "_FAL-WRITER _EXT4-JWR.META-ACTIVE + @ 0=",
                        "_FAL-WRITER _EXT4-JTX-TABLES-VALID?",
                    ]
                )
                + ' IF ." EXT4-TYPED-FREE-ALIAS-REJECTED" THEN'
            ),
            "_FAL-TX _EXT4-JTX-ABORT CONSTANT _FAL-ABORT-IOR",
            (
                _forth_conjunction(
                    [
                        "_FAL-ABORT-IOR 0=",
                        (
                            "_FAL-WRITER _EXT4-JWR.STATE + @ "
                            "_EXT4-JWR-IDLE ="
                        ),
                    ]
                )
                + ' IF ." EXT4-TYPED-FREE-ALIAS-ABORTED" THEN'
            ),
        ],
        patches=tuple(patches),
    )
    _assert_emitted(output, "EXT4-TYPED-FREE-ALIAS-REJECTED")
    _assert_emitted(output, "EXT4-TYPED-FREE-ALIAS-ABORTED")


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
