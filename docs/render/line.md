# akashic-line — Line Box Layout for KDOS / Megapad-64

Breaks a linked list of pre-measured inline runs into line boxes that
fit within a given available width.  Handles line height calculation,
baseline alignment, and horizontal text alignment (left/center/right).

```forth
REQUIRE render/line.f
```

`PROVIDED akashic-line` — safe to include multiple times.
Automatically requires `box.f` (and transitively `dom.f`, `css.f`,
etc.).

---

## Table of Contents

- [Design Principles](#design-principles)
- [Inline Run Descriptor](#inline-run-descriptor)
- [Line Box Descriptor](#line-box-descriptor)
- [Constants](#constants)
- [Run Creation](#run-creation)
- [Run List Building](#run-list-building)
- [Line Breaking](#line-breaking)
- [Alignment](#alignment)
- [Line Accessors](#line-accessors)
- [Cleanup](#cleanup)
- [Quick Reference](#quick-reference)
- [Cookbook](#cookbook)

---

## Design Principles

| Principle | Detail |
|---|---|
| **Pre-measured runs** | Runs arrive with width, height, and ascender already computed.  No font dependency — text measurement happens upstream. |
| **Greedy breaking** | `LINE-BREAK` packs runs left-to-right until the next run would overflow.  Breaks only between runs (no intra-word splitting). |
| **Oversized tolerance** | A single run wider than the available width gets its own line rather than being dropped. |
| **Variable-based state** | Scratch variables prefixed `_LB-`, `_LA-`, `_LF-`.  Not re-entrant. |
| **Prefix convention** | Public: `LINE-`.  Internal: `_LN-`, `_LB-`, etc.  Field accessors: `_LR.xxx` (run), `_LL.xxx` (line). |

---

## Inline Run Descriptor

An inline run represents one atomic piece of inline content — either a
text fragment or an inline box.

8 cells = 64 bytes:

```
Offset  Size  Field
──────  ────  ──────────
+0      8     type       — 0 = text, 1 = box
+8      8     width      — run width in pixels
+16     8     height     — run height in pixels
+24     8     ascender   — distance from top to baseline
+32     8     x          — horizontal position (set by LINE-BREAK)
+40     8     next       — next run (in list, then within line)
+48     8     data       — text: string addr / box: box pointer
+56     8     data-len   — text: string length / box: unused
```

---

## Line Box Descriptor

A line box represents one horizontal row of inline content.

6 cells = 48 bytes:

```
Offset  Size  Field
──────  ────  ──────────
+0      8     y          — line Y position
+8      8     height     — line height (max-ascender + max-descender)
+16     8     baseline   — baseline offset from line top (= max ascender)
+24     8     first-run  — first run on this line
+32     8     width      — total width of all runs
+40     8     next       — next line box
```

---

## Constants

| Constant | Value | Description |
|---|---|---|
| `LINE-T-TEXT` | 0 | Text run type |
| `LINE-T-BOX` | 1 | Box run type |
| `LINE-A-LEFT` | 0 | Left text alignment |
| `LINE-A-CENTER` | 1 | Center text alignment |
| `LINE-A-RIGHT` | 2 | Right text alignment |

---

## Run Creation

### LINE-RUN-TEXT

```forth
LINE-RUN-TEXT  ( width height ascender -- run )
```

Create a text-type run with the given dimensions.  `data` and
`data-len` are left at 0 — set them manually if needed for painting.

### LINE-RUN-BOX

```forth
LINE-RUN-BOX  ( width height ascender -- run )
```

Create a box-type run.  Same as text but with `type = LINE-T-BOX`.
The `data` field can store a pointer to the inline box.

### LINE-RUN-FREE

```forth
LINE-RUN-FREE  ( run -- )
```

Free a single run descriptor.

---

## Run List Building

### LINE-RUN-APPEND

```forth
LINE-RUN-APPEND  ( run list-head -- new-head )
```

Append `run` to the end of a singly-linked run list.  If `list-head`
is 0, the run becomes the new head.  Returns the list head (which is
`run` if the list was empty, or the unchanged original head).

Example — build a list of three runs:

```forth
50 16 12 LINE-RUN-TEXT  ( run1 )
60 16 12 LINE-RUN-TEXT  ( run1 run2 )
OVER LINE-RUN-APPEND DROP   \ list: run1 → run2
30 16 12 LINE-RUN-TEXT  ( run1 run3 )
OVER LINE-RUN-APPEND DROP   \ list: run1 → run2 → run3
```

---

## Line Breaking

### LINE-BREAK

```forth
LINE-BREAK  ( runs avail-w -- lines )
```

Break a linked list of runs into line boxes.  Returns the first line
box (or 0 if `runs` is 0).

**Algorithm:**

1. Walk runs left to right, accumulating width.
2. If adding the next run would exceed `avail-w` **and** the current
   line already has content, finalize the current line and start a new
   one.
3. If the current line is empty and the run is oversized, put it on
   the line alone (no content is dropped).
4. Each run's `x` field is set to its position within the line.
5. Line height is computed as $\max(\text{ascender}) + \max(\text{descender})$ across all runs on the line.
6. Baseline is set to $\max(\text{ascender})$.

**Note:** After `LINE-BREAK`, runs are detached from the input list
and re-linked into per-line run lists.  The original input list is
consumed.

---

## Alignment

### LINE-ALIGN

```forth
LINE-ALIGN  ( line avail-w text-align -- )
```

Shift runs within a line for horizontal alignment:

| `text-align` | Effect |
|---|---|
| `LINE-A-LEFT` (0) | No change (runs already left-aligned). |
| `LINE-A-CENTER` (1) | Shift all runs right by $(\text{avail-w} - \text{line-w}) / 2$. |
| `LINE-A-RIGHT` (2) | Shift all runs right by $\text{avail-w} - \text{line-w}$. |

If the line width exceeds `avail-w`, no shift is applied.

---

## Line Accessors

### Read-only

| Word | Signature | Description |
|---|---|---|
| `LINE-Y` | `( line -- y )` | Line Y position |
| `LINE-HEIGHT` | `( line -- h )` | Line height |
| `LINE-BASELINE` | `( line -- y )` | Baseline offset from line top |
| `LINE-FIRST-RUN` | `( line -- run\|0 )` | First run on this line |
| `LINE-W` | `( line -- w )` | Total width of runs |
| `LINE-NEXT` | `( line -- line\|0 )` | Next line box |

### Run accessors

| Word | Signature | Description |
|---|---|---|
| `LINE-RUN-TYPE` | `( run -- type )` | 0 = text, 1 = box |
| `LINE-RUN-W` | `( run -- w )` | Run width |
| `LINE-RUN-H` | `( run -- h )` | Run height |
| `LINE-RUN-ASC` | `( run -- asc )` | Ascender (top → baseline) |
| `LINE-RUN-X` | `( run -- x )` | Horizontal position within line |
| `LINE-RUN-NEXT` | `( run -- run\|0 )` | Next run in line |

### Setters

| Word | Signature | Description |
|---|---|---|
| `LINE-Y!` | `( y line -- )` | Set line Y position |

---

## Cleanup

### LINE-FREE

```forth
LINE-FREE  ( lines -- )
```

Free all line boxes and their runs.  Walks the linked list of lines;
for each line, walks and frees all runs, then frees the line
descriptor.  Safe to call with 0.

---

## Quick Reference

```
LINE-RUN-TEXT     ( width height ascender -- run )
LINE-RUN-BOX      ( width height ascender -- run )
LINE-RUN-FREE     ( run -- )
LINE-RUN-APPEND   ( run list-head -- new-head )

LINE-BREAK        ( runs avail-w -- lines )
LINE-ALIGN        ( line avail-w text-align -- )
LINE-FREE         ( lines -- )

LINE-Y / LINE-HEIGHT / LINE-BASELINE / LINE-W / LINE-NEXT
LINE-FIRST-RUN / LINE-Y!
LINE-RUN-TYPE / LINE-RUN-W / LINE-RUN-H / LINE-RUN-ASC
LINE-RUN-X / LINE-RUN-NEXT
```

---

## Cookbook

### Break runs and center-align

```forth
\ Build runs
50 16 12 LINE-RUN-TEXT
60 16 12 LINE-RUN-TEXT  OVER LINE-RUN-APPEND DROP
30 16 12 LINE-RUN-TEXT  OVER LINE-RUN-APPEND DROP

\ Break into lines (200px wide)
200 LINE-BREAK

\ Center-align each line
DUP
BEGIN DUP 0<> WHILE
    DUP 200 LINE-A-CENTER LINE-ALIGN
    LINE-NEXT
REPEAT DROP

\ Use lines... then free
LINE-FREE
```

### Walk all runs in all lines

```forth
: DUMP-LINES  ( lines -- )
    BEGIN DUP 0<> WHILE
        CR ." Line y=" DUP LINE-Y .
        ."  h=" DUP LINE-HEIGHT .
        ."  w=" DUP LINE-W .
        DUP LINE-FIRST-RUN
        BEGIN DUP 0<> WHILE
            ."  [" DUP LINE-RUN-X .
            ." +" DUP LINE-RUN-W . ." ]"
            LINE-RUN-NEXT
        REPEAT DROP
        LINE-NEXT
    REPEAT DROP ;
```
