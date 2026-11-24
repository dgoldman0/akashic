"""Load Akashic modules from an MP64FS disk the way KDOS's REQUIRE finds them.

Some suites write the modules they test to an MP64FS disk, boot KDOS from it
and let ``REQUIRE`` load the modules from their directories.  A disk listed
by hand goes stale as soon as a module comes to require another, and KDOS
then reports the missing module and carries on, so these suites build the
disk from the roots' REQUIRE closure and fail on any KDOS diagnostic in the
transcript, not only on their own PASS and FAIL lines.
"""

from __future__ import annotations

from pathlib import Path

from forth_dependencies import dependency_order
from forth_snapshot import KDOS_DIAGNOSTICS, SOURCE_ROOT


# What KDOS prints when a module it loads from disk names a file or a
# directory the disk lacks.
DISK_LOAD_DIAGNOSTICS = (
    "Module not found",
    "Path component not found",
)


def module_disk_files(roots: tuple[str, ...]) -> list[tuple[str, str, Path]]:
    """``(name, directory, host path)`` for ROOTS and their REQUIRE closure.

    ROOTS name modules under akashic/akashic.  Each file goes to its own
    directory on the disk, in dependency order.
    """

    files = []
    for module in dependency_order(SOURCE_ROOT, roots):
        directory, _, name = module.rpartition("/")
        files.append((name, "/" + directory, SOURCE_ROOT / module))
    return files


def kdos_diagnostics(text: str) -> list[str]:
    """The KDOS diagnostics a whole transcript holds."""

    return [item for item in KDOS_DIAGNOSTICS + DISK_LOAD_DIAGNOSTICS
            if item in text]


# Forth that wraps ALLOCATE and FREE for the modules loaded after it, so a
# suite can check a teardown.  Between MLOG-START and MLOG-STOP each call
# records the address it handles.  MLOG-REPEATS counts frees of an address
# an earlier logged free named, MLOG-UNFREED the logged allocations no
# logged free returned, and MLOG-STRAYS the frees of addresses no logged
# allocation gave; MLOG-BALANCED? holds when all three are zero and the
# log kept every call.  With -1 MLOG-HOLD, FREE keeps the blocks out of the
# heap, so a faulty teardown cannot corrupt it and no address is handed out
# twice inside one log.  KDOS's FREE ignores zero, and so does the log.
MEMORY_LOG = r"""
\ ── Memory log ─────────────────────────────────────────────────
' ALLOCATE CONSTANT _MLOG-ALLOCATE
' FREE CONSTANT _MLOG-FREE
1024 CONSTANT _MLOG-CAP
_MLOG-CAP CELLS _MLOG-ALLOCATE EXECUTE DROP CONSTANT _MLOG-A
_MLOG-CAP CELLS _MLOG-ALLOCATE EXECUTE DROP CONSTANT _MLOG-F
VARIABLE _MLOG-NA     0 _MLOG-NA !
VARIABLE _MLOG-NF     0 _MLOG-NF !
VARIABLE _MLOG-ON     0 _MLOG-ON !
VARIABLE _MLOG-KEEP   0 _MLOG-KEEP !
VARIABLE _MLOG-OVER   0 _MLOG-OVER !
: _MLOG-PUSH  ( addr log nvar -- )
    DUP @ _MLOG-CAP >= IF 2DROP DROP -1 _MLOG-OVER ! EXIT THEN
    DUP >R @ CELLS + !  1 R> +! ;
: _MLOG-COUNT  ( addr log n -- k )
    0 SWAP 0 ?DO
        OVER I CELLS + @ 3 PICK = IF 1+ THEN
    LOOP NIP NIP ;
: ALLOCATE  ( u -- addr ior )
    _MLOG-ALLOCATE EXECUTE
    DUP 0= _MLOG-ON @ AND IF OVER _MLOG-A _MLOG-NA _MLOG-PUSH THEN ;
: FREE  ( addr -- )
    DUP 0= IF DROP EXIT THEN
    _MLOG-ON @ IF DUP _MLOG-F _MLOG-NF _MLOG-PUSH THEN
    _MLOG-KEEP @ IF DROP ELSE _MLOG-FREE EXECUTE THEN ;
: MLOG-START  ( -- )
    0 _MLOG-NA !  0 _MLOG-NF !  0 _MLOG-OVER !  -1 _MLOG-ON ! ;
: MLOG-STOP  ( -- )  0 _MLOG-ON ! ;
: MLOG-HOLD  ( flag -- )  _MLOG-KEEP ! ;
: MLOG-FREES  ( -- n )  _MLOG-NF @ ;
: MLOG-ALLOCS  ( -- n )  _MLOG-NA @ ;
: MLOG-REPEATS  ( -- n )
    0  _MLOG-NF @ 0 ?DO
        _MLOG-F I CELLS + @  _MLOG-F I _MLOG-COUNT 0> IF 1+ THEN
    LOOP ;
: MLOG-UNFREED  ( -- n )
    0  _MLOG-NA @ 0 ?DO
        _MLOG-A I CELLS + @  _MLOG-F _MLOG-NF @ _MLOG-COUNT 0= IF 1+ THEN
    LOOP ;
: MLOG-STRAYS  ( -- n )
    0  _MLOG-NF @ 0 ?DO
        _MLOG-F I CELLS + @  _MLOG-A _MLOG-NA @ _MLOG-COUNT 0= IF 1+ THEN
    LOOP ;
: MLOG-BALANCED?  ( -- flag )
    MLOG-REPEATS 0=  MLOG-UNFREED 0= AND  MLOG-STRAYS 0= AND
    _MLOG-OVER @ 0= AND ;
"""
