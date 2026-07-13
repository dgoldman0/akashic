# Trusted-local applet loader

`akashic/tui/app-loader.f` loads an installed trusted-local applet from a validated manifest and a verified MF64 image. It is a synchronous, core-0-only ownership boundary around manifest parsing, VFS reads, image verification and loading, and the applet entry call.

The loader does not evaluate source text and has no `FIND` fallback for the requested entry. It selects the exact version-2 named export recorded by `app.entry`.

This is not a security sandbox. A loaded applet is native Forth code, image imports resolve against the ambient dictionary, and the code executes with the authority of its host. The SHA3 check detects image corruption or substitution relative to the installed manifest; it is not a signature or statement of origin.

## API and ownership

```forth
ALOAD-FROM-MFT   ( mft -- desc status )
ALOAD-MANIFEST   ( doc-a doc-u -- desc status )
ALOAD-PATH       ( manifest-path-a manifest-path-u -- desc status )
ALOAD-DESC-FREE  ( desc -- )
```

All three load operations return `0 status` on failure. On success they return a loader-owned `APP-DESC` and `ALOAD-S-OK`.

- `ALOAD-FROM-MFT` borrows the manifest descriptor and its backing TOML document. It neither frees nor retains them after the call.
- `ALOAD-MANIFEST` borrows the TOML document for the duration of the call. It creates and frees its temporary manifest descriptor internally.
- `ALOAD-PATH` validates the path, exact-reads the document through VFS, and releases the document buffer and file handle internally. Manifest files are limited to 4096 bytes.
- `ALOAD-DESC-FREE` releases a descriptor returned with `ALOAD-S-OK`; it accepts zero. The caller must keep the descriptor alive while Desk or another consumer still refers to it.

The successful descriptor is one heap allocation containing the `APP-DESC` plus owned copies of the manifest title and optional UIDL-file path. It no longer borrows those strings from the manifest document. The loaded dictionary image itself remains resident and has no unload operation.

`ALOAD-PATH` accepts the same canonical absolute path form as the manifest module: 2--255 bytes, components of 1--23 bytes, no empty, `.`, or `..` components, and only letters, digits, `.`, `-`, `_`, and `/`.

## Load pipeline

The installed-manifest pipeline is deliberately ordered:

1. Run `MFT-VALIDATE-INSTALLED`.
2. Open the declared image through VFS, require a size of 1 byte through 1 MiB, and exact-read it into a heap buffer.
3. Compute SHA3-256 over the exact image bytes and compare its lowercase hexadecimal encoding with `package.image-sha3`.
4. Run full structural `IMG-VERIFY-MEM` validation.
5. Resolve the exact `app.entry` export with `IMG-EXPORT-FIND`.
6. Allocate and seed the loader-owned `APP-DESC`.
7. Load that exact export with `IMG-LOAD-EXPORT`. This is the load commit point.
8. Call the export with stack contract `( desc -- )` under `CATCH` and stack sentinels.
9. Validate the resulting descriptor, component identity, and presentation contract.

The loader does not read or compare the source file. `package.source-sha3` is part of the installed build receipt, while `package.image-sha3` is the digest enforced at load time.

## Entry and descriptor contract

The requested export must return normally with exactly the stack effect `( desc -- )`. A throw, missing consumption, or extra output is normalized to a loader status; the loader forcibly restores its caller-visible stack in each case.

After the entry returns, all of the following must hold:

- `APP-DESC-VALID?` accepts the descriptor.
- The component descriptor's ID and version exactly match `app.id` and `app.version`.
- `APP.ABI` exactly matches the manifest ABI and `APP.SIZE` is exactly `APP-DESC`.
- Width, height, title, and UIDL-file path exactly match the manifest.
- Empty inline UIDL is represented canonically as `(0, 0)`; nonempty inline UIDL has a nonzero address.
- If the manifest declares `uidl-file`, the entry supplies no inline UIDL.

After validation, the loader rebinds the title and UIDL-file fields to its owned copies. It does not copy inline UIDL or component data; those pointers remain as supplied by the entry and their backing storage must remain valid. In the normal packaged case that storage is part of the now-resident applet image.

## Commit and failure behavior

At entry to each public load operation, the loader snapshots `HERE` and `LATEST`.

| Failure point | Dictionary effect | Descriptor result |
| --- | --- | --- |
| Before successful `IMG-LOAD-EXPORT` | snapshot restored; handles and heap buffers released | `0 status` |
| Entry or validation failure after load | verified image remains resident; loader allocations released | `0 status` |
| Unexpected throw before load | snapshot restored; `ALOAD-E-UNEXPECTED` | `0 status` |
| Unexpected throw after load | image remains resident; `ALOAD-E-QUARANTINE` | `0 status` |

Successful loading commits the image permanently. A later entry, identity, or presentation failure cannot unload it, so these statuses mean the applet was rejected but its already verified trusted-native definitions may still be present.

## Status values

Manifest statuses `MFT-E-NO-PACKAGE` through `MFT-E-ALLOC` (`-110` through `-119`) propagate unchanged.

| Value | Name | Meaning |
| ---: | --- | --- |
| 0 | `ALOAD-S-OK` | success |
| -120 | `ALOAD-E-MANIFEST-PATH` | invalid manifest path argument |
| -121 | `ALOAD-E-MANIFEST-OPEN` | manifest open failed |
| -122 | `ALOAD-E-MANIFEST-SIZE` | manifest is empty or over 4096 bytes |
| -123 | `ALOAD-E-MANIFEST-READ` | exact manifest read failed |
| -124 | `ALOAD-E-ALLOC` | heap allocation failed |
| -125 | `ALOAD-E-IMAGE-OPEN` | image open failed |
| -126 | `ALOAD-E-IMAGE-SIZE` | image is empty or over 1 MiB |
| -127 | `ALOAD-E-IMAGE-READ` | exact image read failed |
| -128 | `ALOAD-E-IMAGE-HASH` | image SHA3-256 does not match the manifest |
| -129 | `ALOAD-E-IMAGE-VERIFY` | MF64 structural verification failed |
| -130 | `ALOAD-E-EXPORT` | exact named export is absent or invalid |
| -131 | `ALOAD-E-IMAGE-LOAD` | verified image could not be loaded |
| -132 | `ALOAD-E-ENTRY-THROW` | entry threw or did not return normally |
| -133 | `ALOAD-E-ENTRY-STACK` | entry violated `( desc -- )` |
| -134 | `ALOAD-E-DESC` | returned `APP-DESC` is invalid |
| -135 | `ALOAD-E-COMPONENT` | component ID or version differs from the manifest |
| -136 | `ALOAD-E-PRESENTATION` | ABI, size, geometry, title, or UIDL contract differs |
| -137 | `ALOAD-E-CORE` | called away from core 0 |
| -138 | `ALOAD-E-UNEXPECTED` | unexpected throw before the load commit |
| -139 | `ALOAD-E-QUARANTINE` | unexpected throw after the load commit |
| -140 | `ALOAD-E-BUSY` | recursive or concurrent loader entry |

The loader is non-reentrant and intentionally does not hold a guard across VFS I/O. Call it synchronously on core 0.
