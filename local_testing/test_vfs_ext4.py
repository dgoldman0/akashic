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
