# binimg — Relocatable Binary Images for KDOS

**Module:** `akashic/utils/binimg.f`
**Prefix:** `IMG-` (public), `_IMG-` (internal)
**Provides:** `akashic-binimg`
**Phase:** 1 — Core Saver

## Overview

Save compiled Forth dictionary regions as `.m64` binary files with
relocation metadata. The saver snapshots a contiguous segment of the
dictionary (the code and data compiled between `IMG-MARK` and
`IMG-SAVE`), normalizes all in-segment absolute addresses to base-0
offsets, writes the result as a single `.m64` file, then restores the
live dictionary so compilation can continue.

Future phases will add a loader (`IMG-LOAD`), import/export tables,
module-system integration, and diagnostics.

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
   absolute addresses to base-0 offsets (`_IMG-NORMALIZE`).
6. Build the `.m64` output at HERE (past the segment and file
   descriptor) in one contiguous buffer (`_IMG-BUILD-OUTPUT`).
7. Write the entire buffer with a single `FWRITE` (avoids the
   sector-level DMA overwrite issue).
8. Flush directory metadata via `FFLUSH`.
9. Denormalize the live dictionary so compiled words remain usable.

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
| 24     | 8     | export_count | Export table entries (Phase 3: 0)  |
| 32     | 8     | import_count | Import table entries (Phase 3: 0)  |
| 40     | 8     | entry_offset | Entry-point offset (Phase 4: 0)   |
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
[header 64B][segment seg_size B][reloc_table reloc_count × 8B]
```

Each relocation entry is a `u64` byte-offset into the segment. The
8-byte value at that offset is a base-0 address that must be adjusted
by adding the load base address.

## Memory Strategy

No `ALLOCATE` / `FREE`. All buffers live in dictionary space via
`HERE` / `ALLOT`:

```
During compilation (after IMG-MARK):
  [...dict...][reloc-buf 8K][mark-base ... segment ... HERE]

During IMG-SAVE (temporary):
  [...dict...][reloc-buf][segment][fdesc 56B][output-buf]
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
segment are filtered out. These are references to KDOS/BIOS words
(e.g., `!`, `@`, `DUP`) and the terminal link field. They will become
"imports" in Phase 3; for now they remain as absolute addresses in the
segment.

## Error Codes

| Code | Constant          | Meaning                            |
|------|--------------------|------------------------------------|
| 0    | —                  | Success                            |
| -1   | `_IMG-ERR-IO`     | File not found or open failed      |
| -2   | `_IMG-ERR-MAGIC`  | Bad magic (future loader)          |
| -5   | `_IMG-ERR-RELOC`  | Relocation buffer overflow         |

## Design Notes

- **Single FWRITE**: KDOS FWRITE is sector-level DMA. Multiple small
  writes to the same sector overwrite each other. The entire `.m64` is
  assembled in one contiguous buffer and written in a single call.

- **OPEN-BY-SLOT at HERE**: `OPEN-BY-SLOT` builds a 56-byte file
  descriptor at HERE via `,` (comma). `IMG-SAVE` opens the file
  *before* building the output buffer so the fdesc doesn't clobber it.

- **Denormalization**: After saving, `_IMG-DENORMALIZE` restores all
  normalized values so the live dictionary remains functional. The
  caller can continue using words compiled in the segment.

- **No cross-core impact**: The module touches only dictionary space
  (HERE/ALLOT) and the BIOS reloc variables. No heap, no shared
  state, no effect on other cores or tasks.

## Roadmap

| Phase | Status  | Description                          |
|-------|---------|--------------------------------------|
| 1     | **Done**| Core saver (IMG-MARK, IMG-SAVE)      |
| 2     | Planned | Core loader (IMG-LOAD)               |
| 3     | Planned | Import/export tables                 |
| 4     | Planned | Module system integration            |
| 5     | Planned | Diagnostics & hardening              |

See `local_testing/ROADMAP_executable.md` for the full phase plan and
decision log.
