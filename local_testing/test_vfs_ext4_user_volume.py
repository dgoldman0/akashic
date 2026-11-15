#!/usr/bin/env python3
"""The ext4 writer on volumes as a user volume is built and used.

The fixture images of test_vfs_ext4.py carry a fixed population.  These
cases build their volumes with the profile's own mke2fs options and
populate them, or leave them empty, as a user's volume would be, then run
the driver on them through the helpers of test_vfs_ext4.py.
"""

from __future__ import annotations

import random
import re
import subprocess
from pathlib import Path

import pytest

import test_vfs_ext4 as ext4
from test_vfs_ext4 import jbd2_toolchain  # noqa: F401  (session fixture)

_ROW = ext4.IMAGE_ROWS["primary-1k-i256"]
_BLOCK = 1024
_INODES_PER_GROUP = 512
_EPOCH_MS = ext4._STAGED_APPEND_EPOCH_MS


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
        counts = re.search(
            r"(\d+) free blocks, (\d+) free inodes, (\d+) directories"
            r", (\d+) unused inodes",
            line,
        )
        if counts:
            current.update(
                free_blocks=int(counts.group(1)),
                free_inodes=int(counts.group(2)),
                directories=int(counts.group(3)),
                unused_inodes=int(counts.group(4)),
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

