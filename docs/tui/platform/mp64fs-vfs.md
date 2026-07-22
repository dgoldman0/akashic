# akashic/tui/platform/mp64fs-vfs.f — MegaPad-64 VFS composition

**Layer:** TUI platform composition
**Prefix:** `MP64VFS-` (public), `_MP64VFS-` (internal)
**Provider:** `akashic-tui-mp64fs-vfs`
**Dependency:** `utils/fs/drivers/vfs-mp64fs.f`

This is the concrete storage choice for MegaPad-64 TUI product images.  It
opens the boot block device, binds a raw volume, allocates the 128 KiB VFS
arena, mounts the MP64FS adapter, and selects the resulting abstract VFS.

Loading the module performs that composition eagerly.  This is intentional:
Desk may provision applet resources before `ASHELL-RUN`, so an active VFS must
exist before applet modules and composition-time setup execute.  The supported
`local_testing/akashic_tui.py` packager detects any profile whose dependency
closure contains `tui/app-shell.f` and loads this module immediately after
`ENTER-USERLAND` (and after `networking.f` when native networking is present).
For linked profiles it is the first Akashic composition root in the linked
source; unlinked profiles retain an explicit `REQUIRE tui/platform/mp64fs-vfs.f`.

Shared code must depend on `utils/fs/vfs.f`, not this module.  Selecting a
different storage backend is a product/platform decision and requires only
providing an active abstract VFS before applet provisioning.

## API

| Word | Stack | Description |
|------|-------|-------------|
| `MP64VFS-ENSURE` | `( -- )` | Reselect the instance previously owned or adopted by this module, adopt an already active VFS, or mount and select the boot MP64FS volume. |

`PROVIDED akashic-tui-mp64fs-vfs` makes repeated `REQUIRE` operations safe.
The explicit `MP64VFS-ENSURE` word is available to platform composition code;
normal applet and host code should only use the abstract VFS API.
