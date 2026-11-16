# The ext4 driver for everyday writes on a user volume — 2026-11-16

The record of 2026-11-15,
[`user-volume-20261115.md`](user-volume-20261115.md), measured what writing to
a writable ext4 user volume costs and set one round of driver work: a fresh
volume that stopped the machine, inode groups made ready on first use, a sync
refused while a removed file is open, and a cost that grows with the volume.
This note records that round as it ended: what each change does, the evidence
behind it, the runs and their results, and what remains. The 2026-11-15 record
stays as it was written.

## The first half: fresh volumes and inode groups

**A fresh volume no longer stops the machine** (Akashic `fc1b31d2`). The
mount's ownership proof sorts its list of external xattr blocks before it
claims each one, and a volume as `mke2fs` leaves it has none. The sort's pass
began at index one with the empty list's count of zero as its limit, and a
counted loop on this machine ends only when its index meets its limit, so the
pass ran on through the memory after the list until the guest stopped in the
BIOS. On Akashic `e554385c` with MegaPad `5dd6fe1e`, a direct call of the
proof on a 64 MiB volume holding `lost+found` and one host-written file stood
in that sort after 150 million instructions, its index 240,484 cells past the
list and rising; all three fresh-volume forms of the record stood there. The
sort now returns at once for fewer than two cells. The fixture images carry a
file with an external xattr block, which is why no earlier test met it.

**An inode group is made ready by its first inode** (`a3653f52`, `0ac0525c`,
`a79f09b5`). `mke2fs` leaves every group but the first `INODE_UNINIT`, and the
writer took inodes only from groups whose bitmap was in use, so a volume from
the profile's options took about 500 files whatever its size. The writer now
builds such a group's inode bitmap itself, clears the flag and restates the
descriptor's counts and checksums in the transaction that creates the file or
folder, following `ext4_read_inode_bitmap` and `__ext4_new_inode` of Linux
v6.8 and checked against e2fsprogs 1.47.4. A group whose descriptor does not
count every inode free is refused as corrupt. Power-cut matrices cut every
write of a create that readies group 1 (30 writes) and of a folder that
readies both sides of group 4 (34 writes), and a 256 MiB case readies group
16 through the second descriptor block.

## A sync with a removed file held open

A file or folder whose last link goes while a descriptor holds it keeps its
record in the orphan file until the descriptor closes. Until this round the
writer refused everything else meanwhile: `VFS-SYNC` answered busy, and every
create, write or removal answered unsupported with the recovery detail
(detail 5), because each transaction required an empty orphan union before and
after its home writes. File Explorer's preview holds files open, and a save by
rename over a target that another descriptor holds leaves exactly such a
record, so the next save could not even create its stage file.

**What the kernel and e2fsck allow.** The decision of 2026-11-15 was to land
the sync, take other writes, and keep the removed file's record until the file
closes. Before building it, the sources settled what state a landed volume
with a live orphan record may be in. They were read from Linux v6.8
(`git.kernel.org` at tag `v6.8`: `fs/ext4/super.c`, `fs/ext4/orphan.c`,
`fs/jbd2/journal.c`) and from the pinned e2fsprogs 1.47.4 release archive,
whose SHA-256 matched the profile's
(`fd5bf388cbdbe006a3d3b318d983b2948382440acc85a87f1e7d108653e8db0b`).

- `ext4_freeze` empties the journal through `jbd2_journal_flush`, which ends
  with `jbd2_mark_journal_empty` writing `s_start` zero; it then clears
  `needs_recovery`, and clears `orphan_present` only when
  `ext4_orphan_file_empty` holds. `ext4_unfreeze` sets both again. The kernel
  therefore itself lands a journal beside live orphan-file records, with
  `ORPHAN_PRESENT` set, whenever a frozen volume has a removed file open.
- `ext4_setup_super` sets `needs_recovery` and `orphan_present` at every
  read-write mount; `ext4_put_super` clears both at unmount; `ext4_sync_fs`
  only commits the running transaction.
- `__ext4_fill_super` counts `orphan_present` among the reasons a mount
  needs recovery, and every read-write mount runs `ext4_init_orphan_info`
  and then `ext4_orphan_cleanup`, which walks every slot of every orphan-file
  block whatever the journal state and truncates or deletes each record's
  inode.
- e2fsck's `check_if_skip` (`e2fsck/unix.c`) never reports a volume with
  `orphan_file` and `orphan_present` set as clean; it checks it.
  `release_orphan_inodes` (`e2fsck/super.c`) releases the legacy list and then
  each orphan-file record before pass 1, and clears `orphan_present`, unless
  the check is read-only. Under `-n` it does not run, so pass 1 reports the
  record's inode as deleted with zero dtime (`PR_1_ZERO_DTIME`), pass 5 the
  bitmaps that still count its storage, and the end of the run the orphan
  block as not clean (`PR_6_ORPHAN_BLOCK_DIRTY`), as on any ext4 volume with a
  removed file still open.

Landing as decided is therefore within what both tools take: the landed state
is the one `ext4_freeze` leaves, the next mount of either the kernel or this
driver reclaims the record, and `e2fsck -f -p` releases it. The pinned
`e2fsck -f -n` is clean wherever the orphan file is empty; on a landed volume
that holds a record it reports that record, which the tests establish by
running `-f -p` on a copy, requiring it to release exactly the record's
inodes and report nothing else, and then running `-f -n`.

**What the driver does now** (Akashic `2cbbece5`). The mounted writer
retains the union: modern records only, at most the runtime plan's capacity
of them, with `ORPHAN_PRESENT` set exactly while it holds one. At a sync,
`VFS-SYNC` lands the journal in the usual six writes and seven flushes; the
landing's superblock clears `RECOVER` and keeps `ORPHAN_PRESENT`, and the
reloads on either side of the landing must find the same union. Between
operations, creates, writes, saves and removals go on: a generic transaction
requires the union its home writes leave to equal the one its pre-home reload
found, and another removal takes the first empty orphan-file slot beside the
retained records. At the last close, the record drains as before; a close
that finds the journal landed stages its first transaction without writing
and then activates the journal, and `ORPHAN_PRESENT` is cleared only when the
union empties. A mount after a power cut completes an interrupted landing
with `ORPHAN_PRESENT` kept and then drains every record. Writes, truncates and
setattr still refuse the removed file itself. The tests that pinned the old
behaviour (busy at sync, detail 5 at a create, the open-target case of
`test_vfs_replace_ext4.py`) now pin the new one, and
`docs/utils/fs/vfs-replace.md` gives the new account of a save over an open
target.

**Tests.** `local_testing/test_vfs_ext4_retained_orphan.py` is new. Its
behaviour cases land a sync beside a held removed file and check the medium
as above, save twice over a held target and remove a second held file and
drain each record on its own close, and run a truncate of a 17,000-block file
across transactions beside a retained record. Its power-cut matrix records a
landing beside a record, a save whose victim drains beside it, a second
landing, the last close and a landing with the orphan file empty; it cuts
every write of each landing, and of each reopening of the journal, whole and
after its first sector, and cuts the rest on either side of each commit block
and after every eighth write. A fresh mount recovers every state to the
save's old or new file, no record and a clean e2fsck.

## A reload reads again only what a write reached

Every checkpoint, landing and journal activation authenticates the mount
from the medium again. The 2026-11-15 record measured those reloads growing
with the volume, and the work was to find where the cycles go, remove work
that is truly redundant, and state for each removal how its redundancy is
proved, without weakening any check.

**Where the cycles went.** A debug copy of the driver, which never lands,
wrapped 70 of its words in `PERF-CYCLES` counters and printed each word's
calls and inclusive and exclusive system cycles for each step. It ran on
Akashic `2cbbece5`'s driver with MegaPad `977ef95e` at 64 and 256 MiB, and
the counters add about 4 % to every figure it gives. At
256 MiB, a 100-byte overwrite took 145.2 million cycles, of which counting
the orphan file took 92.2 million in two counts, the backup validation 19.0
million in two, the journal validation 13.5 million in three, the group
validation 6.0 million in two, the static-role table 3.0 million and the
comparison of orphan unions 1.7 million; the write itself took 8.4 million.
A sync took 70.3 million, 46.1 of them in one orphan count. A save by rename
took 706.1 million, of which 346.9 million went to reading orphan-file
blocks, 2,590 of them in six counts, an index and the free-slot search. At
64 MiB the same overwrite took 32.5 million, the largest share in the journal
validation (11.5 million) and the orphan count (7.3 million).

Three causes stood out. The orphan count read every block of the orphan file
(32 blocks at 64 MiB, 256 at 256 MiB, 1,024 at 1 GiB) in every complete
reload, and each block's lookup proved again the allocation of the whole
extent the file lies in, a check that itself grows with the file. The
backup validation loaded and checked every primary descriptor once for each
backup copy, the number of groups times the number of copies. And the union
comparison that this round's sync work added took the CRC32C of the 32 KiB
plan table at each checkpoint even when the union was empty.

**What was removed, and why each removal is redundant** (Akashic
`da9d46c7`). Every write now passes a write watch before it reaches the volume,
and nothing else writes a mounted volume, which is the premise the driver's
map epoch already rests on.

- *A lookup proves its inline extent node once per epoch.* A node that passed
  a plain proof in the current map epoch under the same validation limit is
  not proved again. That proof reads only the node's bytes, the geometry and
  the descriptors and block bitmaps of the groups its blocks lie in, which no
  write keeping the epoch reaches, so it would pass again; claim, release and
  audit scopes, the protocol scope, a transaction's images and the read gate
  always prove it.
- *The orphan count and plan stand while no write reaches the orphan file.*
  Both are functions of the orphan file's inode record and the blocks its map
  names. The orphan watch keeps the span of sectors a depth-zero orphan map
  covers and counts every write that meets it, every write to another volume
  or while it keeps no span, and every preparation that finds another record,
  each record named by the CRC32C of its bytes. A count under the same record
  with that count unmoved stands; a plan stands when the context still names
  the table it was built in with the same slots, union count and CRC32C. Each
  record's inode is still validated and the legacy chain still walked. The
  free-slot search uses a standing count or plan and reads only the chosen
  block. A count also skips the entry-by-entry pass over a block whose
  entries are all zero, which adds nothing.
- *The backup validation stands while nothing it reads or compares has
  changed.* It reads only the backup superblocks and descriptor blocks and
  compares them with the primary superblock's fixed fields and the primary
  descriptors' three metadata locations. The watch counts every write that
  meets a backup copy; the group validation that precedes it chains every
  group's primary locations into a CRC32C; and the primary superblock's fixed
  fields are compared with a kept copy. Any change validates every copy in
  the old order, so a changed primary location or fixed field is refused
  against the backups as before.
- *Two empty unions compare by their counts.* A union's identity is its
  record count and, when it holds records, the plan table's CRC32C.

Every home a checkpoint writes is still read back and compared whole, and the
journal is validated as before. The new case
`test_reloads_read_again_only_what_a_write_reached` records the sectors of
every read: the mount reads each of the 32 orphan-file blocks exactly once
(twice before) and every backup copy; the writes, syncs and creates after it
read neither again, but for the two blocks of group 1's copy that every
journal validation reads as the witness of the journal's location; removing a
file with storage writes the orphan file and the reloads after it count every
block again; and the next write reads none.

**Before and after.** The same steps ran on the same images, built with the
profile's `mke2fs` options and population as the 2026-11-15 record built its
own, whose mount and ownership-proof figures they reproduce exactly, each
with a 2 KiB `/doc.txt`. Before is Akashic `2cbbece5` and after `da9d46c7`,
both with MegaPad `977ef95e`, in millions of system cycles:

| Step | 64 MiB before | 64 MiB after | 256 MiB before | 256 MiB after |
|---|---|---|---|---|
| Mount | 27.7 | 22.5 | 121.0 | 44.9 |
| First write's ownership proof | 35.4 | 35.4 | 63.3 | 63.3 |
| 100-byte overwrite, journal active | 29.3 | 18.2 | 135.3 | 26.0 |
| 100-byte overwrite after a sync | 31.4 | 20.3 | 140.1 | 30.8 |
| Sync | 15.8 | 9.4 | 68.0 | 12.5 |
| 2 KiB save by rename, journal landed | 170.8 | 128.4 | 684.9 | 208.2 |
| 2 KiB save by rename, journal active | 162.1 | 124.5 | 623.2 | 200.4 |

The "before" figures match the 2026-11-15 record's, plus the 1.5 million
cycles a sync and the 1.6 to 1.7 million an overwrite gained when the union
comparison arrived with the sync work.

At 1 GiB the measurement ran once, on `da9d46c7` with MegaPad `977ef95e`.
The mount took 136.6 million cycles, an overwrite after a sync 71.2 million
and a sync 23.4 million, where the 2026-11-15 record measured 901.6, 991.0
and 483.5 million on Akashic `86d817ea` with MegaPad `5dd6fe1e`. The
ownership proof took 354.0 million, as it did then. A 2 KiB save by rename
took 494.1 million cycles with the journal landed and 472.7 million with it
active. The volume passed the pinned `e2fsck` afterwards, and the run peaked
at 2.8 GB of host memory, held mostly by the 1 GiB image in the host process.

**Stopped: the journal map's workspace check.** Each journal validation,
three in every checkpoint, takes the CRC32C of the whole journal-map
workspace: one cell for every journal block and a uniqueness table twice
that size, 96 KiB for the 4,096-block journal all three measured volumes
have, at about 25 cycles a byte through the CRC feed. On the debug copy after
this round, those three checks took 7.4 million of the 21.0 million cycles an
overwrite after a sync took at 64 MiB, and of the 32.6 million at 256 MiB:
the largest single cost left in an everyday write. The check guards the
map the driver writes journal blocks through against a change by anything but
its own build; this machine has no memory protection, and on a mismatch the
driver rebuilds the map. Removing or thinning it would change what the writer
checks, so it stays, and the options are left to a decision: (1) keep it as
it is; (2) check the workspace once per checkpoint rather than at each of its
three validations, saving about 4.9 million cycles an overwrite, with the
window between two validations of one checkpoint no longer checked;
(3) hold the journal's map as its extents, a few cells for a journal in one
extent, so the same whole-workspace check costs almost nothing, a larger
change to the replay and revoke code that reads the map; or (4) give the CRC
engine a bulk feed in the BIOS, which speeds every CRC the driver takes, a
MegaPad change.

**Left as they are.** The same debug copy, run on the committed reload work,
shows where an everyday write's cycles go now. At 256 MiB a 2 KiB save by
rename takes 217.5 million cycles: 61.8 million in fifteen journal
validations, 37.1 million of them the workspace check above; 44.8 million in
2,578 descriptor loads, most of them the group validation and the static-role
table, which each complete reload and each new map epoch run over every group;
and 41.8 million in reading 801 orphan-file blocks, two counts and an index,
because the save's victim enters the orphan file and leaves it again. Skipping
the groups no write reached needs a record of which groups' descriptors and
bitmaps each write meets and a kept count for each group, and making the
orphan counts after the victim incremental needs a kept count for each orphan
block; both follow the same proof as the work above and are left for a later
round. The first write's ownership proof, once per mount by design, is
unchanged at 35.4 and 63.3 million cycles.

## Loops that begin at index one

The first half found four counted loops that start at index one and take
their limit from a count. A counted loop on this machine ends only when its
index meets its limit, so a count below one would run such a loop past its
limit, as the empty xattr list ran the sort. Each count was traced to where it
is set. None can arrive below one, and nothing was changed.

- `_EXT4-DD-SELECT-ROUTE` loops to an indexed directory's active entry count.
  That count is set in two places only, both from `_EXT4-DX-COUNT` just after
  a validator accepted the block: the root through `_EXT4-VALIDATE-DX-ROOT`
  in `_EXT4-DD-AUTH-HTREE-ROOT`, and a level-one node through
  `_EXT4-VALIDATE-DX-NODE` in `_EXT4-RD-LOAD-NODE`. Both validators call
  `_EXT4-VALIDATE-DX-ENTRIES`, which refuses a count of zero as corrupt. Its
  three callers, `_EXT4-LOOKUP-HTREE` (twice) and `_XC-AUTH-INDEXED-PARENT`,
  authenticate the root, or load the node, before they route.
- `_EXT4-READDIR-HTREE` loops to the directory's logical block count. Its one
  caller, `_EXT4-RD-WORK`, reaches it only for an indexed directory, and the
  loop's first step, `_EXT4-DD-AUTH-HTREE-ROOT`, reads logical block 0
  through `_EXT4-DD-LOAD-LOGICAL`, which refuses any block at or past that
  count. The count is therefore at least one whenever the loop runs.
- `_XI-BRANCH-BASE` loops to a legacy map's branch level. Its one caller,
  `_XI-FIND`, calls it with levels 3, 2 and 1 and leaves its loop when the
  level reaches zero, before the call.
- `_XC-NODE-ROUTE` loops to a walked index node's entry count, which
  `_XC-AUTH-DEPTH1` sets from `_EXT4-DX-COUNT` right after
  `_EXT4-VALIDATE-DX-NODE` accepted the node; that is its one caller.

`_EXT4-DD-REQUIRE-ACTIVE-HASHES` has the same loop shape and refuses a zero
count itself before its loop.

## Runs

The static set is the source-rule tests (`-k test_ext4_` in
`test_vfs_ext4.py`), `test_ext4_profile.py`, `test_forth_line_delimiters.py`
and both refactor ratchets with their tests. In this round's second half it
ran as two invocations, the source-rule selection on `test_vfs_ext4.py` alone
(36 cases) and the other files whole (43), 79 cases in all; the first half's
rows give the counts that half recorded. The sample is the standing set of 22
test functions of `test_vfs_ext4.py`, 25 cases. Every run used MegaPad's main
checkout read-only; the table names the commit each used.

| Akashic | MegaPad | Run | Result |
|---|---|---|---|
| `e554385c` | `5dd6fe1e` | reproduction of the fresh-volume stop | all three forms stood in the sort |
| `fc1b31d2` | `5dd6fe1e` | the new cases; static set; sample | passed; 74 passed; 25 passed |
| `0ac0525c` | `5dd6fe1e` | the new cases; static set; sample | passed; 74 passed; 25 passed |
| `a79f09b5` | `977ef95e` | `test_vfs_ext4_user_volume.py` whole; static set | 13 passed in 20 min 24 s, 1.07 GiB peak; 74 passed |
| `cf8d6697` (merge with the save by rename) | `977ef95e` | physical Desktop journey, linked and `--system-volume --token-modules`; sample; test tool's wide run | passed; 25 passed; 309 units passed, the whole ext4 unit left out |
| `cf8d6697` with the sync work uncommitted | `977ef95e` | the changed cases of `test_vfs_ext4.py` and `test_vfs_replace_ext4.py` | 14 passed in 5 min 42 s, 1.9 GB peak |
| same | `977ef95e` | `test_vfs_ext4_retained_orphan.py`: the three behaviour cases; the power-cut matrix | 3 passed in 3 min 3 s, 1.0 GB; 5 passed in 26 min 54 s, 1.0 GB |
| same | `977ef95e` | static set; sample; the two cases that check `e2fsck -f -p`'s report, in their final form | 79 passed; 25 passed in 9 min 38 s, 2.4 GB; 2 passed in 3 min 40 s |
| `2cbbece5` (the sync work) | `977ef95e` | the reload profile on a debug copy, 64 and 256 MiB; the reload measurement, 64 and 256 MiB | as above |
| `da9d46c7` (the reload work, run on the working tree just before the commit) | `977ef95e` | the reload measurement, 64 and 256 MiB; static set; the new case; sample | as above; 79 passed; passed in 36 s (it fails on `2cbbece5` at its first check); 25 passed in 4 min 10 s, 2.4 GB |
| `da9d46c7` | `977ef95e` | the reload profile on a debug copy, 64 and 256 MiB; the reload measurement at 1 GiB | as above; as above, 2 min, 2.8 GB peak |
| `da9d46c7` | `977ef95e` | `test_vfs_replace_ext4.py` whole; `test_vfs_ext4_user_volume.py` whole; `test_vfs_ext4_retained_orphan.py` whole | 11 passed in 5 min 17 s, 1.0 GB; 14 passed in 17 min 25 s, 1.1 GB; 8 passed in 15 min 33 s, 1.0 GB |

No run skipped a case.

## The checks before the merge

These ran one at a time on `efddbd54` with MegaPad `977ef95e`, and the last
on `0ad9e8a7`.

- The physical Desktop journey passed as the default linked build (158 s) and
  with `--system-volume --token-modules` (171 s).
- The test tool's wide run took 310 units from the main record, the whole
  ext4 unit apart, and 309 passed. `test_token_equivalence.py` failed on
  eight bytes of four words that the reload work added: `_EXT4-BKM-SPACE`,
  `_EXT4-OV-CRC`, `_EXT4-OF-CRC` and `_EXT4-OC-CRC` keep each mounted
  volume's own superblock fields and orphan checksums, and the two boots
  that test compares mount different volumes. `0ad9e8a7` adds the four words
  to the test's list of such state by their exact names, and the test then
  passed in 191 s.
- The whole `test_vfs_ext4` unit passed in 5,164 s (86 minutes), at a peak
  of 5.4 GiB.

The emulator Desktop smokes were not run; they stay deferred.
