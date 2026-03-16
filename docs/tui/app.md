# akashic/tui/app.f — Standalone TUI Application Lifecycle

**Layer:** 6  
**Lines:** ~70  
**Prefix:** `APP-`  
**Provider:** `akashic-tui-app`  
**Dependencies:** [`cogs/term-init.f`](cogs/term-init.md), `event.f`

## Overview

Standalone application model.  Adds the event-loop layer on top of
the shared terminal primitives in
[`cogs/term-init.f`](cogs/term-init.md).  Standalone apps use this
module directly: one app, one screen, one event loop.

This is **not** for applets.  Applets use `app-desc.f` +
[`app-shell.f`](app-shell.md), which depend on `term-init.f`
directly (not on this file).

`APP-RUN-FULL` wraps the entire lifecycle in a single word, using
`CATCH` to guarantee that `APP-SHUTDOWN` always runs — even if the
user's init callback or the event loop throws an exception.

Not reentrant.

## API Reference

### Re-exported from term-init.f

These words are available after `REQUIRE tui/app.f` because app.f
pulls in `cogs/term-init.f`.  See
[term-init.md](cogs/term-init.md) for full details.

| Word | Stack | Description |
|------|-------|-------------|
| `APP-INIT` | `( w h -- )` | Enter alternate screen, hide cursor, create screen buffer. Idempotent. Auto-sizes when both args are 0. |
| `APP-SHUTDOWN` | `( -- )` | Free screen, restore terminal. Safe to call without prior `APP-INIT`. |
| `APP-SCREEN` | `( -- scr )` | Application screen descriptor. |
| `APP-SIZE` | `( -- w h )` | Current screen dimensions. |
| `APP-TITLE!` | `( addr len -- )` | Set terminal title. |

### Standalone-only (defined here)

| Word | Stack | Description |
|------|-------|-------------|
| `APP-RUN` | `( -- )` | Enter `TUI-EVT-LOOP`. Blocks until `TUI-EVT-QUIT`. |
| `APP-RUN-FULL` | `( init-xt w h -- )` | Convenience: `APP-INIT`, execute `init-xt`, `APP-RUN`, `APP-SHUTDOWN`. Uses `CATCH` for cleanup on `THROW`. |

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

When `GUARDED` is defined, `APP-RUN` and `APP-RUN-FULL` are wrapped
with `_app-guard WITH-GUARD` for thread-safety.  The terminal
primitives have their own guard in `term-init.f`.

## Design Notes

- **Standalone vs Applet.**  This module is for *standalone* TUI
  apps that own their terminal and event loop.  Applets use
  [`app-shell.f`](app-shell.md) instead — both paths share
  [`cogs/term-init.f`](cogs/term-init.md) for terminal management.
- **CATCH-based cleanup.**  `APP-RUN-FULL` wraps the user's init-xt
  in `CATCH`.  If it throws, `APP-SHUTDOWN` still runs, and the
  exception is re-thrown afterward.
- **Thin layer.**  `APP-RUN` is literally `TUI-EVT-LOOP`.  All
  complexity lives in `event.f`; `app.f` only bridges terminal
  init (from `term-init.f`) with the event loop.
