#!/usr/bin/env python3
"""Copying and moving files to and from an ext4 volume.

VFS-COPY writes a stage in the destination folder, syncs, reads it back
against the source and renames it to the final name, which on ext4's
staged-write binding is one journal transaction.  These tests run copies
and moves between the 64 MiB fixture volume and a RAM volume in the same
machine, and within the ext4 volume, and judge the result twice: by what
the driver serves afterwards, and by the pinned e2fsck and debugfs on the
medium the machine left.

One test fills the volume until a few dozen blocks are free, so a copy
runs out of space midway; the stage goes, its blocks come back, and the
volume stays clean.  test_vfs_copy.py covers the protocol's failures on
RAM bindings that fail on demand, and the MP64FS boot volume.  This file
reuses the ext4 harness of test_vfs_ext4.py by import and adds nothing to
that unit.  Power cuts during a copy belong to the killed-run qualification
(docs/utils/fs/places.md, order of work, item 8).
"""

from __future__ import annotations

import gc
import mmap
import re
import struct
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
from forth_dependencies import dependency_order  # noqa: E402
from machine_backends import Printed  # noqa: E402
from native_forth import module_source  # noqa: E402
from test_vfs_ext4 import (  # noqa: E402,F401  (pytest fixtures)
    canonical_images,
    jbd2_toolchain,
)

fat = ext4.fat_harness

COPY_MODULE = "utils/fs/vfs-copy.f"
WRITE_CLOCK_EPOCH_MS = 3_000_000_123_456
# One interpreted line runs at most one copy, mount or unmount.  A 40 KiB
# copy writes, syncs, reads back and renames; a 4 KiB scratch makes it ten
# writes and twenty comparisons.
LINE_MAX_STEPS = 1_500_000_000
LOAD_MAX_STEPS = 400_000_000
NOSPC = 8
EXISTS = 3


def pattern(seed: int, length: int) -> bytes:
    """The bytes CPX-FILL writes: each byte follows its place."""
    return bytes((seed + 13 * index) % 251 for index in range(length))


DOC = pattern(7, 2048)

# Words the journeys run.  Each reporting word prints one bracketed record,
# such as "[copy 0 0 ]", which the echo of the line that called it cannot
# contain.
_GUEST_WORDS = (
    "VARIABLE CPX-V VARIABLE CPX-R VARIABLE CPX-CLOCK VARIABLE CPX-WRITER",
    "VARIABLE CPX-FD VARIABLE CPX-N",
    "CREATE CPX-SCR 4096 ALLOT CREATE CPX-DATA 65536 ALLOT",
    "CREATE CPX-BACK 65536 ALLOT",
    "CREATE CPX-REC VCOPY-SIZE ALLOT CREATE CPX-REPL VREPL-SIZE ALLOT",
    f": CPX-NOW DROP 1 CPX-CLOCK +! {WRITE_CLOCK_EPOCH_MS} CPX-CLOCK @ + 0 ;",
    ": CPX-MOUNT T-ARENA T-VOLUME EXT4-STAGED-WRITE-NEW SWAP CPX-V ! ;",
    ": CPX-BIND ['] CPX-NOW 0 CPX-V @ EXT4-BIND-WRITE-CLOCK? ?DUP IF EXIT THEN",
    "  16 16 2 CPX-V @ EXT4-WRITER-WORKSPACE-BYTES? ?DUP IF NIP EXIT THEN",
    "  A-XMEM ARENA-NEW THROW CPX-WRITER !",
    "  CPX-WRITER @ 16 16 2 CPX-V @ EXT4-BIND-WRITER-ARENA? ?DUP IF EXIT THEN",
    "  0 ;",
    ": CPX-RAM 1048576 A-XMEM ARENA-NEW THROW VFS-RAM-BINDING 0 VFS-NEW THROW",
    "  CPX-R ! ;",
    ': CPX-UP CPX-MOUNT DUP IF ." [up " . ." -1 ]" EXIT THEN DROP',
    '  CPX-BIND ." [up 0 " . ." ]" CPX-RAM ;',
    ': CPX-DOWN 0 CPX-V @ VFS-UNMOUNT ." [down " . ." ]" ;',
    ": CPX-FILL 0 ?DO DUP I 13 * + 251 MOD CPX-DATA I + C! LOOP DROP ;",
    ": CPX-PUT >R 2DUP R@ VFS-CREATE 0= IF 2DROP R> 2DROP",
    '  ." [put -1 ]" EXIT THEN',
    '  VFS-FF-WRITE R> VFS-OPEN? ?DUP IF NIP NIP ." [put " . ." ]" EXIT THEN',
    "  CPX-FD ! CPX-DATA SWAP CPX-FD @ VFS-WRITE-EXACT CPX-FD @ VFS-CLOSE? OR",
    '  ." [put " . ." ]" ;',
    ': CPX-FILE >R VFS-FF-READ R> VFS-OPEN? IF DROP ." [file absent ]" EXIT THEN',
    "  CPX-FD ! CPX-FD @ VFS-SIZE DUP 65536 > IF",
    '    DROP CPX-FD @ VFS-CLOSE? DROP ." [file oversize ]" EXIT THEN',
    "  DUP IF CPX-BACK OVER CPX-FD @ VFS-READ-EXACT IF",
    '    DROP CPX-FD @ VFS-CLOSE? DROP ." [file unreadable ]" EXIT THEN THEN',
    '  CPX-FD @ VFS-CLOSE? DROP ." [file " DUP . CPX-BACK SWAP CRC32 . ." ]" ;',
    ": CPX-HAS >R VFS-RP-NOFOLLOW-FINAL R> VFS-RESOLVE-POLICY? NIP 0=",
    '  ." [has " . ." ]" ;',
    ": CPX-STAGE CPX-REPL VREPL-INIT THROW CPX-REPL VREPL-DERIVE-PATHS! THROW",
    "  CPX-REPL VREPL-STAGE$ ;",
    ": CPX-ANSWER DUP VFS-IOR-REASON . VFS-IOR-FLAGS VFS-IOR-F-PARTIAL AND 0<> . ;",
    ': CPX-COPY CPX-SCR 4096 VFS-COPY ." [copy " CPX-ANSWER ." ]" ;',
    ': CPX-MOVE CPX-SCR 4096 VFS-MOVE ." [move " CPX-ANSWER ." ]" ;',
    ": CPX-STEPS CPX-SCR 4096 CPX-REC VCOPY-INIT ?DUP IF",
    '    ." [steps 0 " CPX-ANSWER ." ]" EXIT THEN',
    "  0 CPX-N ! BEGIN CPX-REC VCOPY-STEP 1 CPX-N +!",
    "    ?DUP IF NIP -1 ELSE 0= DUP IF 0 SWAP THEN THEN UNTIL",
    '  ." [steps " CPX-N @ . CPX-ANSWER ." ]" ;',
)

_snapshot = None


def _copy_stage_modules() -> tuple[str, ...]:
    """vfs-copy.f and what it requires beyond the ext4 snapshot."""
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
        for module in dependency_order(ext4.AKASHIC_ROOT, (COPY_MODULE,))
        if module not in staged
    )


def build_snapshot():
    """Extend the emulator's ext4 snapshot with vfs-copy.f and the words."""
    global _snapshot
    if _snapshot is not None:
        return _snapshot
    base = ext4.build_snapshot()
    restored = ext4.EmulatorJourneys(base)
    system, uart = restored.system, restored.sent
    lines = [*ext4._EXT4_SOURCE_JIT_BEGIN]
    for module in _copy_stage_modules():
        lines += fat._load_forth_lines(str(ext4.AKASHIC_ROOT / module))
    lines += [*_GUEST_WORDS, *ext4._EXT4_SOURCE_JIT_END]
    lines.append('." COPY-WORDS-READY"')
    assert all(len(line.encode()) <= 255 for line in lines)
    steps = ext4._feed_until_idle(
        system, ("\n".join(lines) + "\n").encode(), LOAD_MAX_STEPS
    )
    output = fat.uart_text(uart)
    ext4._assert_no_forth_diagnostics(output)
    assert "\r\nCOPY-WORDS-READY ok\r\n" in output, (
        f"vfs-copy.f did not load in {steps:,}/{LOAD_MAX_STEPS:,} steps:\n"
        + output[-4000:]
    )
    _snapshot = (
        base[0],
        bytes(system.cpu.mem),
        fat.save_cpu_state(system.cpu),
        bytes(system._ext_mem),
    )
    return _snapshot


def copy_sources() -> tuple[tuple[str, bytes], ...]:
    """What the copy machine adds to the ext4 snapshot's sources."""
    return tuple(
        (module, module_source(ext4.AKASHIC_ROOT / module))
        for module in _copy_stage_modules()
    ) + (("copy words", ("\n".join(_GUEST_WORDS) + "\n").encode()),)


_RECORD = re.compile(r"\[(\w+)((?: [-\w]+)*) \]")


class _Side:
    """A copy machine with MEDIA attached, in the process that runs it."""

    def __init__(self, backend: str, media) -> None:
        if backend == "emulator":
            self.machine = ext4.EmulatorJourneys(build_snapshot())
        else:
            self.machine = ext4.SimulatorJourneys(copy_sources())
        self.machine.attach(media, None)

    def line(self, text: str, budget: int):
        output, steps = self.machine.feed([text], budget)
        return (output.lines, output.complete), steps

    def release(self) -> None:
        self.machine.release()


class Machine:
    """One machine on private media.  The simulator runs on a clone of
    this process, so its medium is a shared mapping both processes see."""

    def __init__(self, media: bytes, *, backend: str | None = None) -> None:
        self.backend = machine_backends.chosen(backend)
        if self.backend == "emulator":
            self.media = bytearray(media)
            self._side = _Side("emulator", self.media)
            self._clone = None
        else:
            ext4.loaded_simulator(copy_sources())
            shared = mmap.mmap(-1, len(media))
            shared[:] = media
            self.media = shared
            self._side = None
            self._clone = machine_backends.Clone(
                lambda: _Side("simulator", shared)
            )

    def line(self, text: str) -> dict[str, list[list[str]]]:
        """Run one interpreted line and return the records it printed."""
        budget = machine_backends.budget(LINE_MAX_STEPS, self.backend)
        if self._clone is None:
            printed, _ = self._side.line(text, budget)
        else:
            printed, _ = self._clone.call("line", text, budget)
        output = Printed(*printed)
        ext4._assert_no_forth_diagnostics(output)
        assert output.complete and output.complete[-1], (
            f"line {text!r} did not run to its end:\n{output[-2000:]}"
        )
        records: dict[str, list[list[str]]] = {}
        for tag, values in _RECORD.findall(output):
            records.setdefault(tag, []).append(values.split())
        return records

    def one(self, text: str, tag: str) -> list[str]:
        """The single TAG record that line TEXT prints."""
        records = self.line(text)
        assert len(records.get(tag, ())) == 1, (text, tag, records)
        return records[tag][0]

    def close(self) -> None:
        if self._clone is not None:
            self._clone.close()
            self._clone = None
        if self._side is not None:
            self._side.release()
            self._side = None
            gc.collect()


def _file_record(content: bytes) -> list[str]:
    return [str(len(content)), str(zlib.crc32(content))]


def _debugfs(image: Path, request: str, toolchain: dict[str, object]) -> str:
    ran = subprocess.run(
        [str(toolchain["debugfs"]), "-R", request, str(image)],
        env=toolchain["env"], capture_output=True, text=True, check=False,
    )
    assert ran.returncode == 0, ran.stdout + ran.stderr
    return ran.stdout


def _names(image: Path, folder: str, toolchain: dict[str, object]) -> set[str]:
    """The names in FOLDER, as the pinned debugfs lists them."""
    names = set()
    for row in _debugfs(image, f"ls -p {folder}", toolchain).splitlines():
        fields = row.split("/")
        # /inode/mode/uid/gid/name/size/
        if len(fields) >= 7 and fields[5] not in (".", ".."):
            names.add(fields[5])
    return names


def _free_blocks(image: Path) -> int:
    with image.open("rb") as source:
        source.seek(1024 + 0x0C)
        return struct.unpack("<I", source.read(4))[0]


def _left_image(media, folder: Path, toolchain: dict[str, object]) -> Path:
    """The medium the machine left, once the pinned e2fsck finds it clean."""
    image = folder / "left.img"
    ext4._write_sparse_bytes(image, media)
    ext4._assert_e2fsck_clean(image, toolchain)
    return image


def _volume(
    canonical_images: dict[str, Path],
    toolchain: dict[str, object],
    folder: Path,
    *,
    free_blocks: int | None = None,
) -> bytes:
    """The 64 MiB fixture volume with a 2 KiB /doc.txt and a folder /dir.
    With FREE_BLOCKS, a filler file takes all but about that many blocks."""
    image = folder / "volume.img"
    content = folder / "doc.bin"
    content.write_bytes(DOC)
    ext4._copy_sparse_file(canonical_images["primary-1k-i256"], image)
    _debugfs_write(image, f"write {content} /doc.txt", toolchain)
    _debugfs_write(image, "mkdir /dir", toolchain)
    if free_blocks is not None:
        filler = folder / "filler.bin"
        # Bytes other than zero, so debugfs writes every block rather than
        # leaving holes.  The filler's own extent blocks take a few more.
        filler.write_bytes(b"\xa5" * ((_free_blocks(image) - free_blocks) * 1024))
        _debugfs_write(image, f"write {filler} /filler.bin", toolchain)
        filler.unlink()
    ext4._assert_e2fsck_clean(image, toolchain)
    volume = image.read_bytes()
    image.unlink()
    content.unlink()
    return volume


def _debugfs_write(image: Path, request: str, toolchain) -> None:
    ran = subprocess.run(
        [str(toolchain["debugfs"]), "-w", "-R", request, str(image)],
        env=toolchain["env"], capture_output=True, text=True, check=False,
    )
    assert ran.returncode == 0 and "error" not in ran.stderr.lower(), (
        ran.stdout + ran.stderr
    )


@pytest.fixture(autouse=True)
def _collect_machines():
    """Free each test's machines before the next test builds its own."""
    yield
    gc.collect()


@pytest.fixture(scope="session")
def copy_volume(canonical_images, jbd2_toolchain, tmp_path_factory) -> bytes:
    return _volume(
        canonical_images, jbd2_toolchain, tmp_path_factory.mktemp("copy-volume")
    )


@pytest.fixture(scope="session")
def full_volume(canonical_images, jbd2_toolchain, tmp_path_factory) -> bytes:
    return _volume(
        canonical_images, jbd2_toolchain, tmp_path_factory.mktemp("full-volume"),
        free_blocks=40,
    )


def test_copies_and_moves_reach_ext4_and_leave_it_clean(
    copy_volume: bytes, jbd2_toolchain: dict[str, object], tmp_path: Path,
) -> None:
    machine = Machine(copy_volume)
    try:
        assert machine.one("CPX-UP", "up") == ["0", "0"]
        machine.line("41 40000 CPX-FILL")
        assert machine.one(': J1 40000 S" /in.bin" CPX-R @ CPX-PUT ; J1', "put") == ["0"]
        # RAM to ext4, ext4 to RAM, and within the ext4 volume.
        assert machine.one(
            ': J2 S" /in.bin" CPX-R @ S" /in.bin" CPX-V @ CPX-COPY ; J2', "copy"
        ) == ["0", "0"]
        assert machine.one(
            ': J3 S" /doc.txt" CPX-V @ S" /doc.txt" CPX-R @ CPX-COPY ; J3', "copy"
        ) == ["0", "0"]
        assert machine.one(': J4 S" /doc.txt" CPX-R @ CPX-FILE ; J4', "file") == (
            _file_record(DOC)
        )
        assert machine.one(
            ': J5 S" /doc.txt" CPX-V @ S" /dir/doc2.txt" CPX-V @ CPX-COPY ; J5',
            "copy",
        ) == ["0", "0"]
        assert machine.one(': J6 S" /in.bin" CPX-V @ CPX-FILE ; J6', "file") == (
            _file_record(pattern(41, 40000))
        )
        # The copy refuses a name the volume holds.
        assert machine.one(
            ': J7 S" /doc.txt" CPX-R @ S" /doc.txt" CPX-V @ CPX-COPY ; J7', "copy"
        ) == [str(EXISTS), "0"]
        # Moves: RAM to ext4, a rename inside ext4, ext4 to RAM.
        machine.line("42 3000 CPX-FILL")
        assert machine.one(': J8 3000 S" /mv.bin" CPX-R @ CPX-PUT ; J8', "put") == ["0"]
        assert machine.one(
            ': J9 S" /mv.bin" CPX-R @ S" /dir/mv.bin" CPX-V @ CPX-MOVE ; J9', "move"
        ) == ["0", "0"]
        assert machine.one(': J10 S" /mv.bin" CPX-R @ CPX-HAS ; J10', "has") == ["0"]
        assert machine.one(
            ': J11 S" /in.bin" CPX-V @ S" /dir/in2.bin" CPX-V @ CPX-MOVE ; J11',
            "move",
        ) == ["0", "0"]
        assert machine.one(
            ': J12 S" /dir/doc2.txt" CPX-V @ S" /doc2.txt" CPX-R @ CPX-MOVE ; J12',
            "move",
        ) == ["0", "0"]
        assert machine.one(': J13 S" /doc2.txt" CPX-R @ CPX-FILE ; J13', "file") == (
            _file_record(DOC)
        )
        # A stage a crash left goes when the same copy runs again.
        assert machine.one(
            ': J14 2000 S" /left.bin" CPX-V @ CPX-STAGE CPX-V @ CPX-PUT ; J14', "put"
        ) == ["0"]
        assert machine.one(
            ': J15 S" /left.bin" CPX-V @ CPX-STAGE CPX-V @ CPX-HAS ; J15', "has"
        ) == ["-1"]
        machine.line("43 6000 CPX-FILL")
        assert machine.one(': J16 6000 S" /left.bin" CPX-R @ CPX-PUT ; J16', "put") == ["0"]
        assert machine.one(
            ': J17 S" /left.bin" CPX-R @ S" /left.bin" CPX-V @ CPX-COPY ; J17',
            "copy",
        ) == ["0", "0"]
        assert machine.one(
            ': J18 S" /left.bin" CPX-V @ CPX-STAGE CPX-V @ CPX-HAS ; J18', "has"
        ) == ["0"]
        assert machine.one("CPX-DOWN", "down") == ["0"]
        image = _left_image(machine.media, tmp_path, jbd2_toolchain)
    finally:
        machine.close()

    def cat(path: str) -> bytes:
        return ext4._general_write_cat(image, path, jbd2_toolchain)

    assert cat("/doc.txt") == DOC
    assert cat("/dir/in2.bin") == pattern(41, 40000)
    assert cat("/dir/mv.bin") == pattern(42, 3000)
    assert cat("/left.bin") == pattern(43, 6000)
    # The fixture's root holds lost+found and fixture.
    assert _names(image, "/", jbd2_toolchain) == {
        "lost+found", "fixture", "doc.txt", "dir", "left.bin",
    }
    assert _names(image, "/dir", jbd2_toolchain) == {"in2.bin", "mv.bin"}


def test_folders_copy_and_move_on_ext4_and_leave_it_clean(
    copy_volume: bytes, jbd2_toolchain: dict[str, object], tmp_path: Path,
) -> None:
    """A folder of two levels, with an empty folder and a file larger than
    the scratch, copies from RAM to ext4 and within ext4, moves to another
    parent inside ext4 by one rename, and moves from ext4 back to RAM,
    which hides the source and removes it.  The medium the machine leaves
    is clean and holds the copies and no stage."""
    machine = Machine(copy_volume)
    try:
        assert machine.one("CPX-UP", "up") == ["0", "0"]
        assert machine.one(
            ': K0 S" /" CPX-R @ VFS-CD? S" tree" CPX-R @ VFS-MKDIR OR'
            ' S" /tree" CPX-R @ VFS-CD? OR ." [mk " . ." ]" ; K0', "mk"
        ) == ["0"]
        assert machine.one(
            ': K1 S" sub" CPX-R @ VFS-MKDIR S" e" CPX-R @ VFS-MKDIR OR'
            ' S" /" CPX-R @ VFS-CD? OR ." [mk " . ." ]" ; K1', "mk"
        ) == ["0"]
        machine.line("51 700 CPX-FILL")
        assert machine.one(
            ': K2 700 S" /tree/a.txt" CPX-R @ CPX-PUT ; K2', "put"
        ) == ["0"]
        machine.line("52 40000 CPX-FILL")
        assert machine.one(
            ': K3 40000 S" /tree/sub/b.bin" CPX-R @ CPX-PUT ; K3', "put"
        ) == ["0"]
        # RAM to ext4, then within ext4.
        assert machine.one(
            ': K4 S" /tree" CPX-R @ S" /tree" CPX-V @ CPX-COPY ; K4', "copy"
        ) == ["0", "0"]
        assert machine.one(
            ': K5 S" /tree" CPX-V @ S" /dir/tree2" CPX-V @ CPX-COPY ; K5', "copy"
        ) == ["0", "0"]
        # A rename to another parent inside ext4, then ext4 back to RAM.
        assert machine.one(
            ': K6 S" /dir/tree2" CPX-V @ S" /moved" CPX-V @ CPX-MOVE ; K6', "move"
        ) == ["0", "0"]
        assert machine.one(
            ': K7 S" /tree" CPX-V @ S" /back" CPX-R @ CPX-MOVE ; K7', "move"
        ) == ["0", "0"]
        assert machine.one(': K8 S" /tree" CPX-V @ CPX-HAS ; K8', "has") == ["0"]
        assert machine.one(
            ': K9 S" /back/sub/b.bin" CPX-R @ CPX-FILE ; K9', "file"
        ) == _file_record(pattern(52, 40000))
        assert machine.one(
            ': K10 S" /moved/a.txt" CPX-V @ CPX-FILE ; K10', "file"
        ) == _file_record(pattern(51, 700))
        assert machine.one("CPX-DOWN", "down") == ["0"]
        image = _left_image(machine.media, tmp_path, jbd2_toolchain)
    finally:
        machine.close()
    assert ext4._general_write_cat(image, "/moved/a.txt", jbd2_toolchain) == (
        pattern(51, 700)
    )
    assert ext4._general_write_cat(image, "/moved/sub/b.bin", jbd2_toolchain) == (
        pattern(52, 40000)
    )
    assert _names(image, "/", jbd2_toolchain) == {
        "lost+found", "fixture", "doc.txt", "dir", "moved",
    }
    assert _names(image, "/dir", jbd2_toolchain) == set()
    assert _names(image, "/moved", jbd2_toolchain) == {"a.txt", "sub", "e"}
    assert _names(image, "/moved/sub", jbd2_toolchain) == {"b.bin"}
    assert _names(image, "/moved/e", jbd2_toolchain) == set()


def test_a_copy_that_runs_out_of_space_on_ext4_gives_its_blocks_back(
    full_volume: bytes, jbd2_toolchain: dict[str, object], tmp_path: Path,
) -> None:
    """About 40 blocks are free.  A 64 KiB copy writes chunks until the
    driver answers VFS-E-NOSPC, the stage goes, and a 16 KiB copy then
    fits in the blocks the stage gave back."""
    machine = Machine(full_volume)
    try:
        assert machine.one("CPX-UP", "up") == ["0", "0"]
        machine.line("44 65536 CPX-FILL")
        assert machine.one(': J1 65536 S" /big" CPX-R @ CPX-PUT ; J1', "put") == ["0"]
        steps, reason, partial = (
            int(value) for value in machine.one(
                ': J2 S" /big" CPX-R @ S" /big" CPX-V @ CPX-STEPS ; J2', "steps"
            )
        )
        assert (reason, partial) == (NOSPC, 0)
        assert steps > 2, "the copy ran out of space before it wrote a chunk"
        assert machine.one(': J3 S" /big" CPX-V @ CPX-HAS ; J3', "has") == ["0"]
        assert machine.one(
            ': J4 S" /big" CPX-V @ CPX-STAGE CPX-V @ CPX-HAS ; J4', "has"
        ) == ["0"]
        assert machine.one(
            ': J5 16384 S" /fits" CPX-R @ CPX-PUT ; J5', "put"
        ) == ["0"]
        assert machine.one(
            ': J6 S" /fits" CPX-R @ S" /fits" CPX-V @ CPX-COPY ; J6', "copy"
        ) == ["0", "0"]
        assert machine.one("CPX-DOWN", "down") == ["0"]
        image = _left_image(machine.media, tmp_path, jbd2_toolchain)
    finally:
        machine.close()
    assert ext4._general_write_cat(image, "/fits", jbd2_toolchain) == (
        pattern(44, 16384)
    )
    assert "big" not in _names(image, "/", jbd2_toolchain)
    assert not any(
        name.startswith(".s-") for name in _names(image, "/", jbd2_toolchain)
    )
