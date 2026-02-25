# akashic-surface — Pixel Buffer Abstraction for KDOS / Megapad-64

Flat RGBA8888 pixel buffer with clipping, blitting, and sub-surface
support.  Every rendering target — framebuffers, off-screen images,
temporary bitmaps — is a surface.

```forth
REQUIRE surface.f
```

`PROVIDED akashic-surface` — safe to include multiple times.
Automatically requires `color.f` (and transitively `fp16.f`,
`fp16-ext.f`, `exp.f`).

---

## Table of Contents

- [Design Principles](#design-principles)
- [Memory Layout](#memory-layout)
- [Creation & Destruction](#creation--destruction)
- [Accessors](#accessors)
- [Pixel Access](#pixel-access)
- [Fills & Spans](#fills--spans)
- [Clipping](#clipping)
- [Blitting](#blitting)
- [Sub-Surfaces](#sub-surfaces)
- [Internals](#internals)
- [Quick Reference](#quick-reference)
- [Cookbook](#cookbook)

---

## Design Principles

| Principle | Detail |
|---|---|
| **RGBA8888** | Every pixel is a packed 32-bit value: `R[31:24] G[23:16] B[15:8] A[7:0]`. Compatible with `COLOR-PACK-RGBA` / `COLOR-UNPACK-RGBA`. |
| **Heap-allocated** | `SURF-CREATE` allocates both the descriptor (80 bytes) and pixel buffer via `ALLOCATE`. `SURF-CREATE-FROM` wraps an existing buffer without allocation. |
| **Clip rectangle** | All writing operations honor a per-surface clip rectangle. Reading (`SURF-PIXEL@`) is bounds-checked against the full surface. |
| **Row-major stride** | Pixel data is row-major. Stride (bytes per row) defaults to $w \times 4$ but may differ for sub-surfaces or hardware framebuffers. |
| **Variable-based state** | Internal scratch uses `VARIABLE`s — not re-entrant. |
| **Prefix convention** | Public: `SURF-`. Internal: `_SURF-`. Field accessors: `S.xxx`. |

---

## Memory Layout

A surface descriptor occupies 10 cells = 80 bytes:

```
Offset  Size   Field
──────  ─────  ─────────────
+0      8      buf       — pointer to RGBA8888 pixel data
+8      8      width     — surface width in pixels
+16     8      height    — surface height in pixels
+24     8      stride    — bytes per row (≥ width × 4)
+32     8      clip-x    — clip rectangle origin X
+40     8      clip-y    — clip rectangle origin Y
+48     8      clip-w    — clip rectangle width
+56     8      clip-h    — clip rectangle height
+64     8      flags     — bit 0: 1 = owns buffer (freed on destroy)
+72     8      (reserved)
```

Field accessor words (`S.BUF`, `S.W`, ...) return the address of
each field for use with `@` and `!`.

---

## Creation & Destruction

### SURF-CREATE

```forth
SURF-CREATE  ( w h -- surf )
```

Allocate a new surface with $w \times h$ pixels.  The pixel buffer
is zeroed (transparent black `0x00000000`).  Clip rectangle is set
to the full surface.  The surface owns its buffer.

```forth
320 240 SURF-CREATE CONSTANT my-fb
```

### SURF-CREATE-FROM

```forth
SURF-CREATE-FROM  ( buf w h stride -- surf )
```

Wrap an existing pixel buffer in a surface descriptor.  The surface
does **not** own the buffer — `SURF-DESTROY` will not free it.
Use for hardware framebuffers or aliasing into shared memory.

```forth
\ Wrap a framebuffer at a known address
0x40000000 640 480 2560 SURF-CREATE-FROM  CONSTANT hw-fb
```

### SURF-DESTROY

```forth
SURF-DESTROY  ( surf -- )
```

Free the surface descriptor.  If the surface owns its buffer
(created via `SURF-CREATE`), the pixel buffer is also freed.

```forth
my-fb SURF-DESTROY
```

---

## Accessors

```forth
SURF-BUF     ( surf -- addr )     \ pointer to pixel data
SURF-W       ( surf -- w )        \ width in pixels
SURF-H       ( surf -- h )        \ height in pixels
SURF-STRIDE  ( surf -- stride )   \ bytes per row
```

---

## Pixel Access

### SURF-PIXEL@

```forth
SURF-PIXEL@  ( surf x y -- rgba )
```

Read one pixel.  Returns `0` (transparent black) if $(x, y)$ is
outside the surface bounds.  Bounds-checked against the full
surface dimensions (ignores clip rectangle).

### SURF-PIXEL!

```forth
SURF-PIXEL!  ( surf x y rgba -- )
```

Write one pixel.  Silently discarded if $(x, y)$ is outside the
clip rectangle.

```forth
my-fb 10 20 0xFF0000FF SURF-PIXEL!   \ red pixel at (10,20)
my-fb 10 20 SURF-PIXEL@ .            \ → 4278190335
```

---

## Fills & Spans

### SURF-HLINE

```forth
SURF-HLINE  ( surf x y len rgba -- )
```

Draw a horizontal span of `len` pixels starting at $(x, y)$.
Clipped to the clip rectangle on both ends.  This is the primary
fast-path for filled-shape rendering.

### SURF-FILL-RECT

```forth
SURF-FILL-RECT  ( surf x y w h rgba -- )
```

Fill a $w \times h$ rectangle at $(x, y)$ with a solid color.
Delegates to `SURF-HLINE` per row.

### SURF-CLEAR-REGION

```forth
SURF-CLEAR-REGION  ( surf x y w h rgba -- )
```

Alias for `SURF-FILL-RECT`.

### SURF-CLEAR

```forth
SURF-CLEAR  ( surf rgba -- )
```

Fill the **entire** pixel buffer with one color, ignoring the clip
rectangle.

```forth
my-fb 0x000000FF SURF-CLEAR   \ solid black, fully opaque
```

---

## Clipping

### SURF-CLIP!

```forth
SURF-CLIP!  ( surf x y w h -- )
```

Set the clip rectangle.  Values are clamped to the surface bounds.
All pixel-writing operations (`SURF-PIXEL!`, `SURF-HLINE`,
`SURF-FILL-RECT`, `SURF-BLIT`) respect this clip.

```forth
my-fb 10 10 100 80 SURF-CLIP!   \ only draw within (10,10)–(110,90)
```

### SURF-CLIP-RESET

```forth
SURF-CLIP-RESET  ( surf -- )
```

Reset the clip rectangle to the full surface dimensions.

---

## Blitting

### SURF-BLIT

```forth
SURF-BLIT  ( src dst dx dy -- )
```

Copy all pixels from `src` onto `dst` at offset $(dx, dy)$.
Opaque copy — no alpha blending.  Clipped to `dst`'s clip
rectangle.  Uses `CMOVE` for row-by-row copy.

### SURF-BLIT-ALPHA

```forth
SURF-BLIT-ALPHA  ( src dst dx dy -- )
```

Alpha-blended blit.  Each pixel is composited using premultiplied
alpha via `COLOR-BLEND` from `color.f`.  Fully transparent source
pixels are skipped for performance.

```forth
\ Composite a sprite onto the framebuffer
sprite-surf  my-fb  50 30  SURF-BLIT-ALPHA
```

---

## Sub-Surfaces

### SURF-SUB

```forth
SURF-SUB  ( surf x y w h -- sub )
```

Create a sub-surface that aliases a rectangular region of the
parent surface.  The sub-surface shares the parent's pixel buffer
(same stride) and does **not** own it.

Writing through the sub-surface modifies the parent's pixels.
Coordinates in the sub-surface are relative to its own origin.

```forth
my-fb 100 50 200 150 SURF-SUB CONSTANT panel
panel 0 0 200 150 0xCCCCCCFF SURF-FILL-RECT   \ fills parent too
panel SURF-DESTROY
```

---

## Internals

| Word | Purpose |
|---|---|
| `_SURF-ADDR` `( surf x y -- addr )` | Compute byte address of pixel — no bounds check. |
| `_SURF-CLIP?` `( surf x y -- flag )` | Test if $(x, y)$ falls within the clip rectangle. |
| `_SURF-TMP`, `_SURF-X`, `_SURF-Y`, ... | Scratch `VARIABLE`s used by all operations. |
| `_SURF-F-OWNS-BUF` | Flag constant (1): surface owns its pixel buffer. |
| `S.BUF`, `S.W`, `S.H`, `S.STRIDE`, `S.CLIP-X`, `S.CLIP-Y`, `S.CLIP-W`, `S.CLIP-H`, `S.FLAGS` | Field accessor words returning field addresses. |

---

## Quick Reference

| Word | Stack | Description |
|---|---|---|
| `SURF-CREATE` | `( w h -- surf )` | Allocate surface + pixel buffer |
| `SURF-CREATE-FROM` | `( buf w h stride -- surf )` | Wrap existing buffer |
| `SURF-DESTROY` | `( surf -- )` | Free surface (and buffer if owned) |
| `SURF-BUF` | `( surf -- addr )` | Pixel data pointer |
| `SURF-W` | `( surf -- w )` | Width |
| `SURF-H` | `( surf -- h )` | Height |
| `SURF-STRIDE` | `( surf -- stride )` | Bytes per row |
| `SURF-PIXEL@` | `( surf x y -- rgba )` | Read pixel |
| `SURF-PIXEL!` | `( surf x y rgba -- )` | Write pixel (clipped) |
| `SURF-HLINE` | `( surf x y len rgba -- )` | Horizontal span (clipped) |
| `SURF-FILL-RECT` | `( surf x y w h rgba -- )` | Filled rectangle |
| `SURF-CLEAR-REGION` | `( surf x y w h rgba -- )` | Alias for FILL-RECT |
| `SURF-CLEAR` | `( surf rgba -- )` | Fill entire buffer |
| `SURF-CLIP!` | `( surf x y w h -- )` | Set clip rectangle |
| `SURF-CLIP-RESET` | `( surf -- )` | Reset clip to full surface |
| `SURF-BLIT` | `( src dst dx dy -- )` | Opaque blit |
| `SURF-BLIT-ALPHA` | `( src dst dx dy -- )` | Alpha-blended blit |
| `SURF-SUB` | `( surf x y w h -- sub )` | Create sub-surface |

### Constants

| Name | Value | Meaning |
|---|---|---|
| `SURF-DESC-SIZE` | 80 | Bytes per surface descriptor |
| `_SURF-F-OWNS-BUF` | 1 | Surface owns its pixel buffer |

---

## Cookbook

### Off-screen render target

```forth
256 256 SURF-CREATE CONSTANT offscreen
\ ... draw into offscreen ...
offscreen my-fb 0 0 SURF-BLIT       \ stamp onto framebuffer
offscreen SURF-DESTROY
```

### Scissored drawing

```forth
my-fb 20 20 100 60 SURF-CLIP!
my-fb 0 0 320 240 0xFF0000FF SURF-FILL-RECT   \ only fills clip region
my-fb SURF-CLIP-RESET
```

### Sprite compositing

```forth
sprite my-fb player-x @ player-y @ SURF-BLIT-ALPHA
```
