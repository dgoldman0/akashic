#!/usr/bin/env python3
"""Writes and syncs on ext4 while a removed file is still open.

A file whose last link goes while a descriptor holds it keeps its record in
the orphan file until the descriptor closes.  The driver retains that record:
the volume takes every other write, the records of other removals join and
drain beside it, and VFS-SYNC lands the journal with the record kept and
ORPHAN_PRESENT set, as the kernel's ext4_freeze leaves a volume whose orphan
file is in use.  The last close drains the record, and the next mount after a
power cut drains every record the volume holds.

The cases run on the 64 MiB fixture volume with a 2 KiB /doc.txt that
test_vfs_replace_ext4.py builds, through that file's machine, which records
every block a run writes, and they judge each result by what the driver
serves and by the pinned e2fsck and debugfs.  The power-cut cases rebuild the
medium as it stood after a chosen write, or with only the first of that
write's two sectors applied, and mount it in a fresh machine, which recovers
the journal and drains the orphan file before VREPL-RECOVER settles the save.

A judged cut costs a mount with whatever recovery it does and the host
checks, 5 to 15 seconds.  Every write of a sync is cut whole and torn, and so
is every write that activates the journal again after one; the other phases
are cut on either side of each commit block and after every eighth write.
AKASHIC_RETAINED_CUT_STRIDE=1 in the environment cuts after every write.
"""

from __future__ import annotations

import gc
import os
import re
import struct
import subprocess
from pathlib import Path

import pytest

import test_vfs_ext4 as ext4
import test_vfs_replace_ext4 as rx
from test_vfs_ext4 import canonical_images, jbd2_toolchain  # noqa: F401
from test_vfs_replace_ext4 import document_volume  # noqa: F401

_BLOCK = 1024
_SECTOR = 512
_SUPER = 1024
_INCOMPAT_RECOVER = 0x4
_RO_ORPHAN_PRESENT = 0x0001_0000
_ORPHAN_FILE_INODE = 12

CUT_STRIDE = int(os.environ.get("AKASHIC_RETAINED_CUT_STRIDE", "8"))
if CUT_STRIDE < 1:
    raise RuntimeError("AKASHIC_RETAINED_CUT_STRIDE must be 1 or more")

FIRST = rx.pattern(rx.NEW_SEED, 2048)
SECOND = rx.pattern(rx.NEW_SEED + 1, 4096)

# Words each case defines on its machine, one line each.  RO-STATE prints
# whether RECOVER and the write-active journal stand, the number of orphan
# records, whether ORPHAN_PRESENT is set and whether the volume is dirty.
_WORDS = (
    "VARIABLE RO-FD2 VARIABLE RO-FD3",
    (
        ': RO-STATE ." [state " SVT-V @ _EXT4-CTX '
        "DUP _EXT4-C.RECOVERY + @ 0<> . "
        "DUP _EXT4-C.J.WRITE-ACTIVE + @ 0<> . "
        "DUP _EXT4-C.O.ACTIVE + @ . _EXT4-C.SB + _EXT4-SB.RO-COMPAT + L@ "
        "_EXT4-RO-ORPHAN-PRESENT AND 0<> . "
        'SVT-V @ V.FLAGS @ VFS-F-DIRTY AND 0<> . ." ]" ;'
    ),
    ': RO-RM SVT-V @ VFS-RM ." [rm " . ." ]" ;',
    ': RO-MK SVT-V @ VFS-MKFILE? ." [mk " . DROP ." ]" ;',
    ': RO-HOLD2 VFS-OPEN DUP RO-FD2 ! ." [hold2 " 0<> . ." ]" ;',
    ': RO-HOLD3 VFS-OPEN DUP RO-FD3 ! ." [hold3 " 0<> . ." ]" ;',
    ': RO-RELEASE2 RO-FD2 @ VFS-CLOSE? ." [release2 " . ." ]" ;',
    ': RO-RELEASE3 RO-FD3 @ VFS-CLOSE? ." [release3 " . ." ]" ;',
    (
        ": RO-HELD2 RO-FD2 @ VFS-REWIND SVT-BACK RO-FD2 @ VFS-SIZE "
        'RO-FD2 @ VFS-READ ." [held2 " DUP . SVT-BACK SWAP CRC32 . ." ]" ;'
    ),
    ': RO-TRUNC3 RO-FD3 @ VFS-TRUNCATE ." [trunc " . ." ]" ;',
)

# RO-STATE's records: a journal kept active since the last write, and one
# a sync has landed.
_ACTIVE = ["-1", "-1"]
_LANDED = ["0", "0"]


def _words(machine: rx.Machine) -> None:
    for line in _WORDS:
        machine.line(line)


def _state(machine: rx.Machine) -> list[str]:
    return machine.one("RO-STATE", "state")


def _run(argv, env) -> subprocess.CompletedProcess:
    return subprocess.run(
        [str(part) for part in argv],
        env=env,
        capture_output=True,
        text=True,
        check=False,
    )


def _image(media: bytes, path: Path) -> Path:
    ext4._write_sparse_bytes(path, media)
    return path


def _inode_number(image: Path, name: str, toolchain) -> int:
    stat = ext4._general_write_debugfs(image, f"stat {name}", toolchain)
    match = re.search(r"Inode: (\d+)", stat)
    assert match is not None, stat
    return int(match.group(1))


def _orphan_slots(image: Path) -> list[int]:
    """The live records of the orphan file's first block."""
    _, orphan_inode, _ = ext4._ext4_inode_record(image, _ORPHAN_FILE_INODE)
    block = ext4._extent_root_physical(orphan_inode, 0)
    with image.open("rb") as source:
        source.seek(block * _BLOCK)
        data = source.read(_BLOCK)
    slots = struct.unpack_from(f"<{(_BLOCK - 8) // 4}I", data)
    return [slot for slot in slots if slot]


def _assert_landed_with_records(
    media: bytes, inodes: list[int], folder: Path, toolchain
) -> None:
    """MEDIA is a landed journal beside the records of INODES.

    The superblock is clean with ORPHAN_PRESENT set, the orphan file holds
    the records, and each record's inode has no links and no deletion time.
    The pinned e2fsck in preen mode releases exactly those inodes, as the
    kernel's orphan cleanup would, reports nothing else, and then finds the
    volume clean.
    """
    image = _image(media, folder / "landed.img")
    super_block = media[_SUPER : _SUPER + _BLOCK]
    assert not struct.unpack_from("<I", super_block, 0x60)[0] & (
        _INCOMPAT_RECOVER
    )
    assert struct.unpack_from("<H", super_block, 0x3A)[0] == 1
    assert struct.unpack_from("<I", super_block, 0x64)[0] & _RO_ORPHAN_PRESENT
    assert sorted(_orphan_slots(image)) == sorted(inodes)
    for inode in inodes:
        _, record, _ = ext4._ext4_inode_record(image, inode)
        assert struct.unpack_from("<H", record, 0x1A)[0] == 0, inode
        assert struct.unpack_from("<I", record, 0x14)[0] == 0, inode
    preen = _run(
        [toolchain["e2fsck"], "-f", "-p", image], toolchain["env"]
    )
    assert preen.returncode in (0, 1), preen.stdout + preen.stderr
    released = sorted(
        int(number)
        for number in re.findall(
            r"Clearing orphaned inode (\d+)", preen.stdout + preen.stderr
        )
    )
    assert released == sorted(inodes), preen.stdout + preen.stderr
    # Preen names every problem it fixes, so a run that prints only the
    # released records and its summary found nothing else wrong.
    for line in (preen.stdout + preen.stderr).splitlines():
        assert (
            not line.strip()
            or "Clearing orphaned inode" in line
            or re.search(r": \d+/\d+ files .* blocks$", line)
            or line.startswith("e2fsck ")
        ), preen.stdout + preen.stderr
    ext4._assert_e2fsck_clean(image, toolchain)
    image.unlink()


def _root_names(media: bytes, folder: Path, toolchain) -> set[str]:
    image = _image(media, folder / "names.img")
    listing = ext4._general_write_debugfs(image, "ls -l /", toolchain)
    image.unlink()
    names: set[str] = set()
    for line in listing.splitlines():
        fields = line.split()
        if len(fields) >= 9 and fields[0].isdigit():
            names.add(fields[-1])
    return names


@pytest.fixture(autouse=True)
def _collect_machines():
    """Free each case's machines before the next case builds its own."""
    yield
    gc.collect()


def test_sync_lands_beside_a_removed_file_held_open(
    document_volume: bytes,  # noqa: F811
    jbd2_toolchain: dict[str, object],  # noqa: F811
    tmp_path: Path,
) -> None:
    """The sync lands, writes go on, and the last close drains the record.

    The landing writes its six blocks in seven flushes, as any landing
    does, and leaves the superblock clean with ORPHAN_PRESENT set.  A create
    and a first save then reopen the journal, a second sync lands again,
    and the descriptor still reads the bytes it opened.  Its close finds the
    journal landed, opens it once more, drains the record and clears
    ORPHAN_PRESENT.
    """
    volume_image = _image(document_volume, tmp_path / "volume.img")
    doc_inode = _inode_number(volume_image, "/doc.txt", jbd2_toolchain)
    volume_image.unlink()
    machine = rx.Machine(bytearray(document_volume))
    assert machine.up() == [0, 0, 0]
    _words(machine)
    assert machine.one('S" /doc.txt" SVT-HOLD', "hold") == ["-1"]
    assert machine.one('S" /doc.txt" RO-RM', "rm") == ["0"]
    assert _state(machine) == [*_ACTIVE, "1", "-1", "-1"]

    writes, flushes = len(machine.writes), machine.flushes
    assert machine.one("SVT-SYNC", "sync") == ["0"]
    assert (len(machine.writes) - writes, machine.flushes - flushes) == (6, 7)
    assert _state(machine) == [*_LANDED, "1", "-1", "0"]
    _assert_landed_with_records(
        bytes(machine.media), [doc_inode], tmp_path, jbd2_toolchain
    )

    assert machine.one('S" x.txt" RO-MK', "mk") == ["0"]
    assert _state(machine) == [*_ACTIVE, "1", "-1", "-1"]
    machine.line(f"{rx.NEW_SEED} 2048 SVT-FILL")
    assert machine.one("2048 SVT-NEW SVT-SAVE", "save") == [
        str(rx.VREPL_S_OK)
    ]
    assert machine.one("SVT-SYNC", "sync") == ["0"]
    assert _state(machine) == [*_LANDED, "1", "-1", "0"]
    assert machine.one("SVT-HELD-READ", "held") == rx._file_record(
        rx.OLD_DOC
    )

    assert machine.one("SVT-RELEASE", "release") == ["0"]
    assert _state(machine) == [*_ACTIVE, "0", "0", "-1"]
    assert machine.one("SVT-SYNC", "sync") == ["0"]
    assert _state(machine) == [*_LANDED, "0", "0", "0"]
    assert machine.one('S" /new.txt" SVT-FILE', "file") == rx._file_record(
        FIRST
    )
    assert machine.one("SVT-DOWN", "down") == ["0"]
    assert rx._host_view(machine.media, tmp_path, jbd2_toolchain) == {
        "new.txt": FIRST
    }
    assert {"x.txt", "new.txt"} <= _root_names(
        bytes(machine.media), tmp_path, jbd2_toolchain
    )


def test_records_of_several_open_files_drain_each_on_its_own_close(
    document_volume: bytes,  # noqa: F811
    jbd2_toolchain: dict[str, object],  # noqa: F811
    tmp_path: Path,
) -> None:
    """Records join and drain beside the ones the mount retains.

    A save over the held /doc.txt leaves its old file as a record.  The next
    save renames over the first one's file, which nothing holds: that victim
    takes the next empty slot of the orphan file and drains at once, a
    deletion that leaves the other record and ORPHAN_PRESENT in place.  A
    second held file then loses its last link, a sync lands beside both
    records, and each close drains its own.  A fresh mount of the landed
    volume drains both, and the pinned e2fsck in preen mode releases the
    same two inodes.
    """
    volume_image = _image(document_volume, tmp_path / "volume.img")
    doc_inode = _inode_number(volume_image, "/doc.txt", jbd2_toolchain)
    volume_image.unlink()
    machine = rx.Machine(bytearray(document_volume))
    assert machine.up() == [0, 0, 0]
    _words(machine)
    assert machine.one('S" /doc.txt" SVT-HOLD', "hold") == ["-1"]
    machine.line(f"{rx.NEW_SEED} 2048 SVT-FILL")
    assert machine.one("2048 SVT-DOC SVT-SAVE", "save") == [
        str(rx.VREPL_S_OK)
    ]
    assert _state(machine) == [*_ACTIVE, "1", "-1", "-1"]
    machine.line(f"{rx.NEW_SEED + 1} 4096 SVT-FILL")
    assert machine.one("4096 SVT-DOC SVT-SAVE", "save") == [
        str(rx.VREPL_S_OK)
    ]
    assert _state(machine) == [*_ACTIVE, "1", "-1", "-1"]
    assert machine.one('S" /doc.txt" SVT-FILE', "file") == rx._file_record(
        SECOND
    )

    assert machine.one('S" /doc.txt" RO-HOLD2', "hold2") == ["-1"]
    second_inode = int(
        machine.one(
            ': RO-INO ." [ino " RO-FD2 @ FD.INODE @ D.VNODE @ VN.BID @ . '
            '." ]" ; RO-INO',
            "ino",
        )[0]
    )
    assert machine.one('S" /doc.txt" RO-RM', "rm") == ["0"]
    assert _state(machine) == [*_ACTIVE, "2", "-1", "-1"]
    assert machine.one("SVT-SYNC", "sync") == ["0"]
    assert _state(machine) == [*_LANDED, "2", "-1", "0"]
    landed = bytes(machine.media)
    _assert_landed_with_records(
        landed, [doc_inode, second_inode], tmp_path, jbd2_toolchain
    )

    assert machine.one("SVT-HELD-READ", "held") == rx._file_record(
        rx.OLD_DOC
    )
    assert machine.one("RO-HELD2", "held2") == rx._file_record(SECOND)
    assert machine.one("SVT-RELEASE", "release") == ["0"]
    assert _state(machine) == [*_ACTIVE, "1", "-1", "-1"]
    assert machine.one("SVT-SYNC", "sync") == ["0"]
    assert _state(machine) == [*_LANDED, "1", "-1", "0"]
    assert machine.one("RO-RELEASE2", "release2") == ["0"]
    assert _state(machine) == [*_ACTIVE, "0", "0", "-1"]
    assert machine.one("SVT-SYNC", "sync") == ["0"]
    assert machine.one("SVT-DOWN", "down") == ["0"]
    assert rx._host_view(machine.media, tmp_path, jbd2_toolchain) == {}
    machine.close()

    fresh = rx.Machine(bytearray(landed))
    assert fresh.up() == [0, 0, 0]
    _words(fresh)
    assert _state(fresh) == [*_LANDED, "0", "0", "0"]
    assert fresh.one("SVT-DOWN", "down") == ["0"]
    assert rx._host_view(fresh.media, tmp_path, jbd2_toolchain) == {}
    fresh.close()


def test_truncate_across_transactions_beside_a_retained_record(
    document_volume: bytes,  # noqa: F811
    jbd2_toolchain: dict[str, object],  # noqa: F811
    tmp_path: Path,
) -> None:
    """A truncate's record joins the union and leaves the retained one.

    /long.bin holds 17,000 blocks across three groups, and a writer of five
    metadata homes releases them in more than one transaction.  With the
    removed /doc.txt still open, the truncate's insertion takes the orphan
    file's next empty slot beside doc's record and keeps ORPHAN_PRESENT; the
    pass that ends the release removes the truncate's record, and no
    transaction clears ORPHAN_PRESENT while doc's record remains.  The orphan
    block is written by the insertion and that last pass alone.
    """
    blocks = 17_000
    source = tmp_path / "long.bin"
    source.write_bytes(ext4._general_write_bytes(blocks * _BLOCK, 71))
    volume_image = _image(document_volume, tmp_path / "volume.img")
    wrote = _run(
        [jbd2_toolchain["debugfs"], "-w", "-R", f"write {source} long.bin",
         volume_image],
        jbd2_toolchain["env"],
    )
    assert wrote.returncode == 0, wrote.stdout + wrote.stderr
    source.unlink()
    ext4._assert_e2fsck_clean(volume_image, jbd2_toolchain)
    _, orphan_inode, _ = ext4._ext4_inode_record(
        volume_image, _ORPHAN_FILE_INODE
    )
    orphan_offset = ext4._extent_root_physical(orphan_inode, 0) * _BLOCK
    volume = volume_image.read_bytes()
    volume_image.unlink()

    machine = rx.Machine(bytearray(volume))
    _words(machine)
    machine.line(
        ": RO-UP5 SVT-MOUNT ?DUP IF EXIT THEN ['] SVT-NOW 0 SVT-V @ "
        "EXT4-BIND-WRITE-CLOCK? ?DUP IF EXIT THEN 5 0 0 SVT-V @ "
        "EXT4-WRITER-WORKSPACE-BYTES? ?DUP IF NIP EXIT THEN "
        "A-XMEM ARENA-NEW THROW SVT-WRITER ! 0 ;"
    )
    machine.line(
        ': RO-UP RO-UP5 ?DUP IF ." [up " . ." ]" EXIT THEN SVT-WRITER @ '
        "5 0 0 SVT-V @ EXT4-BIND-WRITER-ARENA? "
        'DUP 0= IF SVT-V @ VFS-USE THEN ." [up " . ." ]" ;'
    )
    assert machine.one("RO-UP", "up") == ["0"]
    assert machine.one('S" /doc.txt" SVT-HOLD', "hold") == ["-1"]
    assert machine.one('S" /doc.txt" RO-RM', "rm") == ["0"]
    assert machine.one("SVT-SYNC", "sync") == ["0"]
    assert _state(machine) == [*_LANDED, "1", "-1", "0"]

    assert machine.one('S" /long.bin" RO-HOLD3', "hold3") == ["-1"]
    first = len(machine.writes)
    assert machine.one("1024 RO-TRUNC3", "trunc") == ["0"]
    truncate = machine.writes[first:]
    commits = [left for _, _, left in truncate if rx._is_commit_block(left)]
    assert len(commits) >= 3, len(commits)
    assert sum(offset == orphan_offset for offset, _, _ in truncate) == 2
    assert _state(machine) == [*_ACTIVE, "1", "-1", "-1"]

    writes = len(machine.writes)
    assert machine.one("RO-RELEASE3", "release3") == ["0"]
    assert len(machine.writes) == writes
    assert machine.one("SVT-RELEASE", "release") == ["0"]
    assert _state(machine) == [*_ACTIVE, "0", "0", "-1"]
    assert machine.one("SVT-SYNC", "sync") == ["0"]
    assert machine.one("SVT-DOWN", "down") == ["0"]
    image = _image(bytes(machine.media), tmp_path / "after.img")
    ext4._assert_e2fsck_clean(image, jbd2_toolchain)
    stat = ext4._general_write_debugfs(image, "stat /long.bin", jbd2_toolchain)
    assert re.search(r"Size: 1024\b", stat), stat
    assert "Blockcount: 2\n" in stat, stat
    image.unlink()


# ---------------------------------------------------------------------
#  Power cuts while a record is retained
# ---------------------------------------------------------------------

# The phases of the recorded run, after a first save over the held /doc.txt
# has left the old file's record: a sync that lands beside it, a second save
# whose victim drains beside it, a second landing, the close that drains the
# record, and a landing with the orphan file empty.
PHASES = ("landing", "save", "landing-again", "last-close", "landing-empty")
PHASE_LINES = {
    "landing": "SVT-SYNC",
    "save": "4096 SVT-DOC SVT-SAVE",
    "landing-again": "SVT-SYNC",
    "last-close": "SVT-RELEASE",
    "landing-empty": "SVT-SYNC",
}
# The second save's transactions: the stage's create, its write, the
# rename, and the first save's file, whose one release pass also deletes it.
SAVE_TRANSACTIONS = 4
RENAME_TRANSACTION = 2


def _is_descriptor_block(block: bytes) -> bool:
    return block[:4] == b"\xc0\x3b\x39\x98" and block[4:8] == b"\0\0\0\1"


@pytest.fixture(scope="session")
def retained_run(
    document_volume: bytes,  # noqa: F811
) -> dict[str, object]:
    """Every write of the phases, from the medium the first save left."""
    machine = rx.Machine(bytearray(document_volume))
    assert machine.up() == [0, 0, 0]
    _words(machine)
    assert machine.one('S" /doc.txt" SVT-HOLD', "hold") == ["-1"]
    machine.line(f"{rx.NEW_SEED} 2048 SVT-FILL")
    assert machine.one("2048 SVT-DOC SVT-SAVE", "save") == [
        str(rx.VREPL_S_OK)
    ]
    assert _state(machine) == [*_ACTIVE, "1", "-1", "-1"]
    base = bytes(machine.media)
    start = len(machine.writes)
    spans: dict[str, tuple[int, int]] = {}
    for phase in PHASES:
        first = len(machine.writes) - start
        if phase == "save":
            machine.line(f"{rx.NEW_SEED + 1} 4096 SVT-FILL")
        records = machine.line(PHASE_LINES[phase])
        values = [value for tag in records for value in records[tag]]
        assert values in ([["0"]], [[str(rx.VREPL_S_OK)]]), (phase, values)
        spans[phase] = (first, len(machine.writes) - start)
    writes = machine.writes[start:]
    machine.close()
    assert all(len(left) == _BLOCK for _, _, left in writes)
    commits = [
        index + 1
        for index, (_, _, left) in enumerate(writes)
        if rx._is_commit_block(left)
    ]
    save_first, save_last = spans["save"]
    save_commits = [c for c in commits if save_first < c <= save_last]
    assert len(save_commits) == SAVE_TRANSACTIONS, save_commits
    for phase in ("landing", "landing-again", "landing-empty"):
        first, last = spans[phase]
        assert last - first == 6, (phase, first, last)
    return {
        "base": base,
        "writes": writes,
        "spans": spans,
        "commits": commits,
        "published": save_commits[RENAME_TRANSACTION],
    }


def _cuts(run: dict[str, object], phase: str) -> list[tuple[int, bool]]:
    """The states to judge in PHASE: (whole writes applied, whether the
    first sector of the next write is applied too)."""
    writes = run["writes"]
    first, last = run["spans"][phase]
    whole = {first, last}
    torn: set[int] = set()
    if phase.startswith("landing"):
        whole.update(range(first, last + 1))
        torn.update(range(first, last))
    else:
        whole.update(range(first, last + 1, CUT_STRIDE))
        # The writes that open the journal again after a landing come
        # before the phase's first descriptor block.
        for index in range(first, last):
            if _is_descriptor_block(writes[index][2]):
                break
            whole.update((index, index + 1))
            torn.add(index)
        for commit in run["commits"]:
            if first < commit <= last:
                whole.update((commit - 1, commit))
    return sorted({(a, False) for a in whole} | {(a, True) for a in torn})


@pytest.mark.parametrize("phase", PHASES)
def test_power_cut_with_a_record_retained_recovers_at_the_next_mount(
    retained_run: dict[str, object],
    jbd2_toolchain: dict[str, object],  # noqa: F811
    tmp_path: Path,
    phase: str,
) -> None:
    """Cut the power during one phase; the next mount drains every record.

    A fresh mount recovers each state, completing a landing that the cut
    interrupted whether or not records remain, drains the orphan file,
    and serves /doc.txt as the first save left it until the second save's
    rename commits, and as the second save left it from then on.  The volume
    it leaves holds no record, no companion of the save, and passes the
    pinned e2fsck.
    """
    base = retained_run["base"]
    writes = retained_run["writes"]
    published = retained_run["published"]
    assert isinstance(base, bytes)
    problems: list[str] = []
    for applied, torn in _cuts(retained_run, phase):
        medium = bytearray(base)
        for offset, _, left in writes[:applied]:
            medium[offset : offset + len(left)] = left
        if torn:
            offset, _, left = writes[applied]
            medium[offset : offset + _SECTOR] = left[:_SECTOR]
        content, faults = rx._after_power_cut(
            medium, "SVT-DOC", "/doc.txt", tmp_path, jbd2_toolchain
        )
        expected = SECOND if applied >= published else FIRST
        if not faults and content != expected:
            faults.append(
                f"/doc.txt is {rx._file_record(content)}, expected "
                f"{rx._file_record(expected)}"
            )
        label = f"after {applied} of {len(writes)} writes"
        if torn:
            label += " and the first sector of the next"
        problems += [f"{label}: {fault}" for fault in faults]
        gc.collect()
    assert not problems, "\n".join(problems)
