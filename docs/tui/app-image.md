# akashic/tui/app-image.f — Binary Image Convenience Wrapper

**Layer:** 8  
**Lines:** 115  
**Prefix:** `APPI-` (public), `_APPI-` (internal)  
**Provider:** `akashic-tui-app-image`  
**Dependencies:** `app.f`, `utils/binimg.f`

## Overview

Thin wrapper that integrates `binimg.f` with the TUI application
lifecycle (`app.f`).  Allows a compiled TUI application to be
frozen to a `.m64` image and reloaded + launched later in a single
call.

All filename arguments are parsed from the Forth input stream
(matching the `binimg.f` convention — not `addr len` on the stack).

## Typical Workflow

```forth
\ --- Build phase ---
APPI-MARK                        \ snapshot dict
: my-app  ( -- )
    ." Hello TUI" CR ;
' my-app APPI-ENTRY               \ register entry point
APPI-SAVE my-app.m64              \ write image to disk

\ --- Run phase (later) ---
80 24 APPI-RUN my-app.m64         \ load + APP-RUN-FULL
```

## API Reference

| Word | Stack | Description |
|------|-------|-------------|
| `APPI-MARK` | `( -- )` | Snapshot the dictionary pointer via `IMG-MARK`. Everything compiled after this call becomes part of the saved image segment. |
| `APPI-ENTRY` | `( xt -- )` | Register an execution token as the application entry point via `IMG-ENTRY`. The xt must point to a word compiled after `APPI-MARK`. |
| `APPI-SAVE` | `( "filename" -- ior )` | Save everything compiled since `APPI-MARK` as a `.m64` image. Filename is parsed from the input stream. Returns 0 on success, negative ior on error. |
| `APPI-LOAD` | `( "filename" -- xt ior )` | Load a `.m64` image that has an entry point. Returns the entry-point xt and 0 on success, or 0 and a negative ior on error. Filename is parsed from the input stream. |
| `APPI-RUN` | `( w h "filename" -- )` | One-shot: load a `.m64` TUI app image and run it. The entry xt is passed to `APP-RUN-FULL` which handles init → execute → event-loop → shutdown. On load error, throws `_APPI-ERR-LOAD` (-100). |

## Error Codes

| Constant | Value | Meaning |
|----------|-------|---------|
| `_APPI-ERR-LOAD` | -100 | Image load failed (from `APPI-RUN`). The underlying binimg ior is printed before the throw. |

## Guard Support

When `GUARDED` is defined, all five public words are wrapped with
`_appi-guard WITH-GUARD` for thread-safety.

## Design Notes

- **Input-stream filenames.** `binimg.f` uses `PARSE-NAME` to read
  the filename token from the Forth input stream, not an `(addr len)`
  pair on the stack.  `APPI-*` follows the same convention so that
  usage is identical to the raw `IMG-*` words.
- **APPI-RUN stack order.** Width and height are placed on the stack
  *before* the filename token: `80 24 APPI-RUN my-app.m64`.  After
  `IMG-LOAD-EXEC` consumes the filename, the stack is
  `( w h xt ior )`.  `-ROT` reorders to `( xt w h )` for
  `APP-RUN-FULL`.
- **Thin by design.** Each word is a one-line delegation to
  `binimg.f` or `app.f`.  The value is in the naming convention and
  the combined load-and-run convenience of `APPI-RUN`.
