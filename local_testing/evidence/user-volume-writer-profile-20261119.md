# The user volume's writer profile: what a save costs at each size — 2026-11-19

Slice 7 of the places work (`docs/utils/fs/places.md`) sets the user volume
writer's transaction size from measurements of the writers' saves. The
writer takes a profile when the volume mounts: the metadata blocks, data
blocks and revoke records one journal transaction may hold. A write larger
than the data blocks of one transaction becomes several transactions. This
note records what the saves the volume's writers make cost with 16, 32, 64,
128 and 256 data blocks, and the rule the mount follows since.

## The rule

The mount takes the most data blocks, from 128 down by halves to 16, that
the volume's journal admits and whose workspace the extended memory holds,
with 16 metadata blocks and 2 revoke records (Decided, 2026-11-19;
`akashic/utils/fs/user-volume.f`, `docs/utils/fs/user-volume.md`). The
profile is a resource the machine and the volume bound, not a fixed
setting: the driver checks each profile against the volume's journal and
sizes its workspace, and a smaller journal or a fuller memory takes a
smaller profile. 128 is where the largest save was fastest.

## How it was measured

The figures come from the exact emulator at Akashic `a9820d59` and MegaPad
`232c3a4e`. A scratch script, kept outside the repository as
`~/.cache/fantasy-engine/notes/user-volume-writer-meas-20261119.py`, builds
on the helpers of `test_vfs_ext4.py`: it restores a machine from that file's
cold-compiled snapshot, loads `sha3.f` and `vfs-replace.f`, and runs each
operation as one interpreted line. Each profile starts from a fresh copy of
the 64 MiB test fixture, with 1 KiB blocks, a journal of 4,096 blocks and a
2 KiB `/doc.txt` that the host's `debugfs` adds, mounted through the staged
writer with an arena of 524,288 bytes.

Each operation ran twice on the same file, and the tables give the second
run; the first differed by at most 0.02 s. Seconds are system cycles divided
by 10^8, the processor time of a 100 MHz device. The emulator completes
storage transfers and flushes at once, so a device's storage latency comes on
top of every figure, and every transaction makes 13 to 17 flushes. Writes
and flushes were counted at the storage device's command hooks, each write
one 1 KiB block; transactions are the JBD2 commit blocks among the writes.
After each profile the volume was unmounted and the host's `e2fsck -f -n`
passed it.

The operations are the shapes of the writers' saves, not the stores
themselves. A whole-file save opens or creates the file, rewinds it,
truncates it to nothing, writes the bytes, closes it and syncs the volume, as
the Agent's conversation store and the Practice head do; 416 bytes is the
head's size and 256 KiB the largest conversation snapshot. A store commit
writes N 4 KiB pages into a 64 KiB page file, appends 512 bytes to a segment
file, syncs, writes one 4 KiB root slot and syncs again, which is the shape of
a persistence store's commit in Streams and Library.

## What a save costs

| Data blocks per transaction | Workspace | 416 B save | 4 KiB save | 64 KiB save | 256 KiB save | 3-page commit | 12-page commit |
|---|---|---|---|---|---|---|---|
| 16 | 45,408 B | 0.54 s | 0.55 s | 1.28 s | 4.10 s | 1.17 s | 2.86 s |
| 32 | 62,432 B | 0.55 s | 0.55 s | 0.91 s | 2.59 s | 1.17 s | 2.87 s |
| 64 | 96,480 B | 0.55 s | 0.55 s | 0.74 s | 1.91 s | 1.18 s | 2.88 s |
| 128 | 164,576 B | 0.55 s | 0.56 s | 0.74 s | 1.69 s | 1.19 s | 2.90 s |
| 256 | 300,768 B | 0.56 s | 0.57 s | 0.75 s | 1.85 s | 1.20 s | 2.94 s |

The 256 KiB save took 17 transactions with 16 data blocks, 9 with 32, 5 with
64, 3 with 128 and 2 with 256. Every save up to 4 KiB took 2 transactions and
35 flushes at every size, and the 64 KiB save took 2 transactions from 64
blocks up.

## What the figures show

- **Data blocks matter only to large writes.** A save of 4 KiB or less costs
  about 0.55 s at every size, two transactions for the truncate and the
  write. The 64 KiB save stops gaining at 64 blocks, and the 256 KiB save is
  fastest at 128. With 256 blocks it is 0.16 s slower than with 128, for
  136 KB more workspace; the cause was not established.
- **A store commit pays per write call.** The writer makes one journal
  transaction for each write call, about 0.2 s each, so a 12-page commit
  takes 14 transactions and 2.9 s whatever the profile. Grouping a commit's
  writes into one transaction would need a driver feature; places.md lists
  it as open.
- **The Agent's saves.** At least 0.55 s a save while a reply streams set the
  Agent's save budget the same day: a streaming run saves again no sooner
  than nine times as long as its last save took, and never within 500 ms
  (`docs/tui/applets/agent/persistence.md`).

## Not measured

The checked replacement, the save of Pad and of the stores bound through
`PLACE-VREPL!`, answered `VREPL-S-INVALID` at every size in this script,
while the same save passes in `test_vfs_replace_ext4.py`. The cause was not
found on this date, and the replacement's cost was not measured. Its writes
are whole files like the saves above, so its cost is expected to follow the
same sizes.
