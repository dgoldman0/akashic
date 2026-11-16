#!/usr/bin/env python3
"""Checked replacement on an ext4 volume: publication by one rename.

ext4's staged-write binding declares VFS-CAP-DURABLE-MUTATIONS, so
VREPL-REPLACE writes its stage, reads it back and renames it over the target,
with no marker, no backup and no VFS-SYNC.  These tests run that save on the
64 MiB fixture volume, which carries a 2 KiB /doc.txt written by the pinned
debugfs, and judge the result twice: by what the driver serves afterwards,
and by the pinned e2fsck and debugfs on the medium the machine left.

The power-cut tests record every block one save writes, rebuild the medium
as it stood after a write, and mount that medium in a fresh machine.  The
mount recovers the journal, VREPL-RECOVER settles what the save left, and
the target must then hold all of the old bytes or all of the new ones, with
no companion file beside it and a clean e2fsck.  A cut state takes whole
writes in the order the driver issued them.  It does not model a device
that reorders or loses writes it has acknowledged, nor a block torn between
its two sectors, which the journal tests of test_vfs_ext4.py cover.

A 2 KiB save over a 2 KiB file makes 112 writes in five journal
transactions.  Judging one cut costs a mount and whatever the cut left to
do, a journal to replay or a stage to remove: 2 to 16 seconds, and 17
minutes for all 113 cuts.  An ordinary run therefore cuts on either side of
every commit block and after every eighth write, 24 cuts in 3.5 minutes,
and AKASHIC_SAVE_CUT_STRIDE=1 in the environment cuts after every write.

test_vfs_replace.py covers the routine's ordering, error propagation and
recovery decisions on the RAM binding.  This file reuses the ext4 harness
of test_vfs_ext4.py by import and adds nothing to that unit.
"""

from __future__ import annotations

import gc
import mmap
import os
import re
import subprocess
import sys
import zlib
from pathlib import Path

import pytest

LOCAL_TESTING = Path(__file__).resolve().parent
if str(LOCAL_TESTING) not in sys.path:
    sys.path.insert(0, str(LOCAL_TESTING))

import machine_backends  # noqa: E402
import test_vfs_ext4 as ext4  # noqa: E402
from devices import STORAGE_CMD_FLUSH, STORAGE_CMD_WRITE  # noqa: E402
from forth_dependencies import dependency_order  # noqa: E402
from machine_backends import Printed  # noqa: E402
from native_forth import module_source  # noqa: E402
from test_vfs_ext4 import (  # noqa: E402,F401  (pytest fixtures)
    canonical_images,
    jbd2_toolchain,
)

fat = ext4.fat_harness

REPLACE_MODULE = "utils/fs/vfs-replace.f"
SECTOR = 512
BLOCK = 1024
DOC_BYTES = 2048
WRITE_CLOCK_EPOCH_MS = 3_000_000_123_456
# One interpreted line runs at most one save, one recovery or one mount.
# The longest measured line is the 64 KiB save, 230 million instructions.
LINE_MAX_STEPS = 600_000_000
LOAD_MAX_STEPS = 400_000_000
# The power-cut tests cut after every CUT_STRIDE-th write of the save, and
# on either side of every commit block whatever the stride.
CUT_STRIDE = int(os.environ.get("AKASHIC_SAVE_CUT_STRIDE", "8"))
if CUT_STRIDE < 1:
    raise RuntimeError("AKASHIC_SAVE_CUT_STRIDE must be 1 or more")
# The journal transactions of a save over an existing file, in order.  The
# third is the rename; the last two drain the old file from the orphan file,
# a release pass and the deletion.
SAVE_TRANSACTIONS = (
    "stage-create", "stage-write", "rename", "victim-release", "victim-delete",
)
RENAME_TRANSACTION = 2

VREPL_S_OK = 0
VREPL_S_IO = 4


def pattern(seed: int, length: int) -> bytes:
    """The bytes the guest's SVT-FILL writes: each byte follows its place."""
    return bytes((seed + 13 * index) % 251 for index in range(length))


OLD_SEED = 7
NEW_SEED = 101
OLD_DOC = pattern(OLD_SEED, DOC_BYTES)


# Words the journeys run.  Each reporting word prints one bracketed record,
# such as "[save 0 ]", which the echo of the line that called it cannot
# contain.
_GUEST_WORDS = (
    "VARIABLE SVT-V VARIABLE SVT-CLOCK VARIABLE SVT-WRITER",
    "VARIABLE SVT-FD VARIABLE SVT-HELD",
    "CREATE SVT-DOC VREPL-SIZE ALLOT CREATE SVT-NEW VREPL-SIZE ALLOT",
    "CREATE SVT-DATA 65536 ALLOT CREATE SVT-BACK 65536 ALLOT",
    f": SVT-NOW DROP 1 SVT-CLOCK +! {WRITE_CLOCK_EPOCH_MS} SVT-CLOCK @ + 0 ;",
    ": SVT-MOUNT T-ARENA T-VOLUME EXT4-STAGED-WRITE-NEW SWAP SVT-V ! ;",
    ": SVT-BIND ['] SVT-NOW 0 SVT-V @ EXT4-BIND-WRITE-CLOCK? ?DUP IF EXIT THEN",
    "  16 16 2 SVT-V @ EXT4-WRITER-WORKSPACE-BYTES? ?DUP IF NIP EXIT THEN",
    "  A-XMEM ARENA-NEW THROW SVT-WRITER !",
    "  SVT-WRITER @ 16 16 2 SVT-V @ EXT4-BIND-WRITER-ARENA? ?DUP IF EXIT THEN",
    "  SVT-V @ VFS-USE 0 ;",
    ": SVT-INIT SVT-V @ SVT-DOC VREPL-INIT ?DUP IF EXIT THEN",
    '  S" /doc.txt" SVT-DOC VREPL-DERIVE-PATHS! ?DUP IF EXIT THEN',
    "  SVT-V @ SVT-NEW VREPL-INIT ?DUP IF EXIT THEN",
    '  S" /new.txt" SVT-NEW VREPL-DERIVE-PATHS! ;',
    ': SVT-UP SVT-MOUNT DUP IF ." [up " . ." -1 -1 ]" EXIT THEN DROP',
    '  SVT-BIND DUP IF ." [up 0 " . ." -1 ]" EXIT THEN DROP',
    '  SVT-INIT ." [up 0 0 " . ." ]" ;',
    ': SVT-DOWN 0 SVT-V @ VFS-UNMOUNT ." [down " . ." ]" ;',
    ": SVT-FILL 0 DO DUP I 13 * + 251 MOD SVT-DATA I + C! LOOP DROP ;",
    ': SVT-SAVE SVT-DATA ROT ROT VREPL-REPLACE ." [save " . ." ]" ;',
    ': SVT-RECOVER VREPL-RECOVER ." [recover " . ." ]" ;',
    ': SVT-FILE VFS-OPEN DUP 0= IF DROP ." [file absent ]" EXIT THEN SVT-FD !',
    "  SVT-FD @ VFS-SIZE DUP 65536 > IF",
    '    DROP SVT-FD @ VFS-CLOSE ." [file oversize ]" EXIT THEN',
    "  DUP IF SVT-BACK OVER SVT-FD @ VFS-READ-EXACT IF",
    '    DROP SVT-FD @ VFS-CLOSE ." [file unreadable ]" EXIT THEN THEN',
    '  SVT-FD @ VFS-CLOSE ." [file " DUP . SVT-BACK SWAP CRC32 . ." ]" ;',
    ": SVT-PRESENT VFS-RP-NOFOLLOW-FINAL SVT-V @ VFS-RESOLVE-POLICY?",
    "  DUP IF NIP VFS-IOR-REASON VFS-R-NOENT = IF 0 ELSE 7 THEN . EXIT THEN",
    "  DROP 0<> . ;",
    ': SVT-COMPANIONS ." [companions " DUP VREPL-STAGE$ SVT-PRESENT',
    '  DUP VREPL-BACKUP$ SVT-PRESENT VREPL-MARKER$ SVT-PRESENT ." ]" ;',
    ': SVT-HOLD VFS-OPEN DUP SVT-HELD ! ." [hold " 0<> . ." ]" ;',
    ": SVT-HELD-READ SVT-HELD @ VFS-REWIND",
    "  SVT-BACK SVT-HELD @ VFS-SIZE SVT-HELD @ VFS-READ",
    '  ." [held " DUP . SVT-BACK SWAP CRC32 . ." ]" ;',
    ': SVT-RELEASE SVT-HELD @ VFS-CLOSE? ." [release " . ." ]" ;',
    ': SVT-SYNC SVT-V @ VFS-SYNC ." [sync " . ." ]" ;',
    ': SVT-LAST ." [last " SVT-V @ V.LAST-IOR @ . ." ]" ;',
    ': SVT-ORPHANS ." [orphans "',
    '  SVT-V @ _EXT4-CTX _EXT4-C.O.ACTIVE + @ . ." ]" ;',
)

_snapshot = None


def _replace_stage_modules() -> tuple[str, ...]:
    """vfs-replace.f and what it requires beyond the ext4 snapshot."""
    staged = set(dependency_order(ext4.AKASHIC_ROOT, (ext4.EXT4_MODULE,)))
    staged.update(
        Path(path).relative_to(ext4.AKASHIC_ROOT).as_posix()
        for path in (
            fat.EVENT_F, fat.SEM_F, fat.GUARD_F, fat.UTF8_F,
            fat.UINT_RANGE_F, fat.MEMORY_SPAN_F, fat.VFS_F,
        )
    )
    return tuple(
        module
        for module in dependency_order(ext4.AKASHIC_ROOT, (REPLACE_MODULE,))
        if module not in staged
    )


def build_snapshot():
    """Extend the ext4 snapshot with vfs-replace.f and the journey words."""
    global _snapshot
    if _snapshot is not None:
        return _snapshot
    base = ext4.build_snapshot()
    restored = ext4.EmulatorJourneys(base)
    system, uart = restored.system, restored.sent
    lines = [*ext4._EXT4_SOURCE_JIT_BEGIN]
    for module in _replace_stage_modules():
        lines += fat._load_forth_lines(str(ext4.AKASHIC_ROOT / module))
    lines += [*_GUEST_WORDS, *ext4._EXT4_SOURCE_JIT_END]
    lines.append('." SAVE-WORDS-READY"')
    assert all(len(line.encode()) <= 255 for line in lines)
    steps = ext4._feed_until_idle(
        system, ("\n".join(lines) + "\n").encode(), LOAD_MAX_STEPS
    )
    output = fat.uart_text(uart)
    ext4._assert_no_forth_diagnostics(output)
    assert "\r\nSAVE-WORDS-READY ok\r\n" in output, (
        f"vfs-replace.f did not load in {steps:,}/{LOAD_MAX_STEPS:,} steps:\n"
        + output[-4000:]
    )
    _snapshot = (
        base[0],
        bytes(system.cpu.mem),
        fat.save_cpu_state(system.cpu),
        bytes(system._ext_mem),
    )
    return _snapshot


_RECORD = re.compile(r"\[(\w+)((?: [-\w]+)*) \]")


def save_sources() -> tuple[tuple[str, bytes], ...]:
    """What the save snapshot adds to the ext4 snapshot, as sources the
    simulator evaluates: vfs-replace.f's closure and the journey words."""
    return tuple(
        (module, module_source(ext4.AKASHIC_ROOT / module))
        for module in _replace_stage_modules()
    ) + (("save words", ("\n".join(_GUEST_WORDS) + "\n").encode()),)


class _Recorder:
    """What the device under a Machine did, recorded where the machine runs:
    every write with the bytes it replaced and the bytes it left, the
    flushes, and every request admitted."""

    def __init__(self, media, misread: bytes | None) -> None:
        self.media = media
        self.misread = misread
        self.writes: list[tuple[int, bytes, bytes]] = []
        self.flushes = 0
        self.requests: list[tuple[int, int, int]] = []
        self._pending: tuple[int, bytes] | None = None

    def admitted(self, command: int, lba: int, count: int) -> None:
        self.settle()
        if command == STORAGE_CMD_WRITE:
            offset, size = lba * SECTOR, count * SECTOR
            self._pending = (offset, bytes(self.media[offset : offset + size]))
        elif command == STORAGE_CMD_FLUSH:
            self.flushes += 1
        self.requests.append((command, lba, count))

    def settle(self) -> None:
        """Log the write the device has finished since the last command."""
        if self._pending is None:
            return
        offset, old = self._pending
        self._pending = None
        new = bytes(self.media[offset : offset + len(old)])
        self.writes.append((offset, old, new))
        # A medium that hands back another byte than the one written to it.
        if self.misread is not None and new == self.misread:
            self.media[offset] ^= 0x01


class _MachineSide:
    """A save-test machine and its recorder, in the process that runs it:
    this one for the emulator, a clone of it for the simulator."""

    def __init__(self, backend: str, media, misread: bytes | None) -> None:
        if backend == "emulator":
            self.machine = ext4.EmulatorJourneys(build_snapshot())
        else:
            self.machine = ext4.SimulatorJourneys(save_sources())
        self.recorder = _Recorder(media, misread)
        self.machine.attach(media, None)
        self.machine.storage.observe(self.recorder.admitted)
        self._reported = (0, 0)

    def line(self, text: str, budget: int):
        """Run TEXT; return what it printed, the steps, and the writes,
        flush count and requests since the last line."""
        output, steps = self.machine.feed([text], budget)
        self.recorder.settle()
        writes, requests = self._reported
        recorder = self.recorder
        self._reported = (len(recorder.writes), len(recorder.requests))
        return (
            (output.lines, output.complete), steps,
            recorder.writes[writes:], recorder.flushes,
            recorder.requests[requests:],
        )

    def release(self) -> None:
        self.machine.release()


class Machine:
    """One machine on private media that records each block it writes.

    ``writes`` holds, in device order, the byte offset of every write with
    the bytes it replaced and the bytes it left.  A guest flush writes no
    host file: the medium is ``media`` alone.  On the emulator that is the
    caller's bytearray; the simulator runs on a clone of this process, so
    its medium is a shared mapping that both processes see, holding the
    caller's bytes.
    """

    def __init__(
        self,
        media: bytearray,
        *,
        misread: bytes | None = None,
        backend: str | None = None,
    ):
        self.backend = machine_backends.chosen(backend)
        self.writes: list[tuple[int, bytes, bytes]] = []
        self.flushes = 0
        self.steps = 0
        self._watchers = []
        if self.backend == "emulator":
            self.media = media
            self._side = _MachineSide("emulator", media, misread)
            self._clone = None
        else:
            # The clone starts from the machine this process loaded.
            ext4.loaded_simulator(save_sources())
            shared = mmap.mmap(-1, len(media))
            shared[:] = media
            self.media = shared
            self._side = None
            self._clone = machine_backends.Clone(
                lambda: _MachineSide("simulator", shared, misread)
            )

    def watch(self, watcher) -> None:
        """Call WATCHER with the command, LBA and count of every request
        the device admits from now on, after the line that made it."""
        self._watchers.append(watcher)

    def line(self, text: str) -> dict[str, list[list[str]]]:
        """Run one interpreted line and return the records it printed."""
        budget = machine_backends.budget(LINE_MAX_STEPS, self.backend)
        if self._clone is None:
            answer = self._side.line(text, budget)
        else:
            answer = self._clone.call("line", text, budget)
        printed, steps, writes, flushes, requests = answer
        output = Printed(*printed)
        self.steps += steps
        self.writes.extend(writes)
        self.flushes = flushes
        for request in requests:
            for watcher in self._watchers:
                watcher(*request)
        ext4._assert_no_forth_diagnostics(output)
        assert output.complete and output.complete[-1], (
            f"line {text!r} did not run to its end:\n{output[-2000:]}"
        )
        records: dict[str, list[list[str]]] = {}
        for tag, values in _RECORD.findall(output):
            records.setdefault(tag, []).append(values.split())
        return records

    def close(self) -> None:
        """Let go of the machine.  Its device hooks and the machine refer to
        each other, so on the emulator the memory it holds waits for a
        collection; the simulator's clone ends."""
        if self._clone is not None:
            self._clone.close()
            self._clone = None
        if self._side is not None:
            self._side.release()
            self._side = None
            gc.collect()

    def one(self, text: str, tag: str) -> list[str]:
        """The single TAG record that line TEXT prints."""
        records = self.line(text)
        assert len(records.get(tag, ())) == 1, (text, tag, records)
        return records[tag][0]

    def up(self) -> list[int]:
        """Mount, bind the clock and a 16/16/2 writer, set up both saves."""
        return [int(value) for value in self.one("SVT-UP", "up")]


def _file_record(content: bytes | None) -> list[str]:
    """What SVT-FILE prints for a file holding CONTENT."""
    if content is None:
        return ["absent"]
    return [str(len(content)), str(zlib.crc32(content))]


def _host_view(
    media: bytearray, folder: Path, toolchain: dict[str, object]
) -> dict[str, bytes]:
    """The root's regular files as the pinned debugfs reads them from MEDIA,
    once the pinned e2fsck has found the volume clean."""
    debugfs = toolchain["debugfs"]
    env = toolchain["env"]
    image = folder / "left.img"
    ext4._write_sparse_bytes(image, media)
    try:
        ext4._assert_e2fsck_clean(image, toolchain)
        listed = subprocess.run(
            [str(debugfs), "-R", "ls -p /", str(image)],
            env=env, capture_output=True, text=True, check=False,
        )
        assert listed.returncode == 0, listed.stdout + listed.stderr
        files: dict[str, bytes] = {}
        for row in listed.stdout.splitlines():
            fields = row.split("/")
            # /inode/mode/uid/gid/name/size/ ; mode 100xxx is a regular file
            if len(fields) < 7 or not fields[2].startswith("100"):
                continue
            name = fields[5]
            if name not in ("doc.txt", "new.txt") and name[:3] not in (
                ".s-", ".b-", ".m-"
            ):
                continue
            files[name] = ext4._general_write_cat(image, f"/{name}", toolchain)
        return files
    finally:
        image.unlink(missing_ok=True)


@pytest.fixture(autouse=True)
def _collect_machines():
    """Free each test's machines before the next test builds its own."""
    yield
    gc.collect()


@pytest.fixture(scope="session")
def document_volume(
    canonical_images: dict[str, Path],
    jbd2_toolchain: dict[str, object],
    tmp_path_factory: pytest.TempPathFactory,
) -> bytes:
    """The 64 MiB fixture volume with a 2 KiB /doc.txt, as its bytes."""
    folder = tmp_path_factory.mktemp("save-volume")
    image = folder / "volume.img"
    content = folder / "doc.bin"
    content.write_bytes(OLD_DOC)
    content.chmod(0o644)
    ext4._copy_sparse_file(canonical_images["primary-1k-i256"], image)
    written = subprocess.run(
        [str(jbd2_toolchain["debugfs"]), "-w", "-R",
         f"write {content} /doc.txt", str(image)],
        env=jbd2_toolchain["env"], capture_output=True, text=True, check=False,
    )
    assert written.returncode == 0, written.stdout + written.stderr
    ext4._assert_e2fsck_clean(image, jbd2_toolchain)
    volume = image.read_bytes()
    image.unlink()
    return volume


def _saved(
    volume: bytes, replacement: str, seed: int, length: int,
    *, misread: bytes | None = None,
) -> tuple[Machine, int, int]:
    """Mount VOLUME and run one save.  Returns the machine, the save's
    status and the index in ``writes`` at which the save began."""
    machine = Machine(bytearray(volume), misread=misread)
    assert machine.up() == [0, 0, 0]
    machine.line(f"{seed} {length} SVT-FILL")
    first = len(machine.writes)
    status = int(machine.one(f"{length} {replacement} SVT-SAVE", "save")[0])
    return machine, status, first


@pytest.mark.parametrize("length", (2048, 65536), ids=("2k", "64k"))
def test_save_renames_new_content_over_an_existing_file(
    document_volume: bytes,
    jbd2_toolchain: dict[str, object],
    tmp_path: Path,
    length: int,
) -> None:
    new = pattern(NEW_SEED, length)
    machine, status, first = _saved(document_volume, "SVT-DOC", NEW_SEED, length)
    assert status == VREPL_S_OK
    assert first == 0, "mounting and binding wrote to the volume"
    assert machine.one('S" /doc.txt" SVT-FILE', "file") == _file_record(new)
    assert machine.one("SVT-DOC SVT-COMPANIONS", "companions") == ["0"] * 3
    assert machine.one("SVT-ORPHANS", "orphans") == ["0"]
    assert machine.one("SVT-DOWN", "down") == ["0"]
    assert _host_view(machine.media, tmp_path, jbd2_toolchain) == {
        "doc.txt": new
    }


def test_save_creates_an_absent_file(
    document_volume: bytes,
    jbd2_toolchain: dict[str, object],
    tmp_path: Path,
) -> None:
    new = pattern(NEW_SEED, 2048)
    machine, status, _ = _saved(document_volume, "SVT-NEW", NEW_SEED, 2048)
    assert status == VREPL_S_OK
    assert machine.one('S" /new.txt" SVT-FILE', "file") == _file_record(new)
    assert machine.one("SVT-NEW SVT-COMPANIONS", "companions") == ["0"] * 3
    assert machine.one("SVT-DOWN", "down") == ["0"]
    assert _host_view(machine.media, tmp_path, jbd2_toolchain) == {
        "doc.txt": OLD_DOC, "new.txt": new
    }


def test_failed_read_back_leaves_the_target_untouched(
    document_volume: bytes,
    jbd2_toolchain: dict[str, object],
    tmp_path: Path,
) -> None:
    # The medium returns one changed byte of the stage's first block.  File
    # data carries no checksum, so only the read-back can see it.
    new = pattern(NEW_SEED, 2048)
    machine, status, first = _saved(
        document_volume, "SVT-DOC", NEW_SEED, 2048, misread=new[:BLOCK]
    )
    assert any(left == new[:BLOCK] for _, _, left in machine.writes[first:])
    assert status == VREPL_S_IO
    assert machine.one('S" /doc.txt" SVT-FILE', "file") == _file_record(OLD_DOC)
    assert machine.one("SVT-DOC SVT-COMPANIONS", "companions") == ["0"] * 3
    assert machine.one("SVT-DOWN", "down") == ["0"]
    assert _host_view(machine.media, tmp_path, jbd2_toolchain) == {
        "doc.txt": OLD_DOC
    }


def _is_commit_block(block: bytes) -> bool:
    """A JBD2 commit block, as the journal writer leaves it."""
    return block[:4] == b"\xc0\x3b\x39\x98" and block[4:8] == b"\0\0\0\2"


def _after_power_cut(
    media: bytearray,
    replacement: str,
    path: str,
    folder: Path,
    toolchain: dict[str, object],
) -> tuple[bytes | None, list[str]]:
    """Mount MEDIA as a power cut left it, recover, and report the target
    the driver serves with everything that is wrong with the result."""
    name = path.lstrip("/")
    faults: list[str] = []
    machine = Machine(media)
    try:
        up = machine.up()
        if up != [0, 0, 0]:
            return None, [f"mount, bind, init returned {up}"]
        status = machine.one(f"{replacement} SVT-RECOVER", "recover")
        if status != [str(VREPL_S_OK)]:
            faults.append(f"VREPL-RECOVER returned {status}")
        served = machine.one(f'S" {path}" SVT-FILE', "file")
        companions = machine.one(
            f"{replacement} SVT-COMPANIONS", "companions"
        )
        if companions != ["0"] * 3:
            faults.append(f"stage, backup, marker present: {companions}")
        down = machine.one("SVT-DOWN", "down")
        if down != ["0"]:
            faults.append(f"unmount returned {down}")
        files = _host_view(machine.media, folder, toolchain)
    except AssertionError as error:
        return None, faults + [f"journey or host check: {str(error)[-600:]}"]
    finally:
        machine.close()
    extra = sorted(set(files) - {"doc.txt", "new.txt"})
    if extra:
        faults.append(f"companions on the medium: {extra}")
    content = files.get(name)
    if served != _file_record(content):
        faults.append(f"driver serves {served}, the medium holds "
                      f"{_file_record(content)}")
    return content, faults


def _recorded_save(
    volume: bytes, replacement: str
) -> tuple[list[tuple[int, bytes, bytes]], list[int]]:
    """Run one 2 KiB save on VOLUME.  Returns every write it made and, for
    each commit block among them, the number of writes up to and including
    it."""
    machine, status, first = _saved(volume, replacement, NEW_SEED, 2048)
    assert status == VREPL_S_OK and first == 0
    writes = machine.writes
    machine.close()
    assert all(len(left) == BLOCK for _, _, left in writes)
    commits = [index + 1 for index, (_, _, left) in enumerate(writes)
               if _is_commit_block(left)]
    return writes, commits


def _cut_points(count: int, commits: list[int], stride: int | None) -> list[int]:
    """Where to cut a save of COUNT writes: before its first write, after
    its last, on either side of every commit block, and after every
    STRIDE-th write."""
    cuts = {0, count}
    for commit in commits:
        cuts.update((commit - 1, commit))
    if stride:
        cuts.update(range(0, count + 1, stride))
    return sorted(cuts)


def _judge_cuts(
    volume: bytes,
    writes: list[tuple[int, bytes, bytes]],
    cuts: list[int],
    published_at: int,
    replacement: str,
    path: str,
    before: bytes | None,
    folder: Path,
    toolchain: dict[str, object],
) -> None:
    """Require, for a power cut after each of CUTS writes, the target as it
    was BEFORE the save while the cut precedes write PUBLISHED_AT, and the
    new content from that write on."""
    new = pattern(NEW_SEED, 2048)
    medium = bytearray(volume)
    applied = 0
    problems: list[str] = []
    for cut in cuts:
        for offset, _, left in writes[applied:cut]:
            medium[offset : offset + len(left)] = left
        applied = cut
        content, faults = _after_power_cut(
            bytearray(medium), replacement, path, folder, toolchain
        )
        expected = new if cut >= published_at else before
        if not faults and content != expected:
            faults.append(
                f"target is {_file_record(content)}, expected "
                f"{_file_record(expected)}"
            )
        problems += [f"after write {cut} of {len(writes)}: {fault}"
                     for fault in faults]
    assert not problems, "\n".join(problems)


@pytest.fixture(scope="session")
def recorded_save(
    document_volume: bytes,
) -> tuple[list[tuple[int, bytes, bytes]], list[int]]:
    """The writes and commit blocks of one 2 KiB save over /doc.txt."""
    writes, commits = _recorded_save(document_volume, "SVT-DOC")
    assert len(commits) == len(SAVE_TRANSACTIONS), (
        "a save over an existing file no longer takes the transactions "
        f"{SAVE_TRANSACTIONS}: commit blocks follow writes {commits}"
    )
    return writes, commits


@pytest.mark.parametrize(
    "transaction", range(len(SAVE_TRANSACTIONS)), ids=SAVE_TRANSACTIONS
)
def test_power_cut_during_a_save_leaves_the_old_or_the_new_file_whole(
    document_volume: bytes,
    recorded_save: tuple[list[tuple[int, bytes, bytes]], list[int]],
    jbd2_toolchain: dict[str, object],
    tmp_path: Path,
    transaction: int,
) -> None:
    """Cut the power during one journal transaction of a save.

    A transaction's cuts run from the one just after the commit block of
    the transaction before it to the one just before its own commit block,
    and the last transaction's run on to the save's last write.  The cut
    that first holds the rename's commit block therefore opens the
    transaction after the rename.  That commit block publishes the save:
    every earlier cut leaves the old file and every later one the new.
    """
    writes, commits = recorded_save
    first = commits[transaction - 1] if transaction else 0
    last = (commits[transaction] - 1 if transaction + 1 < len(commits)
            else len(writes))
    cuts = [cut for cut in _cut_points(len(writes), commits, CUT_STRIDE)
            if first <= cut <= last]
    assert cuts and cuts[0] == first and cuts[-1] == last
    _judge_cuts(
        document_volume, writes, cuts, commits[RENAME_TRANSACTION],
        "SVT-DOC", "/doc.txt", OLD_DOC, tmp_path, jbd2_toolchain,
    )


def test_power_cut_during_a_first_save_leaves_no_file_or_the_new_one(
    document_volume: bytes,
    jbd2_toolchain: dict[str, object],
    tmp_path: Path,
) -> None:
    # A first save has no target to keep and no victim to free: it creates
    # the stage, writes it and renames it.  Until the rename's commit block
    # a cut leaves a stage alone, which recovery removes.  The cuts fall on
    # either side of each commit block.
    writes, commits = _recorded_save(document_volume, "SVT-NEW")
    assert len(commits) == RENAME_TRANSACTION + 1, commits
    _judge_cuts(
        document_volume, writes, _cut_points(len(writes), commits, None),
        commits[RENAME_TRANSACTION], "SVT-NEW", "/new.txt", None,
        tmp_path, jbd2_toolchain,
    )


def test_save_over_a_target_held_open_elsewhere(
    document_volume: bytes,
    jbd2_toolchain: dict[str, object],
    tmp_path: Path,
) -> None:
    """Saves go on while another descriptor holds an old target open.

    Each save lands, and the descriptor keeps reading the bytes it opened.
    The first save's rename takes the open file as its victim, whose storage
    waits in the orphan file until the descriptor closes.  The second save
    renames over the first one's file, which nothing holds, so that victim
    drains at once beside the record the open file keeps.  A sync lands the
    journal with the record in place, and the close drains it.
    """
    first = pattern(NEW_SEED, 2048)
    second = pattern(NEW_SEED + 1, 2048)
    third = pattern(NEW_SEED + 2, 2048)
    machine = Machine(bytearray(document_volume))
    assert machine.up() == [0, 0, 0]
    assert machine.one('S" /doc.txt" SVT-HOLD', "hold") == ["-1"]

    machine.line(f"{NEW_SEED} 2048 SVT-FILL")
    assert machine.one("2048 SVT-DOC SVT-SAVE", "save") == [str(VREPL_S_OK)]
    assert machine.one('S" /doc.txt" SVT-FILE', "file") == _file_record(first)
    assert machine.one("SVT-HELD-READ", "held") == _file_record(OLD_DOC)
    assert machine.one("SVT-ORPHANS", "orphans") == ["1"]

    machine.line(f"{NEW_SEED + 1} 2048 SVT-FILL")
    assert machine.one("2048 SVT-DOC SVT-SAVE", "save") == [str(VREPL_S_OK)]
    assert machine.one('S" /doc.txt" SVT-FILE', "file") == _file_record(second)
    assert machine.one("SVT-DOC SVT-COMPANIONS", "companions") == ["0"] * 3
    assert machine.one("SVT-HELD-READ", "held") == _file_record(OLD_DOC)
    assert machine.one("SVT-ORPHANS", "orphans") == ["1"]
    assert machine.one("SVT-SYNC", "sync") == ["0"]
    assert machine.one("SVT-ORPHANS", "orphans") == ["1"]

    # The close drains the record, and the next save goes on as before.
    assert machine.one("SVT-RELEASE", "release") == ["0"]
    assert machine.one("SVT-ORPHANS", "orphans") == ["0"]
    machine.line(f"{NEW_SEED + 2} 2048 SVT-FILL")
    assert machine.one("2048 SVT-DOC SVT-SAVE", "save") == [str(VREPL_S_OK)]
    assert machine.one('S" /doc.txt" SVT-FILE', "file") == _file_record(third)
    assert machine.one("SVT-DOC SVT-COMPANIONS", "companions") == ["0"] * 3
    assert machine.one("SVT-DOWN", "down") == ["0"]
    assert _host_view(machine.media, tmp_path, jbd2_toolchain) == {
        "doc.txt": third
    }
