# akashic-vfs-mount — Global Mount Table for KDOS / Megapad-64

A thin routing layer that maps path prefixes to VFS instances.
Provides the traditional `OPEN "/sd/readme.txt"` experience across
multiple VFS instances.  Optional — applications that pass VFS
instances explicitly never need this module.

```forth
REQUIRE utils/fs/vfs-mount.f
```

`PROVIDED akashic-vfs-mount` — safe to include multiple times.
Depends on `akashic-vfs`.

---

## Table of Contents

- [Design Principles](#design-principles)
- [Quick Start](#quick-start)
- [API Reference](#api-reference)
- [Constants](#constants)
- [Entry Layout](#entry-layout)
- [Lookup Algorithm](#lookup-algorithm)
- [Quick Reference](#quick-reference)

---

## Design Principles

| Principle | Detail |
|---|---|
| **Sugar, not core** | The mount table is a directory of VFS references.  The VFS abstraction works without it. |
| **Longest-prefix match** | Multiple overlapping prefixes are supported; the longest match wins. |
| **Static table** | The table lives in dictionary space — no arena required.  64 slots × 272 bytes = ~17 KB. |
| **Handles, not drivers** | The table stores pointers to VFS instances.  Each VFS is independently created, configured, and destroyable. |
| **Concurrent-safe** | Optional guard section wraps all public words when `GUARDED` is defined. |

---

## Quick Start

```forth
\ Create two VFS instances
524288 A-XMEM ARENA-NEW  IF -1 THROW THEN
    VFS-RAM-VTABLE VFS-NEW  CONSTANT sd-vfs

524288 A-XMEM ARENA-NEW  IF -1 THROW THEN
    VFS-RAM-VTABLE VFS-NEW  CONSTANT ram-vfs

\ Mount them
sd-vfs  S" /sd"  VMNT-MOUNT DROP
ram-vfs S" /tmp" VMNT-MOUNT DROP

\ Create a file on the SD VFS
sd-vfs VFS-USE
S" hello.txt" sd-vfs VFS-MKFILE DROP

\ Open via mount table — routes to sd-vfs automatically
S" /sd/hello.txt" VMNT-OPEN  ( fd | 0 )

\ List mounts
VMNT-INFO
\   /sd  → VFS@12345
\   /tmp → VFS@67890

\ Unmount
S" /tmp" VMNT-UMOUNT DROP
```

---

## API Reference

### VMNT-MOUNT
```forth
VMNT-MOUNT  ( vfs c-addr u -- ior )
```
Bind a VFS instance to a mount-point prefix string.

| Return | Meaning |
|--------|---------|
| 0 | Success |
| -1 | Table full (all 64 slots occupied) |
| -2 | Prefix too long (> 255 bytes) |

### VMNT-UMOUNT
```forth
VMNT-UMOUNT  ( c-addr u -- ior )
```
Remove the mount entry whose prefix exactly matches `(c-addr u)`.
Returns 0 on success, -1 if not found.

### VMNT-RESOLVE
```forth
VMNT-RESOLVE  ( c-addr u -- vfs c-addr' u' | 0 )
```
Find the longest matching mount prefix for the given path.

On match, returns:
- `vfs` — the VFS instance bound to the matching prefix
- `c-addr'` — pointer to the remainder of the path (after the prefix)
- `u'` — length of the remainder

Returns a single `0` if no mount point matches.

### VMNT-OPEN
```forth
VMNT-OPEN  ( c-addr u -- fd | 0 )
```
Convenience word: `VMNT-RESOLVE` → `VFS-USE` → `VFS-OPEN`.
Returns an open file descriptor, or 0 if no mount matches or the
file does not exist.

### VMNT-INFO
```forth
VMNT-INFO  ( -- )
```
Print all active mount entries to the console.

---

## Constants

| Name | Value | Purpose |
|------|-------|---------|
| `VMNT-MAX-ENTRIES` | 64 | Maximum simultaneous mount points |
| `VMNT-PREFIX-SIZE` | 256 | Maximum bytes per mount-point prefix string |

---

## Entry Layout

Each mount table entry is 272 bytes:

| Offset | Size | Field | Notes |
|--------|------|-------|-------|
| +0 | 256 B | prefix | NUL-terminated prefix string |
| +256 | cell | prefix-len | Cached string length |
| +264 | cell | vfs | Pointer to VFS instance (0 = unused) |

Total table size: 64 × 272 = 17408 bytes.

---

## Lookup Algorithm

`VMNT-RESOLVE` scans all active entries and finds the one whose
prefix is the longest match against the beginning of the given path.
Ties are broken by length (longest wins).

The remainder of the path — everything after the matched prefix — is
returned as `(c-addr' u')` for the VFS to resolve internally via
`VFS-RESOLVE` or `VFS-OPEN`.

Example:
```
Mounts:     /mnt        → vfs-A
            /mnt/deep   → vfs-B

Path:       /mnt/deep/file.txt
Match:      /mnt/deep   (longest)  → vfs-B
Remainder:  /file.txt
```

---

## Quick Reference

| Word | Stack Effect | Purpose |
|------|-------------|---------|
| `VMNT-MOUNT` | `( vfs c-addr u -- ior )` | Bind VFS to prefix |
| `VMNT-UMOUNT` | `( c-addr u -- ior )` | Remove mount |
| `VMNT-RESOLVE` | `( c-addr u -- vfs c-addr' u'\|0 )` | Longest-prefix lookup |
| `VMNT-OPEN` | `( c-addr u -- fd\|0 )` | Mount-aware open |
| `VMNT-INFO` | `( -- )` | List mounts |
