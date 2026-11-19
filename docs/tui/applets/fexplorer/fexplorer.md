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
│ (EXPL-NEW) │  Name               Size Type     │
│            │  README             1.2K file     │
│  tree with │  src                     dir      │
│  VFS inodes│  build.f             540 file     │
│  rename    │        (LST-NEW table)            │
│  Ctrl+N    │  ── or ──                         │
│ Ctrl+Shift+N│                                    │
│  Del,F2,F5 │  (MEDIA-NEW) file preview         │
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
| media.f | `akashic-tui-media` |
| input.f | `akashic-tui-input` |
| dialog.f | `akashic-tui-dialog` |
| app-desc.f | `akashic-tui-app-desc` |
| app-shell.f | `akashic-tui-app-shell` |
| draw.f | `akashic-tui-draw` |
| region.f | `akashic-tui-region` |
| keys.f | `akashic-tui-keys` |
| vfs.f | `akashic-vfs` |
| vfs-copy.f | `akashic-vfs-copy` |

## Public Words

### Entry Points

| Word | Stack | Description |
|------|-------|-------------|
| `FEXP-ENTRY` | `( desc -- )` | Fill an APP-DESC with fexplorer callbacks. Called by app-loader or desk. |
| `FEXP-RUN` | `( -- )` | Standalone entry — creates descriptor and runs via ASHELL-RUN. |

### Clipboard

| Word | Stack | Description |
|------|-------|-------------|
| `FEXP-CLIP-COPY` | `( -- )` | Put the selected file or folder on the clipboard to copy. |
| `FEXP-CLIP-CUT` | `( -- )` | Put the selected file or folder on the clipboard to move. |
| `FEXP-CLIP-PASTE` | `( -- )` | Copy the clipboard's file or folder, or move it after a cut, into the selected directory, the selected file's directory, or the listed directory, in any place of the set. |

### Constants

| Constant | Value | Description |
|----------|-------|-------------|
| `FEXP-SORT-NAME` | 0 | Sort by name (default) |
| `FEXP-SORT-SIZE` | 1 | Sort by size |
| `FEXP-SORT-TYPE` | 2 | Sort by type (dirs first) |

### Agent-visible observation

The `fexplorer.preview.text` resource capability returns `null` unless the
current selection is a file. Otherwise it looks the selection's path up and
returns at most 4096 bytes of valid UTF-8 file content. The lookup, open, read,
and descriptor cleanup share one VFS transaction; malformed text, transfer
failure, or an unexpected post-open exception fails without disclosing a
partial value. Both capabilities report `CBUS-S-NOT-FOUND` when the selected
entry no longer exists.

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
| Right | Expand directory |
| Left | Collapse directory, or select its parent |
| Enter | Expand/collapse a directory, or open a file |
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
- **Details**: a table (the list widget with Name, Size and Type columns and
  a header row) showing the directory's entries.  Selecting a row loads a
  file's preview without leaving the table; opening a row enters a directory
  or opens a file with its application.
- **Preview**: a `<media id=preview>` element whose
  [media widget](../../widgets/media.md) shows the selected file the way its
  kind is shown: a QOI picture in half-block cells, a text or HTML file whole
  in a text area, and otherwise the file's name, kind and size with why it
  shows only those.

## Integration

### With app-loader / desk

```forth
\ In an app manifest:
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

- File Explorer works in the place set it is given (`CINST-PLACES`,
  `docs/utils/fs/places.md`) and names no place. The sidebar's top rows
  are the set's places; the listed directory, the selection, a pending
  delete and the clipboard's source are each a place and a path in it.
  It opens listing the folder of the set's documents place, where a
  person's documents go, or of its first place when the set declares
  none.
  Every change goes through the `PLACE-` words, so a read-only place
  refuses it and nothing reaches outside a place's folder. The status
  bar shows the selection's path, after its place's label when the set
  has several places. Go To takes a path in the listed directory's
  place, or the full form `vfs://<place>/<path>`.
- A paste copies with `PLACE-COPY`, or after a cut moves with
  `PLACE-MOVE` ([vfs-copy.md](../../../utils/fs/vfs-copy.md)), a file or a
  folder with all it holds, from the clipboard's place to the place of the
  directory the paste goes to, which may be on another volume. A read-only
  destination place refuses the paste, and so does a cut's read-only
  source place.
- `fexplorer.toml` is read from the set's origin.
- File Explorer never keeps a VFS entry between operations. Another applet
  may replace or remove an entry at any time; Daybook, for one, saves by
  renaming a new copy over its file, which frees the old entry for the next
  file to reuse. The listed directory and the selection, from either pane,
  are kept as paths, and every action looks its path up when it runs. The
  path buffers take a path as long as the VFS takes (`VFS-PATH-MAX`, 4,096
  bytes), and the command bar the longest full form `vfs://<place>/<path>`;
  a longer path is refused rather than cut short, so nothing is selected.
- Listing a directory walks its VFS children once
  (`_VFS-ENSURE-CHILDREN?`, then the `IN.CHILD @` / `IN.SIBLING @` chain) and
  copies each entry's name, type, size and key into one allocated block of
  row records, sized to the directory. Drawing and capture read only these
  copies, so a row always shows the entry as it was listed. The table is
  that snapshot: File Explorer's own changes and F5 list the directory
  again.
- The rows are sorted in place by an exchange sort: by name, by size
  (smaller first), or by type (directories first, names ascending within
  each type).
- The sidebar tree stays rooted at the places and walks the VFS each time
  it draws. Backspace and Go To change only the listed directory, and
  Backspace stops at its place's folder.
- Rows and tree entries are keyed by `EXPL-ENTRY-KEY`, a hash of the parent's
  key and the name, chained from the place's row; the listed directory's
  key comes from its path (`EXPL-PATH-KEY`), so a rich renderer's item events name the entry it drew
  even after a refresh.
- Selecting a file gives its volume and its path there (`PLACE-BIND`) to
  the preview's media widget, which opens it. A link in a previewed
  document is followed only to a file in the same place. A text file is read whole into a buffer sized to
  it and closed; a picture keeps its file open while it shows and decodes
  only once the Preview tab draws it, a slice a pass from the shell's
  service. A file that cannot be read, or text the memory refuses, shows its
  facts and the reason.
- One 32 KiB scratch buffer serves a paste's copy, which writes 32 KiB at
  a time and compares the copy with its source 16 KiB at a time, the
  properties text, and the agent's text preview.
- Path built by walking `IN.PARENT @` chain up to root, then reversing segments
- Copy and cut keep the selected file or folder in the clipboard as its
  place and its path there, as the selection is kept. They refuse a place's
  own folder, which has no name to paste it under. A paste puts the file or
  folder under its own name, and refuses a name the destination already
  holds, the source's own among them, before anything is written.
- The copy writes a stage, whose name starts with `.s-`, beside the
  destination: a file, or a folder holding the whole tree. It syncs, reads
  the stage back against the source and only then renames it to its own
  name. A paste that fails therefore leaves nothing, and its notice says
  why: no space, a copy that did not match its source, a place that is
  read-only or unavailable, a folder pasted inside itself, a name or path
  too long for the destination, a folder holding a link or a device, or a
  storage error.
- A cut moves the file or folder: by one rename when both places are on one
  volume, and otherwise by the copy, after which the source is removed. If
  the source cannot be removed, the toast says so, as it does when a
  pasted copy stands but its volume did not confirm the last sync. The
  clipboard is cleared once a cut's paste stands.
- A paste runs to its end before File Explorer answers again, so a folder
  of many files keeps Desk waiting while it copies.
- Create, rename, and post-confirmation delete mutations are bounded
  `VFS-TRANSACTION` operations. Modal confirmation never holds the VFS guard
  across its input/yield loop.
- Go To, New File, New Folder, and Rename share a non-blocking command bar
  mounted over the status row, so they work both standalone and inside Desk.
- Selection is unified across the sidebar and Details list. Preview,
  properties, rename, delete, copy, cut, and paste all act on the entry at
  the selection's path. Renaming or deleting the listed directory moves the
  listing with it. The table shows a row selected only when the selection
  is that row; when the selection is the listed directory itself, or an
  entry the tree chose elsewhere, no row is selected (`LST-DESELECT`), so a
  press on any row chooses it. A paste, like every other change, lists the
  directory again and updates the item count.
- Names are validated before mutation: not empty, no slash, and no longer
  than the place's volume takes (`PLACE-NAME-LIMIT`: 23 bytes on MP64FS,
  255 on ext4). The VFS layer rejects duplicate sibling names.
