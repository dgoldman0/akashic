# akashic/tui/app-manifest.f — Application Manifest Reader

**Layer:** 8  
**Lines:** ~288  
**Prefix:** `MFT-` (public), `_MFT-` (internal)  
**Provider:** `akashic-tui-app-manifest`  
**Dependencies:** `utils/toml.f` (which requires `utils/string.f`, `utils/utf8.f`)

## Overview

Reads a TOML manifest describing a TUI application's metadata.
The caller provides an `(addr len)` pair pointing to the TOML text
already in memory.  `MFT-PARSE` allocates a 128-byte descriptor at
`HERE` and populates it from the `[app]` section.

Returned string pointers reference slices of the original document
(via `TOML-GET-STRING`), so the caller must keep the source text
alive for as long as the descriptor is in use.

## Manifest Format

```toml
[app]
name      = "my-app"
title     = "My Application"
version   = "0.1.0"
width     = 80
height    = 24
entry     = "my-main"
binary    = "my-app.m64"
uidl-file = "my-app.xml"

[deps]
uidl = true
css  = true
```

**Required keys:** `name`, `entry`.  
**Optional keys:** `title` (defaults to `name`), `version`, `width`
(default 0 = auto), `height` (default 0 = auto), `binary` (`.m64`
filename), `uidl-file` (UIDL XML filename).  
**Optional section:** `[deps]` — queried lazily via `MFT-DEP?`.

## API Reference

### Lifecycle

| Word | Stack | Description |
|------|-------|-------------|
| `MFT-PARSE` | `( doc-a doc-l -- mft \| 0 )` | Parse a TOML manifest. Returns the descriptor address on success, or 0 if required keys are missing. The descriptor is `ALLOT`ed at `HERE`. |
| `MFT-FREE` | `( mft -- )` | Release the descriptor. Reclaims dictionary space only if the descriptor is the most recent `ALLOT`. |

### Accessors

| Word | Stack | Description |
|------|-------|-------------|
| `MFT-NAME` | `( mft -- addr len )` | Application name (required). |
| `MFT-TITLE` | `( mft -- addr len )` | Application title. Defaults to name if not specified. |
| `MFT-VERSION` | `( mft -- addr len )` | Version string. `( 0 0 )` if not specified. |
| `MFT-WIDTH` | `( mft -- n )` | Preferred terminal width. 0 = auto. |
| `MFT-HEIGHT` | `( mft -- n )` | Preferred terminal height. 0 = auto. |
| `MFT-ENTRY` | `( mft -- addr len )` | Entry word name (required). |
| `MFT-BINARY` | `( mft -- addr len )` | Binary `.m64` filename. `( 0 0 )` if not specified. |
| `MFT-UIDL-FILE` | `( mft -- addr len )` | UIDL XML filename. `( 0 0 )` if not specified. |

### Dependency Query

| Word | Stack | Description |
|------|-------|-------------|
| `MFT-DEP?` | `( mft key-a key-l -- flag )` | Check if a named dependency is listed as `true` in the `[deps]` section. Returns `FALSE` if `[deps]` is missing, the key is absent, or the value is `false`. Performs a lazy lookup into the original TOML document each time. |

## Error Codes

| Constant | Value | Meaning |
|----------|-------|---------|
| `MFT-E-NO-APP` | -110 | Missing `[app]` section. |
| `MFT-E-NO-NAME` | -111 | Missing `name` key in `[app]`. |
| `MFT-E-NO-ENTRY` | -112 | Missing `entry` key in `[app]`. |

> **Note:** The current implementation returns 0 from `MFT-PARSE` on
> error rather than throwing.  The error constants are defined for
> future use or caller-side `THROW`.

## Descriptor Layout

The descriptor is a flat 128-byte (16-cell) structure `ALLOT`ed at
`HERE`:

| Offset | Field | Type | Description |
|--------|-------|------|-------------|
| +0 | name-addr | cell | Pointer into source doc |
| +8 | name-len | cell | Name string length |
| +16 | title-addr | cell | Pointer into source doc |
| +24 | title-len | cell | Title string length |
| +32 | version-addr | cell | Pointer into source doc |
| +40 | version-len | cell | Version string length |
| +48 | width | cell | Preferred width (0 = auto) |
| +56 | height | cell | Preferred height (0 = auto) |
| +64 | entry-addr | cell | Pointer into source doc |
| +72 | entry-len | cell | Entry word name length |
| +80 | binary-addr | cell | Pointer to `.m64` filename string |
| +88 | binary-len | cell | Binary filename length |
| +96 | uidlf-addr | cell | Pointer to UIDL XML filename string |
| +104 | uidlf-len | cell | UIDL XML filename length |
| +112 | doc-addr | cell | Original TOML text address |
| +120 | doc-len | cell | Original TOML text length |

## Internal Words

| Word | Stack | Description |
|------|-------|-------------|
| `_MFT-SET-STR` | `( str-a str-l mft offset -- )` | Store a string pair into the descriptor at the given field offset. |
| `_MFT-GET-STR` | `( mft offset -- addr len )` | Read a string pair from the descriptor. |
| `_MFT-DEALLOC` | `( mft -- )` | Reclaim descriptor space (negative `ALLOT`). |

## Guard Support

When `GUARDED` is defined, all public words (`MFT-PARSE`,
`MFT-FREE`, `MFT-NAME`, `MFT-TITLE`, `MFT-VERSION`, `MFT-WIDTH`,
`MFT-HEIGHT`, `MFT-ENTRY`, `MFT-BINARY`, `MFT-UIDL-FILE`,
`MFT-DEP?`) are wrapped with `_mft-guard WITH-GUARD` for
thread-safety.

## Design Notes

- **TOML, not LCF.** `lcf.f` is an RPC message format
  (`[action]`/`[result]`/`[notification]`), not a config file format.
  Manifests use `toml.f` directly.
- **Zero-copy strings.** `TOML-GET-STRING` returns pointers into the
  original document.  No heap allocation, no copying — but the source
  text must stay alive.
- **Lazy dependency lookup.** `MFT-DEP?` stores the original
  `(doc-addr doc-len)` at offsets +112/+120 and re-parses the `[deps]`
  table on each call.  This avoids pre-loading dependency data that
  may never be queried.
- **Dictionary allocation.** The descriptor lives at `HERE` via
  `ALLOT`.  `MFT-FREE` can only truly reclaim it if nothing else was
  compiled after the parse — otherwise the space is reclaimed on the
  next dictionary reset.  This matches idiomatic Forth ephemeral
  allocation patterns.
- **Title defaults to name.** If no `title` key is present, the
  descriptor copies the name pointer/length into the title fields,
  so `MFT-TITLE` always returns a valid string.
