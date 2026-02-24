# akashic-cache — Glyph Bitmap Cache for KDOS / Megapad-64

Direct-mapped hash cache for rasterized glyph bitmaps.  Avoids
re-rendering frequently used characters by storing their pixel
data keyed on `(glyph_id, pixel_size)`.

```forth
REQUIRE cache.f
```

`PROVIDED akashic-cache` — safe to include multiple times.

---

## Table of Contents

- [Design Principles](#design-principles)
- [Dependencies](#dependencies)
- [Configuration](#configuration)
- [Public API](#public-api)
- [Cache Internals](#cache-internals)
- [Quick Reference](#quick-reference)
- [Known Limitations](#known-limitations)

---

## Design Principles

| Principle | Detail |
|---|---|
| **Direct-mapped** | Each (glyph_id, size) pair hashes to exactly one slot.  Collisions evict the previous entry. |
| **Pool allocator** | Bitmaps are allocated sequentially from a contiguous pool.  No per-bitmap free. |
| **Generational eviction** | When the pool is exhausted, the entire cache is flushed and the pool resets. |
| **Square bitmaps** | Width = height = pixel_size.  Sufficient for most glyphs. |

---

## Dependencies

```
cache.f ──→ raster.f ──→ ttf.f
                     ──→ bezier.f ──→ fp16-ext.f ──→ fp16.f
                     ──→ fixed.f
```

---

## Configuration

| Constant | Value | Description |
|---|---|---|
| `GC-SLOTS` | 256 | Number of cache slots (power of 2) |
| `_GC-POOL-SIZE` | 262144 (256 KiB) | Bitmap pool size in bytes |

At 16×16 pixels (1 byte/pixel), each bitmap is 256 bytes.
The pool holds ~1024 such bitmaps before flushing.

At 32×32 pixels, each bitmap is 1024 bytes, yielding ~256 bitmaps.

---

## Public API

### GC-GET

```forth
GC-GET  ( glyph-id size -- bmp-addr w h | 0 0 0 )
```

Main entry point.  Checks the cache first; on miss, rasterizes the
glyph via `RAST-GLYPH` and stores the result.  Returns the bitmap
address, width, and height, or `0 0 0` on failure.

Prerequisite: TTF tables must be parsed.

### GC-LOOKUP

```forth
GC-LOOKUP  ( glyph-id size -- bmp-addr w h | 0 0 0 )
```

Check cache only — no rasterization on miss.

### GC-STORE

```forth
GC-STORE  ( glyph-id size -- bmp-addr w h | 0 0 0 )
```

Rasterize a glyph and store in cache unconditionally.  If the pool
is full, flushes the entire cache first.

### GC-FLUSH

```forth
GC-FLUSH  ( -- )
```

Invalidate all cache entries and reset the bitmap pool.

---

## Cache Internals

### Hash Function

```
slot = (glyph_id × 2654435761 XOR size) AND (GC-SLOTS − 1)
```

Knuth multiplicative hash on the glyph ID, mixed with the pixel size.

### Entry Structure

Each of the 256 slots stores 6 cells:

| Field | Description |
|---|---|
| `GID` | Glyph ID |
| `SIZE` | Pixel size |
| `W` | Bitmap width |
| `H` | Bitmap height |
| `BMP` | Pointer to bitmap data in pool |
| `VALID` | 1 = occupied, 0 = empty |

### Pool

Bitmap data is stored in a contiguous 256 KiB region.  New bitmaps
are appended at `_GC-POOL-PTR`.  When `_GC-POOL-ALLOC` fails
(insufficient space), `GC-STORE` calls `GC-FLUSH` and retries.

---

## Quick Reference

```
GC-GET      ( glyph-id size -- bmp-addr w h | 0 0 0 )
GC-LOOKUP   ( glyph-id size -- bmp-addr w h | 0 0 0 )
GC-STORE    ( glyph-id size -- bmp-addr w h | 0 0 0 )
GC-FLUSH    ( -- )
GC-SLOTS    ( -- 256 )
```

### Typical Usage

```forth
REQUIRE cache.f

\ After parsing TTF tables...
0x41 TTF-CMAP-LOOKUP   ( -- glyph-id )
16                     ( glyph-id 16 )
GC-GET                 ( -- bmp-addr w h | 0 0 0 )
\ bmp-addr points to a 16×16 monochrome bitmap
```

---

## Known Limitations

1. **Direct-mapped collisions** — Two glyphs hashing to the same
   slot will thrash.  Typical Latin text has low collision rates
   with 256 slots.
2. **No partial eviction** — Pool exhaustion flushes the entire
   cache, which may cause a brief stall.
3. **Square bitmaps** — Width = height = pixel_size.  Glyphs wider
   than tall waste some memory.
4. **No size awareness** — All sizes share the same pool.  Mixed-size
   rendering may exhaust the pool faster.
