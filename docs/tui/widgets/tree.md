# akashic/tui/widgets/tree.f — Tree View Widget

**Layer:** 7  
**Lines:** 849  
**Prefix:** `TREE-` (public), `_TREE-` (internal)  
**Provider:** `akashic-tui-tree`  
**Dependencies:** `widget.f`, `draw.f`, `region.f`, `keys.f`,
`semantic-collections.f`, `memory-span.f`

## Overview

A collapsible tree display for hierarchical data.  The widget does
**not** own the tree data.  It discovers the structure through five
caller-supplied callbacks:

| Callback | Signature | Description |
|----------|-----------|-------------|
| `children-xt` | `( node -- first-child \| 0 )` | First child of a node |
| `next-xt` | `( node -- sibling \| 0 )` | Next sibling |
| `label-xt` | `( node -- addr len )` | Display label |
| `leaf?-xt` | `( node -- flag )` | Is this a leaf? |
| `key-xt` | `( parent-key node -- key )` | The node's key |

Nodes are opaque cell-sized tokens (pointers, handles, indices); `0`
means no node.  A key names a node from draw to draw.  It is nonzero,
unique among the nodes the tree shows, and the same for the same node
whenever its parent's key is.  Top-level nodes get parent key 0.

Callbacks must not call back into the widget.  While one runs,
`TREE-WALK-CONTEXT` returns the context cell of the tree that called it,
so one set of callbacks can serve several trees.

### Expansion and Selection

Expansion is the set of expanded keys, kept as a sorted array that grows
as needed.  Because it is keyed, a branch stays open however the rows
above it change, and there is no node limit.  The selection is the
selected node's key; when that node is no longer shown, the selection
falls back to the first row.

### Drawing

Each shown node takes one row.  A branch's mark (▶ collapsed, ▼
expanded) is drawn at column depth × 2 of the tree's region, and the
label two cells to its right.  The selected row is highlighted.

## Input (via `WDG-HANDLE`)

| Input | Action |
|-------|--------|
| Up / Down | Move the selection one row |
| Page Up / Page Down | Move the selection by the region height |
| Home / End | Select the first / last row |
| Right | Expand the selected branch |
| Left | Collapse the selected branch, or select its parent |
| Enter | Open the selection: the open callback runs if there is one; otherwise a branch expands or collapses |
| Primary press | Select the row under the pointer |
| Primary press on a branch's mark | Also expand or collapse that branch |
| Wheel | Scroll three rows without moving the selection |
| Item SELECT / OPEN / EXPAND / COLLAPSE | Do the same to the node with that key |

Pointer events carry absolute screen cells (see `keys.f`).  Item events
arrive as `KEY-MOUSE-ITEM` with the key in `KEY-MOUSE-ITEM-KEY` and the
action in `KEY-MOUSE-ITEM-ACTION`.  An item event whose key names no shown
node is consumed and changes nothing.

## Descriptor Layout (160 bytes)

| Offset | Field | Description |
|--------|-------|-------------|
| +0..+39 | header | Standard widget header, type=`WDG-T-TREE` (11) |
| +40 | root | Root node token |
| +48 | children-xt | First child |
| +56 | next-xt | Next sibling |
| +64 | label-xt | Node label |
| +72 | leaf-xt | Is a leaf? |
| +80 | key-xt | Node key |
| +88 | cursor-key | Selected node's key, or 0 for the first row |
| +96 | scroll-top | First shown row |
| +104 | on-select-xt | `( widget -- )` when the selection moves, or 0 |
| +112 | on-open-xt | `( widget -- )` when the selection is opened, or 0 |
| +120 | expanded-a | Sorted expanded keys, or 0 |
| +128 | expanded-n | Number of expanded keys |
| +136 | expanded-cap | Capacity of expanded-a, in keys |
| +144 | instance | Nonzero allocation-lifetime instance token |
| +152 | context | The caller's context cell |

## API Reference

### Constructor / Destructor

| Word | Stack | Description |
|------|-------|-------------|
| `TREE-NEW` | `( rgn root children-xt next-xt label-xt leaf?-xt key-xt -- widget )` | Create a tree view with the root collapsed and selected |
| `TREE-FREE` | `( widget -- )` | Free the expanded-key set and the descriptor |

### Expand / Collapse

All of these act on a node that is shown and do nothing otherwise.

| Word | Stack | Description |
|------|-------|-------------|
| `TREE-EXPAND` | `( widget node -- )` | Expand a branch (no-op on leaves) |
| `TREE-COLLAPSE` | `( widget node -- )` | Collapse a branch |
| `TREE-TOGGLE` | `( widget node -- )` | Toggle a branch |
| `TREE-EXPANDED?` | `( widget node -- flag )` | Is the node expanded? |
| `TREE-EXPAND-ALL` | `( widget -- )` | Expand every branch |
| `TREE-COLLAPSE-ALL` | `( widget -- )` | Collapse every branch |

### Selection and Callbacks

| Word | Stack | Description |
|------|-------|-------------|
| `TREE-SELECTED` | `( widget -- node\|0 )` | The selected node |
| `TREE-SELECTED-KEY` | `( widget -- key\|0 )` | The selected node's key |
| `TREE-SELECT` | `( widget node -- )` | Select a shown node and show it |
| `TREE-ON-SELECT` | `( xt widget -- )` | Callback `( widget -- )` when the selection moves to another node |
| `TREE-ON-OPEN` | `( xt widget -- )` | Callback `( widget -- )` when the selection is opened |
| `TREE-CONTEXT!` | `( context widget -- )` | Store the caller's context cell |
| `TREE-CONTEXT@` | `( widget -- context )` | Read the caller's context cell |
| `TREE-WALK-CONTEXT` | `( -- context )` | Inside a callback: the calling tree's context cell |

### Scrolling and Refresh

| Word | Stack | Description |
|------|-------|-------------|
| `TREE-SCROLL-INFO` | `( widget -- content-h offset visible-h )` | Scroll parameters for a scroll container |
| `TREE-SCROLL-SET` | `( offset widget -- )` | Set the first shown row (clamped); the selection does not move |
| `TREE-REFRESH` | `( widget -- )` | Mark dirty after the backing data changed |

### Item View

| Word | Stack | Description |
|------|-------|-------------|
| `TREE-ITEM-VIEW-CAPTURE` | `( root-key dst cap builder widget -- bytes status )` | Build the tree's item view with the caller's builder; `dst cap` of `0 0` measures |
| `TREE-ITEM-VIEW-MEASURE` | `( root-key builder widget -- bytes status )` | Exact bytes the capture needs |
| `TREE-INSTANCE@` | `( widget -- token )` | The instance token, or 0 for anything that is not a live tree |
| `TREE-STORAGE-DISJOINT?` | `( address bytes -- flag )` | A caller span misses the module's own storage |
| `TREE-ITEM-VIEW-STORAGE-DISJOINT?` | `( address bytes widget -- flag )` | A caller span also misses the tree's descriptor, region and expanded-key set |

The capture is a `TREE` item view with one unlabelled text column.  It
carries the shown rows and the selected row wherever it is.  Each row
carries its key, its parent's key, its row, its depth, its label, and the
`SELECTED`, `EXPANDABLE` and `EXPANDED` states that apply.

## UIDL-TUI Integration

A `<tree>` element in a UIDL document gets a `TREE-NEW` widget, created
when the document loads and freed when it detaches.  Five adapter
callbacks walk the UIDL elements:

| Callback | Implementation |
|----------|----------------|
| `children-xt` | `_UTUI-TREE-CHILD` → `UIDL-FIRST-CHILD` |
| `next-xt` | `_UTUI-TREE-NEXT` → `UIDL-NEXT-SIB` |
| `label-xt` | `_UTUI-TREE-LABEL` → `label=` attribute, else `text=`, else `"?"` |
| `leaf?-xt` | `_UTUI-TREE-LEAF?` → `UIDL-FIRST-CHILD 0=` |
| `key-xt` | `_UTUI-TREE-KEY` → the element's index plus one |

See [uidl-tui.md](../uidl-tui.md) for the full backend design.

## Design Notes

- **Callback-driven.** The tree never owns node data.  After changing
  the backing structure, call `TREE-REFRESH`.
- **Keys, not positions.** Expansion and selection follow keys, not
  depth-first row numbers, so opening one branch never moves another
  branch's state onto the wrong node, and a renderer's event names the
  node it drew even when rows moved since.
- **Walks instead of storage.** Rows are found by walking the shown part
  of the tree, so the widget keeps no per-row state.
- When `GUARDED` is defined, the public words are wrapped with
  `WITH-GUARD`, except `TREE-WALK-CONTEXT` (it runs inside callbacks,
  which already hold the guard), the pure `TREE-STORAGE-DISJOINT?`, and
  `TREE-SCROLL-INFO` and `TREE-SCROLL-SET`.

## Tests

`local_testing/test_tui.py` (tree section) covers creation, expansion,
navigation, selection and callbacks.  `test_widget_pointer.py` covers
pointer input, keyed expansion, item events and parent navigation.
`test_semantic_item_views.py` covers the item-view capture.
