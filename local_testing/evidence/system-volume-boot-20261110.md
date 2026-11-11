# Modules from an ext4 system volume — 2026-11-10

Part 2 step 3 of the release plan (fantasy-engine's `dev/PLAN.md`) teaches
KDOS to load modules from ext4 volumes. This records Akashic's side of it:
the module source over a mounted VFS, the whole runs of the ext4 unit that
the step before it waited for, the module that mounts the system volume, and
the Desktop's boot from that volume as an option of the image builder, with
its measured cost. MegaPad's side, the loader's hook, the storage units and
the faults repaired on the way, is in MegaPad's
`docs/module-loading-and-storage-units-2026-11-11.md`.

Every run was made one at a time. A physical Desktop journey is
`physical_desktop_acceptance.py` on the native simulator, under its
900-second watchdog and 3.5 GiB guard. A test unit is a test file run by
`python3 -m fantasy_engine.testing`. Emulator figures are instructions and
system cycles of the exact emulator; simulator times are host time and say
nothing about a device.

## The module source (fc8b0fb2)

KDOS's `LOAD` and `REQUIRE` find and read a file through the current module
source (MegaPad d8a92092; MegaPad's `docs/module-source-contract.md` is the
interface). [`utils/fs/vfs-module-source.f`](../../docs/utils/fs/vfs-module-source.md)
makes a mounted VFS such a source. Its tests load a tree of modules from an
ext4 image by nested relative paths, also with the VFS cache limited to two
entries, because a load resolves other modules' paths and the VFS evicts
whenever a path is resolved. They run in the native simulator, which loads
the whole ext4 driver in 0.6 s and mounts the volume in 0.3 s now that the
driver's one anonymous definition has a name; the emulator takes about 1.2
billion steps to load it. One test loads the same tree on the emulator.

Plain module files keep one rule that linked chunks never had to: a comment
or a string closes on its own line, since KDOS evaluates a file a line at a
time. The driver had broken it in one stack comment since db9cccc4, and the
test of that rule had failed on main unseen until fc8b0fb2 put the comment on
one line.

At MegaPad d8a92092 and Akashic fc8b0fb2 the physical Desktop journey passed,
and so did the 214 test units the changes reach.

## The ext4 unit's whole runs

The whole `test_vfs_ext4` unit had not run since the writer's last slices. It
ran at f068fdd1 and MegaPad 7eba16c8 in 89 minutes, where it had taken
2 h 46 min: 832 cases passed, one was skipped and two failed. Both were
rename-over tests that still counted a whole folder's entries in the VFS
cache, which has held only the names a caller resolves since ext4 began to
look names up one at a time (def0488c). They passed at the commit before it
and failed from it on, and no slice's own run had selected them; c3d127b7
counts what the cache holds.

The unit then passed whole at fc8b0fb2 and MegaPad d8a92092, with the loader
hook under it, in 86 minutes, and once more at fc8b0fb2 and MegaPad e42b0d1c
in 97 minutes. It peaks at 5.1 GiB of memory, above the 4 GiB at which the
working rules ask before a run.

## The system volume's mount (14f39dec)

[`utils/fs/system-volume.f`](../../docs/utils/fs/system-volume.md) is the
piece of a boot that uses the machine's third storage unit, the system disk
(MegaPad f69a52f8). `SYSVOL-MOUNT` mounts the system disk's ext4 volume
read-only from an arena the boot supplies and fills a module source for it,
which the boot hands to KDOS's `MODULE-SOURCE!`. Its tests run that sequence
in the simulator and on the emulator and load a tree of modules by path from
the third unit.

On the merged state (MegaPad c723d121, Akashic 14f39dec) the physical Desktop
journey passed, and so did 275 test units and the ext4 sample of 65 tests.

## The Desktop's boot from the system volume (6832aa50 and 8c06d3f3)

The Desktop boots from the system volume as an option of the image builder.
`--system-volume` puts a profile's modules on an ext4 image beside the boot
image, each a plain file with the repository's text. The boot volume keeps
KDOS, its system modules, the resources and the samples, and holds the
closure of the mounting module in place of the profile's modules, deployed as
the profile deploys source. `autoexec.f` loads that closure, mounts the
volume, selects it as the module source and then runs the profile's own
`REQUIRE` lines. The option is off unless given, and a default build is
unchanged: the boot images of five profiles hold the same files as before.
[`local_testing/README.md`](../README.md) describes the option's use.

The image is made with the pinned e2fsprogs from the ext4 fixtures' profile
and sized from its content. Two rules of the driver set its smallest size:
every block group carries a full group's inode table, and a mount takes the
second group's backup superblock as its journal witness, a read-only mount
included. A volume of 4 KiB blocks is therefore at least 131 MiB, where the
modules need 18 MiB.

On the merged state (Akashic 8c06d3f3, MegaPad c723d121) the unchanged
journey passed, and so did the 27 test units the change reaches and the ext4
sample.

### The measured boot

Measured for `desktop-apt1` on the emulator at MegaPad c723d121, from reset
to the boot line that says the guest is entering Desk, in millions of
instructions read between boot lines at a resolution of two million:

| Phase | Linked chunks | System volume |
|---|---|---|
| BIOS and KDOS | 56 | 56 |
| networking, rich terminal, cold-source loader | 294 | 292 |
| the volume's driver, 24 modules in 8 chunks | | 404 |
| the mount | | 12 |
| the profile's 310 modules | 2,642 | 3,558 |
| the rest | under 2 | 2 |
| total | 2,992 | 4,324 |

In system cycles the totals are 3,716 M and 5,388 M, 37 and 54 seconds at
the SoC's 100 MHz. The modules are 52 chunks of 6.32 MB compacted source in
one column and 309 files of 9.53 MB in the other. KDOS's loader spends about
15,000 instructions on a line whether it holds code or a comment, in both
boots, so the plain files' 53,000 comment and blank lines are most of the
difference: the same modules compacted on the volume loaded in 812 M fewer.
Resolving all 310 paths and reading every file through ext4 costs about
200 M. The driver has no block cache and asked the disk for 11,986 single
blocks, which the emulator does not charge as a card would. With 1 KiB blocks
the volume is 16 MiB and the boot 444 M longer. In the simulator the boot
takes 9.3 s where the linked one takes 2.5 s. The mount used 190,640 bytes of
its 524,288-byte arena.

### The journey with the option

The physical journey passes its first 27 stages with the option and stops at
File Explorer's wheel step, which needs a root listing three rows longer than
its table shows. The 52 chunk files in the boot volume's root had supplied
those rows without the step naming them. In a build made only to check this,
with the root padded to its usual length, the whole journey passed with the
modules loaded from the system volume.

Decided on 2026-11-11: a Desktop built with the option carries ordinary
sample documents, 24 short notes and lists, so that its root listing is long
by its own content (a4fb1679, a644d65d, e9dc6f74). A linked Desktop's image is
unchanged: its chunk files already make the root long, and the documents
would take 24 of the 42 entries its boot volume's directory has free. At
e9dc6f74 and MegaPad 26b98fd9 the journey passed with the option and without
it.

### What would cut the boot's cost

In the order the measurements suggest: the loader skipping comment and blank
lines (up to 0.8 G, bounded by the compacted run); the per-line cost itself,
which is nearly all of both boots; loading only the driver's read-only part
at boot (most of 404 M); and a cache for the driver's metadata blocks with
data read in extent runs (reads fall below a thousand).

Decided on 2026-11-11: the loader's per-line cost is cut first, in MegaPad,
and whether the option becomes the default is decided on the boot measured
after that.
