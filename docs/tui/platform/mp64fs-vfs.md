# akashic/tui/platform/mp64fs-vfs.f — MegaPad-64 VFS composition

**Layer:** TUI platform composition
**Prefix:** `MP64VFS-` (public), `_MP64VFS-` (internal)
**Provider:** `akashic-tui-mp64fs-vfs`
**Dependencies:** `utils/fs/drivers/vfs-mp64fs.f`, `utils/fs/places.f`

This is the concrete storage choice for MegaPad-64 TUI product images.  It
opens the boot block device, binds a raw volume, allocates the 128 KiB VFS
arena, mounts the MP64FS adapter, and reports the resulting abstract VFS to
the places registry as the volume `boot`.

Loading the module performs that composition eagerly.  This is intentional:
Desk may provision applet resources before `ASHELL-RUN`, so the boot volume
must be attached before applet modules and composition-time setup execute.  The supported
`local_testing/akashic_tui.py` packager detects any profile whose dependency
closure contains `tui/app-shell.f` and loads this module immediately after
`ENTER-USERLAND` (and after `networking.f` when native networking is present).
For linked profiles it is the first Akashic composition root in the linked
source; unlinked profiles retain an explicit `REQUIRE tui/platform/mp64fs-vfs.f`.

The places registry is described in `docs/utils/fs/places.md`.
Composition declares places over the volume `boot` by name; the packager
emits the declaration on the lines after this module's load. A composition
that attached its own instance as `boot` before this module loaded has that
instance adopted, and the module mounts nothing.

Shared code must depend on `utils/fs/vfs.f`, not this module.  Choosing a
different storage backend is a product/platform decision and requires only
attaching an abstract VFS as the volume `boot` before applet provisioning.

## API

| Word | Stack | Description |
|------|-------|-------------|
| `MP64VFS-ENSURE` | `( -- )` | Mount the boot MP64FS volume and report it as the volume `boot`, or adopt the instance a composition attached as `boot` first.  Repeated calls change nothing. |

`PROVIDED akashic-tui-mp64fs-vfs` makes repeated `REQUIRE` operations safe.
The explicit `MP64VFS-ENSURE` word is available to platform composition code;
normal applet and host code should only use the abstract VFS API.
