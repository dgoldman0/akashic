# akashic/tui/widgets/explorer.f — File Explorer Widget

**Layer:** 7  
**Lines:** 607  
**Prefix:** `EXPL-` (public), `_EXPL-` (internal)  
**Provider:** `akashic-tui-explorer`  
**Dependencies:** `tree.f`, `input.f`, `dialog.f`, `draw.f`, `box.f`,
`region.f`, `keys.f`, `../../utils/fs/vfs.f`

## Overview

A persistent, non-modal file-system browser in the style of
VS Code's Explorer panel.  Shows a collapsible tree of directories
and files rooted at a configurable VFS inode.  Supports
expand/collapse, navigation, inline rename, delete with
confirmation, and new file/directory creation.

The explorer **bridges `tree.f` to the Akashic VFS layer**.  VFS
inodes ARE the tree nodes — each "node" passed to tree callbacks is
simply a VFS inode pointer.  No node cache, no mapping arrays, no
order arrays.  The VFS child→sibling linked-list structure maps
directly to `tree.f`'s `children-xt` / `next-xt` callback model.

### Key Bindings

| Key | Action |
|-----|--------|
| Up / Down / PgUp / PgDn / Home / End | Move the selection (delegated to the embedded tree) |
| Right | Expand the selected directory |
| Left | Collapse the selected directory, or select its parent |
| Enter | Open a file (fires `on-open-xt`) or expand/collapse a directory |
| F2 | Start inline rename of selected entry |
| F5 | Refresh (re-trigger `_VFS-ENSURE-CHILDREN`, redraw) |
| Delete | Delete selected entry with `DLG-CONFIRM` dialog |
| Ctrl+N | Create new file (`"newfile"`) in selected directory |
| Ctrl+Shift+N | Create new subdirectory (`"newfolder"`) |
| Ctrl+R | Refresh (same as F5) |
| Ctrl+H | Toggle show/hide hidden files |
| Escape | Cancel rename (when active); no-op otherwise |

Pointer and item events go to the embedded tree: a primary press selects
the row under it (and toggles a directory when it lands on the mark), the
wheel scrolls, and a renderer's item events select, open, expand and
collapse entries by key.  Whenever the selection moves to another entry,
by key, press or item event, the explorer fires `on-select-xt`.

### Visual Layout

```
┌─ Explorer ───────────────┐
│▼ projects                │
│  ▼ akashic               │
│    ▶ tui                 │
│    ▶ utils               │
│      README.md           │
│      build.f             │
│  ▶ demos                 │
│    notes.txt             │
└──────────────────────────┘
```

Labels are the entry names.  Directories carry the tree's
expand/collapse mark (`▼` / `▶`); files do not.

## VFS ↔ Tree Callback Mapping

Five callbacks are passed to `TREE-NEW` at construction.  Each
receives a VFS inode pointer as the node token:

| Callback | Signature | Implementation |
|----------|-----------|----------------|
| `_EXPL-CHILDREN` | `( inode -- first-child \| 0 )` | Returns 0 for files. For dirs: calls `_VFS-ENSURE-CHILDREN` then `IN.CHILD @` |
| `_EXPL-NEXT` | `( inode -- sibling \| 0 )` | `IN.SIBLING @` |
| `_EXPL-LABEL` | `( inode -- addr len )` | The name, via `IN.NAME @ _VFS-STR-GET` |
| `_EXPL-LEAF?` | `( inode -- flag )` | `IN.TYPE @ VFS-T-DIR <>` |
| `EXPL-ENTRY-KEY` | `( parent-key inode -- key )` | 64-bit FNV-1a over the parent's key and the name, never 0 |

Lazy loading is automatic — `_VFS-ENSURE-CHILDREN` populates a
directory's children from the backing store on first access.  The
widget is agnostic to the backing store (MP64FS, FAT, ramdisk, etc.).

### Entry Keys

Names are unique within a directory, so an entry's key, hashed from its
parent's key and its name, differs from every entry shown with it and
stays the same across refreshes and reloads.  Inode addresses would not:
the VFS may evict an entry and later load it into a new inode.  The tree keeps its
expansion and selection by these keys, and a rich renderer names entries
by them in item events.

## Descriptor Layout (104 bytes)

| Offset | Field | Type | Description |
|--------|-------|------|-------------|
| +0..+32 | header | widget header | Standard 5-cell header, type=WDG-T-EXPLORER (16) |
| +40 | tree-widget | address | Embedded `TREE-*` widget pointer |
| +48 | vfs | address | VFS instance pointer |
| +56 | root-inode | address | Root directory inode for this view |
| +64 | on-open-xt | xt or 0 | File-opened callback `( inode explorer -- )` |
| +72 | on-select-xt | xt or 0 | Selection-changed callback `( inode explorer -- )` |
| +80 | rename-input | address or 0 | `INP-*` widget for inline rename (0 when inactive) |
| +88 | flags2 | u | Bit 0: show-hidden, Bit 1: rename-active |
| +96 | rename-buf | address | 256-byte rename buffer (allocated at construction) |

### Flags2 Bits

| Constant | Value | Meaning |
|----------|-------|---------|
| `_EXPL-F2-HIDDEN` | 1 | Show hidden files (names starting with `.`) |
| `_EXPL-F2-RENAME` | 2 | Rename mode is currently active |

## API Reference

### Constructor / Destructor

| Word | Stack | Description |
|------|-------|-------------|
| `EXPL-NEW` | `( rgn vfs root-inode -- widget )` | Create explorer bound to a VFS, rooted at given inode. Allocates descriptor (104 B), rename buffer (256 B), and creates the embedded tree with the VFS callbacks. |
| `EXPL-FREE` | `( widget -- )` | Free rename input (if active), rename buffer, embedded tree widget, and descriptor |

### Selection

| Word | Stack | Description |
|------|-------|-------------|
| `EXPL-SELECTED` | `( widget -- inode )` | The selected entry's inode (via `TREE-SELECTED`) |
| `EXPL-ENTRY-KEY` | `( parent-key inode -- key )` | An entry's stable key |
| `EXPL-ON-OPEN` | `( xt widget -- )` | Set file-opened callback `( inode explorer -- )`. Fires when a file is opened by Enter or a renderer's OPEN. |
| `EXPL-ON-SELECT` | `( xt widget -- )` | Set selection-changed callback `( inode explorer -- )`. Fires whenever the selection moves to another entry. |

### Expand / Collapse

| Word | Stack | Description |
|------|-------|-------------|
| `EXPL-EXPAND-ALL` | `( widget -- )` | Expand entire tree (delegates to `TREE-EXPAND-ALL`) |
| `EXPL-COLLAPSE-ALL` | `( widget -- )` | Collapse every directory (delegates to `TREE-COLLAPSE-ALL`) |

### Tree Mutation

| Word | Stack | Description |
|------|-------|-------------|
| `EXPL-RENAME` | `( widget -- )` | Start inline rename — creates `INP-*` widget pre-filled with current name, sets rename-active flag |
| `EXPL-DELETE` | `( widget -- )` | Delete selected entry — shows `DLG-CONFIRM`, then `VFS-RM` with CWD swap to parent, then `VFS-SYNC` |
| `EXPL-NEW-FILE` | `( widget -- )` | Create `"newfile"` in the selected directory (or parent of selected file) via `VFS-MKFILE`, then `VFS-SYNC` |
| `EXPL-NEW-DIR` | `( widget -- )` | Create `"newfolder"` subdirectory via `VFS-MKDIR`, then `VFS-SYNC` |

### Configuration

| Word | Stack | Description |
|------|-------|-------------|
| `EXPL-ROOT!` | `( inode widget -- )` | Change root inode, free the old tree, create a new one, refresh |
| `EXPL-SHOW-HIDDEN!` | `( flag widget -- )` | Set show-hidden flag (TRUE = show, FALSE = hide) |
| `EXPL-SHOW-HIDDEN?` | `( widget -- flag )` | Query current show-hidden state |
| `EXPL-REFRESH` | `( widget -- )` | Mark tree dirty and trigger redraw |

### Accessors

| Word | Stack | Description |
|------|-------|-------------|
| `EXPL-VFS` | `( widget -- vfs )` | Get the VFS instance pointer |
| `EXPL-TREE` | `( widget -- tree-widget )` | Get the embedded tree widget pointer |

## Internal Architecture

### Tree Context

The explorer stores itself in the embedded tree's context cell
(`TREE-CONTEXT!`).  `_EXPL-CHILDREN` reads the explorer's VFS through
`TREE-WALK-CONTEXT`, so the callbacks always serve the tree that is
walking, even when several explorers exist or a snapshot capture visits
an explorer that is not the active one.

### CWD Swap Pattern for Mutations

`VFS-MKFILE`, `VFS-MKDIR`, and `VFS-RM` all resolve filenames
relative to the VFS current working directory (`V.CWD`).  To create
or delete entries in a specific directory, the explorer:

1. Saves the current `V.CWD` to a VARIABLE
2. Sets `V.CWD` to the target directory inode
3. Calls the VFS mutation word
4. Restores the original `V.CWD`

This avoids needing an absolute-path version of the VFS API.

### Inline Rename Flow

1. User presses F2 → `EXPL-RENAME` is called
2. Gets selected inode, reads its name via `IN.NAME @ _VFS-STR-GET`
3. Creates `INP-NEW` widget using the explorer's region and rename buffer
4. Pre-fills the input with `INP-SET-TEXT`, sets `_EXPL-RENAME-COMMIT`
   as the submit callback via `INP-ON-SUBMIT`
5. Sets `_EXPL-F2-RENAME` flag in `flags2`
6. While rename is active, `_EXPL-HANDLE` routes all keys to the
   input widget (except Escape, which cancels)
7. On Enter (submit): `_EXPL-RENAME-COMMIT` validates the name
   (non-empty, no `/`, no duplicate sibling via `_VFS-FIND-CHILD`),
   allocates a new string in the VFS string pool, releases the old
   name, marks the inode dirty, calls `VFS-SYNC`, and clears rename state
8. On Escape: `_EXPL-RENAME-CANCEL` frees the input widget and
   clears the rename flag — no changes made

### Draw Handler (`_EXPL-DRAW`)

Delegates to the embedded tree widget's `WDG-DRAW`.  If rename mode
is active, also draws the input widget on top of the tree.

### Event Handler (`_EXPL-HANDLE`)

Four-phase dispatch:

1. **Rename mode**: If `_EXPL-F2-RENAME` is set, intercept Escape
   (cancel) and forward everything else to the input widget.
2. **Pointer and item events**: delegated to the tree, which reports
   through its callbacks.
3. **Special keys**: F2 (rename), F5 (refresh), Delete, and Escape
   (no-op) are handled here.  Navigation keys and Enter go to the tree,
   which reports through its select and open callbacks.
4. **Ctrl+key combos**: Ctrl+N (new file), Ctrl+Shift+N (new dir),
   Ctrl+H (toggle hidden), Ctrl+R (refresh).

Returns `-1` (consumed) or `0` (not consumed).

### Tree Callbacks (`_EXPL-ON-TREE-SEL`, `_EXPL-ON-TREE-OPEN`)

Registered with `TREE-ON-SELECT` and `TREE-ON-OPEN` at construction.
The tree fires the first when its selection moves; the explorer calls
its `on-select-xt` with `( inode explorer -- )`.  The tree fires the
second when the selection is opened; a directory expands or collapses,
and a file goes to `on-open-xt` with `( inode explorer -- )`.

## Memory Budget

| Component | Size |
|-----------|------|
| Explorer descriptor | 104 B |
| Rename buffer (persistent) | 256 B |
| Embedded tree widget | 160 B |
| Tree expanded-key set | 8 B per expanded directory, allocated 16 keys at a time and doubled as needed |
| Inline rename input (temporary) | 104 B |

No node cache.  No order array.  The VFS inode linked-list provides
O(1) child/sibling access, eliminating the 12+ KiB of cache memory
that a raw-DIRENT approach would need.

## Concurrency

When `GUARDED` is defined and true, all 14 public words are wrapped
with `WITH-GUARD` using a dedicated `_expl-guard` mutex.  The guard
section saves the original xt as a CONSTANT, then redefines the word
to acquire the guard, execute the saved xt, and release.

Guarded words: `EXPL-NEW`, `EXPL-SELECTED`, `EXPL-ON-OPEN`,
`EXPL-ON-SELECT`, `EXPL-ROOT!`, `EXPL-EXPAND-ALL`,
`EXPL-COLLAPSE-ALL`, `EXPL-SHOW-HIDDEN!`, `EXPL-RENAME`,
`EXPL-DELETE`, `EXPL-NEW-FILE`, `EXPL-NEW-DIR`, `EXPL-REFRESH`,
`EXPL-FREE`.

## Deferred (Not Yet Implemented)

| Word | Stack | Description |
|------|-------|-------------|
| `EXPL-REVEAL` | `( widget inode -- )` | Walk `IN.PARENT` chain, expand ancestors, scroll selected inode into view |
| `EXPL-CONTEXT-MENU` | `( widget -- )` | Show context action popup menu (Open / Rename / Delete / New File / New Folder / Refresh) |

## Design Notes

- **Zero-copy VFS bridge.** Inodes are tree nodes — no translation
  layer.  Each of the five tree callbacks is a few lines of Forth.
- **Variable-based handlers.** All mutation words and the event
  handler store the widget pointer in VARIABLEs to avoid deep stack
  gymnastics.  This matches the style used by `tree.f`, `input.f`,
  and `dialog.f`.
- **CWD swap for mutations.** Because `VFS-MKFILE`/`VFS-MKDIR`/
  `VFS-RM` resolve relative to `V.CWD`, the explorer temporarily
  swaps CWD to the target directory, performs the operation, then
  restores.
- **`menu.f` not required.** The roadmap spec included context
  menus but they are deferred.  The current dependency list omits
  `menu.f`.
- **S" is compile-only** in KDOS Forth.  All `S"` usage in the
  explorer is inside colon definitions.
- **`[']` inside colon definitions** for compile-time xt
  resolution.  Interpreter-level code uses `'` (tick).

## Test Coverage (31 tests in `test_explorer.py`)

| Group | Tests |
|-------|-------|
| create | type = WDG-T-EXPLORER (16) |
| tree-embedded | non-zero, type = WDG-T-TREE (11) |
| vfs-accessor | EXPL-VFS matches stored VFS |
| selected-initial | EXPL-SELECTED = root inode |
| leaf-callback | root (dir) → false; file → true |
| children-callback | root → non-zero first child |
| next-callback | first child → has sibling |
| label-callback | root label is the inode name |
| expand-root | 5 visible nodes (root + 4 children) |
| expand-all | 6 visible (root + docs + readme + src + hello.f + notes.txt) |
| nav-down | cursor moves to 1 |
| nav-up | down then up → cursor 0 |
| enter-toggle-dir | Enter on root → 5 visible |
| enter-fires-on-open | Enter on file → callback fires with VFS-T-FILE inode |
| on-select | Down arrow → callback fires once |
| new-file | "newfile" appears in root (VFS-RESOLVE) |
| new-dir | "newfolder" appears in root (VFS-RESOLVE) |
| new-file-in-subdir | "newfile" in src/ (VFS-RESOLVE) |
| refresh | marks widget dirty |
| show-hidden | initial false; set to true |
| rename-flag | sets flags2 bit 1 |
| rename-input | creates input widget (non-zero) |
| f5-refresh | F5 returns consumed (-1) |
| f2-rename | F2 activates rename mode |
| rename-esc-cancels | Escape clears rename flag |
| unrelated-key | char 'a' not consumed (0) |
| collapse-all | 1 visible node |
| free | completes without crash |

### Test VFS Structure

The test suite creates a ramdisk VFS with this layout:

```
/                  (root dir)
├── docs/          (subdir)
│   └── readme     (file)
├── src/           (subdir, empty)
├── hello.f        (file)
└── notes.txt      (file)
```

Children are prepended (newest-first), so the child order after
setup is: `notes.txt → hello.f → src/ → docs/`.
