# Places: how Desk and its applets see storage volumes

This is the design of record for places. It states the model, the words,
what each module does with them, and the order in which the work lands.
The section "Status" says which parts exist in the tree; everything else
is the accepted design for the slices still to come.

```forth
REQUIRE utils/fs/places.f
```

## The model

A **volume** is one mounted VFS instance with a name and a state. The
module that mounts it reports the outcome to the registry: attached, with
the instance, or refused, with the reason. `tui/platform/mp64fs-vfs.f`
reports `boot`, `utils/fs/system-volume.f` will report `system`, and
`utils/fs/user-volume.f` will report `user`. The settings volume is
mounted for one read and destroyed, so it never enters the registry.

A **place** is a folder of a volume with a name, a label and an access.
The name identifies it in the resource form, a person reads the label,
and the access is read-only or writable. Several places may share a
volume. System composition declares them, in the boot-script fragment the
image builder emits for the form it builds. A place is unavailable while
its volume is not attached or its folder is absent, and its status says
which: the volume is missing, the mount was refused, or the folder is not
there.

The **registry** lives in `utils/fs/places.f`. It keeps volumes and
declared places as linked heap records, records their state, and never
stops a boot: every word answers a status.

A **place set** is what one holder is given: an ordered list of places,
each with an access no wider than the place declares, and two marked
members. The **home** is the default writable place for the holder's own
records. Daybook, Grid, the Agent, Streams, the catalogs, the sandbox
store and the Practice head all write there, and none of them chooses it.
The **origin** is the place the holder's shipped files are read from: its
UIDL file, `pad.toml`, `fexplorer.toml` and UIDL media. Composition
builds one default set.

An applet obtains its set through the service lookup it already uses,
`CINST-SERVICE`, under the id `org.akashic.fs.places`. Desk's endpoint
receives the asking instance, passes it to one runtime word,
`PACT-PLACES`, and returns the answer. That word is where a Practice
takes effect: today it answers the activation's set for every caller, and
the Practice permission work replaces its body with a set per applet,
deciding there which places an applet sees and whether it may write. Desk
names no applet. The context field `CTX.PLACES` holds the activation's
set. An applet that runs with no endpoint at all, as a standalone shell
run does, takes the registry's default set; an applet whose endpoint
answers nothing has no places.

Code asks for the home, the origin or the listed places and never spells
a place's name, so the same code serves every build. The two builds
differ only in what composition declares. The linked build declares one
volume, `boot`, and one writable place over its root that is both home
and origin. The shipping form declares a read-only place on the system
volume as origin and writable places on the user volume, one of them the
home. The user volume holds two places for now, documents and records in
separate folders; that layout lives only in what composition declares,
and no applet or library may assume it.

### A place that is unavailable at boot

The registry records the state and composition applies the policy. The
boot stops with a message only when the origin is missing: the boot
fragment marks it with `PLACE-REQUIRED!` and aborts on `PLACES-CHECK`.
When the home is missing, Desk starts in recovery: `PACT-ACTIVATE` finds
no usable home, narrows every place to read-only, and each store opens as
a service that says why. Nothing falls back to another volume.

## The words

Composition side:

```forth
PLACES-VOLUME   ( name-a name-u -- volume ior )   find or create by name
PVOL-ATTACH     ( vfs volume -- ior )
PVOL-REFUSE     ( ior volume -- )
PVOL-DETACH     ( volume -- )
PLACES-DECLARE  ( name-a name-u folder-a folder-u access volume -- decl ior )
PLACE-LABEL!    ( label-a label-u decl -- ior )
PLACE-REQUIRED! ( flag decl -- )
PLACES-CHECK    ( -- decl ior )
PLSET-NEW       ( -- set ior )
PLSET-FREE      ( set -- )
PLSET-GRANT     ( access decl set -- place ior )
PLSET-HOME!  PLSET-ORIGIN!   ( place set -- )
PLSET-READ-ONLY!  ( set -- )
PLACES-DEFAULT! ( set -- )
PLACES-DEFAULT  ( -- set | 0 )
```

The access is `PLACE-READ-ONLY` or `PLACE-WRITABLE`. A declared volume is
unavailable until `PVOL-ATTACH`; `PVOL-REFUSE` records why a mount
failed, and `PVOL-DETACH` returns a volume to missing. `PLACES-CHECK`
answers the first required place that is unavailable, with its status, or
0 0. `PLSET-GRANT` refuses an access wider than the declaration's and a
second grant of the same place. `PLSET-READ-ONLY!` narrows every member,
which is what recovery does.

Applet side, where a `place` is the handle a set gives out:

```forth
PLSET-FIRST  PLSET-HOME  PLSET-ORIGIN   ( set -- place | 0 )
PLACE-NEXT      ( place -- place | 0 )
PLSET-FIND      ( name-a name-u set -- place | 0 )
PLSET-MEMBER?   ( x set -- flag )
PLSET-REVISION  ( set -- n )
PLACE-NAME  PLACE-LABEL   ( place -- a u )
PLACE-STATUS    ( place -- ior )
PLACE-WHY       ( place -- a u )
PLACE-WRITABLE? ( place -- flag )
PLACE-VFS       ( place -- vfs | 0 )
PLACE-ROOT      ( place -- inode | 0 )
PLACE-RESOLVE   ( path-a path-u place -- inode ior )
PLACE-HOLDS?    ( inode place -- flag )
PLACE-PATH      ( inode place buf cap -- len ior )
PLACE-OPEN      ( path-a path-u flags place -- fd ior )
PLACE-CREATE    ( path-a path-u place -- inode ior )
PLACE-MKDIR  PLACE-RM   ( path-a path-u place -- ior )
PLACE-RENAME    ( new-a new-u inode place -- ior )
PLACE-SYNC      ( place -- ior )
PLACE-BIND      ( path-a path-u place buf cap -- vfs len ior )
PLACE-BIND-WRITE  ( path-a path-u place buf cap -- vfs len ior )
PLACE-NAME-LIMIT  ( place -- n )
```

A path inside a place starts at its folder, so `/` is that folder and a
leading `/` changes nothing. A resolved entry must have the place's folder
among its parents, checked along the entry's parent chain, so neither
`..` nor a symbolic link leaves the place: a path that ends outside
answers `VFS-E-XDEV`. A changing word answers `VFS-E-READONLY` on a
read-only place and the place's status on an unavailable one. No word
removes or renames a place's own folder.

`PLACE-STATUS` is 0 for a usable place, `VFS-E-NOVOLUME` while the volume
is missing, the recorded refusal when its mount was refused, and the
resolver's answer when the folder is absent. `PLACE-WHY` is the same
state as a few words for a person, empty for a usable place. A place
keeps no entry of its folder: it resolves the folder when asked, so a
folder that another holder renames or the driver evicts is found again or
reported absent. `PLSET-REVISION` moves when the set's membership or
access changes and when any volume attaches, detaches or is refused, so a
list of places redraws.

Each volume has one current directory, which the resolver uses for
relative paths and the ext4 driver requires as the parent of a new entry.
The `PLACE-` words set it and restore it inside one `VFS-TRANSACTION`, so
applets and widgets never touch `V.CWD`. Giving the VFS words an explicit
parent would remove the bracket; it changes the driver and reruns its
whole unit, and is recorded as later work.

`PLACE-BIND` gives the instance and the volume path of an entry, or of a
new name in an existing folder of the place, to a library that keeps its
own descriptor, as the replacement, fixed-snapshot and generation-pair
libraries and the media widget do. The path it writes has no `..` and no
symbolic link in it, and a name that is a link without its target is
refused, since a write through it could leave the place. `PLACE-BIND`
serves a library that reads; `PLACE-BIND-WRITE` is the same for one that
will write, and a read-only place refuses it, so the place's access holds
for those libraries too. `PLACE-NAME-LIMIT` is the longest entry name the
place's volume takes, from the volume's own answer (`VSF.NAMEMAX`), or
the VFS's 255 when the volume gives none. `PLACE-VFS`
hands native code the instance, so the `PLACE-` words keep applets to
their places and enforce read-only among components that share one
address space; the sandbox, which requires a context with no place set,
stays the boundary against code that would reach around them.

### The resource form

A file handed from one applet to another is `vfs://<place>/<path>`. The
name is 1 to 255 bytes of lowercase letters, digits, `-`, `.` and `_`,
and is neither `.` nor `..`; `utils/fs/place-name.f` holds that rule
(`PLACE-NAME-VALID?`) for the registry and the form alike. In
`interop/resource.f`:

```forth
IRES-VFS!       ( place-a place-u path-a path-u value -- ior )
IRES-VFS-PARSE  ( uri-a uri-u -- place-a place-u path-a path-u flag )
```

A URI that names no place, as `vfs:/x` does, fails to parse.
`interop/place-resource.f` adds the words applets use:

```forth
IRES-PLACE!   ( path-a path-u place value -- ior )
IRES-PLACE@   ( value set -- path-a path-u place ior )
CINST-PLACES  ( instance -- set | 0 )
```

`IRES-PLACE@` looks the name up in the reader's own set, so a resource
naming a place the reader was not given fails, which is where a
Practice's choice takes effect. `CINST-PLACES` is the service lookup
described above.

### Copy and move

In `utils/fs/vfs-copy.f`:

```forth
VCOPY-INIT   ( src-a src-u src-vfs dst-a dst-u dst-vfs scratch-a scratch-u copy -- ior )
VCOPY-STEP   ( copy -- more? ior )
VCOPY-CANCEL ( copy -- ior )
VFS-COPY  VFS-MOVE      ( src-a src-u src-vfs dst-a dst-u dst-vfs scratch-a scratch-u -- ior )
PLACE-COPY  PLACE-MOVE  ( src-a src-u src-place dst-a dst-u dst-place scratch-a scratch-u -- ior )
```

`VFS-COPY` is the loop over `VCOPY-STEP`, which moves one chunk, so an
applet can also step a long copy from its tick. The copy refuses an
existing destination name. It writes a stage file in the destination
folder under the reserved `.s-` name that `VREPL-DERIVE-PATHS!` derives,
syncs, compares the stage with the source in halves of the caller's
scratch, renames the stage to the final name and syncs. The rename is the
commit: before it the final name does not exist, and a failure removes
the stage. The file never needs to fit in memory. `VFS-MOVE` inside one
instance is `VFS-RENAME-AT`. Across instances it is the copy, then
`VFS-RM` of the source and a sync; a failed delete reports that the copy
stands and the source was kept. The word copies files, and a folder copy
is a walk that calls it. A stage left by a crash is removed when the same
copy is retried and is otherwise a hidden file.

### The explorer widget

```forth
EXPL-NEW      ( rgn set -- widget )
EXPL-SELECTED ( widget -- inode place )    inode 0 on a place's own row
on-open and on-select callbacks  ( inode place explorer -- )
```

Its top rows are the set's places by label, each opening onto its
folder. An unavailable place shows its reason and stays closed, and a
read-only place refuses rename, delete and new. The name limit comes from
the volume (`VSF.NAMEMAX`). The rows are tree rows of the canonical
widget, mounted on an ordinary `<region>`, so the cell fallback and rich
output draw the same list with no UIDL annotation, scene or terminal call
added.

### Capacity

Volumes, places, sets and grants are linked heap records, so their number
follows need. The 255-byte name is an interface limit: one component of a
URI, equal to ext4's file-name limit, so any folder name can be a place
name. Labels and folders are stored at their length, a folder within
`VFS-PATH-MAX`.

## The selector goes

The VFS library keeps one process-wide current instance, and `VFS-OPEN`
opens on it while every other word takes its instance, so each caller
brackets its work. `VFS-OPEN` will take its instance, `VFS-NEW` will stop
selecting, and `VFS-USE`, `VFS-CUR` and `_VFS-CUR` will be deleted, so no
code can depend on them. Every site that brackets, restores or adopts the
selector passes an instance or a place instead: the replacement, access
and fixed-snapshot libraries (whose private-range check also starts at
the selector cell), the system-volume and settings mounts, the MP64FS
platform module, the Practice head, the credential vault, the catalog,
builder and loader, the shell's UIDL load, UIDL media sources, Desk's
hand-offs and every applet store. Stores take their set's home, shipped
files are read from the origin, and the prefix router `vfs-mount.f`,
which nothing requires, is deleted with its document and test.

## Order of work

1. One place, end to end, in the linked build: `places.f`, the resource
   form with every producer and reader, the explorer widget, File
   Explorer and Pad on a set, the service, `CTX.PLACES`, the boot
   fragment. `vfs.f` is untouched.
2. The selector goes and each writer gets its home. Stores take places;
   shipped files read from the origin. A source rule forbids the selector
   under `akashic/`.
3. Copy and move: `vfs-copy.f`, `PLACE-COPY`, File Explorer's paste.
4. The user volume attaches: the builder's user image on the machine's
   fourth storage unit, `user-volume.f`, the shipping form's places, and
   a boot without the user image.
5. The ext4 driver makes an inode group ready on first use.
6. File Explorer across volumes, opening with the run that confirms
   whether a sync is refused while a removed file is open.
7. The other writers on ext4: Daybook, Grid, the Agent, Streams, the
   catalogs, the sandbox store, the head.
8. The killed run: the simulator killed at chosen flushes during a save
   and during a copy's stage write and rename; each image passes the
   machine's own remount and the host tools' recovery, then `e2fsck`.
9. Both journeys, linked and shipping form.

Slices 2, 5 and 6 change files the `test_vfs_ext4` unit reads; they end
on patterns with a sample of every ext4 operation, and the whole unit
runs once after slice 8.

## Status

In the tree: `utils/fs/place-name.f` and `utils/fs/places.f`, tested by
`local_testing/test_places.py` on two RAM volumes. Nothing uses them yet.

## Open

- A sweep of stale copy stages at mount costs a folder walk per boot and
  is left out until measured.
- Explicit-parent VFS words in place of the current-directory bracket.
- The user volume's two places, documents and records, are the layout for
  now and may change.
- Whether the shipping form becomes the default build.
