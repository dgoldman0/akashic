# akashic/tui/app-loader.f — Applet Package Loader

**Lines:** ~186  
**Prefix:** `ALOAD-` (public), `_ALOAD-` (internal)  
**Provider:** `akashic-tui-app-loader`  
**Dependencies:** [`binimg.f`](../utils/binimg.md), [`app-manifest.f`](app-manifest.md),
[`app-desc.f`](app-desc.md)

## Overview

Unified loader that ties together the binary image system
(`binimg.f`), the TOML manifest (`app-manifest.f`), and the
applet descriptor (`app-desc.f`) into a single load-and-launch
operation.

```forth
REQUIRE tui/app-loader.f
```

`PROVIDED akashic-tui-app-loader` — safe to include multiple times.

## Applet Package Contract

1. A **TOML manifest** declares name, entry word, `.m64` filename,
   optional UIDL filename, dimensions, dependencies.
2. The `.m64` binary is a **relocatable image** saved with
   `IMG-SAVE-EXEC`.  After loading, its entry word is available
   in the dictionary.
3. The entry word has the signature: **`( desc -- )`**.
   It receives a zeroed `APP-DESC` and fills in its callbacks
   (`init-xt`, `event-xt`, `tick-xt`, `paint-xt`, `shutdown-xt`)
   plus optional UIDL pointer and title.
4. The loader returns the filled `APP-DESC` ready for
   `DESK-LAUNCH` or `ASHELL-RUN`.

## Pipeline

```
  ALOAD-MANIFEST  ( toml-a toml-l -- desc ior )
    │
    ├─ MFT-PARSE         →  parse TOML into manifest descriptor
    ├─ _ALOAD-LOAD-BINARY →  IMG-LOAD-EXEC via EVALUATE trick
    ├─ _ALOAD-FIND-WORD   →  fallback FIND if IMG-LOAD-EXEC returned xt=0
    ├─ _ALOAD-FILL-DESC   →  allocate APP-DESC, fill from manifest, call entry
    └─ MFT-FREE           →  release manifest descriptor
```

## API Reference

### Public Words

| Word | Stack | Description |
|------|-------|-------------|
| `ALOAD-MANIFEST` | `( toml-a toml-l -- desc ior )` | Full pipeline: parse manifest TOML → load binary → build APP-DESC. Frees the manifest descriptor on completion. |
| `ALOAD-FROM-MFT` | `( mft -- desc ior )` | Load applet from an already-parsed manifest descriptor. |

### Error Constants

| Constant | Value | Meaning |
|----------|-------|---------|
| `ALOAD-ERR-PARSE` | −120 | Manifest TOML parse failed |
| `ALOAD-ERR-NOBIN` | −121 | No `binary=` field in manifest |
| `ALOAD-ERR-LOAD` | −122 | `IMG-LOAD-EXEC` failed (file not found, bad magic, etc.) |
| `ALOAD-ERR-ENTRY` | −123 | Entry word not found via `FIND` after load |

On error, `desc` is returned as 0 and `ior` is one of the above codes.

## Internal Words

| Word | Stack | Description |
|------|-------|-------------|
| `_ALOAD-LOAD-BINARY` | `( mft -- xt ior )` | Reads `MFT-BINARY`, builds `"IMG-LOAD-EXEC <filename>"` in a scratch buffer, and calls `EVALUATE`. Returns the entry XT and 0 on success. |
| `_ALOAD-FIND-WORD` | `( addr len -- xt flag )` | Builds a counted string and calls `FIND`. Returns `(xt -1\|1)` on success, `(0 0)` on failure. Name limited to 31 chars. |
| `_ALOAD-FILL-DESC` | `( mft xt -- desc ior )` | Allocates an `APP-DESC` at `HERE`, fills dimensions and title from the manifest, calls the entry XT with `( desc -- )` to let the applet fill its callbacks. |

## Usage Example

```forth
REQUIRE tui/app-loader.f

\ Given a TOML manifest in memory:
S" [app]\nname = \"pad\"\nentry = \"PAD-ENTRY\"\nbinary = \"pad.m64\"\n"
ALOAD-MANIFEST           ( desc ior )
?DUP IF
    ." Load failed: " . CR
    DROP
ELSE
    DESK-LAUNCH           ( slot-id )
    DROP
THEN
```

## The EVALUATE Trick

`IMG-LOAD-EXEC` parses its filename from the Forth input stream
(using `PARSE-NAME`), but the app-loader has the filename as an
`(addr len)` pair from the manifest.  To bridge this gap,
`_ALOAD-LOAD-BINARY` builds the string `"IMG-LOAD-EXEC <filename>"`
in a scratch buffer and passes it to `EVALUATE`, which temporarily
redirects the input stream to that string.

Important: the applet's entry word must use `[']` (compile-time tick)
rather than `'` (runtime tick) to reference words, since the input
stream during `EXECUTE` of a loaded binary is not the original source.

## Design Notes

- **Sibling to `app-image.f`**, not a replacement.  `app-image.f`
  wraps `binimg.f` + `app.f` for **standalone full-terminal** apps
  that call `APP-RUN-FULL`.  `app-loader.f` wraps `binimg.f` +
  `app-manifest.f` + `app-desc.f` for **applets** that fill an
  `APP-DESC` and are hosted by `app-shell.f` or the desk.
- **No INCLUDED.**  KDOS does not have `INCLUDED`.  All applet code
  is loaded as pre-compiled `.m64` binary images via `IMG-LOAD-EXEC`.
- **Dictionary allocation.**  Both the manifest descriptor and the
  `APP-DESC` are `ALLOT`ed at `HERE`.  The manifest is freed after
  loading; the `APP-DESC` persists for the applet's lifetime.
- **Entry word fallback.**  If `IMG-LOAD-EXEC` returns `xt=0` (e.g.
  older binaries without `IMG-ENTRY`), the loader falls back to
  `FIND` on the manifest's `entry` word name.

## Guard-Protected Words

Under `[DEFINED] GUARDED`: `ALOAD-FROM-MFT`, `ALOAD-MANIFEST`
are wrapped with `_aload-guard WITH-GUARD` for concurrency safety.

## See Also

- [app-manifest.md](app-manifest.md) — TOML manifest parser
- [app-desc.md](app-desc.md) — APP-DESC data layout
- [binimg.md](../utils/binimg.md) — Binary image save/load system
- [app-image.md](app-image.md) — Standalone app wrapper (sibling)
- [desk.md](applets/desk/desk.md) — Multi-app desktop (primary consumer)
