# akashic/tui/app-desc.f — APP-DESC Application Descriptor

**Layer:** 6  
**Lines:** ~40  
**Prefix:** `APP.` (public), `_AD-` (internal)  
**Provider:** `akashic-tui-app-desc`  
**Dependencies:** none

## Overview

Pure data-layout file defining the 96-byte **APP-DESC** application
descriptor struct.  No I/O, no terminal, no UIDL dependency.

Extracted from `app-shell.f` so that code needing only the struct
layout (e.g. `desk.f`, compositor, app launchers) can
`REQUIRE app-desc.f` without pulling in the full shell runtime.

```forth
REQUIRE tui/app-desc.f
```

`PROVIDED akashic-tui-app-desc` — safe to include multiple times.

---

## Struct Layout

96 bytes (12 cells).  Allocate with `CREATE my-desc APP-DESC ALLOT`,
zero-fill with `APP-DESC-INIT`.

| Offset | Constant | Accessor | Stack | Description |
|--------|----------|----------|-------|-------------|
| +0 | `_AD-INIT` | `APP.INIT-XT` | `( -- )` | Init callback |
| +8 | `_AD-EVENT` | `APP.EVENT-XT` | `( ev -- flag )` | Event handler |
| +16 | `_AD-TICK` | `APP.TICK-XT` | `( -- )` | Periodic tick |
| +24 | `_AD-PAINT` | `APP.PAINT-XT` | `( -- )` | Custom painting (0 = pure UIDL) |
| +32 | `_AD-SHUTDOWN` | `APP.SHUTDOWN-XT` | `( -- )` | Cleanup on exit |
| +40 | `_AD-UIDL-A` | `APP.UIDL-A` | addr | UIDL XML source address |
| +48 | `_AD-UIDL-U` | `APP.UIDL-U` | u | UIDL XML source length |
| +56 | `_AD-WIDTH` | `APP.WIDTH` | u | Preferred width (0 = auto) |
| +64 | `_AD-HEIGHT` | `APP.HEIGHT` | u | Preferred height (0 = auto) |
| +72 | `_AD-TITLE-A` | `APP.TITLE-A` | addr | Title string address |
| +80 | `_AD-TITLE-U` | `APP.TITLE-U` | u | Title string length |
| +88 | `_AD-FLAGS` | `APP.FLAGS` | u | Reserved (0) |

Each accessor takes `( desc -- addr )` and returns the field address,
suitable for `@` or `!`.

## API

| Word | Stack | Description |
|------|-------|-------------|
| `APP-DESC` | `( -- 96 )` | Descriptor size constant |
| `APP-DESC-INIT` | `( desc -- )` | Zero-fill a descriptor |

## Usage

```forth
REQUIRE tui/app-desc.f

CREATE my-desc APP-DESC ALLOT
my-desc APP-DESC-INIT
['] my-init   my-desc APP.INIT-XT !
['] my-event  my-desc APP.EVENT-XT !
```

## See Also

- [app-shell.md](app-shell.md) — Shell runtime that executes APP-DESC apps
- [app-compositor.md](app-compositor.md) — Multi-app compositor (uses APP-DESC)
