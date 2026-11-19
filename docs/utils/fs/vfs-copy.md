# Copying and moving files and folders

`akashic/utils/fs/vfs-copy.f` copies and moves files and folders, inside one
volume or from one volume to another, and between [places](places.md). A
copy never shows a partial file or folder under its final name: it writes
the copy under a hidden stage name in the destination folder, reads the
stage back against the source, and only then renames the stage to the final
name.

```forth
REQUIRE utils/fs/vfs-copy.f
```

```forth
VCOPY-SIZE      ( -- n )
VCOPY-INIT      ( src-a src-u src-vfs dst-a dst-u dst-vfs scratch-a scratch-u copy -- ior )
VMOVE-INIT      ( src-a src-u src-vfs dst-a dst-u dst-vfs scratch-a scratch-u copy -- ior )
PLACE-COPY-INIT ( src-a src-u src-place dst-a dst-u dst-place scratch-a scratch-u copy -- ior )
PLACE-MOVE-INIT ( src-a src-u src-place dst-a dst-u dst-place scratch-a scratch-u copy -- ior )
VCOPY-STEP      ( copy -- more? ior )
VCOPY-CANCEL    ( copy -- ior )
VCOPY-PROGRESS  ( copy -- files-done files bytes-done bytes phase )
VFS-COPY        ( src-a src-u src-vfs dst-a dst-u dst-vfs scratch-a scratch-u -- ior )
VFS-MOVE        ( src-a src-u src-vfs dst-a dst-u dst-vfs scratch-a scratch-u -- ior )
PLACE-COPY      ( src-a src-u src-place dst-a dst-u dst-place scratch-a scratch-u -- ior )
PLACE-MOVE      ( src-a src-u src-place dst-a dst-u dst-place scratch-a scratch-u -- ior )
```

## The copy

A copy takes a regular file, named by a path on its instance and followed
through a final symbolic link, or a folder (see [Folders](#folders)), and
an absolute destination path on the destination instance, which may be the
same instance. It refuses a
destination name that already names an entry, of any kind. The bytes pass
through the caller's scratch, so a file of any size copies through a few
kilobytes of memory. In order, a copy:

1. opens the source and checks that the destination name is free;
2. removes the stage an earlier copy to the same name left, then creates
   the stage in the destination folder and writes the source into it, as
   much of the scratch as a step moves;
3. closes the stage and takes a barrier on the destination instance;
4. reopens the stage and compares it with the source, half of the scratch
   from each at a time, after checking that both are still the size the
   copy wrote;
5. renames the stage to the final name with `VFS-RN-NOREPLACE` and takes a
   barrier on the destination instance again.

A barrier is `VFS-BARRIER` ([vfs.md](vfs.md#sync-and-eviction)), the word a
checked replacement takes its barriers from: a `VFS-SYNC` on a binding whose
changes reach the medium only at a sync, as MP64FS's do, and nothing on one
with `VFS-CAP-DURABLE-MUTATIONS`, as ext4's staged writer has, where every
completed change is already on the medium. A copy to MP64FS therefore syncs
twice and a copy to ext4 not at all.

The rename is the commit. Before it the final name does not exist; after
it the final name holds every byte, read back. A name that another writer
took while the copy ran is refused by the rename itself, so the copy never
replaces a file. A failure before the rename closes the copy's files,
removes the stage and takes a barrier, so the destination holds nothing of
the copy.
If the stage cannot be removed either, as on a volume that a fault has
turned read-only, it stays as a hidden file until the same copy runs again.

### The stage's name

The stage's name is the reserved `.s-` name that `VREPL-DERIVE-PATHS!`
([vfs-replace.md](vfs-replace.md)) derives from the final path: `.s-`
followed by twenty base32 characters of the path's SHA3-256 digest, 23
bytes in all, in the destination folder. The copy and a checked
replacement therefore share one rule for companion names, and a stage's
name starts with a dot, as a hidden file's does. A power cut during a copy
leaves at most such a file, and running the same copy again derives the
same name and removes it in step 2. A stage that
is the source itself is refused with `VFS-E-INVALID`, and an entry under
the stage's name that is not a regular file keeps the name, refusing the
copy with `VFS-E-EXISTS`. Nothing sweeps stages at mount; [places.md](places.md)
leaves that out until a measurement shows a need.

The replacement library's path rule also bounds what a copy can write, and
it follows the destination volume: an absolute path of at most
`VFS-PATH-MAX` (4,096) bytes whose folder leaves room for the 23-byte stage
name, names no longer than the volume takes (`VFS-NAME-LIMIT`: 255 bytes on
ext4, 23 on MP64FS), and no final name in the reserved `.s-`, `.b-` and `.m-`
namespace. A destination that breaks the rule answers `VFS-E-INVALID`
before anything is written. A file whose name is longer than 23 bytes
therefore copies and moves between ext4 volumes and within one, and is
refused on its way to MP64FS.

### Stepping a copy

Every copy and move runs as steps in a copy record of `VCOPY-SIZE` bytes
that its caller keeps, with the scratch, until it ends. `VCOPY-INIT`
starts a copy of a file or a folder and `VMOVE-INIT` a move;
`PLACE-COPY-INIT` and `PLACE-MOVE-INIT` bind their paths in places first,
as `PLACE-COPY` and `PLACE-MOVE` do. Each refuses at once what it can
refuse before anything is written: a destination the rules refuse, a
source of the wrong kind, a final name that exists. The caller then calls
`VCOPY-STEP` until `MORE?` is false, and the step that ends the copy
answers its `IOR`; an applet does so from its loop, a step a pass, and
Desk keeps answering in between. `VFS-COPY`, `VFS-MOVE`, `PLACE-COPY` and
`PLACE-MOVE` run the same steps to the end in a record of the library's
own.

Each step does one piece of work: a listing, a folder made, a file
opened or closed, a chunk written or compared, a barrier, a rename, or
an entry removed. A file of `n` bytes through a scratch of `s` bytes
takes `⌈n/s⌉` writing steps, one step that syncs and reopens the stage,
`⌈n/(s/2)⌉` comparing steps and the step that renames: ten steps for
10,000 bytes through 4,096 bytes of scratch. The scratch holds bytes only
inside a step, so its owner may use it between steps. Each copy keeps its
state in its own record, its walk, its copy of the source's path and its
replacement descriptors, so two copies may step in turn. Between steps a
file's copy keeps the source and the stage open, which holds their
entries however long it waits; a folder's walk holds no entry at all.
The comparison reads the source again, so another writer's change to
bytes already copied fails it, and a change of the source's size fails
the check before it.

`VCOPY-PROGRESS` answers the files and bytes done, the files and bytes in
all, and what the copy is doing: `VCOPY-P-COUNTING` while a folder's
files are counted, `VCOPY-P-COPYING` while they are written,
`VCOPY-P-CHECKING` while they are read back and the stage renamed,
`VCOPY-P-FINISHING` once the copy stands and a move removes its source,
`VCOPY-P-GIVING-UP` while a failed or cancelled copy removes what it
wrote, and `VCOPY-P-IDLE`. The figures done count again from zero when
the reading back begins; a file copy counts one file and its bytes.

`VCOPY-INIT` and `VMOVE-INIT` refuse a record whose copy is still running
with `VFS-E-BUSY`. A step after a copy has ended, by success or failure,
answers `0 0`. `VCOPY-CANCEL` gives up a copy before its commit: a file's
at once, closing its files, removing the stage and syncing, and answering
the first of those that failed; a folder's by closing its files and
leaving its walk at once, after which the following steps remove the
stage tree and the last of them answers 0, or the failure that kept part
of the stage. A move whose copy stands removes its source to the end:
`VCOPY-CANCEL` then answers `VFS-E-BUSY` and changes nothing. On a record
with no running copy it answers 0, and a record that was never started
answers `VFS-E-INVALID` to it and to `VCOPY-STEP`.

## Folders

A copy of a folder takes it with all it holds, at any depth, by the
file's protocol at the scale of the tree:

1. the source is a folder, the final name is free, and the destination's
   folder exists and is neither the source nor inside it;
2. a walk of the source counts its files and bytes, and refuses a link, a
   device, a name or a path the destination does not take, before
   anything is written;
3. a stage an earlier copy to the same name left, a folder or a file, is
   removed with everything in it, and the stage folder is made;
4. a walk of the source makes each folder in the stage and copies each
   file into it, a scratch at a time;
5. one barrier on the destination instance;
6. a third walk reads every file of the stage back against its source,
   half of the scratch from each, and checks that each folder is there;
7. the stage folder is renamed to the final name with `VFS-RN-NOREPLACE`,
   and a barrier taken.

The rename is the commit, as for a file: a failure before it removes the
stage tree and takes a barrier, so the final name never holds part of a
folder, and a folder copy takes two barriers however many files it holds.
The walk keeps names and paths, never a VFS entry, between its steps: it
lists each folder's entries once into a block of its own and looks each
path up again when it uses it, so neither another writer nor the cache's
eviction leaves it holding a stale entry. Each step is one
`VFS-TRANSACTION`, as a file's are.

A folder copies its files and folders. A symbolic link or a device in it
refuses the copy with `VFS-E-UNSUPPORTED`, since copying a link could
reach outside its place and a device has no bytes to copy. Every name in the
tree must be one the destination volume takes, and every path, as it will
be once the stage is renamed, no longer than `VFS-PATH-MAX`; a name or a
path that breaks this answers `VFS-E-NAMETOOLONG`, and the stage goes. A
folder of names longer than 23 bytes therefore copies between ext4 volumes
and is refused on its way to MP64FS.

## Moving

`VFS-MOVE` moves a regular file or a folder, named by its own name rather
than through a final link, and takes the same destinations a copy takes.
Inside one instance it is one `VFS-RENAME-AT` with `VFS-RN-NOREPLACE` into
the destination folder, then a barrier: the file, or the folder with all it
holds, keeps its storage and no stage is written. The source's entry is
held from its lookup to the rename, a file's by opening it and a folder's
by pinning it. The VFS refuses to move a folder beneath itself with
`VFS-E-INVALID`.

Across two instances a move checks the source and copies it as `VFS-COPY`
does. A file is then removed and a barrier taken on the source's instance.
A folder is first renamed to its own stage name, the one
`VREPL-DERIVE-PATHS!` derives from its path, so it leaves its folder at once,
and that hidden tree is then removed, an entry a step, and a barrier taken;
a hidden tree an earlier move left under that name is removed first. A move
whose copy fails leaves the source as it was.

Between the steps of a move across instances other applets run. A file of
the source that another writer changes after the copy read it back is
removed with the rest once the copy stands, so the copy keeps the bytes it
read. A caller that steps such a move while other writers may change the
source accepts that; a move inside one instance is one rename and is not
exposed to it.

## Answers

Every word answers a VFS ior, 0 for success. An answer that carries
`VFS-IOR-F-PARTIAL` means the destination stands though a later step
failed:

- the barrier after a copy's rename, so the copy may not have reached the
  medium yet;
- a move's removal of its source, or the barrier after it, so the source may
  still be there, under its name, or, for a folder whose removal began,
  hidden under its stage name; a move inside one instance, whose rename
  succeeded, answers this way when only its barrier failed.

Every other failure leaves nothing at the destination and the source as it
was, and never carries the flag, whatever flags a binding set on the
failure it reported. The answers a caller sees most:

| Answer | When |
|---|---|
| `VFS-E-EXISTS` | The destination name holds an entry, or took one while the copy ran |
| `VFS-E-NOENT` | The source, or the destination's folder, does not exist |
| `VFS-E-NOTDIR` | A folder on the destination path is a file |
| `VFS-E-INVALID` | The destination path breaks the replacement library's rule for its volume, the scratch is under two bytes, an instance or the record is 0, a stage is the source, or a folder would go inside itself |
| `VFS-E-NAMETOOLONG` | A name in a folder is longer than the destination volume takes, or a path in it would pass `VFS-PATH-MAX` |
| `VFS-E-UNSUPPORTED` | A folder holds a symbolic link or a device |
| `VFS-E-BUSY` | `VCOPY-INIT` or `VMOVE-INIT` was given a record whose copy is still running, or `VCOPY-CANCEL` a move whose copy stands |
| `VFS-E-NOSPC` | The destination ran out of space |
| `VFS-E-CORRUPT` | The stage did not read back as the source, or the source changed size, or a folder's source changed, while the copy ran |
| `VFS-E-IO` | A binding failed, or a binding operation threw |
| `VFS-E-READONLY` | The destination instance, or a place, is read-only |

## Places

`PLACE-COPY` binds the source path in its place with `PLACE-BIND` and the
destination path in its place with `PLACE-BIND-WRITE`, then copies the
volume paths those words answer. `PLACE-MOVE` binds the source with
`PLACE-BIND-WRITE` as well, since a move changes the source's place, then
moves. A read-only destination place therefore refuses a copy with
`VFS-E-READONLY`, and a read-only source place refuses a move; a path that
leaves its place answers `VFS-E-XDEV`, and an unavailable place answers its
status. Both places may be the same place, or two places of one volume, in
which case a move is a rename. File Explorer's paste copies and moves this
way across the places of its set
([fexplorer.md](../../tui/applets/fexplorer/fexplorer.md)).

## Guards

The words hold this module's guard for their whole length, and take the
replacement library's guard to name the stage before they take the VFS's
for the files, which is the order every checked replacement takes. A
caller must therefore not hold a `VFS-TRANSACTION` around them. Each step
runs inside one `VFS-TRANSACTION`, so the VFS's guard is free between the
steps of a stepped copy and while `VFS-COPY` moves from one step to the
next. A throw from a binding inside a step is caught: the step gives the
copy up as it would on a failure and answers `VFS-E-IO`.

## Tests

`local_testing/test_vfs_copy.py` runs copies and moves between two RAM
volumes whose binding fails on demand, through places over both, and with
the MP64FS boot volume as source and destination, which it reads back with
MegaPad's own MP64FS reader. It covers an existing name and a name taken
during the copy, a destination that runs out of space midway, a stage that
does not read back, failed syncs before and after the rename, a failed
rename, a throwing write, cancel, a retried copy after a stage a crash left,
a move whose delete fails, and a move inside one volume. It also counts the
syncs a copy takes on the RAM binding (two) and on the same binding declared
durable (none), copies a name of 255 bytes and a path of 304, and copies a
name of 23 bytes to the boot volume while refusing one of 24. Its folder
tests copy a tree of three levels, with an empty file, an empty folder and a
file ten times the scratch, between the volumes and inside one, with two
syncs; refuse an existing name, a folder into itself and a missing
destination folder; give the stage tree up on each of the file's failures
and leave the copy standing when only the last barrier fails; clear a stage
folder a crash left; move a folder inside one volume by one rename and
across volumes, where a failed removal leaves the source hidden and the
next move clears it; copy and move folders between places; and copy a folder
onto the boot volume, move it between its folders, and refuse one that holds
a name of 24 bytes. Its stepping tests step a folder copy and read
`VCOPY-PROGRESS` through it, three files of 40,700 bytes counted, written
and read back in more than forty steps with the final name appearing only
at the last; cancel a folder copy midway, after which the steps remove the
stage and leave no file open; step two folder copies in turn; and refuse
to cancel a move across volumes once its copy stands, and move a folder
inside one volume in one step. `local_testing/test_vfs_copy_ext4.py` runs copies and
moves of files and of a folder to, from and within the 64 MiB ext4 fixture
volume, including a file copy that runs out of space on a volume with 39
free blocks, and checks the medium with the pinned `e2fsck` and `debugfs`.
Power cuts during a copy's stage write and rename are the killed-run
qualification of [places.md](places.md), order of work, item 8.
