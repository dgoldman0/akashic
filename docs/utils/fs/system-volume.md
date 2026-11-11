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
