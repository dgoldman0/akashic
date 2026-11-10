# akashic/utils/fs/vfs-module-source.f — KDOS modules from a mounted VFS

```forth
REQUIRE utils/fs/vfs-module-source.f
```

KDOS's `LOAD` and `REQUIRE` do not read a disk themselves. They find and
read a file through the current *module source*, a record of four
operations whose contract is MegaPad's `docs/module-source-contract.md`.
KDOS's own MP64FS is the source selected at boot. This module fills such a
record for a mounted VFS, so that modules can come from any volume a binding
serves, an ext4 volume among them.

| Word | Stack | |
|---|---|---|
| `VMS-INIT` | `( vfs source -- )` | Make `source` serve modules from `vfs`. |

`source` is `/MODULE-SOURCE` bytes that the caller owns. It stays at that
address while the source is selected and while a load that started from it
is under way.

```forth
CREATE sys-source /MODULE-SOURCE ALLOT
sys-vfs sys-source VMS-INIT
sys-source MODULE-SOURCE!          \ modules now come from sys-vfs
REQUIRE akashic/text/utf8.f
FS-MODULE-SOURCE MODULE-SOURCE!    \ back to KDOS's own filesystem
```

Select another source before the VFS is unmounted. A source whose VFS is no
longer mounted, or whose medium changed under it, answers `No filesystem`.

## Paths and the current directory

A path is resolved as the VFS resolves it: from the VFS's current directory,
with a leading `/` for the root, `..` for the parent, and symbolic links
followed. These are the forms KDOS's own source takes, so a module's
`REQUIRE` lines mean the same on either filesystem.

Resolving a file makes its directory the VFS's current one, which is how a
`REQUIRE` inside a module starts at that module's own directory. The loader
puts the earlier directory back when the load ends, so loading leaves the
VFS's current directory where it found it. A path that names a directory, or
goes through a file, names no module.

## What the loader gets

| File record field | Value |
|---|---|
| `MF.USED`, `MF.RESERVE` | the file's size; the read asks for no more |
| `MF.HANDLE` | the file's cache entry |
| `MF.ID` | the identity below, or zero |

A binding that declares stable identities (`VFS-BF-STABLE-IDS`, as the ext4
bindings do) gives each file a number and a generation that survive eviction
and remounting. The first identity cell holds them. The second folds in the
file's size, its modification time, and the cookie KDOS gives each volume
attachment, so a file that has changed, or another volume behind the same
source record, has another identity. KDOS records the identity of each file
whose module is loaded and does not read that file again.

Other bindings number their files as the cache admits them, so those numbers
can come to mean another file. Their files get no identity. Such a file is
read on every `REQUIRE`, and its `PROVIDED` line keeps it from running twice.

## Eviction

A VFS evicts cached entries once a mount holds more than its limit, and it
does so whenever a path is resolved. Loading one module resolves the paths
of others, so an entry the loader still needs could be evicted in the middle
of a load. The module holds two kinds of entry in place:

- a directory the loader will return to, from the moment the loader takes
  its token until it gives the token back;
- the file being read, while it is opened.

It does this with the entry's pin (`VFS-IF-PINNED`). That pin is one bit and
other code sets it too, so the module clears a pin only when it set that pin
itself, and a directory's token carries that fact in its lowest bit. The
root keeps the pin its mount gave it.

## Failures

| What the VFS answers | What the loader does |
|---|---|
| no such name, or a path through a file | prints `Not found:` or `Module not found:` with the path |
| not mounted, or the medium changed | prints `No filesystem` |
| any other failure of resolving or reading | throws the VFS's own ior |

Reading opens the resolved file by its own name from its own directory. If
that name no longer leads to the entry that was resolved, at the size that
was reported, the read stops with a stale-volume ior and copies nothing.
