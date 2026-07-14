# fexplorer — File Explorer Applet

Full-featured dual-pane file explorer for the Megapad-64 TUI.

**Provider:** `akashic-tui-fexplorer`

## Architecture

```
┌────────────── Menu Bar (MNU-NEW) ──────────────┐
│ File   Edit   View   Tools                     │
├────────────┬───────────────────────────────────┤
│  Explorer  │ [Details] [Preview]  (TAB-NEW)    │
│  sidebar   ├───────────────────────────────────┤
│ (EXPL-NEW) │  Name     Size   Type             │
│            │  README   1.2K   file             │
│  tree with │  src/     <DIR>  dir              │
│  VFS inodes│  build.f  540    file             │
│  rename    │        (LST-NEW)                  │
│  Ctrl+N    │  ── or ──                         │
│ Ctrl+Shift+N│                                    │
│  Del,F2,F5 │  (TXTA-NEW) file preview          │
├────────────┴───────────────────────────────────┤
│ 42 items                 /projects/akashic      │
└────────────────────────────────────────────────┘
```

## Dependencies

| Module | Provider |
|--------|----------|
| explorer.f | `akashic-tui-explorer` |
| split.f | `akashic-tui-split` |
| list.f | `akashic-tui-list` |
| tabs.f | `akashic-tui-tabs` |
| status.f | `akashic-tui-status` |
| menu.f | `akashic-tui-menu` |
| textarea.f | `akashic-tui-textarea` |
| input.f | `akashic-tui-input` |
| dialog.f | `akashic-tui-dialog` |
| app-desc.f | `akashic-tui-app-desc` |
| app-shell.f | `akashic-tui-app-shell` |
| draw.f | `akashic-tui-draw` |
| region.f | `akashic-tui-region` |
| keys.f | `akashic-tui-keys` |
| vfs.f | `akashic-vfs` |

## Public Words

### Entry Points

| Word | Stack | Description |
|------|-------|-------------|
| `FEXP-ENTRY` | `( desc -- )` | Fill an APP-DESC with fexplorer callbacks. Called by app-loader or desk. |
| `FEXP-RUN` | `( -- )` | Standalone entry — creates descriptor and runs via ASHELL-RUN. |

### Clipboard

| Word | Stack | Description |
|------|-------|-------------|
| `FEXP-CLIP-COPY` | `( -- )` | Copy selected item to clipboard. |
| `FEXP-CLIP-CUT` | `( -- )` | Cut selected item to clipboard. |
| `FEXP-CLIP-PASTE` | `( -- )` | Paste a copied file into the selected or current directory. |

### Constants

| Constant | Value | Description |
|----------|-------|-------------|
| `FEXP-SORT-NAME` | 0 | Sort by name (default) |
| `FEXP-SORT-SIZE` | 1 | Sort by size |
| `FEXP-SORT-TYPE` | 2 | Sort by type (dirs first) |

### Agent-visible observation

The `fexplorer.preview.text` resource capability returns `null` unless the
current selection is a file. Otherwise it revalidates the selected inode's
exact VFS path and returns at most 4096 bytes of valid UTF-8 file content. Path
verification, open, read, and descriptor cleanup share one VFS transaction;
malformed text, truncated path identity, transfer failure, or an unexpected
post-open exception fails without disclosing a partial value.

## Key Bindings

| Key | Action |
|-----|--------|
| **Tab** | Cycle focus: tree → detail/preview → tree |
| **F10** | Open menu bar |
| **Backspace** | Navigate to parent directory |
| **Ctrl+Q** | Quit |
| **Ctrl+G** | Go to path (overlay input) |
| **Ctrl+I** | Properties dialog |
| **Ctrl+C** | Copy to clipboard |
| **Ctrl+X** | Cut to clipboard |
| **Ctrl+V** | Paste from clipboard |
| **Ctrl+H** | Toggle hidden files |
| **Alt+1** | Switch to Details tab |
| **Alt+2** | Switch to Preview tab |
| **Ctrl+N** | Create a named file in the selected/current directory |
| **Ctrl+Shift+N** | Create a named folder |
| **F2** | Rename the selected item |
| **F5** | Refresh both panes |
| **Delete** | Confirm and delete the selected item |
| **Esc** | Close menu / cancel goto overlay |

### Tree Sidebar (inherited from explorer.f)

| Key | Action |
|-----|--------|
| Up/Down | Navigate tree |
| Right/Enter | Expand directory / open file preview |
| Left | Collapse directory |
| F2 | Rename |
| F5 | Refresh |
| Del | Delete |
| Ctrl+N | New file |
| Ctrl+Shift+N | New directory |

## Menu Structure

- **File**: New File, New Folder, Delete, Rename, Refresh, Quit
- **Edit**: Copy, Cut, Paste
- **View**: Show Hidden, Sort by Name/Size/Type, Expand All, Collapse All
- **Tools**: Go to Path, Properties

## Layout

Three regions from the root:

1. **Menu row**: top row (h=1)
2. **Body**: rows 1..H-2, split vertically (tree left ~30%, detail/preview right ~70%)
3. **Status bar**: bottom row (h=1)

The right pane uses tabbed view with two tabs:
- **Details**: List widget showing directory entries (name, size, type columns)
- **Preview**: Read-only textarea showing file content (up to 32 KiB)

## Integration

### With app-loader / desk

```forth
\ In app-manifest or desk hotbar:
FEXP-ENTRY
```

The word fills an APP-DESC struct with callbacks. The desk or app-loader
then calls `ASHELL-RUN` with that descriptor.

### Standalone

```forth
FEXP-RUN
```

Creates its own descriptor and runs the app-shell event loop.
In a `GUARDED` build this lifecycle word deliberately runs unwrapped on the
applet owner core, matching `ASHELL-RUN`: the event loop may block or yield,
so a cross-core launcher must post a launch request instead of calling it
while retaining the Explorer guard.

## Internals

- Detail list populated by walking VFS inode children (`IN.CHILD @` / `IN.SIBLING @` chain)
- `_VFS-ENSURE-CHILDREN` called before first child walk to lazy-load from binding
- Bubble sort on parallel arrays (items, inodes, formatted lines)
- Preview reads up to 32 KiB with an exact checked transfer; a failed preview
  read leaves the prior view intact.
- Path built by walking `IN.PARENT @` chain up to root, then reversing segments
- Clipboard captures a canonical source path rather than relying on a live
  inode pointer. Directories, same-path pastes, and existing destinations are
  rejected before mutation.
- Paste holds `VFS-TRANSACTION` across validation, context selection, exact
  chunked I/O, sync, byte verification, cleanup, and context restoration. A
  pre-verification failure removes the newly created destination; cleanup
  uncertainty is reported explicitly.
- Cut removes the source only after the copied destination has synced and
  byte-verified. If source deletion fails, both verified copies remain and the
  app reports the incomplete cut instead of silently losing data.
- Create, rename, and post-confirmation delete mutations are bounded
  `VFS-TRANSACTION` operations. Modal confirmation never holds the VFS guard
  across its input/yield loop.
- Go To, New File, New Folder, and Rename share a non-blocking command bar
  mounted over the status row, so they work both standalone and inside Desk.
- Selection is unified across the sidebar and Details list. Preview,
  properties, rename, delete, copy, cut, and paste all act on that same inode.
- MP64FS names are validated before mutation (non-empty, no slash, at most 23
  UTF-8 bytes), and duplicate sibling names are rejected by the VFS layer.
