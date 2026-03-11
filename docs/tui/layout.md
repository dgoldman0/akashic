# akashic-tui-layout — Container Layout Engine

Automatic positioning of child regions within a parent.
Three layout modes: vertical stack, horizontal stack, and fixed
positioning.  Terminal-UI equivalent of CSS flexbox — simpler,
but sufficient for dashboard-style layouts.

```forth
REQUIRE tui/layout.f
```

`PROVIDED akashic-tui-layout` — safe to include multiple times.

**Dependencies:** `region.f`

---

## Table of Contents

- [Design Principles](#design-principles)
- [Constants](#constants)
- [Layout Descriptor](#layout-descriptor)
- [Child Descriptor](#child-descriptor)
- [Constructor / Destructor](#constructor--destructor)
- [Adding Children](#adding-children)
- [Computing Layout](#computing-layout)
- [Accessors](#accessors)
- [Quick Reference](#quick-reference)

---

## Design Principles

| Principle | Implementation |
|-----------|---------------|
| **Three modes** | `LAY-VERTICAL` (top→bottom), `LAY-HORIZONTAL` (left→right), `LAY-FIXED` (caller-managed). |
| **Two-pass compute** | Measure pass sums fixed hints; distribute pass splits remaining space among auto-expand children. |
| **Expand flag** | `LAY-F-EXPAND` distributes remaining space equally among `hint=0` children. Without it, remaining space is padding at the end. |
| **Min-size guarantee** | No child shrinks below its `min-size`, even if space is tight. |
| **Region-based** | Each child gets its own `RGN-SUB` region, updated in-place by `LAY-COMPUTE`. |
| **Heap-allocated** | Descriptors are `ALLOCATE`d; freed recursively by `LAY-FREE`. |
| **Prefix convention** | Public: `LAY-`. Internal: `_LAY-`. |

---

## Constants

| Constant | Value | Description |
|----------|-------|-------------|
| `LAY-VERTICAL`   | 0 | Stack children top-to-bottom |
| `LAY-HORIZONTAL`  | 1 | Stack children left-to-right |
| `LAY-FIXED`       | 2 | Children at explicit positions |
| `LAY-F-EXPAND`    | 1 | Flag: distribute remaining space equally |

---

## Layout Descriptor

Six cells (48 bytes), stored in allocated memory:

| Offset | Field    | Description |
|--------|----------|-------------|
| +0     | region   | Region this layout manages |
| +8     | mode     | `LAY-VERTICAL`, `LAY-HORIZONTAL`, or `LAY-FIXED` |
| +16    | gap      | Gap between children (rows or columns) |
| +24    | count    | Number of children |
| +32    | children | Address of child descriptor array |
| +40    | flags    | `LAY-F-EXPAND`, etc. |

---

## Child Descriptor

Three cells (24 bytes) per child:

| Offset | Field     | Description |
|--------|-----------|-------------|
| +0     | region    | Child region (auto-created, updated by `LAY-COMPUTE`) |
| +8     | size-hint | Requested size: rows (vertical) or columns (horizontal). 0 = auto-expand. |
| +16    | min-size  | Minimum size (never shrink below this) |

---

## Constructor / Destructor

### LAY-NEW

```forth
LAY-NEW  ( rgn mode gap -- lay )
```

Create a layout over the given region.

```forth
my-region LAY-VERTICAL 1 LAY-NEW   \ vertical, 1-row gap
```

### LAY-FREE

```forth
LAY-FREE  ( lay -- )
```

Free the layout, all child regions, and the children array.

---

## Adding Children

### LAY-ADD

```forth
LAY-ADD  ( lay size-hint min-size -- child-rgn )
```

Add a child with the given size hint and minimum size.
Returns the child's region (initially 0×0; updated by `LAY-COMPUTE`).

- `size-hint > 0`: child gets exactly this many rows/columns.
- `size-hint = 0`: child auto-expands (shares remaining space with other `hint=0` children when `LAY-F-EXPAND` is set).
- `min-size`: floor — child never shrinks below this.

```forth
my-layout 10 2 LAY-ADD   \ fixed 10 rows, min 2
my-layout 0 0 LAY-ADD    \ expand to fill remaining
```

### LAY-FLAGS!

```forth
LAY-FLAGS!  ( flags lay -- )
```

Set layout flags (e.g., `LAY-F-EXPAND`).

```forth
LAY-F-EXPAND my-layout LAY-FLAGS!
```

---

## Computing Layout

### LAY-COMPUTE

```forth
LAY-COMPUTE  ( lay -- )
```

Recompute all child positions and sizes.  Call after adding
children or when the parent region's size changes.

**Algorithm** (two passes):

1. **Measure:** Sum all `size-hint` values and gaps.  Compute
   remaining = parent-size − total-hints − total-gaps.
2. **Distribute:** If `LAY-F-EXPAND`, divide remaining space
   equally among children with `hint=0`.  Otherwise remaining
   space is unused padding.

Children are placed sequentially along the layout direction:
vertical layouts vary row, horizontal layouts vary column.
The cross-axis dimension fills the parent (e.g., vertical
children span the full parent width).

---

## Accessors

### LAY-COUNT

```forth
LAY-COUNT  ( lay -- n )
```

Number of children.

### LAY-CHILD

```forth
LAY-CHILD  ( lay n -- child-rgn )
```

Get the nth child's region (0-based).

---

## Quick Reference

| Word | Stack | Description |
|------|-------|-------------|
| `LAY-NEW` | `( rgn mode gap -- lay )` | Create layout over region |
| `LAY-FREE` | `( lay -- )` | Free layout + children |
| `LAY-ADD` | `( lay hint min -- rgn )` | Add child, returns region |
| `LAY-COMPUTE` | `( lay -- )` | Recompute positions |
| `LAY-CHILD` | `( lay n -- rgn )` | Get nth child region |
| `LAY-COUNT` | `( lay -- n )` | Number of children |
| `LAY-FLAGS!` | `( flags lay -- )` | Set layout flags |

### Example: Two-Pane Vertical Split

```forth
\ Create screen and parent region
80 24 SCR-NEW DUP SCR-USE SCR-CLEAR
0 0 24 80 RGN-NEW

\ Create vertical layout: header (3 rows) + body (expand)
DUP LAY-VERTICAL 0 LAY-NEW
LAY-F-EXPAND OVER LAY-FLAGS!

DUP 3  1 LAY-ADD   \ header: 3 rows, min 1
SWAP
DUP 0  5 LAY-ADD   \ body: expand, min 5
SWAP

DUP LAY-COMPUTE

\ Draw into header
DUP 0 LAY-CHILD RGN-USE
S" Dashboard" 0 0 DRW-TEXT

\ Draw into body
DUP 1 LAY-CHILD RGN-USE
S" Content here" 0 0 DRW-TEXT
```
