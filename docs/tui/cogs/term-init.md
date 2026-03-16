# akashic/tui/cogs/term-init.f — Shared Terminal Initialisation Primitives

**Layer:** 5 (below app.f and app-shell.f)  
**Lines:** ~133  
**Prefix:** `APP-` (public), `_APP-` (internal)  
**Provider:** `akashic-tui-term-init`  
**Dependencies:** `ansi.f`, `screen.f`, `focus.f`, `utils/term.f`  
**Location:** `akashic/tui/cogs/term-init.f`

## Why `cogs/`?

Most Akashic TUI modules are standalone composable components — each
one provides a self-contained service and can be used individually.
A few modules are *cogs*: they exist only as internal building blocks
shared between higher-level modules and are not intended to be
required directly by application code.

`term-init.f` is a cog.  It contains the low-level terminal ownership
primitives (alternate screen, screen buffer, cursor, focus chain) that
are shared between two independent consumers:

- **app.f** — standalone TUI apps that own their own event loop.
- **app-shell.f** — the applet host runtime.

Extracting these shared primitives into `cogs/` keeps the
standalone and applet paths fully independent: app-shell.f no longer
depends on app.f.

## Overview

Enters the alternate screen buffer, hides the cursor, creates a
double-buffered screen descriptor, and manages the focus chain.
Provides a matching shutdown that restores the terminal.

These words retain the `APP-` prefix for backward compatibility and
because they genuinely represent "application terminal state" —
the distinction is that `APP-RUN` and `APP-RUN-FULL` (event-loop
words) live in `app.f`, not here.

Not reentrant.  A single terminal session is assumed.

## API Reference

### Lifecycle

| Word | Stack | Description |
|------|-------|-------------|
| `APP-INIT` | `( w h -- )` | Enter alternate screen, hide cursor, clear screen, create `w×h` screen buffer, set as current, clear focus chain. Idempotent — second call is a no-op. **Auto-size:** if both w and h are 0, reads hardware terminal dimensions via `TERM-SIZE`. |
| `APP-SHUTDOWN` | `( -- )` | Free screen, clear focus chain, reset attributes, show cursor, leave alternate screen. Safe to call without prior `APP-INIT` (no-op). |

### Accessors

| Word | Stack | Description |
|------|-------|-------------|
| `APP-SCREEN` | `( -- scr )` | Return the application screen descriptor (0 if not initialised). |
| `APP-SIZE` | `( -- w h )` | Return current screen dimensions. Returns `0 0` if not initialised. |
| `APP-TITLE!` | `( addr len -- )` | Set terminal title via `ANSI-TITLE` (ESC]2;…ST). |

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

## Consumers

| Module | Uses | Purpose |
|--------|------|---------|
| `app.f` | `APP-INIT`, `APP-SHUTDOWN`, `APP-SCREEN`, `APP-SIZE`, `APP-TITLE!` | Standalone TUI lifecycle |
| `app-shell.f` | `APP-INIT`, `APP-SHUTDOWN`, `APP-TITLE!` | Applet host terminal management |

## Guard Support

When `GUARDED` is defined, all five public words are wrapped with
`_tinit-guard WITH-GUARD` for thread-safety.

## Design Notes

- **`APP-` prefix kept.** Renaming to `TINIT-` was considered but
  rejected — every downstream caller already uses the `APP-` names,
  and "application init/shutdown" accurately describes the purpose.
- **Idempotent init.**  `APP-INIT` checks `_APP-INITED` and exits
  early on second call.  This prevents leaked screen buffers.
- **Safe shutdown.**  `APP-SHUTDOWN` checks `_APP-INITED` first,
  so it can be called unconditionally in cleanup paths.
- **No event.f dependency.**  The event loop lives in `app.f`
  (`APP-RUN = TUI-EVT-LOOP`) and is not needed by app-shell.f,
  which runs its own `_ASHELL-LOOP`.  This is the reason
  `term-init.f` was split out.
