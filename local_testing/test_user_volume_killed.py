"""Killed runs on the user volume: a power cut at each flush.

The writers of the user volume run one operation each on MegaPad's native
simulator: Pad's save through a replacement bound in a place, File
Explorer's copy of a file and of a folder and its move between places, the
Agent's first save of a conversation and a later one, and Streams
provisioning its repository.  The machine is cut at each flush in turn.  The simulator lands a write in the medium when the guest makes it,
so the medium as the first request after a flush finds it holds everything
written before that flush and nothing after: what a power cut there leaves.
A storage observer records the blocks each stretch between flushes changed,
and each cut's medium is the operation's starting medium with the stretches
up to that flush applied.

Each cut's medium then passes two recoveries.  A fresh machine mounts it,
which replays the journal, runs the operation's own recovery and finds the
state from before the operation or the one after it, whole; the host's
e2fsck then passes the medium that machine leaves.  The host's own e2fsck,
in preen mode, recovers a copy of the cut medium, after which a forced check
passes and the host's debugfs finds the same state the machine found.  Once
a cut shows the state after the operation, every later cut shows it too.

AKASHIC_KILLED_RUN_STRIDE in the environment cuts at every Nth flush
instead of every one; the cut after the last flush always runs.
"""
from __future__ import annotations

import os
import subprocess
from dataclasses import dataclass, field
from pathlib import Path
from typing import Callable

import pytest

import akashic_tui as tui
from test_user_volume import ARENA, DOCUMENT, Machine, fresh_user_volume  # noqa: F401

READ, WRITE, FLUSH = 0x01, 0x02, 0xFF
SECTOR = 512
STRIDE = max(1, int(os.environ.get("AKASHIC_KILLED_RUN_STRIDE", "1")))
V2 = b"b" * 3000

ROOTS = (
    "utils/fs/vfs-copy.f",
    "tui/applets/agent/storage/vfs-conversation.f",
)

SUITE = r"""
VARIABLE T-REC  CREATE T-SCRATCH 4096 ALLOT
CREATE T-V2 3000 ALLOT  T-V2 3000 CHAR b FILL
: T-V2$  ( -- a u )  T-V2 3000 ;
\ A writable place over the user volume's records folder, in T-SET beside
\ T-DOCS.
: T-RECORDS  ( -- )
    S" user" PLACES-VOLUME THROW
    >R S" records" S" /records" PLACE-WRITABLE R> PLACES-DECLARE THROW
    PLACE-WRITABLE SWAP T-SET @ PLSET-GRANT THROW T-REC ! ;
: T-BOTH  ( -- )  T-PLACES T-RECORDS ;
CREATE T-RB 8192 ALLOT  VARIABLE T-RFD
\ The file at PATH in PLACE read into T-RB: its length, -1 when it is
\ absent, -2 when it does not fit, -3 when it does not read.
: T-LOAD  ( path-a path-u place -- len )
    >R VFS-FF-READ R> PLACE-OPEN IF DROP -1 EXIT THEN T-RFD !
    T-RFD @ VFS-SIZE DUP 8192 > IF DROP T-RFD @ VFS-CLOSE -2 EXIT THEN
    DUP T-RB SWAP T-RFD @ VFS-READ-EXACT IF
        DROP T-RFD @ VFS-CLOSE -3 EXIT
    THEN
    T-RFD @ VFS-CLOSE ;
\ 1 when the file at PATH in PLACE holds A U, 0 when it holds other bytes,
\ -1 when it is absent.
: T-HOLDS  ( a u path-a path-u place -- n )
    T-LOAD DUP 0< IF NIP NIP EXIT THEN
    T-RB SWAP 2SWAP COMPARE 0= IF 1 ELSE 0 THEN ;
\ Settle a save the cut interrupted, as Pad does when it binds a document.
: T-RECOVER  ( path-a path-u -- status )
    T-DOCS @ -1 T-REPL PLACE-VREPL! ?DUP IF EXIT THEN
    T-REPL VREPL-RECOVER  T-REPL VREPL-FINI DROP ;
: T-DOWN  ( -- ior )  USERVOL-VFS VFS-SYNC ?DUP IF EXIT THEN
    0 USERVOL-VFS VFS-UNMOUNT ;
VARIABLE T-STORE  VARIABLE T-CONV
CREATE T-REPLY 2000 ALLOT  T-REPLY 2000 CHAR r FILL
\ The Agent's conversation store in the records place, as its home.
: T-AGENT  ( -- status )  T-REC @ AVFSSTORE-NEW SWAP T-STORE ! ;
: T-SAY  ( role a u -- ior )
    >R >R AMSG-S-COMPLETE 1 R> R> T-CONV @ ACONV-APPEND NIP ;
"""


@dataclass
class Operation:
    """One writer's operation: SETUP makes the starting medium, RUN is the
    operation the cuts interrupt, MACHINE recovers a cut on a fresh machine
    and answers 'old' or 'new', HOST answers it from a host-recovered
    image, or None where the host cannot tell."""

    name: str
    setup: list[str]
    run: list[str]
    machine: Callable[[Machine], str]
    host: Callable[[Path], str | None]
    roots: tuple[str, ...] = ROOTS
    helpers: str = SUITE
    expected: dict = field(default_factory=dict)


def _tools():
    if not os.environ.get("AKASHIC_E2FSPROGS_TOOL_DIR"):
        pytest.skip("set AKASHIC_E2FSPROGS_TOOL_DIR to build user volumes")
    manifest, env, tools = tui._system_volume_toolchain()
    return env, tools


def _host(tool: str, *args: str) -> subprocess.CompletedProcess[bytes]:
    env, tools = _tools()
    return subprocess.run(
        [tools[tool]["path"], *args], env=env, capture_output=True, check=False
    )


def _cat(image: Path, path: str) -> bytes | None:
    """The file at PATH on IMAGE, or None when it is absent."""
    result = _host("debugfs", "-R", f"cat {path}", str(image))
    if result.returncode != 0 or b"File not found" in result.stderr:
        return None
    return result.stdout


def _clean(image: Path) -> None:
    result = _host("e2fsck", "-f", "-n", str(image))
    assert result.returncode == 0, (
        result.stdout + result.stderr
    ).decode(errors="replace")[-2000:]


def _signed(*cells: int) -> tuple[int, ...]:
    """Cells the guest left, as the signed numbers Forth meant."""
    return tuple(c - (1 << 64) if c >= 1 << 63 else c for c in cells)


def _mounted(image: bytes, op: Operation) -> Machine:
    """A machine with IMAGE on the user unit, mounted, and the documents
    and records places in its set."""
    machine = Machine(image, roots=op.roots, helpers=op.helpers)
    assert machine.run(f"{ARENA} USERVOL-MOUNT") == (0,)
    assert machine.run("T-BOTH") == ()
    return machine


class Recorder:
    """The medium's durable states during one run.  At each request a
    flush's completion lets in, it keeps the sectors the writes since the
    flush before it changed, as the medium then holds them."""

    def __init__(self, service) -> None:
        self.service = service
        self.base = service.image_bytes
        self.pending: list[tuple[int, int]] = []
        self.after_flush = False
        self.stretches: list[dict[int, bytes]] = []
        self.observer = service.observe(self.admitted)

    def admitted(self, command: int, lba: int, count: int) -> None:
        if self.after_flush:
            self._keep()
        if command == WRITE:
            self.pending.append((lba, count))
        self.after_flush = command == FLUSH

    def _keep(self) -> None:
        image = self.service.image_bytes
        stretch = {}
        for lba, count in self.pending:
            for sector in range(lba, lba + count):
                stretch[sector] = image[sector * SECTOR:(sector + 1) * SECTOR]
        self.stretches.append(stretch)
        self.pending = []
        self.after_flush = False

    def finish(self) -> None:
        """End the run: the stretch its last flush closed, if no request
        came after it.  Writes after the last flush were never durable."""
        if self.after_flush:
            self._keep()
        self.service.stop_observing()

    def cuts(self):
        """Each cut's flush ordinal and medium, from before the first flush
        to after the last, every STRIDE-th, skipping cuts that change
        nothing."""
        image = bytearray(self.base)
        yield 0, bytes(image)
        last = len(self.stretches)
        for ordinal, stretch in enumerate(self.stretches, 1):
            for sector, data in stretch.items():
                image[sector * SECTOR:(sector + 1) * SECTOR] = data
            if stretch and (ordinal % STRIDE == 0 or ordinal == last):
                yield ordinal, bytes(image)


def _base(fresh: bytes, op: Operation) -> bytes:
    """The starting medium: the operation's setup on a fresh volume,
    synced and unmounted."""
    machine = _mounted(fresh, op)
    for line in op.setup:
        assert machine.run(line) == (0,), line
    assert machine.run("T-DOWN") == (0,)
    return machine.user.image_bytes


def _killed(fresh: bytes, op: Operation, tmp_path: Path) -> list[tuple[int, str]]:
    """Run OP once under the recorder, then recover each cut both ways;
    answer each cut's flush ordinal and the state it recovered to."""
    base = _base(fresh, op)
    # The recorder watches the mount too, so cuts land in it as well.
    machine = Machine(base, roots=op.roots, helpers=op.helpers)
    recorder = Recorder(machine.user)
    assert machine.run(f"{ARENA} USERVOL-MOUNT") == (0,)
    assert machine.run("T-BOTH") == ()
    for line in op.run:
        assert machine.run(line) == (0,), line
    assert machine.run("T-DOWN") == (0,)
    recorder.finish()
    assert recorder.stretches, "the operation flushed nothing"
    states = []
    for ordinal, image in recorder.cuts():
        # The machine's own recovery, then the host's check of what it left.
        own = _mounted(image, op)
        state = op.machine(own)
        assert own.run("T-DOWN") == (0,), ordinal
        remounted = tmp_path / "remounted.img"
        remounted.write_bytes(own.user.image_bytes)
        _clean(remounted)
        # The host's own recovery of the cut medium.
        cut = tmp_path / "cut.img"
        cut.write_bytes(image)
        preen = _host("e2fsck", "-f", "-p", str(cut))
        assert preen.returncode in (0, 1), (
            ordinal, (preen.stdout + preen.stderr).decode(errors="replace"),
        )
        _clean(cut)
        host = op.host(cut)
        assert host in (None, state), (op.name, ordinal, state, host)
        states.append((ordinal, state))
    remounted.unlink()
    cut.unlink()
    first_new = next((o for o, s in states if s == "new"), None)
    print(
        f"[killed] {op.name}: {len(recorder.stretches)} flushes, "
        f"{len(states)} cuts, the new state from the cut after flush "
        f"{first_new}"
    )
    return states


def _assert_all_or_nothing(states: list[tuple[int, str]]) -> None:
    order = [state for _, state in states]
    assert order[0] == "old" and order[-1] == "new", states
    first_new = order.index("new")
    assert all(state == "new" for state in order[first_new:]), states


# ---------------------------------------------------------------------
#  The operations
# ---------------------------------------------------------------------

def _save_machine(machine: Machine) -> str:
    (status,) = machine.run('S" /killed.md" T-RECOVER')
    assert status in (0, 1, 2), status        # OK, rolled back, cleaned up
    old, new = _signed(*machine.run(
        'T-DOC S" /killed.md" T-DOCS @ T-HOLDS  T-V2$ S" /killed.md" T-DOCS @ T-HOLDS'
    ))
    assert (old, new) in ((1, 0), (0, 1)), (old, new)
    return "old" if old == 1 else "new"


def _save_host(image: Path) -> str:
    content = _cat(image, "/documents/killed.md")
    assert content in (DOCUMENT.encode(), V2), content and content[:80]
    return "old" if content == DOCUMENT.encode() else "new"


PAD_SAVE = Operation(
    "Pad's save",
    setup=['T-DOC S" /killed.md" T-SAVE'],
    run=['T-V2$ S" /killed.md" T-SAVE'],
    machine=_save_machine,
    host=_save_host,
)


def _copy_machine(machine: Machine) -> str:
    source, target = _signed(*machine.run(
        'T-V2$ S" /a.md" T-DOCS @ T-HOLDS  T-V2$ S" /a.md" T-REC @ T-HOLDS'
    ))
    assert source == 1 and target in (-1, 1), (source, target)
    return "old" if target == -1 else "new"


def _copy_host(image: Path) -> str:
    assert _cat(image, "/documents/a.md") == V2
    content = _cat(image, "/records/a.md")
    assert content in (None, V2), content and content[:80]
    return "old" if content is None else "new"


FILE_COPY = Operation(
    "File Explorer's copy of a file",
    setup=['T-V2$ S" /a.md" T-SAVE'],
    run=['S" /a.md" T-DOCS @ S" /a.md" T-REC @ T-SCRATCH 4096 PLACE-COPY'],
    machine=_copy_machine,
    host=_copy_host,
)

FOLDER_FILES = ("/f/1.md", "/f/2.md", "/f/3.md")


def _folder_machine(machine: Machine) -> str:
    holds = []
    for path in FOLDER_FILES:
        source, target = _signed(*machine.run(
            f'T-V2$ S" {path}" T-DOCS @ T-HOLDS  '
            f'T-V2$ S" {path}" T-REC @ T-HOLDS'
        ))
        assert source == 1, (path, source)
        holds.append(target)
    assert holds in ([-1] * 3, [1] * 3), holds
    return "old" if holds[0] == -1 else "new"


def _folder_host(image: Path) -> str:
    targets = [_cat(image, f"/records{path}") for path in FOLDER_FILES]
    assert targets in ([None] * 3, [V2] * 3), [t and t[:20] for t in targets]
    return "old" if targets[0] is None else "new"


FOLDER_COPY = Operation(
    "File Explorer's copy of a folder",
    setup=[
        'S" /f" T-DOCS @ PLACE-MKDIR',
        *(f'T-V2$ S" {path}" T-SAVE' for path in FOLDER_FILES),
    ],
    run=['S" /f" T-DOCS @ S" /f" T-REC @ T-SCRATCH 4096 PLACE-COPY'],
    machine=_folder_machine,
    host=_folder_host,
)


def _move_machine(machine: Machine) -> str:
    source, target = _signed(*machine.run(
        'T-V2$ S" /m.md" T-DOCS @ T-HOLDS  T-V2$ S" /m.md" T-REC @ T-HOLDS'
    ))
    assert (source, target) in ((1, -1), (-1, 1)), (source, target)
    return "old" if source == 1 else "new"


def _move_host(image: Path) -> str:
    source = _cat(image, "/documents/m.md")
    target = _cat(image, "/records/m.md")
    assert (source, target) in ((V2, None), (None, V2)), (
        source and source[:20], target and target[:20],
    )
    return "old" if source == V2 else "new"


FILE_MOVE = Operation(
    "File Explorer's move of a file",
    setup=['T-V2$ S" /m.md" T-SAVE'],
    run=['S" /m.md" T-DOCS @ S" /m.md" T-REC @ T-SCRATCH 4096 PLACE-MOVE'],
    machine=_move_machine,
    host=_move_host,
)


def _agent_machine(machine: Machine) -> str:
    assert machine.run("T-AGENT") == (0,)
    count, status = machine.run(
        "T-STORE @ ACSTORE-LOAD SWAP DUP T-CONV ! ACONV.COUNT @ SWAP"
    )
    assert status == 0 and count in (1, 2), (count, status)
    return "old" if count == 1 else "new"


AGENT_SAVE = Operation(
    "the Agent's save of its conversation",
    setup=[
        "T-AGENT",
        "ACONV-NEW SWAP T-CONV !",
        'AROLE-USER S" the first question" T-SAY',
        "T-CONV @ T-STORE @ ACSTORE-SAVE",
    ],
    run=[
        "T-AGENT",
        "T-STORE @ ACSTORE-LOAD SWAP T-CONV !",
        "AROLE-ASSISTANT T-REPLY 2000 T-SAY",
        "T-CONV @ T-STORE @ ACSTORE-SAVE",
    ],
    machine=_agent_machine,
    host=lambda image: None,
)

AGENT_FIRST_LINES = [
    "T-AGENT",
    "ACONV-NEW SWAP T-CONV !",
    'AROLE-USER S" the first question" T-SAY',
    "T-CONV @ T-STORE @ ACSTORE-SAVE",
]


def _agent_first_machine(machine: Machine) -> str:
    """A cut before the first save's slot holds its record leaves no
    conversation, and the save the Agent then makes succeeds."""
    assert machine.run("T-AGENT") == (0,)
    (status,) = machine.run("T-STORE @ ACSTORE-LOAD SWAP T-CONV !")
    (absent,) = machine.run("ACSTORE-S-NOT-FOUND")
    assert status in (0, absent), status
    if status == 0:
        assert machine.run("T-CONV @ ACONV.COUNT @") == (1,)
        return "new"
    for line in AGENT_FIRST_LINES[1:]:
        assert machine.run(line) == (0,), line
    assert machine.run("T-STORE @ ACSTORE-LOAD SWAP T-CONV !") == (0,)
    assert machine.run("T-CONV @ ACONV.COUNT @") == (1,)
    return "old"


AGENT_FIRST_SAVE = Operation(
    "the Agent's first save",
    setup=[],
    run=AGENT_FIRST_LINES,
    machine=_agent_first_machine,
    host=lambda image: None,
)

# Streams' repository in records/own, as its runtime owner keeps it, with
# the page caches and work its repository test gives it.
STREAMS = SUITE + r"""
CREATE T-C0 PERSIST-PAGE-CACHE-SIZE ALLOT
CREATE T-C1 PERSIST-PAGE-CACHE-SIZE ALLOT
PERSIST-PAGE-CACHE-FRAME-SIZE 2 * XBUF T-C0M
PERSIST-PAGE-CACHE-FRAME-SIZE 2 * XBUF T-C1M
GUARD T-G
STREAMS-REPOSITORY-SIZE XBUF T-R
STREAMS-REPOSITORY-WORK-SIZE XBUF T-W
STREAMS-REPOSITORY-RECORD-BUFFER-MIN XBUF T-RBUF
65536 XBUF T-AMAP
CREATE T-AUTH RID-SIZE ALLOT  T-AUTH RID-SIZE 0x61 FILL
T-C0M PERSIST-PAGE-CACHE-FRAME-SIZE 2 * 2 T-C0 PPAGE-CACHE-INIT THROW
T-C1M PERSIST-PAGE-CACHE-FRAME-SIZE 2 * 2 T-C1 PPAGE-CACHE-INIT THROW
: T-REPO  ( -- status )
    S" /records/own" USERVOL-VFS T-C0 T-C1 T-G 0 0 T-R STREAMS-REPOSITORY-INIT
    ?DUP IF EXIT THEN
    T-AMAP 65536 T-RBUF STREAMS-REPOSITORY-RECORD-BUFFER-MIN T-R T-W
        STREAMS-REPOSITORY-WORK-INIT ;
: T-LOAD-REPO  ( -- status )  T-R T-W STREAMS-REPOSITORY-LOAD ;
\ Provision the repository the way its owner does on a volume without one.
: T-PROVISION  ( -- status )
    T-REPO ?DUP IF EXIT THEN
    T-LOAD-REPO STREAMS-REPOSITORY-S-ABSENT <> IF -1 EXIT THEN
    T-AUTH T-R T-W STREAMS-REPOSITORY-PROVISION ?DUP IF EXIT THEN
    T-R T-W STREAMS-REPOSITORY-FINI ;
"""


def _streams_machine(machine: Machine) -> str:
    """A cut before the repository's final root leaves it absent, and the
    provisioning its owner then repeats succeeds; after it, it loads."""
    assert machine.run("T-REPO") == (0,)
    (status,) = machine.run("T-LOAD-REPO")
    (absent,) = machine.run("STREAMS-REPOSITORY-S-ABSENT")
    assert status in (0, absent), status
    if status == absent:
        assert machine.run("T-AUTH T-R T-W STREAMS-REPOSITORY-PROVISION") == (0,)
        assert machine.run("T-LOAD-REPO") == (0,)
    assert machine.run("T-R T-W STREAMS-REPOSITORY-FINI") == (0,)
    return "old" if status == absent else "new"


STREAMS_PROVISION = Operation(
    "Streams provisioning its repository",
    setup=['S" /own" T-REC @ PLACE-MKDIR'],
    run=["T-PROVISION"],
    machine=_streams_machine,
    host=lambda image: None,
    roots=ROOTS + ("tui/applets/streams/repository.f",),
    helpers=STREAMS,
)

OPERATIONS = (
    PAD_SAVE, FILE_COPY, FOLDER_COPY, FILE_MOVE, AGENT_SAVE, AGENT_FIRST_SAVE,
    STREAMS_PROVISION,
)


@pytest.mark.parametrize("op", OPERATIONS, ids=lambda op: op.name)
def test_a_cut_at_any_flush_leaves_the_old_state_or_the_new(
    fresh_user_volume: bytes, tmp_path: Path, op: Operation
) -> None:
    states = _killed(fresh_user_volume, op, tmp_path)
    _assert_all_or_nothing(states)
