# The writable user volume: decisions and what a write costs — 2026-11-15

Part 2 of the release plan (fantasy-engine's `dev/PLAN.md`) gives every
configuration a writable ext4 user volume for documents and records. This
note is Akashic's record of that work as it stood on 2026-11-15: the
decisions on how the ext4 driver and the save routine serve the volume, the
measured cost of writing to it, and the driver work the measurement set.
Nothing described here as work to come had been built on that date.

## Decisions

**Inode groups are made ready on first use** (Decided, 2026-11-11). The
writer makes an inode group ready when it first needs one, as it does a
block group. Until then a volume takes only the files of the groups its
builder made ready, about 500 on a volume from `mke2fs`, whatever its
size.

**A sync lands while a removed file is still open** (Decided, 2026-11-15,
after a run confirmed the case). A sync on a writable mount answers busy
while a removed file is still open, and the driver refuses every create on
the volume meanwhile; File Explorer's preview keeps files open. The driver
is to land the sync, take other writes, and keep the removed file's record
until the file closes.

**A save asks the filesystem what a rename guarantees** (Decided,
2026-11-15). A save asks the filesystem under the file whether a rename
there survives a power cut whole. Where it does, as on ext4, the save
writes the new content beside the file, reads it back, and renames it over
the file in one journal transaction. Where it does not, as on MP64FS, the
save keeps its present protocol of a marker, a backup and a sync after
each step ([`utils/fs/vfs-replace.md`](../../docs/utils/fs/vfs-replace.md)),
which was built for a filesystem without a journal. Both stay, since a
writable place may sit on either kind, and applets call the same word,
`VREPL-REPLACE`. The rename capabilities a binding declares today
(`VFS-CAP-ATOMIC-RENAME`, `VFS-CAP-RENAME-REPLACE`) are set by MP64FS and
the RAM binding as well as ext4, so the choice needs a capability of its
own that only a journaled binding sets.

## How the cost was measured

The figures come from the exact emulator at Akashic `86d817ea`, with
MegaPad `fc1e660b` for every table except the growth table, which ran at
MegaPad `5dd6fe1e`; the 64 MiB runs gave identical counts at both. A
scratch script built on the helpers of `test_vfs_ext4.py` restored a
machine from that file's cold-compiled snapshot, loaded `sha3.f` and
`vfs-replace.f`, and ran each operation as one interpreted line. The script
is not kept in the repository.

Instructions and system cycles are the emulator's own counts for the line,
1,883 instructions of line overhead included, and the guest's
`PERF-CYCLES` agreed within 3,000 cycles. Seconds are cycles divided by
10^8, the processor time of a 100 MHz device. The emulator completes
storage transfers and flushes at once, so a device's storage latency comes
on top of every figure. Writes and flushes were counted at the storage
device's command hooks, and each write was one 1 KiB block. Transactions
are the JBD2 commit blocks among the writes.

The volume is the 64 MiB test fixture with a 2 KiB `/doc.txt` added by the
host's `debugfs`, mounted with an arena of 524,288 bytes and a writer
profile of 16 metadata, 16 data and 2 revoke credits unless a row says
otherwise. Every completed run unmounted cleanly and passed the pinned
`e2fsck -f -n`.

## Mount, first write and sync

| Step | Instructions | Cycles | Seconds | Reads | Writes | Flushes |
|---|---|---|---|---|---|---|
| Staged mount | 21.65 M | 27.74 M | 0.277 | 144 | 0 | 0 |
| Bind clock and writer | 0.20 M | 0.29 M | 0.003 | 4 | 0 | 0 |
| 100-byte overwrite, first after mount | 48.61 M | 65.11 M | 0.651 | 496 | 21 | 17 |
| 100-byte overwrite after a sync | 23.00 M | 29.75 M | 0.298 | 216 | 21 | 17 |
| 100-byte overwrite, journal already active | 21.36 M | 27.67 M | 0.277 | 182 | 15 | 11 |
| Ownership proof, called directly | 25.64 M | 35.38 M | 0.354 | 280 | 0 | 0 |
| `VFS-SYNC` alone | 11.06 M | 14.30 M | 0.143 | 73 | 6 | 7 |
| Clean unmount | 0.23 M | 0.31 M | 0.003 | 0 | 0 | 0 |

The first write of a mount carries the ownership proof, which the
difference between the first two overwrites also gives (35.35 M cycles).
Each overwrite is one transaction. A write that follows a sync pays 2.09 M
cycles, 6 writes and 6 flushes to activate the journal again.

The mount used 204,648 bytes of its arena, and 494 created names raised
that to 351,072. The writer's workspace follows its profile: 13,424 bytes
at 1/1/0, 28,384 at 16/0/2, 45,408 at 16/16/2, 96,480 at 16/64/2 and
300,768 at 16/256/2.

## A save

Checked replacement, `VREPL-REPLACE`, is the save of Pad, Daybook, Grid and
most stores. Each row returned status 0.

| Case | Instructions | Cycles | Seconds | Writes | Flushes | Transactions | Syncs |
|---|---|---|---|---|---|---|---|
| Existing 2 KiB, new 2 KiB | 385.9 M | 494.8 M | 4.95 | 319 | 210 | 12 | 6 |
| Existing 2 KiB, new 64 KiB | 464.3 M | 594.7 M | 5.95 | 441 | 243 | 15 | 6 |
| Existing 64 KiB, new 64 KiB | 463.0 M | 593.2 M | 5.93 | 441 | 243 | 15 | 6 |
| File absent, 2 KiB | 251.8 M | 323.0 M | 3.23 | 217 | 140 | 8 | 4 |

The six syncs take 85.8 M cycles. With the journal's activation after each,
syncs come to about 98 M of the 495 M cycles and 78 of the 210 flushes of
the first row; the twelve transactions, about 33 M cycles each, are the
rest.

The generation pair is the save of the Practice head and the Agent's
conversation: open or create the inactive slot, truncate it, write, close,
sync.

| Case | Profile | Instructions | Cycles | Seconds | Writes | Flushes | Transactions |
|---|---|---|---|---|---|---|---|
| 416 bytes, slot created | 16/16/2 | 57.9 M | 74.4 M | 0.74 | 57 | 35 | 2 |
| 416 bytes, slot rewritten | 16/16/2 | 57.2 M | 73.4 M | 0.73 | 53 | 35 | 2 |
| 256 KiB, slot created or rewritten | 16/16/2 | 390.8 M | 499.1 M | 4.99 | 612, 608 | 200 | 17 |
| 256 KiB, slot created or rewritten | 16/256/2 | 159.0 M | 203.6 M | 2.04 | 312, 308 | 35 | 2 |

File Explorer's operations, each with the `VFS-SYNC` it makes (14.30 M
cycles, 6 writes and 7 flushes of each row):

| Operation | Instructions | Cycles | Seconds | Writes | Flushes | Transactions |
|---|---|---|---|---|---|---|
| `VFS-MKFILE` | 38.4 M | 49.4 M | 0.49 | 36 | 24 | 1 |
| `VFS-MKDIR` | 43.4 M | 55.7 M | 0.56 | 40 | 24 | 1 |
| `VFS-RENAME` | 35.9 M | 46.4 M | 0.46 | 30 | 24 | 1 |
| `VFS-RM`, empty file | 38.1 M | 49.2 M | 0.49 | 36 | 24 | 1 |
| `VFS-RM`, empty folder | 98.9 M | 126.3 M | 1.26 | 72 | 46 | 3 |
| `VFS-RM`, 2 KiB file | 98.7 M | 126.0 M | 1.26 | 72 | 46 | 3 |

## Growth with the volume's size

The three volumes were built with the profile's `mke2fs` options and given
the fixture's files and `/doc.txt`; the 64 MiB one is byte-identical to the
volume of the tables above. Each cell gives system cycles and seconds.

| Volume | Groups | Mount | Arena used | Ownership proof | Overwrite after a sync | `VFS-SYNC` |
|---|---|---|---|---|---|---|
| 64 MiB | 8 | 27.7 M, 0.28 s | 204,648 | 35.4 M, 0.35 s | 29.8 M, 0.30 s | 14.3 M, 0.14 s |
| 256 MiB | 32 | 120.9 M, 1.21 s | 231,144 | 63.3 M, 0.63 s | 138.4 M, 1.38 s | 66.5 M, 0.66 s |
| 1 GiB | 128 | 901.6 M, 9.02 s | 337,128 | 353.9 M, 3.54 s | 991.0 M, 9.91 s | 483.5 M, 4.84 s |

An overwrite makes 21 writes and 17 flushes and a sync 6 and 7 at every
size, while the mount's reads were 144, 838 and 3,311. The time of a write
and of a sync therefore grows through computation over the whole volume,
with the same blocks written. The cause had not been located on this date.
By these figures a checked replacement would take about 20 s at 256 MiB and
150 s at 1 GiB; that is a calculation from twelve overwrites and six syncs,
and was not run. The 1 GiB run peaked at 1,524 MiB of host memory.

## Limits and defects the run showed

**The inode limit.** 494 files were created in the root, the number of free
inodes in group 0. The next `VFS-MKFILE?` returned `VFS-E-UNSUPPORTED` with
detail 18 (`EXT4-D-WRITE-POLICY`), and `VFS-MKDIR` the same. The driver's
`_XC-FI-SAW-UNINIT` flag was set, `STATFS` still reported 3,584 free
inodes, and the host's `dumpe2fs` showed group 0 full with all 3,584 in the
seven `INODE_UNINIT` groups. The 494 creates took 34.8 M cycles each.

**Sync with a removed file open.** `VFS-RM` of an open file returned 0 and
left one orphan record. `VFS-SYNC` then returned `VFS-E-BUSY` twice, with
no I/O, and a `VFS-MKFILE?` in that state returned unsupported with detail
5 (`EXT4-D-RECOVERY`) and wrote nothing. `VFS-CLOSE?` returned 0 in two
transactions and cleared the record, after which `VFS-SYNC` returned 0.

**A fresh volume stops the machine.** On a 64 MiB volume that held only
`lost+found` and `/doc.txt`, the ownership proof ran 42.9 billion
instructions, about 2^32 turns of a ten-instruction loop, after 433 reads,
the last of them the inode-table block that holds `/doc.txt`'s inode. The
guest then sat in the BIOS at address 0x8E2 with interrupts off, printed
nothing and ignored pending input. The direct proof call and a
`VFS-MKFILE` as first write each ended this way, and an overwrite did so
on fresh volumes of all three sizes. The same volumes with the fixture's
files work, which is why no test had met it. The loop had not been located
on this date, nor which of the fixture's files prevents it.

**A truncate that changes nothing is refused.** On a slot just created,
`VFS-TRUNCATE` to zero returned unsupported with detail 18. `_EXT4-TRUNCATE`
refuses it deliberately: the generic VFS marks the volume dirty after any
successful truncate, and a dirty volume with an inactive journal refuses
later mutations. `runtime/vfs-practice-head.f` and the Agent's
`storage/vfs-conversation.f` exit on a nonzero truncate result, so their
first save to an absent slot would fail on ext4; that follows from their
source and was not run.

**The Agent's interval.** The Agent saves its conversation at most every
500 ms during a turn, and a 256 KiB save takes 2.0 to 5.0 s.

## Work that follows

- The save routine gains the rename over the target on a journaled binding,
  with a test that cuts storage after each write of a save.
- One round of driver work takes the fresh volume, inode groups on first
  use, the cost that grows with the volume, and the sync with a removed
  file open. The whole `test_vfs_ext4` unit runs once at its end.
- The truncate that changes nothing, and the Agent's interval, are settled
  when the Practice head and the Agent's store move to the user volume.
