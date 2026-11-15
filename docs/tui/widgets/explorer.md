# akashic/tui/widgets/explorer.f — File Explorer Widget

**Layer:** 7  
**Lines:** 607  
**Prefix:** `EXPL-` (public), `_EXPL-` (internal)  
**Provider:** `akashic-tui-explorer`  
**Dependencies:** `tree.f`, `input.f`, `dialog.f`, `draw.f`, `box.f`,
`region.f`, `keys.f`, `../../utils/fs/vfs.f`, `../../utils/fs/places.f`

## Overview

A persistent, non-modal file-system browser in the style of
VS Code's Explorer panel.  It is given a place set
(`docs/utils/fs/places.md`) and shows a collapsible tree whose top rows
are the set's places, by label; each opens onto its folder, with that
folder's directories and files below it.  A place that is unavailable
shows why after its label, as in `Card (volume missing)`, and stays
closed.  Supports expand/collapse, navigation, inline rename, delete
with confirmation, and new file/directory creation, each of which a
read-only place refuses and none of which applies to a place's own row.

The explorer **bridges `tree.f` to the places and the VFS layer**.  A
top row's node is the place handle the set gave out; every other node is
a VFS inode pointer.  No node cache, no mapping arrays, no order arrays.
The VFS child→sibling linked-list structure maps directly to `tree.f`'s
`children-xt` / `next-xt` callback model.  The same canonical tree rows
serve the cell fallback and rich output.

### Key Bindings

| Key | Action |
|-----|--------|
| Up / Down / PgUp / PgDn / Home / End | Move the selection (delegated to the embedded tree) |
| Right | Expand the selected directory |
| Left | Collapse the selected directory, or select its parent |
| Enter | Open a file (fires `on-open-xt`) or expand/collapse a directory |
| F2 | Start inline rename of selected entry |
| F5 | Refresh (re-trigger `_VFS-ENSURE-CHILDREN`, redraw) |
| Delete | Ask with `DLG-CONFIRM` before deleting the selected entry |
| Ctrl+N | Create new file (`"newfile"`) in the selected directory, or in the selected place's folder |
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

## Place and VFS ↔ Tree Callback Mapping

Five callbacks are passed to `TREE-NEW` at construction.  Each
receives a node token, which is a place when the explorer's set holds
it (`PLSET-MEMBER?`) and a VFS inode pointer otherwise:

| Callback | Signature | Implementation |
|----------|-----------|----------------|
| `_EXPL-CHILDREN` | `( node -- first-child \| 0 )` | A place gives its folder's children, and none when it is unavailable. Returns 0 for files. For dirs: calls `_VFS-ENSURE-CHILDREN` on the entry's own volume, then `IN.CHILD @` |
| `_EXPL-NEXT` | `( node -- sibling \| 0 )` | `PLACE-NEXT` for a place, `IN.SIBLING @` for an entry |
| `_EXPL-LABEL` | `( node -- addr len )` | A place's label, with its reason when unavailable; an entry's name |
| `_EXPL-LEAF?` | `( node -- flag )` | False for a place; `IN.TYPE @ VFS-T-DIR <>` for an entry |
| `_EXPL-KEY` | `( parent-key node -- key )` | `EXPL-PLACE-KEY` for a place, `EXPL-ENTRY-KEY` for an entry |

Lazy loading is automatic — `_VFS-ENSURE-CHILDREN` populates a
directory's children from the backing store on first access.  The
widget is agnostic to the backing store (MP64FS, ext4, ramdisk, etc.).

A place row's label is kept in a block the explorer owns, made when the
explorer is made, when the set's revision moves and on `EXPL-REFRESH`, so
the text a renderer was given stays where it is between those.

The tree calls the key callback for each row in order, and a query stops
at the row it finds.  The callback notes each place as the walk enters
its rows, so after a query the noted place is the place of the row
found.  `EXPL-SELECTED` and the two callbacks report that place, which
is exact even when two places of the set show the same folder.

### Entry Keys

A place's key is hashed from its name, which is unique in a set, and
an entry of its folder has the place's key as its parent's.  Names are
unique within a directory, so an entry's key, hashed from its
parent's key and its name, differs from every entry shown with it and
stays the same across refreshes and reloads.  Inode addresses would not:
the VFS may evict an entry and later load it into a new inode.  The tree keeps its
expansion and selection by these keys, and a rich renderer names entries
by them in item events.

## Descriptor Layout (160 bytes)

| Offset | Field | Type | Description |
|--------|-------|------|-------------|
| +0..+32 | header | widget header | Standard 5-cell header, type=WDG-T-EXPLORER (16) |
| +40 | tree-widget | address | Embedded `TREE-*` widget pointer |
| +48 | set | address | The place set |
| +56 | walk-place | address or 0 | Place of the rows the tree last walked |
| +64 | on-open-xt | xt or 0 | File-opened callback `( inode place explorer -- )` |
| +72 | on-select-xt | xt or 0 | Selection-changed callback `( inode place explorer -- )` |
| +80 | rename-input | address or 0 | `INP-*` widget for inline rename (0 when inactive) |
| +88 | flags2 | u | Bit 0: show-hidden, Bit 1: rename-active |
| +96 | rename-buf | address | 256-byte rename buffer (allocated at construction) |
| +104 | delete | address or 0 | The entry a delete question asks about |
| +112 | seen | u | The tree's, the rename input's and the set's revisions it last counted |
| +120 | labels | address or 0 | The place rows' labels, one block |
| +128 | path-buf | address | Path scratch, `VFS-PATH-MAX` bytes |
| +136 | delete-place | address or 0 | The place of the entry a delete question asks about |
| +144 | first | address or 0 | The set's first place when the tree was made |
| +152 | set-rev | u | The set's revision the labels were made at |

The explorer's revision moves when its tree, its rename input or its set
changes, as well as when it changes itself: it compares their revisions with those it last
counted after it passes on an event and after it draws, and its own words
that change the tree count the change.

### Flags2 Bits

| Constant | Value | Meaning |
|----------|-------|---------|
| `_EXPL-F2-HIDDEN` | 1 | Show hidden files (names starting with `.`) |
| `_EXPL-F2-RENAME` | 2 | Rename mode is currently active |

## API Reference

### Constructor / Destructor

| Word | Stack | Description |
|------|-------|-------------|
| `EXPL-NEW` | `( rgn set -- widget )` | Create an explorer of a place set, which stays the caller's. Allocates the descriptor, the rename buffer (256 B), the path scratch and the place labels, and creates the embedded tree with the VFS callbacks. |
| `EXPL-FREE` | `( widget -- )` | Free rename input (if active), the buffers, the labels, embedded tree widget, and descriptor |

### Selection

| Word | Stack | Description |
|------|-------|-------------|
| `EXPL-SELECTED` | `( widget -- inode place )` | The selected entry and its place; inode 0 on a place's own row, and 0 0 when nothing is selected |
| `EXPL-PLACE-KEY` | `( place -- key )` | A place row's stable key |
| `EXPL-ENTRY-KEY` | `( parent-key inode -- key )` | An entry's stable key |
| `EXPL-PATH-KEY` | `( path-a path-u place -- key )` | The key of the entry at a path of a place, from the path's names alone |
| `EXPL-ON-OPEN` | `( xt widget -- )` | Set file-opened callback `( inode place explorer -- )`. Fires when a file is opened by Enter or a renderer's OPEN. |
| `EXPL-ON-SELECT` | `( xt widget -- )` | Set selection-changed callback `( inode place explorer -- )`, with inode 0 on a place's own row. Fires whenever the selection moves to another row. |

### Expand / Collapse

| Word | Stack | Description |
|------|-------|-------------|
| `EXPL-EXPAND-ALL` | `( widget -- )` | Expand entire tree (delegates to `TREE-EXPAND-ALL`) |
| `EXPL-COLLAPSE-ALL` | `( widget -- )` | Collapse every directory (delegates to `TREE-COLLAPSE-ALL`) |

### Tree Mutation

| Word | Stack | Description |
|------|-------|-------------|
| `EXPL-RENAME` | `( widget -- )` | Start inline rename — creates `INP-*` widget pre-filled with current name, sets rename-active flag |
| `EXPL-DELETE` | `( widget -- )` | Ask with `DLG-CONFIRM` before deleting the selected entry; confirming, while that entry is still selected in the same place, runs `PLACE-RM` on its path, then `PLACE-SYNC` |
| `EXPL-NEW-FILE` | `( widget -- )` | Create `"newfile"` in the selected directory, the selected file's directory or the selected place's folder via `PLACE-CREATE`, then `PLACE-SYNC` |
| `EXPL-NEW-DIR` | `( widget -- )` | Create `"newfolder"` there via `PLACE-MKDIR`, then `PLACE-SYNC` |

### Configuration

| Word | Stack | Description |
|------|-------|-------------|
| `EXPL-SHOW-HIDDEN!` | `( flag widget -- )` | Set show-hidden flag (TRUE = show, FALSE = hide) |
| `EXPL-SHOW-HIDDEN?` | `( widget -- flag )` | Query current show-hidden state |
| `EXPL-REFRESH` | `( widget -- )` | Re-read the places and their labels, mark tree dirty and trigger redraw |

### Accessors

| Word | Stack | Description |
|------|-------|-------------|
| `EXPL-SET` | `( widget -- set )` | Get the place set |
| `EXPL-TREE` | `( widget -- tree-widget )` | Get the embedded tree widget pointer |

## Internal Architecture

### Tree Context

The explorer stores itself in the embedded tree's context cell
(`TREE-CONTEXT!`).  The callbacks read the explorer's set through
`TREE-WALK-CONTEXT`, so the callbacks always serve the tree that is
walking, even when several explorers exist or a snapshot capture visits
an explorer that is not the active one.

### Mutations Go Through the Place

Rename, delete, new file and new directory use the `PLACE-` words on the
selected entry's place and its path there (`PLACE-PATH`).  Those words
keep the entry inside the place's folder, refuse a read-only place, and
hold the volume's current directory for the length of the call, so the
explorer never touches `V.CWD`.  The explorer also asks
`PLACE-WRITABLE?` first, so a read-only place opens no rename input and
no delete question.

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
   (non-empty, no `/`, no longer than `PLACE-NAME-LIMIT` allows),
   renames with `PLACE-RENAME`, which refuses a name the folder already
   holds, calls `PLACE-SYNC`, and clears rename state
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
| Embedded tree widget | 168 B |
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
`EXPL-ON-SELECT`, `EXPL-EXPAND-ALL`,
`EXPL-COLLAPSE-ALL`, `EXPL-SHOW-HIDDEN!`, `EXPL-RENAME`,
`EXPL-DELETE`, `EXPL-NEW-FILE`, `EXPL-NEW-DIR`, `EXPL-REFRESH`,
`EXPL-FREE`.

## Deferred (Not Yet Implemented)

| Word | Stack | Description |
|------|-------|-------------|
| `EXPL-REVEAL` | `( widget inode -- )` | Walk `IN.PARENT` chain, expand ancestors, scroll selected inode into view |
| `EXPL-CONTEXT-MENU` | `( widget -- )` | Show context action popup menu (Open / Rename / Delete / New File / New Folder / Refresh) |

## Design Notes

- **Zero-copy bridge.** Places and inodes are tree nodes — no
  translation layer.  Each of the five tree callbacks is a few lines
  of Forth.
- **Variable-based handlers.** All mutation words and the event
  handler store the widget pointer in VARIABLEs to avoid deep stack
  gymnastics.  This matches the style used by `tree.f`, `input.f`,
  and `dialog.f`.
- **Mutations through the place.** The `PLACE-` words confine each
  change to the place's folder and enforce its access, so the widget
  holds no rule of its own about where it may write.
- **`menu.f` not required.** The roadmap spec included context
  menus but they are deferred.  The current dependency list omits
  `menu.f`.
- **S" is compile-only** in KDOS Forth.  All `S"` usage in the
  explorer is inside colon definitions.
- **`[']` inside colon definitions** for compile-time xt
  resolution.  Interpreter-level code uses `'` (tick).

## Test Coverage (`test_explorer.py`)

| Group | Tests |
|-------|-------|
| create | type = WDG-T-EXPLORER (16) |
| tree-embedded | non-zero, type = WDG-T-TREE (11) |
| set-accessor | EXPL-SET matches the set given |
| selected-initial | EXPL-SELECTED = 0 and the first place |
| leaf-callback | a place and a directory → false; file → true |
| children-callback | a place's children are its folder's |
| next-callback | first child → has sibling; the only place → none |
| label-callback | a place reads its label, an entry its name |
| expand-root | 5 visible nodes (the place + 4 children) |
| expand-all | 6 visible (the place + docs + readme + src + hello.f + notes.txt) |
| nav-down | cursor moves to 1 |
| nav-up | down then up → cursor 0 |
| enter-toggle-dir | Enter on the place → 5 visible |
| enter-fires-on-open | Enter on file → callback fires with the inode and its place |
| on-select | Down arrow → callback fires once |
| new-file | "newfile" appears in the place's folder |
| new-dir | "newfolder" appears in the place's folder |
| new-file-in-subdir | "newfile" in src/ |
| refresh | marks widget dirty |
| show-hidden | initial false; set to true |
| rename-flag | a place's own row is not renamed; an entry sets flags2 bit 1 |
| rename-input | creates input widget (non-zero) |
| f5-refresh | F5 returns consumed (-1) |
| f2-rename | F2 activates rename mode |
| rename-esc-cancels | Escape clears rename flag |
| unrelated-key | char 'a' not consumed (0) |
| collapse-all | 1 visible node |
| free | completes without crash |
| top-rows | two places: two top rows in the set's order, by label |
| row-place | one folder under two places: an entry's place is its row's |
| unavailable | a missing volume's place reads `Card (volume missing)`, has no rows and takes no new file |
| follows-volume | attaching the volume moves the revision and clears the reason |
| read-only | no new entry, rename input or delete question in a read-only place |
| rename-commit | a rename commits through the entry's place |
| path-key | a path's key is the key the tree gives the entry there |

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
