# The user volume

The user volume is the ext4 volume on the machine's fourth storage unit,
unit 3, which KDOS names `USER-UNIT` and MegaPad attaches from
`--user-storage` or a session's `user_image`. It holds the user's documents
and the applets' records, and it is the volume the running system writes.
`akashic/utils/fs/user-volume.f` mounts it and reports it to the places
registry ([places.md](places.md)) as the volume `user`.

```forth
REQUIRE utils/fs/user-volume.f

USERVOL-MOUNT  ( arena-bytes -- ior )
USERVOL-VFS    ( -- vfs | 0 )
```

## Mounting

`USERVOL-MOUNT` opens the unit, mounts the volume through ext4's
staged-write binding (`EXT4-STAGED-WRITE-NEW`), and gives the writer what it
needs before its first change: a clock, the machine's `EPOCH@` in
milliseconds, and a workspace for its credits. The credits are 16 metadata
blocks and 2 revoke records for one transaction (`USERVOL-META-CREDITS`,
`USERVOL-REVOKE-CREDITS`), and as many data blocks as the volume and the
machine allow. The mount tries 128 (`USERVOL-DATA-CREDITS-MAX`) and halves
down to 16 (`USERVOL-DATA-CREDITS-MIN`) until the volume's journal admits the
profile and the extended memory holds the workspace the driver sizes for it,
and `USERVOL-DATA-CREDITS` answers what it took. More data blocks speed only
large writes. On the emulator a 256 KiB save took 4.1 s with 16 data blocks,
1.9 s with 64 and 1.7 s with 128, while every save of 64 KiB or less cost the
same from 64 blocks up
([`user-volume-writer-profile-20261119.md`](../../../local_testing/evidence/user-volume-writer-profile-20261119.md)).
The workspace for 128 is 164,576 bytes, against 45,408 for 16, and a 64 MiB
volume's journal of 4,096 blocks admits 128, so there the memory decides. The
mount's own arena, `ARENA-BYTES` of extended
memory, holds the VFS's and the driver's records for the mount; composition
passes 524,288 bytes, the arena the costs were measured with, of which the
mount uses 194,168 (measured on 2026-11-19). The cache of entries and names
takes its pages from the heap within its budget
([vfs.md](vfs.md#sync-and-eviction)).

The module then reports the outcome, and nothing it does stops a boot:

| What the unit holds | Answer | The volume `user` |
|---|---|---|
| a volume the driver mounts | 0 | attached, with the instance |
| no medium | `VFS-E-NOVOLUME` | missing: its places report `volume missing` |
| a damaged volume, or one of another format | the driver's or the unit's ior | refused with that ior: its places report `mount refused` |

A mount that fails gives back the writer's workspace, the instance with its
arena, the volume and the unit, so a later call can try again. A volume
`user` that another instance holds already keeps it, and the call answers
`VFS-E-BUSY`, as it does once this module has mounted the volume.

## The volume's format

The image builder writes the user volume beside the boot image as
`<image>-user.img` with `--user-volume`, in the format the staged writer
takes: the pinned ext4 profile's features, 1 KiB blocks, 256-byte inodes,
one inode for each 16 KiB of a full block group, and at least two groups.
`--user-volume-mib` sets its size, 64 MiB by default and a whole number of
at least 16. The volume holds the folders of the shipping form's places,
`/documents` and `/records`, and the sample documents in `/documents`. Its
identity follows from its size and content, and the build checks it with the
pinned `e2fsck`. `local_testing/README.md` describes the option.

## The places composition declares on it

With the user volume the boot declares the shipping form's places in place
of the one place over the boot volume:

- `system`, read-only, over the root of the volume that holds the profile's
  shipped files, the origin. That volume is the system volume when the build
  has one, which then also holds the profile's resources, and the boot
  volume otherwise. It is required, so a boot without it stops with a
  message.
- `documents`, writable, over `/documents` on the user volume.
- `records`, writable, over `/records` on the user volume, the home.

A boot whose user volume is missing or refused goes on: the home is then
unavailable, and Desk's activation starts in recovery with every place of its
set read-only. The layout lives only in what composition declares
(`local_testing/akashic_tui.py`, `_user_volume_boot_lines`), and no applet or
library assumes it.

## Tests

`local_testing/test_user_volume.py` mounts a fresh volume the builder makes
and saves documents in it under a 199-byte name and in a path of more than
255 bytes, which the host's `e2fsck` then passes; it mounts nothing, a damaged
copy and a volume of another format, and reads each outcome from the
registry. It then boots Desk with Pad as the builder makes it with the user
volume, without it, and with a system volume whose image is missing, and
saves a document in the documents place the way Pad saves one, which the
host's `e2fsck` passes and a second boot reads back.
