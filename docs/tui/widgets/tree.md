# akashic/tui/widgets/tree.f — Tree View Widget

**Layer:** 7  
**Lines:** 485  
**Prefix:** `TREE-` (public), `_TREE-` (internal)  
**Provider:** `akashic-tui-tree`  
**Dependencies:** `widget.f`, `draw.f`, `region.f`, `keys.f`

## Overview

A collapsible tree display for hierarchical data.  The widget does
**not** own the tree data — it discovers structure through four
user-supplied callbacks:

| Callback | Signature | Description |
|----------|-----------|-------------|
| `children-xt` | `( node -- first-child \| 0 )` | Get first child of node |
| `next-xt` | `( node -- sibling \| 0 )` | Get next sibling |
| `label-xt` | `( node -- addr len )` | Get display label |
| `leaf?-xt` | `( node -- flag )` | Is this a leaf? |

Nodes are opaque cell-sized tokens (pointers, handles, indices).
`0` means "no node" / NIL.

### Navigation

| Key | Action |
|-----|--------|
| Up | Move cursor up one row |
| Down | Move cursor down one row |
| Right | Expand node at cursor |
| Left | Collapse node at cursor |
| Enter | Toggle expand/collapse; fires selection callback |

### Expand / Collapse State

Stored in a flat bitmap (`exp-buf`) indexed by DFS-order position.
The tree is re-walked on each draw or query.  For moderate trees
(< 512 visible nodes) this is fast enough.

### Tree Guides

Box-drawing characters render the tree structure:
`├──`, `│  `, `└──` with indentation (3 chars per depth level).

## Descriptor Layout (112 bytes)

| Offset | Field | Type | Description |
|--------|-------|------|-------------|
| +0..+32 | header | widget header | Standard 5-cell header, type=WDG-T-TREE (11) |
| +40 | root | node | Root node token |
| +48 | children-xt | xt | Callback: first child |
| +56 | next-xt | xt | Callback: next sibling |
| +64 | label-xt | xt | Callback: node label |
| +72 | leaf-xt | xt | Callback: is-leaf? |
| +80 | cursor | u | Selected visible-row index (0-based) |
| +88 | scroll-top | u | First visible row (scroll offset) |
| +96 | on-sel-xt | xt or 0 | Selection callback `( widget -- )` |
| +104 | exp-buf | address | Expand bitmap buffer |

## API Reference

### Constructor / Destructor

| Word | Stack | Description |
|------|-------|-------------|
| `TREE-NEW` | `( rgn root children-xt next-xt label-xt leaf?-xt -- widget )` | Create tree view |
| `TREE-FREE` | `( widget -- )` | Free expand buffer and descriptor |

### Expand / Collapse

| Word | Stack | Description |
|------|-------|-------------|
| `TREE-EXPAND` | `( widget node -- )` | Expand node (no-op on leaves) |
| `TREE-COLLAPSE` | `( widget node -- )` | Collapse node |
| `TREE-TOGGLE` | `( widget node -- )` | Toggle expand/collapse |
| `TREE-EXPAND-ALL` | `( widget -- )` | Expand every node (fills bitmap with 0xFF) |

### Selection

| Word | Stack | Description |
|------|-------|-------------|
| `TREE-SELECTED` | `( widget -- node )` | Get node at current cursor position |
| `TREE-ON-SELECT` | `( widget xt -- )` | Set selection callback `( widget -- )` |

### Utility

| Word | Stack | Description |
|------|-------|-------------|
| `TREE-REFRESH` | `( widget -- )` | Mark dirty for redraw |

## Internal Architecture

### Tree Walk (`_TREE-DO-WALK`)

A DFS walk that visits visible nodes (expanded subtrees only).
For each visible node, calls a user-supplied action-xt with
`( node depth idx )`.  The walk uses variables `_TW-W`, `_TW-ACT`,
`_TW-IDX` to avoid deep stack management across recursive calls.

### Node Lookup (`_TREE-NODE-AT`)

Walks the tree counting visible rows until the target index is
reached; returns the corresponding `( node depth )` pair.

### Cursor Clamping (`_TREE-CLAMP`)

After any structural change (expand/collapse), clamps cursor to
`[0, visible-count - 1]`.

### Scrolling (`_TREE-SCROLL`)

Uses variables `_TSC-CUR`, `_TSC-SCR`, `_TSC-VH` to compute the
new scroll-top, keeping the cursor within the visible viewport.

### UP Handler

Uses `DUP 0> IF 1- THEN` instead of `1- 0 MAX` because `MAX` in
KDOS is an unsigned comparison (defined in `bios.asm`), so
`0 1- 0 MAX` yields UINT64_MAX rather than 0.

## UIDL-TUI Integration

When a `<tree>` element appears in a UIDL document, the UIDL-TUI
backend (`uidl-tui.f`) fully materializes a `TREE-NEW` widget and
stores it in the sidecar's `wptr` cell (+48).  Four adapter callbacks
bridge UIDL tree traversal to the widget's callback protocol:

| Callback | Implementation |
|----------|----------------|
| `children-xt` | `_UTUI-TREE-CHILD` → `UIDL-FIRST-CHILD` |
| `next-xt` | `_UTUI-TREE-NEXT` → `UIDL-NEXT-SIB` |
| `label-xt` | `_UTUI-TREE-LABEL` → `label=` attr, fallback `text=`, fallback `"?"` |
| `leaf?-xt` | `_UTUI-TREE-LEAF?` → `UIDL-FIRST-CHILD 0=` |

The widget's region is the shared proxy region (`_UTUI-PROXY-RGN`),
synced from sidecar geometry before each draw/handle call.  The render
adapter calls `RGN-USE` before `_TREE-DRAW` and `RGN-ROOT` after, so
the widget draws in region-relative coordinates.

Lifecycle: `TREE-NEW` at `_UTUI-MATERIALIZE` (during `UTUI-LOAD`),
`TREE-FREE` at `_UTUI-DEMATERIALIZE` (during `UTUI-DETACH`).

See [uidl-tui.md](../uidl-tui.md) for the full backend design.

## Design Notes

- **Callback-driven.** The tree widget never owns node data.
  Adding/removing nodes in the backing structure is the caller's
  responsibility; call `TREE-REFRESH` afterward.
- **Flat bitmap.** The expand state bitmap supports up to
  `_TREE-MAX-NODES` (512) nodes by DFS index.  This is compact
  (64 bytes) and avoids per-node allocation.
- **Variable-based handlers.** `_TREE-HANDLE` and `_TREE-DO-WALK`
  store the widget pointer in VARIABLEs to avoid deep stack
  gymnastics.  KDOS Forth's `J` word is unreliable for nested
  DO loops.
- When `GUARDED` is defined, every public word is wrapped with
  `WITH-GUARD` for concurrency safety.

## Test Coverage (18 tests)

| Group | Tests |
|-------|-------|
| create | type=11, cursor=0 |
| draw | no crash |
| expand | root → 3 visible; root + ChildB → 4 visible |
| expand-all | 4 visible |
| expand-leaf | leaf expand is no-op |
| free | no crash |
| handle-unrelated | printable key returns 0 |
| nav-clamp | clamp at single row |
| nav-collapse | left key collapses |
| nav-down | one step; two steps |
| nav-enter | enter toggles |
| nav-expand | right key expands |
| nav-up | up from 0 stays at 0; down then up returns to 0 |
| on-select | callback fires |
| selected | root at 0; ChildA at 1 |
| toggle | expand then collapse |
| vis-count | initial = 1 |
