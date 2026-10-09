# Sandbox module store

`akashic/runtime/sandbox-module-store.f` keeps the modules a host installs, so
they survive a restart. It fills the host's module owner
(`runtime/sandbox-module-owner.f`) when it opens and changes it as modules are
installed, revoked and removed.

Revisions are exact. The store never looks up a "latest" revision, and a
revision that was revoked or removed can never be installed again, so one
`(RID, revision)` always means the same module.

## Files

The store keeps two files in one directory of a VFS, at paths the host
chooses. Each is replaced atomically through `utils/fs/vfs-replace.f`, so a
crash leaves either the old file or the new one.

### Catalog

The catalog is a CRC-checked record (`utils/checked-record.f`) with the magic
`AKSBXCAT` and format 1. Its tag is the catalog's generation, which rises by
one with every write. Its payload is:

- a u64 record count and a u64 operation-key count;
- the records, strictly increasing by RID bytes, then revision;
- the operation keys, strictly increasing by their bytes.

A record is 112 bytes:

| Offset | Size | Field |
|---:|---:|---|
| 0 | 32 | module RID, not all zero |
| 32 | 8 | revision, positive |
| 40 | 4 | flags: 1 revoked, 2 removed |
| 44 | 4 | zero |
| 48 | 32 | declaration digest |
| 80 | 32 | artifact digest |

A removed revision keeps its record, so it is never installed again.

An operation key is 72 bytes: the 32-byte key, then the RID and the u64
revision of the module that operation installed, which a record must name. The
caller gives each install a key, such as the review that approved it.

### Pack

The pack holds the declaration and artifact bytes:

| Offset | Size | Field |
|---:|---:|---|
| 0 | 8 | magic `AKSBXPAK` |
| 8 | 2 | format 1 |
| 10 | 2 | header size 64 |
| 12 | 4 | CRC-32 of the header with this field zero |
| 16 | 8 | total bytes |
| 24 | 8 | object count |
| 32 | 32 | zero |

Each object follows: a 48-byte header, then its bytes, zero-padded to 8.

| Offset | Size | Field |
|---:|---:|---|
| 0 | 4 | kind: 1 declaration, 2 artifact |
| 4 | 4 | CRC-32 of the header with this field zero |
| 8 | 8 | length, positive |
| 16 | 32 | digest of the bytes in their domain |

Objects strictly increase by kind, then digest, so each is stored once even
when modules share it. A declaration's digest is its identity
(`declaration-format.md`), and an artifact's is its content digest.

## Ordering and recovery

An install writes the pack before the catalog, and a removal writes the
catalog before the pack. So the catalog never names an object the pack lacks,
whichever write a crash interrupts. An object no live record names is dropped
by the next pack write.

When a pack is rewritten, every object it keeps is copied as it is, checked or
not. A damaged object therefore stays until its module is removed; it is never
deleted silently.

Opening the store:

1. recovers any interrupted replacement of either file;
2. reads the catalog;
3. indexes the pack's object headers;
4. adds every record that is not removed to the module owner as DECLARED,
   retiring the revoked ones.

A module is quarantined by its key when its declaration object is missing,
damaged, or not the recorded one (reason `SBOX-MODULE-Q-STORE`), or when it
names another profile (`SBOX-MODULE-Q-PROFILE`). The store reads a module's
artifact only on first use. An artifact that is missing is quarantined the
same way; one that is not the declared artifact, or that the verifier
refuses, is quarantined by the module owner.

A catalog or pack the store cannot read, or a write whose outcome cannot be
known, puts the store in recovery. Whatever can still be read loads, and the
store refuses every write, so nothing more is lost before someone repairs it.

## Words

- `SBOX-STORE-INIT ( vfs catalog-path catalog-u pack-path pack-u owner store
  -- status )` configures `SBOX-STORE-SIZE` cell-aligned bytes for an owner.
  The paths are absolute and in one directory.
- `SBOX-STORE-OPEN ( store -- status )` recovers, reads and fills the owner,
  which must be empty. `SBOX-STORE-CLOSE ( store -- status )` frees what
  opening read; the owner keeps its modules.
- `SBOX-STORE-INSTALL ( key declaration declaration-u build store -- module|0
  status )` installs the module a declaration describes from a build that
  holds its verified plan. The module owner checks the plan against the
  declaration and takes it, so the module is VERIFIED at once. The pack and
  then the catalog are written before the call returns. The same key again
  returns the module it installed and changes nothing.
- `SBOX-STORE-VERIFY ( module store -- status )` verifies a DECLARED module
  from its stored artifact.
- `SBOX-STORE-REVOKE ( module store -- status )` records the revocation, then
  retires the module.
- `SBOX-STORE-REMOVE ( module store -- status )` records the removal, removes
  the unpinned module from the owner, and drops its objects from the pack.
- `SBOX-STORE-RECOVERY?`, `SBOX-STORE-GENERATION@`,
  `SBOX-STORE-RECORD-FLAGS@ ( rid revision store -- flags|-1 )` and
  `SBOX-STORE-MODULE-STATUS@`, the owner's status behind
  `SBOX-STORE-S-MODULE`.

The statuses are:

| Status | Meaning |
|---|---|
| `SBOX-STORE-S-OK` | Done |
| `-INVALID` | A bad argument or declaration |
| `-NOMEM` | Out of memory |
| `-IO` | A file could not be read or written |
| `-RECOVERY` | The store is in recovery and writes nothing |
| `-STATE` | Not open, or the module is in the wrong state |
| `-BUSY` | The module is pinned by a run |
| `-CONFLICT` | The operation key installed other content |
| `-DUPLICATE` | The revision is already installed |
| `-REVOKED` | The revision was revoked or removed |
| `-REMOVED` | The operation's module has since been removed |
| `-MODULE` | The module owner refused; see `SBOX-STORE-MODULE-STATUS@` |

## Limits

Each file is replaced whole, so a write needs memory for the whole pack. That
suits a host with modest modules. If modules grow large or numerous, the store
should move to the persistence library instead.

## Tests

`local_testing/sandbox-module-store-contracts.f`, run by the
`sandbox-module-store-contracts` profile on a RAM filesystem, covers:

- installs, a repeated operation, a conflicting key, a duplicate revision, and
  an owner refusal;
- revocation, and reinstalling a revoked or removed revision;
- reboots and first-use verification;
- a damaged declaration that stays quarantined and preserved across pack
  rewrites until its module is removed;
- a damaged artifact, a damaged and then repaired catalog, and a truncated
  pack;
- a boot under another profile.
