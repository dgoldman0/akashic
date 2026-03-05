# binimg — Relocatable Binary Images for KDOS

**Module:** `akashic/utils/binimg.f`
**Prefix:** `IMG-` (public), `_IMG-` (internal)
**Provides:** `akashic-binimg`
**Phase:** 3 — Core Saver + Loader + Imports

## Overview

Save compiled Forth dictionary regions as `.m64` binary files with
relocation metadata, and load them back at any base address without
re-parsing source text.

The **saver** (`IMG-MARK` / `IMG-SAVE`) snapshots a contiguous segment
of the dictionary, normalizes in-segment absolute addresses to base-0
offsets, and writes a single `.m64` file.

The **loader** (`IMG-LOAD`) reads a `.m64` file into the dictionary,
applies relocations to adjust all addresses to the new base, resolves
imported external words by name, and splices the loaded words into the
live dictionary chain.

Future phases will add export tables, module-system integration, and
diagnostics.

## Quick Start

```forth
REQUIRE utils/binimg.f

\ 1. Create the target file (enough sectors for the output)
16 1 MKFILE mylib.m64

\ 2. Mark the start of the segment
IMG-MARK

\ 3. Compile your code
VARIABLE COUNTER
: BUMP  1 COUNTER +! ;
: GET   COUNTER @ ;

\ 4. Save
IMG-SAVE mylib.m64    \ ( -- ior )  0 = success

\ --- Later, or in a different session ---

\ Load the saved module
IMG-LOAD mylib.m64    \ ( -- ior )  0 = success

\ Words are now available
BUMP GET .   \ prints 1
```

## Public API

### `IMG-MARK  ( -- )`

Snapshot the current dictionary position as the start of a saveable
segment. Everything compiled after `IMG-MARK` becomes part of the
segment.

Internally:
- Parks a relocation buffer (8 KiB, 1024 entries max) at HERE via
  `ALLOT`.
- Enables BIOS relocation tracking (`_RELOC-ACTIVE`, `_RELOC-BUF`,
  `_RELOC-COUNT`).
- Records `HERE` as `_img-mark-base` and `LATEST` as
  `_img-mark-latest`.

### `IMG-SAVE  ( "filename" -- ior )`

Save the segment `[mark-base .. HERE)` to the named `.m64` file.
The file must already exist on disk (use `MKFILE` to pre-create it).
Returns 0 on success, negative on error.

Steps performed:
1. Disable BIOS reloc tracking.
2. Compute segment size.
3. Walk the dictionary chain to collect link-field relocations
   (`_IMG-COLLECT-LINKS`).
4. Open the target file (via `FIND-BY-NAME` / `OPEN-BY-SLOT`).
5. Normalize: filter relocs to in-segment references only, convert
   absolute addresses to base-0 offsets. Out-of-segment references
   (external calls) are recorded as import candidates
   (`_IMG-NORMALIZE`).
6. Count named imports: for each out-of-segment reloc, attempt
   reverse lookup via `_IMG-XT>ENTRY` → `_IMG-COUNT-IMPORTS`.
7. Build the `.m64` output at HERE (past the segment and file
   descriptor) in one contiguous buffer, including the import table
   (`_IMG-BUILD-OUTPUT`).
7. Write the entire buffer with a single `FWRITE` (avoids the
   sector-level DMA overwrite issue).
8. Flush directory metadata via `FFLUSH`.
9. Denormalize the live dictionary so compiled words remain usable.

### `IMG-LOAD  ( "filename" -- ior )`

Load a `.m64` file, relocate all addresses, and splice the loaded
words into the live dictionary. Returns 0 on success, negative on
error.

Steps performed:
1. Open the file (via `FIND-BY-NAME` / `OPEN-BY-SLOT`).
2. Read the entire file into HERE in one `FREAD` call.
3. Validate header magic (`MF64`) and version.
4. Extract segment size, relocation count, import count, and
   chain-head offset.
5. Mark `HERE+64` as load-base (segment starts after header).
6. `ALLOT` header + segment to make the space permanent.
7. Apply relocations: add load-base to every 8-byte value at the
   offsets listed in the relocation table.
8. Resolve imports: for each import entry, build a counted string
   from the name field, call `FIND` to look up the word in the
   host dictionary, and patch the fixup slot with the resolved XT.
9. Splice the dictionary chain: set the loaded chain's tail link to
   the current `LATEST`, then set `LATEST` to the loaded chain head.

## .m64 File Format

All multi-byte fields are little-endian.

### Header (64 bytes)

| Offset | Size  | Field         | Description                        |
|--------|-------|--------------|------------------------------------|
| 0      | 4     | magic        | `MF64` (77 70 54 52)              |
| 4      | 2     | version      | Format version (currently 1)       |
| 6      | 2     | flags        | Bit flags (see below)              |
| 8      | 8     | seg_size     | Segment size in bytes              |
| 16     | 8     | reloc_count  | Number of relocation entries       |
| 24     | 8     | export_count | Export table entries (Phase 4: 0)  |
| 32     | 8     | import_count | Import table entries               |
| 40     | 8     | chain_head   | Dict chain head offset into segment|
| 48     | 8     | prov_offset  | PROVIDED string offset (Phase 4: 0)|
| 56     | 8     | reserved     | Must be 0                          |

### Flag Bits

| Bit | Constant          | Meaning                 |
|-----|--------------------|------------------------|
| 0   | `_IMG-FLAG-JIT`   | Contains JIT code       |
| 1   | `_IMG-FLAG-XMEM`  | Uses extended memory    |
| 2   | `_IMG-FLAG-EXEC`  | Executable (has entry)  |
| 3   | `_IMG-FLAG-LIB`   | Library (exports only)  |

### Body

```
[header 64B][segment seg_size B][reloc_table reloc_count × 8B][import_table import_count × 32B]
```

Each relocation entry is a `u64` byte-offset into the segment. The
8-byte value at that offset is a base-0 address that must be adjusted
by adding the load base address.

### Import Table

Each import entry is 32 bytes:

| Offset | Size | Field        | Description                        |
|--------|------|-------------|------------------------------------|
| 0      | 8    | fixup_offset | Segment-relative offset of the slot |
| 8      | 24   | name         | NUL-padded ASCII word name          |

The fixup offset points to the 8-byte slot in the segment that
originally held an absolute XT of an external word (outside the
segment). During save, that slot is zeroed. During load, `FIND`
resolves the name, and the resulting XT is written to
`load-base + fixup_offset`.

## Memory Strategy

No `ALLOCATE` / `FREE`. All buffers live in dictionary space via
`HERE` / `ALLOT`:

```
During compilation (after IMG-MARK):
  [...dict...][reloc-buf 8K][mark-base ... segment ... HERE]

During IMG-SAVE (temporary):
  [...dict...][reloc-buf][segment][fdesc 56B][output-buf]

During IMG-LOAD:
  [...dict...][fdesc 56B][header 64B][segment seg_size B][relocs (scratch)]
                                     ^ load-base         ^ new HERE
```

The output buffer is built past the segment and file descriptor,
written in one FWRITE, then abandoned. The dictionary frontier
(`HERE`) is not rolled back — the reloc buffer and fdesc remain
allocated but harmless. Subsequent compilation continues from the
current HERE.

## Relocation Details

Two sources feed the relocation buffer:

1. **BIOS-tracked** (`_RELOC-ACTIVE` / `reloc_record`): The BIOS
   compiler records every `LDI64` immediate that holds an absolute
   address — from `compile_call`, `CREATE`, `VARIABLE`, and `DOES>`.

2. **Dictionary link fields** (`_IMG-COLLECT-LINKS`): Walks from
   `LATEST` back to `_img-mark-latest`, appending the address of each
   link cell.

During normalization, entries whose target value falls **outside** the
segment are recorded as out-of-segment relocs in `_img-ext-pairs`.
These are references to KDOS/BIOS words (e.g., `!`, `@`, `.`) and the
terminal link field. For each, `_IMG-XT>ENTRY` attempts a reverse
lookup by walking the pre-mark dictionary; if found, the reference
becomes a named import entry in the `.m64` file. The fixup slot is
zeroed in the output.

## Error Codes

| Code | Constant          | Meaning                            |
|------|--------------------|------------------------------------|
| 0    | —                  | Success                            |
| -1   | `_IMG-ERR-IO`     | File not found or open failed      |
| -2   | `_IMG-ERR-MAGIC`  | Bad magic or version too new       |
| -3   | `_IMG-ERR-IMPORT` | Unresolved import (name not found) |
| -5   | `_IMG-ERR-RELOC`  | Relocation buffer overflow         |

## Design Notes

- **Single FWRITE**: KDOS FWRITE is sector-level DMA. Multiple small
  writes to the same sector overwrite each other. The entire `.m64` is
  assembled in one contiguous buffer and written in a single call.

- **OPEN-BY-SLOT at HERE**: `OPEN-BY-SLOT` builds a 56-byte file
  descriptor at HERE via `,` (comma). `IMG-SAVE` opens the file
  *before* building the output buffer so the fdesc doesn't clobber it.

- **Denormalization**: After saving, `_IMG-DENORMALIZE` restores all
  normalized values — both in-segment relocs and out-of-segment
  references — so the live dictionary remains functional. The caller
  can continue using words compiled in the segment.

- **Import auto-detection**: The saver does not require the user to
  declare imports. Any compiled reference (LDI64 immediate) whose
  target falls outside the segment is an import candidate.
  `_IMG-XT>ENTRY` walks the pre-mark dictionary chain to find the
  entry containing that code-field address, then `ENTRY>NAME`
  extracts the name for the import table.

- **Pre-mark chain walk**: `_IMG-XT>ENTRY` must walk from
  `_img-mark-latest` (the pre-mark LATEST), not from current LATEST.
  During normalization the link fields of in-segment entries are
  rewritten to base-0 offsets and cannot be followed.

- **No cross-core impact**: The module touches only dictionary space
  (HERE/ALLOT) and the BIOS reloc variables. No heap, no shared
  state, no effect on other cores or tasks.

- **Single FREAD for loading**: KDOS `FREAD` advances the cursor by
  whole sectors (512 bytes), not by the requested byte count.
  Sequential small reads skip data. The loader reads the entire file
  in one `FREAD` call, then parses header, segment, and reloc table
  from the in-memory buffer.

- **Chain-head offset in header**: The saver stores the segment-
  relative offset of `LATEST` (the dictionary chain head) at header
  offset 40. The loader uses this to find the chain head directly,
  avoiding the need to scan or walk the segment.

- **Dictionary chain splice**: After relocation, the loaded chain
  head's most-recent entry links down to the tail (oldest loaded
  word). The tail's link still holds the absolute address of the
  pre-mark `LATEST` from the original save session. The loader
  replaces it with the current `LATEST`, then sets `LATEST` to the
  loaded chain head. The loaded words shadow any same-named words.

## Roadmap

| Phase | Status  | Description                          |
|-------|---------|--------------------------------------|
| 1     | **Done**| Core saver (IMG-MARK, IMG-SAVE)      |
| 2     | **Done**| Core loader (IMG-LOAD)               |
| 3     | **Done**| Import table (auto-detect + resolve) |
| 4     | Planned | Module system integration            |
| 5     | Planned | Diagnostics & hardening              |

See `local_testing/ROADMAP_executable.md` for the full phase plan and
decision log.
