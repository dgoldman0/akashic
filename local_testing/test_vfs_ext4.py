#!/usr/bin/env python3
"""Real-image tests for the read-only ext4 ABI-1 VFS binding."""

from __future__ import annotations

import hashlib
import json
import mmap
import os
import struct
import sys
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[1]
LOCAL_TESTING = Path(__file__).resolve().parent
if str(LOCAL_TESTING) not in sys.path:
    sys.path.insert(0, str(LOCAL_TESTING))

import test_vfs_fat as fat_harness  # noqa: E402


EXT4_F = ROOT / "akashic" / "utils" / "fs" / "drivers" / "vfs-ext4.f"
MANIFEST = ROOT / "local_testing" / "fixtures" / "ext4-profile" / "manifest.json"
IMAGE_DIR = ROOT / "local_testing" / "out" / "ext4-profile"

with MANIFEST.open("r", encoding="utf-8") as source:
    PROFILE = json.load(source)

IMAGE_ROWS = {row["id"]: row for row in PROFILE["images"]}
IMAGE_IDS = tuple(IMAGE_ROWS)

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
        ext_mem_size=16 * (1 << 20),
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
        ext_mem_size=16 * (1 << 20),
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
        run_write = system.storage._run_write
        run_flush = system.storage._run_flush

        def track_write(request):
            nonlocal write_requests
            write_requests += 1
            return run_write(request)

        def track_flush(request):
            nonlocal flush_requests
            flush_requests += 1
            return run_flush(request)

        system.storage._run_write = track_write
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


def _assert_emitted(output: str, marker: str) -> None:
    """Require executed output, not the marker text echoed in Forth source."""
    assert f"\r\n{marker} ok\r\n" in output, output[-4000:]


@pytest.fixture(scope="session")
def canonical_images() -> dict[str, Path]:
    paths: dict[str, Path] = {}
    missing = []
    for image_id, row in IMAGE_ROWS.items():
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
        ],
    )
    _assert_emitted(output, "EXT4-PARSER-TOTAL-OK")
    _assert_emitted(output, "EXT4-HUGE-BLOCKS-OK")
    _assert_emitted(output, "EXT4-TIMESTAMP-SIGN-OK")


def test_indexed_directory_flag_is_an_explicit_unsupported_structure(
    canonical_images: dict[str, Path],
) -> None:
    path = canonical_images["primary-1k-i256"]
    output = run_forth(
        path,
        [
            "T-ARENA T-VOLUME EXT4-NEW CONSTANT _M-IOR CONSTANT _V",
            "2 _V _EXT4-CTX _EXT4-LOAD-INODE CONSTANT _L-IOR",
            (
                "_V _EXT4-CTX _EXT4-C.INODE + _EXT4-I.FLAGS + "
                "DUP @ _EXT4-INDEX-FL OR SWAP !"
            ),
            (
                "_V _EXT4-CTX _EXT4-STAGE-CURRENT-INODE "
                "CONSTANT _S-IOR CONSTANT _TYPE"
            ),
            (
                "_M-IOR 0= _L-IOR 0= AND _TYPE 0= AND "
                "_S-IOR VFS-IOR-REASON VFS-R-UNSUPPORTED = AND "
                "_S-IOR VFS-IOR-DETAIL EXT4-D-FEATURE = AND "
                'IF ." EXT4-HTREE-REFUSAL-OK" THEN'
            ),
        ],
    )
    _assert_emitted(output, "EXT4-HTREE-REFUSAL-OK")


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
        'S" /fixture/fast-link" _V VFS-RESOLVE? DROP CONSTANT _FL',
        "_E4BUF 128 _FL _V VFS-READLINK CONSTANT _FL-IOR CONSTANT _FLN",
        'S" /fixture/slow-link" _V VFS-RESOLVE? DROP CONSTANT _SL',
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


@pytest.mark.parametrize(
    ("field_offset", "mask"),
    ((0x60, 0x22C6), (0x64, 0x1046B)),
)
def test_recovery_required_states_are_distinct_refusals(
    canonical_images: dict[str, Path], field_offset: int, mask: int
) -> None:
    path = canonical_images["primary-1k-i256"]
    patched = _super_with_mask(path, field_offset, mask)
    output = run_forth(
        path,
        [
            "T-ARENA T-VOLUME EXT4-NEW CONSTANT _IOR CONSTANT _V",
            "_IOR VFS-IOR-REASON . _IOR VFS-IOR-DETAIL . _V V.LIFECYCLE @ .",
        ],
        patches=((1024, patched),),
    )
    assert "11 5 0" in output, output[-1500:]


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
    (0x1487F8, 0x04, 13),
    (0x1487FC, 0xA9, 13),
)


def _one_byte_xor(path: Path, offset: int, expected: int) -> tuple[int, bytes]:
    with path.open("rb") as source:
        source.seek(offset)
        actual = source.read(1)
    assert actual == bytes((expected,))
    return offset, bytes((expected ^ 1,))


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
