# akashic/tui/app.f — TUI Application Lifecycle

**Layer:** 6  
**Lines:** 155  
**Prefix:** `APP-` (public), `_APP-` (internal)  
**Provider:** `akashic-tui-app`  
**Dependencies:** `ansi.f`, `screen.f`, `event.f`, `focus.f`, `utils/term.f`

## Overview

One-call application setup and teardown.  Enters the alternate
screen buffer, hides the cursor, creates a double-buffered screen,
runs the event loop, then restores everything on exit.  This is the
top-level entry point for a TUI application.

`APP-RUN-FULL` wraps the entire lifecycle in a single word, using
`CATCH` to guarantee that `APP-SHUTDOWN` always runs — even if the
user's init callback or the event loop throws an exception.

Not reentrant.

## API Reference

### Lifecycle

| Word | Stack | Description |
|------|-------|-------------|
| `APP-INIT` | `( w h -- )` | Enter alternate screen, hide cursor, clear screen, create `w×h` screen buffer, set as current, clear focus chain. Idempotent — second call is a no-op. **Auto-size:** if both w and h are 0, reads hardware terminal dimensions via `TERM-SIZE`. |
| `APP-RUN` | `( -- )` | Enter `TUI-EVT-LOOP`. Blocks until `TUI-EVT-QUIT`. |
| `APP-SHUTDOWN` | `( -- )` | Free screen, clear focus chain, reset attributes, show cursor, leave alternate screen. Safe to call without prior `APP-INIT` (no-op). |
| `APP-RUN-FULL` | `( init-xt w h -- )` | Convenience: `APP-INIT`, execute `init-xt`, `APP-RUN`, `APP-SHUTDOWN`. Uses `CATCH` for cleanup on `THROW`. |

### Accessors

| Word | Stack | Description |
|------|-------|-------------|
| `APP-SCREEN` | `( -- scr )` | Return the application screen descriptor (0 if not initialised). |
| `APP-SIZE` | `( -- w h )` | Return current screen dimensions. Returns `0 0` if not initialised. |
| `APP-TITLE!` | `( addr len -- )` | Set terminal title via `ANSI-TITLE` (ESC]2;...ST). |

## State Variables

| Variable | Default | Purpose |
|----------|---------|---------|
| `_APP-SCR` | 0 | Screen descriptor address. |
| `_APP-INITED` | 0 | TRUE after `APP-INIT`, FALSE after `APP-SHUTDOWN`. |

## Init / Shutdown Sequence

### APP-INIT

1. `ANSI-ALT-ON` — enter alternate screen buffer
2. `ANSI-CURSOR-OFF` — hide cursor
3. `ANSI-RESET` — reset all attributes
4. `ANSI-CLEAR` — clear screen
5. `ANSI-HOME` — cursor to 1,1
6. `SCR-NEW` — allocate screen buffer
7. `SCR-USE` — set as current screen
8. `FOC-CLEAR` — reset focus chain

### APP-SHUTDOWN

1. `SCR-FREE` — deallocate screen buffer
2. `FOC-CLEAR` — reset focus chain
3. `ANSI-RESET` — reset attributes
4. `ANSI-CURSOR-ON` — show cursor
5. `ANSI-ALT-OFF` — leave alternate screen

## Usage Example

```forth
REQUIRE tui/app.f

: my-setup ( -- )
    APP-SCREEN SCR-USE
    \ ... create widgets, add to focus chain ...
    \ Post quit after setup for demo:
    ' TUI-EVT-QUIT TUI-EVT-POST
;

: main  ['] my-setup 80 24 APP-RUN-FULL ;
main
```

## Guard Support

When `GUARDED` is defined, all public words are wrapped with
`_app-guard WITH-GUARD` for thread-safety.

## Design Notes

- **Idempotent init.**  `APP-INIT` checks `_APP-INITED` and exits
  early on second call.  This prevents leaked screen buffers.
- **Safe shutdown.**  `APP-SHUTDOWN` checks `_APP-INITED` first,
  so it can be called unconditionally in cleanup paths.
- **CATCH-based cleanup.**  `APP-RUN-FULL` wraps the user's init-xt
  in `CATCH`.  If it throws, `APP-SHUTDOWN` still runs, and the
  exception is re-thrown afterward.
- **Thin layer.**  `APP-RUN` is literally `TUI-EVT-LOOP`.  All
  complexity lives in event.f; app.f only manages terminal state.
