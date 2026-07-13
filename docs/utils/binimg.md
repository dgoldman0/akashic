# MF64 relocatable dictionary images

`akashic/utils/binimg.f` builds, verifies, and loads relocatable MF64 Forth dictionary images. Version 2 is the current write format and adds exact named exports. The memory APIs also read legacy version-1 images.

MF64 is a trusted-native transport format, not a sandbox or authenticity mechanism. Verification checks structure and resolves imports against the current dictionary. It does not authenticate an image, constrain imported authority, inspect native semantics, or provide unload isolation.

## Memory API

The primary API operates on counted memory buffers and is the interface VFS code should use:

```forth
IMG-MARK          ( -- )
IMG-DISCARD       ( -- ior )
IMG-PROVIDED      ( "token" -- )
IMG-EXPORT        ( xt name-a name-u -- ior )
IMG-ENTRY-NAMED   ( xt name-a name-u -- ior )
IMG-ENTRY         ( xt -- )
IMG-XMEM          ( -- )
IMG-BUFFER-MAX    ( -- max-u ior )
IMG-BUILD-INTO    ( dst cap -- used ior )

IMG-VERIFY-MEM    ( image-a image-u -- ior )
IMG-EXPORT-FIND   ( image-a image-u name-a name-u -- offset ior )
IMG-LOAD-MEM      ( image-a image-u -- ior )
IMG-LOAD-EXEC-MEM ( image-a image-u -- xt ior )
IMG-LOAD-EXPORT   ( image-a image-u name-a name-u -- xt ior )
```

All `ior` results use the status table below. APIs returning another value return zero for that value on failure.

## Building an image

A build is one global marked dictionary region:

```forth
IMG-MARK
\ compile one or more words
' MY-ENTRY S" MY-ENTRY" IMG-ENTRY-NAMED THROW
IMG-BUFFER-MAX THROW              \ leaves exact required byte count
\ allocate caller-owned output storage
output capacity IMG-BUILD-INTO    \ leaves used ior
IMG-DISCARD THROW
```

`IMG-MARK` reserves relocation storage, records `LATEST`, and starts tracking the segment at the subsequent `HERE`. The relocation capacity is 1024 entries in the kernel dictionary and 8192 in userland. Image construction also caps external-reference sites at 1024 and named imports at 1024; repeated calls to the same imported word still consume separate external-reference sites. At least one dictionary word must be compiled after the mark.

Calling `IMG-MARK` again without first calling `IMG-DISCARD` preserves the historical behavior: the previous marked region is left committed in the live dictionary and a new build starts. Code that wants rollback must pair every mark with a successful discard.

`IMG-DISCARD` stops tracking, restores the saved `LATEST`, and rolls `HERE` back through both the compiled segment and its reserved relocation buffer. It returns `IMG-E-STATE` if no build is marked. Building an image does not discard automatically; the live segment remains usable until the caller discards it.

### Registration words

`IMG-EXPORT` registers a named version-2 export. The XT must belong to a dictionary word compiled after the current mark, and the supplied 1--23 byte name must exactly equal that word's dictionary name. Re-registering the same name/offset pair is idempotent; duplicate names with different offsets, duplicate offsets with different names, and more than 16 exports are rejected.

`IMG-ENTRY-NAMED` performs the same exact registration and also makes that export the default executable entry. Version-2 executable entries must be named exports. `IMG-ENTRY` is a compatibility form that derives the word's dictionary name and latches any error rather than returning it.

`IMG-PROVIDED` copies a parsed 1--23 byte token into the segment and records it for `_MOD-MARK` registration after loading. `IMG-XMEM` requests extended-memory allocation at load time. Both words, and compatibility `IMG-ENTRY`, have no status result; misuse is latched into build state and surfaces from a later sizing, build, or save operation.

The first build error is sticky. Once an operation latches an error, subsequent preparation reports it until `IMG-DISCARD` or a new `IMG-MARK` resets the state.

### Buffer ownership

`IMG-BUFFER-MAX` finalizes and prechecks the marked region and returns the exact version-2 image size. `IMG-BUILD-INTO` requires a nonzero caller-owned buffer of at least that size. The destination must not overlap the relocation buffer or live marked segment.

Construction temporarily normalizes pointers in the live marked region, serializes the image, restores the live pointers, and verifies the completed output. On success, `used` is the exact image length. The caller owns the output buffer; binimg neither allocates nor frees it.

## Version-2 file layout

All integer fields are little-endian. The header is exactly 64 bytes:

| Offset | Size | Field |
| ---: | ---: | --- |
| 0 | 4 | magic `MF64` |
| 4 | 2 | version (`2` when written) |
| 6 | 2 | flags |
| 8 | 8 | segment byte length |
| 16 | 8 | relocation count |
| 24 | 8 | export count |
| 32 | 8 | import count |
| 40 | 8 | signed dictionary-head offset |
| 48 | 8 | signed `PROVIDED` string offset, or `-1` |
| 56 | 8 | signed default-entry offset, or `-1` |

The body immediately follows in this exact order, with no alignment gaps or trailing bytes:

```text
segment bytes
relocation[count]     each: u64 slot offset
export[count]         each: 32 bytes
import[count]         each: 32 bytes
```

An export record is a `u64` code offset followed by a 24-byte NUL-padded name. An import record is a `u64` fixup-slot offset followed by the same name representation. A canonical record name is 1--23 bytes followed by NULs through the end of the field.

The recognized flag bits are:

| Mask | Name | Meaning in this implementation |
| ---: | --- | --- |
| `0x1` | `JIT` | recognized legacy flag; no public builder setter or load behavior here |
| `0x2` | `XMEM` | allocate the segment through `XMEM-ALLOT?` |
| `0x4` | `EXEC` | a default executable entry is present |
| `0x8` | `LIB` | version-2 named exports are present |

Unknown flag bits are rejected. For version 2, `LIB` is required exactly when the export count is nonzero.

Version 1 uses the same header shape but has no export records and requires an export count of zero. It can still be verified and loaded, including through its legacy default entry, but exact named-export lookup requires version 2. New builds always serialize version 2.

## Verification

`IMG-VERIFY-MEM` requires the supplied byte count to match the image layout exactly. It rejects truncation and trailing bytes. Validation includes:

- supported version, known flags, nonnegative sizes and counts, and hard caps of 8192 relocations, 16 exports, and 1024 imports;
- unique, in-bounds relocation slots whose stored values are segment-relative;
- unique import slots that are not relocation slots and contain zero in the serialized segment;
- canonical import names that resolve exactly through the current ambient dictionary;
- unique, canonical version-2 export names and offsets;
- a bounded, backward dictionary chain with valid entry shapes and consistent link relocation;
- exact binding of every version-2 export name and code offset to a reachable dictionary word;
- a valid executable entry, with a named export required in version 2;
- a nonempty NUL-terminated `PROVIDED` value when present.

Compiled calls into the preexisting dictionary become named imports and are patched to whatever exact word `FIND` resolves during verification and loading. A limited set of positive low runtime/BIOS ABI addresses is retained directly; unknown external userland references are rejected. Thus verification is environment-dependent and does not turn an import into a capability restriction.

`IMG-VERIFY-MEM` does not modify the supplied image or splice a dictionary segment, but it uses shared module scratch and performs ambient dictionary lookup.

## Exact exports and loading

`IMG-EXPORT-FIND` fully verifies the image and then returns the segment-relative offset for an exact version-2 export name. It does not load the image and rejects version 1.

All load operations verify before allocating and copy the segment into its destination, apply internal relocations, patch resolved imports, splice the image's dictionary chain into `LATEST`, and register an optional `PROVIDED` token. The caller retains ownership of the input image buffer and may release it after the call.

- `IMG-LOAD-MEM` loads an image without selecting an entry.
- `IMG-LOAD-EXEC-MEM` requires `EXEC`, loads the image, and returns the relocated default-entry XT.
- `IMG-LOAD-EXPORT` requires an exact version-2 export, loads the image, and returns that relocated XT.

A successful load is permanent: binimg exposes no unload operation. The module itself does not provide an exception-level transaction around dictionary or XMEM mutation, so a higher-level loader that needs rollback or quarantine semantics must establish that boundary itself.

## Status values

| Value | Name | Meaning |
| ---: | --- | --- |
| 0 | `IMG-E-OK` | success |
| -1 | `IMG-E-IO` | raw-file I/O failure |
| -2 | `IMG-E-FORMAT` | bad magic/version/flags/layout/name or other format violation |
| -3 | `IMG-E-IMPORT` | import is invalid or cannot be resolved |
| -5 | `IMG-E-RELOC` | invalid, duplicate, or inconsistent relocation/fixup |
| -6 | `IMG-E-NOEXEC` | executable entry was requested but is absent |
| -7 | `IMG-E-EXPORT` | named export or exact binding is invalid or absent |
| -8 | `IMG-E-STATE` | invalid build state or overlapping output buffer |
| -9 | `IMG-E-CAPACITY` | count cap or destination/file capacity exceeded |
| -10 | `IMG-E-SHORT` | truncated header/body or short raw-file read |
| -11 | `IMG-E-NOMEM` | DMA, dictionary, or XMEM allocation failed |

The old private `_IMG-ERR-*` aliases remain only for source compatibility. New code should use the public `IMG-E-*` names.

## Legacy raw-file wrappers

These compatibility words parse the following filename token and use the KDOS raw filesystem:

```forth
IMG-SAVE       ( "filename" -- ior )
IMG-SAVE-EXEC  ( xt "filename" -- ior )
IMG-LOAD       ( "filename" -- ior )
IMG-LOAD-EXEC  ( "filename" -- xt ior )
IMG-VERIFY     ( "filename" -- ior )
IMG-INFO       ( "filename" -- )
IMG-CHECKSUM   ( "filename" -- u )
```

The save target must already exist and have enough raw-file capacity. `IMG-SAVE` builds into a temporary DMA buffer first, then truncates, writes, checks the exact resulting size, and flushes. The read wrappers exact-read the complete raw file into DMA memory and release it after verification or loading.

`IMG-INFO` prints verified header metadata or a numeric error. `IMG-CHECKSUM` returns an FNV-like checksum over the image body, or zero on read/verification error. It is a diagnostic compatibility checksum, not a cryptographic digest or trust check.

When guards are enabled, the memory and build-state APIs are individually guarded to serialize shared scratch. The raw wrappers are not guarded across filesystem I/O and also use shared state, so callers must serialize complete raw-file operations themselves.
