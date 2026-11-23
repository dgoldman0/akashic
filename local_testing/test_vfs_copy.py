#!/usr/bin/env python3
"""Copying and moving files (akashic/utils/fs/vfs-copy.f).

Two RAM volumes stand for mounted storage.  Both run on a copy of the RAM
binding whose writes, removals, renames and syncs fail on demand, on the
volume that F-VFS names: a write past F-SPACE bytes answers VFS-E-NOSPC,
F-FLIP changes a byte of each write after the binding stores it, F-THROW
makes the next write throw, F-SYNC fails that many syncs from now, and
F-UNLINK and F-RENAME fail every removal and rename.  The places tests
declare places over both volumes.  The boot-volume tests run the MP64FS
binding on the machine's boot unit, mounted as a boot mounts it, and read
the image the copy left with MegaPad's own MP64FS reader.

Every check runs on a fresh machine and prints its results after a
`RESULT:` marker.  test_vfs_copy_ext4.py runs copies on an ext4 volume.
"""
from __future__ import annotations

import sys
from pathlib import Path

from forth_dependencies import dependency_order
from native_forth import (
    MEGAPAD_ROOT,
    SOURCE_ROOT,
    NativeForth,
    SharedMachine,
    load_sources,
    module_source,
)

sys.path.insert(0, str(MEGAPAD_ROOT))

from diskutil import MP64FS  # noqa: E402
from simulator.platform import create_address_space  # noqa: E402
from simulator.runtime import MegaForthRuntime  # noqa: E402
from simulator.storage import HostedStorageService  # noqa: E402

ROOTS = ("utils/fs/vfs-copy.f",)

# VFS reasons the checks name (VFS-R-* in utils/fs/vfs.f).
INVALID, NOENT, EXISTS, NOTDIR, ISDIR = 1, 2, 3, 4, 5
READONLY, NOSPC, IO, CORRUPT, UNSUPPORTED = 7, 8, 9, 10, 11
BUSY, NAMETOOLONG, XDEV, NOVOLUME = 14, 17, 19, 21
TRUE, FALSE = -1, 0

HELPERS = (
    # The binding both volumes run on.
    'CREATE T-OPS VFS-OPS-SIZE ALLOT',
    'CREATE T-BINDING VFS-BINDING-DESC-SIZE ALLOT',
    'VARIABLE F-VFS  VARIABLE F-SPACE  VARIABLE F-FLIP  VARIABLE F-THROW',
    'VARIABLE F-SYNC  VARIABLE F-UNLINK  VARIABLE F-RENAME  VARIABLE SYNCS',
    ': CLEAR-FAULTS  0 F-VFS !  -1 F-SPACE !  0 F-FLIP !  0 F-THROW !',
    '    0 F-SYNC !  0 F-UNLINK !  0 F-RENAME !  0 SYNCS ! ;',
    'CLEAR-FAULTS',
    'VARIABLE W-B  VARIABLE W-L  VARIABLE W-O  VARIABLE W-I  VARIABLE W-V',
    ': T-WRITE  ( buf len off inode vfs -- actual ior )',
    '    W-V ! W-I ! W-O ! W-L ! W-B !',
    '    W-V @ F-VFS @ = IF',
    '        F-THROW @ IF 0 F-THROW ! -222 THROW THEN',
    '        F-SPACE @ 0< 0= IF',
    '            W-L @ F-SPACE @ > IF 0 VFS-E-NOSPC EXIT THEN',
    '            W-L @ NEGATE F-SPACE +!',
    '        THEN',
    '    THEN',
    '    W-B @ W-L @ W-O @ W-I @ W-V @ _VFS-RAM-WRITE',
    '    DUP 0=  W-V @ F-VFS @ = AND  F-FLIP @ AND IF',
    '        W-I @ IN.BDATA @ W-O @ + DUP C@ 1 XOR SWAP C!',
    '    THEN ;',
    ': T-SYNC  ( vfs -- ior )',
    '    DUP F-VFS @ = IF',
    '        1 SYNCS +!',
    '        F-SYNC @ IF -1 F-SYNC +! F-SYNC @ 0= IF DROP VFS-E-IO EXIT THEN THEN',
    '    THEN',
    '    _VFS-RAM-SYNCFS ;',
    ': T-UNLINK  ( inode vfs -- ior )',
    '    DUP F-VFS @ = F-UNLINK @ AND IF 2DROP VFS-E-IO EXIT THEN',
    '    _VFS-RAM-UNLINK ;',
    ': T-RENAME  ( new-a new-u inode new-parent victim flags vfs -- ior )',
    '    DUP F-VFS @ = F-RENAME @ AND IF 2DROP 2DROP 2DROP DROP VFS-E-IO EXIT THEN',
    '    _VFS-RAM-RENAME ;',
    'VFS-RAM-OPS T-OPS VFS-OPS-SIZE MOVE',
    'VFS-RAM-BINDING T-BINDING VFS-BINDING-DESC-SIZE MOVE',
    'T-OPS T-BINDING VB.OPS !',
    "' T-WRITE T-OPS VFS-OP-WRITE CELLS + !",
    "' T-SYNC T-OPS VFS-OP-SYNCFS CELLS + !",
    "' T-UNLINK T-OPS VFS-OP-UNLINK CELLS + !",
    "' T-RENAME T-OPS VFS-OP-RENAME CELLS + !",
    ': T-VFS  ( -- vfs )',
    '    1048576 A-XMEM ARENA-NEW THROW T-BINDING 0 VFS-NEW THROW ;',
    'VARIABLE VA  VARIABLE VB',
    'T-VFS VA !  T-VFS VB !',
    'S" d" VA @ VFS-MKDIR THROW  S" d" VB @ VFS-MKDIR THROW',
    # Files, their bytes and their stages.
    'CREATE BIG 40000 ALLOT  CREATE BACK 40000 ALLOT  CREATE SCR 4096 ALLOT',
    'CREATE REC VCOPY-SIZE ALLOT  CREATE T-REPL VREPL-SIZE ALLOT',
    ': PAT  ( seed n -- )  0 ?DO DUP I 13 * + 251 MOD BIG I + C! LOOP DROP ;',
    'VARIABLE P-FD',
    ': PUT  ( a u path-a path-u vfs -- )',
    '    >R 2DUP R@ VFS-CREATE 0= ABORT" PUT: create failed"',
    '    VFS-FF-WRITE R> VFS-OPEN? THROW P-FD !',
    '    P-FD @ VFS-WRITE-EXACT THROW  P-FD @ VFS-CLOSE? THROW ;',
    'VARIABLE S-FD',
    ': SAME?  ( path-a path-u vfs a u -- flag )',
    '    2>R VFS-FF-READ SWAP VFS-OPEN? IF DROP 2R> 2DROP 0 EXIT THEN S-FD !',
    '    S-FD @ VFS-SIZE R@ <> IF S-FD @ VFS-CLOSE? DROP 2R> 2DROP 0 EXIT THEN',
    '    BACK R@ S-FD @ VFS-READ-EXACT IF S-FD @ VFS-CLOSE? DROP 2R> 2DROP 0 EXIT THEN',
    '    S-FD @ VFS-CLOSE? DROP  BACK R@ 2R> COMPARE 0= ;',
    ': HAS?  ( path-a path-u vfs -- flag )',
    '    >R VFS-RP-NOFOLLOW-FINAL R> VFS-RESOLVE-POLICY? NIP 0= ;',
    ': STAGE$  ( path-a path-u vfs -- a u )',
    '    T-REPL VREPL-INIT THROW  T-REPL VREPL-DERIVE-PATHS! THROW',
    '    T-REPL VREPL-STAGE$ ;',
    ': FDS  ( vfs -- n )',
    '    0 SWAP V.FDFREE @ BEGIN DUP WHILE SWAP 1+ SWAP FD.FREE @ REPEAT DROP ;',
    'VARIABLE FD-A  VARIABLE FD-B  VARIABLE CWD-A  VARIABLE CWD-B',
    ': NOTE-STATE  VA @ FDS FD-A !  VB @ FDS FD-B !',
    '    VA @ V.CWD @ CWD-A !  VB @ V.CWD @ CWD-B ! ;',
    ': STATE-KEPT?  ( -- flag )',
    '    VA @ FDS FD-A @ =  VB @ FDS FD-B @ = AND',
    '    VA @ V.CWD @ CWD-A @ = AND  VB @ V.CWD @ CWD-B @ = AND ;',
    ': R.  ( ior -- )  VFS-IOR-REASON . ;',
    ': RP.  ( ior -- )  DUP R.  VFS-IOR-FLAGS VFS-IOR-F-PARTIAL AND 0<> . ;',
    # A path of one name of N bytes in the root, and one of LEN bytes in
    # folders of 199-byte names.
    'CREATE LN 4200 ALLOT',
    ': NAME-PATH  ( n -- a u )  LN 4200 110 FILL  47 LN C!  LN SWAP 1+ ;',
    # Every change the binding makes is durable when it returns, as on
    # ext4's staged writer, so a copy needs no sync between its steps.
    ': T-DURABLE  T-BINDING VB.CAPS DUP @ VFS-CAP-DURABLE-MUTATIONS OR SWAP ! ;',
)

PLACES = (
    'VARIABLE PVA  VARIABLE PVB  VARIABLE PVC',
    'VARIABLE P-ONE  VARIABLE P-TWO  VARIABLE P-RO  VARIABLE P-GONE  VARIABLE SET',
    ': T-PLACES  ( -- )',
    '    S" va" PLACES-VOLUME THROW PVA !  S" vb" PLACES-VOLUME THROW PVB !',
    '    S" vc" PLACES-VOLUME THROW PVC !',
    '    VA @ PVA @ PVOL-ATTACH THROW  VB @ PVB @ PVOL-ATTACH THROW',
    '    PLSET-NEW THROW SET !',
    '    S" one" S" /d" PLACE-WRITABLE PVA @ PLACES-DECLARE THROW',
    '    PLACE-WRITABLE SWAP SET @ PLSET-GRANT THROW P-ONE !',
    '    S" two" S" /" PLACE-WRITABLE PVB @ PLACES-DECLARE THROW',
    '    PLACE-WRITABLE SWAP SET @ PLSET-GRANT THROW P-TWO !',
    '    S" ro" S" /d" PLACE-WRITABLE PVB @ PLACES-DECLARE THROW',
    '    PLACE-READ-ONLY SWAP SET @ PLSET-GRANT THROW P-RO !',
    '    S" gone" S" /" PLACE-WRITABLE PVC @ PLACES-DECLARE THROW',
    '    PLACE-WRITABLE SWAP SET @ PLSET-GRANT THROW P-GONE ! ;',
    'T-PLACES',
)

# A folder of three levels: TREE makes /tree on a volume, holding a.txt
# (700 bytes), an empty file c, an empty folder e, and sub/b.bin (40,000
# bytes, ten times the scratch the copies take), and TREE? checks that a
# path holds that tree.  AT joins the base in TP with a suffix, in TQ.
TREE = (
    'CREATE TP 600 ALLOT  VARIABLE TPU  CREATE TQ 600 ALLOT',
    ': BASE!  ( a u -- )  DUP TPU !  TP SWAP CMOVE ;',
    ': AT  ( a u -- a2 u2 )  TP TQ TPU @ CMOVE',
    '    DUP >R TQ TPU @ + SWAP CMOVE  TQ TPU @ R> + ;',
    ': DIR?  ( path-a path-u vfs -- flag )',
    '    VFS-RESOLVE? IF DROP FALSE EXIT THEN IN.TYPE @ VFS-T-DIR = ;',
    ': TREE  ( vfs -- )  >R',
    '    S" /" R@ VFS-CD? THROW  S" tree" R@ VFS-MKDIR THROW',
    '    S" /tree" R@ VFS-CD? THROW  S" sub" R@ VFS-MKDIR THROW',
    '    S" e" R@ VFS-MKDIR THROW  S" /" R@ VFS-CD? THROW',
    '    21 700 PAT  BIG 700 S" /tree/a.txt" R@ PUT',
    '    BIG 0 S" /tree/c" R@ PUT',
    '    22 40000 PAT  BIG 40000 S" /tree/sub/b.bin" R@ PUT  R> DROP ;',
    ': TREE?  ( path-a path-u vfs -- flag )  >R BASE!',
    '    21 700 PAT  S" /a.txt" AT R@ BIG 700 SAME?',
    '    S" /c" AT R@ BIG 0 SAME? AND',
    '    S" /e" AT R@ DIR? AND',
    '    22 40000 PAT  S" /sub/b.bin" AT R@ BIG 40000 SAME? AND  R> DROP ;',
)

SUITE = NativeForth(ROOTS, prelude=HELPERS + PLACES + TREE)


def words(raw: bytes) -> str:
    text = "".join(chr(b) if 0x20 <= b < 0x7F or b in (10, 13, 9) else ""
                   for b in raw)
    assert "RESULT:" in text, text[-800:]
    tail = text.rsplit("RESULT:", 1)[1]
    assert "??" not in tail, tail
    return " ".join(tail.split())


def expect(lines, wanted, max_steps=200_000_000):
    got = words(SUITE.run(['." RESULT: "', *lines, 'CR'], max_steps))
    assert got == " ".join(str(item) for item in wanted), got


# =====================================================================
#  Copies between two RAM volumes
# =====================================================================

def test_a_copy_between_two_volumes_is_exact():
    expect([
        ': T  NOTE-STATE  7 20000 PAT  BIG 20000 S" /big.bin" VA @ PUT',
        '     S" /big.bin" VA @ S" /big.bin" VB @ SCR 4096 VFS-COPY R.',
        '     S" /big.bin" VB @ BIG 20000 SAME? .',
        '     S" /big.bin" VA @ BIG 20000 SAME? .',
        '     S" /big.bin" VB @ STAGE$ VB @ HAS? .',
        # An empty file, and a one-byte file through three bytes of scratch.
        '     BIG 0 S" /empty" VA @ PUT',
        '     S" /empty" VA @ S" /d/empty" VB @ SCR 4096 VFS-COPY R.',
        '     S" /d/empty" VB @ BIG 0 SAME? .',
        '     BIG 1 S" /one" VA @ PUT',
        '     S" /one" VA @ S" /one" VB @ SCR 3 VFS-COPY R.',
        '     S" /one" VB @ BIG 1 SAME? .',
        # Inside one volume, into another folder.
        '     S" /big.bin" VA @ S" /d/again.bin" VA @ SCR 4096 VFS-COPY R.',
        '     S" /d/again.bin" VA @ BIG 20000 SAME? .',
        '     STATE-KEPT? . ;',
        'T',
    ], [0, TRUE, TRUE, FALSE, 0, TRUE, 0, TRUE, 0, TRUE, TRUE])


def test_a_copy_steps_one_chunk_at_a_time():
    """10,000 bytes through 4,096 bytes of scratch: three writes, a step
    that syncs and reopens the stage, five comparisons of 2,048 bytes and
    the rename.  The final name appears only with the last step."""
    expect([
        'VARIABLE N  VARIABLE EARLY',
        ': STEPS  ( -- ior )  0 N !  0 EARLY !',
        '    BEGIN',
        '        S" /s.bin" VB @ HAS? IF -1 EARLY ! THEN',
        '        REC VCOPY-STEP  1 N +!  ?DUP IF NIP EXIT THEN',
        '    0= UNTIL 0 ;',
        ': T  NOTE-STATE  11 10000 PAT  BIG 10000 S" /s.bin" VA @ PUT',
        '     S" /s.bin" VA @ S" /s.bin" VB @ SCR 4096 REC VCOPY-INIT R.',
        '     S" /s.bin" VB @ STAGE$ VB @ HAS? .  S" /s.bin" VB @ HAS? .',
        '     S" /s.bin" VB @ STAGE$ DROP 1+ 3 TYPE SPACE',
        '     STEPS R.  N @ .  EARLY @ .',
        '     S" /s.bin" VB @ BIG 10000 SAME? .  S" /s.bin" VB @ STAGE$ VB @ HAS? .',
        '     REC VCOPY-STEP R. .  STATE-KEPT? . ;',
        'T',
    ], [0, TRUE, FALSE, ".s-", 0, 10, FALSE, TRUE, FALSE, 0, FALSE, TRUE])


def test_a_copy_refuses_an_existing_name():
    """The copy refuses before it writes anything: the destination volume
    sees no sync."""
    expect([
        ': T  3 100 PAT  BIG 100 S" /a" VA @ PUT  BIG 50 S" /a" VB @ PUT',
        '     VB @ F-VFS !',
        '     S" /a" VA @ S" /a" VB @ SCR 4096 VFS-COPY R.',
        '     S" /a" VB @ BIG 50 SAME? .',
        '     S" /a" VA @ S" /d" VB @ SCR 4096 VFS-COPY R.',
        '     S" /a" VB @ STAGE$ VB @ HAS? .  SYNCS @ .',
        '     S" /a" VA @ S" /a" VA @ SCR 4096 VFS-COPY R. ;',
        'T',
    ], [EXISTS, TRUE, EXISTS, FALSE, 0, EXISTS])


def test_a_name_taken_while_copying_is_kept():
    """The rename refuses a final name that appeared after the copy began,
    so the file that took it stays, and the stage goes."""
    expect([
        ': T  17 9000 PAT  BIG 9000 S" /t" VA @ PUT  NOTE-STATE',
        '     S" /t" VA @ S" /t" VB @ SCR 4096 REC VCOPY-INIT R.',
        '     REC VCOPY-STEP R. .  BIG 20 S" /t" VB @ PUT',
        '     BEGIN REC VCOPY-STEP ?DUP IF NIP -1 ELSE 0= DUP IF 0 SWAP THEN THEN',
        '     UNTIL R.',
        '     S" /t" VB @ BIG 20 SAME? .  S" /t" VB @ STAGE$ VB @ HAS? .',
        '     STATE-KEPT? . ;',
        'T',
    ], [0, 0, TRUE, EXISTS, TRUE, FALSE, TRUE])


def test_a_copy_refuses_what_it_cannot_copy():
    expect([
        ': T  NOTE-STATE  BIG 10 S" /f" VA @ PUT',
        # A folder cannot be copied into itself.
        '     S" /d" VA @ S" /d/x" VA @ SCR 4096 VFS-COPY R.',
        '     S" /nope" VA @ S" /x" VB @ SCR 4096 VFS-COPY R.',
        '     S" /f" VA @ S" /d/no/x" VB @ SCR 4096 VFS-COPY R.',
        '     S" /f" VA @ S" /f/x" VA @ SCR 4096 VFS-COPY R.',
        # The replacement library names the stage, and refuses a relative
        # path, a name over the VFS's 255 bytes and a name in its reserved
        # namespace.
        '     S" /f" VA @ S" x" VB @ SCR 4096 VFS-COPY R.',
        '     S" /f" VA @ 256 NAME-PATH VB @ SCR 4096 VFS-COPY R.',
        '     S" /f" VA @ S" /.s-abc" VB @ SCR 4096 VFS-COPY R.',
        '     S" /f" VA @ S" /x" VB @ SCR 1 VFS-COPY R.',
        '     S" /f" VA @ S" /x" 0 SCR 4096 VFS-COPY R.',
        '     S" /f" VA @ S" /x" VB @ SCR 4096 0 VCOPY-INIT R.',
        '     REC VCOPY-SIZE 0 FILL  REC VCOPY-STEP R. .  REC VCOPY-CANCEL R.',
        '     S" /x" VB @ HAS? .  STATE-KEPT? . ;',
        'T',
    ], [INVALID, NOENT, NOENT, NOTDIR, INVALID, INVALID, INVALID, INVALID,
        INVALID, INVALID, INVALID, 0, INVALID, FALSE, TRUE])


def test_a_copy_takes_the_names_and_paths_its_volume_takes():
    """The RAM volume sets no name limit of its own: a name of 255 bytes
    copies, and so does a file in a folder whose path is longer than 255
    bytes."""
    expect([
        ': T  NOTE-STATE  BIG 10 S" /f" VA @ PUT',
        '     S" /f" VA @ 255 NAME-PATH VB @ SCR 4096 VFS-COPY R.',
        '     255 NAME-PATH VB @ BIG 10 SAME? .',
        # /d/<200 bytes>/<100 bytes>: a path of 304 bytes.
        '     LN 4200 111 FILL  S" /d/" LN SWAP CMOVE  47 LN 203 + C!',
        '     S" /d" VB @ VFS-CD? THROW  LN 3 + 200 VB @ VFS-MKDIR THROW',
        '     S" /" VB @ VFS-CD? THROW',
        '     S" /f" VA @ LN 304 VB @ SCR 4096 VFS-COPY R.',
        '     LN 304 VB @ BIG 10 SAME? .  STATE-KEPT? . ;',
        'T',
    ], [0, TRUE, 0, TRUE, TRUE])


def test_a_copy_takes_its_barriers_only_where_the_binding_needs_them():
    """A copy syncs after its stage and after its rename on a binding whose
    changes need a sync to be durable, and not at all where every change is
    durable when it returns; a move across volumes then syncs neither."""
    expect([
        ': T  BIG 10 S" /f" VA @ PUT  VB @ F-VFS !  0 SYNCS !',
        '     S" /f" VA @ S" /x" VB @ SCR 4096 VFS-COPY R.  SYNCS @ .',
        '     T-DURABLE  0 SYNCS !',
        '     S" /f" VA @ S" /y" VB @ SCR 4096 VFS-COPY R.  SYNCS @ .',
        '     VA @ F-VFS !  0 SYNCS !',
        '     S" /f" VA @ S" /z" VB @ SCR 4096 VFS-MOVE R.  SYNCS @ .',
        '     S" /y" VB @ BIG 10 SAME? .  S" /f" VA @ HAS? . ;',
        'T',
    ], [0, 2, 0, 0, 0, 0, TRUE, FALSE])


# =====================================================================
#  Failures leave no final name, and remove the stage
# =====================================================================

def test_running_out_of_space_midway_leaves_no_final_name():
    expect([
        ': T  5 20000 PAT  BIG 20000 S" /big" VA @ PUT  NOTE-STATE',
        '     VB @ F-VFS !  10000 F-SPACE !',
        '     S" /big" VA @ S" /big" VB @ SCR 4096 VFS-COPY RP.',
        '     S" /big" VB @ HAS? .  S" /big" VB @ STAGE$ VB @ HAS? .',
        '     S" /big" VA @ BIG 20000 SAME? .  STATE-KEPT? . ;',
        'T',
    ], [NOSPC, FALSE, FALSE, FALSE, TRUE, TRUE])


def test_a_stage_that_does_not_read_back_is_removed():
    expect([
        ': T  9 9000 PAT  BIG 9000 S" /c" VA @ PUT  NOTE-STATE',
        '     VB @ F-VFS !  -1 F-FLIP !',
        '     S" /c" VA @ S" /c" VB @ SCR 4096 VFS-COPY RP.',
        '     S" /c" VB @ HAS? .  S" /c" VB @ STAGE$ VB @ HAS? .  STATE-KEPT? . ;',
        'T',
    ], [CORRUPT, FALSE, FALSE, FALSE, TRUE])


def test_a_failed_sync_before_the_comparison_removes_the_stage():
    """The first sync fails; the second is the one that follows the stage's
    removal."""
    expect([
        ': T  13 5000 PAT  BIG 5000 S" /y" VA @ PUT  NOTE-STATE',
        '     VB @ F-VFS !  1 F-SYNC !',
        '     S" /y" VA @ S" /y" VB @ SCR 4096 VFS-COPY RP.',
        '     S" /y" VB @ HAS? .  S" /y" VB @ STAGE$ VB @ HAS? .',
        '     SYNCS @ .  STATE-KEPT? . ;',
        'T',
    ], [IO, FALSE, FALSE, FALSE, 2, TRUE])


def test_a_failed_rename_removes_the_stage():
    expect([
        ': T  14 5000 PAT  BIG 5000 S" /n" VA @ PUT  NOTE-STATE',
        '     VB @ F-VFS !  -1 F-RENAME !',
        '     S" /n" VA @ S" /n" VB @ SCR 4096 VFS-COPY RP.',
        '     S" /n" VB @ HAS? .  S" /n" VB @ STAGE$ VB @ HAS? .  STATE-KEPT? . ;',
        'T',
    ], [IO, FALSE, FALSE, FALSE, TRUE])


def test_a_failed_sync_after_the_rename_leaves_the_copy_standing():
    expect([
        ': T  15 5000 PAT  BIG 5000 S" /z" VA @ PUT  NOTE-STATE',
        '     VB @ F-VFS !  2 F-SYNC !',
        '     S" /z" VA @ S" /z" VB @ SCR 4096 VFS-COPY RP.',
        '     S" /z" VB @ BIG 5000 SAME? .  S" /z" VB @ STAGE$ VB @ HAS? .',
        '     STATE-KEPT? . ;',
        'T',
    ], [IO, TRUE, TRUE, FALSE, TRUE])


def test_a_write_that_throws_is_a_failure_that_cleans_up():
    expect([
        ': T  16 9000 PAT  BIG 9000 S" /w" VA @ PUT  NOTE-STATE',
        '     VB @ F-VFS !  -1 F-THROW !',
        '     S" /w" VA @ S" /w" VB @ SCR 4096 VFS-COPY RP.',
        '     S" /w" VB @ HAS? .  S" /w" VB @ STAGE$ VB @ HAS? .  STATE-KEPT? . ;',
        'T',
    ], [IO, FALSE, FALSE, FALSE, TRUE])


def test_cancel_removes_the_stage():
    expect([
        ': T  1 10000 PAT  BIG 10000 S" /k" VA @ PUT  NOTE-STATE',
        '     S" /k" VA @ S" /k" VB @ SCR 4096 REC VCOPY-INIT R.',
        '     REC VCOPY-STEP R. .  REC VCOPY-STEP R. .',
        '     S" /k" VB @ STAGE$ VB @ HAS? .',
        # A record in use takes no second copy.
        '     S" /k" VA @ S" /k2" VB @ SCR 4096 REC VCOPY-INIT R.',
        '     REC VCOPY-CANCEL R.',
        '     S" /k" VB @ STAGE$ VB @ HAS? .  S" /k" VB @ HAS? .',
        '     REC VCOPY-CANCEL R.  REC VCOPY-STEP R. .  STATE-KEPT? . ;',
        'T',
    ], [0, 0, TRUE, 0, TRUE, TRUE, BUSY, 0, FALSE, FALSE, 0, 0, 0, TRUE])


def test_a_retried_copy_removes_the_stage_a_crash_left():
    """A crash during a copy leaves its stage, part written, under the name
    the same copy derives again."""
    expect([
        ': T  2 6000 PAT  BIG 6000 S" /r" VA @ PUT',
        '     BIG 3000 S" /r" VB @ STAGE$ VB @ PUT',
        '     S" /r" VB @ STAGE$ VB @ HAS? .',
        '     S" /r" VA @ S" /r" VB @ SCR 4096 VFS-COPY R.',
        '     S" /r" VB @ BIG 6000 SAME? .  S" /r" VB @ STAGE$ VB @ HAS? .',
        # A file under a stage's name is never taken for the stage when it
        # is the source itself.
        '     S" /q" VB @ STAGE$ 2DUP BIG 10 2SWAP VB @ PUT',
        '     VB @ S" /q" VB @ SCR 4096 VFS-COPY R.',
        '     S" /q" VB @ STAGE$ VB @ HAS? .  S" /q" VB @ HAS? . ;',
        'T',
    ], [TRUE, 0, TRUE, FALSE, INVALID, TRUE, FALSE])


# =====================================================================
#  Moves
# =====================================================================

def test_a_move_across_volumes_copies_then_removes_the_source():
    expect([
        ': T  4 5000 PAT  BIG 5000 S" /m" VA @ PUT  NOTE-STATE',
        '     S" /m" VA @ S" /d/m" VB @ SCR 4096 VFS-MOVE R.',
        '     S" /m" VA @ HAS? .  S" /d/m" VB @ BIG 5000 SAME? .  STATE-KEPT? . ;',
        'T',
    ], [0, FALSE, TRUE, TRUE])


def test_a_move_whose_delete_fails_keeps_both_files():
    expect([
        ': T  4 5000 PAT  BIG 5000 S" /m" VA @ PUT',
        '     VA @ F-VFS !  -1 F-UNLINK !',
        '     S" /m" VA @ S" /m" VB @ SCR 4096 VFS-MOVE RP.',
        '     S" /m" VA @ BIG 5000 SAME? .  S" /m" VB @ BIG 5000 SAME? .',
        '     S" /m" VB @ STAGE$ VB @ HAS? .',
        # A move whose copy fails changes nothing.
        '     CLEAR-FAULTS  VB @ F-VFS !  1000 F-SPACE !',
        '     S" /m" VA @ S" /m2" VB @ SCR 4096 VFS-MOVE RP.',
        '     S" /m" VA @ BIG 5000 SAME? .  S" /m2" VB @ HAS? . ;',
        'T',
    ], [IO, TRUE, TRUE, TRUE, FALSE, NOSPC, FALSE, TRUE, FALSE])


def test_a_move_inside_one_volume_is_a_rename():
    """No stage is written: the file keeps its storage and takes the new
    name, with one sync where a copy takes two.  A folder cannot move
    beneath itself.  A sync that fails after the rename leaves it moved."""
    expect([
        ': T  6 3000 PAT  BIG 3000 S" /in" VA @ PUT  NOTE-STATE  VA @ F-VFS !',
        '     S" /in" VA @ S" /d/moved" VA @ SCR 4096 VFS-MOVE R.',
        '     S" /in" VA @ HAS? .  S" /d/moved" VA @ BIG 3000 SAME? .',
        '     S" /d/moved" VA @ STAGE$ VA @ HAS? .  SYNCS @ .',
        '     BIG 10 S" /in" VA @ PUT',
        '     S" /in" VA @ S" /d/moved" VA @ SCR 4096 VFS-MOVE R.',
        '     S" /d" VA @ S" /d/e" VA @ SCR 4096 VFS-MOVE R.',
        '     S" /in" VA @ S" /.s-x" VA @ SCR 4096 VFS-MOVE R.',
        '     S" /in" VA @ S" /d/no/m" VA @ SCR 4096 VFS-MOVE R.',
        '     VA @ F-VFS !  1 F-SYNC !',
        '     S" /in" VA @ S" /d/m2" VA @ SCR 4096 VFS-MOVE RP.',
        '     S" /in" VA @ HAS? .  S" /d/m2" VA @ HAS? .  STATE-KEPT? . ;',
        'T',
    ], [0, FALSE, TRUE, FALSE, 1, EXISTS, INVALID, INVALID, NOENT,
        IO, TRUE, FALSE, TRUE, TRUE])


# =====================================================================
#  Folders
# =====================================================================

def test_a_folder_copies_whole_between_two_volumes_and_inside_one():
    """The tree goes under the stage name, one barrier follows, every file
    reads back, and the stage folder's rename and a second barrier end it:
    two syncs for the whole folder."""
    expect([
        ': T  VA @ TREE  NOTE-STATE  VB @ F-VFS !  0 SYNCS !',
        '     S" /tree" VA @ S" /d/tree" VB @ SCR 4096 VFS-COPY R.',
        '     S" /d/tree" VB @ TREE? .  S" /tree" VA @ TREE? .',
        '     S" /d/tree" VB @ STAGE$ VB @ HAS? .  SYNCS @ .',
        '     S" /tree" VA @ S" /d/again" VA @ SCR 4096 VFS-COPY R.',
        '     S" /d/again" VA @ TREE? .  STATE-KEPT? . ;',
        'T',
    ], [0, TRUE, TRUE, FALSE, 2, 0, TRUE, TRUE], max_steps=600_000_000)


def test_a_folder_copy_refuses_what_it_cannot_take():
    expect([
        ': T  VA @ TREE  NOTE-STATE',
        '     S" /tree" VA @ S" /d/tree" VB @ SCR 4096 VFS-COPY R.',
        '     S" /tree" VA @ S" /d/tree" VB @ SCR 4096 VFS-COPY R.',
        # Into itself, at any depth.
        '     S" /tree" VA @ S" /tree/sub/in" VA @ SCR 4096 VFS-COPY R.',
        '     S" /tree" VA @ S" /tree/in" VA @ SCR 4096 VFS-COPY R.',
        '     S" /tree/sub/in" VA @ HAS? .',
        '     S" /tree" VA @ S" /nope/x" VB @ SCR 4096 VFS-COPY R.',
        '     S" /tree" VA @ S" /d/t2" VB @ SCR 1 VFS-COPY R.',
        '     S" /tree" VA @ S" /d/t2" 0 SCR 4096 VFS-COPY R.',
        '     S" /d/t2" VB @ HAS? .  STATE-KEPT? . ;',
        'T',
    ], [0, EXISTS, INVALID, INVALID, FALSE, NOENT, INVALID, INVALID,
        FALSE, TRUE], max_steps=600_000_000)


def test_a_folder_copy_that_fails_leaves_no_final_name_and_no_stage():
    """Out of space midway, a copy that does not read back, a failed sync
    before the comparison, a failed rename and a write that throws each
    remove the stage tree; a failed sync after the rename leaves the copy
    standing, and its answer says so."""
    expect([
        ': GONE?  ( a u -- )  2DUP VB @ HAS? .  VB @ STAGE$ VB @ HAS? . ;',
        ': T  VA @ TREE  NOTE-STATE',
        '     VB @ F-VFS !  20000 F-SPACE !',
        '     S" /tree" VA @ S" /t1" VB @ SCR 4096 VFS-COPY RP.  S" /t1" GONE?',
        '     CLEAR-FAULTS  VB @ F-VFS !  -1 F-FLIP !',
        '     S" /tree" VA @ S" /t2" VB @ SCR 4096 VFS-COPY RP.  S" /t2" GONE?',
        '     CLEAR-FAULTS  VB @ F-VFS !  1 F-SYNC !',
        '     S" /tree" VA @ S" /t3" VB @ SCR 4096 VFS-COPY RP.  S" /t3" GONE?',
        '     CLEAR-FAULTS  VB @ F-VFS !  -1 F-RENAME !',
        '     S" /tree" VA @ S" /t4" VB @ SCR 4096 VFS-COPY RP.  S" /t4" GONE?',
        '     CLEAR-FAULTS  VB @ F-VFS !  -1 F-THROW !',
        '     S" /tree" VA @ S" /t5" VB @ SCR 4096 VFS-COPY RP.  S" /t5" GONE?',
        '     CLEAR-FAULTS  VB @ F-VFS !  2 F-SYNC !',
        '     S" /tree" VA @ S" /t6" VB @ SCR 4096 VFS-COPY RP.',
        '     S" /t6" VB @ TREE? .  S" /t6" VB @ STAGE$ VB @ HAS? .',
        '     CLEAR-FAULTS  S" /tree" VA @ TREE? .  STATE-KEPT? . ;',
        'T',
    ], [NOSPC, FALSE, FALSE, FALSE,
        CORRUPT, FALSE, FALSE, FALSE,
        IO, FALSE, FALSE, FALSE,
        IO, FALSE, FALSE, FALSE,
        IO, FALSE, FALSE, FALSE,
        IO, TRUE, TRUE, FALSE, TRUE, TRUE], max_steps=1_200_000_000)


def test_a_retried_folder_copy_removes_the_stage_a_crash_left():
    """A crash leaves the stage folder, part written, under the name the
    same copy derives again."""
    expect([
        ': T  VA @ TREE',
        '     S" /" VB @ VFS-CD? THROW',
        '     S" /r" VB @ STAGE$ SWAP 1+ SWAP 1- VB @ VFS-MKDIR THROW',
        '     S" /r" VB @ STAGE$ BASE!  BIG 100 S" /junk" AT VB @ PUT',
        '     S" /r" VB @ STAGE$ VB @ HAS? .',
        '     S" /tree" VA @ S" /r" VB @ SCR 4096 VFS-COPY R.',
        '     S" /r" VB @ TREE? .  S" /r" VB @ STAGE$ VB @ HAS? . ;',
        'T',
    ], [TRUE, 0, TRUE, FALSE], max_steps=600_000_000)


def test_a_folder_moves_inside_one_volume_by_one_rename():
    expect([
        ': T  VA @ TREE  NOTE-STATE  VA @ F-VFS !  0 SYNCS !',
        '     S" /tree" VA @ S" /d/tree" VA @ SCR 4096 VFS-MOVE R.',
        '     S" /tree" VA @ HAS? .  S" /d/tree" VA @ TREE? .  SYNCS @ .',
        '     S" /d/tree" VA @ S" /d/tree/sub/x" VA @ SCR 4096 VFS-MOVE R.',
        '     S" /d/tree" VA @ TREE? .  STATE-KEPT? . ;',
        'T',
    ], [0, FALSE, TRUE, 1, INVALID, TRUE, TRUE], max_steps=600_000_000)


def test_a_folder_moves_across_volumes_and_leaves_its_folder_at_once():
    """Once the copy stands, the source takes its own stage name, so it is
    gone from its folder, and that tree is removed.  A removal that fails
    leaves it hidden and the answer partial, and the next move of a folder
    by that name clears it first; a rename that fails leaves both folders
    under their names."""
    expect([
        ': T  VA @ TREE  NOTE-STATE',
        '     S" /tree" VA @ S" /m" VB @ SCR 4096 VFS-MOVE R.',
        '     S" /tree" VA @ HAS? .  S" /m" VB @ TREE? .',
        '     S" /tree" VA @ STAGE$ VA @ HAS? .  STATE-KEPT? . ;',
        'T',
        ': U  VA @ TREE  VA @ F-VFS !  -1 F-UNLINK !',
        '     S" /tree" VA @ S" /m2" VB @ SCR 4096 VFS-MOVE RP.',
        '     S" /m2" VB @ TREE? .  S" /tree" VA @ HAS? .',
        '     S" /tree" VA @ STAGE$ VA @ HAS? .',
        '     CLEAR-FAULTS  VA @ TREE',
        '     S" /tree" VA @ S" /m3" VB @ SCR 4096 VFS-MOVE R.',
        '     S" /tree" VA @ STAGE$ VA @ HAS? .  S" /m3" VB @ TREE? . ;',
        'U',
        ': V  VA @ TREE  VA @ F-VFS !  -1 F-RENAME !',
        '     S" /tree" VA @ S" /m4" VB @ SCR 4096 VFS-MOVE RP.',
        '     S" /m4" VB @ TREE? .  S" /tree" VA @ TREE? .',
        # A move whose copy fails changes nothing.
        '     CLEAR-FAULTS  VB @ F-VFS !  1000 F-SPACE !',
        '     S" /tree" VA @ S" /m5" VB @ SCR 4096 VFS-MOVE RP.',
        '     S" /tree" VA @ TREE? .  S" /m5" VB @ HAS? .  CLEAR-FAULTS ;',
        'V',
    ], [0, FALSE, TRUE, FALSE, TRUE,
        IO, TRUE, TRUE, FALSE, TRUE, 0, FALSE, TRUE,
        IO, TRUE, TRUE, TRUE, NOSPC, FALSE, TRUE, FALSE],
        max_steps=1_200_000_000)


def test_places_copy_and_move_folders():
    expect([
        ': T  VB @ TREE',
        '     S" tree" P-TWO @ S" tree" P-ONE @ SCR 4096 PLACE-COPY R.',
        '     S" /d/tree" VA @ TREE? .',
        '     S" tree" P-TWO @ S" t2" P-RO @ SCR 4096 PLACE-COPY R.',
        '     S" /d/t2" VB @ HAS? .',
        '     S" tree" P-ONE @ S" moved" P-TWO @ SCR 4096 PLACE-MOVE R.',
        '     S" /d/tree" VA @ HAS? .  S" /moved" VB @ TREE? . ;',
        'T',
    ], [0, TRUE, READONLY, FALSE, 0, FALSE, TRUE], max_steps=800_000_000)


# =====================================================================
#  Stepping folders and moves
# =====================================================================

# The phase VCOPY-PROGRESS reports, and stepping a record to its end.
STEPPING = [
    ': PHASE  ( copy -- p )  VCOPY-PROGRESS NIP NIP NIP NIP ;',
    ': FINISH  ( copy -- ior )  BEGIN DUP VCOPY-STEP SWAP WHILE DROP REPEAT NIP ;',
]


def test_a_folder_copy_steps_and_says_how_far_it_has_come():
    """VCOPY-INIT takes a folder.  Its steps count the tree, write it into
    the stage, read it back and rename the stage, a listing, a file's
    opening or closing, or a chunk each, more than forty in all, and the
    final name appears only with the last.  VCOPY-PROGRESS reports the
    three files of 40,700 bytes written and then read back."""
    expect([
        *STEPPING,
        'VARIABLE N  VARIABLE EARLY',
        'VARIABLE CF  VARIABLE CB  VARIABLE WF  VARIABLE WB  VARIABLE KF  VARIABLE KB',
        ': NOTE  ( -- )  REC VCOPY-PROGRESS',
        '    DUP VCOPY-P-COPYING = IF DROP CB ! WB ! CF ! WF ! EXIT THEN',
        '    VCOPY-P-CHECKING = IF CB ! KB ! CF ! KF ! EXIT THEN',
        '    2DROP 2DROP ;',
        ': T  VA @ TREE  NOTE-STATE  0 N !  0 EARLY !',
        '     S" /tree" VA @ S" /st" VB @ SCR 4096 REC VCOPY-INIT R.',
        '     REC PHASE .',
        '     BEGIN  S" /st" VB @ HAS? IF -1 EARLY ! THEN',
        '         REC VCOPY-STEP  1 N +!  NOTE  SWAP WHILE DROP REPEAT R.',
        '     N @ 40 > .  EARLY @ .  CF @ . CB @ . WF @ . WB @ . KF @ . KB @ .',
        '     S" /st" VB @ TREE? .  S" /st" VB @ STAGE$ VB @ HAS? .',
        '     REC VCOPY-STEP R. .  REC PHASE .  STATE-KEPT? . ;',
        'T',
    ], [0, 5, 0, TRUE, FALSE, 3, 40700, 3, 40700, 3, 40700,
        TRUE, FALSE, 0, 0, 0, TRUE], max_steps=800_000_000)


def test_a_folder_copy_cancelled_midway_removes_what_it_wrote():
    """A cancel before the commit gives the copy up: it answers at once,
    the steps that follow remove the stage tree, and the last of them
    answers 0.  Nothing of the copy is left, and no file stays open."""
    expect([
        *STEPPING,
        ': T  VA @ TREE  NOTE-STATE',
        '     S" /tree" VA @ S" /c1" VB @ SCR 4096 REC VCOPY-INIT R.',
        '     12 0 DO REC VCOPY-STEP 2DROP LOOP',
        '     REC PHASE .  S" /c1" VB @ STAGE$ VB @ HAS? .',
        '     REC VCOPY-CANCEL R.  REC PHASE .  REC FINISH R.',
        '     S" /c1" VB @ HAS? .  S" /c1" VB @ STAGE$ VB @ HAS? .',
        '     REC VCOPY-STEP R. .  REC VCOPY-CANCEL R.  S" /tree" VA @ TREE? .',
        '     STATE-KEPT? . ;',
        'T',
    ], [0, 1, TRUE, 0, 4, 0, FALSE, FALSE, 0, 0, 0, TRUE, TRUE],
        max_steps=800_000_000)


def test_two_copies_step_side_by_side():
    """Each copy keeps its state in its own record, so two folder copies
    stepped in turn both arrive whole."""
    expect([
        'CREATE REC2 VCOPY-SIZE ALLOT  CREATE SCR2 4096 ALLOT',
        ': T  VA @ TREE  NOTE-STATE',
        '     S" /tree" VA @ S" /i1" VB @ SCR 4096 REC VCOPY-INIT R.',
        '     S" /tree" VA @ S" /i2" VA @ SCR2 4096 REC2 VCOPY-INIT R.',
        '     BEGIN REC VCOPY-STEP DROP  REC2 VCOPY-STEP DROP  OR 0= UNTIL',
        '     S" /i1" VB @ TREE? .  S" /i2" VA @ TREE? .  STATE-KEPT? . ;',
        'T',
    ], [0, 0, TRUE, TRUE, TRUE], max_steps=1_200_000_000)


def test_a_move_cannot_be_cancelled_once_its_copy_stands():
    """Across volumes a move's copy stands at its commit, and the steps
    after it remove the source; VCOPY-CANCEL then answers VFS-E-BUSY and
    the move runs to its end.  Inside one volume VMOVE-INIT's one step
    is the rename."""
    expect([
        *STEPPING,
        ': T  VA @ TREE  NOTE-STATE',
        '     S" /tree" VA @ S" /mv" VB @ SCR 4096 REC VMOVE-INIT R.',
        '     BEGIN REC PHASE DUP VCOPY-P-FINISHING <> SWAP VCOPY-P-IDLE <> AND',
        '     WHILE REC VCOPY-STEP 2DROP REPEAT',
        '     REC PHASE .  S" /mv" VB @ TREE? .  REC VCOPY-CANCEL R.',
        '     REC FINISH R.  S" /tree" VA @ HAS? .  S" /tree" VA @ STAGE$ VA @ HAS? .',
        '     S" /mv" VB @ TREE? .',
        '     S" /mv" VB @ S" /d/mv" VB @ SCR 4096 REC VMOVE-INIT R.',
        '     REC VCOPY-STEP R. .  S" /d/mv" VB @ TREE? .  S" /mv" VB @ HAS? .',
        '     STATE-KEPT? . ;',
        'T',
    ], [0, 3, TRUE, BUSY, 0, FALSE, FALSE, TRUE, 0, 0, 0, TRUE, FALSE, TRUE],
        max_steps=1_200_000_000)


# =====================================================================
#  Places
# =====================================================================

def test_places_bind_the_source_for_reading_and_the_destination_for_writing():
    expect([
        ': T  8 3000 PAT  BIG 3000 S" /d/p.txt" VA @ PUT',
        '     S" p.txt" P-ONE @ S" /p.txt" P-TWO @ SCR 4096 PLACE-COPY R.',
        '     S" /p.txt" VB @ BIG 3000 SAME? .',
        # A read-only place takes nothing, and gives copies but no moves.
        '     S" p.txt" P-ONE @ S" q.txt" P-RO @ SCR 4096 PLACE-COPY R.',
        '     S" /d/q.txt" VB @ HAS? .',
        '     BIG 10 S" /d/r.txt" VB @ PUT',
        '     S" r.txt" P-RO @ S" r.txt" P-ONE @ SCR 4096 PLACE-MOVE R.',
        '     S" /d/r.txt" VB @ HAS? .  S" /d/r.txt" VA @ HAS? .',
        '     S" r.txt" P-RO @ S" r.txt" P-ONE @ SCR 4096 PLACE-COPY R.',
        '     S" /d/r.txt" VA @ BIG 10 SAME? .',
        # A move between places on two volumes.
        '     S" p.txt" P-ONE @ S" moved.txt" P-TWO @ SCR 4096 PLACE-MOVE R.',
        '     S" /d/p.txt" VA @ HAS? .  S" /moved.txt" VB @ BIG 3000 SAME? .',
        # Neither path leaves its place, and a place's own folder copies as
        # a folder does.
        '     BIG 10 S" /x" VA @ PUT',
        '     S" ../x" P-ONE @ S" x" P-TWO @ SCR 4096 PLACE-COPY R.',
        '     S" /moved.txt" P-TWO @ S" ../x2" P-ONE @ SCR 4096 PLACE-COPY R.',
        '     S" /" P-ONE @ S" x" P-TWO @ SCR 4096 PLACE-COPY R.',
        '     S" x" P-GONE @ S" x" P-TWO @ SCR 4096 PLACE-COPY R.',
        '     S" /x2" VA @ HAS? .  S" /x" VB @ DIR? .  S" /x/r.txt" VB @ BIG 10 SAME? . ;',
        'T',
    ], [0, TRUE, READONLY, FALSE, READONLY, TRUE, FALSE, 0, TRUE,
        0, FALSE, TRUE, XDEV, XDEV, 0, NOVOLUME, FALSE, TRUE, TRUE])


# =====================================================================
#  The MP64FS boot volume
# =====================================================================

BOOT_ROOTS = ("utils/fs/vfs-copy.f", "tui/platform/mp64fs-vfs.f")
BOOT_HELPERS = HELPERS + TREE + (
    'VARIABLE VM',
    'S" boot" PLACES-VOLUME THROW PVOL-VFS VM !',
)


def boot_machine(image: bytes) -> tuple[SharedMachine, object]:
    """A machine whose boot unit holds IMAGE, mounted as a boot mounts it
    (tui/platform/mp64fs-vfs.f), with the RAM volumes beside it."""
    storage = HostedStorageService(image)
    runtime = MegaForthRuntime(
        memory=create_address_space(
            external_size=128 << 20, hbw_size=1 << 20,
        ),
        execution_backend="native",
        storage=storage,
    )
    sources = [("kdos.f", (MEGAPAD_ROOT / "kdos.f").read_bytes()),
               ("userland", b"ENTER-USERLAND\n")]
    sources += [(module, module_source(SOURCE_ROOT / module))
                for module in dependency_order(SOURCE_ROOT, BOOT_ROOTS)]
    sources.append(("prelude", ("\n".join(BOOT_HELPERS) + "\n").encode()))
    load_sources(runtime, sources, 800_000_000)
    return SharedMachine(runtime), storage


def boot_image(total_sectors: int, files: dict[str, bytes]) -> bytes:
    fs = MP64FS(total_sectors=total_sectors)
    fs.format()
    fs.mkdir("/d")
    for name, data in files.items():
        fs.inject_file(name, data)
    return bytes(fs.img)


def pattern(seed: int, length: int) -> bytes:
    """The bytes PAT writes."""
    return bytes((seed + 13 * index) % 251 for index in range(length))


def boot_words(machine: SharedMachine, lines) -> str:
    return words(machine.run(['." RESULT: "', *lines, 'CR'], 400_000_000))


def names(fs: MP64FS) -> list[str]:
    return sorted(entry.name for entry in fs.list_files())


def test_the_boot_volume_takes_and_gives_copies_and_moves():
    source = pattern(31, 20000)
    machine, storage = boot_machine(
        boot_image(2048, {"src.bin": source, "mv.bin": source[:700]})
    )
    got = boot_words(machine, [
        ': T  32 9000 PAT  BIG 9000 S" /in.bin" VA @ PUT',
        '     S" /in.bin" VA @ S" /d/in.bin" VM @ SCR 4096 VFS-COPY R.',
        '     S" /src.bin" VM @ S" /src.bin" VA @ SCR 4096 VFS-COPY R.',
        '     S" /mv.bin" VM @ S" /mv.bin" VB @ SCR 4096 VFS-MOVE R.',
        '     S" /src.bin" VM @ S" /d/src2.bin" VM @ SCR 4096 VFS-MOVE R. ;',
        'T',
        ': U  31 20000 PAT  S" /src.bin" VA @ BIG 20000 SAME? .',
        '     S" /mv.bin" VB @ BIG 700 SAME? . ;',
        'U',
    ])
    assert got == "0 0 0 0 -1 -1", got
    fs = MP64FS(bytearray(storage.image_bytes))
    folder = fs.resolve_path("/d")
    assert fs.read_file("in.bin", parent=folder) == pattern(32, 9000)
    assert fs.read_file("src2.bin", parent=folder) == source
    assert names(fs) == ["d", "in.bin", "src2.bin"]


def test_the_boot_volume_takes_names_of_23_bytes_and_no_longer():
    """MP64FS reports names of at most 23 bytes, and a copy follows it: 23
    bytes copy to the boot volume and 24 are refused before anything is
    written, where the RAM volume takes both."""
    machine, storage = boot_machine(boot_image(2048, {}))
    got = boot_words(machine, [
        ': T  VM @ VFS-NAME-LIMIT .  VA @ VFS-NAME-LIMIT .',
        '     BIG 10 S" /f" VA @ PUT',
        '     S" /f" VA @ 23 NAME-PATH VM @ SCR 4096 VFS-COPY R.',
        '     S" /f" VA @ 24 NAME-PATH VM @ SCR 4096 VFS-COPY R.',
        '     S" /f" VA @ 24 NAME-PATH VB @ SCR 4096 VFS-COPY R. ;',
        'T',
    ])
    assert got == f"23 255 0 {INVALID} 0", got
    fs = MP64FS(bytearray(storage.image_bytes))
    assert names(fs) == ["d", "n" * 23]


def test_the_boot_volume_takes_and_gives_folders():
    """A folder copies onto the MP64FS boot volume and moves between its
    folders by one rename.  One that holds a name of 24 bytes, which MP64FS
    does not take, is refused, and leaves neither its final name nor its
    stage."""
    machine, storage = boot_machine(boot_image(2048, {}))
    got = boot_words(machine, [
        ': T  VA @ TREE',
        '     S" /tree" VA @ S" /tree" VM @ SCR 4096 VFS-COPY R.',
        '     S" /tree" VM @ TREE? .',
        '     S" /tree" VM @ S" /d/tree" VM @ SCR 4096 VFS-MOVE R.',
        '     S" /d/tree" VM @ TREE? .  S" /tree" VM @ HAS? .',
        f'     S" /tree" BASE!  BIG 5 S" /{"n" * 24}" AT VA @ PUT',
        '     S" /tree" VA @ S" /t2" VM @ SCR 4096 VFS-COPY R.',
        '     S" /t2" VM @ HAS? .  S" /t2" VM @ STAGE$ VM @ HAS? . ;',
        'T',
    ])
    assert got == f"0 -1 0 -1 0 {NAMETOOLONG} 0 0", got
    fs = MP64FS(bytearray(storage.image_bytes))
    # The reader lists every entry of the volume, in whichever folder: the
    # moved tree, and no stage of either copy.
    assert names(fs) == ["a.txt", "b.bin", "c", "d", "e", "sub", "tree"]
    tree = fs.resolve_path("/d/tree")
    assert fs.read_file("a.txt", parent=tree) == pattern(21, 700)
    assert fs.read_file("c", parent=tree) == b""
    sub = fs.resolve_path("/d/tree/sub")
    assert fs.read_file("b.bin", parent=sub) == pattern(22, 40000)


def test_the_boot_volume_running_out_of_space_keeps_no_stage():
    """64 sectors leave 25 KiB for data: a 30,000-byte copy runs out midway,
    and the stage's sectors come back for the next copy."""
    machine, storage = boot_machine(boot_image(64, {}))
    got = boot_words(machine, [
        ': T  33 30000 PAT  BIG 30000 S" /big" VA @ PUT',
        '     S" /big" VA @ S" /big" VM @ SCR 4096 VFS-COPY RP.',
        '     S" /big" VM @ HAS? .  S" /big" VM @ STAGE$ VM @ HAS? .',
        '     BIG 20000 S" /fits" VA @ PUT',
        '     S" /fits" VA @ S" /fits" VM @ SCR 4096 VFS-COPY R. ;',
        'T',
    ])
    assert got == f"{NOSPC} 0 0 0 0", got
    fs = MP64FS(bytearray(storage.image_bytes))
    assert names(fs) == ["d", "fits"]
    assert fs.read_file("fits") == pattern(33, 20000)
