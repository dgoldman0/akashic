# akashic/tui/app-desc.f — APP-DESC Application Descriptor

**Layer:** 6  
**Lines:** ~95
**Prefix:** `APP.` (public), `_AD-` (internal)  
**Provider:** `akashic-tui-app-desc`  
**Dependencies:** `runtime/instance.f`

## Overview

Pure data-layout file defining the 160-byte **APP-DESC** application
descriptor struct.  It binds a generic `COMP-DESC`/`CINST` to TUI
lifecycle callbacks; it has no terminal or UIDL runtime dependency.

Extracted from `app-shell.f` so that code needing only the struct
layout (e.g. `applets/desk/desk.f`, app launchers) can
`REQUIRE app-desc.f` without pulling in the full shell runtime.

```forth
REQUIRE tui/app-desc.f
```

`PROVIDED akashic-tui-app-desc` — safe to include multiple times.

---

## Struct Layout

160 bytes (20 cells).  Allocate with `CREATE my-desc APP-DESC ALLOT`,
zero-fill with `APP-DESC-INIT`.

| Offset | Constant | Accessor | Stack | Description |
|--------|----------|----------|-------|-------------|
| +0 | `_AD-MAGIC` | `APP.MAGIC` | cell | `APP-MAGIC` |
| +8 | `_AD-ABI` | `APP.ABI` | cell | ABI version |
| +16 | `_AD-SIZE` | `APP.SIZE` | bytes | Descriptor size |
| +24 | `_AD-COMP-DESC` | `APP.COMP-DESC` | addr | Required component descriptor |
| +32 | `_AD-INIT` | `APP.INIT-XT` | `( instance -- )` | Init callback |
| +40 | `_AD-EVENT` | `APP.EVENT-XT` | `( event instance -- flag )` | Event handler |
| +48 | `_AD-TICK` | `APP.TICK-XT` | `( instance -- )` | Periodic tick |
| +56 | `_AD-PAINT` | `APP.PAINT-XT` | `( instance -- )` | Custom painting |
| +64 | `_AD-SHUTDOWN` | `APP.SHUTDOWN-XT` | `( instance -- )` | Final cleanup after close approval |
| +72 | `_AD-UIDL-A` | `APP.UIDL-A` | addr | Inline UIDL source address |
| +80 | `_AD-UIDL-U` | `APP.UIDL-U` | u | Inline UIDL source length |
| +88 | `_AD-WIDTH` | `APP.WIDTH` | u | Preferred width (0 = auto) |
| +96 | `_AD-HEIGHT` | `APP.HEIGHT` | u | Preferred height (0 = auto) |
| +104 | `_AD-TITLE-A` | `APP.TITLE-A` | addr | Title string address |
| +112 | `_AD-TITLE-U` | `APP.TITLE-U` | u | Title string length |
| +120 | `_AD-FLAGS` | `APP.FLAGS` | u | App flags |
| +128 | `_AD-UIDL-FILE-A` | `APP.UIDL-FILE-A` | addr | VFS UIDL path address |
| +136 | `_AD-UIDL-FILE-U` | `APP.UIDL-FILE-U` | u | VFS UIDL path length |
| +144 | `_AD-ACTIVATE` | `APP.ACTIVATE-XT` | `( instance -- )` | Bind instance-relative state |
| +152 | `_AD-REQUEST-CLOSE` | `APP.REQUEST-CLOSE-XT` | `( reason instance -- decision )` | Negotiate normal close |

Each accessor takes `( desc -- addr )` and returns the field address,
suitable for `@` or `!`.

## API

| Word | Stack | Description |
|------|-------|-------------|
| `APP-DESC` | `( -- 160 )` | Descriptor size constant |
| `APP-DESC-INIT` | `( desc -- )` | Zero-fill a descriptor |
| `APP-DESC-VALID?` | `( desc -- flag )` | Validate app header and component descriptor |
| `APP-CLOSE-DECISION-VALID?` | `( decision -- flag )` | Validate ALLOW/CANCEL/DEFER |

Close reasons are `APP-CLOSE-R-QUIT`, `APP-CLOSE-R-WINDOW`, and
`APP-CLOSE-R-HOST-SHUTDOWN`.  A close callback returns one of
`APP-CLOSE-D-ALLOW`, `APP-CLOSE-D-CANCEL`, or `APP-CLOSE-D-DEFER`.
Missing callbacks allow.  Hosts treat a callback `THROW` or unknown decision
as CANCEL.  Only ALLOW authorizes `APP.SHUTDOWN-XT` and resource teardown.

## Usage

```forth
REQUIRE tui/app-desc.f

CREATE my-desc APP-DESC ALLOT
CREATE my-comp COMP-DESC ALLOT
my-comp COMP-DESC-INIT
my-desc APP-DESC-INIT
my-comp         my-desc APP.COMP-DESC !
['] my-init   my-desc APP.INIT-XT !
['] my-event  my-desc APP.EVENT-XT !
['] my-close  my-desc APP.REQUEST-CLOSE-XT !
```

## See Also

- [app-shell.md](app-shell.md) — Shell runtime that executes APP-DESC apps
- [desk.md](applets/desk/desk.md) — Multi-app desktop (APP-DESC applet)
