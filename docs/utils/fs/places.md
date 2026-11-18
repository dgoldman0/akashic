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
reports `boot` and `utils/fs/user-volume.f` reports `user`. Composition
reports `system`: `utils/fs/system-volume.f` mounts the system volume
early in the boot, from a boot volume that carries only what that mount
needs, and the registry loads afterwards from the system volume itself.
The settings volume is mounted for one read and destroyed, so it never
enters the registry.

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
each with an access no wider than the place declares, and three marked
members. The **home** is the default writable place for the holder's own
records. Daybook, Grid, the Agent, Streams, the catalogs, the sandbox
store and the Practice head all write there, and none of them chooses it.
The **origin** is the place the holder's shipped files are read from: its
UIDL file, `pad.toml`, `fexplorer.toml` and UIDL media. The **documents
place** is where a person's documents go: Pad takes a path with no place
of its own there, and File Explorer opens there. Composition builds one
default set and marks all three.

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

Code asks for the home, the origin, the documents place or the listed
places and never spells a place's name, so the same code serves every
build. The two builds differ only in what composition declares. The
linked build declares one volume, `boot`, and one writable place over its
root that is home, origin and documents place. The shipping form declares
a read-only place on the system volume as origin and writable places on
the user volume, one of them the home and another the documents place.
The user volume holds two places for now, documents and records in
separate folders; that layout lives only in what composition declares,
and no applet or library may assume it.

### Who may write a file

Ownership of a file follows from what each applet is granted (Decided,
2026-11-18). Each applet holds a set of its own, and each store's home is
a folder of its own under the records place, so a store writes its own
files and no other's. File Explorer and Pad write the documents place and
read the records place. A document that another applet owns, such as
Daybook's, reaches Pad only through that owner's service in Desk, by its
identity: Pad asks Desk's resource registry whether a file holds a
document Desk hosts and opens such a file through its owner, so no applet
spells another applet's file. A source rule holds applet code to the
place words for every write.

The grants bind every route the system offers: File Explorer, Pad and
every store. Applets outside the sandbox run as native code with every
volume in reach, so the grants do not stop one that sets out to write a
file it was not granted; sandboxed code has no file access of its own.
The linked build declares one place that is home, origin and documents
place at once, so its grants cannot separate records from documents, and
there the registry lookup is what keeps Pad from writing another
applet's file.

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
PLSET-HOME!  PLSET-ORIGIN!  PLSET-DOCUMENTS!   ( place set -- )
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
PLSET-FIRST  PLSET-HOME  PLSET-ORIGIN  PLSET-DOCUMENTS   ( set -- place | 0 )
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
PLACE-VREPL!    ( path-a path-u place write? replacement -- ior )
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

`PLACE-PATH`, `PLACE-HOLDS?` and `PLACE-RENAME` are handed a live entry,
and a lookup may evict an entry that nothing holds open. They therefore
look nothing up before they use it: they find the folder on the entry's
own parent chain, by the depth of the declared folder path, and match
that chain against the path name for name. A folder is for that reason
declared by its own path, `/` or plain names joined by single slashes,
with no `.` or `..` and no symbolic link in it; `PLACES-DECLARE` refuses
the first three, and a folder reached through a link answers
`VFS-E-XDEV` to those three words.

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
for those libraries too. `PLACE-VREPL!` (`utils/fs/place-replace.f`) is the
binding a checked replacement takes: it binds a file of the place, for
writing when asked, and points the replacement at it, configuring the
replacement on the place's volume when it was on another. Pad points its
one replacement at each document this way, and a store that keeps its
records through a replacement binds its file in its place when it opens,
for writing when the place is writable. `PLACE-NAME-LIMIT` is the longest entry name the
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
naming a place the reader was not given fails with `IRES-S-NO-PLACE`,
which is where a Practice's choice takes effect. `IRES-PLACE-PARSE` is the
same for a URI's text, and `CINST-PLACES` is the service lookup described
above, with `CINST-HOME` and `CINST-ORIGIN` for the two roles. A schema
bounds a locator by `IRES-VFS-URI-MAX`, 773 bytes: the prefix, a name of
any length the rule allows, and a path of 512 bytes, the path capacity the
components that exchange files keep.

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
stands and the source was kept. An answer that carries `VFS-IOR-F-PARTIAL`
says so: the destination file stands though a later step failed. The word
copies files, and a folder copy is a walk that calls it.
A stage left by a crash is removed when the same copy is retried and is
otherwise a hidden file. [vfs-copy.md](vfs-copy.md) describes the words
and their answers.

### The explorer widget

```forth
EXPL-NEW      ( rgn set -- widget )
EXPL-SELECTED ( widget -- inode place )    inode 0 on a place's own row
EXPL-SET      ( widget -- set )
EXPL-PLACE-KEY  ( place -- key )
EXPL-PATH-KEY   ( path-a path-u place -- key )
on-open and on-select callbacks  ( inode place explorer -- )
```

Its top rows are the set's places by label, each opening onto its
folder. An unavailable place shows its reason after its label and stays
closed, and a read-only place refuses rename, delete and new, as does a
place's own row. A top row's node is the place handle and every other
node a VFS entry; the widget tells them apart by asking the set. The tree
calls the key callback for each row in order and a query stops at the row
it finds, so the last place that callback saw is the row's place, which
stays exact when two places show one folder. The name limit comes from
the place (`PLACE-NAME-LIMIT`). The rows are tree rows of the canonical
widget, mounted on an ordinary `<region>`, so the cell fallback and rich
output draw the same list with no UIDL annotation, scene or terminal call
added.

### Capacity

Volumes, places, sets and grants are linked heap records, so their number
follows need. The 255-byte name is an interface limit: one component of a
URI, equal to ext4's file-name limit, so any folder name can be a place
name. Labels and folders are stored at their length, a folder within
`VFS-PATH-MAX`.

## Every word names its instance

Every VFS word takes the instance it works on, and the library keeps no
current instance, so no code reaches files through an instance another
module chose. Code that mounts an instance keeps it and passes it on;
code that works in a holder's files passes a place, which answers its
instance. The replacement, access and fixed-snapshot libraries, the
system-volume and settings mounts, the MP64FS platform module, the
Practice head, the credential vault, the catalog, builder and loader, the
shell's UIDL load, UIDL media and every applet store work this way:
stores take their set's home, and shipped files are read from the
origin. A source rule, `local_testing/test_vfs_named_instances.py`, holds
every file under `akashic/` to it.

## Order of work

1. One place, end to end, in the linked build: `places.f`, the resource
   form with every producer and reader, the explorer widget, File
   Explorer and Pad on a set, the service, `CTX.PLACES`, the boot
   fragment. `vfs.f` is untouched.
2. Done: every VFS word names its instance and each writer gets its
   home. Stores take places; shipped files read from the origin. A
   source rule holds `akashic/` to it.
3. Done: copy and move, `vfs-copy.f` with `PLACE-COPY` and
   `PLACE-MOVE`, and File Explorer's paste across its set's places.
4. The user volume attaches: the builder's user image on the machine's
   fourth storage unit, `user-volume.f`, the shipping form's places, and
   a boot without the user image. Stores refuse changes on a read-only
   place themselves, and narrowing a set no longer marks its volumes. The
   slice begins in the replacement and copy libraries: names follow each
   volume's limit and paths the VFS's, and a copy syncs only where a
   replacement does. Done but for what "What slice 4 leaves" lists. Before
   slice 6, the persistence store that Streams and Library share gains a
   read-only mode, so the mark goes, and the place set gains a role for
   the place where a person's documents go; both are done and the mark is
   gone. The recovery in which applets run over read-only places is a step
   of its own before slice 9 (Decided, 2026-11-18).
5. Done: the ext4 driver makes an inode group ready on first use.
6. File Explorer across volumes. It begins with the grants of "Who may
   write a file": a set per applet from what each applet's descriptor
   says it needs, File Explorer and Pad writing the documents place and
   reading the records place, the registry lookup in place of Pad's
   spelling of Daybook's path, and the source rule (Decided, 2026-11-18).
   Done ahead of it: the run confirmed
   that a sync was refused while a removed file was open, and the driver
   now lands that sync and takes other writes, keeping the file's record
   until its last close.
7. The other writers on ext4: Daybook, Grid, the Agent, Streams, the
   catalogs, the sandbox store, the head. Each store's home becomes a
   folder of its own under the records place (Decided, 2026-11-18), and
   Streams and Library compose their layouts under it. The user volume's writer
   takes its transaction size from measurements of these writers' saves,
   the Agent's above all (Decided, 2026-11-18).
8. The killed run: the simulator killed at chosen flushes during a save
   and during a copy's stage write and rename; each image passes the
   machine's own remount and the host tools' recovery, then `e2fsck`.
9. Both journeys, linked and shipping form, the shipping form with the
   user volume. Once both pass, the shipping form with the user volume
   becomes the builder's default (Decided, 2026-11-18).

Slices 2, 5 and 6 change files the ext4 tests read. Those tests run on
MegaPad's simulator, so each of these slices runs them whole and ends
with the standing sample on the emulator; the four ext4 files run whole
on the emulator once after slice 8 (`local_testing/README.md`, "On the
emulator or the simulator").

## Status

Slices 1, 2 and 3 are in the tree, and slice 4 is but for what "What
slice 4 leaves" lists. The linked build declares one place and
everything below runs on it; a build with `--user-volume` declares the
shipping form's places.

- `utils/fs/place-name.f` and `utils/fs/places.f`, tested by
  `local_testing/test_places.py` on two RAM volumes.
- The runtime works over a set. `tui/platform/mp64fs-vfs.f` reports the
  instance it mounts or adopts as the volume `boot`. The image builder
  follows that module's load with the declaration every build has today
  (`PLACES_BOOT_LINES` in `local_testing/akashic_tui.py`): one writable
  place over the boot volume's root, required, and a default set in which
  it is home and origin. `PACT-ACTIVATE` takes a set, reads the Practice
  head from its home, stores the set in `CTX.PLACES`, and narrows it in
  recovery; a set with no usable home activates in recovery with no head.
  `PACT-PLACES` answers the activation's set, and Desk lends it under
  `org.akashic.fs.places` through its service table, whose getters
  receive the asking instance. The sandbox requires a context with no
  place set.
- The resource form is `vfs://<place>/<path>` everywhere. Daybook, Grid
  and Sound Lab name their file in their home; File Explorer and Pad name
  a file in its place and read a locator in their own set. The old form
  and `IRES-VFS-PATH` are gone.
- The explorer widget takes a set. `EXPL-VFS` and `EXPL-ROOT!` are gone.
- File Explorer and Pad obtain their set through `CINST-PLACES` and work
  through the `PLACE-` words. Each reads its configuration from the
  origin.
- Every VFS word takes its instance: `VFS-OPEN` is
  `( c-addr u vfs -- fd|0 )`, and `VFS-NEW` answers the instance it
  mounts to its caller alone. `tui/platform/mp64fs-vfs.f` adopts the
  instance attached as `boot`, the settings disk and the system volume
  mount without changing anything else, and the credential vault saves
  and restores only its own instance's current directory.
- `utils/fs/place-replace.f` gives `PLACE-VREPL!`, which binds a path in a
  place and points a replacement descriptor at the instance the binding
  answers. Pad binds each document through it, and so do the stores that
  keep one file through a replacement.
- Desk hands each store it opens its activation's home (`_DESK-HOME`):
  the sandbox store and its catalog, the Agent's run store, Daybook's
  automation store and owner, the dispatch store, the schedule
  permissions and the broker. The Practice head and the Agent's
  conversation store work through `PLACE-OPEN`, `PLACE-CREATE` and
  `PLACE-SYNC` in the home. The builder publishes in its catalog's place
  and the loader reads in the place it is given.
- Daybook, Grid and Sound Lab keep their file in their home. Streams and
  Library open their repositories on the volume under their home.
- The shell and the applet host read an applet's UIDL file from its
  origin, and a document's media read their file from the place the
  document came from (`UTUI-FILES!`).
- `utils/fs/vfs-copy.f` copies and moves files inside a volume, between
  volumes and between places, through a stage that is read back before a
  rename publishes it, as "Copy and move" describes.
  `local_testing/test_vfs_copy.py` runs it between RAM volumes whose
  binding fails on demand and with the MP64FS boot volume on either side,
  and `local_testing/test_vfs_copy_ext4.py` runs it to, from and within
  an ext4 volume, out of space included, and checks the medium with
  `e2fsck`.
- File Explorer keeps its clipboard as a place and a path, and its paste
  copies with `PLACE-COPY`, or after a cut moves with `PLACE-MOVE`, into
  any place of its set, on its volume or another.
- Names and paths follow each volume (slice 4). The replacement library
  takes a name as long as its volume takes, `VFS-NAME-LIMIT` from the
  volume's `VSF.NAMEMAX`, and a path of `VFS-PATH-MAX`, 4,096 bytes; the
  MP64FS binding reports its 23 bytes through `STATFS`. A descriptor keeps
  its paths in a block sized to them, which `VREPL-FINI` gives back, so the
  4,096-byte limit costs memory only where a path is that long. The stage's
  name stays 23 bytes. Copies, moves and Pad's saves follow the same rule:
  a long name copies and saves on ext4 and is refused on MP64FS. Pad keeps a
  document's path at the 512 bytes the resource form carries.
- A checked replacement and a copy take every barrier between their steps
  from one word, `VFS-BARRIER`: a sync, except on a binding with
  `VFS-CAP-DURABLE-MUTATIONS`, so a copy to ext4 syncs no more than a save
  there does.
- A replacement bound for reading is read-only: `PLACE-VREPL!` marks it
  (`VREPL-READ-ONLY!`), it refuses to replace with `VREPL-S-READ-ONLY`, and
  its recovery changes nothing. The stores that keep their file through
  `PLACE-VREPL!` answer that refusal with a read-only status of their own
  (`SPERM-S-READ-ONLY`, `ADST-S-READ-ONLY`, `DBAS-S-READ-ONLY`,
  `SBOX-STORE-S-READ-ONLY`, `ACAT-S-READONLY`), and Daybook, Grid and the
  shared document word it as a read-only place.
- `utils/fs/user-volume.f` mounts the ext4 volume on `USER-UNIT` through
  the staged writer and reports it as `user`: attached, refused with the
  driver's reason, or missing when the unit holds no medium
  ([user-volume.md](user-volume.md)). The image builder's `--user-volume`
  writes a fresh user volume beside the boot image, attaches it as unit 3
  on every launch path, and declares the shipping form's places: `system`,
  read-only over the root of the volume that holds the shipped files and
  required, as origin; `documents` over `/documents`; and `records` over
  `/records`, the home. The sample documents ship in `/documents`.
- The set marks a third role, the documents place (`PLSET-DOCUMENTS!`),
  which composition declares: the one place in the linked build,
  `documents` with `--user-volume`, and the test sets'
  (`local_testing/test-root-place.f`) one place. Pad takes a path with no
  place of its own in the active document's place or else the documents
  place, and starts an untitled document there; a set that declares none
  makes Pad ask for a place. File Explorer opens in the documents place,
  or in the set's first place when there is none. Every file handed to
  Pad comes as a locator naming its place (Daybook's source, File
  Explorer's open, the Agent's request) or through Pad's own explorer
  with its place, so none depends on the role. Desk with Pad opens the
  bare `notes.md` in both builds.
- Stores refuse changes on a read-only place themselves, so narrowing a
  set (`_PACT-NARROW`) leaves the volumes under its places unmarked. The
  place words refuse, a replacement bound through `PLACE-VREPL!` refuses,
  and the persistence store has a read-only mode (`PSTORE-READ-ONLY!`,
  [storage.md](../../persistence/storage.md)): provisioning, a staging
  reset and a transaction that may stage answer `PERSIST-S-READ-ONLY`,
  while reads, a cold audit in a reading transaction
  (`PSTORE-BEGIN-READ`) among them, still work. Library's repository
  marks both its stores from its home's access
  (`LIBRARY-REPOSITORY-READ-ONLY!`), refuses to provision, bootstrap,
  repair or compact before it touches its folder, and stays absent where
  it does not exist, which Library shows as read-only. Streams'
  repository offers the same to the code that composes it
  (`STREAMS-REPOSITORY-READ-ONLY!`); the applet composes its draft,
  source and observation stores, which mark their replacements from the
  home's access (`STREAMS-DRAFT-STORE-READ-ONLY!`, `VFSNAP-READ-ONLY!`)
  and answer a read-only status of their own.
- The boot policy runs as decided: a boot without its origin stops with a
  message, here the system volume's own; a boot without the user volume
  goes on, provisions no Practice in the missing home, and Desk starts in
  recovery with every place of its set read-only; with the volume, a
  document saved in the documents place passes the host's `e2fsck` and a
  second boot reads it back (`local_testing/test_user_volume.py`).

What slice 4 leaves:

- Desk's recovery fails closed: with no usable home it starts no applet and
  opens none of the stores it gives its home, and shows that the Practice
  is in recovery. The decided recovery, in which applets run over read-only
  places and each store opens as a service that says why, needs Desk to
  compose its applets and stores in recovery as well; the stores' read-only
  answers are tested on read-only places meanwhile. That recovery is a step
  of its own before slice 9, and the Agent and the sandbox stay off in it,
  as they are now (Decided, 2026-11-18).
- With records as the home, the other writers meet ext4 in a build with
  the user volume (slice 7). The Agent's conversation store saves its
  first, absent slot with a truncate that changes nothing, which ext4's
  writer refuses, so Desk shows `history error`; the Practice head no
  longer truncates an empty slot. The Agent saves every 500 ms while a
  256 KiB save takes 2 to 5 s. Streams and Library keep repositories with
  fixed layouts from the volume's root (`/streams/...`, `/library/...`,
  `/streams-*.bin`) whose paths their persistence layer and their own
  checks compare literally; before they move to the user volume, each
  binds its folder in its home once when it opens and composes its paths
  under that folder, through one helper both share, and the persistence
  layer keeps taking an instance and a path (Decided, 2026-11-17).
- File Explorer copies and moves files only and refuses a folder on its
  clipboard. Copying a folder is a walk that calls the copy for each file,
  which the tests make and no applet makes yet.
- File Explorer across volumes is slice 6, and power cuts during a save,
  a copy's stage write and its rename are qualified in slice 8.

## Open

- A sweep of stale copy stages at mount costs a folder walk per boot and
  is left out until measured.
- Explicit-parent VFS words in place of the current-directory bracket.
- The user volume's two places, documents and records, are the layout for
  now and may change.
