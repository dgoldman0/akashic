#!/usr/bin/env python3
"""The ext4 writer on volumes as a user volume is built and used.

The fixture images of test_vfs_ext4.py carry a fixed population.  These
cases build their volumes with the profile's own mke2fs options and
populate them, or leave them empty, as a user's volume would be, then run
the driver on them through the helpers of test_vfs_ext4.py.
"""

from __future__ import annotations

import collections
import gc
import random
import re
import struct
import subprocess
from pathlib import Path

import pytest

import test_vfs_ext4 as ext4
import test_vfs_replace_ext4 as rx
from test_vfs_ext4 import (  # noqa: F401  (session fixtures)
    canonical_images,
    jbd2_toolchain,
)
from test_vfs_replace_ext4 import document_volume  # noqa: F401

_ROW = ext4.IMAGE_ROWS["primary-1k-i256"]
_BLOCK = 1024
_INODE = 256
_INODES_PER_GROUP = 512
_EPOCH_MS = ext4._STAGED_APPEND_EPOCH_MS
_BG_INODE_UNINIT = 0x1
_BG_BLOCK_UNINIT = 0x2
_BG_INODE_ZEROED = 0x4


@pytest.fixture(autouse=True)
def _free_machines_between_cases():
    """Collect each case's machines and media before the next case runs.

    A run's machine and its media sit in reference cycles, and the
    collector counts objects, not bytes, so a few dozen runs can hold
    several gibibytes before it looks.  The power-cut cases collect after
    every cut for the same reason.
    """
    yield
    gc.collect()


# ---------------------------------------------------------------------
#  Host side: volumes and oracles
# ---------------------------------------------------------------------


def _run(argv, env, *, text: bool = True) -> subprocess.CompletedProcess:
    return subprocess.run(
        [str(part) for part in argv],
        env=env,
        text=text,
        capture_output=True,
        check=False,
    )


def _make_volume(
    path: Path,
    toolchain: dict[str, object],
    *,
    mebibytes: int = 64,
    lazy_inode_tables: bool = False,
    commands: tuple[str, ...] = (),
) -> Path:
    """Build a volume with the profile's mke2fs options, then run debugfs.

    LAZY_INODE_TABLES leaves the inode tables as the medium holds them and
    the groups without ITABLE_ZEROED, as mke2fs does by default on Linux.
    """
    tool_dir = toolchain["tool_dir"]
    env = toolchain["env"]
    assert isinstance(tool_dir, Path)
    blocks = mebibytes * 1024
    groups = (blocks - 1 + _ROW["blocks_per_group"] - 1) // _ROW[
        "blocks_per_group"
    ]
    spec = dict(_ROW)
    spec.update(
        filename=path.name,
        image_bytes=blocks * _BLOCK,
        block_count=blocks,
        expected_groups=groups,
        expected_inodes=groups * _INODES_PER_GROUP,
    )
    with path.open("wb") as image:
        image.truncate(spec["image_bytes"])
    context = dict(spec)
    context.update(
        tool_dir=tool_dir,
        image=path,
        feature_names=",".join(
            ext4.ext4_fixture_generator.profile_feature_names(
                ext4.PROFILE, spec
            )
        ),
    )
    argv = ext4.ext4_fixture_generator.render_argv(
        ext4.PROFILE["generator"]["mkfs_argv"], context
    )
    if lazy_inode_tables:
        assert sum("lazy_itable_init=0" in part for part in argv) == 1
        argv = [
            part.replace("lazy_itable_init=0", "lazy_itable_init=1")
            for part in argv
        ]
    made = _run(argv, env)
    assert made.returncode == 0, made.stdout + made.stderr
    ext4.ext4_fixture_generator.validate_observed_superblock(
        ext4.PROFILE,
        spec,
        ext4.ext4_fixture_generator.read_superblock(path),
    )
    if commands:
        script = path.with_suffix(".debugfs")
        script.write_text("\n".join(commands) + "\n", encoding="utf-8")
        authored = _run(
            [toolchain["debugfs"], "-w", "-f", script, path], env
        )
        script.unlink()
        assert authored.returncode == 0, authored.stdout + authored.stderr
        for refusal in ("Command not found", "Could not allocate", "No free"):
            assert refusal not in authored.stdout + authored.stderr
    ext4._assert_e2fsck_clean(path, toolchain)
    return path


def _debugfs(
    image: Path, command: str, toolchain: dict[str, object], *, text=True
):
    ran = _run(
        [toolchain["debugfs"], "-R", command, image],
        toolchain["env"],
        text=text,
    )
    assert ran.returncode == 0, ran.stderr
    return ran.stdout


def _names(image: Path, directory: str, toolchain) -> dict[str, int]:
    """Return the live names of DIRECTORY with their inode numbers."""
    listing = _debugfs(image, f"ls -l {directory}", toolchain)
    result: dict[str, int] = {}
    for line in listing.splitlines():
        fields = line.split()
        if len(fields) >= 9 and fields[0].isdigit():
            result[fields[-1]] = int(fields[0])
    return result


def _groups(image: Path, toolchain) -> dict[int, dict[str, object]]:
    """Return each group's flags and counts as the pinned dumpe2fs prints them."""
    tool_dir = toolchain["tool_dir"]
    assert isinstance(tool_dir, Path)
    ran = _run([tool_dir / "dumpe2fs", image], toolchain["env"])
    assert ran.returncode == 0, ran.stderr
    result: dict[int, dict[str, object]] = {}
    current: dict[str, object] | None = None
    for line in ran.stdout.splitlines():
        head = re.match(r"^Group (\d+): \(Blocks \d+-\d+\) csum 0x\w+(.*)$", line)
        if head:
            flags = re.search(r"\[(.*)\]", head.group(2))
            current = {
                "flags": (
                    frozenset(flags.group(1).split(", ")) if flags else frozenset()
                )
            }
            result[int(head.group(1))] = current
            continue
        if current is None:
            continue
        # dumpe2fs leaves out a group's unused count when it is zero.
        counts = re.search(
            r"(\d+) free blocks, (\d+) free inodes, (\d+) directories"
            r"(?:, (\d+) unused inodes)?",
            line,
        )
        if counts:
            current.update(
                free_blocks=int(counts.group(1)),
                free_inodes=int(counts.group(2)),
                directories=int(counts.group(3)),
                unused_inodes=int(counts.group(4) or 0),
            )
        bitmap = re.search(r"Inode bitmap at (\d+) .*csum 0x(\w+)", line)
        if bitmap:
            current.update(
                inode_bitmap=int(bitmap.group(1)),
                inode_bitmap_csum=int(bitmap.group(2), 16),
            )
        table = re.search(r"Inode table at (\d+)-(\d+)", line)
        if table:
            current.update(inode_table=int(table.group(1)))
    return result


def _descriptor(image: Path, group: int) -> bytes:
    with image.open("rb") as source:
        source.seek(2 * _BLOCK + group * 64)
        descriptor = source.read(64)
    assert len(descriptor) == 64
    return descriptor


def _superblock(image: Path) -> bytes:
    with image.open("rb") as source:
        source.seek(1024)
        return source.read(1024)


def _inode_bitmap_csum(image: Path, bitmap: bytes) -> int:
    seed = struct.unpack_from("<I", _superblock(image), 0x270)[0]
    return ext4._crc32c_raw(bitmap[: _INODES_PER_GROUP // 8], seed)


def _inode_record(image: Path, inode_number: int) -> bytes:
    return ext4._ext4_inode_record(image, inode_number)[1]


# ---------------------------------------------------------------------
#  Guest side
# ---------------------------------------------------------------------


def _mount(prefix: str, *, profile=(16, 16, 2), arena: int = 1 << 20):
    """Mount the staged binding with a clock and a writer profile bound."""
    return [
        (
            f": {prefix}-NOW ( context -- epoch-ms ior ) "
            f"DROP {_EPOCH_MS} 0 ;"
        ),
        f"{arena} A-XMEM ARENA-NEW THROW CONSTANT {prefix}-ARENA",
        (
            f"{prefix}-ARENA T-VOLUME EXT4-STAGED-WRITE-NEW "
            f"CONSTANT {prefix}-MOUNT-IOR CONSTANT {prefix}-V"
        ),
        f"{prefix}-V _EXT4-CTX CONSTANT {prefix}-CTX",
        (
            f"' {prefix}-NOW 0 {prefix}-V EXT4-BIND-WRITE-CLOCK? "
            f"CONSTANT {prefix}-CLOCK-IOR"
        ),
        *ext4._ext4_dedicated_writer_profile_forth(
            f"{prefix}-PROFILE", f"{prefix}-V", *profile
        ),
        f"CREATE {prefix}-STAT VFS-STATFS-SIZE ALLOT",
        (
            f": {prefix}-FFREE ( -- free-inodes ) {prefix}-STAT "
            f"VFS-STATFS-SIZE {prefix}-V VFS-STATFS THROW "
            f"{prefix}-STAT VSF.FFREE @ ;"
        ),
    ]


_MOUNTED = (
    "{p}-MOUNT-IOR 0=",
    "{p}-CLOCK-IOR 0=",
    "{p}-PROFILE-SIZE-IOR 0=",
    "{p}-PROFILE-BIND-IOR 0=",
)


def _mounted(prefix: str) -> list[str]:
    return [check.format(p=prefix) for check in _MOUNTED]


def _checked(name: str, marker: str, checks: list[str]) -> list[str]:
    """Emit MARKER when every check holds, or the first failing index."""
    return [
        *ext4._forth_accumulated_conjunction(name, checks),
        (
            f': {name}-REPORT {name} @ IF ." {marker}" ELSE '
            f'." {marker}-REFUSED-AT " {name}-FIRST-FAILURE @ . THEN ;'
        ),
        f"{name}-REPORT",
    ]


def _unmount(prefix: str, marker: str) -> list[str]:
    return [
        f"0 {prefix}-V VFS-UNMOUNT CONSTANT {prefix}-UNMOUNT-IOR",
        (
            f"{prefix}-UNMOUNT-IOR 0= "
            f"{prefix}-V V.LIFECYCLE @ VFS-L-UNMOUNTED = AND "
            f'IF ." {marker}" THEN'
        ),
    ]


def _emitted(output: str, marker: str) -> None:
    refused = re.search(rf"{re.escape(marker)}-REFUSED-AT (-?\d+)", output)
    assert refused is None, (
        f"{marker}: check {refused.group(1)} is the first that fails\n"
        + output[-3000:]
    )
    ext4._assert_emitted(output, marker)


def _numbers(output: str, tag: str) -> list[int]:
    """Return the numbers a guest line printed as `[TAG n n ...]`."""
    found = re.findall(rf"\r\n\[{re.escape(tag)} ((?:-?\d+ )+)\]", output)
    assert len(found) == 1, (tag, output[-2000:])
    return [int(number) for number in found[0].split()]


# ---------------------------------------------------------------------
#  A volume as mke2fs leaves it
# ---------------------------------------------------------------------


@pytest.fixture(scope="session")
def fresh_volumes(
    jbd2_toolchain: dict[str, object],  # noqa: F811
    tmp_path_factory: pytest.TempPathFactory,
) -> dict[str, Path]:
    """Three 64 MiB volumes: empty, one host file, one host folder.

    None holds an inode with an external xattr block, which the test
    fixture's population has and a new user volume does not.
    """
    directory = tmp_path_factory.mktemp("ext4-fresh-volumes")
    document = directory / "doc.bin"
    document.write_bytes((b"old document line\n" * 200)[:2048])
    volumes = {
        "empty": _make_volume(directory / "empty.img", jbd2_toolchain),
        "file": _make_volume(
            directory / "file.img",
            jbd2_toolchain,
            commands=(f"write {document} /doc.txt",),
        ),
        "folder": _make_volume(
            directory / "folder.img",
            jbd2_toolchain,
            commands=("mkdir /dir",),
        ),
    }
    assert _names(volumes["empty"], "/", jbd2_toolchain).keys() == {
        ".",
        "..",
        "lost+found",
    }
    assert _names(volumes["file"], "/", jbd2_toolchain)["doc.txt"] == 13
    assert _names(volumes["folder"], "/", jbd2_toolchain)["dir"] == 13
    for image in volumes.values():
        groups = _groups(image, jbd2_toolchain)
        assert "INODE_UNINIT" not in groups[0]["flags"]
        assert all(
            "INODE_UNINIT" in groups[group]["flags"] for group in range(1, 8)
        )
    return volumes


def test_sort_cells_orders_any_count(fresh_volumes: dict[str, Path]) -> None:
    """The ownership proof's cell sort takes any count, none included.

    A volume without an external xattr block gives the proof no reference
    to sort.  The sort's first pass then started past its limit and never
    met it, which stopped the machine on every fresh volume.
    """
    rng = random.Random(20261115)
    guard = 0x5A5A5A5A5A5A5A5A
    lines = [
        "CREATE _SC-BUF 66 CELLS ALLOT",
        (
            ': _SC-SHOW ( n -- ) ." [SORTED " 1+ 0 ?DO '
            '_SC-BUF I CELLS + @ U. LOOP ." ]" ;'
        ),
    ]
    expected: list[list[int]] = []
    for count in (0, 1, 2, 3, 4, 5, 13, 14, 40, 64):
        values = [rng.randrange(1 << 64) for _ in range(count)]
        if count >= 4:
            # Repeated cells and both ends of the unsigned range.
            values[1] = values[0]
            values[2] = 0
            values[3] = (1 << 64) - 1
        for index, value in enumerate([*values, guard]):
            lines.append(f"0x{value:X} _SC-BUF {index} CELLS + !")
        lines.append(f"_SC-BUF {count} _EXT4-SORT-CELLS {count} _SC-SHOW")
        expected.append([*sorted(values), guard])
    output = ext4.run_forth(
        fresh_volumes["empty"], lines, max_steps=60_000_000
    )
    shown = re.findall(r"\r\n\[SORTED ((?:\d+ )+)\]", output)
    assert [[int(cell) for cell in row.split()] for row in shown] == expected


_FRESH_FIRST_WRITES = {
    # The first write of the mount is a create in the root.
    "empty": (
        'S" first.txt" _FV-V VFS-MKFILE? '
        "CONSTANT _FV-FIRST-IOR CONSTANT _FV-FIRST-D",
        "_FV-FIRST-D 0<> CONSTANT _FV-FIRST-OK",
    ),
    # The first write of the mount overwrites the host's file.
    "file": (
        'S" /doc.txt" VFS-FF-READ VFS-FF-WRITE OR _FV-V VFS-OPEN? '
        "CONSTANT _FV-OPEN-IOR CONSTANT _FV-FD",
        "_FV-BUF 100 _FV-FD VFS-WRITE? "
        "CONSTANT _FV-FIRST-IOR CONSTANT _FV-ACTUAL",
        "_FV-FD VFS-CLOSE? CONSTANT _FV-CLOSE-IOR",
        "_FV-OPEN-IOR 0= _FV-ACTUAL 100 = AND _FV-CLOSE-IOR 0= AND "
        "CONSTANT _FV-FIRST-OK",
    ),
    # The proof is called before any write, then a create in the folder.
    "folder": (
        "_FV-CTX _EXT4-PROVE-OWNERSHIP CONSTANT _FV-PROOF-IOR",
        'S" /dir" _FV-V VFS-CD? CONSTANT _FV-CD-IOR',
        'S" inner.txt" _FV-V VFS-MKFILE? '
        "CONSTANT _FV-FIRST-IOR CONSTANT _FV-FIRST-D",
        'S" /" _FV-V VFS-CD? CONSTANT _FV-BACK-IOR',
        "_FV-PROOF-IOR 0= _FV-CD-IOR 0= AND _FV-FIRST-D 0<> AND "
        "_FV-BACK-IOR 0= AND CONSTANT _FV-FIRST-OK",
    ),
}


@pytest.mark.parametrize("population", ("empty", "file", "folder"))
def test_fresh_volume_takes_its_first_writes(
    fresh_volumes: dict[str, Path],
    jbd2_toolchain: dict[str, object],  # noqa: F811
    tmp_path: Path,
    population: str,
) -> None:
    """A volume from mke2fs proves its ownership and takes writes.

    Each population starts its mount's writes in the way that stopped the
    machine: a create, an overwrite, and a direct call of the proof.
    """
    backing = tmp_path / f"fresh-{population}.img"
    output, trace, _ = ext4.run_recovery_forth(
        fresh_volumes[population],
        backing,
        [
            "CREATE _FV-BUF 512 ALLOT _FV-BUF 512 90 FILL",
            *_mount("_FV"),
            "_FV-CTX _EXT4-C.OWNERSHIP + @ CONSTANT _FV-PROVED-BEFORE",
            *_FRESH_FIRST_WRITES[population],
            "_FV-CTX _EXT4-C.OWNERSHIP + @ CONSTANT _FV-PROVED-AFTER",
            'S" made" _FV-V VFS-MKDIR CONSTANT _FV-MKDIR-IOR',
            "_FV-V VFS-SYNC CONSTANT _FV-SYNC-IOR",
            (
                'S" second.txt" _FV-V VFS-MKFILE? '
                "CONSTANT _FV-SECOND-IOR CONSTANT _FV-SECOND-D"
            ),
            (
                'S" /second.txt" VFS-FF-READ VFS-FF-WRITE OR _FV-V '
                "VFS-OPEN? CONSTANT _FV-OPEN2-IOR CONSTANT _FV-FD2"
            ),
            "_FV-BUF 300 _FV-FD2 VFS-WRITE-EXACT CONSTANT _FV-WRITE2-IOR",
            "_FV-FD2 VFS-CLOSE? CONSTANT _FV-CLOSE2-IOR",
            "_FV-V VFS-SYNC CONSTANT _FV-SYNC2-IOR",
            *_checked(
                "_FV-OK",
                "EXT4-FRESH-VOLUME-WRITES",
                [
                    *_mounted("_FV"),
                    "_FV-PROVED-BEFORE 0=",
                    "_FV-FIRST-IOR 0=",
                    "_FV-FIRST-OK",
                    "_FV-PROVED-AFTER -1 =",
                    "_FV-MKDIR-IOR 0=",
                    "_FV-SYNC-IOR 0=",
                    "_FV-SECOND-IOR 0=",
                    "_FV-SECOND-D 0<>",
                    "_FV-OPEN2-IOR 0=",
                    "_FV-WRITE2-IOR 0=",
                    "_FV-CLOSE2-IOR 0=",
                    "_FV-SYNC2-IOR 0=",
                    "_FV-V V.LAST-IOR @ 0=",
                    "_FV-V V.FLAGS @ VFS-F-RO AND 0=",
                    *ext4._EXT4_OWNERSHIP_SCOPE_CLEAN_FORTH,
                    "_EXT4-OWN-EA-COUNT @ 0=",
                    "_FV-CTX _EXT4-C.O.ACTIVE + @ 0=",
                ],
            ),
            *_unmount("_FV", "EXT4-FRESH-VOLUME-UNMOUNTED"),
        ],
        capture_media=backing,
        # A proof that ran away used every step of any budget; the three
        # journeys take 165 to 170 million steps.
        max_steps=600_000_000,
    )
    _emitted(output, "EXT4-FRESH-VOLUME-WRITES")
    _emitted(output, "EXT4-FRESH-VOLUME-UNMOUNTED")
    assert trace
    ext4._assert_e2fsck_clean(backing, jbd2_toolchain)
    root = _names(backing, "/", jbd2_toolchain)
    assert {"made", "second.txt"} <= root.keys()
    assert _debugfs(
        backing, "cat /second.txt", jbd2_toolchain, text=False
    ) == b"Z" * 300
    if population == "empty":
        assert "first.txt" in root
    elif population == "file":
        document = _debugfs(
            backing, "cat /doc.txt", jbd2_toolchain, text=False
        )
        assert document == (
            b"Z" * 100 + (b"old document line\n" * 200)[100:2048]
        )
    else:
        assert "inner.txt" in _names(backing, "/dir", jbd2_toolchain)


# ---------------------------------------------------------------------
#  Inode groups on first use
# ---------------------------------------------------------------------


def _fill_commands(directory: Path, files: int) -> tuple[str, ...]:
    """Fill inodes from the root's group on: a folder and FILES empty files."""
    empty = directory / "empty.bin"
    empty.write_bytes(b"")
    return (
        "mkdir /fill",
        *(f"write {empty} /fill/f{index:04d}" for index in range(files)),
    )


def _table_garbage(blocks: int) -> bytes:
    """Bytes a never-written inode table could hold: none of it zero."""
    rng = random.Random(513)
    return bytes(rng.randrange(1, 256) for _ in range(blocks * _BLOCK))


@pytest.fixture(scope="session")
def full_group_volumes(
    jbd2_toolchain: dict[str, object],  # noqa: F811
    tmp_path_factory: pytest.TempPathFactory,
) -> dict[str, Path]:
    """Volumes whose first inode groups the host filled.

    A volume from mke2fs has 500 free inodes in group 0 and 512 in each
    INODE_UNINIT group after it.  `one` has group 0 full, so the next
    inode is group 1's first; that group holds a superblock copy, so its
    block bitmap is already in use.  `four` has groups 0 to 3 full, and
    group 4 is the first that is BLOCK_UNINIT as well.  `lazy` has group 0
    full, no zeroed inode table, and group 1's table full of bytes that
    are not inodes.
    """
    directory = tmp_path_factory.mktemp("ext4-full-groups")
    volumes = {
        "one": _make_volume(
            directory / "one.img",
            jbd2_toolchain,
            commands=_fill_commands(directory, 499),
        ),
        "four": _make_volume(
            directory / "four.img",
            jbd2_toolchain,
            commands=_fill_commands(directory, 499 + 3 * _INODES_PER_GROUP),
        ),
        "lazy": _make_volume(
            directory / "lazy.img",
            jbd2_toolchain,
            lazy_inode_tables=True,
            commands=_fill_commands(directory, 499),
        ),
    }
    for name, full in (("one", 1), ("four", 4), ("lazy", 1)):
        groups = _groups(volumes[name], jbd2_toolchain)
        for group in range(full):
            assert groups[group]["free_inodes"] == 0
            assert "INODE_UNINIT" not in groups[group]["flags"]
        for group in range(full, 8):
            assert "INODE_UNINIT" in groups[group]["flags"]
            assert groups[group]["free_inodes"] == _INODES_PER_GROUP
            assert ("ITABLE_ZEROED" in groups[group]["flags"]) == (
                name != "lazy"
            )
        assert "BLOCK_UNINIT" not in groups[1]["flags"]
        assert "BLOCK_UNINIT" in groups[4]["flags"]
    lazy = volumes["lazy"]
    table = _groups(lazy, jbd2_toolchain)[1]["inode_table"]
    with lazy.open("r+b") as image:
        image.seek(table * _BLOCK)
        image.write(_table_garbage(_INODES_PER_GROUP * _INODE // _BLOCK))
    ext4._assert_e2fsck_clean(lazy, jbd2_toolchain)
    return volumes


def _first_use_checks(prefix: str, inode: int, group: int) -> list[str]:
    """The cold plan took INODE as the first inode of INODE_UNINIT GROUP."""
    return [
        f"{prefix}-IOR 0=",
        f"{prefix}-V V.LAST-IOR @ 0=",
        f"_XC-INODE @ {inode} =",
        f"_XC-FI-GROUP @ {group} =",
        "_XC-GROUP-UNINIT @ -1 =",
        "_XC-FIRST-CLEAR @ 0=",
        f"_XC-GROUP-FREE @ {_INODES_PER_GROUP} =",
        f"_XC-GROUP-NEW-FREE @ {_INODES_PER_GROUP - 1} =",
        f"_XC-GROUP-NEW-UNUSED @ {_INODES_PER_GROUP - 1} =",
        f"{prefix}-FREE-AFTER {prefix}-FREE-BEFORE 1- =",
        f"{prefix}-V V.FLAGS @ VFS-F-RO AND 0=",
        *ext4._EXT4_OWNERSHIP_SCOPE_CLEAN_FORTH,
        f"{prefix}-CTX _EXT4-C.O.ACTIVE + @ 0=",
    ]


def _assert_group_ready(
    image: Path,
    toolchain: dict[str, object],
    group: int,
    *,
    flags: set[str],
    used: tuple[int, ...],
    high_water: int,
    directories: int,
) -> None:
    """GROUP left INODE_UNINIT as the kernel and e2fsprogs require.

    FLAGS are the flags the group keeps, USED its inode indexes in use and
    HIGH_WATER the count of table entries ever used.  The bitmap block
    holds exactly the used inodes and set padding to its end, its checksum
    is in the descriptor, and the descriptor's own checksum covers the new
    counts.
    """
    groups = _groups(image, toolchain)
    state = groups[group]
    assert state["flags"] == flags
    assert state["free_inodes"] == _INODES_PER_GROUP - len(used)
    assert state["unused_inodes"] == _INODES_PER_GROUP - high_water
    assert state["directories"] == directories
    bitmap = ext4._read_ext4_home(
        image, state["inode_bitmap"], block_size=_BLOCK
    )
    expected = bytearray(_INODES_PER_GROUP // 8)
    for index in used:
        expected[index // 8] |= 1 << (index % 8)
    assert bitmap[: _INODES_PER_GROUP // 8] == bytes(expected)
    assert bitmap[_INODES_PER_GROUP // 8 :] == b"\xff" * (
        _BLOCK - _INODES_PER_GROUP // 8
    )
    assert state["inode_bitmap_csum"] == _inode_bitmap_csum(image, bitmap)
    descriptor = _descriptor(image, group)
    assert descriptor == ext4._group_descriptor_with_checksum(
        _superblock(image), descriptor, group
    )
    raw_flags = struct.unpack_from("<H", descriptor, 0x12)[0]
    assert raw_flags & _BG_INODE_UNINIT == 0
    assert bool(raw_flags & _BG_BLOCK_UNINIT) == ("BLOCK_UNINIT" in flags)
    assert bool(raw_flags & _BG_INODE_ZEROED) == ("ITABLE_ZEROED" in flags)
    counts = ext4._ext4_group_counts(image, group)
    assert counts["free_inodes"] == _INODES_PER_GROUP - len(used)
    assert counts["itable_unused"] == _INODES_PER_GROUP - high_water
    assert counts["used_dirs"] == directories


def _assert_checked_inode(image: Path, inode: int) -> bytes:
    record = _inode_record(image, inode)
    assert record == ext4._inode_with_checksum(
        _superblock(image), inode, record
    )
    return record


@pytest.fixture(scope="session")
def ready_group_create(
    full_group_volumes: dict[str, Path],
    jbd2_toolchain: dict[str, object],  # noqa: F811
    tmp_path_factory: pytest.TempPathFactory,
) -> dict[str, object]:
    """Create one file on a volume whose group 0 has no free inode."""
    source = full_group_volumes["one"]
    before = _groups(source, jbd2_toolchain)
    directory = tmp_path_factory.mktemp("ext4-ready-group-create")
    backing = directory / "created.img"
    output, trace, _ = ext4.run_recovery_forth(
        source,
        backing,
        [
            *_mount("_RG"),
            "_RG-FFREE CONSTANT _RG-FREE-BEFORE",
            (
                'S" beyond.txt" _RG-V VFS-MKFILE? '
                "CONSTANT _RG-IOR CONSTANT _RG-D"
            ),
            "_RG-FFREE CONSTANT _RG-FREE-AFTER",
            "_RG-D DUP IF D.VNODE @ THEN CONSTANT _RG-VN",
            *_checked(
                "_RG-OK",
                "EXT4-READY-GROUP-CREATE",
                [
                    *_mounted("_RG"),
                    "_RG-D 0<>",
                    *_first_use_checks("_RG", 513, 1),
                    "_RG-VN VN.TYPE @ VFS-T-FILE =",
                    "_RG-VN VN.BID @ 513 =",
                    "_RG-VN VN.GEN @ 1 =",
                    "_XC-TABLE-FRESH @ 0=",
                    f"_XC-BITMAP-HOME @ {before[1]['inode_bitmap']} =",
                    f"_XC-INODE-HOME @ {before[1]['inode_table']} =",
                    "_RG-CTX _EXT4-C.J.HOME-WRITES + @ 6 =",
                ],
            ),
            *_unmount("_RG", "EXT4-READY-GROUP-CREATE-UNMOUNTED"),
        ],
        capture_media=backing,
    )
    _emitted(output, "EXT4-READY-GROUP-CREATE")
    _emitted(output, "EXT4-READY-GROUP-CREATE-UNMOUNTED")
    return {"source": source, "image": backing, "trace": trace, "before": before}


def test_create_readies_the_next_inode_group(
    ready_group_create: dict[str, object],
    jbd2_toolchain: dict[str, object],  # noqa: F811
) -> None:
    """A create past the last ready group takes the next group's first inode.

    The group leaves INODE_UNINIT in the create's transaction, and its
    inode table keeps ITABLE_ZEROED.
    """
    image = ready_group_create["image"]
    before = ready_group_create["before"]
    assert isinstance(image, Path)
    assert isinstance(before, dict)
    ext4._assert_e2fsck_clean(image, jbd2_toolchain)
    _assert_group_ready(
        image,
        jbd2_toolchain,
        1,
        flags={"ITABLE_ZEROED"},
        used=(0,),
        high_water=1,
        directories=0,
    )
    after = _groups(image, jbd2_toolchain)
    assert after[1]["free_blocks"] == before[1]["free_blocks"]
    for group in (0, *range(2, 8)):
        assert after[group] == before[group]
    assert _names(image, "/", jbd2_toolchain)["beyond.txt"] == 513
    record = _assert_checked_inode(image, 513)
    assert struct.unpack_from("<H", record, 0x00)[0] == 0x81B6
    assert struct.unpack_from("<H", record, 0x1A)[0] == 1
    assert struct.unpack_from("<I", record, 0x64)[0] == 1
    block = ext4._read_ext4_home(
        image, before[1]["inode_table"], block_size=_BLOCK
    )
    assert block[_INODE:] == bytes(_BLOCK - _INODE)
    free_inodes = struct.unpack_from("<I", _superblock(image), 0x10)[0]
    assert free_inodes == 7 * _INODES_PER_GROUP - 1


def test_ready_group_serves_files_and_folders(
    ready_group_create: dict[str, object],
    jbd2_toolchain: dict[str, object],  # noqa: F811
    tmp_path: Path,
) -> None:
    """A group made ready by its first inode works as any other afterwards.

    A second mount creates in it, makes a folder there, creates and
    writes inside that folder, frees two inodes and takes the lowest
    again.  A closed empty file's removal clears its record, so the inode
    starts again at generation 1, and the group's count of unused table
    entries stays at its high-water mark.
    """
    image = ready_group_create["image"]
    assert isinstance(image, Path)
    backing = tmp_path / "served.img"
    output, _, _ = ext4.run_recovery_forth(
        image,
        backing,
        [
            "CREATE _GS-BUF 2000 ALLOT _GS-BUF 2000 71 FILL",
            *_mount("_GS"),
            (
                'S" two.txt" _GS-V VFS-MKFILE? '
                "CONSTANT _GS-TWO-IOR CONSTANT _GS-TWO-D"
            ),
            "_XC-INODE @ CONSTANT _GS-TWO-INO",
            "_XC-GROUP-UNINIT @ CONSTANT _GS-TWO-UNINIT",
            "_XC-GROUP-NEW-UNUSED @ CONSTANT _GS-TWO-UNUSED",
            'S" newdir" _GS-V VFS-MKDIR CONSTANT _GS-DIR-IOR',
            "_XC-INODE @ CONSTANT _GS-DIR-INO",
            "_XC-DATA-BLOCK @ CONSTANT _GS-DIR-BLOCK",
            'S" /newdir" _GS-V VFS-CD? CONSTANT _GS-CD-IOR',
            (
                'S" inside.txt" _GS-V VFS-MKFILE? '
                "CONSTANT _GS-IN-IOR CONSTANT _GS-IN-D"
            ),
            "_XC-INODE @ CONSTANT _GS-IN-INO",
            (
                'S" /newdir/inside.txt" VFS-FF-READ VFS-FF-WRITE OR _GS-V '
                "VFS-OPEN? CONSTANT _GS-OPEN-IOR CONSTANT _GS-FD"
            ),
            "_GS-BUF 2000 _GS-FD VFS-WRITE-EXACT CONSTANT _GS-WRITE-IOR",
            "_GS-FD VFS-CLOSE? CONSTANT _GS-CLOSE-IOR",
            'S" /" _GS-V VFS-CD? CONSTANT _GS-BACK-IOR',
            'S" two.txt" _GS-V VFS-RM CONSTANT _GS-RM2-IOR',
            'S" beyond.txt" _GS-V VFS-RM CONSTANT _GS-RM1-IOR',
            (
                'S" again.txt" _GS-V VFS-MKFILE? '
                "CONSTANT _GS-AGAIN-IOR CONSTANT _GS-AGAIN-D"
            ),
            "_XC-INODE @ CONSTANT _GS-AGAIN-INO",
            "_XC-NEW-GEN @ CONSTANT _GS-AGAIN-GEN",
            "_XC-GROUP-NEW-UNUSED @ CONSTANT _GS-AGAIN-UNUSED",
            "_GS-V VFS-SYNC CONSTANT _GS-SYNC-IOR",
            *_checked(
                "_GS-OK",
                "EXT4-READY-GROUP-SERVES",
                [
                    *_mounted("_GS"),
                    "_GS-TWO-IOR 0=",
                    "_GS-TWO-INO 514 =",
                    "_GS-TWO-UNINIT 0=",
                    f"_GS-TWO-UNUSED {_INODES_PER_GROUP - 2} =",
                    "_GS-DIR-IOR 0=",
                    "_GS-DIR-INO 515 =",
                    "_GS-DIR-BLOCK 8193 U< 0=",
                    "_GS-DIR-BLOCK 16385 U<",
                    "_GS-CD-IOR 0=",
                    "_GS-IN-IOR 0=",
                    "_GS-IN-INO 516 =",
                    "_GS-OPEN-IOR 0=",
                    "_GS-WRITE-IOR 0=",
                    "_GS-CLOSE-IOR 0=",
                    "_GS-BACK-IOR 0=",
                    "_GS-RM2-IOR 0=",
                    "_GS-RM1-IOR 0=",
                    "_GS-AGAIN-IOR 0=",
                    "_GS-AGAIN-INO 513 =",
                    "_GS-AGAIN-GEN 1 =",
                    f"_GS-AGAIN-UNUSED {_INODES_PER_GROUP - 4} =",
                    "_GS-SYNC-IOR 0=",
                    "_GS-V V.LAST-IOR @ 0=",
                    "_GS-V V.FLAGS @ VFS-F-RO AND 0=",
                    *ext4._EXT4_OWNERSHIP_SCOPE_CLEAN_FORTH,
                    "_GS-CTX _EXT4-C.O.ACTIVE + @ 0=",
                ],
            ),
            *_unmount("_GS", "EXT4-READY-GROUP-SERVES-UNMOUNTED"),
        ],
        capture_media=backing,
        max_steps=1_600_000_000,
    )
    _emitted(output, "EXT4-READY-GROUP-SERVES")
    _emitted(output, "EXT4-READY-GROUP-SERVES-UNMOUNTED")
    ext4._assert_e2fsck_clean(backing, jbd2_toolchain)
    _assert_group_ready(
        backing,
        jbd2_toolchain,
        1,
        flags={"ITABLE_ZEROED"},
        used=(0, 2, 3),
        high_water=4,
        directories=1,
    )
    root = _names(backing, "/", jbd2_toolchain)
    assert root["again.txt"] == 513
    assert root["newdir"] == 515
    assert "two.txt" not in root and "beyond.txt" not in root
    assert _names(backing, "/newdir", jbd2_toolchain)["inside.txt"] == 516
    assert _debugfs(
        backing, "cat /newdir/inside.txt", jbd2_toolchain, text=False
    ) == b"G" * 2000
    record = _assert_checked_inode(backing, 513)
    assert struct.unpack_from("<I", record, 0x64)[0] == 1
    assert _inode_record(backing, 514) == bytes(_INODE)


def test_create_leaves_a_block_uninit_group_its_block_side(
    full_group_volumes: dict[str, Path],
    jbd2_toolchain: dict[str, object],  # noqa: F811
    tmp_path: Path,
) -> None:
    """The search passes every full group and readies the first unused one.

    An empty file takes no block, so a group that is BLOCK_UNINIT as well
    keeps that flag: the allocator readies the block side with the first
    block it takes there.  The kernel's allocator readies it here already;
    the format asks for neither, and e2fsprogs leaves it as this does.
    """
    source = full_group_volumes["four"]
    before = _groups(source, jbd2_toolchain)
    backing = tmp_path / "fifth-group.img"
    output, _, _ = ext4.run_recovery_forth(
        source,
        backing,
        [
            *_mount("_G4"),
            "_G4-FFREE CONSTANT _G4-FREE-BEFORE",
            (
                'S" fifth.txt" _G4-V VFS-MKFILE? '
                "CONSTANT _G4-IOR CONSTANT _G4-D"
            ),
            "_G4-FFREE CONSTANT _G4-FREE-AFTER",
            *_checked(
                "_G4-OK",
                "EXT4-READY-FIFTH-GROUP",
                [
                    *_mounted("_G4"),
                    "_G4-D 0<>",
                    *_first_use_checks("_G4", 2049, 4),
                    "_XC-FI-VISITED @ 4 =",
                    "_G4-CTX _EXT4-C.J.HOME-WRITES + @ 6 =",
                ],
            ),
            *_unmount("_G4", "EXT4-READY-FIFTH-GROUP-UNMOUNTED"),
        ],
        capture_media=backing,
        max_steps=1_600_000_000,
    )
    _emitted(output, "EXT4-READY-FIFTH-GROUP")
    _emitted(output, "EXT4-READY-FIFTH-GROUP-UNMOUNTED")
    ext4._assert_e2fsck_clean(backing, jbd2_toolchain)
    _assert_group_ready(
        backing,
        jbd2_toolchain,
        4,
        flags={"BLOCK_UNINIT", "ITABLE_ZEROED"},
        used=(0,),
        high_water=1,
        directories=0,
    )
    after = _groups(backing, jbd2_toolchain)
    assert after[4]["free_blocks"] == before[4]["free_blocks"]
    for group in (0, 1, 2, 3, 5, 6, 7):
        assert after[group] == before[group]
    assert _names(backing, "/", jbd2_toolchain)["fifth.txt"] == 2049


def test_mkdir_readies_both_sides_of_a_group(
    full_group_volumes: dict[str, Path],
    jbd2_toolchain: dict[str, object],  # noqa: F811
    tmp_path: Path,
) -> None:
    """A folder as a group's first inode takes its block there as well.

    One transaction clears INODE_UNINIT and BLOCK_UNINIT in the group's
    descriptor and stages both bitmaps the group stood for.
    """
    source = full_group_volumes["four"]
    before = _groups(source, jbd2_toolchain)
    backing = tmp_path / "mkdir.img"
    output, _, _ = ext4.run_recovery_forth(
        source,
        backing,
        [
            *_mount("_GD"),
            "_GD-FFREE CONSTANT _GD-FREE-BEFORE",
            'S" firstdir" _GD-V VFS-MKDIR CONSTANT _GD-IOR',
            "_GD-FFREE CONSTANT _GD-FREE-AFTER",
            *_checked(
                "_GD-OK",
                "EXT4-READY-GROUP-MKDIR",
                [
                    *_mounted("_GD"),
                    *_first_use_checks("_GD", 2049, 4),
                    "_XC-DATA-BLOCK @ 32769 =",
                    "_GD-CTX _EXT4-C.J.HOME-WRITES + @ 8 =",
                ],
            ),
            *_unmount("_GD", "EXT4-READY-GROUP-MKDIR-UNMOUNTED"),
        ],
        capture_media=backing,
        max_steps=1_600_000_000,
    )
    _emitted(output, "EXT4-READY-GROUP-MKDIR")
    _emitted(output, "EXT4-READY-GROUP-MKDIR-UNMOUNTED")
    ext4._assert_e2fsck_clean(backing, jbd2_toolchain)
    _assert_group_ready(
        backing,
        jbd2_toolchain,
        4,
        flags={"ITABLE_ZEROED"},
        used=(0,),
        high_water=1,
        directories=1,
    )
    after = _groups(backing, jbd2_toolchain)
    assert after[4]["free_blocks"] == before[4]["free_blocks"] - 1
    assert ext4._ext4_block_allocation_state(backing, (32769, 32770)) == {
        32769: True,
        32770: False,
    }
    assert _names(backing, "/", jbd2_toolchain)["firstdir"] == 2049
    assert _names(backing, "/firstdir", jbd2_toolchain).keys() == {".", ".."}


def test_create_readies_a_group_on_the_second_descriptor_block(
    jbd2_toolchain: dict[str, object],  # noqa: F811
    tmp_path: Path,
) -> None:
    """On a 256 MiB volume, group 16 is the first of the second flex group.

    Its descriptor lies in the second block of the descriptor table, and
    its bitmaps and inode table at the start of its own blocks.  With the
    sixteen groups before it full, a create takes its first inode.
    """
    source = _make_volume(
        tmp_path / "wide.img",
        jbd2_toolchain,
        mebibytes=256,
        commands=_fill_commands(tmp_path, 499 + 15 * _INODES_PER_GROUP),
    )
    before = _groups(source, jbd2_toolchain)
    assert len(before) == 32
    for group in range(16):
        assert before[group]["free_inodes"] == 0
    assert before[16]["flags"] == {"INODE_UNINIT", "ITABLE_ZEROED"}
    first = 16 * _INODES_PER_GROUP + 1
    backing = tmp_path / "wide-created.img"
    output, _, _ = ext4.run_recovery_forth(
        source,
        backing,
        [
            *_mount("_GW"),
            "_GW-FFREE CONSTANT _GW-FREE-BEFORE",
            (
                'S" wide.txt" _GW-V VFS-MKFILE? '
                "CONSTANT _GW-IOR CONSTANT _GW-D"
            ),
            "_GW-FFREE CONSTANT _GW-FREE-AFTER",
            *_checked(
                "_GW-OK",
                "EXT4-READY-WIDE-GROUP",
                [
                    *_mounted("_GW"),
                    "_GW-D 0<>",
                    *_first_use_checks("_GW", first, 16),
                    "_XC-FI-VISITED @ 16 =",
                    "_XC-GDT-HOME @ 3 =",
                    "_XC-GDT-OFF @ 0=",
                    f"_XC-BITMAP-HOME @ {before[16]['inode_bitmap']} =",
                    f"_XC-INODE-HOME @ {before[16]['inode_table']} =",
                    "_GW-CTX _EXT4-C.J.HOME-WRITES + @ 6 =",
                ],
            ),
            *_unmount("_GW", "EXT4-READY-WIDE-GROUP-UNMOUNTED"),
        ],
        capture_media=backing,
        max_steps=2_400_000_000,
    )
    source.unlink()
    _emitted(output, "EXT4-READY-WIDE-GROUP")
    _emitted(output, "EXT4-READY-WIDE-GROUP-UNMOUNTED")
    ext4._assert_e2fsck_clean(backing, jbd2_toolchain)
    after = _groups(backing, jbd2_toolchain)
    assert after[16]["flags"] == {"ITABLE_ZEROED"}
    assert after[16]["free_inodes"] == _INODES_PER_GROUP - 1
    assert after[16]["unused_inodes"] == _INODES_PER_GROUP - 1
    assert after[16]["inode_bitmap"] > 16 * 8192
    bitmap = ext4._read_ext4_home(
        backing, after[16]["inode_bitmap"], block_size=_BLOCK
    )
    assert bitmap == b"\x01" + bytes(63) + b"\xff" * (_BLOCK - 64)
    assert after[16]["inode_bitmap_csum"] == _inode_bitmap_csum(
        backing, bitmap
    )
    for group in (*range(16), *range(17, 32)):
        assert after[group] == before[group]
    assert _names(backing, "/", jbd2_toolchain)["wide.txt"] == first
    _assert_checked_inode(backing, first)
    backing.unlink()


def test_unzeroed_inode_table_blocks_are_staged_from_zeros(
    full_group_volumes: dict[str, Path],
    jbd2_toolchain: dict[str, object],  # noqa: F811
    tmp_path: Path,
) -> None:
    """A table the builder did not zero gains only whole initialized blocks.

    Without ITABLE_ZEROED the table holds whatever the medium held.  An
    inode that is the only one in use in its table block is staged in a
    block of zeros, as the kernel reads such a block, so the group's first
    and fifth inodes each start a clean block; the three between them join
    the first one's block as the medium now holds it.  The table's other
    blocks keep their bytes, and the flag stays clear.
    """
    source = full_group_volumes["lazy"]
    table = _groups(source, jbd2_toolchain)[1]["inode_table"]
    garbage = _table_garbage(3)
    assert ext4._read_ext4_home(source, table + 2, block_size=_BLOCK) == (
        garbage[2 * _BLOCK :]
    )
    backing = tmp_path / "lazy.img"
    names = [f"lazy{index}.txt" for index in range(5)]
    creates: list[str] = []
    for index, name in enumerate(names):
        creates.extend(
            (
                (
                    f'S" {name}" _LZ-V VFS-MKFILE? '
                    f"CONSTANT _LZ-IOR{index} CONSTANT _LZ-D{index}"
                ),
                f"_XC-INODE @ CONSTANT _LZ-INO{index}",
                f"_XC-TABLE-FRESH @ CONSTANT _LZ-FRESH{index}",
                f"_XC-NEW-GEN @ CONSTANT _LZ-GEN{index}",
            )
        )
    output, _, _ = ext4.run_recovery_forth(
        source,
        backing,
        [
            *_mount("_LZ"),
            *creates,
            (
                '." [LAZY-FRESH " '
                + " ".join(f"_LZ-FRESH{index} ." for index in range(5))
                + ' ." ]"'
            ),
            (
                '." [LAZY-GEN " '
                + " ".join(f"_LZ-GEN{index} ." for index in range(5))
                + ' ." ]"'
            ),
            *_checked(
                "_LZ-OK",
                "EXT4-LAZY-TABLE",
                [
                    *_mounted("_LZ"),
                    *(f"_LZ-IOR{index} 0=" for index in range(5)),
                    *(
                        f"_LZ-INO{index} {513 + index} ="
                        for index in range(5)
                    ),
                    "_LZ-V V.LAST-IOR @ 0=",
                    "_LZ-V V.FLAGS @ VFS-F-RO AND 0=",
                ],
            ),
            *_unmount("_LZ", "EXT4-LAZY-TABLE-UNMOUNTED"),
        ],
        capture_media=backing,
        max_steps=1_600_000_000,
    )
    _emitted(output, "EXT4-LAZY-TABLE")
    _emitted(output, "EXT4-LAZY-TABLE-UNMOUNTED")
    assert _numbers(output, "LAZY-FRESH") == [-1, 0, 0, 0, -1]
    # Each inode's generation follows the one its table entry held.
    generations = _numbers(output, "LAZY-GEN")
    for index in range(5):
        held = struct.unpack_from("<I", garbage, index * _INODE + 0x64)[0]
        if index in (1, 2, 3):
            held = 0
        assert generations[index] == ((held + 1) & 0xFFFFFFFF or 1)
    ext4._assert_e2fsck_clean(backing, jbd2_toolchain)
    _assert_group_ready(
        backing,
        jbd2_toolchain,
        1,
        flags=set(),
        used=(0, 1, 2, 3, 4),
        high_water=5,
        directories=0,
    )
    root = _names(backing, "/", jbd2_toolchain)
    for index, name in enumerate(names):
        assert root[name] == 513 + index
        _assert_checked_inode(backing, 513 + index)
    second = ext4._read_ext4_home(backing, table + 1, block_size=_BLOCK)
    assert second[_INODE:] == bytes(_BLOCK - _INODE)
    assert ext4._read_ext4_home(backing, table + 2, block_size=_BLOCK) == (
        garbage[2 * _BLOCK :]
    )


def test_create_refuses_an_uninit_group_that_counts_an_inode_in_use(
    full_group_volumes: dict[str, Path],
    jbd2_toolchain: dict[str, object],  # noqa: F811
    tmp_path: Path,
) -> None:
    """An INODE_UNINIT group has every inode free, or its counts are wrong.

    Group 1's descriptor and the superblock each count one inode fewer
    free, under valid checksums, so the mount's sums agree.  The pinned
    e2fsck reports the group, and a create that reaches it refuses as
    corrupt geometry before any write.
    """
    source = full_group_volumes["one"]
    superblock = bytearray(_superblock(source))
    descriptor = bytearray(_descriptor(source, 1))
    struct.pack_into(
        "<H", descriptor, 0x0E, struct.unpack_from("<H", descriptor, 0x0E)[0] - 1
    )
    descriptor = ext4._group_descriptor_with_checksum(
        bytes(superblock), descriptor, 1
    )
    struct.pack_into(
        "<I", superblock, 0x10, struct.unpack_from("<I", superblock, 0x10)[0] - 1
    )
    superblock = ext4._ext4_super_with_checksum(superblock)
    damaged = tmp_path / "damaged.img"
    ext4._copy_sparse_file(source, damaged)
    with damaged.open("r+b") as image:
        image.seek(1024)
        image.write(superblock)
        image.seek(2 * _BLOCK + 64)
        image.write(descriptor)
    checked = _run(
        [jbd2_toolchain["e2fsck"], "-f", "-n", damaged], jbd2_toolchain["env"]
    )
    assert checked.returncode == 4, checked.stdout
    assert "Free inodes count wrong for group #1 (511, counted=512)" in (
        checked.stdout
    )
    backing = tmp_path / "refused.img"
    output, trace, media_sha256 = ext4.run_recovery_forth(
        damaged,
        backing,
        [
            *_mount("_BU"),
            (
                'S" refused.txt" _BU-V VFS-MKFILE? '
                "CONSTANT _BU-IOR CONSTANT _BU-D"
            ),
            (
                'S" refused.txt" _BU-V V.ROOT @ _VFS-FIND-CHILD '
                "CONSTANT _BU-CHILD"
            ),
            *_checked(
                "_BU-OK",
                "EXT4-UNINIT-GROUP-REFUSED",
                [
                    *_mounted("_BU"),
                    "_BU-IOR VFS-IOR-REASON VFS-R-CORRUPT =",
                    "_BU-IOR VFS-IOR-DETAIL EXT4-D-GEOMETRY =",
                    "_BU-D 0=",
                    "_BU-CHILD 0=",
                    "_XC-FI-GROUP @ 1 =",
                    "_XC-GROUP-UNINIT @ -1 =",
                    "_BU-CTX _EXT4-C.J.WRITE-ACTIVE + @ 0=",
                    *ext4._EXT4_OWNERSHIP_SCOPE_CLEAN_FORTH,
                ],
            ),
        ],
        capture_media=backing,
    )
    _emitted(output, "EXT4-UNINIT-GROUP-REFUSED")
    assert trace == ()
    assert media_sha256 == ext4._sha256(damaged)


# ---------------------------------------------------------------------
#  A power cut in the transaction that readies a group
# ---------------------------------------------------------------------

# The operation, its name, the volume, and the group and inode it takes.
_FIRST_USES = {
    "create": (
        'S" beyond.txt" _PC-V VFS-MKFILE? CONSTANT _PC-IOR DROP',
        "beyond.txt",
        "one",
        1,
        513,
    ),
    "mkdir": (
        'S" beyond" _PC-V VFS-MKDIR CONSTANT _PC-IOR',
        "beyond",
        "four",
        4,
        2049,
    ),
}


def _first_use(
    source: Path, media: Path, kind: str, fault_ordinal: int | None
) -> tuple[tuple[str, int, int], ...]:
    """Run the first use of group 1, cutting one write when asked."""
    faults = None
    if fault_ordinal is not None:
        faults = {
            fault_ordinal: {
                "stage": "media",
                "sector_index": 1,
                "byte_index": 0,
                "result": ext4.STORAGE_RESULT_MEDIA_FAILURE,
                "command": ext4.STORAGE_CMD_WRITE,
            }
        }
    output, trace, _ = ext4.run_recovery_forth(
        source,
        media,
        [
            *_mount("_PC"),
            _FIRST_USES[kind][0],
            '." [FIRST-USE " _PC-MOUNT-IOR . _PC-PROFILE-BIND-IOR . ." ]"',
        ],
        write_faults_by_ordinal=faults,
        capture_media=media,
    )
    assert _numbers(output, "FIRST-USE") == [0, 0]
    return trace


def _recovered_presence(
    torn: Path, recovered: Path, name: str
) -> bool:
    """Recover TORN on a fresh mount and say whether NAME is there."""
    output, _, _ = ext4.run_recovery_forth(
        torn,
        recovered,
        [
            f"{1 << 20} A-XMEM ARENA-NEW THROW CONSTANT _PR-ARENA",
            (
                "_PR-ARENA T-VOLUME EXT4-NEW "
                "CONSTANT _PR-MOUNT-IOR CONSTANT _PR-V"
            ),
            (
                f'S" /{name}" _PR-V VFS-RESOLVE? '
                "CONSTANT _PR-IOR CONSTANT _PR-D"
            ),
            "0 _PR-V VFS-UNMOUNT CONSTANT _PR-UNMOUNT-IOR",
            (
                '." [RECOVERED " _PR-MOUNT-IOR . _PR-UNMOUNT-IOR . '
                '_PR-D 0<> . ." ]"'
            ),
        ],
        capture_media=recovered,
    )
    mount_ior, unmount_ior, present = _numbers(output, "RECOVERED")
    assert (mount_ior, unmount_ior) == (0, 0)
    return present != 0


def _continue_after_recovery(recovered: Path, continued: Path) -> None:
    """The recovered volume takes a create on a writable mount."""
    output, _, _ = ext4.run_recovery_forth(
        recovered,
        continued,
        [
            *_mount("_PA"),
            (
                'S" after.txt" _PA-V VFS-MKFILE? '
                "CONSTANT _PA-IOR CONSTANT _PA-D"
            ),
            *_checked(
                "_PA-OK",
                "EXT4-POWER-CUT-CONTINUES",
                [
                    *_mounted("_PA"),
                    "_PA-IOR 0=",
                    "_PA-D 0<>",
                    "_PA-V V.LAST-IOR @ 0=",
                    "_PA-V V.FLAGS @ VFS-F-RO AND 0=",
                ],
            ),
            *_unmount("_PA", "EXT4-POWER-CUT-CONTINUES-UNMOUNTED"),
        ],
        capture_media=continued,
    )
    _emitted(output, "EXT4-POWER-CUT-CONTINUES")
    _emitted(output, "EXT4-POWER-CUT-CONTINUES-UNMOUNTED")


@pytest.mark.parametrize("kind", ("create", "mkdir"))
def test_power_cut_while_readying_a_group_keeps_all_or_nothing(
    full_group_volumes: dict[str, Path],
    jbd2_toolchain: dict[str, object],  # noqa: F811
    tmp_path: Path,
    kind: str,
) -> None:
    """Cut each write of the first use of a group; recover on a new mount.

    A create readies group 1's inode side, and a folder readies both sides
    of group 4.  Every cut tears one block between its two sectors and
    ends the run's writes there.  The next mount either finds the new name
    with its group ready or finds neither, each state passes e2fsck, and
    every cut after the first that kept the name keeps it.  The volumes
    recovered from the first cut, the last, and the two on either side of
    the commit then take another create, in that group either way.
    """
    _, name, volume, group, inode = _FIRST_USES[kind]
    source = full_group_volumes[volume]
    before = _groups(source, jbd2_toolchain)
    whole = tmp_path / "whole.img"
    writes = [
        event
        for event in _first_use(source, whole, kind, None)
        if event[0] == "write"
    ]
    whole.unlink()
    assert len(writes) > 12
    kept: list[bool] = []
    continued: set[int] = set()

    def takes_a_create(ordinal: int, recovered: Path, present: bool) -> None:
        if ordinal in continued:
            return
        continued.add(ordinal)
        after = tmp_path / f"continued-{ordinal}.img"
        _continue_after_recovery(recovered, after)
        ext4._assert_e2fsck_clean(after, jbd2_toolchain)
        assert _names(after, "/", jbd2_toolchain)["after.txt"] == (
            inode + 1 if present else inode
        ), ordinal
        after.unlink()

    earlier: tuple[int, Path, bool] | None = None
    for ordinal in range(1, len(writes) + 1):
        torn = tmp_path / f"torn-{ordinal}.img"
        recovered = tmp_path / f"recovered-{ordinal}.img"
        trace = _first_use(source, torn, kind, ordinal)
        cut_writes = [event for event in trace if event[0] == "write"]
        assert cut_writes == writes[:ordinal], ordinal
        present = _recovered_presence(torn, recovered, name)
        torn.unlink()
        kept.append(present)
        ext4._assert_e2fsck_clean(recovered, jbd2_toolchain)
        root = _names(recovered, "/", jbd2_toolchain)
        if present:
            assert root[name] == inode, ordinal
            _assert_group_ready(
                recovered,
                jbd2_toolchain,
                group,
                flags={"ITABLE_ZEROED"},
                used=(0,),
                high_water=1,
                directories=1 if kind == "mkdir" else 0,
            )
        else:
            assert name not in root, ordinal
            assert _groups(recovered, jbd2_toolchain) == before, ordinal
        edge = earlier is not None and earlier[2] != present
        if earlier is not None:
            if edge:
                takes_a_create(*earlier)
            earlier[1].unlink()
        if edge or ordinal in (1, len(writes)):
            takes_a_create(ordinal, recovered, present)
        earlier = (ordinal, recovered, present)
        gc.collect()
    assert earlier is not None
    earlier[1].unlink()
    assert kept == sorted(kept), kept
    assert kept[0] is False and kept[-1] is True, kept
    assert len(continued) == 4, continued


# ---------------------------------------------------------------------
#  Reloads read what writes reached
# ---------------------------------------------------------------------
#
# Every checkpoint authenticates the mount from the medium again.  Once a
# mount has validated the backup copies and counted the orphan file, a
# reload reads neither again until a write reaches it, and a write to the
# orphan file brings its count back.  The case runs on the 64 MiB fixture
# volume with a 2 KiB /doc.txt that test_vfs_replace_ext4.py builds, through
# that file's machine, and records the sectors of every read the device
# starts.

_ORPHAN_FILE_INODE = 12

# Words the case defines on its machine, one line each.
_RELOAD_WORDS = (
    "CREATE UV-BUF 128 ALLOT UV-BUF 128 65 FILL VARIABLE UV-FD VARIABLE UV-FD2",
    (
        ": UV-OPEN VFS-FF-READ VFS-FF-WRITE OR SVT-V @ VFS-OPEN? "
        '." [open " . ." ]" ;'
    ),
    (
        ": UV-WRITE 0 UV-FD @ VFS-SEEK? UV-BUF 100 UV-FD @ VFS-WRITE? "
        '." [write " . . . ." ]" ;'
    ),
    ': UV-FILL2 UV-BUF 100 UV-FD2 @ VFS-WRITE? ." [fill " . . ." ]" ;',
    ': UV-CLOSE UV-FD @ VFS-CLOSE? ." [close " . ." ]" ;',
    ': UV-CLOSE2 UV-FD2 @ VFS-CLOSE? ." [close " . ." ]" ;',
    ': UV-MK SVT-V @ VFS-MKFILE? ." [mk " . DROP ." ]" ;',
    ': UV-RM SVT-V @ VFS-RM ." [rm " . ." ]" ;',
)


def _record_reads(machine: rx.Machine) -> list[tuple[int, int]]:
    """Record the first sector and sector count of every read MACHINE's
    device starts from now on."""
    reads: list[tuple[int, int]] = []
    storage = machine.system.storage
    start_dma = storage._start_dma

    def track(request, phase):
        if phase == "read":
            reads.append((request[1], request[3]))
        return start_dma(request, phase)

    storage._start_dma = track
    return reads


def _blocks_read(reads: list[tuple[int, int]]) -> collections.Counter:
    """How many times READS read each block."""
    per_block = _BLOCK // rx.SECTOR
    counted: collections.Counter = collections.Counter()
    for sector, sectors in reads:
        first = sector // per_block
        last = (sector + sectors - 1) // per_block
        counted.update(range(first, last + 1))
    return counted


def _orphan_file_blocks(image: Path) -> set[int]:
    """The blocks the orphan file's depth-zero extent map holds."""
    _, record, _ = ext4._ext4_inode_record(image, _ORPHAN_FILE_INODE)
    root = record[0x28 : 0x28 + 60]
    magic, entries, _, depth = struct.unpack_from("<HHHH", root, 0)
    assert magic == 0xF30A and depth == 0
    blocks: set[int] = set()
    for index in range(entries):
        offset = 12 + 12 * index
        length = struct.unpack_from("<H", root, offset + 4)[0]
        if length > 0x8000:
            length -= 0x8000
        start = (struct.unpack_from("<H", root, offset + 6)[0] << 32) | (
            struct.unpack_from("<I", root, offset + 8)[0]
        )
        blocks.update(range(start, start + length))
    assert blocks
    return blocks


def _backup_blocks(media: bytes) -> tuple[set[int], set[int], set[int]]:
    """The blocks of the backup copies: each sparse group's superblock and
    descriptor blocks, which the backup validation reads; those blocks with
    their reserved successors, less the two every journal validation reads
    too; and those two.  The journal's witness is group 1's copy: its
    superblock, for the journal tuple, and the descriptor block after it,
    for group 0's descriptor, which locate the journal inode."""
    superblock = media[1024:2048]
    blocks_count = struct.unpack_from("<I", superblock, 0x04)[0]
    first = struct.unpack_from("<I", superblock, 0x14)[0]
    per_group = struct.unpack_from("<I", superblock, 0x20)[0]
    reserved = struct.unpack_from("<H", superblock, 0xCE)[0]
    groups = -(-(blocks_count - first) // per_group)
    descriptor_blocks = -(-(groups * 64) // _BLOCK)
    starts = [
        first + group * per_group
        for group in range(1, groups)
        if ext4._ext4_sparse_group(group)
    ]
    copies: set[int] = set()
    region: set[int] = set()
    for start in starts:
        copies.update(range(start, start + 1 + descriptor_blocks))
        region.update(range(start, start + 1 + descriptor_blocks + reserved))
    assert starts and starts[0] == first + per_group
    witness = {starts[0], starts[0] + 1}
    return copies, region - witness, witness


def test_reloads_read_again_only_what_a_write_reached(
    document_volume: bytes,  # noqa: F811
    jbd2_toolchain: dict[str, object],  # noqa: F811
    tmp_path: Path,
) -> None:
    """After the mount's validation, a reload reads again only what a write
    reached.

    Mounting reads every orphan-file block once and every backup copy.  The
    writes, syncs and creates that follow, the first write's ownership proof
    included, read neither again, but for the two blocks of group 1's copy
    that every journal validation reads as its witness.  Removing a file
    with storage writes the orphan file, the reloads after that write count
    it again, and the write after the removal reads it no more.
    """
    image = tmp_path / "volume.img"
    ext4._write_sparse_bytes(image, document_volume)
    orphan = _orphan_file_blocks(image)
    image.unlink()
    copies, backups, witness = _backup_blocks(document_volume)

    machine = rx.Machine(bytearray(document_volume))
    reads = _record_reads(machine)
    assert machine.up() == [0, 0, 0]
    mounted = _blocks_read(reads)
    assert {block: mounted[block] for block in orphan} == dict.fromkeys(
        orphan, 1
    )
    assert all(mounted[block] for block in copies), sorted(
        block for block in copies if not mounted[block]
    )
    for line in _RELOAD_WORDS:
        machine.line(line)
    reads.clear()

    steps = (
        ('S" /doc.txt" UV-OPEN UV-FD !', "open", ["0"]),
        ("UV-WRITE", "write", ["0", "100", "0"]),
        ("UV-WRITE", "write", ["0", "100", "0"]),
        ("SVT-SYNC", "sync", ["0"]),
        ("UV-WRITE", "write", ["0", "100", "0"]),
        ('S" new.bin" UV-MK', "mk", ["0"]),
        ('S" /new.bin" UV-OPEN UV-FD2 !', "open", ["0"]),
        ("UV-FILL2", "fill", ["0", "100"]),
        ("UV-CLOSE2", "close", ["0"]),
        ("SVT-SYNC", "sync", ["0"]),
    )
    for index, (text, tag, expected) in enumerate(steps):
        assert machine.one(text, tag) == expected, text
        touched = set(_blocks_read(reads))
        assert not touched & orphan, (text, sorted(touched & orphan))
        assert not touched & backups, (text, sorted(touched & backups))
        if index == 1:
            assert witness <= touched, sorted(witness - touched)
        reads.clear()

    assert machine.one('S" /new.bin" UV-RM', "rm") == ["0"]
    touched = set(_blocks_read(reads))
    assert orphan <= touched, sorted(orphan - touched)
    assert not touched & backups, sorted(touched & backups)
    reads.clear()
    assert machine.one("UV-WRITE", "write") == ["0", "100", "0"]
    touched = set(_blocks_read(reads))
    assert not touched & (orphan | backups), sorted(
        touched & (orphan | backups)
    )

    assert machine.one("UV-CLOSE", "close") == ["0"]
    assert machine.one("SVT-SYNC", "sync") == ["0"]
    assert machine.one("SVT-DOWN", "down") == ["0"]
    left = tmp_path / "left.img"
    ext4._write_sparse_bytes(left, bytes(machine.media))
    machine.close()
    ext4._assert_e2fsck_clean(left, jbd2_toolchain)
    stat = ext4._general_write_debugfs(left, "stat /doc.txt", jbd2_toolchain)
    assert re.search(r"Size: 2048\b", stat), stat
    left.unlink()
