# akashic/utils/fs/system-volume.f — the system volume and its modules

```forth
REQUIRE utils/fs/system-volume.f
```

The system volume is the ext4 volume on the machine's system storage unit,
KDOS's `SYSTEM-UNIT`. It holds the system's modules as individual files, and
nothing writes it while the system runs: the unit is write-protected, and the
mount is the ext4 driver's read-only one. This module mounts the volume and
fills the [module source](vfs-module-source.md) through which KDOS's `LOAD`
and `REQUIRE` read from it.

| Word | Stack | |
|---|---|---|
| `SYSVOL-MOUNT` | `( arena -- ior )` | Mount the system volume from `arena`. |
| `SYSVOL-VFS` | `( -- vfs \| 0 )` | The mounted volume; 0 before a mount. |
| `SYSVOL-SOURCE` | `( -- source )` | The volume's module source. |

## What a boot does

The boot volume holds KDOS, the ext4 driver and this module. A boot loads
them from there, mounts, and selects the source:

```forth
524288 A-XMEM ARENA-NEW THROW  SYSVOL-MOUNT THROW
SYSVOL-SOURCE MODULE-SOURCE!
REQUIRE tui/applets/desk/desk.f     \ a path on the system volume
```

From then on a module name is a path on the system volume, and a `REQUIRE`
inside a module starts at that module's own folder. `FS-MODULE-SOURCE
MODULE-SOURCE!` returns loading to the boot volume and `SYSVOL-SOURCE
MODULE-SOURCE!` selects the system volume again. KDOS remembers each file it
has loaded together with the source it came from, so switching between the
two reads no module twice.

Mounting selects nothing by itself. The boot selects the source with KDOS's
own `MODULE-SOURCE!`, and code that only reads files from the volume takes
`SYSVOL-VFS` and leaves module loading alone.

## The arena

`arena` is the mount's storage and stays the caller's. The VFS and the ext4
driver keep the mount's records and its cache of entries and names inside it.
The volume is mounted once and stays mounted; a second `SYSVOL-MOUNT` answers
`VFS-E-BUSY` and leaves the first mount in place.

## Failures

`SYSVOL-MOUNT` returns the first failure it meets and mounts nothing:

| `ior` | Cause |
|---|---|
| `BD-E-NO-MEDIA` | the machine has no system volume attached |
| another `BD-E-` or `VOL-E-` code | the unit could not be opened |
| `VFS-E-NOMEM` | `arena` is too small for the mount |
| another `VFS-E-` code | the volume is not an ext4 volume the driver reads |

A failed mount gives the unit back, so a later call can mount it, and it
leaves the module source and the current VFS as they were. A successful mount
also leaves the current VFS as it found it.

`SYSVOL-SOURCE` throws `VFS-E-NOVOLUME` before a mount. A boot that went on
after a failed mount therefore stops at that word and never selects a source
that reads nothing.

## An image that boots this way

`local_testing/akashic_tui.py` builds any profile's images this way with
`--system-volume`. The profile's module closure goes onto an ext4 image
written beside the boot image, `<name>-system.img`: each module a plain file
at its module path, with the repository's text and its comments. The boot
image keeps KDOS, its system modules, the profile's resources and its
samples. In the place of the profile's modules it holds the closure of this
module, deployed as the profile deploys source: checked cold-source chunks
for the Desktop, plain files for a profile that is not linked. `autoexec.f`
loads that closure, runs the sequence above, and then runs the profile's own
`REQUIRE` lines, which KDOS resolves as paths on the volume. `smoke`, `serve`
and `accept` attach the volume as the third storage unit, and
`physical_desktop_acceptance.py --system-volume` runs the canonical journey
on a Desktop built this way. The option is off unless it is given.

The canonical journey passes on such a Desktop. File Explorer's wheel step
needs a root listing at least three rows longer than its table shows, and a
linked Desktop's source chunks supply those rows. A Desktop built this way
has few chunks in its root, so its boot image also carries the sample
documents (`local_testing/sample_documents.py`). They ship where the modules
live on the system volume, since there nothing else makes the root long, and
they stand for what a user volume will hold. A linked Desktop's image is
unchanged.

The volume is made by the pinned e2fsprogs that `AKASHIC_E2FSPROGS_TOOL_DIR`
names, with the ext4 fixtures' profile
(`local_testing/fixtures/ext4-profile/manifest.json`): 4 KiB blocks, 256-byte
inodes, a 4 MiB journal and the feature set the driver is qualified against.
Its UUID and directory hash seed derive from the modules' paths and digests,
and its times are the profile's fixed time, so the same sources give the same
image. The build checks the finished volume with `e2fsck` and against the
profile's superblock facts, as the fixtures are checked.

Its size follows from its content and from two things the driver requires of
any volume it mounts:

- Each file takes its bytes rounded up to whole blocks and each directory one
  block. The journal is added, and an eighth of that sum for the filesystem's
  own structures apart from its inode tables.
- A block group spans eight times the block size in blocks, and every group
  carries an inode table for one inode per 16,384 bytes of a full group,
  whatever the volume's size. The driver's admission refuses another count.
- A volume has at least two block groups. The driver takes the backup
  superblock of the second group as its witness when it checks the journal,
  at every mount, read-only ones included.

The volume has as many groups as its content with their inode tables fills,
and as give every file and directory an inode; it reaches far enough into
its last group to hold that group's inode table, and its size is rounded up
to a whole MiB. With 4 KiB blocks a group is 128 MiB, so the smallest volume
is 131 MiB, most of it never written: the image file is sparse. With 1 KiB
blocks a group is 8 MiB and the smallest volume 10 MiB.

A module loaded this way is evaluated a line at a time by KDOS's loader, so
it keeps the rules of a plain file: no line longer than 255 bytes, and a
comment or a string that closes on its own line. Loads nest as `REQUIRE`
lines do, and KDOS nests at most sixteen.
